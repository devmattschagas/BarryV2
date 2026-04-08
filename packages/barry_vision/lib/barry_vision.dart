library barry_vision;

class VisionDetection {
  const VisionDetection({required this.label, required this.confidence, required this.x, required this.y, required this.w, required this.h});
  final String label;
  final double confidence;
  final double x;
  final double y;
  final double w;
  final double h;
}

abstract interface class BarryVisionGateway {
  Future<List<VisionDetection>> dispatchFrame(List<int> rgbaBytes, int width, int height);
}

class MockBarryVisionGateway implements BarryVisionGateway {
  @override
  Future<List<VisionDetection>> dispatchFrame(List<int> rgbaBytes, int width, int height) async {
    return const [
      VisionDetection(label: 'mock-target', confidence: 0.92, x: 0.2, y: 0.2, w: 0.3, h: 0.3),
    ];
  }
}
