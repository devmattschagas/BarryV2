import '../models.dart';
import 'errors.dart';
import 'network_client.dart';

class RemoteAiClient {
  RemoteAiClient(this._networkClient);

  final NetworkClient _networkClient;

  Future<String> infer({required List<ConversationMessage> messages, required AssistantSettings settings}) async {
    if (settings.llmBaseUrl.trim().isEmpty) {
      throw RuntimeFailure(RuntimeErrorType.unavailable, 'Endpoint remoto da IA não configurado.');
    }

    final payload = {
      'model': settings.model,
      'messages': [
        {
          'role': 'system',
          'content':
              'Você é Barry, assistente de voz do sistema ZeptoClaw. Responda de forma natural e útil, sem expor detalhes técnicos de runtime, modelo ou debug.',
        },
        ...messages.take(16).map((m) => {'role': m.role, 'content': m.text}),
      ],
      'temperature': 0.2,
    };

    final decoded = await _networkClient.postJson(
      Uri.parse(settings.llmBaseUrl),
      body: payload,
      timeout: Duration(milliseconds: settings.timeoutMs),
      headers: {if (settings.llmApiKey.isNotEmpty) 'Authorization': 'Bearer ${settings.llmApiKey}'},
    );

    final choices = decoded['choices'];
    if (choices is List && choices.isNotEmpty) {
      final first = choices.first;
      if (first is Map<String, dynamic>) {
        final message = first['message'];
        if (message is Map<String, dynamic>) {
          final content = message['content'] as String? ?? '';
          if (content.trim().isNotEmpty) return content.trim();
        }
      }
    }

    final text = decoded['text'] as String? ?? '';
    if (text.trim().isNotEmpty) return text.trim();

    throw RuntimeFailure(RuntimeErrorType.invalidResponse, 'IA remota retornou payload sem texto válido.');
  }
}
