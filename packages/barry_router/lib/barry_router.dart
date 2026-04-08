library barry_router;

import 'package:barry_core/barry_core.dart';

enum ProcessingMode { local, cloud }

class RouteDecision {
  const RouteDecision({required this.mode, required this.reason, required this.audit});
  final ProcessingMode mode;
  final String reason;
  final Map<String, String> audit;
}

abstract interface class InferenceRouter {
  RouteDecision decide({required String utterance, required bool localLlmAvailable, required bool networkHealthy});
}

class RuleBasedInferenceRouter implements InferenceRouter {
  RuleBasedInferenceRouter({required this.telemetry});
  final TelemetryBus telemetry;

  @override
  RouteDecision decide({required String utterance, required bool localLlmAvailable, required bool networkHealthy}) {
    final isCommand = utterance.split(' ').length <= 8;
    final mode = (localLlmAvailable && isCommand) || !networkHealthy ? ProcessingMode.local : ProcessingMode.cloud;
    telemetry.emit(TelemetryEvent(TelemetryMetric.cloudRoundtripMs, mode == ProcessingMode.cloud ? 1 : 0));
    return RouteDecision(
      mode: mode,
      reason: mode == ProcessingMode.local ? 'fast_path_or_offline' : 'complex_or_network_ok',
      audit: {
        'utterance_length': '${utterance.length}',
        'local_available': '$localLlmAvailable',
        'network_healthy': '$networkHealthy',
      },
    );
  }
}
