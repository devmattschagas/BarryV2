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
  late final TextEditingController _model;
  late final TextEditingController _llmToken;
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

  @override
  void initState() {
    super.initState();
    _llmUrl = TextEditingController(text: widget.initial.llmBaseUrl);
    _model = TextEditingController(text: widget.initial.model);
    _llmToken = TextEditingController(text: widget.initial.llmApiKey);
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
    _llmUrl.dispose();
    _model.dispose();
    _llmToken.dispose();
    _timeout.dispose();
    _localModel.dispose();
    _zeptoRemoteUrl.dispose();
    _zeptoRemoteToken.dispose();
    super.dispose();
  }

  AssistantSettings _build() => AssistantSettings(
        llmBaseUrl: _llmUrl.text.trim(),
        sttBaseUrl: widget.initial.sttBaseUrl,
        ttsBaseUrl: widget.initial.ttsBaseUrl,
        memoryBaseUrl: widget.initial.memoryBaseUrl,
        llmApiKey: _llmToken.text.trim(),
        sttApiKey: widget.initial.sttApiKey,
        ttsApiKey: widget.initial.ttsApiKey,
        model: _model.text.trim().isEmpty ? 'gpt-4.1-mini' : _model.text.trim(),
        timeoutMs: int.tryParse(_timeout.text.trim()) ?? 30000,
        transport: _transport,
        confirmTranscriptBeforeSend: _confirmTranscript,
        localModel: _localModel.text.trim().isEmpty ? 'gemma-3n-e4b' : _localModel.text.trim(),
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

    Future<void> ping(String label, String url, String token) async {
      if (url.isEmpty) {
        result.add('$label: não configurado');
        return;
      }
      try {
        final response = await widget.client
            .get(
              Uri.parse(url),
              headers: {if (token.isNotEmpty) 'Authorization': 'Bearer $token'},
            )
            .timeout(Duration(milliseconds: s.timeoutMs));
        result.add('$label: HTTP ${response.statusCode}');
      } catch (e) {
        result.add('$label: erro ($e)');
      }
    }

    await ping('IA remota', s.llmBaseUrl, s.llmApiKey);
    await ping('ZeptoClaw cloud', s.zeptoRemoteUrl, s.zeptoRemoteApiKey);

    if (!mounted) return;
    setState(() => _healthStatus = result.join('\n'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, title: const Text('Settings do sistema')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section(
            title: 'Política de inferência',
            child: Column(
              children: [
                DropdownButtonFormField<InferencePolicy>(
                  initialValue: _policy,
                  decoration: _inputDecoration('Roteamento local/remoto'),
                  items: const [
                    DropdownMenuItem(value: InferencePolicy.localOnly, child: Text('Somente IA local')),
                    DropdownMenuItem(value: InferencePolicy.hybridPreferLocal, child: Text('Híbrido (preferir local)')),
                    DropdownMenuItem(value: InferencePolicy.hybridPreferRemote, child: Text('Híbrido (preferir remoto)')),
                    DropdownMenuItem(value: InferencePolicy.remoteOnly, child: Text('Somente IA remota')),
                  ],
                  onChanged: (value) => setState(() => _policy = value ?? InferencePolicy.hybridPreferLocal),
                ),
                _field(_localModel, 'Modelo local (principal: Gemma 3n E4B)'),
                SwitchListTile(
                  value: _localModelEnabled,
                  onChanged: (value) => setState(() => _localModelEnabled = value),
                  title: const Text('Habilitar IA local (LiteRT bridge)'),
                ),
              ],
            ),
          ),
          _section(
            title: 'IA remota',
            child: Column(
              children: [
                _field(_llmUrl, 'Endpoint remoto IA (OpenAI-compatible)'),
                _field(_model, 'Modelo remoto padrão'),
                _field(_llmToken, 'Token IA remota', obscure: true),
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
                SwitchListTile(
                  value: _zeptoLocalEnabled,
                  onChanged: (value) => setState(() => _zeptoLocalEnabled = value),
                  title: const Text('ZeptoClaw local/no app'),
                ),
                SwitchListTile(
                  value: _zeptoRemoteEnabled,
                  onChanged: (value) => setState(() => _zeptoRemoteEnabled = value),
                  title: const Text('ZeptoClaw remoto/cloud'),
                ),
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
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(_build()),
                icon: const Icon(Icons.save),
                label: const Text('Salvar'),
              ),
              OutlinedButton.icon(
                onPressed: _healthCheck,
                icon: const Icon(Icons.radar),
                label: const Text('Health-check'),
              ),
            ],
          ),
          if (_healthStatus.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_healthStatus)),
        ],
      ),
    );
  }

  Widget _section({required String title, required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0x3312C8DD), Color(0x22223852)]),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x6600E5FF)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title), const SizedBox(height: 10), child]),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool obscure = false,
    TextInputType keyboardType = TextInputType.text,
  }) {
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
