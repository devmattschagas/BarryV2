import 'package:barry_core/barry_core.dart';
import 'package:barry_livekit/barry_livekit.dart';
import 'package:barry_memory/barry_memory.dart';
import 'package:barry_platform_bridge/barry_platform_bridge.dart';
import 'package:barry_router/barry_router.dart';
import 'package:barry_stt/barry_stt.dart';
import 'package:barry_vad/barry_vad.dart';
import 'package:barry_vision/barry_vision.dart';
import 'package:barry_mobile_hud_live/hud_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('coordinator bootstraps', () {
    final telemetry = InMemoryTelemetryBus();
    final coordinator = HudCoordinator(
      telemetry: telemetry,
      router: RuleBasedInferenceRouter(telemetry: telemetry),
      transcriptionEngine: MockTranscriptionEngine(),
      vadController: VadHysteresisController(
        config: const VadConfig(),
        telemetry: telemetry,
      ),
      livekit: MockLiveKitSessionManager(),
      memory: InMemoryMemoryStore(),
      visionGateway: MockBarryVisionGateway(),
      localLlmEngine: const PlatformLocalLlmEngine(),
      modeController: DegradedModeController(),
    );

    expect(coordinator.state.value, HudUiState.idle);
  });
}
