# Dossier 4

## Brief

Read-only. In /Users/chrisren/Development/claude-infrastructure/hooks/session-continue.sh, list every condition under which the Stop hook blocks a stop (emits a block decision or a blocking reason). For each give the line number, one sentence on the trigger, and the env var or kill switch that disables it, if any. Write the list to /tmp/tokeff-eval/lean/L1-stop-conditions/out-4/answer.md and reply with that path.

## Answer file contents (verbatim)

````markdown
# Stop-blocking conditions in `hooks/session-continue.sh`

File: `/Users/chrisren/Development/claude-infrastructure/hooks/session-continue.sh` (1344 lines).
Every block is emitted as `{decision:"block", reason:...}` JSON on stdout with exit 0. The hook never blocks through exit 2 in Stop mode. Its `exit 2` paths (lines 116, 130, 216) belong only to CLI modes (`--why`, `set|clear|status`, bad `clear` flag).

Dispatch order at Stop (line 1205). If no sentinel exists, the hook runs the mechanical arm, then the ship floor, then the wake floor. The first one that fires decides the outcome.

The kill switch, `kill_switch_active` (line 391), applies to all four arms. It fires when the last genuine user message, meaning a non-`isMeta` transcript record, matches `KILL_RE` at line 348: "and stop", "no auto-continue", "just do X", "stop here", "come back to this", or a bare "stop"/"halt". It is a transcript phrase, not an env var.

## 1. Armed-sentinel continuation (🔧 loop), line 1332 (1334 when no mail is folded in)
- **Trigger:** a continuation sentinel exists for this cwd, created by `session-continue.sh set "<step>"` or by arm 2 below. Its stored sid must match this session, and `.count` must be below the cap. The hook then blocks with "🔧 Loose ends remain — Next: <step>". Any pending inbox mail is folded into that same reason (lines 1272-1316), so mail is not a separate block.
- **Disabled by:**
  - `session-continue.sh clear`, which removes the sentinel.
  - The kill-switch phrase (line 1239), which clears the sentinel and allows the stop.
  - A sid mismatch (line 1246), where the sentinel was inherited across a succession, which clears it.
  - The cap `CLAUDE_CONTINUE_MAX` (line 1255, default 8). Reaching it clears the sentinel and allows the stop, but any fresh `set` resets the count to zero.

## 2. Mechanical 🔧 arm, line 1070 (arms the sentinel), block emitted through arm 1 at line 1332
- **Trigger:** no sentinel exists, `wrap-ledger.sh --machine` reports `RUNG=🔧` (line 1017), and `session_dirty_mine` finds files this session wrote that are still uncommitted (lines 1022-1028). The hook then writes a "Commit the N file(s)…" step into the sentinel and falls through to the armed-path block.
- **Disabled by:**
  - `CC_MECH_CONTINUE=0` (line 939).
  - The per-session budget `CC_MECH_MAX` (default 2, line 1053; spent at 1062). `session-continue.sh clear` also spends this budget outright (line 261).
  - The kill switch (line 941).
  - Being a confirmed or argv-evidenced team assignee, or a fresh teardown marker (`CC_TEARDOWN_DIR`).
  - A missing `jq`, session-writes lib (`SESSION_WRITES_LIB` seam) or wrap-ledger (`WRAP_LEDGER_BIN` seam).
  - After it arms, every arm-1 limit also applies, including `CLAUDE_CONTINUE_MAX`.

## 3. Ship floor, line 1197 (`ship_floor`, line 1098; emitted at 1209-1211)
- **Trigger:** no sentinel exists, the mechanical arm did not arm, and the ledger rung is 📦 (committed but not landed) or 🚀 (landed but not live, line 1128). The work must also belong to this session: `session_unlanded_mine` for 📦, `session_writes_paths` for 🚀. The block tells the session to `/ship` it, or to run `deploy-live.sh` for 🚀. It fires once per HEAD sha per session.
- **Disabled by:**
  - `CC_SHIP_FLOOR=0` (line 1099).
  - The per-session budget `CC_SHIP_FLOOR_MAX` (default 2, line 1162).
  - The latch: the floor does not re-fire on the same HEAD sha.
  - The kill switch (line 1101).
  - Being a team assignee, or a teardown marker.
  - A missing `jq`, wrap-ledger or session-writes lib.

## 4. Wake floor, line 893 (`wake_floor`, line 603; emitted at 1214-1216)
- **Trigger:** no sentinel exists, neither arm 2 nor arm 3 fired, and this pane has no inbox watcher armed (`mailbox_wake_armed` is false). On top of that, at least one of these must hold (line 805):
  - this is the session's first unarmed idle;
  - mail is pending;
  - there is open `cc-custody` work this pane owns.

  The block tells the session to arm `cc-await-ping` in the background. Under a live `/goal` it asks for the `--idle-scoped --sid` form instead.
- **Disabled by:**
  - `CC_WAKE_FLOOR=0` (line 604).
  - The budget `CC_WAKE_FLOOR_MAX` (default 2, line 807).
  - The re-fire interval `CC_WAKE_FLOOR_TTL_S` (default 600 s, line 808).
  - The kill switch (line 850), which leaves only a `systemMessage`.
  - `CC_WAKE_FLOOR_TEARDOWN` (default 1, line 776). While it is on, the floor stands down for team assignees and teardown-marked sessions. Setting it to 0 turns that stand-down off, not the floor itself.
  - It also stands down in these cases:
    - a pane-less or headless session (`CC_PANE_ID` set without `ITERM_SESSION_ID`, line 656);
    - a live `/goal` with mail already pending (line 697);
    - no valid pane id, no `jq`, or the mailbox lib not loaded.

## Not blocks (allow the stop, sometimes with only a `systemMessage`)
- Reaching the continuation cap (line 1267).
- The wake-floor stand-downs: budget exhausted, headless, goal live, teardown.
- Failure to source the sentinel lib (line 130). The hook exits 0 in Stop mode.
````

## Tool calls

1. **Bash** — `{"command": "F=/Users/chrisren/Development/claude-infrastructure/hooks/session-continue.sh; wc -l $F; grep -n -E 'block|decision|exit 2|reason|_off|KILL|CC_[A-Z_]+|CLAUDE_[A-Z_]+' $F | head -300", "de`
2. **Bash** — `{"command": "F=/Users/chrisren/Development/claude-infrastructure/hooks/session-continue.sh; sed -n 100,135p $F; echo ----; sed -n 600,660p $F; echo ----; sed -n 690,730p $F; sed -n 760,860p $F", "desc`
3. **Bash** — `{"command": "F=/Users/chrisren/Development/claude-infrastructure/hooks/session-continue.sh; sed -n 935,1080p $F | grep -v '^ *#'; echo ----; sed -n 1097,1344p $F | grep -v '^ *#'", "description": "Rea`
4. **Bash** — `{"command": "F=/Users/chrisren/Development/claude-infrastructure/hooks/session-continue.sh; sed -n 270,345p $F | grep -v '^ *#'; echo ---; sed -n 886,900p $F; grep -n 'stop_hook_active\\|^if \\[ ! -f `
5. **Bash** — `{"command": "F=/Users/chrisren/Development/claude-infrastructure/hooks/session-continue.sh; sed -n 346,400p $F | grep -v '^ *#'; sed -n 403,420p $F | grep -v '^ *#'", "description": "Read kill switch `
6. **Bash** — `{"command": "F=/Users/chrisren/Development/claude-infrastructure/hooks/session-continue.sh; grep -n 'mechanical_arm() {\\|ship_floor() {\\|wake_floor() {\\|Commit the \\${n_files}\\|return 1$\\|mcnt\"`
7. **Bash** — `{"command": "mkdir -p /tmp/tokeff-eval/lean/L1-stop-conditions/out-4 && cat > /tmp/tokeff-eval/lean/L1-stop-conditions/out-4/answer.md <<'EOF'\n# Stop-blocking conditions in `hooks/session-continue.sh`
8. **SubagentHandback** — `{"message": "I wrote the list to /tmp/tokeff-eval/lean/L1-stop-conditions/out-4/answer.md. The hook blocks a stop in four situations. It always blocks by printing `{decision:\"block\"}` and exiting 0;`
