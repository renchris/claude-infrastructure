# Dossier 2

## Brief
```
In /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh, list every condition under which this Stop hook blocks a stop (emits a block decision or a blocking reason). For each give the line number, one sentence on the trigger, and the env var or kill switch that disables it, if any. numbers: {"conditions": <how many you listed>}.
```

## Returned headline
In Stop mode, session-continue.sh blocks a stop under 5 conditions, each by printing {decision:"block"} at one of three places (lines 1334/1336, 1199 and 895); its exit-2 paths are only reachable in CLI modes. (1) An agent-set sentinel (lines 1334/1336) is stopped by a kill-switch phrase or the CLAUDE_CONTINUE_MAX cap. (2) The mechanical uncommitted-own-files arm (armed at 1072, blocks at 1334/1336) is turned off by CC_MECH_CONTINUE=0 or capped by CC_MECH_MAX. (3) and (4) The ship floor for committed-but-unlanded or landed-but-not-live work (line 1199) is turned off by CC_SHIP_FLOOR=0 or capped by CC_SHIP_FLOOR_MAX. (5) The wake floor for an unarmed inbox watcher (line 895) is turned off by CC_WAKE_FLOOR=0 or held back by CC_WAKE_FLOOR_MAX and CC_WAKE_FLOOR_TTL_S. A kill-switch phrase in the user's last message also stops every floor.

## Returned numbers
`{"conditions": 5}`

## answer.md
# session-continue.sh: the conditions under which the Stop hook blocks a stop

Source: `/tmp/tokeff-regate/f2/tree/hooks/session-continue.sh` (1347 lines, read in full).
The `decision:"block"` sites were found with `grep -n 'decision:"block"\|exit 2'` (measured).

In Stop mode (no argument, JSON on stdin) every path ends `exit 0`. The hook blocks only by printing `{decision:"block",reason:...}`, and that JSON is written at three places: line 895 (wake floor), line 1199 (ship floor) and lines 1334/1336 (the armed-sentinel path). Those three sites cover **5 distinct trigger conditions**:

| # | Line(s) | Trigger (one sentence) | Env var / kill switch that disables it |
|---|---|---|---|
| 1 | 1334 / 1336 (emitted), `mark_blocked continue` at 1331 | A sentinel for this cwd exists because the agent ran `session-continue.sh set "<step>"`, and it survived three checks: no kill phrase (1230), no sid mismatch (1248), and the continuation count below the cap (1260). The hook then blocks with "🔧 Loose ends remain", folding in any pending inbox mail; with mail, line 1334 adds a `systemMessage`. | **Kill-switch phrase** in the last genuine user message (`KILL_RE`, line 348: "and stop", "no auto-continue", "just do X", "stop here", "come back to this", a bare "stop" or "halt"). This clears the sentinel at 1230-1235. **`CLAUDE_CONTINUE_MAX`** (default 8) is a cap: once `.count >= MAX` the hook clears the sentinel and allows the stop at 1260-1270, so `CLAUDE_CONTINUE_MAX=0` disables this path outright. `session-continue.sh clear` disarms it. A sid mismatch between the stored `.sid` and the current session also clears it (1248). |
| 2 | 1072 (arms the sentinel), then blocks at 1334 / 1336 | The mechanical 🔧 arm fires when no sentinel is armed, the wrap-ledger rung is 🔧 (line 1019), and `session_dirty_mine` reports at least 1 uncommitted file written by this session (1024-1030). It auto-writes a "Commit the N file(s)…" sentinel (1072) and falls through to the same block as #1 (see 1209 and 1223-1224). | **`CC_MECH_CONTINUE=0`** (line 941). **`CC_MECH_MAX`** is the per-session budget in `${f}.mech` (default 2; line 1064 allows the stop once it is spent), and `clear` spends it (line 261). The **kill-switch phrase** applies at 952 and again at 1230. It is also exempt for an Agent-Teams assignee (rc 0/2, line 970-982) and when a fresh teardown marker exists (985; `CC_TEARDOWN_DIR`, `CC_WF_TEARDOWN_FRESH_S`). `CLAUDE_CONTINUE_MAX` also caps each chain. |
| 3 | 1199 (reason 1187), printed at 1212 | Ship floor 📦: no sentinel is armed, the mechanical arm did not arm, the rung is 📦, and `session_unlanded_mine` confirms the committed-but-unlanded commits include this session's own writes (1148-1153). It fires once per HEAD sha. | **`CC_SHIP_FLOOR=0`** (1101). **`CC_SHIP_FLOOR_MAX`** caps it per session (default 2; 1176), and the HEAD-sha latch stops a repeat (1174). The **kill-switch phrase** applies at 1103. It also abstains for an assignee (1105-1111) or a fresh teardown marker (1112). |
| 4 | 1199 (reason 1189), printed at 1212 | Ship floor 🚀: same gating as #3, but the rung is 🚀 (landed but not live, converge budget breached) and `session_writes_paths` shows this session wrote something (1155-1157). The hook blocks with "converge via deploy-live.sh". | The same switches as #3: **`CC_SHIP_FLOOR=0`**, **`CC_SHIP_FLOOR_MAX`**, the HEAD-sha latch, the **kill-switch phrase**, and the assignee/teardown abstains. |
| 5 | 895 (emitted from `wake_floor`), printed at 1217 | Wake floor: no sentinel, and neither the mechanical arm nor the ship floor fired. The pane has a valid inbox id (`CC_PANE_ID`/`ITERM_SESSION_ID`) but no armed `cc-await-ping` watcher (614). The session is not headless, not an assignee or terminating, and not goal-live with mail pending. It is also the first idle of the session, or mail is pending, or dispatched custody rows are open (805). The attempt is within budget and the TTL (838-850). The hook blocks with "🔔 WAKE FLOOR — arm your inbox watcher". | **`CC_WAKE_FLOOR=0`** (604). **`CC_WAKE_FLOOR_MAX`** is the budget (default 2): at or above it the hook only warns via `systemMessage` and allows the stop (838). **`CC_WAKE_FLOOR_TTL_S`** is the minimum spacing (default 600 s; 847). The **kill-switch phrase** applies at 852. It abstains when the session is headless (`CC_PANE_ID` set and `ITERM_SESSION_ID` empty, 656), when a /goal is live and mail is pending (697), or when it is an assignee or has a teardown marker (776-797). Setting `CC_WAKE_FLOOR_TEARDOWN=0` turns *off* that last abstain, which makes blocking more likely, not less. |

Precedence: when no sentinel exists, the order is mechanical arm, then ship floor, then wake floor (1207-1222). At most one of them emits per Stop. An armed sentinel (#1) bypasses all three floors.

## Not counted: exit-2 paths, which are CLI modes only

An exit 2 from a Stop hook would also block. The script has three of them, and none is reachable on the Stop path, because Claude Code calls the hook with no arguments:
- line 116: `--why` reference-tier library missing (only on the `--why` argument);
- line 130: sentinel library cannot be sourced, but it exits 2 only for `set|clear|status`; with no argument it exits 0;
- line 216: unknown flag passed to `clear`.


## Tool calls (6) with the first 300 chars of each result
1. `Read: {"file_path": "/tmp/tokeff-regate/f2/tree/hooks/session-continue.sh"}`
   → 1	#!/usr/bin/env bash
2	# session-continue.sh — 🔧 loose-ends continuation loop (agent-set sentinel + Stop-hook actuator).
3	#
4	# WHY: a Stop hook fired on its own is SCOPE-BLIND — a shell script can't tell an
5	# in-scope loose end from an intentional pause or out-of-scope dirt, so a standalone
6	#
2. `Bash: {"command": "ls -la /tmp/tokeff-regate/f2/out/B01-r3/ 2>&1", "description": "Check output directory"}`
   → Exit code 1
ls: /tmp/tokeff-regate/f2/out/B01-r3/: No such file or directory
3. `Read: {"file_path": "/tmp/tokeff-regate/f2/tree/hooks/session-continue.sh", "offset": 675, "limit": 674}`
   → 675	  # ── FLIPPED FROM ABSTAIN TO "INSTRUCT THE SAFE FORM" (2026-08-16, goal-safe-2way-comms §4 C7) ────
676	  # The abstain above closed the starvation pole and left the session in the SPIN one: bare, blocking
677	  # every stop on an unmet goal, re-judging a world nothing has changed — 90 consecu
4. `Bash: {"command": "mkdir -p /tmp/tokeff-regate/f2/out/B01-r3 && grep -n 'decision:\"block\"\\|exit 2' /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh", "description": "Create output dir and locate block emits"}`
   → 46:# This is the hook that drives the loop: it emits {decision:"block"} up to CLAUDE_CONTINUE_MAX
66:# {decision:"block"} — came to write nothing at all. Measured over 978,400 IDL records across 17
116:  exit 2
127:  # never block on error (→ exit 0 allow); a CLI mode signals the failure to the agen
5. `Write: {"file_path": "/tmp/tokeff-regate/f2/out/B01-r3/answer.md", "content": "# session-continue.sh: the conditions under which the Stop hook blocks a stop\n\nSource: `/tmp/tokeff-regate/f2/tree/hooks/session-continue.sh` (1347 lines, read in full).\nThe `decision:\"block\"` sites were found with `grep -n`
   → File created successfully at: /tmp/tokeff-regate/f2/out/B01-r3/answer.md (file state is current in your context — no need to Read it back)
6. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B01-r3/answer.md", "headline": "In Stop mode, session-continue.sh blocks a stop under 5 conditions, each by printing {decision:\"block\"} at one of three places (lines 1334/1336, 1199 and 895); its exit-2 paths are only reachable in CLI modes. (1) An agent-`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
