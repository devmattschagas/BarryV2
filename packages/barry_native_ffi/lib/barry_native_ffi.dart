library barry_native_ffi;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:barry_core/barry_core.dart';
import 'package:ffi/ffi.dart';

class NativeLibNames {
  static const zeptoClaw = 'libzeptoclaw.so';
  static const vad = 'libbarry_vad_native.so';
  static const whisperWorker = 'libbarry_whisper_worker.so';

  static const requiredForStartup = [zeptoClaw, vad, whisperWorker];
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

class ZeptoClawResult {
  const ZeptoClawResult({required this.command, required this.exitCode, required this.payload});

  final String command;
  final int exitCode;
  final Map<String, Object?> payload;

  bool get ok => exitCode == 0;
}

class ZeptoClawExecutor {
  late final int Function(Pointer<Utf8>, Pointer<Utf8>, int) _executeScript;
  late final int Function() _healthCheck;
  late final int Function(Pointer<Utf8>, int) _listCapabilities;
  late final int Function(Pointer<Utf8>, int) _getDeviceState;

  ZeptoClawExecutor() {
    try {
      final lib = Platform.isAndroid ? DynamicLibrary.open(NativeLibNames.zeptoClaw) : DynamicLibrary.process();
      _executeScript = lib
          .lookup<NativeFunction<Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Int32)>>('zeptoclaw_execute_script')
          .asFunction();
      _healthCheck = lib.lookup<NativeFunction<Int32 Function()>>('zeptoclaw_health_check').asFunction();
      _listCapabilities = lib
          .lookup<NativeFunction<Int32 Function(Pointer<Utf8>, Int32)>>('zeptoclaw_list_capabilities')
          .asFunction();
      _getDeviceState = lib
          .lookup<NativeFunction<Int32 Function(Pointer<Utf8>, Int32)>>('zeptoclaw_get_device_state')
          .asFunction();
    } catch (_) {
      _executeScript = (_, __, ___) => -1;
      _healthCheck = () => 0;
      _listCapabilities = (_, __) => -1;
      _getDeviceState = (_, __) => -1;
    }
  }

  bool get isHealthy {
    if (_healthCheck() != 1) return false;
    final caps = _readNative(_listCapabilities);
    return caps.isNotEmpty;
  }

  ZeptoClawResult executeScript({required String command, required Map<String, Object?> payload, int timeoutMs = 2000}) {
    if (!CommandPolicies.zeptoClawCloud.canExecute(command)) {
      throw ArgumentError('command_not_allowlisted');
    }
    final cmd = command.toNativeUtf8();
    final payloadJson = jsonEncode(payload).toNativeUtf8();
    try {
      final code = _executeScript(cmd, payloadJson, timeoutMs);
      final capabilities = _readNative(_listCapabilities).split(',').where((e) => e.trim().isNotEmpty).toList(growable: false);
      final stateRaw = _readNative(_getDeviceState);
      final state = stateRaw.isEmpty ? const <String, Object?>{} : (jsonDecode(stateRaw) as Map<String, dynamic>);
      return ZeptoClawResult(
        command: command,
        exitCode: code,
        payload: {
          ...payload,
          'capabilities': capabilities,
          'device_state': state,
          'native_ok': code == 0,
        },
      );
    } finally {
      calloc.free(cmd);
      calloc.free(payloadJson);
    }
  }

  String _readNative(int Function(Pointer<Utf8>, int) reader) {
    final buf = calloc<Uint8>(2048).cast<Utf8>();
    try {
      final code = reader(buf, 2048);
      if (code != 0) return '';
      return buf.toDartString();
    } finally {
      calloc.free(buf);
    }
  }
}
