# The `CLAUDE.global.md` rename left five install.sh fixtures seeding the pre-rename name

2026-09-11 · cc-backlog `b61619e4bfe4` (post-land RED:
`tests/install-fleet-activation.bats::a STAGED label is never enabled and never bootstrapped
(the 2026-07-26 generator guard)`, convicted at `823398c2e24a`). Measured off-box on a Linux
cloud VM at `origin/main` (`git rev-list --count HEAD..origin/main` = 0, after `git fetch
--unshallow` — the dispatched checkout arrives at depth 50 and every trunk read inside that
horizon answers "never landed").

## Verdict

The RED is real and was **not** cured on trunk. The convicted sha is **innocent**; the
introducer is `367e42f2` and it is **four hours and thirty-five minutes earlier**.

| | commit | when | touches install path? |
|---|---|---|---|
| convicted by postland | `823398c2` *fix(lead-supervisor): an operator-adopted pane inside its hold is not a stall…* | 2026-09-10T12:52:24-05:00 | **no** — `scripts/lead-supervisor.sh`, `scripts/supervisor-e2e.sh` only |
| actual introducer | `367e42f2` *perf(claude-md): the global SSOT moves off the repo root, which was loading it twice* | 2026-09-10T08:17:11-05:00 | yes — `CLAUDE.md => CLAUDE.global.md`, `install.sh` |

Both are ancestors of `origin/main` (`git merge-base --is-ancestor`).

## Mechanism

`367e42f2` (backlog `c3647a090021`) moved the global SSOT off the repo root, because Claude Code
loads a root `CLAUDE.md` as PROJECT memory on top of the byte-identical user-memory copy — ~20.7K
tokens of pure duplicate every session. Only the **repo** side moved; the live side is still
`~/.claude/CLAUDE.md`, so `install.sh:893` reads:

```sh
run cp "$REPO_DIR/CLAUDE.global.md" "$CONFIG_DIR/CLAUDE.md"
```

Five bats suites seed a fixture repo for `install.sh` and each wrote the **pre-rename** repo-side
name. `cp` then fails under `set -e` at the global-instructions stage — which sits *before* every
section those suites measure. In `install-fleet-activation` the launchctl log is **empty** and all
9 tests die at `[ "$status" -eq 0 ]`, i.e. the suite was asserting about a loop that never ran.

`367e42f2` did update two suites for the rename (`tests/deploy-parity.bats`,
`tests/wrap-ledger.bats`). It missed the five that build an `install.sh` fixture.

The signature is diagnostic and worth recognising directly: **every test expecting `install.sh`
to succeed went red, and every test expecting a refusal stayed green** — the latter passing for
the wrong reason, since `status != 0` was being satisfied by an unrelated abort. A suite whose
refusal arm is green and whose success arm is uniformly red is not a logic defect in the subject;
it is the subject dying before the subject under test.

## Cure

One line per fixture — the repo-side seed takes the post-rename name. Anchors asserted to match
exactly once each, so no edit could silently no-op.

| suite | before → after |
|---|---|
| `tests/install-fleet-activation.bats` | 9/9 red → **0/9** |
| `tests/install-stale-refusal.bats` | 6/10 red → **0/10** |
| `tests/install-worktree-refusal.bats` | 5/8 red → **0/8** |
| `tests/install-templatedir-home-guard.bats` | 4/10 red → **0/10** |
| `tests/install-resident-reload.bats` | 14/15 red → **5/15** (residual is platform, below) |

Plan line (`1..N`) present and equal to the test count on every run — an absence of `not ok` in a
filtered read is not a pass.

### Controls

- **Positive control on the environment.** `install-mirror-symlink`, `install-skills-nested` and
  `install-wire-hooks` build the same kind of `install.sh` fixture and were **green throughout**,
  before and after. Linux is therefore not a blanket cause, and the red set is not "the VM".
- **Single-variable arm.** The target suite was fixed alone first and re-run: 9/9 → 0/9 with
  nothing else touched.
- **Population sweep.** All 18 suites in `tests/` that execute `install.sh` were enumerated and
  run, not just the ones that grep for `CLAUDE.md`: the other 13 are green. The fix is the
  population, not a sample of it.

## The residual in `install-resident-reload` is this VM, not a defect — do not "fix" it

Five cases still fail here (1, 4, 6, 7, 14). They are the ones that expect a staleness **report**;
every case expecting *no* report passes. `scripts/lib/cc-common.sh:155` reads a process start time
with BSD `date`:

```sh
start_s="$(TZ=UTC LC_ALL=C date -j -f '%a %b %e %T %Y' "$lstart" +%s 2>/dev/null || true)"
```

`date -j` is BSD/macOS-only. On this Linux VM it exits 1 (`date: invalid option -- 'j'`), the
`|| true` swallows it, `start_s` is empty and the probe fails closed — so no report is ever
emitted. Control, same box: the GNU spelling `date -d "Tue Aug 18 11:36:03 2026" +%s` returns
`1787052963`, proving `date` itself is fine and only the BSD flag is missing.

These five are expected green on the operator's macOS box and are **outside** this item. Rewriting
that line to GNU syntax would break the target platform to satisfy the measuring box.

## Carry-outs

- **A post-land conviction names a commit; read the assertion's own output first.** Here the
  convicted diff touches no install path at all, and the range walk could not have known: every
  commit in the window reaches these suites. The introducer is identified by what `install.sh`
  reads, not by what the range contains.
- **A rename that moves one side of an asymmetric pair rots every fixture that seeded the other.**
  `CLAUDE.global.md` (repo) → `CLAUDE.md` (live) is exactly that shape, and the fixtures carried
  the belief in a **comment** — *"CLAUDE.md and statusline.sh are unconditional cp targets"* — which
  nothing executes. True when written, false 4.5 hours later, and the comment is what the next
  reader trusts.
- **Off-box, attribute every red before curing it.** Three of the eight install suites were green
  on this VM and five of fifteen resident-reload cases are red for a reason that has nothing to do
  with the item. Without the platform control both directions are available and each looks
  plausible.

## Re-measure

```sh
bats tests/install-fleet-activation.bats tests/install-stale-refusal.bats \
     tests/install-worktree-refusal.bats tests/install-templatedir-home-guard.bats \
     tests/install-resident-reload.bats
```

On macOS all five are expected fully green. On Linux expect the five `date -j` cases in
`install-resident-reload` and nothing else.
