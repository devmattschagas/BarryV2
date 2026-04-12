import 'package:barry_platform_bridge/barry_platform_bridge.dart';

import '../models.dart';
import 'errors.dart';

class LocalAiAdapter {
  LocalAiAdapter({LocalLlmEngine? engine}) : _engine = engine ?? const PlatformLocalLlmEngine();

  final LocalLlmEngine _engine;

  Future<String> infer({required String prompt, required AssistantSettings settings}) async {
    if (!settings.localModelEnabled) {
      throw RuntimeFailure(RuntimeErrorType.localUnavailable, 'IA local desabilitada nas configurações.');
    }

    final output = await _engine.infer(prompt);
    final normalized = output.trim();
    if (normalized.isEmpty) {
      throw RuntimeFailure(
        RuntimeErrorType.localUnavailable,
        'Inferência local indisponível no bridge LiteRT para ${settings.localModel}.',
      );
    }

    final looksMock =
        normalized.toLowerCase().contains('litert-lm-bridge-mock') ||
        normalized.toLowerCase().contains('[model:') ||
        normalized.toLowerCase().contains('mock');
    if (looksMock) {
      throw RuntimeFailure(
        RuntimeErrorType.localUnavailable,
        'Inferência local retornou payload de mock; fallback necessário.',
      );
    }
    return normalized;
  }
}
