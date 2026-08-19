# A4-VERIFY — adversarial verification of the Dynamic Workflow engine axis

Verifier pass over `A4-workflow-engine.md`. Date 2026-08-19 · Binary 2.1.220
(`/Users/chrisren/.claude-220/.../bin/claude.exe`, sha256 `8addc857f3fe64d5…`, 256,908,272 B Mach-O arm64).
Method: every load-bearing claim re-derived from scratch — I did not reuse the finder's offsets, script,
or corpus census. Read-only on the live fleet; **nothing spawned, killed, stopped or closed.**

---

## 1. Verdict (≤5 lines)

1. **The finder's core is CONFIRMED and I upgraded its weakest link.** The cap expression is real (I found
   it independently), the history recompute reproduces the finder's table *exactly*, and the one claim
   they explicitly could not runtime-verify — "workflow agents create no process, no pane" — I verified
   **LIVE**, because this very 13-agent wave *is* a Dynamic Workflow.
2. **STRENGTHENED:** the finder said "39 of the 40 largest runs peak at exactly 8". Across **all 231
   workflow tool calls in 158 run dirs, 4 account stores: ZERO ever exceeded 8.** 82 saturate at 8.
3. **CONFIRMED, and WIDER than the finder claimed:** the named-teammate branch takes only the lifetime
   cap. I traced **all three** teammate backends (`$W_` split-pane, `UW_` tmux, `ivd`→`PW_` in-process);
   **none** takes a concurrency slot. It is the whole teammate family that is ungoverned, not just panes.
4. **PARTIALLY REFUTED:** "named teammates = real processes" is *conditional*, not definitional. `qW_`
   routes to an **in-process** teammate whenever `Lrn()` is true — including "not in tmux AND not in
   iTerm2", which is this box's kitty default. The finder's A1-reconciliation instruction is over-strong.
5. **PARTIALLY REFUTED:** the finder's §2c method caveat has its **direction inverted** — the estimator
   under-counts, not over-counts. The conclusion survives and gets *better*: measured peak 8 vs a
   binary-read cap of 8 means the limiter was **saturated**, not merely respected.

---

## 2. Claim-by-claim

| # | Claim under test | Verdict |
|---|---|---|
| C1 | Cap = `Math.min(16,Math.max(2,cores-2))`, `Qq_=Xq_(os.cpus().length)` = 8 here | **CONFIRMED** |
| C2 | Workflow agents = in-process, 0 processes, 0 panes | **CONFIRMED — and upgraded to LIVE** |
| C3 | "50–200 concurrent" is false as concurrency, true as throughput | **CONFIRMED, strengthened** |
| C4 | The 229-agent run: peak 48 = 8 tool calls × ≤8, 11.3 % above 8 | **CONFIRMED, recomputed identically** |
| C5 | Teammate branch calls `N()` (lifetime) and never `U()` (concurrency) | **CONFIRMED, and wider** |
| C6 | Plain `Agent()` *is* capped at 20 concurrent — not ungoverned | **CONFIRMED** |
| C7 | Named teammates are real OS processes with panes | **PARTIALLY REFUTED — conditional** |
| C8 | `[first,last]` transcript span over-counts slot occupancy | **REFUTED — it under-counts** |
| C9 | Workflow cap not configurable; `SPAWN_DEPTH=1` blocks re-spawn | **CONFIRMED (behaviourally)** |
| C10 | 4096-item cap is prose-only, enforcement unlocated | **CONFIRMED as unresolved** |
| C11 | `isolation:'remote'` = 50 cloud agents is the origin of "50 agents fine" | **UNVERIFIED — inference** |
| C12 | Corpus = 160 wf dirs | **MINOR — 159 by find, 158 with parseable transcripts** |

---

## 3. The numbers, with the command that produced each

### C1 — the cap expression, found independently (MEASURED)

The finder could have restated the tool's own documentation. It did not — the code is there.

```
$ /usr/bin/grep -a -o -b 'Math\.min(16,Math\.max(2,[a-zA-Z_$]*-2))' bin/claude.exe
234411135:Math.min(16,Math.max(2,e-2))
```
Positive control that the instrument is not blind: `grep -a -c 'Math.min('` → **375** matching lines;
`Math.min(16` is unique in the file (1 hit).

Byte-slice at that offset (`python3` seek/read, since `dd` is permission-gated here):
```js
function Xq_(e){return Math.min(16,Math.max(2,e-2))}
```
```
$ /usr/bin/grep -a -o -b 'Qq_=[^,;]*'  → 234433389:Qq_=Xq_(JSd.cpus().length)
$ /usr/bin/grep -a -o -b 'JSd=require("[a-z]*")' → 234433351:JSd=require("os")
$ /usr/bin/grep -a -o -b 'Zq_=[^,;]*'  → 234432118:Zq_=50
$ /usr/bin/grep -a -o -b 'QSd=[^,;]*'  → 234432125:QSd=1000
$ /usr/bin/grep -a -o -b 'Et_=[0-9]*'  → 230703566:Et_=20
$ /usr/bin/grep -a -o -b 'vt_=[0-9]*'  → 230703573:vt_=200
```
`hw.ncpu` = 10 ⇒ `min(16, max(2, 8))` = **8**. The limiter construction `B=CB(Qq_,K), j=CB(Zq_,re)` and
the `QSd` breach path (`tengu_workflow_agent_cap_exceeded`) are both present verbatim in the `tTd(...)`
slice I read. **C1 CONFIRMED.** The doc-prose bug the finder flagged is also real — the tool text at
offset 234461500 says *"only ~10 run at any moment"*, which is a 12-core number. Do not quote it.

### C2 — the live proof the finder declined (MEASURED, LIVE)

The finder listed this as *"the one load-bearing claim in the file without a runtime observation"* (§3.4)
and declined to spend quota on a probe. **No probe was needed: this wave is itself a Dynamic Workflow.**
Its run dir is keyed on my own session id:

```
$ /usr/bin/find ~/.claude*/projects -path '*subagents*' -name '*.jsonl' -newermt '-5 minutes'
…/.claude-secondary/projects/-Users-chrisren-Development-claude-infrastructure/
   f285654f-850c-4ada-96b5-407c5c01ccf0/subagents/workflows/wf_06556f35-03a/agent-*.jsonl   (11 live)
```

12 samples at 10 s over ~2 min, while 12 workflow agents were running:

| ts (UTC) | agent files | active ≤15 s | `claude.exe` procs | `--agent-id` procs |
|---|---:|---:|---:|---:|
| 12:06:34 | 12 | 3 | **3** | **1** |
| 12:06:44 → 12:07:56 | 12 | 2–3 | **3** | **1** |
| 12:08:06 | 12 | 4 | **3** | **1** |
| 12:08:26 | 12 | 2 | **3** | **1** |

Process counts **never moved**. The single `--agent-id` process is `A10-hostile-reviewer@session-84bde2e9`,
a leftover teammate from an *unrelated, earlier* session (started 04:31:38, ppid 17203). **A 12-agent
Dynamic Workflow ran to completion adding zero OS processes and zero panes. C2 CONFIRMED, live.**

Argv-position-anchored census (my first `ps | grep` matched its own command line — the known
`pgrep -f`-sees-briefs trap; re-done keying on argv[0]):
```
processes whose ARGV[0] is a claude binary: 19
  session/launcher 17 · daemon 1 · TEAMMATE(--agent-id) 1
```

**And the live run reproduces the cap of 8 as a queueing signature** — the cleanest evidence in either
file. Agent first-write times, relative to the first agent:

```
+   0.0s / +   0.1s / +   0.1s / +   0.2s / +   0.6s / +   1.0s / +   1.4s / +   2.1s     ← 8 start at once
+ 906.7s  (predecessor a95cde75 last wrote + 900.7s)                                       ← slot freed
+ 932.9s  (predecessor afb3d26a last wrote + 927.2s)
+1003.7s  (predecessor a05016d8 last wrote + 999.4s)
+1111.4s  (predecessor add28d6f last wrote +1107.3s)
```
Eight agents start inside 2.1 s; agents 9–12 each start **4–6 s after some predecessor's last write**.
That is a semaphore of exactly 8 releasing and re-acquiring. Sweep-line on the same run: `max concurrent
= 8`, `time >8 = 0 s of 1572 s`. Two independent instruments (binary constant, live queueing) agree.

### C3 + C4 — the history, recomputed from raw timestamps (MEASURED)

I wrote my own sweep-line (`scratchpad/verif_conc.py`, `verif_all.py`) rather than reuse the finder's.

**The 229-agent run, recomputed:**
```
agent files: 229  usable: 229  unusable: 0
timestamp formats: {'Z': 14326}          ← all UTC, single format; no TZ hazard
agents with any is_error: 0
agents with <2 lines (possible crash / never-ran): 0
RUN max concurrent: 48  at 2026-07-21 15:11:17.947+00:00
wall seconds: 25905
time with >8 simultaneous: 2934 s of 25905 s = 11.3%
```
Per-promptId table reproduced **digit-for-digit** against the finder's (6, 34, 36, 33, 40, 39, 6, 6, 29
agents; peaks 4, 8, 8, 8, 8, 8, 6, 6, 8; same windows). The three verifier hazards named in my brief were
checked and are all clean: **no crashed agents** (0 `is_error`, 0 stub files), **timestamps are one
format in one timezone** (all `…Z`), and I did **not** use `journal.jsonl` — it is start/result records
with no timestamps at all, so it cannot record ends and was never load-bearing.

**The global test the finder did not run** — every workflow tool call ever, all 4 account stores:
```
distinct wf dirs analysed: 158
GLOBAL max per-workflow-call concurrency: 8
distribution of per-call peaks: {1:40, 2:26, 3:16, 4:20, 5:12, 6:26, 7:9, 8:82}
per-call peaks >8: 0 of 231
largest single-call agent count: 83   (peak still 8)
```
**231 workflow invocations, not one above 8.** The finder's "39 of 40" understates its own result.

### C5 + C6 + C7 — where the governor is, and where it is not (MEASURED, source)

Agent-tool dispatch, read at 234670600–234673800 (I found this region myself via
`grep -a -o -b 'takeConcurrencySlot'` → 6 hits, and `use_splitpane` → 3 hits; the two sit **210 bytes
apart**, which is what made the branch worth reading rather than assuming):

```js
N = ()=>{ …budget…; let gt=XYr(), Dt=l.taskRegistry.getTotalAgentSpawns();
          if(Dt>=gt) throw `Subagent spawn limit reached (${Dt} of ${gt} …)`;
          l.taskRegistry.incrementTotalAgentSpawns() },                         // LIFETIME
P = ()=>{ let lt=wHu(); if(l.taskRegistry.getConcurrentSubagents()<lt) return;
          if(Ke("tengu_amber_kestrel",!1)) return;                              // bypass 1
          let gt=l.getAppState();
          if(EK(l.rootToolSurface.mainLoopModel,gt.effortValue,gt.ultracode)) return;  // bypass 2
          return `Concurrent subagent limit reached. You can run ${lt} subagents at once.` },
U = async()=>{ let lt=P(); if(lt) throw await at(), lt;
               return l.taskRegistry.takeConcurrencySlot() };                    // CONCURRENCY

if(b&&i&&!L&&!s&&!a){ N();                                    // ← lifetime only
    let et=await cvd({name:i, …, use_splitpane:!0, …},l,d);
    return {data:{status:"teammate_spawned", …}} }            // ← returns; U() never reached
```
`U()` is *defined immediately above* the teammate branch and *never invoked inside it*. **C5 CONFIRMED.**
Registry impl (234213900 region) shows the slot is real and idempotent:
`takeConcurrencySlot(){ t(i=>({...i,runningSubagents:i.runningSubagents+1})); … return ()=>{…Math.max(0,…-1)…} }`.
So **plain `Agent()` is genuinely capped at 20** — the finder is right that "ungoverned free-hand
fan-out" would have been the wrong headline. **C6 CONFIRMED.**

**I then went further than the finder and traced what `cvd` actually does.** `cvd(e,t,r)→qW_(e,t,r)`
@234645398:
```js
function qW_(e,t,r){ …;
  if(Lrn()) return ivd(e,t);                                   // IN-PROCESS teammate
  try{ await Prn() }catch(o){ if(KMt()!=="auto") throw …pane_unavailable…;
       return …"falling back to in-process"…, ivd(e,t) }        // IN-PROCESS fallback
  if(e.use_splitpane!==!1) return $W_(e,t);                     // SPLIT-PANE teammate
  return UW_(e,t) }                                             // TMUX teammate
```
- `$W_` @234637329 builds argv `--agent-id … --agent-name … --team-name … --agent-color …
  --parent-session-id …` — **an exact match for the live `A10-hostile-reviewer@session-84bde2e9`
  process**. So `--agent-name` really is the discriminator the finder proposed for reconciling with A1.
- `UW_` @234639919 → `tmux new-window`.
- `ivd` @234643137 → `Fko(...)` then `Mko({… countedTowardSessionSpawnCap:!0})`. `Mko`→`PW_` @234618745
  contains only `if(!y&&!g) C.incrementTotalAgentSpawns();` — **no `takeConcurrencySlot` anywhere in it.**

**None of the three backends takes a concurrency slot.** The bypass is not a split-pane quirk; it is the
entire named-teammate family, bounded only by 200/session + budget. That makes the finder's headline
*stronger*, and it removes the tempting mitigation "just force in-process teammates" — that path is
un-capped too.

**C7 PARTIALLY REFUTED.** `Lrn()` @232759168 (`isInProcessEnabled`):
```js
if(_n()) return true;                                   // non-interactive (headless) session
let t=gP_(); if(t==="in-process") r=!0; else if(t==="tmux"||t==="iterm2") r=!1;
else { if(e.inProcessFallbackActive) return true;
       r = !Bdo() && !wpe(); }                          // NOT in tmux AND NOT in iTerm2 ⇒ in-process
```
with `KMt()`'s fallback literal being `nrn="in-process"`. On **this** box — kitty, not iTerm2, not tmux —
the unset-mode branch resolves to **in-process** unless `teammateMode` is pinned in settings. So "named
teammate ⇒ OS process + pane" is *conditional on the backend that resolves*, not definitional. The
finder's instruction to A1 ("named teammates = yes, processes") should be restated as: *a teammate is a
process **iff** it took the `$W_`/`UW_` path, which argv makes observable via `--agent-name`.*

Agent-teams are live here — env confirms the gate: `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` (required by
`mc()`, which also needs gate `tengu_amber_flint`).

**Attack-3 residual — could a limiter live in the tool-dispatch layer instead?** `CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY`
exists in the env registry (offsets 73764944 / 163000128 / 226172005); I could not resolve its default.
It cannot rescue this anyway: the teammate branch **returns immediately** with
`status:"teammate_spawned"`, so a dispatch-layer bound limits how many *spawn calls* run at once, never
how many teammates *remain resident*. No team-size cap string exists either — the only "You can run …"
message in the binary is the subagent one (positive control: 354 occurrences of `teammate`, so the
instrument sees that vocabulary fine).

### C8 — the finder's method caveat is inverted (REFUTED)

Finder §2c: *"`[first, last]` transcript timestamp is an **upper bound** on an agent's slot occupancy …
The estimator can therefore **over**-count and never under-count."*

The slot is taken **before** the agent's first message and released **after** its last, so
`[first write, last write] ⊆ [acquire, release]`. Subset intervals ⇒ the sweep-line maximum is a **lower
bound** on true simultaneous occupancy. **The estimator under-counts.**

This does not damage the result; it re-founds it. The right reading: a measured peak of **exactly 8**,
against a cap independently read out of the binary as **8**, means the limiter was **saturated** — and
the live queueing signature in §C2 (agent 9 starting 6 s after agent 3's last write) confirms
release-then-acquire directly, which no interval-estimator argument is needed for.

### C9 / C10 / C11 / C12 — the remainder

- **C9 CONFIRMED, with behavioural corroboration the finder lacked.** `~/.zshrc:484` →
  `export CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1`, and it is live in *my* process env. The consequence
  is observable in my own toolset: **I have no `Agent`/`Task` spawn tool at all.** A workflow agent at
  depth 1 genuinely cannot fan out. No `*WORKFLOW*CONCURREN*` env var exists.
- **C10 CONFIRMED as unresolved.** The workflow region's only `4096` (@234412962) is
  `if(Me.length>4096) ve="output schema too large to classify safely"` — the auto-mode permission
  classifier, unrelated. `"at most 4096 items"` @234461690 is the tool's **doc prose**. Enforcement site
  still unlocated by either of us. Not load-bearing for the ceiling question.
- **C11 UNVERIFIED — downgrade it to INFERENCE in the finder's file.** `workflow_remote_agent` exists in
  the binary (@103521744, @234428222) and `Zq_=50` is real, but I found **no evidence any of our 158 runs
  used `isolation:'remote'`**. A `grep -rl 'isolation.*remote'` hits 97 files under `workflows/wf_*` out
  of 2,813 — but that grep is too loose (it matches the tool doc quoted into prompt text, including in
  this wave's own briefs), so it proves nothing. The claim "remote is the true origin of the operator's
  '50 agents'" is a plausible story, not a measurement.
- **C12 MINOR.** `find … -name 'wf_*' | wc -l` → **159**, of which **158** have parseable agent
  transcripts. Finder said 160. The `wf_edda7d3d-3d8` mirror-duplicate the finder flagged is real and
  visible in my run table (two rows, 62 agents each, identical peaks). Immaterial to every figure.

### Attack 4 — the operator's premise, stated plainly

**"50–200 concurrent workflow agents" is FALSE in our evidence, and it is a COUNT read as a CONCURRENCY.**

| Quantity | Value | Source |
|---|---:|---|
| Largest agent COUNT in one workflow run dir | **229** (over 7.2 h) | `wf_0f8a38e6-82f` |
| Largest agent COUNT in one workflow tool call | **83** | `wf_d20aadf6-502` |
| Largest SIMULTANEOUS in one workflow tool call | **8** | all 231 calls, no exception |
| Largest SIMULTANEOUS across a whole session | **48** | 8 parallel `Workflow` tool calls × ≤8 |
| Where "50" is a real number | `Zq_=50`, **remote/cloud** agents, 0 local cost | binary; **never observed in our runs** |

A single workflow has **never** run more than 8 agents at once on this box, and cannot: the cap is
`min(16, cores−2)` and this box has 10 cores. Reaching 48 required the model to issue eight `Workflow`
tool calls in one turn — the pools do not merge, they *stack*.

---

## 4. What I tried that did NOT work / could not be measured

1. **`dd` is permission-blocked in this harness** (`dd if=<binary> bs=1 skip=…` was denied). All slicing
   was done with `python3` seek/read. Anyone repeating this should skip `dd` entirely.
2. **Wide-context regex on the 257 MB binary times out.** `grep -a -o '.\{60\}length>4096.\{60\}'` blew
   the 120 s budget. Use fixed-string `grep -a -o -b` to get an offset, then seek/read — always.
3. **`ps | grep 'claude.exe'` matches its own command line** and inflated my first census 3× (it counted
   the sampler script and the grep). Re-done anchored on argv[0]. This is the repo's known
   `pgrep -f`-sees-briefs trap and it bit me in the first minute.
4. **`/usr/bin/sysctl` does not exist** (it is `/sbin/sysctl`) — the load column of my live sampler is
   empty. Load was captured separately: `uptime` read `20.57 20.76 24.14` mid-wave. Load attribution is
   A2's axis, not mine, and I did not attempt it.
5. **I did not resolve `CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY`'s default value** — only that the var
   exists. Argued above why it cannot bound resident teammates regardless.
6. **I did not locate the 4096-item enforcement** either. Two of us have now failed to find it; treat the
   number as documentation until someone runs `parallel()` with 5,000 items.
7. **Per-agent marginal memory remains unattributable.** The live workflow gave me process *counts*, not
   a clean heap differential — the parent session was simultaneously running my own Bash probes. I made
   no memory claim.

---

## 5. Open questions the verifier could not close

1. **Does `teammateMode` sit unset on this box?** That decides whether a named teammate here is a
   ~500 MB process + pane or a free in-process generator. Read `~/.claude/settings*.json` for
   `teammateMode`; if absent, `Lrn()`'s kitty branch says **in-process**, which contradicts the fleet's
   lived experience of pane teammates and means something else is pinning it (`--agent-teams` argv, an
   explicit setting, or `Prn()` finding a backend). **This is the one open item that changes an operating
   recommendation.**
2. **Has this fleet ever run a `isolation:'remote'` workflow agent?** If never, the finder's §2e
   explanation for the operator's "50 agents fine" is a hypothesis with no instance, and the real
   explanation is simply item-count-read-as-concurrency (§Attack 4), which our data *does* support.
3. **`tengu_amber_kestrel` and `ultracode && effort==="xhigh"` bypass the 20-cap.** Neither of us checked
   whether either is live for this account. If `xhigh` is ever used, plain subagent fan-out becomes
   bounded only by 200/session — worth one `Ke()`-gate read.
4. **The two pools stack and nothing counts them together.** 8 workflow + 20 subagent + N teammates, in
   one session, with three separate counters and no aggregate. The account router counts *sessions* and
   is blind to all of it. That is a design finding, not a measurement gap, and it belongs to whoever owns
   the recommendation.
5. **For A1 reconciliation:** my answer is *conditional*, not split. Workflow agents and plain subagents
   are **always** in-process. Named teammates are in-process **or** a process, decided at spawn by
   `Lrn()`/`teammateMode`/pane-backend availability. `--agent-name` in argv identifies exactly the ones
   that took a pane. If A1 reports "uniformly processes", it is almost certainly counting only the
   `$W_` population and calling it the whole.
