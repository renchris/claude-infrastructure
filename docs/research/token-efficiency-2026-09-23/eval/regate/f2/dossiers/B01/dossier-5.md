# Dossier 5

## Brief
```
In /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh, list every condition under which this Stop hook blocks a stop (emits a block decision or a blocking reason). For each give the line number, one sentence on the trigger, and the env var or kill switch that disables it, if any. numbers: {"conditions": <how many you listed>}.
```

## Returned headline
session-continue.sh blocks a stop under 4 conditions. (1) An agent-set sentinel exists: blocked at lines 1334/1336, turned off only by `clear` or an operator kill phrase, and bounded by CLAUDE_CONTINUE_MAX. (2) The mechanical 🔧 arm finds this session's own uncommitted writes: it arms at line 1072 and blocks through lines 1334/1336; CC_MECH_CONTINUE=0 disables it. (3) The ship floor finds 📦/🚀 work that is this session's own: blocked at line 1199; CC_SHIP_FLOOR=0 disables it. (4) The wake floor finds no inbox watcher armed: blocked at line 895; CC_WAKE_FLOOR=0 disables it. The operator kill-switch phrases also stop all four.

## Returned numbers
`{"conditions": 4}`

## answer.md
# session-continue.sh: the conditions that block a stop

File: /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh (1347 lines, read in full)

In Stop-actuation mode (no CLI argument, Stop JSON on stdin) the hook always exits 0. It blocks only by printing `{decision:"block", reason:...}`. There are three places that print it (lines 895, 1199 and 1334/1336). They are reached under 4 separate trigger conditions, because the loose-ends continuation block can come from either an agent-set sentinel or a mechanically armed one.

| # | Condition | Emit line (routed at) | Trigger (one sentence) | Disable / kill switch |
|---|---|---|---|---|
| 1 | Agent-armed sentinel (the continuation block) | 1334 (with pending-mail systemMessage) / 1336 (plain) | A sentinel file for this cwd exists because the agent ran `session-continue.sh set "<step>"`, the operator's last message is not a kill phrase, the stored `.sid` does not belong to a different session, and `.count` is below `CLAUDE_CONTINUE_MAX` (default 8). The block feeds the step back, with any new inbox mail added in front. | Run `session-continue.sh clear`, or type an operator kill phrase (`KILL_RE`, line 348: "...and stop", "no auto-continue", "just do X", "stop here", "come back to this", a bare "stop"/"halt"; checked at line 1230). A sid mismatch also clears it (line 1248). `CLAUDE_CONTINUE_MAX` caps the chain (lines 1257-1270), but a fresh `set` resets the counter, so it is a bound, not an off switch. No env var turns this condition off. |
| 2 | Mechanical 🔧 arm (writes the sentinel, then falls through to the same block) | `mechanical_arm` 940-1081 writes the sentinel at 1072; the block is emitted at 1334/1336 | No sentinel exists, but the wrap-ledger rung is 🔧 and `session_dirty_mine` shows at least one uncommitted dirty file that this session wrote. The per-session `.mech` budget must also be below `CC_MECH_MAX` (default 2). The hook then arms a "commit the N file(s)" sentinel and blocks through path 1. | `CC_MECH_CONTINUE=0` (line 941). Also a kill phrase (line 952), an Agent-Teams assignee (confirm rc 0 or 2, lines 970-982), a fresh teardown marker (line 985), `CC_MECH_MAX` exhaustion (line 1064), or `session-continue.sh clear`, which marks the `.mech` budget spent (line 261). |
| 3 | Ship floor | 1199 (printed at 1212) | No sentinel exists and the mechanical arm did not arm, and the rung is either 📦 or 🚀. For 📦 there must be committed-but-unlanded commits that contain this session's own writes (`session_unlanded_mine`). For 🚀 (landed but not live) this session must have write evidence. It fires at most once per HEAD sha, up to `CC_SHIP_FLOOR_MAX` per session (default 2). | `CC_SHIP_FLOOR=0` (line 1101). Also a kill phrase (line 1103), an assignee (line 1105), a teardown marker (line 1112), the same-sha latch (line 1174), or `CC_SHIP_FLOOR_MAX` exhaustion (line 1176). |
| 4 | Wake floor | 895 (printed at 1217) | No sentinel exists, no other floor fired, and the pane has an inbox id but no armed `cc-await-ping` watcher. It is also either the session's first idle, or mail is pending, or open custody rows belong to this pane or cannot be attributed. The `CC_WAKE_FLOOR_MAX` budget (default 2) must not be spent and `CC_WAKE_FLOOR_TTL_S` (default 600 s) must have passed. The block tells the model to arm the watcher (the `--idle-scoped` form when a /goal is live). | `CC_WAKE_FLOOR=0` (line 604). Also a kill phrase (line 852). It stands down for a headless session (`CC_PANE_ID` set and `ITERM_SESSION_ID` empty, line 656) and for a live /goal with pending mail (line 697). It stands down for an assignee or a fresh teardown marker only while `CC_WAKE_FLOOR_TEARDOWN=1` (the default). Setting that variable to 0 turns off those abstains, so the floor becomes more likely to block, not less (line 776). Budget or TTL limits also stop it (lines 838 and 847), and so does an already-armed watcher (line 614). |

Only one floor fires per Stop, in the order mechanical, then ship, then wake (lines 1207-1225). The floors run only when no sentinel exists. When a sentinel does exist, the kill-switch check (line 1230), the SID-bind check (line 1248) and the cap check (line 1260) are applied, in that order, before the block.

## Not counted: non-zero exits that are not Stop blocks
- Line 116 (`exit 2`): runs only when the first argument is `--why` and the reference tier is missing. That is terminal/CLI use, not a Stop.
- Line 130 (`exit 2`): runs when the sentinel library is missing, but only for the `set`/`clear`/`status` CLI verbs. In actuation mode the same failure exits 0 and allows the stop.
- Line 216 (`exit 2`): an unknown `clear` flag. CLI only.
- Lines 659, 699, 792, 842, 853, 1266 and 1220 print only `{systemMessage:...}`, which is advisory and does not block.

## Side observation (not asked)
`clear` spends the mechanical budget by writing `"$SC_SID ${CC_MECH_MAX:-3}"` (line 261). The reader, however, defaults `mmax` to 2 (line 1055) and resets the count whenever the stored sid differs from `cur_sid` (line 1062). So a `clear` run from a bare shell with no session id writes the sid as `?`. That does not spend the budget for a session whose id is known, and the mechanical arm can fire again for that session.


## Tool calls (5) with the first 300 chars of each result
1. `Read: {"file_path": "/tmp/tokeff-regate/f2/tree/hooks/session-continue.sh"}`
   → 1	#!/usr/bin/env bash
2	# session-continue.sh — 🔧 loose-ends continuation loop (agent-set sentinel + Stop-hook actuator).
3	#
4	# WHY: a Stop hook fired on its own is SCOPE-BLIND — a shell script can't tell an
5	# in-scope loose end from an intentional pause or out-of-scope dirt, so a standalone
6	#
2. `Read: {"file_path": "/tmp/tokeff-regate/f2/tree/hooks/session-continue.sh", "offset": 675, "limit": 674}`
   → 675	  # ── FLIPPED FROM ABSTAIN TO "INSTRUCT THE SAFE FORM" (2026-08-16, goal-safe-2way-comms §4 C7) ────
676	  # The abstain above closed the starvation pole and left the session in the SPIN one: bare, blocking
677	  # every stop on an unmet goal, re-judging a world nothing has changed — 90 consecu
3. `Bash: {"command": "mkdir -p /tmp/tokeff-regate/f2/out/B01-r2 && ls /tmp/tokeff-regate/f2/out/B01-r2", "description": "Ensure output directory exists"}`
   → (Bash completed with no output)
4. `Write: {"file_path": "/tmp/tokeff-regate/f2/out/B01-r2/answer.md", "content": "# session-continue.sh: the conditions that block a stop\n\nFile: /tmp/tokeff-regate/f2/tree/hooks/session-continue.sh (1347 lines, read in full)\n\nIn Stop-actuation mode (no CLI argument, Stop JSON on stdin) the hook always exi`
   → File created successfully at: /tmp/tokeff-regate/f2/out/B01-r2/answer.md (file state is current in your context — no need to Read it back)
5. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B01-r2/answer.md", "headline": "session-continue.sh blocks a stop under 4 conditions. (1) An agent-set sentinel exists: blocked at lines 1334/1336, turned off only by `clear` or an operator kill phrase, and bounded by CLAUDE_CONTINUE_MAX. (2) The mechanical`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
