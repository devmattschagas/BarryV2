library barry_native_ffi;

import 'dart:ffi';
import 'dart:io';

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
  late final DynamicLibrary _lib;
  late final double Function(Pointer<Int16>, int) _infer;

  BarryVadNative() {
    _lib = Platform.isAndroid ? DynamicLibrary.open(NativeLibNames.vad) : DynamicLibrary.process();
    _infer = _lib
        .lookup<NativeFunction<Double Function(Pointer<Int16>, Int32)>>('barry_vad_infer')
        .asFunction();
  }

  double inferSpeechProbability(List<int> pcm16) {
    final ptr = calloc<Int16>(pcm16.length);
    for (var i = 0; i < pcm16.length; i++) {
      ptr[i] = pcm16[i];
    }
    final score = _infer(ptr, pcm16.length);
    calloc.free(ptr);
    return score;
  }
}

class ZeptoClawExecutor {
  late final DynamicLibrary _lib;
  late final int Function(Pointer<Utf8>, Pointer<Utf8>, int) _executeScript;

  ZeptoClawExecutor() {
    _lib = Platform.isAndroid ? DynamicLibrary.open(NativeLibNames.zeptoClaw) : DynamicLibrary.process();
    _executeScript = _lib
        .lookup<NativeFunction<Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Int32)>>('zeptoclaw_execute_script')
        .asFunction();
  }

  int executeScript({required String command, required String payloadJson, int timeoutMs = 2000}) {
    final allowed = {'status.read', 'sensors.scan', 'nav.lock'};
    if (!allowed.contains(command)) {
      throw ArgumentError('command_not_allowlisted');
    }
    final cmd = command.toNativeUtf8();
    final payload = payloadJson.toNativeUtf8();
    final result = _executeScript(cmd, payload, timeoutMs);
    calloc.free(cmd);
    calloc.free(payload);
    return result;
  }
}
