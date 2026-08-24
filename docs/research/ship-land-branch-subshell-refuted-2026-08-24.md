# ship-land.sh `BRANCH` in a `$( )` child — REFUTED; the bisect half was cured six days after filing

**Backlog item:** `354c73ebd400` — *"ship-land.sh: BRANCH assigned inside a `$( )` child so the EXIT
trap reads the parent's stale copy — PRE-EXISTING, and the postland bisect elects whichever land
touched the file as culprit."* Filed 2026-08-16T21:23:03Z. Verified against `origin/main` on
2026-08-24; the working tree was identical to trunk for all three files read
(`git diff origin/main -- scripts/ship-land.sh scripts/postland-verify.sh
scripts/subshell-cleanup-lint.sh` was empty).

**Verdict: the item is closed on a disproof plus a discharge, and no diff was written.** Its first
clause is false of `scripts/ship-land.sh` and has been false for the whole 300-commit window
readable here. Its second clause was true when filed and is now cured by a guard stronger than the
one it asked for.

---

## Clause 1 — `BRANCH` is never assigned in a subshell. REFUTED.

`scripts/ship-land.sh` assigns `BRANCH` at exactly three sites, one per entry point:

| line | function | assignment |
|---|---|---|
| 3639 | `main_locked` | `BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null \|\| echo '?')"` |
| 3869 | `main_precheck` | same |
| 3991 | `main_outer` | same |

All three are **parent-shell assignments that take their value from a command substitution** — the
child produces a string on stdout, the parent binds it. That is the *fix* pattern, not the defect.
`scripts/subshell-cleanup-lint.sh` says so in its own header, about three candidates an independent
census raised against it:

> all three are the SAFE shape — `BEAT_KEYS="$(_keys)"` assigns in the PARENT from the child's
> stdout, which is the fix pattern, not the defect.

The defect shape needs the assignment to happen *inside* a call tree the script enters through
`$( )` or a pipeline. None of the three functions is reached that way: `main_precheck` is called at
`ship-land.sh:3988`, and `main_locked` / `main_outer` at the top-level dispatch,
`ship-land.sh:4156` and `:4159`. Every one is a plain command in the parent shell.

The EXIT trap is independently defended anyway. `attest_land` — the row writer every terminal exit
reaches, including `_land_exit_trap` — resolves `BRANCH` lazily at `ship-land.sh:697-701` and floors
it to `?`, because under `set -u` an unset variable would kill the handler mid-`printf` and the exit
would attest nothing at all. So even a hypothetical stale `BRANCH` degrades one JSON field; it does
not cost a land.log row.

### Where the class really lived

The class the item names is real, and the instance it was named for is in a **different file**:
`postland-verify.sh`'s `do_bisect`, whose `prepare_worktree` call assigned the trap-consulted global
`WT_MINTED` two frames below a `c="$(do_bisect …)"`. A worktree cell leaked on every invocation
including success, collected only by the 8h age reaper.

Fixed in **`2850d77e`** (2026-08-06, ancestor of `origin/main`) — *ten days before this item was
filed* — which returns the culprit through the `BISECT_CULPRIT` out-parameter, deletes `do_bisect`'s
`printf` so the `$( )` shape fails loudly at any future caller, and ships
`scripts/subshell-cleanup-lint.sh` with that file's pre-fix blob as its positive control.

That lint is **clean on trunk today**, at default strictness and at `--shapes all`: 175 trap-installing
files parsed of 498 scanned, 0 findings. So the class is not merely absent from `ship-land.sh`, it is
enforced-absent repo-wide.

### The one `--loose` hit on ship-land.sh is a tokenizer artifact, both ends

`--loose` (which drops the destructive-read filter) reports:

```
✗ scripts/ship-land.sh:2174: HOME — assigned inside a pipeline child; the trap reads the parent's stale copy
    site:  gate_bats "$f" 2>&1 | tee "$log" >&2; rc1="${PIPESTATUS[0]}"
    chain: gate_bats   (assigns HOME at :1732)
    trap:  _land_exit_trap → gate_home_teardown reads HOME at :1583
```

Both anchors are misreads, and neither is a variable event:

- **`:1732` does not assign `HOME`.** It is
  `[[ -n "${GATE_HOME:-}" ]] && homeenv=(HOME="$GATE_HOME" CLAUDE_CONFIG_DIR="$GATE_HOME/.claude")`
  — an *array element* built for `env` to receive as an argument. The parent's `HOME` is untouched,
  which is the entire design of the isolation (see `c1eecb54e`, which extended the same array with
  `CLAUDE_CONFIG_DIR` precisely because overriding `HOME` has no purchase on an absolute path).
- **`:1583` does not read `HOME`.** It is the literal text `\$HOME-isolation dir` inside
  `gate_home_teardown`'s refusal `echo`. The teardown's actual subject is `GATE_HOME`, bound to a
  `local d` at `:1574`.

Default strictness correctly suppresses this, which is why the repo-wide default verdict is clean.
Recorded here so the next reader does not re-derive it from a `--loose` run.

## Clause 2 — the bisect's culprit election. TRUE WHEN FILED, DISCHARGED 2026-08-22.

"Elects whichever land touched the file as culprit" describes the `f323b427` incident of 2026-08-06:
`git bisect` takes both endpoints on trust and *declares* the tip without probing it whenever every
interior probe returns GOOD, so a pre-existing trunk red convicted a commit whose entire diff
(`tests/cc-queue.bats`) could not reach the convicted suite. Auto-revert then left trunk worse than
it found it.

`scripts/postland-verify.sh` now carries three culprit guards, applied in that order at
`:2142`, `:2175`ff and `:2188`:

1. **`bisect_reach_ok`** (`:1924`) — vetoes a candidate whose diff is docs-only and whose paths the
   subject file never names. Costs no bats run, and is deliberately one-sided.
2. **the tip confirmation** — re-runs the suite at the tip when `culprit = bad`, so a verdict
   produced by assumption rather than measurement cannot stand.
3. **`bisect_tip_differential_ok`** (`:2000`) — added by **`c897abf4`** (2026-08-22, ancestor of
   `origin/main`), *six days after this item was filed*. It probes the tip's **parent** after the tip
   confirms red, because "is the tip red" is not the question auto-revert acts on — "did the tip
   *make* it red" is, and a pre-existing trunk red is red at the tip too. Scoped to `below > 1` so it
   partitions the range with `bisect_floor_ok` rather than overlapping it, costing zero extra runs.

`c897abf4` was itself driven by a measurement the item did not have (backlog `e1c603144edc`, stamp
`c43aea4c7b9d`): a walk that named `0d50b76a214c` while the red's real source `8da2332e60ce` sat
inside the range 132 commits above the last-green. So this clause is not merely closed — it is
closed against a harder case than the one that was filed.

## What this says about the filing, not just the item

The two clauses share a file only in the filer's summary. The subshell class was `postland-verify.sh`'s
and had been fixed for ten days; the bisect misattribution was `postland-verify.sh`'s too. Neither was
ever `ship-land.sh`'s, and `ship-land.sh` is the only file the item cites. The most likely origin is a
postland RED that named a `ship-land.sh` land as culprit — i.e. clause 2 producing the *evidence* for
clause 1 — which is exactly the misattribution `bisect_tip_differential_ok` now prevents.
