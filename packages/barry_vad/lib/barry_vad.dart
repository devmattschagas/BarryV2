library barry_vad;

import 'dart:math' as math;

import 'package:barry_core/barry_core.dart';
import 'package:barry_native_ffi/barry_native_ffi.dart';

class VadConfig {
  const VadConfig({
    this.preRollMs = 200,
    this.minSpeechMs = 250,
    this.minSilenceMs = 450,
    this.cooldownMs = 200,
    this.heuristicRmsThreshold = 12,
  });
  final int preRollMs;
  final int minSpeechMs;
  final int minSilenceMs;
  final int cooldownMs;
  final double heuristicRmsThreshold;
}

class VadResult {
  const VadResult({required this.voiceDetected, required this.speechRatio, required this.fallbackUsed});
  final bool voiceDetected;
  final double speechRatio;
  final bool fallbackUsed;
}

class VadHysteresisController {
  VadHysteresisController({
    required this.config,
    required this.telemetry,
    this.nativeEnabled = true,
    BarryVadNative? native,
  }) : _native = nativeEnabled ? (native ?? BarryVadNative()) : null;

  final VadConfig config;
  final TelemetryBus telemetry;
  final BarryVadNative? _native;
  final bool nativeEnabled;

  int _speechMs = 0;
  int _silenceMs = 0;
  int _cooldownLeftMs = 0;

  VadResult process(List<int> pcm16Mono16k, {int frameMs = 20}) {
    final prob = _safeNativeInferenceSync(pcm16Mono16k) ?? _heuristicSpeechProbability(pcm16Mono16k);
    return _applyStateTransition(
      prob: prob,
      frameMs: frameMs,
      inferenceMs: 0,
      fallbackUsed: _safeNativeInferenceSync(pcm16Mono16k) == null,
    );
  }

  Future<VadResult> processAsync(List<int> pcm16Mono16k, {int frameMs = 20}) async {
    final sw = Stopwatch()..start();
    double prob;
    var fallback = false;
    try {
      final nativeProb = await _safeNativeInferenceAsync(pcm16Mono16k);
      if (nativeProb == null) {
        fallback = true;
        prob = _heuristicSpeechProbability(pcm16Mono16k);
      } else {
        prob = nativeProb;
      }
    } catch (_) {
      fallback = true;
      prob = _heuristicSpeechProbability(pcm16Mono16k);
    }
    sw.stop();
    return _applyStateTransition(
      prob: prob,
      frameMs: frameMs,
      inferenceMs: sw.elapsedMicroseconds / 1000,
      fallbackUsed: fallback,
    );
  }

  double? _safeNativeInferenceSync(List<int> pcm16Mono16k) {
    if (!nativeEnabled) return null;
    try {
      return _native?.inferSpeechProbability(pcm16Mono16k);
    } catch (_) {
      return null;
    }
  }

  Future<double?> _safeNativeInferenceAsync(List<int> pcm16Mono16k) async {
    if (!nativeEnabled) return null;
    try {
      return await _native?.inferSpeechProbabilityAsync(pcm16Mono16k);
    } catch (_) {
      return null;
    }
  }

  double _heuristicSpeechProbability(List<int> pcm16Mono16k) {
    if (pcm16Mono16k.isEmpty) return 0;
    var sumSquares = 0.0;
    for (final sample in pcm16Mono16k) {
      sumSquares += sample * sample;
    }
    final rms = math.sqrt(sumSquares / pcm16Mono16k.length);
    final normalized = (rms / config.heuristicRmsThreshold).clamp(0, 1).toDouble();
    return normalized;
  }

  VadResult _applyStateTransition({
    required double prob,
    required int frameMs,
    required num inferenceMs,
    required bool fallbackUsed,
  }) {
    if (_cooldownLeftMs > 0) {
      _cooldownLeftMs -= frameMs;
      telemetry.emit(TelemetryEvent(TelemetryMetric.vadInferenceMs, inferenceMs, tags: {'fallback': '$fallbackUsed'}));
      return VadResult(voiceDetected: false, speechRatio: 0.0, fallbackUsed: fallbackUsed);
    }

    if (prob > 0.55) {
      _speechMs += frameMs;
      _silenceMs = 0;
    } else {
      _silenceMs += frameMs;
      if (_silenceMs >= config.minSilenceMs && _speechMs > 0) {
        _cooldownLeftMs = config.cooldownMs;
        _speechMs = 0;
      }
    }

    final detected = _speechMs >= config.minSpeechMs;
    telemetry.emit(TelemetryEvent(TelemetryMetric.vadInferenceMs, inferenceMs, tags: {'fallback': '$fallbackUsed'}));
    return VadResult(voiceDetected: detected, speechRatio: prob, fallbackUsed: fallbackUsed);
  }
}
