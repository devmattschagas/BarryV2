import 'package:flutter/widgets.dart';

import 'src/assistant_shell.dart';
import 'src/storage.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = AppStorage();
  final settings = await storage.loadSettings();
  runApp(BarryAssistantShell(storage: storage, initialSettings: settings));
}
