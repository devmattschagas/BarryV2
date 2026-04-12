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

class UnsupportedLocalTranscriptionEngine implements TranscriptionEngine {
  @override
  Stream<TranscriptChunk> streamTranscription(Stream<List<int>> pcm16leFrames) {
    return Stream<TranscriptChunk>.error(UnsupportedError('Local STT deve ser fornecido pela camada de app/plataforma.'));
  }
}

typedef HttpBatchTranscribe = Future<Map<String, dynamic>> Function(List<int> pcm16);

class RemoteSttAdapter implements TranscriptionEngine {
  RemoteSttAdapter({required this.endpoint, required this.transport, this.httpBatchTranscribe});

  final Uri endpoint;
  final RemoteTransport transport;
  final HttpBatchTranscribe? httpBatchTranscribe;

  @override
  Stream<TranscriptChunk> streamTranscription(Stream<List<int>> pcm16leFrames) {
    if (transport == RemoteTransport.websocket) return _streamWebsocket(pcm16leFrames);
    if (transport == RemoteTransport.http) return _streamHttpBatch(pcm16leFrames);
    return Stream<TranscriptChunk>.error(UnsupportedError('Transporte STT remoto não suportado: $transport'));
  }

  Stream<TranscriptChunk> _streamHttpBatch(Stream<List<int>> pcm16leFrames) async* {
    if (httpBatchTranscribe == null) {
      throw UnsupportedError('httpBatchTranscribe não configurado para STT remoto HTTP.');
    }

    final merged = <int>[];
    await for (final frame in pcm16leFrames) {
      merged.addAll(frame);
    }
    if (merged.isEmpty) return;

    final decoded = await httpBatchTranscribe!(merged);
    final text = (decoded['text'] as String? ?? '').trim();
    if (text.isEmpty) return;
    yield TranscriptChunk(text: text, isFinal: true, startMs: 0, endMs: decoded['end_ms'] as int? ?? 0);
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
        final text = (decoded['text'] as String? ?? '').trim();
        if (text.isEmpty) continue;
        yield TranscriptChunk(
          text: text,
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
    if (capabilities.hasLocalStt) return local.streamTranscription(pcm16leFrames);
    if (capabilities.hasRemoteStt) return remote.streamTranscription(pcm16leFrames);
    return const Stream.empty();
  }
}
