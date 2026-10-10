# 04 — contract and skill: should the escalation step write its own marker?

Slot: contract-and-skill (QUESTION 4). Read-only investigation, 2026-10-10. Runtime of every process
involved: Claude Code **2.1.293** (`"version":"2.1.293"` in the cvf-docs transcript records; lead argv
`/Users/chrisren/.claude-293/.../claude.exe`). Unless a line says *estimated*, every number below was
measured by the command or file:line it cites.

## Answer in one paragraph

Yes. The escalation step should go through a small helper that the lead calls instead of a bare
`kill -TERM`. Call it `bin/cc-teammate-retire`. It writes a **pid-keyed** marker with its own mode,
then TERMs the member and KILLs it after a grace period. Three findings shape that design. **(1)** A
`shutdown_request` reaches a pane member only at a **turn boundary**: the member's inbox poller
submits it as a user record only when the member is not loading. A busy member therefore cannot
receive it until its turn ends, and cvf-docs never got there: it was killed while a tool call was
still running. **(2)** On 2.1.293, `TaskStop` on an `in_process_teammate` never signals the
member process. It aborts the *lead's own* task record and removes the member row. It also starts a
pane teardown with a 10 s timeout, and if that teardown fails the vendor only logs a warning. Here the
pane close was refused by the kitty shim's composer guard, so the process lived. **(3)** The marker
must **not** be sid-keyed in a mode the reader does not know yet. Arm 1.5 accepts *any* fresh
`<sid>.json` whatever its mode. Under the current renderer that paints `✅ CLOSED CLEANLY … exited on
its own` over a member that was killed mid-work with 3 uncommitted files (measured below). The helper
must also gate on the **member's own** worktree. The registry's and the config's `cwd` both name the
lead's worktree, not cvf-docs. When that worktree is dirty, or the member is mid-tool, the helper
should refuse by default. When the lead overrides that, it should checkpoint first and record a
verdict that is distinct from a clean retirement. Finally, the skill's "idle members ignore
`shutdown_request`" (0/4) is stale. The 2026-09-19 W5 probe overturned it, and today's sibling
cvf-readout shows the opposite. It also does not describe this incident, because cvf-docs was
**busy**, not idle.

---

## (a) How a `shutdown_request` is delivered, and why busy and idle members can miss it

### The delivery path (pane member)

1. The lead's `SendMessage{type:"shutdown_request"}` writes into the member's inbox file
   `<cfg>/teams/<team>/inboxes/<member>.json`. Lead transcript `247fdf36…jsonl` record 820 is the tool_use at
   18:04:25.438Z. Record 828 is the result at 18:04:26.207Z:
   `"Shutdown request sent to cvf-docs. Request ID: shutdown-1791655466065@cvf-docs"`.
2. The member's `InboxPoller` checks at 1 Hz. It submits unread messages as a prompt **only when the member
   is not loading and no dialog is up** (`docs/research/SUBAGENT_LIFECYCLE_ROOT_CAUSE_2026-09-19.md:148`).
   The message then becomes a `type:"user"` record whose content is
   `<teammate-message teammate_id="team-lead">{"type":"shutdown_request",…}</teammate-message>` followed by
   the vendor's in-band text `This is a shutdown request. To approve it, call SendMessage …`. That string
   is in the 2.1.293 binary: an mmap read found `This is a shutdown request.` at offset 79735502.
3. Several queued messages are **batched into one user record** at the next boundary. Today's control is
   sibling cvf-readout (`f959926c…jsonl` record 179, 18:00:46.692Z). One record carries both the lead's
   relay update and `{"type":"shutdown_request","requestId":"shutdown-1791655236738@cvf-readout",…}`,
   10 s after its `end_turn` (record 175, 18:00:34.906Z).
4. Approval is model-mediated: `SendMessage{shutdown_response, approve:true}`. The vendor's own tool text,
   captured in the member's `deferred_tools_record`, says *"Approving shutdown terminates your process"*
   (cvf-docs transcript record 322). On the idle path the runtime can also end the member with **no
   assistant turn**. cvf-readout's records 180+ are end-of-session rows only (`last-prompt`, `ai-title`,
   `mode`…), the same shape as W5 P2 (lifecycle doc `:272-281`).

### Why cvf-docs missed it: it was BUSY

Member transcript `5b813b72…jsonl`, measured with a python tail dump:

| time (Z) | record | event |
|---|---|---|
| 18:03:24.595 | 323 | `SendMessage` "cvf-docs DONE: commit eec712aee …" |
| 18:03:30.453 | 332 | `end_turn` |
| 18:03:35.913 | 333 | `hook_cancelled` Stop `completion-assert.sh`, `timedOut:true`, 5108 ms |
| 18:03:41.021 | 335 | `hook_cancelled` TeammateIdle `teammate-auto-shutdown.sh`, `timedOut:true`, 5088 ms |
| 18:03:41.102 | (lead side) | `idle_notification` stamped by cvf-docs (lead record 815) |
| 18:03:41.243 | 337 | **user record: the lead's own relay update ("check your edits against REPORT")**. The member wakes |
| 18:03:43 → 18:04:24 | 338-… | 2 Bash reads, then Edits to CLAUDE.rules.slim…, CLAUDE.global.md ×3, hooks/lib/why-tier.sh |
| 18:04:26.867 | last assistant record | Bash tool_use (`grep -c … && bash -n … && shellcheck …`), **no tool_result ever** |
| (after) | tail | `bridge-session`, `cost-state`, `last-prompt`, `cost-state` end-of-session rows |

The request was written at 18:04:26.2Z. At that moment the member was mid-turn, and 0.7 s later it began
a tool call that never returned. No turn boundary came before the kill, so the poller never submitted the
request. `grep -c "teammate-message"` on the transcript returns 2 (records 9 and 337), and neither holds
`"type":"shutdown_request"`. The 5 bare `shutdown_request` hits are prose in the brief/instructions
(records 10, 88, 129, 357) and the vendor tool text (record 322). These are exactly what
`teammate_facts` excludes (`hooks/lead-crash-watchdog.sh:331-334`).

**Where the lead's "idle" came from:** lead record 815 (read at 18:04:16.915Z) batched the stale DONE
report with an `idle_notification` stamped **18:03:41.102Z**. The member's next user record, the lead's
own relay, landed **141 ms later** (18:03:41.243Z) and restarted it. At 18:04:40.382Z the lead wrote
"`cvf-docs` is idle and its work is harvested". That notification was 59 s old and had already been
overtaken by the lead's own message. This is vendor contract §1 exactly (`skills/agent-teams/SKILL.md:384-392`):
an idle notification fires at every turn boundary and says nothing about the present.

### Why IDLE members can also miss it (or look as if they did)

- **The Stop pass never finishes.** If a settings `Stop` hook blocks, the pass returns before the
  `TeammateIdle` block. The member then never goes idle and sends no idle notification. To the lead it
  looks as if the request was ignored, when in fact the member never went idle (lifecycle doc `:153`,
  `:275-279`). Today's load variant: cvf-docs' Stop and TeammateIdle hooks both **timed out at 5 s**
  (records 333, 335). Load at write time was `load averages: 307.23 311.79 252.26` (`uptime`).
- **A dialog is up.** The poller does not submit while a dialog or permission modal is showing (`:148`).
  W5 left the modal arm unexercised (`:280-281`).
- **A prose acknowledgement.** "Shutting down" with no structured `shutdown_response` keeps the process
  alive (22/25, `:211`).
- **A resumed lead.** Approval reaches the lead, but a resumed lead's roster is empty, so nobody closes
  the pane (`scripts/teammate-orphan-pane-close.sh:6-14`). The process is gone; only the pane survives.

### The skill text is stale on this point, and does not describe this incident

- `SKILL.md:360-363` (table: idle **0/4**) and `SKILL.md:444` ("An idle agent will never answer the
  request") rest on the 2026-08-26 episode. W5 P2 (lifecycle doc `:272-279`) overturned it: *"An idle
  named teammate consumed a structured `shutdown_request` and was gone … inside 10 s … The 2026-08-26
  'idle 0/4' episode was therefore environment, not vendor"*. The skill never took that correction:
  `grep -n "W5\|environment, not vendor\|without a model turn" skills/agent-teams/SKILL.md` returns nothing.
- Today's own controls agree with W5, not with the skill. cvf-readout (idle) was retired by the request
  with no model turn. cvf-hooks (`d2a47de0…`, idle since `end_turn` 18:10:36.979Z) received it at
  18:12:06.258Z (record 658) and exited. The watchdog classified both `RECYCLE cause=retired-teammate`
  (`~/.claude/logs/lead-crash-watchdog.log:59398,59408`).
- cvf-docs was **busy**. The skill's own table says busy members are the case that succeeds (`:362`,
  3/3), *given time*. The lead escalated to `TaskStop` **14 s** after the request (18:04:26.2 →
  18:04:40.6), against the skill's own ~60 s (`:443`). The skill text that primes a fast escalation
  ("idle ⇒ will never answer", plus a stale idle notification) is part of this incident's cause.

## (b) What `TaskStop` does and does not do for an `in_process_teammate` in pane mode

Read from the 2.1.293 binary (mmap read at offset 200156338, function `Rln`, exported as the
`InProcessTeammateTask.kill`):

```js
s.update(a,(e)=>{ … n=e.paneTeardown, e.abortController?.abort(), … return {...e,status:"killed",
  pendingUserMessages:[], abortController:void 0, paneTeardown:void 0, …}});
let c = n ? Nt(n(), T /*1e4*/, `pane teardown did not settle within ${T}ms`).then((e)=>{ if(!e) t(
  `[killInProcessTeammate] pane teardown for ${a} reported failure — the backend could not find/kill the
  pane; its separate \`claude --agent-id\` process may still be running`,{level:"warn"}) … },
  (e)=>(t(`… did not complete cleanly … Not blocking the stop result on it; the backend kill continues in
  the background and the separate \`claude --agent-id\` process may still be running`…),!1))
```

What it **does**:
- aborts the **lead-side** task record's AbortController. That object lives in the lead process; it does
  not cross into the member's process;
- marks the record `killed` and clears `pendingUserMessages`;
- removes the member from the lead's in-memory `teamContext.teammates`;
- removes the member row from the team file (`wKt(team, agentId, …)`), which is why `config.json` now
  lists only `team-lead` (measured with `jq` on `~/.claude-quaternary/teams/session-247fdf36/config.json`);
- calls `paneTeardown` (backend `killPane`) under a **10 s** timeout.

What it **does not** do:
- send any signal to the member process, or any message to its model;
- wait for or verify the process's death. A teardown that fails or times out is only a `warn` log line,
  and the tool still returns success. Lead record 843 (18:04:50.929Z):
  `{"message":"Successfully stopped task: t5ou0rn4u …","task_type":"in_process_teammate"}`, 10.3 s after
  the call (record 842, 18:04:40.623Z), which matches the 10 s timeout.

**Why the pane close failed here (inferred from a measured artifact):** the kitty shim's composer guard
writes its "preserve first" snapshot only on its refusal path (`bin/it2-kitty:1421-1446`, exit 67). On
disk is a **0-byte** `~/.claude/logs/composer-snapshots/20261010T180451Z-win200.txt`, timestamped
18:04:51Z, 0.1 s after `TaskStop` returned. Window 200 is cvf-docs' pane (`pane-spawns.jsonl:4609`,
`"pane":"200"`). So the vendor's background `killPane` reached the guard, the guard found the busy
member's composer state not in `EMPTY|NO-TUI|AGENT-PANE|AGENT-NO-BOX|DEAD-PANE` (`:1423`), and it refused.
The window, and the process it would have SIGHUP'd, both survived. The lead's ps check at 18:04:55
confirmed it (record 853: `23017 checked`). Then came `kill -TERM 23017` at 18:04:59.336Z (record 857).
At 18:05:07 the process was still `S+` (record 862). It exited 143 later. The transcript's mtime is 13:06
local, i.e. 18:06Z (`ls -la`). The watchdog paged at 13:07:03 local and painted at 13:08:04 local
(`lead-crash-watchdog.log:59403,59405`).

Consequence for ordering: **a successful `TaskStop` pane close is itself a marker-less death.** If the
guard had allowed the close, SIGHUP would have killed the member with no marker and no delivered
request. That ends at `abrupt-unknown` just the same. Any helper must therefore run **before**
`TaskStop`. `TaskStop` then does the vendor bookkeeping (roster, task record, member row) against an
already-dead member, whose pane the guard does allow (`DEAD-PANE`/`NO-TUI`).

## (c) Is `bin/cc-teammate-retire` (pid-keyed marker, distinct mode, TERM then KILL) the right shape?

**Yes, with four corrections to the brief's sketch.**

### Correction 1: key it on the pid, not the sid, until the reader learns the mode

Replays of `classify_death` through the `--classify` entrypoint (`hooks/lead-crash-watchdog.sh:1597-1601`).
Every store was isolated in a mktemp dir (`CC_TEARDOWN_DIR`, `CC_REGISTRY_DIR`, `CC_CLOSE_RECORDS_DIR`,
`CC_HANDOFF_LOG`, `CC_JETSAM_DIRS`), with `LEAD_AGENT_ID=cvf-docs@session-247fdf36`, death epoch 18:06:00Z:

| cell | stores | result |
|---|---|---|
| A | none (the real incident) | `CRASH abrupt-unknown 1159 390` |
| B | `23017.json` `{"key_kind":"pid",…,"mode":"teammate-retire"}` | `CRASH abrupt-unknown` (inert) |
| C | B + `<sid>.json` `{"key_kind":"sid",…,"mode":"teammate-retire"}` | `RECYCLE deliberate-teardown` |
| D | `<sid>.json` whose body names a **different** sid | `RECYCLE deliberate-teardown` |
| E | close-record exit 143 + pid key teammate-retire | `CRASH external-sigterm` |

Cells C and D happen because arm 1.5's sid check is filename-only, with no mode check and no
`marker_owns_sid` (`:594-596`). The pid key is read only by `retired_by_desk`, which runs only inside
arm 0 (a close-record exists) and only for `"mode":"teardown"` (`:307-321`, `:549`). Members launch
without `cc-close-attrib`, so a teammate-retire pid key is **inert under every current arm** (B, E).

Then the render. `--pane-verdict` was run with `HOME` pointed at a mktemp dir (so the log and paint went
nowhere) and `CC_PANE_VERDICT_TTY=` (no paint). For `RECYCLE deliberate-teardown` on this transcript it
prints:

```
✅ CLOSED CLEANLY — Claude session 5b813b72 exited on its own (reason: -); nothing relaunched here
   work in /Users/chrisren/Development/.worktrees/close-verdict-first: unlanded:16 · its last close verdict: no
```

"Exited on its own" is false, because its lead killed it. The `work in` line also reads the **lead's**
worktree. `~/.claude/cc-registry/200.json` has `"cwd": "/Users/chrisren/Development/.worktrees/close-verdict-first"`,
because members are spawned in the lead's cwd and only `cd` into their worktree. Re-run with
`CC_PANE_VERDICT_CWD=…/cvf-docs`, the same line says `dirty:3`. The existing `RECYCLE:retired-teammate`
banner would be worse: *"its work went to the lead … This pane holds nothing: close this pane"* over 3
uncommitted files (measured, same harness).

So a sid-keyed marker shipped before its reader arm turns a loud wrong verdict (a false crash page)
into a **silent** wrong one. The reader's own header ranks the silent case as strictly worse
(`:256-258`). The rule that follows: **write the pid key only** (plus the pane key, if wanted, with the
same mode), and land the reader arm in the same commit. `gc_teardown_marker` already collects `<pid>.json`
(`:697-698`). The store currently holds 3,790 files, of which 669 are `teammate-idle` and 175 `teardown`
(`cat …/*.json | grep -o '"mode":"[^"]*"' | sort | uniq -c`).

### Correction 2: the reader arm that pairs with it

Add a new arm after jetsam and before 1.4, keyed on `<pid>.json`. It should fire only if all of these
hold:
- `"mode":"teammate-retire"`;
- `marker_owns_sid` holds against the dead sid. The marker must therefore always carry the member sid
  (see resolution below), so the empty-sid fail-open never applies to this mode;
- the marker's `pid` equals the dead pid;
- the marker is fresh. Use a tighter window than 30 min, for example 10 min (*estimated*: TERM grace +
  KILL + exit under load). Today TERM-to-exit took ~1 min, measured from the 18:04:59 kill to the 18:06
  transcript mtime;
- the transcript's `teamName`/`agentName` match the marker's `agent_id` (the same fields `teammate_facts` reads).

Jetsam still outranks it, as it does for 1.5/1.6. The arm should yield **two different causes**,
chosen from facts the helper recorded at kill time:
- `RECYCLE retired-by-lead`: the tree was clean or all of it reached the lead, and no tool was in flight.
  Banner: "✅ RETIRED — teammate X was stopped by its lead after shutdown_request went unanswered".
- `STOPPED-MID-WORK lead-killed-wip` (not ✅, not a crash): the marker says `dirty>0` or `busy=1`.
  The banner names the worktree, the dirty count, the checkpoint ref, and "tell its lead". Its page
  goes to the lead, not to the desk: no `cc-husk-sweep --resume`, because a teammate is not resumable
  (`:1450-1456`).

### Correction 3: resolve the member from argv (it survives `TaskStop`), not from the config row

`TaskStop` deletes the config row (above), so the helper must not depend on it. Resolution, reusing the
proven rules in `bin/cc-teardown resolve_assignee` (`:443-519`):

1. **Caller = lead.** `CLAUDE_CODE_SESSION_ID` and `CLAUDE_PID` are exported into the Bash tool's
   environment on 2.1.293 (measured with `env | grep ^CLAUDE` in this session). Require all of:
   `CLAUDE_PID` is an ancestor of the helper's own pid (walk `ps -o ppid=`), and its registry row, if any,
   carries that sid. The lead's row exists: `~/.claude/cc-registry/195.json` has `pid 40930,
   session_id 247fdf36…`.
2. **Target pid.** Scan `ps -axww -o pid=,args=` and keep rows where argv[0]'s basename is exactly
   `claude.exe`, a **real** `--agent-id` token equals `<name>@session-<caller-sid8>` exactly, and a real
   `--parent-session-id` token equals the caller's full sid. All three facts appear in 23017's argv (lead
   record 838). Exactly one match is allowed; 0 or ≥2 means refuse. A substring match is never enough:
   `cc-teardown:445-449` records a prose argument containing `--agent-id <name>@session-…` that would have
   been adopted and killed.
3. **Pin identity.** Capture `lstart` and re-check it before every signal, because of pid recycling
   (`cc-teardown:891-899`, `cc-respawn start_is_same`).
4. **Member sid.** Members have no registry row (134/134 per `cc-teardown:423-426`). Read it from the
   member's own watchdog registration: `~/.claude/watchdog/<sid>.pid` contains the member's pid
   (`lead-crash-watchdog.sh:1673`). That same log line names the teammate:
   `registered session=5b813b72… pid=23017 … teammate=cvf-docs@session-247fdf36`
   (`lead-crash-watchdog.log:59393`). Cross-check it against the transcript's `agentName`/`teamName`.
   If the sid cannot be resolved, refuse rather than write an empty-sid marker.
5. **Team config.** If the row still exists, require `leadSessionId == caller sid`, and capture
   `tmuxPaneId` for the later pane close. Otherwise use the pane from the registration line.

### Correction 4: when to write, and how to retract

Copy `cc-teardown`'s discipline (`:883-889`): write the marker **after every gate passes, as the
statement right before the first signal**. A refuse or defer therefore leaves no marker that could mask
a real crash of a live member. Then: TERM, poll with `kill -0` plus lstart, then KILL after grace. If
the process outlives KILL, or the helper aborts after writing, **retract** the marker, following
`teammate-auto-shutdown.sh retract_teardown_marker` (`:269-279`). Then close the pane by its id (it now
holds a dead pane, which the guard allows), verify, and tell the lead to `TaskStop` for bookkeeping.
Exit codes should follow `cc-teardown`: 0 retired and verified · 2 usage/refusal · 5 still alive · 6
indeterminate. Every branch should write a record.

Marker body (one JSON line, pid-keyed file `<pid>.json`):
`{"key_kind":"pid","mode":"teammate-retire","pid":"23017","sid":"5b813b72-…","agent_id":"cvf-docs@session-247fdf36","lead_sid":"247fdf36-…","pane":"200","worktree":"/…/cvf-docs","dirty":3,"busy":1,"checkpoint":"refs/checkpoints/cvf-docs/<ts>","request_id":"shutdown-…","ts":"…"}`

### Guards against absolving a genuine crash, summarised

| guard | stops |
|---|---|
| marker written only at the moment of the signal, and retracted on failure | a stale marker covering a later real crash of a member that is still alive |
| pid key + `marker_owns_sid` + `pid` field equality + lstart pin | pid reuse, and a marker written about another session |
| caller sid == argv `--parent-session-id` == agent-id suffix (== config `leadSessionId` when present), with `CLAUDE_PID` an ancestor | a session that is not the member's lead "retiring" someone else's member, or any member at all |
| exact token match on argv[0]=`claude.exe` + real `--agent-id` | prose argv adoption (`cc-teardown:445-449`) |
| 10-min freshness, and jetsam outranks | an OOM or a much later death being read as the retirement |
| mode `teammate-retire` is its own discriminator (never `teardown`) | `retired_by_desk`'s banner "its work was landed before the retirement" (`:1466-1471`) claiming custody this helper never verified |

## (d) Should it refuse or warn when the member's worktree is dirty?

**It should refuse by default and checkpoint when overridden. Busy-and-dirty is a different verdict,
not a variant of clean retirement.**

- Measured state: `git -C ~/Development/.worktrees/cvf-docs status --short` shows
  ` M CLAUDE.global.md` / ` M CLAUDE.rules.slim.10-session-close.md` / ` M hooks/lib/why-tier.sh`, and
  `diff --stat` shows `3 files changed, 13 insertions(+), 11 deletions(-)` on top of `eec712aee`. The
  lead merged `eec712aee` at 18:04:24 (lead record 819-821). Those 3 edits were made **after** that
  commit, in response to the lead's own 18:03:41 relay. They are in no commit and in no checkpoint.
  `teammate-checkpoint.log` at 13:04:21/37/50 local says
  `no checkpoint needed for …/close-verdict-first — tree clean`, i.e. it gated on the lead's tree.
  `teammate-lifecycle.log` has no cvf-docs line at all, because the TeammateIdle backstop timed out
  (record 335).
- Resolve the worktree by name from git, the way `teammate-auto-shutdown.sh resolve_by_worktree_name`
  does (`:861-912`). The registry cwd and the config cwd are the lead's tree (above), so a gate that
  reads them would have said "clean" here.
- Gates, in this order:
  1. **busy**: the member transcript's last assistant record is a tool_use with no tool_result, or it is
     younger than the poll window. Refuse, printing "member is mid-turn; a shutdown_request is delivered
     at its next turn boundary; wait (skill: ~60 s) or pass `--busy-ok`".
  2. **request delivered?**: report whether the transcript holds the structured request, using the same
     predicate as `teammate_facts`. If it was delivered and is still unanswered after N s, it is a
     refusal-to-approve case. If it was not delivered, the member is still busy (gate 1) or blocked (a
     dialog, or a hung Stop pass).
  3. **dirty**: list the member worktree's modified and untracked files, plus commits not reachable from
     the lead's HEAD. Refuse unless `--wip-ok`. With `--wip-ok`, **checkpoint first** using the git
     plumbing `cc-respawn prepare` already uses (`bin/cc-respawn:141-157`: refs/checkpoints + refs/wip,
     refusing if the checkpoint fails). Record the `dirty` count and the `checkpoint` ref in the marker,
     so the reader paints `lead-killed-wip` with the ref instead of ✅.
- Why refuse rather than warn: the lead's stated premise ("idle and its work is harvested", record 841)
  was false on both counts, and a warning in a Bash result is easy to read past. A refusal costs one
  re-run with a flag, while a wrong kill destroys work. Skill Protocol step 6 then says
  `git worktree remove` (`SKILL.md:453`). git refuses a dirty tree without `--force`, but the protocol
  gives no dirty check of its own.

---

## Concerns and deviations

- The 2.1.293 `TaskStop` source is a minified-bundle read at one offset. Names like `Rln`, `wKt` and
  `Nt` are minifier output. The behaviour (abort, status killed, roster removal, member-row removal,
  10 s pane teardown, warn-only on failure) is stated in the bundle's own strings.
- "The composer guard refused TaskStop's close" is **inferred** from the 0-byte snapshot's name, time
  and code path. The shim's stderr went to the vendor and was discarded, and no rc-67 line exists in any
  log (`grep -l "13:04:[4-5]"` over `~/.claude/logs` found only bash/checkpoint/census logs).
- The 10-min freshness window is an estimate, not a measurement.
- Read-only: no tracked file was edited. The only writes were this file and two mktemp dirs used as
  isolated marker/registry/HOME stores for the replays
  (`/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/tmp.p9tDpl5LqG`).
