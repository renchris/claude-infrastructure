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
bash scripts/capacity-marginal.sh run --total-s 3600 --chunk-s 600 --interval-s 60
```

*(`run` is new in §6b and is now the invocation. The two-command form below still works and is what
`run` drives; it is kept because the analyzer must stay callable against a fixture file rather than
a machine, which is what every control test depends on.)*

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
is ready; only the fleet is missing. *(Counts are as of 2026-08-26; §6b below carries the current
ones. Its conclusion — §6 and nothing else — is unchanged.)*

---

### 6b · One defect the three controls structurally cannot catch, and the protocol driven (2026-08-28)

§6a discharged the half of this item that did not need the box. This is the last off-box increment:
the remaining half is one operator hour on a 10-core Darwin box, and that hour is the scarcest input
in the whole measurement. Two things were spending it, and both are now gone.

**1 · The width defect — and why it is a control problem, not hygiene.** `census_row` read
`ps -axo pid=,ppid=,stat=,comm=`. macOS `ps` renders a row only as wide as the terminal and falls
back to 79 columns when no fd is a tty, which is the case inside `$(...)`. Those three columns cost
~17 characters before `comm` begins, and the launcher image on this box is
`/Users/chrisren/.claude-220/node_modules/@anthropic-ai/claude-code/bin/claude.exe` — 81 characters,
so the row is ~98 and the tail is cut. `CC_MARG_EXEC_RE`'s second alternative, `claude\.exe$`, is
END-ANCHORED, so a cut tail silently un-attributes every process that alternative is the only match
for. The read is now `ps -axwwo` (`-ewwo` on the Linux fallback).

**Why this one outranks its two siblings.** The repo has fixed this defect's near relative twice —
`compressor-sentinel.sh:465` (*"`ps` gives a column its FULL value only when that column is LAST"*,
16-character truncation, measured 2026-08-11) and `cc-reaper:2396` (*"it read 0 matches where the
per-pid form read 6"*). Both of those are **loud**: a census that reads zero gets investigated. This
one is **silent, and silent specifically past the controls**. C1, C2 and C3 are all computed on
`total_run` — the ratio it reproduces, the correlation it carries, the regressor's spread.
The coefficient is fit on `claude_run`. Truncation moves processes out of `claude_run` without
touching `total_run`, so **every control still passes and `VERDICT: MARGINAL` still prints**, low by
however many rows were cut. A wrong number wearing this instrument's certificate is the exact
artifact the item exists to prevent, and it would have been the fifth unrepairable value rather than
the first measured one.

⚠️ **Stated at its true epistemic weight:** the *line-width* truncation is documented macOS `ps`
behaviour and is the mechanism both siblings guard with `ww`, but it was **not measured for this
invocation** — that needs the box, which is the thing this session does not have. The widening is
free on both dialects and removes the risk either way, so it is taken rather than filed. What does
**not** depend on the box is the second paragraph: the blindness of all three controls to any
attribution defect is a property of which series each one reads, and it holds however the truncation
question resolves.

**2 · `run` — §6's protocol, driven.** §6 as written was two commands and a judgment: *"sample,
analyze, and extend the window until the verdict stops being NO-ATTRIBUTION **or** the refusal
repeats with the same term across several windows — which would itself be the finding."* That makes
the operator the runtime — sitting with the box, re-typing `analyze`, and remembering which control
refused last time in order to recognise the second branch at all. `capacity-marginal.sh run` drives
both branches and returns one verdict: it samples in chunks, re-analyzes the growing window after
each, **stops the moment the three controls pass** (so a window that answers in 10 minutes does not
cost 60), and on exhaustion prints the per-window failure signature history and names a signature
identical in every window as §6's second branch. The output file is fresh by default and an existing
one is refused without `--append`, because a file left over from another day extends `span` across
the gap and makes C2 decidable on half-stale evidence.

**3 · The published s.e. now matches the standard C2 already holds.** The OLS slope s.e. was computed
over `n` rows while C2 deliberately reads its correlation over `n_eff` independent observations —
conceding at the last step exactly what the control refuses at the first. It is now inflated by
`sqrt(n/n_eff)`; at the recommended protocol (`--interval-s` = `CC_MARG_TAU`) the factor is exactly
1, so this changes nothing about the intended run and stops a faster-sampled one publishing an s.e.
roughly `sqrt(tau/interval)` too tight. The s.e. is the half of this coefficient a reader uses to
decide whether it separates from the four values it replaces.

**Verified this session, off-box:** `bats tests/capacity-marginal.bats` **21/21** (was 15), with each
of the three additions **mutation-proved able to fail** — and the width control failed that proof on
its first draft. Written per-line, it PASSED against a deliberate revert of the primary read to
`-axo`, because the Darwin read and its Linux fallback share one source line and the fallback's own
`ww` satisfied a substring check for the pair. It now strips comments and extracts each `-o`-bearing
invocation on its own, and each read reverted alone is caught alone. *A control that green-lights the
mutation it was written to catch is worse than no control — this suite's own founding argument, live
against the suite.* Also green: `tests/agent-teams-enforce.bats` + `tests/capacity-admit-active.bats`
(46/46), `scripts/test-hermeticity-lint.sh` (552 suites, 0 new leaks), `test-walltime-lint.sh`,
`bats-testname-eval-lint.sh`, `gate-select.sh lint`, and `bats-assert-liveness.py` clean on the suite.
**`shellcheck` could NOT be run** — the container's proxy refuses the binary download (403), and
`tests/bats-shellcheck-lint.bats` fails 11/11 identically on unmodified trunk, so that arm is
environmental rather than a finding about this diff. `bash -n` clean.

**What remains is still exactly §6, and it is now one command** — `bash
scripts/capacity-marginal.sh run --total-s 3600 --chunk-s 600 --interval-s 60`, run on the 10-core
Darwin box during a dispatch wave (C1 needs the load to move 1.5x and C3 needs three ACTIVE levels;
both are properties of ordinary traffic, which is why a lull is the wrong hour and an intervention is
not needed). Then update the sites a fresh grep returns and close `193ae8ddce72`.

**What this does not do** — it does not measure the number, and nothing off-box can. The instrument
is one defect safer and the operator's hour is one loop shorter; the fleet is still missing.

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
