# BarryV2 (Android-first, local-first + NOMAD opcional)

BarryV2 é um app Flutter com pipeline principal de produção centrada em `ConversationCoordinator` (voz/texto -> ZeptoClaw -> LLM -> TTS), rodando **offline quando o subsistema local está disponível** e com backend remoto opcional compatível com NOMAD/OpenAI/Ollama.

## Decisões técnicas atuais
- **Pipeline única de produção**: `ConversationCoordinator` (o `HudCoordinator` permanece somente legado/testes).
- **LLM local**: bridge Android/iOS não retorna mais payload fake/mock; quando o runtime local não está ligado, retorna erro explícito (`local_llm_unavailable`) para fallback controlado.
- **Modelo local alvo**: família Gemma mobile. Default de configuração: `gemma-2b-it-q4_0`.
- **ZeptoClaw**: executor nativo via FFI com allowlist central (`status.read`, `sensors.scan`, `nav.lock`) + cliente remoto opcional.
- **NOMAD remoto opcional**: campos e health-check de LLM/STT/TTS/Memória/ZeptoClaw expostos em Settings.
- **VAD**: backend nativo ativo com fallback heurístico no `barry_vad`.
- **STT/TTS em packages**: removidos placeholders; local é responsabilidade da camada de app/plataforma, remoto é adapter real por transporte.
- **Memória**: store persistente com embedding determinístico e retrieval semântico local; backend remoto continua opcional.

## Quickstart
```bash
flutter pub global activate melos
melos bootstrap
melos run analyze
melos run test
cd apps/barry_mobile_hud_live
flutter build apk --release
```

## Configuração de execução
1. Abra **Settings** no app.
2. Configure (se quiser modo híbrido/remoto):
   - `LLM endpoint` (OpenAI-compatible/Ollama-compatible, incluindo NOMAD AI Assistant gateway).
   - `STT endpoint` / `TTS endpoint`.
   - `Memória endpoint` (RAG/Qdrant gateway).
   - `ZeptoClaw endpoint`.
3. Para local-only:
   - mantenha rede opcional/desligada,
   - mantenha `IA local habilitada`,
   - forneça runtime local de Gemma mobile no app Android.

## Limitações reais pendentes
- Integração de inferência Gemma Android ainda depende de wiring final do runtime (LiteRT/MediaPipe/llama.cpp) e assets do modelo no build de app.
- iOS segue sem runtime LLM local neste branch.
- Endpoints remotos NOMAD variam por deploy; o app hoje já possui contrato e configuração, mas requer backend ativo.
