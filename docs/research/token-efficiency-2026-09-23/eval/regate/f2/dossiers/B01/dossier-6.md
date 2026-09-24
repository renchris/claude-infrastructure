# Dossier 6

## Brief
```
In /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh, list every condition under which this Stop hook blocks a stop (emits a block decision or a blocking reason). For each give the line number, one sentence on the trigger, and the env var or kill switch that disables it, if any. numbers: {"conditions": <how many you listed>}.
```

## Returned headline
The hook blocks a stop only by emitting {decision:"block"} and exiting 0, never by exit 2 in Stop mode. There are 4 conditions. (1) An agent-armed sentinel, emitted at lines 1336/1334, is stopped by `clear`, a sid mismatch or the CLAUDE_CONTINUE_MAX cap. (2) The mechanical 🔧 arm for this session's uncommitted writes arms at line 1072 and blocks at 1336/1334; CC_MECH_CONTINUE=0 or the CC_MECH_MAX budget stops it. (3) The ship floor for 📦/🚀 own work, at line 1199, is off with CC_SHIP_FLOOR=0 or once CC_SHIP_FLOOR_MAX is spent. (4) The wake floor for an unarmed inbox watcher, at lines 894-895, is off with CC_WAKE_FLOOR=0 or limited by CC_WAKE_FLOOR_MAX and CC_WAKE_FLOOR_TTL_S. An operator kill-switch phrase in the last user message overrides all four.

## Returned numbers
`{"conditions": 4}`

## answer.md
# session-continue.sh: the conditions under which the Stop hook blocks a stop

File: /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh (1347 lines, read in full).

How it blocks: in actuation mode (no CLI arg, Stop JSON on stdin) the hook blocks only by printing
`{decision:"block",reason:...}` and then exiting 0. It never blocks with exit 2 in this mode. The
three `exit 2` paths (lines 116, 130, 216) are reachable only from the `--why`, `set`/`clear`/`status`
CLI arms, and line 130 explicitly exits 0 for the Stop path. At most one block is emitted per Stop.

There is one universal operator override: `kill_switch_active` (lines 348-395). It matches KILL_RE
against the last genuine (non-isMeta) user message in the transcript, e.g. "...and stop",
"no auto-continue", "just do X", "stop here", "come back to this", or a bare "stop"/"halt".
All four conditions below honour it.

## 1. Agent-armed continuation sentinel (the 🔧 loop). Emitted at lines 1336 / 1334
- **Line:** 1336 `jq -nc ... '{decision:"block",reason:$r}'`. Line 1334 is the same block with a
  `systemMessage` added when peer mail is folded in. Line 1331 `mark_blocked continue`.
- **Trigger:** a sentinel file for this cwd exists because the agent ran `session-continue.sh set "<step>"`.
  Its sid matches this session or is unknown, and the continuation count is below the cap. The hook
  then blocks and feeds back "Loose ends remain — do NOT stop yet. Next: <step>".
- **Disabled by:**
  - the kill-switch phrase (line 1230, which clears the sentinel and allows the stop);
  - `session-continue.sh clear` (lines 157-291);
  - a sid mismatch, where the stored `.sid` differs from the session sid (line 1248);
  - the cap `CLAUDE_CONTINUE_MAX` (default 8, line 1257). At the cap the hook clears the sentinel and
    allows the stop with a systemMessage (lines 1260-1269). Setting it to 0 makes every Stop take
    this path, so it effectively disables the loop.

  No dedicated on/off env var exists for this path.

## 2. Mechanical 🔧 arm (uncommitted files this session wrote). Emitted at lines 1336 / 1334
- **Line:** `mechanical_arm` (lines 940-1081) writes the sentinel at line 1072. Control falls through
  lines 1209/1223 into the armed path, and the same block at 1336/1334 is emitted.
- **Trigger:** no sentinel is armed and wrap-ledger reports RUNG=🔧 (line 1019). `session_dirty_mine`
  must find ≥1 dirty path written by this session (lines 1024-1030), and the per-session mechanical
  budget (`${f}.mech`) must not be spent (line 1064).
- **Disabled by:**
  - `CC_MECH_CONTINUE=0` (line 941);
  - the kill-switch phrase (line 952);
  - the budget `CC_MECH_MAX` (default 2, line 1055). `clear` marks this budget spent (line 261), and 0
    disables the arm;
  - stand-downs: a confirmed or undeterminable Agent-Teams assignee (lines 970-983), or a fresh
    teardown marker (line 985).

  After arming, it also inherits condition 1's sid-bind check and its `CLAUDE_CONTINUE_MAX` cap.

## 3. Ship floor (📦 committed-unlanded own work, or 🚀 landed-but-not-live). Emitted at line 1199
- **Line:** 1199 `jq -nc --arg r "$reason" '{decision:"block",reason:$r}'`, printed at 1212 after
  `mark_blocked ship-floor` (line 1211).
- **Trigger:** no sentinel is armed, the mechanical arm did not arm, and the ledger rung is one of:
  - 📦, where `session_unlanded_mine` confirms the unlanded commits contain this session's writes
    (line 1152);
  - 🚀, where `session_writes_paths` shows this session wrote something (line 1156).

  It also requires that HEAD's sha has not already been nudged (line 1174) and that the per-session
  budget is not spent (line 1176).
- **Disabled by:**
  - `CC_SHIP_FLOOR=0` (line 1101);
  - the kill-switch phrase (line 1103);
  - the budget `CC_SHIP_FLOOR_MAX` (default 2, line 1164; 0 disables it);
  - stand-downs: an assignee (lines 1105-1111), a teardown marker (line 1112), or the HEAD-sha latch
    (line 1174).

## 4. Wake floor (going idle with no inbox watcher armed). Emitted at lines 894-895
- **Line:** 894-895 `jq -nc ... '{decision:"block",reason:$r,systemMessage:$m}'`, printed at 1217
  after `mark_blocked wake-floor` (line 1216).
- **Trigger:** no sentinel is armed, and neither the mechanical arm nor the ship floor fired. The pane
  must have a valid inbox id with jq and the mailbox lib present, and no watcher may be armed
  (line 614). The idle must be this session's first, or have mail pending, or have open custody rows
  attributed to this pane (line 805). The attempt budget must not be exhausted (line 838), and the TTL
  must have elapsed since the last attempt (line 847).
- **Disabled by:**
  - `CC_WAKE_FLOOR=0` (line 604);
  - the kill-switch phrase (line 852);
  - the budget `CC_WAKE_FLOOR_MAX` (default 2, line 807). When the budget is exhausted the hook
    allows the stop with a systemMessage, and 0 disables the floor;
  - the spacing `CC_WAKE_FLOOR_TTL_S` (default 600 s, line 808);
  - these abstains:
    - a headless session, meaning CC_PANE_ID is set and ITERM_SESSION_ID is empty (line 656);
    - a live /goal with mail pending (line 697);
    - an assignee or teardown marker (lines 776-797). These abstains apply only while
      `CC_WAKE_FLOOR_TEARDOWN=1`, the default. Setting it to 0 removes them, so the floor blocks
      more often, not less.

## Non-blocking outputs (not counted)
These paths print only a `systemMessage` or stderr text and allow the stop:
- line 1266: cap reached;
- line 842: wake budget exhausted;
- line 853: wake floor sees the kill-switch;
- lines 659, 699, 792: abstain notices;
- line 1220: the wake floor's rc-0 output is passed through.


## Tool calls (4) with the first 300 chars of each result
1. `Read: {"file_path": "/tmp/tokeff-regate/f2/tree/hooks/session-continue.sh"}`
   → 1	#!/usr/bin/env bash
2	# session-continue.sh — 🔧 loose-ends continuation loop (agent-set sentinel + Stop-hook actuator).
3	#
4	# WHY: a Stop hook fired on its own is SCOPE-BLIND — a shell script can't tell an
5	# in-scope loose end from an intentional pause or out-of-scope dirt, so a standalone
6	#
2. `Read: {"file_path": "/tmp/tokeff-regate/f2/tree/hooks/session-continue.sh", "offset": 675, "limit": 674}`
   → 675	  # ── FLIPPED FROM ABSTAIN TO "INSTRUCT THE SAFE FORM" (2026-08-16, goal-safe-2way-comms §4 C7) ────
676	  # The abstain above closed the starvation pole and left the session in the SPIN one: bare, blocking
677	  # every stop on an unmet goal, re-judging a world nothing has changed — 90 consecu
3. `Bash: {"command": "mkdir -p /tmp/tokeff-regate/f2/out/B01-r7 && cat > /tmp/tokeff-regate/f2/out/B01-r7/answer.md <<'EOF'\n# session-continue.sh: the conditions under which the Stop hook blocks a stop\n\nFile: /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh (1347 lines, read in full).\n\nHow it blocks`
   → (Bash completed with no output)
4. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B01-r7/answer.md", "headline": "The hook blocks a stop only by emitting {decision:\"block\"} and exiting 0, never by exit 2 in Stop mode. There are 4 conditions. (1) An agent-armed sentinel, emitted at lines 1336/1334, is stopped by `clear`, a sid mismatch `
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
