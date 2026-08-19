# A8 — The marginal-cost experiment: what ONE more unit actually costs

**Date:** 2026-08-19 · **Box:** MacBookPro18,2 (M1 Max), 10 cores, 64 GiB, macOS 15.6, CC 2.1.220
**Method:** controlled probes + per-process attribution on the live fleet. Every number below carries
the command that produced it. Labels: **[M]** measured · **[I]** inferred · **[Q]** quoted from a doc.

---

## 1 · Verdict (5 lines)

1. **[M] The operator's hypothesis is HALF right, and the half that is wrong is the whole answer.**
   A *named team agent* is a real OS process in a real kitty pane (3 found live). A *plain
   research subagent* — the unit I am — has **no process and no pane**: 13 sibling transcripts
   active, **0** matching processes, on a grep proven able to find them.
2. **[M] Marginal cost is set by DUTY CYCLE, not by unit type.** An API-blocked unit of any kind
   contributes **0.02–0.06 load units**; a mid-turn unit contributes **0.5–2.0**. That 30× span is
   larger than every between-unit difference I measured.
3. **[M] Memory is where the units actually differ:** pane agent **≈380 MB** physical vs in-process
   subagent **≈11 MB** — a **35×** ratio — and the subagent additionally costs **0 panes, 0 fds,
   0 processes**.
4. **[M] Per wall, per unit** (§5): memory admits ~70 sessions / ~70 pane agents / ~2,400 in-process
   subagents; the 2.0/core load gate admits ~37 *simultaneously-active* units of any type. **The
   active-duty load term is what binds, and ~37 is the band the operator's felt ~15 sits in.**
5. **[M] Whole-box Δload CANNOT resolve one unit** — during my probe the box load *fell* (28.96 →
   26.75). Anyone measuring "cost of one session" by watching `uptime` is measuring the fleet.

---

## 2 · The structural finding that the cost numbers rest on

Two different execution models are live on this box **at the same moment**, and the wave's own
agents are split across them.

| | in-process subagent (me, A8) | pane team agent (A9/A10/A11) |
|---|---|---|
| OS process | **none** | `claude.exe --agent-id …` |
| Parent | tool calls are children of the **lead session** | `cc-pane-runner` ← kitty |
| kitty pane | **0** | **1 each** |
| own MCP server | no (shares lead's) | **yes — one `ms-365-mcp-server` each** |
| own hook children | no | yes (`mailbox-wake-arm.sh`) |

```
$ p=$$; ps -p $p -o pid,ppid,command   # walking my own ancestry
85693 99124  /bin/zsh -c source …/.claude-secondary/shell-snapshots/…
99124 99091  /Users/chrisren/.claude-220/node_modules/.bin/claude --permission-mode auto …
99091 83977  bash /Users/chrisren/.claude/bin/cc-close-attrib …
83977   587  /bin/zsh -l
  587     1  /Applications/kitty.app/Contents/MacOS/kitty
$ env | grep -E 'CLAUDE_PID|CHILD_SESSION'
CLAUDE_PID=99124
CLAUDE_CODE_CHILD_SESSION=1
```
My Bash tool runs as a zsh child of the **lead session process 99124**. There is no A8 process.

**Positive control for the null** (method rule 5). The same census that finds nothing for my 13
siblings *does* find the pane agents:

```
$ find ~/.claude-secondary/projects/-Users-chrisren-Development-claude-infrastructure \
       -name '*.jsonl' -mmin -25 | wc -l
      13                       ← 13 live sibling subagent transcripts (this wave)
$ ps ax -o pid,command | grep 'claude\.exe --agent-id' | grep -v grep
 8435 … --agent-id A9-prior-art@session-84bde2e9  --settings …wt-pool-8.json
17602 … --agent-id A10-hostile-reviewer@session-84bde2e9 --settings …wt-pool-8.json
28505 … --agent-id A11-redteam-widening@session-84bde2e9 --settings …wt-pool-8.json
```
The instrument can report agent processes; it reports **3**, and all three belong to a *different*
session — their `--settings` path is `…-worktrees-wt-pool-8.json`, which matches live session
**54762** (a reso session), not my lead 99124. So: one session's team runs in panes while my
13-agent wave runs entirely in-process, **on the same box, in the same minute**.

Their ancestry is our own pane machinery, not a Claude internal:
```
$ ps -p 7723 -o ppid=,command=
  7696 /bin/bash /Users/chrisren/Development/claude-infrastructure/bin/cc-pane-runner
$ ps -p 7696 -o command=
/usr/bin/login … kitty.app/Contents/MacOS/kitten run-shell --shell /bin/zsh -l -i -c 'exec "$CC_PANE_RUNNER"'
```

---

## 3 · The numbers table

### 3a · Physical footprint — `footprint -p`, never summed RSS

```
$ /usr/bin/footprint -p <pid> | sed -n 2p     # and: lsof -p <pid> | wc -l ; ps -M -p <pid> | wc -l
```

| Unit | pid | age | **footprint** | RSS (for contrast) | threads | fds | children |
|---|---|---|---|---|---|---|---|
| Interactive session, fresh | 55717 | 19 m | **221 MB** | 384 MB | 28 | 25 | 1 |
| Interactive session, fresh | 9576 | 20 m | **224 MB** | 406 MB | — | — | — |
| Interactive session, fresh | 56705 | 19 m | **227 MB** | 413 MB | — | — | — |
| Interactive session, mature | 54762 | 36 m | **356 MB** | 705 MB | — | — | — |
| Interactive session, 5-day | 60323 | 5 d | **448 MB** | 580 MB | 28 | 25 | 1 |
| **Lead hosting 13 in-process subagents** | 99124 | 27 m | **364 MB** | 785 MB | — | — | — |
| **Pane team agent** | 17602 | 26 m | **281 MB** | 470 MB | 18 | 28 | 2 |
| **Pane team agent** | 28505 | 26 m | **277 MB** | 503 MB | 19 | 30 | 3 |
| ↳ its MCP server (`node ms-365-mcp-server`) | 18451 | — | **102 MB** | 48 MB | 12 | 23 | — |
| ↳ its hook child (`mailbox-wake-arm.sh`) | 18461 | — | **2.8 MB** | 0.9 MB | 1 | — | — |
| **Headless `claude -p`, mid-turn** | 13852 | 18 s | **189 MB** | — | 15 | 38 | 2 |
| ↳ its own MCP server | 14252 | — | **101 MB** | — | 12 | 23 | — |
| ↳ its hook child (`operator-readout.sh`) | 24747 | — | **3.8 MB** | — | 1 | 12 | — |
| Launcher wrapper (`cc-close-attrib`) | 60248 | 5 d | **1.9 MB** | 0.4 MB | 1 | 9 | 2 |

**Unit totals (footprint, tree-inclusive):**
| Unit | physical |
|---|---|
| Interactive session (fresh → 5-day) | **290 → 460 MB** |
| Pane team agent (proc + MCP + hook) | **≈ 380 MB** |
| Headless `-p` run (proc + MCP + hook) | **≈ 295 MB** |
| **In-process subagent** | **≈ 11 MB** (see below) |

**The in-process subagent's memory, and why it is a bound not a point.** No process exists, so the
only handle is the lead's own footprint. Lead 99124 hosting 13 concurrent subagents = **364 MB**.
Controls: a comparable-age solo session (54762, 36 m) = **356 MB** ⇒ **+0.6 MB/subagent**; the median
fresh session (224 MB, ~20 m) ⇒ **+10.8 MB/subagent**. Take **0.6–11 MB [M, 2-point]**. Either end is
**35–630× cheaper than a pane agent's 380 MB**. RSS tells the same story more loudly (785 vs 705 MB
⇒ +6 MB each) and is *not* used for the claim, per method rule 2.

⚠️ **RSS overstates, unevenly.** Pane agent 470 MB RSS → 281 MB footprint (**1.67×**); session
580 MB → 448 MB (**1.29×**). Summing RSS across the fleet inflates the pane agent's apparent cost
by a third more than the session's — i.e. it biases exactly the comparison this wave is making.

### 3b · Runnable threads — the load-average numerator, attributed per unit

Instrument: `ps -axo pid=,ppid=,stat=` at 2 Hz, ancestor-walk each process to its owning root, count
`STAT ~ /^R/`. Positive/negative controls: the blocked launcher wrapper reads **0.000 runnable in
608 samples** (it can read 0); the busy probe reads **1.30** (it can read >1).

```
$ bash /tmp/a8/perroot.sh     # 30 s, 51 samples, my own instrument subtree excluded by pid-walk
```

| Root | what it is | procs/sample | **runnable procs/sample** |
|---|---|---|---|
| 99124 | **lead + 13 in-process subagents** | 23.18 | **4.098** |
| 54762 | interactive session + 3 pane teammates | 3.04 | 0.216 |
| 60323 | interactive session (idle at prompt) | 4.08 | 0.059 |
| 53709 / 56705 | interactive sessions | 8.00 / 6.00 | 0.039 / 0.039 |
| 20435 / 9576 / 21808 | interactive sessions | 5 / 6 / 1 | 0.020 each |
| 21952, 29540, 55717 | interactive sessions | 4 / 1 / 6 | **0.000** |
| 17602 | **pane team agent** | 6.00 | **0.039** |
| 28505 | **pane team agent** | 6.00 | **0.000** |
| *(instrument, disclosed)* | my own ps/awk | 3.00 | 1.45 |

**Per-unit marginals, and the ×1.553 conversion to load units.** Calibration from the same run:
box-wide runnable processes **18.654** at mean load **28.96** ⇒ **1 R-proc ≈ 1.553 load units**
(the gap is kernel threads + `ps` showing one state per multi-threaded process; **[I]**, single-point).

| Unit | state | **R-procs** | **load units** | source |
|---|---|---|---|---|
| Interactive session | fleet-average (mostly idle at prompt) | 0.041 | **0.064** | 10 sessions excl. 99124 |
| Interactive session | working (54762) | 0.216 | **0.335** | 1 session |
| **Pane team agent** | API-blocked | 0.020 | **0.030** | 2 agents |
| **In-process subagent** | actively tool-calling | 0.315 | **0.489** | 4.098 ÷ 13 |
| **Headless `-p`** | 100% mid-turn (arrival-dominated) | 1.300 | **2.02** | q1, 30 samples |
| **Headless `-p`** | 100% mid-turn, 2nd arm | 0.974 | **1.51** | q2, 38 samples |

Cross-check against the earlier whole-process `ps -M` census (run 1, 2 Hz, 56/39/31 sample instants):
`claude.exe` **process alone** — session **0.038**, pane agent **0.088**, MCP child **0.024**,
launcher wrapper **0.000**. Consistent with the repo's published **4.7% [Q]** claude share of the
load numerator: 11 sessions × 0.038 + 3 agents × 0.088 = 0.68 of ~19.4 ≈ **3.5%**.

### 3c · Fork rate — measured, and NOT a discriminator

Fresh-PID delta (the repo's own corrected method [Q], `session-capacity-ceiling` §7):
```
$ a=$(bash -c 'echo $$'); sleep 10; b=$(bash -c 'echo $$'); echo $(( (b-a) / 10 ))
```
| Window | forks/s |
|---|---|
| baseline (run 1, ~11 sessions + 3 agents) | **611.5**, then **548.2** |
| baseline (run 3, 40 min later) | **1206.8** |
| **during** the headless probe | **617.2** |
| after both probes | **529.1** / **1170.0** |

**The probe's fork contribution is unresolvable** — the mid-probe rate is *half* the baseline taken
minutes earlier. Consistent with the repo's settled §12 [Q]: *load tracks fork CONCURRENCY, not fork
RATE*; fork rate is therefore not an independent wall and its children are already counted in §3b.

**Do pane agents run hooks? YES [M].** Composition census (`ps -axo pid=,ppid=,stat=,comm=` at
2 Hz for 40 s, 69 samples, ancestor-attributed), normalised per unit:

| child image | per interactive session | per pane agent |
|---|---|---|
| `bash` (hooks) | 2.29 | **3.00** |
| `node` (MCP server) | 0.64 | **1.00** |
| `sleep` | 0.88 | 1.00 |
| `zsh` | 0.82 | 0 |
| `tee` (hook logging) | 0.73 | 0 |
| **total resident procs in subtree** | **7.8** | **6.4** |

A pane agent is **not** a stripped-down unit: it runs *more* hook forks and *more* MCP servers per
unit than a session does.

### 3d · Panes and file descriptors

```
$ kitty @ ls | python3 -c "import sys,json;d=json.load(sys.stdin);print(sum(len(t['windows']) for o in d for t in o['tabs']))"
13     (11 twenty minutes later, as agents exited)
```
11 interactive sessions + 3 pane agents = 14 claude units in **13 panes** — because 3 sessions are
driven by `expect -c` (the `limit-recover` harness, `LR_*` env) and hold no pane. **fds:** session 25,
pane agent 28–30 (+23 for its MCP), headless 36–38. Against a 1,048,576 fd limit, fds are noise.

---

## 4 · What I spawned, and cleanup

Four bounded headless runs, all `timeout`-wrapped, all exited, model `claude-haiku-4-5-20251001`:
smoke (`Reply with the single word READY`, rc 0, 8 s), run-1 p1 (1500 integers, **39.7 s**, 1500
lines), run-3 q1 (24 s), run-3 q2 (`--permission-mode auto`, 31 s). Verified clean:
```
$ ps ax -o pid,command | grep -E 'claude.*-p (Print|Run exactly)|a8/run|compose.sh|perroot.sh' | grep -v grep
NONE — all probes exited
```
Nothing was killed, stopped, or torn down. Raw data + harnesses: `/tmp/a8/` (`samples.tsv`,
`sub3.tsv`, `perroot.raw`, `compose.raw`, `fp3.txt`, `run.sh`, `run3.sh`, `perroot.sh`, `subtree.awk`).

**Headless viability [M]:** `claude -p` works from a subagent's Bash tool with the CC_* env stripped
— rc 0, correct answer. It is **not free of our stack**: it loads the MCP server (+101 MB) and fires
Stop hooks (`operator-readout.sh`). One real refusal was observed: with `--permission-mode auto`, our
own `validate-bash` guard blocked `for i in $(seq …)` — *"The Bash tool is blocking expansion
constructs… I can't run the exact command as specified"* — so the tool-using arm executed fewer real
tool calls than designed.

---

## 5 · The answer this axis owns — how many of EACH unit fit

**Available memory now (measured, not the `memory_pressure` headline):**
```
$ vm_stat | grep -E 'Pages free|Pages inactive|Pages purgeable'
free 366,838 · inactive 1,224,126 · purgeable 31,621   × 16 KiB  ⇒  26.6 GB available
$ sysctl -n vm.swapusage → total 0.00M   (no swap; failure mode is compressor exhaustion [Q])
```
**Load ceiling:** `CC_FIRE_MAX_LOAD_PER_CORE` default **2.0** (`scripts/handoff-fire.sh:4470`) ×
`hw.ncpu` 10 = **20.0**. Measured **non-Claude ambient today = 13.000 R-procs × 1.553 = 20.19 load
units** — i.e. the ambient alone already exceeds the gate. Column (b) therefore assumes a *quiet* box
(ambient 2.0 ⇒ 18.0 available) so the per-unit arithmetic is legible.

| Unit | **memory wall** (26.6 GB) | **load gate**, idle | **load gate**, all mid-turn | **pane wall** | **binds first** |
|---|---|---|---|---|---|
| Interactive session | 26,600/375 = **71** | 18/0.064 = **281** | 18/0.335 = **54** | 1 pane each | **memory @ ~71**, load @ ~54 if all working |
| **Pane team agent** | 26,600/380 = **70** | 18/0.030 = **600** | ≥ session's (own render+hooks) **[I]** | 1 pane each — terminal froze at ~30 on iTerm2 **[Q]** | **panes/terminal @ ~30**, then memory @ ~70 |
| **In-process subagent** | 26,600/11 = **2,400** | n/a (has no idle process) | 18/0.489 = **37** | **0** | **active-duty load @ ~37** — nothing else in the OS |
| Headless `-p` run | 26,600/295 = **90** | n/a | 18/2.02 = **8.9 concurrent starts** | 0 | **arrival cost @ ~9 simultaneous launches** |

**The ratio that is the operator's answer.** Pane team agent : in-process subagent —
**processes 2–3 : 0 · panes 1 : 0 · physical memory 380 MB : ≈11 MB (35×) · OS ceilings hit at ~30–70
: ~2,400.** So *"every subagent takes a pane and therefore one of the ~15 slots"* is true **only of
named team agents**; the plain subagent unit — which is what a 13-agent research wave actually uses
here — consumes **no slot at all**. A 50–200-agent fan-out is arithmetically fine against memory and
panes; what caps it is how many are **simultaneously mid-tool-call** (~37), not how many exist.

**And the felt ~15 is not a per-unit budget.** It is the *ambient* term: today's non-Claude load
already reads 20.19 against a ceiling of 20.0, while all 14 Claude units together contributed
5.65 R-procs (30%) — so the gate refuses the 15th session for reasons that have almost nothing to do
with the 15th session. This reproduces the repo's `4.7%` finding [Q] from an independent instrument.

---

## 6 · What did NOT work / could not be measured

1. **Whole-box Δload cannot price one unit — refuted with data.** Mean load: baseline **28.96**,
   during probe **26.75**, after **25.81**. The probe "reduced" the load. Run 1 saw the opposite
   artefact (base 19.40 → post **35.58** with my probe already dead). Any single-unit cost derived
   from `uptime` on this box is measuring the fleet. *Per-process attribution is the only instrument
   that resolves a unit.*
2. **Fork-rate delta likewise unresolvable** — baseline 1206.8/s > mid-probe 617.2/s (§3c).
3. **No mid-turn pane agent was ever caught.** Both surviving pane agents were API-blocked for my
   entire 30 s window (0.039 / 0.000 R). So I can state a pane agent's *memory* and *pane* cost as
   measured, but its *active* load cost only as **[I]** (≥ an in-process subagent's, since it does the
   same work plus its own render loop, statusline and hook forks).
4. **In-process subagent memory is a 2-point parent-delta, not an isolate.** No process exists to
   footprint. The 0.6–11 MB band is the honest width.
5. **The `×1.553` R-procs→load conversion is a single-point fit.** `ps` reports one STAT per
   multi-threaded process and cannot see `kernel_task`'s ~720 threads [Q]; the factor absorbs both.
6. **No `sudo` ⇒ no `dtrace proc:::exec-success`**, so per-fork attribution stays inferential — the
   same limitation the 2026-08-09 wave hit.
7. **The tool-using headless arm was blunted** by our own `validate-bash` expansion guard (§4), so
   its hook-fork load is a floor, not the true cost of a tool-heavy headless turn.
8. **Instrument self-load, disclosed:** my sampler ran at 2 Hz and its own subtree measured **3.00
   procs / 1.45 runnable** per sample — ~8% of the box's runnable-process count, the same order the
   prior wave disclosed. It is excluded from every per-root figure in §3b and constant across arms.
9. **A Dynamic Workflow was never measured.** I measured the *in-process subagent* unit (what this
   wave is). Whether Dynamic Workflows ride the same in-process path is another axis's question; my
   numbers bound the in-process unit only.

---

## 7 · Open questions for the verifier

1. **What decides pane-vs-in-process?** All three pane agents were simultaneously `--agent-type
   deep-research`, `--agent-name`-bearing and `--team-name`-bearing. My data cannot separate the
   three. Re-run with a *named* agent that is not `deep-research`, and a `deep-research` agent that is
   not named, and watch `ps ax | grep -c 'claude\.exe --agent-id'`.
2. **Is `bin/cc-pane-runner` (ours) or Claude Code the thing that forces a pane?** The pane agents'
   grandparent is our own kitty wrapper. If the pane is *our* integration rather than CC's model, then
   "subagents consume panes" is a claude-infrastructure fact, not a Claude Code fact — and it is
   removable. This is the highest-value follow-up in the wave.
3. **Re-derive `×1.553` across loads** (10 / 20 / 40) before quoting any absolute capacity number
   from §5; it is a single-point calibration.
4. **Settle the in-process subagent's memory with a controlled arm:** fresh session, `footprint -p`
   before, spawn N=1/4/12 subagents, footprint again at matched wall-clock. My 0.6–11 MB band should
   collapse to a slope.
5. **Catch a pane agent mid-turn.** Sample `ps -M` on `--agent-id` processes at 5 Hz across a full
   fan-out and report its active R-thread contribution — the one cell in §5 I had to mark **[I]**.
6. **Does the admission gate's 20.0 ceiling ever have headroom?** Measured ambient today is 20.19
   without any Claude unit. If that is typical, the gate is not rationing Claude at all, and every
   "capacity refusal" in the fleet is a refusal about the box's background, not about sessions.
