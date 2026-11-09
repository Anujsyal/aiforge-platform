"""OpenTelemetry traces + Prometheus metrics.

Traces: app → OTLP/HTTP → OTel Collector (observability ns) → Langfuse (/api/public/otel).
App ke paas Langfuse keys NAHI hain; sirf collector ke paas. Team namespace ka egress bhi sirf collector tak.

Standard OTEL_* env vars use hote hain (OTEL_EXPORTER_OTLP_ENDPOINT, OTEL_SERVICE_NAME ...).
"""

from __future__ import annotations

from fastapi import FastAPI
from prometheus_client import Counter, Histogram

from .config import Settings

REQUESTS = Counter("rag_requests_total", "RAG /ask requests", ["status"])
UNANSWERED = Counter("rag_unanswered_total", "Answers jahan model ne 'I don't know' bola (quality signal)")
TOKENS = Counter("rag_llm_tokens_total", "LLM tokens via gateway", ["type"])
LATENCY = Histogram(
    "rag_request_duration_seconds",
    "End-to-end /ask latency",
    buckets=(0.5, 1, 2, 5, 10, 20, 30, 60, 120),
)
RETRIEVAL = Histogram(
    "rag_retrieval_duration_seconds", "Qdrant retrieval latency", buckets=(0.01, 0.05, 0.1, 0.25, 0.5, 1, 2, 5)
)
INGESTED = Counter("rag_ingested_chunks_total", "Chunks written to vector store")
GUARDRAIL = Counter("rag_guardrail_events_total", "Guardrail hits (injection blocked / context sanitized / output redacted)", ["event"])


def setup_tracing(app: FastAPI, s: Settings) -> None:
    if not s.otel_enabled:
        return
    # Import andar: OTEL off ho to packages load hi nahi hote (unit tests fast)
    from opentelemetry import trace
    from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
    from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
    from opentelemetry.instrumentation.httpx import HTTPXClientInstrumentor
    from opentelemetry.sdk.resources import Resource
    from opentelemetry.sdk.trace import TracerProvider
    from opentelemetry.sdk.trace.export import BatchSpanProcessor

    resource = Resource.create(
        {"service.name": s.app_name, "service.namespace": "aiforge", "aiforge.team": s.team}
    )
    provider = TracerProvider(resource=resource)
    provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter()))  # endpoint env se
    trace.set_tracer_provider(provider)

    FastAPIInstrumentor.instrument_app(app, excluded_urls="healthz,readyz,metrics")
    HTTPXClientInstrumentor().instrument()  # openai SDK httpx use karta hai → LLM calls ke spans


def current_trace_id() -> str | None:
    try:
        from opentelemetry import trace

        ctx = trace.get_current_span().get_span_context()
        return format(ctx.trace_id, "032x") if ctx.is_valid else None
    except Exception:
        return None


def span(name: str):
    """Chhota helper: OTel na ho to no-op context manager."""
    try:
        from opentelemetry import trace

        return trace.get_tracer("rag-app").start_as_current_span(name)
    except Exception:
        from contextlib import nullcontext

        return nullcontext()
