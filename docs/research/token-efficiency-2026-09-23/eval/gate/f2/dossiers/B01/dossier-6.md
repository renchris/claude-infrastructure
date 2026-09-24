# Dossier 6

## Brief
```
In /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh, list every condition under which this Stop hook blocks a stop (emits a block decision or a blocking reason). For each give the line number, one sentence on the trigger, and the env var or kill switch that disables it, if any. numbers: {"conditions": <how many you listed>}.
```

## Returned headline
session-continue.sh blocks a stop in 5 cases, all through a decision:block JSON with exit 0. (1) A continuation the agent armed with `set`, emitted at :1334/:1336, bounded by the CLAUDE_CONTINUE_MAX cap (8 by default). (2) The mechanical arm for uncommitted files this session wrote, which arms at :1072 and blocks through the same lines, turned off by CC_MECH_CONTINUE=0. (3) and (4) The ship floor for 📦 unlanded or 🚀 not-live work, at :1199, turned off by CC_SHIP_FLOOR=0. (5) The wake floor for going idle with no inbox watcher, at :895, turned off by CC_WAKE_FLOOR=0. An operator kill-switch phrase (KILL_RE at :348) overrides all five, and the exit-2 paths at :116, :130 and :216 only run in CLI mode, so they never block a stop.

## Returned numbers
`{"conditions": 5}`

## answer.md
# session-continue.sh: the conditions under which the Stop hook blocks a stop

File: `/tmp/tokeff-gate/f2/tree/hooks/session-continue.sh` (1346 lines; line count measured with `wc -l`). I read the whole actuation path, lines 306-1346, and the CLI-mode exits.

In Stop mode the hook blocks only by printing `{decision:"block", reason:...}` on stdout. Every actuation path ends with `exit 0` (header :36-37; :1213, :1218, :1346). There are three places that print a block: the ship floor (:1199), the wake floor (:895) and the armed-sentinel continuation (:1334/:1336). Two different triggers lead into the continuation block, and the ship floor has two versions with different triggers. That gives **5 blocking conditions**.

Order of evaluation (:1203-1225). If no sentinel file exists, the hook tries the mechanical arm first, then the ship floor, then the wake floor. At most one floor prints per Stop. If the mechanical arm arms the sentinel, control falls through to the armed path. If a sentinel already exists, the floors are skipped.

**Kill switch shared by all five.** An operator phrase in the last real (non-`isMeta`) user message turns off every condition. The phrases match `KILL_RE` at :348: "and stop", "no auto-continue", "just do X", "stop here", "come back to this", or a bare "stop"/"halt". The check is `kill_switch_active` (:391). Each condition calls it: sentinel path :1230, mechanical arm :952, ship floor :1103, wake floor :852.

| # | Condition | Block emitted at | Trigger (one sentence) | Env var / kill switch that disables it |
|---|---|---|---|---|
| 1 | Agent-armed 🔧 continuation (sentinel set via `session-continue.sh set`) | :1334 (with a peer-mail systemMessage) / :1336 (without one); marker at :1331 | A sentinel file for this cwd exists, it was armed by this session (no sid mismatch, :1248) and the continuation count is below the cap (:1260). The hook then blocks with "Loose ends remain — Next: <step>" and prepends any pending inbox mail (:1311-1318). | Kill-switch phrase (:1230) clears the sentinel and allows the stop. `session-continue.sh clear` disarms it. The cap `CLAUDE_CONTINUE_MAX` (default 8, :1257) allows the stop once reached, so `CLAUDE_CONTINUE_MAX=0` turns this block off entirely. A sid mismatch also clears it (:1248-1253). There is no dedicated on/off flag. |
| 2 | Mechanical 🔧 arm: uncommitted files this session wrote | Arms the sentinel at :1072, then blocks through the same :1334/:1336 | No sentinel exists, the wrap-ledger rung is 🔧 (:1019), and `session_dirty_mine` attributes at least one dirty path to this session (:1024-1030). The hook then writes the sentinel "Commit the N file(s) you edited…" and falls through to the continuation block. | `CC_MECH_CONTINUE=0` (:941). The per-session budget `CC_MECH_MAX` (default 2, :1055) caps it, so `CC_MECH_MAX=0` turns it off. Kill switch (:952 and again at :1230). It stands down for a confirmed or undeterminable Agent-Teams assignee (:970-983) and when a fresh teardown marker names this session (:985). Once armed, the `CLAUDE_CONTINUE_MAX` cap applies as in #1. |
| 3 | Ship floor 📦: committed but unlanded work this session wrote | :1199 (reason text at :1187); printed at :1210-1213 | No sentinel was armed, the ledger rung is 📦 (:1130), trunk is known, and `session_unlanded_mine` says the unlanded commits hold this session's own writes (:1148-1153). It fires once per new HEAD sha (:1174), up to the per-session cap. | `CC_SHIP_FLOOR=0` (:1101). `CC_SHIP_FLOOR_MAX` (default 2, :1164) caps it, so `=0` turns it off. Kill switch (:1103). Assignee abstain (:1105-1111). Teardown-marker abstain (:1112). |
| 4 | Ship floor 🚀: landed work that is not live (the converger breached its budget) | :1199 (reason text at :1189); printed at :1210-1213 | No sentinel was armed, the ledger rung is 🚀 (:1130), and `session_writes_paths` finds that this session wrote something (:1155-1157). The hook blocks with an instruction to run `scripts/deploy-live.sh`. Same per-sha latch and cap as #3. | Same as #3: `CC_SHIP_FLOOR=0`, `CC_SHIP_FLOOR_MAX`, kill switch (:1103), assignee and teardown abstains. |
| 5 | Wake floor: going idle with no inbox watcher armed | :895; printed at :1215-1218 | No sentinel was armed and neither the mechanical arm nor the ship floor fired. The pane has a valid inbox key but no armed watcher (:614). The floor fires if this is the session's first idle, mail is pending, or open custody rows are attributed to this pane (:805), and only while budget and TTL allow (:838, :847). It blocks with "Arm your inbox watcher NOW". Under a live /goal it names the `--idle-scoped` arm instead (:829-835). | `CC_WAKE_FLOOR=0` (:604). `CC_WAKE_FLOOR_MAX` (default 2, :807) caps it, so `=0` turns it off. `CC_WAKE_FLOOR_TTL_S` (default 600 s, :808) spaces out repeat blocks. Kill switch (:852). Other abstains: headless or pane-less session (`CC_PANE_ID` set without `ITERM_SESSION_ID`, :656); a live /goal with mail pending (:697); a team assignee or fresh teardown marker (:776-798). Note that `CC_WAKE_FLOOR_TEARDOWN=0` does not turn the floor off. It removes the assignee/teardown abstain, so the floor fires in more cases. The floor is also silent if jq is missing, the mailbox lib is missing, or there is no pane id (:605-607). |

## Deliberately excluded: `exit 2` paths are not Stop-mode blocks
- :116 exits 2 when `--why` is used and the reference-tier lib is missing.
- :130 exits 2 when the sentinel lib is missing, but only for the `set`, `clear` and `status` CLI arguments. In Stop mode (no argument) the same failure exits 0.
- :216 exits 2 when `clear` gets an unknown flag.

All three need a CLI argument. Claude Code runs the hook with no arguments (header :18), so none of these can block a stop. The code comment at :127 says so: "A Stop hook must never block on error".

## Non-blocking outputs (listed so they are not mistaken for blocks)
These print only a `systemMessage` and allow the stop:
- the continuation cap message (:1266)
- the wake-floor budget exhausted message (:842)
- the wake-floor kill-switch message (:853)
- the headless abstain message (:659)
- the goal-live abstain message (:699)
- the teardown abstain message (:792)


## Tool calls (8) with the first 300 chars of each result
1. `Bash: {"command": "wc -l /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh; ls -la /tmp/tokeff-gate/f2/out/B01-r7/ 2>&1", "description": "Check hook file size and output dir"}`
   →     1346 /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh
total 0
drwxr-xr-x@  2 chrisren  wheel    64 Sep 24 10:27 .
drwxr-xr-x@ 82 chrisren  wheel  2624 Sep 24 10:27 ..
2. `Bash: {"command": "grep -n -E 'block|decision|reason|exit 2|_KILL|DISABLE|^[a-z_]+\\(\\)|^main|STOP_HOOK|stop_hook_active' /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh | head -300", "description": "Grep block decisions and kill switches"}`
   → 9:# dumb actuator — it just blocks the stop and feeds the next step back, with a hard
32:#   (c) CAP RE-ARM — a fresh `set` resets `.count`; the block reason instructs re-`set` each 🔧 turn
36:# NOTE: deliberately NO `set -e` — a Stop hook that exits 2 *blocks the stop*, so an
46:# This is the hook t
3. `Read: {"file_path": "/tmp/tokeff-gate/f2/tree/hooks/session-continue.sh", "offset": 1, "limit": 140}`
   → 1	#!/usr/bin/env bash
2	# session-continue.sh — 🔧 loose-ends continuation loop (agent-set sentinel + Stop-hook actuator).
3	#
4	# WHY: a Stop hook fired on its own is SCOPE-BLIND — a shell script can't tell an
5	# in-scope loose end from an intentional pause or out-of-scope dirt, so a standalone
6	#
4. `Read: {"file_path": "/tmp/tokeff-gate/f2/tree/hooks/session-continue.sh", "offset": 290, "limit": 330}`
   → 290	      '{cwd:$c,disarmed:($d==1)}' 2>/dev/null)"
291	    exit 0 ;;
292	  status)
293	    f=$(sentinel_for "$PWD")
294	    if [ -f "$f" ]; then
295	      # `unrecorded`, never `?` (W3i C3). `set` writes ${f}.sid only when the arming session HAS an
296	      # id, so the no-sid state is ORDINARY — 
5. `Read: {"file_path": "/tmp/tokeff-gate/f2/tree/hooks/session-continue.sh", "offset": 619, "limit": 300}`
   → 619	    prev_sid="$(sed -n 's/^sid=//p' "$sf" 2>/dev/null | head -n1)"
620	    cnt="$(sed -n 's/^count=//p' "$sf" 2>/dev/null | head -n1)"
621	    ts="$(sed -n 's/^ts=//p'    "$sf" 2>/dev/null | head -n1)"
622	  fi
623	  case "$cnt" in ''|*[!0-9]*) cnt=0 ;; esac
624	  case "$ts"  in ''|*[!0-9]*) ts=
6. `Read: {"file_path": "/tmp/tokeff-gate/f2/tree/hooks/session-continue.sh", "offset": 919, "limit": 430}`
   → 919	#   · DoD REMAINDER — the durable DoD accumulates frozen scopes across weeks BY DESIGN (it is
920	#     INTEGRATE-only), so a remainder is the steady state, not a loose end. Firing on it would block
921	#     every close in this worktree forever.
922	# Both stay with completion-assert's ledger a
7. `Write: {"file_path": "/tmp/tokeff-gate/f2/out/B01-r7/answer.md", "content": "# session-continue.sh: the conditions under which the Stop hook blocks a stop\n\nFile: `/tmp/tokeff-gate/f2/tree/hooks/session-continue.sh` (1346 lines; line count measured with `wc -l`). I read the whole actuation path, lines 306`
   → File created successfully at: /tmp/tokeff-gate/f2/out/B01-r7/answer.md (file state is current in your context — no need to Read it back)
8. `StructuredOutput: {"answer_path": "/tmp/tokeff-gate/f2/out/B01-r7/answer.md", "headline": "session-continue.sh blocks a stop in 5 cases, all through a decision:block JSON with exit 0. (1) A continuation the agent armed with `set`, emitted at :1334/:1336, bounded by the CLAUDE_CONTINUE_MAX cap (8 by default). (2) The `
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
