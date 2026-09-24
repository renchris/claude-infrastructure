# Dossier 8

## Brief
```
In /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh, list every condition under which this Stop hook blocks a stop (emits a block decision or a blocking reason). For each give the line number, one sentence on the trigger, and the env var or kill switch that disables it, if any. numbers: {"conditions": <how many you listed>}.
```

## Returned headline
session-continue.sh blocks a stop under 5 conditions, always as decision:block JSON with exit 0. (1) An agent-set sentinel (lines 1334/1336) stops blocking on a kill-switch phrase, on `clear`, or at the CLAUDE_CONTINUE_MAX cap. (2) A mechanically armed sentinel for this session's own uncommitted files (armed at 1072, blocks at 1334/1336) is turned off by CC_MECH_CONTINUE=0 or CC_MECH_MAX. (3) The ship floor for committed-but-unlanded work (📦, line 1199) and (4) the ship floor for landed-but-not-live work (🚀, line 1199) are turned off by CC_SHIP_FLOOR=0 or CC_SHIP_FLOOR_MAX. (5) The wake floor (line 895) is turned off by CC_WAKE_FLOOR=0, CC_WAKE_FLOOR_MAX or CC_WAKE_FLOOR_TTL_S. The operator kill-switch phrase disables all five.

## Returned numbers
`{"conditions": 5}`

## answer.md
# session-continue.sh: the conditions under which the Stop hook blocks a stop

File: /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh (1347 lines, read in full).

In Stop-actuation mode (no CLI argument, Stop JSON on stdin) every path ends with `exit 0`. A block therefore always comes as `{decision:"block",reason:...}` JSON on stdout, never as exit code 2. There are three emit sites (lines 895, 1199 and 1334/1336). Between them they carry the 5 distinct trigger conditions below. At most one floor emits per Stop.

| # | Emit line | Trigger (one sentence) | Env var / kill switch that disables it |
|---|-----------|------------------------|----------------------------------------|
| 1 | 1334 (with mail systemMessage) / 1336 (plain); reason built at 1304 | An agent-armed sentinel (`session-continue.sh set "<step>"`) exists for this cwd, the last user message has no kill phrase (checked at 1230), the stored `.sid` does not mismatch the current session (1248), and `.count` is below the cap (1260). The hook then blocks with "🔧 Loose ends remain" plus any pending inbox mail folded in. | Kill-switch phrase in the last genuine user message (`KILL_RE`, line 348: "and stop", "no auto-continue", "just do X", "stop here", "come back to this", bare "stop"/"halt"). Also `session-continue.sh clear`, and the cap `CLAUDE_CONTINUE_MAX` (default 8). Setting it to 0 means no block ever fires. A sid mismatch also clears the sentinel. There is no dedicated on/off variable. |
| 2 | 1334/1336 (via the sentinel written at 1072 by `mechanical_arm`, called at 1209) | No sentinel exists, the wrap-ledger rung is 🔧, and `session_dirty_mine` finds uncommitted files this session wrote. The mechanical arm then writes a sentinel ("Commit the N file(s)...") and falls through into the armed path of condition 1, which blocks. | `CC_MECH_CONTINUE=0` (line 941). The per-session budget is `CC_MECH_MAX` (default 2, line 1055). Setting it to 0 stops the arm. `clear` spends that budget (line 261). The kill-switch phrase also stops it (952), as does the `CLAUDE_CONTINUE_MAX` cap. It abstains for an Agent-Teams assignee (rc 0 or 2, line 970) or a fresh teardown marker (985). |
| 3 | 1199 (reason at 1187) | Ship floor, 📦 case. No sentinel, the mechanical arm did not arm, the rung is 📦 (committed but not landed), `session_unlanded_mine` confirms the unlanded commits include this session's own writes, HEAD's sha has not already been nudged, and the per-session count is below the max. The hook blocks telling the session to /ship. | `CC_SHIP_FLOOR=0` (line 1101). `CC_SHIP_FLOOR_MAX` (default 2; setting it to 0 means no block). The kill-switch phrase (1103). It also abstains for an assignee or teardown (1105-1112), and fires only once per HEAD sha (1174). |
| 4 | 1199 (reason at 1189) | Ship floor, 🚀 case. Same path, but the rung is 🚀 (landed work not yet live because the converge budget was breached) and `session_writes_paths` shows this session wrote something. The hook blocks telling the session to run `scripts/deploy-live.sh`. | Same as #3: `CC_SHIP_FLOOR=0`, `CC_SHIP_FLOOR_MAX`, the kill-switch phrase, assignee/teardown abstain, and the per-sha latch. |
| 5 | 895 (reason 860-890) | Wake floor. No sentinel, and neither the mechanical arm nor the ship floor acted. The session has a valid pane/inbox id, and the mailbox lib and jq are present. No watcher is armed. It is the session's first idle, or mail is pending (`pend>0`), or dispatched custody rows are still open (`cust>0`). Budget and TTL still allow a fire. The hook blocks demanding `cc-await-ping` be armed; under a live /goal the command becomes the `--idle-scoped` form. | `CC_WAKE_FLOOR=0` (line 604). `CC_WAKE_FLOOR_MAX` (default 2; setting it to 0 means only the systemMessage, no block). `CC_WAKE_FLOOR_TTL_S` (default 600 s between attempts). The kill-switch phrase (852). It abstains for a headless session (`CC_PANE_ID` set without `ITERM_SESSION_ID`, 656), for a live /goal with mail pending (697), and for an assignee or fresh teardown marker (776-797). Those last two abstains depend on `CC_WAKE_FLOOR_TEARDOWN` staying 1: setting it to 0 turns the abstain off, so the floor blocks more often, not less. |

## Non-blocking exits that look like blocks (not counted)
- Line 116, `exit 2`: reached only with the `--why` argument (terminal reference mode), never in Stop actuation.
- Line 130, `exit 2`: reached only for the `set`/`clear`/`status` CLI modes when the sentinel lib cannot be sourced. Stop actuation takes the `*) exit 0` branch.
- Line 216, `exit 2`: an unknown flag passed to `clear`, which is also CLI only.
- Lines 842, 853, 1266 and similar emit only `{systemMessage}` (budget exhausted, kill switch, cap reached) and allow the stop.

numbers: conditions = 5


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
3. `Bash: {"command": "mkdir -p /tmp/tokeff-regate/f2/out/B01-r6 && cat > /tmp/tokeff-regate/f2/out/B01-r6/answer.md <<'EOF'\n# session-continue.sh: the conditions under which the Stop hook blocks a stop\n\nFile: /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh (1347 lines, read in full).\n\nIn Stop-actua`
   → (Bash completed with no output)
4. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B01-r6/answer.md", "headline": "session-continue.sh blocks a stop under 5 conditions, always as decision:block JSON with exit 0. (1) An agent-set sentinel (lines 1334/1336) stops blocking on a kill-switch phrase, on `clear`, or at the CLAUDE_CONTINUE_MAX ca`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
