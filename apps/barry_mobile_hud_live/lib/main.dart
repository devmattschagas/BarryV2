import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settingsStore = AssistantSettingsStore();
  final settings = await settingsStore.load();
  runApp(BarryAssistantApp(settingsStore: settingsStore, initialSettings: settings));
}

enum AssistantState { idle, listening, processing, speaking, error }

class ConversationTurn {
  ConversationTurn({required this.role, required this.text, required this.timestamp});

  final String role;
  final String text;
  final DateTime timestamp;

  Map<String, dynamic> toJson() => {
        'role': role,
        'text': text,
        'timestamp': timestamp.toIso8601String(),
      };

  factory ConversationTurn.fromJson(Map<String, dynamic> map) => ConversationTurn(
        role: map['role'] as String? ?? 'assistant',
        text: map['text'] as String? ?? '',
        timestamp: DateTime.tryParse(map['timestamp'] as String? ?? '') ?? DateTime.now(),
      );
}

class AssistantSettings {
  const AssistantSettings({
    required this.llmBaseUrl,
    required this.sttBaseUrl,
    required this.ttsBaseUrl,
    required this.memoryBaseUrl,
    required this.llmApiKey,
    required this.sttApiKey,
    required this.ttsApiKey,
    required this.model,
    required this.timeoutMs,
    required this.transport,
  });

  final String llmBaseUrl;
  final String sttBaseUrl;
  final String ttsBaseUrl;
  final String memoryBaseUrl;
  final String llmApiKey;
  final String sttApiKey;
  final String ttsApiKey;
  final String model;
  final int timeoutMs;
  final String transport;

  static const defaults = AssistantSettings(
    llmBaseUrl: '',
    sttBaseUrl: '',
    ttsBaseUrl: '',
    memoryBaseUrl: '',
    llmApiKey: '',
    sttApiKey: '',
    ttsApiKey: '',
    model: 'gpt-4.1-mini',
    timeoutMs: 30000,
    transport: 'https',
  );

  AssistantSettings copyWith({
    String? llmBaseUrl,
    String? sttBaseUrl,
    String? ttsBaseUrl,
    String? memoryBaseUrl,
    String? llmApiKey,
    String? sttApiKey,
    String? ttsApiKey,
    String? model,
    int? timeoutMs,
    String? transport,
  }) {
    return AssistantSettings(
      llmBaseUrl: llmBaseUrl ?? this.llmBaseUrl,
      sttBaseUrl: sttBaseUrl ?? this.sttBaseUrl,
      ttsBaseUrl: ttsBaseUrl ?? this.ttsBaseUrl,
      memoryBaseUrl: memoryBaseUrl ?? this.memoryBaseUrl,
      llmApiKey: llmApiKey ?? this.llmApiKey,
      sttApiKey: sttApiKey ?? this.sttApiKey,
      ttsApiKey: ttsApiKey ?? this.ttsApiKey,
      model: model ?? this.model,
      timeoutMs: timeoutMs ?? this.timeoutMs,
      transport: transport ?? this.transport,
    );
  }

  Map<String, dynamic> toJson() => {
        'llmBaseUrl': llmBaseUrl,
        'sttBaseUrl': sttBaseUrl,
        'ttsBaseUrl': ttsBaseUrl,
        'memoryBaseUrl': memoryBaseUrl,
        'model': model,
        'timeoutMs': timeoutMs,
        'transport': transport,
      };

  factory AssistantSettings.fromJson(Map<String, dynamic> map) => AssistantSettings(
        llmBaseUrl: map['llmBaseUrl'] as String? ?? '',
        sttBaseUrl: map['sttBaseUrl'] as String? ?? '',
        ttsBaseUrl: map['ttsBaseUrl'] as String? ?? '',
        memoryBaseUrl: map['memoryBaseUrl'] as String? ?? '',
        llmApiKey: '',
        sttApiKey: '',
        ttsApiKey: '',
        model: map['model'] as String? ?? 'gpt-4.1-mini',
        timeoutMs: (map['timeoutMs'] as num?)?.toInt() ?? 30000,
        transport: map['transport'] as String? ?? 'https',
      );
}

class AssistantSettingsStore {
  static const _prefsKey = 'assistant_settings_v1';
  static const _historyKey = 'assistant_history_v1';
  static const _llmTokenKey = 'assistant_llm_token';
  static const _sttTokenKey = 'assistant_stt_token';
  static const _ttsTokenKey = 'assistant_tts_token';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  Future<AssistantSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    final fromPrefs = raw == null
        ? AssistantSettings.defaults
        : AssistantSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    return fromPrefs.copyWith(
      llmApiKey: await _secureStorage.read(key: _llmTokenKey) ?? '',
      sttApiKey: await _secureStorage.read(key: _sttTokenKey) ?? '',
      ttsApiKey: await _secureStorage.read(key: _ttsTokenKey) ?? '',
    );
  }

  Future<void> save(AssistantSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonWithoutSecrets = jsonEncode(settings.copyWith(llmApiKey: '', sttApiKey: '', ttsApiKey: '').toJson());
    await prefs.setString(_prefsKey, jsonWithoutSecrets);
    await _secureStorage.write(key: _llmTokenKey, value: settings.llmApiKey);
    await _secureStorage.write(key: _sttTokenKey, value: settings.sttApiKey);
    await _secureStorage.write(key: _ttsTokenKey, value: settings.ttsApiKey);
  }

  Future<List<ConversationTurn>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_historyKey);
    if (raw == null) return <ConversationTurn>[];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(ConversationTurn.fromJson)
        .take(40)
        .toList(growable: false);
  }

  Future<void> saveHistory(List<ConversationTurn> history) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = history.take(40).map((e) => e.toJson()).toList(growable: false);
    await prefs.setString(_historyKey, jsonEncode(payload));
  }
}

class BarryAssistantApp extends StatefulWidget {
  const BarryAssistantApp({super.key, required this.settingsStore, required this.initialSettings});

  final AssistantSettingsStore settingsStore;
  final AssistantSettings initialSettings;

  @override
  State<BarryAssistantApp> createState() => _BarryAssistantAppState();
}

class _BarryAssistantAppState extends State<BarryAssistantApp> {
  late AssistantSettings _settings;
  final SpeechToText _speech = SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final http.Client _client = http.Client();

  AssistantState _state = AssistantState.idle;
  String _partialTranscript = '';
  String _errorText = '';
  String _assistantText = '';
  List<ConversationTurn> _history = <ConversationTurn>[];

  @override
  void initState() {
    super.initState();
    _settings = widget.initialSettings;
    unawaited(_restoreHistory());
  }

  Future<void> _restoreHistory() async {
    final loaded = await widget.settingsStore.loadHistory();
    if (!mounted) return;
    setState(() => _history = loaded);
  }

  @override
  void dispose() {
    _client.close();
    _tts.stop();
    _speech.stop();
    super.dispose();
  }

  Future<void> _toggleListen() async {
    if (_state == AssistantState.listening) {
      await _speech.stop();
      setState(() => _state = AssistantState.idle);
      return;
    }

    final available = await _speech.initialize(
      onError: _onSpeechError,
      onStatus: (value) {
        if (!mounted) return;
        if (value == 'done' && _state == AssistantState.listening) {
          setState(() => _state = AssistantState.idle);
        }
      },
    );

    if (!available) {
      setState(() {
        _state = AssistantState.error;
        _errorText = 'Reconhecimento de voz indisponível no dispositivo.';
      });
      return;
    }

    setState(() {
      _errorText = '';
      _assistantText = '';
      _partialTranscript = '';
      _state = AssistantState.listening;
    });

    await _speech.listen(
      onResult: _onSpeechResult,
      partialResults: true,
      cancelOnError: true,
      listenMode: ListenMode.confirmation,
    );
  }

  Future<void> _onSpeechResult(SpeechRecognitionResult result) async {
    if (!mounted) return;
    setState(() => _partialTranscript = result.recognizedWords);

    if (!result.finalResult || result.recognizedWords.trim().isEmpty) {
      return;
    }

    final userText = result.recognizedWords.trim();
    setState(() {
      _state = AssistantState.processing;
      _history = [
        ..._history,
        ConversationTurn(role: 'user', text: userText, timestamp: DateTime.now()),
      ];
    });

    final reply = await _queryLlm(userText);
    if (!mounted) return;

    if (reply.isEmpty) {
      setState(() {
        _state = AssistantState.error;
        _errorText = 'LLM sem resposta. Confira endpoint/modelo/token no Settings.';
      });
      return;
    }

    setState(() {
      _assistantText = reply;
      _history = [
        ..._history,
        ConversationTurn(role: 'assistant', text: reply, timestamp: DateTime.now()),
      ];
      _state = AssistantState.speaking;
    });
    await widget.settingsStore.saveHistory(_history);
    await _speak(reply);

    if (!mounted) return;
    setState(() => _state = AssistantState.idle);
  }

  void _onSpeechError(SpeechRecognitionError error) {
    if (!mounted) return;
    setState(() {
      _state = AssistantState.error;
      _errorText = 'Erro de STT: ${error.errorMsg}';
    });
  }

  Future<String> _queryLlm(String userText) async {
    if (_settings.llmBaseUrl.trim().isEmpty) return '';

    final uri = Uri.parse(_settings.llmBaseUrl);
    final requestBody = {
      'model': _settings.model,
      'messages': [
        {'role': 'system', 'content': 'Você é Barry, assistente de voz em Android.'},
        ..._history.take(8).map((turn) => {'role': turn.role, 'content': turn.text}),
        {'role': 'user', 'content': userText},
      ],
      'temperature': 0.2,
    };

    final response = await _client
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            if (_settings.llmApiKey.isNotEmpty) 'Authorization': 'Bearer ${_settings.llmApiKey}',
          },
          body: jsonEncode(requestBody),
        )
        .timeout(Duration(milliseconds: _settings.timeoutMs));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      return '';
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = decoded['choices'];
    if (choices is List && choices.isNotEmpty) {
      final first = choices.first as Map<String, dynamic>;
      final message = first['message'] as Map<String, dynamic>?;
      return (message?['content'] as String? ?? '').trim();
    }

    return (decoded['text'] as String? ?? '').trim();
  }

  Future<void> _speak(String text) async {
    await _tts.stop();
    await _tts.setLanguage('pt-BR');
    await _tts.setSpeechRate(0.45);
    await _tts.speak(text);
  }

  Future<void> _openSettings() async {
    final updated = await Navigator.of(context).push<AssistantSettings>(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(settings: _settings, store: widget.settingsStore, client: _client),
      ),
    );
    if (updated == null) return;
    setState(() => _settings = updated);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Barry Assistant'),
          actions: [
            IconButton(onPressed: _openSettings, icon: const Icon(Icons.settings)),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                child: ListTile(
                  title: Text('Estado: ${_state.name}'),
                  subtitle: Text(_state == AssistantState.error ? _errorText : 'Modelo: ${_settings.model}'),
                  trailing: FilledButton.icon(
                    onPressed: _toggleListen,
                    icon: Icon(_state == AssistantState.listening ? Icons.stop : Icons.mic),
                    label: Text(_state == AssistantState.listening ? 'Parar' : 'Ouvir'),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text('Transcript (parcial/final):', style: Theme.of(context).textTheme.titleMedium),
              Text(_partialTranscript.isEmpty ? '—' : _partialTranscript),
              const SizedBox(height: 10),
              Text('Resposta do assistente:', style: Theme.of(context).textTheme.titleMedium),
              Text(_assistantText.isEmpty ? '—' : _assistantText),
              const SizedBox(height: 16),
              Text('Histórico recente', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: _history.length,
                  itemBuilder: (_, index) {
                    final item = _history[index];
                    return ListTile(
                      dense: true,
                      title: Text(item.text),
                      subtitle: Text('${item.role} • ${item.timestamp.toLocal()}'),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.settings,
    required this.store,
    required this.client,
  });

  final AssistantSettings settings;
  final AssistantSettingsStore store;
  final http.Client client;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _llmUrl;
  late final TextEditingController _sttUrl;
  late final TextEditingController _ttsUrl;
  late final TextEditingController _memoryUrl;
  late final TextEditingController _llmToken;
  late final TextEditingController _sttToken;
  late final TextEditingController _ttsToken;
  late final TextEditingController _model;
  late final TextEditingController _timeout;
  String _transport = 'https';
  String _healthText = '';

  @override
  void initState() {
    super.initState();
    _llmUrl = TextEditingController(text: widget.settings.llmBaseUrl);
    _sttUrl = TextEditingController(text: widget.settings.sttBaseUrl);
    _ttsUrl = TextEditingController(text: widget.settings.ttsBaseUrl);
    _memoryUrl = TextEditingController(text: widget.settings.memoryBaseUrl);
    _llmToken = TextEditingController(text: widget.settings.llmApiKey);
    _sttToken = TextEditingController(text: widget.settings.sttApiKey);
    _ttsToken = TextEditingController(text: widget.settings.ttsApiKey);
    _model = TextEditingController(text: widget.settings.model);
    _timeout = TextEditingController(text: widget.settings.timeoutMs.toString());
    _transport = widget.settings.transport;
  }

  @override
  void dispose() {
    _llmUrl.dispose();
    _sttUrl.dispose();
    _ttsUrl.dispose();
    _memoryUrl.dispose();
    _llmToken.dispose();
    _sttToken.dispose();
    _ttsToken.dispose();
    _model.dispose();
    _timeout.dispose();
    super.dispose();
  }

  AssistantSettings _buildSettings() {
    return AssistantSettings(
      llmBaseUrl: _llmUrl.text.trim(),
      sttBaseUrl: _sttUrl.text.trim(),
      ttsBaseUrl: _ttsUrl.text.trim(),
      memoryBaseUrl: _memoryUrl.text.trim(),
      llmApiKey: _llmToken.text.trim(),
      sttApiKey: _sttToken.text.trim(),
      ttsApiKey: _ttsToken.text.trim(),
      model: _model.text.trim().isEmpty ? 'gpt-4.1-mini' : _model.text.trim(),
      timeoutMs: int.tryParse(_timeout.text.trim()) ?? 30000,
      transport: _transport,
    );
  }

  Future<void> _save() async {
    final settings = _buildSettings();
    await widget.store.save(settings);
    if (!mounted) return;
    Navigator.of(context).pop(settings);
  }

  Future<void> _testHealth() async {
    final settings = _buildSettings();
    final checks = <String>[];
    Future<void> check(String label, String url, {String token = ''}) async {
      if (url.isEmpty) {
        checks.add('$label: não configurado');
        return;
      }
      try {
        final response = await widget.client
            .get(
              Uri.parse(url),
              headers: {
                if (token.isNotEmpty) 'Authorization': 'Bearer $token',
              },
            )
            .timeout(Duration(milliseconds: settings.timeoutMs));
        checks.add('$label: HTTP ${response.statusCode}');
      } catch (e) {
        checks.add('$label: falhou ($e)');
      }
    }

    await check('LLM', settings.llmBaseUrl, token: settings.llmApiKey);
    await check('STT', settings.sttBaseUrl, token: settings.sttApiKey);
    await check('TTS', settings.ttsBaseUrl, token: settings.ttsApiKey);
    await check('Memory', settings.memoryBaseUrl);

    if (!mounted) return;
    setState(() => _healthText = checks.join('\n'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _field(_llmUrl, 'LLM base URL / endpoint (chat completions)'),
          _field(_sttUrl, 'STT endpoint/base URL'),
          _field(_ttsUrl, 'TTS endpoint/base URL'),
          _field(_memoryUrl, 'Memory/tools/vision endpoint/base URL'),
          _field(_llmToken, 'LLM API token', secret: true),
          _field(_sttToken, 'STT API token', secret: true),
          _field(_ttsToken, 'TTS API token', secret: true),
          _field(_model, 'Modelo padrão'),
          _field(_timeout, 'Timeout (ms)', keyboardType: TextInputType.number),
          DropdownButtonFormField<String>(
            value: _transport,
            decoration: const InputDecoration(labelText: 'Transporte/protocolo'),
            items: const [
              DropdownMenuItem(value: 'https', child: Text('HTTPS/HTTP')),
              DropdownMenuItem(value: 'websocket', child: Text('WebSocket')),
            ],
            onChanged: (value) => setState(() => _transport = value ?? 'https'),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save), label: const Text('Salvar')),
              OutlinedButton.icon(
                onPressed: _testHealth,
                icon: const Icon(Icons.network_check),
                label: const Text('Testar conectividade'),
              ),
            ],
          ),
          if (_healthText.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(_healthText),
          ],
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool secret = false,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        obscureText: secret,
        keyboardType: keyboardType,
        decoration: InputDecoration(border: const OutlineInputBorder(), labelText: label),
      ),
    );
  }
}
