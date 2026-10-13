# post-land HUNG `tests/gate-red-census.bats` @ 6269/19919: no seam to wrap, the premise is refuted

**Item:** cc-backlog `67003312b29a`, *"post-land HUNG: tests/gate-red-census.bats wedged at
6269/19919 @ a0145eb1261d — un-stubbed external seam, timeout-wrap it (NOT a peer pkill)"*.
**Worked:** 2026-10-13, off-box (cloud VM, Linux, GNU bash 5.2, bats via npm), branch
`claude/fire-20261013T121854Z-87141-1`.
**Verdict:** REFUTED as filed. The suite and its subject contain no external seam that can block,
so there is nothing to timeout-wrap, and the file passes its 30 cases in about 6 s here. No code
change is made. What the filing really records is one `confirm_hang` overrun of the 300 s bound on
the desk. A 6 s file taking over 300 s is a 50x slowdown, which says more about the box at that
moment than about this tree. That desk-side arm was **not re-run** (see "Unrun arm").

## Provenance

| check | result |
|---|---|
| shallow | `true`, so `git fetch --unshallow` ran before any trunk read |
| `git rev-list --count HEAD..origin/main` | **0**, so this tree is trunk (`04b58691`) |
| dispatcher vintage | `origin/main:bin/cc-dispatch` = `03e82d02b1fc…`, **EQUAL** to the blob that composed the brief |
| `a0145eb1261d` | a **tree** (stamps are tree-keyed), the tree of commit `26e83e2babbf` (2026-10-12, `fix(research-kit)…`). `git merge-base --is-ancestor 26e83e2b origin/main` → 0 |
| subject churn | `scripts/gate-red-census.sh` and `tests/gate-red-census.bats` were last changed **2026-08-11** (`cdc598a4`, `95730649`). `26e83e2b` touches neither. Both had been in every post-land corpus for two months before this one HUNG |
| falsifier | `postland-verify.sh --falsify-red tests/gate-red-census.bats 26e83e2b…` → NOT REFUTED (exit 1), silent. That is the safe direction, not a confirmation |

## What the file executes (the full seam census)

- **Fixture side** (`tests/gate-red-census.bats`): `HOME` and `LAND_LOG` are pinned to
  `$BATS_TEST_TMPDIR` in `setup()`. Its helpers call only `date -u -v-NH` (local clock math),
  `printf` (builtin), `seq`, and `stat -f` once (case 19). About 450 `$(ago …)` substitutions in
  total, 100 of them in case 1.
- **Subject** (`scripts/gate-red-census.sh`): argv parsing (every `shift 2` is preceded by
  `${2:-}`, and no test passes a trailing `--days`/`--window`, so the `shift-past-end` spin cannot
  arise here), one `date -u`, then a single `python3 - <<'PY'`. Its only I/O is
  `os.path.exists(LOG)` / `open(LOG)` on the pinned fixture file. There is no `subprocess`, socket,
  `stdin` read, `sleep`, `while` loop or `range()` loop anywhere in the program, so it cannot spin
  or wait.
- Six cases also pipe `$output` into `python3 -c 'json.load(sys.stdin)'`, which reads a finite
  `printf` and exits.

Nothing here waits on a network, lock, tty, daemon or the live `~/.claude`. "Timeout-wrap the seam"
has no seam to apply to. Wrapping `python3` in a bound would only turn a slow pass on a loaded box
into a red.

## Measurement (this VM)

`date -v` is BSD-only, so a PATH shim rewrote `-v-NH` → `-d "-N hours"` (one extra exec per call,
so the shim *overstates* the fixture cost).

| arm | wall |
|---|---|
| whole file, `bats --timing` | **5.67 s**, 30 cases, heaviest is case 1 at 0.80 s |
| 450 `$(date …)` substitutions via the shim | 1.72 s |
| 60 `python3` start-ups importing `json,calendar,time` | 1.85 s |

Case 19 (`it writes nothing to the store`) fails here only because `stat -f '%N %m %z'` is BSD
syntax. That is a platform artifact of this VM and unrelated to the hang.

The cost has no dominant term to cure. The bash32-parse-lint HUNG (`docs/research/bash32-lint-hung-2026-10-08.md`)
was one ~25k-fork loop worth 98% of its pass. Here the cost splits roughly evenly between the
fixture's `date` forks, the census's python start-ups and bats' own overhead, and the total is
about 900 forks. Even a 10x macOS/QoS fork penalty puts this file near 60 s. Reaching 300 s needs
the whole box to be slow by about 50x, and then any file in the corpus would have been the suspect.

## Unrun arm

The **desk** reproduction was not run: the file alone, under `confirm_hang`'s real conditions
(`/bin/bash` 3.2, `nice`/`taskpolicy` QoS, `TMPDIR=$RUN_TMP`, macOS `/usr/bin/python3` xcrun shim,
the box's load at the time). So this artifact refutes the **cause and remedy** as filed (an
un-stubbed seam to timeout-wrap). It does **not** prove the desk overrun was load and not
something macOS-specific. One macOS-only candidate was not tested: the `/usr/bin/python3` xcrun
stub rebuilding its cache under a fresh `TMPDIR`. The candidate stays open in the desk check below,
but it would be a property of the box, shared by every python-calling suite, and not of this file.

Desk falsifier, one command, which settles it either way:

```
cd <pristine checkout of 04b58691> && time timeout 300 bats tests/gate-red-census.bats
```

Completing well under 300 s, as it has on every post-land run since 2026-08-11, confirms the
overrun was environmental. A repeat 124 on a quiet box would be new evidence, so file it **with**
the load at the time (`uptime`, `top -l 2`) and a `sample` of the stuck `python3`/`date`.

## Disposition

No cure sha exists because there is no defect in this tree to cure. Close `67003312b29a` on this
artifact: premise refuted (no external seam), the effect was not reproduced off-box, and the desk
arm is named above.
