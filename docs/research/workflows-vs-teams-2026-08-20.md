# Do Dynamic Workflows supersede the Agent-Teams implementation rule?

**Decision document.** 2026-08-20 · CC 2.1.220 · M1 Max, 10 cores, 64 GiB.
**Inputs:** the six measured axes + five adversarial verifier files in
[`docs/research/workflows-vs-teams-2026-08-20/`](workflows-vs-teams-2026-08-20/), built on the landed
2026-08-19 trio (`orchestration-units` `4a3bd3373` · `oversight-at-scale` `de3e82802` ·
`breaking-the-ceiling` `8b68f0861`).
**Labels on every claim:** **MEASURED** (someone ran it here) · **QUOTED** (verbatim from the 2.1.220
bundle or a live tool description) · **INFERRED** (read out of code, path not executed) · **UNKNOWN**.

---

## 1. THE ANSWER

**No — and the reason is not the one our rule gives. A workflow agent WRITES code perfectly well; it
cannot OWN code. Every act that turns a diff into a landed change — choosing merge order, gating the
merged result, tearing the worker down, and putting the write in a ledger — is keyed on an address a
workflow agent does not have, and nothing in the harness supplies one.**

Three lines under that, and each changes what you do:

- **One amendment is earned, in the opposite direction.** A wave's **read-only verification stage**
  should be a workflow, not a lead's good intentions: it is the stage a lead most often skips
  (MEASURED: 3 sampled Phase-0 rosters declared and never spawned; "Phase 0 says teammates" is ~60%
  predictive, 11 of 12 multi-phase plans kept implementation on the lead) and a `pipeline()` stage
  cannot be forgotten without editing a reviewable artifact.
- **Repair the mandate regardless of this verdict.** It commands `team_name`. **2.1.220's Agent tool
  has no such parameter**, and **0 of 1,251** Agent calls in a 14-day, 5-store, 3,164-file census used
  `team_name` alone. Both of its hard gates — the 250-line brief cap and the teammate model allowlist
  — measured **DEAD** when run head-to-head on the shape this runtime actually emits. That is a live
  regression with nothing to do with workflows and it is the most urgent item in this file.
- **Two of the five "workflows can't" claims this wave started with were refuted by running the
  probe.** A *running* workflow agent **is** addressable by raw `agentId` (MEASURED, n=2, in-band, and
  peer-to-peer), and `TaskStop` **does** abort a running workflow (MEASURED twice, independently). Any
  rule grounded on those two mechanisms would have been false within one day. Ground it on ownership
  of the tail instead — that is the part nothing refuted.

**The one-sentence form for `CLAUDE.md`:** *Workflow `agent()` is for work that ENDS AT A RETURNED
STRING. Implementation ends at a merge order, a land, a teardown and a ledger row — and a workflow
agent inherits the lead's session id and the lead's pane, so all four are keyed on an address it does
not own.*

---

## 2. THE CAPABILITY DIFF

Four units, over the nine axes that decide implementation. **M** = measured on this box this wave ·
**MS** = measured first-person (the measuring agent WAS the unit under test) · **Q** = quoted from the
2.1.220 bundle · **P** = prior landed measurement · **I** = inferred from code · **?** = UNKNOWN.

Column 3 = the workflow `agent()` inside a `Workflow({script})` run. Column 4 = a bare `Agent({})`
with no `name:` (in-process sidechain subagent), which is what today's rule actually means by
"background subagent".

| Axis | **Teammate** `Agent({name})` | **Workflow `agent()`** | **Unnamed `Agent({})`** | **Dispatched session** (`handoff-fire.sh`) |
|---|---|---|---|---|
| **Writes code?** | **YES** — 481 IMPL units / 1,169 in 30 d **(M, W4 §2.2)** | **YES** — `tools:["*"]`, denied only `SendUserMessage`·`Agent`·`Workflow` **(Q, 1 anchored hit each)**; runs at forced `acceptEdits` (`at={...ze,mode:Ue.permissionMode??"acceptEdits"}`) **(Q)**; a live run wrote a script + bats test, `chmod +x`, and **committed** — `63f0483 feat: adder`, `900760b feat: multiplier` **(M, W1 §3)**; 461 workflow agents wrote files in 30 d **(M, W4 §2.2)** | **YES** for `general-purpose` (`tools:["*"]`); **NO** for `Explore` (denies Edit·Write·NotebookEdit) **(Q, W1 §2.3)**; 84 IMPL units / 694 **(M)** | **YES** — it is a full session |
| **Isolated tree?** | available (`isolation:'worktree'`, `claude -w`) but **used on 1 of 1,251 calls in 14 d, and that one was a probe (M, W6 §3c)** | **YES, genuinely** — own `git_dir`, index, HEAD; `sees_sibling:"no"` **2/2 (M)**. Two costs: it lands in the operator's **shared `~/Development/.worktrees/` pool whatever repo fired it** (our `WorktreeCreate` hook's generic branch) **(M)**, and it **leaks 100%** (§5.1). Without it, N agents share ONE index. **There is no third setting.** | **NO** — shares the lead's cwd | **YES** — `--worktree` is where the fleet's real per-task isolation comes from **(M, W6 §3c)** |
| **Persists across turns?** | **YES** — persists until `shutdown_request` **(Q; not re-measured this wave — the two vendor docs disagree, see §7.8)** | **While running: YES.** **After exit: NO — 2/2 `"No transcript found for agent ID"` even though the transcript is on disk (M, W2-VERIFY C2).** Mechanism: `resumeAgentBackground` misses the workflow-nested disk path and falls back to *"in-memory messages mirrored during the run"* **(Q)** | one-shot in practice | **YES** — recycles, resumes, re-arms |
| **Messageable mid-flight?** | **YES**, by `name` | **Three cells, not one.** ⬆️ **to the lead: YES** — `SendMessage({to:"main"})` succeeds, vendor-native (literal in the binary, ×2; positive control 0), **not** our mailbox **(MS, replicated by 2 agents)**. ⬅️ **inbound by raw `agentId`, while running: YES** — delivered in-band as *"Another Claude session sent a message while you were working"*, both targets kept working **(M, n=2)**; **peer-to-peer**, and W5 **replied unprompted**. **By `label`: NO.** **Lead→agent not executed (?)**. **Discovery is free:** an agent that sends one line to `main` publishes its own `agentId` as `origin.from` — **7 and 5 occurrences in the lead's transcript for the two agents that spoke, 0 for the two that stayed silent (M)** | ✅ upward by return only | **YES** — mailbox + `SendMessage` |
| **Stoppable?** | **YES** — `shutdown_request` · `TaskStop <name>` · `cc-teardown <pane-uuid>` | **Run-level YES, agent-level NO, ours-level NO.** `TaskStop(taskId)` halts the whole run — the t=45 s and t=90 s files never appeared across 150 s, then `TaskGet` → `Task not found` **(M, replicated)**; mechanism = every agent's controller chained to the parent's `abortController` **(Q)**. Per-agent `skip`/`retry`/`pause`/`kill` exist in the `/workflows` TUI, keybound `x`/`r`/`p` **(Q)** — operator-only, in the **parent's** pane. **From anything we own: ❌** — `cc-teardown` takes a pane-uuid and a workflow agent's `ITERM_SESSION_ID` **is the parent's**, so aiming it at an agent **kills the lead (MS)**. `kill -KILL` the parent works and strands **dirty** worktrees (`finally` never runs) **(M)** | Esc, from the lead's TUI | **YES** — `cc-teardown`, its own pane |
| **Reviewable?** | **YES** — separate process, own instruments, can spawn its own probes | **Structurally guaranteed, instrumentally crippled.** A `pipeline()` stage cannot be skipped without editing the script **(Q)** — the real win. But `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1`, so **a workflow review stage cannot spawn anything (MS)**, and 4 of yesterday's 6 load-bearing overturns came from the verifier *spawning* or *re-instrumenting*, not from fresh eyes **(M, W5 §2.3)**. 🚨 **A braked agent still reports DONE**: a `PreToolUse` deny halted every tool call of a workflow agent and the journal still wrote `result: DONE` **(M, O1-VERIFY — single instance, see §6)** | fresh but no spawn | **YES** |
| **Auditable?** | **YES** — own session id, own transcript, own `bash-commands.log` rows | **UNAUDITED, not unauditable.** Raw material exists: per-agent transcripts (283–521 KB each), `agent-<id>.meta.json` carrying `worktreePath`, and `journal.jsonl` `result` records with the **full** return string **(M — this refutes W2's "zero result records")**. The index does not: **no label, no phase, no timestamp on any journal row (M, 12/12)**. And attribution is actively wrong — PreToolUse Bash hooks DO fire for workflow agents but log under the **LEAD's** session id: **310 of the last 3,000 rows, six authors, one label (MS)**. `workflow` appears **0 times** in `wrap-ledger.sh`, `completion-assert.sh`, `session-writes.sh`, `session-continue.sh`, `operator-readout.sh`, `cc-custody`, `cc-teardown`, `cc-board`, `postland-verify.sh` — while `pane`/`session` appear 2–259 times in the same files **(M, positive-controlled)** | logs under the lead's sid | **YES** — own sid, custody row, ledger |
| **Lands code?** | **84 / 1,169 = 7.2%** confirmed `[branch sha]` (a floor); 327 ran `git commit` **(M)** | **12 / 1,781 = 0.67%** confirmed **(M)**; a separate 674-agent sample produced **2 `git commit`s and 4 `git push`es total (M, W3 §2d)**. An individual agent CAN: one took the machine-wide land lock and ran `ship-land.sh` to a real verdict (rc 4, shared-checkout refusal) **(MS)**. But **nothing merges** — isolated agents can't see each other and the unisolated verifier on `main` saw an empty `src/` **(M)**; **no return field names the branches**; and **the orchestrator cannot see a diff** — `vm.createContext` binds exactly `{log, phase, console, budget, setTimeout, clearTimeout}` + `agent/parallel/pipeline/workflow`, `codeGeneration:{strings:false,wasm:false}`: **no `fs`, no `child_process`, no `git`** **(M, own strings dump)**. Bash auto-backgrounds at 120 s vs a p90 land episode of 991 s, so the agent returns before its own land finishes **(I)** | **3 / 694 = 0.43%** **(M)** | the fleet's normal landing unit |
| **Cost per unit shipped** | **11.60 pp per confirmed commit**; 51,235 out-tok/pp; IMPL stratum 51,631 **(M, 6,015 transcripts, message.id-deduped)** | **49.31 pp per confirmed commit** (4.3× the teammate); 8,522 out-tok/pp overall, **15,615 in the IMPL stratum = 3.31×**; size-controlled the class penalty **shrinks** — 2.98× → 1.91× → 1.22× **(M)** | 70.73 pp; 9,303 out-tok/pp | 0.875 pp/task worker-side — **no quota advantage over a teammate**; it buys the lead's CONTEXT **(M)** |

**Instrument controls behind those numbers** (this repo has produced false findings by skipping them):
naive line-summing inflates output **2.717×** and cache-creation **2.071×** — *non-uniformly*, so it
distorts out/pp rather than scaling it; cross-file `message.id` duplication 0/7,007; the interactive
`grep` here is a ugrep shim that returned **0 on a `"type":"assistant"` positive control**, so every
commit grep used `/usr/bin/grep`.

### 2b. Where the wave refuted itself — the corrections a reader must carry forward

| Claim as first written | Verdict | What settled it |
|---|---|---|
| *"The child's Bash ran a command the parent's own allowlist would have refused"* (privilege escalation) | 🚨 **REFUTED, twice, independently** | Neither verifier's parent was ever constrained — `--allowedTools` is **additive**. Both ran the missing negative control: `{"parent_bash":"SUCCEEDED","parent_write":"SUCCEEDED"}`. **No escalation of any kind was demonstrated. Do not encode one.** |
| *"An unattended workflow cannot be constrained"* | 🚨 **REFUTED — and this is the operator's real control surface** | `permissions.deny` **binds a workflow child**: `{"deny":["Bash(echo:*)","Write"]}`, no bypass flag → **4/4 denials held**, the harness saying *"Write is disabled for this session, **in subagents as well as here**."* `at={...ze,mode:…}` replaces only `mode`; deny rules ride through **(M + Q)**. Still open: a deny under `bypassPermissions`. |
| *"A running Workflow has NO abort path"* (landed 08-19) | 🚨 **REFUTED** | `TaskStop` works, measured twice. Correct framing: **the abort exists, lives inside the unattended session, and nothing we own can reach it.** |
| *"No name ⇒ unaddressable"* | 🚨 **REFUTED on its decisive half** | Raw `agentId` reaches a **running** agent, 2/2, in-band, bidirectionally. The discriminator is **completion, not the name**. |
| *"Concurrent unisolated writers deterministically corrupt one file"* (4 commits, 2 lost, `feat: gamma` absent everywhere) | 🚨 **RETRACTED** | That tree held **~8 writers from two verifier sessions** that collided on a predictable `/tmp` path. A clean, randomly-named 4-writer re-run finished **byte-correct, 4/4 commits, `feat: gamma` present** — the Write tool enforces read-before-write optimistic concurrency (`"File has been modified since read"`, fired 4×). **The surviving hazard is the git layer only** (`git add -A` in a shared tree makes a commit subject lie about its diff), and it is **stochastic**. |
| *"`resumeFromRunId` replays a failed run's good parts free"* | **REFUTED as used** | Q: *"**Same-session only. Stop the prior run first**"* — unreachable in exactly the failure modes this repo suffers (`Prompt is too long`, reboot, quota cliff). It is an **iteration** primitive, not a **durability** one. |
| *"Register a `WorktreeRemove` hook to fix the leak"* | **REFUTED** | Both isolation paths short-circuit on `hookBased` **before** any removal call. Only session-level `EnterWorktree` cleanup reaches it. **Cleanup must be an external sweeper.** |
| *"The journal has zero `result` records"* | **REFUTED** | `result` records exist and carry the full return string (4,037–4,868 chars). The missing fields are **label, phase, timestamp** — which is the sharper and more buildable statement. |
| *"Orphaned files are attributable to no session"* | **REFUTED** | `agent-<id>.meta.json` carries `worktreePath` per agent. **UNAUDITED, not unauditable** — the only actor that can act never reads it. |

---

## 3. WHERE EACH UNIT WINS — the routing rule

### 3a. The discriminator, stated so it cannot be misread as a capability claim

> **Does this work end at a returned string, or at a landed commit?**

A returned string is a value the parent can hold, check and forward. A landed commit is a *sequence of
acts on shared state* — merge in an order chosen after seeing all N diffs, gate the merged result,
tear the worker down, put the write in a ledger — and every one of those is keyed on an address. A
teammate has one (pane, pid, session id, Stop hook). A workflow agent has **the lead's**.

### 3b. The table

| Task shape | Locus | The number behind it |
|---|---|---|
| Read-only fan-out, **N ≥ ~8 same-shaped units**, each self-verifying; per-slot model/effort wanted | **Workflow** | Only surface with per-agent `effort` (**no `effort` field exists on `AgentInput` at all**, Q) and a **throwing** `budget.total`; 8-wide concurrency cap `min(16,max(2,ncpu-2))`; read-only stratum costs 14.26× more per quota point but the work is cheap and the alternative is not running it |
| **The adversarial VERIFY stage of any wave** | **Workflow `pipeline()` stage** — NEW, this is the amendment | The most-skipped stage (F1, MEASURED); read-only ⇒ the resume trap cannot fire; the shape our 140-script corpus already writes well (fixed width, shared preamble in 80/140, results interpolated into a synthesis stage) |
| Implementation wave or phase | **S · dispatched session** (unchanged default, 2026-08-07) | Buys the lead's **context window**, the resource whose exhaustion kills sessions outright. Costs **1.03–1.76× more quota** than teammates — say so explicitly; it is not a quota lever |
| Members must be synthesised against each other **immediately** AND combined output is small | **T · teammates** | Cheapest per shipped task at every N (below); the whole merge loop lands in the lead's window, which is the price |
| One file's control flow, genuinely unsplittable | **L · lead-inline** | Still a legal locus — which is why "don't do it on the lead" cannot be the rule's invariant |
| **Anything whose definition of done includes a landed commit** | **Never a workflow** | 12 confirmed commits from 1,781 agents; 2 from a separate 674; nothing merges; the orchestrator has no `fs` |

### 3c. The wave arithmetic (T = 45,000 output tokens/task — the measured median IMPL teammate unit)

Worker constants from §2.3 of W4; lead-side terms are MEASURED medians by fan-out count.

| N tasks | (a) N teammates | (b) N-agent workflow | (c) N dispatched sessions | winner |
|---:|---|---|---|---|
| **2** | 2×0.873 + 1.27 = **3.02 pp** | 2×1.699 + 1.27 = **4.67 pp** | 2×0.875 + 3.56 = **5.31 pp** | **(a)** |
| **5** | 5×0.873 + 1.81 = **6.17 pp** | 5×1.699 + 1.81 = **10.30 pp** | 5×0.875 + 4.04 = **8.41 pp** | **(a)** |
| **12** | 12×0.873 + 5.73 = **16.20 pp** | 12×1.699 + 5.73 = **26.11 pp** | 12×0.875 + 6.15 = **16.65 pp** | **(a)** |

Ratios to (a): workflow **1.55× / 1.67× / 1.61×**; dispatch **1.76× / 1.36× / 1.03×**. **Winner (a) at
every N under both exchange rates** (the A1 raw fit 9.27/1.04 narrows workflow to 1.35–1.43× and never
reverses).

Read it honestly: **a workflow's per-task quota premium is 1.5–1.7×, not the headline 6×.** Quota is a
supporting argument here, not the load-bearing one.

### 3d. 🚨 The variable nobody's plan declares, and it is worth 14× more than the locus

| unit output | n | out/pp | med lifetime | med turns | med files |
|---|---:|---:|---:|---:|---:|
| 0–2K | 172 | 2,250 | 11 min | 26 | 1 |
| 20–40K | 304 | 49,986 | 17 min | 36 | 2 |
| **40–80K** | 567 | **61,168** | **32 min** | **60** | **3** |
| **80–150K** | 557 | **58,454** | **73 min** | **107** | **6** |
| >300K | 64 | 32,341 | 773 min | 310 | 15 |

**Spread across size bands: 27×. Spread across vehicles at matched size: 1.9×.** So the rule that
matters most is not *"teammates, not workflows"* — it is **"one task per unit, 40–150K output tokens
wide, never below 20K, split above 300K or 10 files."** Teammates today sit at a median of 36,848
output — under-sized. Re-sizing current briefs into the peak band is **~+19% quota efficiency at zero
risk and no rule change.**

---

## 4. THE VERDICT ON THE STANDING RULE — **AMEND**

Keep the force. Replace the reason. **Repair the enforcement, which is dead for reasons unrelated to
this question.** Every edit below is INTEGRATE-not-overwrite: an `Edit` to a named range, with the
surrounding rationale paragraphs untouched.

### Edit A — `CLAUDE.md:131-136` · replace the mandate paragraph *(land this whatever else you do)*

Replaces the paragraph beginning `**Agent Teams are the DEFAULT for all implementation work.**` and
ending `research/exploration only — never for code changes.` Line 138 onward is unchanged.

```markdown
**Agent Teams are the DEFAULT for all implementation work.** This applies globally.
Code-writing tasks with 2+ files MUST run in a unit that is ADDRESSABLE and WRITE-ISOLATED —
ADDRESSABLE = the operator can SEE what it is doing, STOP it with one command we own, and ATTRIBUTE
every write to it; WRITE-ISOLATED = its own worktree + branch, so no two concurrent writers share an
index. 🚨 **On 2.1.220 the switch is `name:`, NOT `team_name`** (binary-extracted 2026-08-03; the
Agent tool's destructure is `{prompt, subagent_type, description, model, run_in_background, name,
isolation, cwd}` — `team_name` is not in it, and **0 of 1,251** Agent calls in a 14-day 5-store census
used `team_name` alone). A named Agent call becomes a teammate: its own process, pane and lifecycle,
persisting until an explicit `shutdown_request`. Classic `TeamCreate` + `team_name` exists only on
stable 2.1.114. Background subagents (no `name:`) are for research/exploration only — never for code
changes. **That clause is a POLICY, not a capability claim**: an unnamed subagent and a Dynamic
Workflow agent both hold Write/Edit/Bash and both have committed working code here. The reason they
may not carry a wave is § *Dynamic Workflows* below.
```

### Edit B — `CLAUDE.md`, insert **after** line 192 · the paragraph that stops the question recurring

Line 192 currently ends `…firing mechanics → `commands/handoff.md` § Waves.` Insert after it:

```markdown
**Dynamic Workflows are a RESEARCH, BATCH and VERIFY surface — never an implementation locus — and
the reason is ownership of the tail, not capability** (measured 2026-08-20,
`docs/research/workflows-vs-teams-2026-08-20.md`). A workflow `agent()` holds every tool but
`SendUserMessage`/`Agent`/`Workflow`, runs at forced `acceptEdits`, gets a real isolated worktree, and
has committed working code unattended — that argument is over, and re-asserting it is what made this
question re-mint three times. What it cannot do is OWN the work: **nothing merges its branches** (its
agents cannot see each other; no return field names them), **the orchestrator is content-blind** (a
`vm.createContext` sandbox with no `fs`, no `child_process`, no `git` — "merge smallest-diff-first"
is not expressible, only requestable in prose), **its address is the lead's** (it inherits
`CLAUDE_CODE_SESSION_ID` and `ITERM_SESSION_ID`, so `cc-teardown` aimed at an agent kills the lead,
custody never opens a row, a `--by <sid>` backlog lease gives 8 agents no mutual exclusion, and
`session-writes.sh` reads a transcript they do not write to), and **its worktrees leak 100% on this
box** — even on a clean completion by a provably-unchanged agent, because our own `WorktreeCreate`
hook makes them `hookBased:true`, which disables the harness's auto-removal. Measured: 12 confirmed
commits from 1,781 workflow agents in 30 days, and **49.3 quota points per confirmed commit vs 11.6
for a teammate**. Two things this paragraph deliberately does NOT say, because both were measured
false on 2026-08-20: workflow agents are *not* unreachable (a **running** one is addressable by raw
`agentId`, in-band, and publishes that id to the lead the moment it sends one line to `main`), and
there *is* an abort path (`TaskStop` halts a run; the binary ships
`killWorkflowTask`/`pauseWorkflowTask`) — it simply lives inside the unattended session and nothing we
own can reach it. **Use a Workflow where `skills/research-subagents/SKILL.md:392` already says to —
read-only waves >~10 agents, the only surface where per-slot model+effort is pinnable — and for a
wave's adversarial VERIFY stage, which a lead demonstrably forgets. Until `isolation:'worktree'` has a
sweeper, do not use it from this box.** Re-open only on all four of: a `Workflow` PreToolUse matcher
in `settings.json`, a registry row per agent, a stop path in something we own, and write attribution
that does not convict the lead.
```

### Edit C — `CLAUDE.md:226-227` · the second, blunter statement of the same false premise

Replace `Research subagents (no `team_name`, fire-and-forget) are disjoint from Agent / Teams;
teammates write code, subagents never do.` with:

```markdown
Research subagents (no `name:`, fire-and-forget) are disjoint from Agent Teams. **"Subagents never
write code" is our POLICY, not a fact about the tool** — a `general-purpose` subagent has `tools:["*"]`
and 84 of 694 sidechain units wrote files in 30 days (measured 2026-08-20). The policy holds because
an unnamed unit has no address to stop, tear down or attribute; `Explore` is the one genuinely
read-only type (it denies Edit/Write/NotebookEdit at the tool layer).
```

### Edit D — `hooks/agent-teams-enforce.sh` · the dead gates *(the urgent one)*

MEASURED head-to-head on an identical 300-line implementation brief, gates disabled so only the teams
logic answers:

| probe | shape | verdict |
|---|---|---|
| A | `{name:"impl-1", prompt:<300 lines>}` — **what 2.1.220 emits** | **allow** + a nudge telling the model to set `team_name`, which is not in the tool's schema |
| B | `{team_name:"t1", prompt:<300 lines>}` — legacy | **deny** (250-line cap) — works, over an input the runtime never produces |
| C | `{run_in_background:true, prompt:<impl keywords>}` | **deny**, prescribing `TeamCreate` + `team_name` — **neither exists on this runtime** |

Same split on the model allowlist: `{team_name:"x", model:"claude-sonnet-4"}` → **deny**;
`{name:"x", model:"claude-sonnet-4"}` → **allow**. So today **a teammate can be spawned with any brief
size on any model, unchecked.**

```bash
# after the parameter extraction at hooks/agent-teams-enforce.sh:26-30 —
# 2.1.220 has no `team_name`; `name:` is the teammate switch (skills/agent-teams/SKILL.md:50-53).
NAME=$(echo "$INPUT" | jq -r '.tool_input.name // empty')
TEAMMATE_ID="${TEAM_NAME:-$NAME}"

# :508  →  if [ -n "$TEAMMATE_ID" ] && [ -n "$MODEL" ]; then   # model allowlist
# :561  →  if [ -n "$TEAMMATE_ID" ]; then                       # ≤150 warn / ≥250 deny brief cap
```

And at `:656` / `:670`, replace `use TeamCreate first, then spawn agents with team_name parameter set`
with `re-spawn with name: set (2.1.220 has no TeamCreate and no team_name), or dispatch the wave with
scripts/handoff-fire.sh --worktree`. *(A gate printing a cure the runtime rejects is this repo's own
named defect — memory `work-item-remedy-can-become-forbidden`.)*

**Red-proof before landing, one mutant per site:** probe A and the `name:`-shape model probe must FLIP
allow → deny on identical inputs, and probe B must stay `deny`.

### Edit E — `tests/agent-teams-enforce.bats:36-38`

`run_hook()` feeds `{tool_input:{team_name:…}}`. That is why a green suite sat over an unreachable
subject for 17 days. Re-shape it to drive `{name: …}`, keeping **one** `team_name` case pinned as the
2.1.114-legacy control.

### Edit F — `skills/agent-teams/SKILL.md:84-90` · two rows

| Task Type | Pattern |
|---|---|
| Read-only wave >~10 agents, or a wave's adversarial VERIFY stage | **Dynamic Workflow** (`research-subagents` skill §392) |
| **Any task whose done-state is a landed commit** | **Never a Workflow** — nothing merges its branches, the orchestrator has no `fs`, and its address is the lead's |

### Edit G — `skills/plan-conventions/SKILL.md:59-63` · add **W**, scoped

The locus enum is closed at S/T/L. Add a fourth row **restricted to read-only stages**, so the enum
stops being silently incomplete without licensing an implementation locus:

| Locus | Mechanism | Whose context pays | Use when |
|---|---|---|---|
| **W · dynamic workflow** | `Workflow({script})` with `agent(brief, {label, phase, model, effort})` | the run's — the lead pays only for the script it wrote and the run summary | **read-only stages only**: a research fan-out ≥8 units, or the wave's adversarial VERIFY stage. **Never a stage that writes source.** A W stage that writes anything must name its merge owner and its sweeper in the same line, or it is ineligible. |

---

## 5. WHAT WOULD HAVE TO BE BUILT — ranked, so the gap has a size

Six items are ours, three are the vendor's, one is architectural and cannot be built at all. Items 1–2
are **live defects today**, not prerequisites: they are hurting us right now regardless of this
verdict.

| # | Gap | Who | Size | Evidence it is real |
|---:|---|---|---|---|
| **1** | **A worktree/branch sweeper** keyed on branch pattern `wf_<runId>-<n>` + each `agent-*.meta.json`'s `worktreePath` | **us** | small, and **overdue** | **100% leak rate, MEASURED in the BEST case** — 2 provably-unchanged agents, clean completion, clean exit → both worktrees **and** branches survived, 2/2. Pool went 172 → 181 from 5 agents. At the 8-cap one run leaks 8+8 into `~/Development/.worktrees` (already ~180 entries; the repo carries 87 worktrees / 1,766 branches ahead of trunk). **A `WorktreeRemove` hook does NOT fix it** — both isolation paths short-circuit on `hookBased` first. Until this exists, **`isolation:'worktree'` should not be used from this box at all.** |
| **2** | **`hooks/lib/session-writes.sh` must union `subagents/workflows/wf_*/agent-*.jsonl`** under the Stop payload's sid | **us** | **one path change** — the cheapest item here | Today a workflow agent's uncommitted files convict the LEAD, and `session-writes.sh` returns *"no file-edit tool_use"* over a tree six agents are actively editing — so mechanical-🔧, the ship floor and custody all fail open |
| **3** | **An address registry** — stamp `(sid, agentId, runId, label)` on first tool call | **us** | small; or **free** | The `PreToolUse` payload carries `agent_type:"workflow-subagent"`; a `matcher:"*"` hook costs 2.85 ms p50. **Free alternative, measured:** brief every agent to `SendMessage({to:"main"})` once at start — the lead then holds its `agentId` as `origin.from` (7 and 5 hits vs **0** for silent agents) |
| **4** | **A `Workflow` PreToolUse matcher** in `settings.json` | **us** | small | Independently re-verified for this document: the PreToolUse matchers are exactly `Agent`, `AskUserQuestion`, `Bash`, an ms365 list, `Write\|Edit\|MultiEdit`. The **only** `Workflow` string in the whole file is `"skipWorkflowUsageWarning"`, a UI flag |
| **5** | **A labelled, timestamped journal index** (label → agentId → transcript) | **us** | small | `result` bodies exist; label/phase/timestamp do not, on 12/12 rows. Ordering and duration are unreconstructable |
| **6** | **`cc-backlog --venue workflow`** or an agentId-scoped `--by` | **us** | medium | 8 agents share one sid ⇒ `cmd_claim`'s incumbency test `[ "$cby" != "$by" ]` never fires ⇒ **the lease is silently a no-op between siblings** |
| **7** | **A named merge owner** — the parent discovers branches, merges serially, gates the merged result, cleans up | **architectural** | **cannot be built inside a workflow** | The orchestrator has no `fs`. This can only ever be the parent session's job, declared in Phase 0 — which is exactly the teammate lead's job, minus the ability to talk to the workers |
| **8** | **Per-agent stop from a rail we own** | vendor + us | needs #3 first, and is capped | `TaskStop` takes the **run**; per-agent skip/retry is TUI-only in the parent's pane. Even with an address, we can only stop the run |
| **9** | **Post-exit resume** | **vendor** | — | `resumeAgentBackground` misses the workflow-nested disk path; falls back to in-memory mirrors that die with the run |
| **10** | **Stop-hook participation** (close ledger, DoD, custody, origin-close contract) | **vendor** | — | A workflow agent has no session, therefore no Stop. Our entire close-integrity system never runs for it |
| **11** | **A blocking approval gate** (`plan_approval_request` equivalent) | **vendor** | — | The agent cannot pause and wait for an answer; the script cannot orchestrate the exchange |

**The honest size:** 6 buildable (2 of them nearly free), 1 unbuildable-by-design, 3 vendor-side. It is
a subsystem, not a patch — and every one of these already exists for a teammate, which is the whole
argument in one sentence.

---

## 6. THE HONEST CASE AGAINST THIS RECOMMENDATION

Six objections, in descending strength. I hold the verdict, but a reader should see what it costs.

1. **"Keep the rule" is doing rhetorical work it has not earned.** The mandate has never bound: 0 of
   1,251 calls used its mechanism, both hard gates are dead, the worktree isolation it promises comes
   from a locus it does not name, and its prose entered git already-written with no authoring
   rationale. Edits A–E do not *restore* a rule — they **write a new one and call it a keep**. That is
   the most defensible framing available, and it is still a framing.
2. **Two of this wave's five anti-workflow mechanisms died within 24 hours of being asserted.**
   "Unaddressable" and "no abort path" were both refuted by someone running the probe. My verdict now
   rests hardest on *attribution and ledger participation* — which is a fact about **our own tooling**,
   the thing we control, and **two of the six repairs are one-path-change cheap**. If someone spends a
   day on items 1–3 of §5, a large part of this document's reasoning expires.
3. **The 100% worktree leak — the single strongest measured argument — is caused by OUR hook, not by
   the product.** `isolation:'worktree'` documents auto-removal-if-unchanged, and it would work; our
   `WorktreeCreate` hook sets `hookBased:true` and disables it. Fixing our own chain removes the
   argument. Citing a self-inflicted defect as evidence against a vendor primitive is weak, and I am
   doing it.
4. **The cost argument measures how the class is USED, not what it can do.** 90.8% of workflow agents
   never clear 10K output; the median is **356 tokens**. Size-controlled, the penalty *shrinks* with
   task size — 2.98× → 1.91× → **1.22× above 50K** — and the largest observed workflow agent (74,131
   output over 10.6 h) scored near teammate parity. Only **4 units in 30 days** are in that band, so
   the anti-workflow cost case is partly a statement that nobody has tried. A deliberate 8-wide
   full-size workflow could falsify most of §3c.
5. **The "disqualifying" review defect is n=1, and the wave may have manufactured its own worst
   hazard.** *A braked agent still reports DONE* rests on one O1-VERIFY observation under an
   artificial `PreToolUse` deny; it was not reproduced here. And the most alarming finding in the
   folder — two live instances sharing one `agentId`, appending to one transcript, racing on one
   output file with no lock and no error — has a **MEASURED occurrence** but an **INFERRED cause**,
   and the leading candidate is the resume path that a *verifier's own probe* exercises. Separately,
   two adversarial verifiers collided on predictable `/tmp` paths, cross-polluted a git tree, and one
   nearly destroyed the other's finished file. **Both contaminations bias toward "workflows are
   dangerous" — the direction an adversarial reader is least likely to question.**
6. **I am keeping only one of the three axes where workflows genuinely beat teams.** Per-agent
   `effort` (there is **no** `effort` field on `AgentInput` at all — our own skill calls it *"the
   genuinely inert axis"* for teams), a **throwing** `budget.total` (nothing in team-land throws on a
   token total), and a verify stage that cannot be forgotten. I adopt the third. If what actually
   limits our waves is mixed-effort routing or runaway spend rather than merge discipline, this
   recommendation under-adopts, and the 27× size effect in §3d says the locus debate is the smaller
   lever either way.

---

## 7. OPEN QUESTIONS, EACH WITH ITS PROBE

Ranked by how much the answer would move this document.

1. **Do 8 concurrent `isolation:'worktree'` creations race our `WorktreeCreate` hook?** Named by three
   axes as the biggest unmeasured item (the known `.git/config.lock` hazard for parallel *automated*
   worktree creation, GH #34645/#48927). Max concurrency actually run: 4.
   → *Throwaway repo, 8-agent workflow all with `isolation:'worktree'`; count worktrees created vs 8
   and grep for `config.lock`.* **Do this before anyone uses `isolation` from this box.**
2. **Can the LEAD reach a running workflow agent, or only a sibling agent?** Agent→agent is MEASURED
   n=2; lead→agent was **deliberately not executed** (issuing it would perturb a live axis). This is
   the direction that matters for control.
   → *From a lead: `SendMessage({to:"<agentId read from origin.from>"})` at a throwaway workflow
   agent; grep its transcript for the marker.*
3. **Does the one-agentId / two-instances collision reproduce deliberately?** MEASURED occurrence,
   INFERRED cause, and it is §6's strongest self-doubt.
   → *Resume a running workflow agent by agentId, have both instances write the same path, inspect the
   tree and the transcript.* If it reproduces, item 3 of §5 becomes urgent and the verdict hardens.
4. **Does resume serve a stale report after the tree has moved?** The cache key is `(prompt, opts)` —
   **no tree term, no time term** (proven: one key across 3 executions on 3 days), and the journal
   stores the **return value only**, never the side effects.
   → *2-stage script: stage 1 writes a sentinel and returns its content; mutate the sentinel; resume.
   Predicted: stale content served, file not rewritten.* ~4 cheap agents.
5. **Does a workflow agent's backgrounded Bash child survive the run's stop?** The one scenario where
   the verdict moves from *unaccountable* to *unsafe* — a stopped run leaving a `git push` in flight
   holding the machine-wide land mutex.
   → *One agent backgrounds `sleep 600`; stop the run via `/workflows`; `ps` for the sleep.*
6. **Do `Write|Edit|MultiEdit` PreToolUse hooks fire inside a workflow agent?** The Bash ones
   provably do (measured twice, including two live denials). If the Write ones do too, workflow writes
   are already covered by `check-edit-boundary.sh` + `backup-before-write.sh`.
   → *One-agent workflow writes `/tmp/probe.txt`; `ls -t ~/.claude/backups/ | head`.*
7. **Does `permissions.deny` still bind under `bypassPermissions`?** It binds 4/4 in default mode —
   the operator's real control surface. Most of this wave's own probes ran in bypass, where it is
   untested.
   → *Same deny probe, plus `--dangerously-skip-permissions`.*
8. **Does a named teammate actually resume after completion?** The two vendor docs contradict each
   other — `AgentInput.name` says addressable *"while running"*; `SendMessage` says names *"keep
   working after an agent completes"*. The teammate half of the persistence contrast is QUOTED, never
   measured.
   → *Spawn a throwaway teammate, let it complete, `SendMessage` its name.*
9. **Can a workflow agent be driven into the 40–150K efficient band on purpose?** n=4 in 30 days.
   → *One deliberately large workflow agent; measure out/pp.* This is the measurement that would most
   weaken §3c.

---

## 8. PROVENANCE AND FLEET HYGIENE

Six measured axes, five adversarial verifier files, all in
[`workflows-vs-teams-2026-08-20/`](workflows-vs-teams-2026-08-20/):
`W1-can-a-workflow-implement.md` · `W1-VERIFY.md` · `W1-VERIFY-2-deny-and-collision.md` ·
`W2-teammate-only-capabilities.md` · `W2-VERIFY.md` · `W2-LEAD-OBSERVATION-inbound-probe.md` ·
`W3-determinism.md` (+ `strip.js`, `dyn2.py`) · `W4-cost-per-shipped.md` (+ `W4-scan.py`) ·
`W5-review-merge-land.md` · `W6-the-standing-rule.md`.

**Where a verifier refuted a finder, the verifier's measurement was taken** — every case is listed in
§2b, and in each the verifier had run a control the finder had not. Two exceptions where the *finder*
was kept: the worktree **location** (W1 RAN it and got `~/Development/.worktrees/`; W5 QUOTED the
vendor default `.claude/worktrees/` and measured that directory absent — both are true, and the
redirect is our hook's), and the upward-`SendMessage` mechanism (the axis agent's three-check
refutation of the lead's mailbox attribution is visibly stronger than the lead's inference, and the
lead itself then self-corrected).

Independently re-verified while writing this document: `CLAUDE.md:131-136` / `:188-192` / `:226-227`
line ranges; `hooks/agent-teams-enforce.sh:26-30`, `:508`, `:561`; the `settings.json` PreToolUse
matcher list and the absence of any `Workflow` matcher.

**This synthesis is read-only.** Nothing was spawned, killed, closed or configured; no live pane,
session, worktree or process was touched. The axes' own probe ledgers are in their files — all
throwaway repos under `/private/tmp`, all self-started `claude -p` processes exited, and all probe
worktrees removed with the shared pool verified back to baseline.
