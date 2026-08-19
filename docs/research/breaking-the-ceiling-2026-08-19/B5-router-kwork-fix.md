# B5 — the router is misrouting today. The fix, specified.

Axis of `breaking-the-ceiling-2026-08-19`. Builds on `docs/research/orchestration-units-2026-08-19.md`
(commit `4a3bd3373`) L9 / §"our slot accounting". Everything below is MEASURED on this box today
unless labelled otherwise. Read-only throughout: no live config, transcript, or process was written,
and the patched walk was timed as a standalone replica, never by running a modified `claude-accounts`.

---

## 1 · VERDICT

1. **The inversion is real and it is live right now.** At 13:14Z, 3 visible writers vs **25 invisible**
   (89%); `next` scored `k_work = 0` while 16 workflow-agent transcripts were being appended on it,
   because its lead's own transcript had been idle 801 s — a blocked lead is *silent by construction*
   while its fan-out burns.
2. **But it is a BURST defect, not a sustained one, and the landed doc's headline overstates the
   sustained case.** Replayed over 1,200 active minutes (24 h): deep/shallow ratio-of-means **1.31**,
   median **1.00**, p90 1.67, max 9.33. An account reads 0-while-agents-write on **0.5 %** (`next`) to
   **2.4 %** (`next4`) of active minutes — never 63 %. The 63 %/89 % figures are wave-instant samples.
3. **Semantics: count each nested agent as ONE working unit.** MEASURED per active entity-minute, a
   workflow agent bills **0.66×** a session and a subagent **0.78×** (deduped on `message.id`). So
   "1 each" over-charges by 34 %; today's "0 each" under-charges by 100 % of a burn that is two-thirds
   of a session. The premise that 10 agents "share one session's position in the 5-h window" is false —
   the 5-h limit is a *usage meter*, not a slot list; what they share is an OAuth token and a process,
   neither of which is metered.
4. **The abstain is FAIL-OPEN, and provably so** — the opposite of what the code's own docstring
   claims. On 2,108 paired samples the `k_work` gate would exclude **3.84 %** of rows; the pane-census
   fallback excludes **0.19 %** — a **20× looser** gate, engaged on 21 % of sweeps, preferentially when
   the box is loaded. The concurrency gate switches itself off exactly when it matters.
5. **This buys ~0 session-equivalents of sustained capacity and is still worth shipping.** It is an
   *allocation* fix, not a capacity fix. Its measurable prize: 62/671 sweeps had an account at/over the
   5-h cutoff, and in **62 of 62 (100 %)** another account sat under 40 % at the same instant.

---

## 2 · NUMBERS, WITH THE COMMAND BEHIND EACH

### 2.1 The blindness — what the walk cannot see

| # | Figure | Value | Instrument |
|---|---|---|---|
| N1 | Transcript path shapes under `projects/` | `<slug>/<uuid>.jsonl` **3 365** · `<slug>/<uuid>/subagents/workflows/wf_*/agent-*.jsonl` **2 692** · `<slug>/<uuid>/subagents/agent-*.jsonl` **703** · `…/wf_*/journal.jsonl` **158** | `os.walk` over all 4 config dirs, path-shape normalised (MEASURED) |
| N2 | Depth below `projects/` | agents sit at **3 and 5**; the walk scans **1** | same |
| N3 | Live census 2026-08-19 13:14Z, 10-min window | visible **3** · nested-subagent **0** · nested-wfagent **25** ⇒ **89 % invisible** | replica of `working_concurrency`'s mtime rule + recursion (MEASURED) |
| N4 | Per-account, same instant | `next` 0 visible / 16 invisible · `next4` 0 / 3 · `next2` 2 / 6 · `next3` 1 / 0 | same |
| N5 | Why the lead is silent | parent transcript mtime age while its agents wrote: `next` **801 s**, `next4` **1 398 s** — both outside `KWORK_WINDOW_MIN`=10 min | `os.stat` on `<slug>/<sid>.jsonl` (MEASURED) |

N5 is the mechanism, and it is worse than "agents are in a subdirectory": a lead **blocked on its own
fan-out stops writing**, so the account carrying the most concurrent API streams is the one that scores
most idle. The blindness and the inversion are the same fact.

### 2.2 The sustained magnitude — 24 h replay, three candidate semantics

Replay: every `.jsonl` under all four `projects/` roots with mtime < 24 h old (**179 files, 0.21 GB**,
`journal.jsonl` excluded), per-line `timestamp` parsed into 1-minute bins, then `k_work` recomputed for
each of 1,200 active minutes under a 10-minute window.

| Semantics | fleet mean | median | p90 | max |
|---|---|---|---|---|
| **SHALLOW** — today's code | 4.03 | 3.0 | 7 | 20 |
| **DEEP** — 1 per agent (recommended) | **5.25** | 3.0 | **11** | **32** |
| **COLLAPSED** — 1 per parent session | 4.12 | 3.0 | 8 | 20 |

- `F = deep/shallow`: mean **1.21**, median **1.00**, p90 **1.67**, max **9.33** (n=1,198 minutes).
- Pooled ratio-of-means (the statistic a cap must be rescaled by): **1.312**.
- Minutes where an account reads `k_work=0` while its agents write: `next` 6/1200 (0.5 %) · `next4`
  29/1200 (2.4 %) · `next2` 0 · `next3` 0.
- Minutes where the *idlest-account pick* differs between shallow and deep: **34/1200 = 2.8 %**.
- **COLLAPSED is within 2 % of SHALLOW** (mean 4.12 vs 4.03) — i.e. the "count them as 1" option is
  numerically almost the same as not fixing the bug at all. That alone disqualifies it.

### 2.3 The semantics decision — what a nested agent actually costs

Per active entity-minute, 24 h, **deduped on `message.id`** (repo memory: streamed lines repeat per
content block and inflate 2–3× non-uniformly). Billable weight = `in + 1.25·cache_write + 0.1·cache_read
+ 5·out`.

| kind | messages | active entity-minutes | billable / entity-minute | **relative to a session** |
|---|---|---|---|---|
| session | 6 557 | 2 091 | 105 952 | 1.00 |
| subagent | 406 | 98 | 82 431 | **0.78** |
| wfagent | 2 086 | 676 | 70 456 | **0.66** |

Command: single `os.walk` + `json.loads` per line over 24 h-fresh transcripts, summing `message.usage`
once per unique `message.id`.

### 2.4 The over-refusal risk of shipping the recursion at KMAX=8

Per-account, per active minute, fraction at/over `KMAX`=8:

| acct | shallow ≥8 | deep ≥8 | mean sh | mean dp | p95 sh | p95 dp |
|---|---|---|---|---|---|---|
| next | 0.0 % | 1.5 % | 0.19 | 0.36 | 1 | 1 |
| next2 | 1.3 % | 4.7 % | 1.90 | 2.48 | 4 | 7 |
| next3 | 1.4 % | 1.4 % | 1.15 | 1.21 | 4 | 4 |
| next4 | 0.0 % | 2.6 % | 0.80 | 1.24 | 2 | 5 |

Fleet-pooled exceedance: **0.69 %** today (shallow @8) → **2.54 %** (deep @8) → **1.94 %** (deep @10) →
0.75 % (deep @14).

### 2.5 The abstain — rate, and direction

| # | Figure | Value | Instrument |
|---|---|---|---|
| A1 | `k_work is None` rate, last 24 h | **184/884 rows = 20.8 %**; per sweep 46/221 = **21 %**, identical across all 4 accounts (one walk serves the sweep) | `~/.claude/logs/account-utilization.jsonl`, `k_work`/`k_src` fields |
| A2 | Same over the ledger's full 3-day span | 576/2 684 = **21.5 %**; `k_src` = work 2 108 · panes 432 · unmeasured 144 | same |
| A3 | Abort log lines, last 24 h | **92** — i.e. ~2 calls per recorded sweep, so the *call-level* abstain rate is higher than 21 % and is unrecorded | `grep 'walk exceeded budget' ~/.claude/logs/claude-accounts.log` |
| A4 | Abort log lines by day | 14 / 39 / 64 / 35 / 36 / 75 / 116 / 85 / 52 (Aug 11→19) — **rising** | same |
| A5 | `scanned` at abort | **49 … 1 213** project dirs in 5.0 s ⇒ ~4–100 ms *per dir* against a healthy 0.045 s whole-walk | abort log message text |
| A6 | **Direction of the abstain** | k_work gate would exclude **3.84 %**; pane fallback excludes **0.19 %** ⇒ **FAIL-OPEN, 20×** | 2 108 paired rows where both instruments read |
| A7 | Why | on abstain `k_src` flips to `panes`, and `k_cap()` flips the cap **8 → KMAX_RESIDENT 40** with it. Mean utilisation of its own cap: `k_work/8` = 0.221 vs `k/40` = **0.105** | `bin/claude-accounts:1537-1539`, ledger |
| A8 | Empirical duty cycle | mean `k_work` / mean `k` = 1.77 / 4.18 = **0.42** (n=2 108) — same quantity the landed doc measures as 0.36 (median, n=517 min) | ledger |

**The 73 % in the landed doc is not reproduced and I believe it is stale, not wrong.** `KWORK_BUDGET_S`
was raised 2.0 → 5.0 (comment at `bin/claude-accounts:515`); A6-VERIFY's sample spans the old bound.
Current, on 2,684 ledger rows: **21.5 %**. Use 21 %, not 73 %.

### 2.6 What the misrouting costs

| # | Figure | Value |
|---|---|---|
| C1 | Sweeps with ≥1 account at/over the 5-h cutoff (85 %) | **62 / 671 = 9.2 %** |
| C2 | …of those, another account under 40 % at the same instant | **62 / 62 = 100 %** |
| C3 | Worked example | 2026-08-16T23:33Z — `next3` at **100 %**, while `next` 2 % · `next2` 9 % · `next4` 13 % |
| C4 | Current fleet weekly headroom | next 45 pp · next2 68 pp · next3 89 pp · next4 71 pp = **273 pp of 400 unused** |

C4 is the load-bearing context: the fleet is **not** weekly-quota-bound. What strands capacity is one
account being driven into its 5-h wall while three sit idle — which is precisely the decision `k_work`
exists to make and is currently blind for.

---

## 3 · THE FIX, FILE:LINE

### F1 — recurse the walk. `bin/claude-accounts:588-611`

Replace the inner `os.scandir(slug.path)` block with a bounded `os.walk`:

```python
            try:
                slugs = list(os.scandir(pdir))
            except OSError:
                continue
            for slug in slugs:
                if time.monotonic() > deadline:
                    return _kwork_unmeasured(budget_s, scanned)
                scanned += 1
                if not slug.is_dir(follow_symlinks=False):
                    continue
                # A session's own transcript is <slug>/<sid>.jsonl, but its agents write
                # <slug>/<sid>/subagents/[workflows/wf_*/]agent-*.jsonl — 3 and 5 levels below
                # `projects`, which a one-level scandir cannot reach. MEASURED 2026-08-19: 25 live
                # agent writers invisible against 3 visible, and BOTH accounts running a fan-out
                # scored k_work 0 — a lead blocked on its own agents stops appending (parent mtime
                # 801 s / 1 398 s stale), so the busiest account reads as the idlest.
                # journal.jsonl is the workflow's own bookkeeping, written by the PARENT: counting
                # it would add one phantom burner per workflow run (158 such files on disk).
                for dp, _dn, fnames in os.walk(slug.path, followlinks=False):
                    if time.monotonic() > deadline:
                        return _kwork_unmeasured(budget_s, scanned)
                    for fn in fnames:
                        if not fn.endswith(".jsonl") or fn == "journal.jsonl":
                            continue
                        try:
                            if now - os.lstat(os.path.join(dp, fn)).st_mtime <= window_s:
                                counts[name] += 1
                        except OSError:
                            continue
```

**Walk cost, MEASURED** (standalone replica, 3 trials each, all 4 config dirs):

| walk | files stat'd | wall time | % of the 5.0 s budget |
|---|---|---|---|
| shallow (today) | 3 368 | 0.045 / 0.049 / 0.048 s | 0.97 % |
| **deep (patched)** | **6 921** | **0.150 / 0.162 s / 0.153 s** | **3.2 %** |

+0.10 s absolute, **3.3×** relative. The budget is untouched at 5.0 s — it is already ~30× the healthy
deep walk, and raising it only makes a sick sweep slower.

Also fix the sentence that made this invisible — `bin/claude-accounts:543` currently reads *"active
subagents append to their own `.jsonl` **siblings**"*. They do not; they append to descendants. That
false clause is why the one-level walk read as correct on review.

### F2 — rescale the cap in the same diff. `accounts.json` `.router.KMAX` **8 → 10**

Non-negotiable, and it is the whole "getting this wrong in either direction" risk. `KMAX=8` was
calibrated against the **shallow** instrument (its own note: *"observed 5-6 live sessions"*). Recursion
changes the instrument and leaves the integer — the repo's own *assertion-span-must-equal-its-subject*
defect. Ratio-of-means is **1.312**, so `8 × 1.312 = 10.5 → 10` (round down, conservative).

Deliberately **not** 14. Preserving today's 0.69 % exceedance exactly (which 14 would do) erases the
fix's entire point: the fat right tail of the deep distribution *is* the fan-out burn the shallow
instrument cannot see, and refusing into it is the correct new behaviour. At **KMAX=10, deep**, pooled
exceedance is **1.94 %** — the typical charge keeps its old relation to the cap, and the extra ~1.25 pp
of refusals fall almost entirely on wave-lead minutes.

`bin/cc-wave-plan` needs **no change**: `ssot_kmax()` (line 447) reads `.router.KMAX` from the same
SSOT file, and its jq reads `.k_work` straight off `--json`. Both new values flow through.

### F3 — the semantics: ONE unit per agent. Decided, with its falsifier

**Decision: DEEP, weight 1.0 per nested agent. Not COLLAPSED, not a fractional weight.**

Reasoning, in the order that decides it:

1. **Both things `KMAX` protects scale per-agent.** (a) The per-account concurrent-request infra
   limiter — each agent holds its own in-flight request. (b) The 5-h and weekly meters, which are
   *usage* meters. There is no "position in the window" for 10 agents to share; the shared objects are
   an OAuth token and an OS process, and neither is metered. The counter-premise is false at the
   mechanism level, not merely inaccurate.
2. **Measured cost says the true weight is 0.66–0.78, i.e. same order as a session** (§2.3). Choosing
   1.0 is a **34 %** over-charge. Choosing 0 — today — is a **100 %** under-charge of a burn that is
   two-thirds of a full session. The error from 1.0 is 3× smaller and points the safe way: over-charging
   a real burner costs a routing detour; under-charging it causes the pile-on the operator reported.
3. **A fractional weight (0.7) is rejected on maintenance grounds, not accuracy grounds.** It puts a
   float into an integer cap comparison, and it is a magic constant calibrated to today's agent mix that
   will rot silently as that mix changes (repo memory: *control calibrated to implementation decays*).
   The integer count plus one rescaled cap carries the same information and cannot drift apart.
4. **COLLAPSED is disqualified empirically, not by argument**: mean 4.12 vs shallow's 4.03 (§2.2). It
   is within 2 % of shipping nothing, while costing the same walk. It also gets the live case exactly
   backwards — it would score `next` as 1 while 16 streams ran.

**What would falsify this choice.** Regress each account's weekly-meter slope (`Δweekly_pct / Δt` from
`account-utilization.jsonl`) against DEEP `k_work` and against SHALLOW `k_work` over ≥5 account-windows,
and compare the per-unit slope in *fan-out* minutes vs *no-fan-out* minutes:

- if %/day-per-unit under DEEP is materially **lower during fan-outs** than outside them ⇒ DEEP
  over-counts, and the weight should drop toward the measured 0.66;
- if it is materially **higher** ⇒ even 1.0 under-counts, and `KMAX` should be rescaled by more than
  1.312;
- if it is flat across both regimes ⇒ DEEP at 1.0 is the right unit and the rescale is complete.

I could not run this today: see §4.

**One consequence to state loudly.** The landed doc's **9.4 sustainable working units** was derived as
`allowance ÷ (weekly slope ÷ mean k_work)` on the *shallow* `k_work`. Multiply mean `k_work` by 1.312
and the per-unit slope divides by 1.312, so the same physical work re-denominates to **≈12.3 deep
working units**. **No capacity is created.** Any future comparison of that 9.4 against a post-fix
`k_work` reading is a unit error.

### F4 — the abstain: fix the DIRECTION, then the rate. `bin/claude-accounts:519-534`, `1487-1493`, `1537-1539`

**What the code does on abstain, exactly:** `working_concurrency` returns `None` → every row gets
`k_work = None` (`:1207`) → `k_eff` charges `r["k"]`, the pane census (`:1488-1489`) → `k_src` returns
`"panes"` (`:1552`) → **`k_cap` returns `KMAX_RESIDENT`=40 instead of `KMAX`=8** (`:1537-1539`).

**It is fail-OPEN** (A6: 3.84 % → 0.19 % exclusion, 20× looser). The docstring's *"absence degrades to
the stricter count, never to zero"* was true when both instruments were compared against the same
`KMAX`=8, and became **false on 2026-08-13** when the `KMAX_RESIDENT` split landed. The *count* is
indeed stricter; the *gate* is not, because the cap moved with it. That is a textbook instance of the
repo's own **"a gate default decides the failure direction"** — and the suite pins the new direction
deliberately at `tests/claude-accounts-core.bats:1657` (`k=KMAX, k_work=None` ⇒ **not** excluded, "the
33rd-session wall is back"). So the resident wall must be preserved; the active gate must be *added
back*, not swapped in.

Three changes, in order of value:

- **F4a — restore an ACTIVE gate on the fallback path.** Keep `KMAX_RESIDENT` exactly as-is for the
  resident question, and additionally refuse when `k × duty ≥ KMAX_active`, with duty = **0.42**
  (measured, n=2 108; the landed doc's 0.36 median is the same quantity by a different estimator — use
  the larger, and it is the conservative one for a refusal). Sanity check: `4.18 × 0.42 = 1.76` against
  a measured mean `k_work` of **1.77** — the duty-scaled pane census is a calibrated stand-in, not a
  guess. This is the single change that stops the concurrency gate from switching itself off under load.
- **F4b — make the abstain PARTIAL, not total.** Today a timeout discards everything already counted,
  because *"a partial count reads as 'nothing working', which is the dangerous direction"* (`:548-551`).
  That is true **only if the partial count is used alone.** A partial count is a valid **lower bound**;
  so is the duty-scaled census; `max()` of two lower bounds is still a lower bound and can never
  over-refuse beyond what either justifies. Return `(counts, partial=True)` and charge
  `max(partial_k_work, round(k × duty))`. This converts a 21 % total blackout into a 21 % degraded-but-
  present reading, and it is what keeps F1 from making things worse (F1 triples the stat count on the
  exact path that is already timing out).
- **F4c — surface it.** `_kwork_unmeasured` logs to `claude-accounts.log`; the *utilisation ledger*
  already records `k_src`, but nothing counts abstains over time. A4 shows the rate roughly **quadrupled
  in 8 days** (14 → 116/day) and nobody noticed. Emit `kwork_abstain_rate_24h` on `--readout`, or the
  next regression is invisible the same way.

**Not recommended: raising `KWORK_BUDGET_S`.** 5.0 s is already ~30× the healthy deep walk; A5 shows
aborts at 49 dirs, i.e. ~100 ms per directory. That is filesystem stall, not walk size, and a bigger
budget only lengthens a sweep that is already the slow path.

---

## 4 · WHAT I COULD NOT MEASURE, AND WHY

1. **The falsifier in F3.** Regressing weekly-meter slope on DEEP vs SHALLOW `k_work` needs ≥5 clean
   account-windows with a fan-out/no-fan-out contrast. The utilisation ledger only starts
   **2026-08-16T10:26Z** (2 684 rows) and the transcript replay is bounded by disk retention, so the two
   series overlap by ~3 days — enough for the ratio-of-means in §2.2, not enough to separate the
   regimes. Re-run in ~10 days.
2. **The per-account concurrent-request limiter band (5-6, GH#62426)** is QUOTED from the landed doc,
   not re-measured. Probing it would mean deliberately driving an account into refusal — a write to the
   live fleet, out of scope.
3. **Causality between misrouting and the 62 five-hour cutoffs (C1/C2)** is not established. The
   correlation is perfect (62/62) and the mechanism is plausible, but I cannot exclude that some cutoffs
   were operator-directed work on a chosen account.
4. **The patched code was not executed.** The 0.150 s figure is a standalone replica of the proposed
   walk over the same four roots, not `bin/claude-accounts` with F1 applied. Timing the real binary
   means running a sweep, which writes `account-utilization.jsonl` and `claude-accounts-lastgood.json`.
5. **The true call-level abstain rate** (A3: 92 log lines vs 46 ledger-recorded sweeps) is unknown,
   because non-sweep callers of `working_concurrency` write no ledger row. 21 % is a floor.
6. **The 24 h replay window contains an unusually large fan-out** (this wave). The tail statistics
   (p90 1.67, max 9.33) may be over-represented; the ratio-of-means 1.312 over 1,200 minutes is the
   robust figure and is what F2 is sized on.

---

## 5 · THE DECISION THIS AXIS CHANGES

**It does not raise the ceiling. It stops us aiming a wave at the account already carrying it.**

Quantified honestly:

- **Sustained session-equivalents bought: ≈ 0.3, and possibly 0.** The fleet holds 273 pp of unused
  weekly quota across four accounts (C4), so weekly quota is not binding. The loss this fixes is the
  5-h cutoff firing on one account while others idle: 9.2 % of sweeps, during which the routable fleet
  is 3 accounts instead of 4. Perfect spreading recovers at most `9.2 % × 1/3 ≈ 3 %` of the settled
  **9.4** sustainable working units ⇒ **≈ +0.3**. Anyone selling this as a capacity lever is selling a
  unit error (§F3, final paragraph).
- **Burst: this is where it pays.** MEASURED live, `next` read `k_work = 0` while running 16 concurrent
  agent streams. `cc-wave-plan`'s allowance is `min(URGENT_PER_ACCT, KMAX − k_eff)`, so that account was
  offered a head of **8** when the truthful head was **0** (floored). That is the maximum possible
  misrouting: the widest allowance handed to the most saturated account. It cannot happen after F1.
- **Ordering: the router picks the wrong idlest account 2.8 % of active minutes** — but conditional on
  an account running a fan-out, it is near-certain, and a fan-out is exactly when a fire happens.

**Ship order:** F1 + F2 in one diff (recursion without the rescale is a silent tightening; rescale
without recursion is a silent loosening), F4b with them (F1 triples the stat count on the path that
already times out 21 % of the time), then F4a, then F4c.

---

## 6 · RISK — what over-refusal looks like, and how we notice

**Symptom chain.** `_excluded` returns `kmax-concurrency` → `claude-accounts --route` exits rc 2 →
`handoff-fire.sh` **HALTS** rather than falling back. At fleet scale that is a wave lead firing four
items and four refusing, with no work started and no error the operator sees except a stalled wave.

**Predicted magnitude, so a deviation is legible.** Pooled per-account-minute exceedance goes
**0.69 % → 1.94 %** (deep @ KMAX=10). Refusals roughly triple in relative terms and stay under 2 % in
absolute terms. **> 4 % sustained means F2's rescale is too tight** — raise `KMAX` toward 12 (1.29 %) or
14 (0.75 %), which is a one-key edit in `accounts.json` and needs no code change. That is the intended
escape hatch, and it is why F2 lives in the SSOT and not in code.

**How we notice — three sensors, two of which already exist:**

| Sensor | Status | The query |
|---|---|---|
| `account-utilization.jsonl` `k_work`/`k_src` per sweep | **exists** | exceedance rate at `KMAX` before vs after; the pre-fix baselines are in §2.4 |
| `route-meta` `k_src=` / `k_work=` / `kwork_to=` per decision (`:4394-4399`) | **exists** | per-decision instrument + charge, answerable from disk after the fact |
| **Over-refusal tripwire** | **MISSING — ship it with the change** | log when a row is excluded `kmax-concurrency` **while its own `session_pct` < 43 %** (half of `S_CUT`). Refused for concurrency while its actual meter says half-idle is the exact signature of an over-tight cap, and today it is unobservable |

**The alarm-polarity check** (repo memory: an always-firing alarm says as little as one that cannot).
The tripwire's expected rate at KMAX=10 is near zero — an account at ≥10 working units is not at 43 %
of its 5-h window in normal operation. If it fires more than a handful of times a day, that IS the
signal, not noise.

**The failure mode I am NOT worried about, and why.** Under-refusal after the fix is impossible by
construction on the measured path: DEEP `k_work` ≥ SHALLOW `k_work` for every minute of the 1,200-minute
replay (it is a superset count), so no account can be admitted after the fix that would have been
refused before it. All the new risk is on the refusal side, and it is bounded by one integer in one JSON
file.
