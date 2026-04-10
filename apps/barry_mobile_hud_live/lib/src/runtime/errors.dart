enum RuntimeErrorType {
  timeout,
  authentication,
  unavailable,
  client4xx,
  server5xx,
  invalidResponse,
  malformedResponse,
  network,
  localUnavailable,
  unknown,
}

class RuntimeFailure implements Exception {
  RuntimeFailure(this.type, this.message, {this.statusCode});

  final RuntimeErrorType type;
  final String message;
  final int? statusCode;

  @override
  String toString() => 'RuntimeFailure(type: $type, statusCode: $statusCode, message: $message)';
}
