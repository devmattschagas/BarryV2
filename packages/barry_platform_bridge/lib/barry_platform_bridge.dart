library barry_platform_bridge;

import 'package:flutter/services.dart';

abstract interface class LocalLlmEngine {
  Future<String> infer(String prompt);
}

abstract interface class LocalToolCallingEngine {
  Future<Map<String, Object?>> inferStructuredCall(String prompt);
}

abstract interface class LocalPromptFormatter {
  String format(String input);
}

abstract interface class LocalInferenceSession {
  Future<void> warmup();
  Future<void> close();
}

class PlatformLocalLlmEngine implements LocalLlmEngine {
  const PlatformLocalLlmEngine();
  static const _channel = MethodChannel('barry_platform_bridge/litert_lm');

  @override
  Future<String> infer(String prompt) async {
    final output = await _channel.invokeMethod<String>('infer', {'prompt': prompt});
    return output ?? '';
  }
}

class DegradedModeController {
  bool degraded = false;
  void enable() => degraded = true;
}
