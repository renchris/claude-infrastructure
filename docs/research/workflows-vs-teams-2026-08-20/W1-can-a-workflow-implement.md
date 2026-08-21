# W1 — Can a Workflow agent actually implement?

**Axis:** settle by RUNNING one, not by reading.
**Method:** 2.1.220 bundle read (`~/.claude-220/…/bin/claude.exe`) + two real headless workflow runs
in throwaway git repos under `/tmp`. Every capability claim below is `MEASURED` unless labelled.
**Box:** M1 Max, 10 cores, 64 GiB, CC 2.1.220 (`CLAUDE_CODE_EXECPATH` = `~/.claude-220/…/claude.exe`),
`CLAUDE_CONFIG_DIR=~/.claude-secondary`, 2026-08-20.

---

## 1. Verdict (5 lines)

1. **YES — a workflow `agent()` can implement.** It gets *every* tool except three, runs at
   `acceptEdits`, and in a live run two agents each wrote a script + a bats test, `chmod +x`'d it, and
   **committed** — in ~2 minutes, in isolated worktrees, with no operator involvement.
2. **But its output lands nowhere the parent can reach.** With `isolation:'worktree'` the work is on a
   per-agent branch in a per-agent worktree; **no agent could see any sibling's file** (`sees_sibling: no`,
   2/2), the unisolated verifier on `main` saw **an empty `src/`**, and **nothing merges anything**.
3. **Without isolation, N concurrent implementers share one tree** — the exact collision the isolation
   option exists to prevent. There is no third setting.
4. **A failed agent leaves its half-written files behind and the parent is not told where.** The result
   drops to `null`, the worktree is *preserved*, and the returned object contains no path. No rollback.
5. **On THIS box the documented "auto-removed if unchanged" never fires** — our `WorktreeCreate` hook makes
   every agent worktree `hookBased:true`, which skips the removal branch entirely. Verified with a
   provably-unchanged agent: worktree + branch survived. So *every* isolated agent leaks one worktree +
   one branch into the operator's shared `~/Development/.worktrees` pool, forever.

**So: a workflow can WRITE code; it cannot LAND code.** The standing rule survives — but its stated reason
("subagents are for research only") is a *false capability claim* and should be replaced by the true one:
the write is not the hard part, the merge/gate/land is, and a workflow has no organ for it.

---

## 2. Tool surface — MEASURED

### 2.1 What the bundle defines

`LC_ALL=C grep -a -o -b 'workflow-subagent' ~/.claude-220/node_modules/@anthropic-ai/claude-code/bin/claude.exe`
→ 2 hits (196150320, 234435062). Reading the definition at 234435062, verbatim:

```js
ZHs = {
  agentType: "workflow-subagent",
  whenToUse: "Internal subagent for workflow script orchestration.",
  tools: ["*"],
  disallowedTools: [EB, Go, dk],
  source: "built-in", baseDir: "built-in",
  getSystemPrompt: () => tj_
}
```

Resolving the three minified identifiers (`strings -a -n 4 … | grep -aoE '\b(EB|Go|dk)=…'`):

| id | value |
|---|---|
| `EB` | `"SendUserMessage"` |
| `Go` | `"Agent"` |
| `dk` | `"Workflow"` |

**A workflow agent gets every tool except SendUserMessage, Agent and Workflow.**
It therefore **has Write, Edit, Bash (⇒ git), Read, WebFetch, MCP-via-ToolSearch, EnterWorktree, TaskStop**.
It **cannot** spawn an Agent, **cannot** start a nested Workflow, and **cannot** speak to the operator.

### 2.2 The `agentType` escape hatch does NOT restore fan-out

Code at 234418212 resolving `opts.agentType`:

```js
let Wr = [...yr.disallowedTools ?? [], ...ZHs.disallowedTools ?? []]
```

The workflow-subagent denial list is **unioned onto** any custom agentType. So even
`agent(p, {agentType:'general-purpose'})` — whose own definition is `tools:["*"]` with **no**
`disallowedTools` — still cannot call Agent or Workflow inside a workflow.
**A workflow is structurally one level deep. It cannot recruit.**
(`workflow()` inline nesting exists but is capped at one level: *"Nesting is one level only: workflow() inside a child throws."*)

Unknown agentType throws, listing the registry:
`agent({agentType}): agent type 'X' not found. Available agents: …`
Permission-denied agentType throws:
`… is denied by permission rule 'Agent(X)' from <source>.`

### 2.3 Comparison table (all rows read out of the 2.1.220 bundle)

| | workflow `agent()` | `Agent({name})` teammate | unnamed `Agent()` — `general-purpose` | unnamed `Agent()` — `Explore` |
|---|---|---|---|---|
| tool set | `tools:["*"]` | built from `rootToolSurface` (the lead's own surface) | `tools:["*"]` | `tools:["*"]` |
| denied | **SendUserMessage · Agent · Workflow** | — | *(none in the definition)* | **Agent · Artifact · ExitPlanMode · Edit · Write · NotebookEdit** |
| can Write/Edit? | **yes** | yes | yes | **no — read-only** |
| can Bash/git? | **yes** | yes | yes | yes |
| can fan out further? | **no** | yes | yes (bounded by `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`, =1 here) | no |
| can reach the operator? | **no** | yes | via its return only | via its return only |
| permission mode | **forced `acceptEdits`** (see §2.4) | inherits | inherits | inherits |

Command behind the last two columns:
`python3 -c "…re.finditer(rb'agentType:\"general-purpose\"' / rb'agentType:\"Explore\"' …)"` over the bundle;
`Explore` is `{agentType:"Explore", disallowedTools:[Go,qI,h2,fl,nu,OC], model:"inherit", omitClaudeMd:true}`
with `qI="Artifact"`, `h2="ExitPlanMode"`, `fl="Edit"`, `nu="Write"`, `OC="NotebookEdit"`.
Teammate: `{… agentType:"teammate", isBackgroundAgent:true, tools: rootToolSurface …}` at 234619219.

### 2.4 Permission mode is NOT inherited — it is overridden to `acceptEdits`

Bundle, 234418212:

```js
let at = {...ze, mode: Ue.permissionMode ?? "acceptEdits"}
```

`ze` is the parent's `toolPermissionContext`; the **mode** is replaced. `workflow-subagent` declares no
`permissionMode`, so **every workflow agent runs at `acceptEdits` regardless of the parent's mode.**

**Measured, live (run B).** Parent launched *without* `--dangerously-skip-permissions`, in default mode,
with a deliberately narrow allowlist:

```
--allowedTools "Workflow,TaskGet,TaskList,Bash(sleep:*)"
```

The child agent was asked to (1) use the **Write tool** and (2) use the **Bash tool** for
`echo BASH_OK > …`. Result returned by the workflow:

```json
{"write":"SUCCEEDED","write_err":"","bash":"SUCCEEDED","bash_err":""}
```

and both files exist on disk (`permprobe-write.txt` = `WRITE_OK`, `permprobe-bash.txt` = `BASH_OK`).
**The child's Bash ran a command the parent's own allowlist would have refused.** The `acceptEdits`
override explains the Write half from code; the Bash half is MEASURED but its mechanism is INFERRED
(no control was run with an explicit `deny` rule — see §7).

⚠️ One counterweight, also from the bundle: when the parent's mode **is** `auto` (our fleet default), each
agent prompt is first run through a safety classifier (`if (he.mode !== "auto") return false;` … `Ipd({prompt, schemaJson, agentType, …})`)
and can be refused with `[label] blocked by safety classifier: <reason>`. That gate exists **only** in
`auto` mode — i.e. exactly not in the headless/cron shape where nobody is watching.

---

## 3. THE EXPERIMENT — verbatim

Throwaway repo, created fresh (`/private/tmp/w1lab`, `git init -b main`, one seed commit `08a86b6`).
Never this repo, never a live worktree.

### 3.1 The workflow script, verbatim (`/private/tmp/w1lab-wf/impl-probe.js`)

```js
export const meta = {
  name: 'w1-impl-probe',
  description: 'Probe whether workflow agents can implement, isolate and commit',
  phases: [ { title: 'Implement' }, { title: 'Verify' } ],
}

const OUT = '/private/tmp/w1lab-out'

const REPORT = (label, sibling) => `
When finished, run these bash commands and write the answers as ONE single-line JSON object to ${OUT}/${label}.json
(create the directory with mkdir -p first; write it with a bash heredoc, NOT the Write tool, so the path is exact):
  pwd                                   -> key "pwd"
  git rev-parse --show-toplevel         -> key "toplevel"
  git branch --show-current             -> key "branch"
  git rev-parse --git-common-dir        -> key "common_dir"
  git rev-parse --git-dir                -> key "git_dir"
  ls -1 src 2>/dev/null | tr '\\n' ','  -> key "src_listing"
  git log --oneline -1                  -> key "head"
  git status --porcelain | wc -l        -> key "dirty_count"
  test -f src/${sibling}.sh && echo yes || echo no  -> key "sees_sibling_${sibling}"
  git worktree list | wc -l             -> key "worktree_count"
Then output that same JSON as your final text response and nothing else.`

phase('Implement')

const impl = await parallel([
  () => agent(
    `You are implementer A working in the CURRENT working directory, which is a git repository.
1. Create src/adder.sh: a POSIX sh script that takes two integer arguments and echoes their sum. chmod +x it.
2. Create tests/adder.bats with a bats test asserting "src/adder.sh 2 3" outputs 5.
3. Commit with: git add -A && git -c user.email=a@w1.local -c user.name=implA commit -m "feat: adder"
` + REPORT('implA', 'multiplier'),
    { label: 'impl-A', phase: 'Implement', isolation: 'worktree' }),

  () => agent(
    `You are implementer B working in the CURRENT working directory, which is a git repository.
1. Create src/multiplier.sh: a POSIX sh script that takes two integer arguments and echoes their product. chmod +x it.
2. Create tests/multiplier.bats with a bats test asserting "src/multiplier.sh 2 3" outputs 6.
3. Commit with: git add -A && git -c user.email=b@w1.local -c user.name=implB commit -m "feat: multiplier"
` + REPORT('implB', 'adder'),
    { label: 'impl-B', phase: 'Implement', isolation: 'worktree' }),

  () => agent(
    `You are implementer C working in the CURRENT working directory, which is a git repository.
Create src/orphan.sh containing exactly: echo orphan
Do NOT commit anything. Leave it uncommitted.
` + REPORT('implC', 'adder'),
    { label: 'impl-C-doomed', phase: 'Implement', isolation: 'worktree' })
    .then(() => { throw new Error('W1: simulated stage failure AFTER agent C wrote its files') }),
])

phase('Verify')

const verify = await agent(
  `You are the verifier. You are NOT isolated. In the CURRENT working directory:
Run and report the raw output of each: pwd ; git rev-parse --show-toplevel ; git branch --show-current ;
ls -1a src ; ls -1a tests ; git log --oneline --all ; git branch -a ; git worktree list ; git status --porcelain .
Then answer in one line: can you see src/adder.sh and src/multiplier.sh from here? yes or no.
Write the same report to ${OUT}/verify.txt with a bash heredoc, then output it as your final text.`,
  { label: 'verify', phase: 'Verify' })

const typed = await agent(
  `Reply with exactly the word PONG and nothing else.`,
  { label: 'agentType-probe', phase: 'Verify', agentType: 'general-purpose' })

return {
  impl_results: impl,
  impl_nulls: impl.filter(x => x === null).length,
  verify,
  agentType_probe: typed,
}
```

### 3.2 The driver, verbatim (`/private/tmp/w1lab-wf/run-main.sh`)

```zsh
#!/bin/zsh
set -u
mkdir -p /private/tmp/w1lab-out
cd /private/tmp/w1lab || exit 1

export CC_MECH_MAX=0
export CC_SHIP_FLOOR_MAX=0
export CLAUDE_CONTINUE_MAX=1

PROMPT='Call the Workflow tool ONCE with {"scriptPath": "/private/tmp/w1lab-wf/impl-probe.js"}.
It returns immediately with a taskId. Then poll: call TaskGet on that taskId, and between polls run "sleep 20" via Bash.
Keep polling until the task status is completed or failed (up to 25 polls). Do NOT end your turn before then.
When it finishes, print the FULL raw workflow result verbatim, then print the output of this one Bash command:
  git -C /private/tmp/w1lab worktree list; echo ---; git -C /private/tmp/w1lab log --oneline --all; echo ---; git -C /private/tmp/w1lab branch -a; echo ---; ls -1aR /private/tmp/w1lab
Print nothing else.'

exec "$HOME/.claude-220/node_modules/.bin/claude" -p "$PROMPT" \
  --dangerously-skip-permissions \
  --output-format text
```

Fired with `nohup zsh /private/tmp/w1lab-wf/run-main.sh > /private/tmp/w1lab-out/main-run.log 2>&1 &`.
(Note: `~/bin/claude-latest` is pinned to **2.1.114** and would have measured the wrong binary — the
2.1.220 eval binary had to be named explicitly. `~/.zshrc:496` pins the same path.)

### 3.3 Result — the workflow's own return value, verbatim

```json
{"impl_results":[
 "{\"pwd\":\"/Users/chrisren/Development/.worktrees/w1lab-wf_956fa9d7-bda-1\",\"toplevel\":\"/Users/chrisren/Development/.worktrees/w1lab-wf_956fa9d7-bda-1\",\"branch\":\"wf_956fa9d7-bda-1\",\"common_dir\":\"/private/tmp/w1lab/.git\",\"git_dir\":\"/private/tmp/w1lab/.git/worktrees/w1lab-wf_956fa9d7-bda-1\",\"src_listing\":\"adder.sh,\",\"head\":\"63f0483 feat: adder\",\"dirty_count\":\"0\",\"sees_sibling_multiplier\":\"no\",\"worktree_count\":\"4\"}",
 "{\"pwd\":\"/Users/chrisren/Development/.worktrees/w1lab-wf_956fa9d7-bda-2\",…,\"branch\":\"wf_956fa9d7-bda-2\",\"src_listing\":\"multiplier.sh,\",\"head\":\"900760b feat: multiplier\",\"dirty_count\":\"0\",\"sees_sibling_adder\":\"no\",\"worktree_count\":\"4\"}",
 null],
 "impl_nulls":1,
 "verify":"… ANSWER: no — src/adder.sh and src/multiplier.sh are NOT visible from here. …",
 "agentType_probe":"PONG"}
```

and, appended to stdout by the harness:

```
Failures: `parallel[2] failed: W1: simulated stage failure AFTER agent C wrote its files`
```

### 3.4 Result — the disk, independently

| Question | Answer | Command |
|---|---|---|
| Did the files get written? | **Yes.** `src/adder.sh` + `tests/adder.bats` in wt-1; `src/multiplier.sh` + `tests/multiplier.bats` in wt-2; `src/orphan.sh` in wt-3 | `ls -1aR /Users/chrisren/Development/.worktrees/w1lab-wf_956fa9d7-bda-{1,2,3}` |
| Did git ops work? | **Yes.** `63f0483 feat: adder`, `900760b feat: multiplier`, both on their own branch, both `dirty_count:0` | `git -C <wt> log --oneline -3` |
| Did agents see each other? | **No, 2/2.** `sees_sibling_multiplier:"no"`, `sees_sibling_adder:"no"` | in the returned JSON above |
| Did the parent's tree get the work? | **No.** `ls -1a /private/tmp/w1lab/src` → `.` `..` only; `main` still at `08a86b6` | the verifier's own run, reproduced in `verify.txt` |
| How long? | worktrees created 19:19:00 / :03 / :05; A reported 19:20, B 19:22, verify 19:23, run closed 19:24. **~6 min for 5 agents including one stage failure.** | `~/.claude/logs/worktree-lifecycle.log` + `ls -la /private/tmp/w1lab-out` |
| Did our hooks reach the agents? | **Partly yes** — the repo carries `refs/checkpoints/w1lab-wf_956fa9d7-bda-{1,3}/…` and commits `checkpoint: PostToolUse count=10/15/20/30`, i.e. our **PostToolUse** checkpoint hook fired *inside the agents' worktrees*. The **WorktreeCreate** hook fired too (3 log lines). | `find /private/tmp/w1lab/.git/refs -type f`; `grep w1lab ~/.claude/logs/worktree-lifecycle.log` |
| Is there an audit trail? | **Yes, on disk** — 5 × `agent-*.jsonl` + `agent-*.meta.json` + `journal.jsonl`, 532 K, under `~/.claude-secondary/projects/-private-tmp-w1lab/<sid>/subagents/workflows/wf_956fa9d7-bda/` | `find … -newermt '2026-08-20 19:00'`; `du -sh` |

---

## 4. `isolation:'worktree'` — the crux nobody had measured

### 4.1 What the model is told

The Workflow tool's own doc (extracted at bundle offset ~234455400):

> `opts.isolation: 'worktree'` runs the agent in a fresh git worktree — EXPENSIVE (~200-500 ms setup + disk
> per agent), use ONLY when agents mutate files in parallel and would otherwise conflict; **the worktree is
> auto-removed if unchanged.**

The sentence slot immediately after that is an interpolated variable, and in this build it is **empty**
(`gj_=""`, `_j_="'worktree'"`, `yj_=""`, `bj_=""` at 234448797). `_j_` being just `'worktree'` is also why
`'remote'` is not offered — and the code confirms it hard:
`if (ae?.isolation === "remote") throw Error("agent({isolation:'remote'}) is not available in this build")`.

**There is no sentence anywhere about merging.** Because there is no merging.

### 4.2 What the agent is told (bundle, 234418295, verbatim)

```
You are running in an isolated git worktree at ${worktreePath} (a separate working copy of the repo).
Changes you make here do NOT affect the main working directory (${cwd}) or other agents. Work normally —
the worktree will be cleaned up automatically if you made no changes, or preserved for review if you did.
```

*"Preserved for review"* — by whom is not stated, and nothing in the harness reviews it.

### 4.3 Do two concurrent agents get separate trees? — **YES**

Naming: `let It = n ? `${n}-${ne}` : `wf-${ne}`` where `n` = workflow run id, `ne` = agent index.
Measured: `w1lab-wf_956fa9d7-bda-1`, `-2`, `-3`, branches `wf_956fa9d7-bda-1/2/3`, all sharing
`common_dir = /private/tmp/w1lab/.git`. Separate `git_dir`, separate index, separate HEAD. Genuine isolation.

🚨 **They are NOT created next to the repo.** The repo was `/private/tmp/w1lab`; the worktrees landed in
**`/Users/chrisren/Development/.worktrees/`** — the operator's shared pool. Cause: `isolation:'worktree'`
routes through the harness's normal worktree creation, which **fires our `WorktreeCreate` hook**
(`~/.claude/hooks/worktree-setup.sh`), whose generic branch is *"anything else: create a plain worktree
under ~/Development/.worktrees"*. Evidence:

```
[2026-08-20 19:19:00] [worktree-setup] generic worktree: /Users/chrisren/Development/.worktrees/w1lab-wf_956fa9d7-bda-1 (branch wf_956fa9d7-bda-1)
[2026-08-20 19:19:03] … -2 …
[2026-08-20 19:19:05] … -3 …
```

**A workflow fired from ANY repo on this box drops its agent worktrees into the shared pool the reaper and
the worktree sweeper police.**

### 4.4 Who merges them? — **NOBODY**

Nothing in the harness merges, cherry-picks, rebases or even *reports the branch names*. The return value
carries only what each agent chose to say in prose. The verifier stage — an unisolated agent on `main` —
literally could not see the work:

```
$ ls -1a src
.
..
ANSWER: no — src/adder.sh and src/multiplier.sh are NOT visible from here.
```

### 4.5 What happens to the worktree — the cleanup path, verbatim (bundle 234427099)

```js
finally {
  if (et) {
    let {worktreePath, worktreeBranch, headCommit, gitRoot, hookBased} = et
    try {
      if (!hookBased && headCommit && !await EYr(worktreePath, headCommit))
        await Bke(worktreePath, worktreeBranch, gitRoot, false, "workflow_tool")   // removeAgentWorktree
      else if (gitRoot)
        await Cpe(worktreePath, gitRoot)                                          // git worktree unlock
    } catch {}
  }
}
```

with

```js
function EYr(e,t){ let {dirty, commitsAhead} = await Yor(e,t); return dirty || commitsAhead > 0 }
function Cpe(e,t){ await Jn(git, [...,"worktree","unlock", e], {cwd:t}) }
```

So, exactly three outcomes:

| agent state | harness action | net effect |
|---|---|---|
| changed (dirty **or** ≥1 commit ahead) | `git worktree unlock` only | **worktree + branch preserved, forever, unreferenced** |
| unchanged **and** `hookBased:false` | `removeAgentWorktree` | worktree + branch removed |
| **`hookBased:true` (this box, always)** | `git worktree unlock` only | **worktree + branch preserved even when unchanged** |

🚨 **The documented "auto-removed if unchanged" is FALSE on this box**, because a `WorktreeCreate` hook is
configured and the create path then returns `{worktreePath, hookBased:true, headCommit}`
(*"Created hook-based agent worktree at: …"*, bundle 230519209), and `!hookBased` gates the whole removal
branch. The Agent tool's own isolation path has the same shape and says so out loud:
`Hook-based agent worktree kept at: ${lt}` (bundle 234680627).

**Positive control, run live (run B).** One agent, `isolation:'worktree'`, instructed to touch nothing inside
its worktree (its one write went to `/private/tmp/w1lab-out/`, outside):

```
$ git -C /Users/chrisren/Development/.worktrees/w2lab-wf_b06bc7b2-8ff-1 status --porcelain | wc -l
       0
$ git -C … log --oneline -1
cb5f35a chore: seed        # == the base commit; commitsAhead = 0
$ git -C /private/tmp/w2lab worktree list
/private/tmp/w2lab                                             cb5f35a [main]
/Users/chrisren/Development/.worktrees/w2lab-wf_b06bc7b2-8ff-1 cb5f35a [wf_b06bc7b2-8ff-1]
```

Provably unchanged; **still there.** `EYr` would have returned false; `hookBased` short-circuited it.

**Litter accounting for this axis alone:** 4 worktrees + 4 branches from 5 minutes of probing. Removed by
hand afterwards (`git worktree remove --force` ×4, then `worktree prune`); the pool is clean again — and
note `git worktree remove` does **not** delete the branch, so a real cleanup is two commands per agent.

---

## 5. What the parent must do

The Workflow tool's own first line: *"Workflows run in the background — this tool returns immediately with
a task ID, and a `<task-notification>` arrives when the workflow completes."*
`WorkflowOutput.status` is `"async_launched"`. So the shape is:

```
parent ── Workflow{script} ──▶ returns {taskId, runId, transcriptDir, scriptPath}   (immediately)
   │
   │   … N agents run in-process, no pane, no OS process, cap min(16, ncpu-2) = 8 here …
   │
   ◀── <task-notification> ── the script's `return` value, JSON-serialised, + a "Failures:" line
   │
   └── EVERYTHING ELSE IS THE PARENT'S.
```

Concretely, in a teams flow the lead reviews / merges / re-runs gates. In a workflow **there is no later
pipeline stage that can do it**, for a structural reason: a later stage is just another `agent()`, and an
`agent()` sees only its own cwd. A verifier stage on the main tree sees an empty tree (§3.4); a verifier
stage with its own `isolation:'worktree'` gets a *fourth* empty tree. The only actor with a view of all
branches is **the parent, after the run returns** — and to act it must:

1. discover the branch names (they are in **no** return field — you must `git branch --list 'wf_<runId>-*'` or
   read `worktree-lifecycle.log`);
2. merge/cherry-pick N branches itself, serialised, resolving conflicts;
3. run the gate — because **no agent ran the repo's gate over the merged result**; each ran, at most, its own tests
   in its own tree;
4. `git worktree remove --force` + `git branch -D` for each, or leak them.

That is precisely the lead's job in the Agent-Teams flow, minus the ability to talk to the workers while
they do it (no `SendMessage` in, no `SendUserMessage` out, no pane, no `shutdown_request`).

---

## 6. Failure handling — files, and the absence of rollback

Documented: *"A stage that throws drops that item to `null` and skips its remaining stages"*; for `parallel`,
*"A thunk that throws (or whose agent errors) resolves to `null` in the result array — the call itself never
rejects."*

**Measured, concretely.** Agent C wrote `src/orphan.sh`, did not commit, and its thunk then threw.

| | outcome |
|---|---|
| the return value | `impl_results[2] === null`, `impl_nulls: 1` — **no path, no branch, no worktree, no filename** |
| the operator-visible signal | one line: `` Failures: `parallel[2] failed: W1: simulated stage failure AFTER agent C wrote its files` `` — the message *I* wrote, not anything about state |
| the files | **still there**: `/Users/chrisren/Development/.worktrees/w1lab-wf_956fa9d7-bda-3/src/orphan.sh`, `git status --porcelain` → `?? mk.sh`, `?? src/` |
| the branch | `wf_956fa9d7-bda-3` still in `git branch -a` |
| rollback | **none exists.** The `finally` block (§4.5) has exactly two arms: remove-if-unchanged, or unlock. A *changed* worktree is never reverted, never stashed, never reported. |

Two further failure modes the same block governs, read out of the bundle:

- **stall**: `opts.stallMs` (undocumented, default `sj_ = 180000` ms) with up to `YSd = 5` stall-retries; a
  throttled response (no `stop_reason`, <50 output tokens, >½ the stall window) triggers a **45 s sleep +
  one retry**. Each retry re-enters the *same* worktree, on top of whatever the previous attempt left.
- **schema**: `agent({schema})` retries up to `aj_ = 5` times, then throws
  `StructuredOutput retry cap (5) exceeded`. Same disposition — files kept, item `null`.

**The safe/unsafe verdict:** as an implementation primitive this is *unsafe by omission*, not by malice.
Nothing is corrupted; but a partial write becomes an **orphan** — present on disk, absent from every return
value, attributable to no session, and (because `hookBased` defeats the auto-remove) never garbage-collected.
Compare a teammate: it has a pane you can look at, a `shutdown_request`, a registry row, and a lead holding
its branch name.

---

## 7. What I could NOT measure, and why

1. **The mechanism behind the Bash escalation (§2.4).** The Write half is explained by the
   `mode: … ?? "acceptEdits"` override in code. The Bash half is a measured *fact* (a command outside the
   parent's `Bash(sleep:*)` allow-rule ran) but I did **not** run a control with an explicit
   `permissions.deny` rule, so I cannot say whether a hard deny would also be bypassed. **Do not encode
   "workflow agents bypass deny rules" from this.** One more headless run with `--disallowedTools "Bash"`
   settles it.
2. **The `!hookBased` counterfactual on this box.** I proved the unchanged worktree survives *with* the hook.
   I did not run the same probe with `WorktreeCreate` removed from settings, because that is a live-fleet
   mutation and this axis is read-only on the fleet. The removal branch is therefore INFERRED-from-code, not
   observed. (It is a one-line `--settings` override to prove, on a throwaway settings file.)
3. **Concurrency at the cap.** I ran 3 concurrent agents, not 8. `min(16, max(2, ncpu-2))` with
   `sysctl -n hw.ncpu` = 10 ⇒ **8**, and the tool doc states the formula; both are QUOTED here, not re-measured.
   In particular I did **not** measure whether 8 concurrent `isolation:'worktree'` creations race the
   `WorktreeCreate` hook (the known `.git/config.lock` hazard for parallel automated worktree creation).
   **That is the single most decision-relevant thing left unmeasured on this axis.**
4. **Whether `SessionStart` hooks fire for a workflow agent.** I proved `PostToolUse` and `WorktreeCreate`
   do (checkpoint refs, lifecycle log). I did not instrument `SessionStart`/`Stop` — a workflow agent has no
   session, so the expectation is "no", but that is INFERRED.
5. **A repo-scale implementation.** The task was two ~15-line scripts. Nothing here says a workflow agent can
   carry a 500-LOC feature across 6 files with a real test suite; it says the *primitive* writes and commits.
   `CAN` is settled; `DOES-WELL-AT-SCALE` is not, and W1's evidence must not be quoted for it.
6. **Quota cost of this run.** Not attributed — two headless sessions on `~/.claude-secondary` overlapping a
   live fleet make per-run attribution unreliable. The landed 08-19 numbers (31,503 output tok / pp for a
   teammate vs 8,936 for in-process) stand unchallenged by anything here.

---

## 8. The decision this axis changes

**The rule survives. Its stated reason does not.**

Today's global `CLAUDE.md` says: *"Background subagents (no team_name) are for research/exploration only —
NEVER for code changes."* Read as a **capability** claim that is now **measured false**: a workflow agent has
Write, Edit, Bash and git, runs at `acceptEdits`, and committed working code unattended. A rule defended on a
false premise gets re-litigated every time someone reads the tool description — which is exactly the question
that produced this wave.

Replace the premise with the measured one:

> **A Dynamic Workflow can WRITE code but cannot LAND it.** Its agents cannot see each other, nothing merges
> their branches, no stage can run a gate over the merged result, a failure leaves orphaned files the return
> value does not name, and on this box every isolated agent permanently leaks a worktree + branch into the
> shared pool. Implementation ownership therefore stays with a unit that has a pane: a dispatched session, or
> a teammate under one.

Three concrete consequences:

1. **Do not lift the Agent-Teams / dispatched-session mandate for implementation waves.** The bottleneck the
   mandate protects is merge-review-gate-land, and a workflow has no organ for any of the four. (W1 speaks
   only to *this* reason; the quota, oversight and abort-path reasons are W-other axes and the 08-19 docs.)
2. **A workflow IS legitimate for the write half when a named owner takes the branches.** The honest shape is
   *fan-out-to-branches*: workflow writes N branches → **the parent session** discovers, merges serially,
   gates, lands, and cleans up. That is strictly better than N teammates only when the merge is trivial and
   the parent is already the lead. If anyone adopts it, the plan's Phase 0 must name the parent as the merge
   owner, because nothing in the harness will.
3. **🚨 File this as a live defect, not a footnote: `isolation:'worktree'` leaks unconditionally on this box.**
   Our `WorktreeCreate` hook makes every agent worktree `hookBased:true`, which (a) redirects it into
   `~/Development/.worktrees` regardless of which repo fired it, and (b) disables the harness's own
   auto-removal even for provably-unchanged agents. A single 8-wide workflow leaves 8 worktrees + 8 branches
   in the operator's shared pool with no session, no registry row and no reaper claim on them. Until that is
   fixed, **`isolation:'worktree'` should not be used from this box** — and the fix belongs in
   `worktree-setup.sh` / a `WorktreeRemove` hook, not in a doc.

---

### Provenance

| claim class | source |
|---|---|
| tool surface, disallow list, permission override, agentType union, cleanup `finally`, `EYr`/`Cpe` semantics, `hookBased` gate, `'remote'` throw, caps (`1000` agents, `4096` items, `5` stall retries, `5` schema retries, `180000` ms stall) | `~/.claude-220/node_modules/@anthropic-ai/claude-code/bin/claude.exe`, read with `python3` byte-slicing + `LC_ALL=C grep -a`; every negative grep positive-controlled (`agentType` → 10+ hits, `worktree` → 449 hits) |
| everything in §3, §4.3, §4.5-control, §6-measured-rows | two live headless runs, 2026-08-20 19:18–19:24, logs at `/private/tmp/w1lab-out/{main-run.log,perm-run.log}`, scripts at `/private/tmp/w1lab-wf/` |
| concurrency cap 8, in-process footprint, quota per unit, oversight matrix | QUOTED from `orchestration-units-2026-08-19.md`, `oversight-at-scale-2026-08-19.md`, `breaking-the-ceiling-2026-08-19.md` — not re-derived here |

**Fleet hygiene:** nothing live was killed, closed or torn down. This axis created `/private/tmp/w1lab`,
`/private/tmp/w2lab`, `/private/tmp/w1lab-wf`, `/private/tmp/w1lab-out`, two headless `claude -p` processes
(both exited), and 4 worktrees in `~/Development/.worktrees` — **all 4 removed afterwards**, pool verified
clean (`ls -d …/w1lab-* …/w2lab-*` → no matches). The `/private/tmp` labs are left in place as the evidence.
