from __future__ import annotations

import asyncio
import json
import logging
import os
import re
import uuid
from abc import ABC, abstractmethod
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, AsyncGenerator, Literal

import httpx
from pydantic import BaseModel, Field

from agentscope_runtime import AgentApp

APP_VERSION = "0.1.0"


class Settings(BaseModel):
    """Runtime settings loaded from environment variables."""

    agent_app_host: str = Field(default_factory=lambda: os.getenv("AGENT_APP_HOST", "127.0.0.1"))
    agent_app_port: int = Field(default_factory=lambda: int(os.getenv("AGENT_APP_PORT", "8090")))
    agent_app_name: str = Field(default_factory=lambda: os.getenv("AGENT_APP_NAME", "BarryAgent"))
    agent_app_log_level: str = Field(default_factory=lambda: os.getenv("AGENT_APP_LOG_LEVEL", "INFO"))

    model_base_url: str = Field(default_factory=lambda: os.getenv("MODEL_BASE_URL", "http://127.0.0.1:8001/v1"))
    model_name: str = Field(default_factory=lambda: os.getenv("MODEL_NAME", "Qwen2.5-Coder-14B-Instruct"))
    model_api_key: str = Field(default_factory=lambda: os.getenv("MODEL_API_KEY", "local"))
    model_timeout_seconds: float = Field(default_factory=lambda: float(os.getenv("MODEL_TIMEOUT_SECONDS", "120")))

    vault_root: Path = Field(default_factory=lambda: Path(os.getenv("VAULT_ROOT", "/opt/agentos/vault")).resolve())
    work_root: Path = Field(default_factory=lambda: Path(os.getenv("WORK_ROOT", "/opt/agentos/work")).resolve())

    claude_mem_enabled: bool = Field(default_factory=lambda: os.getenv("CLAUDE_MEM_ENABLED", "true").lower() == "true")
    claude_mem_base_url: str = Field(default_factory=lambda: os.getenv("CLAUDE_MEM_BASE_URL", "http://127.0.0.1:37777"))
    claude_mem_timeout_seconds: float = Field(default_factory=lambda: float(os.getenv("CLAUDE_MEM_TIMEOUT_SECONDS", "2.5")))

    openspace_enabled: bool = Field(default_factory=lambda: os.getenv("OPENSPACE_ENABLED", "false").lower() == "true")
    openspace_base_url: str = Field(default_factory=lambda: os.getenv("OPENSPACE_BASE_URL", "http://127.0.0.1:8081/mcp"))
    openspace_timeout_seconds: float = Field(default_factory=lambda: float(os.getenv("OPENSPACE_TIMEOUT_SECONDS", "8")))

    max_retrieval_files: int = Field(default_factory=lambda: int(os.getenv("MAX_RETRIEVAL_FILES", "8")))
    max_retrieval_snippets: int = Field(default_factory=lambda: int(os.getenv("MAX_RETRIEVAL_SNIPPETS", "12")))


class Attachment(BaseModel):
    type: Literal["text", "image", "audio", "video", "file"] = "text"
    uri: str | None = None
    mime_type: str | None = None
    content: str | None = None
    metadata: dict[str, Any] = Field(default_factory=dict)


class NormalizedInput(BaseModel):
    user_id: str
    session_id: str
    text: str = ""
    attachments: list[Attachment] = Field(default_factory=list)
    channel: str = "zeptoclaw"
    metadata: dict[str, Any] = Field(default_factory=dict)
    request_id: str | None = None


class SensorOutput(BaseModel):
    sensor: str
    kind: str
    text: str
    is_stub: bool = False
    metadata: dict[str, Any] = Field(default_factory=dict)


class QueryResponse(BaseModel):
    request_id: str
    user_id: str
    session_id: str
    answer: str
    route: str
    used_stub_sensors: list[str] = Field(default_factory=list)
    retrieved_context: list[dict[str, Any]] = Field(default_factory=list)
    openspace: dict[str, Any] = Field(default_factory=dict)
    created_at: str


class IngestResponse(BaseModel):
    request_id: str
    status: str
    notes_written: list[str] = Field(default_factory=list)
    used_stub_sensors: list[str] = Field(default_factory=list)


class StopRequest(BaseModel):
    user_id: str
    session_id: str


class SensorAdapter(ABC):
    name: str = "base"

    @abstractmethod
    async def process(self, input_data: NormalizedInput, attachment: Attachment | None = None) -> SensorOutput:
        raise NotImplementedError


class TextSensorAdapter(SensorAdapter):
    name = "text"

    async def process(self, input_data: NormalizedInput, attachment: Attachment | None = None) -> SensorOutput:
        text = (attachment.content if attachment and attachment.content else input_data.text).strip()
        return SensorOutput(sensor=self.name, kind="text", text=text, metadata={"channel": input_data.channel})


class ImageSensorAdapterStub(SensorAdapter):
    name = "image_stub"

    async def process(self, input_data: NormalizedInput, attachment: Attachment | None = None) -> SensorOutput:
        return SensorOutput(
            sensor=self.name,
            kind="image",
            text=f"[IMAGE_STUB] uri={attachment.uri if attachment else None}",
            is_stub=True,
            metadata={"status": "stub_not_implemented"},
        )


class AudioSensorAdapterStub(SensorAdapter):
    name = "audio_stub"

    async def process(self, input_data: NormalizedInput, attachment: Attachment | None = None) -> SensorOutput:
        return SensorOutput(
            sensor=self.name,
            kind="audio",
            text=f"[AUDIO_STUB] uri={attachment.uri if attachment else None}",
            is_stub=True,
            metadata={"status": "stub_not_implemented"},
        )


class VideoSensorAdapterStub(SensorAdapter):
    name = "video_stub"

    async def process(self, input_data: NormalizedInput, attachment: Attachment | None = None) -> SensorOutput:
        return SensorOutput(
            sensor=self.name,
            kind="video",
            text=f"[VIDEO_STUB] uri={attachment.uri if attachment else None}",
            is_stub=True,
            metadata={"status": "stub_not_implemented"},
        )


class LlamaCppClient:
    def __init__(self, settings: Settings, logger: logging.Logger) -> None:
        self.settings = settings
        self.logger = logger
        self.timeout = httpx.Timeout(timeout=settings.model_timeout_seconds)

    def _headers(self) -> dict[str, str]:
        return {
            "Authorization": f"Bearer {self.settings.model_api_key}",
            "Content-Type": "application/json",
        }

    async def health(self) -> dict[str, Any]:
        try:
            async with httpx.AsyncClient(timeout=5.0) as client:
                resp = await client.get(f"{self.settings.model_base_url}/models", headers=self._headers())
                return {"ok": resp.status_code < 300, "status_code": resp.status_code}
        except Exception as exc:
            return {"ok": False, "error": str(exc)}

    async def chat(self, messages: list[dict[str, str]], stream: bool = False) -> str:
        payload = {
            "model": self.settings.model_name,
            "messages": messages,
            "temperature": 0.2,
            "stream": stream,
        }
        async with httpx.AsyncClient(timeout=self.timeout) as client:
            try:
                resp = await client.post(
                    f"{self.settings.model_base_url}/chat/completions",
                    headers=self._headers(),
                    json=payload,
                )
                resp.raise_for_status()
                data = resp.json()
                return data["choices"][0]["message"]["content"]
            except httpx.HTTPError as exc:
                self.logger.error("model_call_failed", extra={"error": str(exc)})
                raise

    async def stream_chat(self, messages: list[dict[str, str]]) -> AsyncGenerator[str, None]:
        payload = {
            "model": self.settings.model_name,
            "messages": messages,
            "temperature": 0.2,
            "stream": True,
        }
        url = f"{self.settings.model_base_url}/chat/completions"
        async with httpx.AsyncClient(timeout=self.timeout) as client:
            try:
                async with client.stream("POST", url, headers=self._headers(), json=payload) as resp:
                    resp.raise_for_status()
                    async for line in resp.aiter_lines():
                        if not line or not line.startswith("data:"):
                            continue
                        chunk = line[5:].strip()
                        if chunk == "[DONE]":
                            break
                        try:
                            data = json.loads(chunk)
                            delta = data.get("choices", [{}])[0].get("delta", {}).get("content")
                            if delta:
                                yield delta
                        except json.JSONDecodeError:
                            continue
            except Exception:
                full = await self.chat(messages, stream=False)
                for i in range(0, len(full), 120):
                    yield full[i : i + 120]


class ClaudeMemClient:
    def __init__(self, settings: Settings, logger: logging.Logger) -> None:
        self.enabled = settings.claude_mem_enabled
        self.base_url = settings.claude_mem_base_url.rstrip("/")
        self.timeout = settings.claude_mem_timeout_seconds
        self.logger = logger

    async def health(self) -> dict[str, Any]:
        if not self.enabled:
            return {"ok": False, "status": "not_configured"}
        try:
            async with httpx.AsyncClient(timeout=self.timeout) as client:
                resp = await client.get(f"{self.base_url}/health")
                return {"ok": resp.status_code < 300, "status_code": resp.status_code}
        except Exception as exc:
            return {"ok": False, "status": "unavailable", "error": str(exc)}

    async def _post(self, path: str, payload: dict[str, Any]) -> dict[str, Any]:
        if not self.enabled:
            return {"ok": False, "status": "not_configured"}
        try:
            async with httpx.AsyncClient(timeout=self.timeout) as client:
                resp = await client.post(f"{self.base_url}{path}", json=payload)
                return {"ok": resp.status_code < 300, "status_code": resp.status_code}
        except Exception as exc:
            self.logger.warning("claude_mem_failed", extra={"path": path, "error": str(exc)})
            return {"ok": False, "status": "unavailable", "error": str(exc)}

    async def observe(self, payload: dict[str, Any]) -> dict[str, Any]:
        return await self._post("/api/sessions/observations", payload)

    async def summarize(self, payload: dict[str, Any]) -> dict[str, Any]:
        return await self._post("/api/sessions/summarize", payload)

    async def complete(self, payload: dict[str, Any]) -> dict[str, Any]:
        return await self._post("/api/sessions/complete", payload)


class OpenSpaceClient:
    def __init__(self, settings: Settings, logger: logging.Logger) -> None:
        self.enabled = settings.openspace_enabled
        self.base_url = settings.openspace_base_url.rstrip("/")
        self.timeout = settings.openspace_timeout_seconds
        self.logger = logger

    async def health(self) -> dict[str, Any]:
        if not self.enabled:
            return {"ok": False, "status": "not_configured"}
        try:
            async with httpx.AsyncClient(timeout=self.timeout) as client:
                resp = await client.get(self.base_url)
                return {"ok": resp.status_code < 300, "status_code": resp.status_code}
        except Exception as exc:
            return {"ok": False, "status": "unavailable", "error": str(exc)}

    async def delegate_task(self, task: str, context: dict[str, Any]) -> dict[str, Any]:
        if not self.enabled:
            return {"status": "not_configured"}
        # TODO: Plug the real MCP delegation protocol when OpenSpace contract is finalized.
        health = await self.health()
        if not health.get("ok"):
            return {"status": "unavailable", "detail": health}
        return {"status": "unavailable", "detail": "mcp_protocol_not_implemented", "task": task, "context": context}

    async def discover_skill(self, query: str) -> dict[str, Any]:
        if not self.enabled:
            return {"status": "not_configured"}
        health = await self.health()
        if not health.get("ok"):
            return {"status": "unavailable", "detail": health}
        return {"status": "unavailable", "detail": "mcp_protocol_not_implemented", "query": query}


class VaultMemory:
    def __init__(self, settings: Settings) -> None:
        self.vault_root = settings.vault_root
        self.work_root = settings.work_root
        self.max_files = settings.max_retrieval_files
        self.max_snippets = settings.max_retrieval_snippets
        self.inbox_dir = self.vault_root / "Inbox"
        self.projects_dir = self.vault_root / "Projects"
        self.people_dir = self.vault_root / "People"
        self.areas_dir = self.vault_root / "Areas"
        self.archive_dir = self.vault_root / "Archive"
        self.ensure_dirs()

    def ensure_dirs(self) -> None:
        for d in [
            self.vault_root,
            self.work_root,
            self.inbox_dir,
            self.projects_dir,
            self.people_dir,
            self.areas_dir,
            self.archive_dir,
        ]:
            d.mkdir(parents=True, exist_ok=True)

    def _safe_path(self, target: Path) -> Path:
        resolved = target.resolve()
        if not str(resolved).startswith(str(self.vault_root)) and not str(resolved).startswith(str(self.work_root)):
            raise ValueError("unsafe_path")
        return resolved

    @staticmethod
    def slugify(text: str) -> str:
        cleaned = re.sub(r"[^a-zA-Z0-9\s-_]", "", text).strip().lower()
        cleaned = re.sub(r"[\s_]+", "-", cleaned)
        return cleaned[:80] or "note"

    def write_markdown_note(self, folder: Path, title: str, body: str, metadata: dict[str, Any] | None = None) -> Path:
        metadata = metadata or {}
        slug = self.slugify(title)
        path = self._safe_path(folder / f"{slug}.md")
        now = datetime.now(UTC).isoformat()
        frontmatter = {
            "title": title,
            "created_at": now,
            "updated_at": now,
            **metadata,
        }
        fm = "---\n" + "\n".join(f"{k}: {json.dumps(v, ensure_ascii=False) if isinstance(v, (dict, list)) else v}" for k, v in frontmatter.items()) + "\n---\n\n"
        path.write_text(f"{fm}{body.strip()}\n", encoding="utf-8")
        return path

    def append_daily_inbox(self, text: str, metadata: dict[str, Any]) -> Path:
        date_key = datetime.now(UTC).strftime("%Y-%m-%d")
        path = self._safe_path(self.inbox_dir / f"{date_key}.md")
        if not path.exists():
            path.write_text("---\ntitle: Daily Inbox\n---\n\n", encoding="utf-8")
        timestamp = datetime.now(UTC).isoformat()
        payload = json.dumps(metadata, ensure_ascii=False)
        with path.open("a", encoding="utf-8") as f:
            f.write(f"- [{timestamp}] {text.strip()} | meta={payload}\n")
        return path

    def search(self, query: str, top_k: int | None = None) -> list[dict[str, Any]]:
        q = query.lower().strip()
        if not q:
            return []
        terms = [t for t in re.split(r"\W+", q) if t]
        matches: list[tuple[float, Path, str]] = []
        files = list(self.vault_root.rglob("*.md"))[: self.max_files * 20]
        now = datetime.now(UTC).timestamp()

        for fp in files:
            try:
                content = fp.read_text(encoding="utf-8", errors="ignore")
            except Exception:
                continue
            lc = content.lower()
            name = fp.stem.lower()
            score = 0.0
            for t in terms:
                score += lc.count(t) * 1.0
                if t in name:
                    score += 2.0
            if score <= 0:
                continue
            age_days = max(1.0, (now - fp.stat().st_mtime) / 86400.0)
            recency_bonus = max(0.0, 5.0 - min(5.0, age_days / 7.0))
            score += recency_bonus
            snippet = self._best_snippet(content, terms)
            matches.append((score, fp, snippet))

        matches.sort(key=lambda x: x[0], reverse=True)
        k = top_k or self.max_snippets
        out: list[dict[str, Any]] = []
        for score, fp, snippet in matches[:k]:
            out.append({"file": str(fp), "score": round(score, 3), "snippet": snippet})
        return out

    @staticmethod
    def _best_snippet(content: str, terms: list[str], span: int = 260) -> str:
        text = re.sub(r"\s+", " ", content)
        idx = -1
        for t in terms:
            idx = text.lower().find(t)
            if idx >= 0:
                break
        if idx < 0:
            return text[:span]
        start = max(0, idx - span // 3)
        end = min(len(text), start + span)
        return text[start:end]


def build_system_prompt() -> str:
    return (
        "Você é um assistente pessoal técnico local-first. "
        "Foque em engenharia elétrica, direito e gestão de vida. "
        "Use memória externa curada quando disponível (vault). "
        "Se faltar contexto, declare incerteza e não invente fatos. "
        "Priorize respostas concisas, ações seguras e próximos passos verificáveis. "
        "Quando apropriado, proponha uso de skills/delegação sem quebrar o fluxo principal."
    )


def build_context_block(retrieved: list[dict[str, Any]], sensor_outputs: list[SensorOutput]) -> str:
    mem_block = "\n".join(f"- {item['file']}: {item['snippet']}" for item in retrieved)
    sensor_block = "\n".join(f"- [{s.kind}] {s.text}" for s in sensor_outputs)
    return f"## Vault Context\n{mem_block or '(empty)'}\n\n## Sensor Observations\n{sensor_block or '(empty)'}"


def route_request(input_data: NormalizedInput) -> str:
    text = input_data.text.lower()
    complex_signals = ["plano", "roadmap", "arquitetura", "multi-etapas", "delegar", "analisar contrato"]
    if len(text) > 500 or any(sig in text for sig in complex_signals):
        return "complex"
    return "direct"


async def preprocess_input(input_data: NormalizedInput, sensor_map: dict[str, SensorAdapter]) -> tuple[str, list[SensorOutput], list[str]]:
    outputs: list[SensorOutput] = []
    stub_used: list[str] = []

    text_output = await sensor_map["text"].process(input_data)
    if text_output.text:
        outputs.append(text_output)

    for att in input_data.attachments:
        adapter_key = att.type if att.type in sensor_map else "text"
        out = await sensor_map[adapter_key].process(input_data, att)
        outputs.append(out)
        if out.is_stub:
            stub_used.append(out.sensor)

    consolidated = "\n".join(f"[{o.kind}] {o.text}" for o in outputs if o.text)
    return consolidated.strip(), outputs, sorted(set(stub_used))


async def persist_interaction(
    vault: VaultMemory,
    input_data: NormalizedInput,
    answer: str,
    route: str,
    request_id: str,
) -> list[str]:
    body = (
        f"## User\n{input_data.text}\n\n"
        f"## Assistant\n{answer}\n\n"
        f"## Meta\n- route: {route}\n- request_id: {request_id}\n"
    )
    notes: list[str] = []
    note = vault.write_markdown_note(
        vault.inbox_dir,
        title=f"interaction-{input_data.session_id}-{request_id[:8]}",
        body=body,
        metadata={"user_id": input_data.user_id, "session_id": input_data.session_id},
    )
    notes.append(str(note))
    daily = vault.append_daily_inbox(
        text=f"{input_data.user_id}/{input_data.session_id}: {input_data.text[:240]}",
        metadata={"request_id": request_id, "route": route},
    )
    notes.append(str(daily))
    return notes


def spawn_background_tasks(
    claude_mem: ClaudeMemClient,
    input_data: NormalizedInput,
    answer: str,
    request_id: str,
) -> None:
    payload = {
        "request_id": request_id,
        "user_id": input_data.user_id,
        "session_id": input_data.session_id,
        "input_text": input_data.text,
        "answer": answer,
        "timestamp": datetime.now(UTC).isoformat(),
    }
    asyncio.create_task(claude_mem.observe(payload))


settings = Settings()
logging.basicConfig(
    level=getattr(logging, settings.agent_app_log_level.upper(), logging.INFO),
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
logger = logging.getLogger("agent_app")

app = AgentApp(name=settings.agent_app_name)
app.state.settings = settings
app.state.vault = VaultMemory(settings)
app.state.llm = LlamaCppClient(settings, logger)
app.state.claude_mem = ClaudeMemClient(settings, logger)
app.state.openspace = OpenSpaceClient(settings, logger)
app.state.sensors = {
    "text": TextSensorAdapter(),
    "image": ImageSensorAdapterStub(),
    "audio": AudioSensorAdapterStub(),
    "video": VideoSensorAdapterStub(),
}
app.state.session_cache = {}


async def run_pipeline(input_data: NormalizedInput, streaming: bool = False) -> QueryResponse:
    request_id = input_data.request_id or str(uuid.uuid4())
    consolidated, sensor_outputs, used_stub_sensors = await preprocess_input(input_data, app.state.sensors)
    retrieved = app.state.vault.search(consolidated or input_data.text)
    route = route_request(input_data)

    openspace_result: dict[str, Any] = {}
    if route == "complex":
        openspace_result = await app.state.openspace.delegate_task(
            task=input_data.text,
            context={"session_id": input_data.session_id, "user_id": input_data.user_id},
        )

    context_block = build_context_block(retrieved, sensor_outputs)
    messages = [
        {"role": "system", "content": build_system_prompt()},
        {"role": "user", "content": f"{context_block}\n\n## Session Input\n{consolidated or input_data.text}"},
    ]

    if streaming:
        chunks: list[str] = []
        async for piece in app.state.llm.stream_chat(messages):
            chunks.append(piece)
        answer = "".join(chunks).strip()
    else:
        answer = (await app.state.llm.chat(messages)).strip()

    await persist_interaction(app.state.vault, input_data, answer, route, request_id)
    spawn_background_tasks(app.state.claude_mem, input_data, answer, request_id)

    cache_key = f"{input_data.user_id}:{input_data.session_id}"
    app.state.session_cache[cache_key] = {
        "last_request_id": request_id,
        "last_user_text": input_data.text,
        "last_answer": answer,
        "updated_at": datetime.now(UTC).isoformat(),
    }

    return QueryResponse(
        request_id=request_id,
        user_id=input_data.user_id,
        session_id=input_data.session_id,
        answer=answer,
        route=route,
        used_stub_sensors=used_stub_sensors,
        retrieved_context=retrieved,
        openspace=openspace_result,
        created_at=datetime.now(UTC).isoformat(),
    )


def _http_app() -> Any:
    if hasattr(app, "fastapi"):
        return app.fastapi
    if hasattr(app, "app"):
        return app.app
    raise RuntimeError("AgentApp fastapi handle not found")


http_app = _http_app()


@http_app.get("/info")
async def info() -> dict[str, Any]:
    return {
        "name": settings.agent_app_name,
        "version": APP_VERSION,
        "host": settings.agent_app_host,
        "port": settings.agent_app_port,
        "vault_root": str(settings.vault_root),
        "work_root": str(settings.work_root),
        "model": {"base_url": settings.model_base_url, "name": settings.model_name},
        "claude_mem_enabled": settings.claude_mem_enabled,
        "openspace_enabled": settings.openspace_enabled,
    }


@http_app.get("/deps")
async def deps() -> dict[str, Any]:
    model_health, claude_health, openspace_health = await asyncio.gather(
        app.state.llm.health(),
        app.state.claude_mem.health(),
        app.state.openspace.health(),
    )
    return {
        "model": model_health,
        "claude_mem": claude_health,
        "openspace": openspace_health,
        "vault": {"ok": settings.vault_root.exists() and settings.vault_root.is_dir()},
    }


@http_app.post("/ingest", response_model=IngestResponse)
async def ingest(input_data: NormalizedInput) -> IngestResponse:
    request_id = input_data.request_id or str(uuid.uuid4())
    consolidated, _, used_stub_sensors = await preprocess_input(input_data, app.state.sensors)
    notes_written = await persist_interaction(
        app.state.vault,
        input_data,
        answer=f"[INGEST_ONLY] {consolidated[:400]}",
        route="ingest",
        request_id=request_id,
    )
    return IngestResponse(request_id=request_id, status="ok", notes_written=notes_written, used_stub_sensors=used_stub_sensors)


@http_app.post("/query_sync", response_model=QueryResponse)
async def query_sync(input_data: NormalizedInput) -> QueryResponse:
    return await run_pipeline(input_data, streaming=False)


@app.query("/query")
async def query(input_data: NormalizedInput) -> dict[str, Any]:
    response = await run_pipeline(input_data, streaming=True)
    return response.model_dump()


@http_app.post("/stop")
async def stop_chat(req: StopRequest) -> dict[str, Any]:
    key = f"{req.user_id}:{req.session_id}"
    stopped = False
    if hasattr(app, "stop_chat"):
        try:
            app.stop_chat(user_id=req.user_id, session_id=req.session_id)
            stopped = True
        except TypeError:
            try:
                app.stop_chat(req.user_id, req.session_id)
                stopped = True
            except Exception:
                stopped = False
        except Exception:
            stopped = False
    app.state.session_cache.pop(key, None)
    return {"ok": True, "stopped": stopped, "session_key": key}


@http_app.get("/memory/search")
async def memory_search(q: str, k: int = 8) -> dict[str, Any]:
    return {"query": q, "results": app.state.vault.search(q, top_k=min(max(k, 1), 30))}


if __name__ == "__main__":
    app.run(host=settings.agent_app_host, port=settings.agent_app_port)
