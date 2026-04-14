import 'package:barry_core/barry_core.dart';
import 'package:barry_native_ffi/barry_native_ffi.dart';

import '../models.dart';
import 'errors.dart';
import 'network_client.dart';

class ZeptoClawLocalExecutor {
  ZeptoClawLocalExecutor({ZeptoClawExecutor? executor}) : _executor = executor ?? ZeptoClawExecutor();

  final ZeptoClawExecutor _executor;

  Future<String?> tryExecute(String prompt, AssistantSettings settings) async {
    if (!settings.zeptoLocalEnabled) return null;

    final command = _resolveCommand(prompt);
    if (command == null) return null;
    if (!_executor.isHealthy) {
      throw RuntimeFailure(RuntimeErrorType.localUnavailable, 'ZeptoClaw local indisponível no runtime nativo.');
    }

    final result = _executor.executeScript(
      command: command,
      payload: {'prompt': prompt, 'ts': DateTime.now().toIso8601String()},
      timeoutMs: settings.timeoutMs,
    );
    if (!result.ok) {
      throw RuntimeFailure(RuntimeErrorType.unavailable, 'ZeptoClaw local falhou para $command (exit=${result.exitCode}).');
    }

    final device = result.payload['device_state'];
    return 'ZeptoClaw local executou "$command" com sucesso. device_state=$device';
  }

  String? _resolveCommand(String prompt) {
    final normalized = prompt.toLowerCase();
    if (normalized.contains('status')) return 'status.read';
    if (normalized.contains('sensor')) return 'sensors.scan';
    if (normalized.contains('navega') || normalized.contains('travar') || normalized.contains('lock')) return 'nav.lock';
    return null;
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

    final command = _resolveCommand(prompt);
    if (command == null) return null;
    if (!CommandPolicies.zeptoClawCloud.canExecute(command)) {
      throw RuntimeFailure(RuntimeErrorType.unavailable, 'Comando $command fora da allowlist de segurança.');
    }

    final decoded = await _networkClient.postJson(
      Uri.parse(settings.zeptoRemoteUrl),
      body: {
        'command': command,
        'payload': {'prompt': prompt, 'source': 'barry_mobile_hud_live'},
      },
      timeout: Duration(milliseconds: settings.timeoutMs),
      headers: {if (settings.zeptoRemoteApiKey.isNotEmpty) 'Authorization': 'Bearer ${settings.zeptoRemoteApiKey}'},
    );

    final ok = decoded['ok'] as bool? ?? false;
    final result = decoded['result'] as String? ?? decoded['text'] as String? ?? '';
    if (!ok && result.trim().isEmpty) {
      throw RuntimeFailure(RuntimeErrorType.invalidResponse, 'ZeptoClaw remoto retornou payload inválido.');
    }
    return result.trim().isEmpty ? 'ZeptoClaw remoto executou "$command".' : result.trim();
  }

  String? _resolveCommand(String prompt) {
    final normalized = prompt.toLowerCase();
    if (normalized.contains('status')) return 'status.read';
    if (normalized.contains('sensor')) return 'sensors.scan';
    if (normalized.contains('navega') || normalized.contains('travar') || normalized.contains('lock')) return 'nav.lock';
    return null;
  }
}
