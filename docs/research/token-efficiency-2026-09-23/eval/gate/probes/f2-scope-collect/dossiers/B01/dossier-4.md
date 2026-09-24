# Dossier 4

## Brief
```
In /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh, list every condition under which this Stop hook blocks a stop (emits a block decision or a blocking reason). For each give the line number, one sentence on the trigger, and the env var or kill switch that disables it, if any. numbers: {"conditions": <how many you listed>}.
```

## Returned headline
The session-continue.sh Stop hook blocks a stop under 4 conditions, each by emitting decision:block JSON with exit 0: the armed-sentinel continuation (lines 1334/1336; operator kill phrase, clear or the CLAUDE_CONTINUE_MAX cap), the mechanical 🔧 arm for this session's uncommitted files (armed at 1072, same emit; CC_MECH_CONTINUE=0), the ship floor (1199; CC_SHIP_FLOOR=0) and the wake floor (894-895; CC_WAKE_FLOOR=0).

## Returned numbers
`{"conditions": 4}`

## answer.md
# session-continue.sh: conditions under which the Stop hook blocks a stop

Every block is `{decision:"block"}` JSON on stdout with exit 0. The hook never blocks by exiting 2 in Stop mode: the `exit 2` at lines 116 and 130 fire only for the `--why` and `set|clear|status` CLI arguments.

1. **Armed-sentinel continuation. Lines 1334/1336 (the `jq` emit; 1334 is the variant with inbox mail folded in).** It fires when a continuation sentinel for this cwd exists (armed by `session-continue.sh set`), the last user message has no kill phrase, the stored arming sid matches or is unknown, and `.count` is below the cap. It then feeds back "🔧 Loose ends remain" with the next step. **How to disable it:** there is no on/off env var. The ways out are an operator kill-switch phrase in the last user message (`KILL_RE`, line 348; checked at 1230), `session-continue.sh clear`, a sid mismatch (1248), and the `CLAUDE_CONTINUE_MAX` cap (default 8; line 1257), which allows the stop once it is reached.

2. **Mechanical 🔧 arm. The arm is at line 1072, and it blocks through the same emit at 1334/1336.** It fires when no sentinel exists (1207) and wrap-ledger reports rung 🔧 with at least 1 uncommitted dirty file attributed to this session by `session_dirty_mine`. The hook writes a "Commit the N file(s)…" sentinel and falls through to the armed path. **How to disable it:** `CC_MECH_CONTINUE=0` (line 941). It also stands down on the per-session budget `CC_MECH_MAX` (default 2; line 1055), on a kill-switch phrase (952), for a confirmed or undeterminable Agent-Teams assignee (970-982), and when a fresh teardown marker exists (985).

3. **Ship floor. The block is emitted at line 1199 and printed at 1212.** It fires when no sentinel is armed and the mechanical arm did not arm. The rung must be 📦 with unlanded commits containing this session's own writes, or 🚀 with write evidence from this session. It fires at most once per HEAD sha (1174), and the block tells the model to /ship or converge. **How to disable it:** `CC_SHIP_FLOOR=0` (line 1101). It also stands down on the per-session cap `CC_SHIP_FLOOR_MAX` (default 2; line 1164), on a kill-switch phrase (1103), for an assignee (1105-1111), and when a teardown marker exists (1112).

4. **Wake floor. The block is emitted at lines 894-895 and printed at 1217.** It fires when the session is going idle with no sentinel and no other floor fired, and the pane has a valid inbox id but no armed `cc-await-ping` watcher. It fires only on the session's first idle, or when mail is pending or open custody rows exist (805). The block tells the model to arm the watcher. **How to disable it:** `CC_WAKE_FLOOR=0` (line 604). It also stands down on the attempt cap `CC_WAKE_FLOOR_MAX` (default 2; 838), inside the re-fire interval `CC_WAKE_FLOOR_TTL_S` (default 600 s; 847), and on a kill-switch phrase (852). It abstains for a headless session (`CC_PANE_ID` set with no `ITERM_SESSION_ID`; 656), and when a /goal is live and mail is pending (697). With `CC_WAKE_FLOOR_TEARDOWN=1` (the default; 776) it also abstains for an assignee or when a teardown marker exists.


## Tool calls (8) with the first 300 chars of each result
1. `Bash: {"command": "wc -l /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh; ls -la /tmp/tokeff-gate/f2/out/B01-r12/ 2>&1", "description": "Check file size and output dir"}`
   →     1346 /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh
total 0
drwxr-xr-x@   2 chrisren  wheel    64 Sep 24 11:31 .
drwxr-xr-x@ 102 chrisren  wheel  3264 Sep 24 11:31 ..
2. `Bash: {"command": "grep -n -E 'block|decision|reason|exit 2|_emit|emit_' /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh | head -200", "description": "Find block-related lines in hook"}`
   → 9:# dumb actuator — it just blocks the stop and feeds the next step back, with a hard
32:#   (c) CAP RE-ARM — a fresh `set` resets `.count`; the block reason instructs re-`set` each 🔧 turn
36:# NOTE: deliberately NO `set -e` — a Stop hook that exits 2 *blocks the stop*, so an
46:# This is the hook t
3. `Read: {"file_path": "/tmp/tokeff-gate/f2/tree/hooks/session-continue.sh", "offset": 95, "limit": 60}`
   → 95	}
96	
97	# ── `--why <topic>` REFERENCE TIER (backlog 1031594b6327; docs/plans/STOPHOOK_MESSAGE_TIERING.md §3) ──
98	# Dispatched HERE — before stdin is read and before any IDL/latch/state write — because this arm is run
99	# from a TERMINAL by a reader holding one of this hook's messages. A `cat
4. `Read: {"file_path": "/tmp/tokeff-gate/f2/tree/hooks/session-continue.sh", "offset": 300, "limit": 120}`
   → 300	      # different words even though they earn the same refusal.
301	      echo "ARMED ($(cat "${f}.count" 2>/dev/null || echo 0) continuations, sid=$(cat "${f}.sid" 2>/dev/null || echo 'unrecorded')): $(cat "$f")"
302	    else echo "inactive"; fi
303	    exit 0 ;;
304	esac
305	
306	# ---- Stop-h
5. `Read: {"file_path": "/tmp/tokeff-gate/f2/tree/hooks/session-continue.sh", "offset": 420, "limit": 480}`
   → 420	_ouid="${CC_PANE_ID:-${ITERM_SESSION_ID:-}}"; _ouid="${_ouid##*:}"
421	# KEEP THE RAW PANE KEY. The canonicalisation below deliberately rewrites $_ouid to the SESSION-keyed
422	# mailbox key — right for every mailbox read, wrong for the teardown marker, which is PANE-keyed (and
423	# sid-keyed) 
6. `Read: {"file_path": "/tmp/tokeff-gate/f2/tree/hooks/session-continue.sh", "offset": 899, "limit": 448}`
   → 899	# ── MECHANICAL 🔧 — loose ends must not need the model to REMEMBER (operator crux 2026-08-01) ─────
900	# THE DEFECT: this loop was armed by the model and only by the model. Measured over the live IDL —
901	# 393 `armed/cli-set` against 902 completion-assert Stop invocations — so on most closes 
7. `Bash: {"command": "cat > /tmp/tokeff-gate/f2/out/B01-r12/answer.md <<'EOF'\n# session-continue.sh: conditions under which the Stop hook blocks a stop\n\nEvery block is `{decision:\"block\"}` JSON on stdout with exit 0. The hook never blocks by exiting 2 in Stop mode: the `exit 2` at lines 116 and 130 fire`
   → (Bash completed with no output)
8. `StructuredOutput: {"answer_path": "/tmp/tokeff-gate/f2/out/B01-r12/answer.md", "headline": "The session-continue.sh Stop hook blocks a stop under 4 conditions, each by emitting decision:block JSON with exit 0: the armed-sentinel continuation (lines 1334/1336; operator kill phrase, clear or the CLAUDE_CONTINUE_MAX cap`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
