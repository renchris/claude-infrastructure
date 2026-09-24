# Dossier 7

## Brief
```
In /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh, list every condition under which this Stop hook blocks a stop (emits a block decision or a blocking reason). For each give the line number, one sentence on the trigger, and the env var or kill switch that disables it, if any. numbers: {"conditions": <how many you listed>}.
```

## Returned headline
session-continue.sh can block a stop under 5 conditions, emitted from 3 sites. (1) An armed `set` sentinel continuation (1304/1334), capped by CLAUDE_CONTINUE_MAX. (2) The mechanical 🔧 arm for uncommitted files this session wrote (1072), off with CC_MECH_CONTINUE=0 and capped by CC_MECH_MAX. (3) The 📦 ship floor (1187/1199) and (4) the 🚀 ship floor (1189/1199), both off with CC_SHIP_FLOOR=0 and capped by CC_SHIP_FLOOR_MAX. (5) The wake floor for an idle session with no inbox watcher (860/894), off with CC_WAKE_FLOOR=0 and capped by CC_WAKE_FLOOR_MAX and CC_WAKE_FLOOR_TTL_S. All five also stand down on the operator's kill-switch phrase.

## Returned numbers
`{"conditions": 5}`

## answer.md
# session-continue.sh — every condition under which the Stop hook blocks a stop

File: `/tmp/tokeff-regate/f2/tree/hooks/session-continue.sh` (1346 lines). The hook always exits 0 in
Stop mode; a block is carried by a `{decision:"block",reason:…}` JSON object on stdout. There are
exactly three emission sites (894-895 wake floor, 1199 ship floor, 1334/1336 continuation), and they
cover **5 distinct trigger conditions**. They are checked in this order (dispatch at 1207-1225):
mechanical arm, then ship floor, then wake floor, all only when no sentinel is armed; then the armed
continuation path.

| # | Line (reason / emit) | Trigger (one sentence) | Disabled by |
|---|---|---|---|
| 1 | 1304 / 1334-1336 (`mark_blocked continue` 1331) | **Armed continuation:** a sentinel set by `session-continue.sh set "<step>"` exists for this cwd, its stored sid matches the current session, and the continuation count is below the cap, so the hook blocks and feeds the step back (with any pending inbox mail folded into the same reason, 1311-1318). | Kill-switch phrase in the last genuine operator message clears it (1230-1235); `session-continue.sh clear`; a sid mismatch (1247-1254); the cap `CLAUDE_CONTINUE_MAX` (default 8, 1257-1270). `CLAUDE_CONTINUE_MAX=0` turns it off entirely. |
| 2 | 1072 (writes the sentinel) → blocks via 1334/1336 | **Mechanical 🔧 arm** (`mechanical_arm`, 940-1081): no sentinel, but `wrap-ledger.sh --machine` reads `RUNG=🔧` and `session_dirty_mine` finds files THIS session wrote that are still uncommitted, so the hook arms a "commit these N files" sentinel itself and falls through to the continuation block. | `CC_MECH_CONTINUE=0` (941); budget `CC_MECH_MAX` (default 2 per sid, 1055-1069); kill switch (952); confirmed or argv-only team assignee (969-983); fresh teardown marker (985; freshness `CC_WF_TEARDOWN_FRESH_S`, default 1800 s); `session-continue.sh clear` spends the budget. It is also subject to `CLAUDE_CONTINUE_MAX`. |
| 3 | 1187 / 1199 (emitted 1210-1213) | **Ship floor 📦** (`ship_floor`, 1100-1201): with no sentinel and the mechanical arm not firing, the ledger reads `RUNG=📦` and `session_unlanded_mine` confirms the unlanded commits are this session's, so the hook blocks once per new HEAD sha, telling the agent to `/ship`. | `CC_SHIP_FLOOR=0` (1101); budget `CC_SHIP_FLOOR_MAX` (default 2 per sid, 1164-1180); per-HEAD-sha latch (1174); kill switch (1103); team assignee (1104-1111); teardown marker (1112). |
| 4 | 1189 / 1199 (emitted 1210-1213) | **Ship floor 🚀:** same function, but the ledger reads `RUNG=🚀` (landed but not live) and `session_writes_paths` shows this session wrote something, so the hook blocks telling the agent to run `scripts/deploy-live.sh`. | Same switches as #3: `CC_SHIP_FLOOR=0`, `CC_SHIP_FLOOR_MAX`, sha latch, kill switch, assignee, teardown. |
| 5 | 860 / 894-895 (emitted 1215-1218) | **Wake floor** (`wake_floor`, 603-897): no sentinel, no mechanical or ship block, a valid pane or mailbox key, and no inbox watcher armed (`mailbox_wake_armed` false). It blocks on the first idle stop of the session, or again later if mail is pending (`pend>0`) or open custody rows exist (`cust>0`), telling the agent to arm `cc-await-ping`. The reason text varies with pending mail, custody and a live /goal; with a goal it switches to the `--idle-scoped` arm. | `CC_WAKE_FLOOR=0` (604); `CC_WAKE_FLOOR_TEARDOWN` (default 1) enables the assignee/teardown abstain (776-802); budget `CC_WAKE_FLOOR_MAX` (default 2 per sid, 807, 826-833); re-fire TTL `CC_WAKE_FLOOR_TTL_S` (default 600 s, 808, 834-837); kill switch (838-842). It also abstains for a pane-less headless session (`CC_PANE_ID` set, `ITERM_SESSION_ID` unset, 634-641), for a live /goal while mail is pending (649-655), and when jq or the mailbox lib is missing. |

## Things that look like blocks but are not Stop blocks
- `exit 2` at 116 (`--why` tier missing), 130 (sentinel lib missing, only for the `set|clear|status` CLI
  modes; Stop mode exits 0 there), and 216 (bad `clear` flag). All three are CLI-mode failure signals, not Stop blocks.
- The `systemMessage`-only outputs are advisories that do not extend the turn: the cap-reached notice
  (1266), the wake-floor exhausted, kill-switch, headless, goal and teardown notices, and the unblocked
  `_wf_json` passthrough at 1220.
- No single env var turns off the whole hook in Stop mode. The global runtime off-switch is the
  kill-switch phrase (`KILL_RE`, 349), which every blocking arm honours.


## Tool calls (7) with the first 300 chars of each result
1. `Bash: {"command": "wc -l /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh; grep -n -E 'block|decision|exit 2|reason' /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh | head -150", "description": "Count lines and grep block decisions in hook"}`
   →     1346 /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh
9:# dumb actuator — it just blocks the stop and feeds the next step back, with a hard
32:#   (c) CAP RE-ARM — a fresh `set` resets `.count`; the block reason instructs re-`set` each 🔧 turn
36:# NOTE: deliberately NO `set -e` — a Stop hook
2. `Bash: {"command": "sed -n 100,135p /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh; echo ----; sed -n 300,480p /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh", "description": "Read hook sections"}`
   → # tty, and a state write above it would record a Stop that never happened. The library is sourced ONLY
# on this arm, so the hot path pays nothing.
# `$0`'s own symlink is resolved FIRST: a brand-new hooks/lib file has no ~/.claude/hooks/lib symlink
# until install.sh runs, and the live hook IS a sy
3. `Bash: {"command": "sed -n 580,900p /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh | grep -v '^  *#' | grep -v '^#'", "description": "Read wake floor code without comments"}`
   → wake_floor() { # → echoes JSON on stdout when it wants to BLOCK; otherwise silent. Never fails.
  [ "${CC_WAKE_FLOOR:-1}" = 1 ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  command -v mailbox_wake_armed >/dev/null 2>&1 || return 0
  case "$_ouid" in ''|.|..|.*|*[!A-Za-z0-9._-]*) return 
4. `Bash: {"command": "sed -n 900,1346p /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh | grep -n -v -E '^\\s*#' | awk -F: '{n=$1+899; sub(/^[0-9]+:/,\"\"); print n\": \"$0}'", "description": "Read remaining code with line numbers, no comments"}`
   → 932: TP_MECH="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)"
938: _sc_tp="$TP_MECH"; case "$_sc_tp" in "~"*) _sc_tp="$HOME${_sc_tp#\~}" ;; esac
939: [ -n "$_sc_tp" ] && export WRAP_TRANSCRIPT="$_sc_tp"
940: mechanical_arm() {   # rc 0 = armed (fall through to the armed path
5. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/hooks; awk 'NR>=136 && NR<=300 && /exit/ {print NR\": \"$0}' session-continue.sh; grep -n -oE '\\$\\{?[A-Z_]{4,}[:}-]' session-continue.sh | sort -t: -k2 -u | head -60; sed -n 480,580p session-continue.sh | grep -v '^\\s*#'", "description": "Check CLI exits`
   → 156:     exit 0 ;;
216:       *) echo "session-continue: unknown flag for clear: ${2} (accepted: --if-mine)" >&2; exit 2 ;;
244:       exit 0
247:     # exits 0 — so the verb used to print "cleared" whether it disarmed a live chain or looked in the
257:     # exit. Marking it spent is the difference
6. `Bash: {"command": "mkdir -p /tmp/tokeff-regate/f2/out/B01-r5 && cat > /tmp/tokeff-regate/f2/out/B01-r5/answer.md <<'EOF'\n# session-continue.sh — every condition under which the Stop hook blocks a stop\n\nFile: `/tmp/tokeff-regate/f2/tree/hooks/session-continue.sh` (1346 lines). The hook always exits 0 in`
   → ok
7. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B01-r5/answer.md", "headline": "session-continue.sh can block a stop under 5 conditions, emitted from 3 sites. (1) An armed `set` sentinel continuation (1304/1334), capped by CLAUDE_CONTINUE_MAX. (2) The mechanical 🔧 arm for uncommitted files this session w`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
