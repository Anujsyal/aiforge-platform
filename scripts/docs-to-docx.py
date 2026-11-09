"""Saare Markdown docs ki Word (.docx) copy banao → docs/word/.

Usage:  pip install pypandoc_binary   (ek baar; pandoc saath aata hai)
        python scripts/docs-to-docx.py
Jab bhi koi .md doc badle, ye dobara chala (copies overwrite hoti hain).
"""

import re
from pathlib import Path

import pypandoc

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "docs" / "word"
DOCS = [
    ROOT / "README.md",
    ROOT / "MANUAL-SETUP-GUIDE.md",
    ROOT / "docs" / "PROJECT-EXPLAINED.md",
    ROOT / "docs" / "BUILD-JOURNEY.md",
]


def fix_tables(text: str) -> str:
    """GitHub table ke upar khaali line na ho to bhi dikhata hai; pandoc nahi (asli: 14 mein se 8 tables gayab).
    Table ki pehli line se pehle khaali line daalo (code blocks ke andar kuch nahi chhedte)."""
    out, in_code, prev = [], False, ""
    for line in text.splitlines():
        if line.lstrip().startswith("```"):
            in_code = not in_code
        is_row = not in_code and re.match(r"^\s*\|.*\|\s*$", line)
        prev_is_row = re.match(r"^\s*\|.*\|\s*$", prev or "")
        if is_row and prev.strip() and not prev_is_row:
            out.append("")
        out.append(line)
        prev = line
    return "\n".join(out) + "\n"


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for md in DOCS:
        target = OUT / (md.stem + ".docx")
        pypandoc.convert_text(
            fix_tables(md.read_text(encoding="utf-8")),
            "docx",
            format="gfm",  # GitHub markdown: tables, code blocks
            outputfile=str(target),
            extra_args=["--toc", "--toc-depth=2", f"--resource-path={md.parent}"],
        )
        print(f"  {md.relative_to(ROOT)} -> {target.relative_to(ROOT)} ({target.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
