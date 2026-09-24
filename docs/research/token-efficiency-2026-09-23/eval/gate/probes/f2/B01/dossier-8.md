# Dossier 8

## Brief
```
In /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh, list every condition under which this Stop hook blocks a stop (emits a block decision or a blocking reason). For each give the line number, one sentence on the trigger, and the env var or kill switch that disables it, if any. numbers: {"conditions": <how many you listed>}.
```

## Returned headline
session-continue.sh blocks a stop under 5 conditions. Ship floor 📦 is committed-but-unlanded work this session wrote (:1187/1199; CC_SHIP_FLOOR=0, CC_SHIP_FLOOR_MAX). Ship floor 🚀 is landed work that is not live (:1189/1199). The wake floor fires when the session goes idle with no inbox watcher armed on first idle, with pending mail or with open custody (:894; CC_WAKE_FLOOR=0, CC_WAKE_FLOOR_MAX, CC_WAKE_FLOOR_TTL_S). The mechanical 🔧 arm fires on uncommitted files this session wrote (:1072→1334; CC_MECH_CONTINUE=0, CC_MECH_MAX). The agent-armed sentinel continuation fires after `session-continue.sh set` (:1304/1334; clear, the kill phrase, sid mismatch, CLAUDE_CONTINUE_MAX). All blocks exit 0 with decision:block JSON; exit 2 occurs only in the CLI modes.

## Returned numbers
`{"conditions": 5}`

## answer.md
# session-continue.sh — every condition under which the Stop hook blocks a stop

File: `/tmp/tokeff-gate/f2/tree/hooks/session-continue.sh` (1346 lines).

Every block goes out as JSON `{decision:"block",reason:…}` on stdout with exit 0. Exit 2 only
happens in the CLI modes (`--why` with a missing tier at :116; `set|clear|status` with a missing
sentinel lib at :130), and those run from a terminal, not as a Stop. Fatal errors in Stop mode
exit 0 and allow the stop (:127-130).

This hook has **4 blocking arms**, and one of them has **2 distinct triggers**, so there are
**5 conditions**. The order in the file is: mechanical arm → ship floor → wake floor (these three
run only when no sentinel is armed, :1207-1222), then the armed-sentinel continuation.

| # | Line (emit) | Trigger (one sentence) | Disabled by |
|---|---|---|---|
| 1 | **1187 / 1199** (ship floor 📦; dispatched :1210-1213) | No sentinel is armed, the mechanical arm did not fire, the wrap-ledger rung is `📦`, and `session_unlanded_mine` says the committed-but-unlanded commits ahead of trunk were written by THIS session (:1130, :1148-1153). | `CC_SHIP_FLOOR=0` (:1101). Budget `CC_SHIP_FLOOR_MAX` (default 2 per session, :1164/:1176). Latched once per HEAD sha (:1174). Also stood down by an operator kill phrase (:1103), a confirmed team assignee (:1105-1111), or a teardown marker (:1112). |
| 2 | **1189 / 1199** (ship floor 🚀; same dispatch) | Same arm, but the rung is `🚀` (landed on trunk, while the live layer has breached its converge budget) and `session_writes_paths` shows this session wrote files (:1155-1157). The block tells the session to run `deploy-live.sh`. | The same switches as #1: `CC_SHIP_FLOOR=0`, `CC_SHIP_FLOOR_MAX`, the per-sha latch, a kill phrase, assignee, teardown. |
| 3 | **894-895** (wake floor; dispatched :1215-1218; gate :805) | No sentinel is armed and no inbox watcher is armed (`mailbox_wake_armed` false, :614). The session is about to idle, and one of these holds: it is the first idle this session (`cnt==0`), mail is pending, or open custody rows (dispatched sessions not yet returned) exist for this cwd (:805). | `CC_WAKE_FLOOR=0` (:606). Budget `CC_WAKE_FLOOR_MAX` (default 2) and `CC_WAKE_FLOOR_TTL_S` (default 600 s spacing) (:808-809, :837-850). An operator kill phrase (:852). `CC_WAKE_FLOOR_TEARDOWN=1` (the default) enables the assignee and teardown abstains (:776). It also abstains for a headless pane (`CC_PANE_ID` set, no `ITERM_SESSION_ID`, :656), for a live /goal with pending mail, when jq or the mailbox lib is missing, and for an invalid pane id (:607-609). |
| 4 | **1072 → 1334/1336** (mechanical 🔧 arm writes the sentinel at :1072, then falls through to the continuation block) | No sentinel is armed, the wrap-ledger rung is `🔧` (:1019), and `session_dirty_mine` shows files THIS session edited that are still uncommitted (:1024-1030). The hook then self-arms the sentinel with a "commit these N files" step and blocks. | `CC_MECH_CONTINUE=0` (:941). Budget `CC_MECH_MAX` (default 2 per session, :1055/:1064). Also: an operator kill phrase (:952), a confirmed team assignee (:969-983), a teardown marker (:985), `session-continue.sh clear` (which spends the budget), and the continuation cap `CLAUDE_CONTINUE_MAX` downstream (:1260). |
| 5 | **1304 / 1334-1336** (armed continuation; any pending inbox mail is folded into the same reason at :1311-1318) | A sentinel is armed (the agent ran `session-continue.sh set "<step>"`), no kill phrase is present, the stored sid matches, and `.count` is below the cap. The hook blocks with "🔧 Loose ends remain — Next: <step>". | `session-continue.sh clear` removes the sentinel. An operator kill phrase in the last genuine user message clears it (:1230). A sid mismatch (sentinel inherited across succession) clears it (:1248). The cap `CLAUDE_CONTINUE_MAX` (default 8) allows the stop at :1260. Note that each `set` zeroes `.count`, so the cap does not bound a chain that keeps re-arming. |

Notes:
- The kill phrases in `KILL_RE` (:350) are "…and [then] stop", "no auto-continue", "just do X",
  "stop here", "come back to this", and a bare "stop"/"halt". The hook reads them from the last
  non-`isMeta` user record (:352-384).
- `mark_blocked` (:333) writes the `.blocked` marker for completion-assert whenever arms 1-5 block.
- `systemMessage`-only outputs do not block: wake-floor budget exhausted (:840), its kill-switch and
  abstain notices, and the cap notice at :1266.


## Tool calls (7) with the first 300 chars of each result
1. `Bash: {"command": "wc -l /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh; grep -n -E 'block|decision|exit 2|reason' /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh | head -150", "description": "Count lines and grep block/decision sites in the hook"}`
   →     1346 /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh
9:# dumb actuator — it just blocks the stop and feeds the next step back, with a hard
32:#   (c) CAP RE-ARM — a fresh `set` resets `.count`; the block reason instructs re-`set` each 🔧 turn
36:# NOTE: deliberately NO `set -e` — a Stop hook t
2. `Bash: {"command": "sed -n 95,135p /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh; echo ----; sed -n 300,420p /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh", "description": "Read early exit paths and blocked-marker section"}`
   → }

# ── `--why <topic>` REFERENCE TIER (backlog 1031594b6327; docs/plans/STOPHOOK_MESSAGE_TIERING.md §3) ──
# Dispatched HERE — before stdin is read and before any IDL/latch/state write — because this arm is run
# from a TERMINAL by a reader holding one of this hook's messages. A `cat` above it bloc
3. `Bash: {"command": "sed -n 590,660p /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh; echo ----; sed -n 690,900p /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh | grep -v '^\\s*#'", "description": "Read wake floor function code"}`
   → #   · only on the FIRST idle of this session, or when mail is actually pending
#   · at most CC_WAKE_FLOOR_MAX attempts per session, no sooner than CC_WAKE_FLOOR_TTL_S apart
#   · NEVER after an operator kill-switch phrase (kill_switch_active) — that stop was asked for
#   · budget exhausted ⇒ a hum
4. `Bash: {"command": "sed -n 900,1346p /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh | grep -n -v '^\\s*#' | awk -F: '{n=$1+899; sub(/^[0-9]+:/,\"\"); print n\": \"$0}'", "description": "Read mech arm, ship floor, and main continue arm code"}`
   → 932: TP_MECH="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)"
938: _sc_tp="$TP_MECH"; case "$_sc_tp" in "~"*) _sc_tp="$HOME${_sc_tp#\~}" ;; esac
939: [ -n "$_sc_tp" ] && export WRAP_TRANSCRIPT="$_sc_tp"
940: mechanical_arm() {   # rc 0 = armed (fall through to the armed path
5. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree/hooks; grep -n -E '\"\\$cnt\" -eq 0|mailbox_wake_armed \"\\$_ouid\"|CC_PANE_ID:-\\}\" \\] && \\[ -z|CC_WAKE_FLOOR_TEARDOWN|kill_switch_active; then|^  set\\)|^  clear\\)|^case \"\\$\\{1' session-continue.sh; sed -n 136,160p session-continue.sh | grep -v '^\\s`
   → 138:case "${1:-}" in
139:  set)
157:  clear)
509:# Seams: CC_WAKE_FLOOR_TEARDOWN (0 disables both) · CC_WF_PSTABLE_FILE · CC_WF_MAX_HOPS ·
614:  if mailbox_wake_armed "$_ouid"; then rm -f "$sf" 2>/dev/null; return 0; fi
656:  if [ -n "${CC_PANE_ID:-}" ] && [ -z "${ITERM_SESSION_ID:-}" ]; then
776:  
6. `Bash: {"command": "mkdir -p /tmp/tokeff-gate/f2/out/B01-r4 && cat > /tmp/tokeff-gate/f2/out/B01-r4/answer.md <<'EOF'\n# session-continue.sh — every condition under which the Stop hook blocks a stop\n\nFile: `/tmp/tokeff-gate/f2/tree/hooks/session-continue.sh` (1346 lines).\n\nEvery block goes out as JSON `
   → (Bash completed with no output)
7. `StructuredOutput: {"answer_path": "/tmp/tokeff-gate/f2/out/B01-r4/answer.md", "headline": "session-continue.sh blocks a stop under 5 conditions. Ship floor 📦 is committed-but-unlanded work this session wrote (:1187/1199; CC_SHIP_FLOOR=0, CC_SHIP_FLOOR_MAX). Ship floor 🚀 is landed work that is not live (:1189/1199). T`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
