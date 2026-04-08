# BARRY MOBILE HUD - LIVE

Monorepo Flutter modular para nó híbrido Cloud/Edge com foco Android.

## Estrutura
- `apps/barry_mobile_hud_live`: app Flutter principal.
- `packages/*`: módulos por responsabilidade (core, UI HUD, STT, VAD, router, memória, FFI, plugin etc.).
- `docs/`: arquitetura, ADRs, estratégia de testes e orçamento de performance.

## Premissas honestas
- **Sem contratos proprietários reais** Barry v2/NOMAD/LEANN: usamos ports + adapters mock.
- **STT faster-whisper no Android**: apenas via sidecar/worker abstrato (WebSocket/gRPC loopback), nunca `pip` embutido.
- **LLM local**: ponte de plugin para LiteRT-LM (Kotlin), com fallback para cloud/mock.
- **VAD local**: caminho de produção definido para Silero + ONNX Runtime; build atual inclui stub nativo robusto para dev/CI.

## Build nativo
As bibliotecas `.so` não são arquivos texto no repositório.
Elas são compiladas pelo CMake durante o build Android (`externalNativeBuild`).

## Quickstart
```bash
flutter pub global activate melos
melos bootstrap
melos run analyze
melos run test
cd apps/barry_mobile_hud_live
flutter build apk --release \
  --dart-define=BARRY_LIVEKIT_URL=wss://example.invalid \
  --dart-define=BARRY_LIVEKIT_TOKEN=dev-token
```

## Signing opcional CI
Variáveis esperadas:
- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

Sem essas secrets o workflow gera APK unsigned de CI.
