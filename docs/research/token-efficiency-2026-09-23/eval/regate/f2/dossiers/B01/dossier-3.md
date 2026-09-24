# Dossier 3

## Brief
```
In /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh, list every condition under which this Stop hook blocks a stop (emits a block decision or a blocking reason). For each give the line number, one sentence on the trigger, and the env var or kill switch that disables it, if any. numbers: {"conditions": <how many you listed>}.
```

## Returned headline
session-continue.sh blocks a stop in 4 ways, each emitting decision:"block" while the process exits 0. (1) The agent-armed continuation sentinel, emitted at 1331-1336 and disabled by a kill phrase, `clear`, CLAUDE_CONTINUE_MAX or the SID-bind check. (2) The mechanical 🔧 arm for this session's own uncommitted writes, which arms at 1072 and uses the same emit, disabled by CC_MECH_CONTINUE=0 or CC_MECH_MAX. (3) The ship floor for 📦/🚀 own work at 1199, disabled by CC_SHIP_FLOOR=0 or CC_SHIP_FLOOR_MAX. (4) The wake floor for going idle with no inbox watcher at 894-895, disabled by CC_WAKE_FLOOR=0, CC_WAKE_FLOOR_MAX or CC_WAKE_FLOOR_TTL_S.

## Returned numbers
`{"conditions": 4}`

## answer.md
# Blocking conditions in `hooks/session-continue.sh` (Stop mode)

The hook blocks a stop in **4** ways. Each one emits `{"decision":"block","reason":…}` on stdout, and the process always exits 0. Only the CLI verbs (`set`/`clear`/`status`/`--why`) ever exit 2, and none of them runs as a Stop hook (lines 116, 130, 216). At most one block goes out per Stop. When no sentinel is armed, the floors are tried in order at lines 1207-1225: mechanical, then ship, then wake.

| # | Arm | Block emitted at | Trigger (one sentence) | Disabled by |
|---|---|---|---|---|
| 1 | **Armed continuation (agent-set sentinel)** | 1331-1336 (`mark_blocked continue`; `jq … decision:"block"`) | A sentinel file exists for this cwd because the agent ran `session-continue.sh set "<step>"`. It blocks only if the last user message has no kill phrase (1232), the stored sid matches the current session (1245), and `.count` is below the cap (1260). The pending inbox mail is placed in front of the reason (1300-1325). | Kill-switch phrase in the last non-meta user message (`KILL_RE`, 349; checked 1232). `session-continue.sh clear`, which also spends the `.mech` budget. `CLAUDE_CONTINUE_MAX` (default 8, 1257): the cap clears the sentinel and allows the stop, and a fresh `set` resets the count. The SID-bind check clears a sentinel inherited from a different session. |
| 2 | **Mechanical 🔧 arm** | Arms at 1072 (writes the sentinel), falls through from 1209 into the same emit as #1 at 1331-1336 | The sentinel is absent, `wrap-ledger.sh --machine` reports `RUNG=🔧`, and `session_dirty_mine` attributes at least one uncommitted file to this session's own writes. The hook then auto-writes a "Commit the N file(s)…" sentinel and blocks as in #1. | `CC_MECH_CONTINUE=0` (941). `CC_MECH_MAX` per-session budget (default 2, 1055). Kill-switch phrase (949). Assignee exemption (confirm rc 0 or 2, 961-973). Teardown marker (975). `session-continue.sh clear` spends the budget. After arming, it is also bound by everything in #1, including `CLAUDE_CONTINUE_MAX`. |
| 3 | **Ship floor (📦/🚀)** | 1199 (`jq … decision:"block"` inside `ship_floor`), printed at 1210-1213 | The session is going idle with no sentinel. The ledger rung is 📦 and the unlanded commits contain this session's own writes (`session_unlanded_mine`), or the rung is 🚀 and the session wrote files this session. It fires once per HEAD sha. | `CC_SHIP_FLOOR=0` (1101). `CC_SHIP_FLOOR_MAX` per-session budget (default 2, 1164). Kill-switch phrase (1103). Assignee exemption (1104-1110). Teardown marker (1111). Same-sha latch (1175). |
| 4 | **Wake floor** | 894-895 (`jq … decision:"block",reason,systemMessage`), printed at 1215-1218 | The session is going idle with no sentinel and no inbox watcher armed (`mailbox_wake_armed` is false). It blocks on the first idle of the session, or when mail is pending, or when there are open custody rows this session dispatched and that have not returned. The block tells the agent to arm `cc-await-ping` (the `--idle-scoped` form under a live /goal). | `CC_WAKE_FLOOR=0` (604). `CC_WAKE_FLOOR_MAX` attempts per session (default 2, 807 and 838). `CC_WAKE_FLOOR_TTL_S` minimum re-attempt spacing (default 600 s, 808 and 847). Kill-switch phrase (852). It also stands down for a headless session (`CC_PANE_ID` set without `ITERM_SESSION_ID`, 656), for a live /goal with mail pending (695), and for a team assignee or a session with a fresh teardown marker (776-800). `CC_WAKE_FLOOR_TEARDOWN=0` turns off that last abstain, so it widens blocking rather than disabling it. |

## Notes
- Several stops are allowed but still emit a `systemMessage`, and none of them is a block: the continuation cap reached (1266), the wake-floor budget spent (841), the wake-floor abstain paths with mail pending (659, 697, 796), and the wake-floor kill-switch (853).
- Global safety rule: if `continue-sentinel.sh` cannot be sourced, Stop mode exits 0 and allows the stop (130). If `jq` is missing, every floor abstains.


## Tool calls (8) with the first 300 chars of each result
1. `Bash: {"command": "wc -l /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh; grep -n 'block\\|decision\\|exit\\|_OFF\\|=off\\|CC_\\|CLAUDE_' /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh | head -300", "description": "Count lines and grep block/env sites in the hook"}`
   →     1346 /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh
9:# dumb actuator — it just blocks the stop and feeds the next step back, with a hard
20:# Sentinel lives OUTSIDE any repo (per-account state dir: ${CLAUDE_CONFIG_DIR:-~/.claude}/state),
22:# including different accounts (each with its ow
2. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/hooks; sed -n 300,400p session-continue.sh; echo ------; sed -n 1195,1346p session-continue.sh", "description": "Read main Stop flow and final block path"}`
   →       # different words even though they earn the same refusal.
      echo "ARMED ($(cat "${f}.count" 2>/dev/null || echo 0) continuations, sid=$(cat "${f}.sid" 2>/dev/null || echo 'unrecorded')): $(cat "$f")"
    else echo "inactive"; fi
    exit 0 ;;
esac

# ---- Stop-hook actuation mode (no recog
3. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/hooks; sed -n 400,470p session-continue.sh; echo -----; sed -n 600,900p session-continue.sh", "description": "Read lag-ack and wake floor function"}`
   → # continuation is the COMMON case, so gating this on the sentinel (as the mail FOLD below is) would leave
# .acked lagging .seen forever and make cc-inbox-guard false-alarm on already-consumed mail. Promoting is
# safe unconditionally: it only advances .acked→.seen (never past what was emitted), so 
4. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/hooks; sed -n 935,1195p session-continue.sh", "description": "Read mechanical arm and ship floor"}`
   → # are in this file (the mechanical arm and the ship floor, which already share one sample via
# SC_LED_CACHE). They are one event, so they should observe one snapshot: handing the ledger this
# session's transcript is what lets it serve one. Absent ⇒ that script computes as it always has.
_sc_tp="$T
5. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/hooks; sed -n 95,135p session-continue.sh", "description": "Check early exit-2 paths are CLI-only"}`
   → }

# ── `--why <topic>` REFERENCE TIER (backlog 1031594b6327; docs/plans/STOPHOOK_MESSAGE_TIERING.md §3) ──
# Dispatched HERE — before stdin is read and before any IDL/latch/state write — because this arm is run
# from a TERMINAL by a reader holding one of this hook's messages. A `cat` above it bloc
6. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/hooks; grep -n 'Commit the \\${n_files}\\|^mechanical_arm\\|^ship_floor\\|^wake_floor\\|if ! mechanical_arm\\|f=\"\\$f\"\\|set)' session-continue.sh | head; grep -n 'agent_assignee_argv\\|wf_teardown_marked()' session-continue.sh | head -3", "description": `
   → 139:  set)
443:    # (bin/cc-await-ping `_keys()` → mailbox_keyset). The invariant is COVERAGE, not agreement.
603:wake_floor() { # → echoes JSON on stdout when it wants to BLOCK; otherwise silent. Never fails.
940:mechanical_arm() {   # rc 0 = armed (fall through to the armed path) · rc 1 = did not
7. `Write: {"file_path": "/tmp/tokeff-regate/f2/out/B01-r1/answer.md", "content": "# Blocking conditions in `hooks/session-continue.sh` (Stop mode)\n\nThe hook blocks a stop in **4** ways. Each one emits `{\"decision\":\"block\",\"reason\":…}` on stdout, and the process always exits 0. Only the CLI verbs (`set`
   → File created successfully at: /tmp/tokeff-regate/f2/out/B01-r1/answer.md (file state is current in your context — no need to Read it back)
8. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B01-r1/answer.md", "headline": "session-continue.sh blocks a stop in 4 ways, each emitting decision:\"block\" while the process exits 0. (1) The agent-armed continuation sentinel, emitted at 1331-1336 and disabled by a kill phrase, `clear`, CLAUDE_CONTINUE_`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
