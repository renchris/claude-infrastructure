# Dossier 7

## Brief
```
In /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh, list every condition under which this Stop hook blocks a stop (emits a block decision or a blocking reason). For each give the line number, one sentence on the trigger, and the env var or kill switch that disables it, if any. numbers: {"conditions": <how many you listed>}.
```

## Returned headline
The session-continue.sh Stop hook blocks a stop under 5 conditions: (1) an agent-armed continuation sentinel, blocked at 1334/1336 and capped by CLAUDE_CONTINUE_MAX; (2) the mechanical arm for uncommitted files this session wrote, armed at 1072 and blocked through the same path (CC_MECH_CONTINUE=0, CC_MECH_MAX); (3) the ship floor on 📦, committed but unlanded work it wrote, at 1199; (4) the ship floor on 🚀, landed but not live, at 1199 (both ship floors: CC_SHIP_FLOOR=0, CC_SHIP_FLOOR_MAX); and (5) the wake floor when no inbox watcher is armed, at 895 (CC_WAKE_FLOOR=0, CC_WAKE_FLOOR_MAX, CC_WAKE_FLOOR_TTL_S). The kill-switch phrase in the last user message disarms all five.

## Returned numbers
`{"conditions": 5}`

## answer.md
# session-continue.sh (Stop hook): the conditions that block a stop

File: `/tmp/tokeff-gate/f2/tree/hooks/session-continue.sh` (1346 lines).

The Stop path always exits 0. Every block is a `{decision:"block", reason:…}` JSON object on stdout. The hook's `exit 2` sites (lines 116, 130, 216) belong to the CLI modes `--why`, `set`/`clear`/`status` and `clear <bad flag>`, and not to the Stop path. On a Stop, a missing library exits 0 (line 130). The hook never reads the harness's `stop_hook_active`.

The dispatch order at lines 1207-1225 is as follows. If no sentinel is armed for the cwd, the hook tries `mechanical_arm`. If that fails, it tries `ship_floor`, then `wake_floor`. Any block runs through the armed-sentinel path (lines 1230-1337).

There are **5 blocking conditions**.

| # | Line (block emitted) | Trigger | How to disable it |
|---|---|---|---|
| 1 | **1334 / 1336** (armed-sentinel "🔧 Loose ends remain" block; `mark_blocked continue` at 1331) | An agent armed the cwd's continuation sentinel with `session-continue.sh set "<step>"`. The kill phrase is absent, the sentinel's recorded sid matches this session (1247-1254) and the counter is below the cap. The hook then feeds the step back as the next turn. Any pending inbox mail is folded into the reason (1286-1326). | `session-continue.sh clear` removes the sentinel. The kill-switch phrase in the last user message clears it (1230-1235; `KILL_RE` at 348 covers "and stop", "no auto-continue", "just do X", "stop here", "come back to this" and a bare "stop"/"halt"). **`CLAUDE_CONTINUE_MAX`** (default 8, lines 1257-1270) caps it, but each fresh `set` zeroes the count. A sid mismatch also clears it. |
| 2 | **1072 → 1334 / 1336** (the mechanical arm writes the sentinel at 1072, then falls through to the same block) | No sentinel is armed, and `wrap-ledger.sh --machine` reads rung `🔧` (1019). `session_dirty_mine` then finds files that **this session** edited and left uncommitted (1024-1030). The hook auto-arms "Commit the N file(s) you edited…" and blocks. | **`CC_MECH_CONTINUE=0`** (941). **`CC_MECH_MAX`** is a per-session budget (default 2, 1055-1069). `session-continue.sh clear` spends that budget (261). It also stands down for the kill phrase (952), for a team assignee (969-983) and for a fresh teardown marker (985; `CC_TEARDOWN_DIR`, `CC_WF_TEARDOWN_FRESH_S`). |
| 3 | **1199** (`ship_floor`, rung 📦; emitted at 1210-1213 with `mark_blocked ship-floor`) | No sentinel is armed and the mechanical arm did not fire. The ledger rung is `📦` (committed, not landed), and `session_unlanded_mine` attributes the unlanded commits to this session (1148-1153). HEAD has not already been floored (latched per HEAD sha, 1174). The hook tells the session to /ship or to name the park explicitly (reason at 1187). | **`CC_SHIP_FLOOR=0`** (1101). **`CC_SHIP_FLOOR_MAX`** is the per-session budget (default 2, 1164/1176). It also stands down for the kill phrase (1103), a team assignee (1105-1111) and a teardown marker (1112), and it needs `jq`. |
| 4 | **1199** (`ship_floor`, rung 🚀; same emit site) | Same gate as #3, but the ledger rung is `🚀`: the work is landed, but the live layer has breached its converge budget. The session must also have written paths, per `session_writes_paths` (1155-1157). The hook tells the session to run `scripts/deploy-live.sh` (reason at 1189-1195). | Same levers as #3: `CC_SHIP_FLOOR=0`, `CC_SHIP_FLOOR_MAX`, the kill phrase, assignee and teardown stand-downs, and the per-HEAD-sha latch. |
| 5 | **895** (`wake_floor`; emitted at 1215-1218 with `mark_blocked wake-floor`) | No sentinel is armed and no ship floor fired. The session is about to go idle with **no inbox wake path armed** (`mailbox_wake_armed` false, 614). It fires on the first such stop (cnt 0), or whenever mail is pending or dispatched-session custody is open (805). The hook tells the session to arm `cc-await-ping` (or the `--idle-scoped` form under a live /goal). | **`CC_WAKE_FLOOR=0`** (604). **`CC_WAKE_FLOOR_MAX`** is the budget (default 2, 807/838). **`CC_WAKE_FLOOR_TTL_S`** is the re-fire spacing (default 600 s, 808/847). It also stands down for: the kill phrase (852); a pane-less session (`CC_PANE_ID` set without `ITERM_SESSION_ID`, 656); a live /goal with mail already pending (697); and a team assignee or teardown marker (776-797, gated by `CC_WAKE_FLOOR_TEARDOWN`, default 1). It needs `jq` and a valid pane id. Arming the watcher satisfies it (614). |

The inbox-mail fold (1286-1326) is not a separate condition. Mail rides inside block #1's reason and never blocks alone. Pending mail is only one of the triggers for #5.


## Tool calls (7) with the first 300 chars of each result
1. `Bash: {"command": "wc -l /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh; grep -n 'block\\|exit 2\\|decision' /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh | head -150", "description": "Count lines and grep block decisions in hook"}`
   →     1346 /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh
9:# dumb actuator — it just blocks the stop and feeds the next step back, with a hard
32:#   (c) CAP RE-ARM — a fresh `set` resets `.count`; the block reason instructs re-`set` each 🔧 turn
36:# NOTE: deliberately NO `set -e` — a Stop hook t
2. `Bash: {"command": "sed -n 100,135p /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh; echo ----; sed -n 330,480p /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh | grep -v '^ *#'", "description": "Read hook header and early main flow"}`
   → # tty, and a state write above it would record a Stop that never happened. The library is sourced ONLY
# on this arm, so the hot path pays nothing.
# `$0`'s own symlink is resolved FIRST: a brand-new hooks/lib file has no ~/.claude/hooks/lib symlink
# until install.sh runs, and the live hook IS a sy
3. `Bash: {"command": "sed -n 480,1346p /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh | grep -nv '^ *#' | awk -F: '{ $1=$1+479; print }' OFS=:", "description": "Read rest of hook without comment lines"}`
   → 511:
525:if [ -n "${AGENT_IDENTITY_LIB:-}" ]; then
526:  _ailib="$AGENT_IDENTITY_LIB"
527:else
528:  _ailib="$_scd/lib/agent-identity.sh"
529:  [ -f "$_ailib" ] || { _ait="$0"; [ -L "$_ait" ] && _ait="$(readlink "$_ait")"
530:    _ailib="$(cd "$(dirname "$_ait")" 2>/dev/null && pwd)/lib/agent-identi
4. `Bash: {"command": "sed -n 136,330p /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh | grep -nv '^ *#' | awk -F: '{ $1=$1+135; print }' OFS=: | cut -c1-220", "description": "Read CLI modes and Stop preamble"}`
   → 136:
138:case "${1:-}" in
139:  set)
140:    f=$(sentinel_for "$PWD")
141:    printf '%s' "${2:-Continue the in-scope work.}" > "$f"
142:    rm -f "${f}.count" 2>/dev/null   # fresh chain → reset the loop counter (D-7 re-arm lever)
145:    csid="${CLAUDE_CODE_SESSION_ID:-${CLAUDE_SESSION_ID:-}}"
146
5. `Bash: {"command": "grep -n \"^KILL_RE=\\|^kill_switch_active\\|^mechanical_arm\\|^ship_floor\\|^wake_floor\\|^wf_teardown_marked\" /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh; mkdir -p /tmp/tokeff-gate/f2/out/B01-r5", "description": "Locate function and kill-regex line numbers"}`
   → 348:KILL_RE='(^|[^[:alnum:]])and( then)? stop([^[:alnum:]]|$)|no[ _-]?auto[ _-]?continue|(^|[^[:alnum:]])just do [^[:space:]]|(^|[^[:alnum:]])stop here([^[:alnum:]]|$)|come back to this|^[[:space:]]*(stop|halt)[[:space:].!]*$'
391:kill_switch_active() {
551:wf_teardown_marked() { # → 0 = a fresh tea
6. `Write: {"file_path": "/tmp/tokeff-gate/f2/out/B01-r5/answer.md", "content": "# session-continue.sh (Stop hook): the conditions that block a stop\n\nFile: `/tmp/tokeff-gate/f2/tree/hooks/session-continue.sh` (1346 lines).\n\nThe Stop path always exits 0. Every block is a `{decision:\"block\", reason:…}` JSO`
   → File created successfully at: /tmp/tokeff-gate/f2/out/B01-r5/answer.md (file state is current in your context — no need to Read it back)
7. `StructuredOutput: {"answer_path": "/tmp/tokeff-gate/f2/out/B01-r5/answer.md", "headline": "The session-continue.sh Stop hook blocks a stop under 5 conditions: (1) an agent-armed continuation sentinel, blocked at 1334/1336 and capped by CLAUDE_CONTINUE_MAX; (2) the mechanical arm for uncommitted files this session wro`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
