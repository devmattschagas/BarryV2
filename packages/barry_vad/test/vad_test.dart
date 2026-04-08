import 'package:barry_core/barry_core.dart';
import 'package:barry_vad/barry_vad.dart';
import 'package:test/test.dart';

void main() {
  test('VAD heuristic fallback works when native disabled', () async {
    final controller = VadHysteresisController(
      config: const VadConfig(minSpeechMs: 20),
      telemetry: InMemoryTelemetryBus(),
      nativeEnabled: false,
    );

    final result = await controller.processAsync(List<int>.filled(320, 30));
    expect(result.fallbackUsed, isTrue);
    expect(result.voiceDetected, isTrue);
  });

  test('VAD handles silence safely', () async {
    final controller = VadHysteresisController(
      config: const VadConfig(minSpeechMs: 20),
      telemetry: InMemoryTelemetryBus(),
      nativeEnabled: false,
    );
    final result = await controller.processAsync(List<int>.filled(320, 0));
    expect(result.voiceDetected, isFalse);
  });
}
