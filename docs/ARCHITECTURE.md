# ARCHITECTURE

## Consistency check e correções técnicas
1. **`faster-whisper` no Android**: não há integração Android oficial por `pip`; corrigido para `TranscriptionEngine` com `FasterWhisperSidecarEngine` via loopback WebSocket e fallback mock.
2. **LiteRT-LM**: como depende de APIs Android/Kotlin, ficou no `barry_platform_bridge` (plugin), não no pacote FFI puro.
3. **Silero VAD**: implementação por wrapper nativo ONNX routeada no pacote `barry_native_ffi`; aqui o repositório inclui stubs compiláveis e pontos de substituição para `.so` reais.
4. **Barry v2/NOMAD/LEANN sem contrato público**: definimos ports/adapters sem inventar payload proprietário.

## Módulos
- `barry_core`: telemetria, ring buffer, estado HUD e coordenação.
- `barry_router`: decisão auditável LOCAL/CLOUD.
- `barry_stt`: abstrações STT + sidecar.
- `barry_vad`: hysteresis + chamada nativa VAD.
- `barry_platform_bridge`: ponte LiteRT-LM por plugin.
- `barry_native_ffi`: ZeptoClaw + VAD + worker nativo (stubs).
- `barry_memory`: MVP NOMAD/LEANN com embeddings determinísticos.
- `barry_livekit`, `barry_vision`, `barry_ui_hud`: transporte, visão e UX HUD.

## Pipeline de voz
Mic -> ring buffer PCM16 16k -> VAD -> gate -> STT stream -> router -> LLM local/cloud -> HUD.

## Startup native libs
Constantes centralizadas em `NativeLibNames`. Inicialização valida carregamento por `DynamicLibrary.open` no primeiro uso.
