import 'dart:async';

import 'package:barry_mobile_hud_live/src/models.dart';
import 'package:barry_mobile_hud_live/src/runtime/conversation_coordinator.dart';
import 'package:barry_mobile_hud_live/src/runtime/errors.dart';
import 'package:barry_mobile_hud_live/src/runtime/local_ai_adapter.dart';
import 'package:barry_mobile_hud_live/src/runtime/network_client.dart';
import 'package:barry_mobile_hud_live/src/runtime/remote_ai_client.dart';
import 'package:barry_mobile_hud_live/src/runtime/stt_local_service.dart';
import 'package:barry_mobile_hud_live/src/runtime/tts_local_service.dart';
import 'package:barry_mobile_hud_live/src/runtime/zeptoclaw_services.dart';
import 'package:barry_mobile_hud_live/src/storage.dart';
import 'package:barry_platform_bridge/barry_platform_bridge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart';

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
  Future<void> saveActiveConversationId(String id) async {
    _activeId = id;
  }

  @override
  Future<void> saveConversations(List<ConversationThread> conversations) async {
    _conversations = conversations;
  }

  @override
  Future<void> saveSettings(AssistantSettings settings) async {
    _settings = settings;
  }

  @override
  Future<void> saveUserProfile(UserProfile profile) async {
    _profile = profile;
  }
}

class _FakeStt extends LocalSttService {
  _FakeStt() : super(SpeechToText());

  bool throwsOnStart = false;
  bool emitFinalTwice = true;
  int stopCalls = 0;

  @override
  Future<void> startListening({
    required void Function(String partial, bool isFinal) onTranscript,
    required void Function(RuntimeFailure failure) onError,
  }) async {
    if (throwsOnStart) {
      throw RuntimeFailure(RuntimeErrorType.localUnavailable, 'falhou');
    }
    if (emitFinalTwice) {
      onTranscript('ligar modo debug', true);
      onTranscript('ligar modo debug', true);
    }
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
  }
}

class _FakeTts extends LocalTtsService {
  _FakeTts() : super(FlutterTts());

  int stopCalls = 0;

  @override
  Future<void> speak(String text) async {}

  @override
  Future<void> stop() async {
    stopCalls += 1;
  }
}

class _FakeEngine implements LocalLlmEngine {
  int calls = 0;

  @override
  Future<String> infer(String prompt, {String? model}) async {
    calls += 1;
    return 'ok';
  }
}

class _FakeRemote extends RemoteAiClient {
  _FakeRemote() : super(NetworkClient(http.Client()));

  @override
  Future<String> infer({required List<ConversationMessage> messages, required AssistantSettings settings}) async =>
      'ok remoto';
}

class _FakeZeptoLocal extends ZeptoClawLocalExecutor {
  _FakeZeptoLocal();

  @override
  Future<String?> tryExecute(String prompt, AssistantSettings settings) async => null;
}

class _FakeZeptoRemote extends ZeptoClawRemoteClient {
  _FakeZeptoRemote() : super(NetworkClient(http.Client()));

  @override
  Future<String?> tryExecute(String prompt, AssistantSettings settings) async => null;
}

ConversationCoordinator _buildCoordinator({
  required _MemoryStorage storage,
  _FakeStt? stt,
  _FakeEngine? engine,
  _FakeTts? tts,
}) {
  final fakeStt = stt ?? _FakeStt();
  final fakeEngine = engine ?? _FakeEngine();
  final fakeTts = tts ?? _FakeTts();
  return ConversationCoordinator(
    storage: storage,
    sttService: fakeStt,
    ttsService: fakeTts,
    localAi: LocalAiAdapter(engine: fakeEngine),
    remoteAi: _FakeRemote(),
    zeptoLocal: _FakeZeptoLocal(),
    zeptoRemote: _FakeZeptoRemote(),
  );
}

void main() {
  test('hydrate corrige activeConversationId inválido', () async {
    final storage = _MemoryStorage();
    storage
      .._conversations = [
        ConversationThread(
          id: 'thread-1',
          title: 'x',
          createdAt: DateTime(2026, 1, 1),
          messages: const [],
        ),
      ]
      .._activeId = 'thread-inexistente';
    final coordinator = _buildCoordinator(storage: storage);

    await coordinator.hydrate();

    expect(coordinator.activeConversationId, 'thread-1');
    expect(storage._activeId, 'thread-1');
  });

  test('switchConversation ignora id inexistente', () async {
    final storage = _MemoryStorage();
    final coordinator = _buildCoordinator(storage: storage);
    await coordinator.hydrate();
    final current = coordinator.activeConversationId;

    await coordinator.switchConversation('inexistente');

    expect(coordinator.activeConversationId, current);
  });

  test('submitText ignora entrada vazia', () async {
    final storage = _MemoryStorage();
    final coordinator = _buildCoordinator(storage: storage);
    await coordinator.hydrate();
    final initialMessages = coordinator.activeConversation.messages.length;

    await coordinator.submitText('   ');

    expect(coordinator.activeConversation.messages.length, initialMessages);
  });

  test('submitText não substitui título da conversa com fala do usuário', () async {
    final storage = _MemoryStorage();
    final coordinator = _buildCoordinator(storage: storage);
    await coordinator.hydrate();
    final initialTitle = coordinator.activeConversation.title;

    await coordinator.submitText('Quero status dos sensores agora', muteTts: true);

    expect(coordinator.activeConversation.title, initialTitle);
  });

  test('toggleListening marca erro quando STT falha ao iniciar', () async {
    final storage = _MemoryStorage();
    final stt = _FakeStt()..throwsOnStart = true;
    final coordinator = _buildCoordinator(storage: storage, stt: stt);
    await coordinator.hydrate();

    await coordinator.toggleListening(confirmTranscript: (text) async => text);

    expect(coordinator.state, AssistantState.error);
    expect(coordinator.lastError, contains('falhou'));
  });

  test('toggleListening não envia transcript final duplicado', () async {
    final storage = _MemoryStorage();
    final stt = _FakeStt();
    final engine = _FakeEngine();
    final coordinator = _buildCoordinator(storage: storage, stt: stt, engine: engine);
    await coordinator.hydrate();
    await coordinator.updateSettings(
      coordinator.settings.copyWith(confirmTranscriptBeforeSend: false, inferencePolicy: InferencePolicy.localOnly),
    );

    await coordinator.toggleListening(confirmTranscript: (text) async => text);
    await Future<void>.delayed(const Duration(milliseconds: 1));

    final userMessages = coordinator.activeConversation.messages.where((m) => m.role == 'user').length;
    expect(userMessages, 1);
    expect(engine.calls, 1);
    expect(stt.stopCalls, 1);
  });

  test('toggleListening interrompe TTS quando assistente está speaking', () async {
    final storage = _MemoryStorage();
    final stt = _FakeStt()..emitFinalTwice = false;
    final tts = _FakeTts();
    final coordinator = _buildCoordinator(storage: storage, stt: stt, tts: tts);
    await coordinator.hydrate();
    coordinator.state = AssistantState.speaking;

    await coordinator.toggleListening(confirmTranscript: (text) async => text);

    expect(tts.stopCalls, 1);
    expect(coordinator.state, AssistantState.listening);
  });

  test('coordinator notifica listeners em mudanças de estado', () async {
    final storage = _MemoryStorage();
    final coordinator = _buildCoordinator(storage: storage);
    await coordinator.hydrate();
    var notifications = 0;
    void listener() => notifications += 1;
    coordinator.addListener(listener);

    await coordinator.submitText('teste listener', muteTts: true);

    coordinator.removeListener(listener);
    expect(notifications, greaterThan(0));
  });
}
