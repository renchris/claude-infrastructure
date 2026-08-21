# W6 — The standing rule: what it says, where it came from, what it should say now

**Axis:** the mandate itself, not the capability. Companion axes W1–W5 answer *can a workflow
implement*; this one answers *what is our rule, why does it exist, and does it still bind*.

**Box / binary:** M1 Max, 10 cores, 64 GiB, CC **2.1.220**
(`~/.claude-220/node_modules/@anthropic-ai/claude-code/bin/claude.exe`, 256,908,272 B).
**Repo state:** worktree HEAD `9709c99d3`; `CLAUDE.md` is **byte-identical** on worktree HEAD,
`origin/main`, and the live layer `~/.claude/CLAUDE.md` (773 lines, three-way `diff` clean), so every
`file:line` below is authoritative on all three.

---

## 1. Verdict

1. **The mandate cannot be superseded by workflows, because on this binary it does not bind at all.**
   It commands `team_name`; the 2.1.220 Agent tool has no such parameter, and in 14 days across all
   five account stores **0 of 1,251 Agent calls used `team_name` alone** — all 31 that carried it also
   carried `name`, which is what actually made them teammates.
2. **Both HARD enforcements of the mandate are unreachable, and the one still-reachable gate
   prescribes an impossible cure.** Run head-to-head on identical inputs: the shape 2.1.220 emits
   (`name:`, no `team_name`) → **allow** for a 300-line brief *and* for an off-allowlist model; the
   legacy `team_name` shape → **deny** for both. The still-live background-subagent DENY tells the
   model to "use TeamCreate first, then … `team_name`" — neither exists on this runtime.
3. **What the rule actually protects is (c) a reviewable, stoppable, attributable unit** — the hook has
   said so verbatim since birth (2026-04-17): *"Implementation tasks require Agent Teams **for
   visibility and coordination**."* Not (a) a separate process, not (b) a worktree: `isolation` was set
   on **1 of 1,251** Agent calls in 14 days, and that one was a probe.
4. **Workflows are not forbidden by the rule — they are absent from it.** § Agent Teams Reinforcement
   never names the Workflow tool. Its only appearance in the whole of `CLAUDE.md` outside "Git Commit
   Workflow" is `CLAUDE.md:195`, inside the *product-side line being overridden*. The taxonomy is
   binary (teammates write / subagents research) and workflows are in neither bucket.
5. **Therefore: rewrite the mandate regardless of the wave's capability verdict.** Bind it to the
   invariant (addressable + isolated writes) and make the BACKEND a per-wave declared choice. Draft
   prose for all three verdicts — including "no change" — is in §6.

---

## 2. The rules, verbatim, with file:line

### 2a. `CLAUDE.md` § Agent Teams Reinforcement — the mandate

`/Users/chrisren/Development/claude-infrastructure/CLAUDE.md:129-136`
(identical at `~/.claude/CLAUDE.md:129-136` and `origin/main:CLAUDE.md`):

> ```
> ## Agent Teams Reinforcement (All Projects)
>
> **Agent Teams are the DEFAULT for all implementation work.** This applies globally.
> Code-writing tasks with 2+ files MUST use Agent Teams (`team_name` + worktree isolation). Spawn
> API is runtime-specific (see the **agent-teams** skill § Runtime assumption): classic `TeamCreate`
> on stable 2.1.114; on the 2.1.183 implicit-team model there is no `TeamCreate` — spawn via
> `Agent({ name, team_name, model: opus|fable-5 })`. Background subagents (no `team_name`) are for
> research/exploration only — never for code changes.
> ```

**Parallelise-by-default** — `CLAUDE.md:138-144`:

> 🚨 **PARALLELIZE BY DEFAULT — and this rule OUTRANKS any runtime instruction to the contrary**
> (operator standing directive 2026-07-29). … **A "clean opportunity" = 2+ pieces of work that are
> independent (no shared file, no ordering dependency) and each self-verifiable** …

**The two-units amendment** — `CLAUDE.md:146-156` (this is the 2026-08-07 correction that already
demoted the mandated unit):

> 🚨 **Parallelism has TWO units, and the bigger one is the DEFAULT for implementation.** … So the
> mandated delegation unit above was the one that does *not* protect the scarcest resource: **a plan
> could obey the Agent-Teams rule perfectly and still burn the lead's judgment on implementation
> detail it will never need again.** Therefore, for an implementation **wave or phase**, the default
> locus is a **dispatched session** …

**Teammates-inside / research-unaffected** — `CLAUDE.md:188-192`:

> Teammates remain correct **inside** such a session (that session is then the lead of its own team),
> and on the lead itself only when a wave's members must be synthesised against each other immediately
> AND their combined output is small. Read-only research fan-out is unaffected — subagents return
> findings, not implementations.

**The brief discipline (the crash-derived half)** — `CLAUDE.md:202-205`:

> **Split during planning, not after crash.** If any teammate's deliverable >500 LOC,
> SPLIT into 2-3 teammates in Phase 0. **Brief body ≤150 lines** (tightened from 200
> after tp-assignee crash 2026-05-03). Reading list >5 files = too wide. `/compact`
> crashes teammates (GH #49593) — preventive splitting is the only reliable path.

**The subagents-never-write clause, second statement** — `CLAUDE.md:224-227`:

> ## Research Subagents Reinforcement (All Projects)
>
> Research subagents (no `team_name`, fire-and-forget) are disjoint from Agent
> Teams; teammates write code, subagents never do.

### 2b. `skills/plan-conventions/SKILL.md` § Execution locus — the S/T/L field

`skills/plan-conventions/SKILL.md:53-66` — the locus table, verbatim:

| Locus | Mechanism | Whose context pays | Use when |
|---|---|---|---|
| **S · dispatched session** (DEFAULT) | `handoff-fire.sh --prompt-file <brief> --worktree <br> --notify-back <lead-uuid> --goal '…'`, lead arms `cc-await-ping` in background | the CHILD's | **every implementation wave.** Needs no justification. |
| **T · teammates** | `Agent({name, …})` in-session | the LEAD's | members must be synthesised against each other *immediately* AND their combined output is small |
| **L · lead-inline** | the lead edits the files itself | the LEAD's, in full | the wave is ONE file's control flow and is genuinely unsplittable |

`skills/plan-conventions/SKILL.md:72-74`:

> **T and L each need ONE line of justification in the plan. S never needs a reason.** Naming the
> locus is mandatory even when it is S: an unnamed locus resolves to L in practice, because writing
> the code is what a lead does when nothing told it not to.

`skills/plan-conventions/SKILL.md:76-80`:

> **Why S is the default — a mechanism, not a preference.** … Locus T — the *only* delegation unit
> Phase 0 mandated before this rule — routes every teammate's output back INTO the lead. So a plan
> that obeyed the Agent-Teams rule perfectly still spent the lead's window on implementation detail it
> would never need again: **delegating harder made the protected thing worse.**

**There is no W. The locus enum is closed at three, and a workflow has no row.**

### 2c. `skills/agent-teams/SKILL.md` — the decision table

`skills/agent-teams/SKILL.md:84-90`:

| Task Type | Pattern |
|---|---|
| Writes/modifies code (2+ tasks) | Agent Teams (TeamCreate + worktrees) |
| Writes/modifies code (1 task) | Single agent in lead session OR one assignee |
| Research/exploration (no code) | `Explore` subagent (read-only, fire-and-forget) |
| 50+ parallel read-only tasks | Subagents |
| **Re-checking work YOU just did** | **Never spawn for this.** See below. |

`skills/agent-teams/SKILL.md:316-318`:

> - **Teammates** (`name:` set): **DEFAULT for all implementation.** Persist until shutdown. Max **6 concurrent**. Use for ANY task that writes code.
> - **Subagents** (NO `name:`): Research/exploration ONLY. Safe at ~50 parallel. Never for code changes.

🚨 **The skill already corrected itself and the mandate did not follow.**
`skills/agent-teams/SKILL.md:50-53`:

> 🚨 **`team_name` DOES NOT EXIST on 2.1.220 — `name:` ALONE is the gate** (binary-extracted
> 2026-08-03; this section said `team_name` for weeks and that argument was inert). The Agent tool's
> own destructure is `{prompt, subagent_type, description, model, run_in_background, name, isolation,
> cwd}`.

That correction landed **2026-08-03**. `CLAUDE.md:132` and `hooks/agent-teams-enforce.sh` were never
updated. **17 days of a mandate naming a parameter its own skill documents as nonexistent.**

### 2d. The only landed policy statement about workflows — and it is in the RESEARCH skill

`skills/research-subagents/SKILL.md:392-395`:

> - **Prefer Workflows for waves >~10 agents** — the only surface where per-slot model+effort is
>   pinnable (in-process subagents inherit lead effort, GH #25591), AND the only surface where the
>   Sonnet-5@max worker free win above is realizable.

The operator's opening framing — *"I first thought Dynamic Workflows were for outward RESEARCH"* — is
**exactly what the repo already codifies**, and it is codified nowhere else.

---

## 3. What `hooks/agent-teams-enforce.sh` actually enforces — MEASURED by running it

### 3a. Where it is wired

| Question | Answer | Command |
|---|---|---|
| Registered on which events? | `PreToolUse` matchers: `Bash` · `Write\|Edit\|MultiEdit` · **`Agent`** · ms365-mail · `AskUserQuestion` | `jq -r '.hooks.PreToolUse[].matcher' ~/.claude/settings.json` |
| **Does it fire for the `Workflow` tool?** | **NO — there is no `Workflow` matcher anywhere in `settings.json`.** | same command; and `grep -rn "Workflow" ~/.claude/settings.json` → one hit, `"skipWorkflowUsageWarning": true` (a UI flag, line 1106) |
| Any hook in the repo referencing Workflow? | 1 file, `hooks/model-permission-decider.py:390`, and only as an allow-list string `"WebSearch,Skill,Workflow,ToolSearch,SendMessage"` — a permission passthrough, not a gate | `grep -rln "Workflow" hooks/` |
| What input does it key on? | `team_name`, `run_in_background`, `prompt`, `subagent_type`, `model` | `sed -n '25,31p' hooks/agent-teams-enforce.sh` |

### 3b. Reachability — two probes, identical 300-line implementation brief

Command (run in-repo, gates disabled so only the teams logic answers):

```bash
BIG=$(python3 -c "print('\n'.join('line %d implement refactor modify the schema'%i for i in range(300)))")
# A — the shape 2.1.220 actually emits
jq -nc --arg p "$BIG" '{tool_input:{name:"impl-1",prompt:$p,description:"implement"}}' \
  | CC_LINEAGE_GATE=off CC_ADMIT_GATE=off bash hooks/agent-teams-enforce.sh
# B — the legacy shape
jq -nc --arg p "$BIG" '{tool_input:{team_name:"t1",prompt:$p,description:"implement"}}' \
  | CC_LINEAGE_GATE=off CC_ADMIT_GATE=off bash hooks/agent-teams-enforce.sh
# C — the still-live DENY arm
jq -nc '{tool_input:{run_in_background:true,prompt:"implement the migration and refactor the schema, modify the file",description:"impl"}}' \
  | CC_LINEAGE_GATE=off CC_ADMIT_GATE=off bash hooks/agent-teams-enforce.sh
```

| Probe | Input shape | Verdict | Meaning |
|---|---|---|---|
| **A** | `name:` set, **no** `team_name` — **what 2.1.220 emits** | **`allow`** + nudge: *"has no team_name … MUST use Agent Teams (TeamCreate + team_name + worktree isolation)"* | The 250-line brief **DENY does not fire**. The nudge instructs the model to set a parameter that is not in the tool's schema. |
| **B** | `team_name` set — the legacy shape | **`deny`**: *"Teammate brief is 300 lines — at/over the 250-line hard cap … GH #49593 … tp-assignee 2026-05-03"* | The hard cap works — over an input the runtime never produces. |
| **C** | bare + `run_in_background:true` + ≥2 impl keywords | **`deny`**: *"Background subagents cannot write code … use TeamCreate first, then spawn agents with team_name"* | **Reachable** (355/1,251 calls set `run_in_background`), and its prescribed cure is impossible on this runtime. |

🚨 **A SECOND gate is dead the same way — the teammate model allowlist** (`hooks/agent-teams-enforce.sh:508`,
`if [ -n "$TEAM_NAME" ] && [ -n "$MODEL" ]`). Same off-allowlist model, two shapes:

```bash
jq -nc '{tool_input:{team_name:"x",model:"claude-sonnet-4",prompt:"implement and refactor the schema"}}' \
  | CC_LINEAGE_GATE=off CC_ADMIT_GATE=off bash hooks/agent-teams-enforce.sh   # → deny
jq -nc '{tool_input:{name:"x",     model:"claude-sonnet-4",prompt:"implement and refactor the schema"}}' \
  | CC_LINEAGE_GATE=off CC_ADMIT_GATE=off bash hooks/agent-teams-enforce.sh   # → allow
```

`team_name` shape → **`deny`** *("model='claude-sonnet-4' is not on the Max-plan allowlist"*; SSOT
`~/.claude/model-config.yaml .auto_mode_allowlist.non_firstParty_max` = `claude-opus-4-8`,
`claude-opus-5`, `claude-fable-5`). `name:` shape → **`allow`**. So on 2.1.220 **a teammate can be
spawned on any model with no allowlist check at all**, and the documented consequence — off-allowlist
models *"silent-demote to acceptEdits and break team parallelism"* (`:501-502`) — is unguarded. Edit 2
in §6a repairs both gates in one line, because both key on the same dead variable.

**Why nobody noticed:** the hook's own suite feeds it the legacy shape.
`tests/agent-teams-enforce.bats:36-38` —
`run_hook() { # $1=team_name … '{tool_input:{team_name:$tn,prompt:$p,model:$m}}' | bash "$HOOK" }`.
Green suite, unreachable subject. (This repo's own memory names the class:
`sibling-guard-makes-the-fixture-vacuous`, `control-calibrated-to-implementation-decays`.)

### 3c. What the fleet actually does — 14-day corpus census

Population: `find` over **all five** account transcript roots (`~/.claude`, `-secondary`,
`-tertiary`, `-quaternary`, `-next`) `-name '*.jsonl' -mtime -14` → **3,164 files**; every
`tool_use` block parsed, keyed on `input` shape. (Five roots, per memory
`transcript-corpus-spans-four-account-stores` — a one-root census reads ~26%.)

| Agent-tool shape | count | share | what it means |
|---|---|---|---|
| `name` only — **the real teammate gate** | **823** | 65.8% | the mandate's intent, expressed via a parameter the mandate does not name |
| bare (no `name`, no `team_name`) — in-process subagent | **397** | 31.7% | |
| `name` **and** `team_name` | **31** | 2.5% | `team_name` rode along inert; `name` did the work |
| **`team_name` only** | **0** | **0.0%** | **the mandated mechanism has never once been the operative gate** |
| any `isolation:` | **1** | 0.08% | value `worktree`; description `"Probe worktree isolation repo"` — a probe, not production |
| `run_in_background: true` | 355 | 28.4% | keeps probe C's DENY live |
| `Workflow` tool calls (same window) | **67** | — | unnamed by any policy surface |

**Reading:** worktree isolation — the parenthetical in `CLAUDE.md:132` — is **not** what the Agent
tool delivers here. Where the fleet does get per-task worktrees it gets them from
`handoff-fire.sh --worktree` (locus **S**), which the mandate does not mention and the amendment at
`CLAUDE.md:146-156` made the default two weeks ago.

---

## 4. Provenance — the rule's REASON is not its SCOPE

| Date | Event | Source (grounded) | What it licenses |
|---|---|---|---|
| **2026-04-17** | `hooks/agent-teams-enforce.sh` created, 71 lines. Its DENY text — *"Background subagents cannot write code. Implementation tasks require Agent Teams **for visibility and coordination**"* — is **unchanged to this day**, 678 lines later. | `git log --diff-filter=A -- hooks/agent-teams-enforce.sh` → `c8d8c64e3`; `git show c8d8c64e3:hooks/agent-teams-enforce.sh` | **The rule's own stated purpose: visibility + coordination.** Nothing about processes, panes, or worktrees. |
| 2026-04-17 / 04-18 / 04-21 / **05-03** | Four teammate crashes: `doctor-green-gate`, `routines-v1 Wave 2`, `validators-p0`, `tp-assignee`. *"all trace to **brief-design errors** — not teammate output sizing."* | `skills/agent-teams/SKILL.md:115-119` | The **≤150-line brief cap**. A fact about how much text you may hand a teammate. |
| 2026-05-03 | tp-assignee: *"A `/compact` crashed a teammate (GH #49593) mid-task."* Transcript **PRUNED** (pre-2026-06-10 retention floor) — **CLAUDE.md-sourced only.** | `docs/research/desk-audit-2026-07-18/p11-forensics.md:62-68` and `:6` | The `/compact` half of the same brief cap. **The primary evidence no longer exists to re-read.** |
| 2026-06-06 | The mandate text first enters version control — inside a commit titled *"version-control … CLAUDE.md"*. It arrives **already written**; git holds no authoring event for it. | `git log -S 'MUST use Agent Teams' -- CLAUDE.md` → `b7342b018` | Nothing. The prose has **no recoverable rationale of its own** — only the hook's. |
| **2026-08-03** | `team_name` measured absent from the 2.1.220 Agent tool; skill corrected. `CLAUDE.md` and the hook **not** corrected. | `skills/agent-teams/SKILL.md:50-53` | The staleness that made the mandate inert. |
| **2026-08-07** | The two-units amendment demotes teammates: the mandated unit *"does **not** protect the scarcest resource."* | `CLAUDE.md:146-156`; `skills/plan-conventions/SKILL.md:76-80` | The mandate had already been overruled on its *default*, without its *wording* changing. |
| 2026-08-12 | *"`/compact` crashing teammates (GH #49593) is a **near-zero risk in this fleet because nobody compacts**"* — 203 `compact_boundary` records, every `trigger` value `"manual"`, zero `auto`. | `docs/research/backlog-pipeline-recon-2026-08-12/recon-wave.md:132-135` | One of the two named hazards behind the brief cap is **dormant**. |

**The separation this axis was asked for.** Every incident behind the mandate is an incident about
**how you brief a teammate** (too long → context exhaustion → `/compact` → crash). Not one is an
incident about *a non-teammate unit writing code*. A rule written because teammates crashed on big
briefs is evidence about **brief size**, and carries **zero** evidential weight on whether some other
unit may implement. The scope was never earned; it was inherited from a hook comment written the same
day as the first crash.

---

## 5. The honest question: which of (a)/(b)/(c)/(d) does the rule protect?

| Candidate | Evidence FOR | Evidence AGAINST | Verdict |
|---|---|---|---|
| **(a) a separate OS process per code task** | `name:` yields a real `claude.exe --agent-id` process + pane (landed `4a3bd3373`); 823/1,251 calls take it | The rule's text never says "process"; the hook never checks for one; and `handoff-fire.sh` (locus S) gives a process too, yet the mandate does not mention it | **Not the protected thing** — it is a side-effect of the chosen mechanism |
| **(b) an isolated worktree per code task** | `CLAUDE.md:132` parenthetical *"(`team_name` + worktree isolation)"*; the skill table says *"TeamCreate + worktrees"* | **`isolation` set on 1 of 1,251 Agent calls in 14 days**, and that one was a probe. The hook never reads `isolation` at all. Real worktrees come from locus **S**, which the mandate does not name | **Aspirational, never enforced.** Genuinely load-bearing — see §6 — but the *current* rule does not deliver it |
| **(c) a reviewable, stoppable, attributable unit** | The hook's own words since 2026-04-17: *"for **visibility and coordination**"*, verbatim through 9 rewrites; `agent-teams/SKILL.md:320-328` treats naming as a **lifecycle** decision (*"`name:` is the switch"* — a named agent persists and needs explicit teardown); the whole oversight matrix (`de3e82802`) is built on this axis | none found | ✅ **This is what the rule protects.** |
| **(d) "just don't do it inline on the lead"** | The parallelise-by-default directive (`CLAUDE.md:138-144`) | Explicitly refuted by the repo itself: `plan-conventions:76-80` — locus T routes output back *into* the lead, so *"delegating harder made the protected thing worse"*; **L is still a legal locus** with one line of justification | **Not it** — the rule permits lead-inline, so "not on the lead" cannot be the invariant |

**So the discriminator for workflows is (c), plus the (b) the rule promised and never delivered.** The
question is not *can a workflow agent call `Write`* — it is *can you see it, stop it, and attribute
its writes, and are those writes isolated from every sibling's tree*. The wave's already-landed
oversight matrix answers the first half **❌** for the workflow `agent()` class (no pane → no
`cc-teardown`; not a teammate → no `shutdown_request`; no registry row; no mailbox; 9 agents minted /
0 ledger rows in a window holding 874 others).

**One nuance the draft must not overstate.** The 2.1.220 bundle *does* carry
`killWorkflowTask` · `pauseWorkflowTask` · `skipWorkflowAgent` · `retryWorkflowAgent`
(`LC_ALL=C strings -a -n 6 …claude.exe | grep -n Workflow` → lines 134068-134074). So a STOP path
exists **product-side**; what is absent is a stop path in **anything we own**. Write the rule to say
that precisely — "our control plane cannot reach it" — not "it cannot be stopped", or the rule ships
a claim the next binary can falsify.

---

## 6. Draft replacement wording — ready to paste

All drafts are **INTEGRATE, not overwrite**: each is an `Edit` to a named line range, preserving the
surrounding rationale paragraphs (`CLAUDE.md:138-205` and the whole amendment block are untouched).

### 6a. VERDICT-INDEPENDENT — land this even if the answer is "no change"

The mandate names a dead parameter and its hard gate is unreachable. This is true whatever W1–W5
conclude, and it is the highest-value edit in this document.

**Edit 1 — `CLAUDE.md:131-136`** (replace the paragraph; everything from line 138 on is unchanged):

```markdown
**Agent Teams are the DEFAULT for all implementation work.** This applies globally.
Code-writing tasks with 2+ files MUST run in a unit that is ADDRESSABLE and WRITE-ISOLATED — see
the invariant below. 🚨 **On 2.1.220 the switch is `name:`, NOT `team_name`** (binary-extracted
2026-08-03; the Agent tool's destructure is `{prompt, subagent_type, description, model,
run_in_background, name, isolation, cwd}` — `team_name` is not in it, and 0 of 1,251 Agent calls in
a 14-day fleet census used `team_name` alone). A named Agent call becomes a teammate: its own
process, pane and lifecycle, persisting until an explicit `shutdown_request`. Classic `TeamCreate` +
`team_name` exists only on stable 2.1.114. Background subagents (no `name:`) are for
research/exploration only — never for code changes.
```

**Edit 2 — `hooks/agent-teams-enforce.sh`, one new variable + two branch conditions** (the bodies of
both gates are unchanged and become reachable for the first time on this binary):

```bash
# After the parameter extraction at :26-30 —
# 2.1.220 has no `team_name`; `name:` is the teammate switch (skills/agent-teams/SKILL.md:50-53).
# Accept either, so the brief cap and the model allowlist stop being dead code on this runtime.
NAME=$(echo "$INPUT" | jq -r '.tool_input.name // empty')
TEAMMATE_ID="${TEAM_NAME:-$NAME}"

# :508  →  if [ -n "$TEAMMATE_ID" ] && [ -n "$MODEL" ]; then      # model allowlist
# :561  →  if [ -n "$TEAMMATE_ID" ]; then                          # ≤150 warn / ≥250 deny brief cap
```

Red-proof before landing: probes A and the `name:`-shape model probe in §3b must FLIP (allow → deny)
on the identical inputs, and probe B must stay `deny` — one mutant per site, per memory
`per-site-mutation-attributes-coverage`.

**Edit 3 — the two DENY/nudge reasons at `hooks/agent-teams-enforce.sh:656` and `:670`**: replace
`use TeamCreate first, then spawn agents with team_name parameter set` with
`re-spawn with name: set (2.1.220 has no TeamCreate and no team_name), or dispatch the wave with scripts/handoff-fire.sh --worktree`.
A gate that prints a cure the runtime rejects is this repo's own named defect
(memory `work-item-remedy-can-become-forbidden`).

**Edit 4 — `tests/agent-teams-enforce.bats:36-38`**: `run_hook()` must drive `{name: …}`, with **one**
retained `team_name` case pinned as the 2.1.114-legacy control. Today the whole suite is green over a
shape the current runtime cannot emit.

### 6b. IF the wave's verdict is "workflows CANNOT carry an implementation wave" (expected)

Add — do not replace — one paragraph after `CLAUDE.md:192` (i.e. after *"subagents return findings,
not implementations"*), and one row to the plan-conventions locus table.

```markdown
**Dynamic Workflows are a RESEARCH and BATCH surface, never an implementation locus — and the reason
is oversight, not capability** (measured 2026-08-20, `docs/research/workflows-vs-teams-2026-08-20/`).
A workflow `agent()` can hold write tools; that is not the test. The test is the invariant this whole
section protects, stated in the enforcement hook since 2026-04-17: *implementation runs in a unit we
can SEE, STOP and ATTRIBUTE.* A workflow agent fails all three **in our control plane**: no pane (so
no `cc-teardown`), not a teammate (so no `shutdown_request`), no registry row, no mailbox, and 0 of
our 7 Agent-tool gates fire on it — measured, 9 agents minted with 0 ledger rows in a window holding
874 others; `settings.json` has no `Workflow` PreToolUse matcher at all. (The binary itself ships
`killWorkflowTask`/`pauseWorkflowTask`, so a product-side stop exists — it is simply not reachable
from anything we own. Re-measure that before citing this sentence: it is a perishable fact about the
harness.) Largest historical run: 229 agents / 7.2 h / 39 quota points, unabortable by us throughout.
Quota compounds the verdict rather than driving it: in-process fan-out is **2.43–3.53× worse per
quota point** than a teammate (31,503 output tokens per point vs 8,936), so the memory-cheap unit is
the expensive one. **Use Workflows where `skills/research-subagents/SKILL.md:392` already says to —
read-only waves >~10 agents, the only surface where per-slot model+effort is pinnable.**
```

And in `skills/agent-teams/SKILL.md:84-90`, add one row to the decision table:

| Task Type | Pattern |
|---|---|
| Read-only wave >~10 agents, per-slot model/effort needed | **Dynamic Workflow** (`research-subagents` skill §392) |
| **Any task that writes code** | **Never a Workflow** — no pane, no `shutdown_request`, no registry row, no gate fires |

### 6c. IF the verdict is "workflows CAN implement, under conditions" — the backend becomes a per-wave choice

Then the mandate keeps its force and loses its mechanism. Replace the first sentence of Edit 1 with:

```markdown
**Code-writing tasks with 2+ files MUST run in a unit that is ADDRESSABLE and WRITE-ISOLATED — the
backend is a per-wave choice, the invariant is not.** ADDRESSABLE = at any moment the operator can
SEE what it is doing, STOP it with one command we own, and ATTRIBUTE every write to it.
WRITE-ISOLATED = its own worktree + branch, so no two concurrent writers share an index. Declare the
backend in Phase 0's execution-locus field (S · T · L · W) and name, in one line, how the wave
satisfies both halves. A backend that cannot satisfy them is not eligible, whatever its cost profile.
```

…and add the **W** row to `skills/plan-conventions/SKILL.md:53-66`:

| Locus | Mechanism | Whose context pays | Use when |
|---|---|---|---|
| **W · dynamic workflow** | `Workflow({script})` with `agent(brief, {isolation:'worktree', model, effort})` | the workflow run's — the lead pays only the script it wrote and the run summary | ≥8 independent same-shaped tasks, each self-verifying, **and** the wave declares its stop path and its per-agent worktree. **Ineligible without both.** |

⚠️ **The `isolation:'worktree'` in that row is INFERRED, not measured by W6.** Evidence: the workflow
`agent()` option object destructures `{schema, effort, isolation, agentType}`
(`strings … | sed -n '170395,170402p'`) and the runtime's isolation validator accepts exactly
`worktree|remote` (`sed -n '155138,155150p'`) — one validator, shared with the Agent tool. **Verdict
6c must not ship until a wave axis has RUN a workflow agent with `isolation:'worktree'` and shown the
worktree on disk.** Without it, the write-isolation half of the invariant is unmet and 6b is the
correct verdict by default.

### 6d. IF the verdict is "no change"

Then §6a still lands, and one sentence is added after `CLAUDE.md:192` so the question stops
recurring:

```markdown
**Dynamic Workflows were evaluated as an implementation locus on 2026-08-20 and rejected**
(`docs/research/workflows-vs-teams-2026-08-20/`). They remain the preferred surface for read-only
waves >~10 agents (`skills/research-subagents/SKILL.md:392`). Re-open only on a measured change to
the oversight matrix — a `Workflow` PreToolUse matcher, a registry row, or a stop path we own.
```

Recording the rejection **with its date and its re-open condition** is the point: an unanswered
question re-mints the same analysis every few weeks (memory
`refuted-open-row-remints-its-own-analysis`).

---

## 7. What I could NOT measure, and why

| Not measured | Why | The command that would settle it |
|---|---|---|
| **Whether `PreToolUse\|Write\|Edit\|MultiEdit` hooks fire for a `Write` issued *inside* a workflow agent** | Requires running a workflow that writes a file, then checking for the hook's side-effect. That is a live-fleet write action, outside a read-only axis, and it belongs to the capability axes. **This is the single fact my §6c draft is conditional on** — if the Write gates DO fire, workflow writes are already guarded by `check-edit-boundary.sh` and `backup-before-write.sh`, and 6c's bar is much easier to clear. | Run a one-agent workflow that writes `/tmp/w6-probe.txt`, then `ls -t ~/.claude/backups/ \| head` and grep the IDL for the same minute. |
| **Whether `agent({isolation:'worktree'})` actually provisions a worktree** | Bundle strings show the option key and a shared `worktree\|remote` validator, but a key in a destructure is not a working feature (memory `spec-named-mechanism-may-be-prose-only`). | Run it and `git worktree list` inside the agent. |
| **Whether the 31 `team_name`+`name` calls had `team_name` silently dropped** | The transcript records the *request*, not the runtime's post-validation input. | `--debug` on a live spawn, or the session's own argv (`ps -o args`) for `--team-name`. |
| **Absence of `TeamCreate` on 2.1.220 from my own vantage** | `ToolSearch` returns nothing for `TeamCreate`/`Workflow`/`Agent`, but **that negative is confounded**: the harness does not expose `Agent` or `Workflow` to subagents at all (`hooks/agent-teams-enforce.sh:288-293`), so this instrument cannot distinguish "absent" from "withheld from me". Positive control passed — the same query resolves `TaskCreate`. Authority rests instead on the bundle read + the corpus (0 `team_name`-only calls). | From a **main session**: `ToolSearch "select:TeamCreate"`. |
| **The tp-assignee 2026-05-03 primary evidence** | Transcript pruned below the 2026-06-10 retention floor; `CLAUDE.md`-sourced only (`p11-forensics.md:6`). The number "150 lines" now rests on a summary of a deleted artifact. | Unrecoverable. State it as inherited, not as measured. |

---

## 8. The decision this axis changes

**Before:** the operator asks *"do workflows supersede our Agent-Teams implementation rule?"* and the
answer sounds like a capability comparison.

**After:** the rule is not a live constraint that workflows could supersede. It commands `team_name`;
`team_name` does not exist on this binary; **both** its hard gates — the ≤150/250-line brief cap and
the teammate model allowlist — have been unreachable since the runtime dropped the parameter; its own
skill said so 17 days ago; its still-reachable DENY hands the model a
cure (`TeamCreate`) the runtime rejects; and its stated protection — worktree isolation — is delivered
by a different mechanism (locus **S**) that the mandate never names and that the 2026-08-07 amendment
already made the default. **Three edits (§6a) restore the rule to binding, and they are independent of
whatever W1–W5 conclude.**

**And the workflow question resolves on oversight, not capability.** Whatever a workflow agent *can*
write, the rule's own invariant since 2026-04-17 is *visibility and coordination* — see, stop,
attribute. Our control plane reaches a workflow agent on none of those axes and `settings.json` has no
`Workflow` matcher, so today the honest verdict is **§6b**: workflows stay the research/batch surface
`skills/research-subagents/SKILL.md:392` already made them, and the rejection is recorded **with its
date and its re-open condition** so the question does not re-mint itself in three weeks.

**The re-open condition, stated once so it is testable:** a `Workflow` PreToolUse matcher in
`settings.json`, a registry row per workflow agent, a stop path in something we own, **and** a RUN
demonstration of `agent({isolation:'worktree'})` producing a worktree on disk. All four, or §6b holds.
