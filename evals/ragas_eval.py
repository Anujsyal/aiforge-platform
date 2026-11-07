"""RAGAS metrics (ADVISORY, build fail nahi karta).

Kyun advisory? RAGAS ko ek "judge" LLM chahiye. CI mein judge bhi wahi chhota llama3.2:1b hai,
jiske scores noisy hote hain (same input pe 0.6 se 0.9 tak). Isliye blocking gate promptfoo ke
deterministic asserts hain, aur RAGAS trend dekhne ke liye report hai (Problems faced #9).

Usage:
  RAG_URL=http://localhost:8080 JUDGE_BASE_URL=http://localhost:11434/v1 \
  python evals/ragas_eval.py --out evals/results/ragas.json
"""

from __future__ import annotations

import argparse
import json
import math
import os
from pathlib import Path

import httpx
import yaml


def collect_samples(rag_url: str, dataset_path: Path) -> list[dict]:
    cases = yaml.safe_load(dataset_path.read_text(encoding="utf-8"))
    samples = []
    with httpx.Client(timeout=300) as client:
        for case in cases:
            v = case["vars"]
            r = client.post(f"{rag_url}/ask", json={"question": v["question"]})
            r.raise_for_status()
            body = r.json()
            samples.append(
                {
                    "user_input": v["question"],
                    "response": body["answer"],
                    "retrieved_contexts": body["contexts"] or [""],
                    "reference": v["reference"],
                }
            )
    return samples


def score(samples: list[dict]) -> dict:
    from langchain_openai import ChatOpenAI, OpenAIEmbeddings
    from ragas import EvaluationDataset, evaluate
    from ragas.embeddings import LangchainEmbeddingsWrapper
    from ragas.llms import LangchainLLMWrapper
    from ragas.metrics import Faithfulness, LLMContextRecall, ResponseRelevancy

    base = os.environ.get("JUDGE_BASE_URL", "http://localhost:11434/v1")
    key = os.environ.get("JUDGE_API_KEY", "ollama")
    judge = LangchainLLMWrapper(
        ChatOpenAI(model=os.environ.get("JUDGE_MODEL", "llama3.2:1b"), base_url=base, api_key=key, temperature=0)
    )
    emb = LangchainEmbeddingsWrapper(
        OpenAIEmbeddings(model="nomic-embed-text", base_url=base, api_key=key, check_embedding_ctx_length=False)
    )
    result = evaluate(
        EvaluationDataset.from_list(samples),
        metrics=[Faithfulness(), ResponseRelevancy(), LLMContextRecall()],
        llm=judge,
        embeddings=emb,
        raise_exceptions=False,  # judge kabhi galat JSON deta hai → NaN, crash nahi
    )
    df = result.to_pandas()
    out = {}
    for col in ("faithfulness", "answer_relevancy", "context_recall"):
        if col in df:
            vals = [x for x in df[col].tolist() if isinstance(x, (int, float)) and not math.isnan(x)]
            out[col] = round(sum(vals) / len(vals), 3) if vals else None
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dataset", default=str(Path(__file__).with_name("dataset.yaml")))
    ap.add_argument("--out", default="evals/results/ragas.json")
    args = ap.parse_args()

    samples = collect_samples(os.environ.get("RAG_URL", "http://localhost:8080"), Path(args.dataset))
    try:
        scores = score(samples)
        status = "ok"
    except Exception as exc:  # advisory: report likh do, pipeline mat todo
        scores, status = {}, f"error: {exc}"

    Path(args.out).parent.mkdir(parents=True, exist_ok=True)
    Path(args.out).write_text(json.dumps({"status": status, "samples": len(samples), "scores": scores}, indent=2))
    print(json.dumps({"status": status, "scores": scores}, indent=2))


if __name__ == "__main__":
    main()
