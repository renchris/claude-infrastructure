---
name: desk
description: Convert THIS already-open session into the machine-wide orchestrator desk, in place — claim the desk role for this pane (desk-register) and adopt the canonical desk brief SSOT. Use for "become the desk", "make this session the desk", "take the desk role", "adopt the desk brief", or /desk. For a FRESH desk in a new pane use the `claude-desk` launcher instead; for an automatic replacement after a desk dies, scripts/desk-invariant.sh already fires one.
allowed-tools: Bash, Read
argument-hint: "[--check — report who holds the role, change nothing]"
---

# /desk — become the machine-wide orchestrator desk, in place

Converts the CURRENT session into the desk. Two mechanical steps, then you assume the role.

**The desk identity is two things, and both must be true:**

1. **The role file** — `~/.claude/cc-roles/desk` names THIS pane. It is not cosmetic: pages
   (`cc-reaper`), worker back-channel pings (`cc-dispatch`), `cc-announce`/`cc-await-ping` routing,
   `cc-classify`'s desk **never-reap**, `hooks/waiting-recycle.sh`'s idle gate and
   `scripts/desk-invariant.sh`'s existence sweep ALL follow that file. A desk that is not registered
   is invisible to the fleet and gets reaped as an idle pane.
2. **The brief** — the standing role definition, whose SSOT is
   `docs/templates/desk-boot-brief.md` in claude-infrastructure.

## Step 1 — claim the role for this pane

```bash
desk-register            # idempotent; --print to read the holder without writing
```

Expected output is one of `registered desk → <uuid>`, `already desk → <uuid>` (no-op), or
`reassigned desk: <old> → <uuid>`.

**If it prints `reassigned`, stop and check the previous holder is not still live** — two desks
means the older one silently goes deaf (pages and pings follow the role file). Verify with
`cc-notify --list` / `cc-sessions --json`; retire the stale pane with
`handoff-fire.sh self-close --terminal` from inside it. If the previous holder is genuinely gone,
carry on.

With `$ARGUMENTS` = `--check`: run `desk-register --print` only, report the holder, and STOP —
change nothing.

## Step 2 — adopt the canonical brief

Read the SSOT and follow it as your standing brief:

```
~/Development/claude-infrastructure/docs/templates/desk-boot-brief.md
```

It may already be in your context: `hooks/desk-brief-inject.sh` injects it at SessionStart for
whichever pane holds the role — but that fires at session START, and you are claiming the role
*mid-session*, so on this turn you must read it yourself. (From the next restart, recycle or
compaction onward it arrives automatically, because you now hold the role.)

## Step 3 — assume the role

Do exactly what the brief's **First three actions** say, without waiting to be asked:

1. **Orient** — `cc-blockers` (the Operator Blocker Board, SSOT for what needs the operator),
   `cc-board` + `cc-backlog list --open --blocked`, `cc-notify --list`, `/wrap`.
2. **Confirm the role** — step 1 above already did this.
3. **Drive** — every non-blocked track, to a terminal state.

Then hold the standing duties in the brief: drain the write-only wake dirs, ground every causal
claim with `desk-assert` before making it, filter benign supervisor zombie pages silently, shepherd
spawned sessions, and recycle yourself proactively at idle + high context.

Report back in one line: the role holder, what orientation surfaced (open/blocked counts, live
sessions), and the first track you are driving. Do not ask what to do.
