library barry_native_ffi;

import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:barry_core/barry_core.dart';
import 'package:ffi/ffi.dart';

class NativeLibNames {
  static const zeptoClaw = 'libzeptoclaw.so';
  static const vad = 'libbarry_vad_native.so';
  static const onnx = 'libonnxruntime.so';
  static const whisperWorker = 'libbarry_whisper_worker.so';

  static const requiredForStartup = [zeptoClaw, vad, onnx, whisperWorker];
}

class NativeStartupReport {
  const NativeStartupReport({required this.loaded, required this.failed});
  final List<String> loaded;
  final Map<String, String> failed;

  bool get ok => failed.isEmpty;
}

class NativeLibraryLoader {
  const NativeLibraryLoader();

  NativeStartupReport verify() {
    final loaded = <String>[];
    final failed = <String, String>{};
    for (final name in NativeLibNames.requiredForStartup) {
      try {
        DynamicLibrary.open(name);
        loaded.add(name);
      } catch (e) {
        failed[name] = '$e';
      }
    }
    return NativeStartupReport(loaded: loaded, failed: failed);
  }
}

class BarryVadNative {
  late final double Function(Pointer<Int16>, int) _infer;

  BarryVadNative() {
    try {
      final lib = Platform.isAndroid ? DynamicLibrary.open(NativeLibNames.vad) : DynamicLibrary.process();
      _infer = lib.lookup<NativeFunction<Double Function(Pointer<Int16>, Int32)>>('barry_vad_infer').asFunction();
    } catch (_) {
      _infer = (_, __) => 0.0;
    }
  }

  double inferSpeechProbability(List<int> pcm16) {
    final ptr = calloc<Int16>(pcm16.length);
    try {
      final view = ptr.asTypedList(pcm16.length);
      view.setAll(0, pcm16);
      return _infer(ptr, pcm16.length);
    } finally {
      calloc.free(ptr);
    }
  }

  Future<double> inferSpeechProbabilityAsync(List<int> pcm16) async {
    final request = _VadInferRequest(samples: List<int>.from(pcm16, growable: false), useProcessLibrary: !Platform.isAndroid);
    try {
      return await Isolate.run(() => _inferVadInIsolate(request));
    } catch (_) {
      return 0.0;
    }
  }
}

class _VadInferRequest {
  const _VadInferRequest({required this.samples, required this.useProcessLibrary});
  final List<int> samples;
  final bool useProcessLibrary;
}

double _inferVadInIsolate(_VadInferRequest request) {
  final lib = request.useProcessLibrary ? DynamicLibrary.process() : DynamicLibrary.open(NativeLibNames.vad);
  final infer = lib
      .lookup<NativeFunction<Double Function(Pointer<Int16>, Int32)>>('barry_vad_infer')
      .asFunction<double Function(Pointer<Int16>, int)>();
  final ptr = calloc<Int16>(request.samples.length);
  try {
    final view = ptr.asTypedList(request.samples.length);
    view.setAll(0, request.samples);
    return infer(ptr, request.samples.length);
  } finally {
    calloc.free(ptr);
  }
}

class ZeptoClawExecutor {
  late final int Function(Pointer<Utf8>, Pointer<Utf8>, int) _executeScript;

  ZeptoClawExecutor() {
    try {
      final lib = Platform.isAndroid ? DynamicLibrary.open(NativeLibNames.zeptoClaw) : DynamicLibrary.process();
      _executeScript = lib
          .lookup<NativeFunction<Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Int32)>>('zeptoclaw_execute_script')
          .asFunction();
    } catch (_) {
      _executeScript = (_, __, ___) => -1;
    }
  }

  int executeScript({required String command, required String payloadJson, int timeoutMs = 2000}) {
    if (!CommandPolicies.zeptoClawCloud.canExecute(command)) {
      throw ArgumentError('command_not_allowlisted');
    }
    final cmd = command.toNativeUtf8();
    final payload = payloadJson.toNativeUtf8();
    try {
      return _executeScript(cmd, payload, timeoutMs);
    } finally {
      calloc.free(cmd);
      calloc.free(payload);
    }
  }

  Future<int> executeScriptAsync({required String command, required String payloadJson, int timeoutMs = 2000}) {
    final request = _ScriptRequest(
      command: command,
      payloadJson: payloadJson,
      timeoutMs: timeoutMs,
      useProcessLibrary: !Platform.isAndroid,
    );
    return Isolate.run(() => _executeScriptInIsolate(request));
  }
}

class _ScriptRequest {
  const _ScriptRequest({
    required this.command,
    required this.payloadJson,
    required this.timeoutMs,
    required this.useProcessLibrary,
  });

  final String command;
  final String payloadJson;
  final int timeoutMs;
  final bool useProcessLibrary;
}

int _executeScriptInIsolate(_ScriptRequest request) {
  if (!CommandPolicies.zeptoClawCloud.canExecute(request.command)) {
    throw ArgumentError('command_not_allowlisted');
  }

  final lib = request.useProcessLibrary ? DynamicLibrary.process() : DynamicLibrary.open(NativeLibNames.zeptoClaw);
  final execute = lib
      .lookup<NativeFunction<Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Int32)>>('zeptoclaw_execute_script')
      .asFunction<int Function(Pointer<Utf8>, Pointer<Utf8>, int)>();

  final cmd = request.command.toNativeUtf8();
  final payload = request.payloadJson.toNativeUtf8();
  try {
    return execute(cmd, payload, request.timeoutMs);
  } finally {
    calloc.free(cmd);
    calloc.free(payload);
  }
}
