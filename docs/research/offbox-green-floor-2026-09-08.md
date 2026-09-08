# The off-box producer has two floors, and the row saw only the lower one

**Row:** backlog `ea3ea8f145f9` — *"hermetic partition is structurally red: 427 suites, ONE failing
per run with a ROTATING identity … Excluding named suites is O(n) whack-a-mole — a different one
fails next hour. The axis is per-run flake probability across 427 suites, not any one suite. Do NOT
curate the exclusion manifest against a single window."* Filed 2026-08-15 off four verdict
artifacts.

**The finding, stated first:** the row's remedy-shape warning is right and its mechanism is wrong,
and the two halves matter separately because they bind in sequence. Across **60 consecutive folds**
there is **not one fold with exactly one failing suite** — the count runs 4 to 11 — and **two suites
are red in 52 of 52** partition folds. For the five days this row sat open, the producer was held
red by a *deterministic core* that no flake model describes and no exclusion policy could reach. The
rotating tail the row names is real, and it is what remains **after** the core is cured; it is the
second floor, not the first. A remedy aimed only at the tail could not have produced a single green.

## The instrument

Every `offbox-verdict.json` artifact still retained on the `hermetic` workflow: **60 scheduled runs,
2026-08-30T17:27Z → 2026-09-08T01:10Z**, run ids `33325312922` … `34175790785`. Eight are the daily
CENSUS (a superset of the partition, `suites > expected`) and are excluded from every rate below;
the remaining **52 are partition folds** of 522–560 suites each. Verdict: **red, 60 of 60.** The
`verdict` job — the only thing that publishes a green, and the only thing `offbox-green-pull.sh`
reads — was **skipped in every one**.

Suites red on the runner were re-run on this box through `scripts/offbox-run.sh suites`, the
producer's own classifier (`env -i`, empty `$HOME`, `LC_ALL=C`, `TERM=dumb`), so *red in both* rules
out a machine axis and *red off-box, green here* isolates one. That is the same two-legged
instrument `offbox-red-triage-2026-09-05.md` used, and this note is its continuation over a longer
window.

## What the folds actually contain

| | measured over 52 partition folds |
|---|---|
| folds with exactly ONE failing suite | **0** |
| failing suites per fold | 4 – 11 (median 7) |
| distinct suites ever red | 27 |
| `tests/typed-send-lint.bats` red | **52 / 52** |
| `tests/validate-bash-differential.bats` red | **52 / 52** |
| folds also carrying ≥1 non-verdict | **38 / 52** |

The last row is a mechanism nobody in this row's history had looked at. `offbox-run.sh verdict`
folds `red > 0 ⇒ red` and `cut+empty+missing > 0 ⇒ cut`, so a **non-verdict is exactly as fatal to
a green as a red is**, and the whole conversation — this row, its sibling `8fd1919f7769`, and the
2026-09-05 triage — has been about reds. Over the same window there were folds with **zero** reds
outstanding under a hypothetical cure and still no green, because a suite had cut.

## Cure depth versus green yield

The decisive table. For each *k*, cure the *k* most-frequently-failing suites and ask how many of
the 23 folds since the FIFTH SEEDING landed (`9613e17af`, 2026-09-04) would then have published a
green — a fold greens only if its failing set is inside the cured set **and** it carries no
non-verdict and no unreported suite.

| k | newly cured | folds red-free | folds GREEN |
|---|---|---|---|
| 0 | — | 0 / 23 | 0 / 23 |
| 1 | typed-send-lint | 0 / 23 | 0 / 23 |
| 2 | validate-bash-differential | 0 / 23 | 0 / 23 |
| 3 | goal-inert-watch | 0 / 23 | 0 / 23 |
| 4 | bats-assert-liveness | 1 / 23 | **1 / 23** |
| 6 | + session-end-gc-lock, live-session-registry-atomic | 4 / 23 | 4 / 23 |
| 9 | + deploy-link-parity, post-tool-batch, mailbox-wake-arm | 7 / 23 | 5 / 23 |

Read the first four rows the way they are meant: **the first three cures buy nothing at all.** That
is what makes the core a floor rather than a contributor — it is not that the deterministic suites
are the biggest term, it is that while any one of them stands, the yield is identically zero and
every other remedy is unobservable. The row's instruction not to curate against a single window is
correct, and it is also why the core went unfixed for three weeks: a rule written against
whack-a-mole reads as a rule against per-suite work, and two of these suites needed exactly that.

## The core, and what each one was

Each reproduced on this box under the producer's own classifier — none was machine-coupled.

- **`typed-send-lint`** (52/52, red here 15 ok / 3 notok). Its three failures were one fact: the
  `--selftest` arm re-runs the lint against the real tree. Both sites it named were **false
  positives** — `scripts/handoff-fire.sh`'s recycle `retype` arm and `bin/cc-husk-sweep`'s
  `type_line()` each already echo-verify inline (type, read the pane back, withhold the CR unless it
  reads back intact), and the detector recognises verification by *sanctioned function name* only.
  Cured with the reviewed per-line hatch the lint documents and `bin/cc-pane` set the precedent for
  (`2294f186b`).
- **`validate-bash-differential`** (52/52, red here 1 ok / 6 notok). All six failures assert one
  harness exits 0. Every one of its 34 sites still measured the verdict it pinned; what moved was
  the line numbers — `69ac630ff` inserted 13 lines into `hooks/validate-bash.sh` at ~697 and every
  site below shifted by exactly 13, reported as 22 UNTESTED sites and 22 stale references, the same
  22 counted from both ends. Re-pinned, each new line asserted to be a real grep site carrying its
  literal pattern (`4719f8993`). Second occurrence; `98fd761df` did the same after a 36-line shift.
- **`goal-inert-watch`** (21/23 red, then green from 2026-09-07T22:49Z). Already cured in-flight by
  `2fd076fa3`. No action.
- **`bats-assert-liveness`** — **not a flake**: green in 10 folds, then red in 13 of 13 from
  2026-09-06T05:56Z. `451696db8` gave it a CONTROL asserting the two bashes its grid is defined over
  are the versions it names, and the runner ships no bash ≥ 4, so `MODERN_BASH` resolves to the same
  `/bin/bash` 3.2 as `LEGACY_BASH`. The suite is right; the image lacks a package. Excluded with that
  measurement (`6d07c953e`), naming the preferred cure it is not — see below.

## What remains, and its shape

With those removed, the same 23 folds project to **1 green in 23 (~4%)**, about one per day at the
hourly cadence, against 0 in 60 today. The residual is 1–5 suites per fold drawn from ~20, none
above 26%: `session-end-gc-lock`, `deploy-link-parity`, `live-session-registry-atomic`,
`mailbox-wake-arm`, `post-tool-batch` at 5–6 of 23, then a tail at 2–3, plus `peer-owned` cutting in
4 of 23. **This** is the row's model, and here it holds.

Two things follow that were not knowable before the core came off.

**The tail is bounded — about twenty suites, not the corpus — but it is NOT a repair program, and
that is a change from 2026-09-05.** The row assumed *n* was the whole corpus (427, then 565) and
concluded per-suite work could not terminate; *n* is in fact about twenty. But the second leg was
run on all nine of the most frequent residual suites — `session-end-gc-lock`, `deploy-link-parity`,
`live-session-registry-atomic`, `mailbox-wake-arm`, `bash-audit-attrib`, `ttl-lock-owner-token`,
`mailbox-session-key`, `drain-conversion-churn`, `peer-owned` — and **all nine are green on this
box**, 2026-09-08, under the producer's own classifier. Two of them, `deploy-link-parity` and
`bash-audit-attrib`, were measured red on BOTH legs three days ago and named GENUINELY BROKEN by
`offbox-red-triage-2026-09-05.md`; they have since been fixed on-box. Of that note's five real reds,
none survives: three were cured (two here, `goal-inert-watch` by `2fd076fa3`) and two now pass
locally.

**State the limit of that leg rather than rounding it up.** One local green does not refute a suite
that fails 26% of the time off-box — it is a scalar sample of a varying quantity. What nine greens
DO rule out is a deterministic tree defect in any of them, which is the only class per-suite repair
can address. So there is currently no evidence that fixing code will move the residual at all, and
the sibling row `8fd1919f7769` ("triage per suite: machine-coupled vs genuinely broken", BLOCKED on
a dead-worker stall) may find its population has emptied under it. The remaining levers are not
per-suite repair: they are converging the runner's environment on the box (see the bash divergence
below) and the fork stated next.

**Below about 20 residual suites there is a decision no measurement settles.** At a per-fold residual
of one to five, an all-green fold stays rare however the individual causes are dispatched, and the
only mechanism that changes the arithmetic is letting a not-green suite be re-run within the run.
That is a semantic change, not a tuning: today a green means every partition suite passed on the
first attempt. The producer's own classifier already separates a claim about the CODE (`red`) from a
claim about the MACHINE (`cut`, "proves nothing"), and a suite that is red in one fold and green in
the next on an unchanged tree is making an unstable claim the classifier cannot see inside a single
run — but folding such a suite as `cut` still publishes nothing, so the only version of the
mechanism that yields greens is the one that counts a pass-on-retry AS a green. `/ship`'s on-box
smoke deliberately treats pass-on-retry as a finding rather than a flake. Whether an acquittal-only
second opinion should rule the other way is the operator's call, and it is not made here.

## The runner is not the box, in a way that is not on any exclusion list

`bats-assert-liveness` exposed it rather than caused it: the macos-latest image ships no bash ≥ 4,
so every `#!/usr/bin/env bash` script and every bats body in the off-box corpus runs under **bash
3.2**, while the operator's box resolves Homebrew's **5.x**. The off-box producer has therefore been
acquitting the tree under a different interpreter than the one the tree is actually run with. The
cure is the one the workflow header already records for shellcheck — install the missing package —
and it is deliberately *not* taken here: Homebrew's bin precedes `/bin` on the runner PATH, so
`brew install bash` re-points ~550 suites from 3.2 to 5.x in one step and cannot be measured before
it lands. It is a measured change of its own. A `CC_MODERN_BASH` env seam on the one suite is its
narrow half.
