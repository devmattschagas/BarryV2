import 'package:barry_core/barry_core.dart';
import 'package:barry_livekit/barry_livekit.dart';
import 'package:barry_memory/barry_memory.dart';
import 'package:barry_mobile_hud_live/hud_coordinator.dart';
import 'package:barry_platform_bridge/barry_platform_bridge.dart';
import 'package:barry_router/barry_router.dart';
import 'package:barry_stt/barry_stt.dart';
import 'package:barry_vad/barry_vad.dart';
import 'package:barry_vision/barry_vision.dart';
import 'package:flutter_test/flutter_test.dart';

class _TranscriptionEngine implements TranscriptionEngine {
  @override
  Stream<TranscriptChunk> streamTranscription(Stream<List<int>> pcm16leFrames) =>
      const Stream<TranscriptChunk>.empty();
}

class _LiveKit implements LiveKitSessionManager {
  @override
  Future<void> connect({required String url, required String token}) async {}

  @override
  Future<void> disconnect() async {}

  @override
  Stream<LiveKitStatus> get status => const Stream<LiveKitStatus>.empty();
}

class _VisionGateway implements BarryVisionGateway {
  @override
  Future<List<VisionDetection>> dispatchFrame(List<int> rgbaBytes, int width, int height) async => const [];
}

void main() {
  test('coordinator bootstraps', () {
    final telemetry = InMemoryTelemetryBus();
    final coordinator = HudCoordinator(
      telemetry: telemetry,
      router: RuleBasedInferenceRouter(telemetry: telemetry),
      transcriptionEngine: _TranscriptionEngine(),
      vadController: VadHysteresisController(
        config: const VadConfig(),
        telemetry: telemetry,
      ),
      livekit: _LiveKit(),
      memory: InMemoryMemoryStore(),
      visionGateway: _VisionGateway(),
      localLlmEngine: const PlatformLocalLlmEngine(),
      modeController: DegradedModeController(),
      capabilities: CapabilityProfile.empty,
    );

    expect(coordinator.state.value, HudUiState.idle);
  });
}
