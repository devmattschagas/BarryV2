# PERF BUDGET
- UI frame pacing: alvo 16.6ms (60 FPS), degradar efeitos no modo degradado.
- VAD inferência: alvo < 5ms por chunk de 20ms (Silero ONNX Runtime nativo).
- STT partial latency: alvo < 350ms **somente** com sidecar local otimizado e dispositivo high-end; para medianos aceitar SLO de 350-700ms.
- Router decisão: alvo < 5ms.
- Overlay render: alvo < 4ms por frame.
- FFI overhead: alvo < 1ms por chamada curta.
