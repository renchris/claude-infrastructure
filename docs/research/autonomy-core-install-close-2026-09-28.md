# Autonomy core install — close verdict (2026-09-28)

Backlog `ae6cd9b3a4a9` ("advance Autonomy core — a modular, cross-platform install for outside
users"), plan `docs/plans/AUTONOMY_CORE_INSTALL.md`. Run from a cloud VM whose checkout was trunk
(`git rev-list --count HEAD..origin/main` = 0 after `git fetch --unshallow`). Dispatcher vintage:
`git rev-parse origin/main:bin/cc-dispatch` = `dc9130372d63…`, the same blob as the brief, so the
dispatcher that fired this session is trunk's.

## Verdict: the work was already finished; the plan's frontmatter kept the item open

The plan's author closed it in `60f16325` by changing `status: open` to `status: done`. But `done` is
not in `scripts/find-plan.sh`'s closed vocabulary (`open|in-progress|complete|superseded`; it also
accepts `completed` and `in_progress`), so `find-plan.sh --status` read the plan as **`unknown`**.
Two things followed from that:

- `--list-open` leaves out only `complete|superseded`, so it kept listing the plan as open.
- `plan-phase-scan.sh --falsify` clause (a) needs `complete|superseded`. It fell through to clause
  (b), and (b) finds six level-2/3 headings with no DONE marker (Phase 0, Why, W1, W1 findings, /goal
  evidence, Status log). These are finished prose sections, not remaining work, so (b) returned
  exit 1 ("still live") and the item was re-dispatched.

Of 95 frontmatter `status:` lines in `docs/plans/*.md`, this was the only `done`.

**Cure:** frontmatter changed to `status: complete`. The stored probe now prints `FALSIFIED` and exits
0 (run in this tree). Branch `claude/fire-20260928T091751Z-53793-1` carries the change.

## Checking the work itself

| check | result |
|---|---|
| `install-core.sh`, `core/`, `tests/install-core.bats` are on origin/main | present (`a1623fd0`) |
| README § Quick start: autonomy core | present (`60f16325`) |
| `sha256sum install-core.sh` on trunk vs the README pin | `4e611c1f…4ac1`, matches |
| `bash core/build.sh --check` | `install-core.sh is up to date with core/` |
| `bats tests/install-core.bats` on **Linux 6.18, GNU userland, bash 5.2.21, jq + python3** | `1..16`, 15 ok, 1 skip (#10 looks for Homebrew gnubin; here the whole userland is GNU), 0 not ok |
| `HOME=$(mktemp -d) bash install-core.sh` | all 7 Verifying lines PASS, `READY`, rc 0 |
| `… --uninstall` | rc 0; keeps the user's backups, as designed |

This closes part of the W2 learning "Not done: a real WSL2 run … not by a Linux kernel". The suite and
the installer have now run on a real Linux kernel. They have **still not run on WSL2 itself**. WSL2
Ubuntu is a Linux kernel with GNU userland, so the remaining risk is limited to WSL-specific
filesystem and PATH quirks. It is not a reason to keep the plan open, and the plan's author already
accepted this gap when closing it.

## Follow-up worth filing (desk side, not done here)

`hooks/validate-plan-structure.sh` refuses an invalid `status:` only on a **new** plan. On an existing
plan it gives an advisory warning, so an edit to `done` went through. `done` is the most natural word
for a finished plan, and the next author who uses it will re-open a plan the same way. There are two
cheap fixes, and both must be applied in all three copies of the vocabulary (`find-plan.sh`,
`setup-plan-symlinks.sh`, `validate-plan-structure.sh`, which have no shared lib by design):

- accept `done` as an alias for `complete`; or
- refuse an out-of-vocabulary value on edits to existing plans, not only on new plans.
