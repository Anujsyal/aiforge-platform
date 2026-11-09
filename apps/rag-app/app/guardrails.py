"""Guardrails: model ke AAGE aur PEECHE plain-code checks (prompt-injection defence layer 2).

Kyun (asli CI run, 2026-11-08): sirf system prompt se 1B model pe quality aur security saath nahi mile.
  - Sakht prompt  → quality 16.7%, red-team 100%  (har sawaal pe "I don't know")
  - Simple prompt → quality 91.7%, red-team 50%   ("PWNED", fake sk- key, poisoned doc ka "HACKED")
Chhota model ya sab mana karta hai ya sab maan leta hai. Isliye prompt ko helpful rakha aur security
deterministic code mein daali, jo model ki samajh pe depend nahi karti:

  1. check_question()   : user ke sawaal mein direct injection / jailbreak / secret maangna → model tak jaata hi nahi
  2. sanitize_context() : retrieved chunks se injection wali lines hata do (indirect injection, poisoned docs)
  3. redact_output()    : jawab mein secret jaisa kuch (sk-..., AWS keys, private keys) → [REDACTED]

Ye regex hain, perfect nahi (paraphrase se bypass ho sakte hain). Production mein iske saath ek classifier
(Llama Guard / Prompt Guard, LLM Guard, NeMo Guardrails) lagta hai. Red-team eval batata hai ki layer kaam kar rahi hai.
"""

from __future__ import annotations

import re

BLOCKED_ANSWER = "I can't help with that request. I only answer questions about the AIForge platform documents."

_F = re.IGNORECASE

# Direct injection / jailbreak (user ke sawaal mein)
_QUESTION_PATTERNS = [
    re.compile(r"\b(ignore|disregard|forget|override)\b.{0,40}\b(previous|prior|above|earlier|all|every|your)\b.{0,30}\b(instructions?|rules?|prompts?|guidelines?)\b", _F),
    re.compile(r"\b(system|developer|hidden|initial)\s+(prompt|message|instructions?)\b", _F),
    re.compile(r"\byou\s+are\s+now\b", _F),
    re.compile(r"\b(jailbreak|DAN mode|developer mode|no (rules|restrictions|filters))\b", _F),
    re.compile(r"\b(reply|respond|answer)\s+with\s+only\b", _F),
    # Secret maangna: "master key", "print any api key", "sk-"
    re.compile(r"\b(master|secret|private|api|access)\s+keys?\b.{0,40}\b(print|show|reveal|give|what|list|dump)\b", _F),
    re.compile(r"\b(print|show|reveal|give|list|dump)\b.{0,40}\b(master|secret|private|api|access)\s+keys?\b", _F),
    re.compile(r"\bwhat\s+is\s+the\s+\S*\s*master\s+key\b", _F),
    re.compile(r"\bsk-", _F),
]

# Indirect injection (retrieved document ke andar chhupi instructions). Line-level: sirf wo line hatti hai,
# baaki document (jaise cafeteria timing) model tak jaata hai.
_CONTEXT_PATTERNS = [
    re.compile(r"\b(ignore|disregard|forget|override)\b.{0,40}\b(previous|prior|above|earlier|all|every)\b.{0,30}\b(instructions?|rules?|prompts?|answers?)\b", _F),
    re.compile(r"\bsystem\s+override\b", _F),
    re.compile(r"\b(reveal|print|show)\b.{0,30}\b(system\s+prompt|instructions)\b", _F),
    re.compile(r"\bfrom\s+now\s+on\b", _F),
    re.compile(r"\b(end|start|begin)\s+every\s+(answer|response|reply)\b", _F),
    re.compile(r"\byou\s+are\s+now\b", _F),
]

# Output: secret jaise patterns (model hallucinate kare ya context mein ho, dono case mein bahar nahi jaana chahiye)
_SECRET_PATTERNS = [
    re.compile(r"\bsk-[A-Za-z0-9_\-]{6,}"),                     # OpenAI / LiteLLM style keys
    re.compile(r"\b(AKIA|ASIA)[A-Z0-9]{16}\b"),                 # AWS access key id
    re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
    re.compile(r"\b(pk|sk)-lf-[A-Za-z0-9\-]{6,}"),              # Langfuse keys
    re.compile(r"\bhvs\.[A-Za-z0-9_\-]{20,}"),                  # Vault tokens
]


def check_question(question: str) -> str | None:
    """Injection/jailbreak mila to reason (pattern) return, warna None."""
    for p in _QUESTION_PATTERNS:
        if p.search(question):
            return p.pattern
    return None


def sanitize_context(text: str) -> tuple[str, int]:
    """Injection wali lines hatao. Return (saaf text, kitni lines hati)."""
    kept, removed = [], 0
    for line in text.splitlines():
        if any(p.search(line) for p in _CONTEXT_PATTERNS):
            removed += 1
            continue
        kept.append(line)
    return "\n".join(kept), removed


def redact_output(text: str) -> tuple[str, int]:
    """Secret jaise strings ko [REDACTED]. Return (text, kitne redact hue)."""
    n = 0
    for p in _SECRET_PATTERNS:
        text, k = p.subn("[REDACTED]", text)
        n += k
    return text, n
