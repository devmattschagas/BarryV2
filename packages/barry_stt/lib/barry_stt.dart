library barry_stt;

import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

class TranscriptChunk {
  const TranscriptChunk({required this.text, required this.isFinal, required this.startMs, required this.endMs});
  final String text;
  final bool isFinal;
  final int startMs;
  final int endMs;
}

abstract interface class TranscriptionEngine {
  Stream<TranscriptChunk> streamTranscription(Stream<List<int>> pcm16leFrames);
}

class MockTranscriptionEngine implements TranscriptionEngine {
  @override
  Stream<TranscriptChunk> streamTranscription(Stream<List<int>> pcm16leFrames) async* {
    await for (final _ in pcm16leFrames.take(1)) {
      yield const TranscriptChunk(text: 'mock partial', isFinal: false, startMs: 0, endMs: 300);
      yield const TranscriptChunk(text: 'mock final', isFinal: true, startMs: 0, endMs: 600);
    }
  }
}

class NullTranscriptionEngine implements TranscriptionEngine {
  @override
  Stream<TranscriptChunk> streamTranscription(Stream<List<int>> pcm16leFrames) => const Stream.empty();
}

class FasterWhisperSidecarEngine implements TranscriptionEngine {
  FasterWhisperSidecarEngine(this.endpoint);
  final Uri endpoint;

  @override
  Stream<TranscriptChunk> streamTranscription(Stream<List<int>> pcm16leFrames) async* {
    final channel = WebSocketChannel.connect(endpoint);
    final iterator = StreamIterator<Object?>(channel.stream);

    try {
      await for (final frame in pcm16leFrames) {
        channel.sink.add(frame);
        final hasNext = await iterator.moveNext();
        if (!hasNext) {
          break;
        }

        final decoded = jsonDecode(iterator.current as String) as Map<String, dynamic>;
        yield TranscriptChunk(
          text: decoded['text'] as String? ?? '',
          isFinal: decoded['is_final'] as bool? ?? false,
          startMs: decoded['start_ms'] as int? ?? 0,
          endMs: decoded['end_ms'] as int? ?? 0,
        );
      }
    } finally {
      await iterator.cancel();
      await channel.sink.close();
    }
  }
}
