---
status: in-progress
---

# Custody — only a TERMINAL HANDOFF-PING discharges

Scope (frozen): hooks/mailbox-drain.sh discharges custody only on a terminal HANDOFF-PING (done/landed/closed-class status), never on a progress, decision-gate or blocker ping; the back-channel trailer in scripts/handoff-fire.sh tells peers the exact terminal form; covered by bats that fail on the pre-fix code; landed via /ship and converged live.

Execution locus: L (lead-inline) — one hook edit, one trailer edit, one shared lib, one suite; no parallel split pays for itself.

## Measured defect (2026-09-28)

- `hooks/mailbox-drain.sh:587-618` (the W2 ping-receipt discharger, commit 6cedafbf5) runs
  `cc-custody return <slug>` for EVERY body line matching `HANDOFF-PING <slug>:`, whatever the
  status after the colon.
- `scripts/handoff-fire.sh:11478-11480` (back-channel trailer) tells peers to ping "On completion,
  at a decision gate, or on a blocker" with `HANDOFF-PING <slug>: <one-line status>`.
- So the first progress or blocker ping closes custody. Incident: fire-close-resume-custody opened
  23:25:45Z, returned 23:39:32Z by the drain on a "step 0 part 1 DONE" progress ping; the peer
  finished at 01:28Z, about 2 h later. Store row:
  `~/.claude/autonomy/custody/6cfca083a29d5a1910e2f48da299cb24.jsonl` (the return row has no why).
- Status census over `~/.claude/mailbox/*.md`: DONE 240, LANDED 98, LANDED+VERIFIED 52, CLOSED 14
  (terminal) vs W/WAVE 75, DECISION 16, BLOCKED/BLOCKER 14, PHASE 8, STEP 4, STATUS 4, PROGRESS 2,
  STARTED 2 (non-terminal). DONE also appears mid-status ("step 0 part 1 DONE"), so the match must
  be the status TOKEN right after the colon, not anywhere in the line.
- Consequence: `scripts/custody-deathwatch.sh` stops watching a peer that is only blocked, and the
  lead's close certificate turns green over an unreturned wave.

## Design

- One vocabulary, one file: `hooks/lib/handoff-ping-terminal.sh`, sourced by both the drain and
  handoff-fire's trailer. The status's FIRST whole token (case-insensitive) must be one of
  DONE · LANDED · LANDED+VERIFIED · CLOSED · COMPLETE · COMPLETED. "Whole" means the token ends at
  a character outside `[A-Za-z0-9+_-]`, so `LANDED-UNVERIFIED` and `DONE-ish` do not match.
- Non-terminal pings still deliver as mail and leave custody open; the drain says so in one line.
- Under-discharge is the safe direction: an off-vocabulary final ping still discharges via
  self-close (by marker) or the lead's `cc-custody return`. If the lib is missing, the drain
  discharges nothing.
- `scripts/cloud-return.sh`: `LANDED+VERIFIED` discharges (it also returns by marker itself);
  `LAND REFUSED` and `LANDED-UNVERIFIED` do not — matching cloud-return's own decision to leave
  custody open on those, which the pre-fix drain was silently overriding.

## Status

- [ ] lib + drain + trailer
- [ ] bats red on pre-fix, green after
- [ ] /ship, content-verify, converge
