#!/usr/bin/env python3
"""
Pre-flight cost estimator for the outlook-cleanup classify phase.

Computes both API-key-direct cost (cheap, ~$6 for 36K) and Sonnet-subagent cost
(expensive, ~$17 for 36K — uses claude.ai usage credits, not API balance).

Usage:
    python3 cost.py --data-dir PATH [--avg-msg-chars N]

Output: JSON with both cost paths' breakdowns.
"""

from __future__ import annotations

import argparse
import json
import sys
from math import ceil
from pathlib import Path

DEFAULT_DATA_DIR = Path("/Users/chrisren/Development/personal/outlook-cleanup")

# Pricing per million tokens (Anthropic API direct, as of 2026-05)
PRICING = {
    "haiku-4-5": {
        "input": 0.80,
        "cache_read": 0.08,
        "cache_write": 1.00,
        "output": 4.00,
    },
    "sonnet-4-6": {
        "input": 3.00,
        "cache_read": 0.30,
        "cache_write": 3.75,
        "output": 15.00,
    },
}

# Empirical constants from 2026-05-21 run
CLASSIFY_BATCH_SIZE = 25  # pipeline.py classify subcommand batch
CACHED_PREFIX_TOKENS = 2400  # system prompt + few-shot examples
VERDICT_OUTPUT_TOKENS = 20  # per message JSON verdict
SUBAGENT_BRIEF_TOKENS = 50_000  # CLAUDE.md preamble + tool defs + brief
SUBAGENT_SHARD_SIZE = 500  # hard cap (Sonnet output ≈ 32K tokens)
SUBAGENT_WAVE_SIZE = 10
SUBAGENT_PARALLEL_WALL_SEC = 180  # ~3 min per wave empirical
GRAPH_BATCH_SIZE = 4
GRAPH_SEC_PER_BATCH = 0.83
DETERMINISTIC_BYPASS_RATE = (
    0.20  # ~20% caught by pre-filter (keep-list + transactional)
)


def _line_count(p: Path) -> int:
    if not p.exists():
        return 0
    with p.open("rb") as f:
        return sum(1 for _ in f)


def _avg_msg_size(messages_jsonl: Path, sample: int = 500) -> int:
    if not messages_jsonl.exists():
        return 389  # empirical default
    total = 0
    count = 0
    with messages_jsonl.open() as f:
        for i, line in enumerate(f):
            if i >= sample:
                break
            total += len(line)
            count += 1
    return total // count if count else 389


def estimate_api_direct(
    n_messages: int, avg_chars: int, model: str = "haiku-4-5"
) -> dict:
    """Cost of running pipeline.py classify directly with API key."""
    p = PRICING[model]
    n_batches = ceil(n_messages / CLASSIFY_BATCH_SIZE)
    per_msg_tokens = avg_chars / 4
    per_batch_content = per_msg_tokens * CLASSIFY_BATCH_SIZE
    per_batch_output = VERDICT_OUTPUT_TOKENS * CLASSIFY_BATCH_SIZE

    # Cache: first batch cache-write, rest cache-read for the prefix
    cache_write_cost = (CACHED_PREFIX_TOKENS * p["cache_write"]) / 1_000_000
    cache_read_cost = (
        CACHED_PREFIX_TOKENS * (n_batches - 1) * p["cache_read"]
    ) / 1_000_000
    content_cost = (per_batch_content * n_batches * p["input"]) / 1_000_000
    output_cost = (per_batch_output * n_batches * p["output"]) / 1_000_000

    total_usd = cache_write_cost + cache_read_cost + content_cost + output_cost
    wall_sec = n_batches * 2.0  # ~2 sec per Haiku batch sequential

    return {
        "model": model,
        "credit_source": "console.anthropic.com API balance",
        "n_batches": n_batches,
        "components_usd": {
            "cache_write": round(cache_write_cost, 4),
            "cache_read": round(cache_read_cost, 4),
            "content_input": round(content_cost, 4),
            "output": round(output_cost, 4),
        },
        "total_usd": round(total_usd, 2),
        "wall_minutes": round(wall_sec / 60, 1),
    }


def estimate_subagent_sonnet(n_messages: int, avg_chars: int) -> dict:
    """Cost of spawning Sonnet subagents in parallel waves."""
    p = PRICING["sonnet-4-6"]
    llm_eligible = int(n_messages * (1 - DETERMINISTIC_BYPASS_RATE))
    n_shards = ceil(llm_eligible / SUBAGENT_SHARD_SIZE)
    n_waves = ceil(n_shards / SUBAGENT_WAVE_SIZE)

    per_shard_input_content = (avg_chars / 4) * SUBAGENT_SHARD_SIZE
    per_shard_input_preamble = SUBAGENT_BRIEF_TOKENS  # uncached per spawn
    per_shard_output = VERDICT_OUTPUT_TOKENS * SUBAGENT_SHARD_SIZE

    preamble_cost = (per_shard_input_preamble * n_shards * p["input"]) / 1_000_000
    content_cost = (per_shard_input_content * n_shards * p["input"]) / 1_000_000
    output_cost = (per_shard_output * n_shards * p["output"]) / 1_000_000

    total_usd = preamble_cost + content_cost + output_cost
    wall_sec = n_waves * SUBAGENT_PARALLEL_WALL_SEC

    return {
        "model": "sonnet-4-6",
        "credit_source": "claude.ai usage credits (NOT console API balance)",
        "n_eligible_after_deterministic": llm_eligible,
        "n_shards": n_shards,
        "n_waves": n_waves,
        "components_usd": {
            "subagent_preamble": round(preamble_cost, 2),
            "content_input": round(content_cost, 2),
            "output": round(output_cost, 2),
        },
        "total_usd": round(total_usd, 2),
        "wall_minutes": round(wall_sec / 60, 1),
    }


def estimate_quarantine_purge(delete_rate: float, n_messages: int) -> dict:
    n_moves = int(n_messages * delete_rate)
    n_batches = ceil(n_moves / GRAPH_BATCH_SIZE)
    wall_min = n_batches * GRAPH_SEC_PER_BATCH / 60
    return {
        "estimated_moves": n_moves,
        "graph_batches": n_batches,
        "quarantine_wall_minutes": round(wall_min, 1),
        "purge_wall_minutes": round(wall_min, 1),  # same mechanism
        "outlook_api_cost_usd": 0.0,  # Graph has no per-call billing
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--data-dir", type=Path, default=DEFAULT_DATA_DIR)
    ap.add_argument("--avg-msg-chars", type=int, default=None)
    ap.add_argument(
        "--delete-rate",
        type=float,
        default=0.08,
        help="Empirical default: 8%% DELETE rate",
    )
    ns = ap.parse_args()

    data_dir = ns.data_dir.expanduser().resolve()
    messages = data_dir / "messages.jsonl"
    classifications = data_dir / "classifications.jsonl"

    n_inbox = _line_count(messages)
    n_classified = _line_count(classifications)
    n_remaining = max(0, n_inbox - n_classified)

    avg = ns.avg_msg_chars or _avg_msg_size(messages)

    out = {
        "data_dir": str(data_dir),
        "inbox_size": n_inbox,
        "already_classified": n_classified,
        "remaining_to_classify": n_remaining,
        "avg_msg_chars": avg,
        "paths": {
            "A_api_direct_haiku": estimate_api_direct(n_remaining, avg, "haiku-4-5"),
            "B_subagent_sonnet": estimate_subagent_sonnet(n_remaining, avg),
        },
        "downstream": estimate_quarantine_purge(ns.delete_rate, n_remaining or n_inbox),
        "note": "Path B costs claude.ai usage credits (chat product) "
        "and is ~3-5x Path A. Path A requires ANTHROPIC_API_KEY env var.",
    }
    print(json.dumps(out, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
