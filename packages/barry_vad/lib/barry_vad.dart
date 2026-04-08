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
  VadHysteresisController({required this.config, required this.telemetry, BarryVadNative? native})
      : _native = native ?? BarryVadNative();

  final VadConfig config;
  final TelemetryBus telemetry;
  final BarryVadNative _native;

  VadResult process(List<int> pcm16Mono16k) {
    final sw = Stopwatch()..start();
    final prob = _native.inferSpeechProbability(pcm16Mono16k);
    sw.stop();
    final detected = prob > 0.55;
    telemetry.emit(TelemetryEvent(TelemetryMetric.vadInferenceMs, sw.elapsedMicroseconds / 1000));
    return VadResult(voiceDetected: detected, speechRatio: prob);
  }
}
