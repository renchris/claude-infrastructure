# Dossier 2

## Brief
```
In /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh, list every condition under which this Stop hook blocks a stop (emits a block decision or a blocking reason). For each give the line number, one sentence on the trigger, and the env var or kill switch that disables it, if any. numbers: {"conditions": <how many you listed>}.
```

## Returned headline
session-continue.sh blocks a stop in 5 cases, all by printing decision:block and exiting 0: the ship floor on a 📦 rung (L1187/1199, off with CC_SHIP_FLOOR=0), the ship floor on a 🚀 rung (L1189/1199, same switch), the wake floor (L894-895, off with CC_WAKE_FLOOR=0), the mechanical 🔧 arm that ends in a continuation block (L1072-1080 then L1334/1336, off with CC_MECH_CONTINUE=0), and an armed sentinel continuation (L1334/1336), which has no env switch and is escaped only by `clear`, a kill phrase, or the CLAUDE_CONTINUE_MAX cap.

## Returned numbers
`{"conditions": 5}`

## answer.md
# Stop-block conditions in hooks/session-continue.sh

The hook always exits 0 in Stop mode. It blocks by printing `{decision:"block",reason:...}`. The `exit 2` at lines 116, 130 and 216 only runs in CLI modes (`--why`, `set|clear|status`), so it never blocks a stop.

1. **Ship floor, 📦 rung**: lines 1186-1187 and 1199, printed at 1212. No sentinel is armed, wrap-ledger reports 📦, and the committed-but-unlanded commits contain this session's own writes (`session_unlanded_mine`). It fires once per HEAD sha, up to `CC_SHIP_FLOOR_MAX` (default 2) times per session. Disabled by: `CC_SHIP_FLOOR=0`. It also stands down on an operator kill phrase (line 1103), a confirmed or undeterminable Agent-Teams assignee (1105-1110), or a fresh teardown marker (1112).

2. **Ship floor, 🚀 rung**: lines 1188-1189 and 1199, printed at 1212. No sentinel is armed, wrap-ledger reports 🚀 (landed but not live, because the converge budget has been breached), and `session_writes_paths` shows the session wrote something. Disabled by: the same switches as #1 (`CC_SHIP_FLOOR=0`, the `CC_SHIP_FLOOR_MAX` budget, a kill phrase, assignee or teardown).

3. **Wake floor**: lines 894-896, printed at 1217. No sentinel is armed, the pane has a mailbox identity, and no `cc-await-ping` watcher is armed. It fires only on the session's first idle, when mail is pending, or when open custody rows exist, and then only within `CC_WAKE_FLOOR_MAX` (default 2) attempts spaced at least `CC_WAKE_FLOOR_TTL_S` (default 600 s) apart. Disabled by: `CC_WAKE_FLOOR=0`. It also stands down on a kill phrase (852), a headless session (`CC_PANE_ID` set without `ITERM_SESSION_ID`, 656), a live /goal with pending mail (697), or an assignee or teardown marker (776-797). `CC_WAKE_FLOOR_TEARDOWN=0` turns that last abstain off, so it makes blocking more likely, not less.

4. **Mechanical 🔧 arm leading to a continuation block**: arms at lines 1072-1080; the block is emitted at 1334/1336. No sentinel is armed, wrap-ledger reports 🔧, and `session_dirty_mine` finds uncommitted files this session wrote. The hook then writes a sentinel itself and falls through to the armed-path block. The budget is `CC_MECH_MAX` (default 2) arms per session, and each arm can drive up to `CLAUDE_CONTINUE_MAX` continuations. Disabled by: `CC_MECH_CONTINUE=0`. It also stands down on a kill phrase (952), an assignee (970-983) or a teardown marker (985).

5. **Armed sentinel continuation ("Loose ends remain")**: lines 1303-1306, emitted at 1334 (with an inbox `systemMessage` when mail is folded in) or 1336. A sentinel set via `session-continue.sh set` exists for this cwd, and three checks pass: no kill phrase (1230), the sentinel's sid matches the current session (1248), and the continuation count is below `CLAUDE_CONTINUE_MAX` (default 8, line 1260). Disabled by: no dedicated env var. The ways out are `session-continue.sh clear`, a kill-switch phrase in the last user message, and the `CLAUDE_CONTINUE_MAX` cap. Setting `CLAUDE_CONTINUE_MAX=0` makes every stop allowed.


## Tool calls (6) with the first 300 chars of each result
1. `Bash: {"command": "wc -l /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh; ls -la /tmp/tokeff-gate/f2/out/B01-r10/ 2>&1", "description": "Check hook file size and output dir"}`
   →     1346 /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh
total 0
drwxr-xr-x@   2 chrisren  wheel    64 Sep 24 11:31 .
drwxr-xr-x@ 102 chrisren  wheel  3264 Sep 24 11:31 ..
2. `Bash: {"command": "grep -n -E 'block|decision|reason|exit 2|_KILL|DISABLE|SKIP|^[a-z_]+\\(\\)|:-' /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh | head -300", "description": "Grep block-related lines in hook"}`
   → 9:# dumb actuator — it just blocks the stop and feeds the next step back, with a hard
20:# Sentinel lives OUTSIDE any repo (per-account state dir: ${CLAUDE_CONFIG_DIR:-~/.claude}/state),
32:#   (c) CAP RE-ARM — a fresh `set` resets `.count`; the block reason instructs re-`set` each 🔧 turn
36:# NOTE:
3. `Read: {"file_path": "/tmp/tokeff-gate/f2/tree/hooks/session-continue.sh", "offset": 300, "limit": 330}`
   → 300	      # different words even though they earn the same refusal.
301	      echo "ARMED ($(cat "${f}.count" 2>/dev/null || echo 0) continuations, sid=$(cat "${f}.sid" 2>/dev/null || echo 'unrecorded')): $(cat "$f")"
302	    else echo "inactive"; fi
303	    exit 0 ;;
304	esac
305	
306	# ---- Stop-h
4. `Read: {"file_path": "/tmp/tokeff-gate/f2/tree/hooks/session-continue.sh", "offset": 630, "limit": 720}`
   → 630	  case "$pend" in ''|*[!0-9]*) pend=0 ;; esac
631	
632	  # ── HEADLESS: this session has no terminal, so a WATCHER is not its wake path (F6 of
633	  #    docs/research/scaling-bottlenecks-2026-08-09/03-headless-substrate.md, test T16) ────────────
634	  # A pane session is woken by an armed cc-a
5. `Bash: {"command": "cat > /tmp/tokeff-gate/f2/out/B01-r10/answer.md <<'EOF'\n# Stop-block conditions in hooks/session-continue.sh\n\nThe hook always exits 0 in Stop mode. It blocks by printing `{decision:\"block\",reason:...}`. The `exit 2` at lines 116, 130 and 216 only runs in CLI modes (`--why`, `set|cl`
   → (Bash completed with no output)
6. `StructuredOutput: {"answer_path": "/tmp/tokeff-gate/f2/out/B01-r10/answer.md", "headline": "session-continue.sh blocks a stop in 5 cases, all by printing decision:block and exiting 0: the ship floor on a 📦 rung (L1187/1199, off with CC_SHIP_FLOOR=0), the ship floor on a 🚀 rung (L1189/1199, same switch), the wake floo`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
