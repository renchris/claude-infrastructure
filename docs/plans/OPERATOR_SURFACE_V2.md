---
status: complete
row: 10
subsystem: Observability & operator surface — what the human sees
---

# OPERATOR SURFACE V2 — ground-up rebuild of row 10

**Scope (frozen):** the operator surface renders **every** operator-owned step class within a
bounded render budget — **0 of 5 classes starved at any queue depth** (today: 55 steps through a
6-slot window starves 2 of 5 classes outright) — and carries **0 alarm predicates that test
presence-of-a-named-failure where absence-of-success is meant** (today: 1 of 9, live-suppressed).

Superlatives are banned from this DoD deliberately. Both targets are integers read off disk.

Methodology: the `ground-up` skill. Exemplar: [LAND_PIPELINE_V2.md](LAND_PIPELINE_V2.md).
Row row-10 of [GROUND_UP_REBUILD_MAP.md](GROUND_UP_REBUILD_MAP.md).

**Surfaces owned:** `bin/cc-blockers` (board + its alarm PREDICATES, per the map's rulings
register) · `hooks/operator-readout.sh` (Stop-hook close block + damping) · `hooks/activation-watch.sh`
(the pending-activation queue surface, 3 axes) · `statusline.sh`.

**Seams CONSUMED, never redesigned:** row 1 owns what a verdict *means* (`red · cut · hung · green`)
and the deploy lane; row 4 owns registry/liveness truth; row 5 owns dispatch decisions; row 7 owns
account/quota; row 12 owns `launchd/fleet.manifest` + `bin/cc-fleet`'s 6-state reconcile. This row
decides only whether the board **surfaces** a fact, and how it is ranked and plattered.

---

## §0 · Phase 0 — orchestration (FIRST section, per plan-conventions)

**Team size: 1 (single-lead, NO teammates) — a deliberate deviation from the 2+-files default, with
its reason recorded.** The four surfaces are **one shared contract** (the alarm table, the render
budget, the platter) and the entire defect class under repair is a *seam* bug — row 1's verdict
vocabulary leaking into row 10's alarm predicate. Split ownership across teammates is the mechanism
that produced this class, so re-introducing it to fix it is the wrong shape. Supporting facts:
total deliverable is ~400 LOC across 4 files plus suites, well under the 500-LOC split threshold;
the stages share mutable state (`steps_file` schema, the `ALARMS_JSON` contract), so a fan-out is
dominated by its own serialization (memory `staged-skill-fanout-trap`); and box load at Phase-1
close was already elevated by three sibling rebuilds in flight.

**Task dependency graph** (strictly sequential — each land is the next one's baseline):

```
doc ──▶ M1 polarity ──▶ M2 class-budget ──▶ M3/M4/M5 activation ──▶ M7 statusline ──▶ M6 lint ──▶ map
        (cc-blockers)   (operator-readout)  (activation-watch)      (cherry-pick)    (new script)
```

**Worktree:** this one — `gu-operator-surface` on branch `gu-operator-surface`, base `origin/main`.
Never the shared checkout `~/Development/claude-infrastructure` (project CLAUDE.md).

**Wave order = the land order in §7.** Landing is continuous via `scripts/ship-land.sh`, one atomic
commit per mechanism, never batched.

**Read-only research subagents:** none spawned. Phase 1 was measured by direct disk reads because
every decision here turned on the *load-bearing code itself*, which the `ground-up` skill assigns
to the lead ("subagent summaries are for breadth, your own reads are for the decisions").

---

## §1 · Phase 1 verdict on the row's standing-constraint cell

The map cell read: *"absence-is-loud WITH existence evidence; silver-platter commands."*

**Verdict: CONFIRMED-BUT-INSUFFICIENT.** (Row 5's cell was falsified; row 3's was
CONFIRMED-BUT-RENAMED; row 12's was CONFIRMED-BUT-INSUFFICIENT — this row matches row 12.)

Both halves are true *and both are already implemented*. `bin/cc-blockers` gates every one of its
nine alarms on explicit existence evidence and every row carries a `recover_cmd`; every
`activation-watch` axis reports an unrunnable check as a finding rather than a pass. The cell has
no defect. **The surface still fails**, because the cell is a statement about **per-row
correctness** and both live failures are **whole-surface** properties it cannot express:

1. **POLARITY.** A predicate can be individually well-formed, existence-gated, honest — and still
   be unable to fire. `[ "$red" -eq "$seen" ]` is not an absence-of-loudness bug; it is a
   *polarity* bug. The cell cannot see it.
2. **ATTENTION BUDGET.** 55 loud rows through a 6-slot window carries the **same zero bits** as an
   alarm that cannot fire. Absence-is-loud has no term for the cost of loudness, so a surface can
   satisfy the cell perfectly and still be unreadable.

**Renamed cell:**

> **The operator surface must be COMPLETE, RANKED and BOUNDED — every honest verdict reachable
> within the render budget, and no verdict expressible only as the absence of a specific failure
> name.** An alarm that always fires and an alarm that can never fire are the same alarm.

That equivalence is the row's inversion and §4 is built on it.

### §1.1 Activation and deploy truth (mandatory pre-design check — RUN, not assumed)

Both re-derived at **2026-07-29T~22:2x–22:4xZ**; both decay within hours; re-derive before gating
any decision on them.

| Fact | Value | Command |
|---|---|---|
| `com.claude.*` labels in the override db | **14** — 10 disabled / 4 enabled | `launchctl print-disabled gui/$(id -u)` |
| enabled `com.claude.*` | `postland-verify` · `dispatcher` · `discovery` · `deploy-live` | ditto, `grep '=> enabled'` |
| override-db checksum | **39 labels = 19 disabled + 20 enabled** ✓ | `grep -c '=> disabled'` + `grep -c '=> enabled'` vs `grep -cE '^\s*"'` |
| deploy lag (live layer behind trunk) | **20 → 23 within 12 min** (sibling rows landing) | `git -C ~/Development/claude-infrastructure rev-list --count HEAD..origin/main` |
| postland stamps, lifetime | **33** — 30 red · 2 cut · 1 hung · **0 green EVER** | `jq -r .verdict ~/.claude/autonomy/postland/stamps/*.json \| sort \| uniq -c` |
| newest 5 verdicts | **red · hung · red · red · red** | `for f in $(ls -t …/stamps/*.json \| head -5); do jq -r .verdict $f; done` |
| `last-green` cursor | **absent** | `ls ~/.claude/autonomy/postland/last-green` |
| pending activations (no `.done`) | **12** of 22 staged | `for f in …/*.sh; do [ -f "$f.done" ] \|\| echo x; done \| wc -l` |

**The parse traps were both walked deliberately and both avoided.** `print-disabled` prints
`"<label>" => disabled|enabled`, never `true`/`false` — the checksum row above is the only thing
that distinguishes a real zero from a dead grep, and it is stated because the coordinator lost a
read to exactly this today. `launchctl list | grep` was NOT used as a health oracle anywhere in
this row's measurements (row 12's law: it maps six states onto one boolean and puts four broken
ones on the healthy side).

**THE STRUCTURAL FINDING, which does not decay: the failure MOVED and nothing on the board says
so.** Deploy advanced sharply this afternoon (36 → 23 behind while this session measured it), and
`~/.claude/scripts/deploy-live.sh` — absent for the 59 logged `cannot execute` failures row 12
recorded — was symlinked into place at **Jul 29 10:32**, four minutes *after* the newest failure
line in `deploy.log` (10:28). So the row-12 verdict "the deploy platter names a file that does not
exist" was true and is now false. Meanwhile **12 activations sit staged and un-run**, six of them
carrying the campaign's own just-landed rebuilds (`16-session-beat`, `17-qos-chokepoint`,
`18-fleet`, `17-permission-beacon-wire`, `15-shared-task-board`, `10-lead-crash-orphan-close`).
The dominant failure is no longer *"landed but not deployed"* — it is **"deployed but not switched
on"**, and the operator surface has no row, no rank and no count that expresses it. §4's M2/M3
exist for that migration, not for any particular count.

**CORRECTION to the deploy figure, made during this session and the reason the STRUCTURAL claim is
worded the way it is.** The lag was measured four times in ~90 minutes: **20 → 23 → 0 → 47**. It
reached 0 (the shared checkout genuinely caught up to `458a45e9`), then trunk advanced again as three
sibling rebuilds landed. So "deployed but not switched on" is not a stable state and any plan that
gated on it would be gating on a coin flip. The claim that survives re-derivation:

> **The deploy axis OSCILLATES and is self-correcting; the activation queue is MONOTONE and nobody
> drains it.** 12 pending, 6 of them staged in the last 24h by the campaign's own just-finished
> rebuilds, and the surface that reports it named only 6 of the 12 before this rebuild. A count that
> swings 20→0→47 within the hour is a reconciler's job; a queue that only grows is the operator's,
> and it is the one the board was under-reporting.

### §1.2 Branch-graveyard sweep (Phase 1, non-optional) — POSITIVE CONTROL PASSED FIRST

Method: `git log --all --oneline --diff-filter=A -- <row-10 paths>` plus the per-branch
ahead/behind census, per `GROUND_UP_DISPATCH.md §"Campaign-level graveyard sweep"`.
**Control, run before believing anything else the sweep said** (the coordinator's first two sweeps
both produced confident garbage at exit 0): the sweep must re-find row 12's known-stranded
`scripts/launchd-parity-lint.sh`. It did — `518d61dc`. Only then were the row-10 results read.

The coordinator's pointer named 2 artifacts on `fix/infra-perfection`. **Re-derived: it was wrong
in both directions**, which is why the pointer said to re-derive.

| Artifact | Where it actually is | Verdict |
|---|---|---|
| `tests/statusline-identity.bats` | `fix/infra-perfection` ✓ (as named) — but **useless alone**: its harness self-check asserts `grep -q 'porcelain=v2' statusline.sh`, and trunk's `statusline.sh` has none, so the suite fails at case 1 without the refactor it guards | **TAKEN — with its parent commit** (see below) |
| `tests/statusline-mail-badge.bats` | **NOT on `fix/infra-perfection`** and not on `tm/hygiene`. It lives on `wt-02ba4e52389a` as part of `47288af4 feat(mail-v3): statusline 📬 unread badge` | **REJECTED** — it tests a `📬` badge that does not exist on trunk. The badge is row 3's surface (cross-session comms); row 3 is DONE and did not land it. Taking the test alone lands a red suite; taking the feature is row 3's call, not row 10's. Surfaced to the coordinator rather than dropped silently |
| `78de6237 perf(statusline): one payload read, two git calls — output byte-identical` | `fix/infra-perfection` — **not in the coordinator's list at all** | **TAKEN** — `git cherry-pick -x` applies **CLEAN** (verified by running it, not predicted), touches exactly `statusline.sh` + `tests/statusline-identity.bats`, and ships its own byte-identity harness that extracts the pre-slim baseline *from git* so it cannot drift |

Nothing was taken from `tm/growth` (the doc's stated trap: 0 unique patches, and a 6-branch nested
ancestry). Neither branch was landed wholesale (`fix/infra-perfection` is 55 ahead / 379 behind).

**Method note worth carrying:** the coordinator's list undercounted row 2 (3 artifacts, 2 named)
and *both over- and under-counted* row 10. A hand-maintained cross-row graveyard index decays the
same way every other handed-down count in this campaign has. The two commands are the artifact;
the table is a pointer.

---

## §2 · Measured constants (all citations reproducible; every number re-derived this session)

| # | Constant | Value | Citation / command |
|---|---|---|---|
| C1 | `operator-readout --render` steps rendered | **55** | `bash hooks/operator-readout.sh --render --cwd $PWD` header |
| C2 | …of which SHOWN | **6** (`CC_OPREADOUT_MAX` default) | same, `+49 more` footer |
| C3 | step sources | 1 deploy + **12** activation + **14** class-C decision + **28** blocked-backlog = 55 | `cc-backlog list --blocked --json \| jq length`; `jq 'select(.status=="open" and .class=="C")' ~/.claude/autonomy/decisions/*.json` |
| C4 | first rendered position of a class-C decision | **14** | `CC_OPREADOUT_MAX=99 … --render \| grep -n 'decision C'` |
| C5 | first rendered position of a blocked-backlog item | **> 27** | same, `grep -n 'backlog '` |
| C6 | ⇒ classes structurally unreachable at MAX=6 | **2 of 5** (decisions-C, blocked-backlog) | C4/C5 vs C2 — arithmetic, not opinion |
| C7 | activation-queue depth vs what axis 1 names | **12 pending / 6 named** (`>24h` gate) | `hooks/activation-watch.sh` `age_axis`; SessionStart advisory |
| C8 | postland stamps / green | **33 / 0** | §1.1 |
| C9 | newest-5 window | red · hung · red · red · red ⇒ `seen=5 red=4` | §1.1 |
| C10 | ⇒ `trunk-red` state | **SUPPRESSED**, `4 ≠ 5` | `bin/cc-blockers:302` |
| C11 | `never-green` DETAIL denominator | says **"5 verdicts"**; truth is **33** | live board row; `seen` is capped at `REDRUN_N` |
| C12 | live board alarm rows | **17** (1 `never-green` + 1 `beacon-inert` + 15 `fleet-inert`) | `bash bin/cc-blockers` |
| C13 | alarm-polarity grep hits in owned surfaces | **2 sites, 1 predicate** (`:264` counter, `:302` test) | `grep -nE '\-eq[[:space:]]+"?\$seen' bin/cc-blockers hooks/*.sh statusline.sh` |
| C14 | `deploy-lag` reachability | **0 by construction** — `[ -z "$gcommit" ] && return 0` upstream of it, and `gcommit` requires a green | `bin/cc-blockers:327-341` |
| C15 | CONFIRM-gated share of pending activations | **9 of 12** | `grep -q CONFIRM` per un-`.done` script |
| C16 | staged activations naming a `com.chrisren.*` label | **1** (`13-mailbox-gc-activate.sh`) — invisible to axis 3 | `grep -lE 'com\.chrisren\.' …/pending-activation/*.sh` |
| C17 | axis-2 findings whose live copy differs from **trunk** | **4 of 4** CONTENT-DRIFT confirmed real (live ≠ `origin/main` bytes for all four) | `git show origin/main:docs/activation/pending-activation/<n> \| cmp - <live>` |
| C18 | reflexive wiring check — is row 10's own surface live? | `operator-readout` in **4 of 5** config dirs (absent from `~/.claude-next`); `activation-watch` **5 of 5**; `statusline` **5 of 5**; `cc-blockers` on PATH ✓ | `grep -c` per `settings.json` |
| C19 | `render_block` cost | **~2711 ms** = 73% of the 3688 ms Stop chain | row 13's `MACHINE_CAPACITY_V2.md §8.5.3` (inherited, cited not re-derived) |

C19 is the binding constraint on M2's implementation: **no new fork may enter `render_block`.**
Every ranking signal M2 uses is derived from data the function already reads.

---

## §3 · INVARIANTS (numbered; any design must keep these) vs ARCHITECTURE (inherited from nothing)

**INVARIANTS** — walked out of MEMORY.md and the campaign's learnings, not invented here:

- **I1 · Absence needs existence evidence, and the evidence must come from a DECLARATION, never
  from the subject's own success history** (row 12). Gating on past activity makes "never worked
  once" indistinguishable from "never supposed to exist" — the population that matters.
- **I2 · For a VERDICT ask "is it red?"; for an ALARM ask "is it green?"** (row 12's close
  addendum, coordinator-reproduced). A non-verdict is worse than a failure for "is this
  persistently broken", yet only the red test silences on it.
- **I3 · A detector's negative is not data until it passes a POSITIVE CONTROL** (row 3).
- **I4 · Prove liveness by durable products, never by mtime** — 3 of 4 loaded jobs have logs that
  falsely read dark (row 12, derived twice independently).
- **I5 · Silver platter = the exact runnable command with its env seams pre-resolved.** Naming a
  script is not doing the job.
- **I6 · Fail-OPEN on sensor failure**: a board that invents blockers is ignored exactly like one
  that hides them.
- **I7 · An unrunnable check is a FINDING, not a pass** (backlog `816015ecb30b`).
- **I8 · Every new mechanism ships an env kill switch**; never revert-as-plan.
- **I9 · One renderer.** Push and pull surfaces must not be able to drift.
- **I10 · NEW, this row: no truncation may delete a CLASS.** A `+N more` footer promises "more of
  what you just saw"; it must never be the only trace of a category the operator has never seen.
- **I11 · NEW, this row: a plattered command must be existence-checked or trunk-adjudicated before
  it is handed over.** The deploy platter named an absent file across 59 logged failures and no
  surface noticed; it is valid today only by accident of a symlink landing at 10:32.

**ARCHITECTURE, inherited by default from nothing** — and mostly KEPT, which is the honest
verdict. The incumbent's mechanisms are good: nine existence-gated alarms, one shared
`alarm_table` renderer, per-family selectors, the cheap-stamp damping gate, the three activation
axes, the `.local`/`.done` marker conventions, `cmp`-not-`plutil`, fail-open everywhere. **This
rebuild is not a replacement.** Its inversion is a change of *predicate polarity* and *render
allocation* — two properties the incumbent never modelled — not a new set of sensors. Where the
old design is right, it stays byte-identical, and the tests prove that.

---

## §4 · Design — the failure-mode table (every observed mode → its structural answer)

| # | Observed failure mode (measured) | Structural answer | Mechanism |
|---|---|---|---|
| F1 | `trunk-red` cannot fire: `[ "$red" -eq "$seen" ]` silences on ONE non-verdict in the window (C9/C10) | **Count NOT-GREEN, not RED.** The alarm's question is "is it green?" (I2). One non-verdict must *strengthen* the alarm, never silence it | **M1** |
| F2 | The suppressed row was the one carrying the useful platter — `never-green`'s fallback sends the operator to `runner.log`, `trunk-red`'s sends them to the failing-test histogram. Different action, silently substituted | The state name must distinguish them: `PERSISTENT-RED` (all literally red) vs `PERSISTENT-NOT-GREEN` (window mixes red with non-verdicts). Row 1's verdict vocabulary is consumed verbatim; only the ALARM state is row 10's | **M1** |
| F3 | `never-green` DETAIL says "5 verdicts" against a lifetime of 33 (C11) — the board understates its own evidence 6.6× | Report **both** denominators: window and lifetime. A gate's number and a human's number are different questions | **M1** |
| F4 | ~~`deploy-lag` is structurally incapable of firing…~~ **REVISED on close reading of the code — the diagnosis was half right and the prescription was wrong.** `deploy-lag`'s own predicate is CORRECT and needs no polarity change: its semantic *is* "a GREEN commit sat undeployed", so a missing green is a legitimately absent premise, not a suppression — and `never-green` already exists as the backstop that covers it and DOES fire (verified live). What was genuinely missing was **MAGNITUDE**: `never-green` said "deploy has no cursor" (the cause) and nothing about how many commits of landed work were inert behind it — the number row 3 spent a whole rebuild not knowing | Fold the exposure into `never-green`'s DETAIL rather than add an overlapping alarm. Adding a second row for one fault is what this file's own comments warn against, and inventing a blocker is as bad as hiding one | **M1** |
| F5 | **THE HEADLINE.** 55 steps → 6 slots, fixed section order, so **2 of 5 classes are unreachable at any queue depth** (C6). A genuine class-C judgment call and a blocked work item — the two things most needing a human — cannot be rendered while ≥6 activations are pending | **Allocate the render budget per CLASS, not first-come.** Every class gets ≥1 line: its items if they fit, else an honest counted rollup carrying that class's own drill-down command. Truncation can then never delete a class (I10) | **M2** |
| F6 | Within activations, glob order = filename order, so `18-fleet` (12 dark labels) is always cut and `04-page-channel` is always shown | Rank by a signal already in hand at zero fork cost (C19): **CONFIRM-gated ⇒ has a real effect** (C15: 9 of 12). Effect-bearing activations rank above print-only ones | **M2** |
| F7 | Activation axis 1 hides everything staged <24h — 6 of 12 pending, and the 6 hidden are exactly the campaign's freshest rebuilds (C7). The operator reads "6 pending" and believes that is the queue | **Report the whole queue, partitioned by age.** The age gate was built against rot and now hides the window in which the operator still has context. Never hide a class (I10) | **M3** |
| F8 | `resolve_mirror()` derefs to the SHARED CHECKOUT, so parity is live-vs-checkout while the checkout trails trunk by 23 — **deploy lag masquerades as "never committed"**, and the dangerous direction (LIVE-ONLY ⇒ `cp` into a behind-checkout) is the one it fabricates | **Adjudicate LIVE-ONLY against `origin/main`**, and carry the checkout's trunk lag on every parity finding so a `cp` instruction is never issued blind. Latent today (C17: all 4 drifts are real) — fixed before it fires | **M4** |
| F9 | Axis 3's label regex is `com\.claude\.` only, so an activation whose effect is a `com.chrisren.*` label is unverifiable (C16) — row 12's exact scope bug, one layer out | Widen to both declared families, and distinguish DISABLED from NOT-INSTALLED via the literal `=> disabled` read with the sum checksum. **Defer to `bin/cc-fleet` when present** (consume row 12's contract, fail-soft when dark) | **M5** |
| F10 | The bug class recurs: F1's shape is one grep away from reappearing in the next alarm anybody writes | A declared-file **polarity lint** naming both shapes — equality against a failure name, and existence evidence taken from success history — plus the standing rule that every alarm carries a positive control that proves it FIRES on a non-verdict window (I3) | **M6** |
| F11 | `statusline.sh` renders on every UI update; its byte-identical slim rewrite plus proof harness sat stranded 4 days on an unlanded branch | Take it: `cherry-pick -x 78de6237`, verified clean, with the harness that extracts its own baseline from git. **Perf figure RE-DERIVED, not inherited: measured 108 ms → 63 ms (−42%) over 20 renders each on this box. The commit's own claim of 25-30 ms does not reproduce here** — its 108 ms baseline does, exactly. The take is still clearly right (a hot path every pane renders) but a number in a handed-down message is a claim like any other | **M7** |
| F12 | Reflexive: `operator-readout` is registered in 4 of 5 config dirs (C18) — this row's own surface is dark in one place, and no alarm covers a hook's own wiring | Recorded, not built here. The general mechanism (a hook-wiring alarm) is `beacon-inert`'s shape generalised and belongs to row 6 (guardrail/hook layer). **Named + backlogged, not silently carried** | — |
| F13 | **The frozen DoD's SECOND clause at its last remaining site.** Every sensor family fails OPEN by design (I6), so a ZERO-ROW board means EITHER "everything is healthy" OR "every sensor is broken" — indistinguishable. This is the incident quoted at the top of `bin/cc-blockers` verbatim: it said "no safeguard-blocked sessions surfaced" while a teammate was demonstrably blocked. `beacon-inert` closed that ONE case; the aggregate line still could not tell the two apart. (Per-family the distinction was already good — `NEVER-ACTIVATED` / `NOT-WIRED` / `UNRESOLVABLE` / `UNCONFIRMED` states across six kinds — which is why this is the last site, not the first) | The all-clear line carries a **SENSOR ROSTER with a count**: `— sensors 5/5 readable (stamps:ok launchctl:ok ps:ok fleet:ok board:ok)`. Scoped to READABILITY, never "every family rendered a verdict" — anything stronger needs a second implementation of each family's premise logic. **And it does not editorialize:** the first cut appended "NOT a clean bill of health" on any `x`, which on a fresh host (no board file, cc-fleet not installed) is NORMAL — it would have cried wolf on every clean install, the exact mirror of F5. A count is scannable and asserts nothing | **M8** |

### Mechanism specs

**M1 · POLARITY (`bin/cc-blockers`).** The read loop counts `notgreen` (`[ "$v" != green ]`)
alongside `red`; the alarm tests `notgreen -eq seen`; `state` is `PERSISTENT-RED` iff
`red == seen`, else `PERSISTENT-NOT-GREEN`. DETAIL carries `<seen> newest verdicts, 0 green
(<lifetime_green> of <lifetime> ever)`. `deploy-lag` gains a second, green-free trigger keyed on
the live layer's trunk position (declaration, not success history — I1). Kill switch:
`CC_BLOCKERS_ALARM_POLARITY=legacy` restores the `red == seen` test exactly.

**M2 · CLASS-COMPLETE RENDER (`hooks/operator-readout.sh`).** `steps_file` gains a leading class
key. Compose walks the classes in irreversibility order (deploy → activation → decision-C →
backlog-blocked → queue), spends at most `CC_OPREADOUT_PERCLASS` (default 2) itemized lines per
class, and emits a counted rollup line with that class's exact drill-down command for whatever it
could not itemize. Zero new forks (I19/C19): the CONFIRM rank in F6 reuses the `grep -q CONFIRM`
the loop already runs. Kill switch: `CC_OPREADOUT_CLASSBUDGET=off` restores flat first-come.

**M3/M4/M5 · `hooks/activation-watch.sh`.** One file, one commit. Axis 1 partitions rather than
filters (`CC_ACTIVATION_AGE_FILTER=on` restores). Axis 2 adjudicates LIVE-ONLY against trunk and
annotates lag (`CC_ACTIVATION_TRUNK_ADJUDICATE=off` restores). Axis 3 widens scope and consumes
`cc-fleet` fail-soft (`CC_ACTIVATION_INERT_SCOPE=claude` restores).

**M6 · `scripts/alarm-polarity-lint.sh`.** Declared file list, two patterns, reports per site with
a suppression comment convention for a deliberate verdict-equality. Blocks on the **DIFF**, never
the whole tree (memory `whole-tree-lint-is-a-fleet-wide-hard-stop`). Kill switch:
`CC_ALARM_POLARITY_LINT=off`.

---

## §5 · Rejected alternatives (recorded so they are not relitigated)

| Rejected | Why |
|---|---|
| **Raise `CC_OPREADOUT_MAX` from 6 to 55** | This is the Phase-2 trap verbatim — the old design with bigger constants. The queue only grows; 55 lines at every Stop trains the operator to skip the block entirely, converting a starvation failure into an alarm-fatigue failure. The defect is *allocation*, not *size* |
| **Global priority score over all 55 steps** | Requires a comparable weight across four incommensurable stores (a deploy lag vs a judgment call vs a blocked ticket). Any weighting is a guess that hides the same classes silently, and it needs forks `render_block` cannot afford (C19) |
| **Fold `deploy-lag`/`never-green` into one row** | They have different owners and different recovery actions (F2). Merging is what suppression already does, made permanent |
| **Reimplement launchd state in `activation-watch`** | Row 12 owns the 6-state function; a second implementation is a second answer. Consume `cc-fleet`, degrade honestly when dark (the map's fail-soft ruling) |
| **Drop the `>24h` age gate entirely and page on everything** | Would page on an activation staged 30 seconds ago by the session still running. Partitioning keeps rot loud *and* keeps the fresh class visible without pretending it is overdue |
| **Take `tests/statusline-mail-badge.bats`** | Tests a `📬` badge absent from trunk; the feature is row 3's surface and row 3 (DONE) chose not to land it. Would land a red suite |
| **Take `fix/infra-perfection` / `tm/hygiene` wholesale** | 55 commits at 379 behind; the originating doc's own plan is 25 branches smallest-diff-first and serialized. Out of scope by that doc's design |
| **`revert` as the rollback plan for any mechanism** | I8. Every mechanism above ships a named env kill switch |
| **Fix the alarm by hand and skip the proof bar** | Explicitly refused by the coordinator's ruling: row 10 fixes it *with* the full Phase-4 bar, because the seam (row 1's vocabulary leaking into row 10's predicate) is the generalisable part |

---

## §6 · Acceptance criteria — as DISK-TRUTH READS, not narration

Each row names the file or command that proves it. A criterion nobody can run is not a criterion.

| # | Claim | The read that proves it |
|---|---|---|
| A1 | `trunk-red` fires on the live window | `bash bin/cc-blockers \| grep -c 'trunk-red'` ⇒ ≥1 while `newest 5` contains a non-verdict and 0 green |
| A2 | …and names the mixed window honestly | that row's `state` reads `PERSISTENT-NOT-GREEN`, not `PERSISTENT-RED`, while `red(4) ≠ seen(5)` |
| A3 | The board's denominator is honest | `cc-blockers --json \| jq -r '.[]\|select(.kind=="never-green"\|.kind=="trunk-red").detail'` names **33**, not 5 |
| A4 | `deploy-lag` is reachable with 0 greens | a `deploy-lag` row appears while `last-green` is absent and the live layer is >0 behind trunk |
| A5 | **0 of 5 classes starved** | `bash hooks/operator-readout.sh --render` ⇒ every class present in `steps_file` appears either itemized or as a counted rollup; `grep -c 'decision C'` ≥1 and `grep -c 'backlog'` ≥1 at the default `MAX` |
| A6 | Effect-bearing activations outrank print-only ones | in that render, `18-fleet-activate.sh` precedes `04-page-channel-activate.sh` |
| A7 | No new fork in `render_block` | `git diff origin/main -- hooks/operator-readout.sh \| grep -cE '^\+.*\$\((git\|jq\|cc-)' ` ⇒ 0 |
| A8 | The activation surface reports the whole queue | SessionStart advisory names **12**, and partitions it; `ls …/*.sh \| while …` cross-check agrees |
| A9 | LIVE-ONLY is trunk-adjudicated | a live-only file that exists on `origin/main` is NOT reported LIVE-ONLY; the finding carries the checkout's lag |
| A10 | Axis 3 sees both label families | `13-mailbox-gc-activate.sh`'s `com.chrisren.*` label is in axis-3's scope (test asserts the regex, plus a fixtured positive control) |
| A11 | The bug class cannot recur silently | `bash scripts/alarm-polarity-lint.sh` exits non-zero on a seeded `-eq "$seen"` and zero on the fixed tree |
| A12 | Every new absence assertion has a positive control | each new bats file contains a case that proves the detector FIRES, adjacent to the case that proves it is quiet |
| A13 | Every new test RED-proves | each suite run against a `git archive` of pristine `origin/main` fails on the cases that encode the new behaviour |
| A14 | statusline output did not move | `tests/statusline-identity.bats` green, including its own harness self-check |
| A15 | Kill switches restore the incumbent | with all `CC_*=legacy/off/on` set, board + render output is byte-identical to `origin/main`'s |

---

## §7 · Phase 0 · orchestration

Single-lead, no teammates. Rationale against the standard 2+-files rule: the four surfaces are
**one shared contract** (the alarm table, the render budget, the platter) and the whole defect
class is a *seam* bug — split ownership is what produced it. Deliverable is ~400 LOC across 4
files plus suites, well under the 500-LOC split threshold, and the campaign's own record shows the
sequential-stage fan-out trap (memory `staged-skill-fanout-trap`) applies: the stages share state,
so fan-out would be dominated. Live load at Phase-1 close was already elevated by sibling rows.

Land order, continuously via `scripts/ship-land.sh`, never batched:

1. this design doc
2. **M1** polarity + suite (the coordinator-ruled defect — first)
3. **M2** class-complete render + suite (the row's headline)
4. **M3/M4/M5** activation-watch, one commit + suite
5. **M7** `cherry-pick -x 78de6237` + green `statusline-identity.bats`
6. **M6** polarity lint + suite
7. map row 10 + learnings

**Cited-sha rule:** `ship-land.sh` rebases, so every sha in this document is resolved against
`origin/main` after landing (`git merge-base --is-ancestor <sha> origin/main`) and corrected in a
follow-up land. Row 3 hit exactly this in a doc whose whole purpose was disk-truth citations.

## §8 · Landed shas — ALL SEVEN VERIFIED ON TRUNK

Resolved with `git merge-base --is-ancestor <sha> origin/main` **after** landing, never from local
HEAD: `ship-land.sh` rebases, so a pre-land sha names a commit that is not on trunk. Row 3 hit
exactly this in a doc whose whole purpose was disk-truth citations.

| # | Increment | sha | ancestor of `origin/main` |
|---|---|---|---|
| 1 | design doc (§0-§8) | **`a95f4f38`** | ✓ |
| 2 | **M1** alarm polarity — for a VERDICT ask "is it red?", for an ALARM ask "is it green?" | **`f1451bcf`** | ✓ |
| 3 | **M2** per-CLASS render budget | **`7662ce58`** | ✓ |
| 4 | test determinism — a bare `touch` races `stat %m`'s 1-second granularity | **`a8a0f163`** | ✓ |
| 5 | **M3/M4/M5** activation queue: whole-queue report · trunk-adjudicated LIVE-ONLY · both label families | **`97667057`** | ✓ |
| 6 | **M7** graveyard recovery — `cherry-pick -x 78de6237` + hermeticity fix | **`df6b328f`** | ✓ |
| 7 | **M6** alarm-polarity lint + suite | **`6937d001`** | ✓ |
| 8 | map row 10 DONE + five campaign learnings | **`07b9499c`** | ✓ |
| 9 | dead assertion in the recovered harness SELF-CHECK (`\| \| false`) | **`fca95afd`** | ✓ |
| 10 | **M8** the all-clear line's SENSOR ROSTER | **`030e0f39`** | ✓ |
| 11 | §4 F13/M8 + the rebase-trap note | **`a29473c0`** | ✓ |
| 12 | **the lint did not catch the bug it was written for** — control tightened, pass 1 widened | **`471df5dd`** | ✓ |

**The rebase trap, hit live and worth recording.** Increment 9 was committed locally as `3f42ab7a`;
`ship-land.sh` rebased it over two sibling lands and it reached trunk as **`fca95afd`**, so
`git merge-base --is-ancestor 3f42ab7a origin/main` returns **1** while the content is unambiguously
on trunk. A row that had cited its local sha would have published a citation that resolves to
nothing — and a row that had *verified by sha* would have concluded its own land failed. **Verify by
CONTENT, then resolve the sha from `origin/main` by grepping the subject.** Increments 1-8 were
fast-forwards and their local shas survived; that is luck, not a rule.

## §9 · Close against the frozen DoD

**Both DoD integers met, read off disk, not narrated.**

| DoD target | Before | After | The read |
|---|---|---|---|
| classes starved at any queue depth | **2 of 5** | **0 of 5** | `hooks/operator-readout.sh --render` — all four active classes present at 57 steps / MAX=6 |
| alarm predicates testing a named failure where absence-of-success is meant | **1 of 9, live-suppressed** | **0** | `scripts/alarm-polarity-lint.sh` → clean, 4 files, 1 explained suppression |
| sites where "nothing to report" is indistinguishable from "the check never ran" | **1** (the board's aggregate all-clear line) | **0** | `cc-blockers` all-clear prints `sensors N/5 readable (…)`; per-family already covered by 6 kinds with NEVER-ACTIVATED / NOT-WIRED / UNRESOLVABLE / UNCONFIRMED states |

**PROVEN (disk reads, re-derived at close):**
- **A1/A2** `cc-blockers` emits `trunk-red / PERSISTENT-NOT-GREEN — newest 5: 4 red 1 nonverdict,
  0 green`, carrying the failing-test histogram platter. Pre-fix this window produced **no**
  `trunk-red` row at all.
- **A3** the DETAIL names the lifetime (34 stamps: 31 red · 2 cut · 1 hung · **0 green ever**), not
  the 5-wide window it used to report as if it were the whole history.
- **A5/A6** all four step classes render; `↳` rollups carry `+10 activation`, `+12 decision`,
  `+29 backlog` with each class's own listing command. Effect-bearing activations lead.
- **A7** zero new forks in `render_block`; net one fewer.
- **A8** the queue surface names **12 of 12** pending (was 6 of 12), partitioned ROTTING/FRESH.
- **A11** the lint is clean on the fixed tree and **fires on the real pre-fix predicate recovered
  from git** — the positive control, not an approximation. **CORRECTED after first being claimed
  falsely:** as first landed, the control's baseline selector was "the newest `bin/cc-blockers`
  containing `[ "$red" -eq "$seen" ]`" — a string that SURVIVES in the fixed file, where the
  state-naming line legitimately uses it under `# alarm-polarity-ok:`. One commit later the selector
  extracted the *current* justified version, so the control tested the wrong file. Tightening it to a
  genuinely pre-fix baseline (predicate present, no marker, no `notgreen`) plus a harness self-check
  then exposed the defect underneath: **the lint did not fire at all.** The original bug was written
  `seen=$((seen + 1)); [ "$v" = "red" ] && red=$((red + 1))` on ONE line, and pass 1's single
  `match()` registered `seen` — the window counter — never `red`. The lint recognised only the
  post-fix layout, i.e. it would have shipped as a guard against a shape it could not see. Pass 1 now
  collects every increment on the line; verified against `39ebcd07` it reports the exact line and
  variable of the original defect. **Two compounding defects, both mine, both already landed, and
  neither would have been found without a control tightened past the point where it was comfortable.**
- **M8** the all-clear line now reads `— sensors 5/5 readable (stamps:ok launchctl:ok ps:ok fleet:ok
  board:ok)`, and names any sensor it could not read. That closes the frozen DoD's second clause at
  the last site where it was still open; per-family it was already covered by six kinds carrying
  `NEVER-ACTIVATED` / `NOT-WIRED` / `UNRESOLVABLE` / `UNCONFIRMED` states.
- **A13** every suite RED-proofed against a `git archive origin/main` pristine tree: cc-blockers
  8/12, operator-readout 8/10, activation-watch 9, lint 1 (its positive control). In every case the
  cases that pass on pristine are exactly the positive controls and the kill switches, which by
  definition must reproduce the incumbent.
- **A14** `statusline.sh` output byte-identical (10/10 incl. the harness self-check + a live check).
- **A15** kill switches restore the incumbent: `CC_OPREADOUT_CLASSBUDGET=off` is **byte-identical**
  to `origin/main`'s render; `CC_BLOCKERS_ALARM_POLARITY=legacy` restores the suppression exactly.
- **Dead-assertion sweep run at close** rather than assumed from green runs. Four of this row's five
  suites were clean; the fifth — `tests/statusline-identity.bats`, recovered from the graveyard — had
  a non-final `!` inside the harness SELF-CHECK whose entire job is preventing a vacuous pass, so it
  could not fail. Proved in BOTH directions on a deliberately-false variant: with `|| false` → `not
  ok`, without it → `ok`.
- **Every artifact re-run under `/bin/bash` (3.2.57)**, the version a launchd or hook invocation gets:
  `cc-blockers` (PERSISTENT-NOT-GREEN), `operator-readout --render`, `activation-watch`,
  `alarm-polarity-lint`, `statusline.sh` — all correct. On this box `env bash` also resolves to 3.2,
  so the suites were already exercising it; asserted rather than assumed.
- Totals: **cc-blockers 67/67 · operator-readout 35/35 · activation-watch 27/27 (+ selftest 18/18) ·
  alarm-polarity 7/7 · statusline-identity 10/10 · cc-blockers-fleet 27/27 = **173 pass / 0 fail**,
  plus the activation-watch selftest 18/18. All gate-green through `scripts/ship-land.sh`,
  **12 lands, never batched.**

**IN FLIGHT (autonomous, owner named):** nothing of this row's. All seven increments are landed and
every edit is in an already-symlinked live file, so **this row needs no activation step** — unlike
rows 4, 5, 12 and 13. Its output changes at the next SessionStart / Stop in each session.

**ACCRUING (time-dependent, and where it will be read):**
- The queue-drain metric. The surface now reports 12 of 12; whether the operator's un-run count
  actually falls is measured by `for f in …/pending-activation/*.sh; do [ -f "$f.done" ] || echo; done
  | wc -l` over days, not by this rebuild.
- `trunk-red`'s platter only pays off when someone runs it. The histogram it hands over is the first
  actionable thing the board has offered about the 0-green deadlock (`cc-backlog da18f179ac50`).

**REMAINDERS — named, not silently carried:**
- **R-1 (row 1 seam, ping sent).** Wiring `alarm-polarity-lint.sh` into `run_gate` as a blocking
  diff-scoped gate touches `scripts/ship-land.sh` — row 1's file. Enforcement today is via
  `tests/alarm-polarity-lint.bats`, which run_gate already executes in own-scope when a declared
  alarm file changes. That is real enforcement for this row's surfaces and short of the
  fleet-wide ratchet the rule deserves.
- **R-2 (row 6).** `operator-readout.sh` is registered in **4 of 5** config dirs (absent from
  `~/.claude-next`) — this row's own close block is dark in one place and no alarm covers a hook's
  own wiring. The general mechanism is `beacon-inert`'s shape generalised to every declared hook,
  which is row 6's surface (guardrail/hook layer). Backlogged, not built here.
- **R-3.** The sibling polarity shape — existence evidence from a subject's own success history —
  is deliberately NOT linted (see §4 M6 for why a checker would fire on correct code). It stays a
  review rule under §3 I1.
- **R-4.** `tests/statusline-mail-badge.bats` REJECTED with reasons (§1.2); the 📬 badge is row 3's
  call and row 3 is DONE without it.

**Methodology note earned here:** `shellcheck -S warning` is a WEAKER check than the land gate,
which runs at default severity. One land went RED on an `SC2016` **info** that the pre-land check
passed. Verify with bare `shellcheck` before every land.
