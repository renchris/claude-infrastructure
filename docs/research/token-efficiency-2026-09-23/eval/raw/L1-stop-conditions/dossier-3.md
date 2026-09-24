# Dossier 3

## Brief

Read-only. In /Users/chrisren/Development/claude-infrastructure/hooks/session-continue.sh, list every condition under which the Stop hook blocks a stop (emits a block decision or a blocking reason). For each give the line number, one sentence on the trigger, and the env var or kill switch that disables it, if any. Write the list to /tmp/tokeff-eval/lean/L1-stop-conditions/out-3/answer.md and reply with that path.

## Answer file contents (verbatim)

````markdown
# session-continue.sh: the conditions that block a stop

Source: `/Users/chrisren/Development/claude-infrastructure/hooks/session-continue.sh` (1345 lines, read in full).

In Stop mode the hook always exits 0 (lines 1211, 1216, 1219, 1344). It blocks a stop only by printing
`{decision:"block",reason:…}` on stdout. There are **three emit sites** in the file: ship floor at
line 1197, wake floor at lines 892-893, and continuation at lines 1332/1334. They are reached by **four**
trigger conditions, because the mechanical 🔧 arm has no emit site of its own. It arms the sentinel and
falls through to the continuation emit. At most one block is emitted per Stop.

Order of evaluation for each Stop:
1. If a sentinel exists, go to the armed path (3).
2. If no sentinel exists: run the mechanical arm (4). If it arms, go to the armed path (3). If it does
   not arm, run the ship floor (1), then the wake floor (2). See lines 1205-1223.

The kill switch is shared by every condition below. It is `kill_switch_active` (lines 391-395): the last
genuine user message in the transcript (`.isMeta != true`) matches `KILL_RE` (line 348). That regex covers
"…and [then] stop", "no auto-continue", "just do X", "stop here", "come back to this", and a bare
"stop"/"halt". It is not an env var. It depends on the Stop JSON carrying a readable `transcript_path`.

---

## 1. Ship floor, 📦 committed-but-unlanded (emit L1197; reason L1185; printed at L1210)
- **Trigger:** No sentinel is armed and the mechanical arm did not arm. `wrap-ledger.sh --machine` reports
  `RUNG=📦` with a real `TRUNK`. `session_unlanded_mine` confirms that the unlanded commits contain this
  session's own writes. The current HEAD sha has not already been nudged for this sid (L1172). The
  per-session count is below the max (L1174).
- **Disabled by:**
  - `CC_SHIP_FLOOR=0` (L1099)
  - the kill switch (L1101)
  - the budget `CC_SHIP_FLOOR_MAX` (default 2, L1162)
  - the once-per-HEAD-sha latch in `${f}.ship` (L1172)
  - abstains for a team assignee (rc 0 or 2, L1103-1109) and for a fresh teardown marker (L1110; window
    `CC_WF_TEARDOWN_FRESH_S`, dir `CC_TEARDOWN_DIR`)
  - silently when jq, the ledger (`WRAP_LEDGER_BIN`) or the attribution lib (`SESSION_WRITES_LIB`) is missing

## 2. Ship floor, 🚀 landed-but-not-live (emit L1197; reason L1187-1193; printed at L1210)
- **Trigger:** Same path as #1, but the ledger reports `RUNG=🚀`: the enforcing store has breached its
  converge budget. `session_writes_paths` must also show that this session wrote something (L1153-1155).
- **Disabled by:** the same switches as #1: `CC_SHIP_FLOOR=0`, the kill switch, `CC_SHIP_FLOOR_MAX`, the
  HEAD-sha latch, and the assignee and teardown abstains.

## 3. Wake floor, going idle with no inbox watcher armed (emit L892-893; printed at L1215)
- **Trigger:** No sentinel is armed, and neither the mechanical arm nor the ship floor acted. The pane has
  a valid inbox id (`CC_PANE_ID`/`ITERM_SESSION_ID`). `mailbox_wake_armed` is false, so no `cc-await-ping`
  heartbeat exists. The floor then fires if this is the session's first idle (`count=0`), or if mail is
  pending, or if there are open custody rows attributed to this pane (or rows that cannot be attributed)
  (L805). Its bound is `(cnt ≥ max)` (L836), its re-fire spacing is `(now−ts ≥ TTL)` (L845), and it fires
  only when the kill switch is not active (L850).
- **Disabled by:**
  - `CC_WAKE_FLOOR=0` (L604)
  - the kill switch (L850)
  - the budget `CC_WAKE_FLOOR_MAX` (default 2, L807). Once it is exhausted, a systemMessage is shown and
    the stop is allowed.
  - the minimum re-fire interval `CC_WAKE_FLOOR_TTL_S` (default 600, L808)
  - abstain for a headless session: `CC_PANE_ID` set and `ITERM_SESSION_ID` empty (L656)
  - abstain when a /goal is live and mail is pending (L697)
  - abstains for a team assignee or teardown marker (L776-798). These are controlled by
    `CC_WAKE_FLOOR_TEARDOWN`: the default of 1 enables the abstains, and setting it to 0 turns the abstains
    off, which makes the floor block *more* often, not less.
  - silently when jq or the mailbox lib is missing
  - arming the watcher itself (`mailbox_wake_armed`, L614), which also resets the budget

## 4. Armed sentinel, loose-ends continuation (emit L1332 or L1334)
- **Trigger:** A sentinel file exists for this config-dir+cwd, either agent-armed through
  `session-continue.sh set "<step>"` or mechanically armed (#5). None of the three guards cleared it:
  kill switch (L1228), sid mismatch (L1246), or cap (L1258). The hook then blocks with
  "🔧 Loose ends remain … Next: <step>". Any pending peer mail is prepended to the reason (L1309-1316).
  The mail does not create a separate block.
- **Disabled by:**
  - the kill switch (L1228), which clears the sentinel and allows the stop
  - `session-continue.sh clear` (L157-291), which removes the sentinel
  - SID-BIND (L1245-1252): a sentinel whose `.sid` differs from the current session's sid is cleared
  - the cap `CLAUDE_CONTINUE_MAX` (default 8, L1255). At the cap, a systemMessage is shown and the stop is
    allowed. A fresh `set` resets `.count`.

## 5. Mechanical 🔧 arm, uncommitted own writes (arms at L1070 and falls through to the emit at L1332/1334)
- **Trigger:** No sentinel is armed, the ledger reports `RUNG=🔧`, and `session_dirty_mine` returns rc 0
  with at least one dirty path written by this session. The arm then writes a "Commit the N file(s) you
  edited…" sentinel. The armed path in #4 emits the block.
- **Disabled by:**
  - `CC_MECH_CONTINUE=0` (L939)
  - the kill switch (L950)
  - the per-session budget `CC_MECH_MAX` (default 2, L1053, stored in `${f}.mech`)
  - `session-continue.sh clear`, which spends that budget at L261
  - abstain for a team assignee (rc 0 or 2, L968-981)
  - abstain for a teardown marker (L983)
  - `WRAP_LEDGER_BIN` and `SESSION_WRITES_LIB` are seams. A missing ledger or lib means no arm.
  - Once armed, every guard from #4 also applies, including `CLAUDE_CONTINUE_MAX`.

---

## Paths that do NOT block in Stop mode (checked)
- **L116:** `exit 2` on the `--why` arm (missing reference tier). This runs only from the CLI with `--why`.
- **L130:** `exit 2` if the sentinel lib fails to source. This happens only for the `set`, `clear` and
  `status` args. Stop mode exits 0 here, and the whole loop is inert.
- **L216:** `exit 2` on an unknown `clear` flag. This is CLI only.
- **L840, L851, L659, L699, L792, L1264:** these emit a `systemMessage` only and allow the stop.

## Notes
- If jq is missing, every emit fails. #1-#3 return early when jq is missing. In #4 the `jq -nc` call at
  L1332/1334 fails, so no block is written and the stop is allowed.
- The default for `CC_MECH_MAX` differs between two sites: `clear` writes `${CC_MECH_MAX:-3}` (L261) but
  the arm reads a default of 2 (L1053). Because 3 ≥ 2, `clear` still spends the budget. The mismatch looks
  cosmetic.
- `mark_blocked` (L333) writes `${f}.blocked` at each block (L1209, L1214, L1329). That file is for
  completion-assert and does not affect blocking itself.
````

## Tool calls

1. **Read** — `{"file_path": "/Users/chrisren/Development/claude-infrastructure/hooks/session-continue.sh"}`
2. **Bash** — `{"command": "ls /Users/chrisren/Development/claude-infrastructure/.claude/rules/ 2>/dev/null; ls -la /tmp/tokeff-eval/lean/L1-stop-conditions/out-3/ 2>&1", "description": "List repo rules and check ou`
3. **Read** — `{"file_path": "/Users/chrisren/Development/claude-infrastructure/hooks/session-continue.sh", "offset": 675, "limit": 674}`
4. **Read** — `{"file_path": "/Users/chrisren/Development/claude-infrastructure/.claude/rules/agent-operating-lessons.md"}`
5. **Write** — `{"file_path": "/tmp/tokeff-eval/lean/L1-stop-conditions/out-3/answer.md", "content": "# session-continue.sh: the conditions that block a stop\n\nSource: `/Users/chrisren/Development/claude-infrastruct`
6. **SubagentHandback** — `{"message": "The list is written to /tmp/tokeff-eval/lean/L1-stop-conditions/out-3/answer.md.\n\nThe Stop hook blocks only by printing a \"block\" decision; in Stop mode it always exits 0. Five condit`
