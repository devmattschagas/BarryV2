import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'errors.dart';

class NetworkClient {
  NetworkClient(this._http);

  final http.Client _http;

  Future<Map<String, dynamic>> postJson(
    Uri uri, {
    required Map<String, dynamic> body,
    required Duration timeout,
    Map<String, String> headers = const {},
    int retries = 2,
  }) async {
    var attempt = 0;
    while (true) {
      attempt += 1;
      try {
        final response = await _http
            .post(
              uri,
              headers: {'Content-Type': 'application/json', ...headers},
              body: jsonEncode(body),
            )
            .timeout(timeout);
        return _decodeResponse(response);
      } on TimeoutException {
        if (attempt > retries) {
          throw RuntimeFailure(RuntimeErrorType.timeout, 'Tempo esgotado para ${uri.host}.');
        }
      } on SocketException {
        if (attempt > retries) {
          throw RuntimeFailure(RuntimeErrorType.network, 'Falha de rede para ${uri.host}.');
        }
      } on RuntimeFailure {
        rethrow;
      } catch (e) {
        throw RuntimeFailure(RuntimeErrorType.unknown, 'Erro inesperado de rede: $e');
      }
      await Future<void>.delayed(Duration(milliseconds: 250 * attempt));
    }
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    final status = response.statusCode;
    if (status == 401 || status == 403) {
      throw RuntimeFailure(RuntimeErrorType.authentication, 'Falha de autenticação.', statusCode: status);
    }
    if (status >= 400 && status < 500) {
      throw RuntimeFailure(RuntimeErrorType.client4xx, 'Erro de requisição ($status).', statusCode: status);
    }
    if (status >= 500) {
      throw RuntimeFailure(RuntimeErrorType.server5xx, 'Servidor indisponível ($status).', statusCode: status);
    }

    if (response.body.trim().isEmpty) {
      throw RuntimeFailure(RuntimeErrorType.invalidResponse, 'Resposta vazia do servidor.', statusCode: status);
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw RuntimeFailure(RuntimeErrorType.malformedResponse, 'Resposta malformada.', statusCode: status);
    }
    return decoded;
  }
}
