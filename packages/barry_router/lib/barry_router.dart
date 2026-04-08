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

  static final RegExp _tokenPattern = RegExp(r"[\\p{L}\\p{N}']+", unicode: true);
  static const Set<String> _commandKeywords = {
    'open',
    'close',
    'start',
    'stop',
    'call',
    'turn',
    'ligue',
    'desligue',
    'abrir',
    'fechar',
    'mostrar',
    'hide',
  };

  @override
  RouteDecision decide({required String utterance, required bool localLlmAvailable, required bool networkHealthy}) {
    final cleaned = utterance.trim().toLowerCase();
    final tokens = _tokenPattern.allMatches(cleaned).map((m) => m.group(0)!).toList(growable: false);
    final tokenCount = tokens.length;
    final isQuestion = cleaned.contains('?') ||
        tokens.any((t) => {'how', 'why', 'what', 'quando', 'como', 'por', 'porque', 'qual'}.contains(t));
    final hasCommandVerb = tokens.any(_commandKeywords.contains);
    final hasComplexityMarker = cleaned.contains(':') || cleaned.contains(';') || tokenCount > 14;

    final likelyCommand = hasCommandVerb && tokenCount <= 14 && !isQuestion;
    final mode = !networkHealthy
        ? ProcessingMode.local
        : (localLlmAvailable && likelyCommand && !hasComplexityMarker)
            ? ProcessingMode.local
            : ProcessingMode.cloud;

    telemetry.emit(TelemetryEvent(TelemetryMetric.cloudRoundtripMs, mode == ProcessingMode.cloud ? 1 : 0));
    return RouteDecision(
      mode: mode,
      reason: mode == ProcessingMode.local ? 'offline_or_low_latency_command' : 'cloud_for_complex_or_non_command',
      audit: {
        'token_count': '$tokenCount',
        'is_question': '$isQuestion',
        'has_command_verb': '$hasCommandVerb',
        'local_available': '$localLlmAvailable',
        'network_healthy': '$networkHealthy',
      },
    );
  }
}
