# Dossier 12

## Brief
```
In /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh, list every condition under which this Stop hook blocks a stop (emits a block decision or a blocking reason). For each give the line number, one sentence on the trigger, and the env var or kill switch that disables it, if any. numbers: {"conditions": <how many you listed>}.
```

## Returned headline
The Stop hook blocks under 5 conditions: an agent-set sentinel (line 1334/1336, capped by CLAUDE_CONTINUE_MAX), the mechanical arm for this session's uncommitted writes (same lines; off with CC_MECH_CONTINUE=0), the ship floor for the 📦 and 🚀 rungs (line 1199; off with CC_SHIP_FLOOR=0), and the wake floor (line 895; off with CC_WAKE_FLOOR=0). A kill-switch phrase in the last user message stops all of them.

## Returned numbers
`{"conditions": 5}`

## answer.md
# Blocking conditions in /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh (Stop-hook actuation mode)

Every block is a `{decision:"block",...}` JSON on stdout followed by exit 0. The only `exit 2` (line 116, and line 130 for set/clear/status) belongs to CLI modes, never to the no-arg Stop invocation. Messages that carry only `systemMessage` (lines 659, 699, 792, 842, 853, 1266) warn but do not block.

1. **Line 1334 / 1336 (reason text at 1304). Agent-armed continuation sentinel.** Blocks when a sentinel file exists for this config dir + cwd (written by `session-continue.sh set "<step>"`), the last user message has no kill phrase, the sentinel's session id matches, and `.count` is below the cap. Any pending inbox mail is added to the reason (1334 adds a systemMessage). Disabled by: the kill-switch phrase in the last genuine user message (`KILL_RE`, line 348; clears it at 1230); `session-continue.sh clear`; a session-id mismatch (1248); the cap `CLAUDE_CONTINUE_MAX` (default 8, line 1257; `=0` makes it allow every time). No on/off env var.

2. **Line 1334 / 1336, reached through `mechanical_arm` (1209 → arms sentinel at 1072). Mechanical 🔧 arm.** When no sentinel exists, the wrap-ledger rung is 🔧, and this session wrote uncommitted files (`session_dirty_mine` rc 0), the hook arms the sentinel itself and falls through into the same continuation block. Disabled by: `CC_MECH_CONTINUE=0` (941); the per-session budget `CC_MECH_MAX` (default 2, 1055/1064); the kill switch (952); Agent-Teams assignee (970–981) or a teardown marker (985). Setting `WRAP_LEDGER_BIN` or `SESSION_WRITES_LIB` to a missing path also turns it off.

3. **Line 1199 (reason 1187, emitted via 1210–1213). Ship floor, 📦 rung.** Blocks when there is no sentinel, the rung is 📦, and the committed-but-unlanded commits contain this session's own writes (`session_unlanded_mine`). It fires once per HEAD sha. Disabled by: `CC_SHIP_FLOOR=0` (1101); the budget `CC_SHIP_FLOOR_MAX` (default 2, 1164/1176); the kill switch (1103); assignee or teardown (1105–1112).

4. **Line 1199 (reason 1189). Ship floor, 🚀 rung.** Blocks when there is no sentinel, the rung is 🚀 (the work landed but is not live because the store is over its converge budget), and `session_writes_paths` shows this session wrote something. Same once-per-sha latch. Disabled by the same controls as #3: `CC_SHIP_FLOOR=0`, `CC_SHIP_FLOOR_MAX`, the kill switch, and assignee or teardown.

5. **Line 895 (emitted via 1215–1218). Wake floor.** Blocks when there is no sentinel, no floor above fired, and no inbox watcher is armed (`mailbox_wake_armed` false). It also needs one of these: this is the session's first idle, mail is pending, or dispatched custody is open (805). It tells the agent to arm `cc-await-ping`. Disabled by: `CC_WAKE_FLOOR=0` (604); the budget `CC_WAKE_FLOOR_MAX` (default 2, 838); the backoff `CC_WAKE_FLOOR_TTL_S` (default 600 s, 847); the kill switch (852). It also abstains for a headless session (`CC_PANE_ID` set with no `ITERM_SESSION_ID`, 656), a live /goal with mail pending (697), a team assignee or teardown marker (776–797; `CC_WAKE_FLOOR_TEARDOWN=0` removes this abstain), and a missing or invalid pane id (607).


## Tool calls (9) with the first 300 chars of each result
1. `Bash: {"command": "cat -n /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh; ls -la /tmp/tokeff-gate/f2/out/B01-r9/ 2>&1", "description": "Read the Stop hook and check output dir"}`
   → <persisted-output>
Output too large (103.4KB). Full output saved to: /Users/chrisren/.claude-quaternary/projects/-Users-chrisren-Development--worktrees-research-tokeff-offline-gate/6fdffc57-5e3c-41f3-b9bc-8100b70ac273/tool-results/bu6wo3vgh.txt

Preview (first 2KB):
     1	#!/usr/bin/env bash
     2
2. `Bash: {"command": "F=/tmp/tokeff-gate/f2/tree/hooks/session-continue.sh; wc -l $F; grep -n -E '\"decision\"|block|reason' $F | head -150; ls -la /tmp/tokeff-gate/f2/out/B01-r9/ 2>&1", "description": "Find block-decision lines in the hook"}`
   →     1346 /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh
9:# dumb actuator — it just blocks the stop and feeds the next step back, with a hard
32:#   (c) CAP RE-ARM — a fresh `set` resets `.count`; the block reason instructs re-`set` each 🔧 turn
36:# NOTE: deliberately NO `set -e` — a Stop hook t
3. `Bash: {"command": "F=/tmp/tokeff-gate/f2/tree/hooks/session-continue.sh; grep -n -E 'exit 2|CLAUDE_[A-Z_]*|SC_[A-Z_]*=|\\$\\{?[A-Z_]+_(OFF|DISABLE|MAX|TTL)' $F | head -120", "description": "Find exits and env vars"}`
   → 20:# Sentinel lives OUTSIDE any repo (per-account state dir: ${CLAUDE_CONFIG_DIR:-~/.claude}/state),
22:# including different accounts (each with its own CLAUDE_CONFIG_DIR) — don't collide.
46:# This is the hook that drives the loop: it emits {decision:"block"} up to CLAUDE_CONTINUE_MAX
84:SC_SID="?
4. `Read: {"file_path": "/tmp/tokeff-gate/f2/tree/hooks/session-continue.sh", "offset": 24, "limit": 110}`
   → 24	# HARDENING (a19 D-7/D-8, a17 S-12) beyond the base actuator:
25	#   (a) KILL-SWITCH — actuation reads the transcript's last genuine user message; an operator
26	#       "…and stop" / "no auto-continue" / "just do X" / explicit-pause phrase clears the sentinel
27	#       and allows the stop. Oper
5. `Read: {"file_path": "/tmp/tokeff-gate/f2/tree/hooks/session-continue.sh", "offset": 290, "limit": 140}`
   → 290	      '{cwd:$c,disarmed:($d==1)}' 2>/dev/null)"
291	    exit 0 ;;
292	  status)
293	    f=$(sentinel_for "$PWD")
294	    if [ -f "$f" ]; then
295	      # `unrecorded`, never `?` (W3i C3). `set` writes ${f}.sid only when the arming session HAS an
296	      # id, so the no-sid state is ORDINARY — 
6. `Read: {"file_path": "/tmp/tokeff-gate/f2/tree/hooks/session-continue.sh", "offset": 590, "limit": 320}`
   → 590	#   · only on the FIRST idle of this session, or when mail is actually pending
591	#   · at most CC_WAKE_FLOOR_MAX attempts per session, no sooner than CC_WAKE_FLOOR_TTL_S apart
592	#   · NEVER after an operator kill-switch phrase (kill_switch_active) — that stop was asked for
593	#   · budget e
7. `Read: {"file_path": "/tmp/tokeff-gate/f2/tree/hooks/session-continue.sh", "offset": 909, "limit": 438}`
   → 909	# WHY THIS IS NOT THE BANNED SCOPE-BLIND STOP HOOK (this file's own header, :3-8). That ban was
910	# written when nothing could tell in-scope dirt from anyone else's; scripts/wrap-ledger.sh now
911	# computes the rung from live facts, and lib/session-writes.sh attributes each dirty path to the

8. `Bash: {"command": "cat > /tmp/tokeff-gate/f2/out/B01-r9/answer.md <<'EOF'\n# Blocking conditions in /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh (Stop-hook actuation mode)\n\nEvery block is a `{decision:\"block\",...}` JSON on stdout followed by exit 0. The only `exit 2` (line 116, and line 130 for `
   → ok
9. `StructuredOutput: {"answer_path": "/tmp/tokeff-gate/f2/out/B01-r9/answer.md", "headline": "The Stop hook blocks under 5 conditions: an agent-set sentinel (line 1334/1336, capped by CLAUDE_CONTINUE_MAX), the mechanical arm for this session's uncommitted writes (same lines; off with CC_MECH_CONTINUE=0), the ship floor `
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
