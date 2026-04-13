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
  const BarryAssistantShell({
    super.key,
    required this.storage,
    required this.initialSettings,
    this.coordinatorBuilder,
  });

  final AppStorage storage;
  final AssistantSettings initialSettings;
  final ConversationCoordinator Function(AppStorage storage)? coordinatorBuilder;

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

  InferencePolicy get _selectedMode => _coordinator.settings.inferencePolicy;

  void _onCoordinatorChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _coordinator = (widget.coordinatorBuilder != null)
        ? widget.coordinatorBuilder!(widget.storage)
        : ConversationCoordinator(
            storage: widget.storage,
            sttService: LocalSttService(SpeechToText()),
            ttsService: LocalTtsService(FlutterTts()),
            localAi: LocalAiAdapter(),
            remoteAi: RemoteAiClient(NetworkClient(http.Client())),
            zeptoLocal: ZeptoClawLocalExecutor(),
            zeptoRemote: ZeptoClawRemoteClient(NetworkClient(http.Client())),
          );
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 2800))..repeat();
    _coordinator.addListener(_onCoordinatorChanged);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _coordinator.hydrate();
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _coordinator.removeListener(_onCoordinatorChanged);
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

  Future<void> _setExecutionMode(InferencePolicy mode) async {
    await _coordinator.updateSettings(_coordinator.settings.copyWith(inferencePolicy: mode));
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
    if (_coordinator.isBusy || _coordinator.state == AssistantState.listening) return;
    final text = _composerController.text.trim();
    if (text.isEmpty) return;
    _composerController.clear();
    await _coordinator.submitText(text, muteTts: _isVoiceMuted);
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
    setState(() {
      _navOpen = false;
      _dragProgress = 0;
    });
    final updated = await Navigator.of(context).push<AssistantSettings>(
      MaterialPageRoute(builder: (_) => SettingsScreen(initial: _coordinator.settings, client: http.Client())),
    );
    if (updated == null) return;
    await _coordinator.updateSettings(updated);
    if (!mounted) return;
    setState(() => _navOpen = false);
  }

  Future<void> _openAccount() async {
    setState(() {
      _navOpen = false;
      _dragProgress = 0;
    });
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

  String _topLeftText(ConversationThread thread) {
    if (_coordinator.state == AssistantState.listening) {
      if (_coordinator.partialTranscript.trim().isNotEmpty) {
        return 'Ouvindo: ${_coordinator.partialTranscript.trim()}';
      }
      return 'Ouvindo…';
    }
    if (_coordinator.state == AssistantState.processing) return 'Processando solicitação…';
    if (_coordinator.state == AssistantState.speaking) return 'Barry respondendo…';
    if (_coordinator.state == AssistantState.error) return 'Atenção: ocorreu um erro';
    return thread.title;
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
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: navProgress > 0.01,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                      child: Column(
                        children: [
                          _buildTopBar(_topLeftText(thread)),
                          const SizedBox(height: 10),
                          _buildModeSelector(),
                          const SizedBox(height: 8),
                          Expanded(
                            child: Column(
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      const _HudPanel(left: 20, top: 70, title: 'KERNEL.LOAD'),
                                      const _HudPanel(left: 12, bottom: 92, title: 'SYNC.AA'),
                                      const _HudPanel(right: 20, top: 74, title: 'BUFFERING'),
                                      const _HudPanel(right: 18, bottom: 96, title: 'COGNITIVE.ARRAY'),
                                      _LiveCore(
                                        state: _coordinator.state,
                                        animation: _pulseController,
                                        onTap: _toggleListening,
                                      ),
                                    ],
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
              ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                left: -panelWidth + (panelWidth * navProgress),
                top: 0,
                bottom: 0,
                width: panelWidth,
                child: _buildSideNavigation(),
              ),
              Positioned(
                left: 0,
                top: MediaQuery.of(context).size.height * 0.45,
                child: GestureDetector(
                  onTap: () => setState(() {
                    _navOpen = !_navOpen;
                    _dragProgress = _navOpen ? 1 : 0;
                  }),
                  child: Container(
                    key: const Key('shell_nav_toggle'),
                    width: 24,
                    height: 80,
                    decoration: BoxDecoration(
                      color: const Color(0xFF18273A).withValues(alpha: 0.75),
                      borderRadius: const BorderRadius.horizontal(right: Radius.circular(20)),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                    ),
                    child: Center(
                      child: Text(_navOpen ? '<' : '>', style: const TextStyle(fontSize: 18, color: Colors.white70)),
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

  Widget _buildTopBar(String text) {
    return Row(
      children: [
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, letterSpacing: 0.4, fontSize: 18),
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

  Widget _buildModeSelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          _modeChip('Auto', InferencePolicy.hybridPreferLocal),
          _modeChip('KidFlash', InferencePolicy.localOnly),
          _modeChip('Barry', InferencePolicy.remoteOnly),
        ],
      ),
    );
  }

  Widget _modeChip(String label, InferencePolicy policy) {
    final selected = _selectedMode == policy;
    return Expanded(
      child: GestureDetector(
        onTap: () => _setExecutionMode(policy),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF7BC9FF).withValues(alpha: 0.24) : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? const Color(0xFF8FD8FF).withValues(alpha: 0.55) : Colors.transparent),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(color: selected ? Colors.white : Colors.white70, fontWeight: selected ? FontWeight.w600 : FontWeight.w400),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryLayer(ConversationThread thread) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [const Color(0xFF8FCDFF).withValues(alpha: 0.18), const Color(0xFF0D2137).withValues(alpha: 0.2)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Stack(
        children: [
          Positioned(
            right: 12,
            bottom: 10,
            child: Icon(Icons.memory_rounded, color: Colors.white.withValues(alpha: 0.06), size: 120),
          ),
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black, Colors.black, Colors.transparent],
              stops: [0, 0.08, 0.9, 1],
            ).createShader(bounds),
            blendMode: BlendMode.dstIn,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              itemCount: thread.messages.length,
              itemBuilder: (context, index) {
                final m = thread.messages[index];
                final user = m.role == 'user';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    mainAxisAlignment: user ? MainAxisAlignment.end : MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!user)
                        Container(
                          width: 34,
                          height: 34,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                Colors.white.withValues(alpha: 0.88),
                                const Color(0xFF8ED3FF).withValues(alpha: 0.54),
                                const Color(0xFF8ED3FF).withValues(alpha: 0.22),
                              ],
                            ),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                          ),
                          child: const Icon(Icons.auto_awesome, size: 16, color: Color(0xFF0F2A44)),
                        ),
                      Flexible(
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 300),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                          decoration: BoxDecoration(
                            color: user ? const Color(0xFF2E9BFF).withValues(alpha: 0.16) : Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                          ),
                          child: Text(m.text, style: const TextStyle(color: Colors.white70, height: 1.25)),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComposer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 7, 7, 7),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1B2B).withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
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
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF85CCFF).withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(16),
            ),
            child: IconButton(
              onPressed: (_coordinator.isBusy || _coordinator.state == AssistantState.listening) ? null : _sendTypedMessage,
              icon: const Icon(Icons.north_east_rounded),
              color: Colors.white70,
            ),
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
            _navAction(key: const Key('shell_nav_settings'), icon: Icons.tune, label: 'Settings', onTap: _openSettings),
            _navAction(key: const Key('shell_nav_account'), icon: Icons.account_circle, label: 'Conta do usuário', onTap: _openAccount),
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

  Widget _navAction({Key? key, required IconData icon, required String label, required Future<void> Function() onTap}) {
    return ListTile(
      key: key,
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
          center: Alignment(0, -0.2),
          radius: 1.25,
          colors: [Color(0xFF123D6A), Color(0xFF071628), Color(0xFF030914)],
          stops: [0, 0.48, 1],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: 0.1,
              child: CustomPaint(painter: _GridWavePainter()),
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
          final inner = 124 + (state == AssistantState.processing ? 18 : 12) * wave;
          final mid = inner + 38 + 10 * (1 - wave);
          final outer = mid + 38 + 14 * wave;

          return SizedBox(
            width: 370,
            height: 370,
            child: Stack(
              alignment: Alignment.center,
              children: [
                _ring(outer + 24, _accent.withValues(alpha: 0.14), 1.0),
                _ring(outer, _accent.withValues(alpha: 0.2), 1.4),
                _ring(mid, _accent.withValues(alpha: 0.26), 1.3),
                _ring(inner, _accent.withValues(alpha: 0.34), 1.2),
                Container(
                  width: 136 + 10 * wave,
                  height: 136 + 10 * wave,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [Colors.white.withValues(alpha: 0.88), _accent.withValues(alpha: 0.48), _accent.withValues(alpha: 0.12)],
                    ),
                    boxShadow: [BoxShadow(color: _accent.withValues(alpha: 0.45), blurRadius: 60, spreadRadius: 6)],
                  ),
                ),
                Positioned(
                  bottom: 22,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                    ),
                    child: Text(
                      _stateLabel(state),
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.82), letterSpacing: 2, fontSize: 14),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _ring(double size, Color color, double width) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: color, width: width)),
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

class _HudPanel extends StatelessWidget {
  const _HudPanel({this.left, this.right, this.top, this.bottom, required this.title});

  final double? left;
  final double? right;
  final double? top;
  final double? bottom;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left,
      right: right,
      top: top,
      bottom: bottom,
      child: Container(
        width: 96,
        height: 46,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Center(child: Icon(Icons.show_chart, size: 14, color: Colors.white54)),
              ),
            ),
            const SizedBox(height: 2),
            Text(title, style: const TextStyle(fontSize: 8, color: Colors.white54), overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

class _GridWavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF89D0FF).withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;
    for (double y = 40; y < size.height; y += 44) {
      final path = Path();
      path.moveTo(0, y);
      for (double x = 0; x <= size.width; x += 26) {
        path.lineTo(x, y + 6 * math.sin((x / size.width) * math.pi * 4));
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              Colors.white.withValues(alpha: active ? 0.42 : 0.22),
              const Color(0xFF8ED3FF).withValues(alpha: active ? 0.28 : 0.14),
              const Color(0xFF1A3750).withValues(alpha: 0.2),
            ],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: Icon(icon, size: 24, color: Colors.white70),
      ),
    );
  }
}
