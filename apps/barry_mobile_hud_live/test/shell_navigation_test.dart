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

Future<void> _pumpUi(WidgetTester tester, {Duration duration = const Duration(milliseconds: 350)}) async {
  await tester.pump();
  await tester.pump(duration);
}

void main() {
  testWidgets('abre Settings a partir do shell e salva sem crash', (tester) async {
    final storage = _MemoryStorage();

    await tester.pumpWidget(
      BarryAssistantShell(
        storage: storage,
        initialSettings: AssistantSettings.defaults,
        coordinatorBuilder: _buildCoordinator,
      ),
    );
    await _pumpUi(tester, duration: const Duration(milliseconds: 600));

    await tester.tap(find.byKey(const Key('shell_nav_toggle')));
    await _pumpUi(tester);
    await tester.tap(find.byKey(const Key('shell_nav_settings')));
    await _pumpUi(tester);

    expect(find.text('Settings do sistema'), findsOneWidget);
    final settingsSaveButton = find.widgetWithText(FilledButton, 'Salvar');
    await tester.ensureVisible(settingsSaveButton);
    await tester.tap(settingsSaveButton);
    await _pumpUi(tester);

    expect(find.byKey(const Key('shell_nav_toggle')), findsOneWidget);
    expect(find.text('Settings do sistema'), findsNothing);
  });

  testWidgets('abre Conta do usuário a partir do shell e salva sem crash', (tester) async {
    final storage = _MemoryStorage();

    await tester.pumpWidget(
      BarryAssistantShell(
        storage: storage,
        initialSettings: AssistantSettings.defaults,
        coordinatorBuilder: _buildCoordinator,
      ),
    );
    await _pumpUi(tester, duration: const Duration(milliseconds: 600));

    await tester.tap(find.byKey(const Key('shell_nav_toggle')));
    await _pumpUi(tester);
    await tester.tap(find.byKey(const Key('shell_nav_account')));
    await _pumpUi(tester);

    expect(find.text('Conta do usuário'), findsOneWidget);
    final nameField = find.widgetWithText(TextField, 'Nome de usuário');
    await tester.ensureVisible(nameField);
    await tester.enterText(nameField, 'Operador Teste');
    final saveProfileButton = find.widgetWithText(FilledButton, 'Salvar perfil');
    await tester.ensureVisible(saveProfileButton);
    await tester.tap(saveProfileButton);
    await _pumpUi(tester);

    expect(find.byKey(const Key('shell_nav_toggle')), findsOneWidget);
    expect(find.text('Conta do usuário'), findsNothing);
  });
}
