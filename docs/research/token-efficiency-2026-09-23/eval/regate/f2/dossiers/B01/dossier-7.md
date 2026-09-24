# Dossier 7

## Brief
```
In /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh, list every condition under which this Stop hook blocks a stop (emits a block decision or a blocking reason). For each give the line number, one sentence on the trigger, and the env var or kill switch that disables it, if any. numbers: {"conditions": <how many you listed>}.
```

## Returned headline
session-continue.sh blocks a stop in 5 conditions, emitted from 3 JSON sites: (1) the agent armed a continuation with `set` (:1334/1336, capped by CLAUDE_CONTINUE_MAX); (2) the mechanical arm finds uncommitted files this session wrote (:1072, then the same block; CC_MECH_CONTINUE=0 / CC_MECH_MAX); (3) the 📦 ship floor and (4) the 🚀 ship floor (:1199; CC_SHIP_FLOOR=0 / CC_SHIP_FLOOR_MAX, once per HEAD sha); (5) the wake floor, when no inbox watcher is armed (:895; CC_WAKE_FLOOR=0 / CC_WAKE_FLOOR_MAX / CC_WAKE_FLOOR_TTL_S). The operator kill phrase releases all five.

## Returned numbers
`{"conditions": 5}`

## answer.md
# session-continue.sh — every condition under which the Stop hook blocks

File: `/tmp/tokeff-regate/f2/tree/hooks/session-continue.sh` (1346 lines).

**5 blocking conditions.** They are emitted from 3 JSON sites: `{decision:"block"}` at :895 (wake floor), :1199 (ship floor) and :1334/:1336 (continuation). The hook always exits 0 in Stop mode; the block travels in the JSON.

The order of evaluation matters. If no sentinel is armed (:1207), the hook tries the mechanical arm (:1209). If that does not arm, it tries the ship floor (:1210), then the wake floor (:1215). An armed sentinel, whether armed by the agent or by the mechanical arm, goes to the continuation path (:1230–1337).

| # | Line (emit / dispatch) | Trigger | Disable / kill switch |
|---|---|---|---|
| 1 | :1334 / :1336 (`{decision:"block",reason:"🔧 Loose ends remain…"}`) | The agent armed a continuation sentinel with `session-continue.sh set "<step>"`. On Stop, the sentinel exists for this cwd, its stored sid matches the current session, and `.count` < cap. Any pending inbox mail is folded into the reason (:1311–1318); that is part of this same block, not a separate trigger. | `session-continue.sh clear`. Operator kill phrase in the last user message (`kill_switch_active`, :1230 clears and allows). Sid mismatch clears the sentinel (:1248). Cap `CLAUDE_CONTINUE_MAX` (default 8, :1257–1269): hitting it allows the stop with a systemMessage. A fresh `set` zeroes `.count`, so a re-arming chain is not bounded. |
| 2 | Arms at :1072 (`mechanical_arm`, called :1209), then falls through to the block at :1334/:1336 | No sentinel, and wrap-ledger `--machine` reports `RUNG=🔧` (:1019). `session_dirty_mine` then names ≥1 uncommitted file that THIS session wrote (:1024–1030). The arm writes a "Commit the N file(s)…" sentinel, and the continuation path blocks. | `CC_MECH_CONTINUE=0` (:941). Kill phrase (:952). Confirmed/unconfirmable team assignee (:970–981). Fresh teardown marker (:985; `CC_TEARDOWN_DIR`, `CC_WF_TEARDOWN_FRESH_S`). Per-session budget `CC_MECH_MAX` (default 2, :1055–1068). After that, the cap from row 1 (`CLAUDE_CONTINUE_MAX`) and `session-continue.sh clear` also apply. `clear` spends the mech budget (:261). |
| 3 | :1199 (`ship_floor`, dispatched :1210–1213), 📦 branch :1187 | No sentinel, the mechanical arm did not arm, and the ledger rung is `📦` (committed, not landed, :1130). `session_unlanded_mine` must confirm the unlanded commits are this session's against a real `TRUNK` (:1148–1153). Fires once per HEAD sha. | `CC_SHIP_FLOOR=0` (:1101). Kill phrase (:1103). Team assignee (:1105–1110). Teardown marker (:1112). Latched for the same HEAD sha (:1174). Budget `CC_SHIP_FLOOR_MAX` (default 2 per session, :1164/:1176). Test seams: `WRAP_LEDGER_BIN`, `SESSION_WRITES_LIB`. |
| 4 | :1199 (`ship_floor`), 🚀 branch :1189 | Same path, but the ledger rung is `🚀`: landed, but the live layer breached its converge budget. `session_writes_paths` must show that this session wrote files (:1155–1157). The reason tells the agent to run `scripts/deploy-live.sh`. | Same controls as row 3: `CC_SHIP_FLOOR=0`, kill phrase, assignee, teardown, HEAD-sha latch, `CC_SHIP_FLOOR_MAX`. |
| 5 | :895 (`wake_floor`, dispatched :1215–1218) | No sentinel, and neither the mechanical arm nor the ship floor fired. The session has a valid pane id (`_ouid`) and no armed inbox wake path (`mailbox_wake_armed` false, :617). It is the first attempt, OR mail is pending, OR open custody debts exist (:805). The TTL has elapsed (:846). The reason demands arming `cc-await-ping`, or `--idle-scoped --sid` when a /goal is live. | `CC_WAKE_FLOOR=0` (:604). Kill phrase (:852). Budget `CC_WAKE_FLOOR_MAX` (default 2, :807/:837). Retry spacing `CC_WAKE_FLOOR_TTL_S` (default 600 s). Automatic abstains: headless/pane-less session (`CC_PANE_ID` set and `ITERM_SESSION_ID` unset, :656); live /goal with mail pending (:673); team assignee or fresh teardown marker (:776–804; these abstains are governed by `CC_WAKE_FLOOR_TEARDOWN`, and setting it to 0 REMOVES the abstain, which means more blocking); missing jq, missing mailbox lib, or an invalid pane id (:605–607). |

## Exit 2 paths that are not Stop blocks

- :116 is `--why` mode.
- :130 is `set|clear|status` when the sentinel lib cannot be sourced.
- :216 is an unknown `clear` flag.

These are CLI invocations and never run on a Stop event. In Stop mode, a missing sentinel lib exits 0, which means allow (:130).

## Global override

No single env var disables every arm. The operator kill phrase (`kill_switch_active`, :391, which reads the last genuine user message) is honoured by all five: rows 1–2 at :1230/:952, rows 3–4 at :1103, and row 5 at :852.


## Tool calls (7) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/hooks && wc -l session-continue.sh && grep -n -E 'block|decision|reason|exit 2|_MAX|kill|=off|:-' session-continue.sh | head -300", "description": "Count lines and grep block-related lines in hook"}`
   →     1346 session-continue.sh
9:# dumb actuator — it just blocks the stop and feeds the next step back, with a hard
20:# Sentinel lives OUTSIDE any repo (per-account state dir: ${CLAUDE_CONFIG_DIR:-~/.claude}/state),
30:#       ignores a sentinel whose sid ≠ the actuating session's (kills S-12 cross-
2. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/hooks && sed -n 280,315p session-continue.sh; echo ----; sed -n 385,400p session-continue.sh; echo ----; sed -n 600,660p session-continue.sh", "description": "Read main-flow and wake-floor opening"}`
   →           [ -n "$_w" ] || _w="cwd unknown (armed before the .cwd stamp) — sentinel $_b"
          _others="${_others}
  · $_w"
        done
        # shellcheck disable=SC2016  # the backticks are MARKDOWN around a command the agent reads, not
        # a substitution — single quotes are exactly rig
3. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/hooks && sed -n 660,860p session-continue.sh | grep -v '^\\s*#'", "description": "Read wake floor gate conditions without comments"}`
   →         '{systemMessage:$m}' 2>/dev/null || true
    fi
    log_idl abstained "wake-floor-headless" "$(jq -cn --argjson p "$pend" '{pend:$p}' 2>/dev/null)"
    return 0
  fi

  local _wf_goal=""
  if command -v goal_live_condition >/dev/null 2>&1; then
    local _wf_tp
    _wf_tp="$(printf '%s' "$in
4. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/hooks && awk 'NR>=895 && NR<=1346 && $0 !~ /^[[:space:]]*#/ {print NR\": \"$0}' session-continue.sh", "description": "Read mech arm, ship floor, main armed path with line numbers"}`
   → 895:     '{decision:"block",reason:$r,systemMessage:$m}'
896:   return 1
897: }
898: 
932: TP_MECH="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)"
938: _sc_tp="$TP_MECH"; case "$_sc_tp" in "~"*) _sc_tp="$HOME${_sc_tp#\~}" ;; esac
939: [ -n "$_sc_tp" ] && export WRAP_TRANSCR
5. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/hooks && awk 'NR>=116 && NR<=137 || NR>=314 && NR<=340 || NR>=400 && NR<=470 || NR>=518 && NR<=575 {if ($0 !~ /^[[:space:]]*#/) print NR\": \"$0}' session-continue.sh; grep -n 'stop_hook_active' session-continue.sh", "description": "Read remaining guard sec`
   → 116:   exit 2
117: fi
118: _scd="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
119: _lib="$_scd/lib/continue-sentinel.sh"
120: [ -f "$_lib" ] || _lib="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/lib/continue-sentinel.sh"
121: [ -f "$_lib" ] || _lib="$HOME/.claude/hooks/lib/continue-sentinel.sh"
125: if 
6. `Bash: {"command": "mkdir -p /tmp/tokeff-regate/f2/out/B01-r5 && cat > /tmp/tokeff-regate/f2/out/B01-r5/answer.md <<'EOF'\n# session-continue.sh — every condition under which the Stop hook blocks\n\nFile: `/tmp/tokeff-regate/f2/tree/hooks/session-continue.sh` (1346 lines).\n\n**5 blocking conditions.** The`
   → (Bash completed with no output)
7. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B01-r5/answer.md", "headline": "session-continue.sh blocks a stop in 5 conditions, emitted from 3 JSON sites: (1) the agent armed a continuation with `set` (:1334/1336, capped by CLAUDE_CONTINUE_MAX); (2) the mechanical arm finds uncommitted files this sess`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
