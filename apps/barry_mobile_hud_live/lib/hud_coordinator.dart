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
  Timer? _ringTimer;
  bool _started = false;
  bool _networkHealthy = true;
  Future<void> _frameQueue = Future<void>.value();

  @override
  final ValueNotifier<HudUiState> state = ValueNotifier(HudUiState.idle);

  Future<void> startListening(Stream<List<int>> pcm16Frames, {required bool networkHealthy}) async {
    await _bootstrapIfNeeded(networkHealthy: networkHealthy);
    _audioSub = pcm16Frames.listen(
      (frame) {
        _frameQueue = _frameQueue.then((_) => _processAudioFrame(frame));
      },
      onError: (_) => _enterDegradedMode(),
      cancelOnError: true,
    );
  }

  Future<void> startListeningFromRingBuffer(
    PcmRingBuffer ringBuffer, {
    required bool networkHealthy,
    Duration pollingInterval = const Duration(milliseconds: 20),
  }) async {
    await _bootstrapIfNeeded(networkHealthy: networkHealthy);
    _ringTimer = Timer.periodic(pollingInterval, (_) {
      final frames = ringBuffer.drain();
      for (final frame in frames) {
        _frameQueue = _frameQueue.then((_) => _processAudioFrame(frame.samples));
      }
    });
  }

  Future<void> _bootstrapIfNeeded({required bool networkHealthy}) async {
    if (_started) {
      return;
    }
    _started = true;
    _networkHealthy = networkHealthy;
    state.value = HudUiState.listening;

    _speechFrames = StreamController<List<int>>(sync: true);
    _transcriptSub = transcriptionEngine.streamTranscription(_speechFrames!.stream).listen(
      (chunk) {
        _frameQueue = _frameQueue.then((_) => _onTranscript(chunk));
      },
      onError: (_) => _enterDegradedMode(),
      onDone: () {
        if (state.value != HudUiState.degradedMode) {
          state.value = HudUiState.idle;
        }
      },
      cancelOnError: true,
    );
  }

  Future<void> _processAudioFrame(List<int> frame) async {
    final vadResult = await vadController.processAsync(frame);
    if (!vadResult.voiceDetected) {
      return;
    }

    if (state.value == HudUiState.listening || state.value == HudUiState.idle) {
      state.value = HudUiState.transcribing;
    }
    _speechFrames?.add(frame);
  }

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
      await memory.put(
        MemoryItem(id: DateTime.now().microsecondsSinceEpoch.toString(), text: response, embedding: const []),
      );
    } else {
      state.value = HudUiState.cloudProcessing;
      await memory.put(
        MemoryItem(id: DateTime.now().microsecondsSinceEpoch.toString(), text: chunk.text, embedding: const []),
      );
    }

    state.value = HudUiState.responding;
  }

  void _enterDegradedMode() {
    modeController.enable();
    state.value = HudUiState.degradedMode;
  }

  Future<void> stopListening() async {
    _ringTimer?.cancel();
    _ringTimer = null;
    await _audioSub?.cancel();
    await _transcriptSub?.cancel();
    await _speechFrames?.close();
    await _frameQueue;

    _audioSub = null;
    _transcriptSub = null;
    _speechFrames = null;
    _started = false;
    _frameQueue = Future<void>.value();
    if (state.value != HudUiState.degradedMode) {
      state.value = HudUiState.idle;
    }
  }
}
