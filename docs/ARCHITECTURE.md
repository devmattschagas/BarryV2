# ARCHITECTURE

## Consistency check e correções técnicas
1. **Trap de `.so` fake**: removidos arquivos texto em `jniLibs`; as libs agora são geradas por CMake (`zeptoclaw`, `barry_vad_native`, `barry_whisper_worker`, `onnxruntime` stub dev) no build Android.
2. **`faster-whisper` no Android**: não há integração Android oficial por `pip`; mantido `TranscriptionEngine` com `FasterWhisperSidecarEngine` via loopback e fallback mock.
3. **LiteRT-LM**: integração em plugin (`barry_platform_bridge`) por depender de APIs Android/Kotlin; não fica no FFI puro.
4. **VAD em produção**: arquitetura exige Silero + ONNX Runtime; o stub atual adiciona ruído-adaptativo/hangover para dev/CI e define ponto explícito de troca para chamada ONNX real.
5. **Barry v2/NOMAD/LEANN sem contrato público**: somente ports/adapters configuráveis, sem inventar payload proprietário.

## Módulos
- `barry_core`: telemetria, ring buffer, estado HUD.
- `barry_router`: decisão auditável LOCAL/CLOUD.
- `barry_stt`: abstrações STT + sidecar.
- `barry_vad`: hysteresis + chamada nativa VAD.
- `barry_platform_bridge`: ponte LiteRT-LM por plugin.
- `barry_native_ffi`: ZeptoClaw + VAD + worker nativo.
- `barry_memory`: MVP NOMAD/LEANN com embeddings determinísticos.
- `barry_livekit`, `barry_vision`, `barry_ui_hud`: transporte, visão e UX HUD.

## Pipeline de voz
Mic -> ring buffer PCM16 16k -> VAD -> gate -> STT stream -> router -> LLM local/cloud -> HUD.

## Startup native libs
`NativeLibraryLoader.verify()` valida abertura de libs obrigatórias no boot e permite degradação controlada quando faltarem artefatos nativos.
