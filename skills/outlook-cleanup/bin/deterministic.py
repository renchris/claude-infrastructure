#!/usr/bin/env python3
"""
Extended deterministic pre-classification filter.

Runs before any LLM call. For each message in messages.jsonl not yet in
classifications.jsonl, attempts to classify via deterministic content rules.
Appends only confident matches; leaves ambiguous messages for the LLM.

Output: appends to <data-dir>/classifications.jsonl with source="deterministic"
or source="keep-list".

Empirical effect: ~20% of an inbox is classified deterministically, saving
that much of the LLM cost.

Usage:
    python3 deterministic.py --data-dir PATH [--apply]

Without --apply, reports only the would-be counts. With --apply, writes.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter
from pathlib import Path

DEFAULT_DATA_DIR = Path("/Users/chrisren/Development/personal/outlook-cleanup")

# User keep-list (always KEEP regardless of content)
KEEP_LIST_DOMAINS = {
    "factorytown.com",
    "email.factorytown.com",
    "canadianprotein.com",
    "send.canadianprotein.com",
    "justthrivehealth.com",
}

# High-confidence KEEP signals — transactional, financial, security
KEEP_TRANSACTIONAL = re.compile(
    r"\b(order\s*#|receipt|shipped|tracking\s*#|RMA|"
    r"refund\s+(processed|issued|of)|invoice|"
    r"appointment\s+confirm|reservation\s+confirm|booking\s+confirm)\b",
    re.I,
)

KEEP_AUTH = re.compile(
    r"\b(verification\s+code|one.?time\s+(code|password)|"
    r"\bOTP\b|\bMFA\b|\b2FA\b|two.factor|"
    r"password\s+reset|security\s+alert|"
    r"new\s+sign.?in|signed?\s+in\s+from|new\s+device)\b",
    re.I,
)

KEEP_FINANCIAL_DOC = re.compile(
    r"\b(T[45]|statement\s+(is\s+)?ready|tax\s+(document|form|slip|summary)|"
    r"year.?end\s+summary|account\s+statement)\b.*\b(20\d{2})\b|"
    r"\b(20\d{2})\b.*\b(statement|tax)\b",
    re.I,
)

# High-confidence DELETE signals — pure marketing blasts
DELETE_BLAST_SUBJECT = re.compile(
    r"^\s*(\d+%\s*off|save\s+\d+%|free\s+shipping\s+ends|"
    r"last\s+chance|\d+\s+days?\s+(only|left)|"
    r"flash\s+sale|exclusive\s+\d+%|extra\s+\d+%)",
    re.I,
)

DELETE_BLAST_BODY_OPENS = re.compile(
    r"^\s*(SHOP\s+NOW|SALE\s+ENDS|We\s+miss\s+you|Don'?t\s+miss|"
    r"Hurry,?\s+|\d+%\s+off\s+sitewide|Limited\s+time)",
    re.I,
)

# Outlook's pre-computed focus signal — focused = KEEP heuristic
FOCUSED = "focused"


def _domain(addr: str) -> str:
    return addr.split("@")[-1].lower() if "@" in addr else ""


def classify_message(msg: dict) -> tuple[str | None, str | None, str]:
    """
    Returns (verdict, source, rationale).

    Returns (None, None, "") if no deterministic rule matches; message goes
    to LLM.
    """
    addr = (msg.get("from", {}).get("emailAddress", {}).get("address") or "").lower()
    domain = _domain(addr)
    subj = msg.get("subject", "") or ""
    body = (msg.get("bodyPreview", "") or "")[:300]
    haystack = f"{subj}\n{body}"

    # Tier 1: Keep-list senders (highest priority)
    if domain in KEEP_LIST_DOMAINS:
        return "KEEP", "keep-list", f"keep-list domain ({domain})"

    # Tier 2: Auth/security (irreversible if deleted)
    m = KEEP_AUTH.search(haystack)
    if m:
        return "KEEP", "deterministic", f"auth-security keyword '{m.group(0)[:30]}'"

    # Tier 3: Transactional records
    m = KEEP_TRANSACTIONAL.search(haystack)
    if m:
        return "KEEP", "deterministic", f"transactional keyword '{m.group(0)[:30]}'"

    # Tier 4: Financial documents
    m = KEEP_FINANCIAL_DOC.search(haystack)
    if m:
        return "KEEP", "deterministic", f"financial document '{m.group(0)[:30]}'"

    # Tier 5: Focused inbox heuristic (low confidence, but Outlook's ML)
    # Only use as KEEP when no DELETE signal also fires
    is_focused = msg.get("inferenceClassification") == FOCUSED
    has_delete_signal = DELETE_BLAST_SUBJECT.search(
        subj
    ) or DELETE_BLAST_BODY_OPENS.search(body)

    if has_delete_signal:
        # High-confidence DELETE — pure blast
        ev = DELETE_BLAST_SUBJECT.search(subj) or DELETE_BLAST_BODY_OPENS.search(body)
        return "DELETE", "deterministic", f"blast pattern '{ev.group(0)[:30]}'"

    if is_focused:
        # Conservative: don't auto-KEEP just on focused signal; send to LLM
        # for content review. Focused is informative but not authoritative.
        return None, None, ""

    return None, None, ""


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--data-dir", type=Path, default=DEFAULT_DATA_DIR)
    ap.add_argument(
        "--apply",
        action="store_true",
        help="Write to classifications.jsonl (default is dry-run)",
    )
    ns = ap.parse_args()

    data_dir = ns.data_dir.expanduser().resolve()
    messages_f = data_dir / "messages.jsonl"
    classifications_f = data_dir / "classifications.jsonl"

    if not messages_f.exists():
        print(
            json.dumps({"error": f"messages.jsonl not found at {messages_f}"}),
            file=sys.stderr,
        )
        return 1

    # Build already-classified id set
    classified_ids: set[str] = set()
    if classifications_f.exists():
        with classifications_f.open() as f:
            for line in f:
                try:
                    classified_ids.add(json.loads(line)["messageId"])
                except (json.JSONDecodeError, KeyError):
                    pass

    new_classifications = []
    counts: Counter = Counter()
    examined = 0

    with messages_f.open() as f:
        for line in f:
            try:
                msg = json.loads(line)
            except json.JSONDecodeError:
                continue
            examined += 1
            if msg["id"] in classified_ids:
                continue

            verdict, source, rationale = classify_message(msg)
            if verdict is None:
                counts["llm_eligible"] += 1
                continue

            counts[f"{verdict}/{source}"] += 1
            counts[verdict] += 1
            evidence = (msg.get("subject") or msg.get("bodyPreview") or "")[:80]
            new_classifications.append(
                {
                    "messageId": msg["id"],
                    "evidence_quote": evidence,
                    "rationale": rationale,
                    "verdict": verdict,
                    "source": source,
                }
            )

    out = {
        "data_dir": str(data_dir),
        "examined": examined,
        "already_classified": len(classified_ids),
        "deterministic_matches": len(new_classifications),
        "llm_eligible": counts.get("llm_eligible", 0),
        "breakdown": dict(counts),
        "applied": False,
    }

    if ns.apply and new_classifications:
        with classifications_f.open("a") as f:
            for c in new_classifications:
                f.write(json.dumps(c) + "\n")
        out["applied"] = True
        out["appended_to"] = str(classifications_f)

    print(json.dumps(out, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
