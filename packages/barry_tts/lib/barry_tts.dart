library barry_tts;

import 'package:barry_core/barry_core.dart';

abstract interface class TtsEngine {
  Future<List<int>> synthesize(String text);
}

class UnsupportedLocalTtsEngine implements TtsEngine {
  @override
  Future<List<int>> synthesize(String text) {
    throw UnsupportedError('Local TTS deve ser fornecido pela camada de app/plataforma.');
  }
}

typedef RemoteTtsSynthesize = Future<List<int>> Function(String text, RemoteTransport transport);

class RemoteTtsEngine implements TtsEngine {
  const RemoteTtsEngine({required this.transport, required this.synthesizeFn});
  final RemoteTransport transport;
  final RemoteTtsSynthesize synthesizeFn;

  @override
  Future<List<int>> synthesize(String text) => synthesizeFn(text, transport);
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
