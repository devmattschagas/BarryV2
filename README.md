# BarryV2 (Android-first, arquitetura híbrida local + nuvem)

BarryV2 é uma base Flutter/Android para HUD de voz com roteamento explícito por capability, tolerância a falhas por subsistema e modo degradado granular.

## Princípios de produto (não demo)
- Híbrido real: não força tudo local nem tudo cloud.
- Roteamento auditável por subsistema (VAD/STT/TTS/LLM/memória/tools).
- Degradação por capability (falha parcial não derruba pipeline inteiro).
- Integrações cloud reais preservadas no desenho: **Qwen2.5 14B**, **OpenClaude/Claude Code OSS**, **ZeptoClaw cloud**, **Vault**, **Claude-Mem**, **PAUL**.

## Stack e responsabilidades
- **Local-first crítico de latência**: VAD, memória operacional curta, fallback STT/TTS, regras de segurança.
- **Cloud principal para complexidade**: Qwen2.5 14B, execução remota de tools com ZeptoClaw, memória longa (Vault), otimização/contexto (Claude-Mem/PAUL), orquestração (OpenClaude).
- **Transporte de mídia remoto (streaming contínuo)**: WebRTC como caminho principal; WebSocket/HTTP apenas quando tecnicamente justificado.

## Quickstart
```bash
flutter pub global activate melos
melos bootstrap
melos run analyze
melos run test
cd apps/barry_mobile_hud_live
flutter build apk --release
```

## CI
Workflow valida analyze/test/build, presença de libs nativas no APK e gera build assinado quando secrets existem; se não existirem, mantém build CI unsigned de forma segura.

## Estado real de implementação
- Implementado em código: capability profile granular, router híbrido auditável, STT/TTS híbridos com fallback, VAD robusto com fallback heurístico, memória local com embedding automático, coordinator idempotente e degradado por capability.
- Ainda abstrato/mockado: integrações efetivas de produção com endpoints de Qwen/OpenClaude/Vault/Claude-Mem/PAUL/ZeptoClaw cloud (ports prontos, wiring real pendente por ambiente).
