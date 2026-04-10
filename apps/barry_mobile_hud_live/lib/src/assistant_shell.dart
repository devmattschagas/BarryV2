import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'models.dart';
import 'screens/account_screen.dart';
import 'screens/settings_screen.dart';
import 'storage.dart';

class BarryAssistantShell extends StatefulWidget {
  const BarryAssistantShell({super.key, required this.storage, required this.initialSettings});

  final AppStorage storage;
  final AssistantSettings initialSettings;

  @override
  State<BarryAssistantShell> createState() => _BarryAssistantShellState();
}

class _BarryAssistantShellState extends State<BarryAssistantShell> {
  final SpeechToText _speech = SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final http.Client _client = http.Client();
  final TextEditingController _composerController = TextEditingController();

  late AssistantSettings _settings;
  AssistantState _state = AssistantState.idle;
  String _partialTranscript = '';
  String _error = '';
  List<ConversationThread> _conversations = <ConversationThread>[];
  String? _activeConversationId;
  UserProfile _profile = UserProfile.defaults;

  ConversationThread get _activeConversation => _conversations.firstWhere(
        (c) => c.id == _activeConversationId,
        orElse: () => _conversations.first,
      );

  @override
  void initState() {
    super.initState();
    _settings = widget.initialSettings;
    unawaited(_hydrate());
  }

  Future<void> _hydrate() async {
    final loadedConversations = await widget.storage.loadConversations();
    final loadedActive = await widget.storage.loadActiveConversationId();
    final loadedProfile = await widget.storage.loadUserProfile();
    final seeded = loadedConversations.isEmpty ? [_newConversation(seed: true)] : loadedConversations;

    if (!mounted) return;
    setState(() {
      _conversations = seeded;
      _activeConversationId = loadedActive ?? seeded.first.id;
      _profile = loadedProfile;
    });
  }

  @override
  void dispose() {
    _client.close();
    _speech.stop();
    _tts.stop();
    _composerController.dispose();
    super.dispose();
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

  Future<void> _createConversation() async {
    final thread = _newConversation();
    setState(() {
      _conversations = [thread, ..._conversations];
      _activeConversationId = thread.id;
    });
    await widget.storage.saveConversations(_conversations);
    await widget.storage.saveActiveConversationId(thread.id);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _switchConversation(String id) async {
    setState(() => _activeConversationId = id);
    await widget.storage.saveActiveConversationId(id);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _openSettings() async {
    final updated = await Navigator.of(context).push<AssistantSettings>(
      MaterialPageRoute(builder: (_) => SettingsScreen(initial: _settings, client: _client)),
    );
    if (updated == null) return;
    setState(() => _settings = updated);
    await widget.storage.saveSettings(updated);
  }

  Future<void> _openAccount() async {
    final updated = await Navigator.of(context).push<UserProfile>(
      MaterialPageRoute(builder: (_) => AccountScreen(initialProfile: _profile)),
    );
    if (updated == null) return;
    setState(() => _profile = updated);
    await widget.storage.saveUserProfile(updated);
  }

  Future<void> _toggleListening() async {
    if (_state == AssistantState.listening) {
      await _speech.stop();
      setState(() => _state = AssistantState.idle);
      return;
    }

    final available = await _speech.initialize(onError: _onSpeechError);
    if (!available) {
      setState(() {
        _state = AssistantState.error;
        _error = 'STT não disponível no dispositivo.';
      });
      return;
    }

    setState(() {
      _state = AssistantState.listening;
      _partialTranscript = '';
      _error = '';
    });

    await _speech.listen(
      onResult: _onSpeechResult,
      partialResults: true,
      cancelOnError: true,
      listenMode: ListenMode.dictation,
    );
  }

  void _onSpeechError(SpeechRecognitionError error) {
    if (!mounted) return;
    setState(() {
      _state = AssistantState.error;
      _error = 'Erro STT: ${error.errorMsg}';
    });
  }

  Future<void> _onSpeechResult(SpeechRecognitionResult result) async {
    setState(() => _partialTranscript = result.recognizedWords);
    if (!result.finalResult || result.recognizedWords.trim().isEmpty) {
      return;
    }

    final recognizedText = result.recognizedWords.trim();
    if (_settings.confirmTranscriptBeforeSend) {
      final edited = await _confirmTranscript(recognizedText);
      if (edited == null || edited.trim().isEmpty) {
        setState(() => _state = AssistantState.idle);
        return;
      }
      await _submitUserText(edited.trim());
      return;
    }
    await _submitUserText(recognizedText);
  }

  Future<String?> _confirmTranscript(String text) async {
    final controller = TextEditingController(text: text);
    final confirmed = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Confirmar transcript'),
          content: TextField(
            controller: controller,
            maxLines: 4,
            autofocus: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Edite antes de enviar',
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Enviar')),
          ],
        );
      },
    );
    controller.dispose();
    return confirmed;
  }

  Future<void> _sendTypedMessage() async {
    final text = _composerController.text.trim();
    if (text.isEmpty) return;
    _composerController.clear();
    await _submitUserText(text);
  }

  Future<void> _submitUserText(String text) async {
    final now = DateTime.now();
    final userMessage = ConversationMessage(
      id: now.microsecondsSinceEpoch.toString(),
      role: 'user',
      text: text,
      timestamp: now,
    );

    final thread = _activeConversation;
    final updatedThread = thread.copyWith(
      title: thread.messages.isEmpty ? _deriveTitle(text) : thread.title,
      messages: [...thread.messages, userMessage],
    );

    _replaceThread(updatedThread);
    setState(() {
      _state = AssistantState.processing;
      _partialTranscript = text;
    });

    final replyText = await _queryLlm(updatedThread.messages);
    if (!mounted) return;

    if (replyText.isEmpty) {
      setState(() {
        _state = AssistantState.error;
        _error = 'Sem resposta do assistente. Verifique Settings.';
      });
      return;
    }

    final assistantMessage = ConversationMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      role: 'assistant',
      text: replyText,
      timestamp: DateTime.now(),
    );

    _replaceThread(updatedThread.copyWith(messages: [...updatedThread.messages, assistantMessage]));

    setState(() => _state = AssistantState.speaking);
    await _tts.stop();
    await _tts.setLanguage('pt-BR');
    await _tts.setSpeechRate(0.45);
    await _tts.speak(replyText);

    if (!mounted) return;
    setState(() => _state = AssistantState.idle);
  }

  String _deriveTitle(String text) {
    if (text.length <= 28) return text;
    return '${text.substring(0, 28)}…';
  }

  void _replaceThread(ConversationThread updated) {
    final replaced = _conversations.map((c) => c.id == updated.id ? updated : c).toList(growable: false);
    setState(() => _conversations = replaced);
    unawaited(widget.storage.saveConversations(replaced));
  }

  Future<String> _queryLlm(List<ConversationMessage> messages) async {
    if (_settings.llmBaseUrl.isEmpty) return '';

    final payload = {
      'model': _settings.model,
      'messages': [
        {'role': 'system', 'content': 'Você é Barry, um assistente de voz amigável e objetivo.'},
        ...messages.take(14).map((m) => {'role': m.role, 'content': m.text}),
      ],
      'temperature': 0.25,
    };

    final response = await _client
        .post(
          Uri.parse(_settings.llmBaseUrl),
          headers: {
            'Content-Type': 'application/json',
            if (_settings.llmApiKey.isNotEmpty) 'Authorization': 'Bearer ${_settings.llmApiKey}',
          },
          body: jsonEncode(payload),
        )
        .timeout(Duration(milliseconds: _settings.timeoutMs));

    if (response.statusCode < 200 || response.statusCode >= 300) return '';
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = decoded['choices'];
    if (choices is List && choices.isNotEmpty) {
      final first = choices.first as Map<String, dynamic>;
      final message = first['message'] as Map<String, dynamic>?;
      return (message?['content'] as String? ?? '').trim();
    }
    return (decoded['text'] as String? ?? '').trim();
  }

  @override
  Widget build(BuildContext context) {
    final thread = _activeConversation;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        drawer: _HudDrawer(
          profile: _profile,
          conversations: _conversations,
          activeId: _activeConversationId,
          onNewConversation: _createConversation,
          onSelectConversation: _switchConversation,
          onOpenSettings: _openSettings,
          onOpenAccount: _openAccount,
        ),
        appBar: AppBar(
          title: Text(thread.title),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: _StatusPill(state: _state),
            ),
          ],
        ),
        body: Stack(
          children: [
            const Positioned.fill(child: _HudBackdrop()),
            Column(
              children: [
                if (_partialTranscript.isNotEmpty)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.fromLTRB(12, 10, 12, 2),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0x3300E5FF),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0x6600E5FF)),
                    ),
                    child: Text('Você: $_partialTranscript'),
                  ),
                if (_state == AssistantState.error)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: Text(_error, style: const TextStyle(color: Colors.redAccent)),
                  ),
                Expanded(
                  child: ListView.builder(
                    reverse: false,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                    itemCount: thread.messages.length,
                    itemBuilder: (context, index) => _MessageBubble(message: thread.messages[index]),
                  ),
                ),
              ],
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.large(
          onPressed: _toggleListening,
          backgroundColor: _state == AssistantState.listening ? const Color(0xFFEF5350) : const Color(0xFF00BCD4),
          child: Icon(_state == AssistantState.listening ? Icons.stop : Icons.mic),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xAA0A111D),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0x5500E5FF)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _composerController,
                      minLines: 1,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        hintText: 'Escreva para o Barry...',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      onSubmitted: (_) => _sendTypedMessage(),
                    ),
                  ),
                  IconButton(onPressed: _sendTypedMessage, icon: const Icon(Icons.send_rounded)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HudDrawer extends StatelessWidget {
  const _HudDrawer({
    required this.profile,
    required this.conversations,
    required this.activeId,
    required this.onNewConversation,
    required this.onSelectConversation,
    required this.onOpenSettings,
    required this.onOpenAccount,
  });

  final UserProfile profile;
  final List<ConversationThread> conversations;
  final String? activeId;
  final Future<void> Function() onNewConversation;
  final Future<void> Function(String id) onSelectConversation;
  final Future<void> Function() onOpenSettings;
  final Future<void> Function() onOpenAccount;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF050A14), Color(0xFF0A1422)],
          ),
        ),
        child: Column(
          children: [
            DrawerHeader(
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundImage: profile.avatarPath.isEmpty ? null : FileImage(File(profile.avatarPath)),
                    child: profile.avatarPath.isEmpty ? const Icon(Icons.person) : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(profile.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.add_comment),
              title: const Text('Nova conversa'),
              onTap: onNewConversation,
            ),
            ListTile(
              leading: const Icon(Icons.tune),
              title: const Text('Settings'),
              onTap: onOpenSettings,
            ),
            ListTile(
              leading: const Icon(Icons.account_circle),
              title: const Text('Conta do usuário'),
              onTap: onOpenAccount,
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Conversas', style: TextStyle(color: Color(0xFF80DEEA), fontWeight: FontWeight.w700)),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: conversations.length,
                itemBuilder: (context, index) {
                  final convo = conversations[index];
                  final selected = convo.id == activeId;
                  return ListTile(
                    selected: selected,
                    title: Text(convo.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      convo.messages.isEmpty ? 'Sem mensagens' : convo.messages.last.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => onSelectConversation(convo.id),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final ConversationMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isUser ? const Color(0x5534C3FF) : const Color(0x3326A69A),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isUser ? 16 : 4),
              bottomRight: Radius.circular(isUser ? 4 : 16),
            ),
            border: Border.all(
              color: isUser ? const Color(0x9900E5FF) : const Color(0x9964FFDA),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(isUser ? 'Você' : 'Barry', style: const TextStyle(fontSize: 11, color: Colors.white70)),
              const SizedBox(height: 4),
              Text(message.text),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.state});

  final AssistantState state;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (state) {
      AssistantState.idle => ('idle', const Color(0xFF90A4AE)),
      AssistantState.listening => ('ouvindo', const Color(0xFF00E5FF)),
      AssistantState.processing => ('processando', const Color(0xFFFFC400)),
      AssistantState.speaking => ('falando', const Color(0xFF69F0AE)),
      AssistantState.error => ('erro', const Color(0xFFEF5350)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withValues(alpha: 0.18),
        border: Border.all(color: color.withValues(alpha: 0.75)),
      ),
      child: Text(label),
    );
  }
}

class _HudBackdrop extends StatelessWidget {
  const _HudBackdrop();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _HudPainter(),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF03070F), Color(0xFF091220)],
          ),
        ),
      ),
    );
  }
}

class _HudPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = const Color(0x4400E5FF);

    final center = Offset(size.width * 0.82, size.height * 0.15);
    final rect = Rect.fromCircle(center: center, radius: 72);
    canvas.drawArc(rect, -0.4, 1.7, false, line);
    canvas.drawArc(rect.inflate(22), 2.6, 1.2, false, line);

    final leftPath = Path()
      ..moveTo(0, size.height * 0.22)
      ..lineTo(size.width * 0.24, size.height * 0.22)
      ..lineTo(size.width * 0.2, size.height * 0.26)
      ..lineTo(0, size.height * 0.26)
      ..close();
    canvas.drawPath(
      leftPath,
      Paint()
        ..style = PaintingStyle.fill
        ..color = const Color(0x2219D7FF),
    );
    canvas.drawPath(leftPath, line);

    final grid = Paint()
      ..strokeWidth = 0.7
      ..color = const Color(0x2200E5FF);
    for (double y = size.height * 0.35; y < size.height; y += 26) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
