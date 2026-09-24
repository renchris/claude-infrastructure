# Dossier 1

## Brief
```
In /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh, list every condition under which this Stop hook blocks a stop (emits a block decision or a blocking reason). For each give the line number, one sentence on the trigger, and the env var or kill switch that disables it, if any. numbers: {"conditions": <how many you listed>}.
```

## Returned headline
session-continue.sh blocks a stop in 5 cases. Two go through the continuation sentinel, which blocks at lines 1334/1336. Case 1 is a sentinel armed with `set`; it is disabled by `clear`, a sid mismatch or `CLAUDE_CONTINUE_MAX`. Case 2 is the mechanical 🔧 arm for this session's own uncommitted files; it is disabled by `CC_MECH_CONTINUE=0` or `CC_MECH_MAX`. The other three are floors that apply when no sentinel is armed. Cases 3 and 4 are the ship floor (line 1199) for 📦 unlanded commits and 🚀 not-live work; they are disabled by `CC_SHIP_FLOOR` other than 1 or `CC_SHIP_FLOOR_MAX`. Case 5 is the wake floor (line 895) for going idle with no inbox watcher armed; it is disabled by `CC_WAKE_FLOOR` other than 1 or `CC_WAKE_FLOOR_MAX`. An operator kill phrase (`KILL_RE`, line 348) turns off all five.

## Returned numbers
`{"conditions": 5}`

## answer.md
Stop-blocking conditions in /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh

The hook always exits 0 in Stop mode. It blocks only by printing `{decision:"block",reason:…}` JSON. The `exit 2` paths at lines 116, 130 and 216 run only in CLI mode (`--why`, `set`, `clear`, `status`), not at Stop, so they are not listed. Every row below is also switched off by a kill phrase in the operator's last real user message (`KILL_RE`, line 348, checked by `kill_switch_active`, line 391). Examples of kill phrases: "stop", "and then stop", "stop here", "no auto continue", "just do X".

1. **Line 1334 (with folded inbox mail) / line 1336 (without): armed continuation sentinel.** A sentinel file exists for this cwd (written by `session-continue.sh set "<step>"`), its stored sid matches this session or is unknown, and its `.count` is below the cap, so the hook blocks with "🔧 Loose ends remain — Next: <step>". Any pending peer mail is added to the top of the reason.
   - Disabled by: `session-continue.sh clear`; a kill phrase (line 1230); a different session's sid (line 1248); or the cap `CLAUDE_CONTINUE_MAX` (default 8, lines 1257-1260), which clears the sentinel and allows the stop. `CLAUDE_CONTINUE_MAX=0` turns this block off.

2. **Line 1072 (writes the sentinel), then blocks at 1334/1336: mechanical 🔧 arm.** There is no sentinel. The wrap ledger says `RUNG=🔧` and `session_dirty_mine` finds uncommitted files this session edited. The hook writes a "Commit the N file(s)…" sentinel and falls through to the armed block in row 1. The per-session budget is `CC_MECH_MAX` (default 2).
   - Disabled by: `CC_MECH_CONTINUE=0` (line 941); a kill phrase (line 952); a confirmed team-assignee session (line 981) or a fresh teardown marker (line 985); `CC_MECH_MAX=0`; or a missing jq, session-writes lib or wrap-ledger.

3. **Line 1199, reason text at 1187 (printed at 1212): ship floor 📦.** There is no sentinel and the mechanical arm did not fire. The ledger says `RUNG=📦`, and `session_unlanded_mine` finds committed but unlanded commits written by this session. It fires once per new HEAD sha, up to `CC_SHIP_FLOOR_MAX` times per session (default 2).
   - Disabled by: `CC_SHIP_FLOOR` set to anything other than 1 (line 1101); a kill phrase (line 1103); team assignee or teardown marker (lines 1105-1112); `CC_SHIP_FLOOR_MAX=0`.

4. **Line 1199, reason text at 1189 (printed at 1212): ship floor 🚀.** The same path as row 3, but the ledger says `RUNG=🚀`, meaning landed work is not live because the enforcing store breached its converge budget. `session_writes_paths` confirms this session wrote files, so the hook blocks with an instruction to run `deploy-live.sh`. The same once-per-sha rule and `CC_SHIP_FLOOR_MAX` budget apply.
   - Disabled by: the same switches as row 3 (`CC_SHIP_FLOOR` other than 1, a kill phrase, team assignee or teardown, `CC_SHIP_FLOOR_MAX=0`).

5. **Line 895 (printed at 1217): wake floor 🔔.** There is no sentinel and neither of the floors above fired. The pane-bound session (`CC_PANE_ID`/`ITERM_SESSION_ID`) has no inbox watcher armed (`mailbox_wake_armed` fails). It is the first floor for this sid, or mail is pending, or there are open cc-custody rows for this cwd. Budget and TTL allow it: `CC_WAKE_FLOOR_MAX` (default 2) and `CC_WAKE_FLOOR_TTL_S` (default 600 s). The hook blocks, telling the model to arm `cc-await-ping`.
   - Disabled by: `CC_WAKE_FLOOR` set to anything other than 1 (line 604); a kill phrase (line 852); `CC_WAKE_FLOOR_MAX=0`.
   - It also stands down on its own in these cases: a headless session (`CC_PANE_ID` set without `ITERM_SESSION_ID`); a live /goal while mail is pending; a team assignee or teardown marker (only while `CC_WAKE_FLOOR_TEARDOWN=1`, the default); or when jq or the mailbox lib is missing.


## Tool calls (12) with the first 300 chars of each result
1. `Bash: {"command": "wc -l /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh; ls -la /tmp/tokeff-gate/f2/out/B01-r11/ 2>&1", "description": "Check file size and output dir"}`
   →     1346 /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh
total 0
drwxr-xr-x@   2 chrisren  wheel    64 Sep 24 11:31 .
drwxr-xr-x@ 102 chrisren  wheel  3264 Sep 24 11:31 ..
2. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree/hooks; grep -n -E 'block|decision|reason|exit 2|_DISABLE|KILL|^[a-z_]+\\(\\)|^main|kill' session-continue.sh | head -300", "description": "Grep block-related lines"}`
   → 9:# dumb actuator — it just blocks the stop and feeds the next step back, with a hard
25:#   (a) KILL-SWITCH — actuation reads the transcript's last genuine user message; an operator
30:#       ignores a sentinel whose sid ≠ the actuating session's (kills S-12 cross-succession
32:#   (c) CAP RE-ARM 
3. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree/hooks; sed -n 96,135p session-continue.sh; echo ----; sed -n 296,340p session-continue.sh", "description": "Read early exit paths"}`
   → # ── `--why <topic>` REFERENCE TIER (backlog 1031594b6327; docs/plans/STOPHOOK_MESSAGE_TIERING.md §3) ──
# Dispatched HERE — before stdin is read and before any IDL/latch/state write — because this arm is run
# from a TERMINAL by a reader holding one of this hook's messages. A `cat` above it blocks 
4. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree/hooks; sed -n 1100,1346p session-continue.sh", "description": "Read ship floor and main path"}`
   → ship_floor() { # → echoes JSON to BLOCK (rc 1); rc 0 otherwise (never emits on rc 0). Never fails.
  [ "${CC_SHIP_FLOOR:-1}" = 1 ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  kill_switch_active && { log_idl abstained "ship-floor-kill-switch"; return 0; }
  local _sf_aid _sf_c
  if _sf_
5. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree/hooks; sed -n 600,900p session-continue.sh | grep -v '^\\s*#'", "description": "Read wake floor code without comments"}`
   → wake_floor() { # → echoes JSON on stdout when it wants to BLOCK; otherwise silent. Never fails.
  [ "${CC_WAKE_FLOOR:-1}" = 1 ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  command -v mailbox_wake_armed >/dev/null 2>&1 || return 0
  case "$_ouid" in ''|.|..|.*|*[!A-Za-z0-9._-]*) return 
6. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree/hooks; awk 'NR>=936 && NR<=1085 && $0 !~ /^[[:space:]]*#/ {print NR\": \"$0}' session-continue.sh", "description": "Read mechanical_arm code with line numbers"}`
   → 938: _sc_tp="$TP_MECH"; case "$_sc_tp" in "~"*) _sc_tp="$HOME${_sc_tp#\~}" ;; esac
939: [ -n "$_sc_tp" ] && export WRAP_TRANSCRIPT="$_sc_tp"
940: mechanical_arm() {   # rc 0 = armed (fall through to the armed path) · rc 1 = did not arm
941:   [ "${CC_MECH_CONTINUE:-1}" = "0" ] && return 1
942:   com
7. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree/hooks; grep -n -E 'exit 2|\"block\"|decision:' session-continue.sh | grep -v '^[0-9]*:\\s*#'; sed -n 136,150p session-continue.sh", "description": "Find all exit 2 and block emissions"}`
   → 116:  exit 2
130:  case "${1:-}" in set|clear|status) exit 2 ;; *) exit 0 ;; esac
216:      *) echo "session-continue: unknown flag for clear: ${2} (accepted: --if-mine)" >&2; exit 2 ;;
895:    '{decision:"block",reason:$r,systemMessage:$m}'
1199:  jq -nc --arg r "$reason" '{decision:"block",reason:
8. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree/hooks; sed -n '1206,1222p' session-continue.sh | cat -n | sed 's/^/+1205 /'; grep -n '_ouid=' session-continue.sh | head -3", "description": "Confirm print line numbers and _ouid source"}`
   → +1205      1	# (reachability). At most ONE floor emits per Stop — the hook prints a single JSON object.
+1205      2	if [ ! -f "$f" ]; then
+1205      3	  rm -f "${f}.count" "${f}.sid" "${f}.cwd" 2>/dev/null
+1205      4	  if ! mechanical_arm; then
+1205      5	    if ! _sf_json="$(ship_floor)"; the
9. `Write: {"file_path": "/tmp/tokeff-gate/f2/out/B01-r11/answer.md", "content": "Stop-blocking conditions in /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh\n\nThe hook always exits 0 in Stop mode. It blocks only by printing `{decision:\"block\",reason:…}` JSON. The `exit 2` paths at lines 116, 130 and 216`
   → File created successfully at: /tmp/tokeff-gate/f2/out/B01-r11/answer.md (file state is current in your context — no need to Read it back)
10. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree/hooks; grep -n -E 'stored_sid\" != \"\\$cur_sid|MAX=\"\\$\\{CLAUDE_CONTINUE_MAX|if \\[ \"\\$n\" -ge \"\\$MAX\" \\]' session-continue.sh", "description": "Verify cited line numbers"}`
   → 1248:if [ -n "$stored_sid" ] && [ -n "$cur_sid" ] && [ "$stored_sid" != "$cur_sid" ]; then
1257:MAX="${CLAUDE_CONTINUE_MAX:-8}"
1260:if [ "$n" -ge "$MAX" ]; then
11. `Bash: {"command": "cd /tmp/tokeff-gate/f2/out/B01-r11; sed -i '' 's/(line 1250)/(line 1248)/; s/(default 8, line 1258)/(default 8, lines 1257-1260)/' answer.md; grep -n '1248\\|1257' answer.md", "description": "Fix line numbers in answer"}`
   → 6:   - Disabled by: `session-continue.sh clear`; a kill phrase (line 1230); a different session's sid (line 1248); or the cap `CLAUDE_CONTINUE_MAX` (default 8, lines 1257-1260), which clears the sentinel and allows the stop. `CLAUDE_CONTINUE_MAX=0` turns this block off.
12. `StructuredOutput: {"answer_path": "/tmp/tokeff-gate/f2/out/B01-r11/answer.md", "headline": "session-continue.sh blocks a stop in 5 cases. Two go through the continuation sentinel, which blocks at lines 1334/1336. Case 1 is a sentinel armed with `set`; it is disabled by `clear`, a sid mismatch or `CLAUDE_CONTINUE_MAX``
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
