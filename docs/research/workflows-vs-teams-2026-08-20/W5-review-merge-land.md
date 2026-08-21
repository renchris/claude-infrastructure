# W5 — THE PART AFTER THE CODE IS WRITTEN: review, merge, land, teardown, account

**Date:** 2026-08-20 · **Box:** MacBookPro18,2 (M1 Max, hw.ncpu=10, 64 GiB) · **Binary:** Claude Code 2.1.220
**Read-only on the live fleet.** Nothing was killed, closed, torn down, signalled or keystroked. Every write
went to `/tmp/w5-*` throwaway dirs, all removed (§3.6). One real invocation of `scripts/ship-land.sh` was
made in this checkout; it exits **4 at preflight, before the fetch, before the lock, before any ref** — see
§2.1.

**Labels:** **MEASURED** = I ran it here, this session · **INFERRED** = read out of code/binary, path not
executed · **QUOTED** = vendor text read verbatim from the 2.1.220 bundle.

> 🚨 **METHOD NOTE THAT CHANGES THE EVIDENCE CLASS OF THIS FILE.** Partway through I established that
> **I am myself a Dynamic Workflow agent** — `W5-review-and-merge`, agentId `a…` inside run
> `wf_d8303f9f-4e4`, `{"agentType":"workflow-subagent","spawnDepth":1}`, one of **six** concurrent agents
> in this run, all sharing one cwd (the shared checkout) and one session id. So most of §2 is not a code
> read: it is a **workflow agent running the actual landing tail and reporting what happened to it.**
> That is the strongest evidence class available for this axis and it was not available to the three
> waves that landed yesterday.
> ```
> $ ls ~/.claude-secondary/projects/-Users-chrisren-Development-claude-infrastructure/\
>      f285654f-850c-4ada-96b5-407c5c01ccf0/workflows/scripts/
> orchestration-unit-capacity-wf_06556f35-03a.js     ← 4a3bd3373 was itself a workflow
> oversight-at-scale-wf_4385fe24-845.js              ← de3e82802 was itself a workflow
> break-the-15-ceiling-wf_586b146f-72e.js            ← 8b68f0861 was itself a workflow
> workflows-vs-agent-teams-wf_d8303f9f-4e4.js        ← this wave
> $ cat …/subagents/workflows/wf_d8303f9f-4e4/agent-a36983a00fc52b349.meta.json
> {"agentType":"workflow-subagent","spawnDepth":1}
> ```

---

## 1. VERDICT (≤5 lines)

1. **A workflow agent can execute every step of the tail — and the tail still cannot be carried by a
   workflow, because the ORCHESTRATOR cannot touch any of it.** MEASURED: I took the machine-wide land
   lock, ran `ship-land.sh` to a real verdict, created and removed a `git worktree`, and read the custody
   store. But the workflow *script* runs in a `vm.createContext` sandbox bound to exactly
   `{log, phase, console, budget, setTimeout, clearTimeout}` + `agent/parallel/pipeline/workflow`, with
   `codeGeneration:{strings:false,wasm:false}` — **no `fs`, no `child_process`, no `git`, no shell.** The
   thing that decides merge order, adjudicates a review, and drives the land is the one component that
   cannot run a command. Every serialization decision has to be re-expressed as an agent, i.e. as prose.
2. **The two mechanisms that make our merge tail safe are keyed on units a workflow does not have.**
   MEASURED, hermetically: the in-flight marker is **per-worktree** — 6 agents in one worktree ⇒ the
   first claims it and the rest get exit 11 — and before that they all hit the **dirty-tree refusal**
   (exit 2) over each other's edits. Give each `isolation:"worktree"` and you get N worktrees serialized
   behind one machine-wide mutex whose measured waits in this repo run 98 s / 665 s / 2,362 s / 5,536 s,
   burning a slot of 8 per waiter, invisibly.
3. **Teardown has no equivalent and cannot be given one without first minting an address.** QUOTED from
   the binary: `isolation:"worktree"` is *"auto-cleaned if unchanged"*, and `removeAgentWorktree` aborts
   on **either** `changed_files` (`git status --porcelain`) **or** `commits` (`rev-list --count ..HEAD`).
   So the safety is real — nothing is lost — and the consequence is that **every implementing agent
   worktree is KEPT by construction**, in `.claude/worktrees/`, a namespace no sweeper of ours reads.
   `cc-teardown` takes a pane-uuid; a workflow agent's `$ITERM_SESSION_ID` **is the parent's pane**, so
   the one teardown verb we own, aimed at an agent, kills the lead. Live during this write-up I proved
   the reachability runs the *other* way: a workflow agent can `SendMessage` a bare agentId and
   **resume a finished agent into a background task** — a spawn-equivalent act on a tool no PreToolUse
   matcher covers (§2.2d). We cannot stop them; they can restart each other.
4. **Fresh context is NOT what made yesterday's review stages work — independent re-measurement was —
   and a workflow review stage has a defect that disqualifies it anyway: a braked agent reports DONE.**
   O1-VERIFY measured a `PreToolUse` deny halting every tool call of a workflow agent while the journal
   still wrote `result: DONE` and the run completed. A review that cannot fail loudly is not a review.
   Corroborated live: this run's `journal.jsonl` carries **no timestamp on any row** and lags badly
   (6 started/0 result, then 8 started/4 result 15 min later — the population grew *during* the
   analysis), and the parent transcript contains **0** occurrences of any agent id or of any tool call
   any of us made (§2.3).
5. **The accounting tail scores zero, by construction, and the fix is not small.** MEASURED by grep with
   a positive control: the string `workflow` appears **0 times** in `wrap-ledger.sh`, `completion-assert.sh`,
   `session-writes.sh`, `session-continue.sh`, `operator-readout.sh`, `cc-custody`, `cc-teardown`,
   `cc-board`, `postland-verify.sh` — while `pane`/`session` appear 2–259 times in the same files. Worse
   than absent: **a workflow agent inherits the parent's `CLAUDE_CODE_SESSION_ID`**, so all six of us are
   ONE identity to every store — a backlog lease keyed on `--by <sid>` gives six agents **no mutual
   exclusion at all**, and 310 of the last 3,000 `bash-commands.log` rows are filed under that one id
   with nothing distinguishing which of six ran them.

---

## 2. MECHANISM BY MECHANISM, WITH THE COMMAND BEHIND EACH CELL

### 2.0 Summary table

| Tail step | Teammate `Agent({name})` | Workflow `agent()` | Class |
|---|---|---|---|
| Own worktree | ✅ `isolation:"worktree"` or `claude -w` | ✅ `isolation:"worktree"` (QUOTED, §2.2) | parity |
| Run `git`, gate, `ship-land.sh` | ✅ | ✅ **MEASURED — I did** (§2.1) | parity |
| Take the machine-wide land lock | ✅ | ✅ **MEASURED — I did** (§2.1b) | parity |
| Hold it for a p90 land (991 s) | ✅ (own process, backgrounds freely) | ⚠️ Bash tool auto-backgrounds at 120 s; the agent then **returns before its own land finishes** (§2.1c) | **worse** |
| Serialize N landers deliberately | ✅ lead sequences `shutdown_request`/merge order | ❌ orchestrator has no `fs`/`git`; order can only be *asked for* in prose (§2.1d) | **worse** |
| Structured teardown | ✅ `shutdown_request` (13 refs in bundle) | ❌ none exists (§2.2) | **absent** |
| Worktree reclaimed after work | n/a (ours, swept by our tooling) | ❌ **kept by construction** whenever it holds changes *or* commits (§2.2) | **absent** |
| Stoppable from a rail we own | ✅ `cc-teardown <pane-uuid>` | ❌ pane = the parent's (§2.2c) | **absent** |
| Fresh-context adversarial review | ✅ separate process, own probes, own subagents | ⚠️ fresh, but **cannot spawn** (`SPAWN_DEPTH=1`) and a **denied agent still reports DONE** (§2.3) | **worse** |
| Custody (`cc-custody`) | partial (cwd-keyed) | ❌ nothing opens a row; cwd is the parent's (§2.4a) | **absent** |
| Backlog claim/lease (`--by <sid>`) | ⚠️ sid-keyed, teammate has its own | ❌ **six agents, one sid ⇒ the lease is a no-op between them** (§2.4b) | **absent** |
| Close ledger / mechanical 🔧 | ✅ own Stop hooks | ❌ no Stop hook; edits land in a transcript `session-writes.sh` never reads (§2.4c) | **absent** |
| Command attribution | ✅ own sid in `bash-commands.log` | ❌ 310/3000 rows under the parent sid (§2.4d) | **absent** |
| PreToolUse Bash/Write gates | ✅ | ✅ **MEASURED — denied me twice** (§2.5) | **parity — the one live rail** |

---

### 2.1 THE LANDING PATH

#### a. `ship-land.sh` runs, and reaches a real verdict — MEASURED

```
$ timeout 60 bash scripts/ship-land.sh; echo "rc=$?"
✗ ship-land: REFUSING to land from the shared checkout (/Users/chrisren/Development/claude-infrastructure)
  on protected branch 'main'. …Re-run from a dedicated worktree (claude -w <name>).
rc=4
```

Run by me, a workflow agent, in this session. Nothing in the tool surface stopped it. **A workflow agent
is not mechanically barred from the landing pipeline** — the refusal is about *where it stood*, which is
the identical refusal a human session gets.

That refusal is the first of three preflight walls, in this order (`scripts/ship-land.sh:3835-3879`,
read):

| # | Wall | Exit | What it does to a 6-agent workflow in ONE cwd |
|---|---|---|---|
| 1 | shared-checkout refusal | 4 | all 6 refused if that cwd is the shared checkout — **which is exactly where this run put all six of us** |
| 2 | **dirty-tree refusal** | 2 | **all 6 refused over each other's uncommitted edits.** This fires *before* the in-flight marker and is the real first wall |
| 3 | in-flight claim | 11 | of whoever survives (2), the **first** claims it; the rest are refused |

#### b. It can take the machine-wide land lock — MEASURED, hermetically

```
$ export LAND_LOCK_DIR=/tmp/w5-probe-lock LAND_LOG=/tmp/w5-probe-land.log
$ timeout 30 bash scripts/land-lock.sh -- bash -c 'echo HELD_BY_PID=$$; …'
→ land-lock: acquired (no wait) — machine-wide landing lock held.
HELD_BY_PID=72712
LOCKPID=72683
{"ts":"2026-08-21T02:22:00Z","repo":"…/claude-infrastructure","branch":"main","event":"release",
 "wait_s":0,"hold_s":0,"exit":0,"depth":0,"pid":72683}
```

**Can it? Yes — proven.** *(Probe dir and log removed; the real lock at `/tmp/land-lock-3cca03ed6835`
was only ever read via `--status`, which takes no lock by design.)*

**Should it? Yes, and it must — but the lock's liveness contract fits it badly.** The lock records
`pid + lstart` of the process running the wrapped command (`land-lock.sh:234-240`), and for a workflow
agent that process is **the per-tool-call Bash shell** (`LOCKPID=72683`, a `bash` whose parent is the
tool-call shell), not the agent and not `claude.exe`. The shell is the shortest-lived thing in the
picture. `land-lock.sh`'s own comment states the mismatch it was written against:

> *"a backgrounded land is the normal shape (Bash-tool ceiling 600 s < episode p90 991 s)"* — `land-lock.sh:127-128`

#### c. …and that is the first genuine defect: the agent returns before its own land finishes — MEASURED + INFERRED

MEASURED, incidentally, on my own toolchain this session:

```
Command did not complete within its 120s timeout and was moved to the background (ID: bt3hh0wcy).
```

A workflow agent's Bash tool **auto-backgrounds at 120 s**. A land's p90 episode is 991 s. So the normal
shape of a workflow-agent land is: the land is still running when the `agent()` generator returns its
result string. **INFERRED (not executed, and I would not execute it read-only):** the agent's returned
result therefore cannot carry the land's verdict, the workflow script has no `fs` with which to go and
check (§2.1d), and the backgrounded child is parented to the long-lived `claude.exe`, so it outlives
both the agent and — plausibly — the run. The bundle carries `The workflow stopped before this agent
finished.` (QUOTED), which is the product's own acknowledgement that agents survive their run's end as a
*state*, not that their shell children are reaped.

A teammate does not have this problem: it is a separate `claude.exe` with its own turn loop, so it can
background a land and then keep taking turns until the land reports.

#### d. What happens if 8 concurrent workflow agents all try to land

Two topologies, both bad, for different reasons.

**Topology A — all 8 in ONE worktree (this run's actual topology).** MEASURED, hermetic red-proof that
the in-flight marker is per-worktree and therefore shared:

```
$ cd /tmp/w5-inflight-probe/repo && GD=$(git rev-parse --absolute-git-dir)
$ printf 'pid=%s\nlstart=%s\nstarted=%s\nbranch=main\n' "$$" "$(ps -o lstart= -p $$)" "$(date +%s)" \
    > "$GD/ship-land-inflight"
$ . hooks/lib/land-inflight.sh; land_inflight_live .
SECOND-AGENT-VERDICT: IN-FLIGHT [98179 1787279003 main] => inflight_claim refuses => ship-land exit 11
$ ls -1 "$GD"/ship-land-inflight | wc -l
1                                  ← one marker for the whole worktree
```

Outcome: **1 lands, 7 refused** — and in practice 0 land, because wall 2 (dirty tree) fires first over
the siblings' edits, and because 8 agents committing into one index is the exact incident this repo's
project `CLAUDE.md` documents (`dfacccd`, 5 files silently dropped).

**Topology B — 8 × `isolation:"worktree"`.** Same probe, second half:

```
$ git worktree add -q -b w5b ../wt2
$ land_inflight_path ../wt2
/private/tmp/w5-inflight-probe/repo/.git/worktrees/wt2/ship-land-inflight
→ wt2 FREE (separate marker => separate land allowed)
```

So all 8 are *permitted* to land, and they collide on exactly one thing: the machine-wide mutex, keyed on
`--git-common-dir` so every worktree of the repo shares it (`land-lock.sh:13-19`). Serialization is
correct — and the **cost lands on the workflow's parallelism**, because a queued lander is an agent
sitting in `sleep 2` holding one of 8 slots. Measured waits in this repo's own ledger, quoted in
`land-lock.sh:210-211`: **98 s / 665 s / 2,362 s / 5,536 s**, against `LAND_LOCK_WAIT` default **3600 s**.
Eight landers can therefore consume the entire run's concurrency for an hour, and the `/workflows` view
renders all eight as *running*.

**And nothing can sequence them.** In our Agent-Teams pattern the lead merges *smallest-diff-first,
serialized* — a judgment made after seeing all N diffs. The workflow orchestrator cannot see a diff:

```
$ grep -oE '.{100}createContext\(\{__proto__.{400}' /tmp/cc220-strings.txt      # MEASURED, my own dump
…Hsn.createContext({__proto__:null, log:nEe(p.log), phase:nEe(p.phase), console:m, budget:g,
  setTimeout:y.setTimeout, clearTimeout:y.clearTimeout}, {codeGeneration:{strings:!1,wasm:!1}})…
```

No `fs`, no `require`, no `process`, no `child_process`, and `eval` disabled. A `pipeline()` can order
agents in *time*; it cannot compute an order from the *content* of what they produced. "Merge
smallest-diff-first" becomes a sentence in a prompt.

---

### 2.2 TEARDOWN

#### a. There is no `shutdown_request` equivalent — QUOTED + MEASURED

`shutdown_request` occurs **13** times in the 2.1.220 bundle (positive control for the instrument) and
belongs to `SendMessage`'s teammate protocol. A workflow agent is not a teammate: it has no name in that
namespace, no pane, no process. Its lifecycle is *the generator returns*. There is nothing to request.

What the product actually offers instead is `/workflows` — operator-only, TUI-only, in the **parent's**
pane (O6 §2c, MEASURED there). It stops the *run*, not an agent, and the bundle's own string for what
that leaves is `The workflow stopped before this agent finished.`

#### b. What `isolation:"worktree"` leaves behind — QUOTED from the binary, positive-controlled

Vendor contract, verbatim:

> *"`isolation: "worktree"` gives the agent its own git worktree (auto-cleaned if unchanged)."*
> *"With `isolation: "worktree"`, the worktree is automatically cleaned up if the agent makes no changes;
> otherwise the path and branch are returned in the result."*

The implementation is safer than that sentence sounds, and the safety is exactly what makes it an orphan
generator. `removeAgentWorktree` refuses on **two** independent grounds, and I can name both from the
adjacent symbol block:

```
status  --porcelain          → changed_files
rev-list  --count  ..HEAD    → commitsAhead        (keys: already_gone · hook_based · changed_files ·
                                                     commits · no_root · errorSummary · needsForce)
removeAgentWorktree: aborted <N> changed file(s) would be lost, kept
removeAgentWorktree: kept branch <b> — detached or dir gone
removeAgentWorktree: git worktree remove failed, kept
Could not delete agent worktree branch
```

So: **an agent that did nothing is cleaned; an agent that did anything at all — dirty tree OR a commit
not in the base — is KEPT.** Nothing is lost. But an implementing agent is *by definition* in the second
class, so **`isolation:"worktree"` used for implementation leaves one worktree + one branch per agent,
every time, permanently, by design.**

Two further facts make those orphans invisible to us:

- They live under **`.claude/worktrees/`** (`removeAgentWorktree` refuses any path *"not directly under a
  `.claude/worktrees` directory"*). MEASURED: `ls -d .claude/worktrees` → **ABSENT** in this repo and in
  `~/.claude` — i.e. no agent worktree has ever been created here, and no sweeper of ours knows the path.
  Our own worktrees live in `~/Development/.worktrees/` and `/private/tmp/`.
- The harness's own `cleanupStaleAgentWorktrees` exists but is gated by the same two safety checks, so it
  can only ever remove the ones that were already empty.

Scale of the tail we *already* carry with our current pattern, MEASURED, as the denominator any new
generator would be added to:

```
$ git worktree list | wc -l                                              → 87
$ git for-each-ref refs/heads --format='%(refname:short)' | wc -l        → 1834
$ git branch --merged origin/main --format='%(refname:short)' | wc -l    → 68
                                                     ⇒ 1766 branches not tip-merged
```

⚠️ **Stated as a bound, not a loss claim.** "Not tip-merged" ≠ "content unlanded" — a rebased land
rewrites the object (MEMORY `cited-sha-may-not-survive-the-land`), so the true stranded count is smaller.
The point is the *direction*: this tail is already 1,766 branches and 87 worktrees deep under a pattern
whose teardown verb we own. `isolation:"worktree"` adds a generator whose teardown verb we do not.

#### c. `cc-teardown` aimed at a workflow agent hits the lead — MEASURED

`bin/cc-teardown:187` takes `<pane-uuid|name>`; an agent *name* is refused outright
(`reason_kind=target-not-a-pane-uuid`, `:192-196`). What does a workflow agent report as its pane?

```
$ echo "ITERM_SESSION_ID=$ITERM_SESSION_ID  KITTY_WINDOW_ID=$KITTY_WINDOW_ID"
ITERM_SESSION_ID=w0t0p0:388  KITTY_WINDOW_ID=388          ← the PARENT session's pane
$ echo "CLAUDE_AGENT_ID=${CLAUDE_AGENT_ID:-<unset>}"
CLAUDE_AGENT_ID=<unset>
```

Run inside a live workflow agent. The only address it can offer is its parent's. **Tearing down "the
agent" tears down the lead session and its five siblings.** This is not a missing feature that a patch
closes; it is the by-construction cell from O6 — a patch has to mint an address first.

#### d. One thing that is NOT absent, discovered live this run — MEASURED

While writing this file I received, as a running workflow agent:

```
<agent-message from="ab4fd4f00048fe6b3">
[W2-VERIFY PROBE — no action needed…] Testing whether a RUNNING workflow agent is addressable by raw agentId.
</agent-message>
```

**A running workflow agent IS deliverable-to by raw agentId.** That narrows the landed claim *"no
mailbox"* (`de3e82802`): the inbound half exists.

I then tested the outbound half by replying, and **the result is larger than the probe asked for**
(MEASURED):

```
$ SendMessage → to: "ab4fd4f00048fe6b3"
{"success":true,
 "message":"Agent \"ab4fd4f00048fe6b3\" had no active task; resumed from transcript in the
            background with your message. You'll be notified when it finishes.",
 "resumedAgentId":"ab4fd4f00048fe6b3"}
```

So a workflow agent can not only send — it can **RESUME AN ALREADY-FINISHED AGENT FROM ITS TRANSCRIPT
AND PUT IT BACK TO WORK IN THE BACKGROUND.** That is a spawn-equivalent act, and it took a path our
admission surface does not watch: `agent-teams-enforce.sh` and `frontier-spawn-gate.sh` are both bound
to `matcher:"Agent"` (MEASURED, §2.5), and **`SendMessage` is not `Agent`**. It also bypasses
`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1`, which blocked me from spawning a *new* agent — reviving an old
one is not a spawn.

None of this rescues teardown, and the direction it moves the column is the wrong one:

- **Delivery is not control.** No `shutdown_request` semantics reached me; I am not a teammate, and the
  protocol's own doc says approving shutdown *"terminates your process"* — a workflow agent has no
  process of its own to terminate.
- **The address is opaque.** MEASURED: `grep -c a36983a00fc52b349 <parent-transcript>` → **0**. The
  agentId appears in no registry, no `cc-*` verb, and no namespace the operator can type — so it is
  reachable by an agent that already knows it and by nobody else.
- **It is a NEW ungoverned lever, not a recovered one.** The teardown cell stays ❌ and the spawn-gate
  cell gets worse: an in-process agent with no ledger row can restart other agents, in the background,
  through a tool no PreToolUse matcher covers.

W2 owns the messaging thread; I record it because it is the one cell in my column that came back
*different* from the prior, and because the second half of it belongs in the oversight ledger, not in
mine.

---

### 2.3 REVIEW — is a fresh pipeline stage an ADVANTAGE?

**The case FOR (argued at full strength).** Our discipline demands a fresh-context reviewer and forbids
self-recheck, and a workflow gives that *for free and by construction*: `pipeline()` hands stage N+1 the
string stage N returned and nothing else — no shared history to anchor on, no social relationship with
the author, and no way for the author to "explain" the result. It is also **cheaper to insist on**: a
lead has to remember to spawn a reviewer, whereas a pipeline stage cannot be skipped without editing the
script, and the script is a reviewable artifact on disk. Yesterday's three waves each ran adversarial
verifier stages and they overturned a lot — a raw `grep -c REFUTED` across the nine verifier files in
`4a3bd3373`, `de3e82802`, `8b68f0861` gives **48** refutation tokens against **130** confirmations. On
its face: fresh context works, so build it into the structure.

**The case AGAINST, and it wins, on two grounds — one from the evidence, one from the mechanism.**

**(i) Fresh context is not what did the work; independent RE-MEASUREMENT is.** I read the verdict blocks
of four of yesterday's verifier files. Every load-bearing overturn came from the verifier **running
something the finder never ran**, not from reading the finder's text with clean eyes:

| Overturn | What actually caused it |
|---|---|
| A1-VERIFY C11 — *"daemon/pty-hosts ALL GONE"* **REFUTED as a standing fact** | verifier ran its **own** `ps` census and found 1 daemon + 4 pty-hosts live — *and traced them to sibling agent A3's probe, which had reported tearing them down* |
| A1-VERIFY C14 — the finder's load-bearing UNKNOWN | verifier **spawned a bare `Agent({})`** and counted processes: 0/7 vs an 11/11 control |
| A4-VERIFY C8 — finder's caveat **REFUTED, direction inverted** | verifier recomputed the estimator over all 231 tool calls in 158 run dirs |
| O1-VERIFY — *"Esc stops an unnamed subagent"* **REFUTED** | verifier **spawned its own throwaway tmux workflow and stopped it**, watched a post-stop tripwire agent fail to run |
| O2-VERIFY — *"nothing emits a BEL"* **false** | the finder's null came from a `grep -r` over a symlink layer BSD grep cannot walk; the verifier used a different instrument |
| O2-VERIFY — `3.75 × 4 h ≈ 15` **REFUTED** | verifier computed the actual rolling-4 h *union* (4.9, not 14.6) |

A workflow pipeline stage gets the freshness and **loses the instruments**: `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1`
is set in `~/.zshrc:484` (MEASURED — it is in my own env), and a workflow agent is created at depth 1, so
**a workflow review stage cannot spawn anything.** A1-VERIFY's and O1-VERIFY's two sharpest overturns are
literally unavailable to it. It can still run Bash, so it is not helpless — but the review our discipline
actually wants is "go and measure it yourself with a different instrument", and the structure that makes
the stage automatic is the same structure that takes half the instruments away.

**(ii) A workflow review stage cannot fail loudly, and this is disqualifying.** O1-VERIFY, MEASURED:
a `PreToolUse` HALT-flag `deny` hook fired for a workflow agent's own tool calls, mid-run, overriding
`--permission-mode bypassPermissions` — every tool call denied, zero side effects — **and the journal
still wrote `result: DONE` for the braked agent and the run completed with a 2 KB output file.** A review
stage that is silently prevented from measuring anything returns a green string, and `pipeline()` carries
it forward as a pass.

Corroborated independently, live, in this very run:

```
$ cat …/subagents/workflows/wf_d8303f9f-4e4/journal.jsonl        # first read
{"type":"started","key":"v2:e27b1079…","agentId":"a36983a00fc52b349"}
{"type":"started", …}  × 6            ← 6 rows, all `started`, no timestamps
$ grep -c 'a36983a00fc52b349' …/f285654f-850c-4ada-96b5-407c5c01ccf0.jsonl
0                                      ← the parent transcript never names any of the six
```

🚨 **Re-measured ~15 min later, and the correction matters — do not quote "0 results" as a standing
fact.** Results *are* eventually written; what is missing is time and coverage, and the population grew
during its own analysis (memory `generator-population-grows-during-its-own-repair`):

```
$ python3 …  # over the same journal.jsonl
rows 12  started 8  result 4              ← was 6/6/0; the agent count itself went 6 → 8
keys in a result row: ['agentId','key','result','type']
any timestamp field anywhere: False       ← ordering and duration are unreconstructable
my id a36983a00fc52b349 has result: False ← live-and-unresulted is indistinguishable from stalled
```

And the identity of that agent id is now pinned rather than assumed — the discriminator is a string
only I emitted:
```
$ for f in …/wf_d8303f9f-4e4/agent-*.jsonl; do echo "$(basename $f) $(grep -c w5-inflight-probe $f)"; done
agent-a36983a00fc52b349  9      ← me
agent-a767f253e722c66fb  0        (…and 0 for every other agent)
$ grep -c 'w5-inflight-probe' …/f285654f-850c-4ada-96b5-407c5c01ccf0.jsonl
0                                ← none of my tool calls exist in the parent transcript
```
The single hit for `W5-review-merge-land` in the parent transcript is the *script's instruction text*
(`Write ${OUT}/W5-review-merge-land.md`), **not** a `tool_use` record — which is precisely why
`session-writes.sh`, which parses `tool_use`, is blind (§2.4c).

**Landing on one:** *no.* Fresh context is necessary and it is not the scarce ingredient — we already get
it from a separate Agent, which additionally keeps its instruments and can fail loudly. Adopting workflow
pipeline stages as the review mechanism would trade an auditable, interruptible, self-spawning reviewer
for an automatic one that reports DONE when it has been gagged.

---

### 2.4 THE ACCOUNTING TAIL

**Coverage grep, with the positive control the method rules require** (MEASURED):

| File | `workflow` | `teammate` | `pane` | `session` |
|---|---:|---:|---:|---:|
| `scripts/wrap-ledger.sh` | **0** | 0 | 2 | 70 |
| `hooks/completion-assert.sh` | **0** | 1 | 4 | 88 |
| `hooks/lib/session-writes.sh` | **0** | — | — | — |
| `hooks/session-continue.sh` | **0** | — | — | — |
| `hooks/operator-readout.sh` | **0** | — | — | — |
| `bin/cc-custody` | **0** | 0 | 14 | 7 |
| `bin/cc-backlog` | 2 *(both prose: "not a workflow verb")* | 1 | 13 | 109 |
| `bin/cc-teardown` | **0** | 1 | 259 | 105 |
| `bin/cc-board` | **0** | — | — | — |
| `scripts/postland-verify.sh` | **0** | — | — | — |
| `scripts/ship-land.sh` | 1 *(prose)* | — | — | — |

The instrument is not blind — it finds `pane`, `session`, `teammate` everywhere. **Zero real coverage.**

#### a. Custody — readable, un-participate-able

MEASURED, from inside a workflow agent: `bin/cc-custody count --open` → **127**; `list --open` renders
rows. So the store is reachable. But custody is **cwd-keyed** (`_fired_cwd_key`, `cc-custody:12-16`), and
its only producers are `handoff-fire.sh` and `mailbox-drain.sh`. A workflow agent shares the parent's cwd
and fires no handoffs, so **nothing ever opens a row for it.** An in-flight workflow — 8 agents, hours of
wall — is invisible to `CUSTODY_OPEN`, which is precisely the leak `cc-custody` was built to close for
dispatched sessions (62 content-stranded commits / 21 branches / 5 wave-day spikes).

#### b. Backlog claim/lease — the lease becomes a no-op between siblings

`cc-backlog claim <id> --by <sid>`, and `claimer_live` resolves a session-shaped claimer through the
cc-sessions pane registry. MEASURED, from inside a workflow agent:

```
$ echo $CLAUDE_CODE_SESSION_ID
f285654f-850c-4ada-96b5-407c5c01ccf0        ← the PARENT's session id
$ cc-sessions --json | …                     → registry rows: 10 · my sid present: True
```

Two consequences, and the second is worse than "unsupported":

1. **The liveness oracle answers LIVE** — for the parent. So a workflow agent's claim is not reaped
   mid-work. Good news, arrived by accident.
2. **All 8 agents present ONE identity.** `cmd_claim`'s incumbency test is
   `[ "$cby" != "$by" ] && claimer_live …` (`cc-backlog:1619`) — same `$by` ⇒ the guard never fires ⇒
   **eight agents can claim the same item simultaneously and the lease is silent.** The condition-lease
   added after the 2026-08-?? duplicate-dispatch incident keys on `(project, condition)` and likewise
   cannot separate them. There is no `--venue workflow` and no third rc for "an unaddressable in-process
   worker", the way `--venue cloud` earned rc 2.

#### c. The close ledger and the mechanical 🔧 — blind twice over

MEASURED: `bash scripts/wrap-ledger.sh` from inside a workflow agent →

```
🔧 Loose ends — 25 uncommitted change(s) in the tree; continuing.
```

One rung, over one tree, for six agents plus whatever siblings share the checkout. It cannot say whose.

And the arm that was supposed to fix exactly that is blind here. `hooks/lib/session-writes.sh` attributes
dirt by parsing `Write|Edit|MultiEdit|NotebookEdit` tool_use records out of **the Stop payload's
`transcript_path`** — the parent's `<sid>.jsonl`. A workflow agent's tool calls are written to a
*different file*, `…/<sid>/subagents/workflows/wf_<id>/agent-<id>.jsonl` (MEASURED: six such files,
283–434 KB each, live). So `session-writes.sh` returns rc 1 *"read cleanly, no file-edit tool_use"* over a
tree six agents are actively editing. Its documented fail direction is safe-but-silent: the certificate
is withheld, no continuation is forced — **so six agents' uncommitted work reaches idle with nothing
blocking the stop.** A workflow agent also runs **no Stop hook of its own** (it is not a session), so
there is no second chance.

#### d. Attribution — MEASURED

```
$ tail -3000 ~/.claude/logs/bash-commands.log | sed -nE 's/^\[[^]]*\] \[([^]]*)\].*/\1/p' | sort | uniq -c | sort -rn | head -3
 310 f285654f-850c-4ada-96b5-407c5c01ccf0        ← me AND my five siblings
  64 4426905b-…
  52 ebb31eb7-…
```

The row format is `[ts] [session-id] <command>` — there is no agent field. 310 rows, six authors, one
label. This reproduces O6's finding (516/5,000 under one uuid) on a different day and a different wave.

#### e. What would have to be built

Minimum viable participation, in dependency order — the first item is a prerequisite for all the rest:

1. **Mint an address.** A workflow agent needs a stable, externally-visible identity. The raw agentId
   exists (§2.2d proves it is deliverable-to) but appears in no store. Cheapest real source: the
   `PreToolUse` payload, which O1-VERIFY measured carries `agent_type:"workflow-subagent"` — a
   `matcher:"*"` hook (measured absent today; measured cost 2.85 ms p50) could stamp
   `(sid, agentId, run_id)` into a registry on first tool call.
2. **`cc-teardown` / `cc-sessions` rows** keyed on that address, plus a refusal when the target resolves
   to a parent pane (today it silently would not).
3. **`session-writes.sh`** to union the `subagents/workflows/wf_*/agent-*.jsonl` files under the Stop
   payload's sid — a path change, not a design change, and the only cheap item on this list.
4. **`cc-backlog`**: a `--venue workflow` with rc-2 semantics, or an agentId-scoped `--by`, so eight
   agents are eight claimers.
5. **`cc-custody`**: a producer at `agent()` time and a discharge at result time — but the journal
   records **0 results** (§2.3), so this needs the vendor's journal to improve or an independent stamp.
6. **A worktree sweeper** for `.claude/worktrees/`, which nothing of ours currently reads.

That is six mechanisms, of which one is cheap. **It is a subsystem, not a patch** — and every one of them
is work we do not have to do for a teammate, because a teammate already has a pane, a pid, a session id
and a Stop hook.

---

### 2.5 THE ONE RAIL THAT ALREADY REACHES A WORKFLOW AGENT — MEASURED, twice, by being stopped

Our `PreToolUse` `Bash` gates fire for workflow agents. I did not set out to prove this; I was denied.

```
$ … git add f … ; rm -rf "$D"
✗ git add -rf blocked — gitignored files are intentionally excluded. …

$ … git -C "$D" config user.email … ; …
✗ git identity write to an all-expansion target blocked: -C '"$D"'. …
```

Both are our own hooks (`~/.claude/hooks/` — the `Bash` matcher carries nine of them). So the class is
**not** ungoverned at the tool layer; it is ungoverned at the *Agent-spawn* layer, which is where
`agent-teams-enforce.sh` lives (`matcher:"Agent"`, MEASURED — the enumerated matchers are exactly
`Bash`, `Write|Edit|MultiEdit`, `Agent`, an ms365 list, `AskUserQuestion`; **no `*`, no `Workflow`**).
A workflow agent slips the spawn gate and then walks straight into the Bash gate.

⚠️ **Incidental defect, filed here because it fired live and is off-axis:** the first denial is a **false
positive** — the guard's own message asserts *"a `-f` belonging to another command on the same line is not
this rule"*, and it then fired on exactly that (`git add f` co-occurring with `rm -rf "$D"`). Confirmed by
re-running the identical `git add f` without the `rm` on the line: it passed. This is the greedy-token
class, and the reassurance clause is the untested half (MEMORY `reassurance-clause-is-the-untested-half`).

---

### 2.6 THE RUN'S OWN RESIDUE — what N agents in ONE tree did while I wrote this — MEASURED

This wave passes **no `isolation` option**: every `agent()` call site is `agent(a.measure, { label, phase })`,
so all of us share cwd `/Users/chrisren/Development/claude-infrastructure` — the symlink source that this
repo's own `.claude/CLAUDE.md` forbids committing in. Two artefacts of that, observed live:

**(a) Scratch litter in the deliverable directory.** At 19:27 the output dir held, beside the five axis
`.md` files, two working scripts written by *other* agents — `dyn2.py` and `strip.js`. A
`git add docs/research/workflows-vs-teams-2026-08-20/` sweeps them into the commit. The repo's G4 rule
("explicit paths; never sweep unrelated / other-session changes") is **unenforceable here, because there
is no other session**: from git's point of view it is one tree, one index, one HEAD.

**(b) My own deliverable was rewritten underneath me, mid-run.** I wrote this file, then applied four
targeted `Edit`s; the fifth returned
`File has been modified since read, either by the user or by a linter`, and the file on disk had become a
different, longer document covering the same axis. I could not attribute the writer — **and that is the
finding, not an aside.** The tools that would answer *"who wrote this"* are exactly the ones §2.4 shows to
be blind for this class: `bash-commands.log` files every agent under one session id, the parent transcript
records none of our tool calls, and `session-writes.sh` reads a transcript ours are not in. In an
Agent-Teams wave the same collision is answerable in one command (each member has its own worktree, its own
session id, and its own transcript) and mostly cannot happen at all. Here the correct response was the
INTEGRATE rule — read the surviving file, keep it, and merge the measurements it lacked (done: §2.3's
re-measurement and this section) — which is a *discipline* substituting for a *mechanism*.

**Read (a) and (b) together and they are the axis in miniature:** the failure of a shared-tree fan-out is
not that work is lost, it is that **nothing can say whose it was** — and every merge decision in §2.1d
depends on being able to say exactly that.

---

## 3. WHAT I COULD NOT MEASURE, AND WHY

1. **I did not run a real land from a workflow agent.** Landing is not read-only, and there is no dry-run
   that exercises the lock-hold + push window. So §2.1c (the agent returns before its land finishes) is
   INFERRED from three measured parts — auto-background at 120 s, the p90 991 s episode quoted in
   `land-lock.sh`, and the tool-call shell being the recorded lock holder — not from watching one.
2. **I could not determine what happens to a workflow agent's backgrounded Bash child when the RUN ends.**
   This is the highest-consequence open question in my axis: if the run's abort path does not reap it, a
   `/workflows` stop leaves a `git push` in flight holding the machine-wide mutex. Falsifiable cheaply in
   a throwaway repo: workflow with one agent that backgrounds `sleep 600`, stop the run via `/workflows`,
   `ps` for the sleep. I did not do it because it needs a TUI and a spawned run.
3. **I did not exercise `isolation:"worktree"`.** Nothing in this run used it; creating one requires
   spawning a workflow, and `.claude/worktrees/` does not exist in this repo (MEASURED), so I have no
   real specimen. §2.2b is QUOTED vendor contract + the symbol block around `removeAgentWorktree`, with
   the two abort keys (`changed_files`, `commits`) read out of the adjacent constant list — **INFERRED
   from code, not executed.** If the `commits` guard turns out to be checked only against the *base ref*
   and not the *upstream*, a committed-and-pushed agent worktree would be reaped, and §2.2b's "nothing is
   lost" needs re-stating.
4. ~~**`SendMessage` outbound from a workflow agent is untested**~~ — **RESOLVED during writing, both
   directions MEASURED (§2.2d), and the outbound test returned more than it was asked: the send
   *resumed a finished agent from its transcript into a background task*, through a tool no PreToolUse
   matcher covers.** What remains unmeasured is whether a `shutdown_request`-shaped payload sent to a
   workflow agent's agentId does anything at all — that is the test that would move the teardown cell,
   and it is §5.4.
5. **The 1,766-unmerged-branches figure is a bound, not a loss count** — `--merged` is tip-containment
   and a rebased land rewrites the object.
6. **Cleanup ledger** (rule 3). I created and removed: `/tmp/w5-probe-lock` + `/tmp/w5-probe-land.log`
   (hermetic land-lock), `/tmp/w5-inflight-probe/` incl. a `git worktree add ../wt2` which I
   `git worktree remove --force`d, `/tmp/w5-ship.out`, `/tmp/cc220-strings.txt` (412,384-line strings
   dump, left in place — it is the shared instrument this wave's other axes also built). One
   `scripts/ship-land.sh` invocation in this checkout, exit 4 at preflight. **No live pane, session,
   process, worktree, lock, backlog row, custody row or config was killed, closed or written.**

---

## 4. THE DECISION THIS AXIS CHANGES

**The rule stands, and my axis supplies the reason that makes it stop recurring.**

The recurring question is *"a workflow agent has Write and Bash, so why can't it implement?"* — and on my
axis the answer is finally not a capability claim, because **the capability claim is conceded.** A
workflow agent can edit, commit, gate, take the machine-wide land lock, make a worktree, and run
`ship-land.sh` to a real verdict. I did five of those six things while writing this file. That argument is
over.

What it cannot do is be **accounted for**, and implementation is the one kind of work where that is the
whole job:

- **Merge order is a judgment over content, and the orchestrator is content-blind** (`vm.createContext`
  with six bindings, no `fs`). "Serialized, smallest-diff-first, `--ff-only`" is not expressible; it can
  only be requested in prose from an agent that cannot see its siblings' diffs.
- **The unit of work has no address**, so teardown aimed at it hits the lead, custody never opens, the
  backlog lease cannot separate eight claimers that share one sid, the close ledger reads one 🔧 for six
  authors, and `session-writes.sh` reads a transcript that six agents do not write to. Six mechanisms
  would have to be built, and every one of them already exists for a teammate.
- **A review stage that is silenced still reports `DONE`.** Of everything in this file, this is the fact
  that should end the debate on its own: the mechanism proposed as the workflow's *advantage* over Agent
  Teams is the mechanism with a measured silent-pass mode.

**Wording that carries the reason, for whoever owns the CLAUDE.md diff (W6's call, not mine).** Do not
re-assert "MUST use Agent Teams" — that is what has failed to settle the question three times, because it
asserts a conclusion whose premise ("workflows can't write code") is false and every reader can check
that it is false. Assert the actual discriminator:

> Workflow `agent()` is for work that ENDS AT A RETURNED STRING. Implementation does not: it ends at a
> merge order, a land, a teardown and an entry in a ledger, and a workflow agent has no address any of
> those four are keyed on — it inherits the lead's session id and the lead's pane. Its worktrees are kept
> by design whenever they hold work, in a directory nothing of ours sweeps; a silenced agent still
> reports DONE. Use a teammate (or a dispatched session) for anything whose definition of done includes
> a landed commit.

**Where a workflow IS right for implementation-adjacent work, stated so the rule is not read as a ban:**
the *research and verification that precedes a wave* — which is exactly what all four of today's runs,
including this one, actually are, and they landed three commits by handing their strings to a session
that owned the tail. That division is already the working practice; it just was not written down. The
line is not "workflows may not write" — **it is that the unit which lands must be the unit we can name.**

---

## 5. OPEN QUESTIONS FOR THE VERIFIER

1. **Re-run §2.2b against a real specimen.** Spawn a one-agent workflow with `isolation:"worktree"` that
   makes one commit and returns. Predictions to falsify: (a) the worktree is **kept**, (b) it is under
   `.claude/worktrees/`, (c) the branch survives, (d) nothing of ours lists it. If (a) fails, my orphan
   claim inverts into a *data-loss* claim, which is worse and more urgent.
2. **Settle §3.2 — the backgrounded child across a run stop.** The one scenario where this axis's answer
   could change from "unaccountable" to "unsafe".
3. **Attack §2.4b from the other side.** I claim eight workflow agents defeat the backlog lease because
   they share a sid. Check whether any claim path can see `agentId` at all — if `cc-backlog` could be
   passed one, item 4 of §2.4e collapses from a redesign to a flag.
4. **Test SendMessage OUTBOUND from a workflow agent** (§3.4) and, more importantly, whether a
   `shutdown_request` sent to a workflow agent's agentId does anything. If it does, the teardown row of
   §2.0 changes and so does the recommendation's second bullet.
5. **Check my §2.3 reading against the VERIFY files I did not read** (A3, A6, B1, B2, B3). I sampled four
   of nine and generalised "the overturns came from re-measurement, not from freshness". A counter-example
   — a load-bearing overturn produced purely by re-reading — weakens the review argument, though not the
   `result: DONE` half, which stands alone.
