# Dossier 8

## Brief
```
In /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh, list every condition under which this Stop hook blocks a stop (emits a block decision or a blocking reason). For each give the line number, one sentence on the trigger, and the env var or kill switch that disables it, if any. numbers: {"conditions": <how many you listed>}.
```

## Returned headline
I found five conditions under which session-continue.sh blocks a stop; each prints {decision:"block"} and the hook always exits 0 on the Stop path. (1) An agent-armed 🔧 sentinel, emitted at line 1336/1334: stopped by a kill phrase, a sid mismatch or the CLAUDE_CONTINUE_MAX cap (default 8). (2) The mechanical 🔧 arm for uncommitted files this session wrote, which blocks through that same path: off with CC_MECH_CONTINUE=0, budget CC_MECH_MAX. (3) and (4) The ship floor for 📦 and 🚀, emitted at line 1199: off with CC_SHIP_FLOOR=0, budget CC_SHIP_FLOOR_MAX. (5) The wake floor, emitted at lines 894-895: off with CC_WAKE_FLOOR=0, limited by CC_WAKE_FLOOR_MAX and CC_WAKE_FLOOR_TTL_S. The operator kill phrase (KILL_RE, line 348) suppresses all five. This comes from reading the code only; nothing was run.

## Returned numbers
`{"conditions": 5}`

## answer.md
# session-continue.sh (Stop hook): every condition that blocks a stop

File: /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh (1346 lines, read in full for the actuation path, lines 306-1346).

How it blocks: on the Stop path the hook always exits 0. A block is the JSON `{decision:"block",reason:...}` it prints on stdout. That JSON is emitted from three places: the ship floor (line 1199), the wake floor (lines 894-895), and the sentinel continuation (lines 1334/1336). The exits with code 2 (lines 116 and 130) are reached only from the CLI forms (`--why`, `set|clear|status`). On a Stop invocation with no arguments, line 130 exits 0. So neither of those exits blocks a stop.

Control flow: if no sentinel exists (line 1207), the hook runs the mechanical arm (1209). If that does not arm, it runs the ship floor (1210-1213) and then the wake floor (1215-1218). At most one floor emits per Stop. If a sentinel exists, or the mechanical arm just created one, execution reaches the armed path. That path checks the kill-switch (1230), then SID-BIND (1248), then the cap (1260), and then emits the block at 1334/1336.

## Conditions (5)

| # | Emit line | Trigger (one sentence) | Disabled by |
|---|-----------|------------------------|-------------|
| 1 | 1336 (1334 when inbox mail is folded in, and the reason text is at 1304) | Blocks when an agent-armed 🔧 sentinel (created by `session-continue.sh set "<step>"`) exists for this cwd and three things hold: the last real user message has no kill phrase, the stored `.sid` matches this session (or either sid is empty), and `.count` is still under the cap. | No dedicated on/off env var. The ways out are `session-continue.sh clear`, a kill phrase in the last user message (`KILL_RE` at 348, checked at 1230), a sid mismatch (1248), and the cap `CLAUDE_CONTINUE_MAX` (default 8, line 1257). `CLAUDE_CONTINUE_MAX=0` disables it in practice, because 0 >= 0 sends every Stop to the cap-and-allow path. |
| 2 | 1336 (the mechanical arm creates the sentinel at 1072, then falls through) | With no sentinel, `mechanical_arm` (940) arms one when four things hold: wrap-ledger reports rung 🔧, `session_dirty_mine` finds uncommitted files this session wrote, the session is neither an assignee nor carrying a teardown marker, and the per-session `.mech` budget has room. The block then happens through the armed path. | `CC_MECH_CONTINUE=0` (line 941). `CC_MECH_MAX` (default 2, line 1055), where 0 means it never arms. The kill phrase (952). The assignee exemption (970-982). The teardown marker (985). `CLAUDE_CONTINUE_MAX` also caps the chain. The test seams `WRAP_LEDGER_BIN` and `SESSION_WRITES_LIB` make it inert when they point at nothing. |
| 3 | 1199 (reason at 1187; printed at 1212) | Ship floor 📦: with no sentinel and no mechanical arm, it blocks when wrap-ledger reports rung 📦, the trunk is known, `session_unlanded_mine` confirms the unlanded commits contain this session's own writes, HEAD has not already been nudged for this session, and the per-session count is under the max. | `CC_SHIP_FLOOR` set to anything other than 1, e.g. 0 (line 1101). `CC_SHIP_FLOOR_MAX` (default 2, line 1164), where 0 means never. The kill phrase (1103). The assignee check (1105-1111). The teardown marker (1112). A once-per-HEAD-sha latch (1174). |
| 4 | 1199 (reason at 1189; printed at 1212) | Ship floor 🚀: under the same gates as #3, it blocks when the rung is 🚀 (landed work not live because the converger breached its budget) and `session_writes_paths` shows this session wrote something. | Same as #3: `CC_SHIP_FLOOR=0`, `CC_SHIP_FLOOR_MAX`, kill phrase, assignee, teardown, HEAD-sha latch. |
| 5 | 894-895 (reason at 860-890; printed at 1217) | Wake floor: with no sentinel and neither of the earlier floors firing, it blocks when the pane has a valid inbox id and no armed `cc-await-ping` watcher, and one of three holds: this is the first attempt this session, mail is pending, or dispatched custody rows this pane owns (or that cannot be attributed) are still open. It tells the session to arm the watcher, or the `--idle-scoped` form under a live /goal. | `CC_WAKE_FLOOR` set to anything other than 1, e.g. 0 (line 604). `CC_WAKE_FLOOR_MAX` (default 2, line 807), where 0 means never. `CC_WAKE_FLOOR_TTL_S` backoff (default 600 s, line 808). The kill phrase (852). It also stands down in five cases. A headless pane (`CC_PANE_ID` set and `ITERM_SESSION_ID` unset, line 656). A live /goal with mail pending (697). An assignee or a teardown marker (776-798), but only while `CC_WAKE_FLOOR_TEARDOWN=1`; setting that to 0 removes the abstain rather than the floor. A missing jq or mailbox lib (605-606). An invalid `_ouid` (607). |

## Notes
- The kill-switch is shared: `kill_switch_active` (391) matches `KILL_RE` (348) against the last non-`isMeta` user message in the transcript. Phrases include "and stop", "no auto-continue", "just do X", "stop here", "come back to this", and a bare "stop" or "halt". It suppresses all five conditions.
- The inbox-mail fold (1286-1326) does not add a condition. It only prepends mail to the reason of #1 or #2.
- `CLAUDE_CONTINUE_MAX` with a non-numeric value makes the test at 1260 error out as false, so the block still fires (estimated by reading the code, not run).
- Everything here comes from reading the file statically. Nothing was executed.


## Tool calls (8) with the first 300 chars of each result
1. `Bash: {"command": "wc -l /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh; ls -la /tmp/tokeff-regate/f2/out/B01-r6/ 2>&1", "description": "Check hook file size and output dir"}`
   →     1346 /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh
total 0
drwxr-xr-x@  2 chrisren  wheel    64 Sep 24 13:39 .
drwxr-xr-x@ 82 chrisren  wheel  2624 Sep 24 13:39 ..
2. `Bash: {"command": "grep -n -E 'block|decision|reason|exit 2|KILL|DISABLE|_OFF|SKIP|^[a-z_]+\\(\\)' /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh | head -300", "description": "Grep block-related lines in hook"}`
   → 9:# dumb actuator — it just blocks the stop and feeds the next step back, with a hard
25:#   (a) KILL-SWITCH — actuation reads the transcript's last genuine user message; an operator
32:#   (c) CAP RE-ARM — a fresh `set` resets `.count`; the block reason instructs re-`set` each 🔧 turn
36:# NOTE: del
3. `Read: {"file_path": "/tmp/tokeff-regate/f2/tree/hooks/session-continue.sh", "limit": 200}`
   → 1	#!/usr/bin/env bash
2	# session-continue.sh — 🔧 loose-ends continuation loop (agent-set sentinel + Stop-hook actuator).
3	#
4	# WHY: a Stop hook fired on its own is SCOPE-BLIND — a shell script can't tell an
5	# in-scope loose end from an intentional pause or out-of-scope dirt, so a standalone
6	#
4. `Read: {"file_path": "/tmp/tokeff-regate/f2/tree/hooks/session-continue.sh", "offset": 290, "limit": 330}`
   → 290	      '{cwd:$c,disarmed:($d==1)}' 2>/dev/null)"
291	    exit 0 ;;
292	  status)
293	    f=$(sentinel_for "$PWD")
294	    if [ -f "$f" ]; then
295	      # `unrecorded`, never `?` (W3i C3). `set` writes ${f}.sid only when the arming session HAS an
296	      # id, so the no-sid state is ORDINARY — 
5. `Read: {"file_path": "/tmp/tokeff-regate/f2/tree/hooks/session-continue.sh", "offset": 619, "limit": 300}`
   → 619	    prev_sid="$(sed -n 's/^sid=//p' "$sf" 2>/dev/null | head -n1)"
620	    cnt="$(sed -n 's/^count=//p' "$sf" 2>/dev/null | head -n1)"
621	    ts="$(sed -n 's/^ts=//p'    "$sf" 2>/dev/null | head -n1)"
622	  fi
623	  case "$cnt" in ''|*[!0-9]*) cnt=0 ;; esac
624	  case "$ts"  in ''|*[!0-9]*) ts=
6. `Read: {"file_path": "/tmp/tokeff-regate/f2/tree/hooks/session-continue.sh", "offset": 918, "limit": 430}`
   → 918	#     Looping on it is the infinite-loop-wearing-diligence's-clothes case, by name.
919	#   · DoD REMAINDER — the durable DoD accumulates frozen scopes across weeks BY DESIGN (it is
920	#     INTEGRATE-only), so a remainder is the steady state, not a loose end. Firing on it would block
921	#    
7. `Bash: {"command": "cat > /tmp/tokeff-regate/f2/out/B01-r6/answer.md <<'EOF'\n# session-continue.sh (Stop hook): every condition that blocks a stop\n\nFile: /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh (1346 lines, read in full for the actuation path, lines 306-1346).\n\nHow it blocks: on the Stop `
   → (Bash completed with no output)
8. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B01-r6/answer.md", "headline": "I found five conditions under which session-continue.sh blocks a stop; each prints {decision:\"block\"} and the hook always exits 0 on the Stop path. (1) An agent-armed 🔧 sentinel, emitted at line 1336/1334: stopped by a kill`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
