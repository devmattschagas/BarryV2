import 'dart:io';
import 'dart:math' as math;

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

class _BarryAssistantShellState extends State<BarryAssistantShell> with SingleTickerProviderStateMixin {
  final TextEditingController _composerController = TextEditingController();
  late final ConversationCoordinator _coordinator;
  late final AnimationController _pulseController;

  bool _isMicMuted = false;
  bool _isVoiceMuted = false;
  bool _navOpen = false;
  double _dragProgress = 0;

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
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 2800))..repeat();
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
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _toggleListening() async {
    if (_isMicMuted) return;
    await _coordinator.toggleListening(confirmTranscript: _confirmTranscript);
    if (!mounted) return;
    setState(() {});
  }

  Future<String?> _confirmTranscript(String text) async {
    final controller = TextEditingController(text: text);
    final confirmed = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0C1724),
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
    await _coordinator.submitText(text, muteTts: _isVoiceMuted);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _createConversation() async {
    await _coordinator.createConversation();
    if (!mounted) return;
    setState(() => _navOpen = false);
  }

  Future<void> _switchConversation(String id) async {
    await _coordinator.switchConversation(id);
    if (!mounted) return;
    setState(() => _navOpen = false);
  }

  Future<void> _openSettings() async {
    final updated = await Navigator.of(context).push<AssistantSettings>(
      MaterialPageRoute(builder: (_) => SettingsScreen(initial: _coordinator.settings, client: http.Client())),
    );
    if (updated == null) return;
    await _coordinator.updateSettings(updated);
    if (!mounted) return;
    setState(() => _navOpen = false);
  }

  Future<void> _openAccount() async {
    final updated = await Navigator.of(context).push<UserProfile>(
      MaterialPageRoute(builder: (_) => AccountScreen(initialProfile: _coordinator.profile)),
    );
    if (updated == null) return;
    await _coordinator.updateProfile(updated);
    if (!mounted) return;
    setState(() => _navOpen = false);
  }

  void _handleHorizontalDragUpdate(DragUpdateDetails details) {
    final panelWidth = MediaQuery.of(context).size.width * 0.74;
    setState(() {
      _dragProgress = (_dragProgress + details.delta.dx / panelWidth).clamp(0.0, 1.0);
    });
  }

  void _handleHorizontalDragEnd(DragEndDetails details) {
    setState(() {
      _navOpen = _dragProgress > 0.5;
      _dragProgress = _navOpen ? 1 : 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_coordinator.conversations.isEmpty) {
      return const MaterialApp(home: Scaffold(body: Center(child: CircularProgressIndicator())));
    }

    final thread = _coordinator.activeConversation;
    final panelWidth = MediaQuery.of(context).size.width * 0.74;
    final navProgress = _navOpen ? 1.0 : _dragProgress;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: GestureDetector(
          onHorizontalDragUpdate: _handleHorizontalDragUpdate,
          onHorizontalDragEnd: _handleHorizontalDragEnd,
          child: Stack(
            children: [
              const _AtmosphericBackground(),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                left: -panelWidth + (panelWidth * navProgress),
                top: 0,
                bottom: 0,
                width: panelWidth,
                child: _buildSideNavigation(),
              ),
              Positioned.fill(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  transform: Matrix4.translationValues(panelWidth * navProgress * 0.08, 0, 0),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                      child: Column(
                        children: [
                          _buildTopBar(thread.title),
                          const SizedBox(height: 12),
                          Expanded(
                            child: Column(
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: Center(
                                    child: _LiveCore(
                                      state: _coordinator.state,
                                      animation: _pulseController,
                                      onTap: _toggleListening,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 4,
                                  child: _buildHistoryLayer(thread),
                                ),
                                _buildComposer(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                top: MediaQuery.of(context).size.height * 0.44,
                child: GestureDetector(
                  onTap: () => setState(() {
                    _navOpen = !_navOpen;
                    _dragProgress = _navOpen ? 1 : 0;
                  }),
                  child: Container(
                    width: 24,
                    height: 80,
                    decoration: BoxDecoration(
                      color: const Color(0xFF18273A).withValues(alpha: 0.75),
                      borderRadius: const BorderRadius.horizontal(right: Radius.circular(20)),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                    ),
                    child: Center(
                      child: Text(
                        _navOpen ? '<' : '>',
                        style: const TextStyle(fontSize: 18, color: Colors.white70),
                      ),
                    ),
                  ),
                ),
              ),
              if (_coordinator.lastError.isNotEmpty)
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 94,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.redAccent.withValues(alpha: 0.35)),
                    ),
                    child: Text(_coordinator.lastError, style: const TextStyle(color: Colors.white70)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(String title) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, letterSpacing: 0.5),
          ),
        ),
        _TopIconButton(
          icon: _isMicMuted ? Icons.mic_off : Icons.mic,
          active: !_isMicMuted,
          onPressed: () => setState(() => _isMicMuted = !_isMicMuted),
        ),
        const SizedBox(width: 8),
        _TopIconButton(
          icon: _isVoiceMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
          active: !_isVoiceMuted,
          onPressed: () => setState(() => _isVoiceMuted = !_isVoiceMuted),
        ),
      ],
    );
  }

  Widget _buildHistoryLayer(ConversationThread thread) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white.withValues(alpha: 0.12), Colors.white.withValues(alpha: 0.03)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: ShaderMask(
        shaderCallback: (bounds) {
          return const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black, Colors.black, Colors.transparent],
            stops: [0.0, 0.12, 0.88, 1.0],
          ).createShader(bounds);
        },
        blendMode: BlendMode.dstIn,
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          itemCount: thread.messages.length,
          itemBuilder: (context, index) {
            final m = thread.messages[index];
            final user = m.role == 'user';
            return Align(
              alignment: user ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 5),
                constraints: const BoxConstraints(maxWidth: 300),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: user ? const Color(0xFF2E9BFF).withValues(alpha: 0.16) : Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Text(m.text, style: const TextStyle(color: Colors.white70, height: 1.25)),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildComposer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 7, 7, 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _composerController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Enviar mensagem para Barry',
                hintStyle: TextStyle(color: Colors.white54),
                border: InputBorder.none,
                isCollapsed: true,
              ),
              onSubmitted: (_) => _sendTypedMessage(),
            ),
          ),
          IconButton(
            onPressed: _sendTypedMessage,
            icon: const Icon(Icons.north_east_rounded),
            color: Colors.white70,
          ),
        ],
      ),
    );
  }

  Widget _buildSideNavigation() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0A1624).withValues(alpha: 0.96),
        border: Border(right: BorderSide(color: Colors.white.withValues(alpha: 0.12))),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            ListTile(
              leading: CircleAvatar(
                backgroundImage: _coordinator.profile.avatarPath.isEmpty ? null : FileImage(File(_coordinator.profile.avatarPath)),
                child: _coordinator.profile.avatarPath.isEmpty ? const Icon(Icons.person) : null,
              ),
              title: Text(_coordinator.profile.name),
              subtitle: const Text('Perfil local'),
            ),
            const SizedBox(height: 8),
            _navAction(icon: Icons.add, label: 'Nova conversa', onTap: _createConversation),
            _navAction(icon: Icons.tune, label: 'Settings', onTap: _openSettings),
            _navAction(icon: Icons.account_circle, label: 'Conta do usuário', onTap: _openAccount),
            const Divider(height: 28),
            ..._coordinator.conversations.map(
              (c) => ListTile(
                dense: true,
                selected: c.id == _coordinator.activeConversationId,
                title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => _switchConversation(c.id),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _navAction({required IconData icon, required String label, required Future<void> Function() onTap}) {
    return ListTile(
      dense: true,
      leading: Icon(icon, color: Colors.white70),
      title: Text(label),
      onTap: onTap,
    );
  }
}

class _AtmosphericBackground extends StatelessWidget {
  const _AtmosphericBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.12),
          radius: 1.2,
          colors: [Color(0xFF1A3E66), Color(0xFF07111D), Color(0xFF04080F)],
          stops: [0.0, 0.46, 1.0],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: -40,
            right: -40,
            bottom: 130,
            child: Container(
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF64C3FF).withValues(alpha: 0.07),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF64C3FF).withValues(alpha: 0.13),
                    blurRadius: 120,
                    spreadRadius: 20,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveCore extends StatelessWidget {
  const _LiveCore({required this.state, required this.animation, required this.onTap});

  final AssistantState state;
  final Animation<double> animation;
  final VoidCallback onTap;

  Color get _accent {
    switch (state) {
      case AssistantState.listening:
        return const Color(0xFF6BE8FF);
      case AssistantState.processing:
        return const Color(0xFF8F96FF);
      case AssistantState.speaking:
        return const Color(0xFF78FFBA);
      case AssistantState.error:
        return const Color(0xFFFF6B8B);
      case AssistantState.idle:
        return const Color(0xFF62B1FF);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, child) {
          final wave = 0.5 + 0.5 * math.sin(animation.value * math.pi * 2);
          final inner = 104 + (state == AssistantState.processing ? 16 : 10) * wave;
          final mid = inner + 32 + 9 * (1 - wave);
          final outer = mid + 30 + 14 * wave;

          return SizedBox(
            width: 320,
            height: 320,
            child: Stack(
              alignment: Alignment.center,
              children: [
                _ring(outer, _accent.withValues(alpha: 0.18)),
                _ring(mid, _accent.withValues(alpha: 0.26)),
                _ring(inner, _accent.withValues(alpha: 0.32)),
                Container(
                  width: 112 + 8 * wave,
                  height: 112 + 8 * wave,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [Colors.white.withValues(alpha: 0.85), _accent.withValues(alpha: 0.45), _accent.withValues(alpha: 0.08)],
                    ),
                    boxShadow: [
                      BoxShadow(color: _accent.withValues(alpha: 0.45), blurRadius: 44, spreadRadius: 4),
                    ],
                  ),
                ),
                Positioned(
                  bottom: 30,
                  child: Text(
                    _stateLabel(state),
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.82), letterSpacing: 1.8, fontSize: 12),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _ring(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 1.2),
      ),
    );
  }

  String _stateLabel(AssistantState state) {
    switch (state) {
      case AssistantState.idle:
        return 'IDLE';
      case AssistantState.listening:
        return 'OUVINDO';
      case AssistantState.processing:
        return 'PROCESSANDO';
      case AssistantState.speaking:
        return 'FALANDO';
      case AssistantState.error:
        return 'ERRO';
    }
  }
}

class _TopIconButton extends StatelessWidget {
  const _TopIconButton({required this.icon, required this.active, required this.onPressed});

  final IconData icon;
  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onPressed,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: active ? 0.14 : 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: Icon(icon, size: 18, color: Colors.white70),
      ),
    );
  }
}
