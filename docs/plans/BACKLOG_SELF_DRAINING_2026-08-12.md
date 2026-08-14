---
status: open
---

# BACKLOG, SELF-DRAINING — fresh against today's tree, grouped into wave-sized efforts, executed off the operator's box

**Mission.** Make `cc-backlog` maintain and drain itself: every open row re-validated against the
CURRENT tree rather than the one it was written against, the pile organised into a small number of
wave-sized efforts each carrying its own roadmap, and those efforts executed to done — off-box where
the work can leave this machine, locally where it cannot — under a capacity policy that can never
again take the operator's own slots.

**Why now.** Measured 2026-08-12: the dispatcher had fired **nothing at all — cloud or local — for
1 h 34 m** (`fired:0, deferred:318`), and it had no timeout that would ever end that. Meanwhile the
operator's product repos went quiet: `reso-management-app` **0 commits in 7 days** (last 2026-08-05),
`lakehouse-lecture` **0 since 08-10**, while `claude-infrastructure` took **884**. The infrastructure
had become the work.

---

## Phase 0 · Agent Team Orchestration

**EXECUTION LOCUS PER WAVE.**

| Wave | Locus | Deliverable | Depends on |
|---|---|---|---|
| **W0 · unwedge** ✅ DONE | **L** (lead-inline) | the dispatcher fires again; a terminal cloud session releases its slot | — |
| **W1 · freshness** | **S** (dispatched, local) | every open row carries a currency verdict against today's HEAD, on a schedule, with a `lastValidated` fact | W0 |
| **W2 · grouping-for-execution** ✅ DONE | **S** (dispatched, local) | the ungrouped remainder is folded into wave-sized `master-*` conditions; the applying scripts become tracked machinery — **delivered: ungrouped 424→7, ten master efforts, `1b044624d`** | W0 |
| **W3 · capacity symmetry** | **S** (dispatched, local) | no unattended spawner can outbid the operator; the presence beat is consulted at SPAWN, not only at teardown | — (parallel with W1/W2) |
| **W4 · drain** | **S ×N** (one long-running wave session per master effort) | the grouped efforts worked to done | W1, W2, W3 |

**W0 was lead-inline and that needs its one line of justification:** it was four surgical edits in
three files, fully diagnosed with line anchors before any code was written, and the box was in the
exact capacity state this plan exists to protect — firing a teammate wave to repair the spawn
economy would have been the defect performing itself. Every other wave is **S**, the default.

🚨 **W4 is deliberately N long-running sessions, NOT one per backlog row.** That is the operator's
directive and the measurements back it: 695 panes over 5 days, **94% agent-initiated, 1.6%
operator-initiated**, and the machine's own commit `25f369292` records *"189 worker panes a day
against an operator budget of ~15 … the dispatcher had become a competitor to the operator."*

**Lead context budget:** the lead holds ≥50% for deciding venue and adjudicating grouping. Succession
at the seam between waves, never mid-wave — `--recycle` is proven 14/14 on this box, but
`--recycle --worktree` has **never run for real** (only a `--dry-run` on record), so a relocating
recycle here would be its production debut and should be treated as such.

---

## 1 · What is measured, and what it refutes

All figures re-derived 2026-08-12 from the live store and tree. Nothing quoted from an earlier plan —
published figures in this repo have gone stale inside 36 hours more than once.

**The store.** 1,905 folded ids · **536 live** (321 open · 209 blocked · 6 claimed) · 1,369 done.
Intake vs drain over 14 days: **1,212 filed / 835 closed = +377**, ~27/day net. Peak intake 242 in one
day; peak drain 229. **The drain capacity exists and does not keep up on average.**

**Staleness is real and it is the median, not the tail.** The repo lands **~156 commits/day**. For the
292 live `claude-infrastructure` rows, commits landed since the row was written:

| p25 | **p50** | p75 | p90 | max |
|---|---|---|---|---|
| 184 | **361** | 558 | 737 | 2,066 |

**249 of 292 (85%) are more than 100 commits behind.** Age in *days* reads healthy (p50 2.0 d) for the
same population — because the store's clock is days and the tree's clock is commits. That single
mismatch is the operator's complaint, quantified.

**Nothing re-asks an unworked item.** `run_falsifier` has exactly one call site
(`bin/cc-premise:1819`), reached only when somebody tries to CLAIM. **205 of 327 live rows have never
been claimed**, so their probe may never have executed. There is no `lastValidated` field anywhere, so
"how many have ever been re-validated" is **not answerable from the store**. And the whole-store
re-validation pass that would fix this — `cc-premise sweep`, `cc-premise screen --all` — has **zero
callers** on the box.

### 🚨 The consolidation premise needs one correction, and the instinct behind it is right

The ask was to merge the pile into grouped tickets so fewer sessions are needed. Two separate claims
sit inside that, and they do not share a fate:

- **Dedup cannot shrink the pile.** Three independent methods converge: the duplicate surplus is
  **28–38 rows, 5–7% of 536**, recoverable once. The pile is **~93–95% genuinely distinct efforts**.
  Worse, a `fold` removes **zero** rows *by design* — `backlog-consolidation-trigger.sh` asserts
  `conservation=ok · live 537→537` and its own docstring says *"absorption is traceability, not
  closure."* A perfect fold of all 18 mechanical groups leaves the count at 536.
- **Grouping-for-execution is the real lever, and it is exactly what was asked for.** The binding
  constraint is not row count, it is **session count against a load-bound box**. The condition lease
  already makes one worker claim a whole condition group and refuses its siblings — so N grouped rows
  cost ONE session. Today only **129 of 536 rows carry a condition, in 37 groups of which 29 are
  n=1** — about 8 real groups. The other ~407 rows are one-session-each by default.

So the target is not "fewer rows", it is **~407 ungrouped rows → a couple of dozen wave-sized
efforts**. The proven precedent is already on disk: `link.py` wrote 113 links into seven hand-authored
`master-*` conditions (`master-convergence-deadlock` 35, `master-fire-gate` 22,
`master-fleet-footprint` 20, …). ⚠️ **`link.py` and `prune.py` are UNTRACKED** — they live only in
`docs/plans/backlog-consolidation-2026-08-09/`, have no caller, and are one `git clean -f -d` from
gone. *The only thing that has ever reduced this pile is not part of the machine.*

### The crowd-out has a named mechanism, and it is asymmetry

**There is no "15".** No code reads it; `CONCURRENCY_PROGRAM.md:574` already calls it folklore. What
binds is **load ≥ 2.0/core** (`scripts/lib/capacity-admit.sh:121`). The asymmetry is the defect:

- for `handoff-fire` — **the operator's own path** — the refusal is **unbounded**;
- for unattended callers it **budget-releases after 3 consecutive refusals** (`capacity-admit.sh:398`);
- for the **Agent tool**, the highest-volume spawn surface, the load term is **off entirely**
  (`hooks/agent-teams-enforce.sh:183`, `basis:"headroom-only"`).

**So the one path subject to the full gate is the human's.** 64 capacity refusals are logged in the
retained window (12 / 46 / 6 across 08-09..08-11).

**The guard that would fix this already exists and is inert.** `hooks/session-beat.sh` +
`hooks/lib/cc-beat.sh` maintain a real operator-presence signal including `operatorT`, the sticky
high-water of presence. Its only consumer is `hooks/teammate-auto-shutdown.sh`. **The fleet knows
whether the human is at the keyboard and uses it solely to decide whether to CLOSE a pane — never
whether to OPEN one.** There are no quiet hours on the spawn side anywhere.

**This session's own conduct is part of the evidence.** The five recon subagents that produced these
numbers registered as ordinary pane sessions (uuids 416–420) and were **5 of 8 live slots, 62%**.
Nothing in the accounting separates "the operator's budget" from "the agent's fan-out". W3 owns that.

---

## 2 · W0 — the unwedge, done (commit `a984691f6`)

The pipeline was not slow, it was **dead in place with no timeout**. Three defects composed; the
symptom pointed at none of them. Full reasoning is in the commit body; the shape:

| # | Defect | Fix |
|---|---|---|
| D1 | `live_workers()` folded `claimed` with **no venue predicate**, so six OFF-BOX sessions saturated the ceiling that bounds panes/worktrees/CPU | venue-scoped fold, one ceiling per resource, `CC_DISPATCH_CLOUD_CEILING` bounds the new lane |
| D2 | the `.returned` latch omitted the **backlog close**, so a landed+verified round trip that failed to close latched anyway → `already returned` forever, unretryable | close joins the latch; refusal reason captured instead of `>/dev/null`; permanent failure bounded by `CC_RETURN_CLOSE_MAX` in a sidecar counter |
| D3 | **nothing ever called `cc-cloud retire`** (0 markers / 38 declarations); `is-offbox` is two file-existence tests with no completion notion, so reap could never reopen the claim | the terminal path retires — and only there, so a working VM is never declared dead |
| BAND | the fold's 60 s bound was sized in the foreground (17.5 s) while the sweep runs in Darwin's Background band (**68.1 s**) → rc 124 on 10/10 runs | probes run at `utility` (20.3 s), bound 180 s |

**The honest caveat, because it changes what W1–W4 can assume:** venue-scoping *alone* would not have
freed this box. All six claims were cloud, so a cloud lane at 6/6 is still full. **D3 is what actually
releases them.** D1 is correct accounting that stops the two lanes starving each other.

**And the BAND fix has a consequence worth naming:** `fold_conservation` can now reach `ok`, which is
the documented precondition for flipping `--fold` to `--fold --apply`. Run to completion today it
reports `conservation=ok · 19 groups · 18 would fold · 0 ambiguous`. **The criterion was already
satisfied and no instrument on the box could observe it.** W2 owns the flip — on a series, not on this
one reading.

### 🚨 The BAND fix also attacks the thing blocking the ENTIRE live layer, and the arithmetic is
### counter-intuitive enough that it was nearly shipped as a regression

Raising a timeout from 60 s to 180 s reads like it must make a suite slower, and `tests/autonomy-sweep.bats`
runs the real sweep once per test across **49 tests with no stubs for the trigger or the ratchet** —
so the instinct was that this change would worsen a suite already stamping `verdict:"hung"`
(`run_s` 4,144 s and 5,235 s on the two commits before this one; the hang is **pre-existing**, not
introduced here).

Measured instead, same box, launched from the Background band exactly as launchd and the verifier do:

| per-sweep probe block | `--file` | `--assert` | `--fold` | **wall** |
|---|---|---|---|---|
| pre-fix (Background, 60 s ceiling) | rc 0 | rc 1 | **rc 124** | **94.1 s** |
| post-fix (utility, 180 s ceiling) | rc 0 | rc 1 | **rc 0** | **26.0 s** |

**3.6× faster.** The bound was never a ceiling the fold approached — the fold consumed the *entire*
60 s and was then killed, every single pass. Completing costs 20 s; being cut costs 60 s. Raising the
bound made the work finish instead of dying at the wall, and a bigger number bought less time.
Across 49 tests that is roughly **77 min → 21 min** in the probe block alone.

That matters far past this plan: **no GREEN `postland-verify` stamp exists because that suite hangs,
and `deploy-live.sh` is fail-closed on GREEN stamps — so the live `~/.claude` layer cannot advance at
all.** The measurement above is therefore a direct attack on the fleet's convergence blockage, not
only on the fold. Whether it is sufficient is unproven: the verifier's own `run_s` is the arbiter and
its first run against this commit is in flight.

**Generalisable, and it is the reason this section exists:** a timeout that is always hit is not a
bound, it is a fixed cost. Before sizing one, measure whether the subject *completes* — the two cases
have opposite responses to raising the number.

---

## 3 · The waves

### W1 · Freshness — a currency verdict for every row, on a schedule ✅ DONE (`cf0f11a4b`)

**Outcome: never-validated 536 → 387 on the live store, 18 falsified rows retired, decay now readable
in commits (p50 402) as well as days (p50 2.0).** All six items landed and content-verified; the full
account — including the correction the wave lead caught mid-build, which is the load-bearing part —
is in the Status log below. The six items as originally written are kept verbatim underneath, because
item 5's framing turned out to name the wrong half of its own defect.

⚠️ **387 is not a failure to reach zero; it is the honest number.** 386 live rows carry no probe at
all, so nothing can be asked about them and nothing is stamped. Driving that down is the coverage
ratchet's queue (master M2 wires generators to emit `--falsifier`), not this wave's.

**The gap in one sentence:** re-validation is demand-driven and 63% of live rows generate no demand.

1. **Wire the zero-caller pass.** `cc-premise sweep` and `cc-premise screen --all` are built,
   documented, and invoked by nothing. Put them on the sweep, at `utility` with a band-fitting bound
   (W0's `_bounded` is the pattern). Today's hand-run: 2 superseded · 2 self-duplicate · **16
   falsified** · 67 suspect.
2. **Record that a probe RAN.** Add `lastValidated` (+ the trunk sha it was validated against). Without
   it, `backlog-ratchet.sh` measures *coverage* — how many rows CAN self-check — and a store could be
   100% covered and 0% ever-executed and read GREEN.
3. **Measure decay in COMMITS, not days.** Every age reader uses wall time. Publish
   `commits-since-filing` per row; it is the number that makes p50=361 visible.
4. **Close what is provably dead.** A falsified row today *refuses claims and never closes* — it
   becomes permanently live and permanently unfireable. 16 rows are in that state right now.
5. **Put `reopen` behind the same re-read as `unblock`.** Measured 276 reopens vs 44 unblocks on live
   rows; the amnesia path is 6× the guarded one.
6. **Give `ratchet_rc` a consumer.** It has read RED on every recorded run today (48.6% vs a 50.0%
   high-water) and the only consequence is a JSON field.

**DoD:** every live row carries a currency verdict no older than one sweep, and the count of
never-validated rows is reportable and falling.

### W2 · Grouping-for-execution — ~407 ungrouped rows into wave-sized efforts ✅ DONE (`1b044624d`)

**Outcome: ungrouped 424 → 7, ten master efforts, 418 links, 0 refusals.** All five items landed and
content-verified; the full account with its three corrections is in the Status log below. The five
items as originally written are kept verbatim underneath, because two of them turned out to be
phrased for a defect that was not the binding one.

1. **Promote `link.py` / `prune.py` into tracked machinery.** They are the only things that have ever
   moved this pile (161 closes, 113 links, 0 failures) and they are untracked with no caller.
2. **Extend `master-*` coverage** from 129/536 toward the whole live set. Semantic grouping, not
   mechanical — the mechanical key is honest about its own limits (its largest "cluster" of 14 was
   **nine different stranded worktrees**; folding them would have refused dispatch on all nine).
3. **Flip `--fold` to `--apply`** once `fold_conservation` reads `ok` across a *series* of sweeps —
   now reachable. Never flip past a `FAILED`.
4. **Fix the escalation row that can never update.** `cmd_add` returns early on a known id, so the
   trigger's `--file` is a no-op rather than an update; row `5df742fb3894` has been frozen at its
   pre-R6 wording since 2026-08-11 and will stay frozen forever.
5. **Each master effort gets a plan file with its own Phase 0 wave table** — that is the artifact W4
   executes.

⚠️ **A roadmap in a plan file binds nothing on its own.** `GROUND_UP_DISPATCH.md` measured this the
hard way: *"a runbook paragraph binds a successor who is never spawned"*, and *"a worker reads the
payload, never the runbook that discusses it."* So each wave must exist in **three** places: the plan
file (for humans), a condition-keyed `cc-backlog` row (for the dispatcher), and **restated inside the
fired brief itself** (for the worker). Also: every `dodRef` is an absolute path into the shared
checkout, which trails trunk — so a brief must reference the trunk ref, not the working tree.

**DoD:** ungrouped live rows < 50, and the number of distinct wave-sized efforts is countable on two
hands.

### W3 · Capacity symmetry — the operator can never be outbid again

1. **Consult the presence beat at every SPAWN site.** `cc-beat` is measured, live, and read by nothing
   that opens a pane. This is the single highest-leverage inert guard on the box.
2. **Remove the asymmetry.** Either the operator's path gets the same budget release, or unattended
   callers lose theirs. Today only the human's fire can be refused indefinitely.
3. **Re-enable the load term for the Agent tool**, or charge its panes somewhere. It is the
   highest-volume surface and is gated on memory headroom alone.
4. **Reserve slots.** A floor of local capacity that autonomy may never take, so `~15` becomes a real
   number enforced in one place instead of folklore.
5. **Quiet hours on the spawn side.** None exist; the 08-10 peak of 54 sustained sessions sat squarely
   inside the operator's working day.

**DoD:** with the operator active, unattended spawns yield — demonstrated by a capacity refusal that
hits an autonomy path rather than a `/handoff`.

### W4 · Drain — one long-running session per master effort

Per effort: claim the condition (the lease refuses siblings, so the group costs one session), work the
roadmap with teammates **inside** that session, land, converge, close the rows.

**Longevity is not the constraint; cumulative context is.** Multi-day sessions already exist here —
80.4 h observed. The only 100%-fatal class is `Prompt is too long` (5 sessions, 5 terminal), and it
selects for exactly this shape: 4 of the 5 were long claude-infrastructure leads, none had ever
compacted. Teammate-leads reach **1.6× the peak context** of dispatch-leads (458 K vs 289 K median).
Hence: teammates belong *inside* a dispatched wave session, never on the standing lead, and the lead
recycles at wave seams.

**Venue:** cloud takes what it can, which is inherently limited — **47 of 536 (8.8%)** are off-box
eligible, and the refusal classes are structural (`ineligible-box` 149, shallow 50-commit clone, no
`gh`, no `~/.claude`). **248 rows carry no venue label at all** because `cc-venue run` is open-only and
new rows wait for the next producer pass. Re-labelling is a W2 prerequisite for routing.

🚨 **Do not set `CC_DISPATCH_VENUE_ONLY=cloud` and call the migration done.** It parks **489 of 536
rows indefinitely** — and, because the claim path is the only *blocking* re-validation in the system,
it also silently switches off currency-checking for 86% of the store. The venue lever steers; it does
not scale.

---

## 4 · Definition of done

1. No open row cites a tree state it has not been re-checked against since — and the check runs
   whether or not anyone tries to work the row.
2. The live set is organised into wave-sized efforts, each with a plan file, a condition-keyed row, and
   a brief that restates its own instruction.
3. Those efforts run to done — cloud where eligible, local otherwise — as long-running wave sessions.
4. Throughput exceeds intake, so the count falls rather than oscillating.
5. **The operator's own fire is never the one that gets refused.**

**Anti-goal:** a pipeline that dispatches blind, or a consolidation that renames the pile without
reducing the sessions needed to work it.

---

## SUCCESSOR — start here

State at the 2026-08-12 recycle: **🚀 landed, not live.** `c221caa58` + `39388b17d` are
content-verified on `origin/main`; the live `~/.claude` layer still runs the pre-fix bytes because
the shared checkout trails trunk and `deploy-live.sh` is fail-closed on a GREEN `postland-verify`
stamp that does not yet exist.

**Do these in order. The first one may already be done for you.**

1. **Check whether the fleet's convergence blocker just cleared.**
   `ls -t ~/.claude/autonomy/postland/stamps | head -3` and read the newest verdict.
   The two stamps before this work read `verdict:"hung"` / `failing:["tests/autonomy-sweep.bats"]`
   with `run_s` 4,144 s and 5,235 s. **The arithmetic says that suite's probe block WAS the hang**:
   49 tests × ~94 s of probe = ~4,600 s, which is essentially the whole run time, and the BAND fix
   takes that to ~26 s × 49 ≈ 1,270 s. If the stamp against `39388b17d` is GREEN, run
   `bash scripts/deploy-live.sh` and the whole backlog fix goes live in one step.
   **If it still hangs, that is the highest-value target on the box** — nothing in `~/.claude`
   can advance until it passes (filed `35190812890d`).
2. **Confirm the unwedge actually took, once live.** `bin/cc-dispatch` should stop reporting
   `reason:"at-ceiling"` with `fired:0`, and finished cloud sessions should start carrying
   `.retired` markers (there were 0 across 38 declarations).
3. **Then W1/W2/W3** below — filed as `b585e86ea4e4` (freshness), `ce1e9d1adab8` (the untracked
   `link.py`/`prune.py`), `8ae4b508f274` (capacity symmetry). W3 is the one the operator feels.

**Two traps this session hit, so you do not pay for them twice.**
- **A timeout that is ALWAYS hit is not a bound, it is a fixed cost.** Raising one can make a suite
  faster. Measure whether the subject *completes* before sizing it.
- **A harness that extracts one shell function loses the helpers it calls.** Extracting
  `live_workers` without `is_uint` made every case return UNKNOWN and pass vacuously — against the
  *broken* binary too. Always RED-prove against pristine trunk before believing a green suite.

**Do not re-run the recon.** It is preserved at `docs/research/backlog-pipeline-recon-2026-08-12/`
with its own README naming the one finding later corrected by measurement.

## Status log

- **2026-08-13 02:5xZ — the two facts that reframe this whole plan, both raised by the operator and
  both measured rather than argued. THE DRAIN IS NOT THE BOTTLENECK; INTAKE IS. AND CLOUD CANNOT
  TAKE THIS PILE.** A successor reading only the earlier entries would get both of these wrong.

  **1 · We are net-FILING, and the plan's framing hid it.** Every entry above measures closes. Nobody
  measured the balance:

  | day | filed | closed | net |
  |---|---|---|---|
  | 2026-08-09 | 373 | 68 | **+305** |
  | 2026-08-10 | 172 | 231 | −59 |
  | 2026-08-11 | 261 | 122 | **+139** |
  | 2026-08-12 | 117 | 74 | **+43** |
  | **5-day** | **1,129** | **503** | **+426** |

  Filing outran closing on four of five days. **2026-08-12 was the largest drain day of the week** —
  47 stranded rows closed on one lease, the first whole-store currency pass, four off-box suites
  root-caused — **and it still ended +43.** The lead alone filed 7 of that day's 99 adds, then closed
  by naming three more follow-ons.

  **The mechanism: filing is frictionless and closing is not**, so "file it" is the cheaper branch at
  every decision point. The Follow-On Gate (F1-F4) governs whether to *pursue* adjacent work and says
  **nothing** about whether to *file* it — so the one disposition with no gate on it is the one that
  grows the pile. A filed row is not a discharged obligation; it is a deferred one with a carrying
  cost, and 426 of them accumulated in five days. **Treat `filed N / closed M` per effort as a
  reported metric, and never close an effort net-positive.** (A per-session conservation rule —
  file N, close ≥N — is the obvious mechanical form; it is NOT built, and it carries a real cost
  worth weighing first: expensive filing means some findings get dropped instead of recorded, and
  dropping a security finding to protect a counter is a bad trade.)

  **2 · Cloud cannot drain this backlog, and the reason is structural, not a tuning problem.**

  | | |
  |---|---|
  | live rows by venue | local **275** · unlabelled **195** · cloud **68** |
  | cloud declarations | LANDED **6** · STALLED 17 · NOT-STARTED 17 · ABANDONED 7 · BOOTING 2 · ALIVE 2 |

  **6 of 51 declarations ever landed (12%); 34 of 51 (67%) never did useful work.** And the
  eligibility gate names its own refusals: `ineligible-box` (local-only state a VM cannot see),
  `ineligible-spawn-rail` (verified only by a live fire on this box), `ineligible-visual`,
  `ineligible-branch-banking` (the corpus exists only on this disk), `ineligible-github` (no `gh`
  off-box), `ineligible-offbox-lane`. **This backlog is overwhelmingly ABOUT THIS MACHINE, and cloud
  cannot see the machine.** Any plan that budgets on cloud absorbing the remainder is wrong at the
  premise. 🚨 Do NOT respond by setting `CC_DISPATCH_VENUE_ONLY=cloud` — that parks the local
  majority indefinitely (§3 W4 already records why).

  **`cc-venue` was the producer with ZERO callers** — its own header quotes `cc-dispatch:470`,
  *"`cc-backlog claim --venue local|cloud` shipped fully built and fully tested with ZERO
  PRODUCERS"*. Ran it 2026-08-13: unlabelled **239 → 195**, cloud **56 → 68**, local **244 → 275**.
  195 remain unlabelled and the dispatcher journals those `ready:false, reason:"venue-unlabelled"`,
  i.e. routed nowhere. Re-run it on a schedule or the label rots as fast as the rows.

  **CONSEQUENCE — THE LOCAL DRAIN (pane 463, `local-drain`, goal armed).** The operator's design, and
  it is the correct one: *one* long-running local session for the **470 non-cloud rows**, walking the
  ten `master-*` efforts **smallest-first**, claiming each CONDITION so one lease covers its rows,
  using teammates only INSIDE itself, and **`--recycle`-ing at every effort boundary** instead of
  stopping. One slot, indefinite duration — because the bottleneck is concurrent sessions (~15), not
  session length, and every wave fired today took a slot and then retired. Brief: `/tmp/fire-local-drain.txt`.
  Deliberately NOT re-keyed into one mega-condition: that would dissolve W2's ten efforts and each
  effort's roadmap with them.

- **2026-08-12 — W1 LANDED, all six items. Row `b585e86ea4e4`.** One commit (`cf0f11a4b`) across
  `bin/cc-backlog`, `bin/cc-premise`, `scripts/autonomy-sweep.sh`, `scripts/backlog-ratchet.sh`,
  plus `tests/backlog-freshness.bats` (25 cases) and 3 caller-proof cases in
  `tests/autonomy-sweep.bats`.

  **DoD met, two readings on the live store: never-validated 536 → 387, falling.** `cc-backlog
  freshness` is the command that prints it (`--never` prints the bare integer). The pass probed 150
  rows and retired **18 falsified rows** — including `5df742fb3894`, the row W2 recorded as "frozen
  at its pre-R6 wording since 2026-08-11 and will stay frozen forever".

  🚨 **The most important number in this entry is 387, and it is deliberately NOT zero.** 386 live
  rows carry no probe at all, so nothing was asked about them and nothing was stamped. That is the
  honest reading and it took a correction to get there — see below.

  **What each item turned into:**
  1. The pass is on `autonomy-sweep` at utility with its **own** bound. The shared 180 s did not
     fit: measured **106 s at utility over 564 rows**, so the bound is 420 s (4× measured). It runs
     on a **6 h cadence, not per sweep** — the sweep fires every 300 s, and a 106 s pass every 5
     minutes would spend a third of the box's sweep budget. The stamp is claimed BEFORE the run, so
     a pass killed by its bound costs one interval instead of spiralling.
  2. `lastValidated` + its trunk sha, in a **regenerated side file**, not the ledger. Per-row events
     would add ~20 MB/day to a 2.8 MB store — the sweep is 5-minutely and `cc-backlog compact` has
     no caller. Consequences (a close) still go in the ledger as ordinary records.
  3. Decay in commits: **p50 402 · p75 686 · p90 1040 · max 2322** against p50 2.0 DAYS for the same
     population. Anchored on a new **first-wins `firstTs`**, never `lastTs`.
  4. `sweep --close-falsified <cap>` — re-asks each row immediately before acting, never touches a
     CLAIMED row, and reports the cap whenever it binds. A bare `--close-falsified` is rc 2.
  5. The re-read was `unblock`-only at `bin/cc-backlog:1935`. Re-measured: **374 reopen vs 60
     unblock** on live rows. Both now re-ask; the verb picks the AUDIENCE, so reopen speaks only on a
     blocking verdict — 374 advisories a day is an ambient alarm.
  6. A red ratchet now files **one condition-keyed row carrying its own falsifier**, so the standing
     regression is one standing row that retires itself when coverage recovers.

  🚨 **THE CORRECTION, caught by the wave lead mid-build, and it was worse than reported.** The lead
  measured that `lastTs` is worthless as a currency signal — W2's own grouping pass rewrote **70% of
  the store's `lastTs` inside one hour** as pure link bookkeeping, so the store's decay p50 read 8
  commits behind against a true ~361. The same defect was live in this wave's first design one layer
  deeper: **`assess` returns `clear` both for "a probe ran and said still live" and for "there is no
  probe, so nothing was asked"**, and the sweep was stamping both. That would have driven
  never-validated to **zero** while ~400 of 564 rows had had nothing run against them — a metric
  reporting fresh forever and hiding the exact staleness it was built to expose. Fixed by making
  `assess` report WHICH ARM fired (`out["probed"]`), stamping only probed rows, publishing the
  unprobed count beside them, and removing the stamp from the re-admission path entirely: **one
  producer, and only a measurement.** Decay is additionally published from the validated **sha**,
  which no bookkeeping write can bump. (memory: `proxy-must-be-independent-of-what-it-supplements`.)

  **Two defects the build found in its own instruments, both silent:**
  - `[ -d "$repo/.git" ]` is false in a **linked worktree** (`.git` is a file), so the second clock
    was switched off in exactly the place this repo's waves work. The census printed "commits since
    filing: UNKNOWN" against a perfectly readable repo.
  - `git log --format=%cI` prints the **committer's offset** (`+02:00`) while the store is UTC `Z`,
    and the comparison is lexicographic — it would have returned a plausible, wrong integer forever.

  **RED-PROOF, not a green board.** The suite was replayed against the real pre-fix artifact
  (`git archive origin/main` @ `53caadb3b`): **18 of 21 red**. The three that passed are named
  controls, each proven killable by its own mutant. Case 19 was strengthened after a mutant survived
  it — it had fixtured only an ABSENT premise binary, which skips the block before reaching the `||`
  that carries the exit code, while the dangerous case is one that EXISTS and exits 3 (cc-premise's
  normal blocking verdict). Case 9b kills the pre-correction design above.

  **Left standing, deliberately:** coverage is 46% and the ratchet's high-water is 50%, so `--assert`
  is genuinely RED — that is a true regression (rows are being filed without probes), and it now has
  a consumer rather than being only a JSON field. Driving coverage back up is the generators' job
  (master M2), not this wave's.

- **2026-08-12 12:50Z — the live layer's no-budget door is T1H, its producer has been dead two days,
  and exactly TWO suites are holding it shut.** This supersedes the framing of every entry below that
  treats convergence as "wait for a green stamp or wait for the clock". `deploy-live.sh` has a
  **four-tier** ladder (its own header, lines 27-37), and only one tier had been looked at:

  | Tier | Advances when | Budget |
  |---|---|---|
  | **T1** VERIFIED | newest GREEN tree descending live HEAD | — (producer emits **0.17 greens/day**, so this door is effectively shut by design) |
  | **T1H** HERMETIC | newest commit above live HEAD carrying an **off-box green over the hermetic subset** AND no on-box RED | 🚨 **NONE — advances on a POSITIVE result** |
  | **T2** DEGRADED | T1 and T1H empty AND lag past budget | 25 commits / 6 h, whichever trips first |
  | **T3** BLOCKED | every commit above live HEAD is RED | refuse + page |

  **T1H exists precisely because T1 is unreachable in practice** — the file says so: *"T1's producer
  emits 0.17 greens/day, so the healthy silent path is unreachable in practice and every advance has
  to come through T2's absence-of-evidence door. T1H is a SECOND producer for the same ladder."*

  **That second producer is `.github/workflows/hermetic.yml`, and it has failed EVERY run since
  2026-08-10** — six consecutive scheduled failures today (05:00, 06:41, 08:38, 10:09, 10:19, 11:56 Z),
  each ~16-21 min. `~/.claude/autonomy/postland/offbox/` holds **exactly one** stamp, green, dated
  `2026-08-10T09:50:08Z`. So the no-budget door has had nothing to open it for two days, and every
  advance has been forced through T2's clock.

  **The fold from run `31594132333`, verbatim — all ten shards completed:**

  ```json
  {"verdict":"red","suites":405,"expected":405,"green":403,"red":2,"nonverdict":0,
   "unreported":0,"run_s":3571,
   "failing":["tests/autonomy-sweep.bats","tests/worker-claim-gate-coverage.bats"],
   "nonverdict_suites":[],"unreported_suites":[]}
  ```

  **403 of 405 green. Two suites.** Fix them → the workflow goes green → an off-box stamp lands →
  T1H advances with no budget → W2's 21 new files and W3's `spawn-presence.sh` reach the live layer
  immediately instead of on a 25-commit/6-hour timer. Filed `3b22efbc2340` under
  `master-convergence-deadlock`. Pane 433 redirected onto it; the SIGTERM hunt (`b7252a3bb015`) is
  demoted to its fallback, because T1H does not need the on-box corpus to succeed at all.

  🚨 **AND IT REFUTES THIS SESSION'S OWN EARLIER CLOSE — `35190812890d` is REOPENED (`--force`).**
  That row was closed citing *"the corpus named ZERO failing suites"*. The stamp it cited read
  `verdict:"cut"`, and **a cut names no suite BY CONSTRUCTION** — the runner's own words are *"no test
  completed and failed, so nothing is proven"*. An empty `failing[]` from a cut is a **null from a
  blind instrument, not an absence**, and reading it as an acquittal is exactly the error the memory
  `read-the-diff-not-the-commit-subject` names. The off-box run that DID complete all 405 lists
  `tests/autonomy-sweep.bats` as one of the two reds. **The HANG is genuinely fixed — 3,562 s vs
  4,144-5,235 s, and the off-box shard completed it — but the SUITE is not green, and those are
  different claims.** The general guard this implies (a close may not cite an empty `failing[]` from a
  non-verdict stamp) is filed as `3ec6c070f52f` under `master-verification-integrity`.

- **2026-08-12 — W2 LANDED, all five items. Row `ce1e9d1adab8`.** Five commits: the `cc-backlog`
  update arm, the trigger's conservation span, the tracked consolidation machinery, the sweep wiring,
  and the ten master plan files.

  **The store, measured after the apply: 566 live · 559 grouped · UNGROUPED 7 (was 424) · 10 master
  efforts.** DoD asked for ungrouped < 50 and an effort count countable on two hands; both met. 418
  links were written in three passes, narrowest key first: the mechanical fold 46 (18 groups, its
  first real apply ever), the 2026-08-09 triage wave's own human adjudication replayed 45 — rows it
  had judged KEEP/UPDATE that nobody had ever linked — and the semantic grouper 327, with 0 refusals
  in all three.

  **The honest second number: 51 other condition groups hold the remaining 82 rows.** Those are the
  ~12 per-worktree re-land groups the mechanical fold minted plus ~29 pre-existing singletons. They
  are not wave-sized efforts and are not counted as such (see the fold-precedence decision below).
  The 7 ungrouped are 4 residue rows a human should read and 3 CLAIMED rows deliberately left alone —
  joining a held row makes its whole group unclaimable for as long as the holder lives, which is the
  lease working against you.

  **Where each wave now exists, all three places, as the brief required:** the plan file
  (`docs/plans/MASTER_*.md`), a condition-keyed row the dispatcher can see, and the row's own title
  restating its instruction — because a worker reads the payload, never the runbook. Six of the ten
  wave rows resolved to the CLOSED M1-M6 rows from 2026-08-09/10 (`mk_cond_id` is project+condition,
  so the M-wave already owned those keys) and cc-backlog's done-guard correctly refused to reopen them
  silently. They were reopened with `--force` and evidence, because each state measurably holds again
  with a far larger population: the convergence deadlock is unbroken, 69 stranded commits sit across
  778 branches, 273 worktree dirs against 151 registered. **Their titles were then refreshed by this
  wave's own update arm** — the M-wave wording became the W4 wave wording, which is item 4 in live
  use. Every `dodRef` is `origin/main:<path>`, a TRUNK REF, never a shared-checkout path.

  **Filed, not fixed:** `aee48ef0ffcf` — `cc-backlog link` costs one full ledger fold per row, so this
  418-row pass degraded from ~4 s to ~20 s per link as the append-only ledger grew, and took over an
  hour of wall clock to write one condition field per row. The next consolidation wave needs a batch
  verb; `link.py --plan` already emits exactly the input it would take.

  **What each item actually cost, and the three things that came out different from the plan:**

  1. **`link.py` / `prune.py` promoted — and GENERALISED, because tracking alone would have left them
     inert.** `link.py` read exactly one artifact (`verdicts.json`, from a wave that will never run
     again in that shape), so a tracked copy's only possible caller was "the next hand-driven
     triage", i.e. nobody. It now takes a PLAN of `(id, condition)` from a file or stdin and is the
     single WRITER; the new `group.py` classifies and calls it. `citegraph.py` reads the live store
     instead of a frozen snapshot (a derived signal that stops being derived still prints a confident
     ranking). `prune.py` + `verify.py` stay the triage-wave pair, parameterised by `--dir`.
     36 tests across three suites, every site mutation-tested one at a time.
     ⚠️ **That sweep found a real coverage hole rather than confirming the tests:** deleting
     `group.py`'s already-conditioned skip left the whole suite GREEN, because `link.py` applies the
     same predicate and `cc-backlog link` refuses a re-key with rc 4 — three copies of one rule, only
     the last two able to refuse a write. The per-site tests moved onto the writer that enforces them.
  2. **Grouping is SEMANTIC and the classifier's two corrections are the transferable part.** A
     backlog "title" here is a PARAGRAPH — p50 299 chars, p90 1251, max 2558 — so a generic word
     matched anywhere in it is a lottery: `token` stole a row about attaching evidence, `by hand`
     stole one about untracked skills, `codex` stole a lint row via a path in its `dodRef`. Rules now
     match the HEADLINE (`title[:120]` + `dodRef` + `source`). **That cost recall — residue 14 → 31 —
     and this plan's own discipline says to say so:** the comment in the file first read "recall cost,
     measured: 0 rows", written before the measurement. Writing the families the residue exposed took
     it to 3. Second correction: `_` is a word character, so `\bROUTER\b` never matched
     `START_LATENCY_ROUTER` and the whole SCREAMING_SNAKE `plan-open` family fell through to residue.
  3. **The `--apply` flip: the criterion was already satisfied and nothing on the box could see it.**
     Five consecutive dry runs, `conservation=ok` on all five, 19 groups / 18 would fold / 0
     ambiguous, byte-identical across the series. Flipped as **dry-then-apply**, not a bare
     `--apply`: the writer runs only when THIS sweep's own dry verdict reads `ok`, so "never flip past
     a FAILED" stops being a rule someone has to remember, and a key that starts merging across a
     distinction disarms the writer on the sweep that notices.
  4. **`cmd_add`'s early return, proven on the live row the brief named.** `5df742fb3894` carried ONE
     `add` record from 2026-08-11T08:36:59Z and nothing since, while the sweep re-filed it every few
     minutes — each pass a silent rc-0 no-op. After the fix its next `--file` run appended
     `event:"update"` at 11:44:45Z carrying the current R6 wording: **27 hours frozen, then current.**
     `--falsifier` is deliberately NOT updatable here — `cmd_falsify` RUNS the probe first and
     refuses one that exits 0 against a live row, and writing it from `add` would be a second door
     into that store with the guard missing. A DONE row is excluded for two reasons, the second
     measured: `cc-value:179` folds status as the RAW EVENT, so an update on a done row would delete
     it from the fleet's closed-work metric (`venue` already masks 241 rows that way).
  5. **Ten plan files, each with its own Phase 0 wave table** — and `tests/backlog-grouping.bats`
     asserts every master the taxonomy can emit HAS one, because a wave nobody can run is worse than
     an ungrouped row.

  🚨 **THE DEFECT THIS WAVE FOUND BY RUNNING ITS OWN TOOL: the fold's conservation assertion spanned
  the whole store.** Its first real apply wrote 46 links with 0 refusals and reported
  `conservation=FAILED live 555→555 · open 330→331` — a sibling session had unblocked an unrelated row
  during the three minutes it took. Nothing was wrong with the fold. But FAILED is the one verdict a
  caller may never flip past, so an over-wide version of it does not merely mis-report: **it would
  have permanently disarmed the writer this wave had just armed, on another mechanism's correct
  behaviour.** The dry-run branch already got this right in a comment; the apply branch under it did
  not. The discriminator is structural rather than a tolerance — a `link` record carries no status
  arm, so it CANNOT create, close, block or reopen a row, and a changed count is by construction not
  ours; what it can break is a row IT linked losing its status. Both `link.py` and the trigger now ask
  that, per row, against a pre-write snapshot, and report `unknown` when the store moved elsewhere.

  **A decision worth recording, because the DoD's headline number reads better if you make the other
  choice.** The mechanical fold ran FIRST (narrowest, key-verified), and it keyed 46 re-land rows onto
  ~12 per-worktree digest slugs. Those rows are therefore NOT in `master-stranded-work` — the semantic
  grouper never re-keys. Folding them in with `link --force` would have made the effort count smaller
  and would have been optimising the metric over the mechanism: the fold's per-worktree key is the
  more conservative one, and 46 rows → 12 groups is a real reduction. So the honest count has two
  numbers, not one, and both are reported above.

  **Venue re-labelling** (named in the brief as related work) is already filed as `116d5a15674b` and
  is now a member of `master-fire-gate`, whose F1 sub-wave owns it — including the measured warning
  that `CC_DISPATCH_VENUE_ONLY=cloud` parks 489 of 536 rows AND switches currency-checking off for
  86% of the store. Routed, not dropped.

- **2026-08-12 11:10Z — W3 LANDED (`8576c0190`), all five items, and two of them came out different from
  the way the plan phrased them.** Row `8ae4b508f274`. `scripts/lib/spawn-presence.sh` is new;
  `capacity-admit.sh`, `handoff-fire.sh` and `agent-teams-enforce.sh` consume it.
  **DoD met:** `tests/spawn-presence.bats` case 20 drives BOTH gates over ONE pinned world and
  asserts they DISAGREE — autonomy refused on `reserve-slots`, the operator's own `capacity_gate`
  admitted — because either half alone is satisfiable by a gate that refuses or admits everything.
  31 cases, **31/31 RED against pristine `caab1c283`**, 31/31 green after; 129/129 with the four
  neighbouring suites; shellcheck clean.

  | item | what the plan said | what the measurement said |
  |---|---|---|
  | 4 · reserve slots | make `~15` a real number | **54.** `pool-floor.sh`: 54 sustained all-green, 10 consecutive samples of 14,321 over 320.7 h. 15 was never measured (`cloud-ceiling-probe.sh:14`, `CONCURRENCY_PROGRAM.md:574` both say so) and a ceiling of 15 would refuse a fleet this box carries. |
  | 5 · quiet hours | none exist; the 08-10 peak sat inside the working day | the working day is **10:00→04:59 local** — 90.7% of 978 operator turn-attestations. The trough is **05:00–09:59** (5.0%). An assumed 08:00–20:00 would hold the reserve while the human sleeps and drop it while they work. |

  **Item 2's direction was forced, not chosen.** The operator's path GAINS the budget release;
  autonomy does not lose its own. Taking autonomy's away re-commits the architecture §8.5.2's
  retraction and §12.2's live measurement already refuted — a permanent refusal on an unattended
  recovery path is an outage, and it cannot self-clear because refusing spawns does not lower the
  loadavg the gate reads. §9's law binds both; `capacity_gate` never satisfied it. The operator's
  budget is 1 vs autonomy's 3: a human reads the refusal, so one delivers the whole message.

  **The beat is PRESENCE, never a CENSUS — do not charge a ceiling on it.** Measured: **zero beats
  younger than 60 s while ten sessions were live**, because `session-beat.sh` writes at turn
  boundaries and the busiest sessions are the quietest. Population comes from `ps` at the command
  position, counted as trees. And the consult is **ONE jq pass**, not `cb_system_live`'s per-file
  fork: 1,527 beat files × ~10 ms is >15 s of PreToolUse latency on the highest-volume spawn surface.

  🚨 **A BARE `[[ ]]` MID-TEST-BODY IS A NO-OP IN BATS — this cost a vacuous pass and it is the
  W3-shaped trap for whoever reads this next.** Probed against bats 1.13: `[ 1 -eq 2 ]` mid-body
  FAILS the test, `[[ "x" == "y" ]]` does NOT, so only the **last** assertion in a body binds.
  Case 29 **passed on pristine trunk** while its own captured output read `rc2=9` against an
  assertion of `rc2=0`. That is the same class as the predecessor's `live_workers`-without-`is_uint`
  harness, arriving through the assertion syntax instead of the extraction. All 13 occurrences here
  carry `|| false` (the idiom this corpus already uses in `agent-teams-enforce.bats`). **2,561 bare
  occurrences remain across `tests/*.bats`** — filed `67a7d78c1134`, out of scope for a spawn-side
  wave, but every one that is not the last command in its body is currently decorative.

  Two more found by this diff's own controls: the census returned a well-formed **`0` when `ps`
  produced nothing** — a dead probe reading as an empty fleet and therefore as infinite headroom
  (case 18 found it; a rows-counted positive control now returns rc 1). And **`extra-bang` was in no
  gate denominator** — an argv-surface refusal falling into `_fire_gate_of`'s fail-visible `*)` arm
  since it was added, which had `handoff-fire-capacity-gate` case 31 RED on trunk and therefore blind
  to every other unmapped reason. Both fixed in the same diff. `capacity-alarm.sh`'s own `census()`
  copy is left alone deliberately — converting a live 60 s daemon is its own item, filed
  `c4383f1c9172` — with the duplication pinned BEHAVIOURALLY by case 17 (both awk programs, one
  stubbed `ps` fixture), because this repo already learned that a literal-comparison ratchet detects
  drift it cannot prevent and says nothing about the lines it never compared.

- **2026-08-12 11:05Z — the stamp landed and it settles the hang: `autonomy-sweep` is acquitted, and
  the thing blocking the live layer was never one mechanism.** Stamp `bfcb13dac9c1` @ commit
  `33a8f41a86c1` — the first tree ever verified that CARRIES the band fix — ran the corpus in
  **3,562 s and named ZERO failing suites**. `tests/autonomy-sweep.bats` is not in `failing[]`.
  Backlog `35190812890d` is **closed on that evidence**; both of its `hung` stamps ran trees where
  `39388b17d` is not an ancestor, so neither had ever tested the fix they were being read against.

  🚨 **But the verdict is `cut`, not `green`, and the reason is a different mechanism entirely**
  (filed `b7252a3bb015`, with a falsifier attached so it re-asks itself). The runner's own line:
  *"corpus TRUNCATED — zero not-ok in a non-zero run — the run was KILLED by signal 15 from OUTSIDE
  this runner (sender unidentified)"*. Three things make this its own item rather than a footnote:

  - **It is the dominant verdict.** 28 `cut` · 6 `red` · 2 `hung` · **4 `green`** across the last 40
    stamps. A cut proves nothing, so no green is earned, so nothing reaching the live layer is
    full-suite-proven.
  - **The known cut engine was already fixed and this one survived it.** `c5e08d419` (C33, 2026-08-11)
    found the mutex comparing two locales' renderings of one instant — `ps -o lstart=` formats through
    `LC_TIME`, so a session-fired `--run-if-needed` read the launchd daemon's C-locale record as a
    *stranger*, reaped a LIVE holder, and started a second 441-suite verifier beside it. That fix is
    landed AND deployed (`LC_ALL` present in the live file), and today's cut had **exactly one**
    verifier — sequential runs, `09:05Z→10:02Z` then `10:03Z→11:02Z`, no overlap. So the double-corpus
    explanation is spent and the sender is genuinely unknown.
  - **The runner's own kills are excluded by construction.** `postland-verify.sh:2533/2540` set
    `cutby=preplan|stall` and unify onto rc 124; this run reported rc>128 with `cutby` empty, which is
    the branch at `:1502` that means *somebody else sent it*. `scripts/gate-cleanup.sh:188` is the only
    worktree-scoped TERM sender in the tree and it has **no automated caller** — it is named only in
    `ship-land.sh`'s advice and in `validate-bash.sh`'s denial message.

  ⚠️ **It is NOT currently blocking convergence, and the successor brief's premise that it is has
  expired.** `deploy-live.sh` reports `lag 5 commit(s) / 0h, inside the degrade budget (25 / 6h) — no
  advance, and none is due yet`. The live layer converges; it converges *degraded*, on 4-in-40 greens.
  Severity is "the full-suite claim is mostly unearned", not "the box is stuck".

  **Also corrected: `at-ceiling` is no longer evidence of a wedge.** The dispatcher read
  `verdict:"defer", reason:"at-ceiling", free_slots:0` again at `11:00:04Z` — but with
  **`live_workers:7`** against `ceiling:6`. That is an honest refusal over seven real workers, which is
  precisely what W0 built the distinction for; the wedge was `free_slots:0` with the slots held by
  *terminal* claims. Three of those seven are this session's own wave fires, which is the tension W3
  exists to resolve.

- **2026-08-12 11:00Z — successor re-verified W0 and fired W1/W2/W3; the hang is gone and the retire
  arm is now waiting on a live round trip that is ALREADY RUNNING.** Four findings, each from a live
  read rather than the predecessor's record:

  1. **The dispatcher has NOT re-wedged.** Its own IDL row at `10:41:58Z`:
     `verdict:"admit", free_slots:6, ceiling:6, live_workers:0, deferred:0`. The `at-ceiling` /
     `fired:0` state has not returned in the ~12 min of passes since.
  2. **`tests/autonomy-sweep.bats` no longer hangs.** The two `hung` stamps (`07:04Z` run_s 5,235 ·
     `08:39Z` run_s 4,144) both ran trees WITHOUT the band fix — `39388b17d` is not an ancestor of
     either. The postland run in flight since `10:16Z` IS on a tree that carries it
     (`33a8f41a8`), and its corpus `bats` **completed and exited** at ~36 min against the 69–87 min
     hangs. No stamp yet, so this is a strong indication and not the verdict; the verdict is the
     stamp for tree `33a8f41a86c1`.
  3. **`cc-cloud retire` is still unexercised, but the round trip that will exercise it is live
     now.** `session_01QmBkP5BH741J3BRw2A7F4a` (fired `10:26Z`) is `ALIVE`; a second, `…VA64gC…`,
     is `NOT-STARTED`. Both are post-fix dispatcher fires, which is itself evidence the venue-scoped
     ceiling works on the cloud side too.
  4. 🚨 **The retire arm is FORWARD-ONLY, and that is a second gap the W0 fix does not reach**
     (filed `b8a515115b2f`). 41 declarations · **0** `.retired` · 5 `.returned`. The 5 already-latched
     sessions short-circuit at `already returned` on every future sweep, and the ~24 that reached a
     terminal state before the fix landed have no path to release their claim at all. Cloud dispatch
     is *not* blocked by this today (it fired twice at 10:26/10:27Z), so it is hygiene, not an
     outage — but "the ceiling self-heals" is true only of round trips that START after the fix.

  **W1/W2/W3 fired, locus S, one dispatched session each, `--goal` armed on all three:**
  W3 capacity → pane 430 (`next4`, worktree `wave-w3-capacity`, goal verified at fire) ·
  W2 grouping → pane 432 (`next3`, `wave-w2-grouping`, goal verified at fire) ·
  W1 freshness → pane 431 (`next`, `wave-w1-freshness`, goal armed on the second attempt, see below).

  ⚠️ **W1's fire declared `FIRE FAILED — never engaged` and was WRONG** (filed `4043ab43bf4a`).
  `handoff-fire.sh`'s 120 s engagement window is sized for an idle box; at load 14.7 the cold-worktree
  session engaged LATE, after the window closed. The consequences all landed on a session that was
  working correctly: goal arming was skipped (`verdict=unreachable reason=never-engaged`), and
  fire-cleanup registered the pane as **task-less and reapable**. Recovered by confirming engagement
  from the pane's own transcript (150 rows, its own first line `"I'll start by reading the plan
  section that is my DoD"`) and having it arm its own goal over `cc-notify` — receipt `acked=1`,
  `goal-armed` present in its transcript. **The generalisable half: a fixed engagement bound sized on
  an idle box mislabels a healthy session as dead on a loaded one, and every downstream action it
  takes is destructive.** Same shape as W0's own bound-vs-band finding, one layer up.

- **2026-08-12 10:29Z — W0 IS LIVE, AND THE WEDGE IS BROKEN ON THE LIVE BOX.** The converger advanced
  (live HEAD `0ffe96995` → `3d4585168d`, lag 14 → 1) and all four markers are present in the deployed
  files — `cc-dispatch` venue-scoped ceiling, `cloud-return` retire + split `.woken` latch,
  `autonomy-sweep` band-fitted bound. The dispatcher's own journal, before → after:

  | ts | fired | admitted | deferred |
  |---|---|---|---|
  | 10:21:06Z | 0 | 3 | **320** |
  | 10:24:32Z | 0 | 4 | **320** |
  | **10:28:03Z** | **2** | 4 | **36** |
  | 10:29:44Z | 0 | 1 | **0** |

  and its decision rows moved from `live=6 free=0 reason=at-ceiling` to `live=0 free=6 verdict=admit`.
  **`free_slots` 0 → 6, `deferred` 320 → 0, and it fired.** That is the `🚀 → ✅` transition earned by
  observation in the enforcing store, not asserted off a git ref.

  ⚠️ **`.retired` markers are still 0** — the release path has not been EXERCISED yet, only deployed;
  no cloud session has reached the terminal branch since. That is the first thing to confirm once one
  does, because D3 is the arm that keeps the ceiling self-healing and it is the least proven of the
  three (its /Users/chrisren/.claude/bin/cc-bats coverage is structural, and the behavioural proof is a live round trip).


- **2026-08-12 — plan opened; W0 LANDED (`a984691f6`).** Recon by 5 read-only agents across staleness,
  consolidation, cloud readiness, the capacity bottleneck, and long-horizon execution; every figure
  re-derived against the live store and tree. **The dispatcher was found wedged dead** (`fired:0,
  deferred:318` for 1 h 34 m, no timeout) and unwedged: venue-scoped ceiling, terminal-session retire,
  close-aware latch with a bounded retry, and the fold's bound resized for the QoS band it actually
  runs in (measured foreground 17.5 s / **background 68.1 s** / utility 20.3 s against a 60 s bound —
  rc 124 on 10/10 runs, which made the documented `--apply` flip criterion unreachable). 16 cases,
  12 RED pre-fix; cloud-return 22/22.
  **Two premises corrected by measurement.** (1) Consolidation-as-dedup recovers 5–7% once and a fold
  removes zero rows by design — the pile is 93–95% distinct, so the lever is grouping-for-*execution*,
  not deduplication. (2) "~15 sessions" is folklore no code reads; the real bind is load 2.0/core, and
  the defect is that it is **unbounded for the operator's path, budget-released for unattended callers,
  and off entirely for the Agent tool.**
  **Named, not fixed here:** `link.py`/`prune.py` remain untracked (W2 item 1); the presence beat
  remains inert at every spawn site (W3 item 1); 248 rows remain unlabelled for venue (W2).

- **2026-08-12 — the deploy lane was unblocked from the OFF-BOX side, not by finding the SIGTERM
  sender (`cfe821e94`, `cedf79ed9`, landed `7df8cb7e2`).** Fired to hunt whatever kills the corpus
  `bats` run (`b7252a3bb015`); the shorter path turned out to be `deploy-live.sh`'s **T1H** tier,
  which advances on an off-box green with **no lag budget** and is blocked only by an on-box `red`
  — and our stamps are `cut`, which T1H treats as eligible (R6). T1H's producer,
  `.github/workflows/hermetic.yml`, had failed **8 consecutive runs**; the last off-box green was
  2026-08-10. The fold read 403/405 green, so **two suites** stood between this box and a live
  layer. Neither was a real regression, and both were instruments lying rather than subjects
  breaking:
  - `tests/worker-claim-gate-coverage.bats:247` — case 10 anchored the capacity term on
    `^…if ! CC_ADMIT_LOAD_TERM=off cc_capacity_admit`, the two tokens ADJACENT on one line. W3's
    `450a47c50` inserted `CC_ADMIT_SID=…` between them and wrapped the statement, so `$cap` came
    back EMPTY and the case reddened against a subject whose ordering property is intact
    (gate 113 < capacity 206). **A test calibrated to FORMATTING, failing on a reformat.**
    Re-anchored on the invocation itself — invariant under both an env prefix and a rewrap.
    RED-proved against the contract the suite records: M1 → 09/10/13 RED, M2 → 10 RED.
  - `tests/autonomy-sweep.bats:534` — case 25 copies the sweep into `BATS_TEST_TMPDIR` to mutate
    it, which breaks rung 1 of `autonomy-sweep.sh:103-113`'s lib ladder, so **the mutant was
    resolving `cc-common.sh` off the developer's live `~/.claude`** (rung 3). The suite pins no
    `HOME`, so it passed on a Mac and could never pass on a runner. Off-box the mutant died at
    `:112` with `FATAL — cannot source` before reaching `ladder_v2` at all. Fixed by symlinking
    `lib/` beside the mutant, pinning rung 1.
  🚨 **THE METHOD LESSON, and it nearly shipped a false verdict.** The first repro attempt FAILED
  to reproduce — case 25 passed with an empty `HOME`, which reads as "hypothesis refuted". It
  passed because an exported `CLAUDE_CONFIG_DIR` rescued **rung 2**. Only
  `env -u CLAUDE_CONFIG_DIR HOME=<empty>` reproduces: without the fix, the exact off-box `not ok`;
  with it, 49/49. *An environment hypothesis is only tested at an environment you actually
  cleaned* (memory: `hermetic-in-stubs-not-in-interpreter`). **The quieter casualty** is the
  second assertion: a script that dies at `:112` also posts nothing, so `[ "$(osa_posts)" -eq 0 ]`
  passed VACUOUSLY off-box — the control certified a silence it never observed.
  **Also corrected:** `b7252a3bb015`'s own falsifier was INVERTED — its probe exits 0 exactly when
  the newest stamp IS a cut, and `cc-backlog` reads exit 0 as *retract*, so the row refused every
  claim with `verdict=falsified` while the condition was fully present. Probe re-polarised.

- **2026-08-12 — the corpus was killing live processes as a side effect of verifying the tree
  (`6fd24a59f`); the corpus SIGTERM sender is still NOT identified.** `sweep()` calls
  `garbage_sweep` FIRST (`bin/cc-reaper:814`), and its seams live in `mk_garbage_fixtures`, which
  each garbage test calls itself — **never in `setup()`**. So ~90 `sweep --reap` cases read the
  real `ps -Ax` and issued real `kill -TERM`/`-KILL` at any ppid-1 process matching
  `bin/cc-reaper:344-349`; `orphan-bash` is *any* ppid-1 bash older than 600 s whose argv misses
  the `:339` whitelist, and `bats` is not in it. The suite is not in `host-suites.manifest`, so
  the postland corpus runs it. **Nothing recorded the victims** — `setup()` redirects
  `CC_REAPER_LOG` into the test tmpdir — which is exactly why the sender was unidentifiable after
  the fact. Confirmed live at 12:53Z: a read-only ppid-1 watcher of this session, age 883 s, was
  selected `orphan-bash` and killed **mid-measurement** — the arm reaped the instrument measuring
  it. Pinned `/dev/null` (the documented fail-open seam) in `setup()`; 99/99 green.
  **Do not read this as the cut engine.** The corpus's `cpid` is a `gtimeout` whose ppid is the
  live runner, so this arm cannot select it. `28 cut · 6 red · 2 hung · 4 green` over 40 stamps
  stands, and the honest state is: `scripts/gate-cleanup.sh:188` is confirmed to have **no**
  automated caller (only `ship-land.sh:1481` advice and `validate-bash.sh:558` deny text); jetsam
  sends SIGKILL not SIGTERM; `cc-reaper` is the only in-repo predicate that matches `gtimeout` /
  `bash` by orphanhood, and it needs `ppid==1`, which the corpus chain does not present.
  **The instrument is still the deliverable** — the runner deletes `RUN_TMP`
  (`postland-verify.sh:2629`) the moment it cuts, destroying the TAP that would name the test
  executing at kill time, and neither side records identity. Filed `a3a070520f3d`.

- **2026-08-13 — W4 off-box lane: five reds cleared and the generator closed. Row `3b22efbc2340`.**
  Seven commits, `cc4f5e150`..`b9bbc201e`. The three named reds were the sample; the deliverable is
  the admission rule, exactly as the wave lead framed it.

  **Five root causes, five different mechanisms, and NOT ONE was load** — which matters because the
  suite with the strongest load history had the crispest deterministic cause:
  1. `tests/typed-send-lint.bats` (`cc4f5e150`) — the **detector**, not the subject. `ctrl_only()`
     cut the payload at the first `[>|;&]`, but a redirection is `[0-9]*[<>]`, so
     `session send … $'\r' 2>/dev/null` cut to a payload whose last word was the fd number `2`, and
     a bare carriage return read as a typed command line. It survived because the selftest fixture
     and all four real handoff-fire sites spell it `>/dev/null 2>&1` — no digit before the operator
     — so no case in the suite could tell the two spellings apart, and they are the same send.
  2. `tests/land-gate-cas.bats` (`c5f1d1d56`) — a **stale assertion**. The 2026-08-12 damping commit
     reshaped the stranded-sweep verdict line into "on N of M local branch(es)" and did not carry
     the fixture. The sweep was working perfectly. Re-pointed and STRENGTHENED to two numbers (the
     walk and the reporting path), never relaxed — relaxing it is the defect it exists to prevent.
  3. `tests/boundary-handoff.bats` (`378072b52`) — a **wall-clock age asserted as a string literal**.
     `mk_btx 30` stamps `now-30`; the hook re-derives the age from its own `date +%s` after several
     git calls and a wrap-ledger run, so `30` was a coin-flip: **6/20 at idle, 10/20 under an 8-way
     load**. One mechanism explains all three prior convictions — the off-box red, the on-box red at
     02:02:19Z, and postland-verify's C29 note. Load raises the odds; it is not the cause.
  4. `tests/tsv-field-collapse.bats` (`e71ea0b66`) — **not ours, and it was blocking every land in
     the repo.** 0x1f is the second byte of the GZIP MAGIC (1f 8b), so the sentinel guard matched
     every vendored `.gz` by construction; sibling commit `28a8fba9b` added a `.gz` fixture for an
     unrelated reason and turned that guard standing-red on trunk. Fixed with `-I`, carried into the
     non-vacuity control too — a control running different flags from the scan it certifies proves
     nothing about that scan.
  5. `tests/cc-premise-supersession.bats` (`01d66b022`) — **the fixture's own subject was a random
     variable.** `cc-premise`'s `cited_shas()` skips an all-digit token by design (a bare number in
     prose is not a sha); the fixture minted a random `rev-parse --short=8`, and
     P(8 hex chars all digits) = (10/16)^8 = 2.33% over ~5 asserting fixtures ⇒ ~11% per run.
     Measured **1/8, 1/6, 1/12 red before; 0/40 outside bats; 20/20 green after**. The product is
     right; the fixture was a coin-flip. The failing TEST moved run to run, which is why it read as
     contention.

  🚨 **TWO PREMISES IN THE WAVE BRIEF WERE WRONG, and re-measuring them changed the fix.**
  - *"The fold counts a nonverdict into red, so it is stricter than the ladder it feeds."* It does
    not. `offbox-run.sh` orders `short ⇒ cut · red ⇒ red · cut/empty/missing ⇒ cut`, honouring R6
    exactly. The asymmetry is real but sits one layer LOWER: the workflow's conclusion is BINARY
    (green or nothing), so a `cut` and a `red` are indistinguishable to the puller and a
    merely-timing-out suite shuts T1H just as hard. The lead accepted this correction and amended
    the row.
  - *"New-suites-default-included is the defect."* It is not, and it was NOT reversed —
    `offbox-partition.sh` argues correctly that an inclusion list decays invisibly. The real defect
    is narrower and mechanical: **the growth side was actuated and the cure side was not.** The
    manifest names `offbox-run.sh census` as its anti-rot arm; that arm was a `workflow_dispatch`
    checkbox with no schedule, no consumer, and nothing that ever deleted a line.

  **What closed it (`13f09023d`).** `scripts/offbox-admission-lint.sh`, wired as ship-land's LAST
  gate arm: a /Users/chrisren/.claude/bin/cc-bats suite a land ADDS must be green under the off-box runner before it may land. It
  binds only on ENTRY to the partition — an existing suite is already measured hourly, and
  re-litigating it at every author's land is the fleet-wide stop §9 measured, not a gate. It costs
  one `git diff` on the common land, which adds no suite at all.
  It **runs the producer's own runner** rather than emulating one, via a new `offbox-run.sh suites`
  verb reaching the same `run_one` the CI shards use. Positive control taken BEFORE the gate was
  written, because a gate whose probe cannot fail is a vacuous pass: `boundary-handoff` was 35/35
  GREEN under ordinary `bats` and came back `red ok=34 notok=1` in 27s through that path —
  set-identical to that day's off-box fold.
  It **allows its own cure**: the refusal prints the repro command AND a paste-ready manifest line
  carrying the measurement it just took, so the manifest's every-entry-is-a-MEASUREMENT contract is
  satisfiable at land time instead of via an hour-long CI round-trip. A gate that cannot be
  satisfied gets routed around rather than obeyed.
  **The shrink half** got the actuator it never had: a daily census cron (selected on the cron
  EXPRESSION, so the selector cannot drift from the trigger) plus a verdict-job RELEASE list naming
  exclusions that came back green in a run that actually executed them — positive-evidence only, a
  partition run never executes them so their absence is never read as an acquittal.

  **The ratchet then shed its first line ever (`b9bbc201e`)**, and the arm named it rather than a
  human noticing: `tests/tsv-field-collapse.bats` had two recorded causes, both since fixed, and
  re-measured green 34/34. Exclusions 44 → 43, partition 415 → 419.

  **KNOWN LIMIT, stated rather than hidden.** The gate runs on THIS box, so it reproduces the
  environment axes (`env -i`, empty `$HOME`, no `~/.gitconfig`, `LC_ALL=C`, `TERM=dumb`, a fresh
  `TMPDIR`) and NOT the machine axes (no iTerm2, no launchd, a different scheduler band and brew
  prefix). A suite red off-box for one of THOSE reasons still passes here and still shuts the door;
  that class is what the exclusion manifest is for, which is why the shrink actuator is the other
  half of the fix rather than a nicety.

  **THREE DEFECTS THIS WORK FOUND IN ITSELF**, all before shipping, and all the same shape as the
  five above — an instrument wrong about a healthy subject:
  - The admission lint's own `--selftest` passed **VACUOUSLY**: load-time globals could not be
    overridden by the env prefix its own stubs set, so every refusing-direction case silently ran
    against the REAL partition and admitted suites that do not exist in it. Exactly the trap
    `test-walltime-lint.sh` documents for `horizon_years()`. Now call-time resolvers.
  - `resolve_bats()` skipped the live-layer wrapper but not `$BATS_LIBEXEC`, so a nested invocation
    picked bats' internal entrypoint, which emits no TAP and exits 0 — classified `empty`, turning a
    green suite into a refusal. The classification was right; the binary it was applied to was not.
  - The new release step used a flat `shards/*.tsv` glob where the fold uses `find`; the shard
    artifacts nest under `out/`, so it would have shipped as a **silent no-op** — the shrink arm
    reporting nothing, indistinguishable from finding nothing.
  And the RED-proof for cause 5 took **three** attempts, both failures recorded in the test because
  both are easy to write again: a literal `12345678` is unresolvable, so the finding is absent for a
  SECOND reason and mutating the skip leaves the test green; and grinding the LAST commit grinds the
  one touching `bin/other-tool`, which the item does not cite, so the landed-diff conjunct rejects
  it whatever its digits. Only grinding the SUBJECT commit isolates the variable.

---

## THE BIGGEST SINGLE LEVER IS NOT AN EFFORT — it is the `re-land` generator (measured 2026-08-13, THE LOCAL DRAIN recycle #1)

**Do not walk the ten master efforts smallest-first without reading this.** The effort order banks
completed efforts early, which is right — but it is aimed at the wrong population. Measured against
the live store while working effort 2:

| Fact | Number |
|---|---|
| non-cloud open rows | **472** (was 470 at effort-2 start — it went UP while a drain was closing rows) |
| open rows whose title starts `re-land ` | **60** — and **all 60 are non-cloud, i.e. entirely the drain's burden** |
| distinct branches those 60 name | **26** ⇒ **34 rows are duplicates of a row already in the store** |
| of those 26 branches, no longer existing on origin OR locally | **18** |
| rows attributable to those 18 vanished branches | **46** |

**`re-land` rows are ~12.7% of the entire non-cloud backlog, and 46 of them point at branches that
are GONE.** For scale: the DoD is *fewer than 50 non-cloud rows total*, and this ONE auto-generated
class is 60. **The target is arithmetically unreachable without addressing it**, however many master
efforts get drained.

**It is a live, self-feeding loop, not a historical pile.** `ship-land` mints a row on a FAILED
sibling land, so the same stuck branch re-mints on every retry: `mcp-w3-no-inherit` ×6,
`falsifier-emission` ×4, `claude/fire-20260812T172113Z-3600-1` ×4 (04:51 and again 05:43 while this
was being written). In the 12 h to 2026-08-13T05:50Z, **10 of the 18 non-cloud filings were
auto-minted re-land rows — 56%.** Lands fail because the box is saturated, so **load manufactures
backlog faster than a drain closes it.** The predecessor measured the symptom (store 470→470 flat
across 2 real closes); this is the generator behind it. The remedy row for the swallowed falsifier
attach, `b15a2984d134` (`ship-land.sh:854`), is still open.

🚨 **DO NOT BULK-CLOSE THE 46. "Branch GONE" has two opposite readings** and the store cannot tell
them apart: gone-because-its-content-LANDED (the row is litter — close it) versus
gone-because-the-work-was-LOST (the row is the only surviving pointer — closing it strands real work
permanently, which is exactly the failure `re-land` exists to prevent). Adjudicate **per branch, by
CONTENT**, never by a commit count and never by the branch's absence:
`git log --all --diff-filter=A`, ref-containment, and `git ls-tree origin/main -- <paths>` per path
(memories: `landedness-over-commits-is-blind-to-staged-content`,
`search-branch-graveyard-before-building`, and this repo's own rule that a count reads 0 after a
sibling rebase and proves nothing).

**Recommended next action, ahead of resuming the master efforts:** (1) close the **34 duplicate**
rows against their surviving sibling — that is pure store hygiene needing no content adjudication,
only a same-branch match; (2) adjudicate the 18 GONE branches by content, closing the litter and
KEEPING any whose work is genuinely unlanded; (3) only then fix the generator (`b15a2984d134`), so
the class stops refilling. Steps 1-2 are worth up to ~46 rows — more than twice the whole of effort 2
— and step 3 is what stops the store rising underneath every future effort.

### CORRECTION to the section above, same session — the 46 are NOT mostly litter, and bulk-closing them would have stranded 11 branches of real work

The recommendation above ("steps 1-2 are worth up to ~46 rows") was written from a COUNT. Then the
content adjudication ran, and it inverts the expectation. **Recording the correction rather than
editing the claim away, because the wrong instinct is the reusable lesson.**

**The predicate matters, and two obvious ones are wrong.** ❌ *branch absence* — a deleted branch says
nothing about whether its content landed. ❌ `git diff <pinned-sha> origin/main` — that lists every
change siblings landed since, so a long-landed branch still "differs" and reads as unlanded; it was
tried here and produced exactly that false signal. ✅ **`git merge-base --is-ancestor <final pinned
head> origin/main`, then the same test on EVERY distinct pinned sha** (a retry loop pins a different
sha per attempt, and an amend/rebase between attempts can orphan an earlier one).

**Result over the 18 vanished branches (46 rows):**

| Verdict | Branches | Disposition |
|---|---|---|
| **LANDED** (every distinct pinned sha contained) | **2** — `mcp-w3-no-inherit`, `w2-cloud-rails` | **9 rows CLOSED** with per-sha evidence |
| **UNLANDED** (final head not an ancestor of trunk) | **11** | 🚨 **KEEP.** `audit-tests` · `cloud-pipeline` · `deskless` · `detector-derive` · `falsifier-emission` · `fix-goal-bg-bash-guard` · `land-arch-p0-selfmeasure` · `land-arch-p2-shiftleft` · `probe-corpus` · `wt-6110fc45141e` · `wt-7ff1b6f5ddbb`. Each row is the **only surviving pointer** to real work — closing it strands that work permanently, which is the precise failure `re-land` exists to prevent. |
| **NO PIN AT ALL** (no branch AND no `refs/land/failed/*`) | **5** | `feat/start-latency-router` · `feat/workflow-harvest` · `fix/backlog-ratchet-readiness-w0` · `fix/curl-gate-worktree-scope` · `fix/resume-path-width-asis-tombstone`. **The worst state and the least visible:** the row names work with no pointer left in this clone. Needs the graveyard sweep (`git log --all --diff-filter=A`, ref-containment) before any disposition. |

**So the lever is real but it points the other way: ~11-16 of these rows are protecting genuinely
stranded work, and the store is UNDER-counting the problem, not over-counting it.** Only 9 of 46 were
litter. **Do not close a `re-land` row without the per-sha ancestry check above.**

**Worked example of the subject-vs-diff trap, from this adjudication.** `w2-cloud-rails` had 3 pinned
shas; two were contained and `bc7290e3f` was NOT — while carrying a commit subject *identical* to the
contained `43e156a1b`. Closing on the matching subject would have been luck, not evidence. The diff
settled it: identical patch-id (`6c7d8e578cd942336e5ff291ffd0c2f774a589c6`), same three files, same
122 insertions / 12 deletions, and `git cherry origin/main bc7290e3f` marked `-` (equivalent patch
already upstream) ⇒ a pre-rebase duplicate, safe. Had the patch-ids differed, that one sha alone would
have made all three rows KEEP.

**Store effect, measured:** non-cloud **472 → 463**. First genuine net decrease of this mission — the
predecessor's two real closes netted 470 → 470 because sibling intake cancelled them.

### The generator files rescue rows for work that needs no rescue — measured on a row it minted the same hour

Closing the surviving-branch cases produced a sharper indictment than the vanished-branch ones did.
`cfa642b48fc7` was auto-minted at **2026-08-13T05:07:38Z** — during this very session — reading
*"re-land w4/gc-activation-path … ship-land exited 5"*. Its branch tip is **`645b56ebd`**, which was
`origin/main`'s **head** at that moment (it is the base this session's own land fast-forwarded from:
`645b56ebd..9625360f4`). **The branch was identical to trunk when the row was filed.** There was
nothing to re-land, and the row was stale before it was written.

So the generator's precondition is *"my land exited non-zero"*, never *"is this content actually
absent from trunk?"* — and a land can exit non-zero for reasons that have nothing to do with the
content arriving (a sibling landed the same work first; a retry succeeded; the gate was cut; the
process was SIGTERMed, `cdeb77e34952` exit 143). **Every one of those mints a row asserting work is
stranded when it is not.** Three of the twelve re-land rows closed this session were of exactly this
shape (`fix/smart-allowlist-narrow`, `w4/gc-activation-path`, `w4/gc-franchise-reland` — all
local-only branches whose tips were already contained).

**The one-line fix shape, for whoever takes `b15a2984d134`:** before filing, test
`git merge-base --is-ancestor <branch tip> origin/main` and file NOTHING when it is contained. That is
the same predicate this session used to adjudicate 26 branches, it is cheap, and it is the difference
between a row that protects stranded work and a row that is litter on arrival. **Do not instead
de-duplicate on branch name** — the retry loop legitimately pins DIFFERENT shas per attempt
(`mcp-w3-no-inherit`'s six rows hold four distinct commits), so name-dedup would discard real
pointers.

**Session tally at this point:** closed **14** (2 effort-2 rows + 12 re-land rows), filed **1**
(`782607797fc5`, operator-gated). Non-cloud store **470 → 460**. Every close carries per-sha content
evidence; none was closed on a count, a subject line, or a branch's absence.

### THREE STACKED INSTRUMENT BUGS, one FALSE CLOSE, and the corrected adjudicator — read this before touching another `re-land` row

The adjudicator above was rebuilt **three times**, and *each broken version returned a confident,
plausible, wrong answer.* One of them caused a **false close of a row protecting real unlanded work.**
Recording the whole chain, because the failure is invisible by construction: a glob that matches
nothing is indistinguishable from a branch that has no pins.

| # | The instrument | What it reported | Why it was wrong |
|---|---|---|---|
| 1 | `git for-each-ref 'refs/land/failed/*-<branch>'` | 5 branches have **NO PIN AT ALL** — "the worst state, no pointer left" | **git's `*` does not match across `/`.** Every branch whose name contains a slash reported zero pins. Perfect correlation: all 5 "NO-PIN" branches were slashed, every cleanly-resolved branch was not. |
| 2 | enumerate all refs, suffix-match the literal branch name | still **zero pins** for all 8 slashed branches | the refs **SANITISE `/` to `-`**: `fix/curl-gate-worktree-scope` pins as `refs/land/failed/<stamp>-<uuid>-fix-curl-gate-worktree-scope`. The literal name with its slash cannot appear. |
| 3 | **normalise `/`→`-`, THEN suffix-match** ✅ | pins found for 7 of 8 | the working form. Also add the `git cherry` patch-equivalence arm — a sha can be absent from trunk yet already applied upstream under a different hash. |

🚨 **THE FALSE CLOSE.** Under instrument #1, `fix/smart-allowlist-narrow` showed "all 1 sha(s)
contained" — the *1* being its branch tip, because its pins were invisible. Its row `59a83d4983f9` was
closed with evidence asserting *"every distinct pinned sha … was checked and all are contained."*
**That sentence was vacuously true and materially false: the glob matched nothing, so nothing was
checked.** Instrument #3 shows the branch has **2 pinned shas, `33b268d27` and `aa0e73958`, and
NEITHER is contained nor patch-equivalent upstream.** The work is genuinely unlanded and that row was
its only surviving pointer. **Reopened with `cc-backlog reopen … --force`.** The other two closes in
that batch re-verify as correctly landed.

**The transferable rule: an empty result from a matcher is not evidence of absence until the matcher
has been shown capable of returning a hit.** A positive control costs one line — match a branch you
*know* has pins — and it would have caught this at the first attempt instead of the third. Same class
as this session's `grep -r` over `~/.claude` returning empty because those are per-file symlinks it
will not follow.

**Corrected verdicts over the 8 previously-unresolved branches:** LANDED (rows closed) —
`feat/start-latency-router`, `fix/backlog-ratchet-readiness-w0`, `fix/curl-gate-worktree-scope`,
`fix/resume-path-width-asis-tombstone`, `w4/gc-activation-path`, `w4/gc-franchise-reland`.
**UNLANDED — KEEP** — `fix/smart-allowlist-narrow` (reopened), `feat/workflow-harvest` (`96bb204e5`).

**Session totals:** closed **22**, reopened **1**, filed **1**. Non-cloud store **470 → 454**. Every
surviving `re-land` row now carries a per-sha content verdict, and every close names the shas it
rests on.

### BUG #4 and the final verdict: 34 of the 43 remaining `re-land` rows protect GENUINELY UNLANDED work

A fourth instrument bug was caught **before** it closed anything, and it is the subtlest of the four.
The patch-equivalence arm was written as *"landed if `git cherry origin/main <sha> | grep -q '^-'`"* —
i.e. **landed if ANY commit is upstream.** But `git cherry` lists **every** commit from the merge-base,
marking each `-` (equivalent upstream) or `+` (missing). A five-commit branch with one landed commit
would clear on the strength of that one. **Correct test: no `+` line at all.**

Tightening it **flipped three branches from LANDED to UNLANDED** — `audit-tests` (2/2 missing),
`wave-offbox-green` (3/4), `wt-6110fc45141e` (3/3) — which would have been **six more false closes**
on top of the one already made and reopened.

**The four bugs, as a checklist for anyone re-deriving this** (each returned a confident wrong answer):

1. `for-each-ref 'refs/land/failed/*-<branch>'` — git's `*` does not cross `/` ⇒ slashed branches read as **no pins at all**.
2. literal suffix match — the refs **sanitise `/`→`-`** ⇒ the literal name can never appear.
3. checking only the **final** pinned head — a retry loop pins a different sha per attempt and an amend can orphan an earlier one ⇒ check **every distinct** sha.
4. `git cherry … | grep '^-'` — clears a branch on ONE landed commit ⇒ require **no `+`**.

Plus the gate that makes the whole thing trustworthy: **a POSITIVE CONTROL on the matcher** (a branch
known to have pins must return >0) — because an empty match and a true absence are otherwise
identical, which is what produced the false close.

**FINAL VERDICT over the 43 rows / 19 branches:**

| | Rows | Disposition |
|---|---|---|
| **LANDED** — every sha fully upstream | **9** | CLOSED (`claude/fire-20260812T040633Z-32515-1`, `deskless`, `land-arch-p0-selfmeasure`, `local-drain`) |
| **UNLANDED** — at least one sha missing from trunk | **34** | 🚨 **KEPT.** These are not litter. They are the surviving pointers to real stranded work across 15 branches, including three live `claude/fire-*` branches carrying **14, 6 and 3** missing commits. |

**So the class inverts the intuition it started with.** The opening hypothesis was *"60 auto-generated
rows, mostly duplicate noise, worth ~46 easy closes."* Measured: **26 of 60 were litter and closed;
34 remain and every one is protecting work that is genuinely not on trunk.** The `re-land` mechanism
is doing its job — the store is **under**-reporting stranded work, not padding the count. The thing to
fix is the generator's *precondition* (`b15a2984d134` — test containment before filing), not the rows.

**Session totals:** closed **31**, reopened **1** (a false close, caught and retracted), filed **1**
(operator-gated). Non-cloud store **470 → 446**. `re-land` rows **60 → 34**. Every close names the
shas it rests on; not one rests on a count, a subject line, or a branch's absence.

### 2026-08-14 — THE LOCAL DRAIN recycle #2: the `re-land` generator's precondition is closed (`b15a2984d134`, landed `40613b786`)

The previous entry ended by naming the one thing left in the class: *"the thing to fix is the
generator's precondition — test containment before filing — not the rows."* That is now done, and
the shape of the defect is worth keeping, because it is the third instance in this plan of an
instrument whose answer was thrown away rather than wrong.

`land_failure_inbox()` attached the content oracle with `>/dev/null 2>&1 || true`. `falsify` has two
informative outcomes and the filer read **neither**. rc 5 is a REFUSAL — the probe already exits 0,
so the oracle says the ref's content is ALREADY on trunk and the land died *after* its content
landed. Discarded, that refusal still leaves the row filed carrying `falsifier=NONE`, and a
probe-less row is in **neither** of the retractor's buckets: it can never self-retract and nothing
reports it. So the S3 acceptance figure — "the retractor covers 14 of 23" — was measured over rows
that HAD probes, and was blind to the population it was leaking.

**The fix reads the rc.** rc 5 CLOSES the row with its evidence; every other non-zero is REPORTED by
row id. Containment is therefore tested before the row persists, paid for with the **one oracle run
`falsify` already makes** — deliberately not a second pre-check ahead of the filing, because this
handler may be running under a signal and must not double a fetch. Exit-code discipline is
unchanged: every branch returns 0.

**Two things the land itself taught, both cheap to re-learn the hard way:**
- The dead-assertion ratchet caught a defect in the NEW test, not the subject: `! grep -q …` is
  unreachable by errexit, so the negative half of the new case could never have failed.
  `scripts/bats-assert-liveness-fix.py` emitted the correct `! A || false`, and it was
  **mutant-proved in both directions** before being believed (asserting the absence of a token that
  IS present reds at exactly that line). A first mutant attempt via `perl -0pi` silently matched
  nothing and the suite went green — the vacuous-pass trap, caught only because the substitution
  printed no anchor. **Assert the mutant APPLIED before reading its verdict.**
- `"$bl" done …` must be QUOTED: bare, shellcheck reads `done` as an unterminated loop body (SC1010)
  and the gate reds on the file. Runtime is fine either way, which is precisely why it survives a
  local test run and dies at the gate.

**State at this recycle.** `master-stranded-work` 7 → 6 live rows: **4 blocked** (two genuinely
operator-only and web-gated — the GitHub server-side author-email ruleset `8f4eae55a0c7` and the
Claude GitHub App install `1dca461d4b90`; plus reso's worktree-local `.eslintcache` `216f429128a2`
and the 122-orphan worktree sweep `475b43aacbf2`) and **2 open** — `ff0b5cf4528b` (limit-recover
engagement is DETECT-ONLY; carries a deferred blast-radius decision, so read it for a ⛔ before
coding) and `8ad4b02602dc` (no wake path for an idle headless session; stream-json needs a
stdin-FIFO writer). Live store 528. Effort order by size is unchanged: after this one,
`master-verification-integrity` (13) → `master-operator-gated` (25) → `master-account-facts` (26) →
`master-enforcing-store` (32) → `master-session-lifecycle` (41) → `master-fleet-footprint` (56) →
`master-product-repos` (57) → `master-fire-gate` (58) → `master-convergence-deadlock` (84).

**Live-layer note, so the next session does not re-diagnose it.** `deploy-live.sh` declines with
*"already deployed — live layer is at the newest deployable commit `95a3caf82505` (2 un-stamped
commit(s) above)"*. That is the standing GREEN-stamp fail-closed (`35190812890d`), not this diff:
the land makes no full-suite claim and only the background `postland-verify` stamp moves the marker.
The lag is **2** and this diff ADDS no file, so it rides its existing per-file symlink inside the
converge budget — `✅` with a note, not `🚀`. A land that ADDS a file gets no budget and would breach
at a lag of 1.

### 2026-08-14 (same session) — the drain walked into a LIVE 24-day false alarm, and the guard that should have caught it was scoped to a directory

Reading `master-stranded-work`'s next row (`ff0b5cf4528b`, limit-recover's DETECT-ONLY engagement
audit) meant reading the daemon's log, and the log was not saying what the row said. **1,797 of
2,211 lines (81%) are one identical line** — `resume spawn failed (LR_POLLER_SPAWN=auto; no GUI and
no tmux)` — across **11 sids over 24 days**, one sid retried **380 times**, still firing every ten
minutes today. The detector `ff0b5cf4528b` is about has **never fired once**, because a spawn that
fails releases its claim immediately and the engagement audit only ever sees claims that survive.

**The line was false about the box.** `/opt/homebrew/bin/tmux` has been installed throughout.
`com.reso.lr-reset-poller.plist` sets no PATH, launchd's default is `/usr/bin:/bin:/usr/sbin:/sbin`,
and Homebrew is not on it — so `spawn_tmux`'s opening `command -v tmux || return 1` was always
false. LR-m's contract, *"GUI unavailable → tmux rather than stranding the resume"*, had **never
once been honoured in production** since it shipped.

**Three things generalise, and the third is the one to carry:**

1. **The guard is what hid it.** A bare `tmux` would have been a loud 127. `command -v tmux ||`
   turns identical PATH blindness into a SILENT capability loss — which is exactly
   `unattended-path-lint`'s own `guarded` finding class ("it will not crash, but the capability is
   silently lost, which for a gate or an actuator is failing OPEN").
2. **The same file had already learned this lesson and applied it to a different binary.**
   `LRP_TIMEOUT_BIN` three lines above carries the absolute Homebrew ladder; `tmux` never got it
   (memory: `corrected-instrument-can-lie-again`). The fix is that ladder, plus an ERROR line that
   reports the RESOLUTION (`tmux=<path>` vs `tmux=unresolved`) instead of asserting a fact about the
   box it never checked. Landed `b2f192698`.
3. 🚨 **THE POPULATION, NOT THE RULE, IS THE HOLE.** `unattended-path-lint` exists for precisely
   this class and runs clean. It enumerates **`"$root"/launchd/*.plist`** — 25 plists — and this
   job's plist is committed at **`scripts/limit-recover/`**, tracked and live-loaded but outside the
   directory the lint globs. Measured further: **12 LaunchAgents are installed with no plist in
   `launchd/` at all** (`com.reso.*` ×5, `gl.reso.*` ×2, `com.claude.accounts-keepwarm` / `cc-gc` /
   `relogin`, `com.chrisren.restic-claude-archive` / `verify-2114-archive`) — so the ENFORCING store
   (`~/Library/LaunchAgents`) and the AUDITED store disagree by 12 jobs, and every one of them is
   unjudged. Filed **`3f5ea840b296`**, with a falsifier that retracts when the lint's own `--list`
   names this job. Deliberately NOT folded into the instance fix: widening a **land-blocking**
   ratchet's population needs its own grandfather pass, which is a wave, not a follow-on.

**Two land-gate lessons, both about the tests rather than the subject** (the ratchet caught both
before trunk did): a bare `! grep -q …` is unreachable by errexit, and `A && false || true` is worse
— the `and-absorbed` family, where BOTH branches reach true. `scripts/bats-assert-liveness-fix.py`
emitted the right per-class form each time, and each was **mutant-proved in both directions** before
being believed. Do not trust the analyzer alone; and **assert the mutant APPLIED** before reading
its verdict — a `perl -0pi` substitution that silently matched nothing produced a green run that
proved exactly nothing.

**Session tally so far: closed 1 (`b15a2984d134`), filed 1 (`3f5ea840b296`), landed 3
(`40613b786`, `e215abb6d`, `b2f192698`).** Net +0 on the store and one live alarm silenced. NOTE for
whoever files under a master effort: **`cc-backlog add --condition <slug>` re-keys the id to
`hash(project+condition)`**, so it lands on the effort's EXISTING row and appends an `update` that
REWRITES its title. That happened here to `3ec6c070f52f` and was restored from the append-only trail
in the same minute. File without `--condition`; the master conditions were applied by `link`, not by
`add`.
