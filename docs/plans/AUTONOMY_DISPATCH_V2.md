---
status: in-progress
---

# AUTONOMY DISPATCH V2 — first-principles rebuild of dispatch & discovery

**Scope (frozen):** the autonomy dispatch & discovery subsystem achieves a dispatch decision
within 5 minutes of a backlog-add and ZERO false cliffs, under the standing constraint that
**backlog > concurrency is NORMAL and never a cliff** — measured, landed, and verified by
disk-truth acceptance reads.

Status: **BUILT + LANDED + LIVE-VERIFIED** (2026-07-31) — S1–S8 on trunk, both labels activated by
the operator 2026-07-30, 14/14 acceptance criteria PASS (§10). **A2 closed 2026-07-31** (`9dfaac64`,
item `de5e3e24be8f`): the singleton gated DECISION as well as admission, so a kick arriving during a
414–833 s spawn tail produced no verdict at all; the lock now gates admission only, RED-proved
against two pinned pre-change artifacts. Its live re-measurement over a fresh 10 h journal window is
the remaining read. Open: the §9 activation-SSOT drift. Design 2026-07-29 · owner session 8891c11f ·
branch `gu-autonomy-dispatch` ·
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
| R11 | Existing ledger invariants are kept verbatim: append-only fold, done-latch, blocked-excluded-from-wave, reopen guards, liveness-oracle reap, abstention ≠ death. | `bin/cc-backlog:25-84` — these survive the redesign untouched. **Correction 2026-07-30 (backlog 9efae9e3cfc1):** "abstention ≠ death" held for oracle 1 (the claimer registry) and NOT for oracle 2 (worktree occupancy), which returned a bare "no evidence" whether it had asked or merely failed to run — so a starved lsof read as a dead worker and reopened it. Since a dispatched claim's `by` is the dispatcher's spent pid, oracle 1 always returns a *real* not-live verdict and oracle 2 is the only one that speaks for the worker: the half that was missing was the load-bearing half. Both oracles are three-valued now; TOTAL starvation fails toward KEEP, bounded by `UNRESOLVED_MAX_S` and then BLOCKED, never reopened. |
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
`CEILING` (`CC_DISPATCH_CEILING`, default 6) sitting below the quota wall by construction, so the
dispatcher cannot exhaust quota. `free_slots == 0` ⇒ every item defers with `reason:"at-ceiling"` —
**no oracle call, no page, no cliff**. This alone removes the entire measured abstention population.

**`live_workers` is the ledger's `claimed` count — NOT a live-session count.** This distinction is
load-bearing and was corrected mid-build after the first spec got it wrong; recording the error
because it is the more instructive artifact:

> The initial spec read `live_workers` from `claude-accounts --json .rows[].k`. Measured live, that
> field totals **12** — it counts every session on each account (the lead, the desk pane, operator
> panes, this rebuild's own teammates, sibling rebuild sessions), not the workers dispatch has
> outstanding. With `CEILING=6` it yields `free_slots = max(0, 6−12) = 0` **permanently**: a
> dispatcher that defers 100 % of items forever and never fires once — and because deferrals
> deliberately never page (R2), it would do so **silently**. That is strictly worse than the false
> cliff this rebuild exists to remove: a false cliff at least pages.

The correct control variable is the count of items whose folded status is `claimed` — by definition
"how many workers dispatch currently has out" (measured now: **0**, against 12 live sessions — the
two numbers are not even close, which is what makes the error consequential rather than cosmetic).
Three properties follow, and they are why this is not merely a bug-fix but the better design:
- **No oracle is consulted for the ceiling at all** — so there is no timeout, no `unknown` state,
  and no degradation path to get wrong. The ledger read is already in hand at step 1.
- **It self-heals.** A claim whose worker died is reopened by the existing `reap` liveness oracles
  (`cc-backlog:52-84`), so the ceiling cannot wedge at a stale count. Dispatch does not implement
  its own liveness probe — `reap` owns that, and duplicating it would reintroduce the false-dead
  verdict that spawns duplicate peers (F12).
- **It is the honest unit.** The ceiling is about dispatch's own outstanding work; charging it for
  the operator's panes would let unrelated human activity silently throttle autonomy.

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

### §4.1 Ownership rulings (coordinator-decided 2026-07-29 — binding, do not relitigate)

Two surfaces were named in NO map row. Row 5 pinged the coordinator rather than claiming them
silently; the rulings landed in `GROUND_UP_REBUILD_MAP.md` § "Unowned-surface rulings" and are
mirrored here because this rebuild acts on them:

- **`bin/cc-wave-plan` → row 5 (ours).** Deciding test is the map's MECE basis — *who answers when
  it breaks* — not who calls it. Its sole **executable** consumer is `bin/cc-dispatch:200`;
  `cc-backlog`'s mentions (`:464`, `:535-536`) are comments describing the `wt-<id>` convention,
  not calls. A false ⛔ cliff is a dispatch failure, i.e. row 5's standing constraint verbatim.
  Method note worth keeping: rule by executable call sites, never by a comment asserting ownership
  (a comment is text, not evidence), and never with an extension filter on the grep — this repo's
  `bin/` is extensionless, so `--include='*.sh'` hides the very consumers that decide the question.
- **`bin/cc-route` → row 7 (NOT ours).** It parses `~/.claude/model-config.yaml` (row 7's named
  SSOT) and its exit contract (0 plan · 2 usage · 3 blind/no-data · 4 cliff) is pinned by
  `scripts/route-safety-gate.sh:33-50` + `tests/cc-route.bats`. V2 may **wrap its invocation** in
  `timeout(1)` from inside cc-wave-plan — that changes cc-wave-plan, not cc-route — but may not
  change what it returns or how it is parsed. A cc-route rc=4 remains a GENUINE `capped` verdict.

**A test can encode a falsified premise; changing it is legitimate, hiding it is not.**
`tests/cc-wave-plan.bats:135` asserts "wave exceeds total concurrency → exit 4 cliff" — the exact
belief §1 disproved. V2 changes it deliberately and RED-proofed, with the reason recorded here:
wave-oversize is no longer a cliff at all, because surplus never reaches the oracle (S1/S2). Its
neighbour `:141` (a cc-route-propagated quota cliff) is a genuine cliff and MUST remain
distinguishable — after the change those two tests assert **different** verdicts. Telling a real
capped-account stop apart from a wave-sizing false cliff is the whole point of the split.

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
| F12a | **Completed work re-dispatched by a RACE, not a reopen** — F12's remedy is PULL-TIME ONLY. The `wasDone` filter reads a snapshot at step 1 and the claim is taken at step 5a, with the 7-45 s wave-plan plus the admission tail (`warm_worktree` + `handoff-fire`) in between. A `done` landing inside that gap is invisible to the snapshot, so the claim fires against stale truth. | Measured live 2026-08-05, item `5690b9d11bee`: ledger records `event:"done"` at 20:20:52Z and `event:"claim"` at 20:26:15Z on the same id — 5 m 23 s later — and the spawned worker burned a whole session re-verifying landed work. Backlog `dadc3c2410aa`. | **The ACTUATOR is the arbiter**: `cc-backlog claim` refuses a `wasDone` item outright (rc 4, `--force` override), mirroring the reopen terminal-guard `8549338`. A second pull-time re-check was rejected — it narrows the read→append window, never closes it, and leaves every other caller of `claim` unguarded. `cc-dispatch:5a` branches on rc 4 and records a **skip**, not a failure (a raced landing is not a dispatcher fault); the step-1b filter stays as the cheap fence that keeps a latched item out of the wave-plan call and the quota placement entirely. Live paired control: pre-fix tree claims + spawns on the raced item, fixed tree claims 0 / spawns 0 / skipped 1. |
| F13 | Dead worker strands a claim; thrashing item re-cycles the wave | `cc-backlog:52-84` | Kept verbatim: `reap` liveness oracles, abstention ≠ death, thrash-block |
| F14 | Operator-gated item re-dispatched in a loop | `cc-backlog:45-50` | Kept verbatim: `blocked` folds distinctly and is excluded from the wave |
| F15 | Discovery refills a queue nothing drains | discovery 3600 s vs 121 undrained open items | S1 makes the depth *visible as deferrals*; discovery stays idempotent + event-keyed (`cc-discover:12-17`) so supply never duplicates |
| F16 | **Ceiling wedges at a stale count ⇒ permanent SILENT deferral** — the failure mode S2's own correction revealed. Deferrals never page (R2, deliberately), so a `live_workers` that never decreases produces a dispatcher that fires nothing and says nothing. | Near-miss this session: the first S2 spec would have wedged at `free_slots=0` from day one (12 sessions vs ceiling 6) | Ceiling reads the `claimed` fold, which `reap` heals (`cc-backlog:52-84`) — plus **A13**: alarm when `free_slots==0` persists past `CC_DISPATCH_SATURATED_H`. R2 says surplus must not page; it does NOT say saturation may be invisible. The two are different claims and only the second is an alarm. |

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
| A12 | Ledger invariants intact | ~~`bin/cc-backlog` selftest~~ + `cc-dispatch` selftest — **corrected 2026-07-31: `cc-backlog` has no selftest and never has** (`cc-backlog selftest` ⇒ rc 2 `unknown verb`; zero occurrences of the string in the source or `--help`). The real ledger oracle is `tests/cc-backlog.bats` (79) + `tests/cc-backlog-compact-race.bats` (5). | all pre-existing assertions still pass (F12–F14 kept verbatim) |
| A13 | Saturation is visible (F16) | `jq 'select(.action=="decision" and .reason=="at-ceiling")'` grouped by pass — is there a pass in the last `CC_DISPATCH_SATURATED_H` (default 6) with **any** `admit`? | if every pass in the window is 100 % `at-ceiling`, an alarm row exists. Deferral is silent by design; *sustained total* deferral is not |
| A14 | Ceiling counts the right thing | `cc-backlog list --all --json \| jq '[.[]\|select(.status=="claimed")]\|length'` vs the `live_workers` recorded on decision records | the two agree; and neither equals `claude-accounts .rows[].k` unless coincidental (guards the corrected S2 from silently regressing) |

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

**⚠️ Activation is NOT this rebuild's call to make, and the reason is new evidence.** Verified
independently this session (`launchctl print-disabled gui/$(id -u)`): **12 of the 14 `com.claude.*`
labels are disabled** — only `com.claude.postland-verify` and `com.claude.deploy-live` are enabled,
and `launchctl list` shows those two alone loaded. That is a *fleet-wide* pattern, not a
dispatcher-specific oversight, so the premise "the dispatcher is inert by accident and should be
switched on" is **unproven**. Whether the mass-disable was deliberate (a reboot re-writing the
override DB, or an operator quieting the fleet) is an **OPEN operator question** — row 12 owns it.

Consequences for this rebuild, and they are deliberate:
- V2 is built, tested and landed to be **correct when activated**, and correct-and-silent while
  not. Nothing here activates anything.
- The `DISPATCH-NOT-ACTIVATED` alarm (S8) reports the disabled state as an **operator queue item,
  never a stall** — precisely so that a deliberate quiet fleet does not generate a false alarm,
  while an *accidental* inertness stops being invisible. This is why the alarm is gated on
  existence evidence rather than on the IDL gap alone.
- The acceptance reader reports A11 as **NOT-RUN**, not FAIL, in this state (verified live) — an
  un-activated job is a non-verdict, not a failure.
- The DoD's live latency numbers (A2/A3/A7) are therefore **ACCRUING**, not provable this session.
  What *is* provable now, and is proven, is everything measurable from source and fixtures
  (A4/A5/A8/A9/A10/A12). §10 splits the close on exactly this line.

### §9.1 — UPDATE 2026-07-31: the premise above is spent, the operator activated both labels

Every claim in §9 was true when written and is now **historical**. Verified live this session:

| Read | 2026-07-29 (§9 as written) | 2026-07-31 (measured) |
|---|---|---|
| `launchctl print-disabled gui/$(id -u)` | `dispatcher`/`discovery` ⇒ **disabled** | both ⇒ **enabled** |
| `launchctl list` | absent | both **loaded** (pids 52966 / 36579) |
| installed dispatcher `StartInterval` | 900 (stale mirror) | **300** — the §3 S5 backstop |
| `/tmp/claude-dispatcher.*.log` | absent | present |

Activation happened **2026-07-30 ≈01:38–01:41** (live plist mtime + the `.done` markers). So the
open operator question §9 raised — was the fleet-wide mass-disable deliberate? — was answered by
the operator acting, not by this rebuild deciding. Nothing here activated anything, as designed.

**The ACCRUING criteria have now accrued**, and this section's own instruction is therefore
discharged: A2/A3/A7 are no longer "provable later", they are measured in §10 against the journal
window `2026-07-30T19:35:46Z → 2026-07-31T05:32:57Z` (~10 h). **Read that window, not the whole
file**: `idl.jsonl` rotated at `20260730T193526Z`, so the 12 abstentions §2 cites live in
`idl.jsonl.20260730T193526Z.gz` and a naive all-time grep on the live file reads 0 for the wrong
reason. A count is only a verdict once its denominator is named.

**One §9 side-claim is now falsified and is corrected here rather than deleted.** `bin/cc-blockers`
:139-144 justifies naming the REPO copy of `02-load-dispatcher-activate.sh` with "…which is why the
label is disabled today". The label is not disabled today. The *choice* remains correct — the live
mirror is still content-drifted and still bootstraps without enabling first, so handing the
operator the mirror would still reproduce the original failure — but the reason is now "the mirror
is stale", not "the mirror is why we are down". The activation SSOT drift (§9's third paragraph)
is therefore **still open**: repo and `~/.claude/autonomy/pending-activation/` disagree on
`02`/`03`, and the repo side is the correct one.

**CLOSED 2026-07-31.** The live mirror held **zero** occurrences of `enable` in either script
(repo: 8 each) — i.e. the operator's queue was handing over exactly the version that bootstraps a
label sitting in launchd's disabled DB and fails with a bare EIO naming neither cause nor cure.
Both were synced repo → live (`~/.claude/autonomy/pending-activation/`, prior copies preserved at
`/tmp/pending-activation-backup-20260731/`); `diff` is now empty for both, each still parses, and
each is still a no-op without `CONFIRM=1`. This is a **live-layer** sync, not a repo change: no
script was executed and nothing was activated — the repo SSOT was already correct and only the
mirror moved. §9's remaining scope is now empty; the only open item in this plan is A2.

---

## §10 The close — what is proven, what is measured, what remains

§9 promised this section would "split the close on exactly this line". It now can, because the
labels are live (§9.1). Every row is a read taken **2026-07-31** against the journal window
`2026-07-30T19:35:46Z → 2026-07-31T05:32:57Z`: 14,199 decision records over 154 distinct passes,
220 admits, 13,941 defers, 28 fires, 112 spawn-failures, **0 abstentions, 0 quota-cliffs**.

| # | Verdict | Evidence |
|---|---|---|
| A1 | **PASS** | 154 passes each journal the whole dispatchable set (~125–140 records/pass vs the live open count); latency is not O(N) — the decision phase over a full backlog costs 7–45 s |
| A2 | **PASS structurally — CLOSED `9dfaac64`** (was PARTIAL, the one DoD clause not met) | The measured miss: 18 in-window adds, p50 **8 s** (the S5 kick working as designed), but **3 exceeded 300 s** (338/515/714 s) — every one of them a pass that found the singleton held and returned without deciding. Cause and fix below; the lock now gates admission only, so no pass can be silenced by a concurrent one. The live re-measurement over a fresh window is the remaining read |
| A3 | **PASS** | 13,941 `defer` records with `position`+`reason` and **0 `abstained`** — surplus is a recorded decision, never an abstention |
| A4 | **PASS (structurally, and now live)** | 0 `capped` verdicts because 0 wall verdicts of any kind were reached; the entire measured abstention population of §2 is gone, exactly as S2 predicted |
| A5 | PASS | `tests/cc-wave-plan-verdict.bats` — a stubbed oracle timeout yields `unknown`, never `capped`, with no page |
| A6 | PASS | same suite — `auth` routes to `/relogin`, distinct from `capped`'s `/limit-recover` |
| A7 | **PASS** | every pass records `ceiling=6`; the at-ceiling path makes zero wave-plan calls. The dispatcher never exhausted quota in 10 h of continuous running — the §2 incident is structurally unreachable |
| A8 | PASS | zero unwrapped `claude-accounts`/`cc-route` call sites; `run_oracle` is the single bounded chokepoint |
| A9 | **PASS (live, not just fixtured)** | 21 real `{action:"skipped",reason:"pass-in-flight"}` records — S6 skip-not-queue observed under genuine contention, not only in a stub |
| A10 | PASS | `tests/dispatch-cadence.bats` — `NOT-ACTIVATED` vs `STALE` with a positive control each |
| A11 | **PASS** (was NOT-RUN) | label loaded, absent from `print-disabled`, log present. Note the messages land on **stderr**; `/tmp/claude-dispatcher.stdout.log` is legitimately 0 bytes, so an A11 read that requires a non-empty *stdout* log reports a false negative |
| A12 | PASS | selftest 113/113; cc-dispatch 12/12, -v2 15/15, -projects 18/18, cadence 23/23, dispatch-assert 21/21, cc-blockers 67/67 |
| A13 | **PASS — built this session** | was specified and never implemented: `CC_DISPATCH_SATURATED_H` existed **only in this document**, zero occurrences in `bin/`, `tests/`, `scripts/`. Now a third `dispatch-inert` state (`f56041ae`), correctly silent against the live journal (220 admits in-window) |
| A14 | PASS | ceiling reads the `claimed` fold (measured 5) and never `claude-accounts .rows[].k` — the corrected S2 has not regressed |

### The one gap, stated plainly — and CLOSED 2026-07-31 (`9dfaac64`)

**A2 was not met, and the reason was not what the design predicted.** The decision phase is fast —
7–45 s for ~135 items — so S1 does what it claimed. The miss came from the **singleton lock being
held across the SPAWN tail**: admission (wave-plan → claim → warm worktree → `handoff-fire`) takes
**414–833 s**, one lock covered both phases, so a kick arriving during a spawn was skipped (S6,
correctly) and its item waited for the next pass. Pass gaps reach **1073 s** (58 of 170 over 300 s),
which is why the 300 s launchd backstop could not hold its guarantee.

This contradicted S1's own premise — *"a decision is a pure read: it costs no quota, no session, no
lock"* — which the implementation violated by holding the decision lock through admission.

**The fix — narrow what the lock GATES, never what it PROTECTS.** A pass that loses the singleton no
longer returns at step 0. It runs the whole decision phase, journals a verdict for every
dispatchable item (`verdict:"defer"`, `reason:"pass-in-flight"`, `free_slots:0`,
`live_workers:null`), and returns before the first capacity-consuming act. Decision latency is back
to the pass cadence for **every** pass, contended or not, and A9's `{skipped, pass-in-flight}` record
is still written — now *alongside* the decisions rather than instead of them.

`live_workers:null` is deliberate, not an omission: `free_slots` is 0 because a lock is held, not
because the fleet is full, and a live count on that record would read as though the pass had
evaluated capacity and found none. `pass-in-flight` also outranks `at-ceiling` in the reason
precedence for a second reason — `cc-blockers`' SATURATED premise gate counts `reason=="at-ceiling"`
deferrals as evidence of real ceiling pressure, and these carry none.

**Why the ceiling cannot double-admit.** The invariant is enforced by the lock's *presence* over
[read `live_workers` … take claims], not by its *duration*, and that whole region is unreachable
without it: `admit_n` is forced to 0 before the journal is written, and the pass returns before
wave-plan, before claim and before spawn. The holder's path is byte-identical to before.

**Both obvious alternatives were rejected on evidence, and the plan's framing of the fix was wrong.**
This document (and the backlog item) said the split needed *"a separate admission lock or an atomic
claim-based ceiling"*. Neither is required, and one is unsafe:

- *"Release the lock before the spawn tail, keep the pull inside."* Unsafe twice over.
  `cc-backlog claim` has **no** already-claimed guard — `cmd_transition` appends the event from any
  status, deliberately — so two passes whose pulls straddle a claim both claim the same id: the
  2026-07-20 double-worker incident exactly. And `warm_worktree` runs `git -C <repo> worktree add`,
  which races `.git/config.lock` when two tails run concurrently (GH #34645/#48927). The tail
  genuinely needs serialising; only the *journal* needed freeing.
- *"A second, separate admission lock."* Buys nothing. The loser of an admission lock still has to
  decide lock-free to fix A2, and once it does, the first lock has no remaining job.

**RED-proved against two pinned real artifacts, never approximations** (`tests/cc-dispatch-v2.bats`,
memory `control-must-replay-the-real-artifact`): `bf796c57` (pre-S6) still double-claims the same id
under concurrency — the double-admission proof this change had to survive; and a second pinned
control `ec92e68c` (S6 held across the tail) decides **zero** items under an identical held-lock
fixture where the shipped tree decides all three. A second sha was needed because the v2 rebuild's
own control has no singleton at all, so it cannot testify about a defect *inside* the singleton.
Each zero-effect read has a positive control. Suites: selftest 121/121 · cc-dispatch 12/12 ·
-v2 16/16 · -projects 18/18 · cadence 23/23 · cc-blockers 67/67 · dispatch-acceptance 10/10.

**A2 is now met structurally; the live re-measurement is the operator's next window.** What is
proved is that no pass can be silenced by a concurrent one; what the next 10 h journal window will
show is the resulting max-latency figure against the 300 s bound.

### Also closed in the same session (`988f14a8`) — the acceptance reader's own selftest was RED

`dispatch-acceptance.sh selftest` had been exiting 1 (8 passed, **1 failed**), reproduced
byte-identically on `origin/main`, so it predates this work. Not a reader defect: the A2-scoping case
asserted *"an add for ANOTHER project must not be counted undecided — cc-dispatch never had it"*,
a premise multi-project coverage (`f7abcbdee98c`) retired. The producer now decides about every open
item, and an undeclared foreign one gets `{verdict:"skip", reason:"project-not-dispatched"}`. A1's
denominator was taught that new state; this fixture was not — one consumer updated, another left
behind, which is `named-failure-vs-no-verdict` exactly. Re-aimed rather than deleted: the same
foreign add now PASSes with its skip record present and FAILs with it absent, so an undrained
foreign project can never read as healthy. 10/10, 0 failed.

### What "landed green" is worth on this box — read the A12 row with this caveat

Every verdict above was earned by **running the suites by hand before landing**, not by the land
gate. `ship-land.sh:63` sheds the smoke phase at 1-min load ≥ `CC_GATE_MAX_LOAD` (default 8), and
this box does not go below 8 by construction (13.42 measured during this session; 26 concurrently;
62 in a prior incident). This land's own row in `~/.claude/land.log` records it plainly:

```json
{"ts":"2026-07-31T06:04:46Z","exit":0,"gate_scope":"fast","selected_n":0,"smoke":"skipped","smoke_n":0,"smoke_s":0}
```

Six commits touching `bin/cc-dispatch`, `bin/cc-blockers` and four suites, landed **behaviorally
ungated** — statically green (lint + ratchets, one of which did block and was fixed) but zero bats
at land time. That is also how `d6b417e9` landed a day earlier with `tests/cc-wave-plan.bats` RED
while that suite is **direct-selected and un-exonerable** for it (`gate-select --explain` emits both
a `literal:` and a `naming:` edge). The known `FULL_FILES` no-smoke path does **not** explain that
one — none of the five were touched and selection was partial, 131 of 226 — so the load-shed is the
operative mechanism, and the designed backstop cannot cover it either while `postland-verify` is in
its known convergence deadlock. Filed as `507558782503`. Consequence for anyone reading this plan's
acceptance table: these rows are trustworthy because they were *self-run*, and a future row that
cites "the land gate was green" is citing a check that did not run.

### Also found live, and fixed (`8d182bc0`)

The actuator discarded the evidence it was reporting on: `"$spawn" … >/dev/null 2>&1` meant every
failure record read only `"<id>: spawn non-zero (reopened)"`. **112 such records accrued in 10 h
against 28 successful fires** — all distinct ids, so systemic rather than per-item thrash, and with
both streams discarded there was no way to tell which. That is §1(c)'s defect class reproduced
inside our own fire path, and it violates R3 and this plan's own rule that a verdict must carry the
evidence that falsifies it. The record now carries the rc and a bounded excerpt. The *underlying*
spawn failure belongs to the row-2 fire seam and is **not** claimed here — only its diagnosability,
which is dispatch-side, was ours to fix.

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

- **2026-07-29 — all three teammates landed.** `gu5-decide` → `e4b17229` (S1/S2/S6/S7) plus
  `f16c37ee` (the S2 correction: the ceiling reads the ledger's `claimed` fold, not a live-session
  count). `gu5-verdict` → `8c0ae731` (S3/S4) plus the deliberate split of the falsified
  wave-sizing cliff from a genuine capped stop. `gu5-cadence` → `21d8e869` (S5/S8).
  Later: `f90fd1bd` multi-project coverage, `5375088b` the `/`-project fix (F11).
- **2026-07-31 — branch hygiene, verified by CONTENT not by count.** `gu5/decide`, `gu5/verdict`
  and `gu5/cadence` each still read 1–2 commits "ahead" of trunk, which looks like stranded work.
  `git cherry -v origin/main <branch>` marks **every one `-`** — all four patches are in trunk by
  patch-id, rebase-landed under different shas. Nothing stranded; the branches are stale pointers.
  Recorded because the ahead-count alone would have prompted a pointless re-land (memory
  `landing-safety-tooling`: verify by CONTENT).
- **2026-07-31 — checkpoint criterion 1–3 re-verified post-landing, criterion 4 extended.** The
  lead's own criteria were re-run against trunk rather than trusted from the acks. Criterion 2's
  "unwrapped call sites == 0" and criterion 3's activation-script assertions both still hold. What
  the criteria did **not** cover, and what a live read caught: A13 was specified in §5/§7 and never
  built (see §10), and the fire path discarded its own failure evidence. Both are now closed —
  `f56041ae`, `8d182bc0`. Lesson for the next row: a checkpoint that greps for the *mechanisms a
  teammate was told to build* cannot see a mechanism **no teammate was assigned**. A13 fell in the
  gap between `gu5-decide` (ceiling) and `gu5-cadence` (alarms) and nobody owned it.

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
- **2026-07-31 — the design's own rule caught the design breaking it, one layer down.** The rule
  directly above was written about `cc-wave-plan`'s cliff. The *same* defect was sitting in our own
  actuator the whole time: `"$spawn" … >/dev/null 2>&1` threw away both streams, so 112 spawn
  failures in a 10 h window each recorded only that something failed. A principle stated about one
  seam is worth re-running over every seam you own — the second instance was found by *measuring*
  the live journal, never by re-reading the code that had already been reviewed at checkpoint.
- **2026-07-31 — a specified mechanism can ship as prose.** `CC_DISPATCH_SATURATED_H` appeared in
  §5 F16 and §7 A13 as though it existed; `grep -rn SATURATED bin/ tests/ scripts/` returned **only
  this document**. It fell between two teammates' ownership boundaries and no checkpoint asked
  "does the thing the doc names actually exist?". Cheap, general guard for the remaining rows: grep
  the plan's own env-var and verdict names against the tree before declaring the row done — a doc
  that describes a mechanism is not evidence the mechanism was built.
- **2026-07-31 — S1's premise was right and the implementation still lost the bound.** "A decision
  costs no quota, no session, no lock" is true of the decision *phase* (7–45 s over 135 items) and
  false of the *pass*, because one lock spans decision and spawn (414–833 s). The architecture was
  never the problem; the lock's SCOPE was. Generalisable: when a design's key claim is about
  cost-of-X, check that the *unit holding the lock* is X and not X-plus-something-slow.
  **Resolved `9dfaac64`, and the resolution taught a second thing: this document's own prescription
  for the fix was wrong.** Both the §10 text and the backlog item said the split needed *"a separate
  admission lock or an atomic claim-based ceiling"*. It needed neither — moving the *acquisition
  point* was enough, because what a lock protects is a REGION, not a duration, and the region here
  (`read live_workers … take claims`) was never the slow part. A prescription written at the moment
  a defect is *filed* is a hypothesis, and the item's remedy half rots independently of its symptom
  half (memory `work-item-remedy-can-become-forbidden`): derive the fix from the mechanism at the
  time you implement it, and re-verify the *reasons* the filing gave, not just its diagnosis. Here
  one of them was actively unsafe — the "obvious" alternative of releasing the lock before the spawn
  tail would have re-created the 2026-07-20 double-worker incident, because `cc-backlog claim`
  refuses nothing and `warm_worktree` races `.git/config.lock`.
- **2026-07-31 — a suite with a pinned control needs a NEW pin per change, not the original one.**
  `tests/cc-dispatch-v2.bats` pins `bf796c57` so landing cannot invert its RED halves — correct, and
  it kept working. But that control is *pre-S6*: it has no singleton at all, so it is structurally
  incapable of testifying about a defect **inside** the singleton, and a RED half written against it
  would have passed for the wrong reason. The A2 fix needed a second pin (`ec92e68c`) carrying the
  S6-era tree. Generalisable: the control is not "the old code", it is "the artifact that exhibits
  the specific behaviour you are changing" — when the file changes twice, that is two shas.
- **2026-07-31 — a green suite is not a green subsystem: check the reader's own selftest too.**
  Every bats suite this diff touched was green while `scripts/dispatch-acceptance.sh selftest` — the
  reader that grades *this entire plan* — had been exiting 1 on `origin/main`. It was found only by
  running it, not by any gate. A criterion's producer and its reader are two consumers of one
  contract, and `f7abcbdee98c` updated the producer plus A1's denominator while leaving A2's fixture
  asserting the retired premise. When a state is added to a system, enumerate its consumers and
  visit each (memory `named-failure-vs-no-verdict`).
- **2026-07-31 — the plan named a second tool that does not exist, and this row certified it.** A12's
  stated read was "`bin/cc-backlog` selftest + `cc-dispatch` selftest". `cc-backlog` has **no**
  selftest and never has (rc 2 `unknown verb`; zero occurrences in source or `--help`). Caught by a
  peer verifier, *after* this session had already marked A12 PASS — the verdict survives on the real
  oracle (`tests/cc-backlog.bats` 79 + compact-race 5), but the criterion's own read was fiction.
  That is the **same class as A13 two entries up, in the same document**, which is the point: one
  instance is an oversight, two is a habit. The cheap guard — grep the plan's own identifiers
  against the tree — would have caught both, and neither cost more than a minute to check.
- **2026-07-31 — "landed green" does not mean "tested" on this box.** `ship-land.sh:63` sheds the
  smoke phase at load ≥ 8; the box never goes below 8. This plan's own land recorded
  `smoke:"skipped", smoke_n:0`. So every acceptance verdict here is worth exactly what the *self-run*
  suites are worth, and nothing more. It is also how a direct-selected suite stayed RED on trunk for
  a day (`507558782503`). Corollary for every remaining row: run the full suite set your diff
  touches — a suite you merely *edited* is not the boundary, a suite the selector *picks* is.
- **2026-07-31 — a rotated journal silently changes a count's denominator.** `idl.jsonl` rotated at
  `20260730T193526Z`. An all-time `grep -c abstained` on the live file reads 0 — the right answer
  for the wrong reason, since §2's 12 abstentions moved into the `.gz`. Every number in §10 names
  its window for this reason (memory `positive-control-the-denominator`).
