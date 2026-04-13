package com.barry.platform_bridge

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.BufferedReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL

class BarryPlatformBridgePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
  private lateinit var channel: MethodChannel

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(binding.binaryMessenger, "barry_platform_bridge/litert_lm")
    channel.setMethodCallHandler(this)
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "infer" -> {
        val prompt = call.argument<String>("prompt")?.trim().orEmpty()
        val model = call.argument<String>("model")?.trim().orEmpty()
        val endpoint = call.argument<String>("endpoint")?.trim().orEmpty().ifEmpty {
          "http://127.0.0.1:11434/api/generate"
        }
        val timeoutMs = call.argument<Int>("timeoutMs") ?: 45000
        if (prompt.isEmpty()) {
          result.error("invalid_prompt", "Prompt vazio.", null)
          return
        }
        try {
          val generated = invokeLocalRuntime(prompt = prompt, model = model, endpoint = endpoint, timeoutMs = timeoutMs)
          if (generated.isBlank()) {
            result.error("local_llm_unavailable", "Runtime local respondeu sem conteúdo.", mapOf("model" to model, "endpoint" to endpoint))
            return
          }
          result.success(generated)
        } catch (e: Exception) {
          result.error("local_llm_unavailable", "Falha na inferência local: ${e.message}", mapOf("model" to model, "endpoint" to endpoint))
        }
      }
      else -> result.notImplemented()
    }
  }

  private fun invokeLocalRuntime(prompt: String, model: String, endpoint: String, timeoutMs: Int): String {
    val connection = (URL(endpoint).openConnection() as HttpURLConnection).apply {
      requestMethod = "POST"
      connectTimeout = timeoutMs
      readTimeout = timeoutMs
      doOutput = true
      setRequestProperty("Content-Type", "application/json")
    }
    try {
      val payload = JSONObject()
        .put("model", model.ifBlank { "gemma-4b-it-q4_0" })
        .put("prompt", prompt)
        .put("stream", false)
      OutputStreamWriter(connection.outputStream).use { writer ->
        writer.write(payload.toString())
      }

      val statusCode = connection.responseCode
      val stream = if (statusCode in 200..299) connection.inputStream else (connection.errorStream ?: connection.inputStream)
      val body = BufferedReader(stream.reader()).use { it.readText() }
      if (statusCode !in 200..299) {
        throw IllegalStateException("HTTP $statusCode: $body")
      }
      val decoded = JSONObject(body)
      return decoded.optString("response").ifBlank {
        decoded.optString("text").ifBlank {
          decoded.optJSONArray("choices")
            ?.optJSONObject(0)
            ?.optJSONObject("message")
            ?.optString("content")
            .orEmpty()
        }
      }
    } finally {
      connection.disconnect()
    }
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
  }
}
