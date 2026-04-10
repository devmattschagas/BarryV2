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
  late final TextEditingController _llmToken;
  late final TextEditingController _sttToken;
  late final TextEditingController _ttsToken;
  late final TextEditingController _model;
  late final TextEditingController _timeout;
  late bool _confirmTranscript;
  late String _transport;
  String _healthStatus = '';

  @override
  void initState() {
    super.initState();
    _llmUrl = TextEditingController(text: widget.initial.llmBaseUrl);
    _sttUrl = TextEditingController(text: widget.initial.sttBaseUrl);
    _ttsUrl = TextEditingController(text: widget.initial.ttsBaseUrl);
    _memoryUrl = TextEditingController(text: widget.initial.memoryBaseUrl);
    _llmToken = TextEditingController(text: widget.initial.llmApiKey);
    _sttToken = TextEditingController(text: widget.initial.sttApiKey);
    _ttsToken = TextEditingController(text: widget.initial.ttsApiKey);
    _model = TextEditingController(text: widget.initial.model);
    _timeout = TextEditingController(text: widget.initial.timeoutMs.toString());
    _transport = widget.initial.transport;
    _confirmTranscript = widget.initial.confirmTranscriptBeforeSend;
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

  AssistantSettings _build() => AssistantSettings(
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
        confirmTranscriptBeforeSend: _confirmTranscript,
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

    await ping('LLM', s.llmBaseUrl, s.llmApiKey);
    await ping('STT', s.sttBaseUrl, s.sttApiKey);
    await ping('TTS', s.ttsBaseUrl, s.ttsApiKey);
    await ping('MEM', s.memoryBaseUrl, '');

    if (!mounted) return;
    setState(() => _healthStatus = result.join('\n'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section(
            title: 'Conectividade',
            child: Column(
              children: [
                _field(_llmUrl, 'LLM endpoint'),
                _field(_sttUrl, 'STT endpoint'),
                _field(_ttsUrl, 'TTS endpoint'),
                _field(_memoryUrl, 'Memory/Tools endpoint'),
                _field(_model, 'Modelo padrão'),
                _field(_timeout, 'Timeout (ms)', keyboardType: TextInputType.number),
                DropdownButtonFormField<String>(
                  value: _transport,
                  decoration: const InputDecoration(labelText: 'Transporte'),
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
            title: 'Segredos',
            child: Column(
              children: [
                _field(_llmToken, 'LLM token', obscure: true),
                _field(_sttToken, 'STT token', obscure: true),
                _field(_ttsToken, 'TTS token', obscure: true),
              ],
            ),
          ),
          _section(
            title: 'Experiência',
            child: SwitchListTile(
              value: _confirmTranscript,
              contentPadding: EdgeInsets.zero,
              title: const Text('Confirmar transcript antes de enviar'),
              subtitle: const Text('Mostra modal editável após STT final.'),
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
                icon: const Icon(Icons.network_check),
                label: const Text('Health-check'),
              ),
            ],
          ),
          if (_healthStatus.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_healthStatus),
            ),
        ],
      ),
    );
  }

  Widget _section({required String title, required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0x3300B8D4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x6600E5FF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          child,
        ],
      ),
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
      child: TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: const Color(0x22121824),
        ),
      ),
    );
  }
}
