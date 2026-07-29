---
status: open
---

# AUTONOMY DISPATCH V2 — first-principles rebuild of dispatch & discovery

**Scope (frozen):** the autonomy dispatch & discovery subsystem achieves a dispatch decision
within 5 minutes of a backlog-add and ZERO false cliffs, under the standing constraint that
**backlog > concurrency is NORMAL and never a cliff** — measured, landed, and verified by
disk-truth acceptance reads.

Status: DESIGN 2026-07-29 · owner session 8891c11f · branch `gu-autonomy-dispatch` ·
row 5 of docs/plans/GROUND_UP_REBUILD_MAP.md · methodology: skills/ground-up/SKILL.md ·
exemplar: docs/plans/LAND_PIPELINE_V2.md

**Seams NOT owned here** (consume the contract, never redesign): fires execute through row 2
(session lifecycle — `handoff-fire.sh`); the operator surface is row 10 (`cc-blockers`,
`operator-readout.sh`); account/quota ranking is row 7 (`claude-accounts`, `model-config.yaml`).

---

## §1 First principles — why the old frame cannot work

The dispatcher's job is: given a backlog of N open items and a fleet that can run C workers
concurrently, decide what to work on next. The measured reality (§2) is **N = 121 open, C ≈ 4–8**.
N ≫ C is not an anomaly — it is the *steady state*, and the standing constraint says so.

The incumbent frame is: **on a timer, slice the first `MAX_SPAWN` items off the backlog, ask the
quota oracle to place that slice, and spawn.** Three consequences follow, all measured, none
fixable inside the frame:

**(a) Decision latency is O(backlog), not O(cadence).** The wave is `.[0:2]` of the FIFO-ordered
open list (`bin/cc-dispatch:199`) on a 900 s timer (`launchd/com.claude.dispatcher.plist:31-32`).
An item at queue position P therefore waits ⌈P/2⌉ × 15 min for *any* decision about it. At the
measured N = 121 the tail item waits **≈ 15.1 hours**. No tick-rate change fixes this: at a 60 s
tick the tail still waits ~1 hour, and the timer would spawn 2 workers/minute. The DoD's 5-minute
bound is **unreachable in this frame at any cadence**, because the frame has no way to *decide*
about an item without *spawning* it.

**(b) There is no concurrency ceiling, so the dispatcher manufactures its own cliff.**
`cc-dispatch` contains no live-worker count anywhere (grep: absent). `MAX_SPAWN` is a *per-tick*
cap, not a fleet cap; `cc-wave-plan`'s `CC_WAVE_MAX_PER_ACCT` is a *per-wave* cap that resets every
invocation, and the live session count `RLOAD` is only a tie-breaker in the placement minimisation
(`bin/cc-wave-plan:149-151`) — it never caps anything. So the dispatcher fires 2 workers every
15 min **unconditionally**: 192 spawns/day at full cadence. The measured run fired **50 sessions in
17.5 h (2.9/h sustained)** and then spent the next three hours emitting `quota-cliff` — the
accounts were exhausted *by those very fires*. The hourly histogram is a textbook exhaustion curve
(2–6 fires/h until 14:00, then 2/1/3 as quota trickled back). **The cliff is the dispatcher's own
exhaust.** This is the fail-closed-as-amplifier law with the sign flipped: *success* amplifies
until it walls.

**(c) A cliff verdict carries no evidence, so "false cliff" is not even measurable.** The record
written is `{action:"abstained", detail:"quota-cliff"}` — a bare string. Three structurally
different states collapse into it: (i) every account genuinely at its limit; (ii) accounts
*logged out* (an auth wall — `/limit-recover`, which the page recommends, does nothing for it);
(iii) the oracle failed or was unavailable — `load_ranks` reads `claude-accounts --rank general`
inside a process substitution with **no `timeout(1)` anywhere in either script** (grep: zero), so
a hang, a non-zero exit, or an unparseable stdout all yield an empty `RANKED` and hence
`cliff "no account has general headroom (rank empty)"` (`bin/cc-wave-plan:120`). **An unknown is
reported as a cliff.** Two of those three states are false cliffs by definition, and no disk read
can currently tell them apart.

### The falsified inheritance

The handed-down diagnosis — "a quota-cliff that never clears despite headroom is a wave-sizing
false cliff (backlog > concurrency), fixed by bef587a" — is **false as a root cause, and this
rebuild must not inherit it.** `bef587ac` ("bound wave to MAX_SPAWN so an oversized backlog stops
false-cliffing") landed **2026-07-18**. The 12 cliff abstentions occurred **2026-07-26**, eight
days later, at a 28.6 % abstention rate. Wave-sizing was a real bug and its fix is sound, but it
was not the cause of the observed cliffs. Re-derived from primary disk truth per the skill's
Phase 1 rule; the memory entry `dispatch-false-cliff-wave-sizing.md` is corrected by this section.

### The inversion

**Separate the DECISION from the SPAWN, and drive admission from CAPACITY rather than from a timer.**

- A **decision** is a pure read: for every open item, emit `admit | defer(reason, position) |
  block | skip`. It costs no quota, no session, no lock — so it can cover the *entire* backlog on
  every pass. Decision latency then equals pass cadence, independent of N. `defer` is a **real,
  recorded decision**, not a stall and not a cliff: it is precisely how "backlog > concurrency"
  is expressed. This makes the standing constraint a first-class output rather than an error.
- **Admission** is the only capacity-bound step: fire exactly `max(0, CEILING − live_workers)`
  items, where `CEILING` is a fleet concurrency ceiling set *below* the quota wall. A dispatcher
  that never exhausts quota never reaches a cliff — the cliff class is dissolved structurally
  rather than detected better.
- A **cliff** becomes a narrow, evidenced verdict reachable only when an admission attempt with
  free slots finds zero placeable capacity, and it must carry the headroom evidence that justifies
  it. Unknown ≠ cliff (R6). Auth-wall ≠ quota-wall (R6).
- **Kick on write, poll as backstop** (the exemplar's postland shape): `cc-backlog add` kicks a
  debounced decision pass, so latency is seconds; the timer only guarantees liveness. This is what
  buys the 5-minute bound with margin rather than by cadence-tuning.

If the new design were the old one with a shorter interval and a bigger `MAX_SPAWN`, it would be a
Phase-1 failure. It is not: the timer stops being the decision trigger, and capacity — not the
clock — gates the spawn.

### Requirements (goal + invariants that SURVIVE the redesign)

| # | Requirement | Provenance |
|---|---|---|
| R1 | Every open item receives a recorded decision within 5 min of its add, at any backlog depth. | DoD |
| R2 | `backlog > concurrency` yields `deferred` decisions with position + reason — never `abstained`, never a page. | standing constraint |
| R3 | A `cliff` verdict is emitted only with machine-readable headroom evidence attached; a cliff without evidence is a defect. | §1(c) |
| R4 | The three wall states — `capped` (quota), `auth` (logged out), `unknown` (oracle failed/absent) — are distinct verdicts with distinct operator actions. A non-verdict is never a cliff. | memory `named-failure-vs-no-verdict`, `gate-never-ran-vs-gate-red` |
| R5 | Fleet-wide live-worker concurrency has an explicit ceiling enforced at admission; the dispatcher can never be the cause of quota exhaustion. | §1(b) |
| R6 | Every external oracle call is bounded by absolute-path `timeout(1)`; a bound covers the failure mode it bounds (connect + rpc, whole process group). | memory `bounding-external-calls`; zero bounds exist today |
| R7 | Fail-closed never amplifies: shedding load = defer (cheap, no spawn), never wait-then-spawn-anyway. | memory `fail-closed-degradation-as-amplifier` |
| R8 | Absence is loud WITH existence evidence: an inert dispatcher (disabled/never-run) must raise an operator-visible alarm, gated on the job being *supposed* to run. | memory `feature-durability-mechanism-not-memory`, `absence-alarm-needs-existence-evidence` |
| R9 | Passes are singleton and skip-not-queue, pinned by pid+lstart; a pass that outruns its interval must never self-overlap. | memory `periodic-job-self-overlap` |
| R10 | No head-of-line blocking: a repeatedly-failing item at the queue head cannot starve the rest (the existing `reap` thrash-block is the floor, not the ceiling). | §1(a) + `bin/cc-backlog:52-62` |
| R11 | Existing ledger invariants are kept verbatim: append-only fold, done-latch, blocked-excluded-from-wave, reopen guards, liveness-oracle reap, abstention ≠ death. | `bin/cc-backlog:25-84` — these survive the redesign untouched |
| R12 | Every new mechanism ships with an env kill switch; never revert-as-plan. | global CLAUDE.md |

---

## §2 Measured constants this design is built against

Every row re-derived from primary disk truth on 2026-07-29 by this session (skill Phase 1: a
handed-down count is a CLAIM). Commands are reproducible as written.

| Constant | Value | Source |
|---|---|---|
| Open backlog depth | **121 open**, 29 blocked, 519 done | `cc-backlog list --all --json \| jq 'group_by(.status)'` |
| Ledger size | 669 distinct items / 1,911 append-only records | `jq -rs '[.[].id]\|unique\|length'`; `wc -l ~/.claude/autonomy/backlog.jsonl` |
| Open by project | claude-infrastructure 126*, reso-management-app 10, doc_classifier 9, `/` 5 | `cc-backlog list --open --json \| group_by(.project)` (*`--open` includes blocked; `/` = residue of the un-normalised-path bug, `cc-dispatch:60-63`) |
| Dispatcher cadence | `StartInterval` **900 s**, `RunAtLoad false` | `launchd/com.claude.dispatcher.plist:31-35` |
| Discovery cadence | `StartInterval` **3600 s**, `RunAtLoad false` | `launchd/com.claude.discovery.plist` |
| **Dispatcher activation state** | **`=> disabled`** in the gui/501 override DB; absent from `launchctl list`; `/tmp/claude-dispatcher.*.log` **ABSENT** | `launchctl print-disabled gui/$(id -u)`; `launchctl list \| grep com.claude`; `ls /tmp/claude-dispatcher.*.log` |
| Discovery activation state | **`=> disabled`**, same three reads | same |
| Dispatch passes ever recorded | **42** `summary` records, **all** inside 2026-07-26T01:14:12Z–18:41:33Z (17.5 h); **zero in the ~3 days since** | `jq 'select(.actor=="cc-dispatch")' ~/.claude/autonomy/idl.jsonl` |
| Observed live cadence in that window | ~900 s between passes (14:45:01, 15:00:18, 15:15:26, 15:30:32 …) | idl.jsonl — confirms the job *was* loaded on 07-26 then went inert |
| Fires | **50** | idl `action=="fired"` |
| Abstentions | **12** (= **28.6 %** of 42 passes), all `detail:"quota-cliff"`, clustered 14:45–17:42 | idl `action=="abstained"` |
| Failures | 10 | idl `action=="failed"` |
| Sustained spawn rate | **2.9 fires/h** over 17.5 h; 2–6/h hourly peak | idl hourly histogram |
| Theoretical spawn rate at full cadence | **192/day** (2 × 96 ticks) | `cc-dispatch:57` + plist:31 |
| Per-tick spawn cap | `CC_DISPATCH_MAX_SPAWN` = **2** | `bin/cc-dispatch:57` |
| Per-wave per-account cap | `CC_WAVE_MAX_PER_ACCT` = **2**; wave capacity = \|RANKED\| × 2 = **8** today | `bin/cc-wave-plan:41,149` |
| **Fleet concurrency ceiling** | **NONE — the constant does not exist** | grep of `bin/cc-dispatch`: no live-worker term |
| Accounts ranked healthy (2026-07-29) | **4** (next3, next4, next, next2); call took 2 s | `claude-accounts --rank general` |
| **`timeout(1)` in the dispatch path** | **ZERO** | `grep -n timeout bin/cc-wave-plan bin/cc-dispatch` |
| Wave slice | `.[0:MAX_SPAWN]`, FIFO by ledger order | `bin/cc-dispatch:199` |
| **Decision latency, item at position P** | ⌈P/2⌉ × 15 min ⇒ **≈ 15.1 h** at P = 121 | derived from `cc-dispatch:199` + plist:31 |
| False-cliff fix vs observed cliffs | fix `bef587ac` **2026-07-18**; cliffs **2026-07-26** (8 days later) | `git log --format='%h %ad' bef587ac`; idl |
| Discovery critics | 4 (C1 frontier-hole, C2 plan-open, C3 wiring-inert, C4 gate-red), idempotent event-keyed adds | `bin/cc-discover:12-17` |

**The two headline reads.** (1) The subsystem is **inert**: both launchd jobs are `disabled`, have
no log files, and have recorded no decision for ~3 days — so the DoD's 5-minute bound is currently
met **zero percent of the time**, because no automated decision exists at all. (2) In the one
window it *did* run, it exhausted the fleet's quota in 17.5 h and spent the tail of that window
paging about the wall it had walked into.

---

## §3 Architecture — the decision/admission split

```
cc-backlog add ──kick(debounced)──┐
                                  ▼
launchd timer (backstop) ───► cc-dispatch --decide          [PURE READ, whole backlog]
                                  │   for each open item → admit | defer(pos,reason) | block | skip
                                  │   → decision journal (append-only, one record per item per pass)
                                  ▼
                              admit set, truncated to free_slots = max(0, CEILING − live_workers)
                                  │
                                  ▼
                              cc-wave-plan  [BOUNDED oracle, trichotomous verdict]
                                  │   0 = placements · 4 = capped(+evidence) · 5 = auth · 6 = unknown
                                  ▼
                              claim → warm worktree → handoff-fire  (row 2 seam, unchanged)
```

**S1 — Decision pass covers the whole backlog, always.** Every open item gets a journal record
every pass. `defer` carries `{position, free_slots, reason:"capacity"}`. This is what makes R1
independent of N and R2 structural: at N = 121 and 6 free slots, the pass emits 6 `admit` and 115
`defer` records — and 115 deferrals is a *healthy* steady state, not an incident.

**S2 — Admission is capacity-driven.** `free_slots = max(0, CEILING − live_workers)`, with
`live_workers` read from the session registry (row 4's `cc-sessions`, cross-checked against
`claude-accounts --json .rows[].k`). `CEILING` (`CC_DISPATCH_CEILING`, default 6) sits below the
quota wall by construction, so the dispatcher cannot exhaust quota. `free_slots == 0` ⇒ every item
defers with `reason:"at-ceiling"` — **no oracle call, no page, no cliff**. This alone removes the
entire measured abstention population.

**S3 — Trichotomous, evidenced wall verdicts.** `cc-wave-plan` gains distinct exits: `4 = capped`
(every account at its quota limit — evidence: per-account limit state), `5 = auth` (≥1 account
logged out and none healthy — action is `/relogin`, not `/limit-recover`), `6 = unknown` (oracle
timed out, exited non-zero, or emitted unparseable output — action: retry next pass, **never a
page, never a cliff**). Every non-zero carries a JSON evidence blob onto the journal record. R3/R4.

**S4 — Bounded oracle.** Every `claude-accounts` / `cc-route` invocation wrapped in absolute-path
`timeout(1)` (`CC_DISPATCH_ORACLE_TIMEOUT_S`, default 20). Timeout ⇒ verdict `unknown` (S3), never
`capped`. R6.

**S5 — Kick on write.** `cc-backlog add` invokes a debounced kick (`CC_BACKLOG_KICK`, default on)
that runs one decision pass. Debounce window `CC_DISPATCH_KICK_DEBOUNCE_S` (default 30) collapses
a discovery burst of 20 adds into one pass. Timer cadence drops 900 s → 300 s as the *backstop*, so
R1 holds even with the kick disabled. Kick failure is silent-and-harmless: the backstop covers it.

**S6 — Singleton, skip-not-queue.** One decision pass at a time, lock pinned by pid+lstart
(`kill -0` wedges on a recycled pid — memory `periodic-job-self-overlap`). A pass that finds the
lock held **skips** and records `{action:"skipped",reason:"pass-in-flight"}` — it never queues.
R9.

**S7 — Fair ordering, no head-of-line block.** The admit set is chosen by an explicit priority key
(age, then blocked-status, then thrash-count ascending) rather than raw FIFO slice, so an item that
repeatedly fails to spawn sinks instead of starving the queue. The existing `reap` thrash-block
(`cc-backlog:52-62`) remains the terminal guard. R10.

**S8 — Inert-alarm with existence evidence.** A check surfaces "dispatcher has recorded no decision
in > `CC_DISPATCH_STALE_H` (default 2 h)" **only when the job is supposed to be running** — i.e.
gated on the label being enabled+loaded. Disabled-and-unloaded is reported as `not-activated`
(an operator queue item), never as a stall. R8, and it is the mechanism that would have caught the
measured 3-day inertness on day one.

---

## §4 Seam contracts (consumed, never redesigned)

| Seam | Owner row | Contract consumed | Breakage risk |
|---|---|---|---|
| Fire execution | 2 | `handoff-fire.sh <argv…>`; non-zero ⇒ reopen the claim. `fire_line` passed verbatim as argv (no eval). Warm worktree provisioned by the actuator before firing (cold `--worktree` races the auto-submit keystroke). | `cc-dispatch:230-312`; the argv-array/string duality at :242-255 is a *dispatch-side* adaptation to wave-plan's emission, not a row-2 contract |
| Operator surface | 10 | Pages dropped as `$PAGES_DIR/*.page` (line 1 = epoch, line 2 = human); `cc-blockers` renders blocked items + pending activations. | `cc-dispatch:129-137`. V2 adds *fewer* pages, never new formats |
| Account/quota ranking | 7 | `claude-accounts --rank general` (ranked names) and `--json` (`.window.deadline`, `.rows[].k`); `cc-route <slot> --json`. SSOT `~/.claude/model-config.yaml` — never grep/hardcode the window. | `cc-wave-plan:20-26`. V2 adds a *bound* around these calls; the parse contract is unchanged |
| Session registry | 4 | `cc-sessions` liveness for `live_workers` and for `claimer_live`. | `cc-backlog:405-423` reap oracles — reused verbatim |

---

## §5 Failure-mode table — every observed mode → its structural answer

A mode without an answer is an unfinished design.

| # | Observed mode | Evidence | Structural answer |
|---|---|---|---|
| F1 | Tail item waits ~15 h for any decision | `cc-dispatch:199` + plist:31, N=121 | S1 decision pass covers the whole backlog; latency = cadence, not O(N) |
| F2 | Dispatcher exhausts quota then pages about it (12 cliffs / 42 passes) | idl 14:45–17:42; 50 fires/17.5 h | S2 capacity ceiling below the quota wall — exhaustion is unreachable |
| F3 | `backlog > concurrency` read as a cliff | `cc-wave-plan:257` "wave exceeds capacity"; memory bef587a | S1/S2 `defer` is the recorded decision for surplus; only a *free-slot* attempt can wall |
| F4 | Oracle failure/hang reported as quota cliff | `cc-wave-plan:113-120`, no `timeout` anywhere | S3 `unknown` verdict + S4 bound; unknown never pages |
| F5 | Logged-out accounts reported as quota cliff (wrong operator action) | `--rank general` empties on auth loss; page says `/limit-recover` | S3 `auth` verdict routes to `/relogin` |
| F6 | Cliff record carries no evidence ⇒ false cliffs unmeasurable | `idl` `{action:"abstained",detail:"quota-cliff"}` | S3 evidence blob on every wall verdict — the acceptance read in §7 depends on it |
| F7 | Both launchd jobs `disabled`, never run, zero alarm, 3 days | `launchctl print-disabled`; logs absent; idl gap | S8 inert-alarm gated on existence evidence; §6 activation staged with `launchctl enable` first |
| F8 | Unbounded external call can hang a pass past its own interval | no `timeout(1)`; `StartInterval` 900 s | S4 bound + S6 singleton skip-not-queue |
| F9 | Overlapping passes double-claim | no lock in `cc-dispatch` | S6 singleton pinned by pid+lstart |
| F10 | Head-of-line item starves the queue | `.[0:2]` FIFO slice | S7 priority key with thrash-count demotion |
| F11 | Un-normalised project path matches nothing ("backlog empty" forever) | `cc-dispatch:60-63`; residue: 5 items under project `/` | Kept fix (basename normalisation) + §7 acceptance read asserting no `/`-project item is silently unreachable |
| F12 | Completed work re-dispatched by a reopen | incident 2026-07-20 a60d62a215f1→6488617 | Kept verbatim: `wasDone` done-latch (`cc-dispatch:166`), reopen guards (`cc-backlog:25-42`) |
| F13 | Dead worker strands a claim; thrashing item re-cycles the wave | `cc-backlog:52-84` | Kept verbatim: `reap` liveness oracles, abstention ≠ death, thrash-block |
| F14 | Operator-gated item re-dispatched in a loop | `cc-backlog:45-50` | Kept verbatim: `blocked` folds distinctly and is excluded from the wave |
| F15 | Discovery refills a queue nothing drains | discovery 3600 s vs 121 undrained open items | S1 makes the depth *visible as deferrals*; discovery stays idempotent + event-keyed (`cc-discover:12-17`) so supply never duplicates |

---

## §6 Kill switches (every new mechanism, never revert-as-plan)

| Switch | Default | Effect when set |
|---|---|---|
| `CC_DISPATCH_CEILING` | 6 | Fleet concurrency ceiling. `0` ⇒ admit nothing (decisions still recorded — a pure-observation mode) |
| `CC_DISPATCH_KICK` / `CC_BACKLOG_KICK` | on | `off` ⇒ no add-time kick; timer backstop only (reverts to poll-only behaviour) |
| `CC_DISPATCH_KICK_DEBOUNCE_S` | 30 | Collapse window for add bursts |
| `CC_DISPATCH_ORACLE_TIMEOUT_S` | 20 | Bound on every accounts/route call; `unknown` on expiry |
| `CC_DISPATCH_DECIDE_ONLY` | off | `on` ⇒ decisions journalled, **zero spawns** (the safe activation lane) |
| `CC_DISPATCH_STALE_H` | 2 | Inert-alarm horizon |
| `CC_DISPATCH_LANE` | v2 | `v1` ⇒ the incumbent timer/slice path verbatim (the whole-rebuild kill switch) |

Existing switches unchanged and still in play: `SHIP_LAND_LANE=v1`, `POSTLAND_STALL_S=0`,
`POSTLAND_AUTOREVERT=off`.

---

## §7 Acceptance criteria — as disk-truth reads

Each row names the **file or log that proves it**. Narration is not evidence.

| # | Claim | Disk-truth read | Pass condition |
|---|---|---|---|
| A1 | Every open item gets a decision each pass | `jq 'select(.actor=="cc-dispatch" and .action=="decision")' ~/.claude/autonomy/idl.jsonl \| jq -s 'group_by(.pass)[-1] \| length'` | == open-item count from `cc-backlog list --open --json` (blocked excluded) |
| A2 | Decision within 5 min of add | join `cc-backlog` add `ts` to the first decision record for that id; report p50/p99/max | **max < 300 s** over the observation window |
| A3 | Surplus is deferred, never abstained | same journal, `select(.verdict=="defer")` present **and** `select(.action=="abstained")` count | deferrals > 0 while abstentions == 0 at N > ceiling |
| A4 | Zero false cliffs | every `verdict=="capped"` record carries `evidence` with per-account limit state | 0 records where `verdict=="capped"` and evidence shows any account healthy; 0 where `verdict=="capped"` and the oracle rc was non-zero |
| A5 | Unknown ≠ cliff | `select(.verdict=="unknown")` | such records exist under a stubbed oracle failure and are accompanied by **no** `.page` file |
| A6 | Auth ≠ quota | `select(.verdict=="auth")` | routes to `/relogin` in its `action` field; no `quota-cliff` page written |
| A7 | Ceiling enforced | `select(.action=="fired")` count in any window vs concurrent `live_workers` | live workers never exceed `CC_DISPATCH_CEILING` |
| A8 | Oracle bounded | `grep -n 'timeout ' bin/cc-dispatch bin/cc-wave-plan` | every `claude-accounts`/`cc-route` call site is wrapped; count of unwrapped call sites == 0 |
| A9 | Singleton holds | two concurrent `--decide` passes | second records `{action:"skipped",reason:"pass-in-flight"}`; exactly one journal pass appears |
| A10 | Inert-alarm fires only with existence evidence | disable the label → check alarm text; enable+stop writing → check alarm text | disabled ⇒ `not-activated`; enabled+stale ⇒ `stalled`; never the reverse |
| A11 | Activation is real | `launchctl print gui/$(id -u)/com.claude.dispatcher`; `/tmp/claude-dispatcher.stdout.log` | label loaded, **not** in `print-disabled`, log file **exists and is non-empty** |
| A12 | Ledger invariants intact | `bin/cc-backlog` selftest + `cc-dispatch` selftest | all pre-existing assertions still pass (F12–F14 kept verbatim) |

**Observation window for A2/A3/A4/A7:** the first 2 h after activation, read from
`~/.claude/autonomy/idl.jsonl`. These are **ACCRUING** criteria — the design is provable at build
time against fixtures, and the live numbers accrue post-activation (§9).

---

## §8 Rejected alternatives (so they are not relitigated)

| Rejected | Why |
|---|---|
| **Shorten `StartInterval` to 300 s and raise `MAX_SPAWN`** | The old design with bigger constants — the Phase-1 failure signature. Latency stays O(N) (tail item still ~5 h at N=121) and a bigger `MAX_SPAWN` *accelerates* quota exhaustion (F2). Fixes neither DoD clause. |
| **Retry the wave at a smaller size on cliff (degrade 2 → 1)** | Treats the symptom. `cc-wave-plan`'s "never a blind partial" contract is *correct*; the bug is that a surplus ever reaches the oracle. S1/S2 keep surplus out of the oracle entirely. Also adds oracle calls on the exact path that is already unbounded (F8). |
| **Cap by parsing quota % and firing while headroom > X %** | Couples dispatch to row 7's internal quota semantics (a seam we consume, not own) and re-introduces the loose-parse failure the SSOT discipline exists to prevent (memory `frontier-window-ssot-discipline`). Live-worker count is the honest control variable. |
| **`fswatch`/FSEvents on the backlog file instead of a kick in `add`** | A second daemon to keep alive, with its own inertness failure mode (F7), to observe a write we already control. The writer kicking is strictly simpler and fails safe to the timer. |
| **Queue the pass instead of skip-not-queue** | Queued passes under a slow oracle produce the self-overlap pathology (memory `periodic-job-self-overlap`, 5-concurrent sweeps). A skipped pass loses nothing: the next pass recomputes from the ledger fold, which is idempotent. |
| **Drop `cc-wave-plan` and place inline in `cc-dispatch`** | Row 7's routing (Fable straddle guard, per-slot model/effort, SSOT parse) is real, tested, and not ours to absorb. V2 keeps the seam and adds only the bound + verdict trichotomy. |
| **Auto-activate the launchd jobs from the agent** | Classifier-terminal (C10) and correctly so — autonomous "Claude kicks off Claude" begins only on a deliberate operator step. V2 stages the exact command instead (§9). |
| **Let a cliff auto-`/limit-recover`** | A cliff that auto-remediates hides F2 (the dispatcher causing its own wall) and would have masked the entire measured incident. The ceiling removes the wall; the page stays operator-owned. |
| **Delete the 121 open items / triage the backlog as part of this rebuild** | Backlog *content* is not this subsystem's responsibility; N ≫ C is the standing constraint the design must serve, not a mess to clean. Deferrals make depth visible without touching content. |

---

## §9 Activation (operator-owned, C10) and closing buckets

Both labels are currently `disabled` **and** unloaded (§2). Activation must `launchctl enable`
*before* `bootstrap` — a bootstrap alone against a disabled label fails silently (the landing
rebuild's measured deploy-layer finding). The staged scripts and their SSOT parity live in
`docs/activation/pending-activation/` (repo SSOT) mirrored to
`~/.claude/autonomy/pending-activation/` (operator queue); `02-load-dispatcher-activate.sh` and
`03-load-discovery-activate.sh` already exist there and are **content-drifted** (SessionStart
parity report) — reconciling them is part of this rebuild's activation work.

Recommended first activation runs with `CC_DISPATCH_DECIDE_ONLY=on`: the decision journal accrues
(proving A1–A3, A5, A9) with **zero spawns**, then the switch flips.

---

## Phase 0 — Agent Team Orchestration

Three teammates, disjoint file ownership. Seams between them are the three contracts frozen above
(§3 verdict vocabulary · §4 seam table · §6 switch names) — cite by section, never renegotiate.

| Teammate | Deliverable | Owns (exclusive) | Branch |
|---|---|---|---|
| `gu5-decide` | S1/S2/S6/S7 — decision/admission split, ceiling, singleton, fair ordering in `cc-dispatch` | `bin/cc-dispatch`, `tests/cc-dispatch-v2.bats` | `gu5/decide` |
| `gu5-verdict` | S3/S4 — trichotomous evidenced verdicts + bounded oracle in `cc-wave-plan` | `bin/cc-wave-plan`, `tests/cc-wave-plan-verdict.bats` | `gu5/verdict` |
| `gu5-cadence` | S5/S8 — add-time kick, 300 s backstop, inert-alarm, activation SSOT reconcile | `bin/cc-backlog` (kick hook only), `launchd/com.claude.{dispatcher,discovery}.plist`, `docs/activation/pending-activation/0{2,3}-*.sh`, `tests/dispatch-cadence.bats` | `gu5/cadence` |

Lead (this session): this plan, checkpoint review against §7, merge order smallest-diff-first
rebase+ff-only serialized, land via project-local `/ship` continuously.

**Checkpoint-review criteria (lead, at each Phase A ack) — written BEFORE spawning:**
1. `gu5-decide`: decision journal covers **every** open item per pass (A1) with a discriminating
   fixture at N > ceiling; `free_slots==0` path makes **zero** oracle calls and writes **zero**
   pages (A3); singleton proven by two concurrent passes (A9), lock pinned by pid+lstart not bare
   pid; `wasDone` done-latch, `blocked` exclusion and reopen self-release preserved verbatim (A12).
2. `gu5-verdict`: `capped`/`auth`/`unknown` are distinct exits with evidence attached (A4–A6);
   a stubbed oracle **timeout** yields `unknown`, never `capped` — positive control alongside;
   every accounts/route call site wrapped in absolute-path `timeout(1)`, unwrapped count 0 (A8).
3. `gu5-cadence`: kick is debounced and its failure is harmless (timer backstop proven with the
   kick stubbed to fail); inert-alarm distinguishes `not-activated` from `stalled` with a positive
   control for each (A10); activation script `launchctl enable` **before** `bootstrap`, and the
   script is never executed by the tests.
4. All: RED-proof every new test against the pristine pre-change tree recovered via `git archive`
   (never a hand-edited approximation); a positive control beside every absence assertion;
   `|| false` on non-final `[[ ]]` in bats; re-run launchd-bound artifacts under `/bin/bash`
   (the Bash tool runs zsh, so repros lie); shellcheck + own-suite green before ack.

**Checkpoint log:** (appended as acks land — never delete entries)

---

## Learnings (accumulate; never delete)

- **2026-07-29 — the inherited root cause was wrong.** "backlog > concurrency false cliff, fixed by
  bef587a" does not survive re-derivation: the fix landed 2026-07-18, the 12 cliffs occurred
  2026-07-26. The real cause is an unbounded spawn rate with no fleet concurrency ceiling —
  the dispatcher walked into a wall it built. Corrects memory `dispatch-false-cliff-wave-sizing`.
- **2026-07-29 — the subsystem was inert, silently, for ~3 days.** Both launchd labels sit
  `disabled` with no log files and no IDL records since 2026-07-26T18:41:33Z. A built-but-inert
  spine raises no alarm today; S8 is the mechanism that makes inertness loud (memory
  `feature-durability-mechanism-not-memory`).
- **2026-07-29 — an un-evidenced verdict makes its own defect unmeasurable.** Because
  `{action:"abstained",detail:"quota-cliff"}` carries no headroom evidence, "zero false cliffs"
  could not be *measured* at all before this rebuild — the acceptance criterion had to create its
  own evidence (A4). Design rule: a verdict that gates an alarm must carry the evidence that
  falsifies it.
