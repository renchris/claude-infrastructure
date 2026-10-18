#!/usr/bin/env python3
"""A6-harness census: SessionStart harness mechanics measured from main transcripts.

Read-only. Usage: python3 -I a6_census.py /tmp/startup-hooks-census-files.txt
Reports:
  1. hook_cancelled on SessionStart: count per command, overshoot (durationMs - timeoutMs)
  2. parallelism: per SessionStart batch (toolUseID), spread of inferred start times
  3. async_hook_response on SessionStart: how many carry stderr / non-empty response
  4. first-turn wait: sessions whose first prompt was enqueued before the last sync
     SessionStart hook finished, and by how much the hooks delayed it
  5. hook_non_blocking_error / hook_system_message / hook_additional_context per source
"""

import json, sys, collections, statistics
from datetime import datetime


def ts(s):
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except Exception:
        return None


def pct(xs, p):
    if not xs:
        return None
    xs = sorted(xs)
    k = max(0, min(len(xs) - 1, int(round(p / 100 * (len(xs) - 1)))))
    return xs[k]


files = [l.strip() for l in open(sys.argv[1]) if l.strip()]
cancel = collections.defaultdict(list)  # cmd -> overshoot ms
cancel_by_source = collections.Counter()
batches = collections.defaultdict(list)  # (file, toolUseID) -> [(start, end, cmd)]
async_ss = collections.Counter()
async_stderr_examples = collections.Counter()
types_by_source = collections.Counter()
ctx_len_by_source = collections.defaultdict(list)
sysmsg_len = []
first_wait = []  # ms the first prompt waited on SessionStart hooks
first_wait_n_sessions = 0
nbe_examples = collections.Counter()

for f in files:
    try:
        fh = open(f, errors="replace")
    except OSError:
        continue
    ss_end = None  # last end time of the startup SessionStart batch
    first_enqueue = None
    first_user = None
    seen_startup = False
    with fh:
        for line in fh:
            if (
                '"attachment"' not in line
                and '"queue-operation"' not in line
                and '"user"' not in line
            ):
                continue
            try:
                r = json.loads(line)
            except Exception:
                continue
            t = ts(r.get("timestamp") or "")
            if (
                r.get("type") == "queue-operation"
                and first_enqueue is None
                and r.get("operation") == "enqueue"
            ):
                first_enqueue = t
            if (
                r.get("type") == "user"
                and not r.get("isMeta")
                and first_user is None
                and isinstance(r.get("message", {}).get("content"), str)
            ):
                first_user = t
            a = r.get("attachment")
            if not isinstance(a, dict):
                continue
            hn = a.get("hookName") or ""
            if not hn.startswith("SessionStart"):
                continue
            src = hn.split(":", 1)[1] if ":" in hn else "?"
            at = a.get("type")
            types_by_source[(src, at)] += 1
            cmd = (a.get("command") or "").split("/")[-1]
            if at == "hook_cancelled":
                cancel_by_source[src] += 1
                if (
                    a.get("timedOut")
                    and a.get("durationMs") is not None
                    and a.get("timeoutMs")
                ):
                    cancel[cmd].append(a["durationMs"] - a["timeoutMs"])
                else:
                    cancel[cmd + " (not timedOut)"].append(0)
            if (
                at in ("hook_cancelled", "hook_success", "hook_non_blocking_error")
                and a.get("durationMs") is not None
                and t
            ):
                batches[(f, a.get("toolUseID"))].append(
                    (t - a["durationMs"] / 1000.0, t, cmd)
                )
                if src == "startup" and not seen_startup:
                    pass
                if src == "startup":
                    ss_end = max(ss_end or 0, t)
            if at == "hook_non_blocking_error":
                nbe_examples[(cmd, (a.get("stderr") or "")[:90])] += 1
            if at == "hook_additional_context":
                c = a.get("content")
                n = sum(len(x) for x in c) if isinstance(c, list) else len(str(c or ""))
                ctx_len_by_source[src].append(n)
            if at == "hook_system_message":
                sysmsg_len.append(len(str(a.get("content") or "")))
            if at == "async_hook_response":
                se = (a.get("stderr") or "").strip()
                resp = a.get("response") or {}
                async_ss["total"] += 1
                if se:
                    async_ss["with_stderr"] += 1
                    async_stderr_examples[se.splitlines()[0][:110]] += 1
                if resp:
                    async_ss["with_nonempty_response"] += 1
                if a.get("exitCode") not in (0, None):
                    async_ss["nonzero_exit"] += 1
    if ss_end and first_enqueue and first_enqueue < ss_end:
        first_wait_n_sessions += 1
        first_wait.append((ss_end - first_enqueue) * 1000)

print("== 1. SessionStart hook_cancelled, per command: n, overshoot ms p50/p90/max")
for cmd, xs in sorted(cancel.items(), key=lambda kv: -len(kv[1])):
    print(
        f"  {cmd:45s} n={len(xs):4d} p50={pct(xs, 50)} p90={pct(xs, 90)} max={max(xs)}"
    )
print("  by source:", dict(cancel_by_source))

print(
    "== 2. parallelism: per batch with >=2 timed records, spread of inferred start (ms)"
)
spreads = []
for k, v in batches.items():
    if len(v) >= 2:
        starts = [s for s, _, _ in v]
        spreads.append((max(starts) - min(starts)) * 1000)
print(
    f"  batches={len(spreads)} spread p50={pct(spreads, 50):.0f} p90={pct(spreads, 90):.0f} max={max(spreads):.0f}"
    if spreads
    else "  none"
)

print("== 3. async_hook_response on SessionStart:", dict(async_ss))
for k, n in async_stderr_examples.most_common(8):
    print(f"  {n:4d}  {k}")

print("== 4. first prompt enqueued before startup SessionStart hooks finished")
print(
    f"  sessions={first_wait_n_sessions} wait ms p50={pct(first_wait, 50)} p90={pct(first_wait, 90)} max={max(first_wait) if first_wait else None}"
)

print("== 5. SessionStart attachment types by source")
for (src, at), n in sorted(types_by_source.items()):
    print(f"  {src:8s} {at:28s} {n}")
for src, xs in ctx_len_by_source.items():
    print(
        f"  additionalContext chars [{src}] n={len(xs)} mean={statistics.mean(xs):.0f} p50={pct(xs, 50)} max={max(xs)}"
    )
if sysmsg_len:
    print(
        f"  systemMessage chars n={len(sysmsg_len)} mean={statistics.mean(sysmsg_len):.0f} max={max(sysmsg_len)}"
    )
print("  hook_non_blocking_error examples:")
for (cmd, se), n in nbe_examples.most_common(8):
    print(f"  {n:4d} {cmd} :: {se}")
