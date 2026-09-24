# Dossier 2

## Brief
```
In /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh, list every condition under which this Stop hook blocks a stop (emits a block decision or a blocking reason). For each give the line number, one sentence on the trigger, and the env var or kill switch that disables it, if any. numbers: {"conditions": <how many you listed>}.
```

## Returned headline
The Stop hook can block a stop under 5 conditions, and every block is printed JSON {decision:"block"} followed by exit 0 (never exit 2): (1) the agent has armed a 🔧 sentinel (emitted at lines 1334/1336; disabled by a kill phrase, `clear`, a sid mismatch, or the CLAUDE_CONTINUE_MAX cap, where 0 turns it off); (2) the hook arms that sentinel itself when the session has its own uncommitted edits (line 1072, then 1334/1336; CC_MECH_CONTINUE=0 turns it off, CC_MECH_MAX caps it); (3) the 📦 ship floor on unlanded commits and (4) the 🚀 ship floor on unconverged landed work (both line 1199, printed at 1212; CC_SHIP_FLOOR=0 turns them off, CC_SHIP_FLOOR_MAX caps them, and they do not re-fire on the same HEAD sha); (5) the wake floor when no inbox watcher is armed (lines 894-895, printed at 1217; CC_WAKE_FLOOR=0 turns it off, CC_WAKE_FLOOR_MAX caps it, CC_WAKE_FLOOR_TTL_S backs it off). An operator kill phrase suppresses all 5.

## Returned numbers
`{"conditions": 5}`

## answer.md
# session-continue.sh (Stop hook): the conditions that block a stop

File: /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh (1346 lines). I found these by reading the file with grep, sed and awk; nothing was executed. The hook always blocks by printing `{"decision":"block",...}` JSON and exiting 0. On the Stop path (no CLI argument) it never exits 2, because the header comment at lines 36-37 says every actuation path ends in `exit 0`.

I found **5 blocking conditions**. At most one fires per Stop, in this order: mechanical arm, then ship floor, then wake floor if there is no sentinel file; otherwise the armed sentinel path.

| # | Line (emit) | Trigger (one sentence) | What disables it |
|---|---|---|---|
| 1 | 1334 / 1336 (`{decision:"block",reason:"🔧 Loose ends remain…"}`; the 1334 form adds a `systemMessage` when inbox mail is folded in) | A sentinel set by the agent (`session-continue.sh set "<step>"`) exists for this cwd, and none of these apply: a kill phrase in the last user message, a sid mismatch between the armer and this session, or a continuation count at the cap. | Kill-switch phrase in the last genuine user message (`KILL_RE` at line 348, checked at line 1230: "…and stop", "no auto-continue", "just do X", "stop here", "come back to this", a bare "stop"/"halt"). Also `session-continue.sh clear`. The cap `CLAUDE_CONTINUE_MAX` (default 8, line 1256) turns the stop into an allow once reached; `CLAUDE_CONTINUE_MAX=0` disables it outright. |
| 2 | 1072 (arms the sentinel), then the block goes out at 1334/1336 | With no sentinel, `mechanical_arm` finds the wrap-ledger rung is 🔧 and this session has its own uncommitted edits (`session_dirty_mine`). It writes a "Commit the N file(s)…" sentinel and drops into the path in #1. | `CC_MECH_CONTINUE=0` (line 941). Budget `CC_MECH_MAX` (default 2 per sid, line 1055). Kill phrase (line 952). Also skipped for a confirmed or argv-evidenced team assignee (lines 970-981) or a fresh teardown marker (line 985). After arming, #1's kill/sid/cap checks also apply. |
| 3 | 1199 (reason at 1187), printed at 1212 | Ship floor 📦: with no sentinel and no mechanical arm, the ledger rung is 📦 and the committed-but-unlanded commits are attributed to this session (`session_unlanded_mine`), so the hook blocks and tells it to /ship. | `CC_SHIP_FLOOR=0` (line 1101). Kill phrase (line 1103). Team assignee (lines 1105-1110). Teardown marker (line 1112). Latched: it does not re-fire on the same HEAD sha (line 1174). Budget `CC_SHIP_FLOOR_MAX` (default 2 per sid, line 1164). |
| 4 | 1199 (reason at 1189), printed at 1212 | Ship floor 🚀: same path as #3, but the ledger rung is 🚀 (landed work whose enforcing store has breached its converge budget) and `session_writes_paths` shows this session wrote files, so the hook blocks and tells it to run `deploy-live.sh`. | Same as #3: `CC_SHIP_FLOOR=0`, kill phrase, assignee, teardown marker, same-sha latch, `CC_SHIP_FLOOR_MAX`. |
| 5 | 894-895 (`{decision:"block",…,systemMessage:"🔔 Wake floor…"}`), printed at 1217 | Wake floor: with no sentinel and no ship block, the session is going idle with no inbox watcher armed (`mailbox_wake_armed` false). It fires on the first idle, or whenever mail is pending or open custody rows it owns or cannot attribute remain (line 805). | `CC_WAKE_FLOOR=0` (line 604). Kill phrase (line 852). Budget `CC_WAKE_FLOOR_MAX` (default 2, line 807). TTL backoff `CC_WAKE_FLOOR_TTL_S` (default 600 s, lines 808 and 847). It also stays silent for: no jq or mailbox lib, an invalid or empty pane id (line 607), a pane-less session (`CC_PANE_ID` set without `ITERM_SESSION_ID`, line 656), a live /goal with mail already pending (line 697), or a team assignee or teardown marker (lines 776-797). `CC_WAKE_FLOOR_TEARDOWN=0` turns off that last abstention, so it can make the floor block *more* often, not less. |

## Things I did not count as blocking conditions
- **Exit 2 at lines 116, 130 and 216.** These are reachable only in CLI modes (`--why`, `set`/`clear`/`status` with a missing lib, or an unknown `clear` flag). They are not Stop-hook blocks: when the lib is missing on the Stop path the hook exits 0 (line 130).
- **Cap reached (lines 1259-1269).** It emits only a `systemMessage` and then `exit 0`, so the stop is allowed.
- **Wake-floor warnings when its budget is spent, when the kill switch is on, or when a goal is live or it abstains (lines 659, 699, 792, 842, 853).** These are only `{systemMessage}` messages and do not block.
- **Inbox mail fold (lines 1311-1325).** It adds to the block in #1 and is not a separate trigger.


## Tool calls (8) with the first 300 chars of each result
1. `Bash: {"command": "wc -l /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh; ls -la /tmp/tokeff-regate/f2/out/B01-r3/ 2>&1", "description": "Check file size and output dir"}`
   →     1346 /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh
total 0
drwxr-xr-x@  2 chrisren  wheel    64 Sep 24 13:39 .
drwxr-xr-x@ 82 chrisren  wheel  2624 Sep 24 13:39 ..
2. `Bash: {"command": "grep -n -iE 'block|decision|reason|exit 2|emit|DISABLE|KILL|_OFF|SKIP|^[a-z_]+\\(\\)|^main|return' /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh | head -300", "description": "Grep for block decisions and kill switches"}`
   → 9:# dumb actuator — it just blocks the stop and feeds the next step back, with a hard
25:#   (a) KILL-SWITCH — actuation reads the transcript's last genuine user message; an operator
30:#       ignores a sentinel whose sid ≠ the actuating session's (kills S-12 cross-succession
32:#   (c) CAP RE-ARM 
3. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/hooks/session-continue.sh; sed -n 1,44p $F; echo ----; sed -n 95,140p $F; echo ----; sed -n 1200,1346p $F", "description": "Read header, preamble and main actuation flow"}`
   → #!/usr/bin/env bash
# session-continue.sh — 🔧 loose-ends continuation loop (agent-set sentinel + Stop-hook actuator).
#
# WHY: a Stop hook fired on its own is SCOPE-BLIND — a shell script can't tell an
# in-scope loose end from an intentional pause or out-of-scope dirt, so a standalone
# one loops o
4. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/hooks/session-continue.sh; sed -n 290,341p $F; echo ----; sed -n 396,475p $F | grep -v '^ *#'", "description": "Read actuation preamble after CLI mode"}`
   →       '{cwd:$c,disarmed:($d==1)}' 2>/dev/null)"
    exit 0 ;;
  status)
    f=$(sentinel_for "$PWD")
    if [ -f "$f" ]; then
      # `unrecorded`, never `?` (W3i C3). `set` writes ${f}.sid only when the arming session HAS an
      # id, so the no-sid state is ORDINARY — the operator's own bare-shel
5. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/hooks/session-continue.sh; awk 'NR>=596 && NR<=900 && $0 !~ /^[[:space:]]*#/ {print NR\": \"$0}' $F | cut -c1-220", "description": "Read wake_floor code lines without comments"}`
   → 603: wake_floor() { # → echoes JSON on stdout when it wants to BLOCK; otherwise silent. Never fails.
604:   [ "${CC_WAKE_FLOOR:-1}" = 1 ] || return 0
605:   command -v jq >/dev/null 2>&1 || return 0
606:   command -v mailbox_wake_armed >/dev/null 2>&1 || return 0
607:   case "$_ouid" in ''|.|..|.*|*
6. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/hooks/session-continue.sh; sed -n 799,805p $F; echo ----; awk 'NR>=940 && NR<=1200 && $0 !~ /^[[:space:]]*#/ {print NR\": \"$0}' $F | cut -c1-200", "description": "Read mechanical_arm and ship_floor code"}`
   →   # Fire on the first idle of the session, any idle where mail is actually waiting, or any idle
  # while dispatched work THIS PANE OWNS (or that nothing can attribute away from it) has not
  # returned — the originator's one job while waiting is to be wakeable. A row a sibling in this
  # shared ch
7. `Bash: {"command": "cat > /tmp/tokeff-regate/f2/out/B01-r3/answer.md <<'EOF'\n# session-continue.sh (Stop hook): the conditions that block a stop\n\nFile: /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh (1346 lines). I found these by reading the file with grep, sed and awk; nothing was executed. The h`
   → (Bash completed with no output)
8. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B01-r3/answer.md", "headline": "The Stop hook can block a stop under 5 conditions, and every block is printed JSON {decision:\"block\"} followed by exit 0 (never exit 2): (1) the agent has armed a 🔧 sentinel (emitted at lines 1334/1336; disabled by a kill p`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
