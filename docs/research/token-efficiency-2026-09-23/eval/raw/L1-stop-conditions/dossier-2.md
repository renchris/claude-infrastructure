# Dossier 2

## Brief

Read-only. In /Users/chrisren/Development/claude-infrastructure/hooks/session-continue.sh, list every condition under which the Stop hook blocks a stop (emits a block decision or a blocking reason). For each give the line number, one sentence on the trigger, and the env var or kill switch that disables it, if any. Write the list to /tmp/tokeff-eval/lean/L1-stop-conditions/out-2/answer.md and reply with that path.

## Answer file contents (verbatim)

````markdown
# session-continue.sh — Stop-hook block conditions

Source: /Users/chrisren/Development/claude-infrastructure/hooks/session-continue.sh (1344 lines, measured with `wc -l`).
I found the lines by reading the file with `sed -n` and `grep -n`. The Stop hook always blocks through stdout JSON `{decision:"block",...}` and then `exit 0`. The Stop path never uses exit 2 to block (header :36-37).

There are three emit sites. The first two are "floors" that run only when **no sentinel** exists, and at most one of them fires per Stop (dispatch at :1205-1219). The third is the armed "continue" path.

## 1. SHIP FLOOR: block (emit at :1197, printed at :1210)
- **Trigger:** No sentinel exists and the mechanical arm did not arm. The wrap-ledger rung is 📦 (committed-but-unlanded commits that contain this session's own writes, per `session_unlanded_mine`) or 🚀 (landed but not live, with write evidence from this session). The current HEAD sha has not already been nudged, and the per-session count is below the cap.
- **Disabled by:** `CC_SHIP_FLOOR=0` (:1099).
- **Bounded by:** `CC_SHIP_FLOOR_MAX` (default 2 per session, :1162). It is latched to one fire per HEAD sha (:1172).
- **Also abstains on:** a kill-switch phrase in the last user message (:1101), a confirmed or undeterminable team assignee (:1102-1108), a teardown marker (:1109), a missing jq, ledger, or session-writes lib (:1100, :1123-1127, :1139), and attribution refused (:1147-1153).

## 2. WAKE FLOOR: block (emit at :892-893, printed at :1215)
- **Trigger:** No sentinel exists, neither the mechanical arm nor the ship floor fired, and no inbox wake path (cc-await-ping watcher) is armed for this pane (:614). One of these is also true: this is the session's first wake-floor attempt, mail is pending, or open cc-custody rows are attributable to this pane or unattributable (:805). It blocks to tell the model to arm the watcher.
- **Disabled by:** `CC_WAKE_FLOOR=0` (:604).
- **Bounded by:** `CC_WAKE_FLOOR_MAX` (default 2, :807; exhaustion allows the stop with a systemMessage, :835-842) and `CC_WAKE_FLOOR_TTL_S` (default 600 s between attempts, :808, :845). A new session id resets the budget.
- **Also abstains on:** a kill-switch phrase (:850), a headless session where `CC_PANE_ID` is set and `ITERM_SESSION_ID` is not (:656), a live /goal with mail pending (:697), and a team-assignee or teardown marker (:776-802). `CC_WAKE_FLOOR_TEARDOWN=0` turns off that last abstain; it does not turn off the floor. It also abstains when jq or the mailbox lib is missing or the pane id is invalid (:605-607).

## 3. ARMED CONTINUE path, "🔧 Loose ends remain": block (emit at :1332 with systemMessage when inbox mail is folded in, otherwise :1334)
- **Trigger:** A continuation sentinel exists for this cwd. Either the agent armed it with `session-continue.sh set "<step>"`, or the mechanical arm armed it (see 3a). The last user message has no kill phrase (:1228), the stored sid does not differ from the current sid (:1246), and the count is below the cap (:1258). The block reason carries the next step, plus any pending peer mail prepended (:1309-1323).
- **Disabled by:** `session-continue.sh clear` (removes the sentinel), or a kill-switch phrase in the last genuine user message (`KILL_RE` at :348, checked by `kill_switch_active` at :391, applied at :1228). No dedicated env on/off switch exists. `CLAUDE_CONTINUE_MAX` (default 8, :1255) is the loop cap: at or above it the hook clears and allows. Setting it to 0 in effect disables the path (inferred from the code, not tested).

### 3a. MECHANICAL 🔧 arm (feeds path 3; the arm itself does not emit): `mechanical_arm` at :938, sentinel write at :1070
- **Trigger:** No sentinel exists, the wrap-ledger rung is 🔧 (:1017), and `session_dirty_mine` finds at least one dirty path written by this session (:1021-1028). The arm then writes the sentinel ("Commit the N file(s) you edited…") and falls through to the block at path 3.
- **Disabled by:** `CC_MECH_CONTINUE=0` (:939).
- **Bounded by:** `CC_MECH_MAX` (default 2 per session id, in `${f}.mech`, :1053-1066). The `clear` CLI spends that budget (:261). Worst case is CC_MECH_MAX × CLAUDE_CONTINUE_MAX forced turns (from the comment at :1047).
- **Also stands down on:** a kill-switch phrase (:950), a confirmed or undeterminable assignee (:966-981), and a teardown marker (:983).

## Not Stop-hook blocks (exit 2 only in CLI modes)
- :116 is `--why` with the reference-tier lib missing.
- :130 is the `set|clear|status` CLI when continue-sentinel.sh fails to source. The Stop path exits 0 in that case.
- :216 is `clear` given an unknown flag.

These exits signal errors to a CLI caller. They do not block a stop.

## Global kill switch
The kill phrase regex `KILL_RE` (:348) matches the operator's last non-meta user message. It stops all three emitters: ship :1101, wake :850, mechanical :950, armed path :1228. The hook has no single master env var. Each emitter has its own env switch, listed above.
````

## Tool calls

1. **Bash** — `{"command": "wc -l /Users/chrisren/Development/claude-infrastructure/hooks/session-continue.sh; ls -la /tmp/tokeff-eval/lean/L1-stop-conditions/out-2/ 2>&1; ls /Users/chrisren/Development/claude-infra`
2. **Bash** — `{"command": "cd /Users/chrisren/Development/claude-infrastructure/hooks; grep -n -E 'block|decision|reason|exit 2|KILL|DISABLE|_OFF|kill' session-continue.sh | head -200", "description": "Find block/d`
3. **Bash** — `{"command": "cd /Users/chrisren/Development/claude-infrastructure/hooks; sed -n 36,60p session-continue.sh; echo ----; sed -n 95,135p session-continue.sh; echo ----; sed -n 300,440p session-continue.s`
4. **Bash** — `{"command": "cd /Users/chrisren/Development/claude-infrastructure/hooks; sed -n 590,900p session-continue.sh", "description": "Read wake floor function"}`
5. **Bash** — `{"command": "cd /Users/chrisren/Development/claude-infrastructure/hooks; sed -n 900,1344p session-continue.sh", "description": "Read mechanical floor, ship floor, and armed path"}`
6. **Bash** — `{"command": "cd /Users/chrisren/Development/claude-infrastructure/hooks; sed -n 95,135p session-continue.sh; echo -----; sed -n 136,300p session-continue.sh | grep -n -E 'exit|CLAUDE_|CC_|^\\s*case|\\`
7. **Bash** — `{"command": "cd /Users/chrisren/Development/claude-infrastructure/hooks; sed -n 290,345p session-continue.sh | grep -v '^\\s*#'; sed -n 395,420p session-continue.sh | grep -v '^\\s*#'", "description":`
8. **Bash** — `{"command": "cd /Users/chrisren/Development/claude-infrastructure/hooks; grep -n -E 'CC_WAKE_FLOOR:-1|CC_SHIP_FLOOR:-1|CC_MECH_CONTINUE:-1|CC_MECH_MAX:-|CC_SHIP_FLOOR_MAX:-|CC_WAKE_FLOOR_MAX:-|CC_WAKE`
9. **Write** — `{"file_path": "/tmp/tokeff-eval/lean/L1-stop-conditions/out-2/answer.md", "content": "# session-continue.sh \u2014 Stop-hook block conditions\n\nSource: /Users/chrisren/Development/claude-infrastructu`
10. **SubagentHandback** — `{"message": "The list is at /tmp/tokeff-eval/lean/L1-stop-conditions/out-2/answer.md. The hook blocks a stop in three places, and a fourth condition arms one of them. Every block is stdout JSON `{deci`
