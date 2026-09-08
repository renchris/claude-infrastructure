# The postland stamp store was never mis-keyed — and trunk has had no green since 2026-09-03

**Date:** 2026-09-08 · **Backlog:** `24d291d2384e` (the refuted premise), `<real-blocker>` (the live fault)
**Trigger:** a P0 handoff asserting that the post-land verifier stamps pre-rebase shas, so no stamp in
four days was keyed to a sha surviving on trunk.

## 1. The premise was instrument error, and the instrument was `--is-ancestor`

The measurement took each stamp's **filename** as a commit sha and ran
`git merge-base --is-ancestor <filename> origin/main`, with stderr suppressed, reading any non-zero
as "off-trunk". It read `off` 20 times out of 20.

The stamp store is **tree-keyed**. The filename is a *tree* object, and `deploy-live.sh:11` says so
in the file's own words:

> Stamp contract: `<stamps>/<tree-sha>.json` containing `"verdict":"green"` (tree-keyed, so a
> rebase/cherry-pick that preserves the tree keeps its verdict).

`--is-ancestor` speaks only about commits. Handed a tree it exits **128**, not 1:

```
error: object 08f72a38441b… is a tree, not a commit
fatal: Not a valid commit name 08f72a38441b…
```

Suppressed and consumed by `if !`, 128 and 1 are the same byte. Every row was a *could-not-ask*
misread as a *no*.

**Measured correctly, on the stamp's own `.commit` field:**

| population | ancestors of `origin/main` |
|---|---|
| newest 20 stamps | **20 / 20** |
| whole corpus | **568 / 581** |
| the 13 exceptions | all dated **2026-07-30 … 2026-08-01**; zero in the last five weeks |

So tree-keying is doing exactly the job it was built for. The rebase-survival property the handoff
proposed to build already exists, and re-keying stamps to the landed commit would have **destroyed**
it — a stamp whose recorded `.commit` is a pre-rebase branch sha is still a valid verdict about the
tree that landed. Brief steps 1 and 4 were withdrawn on this basis.

### The consequence chain, corrected

| claim | verdict |
|---|---|
| the verifier certifies shas that do not survive the land | **refuted** — tree-keyed by design |
| `cc-blockers` computes trunk-red over an off-trunk population | **refuted** — newest 5 are all trunk ancestors; the row is a correct verdict |
| the newest green sits ~294 behind | **correct** — that is the green-*pointer* lag (301 by direct count) |
| the live `~/.claude` layer is ~294 commits stale | **refuted** — live HEAD `c4294e9ff628` is **7** behind trunk, and an ancestor of it |

The last two are different quantities. Conflating them turned a healthy converger into a P0.

**This trap is a repeat.** The same misread is already recorded, and fixed, twice in this tree —
`scripts/postland-verify.sh:2924` ("handing it a tree sha makes `rev-parse <tree>^{commit}` fail and
the probe answers 'could not ask' on every single…") and `scripts/deploy-parity-assert.sh:1415`
("which exits 128 for every input"). Nothing guarded it, so it recurred a third time.

## 2. What was actually broken: an unaskable question answered anyway

`bin/cc-blockers` read the deploy cursor's ancestry as a two-way test:

```bash
if ! git -C "$DEPLOY_REPO" merge-base --is-ancestor "$head_sha" "$gcommit" >/dev/null 2>&1; then
```

`$gcommit` is read from a stamp's `.commit`, so both unaskable shapes are **reachable, not
theoretical**: the object may be pruned (the live store holds 13 such pre-rebase branch shas), or a
reader may put the tree-shaped key there. Replayed through the row with the real artifacts, pre-fix:

| `.commit` holds | pre-fix row | post-fix |
|---|---|---|
| a real ancestor (control) | `green 3bc036077c32 sits 1 behind live HEAD` | **unchanged** |
| an object this repo lacks | `green deadbeefdead is not above live HEAD` | **no row** |
| a **tree** | `green 4b825dc642cb **sits 2 behind live HEAD**` | **no row** |

The tree case is the worst of the three: `rev-list --count <tree>..<head>` counts the whole history
rather than failing, so the board rendered a **confident, quantified, false wedge**. That
contradicts the law this file's own suite already states — *"alarms fail OPEN: an unreadable/absent
sensor yields NO row, never an invented blocker."*

**Fix:** the ancestry test is given its third answer. `0` yes · `1` no · anything else = *could not
ask* ⇒ abstain. Abstaining opens no blind spot: `green-starved` (age) and `never-green` (existence)
are emitted above this point and are not gated on it, so a genuinely starved store still speaks
through the arms whose question can be answered.

**Guards** (`tests/cc-blockers.bats`), red-proofed against a mutant built by editing the working
tree back to the two-way fold — never by replaying a ref:

- **W6** pruned object ⇒ no row. RED on the mutant.
- **W7** tree in `.commit` ⇒ no row *and no fabricated magnitude*. RED on the mutant.
- **W8** pins the premise the three-way split rests on: a real non-ancestor is rc **1**, a tree is rc
  **128**, and a stamp's key really is a `tree` object. Green against both arms **by design** — it
  asserts git's behaviour, not our branch, so it must not move; it is the arm that would have caught
  the four-day misread. (Same precedent as this file's SUP2/SUP6.)

W1–W5, the preservation arms, are unmoved against both.

## 3. The real fault: every run since 2026-09-03 breaches the wall backstop

No green stamp exists after **2026-09-03T16:23Z**. The cause is none of the three hypotheses put to
this session (one persistently-red test · a different one each run · the `cut` class never
finishing). It is a **runtime regime change**.

`POSTLAND_SUITE_TIMEOUT_S` = **10800s** (`scripts/postland-verify.sh:275`), a wall backstop. A run
that hits it names whatever has not yet passed as red.

| day | suites | median `run_s` | runs over 10800 | greens |
|---|---|---|---|---|
| 2026-08-28 | 549 | 3781 | 0 | 7 |
| 2026-08-29 | 553 | 3140 | 0 | 6 |
| 2026-09-01 | 557 | 2932 | 0 | 5 |
| 2026-09-02 | 559 | 3102 | 1 | 3 |
| **2026-09-03** | 559 | **11182** | 3 | 1 |
| 2026-09-04 | 569 | 11273 | 6 | **0** |
| 2026-09-05 | 573 | 11206 | 6 | **0** |
| 2026-09-06 | 577 | 11382 | 5 | **0** |
| 2026-09-07 | 590 | 11276 | 6 | **0** |
| 2026-09-08 | 596 | 11279 | 2 | **0** |

Median `run_s` for reds jumped **3272 → 11268** at that boundary; for cuts, **2600 → 11642**. The
*only* run in the window that finished in normal time — 2026-09-03T16:23Z, **2923s** — went **green**.

**The rotation has a sharper owner, and it is not this.** I first read the rotating failing set as
"whatever the wall interrupted", i.e. arbitrary. **That is refuted.** Pane 537 landed `fc61fa948` the
same night with the actual mechanism: `postland-verify`'s `conviction_clear` spent the corroboration
row of the very file the run had just convicted, so a chronically failing suite could never hold two
consecutive windows — it reds every *other* sweep, and the reds alternate between two halves of ONE
stable population. Measured on this host: **lag-1 overlap 0.00 across all 21 consecutive RED pairs,
lag-2 Jaccard up to 1.00**. That is a period-2 oscillation, not a reroll, and the alternation is
plainly visible in the raw stamps — `{compressor-sentinel, handoff-fire-completion-push}` at
09-07T11:22, 09-07T21:03 and 09-08T04:01, interleaved with a disjoint set each time between.

So: **537 owns *which* suites are named and why they alternate. The measurement below owns *why runs
stopped finishing*.** They are complementary, and the union of the two halves — 21 suites — is the
real failing population, which is what makes per-suite work tractable again.

### The discriminator

| window | n | median retries | median load | median `run_s` | suites |
|---|---|---|---|---|---|
| 2026-08-25 … 09-03 | 117 | **2** | 14.7 | 2932 | 559 |
| 2026-09-03 … now | 28 | **14** | 19.9 | 11273 | 596 |

Retries rose **7×** while load moved **1.35×** and the corpus grew **6.6%**. Load did not change the
regime; the **retry ladder** did. Each retry re-runs a file under `FILE_TO` (300s) / `RETRY_TO`
(5400s), so a ladder this deep consumes the 10800s wall. Pre-window retries were 0/2/4 in 113 of 117
runs; post-window they span 6–28.

**Whether `fc61fa948` also fixes this is open and now testable.** A period-2 oscillation makes every
chronic suite re-pend and re-corroborate on alternating sweeps, which is itself a retry generator, so
the ladder depth and the oscillation plausibly share a cause. If they do, the next full sweep after
`fc61fa948` should show `retries` falling back toward the pre-window 0/2/4 band and `run_s` back
under the wall. **That is the one prediction this document makes, and it is falsifiable on the next
stamp.** If retries stay at 14+, the runtime regime has a second, independent cause still unfound.

**The admission gate is NOT that cause** — checked and closed by reading rather than assumed:
`~/.claude/bin/bats` resolves to the `cc-bats` admission wrapper, which defers with **rc 75** when
other execution roots are live, but `postland-verify.sh:225` exports `CC_BATS_MAX_ROOTS=0` to exempt
itself, and `:1610` treats a stray rc 75 as an explicit "the exemption did not reach the child"
failure. The verifier is not being deferred.

**And the ceiling stops binding the moment several sessions reach for its override.** Observed live
while writing this, 2026-09-08 08:12Z: **1-min load 91.80** (5-min 57.8, 15-min 37.7) with at least
three concurrent bats execution roots, each started under `CC_BATS_MAX_ROOTS=0` by a different
session — the wrapper's own documented escape hatch, which every contending caller can take
unilaterally. My own `tests/cc-blockers.bats` run went from finishing 108 tests comfortably to
completing 8 in several minutes on the same tree. The gate is fail-safe by design; it is not a
scheduler, and nothing arbitrates between the callers that opt out of it. That is the contention the
verifier runs its 596-suite corpus inside, and it is the most plausible remaining driver of §3's
retry ladder.

⚠️ **A deferral is not a pass, and a piped run cannot tell you which you got.** Running these 21
suites the naive way — `bats "$s" | tail -4` — returned `RC=0` for all 21 while **none of them ran**:
`$?` after a pipe is `tail`'s, and the wrapper's own "nothing ran, nothing was verified" line had
been cut off by the `tail`. The real signal is rc **75** and it was never observed. Same class as the
two instrument errors above.

## 4. The dominant `cut` reason

Brief step 3 (record a reason at write time) **already landed** as `c4294e9ff` on 2026-09-07 and is
live; no `cut` has occurred since, so 0 of 308 stamps carry `cut_why` yet. The durable answer is
available now from `runner.log`, which has carried the distinction since 2026-08-17 — 400 cut events,
2026-07-26 … 2026-09-08:

| reason | n | share |
|---|---|---|
| **run KILLED by signal 9/15 from OUTSIDE the runner (sender unidentified)** | **236** | **59%** |
| ladder convicted N file(s) in ONE load window — awaiting a second (C29) | 90 | 22% |
| zero not-ok in a non-zero run — truncated | 40 | 10% |
| machine pressure, not the tree | 18 | 5% |
| bats rc ambiguity (0=pass, 1=fail) | 10 | 3% |
| our own bound cut the run | 6 | 2% |

**~74% of cuts are the run being killed or truncated from outside** — but that is a **historical**
population, and it is already cured. `1e594d10a` (sibling, 2026-09-08) names the sender: `bin/cc-reaper`'s
stuck-wrapper arm, whose predicate `comm==bash && args ~ /cc-close-attrib/ && secs>=1800` was an
**unanchored substring test over the whole argv**. `postland-verify` runs its corpus as one command
line naming ~558 suite paths, one of them `tests/cc-close-attrib.bats` — so **the corpus matched
itself** every time it ran past 1800s, and `garbage_sweep`'s TERM → sleep 3 → KILL is why one sender
produced both signal 15 and signal 9. Cured on trunk by `9f9a64bb4` (2026-09-02), with both controls:
281 runs / 154 signal-killed (55%) before, **33 runs / 0 signal-killed** after, last kill
2026-09-02T10:58Z.

**So the table above is a post-mortem, not a live diagnosis**, and my own stamp census agrees with the
cure date independently: only **4** cuts against 23 reds since 2026-09-03, where the pre-cure ratio ran
the other way. The `cut` class is no longer the story; it stopped being the story six days ago.

## 5. What was NOT done, deliberately

The handoff forbade lowering the converger's bar, treating a missing stamp as green, or
force-advancing the live layer, and none of that was done. The live layer was **not** converged: it
is 7 commits behind trunk, reported and left for a separate decision. Nothing was committed in the
shared checkout; `core.bare` read `false` before and after.

## 6. Which suites actually fail on trunk: **none of them, individually**

The desk's remaining half, now tractable because `fc61fa948` makes the failing population stable. The
union of every suite named across the 23 reds since 2026-09-03 is **21 suites** — which, under 537's
period-2 finding, is the whole population rather than any one run's half. Each was run individually on
trunk with the verifier's own admission exemption (`CC_BATS_MAX_ROOTS=0`), full TAP captured per suite:

**20 of 21 green — 937 assertions planned, 936 ok, 1 not ok.** The single exception was
`tests/handoff-fire-completion-push.bats` test 5 — one `not ok` of 11 — and it is **intermittent**:
it passed alone, then passed 3 of 3 further full-file runs, 4 for 4 since. Its own name is
*"--successor liveness gate is **load-robust**: a failing tty query does NOT leak a raw osascript
exit"*, and its comment says it guards a flake that appears "under iTerm2 AppleScript-bridge
contention". It failed in the one run that overlapped another bats root of mine, and nowhere else.

**So the red band is not a set of broken suites.** No suite in it fails deterministically on trunk.
That is consistent with 537's oscillation plus load coupling, and inconsistent with a content fault —
and it is why `tests/compressor-sentinel.bats`, named in 10 of 23 reds, passes in seconds by hand.

⚠️ **What this does NOT prove.** These ran one suite at a time on a comparatively quiet box; the
verifier runs ~596 suites in a single command under real load. A green here bounds *determinism*, not
*flakiness under the verifier's regime* — the band may still red there. The claim is the narrow one:
**there is no suite on trunk that is simply broken**, so per-suite content work has no target, and the
remaining lever is the runtime regime of §3.
