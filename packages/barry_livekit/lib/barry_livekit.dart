library barry_livekit;

import 'dart:async';

import 'package:livekit_client/livekit_client.dart';

enum LiveKitStatus { disconnected, connecting, connected, reconnecting }

abstract interface class LiveKitSessionManager {
  Stream<LiveKitStatus> get status;
  Future<void> connect({required String url, required String token});
  Future<void> disconnect();
}

class BarryLiveKitSessionManager implements LiveKitSessionManager {
  final _controller = StreamController<LiveKitStatus>.broadcast();
  Room? _room;

  @override
  Stream<LiveKitStatus> get status => _controller.stream;

  @override
  Future<void> connect({required String url, required String token}) async {
    _controller.add(LiveKitStatus.connecting);
    final room = Room();
    await room.connect(url, token);
    _room = room;
    _controller.add(LiveKitStatus.connected);
  }

  @override
  Future<void> disconnect() async {
    await _room?.disconnect();
    _room = null;
    _controller.add(LiveKitStatus.disconnected);
  }
}
