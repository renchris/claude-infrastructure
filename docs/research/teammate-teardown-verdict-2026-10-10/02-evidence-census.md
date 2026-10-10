# 02 — Evidence census: what durable proof of a LEAD-ORDERED teardown exists for cvf-docs

Slot: evidence-census · Question 2 · read-only investigation, 2026-10-10.
All times are UTC. Local log stamps (CDT, −0500) are converted and labelled. Every number below is
**measured** (the command or file:line is named) unless it says **estimated**.

## Answer first

The only durable, hard-to-forge, **lead-authored** evidence on disk is **the lead's own transcript**.
It holds three tool calls with vendor-written results: the `SendMessage` shutdown_request, the
`TaskStop`, and the `kill -TERM 23017`. All three landed **2–2.6 minutes before** the death was
classified (18:07:03Z) and **≈2.8–3.4 min before** the verdict was stamped (18:07:49Z). The
transcript is kept for 365 days. Every other candidate fails in one of four ways:

- **Not durable.** The inbox is a queue that the recipient prunes on delivery.
- **Not an event.** `config.json` member absence is a state with no per-member timestamp.
- **Not lead-authored.** Teardown markers can come from a teammate-side writer. The orphan-pane and
  auto-shutdown logs are member-side.
- **Absent for this death class.** There are no close records for members, and no SessionEnd ran.

A fleet census backs the ranking. Seven teammate deaths were classified `CRASH/abrupt-unknown`. In
6 of the 7, the lead transcript holds a successful `TaskStop` of that member 33–53 s before the death
row. In 1 of the 7 (cvf-docs) it also holds a successful shutdown_request. So the incident is not a
one-off. The commonest shape is a TaskStop with **no** shutdown_request, which the current arm 1.4
can never see.

## Timeline (receipts)

| UTC | event | receipt |
|---|---|---|
| 17:53:48.437 | lead `Agent` spawn `name:"cvf-docs"`, description "Apply verdict-first doc rule edits" | lead transcript line 531 |
| 17:53:59.960 | result `status:"teammate_spawned"`, `agent_id:"cvf-docs@session-247fdf36"`, `tmux_pane_id:"200"`, `team_name:"session-247fdf36"` | lead line 539 `.toolUseResult` |
| 17:53:56 (12:53:56 CDT) | watchdog registers `session=5b813b72… pid=23017 tty=ttys019 pane=200 teammate=cvf-docs@session-247fdf36` | `~/.claude/logs/lead-crash-watchdog.log:59393` |
| 18:03:41.243 | teammate gets the lead's "relay doc passages" message and resumes editing (this is why it was BUSY later) | teammate transcript line 337 |
| 18:04:25.438 | **lead `SendMessage` shutdown_request → cvf-docs** | lead line 820 |
| 18:04:26.207 | **result** `success:true, request_id:"shutdown-1791655466065@cvf-docs", target:"cvf-docs"` | lead line 828 |
| 18:04:26.867 | teammate's last message record: a `Bash` tool_use with no tool_result ever written | teammate transcript (390 lines; tail) |
| 18:04:26.983 | `inboxes/cvf-docs.json` atomically rewritten to `[]` (birth = mtime = ctime) | python `os.stat` (below) |
| 18:04:27.48 → 18:05:27.92 | the teammate's in-flight Bash output file is born, then completes **after** the SIGTERM. The transcript never records it | `/private/tmp/claude-501/…/5b813b72…/tasks/bd2j37woq.output` birth/mtime |
| 18:04:40.623 | **lead `TaskStop {"task_id":"cvf-docs"}`** | lead line 842 |
| 18:04:50.929 | **result** `"Successfully stopped task: t5ou0rn4u (Apply verdict-first doc rule edits)"`, `task_type:"in_process_teammate"`. It took 10.3 s, which matches the vendor's 10 s pane-teardown timeout (see §3) | lead line 843 |
| 18:04:59.336 | **lead `Bash` `kill -TERM 23017; ps -p 23017 -o pid= \|\| echo gone`** | lead line 857; `~/.claude/logs/bash-commands.log:42997` `[2026-10-10T18:04:59Z] [247fdf36-…]` |
| 18:05:00.283 | result `stdout:"23017"` (still alive) | lead line 858; `~/.claude/logs/bash-execution.log:7322` `… \| Exit: 0` |
| 18:05:07 / 18:05:25 / 18:05:56 | lead's polls still see 23017 (`23017 S+`, then `23017`) | lead lines 862, 881, 913 |
| ≈18:06:27.4 | claude.exe 23017 exits 143. **Estimated** from the teammate's final `cost-state` record, `startTime 1791654833767 + totalDuration 753659 ms`. It agrees with the transcript mtime 13:06:27 CDT | `tail -n1` of teammate transcript; `stat` |
| (unstamped) → 18:07:03 | watchdog logs `LEAD CRASH detected pid=23017`, then `death class=CRASH cause=abrupt-unknown (1159KB/390recs …)`. Crash row `ts 18:07:03Z`, `exit_code:""` | watchdog log :59401-59403; `claude-crashes.jsonl` row for 5b813b72 |
| 18:07:49 | verdict text stamped "verdict painted 2026-10-10T18:07:49Z" | screenshot `~/.reso/teammate-teardown/killed-pane-2026-10-10.png` |
| 18:08:04 (13:08:04 CDT) | watchdog logs `pane verdict PAINTED on ttys019 (pane 200)` | watchdog log :59405 |
| 18:09:57 | lead first sees `docs-gone` | lead line 939 |
| 18:12:12.816 | `config.json` last rewritten (the cvf-hooks removal). The cvf-docs removal has no separate timestamp | `os.stat` |

**Negative facts at classification time** (all measured):

- No `Session ended sid=5b813b72…` line in `~/.claude/logs/sessions.log`. The siblings have one:
  f959926c at 13:01:00 CDT and d2a47de0 at 13:12:14 CDT.
- SessionEnd never ran, so the pidfile survived. The daemon therefore took the `LEAD CRASH detected`
  branch (`hooks/lead-crash-watchdog.sh:1844`), not `pid file gone AND lead pid … is gone`
  (`:1820`), which the siblings took.
- No `orphan-pane-close cvf-docs` line in `teammate-lifecycle.log`.
- No teardown marker named `5b813b72…`, `23017` or `200` in `~/.claude/watchdog/teardown`.
- No close record `23017-*.json` among the 1498 in `~/.claude/logs/close-records`.
- No `shutdown_request` teammate-message in the teammate transcript. A python scan found 7
  "shutdown" hits, all prose: instructions, brief, skill list and TeammateIdle-hook names.

The classifier still says the same thing today. I re-ran it with isolated teardown, close-record
and handoff stores:

```
$ CC_TEARDOWN_DIR=$TMPD/td CC_CLOSE_RECORDS_DIR=$TMPD/cr CC_HANDOFF_LOG=$TMPD/h.jsonl \
  bash hooks/lead-crash-watchdog.sh --classify 5b813b72-0d7c-40ab-bf65-40d9ee333fd3 23017 1791655587
CRASH	abrupt-unknown	1159	390
(same with live stores)  CRASH	abrupt-unknown	1159	390
siblings f959926c / d2a47de0 →  RECYCLE retired-teammate  (both)
```

The deployed hook is byte-identical to this worktree: `diff -q hooks/lead-crash-watchdog.sh
~/.claude/hooks/lead-crash-watchdog.sh` ⇒ SAME.

---

## 1. Lead transcript: the strong candidate

`~/.claude-quaternary/projects/-Users-chrisren-Development--worktrees-close-verdict-first/247fdf36-462d-4657-a4ca-6b951f6773b3.jsonl`
(4,647,962 bytes). The member's transcript is a **sibling in the same project dir**, because members
spawn with the lead's cwd. The file listing shows `247fdf36…`, `5b813b72…`, `d2a47de0…` and
`f959926c…` side by side.

### 1a. SendMessage shutdown_request (line 820) and its result (line 828)

```
record.type == "assistant", record.sessionId == "247fdf36-…", record.uuid == "306f85f3-…"
record.message.content[] where .type=="tool_use" && .name=="SendMessage":
  .id    = "toolu_01LTMuefvQL2WdTbZs12ikUF"
  .input = {"to":"cvf-docs",
            "message":{"type":"shutdown_request","reason":"eec712aee merged into close-verdict-first"},
            "type":"shutdown_request","recipient":"cvf-docs","recipient_kind":"name","content":"…"}
```
```
record.type == "user", record.sourceToolAssistantUUID == "306f85f3-…" (== the tool_use record's uuid)
record.message.content[] where .type=="tool_result" && .tool_use_id=="toolu_01LTMuefvQL2WdTbZs12ikUF"
record.toolUseResult = {"success":true,
                        "message":"Shutdown request sent to cvf-docs. Request ID: shutdown-1791655466065@cvf-docs",
                        "request_id":"shutdown-1791655466065@cvf-docs","target":"cvf-docs"}
```

What a reader should match:
- `.input.to == <name>` OR `.input.recipient == <name>`.
- `.input.message.type == "shutdown_request"`, with legacy `.input.type` as the fallback.
- The joined result must have `.toolUseResult.success == true` and
  `.toolUseResult.request_id` ending in `"@<name>"`.

The request id embeds the send instant: 1791655466065 ms = 18:04:26.065Z.

### 1b. TaskStop (line 842) and its result (line 843)

```
tool_use: .name=="TaskStop", .id=="toolu_01H3E8rmy6YnLb5VhoysXSZU", .input == {"task_id":"cvf-docs"}
result:   record.toolUseResult == {"message":"Successfully stopped task: t5ou0rn4u (Apply verdict-first doc rule edits)",
                                   "task_id":"t5ou0rn4u","task_type":"in_process_teammate",
                                   "command":"Apply verdict-first doc rule edits"}
          record.message.content[0].content is the same JSON as a STRING (no is_error)
```

**Trap: the result does NOT name the member.** `task_id` is an opaque id (`t5ou0rn4u`), and
`command` is the spawn's `description`. The member name exists only in the **tool_use input**, so a
reader must join on `tool_use_id`. My first census pass filtered lines by the member name and scored
every TaskStop result as missing. The pass that joined on the id found them.

**Trap: a failed TaskStop has the same tool_use shape.** Lead line 726 at 18:01:01Z is a TaskStop
of cvf-readout. Its result is `"<tool_use_error>No task found with ID: cvf-readout. Running
teammates: …</tool_use_error>"`, with a string `toolUseResult` starting `Error:`. So the reader must
require `toolUseResult.task_type == "in_process_teammate"` and not an error.

Vendor semantics (binary `~/.claude-293/…/claude.exe`, v2.1.293, read with python mmap):

- `ULt = {name:"InProcessTeammateTask", type:"in_process_teammate", async kill(…){ let
  {memberRemoval:u, osTeardown:o} = Rln(…); await Promise.all([u,o]) }}` with `T=1e4`.
- `Rln` marks the task `killed`, aborts it, and races `paneTeardown` against `T`. On timeout it logs
  "`pane teardown … did not complete cleanly … Not blocking the stop result on it; the backend kill
  continues in the background and the separate \`claude --agent-id\` process may still be
  running`".
- It also calls `wKt(teamName, agentId, {onlyIfJoinedBefore: Date.now()})`, which is
  `removeMemberByAgentId`: `s.members.splice(u,1)` on the team file.
- The tool then returns `Successfully stopped task: ${taskId} (${command})` regardless of the pane
  outcome.

The 10.306 s TaskStop duration (18:04:40.623 → 18:04:50.929) equals that 10 s timeout. It is the
on-disk fingerprint of "TaskStop said stopped, the process lived on". The five sibling TaskStops in
the census (§7) returned in 0.4–1.0 s, and their processes died.

### 1c. The kill (lines 857/858) plus two hook logs

```
tool_use .name=="Bash", .input.command == "kill -TERM 23017; ps -p 23017 -o pid= || echo gone"
result   .toolUseResult.stdout == "23017", is_error false
```

The same command was also logged by hooks, keyed on the hook-input session id:
- `bash-commands.log:42997 [2026-10-10T18:04:59Z] [247fdf36-…] kill -TERM 23017; …` (PreToolUse,
  `hooks/log-bash.sh` family)
- `bash-execution.log:7322 [2026-10-10T18:05:00Z] [247fdf36-…] … | Exit: 0`

This evidence works only as a pid-literal text match. It misses `pkill -f`, `kill $(pgrep …)` and
cc-teardown. Both logs rotate: the oldest line in each is from today (03:22Z and 05:37Z). Use it as
corroboration only.

### 1d. Who writes it, forgeability, timing, survival

| property | finding |
|---|---|
| writer | the lead's own claude.exe, with vendor-minted `toolUseResult` (request id `shutdown-<ms>@<name>`, `task_type`), linked by `sourceToolAssistantUUID` → tool_use record `uuid` |
| can a teammate or unrelated process write it? | Only by deliberately appending to another session's 0600 JSONL as the same uid. No hook or agent does that. Forging means synthesising a tool_use plus a matching vendor result plus a uuid chain, which is far costlier than any other candidate. |
| present before classification? | Yes. 18:04:25–18:05:00, against classification ≤18:07:03 and verdict 18:07:49. |
| survives? | `cleanupPeriodDays = 365` in `~/.claude/settings.json` and `~/.claude-quaternary/settings.json`. 0 of 2007 quaternary transcripts are older than 60 days (`find -mtime +60`). |
| how the classifier finds it | The member transcript records carry `teamName:"session-247fdf36"` and `agentName:"cvf-docs"`, but no lead sid key (python key census: 268 records with teamName/agentName, none with a parent id). Join routes: (a) `teams/<team>/config.json .leadSessionId` (gone once the lead exits gracefully: dir deleted, per `docs/research/team-inplace-upgrade-2026-09-23/q1-lead-exit.md:158`); (b) the 8-hex team suffix as a sid prefix in the **same project dir**, which resolved every case in the census; (c) the member argv `--parent-session-id 247fdf36-…` (visible in lead line 838's `ps`). The watchdog does **not** capture (c) at registration today. It captures only `--agent-id` (`hooks/lead-crash-watchdog.sh:1686-1699`), so (c) would be the cheapest robust join to add. |
| guards a reader needs | the event's sessionId must be the member's lead; `name` must equal the member's `agentName`; the event must fall **after** the member's spawn (re-spawned same-name members exist; the vendor guards the same thing with `onlyIfJoinedBefore`) and **before** the death, within a freshness window |

---

## 2. Team inbox `teams/session-247fdf36/inboxes/cvf-docs.json`: not durable

```
cvf-docs.json   birth 18:04:26.983  mtime 18:04:26.983  ctime 18:04:26.983  size 2   ("[]")
cvf-readout.json birth 18:00:37.521 mtime 18:00:37.521  size 2
cvf-hooks.json  birth 18:12:06.326  mtime 18:12:06.326  size 2
team-lead.json  birth 18:12:13.059  mtime 18:12:13.059  size 2
```
(python `os.stat` → `st_birthtime/st_mtime/st_ctime`, UTC ms)

**When it was emptied:** 18:04:26.983Z. That is 0.78 s after the lead's SendMessage result (18:04:26.207)
and 116 ms after the teammate's last tool_use (18:04:26.867). Birth equal to mtime means an
atomic replace.

**By whom:** the recipient, pid 23017. This is inferred with high confidence. The vendor
`markMessagesAsRead` takes the inbox lock, keeps only `!read && !delivered` entries,
`atomicWrite(path, …)`, and logs "`pruned N delivered message(s), M remain`". The lead made no
further write to that inbox. "Delivered" means handed to the member's runner, not yet written to its
transcript. The member was mid-Bash, so the message waited for the next turn boundary, which never
came. The vendor runner string "`received shutdown request - passing to model`" shows the hand-off
is in memory.

The sibling cvf-readout proves the gap exists even on a healthy member. Its inbox was pruned at
18:00:37.521Z, but the `<teammate-message>` shutdown_request reached its transcript only at
18:00:46.692Z, 9.2 s later, batched with the relay message (f959926c line 179). cvf-hooks, which was
idle, had delivery (18:12:06.258) and prune (18:12:06.326) 68 ms apart.

**Does an inbox ever durably keep a shutdown_request?** Only while it is **unconsumed**. Census
across all 4 roots (python over `~/.claude*/teams/*/inboxes/*.json`):

- 44 inbox files: 2 + 12 + 11 + 19.
- 11 `shutdown_request` entries in total: 1 in `~/.claude`, 6 in quaternary, 4 in tertiary.
- **Every one is `read:false`**, and no `read:true` message of any type exists anywhere.
- Examples: `~/.claude/teams/default/inboxes/gate-probe.json` (2026-10-07T22:07:57Z); three
  `session-cd5eee6e` members (2026-09-15T22:12Z) whose recipients never polled again.
- Four of the eleven are **`"from":"watchdog"`** injections with **no requestId**
  (`session-6ee7e044`, 2026-08-25). They are written by `hooks/lead-crash-watchdog.sh:2085-2115`
  when a lead crashes.

So an inbox entry means "sent but never consumed". It is the opposite of what a classifier wants
from a member that did consume. It is also writable by a non-lead local process (the watchdog's
jq read-modify-write).

Inbox **dirs** are also mostly gone: `ls -d teams/*/inboxes` gives 2/55, 4/68, 2/227 and 4/89 team
dirs per root.

**Verdict:** worthless as a classifier input. At most it is weak corroboration that a message was
consumed.

Side finding for whoever owns arm 1.4: `teammate_facts` accepts a shutdown_request with an **empty**
requestId (`shut = any((not r) or …)`, `hooks/lead-crash-watchdog.sh:375`). If a watchdog injection
were delivered into a member transcript, it would therefore read as a lead-ordered retirement. That
is arguably the right outcome for a crashed lead, but it means arm 1.4 does not prove "the lead
ordered it".

---

## 3. Team `config.json` member removal: lead-side, but a state with no timestamp

- Now: `members` = `[team-lead]` only. `mtime = ctime = 18:12:12.816Z`, birth 16:19:14.578Z.
- The 18:12:12 write matches the cvf-hooks retirement: its inbox was pruned at 18:12:06 and its
  session ended at 13:12:14 CDT. That write **overwrote any timestamp** the cvf-docs removal had.
- **When cvf-docs was removed:** not recoverable from disk. Vendor code and timing put it at the
  TaskStop window, 18:04:40–18:04:50Z: `Rln` → `wKt(…, {onlyIfJoinedBefore})` → `members.splice`.
  cvf-docs never approved, so the other path (the lead's InboxPoller processing `shutdown_approved`)
  cannot apply. This is an inference, not a measurement.
- No vendor debug log exists for the lead. `~/.claude-quaternary/debug/247fdf36*` has no match, so
  the `[TeammateTool] Removed member …` line was never persisted.

**What else removes members, or makes them absent:**
1. The lead's InboxPoller on `shutdown_approved`: kill pane, remove row
   (`docs/research/SUBAGENT_LIFECYCLE_ROOT_CAUSE_2026-09-19.md:149`).
2. TaskStop → `killInProcessTeammate` (vendor, above).
3. The whole team dir deleted by `rm -rf` on a graceful lead exit, including SIGTERM/SIGINT/SIGHUP
   (`docs/research/team-inplace-upgrade-2026-09-23/q1-lead-exit.md:158`).
4. A resumed lead rebuilding its roster (same research).
5. The repo's own code edits no `members` arrays. The only hit for a members assignment is
   `scripts/research-kit/lib/cli_records.py:237`, which is unrelated.

Members only write `isActive` (`q2-teammate-relaunch.md:34`).

**Verdict:**
- Writer: lead-side, vendor. It can be forged by any same-uid process, and none does.
- Present before classification: almost certainly yes, but not provable.
- Survival: weak, because team dirs are deleted wholesale on graceful lead exit.
- Meaning: "absent from members" cannot tell retired-by-approval, TaskStopped, team-gone and
  never-a-member apart. Corroboration only, never a trigger.

---

## 4. `scripts/teammate-orphan-pane-close.sh` and `hooks/teammate-auto-shutdown.sh`: member-side, silent here

- **teammate-orphan-pane-close.sh** is **not** invoked by TaskStop or by any lead hook. Its header
  (`:3-4`) says "Detached by hooks/session-end.sh in the member's own SessionEnd; never run inside a
  turn". The only caller is `hooks/session-end.sh:97-109`, which passes
  `--cfg --team --name --agent-id --pane` once the member's argv qualifies.
- It logs to `TOPC_LOG:-~/.claude/logs/teammate-lifecycle.log` (`:58-59`). The siblings logged
  `[13:01:23] orphan-pane-close cvf-readout: no shutdown_approved …` and `[13:12:36] … cvf-hooks …`.
  **There is no line for cvf-docs**, because its SessionEnd never ran.
- What it reads is the member's **approval** in `team-lead.json`. That is a member-written fact, not
  a lead order.
- **teammate-auto-shutdown.sh** is a TeammateIdle hook that runs **inside the teammate**
  (`:1-4`, "Locus corrected 2026-09-19 — it is NOT lead-side"). It logs to `teammate-lifecycle.log`
  (`:128`) and has no cvf-docs line. Its last firing on cvf-docs, 18:03:41Z, **timed out at 5 s**:
  teammate transcript line 335, `hook_cancelled … teammate-auto-shutdown.sh … timedOut:true`.
- It is also a **teardown-marker writer**: `write_teardown_marker … teammate-idle` at `:240-257`,
  called from `close_and_log` at `:364`.

**Verdict:** neither is evidence of a lead order, and both are absent for a member that never
reaches SessionEnd or idle.

---

## 5. Teardown markers and the watchdog log

Store `~/.claude/watchdog/teardown`:
- 3790 files, **none** for `5b813b72…`, `23017` or `200`.
- 58 files are under 1 day old; **2468 are over 30 days old** (`find -mtime +30`).
- GC runs only from `gc_teardown_marker` on the owner-guarded pidfile-rm path
  (`hooks/lead-crash-watchdog.sh:685-701`), so in practice markers accumulate. Only the 30-min
  freshness window keeps them honest.

Mode census (grep over all files): `terminal` 1889, `recycle` 1009, `teammate-idle` 669,
`teardown` 175, `successor` 48.

Writers:

| writer | locus | modes / notes |
|---|---|---|
| `bin/cc-teardown:259-280` | desk | `mode:"teardown"`, keyed sid + pane + **pid** |
| `scripts/handoff-fire.sh:8089` | the session itself | recycle / terminal / successor |
| `hooks/teammate-auto-shutdown.sh:240-257` | **teammate side** | `mode:"teammate-idle"` |

Neither SendMessage nor TaskStop writes a marker.

**Gap in the arm 1.4 comment.** Arm 1.4's comment (`:583`) says "a member never writes either". But arm 1.5's
sid-keyed check (`:599`) accepts **any** mode, and the teammate-side auto-shutdown hook does write
markers. Fleet census: 16 registered-teammate deaths classified `deliberate-teardown`, 7 of them with
no lead shutdown_request. Of those 7, 6 had a lead TaskStop and 1 had neither. So a teammate-written
marker already absolves teammate deaths. `retired_by_desk` (`:307-320`) is the only reader that
requires `"mode":"teardown"`.

Watchdog log (`~/.claude/logs/lead-crash-watchdog.log`), every line for this sid:
- :59393 `[12:53:56 CDT] registered session=5b813b72… pid=23017 tty=ttys019 pane=200 teammate=cvf-docs@session-247fdf36`
- :59394 daemon pid 24877
- :59401 `LEAD CRASH detected pid=23017`
- :59402 `death class=CRASH cause=abrupt-unknown (1159KB/390recs mem_free=37% concurrent=29)`
- :59403 `[13:07:03 CDT] death page DELIVERED …`
- :59404 `crash — no teams affected`
- :59405 `[13:08:04 CDT] pane verdict PAINTED on ttys019 (pane 200): ⛔ NOT A CLEAN EXIT …`

This is an **output** of the classifier, not an input. Note that the registration line already
holds `teammate=<name>@<team>`, which is the join key the lead-transcript reader needs.

---

## 6. Close records (`bin/cc-close-attrib` store)

`ls ~/.claude/logs/close-records | grep '^23017-'` gives nothing, out of 1498 records. Nothing in
`close-attrib.jsonl` either. Members launch without the wrapper, so `ec` was empty, which is why the
cause stayed `abrupt-unknown` rather than `external-sigterm` (`:670`). The record would be written by
the **victim's** wrapper anyway: an observation of a signal, not a declaration of who ordered it
(`:291-299`). `cc-pane-runner` printed "claude.exe exited 143", but only to the pane's stderr
(`bin/cc-pane-runner:180`), so it is not durable.

**Verdict:** absent for the whole member class, and it would not identify the lead even if present.

---

## 7. Fleet census: does the lead-transcript signal generalise?

Method: python over `lead-crash-watchdog.log`.
1. Take every `registered … teammate=<name>@<team>` sid that has a `death class=` line: 77 deaths.
2. Find the lead transcript as the sid-prefix sibling of the member transcript.
3. In it, look for a SendMessage shutdown_request to `<name>` with `success` and
   `request_id …@<name>` (**SR_OK**).
4. Look for a TaskStop whose `input.task_id` is `<name>`, with the result joined by `tool_use_id`
   and `task_type=="in_process_teammate"` (**TS_OK**).

Scripts: `/tmp/ec-census/census.py` and `/tmp/ec-census/timing.py`.

```
50 RECYCLE retired-teammate   SR_OK          2 RECYCLE retired-teammate   SR_OK+TS_OK
 4 RECYCLE deliberate-teardown SR_OK         5 RECYCLE deliberate-teardown SR_OK+TS_OK
 6 RECYCLE deliberate-teardown noSR+TS_OK    1 RECYCLE deliberate-teardown noSR
 1 CRASH  abrupt-unknown       SR_OK+TS_OK   ← cvf-docs
 5 CRASH  abrupt-unknown       noSR+TS_OK    ← p3-cue, p3-naming, p3-vtt, p3-wire, lrsh-c4
 1 CRASH  abrupt-unknown       noSR          ← w3-p2 (no lead signal: plausibly a genuine death)
 1 CRASH  jetsam-oom SR_OK · 1 CRASH jetsam-oom noSR
```

The five TaskStop-only CRASHes, with TaskStop result time against the crash-row time:

| member | TaskStop result | crash row | gap |
|---|---|---|---|
| p3-naming | 04:18:03Z | 04:18:36Z | 33 s |
| p3-vtt | 04:18:04Z | 04:18:14Z | 10 s |
| p3-cue | 05:07:57Z | 05:08:39Z | 42 s |
| p3-wire | 05:28:21Z | 05:28:53Z | 32 s |
| lrsh-c4 | 16:23:20Z | 16:24:08Z | 48 s |

Each result reads "Successfully stopped task: t… (…)" with `task_type:"in_process_teammate"`.

Reading:
- A lead-transcript reader that accepts **either** SR_OK **or** TS_OK, in a window before death,
  would have turned **6 of 7** `abrupt-unknown` teammate CRASHes into retirements. Measured over
  the population that carries the `teammate=` tag.
- It would have left alone the one with no lead signal (w3-p2) and both jetsam deaths, since jetsam
  outranks.
- SR_OK alone rescues **1 of 7**. The TaskStop leg is the bigger half.
- Every one of the 52 `retired-teammate` deaths also carries SR_OK. The lead-side read agrees with
  arm 1.4 wherever arm 1.4 fires.

Caveat: this census matched `input.task_id == <name>` and did not verify each result's
`task_id`/`command` against that member's spawn. The 0 false matches and the sub-minute gaps make
coincidence unlikely, but **I did not prove** it per row.

---

## Ranking as a classifier input

| rank | candidate | lead-authored? | forge cost | present before verdict (this case) | durability | covers this incident | recommendation |
|---|---|---|---|---|---|---|---|
| **1** | **Lead transcript TaskStop**: `tool_use.name=="TaskStop"`, `input.task_id ∈ {name, name@team}`, joined result `toolUseResult.task_type=="in_process_teammate"`, not `<tool_use_error>` | yes (vendor-minted result) | high | yes (18:04:50, −2:13 before classify) | 365 d | yes | **primary trigger** (with 2) |
| **2** | **Lead transcript SendMessage shutdown_request**: `input.(to\|recipient)==name`, `input.message.type=="shutdown_request"`, joined `toolUseResult.success && request_id endswith "@"+name` | yes | high | yes (18:04:26, −2:37) | 365 d | yes | **primary trigger** (OR with 1) |
| 3 | Member transcript delivered `<teammate-message>` shutdown_request (today's arm 1.4) | lead's message, but delivery is member-side | medium (accepts empty requestId, so watchdog injections count) | **no**: the member died before its turn boundary | 365 d | **no** | keep as-is, an additional route |
| 4 | Lead-sid Bash kill line (lead transcript Bash tool_use; `bash-commands.log` / `bash-execution.log`) | yes | medium (text) | yes (18:04:59) | transcript 365 d; hook logs rotate within a day | yes, but only by pid literal | corroboration / explanation text only |
| 5 | `config.json` member absent | yes (vendor, lead-side) | low–medium | probably (unprovable) | team dir deleted on lead exit | ambiguous | corroboration only |
| 6 | Teardown marker (arm 1.5/1.6) | **no**: desk, self, or teammate-idle | low (teammate-side writer exists) | **absent** | 30-min window; GC incomplete (2468 > 30 d) | no | unchanged; not for this class |
| 7 | Inbox shutdown_request | sender is lead **or watchdog** | low | **pruned 0.78 s after landing** | queue | no | do not use |
| 8 | Close record | victim's wrapper | n/a | absent (members unwrapped) | — | no | n/a |
| 9 | orphan-pane-close / auto-shutdown logs | member-side | — | absent (no SessionEnd / idle) | log | no | n/a |

Minimum reader contract for ranks 1+2:
- Resolve the lead sid from `config.json .leadSessionId`, else the team-suffix prefix in the member's
  project dir, else a captured `--parent-session-id`.
- Stream the lead JSONL and keep tool_use ids for `SendMessage`/`TaskStop` aimed at `<name>`.
- Accept only when the joined result shows success.
- Accept only events after the member's spawn (lead `Agent` result `agent_id == name@team`) and at
  or before the death epoch, within a bounded window (for example the 30 min used for markers).
- Jetsam still outranks, as it does for every other arm.
