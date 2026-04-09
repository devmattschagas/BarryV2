import 'package:barry_core/barry_core.dart';
import 'package:barry_ui_hud/barry_ui_hud.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders idle state', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: BarryHudScreen(state: HudUiState.idle),
        ),
      ),
    );

    expect(find.textContaining('HUD State: idle'), findsOneWidget);
  });
}
