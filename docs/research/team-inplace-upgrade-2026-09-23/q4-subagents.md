# Q4: in-process subagents during a same-account in-place relaunch (idle vs active)

**Verdict (5 lines)**
1. **Idle (finished) subagents are SAFE to relaunch over.** `subagent_gate` lets them through, and on 2.1.280 an old agent can still be continued after `--resume` by sending `SendMessage` to its agentId, which resumes it from `<sid>/subagents/agent-<id>.jsonl` on disk. The same-account relaunch keeps the same sid and config dir, so those files stay where the harness looks for them.
2. **In-flight background subagents die with the process** (they run in-process, so the SIGKILL takes them too). `subagent_gate` already REFUSES with rc 4 before anything is typed, and lr-upgrade never passes `--allow-live-subagents`. It records `skipped: handoff-fire refused before /exit (rc 4)`, and the next poller tick re-queues the row. So "defer, re-judge next pass" already exists in effect, but it is **misreported**: the census says `upgrade` for this row.
3. **An in-flight foreground subagent is already excluded as `mid-turn`.** The lead has an unresolved tool_use, so the at-rest check fails.
4. **Three real gaps:**
   - (a) In-flight background **Dynamic Workflows** are invisible to both gates, so a relaunch kills them.
   - (b) `subagent_gate` is not re-run at the last pre-`/exit` read (only at-rest is), so a subagent spawned inside the ≤180 s composer window gets killed.
   - (c) A subagent killed in an earlier process life reads "in flight" forever, so the row is re-refused on every tick.
5. **Recommendation:**
   - Add a census disposition `subagents-in-flight` (defer, re-judged next pass). Derive it from handoff-fire's OWN predicate, not a copy.
   - Add workflow detection.
   - Re-run `live_subagents_of` at the last read.
   - Retire corpses by comparing the agent file's mtime with the lead pid's lstart.
   - Never auto-pass `--allow-live-subagents`.

---

## 1. How `subagent_gate` classifies (scripts/handoff-fire.sh)

**Where it looks.** `subagent_dir_for_sid` (:5240-5258) globs `${CC_PROJECTS_DIRS:-$HOME/.claude*/projects}/*/<sid>` and keeps the first dir that has a `subagents/` child. No `subagents/` dir means the session never spawned a subagent, which is a silent all-clear (:5282-5286).

**How it enumerates.** `live_subagents_of` (:5196-5228) iterates `<dir>/subagents/agent-*.meta.json` (:5200). It skips a meta that has no sibling `agent-<id>.jsonl` (:5203). The glob does **not** descend into `subagents/workflows/<runId>/` (see §4a).

**How it decides one agent is "stopped".** Two arms, primary first:
- **PRIMARY: a structural stop record.** `subagent_stops_of` (:5183-5194) reads the PARENT transcript `<dir>.jsonl`. It keeps only lines that carry a BARE harness key:
  - `"origin":{"kind":"task-notification"}`
  - `"type":"queue-operation"`
  - `"type":"queued_command"`

  It then requires the content/prompt string to OPEN with `<task-notification>\n<task-id>ID</task-id>`, and emits `id<TAB>timestamp`. The agent counts as stopped iff the max bare `"timestamp"` in its own jsonl is ≤ the latest stop ts (:5208-5216). An agent that wrote anything AFTER its last stop was RESUMED, so it is live again (:5217-5218).
- **FALLBACK** (no stop record, or no timestamps): the agent counts as stopped iff the last quoted `"stop_reason"` in its jsonl is `"end_turn"` (:5221-5222).

**Everything else is IN FLIGHT.** It is emitted as `id<TAB>description<TAB>path` (:5226-5227).

**Signals deliberately rejected** (design notes, :5123-5150):
- the main transcript's tool_result: a background agent's `toolUseResult.status` reads `async_launched` forever;
- mtime;
- a substring scan for `<task-id>…<status>`: forgeable by tool output, whose quotes are JSON-escaped.

**Why the stop record was added** (:5134-5141). Measured: 241 of 483 subagent transcripts (112 of 136 on 2.1.260) never write `end_turn`. The stop record covers 407 of 483, with 0 violations.

**Decision** (`subagent_gate` :5266-5318):

| state | action |
|---|---|
| `CC_RECYCLE_SUBAGENT_GATE=off` | admit, logs `gate-off` (:5269-5271) |
| no sid | admit LOUDLY, `unresolved` (fail-open; :5277-5281) |
| no in-flight rows (all idle/finished) | **admit silently** (:5288-5289) |
| in-flight rows, `--allow-live-subagents` absent | **REFUSE rc 4**: names each id, description and partial transcript, then `emit_fire_refusal live-subagents` (:5291-5313) |
| in-flight rows, flag present | admit, "KILLED deliberately", then `emit_gate_admit … override` (:5316-5317). The successor brief gets a "SUBAGENTS KILLED BY THE RECYCLE" trailer listing the partial-transcript paths (:10921-10934) |

**Where it is called:**
- `--recycle`: :9960, in the foreground pre-pass before any side effect. For a same-account row this is AFTER `hf_same_account_evidence` (:9876). `--allow-live-subagents` is forced only by `--transplanted-source --transplant-cause limit` (:9953-9959), never for same-account.
- self-close: :8576.
- `--probe-recycle-preconditions` COUNTS it without refusing (`live_subagents: N`), on every path (:7972-7973).

**The same-account at-rest oracle is a different question.** `hf_transcript_at_rest` (:2304-2314) is true iff the last non-sidechain user/assistant record in the last 400 lines is an assistant record with `end_turn`. `hf_same_account_evidence` (:2325-2365) requires it at admission. `recycle_fire` re-reads it right before `/exit` and aborts with `recycle-held-busy` if it is no longer at rest (:12798-12810).

A lead with only BACKGROUND agents running is usually at rest (end_turn after the `async_launched` result), so at-rest does not protect them; `subagent_gate` does. A FOREGROUND agent in flight leaves the lead with an unresolved tool_use, so at-rest returns 1.

## 2. Process death and what a resumed lead sees (binary 2.1.280)

**Subagents die with the process.** They run in-process: the gate text at :5297-5298 says so, and the binary agrees (below).

**The resume-time orphan scan.** Function `w3e` → `$r` → `Hr`, near byte 193265412 of `~/.claude-280/.../claude.exe`:
- It collects from the parent transcript every tool_result with `status==="async_launched"` and an `agentId`. These are background Agent spawns, flagged `launchedByAgentTool`.
- It skips agents already in `notifiedTaskIds`, meaning they had a task-notification, i.e. they finished.
- Everything left is an orphan. It logs `resume: N background agent(s) orphaned by previous process exit` and counts telemetry `task_local_agent/orphaned_on_resume`.

**What each orphan gets.** A queued task-notification (`mode:"task-notification"`, `priority:"next"`, `shouldQuery:false`), chosen as follows:
- **>20 orphans** (`Ne=20`): all are marked `failed` in one aggregate notice.
- **Transcript on disk** (mtime known): status `stopped`, note *"No completion record was found … may have been running when the previous Claude Code process exited — either way its transcript is saved, so its progress is not lost. Resume it by sending it a message with SendMessage, or check its worktree/output for partial work before assuming the task landed."*
- **No transcript**: status `failed`, note *"It was running when the previous Claude Code process exited and did not complete. Its in-process state was lost."*
- **Auto-restart** (*"restarted after the previous session ended … automatically restarted from its saved transcript"*) happens only when a resume callback `r` is supplied and the agent transcript is younger than `Fr=172800000` ms (48 h). The callback is supplied ONLY on the background-job adopt path: `restoreOnMount` → `if (Fl())` … `w3e(h,D,(Fe)=>this.resumeOrphanedAgents(Fe,Pe),…)`, with `Fl()` = `s9()==="bg" || bgTakeover`. The ordinary interactive REPL resume calls `w3e(h,D,void 0,void 0,Q)`, i.e. **no auto-restart**. The lr-upgrade relaunch is an interactive `--resume` in a pane, so it takes this no-auto-restart path.

**A resumed lead can continue an old subagent by id.** The SendMessage tool prompt says: *"names keep working after an agent completes (a send resumes it from its transcript). Use the raw `agentId` (format `a...-...`) … only when the agent has no name"*. The orphan notices themselves say "Resume any of them by sending a message to its id with SendMessage".

So after a restart:
- **finished agents** stay continuable via SendMessage to their agentId;
- **agents killed mid-run** are announced as `stopped` and can also be continued from their saved transcript, but they redo the in-flight step and get no auto-restart;
- **dangling foreground tool_use**: interrupt markers exist (`[Request interrupted by user for tool use]`), but same-account admission already refuses that state, so it does not arise here.
- **Use the agentId, not the name.** That a name survives a restart is unverified, whereas the orphan notes address agents by id.

**Workflows have their own orphan branch** (`zr`): *"Background workflow … orphaned … relaunch with Workflow({scriptPath, resumeFromRunId}) — completed agent() calls return cached."* Workflow agents live under `<sid>/subagents/workflows/wf_<run>/agent-*.{jsonl,meta.json}`. I checked this on disk: `~/.claude/projects/-Users-chrisren-Development-personal/140be330-…/subagents/workflows/wf_18ac7a0b-cd8/agent-a4ddc0ba7722d761f.meta.json`. The memory `subagent-records-live-in-separate-files.md` records the same layout.

## 3. Recommendation for lr-upgrade

**What it does now** (scripts/limit-recover/lr-upgrade.sh):
- The census dispositions (:29-31, :295-321) include `mid-turn` (`lru_at_rest`, :313) and `background-job` (bash children only, `lru_bg_kind` :179, :316). Nothing looks at Agent/Workflow tasks.
- `--drive` calls `handoff-fire.sh --recycle --same-account …` (:484-486) **without** `--allow-live-subagents`, so it relies on the gate.
- On rc 4 the old pid is still alive, so the run is recorded as `skipped "handoff-fire refused before /exit (rc 4): !! recycle REFUSED: N Agent-tool subagent(s)…"` (:492-493). `lru_auto_enqueue` re-queues every `upgrade` row on the next tick (:565-585). **Nothing is killed today.**
- The cost of this path: each tick runs a capacity probe and mints a token (:458-460 / `lru_capacity`), mints a launcher, and reads the composer, only to be refused. The census also reports the row as `upgrade`.

| state at relaunch | safe? | handled today by |
|---|---|---|
| no subagents / all finished (stop record or end_turn) | **yes**; continuable after resume via SendMessage(agentId) | gate admits silently |
| foreground Agent in flight | no | at-rest → `mid-turn` |
| background Agent in flight | no; it dies and resumes as a `stopped` orphan | gate rc 4 → `skipped`, re-queued (census still says `upgrade`) |
| background Workflow in flight | no | **NOT handled**: gate glob misses `subagents/workflows/`, and at-rest is true |
| agent spawned between pre-pass and `/exit` (≤ `CC_RECYCLE_DRAFT_WAIT`=180 s window, :12584) | no | **NOT handled**: the last read (:12805) re-checks at-rest only, not subagents |
| agent killed in an EARLIER process life (no stop record, no end_turn) | yes; it is already dead | **over-refused forever**. This is by design (:5152-5155), but it means the row never upgrades |

**Proposed changes** (none duplicates existing code):
1. **Census disposition `subagents-in-flight`**, placed after `mid-turn` and before `background-job`. Derive it from handoff-fire's own predicate, never a copy (see memory `sibling-auditors-must-share-the-state-model`): parse the `live_subagents: N` line of `handoff-fire.sh --probe-recycle-preconditions --source-pane P --source-session S`. That line is emitted on every path, exactly so callers can record it (:7962-7973); ignore the probe's limit verdict. An alternative is to factor `subagent_dir_for_sid`/`subagent_stops_of`/`live_subagents_of` into a sourced lib, which removes the duplication `lru_at_rest` already carries. The row then shows up honestly in `--census`, `--drive` skips it without spending a capacity token, and the next tick re-judges it.
2. **Workflow coverage.** Extend the enumeration to `subagents/workflows/*/agent-*.meta.json`, or better, key on the main transcript's `async_launched` `local_workflow` taskIds that have no structural task-notification (the binary's own `zr` logic). Put this in the shared predicate so the gate gains it too.
3. **Last-moment re-read.** In the same-account arm at :12804, call `live_subagents_of` again next to `hf_transcript_at_rest`, and abort with the same `recycle-held-busy` event.
4. **Corpse retirement (optional; it reduces over-refusal and keeps the safe direction).** If an agent's jsonl mtime is earlier than the lead pid's `lstart` (the process snapshot lr-upgrade already takes, with TZ pinned), that agent cannot be running in this process. It is a corpse from a prior life, so drop it from the in-flight set. A live agent was spawned by the current process and therefore has a write after `lstart`.
5. **Keep `--allow-live-subagents` out of the upgrade drive.** An upgrade is voluntary, so the agents are genuinely running (the same reasoning as D1 at :9941-9951).

**Unverified.** I have not observed whether the orphan notice the 2.1.280 resume writes is persisted with the bare `origin:task-notification` key. If it is, `subagent_stops_of` would retire a post-resume corpse by itself. Measure this on one resumed session before relying on it.
