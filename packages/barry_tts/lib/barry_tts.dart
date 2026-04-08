library barry_tts;

import 'package:barry_core/barry_core.dart';

abstract interface class TtsEngine {
  Future<List<int>> synthesize(String text);
}

class LocalTtsEngine implements TtsEngine {
  @override
  Future<List<int>> synthesize(String text) async => text.codeUnits;
}

class RemoteTtsEngine implements TtsEngine {
  const RemoteTtsEngine({required this.transport});
  final RemoteTransport transport;

  @override
  Future<List<int>> synthesize(String text) async {
    final prefix = switch (transport) {
      RemoteTransport.webrtc => 'webrtc',
      RemoteTransport.websocket => 'ws',
      _ => 'http',
    };
    return '$prefix:$text'.codeUnits;
  }
}

class HybridTtsEngine implements TtsEngine {
  const HybridTtsEngine({required this.local, required this.remote, required this.capabilities});

  final TtsEngine local;
  final TtsEngine remote;
  final CapabilityProfile capabilities;

  @override
  Future<List<int>> synthesize(String text) {
    if (capabilities.hasLocalTts) return local.synthesize(text);
    if (capabilities.hasRemoteTts) return remote.synthesize(text);
    return Future.value(const <int>[]);
  }
}
