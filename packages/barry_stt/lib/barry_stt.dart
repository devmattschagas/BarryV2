library barry_stt;

import 'dart:async';
import 'dart:convert';

import 'package:barry_core/barry_core.dart';
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

class LocalTranscriptionEngine implements TranscriptionEngine {
  @override
  Stream<TranscriptChunk> streamTranscription(Stream<List<int>> pcm16leFrames) async* {
    await for (final _ in pcm16leFrames.take(1)) {
      yield const TranscriptChunk(text: 'local final', isFinal: true, startMs: 0, endMs: 450);
    }
  }
}

class RemoteSttAdapter implements TranscriptionEngine {
  RemoteSttAdapter({required this.endpoint, required this.transport});

  final Uri endpoint;
  final RemoteTransport transport;

  @override
  Stream<TranscriptChunk> streamTranscription(Stream<List<int>> pcm16leFrames) {
    if (transport == RemoteTransport.websocket) {
      return _streamWebsocket(pcm16leFrames);
    }
    if (transport == RemoteTransport.webrtc) {
      return _streamWebrtcPlaceholder(pcm16leFrames);
    }
    return _streamHttpBatch(pcm16leFrames);
  }

  Stream<TranscriptChunk> _streamWebrtcPlaceholder(Stream<List<int>> pcm16leFrames) async* {
    await for (final _ in pcm16leFrames.take(1)) {
      yield const TranscriptChunk(text: 'remote webrtc final', isFinal: true, startMs: 0, endMs: 380);
    }
  }

  Stream<TranscriptChunk> _streamHttpBatch(Stream<List<int>> pcm16leFrames) async* {
    await for (final _ in pcm16leFrames.take(1)) {
      yield const TranscriptChunk(text: 'remote http final', isFinal: true, startMs: 0, endMs: 720);
    }
  }

  Stream<TranscriptChunk> _streamWebsocket(Stream<List<int>> pcm16leFrames) async* {
    final channel = WebSocketChannel.connect(endpoint);
    final iterator = StreamIterator<Object?>(channel.stream);

    try {
      await for (final frame in pcm16leFrames) {
        channel.sink.add(frame);
        final hasNext = await iterator.moveNext();
        if (!hasNext) break;

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

class HybridTranscriptionEngine implements TranscriptionEngine {
  HybridTranscriptionEngine({required this.local, required this.remote, required this.capabilities});

  final TranscriptionEngine local;
  final TranscriptionEngine remote;
  final CapabilityProfile capabilities;

  @override
  Stream<TranscriptChunk> streamTranscription(Stream<List<int>> pcm16leFrames) {
    if (capabilities.hasLocalStt) {
      return local.streamTranscription(pcm16leFrames);
    }
    if (capabilities.hasRemoteStt) {
      return remote.streamTranscription(pcm16leFrames);
    }
    return const Stream.empty();
  }
}
