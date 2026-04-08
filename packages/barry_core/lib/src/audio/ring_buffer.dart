import 'dart:collection';

class PcmFrame {
  PcmFrame({required this.timestampUs, required this.samples});
  final int timestampUs;
  final List<int> samples;
}

class PcmRingBuffer {
  PcmRingBuffer({required this.capacityFrames}) : _queue = ListQueue<PcmFrame>(capacityFrames);

  final int capacityFrames;
  final ListQueue<PcmFrame> _queue;
  int droppedFrames = 0;

  void push(PcmFrame frame) {
    if (_queue.length >= capacityFrames) {
      _queue.removeFirst();
      droppedFrames++;
    }
    _queue.addLast(frame);
  }

  List<PcmFrame> drain() {
    final out = _queue.toList(growable: false);
    _queue.clear();
    return out;
  }
}
