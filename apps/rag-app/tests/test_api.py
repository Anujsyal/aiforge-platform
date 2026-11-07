"""Unit tests: koi LLM ya Qdrant nahi chahiye (fake pipeline). Asli quality test = evals/ (promptfoo)."""

from fastapi.testclient import TestClient

from app.main import app, get_pipeline
from app.rag import Answer


class FakePipeline:
    def __init__(self):
        self.ingested = []

    def ready(self):
        return True

    def ask(self, question, trace_id=None):
        return Answer(
            answer="The default budget is 25 USD per month.",
            sources=["budgets.md"],
            contexts=["Every team gets a default LLM budget of 25 USD per month."],
            model="llama3.2-1b",
            prompt_tokens=120,
            completion_tokens=12,
            retrieval_ms=5.0,
            generation_ms=900.0,
        )

    def ingest(self, docs):
        self.ingested.extend(docs)
        return len(docs) * 2

    def load_sample_docs(self):
        return [("budgets.md", "x")]


class BrokenPipeline(FakePipeline):
    def ask(self, question, trace_id=None):
        raise RuntimeError("Budget has been exceeded! Current cost: 25.1")


fake = FakePipeline()
app.dependency_overrides[get_pipeline] = lambda: fake
client = TestClient(app)


def test_healthz():
    assert client.get("/healthz").json()["status"] == "ok"


def test_ask_returns_answer_and_sources():
    r = client.post("/ask", json={"question": "What is the default budget?"})
    assert r.status_code == 200
    body = r.json()
    assert "25 USD" in body["answer"]
    assert body["sources"] == ["budgets.md"]
    assert body["usage"]["prompt_tokens"] == 120


def test_ask_validates_input():
    assert client.post("/ask", json={"question": ""}).status_code == 422


def test_ingest_bundled():
    r = client.post("/ingest", json={"bundled": True})
    assert r.status_code == 200
    assert r.json()["documents"] == 1


def test_ingest_requires_documents():
    assert client.post("/ingest", json={}).status_code == 400


def test_budget_exceeded_maps_to_429():
    app.dependency_overrides[get_pipeline] = lambda: BrokenPipeline()
    try:
        r = client.post("/ask", json={"question": "anything here?"})
        assert r.status_code == 429
    finally:
        app.dependency_overrides[get_pipeline] = lambda: fake


def test_metrics_exposed():
    r = client.get("/metrics")
    assert r.status_code == 200
    assert "rag_requests_total" in r.text
