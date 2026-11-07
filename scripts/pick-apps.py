"""Multi-document YAML file se sirf chuni hui Argo CD Applications nikaalo (phase-by-phase apply ke liye).

Usage (Git Bash):
  python scripts/pick-apps.py gitops/platform/10-core.yaml vault kyverno | kubectl apply -f -
  python scripts/pick-apps.py gitops/platform/10-core.yaml --list
"""

import sys

import yaml


def main() -> None:
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    path, names = sys.argv[1], sys.argv[2:]
    docs = [d for d in yaml.safe_load_all(open(path, encoding="utf-8")) if d]
    if names == ["--list"]:
        for d in docs:
            print(d["kind"], d["metadata"]["name"])
        return
    picked = [d for d in docs if d["metadata"]["name"] in names]
    missing = set(names) - {d["metadata"]["name"] for d in picked}
    if missing:
        sys.exit(f"not found in {path}: {', '.join(sorted(missing))}")
    sys.stdout.write(yaml.safe_dump_all(picked, sort_keys=False))


if __name__ == "__main__":
    main()
