library barry_livekit;

enum LiveKitStatus { disconnected, connecting, connected, reconnecting }

abstract interface class LiveKitSessionManager {
  Stream<LiveKitStatus> get status;
  Future<void> connect({required String url, required String token});
  Future<void> disconnect();
}

class MockLiveKitSessionManager implements LiveKitSessionManager {
  final Stream<LiveKitStatus> _status = Stream<LiveKitStatus>.value(LiveKitStatus.connected);

  @override
  Stream<LiveKitStatus> get status => _status;

  @override
  Future<void> connect({required String url, required String token}) async {}

  @override
  Future<void> disconnect() async {}
}
