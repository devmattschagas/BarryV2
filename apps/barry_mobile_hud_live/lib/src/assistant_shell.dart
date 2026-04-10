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
    if (!result.finalResult || result.recognizedWords.trim().isEmpty) return;

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
      barrierColor: Colors.black87,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF09111E), Color(0xFF101B2A)],
              ),
              border: Border.all(color: const Color(0x7700E5FF)),
              boxShadow: const [BoxShadow(color: Color(0x5500E5FF), blurRadius: 18)],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Confirmar transcript', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                TextField(
                  controller: controller,
                  maxLines: 4,
                  autofocus: true,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    labelText: 'Edite antes de enviar',
                    fillColor: const Color(0x33131E2D),
                    filled: true,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
                    const SizedBox(width: 8),
                    FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Enviar')),
                  ],
                ),
              ],
            ),
          ),
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

  String _deriveTitle(String text) => text.length <= 28 ? text : '${text.substring(0, 28)}…';

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
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF050B14),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00D9FF), brightness: Brightness.dark),
      ),
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
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(thread.title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const Text('Barry Assistant', style: TextStyle(fontSize: 12, color: Colors.white70)),
            ],
          ),
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
            Positioned.fill(
              child: Column(
                children: [
                  if (_partialTranscript.isNotEmpty)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.fromLTRB(12, 8, 12, 2),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0x3319D8FF), Color(0x2215B7D3)]),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0x8800E5FF)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.graphic_eq, color: Color(0xFF80DEEA), size: 16),
                          const SizedBox(width: 8),
                          Expanded(child: Text(_partialTranscript, maxLines: 2, overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                    ),
                  if (_state == AssistantState.error)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(_error, style: const TextStyle(color: Colors.redAccent)),
                      ),
                    ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                      itemCount: thread.messages.length,
                      itemBuilder: (context, index) => _MessageBubble(message: thread.messages[index]),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        floatingActionButton: _VoiceActionButton(state: _state, onTap: _toggleListening),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: _ComposerBar(controller: _composerController, onSend: _sendTypedMessage),
          ),
        ),
      ),
    );
  }
}

class _ComposerBar extends StatelessWidget {
  const _ComposerBar({required this.controller, required this.onSend});

  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: _BevelClipper(),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xCC0D1727), Color(0xDD0A111D)]),
          border: Border.all(color: const Color(0x6600E5FF)),
          boxShadow: const [BoxShadow(color: Color(0x3300E5FF), blurRadius: 12)],
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Fale ou escreva com Barry…',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                onSubmitted: (_) => onSend(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(onPressed: onSend, icon: const Icon(Icons.arrow_upward_rounded)),
            ),
          ],
        ),
      ),
    );
  }
}

class _VoiceActionButton extends StatelessWidget {
  const _VoiceActionButton({required this.state, required this.onTap});

  final AssistantState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isListening = state == AssistantState.listening;
    final color = isListening ? const Color(0xFFFF5252) : const Color(0xFF00D9FF);
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 18)],
      ),
      child: FloatingActionButton.large(
        onPressed: onTap,
        elevation: 0,
        backgroundColor: const Color(0xFF091628),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999), side: BorderSide(color: color, width: 2)),
        child: Icon(isListening ? Icons.stop : Icons.mic, color: color),
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
      width: MediaQuery.of(context).size.width * 0.84,
      backgroundColor: Colors.transparent,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xEE040A14), Color(0xEE0C1626)]),
          border: Border(right: BorderSide(color: Color(0x6600E5FF))),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 44, 16, 16),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: const Color(0x5500E5FF).withValues(alpha: 0.5))),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0x7700E5FF))),
                    child: CircleAvatar(
                      radius: 28,
                      backgroundImage: profile.avatarPath.isEmpty ? null : FileImage(File(profile.avatarPath)),
                      child: profile.avatarPath.isEmpty ? const Icon(Icons.person) : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(profile.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        const Text('Perfil local', style: TextStyle(fontSize: 11, color: Colors.white70)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _DrawerAction(icon: Icons.add_comment, label: 'Nova conversa', onTap: onNewConversation),
            _DrawerAction(icon: Icons.tune, label: 'Settings', onTap: onOpenSettings),
            _DrawerAction(icon: Icons.account_circle, label: 'Conta do usuário', onTap: onOpenAccount),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
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
                  return InkWell(
                    onTap: () => onSelectConversation(convo.id),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: selected ? const Color(0x3325C6DA) : const Color(0x111A2433),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: selected ? const Color(0x9900E5FF) : const Color(0x332A3A4F)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(convo.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(
                            convo.messages.isEmpty ? 'Sem mensagens' : convo.messages.last.text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
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

class _DrawerAction extends StatelessWidget {
  const _DrawerAction({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      child: Material(
        color: const Color(0x141A2433),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(icon, size: 18, color: const Color(0xFF80DEEA)),
                const SizedBox(width: 10),
                Text(label),
              ],
            ),
          ),
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
      child: Container(
        constraints: const BoxConstraints(maxWidth: 330),
        margin: const EdgeInsets.only(bottom: 10),
        child: ClipPath(
          clipper: _BevelClipper(invert: isUser),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isUser ? const [Color(0x6623BCE0), Color(0x5532A4FF)] : const [Color(0x5527A89C), Color(0x4436628A)],
              ),
              border: Border.all(color: isUser ? const Color(0x9900E5FF) : const Color(0x8864FFDA)),
              boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 6)],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isUser ? 'Você' : 'Barry', style: const TextStyle(fontSize: 11, color: Colors.white70)),
                const SizedBox(height: 5),
                Text(message.text),
              ],
            ),
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
        gradient: LinearGradient(colors: [color.withValues(alpha: 0.2), color.withValues(alpha: 0.08)]),
        border: Border.all(color: color.withValues(alpha: 0.75)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 8, color: color),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
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
      ..strokeWidth = 1.1
      ..color = const Color(0x3300E5FF);

    final center = Offset(size.width * 0.83, size.height * 0.16);
    final rect = Rect.fromCircle(center: center, radius: 78);
    canvas.drawArc(rect, -0.5, 1.9, false, line);
    canvas.drawArc(rect.inflate(22), 2.5, 1.3, false, line);

    final circlePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9
      ..color = const Color(0x2200E5FF);
    canvas.drawCircle(Offset(size.width * 0.18, size.height * 0.12), 40, circlePaint);

    final leftPath = Path()
      ..moveTo(0, size.height * 0.24)
      ..lineTo(size.width * 0.27, size.height * 0.24)
      ..lineTo(size.width * 0.22, size.height * 0.28)
      ..lineTo(0, size.height * 0.28)
      ..close();
    canvas.drawPath(leftPath, Paint()..color = const Color(0x1F19D7FF));
    canvas.drawPath(leftPath, line);

    final grid = Paint()
      ..strokeWidth = 0.7
      ..color = const Color(0x1B00E5FF);
    for (double y = size.height * 0.35; y < size.height; y += 28) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _BevelClipper extends CustomClipper<Path> {
  const _BevelClipper({this.invert = false});

  final bool invert;

  @override
  Path getClip(Size size) {
    const cut = 12.0;
    if (invert) {
      return Path()
        ..moveTo(cut, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width, size.height - cut)
        ..lineTo(size.width - cut, size.height)
        ..lineTo(0, size.height)
        ..lineTo(0, cut)
        ..close();
    }
    return Path()
      ..moveTo(0, 0)
      ..lineTo(size.width - cut, 0)
      ..lineTo(size.width, cut)
      ..lineTo(size.width, size.height)
      ..lineTo(cut, size.height)
      ..lineTo(0, size.height - cut)
      ..close();
  }

  @override
  bool shouldReclip(covariant _BevelClipper oldClipper) => oldClipper.invert != invert;
}
