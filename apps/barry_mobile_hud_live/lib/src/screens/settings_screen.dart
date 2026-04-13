import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.initial,
    required this.client,
  });

  final AssistantSettings initial;
  final http.Client client;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _llmUrl;
  late final TextEditingController _sttUrl;
  late final TextEditingController _ttsUrl;
  late final TextEditingController _memoryUrl;
  late final TextEditingController _model;
  late final TextEditingController _llmToken;
  late final TextEditingController _sttToken;
  late final TextEditingController _ttsToken;
  late final TextEditingController _timeout;
  late final TextEditingController _localModel;
  late final TextEditingController _zeptoRemoteUrl;
  late final TextEditingController _zeptoRemoteToken;

  late bool _confirmTranscript;
  late bool _localModelEnabled;
  late bool _zeptoLocalEnabled;
  late bool _zeptoRemoteEnabled;
  late String _transport;
  late InferencePolicy _policy;

  String _healthStatus = '';

  static const Color _bg = Color(0xFF050C16);

  @override
  void initState() {
    super.initState();
    _llmUrl = TextEditingController(text: widget.initial.llmBaseUrl);
    _sttUrl = TextEditingController(text: widget.initial.sttBaseUrl);
    _ttsUrl = TextEditingController(text: widget.initial.ttsBaseUrl);
    _memoryUrl = TextEditingController(text: widget.initial.memoryBaseUrl);
    _model = TextEditingController(text: widget.initial.model);
    _llmToken = TextEditingController(text: widget.initial.llmApiKey);
    _sttToken = TextEditingController(text: widget.initial.sttApiKey);
    _ttsToken = TextEditingController(text: widget.initial.ttsApiKey);
    _timeout = TextEditingController(text: widget.initial.timeoutMs.toString());
    _localModel = TextEditingController(text: widget.initial.localModel);
    _zeptoRemoteUrl = TextEditingController(text: widget.initial.zeptoRemoteUrl);
    _zeptoRemoteToken = TextEditingController(text: widget.initial.zeptoRemoteApiKey);

    _confirmTranscript = widget.initial.confirmTranscriptBeforeSend;
    _localModelEnabled = widget.initial.localModelEnabled;
    _zeptoLocalEnabled = widget.initial.zeptoLocalEnabled;
    _zeptoRemoteEnabled = widget.initial.zeptoRemoteEnabled;
    _transport = widget.initial.transport;
    _policy = widget.initial.inferencePolicy;
  }

  @override
  void dispose() {
    for (final controller in [_llmUrl, _sttUrl, _ttsUrl, _memoryUrl, _model, _llmToken, _sttToken, _ttsToken, _timeout, _localModel, _zeptoRemoteUrl, _zeptoRemoteToken]) {
      controller.dispose();
    }
    super.dispose();
  }

  AssistantSettings _build() => AssistantSettings(
        llmBaseUrl: _llmUrl.text.trim(),
        sttBaseUrl: _sttUrl.text.trim(),
        ttsBaseUrl: _ttsUrl.text.trim(),
        memoryBaseUrl: _memoryUrl.text.trim(),
        llmApiKey: _llmToken.text.trim(),
        sttApiKey: _sttToken.text.trim(),
        ttsApiKey: _ttsToken.text.trim(),
        model: _model.text.trim().isEmpty ? 'qwen2.5:7b-instruct' : _model.text.trim(),
        timeoutMs: int.tryParse(_timeout.text.trim()) ?? 30000,
        transport: _transport,
        confirmTranscriptBeforeSend: _confirmTranscript,
        localModel: _localModel.text.trim().isEmpty ? 'gemma-4b-it-q4_0' : _localModel.text.trim(),
        localModelEnabled: _localModelEnabled,
        inferencePolicy: _policy,
        zeptoLocalEnabled: _zeptoLocalEnabled,
        zeptoRemoteEnabled: _zeptoRemoteEnabled,
        zeptoRemoteUrl: _zeptoRemoteUrl.text.trim(),
        zeptoRemoteApiKey: _zeptoRemoteToken.text.trim(),
      );

  Future<void> _healthCheck() async {
    final s = _build();
    final result = <String>[];

    Future<void> postProbe(String label, String url, String token, Map<String, dynamic> payload) async {
      if (url.isEmpty) {
        result.add('$label: não configurado');
        return;
      }
      final uri = Uri.tryParse(url);
      if (uri == null || !(uri.isScheme('http') || uri.isScheme('https') || uri.isScheme('ws') || uri.isScheme('wss'))) {
        result.add('$label: URL inválida');
        return;
      }
      if (uri.isScheme('ws') || uri.isScheme('wss')) {
        result.add('$label: WS configurado (probe HTTP ignorado)');
        return;
      }
      try {
        final response = await widget.client
            .post(uri, headers: {'Content-Type': 'application/json', if (token.isNotEmpty) 'Authorization': 'Bearer $token'}, body: '{}')
            .timeout(Duration(milliseconds: s.timeoutMs));
        result.add('$label: HTTP ${response.statusCode}');
      } catch (e) {
        result.add('$label: erro ($e)');
      }
    }

    await postProbe('IA remota', s.llmBaseUrl, s.llmApiKey, {'model': s.model, 'messages': []});
    await postProbe('STT remoto', s.sttBaseUrl, s.sttApiKey, {'audio_b64': ''});
    await postProbe('TTS remoto', s.ttsBaseUrl, s.ttsApiKey, {'text': 'ping'});
    await postProbe('Memória/NOMAD', s.memoryBaseUrl, s.llmApiKey, {'query': 'ping'});
    await postProbe('ZeptoClaw cloud', s.zeptoRemoteUrl, s.zeptoRemoteApiKey, {'command': 'status.read', 'payload': {}});

    if (!mounted) return;
    setState(() => _healthStatus = result.join('\n'));
  }

  void _applyNomadPreset() {
    const base = 'http://127.0.0.1:8080/api';
    setState(() {
      _llmUrl.text = '$base/ollama/chat';
      _memoryUrl.text = '$base/rag/files';
      _sttUrl.text = '';
      _ttsUrl.text = '';
      _model.text = 'gemma3:4b';
      _transport = 'https';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(backgroundColor: _bg, title: const Text('Settings do sistema')),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF071426), Color(0xFF050C16)],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
          _section(
            title: 'Política de inferência',
            child: Column(
              children: [
                DropdownButtonFormField<InferencePolicy>(
                  initialValue: _policy,
                  decoration: _inputDecoration('Modo de execução'),
                  items: const [
                    DropdownMenuItem(value: InferencePolicy.hybridPreferLocal, child: Text('Auto (decide local/remoto)')),
                    DropdownMenuItem(value: InferencePolicy.localOnly, child: Text('KidFlash (força IA local)')),
                    DropdownMenuItem(value: InferencePolicy.remoteOnly, child: Text('Barry (força IA remota)')),
                  ],
                  onChanged: (value) => setState(() => _policy = value ?? InferencePolicy.hybridPreferLocal),
                ),
                _field(_localModel, 'Modelo local Gemma móvel'),
                SwitchListTile(
                  value: _localModelEnabled,
                  onChanged: (value) => setState(() => _localModelEnabled = value),
                  title: const Text('Habilitar IA local (Android plugin)'),
                ),
              ],
            ),
          ),
          _section(
            title: 'Backends remotos / NOMAD',
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _applyNomadPreset,
                    icon: const Icon(Icons.hub),
                    label: const Text('Aplicar preset Project NOMAD'),
                  ),
                ),
                const SizedBox(height: 10),
                _field(_llmUrl, 'LLM endpoint (OpenAI/Ollama-compatible)'),
                _field(_model, 'Modelo remoto padrão'),
                _field(_llmToken, 'Token LLM', obscure: true),
                _field(_sttUrl, 'STT endpoint'),
                _field(_sttToken, 'Token STT', obscure: true),
                _field(_ttsUrl, 'TTS endpoint'),
                _field(_ttsToken, 'Token TTS', obscure: true),
                _field(_memoryUrl, 'Memória/RAG endpoint (NOMAD/Qdrant gateway)'),
                _field(_timeout, 'Timeout (ms)', keyboardType: TextInputType.number),
                DropdownButtonFormField<String>(
                  initialValue: _transport,
                  decoration: _inputDecoration('Transporte'),
                  items: const [
                    DropdownMenuItem(value: 'https', child: Text('HTTPS/HTTP')),
                    DropdownMenuItem(value: 'websocket', child: Text('WebSocket')),
                  ],
                  onChanged: (value) => setState(() => _transport = value ?? 'https'),
                ),
              ],
            ),
          ),
          _section(
            title: 'ZeptoClaw',
            child: Column(
              children: [
                SwitchListTile(value: _zeptoLocalEnabled, onChanged: (value) => setState(() => _zeptoLocalEnabled = value), title: const Text('ZeptoClaw local/no app')),
                SwitchListTile(value: _zeptoRemoteEnabled, onChanged: (value) => setState(() => _zeptoRemoteEnabled = value), title: const Text('ZeptoClaw remoto/cloud')),
                _field(_zeptoRemoteUrl, 'Endpoint ZeptoClaw cloud'),
                _field(_zeptoRemoteToken, 'Token ZeptoClaw cloud', obscure: true),
              ],
            ),
          ),
          _section(
            title: 'Experiência',
            child: SwitchListTile(
              value: _confirmTranscript,
              contentPadding: EdgeInsets.zero,
              title: const Text('Confirmar transcript antes de enviar'),
              onChanged: (value) => setState(() => _confirmTranscript = value),
            ),
          ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton(onPressed: () => Navigator.of(context).pop(_build()), child: const Text('Salvar')),
              OutlinedButton.icon(onPressed: _healthCheck, icon: const Icon(Icons.radar), label: const Text('Health-check')),
            ],
          ),
          if (_healthStatus.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_healthStatus)),
          ],
        ),
      ),
    );
  }

  Widget _section({required String title, required Widget child}) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF0B1828),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0x6600E5FF)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title), const SizedBox(height: 10), child]),
      );

  Widget _field(TextEditingController controller, String label, {bool obscure = false, TextInputType keyboardType = TextInputType.text}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(controller: controller, obscureText: obscure, keyboardType: keyboardType, decoration: _inputDecoration(label)),
    );
  }

  InputDecoration _inputDecoration(String label) => InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: const Color(0x22121824),
      );
}
