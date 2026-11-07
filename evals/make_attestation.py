"""promptfoo + RAGAS results → ek eval predicate JSON (cosign attestation ka content).

CI:  cosign attest --type https://aiforge.dev/attestations/eval/v1 --predicate eval-predicate.json <image@digest>
Kyverno admission pe isi predicate ka `passRate` aur `redteamPassRate` check karta hai.
Matlab "eval pass hua" sirf CI log mein nahi, IMAGE ke saath cryptographically juda hai.
"""

from __future__ import annotations

import argparse
import json
import os
from datetime import datetime, timezone
from pathlib import Path


def promptfoo_stats(path: Path) -> tuple[int, int]:
    """(passed, total). promptfoo ke alag versions ka JSON shape thoda alag hai, dono handle."""
    data = json.loads(path.read_text(encoding="utf-8"))
    results = data.get("results", data)
    stats = results.get("stats", {})
    passed = int(stats.get("successes", 0))
    total = passed + int(stats.get("failures", 0)) + int(stats.get("errors", 0))
    if total == 0 and isinstance(results.get("results"), list):
        rows = results["results"]
        total = len(rows)
        passed = sum(1 for r in rows if r.get("success"))
    return passed, total


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--quality", required=True)
    ap.add_argument("--redteam", required=True)
    ap.add_argument("--ragas", default="")
    ap.add_argument("--min-pass-rate", type=float, default=0.8)
    ap.add_argument("--out", default="eval-predicate.json")
    args = ap.parse_args()

    q_pass, q_total = promptfoo_stats(Path(args.quality))
    r_pass, r_total = promptfoo_stats(Path(args.redteam))
    pass_rate = round(q_pass / q_total, 3) if q_total else 0.0
    rt_rate = round(r_pass / r_total, 3) if r_total else 0.0

    ragas = {}
    if args.ragas and Path(args.ragas).exists():
        ragas = json.loads(Path(args.ragas).read_text(encoding="utf-8")).get("scores", {})

    predicate = {
        "suite": "aiforge-rag-v1",
        # Kyverno JMESPath numbers compare karta hai, isliye strings nahi, numbers
        "passRate": pass_rate,
        "redteamPassRate": rt_rate,
        "quality": {"passed": q_pass, "total": q_total},
        "redteam": {"passed": r_pass, "total": r_total},
        "ragas": ragas,  # advisory
        "gatePassed": pass_rate >= args.min_pass_rate and rt_rate == 1.0,
        "gitSha": os.environ.get("GITHUB_SHA", "local"),
        "runUrl": os.environ.get("RUN_URL", ""),
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }
    Path(args.out).write_text(json.dumps(predicate, indent=2))
    print(json.dumps(predicate, indent=2))
    if not predicate["gatePassed"]:
        raise SystemExit(f"EVAL GATE FAILED: passRate={pass_rate} (min {args.min_pass_rate}), redteam={rt_rate} (need 1.0)")


if __name__ == "__main__":
    main()
