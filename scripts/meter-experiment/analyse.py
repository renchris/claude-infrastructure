#!/usr/bin/env python3
"""Verdict for the meter-identification experiment.

Compares the OBSERVED Δweekly_pct on next2 against what each live hypothesis PREDICTS from
the actually-measured token counts of the experiment's own session.

  H_free  cache_read carries no weekly-limit weight (A1's NNLS shape, lead-calibrated)
            out 3.83 pp/Mtok · cc 0.314 pp/Mtok · cr 0.000
  H_list  the meter tracks API list price (A3/A6/A7's implicit model), normalised so that
          OUTPUT costs the same 3.83 pp/Mtok in both — so the two differ ONLY on cr and cc,
          which is exactly the contested part
            relative $/Mtok Opus-5: in 5 · out 25 · cache-write(1h TTL) 10 · cache-read 0.5
            NB the 1-hour write multiplier is x2 of input, NOT the x1.25 five artifacts used.

Token counts are deduped on message.id — a streamed assistant message is written to the
transcript once per content block, and summing lines inflates 2-3x.
"""

import json, os, glob, sys

SID = open("/tmp/meter-exp/arm-sid.txt").read().strip().lower()
ROOT = os.path.expanduser("~/.claude-secondary/projects")

files = [
    f
    for f in glob.glob(os.path.join(ROOT, "**", "*.jsonl"), recursive=True)
    if SID in os.path.basename(f).lower()
]
if not files:
    print("ABSTAIN — no transcript found for the arm session", SID)
    sys.exit(1)

seen, tot, turns = set(), {"in": 0, "out": 0, "cc": 0, "cr": 0}, 0
for f in files:
    for line in open(f, "rb"):
        if b'"usage"' not in line:
            continue
        try:
            d = json.loads(line)
        except Exception:
            continue
        m = d.get("message") or {}
        u = m.get("usage")
        if not isinstance(u, dict):
            continue
        mid = m.get("id")
        if mid in seen:
            continue
        seen.add(mid)
        turns += 1
        tot["in"] += int(u.get("input_tokens") or 0)
        tot["out"] += int(u.get("output_tokens") or 0)
        tot["cc"] += int(u.get("cache_creation_input_tokens") or 0)
        tot["cr"] += int(u.get("cache_read_input_tokens") or 0)

print("=" * 78)
print(f"ARM SESSION {SID}   ({turns} deduped billed responses)")
for k in ("in", "out", "cc", "cr"):
    print(f"  {k:3s} {tot[k]:>14,}")
print(f"  cr:out ratio = {tot['cr'] / max(tot['out'], 1):,.0f} : 1")


# ---- predictions -------------------------------------------------------------------
def pp_free(t):
    return (t["out"] * 3.83 + t["cc"] * 0.314 + t["in"] * 3.83) / 1e6


K = 3.83 / 25.0  # normalise so OUTPUT costs 3.83 pp/Mtok under list pricing too


def pp_list(t):
    return K * (t["out"] * 25 + t["cc"] * 10 + t["cr"] * 0.5 + t["in"] * 5) / 1e6


pf, pl = pp_free(tot), pp_list(tot)
print()
print("PREDICTED Δweekly_pct for the tokens actually spent:")
print(f"  H_free  (cache_read weightless)      {pf:6.2f} pp")
print(f"  H_list  (meter tracks list price)    {pl:6.2f} pp")
print(f"  separation = {pl - pf:.2f} pp   (the meter's quantum is 1 pp)")

# ---- observed ----------------------------------------------------------------------
obs = []
for ln in open("/tmp/meter-exp/log.tsv", errors="replace"):
    p = ln.rstrip("\n").split("\t")
    if len(p) >= 3 and p[0].startswith("20") and p[1] not in ("NA", ""):
        try:
            obs.append((p[0], int(p[1]), int(p[2])))
        except ValueError:
            pass
print()
if len(obs) < 2:
    print("ABSTAIN — fewer than 2 usable meter reads; cannot difference.")
    sys.exit(1)
print("METER (next2):")
for t, w, s in obs:
    print(f"  {t[:19]}  weekly={w:>3}  5h={s:>3}")
d_week = obs[-1][1] - obs[0][1]
d_5h = obs[-1][2] - obs[0][2]
print(f"\nOBSERVED Δweekly = {d_week} pp   (Δ5h = {d_5h} pp)")

# ---- verdict -----------------------------------------------------------------------
print()
mid = (pf + pl) / 2
if pl - pf < 1.0:
    print("NO VERDICT — the two hypotheses predict less than one meter-quantum apart.")
    print("             Scale the arm up (more resumed turns) and re-run.")
elif d_week >= mid:
    print("VERDICT: cache_read IS CHARGED.")
    print(
        f"  observed {d_week} pp sits at/above the midpoint {mid:.2f}, consistent with H_list."
    )
    print(
        "  => context length DOES cost weekly quota; trimming/recycling is a real cost lever,"
    )
    print(
        "     and the plan's 'shrinking context optimises the free class' must be retracted."
    )
else:
    print("VERDICT: cache_read is ~FREE against the weekly limit.")
    print(
        f"  observed {d_week} pp sits below the midpoint {mid:.2f}; H_list predicted {pl:.2f} and is refuted."
    )
    print(
        "  => re-reading cached context is not what the plan charges for. Quota buys OUTPUT and"
    )
    print(
        "     newly-cached tokens. Recycling stays justified by rot and the context ceiling only."
    )
print()
print(
    "CAVEAT: this measures the WEEKLY meter on ONE account over ONE run. The 5h column is"
)
print(
    "shown so a reader can see whether the two meters agree; they need not share a unit."
)
