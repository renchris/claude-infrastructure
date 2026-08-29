# Marginal load per ACTIVE session — the four published values cannot be repaired, and the instrument that produced them cannot measure the quantity

**Date:** 2026-08-19 · **Item:** backlog `193ae8ddce72`
**DoD ref:** [`gc-cpu-vs-session-ceiling-2026-08-18.md`](gc-cpu-vs-session-ceiling-2026-08-18.md) §5
**Ships:** `scripts/capacity-marginal.sh` · `tests/capacity-marginal.bats` (15 rows)

---

## 1 · Verdict

**The number is still unmeasured, and this is the wave that says why the archive cannot supply it.**
The four published values are not four estimates of one quantity that could be averaged, reconciled
or ranked. Three are arithmetically disqualified and the fourth pair has no committed derivation at
all — and all four were produced by an instrument (`load1` against session count) that trunk has
already measured as **unidentified on this box**. So there was never a number to recover, and the
deliverable this item can honestly close on is the instrument that *can* answer, carrying the
control the DoD named, **proven able to fail**.

1. **No coefficient is asserted here.** The measurement needs the live 10-core Darwin fleet; it was
   built and verified off-box. §6 is the run, and it is ~30 minutes of wall clock on the box with no
   operator judgment in it.
2. **The naive fit is not merely noisy, it is unidentified.** B3 attributed 87.3% of the load
   numerator to things that are not Claude, moving across load1 **8.35 → 46.39 in one day**; A8 ran
   the whole-box Δload probe and watched the load *fall* while a unit was added. A regression of
   load1 on session count has 3× more variance in its confounder than in its treatment. It will
   always return something. That is where `0.172` and `0.566` come from.
3. **The fix is to fit on the attributed series, not the box.** `capacity-marginal.sh` regresses the
   **Claude-owned** runnable census on the **ACTIVE** (mid-turn) count, then converts to load units
   with a ratio the *same window* measures — and prints the naive pooled slope beside it, labelled
   unidentified, so the two can never again be mistaken for each other. On a planted-coefficient
   fixture the two disagree by 23% in the same window (`0.333` recovered vs `0.257` naive, planted
   `0.325`).
4. **The control is the product; the coefficient is the by-product.** Three controls, all three
   required, each able to fail for its own reason, each with a test that watches it do so — starting
   with a replay of the exact census shape (flat 19–20 across a 2.2× load range) that killed this
   wave's own "64% is our own automation" headline.

---

## 2 · The four values, adjudicated

| value | stated method | what is actually wrong | repairable from the archive? |
|---|---|---|---|
| **2.5–5** | published, quoted into `capacity-admit.sh:698` and `agent-teams-enforce.sh:220` | **A ratio, not a marginal** — an aggregate ÷ N. Already refuted in the DoD. Its own source pair (load1 27.4 → 44.4 at 9 all-active) gives 1.89, not 2.5–5. | **No** — the arithmetic is the defect. |
| **1.89** | `(44.4 − 27.4) / 9` | A **two-point delta**. n = 2 ⇒ no control is *computable*, let alone passable; and the 9 sessions arrived together with the instrument that measured them. | **No** — a control needs a series. |
| **0.172** | "pooled OLS" | **No committed derivation exists on trunk** (grep: the only occurrence in the repo is the DoD line listing it). Pooled ⇒ dominated by the ambient confounder (§3). | **No** — unauditable *and* unidentified. |
| **0.566** | "in-band bucket median" | Same: no committed derivation. Bucketing narrows the load range, which *weakens* identification rather than fixing it. | **No** — same two reasons. |

**The 30× span is therefore not disagreement between measurements. It is four different quantities,
two of which cannot be re-derived.** Any future citation of one of them is a citation of nothing;
`capacity-admit.sh:698` and `hooks/agent-teams-enforce.sh:220` both currently quote the 2.5–5 row and
should be updated to the measured value once §6 has been run — **not** before, and not to one of the
other three.

---

## 3 · Why `load1 ~ N` cannot answer this on this box

Two independent trunk measurements, both from 2026-08-19, both stronger than anything this axis could
add:

- **The confounder is 87.3% of the signal and has 3× the range.**
  `breaking-the-ceiling-2026-08-19/B3-ambient-load.md` §2a: a 240-sample per-thread census with full
  ancestry attribution puts **Claude sessions and everything they spawn at 12.7%** of the load
  numerator (`claude.exe` alone: 4.2%); macOS/third-party is 33.6% and **our own automation 25.9%**,
  with `cc-backlog` alone at 17.5% of the whole box. Load1 spanned **8.35 → 46.39 on one day**.
- **The direct probe returns the wrong sign.**
  `orchestration-units-2026-08-19/A8-marginal-cost.md` §6.1: mean load 28.96 baseline → **26.75
  during** the added unit → 25.81 after; a second run read 19.40 → **35.58 with the probe already
  dead**. Verbatim: *"Any single-unit cost derived from `uptime` on this box is measuring the
  fleet."*

A pooled fit under those conditions is not a weak estimate of the marginal — it is an estimate of
whatever the ambient was doing while the session count happened to move. It has no null: it returns a
finite slope from pure noise. This is the generator of the 30× span, and it is why the sampler fits
the attributed series instead.

---

## 4 · The instrument

`scripts/capacity-marginal.sh sample | analyze`. One TSV row per sample:

```
#ts   load1   unit   total_run   claude_run   active   resident
```

- **`load1`** — `sysctl -n vm.loadavg` (Darwin) / `/proc/loadavg` (Linux). Unreadable ⇒ the row is
  dropped, never recorded as 0.
- **`total_run` / `claude_run`** — one `ps -axo pid=,ppid=,stat=,comm=`; a process is runnable when
  STAT begins `R`/`D`/`U`, and **Claude-owned when it or any ancestor's `comm` matches the launcher's
  executable path** (bounded 32-hop walk). The ancestor walk is load-bearing: B3 measured a session's
  `jq`/hook/MCP forks at ~3× `claude.exe`'s own contribution, so attributing only the launcher
  process undercounts Claude by two thirds.
- **`active`** — `cc_sp_active` from `scripts/lib/spawn-presence.sh`, the repo's one definition of
  mid-turn, and the population `CC_ADMIT_ACTIVE_CEILING=8` is denominated in. It is a **proven lower
  bound**, so the coefficient it yields is an **upper** bound on cost per active session. Unmeasurable
  records `-`, never 0 — a dead sensor must not read as a quiet box.
- **`resident`** — counted by **`comm` (executable path), never argv**, per the DoD: argv reads 30–33
  against a true 15–16 because session briefs quote the interpreter path.
- **`unit`** — `proc`. The **thread**-level census reproduces load better (B3: ratio 0.913 vs the
  process census's 1.30–1.55), but Darwin's `ps -axM` needs a parser this repo has no captured
  fixture to test against, and an untested parser inside a control is how a control becomes
  decorative. C1 *measures* the ratio rather than assuming one, so the coarser unit costs accuracy in
  the ratio, never validity in the verdict. `analyze` refuses a file whose rows mix units.

### The three controls

| | asks | passes when | default |
|---|---|---|---|
| **C1 LEVEL** | does the census reproduce the load it apportions, **at more than one load**? | load/census ratios computed in **load tertiles** agree within `CC_MARG_RATIO_TOL`, over a window spanning ≥ `CC_MARG_MIN_LOAD_SPREAD` | 1.35× · 1.5× |
| **C2 DYNAMICS** | does the census **move** when the load moves? | `corr(load1, census) ≥ CC_MARG_MIN_R` over **`n_eff` ≥ `CC_MARG_MIN_N` independent** observations | 0.30 · 20 |
| **C3 IDENTIFY** | did the regressor vary? | the ACTIVE count spans ≥ `CC_MARG_MIN_ACTIVE_SPREAD` across ≥ `CC_MARG_MIN_ACTIVE_LEVELS` distinct levels | 2 · 3 |

**Why tertiles and not one ratio (C1).** A8's `×1.553` R-procs→load factor was fitted at one point;
B3 reproduced it in none of three windows (0.913 / 1.077 / 1.235) and killed every absolute derived
from it. A ratio that has only ever been computed once is a fudge factor. C1 also **fails a window
that never moved** — a ratio agreeing across three identical loads has reproduced nothing.

**Why `n_eff` and not `n` (C2).** `load1` is a 60 s moving average, so two samples 5 s apart are one
observation of it read twice. `n_eff = span/τ + 1`, capped at `n`. This is exactly the arithmetic
that left B3's own dynamics control **undecided rather than refuting**: its windows were 2.5–4 min,
≈2.5 independent observations, so its negative correlations carried no information. The sampler
refuses that window instead of reporting from it.

**Why 3 levels and not 2 (C3).** A two-level fit *is* the 1.89 defect. A one-level fit is division by
zero wearing a decimal point.

**All three, or nothing.** Any failure ⇒ `NO-ATTRIBUTION`, exit 1, naming the term that failed. The
fit that *would* have been reported is printed in parentheses and explicitly marked withheld, and the
string `VERDICT: MARGINAL` never appears — so a grep for a quotable number over a failed window
returns nothing. Exit codes: **0** coefficient · **1** control failed · **2** usage · **3** NO-DATA.

---

## 5 · The proof the control can fail

A control nobody has watched fail is a rubber stamp. `tests/capacity-marginal.bats` — 15 rows, green:

| test | what it pins |
|---|---|
| **POSITIVE CONTROL** | The census shape that killed this wave's own headline — flat 19–20 across a 2.2× load range, **at 60 s spacing so `n_eff` is not the reason** — is REFUSED, by C2, naming the correlation. |
| **NEGATIVE CONTROL** | A planted 0.25 runnable-procs-per-active-session against a moving ambient is **recovered as 0.333 load units** (planted 0.325, within 5%) with all three controls PASS. Without this, a refusal proves nothing. |
| C2 uninformative | Near-perfect correlation at 5 s spacing is still refused — `n_eff` 4.25 < 20, worded *"uninformative, not refuting"* (B3's defect, by name). |
| C2 constant | A census constant across a 1.5× load range is named *"the instrument, not the box"*. |
| C1 drift | A census that tracks load's **rank** perfectly (C2 PASS) but whose ratio drifts 2× across tertiles is refused by C1 alone — the `×1.553` defect. |
| C1 quiet | A window that never moved fails C1 rather than certifying a vacuous ratio. |
| C3 flat / C3 blind | One active level ⇒ FAIL; zero measurable rows ⇒ FAIL *stating how many were blind*, never coerced to 0. |
| no quotable number | On a refusal, `VERDICT: MARGINAL` is absent and the withheld fit is labelled withheld. |
| mixed units | Pooling a proc census with a thread census is NO-DATA — their ratios differ by 40% and C1 would certify the average of two wrongs. |
| attribution | A fixed process table with a session, its `jq`/`ugrep` descendants, an idle session's `D`-state child, kitty and `mediaanalysisd` resolves to exactly `6 4 2`. |
| comm-not-argv | The source's `ps` invocation contains `comm=` and not `args=`. An edit swapping them would double the denominator of every capacity claim and change no other test. |

---

## 6 · The run — what remains, and it is not a judgment call

On the box, in a session that is not itself doing heavy work (the sampler costs one `ps` per minute):

```sh
bash scripts/capacity-marginal.sh sample --window-s 3600 --interval-s 60 --out /tmp/marg.tsv
bash scripts/capacity-marginal.sh analyze --in /tmp/marg.tsv
```

**One hour at 60 s gives `n_eff` = 60 against a floor of 20**, so C2 is decidable rather than
undecided — the single thing B3's three windows could not buy. Two conditions make C1 and C3
decidable too, and both are ordinary operating conditions on this box rather than an intervention:

- **C1 needs the load to move ≥1.5×.** Measured range on an ordinary day is 8.35 → 46.39, so an hour
  will normally clear this; a dead-quiet hour will correctly refuse.
- **C3 needs the ACTIVE count at ≥3 distinct levels.** The DoD asks for *"N≥5 at different
  baselines"* and a continuous window is the cheaper spelling of the same design: a dispatch wave
  moves `cc_sp_active` through several levels on its own. If an hour lands on one level, run the
  window across a wave rather than during a lull — **do not** synthesise levels by pausing the box.

`analyze` is re-runnable over a growing file, so the honest protocol is: sample, analyze, and extend
the window until the verdict stops being `NO-ATTRIBUTION` **or** the refusal repeats with the same
term across several windows — which would itself be the finding (the process-unit census is not the
right instrument, and the thread-unit refinement in §7 becomes the next increment rather than a
nicety).

On a PASS, quote the coefficient **with its standard error and its window**, update
`scripts/lib/capacity-admit.sh:698` and `hooks/agent-teams-enforce.sh:220` (both currently carry
2.5–5), and close `193ae8ddce72` with the landed sha.

### 6a · The ban is now enforced in code — and there were THREE sites, not two (2026-08-26)

The paragraph above splits this item cleanly in half, and only one half needs the box. The other
half — §1's *"none of the four may be quoted"* — was **in force on trunk and violated by trunk**,
and has now been discharged off-box. What landed:

| site | what it said | what it says now |
|---|---|---|
| `scripts/lib/capacity-admit.sh` | *"Axis 09: 2.5-5 runnable threads per genuinely-ACTIVE session … ⇒ ~4-8 concurrent actives"* — the stated derivation of `CC_ADMIT_ACTIVE_CEILING=8` | the figure struck and labelled REFUTED with a pointer here; the ~4-8 band **retained on its surviving footing** |
| `hooks/agent-teams-enforce.sh` | the same figure inside the **runtime `permissionDecisionReason`** string | same, in the deny message itself |
| **`scripts/lib/spawn-presence.sh`** § THE ACTIVE POPULATION | the same figure, **and this doc did not know it existed** | same |

**The third site is the finding.** §2 and §6 both name two sites; a `grep` over live code (excluding
`docs/`) returns three. `spawn-presence.sh` is the library that *defines* `cc_sp_active` — the
population the coefficient is denominated in and that both other sites consume — so the refuted
figure was resident in the census's own header, one level below the two places anyone was told to
look. A ban enumerated as a list of paths is a denylist of spellings, and this repo already has that
lesson written down in `bin/cc-eligible`. **Re-grep at the PASS, do not work from this table.**

**Nothing was substituted**, per the rule above: no site now carries 0.172, 0.566, 1.89 or 2.5–5.
The ceiling is left standing on the one anchor the adjudication does not touch — **127/127 historic
gate refusals landing at ~4-8 concurrent actives**, a count over refusals rather than a division by
a per-session coefficient. That matters for sequencing: `CC_ADMIT_ACTIVE_CEILING=8` is **not blocked
on §6**, so the measurement can take as long as it needs without leaving a gate justified by a
number its own source pair refutes.

**What remains is exactly §6 and nothing else** — one ~1 h window on the 10-core Darwin box during a
dispatch wave, then the update-and-close. Verified this session, off-box: `bats
tests/capacity-marginal.bats` **15/15**, plus `tests/agent-teams-enforce.bats` and
`tests/capacity-admit-active.bats` green alongside them (61/61 total), `shellcheck` clean,
`test-hermeticity-lint.sh` clean (551 suites, 0 new leaks), and the sampler smoke-run on Linux
correctly refusing a 60 s quiet window — `C1 FAIL` (tertile swing 1.56× > 1.35×), `C2 FAIL`
(`n_eff` 1.8 < 20, worded *uninformative, not refuting*), `C3 FAIL` (0 rows carry an ACTIVE count,
6 unmeasurable), `VERDICT: NO-ATTRIBUTION`, exit 1, withheld fit labelled withheld. The instrument
is ready; only the fleet is missing.

### 6b · §6 was a protocol, not a recipe — and the adjudication in it is now code (2026-08-29)

§6 above is two commands and three paragraphs, and the paragraphs contain a **loop, a stop rule and
an adjudication** that were left for a person to execute at 1 h per iteration while remembering
which term failed last time. A recipe a human has to interpret is a worksheet, and making the human
the interpreter is the defect (global CLAUDE.md § Manual-Command Delivery). **`scripts/capacity-marginal-run.sh`
is the interpreter.** One command, resumable, walk away:

```sh
bash scripts/capacity-marginal-run.sh                  # 6 x 1 h windows into $TMPDIR/capacity-marginal.tsv
```

**The stop rule is not "did it fail again", and that is the whole reason this needed writing.** §6
says "the same TERM", and the terms are not interchangeable — two of the three controls fail for a
reason about the BOX that self-resolves, and for a reason about the INSTRUMENT that never will. So
every refusal is reduced to a per-control reason token taken from the analyzer's own why-string,
and only an **instrument** term earns §6's second exit:

| | terms | what a repeat means |
|---|---|---|
| **INSTRUMENT** → exit 1, §6's finding | `C1:swing` (the ×1.553 single-point-fit defect, live) · `C2:corr` (the census does not track the load it apportions — the "64% is our own automation" cause of death) · `C2:constant` ("the instrument, not the box") | more hours cannot fix it; §7.3's thread unit is the next increment, and the run prints the `cc-backlog add` for it |
| **CONDITION** → exit 3, keep extending | `C1:span` (a quiet hour) · `C2:neff` (n_eff = span/τ + 1, so this ALWAYS clears given wall clock — "uninformative, not refuting") · `C3:flat` (a lull; §6's remedy is to run ACROSS A DISPATCH WAVE, never to synthesise levels by pausing the box) · `C3:blind` | a report about the hour you chose, not about the census |

An **unrecognised** why-string counts as an instrument term on purpose: the safe side of "I cannot
tell" is to stop and make a human read it, never to keep burning hours on a refusal whose meaning
the driver has silently lost. Calling a quiet box an instrument failure would be this wave's own
original sin — an instrument that always answers — wearing the opposite sign, which is why the
condition/instrument split is asserted in both directions rather than assumed.

Two properties are inherited and pinned rather than hoped for. **No coefficient escapes a failed
control:** every non-PASS exit is asserted to print no number of its own and to leave the withheld
fit labelled withheld — the leak that put four values spanning 30× in the archive. **The tokens are
pinned against the REAL analyzer**, over fixtures engineered to produce each why-string, so a
reworded string fails a test instead of collapsing every signature to `:other` and turning the stop
rule back into "it failed again". On a PASS the handover prints the **re-grep**, never the two known
paths — §6a's own finding was that the ban enumerated two sites and a grep found three.

Verified off-box (Linux container, no fleet): `bats tests/capacity-marginal-run.bats` **15/15** and
`tests/capacity-marginal.bats` **15/15** (30/30 together), `shellcheck` clean on the driver and the
suite, `bash -n` clean, `gate-select.sh lint` clean, `test-hermeticity-lint.sh` clean (554 suites,
0 new leaks), `bats-testname-eval-lint` / `bats-kill-guard-lint` / `test-walltime-lint` clean, and
the driver end-to-end against the real sampler on this host — a 2 s window correctly reaching
NO-DATA and quoting nothing. **§6's run still needs the box; nothing here measures a coefficient.**

### 6c · The run's own first statement was untested, and the item is now operator-gated (2026-08-29)

Two things closed this item's off-box half for good, and neither of them is a coefficient.

**The Darwin arm of `read_load1` was unreachable, not merely uncovered.** Every row §6's run records
begins there, and the reader has two branches: `/proc/loadavg` on Linux, `sysctl -n vm.loadavg` on
Darwin. `/proc/loadavg` is readable on every host this corpus runs on, so the first branch always won
the `if` and **no test could enter the second** — which is the only branch the remaining run
executes, and the only platform-specific parsing in the file. Darwin prints `{ 1.23 4.56 7.89 }`, so
the value is field **two**; reading field one takes the brace, fails the numeric guard, and drops
*every* row. The visible result of that would be the driver exiting 3 with *"the sampler recorded
nothing"* after burning the first hour of the one command whose whole promise is walk-away. This is
§4's own `ps -axM` lesson — *an untested parser inside a control is how a control becomes
decorative* — aimed at the reader instead of the census, and `CC_MARG_PS_OVERRIDE` already existed to
prevent exactly it for the attribution walk while the load reader had no equivalent seam.
`CC_MARG_PROC_LOADAVG` is that seam (default `/proc/loadavg`, unchanged on the box, and the default
is itself pinned by a test so a hook can never silently redirect what the sampler reads). Three rows
now exercise the real function: the `{ … }` format parses to field 2; an erroring `sysctl` and a
non-numeric answer are both **refused** rather than coerced to a load of 0, per §4's *"a zero load is
a measurement, an unreadable one is not"*. RED-proved by mutating the parse to field 1 — the format
row fails and no other test moves. Suites: **18/18 + 15/15**.

**What remains is operator-only, and is recorded here because a cloud VM has no other channel.**
The instrument is ready and nothing off-box can advance the item further: §6 needs macOS, the
10-core box, and a live dispatch wave (C3 wants the ACTIVE count at ≥3 levels, and §6 forbids
synthesising them by pausing the box). One command, resumable, walk away:

```sh
bash scripts/capacity-marginal-run.sh
```

Note for whoever dispatches this next: `cc-backlog block 193ae8ddce72` **exits 0 without doing
anything** from a cloud VM — the store is `~/.claude/autonomy/backlog.jsonl`, which exists only on
the operator's box (`cloud-land-arm-step-2026-08-25.md` §6.6, and `cc-notify --role desk` fails the
same way). So the park is not expressible in the ledger from here and is expressed in this
paragraph instead. **Re-dispatching this item to a cloud worker cannot advance it**; it needs the
box, and then the close-out the driver prints on PASS.

---

## 7 · What this does not do

1. **It measures no number today.** Off-box: no Darwin, no fleet. Everything above is the
   instrument and its controls, verified against fixtures.
2. **It is observational, not experimental.** The slope is a within-window association between the
   attributed census and the active count, not a randomised effect of adding a session. It is
   strictly weaker than the DoD's "fire ONE session at a held-constant baseline" arm — and strictly
   stronger than any of the four values, because that arm yields `n_eff` = 2 per pair and cannot
   clear C2 at all without ≥5 pairs. Run the paired arm as confirmation *after* the observational
   coefficient exists, never instead of it.
3. **Process unit, not thread unit.** §4. The ratio is measured, not assumed, so this bounds the
   error rather than hiding it — but B3's thread census is the better instrument and wants a captured
   `ps -axM` fixture before its parser can be tested and shipped.
4. **`cc_sp_active` is a lower bound**, so the coefficient is an upper bound on per-active-session
   cost. That is the correct direction for a ceiling constant and the wrong one for a "+N sessions"
   projection; do not invert it.
5. **`kernel_task` remains invisible** to `ps` (~720 threads; B3 §2e). It lives inside C1's ratio
   residual and is attributable to nobody.
6. **A passing control does not make the coefficient causal.** It makes it *quotable*: an
   apportionment whose census demonstrably tracks the quantity it apportions, over enough independent
   observations to tell. That is the bar the DoD set, and it is the bar nothing in this repo has met
   before.

---

## 8 · Provenance

Built and verified off-box (Linux container, no fleet): `bats tests/capacity-marginal.bats` 15/15
green · `shellcheck` clean · `bash -n` clean · `scripts/test-hermeticity-lint.sh` clean (516 suites,
0 new leaks) · sampler smoke-run end-to-end on the host it was written on, correctly refusing a
9-second quiet window with all three controls FAIL. Trunk evidence read at
`origin/main` = `ec43e046`.
