"""Saari settings environment variables se (12-factor). Helm chart / docker-compose yahi set karte hain."""

import os
from dataclasses import dataclass, field


def _bool(name: str, default: bool) -> bool:
    return os.getenv(name, str(default)).lower() in ("1", "true", "yes")


@dataclass(frozen=True)
class Settings:
    app_name: str = field(default_factory=lambda: os.getenv("APP_NAME", "rag-app"))
    team: str = field(default_factory=lambda: os.getenv("TEAM", "local"))
    # ALB path-based routing: /apps/<app-name>/... (ALB prefix strip nahi karta, isliye app khud prefix samajhta hai)
    base_path: str = field(default_factory=lambda: os.getenv("BASE_PATH", "").rstrip("/"))

    # LLM gateway (cluster mein LiteLLM; local/CI mein seedha Ollama ka OpenAI-compatible /v1)
    llm_base_url: str = field(default_factory=lambda: os.getenv("LLM_BASE_URL", "http://localhost:4000/v1"))
    llm_api_key: str = field(default_factory=lambda: os.getenv("LLM_API_KEY", "sk-local"))
    chat_model: str = field(default_factory=lambda: os.getenv("CHAT_MODEL", "llama3.2-1b"))
    embed_model: str = field(default_factory=lambda: os.getenv("EMBED_MODEL", "nomic-embed-text"))
    embed_dim: int = field(default_factory=lambda: int(os.getenv("EMBED_DIM", "768")))
    llm_timeout_s: float = field(default_factory=lambda: float(os.getenv("LLM_TIMEOUT_S", "120")))
    max_tokens: int = field(default_factory=lambda: int(os.getenv("MAX_TOKENS", "256")))

    # Vector DB
    qdrant_url: str = field(default_factory=lambda: os.getenv("QDRANT_URL", "http://localhost:6333"))
    collection: str = field(default_factory=lambda: os.getenv("QDRANT_COLLECTION", "rag-docs"))
    # Cluster mein collection Crossplane VectorStore banata hai → false. Local/CI mein app khud bana leta hai.
    auto_create_collection: bool = field(default_factory=lambda: _bool("AUTO_CREATE_COLLECTION", True))
    top_k: int = field(default_factory=lambda: int(os.getenv("TOP_K", "4")))
    chunk_size: int = field(default_factory=lambda: int(os.getenv("CHUNK_SIZE", "800")))
    chunk_overlap: int = field(default_factory=lambda: int(os.getenv("CHUNK_OVERLAP", "100")))

    # /ingest protect karne ke liye (khaali = open, sirf local/CI)
    ingest_token: str = field(default_factory=lambda: os.getenv("INGEST_TOKEN", ""))
    sample_docs_dir: str = field(default_factory=lambda: os.getenv("SAMPLE_DOCS_DIR", "/app/sample-docs"))

    # Observability
    otel_enabled: bool = field(default_factory=lambda: _bool("OTEL_ENABLED", False))


settings = Settings()
