import 'dart:async';

import 'package:barry_core/barry_core.dart';
import 'package:barry_livekit/barry_livekit.dart';
import 'package:barry_memory/barry_memory.dart';
import 'package:barry_platform_bridge/barry_platform_bridge.dart';
import 'package:barry_router/barry_router.dart';
import 'package:barry_stt/barry_stt.dart';
import 'package:barry_ui_hud/barry_ui_hud.dart';
import 'package:barry_vad/barry_vad.dart';
import 'package:barry_vision/barry_vision.dart';
import 'package:flutter/foundation.dart';

class HudCoordinator implements HudStateSource {
  HudCoordinator({
    required this.telemetry,
    required this.router,
    required this.transcriptionEngine,
    required this.vadController,
    required this.livekit,
    required this.memory,
    required this.visionGateway,
    required this.localLlmEngine,
    required this.modeController,
  });

  final TelemetryBus telemetry;
  final InferenceRouter router;
  final TranscriptionEngine transcriptionEngine;
  final VadHysteresisController vadController;
  final LiveKitSessionManager livekit;
  final MemoryStore memory;
  final BarryVisionGateway visionGateway;
  final LocalLlmEngine localLlmEngine;
  final DegradedModeController modeController;

  StreamSubscription<List<int>>? _audioSub;
  StreamSubscription<TranscriptChunk>? _transcriptSub;
  StreamController<List<int>>? _speechFrames;
  bool _started = false;

  @override
  final ValueNotifier<HudUiState> state = ValueNotifier(HudUiState.idle);

  Future<void> startListening(Stream<List<int>> pcm16Frames, {required bool networkHealthy}) async {
    if (_started) {
      return;
    }
    _started = true;
    state.value = HudUiState.listening;

    _speechFrames = StreamController<List<int>>(sync: true);
    _transcriptSub = transcriptionEngine.streamTranscription(_speechFrames!.stream).listen(
      _onTranscript,
      onError: (_) => _enterDegradedMode(),
      onDone: () {
        if (state.value != HudUiState.degradedMode) {
          state.value = HudUiState.idle;
        }
      },
    );

    _audioSub = pcm16Frames.listen(
      (frame) async {
        final vadResult = await vadController.processAsync(frame);
        if (!vadResult.voiceDetected) {
          return;
        }
        if (state.value == HudUiState.listening || state.value == HudUiState.idle) {
          state.value = HudUiState.transcribing;
        }
        _speechFrames?.add(frame);
      },
      onError: (_) => _enterDegradedMode(),
      onDone: () async {
        await _speechFrames?.close();
      },
      cancelOnError: true,
    );

    // Keep the routing decision context available when transcript chunks arrive.
    _networkHealthy = networkHealthy;
  }

  bool _networkHealthy = true;

  Future<void> _onTranscript(TranscriptChunk chunk) async {
    if (chunk.text.trim().isEmpty) {
      return;
    }
    if (!chunk.isFinal) {
      state.value = HudUiState.transcribing;
      return;
    }

    final decision = router.decide(
      utterance: chunk.text,
      localLlmAvailable: !modeController.degraded,
      networkHealthy: _networkHealthy,
    );

    if (decision.mode == ProcessingMode.local) {
      state.value = HudUiState.localProcessing;
      final response = await localLlmEngine.infer(chunk.text);
      await memory.put(MemoryItem(id: DateTime.now().microsecondsSinceEpoch.toString(), text: response, embedding: const []));
    } else {
      state.value = HudUiState.cloudProcessing;
      await memory.put(MemoryItem(id: DateTime.now().microsecondsSinceEpoch.toString(), text: chunk.text, embedding: const []));
    }

    state.value = HudUiState.responding;
  }

  void _enterDegradedMode() {
    modeController.enable();
    state.value = HudUiState.degradedMode;
  }

  Future<void> stopListening() async {
    await _audioSub?.cancel();
    await _transcriptSub?.cancel();
    await _speechFrames?.close();
    _audioSub = null;
    _transcriptSub = null;
    _speechFrames = null;
    _started = false;
    if (state.value != HudUiState.degradedMode) {
      state.value = HudUiState.idle;
    }
  }
}
