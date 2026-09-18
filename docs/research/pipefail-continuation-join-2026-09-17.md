# pipefail-sigpipe-lint is blind to a pipeline split across a line continuation

**2026-09-17.** Backlog row `c128aeff816e`, condition `pipefail-lint-continuation-join`.
Sites fixed: `22e133a0e`. Detector gap: **CLOSED 2026-09-18** — see *The cure* at the foot of
this file, which also corrects the 9-site bound below by re-measuring it with the detector.

`scripts/pipefail-sigpipe-lint.sh:532` names this residual itself — *"It does not join
CONTINUATION lines (pipe258.py is a working joiner nobody has wired in)"* — and `:542`
instructs: *"The continuation join is a different gap and it has NO row … File it under its
own condition before citing an id for it."* This is that row's evidence.

## The measurement

One variable per fixture, against the **shipped** detector (`CC_PIPEFAIL_ROOT` fixture tree,
`--census`, `CC_PIPEFAIL_MEMO=off`):

| fixture | shape | detector |
|---|---|---|
| `c_and_oneline` | `printf … \| grep -Eq P && act` — one physical line | **REPORTED** |
| `b_andchain` | same, split by `\` | not reported |
| `a_if` | `if printf … \| grep -Eq P; then` — one physical line | **REPORTED** |
| `d_if_contin` | same, split by `\` | not reported |

So `&&` is **not** the blind axis. The continuation is.

## The residual is no longer hypothetical

The lint's own paragraph says *"Neither shows up in today's numbers."* That was false when
measured. Three live fail-open guard sites were hiding behind exactly this gap in
`bin/cc-cannot` — `:136` (`open tel:/sms:`), `:140` (interactive credential flows), `:208`
(the editor refutation). Each gates an `&&` that fires a **verdict**, so under `set -o
pipefail` a match SIGPIPEs the producer, the pipeline reports the producer's death, and the
guard stays silent exactly when it should speak. That is `0ea2ab91c`'s own polarity argument
reaching three sites its ratchet could not point at.

`0ea2ab91c` drained the five sites the ratchet **did** flag. `22e133a0e` drained these three
and pinned them structurally (not an allowlist row — the allowlist is shrink-only and the
ratchet cannot see these lines to count them). Red-proof: swapping in `origin/main`'s
`bin/cc-cannot` makes the pin fail naming exactly 136, 140, 208.

## Blast radius — a BOUND, not the detector's count

⚠️ Measured with **my own approximating scanner**, not the detector: join backslash-continued
lines, match `| grep -*q` or `| head -N`, restrict to files whose head mentions `pipefail`.
Quote it as a bound.

- **27** continuation-split early-exit pipelines tree-wide
- **9** with rc **consumed**, so a verdict can invert:
  `hooks/lead-crash-watchdog.sh:475` · `hooks/stop-failure-marker.sh:85` ·
  `scripts/completion-push.sh:174` · `scripts/gate-classify.sh:123` ·
  `scripts/plan-phase-scan.sh:112` · `scripts/settings-hook-timeouts.sh:176`, `:194`, `:196` ·
  `scripts/smoke-test.sh:172`
- **18** where the rc dies in a command substitution and **must stay exempt**

🚨 **Do not quote 92.** An earlier, deliberately over-generating pass returned 92; the
commit body of `22e133a0e` cites that figure and is superseded here. The 27/9 split is after
requiring rc-consumption. Drained-or-not is about whether an rc is **read**, never about the
shape — `cc-cannot:174` (`head -80 … | grep -Eom1`) is the canonical case the lint is
**right** not to flag, because its rc dies in a substitution.

## Why this is its own wave

Wire `~/.claude/autonomy/pipe258.py` into the scan, re-measure, drain the rc-consuming set,
keep the discarded-rc set exempt, re-pin. The allowlist is **shrink-only by contract**, so
nothing the joiner reveals can be absorbed: every rc-consuming site must be drained before
the detector can ship, which blocks every land until done. That is a land-gate widening for
the whole fleet, not a follow-on to a one-row fix.

## Re-derive

```
cd ~/Development/claude-infrastructure
sed -n '525,560p' scripts/pipefail-sigpipe-lint.sh      # the residual, in the lint's own words
```
Then rebuild the four fixtures above under a `CC_PIPEFAIL_ROOT` tree and run
`bash scripts/pipefail-sigpipe-lint.sh --census`. Re-measure; never re-quote.


---

# The cure — 2026-09-18

Wired at **GATE ZERO** of `scripts/pipefail-sigpipe-lint.sh`: `cont_open()` / `strip_cont()` plus a
join block at the head of the pass-two rule, so every clause below it judges a **logical** line.
`~/.claude/autonomy/pipe258.py` was not used — it lives on the operator box and this was done from a
cloud VM; the joiner is ~12 lines of awk in the detector itself, which also keeps it in the file a
reader can run.

## What it cost, one variable per arm

Method 213. Control = the shipped detector extracted read-only from `origin/main`, mutant = a
whole-file copy differing in exactly the named runs, `CC_PIPEFAIL_ROOT` pinned to the same tree on
both arms, `--census` keyed on (path, TEXT) taken verbatim. **The control reproduces `--census`
byte-for-byte at 121 rows**, so the arms below are differences and not drift.

| arm | rows | note |
|---|---|---|
| control — `origin/main` | 121 | reproduces the shipped census exactly |
| `is_early` stage truncation ALONE, no join | **121** | byte-identical: a no-op until the join exists |
| join alone | 130 | +12 NEW, −2 LOST, 1 row re-texted |
| join + truncation (shipped) | 128 | the 2 it drops are false positives the join minted |
| + the newly-visible sites drained | **119** | allowlist **shrinks by 2** and gains none |

The truncation is not optional. `is_early` anchors its command *word* at the head of a segment but
scanned the whole segment for the early-exit *flag* — fine while a record is one physical line.
Joined, `! plutil -p F | grep PAT >/dev/null \` + `&& grep -q OTHER F` is one record whose second
segment is `grep PAT >/dev/null \003 grep -q OTHER F`, and the `-q` belongs to a command that is
not in the pipeline at all. Two files were convicted for using the exact remedy this lint
prescribes — `migrations/0010-postland-band-plist.sh:74` and `migrations/0016-…:79` — which is the
`a6449cebc` class, a ratchet refusing a land for a reason that is not about the code.

## ⚠️ The 9-site bound above is wrong, and in both directions

That list came from an approximating scanner, and the header of that section says to quote it as a
bound. Re-measured with the **detector**, the two populations barely overlap:

- **1 of the 9** is confirmed and was newly reported: `scripts/plan-phase-scan.sh:112`.
- **1 of the 9** was *already* in the census before any of this — `hooks/lead-crash-watchdog.sh:475`
  is a complete pipeline on its own physical line, with only the `&&` wrapped.
- **7 of the 9** carry a **top-level trailing `||`** on the joined line, so clause 5 exonerates
  them: `stop-failure-marker.sh:85`, `completion-push.sh:174`, `gate-classify.sh:123`,
  `settings-hook-timeouts.sh:176/194/196`, `smoke-test.sh:172`.
- **11 sites the scanner never listed** are what the detector actually found. The bound was not
  merely loose; it was a different set.

The 10 real ones are drained in this commit: `bin/cc-dispatch:2434`, `hooks/completion-assert.sh:891`
(both stages), `hooks/dispatch-assert.sh:135` and `:199`, `scripts/bats-shellcheck-lint.sh:412`,
`scripts/iterm-metal-bench-app.sh:245`, `scripts/plan-phase-scan.sh:112`,
`scripts/postland-verify.sh:3095`, `scripts/store-bounds-census.sh:208`.

## The two LOST rows, which are the part worth reading

`bin/cc-bus:1055` and `bin/cc-comms-alarm-sweep:294` are `p | grep -q X && ok … || bad …` split
across a backslash. Joined, clause 5 finally sees the top-level `||` and exonerates them — so **the
join retires two rows it did not fix**, and the allowlist shrink that follows makes that permanent.
A SIGPIPEd producer still flips both assertions to a spurious FAIL. Both are drained here too,
because a row that leaves the census because a clause finally sees an exoneration is a row nothing
will ever count again.

## Named, not widened: clause 5 vs. an `&&`/`||` verdict pair

Those two sites and the 7 above are one population: `p | grep -q X && ok … || bad …`. Clause 5's
contract is about the **141 reaching errexit or a caller**, and it is right that a top-level `||`
swallows that. It says nothing about the **verdict**, which inverts — `ok` is skipped and `bad`
fires on a match that is present. That is the same polarity argument `0ea2ab91c` made, one clause
over, and it is **not** a continuation problem: the one-line spelling is exonerated identically and
the population is tree-wide. It wants its own row, its own measurement of how many sites clause 5
exonerates, and its own decision about whether the clause should distinguish `|| true` (a genuine
neutraliser) from `|| bad …` (a verdict). Not folded in here.

## Still open, and it is now all that the lint header's residual names

The **dangling-quote** contract. A multi-line `jq` or `awk` program carries no backslash, so this
joiner does not touch it and its opening line still runs to end of line as quoted context (arm 25
pins that the obvious repair is wrong for this tree). Pass **one** — `collect_caller`, clause 4c —
is also still line-local by choice: joining there changes which *callers* are found, a different
population that wants its own measurement.

## How it is pinned

`--selftest` 65 → **72**; `tests/pipefail-sigpipe-lint.bats` 27 → **28** arms.

Seven mutants, six of which die on exactly one arm each:

| mutant | dies on |
|---|---|
| M1 — no join at all | r37, r38 |
| M2 — join with no comment guard | r39 |
| M3 — anchored `/\\$/` instead of an odd count | g37 |
| M5 — `is_early` untruncated | g39 |
| M6 — heredoc opener read from `$0` | g38 |
| M7 — quote-blind `first_cmd` | r40 |
| M4 — join moved ABOVE the heredoc tracker | **nothing — green on all 72** |

M4 is recorded as an equivalence rather than claimed as a pin: the heredoc tracker tests `$0`, the
*last* physical line of a record, and a terminator is always alone on its own line, so the ordering
is defensive and not load-bearing. The first cut of g37 and g38 also passed in both states and
pinned nothing — g37 opened with `:`, which `is_external` lists beside `echo` and `printf` as a
bounded builtin. Both were rebuilt until a mutant killed them.

## Re-derive

```
git fetch origin && git show origin/main:scripts/pipefail-sigpipe-lint.sh > /tmp/A.sh
CC_PIPEFAIL_MEMO=off CC_PIPEFAIL_ROOT="$PWD" bash /tmp/A.sh --census | wc -l    # the control
CC_PIPEFAIL_MEMO=off bash scripts/pipefail-sigpipe-lint.sh --census | wc -l     # shipped
bash scripts/pipefail-sigpipe-lint.sh --selftest && bats tests/pipefail-sigpipe-lint.bats
```
