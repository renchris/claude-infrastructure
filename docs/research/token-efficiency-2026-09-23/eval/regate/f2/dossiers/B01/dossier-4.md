# Dossier 4

## Brief
```
In /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh, list every condition under which this Stop hook blocks a stop (emits a block decision or a blocking reason). For each give the line number, one sentence on the trigger, and the env var or kill switch that disables it, if any. numbers: {"conditions": <how many you listed>}.
```

## Returned headline
session-continue.sh blocks a Stop under 5 conditions: (1) an agent-armed `set` sentinel (1334/1336; disabled by clear, a kill phrase, a SID mismatch or CLAUDE_CONTINUE_MAX); (2) the mechanical arm, when this session's own uncommitted files sit on a 🔧 ledger (it arms the sentinel and blocks through the same path; CC_MECH_CONTINUE=0 / CC_MECH_MAX); (3) the ship floor on 📦 unlanded commits of its own and (4) on 🚀 landed-but-not-live work (both at 1199; CC_SHIP_FLOOR=0 / CC_SHIP_FLOOR_MAX / a per-HEAD latch); and (5) the wake floor, when it goes idle with no inbox watcher (895; CC_WAKE_FLOOR=0 / CC_WAKE_FLOOR_MAX / CC_WAKE_FLOOR_TTL_S). All four floors stand down on an operator kill phrase.

## Returned numbers
`{"conditions": 5}`

## answer.md
# session-continue.sh: the conditions that block a Stop

File: `/tmp/tokeff-regate/f2/tree/hooks/session-continue.sh` (1346 lines).

In Stop mode the hook always exits 0. It blocks a stop only by printing JSON containing `{decision:"block", reason:…}`, and it prints at most one such object per Stop. The `exit 2` lines at 116, 130 and 216 are not Stop blocks: they belong to the terminal/CLI arms (`--why`, `set|clear|status` when a library is missing, and a bad `clear` flag).

There are **5 blocking conditions**. The first is the agent-armed path. The other four are "idle floors", which run only when no sentinel exists (1207-1222). The floors are tried in this order: mechanical, then ship, then wake.

| # | Line (emit) | Trigger (one sentence) | Disabled by |
|---|---|---|---|
| 1 | **1334 / 1336** (block JSON; `mark_blocked continue` at 1331) | A continuation sentinel for this cwd exists, armed by `session-continue.sh set "<step>"` (CLI at 137-156), so the stop is blocked and the step is fed back as the next turn. Pending inbox mail is taken and folded into the same reason (1286-1326), which adds a `systemMessage`. | `session-continue.sh clear` (removes or spends the sentinel). An operator **kill-switch phrase** in the last non-meta user message (`KILL_RE`, 1230-1235). **SID mismatch**, meaning a sentinel inherited from another session (1247-1254). The **cap `CLAUDE_CONTINUE_MAX`** (default 8, 1257-1270; a fresh `set` zeroes the count). |
| 2 | 940-1080 arms the sentinel, then falls into the block at **1334 / 1336** | **Mechanical 🔧 arm.** No sentinel exists, `wrap-ledger.sh --machine` reports `RUNG=🔧` (1019), and `session_dirty_mine` finds uncommitted files that *this session* wrote (1024-1030). The hook then writes a "commit these N files" sentinel (1072) and blocks through path 1. | **`CC_MECH_CONTINUE=0`** (941). Kill-switch phrase (952). Confirmed or undecidable Agent-Teams assignee (970-983). A fresh teardown marker (`CC_TEARDOWN_DIR`, freshness `CC_WF_TEARDOWN_FRESH_S`, 985). Budget **`CC_MECH_MAX`** (default 2 per session, 1055-1069). Missing jq, session-writes lib or wrap-ledger (`SESSION_WRITES_LIB`, `WRAP_LEDGER_BIN` override paths). After arming, the path-1 bounds (`CLAUDE_CONTINUE_MAX`, kill-switch, `clear`) also apply. |
| 3 | **1199** (returned rc 1; printed at 1210-1213, `mark_blocked ship-floor`) | **Ship floor 📦.** Going idle while the ledger reads `RUNG=📦` (committed but not landed), and `session_unlanded_mine` attributes the unlanded commits to this session. The reason tells it to `/ship` (1187). | **`CC_SHIP_FLOOR=0`** (1101). Kill-switch phrase (1103). Assignee (1105-1111). Teardown marker (1112). Commits not this session's (1152-1153). Latch: it fires once per HEAD sha (1174-1175). Budget **`CC_SHIP_FLOOR_MAX`** (default 2 per session, 1176-1180). |
| 4 | **1199** (same emit as #3) | **Ship floor 🚀.** Going idle while the ledger reads `RUNG=🚀` (landed but not live, i.e. the live layer has breached its converge budget), and `session_writes_paths` shows this session wrote something. The reason tells it to run `scripts/deploy-live.sh` (1189-1195). | Same switches as #3: `CC_SHIP_FLOOR=0`, kill-switch, assignee, teardown marker, per-HEAD-sha latch, `CC_SHIP_FLOOR_MAX`. |
| 5 | **895** (returned rc 1; printed at 1215-1218, `mark_blocked wake-floor`) | **Wake floor.** Going idle with no inbox watcher armed (`mailbox_wake_armed` is false) in a pane that has an inbox identity. It fires on the session's **first** idle, or whenever **mail is pending**, or whenever **dispatched sessions this pane fired (custody rows) are still open** (805). It demands that the session arm `cc-await-ping` (the `--idle-scoped` form if a /goal is live). | **`CC_WAKE_FLOOR=0`** (604). An armed watcher (it clears the budget, 612). Kill-switch phrase (832-836). Budget **`CC_WAKE_FLOOR_MAX`** (default 2, 822-830) and spacing **`CC_WAKE_FLOOR_TTL_S`** (default 600 s, 831). Team-assignee or teardown-marker abstain, gated by **`CC_WAKE_FLOOR_TEARDOWN`** (default 1; setting it to 0 removes this exemption, 757-780). Pane-less headless session (`CC_PANE_ID` set without `ITERM_SESSION_ID`, 695-702). A live /goal while mail is already pending (720-727). Missing jq or mailbox lib, or an invalid pane id (605-607). |

## Notes
- **Fail-safe paths never block.** A missing `continue-sentinel.sh` exits 0 in Stop mode (130). Every floor returns 0 (allow) when jq, a library or the ledger is missing.
- **Some exhaustion branches emit only a `systemMessage`, which does not block.** These are the wake-floor budget, kill-switch, headless and goal-live cases, and the `CLAUDE_CONTINUE_MAX` cap message at 1266.
- **The kill-switch phrases** (`KILL_RE`, 349): "…and [then] stop", "no auto-continue", "just do X", "stop here", "come back to this", or a bare "stop"/"halt". They are read from the last user record that is not `isMeta` (351-389).


## Tool calls (8) with the first 300 chars of each result
1. `Bash: {"command": "f=/tmp/tokeff-regate/f2/tree/hooks/session-continue.sh; wc -l $f; grep -n 'block\\|exit 2\\|decision' $f | head -150", "description": "Locate block-decision sites in the hook"}`
   →     1346 /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh
9:# dumb actuator — it just blocks the stop and feeds the next step back, with a hard
32:#   (c) CAP RE-ARM — a fresh `set` resets `.count`; the block reason instructs re-`set` each 🔧 turn
36:# NOTE: deliberately NO `set -e` — a Stop hook
2. `Bash: {"command": "sed -n 95,135p /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh; echo ----; sed -n 300,420p /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh", "description": "Read hook header and guard sections"}`
   → }

# ── `--why <topic>` REFERENCE TIER (backlog 1031594b6327; docs/plans/STOPHOOK_MESSAGE_TIERING.md §3) ──
# Dispatched HERE — before stdin is read and before any IDL/latch/state write — because this arm is run
# from a TERMINAL by a reader holding one of this hook's messages. A `cat` above it bloc
3. `Bash: {"command": "sed -n 420,960p /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh | grep -v '^ *#'", "description": "Read wake-floor code without comments"}`
   → _ouid="${CC_PANE_ID:-${ITERM_SESSION_ID:-}}"; _ouid="${_ouid##*:}"
_opane="$_ouid"
if [ -f "$_mbxlib" ] && command -v jq >/dev/null 2>&1; then
  if . "$_mbxlib" 2>/dev/null; then
    case "$_ouid" in
      ''|.|..|.*|*[!A-Za-z0-9._-]*) : ;;
      *) if command -v mailbox_resolve_key >/dev/null 2>&1;
4. `Bash: {"command": "f=/tmp/tokeff-regate/f2/tree/hooks/session-continue.sh; grep -n 'cnt\" -eq 0\\|wake_floor()\\|mechanical_arm()\\|ship_floor\\|^[a-z_]*() *{' $f; sed -n 560,600p $f; sed -n 800,812p $f", "description": "Find function defs and wake-floor gating comments"}`
   → 85:log_idl() { # $1=disposition $2=reason $3=extra JSON OBJECT (optional, jq-built {…}; default {})
135:sentinel_for() { continue_sentinel_for "$1"; }
333:mark_blocked() { # $1 = which arm blocked (recorded for forensics, not read by the guard)
351:last_user_msg() {
391:kill_switch_active() {
551:wf
5. `Bash: {"command": "sed -n 960,1346p /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh | cat -n | awk '{ $1 = $1 + 959; print }' | grep -v '^[0-9]* *#'", "description": "Read mechanical arm, ship floor, main actuation with line numbers"}`
   → 969 local _ma_aid _ma_c
970 if _ma_aid="$(agent_assignee_argv)" && [ -n "$_ma_aid" ]; then
971 agent_team_member_confirms "$_ma_aid"; _ma_c=$?
972 if [ "$_ma_c" -eq 0 ] || [ "$_ma_c" -eq 2 ]; then
979 log_idl cleared "mechanical-assignee" "$(jq -cn --arg a "$_ma_aid" --argjson c "$_ma_c" \
980 '{ass
6. `Bash: {"command": "f=/tmp/tokeff-regate/f2/tree/hooks/session-continue.sh; sed -n 940,968p $f; sed -n 1200,1230p $f | grep -n '#'; sed -n 136,160p $f", "description": "Read mechanical arm head and sentinel set section"}`
   → mechanical_arm() {   # rc 0 = armed (fall through to the armed path) · rc 1 = did not arm
  [ "${CC_MECH_CONTINUE:-1}" = "0" ] && return 1
  command -v jq >/dev/null 2>&1 || return 1
  # The operator asked to stop → never manufacture a continuation. Checked HERE as well as in the
  # armed path so a
7. `Bash: {"command": "mkdir -p /tmp/tokeff-regate/f2/out/B01-r8 && cat > /tmp/tokeff-regate/f2/out/B01-r8/answer.md <<'EOF'\n# session-continue.sh: the conditions that block a Stop\n\nFile: `/tmp/tokeff-regate/f2/tree/hooks/session-continue.sh` (1346 lines).\n\nIn Stop mode the hook always exits 0. It blocks`
   → (Bash completed with no output)
8. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B01-r8/answer.md", "headline": "session-continue.sh blocks a Stop under 5 conditions: (1) an agent-armed `set` sentinel (1334/1336; disabled by clear, a kill phrase, a SID mismatch or CLAUDE_CONTINUE_MAX); (2) the mechanical arm, when this session's own unc`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
