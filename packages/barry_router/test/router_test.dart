import 'package:barry_core/barry_core.dart';
import 'package:barry_router/barry_router.dart';
import 'package:test/test.dart';

void main() {
  test('routes privacy sensitive utterance to local when possible', () {
    final router = RuleBasedInferenceRouter(telemetry: InMemoryTelemetryBus());
    final result = router.decide(
      RoutingContext(
        utterance: 'abrir contatos pessoais',
        capabilities: CapabilityProfile.empty.copyWith(hasLocalLlm: true, hasCloudQwen: true, hasLocalStt: true),
        networkHealthy: true,
        estimatedLatencyMs: 30,
        deviceThermalHigh: false,
        estimatedCloudCost: 0.01,
        privacySensitive: true,
        requiresTools: false,
        requiresLongMemory: false,
        minQuality: 0.4,
      ),
    );
    expect(result.inferenceMode, ProcessingMode.local);
  });

  test('routes complex long-memory query to cloud and layered memory', () {
    final router = RuleBasedInferenceRouter(telemetry: InMemoryTelemetryBus());
    final result = router.decide(
      RoutingContext(
        utterance: 'explique em detalhes o plano e recupere meu histórico completo de decisões',
        capabilities: CapabilityProfile.empty.copyWith(
          hasCloudQwen: true,
          hasVault: true,
          hasClaudeMem: true,
        ),
        networkHealthy: true,
        estimatedLatencyMs: 220,
        deviceThermalHigh: false,
        estimatedCloudCost: 0.04,
        privacySensitive: false,
        requiresTools: true,
        requiresLongMemory: true,
        minQuality: 0.95,
      ),
    );
    expect(result.inferenceMode, ProcessingMode.cloud);
    expect(result.memoryMode, MemoryMode.layeredCloud);
  });
}
