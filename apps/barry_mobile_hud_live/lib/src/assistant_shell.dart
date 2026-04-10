import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart';

import 'models.dart';
import 'runtime/conversation_coordinator.dart';
import 'runtime/local_ai_adapter.dart';
import 'runtime/network_client.dart';
import 'runtime/remote_ai_client.dart';
import 'runtime/stt_local_service.dart';
import 'runtime/tts_local_service.dart';
import 'runtime/zeptoclaw_services.dart';
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
  final TextEditingController _composerController = TextEditingController();
  late final ConversationCoordinator _coordinator;

  @override
  void initState() {
    super.initState();
    _coordinator = ConversationCoordinator(
      storage: widget.storage,
      sttService: LocalSttService(SpeechToText()),
      ttsService: LocalTtsService(FlutterTts()),
      localAi: LocalAiAdapter(),
      remoteAi: RemoteAiClient(NetworkClient(http.Client())),
      zeptoLocal: ZeptoClawLocalExecutor(),
      zeptoRemote: ZeptoClawRemoteClient(NetworkClient(http.Client())),
    );
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _coordinator.hydrate();
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _composerController.dispose();
    super.dispose();
  }

  Future<void> _toggleListening() async {
    await _coordinator.toggleListening(confirmTranscript: _confirmTranscript);
    if (!mounted) return;
    setState(() {});
  }

  Future<String?> _confirmTranscript(String text) async {
    final controller = TextEditingController(text: text);
    final confirmed = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar transcript'),
        content: TextField(controller: controller, maxLines: 4),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Enviar')),
        ],
      ),
    );
    controller.dispose();
    return confirmed;
  }

  Future<void> _sendTypedMessage() async {
    final text = _composerController.text.trim();
    if (text.isEmpty) return;
    _composerController.clear();
    await _coordinator.submitText(text);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _createConversation() async {
    await _coordinator.createConversation();
    if (!mounted) return;
    setState(() {});
    Navigator.of(context).pop();
  }

  Future<void> _switchConversation(String id) async {
    await _coordinator.switchConversation(id);
    if (!mounted) return;
    setState(() {});
    Navigator.of(context).pop();
  }

  Future<void> _openSettings() async {
    final updated = await Navigator.of(context).push<AssistantSettings>(
      MaterialPageRoute(builder: (_) => SettingsScreen(initial: _coordinator.settings, client: http.Client())),
    );
    if (updated == null) return;
    await _coordinator.updateSettings(updated);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openAccount() async {
    final updated = await Navigator.of(context).push<UserProfile>(
      MaterialPageRoute(builder: (_) => AccountScreen(initialProfile: _coordinator.profile)),
    );
    if (updated == null) return;
    await _coordinator.updateProfile(updated);
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_coordinator.conversations.isEmpty) {
      return const MaterialApp(home: Scaffold(body: Center(child: CircularProgressIndicator())));
    }

    final thread = _coordinator.activeConversation;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        drawer: Drawer(
          child: ListView(
            children: [
              UserAccountsDrawerHeader(
                accountName: Text(_coordinator.profile.name),
                accountEmail: const Text('Perfil local'),
                currentAccountPicture: CircleAvatar(
                  backgroundImage: _coordinator.profile.avatarPath.isEmpty ? null : FileImage(File(_coordinator.profile.avatarPath)),
                  child: _coordinator.profile.avatarPath.isEmpty ? const Icon(Icons.person) : null,
                ),
              ),
              ListTile(leading: const Icon(Icons.add), title: const Text('Nova conversa'), onTap: _createConversation),
              ListTile(leading: const Icon(Icons.tune), title: const Text('Settings'), onTap: _openSettings),
              ListTile(leading: const Icon(Icons.account_circle), title: const Text('Conta do usuário'), onTap: _openAccount),
              const Divider(),
              ..._coordinator.conversations.map(
                (c) => ListTile(
                  selected: c.id == _coordinator.activeConversationId,
                  title: Text(c.title),
                  onTap: () => _switchConversation(c.id),
                ),
              ),
            ],
          ),
        ),
        appBar: AppBar(
          title: Text(thread.title),
          actions: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Chip(label: Text(_coordinator.state.name)),
            ),
          ],
        ),
        body: Column(
          children: [
            if (_coordinator.partialTranscript.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                color: Colors.cyan.withValues(alpha: 0.15),
                child: Text(_coordinator.partialTranscript),
              ),
            if (_coordinator.lastError.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(_coordinator.lastError, style: const TextStyle(color: Colors.redAccent)),
              ),
            Expanded(
              child: ListView.builder(
                itemCount: thread.messages.length,
                itemBuilder: (context, index) {
                  final m = thread.messages[index];
                  final user = m.role == 'user';
                  return Align(
                    alignment: user ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.all(8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: user ? Colors.blue.withValues(alpha: 0.25) : Colors.green.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(m.text),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.large(
          onPressed: _toggleListening,
          child: Icon(_coordinator.state == AssistantState.listening ? Icons.stop : Icons.mic),
        ),
        bottomNavigationBar: SafeArea(
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _composerController,
                  decoration: const InputDecoration(hintText: 'Escreva para Barry', contentPadding: EdgeInsets.all(10)),
                ),
              ),
              IconButton(onPressed: _sendTypedMessage, icon: const Icon(Icons.send)),
            ],
          ),
        ),
      ),
    );
  }
}
