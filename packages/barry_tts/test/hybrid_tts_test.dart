import 'package:barry_core/barry_core.dart';
import 'package:barry_tts/barry_tts.dart';
import 'package:test/test.dart';

class _LocalTts implements TtsEngine {
  @override
  Future<List<int>> synthesize(String text) async => text.codeUnits;
}

void main() {
  test('local TTS first', () async {
    final engine = HybridTtsEngine(
      local: _LocalTts(),
      remote: RemoteTtsEngine(transport: RemoteTransport.webrtc, synthesizeFn: (text, transport) async => 'remote:$text'.codeUnits),
      capabilities: CapabilityProfile.empty.copyWith(hasLocalTts: true, hasRemoteTts: true),
    );
    final out = await engine.synthesize('oi');
    expect(String.fromCharCodes(out), 'oi');
  });

  test('remote fallback', () async {
    final engine = HybridTtsEngine(
      local: _LocalTts(),
      remote: RemoteTtsEngine(transport: RemoteTransport.webrtc, synthesizeFn: (text, transport) async => 'webrtc:$text'.codeUnits),
      capabilities: CapabilityProfile.empty.copyWith(hasRemoteTts: true),
    );
    final out = await engine.synthesize('ola');
    expect(String.fromCharCodes(out), startsWith('webrtc:'));
  });
}
