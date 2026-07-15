# Reaper-birth-grace — ACTIVATION runbook (C10: human-only)

The reaper-safety build is **complete, RED-proven, and landed**; `scripts/reaper-safety-gate.sh` is GREEN
(`1 met · 0 failed · 0 NOT BUILT`). `scripts/reap-guard.sh` is a **standalone REAP|DEFER decision module**.
What remains is **activation — wiring the live hook to CALL the guard — which is C10 (human-only).** The
agent built + tested + wrote this runbook + `/tmp/reaper-safety-activate.sh`; **the operator runs it.** The
agent NEVER edits `~/.claude/hooks/teammate-auto-shutdown.sh` in place — that build-vs-activation split is
what keeps the C10 line where it is.

## What the guard does (the three guards the bare-idleness hook lacked)

`scripts/reap-guard.sh decide --worktree <wt> --spawn-time <epoch> --member <id> [--grace-s <secs>]`
→ **exit 0 = REAP** (safe) · **exit 10 = DEFER** (hold). Every decision writes an outcome record to
`~/.claude/reap-guard/` (`CC_REAP_RECORDS_DIR`).

- **R-a birth grace** — never reap within `--grace-s` (default 300s) of spawn. A just-born clean-tree
  teammate → DEFER. (A just-born worker is not a finished one.)
- **R-b effect-read** — reap only if there are WORK PRODUCTS since spawn (a commit newer than spawn, or a
  wip/checkpoint ref). A clean tree with no products yet is the just-born ≡ finished ambiguity → DEFER.
- **R-c abstention law** — every reap/defer writes an outcome record; the current hook reaps SILENTLY, and
  a silent reaper is the D9 shape with a body count. (It also preserves the hook's existing dirty-tree and
  `.teammate-busy` defers — the module only ADDS safety, removes none.)

Grace-window blindness (a genuinely-hung just-born within the window) is covered by the L2 wait-contract
DEADLINE + L1 exit-instant — another layer holds it (composition, desk-recorded).

## Activation (run `/tmp/reaper-safety-activate.sh`, opened in Cursor)

1. **Deployed verification** — `scripts/reap-guard.sh --selftest` fires GREEN (6/6) and the gate is green.
2. **Wire the live hook (YOU edit it — the agent never does).** In `teammate-auto-shutdown.sh`, immediately
   BEFORE its reap action, insert a call to the guard and take its verdict:
   ```sh
   # spawn-time from the P8 registry / team config.json (the member's registration epoch); worktree + member
   # from the TeammateIdle payload the hook already has.
   if ! "<REPO>/scripts/reap-guard.sh" decide --worktree "$WT" --spawn-time "$SPAWN_EPOCH" --member "$MEMBER"; then
     exit 0   # DEFER — the guard held the reap (birth grace / no products / dirty / busy)
   fi
   # else: exit 0 = REAP → fall through to the hook's existing reap action
   ```
   The guard is ADDITIVE: it can only turn a would-be reap into a DEFER, never the reverse.
3. **Spawn-time source** — the hook must pass the teammate's spawn/registration epoch. Take it from the P8
   live-session registry entry (its creation time) or the team `config.json` member record. If unavailable,
   fall back to the worktree's `.git` creation mtime — but a real spawn timestamp is preferred.
4. **Monitor the outcome records** — `~/.claude/reap-guard/reap-*.json` are the reaper's audit trail (R-c);
   a spike in `no-products` or `grace-held` defers is a signal (spawns racing the sweep), not an error.

## Verify after activation

```
scripts/reap-guard.sh --selftest        # 6/6 GREEN
scripts/reaper-safety-gate.sh           # 1 met · 0 failed · 0 NOT BUILT
# spawn a teammate, watch ~/.claude/reap-guard/ — the first sweep within grace logs a grace-held DEFER,
# not a reap (the incident is now structurally unreproducible).
```

## Rollback

Remove the inserted guard call from `teammate-auto-shutdown.sh`. Nothing else changed; the guard tool on
trunk is untouched. No data migration, nothing destructive.
