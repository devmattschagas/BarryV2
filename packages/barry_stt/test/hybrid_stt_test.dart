import 'package:barry_core/barry_core.dart';
import 'package:barry_stt/barry_stt.dart';
import 'package:test/test.dart';

class _LocalEngine implements TranscriptionEngine {
  @override
  Stream<TranscriptChunk> streamTranscription(Stream<List<int>> pcm16leFrames) async* {
    yield const TranscriptChunk(text: 'local final', isFinal: true, startMs: 0, endMs: 10);
  }
}

void main() {
  test('prefers local STT when capability exists', () async {
    final engine = HybridTranscriptionEngine(
      local: _LocalEngine(),
      remote: RemoteSttAdapter(endpoint: Uri.parse('https://localhost:9999/stt'), transport: RemoteTransport.http, httpBatchTranscribe: (_) async => {'text': 'remote'}),
      capabilities: CapabilityProfile.empty.copyWith(hasLocalStt: true, hasRemoteStt: true),
    );
    final out = await engine.streamTranscription(Stream.value([1, 2, 3])).first;
    expect(out.text, 'local final');
  });

  test('falls back to remote STT when local unavailable', () async {
    final engine = HybridTranscriptionEngine(
      local: _LocalEngine(),
      remote: RemoteSttAdapter(
        endpoint: Uri.parse('https://example.invalid/stt'),
        transport: RemoteTransport.http,
        httpBatchTranscribe: (_) async => {'text': 'remote http final'},
      ),
      capabilities: CapabilityProfile.empty.copyWith(hasRemoteStt: true),
    );
    final out = await engine.streamTranscription(Stream.value([1, 2, 3])).first;
    expect(out.text, contains('remote'));
  });
}
