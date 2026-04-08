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

  @override
  final ValueNotifier<HudUiState> state = ValueNotifier(HudUiState.idle);
}
