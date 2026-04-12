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

@Deprecated('Legacy coordinator: produção usa ConversationCoordinator.')
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
    required this.capabilities,
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
  final CapabilityProfile capabilities;

  StreamSubscription<List<int>>? _audioSub;
  StreamSubscription<TranscriptChunk>? _transcriptSub;
  StreamController<List<int>>? _speechFrames;
  Timer? _ringTimer;
  bool _started = false;
  bool _disposed = false;
  bool _networkHealthy = true;
  Future<void> _frameQueue = Future<void>.value();

  @override
  final ValueNotifier<HudUiState> state = ValueNotifier(HudUiState.idle);

  Future<void> startListening(Stream<List<int>> pcm16Frames, {required bool networkHealthy}) async {
    if (_disposed) return;
    await _bootstrapIfNeeded(networkHealthy: networkHealthy);
    _audioSub ??= pcm16Frames.listen(
      (frame) => _enqueueFrame(frame),
      onError: (_) => _enterDegradedMode('audio_stream_error'),
      cancelOnError: false,
    );
  }

  Future<void> startListeningFromRingBuffer(
    PcmRingBuffer ringBuffer, {
    required bool networkHealthy,
    Duration pollingInterval = const Duration(milliseconds: 20),
  }) async {
    if (_disposed) return;
    await _bootstrapIfNeeded(networkHealthy: networkHealthy);
    _ringTimer ??= Timer.periodic(pollingInterval, (_) {
      final frames = ringBuffer.drain();
      for (final frame in frames) {
        _enqueueFrame(frame.samples);
      }
    });
  }

  void _enqueueFrame(List<int> frame) {
    _frameQueue = _frameQueue.then((_) => _processAudioFrame(frame)).catchError((_) {
      _enterDegradedMode('frame_processing_error');
    });
  }

  Future<void> _bootstrapIfNeeded({required bool networkHealthy}) async {
    if (_started) return;
    _started = true;
    _networkHealthy = networkHealthy;
    state.value = HudUiState.listening;

    _speechFrames = StreamController<List<int>>(sync: true);
    _transcriptSub = transcriptionEngine.streamTranscription(_speechFrames!.stream).listen(
      (chunk) => _frameQueue = _frameQueue.then((_) => _onTranscript(chunk)),
      onError: (_) => _enterDegradedMode('stt_stream_error'),
      onDone: () {
        if (!_disposed && state.value != HudUiState.degradedMode) {
          state.value = HudUiState.idle;
        }
      },
      cancelOnError: false,
    );
  }

  Future<void> _processAudioFrame(List<int> frame) async {
    final vadResult = await vadController.processAsync(frame);
    if (!vadResult.voiceDetected) return;

    if (state.value == HudUiState.listening || state.value == HudUiState.idle) {
      state.value = HudUiState.transcribing;
    }
    _speechFrames?.add(frame);
  }

  Future<void> _onTranscript(TranscriptChunk chunk) async {
    if (chunk.text.trim().isEmpty) return;
    if (!chunk.isFinal) {
      state.value = HudUiState.transcribing;
      return;
    }

    final decision = router.decide(
      RoutingContext(
        utterance: chunk.text,
        capabilities: capabilities,
        networkHealthy: _networkHealthy,
        estimatedLatencyMs: 200,
        deviceThermalHigh: false,
        estimatedCloudCost: 0.02,
        privacySensitive: false,
        requiresTools: chunk.text.contains('tool') || chunk.text.contains('comando'),
        requiresLongMemory: chunk.text.contains('histórico') || chunk.text.contains('history'),
        minQuality: 0.8,
      ),
    );

    if (decision.inferenceMode == ProcessingMode.local && capabilities.hasLocalLlm && !modeController.degraded) {
      state.value = HudUiState.localProcessing;
      try {
        final response = await localLlmEngine.infer(chunk.text, model: null);
        await memory.put(MemoryItem(id: DateTime.now().microsecondsSinceEpoch.toString(), text: response, embedding: const []));
      } catch (_) {
        _enterDegradedMode('local_llm_failure');
      }
    } else {
      state.value = HudUiState.cloudProcessing;
      await memory.put(MemoryItem(id: DateTime.now().microsecondsSinceEpoch.toString(), text: chunk.text, embedding: const []));
    }

    if (!_disposed) {
      state.value = HudUiState.responding;
    }
  }

  void _enterDegradedMode(String reason) {
    telemetry.emit(TelemetryEvent(TelemetryMetric.cloudRoundtripMs, -1, tags: {'reason': reason}));
    modeController.enable(reason: reason);
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
    if (!_disposed && state.value != HudUiState.degradedMode) {
      state.value = HudUiState.idle;
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    await stopListening();
    state.dispose();
  }
}
