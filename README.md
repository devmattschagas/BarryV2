# BarryV2 (Android-first, local-first + NOMAD opcional)

BarryV2 é um app Flutter com pipeline principal de produção centrada em `ConversationCoordinator` (voz/texto -> ZeptoClaw -> LLM -> TTS), rodando **offline quando o subsistema local está disponível** e com backend remoto opcional compatível com NOMAD/OpenAI/Ollama.

## Decisões técnicas atuais
- **Pipeline única de produção**: `ConversationCoordinator` (o `HudCoordinator` permanece somente legado/testes).
- **LLM local Android real**: o plugin Android chama um runtime local HTTP em loopback (`127.0.0.1:11434/api/generate`), sem payload fake/mock; quando o runtime não está ativo, retorna erro explícito (`local_llm_unavailable`) para fallback controlado.
- **Modelo local alvo**: família Gemma mobile. Default de configuração: `gemma-4b-it-q4_0`.
- **ZeptoClaw**: executor nativo via FFI com allowlist central (`status.read`, `sensors.scan`, `nav.lock`) + cliente remoto opcional.
- **NOMAD remoto opcional**: preset explícito em Settings para `Project NOMAD` (base `http://<host>:8080/api`) e health-check de LLM/STT/TTS/Memória/ZeptoClaw.
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
   - forneça runtime local de Gemma mobile no app Android (ex.: Ollama/llama.cpp compatível em `127.0.0.1:11434/api/generate`).

## Integração com Project NOMAD (fluxo real)
1. Suba o NOMAD e confirme `http://<IP>:8080/api/health`.
2. No Barry, abra **Settings** e use **Aplicar preset Project NOMAD**.
3. Ajuste `LLM endpoint` para `/api/ollama/chat` e `Memória endpoint` para `/api/rag/files` (ou endpoint custom do seu deploy).
4. Rode **Health-check** para validar conectividade.

Referências NOMAD usadas neste branch:
- `GET /api/health`
- `POST /api/ollama/chat`
- `GET /api/rag/files`
- `GET /api/system/services`

## ZeptoClaw local
- `health_check` agora valida runtime + capabilities.
- `execute_script` aplica allowlist real e valida payload/timeout.
- respostas incluem `capabilities` e `device_state` estruturados para contexto do Barry.

## Validação manual (resumo)
1. Abrir Settings e Conta pelo menu lateral (sem tela translúcida).
2. Salvar e voltar ao shell.
3. STT: iniciar escuta, ver parcial, finalizar sem duplicação de transcript.
4. LLM local: com runtime local ativo, enviar prompt e confirmar resposta local.
5. NOMAD: aplicar preset + health-check.

## Limitações reais pendentes
- Integração de inferência Gemma Android ainda depende de wiring final do runtime (LiteRT/MediaPipe/llama.cpp) e assets do modelo no build de app.
- iOS segue sem runtime LLM local neste branch.
- Endpoints remotos NOMAD variam por deploy; o app hoje já possui contrato e configuração, mas requer backend ativo.
