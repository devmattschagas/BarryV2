import 'package:barry_core/barry_core.dart';
import 'package:barry_stt/barry_stt.dart';
import 'package:test/test.dart';

void main() {
  test('prefers local STT when capability exists', () async {
    final engine = HybridTranscriptionEngine(
      local: LocalTranscriptionEngine(),
      remote: RemoteSttAdapter(endpoint: Uri.parse('ws://localhost:9999'), transport: RemoteTransport.http),
      capabilities: CapabilityProfile.empty.copyWith(hasLocalStt: true, hasRemoteStt: true),
    );
    final out = await engine.streamTranscription(Stream.value([1, 2, 3])).first;
    expect(out.text, 'local final');
  });

  test('falls back to remote STT when local unavailable', () async {
    final engine = HybridTranscriptionEngine(
      local: LocalTranscriptionEngine(),
      remote: RemoteSttAdapter(endpoint: Uri.parse('wss://example.invalid/stt'), transport: RemoteTransport.webrtc),
      capabilities: CapabilityProfile.empty.copyWith(hasRemoteStt: true),
    );
    final out = await engine.streamTranscription(Stream.value([1, 2, 3])).first;
    expect(out.text, contains('remote'));
  });
}
