# reap-safety — activation snippet (P0-13 reap-guard TeammateIdle wiring)

**C10 ceiling:** the `reap-safety` agent builds + RED-proves `scripts/reap-guard.sh` (R-a birth-grace,
R-b effect-read, R-c no-silent-reap); the **operator** (or the `wiring-author` consolidation bundle)
performs the live wiring below. Nothing here edits `hooks/teammate-auto-shutdown.sh`, `settings.json`,
or a plist **in place** — this file is the hand-off. `reap-guard.sh` is a SEPARATE decision module the
live hook CALLS, so the fix lands + tests WITHOUT ever editing the live TeammateIdle hook in place
(the a18 L-9 finding: the module is built + selftest-GREEN but the hook **never calls it** — the
bare-idleness heuristic is still the live predicate; this snippet closes that gap).

## What was built (repo files, on `feat/desk-reap-safety`)

| Artifact | Kind | Needs wiring? |
|---|---|---|
| `scripts/reap-guard.sh` | standalone `decide` module (exit 0 = REAP · 10 = DEFER · 2 = usage) | **symlink** into `~/.claude/scripts/` + the hook insert below |
| `tests/reap-guard.bats` + `--selftest` | R-a/R-b/R-c RED-proofs | none (CI/regression only) |

## Interface contract (verified against the hook's available variables)

```
reap-guard.sh decide --worktree <wt> --member <id> --spawn-time <EPOCH-SECONDS> [--grace-s <secs>]
    exit 0  = REAP   (past grace, produced work products since spawn, clean tree, no busy marker)
    exit 10 = DEFER  (within birth grace | dirty | .teammate-busy | NO products since spawn)
    exit 2  = usage/fail-closed  → treat as DEFER (never reap on ambiguity)
```

The live hook (`hooks/teammate-auto-shutdown.sh`) already resolves everything `decide` needs at its
reap-decision point: `$WORKTREE` (manifest/glob resolution, :236-317), `$TEAMMATE_NAME` (the member,
:230-234), and `$SESSION_ID` (the teammate's own session). The gate is **additive** — it only ever
converts a would-be reap into a DEFER; it never turns a hook-DEFER into a reap.

## The birth-grace spawn-time source — registry `startedAt` (epoch-MS → seconds)

`--spawn-time` is **epoch-SECONDS** (reap-guard computes `age = $(date +%s) - spawn`). The session
registry writes `startedAt` in epoch-**MILLISECONDS** (`hooks/session-register.sh:69` —
`started=$(( $(date +%s) * 1000 ))`), so the snippet MUST divide by 1000. This is the same ms/s unit
seam fixed in `cc-classify` `find_successor` (P0-13 t1); do not pass raw `startedAt`.

**Fail-safe:** if `startedAt` is unresolvable (an unregistered teammate — a18 L-2) the snippet
defaults `spawn` to **now**, so `age = 0 < grace` ⇒ DEFER. And if raw milliseconds are passed by
mistake, `spawn` lands far in the future ⇒ negative age ⇒ still DEFER. Both wrong inputs fail toward
**never reaping**, never toward a wrongful reap. (Verified: `--spawn-time now → DEFER 10`;
`--spawn-time now*1000 → DEFER 10`.)

## Step 1 — land the branch, then symlink `reap-guard.sh`

```sh
# land feat/desk-reap-safety via the project-local /ship (content-verified) first, then:
ln -sfn ~/Development/claude-infrastructure/scripts/reap-guard.sh ~/.claude/scripts/reap-guard.sh
```

If the link is absent the insert below **degrades safely**: the `[ -x "$REAP_GUARD" ]` guard is false,
so the hook keeps its existing behavior (no new reaps, no errors) — the feature simply does not engage.

## Step 2 — the exact hook insert (operator applies; the agent never edits this hook)

Insert this block in `hooks/teammate-auto-shutdown.sh` **immediately after the Rule 3 dirty-tree defer
block** (the `fi` that closes `if $TREE_DIRTY && (( DEFER_COUNT < MAX_DEFERS ))`, currently `:347`) and
**before** `# Clear defer counter — we're proceeding to reap` (`:349`). At that point the hook has
decided to reap; this is the last gate:

```diff
   # Do NOT emit {"continue": false}; let the teammate keep working.
   exit 0
 fi

+# ── reap-safety birth-grace + effect-read gate (P0-13 reap-guard R-a/R-b) ──────────────────────────
+# The LAST gate before reap: a just-born teammate (within grace) or a clean tree with NO work products
+# since spawn is indistinguishable from a finished one by tree-state alone — DEFER, do not shut down.
+REAP_GUARD="${CC_REAP_GUARD_BIN:-$HOME/.claude/scripts/reap-guard.sh}"
+if [[ -n "$WORKTREE" && -x "$REAP_GUARD" ]]; then
+  # spawn-time = registry startedAt (epoch-MILLISECONDS) / 1000; unresolvable → now → DEFER (fail-safe)
+  _started_ms="$(cc-sessions --json 2>/dev/null \
+     | jq -r --arg s "$SESSION_ID" '.[] | select((.session_id // .sessionId)==$s) | .startedAt // empty' 2>/dev/null | head -1)"
+  if [[ "$_started_ms" =~ ^[0-9]+$ ]]; then _spawn_s=$(( _started_ms / 1000 )); else _spawn_s="$(date +%s)"; fi
+  if ! "$REAP_GUARD" decide --worktree "$WORKTREE" --member "$TEAMMATE_NAME" --spawn-time "$_spawn_s" >/dev/null 2>&1; then
+    log "defer $TEAMMATE_NAME (team=$TEAM_NAME): reap-guard DEFER (birth-grace / no-products-since-spawn)"
+    # Do NOT emit {"continue": false}; let the just-born teammate keep working.
+    exit 0
+  fi
+fi
+
 # Clear defer counter — we're proceeding to reap
 rm -f "$DEFER_COUNTER" 2>/dev/null || true
```

Notes for the operator:
- `member` MUST match the ref namespace the checkpoint writes (`refs/wip/<member>/…`) so R-b's
  products-since-spawn read resolves — the hook already uses `$TEAMMATE_NAME` for both, so pass it
  verbatim.
- `if ! "$REAP_GUARD" decide …` treats **any** non-zero (10 DEFER or 2 usage) as DEFER — the
  conservative direction. Only a clean exit 0 (REAP) lets the hook fall through to its shutdown.
- The gate is idempotent across the 3-4 TeammateIdle fires: within grace it DEFERs every fire; once
  past grace WITH products it permits exactly the reap the hook would already do.

## Verify (after wiring)

```sh
# the module resolves + selftests GREEN through the deployed link:
~/.claude/scripts/reap-guard.sh --selftest | tail -1
# the hook now references reap-guard at its reap-decision point:
grep -n 'reap-guard\|REAP_GUARD' ~/.claude/hooks/teammate-auto-shutdown.sh
# a just-born teammate DEFERs (records land under ~/.claude/reap-guard/ with decision=DEFER):
ls -t ~/.claude/reap-guard/*.json 2>/dev/null | head -3
```

## Rollback

```sh
# remove the hook insert (revert the operator edit); then drop the link:
rm -f ~/.claude/scripts/reap-guard.sh
# with the link gone, the `[ -x "$REAP_GUARD" ]` guard also no-ops the block even if left in place.
```
