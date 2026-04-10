import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class AppStorage {
  static const _settingsKey = 'assistant_settings_v2';
  static const _conversationsKey = 'assistant_conversations_v1';
  static const _activeConversationKey = 'assistant_active_conversation_v1';
  static const _profileKey = 'assistant_user_profile_v1';
  static const _llmTokenKey = 'assistant_llm_token';
  static const _sttTokenKey = 'assistant_stt_token';
  static const _ttsTokenKey = 'assistant_tts_token';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  Future<AssistantSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_settingsKey);
    final fromPrefs = raw == null
        ? AssistantSettings.defaults
        : AssistantSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    return fromPrefs.copyWith(
      llmApiKey: await _secureStorage.read(key: _llmTokenKey) ?? '',
      sttApiKey: await _secureStorage.read(key: _sttTokenKey) ?? '',
      ttsApiKey: await _secureStorage.read(key: _ttsTokenKey) ?? '',
    );
  }

  Future<void> saveSettings(AssistantSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_settingsKey, jsonEncode(settings.toJson()));
    await _secureStorage.write(key: _llmTokenKey, value: settings.llmApiKey);
    await _secureStorage.write(key: _sttTokenKey, value: settings.sttApiKey);
    await _secureStorage.write(key: _ttsTokenKey, value: settings.ttsApiKey);
  }

  Future<List<ConversationThread>> loadConversations() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_conversationsKey);
    if (raw == null) return <ConversationThread>[];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(ConversationThread.fromJson)
        .toList(growable: false);
  }

  Future<void> saveConversations(List<ConversationThread> conversations) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = conversations.map((e) => e.toJson()).toList(growable: false);
    await prefs.setString(_conversationsKey, jsonEncode(encoded));
  }

  Future<String?> loadActiveConversationId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_activeConversationKey);
  }

  Future<void> saveActiveConversationId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeConversationKey, id);
  }

  Future<UserProfile> loadUserProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_profileKey);
    if (raw == null) return UserProfile.defaults;
    return UserProfile.fromJson(raw);
  }

  Future<void> saveUserProfile(UserProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profileKey, jsonEncode(profile.toJson()));
  }
}
