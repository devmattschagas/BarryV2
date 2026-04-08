library barry_ui_hud;

import 'package:barry_core/barry_core.dart';
import 'package:flutter/material.dart';

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

class BarryHudScreen extends StatelessWidget {
  const BarryHudScreen({super.key, required this.state});
  final HudUiState state;

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      HudUiState.localProcessing => Colors.amber,
      HudUiState.cloudProcessing => Colors.cyanAccent,
      _ => Colors.blueGrey,
    };
    return Stack(
      children: [
        Center(child: CustomPaint(size: const Size(240, 240), painter: ReactorPainter(color: color))),
        Positioned(
          left: 16,
          top: 16,
          child: DecoratedBox(
            decoration: BoxDecoration(border: Border.all(color: Colors.white24)),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Text('HUD State: $state'),
            ),
          ),
        ),
      ],
    );
  }
}

class ReactorPainter extends CustomPainter {
  ReactorPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final glow = Paint()..color = color.withValues(alpha: .25);
    canvas.drawCircle(center, size.shortestSide * .45, glow);
    final core = Paint()..color = color;
    canvas.drawCircle(center, size.shortestSide * .2, core);
  }

  @override
  bool shouldRepaint(covariant ReactorPainter oldDelegate) => oldDelegate.color != color;
}
