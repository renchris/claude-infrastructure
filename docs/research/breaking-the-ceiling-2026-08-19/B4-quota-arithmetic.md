---
axis: B4 — the sustained-throughput arithmetic. What number does each lever actually deliver?
date: 2026-08-19
status: MEASURED — ceiling re-derived from today's live meters; ladder costed per lever
builds_on: docs/research/orchestration-units-2026-08-19.md (4a3bd3373) + A6 / A6-VERIFY
headline: >
  Sustained concurrency is quota-bound at ~8.7-8.9 working units fleet-wide (~24-25 resident panes),
  and the operator is not near that — they are near a LOWER wall they built themselves. Today's routing mix
  walls `next` at 1.14x while three accounts sit at 0.55-0.73x, which caps the fleet at 5.95 working
  units = 16.7 resident panes. The operator runs 17. Balance is worth +2.9 units (+49%) and is free.
  The lever the wave was most tempted by — express fan-out as workflow agents instead of named
  teammates — moves the wrong ceiling: it is ~3x (3.2-3.5x) LESS quota-efficient per output token, so it buys
  box capacity we do not need and spends the quota we do.
load_bearing_claim: >
  A quota point buys OUTPUT TOKENS, and every orchestration unit pays a roughly identical fixed
  cache-creation ARRIVAL TAX (125-281K tokens) on the way in. So sustained quota efficiency is a
  function of how much work each unit does, not of what process shape wraps it. Cheap-on-the-box
  units are cheap because they are SMALL, and small is exactly what the meter punishes.
---

## 1. Verdict (≤5 lines)

1. **CURRENT sustainable ceiling, re-derived from today's meters: ~8.7–8.9 concurrent WORKING units
   fleet-wide (5.8–10.7), = ~24–25 resident panes (16–30) at the measured 0.357 duty cycle.**
   The landed figures (6.08 %/day per unit → 9.4 units, duty 0.36, crossover 26) reproduce: I get
   **6.45–6.57 %/day per unit, duty 0.357, 8.70–8.86 units, crossover 24.4–24.8**. Both halves hold.
   It moved 6% in 8 hours and 1.8% in 8 *minutes* — quote it as a band with its timestamp, or re-run.
2. **They are quota-bound TODAY — but by IMBALANCE, not by total.** Fleet burn is 43.7–49.3 %/day
   against a 57.1 %/day allowance (76–86% used), yet `next` projects **113.7% ⚠ WALL** while next2/
   next3/next4 project 54.7/73.2/63.9%. Under today's mix the fleet walls when `next` walls: **5.95
   working units = 16.7 panes. They are running 17.**
3. **L-b (balance the 4 accounts) is the whole free win: +2.91 units, +8.1 panes, +49%.** It is
   unrealised because the router's `k_work` walk is `scandir` at **depth 1 only**, so it is blind to
   every nested fan-out transcript: measured **35 of 41 live writers invisible (85%), 100% of them
   workflow agents** — and the polarity is inverted, reading `next=0` (the walled account) while
   `next` had 18 live writers.
4. **L-a is a trap and this axis exists to say so.** Named teammates deliver **31,503 output tokens
   per quota point**; workflow agents **8,936**, unnamed sidechain subagents **11,622** — a **~3×
   penalty** (3.2–3.5× on re-run; 2.43–3.53× across every exchange-rate variant tested, incl. one penalising
   teammates for 1h-TTL cache). L-a raises agents-per-pane and *lowers* sustained throughput.
5. **The honest bottom line: sustained is quota-bound at ~9–12 working units no matter what we do
   locally, and only off-meter capacity moves it further.** Free levers reach ~11–12 units (≈33
   panes). A 5th Claude account is +2.21 units, linear, and costs money. The two already-routable
   non-Claude backends are the only units that consume neither ceiling.

---

## 2. The numbers, with the command behind each

### 2.0 The live account readout, VERBATIM

`/Users/chrisren/.claude/bin/claude-accounts --readout` — invoked **directly**. The brief's
`bash <path>` form is wrong (the file is `#!/usr/bin/env python3`); A6-VERIFY §C7 already established
this and it reproduced here.

```
| account | live | 5h used | 5h resets | weekly used | Fable used | weekly resets | login expires |
|---|---|---|---|---|---|---|---|
| **next** ➤ᶠ | 2 | 17% | Wed 07:29 (in 1.3h) | 55% | 22% | Sat 20:59 (in 3d 14h) | Tue Sep 15 15:44 (in 27d 9h) |
| next4 | 3 | 20% | Wed 09:19 (in 3.1h) | 29% | 15% | Sun 01:59 (in 3d 19h) | Sat Sep 12 23:02 (in 24d 16h) |
| next3 | 7 | 27% | Wed 07:00 (in 45m) | 11% | 0% | Tue 05:00 (in 5d 22h) | Thu Sep 03 10:27 (in 15d 4h) |
| **next2** ➤ ← you | 5 | 24% | Wed 08:49 (in 2.6h) | 32% | 0% | Sat 03:59 (in 2d 21h) | Mon Sep 07 04:28 (in 18d 22h) |

➤ desk (bare `claude`) → **next2** — earliest weekly reset among 5h-safe accounts · weekly ↻ 2d 21h · 5h 24% · safe set · sticky
➤ general → **next2** · ➤ fable → **next**
weekly burn (1.00× = lands exactly at the 100% wall): next2 burn 0.55× → ~55% by reset, needs 23%/d over 2d (recent 16%/d) · next burn 1.14× → ~114% by reset ⚠ WALL, needs 12%/d over 3d (recent 8%/d) · next4 burn 0.64× → ~64% by reset, needs 19%/d over 3d (recent 10%/d) · next3 burn 0.73× → ~73% by reset, needs 15%/d over 5d (recent 14%/d)
Fable window: **permanent** (no expiry).

**Agent backends beyond Claude** — registry `~/.claude/providers.json`

| backend | routable | version | auth | plan | bills outside it? | model pinned |
|---|---|---|---|---|---|---|
| Codex CLI | ✅ | codex-cli 0.147.0 | ok | ChatGPT Plus | no | gpt-5.6-sol @ xhigh ✓proven |
| Pi · Codex backend | ✅ | 0.84.1 | ok | ChatGPT Plus | no | gpt-5.6-sol ✓proven |
| Pi · Claude backend | ⊘ skipped | 0.84.1 | credentials_not_configured | Claude Pro/Max (auth works, usage does NOT draw on the plan) | 🚨 **YES** | — |
| Antigravity | ⊘ skipped | 1.107.0 | ok | UNKNOWN | UNKNOWN | — |
| Gemini CLI | ⊘ skipped | 0.29.5 | ok | UNKNOWN | UNKNOWN | gemini-3-pro-preview ⚠unproven |
| Grok CLI | ⊘ skipped | not installed | — | UNKNOWN | 🚨 **YES** | — |
- ⊘ `pi-claude` — COST GATE FAIL — bills per token outside the Max plan
- ⊘ `antigravity` — NOT AN AGENT BACKEND — the binary is the VS Code editor launcher, no non-interactive mode
- ⊘ `gemini` — DEFERRED — plan tier UNKNOWN, so the cost gate cannot clear it
- ⊘ `grok` — COST GATE FAIL — API-key-only, and we hold no xAI plan

➤ non-Claude backends ready now: **2 of 2 routable** (6 known)
- 🚨 rows marked **YES** bill OUTSIDE a plan we hold — not wired, by policy (`accounts.json spend.usage_credits_authorized=false`)
```

Three lines change a decision: **`next` is at ⚠ WALL 1.14× while the other three sit at 0.55–0.73×**;
`next3` holds 7 of 17 panes on the account with the *most* weekly slack (11% used, resets in 5d 22h);
and two non-Claude backends are `✅ routable` right now and appear in nobody's capacity model.

---

### 2.1 THE SUSTAINABLE CEILING, RE-DERIVED (do not inherit — this drifts)

**Method (model-free, touches no token model).** Slope of each account's own **weekly meter**
(%/day) over one weekly window, divided by the mean `k_work` observed across that same window.
Windows keyed on `weekly_reset_at` **rounded to the hour** — keying on the raw string fragments the
set, because the field drifts by minutes sample-to-sample (this is A6 §3.3's trap; keying to the
minute is *not* enough, it still split `next` into two windows giving 5.17 and 8.09).

```
$ python3 docs/research/breaking-the-ceiling-2026-08-19/B4-weekly-slope.py          # walks ~/.claude/logs/account-utilization.jsonl (7,697 rows)
rows with NULL weekly_reset_at: 165/7697   (excluded; positive control: 7,532 rows DO have it)

acct   window start         hrs   dW%   %/day  meankw   nkw  %/d/unit
next   2026-08-16T04:04   81.2    54    16.0    2.48   527      6.45
next2  2026-08-15T18:50   90.4    32     8.5    0.90   527      9.45
next3  2026-08-11T17:56  162.0    98    14.5    2.72   340      5.34
next3  2026-08-18T15:04   22.2    11    11.9    2.06   160      5.78
next4  2026-08-16T09:04   76.2    28     8.8    1.23   527      7.15

n=5 median=6.45 mean=6.83 range=5.34-9.45 %/day/unit
allowance = 100%/7d = 14.29 %/day
  => per account: 2.22 units (median) | 1.51-2.68
  => FLEET (4)  : 8.86 units (median) | 6.05-10.71
```

**Re-run of the same script 8 minutes later, 13:22Z — quoted because the drift is the point:**

```
next   2026-08-16T04:04   81.3    55    16.2     2.47   528        6.57
next2  2026-08-15T18:50   90.5    34     9.0     0.91   528        9.94
next3  2026-08-11T17:56  162.0    98    14.5     2.72   340        5.34
next3  2026-08-18T15:04   22.3    11    11.8     2.06   161        5.76
next4  2026-08-16T09:04   76.3    28     8.8     1.23   528        7.14
n=5 median=6.57  => FLEET (4): 8.70 units (5.75-10.71)  => crossover 24.4 panes (16.1-30.0)
```

**8 minutes moved the fleet figure 8.86 → 8.70 (−1.8%) and the crossover 24.8 → 24.4.** Report this
quantity as **~8.7–8.9 working units / ~24–25 resident panes**, never as a point, and re-run the
script rather than citing this file's digits (repo memory: `published-figure-decays-with-its-source`).
Everything downstream uses the 13:14Z snapshot, so it stays internally consistent with the readout in
§2.0 and the imbalance analysis in §2.2, which were taken at the same instant.

**Duty cycle, re-measured** (fleet buckets where all 4 accounts report `k_work`):

```
=== FLEET DUTY CYCLE ===
  n=527 minutes
  fleet k (panes)        med=15  p95=37  max=51
  fleet k_work (writers) med=5   p95=22  max=46
  fleet k_work/k         med=0.357  mean=0.395  p95=0.800  max=1.842
  LAST 24h: n=175  k med=13  kw med=5  ratio med=0.364 mean=0.374
```

| quantity | LANDED (A6-VERIFY, 08-19 early) | **RE-DERIVED (this axis, 08-19 13:14Z)** | verdict |
|---|---|---|---|
| %/day per working unit | 6.08 (5.21–9.23) | **6.45 (5.34–9.45)** | reproduces, 6% tighter |
| duty cycle `k_work/k` | 0.36 (n=517) | **0.357 (n=527)** | reproduces |
| sustainable units, fleet | 9.4 (6.2–11.0) | **8.86 (6.05–10.71)** | reproduces |
| crossover, resident panes | 26 (17–30) | **24.8 (16.9–30.0)** | reproduces |

**Both halves check out. State the number as 8.9 working units / ~25 panes, dated.** It moved 6% in
eight hours; anyone quoting it a week from now should re-run `b4_weekly.py`, not cite this line.

---

### 2.2 ARE THEY QUOTA-BOUND TODAY? — yes, and by imbalance, not by total

```
$ python3 -  # over claude-accounts --json
acct    wk% elapsed_d  avg %/d recent %/d proj_end  ratio   k  kw
next     55      3.39    16.25       8.26    113.7   1.14   2   0
next4    29      3.18     9.13      10.32     63.9   0.64   3   0
next3    11      1.05    10.46      14.32     73.2   0.73   7   1
next2    32      4.09     7.82      16.36     54.7   0.55   5   2

FLEET allowance = 4 x 14.29 = 57.14 %/day
FLEET avg-so-far burn  = 43.65 %/day  = 76% of allowance
FLEET recent burn      = 49.26 %/day  = 86% of allowance
FLEET k (panes) = 17   k_work = 3
```

Two different answers, and the gap between them **is** the finding:

| question | answer |
|---|---|
| Is the FLEET TOTAL quota-bound? | **Not quite** — 76–86% of allowance used. 14–24% headroom ≈ **+1.2 to +2.1 working units.** |
| Is the operator quota-bound in practice? | **Yes.** `next` walls at 1.14× while the mean account sits at 0.764×. Under a fixed routing mix the fleet stops when the first account stops. |

```
IMBALANCE  mean burn_ratio=0.764  max=1.137 (next)
  => effective sustainable under TODAY's routing mix = 8.86 x 0.764/1.137 = 5.95 units = 16.7 panes
```

**The operator runs 17 resident panes against a 16.7-pane imbalance-limited ceiling.** That is the
direct answer to the question behind the question: the felt ~15 ceiling is *not* the box and *not*
the fleet's quota — it is one account's quota, reached because the work is not spread.

*Caveat, stated because it cuts against me:* "recent burn 49.26 %/day" is measured while this very
wave is running 8+ agents. The avg-so-far figure (43.65) is the fairer sustained reading. Both leave
the imbalance verdict unchanged — that one is computed from `proj_end_pct`, not from burn rate.

---

### 2.3 WHY L-b IS UNREALISED — the router is 85% blind, and inverted on the walled account

The brief says `k_work` misroutes. It is worse than "noisy", and the mechanism is a one-line
structural fact rather than a tuning problem.

**The mechanism.** `bin/claude-accounts:working_concurrency()` walks
`projects/<slug>/` with `os.scandir(slug.path)` and takes `fe.name.endswith(".jsonl")` — **depth 1
only, no recursion.** Its own docstring promises the opposite: *"active subagents append to their own
.jsonl siblings and are burners too"* — true for named teammates (`projects/<slug>/<uuid>.jsonl`),
false for workflow agents and unnamed subagents, which are filed at
`projects/<slug>/<session>/subagents/[workflows/<wf>/]agent-*.jsonl`.

**Measured, at the same instant as the readout, using k_work's own 10-minute window:**

```
$ python3 -   # replicates the depth-1 scandir, then compares against a recursive walk
=== WHAT k_work ACTUALLY COUNTS (its own 10-min window, its own depth-1 scandir) ===
depth-1  projects/<slug>/*.jsonl   : {'next2': 4, 'next3': 1, 'next4': 1}  TOTAL 6
DEEPER   (invisible to the walk)   : {'next': 18, 'next2': 14, 'next4': 3}  TOTAL 35
   deeper breakdown by kind        : {'workflow': 35}
router reported k_work             : {'next': 0, 'next4': 0, 'next3': 1, 'next2': 2}  TOTAL 3

blind fraction = 35/41 = 85% of live writers
```

- **85% of live writers are invisible**, and **100% of the invisible ones are workflow agents.**
- **The polarity is inverted where it matters most.** The router reads `next = 0 working` — the
  idlest account in the fleet — while `next` had **18 live writers** and is the one account at
  ⚠ WALL 1.14×. `next3`, which reads 1, had 0.
- Its own instrument note is honest about a *different* failure (`k_work=None` when the walk exceeds
  budget, 72.6% of samples here) and silent about this one, because the depth-1 walk **succeeds** —
  it returns a confident wrong number rather than abstaining. A null from a blind instrument reads as
  absence; this is worse, it reads as *idle*.

*Scope note:* this is B5's axis. I measured it only far enough to price L-b, and the price is that
L-b's +2.91 units are currently unreachable by the automatic router.

---

### 2.4 THE CRUX — L-a moves the wrong ceiling. Measured ~3× (3.2–3.5×).

The temptation: a named teammate is 382 MB + a pane + a process; an unnamed subagent or workflow
agent is 0.6–11 MB and no pane. Express the fan-out cheaply and get more agents per pane.

**That is a BOX lever, and the box is not the sustained wall.** On the QUOTA axis, measure work per
quota point. Proxy for work = **output tokens** — the meter's dominant term and the only token class
that is unambiguously produced reasoning.

```
$ python3 docs/research/breaking-the-ceiling-2026-08-19/B4-class-efficiency.py 60      # 4 stores, realpath-deduped, message.id-deduped,
                                         # record's OWN timestamp (not file mtime), pp @ A6's fit
window=60.0h  files scanned=451  cross-store dup paths skipped=0

class                 files    resp        output    cache_creat     cache_read       pp    out/pp  work%
main-session            136   13570    10,538,331    163,718,072  3,694,598,368    386.4    27,270  21.6%
teams-agent             131    6962     5,267,444     67,802,668  1,038,538,604    167.2    31,503  25.0%
workflow-agent          138    4123       525,720     29,548,791    557,277,769     58.8     8,936   7.1%
sidechain-subagent       30     771       100,857      4,258,463     89,143,506      8.7    11,622   9.2%
TOTAL                                                                              621.2

QUOTA EFFICIENCY  teams-agent : workflow-agent = 31,503 : 8,936 out-tok/pp = 3.53x
QUOTA EFFICIENCY  main-session: workflow-agent = 27,270 : 8,936 out-tok/pp = 3.05x

SENSITIVITY to the exchange rate:
  A6 deduped fit (7.93/1.85)          teams/workflow = 3.53x
  A1 raw fit     (9.27/1.04)          teams/workflow = 2.99x
  cc @1.6x for 1h-TTL classes only    teams/workflow = 2.43x
```

**Re-run 8 minutes later** (466 files; the live wave was still adding workflow agents):
`teams 31,562 : workflow 9,730 = **3.24×**`. So the penalty is a band, not a digit —
**3.2–3.5× at the A6 fit, 2.4–3.5× across every rate tested.** Direction and order of magnitude are
stable across both the time drift and the exchange-rate sensitivity; treat "~3×" as the finding.

**The verdict survives every exchange rate, including the one built to hurt it.** A6's open Q1 (does
1h-TTL cache cost 1.6× a 5m one?) is the strongest available argument *for* workflow agents; granting
it in full still leaves them **2.43× worse**.

*Independent-derivation check:* my `teams-agent` total lands at **167.2 pp**, identical to A6 §2.8's
167.2 pp from a separately written script. Main 386.4 vs 377.4 and workflow 58.8 vs 67.6 differ by the
two-day window shift.

**The mechanism — and it is the generalizable law, not a fact about workflows.**

```
$ python3 -   # out-per-pp banded by the UNIT's own output size
unit output band    n units       sum out         sum cc       pp    out/pp
<1K                      90        32,995     10,813,846     20.3     1,628
1K-10K                  104       431,407     29,211,835     57.5     7,508
10K-50K                 121     3,213,036     26,740,005     74.9    42,870
50K-200K                116    11,346,790    116,918,690    306.3    37,047
>200K                     4     1,422,896     81,719,450    162.5     8,758

teams-agent          n=131  median unit output=30,518 tok   out/pp=31,510  median cc/unit=158,792
workflow-agent       n=138  median unit output= 1,708 tok   out/pp= 9,059  median cc/unit=175,219
sidechain-subagent   n= 30  median unit output= 1,688 tok   out/pp=11,622  median cc/unit=124,686
main-session         n=136  median unit output=69,439 tok   out/pp=27,276  median cc/unit=281,409
```

**The arrival tax is a fixed, roughly class-independent 125–281K cache-creation tokens per unit.**
Workflow agents and unnamed subagents pay the *same* tax as a teammate (175K vs 159K — the workflow
agent pays *more*) against **18× less output**. They are not cheap units; they are units that pay
full price for a fraction of the work. A unit's quota efficiency tracks its **size**, not its process
shape — 1,628 out/pp below 1K output, 42,870 out/pp in the 10–50K band, a **26× swing** on the same
axis that L-a would push the wrong way.

*(The `>200K` band inverting to 8,758 is a small-n artifact of 4 very-long-context main sessions
carrying 81.7M cache-creation between them, not a real efficiency collapse; n=4, do not build on it.)*

**So L-a's precise answer, which is the thing the wave needed settled:**

| | L-a delivers |
|---|---|
| agents per pane | 1 → 8 per workflow run, 20 per session. **Real.** |
| resident memory | 382 MB → 0.6–11 MB. **Real.** |
| BURST session-equivalents | positive, but re-bound almost immediately by the load gate (~4–8 mid-turn, B3) and by the 8/20 caps themselves — the cheap path is the *capped* one. |
| **SUSTAINED session-equivalents** | **NEGATIVE. −2.43× to −3.53× work per quota point.** |
| what it does NOT solve | the quota wall, which is the only sustained wall. It makes it arrive **~3× sooner** for the same delivered work. |

**The actionable form of L-a is its inverse: fan out to FEWER, BIGGER units.** Today
**67.5 pp of 621.2 (10.9%) of all fleet spend** goes to units whose median output is ~1,700 tokens —
**91–93% of that spend is arrival tax, not work.** Consolidating that slice to teams-agent efficiency
frees `67.5 × (1 − 1/3.53) = 48.4 pp / 60h = 19.4 pp/day fleet-wide = +3.0 sustained working units`
(**UPPER BOUND** — it assumes the small jobs merge, which I did not measure; see §3).

---

### 2.5 THE LADDER

Unit: **1 session-equivalent = 1 continuously-WORKING unit**, i.e. one unit emitting at the measured
6.45 %/day of one account's weekly meter. Multiply by 1/0.357 = **2.80** for resident panes.

| lever | SUSTAINED s-e | BURST s-e | costs | does NOT solve | available today |
|---|---|---|---|---|---|
| **L-a** express fan-out as workflow/unnamed agents | **−, ÷2.43–3.53 on the slice moved** | + (bounded by load gate ~4–8 and the 8/20 caps) | quota, hard | the quota wall — it arrives ~3× sooner | yes, and it is a **net loss**; the inverse (consolidate to bigger units) is worth **+1.5 to +3.0** |
| **L-b** spread across the 4 accounts | **+2.91** (5.95 → 8.86; +49%) | +0 (burst is already box-bound) | nothing — same work, same tokens, four meters | the box; the refresh herd | **structurally yes, operationally NO** — the router is 85% blind (§2.3). Manual `--account` works today. |
| **L-c** cloud sessions | **+N if off-meter, 0 if on** — B2 owns the fork | + regardless | unknown | the box either way | conditional |
| **L-d** reduce ambient load (B3) | **≤ +1.2 to +2.1**, hard-capped by the 14–24% unspent allowance | + directly | box effort | the quota — it raises the RATE you can spend, never the allowance | yes |
| **L-e** non-Claude backends (Codex CLI, Pi·Codex) | **+N, off both ceilings** — bounded by ChatGPT Plus's own meter, which nobody measured | + | none on our meters | nothing about Claude capacity | **✅ routable now** |
| **L-f** in-process teammates (B1) | **+0, but NEUTRAL not negative** — same unit size ⇒ same arrival tax ⇒ same out/pp | + (removes pane + 382 MB + process) | a config flip (`teammateMode`), and it **costs pane VISIBILITY** | the quota | yes, one setting |
| *(reference)* a 5th Claude account | **+2.21** (+6.2 panes), linear | + | money | the box | purchasable |

**L-f is strictly better than L-a and the wave should not confuse them.** Both remove the pane and the
382 MB. L-a does it by shrinking the *unit of work* — which multiplies the arrival tax. L-f does it by
shrinking the *process wrapper* while the unit of work stays a teammate-sized job — so out/pp is
unchanged. **Cheapen the wrapper, never the job.**

---

### 2.6 THE HONEST BOTTOM LINE

```
  (i)   today, as routed                          6.0 working units =  16.7 resident panes   <- they run 17
  (i')  today, if perfectly balanced              8.9 working units =  24.8 resident panes
  (ii)  free levers (L-b + consolidate fan-out)  ~11-12 working units = ~31-33 resident panes
  (iii) + a 5th account                          ~14   working units = ~39   resident panes
```

| step | max SUSTAINED session-equivalents | **the wall that binds** |
|---|---|---|
| **(i) today, zero changes** | **5.95** (16.7 panes) | **`next`'s weekly meter** — one account at 1.14× while the fleet mean is 0.764× |
| **(i′) balance only** | **8.86** (24.8 panes) | the **fleet weekly meter** |
| **(ii) free levers only** | **~11–12** (31–33 panes) | still the **fleet weekly meter** — and now the box re-enters: the load gate (~4–8 mid-turn) and terminal (~30) arrive in the same range |
| **(iii) everything local, incl. a 5th account** | **~14** (39 panes) | the **fleet weekly meter again**, plus the **OAuth refresh herd** (A6-VERIFY §C3: fan-out concentrates herd risk on the same axis, and its failure mode is a discontinuous account-wide logout) |

*(ii) is a band, not a point, because L-b's +2.91 and the fan-out-consolidation's +3.0 partially
overlap: the 6.45 %/day-per-unit denominator counts only depth-1 units (§2.3) while its numerator
includes the invisible workflow agents' spend, so removing that spend also corrects the rate by
~10.9% in the same direction. I have not double-counted them into a single 14.8; I have banded them
at 11–12.*

**The sentence the wave needs:** *sustained concurrency is quota-bound at roughly 9–12 working units
fleet-wide (≈25–33 resident panes) and no local process engineering moves that — the only things that
raise it are more meters (a 5th account, +2.21) or capacity that is off the meter entirely (the two
already-routable non-Claude backends). Everything else in the ladder either redistributes the same
allowance or, in L-a's case, spends it 3× faster.*

**And the immediately actionable one:** the operator is not at the 25-pane wall. They are at a
16.7-pane wall of their own making, and **balancing the accounts is worth +49% for free.**

---

## 3. What I could NOT measure, and why

1. **Whether the small-unit work actually merges.** The +3.0 from consolidating fan-out assumes a
   20-wide grep-the-files fan-out *could* have been 2 bigger units. Some genuinely cannot. Treat +3.0
   as an upper bound; the lower bound (halving the unit count) is ~+1.5. **The 3.53× penalty itself is
   measured and is not an assumption** — only the recoverable fraction is.
2. **Cloud-session billing (L-c).** B2 owns it. My table is written as a fork because the answer
   changes the row from "+N sustained" to "burst only", and nothing else in my axis resolves it.
3. **Ambient load (L-d) and in-process teammate cost (L-f).** B3 and B1. I costed L-d only by its
   *ceiling* — it cannot exceed the 14–24% of allowance currently unspent, whatever the box gains.
4. **ChatGPT Plus's own meter.** L-e is off *our* ceilings but has its own, and I did not measure it.
   Without that number L-e is "+N unbounded", which is not a number a decision can rest on. **This is
   the largest missing figure in the wave** — it is the only lever that adds capacity rather than
   redistributing it, and nobody owns it (A6 §4 Q4 and A6-VERIFY §4 Q5 both flag the same gap).
5. **The 1h vs 5m cache-TTL price.** Structurally collinear with class (A6 §2.6: 100%/0% separation),
   so observational data can never identify it. I handled it by granting the worst case as a
   sensitivity row (2.43×) rather than by resolving it.
6. **Whether duty cycle 0.357 is causal or symptomatic.** If panes idle *because* the box is slow,
   L-d would raise duty and thus burn — converting box headroom into quota burn. A6-VERIFY already
   ruled out quota-forced idling (only 1.1% of samples ≥90% of a 5-hour window); it did not rule out
   box-forced idling. This matters: **a box lever that raises duty cycle spends quota faster and can
   make (i) worse, not better.**
7. **`k_work` censoring bounds every rate here.** It is `None` in **72.6%** of samples (2,108/7,697
   present). Every %/day-per-unit figure is computed on the measured 27.4%. If the walk aborts
   preferentially when the fleet is busiest, mean `k_work` is biased low ⇒ %/day/unit biased high ⇒
   sustainable count biased **low**. The correction is conservative in the operator's favour.
8. **I spawned nothing and changed nothing.** No `claude -p`, no fires, no config touched, nothing
   killed or stopped. All of the above is log/transcript/`ps`-free filesystem reads plus one direct
   invocation of the read-only `claude-accounts` dashboard.

**Instrument note for the rest of the wave:** A6 §2.2 reported `sidechain-subagent = 0` in its 60-hour
window as a *genuine absence*. It is **non-empty today** — 771 assistant records across 30 files under
`~/.claude-quaternary/.../subagents/agent-*.jsonl`. That class refilled in two days; do not inherit
the zero.

---

## 4. The decision this axis changes

**Do not spend the wave's effort on cheaper orchestration units.** That was the wave's most likely
recommendation and it is measurably backwards: a workflow agent buys 0.6 MB instead of 382 MB and
pays 3.53× more quota per unit of work delivered. The box is not the sustained wall — above ~25
resident panes quota is, and below it the binding constraint today is one over-burned account.

**Three actions, in the order their numbers justify:**

1. **Fix the router's blindness, then balance.** `working_concurrency()` must recurse (or the fan-out
   spend must be attributed some other way). Today it reads the walled account as idle. **Worth +2.91
   sustained session-equivalents (+49%), free.** Until it is fixed, `--account` chosen by hand beats
   the router — which is a sentence worth putting in `commands/handoff.md`.
2. **Make fan-out units BIGGER, not cheaper.** 10.9% of all fleet quota currently buys ~1,700 output
   tokens per unit against a 175K arrival tax. Fewer, larger briefs. **Worth +1.5 to +3.0.**
3. **Price the non-Claude backends.** They are the only lever in the wave that adds capacity instead
   of redistributing it, they are `✅ routable` today, and no axis owns them. Everything else in this
   ladder is a fight over one fixed weekly allowance.

**And the reframe the operator asked for.** They wanted >15 concurrent session-equivalents. At the
measured 0.357 duty cycle, **15 panes is only 5.4 working units** — so "more than 15" was never really
a question about 15. The fleet sustains **8.9** and could reach **~11–12** free. The gap between the
felt ceiling and the real one is not capacity; it is that **17 panes are drawing on a meter that only
one of the four accounts is actually paying.**
