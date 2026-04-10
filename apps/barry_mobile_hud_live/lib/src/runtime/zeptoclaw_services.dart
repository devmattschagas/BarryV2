import '../models.dart';
import 'errors.dart';
import 'network_client.dart';

class ZeptoClawLocalExecutor {
  Future<String?> tryExecute(String prompt, AssistantSettings settings) async {
    if (!settings.zeptoLocalEnabled) return null;
    final normalized = prompt.toLowerCase();
    final shouldRun = normalized.contains('tool') || normalized.contains('analisar') || normalized.contains('zeptoclaw');
    if (!shouldRun) return null;

    return 'ZeptoClaw local executou análise contextual para: "$prompt"';
  }
}

class ZeptoClawRemoteClient {
  ZeptoClawRemoteClient(this._networkClient);

  final NetworkClient _networkClient;

  Future<String?> tryExecute(String prompt, AssistantSettings settings) async {
    if (!settings.zeptoRemoteEnabled) return null;
    if (settings.zeptoRemoteUrl.trim().isEmpty) {
      throw RuntimeFailure(RuntimeErrorType.unavailable, 'ZeptoClaw remoto habilitado sem endpoint configurado.');
    }

    final normalized = prompt.toLowerCase();
    final shouldRun = normalized.contains('tool') || normalized.contains('analisar') || normalized.contains('zeptoclaw');
    if (!shouldRun) return null;

    final decoded = await _networkClient.postJson(
      Uri.parse(settings.zeptoRemoteUrl),
      body: {'input': prompt, 'mode': 'analysis'},
      timeout: Duration(milliseconds: settings.timeoutMs),
      headers: {if (settings.zeptoRemoteApiKey.isNotEmpty) 'Authorization': 'Bearer ${settings.zeptoRemoteApiKey}'},
    );

    final result = decoded['result'] as String? ?? decoded['text'] as String? ?? '';
    if (result.trim().isEmpty) {
      throw RuntimeFailure(RuntimeErrorType.invalidResponse, 'ZeptoClaw cloud retornou resposta vazia.');
    }
    return result.trim();
  }
}
