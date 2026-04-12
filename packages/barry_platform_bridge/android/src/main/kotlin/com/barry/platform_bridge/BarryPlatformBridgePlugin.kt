package com.barry.platform_bridge

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

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
        if (prompt.isEmpty()) {
          result.error("invalid_prompt", "Prompt vazio.", null)
          return
        }

        // Production requires a real on-device LLM runtime (Gemma mobile variant).
        // This plugin intentionally never emits mock payloads; if runtime isn't wired,
        // it surfaces explicit unavailability so Flutter can route fallback correctly.
        result.error(
          "local_llm_unavailable",
          "Runtime LLM local não inicializado. Configure Gemma mobile (LiteRT/MediaPipe) no app Android.",
          mapOf("model" to model)
        )
      }
      else -> result.notImplemented()
    }
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
  }
}
