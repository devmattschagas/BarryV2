enum TelemetryMetric {
  livekitConnectMs,
  livekitRttMs,
  vadInferenceMs,
  sttPartialLatencyMs,
  sttFinalLatencyMs,
  localLlmTtftMs,
  localLlmDecodeTps,
  cloudRoundtripMs,
  frameSampleRate,
  droppedVideoFrames,
  ffiCallMs,
  memoryRetrievalMs,
}

class TelemetryEvent {
  const TelemetryEvent(this.metric, this.value, {this.tags = const {}});
  final TelemetryMetric metric;
  final num value;
  final Map<String, String> tags;
}

abstract interface class TelemetryBus {
  void emit(TelemetryEvent event);
  List<TelemetryEvent> snapshot();
}

class InMemoryTelemetryBus implements TelemetryBus {
  final List<TelemetryEvent> _events = [];

  @override
  void emit(TelemetryEvent event) => _events.add(event);

  @override
  List<TelemetryEvent> snapshot() => List.unmodifiable(_events);
}
