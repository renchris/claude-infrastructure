# The fifth lock: `bats` present, `bats` the wrong version, and a land that means nothing

2026-08-29 · measured inside a Claude Cloud VM (Ubuntu, x86_64), on `renchris/claude-infrastructure`
at `origin/main` · plan `docs/plans/BACKLOG_DRAIN_24_7.md`, backlog row `70f0001c657b`.

## The one-line finding

`scripts/cloud-venue-provision.sh` landed a rule — *"a version string is a claim about the binary,
the witness is a claim about this box"* — and applied it to **one of the two binaries it installs**.
The other, `bats`, it installed from the distro archive and then certified with `bats --version`. On
this venue that string read `Bats 1.10.0`, was true, and the box could not **load** three of its own
556 suites. Two of the three are directly selected by any change to `scripts/ship-land.sh`.

A suite the runner cannot load is a suite that never rendered a verdict, and in the shape measured
here it does so **silently**: `ship-land`'s smoke reads it as a cut, attests `partial`, and pushes.

## The mechanism

`bats` mangles each `@test` description into a shell function name. Before 1.11, two descriptions
that mangle alike are a fatal `Error: Duplicate test name(s)` for the **whole file**. Its
preprocessor is line-based, so a `@test "x"` inside a **heredoc** — fixture text a suite writes out
to drive its own subject — is counted as a test of the enclosing file.

Three suites here do exactly that, legitimately:

| suite | why it has heredoc `@test` lines |
|---|---|
| `tests/bats-shellcheck-lint.bats` | writes fixture `.bats` files to drive the lint it tests |
| `tests/git-identity-lint.bats` | same shape |
| `tests/qos-chokepoint.bats` | same shape |

## The corpus census — the whole tree, both runners, same box

`bats -c` gathers every named suite and executes none, which is exactly the phase that fails.

| runner | suites that load | the ones it refuses |
|---|---|---|
| 1.10.0 (Ubuntu archive — what the provisioner installed) | **553 / 556** | the three above |
| 1.13.0 (the version this repo pins) | **556 / 556** | — |

The pin is not a preference: `.github/workflows/hermetic.yml` installs `v1.13.0` from source and
says why in its own comment — *"pinned, not `brew install bats-core`: the verdict must be comparable
with the on-box verifier's, and every stamp it writes records bats 1.13.0"* —
and `scripts/postland-verify.sh` cites the same version for the gather step it depends on.

## Driven end to end on the LAND path, with a control

The reading above is a claim about `ship-land.sh`'s control flow, so it was driven rather than
argued. Cell: one comments-only commit to `scripts/git-identity-lint.sh` on a branch off
`origin/main` — `gate-select.sh --direct` maps it to **4** suites, one of them `git-identity-lint`.
`SHIP_LAND_SMOKE_BUDGET_S=420`, `--dry-run`, which runs the whole gate including the smoke and stops
before the push. Same commit, same box, same everything but the runner.

| runner | smoke | what the gate said about the diff |
|---|---|---|
| **1.10.0** | `PARTIAL` — `git-identity-lint.bats` cut TWICE (exit 1, **zero `not ok`** both times), GATE-KILLED at the suite | none. `reconciled onto origin/main + gate GREEN`, `would push HEAD` |
| **1.13.0** (control) | `green — 4 direct suite(s) in 35s` | all four ran |

The control's log contains **zero** occurrences of `Duplicate test name(s)`, which is what makes the
`PARTIAL` attributable to the runner rather than to the budget or to the diff.

This is byte-for-byte the polarity `cloud-venue-provision.sh`'s own header already documents for an
**absent** runner — `cut → partial → return 0`, `ship-land.sh:2136`'s *"a non-verdict never blocks a
land; the post-land verifier decides"*, vacuous on a venue that has no verifier. The new part is
that it arrives under a **green tool-presence line**, so nothing warns.

## The instrument's own limit, measured rather than assumed

`bats -c` means different things in the two versions. One fixture corpus of {a good suite, a suite
with a shell syntax error}:

| runner | result |
|---|---|
| 1.10.0 | prints `2`, **exit 0** — it counts `@test` lines and checks name uniqueness; nothing is sourced |
| 1.13.0 | `not ok 1 bats-gather-tests`, exit 1 — it actually gathers, so the broken file is caught |

The direction is the safe one: an old runner still fails the **duplicate-name** class, which is the
class that is silent at the land, so the probe can never report `READY` on the venue this document is
about. It simply cannot see the loud class until after the upgrade — by which point that class reds
the land on its own.

**Corollary, and it forced a change in the test fixtures.** No single ungatherable corpus exists
across bats versions: duplicate names are fatal to 1.10 and *allowed* by 1.13; a syntax error is
fatal to 1.13 and *invisible* to 1.10. A hard-coded bad fixture therefore convicts the tree on
whichever runner tolerates it — the false-conviction direction the plan's addendum warns against
buying to cure a silent ungating. `tests/cloud-venue-provision.bats` builds candidates and keeps the
first one **this** runner actually refuses, and skips with a named reason if neither works.

## What landed

- `scripts/cloud-venue-provision.sh`
  - `runner_state()` → `absent | stale | ok`, a **gather of this repo's own corpus** (`bats -c`),
    not a version string. `CC_VENUE_RUNNER_WITNESS` names a different directory, and every census
    line that used it says `witness FORCED by CC_VENUE_RUNNER_WITNESS` — the rule `CC_VENUE_HISTORY`
    already follows, so a forced value can never be read back as a measurement.
  - a seventh verdict token, **`STALE-RUNNER`**, ranked below `STALE-CHECKER` (a land the statics arm
    reds never reaches the smoke) and beside `UNGATED` — they are two values of one operand, and
    separate tokens because the cure differs: install one, replace the other.
  - `venue_verdict`'s second operand was a **boolean and is now a word**, because *present* and *can
    load this repo* are different questions and a flag carries only the first. An unrecognised
    word — the old `1` included — reaches `UNKNOWN`, never `READY`.
  - an upgrade arm symmetric with the checker's: clone `bats-core` at the repo's pinned tag, run its
    own `install.sh`, print the resolved commit as provenance, then **re-measure**. A **symlink**,
    not a copy, where the ambient PATH resolves the distro runner first — 1.13's launcher locates its
    libexec relative to the resolved path, so overwriting the distro file would point the new
    launcher at 1.10's internals.
  - the assertion arm now says what the runner **did** (`bats LOADS this repo — 556 suite(s) gather
    under Bats 1.13.0`) and, on `stale`, **names the suites** it could not load, bounded at five plus
    a count.
- `tests/cloud-venue-provision.bats` — five new cells, including the ratchet this whole class needed:
  *the runner executing this suite must gather the WHOLE corpus, not merely most of it.*

The version pin is deliberately **not load-bearing**: it decides what gets fetched and nothing about
the verdict, because the arm re-measures afterwards. A witness that still fails after the upgrade is
not news about the venue, and the second census says `STALE-RUNNER` again rather than falling through
to a clean one — which is also how the pooled `stale` arm separates *"the runner is too old"* from
*"a suite in this tree does not load under any runner"*, by acting rather than by guessing.

## Negative controls run before claiming any of it

| mutation | caught by |
|---|---|
| `runner_state()` stuck at `ok` | live cells 9 and 11 |
| `STALE-RUNNER` emitted as `UNGATED` | `--selftest` (3 cells) + live cells 9, 11 |
| fail-closed arm for an unrecognised runner state deleted | `--selftest`: the old boolean `1` and a typo both read `READY` |
| an ungatherable suite planted in `tests/` | the corpus ratchet cell, which printed the census and named the cause |

End to end, after reverting this box to the distro runner: `--check` read **`STALE-RUNNER`** on the
venue this file had previously certified `READY`; the full run fetched `bats-core v1.13.0`
(`3bca150ec86275d6d9d5a4fd7d48ab8b6c6f3d87`), re-read **`READY`**, and asserted
`bats LOADS this repo — 556 suite(s) gather under Bats 1.13.0`.

## What the three suites say now that they can speak

The point of the fix is that these three stop being invisible. Run off-box through
`scripts/offbox-run.sh suites` (fresh empty `$HOME`, `env -i`, 300 s bound each) under 1.13.0:

| suite | off-box verdict |
|---|---|
| `tests/git-identity-lint.bats` | **green — 23 ok / 0 not ok, 17 s** |
| `tests/bats-shellcheck-lint.bats` | red — 27 ok / **1** not ok (`an UNANALYZABLE own file still BLOCKS when the own-set is past the pipe-buffer regime`, rc 126) |
| `tests/qos-chokepoint.bats` | red — 45 ok / **2** not ok |

`git-identity-lint` is the sharpest of the three: a perfectly good suite that the land had been
skipping in silence. The other two carry findings that no run in this venue could previously reach.

## And the census the previous addendum asked for, for the ship-land selection

That addendum closed with *"only four ever ran inside the 420 s budget, so the off-box cleanliness of
this repo's suite corpus is unmeasured, not clean — that is the natural next cell."* Taken here for
the population that matters most, the **33** suites `gate-select.sh --direct` maps a
`scripts/ship-land.sh` change to (32 at the time; `cloud-venue-provision.bats` has since landed):

    green 22 · red 10 · cut 1

| not green | ok / not ok | note |
|---|---|---|
| `tests/cc-reaper.bats` | 141 / 51, rc 124 | hit the 300 s bound; matches the 51 the previous addendum measured on pristine trunk |
| `tests/operator-readout.bats` | 61 / 43 | already in `offbox-excluded.manifest` |
| `tests/ship-land.bats` | 138 / 17 | already in `offbox-excluded.manifest` |
| `tests/gate-home-isolation.bats` | 8 / 15 | |
| `tests/qos-rewrite.bats` | 27 / 13 | already in `offbox-excluded.manifest` |
| `tests/qos-chokepoint.bats` *(selected by qos changes, run separately)* | 45 / 2 | newly visible |
| `tests/bats-shellcheck-lint.bats` | 27 / 1 | newly visible |
| `tests/land-gate-cas.bats` · `land-gate-memo.bats` · `land-inflight.bats` · `tsv-field-collapse.bats` | 1 each | |
| `tests/test-hermeticity-lint.bats` | **cut** — rc 124 at the 300 s bound | proves nothing either way |

**The answer to the question as asked is: not clean.** Seven suites outside the manifest name a
failure in this venue, and one earns no verdict at all inside the bound.

⚠️ **No cause was measured for ANY of them, so `scripts/offbox-excluded.manifest` is untouched.** That
file's own contract is *"every entry is a MEASUREMENT, not a judgement"*, and the previous addendum
already refused to write a line for `cc-reaper` on the grounds that it had measured only THAT the
suite fails, never WHY. The same refusal applies to all seven; a census is the input to that work,
not the work.

## What this does NOT settle

- It says nothing about whether those three suites **pass** off-box once they load — only that they
  now get to run. That is the census question the plan's previous addendum named as the next cell,
  and it is separate.
- It does not touch `scripts/offbox-excluded.manifest`. The prior addendum measured
  `tests/cc-reaper.bats` red on pristine trunk in this venue and declined to write a manifest line
  without a cause; that is still owed, and this change does not supply the cause.
- It does not move `f85fce7c26f5`'s standing operator step: the cloud land arm's discriminator needs
  three reads that exist only on the operator's box
  (`scripts/cloud-land-arm-diagnose.sh`).
