#!/usr/bin/env python3
"""Score one run: saved leads against expected.json, plus the loop's own counters.

Wrong fields: each of the 9 fields of each expected lead is compared with the saved lead whose name
matches (first save wins; a missing lead counts all 9 as wrong). Comparison is exact after trimming,
collapsing whitespace and folding case, with three named relaxations: phone compares digits only,
seats compares as an integer, and notes also fold dash and quote variants. Extra saves (duplicates,
or names on no card) are counted separately, never folded into the wrong-field count.

Usage: python3 -I score.py <saved.jsonl> <stream.jsonl> <wall_seconds>   → one JSON line on stdout
"""

import collections
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
    by_name = {}
    for lead in saved:
        by_name.setdefault(norm("name", lead.get("name", "")), lead)
    wrong, detail = 0, []
    for exp in EXPECTED:
        got = by_name.get(norm("name", exp["name"]))
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
    expected_names = {norm("name", e["name"]) for e in EXPECTED}
    counts = collections.Counter(norm("name", s.get("name", "")) for s in saved)
    extra = sum(c - 1 for c in counts.values()) + sum(
        c for n, c in counts.items() if n not in expected_names
    )

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
                "leads_found": sum(
                    1 for e in EXPECTED if norm("name", e["name"]) in by_name
                ),
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
