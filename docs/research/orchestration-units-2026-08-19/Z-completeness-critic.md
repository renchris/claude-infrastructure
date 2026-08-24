# Z — completeness critic: what is MISSING or UNSAFE to act on

Read: `orchestration-units-2026-08-19.md` + all 12 axis files. Ranked by how much a decision changes
if the gap is real. Labels: **MEASURED HERE** = I ran it this pass · **UNMEASURED** = nobody ran it.
Probes are read-only unless marked.

---

## G1 — The headline's evidence is n=18 and does NOT survive the extension its own verifier prescribed

§1 fact 2 and §9 row 2 rest on *"named 11/11 with a coincident pane split, unnamed 0/7 — perfect
discrimination."* A1-VERIFY's own Q1 said to re-run it over the full pane ledger (2,521 rows) and
called it "cheap". **I ran it. It does not reproduce as 100%/0%.**

```
$ python3 /tmp/zc_join3.py        # 565 pane splits (ppid_comm=claude), 2026-08-07T21:18Z → 2026-08-19T11:31Z
                                  # 937 Agent/Task tool_use calls in the same window, 4 stores, deduped on basename
    offset      named hit%        unnamed hit%
         0     92.3% (585/634)    15.5% (47/303)     ← the real numbers
       900     13.2%              6.6%               ← offset controls: the named signal is REAL…
      3600      4.1%              3.6%
      7200      7.7%             10.2%
     86400      2.2%              0.0%
     -3600      4.3%              1.7%
```

Three things the published figure hides:

- **49 NAMED calls produced no pane** and **47 UNNAMED calls did.** The unnamed 15.5% is 2–4× the
  offset-control base rate (0–10%) — concentrated in `general-purpose` at **26/96 = 27%**. That is
  not noise, and nothing in the wave explains it. L1 is priced on "1 pane → 0".
- **The one-day sample could not have tested the confound it claims to have controlled.** All 11
  named calls were `deep-research`; all 7 unnamed were `Explore`/`general-purpose`. `name` and
  `subagent_type` were 100% collinear at n=18, so "perfect control" is an overclaim *about that
  sample*.
- **The confound IS breakable, and it breaks in the synthesis's favour** — which is why this should
  be published instead of the 0/7:
  `[deep-research] named 154/179 · unnamed 7/76` · `[Explore] named 23/27 · unnamed 14/123` ·
  `[general-purpose] named 353/370 · unnamed 26/96`.

**Probe to close:** attribute the 47 unnamed-with-pane and 49 named-without-pane rows by `sessionId`
and check whether a sibling teammate wave was live in the same session at those instants. Script and
raw output: `pane-attribution-join.py`, preserved beside this file (re-runnable, read-only; it was
authored into `/tmp`, which would have expired it — the lead copied it into the repo and reproduced
its numbers to the digit before publishing them). Publish 92.3%/15.5% with the offset table,
not 11/11 vs 0/7.

---

## G2 — L1 (the flagship recommendation) moves fan-out to the ONE unit our tooling cannot stop

§6 L1's Risk column lists three costs (gates, caps, "one teammate = one pane you can look at"). It
omits the operationally worst one, and the wave measured it: **a running Dynamic Workflow has no
abort path in anything we own.** A5 §2d: *"U1/U3 have no process and no pane, so teardown is n/a and
`shutdown_request` is the only lever (and only for U2)."* So a workflow has no `cc-teardown` (no
pane), no `shutdown_request` (not a teammate), no `claude stop` (not a bg job), no registry row, and
no mailbox. The largest run in our history is **229 agents over 7.2 h costing 39 pp**; if that run
goes wrong today the only lever is killing the parent session, which kills the operator's context
too.

**Probe:** grep the 2.1.220 binary for a workflow-abort surface (`WorkflowAbort`, `abortSignal` bound
into `tTd`, `/stop` handling of an in-flight `Workflow` tool call) with a positive control on
`tengu_workflow_agent_cap_exceeded` (known present). If none exists, L1's risk line must say so and
the mitigation is a budget (`budget.total`), not a gate.

---

## G3 — The wall that has actually panicked this box four times is not in §5's ranking

§5 wall #4 states the failure mode correctly — *"the failure mode is compressor exhaustion /
watchdog panic, not OOM"* — and then computes the wall as `26.6 GB ÷ 375 MB = 70`. Those two
sentences are inconsistent: 26.6 GB counts **inactive** pages as available.

MEASURED HERE (reproduces A8's number and shows what it contains):

```
$ vm_stat        free 241,923 · inactive 1,321,844 · purgeable 48,843  ×16 KiB = 26.4 GB "available"
                 active 1,358,288 (22.2 GB) · compressor 503,582 (8.2 GB)
$ sysctl kern.memorystatus_vm_pressure_level                    → 1 (NORMAL)
$ sysctl vm.compressor_segment_pages_compressed                 → 1,008,031
$ sysctl vm.compressor_segment_pages_compressed_limit           → 26,073,840
```

The repo already ships the right instrument — `cc_hw_compressor_segment_pct`
(`scripts/lib/capacity-admit.sh:667`, ceiling 50%), and A5 read it live at **9.00%** during the wave.
Its own comment records **100% at panic, 0.00% on a quiet-box control**. **Per-unit segment cost is
UNMEASURED for every one of the seven units in §2**, so the wall with four incidents behind it
(tasks #75/#142/#151) has no number and no rank.

**Probe:** `cc_hw_compressor_segment_pct` before / during / after (a) an 8-agent workflow and (b) an
8-teammate wave; the wall is `50% ÷ slope`. Two 30-second reads around waves that are going to run
anyway.

**RESOLVED IN PART (2026-08-24, backlog `33d9b33bbd28`).** The synthesis now carries **§5-bis**,
which bounds all seven units' *resident* segment cost from measured footprints and shows the wall is
**≥135 resident panes** — it does not rank, and 13 teammates at the panic account for **4.4%** of the
limit the kernel read at 100%. The ranking defect this section names is fixed. What stays open is the
**flow** term, refiled as the synthesis's **Q12**; the probe prescribed above now ships as
`scripts/unit-segment-cost.sh`, with the drift discipline §6 N9's refuted differential lacked.

---

## G4 — §5 wall #3 (`terminal ~30`) is an iTerm2 figure, on the wrong unit, contradicted by §1

- It is inherited from `terminal-for-30-panes-2026-07-31.md` — **19 days old, about iTerm2**, and this
  box migrated to kitty *because of* that limit.
- It is attributed to the wrong unit. That doc's line 7 and README:248 say the freeze is an iTerm2
  **window**-leak (upstream #12097/#12645/#12905): *"a pane inside an existing window costs almost
  nothing"*, and kitty was picked because it *"holds all 30–40 panes in one OS window (measured)"*.
- **§1 of the same synthesis contradicts §5 of it.** §1 quotes `max 51` panes from the utilization
  log. MEASURED HERE over all 1,875 fleet timestamps: `med 11 · p95 37 · **max 54** · 156 samples
  >30 · 82 samples >40`. A pane count that exceeded 30 on 156 occasions cannot also be a wall at 30.

Only two readings, and both are actionable: either `k` counts non-pane processes — which is exactly
A5's **W6**, still INFERRED and never observed — or the rung is false today.

**Probe (settles both at once, 30 s, needs a daemon alive):**
`ps -wwEo command= > /tmp/k.txt; grep -c 'claude.exe daemon' /tmp/k.txt` cross-checked against
`claude-accounts --route-meta`'s `k=`. Then re-rank the terminal wall on kitty, or delete the rung.

---

## G5 — Six orchestration units exist and were never measured; four have zero mentions in 13 files

A7 §2g reads the binary's own task-type map — `{local_bash, local_agent, remote_agent,
in_process_teammate, local_workflow, mcp_task}` — six types, and its own "consumes local ceiling?"
table has **five rows**. Coverage across all 13 wave files (`grep -ril`, 13 = all):

| unit | files mentioning | status |
|---|---|---|
| `mcp_task` | **1** (a list, no row) | UNMEASURED — a task type the binary names |
| `local_bash` = `Bash(run_in_background:true)` | 2 | A1 Q2 named the probe; never run. Also has a **known correctness side-effect**: CLAUDE.md documents that a non-terminal background Bash deletes a live `/goal`'s Stop hook |
| `isolation:"worktree"` | 0 as a unit (10 files mention "worktree" for `--worktree` fires) | UNMEASURED — **no column in §2's table**, and it is the *landing zone* of A7's silent remote downgrade. Only unit that costs a git worktree; this repo has a standing 65-worktree hygiene sweep |
| `Agent({run_in_background:true})` | 2 | UNMEASURED — the field is visible in A1-VERIFY §3.9's own key list and in A7 §2b's `W.background===true` branch |
| Skill-invoked background subagent | **0** | UNMEASURED — the Skill tool's own contract: *"some skills instead run in a subagent… a skill that runs in the background returns only the agent's name"* |
| `claude agents` view process | 1 (A3-VERIFY C13) | UNMEASURED — `tengu_bg_leftarrow_inprocess` defaults **true**, falls through to `qUe({args:["agents",…]})` (a real spawn) on throw |

**Probe (one scratch session, ~5 min):** one call each; `ps -axww -o pid=,ppid=,args= > f` before and
after, then grep the file anchored on argv[0]; `kitten @ ls` pane count either side. Add a column per
unit to §2 or an explicit "not measured" cell — an absent column reads as "costs nothing".

---

## G6 — §4's per-unit pp numbers are printed flat, over a model two verifiers said cannot carry them

§9 records the cache-read downgrade and then §4 prints `median 0.213 pp`, `12–40 pp`,
`39.1 pp = 39% of an account's 5-hour allowance` with no interval. A6-VERIFY §C5 showed
`RMSE=1.73, n=23` is arithmetically impossible against a published in-criteria residual of 17.7 pp
(contributes 313 against a total SSR budget of 68.8) and could not resolve it because the fit-set
list is in a scratchpad. Worse for the decision at hand: **A6 §2.6 measures a perfect class/TTL
collinearity** — `teams-agent` writes 100% 1-hour-TTL cache, `workflow-agent` writes 100%
5-minute-TTL cache, a 1.6× list-price difference on the token class that dominates a fan-out unit's
cost — and A6 §3.5 states outright that observational data can **never** separate the two
coefficients. So the single comparison L1 turns on (teammate pp vs workflow pp) is precisely the one
the model is least able to make, and §4 makes it anyway.

**Probe (A6's own §4 Q1, ~10 min, spends a little quota):** one idle account, identical prompt, run
once as a named teammate and once as a workflow agent; read `claude-accounts --readout` before/after.
Until then, publish §4's pp figures with the class caveat attached.

---

## G7 — "Billed to the parent's account, always" is true of the ACCOUNT and false of the METER

Five custom agent definitions exist and are identical in all four config dirs
(`~/.claude*/agents/{deep-research,deep-research-sonnet,frontier-derivation,motion-reviewer,
research-decomposition-critic}.md`). MEASURED HERE — their frontmatter carries:

- `model: opus` / `model: sonnet`, and `frontier-derivation`'s own description says the lead passes
  `model:"fable"` at call time. **The readout has a separate `Fable used` column and A6 excluded
  Fable windows from its fit** — so a fable-pinned in-session agent draws a *different meter*. That
  is a routing lever for an "unroutable" unit, and §4 and §6 both miss it.
- `maxTurns: 100` — a per-agent bound in no table in the wave.
- `deep-research.md` grants the **`Agent`** tool, i.e. nesting is *defined*, defeated only by the
  undocumented `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1` of §8 Q10.

**Probe:** one unnamed `Agent({model:"fable"})` call; diff the `Fable used` column and the 5h/weekly
columns in `claude-accounts --readout` before/after.

---

## G8 — L1's resource failure mode is unstated: it concentrates N agents into ONE Bun heap, and nobody measured that heap's wall

The per-agent figure L1 sells (`0.6–11 MB`) is a **2-point parent delta with an 18× internal spread**;
A8 §6.4 says so in its own words ("not an isolate"), and A1 §5.4 says conversation length dominates
and it could not separate it. At the top of that band, `8 workflow + 20 subagent = 28` in-process
agents = ~308 MB of heap added to a process already footprinting 224–449 MB. **Nothing in the wave
measured a per-process ceiling** (JS heap / Bun gigacage / the `IOAccelerator` term of §8 Q1). And
§6 L6 cites **2.1.221 "memory-leak fixes in long sessions"** as a *benefit* without connecting it to
L1 as a *risk*: L1 is the lever that maximises time-in-one-long-session.

**Probe (A8's own Q4):** fresh session; `/usr/bin/footprint -p` at N = 1 / 4 / 12 / 20 concurrent
unnamed agents at matched wall-clock, recording the `JS VM Gigacage` and `JS JIT` rows, not just the
total. The 0.6–11 MB band should collapse to a slope; if it does not, L1's arithmetic has no floor.

---

## G9 — §5's ordering line reproduces the exact unit error §5 opens by calling "the single biggest error in the wave"

> ⇒ **Ordered: load gate (~4–8 active / felt ~15) < quota (26 panes) < terminal (~30) < memory (~70).**

Item 1 is in *mid-turn* units; items 2–4 are in *resident panes*. At the wave's own measured duty
cycle (0.36) the load gate is **11–22 resident panes**, which reorders nothing but is 3× the number a
reader takes from that line. **Probe: none needed — restate the whole ranking in resident panes and
show the 0.36 conversion inline.**

---

## G10 — Wall #1 rests on a historic calibration A5 flagged as possibly test-contaminated, and nobody closed it

`capacity-admit.sh:695-700` (the source of both the `active ceiling 8` and §5's "~4–8 mid-turn
sessions") reads: *"2.5-5 runnable threads per genuinely-ACTIVE session … which is also what all
**127/127** historic gate refusals correspond to."* A5 §3 C1 measured **19** refusals in the 9-day
window, all `under_test:false` — and separately measured that **196 of 201 `gate-off` rows are the
test harness**. If the historic 127 included harness fires, the number that produces the binding wall
is contaminated. A5 raised it as Q3; the synthesis inherits "~4–8" without it.

**Probe:** `jq 'select(.gate=="capacity" and .verdict=="refuse" and .under_test==false)'` over the
whole of `~/.claude/logs/handoffs.jsonl` (not just the 9-day window) and republish the calibration
count, or mark the 8 as provisional in `capacity-admit.sh` itself.

---

## G11 — "The fleet's median pane count is exactly 15" is sample-conditioned; unconditioned it is 11

§1's closing argument ("~15 is a *descriptive median*, not an enforced limit") cites A6-VERIFY's
`med=15, p95=37, max=51, n=517`. That n=517 is the subset of timestamps where **all four accounts
reported simultaneously**, which selects busy moments. MEASURED HERE over all **1,875** fleet
timestamps in the same log: `med 11 · p95 37 · max 54`. Both are defensible; only one is published,
and it is the one that makes the operator's number land exactly on the median.

**Probe:** publish both, with the filter stated. If the unconditioned median is 11, the operator's
"~15" is ~70th percentile, not the median — a different and weaker version of the same (correct)
point.

---

## G12 — Cloud relief (L3) is unpriced against a default a verifier explicitly handed over

A3-VERIFY §3.6 inspected all 41 `maxConcurrent` hits and found the **scheduled-tasks daemon worker**
at `maxConcurrent: E.number().int().positive().default(1)`, then wrote: *"if cloud routines are being
counted as ceiling relief anywhere in this wave, that default needs checking."* The synthesis counts
cloud as relief (L3, §5 "Cloud: zero local slots") and never checks it. Also missing from L3's Risk
cell, both from A7: the **daily per-account routine run cap**, and that a cloud session with
`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` fans out — so "N cloud sessions" is not N units of
parallelism, in either direction.

**Probe:** read the `WORKER_KINDS` / `runDaemonWorker` slice around that default and determine
whether it bounds routine *execution* concurrency; and fire two `--cloud` sessions and confirm both
run rather than queue.

---

## G13 — Two levers with named mechanisms are missing from §6 entirely

- **`--bare`.** A7 §3E calls it *"the highest-leverage local knob available today"* — it skips hooks,
  skills, plugins, MCP discovery, auto-memory and CLAUDE.md, which is most of what makes a session
  expensive here. A7 could not measure it (needs `ANTHROPIC_API_KEY`; bare mode never reads OAuth).
  That makes it a **pricing decision**, not an unavailable lever — and §6 lists nine levers without
  it. Probe: mint one key, run `claude -p --bare` and `claude -p` on the same prompt,
  `footprint -p` both, and count MCP children.
- **`CLAUDE_CODE_TEAMMATE_COMMAND`** (A2 §2i, byte 230485238): replaces the teammate launch command
  outright — *"the hook point for admission control on teammate spawn."* §7 names "the 6-concurrent-
  teammate cap is prose only" as a live defect and §6 offers **no** remedy for it, while A2 hands one
  over. Probe: set it to a wrapper that logs + defers to the real binary, spawn one teammate, confirm
  the wrapper ran.

---

## G14 — L7's coverage is unmeasured, and the store carries the same symlink trap the wave already found

MEASURED HERE: **14** `sessions/*.json` files across the four config dirs, **11 unique** — because
`~/.claude-next/sessions` resolves into `~/.claude/sessions`, exactly the trap A6 §3.7 documented for
`projects` and nobody carried over. All 11 pids are alive (so the self-GC claim holds), against
**17** live claude-family processes by argv[0]. So a census that walks four dirs double-counts
`next`, and the coverage ratio (11/17, or better if the 6 are launcher wrappers) is stated nowhere.
L7's Risk cell says only "a second registry to reconcile".

**Probe:** union on `pid` across `realpath`'d dirs, diff against an argv[0]-anchored `ps` snapshot,
and classify every unmatched claude process before adopting the registry.

---

## G15 — N7 ends "needs a filed decision" and no decision was filed

`scaling-bottlenecks-2026-08-09.md:36,150` still carries *"68% of quota cost is cache-read ⇒ halving
context ≈ +50% active capacity"* into **standing policy**, and `exchange-rate.md:223` gives the
opposite advice. The synthesis names the contradiction, says a filed decision is required, and
files nothing — so by this repo's own close protocol it is invisible to every sensor.
**Probe: `cc-decide open --class C`, one line, plus an INTEGRATE edit striking line 36/150.**

---

## Live-state note (not a gap — verified so the synthesis's assertion has a timestamp)

§7 asserts A3's leaked probe *"was later reaped by that axis's own verifier."* Confirmed at
2026-08-19, snapshot-to-file then grep, with a control token that reads 0:

```
claude.exe daemon run     0
bg-pty-host               0
claude.exe --agent-id     1
ZZZ-cannot-exist          0     ← control
```

Recorded because the synthesis asserted a live-state fact with no timestamp, which is the class this
repo calls "published figure rots".

---

## Two claims I checked and could NOT break

- **The workflow cap is 8, and it saturates.** Binary constant, live queueing at 4–6 s release
  intervals, and 231 historical tool calls with zero peaks above 8. Three independent instruments,
  one of them prospective. Nothing to add.
- **The teammate family takes no concurrency slot.** All three backends traced independently by two
  agents (`$W_`, `UW_`, `ivd`→`PW_`), with `takeConcurrencySlot` positive-controlled at 6 hits
  binary-wide and 0 in the reachable path. This is the strongest finding in the wave and N1/N2 are
  correctly derived from it.
