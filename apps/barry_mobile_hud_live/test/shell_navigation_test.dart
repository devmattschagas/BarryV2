import 'package:barry_mobile_hud_live/src/assistant_shell.dart';
import 'package:barry_mobile_hud_live/src/models.dart';
import 'package:barry_mobile_hud_live/src/runtime/conversation_coordinator.dart';
import 'package:barry_mobile_hud_live/src/runtime/errors.dart';
import 'package:barry_mobile_hud_live/src/runtime/local_ai_adapter.dart';
import 'package:barry_mobile_hud_live/src/runtime/remote_ai_client.dart';
import 'package:barry_mobile_hud_live/src/runtime/stt_local_service.dart';
import 'package:barry_mobile_hud_live/src/runtime/tts_local_service.dart';
import 'package:barry_mobile_hud_live/src/runtime/zeptoclaw_services.dart';
import 'package:barry_mobile_hud_live/src/storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryStorage extends AppStorage {
  AssistantSettings _settings = AssistantSettings.defaults;
  List<ConversationThread> _conversations = <ConversationThread>[];
  String? _activeId;
  UserProfile _profile = UserProfile.defaults;

  @override
  Future<String?> loadActiveConversationId() async => _activeId;

  @override
  Future<List<ConversationThread>> loadConversations() async => _conversations;

  @override
  Future<UserProfile> loadUserProfile() async => _profile;

  @override
  Future<AssistantSettings> loadSettings() async => _settings;

  @override
  Future<void> saveActiveConversationId(String id) async => _activeId = id;

  @override
  Future<void> saveConversations(List<ConversationThread> conversations) async => _conversations = conversations;

  @override
  Future<void> saveSettings(AssistantSettings settings) async => _settings = settings;

  @override
  Future<void> saveUserProfile(UserProfile profile) async => _profile = profile;
}

class _FakeStt implements LocalSttService {
  @override
  Future<void> startListening({
    required void Function(String partial, bool isFinal) onTranscript,
    required void Function(RuntimeFailure failure) onError,
  }) async {}

  @override
  Future<void> stop() async {}
}

class _FakeTts implements LocalTtsService {
  @override
  Future<void> speak(String text) async {}

  @override
  Future<void> stop() async {}
}

class _FakeLocalAi implements LocalAiAdapter {
  @override
  Future<String> infer({required String prompt, required AssistantSettings settings}) async => 'ok';
}

class _FakeRemoteAi implements RemoteAiClient {
  @override
  Future<String> infer({required List<ConversationMessage> messages, required AssistantSettings settings}) async => 'ok remoto';
}

class _FakeZeptoLocal implements ZeptoClawLocalExecutor {
  @override
  Future<String?> tryExecute(String prompt, AssistantSettings settings) async => null;
}

class _FakeZeptoRemote implements ZeptoClawRemoteClient {
  @override
  Future<String?> tryExecute(String prompt, AssistantSettings settings) async => null;
}

class _SettingsTestScreen extends StatelessWidget {
  const _SettingsTestScreen({required this.initial});

  final AssistantSettings initial;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings Test Screen')),
      body: Center(
        child: FilledButton(
          key: const Key('settings_save_test'),
          onPressed: () => Navigator.of(context).pop(initial.copyWith(timeoutMs: initial.timeoutMs + 1)),
          child: const Text('Salvar'),
        ),
      ),
    );
  }
}

class _AccountTestScreen extends StatelessWidget {
  const _AccountTestScreen({required this.initial});

  final UserProfile initial;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Account Test Screen')),
      body: Center(
        child: FilledButton(
          key: const Key('account_save_test'),
          onPressed: () => Navigator.of(context).pop(UserProfile(name: 'Operador Teste', avatarPath: initial.avatarPath)),
          child: const Text('Salvar perfil'),
        ),
      ),
    );
  }
}

ConversationCoordinator _buildCoordinator(AppStorage storage) {
  return ConversationCoordinator(
    storage: storage,
    sttService: _FakeStt(),
    ttsService: _FakeTts(),
    localAi: _FakeLocalAi(),
    remoteAi: _FakeRemoteAi(),
    zeptoLocal: _FakeZeptoLocal(),
    zeptoRemote: _FakeZeptoRemote(),
  );
}

void main() {
  testWidgets('abre Settings a partir do shell e salva sem crash', (tester) async {
    final storage = _MemoryStorage();

    await tester.pumpWidget(
      BarryAssistantShell(
        storage: storage,
        initialSettings: AssistantSettings.defaults,
        coordinatorBuilder: _buildCoordinator,
        enableCorePulseAnimation: false,
        settingsScreenBuilder: (context, settings) => _SettingsTestScreen(initial: settings),
        accountScreenBuilder: (context, profile) => _AccountTestScreen(initial: profile),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('shell_nav_toggle')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('shell_nav_settings')));
    await tester.tap(find.byKey(const Key('shell_nav_settings')));
    await tester.pumpAndSettle();

    expect(find.text('Settings Test Screen'), findsOneWidget);
    final settingsSaveButton = find.byKey(const Key('settings_save_test'));
    await tester.ensureVisible(settingsSaveButton);
    await tester.tap(settingsSaveButton);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shell_nav_toggle')), findsOneWidget);
    expect(find.text('Settings Test Screen'), findsNothing);
  });

  testWidgets('abre Conta do usuário a partir do shell e salva sem crash', (tester) async {
    final storage = _MemoryStorage();

    await tester.pumpWidget(
      BarryAssistantShell(
        storage: storage,
        initialSettings: AssistantSettings.defaults,
        coordinatorBuilder: _buildCoordinator,
        enableCorePulseAnimation: false,
        settingsScreenBuilder: (context, settings) => _SettingsTestScreen(initial: settings),
        accountScreenBuilder: (context, profile) => _AccountTestScreen(initial: profile),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('shell_nav_toggle')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('shell_nav_account')));
    await tester.tap(find.byKey(const Key('shell_nav_account')));
    await tester.pumpAndSettle();

    expect(find.text('Account Test Screen'), findsOneWidget);
    final saveProfileButton = find.byKey(const Key('account_save_test'));
    await tester.ensureVisible(saveProfileButton);
    await tester.tap(saveProfileButton);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shell_nav_toggle')), findsOneWidget);
    expect(find.text('Account Test Screen'), findsNothing);
  });
}
