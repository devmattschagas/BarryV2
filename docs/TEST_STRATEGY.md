# TEST STRATEGY
- Unit: router, retriever memória, lógica VAD.
- Widget: HUD states principais.
- Native: stubs C ZeptoClaw/VAD compiláveis e comportamento básico.
- E2E mock: mic->vad->stt mock->router->hud.
- Performance: harness preparado em `barry_testkit`.
