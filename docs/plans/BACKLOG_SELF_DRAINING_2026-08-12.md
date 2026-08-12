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

### W1 · Freshness — a currency verdict for every row, on a schedule

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
