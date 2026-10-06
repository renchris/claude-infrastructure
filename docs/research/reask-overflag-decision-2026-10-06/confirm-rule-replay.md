# E1h research slot: offline replay of precision join rules (no new calls)

Date 2026-10-06. Worker, read-only. No classifier call was made, no sealed set or key was opened,
`tuning-v2.jsonl` was not read, no miner prompt was printed, and no tracked file was edited.
`tuning.jsonl` was read for its `stratum` field only, as `union-sim.py` reads it.
Deviation from the brief: I did not run `git pull` (a git mutation, outside this worker's rules).
The worktree HEAD is `ff3e87fb7`, which already holds wave E1g's record, so every input named in the
brief was there.

## Inputs and what they can show

- **Tuning replay:** `docs/research/router-classifier-e1c-2026-10-04/tune-2reps.json`, with arm
  `off-e1b` as the fast call and `on-pre` as the careful call. That pairing is today's router
  configuration. The data is 96 rows x 2 reps. All arms were started at the same instant as
  cold calls, at load 28-46, and every call ran to completion, so both labels are known for every
  row and rep. Gold is the two rater files' agreed labels: 69 agreed rows, 13 borderline rows.
  The metrics use `e1c-choose.py`'s and `union-sim.py`'s definitions:
  - recall is measured on agreed relay-gold rows outside stratum `other`.
  - `other` counts every call on agreed rows in stratum `other`, and a fallback counts as wrong.
  - borderline is the number of relays on the 26 borderline calls.
  - fallback is the number of calls with no usable label.
  - I added `other relays` (relays on agreed `other`-stratum rows) and `false relays` (relays on
    agreed rows whose agreed label is not a relay label, in any stratum).
- **Limits:** the fast label is usable if it arrived within 9.0 s. The careful label is usable only
  within 8.5 s, the router's `DELIVER_MARGIN_S` hand-back. When the careful call is held to 9.0 s,
  rule (a) reproduces `union-sim.py`'s 52/52, 43/44, 19/26, 1/192 exactly (see the reconciliation
  line).
- **Walls:** they are E1c's cold walls. The resident path is faster for both calls, so the `wall`
  columns below are estimates of relative cost only (method: per call, the time at which the rule
  can decide, computed from the two cold walls). They do not forecast live latency.
- **v3, router side only:** `reading-v3-2026-10-05.jsonl` (stratum, counted, label, wall) and
  `.paths.jsonl` (the answering call), matched line by line: 450 rows, all 450 labels equal, `t`
  increasing. Because of the join in `router.py` `classify`, each reason string means one thing:
  - `fast call, resident` with a relay label: the fast call relayed and the careful call was
    stopped. Its label is unknown.
  - `fast call, resident` with a non-relay label: the careful call answered a non-relay label
    within 8.5 s. That label is unknown, and the wall is about max(fast, careful).
  - `...; the careful call: had not answered`: the fast label was handed back at 8.5 s.
  - `careful call, resident`: the careful call relayed. The fast label is unknown, and either it
    was not a relay or it had not arrived yet.

## Part 1: rules replayed on tuning v1 (measured: the script below, run 2026-10-06)

| rule | relay recall | `other` (all calls) | borderline relays | fallback | `other` relays | false relays | est. wall med / p90 (cold) |
|---|---|---|---|---|---|---|---|
| (a) current union | 52/52 | 43/44 | 19/26 | 1/192 | 3 | 7/84 | 4.91 / 8.50 |
| (b) careful-confirms | 52/52 | 43/44 | 19/26 | 1/192 | 3 | 6/84 | 5.66 / 8.50 |
| (b') confirms, and a careful-only relay does not stand (interpretation variant) | 51/52 | 44/44 | 10/26 | 1/192 | 2 | 2/84 | 2.20 / 6.54 |
| (c) careful-authoritative | 52/52 | 43/44 | 19/26 | 1/192 | 3 | 6/84 | 5.66 / 8.50 |
| (d) intersection, strict (a lone relay with nothing to confirm it = fallback) | 50/52 | 44/44 | 9/26 | 9/192 | 2 | 1/84 | 2.14 / 5.66 |
| (e) fast only | 51/52 | 44/44 | 10/26 | 1/192 | 2 | 3/84 | 1.70 / 2.31 |
| (f) careful only (8.5 s) | 51/52 | 34/44 | 18/26 | 41/192 | 3 | 5/84 | 5.21 / 7.36 |

How I defined each rule:
- **(b):** when the fast call relays and the careful call answered within 8.5 s, the result is
  the fast relay if the careful call also relayed, and the careful call's label if it did not.
  When the careful call did not answer, the fast relay stands. Everything else is as in (a), so a
  careful-only relay still relays.
- **(b'):** the stricter reading of the brief's wording, which also equals intersection with
  "silent careful = confirm".
- **(d), strict:** a fast non-relay gives the fast label. A careful non-relay gives the careful
  label. A relay from one call while the other is silent has no non-relay label to fall back on,
  so it falls back.
- In `other relays`, 2 of each arm's relays are correct: one agreed `other`-stratum row has an
  agreed relay label (2 calls).

What the tuning replay can and cannot tell:
- **On v1 the fast call never over-flags `other`.** Its relays on agreed `other`-stratum rows are
  the 2 correct ones. Across all agreed non-relay rows it made 3 wrong relays in 192 calls, all in
  the completeness strata. In those 3 calls the careful call said relay once, non-relay once
  (within 8.5 s), and nothing within 8.5 s once. So **a veto rule has 1 call on tuning v1 to act
  on**, and (b) differs from (a) by exactly that call (false relays 7 to 6, `other` unchanged).
  The failure that v3 measured, fast relays on ordinary prompts, does not occur in this data, so
  tuning v1 cannot rank (a) to (d) on it.
- **Careful-only relays are the borderline sensitivity.** Of the borderline calls, 9 were relayed
  by the careful call alone (fast non-relay). Every 9 the fast call relayed, the careful call
  confirmed, and 1 more had a silent careful call. So (b) and (c) keep 19/26. Any rule that drops
  careful-only relays (b', d, e) falls to 9-10/26, below E1g's own bar of 17.
- The 4 wrong careful-only relays on agreed non-relay rows are 3 regex-missed `other`, 1 `other`
  `other`. They are what (b'), (d) and (e) remove. (b) and (c) keep them.
- **(c) equals (b) on these numbers.** Its risk is not visible on tuning: (c) gives the careful
  label on every call where the careful call answers, and the careful call's `other` labeling is
  the configuration that read 0.88 and 0.72 on v2.
- **(f) fails fallback on tuning:** 41/192 = 0.21 at 8.5 s.
- **Latency cost (estimated, cold walls):** (b) and (c) make a fast relay wait for the careful call,
  which moves the median decision from 4.9 to 5.7 s. On the resident path this matters more:
  fast relays land at 0.54 s median on v3 (below), and under (b) every true re-ask would instead
  wait for the careful call (careful answers on v3: median about 5.6 s).

## Part 2: v3 router side (measured: same script; labels, walls and reasons only, no prompt or gold)

Answering call per stratum (counted unless marked):

| stratum | fast relay | careful relay | fast non-relay, careful answered non-relay within 8.5 s | fast non-relay, careful not answered by 8.5 s |
|---|---|---|---|---|
| regex-matched (114) | 51 | 7 | 35 | 21 |
| regex-missed (180) | 43 | 7 | 96 | 34 |
| pushback (4) | 2 | 0 | 1 | 1 |
| other (148) | **26** | **10** | 88 | 24 |
| uncounted (4) | 4 | 0 | 0 | 0 |
| total 450 | 126 | 24 | 220 | 80 |

- **Relays came 126 from the fast call and 24 from the careful call.** On counted `other`, the
  fast call gave 21 completeness and 5 pushback, and the careful call gave 7 completeness and 3
  pushback.
- **Careful relay walls (router clock):**
  - all 24: min 3.06, p25 4.57, median 5.62, p75 6.76, p90 7.58, max 8.47 s.
  - the 10 on `other`: 3.06, 3.99, 4.02, 4.12, 5.54, 5.55, 6.08, 6.27, 6.66, 7.14 s (median 5.54).
- **Fast relay walls:** all 126: median 0.54 s, p90 0.83 s, max 6.96 s. Only 3 are above 1.5 s
  (1.57, 1.66, 6.96). On `other`: median 0.51 s, max 6.96 s. No careful relay arrived before the
  fast-relay p90.
- **How often the careful call answers by 8.5 s:** on calls the fast call did not relay, 244/324 =
  0.75 overall and 98/122 = 0.80 on counted `other`. This is the only measure of it on v3.
  Fast-relayed calls stop the careful call, so they give no information on it.
- **Fast non-relay labels with the careful call answered** (wall about the later of the two): n=220,
  median 5.68 s, p90 7.52 s.

## What each rule would have done to the 36 relays on v3 `other`

Mostly unknowable, because only the answering call is recorded:
- For the **26 fast relays**, the careful call was stopped at about 0.5 s, so its label is unknown.
- For the **10 careful relays**, the fast label is unknown. The timing suggests the fast call had
  already answered non-relay: fast relays land at 0.5 s median and only 1 of 126 after 3.06 s.
  That is an estimate, not a record.
- I do not infer gold. The published totals (36 relays, 35 misses) show the relays and the misses
  are not identical sets, and this data does not say which relay was right.

- **(a) union:** 36, as read (113/148 = 0.76).
- **(b) careful-confirms:**
  - The 10 careful relays stand.
  - Of the 26 fast relays, a veto needs the careful call to have answered within 8.5 s and said
    non-relay. If it answered at the rate seen on other `other` calls (0.80, an estimate that
    assumes the same timing), about 21 could have been vetoed and about 5 stand unconfirmed. How
    many of the 21 the careful call would have confirmed is unknown.
  - Bound (estimated): `other` passes 0.90 only at 134/148, which needs +21 over 113. That
    requires that essentially every answered fast relay was wrong, that the careful call vetoed all
    of them, and that it gave the exact agreed label each time. On tuning v1, the careful call
    agreed with 1 of the 3 wrong fast relays. On v2 the same careful configuration read 0.72-0.88
    on `other`. Reaching 0.90 under (b) on a set like v3 would take every unknown going the
    favourable way.
- **(c) careful-authoritative:**
  - Changes the label on every `other` call where the careful call answered: the 88
    careful-answered calls (careful label unknown), the 10 careful relays (stand), and the 26
    fast-relay calls (careful label unknown, answered about 80% of the time, estimated).
  - Only the 24 late calls keep the fast label.
  - Its `other` rate becomes roughly the careful call's own, which is not on record for v3 and
    read 0.72-0.88 on v2.
- **(d) intersection, strict:** the 10 careful relays are dropped if, as the timing suggests, the
  fast call said non-relay. Each of the 26 fast relays needs a careful relay. About 5 (estimated,
  20% late) become fallbacks instead. Across v3, roughly 0.2 x 126 = 25 fast relays would face a
  silent careful call, an estimated fallback share of about 0.06 before any other cause.
- **(e) fast only:**
  - The 26 fast relays stand, so `other` is at most 123/148 = 0.83 (as E1g's record says). It
    FAILS whatever the 10 fast labels were.
  - The 14 careful relays in the completeness strata (7 regex-matched, 7 regex-missed) would get
    the fast label. How many of them were relay-gold is unknown, so the recall loss is between 0
    and 14 (regex-missed currently 24/25).
- **(f) careful only:**
  - At least 80 of 450 calls had no careful answer by 8.5 s, so the fallback share is >= 0.18 and
    (f) FAILS fallback.
  - At least 24 of the 148 `other` calls fall back, so `other` <= 124/148 = 0.84 and (f) FAILS
    `other` too.
  - Both are lower bounds (estimated: they assume the careful call's timing without a sibling fast
    call is the same).

**Bottom line (estimated).**
- Of the six rules, the v3 router-side data rules out (e) and (f) outright.
- (b) and (c) are the only rules that keep borderline sensitivity on tuning (19/26).
- Neither rule's `other` effect on v3 can be computed. (b)'s best case needs every unknown
  favourable, and (c) hands `other` labeling to the configuration that failed it twice on v2.
- Tuning v1 cannot discriminate among (a) to (d) on the failing mode, because the fast call
  makes 0 wrong `other` relays there.
- The careful call's label on fast-relayed prompts is the missing datum for (b), (c) and (d).
  Only a run that lets the careful call finish after a fast relay, on prompts not in any sealed
  set, can supply it.

## Script (run as `python3 replay.py`; output follows)

```python
#!/usr/bin/env python3
"""Offline replay of join rules for the fast+careful re-ask classifier (wave E1h research slot).
Part 1: E1c per-call tuning data (tune-2reps.json; arms off-e1b = fast, on-pre = careful, started
together, cold calls, load 28-46) + the two rater labels of tuning v1. No new calls, no sealed set.
Part 2: router-side v3 reading files (labels, walls, which call answered). No prompts, no gold."""
import json, collections, statistics
from pathlib import Path
REPO = Path("/Users/chrisren/Development/.worktrees/wt-cc-024434-55635")
H = Path.home() / ".claude/autonomy/research/router-heldout"
REL = ("completeness", "pushback")
FAST_LIM = 9.0   # fast label usable if it arrived inside the router's 9 s (as union-sim.py)
CARE_LIM = 8.5   # careful label usable only inside the 8.5 s hand-back (DELIVER_MARGIN_S)

d = json.load(open(REPO / "docs/research/router-classifier-e1c-2026-10-04/tune-2reps.json"))
strata = [json.loads(l)["stratum"] for l in open(H / "tuning.jsonl")]   # stratum only; prompt never read
lab = [{int(r["id"][1:]): r["label"] for r in map(json.loads, open(H / f"tuning-labels-{v}.jsonl"))}
       for v in ("anthropic", "openai")]
agreed = {k: lab[0][k] for k in lab[0] if lab[1].get(k) == lab[0][k]}
border = [k for k in lab[0] if k in lab[1] and lab[0][k] != lab[1][k] and (lab[0][k] in REL or lab[1][k] in REL)]

def valid(x): return x["label"] not in ("INVALID", "TIMEOUT")
def rel(lbl): return lbl in REL

def join(rule, F, C, care_lim=CARE_LIM):
    """-> (label or None, decision time in s, estimated from the two cold walls)."""
    fo = valid(F) and F["wall_s"] <= FAST_LIM; f = F["wall_s"]
    co = valid(C) and C["wall_s"] <= care_lim; c = C["wall_s"]
    cd = min(c, care_lim)            # when the careful call is done or given up on
    FL, CL = F["label"], C["label"]
    if rule == "a-union":
        rt = [t for ok, l, t in ((fo, FL, f), (co, CL, c)) if ok and rel(l)]
        if rt: return (FL if fo and rel(FL) and f <= min(rt) else CL), min(rt)
        if fo: return FL, max(f, cd)
        if co: return CL, c
        return None, 9.0
    if rule == "b-confirms":
        if fo and rel(FL):
            if co: return (FL if rel(CL) else CL), max(f, c)
            return FL, max(f, cd)
        if co and rel(CL): return CL, c
        if fo: return FL, max(f, cd)
        if co: return CL, c
        return None, 9.0
    if rule == "b'-confirms-no-careful-only":   # interpretation variant: careful-alone relay does not stand
        if fo and rel(FL):
            if co: return (FL if rel(CL) else CL), max(f, c)
            return FL, max(f, cd)
        if fo: return FL, f
        if co: return CL, c
        return None, 9.0
    if rule == "c-careful-auth":
        if co: return CL, c
        if fo: return FL, max(f, cd)
        return None, 9.0
    if rule == "d-intersection":     # strict: a relay needs both; a lone relay with no non-relay label = fallback
        if fo and not rel(FL): return FL, f
        if co and not rel(CL): return CL, (max(f, c) if fo else c)
        if fo and co: return FL, max(f, c)          # both relay
        return None, max(f if fo else 9.0, cd)
    if rule == "e-fast-only":
        return (FL, f) if fo else (None, 9.0)
    if rule == "f-careful-only":
        return (CL, c) if co else (None, 9.0)
    raise ValueError(rule)

RULES = ["a-union", "b-confirms", "b'-confirms-no-careful-only", "c-careful-auth",
         "d-intersection", "e-fast-only", "f-careful-only"]
fast, care = d["arms"]["off-e1b"], d["arms"]["on-pre"]
calls = [(int(k), i, F, care[k][i]) for k, Fs in fast.items() for i, F in enumerate(Fs)]

def score(rule, care_lim=CARE_LIM):
    out = [(k, *join(rule, F, C, care_lim)) for k, i, F, C in calls]
    fb = sum(1 for _, l, _ in out if l is None)
    rec = [rel(l) for k, l, _ in out if strata[k] != "other" and agreed.get(k) in REL]
    oth = [l == agreed[k] for k, l, _ in out if strata[k] == "other" and k in agreed]
    oth_ans = [l == agreed[k] for k, l, _ in out if strata[k] == "other" and k in agreed and l is not None]
    oth_rel = sum(1 for k, l, _ in out if strata[k] == "other" and k in agreed and rel(l))
    nonrel = [rel(l) for k, l, _ in out if k in agreed and agreed[k] not in REL]
    bd = sum(1 for k, l, _ in out if k in border and rel(l))
    ts = sorted(t for _, l, t in out if l is not None)
    return dict(recall=f"{sum(rec)}/{len(rec)}", other=f"{sum(oth)}/{len(oth)}",
                other_ans=f"{sum(oth_ans)}/{len(oth_ans)}", other_relays=oth_rel,
                false_relays=f"{sum(nonrel)}/{len(nonrel)}", border=f"{bd}/{2*len(border)}",
                fallback=f"{fb}/{len(out)}", wall_med=round(ts[len(ts)//2], 2),
                wall_p90=round(ts[int(len(ts)*0.9)], 2))

print("PART 1 — tuning v1, E1c pairs (fast=off-e1b, careful=on-pre), careful limit 8.5 s, fast limit 9.0 s")
print(f"agreed rows {len(agreed)}, borderline rows {len(border)}, calls {len(calls)}")
for r in RULES: print(f"{r:30s}", json.dumps(score(r)))
print("reconciliation: a-union with careful limit 9.0 s (union-sim.py's setting):", json.dumps(score("a-union", 9.0)))

# what the fast relays on agreed non-relay rows were, and what careful said in the same call
print("\nfast relays on agreed NON-relay rows (the over-flag the v3 'other' failure is made of):")
cnt = collections.Counter()
for k, i, F, C in calls:
    if k in agreed and agreed[k] not in REL and valid(F) and F["wall_s"] <= FAST_LIM and rel(F["label"]):
        cs = "careful relay<=8.5" if valid(C) and C["wall_s"] <= CARE_LIM and rel(C["label"]) else \
             "careful non-relay<=8.5" if valid(C) and C["wall_s"] <= CARE_LIM else "careful none<=8.5"
        cnt[(strata[k], agreed[k], cs)] += 1
for x, n in sorted(cnt.items()): print("  ", x, n)
print("careful relays on agreed NON-relay rows (fast non-relay):")
cnt = collections.Counter()
for k, i, F, C in calls:
    if k in agreed and agreed[k] not in REL and valid(C) and C["wall_s"] <= CARE_LIM and rel(C["label"]):
        fs = "fast relay" if valid(F) and rel(F["label"]) else "fast non-relay"
        cnt[(strata[k], agreed[k], fs)] += 1
for x, n in sorted(cnt.items()): print("  ", x, n)
print("borderline calls: fast relays and what careful said:")
cnt = collections.Counter()
for k, i, F, C in calls:
    if k in border:
        fr = valid(F) and rel(F["label"]); cr = valid(C) and C["wall_s"] <= CARE_LIM and rel(C["label"])
        cn = valid(C) and C["wall_s"] <= CARE_LIM
        cnt[(("F-rel" if fr else "F-non"), ("C-rel" if cr else "C-non" if cn else "C-none"))] += 1
for x, n in sorted(cnt.items()): print("  ", x, n)

# PART 2 — v3 router side
R = [json.loads(l) for l in open(H / "reading-v3-2026-10-05.jsonl")]
P = [json.loads(l) for l in open(H / "reading-v3-2026-10-05.paths.jsonl")]
assert len(R) == len(P) and all(r["got"] == p["label"] for r, p in zip(R, P))
def kind(p):
    w = p["why"]
    if w.startswith("classifier (careful call"): return "careful"
    if "had not answered" in w: return "fast, careful not answered by 8.5 s"
    if w == "classifier (fast call, resident)": return "fast"
    return "other-reason"
print("\nPART 2 — v3 router side (450 calls; 446 counted)")
tab = collections.Counter()
for r, p in zip(R, P):
    k = kind(p); k2 = k if k != "fast" else ("fast relay" if rel(p["label"]) else "fast non-relay, careful answered non-relay")
    tab[(r["stratum"], r["counted"], k2)] += 1
for x, n in sorted(tab.items()): print("  ", x, n)
def q(xs, p): xs = sorted(xs); return xs[min(len(xs)-1, int(len(xs)*p))]
def desc(xs):
    return f"n={len(xs)} min {min(xs):.2f} p25 {q(xs,.25):.2f} med {statistics.median(xs):.2f} p75 {q(xs,.75):.2f} p90 {q(xs,.9):.2f} max {max(xs):.2f}" if xs else "n=0"
cr = [p["wall_s"] for p in P if kind(p) == "careful"]
cr_oth = [p["wall_s"] for r, p in zip(R, P) if kind(p) == "careful" and r["stratum"] == "other" and r["counted"]]
fr = [p["wall_s"] for p in P if kind(p) == "fast" and rel(p["label"])]
fr_oth = [p["wall_s"] for r, p in zip(R, P) if kind(p) == "fast" and rel(p["label"]) and r["stratum"] == "other" and r["counted"]]
fn = [p["wall_s"] for p in P if kind(p) == "fast" and not rel(p["label"])]
print("careful relay walls (router clock), all:", desc(cr))
print("  on counted 'other':", desc(cr_oth), sorted(cr_oth))
print("fast relay walls, all:", desc(fr))
print("  on counted 'other':", desc(fr_oth))
print("fast non-relay with careful answered non-relay (wall ~ max(fast, careful)):", desc(fn))
print("careful relay walls below the fast-relay p90 / max:", sum(1 for w in cr if w <= q(fr, .9)), sum(1 for w in cr if w <= max(fr)))
nr = [p for p in P if not (kind(p) == "fast" and rel(p["label"]))]
ans = sum(1 for p in nr if kind(p) in ("careful", "fast")); late = sum(1 for p in nr if kind(p).startswith("fast, careful not"))
print(f"careful call answered by 8.5 s on calls the fast call did not relay: {ans}/{ans+late} = {ans/(ans+late):.2f}")
oth = [(r, p) for r, p in zip(R, P) if r["stratum"] == "other" and r["counted"]]
print("counted 'other' by answering call:", collections.Counter(kind(p) + (" relay" if rel(p["label"]) else "") for r, p in oth))
print("labels on counted 'other':", collections.Counter(p["label"] for r, p in oth))
print("relay labels on counted 'other' by call:", collections.Counter((kind(p), p["label"]) for r, p in oth if rel(p["label"])))
```

## Output (measured, 2026-10-06 ~01:09 CDT)

```
PART 1 — tuning v1, E1c pairs (fast=off-e1b, careful=on-pre), careful limit 8.5 s, fast limit 9.0 s
agreed rows 69, borderline rows 13, calls 192
a-union                        {"recall": "52/52", "other": "43/44", "other_ans": "43/44", "other_relays": 3, "false_relays": "7/84", "border": "19/26", "fallback": "1/192", "wall_med": 4.91, "wall_p90": 8.5}
b-confirms                     {"recall": "52/52", "other": "43/44", "other_ans": "43/44", "other_relays": 3, "false_relays": "6/84", "border": "19/26", "fallback": "1/192", "wall_med": 5.66, "wall_p90": 8.5}
b'-confirms-no-careful-only    {"recall": "51/52", "other": "44/44", "other_ans": "44/44", "other_relays": 2, "false_relays": "2/84", "border": "10/26", "fallback": "1/192", "wall_med": 2.2, "wall_p90": 6.54}
c-careful-auth                 {"recall": "52/52", "other": "43/44", "other_ans": "43/44", "other_relays": 3, "false_relays": "6/84", "border": "19/26", "fallback": "1/192", "wall_med": 5.66, "wall_p90": 8.5}
d-intersection                 {"recall": "50/52", "other": "44/44", "other_ans": "44/44", "other_relays": 2, "false_relays": "1/84", "border": "9/26", "fallback": "9/192", "wall_med": 2.14, "wall_p90": 5.66}
e-fast-only                    {"recall": "51/52", "other": "44/44", "other_ans": "44/44", "other_relays": 2, "false_relays": "3/84", "border": "10/26", "fallback": "1/192", "wall_med": 1.7, "wall_p90": 2.31}
f-careful-only                 {"recall": "51/52", "other": "34/44", "other_ans": "34/35", "other_relays": 3, "false_relays": "5/84", "border": "18/26", "fallback": "41/192", "wall_med": 5.21, "wall_p90": 7.36}
reconciliation: a-union with careful limit 9.0 s (union-sim.py's setting): {"recall": "52/52", "other": "43/44", "other_ans": "43/44", "other_relays": 3, "false_relays": "7/84", "border": "19/26", "fallback": "1/192", "wall_med": 4.91, "wall_p90": 9.0}

fast relays on agreed NON-relay rows (the over-flag the v3 'other' failure is made of):
   ('regex-matched', 'new-idea', 'careful none<=8.5') 1
   ('regex-matched', 'new-idea', 'careful relay<=8.5') 1
   ('regex-missed', 'other', 'careful non-relay<=8.5') 1
careful relays on agreed NON-relay rows (fast non-relay):
   ('other', 'other', 'fast non-relay') 1
   ('regex-matched', 'new-idea', 'fast relay') 1
   ('regex-missed', 'other', 'fast non-relay') 3
borderline calls: fast relays and what careful said:
   ('F-non', 'C-non') 3
   ('F-non', 'C-none') 4
   ('F-non', 'C-rel') 9
   ('F-rel', 'C-none') 1
   ('F-rel', 'C-rel') 9

PART 2 — v3 router side (450 calls; 446 counted)
   ('other', True, 'careful') 10
   ('other', True, 'fast non-relay, careful answered non-relay') 88
   ('other', True, 'fast relay') 26
   ('other', True, 'fast, careful not answered by 8.5 s') 24
   ('pushback', True, 'fast non-relay, careful answered non-relay') 1
   ('pushback', True, 'fast relay') 2
   ('pushback', True, 'fast, careful not answered by 8.5 s') 1
   ('regex-matched', False, 'fast relay') 2
   ('regex-matched', True, 'careful') 7
   ('regex-matched', True, 'fast non-relay, careful answered non-relay') 35
   ('regex-matched', True, 'fast relay') 51
   ('regex-matched', True, 'fast, careful not answered by 8.5 s') 21
   ('regex-missed', False, 'fast relay') 2
   ('regex-missed', True, 'careful') 7
   ('regex-missed', True, 'fast non-relay, careful answered non-relay') 96
   ('regex-missed', True, 'fast relay') 43
   ('regex-missed', True, 'fast, careful not answered by 8.5 s') 34
careful relay walls (router clock), all: n=24 min 3.06 p25 4.57 med 5.62 p75 6.76 p90 7.58 max 8.47
  on counted 'other': n=10 min 3.06 p25 4.02 med 5.54 p75 6.27 p90 7.14 max 7.14 [3.06, 3.99, 4.02, 4.12, 5.54, 5.55, 6.08, 6.27, 6.66, 7.14]
fast relay walls, all: n=126 min 0.44 p25 0.50 med 0.54 p75 0.63 p90 0.83 max 6.96
  on counted 'other': n=26 min 0.45 p25 0.48 med 0.51 p75 0.52 p90 0.62 max 6.96
fast non-relay with careful answered non-relay (wall ~ max(fast, careful)): n=220 min 2.39 p25 4.38 med 5.68 p75 6.78 p90 7.52 max 8.50
careful relay walls below the fast-relay p90 / max: 0 19
careful call answered by 8.5 s on calls the fast call did not relay: 244/324 = 0.75
counted 'other' by answering call: Counter({'fast': 88, 'fast relay': 26, 'fast, careful not answered by 8.5 s': 24, 'careful relay': 10})
labels on counted 'other': Counter({'other': 47, 'work-order': 34, 'completeness': 28, 'research-order': 15, 'new-idea': 10, 'pushback': 8, 'concern': 6})
relay labels on counted 'other' by call: Counter({('fast', 'completeness'): 21, ('careful', 'completeness'): 7, ('fast', 'pushback'): 5, ('careful', 'pushback'): 3})
```
