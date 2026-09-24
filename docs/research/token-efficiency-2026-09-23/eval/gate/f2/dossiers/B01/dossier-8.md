# Dossier 8

## Brief
```
In /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh, list every condition under which this Stop hook blocks a stop (emits a block decision or a blocking reason). For each give the line number, one sentence on the trigger, and the env var or kill switch that disables it, if any. numbers: {"conditions": <how many you listed>}.
```

## Returned headline
In Stop mode, session-continue.sh blocks under five conditions and always exits 0, sending the block as {decision:"block"} JSON: (1) a sentinel armed with `set` (:1336/:1334; turned off by the kill phrase, a SID mismatch or CLAUDE_CONTINUE_MAX=0), (2) a sentinel armed by mechanical_arm for this session's uncommitted files, which blocks through the same path (CC_MECH_CONTINUE=0, CC_MECH_MAX budget), (3) the 📦 ship floor and (4) the 🚀 ship floor (:1199; CC_SHIP_FLOOR=0, CC_SHIP_FLOOR_MAX, latched once per HEAD commit), and (5) the wake floor when no inbox watcher is armed (:895; CC_WAKE_FLOOR=0, CC_WAKE_FLOOR_MAX, CC_WAKE_FLOOR_TTL_S). The operator kill phrase (KILL_RE :348) turns off all five, and every exit 2 in the file is on a CLI path, never on a Stop.

## Returned numbers
`{"conditions": 5}`

## answer.md
# session-continue.sh: the conditions that block a stop

File: `/tmp/tokeff-gate/f2/tree/hooks/session-continue.sh` (1346 lines; `wc -l`).

In Stop mode (no CLI argument, JSON on stdin) this hook **always exits 0**. It blocks a stop only by printing `{decision:"block",reason:…}` on stdout. Every `exit 2` in the file is on a CLI arm: `--why` at :116, a missing-lib `set|clear|status` at :130, and a bad `clear` flag at :216. None of them runs on a Stop. When the sentinel lib is missing, Stop mode exits 0 at :130, which means it allows the stop. At most one JSON object is emitted per Stop. The floor order is mechanical 🔧, then ship floor, then wake floor (:1204-1221), and all three run only when no sentinel file exists.

I found 5 blocking conditions.

| # | Emit line | Trigger (one sentence) | Disable / kill switch |
|---|-----------|------------------------|-----------------------|
| 1 | **1336**; with-mail variant **1334** | An armed continuation sentinel exists for this cwd (the agent ran `session-continue.sh set "<step>"`), and the kill switch, SID-bind and cap checks all pass, so the hook blocks with "🔧 Loose ends remain — Next: <step>". Any pending peer inbox mail is folded into the same reason, and a `systemMessage` is added (:1310-1334). | **Kill phrase** in the last genuine user message (`KILL_RE` :348, e.g. "stop", "halt", "and then stop", "stop here", "no auto continue", "just do X", "come back to this") clears the sentinel and allows the stop (:1230-1235). **SID mismatch** (the stored arming sid differs from the current session) clears and allows (:1242-1249). **Cap** `CLAUDE_CONTINUE_MAX` (default 8; count ≥ MAX clears and allows, :1252-1270). Setting it to `0` disables this block entirely. `session-continue.sh clear` removes the sentinel. |
| 2 | **1336 / 1334** (armed at 1072, falls through at :1222-1224) | No sentinel exists, but `mechanical_arm` (:940) finds that the wrap-ledger rung is 🔧 and that this session's own edited files are still uncommitted, so it writes a "Commit the N file(s) you edited…" sentinel. The Stop then blocks through the same continuation path as #1. | **`CC_MECH_CONTINUE=0`** (:941). Budget **`CC_MECH_MAX`** (default 2 per session, :1055-1069). The kill phrase (:952), then all of #1's switches (kill phrase, SID, `CLAUDE_CONTINUE_MAX`). It also abstains for a confirmed team assignee (:969-983), a fresh teardown marker (`CC_TEARDOWN_DIR`, `CC_WF_TEARDOWN_FRESH_S`, :985), a missing jq, session-writes lib or wrap-ledger (`SESSION_WRITES_LIB`, `WRAP_LEDGER_BIN`), or a rung other than 🔧. |
| 3 | **1199** (printed at 1212) | Ship floor 📦: going idle while the ledger rung is 📦 (committed-but-unlanded commits ahead of a known trunk that `session_unlanded_mine` attributes to this session), and HEAD differs from the last-latched sha, so it blocks with "📦 SHIP FLOOR — /ship it". | **`CC_SHIP_FLOOR` ≠ 1** (:1101). Budget **`CC_SHIP_FLOOR_MAX`** (default 2 per session, :1164/1176). It latches once per HEAD sha (:1174). The kill phrase (:1103). It also abstains for a team assignee (:1105-1111), a teardown marker (:1112), no trunk (`TRUNK=none`, :1151), or work that is not this session's (:1152). |
| 4 | **1199** (printed at 1212) | Ship floor 🚀: going idle while the ledger rung is 🚀 (landed work whose enforcing store breached its converge budget, so the live bytes are stale) and this session wrote files (`session_writes_paths`), so it blocks with "🚀 SHIP FLOOR — run deploy-live.sh". | Same switches as #3: `CC_SHIP_FLOOR`, `CC_SHIP_FLOOR_MAX`, the per-sha latch, the kill phrase, the assignee and teardown abstains, and not-mine (:1156). |
| 5 | **895** (printed at 1217) | Wake floor: going idle (no sentinel, no ship-floor block) with no inbox wake path armed (`mailbox_wake_armed` false). It fires on the first attempt this session (cnt=0), or when mail is pending, or when cc-custody open rows exist for this cwd (:805), and blocks with "🔔 WAKE FLOOR — arm cc-await-ping". Pending mail and custody text are prepended, and it uses the `--idle-scoped` arm under a live /goal. | **`CC_WAKE_FLOOR` ≠ 1** (:604). Budget **`CC_WAKE_FLOOR_MAX`** (default 2, :807/838; exhausted means a warning systemMessage and allow). TTL **`CC_WAKE_FLOOR_TTL_S`** (default 600 s between attempts, :847). The kill phrase (:852). It also abstains when jq or the mailbox lib is absent, when `_ouid` (from `CC_PANE_ID`/`ITERM_SESSION_ID`) is invalid (:605-607), for a pane-less headless session (`CC_PANE_ID` set with `ITERM_SESSION_ID` empty, :656), when a /goal is live and mail is pending (:697), and for a team assignee or teardown marker while `CC_WAKE_FLOOR_TEARDOWN=1` (the default, :776). Setting `CC_WAKE_FLOOR_TEARDOWN=0` removes those abstains, so it makes blocking *more* likely. |

## Notes
- #1 and #2 share one emission site. They are listed separately because the arming trigger and the disable switches differ: #2 can be turned off alone with `CC_MECH_CONTINUE=0`, and #1 cannot.
- The mail fold (:1334) is not an independent blocker. It only changes the reason and adds a `systemMessage` on a stop that #1 or #2 already blocks.
- Non-blocking outputs, all `{systemMessage}` only: cap reached (:1267), wake-floor budget exhausted (:842), kill phrase under the wake floor (:853), and headless, goal-live and teardown abstains (:659, :699, :792).
- The only kill switch that covers every blocker is the operator kill phrase (`KILL_RE` :348) in the transcript's last non-meta user message. No single env var turns the whole hook off. The per-arm switches are `CC_MECH_CONTINUE=0`, `CC_SHIP_FLOOR=0`, `CC_WAKE_FLOOR=0` and `CLAUDE_CONTINUE_MAX=0`.


## Tool calls (10) with the first 300 chars of each result
1. `Bash: {"command": "wc -l /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh; ls -la /tmp/tokeff-gate/f2/out/B01-r6/ 2>&1", "description": "Check hook file size and output dir"}`
   →     1346 /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh
total 0
drwxr-xr-x@  2 chrisren  wheel    64 Sep 24 10:27 .
drwxr-xr-x@ 82 chrisren  wheel  2624 Sep 24 10:27 ..
2. `Bash: {"command": "grep -n -E 'block|decision|reason|exit 2|_DISABLE|KILL|SKIP|^[a-z_]+\\(\\)|^main|emit' /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh | head -300", "description": "Grep for block decisions and kill switches"}`
   → 9:# dumb actuator — it just blocks the stop and feeds the next step back, with a hard
25:#   (a) KILL-SWITCH — actuation reads the transcript's last genuine user message; an operator
32:#   (c) CAP RE-ARM — a fresh `set` resets `.count`; the block reason instructs re-`set` each 🔧 turn
34:#       giv
3. `Bash: {"command": "sed -n 96,135p /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh; echo ----; sed -n 280,345p /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh", "description": "Read preamble and dispatch sections"}`
   → # ── `--why <topic>` REFERENCE TIER (backlog 1031594b6327; docs/plans/STOPHOOK_MESSAGE_TIERING.md §3) ──
# Dispatched HERE — before stdin is read and before any IDL/latch/state write — because this arm is run
# from a TERMINAL by a reader holding one of this hook's messages. A `cat` above it blocks 
4. `Bash: {"command": "sed -n 1200,1346p /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh", "description": "Read the main Stop flow"}`
   →   return 1
}

# No sentinel → the agent did NOT request continuation → the session is going IDLE. This is the one
# transition the floors guard; a sentinel-blocked stop is not idle, so it needs no floor.
# Floor order: mechanical 🔧 (uncommitted own writes) → ship floor (📦/🚀 own work) → wake floor
# 
5. `Bash: {"command": "sed -n 345,600p /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh | grep -v '^\\s*#'", "description": "Read code lines 345-600 without comments"}`
   → KILL_RE='(^|[^[:alnum:]])and( then)? stop([^[:alnum:]]|$)|no[ _-]?auto[ _-]?continue|(^|[^[:alnum:]])just do [^[:space:]]|(^|[^[:alnum:]])stop here([^[:alnum:]]|$)|come back to this|^[[:space:]]*(stop|halt)[[:space:].!]*$'
last_user_msg() {
  local tp
  tp=$(printf '%s' "$input" | jq -r '.transcript
6. `Bash: {"command": "awk 'NR>=600 && NR<=900 && $0 !~ /^[[:space:]]*#/ {print NR\": \"$0}' /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh", "description": "Read wake_floor code with line numbers"}`
   → 603: wake_floor() { # → echoes JSON on stdout when it wants to BLOCK; otherwise silent. Never fails.
604:   [ "${CC_WAKE_FLOOR:-1}" = 1 ] || return 0
605:   command -v jq >/dev/null 2>&1 || return 0
606:   command -v mailbox_wake_armed >/dev/null 2>&1 || return 0
607:   case "$_ouid" in ''|.|..|.*|*
7. `Bash: {"command": "awk 'NR>=900 && NR<=1200 && $0 !~ /^[[:space:]]*#/ {print NR\": \"$0}' /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh", "description": "Read mechanical_arm and ship_floor code"}`
   → 932: TP_MECH="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)"
938: _sc_tp="$TP_MECH"; case "$_sc_tp" in "~"*) _sc_tp="$HOME${_sc_tp#\~}" ;; esac
939: [ -n "$_sc_tp" ] && export WRAP_TRANSCRIPT="$_sc_tp"
940: mechanical_arm() {   # rc 0 = armed (fall through to the armed path
8. `Bash: {"command": "F=/tmp/tokeff-gate/f2/tree/hooks/session-continue.sh; grep -noE '\\$\\{?[A-Z][A-Z0-9_]+' $F | sort -t: -k2 -u | awk -F: '{print $2}' | sort | uniq -c; grep -n 'exit 2' $F; sed -n 1,60p $F | grep -n -i 'kill\\|disable\\|env'", "description": "List env vars referenced and exit 2 sites"}`
   →    1 ${AGENT_IDENTITY_LIB
   1 ${CC_CUSTODY_BIN
   1 ${CC_MAILBOX_DIR
   1 ${CC_MECH_CONTINUE
   1 ${CC_MECH_MAX
   1 ${CC_PANE_ID
   1 ${CC_SHIP_FLOOR
   1 ${CC_SHIP_FLOOR_MAX
   1 ${CC_TEARDOWN_DIR
   1 ${CC_WAKE_FLOOR
   1 ${CC_WAKE_FLOOR_MAX
   1 ${CC_WAKE_FLOOR_TEARDOWN
   1 ${CC_WAKE_FLOOR_TIM
9. `Write: {"file_path": "/tmp/tokeff-gate/f2/out/B01-r6/answer.md", "content": "# session-continue.sh: the conditions that block a stop\n\nFile: `/tmp/tokeff-gate/f2/tree/hooks/session-continue.sh` (1346 lines; `wc -l`).\n\nIn Stop mode (no CLI argument, JSON on stdin) this hook **always exits 0**. It blocks `
   → File created successfully at: /tmp/tokeff-gate/f2/out/B01-r6/answer.md (file state is current in your context — no need to Read it back)
10. `StructuredOutput: {"answer_path": "/tmp/tokeff-gate/f2/out/B01-r6/answer.md", "headline": "In Stop mode, session-continue.sh blocks under five conditions and always exits 0, sending the block as {decision:\"block\"} JSON: (1) a sentinel armed with `set` (:1336/:1334; turned off by the kill phrase, a SID mismatch or C`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
