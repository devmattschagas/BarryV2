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

    final augmentedPrompt = '[model:${settings.localModel}] $prompt';
    final output = await _engine.infer(augmentedPrompt);
    if (output.trim().isEmpty) {
      throw RuntimeFailure(
        RuntimeErrorType.localUnavailable,
        'Inferência local indisponível no bridge LiteRT para ${settings.localModel}.',
      );
    }
    return output.trim();
  }
}
