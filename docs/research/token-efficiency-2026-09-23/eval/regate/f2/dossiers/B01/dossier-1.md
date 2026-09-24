# Dossier 1

## Brief
```
In /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh, list every condition under which this Stop hook blocks a stop (emits a block decision or a blocking reason). For each give the line number, one sentence on the trigger, and the env var or kill switch that disables it, if any. numbers: {"conditions": <how many you listed>}.
```

## Returned headline
session-continue.sh blocks a stop under 5 conditions: (1) a sentinel the agent armed with `set` (block emitted at 1334/1336, capped by CLAUDE_CONTINUE_MAX); (2) the mechanical arm, for uncommitted files this session wrote while the rung is 🔧 (sentinel written at 1072, turned off by CC_MECH_CONTINUE=0 and CC_MECH_MAX); (3) the ship floor on 📦 and (4) the ship floor on 🚀 (both at 1199, turned off by CC_SHIP_FLOOR=0 and CC_SHIP_FLOOR_MAX); and (5) the wake floor (895, turned off by CC_WAKE_FLOOR=0, CC_WAKE_FLOOR_MAX and CC_WAKE_FLOOR_TTL_S). All five also stand down on an operator kill phrase.

## Returned numbers
`{"conditions": 5}`

## answer.md
# session-continue.sh — every condition under which the Stop hook blocks a stop

File: /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh (1346 lines).

The hook always exits 0 in Stop mode. It blocks by printing `{decision:"block",reason:…}` JSON. There are
three places that emit a block: 895 (wake floor), 1199 (ship floor) and 1334/1336 (the armed-sentinel
continuation). They cover **5 trigger conditions**, because the ship floor has two variants and the
continuation block can be reached by two kinds of arming.

The two floors are tried only when no sentinel file exists and the mechanical arm did not arm
(1207-1222). They run in this order: mechanical arm, then ship floor, then wake floor. The first one to
block wins.

| # | Emit line | Trigger (one sentence) | Disabled by |
|---|---|---|---|
| 1 | 1304-1306, emitted 1334/1336 (`mark_blocked continue` 1331) | **Agent-armed continuation:** a sentinel set with `session-continue.sh set "<step>"` exists for this cwd, so the stop is blocked with "🔧 Loose ends remain" plus the next step, and any pending inbox mail is folded into the reason (1311-1318). | Kill phrase in the last genuine operator message (1230). Stored sid ≠ current sid, i.e. a successor session (1248). `CLAUDE_CONTINUE_MAX` cap, default 8 (1257-1269); a fresh `set` resets the count. `session-continue.sh clear`. |
| 2 | 1072 writes the sentinel, then the block reaches 1334/1336 | **Mechanical 🔧 arm:** no sentinel exists, `wrap-ledger.sh --machine` reads `RUNG=🔧`, and `session_dirty_mine` finds files this session wrote that are still uncommitted, so the hook arms the sentinel itself ("Commit the N file(s) you edited…"). It then falls through into condition 1's block. | `CC_MECH_CONTINUE=0` (941). Kill phrase (952). Session is a confirmed or argv-only team assignee (969-983). A fresh teardown marker, window `CC_WF_TEARDOWN_FRESH_S`, default 1800 (985). `CC_MECH_MAX` per-session budget, default 2 (1055-1069). All of condition 1's guards: kill-switch, sid-bind and `CLAUDE_CONTINUE_MAX`. |
| 3 | 1187, emitted 1199 (printed 1210-1213) | **Ship floor, 📦:** the ledger rung is 📦 (committed but not landed), and `session_unlanded_mine` attributes the unlanded commits to this session, so the stop is blocked with "📦 SHIP FLOOR — /ship it". | `CC_SHIP_FLOOR=0` (1101). Kill phrase (1103). Assignee (1105-1111). Teardown marker (1112). Latched once per HEAD sha (1174). `CC_SHIP_FLOOR_MAX` per session, default 2 (1164-1180). `session-continue.sh clear` spends the budget. |
| 4 | 1189-1195, emitted 1199 | **Ship floor, 🚀:** the ledger rung is 🚀 (landed, but the live layer has breached its converge budget), and this session wrote files per `session_writes_paths`, so the stop is blocked with "🚀 SHIP FLOOR — converge with deploy-live.sh". | Same as condition 3: `CC_SHIP_FLOOR=0`, kill phrase, assignee, teardown, HEAD-sha latch, `CC_SHIP_FLOOR_MAX`. |
| 5 | 860-890, emitted 894-895 (printed 1215-1218) | **Wake floor:** no inbox wake path is armed (`mailbox_wake_armed` is false), and there is pending mail, open cc-custody rows, or an earlier floor count this session, so the stop is blocked to demand that `cc-await-ping` be armed (the `--idle-scoped` form when a /goal is live). | `CC_WAKE_FLOOR=0` (604). No usable pane id (607). Pane-less headless session, i.e. `CC_PANE_ID` set without `ITERM_SESSION_ID` (656). A live /goal with mail already pending (697). Assignee or teardown marker, which `CC_WAKE_FLOOR_TEARDOWN=0` turns off (776-798). Nothing pending, no custody rows and count 0 (805). `CC_WAKE_FLOOR_MAX` budget, default 2 (838). `CC_WAKE_FLOOR_TTL_S` re-fire spacing, default 600 (847). Kill phrase (852). |

## Not counted as blocks

- **Exit-2 paths at 116 (`--why`) and 130 (lib missing, CLI mode), and the CLI flag error at 216.** These
  are CLI invocations (`set`/`clear`/`status`/`--why`), not the Stop hook. In Stop mode, a missing
  sentinel lib exits 0 (130).
- **The `systemMessage` warnings.** These are the wake floor's exhausted budget (842), its kill-switch
  (853), headless (659) and goal-live (699) branches, and the continuation cap (1266). All of them allow
  the stop.


## Tool calls (6) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/hooks && wc -l session-continue.sh && grep -n 'block\\|exit 2\\|decision' session-continue.sh | head -150", "description": "Count lines and grep block decisions in hook"}`
   →     1346 session-continue.sh
9:# dumb actuator — it just blocks the stop and feeds the next step back, with a hard
32:#   (c) CAP RE-ARM — a fresh `set` resets `.count`; the block reason instructs re-`set` each 🔧 turn
36:# NOTE: deliberately NO `set -e` — a Stop hook that exits 2 *blocks the stop*, 
2. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/hooks && sed -n 100,135p session-continue.sh && echo ---- && sed -n 300,420p session-continue.sh", "description": "Read hook header and early logic"}`
   → # tty, and a state write above it would record a Stop that never happened. The library is sourced ONLY
# on this arm, so the hot path pays nothing.
# `$0`'s own symlink is resolved FIRST: a brand-new hooks/lib file has no ~/.claude/hooks/lib symlink
# until install.sh runs, and the live hook IS a sy
3. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/hooks && grep -v '^\\s*#' session-continue.sh | cat -n >/dev/null; awk 'NR>=420 && NR<=1346 && $0 !~ /^[[:space:]]*#/ {print NR\": \"$0}' session-continue.sh", "description": "Print non-comment code lines 420-1346"}`
   → 420: _ouid="${CC_PANE_ID:-${ITERM_SESSION_ID:-}}"; _ouid="${_ouid##*:}"
425: _opane="$_ouid"
426: if [ -f "$_mbxlib" ] && command -v jq >/dev/null 2>&1; then
429:   if . "$_mbxlib" 2>/dev/null; then
453:     case "$_ouid" in
457:       ''|.|..|.*|*[!A-Za-z0-9._-]*) : ;;
458:       *) if command -v m
4. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/hooks && sed -n 1222,1245p session-continue.sh; grep -noE '\\$\\{[A-Z_]+:-[^}]*\\}' session-continue.sh | sort -t: -k2 -u | head -60; sed -n 140,160p session-continue.sh", "description": "Read remaining comments and env vars"}`
   →   fi
  # Armed mechanically → fall through into the armed path below, which applies the kill-switch,
  # SID-BIND and cap checks and emits the block. No second code path, no second bound.
fi

# ── (a) KILL-SWITCH — operator stop ALWAYS wins over a stale sentinel (I-2 / D-8) ──
# A kill phrase ⇒ clea
5. `Bash: {"command": "mkdir -p /tmp/tokeff-regate/f2/out/B01-r4 && cat > /tmp/tokeff-regate/f2/out/B01-r4/answer.md <<'EOF'\n# session-continue.sh — every condition under which the Stop hook blocks a stop\n\nFile: /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh (1346 lines).\n\nThe hook always exits 0 i`
   → ok
6. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B01-r4/answer.md", "headline": "session-continue.sh blocks a stop under 5 conditions: (1) a sentinel the agent armed with `set` (block emitted at 1334/1336, capped by CLAUDE_CONTINUE_MAX); (2) the mechanical arm, for uncommitted files this session wrote whi`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
