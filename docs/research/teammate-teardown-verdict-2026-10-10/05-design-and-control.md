# 05 — design and control: the busy-teammate teardown verdict

Slot: design-and-control (question 5 + design). Worktree HEAD `16b6b441f`; subject file
`hooks/lead-crash-watchdog.sh` (2136 lines, last touched by `c3d5a71dc`). Read-only run: no tracked
file edited, no process signalled. Scratch files lived only under `mktemp -d` dirs outside the repo
(a prototype `.bats` and a plain-bash replay of it). That is the one place I went past "write only
the delivery file", and only to isolate stores as the brief allows.

## 0. Verdict first

- **Verified, on current code:** the real incident transcript classifies `CRASH abrupt-unknown`, with
  or without `LEAD_AGENT_ID` (§1.1). The fact that the member was retired exists in one durable place
  only: a harness-written `toolUseResult` in the **lead's** transcript (§1.2). The member's inbox and
  the team config hold nothing usable (§1.3).
- **The regression test fails today and the control passes today** (§2, measured with a plain-bash
  replay of the exact fixture: 3 FAIL / 5 PASS on the regression, 4/4 PASS on the control, 2/2 PASS on
  the guards). bats itself was refused by the machine's admission gate the whole time (§2.4), so these
  are **not** bats results.
- **Recommendation: D1, with the D4 refinements.** Teach `teammate_facts` to read the lead's
  transcript for a structured, harness-written shutdown_request result naming this member. Add a
  generation guard (the request must be newer than the member's first record) and, optionally, a
  successful TaskStop of `in_process_teammate` joined on its tool_use_id. Fix the two renderer lines.
  One file plus one test file. **Conviction 85%.**

## 1. Facts this design rests on (re-verified, not taken from the brief)

### 1.1 Current code misclassifies the real incident

Command (isolated stores, real transcript read-only, death epoch = 18:05:00Z):

```
T=$(mktemp -d); HOME=$T/home CC_ACCOUNT_BASES=/Users/chrisren/.claude-quaternary CC_TEARDOWN_DIR=$T/td \
 CC_REGISTRY_DIR=$T/reg CC_CLOSE_RECORDS_DIR=$T/close CC_JETSAM_DIRS=$T/jet CC_HANDOFF_LOG=$T/h.jsonl \
 bash hooks/lead-crash-watchdog.sh --classify 5b813b72-0d7c-40ab-bf65-40d9ee333fd3 23017 1791655500
=> CRASH	abrupt-unknown	1159	390
(same with CC_PANE_VERDICT_AGENT_ID=cvf-docs@session-247fdf36)
=> CRASH	abrupt-unknown	1159	390
```

`find $T -type f` afterwards was empty, so `--classify` wrote nothing. The live log agrees.
`~/.claude/logs/lead-crash-watchdog.log:59402` shows `death class=CRASH cause=abrupt-unknown (1159KB/390recs …)`,
`:59403` shows the desk was **paged** at 13:07:03 local (18:07:03Z), and `:59405` shows the pane was
painted at 13:08:04 local. So the bug did two things: it painted a false verdict, and it sent a false
page. The siblings show the contrast. `cvf-readout` (`:59398`) and `cvf-hooks` (`:59407`) were idle,
got the request delivered, and classified `RECYCLE cause=retired-teammate`, and their panes closed.

Member transcript (`…/5b813b72-….jsonl`, 390 lines):
- every member record carries `teamName=session-247fdf36` and `agentName=cvf-docs`
  (`python3` set of pairs ⇒ `{('session-247fdf36','cvf-docs'), (None,None)}`);
- `grep -n shutdown_request` ⇒ 5 hits, at lines 10, 88, 129, 322 and 357. **All 5 are prose**
  (the instructions attachment, tool_result text, the deferred-tools record). None is a
  `<teammate-message>` user record;
- last real records: `18:04:24.713Z` user tool_result (Edit of `hooks/lib/why-tier.sh`), then
  `18:04:26.867Z` assistant `tool_use Bash` with **no tool_result**. It was killed mid-call;
- first timestamped record `2026-10-10T17:53:56.848Z`;
- recorded `cwd` set = `{'/Users/chrisren/Development/.worktrees/close-verdict-first'}`. That is the
  **lead's** worktree, while the edits went to `~/Development/.worktrees/cvf-docs`
  (`git -C … status --short` ⇒ ` M CLAUDE.global.md`, ` M CLAUDE.rules.slim.10-session-close.md`,
  ` M hooks/lib/why-tier.sh`, on top of `eec712aee`).

No close record and no teardown marker exist: `ls ~/.claude/logs/close-records/ | grep '^23017-'` ⇒
empty, and `ls ~/.claude/watchdog/teardown/ | grep -E '5b813b72|23017|^200\.json'` ⇒ none.

### 1.2 The lead's transcript holds the evidence, in structured form

`…/247fdf36-….jsonl` (1224 lines, 4.6 MB):

| line | ts (Z) | record |
|---|---|---|
| 820 | 18:04:25.438 | assistant `tool_use SendMessage` input `{"to":"cvf-docs","message":{"type":"shutdown_request",…}}` |
| 828 | 18:04:26.207 | user tool_result, **`toolUseResult`** `{"success":true,"request_id":"shutdown-1791655466065@cvf-docs","target":"cvf-docs"}` |
| 842 | 18:04:40.623 | assistant `tool_use TaskStop` input `{"task_id":"cvf-docs"}` |
| 843 | 18:04:50.929 | user `toolUseResult` `{"message":"Successfully stopped task: t5ou0rn4u …","task_type":"in_process_teammate"}` (does **not** name the member, so it can only be joined through tool_use_id `toolu_01H3E8rmy6YnLb5VhoysXSZU` to line 842) |
| 857 | 18:04:59.336 | `Bash kill -TERM 23017; …` |

Lead records carry neither `teamName` nor `agentName` (keys dumped: `type, timestamp, sessionId,
toolUseResult, sourceToolAssistantUUID, message`).

How much noise is there? `grep -c shutdown_request` on the lead transcript gives 16 lines and
`grep -c '@cvf-docs'` gives 5. A structural parse (user record with a dict `toolUseResult`,
`success is True`, `request_id` starting `shutdown-` and ending `@cvf-docs`, `target == "cvf-docs"`)
gives **exactly one hit**, `('2026-10-10T18:04:26.207Z','shutdown-1791655466065@cvf-docs')`. The
TaskStop join gives one hit, `('2026-10-10T18:04:50.929Z','t5ou0rn4u')`. With a substring prefilter
the parse took 0.07 s wall time on the 4.6 MB file (measured, `time python3 -I …`).

**Timing.** The evidence is written before the kill, and so before the watchdog's classify. Records
are appended in order: line 828 at 18:04:26 precedes the lead's own `kill` tool_use at 18:04:59, and
classify ran before the 18:07:03Z page. Any reasonable lead does the same: it sends the request (or
TaskStop) and then kills. If a lead kills with neither, D1 abstains (§3).

**Lead-sid derivability** (measured over every `~/.claude*/teams/*/config.json`): 476 configs, all
476 have `leadSessionId`, and **475/476 are named `session-<leadSessionId[:8]>`**. The exception is
`bsm-port`. `find_transcript` already globs `projects/*/"$sid"*.jsonl`, so an 8-char prefix
resolves (`lead-crash-watchdog.sh:146-157`).

### 1.3 Team inbox and config hold no usable evidence (this rules out D2)

`~/.claude-quaternary/teams/session-247fdf36/inboxes/cvf-docs.json` contains `[]` and has mtime
**13:04:26 local = 18:04:26Z**, the second the request was sent. The member's poller drained it
straight into the busy process's memory, and the process died before the message reached its
transcript. `config.json` (mtime 13:12:12 local, i.e. the cvf-hooks removal) now lists only
`team-lead`, so the removal time of `cvf-docs` is unrecoverable. The config does carry
`leadSessionId` in full, which makes it useful as a **resolver** (team → lead sid) when the team dir
still exists. A populated config elsewhere (`~/.claude-next/teams/session-117784d6/config.json`)
shows member fields `agentId, name, tmuxPaneId, cwd, backendType, isActive, joinedAt, …` and **no
sid or pid**.

## 2. (a) Existing coverage, (b) the regression test and its control

### 2.1 Existing bats coverage for the teammate verdict

`grep -rn -E 'teammate_facts|retired-teammate|retired_teammate|RETIRED — teammate|re-spawns members|LEAD_AGENT_ID' tests`
returns hits **only** in `tests/watchdog-retired-teammate.bats`. No test names `teammate_facts`,
`LEAD_AGENT_ID` or "re-spawns members" literally. The agent-id path is covered through its seam
`CC_PANE_VERDICT_AGENT_ID` (`lead-crash-watchdog.sh:1310`).

Harness (`watchdog-retired-teammate.bats:14-38`): `HOME=$T/home`. Every store is pointed into
`$BATS_TEST_TMPDIR`: `CC_ACCOUNT_BASES=$T/acct`, `CC_JETSAM_DIRS`, `CC_TEARDOWN_DIR`,
`CC_REGISTRY_DIR`, `CC_ROLES_DIR`, `CC_SESSIONS_LOG`, `CC_HANDOFF_LOG` and `CC_CLOSE_RECORDS_DIR`.
The pane is faked through `CC_PANE_VERDICT_DEV=$T/dev`, `CC_PANE_VERDICT_TTY=ttys099` (a plain file)
and `CC_PANE_VERDICT_TTY_PROCS` (holding `Ss+ /bin/zsh -l`), with `SETTLE_S=0`, `PANE=33`,
`CFG=/x/.claude-tertiary` and `CWD=$T/nocwd`. The closer, pager and osascript are argv-recorder
stubs (`CC_PANE_CLOSE_BIN`, `CC_DEATH_PAGER`, `CC_DEATH_OSA_BIN`), and `CLOSE_GRACE_S=0`. The member
sid is `74148f20-…` and `TX=$T/acct/projects/proj/$SID.jsonl`.
Helpers: `mk_member_tx` (:42-47) writes 3 records carrying `teamName=session-4726bdf3` and
`agentName`: a teammate-message intro, a prose instructions attachment, and an assistant text.
`add_shutdown` (:48-50) appends a delivered `<teammate-message>` user record whose JSON has
`"type":"shutdown_request","requestId":"shutdown-…@<name>"`. `verdict` (:51-53) runs
`bash "$HOOK" --pane-verdict "$SID" 63977 <class> <cause> <exit> <sig> "$TX"`, and `painted` (:54)
cats the fake tty.
Entrypoints used: `--classify <sid> <pid>` (hook :1597), `--pane-verdict` (:1591), `--surface-death`
(:1581) and `--close-fields` (:1603).

| # | test name | file:line | fixture | invocation |
|---|---|---|---|---|
| 1 | a teammate shut down by its lead classifies RECYCLE/retired-teammate, and the death page is NOT sent | `watchdog-retired-teammate.bats:58` | mk_member_tx + add_shutdown(self) | `--classify $SID ""`, `--surface-death … RECYCLE retired-teammate`, asserts `$PAGED` empty |
| 2 | a retired teammate overrides a close record's exit code too (signal is not a crash) | `:68` | same + close record pid 7001 exit 137 | `--classify $SID 7001` (arm 0) |
| 3 | the retired banner says RETIRED and close this pane, and offers no resume at all | `:75` | same | `verdict RECYCLE retired-teammate`; greps `RETIRED — teammate lt-wrap (session 74148f20) was shut down by its lead`, `close this pane`, no `Resume`/`--resume` |
| 4 | a shutdown_request addressed to ANOTHER member, or only mentioned in prose, is not a retirement | `:85` | add_shutdown(someone-else); prose-only | `--classify` ⇒ `!= retired-teammate` |
| 5 | the registration-time agent id identifies the member when its records carry no teamName | `:94` | bare user record with shutdown_request@acct-routing, no teamName | `CC_PANE_VERDICT_AGENT_ID=acct-routing@session-6a000e4a --classify` |
| 6 | a teammate death WITHOUT a shutdown_request keeps its class, and its banner names the lead instead of --resume | `:102` | mk_member_tx only | `--classify` ⇒ CRASH; `verdict CRASH external-sigterm 143 15` ⇒ `NOT A CLEAN EXIT` + `tell its lead (session 4726bdf3)`; `verdict RECYCLE clean-exit 0` ⇒ `tell its lead` |

The gap: every positive case puts the request **in the member's own transcript**. No fixture models a
busy member, a dangling tool_use, a lead transcript, or timestamps. Test 6 is the closest relative of
this incident, and it **pins the current wrong behaviour** for the "no request in own transcript" shape.
That is correct for the control and must stay true when no lead evidence exists.

### 2.2 The regression fixture (models the incident's identifier shapes)

The fixture-shape lesson (`.claude/rules/agent-operating-lessons-situational.md:40`) asks for this:
the lead lives in a **different account base** from the member, its sid shares only the 8-char prefix
with the team name, and its records carry no team fields. Add to `setup()`:

```bash
  LEAD_SID="4726bdf3-9c1e-4b7a-8d2f-5e6a7b8c9d0e"          # team session-4726bdf3 ⇒ prefix only
  mkdir -p "$T/acct2/projects/lead-proj"
  LTX="$T/acct2/projects/lead-proj/$LEAD_SID.jsonl"
```

Helpers:

```bash
# The 2026-10-10 cvf-docs shape: a member BUSY when its lead's request was sent. Timestamped records,
# last one a Bash tool_use with NO tool_result (killed mid-call); shutdown_request only in PROSE.
mk_busy_member_tx() { # $1=agentName
  printf '{"teamName":"session-4726bdf3","agentName":"%s","type":"user","timestamp":"2026-10-10T17:53:56.000Z","message":{"role":"user","content":"<teammate-message teammate_id=\\"team-lead\\">\\nYou are a teammate. Then wait for a shutdown_request.\\n</teammate-message>"}}\n' "$1" > "$TX"
  printf '{"teamName":"session-4726bdf3","agentName":"%s","type":"attachment","timestamp":"2026-10-10T17:53:57.000Z","attachment":{"type":"instructions","content":"If you receive a JSON message with `type: \\"shutdown_request\\"`, respond."}}\n' "$1" >> "$TX"
  printf '{"teamName":"session-4726bdf3","agentName":"%s","type":"user","timestamp":"2026-10-10T18:04:24.713Z","message":{"role":"user","content":[{"tool_use_id":"toolu_M1","type":"tool_result","content":"The file /w/hooks/lib/why-tier.sh has been updated successfully."}]}}\n' "$1" >> "$TX"
  printf '{"teamName":"session-4726bdf3","agentName":"%s","type":"assistant","timestamp":"2026-10-10T18:04:26.867Z","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_M2","name":"Bash","input":{"command":"cd /w && bash -n hooks/lib/why-tier.sh"}}]}}\n' "$1" >> "$TX"
}
# The LEAD's records, shaped as 247fdf36…jsonl:820/828 (no teamName/agentName; harness toolUseResult).
add_lead_shutdown() { # $1=member $2=result timestamp
  printf '{"type":"assistant","timestamp":"2026-10-10T18:04:25.438Z","sessionId":"%s","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_L1","name":"SendMessage","input":{"to":"%s","message":{"type":"shutdown_request","reason":"work merged"}}}]}}\n' "$LEAD_SID" "$1" >> "$LTX"
  printf '{"type":"user","timestamp":"%s","sessionId":"%s","toolUseResult":{"success":true,"message":"Shutdown request sent to %s. Request ID: shutdown-1791655466065@%s","request_id":"shutdown-1791655466065@%s","target":"%s"},"message":{"role":"user","content":[{"tool_use_id":"toolu_L1","type":"tool_result","content":[{"type":"text","text":"{\\"success\\":true,\\"request_id\\":\\"shutdown-1791655466065@%s\\",\\"target\\":\\"%s\\"}"}]}]}}\n' "$2" "$LEAD_SID" "$1" "$1" "$1" "$1" "$1" "$1" >> "$LTX"
}
# …and 842/843: TaskStop names the member only in its tool_use input; the result names the task id.
add_lead_taskstop() { # $1=member
  printf '{"type":"assistant","timestamp":"2026-10-10T18:04:40.623Z","sessionId":"%s","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_L2","name":"TaskStop","input":{"task_id":"%s"}}]}}\n' "$LEAD_SID" "$1" >> "$LTX"
  printf '{"type":"user","timestamp":"2026-10-10T18:04:50.929Z","sessionId":"%s","toolUseResult":{"message":"Successfully stopped task: t5ou0rn4u (docs)","task_id":"t5ou0rn4u","task_type":"in_process_teammate"},"message":{"role":"user","content":[{"tool_use_id":"toolu_L2","type":"tool_result","content":"{\\"message\\":\\"Successfully stopped task: t5ou0rn4u (docs)\\",\\"task_type\\":\\"in_process_teammate\\"}"}]}}\n' "$LEAD_SID" >> "$LTX"
}
```

### 2.3 The tests (assertions)

Feed the classified class and cause into the verdict, as the daemon does, so the paint assertion
fails on current code too and does not pass only because the test hard-codes the class:

```bash
@test "a BUSY member its lead shut down (request only in the LEAD's transcript, killed mid-call, exit 143) is RETIRED, and nobody is told to re-spawn it" {
  mk_busy_member_tx lt-wrap; add_lead_shutdown lt-wrap 2026-10-10T18:04:26.207Z; add_lead_taskstop lt-wrap
  export CC_ACCOUNT_BASES="$T/acct $T/acct2"
  run bash "$HOOK" --classify "$SID" ""                      # no close record: the members' real path
  [ "$(printf '%s' "$output" | cut -f1-2)" = "$(printf 'RECYCLE\tretired-teammate')" ]
  printf '{"pid":7002,"exit_code":143,"signal":"15","version":"2.1.284"}\n' > "$T/close/7002-100.json"
  run bash "$HOOK" --classify "$SID" 7002                    # arm 0: 143 must not read as a crash either
  [ "$(printf '%s' "$output" | cut -f1-2)" = "$(printf 'RECYCLE\tretired-teammate')" ]
  cls=$(printf '%s' "$output" | cut -f1); cause=$(printf '%s' "$output" | cut -f2)
  run verdict "$cls" "$cause" 143 15
  painted | grep -q 'RETIRED — teammate lt-wrap (session 74148f20) was shut down by its lead'
  ! painted | grep -q 'NOT A CLEAN EXIT' || false
  ! painted | grep -q 're-spawns members' || false
  ! painted | grep -q 'tell its lead' || false
  ! painted | grep -q -- '--resume' || false
  bash "$HOOK" --surface-death "$SID" 63977 "$cls" "$cause" 143 15 "$TX" >/dev/null
  [ ! -s "$PAGED" ] || { echo "a retired teammate was paged: $(cat "$PAGED")"; false; }
}

@test "CONTROL: the same busy member with NO lead-teardown evidence is still NOT A CLEAN EXIT" {
  mk_busy_member_tx lt-wrap
  export CC_ACCOUNT_BASES="$T/acct $T/acct2"                 # the lead's store is reachable, just empty
  run bash "$HOOK" --classify "$SID" ""
  [ "$(printf '%s' "$output" | cut -f1-2)" = "$(printf 'CRASH\tabrupt-unknown')" ]
  printf '{"pid":7003,"exit_code":143,"signal":"15","version":"2.1.284"}\n' > "$T/close/7003-100.json"
  run bash "$HOOK" --classify "$SID" 7003
  [ "$(printf '%s' "$output" | cut -f1-2)" = "$(printf 'CRASH\texternal-sigterm')" ]
  run verdict CRASH abrupt-unknown "" ""
  painted | grep -q 'NOT A CLEAN EXIT'
  painted | grep -q 'tell its lead (session 4726bdf3)'
  ! painted | grep -q 'RETIRED' || false
}

@test "lead evidence must be structural, for THIS member, and from THIS generation" {
  mk_busy_member_tx lt-wrap; export CC_ACCOUNT_BASES="$T/acct $T/acct2"
  # prose naming the request id, an unanswered SendMessage call, and a request to someone else
  printf '{"type":"assistant","timestamp":"2026-10-10T18:04:00.000Z","message":{"role":"assistant","content":[{"type":"text","text":"next: shutdown_request for lt-wrap, request_id shutdown-1@lt-wrap"}]}}\n' > "$LTX"
  printf '{"type":"assistant","timestamp":"2026-10-10T18:04:10.000Z","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_X","name":"SendMessage","input":{"to":"lt-wrap","message":{"type":"shutdown_request"}}}]}}\n' >> "$LTX"
  add_lead_shutdown someone-else 2026-10-10T18:04:26.207Z
  run bash "$HOOK" --classify "$SID" ""
  [ "$(printf '%s' "$output" | cut -f2)" != retired-teammate ]
  # a request to a PREVIOUS member of the same name (before this member's first record)
  : > "$LTX"; add_lead_shutdown lt-wrap 2026-10-10T17:40:00.000Z
  run bash "$HOOK" --classify "$SID" ""
  [ "$(printf '%s' "$output" | cut -f2)" != retired-teammate ]
}
```

Also keep existing test 6 (`:102`) unchanged. It is the second control: no lead store at all
(`CC_ACCOUNT_BASES=$T/acct`), the old fixture without timestamps, and it must still read CRASH.

### 2.4 Measured against current code

bats was refused on every attempt for roughly 25 minutes by the admission gate:
`cc-bats: REFUSED — 2 concurrent bats execution root(s) (ceiling CC_BATS_MAX_ROOTS=2) AND 1-min load/core at or above 2.0`.
The holders were pid 20158 (close-verdict-first, completion-assert.bats) and pid 87056
(lr-stranded-husk). I did not take the waiver, because it writes `~/.claude/state/bats-waivers.jsonl`.
So the prototype `proto.bats` (the three tests above, with the verdict call given the class
literally) was replayed by a plain-bash script that sources the same `setup()` and helpers and runs
the same assertions (`bash replay.sh proto.bats`):

```
## REGRESSION
   classify(no pid) => CRASH	abrupt-unknown
FAIL  classify no-record path = RECYCLE/retired-teammate
   classify(pid 7002, close 143) => CRASH	external-sigterm
FAIL  classify arm-0 143 path = RECYCLE/retired-teammate
PASS  painted RETIRED headline          (prototype hard-coded the class; §2.3 chains it, so this FAILS too)
PASS  no NOT A CLEAN EXIT               (same caveat)
FAIL  no re-spawns members              (the RETIRED body itself says it: hook :1471)
PASS  no tell its lead
## CONTROL
PASS  CRASH/abrupt-unknown
PASS  CRASH/external-sigterm
PASS  NOT A CLEAN EXIT
PASS  tell its lead (session 4726bdf3)
## GUARDS
PASS  prose/other-member not retired
PASS  previous-generation request not retired   (vacuous today: nothing reads the lead yet)
```

So the regression test fails today on classification at both the no-record and the arm-0 path. It
also fails on the `re-spawns members` assertion even when the class is right, which means the fix
must also reword `:1471` (§4). The control passes today, as it must.

## 3. (c) Fix designs

The criteria below are the brief's. "Lines" are estimates from reading the code, not a diff.

### D1. Read the LEAD's transcript inside `teammate_facts`

Mechanism. `teammate_facts` (`:340-381`) already knows `name` and `team`, from `LEAD_AGENT_ID` or
the member's records. Two new steps go into the same Python process:

1. Resolve the lead transcript. Prefer `<LEAD_CFG>/teams/<team>/config.json` `leadSessionId`. Fall
   back to the sid8 from `team` matching `session-([0-9a-f]{8})`, then glob
   `<base>/projects/*/<sid>*.jsonl` over `CC_ACCOUNT_BASES` (pass the bases as argv).
2. Stream it with a substring prefilter (`shutdown-` / `TaskStop` / `in_process_teammate`). Accept a
   record only if all of these hold: `type=="user"`, no `teamName`/`agentName`, a dict
   `toolUseResult` with `success is True`, `request_id` starting with `shutdown-` and ending with
   `@<name>`, `target == <name>`, and `timestamp >=` the member's first record timestamp (the
   generation guard). Optionally also accept a successful `in_process_teammate` TaskStop whose
   `tool_use_id` joins to a `TaskStop` tool_use with `input.task_id` in `{name, name@team}`.

SHUTDOWN becomes `self_request or lead_request`. Both classify arms (`:556`, `:584`) call
`retired_teammate`, so neither arm changes.

- **Correctness on this incident:** yes. The prototype parse returns exactly line 828 (and 843 via
  the join) on the real file, and `team=session-247fdf36` resolves.
- **Genuine-crash preservation:** a member with no lead request still reads CRASH (control). Jetsam
  still outranks (arm 0 guard `:556`; the no-record path checks jetsam at `:578` before 1.4).
  Residual: the lead sends shutdown_request, the member refuses and works on, then really crashes.
  That reads RETIRED. The member-transcript arm already has the same residual today: `teammate_facts`
  never checks a `shutdown_response approve:false`. An optional recency cap (request within 30 min of
  death, matching the teardown-marker window) bounds it.
- **Forgeability:** prose cannot trigger it (16 prose lines vs 1 structural hit, measured). A
  `toolUseResult` is written by the harness on a real SendMessage call, so a model reaches it only by
  actually asking the member to shut down, or by hand-writing a JSONL line into another session's
  transcript. The second is the same local-write trust that markers and the member transcript
  already rely on. The team binding comes from the lead-sid resolution, so a request inside some
  other lead's transcript is never read.
- **Timing:** the evidence is written before the kill (§1.2) and so is present at classify time,
  well before the ~3-minute paint. It does not need the team dir to survive: TeamDelete only loses
  the config resolver, and the sid8 glob remains (475/476 derivable).
- **Blast radius:** `hooks/lead-crash-watchdog.sh` only. About 30-40 lines of Python inside
  `teammate_facts`, plus 1-2 lines of bash to pass `CC_ACCOUNT_BASES`/`LEAD_CFG`, plus the renderer
  wording (§4). One test file, either appended to `watchdog-retired-teammate.bats` or new (~70 lines).
  No new store, hook or settings change. Seal check ("Nth source un-seals old fixtures",
  `.claude/rules/agent-operating-lessons-situational.md:166`): the existing fixtures set
  `CC_ACCOUNT_BASES=$T/acct` and `CFG=/x/.claude-tertiary`, so the new source resolves to nothing
  there, provided the implementation never falls back to live `$HOME/.claude*` when
  `CC_ACCOUNT_BASES` is set.
- **Does not cover:** a lead that kills with **neither** a shutdown_request nor a TaskStop. That stays
  CRASH, which is the safe direction.

### D2. Read the team inbox and config

- **Correctness:** **no.** Measured (§1.3): the member's inbox is `[]` and was drained at 18:04:26Z
  into the busy process's memory. The config no longer lists the member, and its removal time cannot
  be recovered.
- **Genuine-crash preservation:** poor if "member missing from config" were used as the signal. It is
  absence evidence, and it is not established whether the harness also removes a member that died on
  its own (not measured).
- **Forgeability:** a plain JSON file any process rewrites, and the harness rewrites it continuously.
- **Timing:** races the harness's own edits.
- **Verdict:** rejected as evidence. Keep `config.json` `leadSessionId` only as D1's lead-sid
  resolver, and `members[].cwd` for the work line (§4).

### D3. A lead-called helper writes a pid-keyed `mode:teammate-retire` marker

- **Correctness:** only if the lead calls it. This lead ran a raw `kill -TERM 23017` (line 857), so a
  helper the model has to remember would not have fired. A harness-driven variant (a PostToolUse hook
  on SendMessage `shutdown_request`) removes that dependency but adds a hook registration in
  `settings.json`. It would also only duplicate a fact the lead transcript already holds durably.
- **Reader gap, from reading the code:** a pid-keyed marker is read **only** by `retired_by_desk`
  (`:307-321`), and only from arm 0 (`:549`), which runs only when a close record exists. Members
  launch without `cc-close-attrib` (no record for 23017, measured), so on their real path **nothing
  reads a pid key**. Meanwhile arm 1.5's sid key (`:599`) accepts **any** fresh `$sid.json` without
  checking `mode`. A sid-keyed teammate marker would therefore classify `deliberate-teardown` and
  paint "✅ CLOSED CLEANLY … exited on its own", plus the teammate's "tell its lead" line. That is the
  wrong headline. So D3 also needs new reads in classify_death's no-record path and a new renderer
  case.
- **Mapping problem:** the lead knows a name. Team config gives `tmuxPaneId`, but neither sid nor
  pid, so the helper has to go pane → registry → sid → pid. That is the multi-hop address resolution
  `marker_owns_sid` exists to police.
- **Forgeability:** the same as the existing marker store (`mode` is a string anyone can write).
- **Timing:** fine if it is written before the kill.
- **Blast radius:** a new `bin/` helper (or hook plus a `settings.json` entry), `classify_death` (new
  arm), `retired_by_desk` or a sibling, the renderer, tests for each, and a behaviour/docs change for
  every lead. **Largest.**
- **Verdict:** rejected as primary. It could later complement D1 for "kill without any message", but
  only the harness-driven variant would fire in practice.

### D4. Combinations

- **D1 + TaskStop join** (recommended): this covers leads that skip SendMessage and only TaskStop. It
  costs about 10 more Python lines (keep a tool_use_id → task_id map, join on the result). Measured
  on the real file: one join hit.
- **D1 + config resolver**: `leadSessionId` first, then the sid8 glob. This covers the 1/476
  custom-named team (`bsm-port`) while its dir exists.
- **D1 + D3**: two sources for one fact, and the marker path still needs the no-record-arm and
  renderer work. Not worth it now.

### Recommendation

**D1 + TaskStop join + config resolver + generation guard, plus the §4 renderer fixes. Conviction 85%.**
The remaining 15% covers three unknowns: whether `toolUseResult.request_id`/`target` keep this shape
across CC versions (seen in 3/3 shutdown requests in this one transcript, at lines 705, 828 and
1011, but not surveyed fleet-wide in this slot); whether multi-account teams ever put the lead in a
base outside `CC_ACCOUNT_BASES` (default: the 4 roots; `.claude-next` is not in the default list,
`:149`); and the shared refusal residual above.

## 4. The renderer: is the teammate advice wrong in itself?

The incident banner, reproduced on current code (`--pane-verdict 5b813b72… 23017 CRASH abrupt-unknown`,
with `CC_PANE_VERDICT_CWD=…/close-verdict-first`, `AGENT_ID=cvf-docs@session-247fdf36`, `PANE=200`,
`CC_PANE_VERDICT_CLOSE=off` and a temp tty):

```
⛔ NOT A CLEAN EXIT — Claude session 5b813b72 was KILLED here (…).
   cause: abrupt-unknown. … ignore it — a teammate is not resumable outside its team.
   work in /Users/chrisren/Development/.worktrees/close-verdict-first: unlanded:16 · its last close verdict: no
▶ Teammate cvf-docs is not resumable: tell its lead (session 247fdf36) — the lead re-spawns members
▶ Or triage first:  cc-husk-sweep --pane 200
```

1. **CRASH with `tm_is==1` (`:1459-1465`).** For a *genuine* crash, "tell its lead … the lead
   re-spawns members" is directionally right: the member is not resumable outside its team, and the
   lead owns re-spawning. It is not wrong in itself. It is incomplete in two ways that matter:
   - **The work line reads the wrong tree.** `work=$(pane_work_state "$LEAD_CWD")` (`:1441`) uses the
     member's launch cwd, which for members is the **lead's** worktree (measured: transcript cwd =
     close-verdict-first). The real work sat in `cvf-docs` with 3 uncommitted files. That banner said
     `unlanded:16` about someone else's tree, and nothing about the 3 dirty files. A genuine teammate
     crash should name **the member's worktree and its dirty count**. Sources, in order: team
     `config.json` `members[].cwd` while the team exists, else the `cd <dir> &&` prefix of the
     member's last Bash tool_use. That is a heuristic; label it as such.
   - **The lead may already be gone.** If the lead itself died or ended, "tell its lead" has no one to
     receive it. The banner's `cc-husk-sweep --pane` line is then the only workable advice. Suggested:
     "▶ Teammate X crashed: its lead (session Y) re-spawns members; its uncommitted work is in <dir>
     (dirty:N), so the lead should collect it before re-spawning."
2. **RECYCLE:retired-teammate (`:1467-1471`).** "…its work went to the lead" and "It is not
   resumable — its lead re-spawns members." are both wrong for a retirement. Nothing is re-spawned;
   the lead ended the member on purpose. The incident also shows that for a **busy** retirement
   "its work went to the lead" is false: the 3 edits were made at 18:04:21-24Z, after the merged
   `eec712aee`. Fix: drop "re-spawns members" from the retired body (this is what makes the
   regression's `! grep 're-spawns members'` pass). When the evidence came from the lead's transcript
   (expose a 5th field in `teammate_facts`, e.g. `SOURCE=self|lead`), say "stopped by its lead
   mid-work (its shutdown_request at <ts> was never delivered — it was busy)" plus the member's
   worktree dirty count. **Caution:** adding a 5th field breaks `retired_teammate`'s
   `${f##*$'\t'}` (`:385`), which reads the *last* field. Change it to read field 4 explicitly.
3. **The death page (`:1179`, `:1199`)** never fires for RECYCLE, but `--surface-death` can build it.
   `:1199` repeats "its lead re-spawns members" for `retired-teammate`, so reword it the same way, or
   the regression's `--surface-death` content will contradict the banner. `:1179` "its work already
   handed to the lead" has the same busy-retirement caveat.

Side note, not fixed by any design here: `cc-pane-close` gate 4 (`bin/cc-pane-close:209-212`)
checks the transcript cwd. For members that is the lead's tree, so the auto-close after a RETIRED
verdict never checks the member's real worktree. Closing the pane does not delete those files, but
nothing points at them either.

## 5. Deviations and limits

- bats did not run (the admission gate refused for about 25 min, and the waiver was not taken because
  it writes a state file). The FAIL/PASS table is from a plain-bash replay of the same fixture and
  assertions. Re-run `bats` on the §2.3 tests before trusting the bats form.
- Scratch files lived only in `/var/folders/…/tmp.zcKwBjViem/` (`proto.bats`, `replay.sh`) and other
  `mktemp -d` dirs. None is in the repo.
- Not measured: the fleet-wide stability of the `toolUseResult` shutdown shape across CC versions;
  whether the harness removes a crashed (non-retired) member from `config.json`; and the member-cwd
  heuristic's hit rate.
