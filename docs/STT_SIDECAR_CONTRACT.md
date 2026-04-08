# STT SIDECAR CONTRACT (ABSTRATO)

Transporte sugerido: WebSocket loopback (`ws://127.0.0.1:<port>/stt`).

## Client -> Sidecar
- Binário PCM16 LE mono 16k em chunks de streaming.

## Sidecar -> Client (JSON)
```json
{
  "text": "partial or final text",
  "is_final": false,
  "start_ms": 0,
  "end_ms": 420
}
```

Sem schema proprietário Barry v2: contrato mínimo extensível.
