library barry_platform_bridge;

import 'package:flutter/services.dart';

abstract interface class LocalLlmEngine {
  Future<String> infer(String prompt, {String? model});
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
  Future<String> infer(String prompt, {String? model}) async {
    final output = await _channel.invokeMethod<String>('infer', {
      'prompt': prompt,
      if (model != null) 'model': model,
    });
    return output ?? '';
  }
}

class DegradedModeController {
  bool degraded = false;
  final Set<String> degradedCapabilities = <String>{};

  void enable({String reason = 'unknown'}) {
    degraded = true;
    degradedCapabilities.add(reason);
  }

  void disable() {
    degraded = false;
    degradedCapabilities.clear();
  }
}
