# TrueMemory build-now Waves A-C were already landed — verdict on cc-backlog `eb41b669e5e6`

**Date:** 2026-09-28 · **Verdict:** ALREADY DONE on trunk · **Disposition:** close the row on the
shas below; no new code.
**Measured on:** an Anthropic cloud VM (Linux x86_64, GNU coreutils, mawk, running as root). The
desk is macOS, so this run is a second machine, not a re-read.
**Trunk read:** `origin/main` = `ea07499f1f93c4b527fdf0ece16a334c81b9e44e` (2026-09-28T08:58-05:00).
The clone arrived shallow and was deepened with `git fetch --unshallow` before any ancestry check.
`git rev-list --count HEAD..origin/main` = 0.

---

## The claim

The row asked for build-now items #1-#14 of `docs/research/truememory-2026-09-27.md` §2, done per
the DoD in `docs/plans/TRUEMEMORY_ADOPTION.md`. On trunk, that plan already records all three waves
as **DONE 2026-09-28**, and its status log has three entries saying so (Wave A, Wave B, Wave C,
each with "live layer converged"):

| Wave | Items | Plan section |
|---|---|---|
| A — correctness and safety | #1, #2 (P0, P0b, P1), #3, #8, #11 (+ migration 0043, rejection record) | `## Wave A … — DONE 2026-09-28` |
| B — substrate and push consumers | #4, #5, #6 + #7, #10 (+ #26 shadow, #35 benchmark) | `## Wave B … — DONE 2026-09-28` |
| C — the rest of build-now | #9, #12, #13, #14 | `## Wave C … — DONE 2026-09-28` |

That covers all 14 items. The plan's frontmatter still reads `status: in-progress` because its scope
has since grown to Waves D and E. Those waves are outside this row's frozen scope.

## Every cited sha is on trunk

I pulled every backticked 9-hex sha from the plan's Wave A-C sections through the end of its
Wave C record (49 distinct shas) and asserted each one:

```
git merge-base --is-ancestor <sha> origin/main     # 49 of 49 exit 0, 0 missing
```

The shas are listed per item in the plan's "Landed (origin/main, content-verified)" blocks. I did
not copy them here, because a second list would drift from the first.

**Dispatcher vintage.** `git rev-parse origin/main:bin/cc-dispatch` =
`dc9130372d6332940388c2a17da7c65c1af3c3bd`, the same blob that composed this brief: **EQUAL**. The
dispatcher that fired this session is trunk. So this is not a landed-but-not-live gap: the row went
stale when the waves landed on the same day it was filed.

## What was run: the items' own suites, on a machine that has never run them

These are the 32 `tests/*.bats` files touched by the 49 shas, run with `bats --tap`, with
bats/sqlite3/shellcheck installed from apt. Every row asserts the `1..N` plan line, so none of these
is a refusal read as a pass.

**Green as-is (20 suites, 404 tests, 0 failures):** bench-score 5 · cc-memory-rotate 56 ·
cc-memory-search 19 · cc-memory-supersession-check 11 · harvest-skill-end 22 · hook-output-contract 10 ·
land-gate-cas 22 · lesson-recall 23 · memory-index-budget 37 · memory-index-drain 36 ·
memory-nudge-budget 43 · memory-nudge-interval 5 · memory-recall-eval 18 · memory-store-snapshot 14 ·
norm-share 12 · rules-hook-budget-lint 38 · rules-loaded 10 · session-index-init-db 6 ·
ship-land-outer-timeout 7 · transcript-norm 10.

**Red on first pass (12 suites).** Every red was traced to a named macOS dependency, never to item
logic. For each, I removed the dependency and ran the suite again:

| Suite (item) | First pass | Cause (measured) | After removing the cause |
|---|---|---|---|
| memory-fleet-sweep (#8) | 7 red / 25 | bats puts its tmpdir under `/tmp` on Linux; the sweep skips `-tmp-*` slugs as fixtures (`scripts/memory-fleet-sweep.sh:127`); the desk's tmpdir is `/var/folders` | **25/25** with `TMPDIR` off `/tmp` |
| postland-verify | 61 red / 152 | the fixture's isolated `$HOME` has no git identity (exit 128); BSD `date -v`, `stat -f` | **152/152** with a git identity in env + a BSD `date`/`stat` shim |
| idl-abstain-alarm (#3) | 1 red / 33 | selftest F uses BSD `date -r <epoch>`, whose fallback is a pinned `2026-07-19` | **33/33** with the shim |
| memory-nudge-ruling-shadow (#26) | 1 red / 16 | `stat -f %m f \|\| stat -c %Y f`: GNU `stat -f` is a filesystem stat, prints multi-line output and exits non-zero, so the fallback appends to garbage and every counter is skipped | **16/16** with the shim |
| session-index-fts-identity (#2 P1) | 6 red / 10 | BSD `date -v`, `stat -f '%m%t%z%t%N'`; Linux has `flock(1)`, the desk does not | **10/10** with the shim + `flock` hidden |
| session-index-sweep (#2 P0/P0b) | 14 red / 20 | same, plus tests 9-10 pin `PATH=/usr/bin:/bin` to force BSD `awk`/`stat`, and test 13 runs `plutil` on the launchd plist | **17/20**; the 3 left are those macOS-pinned cases |
| mem-neighbours (#10) | 3 red / 15 | BSD `date -r` in the `mt` helper; test 15 relies on `touch -t` moving APFS **birthtime** (`stat -f %B`) | **14/15**; the 1 left is the birthtime case |
| cc-memory-refs (#13) | 1 red / 8 | test 8 expects a `chmod 000` dir to be unreadable; the VM runs as uid 0 | unchanged; root reads it |
| cc-bats-admission | 10 red / 32 | load read via `sysctl -n vm.loadavg` (macOS) | unchanged |
| gate-home-isolation | 15 red / 23 | the gate clones `$HOME` with APFS `cp -Rc` and fails open without it | unchanged |
| deploy-live | 3 red / 168 | BSD `stat -f %m`; a launchd exec case; a SIGPIPE-timing fixture | **166/168** |
| ship-land | 10 red / 176 | `date -v -48H` via hard-coded `/bin/date`; a sysctl load ceiling; the shellcheck-ABSENT case (shellcheck was installed for this run) | unchanged |

The last four suites are land-gate infrastructure: an item sha touched them (the #6 pointer emitters
and the #6 outer-timeout refusal), but they are not TrueMemory deliverables. Their reds are the same
macOS dependencies. **Every item-owned suite is fully green on this machine, except cases that
require APFS birthtime, BSD-pinned `/usr/bin`, `plutil`, or a non-root user.**

The shim used: `date` translates `-r <epoch>` to `-d @<epoch>` and `-v±N<unit>` to a relative `-d`;
`stat` translates `-f FMT` / `-fFMT` to `--printf`, mapping `%m %z %B %N %t`. Both are scratch
files, and neither is committed.

## One finding outside this row's scope (not fixed here: frozen scope)

`scripts/idl-abstain-alarm.sh:716-717` builds selftest fixture timestamps with
`date -u -r "$NOW" … || echo 2026-07-19T04:00:00Z`. Nearby lines (242, 354, 931, 970) fall back to
`date -d "@…"` instead. On a non-BSD `date` the fixture is pinned to a date that falls further
behind every day, and selftest case F misclassifies. The desk is unaffected (BSD `date -r` answers
first); it matters only if this selftest ever runs off-box, e.g. in cloud CI. A one-line fix
aligns it with its neighbours.

## Disposition

Close `eb41b669e5e6` as done. The evidence is the plan's three DONE sections on
`origin/main` (last edit `7062884c`, "docs(plans): TrueMemory Wave C done — shas and learnings")
and the 49/49 ancestry assertion above. Wave D (build-later) and Wave E (experiments) are a
different scope, and the plan already marks them ready.
