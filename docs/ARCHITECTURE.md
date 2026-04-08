# ARCHITECTURE (híbrida, explícita por subsistema)

## Matriz por subsistema
| Subsistema | Caminho principal | Fallback local | Fallback remoto | Roteamento | Transporte | Observabilidade |
|---|---|---|---|---|---|---|
| VAD | Local nativo (`BarryVadNative`) | Heurístico RMS local | N/A | `hasLocalVad` | Local FFI | `vadInferenceMs`, tag fallback |
| STT | Local quando `hasLocalStt` | Null/empty sem crash | Remoto via adapter (`hasRemoteStt`) | Capability + rede | WebRTC preferencial, WS/HTTP justificado | latência STT + auditoria router |
| TTS | Local quando `hasLocalTts` | áudio vazio controlado | Remoto quando `hasRemoteTts` | Capability + qualidade | WebRTC preferencial | eventos de rota |
| LLM pequeno local | Plugin Android (`PlatformLocalLlmEngine`) | resposta vazia controlada | cloud | privacidade/latência/térmica | MethodChannel | telemetria de decisão |
| LLM cloud principal | Qwen2.5 14B (modelo alvo) | local pequeno quando viável | N/A | complexidade + qualidade + tools | HTTPS/stream | auditoria no router |
| Tool execution | ZeptoClaw cloud | deny/skip local | remoto policy-based | `hasZeptoClawCloud` + allowlist | API remota | policy logs |
| Memória curta | store local (`InMemoryMemoryStore`) | N/A | sincronização eventual | sempre ativo | local | retrieval timing |
| Memória longa | Vault (alvo) | resumo local | camada cloud complementar | `hasVault` | API remota | métricas de consulta |
| Memória contextual | Claude-Mem / PAUL (alvo) | resumo local | cloud auxiliar | `hasClaudeMem`/`hasPaul` | API remota | auditoria de contexto |
| Orquestração | OpenClaude/Claude Code OSS (alvo) | roteador local mínimo | cloud coordinator | capacidade + tipo de tarefa | API remota | trilha de decisão |
| Mídia tempo real | Remote streaming via WebRTC | buffer local | WS/HTTP somente quando necessário | `hasRealtimeRemoteTransport` | WebRTC | RTT e falhas por canal |

## Regras obrigatórias aplicadas
1. Adapter local ≠ adapter remoto.
2. Fallback por capability, não global.
3. Falha de plugin/bridge/FFI não pode crashar app.
4. Policy/allowlist centralizada (`CommandPolicies`).
5. Router auditável com critérios de latência/rede/custo/privacidade/complexidade/memória/tools/qualidade.

## Status de integração
- **Integrado de fato no repositório**: arquitetura híbrida e contratos por subsistema.
- **Backlog de integração ambiente real**: endpoints autenticados e contratos finais com Qwen/OpenClaude/ZeptoClaw/Vault/Claude-Mem/PAUL.
