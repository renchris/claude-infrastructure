# Autonomous session reaper — ACTIVATION runbook (C10: human-only)

The build is **complete, RED-proven, and landed**: `scripts/session-lifecycle-safety-gate.sh` is GREEN
(`3 met · 0 failed · 0 NOT BUILT`) — `bin/cc-classify` (7-cause classifier, 11 RED-proofs), `bin/cc-reaper`
(the safe sweep, 13 RED-proofs incl. all 5 never-reap guarantees), and the effect-verified `bin/cc-teardown`
actuator. What remains is **activation** — loading the standing loop — **which is C10 (human-only)**: an agent
must never self-install a daemon that can close sessions. The agent built + tested + wrote this runbook +
`docs/activation/autonomous-reaper.plist`; **the operator loads it.** The agent NEVER runs `launchctl load`.

## What it fixes

Teammates auto-reap (the TeammateIdle hook); **leads do not.** A handed-off lead whose `--recycle` pane-exit
fails lingers idle holding a pane until a human notices — incident 2026-07-17: session `9e5c5f1f` sat idle
**2.6h** after its successor had taken over and its work had landed. This closes the north star: an idle
handed-off lead is detected and closed **unattended, within minutes**, and *nothing else is ever killed*.

## The composition (each layer's blindness named + its covering layer)

| Layer | File | Does | Blind to → covered by |
|---|---|---|---|
| enumerate | `bin/cc-sessions` | list live sessions across 4 accounts from the registry | it2-ls-0 blindness → registry is the SSOT, not `it2 ls` |
| classify | `bin/cc-classify` | WHY idle → 1 of 7 causes from durable signals | successor/hang precision → the reaper re-checks work-landed + cc-teardown re-gates |
| decide+act | `bin/cc-reaper` | reap ONLY safe causes, checkpoint-first, dry-run default | a post-classify race → work-landed RE-checked at act-time; abort + WIP checkpointed |
| actuate | `bin/cc-teardown` | kill+close+**re-observe**, FAIL-LOUD on survivor | a blind 0-list → INDETERMINATE, never false "gone" (the fix) |
| standing loop | `docs/activation/autonomous-reaper.plist` | fire `cc-reaper sweep --reap` every 5 min | — (this file activates it) |

## Why launchd (not a hook, not the desk loop)

A **hook** (SessionStart/Stop/TeammateIdle) dies with its session and cannot run when *no* session is alive —
exactly when an orphaned pane needs reaping. The **desk loop** stops when the desk is closed or recycled, and
cannot reap the desk itself. **launchd** is OS-level, session-independent, survives logout, and fires on a
fixed interval regardless of who is watching — the only mechanism that runs "when no one is watching."
Precedent: `scripts/team-orphan-reaper.sh` already uses launchd.

## The safety contract (a reap requires ALL of these, independently)

1. `cc-classify` labels it **handed-off-lead** (a real `/handoff` fired AND a **LIVE** successor exists) or
   **finished-teammate** (a worktree/teammate session). A dead successor is refused; a bridge-session record
   is not a handoff.
2. Work is **LANDED** — clean tree AND nothing ahead of `origin/main` — **re-verified at act-time**, after
   the classify, to catch a race.
3. Idle ≥ the **settle window** (default 600s): the primary `--recycle` / TeammateIdle self-close had its
   chance first. The reaper is the BACKSTOP, never the first mover.
4. **Checkpoint-first**: any WIP is snapshotted to `refs/wip/<name>/LAST` (via `teammate-checkpoint.sh`)
   BEFORE any close. Losing uncommitted work is a P0 failure.
5. `cc-teardown` re-runs its OWN gate (work-safe + positive-done + self-guard + tty-exclusive + re-observed
   effect-verify). The `--done-evidence` is DERIVED from positive signals, never inferred from silence.

`active` / `owned-wait` / `coordination-hang` / `rate-limited` / `crashed` are **never** reaped — surfaced only.

## Activation

```sh
# 0. Prove the bar is green (do this first, every time):
scripts/session-lifecycle-safety-gate.sh          # ⇒ 3 met · 0 failed · 0 NOT BUILT

# 1. Watch it first — a DRY-RUN sweep shows exactly what it WOULD reap (writes nothing):
cc-reaper sweep                                    # expect: all live sessions → "keep … never-reap cause"

# 2. Install + load the standing loop (C10):
cp docs/activation/autonomous-reaper.plist ~/Library/LaunchAgents/com.chrisren.cc-reaper.plist
launchctl load  ~/Library/LaunchAgents/com.chrisren.cc-reaper.plist

# 3. (optional) trigger one sweep immediately instead of waiting for the 5-min interval:
launchctl start com.chrisren.cc-reaper
```

## Verify after activation

```sh
launchctl list | grep cc-reaper                    # loaded
tail -f ~/.claude/logs/cc-reaper.log               # per-sweep decisions (keep / would-reap / reaped)
cc-reaper sweep                                     # manual dry-run any time
```

## Rollback

```sh
launchctl unload ~/Library/LaunchAgents/com.chrisren.cc-reaper.plist
rm ~/Library/LaunchAgents/com.chrisren.cc-reaper.plist
```

Nothing destructive: the tools stay on trunk; unloading the agent stops all autonomous reaping. To pause
without unloading, raise the settle window (`CC_REAPER_SETTLE_S`) or edit the plist interval. `cc-reaper
sweep` (no `--reap`) is always safe to run by hand.
