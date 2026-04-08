library barry_router;

import 'package:barry_core/barry_core.dart';

enum ProcessingMode { local, cloud, hybrid }

enum MemoryMode { localOnly, vault, layeredCloud }

class RoutingContext {
  const RoutingContext({
    required this.utterance,
    required this.capabilities,
    required this.networkHealthy,
    required this.estimatedLatencyMs,
    required this.deviceThermalHigh,
    required this.estimatedCloudCost,
    required this.privacySensitive,
    required this.requiresTools,
    required this.requiresLongMemory,
    required this.minQuality,
  });

  final String utterance;
  final CapabilityProfile capabilities;
  final bool networkHealthy;
  final int estimatedLatencyMs;
  final bool deviceThermalHigh;
  final double estimatedCloudCost;
  final bool privacySensitive;
  final bool requiresTools;
  final bool requiresLongMemory;
  final double minQuality;
}

class RouteDecision {
  const RouteDecision({
    required this.inferenceMode,
    required this.sttMode,
    required this.ttsMode,
    required this.memoryMode,
    required this.reason,
    required this.audit,
  });

  final ProcessingMode inferenceMode;
  final ProcessingMode sttMode;
  final ProcessingMode ttsMode;
  final MemoryMode memoryMode;
  final String reason;
  final Map<String, String> audit;
}

abstract interface class InferenceRouter {
  RouteDecision decide(RoutingContext context);
}

class RuleBasedInferenceRouter implements InferenceRouter {
  RuleBasedInferenceRouter({required this.telemetry});
  final TelemetryBus telemetry;

  static final RegExp _tokenPattern = RegExp(r"[\\p{L}\\p{N}']+", unicode: true);

  @override
  RouteDecision decide(RoutingContext context) {
    final tokens = _tokenPattern.allMatches(context.utterance.toLowerCase()).map((m) => m.group(0)!).toList();
    final isComplex = tokens.length > 14 || context.utterance.contains('?') || context.requiresLongMemory;

    final canUseCloud = context.networkHealthy && context.capabilities.hasCloudQwen;
    final canUseLocal = context.capabilities.hasLocalLlm && !context.deviceThermalHigh;

    final preferLocalByPrivacy = context.privacySensitive && canUseLocal;
    final preferCloudByQuality = context.minQuality >= 0.85 && canUseCloud;

    final inferenceMode = preferLocalByPrivacy
        ? ProcessingMode.local
        : (isComplex || context.requiresTools || preferCloudByQuality || context.estimatedLatencyMs > 450)
            ? (canUseCloud ? ProcessingMode.cloud : ProcessingMode.local)
            : (canUseLocal ? ProcessingMode.local : ProcessingMode.cloud);

    final sttMode = context.capabilities.hasLocalStt
        ? ProcessingMode.local
        : (context.capabilities.hasRemoteStt ? ProcessingMode.cloud : ProcessingMode.local);

    final ttsMode = context.capabilities.hasLocalTts
        ? ProcessingMode.local
        : (context.capabilities.hasRemoteTts ? ProcessingMode.cloud : ProcessingMode.local);

    final memoryMode = context.requiresLongMemory && context.capabilities.hasVault
        ? (context.capabilities.hasClaudeMem || context.capabilities.hasPaul ? MemoryMode.layeredCloud : MemoryMode.vault)
        : MemoryMode.localOnly;

    telemetry.emit(TelemetryEvent(TelemetryMetric.cloudRoundtripMs, inferenceMode == ProcessingMode.cloud ? 1 : 0));

    return RouteDecision(
      inferenceMode: inferenceMode,
      sttMode: sttMode,
      ttsMode: ttsMode,
      memoryMode: memoryMode,
      reason: 'hybrid_capability_routing',
      audit: {
        'token_count': '${tokens.length}',
        'is_complex': '$isComplex',
        'network_healthy': '${context.networkHealthy}',
        'can_use_cloud': '$canUseCloud',
        'can_use_local': '$canUseLocal',
        'privacy_sensitive': '${context.privacySensitive}',
        'requires_tools': '${context.requiresTools}',
        'requires_long_memory': '${context.requiresLongMemory}',
        'estimated_cloud_cost': '${context.estimatedCloudCost}',
      },
    );
  }
}
