# Dossier 6

## Brief
```
In /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh, list every condition under which this Stop hook blocks a stop (emits a block decision or a blocking reason). For each give the line number, one sentence on the trigger, and the env var or kill switch that disables it, if any. numbers: {"conditions": <how many you listed>}.
```

## Returned headline
session-continue.sh blocks a stop under 5 conditions, all by printing {decision:"block"} JSON while exiting 0: an agent-armed sentinel (1336/1334, limited by CLAUDE_CONTINUE_MAX), a sentinel the hook arms itself for this session's uncommitted files (armed at 1072, disabled by CC_MECH_CONTINUE=0), the ship floor for unlanded work on the 📦 rung and not-live work on the 🚀 rung (1199, disabled by CC_SHIP_FLOOR=0), and the wake floor (895, disabled by CC_WAKE_FLOOR=0). An operator kill-switch phrase turns off all five.

## Returned numbers
`{"conditions": 5}`

## answer.md
# session-continue.sh: the conditions under which the Stop hook blocks a stop

File: /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh (1346 lines). Line numbers come from `grep -n` and `sed -n` on that file.

How it blocks: in Stop (actuation) mode the hook always exits 0. It blocks only by printing a `{decision:"block",reason:...}` JSON object. The `exit 2` paths at lines 116, 130 and 216 run only in the `--why`, `set`, `clear` and `status` CLI modes, never in a Stop, and line 130 exits 0 in actuation mode. The hook prints at most one JSON object per Stop.

The order is:
1. No sentinel: mechanical arm, then ship floor, then wake floor (lines 1207-1225).
2. Sentinel present, or just armed by the mechanical arm: kill-switch check (1230), then SID-bind check (1248), then cap check (1260), then the block (1334/1336).

A kill-switch phrase (KILL_RE, line 347) in the last genuine operator message disables every condition below. KILL_RE covers "…and stop", "no auto-continue", "just do X", "stop here", "come back to this", and a bare "stop" or "halt". It is not an env var.

| # | Line (emit) | Trigger | Env var / kill switch that disables it |
|---|---|---|---|
| 1 | 1336 (1334 when peer mail is folded in; reason built at 1304) | A continuation sentinel armed by the agent's `session-continue.sh set "<step>"` exists for this cwd. The stop is blocked with "🔧 Loose ends remain — Next: <step>" until the per-chain counter reaches the cap. Any pending inbox mail is prepended to the reason (1311-1318). | Kill-switch phrase (1230). Also stops when the sentinel's `.sid` differs from this session's sid (1248). `CLAUDE_CONTINUE_MAX` (default 8) caps it at 1260, and `CLAUDE_CONTINUE_MAX=0` disables it outright. `session-continue.sh clear` removes the sentinel. |
| 2 | Armed at 1072 by `mechanical_arm`; emits through the same 1334/1336 path | There is no sentinel, the wrap-ledger rung is 🔧, and at least one uncommitted dirty file was written by THIS session (`session_dirty_mine`). The hook then writes a "Commit the N file(s) you edited…" sentinel itself and falls through to the block. | `CC_MECH_CONTINUE=0` (941). Kill-switch phrase (952). `CC_MECH_MAX` budget (default 2 per session, 1064). Also skipped for a confirmed or undecidable Agent-Teams assignee (970-981) and for a fresh teardown marker (985). The `CLAUDE_CONTINUE_MAX` cap and the SID-bind check from #1 also apply. |
| 3 | 1199 (reason 1187; printed at 1212) | Ship floor, 📦 rung: there is no sentinel, the mechanical arm did not arm, and the ledger rung is 📦 (committed but not landed). `session_unlanded_mine` must show the unlanded commits hold this session's own writes. It fires once per HEAD sha. | `CC_SHIP_FLOOR=0` (1101). Kill-switch phrase (1103). `CC_SHIP_FLOOR_MAX` budget (default 2 per session, 1176). Also skipped for an assignee (1105-1110), a teardown marker (1112), or when the HEAD sha is already latched (1174). |
| 4 | 1199 (reason 1189; printed at 1212) | Ship floor, 🚀 rung: same path as #3, but the ledger rung is 🚀 (landed but not live: the converge budget is breached) and `session_writes_paths` shows this session wrote something. The reason tells the agent to run deploy-live.sh. | Same as #3: `CC_SHIP_FLOOR=0`, the kill-switch phrase, `CC_SHIP_FLOOR_MAX`, and the assignee, teardown and sha-latch skips. |
| 5 | 894-895 (printed at 1217) | Wake floor: there is no sentinel and neither floor above blocked. The pane has an inbox identity (`CC_PANE_ID` or `ITERM_SESSION_ID`) and no `cc-await-ping` watcher is armed. It then fires on the session's first idle, when inbox mail is pending, or while open cc-custody dispatches exist for this pane (805). The reason tells the agent to arm the watcher. | `CC_WAKE_FLOOR=0` (604). Kill-switch phrase (852). `CC_WAKE_FLOOR_MAX` budget (default 2, 812) and the `CC_WAKE_FLOOR_TTL_S` backoff (default 600 s, 846). It stands down for a pane-less headless session (`CC_PANE_ID` set without `ITERM_SESSION_ID`), when a /goal is live and mail is pending, or for a team assignee or teardown marker (776-797). Setting `CC_WAKE_FLOOR_TEARDOWN=0` turns that last stand-down off, which makes the floor fire more often. |

Notes:
- Peer-mail folding (1286-1326) is not a separate trigger. It only adds text to the block from #1 or #2.
- The floors (#3-#5) apply only when no sentinel exists. A stop already blocked by a sentinel "is not idle" (1203-1204).
- The disabling behaviour of `CLAUDE_CONTINUE_MAX=0` is inferred from the `[ "$n" -ge "$MAX" ]` check at 1260. It was not run.


## Tool calls (10) with the first 300 chars of each result
1. `Bash: {"command": "wc -l /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh; ls -la /tmp/tokeff-regate/f2/out/B01-r7/ 2>&1", "description": "Check hook file size and output dir"}`
   →     1346 /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh
total 0
drwxr-xr-x@  2 chrisren  wheel    64 Sep 24 13:39 .
drwxr-xr-x@ 82 chrisren  wheel  2624 Sep 24 13:39 ..
2. `Bash: {"command": "grep -n -iE 'block|decision|reason|exit 2' /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh | head -200", "description": "Find block/decision sites in hook"}`
   → 9:# dumb actuator — it just blocks the stop and feeds the next step back, with a hard
32:#   (c) CAP RE-ARM — a fresh `set` resets `.count`; the block reason instructs re-`set` each 🔧 turn
36:# NOTE: deliberately NO `set -e` — a Stop hook that exits 2 *blocks the stop*, so an
45:# ── B-3 telemetry —
3. `Bash: {"command": "sed -n 1,200p /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh", "description": "Read hook header"}`
   → #!/usr/bin/env bash
# session-continue.sh — 🔧 loose-ends continuation loop (agent-set sentinel + Stop-hook actuator).
#
# WHY: a Stop hook fired on its own is SCOPE-BLIND — a shell script can't tell an
# in-scope loose end from an intentional pause or out-of-scope dirt, so a standalone
# one loops o
4. `Bash: {"command": "sed -n 300,480p /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh", "description": "Read actuation start"}`
   →       # different words even though they earn the same refusal.
      echo "ARMED ($(cat "${f}.count" 2>/dev/null || echo 0) continuations, sid=$(cat "${f}.sid" 2>/dev/null || echo 'unrecorded')): $(cat "$f")"
    else echo "inactive"; fi
    exit 0 ;;
esac

# ---- Stop-hook actuation mode (no recog
5. `Bash: {"command": "sed -n 590,910p /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh | grep -v '^ *#'", "description": "Read wake floor code without comments"}`
   → wake_floor() { # → echoes JSON on stdout when it wants to BLOCK; otherwise silent. Never fails.
  [ "${CC_WAKE_FLOOR:-1}" = 1 ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  command -v mailbox_wake_armed >/dev/null 2>&1 || return 0
  case "$_ouid" in ''|.|..|.*|*[!A-Za-z0-9._-]*) return 
6. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/hooks; grep -n 'CC_WAKE_FLOOR\\|CC_SHIP\\|kill_switch_active\\|CLAUDE_CONTINUE\\|cnt\" -eq 0\\|return 1\\|exit 0\\|exit 2' session-continue.sh | sed -n 1,200p; sed -n 820,836p session-continue.sh", "description": "Locate key guard lines"}`
   → 37:# accidental non-zero exit could force a false continuation. Every actuation path ends `exit 0`.
46:# This is the hook that drives the loop: it emits {decision:"block"} up to CLAUDE_CONTINUE_MAX
114:  # LOUD, never a silent exit 0 — a pointer that resolves to nothing is the defect this tier close
7. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/hooks; sed -n 795,806p session-continue.sh; echo ----; sed -n 905,1346p session-continue.sh | grep -n -v '^ *#' | awk -F: '{n=$1+904; $1=\"\"; print n\":\"$0}'", "description": "Read mechanical arm, ship floor, main actuation"}`
   →       log_idl abstained "wake-floor-teardown" "$(jq -cn --argjson p "$pend" --arg w "$_wf_why" '{pend:$p,why:$w}' 2>/dev/null)"
      return 0
    fi
  fi

  # Fire on the first idle of the session, any idle where mail is actually waiting, or any idle
  # while dispatched work THIS PANE OWNS (or tha
8. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/hooks; sed -n 505,590p session-continue.sh; echo ----; sed -n 905,968p session-continue.sh; sed -n 1086,1099p session-continue.sh; sed -n 1202,1245p session-continue.sh", "description": "Read seam comments and guards"}`
   → #
# FAIL-SAFE DIRECTION IS ASYMMETRIC AND DELIBERATE: no evidence ⇒ do NOT abstain ⇒ the floor applies
# exactly as before. Abstaining on ignorance would silently disarm the entire fleet — the same
# reasoning by which cc-await-ping's owner guard refuses to read reparenting as death.
# Seams: CC_WAK
9. `Bash: {"command": "cat > /tmp/tokeff-regate/f2/out/B01-r7/answer.md <<'EOF'\n# session-continue.sh: the conditions under which the Stop hook blocks a stop\n\nFile: /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh (1346 lines). Line numbers come from `grep -n` and `sed -n` on that file.\n\nHow it block`
   → (Bash completed with no output)
10. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B01-r7/answer.md", "headline": "session-continue.sh blocks a stop under 5 conditions, all by printing {decision:\"block\"} JSON while exiting 0: an agent-armed sentinel (1336/1334, limited by CLAUDE_CONTINUE_MAX), a sentinel the hook arms itself for this se`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
