# Dossier 5

## Brief
```
In /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh, list every condition under which this Stop hook blocks a stop (emits a block decision or a blocking reason). For each give the line number, one sentence on the trigger, and the env var or kill switch that disables it, if any. numbers: {"conditions": <how many you listed>}.
```

## Returned headline
session-continue.sh blocks a stop in 5 cases, emitted from 3 places (lines 1334/1336, 1199, 895). The cases are: an armed continuation sentinel (1334/1336, capped by CLAUDE_CONTINUE_MAX); an auto-armed sentinel for uncommitted files this session edited (off with CC_MECH_CONTINUE=0); the ship floor for committed-but-unlanded work (1199); the ship floor for landed-but-not-live work (1199), both off with CC_SHIP_FLOOR≠1; and the wake floor when no inbox watcher is armed (895, off with CC_WAKE_FLOOR≠1). A kill phrase in the operator's last message overrides all five, and the exit-2 paths only run from the command line, never on a Stop.

## Returned numbers
`{"conditions": 5}`

## answer.md
# session-continue.sh: when the Stop hook blocks a stop

File: /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh (1346 lines; read with sed/grep).

The hook blocks only by printing `{decision:"block",...}` JSON and exiting 0. There are **three emit sites**
(lines 895, 1199, 1334/1336). They are reached by **five distinct trigger conditions**:

| # | Emit line | Trigger (one sentence) | Disabled by |
|---|-----------|------------------------|-------------|
| 1 | 1334 / 1336 (sentinel check at 1207) | An operator- or agent-armed continuation sentinel (`session-continue.sh set "<step>"`) exists for this cwd, its stored sid matches the current session (1247-1254), and `.count` is under the cap (1257-1260), so the stop is blocked with "🔧 Loose ends remain" plus any pending inbox mail folded in (1286-1326). | No on/off env var. `CLAUDE_CONTINUE_MAX` (default 8, line 1257) caps it, and setting it to 0 makes every Stop hit the cap and allow. Also stopped by a kill phrase in the last user message (`kill_switch_active`, 1230), by `session-continue.sh clear`, or by a sid mismatch (1248). |
| 2 | 1334 / 1336 via `mechanical_arm` (940-1081, called at 1209) | With no sentinel, the wrap ledger reports rung 🔧 (1019) and `session_dirty_mine` attributes uncommitted files to this session (1024-1030), so the hook writes a sentinel itself ("Commit the N file(s)…", 1072) and falls through to the armed path's block. | `CC_MECH_CONTINUE=0` (941). `CC_MECH_MAX` (default 2 per session, 1055/1064) is the budget, and 0 disables it. Also suppressed by a kill phrase (952), a confirmed or argv-only team assignee (969-983), or a teardown marker (985). |
| 3 | 1199 (reason at 1187) | Ship floor, 📦 rung: no sentinel, the mechanical arm did not fire, the ledger says committed-but-unlanded (1130) and `session_unlanded_mine` attributes the commits to this session (1152), so the hook blocks with "📦 SHIP FLOOR … /ship it". It fires once per new HEAD sha (latch at 1174) and at most `CC_SHIP_FLOOR_MAX` times per session. | `CC_SHIP_FLOOR` set to anything other than 1 (1101). `CC_SHIP_FLOOR_MAX` (default 2, 1164) is the budget, and 0 disables it. Also suppressed by a kill phrase (1103), an assignee (1105-1111) or a teardown marker (1112). |
| 4 | 1199 (reason at 1189) | Ship floor, 🚀 rung: same path as #3, but the ledger says the landed work is not live (the converge budget was breached) and `session_writes_paths` shows this session wrote something (1156), so it blocks with "🚀 SHIP FLOOR … run deploy-live.sh". | Same as #3: `CC_SHIP_FLOOR`≠1, `CC_SHIP_FLOOR_MAX=0`, kill phrase, assignee, teardown marker. |
| 5 | 895 (reached from 1215) | Wake floor: no sentinel, and neither the mechanical arm nor the ship floor fired, and no inbox watcher is armed (`mailbox_wake_armed`, 612). It blocks with "🔔 WAKE FLOOR … arm cc-await-ping" (805) on the session's first idle, or whenever mail is pending or open dispatched (custody) sessions exist, as long as the budget remains (838) and the TTL has elapsed (847). | `CC_WAKE_FLOOR` set to anything other than 1 (597). `CC_WAKE_FLOOR_MAX` (default 2, 807) is the budget, and 0 disables it. `CC_WAKE_FLOOR_TTL_S` (default 600 s, 808) sets the backoff. Also suppressed by a kill phrase (852), a pane-less headless session (`CC_PANE_ID` set with no `ITERM_SESSION_ID`, 637), a live /goal with mail already pending (721), or a team assignee or teardown marker (776-797). `CC_WAKE_FLOOR_TEARDOWN=0` turns off only that last abstain, which lets the floor fire more often. |

Shared kill switch: `kill_switch_active` (391) matches `KILL_RE` (348) against the last genuine
(non-isMeta) user message. Examples are "and stop", "no auto continue", "just do X", "stop here",
"come back to this", or a bare "stop"/"halt". All five conditions honour it (1230, 952, 1103, 852).

## Not counted as Stop blocks
- `exit 2` at 116 (`--why` arm), 130 (sentinel library could not be sourced) and 216 (unknown
  `clear` flag) happen only in CLI modes (`--why`, `set|clear|status`). When the library cannot be
  sourced during a real Stop, line 130 exits 0 (allow).
- The cap path (1260-1269), wake-floor budget/TTL/kill/headless/goal paths and teardown paths print
  only `{systemMessage:...}` and exit 0, so they do not block.


## Tool calls (10) with the first 300 chars of each result
1. `Bash: {"command": "wc -l /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh; ls -la /tmp/tokeff-regate/f2/out/B01-r2/ 2>&1", "description": "Check file size and output dir"}`
   →     1346 /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh
total 0
drwxr-xr-x@  2 chrisren  wheel    64 Sep 24 13:39 .
drwxr-xr-x@ 82 chrisren  wheel  2624 Sep 24 13:39 ..
2. `Bash: {"command": "grep -n -iE 'block|decision|reason|exit 2|emit_|^[a-z_]+\\(\\)|KILL|DISABLE|_OFF|=0|env' /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh | head -300", "description": "Grep for block decisions and functions"}`
   → 1:#!/usr/bin/env bash
9:# dumb actuator — it just blocks the stop and feeds the next step back, with a hard
25:#   (a) KILL-SWITCH — actuation reads the transcript's last genuine user message; an operator
30:#       ignores a sentinel whose sid ≠ the actuating session's (kills S-12 cross-succession

3. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/hooks/session-continue.sh; sed -n 95,135p $F; echo ----; sed -n 136,315p $F | grep -n '' | awk -F: '{ $1=$1+135; print }' OFS=: | grep -E 'case|exit|\\)$|;;' ", "description": "Read head and CLI section"}`
   → }

# ── `--why <topic>` REFERENCE TIER (backlog 1031594b6327; docs/plans/STOPHOOK_MESSAGE_TIERING.md §3) ──
# Dispatched HERE — before stdin is read and before any IDL/latch/state write — because this arm is run
# from a TERMINAL by a reader holding one of this hook's messages. A `cat` above it bloc
4. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/hooks/session-continue.sh; sed -n 596,735p $F | grep -vE '^\\s*#'", "description": "Read wake floor first part"}`
   → wake_floor() { # → echoes JSON on stdout when it wants to BLOCK; otherwise silent. Never fails.
  [ "${CC_WAKE_FLOOR:-1}" = 1 ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  command -v mailbox_wake_armed >/dev/null 2>&1 || return 0
  case "$_ouid" in ''|.|..|.*|*[!A-Za-z0-9._-]*) return 
5. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/hooks/session-continue.sh; sed -n 735,900p $F | grep -nvE '^\\s*#' | awk -F: '{ $1=$1+734; print }' OFS=:", "description": "Read rest of wake floor"}`
   → 737:  for _cb in ${CC_CUSTODY_BIN:+"$CC_CUSTODY_BIN"} \
738:             "$(dirname "$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")")/../bin/cc-custody" \
739:             "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/bin/cc-custody" "$HOME/.claude/bin/cc-custody"; do
740:    [ -x "$_cb" ] && break; _cb
6. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/hooks/session-continue.sh; sed -n 799,822p $F; echo ----; sed -n 900,1110p $F | grep -nvE '^\\s*#' | awk -F: '{ $1=$1+899; print }' OFS=:", "description": "Read wake floor gating comment and mechanical arm"}`
   →   # Fire on the first idle of the session, any idle where mail is actually waiting, or any idle
  # while dispatched work THIS PANE OWNS (or that nothing can attribute away from it) has not
  # returned — the originator's one job while waiting is to be wakeable. A row a sibling in this
  # shared ch
7. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/hooks/session-continue.sh; sed -n 1110,1346p $F | grep -nvE '^\\s*#' | awk -F: '{ $1=$1+1109; print }' OFS=:", "description": "Read ship floor and main armed path"}`
   → 1110:    }
1111:  fi
1112:  wf_teardown_marked && { log_idl abstained "ship-floor-teardown"; return 0; }
1113:
1114:  local wrap led rung ahead shas trunk
1117:  led="${SC_LED_CACHE:-}"
1118:  if [ -z "$led" ]; then
1119:    wrap="${WRAP_LEDGER_BIN:-}"
1120:    if [ -z "$wrap" ]; then
1121:      for
8. `Bash: {"command": "F=/tmp/tokeff-regate/f2/tree/hooks/session-continue.sh; awk 'NR>=305 && NR<=600 && /exit|jq -n|printf .*\\{/ && !/^\\s*#/ {print NR\": \"$0}' $F; grep -n '\"continue\"\\s*:\\s*false\\|continue:false' $F", "description": "Check middle section for other emits"}`
   → 308: input=$(cat 2>/dev/null || printf '{}')
334:   printf '%s %s %s\n' "${cur_sid:-?}" "$(date +%s 2>/dev/null || echo 0)" "$1" \
9. `Bash: {"command": "cat > /tmp/tokeff-regate/f2/out/B01-r2/answer.md <<'EOF'\n# session-continue.sh: when the Stop hook blocks a stop\n\nFile: /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh (1346 lines; read with sed/grep).\n\nThe hook blocks only by printing `{decision:\"block\",...}` JSON and exiti`
   → (Bash completed with no output)
10. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B01-r2/answer.md", "headline": "session-continue.sh blocks a stop in 5 cases, emitted from 3 places (lines 1334/1336, 1199, 895). The cases are: an armed continuation sentinel (1334/1336, capped by CLAUDE_CONTINUE_MAX); an auto-armed sentinel for uncommitte`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
