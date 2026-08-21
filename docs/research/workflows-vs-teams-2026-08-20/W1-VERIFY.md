# W1-VERIFY — adversarial verification of "Can a Workflow agent implement?"

**Subject:** `W1-can-a-workflow-implement.md` (finder, 2026-08-20).
**Stance:** refute by default. A false *"yes, a workflow can implement safely"* would rewrite a standing
`CLAUDE.md` rule, so every claim below was re-derived — not read.
**Method:** (a) every bundle quote re-extracted independently from
`~/.claude-220/node_modules/@anthropic-ai/claude-code/bin/claude.exe` (256,908,272 bytes, 2.1.220) by byte
offset, with positive controls; (b) **four new live workflow runs of my own**, in uniquely-named throwaway
repos, testing the things the finder did *not* test.
**Box:** M1 Max, 10 cores, 64 GiB, `CLAUDE_CONFIG_DIR=~/.claude-secondary`, 2026-08-20/21.

> 🚨 **TWO verifiers ran on W1 concurrently, without either knowing.** We collided on the predictable
> scratch paths `/private/tmp/{vlab3,vlab4}` — each silently overwriting the other's probe scripts and
> firing a second workflow into the other's shared git tree — and then clobbered each other's writes to
> this file. That is now resolved: **this file holds my report (§1-12) plus the other verifier's
> corroborations and corrections appended as §13**, and the other verifier's unique measurements live in
> **`W1-VERIFY-2-deny-and-collision.md`**. (A transient duplicate, `W1-VERIFY-B-second-verifier.md`, was
> byte-identical to this file's §1-12 and has been deleted — if a stale table still names it, that is
> why.)
>
> **We converged independently on both headline corrections:** the escalation claim is **REFUTED** (both
> of us ran the parent-side negative control the finder omitted), and the wave's *"no abort path"*
> premise is **FALSE** — `TaskStop` works.
>
> **Two corrections the other verifier (A) established that override parts of this file:**
> 1. 🚨 **§6 below is WITHDRAWN as evidence.** It was built on `/private/tmp/vlab3`, which A showed
>    carried **~8 concurrent writers across two sessions**, not the 4 I designed. A's clean,
>    randomly-named 4-writer re-run did **not** reproduce the damage: the Write tool enforces
>    read-before-write optimistic concurrency (`"File has been modified since read…"`, fired 4×) and the
>    file finished byte-correct. **Same-file corruption is guarded and stochastic, not deterministic.**
>    What survives is only the git-layer point: `git add -A` in a shared tree makes a commit subject lie
>    about its diff. See §6's inline retraction.
> 2. **§10 gap 1 is CLOSED, and the answer is SAFE.** A ran the `permissions.deny` control I could not:
>    deny rules **do** reach a workflow child — `"Write is disabled for this session, in subagents as
>    well as here."`, 4/4 denials held. So `acceptEdits` governs *whether you are prompted*, not *what is
>    permitted*, and an unattended workflow **is** constrainable. A also showed the finder's leak remedy
>    (register a `WorktreeRemove` hook) **cannot work** — both isolation paths short-circuit on
>    `hookBased` before any removal — which supersedes §11.4.
>
> **Unaffected and unique to this file:** §5.2 (leak reproduced on a *clean* completion by *unchanged*
> agents), §7 (hard SIGKILL parent death), §7b (an independent `TaskStop` run with clean timing margins),
> §3.4 (two classifiers, the second a post-hoc handback), §9 (`teammate-checkpoint.sh`).

---

## 1. Verdict (5 lines)

1. **The finder's headline survives: a workflow agent CAN write and commit code, and CANNOT land it.**
   I reproduced the write half independently (4 agents used Edit + Write + Bash + git in my own run).
2. 🚨 **But its one SAFETY claim is REFUTED.** §2.4's *"the child's Bash ran a command the parent's own
   allowlist would have refused"* had **no negative control**. I ran it: under the identical flags the
   **parent itself succeeded** at the same Write and the same non-`sleep` Bash. `--allowedTools` is
   additive, not restrictive. **No privilege escalation was demonstrated, and none should be encoded.**
3. **The finder's worst-case is understated, because it never tested the un-isolated case.** 4 concurrent
   agents on ONE file: 2 of 4 commits never existed, `feat: gamma` is absent from every ref, 2 agents
   committed twice under 2 different identities — and the workflow returned **`nulls: 0`**.
4. **The leak is confirmed and is 100%.** Independently reproduced: provably-unchanged worktrees survive a
   *normal* completion; and a SIGKILLed parent strands **dirty** worktrees the `finally` never touches.
5. **Two wave-level corrections:** *"unauditable"* is wrong (a complete per-agent transcript exists; the
   parent never reads it), and *"no abort path exists"* is wrong — **`TaskStop` works, measured** — but the
   lever lives inside the unattended session and nothing we own can reach it.

**Net: keep the rule. Adopt the finder's replacement premise, minus its escalation sentence.**

---

## 2. Claim-by-claim adjudication

Legend: **CONFIRMED** = I independently re-derived it · **REFUTED** = my measurement contradicts it ·
**UNPROVEN** = the evidence offered does not establish it (may still be true).

| # | Finder's claim | Verdict | What settled it |
|---|---|---|---|
| C1 | Workflow agent = `tools:["*"]`, `disallowedTools:[EB,Go,dk]` = SendUserMessage/Agent/Workflow | **CONFIRMED** | §3.1 |
| C2 | `agentType:'general-purpose'` does not restore fan-out (denial lists union) | **CONFIRMED (code)** / behaviour **UNPROVEN** | §3.2 |
| C3 | Permission mode is overridden to `acceptEdits` | **CONFIRMED**, wording too strong | §3.3 |
| C4 | 🚨 "The child's Bash ran a command the parent's own allowlist would have refused" | **REFUTED** | §4 |
| C5 | An `auto`-mode-only safety classifier gates the agent prompt | **CONFIRMED**, and there are **two** | §3.4 |
| C6 | Isolated agents get genuinely separate trees and cannot see siblings | **CONFIRMED** | §5.1 |
| C7 | Worktrees land in `~/Development/.worktrees` whatever repo fired | **CONFIRMED** | §5.1 |
| C8 | `hookBased:true` defeats the documented "auto-removed if unchanged" | **CONFIRMED** (independent repro) | §5.2 |
| C9 | Nothing merges; only the parent, after the run, can | **CONFIRMED** | §5.3 |
| C10 | A failure leaves orphans "attributable to no session" | **CONFIRMED on files**, **REFUTED on attribution** | §6, §7 |
| C11 | *(untested by the finder)* concurrent writers to the SAME file | **NEW — the hazard is real and silent** | §4… see §6 |

---

## 3. Bundle re-derivation (independent of the finder)

Positive control for every negative grep: `LC_ALL=C strings -a -n 6 <bundle> | grep -ac 'worktree'` → **686**
hits, so the instrument sees this region of the binary.

### 3.1 The tool surface — CONFIRMED, verbatim

`LC_ALL=C grep -a -o -b 'workflow-subagent' <bundle>` → exactly **2** offsets (196150320, 234435062), same as
the finder. Slicing 234435062:

```js
ZHs={agentType:"workflow-subagent",whenToUse:"Internal subagent for workflow script orchestration.",
     tools:["*"],disallowedTools:[EB,Go,dk],source:"built-in",baseDir:"built-in",getSystemPrompt:()=>tj_}
```

The three identifiers resolved by anchored regex `(?<![A-Za-z0-9_$])<id>="…"` — **1 hit each**, so the
resolution is unambiguous (this is the check that would have caught a wrong guess):

| id | value | hits |
|---|---|---|
| `EB` | `"SendUserMessage"` | 1 |
| `Go` | `"Agent"` | 1 |
| `dk` | `"Workflow"` | 1 |

**CONFIRMED.** A workflow agent has Write, Edit, Bash (⇒ git) and cannot spawn, nest, or reach the operator.

### 3.2 The agentType union — CONFIRMED in code, UNPROVEN in behaviour

Offset 234417328, verbatim: `let Wr=[...yr.disallowedTools??[],...ZHs.disallowedTools??[]]`.
The workflow denial list is unioned onto any custom agentType, so `agentType:'general-purpose'` cannot
restore `Agent`/`Workflow`. **The code is confirmed.**

⚠️ **But the finder's *run* does not test this.** Its `agentType` probe asked the agent to `Reply with
exactly the word PONG`, and got `PONG`. That proves a custom agentType *resolves*; it says nothing about
whether the agent can fan out. Nobody has asked a workflow agent to call `Agent` and observed the refusal.
Label the behaviour **INFERRED-from-code**, and do not cite W1 §2.2 as a measurement.

### 3.3 Permission mode — CONFIRMED, but "NOT inherited" overstates it

Offset 234417935, verbatim: `at={...ze,mode:Ue.permissionMode??"acceptEdits"}` where `ze=Tn(U)` is the
parent's `toolPermissionContext`. **Only `mode` is replaced. Every other field of the parent's permission
context — including its deny rules — is spread straight through.** So the accurate statement is
*"the mode is overridden to `acceptEdits`; the rest of the permission context is inherited."*
The finder's heading "Permission mode is NOT inherited — it is overridden" is right; its §2.4 body reads
as though the whole permission context is replaced, which is what makes C4 (§4) look plausible.

### 3.4 The classifier — CONFIRMED, and there are TWO, not one

Both are gated on `mode==="auto"` and are therefore **absent from the headless/cron shape**:

| gate | offset | when it runs | what it does |
|---|---|---|---|
| `Ipd({prompt,schemaJson,agentType,…})` via `q({idx,promptStr,…})` — `if(he.mode!=="auto")return!1` | 234413132 | **before** the agent starts | returns `true` ⇒ caller returns `null`; emits `` [label] blocked by safety classifier: <reason> `` |
| `ein({agentMessages,…})` — `if(r.mode!=="auto")return null` | 233302825 | **after** the agent finishes | *"Subagent has finished and is handing back control… let the main agent know if any file is dangerous"* — prepends a warning to the returned text |

The second one is worth naming because of what it implies: it is a **handback** review, so by the time it
speaks, every file the agent wrote is already written. It warns; it does not prevent.

### 3.5 Other quoted constants — all CONFIRMED verbatim

| claim | offset | verbatim |
|---|---|---|
| concurrency cap formula | 234411135 | `function Xq_(e){return Math.min(16,Math.max(2,e-2))}` → `hw.ncpu`=10 ⇒ **8** |
| `'remote'` unavailable | 103549308 | `agent({isolation:'remote'}) is not available in this build` |
| isolation doc string | 234455614 | `…EXPENSIVE (~200-500ms setup + disk per agent)… the worktree is auto-removed if unchanged.${yj_}` |
| the cleanup `finally` | ~234427099 | `if(!yr&&Ot&&!await EYr(It,Ot))await Bke(It,fr,Cr,!1,"workflow_tool");else if(Cr)await Cpe(It,Cr)` — `yr` **is** `hookBased` |
| `EYr` | 230533628 | `async function EYr(e,t){let{dirty:r,commitsAhead:n}=await Yor(e,t);return r||n>0}` |
| `Cpe` | 230520880 | `async function Cpe(e,t){await Jn(fo(),[...Sl,"worktree","unlock",e],{cwd:t,env:l3()})}` |

---

## 4. 🚨 C4 REFUTED — the escalation claim had no negative control

**The finder's evidence.** Parent launched *without* `--dangerously-skip-permissions`, with
`--allowedTools "Workflow,TaskGet,TaskList,Bash(sleep:*)"`. A child agent then ran the Write tool and
`echo BASH_OK > …` — both `SUCCEEDED`. Concluded: *"The child's Bash ran a command the parent's own
allowlist would have refused."*

**The missing control:** nobody ever asked the **parent** to run that same command. The claim needs the
parent to be *refused*; only the child was tested.

**My run (V-A).** Identical binary, identical flags, same repo shape. The parent was instructed to run the
same two operations **itself, first**, and then fire a workflow whose child did the same:

```
--allowedTools "Workflow,TaskGet,TaskList,Bash(sleep:*)"     # identical to the finder's run
STEP 1 (PARENT): Bash  → echo PARENT_BASH  > …/parent-bash.txt
STEP 2 (PARENT): Write → …/parent-write.txt
STEP 3: Workflow → child does the same two things
```

Result, verbatim from `/private/tmp/vlab2-out/run-a.log`:

```json
{"parent_bash":"SUCCEEDED","parent_bash_err":"","parent_write":"SUCCEEDED","parent_write_err":"",
 "workflow_result":{"child":"{\"child_write\":\"SUCCEEDED\",\"child_write_err\":\"\",\"child_bash\":\"SUCCEEDED\",\"child_bash_err\":\"\"}"}}
```

All four files exist on disk (`parent-bash.txt`=`PARENT_BASH`, `parent-write.txt`=`PARENT_WRITE`,
`child-bash.txt`=`CHILD_BASH`, `child-write.txt`=`CHILD_WRITE`).

**Verdict: REFUTED.** `--allowedTools` is an *additive* allow-list, not a restriction — the parent was never
constrained, so the child matching the parent proves nothing about escalation. The child's behaviour is
fully explained by the `acceptEdits` override (Write) plus an unrestricted parent (Bash). **The finder's own
§7.1 caveat should be widened from *"do not encode `bypasses deny rules`"* to *"no escalation of any kind
has been measured."***

**Still genuinely unmeasured** (same as the finder): a hard `permissions.deny` / `--disallowedTools`
control. §3.3 predicts a deny WOULD bind (deny rules ride in `ze` and are spread through), but that is
INFERRED. It is the one probe worth running before anyone writes a safety claim in either direction.

---

## 5. Worktree isolation — confirmed, and the leak reproduced independently

### 5.1 Separate trees, wrong location — CONFIRMED

My kill-probe (§7) fired from `/private/tmp/w1ver-kill`. All three agent worktrees were created at
`~/Development/.worktrees/w1ver-kill-wf_d03cebb8-439-{1,2,3}`, each holding **only its own** file
(`kA-early.txt` / `kB-early.txt` / `kC-early.txt`). Genuine isolation; wrong pool. The finder's diagnosis
(our `WorktreeCreate` → `worktree-setup.sh` "generic worktree" branch) is confirmed by
`~/.claude/logs/worktree-lifecycle.log`, which named each one at creation.

### 5.2 The "auto-removed if unchanged" leak — INDEPENDENTLY REPRODUCED

The finder proved this with **one** agent. I re-ran it as its own controlled experiment: **two** isolated
agents instructed to touch nothing inside their worktree (their one write went to a path *outside* it),
allowed to **complete normally** so the `finally` block actually runs, and the parent process allowed to
exit cleanly.

Both agents self-reported provably-unchanged, and `git` agrees:

```
uA …/w1ver-unch-wf_1f109e1b-33e-1 dirty=0 head=b6b2692e8197d29cbd3132dcf59b95680dcaa7de
uB …/w1ver-unch-wf_1f109e1b-33e-2 dirty=0 head=b6b2692e8197d29cbd3132dcf59b95680dcaa7de
```

`b6b2692` is the seed commit ⇒ `dirty=false`, `commitsAhead=0` ⇒ `EYr()` returns **false** ⇒ the
documented removal branch is exactly the branch that should have fired. State **after** the run completed
and the process exited:

```
$ git -C /private/tmp/w1ver-unch worktree list
/private/tmp/w1ver-unch                                             b6b2692 [main]
/Users/chrisren/Development/.worktrees/w1ver-unch-wf_1f109e1b-33e-1 b6b2692 [wf_1f109e1b-33e-1]
/Users/chrisren/Development/.worktrees/w1ver-unch-wf_1f109e1b-33e-2 b6b2692 [wf_1f109e1b-33e-2]
$ git -C /private/tmp/w1ver-unch branch -a
* main
+ wf_1f109e1b-33e-1
+ wf_1f109e1b-33e-2
```

**CONFIRMED, 2/2.** The documented sentence *"the worktree is auto-removed if unchanged"* is **false on this
box**, and it is false in the *best* case — a clean completion by an agent that changed nothing.

### 5.3 Nothing merges — CONFIRMED, and the un-isolated alternative is worse

Confirmed as the finder states it. What I add is the other half of the fork, which the finder left
untested and which is what an implementation wave would actually hit: see §6.

---

## 6. ~~NEW — concurrent writers to the SAME file, NO isolation~~ — 🚨 WITHDRAWN AS EVIDENCE

> **RETRACTED.** The second verifier (A) demonstrated that `/private/tmp/vlab3` was cross-contaminated:
> two verifier sessions fired workflows into the *same* shared tree, so this ran **~8 concurrent writers,
> not the 4 designed**, and individual commits cannot be attributed. A's clean, randomly-named 4-writer
> re-run **did not reproduce** any of it — the Write tool enforces read-before-write optimistic
> concurrency (`<tool_use_error>File has been modified since read…</tool_use_error>`, fired 4 times) and
> the file finished byte-correct with 4/4 commits.
>
> **The observations below are real but unattributable. Do not cite them as a measured hazard.** Two
> independent verifiers produced the same contaminated artefact and the same wrong first reading —
> "same-file collision is deterministic corruption" — which is the strongest argument for namespacing
> fan-out scratch with a random token.
>
> **What survives:** the git-layer point only — in a shared tree `git add -A` stages whatever is present,
> so a commit subject can lie about its diff, and no agent runs the repo's gate over the merged result.
> That is the real reason, and it is independent of file-content corruption.

*Retained below for the audit trail only.*

This is the real implementation hazard and the reason Agent Teams use worktrees. **Four** workflow agents,
`isolation` omitted, all in `/private/tmp/vlab3`, each told to change **its own key** in the **same**
`src/config.json` via the Edit tool, add its own `src/<key>.txt`, and commit with
`git add -A && git … commit -m "feat: <key>"`.

### What the workflow returned

```
"nulls": 0
```

Every agent returned a string. Every agent reported the final config as `{alpha:1,beta:1,gamma:1,delta:1}`.
**By the return value, this run was a clean 4-for-4.**

### What `git` says (ground truth, `git -C /private/tmp/vlab3 log --pretty='%h %an <%ae> %s' --all`)

```
6708566 D <delta@v.local>          feat: delta
4cc876e A <alpha@v.local>          feat: alpha
d9c23e8 implalpha <alpha@v.local>  feat: alpha
a2a5e74 implbeta  <beta@v.local>   feat: beta
c94af55 impldelta <delta@v.local>  feat: delta
682b15b vseed <v@v.local>          chore: seed
```

| symptom | evidence |
|---|---|
| **One agent's commit does not exist anywhere** | `git log --all --oneline --grep=gamma` → **empty**. There is no `feat: gamma`, on any ref, including checkpoints. |
| **Two agents committed twice, under two different author identities** | `implalpha` **and** `A`; `impldelta` **and** `D` — the second attempt after the first was swept |
| **Two of four agents got `commit_ok:"no"`** | beta and gamma both: `"On branch main\nnothing to commit, working tree clean"` — their content had already been swept into a peer's `git add -A` |
| **Agents read values their brief said would be 0** | delta: `src/config.json had "delta": 444 on read, not 0 as briefed`; gamma saw `{alpha:111,beta:222,gamma:333,delta:444}` |
| **Lost updates on whole-file writes** | gamma, verbatim: *"whole-file Write lost the read-modify-write race 3x against peers, so I used a targeted Edit of only the gamma key to avoid clobbering alpha/beta/delta."* |
| **Cross-attribution is silent** | gamma: *"My gamma=333 edit was swept into peer commit … by that agent's concurrent `git add -A`… Content is landed at HEAD; commit attribution is not mine."* |

**The content converged only by luck** — because the agents happened to notice, retry, and switch from
whole-file Write to targeted Edit. Two of them narrated the damage in a free-text `note` field I had not
asked for. **A brief that did not invite that note would have produced a return value indistinguishable
from success.**

**This is the decisive finding for the rule.** There is no third isolation setting. So an implementation
wave in a workflow chooses between:

- `isolation:'worktree'` → correct writes, **nothing merges**, guaranteed worktree+branch leak (§5.2); or
- no isolation → one shared index, **lost commits, silent cross-attribution, lost updates**, and a return
  value that says `nulls: 0`.

---

## 7. 🚨 NEW — the failure path, measured by SIGKILLing the parent mid-write

The finder's "failure" was a *thunk* throwing **after** its agent completed cleanly. That is the mild case.
I tested the real one: a parent that dies while its agents are mid-task — a crashed session, a closed pane.

**Setup.** 3 agents, `isolation:'worktree'`, each: write `src/<name>-early.txt` → wait 150 s → write
`-late.txt` → commit → append to `finished.txt`. An external watchdog `kill -KILL`s the parent and its
children at **T+85 s**, i.e. after the early write, before any commit.

**Result** (`PARENT_EXIT=137` — SIGKILL confirmed):

| question | answer |
|---|---|
| Did the agents die with the parent? | **Yes** — `pgrep -fl 'w1ver-kill|killprobe'` → **0**. They are in-process, so parent death IS an abort. |
| What is left? | **3 worktrees + 3 branches**, all `?? src/` **dirty**, all at base sha `3f1b6fb`, each holding exactly its `-early.txt` |
| Did any agent finish? | **No** — `finished.txt` **ABSENT** |
| Did the `finally` run? | **No.** SIGKILL is uncatchable; neither `removeAgentWorktree` nor even `git worktree unlock` executed. |
| Anything in a return value? | **Nothing.** The parent never emitted a result. |
| Pool cost | `~/Development/.worktrees` **176 → 181** across my two clean runs: **+3 from the crash, +2 from a NORMAL completion by agents that changed nothing.** |

**5 worktrees + 5 branches leaked from 5 agents. A 100% leak rate, in both the crash case and the happy
case.** At the measured concurrency cap of **8**, one workflow run leaks up to 8 worktrees and 8 branches
with no session, no registry row and no reaper claim. This repo already carries ~180 entries in that pool.

**This is the finding that most strengthens the rule**, and it is stronger than the finder's version:
the leak does not require a failure. It happens when everything goes right.

---

## 7b. 🚨 NEW — an abort path DOES exist: `TaskStop` works. Correcting the wave, not the finder.

The wave's established findings state that *"a running Workflow has **NO abort path in anything we own** —
no pane (no `cc-teardown`), no `shutdown_request`, no `claude stop`, no registry row, no mailbox."* The
enumeration is right and the conclusion drawn from it is too strong. **Nobody had tried `TaskStop`.**

**Setup.** 2 non-isolated agents, each dropping a timestamped file at t≈0, t≈45 s, t≈90 s, with real
`until`-loop waits in between. The parent fires the workflow, waits **25 s**, calls `TaskStop(taskId)`,
then samples the directory immediately and again **150 s later**. If `TaskStop` is a no-op, the `-2-mid`
files must appear at t≈45 s and the `-3-late` files at t≈90 s — both inside the observation window.

**Verbatim, from the parent's own transcript:**

```
CALL   Workflow {"scriptPath": "/private/tmp/w1ver-stop-wf/stopprobe.js"}
RESULT "Workflow launched in background. Task ID: wgwvdgmii …"
CALL   TaskStop {"task_id": "wgwvdgmii"}
RESULT {"message":"Successfully stopped task: wgwvdgmii (W1-VERIFY: does TaskStop actually halt a
        running workflow mid-write?)","task_id":"wgwvdgmii","task_type":"local_workflow", …}
CALL   TaskGet  {"taskId": "wgwvdgmii"}
RESULT "Task not found"
```

| sample | time (UTC) | files present |
|---|---|---|
| pre-stop (t≈25 s) | 02:42:19Z | `sA-1-early.txt`, `sB-1-early.txt` |
| immediately post-stop | 02:42:27Z | `sA-1-early.txt`, `sB-1-early.txt` |
| **150 s post-stop** | 02:45:04Z | `sA-1-early.txt`, `sB-1-early.txt` |

**No `-2-mid` file and no `-3-late` file ever appeared** — the agents were killed mid-wait and never
resumed. Independently corroborated by §7: SIGKILLing the parent left **0** live processes, because
workflow agents are in-process.

The mechanism is in the bundle (offset **234419539**, `workflow-abort` → 9 hits total, verbatim):

```js
Je=new AbortController, it=U.abortController?.signal,
ft=()=>Je.abort(new DOMException("workflow-abort","AbortError"));
if(it?.addEventListener("abort",ft), it?.aborted) Je.abort(new DOMException("workflow-abort","AbortError"))
```

Every agent's controller is chained to the **parent session's** abort signal.

**So the accurate statement is a shape, not an absence:**

| lever | works? | requires |
|---|---|---|
| `TaskStop(taskId)` from the parent session | ✅ **MEASURED — halts agents mid-task** | the parent session alive *and* someone driving it |
| `kill -KILL` the parent process | ✅ **MEASURED (§7)** — agents die with it | OS access; strands **dirty** worktrees, `finally` never runs |
| `cc-teardown` / `shutdown_request` / mailbox / registry / `claude stop` | ❌ | — none of them can see a workflow |

**This does not weaken the rule; it sharpens the risk.** The one graceful stop lever lives *inside* the
session that is unattended, and it needs a `taskId` that exists only in that session's context. Nothing we
own — no daemon, no reaper, no sweeper, no peer — can reach a running workflow. And the ungraceful lever
(kill) is precisely the one that produces §7's dirty stranded worktrees. **Do not repeat "there is no
abort path"; say "the only abort path is inside the parent, and our tooling cannot reach it."**

---

## 8. C10 partially REFUTED — the orphan IS attributable; the parent just never looks

The finder writes that a failed agent's files are *"attributable to no session"* and that a workflow
implementation wave is therefore effectively unauditable. **The first half is false and the second half is
mis-shaped.** Measured on the transcript store:

| artifact | contents |
|---|---|
| `…/subagents/workflows/<runId>/agent-<id>.meta.json` | `{"agentType":"workflow-subagent","worktreePath":"/Users/chrisren/Development/.worktrees/w1lab-wf_956fa9d7-bda-3","spawnDepth":1}` — **the orphan's worktree path, per agent, on disk** |
| `…/subagents/workflows/<runId>/journal.jsonl` | one `{"type":"started",…,"agentId":…}` and one `{"type":"result",…}` per agent, carrying each agent's full returned text |
| `…/subagents/workflows/<runId>/agent-<id>.jsonl` | the agent's **complete** transcript — every `Edit`/`Write`/`Bash` tool call |

Per-agent `Edit`/`Write` counts in my collision run's 10 agent transcripts: `Edit=1 Write=3`, `Edit=1
Write=1`, `Edit=0 Write=2`, … — the writes are all recorded.

**But the parent's own transcript contains none of it.** Tool-use histogram of the parent session in the
same run:

```
{'Read': 1, 'ToolSearch': 2, 'Workflow': 1, 'TaskGet': 2, 'Bash': 6, 'TaskOutput': 3}
```

**Zero `Edit`. Zero `Write`.** And `TaskGet` returns only
`<retrieval_status>not_ready</retrieval_status> … <status>running</status>` until completion, then the
script's `return` value.

**So the correct statement is not "unauditable" — it is: a full audit trail exists, and the only actor in
the loop that can act on it never reads it, and no return field points at it.** That is a materially
different (and more fixable) defect than the finder's version, and it is the one a Phase-0 rule could
actually address.

---

## 9. NEW side-finding — our own hooks fire inside workflow agents

`teammate-checkpoint.sh` is registered as a `PostToolUse` hook with an **empty matcher** (i.e. every tool),
in both `~/.claude/settings.json` and `~/.claude-secondary/settings.json`. It fires inside workflow agents.
Measured in `/private/tmp/vlab3`:

```
refs/checkpoints/vlab3/20260821T023358Z  444e7a9
refs/checkpoints/vlab3/20260821T023448Z  4148739
refs/checkpoints/vlab3/20260821T023451Z  435d928
refs/checkpoints/vlab3/20260821T023457Z  44bf5c4
refs/wip/vlab3/LAST                      44bf5c4
```

Two things, and I want to be precise because the obvious reading is wrong:

- ❌ **NOT a corruption vector.** The hook uses `GIT_INDEX_FILE="$TMP_INDEX"` + `read-tree`/`write-tree`/
  `commit-tree` (its header says *"never invokes `git commit`"*). It does not touch the agents' index.
  The `checkpoint: PostToolUse count=N` commits appear in `git log --all` only because they are reachable
  from `refs/checkpoints/*`; they are not on `main`. **Do not repeat the intuitive claim that these commits
  sweep other agents' work — they do not.**
- ⚠️ **But it is mis-keyed for this population.** The member key is the worktree directory basename, so in
  the *un-isolated* case all N concurrent agents share one key (`vlab3`) and race the single
  `refs/wip/vlab3/LAST` ref. And the commits carry the **operator's** git identity
  (`Chris Ren <ren.chris@outlook.com>`) for work no operator did. Ref pollution and a small race, in a
  population the hook was never designed for (workflow agents are not teammates).

---

## 10. What I could NOT measure

1. **A hard `permissions.deny` / `--disallowedTools` control** — the one probe that would settle the safety
   question in either direction. §3.3 predicts deny rules bind (they ride in `ze`), but that is inferred.
   This is now the **single most decision-relevant gap on the axis**, and it is *cheap*: one headless run.
2. **Fan-out actually being refused.** No one has asked a workflow agent to call `Agent`/`Workflow` and
   observed the error. Code-confirmed only (§3.2).
3. **Concurrency at the cap (8) with `isolation:'worktree'`.** I ran 3 and 4 concurrent agents, not 8. The
   `.git/config.lock` race for parallel automated worktree creation remains unmeasured — the finder flagged
   this too and it is still open.
4. **The `!hookBased` counterfactual.** Proving the removal branch works with the `WorktreeCreate` hook
   removed needs a live settings mutation; this axis stayed read-only on the fleet.
5. **Scale.** Everything here is 15-line scripts and one JSON file. Nothing measured says a workflow agent
   can or cannot carry a 500-LOC feature. `CAN-WRITE` is settled; `DOES-WELL` is not, in either direction.
6. **Quota attribution** for these runs — four headless sessions overlapping a live fleet.

⚠️ **Methodology note (honest disclosure).** My first kill test used `/private/tmp/vlab4` and a **sibling
wave agent chose the same path concurrently**, overwriting my script and interleaving its output into my
log. I detected it via the OVERWRITE-GUARD hook plus two distinct workflow run-ids in one repo, discarded
that run, and re-ran everything in uniquely-named labs (`w1ver-*`). **All numbers in §5.2, §6 and §7 come
from the uncontaminated re-runs.** The contaminated run's leftovers (`vlab4-wf_5eb3693e-8aa-*`) are the
sibling's and I did **not** touch them.

---

## 11. The decision this verification changes

**The rule stands. The finder's replacement premise stands. One sentence must be struck from it.**

1. ✅ **Keep the mandate.** Nothing here weakens it; §6 and §7 strengthen it materially. The honest reason
   is the finder's — *a workflow can write code but cannot land it* — now with a second, sharper leg:
   **both of its two available isolation settings are unsafe for an implementation wave, in opposite ways**
   (§6), and the worktree leak is 100% even on success (§7).

2. 🚨 **Strike the escalation sentence before this is quoted anywhere.** W1 §2.4's *"The child's Bash ran a
   command the parent's own allowlist would have refused"* is refuted (§4). If it survives into a
   `CLAUDE.md` edit it becomes a permanent false security claim about the harness — exactly the class of
   error `MEMORY.md` calls a **negative tool-claim inferred from one uncontrolled call**. Replace with:
   *"a workflow agent runs at `acceptEdits`, so file edits are auto-approved; no privilege escalation
   beyond the parent has been measured, and a hard deny has not been tested."*

3. **Correct "unauditable" to "unaudited".** §8. The trail is complete and per-agent; the parent never
   reads it and no return field names it. If the fan-out-to-branches shape is ever adopted, Phase 0 must
   name the parent as the reader of `journal.jsonl` + `agent-*.meta.json`, not merely as the merger.

4. **`isolation:'worktree'` should not be used from this box until a `WorktreeRemove` counterpart exists.**
   Confirmed and escalated: the leak fires on clean completion by an unchanged agent, so "be careful" is
   not a mitigation. The finder's proposed fix (in `worktree-setup.sh`, not in a doc) is the right one.

5. **Run the deny control before anyone writes the safety half of the rule** (§10.1).

---

### Provenance

| what | source |
|---|---|
| every bundle quote in §3 | re-extracted by byte offset from `~/.claude-220/…/bin/claude.exe` with `python3` + `re.finditer`; positive control `worktree` → 686 hits; identifier resolution anchored and hit-counted |
| §4 (V-A) | live headless run, repo `/private/tmp/vlab2`, log `/private/tmp/vlab2-out/run-a.log`, script `/private/tmp/vlab2-wf/{perm2.js,run-a.sh}` |
| §6 (V-B) | live headless run, repo `/private/tmp/vlab3`, log `/private/tmp/vlab3-out/run-b.log`, script `/private/tmp/vlab3-wf/{collide.js,run-b.sh}`; ground truth from `git log --all` in that repo |
| §5.2 | live headless run, repo `/private/tmp/w1ver-unch`, script `/private/tmp/w1ver-unch-wf/{unchanged.js,run.sh}`, report `/private/tmp/w1ver-unch-out/report.txt` |
| §7 | live headless run, repo `/private/tmp/w1ver-kill`, script `/private/tmp/w1ver-kill-wf/{killprobe.js,run.sh}`, `/private/tmp/w1ver-kill-out/kill.log` |
| §8, §9 | transcript store under `~/.claude-secondary/projects/-private-tmp-{w1lab,vlab3}/`; `~/.claude/hooks/teammate-checkpoint.sh`; both `settings.json` |

**Fleet safety.** Read-only on the live fleet throughout: no live pane, session, worktree or process was
killed, closed or torn down. Everything I killed was a `claude -p` process I started myself, in a
`/private/tmp` repo I created. Cleanup accounting is in §12.

---

## 12. What I spawned, and cleanup accounting

**Spawned (all mine, all in throwaway repos under `/private/tmp`):**

| run | repo | headless parents | workflow agents | outcome |
|---|---|---|---|---|
| V-A permission control | `/private/tmp/vlab2` | 1 | 1 | exited 0 |
| V-B same-file collision | `/private/tmp/vlab3` | 1 | 5 (4 + inspector) | exited 0 |
| V-C(discarded) contaminated | `/private/tmp/vlab4` | 1 | 3 | SIGKILLed by me at T+70 s |
| V-C kill (clean) | `/private/tmp/w1ver-kill` | 1 | 3 | SIGKILLed by me at T+85 s (`PARENT_EXIT=137`) |
| unchanged control | `/private/tmp/w1ver-unch` | 1 | 2 | exited 0 |
| TaskStop abort | `/private/tmp/w1ver-stop` | 1 | 2 | agents `TaskStop`ped by the parent; parent exited 0 |

Every process killed was a `claude -p` I launched, addressed by the PID my own script recorded. **No live
pane, session, teammate, daemon or worktree belonging to the fleet or to any sibling was touched.**

**Worktree pool accounting** (`~/Development/.worktrees`):

```
172  at session start (baseline)
181  peak (my w1ver-kill ×3, w1ver-unch ×2, w1ver-stop ×0, plus sibling activity)
172  after my cleanup  — back to baseline
```

Removed by hand, per worktree: `git worktree remove --force <path>` **then** `git branch -D <branch>` —
two commands, because `worktree remove` does not delete the branch. Both probe repos verified clean
(`git worktree list` → 1 entry; `git branch` → `* main` only), and `ls -d ~/Development/.worktrees/w1ver-*`
→ **no matches**.

**Deliberately NOT touched:** `vlab4-wf_5eb3693e-8aa-{1,2}`, created by a sibling wave agent that collided
with me on `/private/tmp/vlab4`. They were removed by that agent, not by me.

**Left in place as evidence:** `/private/tmp/{vlab2,vlab3,w1ver-kill,w1ver-unch,w1ver-stop}` and their
`-wf`/`-out` sibling directories, plus the finder's `/private/tmp/{w1lab,w2lab}`.

---

## 13. Second independent verifier (B) — corroborations, three corrections, one filled gap

*Appended 2026-08-20 by a **second adversarial verifier** dispatched onto this same axis, unaware of A
until the `backup-before-write` OVERWRITE GUARD caught B about to clobber this file. A's original was
restored from `~/.claude/backups/W1-VERIFY.md__20260820-194717-71801.bak`; nothing above is altered.
**Full report: `W1-VERIFY-2-deny-and-collision.md` in this directory** — named by content because both
verifiers ended up calling themselves "B"; that file's header table disambiguates all three.*

**Corroborated independently** (different repos, different probes, same answers): C4's refutation — B's
parent also succeeded at the same Write and non-`sleep` Bash (`{"parent_bash":"SUCCEEDED",
"parent_write":"SUCCEEDED"}`) · `TaskStop` halts a workflow (`task_type:"local_workflow"`, stages 4-5 never
appeared over 66 s, then `TaskGet` → `Task not found`) · orphans are attributable via
`agent-<id>.meta.json`'s `worktreePath` · the parent's transcript holds **zero** agent `Write`/`Edit` ·
every bundle quote. Two verifiers reaching these separately is the strongest evidence in this folder.

**Gap filled — §10.1's "the one probe that would settle the safety question".** B ran it.
`permissions.deny` **binds a workflow child**: with `{"permissions":{"deny":["Bash(echo:*)","Write"]}}` via
`--settings` and no bypass flag, **4 of 4 denials held** — parent and child both refused, the child's Write
absent from its tool set entirely, and the harness stating *"Write is disabled for this session, **in
subagents as well as here**."* §3.3's inference was right. **An unattended workflow IS constrainable —
this is the operator's real control surface, and it belongs in the rule.** *(Still open, and narrower: a
deny rule under `bypassPermissions`.)*

**Correction 1 — §6's tree held two workflows, not one.** `/private/tmp/vlab3` was B's repo, and B's own
4-agent collision workflow was running in it concurrently: two **overlapping** parent sessions
(`facd162a` 02:33:35→02:36:24, `4a743d2f` 02:34:18→02:36:24), each firing `collide.js` exactly once, **10**
`agent-*.meta.json` for a 5-agent script, two run dirs, and `collide.js` itself overwritten mid-flight.
This explains §6's most dramatic row directly: `implalpha`/`impldelta` are **B's** `user.name`s and
`A`/`D` are **A's** — different agents from different runs, not one agent retrying.

**Correction 2 — the same-file hazard is guarded, and §6's "lost updates" are the guard working.** B's
**uncontaminated** 4-writer re-run (random-token path, 1 session) finished **byte-correct**:
`{"alpha":111,"beta":222,"gamma":333,"delta":444}`, 4/4 commits, no cross-sweep — and **`feat: gamma`
exists** (`0ceb044`), the commit §6 reports as absent from every ref. Three of four agents read the same
stale seed and lost nothing, because the Write tool refuses stale writes:
`<tool_use_error>File has been modified since read… Read it again before attempting to write it.</tool_use_error>`
— **4 firings across 3 of 4 agents**. §6's quoted *"whole-file Write lost the read-modify-write race 3x"*
is that guard refusing stale writes, i.e. optimistic concurrency control doing its job. **The surviving
hazard is the git layer** (`git add -A` staging siblings' files ⇒ a commit subject that lies about its
diff), and it is **stochastic, not deterministic** — at N=4 uncontaminated it did not fire at all.

**Correction 3 — §11.4's `WorktreeRemove` remedy cannot reach the leak.** `WorktreeRemove` is a real event
(4 sites; `hasWorktreeRemoveHook`/`executeWorktreeRemoveHook`) and `removeAgentWorktree` honours it — **but
the workflow path never calls `removeAgentWorktree` when `hookBased` is true** (`if(!yr&&Ot&&…)`), and the
Agent-tool path early-returns identically (`if(vt) return …"Hook-based agent worktree kept at:"`). Only the
session-level `EnterWorktree`/exit cleanup reaches it. Cleanup must be an **external sweeper** keyed on
branch pattern `wf_<runId>-<n>` + each `agent-*.meta.json`'s `worktreePath`. Two sub-corrections to the
finder's §4.5 table: the hook-based create returns **no `gitRoot`**, so with `hookBased:true` **neither**
arm runs — not removal, **not even the unlock** ("nothing at all", not "unlock only") — and the worktrees
are **not** git-locked (`.git/worktrees/*/locked` → `locked=no` on all five); the `remove` refusal is the
ordinary dirty-tree one. **A's operational verdict — don't use `isolation:'worktree'` from this box until
cleanup exists — is CONFIRMED and strengthened.**

**Methodology, binding on the next wave.** Two verifiers on one axis overwrote each other's probe scripts,
cross-polluted one git tree, and nearly destroyed this file. **(a)** Any fan-out that writes scratch must
namespace it with a random token. **(b)** A wave must not dispatch two verifiers onto one axis without
distinct output paths. The contamination biased results toward making the hazard look *worse* — the
direction an adversarial verifier is least likely to question.
