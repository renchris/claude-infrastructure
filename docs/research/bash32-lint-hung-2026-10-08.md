# post-land HUNG `tests/bash32-parse-lint.bats` @ 655/18890: a fork storm, not a wedge

**Item:** cc-backlog `aeca00c34eaf`, *"post-land HUNG: tests/bash32-parse-lint.bats wedged at
655/18890 @ 19ebfca2bbce: un-stubbed external seam, timeout-wrap it (NOT a peer pkill)"*.
**Worked:** 2026-10-08, off-box (cloud VM, Linux, GNU bash 5.2), branch
`claude/fire-20261008T081912Z-9848-1`.
**Verdict:** the effect (the file alone overran `POSTLAND_FILE_TIMEOUT_S=300` in `confirm_hang`)
is real, and this branch cures it. The stated cause and remedy are both refuted: no external seam
blocks, and wrapping it in a timeout would turn a slow pass into a permanent red.

## Provenance

| check | result |
|---|---|
| shallow | `true`, so `git fetch --unshallow` ran before any trunk read |
| `git rev-list --count HEAD..origin/main` | **0**: this tree is trunk (`ba1fdc86c907`) |
| dispatcher vintage | `origin/main:bin/cc-dispatch` = `03e82d02b1fc…`, **EQUAL** to the blob that composed the brief |
| `19ebfca2bbce` | a **tree** (stamps are tree-keyed). Its commit is `bc7894fe21e5`, a docs-only commit, so the tree's whole-repo population is the subject, not that diff |
| cure already on trunk? | no. `scripts/bash32-parse-lint.sh` and its suite have one commit each (`ec3f7c0f`) |

## Mechanism

Case 1 of the suite (`the tree as it stands is CLEAN`) scans **every tracked file** (8,499 at
trunk). For each one, `_is_shell_script` ran `first="$(LC_ALL=C head -1 "$f" | LC_ALL=C tr -d '\0')"`,
which is a subshell plus two execs, about 25k process creations a pass. Its only external calls
are `git ls-files`/`git rev-parse` (local, non-blocking) and `bash -n` on the 856 scripts that
qualify. Nothing waits on a network, a lock or a tty.

Measured here, idle VM, `bash` 5.2 standing in for 3.2 through a wrapper that answers the version
probe with `3` (the 3.2-specific parse is not the cost; see below):

| arm | wall |
|---|---|
| whole lint, trunk | **40.9 s** |
| the `head \| tr` population loop alone | **42.4 s** |
| the same loop with builtin `read -r -n 256` | **0.54 s** |
| `bash -n` over the `*.sh` subset | 3.3 s |
| whole lint, this branch | **7.2 s** |

So about 98% of the pass was the population test, not the parse. On macOS, fork+exec costs several
times what it costs on Linux, and post-land runs the file under utility QoS on a loaded box. That
lifts a 41 s pass past the 300 s hang-confirm bound, which matches the filed `REPRODUCED` HUNG.

## Cure

`_is_shell_script` reads the first line with the builtin `IFS= read -r -n 256 first < "$f"`
(no fork). Equivalence, both measured:

- the selected population over the real tree is **byte-identical**: 856 files, `cmp` equal;
- edge fixtures (bash shebang, `.bats` with bash shebang, `env sh`, `env zsh`, python, empty file,
  shebang with no trailing newline, binary with an embedded NUL) give identical Y/N vectors under
  old and new code. `read` drops NULs silently, so binaries neither warn nor match.

`shellcheck` (bare, as the land gate runs it) is clean before and after.

## Unrun arm

This VM has no bash 3.2 (the egress proxy refuses ftp.gnu.org and its mirrors), so
`tests/bash32-parse-lint.bats` **SKIPs 7/7** here by its own declared precondition. That means
the **desk timing under real `/bin/bash` 3.2 + QoS was not measured**, and neither were the
RED-PROOF and REAL-ARTIFACT cases. The diff changes only population selection, which is proven
identical above, so those cases' verdicts cannot move. The desk lander's gate run is the first
real-3.2 execution, and it should show case 1 well under 300 s.
