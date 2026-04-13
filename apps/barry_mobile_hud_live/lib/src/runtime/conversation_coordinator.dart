import 'dart:async';
import 'package:flutter/foundation.dart';

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

  final StorageGateway storage;
  final SttService sttService;
  final TtsService ttsService;
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
  bool _isSubmitting = false;
  bool _isHandlingFinalTranscript = false;
  final Set<VoidCallback> _listeners = <VoidCallback>{};

  bool get isBusy => _isSubmitting || state == AssistantState.processing || state == AssistantState.speaking;

  void addListener(VoidCallback listener) => _listeners.add(listener);

  void removeListener(VoidCallback listener) => _listeners.remove(listener);

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
    final hasLoadedActive = loadedActive != null && conversations.any((c) => c.id == loadedActive);
    activeConversationId = hasLoadedActive ? loadedActive : conversations.first.id;
    if (!hasLoadedActive) {
      await storage.saveActiveConversationId(activeConversationId!);
    }
    _notifyListeners();
  }

  Future<void> createConversation() async {
    final thread = _newConversation();
    conversations = [thread, ...conversations];
    activeConversationId = thread.id;
    await storage.saveConversations(conversations);
    await storage.saveActiveConversationId(thread.id);
    _notifyListeners();
  }

  Future<void> switchConversation(String id) async {
    if (!conversations.any((c) => c.id == id)) return;
    activeConversationId = id;
    await storage.saveActiveConversationId(id);
    _notifyListeners();
  }

  Future<void> updateSettings(AssistantSettings value) async {
    settings = value;
    await storage.saveSettings(value);
    _notifyListeners();
  }

  Future<void> updateProfile(UserProfile value) async {
    profile = value;
    await storage.saveUserProfile(value);
    _notifyListeners();
  }

  Future<void> toggleListening({required TranscriptConfirmation confirmTranscript}) async {
    if (_isSubmitting) return;

    if (state == AssistantState.listening) {
      await sttService.stop();
      state = AssistantState.idle;
      partialTranscript = '';
      _isHandlingFinalTranscript = false;
      _notifyListeners();
      return;
    }
    if (state == AssistantState.speaking) {
      await ttsService.stop();
      state = AssistantState.idle;
    }

    state = AssistantState.listening;
    partialTranscript = '';
    lastError = '';
    _isHandlingFinalTranscript = false;
    _notifyListeners();

    try {
      await sttService.startListening(
        onTranscript: (partial, isFinal) async {
          partialTranscript = partial;
          _notifyListeners();
          if (!isFinal || partial.trim().isEmpty) return;
          if (_isSubmitting || _isHandlingFinalTranscript || state != AssistantState.listening) return;
          _isHandlingFinalTranscript = true;

          try {
            await sttService.stop();

            if (settings.confirmTranscriptBeforeSend) {
              final confirmed = await confirmTranscript(partial);
              if (confirmed == null || confirmed.trim().isEmpty) {
                state = AssistantState.idle;
                partialTranscript = '';
                _notifyListeners();
                return;
              }
              await submitText(confirmed.trim());
              return;
            }
            await submitText(partial.trim());
          } finally {
            _isHandlingFinalTranscript = false;
          }
        },
        onError: (failure) {
          state = AssistantState.error;
          lastError = failure.message;
          _notifyListeners();
        },
      );
    } on RuntimeFailure catch (failure) {
      state = AssistantState.error;
      lastError = failure.message;
      _notifyListeners();
    } catch (e) {
      state = AssistantState.error;
      lastError = 'Falha ao iniciar escuta local: $e';
      _notifyListeners();
    }
  }

  Future<void> submitText(String text, {bool muteTts = false}) async {
    final normalizedText = text.trim();
    if (normalizedText.isEmpty || _isSubmitting) return;
    _isSubmitting = true;

    final userMessage = ConversationMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      role: 'user',
      text: normalizedText,
      timestamp: DateTime.now(),
    );

    final current = activeConversation;
    final updated = current.copyWith(messages: [...current.messages, userMessage]);
    _replaceConversation(updated);

    state = AssistantState.processing;
    partialTranscript = normalizedText;
    _notifyListeners();

    try {
      final zeptoContext = await _resolveZeptoContext(normalizedText);
      final prompt = zeptoContext == null ? normalizedText : '$normalizedText\n\nContexto ZeptoClaw:\n$zeptoContext';
      final assistantText = _sanitizeAssistantText(await _resolveModelReply(prompt, updated.messages), normalizedText);

      final assistantMessage = ConversationMessage(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        role: 'assistant',
        text: assistantText,
        timestamp: DateTime.now(),
      );

      _replaceConversation(updated.copyWith(messages: [...updated.messages, assistantMessage]));

      if (!muteTts) {
        state = AssistantState.speaking;
        await ttsService.speak(assistantText);
      }
      state = AssistantState.idle;
      lastError = '';
      _notifyListeners();
    } on RuntimeFailure catch (failure) {
      state = AssistantState.error;
      lastError = failure.message;
      _notifyListeners();
    } catch (e) {
      state = AssistantState.error;
      lastError = 'Falha inesperada do runtime: $e';
      _notifyListeners();
    } finally {
      _isSubmitting = false;
      _notifyListeners();
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

  String _sanitizeAssistantText(String raw, String prompt) {
    var sanitized = raw
        .replaceAll(RegExp(r'\[litert-lm-bridge-mock\]', caseSensitive: false), '')
        .replaceAll(RegExp(r'\[model:[^\]]+\]', caseSensitive: false), '')
        .trim();
    if (sanitized.isEmpty) return 'Barry aqui. Não consegui concluir uma resposta útil agora, tente novamente em instantes.';

    final promptNormalized = prompt.trim().toLowerCase();
    final sanitizedNormalized = sanitized.trim().toLowerCase();
    if (promptNormalized.isNotEmpty && sanitizedNormalized == promptNormalized) {
      return 'Entendi você. Posso te ajudar com mais detalhes se você me disser o objetivo exato.';
    }
    return sanitized;
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
    _notifyListeners();
  }

  ConversationThread _newConversation({bool seed = false}) {
    final now = DateTime.now();
    final formattedMinute = now.minute.toString().padLeft(2, '0');
    return ConversationThread(
      id: now.microsecondsSinceEpoch.toString(),
      title: seed ? 'Conversa inicial' : 'Conversa ${now.day}/${now.month} ${now.hour}:$formattedMinute',
      createdAt: now,
      messages: <ConversationMessage>[],
    );
  }

  void _notifyListeners() {
    if (_listeners.isEmpty) return;
    final snapshot = List<VoidCallback>.from(_listeners);
    for (final listener in snapshot) {
      listener();
    }
  }
}
