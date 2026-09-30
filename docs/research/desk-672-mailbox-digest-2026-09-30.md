# Desk mailbox 672 — digest of the pages nobody read (2026-09-08 → 2026-09-30)

Written by desk-reach.1 (backlog master plan 2026-09-30, W0). The raw box was archived, not deleted,
to `~/.claude/mailbox/archive/672.md.2026-09-30` (with its `.acked`/`.seen` cursors beside it).

## What happened

`~/.claude/cc-roles/desk` named pane 672 from 2026-09-09. That pane died, and nothing re-pointed the
role, because com.claude.desk-invariant (the job that repairs a stale desk role) has been `staged`
since it was ruled "run" on 2026-08-14. Every pager that addressed the desk kept writing into 672's
mailbox, which no process reads.

| | |
|---|---|
| lines in the box | 7,730 (2026-09-08 → 2026-09-30) |
| acked by the dead pane | 4,050 |
| **never read** | **3,680** |
| unread by day | 09-24 1,600 · 09-25 672 · 09-26 276 · 09-27 203 · 09-28 333 · 09-29 430 · 09-30 166 |

Unread pages by class (sender tag, normalised):

| count | class |
|---:|---|
| 628 | desk-sweep summaries (`NEW: N page(s), N alarm(s) …`) |
| 488 | lead-supervisor SUPERVISOR PAGE (stall candidates, past-threshold context) |
| 195 | PERMISSION-PENDING (a session blocked on a prompt) |
| 128 | PERMISSION-PENDING ESCALATED |
| 49 | handoff-fire COMPLETION pings |
| ~60 | cc-reaper SELF-CHECK / SURFACE |
| 43 | limit-recover (lr-fleet verdicts, CC-LR-UPGRADE skips) |
| 13 | fired peers that ENGAGED then went DARK |
| 12 | SESSION DEATH |
| 5 | **DATED PARK ARMED — 2aa99648bd80** |

## The one item still actionable

- **Dated park `2aa99648bd80`** (read acceptance A5/A6 of SUBAGENT_LIFECYCLE_ROOT_CAUSE) armed on
  2026-09-26 and paged five times, all into this box. `bash scripts/dated-park-arm.sh --report`
  still shows it ARMED on 2026-09-30. From this land on, the dated-park arm pages through
  `bin/cc-desk-page`, so its next daily page reaches the Notification Center.

Everything else is time-bound telemetry (stalls, prompts, completions) whose moment has passed; the
live instruments (`lead-supervisor`, `cc-reaper`, the sweep) re-raise anything still true.

## Consequence data carried over from backlog 4f31ab82428c (merged into f8b768eaaebd)

- `launchctl print gui/501/com.claude.desk-invariant` → "Could not find service"; its plist is in
  `~/Library/LaunchAgents` and byte-identical to `launchd/com.claude.desk-invariant.plist`.
- `idl.jsonl` role:desk lines: 09-2x delivered:true 0 / false 75; 09-29 true 0 / false 56; plus
  `page_send_failed` rc=124 entries (cc-notify cut at its caller's bound).
- `18-fleet-activate.sh` skips every `staged` row (`[ "$expect" = run ] || continue`), so the row's
  old instruction "run 18" could not load the job; only the manifest flip can (corrected in
  `launchd/fleet.manifest` beside the row).

## What changed (desk-reach.1)

- The role file was cleared (archived to `~/.claude/cc-roles/archive/desk.672.dead-2026-09-30`), so
  `lead-supervisor` stops writing into a dead box and every `cc-notify --role desk` fails loud (rc 3)
  instead of enqueueing silently. `lead-supervisor` already treats a role-less box as "the
  Notification Center is the primary surface".
- `bin/cc-desk-page` pages the desk and falls back to `lr-page.sh` (Notification Center, plus
  Pushover once `~/.config/lr-page/pushover.env` exists). The sweep's standing arms use it, and it
  writes one honest idl line per page: `delivered` (on some surface) and `read_proven` (a live
  desk took it) are separate fields.
- First proof, 2026-09-30T18:28:14Z: a test page wrote
  `{"tool":"cc-desk-page","notified":"role:desk","delivered":true,"channel":"notification-center"}`
  within 1 s.
