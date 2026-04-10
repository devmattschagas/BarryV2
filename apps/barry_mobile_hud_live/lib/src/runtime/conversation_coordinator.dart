import 'dart:async';

import '../models.dart';
import '../storage.dart';
import 'errors.dart';
import 'local_ai_adapter.dart';
import 'remote_ai_client.dart';
import 'stt_local_service.dart';
import 'tts_local_service.dart';
import 'zeptoclaw_services.dart';

typedef TranscriptConfirmation = Future<String?> Function(String transcript);

class ConversationCoordinator {
  ConversationCoordinator({
    required this.storage,
    required this.sttService,
    required this.ttsService,
    required this.localAi,
    required this.remoteAi,
    required this.zeptoLocal,
    required this.zeptoRemote,
  });

  final AppStorage storage;
  final LocalSttService sttService;
  final LocalTtsService ttsService;
  final LocalAiAdapter localAi;
  final RemoteAiClient remoteAi;
  final ZeptoClawLocalExecutor zeptoLocal;
  final ZeptoClawRemoteClient zeptoRemote;

  AssistantSettings settings = AssistantSettings.defaults;
  AssistantState state = AssistantState.idle;
  String partialTranscript = '';
  String lastError = '';
  List<ConversationThread> conversations = <ConversationThread>[];
  String? activeConversationId;
  UserProfile profile = UserProfile.defaults;

  ConversationThread get activeConversation => conversations.firstWhere(
        (c) => c.id == activeConversationId,
        orElse: () => conversations.first,
      );

  Future<void> hydrate() async {
    settings = await storage.loadSettings();
    final loadedConversations = await storage.loadConversations();
    final loadedActive = await storage.loadActiveConversationId();
    profile = await storage.loadUserProfile();
    conversations = loadedConversations.isEmpty ? [_newConversation(seed: true)] : loadedConversations;
    activeConversationId = loadedActive ?? conversations.first.id;
  }

  Future<void> createConversation() async {
    final thread = _newConversation();
    conversations = [thread, ...conversations];
    activeConversationId = thread.id;
    await storage.saveConversations(conversations);
    await storage.saveActiveConversationId(thread.id);
  }

  Future<void> switchConversation(String id) async {
    activeConversationId = id;
    await storage.saveActiveConversationId(id);
  }

  Future<void> updateSettings(AssistantSettings value) async {
    settings = value;
    await storage.saveSettings(value);
  }

  Future<void> updateProfile(UserProfile value) async {
    profile = value;
    await storage.saveUserProfile(value);
  }

  Future<void> toggleListening({required TranscriptConfirmation confirmTranscript}) async {
    if (state == AssistantState.listening) {
      await sttService.stop();
      state = AssistantState.idle;
      return;
    }

    state = AssistantState.listening;
    partialTranscript = '';
    lastError = '';

    await sttService.startListening(
      onTranscript: (partial, isFinal) async {
        partialTranscript = partial;
        if (!isFinal || partial.trim().isEmpty) return;

        if (settings.confirmTranscriptBeforeSend) {
          final confirmed = await confirmTranscript(partial);
          if (confirmed == null || confirmed.trim().isEmpty) {
            state = AssistantState.idle;
            return;
          }
          await submitText(confirmed.trim());
          return;
        }
        await submitText(partial.trim());
      },
      onError: (failure) {
        state = AssistantState.error;
        lastError = failure.message;
      },
    );
  }

  Future<void> submitText(String text) async {
    final userMessage = ConversationMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      role: 'user',
      text: text,
      timestamp: DateTime.now(),
    );

    final current = activeConversation;
    final updated = current.copyWith(
      title: current.messages.isEmpty ? _deriveTitle(text) : current.title,
      messages: [...current.messages, userMessage],
    );
    _replaceConversation(updated);

    state = AssistantState.processing;
    partialTranscript = text;

    try {
      final zeptoContext = await _resolveZeptoContext(text);
      final prompt = zeptoContext == null ? text : '$text\n\nContexto ZeptoClaw:\n$zeptoContext';
      final assistantText = await _resolveModelReply(prompt, updated.messages);

      final assistantMessage = ConversationMessage(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        role: 'assistant',
        text: assistantText,
        timestamp: DateTime.now(),
      );

      _replaceConversation(updated.copyWith(messages: [...updated.messages, assistantMessage]));

      state = AssistantState.speaking;
      await ttsService.speak(assistantText);
      state = AssistantState.idle;
      lastError = '';
    } on RuntimeFailure catch (failure) {
      state = AssistantState.error;
      lastError = failure.message;
    } catch (e) {
      state = AssistantState.error;
      lastError = 'Falha inesperada do runtime: $e';
    }
  }

  Future<String> _resolveModelReply(String prompt, List<ConversationMessage> messages) async {
    switch (settings.inferencePolicy) {
      case InferencePolicy.localOnly:
        return localAi.infer(prompt: prompt, settings: settings);
      case InferencePolicy.remoteOnly:
        return remoteAi.infer(messages: [...messages, _promptAsUser(prompt)], settings: settings);
      case InferencePolicy.hybridPreferLocal:
        try {
          return await localAi.infer(prompt: prompt, settings: settings);
        } on RuntimeFailure {
          return remoteAi.infer(messages: [...messages, _promptAsUser(prompt)], settings: settings);
        }
      case InferencePolicy.hybridPreferRemote:
        try {
          return await remoteAi.infer(messages: [...messages, _promptAsUser(prompt)], settings: settings);
        } on RuntimeFailure {
          return localAi.infer(prompt: prompt, settings: settings);
        }
    }
  }

  Future<String?> _resolveZeptoContext(String text) async {
    try {
      final local = await zeptoLocal.tryExecute(text, settings);
      if (local != null) return local;
    } on RuntimeFailure {
      // Distinto do remoto: erro local não impede fallback cloud.
    }

    try {
      final remote = await zeptoRemote.tryExecute(text, settings);
      if (remote != null) return remote;
    } on RuntimeFailure catch (failure) {
      if (settings.inferencePolicy == InferencePolicy.remoteOnly) {
        throw RuntimeFailure(RuntimeErrorType.unavailable, 'ZeptoClaw cloud falhou: ${failure.message}');
      }
    }
    return null;
  }

  ConversationMessage _promptAsUser(String prompt) => ConversationMessage(
        id: 'prompt-${DateTime.now().microsecondsSinceEpoch}',
        role: 'user',
        text: prompt,
        timestamp: DateTime.now(),
      );

  void _replaceConversation(ConversationThread updated) {
    conversations = conversations.map((c) => c.id == updated.id ? updated : c).toList(growable: false);
    unawaited(storage.saveConversations(conversations));
  }

  ConversationThread _newConversation({bool seed = false}) {
    final now = DateTime.now();
    return ConversationThread(
      id: now.microsecondsSinceEpoch.toString(),
      title: seed ? 'Conversa inicial' : 'Nova conversa',
      createdAt: now,
      messages: <ConversationMessage>[],
    );
  }

  String _deriveTitle(String text) => text.length <= 28 ? text : '${text.substring(0, 28)}…';
}
