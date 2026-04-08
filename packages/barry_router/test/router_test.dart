import 'package:barry_core/barry_core.dart';
import 'package:barry_router/barry_router.dart';
import 'package:test/test.dart';

void main() {
  test('routes short command to local', () {
    final router = RuleBasedInferenceRouter(telemetry: InMemoryTelemetryBus());
    final result = router.decide(utterance: 'open map', localLlmAvailable: true, networkHealthy: true);
    expect(result.mode, ProcessingMode.local);
  });

  test('routes question to cloud even when short', () {
    final router = RuleBasedInferenceRouter(telemetry: InMemoryTelemetryBus());
    final result = router.decide(utterance: 'why is the sky blue?', localLlmAvailable: true, networkHealthy: true);
    expect(result.mode, ProcessingMode.cloud);
  });
}
