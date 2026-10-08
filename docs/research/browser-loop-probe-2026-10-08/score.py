#!/usr/bin/env python3
"""Score one run: saved leads against expected.json, plus the loop's own counters.

Wrong fields: each expected lead is paired with the saved lead that matches it on the most fields
(one saved lead per card; the pairing maximizes total matches), and each of its 9 fields is compared;
a card with no saved lead counts all 9 as wrong. Pairing by best match, not by exact name, is
deliberate: the first measured run typed "Lena Voyt" for "Lena Vogt", and a name-keyed pairing scored
that one misread letter as a missing lead plus a stray save. Comparison is exact after trimming,
collapsing whitespace and folding case, with three named relaxations: phone compares digits only,
seats compares as an integer, and notes also fold dash and quote variants. Saves left unpaired
(duplicates, or a lead on no card) are counted as extra saves, never folded into wrong fields.

Usage: python3 -I score.py <saved.jsonl> <stream.jsonl> <wall_seconds>   → one JSON line on stdout
"""

import collections
import itertools
import json
import pathlib
import re
import sys

FIELDS = [
    "name",
    "company",
    "email",
    "phone",
    "role",
    "plan",
    "seats",
    "follow_up",
    "notes",
]
EXPECTED = json.loads(
    (pathlib.Path(__file__).resolve().parent / "expected.json").read_text()
)["leads"]


def norm(field, v):
    s = re.sub(r"\s+", " ", str(v)).strip().casefold()
    if field == "phone":
        return re.sub(r"\D", "", s)
    if field == "seats":
        try:
            return int(float(s))
        except ValueError:
            return s
    if field == "notes":
        return s.translate(
            str.maketrans({"–": "-", "—": "-", "’": "'", "“": '"', "”": '"'})
        )
    return s


def read_jsonl(path):
    p = pathlib.Path(path)
    if not p.exists():
        return []
    return [json.loads(line) for line in p.read_text().splitlines() if line.strip()]


def main(saved_path, stream_path, wall):
    saved = read_jsonl(saved_path)

    def hits(exp, got):
        return sum(norm(f, got.get(f, "")) == norm(f, exp[f]) for f in FIELDS)

    # Brute force over pairings: 3 cards and a handful of saves keep this tiny.
    best, best_score = (), -1
    slots = list(range(len(saved))) + [None] * len(EXPECTED)
    for perm in itertools.permutations(slots, len(EXPECTED)):
        score = sum(hits(e, saved[i]) for e, i in zip(EXPECTED, perm) if i is not None)
        if score > best_score:
            best, best_score = perm, score
    wrong, detail = 0, []
    for exp, i in zip(EXPECTED, best):
        got = None if i is None else saved[i]
        for f in FIELDS:
            if got is None or norm(f, got.get(f, "")) != norm(f, exp[f]):
                wrong += 1
                detail.append(
                    {
                        "lead": exp["name"],
                        "field": f,
                        "want": exp[f],
                        "got": None if got is None else got.get(f),
                    }
                )
    paired = sum(1 for i in best if i is not None)
    extra = len(saved) - paired

    tools, init, result = collections.Counter(), {}, {}
    for ev in read_jsonl(stream_path):
        if ev.get("type") == "system" and ev.get("subtype") == "init":
            init = ev
        elif ev.get("type") == "assistant":
            for block in ev.get("message", {}).get("content", []):
                if block.get("type") == "tool_use":
                    tools[block.get("name")] += 1
        elif ev.get("type") == "result":
            result = ev
    usage = result.get("usage", {})
    print(
        json.dumps(
            {
                "model": init.get("model"),
                "cli": init.get("claude_code_version"),
                "saved": len(saved),
                "leads_paired": paired,
                "wrong_fields": wrong,
                "extra_saves": extra,
                "tool_calls": sum(tools.values()),
                "tools": dict(tools),
                "wall_s": round(float(wall), 1),
                "api_s": round(result.get("duration_api_ms", 0) / 1000, 1),
                "turns": result.get("num_turns"),
                "is_error": result.get("is_error"),
                "subtype": result.get("subtype"),
                "input_tokens": usage.get("input_tokens"),
                "cache_read": usage.get("cache_read_input_tokens"),
                "cache_creation": usage.get("cache_creation_input_tokens"),
                "output_tokens": usage.get("output_tokens"),
                "notional_usd": result.get("total_cost_usd"),
                "wrong_detail": detail,
            }
        )
    )


if __name__ == "__main__":
    main(*sys.argv[1:4])
