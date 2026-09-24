# Dossier 4

## Brief
```
In /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh, list every condition under which this Stop hook blocks a stop (emits a block decision or a blocking reason). For each give the line number, one sentence on the trigger, and the env var or kill switch that disables it, if any. numbers: {"conditions": <how many you listed>}.
```

## Returned headline
The Stop hook blocks under 5 conditions. (1) Agent-armed 🔧 continuation (:1334/:1336, capped by CLAUDE_CONTINUE_MAX, removed by `clear`). (2) Mechanical 🔧 arm on this session's uncommitted files (arms at :1072, blocks via the continuation site; off with CC_MECH_CONTINUE=0, budget CC_MECH_MAX). (3) Ship floor on 📦 and (4) ship floor on 🚀 (:1199; off with CC_SHIP_FLOOR=0, budget CC_SHIP_FLOOR_MAX, fires once per HEAD sha). (5) Wake floor when no inbox watcher is armed (:895; off with CC_WAKE_FLOOR=0, limited by CC_WAKE_FLOOR_MAX and CC_WAKE_FLOOR_TTL_S). All five are also suppressed by an operator kill-switch phrase.

## Returned numbers
`{"conditions": 5}`

## answer.md
# session-continue.sh — every condition under which the Stop hook blocks a stop

File: `/tmp/tokeff-gate/f2/tree/hooks/session-continue.sh` (1346 lines). In Stop mode the hook always exits 0.
A block is always sent as JSON `{decision:"block", reason:…}` on stdout. There are three emission sites:
ship floor `:1199`, wake floor `:895`, and the continuation block `:1334`/`:1336`.
Order of evaluation: if there is no sentinel (`:1207`), the mechanical arm runs first, then the ship floor, then the wake floor. Once a sentinel exists, the continuation path runs.

Kill switch shared by conditions 1–5: `kill_switch_active` (`:391`). It matches a kill phrase in the last non-meta user message, using `KILL_RE` at `:348`: "…and stop", "no auto-continue", "just do X", "stop here", "come back to this", or a bare "stop"/"halt".

| # | Line (emit) | Trigger (one sentence) | Disabled by |
|---|---|---|---|
| 1 | `:1334` / `:1336` (`mark_blocked continue` `:1331`) | **Agent-armed continuation:** a sentinel file set by `session-continue.sh set "<step>"` exists for this cwd, with no kill phrase, a stored sid equal to the current session sid (`:1248`), and `.count` below the cap (`:1260`). The hook then blocks with "🔧 Loose ends remain — Next: <step>", adding any pending inbox mail to the reason (`:1311-1318`). | `session-continue.sh clear` · kill-switch phrase (`:1230`, clears the sentinel) · `CLAUDE_CONTINUE_MAX` (default 8; at the cap it clears and allows, `:1257-1270`) · a sid mismatch clears it (`:1248`). |
| 2 | arms at `:1072`, blocks via `:1334`/`:1336` | **Mechanical 🔧 arm:** there is no sentinel, and `wrap-ledger.sh --machine` reads `RUNG=🔧` (`:1019`). `session_dirty_mine` also finds files this session edited that are still uncommitted (`:1024-1030`). The hook then writes a "Commit the N file(s)…" sentinel itself and falls through to the continuation block. | `CC_MECH_CONTINUE=0` (`:941`) · `CC_MECH_MAX` per-session budget (default 2, `:1055-1069`) · `clear` spends the budget outright (`:261`) · kill-switch phrase (`:952`) · a confirmed or argv-only team assignee (`:970-982`) · a teardown marker (`:985`) · the `CLAUDE_CONTINUE_MAX` cap from #1 still applies afterwards. |
| 3 | `:1199` (`mark_blocked ship-floor` `:1211`) | **Ship floor 📦:** there is no sentinel, the mechanical arm did not arm, and the ledger rung is `📦` (committed, not landed, `:1130`). `session_unlanded_mine` must also attribute the unlanded commits to this session (`:1148-1153`). The reason is "📦 SHIP FLOOR — /ship it". | `CC_SHIP_FLOOR` ≠ 1 (e.g. `0`, `:1101`) · `CC_SHIP_FLOOR_MAX` (default 2 per session, `:1164/1176`) · a latch fires only once per HEAD sha (`:1174`) · kill-switch phrase (`:1103`) · a team assignee (`:1105`) · a teardown marker (`:1112`). |
| 4 | `:1199` (same emit) | **Ship floor 🚀:** the same path fires when the ledger rung is `🚀` (landed but the live layer breached its converge budget) and `session_writes_paths` shows this session wrote something (`:1154-1157`). The reason is "🚀 SHIP FLOOR — run deploy-live.sh". | Same switches as #3: `CC_SHIP_FLOOR`, `CC_SHIP_FLOOR_MAX`, the per-HEAD-sha latch, the kill switch, assignee and teardown. |
| 5 | `:895` (`mark_blocked wake-floor` `:1216`) | **Wake floor:** there is no sentinel, the mechanical arm did not arm, and the ship floor did not fire. On top of that, no inbox watcher is armed for this pane (`mailbox_wake_armed`, `:614`). The hook then blocks to demand `cc-await-ping` in the background. It does this only on the first attempt, or when mail is pending, or when open custody rows exist (`:805`). The reason adds a pending-mail line and a custody line when they apply. | `CC_WAKE_FLOOR` ≠ 1 (`:604`) · `CC_WAKE_FLOOR_MAX` (default 2 attempts, `:807/830`) · `CC_WAKE_FLOOR_TTL_S` (default 600 s between attempts, `:808`) · kill-switch phrase (`:852`) · abstains for a pane-less headless session (`CC_PANE_ID` set with no `ITERM_SESSION_ID`, `:656`), for a live /goal with mail pending (`:697`), and for a team assignee or a teardown marker (`:776`; `CC_WAKE_FLOOR_TEARDOWN=0` turns that abstention off) · abstains when the pane id is empty or malformed. |

**Not counted:**
- `exit 2` at `:116`, `:130` and `:216` comes only from the CLI modes (`--why`, `set`/`clear`/`status`, bad flag). It signals an error to the agent and is not a Stop-hook block.
- A missing sentinel library in Stop mode exits 0 (`:130`).
- The inbox-mail fold (`:1286-1326`) is part of block #1's reason, not a separate trigger.
- The informational `{systemMessage}` outputs (for example at the cap, `:1266`, or when the wake floor is exhausted) do not block.


## Tool calls (7) with the first 300 chars of each result
1. `Bash: {"command": "wc -l /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh; grep -n 'block\\|decision\\|exit 2\\|reason' /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh | head -150", "description": "Count lines and grep block-related lines in the hook"}`
   →     1346 /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh
9:# dumb actuator — it just blocks the stop and feeds the next step back, with a hard
32:#   (c) CAP RE-ARM — a fresh `set` resets `.count`; the block reason instructs re-`set` each 🔧 turn
36:# NOTE: deliberately NO `set -e` — a Stop hook t
2. `Bash: {"command": "sed -n 100,135p /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh; echo ----; sed -n 300,420p /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh", "description": "Read hook top-level entry and sentinel sections"}`
   → # tty, and a state write above it would record a Stop that never happened. The library is sourced ONLY
# on this arm, so the hot path pays nothing.
# `$0`'s own symlink is resolved FIRST: a brand-new hooks/lib file has no ~/.claude/hooks/lib symlink
# until install.sh runs, and the live hook IS a sy
3. `Bash: {"command": "sed -n 590,900p /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh | grep -v '^\\s*#'", "description": "Read wake floor function code without comments"}`
   → wake_floor() { # → echoes JSON on stdout when it wants to BLOCK; otherwise silent. Never fails.
  [ "${CC_WAKE_FLOOR:-1}" = 1 ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  command -v mailbox_wake_armed >/dev/null 2>&1 || return 0
  case "$_ouid" in ''|.|..|.*|*[!A-Za-z0-9._-]*) return 
4. `Bash: {"command": "sed -n 900,1346p /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh | grep -nv '^\\s*#' | awk -F: '{n=$1+899; $1=\"\"; print n\":\"$0}'", "description": "Read mechanical, ship floor, and main block code with real line numbers"}`
   → 932: TP_MECH="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)"
938: _sc_tp="$TP_MECH"; case "$_sc_tp" in "~"*) _sc_tp="$HOME${_sc_tp#\~}" ;; esac
939: [ -n "$_sc_tp" ] && export WRAP_TRANSCRIPT="$_sc_tp"
940: mechanical_arm() {   # rc 0 = armed (fall through to the armed path
5. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree/hooks; grep -n 'CC_WAKE_FLOOR\\|kill_switch_active\\|mailbox_wake_armed \"\\|cnt\" -eq 0\\|CC_PANE_ID:-}\" \\] &&\\|_wf_goal\" \\] && \\[ \"\\$pend\\|wf_teardown_marked &&\\|CC_MECH\\|CC_SHIP_FLOOR\\|CLAUDE_CONTINUE_MAX\\|session_dirty_mine \"\\|\\[ \"\\$rung`
   → 46:# This is the hook that drives the loop: it emits {decision:"block"} up to CLAUDE_CONTINUE_MAX
261:    printf '%s %s' "$SC_SID" "${CC_MECH_MAX:-3}" > "${f}.mech" 2>/dev/null || true
355:  [ -n "$tp" ] && [ -f "$tp" ] || return 1
386:  [ -n "$_j" ] || return 1
391:kill_switch_active() {
392:  loca
6. `Bash: {"command": "cat > /tmp/tokeff-gate/f2/out/B01-r8/answer.md <<'EOF'\n# session-continue.sh — every condition under which the Stop hook blocks a stop\n\nFile: `/tmp/tokeff-gate/f2/tree/hooks/session-continue.sh` (1346 lines). In Stop mode the hook always exits 0.\nA block is always sent as JSON `{dec`
   → (Bash completed with no output)
7. `StructuredOutput: {"answer_path": "/tmp/tokeff-gate/f2/out/B01-r8/answer.md", "headline": "The Stop hook blocks under 5 conditions. (1) Agent-armed 🔧 continuation (:1334/:1336, capped by CLAUDE_CONTINUE_MAX, removed by `clear`). (2) Mechanical 🔧 arm on this session's uncommitted files (arms at :1072, blocks via the c`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
