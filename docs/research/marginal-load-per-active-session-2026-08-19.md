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

---

## 9 · 2026-08-25 — the instrument re-verifies; the citation is purged; §6 is the only thing left

This item was re-dispatched on 2026-08-25 and driven off-box again. Three things came out of it, and
the first is the one that decides the item's state.

**§6 remains unrun, and it is not runnable anywhere but the box.** This dispatch landed in a Linux
container: `uname` Linux, **4 cores**, **one** `claude` process, no Darwin, no fleet. `capacity-marginal.sh`
needs `sysctl vm.loadavg`, a `ps` census with real Claude ancestry, and `cc_sp_active` moving through
≥3 levels. None of those exist here, so no window run from this environment could clear C1, C2 or C3 —
and one that appeared to would be measuring the container, which is exactly the class of error §3
exists to refuse. **The coefficient is therefore operator-gated, not agent-gated**, and the backlog item
is parked on that step rather than reopened.

**The instrument itself re-verified clean, in a tree that had never seen it.** `bats
tests/capacity-marginal.bats` → **15/15 green** on a fresh clone at `origin/main`, including the two
rows that carry the DoD's actual requirement: the POSITIVE CONTROL (the flat 19–20-across-2.2×-load
census is REFUSED by C2, naming the correlation) and the NEGATIVE CONTROL (a planted 0.325 recovered as
0.333 with all three PASS). **The DoD clause "sampler must pass a correlation control" is met** — the
control exists, it is C2, and it has been watched failing for its own reason. What is outstanding is
the coefficient, never the instrument.

**The disqualified value was still live in THREE places, not the two §2 and §6 name.** §2's closing
paragraph and §6 both list `capacity-admit.sh` and `agent-teams-enforce.sh`; a repo-wide grep of
`scripts hooks bin commands skills` found a third — `scripts/lib/spawn-presence.sh`, in the header that
defines the ACTIVE population itself, i.e. the very census `capacity-marginal.sh` was built to replace.
(The two line numbers had also drifted: `capacity-admit.sh:698` → `:723`, `agent-teams-enforce.sh:220`
→ `:235`.) All three are now purged. The other three values (`0.172`, `0.566`, `1.89`) occur nowhere in
live code — only inside `capacity-marginal.sh`'s own header, correctly labelled as disqualified.

🚨 **The purge asserts NO coefficient, and that is deliberate.** §6 says update these sites to the
measured value *once the window has run* — "not before, and not to one of the other three." Replacing a
refuted number with a *number* would break that rule; replacing it with the refutation does not. So each
site now states that the per-active-session cost is UNMEASURED, names this doc and the backlog id, and
says what may not be done with the gap:

| site | was | now |
|---|---|---|
| `scripts/lib/capacity-admit.sh` (ACTIVE-CONCURRENCY term) | "8 is the top of the measured band. Axis 09: **2.5-5** runnable threads per genuinely-ACTIVE session…" | 8 restated as an **operating** ceiling standing on the direction of the evidence and the 127/127 refusal history, **not** on a coefficient; all four values named as unrepairable; `capacity-marginal.sh` named as the replacement; "re-derive before moving it" |
| `scripts/lib/spawn-presence.sh` (THE ACTIVE POPULATION) | "…i.e. **2.5-5** runnable threads per genuinely ACTIVE session against the 1.6 that a MIXED fleet averages to" | the qualitative claim kept (an active session costs real runnable load, a resident one costs almost none — which is all this census needs), the per-session arithmetic removed as an aggregate/N |
| `hooks/agent-teams-enforce.sh` (the `active` refusal message an agent actually reads) | "…but **2.5-5** runnable threads arrive with every ACTIVE session" | "…but real runnable load arrives with every ACTIVE session", plus an explicit *do not quote one, and do not raise the ceiling from one* |

The third row is the one that mattered most operationally: it is the only site of the three that an
agent **reads at refusal time**, so it was the path by which a disqualified number could be quoted back
into a decision to widen a fan-out.

**`CC_ADMIT_ACTIVE_CEILING=8` is unchanged**, in value and in behaviour. This is a comment-and-message
diff; no term, threshold or control moved.

### Gate evidence for this increment

`bash -n` clean on all three files · the `agent-teams-enforce.sh` jq refusal program extracted and run
under `jq -n`, parsing and rendering the new sentence (a message edit inside a jq string literal is the
one way a comment-shaped diff can break at runtime) · `bats` green on every suite covering the three
files: `capacity-marginal` 15/15, `capacity-admit-active` 22/22, `capacity-admit-coverage` 15/15,
`agent-teams-enforce` 24/24. `capacity-admit` (12 fail), `spawn-presence` (6 fail) and
`handoff-fire-capacity-gate` (3 fail) fail **identically, test-name for test-name, on a pristine
`origin/main` worktree in the same container** — Darwin-only rows (`/usr/sbin/sysctl`, `vm_stat`)
that cannot pass on Linux. Baselining them was not optional: a post-land RED reproduces faithfully in
an environment that was never able to go green, and mistaking one for a regression is how a diff ends
up reverting trunk. **`shellcheck` could not be run here** — the proxy returns 403 on the binary
download and no distro package is reachable — so it is owed on the box; the diff adds no code, only
comment lines and one string literal.

### What remains — one operator command, no judgment in it

```sh
bash scripts/capacity-marginal.sh sample --window-s 3600 --interval-s 60 --out /tmp/marg.tsv
bash scripts/capacity-marginal.sh analyze --in /tmp/marg.tsv
```

Run it on the 10-core Darwin box, in a session not doing heavy work, across a dispatch wave rather
than a lull (C3 wants ≥3 ACTIVE levels; §6). On a PASS, quote the coefficient **with its standard
error and its window** and update the three sites in the table above — which are now the complete set,
grep-verified, rather than the two previously believed.
