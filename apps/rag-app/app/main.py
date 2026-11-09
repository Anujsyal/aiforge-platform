"""AIForge sample RAG API (FastAPI).

Routes (sab BASE_PATH ke neeche bhi, ALB path routing ke liye):
  GET  /healthz   liveness (koi dependency check nahi)
  GET  /readyz    readiness (Qdrant reachable?)
  POST /ask       {"question": "..."} → answer + sources + contexts
  POST /ingest    {"documents":[{"source":"a.md","text":"..."}]} ya {"bundled": true}
  GET  /metrics   Prometheus (sirf root pe, ALB pe expose nahi)
"""

from __future__ import annotations

import hmac
import logging
import time

from fastapi import APIRouter, Depends, FastAPI, Header, HTTPException, Response
from prometheus_client import CONTENT_TYPE_LATEST, generate_latest
from pydantic import BaseModel, Field

from . import telemetry as t
from .config import settings
from .rag import UNKNOWN_ANSWER, RagPipeline

logging.basicConfig(level=logging.INFO, format='{"level":"%(levelname)s","logger":"%(name)s","msg":"%(message)s"}')
log = logging.getLogger("rag-app")


class _ProbeFilter(logging.Filter):
    """Probe/scrape ke access logs drop. Asli run (2026-11-09): Loki mein ~1.8k lines/ghanta, lagbhag saari
    kubelet (/readyz, /healthz), ALB (/apps/<app>/healthz) aur Prometheus (/metrics) ki; asli /ask 5 the."""

    NOISY = ("/healthz", "/readyz", "/metrics")

    def filter(self, record: logging.LogRecord) -> bool:
        args = record.args if isinstance(record.args, tuple) else ()
        path = str(args[2]) if len(args) > 2 else record.getMessage()
        return not path.split("?")[0].endswith(self.NOISY)


logging.getLogger("uvicorn.access").addFilter(_ProbeFilter())
# httpx har Qdrant/LiteLLM call pe INFO likhta hai (probe ke andar bhi). Errors phir bhi WARNING+ pe aate hain.
logging.getLogger("httpx").setLevel(logging.WARNING)


class AskRequest(BaseModel):
    question: str = Field(min_length=3, max_length=2000)


class AskResponse(BaseModel):
    answer: str
    sources: list[str]
    contexts: list[str]
    model: str
    usage: dict
    latency_ms: dict


class IngestDoc(BaseModel):
    source: str = Field(min_length=1, max_length=200)
    text: str = Field(min_length=1)


class IngestRequest(BaseModel):
    documents: list[IngestDoc] = []
    bundled: bool = False  # true = image ke andar wale sample-docs/ ingest karo


_pipeline: RagPipeline | None = None


def get_pipeline() -> RagPipeline:
    global _pipeline
    if _pipeline is None:
        _pipeline = RagPipeline(settings)
    return _pipeline


def check_ingest_token(x_ingest_token: str = Header(default="")) -> None:
    if settings.ingest_token and not hmac.compare_digest(x_ingest_token, settings.ingest_token):
        raise HTTPException(status_code=401, detail="invalid ingest token")


router = APIRouter()


@router.get("/healthz")
def healthz():
    return {"status": "ok", "app": settings.app_name}


@router.get("/readyz")
def readyz(p: RagPipeline = Depends(get_pipeline)):
    with t.untraced():  # probe har 10s: Qdrant GET ko trace mat karo (Langfuse noise/quota)
        ok = p.ready()
    if not ok:
        raise HTTPException(status_code=503, detail="vector store not reachable")
    return {"status": "ready"}


@router.post("/ask", response_model=AskResponse)
def ask(req: AskRequest, p: RagPipeline = Depends(get_pipeline)):
    start = time.perf_counter()
    try:
        with t.span("rag.ask"):
            ans = p.ask(req.question, trace_id=t.current_trace_id())
    except Exception as exc:  # gateway down / budget exceeded / timeout
        t.REQUESTS.labels(status="error").inc()
        log.error("ask failed: %s", exc)
        # LiteLLM budget khatam hone pe 400/429 deta hai: user ko saaf message
        msg = str(exc)
        if "budget" in msg.lower():
            raise HTTPException(status_code=429, detail="team LLM budget exceeded") from exc
        raise HTTPException(status_code=502, detail="LLM gateway error") from exc

    t.REQUESTS.labels(status="ok").inc()
    t.LATENCY.observe(time.perf_counter() - start)
    t.RETRIEVAL.observe(ans.retrieval_ms / 1000)
    t.TOKENS.labels(type="prompt").inc(ans.prompt_tokens)
    t.TOKENS.labels(type="completion").inc(ans.completion_tokens)
    if UNKNOWN_ANSWER.lower()[:12] in ans.answer.lower():
        t.UNANSWERED.inc()
    for event in ans.guardrails:
        t.GUARDRAIL.labels(event=event).inc()
        log.warning("guardrail: %s", event)

    return AskResponse(
        answer=ans.answer,
        sources=ans.sources,
        contexts=ans.contexts,
        model=ans.model,
        usage={"prompt_tokens": ans.prompt_tokens, "completion_tokens": ans.completion_tokens},
        latency_ms={"retrieval": round(ans.retrieval_ms, 1), "generation": round(ans.generation_ms, 1)},
    )


@router.post("/ingest", dependencies=[Depends(check_ingest_token)])
def ingest(req: IngestRequest, p: RagPipeline = Depends(get_pipeline)):
    docs = [(d.source, d.text) for d in req.documents]
    if req.bundled:
        docs += p.load_sample_docs()
    if not docs:
        raise HTTPException(status_code=400, detail="no documents")
    with t.span("rag.ingest"):
        n = p.ingest(docs)
    t.INGESTED.inc(n)
    log.info("ingested %d chunks from %d documents", n, len(docs))
    return {"documents": len(docs), "chunks": n, "collection": settings.collection}


app = FastAPI(title=f"AIForge RAG: {settings.app_name}", docs_url=f"{settings.base_path}/docs",
              openapi_url=f"{settings.base_path}/openapi.json")
app.include_router(router)  # root: k8s probes
if settings.base_path:
    app.include_router(router, prefix=settings.base_path)  # ALB: /apps/<name>/ask


@app.get("/metrics", include_in_schema=False)
def metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


t.setup_tracing(app, settings)
