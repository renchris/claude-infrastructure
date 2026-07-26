# Worktree Backlog Triage — 2026-07-26

Read-only analysis of the unlanded-patch backlog that accumulated while the landing gate was
effectively broken (P(green) ≈ 2.3%/attempt until Phase 1 landed as `1bc02f6f`, now ≈ 49.9%).
Nothing was deleted, landed, or removed by this pass except this document itself.

Base of every measurement: `origin/main` = `5d85e916` (fetched fresh at analysis time).

---

## Headline

| Bucket | Branches | Meaning |
|---|---:|---|
| **REDUNDANT** | **7** | No separate land needed (6 subsumed by a sibling tip, 1 exact duplicate) |
| **REAL** | **26** | Genuinely unlanded content |
| **SUPERSEDED** | **1** | Solved differently on trunk; carries an explicit DO-NOT-LAND marker |
| **STALE/UNCLEAR** | **0** | Every branch's intent was determinable from its commits |
| Total | 34 | |

**Genuinely real distinct patches: 138.**

The "296" (re-measured today as **311**) is a **row count** — it sums per-branch
`rev-list --count` and therefore counts shared history once per branch. The reduction:

| Measure | Count | What it removes |
|---|---:|---|
| Sum of per-branch counts | 311 | — (the reported figure) |
| Distinct commits (union across all 34) | 191 | shared history, chiefly the tm/* stack |
| Distinct **patch-ids** | 144 | the same patch carried on several branches |
| Minus patch-ids already on trunk | **139** | landed under a different SHA |
| Restricted to the 26 REAL branches | **138** | the superseded branch's single patch |

Monday's drain is **~138 patches across 26 lands**, not 296 across 34.

> The single biggest correction is not redundancy — it is **the tm/\* stack**. `tm/launchd ⊂
> tm/wtgc ⊂ tm/closure-a ⊂ tm/hooks ⊂ tm/hygiene ⊂ tm/gates ⊂ tm/growth` is a linear chain.
> Landing `tm/growth` alone lands all seven, collapsing 165 row-counted patches into 46 commits
> and 7 lands into 1.

---

## Method, and why the expected answer did not appear

The brief anticipated "a large fraction redundant" (28 of 62 last time). **Zero of the 34 branches
are redundant against trunk.** That is a real finding, not a broken test — it was validated
against three controls before being reported.

### Operator selection

| Operator | Verdict on the backlog | Why it is not sufficient alone |
|---|---|---|
| `rev-list --count origin/main..B` | 311 unlanded | Row count. Blind to shared history and to rebase-lands. This is the metric `bin/cc-teardown` uses, hence its false-DEFER. |
| `git cherry origin/main B` | 306 '+' / 5 '−' | Patch-id survives a clean rebase-land but **breaks on a squash-land** (proven below). |
| `git diff origin/main...B` | 0 empty | Answers the wrong question — three-dot diffs the *fork point*, so it stays non-empty even when the work is fully landed. Only detects the trivial ancestor case. |
| `git diff origin/main..B -- <paths>` | — | False-positives whenever trunk merely advances on those files. |
| **`git merge-tree --write-tree origin/main B`** | **0 redundant** | **Used.** Merged tree == trunk tree ⟺ the branch contributes nothing. Catches rebase-lands, squash-lands, and conflict-resolved lands alike. |

### Controls run before trusting the result

| Control | rev-list | `git cherry` | merge-tree |
|---|---|---|---|
| No-op (trunk vs itself) | — | — | tree == trunk ✓ |
| **Rebase-land** (last 5 trunk commits replayed as new SHAs) | says "5 unlanded" ✗ | 5 '−' ✓ | **REDUNDANT ✓** |
| **Squash-land** (same net content as 1 commit) | says "1 unlanded" ✗ | **1 '+' ✗** | **REDUNDANT ✓** |

The squash control is the decisive one: it is the case where patch-id fails and merge-tree
still returns the right answer. Having passed all three, merge-tree's "zero redundant" verdict
across the 34 is trustworthy.

**Interpretation:** work piled up because it *could not land*, not because it was already landed.
The backlog is real, and the gate fix was the correct intervention.

### Two measurement traps hit during this analysis (recorded so they are not re-hit)

1. **zsh does not word-split parameter expansions.** `for a in $BR` (where `BR` is a multi-line
   variable) iterates **once** with the whole blob as a single value — a containment matrix
   silently reported "no relationships" while `--independent` proved otherwise. `for a in $(cmd)`
   *does* split, which is why earlier loops worked and masked the bug. Use `$(...)` directly or
   `while read`.
2. **Empty pathspec degrades to unrestricted.** `git diff A..B -- $paths` with `$paths` empty
   silently diffs everything, manufacturing a false signal. Guard the empty case.

---

## Full classification — all 34

Evidence column gives the specific check that determined the bucket.

### REDUNDANT — 7 (no separate land required)

| Branch | Patches | Evidence |
|---|---:|---|
| `tm/gates` | 38 | `merge-base --is-ancestor tm/gates tm/growth` → true. Fully inside `tm/growth`. |
| `tm/hygiene` | 29 | Contained in `tm/gates`, `tm/growth`. |
| `tm/hooks` | 23 | Contained in `tm/gates`, `tm/growth`, `tm/hygiene`. |
| `tm/closure-a` | 13 | Contained in `tm/gates`, `tm/growth`, `tm/hooks`, `tm/hygiene`. |
| `tm/wtgc` | 9 | Contained in `tm/closure-a`, `tm/gates`, `tm/growth`, `tm/hooks`, `tm/hygiene`. |
| `tm/launchd` | 7 | Deepest in the stack — contained in all six above. |
| `fix/gate-home-iso-2` | 1 | Byte-identical to `fix/gate-home-isolation`: both diffs hash to patch-id `3211e401de5e…`, same subject "feat(gate): per-gate $HOME isolation via APFS clonefile (Phase 2a)". Land one, retire the other. |

These are redundant **as landing targets**, not as work — their content is real and reaches trunk
via `tm/growth` (or via the surviving twin). None is redundant against trunk in isolation.

**Per-branch `git cherry` split for the tm/\* branches** (requested — a mix is expected, not corruption):
every tm/* branch is `N−1` '+' and exactly `1` '−'. The single '−' is the shared already-landed
`worktree-gc` janitor patch (see the regression warning below). There is no partial-merge
scatter: the lead's branches are cleanly stacked, so the split is uniform.

### SUPERSEDED — 1

| Branch | Patches | Evidence |
|---|---:|---|
| `wt-a186c7d48637` | 1 | Head `5bd71624` "fix(cc-notify): accept the uuid prefix the lister actually prints" is pointed at by the ref **`superseded/cc-notify-prefix-DO-NOT-LAND`**. Trunk solved the same problem differently (strip-dashes-then-hex gate, landed `6991dfa3` + `65e6bb54`, which tolerates every partial-paste shape rather than one prefix width). This is the losing side of a parallel fix. **Do not land.** |

### REAL — 26

Contended-file flags: **SL** = touches `scripts/ship-land.sh`; **T** = number of `tests/` files.

| Branch | Patches | Files | +lines | SL | T | What it does |
|---|---:|---:|---:|:--:|---:|---|
| `fix/infra-perfection` | 55 | 125 | 8450 | | 29 | Broad infra-perfection sweep: reaper-horizon-lint scoring, growth-coverage-lint, gate-green resolution |
| `tm/growth` | 46 | 117 | 7984 | | 25 | Agent-team stack tip — growth-coverage-lint, plan-store keep-policy, statusline perf, claude-update cache |
| `feat/board-runnable-commands` | 19 | 23 | 1123 | **SL** | 9 | Operator Board renders `▶ run` commands by construction + `--lint` fail-closed gate |
| `wt-02ba4e52389a` | 8 | 29 | 2420 | | 9 | cross-session mail v3 P2–P4: mailbox lifecycle, Operator Board comms store, comms hygiene |
| `wt-1a941c28a079` | 8 | 16 | 911 | | 1 | TSV sweep suite: hermetic `$HOME`, widened guard, shellcheck debt clearance |
| `wt-a3d505ff2cef` | 8 | 24 | 610 | | 10 | comms safety: mailbox `.forward` on the crash path, suite-wide cc-notify stub, F5 three outcomes |
| `wt-6cab0ab3cb2f` | 8 | 13 | 1931 | | 4 | cc-gc franchise sweep: plist SSOT + activation closing the symlink gap |
| `wt-63929c8d6072` | 7 | 53 | 1217 | **SL** | 50 | bats-assert-lint closes the `(( ))` exempt form; end-to-end ship-land gate proof |
| `feat/relogin-executor` | 4 | 3 | 1425 | | 1 | cc-relogin phase A (gate, headless refresh, verify-by-effect). 3 of 4 patches already on trunk |
| `tm/closure-b` | 3 | 8 | 431 | | 5 | context-econ predicate parity + three-valued interactive answer; proc-identity argv pinning |
| `wt-8b90c69e0edd` | 3 | 4 | 661 | | 2 | postland KILLED vs HUNG as distinct states; bats-outlives-killed-child coverage |
| `feat/relogin-observability` | 3 | 5 | 862 | | 1 | `--relogin-status`, class-C blocker row, log rotation. 2 of 3 patches already on trunk |
| `docs/frontier-problems-2026-07-23` | 2 | 32 | 4020 | | 0 | Docs only — frontier-problem portfolio + stranded 2026-07-20 wave reports |
| `fix/postland-path-normalize` | 2 | 2 | 75 | | 1 | Normalize PATH before bats (the 0-green-stamp root cause) + revive dead assertions |
| `fix/gate-per-suite-keystone` | 2 | 3 | 136 | | 1 | bats-assert-liveness: the fixer turned a working negative assertion permanently red |
| `wt-fdf4161aeb28` | 2 | 2 | 52 | | 0 | Activation SSOT: `~/.claude-next` in the 09 readout wiring; SSOT copy of live-only 05 script |
| `fix/gate-home-isolation` | 1 | 2 | 529 | **SL** | 1 | **Phase 2a** — per-gate `$HOME` isolation via APFS clonefile |
| `feat/cc-mail` | 1 | 2 | 255 | | 1 | `cc-mail` operator read surface for cross-session mail |
| `wt-e280bbc8b6e4` | 1 | 3 | 328 | | 1 | cc-authbrowser injectable CDP port block — last unisolated global |
| `wt-761a546f939c` | 1 | 5 | 692 | | 2 | deploy-now link-parity report: landed files with no live symlink |
| `wt-3c6bf04ba842` | 1 | 4 | 205 | | 2 | handoff-fire bounds the last unbounded it2 forks (shim bypass) |
| `fix/iterm-sticky-custom-command` | 1 | 4 | 201 | | 1 | ⌘D no longer relaunches Claude — kills the sticky custom-command override |
| `fix/reaper-desk-registration` | 1 | 2 | 170 | | 1 | Desk-scoped stale-row heal in cc-reconcile; clears false Δ1 self-check page |
| `fix/origin-never-self-closes` | 1 | 4 | 113 | | 3 | An ORIGIN session never self-closes — only a fired peer may retire |
| `wt-9cc78e748e7e` | 1 | 2 | 51 | | 1 | test-hermeticity-lint `--selftest` false-RED through the deployed symlink path |
| `fix/activation-enable-before-bootstrap` | 1 | 4 | 31 | | 0 | Enable before bootstrap — a disabled label refuses the load with a bare EIO |

### STALE/UNCLEAR — 0

Every branch's intent was recoverable from its commit subjects. The `wt-<hex>` branches are
backlog-item worktrees keyed to backlog IDs; their commits are descriptive enough to classify
without guessing. Caveats that are *not* unclarity are listed under Unresolved.

---

## Landing order for the REAL bucket

Smallest-diff-first (standing rule: small diffs rebase cleanly and shorten the window in which
trunk moves underneath). `merge-tree` conflict status is shown because it predicts whether the
land needs manual resolution — 13 of 26 will conflict against current trunk.

| # | Branch | cmt | +lines | Conflicts vs trunk | Notes |
|---:|---|---:|---:|:--:|---|
| 1 | `fix/activation-enable-before-bootstrap` | 1 | 31 | clean | |
| 2 | `wt-9cc78e748e7e` | 1 | 51 | clean | |
| 3 | `wt-fdf4161aeb28` | 2 | 52 | clean | |
| 4 | `fix/postland-path-normalize` | 2 | 75 | clean | live session |
| 5 | `fix/origin-never-self-closes` | 1 | 113 | clean | live session |
| 6 | `fix/gate-per-suite-keystone` | 2 | 136 | clean | live session |
| 7 | `fix/reaper-desk-registration` | 1 | 170 | **conflict** | |
| 8 | `fix/iterm-sticky-custom-command` | 1 | 201 | **conflict** | |
| 9 | `wt-3c6bf04ba842` | 1 | 205 | **conflict** | |
| 10 | `feat/cc-mail` | 1 | 255 | clean | |
| 11 | `wt-e280bbc8b6e4` | 1 | 328 | clean | live session |
| 12 | `tm/closure-b` | 3 | 431 | clean | |
| 13 | **`fix/gate-home-isolation`** | 1 | 529 | clean | **ship-land.sh — see sequencing** |
| 14 | `wt-a3d505ff2cef` | 8 | 610 | clean | live session |
| 15 | `wt-8b90c69e0edd` | 3 | 661 | **conflict** | live session |
| 16 | `wt-761a546f939c` | 1 | 692 | clean | |
| 17 | `feat/relogin-observability` | 3 | 862 | **conflict** | only 1 of 3 patches is new |
| 18 | `wt-1a941c28a079` | 8 | 911 | clean | live session |
| 19 | **`feat/board-runnable-commands`** | 19 | 1123 | **conflict** | **ship-land.sh**; oldest fork (325 behind trunk) |
| 20 | **`wt-63929c8d6072`** | 7 | 1217 | **conflict** | **ship-land.sh**; 50 test files |
| 21 | `feat/relogin-executor` | 4 | 1425 | **conflict** | only 1 of 4 patches is new; partially superseded |
| 22 | `wt-6cab0ab3cb2f` | 8 | 1931 | **conflict** | carries stale `worktree-gc.sh` |
| 23 | `wt-02ba4e52389a` | 8 | 2420 | **conflict** | |
| 24 | `docs/frontier-problems-2026-07-23` | 2 | 4020 | **conflict** | docs-only; can land out of order (no code risk) |
| 25 | `tm/growth` | 46 | 7984 | **conflict** | **lands the whole tm/\* stack** |
| 26 | `fix/infra-perfection` | 55 | 8450 | **conflict** | largest; 143 behind trunk |

### `scripts/ship-land.sh` — mandatory sequencing

Three REAL branches modify the lander, which is itself under active change today (Phase 1 landed
into it as `1bc02f6f`; Phase 2a is queued). They **must** be serialized, in this order:

1. **`fix/gate-home-isolation`** (+124/−1 to ship-land.sh) — this *is* Phase 2a, the queued item.
   Land it first, while it is still the only lander change in flight.
   Its twin `fix/gate-home-iso-2` is byte-identical: land exactly one, retire the other.
2. **`wt-63929c8d6072`** (+28/−1) — adds an end-to-end ship-land gate proof plus 50 test files;
   it wants the lander's post-Phase-2a shape to assert against.
3. **`feat/board-runnable-commands`** (+13/−1) — smallest lander touch, oldest fork (325 commits
   behind), so it should absorb the accumulated drift last.

Landing any two of these in parallel will conflict in `scripts/ship-land.sh` directly.

### Other serialization requirements (same file, two or more REAL branches)

| File | Branches | Consequence |
|---|---:|---|
| `bin/cc-reaper`, `tests/cc-reaper.bats` | 4 | Serialize; single owner per land |
| `scripts/autonomy-sweep.sh`, `tests/autonomy-sweep.bats` | 4 | Serialize |
| `tests/ship-land.bats` | 4 | Serialize — pairs with the ship-land.sh order above |
| `scripts/worktree-gc.sh`, `tests/worktree-gc.bats` | 3 | **See regression warning** |
| `statusline.sh`, `install.sh`, `hooks/session-continue.sh` | 3 each | Serialize |
| `docs/activation/pending-activation/{05,09}-*.sh` | 3 each | Serialize; also implicated in the SSOT drift already flagged at session start |
| `scripts/{scratchpad-reaper,rotate-autonomy-logs,reaper-horizon-lint}.sh` | 3 each | Serialize |

308 distinct files are touched across the 26 REAL branches, so collisions are the norm rather
than the exception — landing strictly one-at-a-time is the safe default.

### ⚠ `worktree-gc.sh` regression risk

The `worktree-gc` janitor **already landed on trunk** as `4644820e`, and trunk has since evolved
the file to blob `1a9ba9c9`. Five branches (`wt-6cab0ab3cb2f`, `fix/infra-perfection`,
`tm/growth`, `tm/wtgc`, `tm/closure-a`) all still carry the *original* blob `3aed05ea`. Landing
any of them without rebasing that file onto trunk's current version will **revert trunk's later
fixes**. This is the concrete mechanism behind three of the five "already on trunk" patch-ids.
Resolve `scripts/worktree-gc.sh` in favour of trunk during each of those rebases.

### Estimated gate cost

Cost is expressed in **gate runs** (each run executes 141 bats suites in-lock); wall-clock per
run was not measured this session and is deliberately not asserted.

- 26 lands × ~2 attempts at the post-Phase-1 P(green) ≈ 49.9% ≈ **~52 gate runs**.
- The 13 conflicting branches need a rebase-and-resolve *before* the gate; a conflict exits
  ship-land **before** `run_gate`, which is a third state — gate-never-ran, not gate-red — and a
  pre-rebase green is not clearance.
- Retiring the 7 REDUNDANT branches saves ~14 gate runs outright, and `tm/growth` alone replaces
  what would have been 7 separate stack lands.
- Recommendation: land items 1–12 (all small, 9 of 12 clean) in one session to bank early wins
  and let the gate's improved P(green) compound, then take the ship-land.sh trio deliberately.

---

## Unresolved / could not determine

1. **Seven worktrees have live sessions right now** — `fix/gate-per-suite-keystone`,
   `fix/origin-never-self-closes`, `fix/postland-path-normalize`, `wt-1a941c28a079`,
   `wt-8b90c69e0edd`, `wt-a3d505ff2cef`, `wt-e280bbc8b6e4` (detected by cwd occupancy, not argv).
   Their content is **not frozen** — counts above are a snapshot and may grow. Re-measure
   immediately before landing any of them.
2. **Which twin of the gate-home-isolation pair is canonical.** The two are byte-identical, so
   the choice is arbitrary on content, but I could not determine which worktree the owning
   session intends to keep. `fix/gate-home-iso-2` sits in `wt-2a-relocate`, whose name hints it is
   the deliberate relocation and therefore the survivor — unverified. Operator's call.
3. **Backlog-ID ownership for the `wt-<hex>` branches.** Their intent is clear from commits, but I
   did not cross-reference the `cc-backlog` store to confirm which are claimed vs abandoned, so
   "should this land at all" is answered on content only.
4. **`superseded/infra-green-narrow-DO-NOT-LAND`** (`60d5f042`) is reachable from no live branch
   in the 34 — already isolated, no action, noted only so it is not rediscovered as a loose end.
5. **Conflict counts are from `merge-tree` against trunk as of `5d85e916`.** Every land moves
   trunk, so later items will conflict differently than shown. The order is correct; the
   per-branch conflict flags decay as the drain proceeds.
6. **Gate wall-clock per run** was not measured. The 141-suite count is from disk; minutes per
   run should come from an actual timed run before scheduling Monday around it.
