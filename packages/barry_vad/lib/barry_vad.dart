library barry_vad;

import 'package:barry_core/barry_core.dart';
import 'package:barry_native_ffi/barry_native_ffi.dart';

class VadConfig {
  const VadConfig({
    this.preRollMs = 200,
    this.minSpeechMs = 250,
    this.minSilenceMs = 450,
    this.cooldownMs = 200,
  });
  final int preRollMs;
  final int minSpeechMs;
  final int minSilenceMs;
  final int cooldownMs;
}

class VadResult {
  const VadResult({required this.voiceDetected, required this.speechRatio});
  final bool voiceDetected;
  final double speechRatio;
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
    final prob = nativeEnabled ? (_native?.inferSpeechProbability(pcm16Mono16k) ?? 0.0) : 0.0;
    return _applyStateTransition(prob: prob, frameMs: frameMs, inferenceMs: 0);
  }

  Future<VadResult> processAsync(List<int> pcm16Mono16k, {int frameMs = 20}) async {
    final sw = Stopwatch()..start();
    final prob = nativeEnabled ? await (_native?.inferSpeechProbabilityAsync(pcm16Mono16k) ?? Future.value(0.0)) : 0.0;
    sw.stop();
    return _applyStateTransition(prob: prob, frameMs: frameMs, inferenceMs: sw.elapsedMicroseconds / 1000);
  }

  VadResult _applyStateTransition({required double prob, required int frameMs, required num inferenceMs}) {
    if (_cooldownLeftMs > 0) {
      _cooldownLeftMs -= frameMs;
      telemetry.emit(TelemetryEvent(TelemetryMetric.vadInferenceMs, inferenceMs));
      return const VadResult(voiceDetected: false, speechRatio: 0.0);
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
    telemetry.emit(TelemetryEvent(TelemetryMetric.vadInferenceMs, inferenceMs));
    return VadResult(voiceDetected: detected, speechRatio: prob);
  }
}
