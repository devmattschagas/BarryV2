import 'package:barry_core/barry_core.dart';
import 'package:test/test.dart';

void main() {
  test('capability detector is granular and non-global', () {
    final profile = const CapabilityDetector().detect(
      networkHealthy: true,
      nativeVadLoaded: true,
      localLlmBridgeAvailable: false,
      localSttAvailable: true,
      localTtsAvailable: true,
      remoteQwenConfigured: true,
      remoteSttConfigured: true,
      remoteTtsConfigured: false,
      zeptoClawConfigured: true,
      vaultConfigured: true,
      claudeMemConfigured: false,
      paulConfigured: true,
      embeddingsRemoteConfigured: true,
      remoteTransport: RemoteTransport.webrtc,
    );

    expect(profile.hasLocalVad, isTrue);
    expect(profile.hasLocalLlm, isFalse);
    expect(profile.hasCloudQwen, isTrue);
    expect(profile.hasRemoteTts, isFalse);
  });

  test('command policy allowlist centralization', () {
    expect(CommandPolicies.zeptoClawCloud.canExecute('status.read'), isTrue);
    expect(CommandPolicies.zeptoClawCloud.canExecute('rm -rf /'), isFalse);
  });
}
