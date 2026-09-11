# The install.sh fixture rename: one trunk commit, five stale bats fixtures

**Date:** 2026-09-11 · **Item:** cc-backlog `e7bdbf4f8343` (post-land RED,
`tests/install-templatedir-home-guard.bats::install.sh under a fixture HOME SKIPS the git config
write entirely` @ `823398c2e24a`) · **Measured off-box** on a cloud VM (Linux, GNU coreutils,
bash 5.2), tree at `origin/main` with `git rev-list --count HEAD..origin/main` = 0.

## Verdict

Real, reproducible, and **not a defect in the subject under test**. The guard
(`scripts/lib/real-home.sh` + install.sh's call site) behaves exactly as designed. The red is a
**stale test FIXTURE**, and the item named one suite of a five-suite population.

## Root cause

`367e42f2` ("the global SSOT moves off the repo root, which was loading it twice") renamed the
repo-side global-instructions file `CLAUDE.md` → `CLAUDE.global.md`. install.sh followed
(`install.sh:891-894`). The bats fixtures that stand up a throwaway repo for install.sh did not.

install.sh reads exactly **two** repo-root files with no existence guard in front of them —
`CLAUDE.global.md` and `statusline.sh`; every other `$REPO_DIR/<file>` read sits behind an
`[[ -f ]]`/`[[ -d ]]`. Under `set -euo pipefail` an absent one aborts the whole install:

```
Global instructions → .../cfg/CLAUDE.md
cp: cannot stat '.../repo/CLAUDE.global.md': No such file or directory
RC=1
```

Every affected test then reds on the same `[ "$status" -eq 0 ]` line, with the cause nowhere in the
output — the "three tests away from the cause, reading as a test bug" shape that
`install-templatedir-home-guard.bats`'s own header was written to record, now turned on that suite.

Note the direction: the repo root deliberately carries **no** `CLAUDE.md` (it would load as PROJECT
memory on top of the byte-identical user-memory copy — `.claude/CLAUDE.md`, backlog `c3647a090021`),
so a fixture doubling that name doubles a file the repo is pinned not to have. The **deployed**
copy is still `~/.claude/CLAUDE.md`, which is why `deploy-parity.bats`'s `$CC_PARITY_LIVE/CLAUDE.md`
writes are correct and were left alone.

## The population — the item named 1 of 5

A hand-found class is a sample. Measured across all nine `tests/install-*.bats`, before → after the
one-token fixture fix:

| suite | before | after |
|---|---|---|
| `install-templatedir-home-guard` (the filed one) | 6ok/4red | **12ok/0red** (2 tests added) |
| `install-fleet-activation` | 0ok/9red | **9ok/0red** |
| `install-worktree-refusal` | 3ok/5red | **8ok/0red** |
| `install-stale-refusal` | 4ok/6red | **10ok/0red** |
| `install-resident-reload` | 1ok/14red | 10ok/**5red** — see residual below |
| `install-mirror-symlink`, `install-skills-nested`, `install-staged-plist`, `install-wire-hooks` | green | green (not in the class) |

29 reds across four suites cured by one token each. Had only the filed suite been fixed, the other
four would have been dispatched as four more post-land RED rows for the identical cure.

The attribution arm: each sibling was first probed in a **scratch copy** (`sed CLAUDE.md →
CLAUDE.global.md`, run, discard) before the repo was touched, so "same cause" is a measurement and
not an inference from a matching symptom.

## Residual: `install-resident-reload` 5 red — a property of THIS VM, not of the diff

Not the rename class, and **unreachable on the operator's box**.
`scripts/lib/cc-common.sh::resident_image_stale` parses `ps -o lstart` with BSD `date -j -f`:

```
$ TZ=UTC LC_ALL=C date -j -f '%a %b %e %T %Y' "Tue Aug 18 11:36:03 2026" +%s
date: invalid option -- 'j'        # GNU coreutils 9.4
```

`start_s` is then empty and the function's documented fail-closed arm returns "NOT stale", so the
five behavioural staleness tests cannot pass here. Test 8 of that suite ("STRUCTURAL: the start-time
read pins BOTH TZ and LC_ALL") passes, because it is a static grep. postland runs on Darwin, where
`date -j` is native. **Left alone deliberately** — adding GNU-date support to a macOS-targeted
primitive is neither this item's scope nor an observed defect.

Same class, same session: `tests/bats-assert-liveness.bats` (6 red) and
`tests/bats-shellcheck-lint.bats` (2 red) fail here with a **byte-identical failing set on clean
trunk** (control arm: `git stash`, re-run, compare). Their own CONTROL test says why — "the two
bashes this grid is defined over are the versions it names", and this VM has no bash 3.2. Not
caused by, and not affected by, this diff.

## The fix, and the anti-rot guard

1. The five fixtures now write `CLAUDE.global.md`, and the stale comments that named `CLAUDE.md` as
   "an unconditional cp target" are corrected in place — that sentence is what made the wrong name
   look deliberate to every reader after the rename.
2. `install_fixture()` now prints install.sh's own error to stderr on a non-zero exit. Diagnostic
   only; the verdict stays with each caller's assertion, so it never decides a test.
3. Two appended tests in the filed suite (appended, so the header's `6/7/10` red-proof positions
   stay true):
   - **11, FIXTURE CONTRACT** — every repo-root file the fixture doubles still exists in the repo,
     by name.
   - **12, FIXTURE CONTROL** — the fixture is *sufficient*: install.sh completes under it.

Neither is decorative, and neither subsumes the other. Three mutants separate them:

| mutant | 11 | 12 |
|---|---|---|
| M1 — fixture reverts to the pre-rename `CLAUDE.md` (the actual incident) | **red** | **red** |
| M2 — repo renames the file again; fixture stays self-consistent | **red** | green |
| M3 — install.sh gains a new unconditional repo-root input, no fixture double | green | **red** |

M2 is the discriminator for 11 (12 cannot see a repo-side rename the fixture happens to match);
M3 is the discriminator for 12 (11 enumerates nothing about install.sh's reads, so it structurally
cannot catch an added input). Both mutants were re-run after a later edit to test 11's loop, since
an assertion change invalidates a prior mutation run.

The suite's two **documented** mutants were re-run to confirm the fixture change eroded nothing:
the predicate's `return 1` always-skip reds tests 1-5 (incl. test 2, the anti-vacuity arm it is
named for), and `if false` at install.sh's call site reds exactly 6/7/10, as the header claims.

Instrument scar worth recording: the first attempt at the predicate mutant used a `perl -0pi`
anchor with a semicolon the source does not have. It applied to **nothing**, and the resulting
"no reds" would have read as *the suite has no power*. The retry asserts the edit landed
(`git diff --numstat` = 1 insertion, and the added line printed) before believing the run — a
mutant anchored on a string that does not match proves nothing at all.

## Gates run (and what was a non-verdict, not a pass)

Clean: `bats-assert-liveness.py` (5 files), `bats-shellcheck-lint.sh` (5 suites, 0 blocking, 0
unanalyzable — shellcheck 0.9.0 installed first, because its "not installed" line is a
**non-verdict**, not a green), `bats-kill-guard-lint.sh`, `bats-shim-parity-lint.sh`,
`alarm-polarity-lint.sh` (rc 0). Every suite's plan line was read and matches its test count.

**Declared non-verdict:** `bash32-parse-lint.sh` — "`/bin/bash` is bash 5, not 3.x — NON-VERDICT".
Not treatable as a pass. The one bash-3.2-sensitive construct added here is the array expansion in
test 11, which is written in this repo's own `${a[@]+"${a[@]}"}` form (an empty array is UNBOUND
under `set -u` in 3.2 — the idiom `cc-common.sh` uses for the same reason), i.e. made safe by shape
rather than certified by the lint.

## Dispatcher vintage

`git rev-parse origin/main:bin/cc-dispatch` = `9109de61dc7add48cd94809d54e591af0bfe9021`, **equal**
to the blob that composed the brief. The dispatcher that fired this session IS trunk; no
landed-vs-live gap applies to this row.
