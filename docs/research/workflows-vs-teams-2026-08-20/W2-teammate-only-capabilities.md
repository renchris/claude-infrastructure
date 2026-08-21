# W2 — What a teammate has that a workflow agent cannot, and the reverse

**Date:** 2026-08-20 · **Binary:** CC 2.1.220 (`~/.claude-220/.../bin/claude.exe`) · **Box:** M1 Max, 10 cores
**Method note:** this axis was measured **from inside a workflow agent**. The wave that asked the
question was itself fired as a Dynamic Workflow (`wf_d8303f9f-4e4`), so every claim below marked
MEASURED-SELF is a first-person observation of the unit under test, not an inference about it.
My own agentId is `a78518b03eeb3be55`; my transcript is
`~/.claude-secondary/projects/-Users-chrisren-Development-claude-infrastructure/f285654f-850c-4ada-96b5-407c5c01ccf0/subagents/workflows/wf_d8303f9f-4e4/agent-a78518b03eeb3be55.jsonl`.

---

## 1. Verdict

1. **The asymmetry is not "fewer tools" — it is that a workflow agent has no NAME, and a name is
   what every mid-flight verb in this harness resolves against.** No name ⇒ not addressable
   (`SendMessage`), not stoppable individually (`TaskStop`), not shutdownable (`shutdown_request`),
   not resumable, not continuable. MEASURED-SELF: `SendMessage` from inside a workflow agent
   returns *"No agent named 'X' is reachable"* with **no roster at all** — a workflow agent sees
   zero peers and zero teammates.
2. **The persistence gap is total and one-directional.** A teammate persists and takes N turns —
   the live `SendMessage` doc states *"names keep working after an agent completes (a send resumes
   it from its transcript)"*. A workflow `agent()` is one prompt in, one string out, with **no
   continuation primitive anywhere in the DSL** (full primitive list QUOTED below). A "checkpoint"
   in a workflow is a *different agent* handed ≤N characters of the previous one's return string.
3. **But the traffic is not zero — it is one-way UP, over a HARNESS channel, not ours.**
   MEASURED-SELF: `SendMessage({to:"main"})` from a workflow agent **succeeds**
   (*"Message queued for the main conversation's next turn"*). That response string is **in the
   2.1.220 binary** (`grep -c` = 2 hits) and my transcript records it as a `SendMessage` **tool_use**
   block — not a Bash call, not `cc-notify`. See §2b-bis, which corrects a lead-written note in this
   same directory that attributed it to our mailbox. A workflow agent can report to the lead. The
   lead cannot reply. Escalation works; redirection does not.
4. **Two things workflows genuinely have that teams genuinely lack, and only two:** per-member
   **`effort`** as an inline call argument (there is *no* effort field on the Agent tool in either
   version — our own `agent-teams` skill calls this "the genuinely inert axis" for teams), and a
   **hard token ceiling** (`budget.total`) that throws rather than advises. Everything else on the
   workflow-only list — loops, conditionals, fan-out width, structured output, caching — a lead can
   approximate in ordinary tool use; the difference is reliability, not capability.
5. **The audit trail is real but unindexed.** Per-agent transcripts exist; the `journal.jsonl` that
   indexes them carries **only `{type, key, agentId}`** — no label, no phase, no prompt, no
   timestamp (MEASURED-SELF, 6/6 records this run).

---

## 2. The two-way capability diff

Legend: **MS** = measured self (I ran it, from inside a workflow agent) · **M** = measured this
session on this box · **Q** = quoted verbatim from the 2.1.220 bundle or a live tool description ·
**P** = prior landed measurement in this repo (cited) · **I** = inferred, marked as such.

### 2a. PERSISTENCE — the single biggest difference

| Capability | Teammate `Agent({name})` | Workflow `agent()` | Evidence / command |
|---|---|---|---|
| Lives past one prompt | **YES** — persists until shutdown | **NO** — one prompt in, one return value out | Q: `agent()` signature enumerates *no* continuation primitive (§2f) |
| Can be given follow-up work without re-spawning | **YES** | **NO** | Q (live `SendMessage` tool description): *"names keep working after an agent completes (a send resumes it from its transcript)"* |
| Has a stable address | **YES** — `name` | **NO** — only a `label` | Q `AgentInput.name`: *"Name for the spawned agent. **Makes it addressable via `SendMessage({to: name})` while running.**"* `agent()` opts = `{label, phase, schema, model, effort, isolation, agentType}` — **no `name`** |
| Appears in the name registry | **YES** | **NO** | Q: `spawnInProcessTeammate` calls `agentLifecycle.registerName(...)`; the workflow agent controller's fields are `label, phaseIndex, phaseTitle, promptPreview, lastProgressAt` — no name path |
| Resumable from transcript | **YES** | **NO** | Q: `identity.resumableAgentId` exists on the teammate task shape only |
| Keeps a warm context across the whole assignment | **YES** — one system prompt + one repo load, N turns | **NO** — every stage pays a cold start | MS: my own prompt contains the full CLAUDE.md + MEMORY.md reload |

**Command behind the negative:** the `agent()` opts object is quoted directly out of the binary —
```
LC_ALL=C strings -a -n 6 ~/.claude-220/node_modules/@anthropic-ai/claude-code/bin/claude.exe \
  | grep -F "opts.model overrides the model for this agent call"
```
Positive control for the same grep technique: `grep -F "addressable via SendMessage"` returns the
`AgentInput.name` doc, so the corpus is present and the tool is not silently failing.

**Why the two halves are not symmetric.** `SendMessage`'s resolver builds its roster from exactly
four sources (Q, function `pmr`): `main`; `teamContext.teammates`; `agentNameRegistry` entries whose
task is `type === "local_agent"`; and `teamFile.members`. A workflow agent is in **none** of them —
structurally, because the whole workflow is **one** task of `type:"local_workflow"` whose agents live
in its private `agentControllers` collection. There is no per-agent task row to address, stop, or
resume. That one design fact generates every ❌ in this table.

### 2b. MID-FLIGHT COMMUNICATION

| Channel | Teammate | Workflow agent | Evidence |
|---|---|---|---|
| Lead → member, mid-flight | **YES** `SendMessage({to: name})` | **NO** | MS + Q (resolver roster, above) |
| Member → lead, mid-flight | YES | **YES — harness-native** | **MS**: `SendMessage({to:"main"})` → `{"success":true,"message":"Message queued for the main conversation's next turn."}`. Mechanism proven in §2b-bis. |
| Member ↔ member (peer mail) | **YES** (name-addressed) | **NO** | MS: `SendMessage({to:"w2-nonexistent-probe-target"})` → `{"success":false,"message":"No agent named '…' is reachable.\nCheck the spelling, or use the agent ID from a background agent's spawn result."}` |
| Roster visible to the member | YES (team roster) | **NO** | MS: the resolver returned the **non-team** error variant. The team variant exists in the binary (*"Check the spelling against your team roster."* / *"No teammate named 'X' is currently on team 'Y'"*) and was **not** the one I got ⇒ this agent has no `teamContext`. |
| Graceful `shutdown_request` / `shutdown_response` | **YES** | **NO** | Q: the protocol frame set (`shutdown_request`, `shutdown_approved`, `shutdown_rejected`, `plan_approval_request`, `mode_set_request`) lives on the teammate runner (`inProcessRunner` / pane teammate); a workflow agent has no inbox to receive one |
| Plan approval gate (`plan_approval_request`) | **YES** | **NO** | Q, same frame set |
| Operator can intervene on ONE member | via pane + `SendMessage` + `TaskStop <name>` | **skip / retry only, from `/workflows`** | Q: telemetry events `task_local_workflow_skip_agent`, `task_local_workflow_retry_agent`; abort reasons `user-skip` / `user-retry` |
| Operator can stop ONE member | **YES** — `TaskStop` accepts *"agent ID (`name@team`) or bare teammate name"* | **NO** — `TaskStop` takes the **run's** taskId; stopping is all-or-nothing | Q: live `TaskStop` tool description |

**The redirect asymmetry is the operational point.** A teammate going wrong can be *corrected*: the
lead sends a message and the same agent, holding all its context, changes course. A workflow agent
going wrong can only be **skipped or restarted from zero** — its 40 minutes of accumulated reading
are discarded either way. For research that is a rounding error. For an implementation wave, where
"you're editing the wrong file, use the worktree at X" is the single most common lead intervention,
it is the difference between a 30-second fix and a full re-run.

*Nuance, stated because it cuts the other way:* the workflow runner has **built-in stall detection**
a teammate does not — Q: `agent stalled on all N attempts (no progress for Nms each)` with constants
`sj_=180000` (180 s no-progress window) and `YSd=5`/`aj_=5` (attempt counts), plus throttle backoff
(*"sleeping 45s before retry"*). A stalled workflow agent is auto-retried then abandoned to `null`.
A stalled teammate just sits there — which is precisely why this repo had to build
`lead-supervisor.sh`. So workflows own *liveness*; teams own *steerability*.

### 2b-bis. The upward channel is `SendMessage`, NOT our mailbox — correcting the lead's note

While this run was in flight the **wave lead** wrote
`W2-LEAD-OBSERVATION-inbound-probe.md` into this directory, confirming my probe arrived but
attributing it to the wrong mechanism: *"The message did not travel over any workflow-native
channel… What the agent actually has is **Bash** — and this machine happens to run an operator-built
mailbox (`cc-notify` → the inbox → `mailbox-drain.sh`)… This is not a portable capability. On a box
without our mailbox, the same workflow agent is mute."*

**That mechanism claim is REFUTED, on three independent checks:**

| Check | Command | Result |
|---|---|---|
| Is the success string ours or the vendor's? | `LC_ALL=C strings -a -n 6 claude.exe \| grep -c "Message queued for the main conversation"` | **2** — it is a literal in the 2.1.220 binary. Positive control: `grep -c "W2MARKER-UNIQUE-7f3a2b"` on the same dump = **0**, so the corpus is not matching everything. |
| Which tool carried it? | tool_use census over my own transcript `agent-a78518b03eeb3be55.jsonl` | `{'Bash': 49, 'ToolSearch': 3, **'SendMessage': 2**, 'Write': 1, 'Read': 1}` — and the `SendMessage` block is recorded verbatim with `"to":"main"`, `"caller":{"type":"direct"}` |
| Did I invoke the mailbox from Bash at all? | scan every `Bash` tool_use `input.command` for `cc-notify\|cc-mail\|mailbox` | **2 hits, both AFTER the send, and both are these very verification greps.** Zero mailbox invocations preceded the message. |

The channel is the **`SendMessage` tool**, which is served to a workflow agent through `ToolSearch`
and whose own live description documents this exact recipient: *`"main"` | The main conversation
(**background subagents only**)*. It is a Claude Code feature.

**What this changes and what it does not:**
- **Portability: REVERSED.** The lead's §1 ("not portable, rests on `claude-infrastructure`") is
  wrong — this works on any 2.1.220 box with no infrastructure of ours. The upward channel is real
  and vendor-supplied.
- **The lead's §2 and §3 stand, and I adopt them.** It is one-way; the valuable direction —
  lead → member redirect — remains ❌; and an agent that can talk while remaining unstoppable
  sharpens rather than softens the abort finding. My §2b table already scored it that way, and the
  lead's demand for **two cells, not one**, is correct: score
  **✅ can emit to the parent (`SendMessage({to:"main"})`, harness-native, one-way)** and
  **❌ cannot be addressed, redirected or stopped mid-flight.**
- **The lead's open probe is the right one and is still open** (my §3 item 1): have the parent try
  to reach a *running* workflow agent by label or agentId. Note the lead's framing assumes a mailbox
  read-point; the cheaper test is simply `SendMessage` from the lead, since that is the channel that
  actually turned out to be in play.

*Generalisable lesson, and the reason this subsection exists rather than a quiet edit: the lead
inferred the mechanism from what it knows this box has, and reasoned to a portability verdict from
it. Neither the binary nor the transcript was consulted. This is the repo's own "false corroboration"
pattern — a true fact about our mailbox sitting beside an unrelated event and reading as an
explanation.*

### 2c. CHECKPOINTS + REVIEW — superficially similar, structurally not

Our teams discipline uses (a) phase checkpoints inside one teammate and (b) a fresh-context reviewer.
A workflow expresses (b) well and **cannot express (a) at all**.

| | Teams | Workflow | Equivalent? |
|---|---|---|---|
| Phase checkpoint — *same* agent pauses, reports, continues with its context intact | `SendMessage` round-trip; agent retains everything | **impossible** | **NO** |
| Fresh-context reviewer of someone else's output | spawn a second agent, hand it the artifact path | `pipeline(items, stage1, stage2)` | **YES — and the workflow does it better** (guaranteed to run; a lead can forget) |
| Judge panel / N-vote adversarial verify | lead must remember to fan out | `parallel([...3 lenses])`, in the script | **YES, workflow stronger** |

**Proof that a pipeline stage is a NEW agent, from this very run** (MEASURED-SELF). The script
orchestrating this wave contains:

```js
pipeline(
  VERIFIED,
  a => agent(a.measure, { label: a.label, phase: 'Measure' }),
  (prior, a) => agent(a.verify(prior), { label: `verify:${a.label}`, phase: 'Verify' })
)
```
`~/.claude-secondary/projects/…/f285654f-…/workflows/scripts/workflows-vs-agent-teams-wf_d8303f9f-4e4.js:295-299`

Stage 2 is a **fresh `agent()` call**. The only thing that crosses the boundary is `prior` — my
returned string — and the script then truncates it: `` `${String(p).slice(0, 6000)}` ``. My
verifier will receive **at most 6,000 characters of my final text** and nothing else: not my tool
results, not the binary greps I ran, not my reasoning. It is told *"Full file: …/W2-…md"* precisely
because the harness cannot carry context and the author had to route it through **the filesystem
instead**.

That is the general shape: **in a workflow, continuity is re-serialisation.** State crosses stages
only as (i) a return value the script threads by hand, or (ii) a file path a later agent re-Reads at
full token cost. In a team, continuity is *the agent still being alive*.

Confirmed by the on-disk agent identities: every agent in this run is a distinct
`{"agentType":"workflow-subagent","spawnDepth":1}` with its own transcript file —
```
for f in …/wf_d8303f9f-4e4/*.meta.json; do echo -n "$(basename $f): "; cat "$f"; done
```
→ 6 files, 6 distinct `agent-<id>.jsonl` transcripts, no shared session.

### 2d. WHAT ONLY A WORKFLOW HAS — with the honest "can a lead do this too?" column

| Workflow capability | Mechanism (Q) | Can a lead/team do it? | Genuinely workflow-only? |
|---|---|---|---|
| Deterministic loops / conditionals | plain JS `while`/`if` in the script | A lead can loop by *deciding* to. It cannot be *made* to. | **Partly** — reliability, not capability |
| Fan-out width as an expression | `parallel(items.map(...))`, ≤4096 items/call | Lead can spawn N — but N is chosen by judgement | **Partly** |
| Hard token ceiling | `budget.total` — *"a HARD ceiling, not advisory: once `spent()` reaches `total`, further `agent()` calls throw"*; `WorkflowBudgetExceededError` | **NO.** Nothing in team-land throws on a token total. | **YES** |
| Runaway backstop | 1000-agent lifetime cap; `WorkflowAgentCapError` | No equivalent — a teammate spawn is *uncapped* (P: `orchestration-units-2026-08-19.md`) | **YES** |
| Structured output enforced at the tool layer | `opts.schema` (JSON Schema) forces a `StructuredOutput` tool call, validates, and **retries the model on mismatch** (retry cap enforced) | A lead can ask for JSON and re-prompt; it cannot enforce at the tool-call layer | **YES, in strength** |
| Resume-from-cache | `resumeFromRunId`: *"Completed `agent()` calls with unchanged (prompt, opts) return their cached results instantly; only edited or new calls re-run. Same-session only."* Content-pinned by `scriptSha256`; a changed script must be re-approved | **NO equivalent whatsoever.** A crashed wave re-runs from scratch. | **YES — the strongest workflow-only item** |
| Journal | `journal.jsonl` under the run dir | Teams have the task board + per-session transcripts | **NO** (and see the caveat below) |
| Per-member **effort** | `opts.effort: 'low'|'medium'|'high'|'xhigh'|'max'` inline on the call | **NO.** There is no `effort` field on the Agent tool (verified: `AgentInput` in `sdk-tools.d.ts:484-520` has description/prompt/subagent_type/model/run_in_background/name/team_name/mode/isolation — no effort). Teams must pre-write `.claude/settings.local.json` in the member's worktree *before* spawn (`~/.claude/scripts/set-teammate-effort.sh`), per our own `agent-teams` skill §"Per-Teammate Effort", which calls effort *"the genuinely inert axis"* for teams. | **YES** |
| Nested sub-workflow | `workflow(nameOrRef, args)`, one level only | Teammates can spawn (depth-capped) | tie |
| Safety-classifier pre-screen on each agent | Q: `[…] blocked by safety classifier:` → `workflow_agent_<n>_blocked` | Agent spawns also screened | tie |

**Do not overstate the journal.** MEASURED-SELF, this run, all 6 records:
```
cat …/subagents/workflows/wf_d8303f9f-4e4/journal.jsonl
{"type":"started","key":"v2:e27b1079…","agentId":"a36983a00fc52b349"}   ×6
```
Every record is `started`; **zero `result` records** at the time of writing (run in flight — this is
exactly the "started with no result" population the landed oversight research counted at 271/2,778).
Keys are `{type, key, agentId}` only: **no label, no phase, no prompt, no model, no timestamp.** The
`key` is a content sha256 (`v2:` prefix) — its purpose is *resume cache identity*, not audit. So the
journal cannot answer "which agent did what, when." The per-agent transcripts **can** (I located my
own by grepping a marker I had echoed: `grep -l "W2MARKER-UNIQUE-7f3a2b" …/*.jsonl`) — but no tool
we own reads them, and correlating a label to an agentId requires reading the script and the
transcripts side by side. **The raw material for AUDIT exists; the index does not.** That is a
sharper statement than "❌ AUDIT" and it names a buildable fix.

### 2e. MODEL / EFFORT PINNING

| | Teammate | Workflow agent |
|---|---|---|
| Model, per member | `model?: "sonnet" \| "opus" \| "haiku" \| "fable"` — a **4-value alias enum** (Q, `sdk-tools.d.ts:499-502`); also settable via agent-definition frontmatter `model:` | `opts.model` — a **free string**, *"overrides the model for this agent call"* (Q). Default advice in the doc: omit, inherit the resolved session model. |
| Effort, per member | **none on the call.** Inherited: an assignee gets `--effort <lead's value>` on argv (2.1.220). Only settable by writing `.claude/settings.local.json` into the member's worktree before spawn. | `opts.effort` inline, `'low'…'max'` (Q) |
| Honored? | model: honored by an assignee; a bare subagent reads it too, but **both fall back on allowlist rejection** (P: `agent-teams` skill §Per-Teammate Effort/Model) | **UNMEASURED** — see §3 |

The practical read: **workflows win the per-member routing axis outright.** A workflow can run its
cheap mechanical stages at `effort:'low'` and its adversarial verify at `'max'` in the same script.
Teams cannot express that at all without a filesystem side-channel per worktree.

### 2f. THE COMPLETE WORKFLOW PRIMITIVE LIST — the basis for every "cannot" above

QUOTED verbatim from the binary's Workflow tool description (extraction:
`LC_ALL=C strings -a -n 6 claude.exe | grep -n "skips its remaining stages."` then read ±9 KB):

> - `agent(prompt, opts?: {label?, phase?, schema?, model?, effort?, isolation?: 'worktree', agentType?})`
> - `pipeline(items, stage1, stage2, ...)` — no barrier between stages
> - `parallel(thunks)` — a BARRIER
> - `log(message)` · `phase(title)` · `args` · `budget: {total, spent(), remaining()}`
> - `workflow(nameOrRef, args?)` — nesting one level only

**That is the whole surface.** There is no `send`, no `resume`, no `continue`, no `ask`, no handle
returned by `agent()` that could be addressed later. The "cannot continue a workflow agent" finding
is therefore *not* a failed search — it is an exhaustive enumeration of the API.

Additional binding constraints on the **script** (not the agents): `Date.now()`, `new Date()` and
`Math.random()` **throw** (they would break resume); **no filesystem or Node API** in the script
body. So the orchestrator itself cannot read a file, check a git status, or stamp a time — every
such fact must be fetched by an `agent()` and returned as a string.

### 2g. TOOL SURFACE + HARNESS PARTICIPATION (measured on myself)

| | Teammate | Workflow agent (MEASURED-SELF) |
|---|---|---|
| Own OS process | **YES** — `claude.exe --agent-id`, 382 MB, 18 threads (P) | **NO** — my Bash tool's PPID is **99124**, the lead's own `claude` process (`ps -o ppid= -p $$`). No `--agent-id` process exists between us. |
| Own session id | YES | **NO** — `CLAUDE_CODE_SESSION_ID=f285654f-850c-4ada-96b5-407c5c01ccf0` = **the lead's** |
| Own pane / tty | YES (P) | **NO** |
| `Agent` tool (can spawn a teammate) | YES | **NO** — `ToolSearch("select:Agent,Workflow,StructuredOutput,SendUserMessage,ObserverReport")` → *"No matching deferred tools found"*, and none are in the resident list. Positive control: `select:SendMessage,TaskList,TaskGet,TaskStop` returned all four. |
| `Workflow` tool (can nest) | YES | **NO** (same probe) · `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1` |
| `SendMessage` | YES | **present but resolves to `main` only** (§2b) |
| Task board (`TaskList`/`TaskUpdate`) | YES | **YES** — `CLAUDE_CODE_TASK_LIST_ID=claude-infrastructure-main`; the board is injected into my context |
| `Skill` | YES | **YES** |
| CLAUDE.md / MEMORY.md inheritance | YES | **YES** — full project + user memory is in my system prompt |
| Write / Edit / Bash | YES | **YES** |
| **Our PreToolUse hooks fire?** | YES | **YES — and this is the surprise.** MEASURED-SELF: I echoed `W2MARKER-UNIQUE-7f3a2b` and it appears in `~/.claude/logs/bash-commands.log`, stamped `[f285654f-850c-4ada-96b5-407c5c01ccf0]`. |

**The hook finding needs stating precisely, because it both corrects and worsens the prior read.**
The landed research's "0 of our 7 gates" is about **Agent-spawn** gates — correct, and unchanged: a
workflow agent is never *spawned* through the Agent tool, so no spawn gate sees it. But **tool-level
PreToolUse hooks DO fire** on a workflow agent's Bash calls. So the class is not ungoverned at the
tool layer.

The worse half: **it is logged under the LEAD's session id.** Every attribution mechanism in this
repo keys on session id — `hooks/lib/session-writes.sh` (the transcript's own edit records),
`completion-assert.sh`, the mechanical-🔧 arm, the ship floor, custody. So **a workflow agent's
uncommitted files convict the LEAD**, and a lead cannot distinguish its own loose end from its
workflow's. For a research wave that writes six .md files, that is noise. For an implementation wave
where eight agents each leave a dirty tree, the lead's close ledger becomes uninterpretable — and
the ship-floor / mechanical-🔧 machinery, which exists precisely to make "reaching idle on your own
loose end a mechanism failure", fires on work the lead did not do and cannot attribute. A teammate,
having its own session id, is attributed to itself.

---

## 3. What I could NOT measure, and why

1. **Lead → workflow-agent direction, executed.** I cannot act as the lead, so I could not *run*
   `SendMessage({to:"<some workflow agent>"})` from the main conversation. The claim rests on
   (a) the enumerated `agent()` opts having no `name`, (b) `AgentInput.name`'s doc making `name` the
   thing that confers addressability, and (c) the resolver's four roster sources, none of which a
   workflow agent enters. **Strength: strong structural + a confirming negative from my side**
   (I see no roster at all). Not a direct execution. → **This is exactly what the W2 verifier should
   run:** from the lead, `SendMessage({to:"teammate-only-capabilities"})` (my `label`) and
   `SendMessage({to:"a78518b03eeb3be55"})` (my agentId). If either lands in my transcript, my
   claim 1 is REFUTED. I expect both to fail with "not reachable".
2. **Whether `opts.model` accepts an arbitrary model id** (e.g. `claude-opus-5`) or is coerced to
   the same 4-alias set. I have no `Workflow` tool, so I cannot run a probe. The doc does not
   constrain the string; the Agent tool's does. **UNMEASURED — do not claim workflow model pinning
   is finer-grained until someone runs `agent(p,{model:'claude-opus-5'})` and reads the transcript's
   model field.**
3. **A `result` journal record.** This run had none yet (6/6 `started`). So I could not confirm the
   `result` record's shape or whether it carries a label. Prior fleet counts (P) suggest results are
   frequently never written at all.
4. **Whether a teammate really persists across N turns, re-run this session.** I could not spawn
   one. That half is QUOTED (live `SendMessage` description; the `resumableAgentId` /
   `pendingUserMessages` / poll-loop machinery in the binary) and P (landed research), not
   re-measured. It is also not seriously in doubt — it is the documented purpose of the `name`
   parameter.
5. **Whether `PostToolUse`/`Stop` hooks fire for a workflow agent.** I measured only PreToolUse-Bash.
   A workflow agent has no Stop of its own (it has no session), so `Stop`-hook machinery — which is
   where this repo's entire close-integrity system lives — almost certainly never runs for it, but I
   did not prove that. **INFERRED, flagged.**

---

## 4. The decision this axis changes

**It does not settle the rule change; it fixes what the rule change must be about.** The question is
usually posed as "can a workflow agent write code?" — it can, it has Write/Edit/Bash, and the answer
is uninteresting. The question this axis says to ask instead is:

> **Does this piece of work need to be CORRECTED mid-flight, or only CHECKED afterwards?**

- **Only checked afterwards** → the workflow is *superior*, and not marginally. Its reviewer cannot
  be forgotten, its verify stage is guaranteed to run, its fan-out width is a number rather than a
  vibe, its budget throws instead of advising, and a failed run replays the good parts free
  (`resumeFromRunId`). That describes research, audits, sweeps, and mechanical migrations — the work
  where each unit is independently checkable from its artifact.
- **Needs correcting mid-flight** → the workflow is *structurally unable*, and no amount of prompt
  quality fixes it. There is no address, so there is no message; the only interventions are skip and
  restart-from-zero, both of which discard the context that made the agent worth correcting. That
  describes most implementation waves in this repo, where the lead's highest-value act is a
  two-sentence redirect at minute 20.

**Three concrete consequences for the CLAUDE.md wording, from this axis alone:**

1. **The current rule's stated reason is wrong even though its verdict may be right.** The rule says
   background subagents are research-only *because they don't write code*. That is false for
   workflow agents (they have the full write surface, plus `isolation:'worktree'`). The defensible
   reason is **unaddressability**: *a unit you cannot message cannot be corrected, only discarded.*
   If the rule is kept, restate it on that ground, or it will keep being re-litigated by every
   session that notices workflow agents can Write — which is what happened today.
2. **A workflow agent's writes are attributed to the lead's session.** Any amendment permitting
   workflow-run implementation must state what happens to the close ledger, or it silently breaks
   the mechanical-🔧 / ship-floor / custody arms. This is a *prerequisite to build*, not a caveat.
3. **Per-member `effort` is a real workflow-only win and teams should not pretend otherwise.** If
   the rule stays team-first for implementation, it should acknowledge that a workflow is the only
   way to run a mixed-effort wave, and point at `set-teammate-effort.sh` as the clumsy team
   equivalent.

**Ranked list of what would have to exist for a workflow to be a legitimate implementation locus**
(this axis's contribution to the wave's item 5):

| # | Gap | Buildable by us? |
|---|---|---|
| 0 | *(already exists, free)* **upward escalation**: a workflow agent can `SendMessage({to:"main"})` | **Already there.** An implementation workflow should be *briefed to use it* — "message main before you do anything destructive / if the brief looks wrong". It is the only oversight lever that costs nothing to adopt. |
| 1 | **An address per workflow agent** — anything that lets `SendMessage` resolve one | **No.** `agent()` has no `name`; the run is one task with private controllers. Vendor change. |
| 2 | **Per-agent stop** | **No.** `TaskStop` takes the run. (Skip/retry exist in `/workflows` — operator-only, and they discard context.) |
| 3 | **Session-distinct write attribution** | Partly — our hooks could key on `agentId` if the harness exposed it to the hook payload. **UNVERIFIED whether it does.** |
| 4 | **A labelled, timestamped journal** | **Yes, cheaply** — a PostToolUse/side-car indexer joining `label` → `agentId` → transcript. The transcripts already exist. |
| 5 | **Stop-hook participation** (close ledger, DoD, custody) | **No** — a workflow agent has no Stop. |

Items 1, 2 and 5 are vendor-side. That, not any cost argument, is the real size of the gap.

---

## 5. Probe ledger (per method rule 3)

Nothing was killed, closed, or torn down. No process was spawned. Exactly three side-effecting acts:

1. `SendMessage({to:"w2-nonexistent-probe-target"})` — failed by design; zero side effect.
2. `SendMessage({to:"main"})` — one labelled line into the lead's next turn. It provoked the lead's
   `W2-LEAD-OBSERVATION-inbound-probe.md`, corrected in §2b-bis. Not cleaned up: it is evidence.
3. Scratchpad writes under this session's own scratchpad dir (`w2-strings.txt`, a 412,384-line
   `strings` dump of the 2.1.220 binary, and `w2-dsl-doc.txt`, the extracted Workflow DSL doc).
   Left in place deliberately — sibling axes on this wave can reuse them; the dir is session-scoped.

All reads of the live fleet were `ps`/`ls`/`grep` only.
