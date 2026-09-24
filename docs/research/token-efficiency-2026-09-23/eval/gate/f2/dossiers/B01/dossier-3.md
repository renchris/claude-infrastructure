# Dossier 3

## Brief
```
In /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh, list every condition under which this Stop hook blocks a stop (emits a block decision or a blocking reason). For each give the line number, one sentence on the trigger, and the env var or kill switch that disables it, if any. numbers: {"conditions": <how many you listed>}.
```

## Returned headline
session-continue.sh blocks a stop under 5 conditions, always by printing decision:block JSON and exiting 0: the agent-armed 🔧 continuation (emitted at 1336, or 1334 with mail; ends via kill phrase, `clear` or CLAUDE_CONTINUE_MAX), the mechanical 🔧 arm for this session's own uncommitted files (armed 1072, CC_MECH_CONTINUE=0 or CC_MECH_MAX), the 📦 ship floor (1187/1199, CC_SHIP_FLOOR=0 or CC_SHIP_FLOOR_MAX), the 🚀 ship floor (1189/1199, same switches) and the wake floor (895, CC_WAKE_FLOOR=0, CC_WAKE_FLOOR_MAX or CC_WAKE_FLOOR_TTL_S); every one of them also stands down on an operator kill phrase.

## Returned numbers
`{"conditions": 5}`

## answer.md
# session-continue.sh: the conditions under which the Stop hook blocks a stop

File: `/tmp/tokeff-gate/f2/tree/hooks/session-continue.sh` (1346 lines).

In Stop mode the hook never blocks through its exit code; it always exits 0 (lines 1213, 1218, 1221, 1346). It blocks only by printing `{decision:"block",reason:…}` on stdout. That JSON is printed at three places: line 895 (wake floor), line 1199 (ship floor) and lines 1334/1336 (the continuation). Those three places cover **5 distinct conditions**.

| # | Emit line (condition line) | Trigger | Disabled by / kill switch |
|---|---|---|---|
| 1 | **1336** (1334 when mail is folded in) | **Agent-armed continuation.** The model ran `session-continue.sh set "<step>"`, so a sentinel file exists for this cwd (`[ ! -f "$f" ]` at 1207 is false). The hook then emits `🔧 Loose ends remain — do NOT stop yet. Next: <step>`. It first checks that no kill phrase is present (1230), that the sentinel's sid matches this session or either sid is unknown (1248), and that `.count` is below the cap (1260). | Operator kill phrase in the last non-meta user message (`KILL_RE` at 348: "and stop", "no auto-continue", "just do X", "stop here", "come back to this", bare "stop"/"halt"). `session-continue.sh clear`. Sid mismatch (successor session). `CLAUDE_CONTINUE_MAX` (default 8) caps the chain, but a fresh `set` zeroes `.count`, so it does not bound a chain that keeps re-arming. `CLAUDE_CONTINUE_MAX=0` effectively turns this arm off. There is no dedicated on/off env var. |
| 2 | 1072 arms the sentinel, then the block is emitted at **1336** | **Mechanical 🔧 (uncommitted own writes).** No sentinel exists. `wrap-ledger.sh --machine` reports `RUNG=🔧` (1019), and `session_dirty_mine` attributes at least one dirty path to this session's transcript (1024-1030). The hook then writes the sentinel with a "Commit the N file(s) you edited…" step and falls through to the same block as #1. | `CC_MECH_CONTINUE=0` (941). Budget `CC_MECH_MAX` (default 2) per session in `${f}.mech` (1055-1069). Kill phrase (952). Confirmed Agent-Teams assignee or an undecidable one (rc 0/2, 970-982). A fresh teardown marker (985; window `CC_WF_TEARDOWN_FRESH_S`, dir `CC_TEARDOWN_DIR`). Attribution rc ≠ 0 (1025). After arming, #1's kill-switch, sid and `CLAUDE_CONTINUE_MAX` checks also apply. `session-continue.sh clear` spends the budget. |
| 3 | **1199** (reason at 1187) | **Ship floor 📦.** No sentinel, and the mechanical arm did not fire. The ledger reports `RUNG=📦`, meaning committed but not landed (1130). `session_unlanded_mine` confirms the unlanded commits contain this session's own writes (1152). The current HEAD sha has not already been nudged this session (1174). | `CC_SHIP_FLOOR=0` (1101). `CC_SHIP_FLOOR_MAX` (default 2) per session, at most one block per HEAD sha (1164-1180). Kill phrase (1103). Assignee rc 0/2 (1105-1110). Teardown marker (1112). No trunk, or the commits are not this session's (1151-1153). |
| 4 | **1199** (reason at 1189) | **Ship floor 🚀.** Same path as #3, but the ledger reports `RUNG=🚀`: landed, but the live layer is past its converge budget. `session_writes_paths` shows this session wrote something (1156). The block tells the model to run `deploy-live.sh`. | Same switches as #3: `CC_SHIP_FLOOR=0`, `CC_SHIP_FLOOR_MAX`, per-sha latch, kill phrase, assignee, teardown marker. |
| 5 | **895** (reason at 860) | **Wake floor.** No sentinel, and neither the mechanical arm nor the ship floor fired. The session has a valid pane/inbox id (607), and `mailbox_wake_armed` is false, so no `cc-await-ping` watcher is live (614). It fires if any of these holds: first idle of the session (`cnt==0`), inbox mail pending, or open `cc-custody` rows owned by this pane or unattributable (805). The reason tells the model to arm `cc-await-ping`, or the `--idle-scoped --sid` form under a live /goal. | `CC_WAKE_FLOOR=0` (604). `CC_WAKE_FLOOR_MAX` (default 2): once exhausted it only sends a systemMessage (838-845). `CC_WAKE_FLOOR_TTL_S` (default 600 s) spacing between attempts (847). Kill phrase (852). `CC_WAKE_FLOOR_TEARDOWN` (default 1) gates the assignee/teardown abstain (776-798); with it at 1 an assignee or a torn-down session abstains. It also abstains for a headless session (`CC_PANE_ID` set, `ITERM_SESSION_ID` unset, 656), when a /goal is live and mail is pending (697), and when jq or the mailbox lib is missing (605-606). |

## Order and precedence
With no sentinel, the checks run in the order mechanical 🔧, then ship floor, then wake floor (1207-1222), and at most one of them emits per Stop. When the mechanical arm fires, the hook goes on to the armed path. Every blocking path writes the double-block marker `${f}.blocked` through `mark_blocked` (1211, 1216, 1331).

## Excluded (not a Stop block)
- The `exit 2` at line 116 belongs only to the `--why` CLI arm, when its library is missing.
- The `exit 2` at line 130 fires only for the `set`, `clear` and `status` CLI modes when the sentinel lib cannot be sourced. In Stop mode that same failure exits 0 and allows the stop.
- Several paths emit a `systemMessage` only, with no `decision`, so they never block: cap reached (1266), wake floor exhausted (842) or kill-switched (853), and the headless, goal and teardown abstains (659, 699, 792).


## Tool calls (8) with the first 300 chars of each result
1. `Bash: {"command": "wc -l /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh; grep -n 'block\\|decision\\|exit 2\\|reason' /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh | head -200", "description": "Count lines and grep block decisions in the hook"}`
   →     1346 /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh
9:# dumb actuator — it just blocks the stop and feeds the next step back, with a hard
32:#   (c) CAP RE-ARM — a fresh `set` resets `.count`; the block reason instructs re-`set` each 🔧 turn
36:# NOTE: deliberately NO `set -e` — a Stop hook t
2. `Read: {"file_path": "/tmp/tokeff-gate/f2/tree/hooks/session-continue.sh", "offset": 96, "limit": 40}`
   → 96	
97	# ── `--why <topic>` REFERENCE TIER (backlog 1031594b6327; docs/plans/STOPHOOK_MESSAGE_TIERING.md §3) ──
98	# Dispatched HERE — before stdin is read and before any IDL/latch/state write — because this arm is run
99	# from a TERMINAL by a reader holding one of this hook's messages. A `cat` abo
3. `Read: {"file_path": "/tmp/tokeff-gate/f2/tree/hooks/session-continue.sh", "offset": 300, "limit": 120}`
   → 300	      # different words even though they earn the same refusal.
301	      echo "ARMED ($(cat "${f}.count" 2>/dev/null || echo 0) continuations, sid=$(cat "${f}.sid" 2>/dev/null || echo 'unrecorded')): $(cat "$f")"
302	    else echo "inactive"; fi
303	    exit 0 ;;
304	esac
305	
306	# ---- Stop-h
4. `Read: {"file_path": "/tmp/tokeff-gate/f2/tree/hooks/session-continue.sh", "offset": 420, "limit": 480}`
   → 420	_ouid="${CC_PANE_ID:-${ITERM_SESSION_ID:-}}"; _ouid="${_ouid##*:}"
421	# KEEP THE RAW PANE KEY. The canonicalisation below deliberately rewrites $_ouid to the SESSION-keyed
422	# mailbox key — right for every mailbox read, wrong for the teardown marker, which is PANE-keyed (and
423	# sid-keyed) 
5. `Read: {"file_path": "/tmp/tokeff-gate/f2/tree/hooks/session-continue.sh", "offset": 899, "limit": 448}`
   → 899	# ── MECHANICAL 🔧 — loose ends must not need the model to REMEMBER (operator crux 2026-08-01) ─────
900	# THE DEFECT: this loop was armed by the model and only by the model. Measured over the live IDL —
901	# 393 `armed/cli-set` against 902 completion-assert Stop invocations — so on most closes 
6. `Bash: {"command": "sed -n 136,160p /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh; grep -n '^case\\|^  [a-z|*]*)' /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh | head", "description": "Check CLI dispatch section of the hook"}`
   → # ---- Agent CLI mode -------------------------------------------------------------
case "${1:-}" in
  set)
    f=$(sentinel_for "$PWD")
    printf '%s' "${2:-Continue the in-scope work.}" > "$f"
    rm -f "${f}.count" 2>/dev/null   # fresh chain → reset the loop counter (D-7 re-arm lever)
    # (b)
7. `Bash: {"command": "mkdir -p /tmp/tokeff-gate/f2/out/B01-r1 && cat > /tmp/tokeff-gate/f2/out/B01-r1/answer.md <<'EOF'\n# session-continue.sh: the conditions under which the Stop hook blocks a stop\n\nFile: `/tmp/tokeff-gate/f2/tree/hooks/session-continue.sh` (1346 lines).\n\nIn Stop mode the hook never blo`
   → ok
8. `StructuredOutput: {"answer_path": "/tmp/tokeff-gate/f2/out/B01-r1/answer.md", "headline": "session-continue.sh blocks a stop under 5 conditions, always by printing decision:block JSON and exiting 0: the agent-armed 🔧 continuation (emitted at 1336, or 1334 with mail; ends via kill phrase, `clear` or CLAUDE_CONTINUE_MA`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
