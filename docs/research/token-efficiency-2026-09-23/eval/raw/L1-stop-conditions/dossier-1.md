# Dossier 1

## Brief

Read-only. In /Users/chrisren/Development/claude-infrastructure/hooks/session-continue.sh, list every condition under which the Stop hook blocks a stop (emits a block decision or a blocking reason). For each give the line number, one sentence on the trigger, and the env var or kill switch that disables it, if any. Write the list to /tmp/tokeff-eval/lean/L1-stop-conditions/out-1/answer.md and reply with that path.

## Answer file contents (verbatim)

````markdown
# session-continue.sh: when the Stop hook blocks a stop

File: /Users/chrisren/Development/claude-infrastructure/hooks/session-continue.sh (1344 lines, read 2026-09-23).

Every block is a `{decision:"block",reason:...}` JSON object on stdout, and the hook exits 0 each time. No Stop-mode path blocks by exiting 2. At most one block is printed per Stop. When no sentinel exists (the session is going idle), the floors are tried in this order: mechanical arm, then ship floor, then wake floor (lines 1201-1223).

| # | Block emitted at | Trigger (one sentence) | Disable / kill switch |
|---|---|---|---|
| 1 | **1332 / 1334** (armed-sentinel "continue" block; `mark_blocked continue` at 1329) | A continuation sentinel exists for this cwd (armed by the agent via `session-continue.sh set "<step>"`, or mechanically, see #2), the last user message has no kill phrase, the stored sid matches, and `.count` is under the cap, so the hook blocks with "🔧 Loose ends remain" and folds in any pending inbox mail. | Kill phrase in the last genuine user message (`KILL_RE`, line 348: "and stop", "no auto-continue", "just do X", "stop here", "come back to this", a bare "stop"/"halt"), which clears the sentinel (1228-1233). A sid mismatch clears it (1245-1252). `CLAUDE_CONTINUE_MAX` (default 8) is the cap; at the cap the hook clears and allows the stop (1255-1268). `session-continue.sh clear` removes the sentinel. |
| 2 | Armed at **938-1073** (`mechanical_arm` writes the sentinel at 1065); the block itself goes out through #1 at 1332/1334 | No sentinel, the wrap-ledger rung is 🔧, and `session_dirty_mine` attributes uncommitted files to this session's own writes, so the hook arms a "commit the N file(s) you edited" sentinel and falls through to the continue block. | `CC_MECH_CONTINUE=0` (line 939). A kill phrase (949). Budget `CC_MECH_MAX` (default 2 per session, `${f}.mech`, 1053-1062), and `clear` spends that budget outright (line 261). Also stands down for a confirmed team assignee (rc 0/2, 966-980), a teardown marker (982), a missing jq, session-writes lib or wrap-ledger, or attribution rc≠0. The `CLAUDE_CONTINUE_MAX` cap from #1 then applies, so the worst case is CC_MECH_MAX × CLAUDE_CONTINUE_MAX. |
| 3 | **1197** (`ship_floor`; printed by the main flow at 1208-1211, `mark_blocked ship-floor`) | No sentinel and the mechanical arm did not arm, the ledger rung is 📦 (committed but not landed, and `session_unlanded_mine` says the commits are this session's) or 🚀 (landed but not live, with write evidence from this session), and HEAD has not already been nudged, so the hook blocks with a "SHIP FLOOR" demand to `/ship` or run `deploy-live.sh`. | `CC_SHIP_FLOOR=0` (1099). A kill phrase (1101). Budget `CC_SHIP_FLOOR_MAX` (default 2 per session) plus a latch of once per HEAD sha (`${f}.ship`, 1162-1177). Abstains for an assignee (rc 0/2), a teardown marker, missing jq, ledger or lib, or when attribution refuses. |
| 4 | **893** (`wake_floor`; printed by the main flow at 1213-1216, `mark_blocked wake-floor`) | No sentinel, neither earlier floor fired, and no inbox wake path is armed (`mailbox_wake_armed` is false), on the first idle of the session, or while mail is pending, or while open custody rows (dispatched sessions) are attributed to this pane, so the hook blocks demanding a `cc-await-ping` watcher (the `--idle-scoped` form when a /goal is live). | `CC_WAKE_FLOOR=0` (604). A kill phrase (849-853). Budget `CC_WAKE_FLOOR_MAX` (default 2) and re-fire spacing `CC_WAKE_FLOOR_TTL_S` (default 600 s) (807-847). Abstains on a headless/pane-less session (`CC_PANE_ID` set with no `ITERM_SESSION_ID`, 649), on a live /goal with mail already pending (694), or on an assignee or teardown marker; `CC_WAKE_FLOOR_TEARDOWN=0` turns off both of those last abstains (776). Also skips when jq or the mailbox lib is missing, or the pane id is invalid. |

## Not blocks (for completeness)
- Line 116 (`--why` reference tier missing) and line 130 (`set|clear|status` when the sentinel lib fails to source) exit 2 only in CLI modes. In Stop mode the lib failure exits 0 and allows the stop.
- The cap (1267), kill switch (1233), sid mismatch (1252) and floor-budget exhaustion paths all allow the stop. Some of them print a `systemMessage` warning but never a block decision.
````

## Tool calls

1. **Bash** — `{"command": "F=/Users/chrisren/Development/claude-infrastructure/hooks/session-continue.sh; wc -l $F; grep -n -E 'decision|block|\"reason\"|exit 2|emit_|_block\\b|^[a-z_]+\\(\\)|KILL|_MAX|=off|disable`
2. **Bash** — `{"command": "F=/Users/chrisren/Development/claude-infrastructure/hooks/session-continue.sh; sed -n 100,132p $F; echo ----; sed -n 600,900p $F", "description": "Read early exit paths and wake floor"}`
3. **Bash** — `{"command": "F=/Users/chrisren/Development/claude-infrastructure/hooks/session-continue.sh; sed -n 936,1344p $F", "description": "Read mechanical arm, ship floor, main flow"}`
4. **Bash** — `{"command": "F=/Users/chrisren/Development/claude-infrastructure/hooks/session-continue.sh; sed -n 133,200p $F | grep -nE 'exit|case' ; echo ---; sed -n 296,345p $F; sed -n 391,470p $F | grep -nE 'exi`
5. **Bash** — `{"command": "mkdir -p /tmp/tokeff-eval/lean/L1-stop-conditions/out-1 && cat > /tmp/tokeff-eval/lean/L1-stop-conditions/out-1/answer.md <<'EOF'\n# session-continue.sh: when the Stop hook blocks a stop\`
6. **SubagentHandback** — `{"message": "The list is written to /tmp/tokeff-eval/lean/L1-stop-conditions/out-1/answer.md.\n\nThe Stop hook in /Users/chrisren/Development/claude-infrastructure/hooks/session-continue.sh blocks a s`
