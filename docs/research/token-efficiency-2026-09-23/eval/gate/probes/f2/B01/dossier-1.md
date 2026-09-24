# Dossier 1

## Brief
```
In /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh, list every condition under which this Stop hook blocks a stop (emits a block decision or a blocking reason). For each give the line number, one sentence on the trigger, and the env var or kill switch that disables it, if any. numbers: {"conditions": <how many you listed>}.
```

## Returned headline
session-continue.sh blocks a stop under 4 conditions, always as decision:block JSON with exit 0 (exit 2 appears only on the CLI path). (1) An agent-armed sentinel blocks at lines 1334/1336; it is disabled by the kill-switch phrase, `clear`, a sid mismatch, or the CLAUDE_CONTINUE_MAX cap. (2) The mechanical arm (own uncommitted writes on the 🔧 rung) re-uses that block at 1334/1336; it is disabled by CC_MECH_CONTINUE=0 or the CC_MECH_MAX budget. (3) The ship floor (📦/🚀 own work) blocks at 1199; it is disabled by CC_SHIP_FLOOR=0 or the CC_SHIP_FLOOR_MAX budget. (4) The wake floor (no inbox watcher armed) blocks at 894-895; it is disabled by CC_WAKE_FLOOR=0, the CC_WAKE_FLOOR_MAX budget or the CC_WAKE_FLOOR_TTL_S backoff. The kill-switch phrase also stops conditions 2-4, and the assignee and teardown-marker abstains stop conditions 2-4 as well.

## Returned numbers
`{"conditions": 4}`

## answer.md
# session-continue.sh: when the Stop hook blocks a stop

File: `/tmp/tokeff-gate/f2/tree/hooks/session-continue.sh` (1346 lines, read in full over the actuation path, lines 306-1346)

The hook blocks in only one way: it prints `{decision:"block",...}` JSON and exits 0. When the harness invokes it as a Stop hook (no arguments), it never exits 2. Every `exit 2` in the file (lines 116, 130, 216) is on the `--why`, `set`, `clear` or `status` CLI path, and at line 130 the Stop path exits 0 instead. The file has **3 places that print a block**, and **4 separate conditions** reach them. At most one fires per Stop.

## Conditions that block

| # | Block emitted at | Trigger (one sentence) | How to disable it |
|---|---|---|---|
| 1 | **1334 / 1336** (armed path; `mark_blocked continue` at 1331) | A sentinel set by the agent (`session-continue.sh set "<step>"`) exists for this cwd and gets past three checks: no kill phrase in the last real user message (1230), the stored `.sid` equals this session's sid or one of them is unknown (1248), and `.count` is below `CLAUDE_CONTINUE_MAX` (1260). The hook then blocks with "Loose ends remain... Next: <step>", plus any pending inbox mail from 1311. | Kill switch: the last non-`isMeta` user message matches `KILL_RE` (line 348: "and stop", "no auto-continue", "just do X", "stop here", "come back to this", or a bare "stop"/"halt"). `session-continue.sh clear` removes the sentinel. A sid mismatch clears it. The cap `CLAUDE_CONTINUE_MAX` (default 8) also ends it, and setting it to `0` stops every block on this path because `n -ge 0` is always true. No on/off env var exists for the agent-set sentinel. |
| 2 | **1334 / 1336**, reached through `mechanical_arm` (called at 1209, arms at 1072) | No sentinel exists. `wrap-ledger.sh --machine` reports `RUNG=🔧`, and `session_dirty_mine` finds uncommitted paths written by this session. The mechanical budget (`.mech`, default `CC_MECH_MAX` 2 per sid) is not spent. The hook then writes a "Commit the N file(s) you edited..." sentinel and continues into the same armed-path block. | `CC_MECH_CONTINUE=0` (line 941). Kill switch (952). The arm also stands down for an Agent-Teams assignee, confirmed or undecidable (970-982), and when a fresh teardown marker names the session (`CC_TEARDOWN_DIR`, `CC_WF_TEARDOWN_FRESH_S`; line 985). The budget `CC_MECH_MAX` (1055) bounds it, and `clear` uses that budget up (261). If a lib or the ledger is missing, it does not arm (997, 1000, 1014, 1016). Once armed, the kill-switch, sid and `CLAUDE_CONTINUE_MAX` checks from row 1 also apply. |
| 3 | **1199** (returned by `ship_floor`; printed at 1210-1213, `mark_blocked ship-floor`) | No sentinel exists and the mechanical arm did not arm. The ledger rung is either 📦 with unlanded commits that `session_unlanded_mine` attributes to this session, or 🚀 with `session_writes_paths` evidence that this session wrote something. The current HEAD sha has not already been nudged (1174) and the per-session count is below `CC_SHIP_FLOOR_MAX` (default 2). The hook then blocks with "SHIP FLOOR" (📦: /ship it; 🚀: run `deploy-live.sh`). | `CC_SHIP_FLOOR=0` (1101). Kill switch (1103). Assignee abstain (1105-1111). Teardown marker (1112). The latch fires once per HEAD sha. `CC_SHIP_FLOOR_MAX` is the budget (1164/1176). If attribution fails or an oracle, jq or the ledger is missing, it abstains. |
| 4 | **894-895** (returned by `wake_floor`; printed at 1215-1218, `mark_blocked wake-floor`) | No sentinel exists and neither the mechanical arm nor the ship floor fired. The pane has a valid inbox id (`CC_PANE_ID`/`ITERM_SESSION_ID`), the mailbox lib and jq are present, and no `cc-await-ping` watcher is armed (614). The hook then blocks with "WAKE FLOOR: arm your inbox watcher" if all of the following hold: this is the session's first idle, mail is pending, or open custody rows are attributed to this pane or cannot be attributed (805); the attempt count is below `CC_WAKE_FLOOR_MAX` (default 2); at least `CC_WAKE_FLOOR_TTL_S` (default 600 s) has passed since the last attempt; and the kill switch is not active. | `CC_WAKE_FLOOR=0` (604). Kill switch (852). `CC_WAKE_FLOOR_MAX` is the budget (807/838) and `CC_WAKE_FLOOR_TTL_S` the backoff (808/847). It abstains for a headless session (`CC_PANE_ID` set without `ITERM_SESSION_ID`; 656), for a live `/goal` with pending mail (697), and for an assignee or teardown-marked session (776-797). `CC_WAKE_FLOOR_TEARDOWN=0` works the other way: it turns off the assignee/teardown abstain, so the floor blocks in more cases, not fewer. An armed watcher clears the budget (614). |

**conditions: 4**. There are 3 emission sites, because conditions 1 and 2 share the block at 1334/1336.

## Order, and what is not a block

- Order when no sentinel is armed (1207-1222): mechanical arm, then ship floor, then wake floor. The first one to fire wins. If the mechanical arm arms, control falls through to the armed path (1227 onward), where the kill switch (1230), SID-BIND (1248) and cap (1260) are checked before the block at 1334/1336.
- These paths allow the stop and do not block: the kill-switch clear (1230-1235), the sid-mismatch clear (1248-1254), the cap being reached (1260-1270, which prints only `{systemMessage}`), the wake-floor budget running out (838-845, `systemMessage` only), and the headless / goal-live / teardown abstains (`systemMessage` only).
- Inbox mail is folded into the block at 1311-1326 and only adds text to the reason for condition 1 or 2. It is not a separate trigger.

## Minor observation (not asked)

- `clear` writes `${CC_MECH_MAX:-3}` into `.mech` (line 261), but `mechanical_arm` defaults `mmax` to `${CC_MECH_MAX:-2}` (1055). With the defaults the budget still counts as spent (3 >= 2), so behaviour is unchanged; the two defaults have simply drifted apart.
- `clear` stamps `.mech` with the sid from `CLAUDE_CODE_SESSION_ID`/`CLAUDE_SESSION_ID` or `?` (line 260), while the arm compares against `cur_sid` from the Stop JSON (1062). If those two differ, or the env var is unset when `clear` runs, the spent budget resets and the mechanical arm can re-block.

Method: read lines 1-133 and 230-1346 of the file with the Read tool, grepped for `decision`/`block`/`exit 2`, and grepped the CLI section (133-230) for exits. I did not run the hook or edit anything.


## Tool calls (9) with the first 300 chars of each result
1. `Bash: {"command": "cat -n /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh; ls -la /tmp/tokeff-gate/f2/out/B01-r3/ 2>&1", "description": "Read the Stop hook and check output dir"}`
   → <persisted-output>
Output too large (103.4KB). Full output saved to: /Users/chrisren/.claude-quaternary/projects/-Users-chrisren-Development--worktrees-research-tokeff-offline-gate/6fdffc57-5e3c-41f3-b9bc-8100b70ac273/tool-results/bycwjhe3n.txt

Preview (first 2KB):
     1	#!/usr/bin/env bash
     2
2. `Bash: {"command": "F=/tmp/tokeff-gate/f2/tree/hooks/session-continue.sh; wc -l $F; grep -n '\"block\"\\|decision\\|block_\\|emit_block\\|^[a-z_]*()\\|exit 2' $F | head -150; ls -la /tmp/tokeff-gate/f2/out/B01-r3/ 2>&1", "description": "Find block emission sites and functions"}`
   →     1346 /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh
46:# This is the hook that drives the loop: it emits {decision:"block"} up to CLAUDE_CONTINUE_MAX
66:# {decision:"block"} — came to write nothing at all. Measured over 978,400 IDL records across 17
72:# Stops/day against ~63k IDL rows/day, 
3. `Read: {"file_path": "/tmp/tokeff-gate/f2/tree/hooks/session-continue.sh", "offset": 24, "limit": 110}`
   → 24	# HARDENING (a19 D-7/D-8, a17 S-12) beyond the base actuator:
25	#   (a) KILL-SWITCH — actuation reads the transcript's last genuine user message; an operator
26	#       "…and stop" / "no auto-continue" / "just do X" / explicit-pause phrase clears the sentinel
27	#       and allows the stop. Oper
4. `Read: {"file_path": "/tmp/tokeff-gate/f2/tree/hooks/session-continue.sh", "offset": 1200, "limit": 147}`
   → 1200	  return 1
1201	}
1202	
1203	# No sentinel → the agent did NOT request continuation → the session is going IDLE. This is the one
1204	# transition the floors guard; a sentinel-blocked stop is not idle, so it needs no floor.
1205	# Floor order: mechanical 🔧 (uncommitted own writes) → ship floor 
5. `Read: {"file_path": "/tmp/tokeff-gate/f2/tree/hooks/session-continue.sh", "offset": 230, "limit": 420}`
   → 230	    # coincidence of absence.
231	    # The bare verb is untouched by all of this: `_sc_ifmine` is 0 without the flag, so the
232	    # operator's own park gesture — which carries no sid by construction — never reaches this test.
233	    _sc_cur="${CLAUDE_CODE_SESSION_ID:-${CLAUDE_SESSION_ID:-}}
6. `Read: {"file_path": "/tmp/tokeff-gate/f2/tree/hooks/session-continue.sh", "offset": 650, "limit": 550}`
   → 650	  # expression, at the one other site that needs the same answer.
651	  #
652	  # Placed with the other abstains, BEFORE the state-file write: an abstain must never consume a
653	  # budget attempt. And it is not silent when it costs something — with mail actually pending it
654	  # names the co
7. `Bash: {"command": "sed -n 133,230p /tmp/tokeff-gate/f2/tree/hooks/session-continue.sh | grep -n 'exit\\|case\\|^  [a-z]*)' ", "description": "Check CLI-mode exits in lines 133-230"}`
   → 6:case "${1:-}" in
7:  set)
24:    exit 0 ;;
25:  clear)
81:    case "${2:-}" in
84:      *) echo "session-continue: unknown flag for clear: ${2} (accepted: --if-mine)" >&2; exit 2 ;;
8. `Write: {"file_path": "/tmp/tokeff-gate/f2/out/B01-r3/answer.md", "content": "# session-continue.sh: when the Stop hook blocks a stop\n\nFile: `/tmp/tokeff-gate/f2/tree/hooks/session-continue.sh` (1346 lines, read in full over the actuation path, lines 306-1346)\n\nThe hook blocks in only one way: it prints`
   → File created successfully at: /tmp/tokeff-gate/f2/out/B01-r3/answer.md (file state is current in your context — no need to Read it back)
9. `StructuredOutput: {"answer_path": "/tmp/tokeff-gate/f2/out/B01-r3/answer.md", "headline": "session-continue.sh blocks a stop under 4 conditions, always as decision:block JSON with exit 0 (exit 2 appears only on the CLI path). (1) An agent-armed sentinel blocks at lines 1334/1336; it is disabled by the kill-switch phr`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
