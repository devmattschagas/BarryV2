import 'package:barry_core/barry_core.dart';
import 'package:barry_livekit/barry_livekit.dart';
import 'package:barry_memory/barry_memory.dart';
import 'package:barry_native_ffi/barry_native_ffi.dart';
import 'package:barry_platform_bridge/barry_platform_bridge.dart';
import 'package:barry_router/barry_router.dart';
import 'package:barry_stt/barry_stt.dart';
import 'package:barry_ui_hud/barry_ui_hud.dart';
import 'package:barry_vad/barry_vad.dart';
import 'package:barry_vision/barry_vision.dart';
import 'package:flutter/material.dart';

import 'hud_coordinator.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final telemetry = InMemoryTelemetryBus();
  final nativeReport = const NativeLibraryLoader().verify();

  final coordinator = HudCoordinator(
    telemetry: telemetry,
    router: RuleBasedInferenceRouter(telemetry: telemetry),
    transcriptionEngine: MockTranscriptionEngine(),
    vadController: VadHysteresisController(
      config: const VadConfig(),
      telemetry: telemetry,
      nativeEnabled: nativeReport.ok,
    ),
    livekit: MockLiveKitSessionManager(),
    memory: InMemoryMemoryStore(),
    visionGateway: MockBarryVisionGateway(),
    localLlmEngine: const PlatformLocalLlmEngine(),
    modeController: DegradedModeController(),
  );

  runApp(BarryHudApp(coordinator: coordinator));
}
