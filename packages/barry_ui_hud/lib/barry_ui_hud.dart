library barry_ui_hud;

import 'dart:math' as math;

import 'package:barry_core/barry_core.dart';
import 'package:flutter/material.dart';

Color _withAlphaFromOpacity(Color color, double opacity) {
  final rawAlpha = (opacity * 255).round();
  final clampedAlpha = rawAlpha < 0
      ? 0
      : rawAlpha > 255
          ? 255
          : rawAlpha;
  return color.withAlpha(clampedAlpha);
}

abstract interface class HudStateSource {
  ValueNotifier<HudUiState> get state;
}

class BarryHudApp extends StatelessWidget {
  const BarryHudApp({super.key, required this.coordinator});
  final HudStateSource coordinator;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: const Color(0xFF05070C)),
      home: Scaffold(
        body: ValueListenableBuilder<HudUiState>(
          valueListenable: coordinator.state,
          builder: (_, state, __) => BarryHudScreen(state: state),
        ),
      ),
    );
  }
}

class BarryHudScreen extends StatefulWidget {
  const BarryHudScreen({super.key, required this.state});
  final HudUiState state;

  @override
  State<BarryHudScreen> createState() => _BarryHudScreenState();
}

class _BarryHudScreenState extends State<BarryHudScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = switch (widget.state) {
      HudUiState.localProcessing => const Color(0xFFFFB300),
      HudUiState.cloudProcessing => const Color(0xFF00E5FF),
      HudUiState.listening || HudUiState.transcribing => const Color(0xFF29B6F6),
      _ => const Color(0xFF607D8B),
    };

    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) => Stack(
        children: [
          Center(
            child: CustomPaint(
              size: const Size(300, 300),
              painter: ReactorPainter(color: color, phase: _controller.value),
            ),
          ),
          Positioned(
            left: 16,
            top: 16,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white24),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Text('HUD State: ${widget.state.name}'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ReactorPainter extends CustomPainter {
  ReactorPainter({required this.color, required this.phase});
  final Color color;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.shortestSide / 2;

    final pulse = 0.9 + 0.1 * math.sin(phase * math.pi * 2);

    final aura = Paint()
      ..shader = RadialGradient(
        colors: [_withAlphaFromOpacity(color, 0.32), Colors.transparent],
      ).createShader(Rect.fromCircle(center: center, radius: r * 0.95 * pulse));
    canvas.drawCircle(center, r * 0.95 * pulse, aura);

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = _withAlphaFromOpacity(color, 0.7);

    for (var i = 0; i < 4; i++) {
      final rr = r * (0.26 + i * 0.12);
      final start = phase * math.pi * (i + 1);
      canvas.drawArc(Rect.fromCircle(center: center, radius: rr), start, math.pi * 1.4, false, ring);
    }

    final spoke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = _withAlphaFromOpacity(color, 0.45);

    final spokePath = Path();
    for (var i = 0; i < 12; i++) {
      final a = (i / 12) * math.pi * 2 + (phase * 0.6);
      final p1 = Offset(center.dx + math.cos(a) * r * 0.22, center.dy + math.sin(a) * r * 0.22);
      final p2 = Offset(center.dx + math.cos(a) * r * 0.48, center.dy + math.sin(a) * r * 0.48);
      spokePath.moveTo(p1.dx, p1.dy);
      spokePath.lineTo(p2.dx, p2.dy);
    }
    canvas.drawPath(spokePath, spoke);

    final core = Paint()
      ..shader = RadialGradient(
        colors: [_withAlphaFromOpacity(Colors.white, 0.92), color, _withAlphaFromOpacity(color, 0.3)],
      ).createShader(Rect.fromCircle(center: center, radius: r * 0.18));
    canvas.drawCircle(center, r * 0.18, core);
  }

  @override
  bool shouldRepaint(covariant ReactorPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.phase != phase;
  }
}
