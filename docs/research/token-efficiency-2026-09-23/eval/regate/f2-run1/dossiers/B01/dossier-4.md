# Dossier 4

## Brief
```
In /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh, list every condition under which this Stop hook blocks a stop (emits a block decision or a blocking reason). For each give the line number, one sentence on the trigger, and the env var or kill switch that disables it, if any. numbers: {"conditions": <how many you listed>}.
```

## Returned headline
session-continue.sh blocks a stop under 5 conditions, each disabled by its own kill switch: the agent-armed continuation (L1334/1336; stops on `clear`, a kill-switch phrase, a sid mismatch or the CLAUDE_CONTINUE_MAX cap, and has no on/off env var), the mechanical uncommitted-files arm (same emitter; CC_MECH_CONTINUE=0 or CC_MECH_MAX), the 📦 ship floor and the 🚀 ship floor (L1199; CC_SHIP_FLOOR=0 or CC_SHIP_FLOOR_MAX), and the wake floor (L895; CC_WAKE_FLOOR=0 or CC_WAKE_FLOOR_MAX/TTL).

## Returned numbers
`{"conditions": 5}`

## answer.md
# session-continue.sh: every condition where the Stop hook blocks

File: `/tmp/tokeff-regate/f2/tree/hooks/session-continue.sh` (1346 lines).

The hook blocks only by printing `{decision:"block",reason:…}` to stdout and exiting 0. It has three
blocking emitters: the wake floor (L895), the ship floor (L1199) and the continuation block
(L1334/L1336). They fire under **5 distinct conditions**:

| # | Line(s) | Trigger (one sentence) | What disables it |
|---|---|---|---|
| 1 | 1304 reason, emitted 1334/1336 (1334 when inbox mail is folded in) | **Agent-armed continuation.** The sentinel `$f` exists because the agent ran `session-continue.sh set "<step>"`, so the stop is blocked and the step is fed back as the next turn ("🔧 Loose ends remain"). Any pending peer mail is folded into the same reason (L1310-1318). | **No dedicated on/off env var.** It stops blocking on `session-continue.sh clear`; on a kill-switch phrase in the last genuine user message (`KILL_RE` L350, checked L1230: "and stop", "no auto-continue", "just do X", "stop here", "come back to this", a bare "stop"/"halt"); on a sentinel-sid ≠ session-sid mismatch (L1248); and when the count reaches `CLAUDE_CONTINUE_MAX` (default 8, L1257-1269), which clears the sentinel and allows the stop. Setting `CLAUDE_CONTINUE_MAX=0` disables it in effect. |
| 2 | 940-1082 (`mechanical_arm`) arms the sentinel at L1077, then blocks through the same emitter at 1334/1336 | **Mechanical 🔧 arm.** With no sentinel present (L1207), `wrap-ledger.sh --machine` reports `RUNG=🔧` (L1019) **and** `session_dirty_mine` finds files this session wrote that are still uncommitted (L1024). The hook then writes a "Commit the N file(s) you edited…" step and blocks. | `CC_MECH_CONTINUE=0` (L941). Also stands down on a kill-switch phrase (L943), when the session is a confirmed team assignee (L945-951), when a fresh teardown marker names the session (L953, dir `CC_TEARDOWN_DIR`), and after `CC_MECH_MAX` arms per session (default 2, L1055/L1064). Each armed chain is then still capped by `CLAUDE_CONTINUE_MAX`. |
| 3 | 1187 reason, emitted 1199 (called L1210) | **Ship floor, 📦.** With no sentinel and no mechanical arm, the ledger rung is `📦` (committed, not landed; L1130/1148) and `session_unlanded_mine` attributes the unlanded commits to this session. It blocks once per new HEAD sha and tells the agent to `/ship`. | `CC_SHIP_FLOOR=0` (L1101). Also stands down on a kill-switch phrase (L1103), for a team assignee (L1105-1110) or a teardown marker (L1111), when already latched on the current HEAD sha (L1174), and after `CC_SHIP_FLOOR_MAX` fires per session (default 2, L1164/1176). |
| 4 | 1189 reason, emitted 1199 | **Ship floor, 🚀.** Same gate, but the rung is `🚀` (landed, but the live layer has breached its converge budget) and this session has writes (`session_writes_paths`, L1154-1157). It blocks and tells the agent to run `deploy-live.sh`. | Same switches as #3: `CC_SHIP_FLOOR=0`, `CC_SHIP_FLOOR_MAX`, the kill switch, assignee, teardown marker and the per-sha latch. |
| 5 | 860 reason, emitted 895 (called L1215) | **Wake floor.** With no sentinel, no mechanical arm and no ship-floor block, the session has a valid pane id and no inbox wake watcher is armed (`mailbox_wake_armed` false, L614). It fires on the first attempt, or on a later one if mail is pending or dispatched-session custody is open (L805). It blocks and tells the agent to arm `cc-await-ping`. | `CC_WAKE_FLOOR=0` (L604). Also stands down when the session is pane-less/headless (`CC_PANE_ID` set without `ITERM_SESSION_ID`, L656); when a `/goal` is live and mail is pending; for a team assignee or teardown marker (gated by `CC_WAKE_FLOOR_TEARDOWN`, default 1; setting it to 0 turns these abstentions off rather than the floor); after `CC_WAKE_FLOOR_MAX` attempts (default 2, L838); inside `CC_WAKE_FLOOR_TTL_S` of the last attempt (default 600 s, L847); and on a kill-switch phrase (L852). |

## Paths that look like blocks but are not
- **Exit 2 (L116, L130, L216).** These fire only for CLI invocations (`--why`, `set|clear|status` when the sentinel lib is missing, or a bad `clear` flag). On the Stop path a missing lib exits 0 (L130).
- **systemMessage-only output.** The cap message (L1266), the wake-floor exhausted, kill-switch, headless, goal-live and teardown notices, and the pass-through at L1219 add no `decision`, so they do not block.
- **Failure behaviour.** Every error path returns without blocking (never `set -e`, and the script always ends `exit 0`).


## Tool calls (7) with the first 300 chars of each result
1. `Bash: {"command": "f=/tmp/tokeff-regate/f2/tree/hooks/session-continue.sh; wc -l $f; grep -n 'block\\|decision\\|reason' $f | head -150", "description": "Locate block decisions in the hook"}`
   →     1346 /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh
9:# dumb actuator — it just blocks the stop and feeds the next step back, with a hard
32:#   (c) CAP RE-ARM — a fresh `set` resets `.count`; the block reason instructs re-`set` each 🔧 turn
36:# NOTE: deliberately NO `set -e` — a Stop hook
2. `Bash: {"command": "f=/tmp/tokeff-regate/f2/tree/hooks/session-continue.sh; grep -n 'exit 2\\|exit 0\\|^[a-z_]*()\\|CC_[A-Z_]*\\|CLAUDE_[A-Z_]*' $f | grep -v '^ *#' | head -120", "description": "List exits, functions and env vars"}`
   → 20:# Sentinel lives OUTSIDE any repo (per-account state dir: ${CLAUDE_CONFIG_DIR:-~/.claude}/state),
22:# including different accounts (each with its own CLAUDE_CONFIG_DIR) — don't collide.
37:# accidental non-zero exit could force a false continuation. Every actuation path ends `exit 0`.
46:# This 
3. `Bash: {"command": "f=/tmp/tokeff-regate/f2/tree/hooks/session-continue.sh; sed -n 100,132p $f; echo ----; sed -n 300,420p $f | grep -v '^ *#'; echo ----; sed -n 600,900p $f | grep -v '^ *#'", "description": "Read header, kill switch, wake floor"}`
   → # tty, and a state write above it would record a Stop that never happened. The library is sourced ONLY
# on this arm, so the hot path pays nothing.
# `$0`'s own symlink is resolved FIRST: a brand-new hooks/lib file has no ~/.claude/hooks/lib symlink
# until install.sh runs, and the live hook IS a sy
4. `Bash: {"command": "f=/tmp/tokeff-regate/f2/tree/hooks/session-continue.sh; sed -n 936,1346p $f | grep -v '^ *#'", "description": "Read mechanical arm, ship floor, main path"}`
   → _sc_tp="$TP_MECH"; case "$_sc_tp" in "~"*) _sc_tp="$HOME${_sc_tp#\~}" ;; esac
[ -n "$_sc_tp" ] && export WRAP_TRANSCRIPT="$_sc_tp"
mechanical_arm() {   # rc 0 = armed (fall through to the armed path) · rc 1 = did not arm
  [ "${CC_MECH_CONTINUE:-1}" = "0" ] && return 1
  command -v jq >/dev/null 2>&
5. `Bash: {"command": "f=/tmp/tokeff-regate/f2/tree/hooks/session-continue.sh; grep -n 'if kill_switch_active; then\\|stored_sid\" != \"\\|\"$n\" -ge \"$MAX\"\\|if \\[ ! -f \"\\$f\" \\]\\|if ! mechanical_arm\\|\\[ \"\\$cnt\" -eq 0 \\] ||\\|mailbox_wake_armed \"\\$_ouid\"; then\\|mcnt\" -ge \"\\$mmax\\|pcnt\" `
   → 614:  if mailbox_wake_armed "$_ouid"; then rm -f "$sf" 2>/dev/null; return 0; fi
805:  [ "$cnt" -eq 0 ] || [ "$pend" -gt 0 ] || [ "$cust" -gt 0 ] || return 0
838:  if [ "$cnt" -ge "$maxa" ]; then
847:  if [ "$(( now - ts ))" -ge "$ttl" ] 2>/dev/null; then :; else
848:    log_idl abstained "wake-floo
6. `Bash: {"command": "mkdir -p /tmp/tokeff-regate/f2/out/B01-r8 && cat > /tmp/tokeff-regate/f2/out/B01-r8/answer.md <<'EOF'\n# session-continue.sh: every condition where the Stop hook blocks\n\nFile: `/tmp/tokeff-regate/f2/tree/hooks/session-continue.sh` (1346 lines).\n\nThe hook blocks only by printing `{de`
   → (Bash completed with no output)
7. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B01-r8/answer.md", "headline": "session-continue.sh blocks a stop under 5 conditions, each disabled by its own kill switch: the agent-armed continuation (L1334/1336; stops on `clear`, a kill-switch phrase, a sid mismatch or the CLAUDE_CONTINUE_MAX cap, and `
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
