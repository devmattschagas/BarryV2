import 'package:barry_core/barry_core.dart';
import 'package:barry_tts/barry_tts.dart';
import 'package:test/test.dart';

void main() {
  test('local TTS first', () async {
    final engine = HybridTtsEngine(
      local: LocalTtsEngine(),
      remote: const RemoteTtsEngine(transport: RemoteTransport.webrtc),
      capabilities: CapabilityProfile.empty.copyWith(hasLocalTts: true, hasRemoteTts: true),
    );
    final out = await engine.synthesize('oi');
    expect(String.fromCharCodes(out), 'oi');
  });

  test('remote fallback', () async {
    final engine = HybridTtsEngine(
      local: LocalTtsEngine(),
      remote: const RemoteTtsEngine(transport: RemoteTransport.webrtc),
      capabilities: CapabilityProfile.empty.copyWith(hasRemoteTts: true),
    );
    final out = await engine.synthesize('ola');
    expect(String.fromCharCodes(out), startsWith('webrtc:'));
  });
}
