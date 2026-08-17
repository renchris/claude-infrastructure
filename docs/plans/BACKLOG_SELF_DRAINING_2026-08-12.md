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

### W1 · Freshness — a currency verdict for every row, on a schedule ✅ DONE (`044a3ebb`)

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

- **2026-08-12 — W1 LANDED, all six items. Row `b585e86ea4e4`.** One commit (`044a3ebb`) across
  `bin/cc-backlog`, `bin/cc-premise`, `scripts/autonomy-sweep.sh`, `scripts/backlog-ratchet.sh`,
  plus `tests/backlog-freshness.bats` (25 cases) and 3 caller-proof cases in
  `tests/autonomy-sweep.bats`. Test hardening followed in `4059094a` (six assertions were
  decorative — a bare `[[ ]]` off the last line is not reached by errexit).

  ⚠️ **This entry cited `cf0f11a4b` until 2026-08-15, and that sha is not on trunk and never was** —
  it was the pre-land sha on the wave branch, which `/ship`'s rebase replaced with `044a3ebb`. A
  successor auditing this row could not resolve the cited object at any fetch depth, which is the
  exact dead end the dispatch brief's FIRST STEP warns about (*"check the cited sha against
  origin/main"*). **Cite the LANDED sha, never the one your own branch produced** — verify with
  `git merge-base --is-ancestor <sha> origin/main` after the land, not before it. W2's `1b044624d`
  resolves fine, so this was W1's marker specifically, not a convention-wide defect.

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

  ⚠️ **2026-08-15 — that "true regression" reading was PARTLY WRONG, and the wrong part was the
  instrument** (item `e08ad9ab1ff6`, the row this ratchet's own RED files). The numerator counted
  `select(.falsifier != "")` — the STORED field alone — while the consumer that actually re-checks a
  row, cc-premise `assess`, composes THREE arms and records which fired in `probe_kind`: `stored`,
  `derived-plan`, `derived-postland`. Two auditors, one population, one question, different answers
  (memory: `sibling-auditors-must-share-the-state-model`).

  **It inverted the alarm rather than merely blurring it.** `post-land RED:` rows store no probe ON
  PURPOSE — cc-premise derives that predicate, and postland-verify's `--falsify-red` header records
  that storing an equal probe there would "shadow a tested, documented arm and buy nothing but a
  second implementation to keep in sync". postland-verify is also the fleet's highest-volume
  generator (one row per failing suite per red run, cap 25). Those rows sat in the DENOMINATOR and
  could never reach the NUMERATOR, so **every red trunk mechanically depressed coverage** with no row
  anywhere losing the ability to re-check itself — and `--assert` went RED on that. Its remediation
  line then said *"Add `--falsifier` to the generator that regressed"*, which for that population is
  precisely the change its sibling documents as harmful. Measured on a 50-row fixture (25 postland +
  25 stored): the ratchet read **50.0% — "25 of 50 can re-check themselves"** while `cc-premise
  check` returned `verdict=falsified` for those same 25 rows, having actually retracted them.

  **Fixed by the cure this file already applied once:** ONE ARBITER PER FACT. The `freshness` block
  asks cc-backlog rather than re-deriving the fold; coverage now asks the new `cc-premise coverage`
  (capability census — classifies by arm and by source, executes no probe, shells out to nothing)
  rather than re-deriving the predicate. `denominator_version` → **3**, because the NUMERATOR changed
  and a v2 mark measures a different thing. The RED now **names the generator** whose rows are
  uncovered, and says that a generator absent from that list must NOT be handed a stored probe.
  Fail-open is to **UNKNOWN, never to the stored-only count** — that number is lower by construction,
  so a silent fallback would red against a mark recorded from the composed one and be
  indistinguishable from a true regression (memory:
  `sensor-default-off-makes-blindness-the-shipping-path`).

  **Red-proof:** 3 mutants, each killed — numerator reverted to stored-only (5 cases across both
  suites), status folded from `build_index` instead of cc-backlog (3 cases — the third-auditor bug
  the first draft of the fix actually shipped and the suite caught), and the ratchet silently falling
  back to stored-only instead of UNKNOWN (1 case). 12 new cases in `tests/cc-premise-coverage.bats`,
  5 in `tests/backlog-ratchet.bats`.

  **Still the generators' job (master M2), unchanged:** rows filed by an agent at a hook's prompt
  (`dispatch-assert.sh`, `completion-assert.sh`) carry no probe and no arm derives one for them.
  Those are genuinely uncovered and the per-source breakdown now names them instead of leaving the
  reader to find them.

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

  **FIXED 2026-08-14 — `cc-backlog link --plan <file|->`, and W4 no longer has to budget an hour for
  its grouping pass.** The quadratic term was the FOLD, not the append: the per-row verb asks the
  store two whole-ledger questions (`has_id` over every raw record, then the full `fold`), so an
  N-row plan folded a ledger that its own N link records were growing. `--plan` folds ONCE for the
  whole plan; `link.py --run` now makes exactly one call instead of N. **Re-measured end-to-end on
  this pass's own shape — 418 rows against a 2400-line store: 1.28 s, conservation=ok, idempotent
  on re-run.** Against the >1 h original that is the difference between a grouping pass being a
  wave and being a command.

  Three decisions in it are worth carrying forward, because each one is a rule this store keeps
  re-teaching:

  * **The WRITE stayed per-row, deliberately.** Only the fold was batched. Bare `O_APPEND` is atomic
    at these line lengths and that is what keeps ~14 concurrent writers coordination-free; batching
    the write into one multi-KB block would buy nothing measurable and would hand a stdio flush the
    chance to land mid-record. Optimise the term you measured, not the one next to it.
  * **Failure classes split on whether they can RACE.** A malformed plan (an unstable slug, one id
    asking for two conditions) is refused WHOLE before any write — knowable with no reference to the
    store, identical on the re-run, and a half-applied plan cannot be told from a completed one. A
    store refusal (unknown id, a row a sibling conditioned first) is per-row and never fatal (rc 5,
    verdicts name each), because the ledger moves under any pass long enough to need this verb.
  * **An EMPTY plan is rc 0, not a refusal — and getting that backwards is what the first cut did.**
    "Nothing left to do" is the NORMAL end state of an idempotent writer, so refusing it turned every
    re-run of `link.py` whose candidates were all already conditioned into an exit-1, and three
    tests/backlog-grouping.bats suites went red. Unlike `validated --batch`, an empty pass here
    erases nothing, so it needs no refusal to stay safe. A plan that carried LINES and could use none
    of them is still rc 2 — that one is a producer bug.

  ONE ARBITER (`link_apply`) owns every guard and the single-row form is a one-row plan through it,
  so its published rc contract (3 unknown · 4 already-conditioned · echo the id otherwise) is a
  rendering of that row's verdict rather than a second copy of the rules — the same
  make-the-actuator-the-arbiter discipline that already makes `backfill --apply` delegate to `link`
  instead of hand-rolling an append. Pinned by `tests/cc-backlog-link-plan.bats` (24 tests), and the
  cost property is pinned **structurally, not by wall clock**: a shimmed `jq` counts the real folds,
  so "3× the rows must not cost 3× the invocations" is deterministic on any hardware, red-proved by
  re-introducing a per-row fold, and paired with a CONTROL asserting the per-row form still does pay
  per row. A timing assertion on shared CI would flake, get muted, and defend nothing.

  **Still per-row, and deliberately left so:** `cmd_backfill --apply` loops the single-row verb. It
  halved (2 folds/row → 1) for free with this change and its population is bounded by the mechanical
  fold's floors, so it never reached wave scale — but it is the same defect class and the same
  `link_apply` is now sitting there to take it. Filed rather than folded in, to keep this diff inside
  its frozen scope.

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

### 2026-08-14 — THE LOCAL DRAIN recycle #3: the actuator the audit was missing, and the fix that landed but never reached the box

Two things came out of `ff0b5cf4528b` (limit-recover's DETECT-ONLY engagement audit), and the
second one is the more transferable.

**1. THE ACTUATOR — landed `a346b6993`.** The row carried a deliberate deferral from `4ba91ad95`
("adding an actuator to a live unattended limit-recovery daemon is a different decision with a
different blast radius"), so the question was *which* direction, not whether. **The daemon's own
log answers it.** 1,800 of `poller.log`'s lines are one identical `ERROR … resume spawn failed`;
a failed spawn releases its claim immediately (so the 15-minute TTL never brakes it) and leaves
the record PARKED, so the very next tick re-fires it — without bound. **The defect was never "a
fire that did not work is not RETRIED"; it is "a fire that cannot work is retried forever."** So
the safe actuator is the one that fires LESS, and this one counts consecutive failed fires per sid
and drops the sid from CANDIDACY at 3, for 6 hours, reporting once.

🚨 **The audit's population was EMPTY, and the reason generalises.** `NOT-ENGAGED` = 0 against
`RESUMED` = 2 over 24 days. The audit walks CLAIMS, and the 1,800-strong failure mode **deletes
its claim on the way out** — so the arm was structurally blind to the only failure that was
actually happening (memory: `cap-whose-population-is-empty`). A detector wired to the surviving
half of a lifecycle measures the half that does not fail.

Two design notes worth keeping. **The filter is at candidacy, not at the fire**: `MAX_PER_WORKTREE`
is 1, so a latched sid left in the pool takes its worktree's only slot and is *then* skipped —
starving the worktree instead of braking one session. And §2 keeps a second check anyway, ahead of
the winner test, because a sid filtered out of selection reaches `sel_reason`'s empty answer and
would be retired as "not selected" — a misattribution, and a permanent one. **A mutant of EITHER
site reds A9**, which is why that case exists.

**One fix the counter forced:** `claim_sid` now re-arms the audit's once-per-fire damping marker.
That marker was only ever cleared by an ENGAGEMENT — which a session that keeps wedging never
reaches — so the second wedge of a sid was silent forever, and the count could never pass 1 on the
wedge path. **A damping marker keyed on recovery cannot damp a thing that never recovers.**

**2. 🚨 THE PREDECESSOR'S FIX LANDED AND THE BOX NEVER GOT IT — measured, not inferred.** The
previous entry closed on "one live alarm silenced" (`b2f192698`, the tmux absolute-path ladder).
It is not silenced: `poller.log` was still emitting the pre-fix line — *verbatim*, including the
`no GUI and no tmux` text the fix REPLACED — at 09:25 today, ten minutes before this was written,
and the ERROR count had moved 1,797 → 1,800.

The chain is short and worth stating because every claim about this repo's "live" state runs
through it. The LaunchAgent execs `~/.claude/scripts/limit-recover/lr-reset-poller.sh`, which is a
**per-file symlink into the shared checkout's working tree** — so the live bytes are whatever
`~/Development/claude-infrastructure` currently has checked out, and that tree was **5 commits
behind `origin/main`**. `deploy-live.sh` declines to advance it ("already deployed … 5 un-stamped
commit(s) above") because of the standing GREEN-stamp fail-closed `35190812890d`. So a land that
edits a live daemon is **`🚀` in fact and `✅` on paper**: the file exists, the symlink resolves,
every structural check passes, and the box runs last week's version of it.

**The falsifier that settles it in one line, for any future claim of this shape** — do not compare
commit counts, compare the BYTES the box will execute against the fix:

```bash
grep -c 'LRP_TMUX_BIN' "$(readlink -f ~/.claude/scripts/limit-recover/lr-reset-poller.sh)"
```

That is the generalisation of `conclusion-must-reach-the-enforcing-store`: for a repo whose live
layer is a symlink farm into a *working tree*, **landing on `origin/main` is not deployment**, and
the lag is invisible to `git log`, to the ledger's ADD-detector (no file was added), and to the
alarm itself (which keeps printing, identically, and therefore looks like a fix that did not work
rather than a fix that never arrived). Filed as the live-layer question the convergence-deadlock
effort owns; this session did not widen scope into it.

**State at this recycle.** `master-stranded-work` 6 → 5 live rows: 4 blocked (unchanged — the two
web-gated operator-only ones `8f4eae55a0c7` / `1dca461d4b90`, reso's `.eslintcache`
`216f429128a2`, the 122-orphan worktree sweep `475b43aacbf2`) and **1 open** — `8ad4b02602dc`
(no wake path for an idle headless session; stream-json needs a stdin-FIFO writer). Effort order
by size after this one is unchanged: `master-verification-integrity` (13) →
`master-operator-gated` (25) → `master-account-facts` (26) → `master-enforcing-store` (32) →
`master-session-lifecycle` (41) → `master-fleet-footprint` (56) → `master-product-repos` (57) →
`master-fire-gate` (58) → `master-convergence-deadlock` (84).

### 2026-08-14 — recycle #4: `master-stranded-work` has ZERO open rows, and the last one was sitting in a dead pane's working tree

The effort's final open row (`8ad4b02602dc`, no wake path for an idle headless session) was marked
**dispatched to pane 473** with custody ABANDONED — *"partial and unverified … no tests run …
nothing is lost: the pane is alive and resumes the moment the prompt is answered."* Every clause of
that was true when written and the conclusion had **expired**:

- **The pane was gone.** Its custody remedy addresses `unix:/tmp/kitty-600`; that socket does not
  exist. The live kitty answers on `/tmp/kitty-587` with 5 panes, max id **35** — a restarted
  instance. That positive control is what makes "no 473" an absence rather than a null from a dead
  instrument.
- **The work was in exactly one place a reaper could take it.** `bin/cc-wake-headless` (new) and a
  modified `bin/cc-pane-headless` sat **uncommitted** in `.worktrees/w4/headless-wake`, on a branch
  **0 ahead of origin/main**. No process held that worktree. A `git log --all` for the file finds
  only a PostToolUse *checkpoint* commit — the safety net worked, but nothing in the drain's normal
  instruments (branch ahead-count, ledger, custody) could see the bytes.

**So a park that is honest about the CODE can still be wrong about the WORLD.** The abandon note
reasoned entirely about the work's readiness and not at all about the container's lifetime, and the
container is what died. Committed verbatim first (`af0127d07`), before reading a line of it:
**review cannot lose what it has not yet read.**

**The gap itself was ONE redirect.** `cc-pane-headless` spawned every agent `</dev/null` — stdin
closed at birth. `cc-await-ping` cannot substitute, because its wake IS process exit: the harness's
task-completion notification synthesises the turn, and in `--input-format stream-json` **nothing
consumes that exit**, so an armed watcher fires perfectly and changes nothing. Pane 473's design was
right and is now landed (`a565f3b43`): a per-agent `in.fifo`, a **holder** process, and
`cc-wake-headless` as the one writer.

**The holder is the subtle part, and its comment is worth keeping.** `9<>` (O_RDWR), never `9>`:
opening a FIFO write-only **blocks until a reader opens**, so a write-only holder makes spawn order
load-bearing and one that loses the race leaves the agent wedged in `open(2)` **forever — live to
every liveness probe, and permanently deaf.** And the holder cannot be the waker: the instant the
last writer closes, the agent reads EOF and the session ends.

🚨 **W9 is the reusable test lesson: a cleanup test whose subject also cleans up on its own is
VACUOUS until the self-cleanup is made slower than the assertion.** The holder exits by itself once
the agent dies, so at the suite's 1 s poll `close reaps the holder` passed whether `close` reaped it
or not — **measured, by the mutant that deleted the reap and survived.** Pinned at
`CC_PANE_HOLD_POLL_S=30`, only an explicit kill can end it inside the window, and the mutant now
convicts. Six mutants total, each asserted APPLIED before its verdict was read.

**Two land-gate lessons, both about the tests and neither about the subject.** An **optional-arg
/Users/chrisren/.claude/bin/cc-bats helper** makes shellcheck read every bare call as a forgotten `"$@"` (SC2119/SC2120) — 8
findings from one helper, and the fix is *two named helpers*, not eight annotations. And
**duplicating a subshell so two branches differ only in a redirect** raises SC2030/SC2031 on the
second copy's `export`; factoring to one spawn site with the stdin source in a variable removes both
the finding and the duplication it was pointing at. The gate also cut the smoke suite at its 120 s
budget — that is a **GATE-KILLED non-verdict, not a red**; `SHIP_LAND_SMOKE_BUDGET_S=420` earned a
real green (3 suites / 166 s).

**Effort state: `master-stranded-work` is DRAINED as far as an agent can take it — 0 open, 4
blocked**, all four genuinely operator-gated and re-verified: `8f4eae55a0c7` (GitHub server-side
author-email ruleset, web UI), `1dca461d4b90` (Claude GitHub App install — state UNKNOWN, not
absent; settling it fires a CLOUD create), `216f429128a2` (reso worktree-local `.eslintcache`),
`475b43aacbf2` (122-orphan worktree sweep). A fifth row closed as **moot** on the way past:
`438b6f76343b` was the operator step "answer the permission prompt in pane 473", whose pane and
whose purpose both expired.

Next by size: `master-verification-integrity` (13) → `master-operator-gated` (25) →
`master-account-facts` (26) → `master-enforcing-store` (32) → `master-session-lifecycle` (41) →
`master-fleet-footprint` (56) → `master-product-repos` (57) → `master-fire-gate` (58) →
`master-convergence-deadlock` (84). Live store 539 (sibling intake ran +9 while this row was
worked — the drain's own arithmetic is net-of-intake, never a raw total).

### 2026-08-14 — THE LOCAL DRAIN recycle #4: `master-verification-integrity` opens, and two of its three closes cost no code at all

`master-stranded-work` is drained, so this recycle took the next effort by size,
`master-verification-integrity` (13 live rows). The brief's warning was the right one and it paid
immediately: **of the first three rows touched, two were already fixed on trunk and open only
because a LEASE expired.**

- **`91c6f91062ae`** (pane-spawn-coverage has no could-not-run third state) — closed on
  `c0e280a19`, content-verified: `SCAN_SENTINEL` ×8, the absolute `CHECK_FAILED` veto → exit 2, and
  `memo_batch_record` ×1, i.e. both halves the row required. It was reopened at 05:59 by
  `cc-backlog-reap` when its claimer's lease went stale — **two hours after the landing commit**. A
  lease verdict is not a work verdict.
- **`73583e2519d6`** (bats-assert-liveness fails OPEN) — closed on `4a33679c7`. Its own stored
  falsifier **retracts**: run against `origin/main` it exits 0. Its `blocked` status was an
  unresolvable worktree-occupancy oracle for a cloud claim — the claimer had read the DISPATCHER's
  spent pid — so the block was about a probe, never about the work.

**Read the falsifiers first.** Three of the class's rows carry probes; running all three against
`origin/main` took one command and split the class before a line was written: one retracting (close
it), two still failing (real work). That is the cheapest discriminator this store has.

#### `57ff249657e0` — `exit` cannot leave a `$( )`, and the report it fabricated prescribed the act that destroys the ratchet

Landed **`590c85187`** (in push `d2fe55adf`). `scan()` guards four unusable states and each says
`exit 2`, the honest non-verdict — but `hits="$(scan)" || true` ended only the SUBSHELL and
discarded the status. Empty `hits` against an EMPTY allowlist would be a lost verdict; against the
real **16-row** one it **inverts into a positive claim**: every grandfathered file reads
`cur=0 < alw=N`, so the ratchet's downward half fires. Measured on `origin/main` at
`ROOT=/nonexistent`: **exit 1**, naming 16 sites as newly FIXED that nobody had touched.

**The third victim the row did not name is the worst one.** That fabricated report's own FIX line
says `--regen > scripts/pipefail-sigpipe-allow.txt`, and `regen` read `scan` through a PIPELINE —
the same subshell. Measured: four header lines, zero rows, **exit 0**. A well-formed allowlist
declaring every grandfathered site clean, written over the real one by a redirect the shell had
already truncated. **The prescribed remedy was the destructive act** (memory:
`prescribed-remedy-worse-than-the-bug`).

Two things generalise:

1. **`--census` is the control that names the mechanism.** There `scan` runs in THIS shell and
   `exit 2` leaves the script correctly — measured 2 both before and after. So the defect is the
   *subshell*, not the exit. It is also why the suite's existing **test 12 was a VACUOUS guard**: it
   proved the exit-2 path through the one entry point that was never in danger, and stayed green on
   the pre-fix file while 15/16/17 went red (memory: `sibling-guard-makes-the-fixture-vacuous`).
2. **Prove the mutant applied, and prove it PER SITE.** Replaying the real pre-fix file from
   `origin/main` reds 15+16+17 together, which credits no site. Two single-site mutants separate
   them: `main_scan` alone reds 15+16 and leaves 17 green; `regen`+dispatcher alone reds 17 and
   leaves 15+16 green. Test 18 (healthy path) is green under both mutants **and** the fix — a
   control that discriminates nothing about the change is what makes the reds mean something.

**A stale falsifier cannot retract, and this one now can't.** `57ff249657e0`'s probe greps `hits=`
as its clause-1 precondition — the exact spelling the fix DELETED (0 occurrences on `origin/main`).
It therefore returns 1 unconditionally and the row could never self-retract. Closed on content
instead. Worth carrying: **a falsifier keyed on the defect's spelling dies at the moment it should
fire**; key it on the REMEDY's marker.

#### The sidecar: an `-eq 13` that blocked every land in the repo — and deleted its own verification

The land gate red'd on `tests/gate-ownscope-leak.bats` test 16, which asserted the `own_run` census
returns **exactly 13** pairs. `85fd75bc8` had correctly added a **14th** (`MOVINGREF`), presence
test and all. **Reproduced on PRISTINE `origin/main` in a detached worktree** with a diff touching
neither `ship-land.sh` nor any `CC_*_OWN` — so: not mine, and red for a sibling doing exactly what
the test exists to require.

The second-order damage is the part to remember. **bats aborts the test body at the failing line**,
so the per-arm loop below — the ACTUAL check — never ran, and the new arm went **entirely unjudged
by the very test that was red about it**. An exact-count assertion does not merely misfire; it
deletes the verification standing behind it. (Confirmed afterwards that `moving-ref-control-lint.sh`
carries two `${CC_MOVINGREF_OWN+set}` tests and zero two-state forms — a pure false red.)

An `-eq N` here can only fire on GROWTH: a lint that LOSES its three-state test leaves the count at
14 and is caught by the loop. So the count's real job is narrower — catching a grep that stopped
matching and silently truncated the population. That is a **FLOOR** (`-ge 13`) with the loop as the
TALLY (memory: `exact-count-assertion-tripwires-its-own-subject`). Mutant-proved: narrowing the
census regex to 0 pairs still reds. Landed **`d2fe55adf`**.

**State at this recycle.** `master-verification-integrity` **13 → 10 live rows** (7 open, 2 blocked,
1 claimed); 3 closed, 0 filed, 2 commits landed (`590c85187`, `d2fe55adf`), net **−3** on the effort
and net-negative on the store. Remaining open: `3ec6c070f52f` (the W4 master — **its first clause,
the 9-of-15 arms, is already DONE via `446fe07464e0`/`b7f771848`; re-scope it against the other
three clauses rather than re-deriving it**), `2c5ab136d63f` (hermeticity `--selftest` maps both
exit-2 reasons onto one — the sibling of the row just closed, and the next one to take),
`c1a29f8ee045`, `e191b6801be5`, `05ff1e5fabc0`, `8efd655b0fe1`, `b02e87582e96`.

**Live layer: `🚀`, and the ADDs are a sibling's.** `deploy-live.sh` declines — *"already deployed …
6 un-stamped commit(s) above"* — the standing GREEN-stamp fail-closed `35190812890d`, which is open
and already filed (not re-filed here; an open row whose remedy keeps getting re-minted is its own
defect). The ledger reads `🚀` on **2 NEW files absent from the live layer**, and both —
`bin/cc-wake-headless`, `tests/cc-wake-headless.bats` — arrived on trunk from another session's
land. **This diff adds no file**: all three paths are `M`, so they ride their existing per-file
symlinks. Effort order after this one is unchanged: `master-operator-gated` (25) →
`master-account-facts` (26) → `master-enforcing-store` (32) → `master-session-lifecycle` (41) →
`master-fleet-footprint` (56) → `master-product-repos` (57) → `master-fire-gate` (58) →
`master-convergence-deadlock` (84).

### 2026-08-15 — THE LOCAL DRAIN recycle #5: the selftest that had no third state, and a master row whose four clauses had all already landed

`master-verification-integrity` **10 → 8 live rows** (4 open, 3 blocked, 1 claimed): one code fix
landed (`26ccbb3a8`) and one master row closed on measurement alone.

#### `2c5ab136d63f` — `--selftest` could only ever exit 0 or 1, so one lost fork convicted a clean tree

Landed **`26ccbb3a8`**, content-verified on `origin/main` (six markers present, `git diff origin/main`
empty on all three paths).

`lint_dir` answers **2 for five different reasons** and they are not one class. Four are STRUCTURAL —
not a directory, no `.bats` suites under it, and the two extractors that cannot find their own anchor
— and each says something true, so each must stay a FAIL. The fifth is `CHECK_FAILED`: a predicate
that could not RUN, which on this box means a lost fork under load and is **not a claim about the
tree at all**. Case (e) is the only assertion in the whole selftest that lints the REAL tree, so it
is precisely the one a busy box can break — and all five collapsed onto one `fails=1`.

The damage was three-way and none of it was about the tree: `tests/test-hermeticity-lint.bats`
asserted `-eq 0` in three places · `postland-verify` reads exit 1 as **INSTRUMENT-BROKEN**, skipping
the scan so no green is claimable · `nightly-regression` scored it a plain regression.

**The enabling property is a redirect, and it is one character from being destroyed.** `CHECK_FAILED`
is readable by the caller ONLY because case (e) calls `lint_dir` with a plain redirect — *a redirect
is not a subshell*. `$( )` would be, and would discard the assignment before anyone could read it:
exactly the sibling row `57ff249657e0`, where `hits="$(scan)"` swallowed four honest `exit 2`s. So
the property is now **pinned by its own case (e2)**, not left as a comment — mutant m1 wraps that one
call in `( )` and reds.

**Consumers were re-verified, not assumed, and one genuinely needed the same diff.**
`postland-verify` already routes any non-1 nonzero to *"instrument unproven, scanning anyway"*, so it
needs nothing and strictly improves. `ship-land` does not run this selftest. But
`nightly-regression`'s NON-VERDICT class is `124|137|143|75` — exit 2 fell straight through to the
plain-regression arm (memory: `new-nonverdict-state-strands-its-consumers`). Fixed here,
**MARKER-GATED**: `bash` itself exits 2 on a syntax error, so a bare `2)` would turn every broken
check in the fleet into a silent CUT — fail-OPEN, the one direction that block must never grow in.

**The mutant matrix, one single-site mutant per site, each asserted APPLIED (diff printed) before its
verdict was read, against a control green under all of them:**

| | mutant | reds |
|---|---|---|
| ctl | none | **nothing (rc 0)** |
| m1 | `$( )` around case (e2)'s `lint_dir` | (e2) only — `CHECK_FAILED` unreadable |
| m2 | collapse exit-2 → FAIL (**the pre-fix code**) | (e2) only; (e3) stays green |
| m3 | abstain on every exit-2 (too wide) | (e3) only; (e2) stays green |
| m4 | non-verdict → exit 1 | `selftest_exit_code (0,1)` only |
| m5 | precedence flipped | `selftest_exit_code (1,1)` only |
| N1/N2 | nightly: drop marker gate / delete arm | one nightly case each |
| W1/W2 | wrapper guard too wide / too narrow | its own assertion each |

🚨 **m2 and m3 mutate THE SAME LINE in opposite directions and red DIFFERENT cases.** That, not the
count, is what proves the discrimination is two-sided and neither branch vacuous.

**Two instrument lessons, both found by mutating rather than reading.**

1. 🚨 **A pre-commit `shellcheck -S warning` is BLIND to the severity the land gate enforces.** The
   gate red'd on a single **SC2181 (style)** — `selftest_exit_code 0 0; [ "$?" -eq 0 ]` — that my own
   pre-commit check could not see, because I had run it at `-S warning`. Note *why* only that one
   line: SC2181 fires on a comparison against **0** (which is just the command's own status) and not
   on `-eq 1`/`-eq 2`, which `$?` is the only way to express — which is why the file's many existing
   `[ "$?" -eq 1 ]` lines are clean. This is `prescribed-repro-weaker-than-the-harness` with
   *severity* as the axis: **a pre-check run at a weaker setting than the gate can only ever
   exonerate.** Run the gate's own invocation, with no `-S`.
2. **W1 caught a vacuous-pass trap in the new wrapper control itself.** This suite loads no
   bats-assert, so `fail` is `command not found` (status 127). The control went red for the right
   reason with **entirely the wrong message** — and on the healthy path `fail` is never invoked, so
   nothing would have revealed it. Replaced with an explicit `echo >&2; return 1`.

#### `3ec6c070f52f` (the W4 master) — closed on measurement: all FOUR clauses had already landed

The brief said to re-scope it rather than work it, and the re-scope closed it outright. Measured, not
inferred:

- **9 of 15 ratchet arms collapse exit 2 into gate_red** → `b7f771848` ("8 gate arms collapsed a
  lint's exit 2 into gate_red — route could-not-run to GATE_KILLED"), on trunk, closed as
  `446fe07464e0`.
- **A SIGKILLed bats run reads as GATE RED** → `tests/ship-land.bats:1904` asserts a SIGNAL-killed
  corpus exits **9, not 6**, and greps that GATE RED is *absent*. It ran GREEN inside this session's
  own land (`ok 84`).
- **bats-assert-liveness fails OPEN** → `4a33679c7`, closed last recycle — and **live-confirmed here
  by accident**: run against a directory it printed *"COULD NOT RUN … exit 2 is a NON-VERDICT, not a
  clean tree"*. The fix demonstrating itself is better evidence than the commit.
- **89 non-final bare-`!` assertions across 28 files** → `bats-assert-liveness.py` over all **473**
  suites: **exit 0, zero findings**.

An open row whose remedy has already landed keeps minting duplicate analysis (memory:
`refuted-open-row-remints-its-own-analysis`); closing it is part of landing the fix.

#### Two operational facts the next recycle should not re-derive

- 🚨 **A CONDITION lease can block a row that is not the one being worked.** `cc-backlog claim`
  refused `2c5ab136d63f` because a SIBLING in the same condition (`0be0bd2c0b65`) was held live by a
  **cloud dispatcher**. `--force` was justified on three measurements, not impatience: the
  dispatcher's pid was spent (expected for a cloud claim, so worthless either way), **0 of 49 remote
  branches carried that row's work** 71 minutes after the claim, and the two rows touch *different
  files*. Do not touch `0be0bd2c0b65` itself.
- 🚨 **`ship-land` must be a HARNESS-OWNED background task, never `nohup … &` from a tool call.** Two
  full runs (~20 min each) were lost mid-gate with no verdict line — the process group dies with the
  tool call (memory: `nohup-from-a-tool-call-is-not-detached`). The third run, launched as a plain
  backgrounded command the harness tracks, reached `✓ ship-land: LANDED`. Also: the smoke's budget
  cut is a **GATE-KILLED non-verdict, not a red** — `SHIP_LAND_SMOKE_BUDGET_S=900` earned a full
  verdict here.

**State at this recycle.** `master-verification-integrity` **8 live**: open — `05ff1e5fabc0` (3
CI-only reds on the hermetic corpus), `8efd655b0fe1` (a CI shard CANCELLED mid-run, ~41 suites of
evidence lost per run), `b02e87582e96` (triage 7 defective adversarial screens), `e191b6801be5`
(unguarded-kill ratchet has no own-set — **its falsifier still fails against `origin/main`, so it is
real work**); claimed — `c1a29f8ee045` (own-set basename collapse, also still failing its falsifier);
blocked — `782607797fc5`, `67a7d78c1134`, `0be0bd2c0b65`. Live store 547 (sibling intake continues;
the drain's arithmetic is net-of-intake, never a raw total). Effort order after this one is
unchanged: `master-operator-gated` (25) → `master-account-facts` (26) → `master-enforcing-store` (32)
→ `master-session-lifecycle` (41) → `master-fleet-footprint` (56) → `master-product-repos` (57) →
`master-fire-gate` (58) → `master-convergence-deadlock` (84).

### 2026-08-15 — THE LOCAL DRAIN recycle #6: a ratchet whose "free" strictness rested on an invariant nothing re-asserted — and two trunk reds the land itself found

`master-verification-integrity` **8 → 7 live rows** (2 open, 4 blocked, 1 claimed). One row closed;
**three** commits landed as **`9a7818c38`**, content-verified on `origin/main` (eight markers
present, `git diff origin/main` empty on all eight paths), `LANDED … sweep=clean`, rc 0.

#### `e191b6801be5` — the unguarded-kill ratchet was strict whole-corpus on a RUNTIME premise

The arm's design argument was explicit and, read once, sound: the commit that introduced it swept
the corpus to zero, so *with a clean baseline the strictest rule is the free one* — no own-set to
derive, no exemption list to rot. `land-architecture-100p §5.P2` audited all fifteen ratchet arms,
found this one **"by design, not a leak"**, and declined to fix it because *weakening it would lower
the bar*.

**The premise is a RUNTIME fact and nothing re-asserted it.** From the first sibling site onward the
arm refuses EVERY land in the fleet over a file the author never opened, printing a remedy that is
not theirs to apply.

**It is not the weakening P2 forbids, and the asymmetry is the whole argument:** the author who
TYPES an unguarded kill has that suite in their own diff, so they are still hard-refused at the
chokepoint · an ABSENT own-set still means strict, so `postland-verify` and a bare human run judge
all 473 suites unchanged · an out-of-scope finding is still PRINTED (`kill-guard?`) and counted, so
drift is legible on every land instead of once · and for the corpus to be non-zero at all, a site
must have arrived by a route that never passed this gate — which strict whole-corpus never
prevented and only charged forward to the next lander. The baseline invariant is now an EXECUTED
assertion (the suite's ZERO-kills case, `env -u` so an inherited own-set cannot narrow the census)
rather than a comment.

**BOTH consumers took the fix in one diff.** `hooks/task-quality-gate.sh` runs the same lint at the
earlier chokepoint and fires on EVERY task in the repo, so whole-corpus there made one sibling's
kill a red for every author of every task. Its own-set is the suites the work CHANGED, captured at
the collection loop — NOT `$batsfiles`, which the sibling mapping widens to `tests/<name>.bats` for
any changed script (memory: `new-nonverdict-state-strands-its-consumers`).

**`in_own`'s body is COPIED VERBATIM from the path-keyed siblings.** A fifth spelling would be a new
latent basename-collapse vector wearing the same name — and `tests/gate-ownscope-leak.bats` pins the
copies identical, which is what makes copying correct rather than duplication. Its arm census is
derived from ship-land's own `own_run` call sites, so the new arm was covered without editing it
(verified present: 6 of 15).

**Ten single-site mutants, each asserted APPLIED (diff printed) before its verdict was read, control
green under all.** Four pairs mutate ONE line in OPPOSITE directions and red DIFFERENT cases:
`m1/m1b` (the ABSENCE test) · `m2/m2b` (SET-BUT-EMPTY) · `m3/m3c` (the PATH arm; m3c replays the real
pre-fix basename collapse) · `m6/m6b` (UNREADABLE scoping); plus `m3b`, `m4`, `m5`, and `h1/h2` on
the hook. Every new /Users/chrisren/.claude/bin/cc-bats case is attributed to a mutant that reds it ALONE: 3←m1, 4←m5, 5←m2b, 6←m4,
7←m3c, 35←h1/h2.

#### The land found TWO trunk reds that were not mine — and attribution, not driving, is what made them cheap

Both were reproduced on a **pristine detached `origin/main` worktree** before a line was written.

**1. `land-gate-cas.bats` case 11 — a stale MODE, not a stale wording.** It asserts the
stranded-sweep's un-`--mine` verdict out of ship-land's own output. `a2de71b95` made ship-land pass
`--mine "$CLAUDE_CODE_SESSION_ID"` whenever a sid exists, and `setup()` pins one for hermeticity —
so every land in that suite now runs ATTRIBUTED, the fixture's 40 strands belong to no session, the
sweep correctly reports CLEAN, and the asserted line became unreachable. `a2de71b95` (18:01) and
`c5f1d1d56` (18:20) landed **19 minutes apart on sibling branches, neither an ancestor of the
other** — a semantic conflict a clean rebase cannot see. The smoke lane selects that suite only for
a diff touching `ship-land.sh`, so it sat red from 2026-08-12. Fixed by asserting the MODE: the
walk/report numbers now come from a DIRECT sweep in the mode that renders them, with the attributed
mode asserted BESIDE it over the same tree.

**2. `SHIP_LAND_MEAS_ROUNDS` bleeds into every suite a re-gating land smokes** — the sharper one.
`meas_export()` carries `SHIP_LAND_T0` + `MEAS_{ROUNDS,GATE_S,ARMS_S,STATICS_S}` across the locked
re-exec, and `gate_bats` scrubbed the operator's TUNING but not this. So the moment an outer land
takes the in-lock path, every fixture pipeline starts counting from the OUTER land's total: case 14
asserts `"gate_rounds":2` and read 3. **Nobody has to set anything — the land sets these on
itself**, so the poison appears only on lands that re-round. Measured: land #2 (no stale gate)
passed case 14, land #3 (stale gate) failed it twice, and standalone it is 3-for-3 green even at
load 25 — "flake under load" was the wrong reading. Reproduced deterministically with
`SHIP_LAND_MEAS_ROUNDS=1 /Users/chrisren/.claude/bin/cc-bats -f 'P0 exit 42 attests' …`, same file, same line, same message. Fixed
at the chokepoint (`gate_bats`) AND in both suites' unset lists, with the gate-boundary contract in
`tests/ship-land.bats` extended to assert all five arrive unset.

#### Three instrument lessons, all paid for this recycle

1. 🚨 **A comment between a `\` and its command SILENTLY DELETES the command prefix.** My own scrub's
   first draft put the explanatory block between `${pre[@]+"${pre[@]}"} \` and `env`, which ends the
   continuation — so `timeout`/`nice` stopped wrapping the smoke entirely. Symptom on a fixture that
   hangs 120s under a 3s budget: **`✓ gate: smoke green — 1 direct suite(s) in 120s`**. Not a
   loosened bound — *no bound*. Caught only because `tests/ship-land.bats` pins the wall bound in
   BOTH directions, and attributed to me (not the load) by an A/B against pristine origin/main. The
   invariant now lives ON the line above the continuation.
2. 🚨 **A `perl -0pi` mutant harness INTERPOLATES the subject's own `$2` / `${3:-0}`.** Three mutants
   never applied and **two applied a DIFFERENT mutant than their label claimed** (`[ -n "$2" ]`
   became `[ -n "" ]`), producing plausible verdicts for code never under test. The "DID NOT APPLY"
   guard caught the first three; only reading the printed diff caught the silent two. Replaced with
   a literal replacer asserting EXACTLY ONE matching site. **Print the diff AND assert the site
   count** — a harness that can silently mutate something else fabricates evidence.
3. **`bats … | tail -30` reports the PIPE's rc** (memory: `verification-harness-vacuous-pass-traps`,
   hit again). The first `ship-land.bats` run "passed" with exit 0 while only its last 30 lines
   existed. Re-run writing full TAP to a file: **137/137, real rc 0**.

#### Operational notes the next recycle should not re-derive

- 🚨 **A live CONDITION-lease sibling is not a stale lease.** `cc-backlog claim` refused this row
  because `c1a29f8ee045` was held by a cloud dispatcher — and unlike last recycle the claimer was
  NOT spent: `origin/claude/fire-20260815T031727Z-93323-1` carried that row's real work, updated 55
  minutes after the claim. The `--force` was justified on **non-duplication**, measured: a different
  row, a different subject file (`scripts/bats-kill-guard-lint.sh` appears nowhere in their branch),
  and the one shared file touched ~600 lines apart. **Read the branch, not just the pid** — with a
  live claim the question is overlap, not liveness.
- **The smoke budget needed 3000s, not 900s.** Two lands were refused by a budget CUT (a GATE-KILLED
  non-verdict) at 900s and 2700s while a sibling ran a full 400-suite postland corpus (load 25). The
  cut is not a red, but ship-land counts it into "1 of N direct suites named a failure", so it still
  refuses the land — budget UP rather than retry.
- **`ship-backup-reap` keeping the backup ref with a "content DIFFERS" warning is BENIGN when the
  differing file is one a sibling also changed.** Here `hooks/task-quality-gate.sh` differed between
  the pre-rebase backup ref and the landed head; `git diff origin/main` on that path was empty and
  my marker was present, i.e. the trunk carries mine *plus* the sibling's. Verify by CONTENT before
  reading it as a drop.

**State at this recycle.** `master-verification-integrity` **7 live**: open — `05ff1e5fabc0` (3
CI-only reds on the hermetic corpus), `8efd655b0fe1` (a CI shard CANCELLED mid-run); claimed —
`b02e87582e96` (triage 7 defective adversarial screens); blocked — `782607797fc5`, `67a7d78c1134`,
`0be0bd2c0b65`, and `c1a29f8ee045` (now blocked, cloud-held). **Both remaining OPEN rows are
CI-only** — they need a GitHub Actions run to judge, not a desk one, which is the first time this
effort's residue has been off-box work. Live store 552 (sibling intake continues; the drain's
arithmetic is net-of-intake, never a raw total). Effort order after this one is unchanged:
`master-operator-gated` (25) → `master-account-facts` (26) → `master-enforcing-store` (32) →
`master-session-lifecycle` (41) → `master-fleet-footprint` (56) → `master-product-repos` (57) →
`master-fire-gate` (58) → `master-convergence-deadlock` (84).

### 2026-08-15 — THE LOCAL DRAIN recycle #7: the CI shard that "GitHub cancelled" was killed by our own corpus, and a bound rule that guarded the bug it was written beside

`master-verification-integrity` **7 → 6 live rows** (2 open, 4 blocked). **Three rows closed, two
filed**; three commits landed and content-verified on `origin/main` — **`910f53fcb`** (the reaper
fix), **`30494ba09`** (a trunk red the land found), **`cf4160fa7`** (the manifest entry), each
`land-verify: path(s) present + content-identical`, `git diff origin/main` empty, 0 unlanded.

**The brief's fallback did not apply, and checking that took one command.** It said: if both open
rows are genuinely off-box, say so and move to the next effort. `gh auth status` is authenticated
and `hermetic.yml` accepts `workflow_dispatch`, so CI evidence is reachable from the desk —
`gh run view --job … --log`, `gh run download`, `gh workflow run`. **Neither row was off-box.** The
repo is PUBLIC, so Actions minutes (macOS included) are free and a confirmation run costs nothing
but wall time. Do not re-derive this: the desk can read and drive this CI.

#### `8efd655b0fe1` — the runner did not shut down; `tests/reap-sweep-bounds.bats` TERMed it

The row's START HERE was *"emit a per-suite START marker so the log names the suite that was
RUNNING rather than the last one that finished"* — **that marker already exists**, and reading it
named the culprit in one grep. Across all six cut runs in the last twelve
(`31879973156 · 31882316087 · 31885942191 · 31890394871 · 31896109392 · 31898668582`),
`##[error]The runner has received a shutdown signal` arrives **0.4–0.7 s after
`>>> RUNNING tests/reap-sweep-bounds.bats`**, always shard 2, taking ~43 suites of evidence with it.
The row's strong lead — *successor-of-last-logged-suite* — pointed at the same file for the wrong
reason; the marker made it a measurement instead of an inference, which is exactly what the row
demanded before anyone acted.

**The mechanism.** That suite runs a real `sweep --reap` with the process table UNPINNED, so the
sweep's first arm (`garbage_sweep`) forks two live `/bin/ps -Ax` and issues real TERM/KILL. Its
`orphan-bash` shape is *launchd-parented bash, age ≥600 s, args off the whitelist* — which is
precisely what a GitHub Actions macOS runner service is: `/bin/bash …/runsvc.sh`. Reproduced
deterministically off-CI with a runner-shaped fixture snapshot: **2 candidates, 2 TERMed, one of
them runsvc.sh**.

🚨 **The obvious discriminator is NOT the explanation — check it before you publish it.** In-job
elapsed at that suite is **263–322 s on the cut shards and 258–313 s on the survivors**, fully
overlapping. So the ~50% coin flip is pre-job *runner uptime* crossing the 600 s age threshold, not
anything the job does. "Elapsed explains it" was a clean story that the data refuses, and the desk
never sees the effect at all (no ≥600 s orphaned bash here — the collector run caught zero).

**The row's own prescription would have made things worse** (memory:
`prescribed-remedy-worse-than-the-bug`). It offered *"scope the reaper's process selection by cwd"*
— but that arm is deliberately machine-wide: it collects the residue of DEAD sessions across the box
(the load-781 incident, 3,599 processes). Two narrower fixes instead:

1. **NEVER AN ANCESTOR OF THIS SWEEP.** The kill discipline enumerated what must not be touched by
   IDENTITY — claude, kitty, iTerm2, a whitelisted daemon — and **every clause names somebody
   else's process**. Nothing said *not the tree we are running inside*, while the classifier selects
   on SHAPE. A process this sweep descends from is by construction alive and holding the sweep, so
   it can never be the residue this arm collects. Placed at the **actuator** (memory:
   `make-the-actuator-the-arbiter`) so one guard covers the TERM pass, the KILL escalation and the
   watchdog branch whose candidates never pass through the awk — and BEFORE the collector seam, so
   a test can observe the refusal. The chain comes from live `ps`, never the snapshot: under a
   fixtured snapshot the sweep's own pid is absent by construction, so a snapshot-derived chain
   would be empty in exactly the tests that must exercise the guard.
2. **Fixture the process table in the suite** — the half `$HOME` does not reach. `/dev/null` is the
   spelling `tests/cc-reaper.bats:98` already used for this reason; that sibling was pinned and this
   one never was. Census: 41 suites name cc-reaper, exactly **2** execute a reaping verb, and both
   are now pinned.

**The pre-existing exact-set case asserted a TERM on `$$`** — the test's own pid, an ancestor of the
sweep it runs. It now uses a spawned child, with the ancestor asserted REFUSED beside it: one
mechanism, both directions, identical candidate shape.

#### The land refused twice, and both refusals were worth more than the diff

**1. The dead-assertion ratchet caught MY new case.** `A && { echo …; return 1; }` is unreachable
under errexit; `bats-assert-liveness-fix.py` **DECLINED** the shape (*"not a single scannable AND-OR
list"*) rather than guess, which makes the repair a hand-edit that must be proved. Rewritten as an
`if`, then proved live by a mutant that makes the ancestor branch print **both** strings — so the
positive half still matches and only the negative half can red. A decline is not a failure of the
fixer; it is the fixer refusing to fabricate.

**2. `tests/watchdog-census.bats` case 18 was RED ON TRUNK** — reproduced on a pristine detached
`origin/main` worktree before a line was written (the attribution step earns its keep every
recycle). `hook: every external call on the death path is time-bounded` requires
`lcw_bounded … ps aux` in `hooks/lead-crash-watchdog.sh`. **The hook executes no `ps aux`** — its
concurrency probe is `pgrep -x`, and the walk survives only inside the comment recording why it left
(load-781: 10–30 s per scan × ~20 concurrent scans feeding the load they were measuring). Both
halves came from the **same commit** (`dd7ddb528`), so the case was **born unsatisfiable in the one
direction that matters**: the only way to make it pass was to re-introduce the walk. A stale term
does not merely fail to guard — **it guards the bug** (memory:
`stale-assertion-becomes-an-inverted-guard`).

**Why nobody noticed: the suite is in `scripts/offbox-excluded.manifest`, so the off-box producer
never judges it** — and the on-box verifier runs in the shared checkout, whose tree diverges from
trunk (`4e39debcf`). A suite both producers are blind to is red for as long as it likes.

🚨 **And fixing the stale term exposed that the rule could not fail per site.** It asked whether the
file held SOME bounded occurrence of each NAME, so with two `pgrep` probes on the death path,
unbinding one left the case **GREEN** — proved by mutation (m7), which is the only reason it was
found. The rule is now per site, keyed on **invocation shapes** rather than bare names, because
`[[ -n "$tdbin" ]]` is a test and a bare-name rule would red the three guards surrounding the one
real call. m7 and m9 both red it now; each shape must still EXIST, so it cannot pass by deletion. A
third case pins the load-781 cure itself, which had **no guard at all** — the only assertion in the
area pointed the other way.

#### `05ff1e5fabc0` — all three named reds are RETRACTED, and the class had moved

Zero of the three (`lr-resume-answer-width`, `autonomy-sweep:534`, `boundary-handoff:369`) appear in
**twelve consecutive folds**. Not a hole either: they live in shards 1, 4 and 5, never the dead
shard 2, so their absence from `failing` is genuine greenness. **Do not spend another session on
TERM/COLUMNS or expect(1)** — the row's live hypotheses died with its symptom.

The class had a different, deterministic member: **`tests/unattended-path-lint.bats`, red in 12 of
12 and green 18/18 here** — the only suite red in every one, i.e. the single line standing between
the producer and a green all day, while `deploy-live`'s consumer wants a recent green. Cause named
by content, not hinted: the lint asks whether a bare name resolves on the PATH a launchd job runs
under, which is **a fact about which binaries the machine has**. The runner ships none of
`tmux · kitty · pnpm · yarn · uv`; the desk resolves all five *inside the hardened PATH itself*.
Manifest-excluded with that measurement, following its own sibling `unattended-sysctl-path.bats`.
**Teaching the lint to excuse "absent from this host" was rejected**: it would weaken the desk
verdict — the only one that means anything here — to buy an off-box opinion that never can.

#### `b02e87582e96` — a peer discharged it in full, and its follow-on could not reach the store

`ba9141f11` re-verified all 7 screens with 7 independent verifiers, none reviewing its own screen:
**20 of 21 findings live, no verdict overturned**. The row is closed on that evidence. But its
closing paragraph is the finding: *"Not filed to cc-backlog: the store is machine-local and absent
in a cloud container, so filing would have written to a store that evaporates."* **The analysis is
durable and the work was unreachable by `cc-dispatch`.** Filed as ONE pointer row (`c60963776f2e`),
not six — six rows to close one is the arithmetic this drain exists to avoid, and the triage doc
already ranks them (gate-memo first: a red lands green in the land gate, reproduced end-to-end).
🚨 **A cloud peer cannot file. Harvest its commit message, or the wave is lost.**

#### Two things the next recycle should not re-derive

- **`782607797fc5`'s premise is stale** (it is BLOCKED; this is a note, not an action). It asks the
  operator to authorize a privileged signal trace because *"With every run cut, NO GREEN STAMP CAN
  EVER EXIST, so deploy-live refuses forever."* `~/.claude/autonomy/postland/runner.log` records
  **`GREEN ba9141f110f8 … run_s=2299 retries=2 flakes=1` at 2026-08-15T13:57:42Z**, and the cut
  before it names its own cause (*"our own 5400s bound fired"*), not an external sender. `deploy-live`
  still refuses — for the **divergence**, not the absence: `target ba9141f110f8 is not a descendant of
  live HEAD 4e39debcfb3f`. Re-verify the wall before spending the operator on it (memory:
  `parked-blocker-obsoleted-by-later-fix`).
- **A land advisory now names `tests/watchdog-census.bats` as a shrink candidate** (*"green off-box
  now — delete its line from `scripts/offbox-excluded.manifest`"*). It was red for the reason fixed
  above, so the candidacy is plausible — but a partition run **cannot speak** for an excluded suite
  by construction. Confirm on a CENSUS run (`workflow_dispatch` with `census: true`, free) before
  deleting the line.

**State at this recycle.** `master-verification-integrity` **6 live**: open — `6a7eb069e703` (the
intermittent `cc-close-attrib` exit-code race, 3 of 12 — a RACE, not the host-coupling class, so it
must not be manifest-excluded on the intermittency), `c60963776f2e` (the 6-cluster triage wave);
blocked — `782607797fc5`, `67a7d78c1134`, `0be0bd2c0b65`, `c1a29f8ee045`. Confirmation of the reaper
fix is in flight: **`workflow_dispatch` run `31907405089`, pinned to `30494ba09`** (the first sha
carrying it) — read its shard 2 and its fold's `unreported`; the scheduled run `31907172661` is
pinned to the pre-fix `ba9141f11` and is the control. Live store 569 (sibling intake continues; the
drain's arithmetic is net-of-intake, never a raw total). Effort order after this one is unchanged:
`master-operator-gated` (25) → `master-account-facts` (26) → `master-enforcing-store` (32) →
`master-session-lifecycle` (41) → `master-fleet-footprint` (56) → `master-product-repos` (57) →
`master-fire-gate` (58) → `master-convergence-deadlock` (84).

---

### 2026-08-15 — THE LOCAL DRAIN recycle #8: the 7-cluster triage wave is retired, the exclusion list SHRANK for the first time, and the flake nobody has ever observed stayed unobserved through 658 runs

`master-verification-integrity` **6 live** (2 open, 4 blocked) — and the count is flat for an honest
reason: **`c60963776f2e` is CLOSED, its whole seven-item wave retired**, and the one genuinely new
thing this recycle measured was filed in its place (`ff3f38d6eeed`). One closed, one filed: net
zero, never net-positive.

**Ten commits landed and content-verified**, each `land-verify: path(s) present + content-identical`
with `git diff origin/main` empty on every path at close, 0 unlanded:
**`0364d24c8`** + **`b3110a79f`** (gate-memo), **`e6c8e723d`** (cc-recover-safeguard),
**`c68c7ea0d`** (the manifest shrink), **`543a0d841`** (worktree-memory-link), **`70b8c7797`**
(lead-supervisor), **`6f81a4185`** (this entry), **`97769f24e`** (session-writes), **`af9ba29a7`**
(cc-config-slot), **`4561aab18`** (branch-reaper), **`e78aef3c4`** (mailbox-forward).

#### The verdict recycle #7 left in flight: the fold is WHOLE, and `8efd655b0fe1` stays closed

Run `31907405089` never produced one — a `workflow_dispatch` shares a concurrency group with other
dispatches, so dispatching a run at current trunk **cancelled it**. Read that as a rule, not an
accident: *do not dispatch on `main` while a pinned dispatch is pending; the schedule is a
different group and is never cancelled.* The replacement is strictly better evidence anyway —
**`31908006223` at `4e21050b5`**, which carries the reaper fix AND `cf4160fa7`: **`unreported: 0`,
all ten shard artifacts present, no cut.** Against a measured pre-fix base rate of **6 cuts in 12
folds (50%)**, and with the mechanism named and reproduced off-CI, that is corroboration, not
proof-by-one-run — but nothing says reopen. `tests/unattended-path-lint.bats` is also gone from the
failing set, which is `cf4160fa7` working.

**Two suites reds appeared that were in none of the previous twelve folds** (`tests/cc-gc.bats`,
`tests/deathwatch-watchfile.bats`, plus a `completion-assert` cut at the 300 s bound). They are NOT
ours and it took one command to say so: `30494ba09` touches only `tests/watchdog-census.bats` and
`cf4160fa7` only the manifest, so neither can red a third suite. Both are spawn-then-kill,
dead-pid-observation shaped — the same family as `6a7eb069e703`, which is worth noticing.

#### The exclusion manifest shrank — the first time its cure arm has ever deleted a line

`c68c7ea0d` delists `tests/watchdog-census.bats`. The file calls itself *"RE-MEASURED, NOT
CURATED"* and names the census as the arm that stops an entry becoming permanent; that arm had
never removed anything, because growth was mechanised and the cure was a human remembering to tick
a box. The bar used, and the one to reuse: **a named mechanism PLUS a census green.** `30494ba09`
is the mechanism; census run **`31909362400`** ran the suite at **20 ok / 0 notok / 4 s** (the desk
reproduces it identically). The same census re-confirms what it does NOT delist —
`unattended-path-lint` red at 15 ok / 3 notok, exactly the runner-package-set class it was excluded
for. Partition 426 → 427.

#### `6a7eb069e703` — STILL OPEN, and the next attempt should not start where the row says

**658 runs, zero reproductions.** The row's own START HERE is now refuted twice over, and that is
the deliverable:

- *"the wrapper reads the child status after redirecting through a `>(tee)` process
  substitution"* — **that construct is gone.** `bin/cc-close-attrib:169-198` replaced it with an
  explicit FIFO plus a backgrounded `tee` whose pid is held, deliberately, in the 2026-08-07
  load-781 fix. The named mechanism does not exist in the subject.
- *"Reproduce with the suite under artificial load on the desk"* — **measured, and it does not.**
  Desk, 410 green / 0 red across five shapes: 40 direct-wrapper · 150 under 8-way CPU load · 120
  under 4× oversubscription + a fork storm · 60 under `bats` · 40 under the faithful
  `offbox-run.sh suites` invocation (`env -i`, `LC_ALL=C`, `TERM=dumb`, stdin `/dev/null`, under
  `timeout -k 10 300`). Both boxes are **bash 3.2.57 arm64**, so the interpreter was never the
  variable.

So the machine was ruled out on the machine that fails. A throwaway probe branch (`probe-**`, its
own workflow, never `wt-**`/`offbox-**` so it cannot spend the hermetic concurrency) ran the real
thing on `macos-latest`:

| probe | shape | result |
|---|---|---|
| `31909730457` reps 3, 5 | case 1 alone ×240, plus the whole suite ×12 immediately after its real shard-8 predecessor `tests/cc-backlog.bats` | **all green** |
| `31910734148` ×8 | the real `offbox-run.sh shard 8 10` — 43 suites, end to end, suite instrumented in place | **all green, and all 8 shards fully green** |

The instrumentation was positive-controlled before it was trusted (a `code+1` mutant made it print
`PROBE-OBSERVED status=34` beside the close-record's own `exit_code:33` — the field that
discriminates "wrapper returned the wrong code" from "`wait` returned the wrong code"). It never
fired. `P(0 fails | p=0.25, n=8) ≈ 0.10`, so this does not *refute* the rate; it says the trigger
is not in the suite, the case, the predecessor, the shard sequence, or the image.

**Do not attribute it to `910f53fcb`** — that was checked and is false. The reaper suite that TERMed
the runner is `tests/reap-sweep-bounds.bats` in **shard 2**, `cc-reaper` is **shard 1**, and
`cc-close-attrib` is **shard 8 position 7 of 43** whose only reaper-ish suite (`team-orphan-reaper`)
runs at position 41, *after* it — different runner VMs entirely. Two of the three failures
coincided with cut runs and one (`31893067668`) did not.

**The one hypothesis the data still supports** is the one that commit measured for the cut: **runner
STATE, not tree state** — there, the coin flip was pre-job runner uptime crossing a 600 s age
threshold, which is invisible to any number of fresh-runner reps. Next attempt starts there
(correlate failures against runner uptime / warm-vs-cold VM), not at the desk and not at the
wrapper. The row must still not be manifest-excluded: 3-of-12 is a race, and an entry there needs a
measurement of MACHINE coupling.

#### `c60963776f2e` — CLOSED: all seven ranked items retired, in the triage's own order

- **`gate-memo` (rank 1, "a red lands green").** The salt hashed four interpreter versions and no
  configuration, while `ship-land` invokes the analyser with **no `--norc`** — so `.shellcheckrc`,
  which waives two codes by name and calls itself *"a FLOOR"*, decides verdicts the memo stores.
  Reproduced on trunk's own lib: identical blob **and** identical salt across an `rc=0 → rc=1` flip.
  Fixed by folding the rc into the salt by value (`HERM_READSET`'s shape), and `b3110a79f` then
  corrects three comments citing a `git ls-tree` this file has never called.
- **`cc-recover-safeguard` (rank 2).** All four live. The load-bearing one: both `self-close` arms
  ended `|| true` and nothing re-read them, so a REFUSED close (exit 2 is the *ordinary* answer when
  a third process drives `self-close --session-id`) produced "recovery complete: … closed", a ✅
  page, and exit 0. The re-fire's status was checked rigorously and the **destructive** half was not
  checked at all.
- **`worktree-memory-link` (rank 3).** `encode()` mapped only `/` and `.` beneath a comment
  certifying *"Verified 2026-07-31 against ground truth … not inferred"* — the verification was
  real and its **span was two characters wide**. Re-measured against the live fleet rather than the
  triage's single container build (which pinned CLI 2.1.42 while the fleet runs 2.1.183/2.1.220):
  **1,661 project dirs across four config roots, zero containing `_` or `.`**, with a positive
  control that makes the zero non-vacuous — `~/Development/doc_classifier` exists and is keyed
  `-Users-chrisren-Development-doc-classifier` in all four roots (227 session files), while the
  narrow rule's slug exists nowhere. `70b8c7797` then fixes the same rule in `lead-supervisor.sh`,
  where its fail direction is a **false `STALL?` page at a healthy session**.

- **`session-writes:278` (rank 4).** Converted to the herestring its sibling three lines below
  already uses. **The honest scope is in the diff**: the CONSTRUCT reproduces here (141 at ≥49 KB,
  and at 269 KB under both greps), but `session_dirty_mine` driven under pipefail with 3,001 written
  paths returned the pipeline rc as 0 every time — so a regression test written against that entry
  point PASSES PRE-FIX, and it was **deleted rather than shipped**. A green assertion over an
  unreached mechanism is worse than none. That refines the row: its reproduction is a top-level one.
- **`cc-config-slot` (rank 5).** Three error paths that crashed, mislabelled, or raised out of
  themselves — including one the screen missed: the unknown-account handler called `load_accounts()`
  a second time INSIDE its own `except`, so a record missing `name` threw an uncaught traceback out
  of the arm whose job is to report the problem. Also `except (…, json.JSONDecodeError, …)` missing
  `UnicodeDecodeError`, which crashed a resolver that sits in the launch path of every session.
- **`branch-reaper` (rank 6).** `--trunk` / `--keep` / `--restore` typed LAST spun the parse loop
  forever at 100% CPU (`shift 2` shifts nothing and returns non-zero; nothing reads it) — all three
  exit 124 under `timeout 6` on the trunk copy. And the "NOT merged (untouched, holds work)" line is
  a RESIDUAL, so `--keep` relabelled merged contentless refs as unlanded: 1 → 3 on a fixture whose
  ground truth stays 1.
- **`mailbox-forward` (rank 7, test-only).** `grep -qv 'l1'` returns the SAME verdict on the
  regression and on the fix. **Measuring that needed care**: on this desk `grep` is ugrep, whose
  `-qv` exits 1 where `/usr/bin/grep` exits 0 on byte-identical `-v` output — so the assertion
  accidentally discriminates under ugrep and is vacuous under the portable grep the runner has. **A
  desk check would have exonerated it.** Replaced with a `grep -c` count, which separates the two
  under both.

#### The method note worth carrying: a mid-body `! cmd` asserts NOTHING

Building the safeguard tests, the class-not-spelling case **passed against the pre-fix script**. The
cause is not /Users/chrisren/.claude/bin/cc-bats but bash: a command whose status is inverted with `!` is **exempt from errexit**,
so only the LAST line of a test body is load-bearing in that form — `shellcheck` says the same thing
as **SC2314**. Every negative in the new tests is an `if … return 1`. This is the executable half of
blocked row **`67a7d78c1134`** (bare mid-body `[[ ]]`, 2,561 sites): the same defect, a different
spelling, and the reason a suite can be green over a live bug. **Every new assertion this recycle
was mutant-proved per site** — safeguard 13 ok / 5 not ok pre-fix (the 5 being exactly its four
findings), worktree-memory-link 13 / 3, gate-memo 10 / 1, lead-supervisor 98 / 1 — with an always-on
control green in both worlds each time.

**Blast radius of `ff3f38d6eeed`, measured before filing it as work rather than as a fix.** A rule
widened the obvious way — *a builtin producer fed a VARIABLE is not exempt* — matches **262 sites
across 96 files** (non-test paths). The allowlist may only SHRINK, so that is not a regeneration,
it is a project. And most of those 262 are genuinely safe: the hazard is not "the producer is a
variable", it is "the variable can grow WITHOUT BOUND" — a session's whole path list, a whole file,
a whole ref list — which is not statically decidable from the pipeline alone. So the next attempt
should not start by widening the detector; it should start by asking whether the rule can key on
the variable's SOURCE (a file read, a `git for-each-ref`, a transcript scan) rather than on its
being a variable. Do not re-run the 262 count; it is here.

**State at this recycle.** `master-verification-integrity` **6 live**: open — `6a7eb069e703` (see
above; do not restart at the desk) and `ff3f38d6eeed` (NEW, the harvested lint-exemption finding —
filed as ONE pointer row, with its threshold measured so nobody re-derives it); blocked —
`782607797fc5`, `67a7d78c1134`, `0be0bd2c0b65`, `c1a29f8ee045`. `c60963776f2e` is **closed**. The
next recycle's cheapest read is `ff3f38d6eeed`, because it is the reason `session-writes:278` was
never on the ratchet's allowlist in the first place. The throwaway `probe-close-attrib`
branch and its workflow are deleted; they never touched `main`. Effort order after this one is
unchanged: `master-operator-gated` (25) → `master-account-facts` (26) → `master-enforcing-store`
(32) → `master-session-lifecycle` (41) → `master-fleet-footprint` (56) → `master-product-repos`
(57) → `master-fire-gate` (58) → `master-convergence-deadlock` (84).

#### After the wave: two more efforts touched, and both moves were AUDITS rather than diffs

**`master-operator-gated` 25 → 24, by its own O1 (`f3f2f0805807`).** The deliverable there is *demote
every row an agent could actually do* — an operator-only step is not an escape hatch. All 24 blocked
rows were read; **21 are unambiguous gates** (credentials, OAuth consent clicks, an external human at
KPMG, taste calls on motion and menus) and three were checked one by one:

- `5436396f405c` → **`master-enforcing-store`, unblocked.** Its own title says *"the fix is that
  sessions work in their own worktree, not a command to run"* — which conflates *no command for the
  OPERATOR* with *nothing to build*. Measured: **no guard on `git pull`/`git merge` exists anywhere
  in `hooks/`**, and `validate-bash.sh`'s 40 deny arms cover other classes. A norm nothing enforces
  is the repo's own `enforcement-must-live-at-the-chokepoint` memory, and building that guard is
  agent work.
- `1cc794cbc6c4` → **`master-product-repos`.** Not operator-gated at all: `by=cc-backlog-reap`, i.e.
  the STALE-CLAIM REAPER blocked it defensively when a worktree-occupancy oracle could not resolve
  for a cloud-venue worker. Its actual work is a `source_type` ruling in `doc_classifier`.
- `bd3a486fa469` → **kept.** Redirecting the machine's own first-party telemetry for ~6 h is exactly
  the operator's call, and the row says so.

🚨 **`--force` on a condition re-key needs a MEASUREMENT, and here it had one.** `cc-backlog link`
refuses without it because a re-key can move a row out from under a live worker's lease. Measured
before forcing: **no row in the group has a claimer** (`1cc794cbc6c4`'s `by` is the reaper's own
bookkeeping stamp, not a worker), **no remote branch carries either row**, and the group's own plan
defines it as the one condition *"no session is ever fired at"*. Both ids survived the re-key.

**`master-account-facts` 26 → 25, and the win was re-measuring a dated title — but only after
measuring the RIGHT population.** `6a428f48fd2e` claims account 1 configures 69 hook commands vs 74
elsewhere. The first re-measurement said all four dirs were equal at 82 and the row was refuted —
**and it was measuring `~/.claude`, the live layer, not `~/.claude-next`, which `accounts.json` names
as account 1.** Against the correct four the row STILL HOLDS with drifted numbers: **77 vs 82, the
same gap of 5** (four scripts; `session-beat.sh` counts twice, prompt+stop). Both sides had grown by
8, so the gap never closed — it moved. *A dated measurement must be re-taken against the population
the SSOT names, or a refutation is just a different question answered correctly.*

The remedy turned out to be **already built**: `migrations/0009-claude-next-guardrail-parity.sh`,
class `c10`, citing the predecessor row `4ce34a4f703c` (**done** — closed on the build). Its own
`migration-verify` returns 1 (un-run) and its `migration-conflict` returns 0 — the **OVERRIDDEN**
state, confirmed directly: `~/.claude-next/hooks` is a forked REAL directory (53 entries vs 77 in
`~/.claude/hooks`) missing 3 of the 4 targets, so a settings-only edit would make it WORSE and the
migration's links-first ordering is load-bearing. So the row was BLOCKED with that measurement and
routed to the operator batch — the agent half is done, and only the C10 activation is left (the
'operator CAN REVERT' rescope, `b09f54e9e080`, is unratified, so the operator still RUNS every
activation).

### 2026-08-15 — THE LOCAL DRAIN recycle #9: `master-account-facts` opened, two rows landed, and the row that read "forked" turned out to have one inode behind five paths

**State: `master-account-facts` 16 open → 12 open** (11 blocked, unchanged in count — two were added
here and two of the old ones are unrelated). Two rows LANDED AND CLOSED, two BLOCKED on named
operator value-calls, and one re-measured hard enough to change what its remedy should be.

#### The correction the next recycle needs FIRST: the brief's "RUN: none on every one" is FALSE

Recycle #8's handoff said this effort's rows carry no falsifiers, so the row TITLE was the only
discriminator. Measured: **six of the sixteen carry one** — `37a0b651bcce` (a `merge-base
--is-ancestor` on a parked branch) and all five `advance <PLAN>` rows (`plan-phase-scan.sh <plan>
--falsify`). Running them first is still the right instinct; the premise that there was nothing to
run was simply wrong.

🚨 **And reading one of them nearly produced a false finding.** All five plan falsifiers exit **1
with completely empty output**, which reads exactly like a broken probe — that was the first
conclusion, and it was wrong. `scripts/plan-phase-scan.sh` prints the affirmative token `FALSIFIED`
**only on success** and says "this plan still holds work" by exiting non-zero and printing nothing.
Empty output is the DESIGNED live answer, not a failure to run. The probe even documents why it is
shaped that way: this script's second positional is a FORMAT with a silent default, so an older
deployed copy handed `--falsify` would print a section dump and exit 0 — and under the falsifier
contract exit 0 means "premise gone, refuse the claim". The affirmative token is what makes the
answer unforgeable by an older binary. **Read the probe's contract before calling it broken**; the
"ANDed clause one is false" warning has a twin, which is "silence is the answer".

#### `d1068fdf9b6a` — LANDED `fb1ea5d43`. The row's own remedy would have broken an invariant

`probe_provider()` measured **3.68s of a 3.7s `claude-accounts --json`** (6 providers, 8 child CLI
processes), re-paid by cc-context, cc-value, cc-board, cc-wave-plan and cc-blockers on every
invocation. Warm `--agents` is now **0.068s against 3.24s cold**, `--json` 1.5s against ~4.4s, and
the rendered table is byte-identical cached vs `--fresh`.

**The row asked for "a ~900s cache invalidated on providers.json mtime", and that literal remedy is
wrong.** It reads naturally as caching `probe_provider()`, which cannot be done: `pinned_model` is
read from the provider's OWN config precisely so that a config file governs and a remembered value
does not, and `installed` must answer for the PATH as it is now. Both become remembered values
under a whole-probe cache. This was not reasoned, it was RUN — the whole-probe mutant reds test 9,
"the model pin is read from the provider's OWN config", which edits a provider's settings.json
between two runs with the registry untouched. That test is now the memo's standing control.

So only the CHILD PROCESSES are memoised. The key carries the argv, the resolved binary's
realpath+mtime+size, and the registry's mtime+size — and the binary's identity is in there for a
measured reason: **the weaker key the row literally proposed (registry alone) reds test 15 and
nothing else**, reporting an upgraded provider at its old version. Failures cache at 60s rather than
900s, because a provider whose CLI hangs costs its full timeout on every call, but a transient
failure must not pin a wrong `auth_state` for a quarter of an hour.

**The dead-assertion gate caught one of mine, and the lesson is narrower than the one #8 recorded.**
Every negative was written as `if …; then echo >&2; return 1; fi` to avoid the mid-body `! cmd`
errexit exemption — and one test still carried a bare mid-body `[[ "$output" != *"Traceback"* ]]`,
**copied from a sibling test where it is the LAST line of the body and therefore load-bearing**.
The defect is not the spelling, it is the MOVE: the same characters assert something in one position
and nothing in another. Revived with `scripts/bats-assert-liveness-fix.py`, then proven live in both
directions.

#### `e9245cc24dff` — LANDED `bfe2b5daf` → `313d83050`. A guard that could only fire after the money moved

The standing cost guard asks that extra-usage stay OFF on all four accounts. Everything built for it
keyed on SPEND: the SSOT field `accounts.json:spend.usage_credits_authorized`, and `render_readout`'s
¢/🚨 lines on `credits_used > 0`. Spend is the right BREACH signal — an account read
`credits_on=false` with $176.91 already gone — but the earliest a spend-keyed line can fire is after
the money is gone.

**Measured, not assumed:** `render_readout` with `credits_on=True` and zero spend emitted nothing
about the toggle at all, and still routed the desk to that account. `render_table` has surfaced it
all along, pinned with a positive control. **Two renderers, and the silent one was the
operator-facing surface.** Fixed with a distinct `⚠` marker (never `¢`, so the existing "no ¢ at
zero spend" assertion needed no edit) as an `elif`, so a spending account gets the louder line and
never both. Fails safe on absent config: the fixture cfg has no `spend` block at all, and a missing
standing answer reads as unauthorized. It cannot fire today — all four accounts read
`credits_on=False`, `credits_used=0.0` — which is the polarity you want.

#### `3e2358f03e23` — HALF REFUTED, and the refuted half is the one that made it urgent

The row: "19 skills live in `~/.claude/skills` with NO tracked source — untracked, unlandable, and
**forked across config dirs** … REAL FILES, duplicated independently in `~/.claude` and
`~/.claude-secondary` with nothing keeping them in sync — so an edit to one silently forks the
other."

- **The untracked half HOLDS, with drift: 19 → 18.** `cc-version-audit` has since been tracked.
- **The FORK half is REFUTED.** Every other config root's `skills/` is a **symlink to
  `~/.claude/skills`** — `.claude-next`, `.claude-secondary`, `.claude-tertiary`, `.claude-quaternary`
  all of them. `SKILL.md` reaches **inode 362553914 through every path**. There is ONE copy on disk,
  so an edit cannot fork what does not exist twice, and `diff -rq` reports all 18 identical for the
  trivial reason that they are the same file. *A harm claim about duplication has to be measured on
  inodes, not on paths.*

The row had **no falsifier**; one is now attached and controlled in both directions (exit 0 only when
every live skill is either tracked on origin/main or declares itself local-only; it names the 18
today, and a fixture with a `local-only` declaration flips it to 0).

🚨 **A trap for whoever picks this up: landing the sources WITHOUT converging the live layer would
CREATE the fork this row wrongly claimed.** `install.sh:598-608` already does the right thing — for
each skill name present in the repo it makes the live dir real and per-file symlinks into the
checkout, leaving unknown skills untouched — but until that runs, a tracked copy plus an untracked
live copy is two files where there is currently one. So the tracking and the symlink conversion are
ONE operation, not two. The remaining work is 18 judgment calls (**768 KB total**, dominated by
`react-best-practices` 296 KB/59 files, `pyramid-principle-full` 116 KB/11, `outlook-cleanup` and
`frontend-design-vue` 84 KB each), and the row itself allows "declare local-only IN the skill" as a
valid disposition — which is the right answer for the vendor corpora and for
`pyramid-principle-full`, a distillation of a copyrighted book.

#### Two rows BLOCKED on operator value-calls that the rows themselves already named

- **`f3e662d4e2a8`** — the target concurrent-session count is a SUBSCRIPTION question, not a compute
  one: cloud is free but shares the same rate-limit pool, so the ceiling is accounts × limits. The
  answer is how many Max subscriptions the operator authorizes holding. And upstream it is not even
  measurable right now: `CONCURRENCY_PROGRAM.md` § S5-CEILING records the cloud create as intermittent
  (1 of 4 in a 15-minute window, three falling back to bundle mode), so a ramp would measure
  flakiness rather than a limit.
- **`e09a075539f5`** — may `cc-url-open` hold a PERSISTENT CDP connection to Dia? That is the fix for
  the consent-dialog fallback, and it is exactly what the dia-agent skill's no-daemonization rule
  forbids. A security-envelope tradeoff; the current fallback is safe, so this is reliability only.

#### Where the effort stands

`master-account-facts` **12 open / 11 blocked**. Of the 12 open, **five are `advance <PLAN>`
pointer rows** whose falsifiers all correctly report their plans still hold work — those are whole
plans, not rows, and each wants its own dispatched session rather than an inline pass. One
(`b22e519e06cb`) is the W4 wave roster. The genuinely row-shaped remainder is `3e2358f03e23`
(triage above), `37a0b651bcce` (the parked `fix/accounts-eval-bin-resolver` branch, which exists at
`1a2c536ac`, is on NO remote, and is not an ancestor of origin/main), `1d20ff5ee344`,
`f272b30e66f5`, `66be078a3f50` and `492b95cbac72`.

#### Recycle #9 outcome: `master-account-facts` reached **0 open** — 16 → 0, and only three rows needed a diff

Final state **0 open / 17 blocked**, every row either landed on origin/main and closed, or blocked
with a named operator-only step. The distribution is the finding: **three rows needed code**, three
were closed by re-measuring a dated claim, one was a duplicate, and **ten were already finished or
already operator-gated and nobody had said so.**

**Landed** — `fb1ea5d43` (provider-probe memo), `bfe2b5daf` (the cost guard's leading indicator),
`27772ede4` (the qos-rewrite narrowing).

**Closed by re-measurement, zero code** — `37a0b651bcce` (the two eval-bin spellings both exist, but
the second is a DELEGATOR and four tests pin the agreement), `f272b30e66f5` (the instrument exists
and its line 2 names the row), `096b75d15d9f` (the probe answered on 2026-08-11; only the FRONTMATTER
said otherwise). `492b95cbac72` folded into `48e14163e78a`.

**The generator behind the biggest single win.** `096b75d15d9f` sat open for four days because
`plan-phase-scan.sh --falsify` reads YAML frontmatter, the plan's status log said "PROBE CLOSED —
status: answered", and **the frontmatter still said `open`**. One three-word edit retracted the row,
verified by running its own stored falsifier (now prints `FALSIFIED`, exit 0) against a control that
still exits 1. **A plan whose machine-readable status is stale re-mints an "advance" row forever.**
Worth a sweep of every `plan-open` row in the store against its plan's own status log.

**The other seven closed as blocked, and each names a step only the operator can take** — the C10
launcher flip `claude` → `claude1` (D-A, which gates BOTH `180d38b29912` and `48e14163e78a`), the
auth-recorder activation, the Gemini plan-tier check, the heal()-with-live-sessions ruling, the
concurrency/subscription call, the Dia CDP security envelope, and the convergence circle.

**Two defects surfaced that nobody was looking for.** (1) `com.claude.auth-timeseries` is
bootstrapped with a MISSING target and has failed **468 times** — `launchctl list` shows it loaded,
last exit 126, while the activation script that creates its symlink *and refuses to arm without it*
was bypassed. It has looked armed while recording nothing. Filed `85fc4f3216a7` with the runnable
activation. (2) The "19 forked skills" row is **half refuted**: five config roots share ONE inode, so
nothing has forked; the untracked half holds at 18.

**Method, and all three failures were the same shape — an instrument answering a question nobody
asked.** The handoff said no row here carries a falsifier; **six do**, and five of those answer
"still live" by printing NOTHING and exiting 1, which reads exactly like a broken probe (the
affirmative token is deliberate, so an older deployed copy cannot forge a retraction). A falsifier
keyed on whether a BRANCH landed can only ever say "live" once the fix arrives by another route —
which is also why five shas cited as shipped RESOLVE but are not ancestors of trunk, and why every
landedness claim here was settled by CONTENT. And the first reproduction probe for `1d20ff5ee344`
was **VACUOUS and said the opposite**: its command text contained `cc-bats`, tripping that hook's own
idempotency guard, so the probe disabled the mechanism it was testing while its control cheerfully
confirmed the file had been written.

**Next effort by size:** `master-enforcing-store` (33) → `master-session-lifecycle` (41) →
`master-fleet-footprint` (56) → `master-product-repos` (58) → `master-fire-gate` (58) →
`master-convergence-deadlock` (84). 🚨 **Read `master-convergence-deadlock` before the others** — it
is last by size but it is the blocker under `3e2358f03e23`, `6f183f5df5b9`, `48e14163e78a` and the
skills track-half, so draining it unblocks work across every effort above it.

### 2026-08-17 — `67a7d78c1134` closes on measurement: the cure landed 18 days BEFORE the row was filed, and the row's own metric counts the cure as the defect

Row `67a7d78c1134` — *"a bare `[[ ]]` mid-test-body is a NO-OP — measured, 2,561 sites in
`tests/*.bats`"* — fired as a cloud dispatch on 2026-08-17. **Nothing was re-derived and no
`tests/*.bats` file is touched: the corpus holds ZERO dead assertions, and held zero before the row
existed.**

**Verified against trunk, not a working tree.** The container clones shallow (50 commits), so — per
the `0e8a10c501af` precedent above — `--diff-filter=A` named the graft boundary as every file's
author until `git fetch --unshallow` (2,988 commits). Only then:

| what | when |
|---|---|
| `scripts/bats-assert-liveness.py` + `-fix.py` + `tests/bats-assert-liveness.bats` | born `f1b813f6`, **2026-07-25** |
| the ratchet becomes a LAND gate (`SHIP_LAND_DEAD_LINT`, exit 6) | `4a33679c`, **2026-07-31** |
| the row was filed | **2026-08-12** |

`python3 scripts/bats-assert-liveness.py --summary` on trunk → **`0 dead assertion(s) in 0 of 478
file(s)`**. Re-run against the tree at the row's own filing commit `1b044624` → **`0 of 455`**. The
row was not true on the day it was written.

🚨 **The premise defect, and it is the reusable half: `2,561` counts `[[` OCCURRENCES, not DEAD ones
— and the cure idiom `[[ … ]] || false` matches the very same grep.** Today's raw count is **3,264**,
of which **1,916 carry `|| false`** (that IS the fix), **2,247** sit in an `&&`/`||` list, and 14 are
in `if`/`while` condition position, where a conditional is not an assertion at all. Only **547** are
bare statement-position occurrences, and every one is the FINAL command of its body — the live
position. Hand-checked a sample (`accounts-board:138`, `:355`, `backlog-freshness:328`,
`capacity-admit-coverage:127`): each is followed immediately by `}`. **A metric that counts the fix
cannot reach zero, so a row keyed on it can never close by being worked — only by being
re-measured.** That is `6110fc45141e` one level up: not a stale TREE, a stale METRIC.

**The analyzer is not blind, and that was proved before it was trusted.** A mutant carrying one dead
site per class returns all three (`cond-keyword`, `arith`, `negation`) at rc 1, and correctly leaves
a FINAL `[[ ]]` unflagged. Deadness is a function of BLOCK POSITION, which is exactly why `grep`
cannot answer this question and the analyzer exists.

⚠️ **Refinement measured against a real bats oracle — the three classes are NOT equally version-
dependent, and "a mid-body `! cmd` asserts NOTHING" above is the durable one.** Under **bats 1.14.0
/ bash 5.2.21**, a mid-body `[[ 1 == 2 ]]` and `(( 1 == 2 ))` **DO fail the test**; only `! true`
still passes vacuously. `docs/research/BATS_DEAD_ASSERTIONS_2026-07-25.md` already anticipates this
— *"bash 3.2 is what was measured. Bash ≥4.1 narrows some of these exemptions … `|| false` is
correct under both"* — so this **confirms** the model rather than amending it. Operationally: on the
macOS bash 3.2 the suite actually runs under, all three classes are exempt and the analyzer's
conservative model is the right one; the `! cmd` class is the only one that survives a bash upgrade,
which is why it is the spelling that keeps coming back.

**Why this is recorded here rather than filed.** `~/.claude/autonomy/backlog.jsonl` is untracked and
unreachable from a cloud container (`scripts/cloud-reconcile.sh`: no `~/.claude`, no local `/ship`),
so trunk is the durable carrier (precedent `6394a353`, `3a072159`). The row is currently **blocked**
under `master-verification-integrity`; it should be **closed**, not unblocked — the close verb runs
on the box:

    cc-backlog done 67a7d78c1134 --evidence f1b813f6

**Do not re-file this row from a `grep -c '\[\['` reading.** The only sound measure is
`python3 scripts/bats-assert-liveness.py --summary`, and it is already enforced at two chokepoints:
`gate-select.sh` clause (g) selects the repo-wide ratchet on ANY `.bats` edit (a changed suite
selecting only itself would land green, since a dead assertion is discarded rather than failed), and
`ship-land.sh` blocks the land own-scope at exit 6 — fail-CLOSED on rc since `73583e2519d6`
(2026-08-14), where an empty stdout from a missing `python3` had been reading as the clean verdict.
