"""Per-team AI showback: LLM token cost (LiteLLM) + infra cost (OpenCost) → ek table + CSV.

Project 1 (FinOps showback) wala idea, AI platform pe: "team-alpha ne is hafte $X LLM pe aur $Y infra pe kharch kiya".

Pehle 2 port-forwards (alag terminals):
  kubectl -n ai-gateway port-forward svc/litellm 4000:4000
  kubectl -n opencost   port-forward svc/opencost 9003:9003
Run:
  LITELLM_MASTER_KEY=$(kubectl -n ai-gateway get secret litellm-secrets -o jsonpath='{.data.LITELLM_MASTER_KEY}' | base64 -d) \
  python scripts/showback_report.py --window 7d --csv showback.csv
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import subprocess
import urllib.request
from collections import defaultdict


def get_json(url: str, token: str | None = None):
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"} if token else {})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read().decode())


def namespace_to_team() -> dict[str, str]:
    """Namespace label aiforge.io/team se mapping (ApplicationSet ye label lagata hai)."""
    out = subprocess.run(["kubectl", "get", "ns", "-o", "json"], capture_output=True, text=True, check=True)
    mapping = {}
    for ns in json.loads(out.stdout)["items"]:
        labels = ns["metadata"].get("labels", {})
        mapping[ns["metadata"]["name"]] = labels.get("aiforge.io/team") or (
            "platform" if labels.get("aiforge.io/platform") == "true" else "shared"
        )
    return mapping


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--window", default="7d", help="OpenCost window: 24h, 7d, 30d")
    ap.add_argument("--litellm", default="http://localhost:4000")
    ap.add_argument("--opencost", default="http://localhost:9003")
    ap.add_argument("--csv", default="")
    args = ap.parse_args()

    rows: dict[str, dict] = defaultdict(lambda: {"llm_spend": 0.0, "llm_budget": None, "infra_cost": 0.0})

    # --- LLM spend (LiteLLM team spend = current budget period) ---
    teams = get_json(f"{args.litellm}/team/list", os.environ["LITELLM_MASTER_KEY"])
    for t in teams:
        name = t.get("team_alias") or t["team_id"]
        rows[name]["llm_spend"] += float(t.get("spend") or 0)
        rows[name]["llm_budget"] = t.get("max_budget")

    # --- Infra cost (OpenCost allocation per namespace → team) ---
    ns_team = namespace_to_team()
    alloc = get_json(f"{args.opencost}/allocation/compute?window={args.window}&aggregate=namespace&accumulate=true")
    for window in alloc.get("data", []):
        for ns, a in (window or {}).items():
            team = ns_team.get(ns, "shared" if ns != "__idle__" else "idle")
            rows[team]["infra_cost"] += float(a.get("totalCost") or 0)

    header = f"{'team':<16}{'LLM spend $':>14}{'LLM budget $':>14}{'infra $ (' + args.window + ')':>18}{'total $':>12}"
    print(header)
    print("-" * len(header))
    out = []
    for team, r in sorted(rows.items(), key=lambda kv: -(kv[1]["llm_spend"] + kv[1]["infra_cost"])):
        total = r["llm_spend"] + r["infra_cost"]
        budget = "-" if r["llm_budget"] is None else f"{r['llm_budget']:.2f}"
        print(f"{team:<16}{r['llm_spend']:>14.4f}{budget:>14}{r['infra_cost']:>18.2f}{total:>12.2f}")
        out.append({"team": team, **r, "total": round(total, 4)})
    print("\nNote: 'platform' + 'idle' = shared cost. Chargeback model mein ise teams ke usage ratio se baant-te hain.")

    if args.csv:
        with open(args.csv, "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=["team", "llm_spend", "llm_budget", "infra_cost", "total"])
            w.writeheader()
            w.writerows(out)
        print(f"CSV: {args.csv}")


if __name__ == "__main__":
    main()
