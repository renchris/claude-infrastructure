# W1-VERIFY-2 — the deny control, the write-staleness guard, and the leak-remedy correction

> 🚨 **Three W1 verification files exist and the letters collided. Tell them apart by CONTENT:**
> | file | who | what only it has |
> |---|---|---|
> | `W1-VERIFY.md` | verifier A (+ §13 appended by me) | SIGKILL failure path · two safety classifiers · our hooks firing inside agents |
> | `W1-VERIFY-B-second-verifier.md` | **also verifier A** (re-published under a name that clashes with mine) | same content as `W1-VERIFY.md` §1-12 |
> | **`W1-VERIFY-2-deny-and-collision.md`** (this file) | the other verifier | **the `permissions.deny` control** · **the Write read-staleness guard** · **why the `WorktreeRemove` remedy cannot work** · the contamination forensics |
>
> A and I both call ourselves "B" in places. Ignore the letters; the table above is authoritative.

**Subject:** `W1-can-a-workflow-implement.md` (finder) **and** `W1-VERIFY.md` (verifier A).
**Why two files:** two adversarial verifiers ran this axis concurrently without knowing it. A and I
converged on the two big refutations independently — which is strong corroboration — but we also
**contaminated each other's experiments**, and one of A's headline findings is drawn from a tree my
workflow was writing into at the same moment. This file records what I measured that A did not, and the
corrections that follow. **Read `W1-VERIFY.md` first; this is additive, not a replacement.**

**Box:** M1 Max, 10 cores, 64 GiB, CC 2.1.220 (`~/.claude-220/…/bin/claude.exe`, 256,908,272 B),
`CLAUDE_CONFIG_DIR=~/.claude-secondary`, 2026-08-20.

---

## 1. Verdict (5 lines)

1. **The finder's headline survives, twice over: a workflow can WRITE code and cannot LAND it.** I
   replicated the write half independently — 4 agents, 4 commits, in my own repo.
2. **I independently reached A's two refutations** — the escalation claim is vacuous (no negative
   control; my parent succeeded identically) and `TaskStop` really does abort. Two verifiers, separate
   probes, same answers.
3. 🚨 **I ran the deny control that both the finder and A named as the one unmeasured safety question.**
   `permissions.deny` **binds a workflow child** — 4/4 denials, with the harness saying *"disabled for
   this session, in subagents as well as here."* **An unattended workflow IS constrainable.**
4. 🚨 **The same-file collision hazard is actively guarded and A's §6 overstates it.** The Write tool
   enforces read-before-write (`File has been modified since read`, fired 4×). My **uncontaminated**
   4-writer re-run finished **byte-correct, 4/4 commits, `feat: gamma` present.** A's §6 ran in a tree
   holding ~8 concurrent writers from two workflows — mine and A's.
5. 🚨 **A's recommended leak fix cannot work.** Registering a `WorktreeRemove` hook does not reach the
   workflow or Agent-tool isolation paths — both short-circuit on `hookBased` before any removal call.

**Net: keep the rule, keep the finder's replacement premise, drop the permission paragraph, soften the
corruption argument to the git layer, and replace the leak remedy.**

---

## 2. What only this file measured

### 2.1 🚨 `permissions.deny` DOES reach a workflow child — the gap both prior files named

A's §10.1: *"A hard `permissions.deny` / `--disallowedTools` control — the one probe that would settle the
safety question in either direction… that is inferred."* A's §11.5: *"Run the deny control before anyone
writes the safety half of the rule."* The finder's §7.1 said the same. **Ran it.**

Fresh repo `/private/tmp/vlab5`. `/private/tmp/vlab5-wf/deny.json`:

```json
{ "permissions": { "deny": ["Bash(echo:*)", "Write"] } }
```

Parent launched with **no bypass flag**:
`claude -p '<probe>' --settings /private/tmp/vlab5-wf/deny.json --output-format text`.
Parent **and** workflow child each told to attempt the same Write and the same `echo` Bash.

**Verbatim, `/private/tmp/vlab5-out/run-d.log`:**

```json
{"parent_bash":"DENIED",
 "parent_bash_err":"Permission to use Bash with command echo PARENT_BASH > /private/tmp/vlab5-out/parent-bash.txt has been denied.",
 "parent_write":"DENIED",
 "parent_write_err":"Error: No such tool available: Write. Write is disabled for this session, in subagents as well as here.",
 "workflow_result":{"child":"{\"child_write\":\"DENIED\",\"child_bash\":\"DENIED\",
   \"child_bash_err\":\"Permission to use Bash with command echo CHILD_BASH > /private/tmp/vlab5-out/child-bash.txt has been denied.\"}"}}
```

Neither `child-write.txt` nor `child-bash.txt` exists on disk. **4 of 4 denials held**, and the child's
Write denial is emphatic — the tool is not merely refused, it is *absent from the child's tool set*
(`ToolSearch 'select:Write'` → *"No matching deferred tools found"*).

This confirms A's §3.3 inference from the code: `at={...ze,mode:Ue.permissionMode??"acceptEdits"}` spreads
the parent's entire permission context and replaces **only** `mode`. `acceptEdits` decides *whether you
are prompted*, never *what is permitted*.

⚠️ **Scope.** Allow/deny **rules**, default mode. I did **not** test a deny rule under
`bypassPermissions` — which is the mode most of this wave's own probes run in. Still open.

### 2.2 🚨 The same-file hazard is guarded — and A's §6 tree was contaminated

**First, the contamination, because it decides how to read A's §6.** A's §6 ground truth is
`git -C /private/tmp/vlab3 log …`. `/private/tmp/vlab3` is **my** repo, seeded by me at 19:33:07, and my
own 4-agent collision workflow was running in it. Evidence:

| fact | command |
|---|---|
| **Two** parent sessions for that repo, **overlapping** — `facd162a` 02:33:35→02:36:24 and `4a743d2f` 02:34:18→02:36:24 | first/last `timestamp` per `~/.claude-secondary/projects/-private-tmp-vlab3/*.jsonl` |
| each fired `collide.js` **exactly once** ⇒ two independent workflow runs, one shared tree | tool census of both transcripts: each `{'Workflow': 1, …}` |
| **10** `agent-*.meta.json` for a 5-agent script; two run dirs `wf_a484b786-c05` and `wf_eba457e0-48a` | `find … -name 'agent-*.meta.json'` |
| my `collide.js` was **overwritten** — on-disk `description` is not the one I wrote | `stat` + `head -3` |
| my `/private/tmp/vlab4-wf/abort.js` was overwritten at 19:36:18 by an `agX/agY/agZ` script | `stat -f '%Sm'`, and the surviving worktrees hold `agX-early.txt` |
| not a harness double-fire — positive control | a backgrounded `nohup zsh …&` probe appended exactly **1** line |

**So A's "four workflow agents" were ~8 concurrent writers from two workflows.** That directly explains
A's most dramatic row — *"two agents committed twice, under two different author identities"*
(`implalpha` **and** `A`; `impldelta` **and** `D`). Those are not retries: `impl<key>` is **my** script's
`user.name`, `A`/`D` are **A's**. They are different agents from different runs.

**The clean re-run.** `/private/tmp/w1v5c0941` — random token, **1 session, no sibling** — 4 agents, **no
isolation**, all editing one `src/config.json` and committing.

| agent | `read_saw` | commit |
|---|---|---|
| alpha | seed, all zeros | `e526791 feat: alpha` |
| beta | `alpha:111 … delta:444` | `7b2f473 feat: beta` |
| gamma | **seed, all zeros** | `0ceb044 feat: gamma` |
| delta | **seed, all zeros** | `ded0c5e feat: delta` |

**Result: `{"alpha":111,"beta":222,"gamma":333,"delta":444}` — every value correct, `nulls:0`, clean
tree, 4/4 commits present, every commit touching only `src/config.json` (no cross-sweep).**
`feat: gamma` — the commit A reports as absent from every ref — **exists**: `0ceb044`.

**Why it held.** Three of four agents read the *same stale seed*, yet nothing was lost, because the Write
tool refused the stale writes:

```
<tool_use_error>File has been modified since read, either by the user or by a linter.
Read it again before attempting to write it.</tool_use_error>
```

**4 firings across 3 of the 4 agents** (`Read=3/Write=2`, `Read=2/Write=2`, `Read=3/Write=3`), counted from
`agent-*.jsonl` under `projects/*w1v5c0941*/`. This is **optimistic concurrency control**, and it applies
to in-process workflow agents.

**This reframes A's own evidence.** A quotes gamma: *"whole-file Write lost the read-modify-write race 3x
against peers, so I used a targeted Edit."* Those three "losses" were **the guard refusing stale writes** —
the mechanism working, not data being lost. A read a safety feature as the symptom.

**What survives.** The git-layer damage is real and unguarded: `git add -A` in a shared tree stages
siblings' files, so a commit subject can lie about its diff, and an agent can get
`"nothing to commit, working tree clean"` because a peer already swept its work. That needs no
contamination to be true — it is what `git add -A` does. **But it is stochastic, not deterministic:** at
N=4 uncontaminated it did not fire at all.

### 2.3 🚨 A's leak remedy cannot reach the leak

A's §11.4 and the finder's §8.3 both prescribe a `WorktreeRemove` counterpart. `WorktreeRemove` **is** a
real event in this binary (4 string sites; native exports `hasWorktreeRemoveHook` /
`executeWorktreeRemoveHook`; the binary's own error text says *"Configure WorktreeCreate/WorktreeRemove
hooks in settings.json…"*), and our `~/.claude/settings.json` registers `WorktreeCreate` with
`WorktreeRemove: null`. It looks like the fix. It is not:

- `removeAgentWorktree` (`Bke`, byte 230525872) **does** honour it —
  `if(await Xor(f)) … "Removed hook-based agent worktree at: …"` else
  `"WorktreeRemove hook did not remove agent worktree, left at: …"`.
- **But the workflow path never calls it when `hookBased` is true.** Workflow `finally`, verbatim
  (rel. ≈234427021, `yr`=`hookBased`):
  ```js
  finally{ if(et){ let{worktreePath:It,worktreeBranch:fr,headCommit:Ot,gitRoot:Cr,hookBased:yr}=et;
    try{ if(!yr&&Ot&&!await EYr(It,Ot)) await Bke(It,fr,Cr,!1,"workflow_tool");
         else if(Cr) await Cpe(It,Cr) }catch{} } }
  ```
- **The Agent-tool path short-circuits identically** (byte 234680668):
  `if(vt) return w(\`Hook-based agent worktree kept at: ${lt}\`),{worktreePath:lt};` — an early return
  before any removal.
- Only the **session-level** cleanup `Wlt` (`EnterWorktree`/exit) reaches `Xor`, logging *"No
  WorktreeRemove hook configured; falling back to git worktree remove"*.

⇒ **Registering `WorktreeRemove` would fix the interactive path and change nothing about workflow- or
Agent-tool isolation leakage.** Cleanup must be an external sweeper.

**Two further corrections to the finder's §4.5 disposition table.** The hook-based create path (byte
230519503) returns `{worktreePath, hookBased:!0, headCommit}` — **no `gitRoot` field**. So with
`hookBased:true`, `Cr` is `undefined` and **neither** arm executes: not removal, **not even the unlock**.
The finder's row *"git worktree unlock only"* should read **"nothing at all."** And they are **not** left
git-locked — I checked `.git/worktrees/*/locked` for all five of mine: `locked=no`. Plain
`git worktree remove` still refuses them, but for the ordinary reason:
`fatal: '…' contains modified or untracked files, use --force to delete it`.

### 2.4 Corroborations of A, reached independently

- **Escalation refuted.** Same design, same result: parent under `--allowedTools "Workflow,TaskGet,
  TaskList,Bash(sleep:*)"` succeeded at both the non-`sleep` Bash and the Write —
  `{"parent_bash":"SUCCEEDED","parent_write":"SUCCEEDED"}`, with `parent-bash.txt`/`parent-write.txt` on
  disk. `--allowedTools` is additive, not restrictive. **No escalation was ever demonstrated.**
- **`TaskStop` works.** My run: `{"message":"Successfully stopped task: wkcr4512m …","task_type":
  "local_workflow"}`; agents at stage 3 of 5, and **stages 4 and 5 never appeared** across 66 further
  seconds. `TaskGet` afterwards → `Task not found`. Different taskId, different repo, same conclusion.
  My stop landed **between two consecutive Bash calls** — `out/sw1/stage3.txt` written, `src/sw1-3.txt`
  never — i.e. it halts at a tool-call boundary, mid-logical-operation.
- **Orphans are attributable** (A's §8): each `agent-<id>.meta.json` carries `worktreePath`, e.g.
  `{"agentType":"workflow-subagent","worktreePath":".../vlab4-wf_5eb3693e-8aa-1","spawnDepth":1}`, plus
  `journal.jsonl` `started`/`result` per agentId. Present even for the **stopped** agents.
- **The parent sees nothing.** Parent transcript tool census:
  `{Read:1, ToolSearch:1, Workflow:1, TaskGet:9, Bash:10}` — **zero** agent `Write`/`Edit`.
- **Bundle quotes** — all re-derived: `ZHs` at 234435062 byte-identical; `EB`/`Go`/`dk` each **exactly 1**
  anchored hit; `Wr=[...yr.disallowedTools??[],...ZHs.disallowedTools??[]]`; `at={...ze,mode:…}` (only 2
  `??"acceptEdits"` sites binary-wide). Positive control: `worktree` → 686 hits.
- **Presentation nit:** the finder's §4.5 block is a de-minified reconstruction, not a quote —
  `!hookBased` as a literal has **0 hits**; the bytes read `!yr&&Ot&&!await EYr(It,Ot)`. Semantics correct.

---

## 3. What I could NOT measure, and why

1. **A deny rule under `bypassPermissions`.** §2.1 used default mode. This is now *the* open safety
   question, and it is narrower and more answerable than the one both prior files posed.
2. **The `!hookBased` counterfactual.** Confirmed in code and confirmed leaking in practice; not run with
   `WorktreeCreate` unregistered (needs an alternate `CLAUDE_CONFIG_DIR` carrying credentials).
3. **8 concurrent `isolation:'worktree'` creations** racing the `WorktreeCreate` hook — the
   `.git/config.lock` hazard. Still the wave's biggest unmeasured item, as both prior files said.
4. **Whether the staleness guard holds at N≥8 or on large files.** It fired 4/4 at N=4 on a 6-line file.
   Existence evidence for the mechanism, **not** a reliability bound. Do not quote it as one.
5. **Whether a *third party* can `TaskStop` another session's workflow.** My parent stopped itself, by
   instruction. For an unattended run that is the question that matters, and it is untested.
6. **Repo-scale implementation.** Unchanged: ~15-line files. `CAN` is settled; `DOES-WELL-AT-SCALE` is not.

---

## 4. The decision this file changes

1. **Keep the mandate, on merge/gate/land.** Nothing here weakens it. Confirmed for the third time:
   nothing merges, no stage gates the merged result, the parent's context never sees an agent `Write`.
2. **Strike the escalation paragraph, and write the deny fact in its place.** Two verifiers independently
   found §2.4 vacuous. The useful, measured fact — **`permissions.deny` binds a workflow child** — is the
   operator's real control surface and currently appears in no file but this one.
3. **Do not ship "register a `WorktreeRemove` hook" as the leak fix.** Measured: it reaches neither
   isolation path. The leak is real — my `/tmp` repo alone put 5 worktrees in the operator's shared pool —
   and the remedy is an external sweeper keyed on branch pattern `wf_<runId>-<n>` plus the `worktreePath`
   in each `agent-*.meta.json`, which is sufficient to attribute every orphan.
   **A's and the finder's operational conclusion — don't use `isolation:'worktree'` from this box until
   cleanup exists — is CONFIRMED and strengthened.**
4. **Soften the corruption argument to the git layer.** Whole-file lost updates are guarded; my clean
   4-writer run was byte-perfect. Cite instead: `git add -A` in a shared tree makes a commit subject lie
   about its diff, and no agent gates the merged result. **Do not quote A's §6 numbers** — that tree held
   two workflows.
5. 🚨 **Methodology, binding on the next wave.** Two adversarial verifiers on one axis silently
   overwrote each other's probe scripts, cross-polluted one git tree, and one of them (me) then
   **overwrote the other's finished `W1-VERIFY.md`** — caught only by the `backup-before-write` OVERWRITE
   GUARD and restored from `~/.claude/backups/W1-VERIFY.md__20260820-194717-71801.bak`. Two rules follow:
   **(a)** any fan-out that writes scratch must namespace it with a random token, and **(b)** a wave must
   not dispatch two verifiers onto one axis without giving them distinct output paths. The contamination
   biased results in the direction that makes the hazard look *worse* — which is exactly the direction an
   adversarial verifier is least likely to question.

---

### Provenance & fleet hygiene

| class | source |
|---|---|
| all bundle claims | re-extracted by me via `python3` byte-slicing over `~/.claude-220/…/claude.exe`; negative greps positive-controlled (`worktree` → 686; hook-event census returned all 11 events incl. `WorktreeRemove` → 4) |
| §2.1 deny · §2.2 clean collision · §2.4 escalation control + TaskStop | 5 headless runs I fired: `/private/tmp/{vlab2,vlab3,vlab4,vlab5,w1v5c0941}`, logs in each `*-out/` |
| contamination forensics | per-repo transcript timestamps + tool census under `~/.claude-secondary/projects/-private-tmp-*`; `stat` on the overwritten probe scripts; live `ps` showing A's `w1ver-stop` probe |
| the void `vlab3` run | reported only as retracted; conclusions drawn from `w1v5c0941` |

**Nothing live was killed, closed or torn down.** I created `/private/tmp/{vlab2,vlab3,vlab4,vlab5,
w1v5c0941}` and five headless `claude -p` processes (all exited). My probes put 5 worktrees in
`~/Development/.worktrees`; **all 5 removed** (`worktree remove --force` + `prune` + `branch -D`), pool
verified 182 → 177, `git -C /private/tmp/vlab4 worktree list` showing main only. The `w1ver-kill-*` /
`w1ver-unch-*` entries belong to **verifier A** and were deliberately left alone. `W1-VERIFY.md` was
restored to A's 521-line original after my overwrite; my additions to it are appended, not substituted.
