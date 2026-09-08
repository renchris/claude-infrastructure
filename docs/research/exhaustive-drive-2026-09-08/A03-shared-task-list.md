# A03 — A Shared Task List a Stop hook can read

Wave: exhaustive-drive-2026-09-08 · axis A03 · read-only research · binary 2.1.260
All numbers below carry the command that produced them and the population counted.
"measured" = I ran it this session. "inferred" = reasoned, not run.

---

## Answer first

**The shared store already exists and is already fleet-wide. The tools that write to it are off, and
nothing reads what is in it.** Three separate defects wearing one name:

1. **Tools off.** `CLAUDE_CODE_ENABLE_TODO_TOOLS` is the gate, and it works — **measured**, A/B, both
   via the environment and via `settings.json` `env`. One c10 migration turns the Task tools on for
   every session of every account including headless.
2. **Store shared, list fragmented.** `~/.claude{,-secondary,-tertiary,-quaternary,-next}/tasks` all
   `realpath` to **one directory** (measured) — the store is already shared. But the launcher's list
   id is `<repo-basename>-<branch>` (`~/.zshrc:88`), so each worktree gets its **own** list: **994
   list dirs, 219 of them the doubled `X-X` worktree shape, 87/137/83 distinct project paths in the
   three populated per-account indexes** (measured). "The" shared list does not exist; ~60 of them do.
3. **Nothing reads it.** **293 open items across 58 lists, 85% older than 30 days, oldest 228 days**
   (measured). `TASKS.md` is regenerated to 102,725 bytes and **has no consumer anywhere in
   `hooks/ bin/ scripts/ commands/ skills/`** (measured grep). This graveyard is the strongest
   evidence for the rung the operator asked for — and the strongest warning about how to scope it.

The rung `OPEN_TASKS_MINE` is buildable and cheap (**73 ms** to count one list from raw JSON,
measured), but **must be session-attributed, not list-attributed**: a list-scoped term would fire on
66 stale items at every close in this repo forever — the alarm-that-always-fires the house has
already been burned by. Attribution has no field today (**3.4% of open items carry
`metadata.owner_session`**, measured); the deterministic fix is a **`TaskCreated` hook writing a
sidecar**, and `TaskCreated` is a real event in the binary that we do not register.

---

## (a) The gate, decoded out of the binary

`/Users/chrisren/.claude-260/node_modules/@anthropic-ai/claude-code/bin/claude.exe`, 198,289,440 B.
Scanned with a Python `bytes.find` pass (the interactive `grep` is rewritten to ugrep and chokes on
binaries; `grep -o -E '.{0,200}…'` did not finish in 120 s on this file, a Python scan of all 8
patterns took ~20 s).

Occurrence counts (measured): `CLAUDE_CODE_ENABLE_TODO_TOOLS` 4 · `CLAUDE_CODE_ENABLE_TASKS` 4 ·
`CLAUDE_CODE_TASK_LIST_ID` 5 · `tengu_rosy_wren` 2 · `TaskCreate` 35 · `TaskUpdate` 23 ·
`TaskCompleted` 27 · **`_summary.json` 0**.

### The predicate, verbatim (offset 163543861)

```js
var NDo=[["opus",[4,8]],["sonnet",[5]],["fable",[5]],["mythos",[5]]],
    l0e=[NS,DE,B3,NE,mT],
    LDo="tengu_rosy_wren";
function FDo(e){return!V1e(e,NDo)}
function pM(){
  if(Wa()||RPn())return!0;
  let e=IFe();
  if(e===void 0||FDo(e))return!0;
  if(a.CLAUDE_CODE_ENABLE_TODO_TOOLS===!0)return!0;
  return I(LDo,!1)===!0
}
function O9(){return $_()&&pM()}
```

Resolved helpers (each grepped separately):

| symbol | offset | meaning |
|---|---|---|
| `$_()` | 159792244 | `if(a.CLAUDE_CODE_ENABLE_TASKS===!1)return!1;return!0` — **a KILL switch, default ON**, not the enable |
| `Wa()` | 158157815 | `ht()\|\|Gh()!==null` — `ht()` is `CLAUDE_CODE_SESSION_KIND ∈ {bg,daemon,daemon-worker}`; `Gh()` a job context ⇒ **background/daemon sessions get the tools unconditionally** |
| `RPn()` | 155978029 | `host.launchOptions.todoToolsOptIn()` — an SDK/host launch option. **No CLI flag exposes it** (`claude --help` grep for todo/task: no match) |
| `IFe()` | 157747952 | `KN().mainLoopCanonical?.()` — the canonical model id |
| `V1e(e,r)` | 158638419 | parses `^claude-([a-z]+)-(\d+(?:-\d+)*)$`, compares component-wise against the family's floor; true ⇒ **at or above** |
| `I(LDo,!1)` | — | gate/flag read of `tengu_rosy_wren`, default false |
| `xE()` | 159793232 | list id = `CLAUDE_CODE_TASK_LIST_ID` → team name → `ri() \|\| cs().taskList.leaderTeamName \|\| K()` |
| `Lk(e)` / `F(e,n)` | 159793266 | `join(configDir(),"tasks",sanitize(e))` / `join(Lk(e), sanitize(n)+".json")` |

`HE(e)=e.replace(/[^a-zA-Z0-9_-]/g,"-")` sanitizes both the list id and the task id.

The binary's own changelog string (offset 167866884) confirms the reading:

> Todo/task-tracking tools (TaskCreate/Get/Update/List, TodoWrite) are no longer available on Opus
> 4.8, Sonnet 5, Fable 5, Mythos 5, and newer models; set `CLAUDE_CODE_ENABLE_TODO_TOOLS=1` to bring
> them back

**Two things this corrects in the wave brief.**

- The two env names are **not alternatives**. `CLAUDE_CODE_ENABLE_TASKS` only *disables* (`===!1`);
  `CLAUDE_CODE_ENABLE_TODO_TOOLS` is the *enable*. Setting `ENABLE_TASKS=false` would be actively
  wrong: `TodoWrite.isEnabled` is `!$_()&&pM()` (offset 163894876), i.e. **TodoWrite is the fallback
  for when the disk-backed Task family is switched off**, and it writes to in-memory app state
  (`r.todos[agentId]`), not to `~/.claude/tasks`. We want the Task family, so leave `ENABLE_TASKS`
  alone.
- `CLAUDE_CODE_TASK_LIST_ID` does exactly what the launcher assumes: it is the **first** branch of
  `xE()`, overriding the team name and the session id.

---

## (b) The probe — and the blocked backlog row it refutes

Backlog row **`ebe84950e98a`** is filed **blocked** with the note *"Do the task/todo tools survive on
2.1.260 + opus-5? A --print probe is measurably BLIND to this axis"*
(`cc-backlog list --all --json | jq 'select(.id=="ebe84950e98a")'`, measured).

**That premise is false.** A `--print` probe is not blind if you (i) strip settings so hooks cannot
interfere and (ii) ask the model to enumerate its tools. Deferred tools are listed by NAME in the
model's context, so the enumeration is complete. Three runs, same binary, same model, same cwd
(`/tmp/a03-probe`), differing only in how the flag was supplied:

```
/Users/chrisren/.claude-260/node_modules/@anthropic-ai/claude-code/bin/claude.exe \
  --print --model claude-opus-5 --effort low --setting-sources "" \
  --output-format json --permission-prompts none \
  'Reply with ONLY a comma-separated list of the exact names of every tool available to you. No prose.'
```

| run | Task-family tools in the reply | cost |
|---|---|---|
| **control**, no env | *(none)* — `Agent, Bash, Edit, ListAgents, Read, ReportFindings, ScheduleWakeup, Skill, ToolSearch, Workflow, Write, CronCreate, CronDelete, CronList, DesignSync, EnterWorktree, ExitWorktree, Monitor, NotebookEdit, PushNotification, RemoteTrigger, SendMessage, TaskOutput, TaskStop, WebFetch, WebSearch` | $0.073 |
| **env** `CLAUDE_CODE_ENABLE_TODO_TOOLS=1` | **+ TaskCreate, TaskGet, TaskList, TaskUpdate** | $0.048 |
| **settings** `--settings '{"env":{"CLAUDE_CODE_ENABLE_TODO_TOOLS":"1"}}'` | **+ TaskCreate, TaskGet, TaskList, TaskUpdate** | ~$0.04 |

(`TaskOutput` / `TaskStop` are the *background-task* tools and are present in the control too — they
are not the todo family. `TodoWrite` never appears, exactly as `!$_()&&pM()` predicts.)

**Cost of enabling, measured.** Same probe, prompt `Say OK.`, comparing cached system prompt size:

```
off: cache_creation=3580  cache_read=13026  total=16606
on:  cache_creation=3606  cache_read=13026  total=16632
```

**+26 tokens.** Because all four tools carry `shouldDefer:!0` (offsets 164040945, 164043068,
164047290) they are *deferred*: only the name is in context until the model runs `ToolSearch`. The
"it will bloat every prompt" objection is refuted at 26 tokens — and the *adoption* problem is real
instead (see §Adversarial 1).

**Probe footprint:** none in any live store. `~/.claude/tasks/a03-probe` does not exist after the
runs (`ls -d`, measured) — `--setting-sources ""` suppressed our SessionStart hooks and no task tool
was called. Cost of the whole probe set: ~$0.20.

---

## (c) Our five task hooks — which fire today

Registration read from `~/.claude/settings.json`
(`jq -r '.hooks | to_entries[] | …'`, measured):

| file | registered as | fires today? |
|---|---|---|
| `hooks/setup-task-symlinks.sh` (196 L) | `SessionStart *` | **YES** — every start, every project, every config dir |
| `hooks/task-mutation-index.sh` (35 L) | `PostToolUse TaskCreate\|TaskUpdate` | **NO** — the matcher names tools that do not exist in this build |
| `hooks/task-quality-gate.sh` (337 L) | `TaskCompleted *` | **effectively NO** — the event can only be raised by a `TaskUpdate` to `completed`, and it exits 0 immediately unless `team_name` is set |
| `hooks/task-completed-index.sh` (83 L) | **nothing** | **NO — orphaned.** It appears in no settings file (`grep` across the repo + both settings files: only its own header and docs). Its body duplicates `task-mutation-index.sh` plus an index refresh |
| `hooks/lib/task-helpers.sh` (261 L) | sourced by the three above | runs inside `setup-task-symlinks.sh` only |

So of ~912 lines of task machinery, **only `setup-task-symlinks.sh` + `task-helpers.sh` execute**,
and their whole output (`TASKS.md`, `_summary.json`, `.claude-tasks/_current`) is consumed by nobody.

**`TaskCreated` is a registered-nowhere event that the binary raises.** The full event list in the
binary (offset 156773548 / 157879970) contains both `TaskCreated` and `TaskCompleted`; our
`settings.json` registers 21 events and `TaskCreated` is not among them. Its payload schema (offset
157890649, same shape for both):

```
{session_id, transcript_path, cwd, prompt_id?, hook_event_name:"TaskCreated"|"TaskCompleted",
 task_id, task_subject, task_description?, teammate_name?, team_name?}
```

`session_id` **and** `task_id` in one payload is exactly the attribution join we lack. This is one of
the 15 unregistered events already filed as `8439a41639b3`.

🚨 **`TaskCreated` is a BLOCKING event.** `ovn=["Stop","TeammateIdle","TaskCreated","TaskCompleted"]`
(offset 157431448) is the set that gets ` hook feedback:\n` treatment, and `TaskCreate`'s own body
(offset 164041206) does `if(D.length>0) throw await p9t(xE(),C,…)` — **a blocking TaskCreated hook
DELETES the just-created task and throws.** Any sidecar hook must `exit 0` unconditionally.

Also measured: **`_summary.json` occurs 0 times in the binary.** The summary file is entirely our
invention, written only by `regenerate_summary` in `task-helpers.sh`. Anything that reads it is
reading a cache only our own hooks refresh.

---

## (d) The store census — a graveyard, and a shared one

All counts from a Python walk of `~/.claude/tasks` (measured, 2026-09-08).

```
list dirs                     994   (+1 non-dir: .sweep-stamp)
   of which EMPTY              561   (56%)
   of which hold exactly 1 file 362  (mostly just _summary.json)
   doubled `X-X` (repo==branch) 219
   UUID-named                    10
task JSON files              1,527  (+431 _summary.json)
status: completed              803
        pending                212
        in_progress             81
OPEN (pending+in_progress)     293   across 58 lists
   >30 d old                   248   (85%)
   >90 d old                    89
   >180 d old                   40
   median age                 41.2 d      oldest 228.6 d (2026-01-23, "Install iTerm2 via Homebrew")
```

Top lists by open count: `claude-infrastructure-main` **66** · `reso-management-app` 23 ·
`claude-infrastructure` 13 · `doc_classifier` 8 · `improve-exec` 8 · `shadcn-pivot-data-table-example` 8 ·
`t10v2` 8 · `wt-cc-121729-2026-cc-121729-2026` 8.

`claude-infrastructure-main` alone: 186 items on disk, 120 completed, 54 pending, 12 in_progress,
median open age 32.6 d, 35 of 66 older than 30 days.

### The store IS already shared across accounts

```
$ python3 -c "import os;print(os.path.realpath('…/tasks'))"   # per config dir
~/.claude/tasks             → /Users/chrisren/.claude/tasks
~/.claude-secondary/tasks   → /Users/chrisren/.claude/tasks
~/.claude-tertiary/tasks    → /Users/chrisren/.claude/tasks
~/.claude-quaternary/tasks  → /Users/chrisren/.claude/tasks
~/.claude-next/tasks        → /Users/chrisren/.claude/tasks
```

All five report the same 992 entries. `task-helpers.sh:14-17` already anticipates this ("The mirror
now symlinks tasks/ so both spellings land in the same place — deriving it anyway keeps these hooks
correct if that ever stops being true").

### …but the INDEX is not, and account 1's is nearly empty

`tasks-index.json` is a **real file per config dir** (measured `ls -l`):

| config dir | bytes | indexed lists | distinct project paths |
|---|---|---|---|
| `~/.claude` | **580** | **2** | 2 |
| `~/.claude-secondary` | 25,511 | 91 | 87 |
| `~/.claude-tertiary` | 40,598 | 145 | 137 |
| `~/.claude-quaternary` | 25,061 | 90 | 83 |

`~/.claude/tasks-index.json` maps only `renchris-marquee` and `/private/tmp`. Consequence, measured:
**open items in INDEXED lists = 0; open items in UNINDEXED lists = 293.** `find_active_list($proj)`
in `task-helpers.sh` refuses a global fallback by design, so **on account 1 every
claude-infrastructure session's active-list lookup returns NONE** and `setup-task-symlinks.sh` falls
through to the `$TASK_LIST_ID` arm. Same session, different account, different answer. (One index key
is also malformed — `"renchris-marquee-HEAD\nnogit"`, a literal newline from `_cc_tlid`'s command
substitution — and can never match the sanitized directory name `renchris-marquee-HEAD-nogit`.)

### The fragmentation cause

`~/.zshrc:88`:

```bash
_cc_tlid() { echo "$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")-$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo nogit)"; }
```

In a linked worktree `--show-toplevel` is the *worktree* path, so a wave of six worktrees mints six
lists. 219 of 994 dirs have the `X-X` shape that this produces when basename == branch
(`wt-311062ef8e9a-wt-311062ef8e9a`, `drain-loop-w4-drain-loop-w4`, …).

### And `TASKS.md` has no reader

`grep -rn "TASKS.md\|\.claude-tasks" hooks bin scripts commands skills` returns **only the four
generators plus two worktree-GC comments** (measured). The live artifact is 102,725 bytes
(`/Users/chrisren/Development/claude-infrastructure/.claude-tasks/TASKS.md`) and the only pointer to
it is a SessionStart `additionalContext` string that says *"TASKS.md ready."* — a pointer nobody
follows, which is the same shape as the `--why <topic>` tier this repo already calls *"a deletion
wearing a pointer's clothes"*.

---

## (e) `OPEN_TASKS_MINE` — the design

### The attribution problem, measured

`TaskCreate`'s body sets **`owner: void 0`** (offset 164041206). The `owner` field is the
Agent-Teams *assignee* (observed values: `lead`, `live-azure-lead`, `channels-s4`, `reducer-s5`), not
a creator. No task JSON carries a session id by construction. Today **10 of 293 open items (3.4%)**
carry `metadata.owner_session` — and all ten were written *by hand* through Bash by this wave's lead
(`~/.claude/tasks/claude-infrastructure-main/200.json`–`207.json`, mtime 16:41 today, metadata
`{"owner_session":"b418b97a-…","programme":"exhaustive-drive-2026-09-08"}`).

`TaskCreate`'s input schema **does** accept `metadata` (it is the 4th destructured arg), so the model
*can* self-attribute — but that is model-discretionary and **fails open**: an unattributed task is
invisible to the rung, i.e. the mechanism is silent in exactly the state it exists to catch.

**The deterministic channel is the `TaskCreated` hook**, whose payload carries `session_id` and
`task_id` together. Sidecar, written by us, never by the model:

```
~/.claude/tasks/<listId>/.owners/<taskId>   →  one line: "<session_id>\t<iso ts>\t<cwd>"
```

Rules: `exit 0` unconditionally (a non-zero exit deletes the task); no `jq` dependency beyond what
every other hook already assumes; sidecar for a task that is later deleted is harmless.

### The term

In `scripts/wrap-ledger.sh`, mirroring `count_filed_undriven()` (lines 807-836) exactly — same
fail-open discipline, same `SID`/`SID_SRC` plumbing, same `--machine` emission:

```
OPEN_TASKS_MINE = | { t ∈ tasks(list = $CLAUDE_CODE_TASK_LIST_ID, else .claude-tasks/.active-list-id)
                    : t.status ∈ {pending, in_progress}
                      ∧ owner_of(t) == $SID } |
where owner_of(t) = read(.owners/<t.id>)  ?? t.metadata.owner_session  ?? ⊥
```

Emission alongside `FILED_MINE`/`UNCONVICTED_MINE`:
`OPEN_TASKS_MINE=<n>`, `OPEN_TASKS_SRC=skip|none|error|<SID_SRC>`.

Ladder position: fold into **🔧**, at the same rank as `FILED_MINE`, above 🚀/👤 and below ⛔/📤.
Cure line, in the shape wrap-ledger already uses at :1755:

> `🔧 Loose ends — N task(s) you opened this session are still pending
> (TaskList, or jq over .claude-tasks/_current/); finish each and TaskUpdate it to completed, or
> TaskUpdate it with an owner so it is someone's.`

Consumption in `hooks/completion-assert.sh`: one more `lfield` read beside
`FILEDM="$(lfield FILED_MINE)"` at :572 and `UNCONV="$(lfield UNCONVICTED_MINE)"` at :583 — the hook
already **consumes** the ledger's counts and never re-derives them (`make-the-actuator-the-arbiter`),
so this is a three-line change plus its assertion arm.

Cost, measured in the live store: **73 ms** for `jq -s` over all 186 raw JSONs of
`claude-infrastructure-main`; **10 ms** to read `_summary.json`. Read the RAW files — the summary is
only fresh if our own hooks ran, and the whole point of the term is to be true when they did not.

### The `TaskCompleted` hook's role

`TaskCompleted` fires on the transition to `completed`. It is the natural place to **delete the
sidecar** (keeping `.owners/` bounded) and to refresh the summary — which is what the orphaned
`task-completed-index.sh` already does, minus the sidecar. Register that file (it is written, tested
in shape, and dead) rather than writing a new one. Note the sequencing constraint: `task-quality-gate.sh`
is already on `TaskCompleted` and **can block** — put the sidecar-delete hook *after* it, or make it
independent of the gate's verdict.

### Failure direction, stated

- **Session-scoped (recommended).** Errs toward **SILENCE**: a task opened by a predecessor session
  and inherited across a `/handoff` or `--recycle` is invisible to the successor's rung. Mitigation:
  the sidecar can carry a `programme` tag and the term can widen to it when
  `dod-persist` says the successor inherited the same frozen DoD — but that is a second increment,
  not this one.
- **List-scoped (rejected).** Errs toward **NOISE**, catastrophically: 66 open items in
  `claude-infrastructure-main`, 35 of them >30 days old, would make the term non-zero at *every*
  close of *every* session in this repo, forever. That is the `alarm-polarity-and-attention-budget`
  and `fail-safe-default-mimics-the-healthy-state` failure the house has already paid for twice.
- **Model-set metadata only (rejected).** Errs toward **silence and unfalsifiability**: 3.4%
  coverage today, and no way to distinguish "no open tasks" from "the model did not tag them".

---

## (f) Fleet-wide enablement — three paths, one recommendation

| path | reach | classifier surface | verdict |
|---|---|---|---|
| `~/.zshrc` launcher env prefix (lines 173, 175, 498, 501 already carry `CLAUDE_CODE_TASK_LIST_ID`) | sessions started via `claude` / `claude-nextN` / `handoff-fire` panes | **`autoMode.soft_deny` "Unauthorized Persistence: modifying shell profiles"** | **NO** — and it misses `claude -p`, daemon/`--bg`, cron and resumed sessions whose env was lost (`resumed-session-loses-terminal-identity`) |
| `settings.json` `env` block, per config dir | **every** session on that config dir, including headless `-p`, `--bg` and daemon | `autoMode.soft_deny` "Self-Modification: modifying the agent's own configuration, settings, or permission files" ⇒ the existing **c10 migration** convention (`migrations/NNNN-*.sh`, `# migration-class: c10`) | **YES** — measured to work (probe C) |
| `handoff-fire.sh` env | fired panes only | none | no — strictly narrower than the launcher |

**Recommendation: one c10 migration adding `"CLAUDE_CODE_ENABLE_TODO_TOOLS": "1"` to the `env` block
of all four `settings.json` files.** They are **four separate inodes with four different sizes**
(41,763 / 38,759 / 40,946 / 38,803 — measured `stat -f %i`), so the migration must write all four;
writing only `~/.claude/settings.json` enables the tools on one account of four, which is precisely
the cross-account asymmetry the `tasks-index.json` census already shows this machine produces by
accident.

The `env` mechanism is proven on this exact key shape: `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS: "1"`
already lives in that block and the binary reads it through the same typed-env accessor (`a.X`) as
`CLAUDE_CODE_ENABLE_TODO_TOOLS`, and probe C confirmed the string `"1"` coerces to the `===!0`
comparison the gate makes.

**Do NOT add `CLAUDE_CODE_ENABLE_TASKS`.** It is a kill switch; setting it false swaps the disk-backed
Task family for the in-memory `TodoWrite`, which writes nothing a Stop hook can read.

**De-fragmentation, same migration or the next.** `_cc_tlid()` at `~/.zshrc:88` should drop the
branch component and resolve the *main* worktree's toplevel (`git rev-parse --path-format=absolute
--git-common-dir` → its parent) so every worktree of one repo shares one list. That edit is in the
shell profile and therefore hits the same soft_deny; it belongs in a c10 migration too, and it is
**strictly optional for the rung** (the rung is session-attributed, so it works on a fragmented
store; the fragmentation hurts *humans* reading the board, not the mechanism).

---

## Adversarial pass — what I did not want to be true

**1. Enabling the tool does not make the model use it.** All four carry `shouldDefer:!0`, so they
arrive as *deferred* names and the model must `ToolSearch` before it can call one. That is why the
context cost is only 26 tokens — and it is also why enablement alone will produce **zero** tasks.
The rung would then be permanently 0: a term that never fires, carrying exactly as many bits as one
that always does. **Enablement must ship with the CLAUDE.md clause that names the tools** (the
operator's step 2, "multiple todo items → track them in a Shared Task List"), or A03 lands a switch
and nothing else. This is the single largest risk in this axis and it is not measurable until after
the flip; the falsifier is `count(tasks created after the migration sha) > 0 within 48 h`.

**2. Four accounts now write one directory.** Because all four `tasks` paths are one inode and the
list id is `$CLAUDE_CODE_TASK_LIST_ID`, two sessions on two accounts in the same repo+branch will
allocate `<N>.json` from the same highwatermark. The binary does hold a mutex on that path
(`nm(i,"[Tasks] resetTaskList")`, `claimTaskWithBusyCheck` at offset 159802755) so the *file* write is
guarded — but I did **not** measure concurrent allocation and cannot say the id allocation is
atomic across processes. Today this is latent (tools off); the migration makes it live across
4 accounts × up to 12 sessions. **Unmeasured. Probe before flipping:** two `--print` sessions with
the same `CLAUDE_CODE_TASK_LIST_ID` creating tasks simultaneously into a throwaway
`CLAUDE_CONFIG_DIR`, then check for a lost/overwritten `<N>.json`.

**3. `_summary.json` is 250,636 bytes for 186 tasks and is regenerated on every mutation.**
`hooks/task-mutation-index.sh` runs `regenerate_summary` on every `TaskCreate`/`TaskUpdate`
PostToolUse — a hook that currently never fires and, after the flip, will fire on every task edit,
rewriting a quarter-megabyte file and a 100 KB `TASKS.md` each time. That is a new per-tool-call cost
on a Stop-adjacent path this repo already measured as latency-critical. Failure direction: **noise
and latency, not silence** — but `setup-task-symlinks.sh` already carries a whole essay about being
killed by its own `timeout: 5`, and this reintroduces the same class one layer down.

**4. The rung can be laundered.** `TaskUpdate` can set `status: completed` without doing the work, and
that is a one-token discharge — cheaper than the work, exactly like the "filing was the compliance
action" defect `FILED_MINE` was built to fix (`wrap-ledger.sh:790` comment block). The rung should
therefore be a **🔧 that names the items**, not a gate that anything discharges on a written row; and
the `TaskCompleted` hook is the place to record the completion *with its session*, so a future census
can measure the discharge rate. Stated plainly: this rung errs toward being **gameable**, and the
counter-measure is a measurement, not a stronger gate.

**5. Did I check whether the operator already has a working board somewhere else?** Yes —
`cc-backlog` (`~/.claude/autonomy/backlog.jsonl`) and `cc-decide` are the live, drained, hook-read
stores. The task store is a *third* queue. The honest risk is that A03 revives a queue that lost to
`cc-backlog` on merit. The counter-argument is the operator's own words ("track them in a **Shared
Task List**") plus one structural difference `cc-backlog` cannot supply: `blocks`/`blockedBy` on every
task JSON, i.e. a dependency graph, which is what a *wave* needs and a flat backlog does not have.
I flag this as a genuine open question, not a settled one.

---

## Open questions

- Does the id allocator survive 4-account concurrency on one shared `tasks/` inode? (unmeasured; probe in Adversarial 2)
- Why is `~/.claude/tasks-index.json` 2 entries when its three siblings hold 90-145? It was rewritten today 06:24; `store_sweep`'s prune only deletes entries whose dir is gone, and 994 dirs exist. Something truncated or re-initialised it.
- Is `TaskCompleted` raised for a `TaskUpdate` that sets `status:"completed"`, or only via a teammate flow? (`executeTaskCompletedHooks` exists at offset 70316779; I did not trace its call site.)
- Should the rung widen from session to *programme* across a handoff chain, and if so does `dod-persist`'s repo-keyed frozen DoD already carry the join key?

---

## Provenance

Every command in this report was run read-only. The only writes this session made anywhere are this
file and the three `--print` probes' own transcripts under `/tmp/a03-probe`'s project root. No repo
file, hook, setting, backlog row, decision packet, task or transcript was edited; nothing was
committed; no process was killed.
