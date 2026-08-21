# W3 — DETERMINISM: what each primitive eliminates, and what it introduces

**Date:** 2026-08-20 · **Box:** MacBookPro18,2 (M1 Max, 10 cores, 64 GiB) · **Binary:** Claude Code 2.1.220
(`~/.claude-220/node_modules/@anthropic-ai/claude-code/bin/claude.exe`, 256,908,272 B)
**Corpus:** 140 deduped Dynamic-Workflow scripts across all 7 account stores · 674 workflow-agent
transcripts from 40 sampled runs · 5,707 land-ledger rows · live git state.
**Labels:** MEASURED · QUOTED (verbatim from the 2.1.220 bundle) · INFERRED.

Builds on and does not re-derive: `orchestration-units-2026-08-19.md`,
`oversight-at-scale-2026-08-19.md`, `breaking-the-ceiling-2026-08-19.md`.

---

## 1. VERDICT

**Scripted control flow eliminates exactly ONE of our four recorded delegation failures — the
roster written and never spawned — and it eliminates that one by construction. It does not touch
the other three. It introduces one class we have never had: a resume that serves a REPORT about a
tree that no longer exists, because the cache key is `(prompt, opts)` with no tree term and no time
term (MEASURED: one key, `v2:5df86b8aafe0ac8eb31`, identical across three separate executions on
three different days).**

Three facts carry it:

1. **We have never reached for the constructs that would recover author-time rigidity.** Across 140
   scripts: **0 use `while`**, **0 use `budget.remaining()`**, **0 derive fan-out width from a prior
   agent's result**, **1 spawns an agent conditionally**. The shape is a literal in 139/140. That is
   *more* rigid than a lead, not less — a lead who reads the code for 30 minutes can change the plan;
   a script cannot, and 139/140 of ours were never written to.
2. **`parallel()` converts a dropped member from visible to invisible.** QUOTED: *"A thunk that
   throws (or whose agent errors) resolves to `null` in the result array — the call itself never
   rejects."* A dead teammate is a missing pane; a dead workflow agent is a `null` in an array.
   **11 of the 111 scripts that call `parallel()` never `.filter(Boolean)`** — those proceed with a
   hole and cannot tell.
3. **Against the bottleneck that actually costs us, determinism is worth zero.** MEASURED today:
   **42.6% of 5,707 land attempts exit nonzero**; **1,766 local branches sit ahead of trunk**; and
   **674 sampled workflow agents produced 2 `git commit`s and 4 `git push`es between them.**
   Orchestration ordering is not what our waves fail on.

**Rule implication:** W3 gives no reason to relax "Agent Teams for implementation." It gives one
reason to *add* a workflow — the reviewer/verifier stage that a lead forgets — and one reason to
forbid one: **an implementation workflow must never be resumed after the tree has moved.**

---

## 2. THE TABLE

### 2a. Does a scripted workflow eliminate the failure? (four recorded instances)

| # | Failure, as it actually happened here | Eliminated by a workflow? | Evidence / command |
|---|---|---|---|
| **F1** | **Roster written, never spawned.** Three sampled Phase-0 rosters were declared and no teammate was ever created: `cap-qos/readout/leak`; `TERMINAL_AGNOSTIC_L3_L4` T1–T4; all of `CONCURRENCY_PROGRAM.md` (branch 0 ahead / 58 behind). "Phase 0 says teammates" measured **~60% predictive, not 100%** over 12 sampled multi-phase plans; **11 of 12 kept implementation in the lead session** anyway. | **YES — by construction.** A stage in a script is a line that executes or an exception. There is no "the lead decided not to". | `docs/research/phase-execution-locus-2026-08-07.md` §3 (census of 2,816 deduped transcripts, 2,372 spawns) |
| **F2** | **Fan-out width chosen by vibes.** Our own default is a *prose* number — "N=12 for typical complex research" — with a sensitivity table nobody re-derives per wave. | **NO — relocated, and frozen.** The number moves from run-time judgement to author-time judgement, where it is still a vibe, and is then unrevisable for the run. MEASURED: `parallel()`/`pipeline()` arguments are **131 map-over-a-literal-array, 41 literal array, 10 map-over-a-variable, 48 other**; **0/140** map over a prior agent's result. | `python3 dyn2.py` (brace-matched AST-lite over the stripped corpus; script in §5) |
| **F3** | **A wave silently drops a member.** `GROUND_UP_DISPATCH.md` § INCIDENT 2026-07-29T19:04Z: lead died mid-wave with 5 assignees still working; `gu5-decide` held ~518 uncommitted insertions; resume restored the session but **not** the team channel (`No agent named 'gu5-decide' is reachable`). | **NO — the shape changes, the class survives.** The workflow's `journal.jsonl` does record `{started}`/`{result}` per agent, which is better instrumentation than we have for teammates. But `parallel()` *never rejects*: a failed member is `null`. **11/111 scripts that use `parallel()` have no `.filter(Boolean)`** and would run their synthesis stage over a hole. | QUOTED bundle §2b row 4; `grep -L 'filter(Boolean)'` over the 111 `parallel()` users |
| **F4** | **Inconsistent briefs.** The whole 5-rule brief discipline (≤150 lines, pre-greped line ranges, verbatim stop-on-issue clause) exists because hand-written briefs drift between members of one wave. | **YES — partially, and it is the cleanest win.** A shared preamble is one template literal interpolated N times. MEASURED: **80/140 (57%)** of our scripts already do exactly this — a `const PRE = \`…\`` interpolated into ≥2 prompts. The remaining 43% write each prompt free-hand and inherit the same drift. | `python3` shared-preamble scan, §5 |

### 2b. What the script introduces

| Property | Value | Command / quote |
|---|---|---|
| **Determinism is ENFORCED, not advised** | `Date.now()`, `Math.random()`, `new Date()` are rejected **at launch** by an acorn walk over the script AST (`WRo`), *and* shimmed at runtime (`ShimDate` throws; `Object.freeze(RealDate)`; `globalThis.Date = ShimDate`). Launch refusal is `errorCode:4`, layer `"nondeterminism"`. | QUOTED: *"Workflow scripts must be deterministic: Date.now()/Math.random()/new Date() are unavailable (breaks resume). Stamp results after the workflow returns, or pass timestamps via args."* |
| **…and that bites implementation specifically** | Our fire machinery names worktrees by timestamp (`wt-cc-223740-82148`). A workflow script **cannot compute one.** It must take it in `args`, or have an agent mint it via Bash — in which case the name lives inside a **cached result** (see below). | INFERRED from the enforcement above + `scripts/handoff-fire.sh` naming |
| **Resume cache key** | **`(prompt, opts)` — no tree, no time, no sha, no mtime.** Key format `v2:<sha256>`. | QUOTED: *"agents whose (prompt, opts) are unchanged replay from cache."* MEASURED: in `wf_e16552fc-ae6/journal.jsonl`, key `v2:5df86b8aafe0ac8eb31` appears under **3 distinct agentIds** across 3 executions — if any time or tree term were in the preimage the keys would differ. |
| **What is cached** | The **return value only**. `journal.jsonl` schema is exactly `{type:'started'\|'result', agentId, key, result}` — no file list, no diff, no side-effect record. | `python3 -c "…collections.Counter(o['type'])…"` over `journal.jsonl`: `started 51 ['agentId','key','type']` / `result 51 ['agentId','key','result','type']` |
| **Resume is real and used** | **20 genuine `Workflow({resumeFromRunId})` tool_use invocations** across 10 sessions and 4 account stores (not tool_result suggestion text — parsed as JSON tool_use inputs). Largest: `wf_0f8a38e6-82f` resumed 6×. | JSON walk over `~/.claude*/projects/**/*.jsonl` for `tool_use.name=='Workflow'` with `resumeFromRunId` in `input` |
| **The cache can be empty and still "hit"** | QUOTED: *"cached results may themselves be empty — inspect journal.jsonl before assuming there is something to recover."* The harness ships this warning in its own tool result. | bundle @19803098 |
| **Per-agent surgical control DOES exist** | `skipWorkflowAgent` / `retryWorkflowAgent` / `pauseWorkflowTask` / `killWorkflowTask`, bound to `x` / `r` / `p` in the `/workflows` TUI. So a running workflow is *not* unsteerable — it is unsteerable **from anything we own** (no pane, no `shutdown_request`, no registry row). | `tt(BSd,{…skipWorkflowAgent:()=>Wfr,retryWorkflowAgent:()=>Gfr,pauseWorkflowTask:()=>Rft,killWorkflowTask:()=>oEe…})`; keymap at @27789170 |
| **A budget/loop API exists — and is unused here** | QUOTED: `budget: {total, spent(), remaining()}` … *"Use for dynamic loops: `while (budget.total && budget.remaining() > 50_000) { … }`"*. Anthropic anticipated it enough to ship a dedicated error: *"Workflow agent() call cap reached (1000). This usually means a loop using budget.remaining() never terminates…"* | MEASURED: **0/140** scripts reference `budget` outside a prompt string (74 raw `budget` hits, all prose). **0/140** contain a `while (` statement outside a string. |

### 2c. Static vs dynamic — the corpus, measured

| Measure | Result | Command |
|---|---|---|
| Scripts analysed (deduped by basename across 7 stores) | **140** (143 paths) | `find ~/.claude* -path '*workflows/scripts*' -name '*.js'` |
| Mean length / total `agent()` call sites | 237 lines · **443** | `node strip.js uniq-paths.txt` |
| `while (` outside strings | **0 / 140** | tokenizer strips `''`/`""`/`` ` ` ``/comments, keeps `${…}` |
| `for (` outside strings | **20 sites in 13 files** | ″ |
| `agent()` inside an `if` block (conditional spawn) | **1 / 140** (`apple-music-ios26-kb`) | brace-matched enclosing-block walk |
| `agent()` inside a `.map` over a **result** var (runtime fan-out width) | **0 / 140** | ″ |
| Later prompt interpolates an earlier agent's result (content-dynamic) | **31 / 140 (22%)** | `${…}` expressions matched against vars bound to `await agent/parallel/pipeline` |
| ≥2 sequential `await parallel/pipeline` stages | **56 / 140** | ″ |
| Exactly 1 stage (single blind fan-out) | **66 / 140** | ″ |
| Workflow concurrency actually observed | never >8 (`min(16,max(2,ncpu−2))`) | established in `orchestration-units-2026-08-19.md` §1.3 |

**Read:** the corpus is *content*-dynamic in 22% of cases and *shape*-dynamic in ~1%. Every script
here is a fixed-width fan-out whose members sometimes read each other's answers.

### 2d. Do workflow agents implement? (CAN vs DOES)

| Measure | Result | Command |
|---|---|---|
| Workflow agents sampled | **674** across 40 run dirs | walk `subagents/workflows/wf_*/agent-*.jsonl` |
| Used `Write`/`Edit`/`MultiEdit` | **173 (25.7%)** | tool_use census |
| Tool mix | Bash 13,889 · Read 1,077 · WebSearch 1,046 · StructuredOutput 543 · WebFetch 359 · Write 300 · Edit 94 | ″ |
| Bash containing `git commit` | **2** | substring scan of Bash `command` inputs |
| Bash containing `git push` | **4** | ″ |

**Read:** workflow agents already write files — overwhelmingly the delivery-contract artifact, not
source. They essentially never commit and never land. "A workflow agent has the Write tool" is
true; "a workflow has carried an implementation wave here" is **not evidenced once** in 674 agents.

---

## 3. THE TRAP, STATED PRECISELY

The axis asks whether `resumeFromRunId` is a superpower (fix stage 3, replay 1–2 free) or a trap.
**It is a superpower for research and a trap for implementation, and the discriminator is not
subtle — it is which half of an agent's output you needed.**

- A **research** agent's output IS its return value. Replaying it returns exactly the thing you
  wanted. The world may have moved, but a 2-hour-old web finding is usually still the finding.
- An **implementation** agent's output is a **mutation of a tree**; its return value is a *report
  about* that mutation. The cache stores the report. **Replay does not re-apply the edits.**

So the failure is not "stale data" — it is **a script that proceeds believing work exists which does
not exist**, and every downstream stage's prompt is built from a description of a tree state that is
gone. Three concrete triggers, all routine in this repo:

1. **The branch moved.** Stage 3 failed, you `git reset`/re-cut the worktree, then resume. Stages
   1–2 "replay free" — their commits are gone, their reports are served as current.
2. **A sibling landed.** 42.6% land failure rate and 1,766 branches ahead of trunk mean the tree
   under a resumed workflow is very likely not the tree its cached stages described.
3. **The worktree name is inside the cache.** Because the script may not call `Date.now()`, a
   timestamped worktree name must be minted by an *agent*, which puts it in a cached result. Resume
   a day later and stage 4 gets handed a path to a worktree that has been reaped.

**The condition under which resume is safe, stated as a rule:** resume is safe iff every replayed
stage's *side effects* are still present in the tree, or were never load-bearing. For a pure-read
research wave that is automatic. For an implementation wave it is a claim about the tree that
**nothing in the harness checks and nothing in the cache key can express.** Absent a tree term in
the key, the only sound discipline is: *never resume an implementation workflow across a tree
change; re-run it.* Which deletes the superpower exactly where it was supposed to pay.

**Honest counterweight:** the harness is not naive here. It ships the `<diagnostics>` block telling
you to Read `journal.jsonl` before trusting a result, it warns cached results may be empty, and the
`/workflows` TUI lets you `r`etry a single agent — which is the surgical form of "invalidate one
cache entry". A disciplined author who retries every side-effecting stage on resume gets the
research-side benefit without the trap. That discipline is not enforced, is not defaulted, and
appears nowhere in our 140 scripts.

---

## 4. WHAT I COULD NOT MEASURE, AND WHY

| Unmeasured | Why | What would settle it |
|---|---|---|
| **A live resume-after-tree-change probe** — the direct experiment for §3 | The `Workflow` tool is **not available to a research subagent**. `ToolSearch "select:Workflow"` returned *"No matching deferred tools found"*; `Agent` is likewise absent. I could not launch or resume a workflow from this agent. | A lead session: run a 2-stage script where stage 1 writes a sentinel and returns its content, mutate the sentinel, resume. Predicted from §2b: stage 1's cached (stale) content is served and the file is not rewritten. ~4 cheap agents. |
| **The exact sha256 preimage of the `v2:` cache key** | The `"v2:"` literal is merged into minified code the strings dump cannot re-associate with its hashing site. `sha256(prompt)` and `sha256(prompt.strip())` both **failed** to reproduce a real key (`v2:00bf92a8…` for agent `a882d8cfb478902da`), so `opts` is definitely in the preimage — I just cannot enumerate the field order. | This does not weaken the finding: the *absence* of a tree/time term is proven by the cross-execution key collision (§2b), which is independent of the field order. |
| **Whether a `while`/`budget` loop actually behaves as documented** | 0 instances in the corpus to observe, and I cannot run one. The API's existence is QUOTED from the bundle's own tool description; its behaviour is unverified on this box. | One script using `while (budget.remaining() > X)` under a `+Nk` turn directive. |
| **Whether the 11 unguarded `parallel()` scripts ever actually swallowed a `null`** | Would require joining each run's `journal.jsonl` (which records only completed agents' results) against the script's synthesis stage. Doable but the join is per-script and the population is small. | Per-run: `count(started) − count(result) > 0` AND no `filter(Boolean)` ⇒ a proven hole. `wf_34feddfd-95a` is the standing candidate: **39 started, 8 results.** |
| **Teammate-side comparison numbers** (how often a named teammate commits/lands) | Out of axis and owned by W1/W2; I deliberately did not re-derive it. | — |

**One correction to a premise in my own brief.** The brief says a running workflow has "NO abort
path in anything we own" — true, and W2 owns that verdict. But it is *not* true that a running
workflow is unsteerable: `skipWorkflowAgent`/`retryWorkflowAgent`/`pauseWorkflowTask` exist and are
keybound in `/workflows` (`x`/`r`/`p`). The gap is **ours** — no pane, no registry row, no
`cc-teardown` reach — not the product's. That matters for W3 because per-agent retry is precisely
the lever that would make resume safe for implementation.

---

## 5. THE DECISION THIS AXIS CHANGES

**Keep the rule. Add one clause; do not relax the main one.**

1. **Do NOT relax "Agent Teams for implementation" on determinism grounds.** The determinism
   argument is real but it buys F1 and F4 — *the reviewer stage that never got spawned* and *brief
   drift* — neither of which is what our implementation waves die of. It costs F2 (a frozen
   decomposition, and our corpus proves we never write the escape hatch) and converts F3 from a
   visible failure to an invisible one. Net: not a trade worth making for a wave that edits source.

2. **Add the clause that IS earned:** *a wave's verification/adversarial stage is a good workflow*,
   because it is (a) the stage most often skipped by a lead — measured, F1 — (b) read-only, so the
   §3 replay trap cannot fire, and (c) exactly the shape our corpus already writes well (fixed
   width, shared preamble, results interpolated into a synthesis stage). This is a *complement* to
   Agent Teams, not a replacement: teammates write the code in worktrees, a workflow adjudicates it.

3. **Write the prohibition down, because nothing enforces it:**
   > **Never resume an implementation workflow across a tree change.** The cache key is
   > `(prompt, opts)` — no sha, no mtime, no branch. A replayed stage returns its *report*, never its
   > *edits*. If any replayed stage wrote to the tree, `r`etry it in `/workflows` or re-run the whole
   > script. `resumeFromRunId` is safe for read-only waves and unsafe for write waves, and the
   > harness cannot tell them apart.

4. **If a workflow is ever used for anything whose members can fail, `.filter(Boolean)` is
   mandatory** — `parallel()` never rejects. 11 of our 111 `parallel()` scripts are already exposed.
   This is a one-line lint over `~/.claude*/projects/**/workflows/scripts/*.js` and should be one.

**Where the leverage actually is (item 4, answered bluntly).** Our waves do not fail on ordering.
They fail after the ordering is over: **42.6% of 5,707 land attempts exit nonzero** (exit 6 ×870,
42 ×636, 5 ×487, 143 ×272), **p95 land wait 240 s and max 7,386 s**, and **1,766 branches ahead of
trunk right now**. Scripted control flow touches none of it — a workflow's agents cannot even reach
the land path (2 commits / 674 agents), so adopting workflows for implementation would move work
*away* from the only primitive that currently lands anything. If the goal is fewer stranded waves,
the money is in the land pipeline (`docs/research/land-architecture-100p-2026-08-10.md`), not in the
orchestration unit.

---

## 6. REPRODUCTION

```bash
W=/tmp/w3 && mkdir -p $W && cd $W
find ~/.claude* -path '*workflows/scripts*' -name '*.js' 2>/dev/null | sort > all-paths.txt
awk -F/ '{print $NF"\t"$0}' all-paths.txt | sort -u -k1,1 | cut -f2 > uniq-paths.txt   # 143 -> 140

# bundle facts (positive-control every negative)
B=~/.claude-220/node_modules/@anthropic-ai/claude-code/bin/claude.exe
LC_ALL=C strings -a -n 6 $B > bundle.strings          # 412,384 lines
grep -c 'budget\.remaining' bundle.strings            # 6   (API exists)
grep -c 'workflow_phase'   bundle.strings             # 9   (positive control)
python3 - <<'EOF'                                     # the two load-bearing quotes
import re; s=open('bundle.strings',errors='replace').read()
for p in ['agents whose (prompt, opts) are unchanged replay from cache',
          'Workflow scripts must be deterministic']:
    print(p, len(list(re.finditer(re.escape(p), s))))
EOF

# corpus control flow (tokenizer strips strings/templates/comments, keeps ${...})
node strip.js uniq-paths.txt      # while=0  for=20/13f  budget=0  agent()=443
python3 dyn2.py                   # dynFanout=0  condAgent=1  interpFromResult=31

# resume was really invoked (tool_use inputs, not tool_result prose)
grep -rl '"resumeFromRunId"' ~/.claude*/projects --include='*.jsonl' | wc -l   # 10 files, 20 calls

# cache key has no tree/time term: one key, three executions
python3 -c "
import json,collections
D='$HOME/.claude-tertiary/projects/-Users-chrisren-Development--worktrees-wt-cc-030642-69458/21834177-30ac-4ccc-b808-be0aa3585f30/subagents/workflows/wf_e16552fc-ae6'
st=[json.loads(l) for l in open(D+'/journal.jsonl') if '\"started\"' in l]
c=collections.Counter(x['key'] for x in st)
print('started',len(st),'unique keys',len(c),'keys reused',sum(1 for v in c.values() if v>1))"

# the bottleneck
python3 -c "
import json,collections,statistics
w=[];e=[]
for l in open('$HOME/.claude/land.log'):
    try: o=json.loads(l)
    except: continue
    if isinstance(o.get('wait_s'),(int,float)): w.append(o['wait_s'])
    if 'exit' in o: e.append(o['exit'])
w.sort(); print('wait p95=%ss max=%ss'%(w[int(.95*len(w))],w[-1]))
print('nonzero exits %.1f%% of %d'%(100*sum(1 for x in e if x)/len(e),len(e)))"
git for-each-ref --format='%(refname:short)' refs/heads |
  while read -r b; do n=$(git rev-list --count origin/main..$b 2>/dev/null||echo 0);
  [ "${n:-0}" -gt 0 ] && echo x; done | wc -l          # 1766
```

[`strip.js`](strip.js) (JS tokenizer: drops comments and `''`/`""`/`` ` ` `` contents, preserves
`${…}` expressions as `INTERP{…}`) and [`dyn2.py`](dyn2.py) (brace-matched enclosing-block walk +
`parallel()`/`pipeline()` argument-shape classifier) ship beside this file. Both take
`uniq-paths.txt` as their only input and print the §2c table directly.
