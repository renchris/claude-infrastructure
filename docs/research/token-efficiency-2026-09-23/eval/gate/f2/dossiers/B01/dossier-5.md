# Dossier 5

## Brief
```
In /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh, list every condition under which this Stop hook blocks a stop (emits a block decision or a blocking reason). For each give the line number, one sentence on the trigger, and the env var or kill switch that disables it, if any. numbers: {"conditions": <how many you listed>}.
```

## Returned headline
session-continue.sh blocks a stop under 5 conditions, all by printing {decision:"block"} (it never blocks through its exit code): (1) a sentinel the agent set with `set` exists (L1334/1336), (2) the mechanical arm arms on this session's uncommitted writes and falls through to that same block, (3) the 📦 ship floor for this session's committed-but-unlanded commits (L1187/1199), (4) the 🚀 ship floor for work that landed but is not live (L1189/1199), and (5) the wake floor when no inbox watcher is armed (L895). The off switches are CC_MECH_CONTINUE=0, CC_SHIP_FLOOR=0 and CC_WAKE_FLOOR=0; the sentinel path has none, but a kill phrase or CLAUDE_CONTINUE_MAX=0 lets its stops through.

## Returned numbers
`{"conditions": 5}`

## answer.md
# session-continue.sh: every condition under which the Stop hook blocks a stop

File: `/tmp/tokeff-gate/f2/tree/hooks/session-continue.sh` (1346 lines; `wc -l`)

## How it blocks

When Claude Code runs the hook as a Stop hook (no args, Stop JSON on stdin), the only way it blocks is by printing `{decision:"block", reason:...}` to stdout. There are three places that print it:

- **L895**: `wake_floor()`, with `systemMessage`
- **L1199**: `ship_floor()`, with one of two reason texts (L1187 for 📦, L1189 for 🚀)
- **L1334 / L1336**: the armed continuation path (L1334 is the variant that also carries inbox mail and a `systemMessage`; L1336 is the plain one)

The hook never blocks through its exit code. Every actuation path ends in `exit 0` (header L37-38; L1213, L1269, L1346). The two `exit 2` lines (L116 for `--why`, L130 for the `set|clear|status` CLI) cannot be reached when the hook runs as a Stop hook. The cap message (L1266) and the wake-floor "stood down / exhausted" messages (L660, L699, L792, L842, L853) print only `{systemMessage}`, so they do not block.

## The order of checks on each Stop

- **Sentinel present** (the agent ran `set`, or the mechanical arm armed one): the hook goes to the armed path. That path checks the kill switch (L1230), then SID-BIND (L1248), then the cap (L1260). If none of them lets the stop through, it blocks at L1334/1336.
- **Sentinel absent** (L1207): the hook runs `mechanical_arm` (L1209). If that arms, control falls through to the armed path above. Otherwise it runs `ship_floor` (L1210) and then `wake_floor` (L1215). At most one of these blocks on any Stop.

## Conditions (5)

| # | Emit line | Trigger (one sentence) | What disables it |
|---|---|---|---|
| 1 | L1334 / L1336 (reason L1304; L1313 adds the inbox fold) | A sentinel set by the agent with `session-continue.sh set "<step>"` exists for this cwd. The last real user message has no kill phrase, the stored arming sid is not a different known sid, and `.count` is below the cap, so the hook blocks with "🔧 Loose ends remain — Next: <step>". Any pending peer mail is added to the reason and to a `systemMessage`. | No env var turns this path off. The levers are: `session-continue.sh clear`; a kill phrase in the last user message (`KILL_RE` L348: "…and stop", "no auto-continue", "just do X", "stop here", "come back to this", a bare "stop"/"halt"), checked at L1230; a sid mismatch (L1248); and the cap `CLAUDE_CONTINUE_MAX` (default 8, L1257). The cap check `n -ge MAX` (L1260) means `CLAUDE_CONTINUE_MAX=0` allows every stop, so in practice it works as an off switch. |
| 2 | L1336 via the armed path (arms at L1072-1078; falls through from L1209) | No sentinel exists, `wrap-ledger.sh --machine` reports `RUNG=🔧` (L1019), and `session_dirty_mine` finds uncommitted files that this session wrote (L1024). The mechanical arm then writes a "Commit the N file(s) you edited…" sentinel, and condition 1's block fires on this same Stop. | `CC_MECH_CONTINUE=0` (L941). The per-session budget `CC_MECH_MAX` (default 2, L1055/L1064), stored in `${f}.mech`. `clear` marks that budget as spent (L261). A kill phrase (L952). Abstains for a confirmed team assignee (L970) and when a fresh teardown marker exists (L985). The armed-path cap, sid-bind and kill-switch checks from condition 1 still apply. |
| 3 | L1199 (reason L1187, 📦) | No sentinel, the ledger rung is 📦, `TRUNK` is known, and `session_unlanded_mine` shows that the commits not yet landed include this session's own writes (L1152). The hook blocks with "📦 SHIP FLOOR … /ship it". | `CC_SHIP_FLOOR=0` (L1101, which also covers condition 4). The budget `CC_SHIP_FLOOR_MAX` (default 2, L1164/L1176). A once-per-HEAD-sha latch (L1174). A kill phrase (L1103). Abstains for an assignee (L1105) or a teardown (L1112). Does nothing if jq, the ledger or the session-writes lib is missing. |
| 4 | L1199 (reason L1189, 🚀) | No sentinel, the ledger rung is 🚀 (the work has landed but is not live because the enforcing store is past its converge budget), and `session_writes_paths` shows this session wrote something (L1156). The hook blocks with "🚀 SHIP FLOOR … run deploy-live.sh". | The same levers as condition 3: `CC_SHIP_FLOOR=0`, `CC_SHIP_FLOOR_MAX`, the HEAD-sha latch, a kill phrase, and the assignee/teardown abstain. |
| 5 | L895 | No sentinel, and neither ship floor blocked. The session has an inbox identity (`CC_PANE_ID`/`ITERM_SESSION_ID`, L607) and no inbox watcher is armed (L614). It is also either the session's first idle, or mail is pending, or open `cc-custody` rows exist for this cwd (L805). The hook blocks with "🔔 WAKE FLOOR — arm cc-await-ping". | `CC_WAKE_FLOOR=0` (L604). The budget `CC_WAKE_FLOOR_MAX` (default 2, L838). The spacing `CC_WAKE_FLOOR_TTL_S` (default 600 s, L847). A kill phrase (L852). It stands down in these cases: a pane-less session (`CC_PANE_ID` set without `ITERM_SESSION_ID`, L656); a live `/goal` with mail pending (L697); a team assignee or a teardown marker (L776-795, only while `CC_WAKE_FLOOR_TEARDOWN=1`; setting that var to 0 removes the stand-down, it does not turn the floor off); a watcher already armed; jq or the mailbox lib missing. |

## Notes

- Conditions 2-5 run only when no sentinel file exists (L1207). The floors never stack on top of an armed continuation, and at most one JSON object is printed per Stop.
- The kill switch reads only the last user record in the transcript that is not `isMeta` (L380). Command and skill bodies injected into the transcript do not trigger it.
- Minor inconsistency found. `clear` marks the mech budget spent with `${CC_MECH_MAX:-3}` (L261), but `mechanical_arm` defaults to `${CC_MECH_MAX:-2}` (L1055). Since 3 ≥ 2 it is still treated as spent, so nothing breaks, but the two defaults disagree.


## Tool calls (11) with the first 300 chars of each result
1. `Bash: {"command": "cat -n /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh; ls -la /tmp/tokeff-gate/f2/out/B01-r2/ 2>&1", "description": "Read the Stop hook and check output dir"}`
   → <persisted-output>
Output too large (103.4KB). Full output saved to: /Users/chrisren/.claude-quaternary/projects/-Users-chrisren-Development--worktrees-research-tokeff-offline-gate/6fdffc57-5e3c-41f3-b9bc-8100b70ac273/tool-results/bnjtar43s.txt

Preview (first 2KB):
     1	#!/usr/bin/env bash
     2
2. `Bash: {"command": "F=/tmp/tokeff-gate/f2/tree/hooks/session-continue.sh; wc -l $F; ls -la /tmp/tokeff-gate/f2/out/B01-r2/ 2>&1; grep -n -E '\"decision\"|decision|block|reason' $F | grep -v '^\\s*[0-9]*:\\s*#' | head -100", "description": "Find block emissions in the hook"}`
   →     1346 /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh
total 0
drwxr-xr-x@  2 chrisren  wheel    64 Sep 24 10:27 .
drwxr-xr-x@ 82 chrisren  wheel  2624 Sep 24 10:27 ..
85:log_idl() { # $1=disposition $2=reason $3=extra JSON OBJECT (optional, jq-built {…}; default {})
90:  printf '[%s] %s sid=%s
3. `Bash: {"command": "F=/tmp/tokeff-gate/f2/tree/hooks/session-continue.sh; grep -n -E 'exit 2|>&2|SC_[A-Z_]*=|\\$\\{SC_|\\$SC_[A-Z_]+|_DISABLE|KILL|NO_' $F | head -80; sed -n 24,84p $F", "description": "Find exit codes and env vars, read header"}`
   → 25:#   (a) KILL-SWITCH — actuation reads the transcript's last genuine user message; an operator
84:SC_SID="?"
90:  printf '[%s] %s sid=%s reason=%s\n' "$ts" "$1" "$SC_SID" "$2" >> "$CLOG" 2>/dev/null || true
92:  jq -cn --arg ts "$ts" --arg sid "$SC_SID" --arg disp "$1" --arg reason "$2" --argjson 
4. `Bash: {"command": "F=/tmp/tokeff-gate/f2/tree/hooks/session-continue.sh; sed -n 96,140p $F; echo ----; sed -n 296,346p $F; echo ----; sed -n 1195,1346p $F", "description": "Read startup, dispatch and actuation tail"}`
   → # ── `--why <topic>` REFERENCE TIER (backlog 1031594b6327; docs/plans/STOPHOOK_MESSAGE_TIERING.md §3) ──
# Dispatched HERE — before stdin is read and before any IDL/latch/state write — because this arm is run
# from a TERMINAL by a reader holding one of this hook's messages. A `cat` above it blocks 
5. `Bash: {"command": "F=/tmp/tokeff-gate/f2/tree/hooks/session-continue.sh; sed -n 346,420p $F; echo -----; sed -n 600,900p $F | grep -v '^\\s*#'", "description": "Read kill-switch and wake floor code"}`
   → # Kill phrases (resident CLAUDE.md kill-switch + explicit-pause list):
#   …and [then] stop · no auto-continue · just do X · stop here · come back to this · bare stop/halt
KILL_RE='(^|[^[:alnum:]])and( then)? stop([^[:alnum:]]|$)|no[ _-]?auto[ _-]?continue|(^|[^[:alnum:]])just do [^[:space:]]|(^|[^[
6. `Bash: {"command": "F=/tmp/tokeff-gate/f2/tree/hooks/session-continue.sh; sed -n 900,1195p $F | grep -v '^\\s*#' | cat -n | sed 's/^/+899 /'", "description": "Read mechanical arm and ship floor"}`
   → +899      1	TP_MECH="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)"
+899      2	_sc_tp="$TP_MECH"; case "$_sc_tp" in "~"*) _sc_tp="$HOME${_sc_tp#\~}" ;; esac
+899      3	[ -n "$_sc_tp" ] && export WRAP_TRANSCRIPT="$_sc_tp"
+899      4	mechanical_arm() {   # rc 0 = armed (fa
7. `Bash: {"command": "F=/tmp/tokeff-gate/f2/tree/hooks/session-continue.sh; grep -n -E '^mechanical_arm\\(\\)|^ship_floor\\(\\)|^wake_floor\\(\\)|CC_MECH_CONTINUE|CC_SHIP_FLOOR|CC_WAKE_FLOOR|CLAUDE_CONTINUE_MAX|CC_MECH_MAX|rung\" = \"🔧\"|RUNG|mkdir -p \"\\$\\(continue_state_dir|log_idl armed|mfile=|n=\\$\\(\`
   → 46:# This is the hook that drives the loop: it emits {decision:"block"} up to CLAUDE_CONTINUE_MAX
132:mkdir -p "$(continue_state_dir)" 2>/dev/null
154:    log_idl armed "cli-set" "$(jq -cn --arg s "${2:-Continue the in-scope work.}" --arg c "$PWD" \
261:    printf '%s %s' "$SC_SID" "${CC_MECH_MAX:-3
8. `Bash: {"command": "F=/tmp/tokeff-gate/f2/tree/hooks/session-continue.sh; sed -n 240,265p $F; grep -n '_opane' $F | head; sed -n 1028,1052p $F; sed -n 1084,1099p $F; sed -n 580,602p $F", "description": "Read clear mode, mech budget comments, floor docs"}`
   →       [ -n "$_sc_cur_label" ] || _sc_cur_label="a caller that recorded no sid"
      echo "refused — the sentinel armed for this cwd was armed by ${_sc_owner_label}, not by you (${_sc_cur_label}); nothing was cleared: $PWD"
      log_idl refused "cli-clear-foreign-sid" "$(jq -cn --arg o "$_sc_owner"
9. `Bash: {"command": "cat > /tmp/tokeff-gate/f2/out/B01-r2/answer.md <<'EOF'\n# session-continue.sh: every condition under which the Stop hook blocks a stop\n\nFile: `/tmp/tokeff-gate/f2/tree/hooks/session-continue.sh` (1346 lines; `wc -l`)\n\n## How it blocks\n\nWhen Claude Code runs the hook as a Stop hook`
   → 369:  # ── AND `.isMeta != true`: A COMMAND/SKILL BODY IS NOT OPERATOR PROSE ─────────────────────────
380:  _j="$(jq -c 'select(.type=="user" and (.isMeta != true))
453:    case "$_ouid" in
467:    case "$_ouid" in ''|.|..|.*|*[!A-Za-z0-9._-]*) : ;; *) mailbox_promote_acked "$_ouid" ;; esac
607:  c
10. `Bash: {"command": "cd /tmp/tokeff-gate/f2/out/B01-r2 && sed -i '' -e 's/ITERM_SESSION_ID`, L608)/ITERM_SESSION_ID`, L607)/' -e 's/(L381)/(L380)/' answer.md && grep -c 'L607\\|L380' answer.md", "description": "Correct two line citations in answer"}`
   → 2
11. `StructuredOutput: {"answer_path": "/tmp/tokeff-gate/f2/out/B01-r2/answer.md", "headline": "session-continue.sh blocks a stop under 5 conditions, all by printing {decision:\"block\"} (it never blocks through its exit code): (1) a sentinel the agent set with `set` exists (L1334/1336), (2) the mechanical arm arms on thi`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
