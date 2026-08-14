---
status: in-progress
---

# DAEMON FLEET V2 — first-principles architecture for what runs unattended

**Scope (frozen):** the daemon fleet & activation subsystem achieves **every staged job either
RUNNING or ALARMING within 24h of being staged**, under the standing constraint of the
disabled-bit trap and the C10 boundary (an agent stages, the operator activates once) — measured,
landed, and verified by disk-truth acceptance reads.

Status: DESIGN 2026-07-29 · row 12 of docs/plans/GROUND_UP_REBUILD_MAP.md · branch
`gu-daemon-fleet-activation` · methodology skills/ground-up/SKILL.md · exemplar
docs/plans/LAND_PIPELINE_V2.md

> **Note on the standing goal.** The dispatch brief's STEP 1 asked for `/goal`. No such command
> exists on this box (`~/.claude/commands/` has 22 entries, none named `goal`; no `cc-goal` in
> `~/.claude/bin/`; `find ~/.claude -maxdepth 2 -name '*goal*'` is empty). The frozen DoD above is
> the durable substitute — it is on disk, in the repo, and survives recycles, which is what the
> standing goal was for. Recorded rather than silently skipped.

---

## Phase 0 — Agent Team Orchestration

Three teammates, disjoint file ownership, spawned concurrently. No `blockedBy` edges: T2 and T3
depend on T1's **contract** (the manifest schema §4.1 and the verdict-row JSON §4.2.3), which is
frozen in this document, not on T1's code.

| Teammate | Deliverable | Owns (exclusive) | Worktree |
|---|---|---|---|
| `df-reconciler` | the six-state fleet reconciler + the manifest | `launchd/fleet.manifest`, `bin/cc-fleet`, `tests/cc-fleet.bats` | shared (see note) |
| `df-board` | board integration + plist SSOT parity leg | `bin/cc-blockers` (fleet rows only), `tests/cc-blockers-fleet.bats` | shared (see note) |
| `df-platter` | the one C10 operator command + queue staging | `docs/activation/pending-activation/18-fleet-activate.sh`, `tests/fleet-activate.bats` | shared (see note) |

> **Worktree note (measured, 2026-07-29 — correct this expectation in future rebuilds).** On this
> runtime an `Agent({team_name})` spawn did **not** create per-teammate worktrees: `git worktree
> list` showed a single entry and all three teammates ran in the lead's tree. Isolation therefore
> came from **disjoint file ownership plus an explicit-paths staging rule**, not from git. The
> standard brief line "commit on your own branch" is actively DANGEROUS under that arrangement — a
> `checkout -b` moves the tree under two siblings and the lead mid-write — so all three were
> corrected to commit on the current branch and to `git add` explicit paths only, never `-A`. Check
> `git worktree list` after spawning rather than assuming the isolation the roster implies.

Lead (this session): this plan, the contract freeze, integration review, merge order
(smallest-diff first, rebase + ff-only, serialized), continuous landing via the project-local
`/ship`. Briefs ≤150 lines, pre-greped line ranges, verbatim stop-on-issue clause.

**Checkpoint-review criteria (lead, at each Phase A ack) — written here BEFORE spawning:**

1. `df-reconciler`: the state function must be **total** — every declared label resolves to exactly
   one of S0–S6 (§3.1) with no fall-through, and the suite must prove each of the seven arms with a
   fixture. `launchctl` is reached ONLY through `CC_FLEET_LAUNCHCTL_BIN` (stubbed in tests, never
   real launchd) and ONLY via read-only subcommands (`list`, `print`, `print-disabled`). Any
   `plutil -extract` carries `-o -` (memory `plutil-extract-clobbers-input`: without it the plist is
   rewritten in place; 5 LaunchAgents were destroyed this way). No `case` inside a `$( )` (bash 3.2
   command-substitution parser death — `bash -n` and shellcheck both pass it).
2. `df-board`: fleet rows must be **additive** — the existing `alarm_rows()` and
   `dispatch_alarm_rows()` keep their exact current output (rows 1 and 5 own those semantics; this
   rebuild consumes, never redesigns). A sensor failure fails **open** (no row), never invents one.
   The DETAIL cell is ASCII-only and ≤44 bytes (the renderer pads by BYTES; one em-dash shifts the
   column).
3. `df-platter`: the script must `launchctl enable` **before** `bootstrap` (§1.3 — bootstrap alone
   returns EIO on a disabled label and prints nothing useful), be idempotent, be self-verifying via
   `launchctl print` (not `list | grep`), and never run launchctl inside its own tests. It gates real
   work behind `CONFIRM=1` — and because that idiom is exactly what produced the claimed-done-but-inert
   class (§5 F7), a bare run must print a line that says so in words.
4. All: `shellcheck` + own-suite `bats` green before ack; every new test RED-proofed against the
   pristine pre-change tree recovered by `git archive` (never a hand-edited approximation); a
   positive control beside every absence assertion; `|| false` on every non-final `[[ ]]`; every
   launchd-bound artifact re-run under `/bin/bash` (the agent Bash tool runs zsh, so repros lie).

**Checkpoint log:** (appended as acks land)

---

## §1 First principles — why the incumbent frame cannot work

### 1.1 The observed reality, measured this session

Fourteen `com.claude.*` jobs are registered in this user's launchd domain. **Ten are disabled.**
Of the four that are enabled, one — `com.claude.deploy-live` — has **never once succeeded in its
entire life**: 59 logged `cannot execute` failures, `runs = 15`, `last exit code = 1`, and its log
has been frozen for 3h48m against a declared 600-second interval.

The operator board, read at the same moment, printed `no safeguard-blocked sessions surfaced`.

That pair of facts is the whole problem. The subsystem is 71% dark, its deploy daemon has never
worked, the live layer is behind trunk — and the surface built to surface exactly this said
nothing.

### 1.2 Why nothing said anything — the enumeration bug

The only mechanism that watches activation, `hooks/activation-watch.sh`, is genuinely good: three
axes, an effect-read on `.done` markers (axis 3, added 2026-07-29 after `02-load-dispatcher` and
`03-load-discovery` sat `.done`-marked and unloaded for 10 days), a `.local` exemption, and a
loud-not-silent failure when its own mirror cannot be resolved. It is not a weak check.

It is a check of **the wrong set**. Every axis iterates `"$DIR"/*.sh` — the *activation queue*, a
list of scripts an agent happened to stage. It never iterates the *fleet*. Measured consequence:

> **8 of the 10 dark jobs are named by no pending-activation script at all** — `team-orphan-reaper`,
> `nightly-regression`, `log-rotation`, `lead-supervisor`, `session-search-sweep`,
> `session-search-backfill`, `desk-invariant`, `boot-resume`. They are invisible to all three axes
> by construction. The two that *are* visible (`power-policy-verify`, `caffeinate-floor`) are
> visible only incidentally, because `05-pmset-caffeinate-activate.sh` is itself un-run and >24h old
> — axis 1 is naming the *script*, not noticing the *jobs*.

`bin/cc-blockers` adds two more daemon alarms, and they are the right shape (existence evidence
first, `launchctl` read for both loaded-ness and the disabled bit, `NOT-ACTIVATED` distinguished
from `STALE` because they have different owners and different fixes, fail-open on sensor error).
But they are **hand-written per label** — `alarm_rows()` for row 1's verifier, `dispatch_alarm_rows()`
for row 5's dispatcher, the second explicitly commented "Mirrors `alarm_rows()` above deliberately".
Two labels of fourteen have an alarm. A third daemon means a third copy-paste. **Twelve have none.**

So coverage is not a property of the fleet; it is a property of who remembered. That is the frame.

### 1.3 The disabled bit — one trap, three silent states

`launchctl disable gui/501/<label>` writes `<label> => 1` into
`/var/db/com.apple.xpc.launchd/disabled.501.plist` — a **root-owned file outside the repo, outside
the plist, and outside every check anyone has written**. It survives reboot. A disabled label
cannot be bootstrapped: `launchctl bootstrap` returns EIO, which `install.sh` swallows (recorded
independently in LAND_PIPELINE_V2.md:191-192 — "activation MUST `launchctl enable` before
bootstrap; install.sh's bootstrap alone fails EIO silently").

And a disabled job **does not appear in `launchctl list` at all**. Since every existing check asks
`launchctl list | grep <label>`, the real state space collapses:

| Real state | What `launchctl list \| grep` returns |
|---|---|
| S1 declared but never installed | absent |
| S2 installed but **disabled** | absent |
| S3 loaded, `runs = 0`, never executed | **present** |
| S4 loaded, executing, **every run fails** | **present** |
| S5 loaded, enabled, scheduled, **not firing** | **present** |
| S6 healthy | present |

Four of the six broken states read as *healthy*, and the two absences are indistinguishable from
each other and from "this job was never supposed to exist". `deploy-live` is a live S4→S5: it
failed 59 times, then launchd's fast-fail throttle (`minimum runtime = 10` in its own
`launchctl print`) stopped scheduling it, and **the failure got quieter with age**. A broken daemon
decays into a silent daemon on its own.

### 1.4 Why `.done` cannot carry this weight

An activation is currently "complete" when a marker file exists beside the script. A marker records
that **a script ran**; only launchd records that **the effect landed**. `activation-watch.sh`'s own
axis-3 comment documents the 10-day dispatcher outage this produced. Axis 3 fixed the narrow case
(`.done` + a `com.claude.*` label mentioned in the script + `launchctl list`), but it inherits both
holes above: it only sees queue-staged labels, and `launchctl list` cannot see S3/S4/S5.

**Conclusion (the inversion).** Activation is not an event with a receipt. It is an **invariant that
must be continuously reconciled**. Stop asking *"did the activation script run?"* — a question about
the past, answered by a claim — and start asking *"does the world match the declaration?"* — a
question about now, answered by launchd. One manifest declares intent for every label; one
reconciler computes the total six-state truth for every declared label and emits one parseable
verdict each; the operator board renders every non-healthy verdict. Coverage stops depending on who
remembered, because **a daemon is covered the moment it is declared, not when someone writes it an
alarm.**

### 1.5 The refinement this forces on the absence-alarm law

Memory `absence-alarm-needs-existence-evidence` says: only alarm where X was *supposed* to run, else
fixtured voids fire phantom rows. That law is correct and `dispatch_alarm_rows()` implements it
faithfully — it gates on ≥1 prior `cc-dispatch` journal record before it will claim staleness.

But *that* implementation takes the existence evidence from **the subject's own success history**.
Which means a daemon that has **never worked once** is indistinguishable from a daemon that was
never supposed to exist — so it is never alarmed. And "never worked once" is precisely the
population that matters here: 8 silent jobs plus `deploy-live`, whose covering alarm (`deploy-lag`)
is additionally gated on a GREEN stamp — of which **there are 0 in 33** (30 red, 2 cut, 1 hung), so
that alarm is *structurally incapable of firing* no matter how long the deploy lane stays broken.

> **The refinement (design law for this row):** existence evidence must come from a **DECLARATION**,
> never from the subject's own past success. A declared job that has never run is the LOUDEST case,
> not the silent one. An alarm whose premise depends on the healthy operation of the chain it
> monitors cannot fire when that chain was dead from the start.

This is what makes the manifest load-bearing rather than bookkeeping: it is the existence evidence
that lets absence be loud without inventing phantom rows in fixtured `$HOME` voids.

### 1.6 Verdict on the map's standing-constraint cell — CONFIRMED but INSUFFICIENT

Row 12's cell reads *"disabled-bit trap; agent stages / operator activates"*. Per the map's
2026-07-29 learning, that is the prior session's hypothesis and Phase 1 must kill or confirm it.

**Confirmed:** the disabled-bit trap is real and is primary disk truth — 10 of 14 labels carry
`=> 1` in the root-owned override db, the bit survives reboot, it is invisible to `launchctl list`,
and `bootstrap` without a prior `enable` fails EIO. The C10 boundary is likewise real.

**Insufficient, and the insufficiency is the design:** the cell names *one* silent state, and
designing against only that state leaves the other two silent. `deploy-live` is **enabled, loaded,
and broken** — the disabled bit has nothing to say about it, and it is the single most consequential
failure in the fleet (it is why the live layer is behind trunk). Had this rebuild inherited the cell
unexamined, it would have shipped an enable-the-disabled-jobs fix and declared victory while the
deploy daemon stayed dead. The cell is promoted from *one trap* to a **three-state truth**: not
installed · installed-but-disabled · loaded-but-not-executing.

**And the handed-down count itself was already stale.** The dispatch brief and the map learning both
state 12 disabled / 2 enabled, verified by the coordinator earlier the same day. Live re-derivation
hours later reads **10 disabled / 4 enabled** — `dispatcher` and `discovery` are both enabled and
loaded (`dispatcher` pid 74276), their live plists rewritten at 11:06 and the override db at 12:22
today. Nobody was wrong; the measurement simply decayed. That is the subsystem's defining property in
miniature: **fleet state is a moving target that no mechanism re-reads.** A one-shot manual
`launchctl print-disabled` is stale within hours, which is exactly why the answer has to be a
reconciler on a schedule and not a better audit.

*(Consequence for row 5, already pinged to the coordinator: its "dispatch decision ≤5 min" metric is
now MEASURABLE rather than 0-by-construction.)*

### Requirements — invariants that survive the redesign

Sorted from MEMORY.md and the incident record per Phase 2 of the skill (invariants become numbered
requirements; the incumbent's mechanisms are inherited from nothing).

- **R1** Every job declared in the fleet manifest resolves to exactly one total state S0–S6; no
  label falls through, and no state is inferred from a single sensor.
- **R2** Existence evidence comes from the declaration, never from the subject's own success history
  (§1.5). A declared-`run` job that has never executed is the loudest row on the board.
- **R3** Absence stays loud *with* existence evidence: an undeclared label never produces a row, so
  fixtured `$HOME` voids and other hosts stay silent (memory `absence-alarm-needs-existence-evidence`).
- **R4** Liveness is proven by **durable products**, never by mtime alone — launchd's own
  `runs`/`last exit code` plus the manifest-declared evidence artifact, two independent sensors
  (memory `effect-read-predicate-red-proof`: built ≠ deployed ≠ exercised).
- **R5** A sensor that cannot run **says so** and fails **open** — never a vacuous pass, never an
  invented row (the `816015ecb30b` vacuous-parity class; the false `verifier-inert` from a bash-3.2
  `case`-in-`$( )` death).
- **R6** Every live plist has a repo SSOT copy, and drift in either direction is reported (memory
  `plutil-extract-clobbers-input` — 5 LaunchAgents destroyed by an in-place rewrite; `-o -` is
  mandatory on every `plutil -extract`).
- **R7** The verdict is a **parseable structured token**, not prose, so its consumer cannot mistake a
  claimed outcome for a checked one (memory `claimed-outcome-vs-checked-outcome`).
- **R8** A non-verdict is never a red: sensor-unavailable, undeclared, and deliberately-retired are
  distinct from broken (memory `named-failure-vs-no-verdict`).
- **R9** The C10 boundary is respected absolutely: the agent stages and drives to the gate; a single
  proven, env-seam-resolved command is plattered in **both** the live queue and the repo SSOT; the
  agent never mutates launchd (memory `classifier-enforced-activation-deploy-boundary`).
- **R10** Every new mechanism ships with an env kill switch, never revert-as-plan; and it must
  **fail loud when inert** — a reconciler that stops running is itself a declared job subject to its
  own reconciliation (memory `feature-durability-mechanism-not-memory`: ~100% abstain ⇒ inert by
  construction).
- **R11** Carried rows are consumed **fail-soft**: rows 1, 4, 5, 7 and 8 may be landed-but-inert, and
  this design's correctness never depends on any of them being activated (map ruling 2026-07-29).

---

## §2 Measured constants this design is built against

Every row re-derived from primary disk truth this session. Handed-down counts are marked where they
disagreed.

| Constant | Value | Source |
|---|---|---|
| `com.claude.*` labels in the domain | **14** | `launchctl print-disabled gui/501` |
| Disabled / enabled split | **10 / 4** (brief and map both said 12/2 — **stale**) | `launchctl print-disabled gui/501`; `/var/db/com.apple.xpc.launchd/disabled.501.plist` |
| Enabled AND loaded | 4: postland-verify (pid 94251), dispatcher (pid 74276), discovery, deploy-live | `launchctl list \| grep claude` |
| Dark jobs named by **no** activation script | **8 of 10** | `grep -rl 'com\.claude\.<lbl>' ~/.claude/autonomy/pending-activation/*.sh` per label |
| Fleet labels with a bespoke `cc-blockers` alarm | **2 of 14** (postland-verify, dispatcher) | `bin/cc-blockers:100-177`, `:199-239` |
| Last boot (origin of the mass-dark state) | **Mon 2026-07-27 19:02:44** | `sysctl -n kern.boottime`; corroborates LAND_PIPELINE_V2.md:190 |
| Fleet dark for | **~43h** at time of writing | boottime vs `date` |
| `deploy-live` logged failures | **59** `cannot execute` lines, one per failed run | `grep -c 'cannot execute' ~/.claude/autonomy/postland/deploy.log` |
| `deploy-live` launchd counters | `runs = 15`, `last exit code = 1`, `state = not running` | `launchctl print gui/501/com.claude.deploy-live` |
| `deploy-live` declared vs actual cadence | `run interval = 600s`; log frozen **3h48m** (≈22 missed intervals) | same print; `stat -f %m` on deploy.log |
| `deploy-live` root cause | `~/.claude/scripts/deploy-live.sh` absent until **Jul 29 10:32**; last failure 10:28 | `ls -la ~/.claude/scripts/deploy-live.sh` |
| GREEN stamps in system history | **0 of 33** (30 red · 2 cut · 1 hung) | `jq -r .verdict ~/.claude/autonomy/postland/stamps/*.json \| sort \| uniq -c` |
| ⇒ `deploy-lag` alarm firing capability | **structurally 0** — gated on `[ -n "$gcommit" ]` | `bin/cc-blockers:169` |
| Deployed HEAD vs trunk | `32c05b01` vs `origin/main 1d7ada13` — live layer **behind** | `git -C ~/Development/claude-infrastructure rev-parse HEAD` |
| Operator board content at that moment | `no safeguard-blocked sessions surfaced` (**empty**) | `~/.claude/bin/cc-blockers` |
| Live plists with **no** repo SSOT copy | **1** — `com.claude.lead-supervisor` | `ls ~/Library/LaunchAgents/com.claude.*` vs `launchd/*.plist` |
| `lead-supervisor` dark for | **354h** (~14.8 days) | `stat -f %m` on its `StandardOutPath` |
| Jobs that have **never** produced a log line | **8** incl. `session-search-sweep` (declared `StartInterval 60`) | per-label `plutil -extract StandardOutPath raw -o -` + `stat` |
| Pending-activation queue | 21 scripts repo-side / 21 live + 10 `.done`; **7** staged >24h un-run | `ls` both dirs; `hooks/activation-watch.sh` axis 1 |
| Activation SSOT drift | **6** — 1 live-only, 1 repo-only, 4 content-drift | `activation-watch.sh --parity` |

### 2.1 Archaeology deltas (Phase 1 researcher, 2026-07-29 — every one re-verified by the lead)

**The open operator question is ANSWERED, not ruled on. The mass-disable was DELIBERATE.**
An operator-directed fleet shutdown ran **2026-07-26 11:46–11:56 PDT** via `/tmp/claude-fleet-shutdown.sh`,
recovered verbatim from a transcript in `~/.claude-tertiary/` (`7ef6df8d-1d41-…jsonl`). It ran
`bootout` + `disable` + `unload -w` over **exactly 13 labels — set-identical to the 13 `true`
entries in the override db**, and its own header states the motive: four of those jobs *create
sessions on a timer*, so closing panes could not converge (31 live processes, load 17). Corroborated
independently by `~/FLEET-SHUTDOWN-PATCHES/` (7 worktrees snapshotted 11:45:27, seconds before) and
by `AUTONOMY_DISPATCH_V2.md:130-131` ("last dispatch pass 18:41:33Z"). The **07-27 19:02 reboot was
the amplifier, not the cause** — it converted 13 latent bits into 0 loaded jobs. Backlog
`107f27fbb00c` should be **closed with this evidence**.

> **This is why the manifest's `staged` class is load-bearing rather than bureaucratic.**
> `desk-invariant` and `boot-resume` are the runaway session **generators** the shutdown existed to
> stop; re-enabling either without a fleet concurrency ceiling **reopens the incident**. The other 8
> were collateral, disabled only because they run bats suites or hold the machine awake. A mass
> re-enable — the obvious fix, and the one an unexamined reading of the map cell invites — would
> have re-created the outage. Both generators are declared `staged`, and the platter touches only
> `expect = run`, so the design refuses that guess *structurally*, not by remembering to.

> **CORRECTION 2026-08-14 — the prohibition is REFUTED for `desk-invariant`. It stands, untested,
> only for `boot-resume`.** (backlog `ff6a95a1779b`.) The paragraph above is kept verbatim: it is the
> reasoning the platter and `install.sh`'s manifest gate were built from, and both are still right.
> What does not survive is the word **generator** applied to `desk-invariant`, and the precondition
> attached to it.
>
> 1. **It has never generated a session.** Its only production figure is **266 fire attempts over
>    41 h** (2026-07-23T07:35Z → 2026-07-25T01:02Z), and **every one returned nonzero and created
>    nothing** — the anchorless-refusal outage recorded in `scripts/desk-invariant.sh:221-227` and
>    `:445`. At the 07-26 bootout its lifetime session count was **0**. It was collateral like the
>    other 8, not one of the four jobs the shutdown header names.
> 2. **The per-job ceiling already existed, and predates the shutdown.** `RESPAWN_MAX=2` /
>    `RESPAWN_WINDOW_S=21600` (`:100-101`); exhaustion is **page-only, never a respawn loop**
>    (`:439`); and the budget marker is written **before the attempt**, so a permanently-failing fire
>    consumes budget (`:441-448`). That last fix landed **2026-07-25 — a day before the bootout**.
>    The prohibition was written against the pre-fix script, where the 266 were possible precisely
>    because failure was free. It cannot be re-derived from today's file.
> 3. **The named precondition — a fleet concurrency ceiling — WAS built, and is live.**
>    `capacity_gate()` (`scripts/handoff-fire.sh:4115`) is **on by default**
>    (`CC_FIRE_CAPACITY_GATE:-on`), with `CC_FIRE_MAX_LOAD_PER_CORE` (default **2.0/core**) and the
>    M10 memory-headroom term, **both** of which a **net-new** spawn must clear (`:6079`; only a
>    recycle is exempt, because it is net-zero panes). `desk-invariant` fires through
>    `handoff-fire.sh` with no `--recycle` (`:214-253`), so it is gated **by construction** — it
>    cannot fire into a loaded box even when its own 2/6 h budget is intact. The **`UNMEASURABLE`**
>    verdict in `CONCURRENCY_PROGRAM.md` (§S5-CEILING, §S5.2, §S5.4) is about a **different
>    ceiling**: the off-box **cloud create quota** that `scripts/cloud-ceiling-probe.sh` cannot
>    validate because its classifier has no calibration control. An unmeasurable *cloud* quota says
>    nothing about an *on-box* load/memory gate that is measured, live, and demonstrably refusing.
> 4. **Since `6c72434c3` (2026-08-07, D6) enabling it on an unwired box is a provable no-op.** The
>    `not-opted-in` branch abstains with **zero** side effects — no page, no budget spend, no dedup
>    marker — when the role file is ABSENT/EMPTY and `CC_DESK_OPTIN` is unset. A wired-**then**-broken
>    desk still takes the page+fire path, which is the state the organ exists for.
>
> **One argument that did NOT survive either — recorded so it is not reused.** The filing's "3 of the
> 4 generators run today with no ceiling" is false in all three parts: this doc names exactly **two**
> generators and **both are `staged`**; `boot-resume` carries `CC_BOOT_RESUME_MAX_PER_WORKTREE=1` /
> `CC_BOOT_RESUME_MAX_TOTAL=4` (`scripts/boot-resume.sh:83-84`); `com.claude.dispatcher` carries
> `CC_DISPATCH_CEILING` (default **12**, `bin/cc-dispatch:368`) plus `free_slots` admission; and
> `com.claude.discovery` creates **no sessions at all** — `bin/cc-discover` has **zero**
> `handoff-fire` call sites and writes `cc-backlog` rows. The refutation above rests on none of it.
>
> **DECISION: `desk-invariant` is ENABLED by the C10 route below — not deleted.** A disabled
> invariant asserts nothing, and this is the only asset in the repo that can CREATE or RE-ENGAGE a
> desk from **outside** the API failure domain it watches (SO-6). Deleting it would remove the answer
> to a stunned or dead desk and leave every terminal branch draining to an absent human.
>
> **The C10 route is ONE line, and it is the operator's.** `install.sh` bootstraps exactly the labels
> the manifest declares `expect = run` (`install.sh:755-760` — the R-1 gate) and `deploy-live`
> invokes it every 600 s; `18-fleet-activate.sh` `continue`s past every non-`run` label (`:134`). So
> the manifest row **is** the activation switch, and an agent flipping it would be mutating launchd
> by proxy. This session leaves the row at `staged` and files the step:
>
> ```
> launchd/fleet.manifest:  com.claude.desk-invariant | staged | 300 | …   →   | run | 300 | …
> ```
>
> After the flip, activation converges unattended within one `deploy-live` tick, or immediately via
> `bash docs/activation/pending-activation/18-fleet-activate.sh`. The row's `activate` field is
> retargeted to that script in the same commit as this correction: it previously named
> `06-desk-bootstrap-activate.sh`, which wires the desk *bootstrap* (`desk-register`, `/desk`, the
> brief hook) and contains **no reference to the launchd label at all** — so the `recover_cmd`
> `cc-fleet` would print the moment the row went `run` pointed at a script that cannot turn the job
> on. Retargeting `activate` changes no `expect` and activates nothing.
>
> **Expect the flip to be INERT at first, and read that as correct rather than broken.** As measured
> 2026-08-09 (`backlog-consolidation-2026-08-09/OUT-dispatch.md:43`) `~/.claude/cc-roles/` held no
> `desk` file at all — one 0-byte `orchestrator`. Against an ABSENT role file the D6 `not-opted-in`
> branch abstains with zero side effects, so a freshly-`run` `desk-invariant` will log abstentions
> and do nothing until a desk is registered (`desk-register`, already wired — `06`'s `.done` exists
> in the live queue). That ordering is the fail-safe one and is why this decision does not need to
> wait on the desk: the job cannot act before there is something for it to watch. Verify with
> `ls -l ~/.claude/cc-roles/desk` and `jq -r 'select(.src=="desk-invariant")|.disposition'
> ~/.claude/autonomy/idl.jsonl | tail` (the record's key is `src`, not `actor` —
> `scripts/desk-invariant.sh:179`).
>
> **`boot-resume` is NOT covered by this correction** and stays `staged`. It genuinely fires per
> ghost, its bound is a different one (above), and nobody has re-derived its incident attribution.
> Do not read this correction as covering both generators — that is the same over-generalisation,
> pointed the other way.

| Delta | Value | Source |
|---|---|---|
| Enable event for dispatcher+discovery | **2026-07-29 12:22:34** by `/tmp/claude-dispatcher-enable.sh --enable` (the 11:06 plist mtime is only the `cp`) | override-db mtime; the script, still on disk |
| `com.claude.dispatcher` plist drift | repo declares `StartInterval 300` (landed `21d8e869`), live runs **900** — row 5's ≤5-min bound **is not live** | `plutil -p` both copies |
| `lead-supervisor` SSOT | **not missing — abandoned.** Exists at `launchd/com.claude.lead-supervisor.plist` in `e360c309`, stranded on unlanded branch `tm/growth` | `git log --all` |
| Fleet-wide shape | 7 plists landed in one day 2026-07-18 (the autonomy-100 burst); 6 of 7 now inert | `git log --diff-filter=A -- launchd/` |
| Survivors of the reboot | exactly the labels with **no override-db entry** (`com.chrisren.*`) — absence from the db means enabled | override db read |
| `deploy-live` exit 1 **today** | its **designed** no-green refusal, not a crash | `deploy-live.sh --dry-run` (lead-verified) |

**Correction to §1.1/§2, made by the lead against its own earlier claim.** "deploy-live has never
once succeeded" was too strong. The 59 `cannot execute` failures were real but bounded: 2026-07-28
22:34 (activation) → 2026-07-29 10:32 (when its symlink finally appeared) — an activation that ran
*before* the deploy that creates the symlink, i.e. the bootstrap circle. Since 10:32 it has been
**correctly refusing**, because there is still no green stamp. The design consequence is sharper
than the original claim, not weaker — see F20.

### 2.2 What already exists — consumed, not rebuilt

`hooks/activation-watch.sh` axis 3 (`inert_axis`, `:103-126`) already effect-reads `.done` markers
against `launchctl list`, is deployed, is in all 5 config dirs' `settings.json`, and self-clears.
This design **generalises its shape** to the whole roster rather than replacing it — axis 3 walks
`pending-activation/*.sh`, so a label with no activation script (`lead-supervisor`) is invisible to
it. `cc-blockers`' `NOT-ACTIVATED`-vs-`STALE` split, existence gating, and per-sensor fail-open are
reused verbatim; **the gap there is a call site, not a design** — `cc-blockers` has zero automatic
callers and runs only when a human types it. The A11 verify block
(`02-load-dispatcher-activate.sh:67-79`) and the deliberately-outside-the-`&&`-chain
`enable`-before-`bootstrap` idiom (`3b88c5e5`) are both adopted by the platter.

---

## §3 The architecture — declare, reconcile, one board

```
DECLARATION (repo, versioned)        RECONCILER (read-only, every 5 min)       SURFACE (existing)
─────────────────────────────        ───────────────────────────────────       ──────────────────
launchd/fleet.manifest               bin/cc-fleet --json                       cc-blockers board
  one line per label:                for each DECLARED label:                    fleet rows, same
    label                              repo plist?      ─┐                       schema as today's
    expect = run|staged|retired        installed plist? ─┤                       alarm rows
    interval_s                         disabled bit?    ─┼─► total state S0..S6
    evidence path                      launchctl print  ─┤   + one structured    operator-readout
    owner row                          evidence mtime   ─┘   verdict= token      silver platter
    activate script                                                              ▲
        │                            never mutates launchd                       │
        └────────── is itself a declared job (R10) ───────────────────────────────┘
                                                                    ONE C10 command:
                                                          18-fleet-activate.sh (enable→bootstrap)
```

### 3.1 The state function (total, R1)

| State | Meaning | Sensors that decide it | Board? |
|---|---|---|---|
| **S0 UNDECLARED** | label present on the box, absent from the manifest | manifest ∌ label | no row — but counted, and a *summary* row fires if >0 (an undeclared live job is a manifest gap, not a daemon fault) |
| **S1 NOT-INSTALLED** | declared `run`, no plist in `~/Library/LaunchAgents` | filesystem | **row** |
| **S2 DISABLED** | installed, `=> disabled` in the override db | `print-disabled` | **row** — the C10 fix, one command |
| **S3 NEVER-RAN** | loaded, `runs = 0`, no evidence artifact ever | `launchctl print` + evidence path | **row** |
| **S4 FAILING** | loaded, `last exit code ≠ 0` | `launchctl print` | **row** |
| **S5 STALLED** | loaded, exit 0, evidence older than `interval_s × CC_FLEET_STALE_FACTOR` | evidence mtime + declared interval | **row** |
| **S6 HEALTHY** | loaded, enabled, exit 0, evidence fresh | all | no row |
| *(S7 RETIRED)* | declared `retired` — deliberately not running | manifest | no row, ever (R8: retired ≠ broken) |
| *(S8 UNDECIDED)* | declared `staged` — built, activation pending, not yet expected live | manifest | **always exactly one row**, `state:"UNDECIDED"` — a pending *decision*, never a daemon-fault row |

`expect = staged` is the honest answer to "is this job *supposed* to run?" where the evidence does
not settle it. It surfaces as a decision for the operator instead of either a guessed alarm (noise)
or a guessed silence (the current failure). Ambiguity is declared, not resolved by the agent.

**`staged` must never become a hiding place.** It emits a row unconditionally — absence-is-loud
applied to the *decision* rather than to the daemon — so classifying a job `staged` cannot be used
to silence it, only to say honestly that nobody has decided yet. The operator converts each to `run`
or `retired` with a one-line manifest edit. Initial classification (lead, evidence-based):
**7 `run`** — postland-verify, deploy-live, dispatcher, discovery, log-rotation, session-search-sweep,
session-search-backfill; **7 `staged`** — caffeinate-floor, power-policy-verify, team-orphan-reaper,
desk-invariant, boot-resume, lead-supervisor, nightly-regression; **0 `retired`** (retiring anything
is an operator call, not an agent's).

### 3.1.1 Sensor facts the state function is built on (measured 2026-07-29)

`launchctl print gui/501/<label>` returns **rc=113 with an identical `Could not find service`
message for a DISABLED label and for a label that does not exist at all** (measured:
`com.claude.log-rotation` vs `com.claude.does-not-exist`; a loaded label returns rc=0). So `print`
is a three-way ambiguity, not a signal, and **S1 and S2 must never be inferred from it** — S1 comes
from the filesystem (`~/Library/LaunchAgents/<label>.plist`), S2 from the override db. `print` is
used only for S3/S4, where rc=0 guarantees the parse is meaningful; a non-zero `print` on a label
that *is* installed and *is not* disabled is a genuine UNKNOWN (R5/R8: no row, say so).

`print-disabled` emits `\t\t"<label>" => disabled|enabled`. The label must be matched **whole and
quoted**, or `com.claude.dispatcher-foo` satisfies `com.claude.dispatcher`. **Absence from the
override db means ENABLED** — it records overrides, not memberships (the rule `cc-blockers:222-224`
already states; reused verbatim rather than re-derived).

### 3.2 Why this dissolves the failure class rather than enlarging the old one

The skill's Phase-2 test: *if the new design is the old one with bigger constants, return to Phase 1.*

The old design's unit of coverage is **an alarm someone wrote**. Scaling it means writing 12 more
copies of `dispatch_alarm_rows()`, and the 15th daemon is dark again the day it ships. The new
design's unit of coverage is **a line in a manifest**, and the reconciler is written once. That is a
change of kind: coverage becomes total by construction and stays total as the fleet grows. The
second inversion is the sensor set — from one ambiguous boolean (`launchctl list | grep`) to the
four independent reads that make the six states distinguishable, which is what turns four
silently-healthy-looking failures into four named rows.

---

## §4 Component specifications

### 4.1 `launchd/fleet.manifest` — the declaration (contract, frozen)

Plain text, one record per line, `#` comments, `|`-separated. Chosen over JSON/YAML deliberately:
`bin/` here is POSIX-shell and must parse this without `jq` available (R5 — a parser dependency is
a sensor that can fail).

```
# label | expect | interval_s | evidence | owner_row | activate
com.claude.postland-verify | run | 300 | ~/.claude/autonomy/postland/runner.log | 1 | 14-land-pipeline-v2-activate.sh
com.claude.deploy-live     | run | 600 | ~/.claude/autonomy/postland/deploy.log | 1 | 14-land-pipeline-v2-activate.sh
```

- `expect` ∈ `run | staged | retired` (§3.1).
- `interval_s` — the declared cadence; `0` for calendar-scheduled jobs, whose staleness bound is
  `86400 × CC_FLEET_STALE_FACTOR` instead.
- `evidence` — the **durable product** that proves execution (R4), `~`-expanded at read time. `-`
  means no artifact exists, in which case only launchd's own counters decide S3/S4 and S5 is
  never claimed (R8: no sensor ⇒ no verdict, not a red).
- `owner_row` — the rebuild-map row that answers when it breaks. Routing metadata; it never
  changes a verdict.
- A **lint** (§4.4) enforces manifest ⟷ `launchd/*.plist` ⟷ `~/Library/LaunchAgents` three-way
  coverage, so a new plist cannot land undeclared.

### 4.2 `bin/cc-fleet` — the reconciler

**4.2.1 Verbs.** `--json` (one verdict object per line) · `--table` (operator-readable) ·
`--check` (exit 0 iff every declared-`run` label is S6; exit 1 otherwise — the gate entry point) ·
`--selftest`.

**4.2.2 Discipline.** Read-only launchd subcommands only (`list`, `print`, `print-disabled`),
reached exclusively through `CC_FLEET_LAUNCHCTL_BIN` so tests stub it and never touch real launchd —
the idiom `cc-blockers` already established at `:70`. Every `plutil -extract` carries `-o -` (R6).
No `case` inside a `$( )`. Sensor failure ⇒ that label reports `state=UNKNOWN reason=<sensor>` and
produces **no** alarm row (R5/R8) — an unrunnable check says so and never passes vacuously.

**4.2.3 Row schema (contract, frozen — `df-board` codes against this).** One JSON object per line,
matching the board's existing alarm-row shape so the renderer needs no change:

```json
{"kind":"fleet-inert","state":"DISABLED","detail":"disabled at the domain level (C10)",
 "subject":"com.claude.log-rotation","recover_cmd":"CONFIRM=1 bash <platter>","ts":1785...}
```

`state` ∈ `NOT-INSTALLED | DISABLED | NEVER-RAN | FAILING | STALLED | UNDECLARED-SUMMARY`.
`detail` is ASCII-only and ≤44 bytes (the renderer pads by BYTES). `recover_cmd` is the exact
paste-ready command, with `$(id -u)` **emitted** rather than evaluated so it stays uid-portable in
the operator's shell — again the existing idiom (`cc-blockers:145-147`).

**4.2.4 Precedence.** States are checked in order S1 → S2 → S3 → S4 → S5, first match wins, and each
is **terminal**: a job that is not installed cannot be disabled; a job that is disabled cannot be
late. This is `dispatch_alarm_rows()`'s "terminal NOT-ACTIVATED" rule (`:231`) generalised, and it is
what stops one dark job from emitting five rows.

**4.2.5 Kill switch.** `CC_FLEET_RECONCILE=off` ⇒ exit 0, no rows, one line to stderr saying it is
off. Tunables: `CC_FLEET_STALE_FACTOR` (default 3), `CC_FLEET_MANIFEST`, `CC_FLEET_LAUNCHCTL_BIN`.

### 4.3 `bin/cc-blockers` — board integration (`df-board`)

One new `fleet_alarm_rows()` that shells `cc-fleet --json` and passes its lines through, joining the
existing `{ alarm_rows; dispatch_alarm_rows; }` composition at `:241`. **Purely additive**:
`alarm_rows()` and `dispatch_alarm_rows()` are untouched — rows 1 and 5 own those semantics and this
rebuild consumes them (R11). Overlap is intentional and harmless: their rows carry row-specific
meaning (`trunk-red` is a trunk problem, not a daemon problem) that a generic reconciler cannot
express; the fleet row is the **floor**, guaranteeing every label at least one honest verdict.
Absent or non-executable `cc-fleet` ⇒ no rows, no error (R5, fail-open).

### 4.4 Plist SSOT parity (`df-board`)

A `--plist-parity` leg mirroring `activation-watch.sh`'s axis 2, over `launchd/*.plist` vs
`~/Library/LaunchAgents/com.claude.*.plist`: **LIVE-ONLY** (one `rm` from unrecoverable — currently
`lead-supervisor`) · **REPO-ONLY** (committed, never installed) · **CONTENT-DRIFT** (the copy launchd
actually loads differs from the committed SSOT). Enforced at the **chokepoint**, not only by its own
suite (memory `enforcement-must-live-at-the-chokepoint`): the manifest lint runs in `run_gate` so an
undeclared or unmirrored plist cannot land.

### 4.5 The C10 platter — `18-fleet-activate.sh` (`df-platter`)

**One** operator command that brings the fleet to its declared state. Reads the manifest, and for
every `expect = run` label not currently S6:

```
launchctl enable    gui/$(id -u)/<label>      # FIRST — bootstrap alone returns EIO on a disabled label
launchctl bootstrap gui/$(id -u) <plist>      # idempotent: already-loaded is not an error
launchctl print     gui/$(id -u)/<label>      # self-verify — print, never `list | grep` (LAND_PIPELINE_V2 amend log)
```

then re-runs `cc-fleet --check` and prints the resulting state table. Idempotent, `CONFIRM=1`-gated,
and — because the bare-run-then-`touch` idiom is exactly what produced the claimed-done-but-inert
class — a bare run prints, in words, that nothing was changed and the `.done` marker must not be
touched. Staged to **both** `docs/activation/pending-activation/` (repo SSOT) and
`~/.claude/autonomy/pending-activation/` (the copy the operator runs), per the parity rule. Env
seams are pre-resolved at stage time: the platter hands the operator the command that **works**, not
the one that should (LAND_PIPELINE_V2's activation needed `CC_REPO` pointed at the landed worktree).

### 4.6 The reconciler is itself a declared job (R10)

`com.claude.fleet-reconcile` runs `cc-fleet --check` on an interval and is declared in the manifest
it reads. A reconciler that stops running is therefore reported by the *next* run of the board's own
freshness read of its evidence artifact — the mechanism cannot go inert without saying so. Until the
operator activates it, `cc-blockers` still calls `cc-fleet` synchronously on every board render, so
**the alarm works with zero activation** — the daemon only reduces latency. That is R11 applied to
this design's own dependency: it degrades cleanly when dark.

---

## §5 Failure-mode coverage (every observed mode → structural answer)

| # | Observed mode (measured) | v2 structural answer |
|---|---|---|
| F1 | 10 of 14 jobs disabled 43h, zero alarms | manifest declares intent ⇒ every declared-`run` label not S6 is a board row (R2) |
| F2 | 8 dark jobs named by no activation script ⇒ invisible to all 3 axes | reconciler iterates the **fleet**, not the queue (§1.2) |
| F3 | `deploy-live` enabled+loaded+never-succeeded, no alarm | S4 FAILING reads `last exit code`, which `launchctl list` cannot express |
| F4 | `deploy-live` 22 missed 600s intervals, log frozen, no alarm | S5 STALLED compares the **declared** interval against a durable evidence artifact (R4) |
| F5 | launchd fast-fail throttle makes a broken job quieter with age | verdict is computed from declaration vs world, never from the volume of complaints |
| F6 | `deploy-lag` alarm gated on a GREEN stamp that has never existed (0/33) | existence evidence comes from the declaration, not the subject's success history (R2/§1.5) |
| F7 | `.done` marker set after a bare `CONFIRM`-less run ⇒ 10-day silent dispatcher outage | `.done` is no longer the completion oracle; the reconciler's S6 is. Platter says so in words on a bare run |
| F8 | `bootstrap` without `enable` fails EIO silently on a disabled label | platter always `enable`s first, then self-verifies with `launchctl print` |
| F9 | `launchctl list \| grep` conflates 4 broken states with healthy | four independent sensors ⇒ total six-state function (R1) |
| F10 | `lead-supervisor` live-only, dark 354h, no repo SSOT — one `rm` from unrecoverable | plist SSOT parity leg + manifest lint at the `run_gate` chokepoint (R6) |
| F11 | A new daemon ships with no alarm because nobody wrote one | manifest lint refuses an undeclared plist at land time (§4.4) |
| F12 | Coordinator's own 3-hour-old count already stale (12/2 → 10/4) | reconciliation is scheduled, not a one-shot audit (§1.6) |
| F13 | An alarm invented rows in fixtured `$HOME` voids | undeclared ⇒ no row; the manifest is the existence evidence (R3) |
| F14 | A parity check resolved `REPO=~/.claude` and passed vacuously | unresolvable sensor ⇒ reported as UNKNOWN, never a pass (R5) |
| F15 | `plutil -extract` without `-o -` destroyed 5 LaunchAgents | `-o -` mandatory, enforced by the reviewer checklist and the suite (R6) |
| F16 | A bash-3.2 `case`-in-`$( )` death produced a **false** alarm row | banned in this component; validation happens outside command substitution |
| F17 | Retiring a job would produce a permanent false alarm | `expect = retired` is a first-class declaration (R8) — retired ≠ broken |
| F18 | This mechanism itself goes inert and nobody notices | it is a declared job reconciled by itself, and the board calls it synchronously so it works un-activated (R10/§4.6) |
| F19 | `install.sh:306-315` boots out every plist then bootstraps with **no `launchctl enable`**, swallowing every error (`2>/dev/null \|\| true`) — and `deploy-live.sh:283` calls it on **every** autonomous advance (600s). An enabled job is bounced mid-work (postland-verify mid-corpus); a disabled job can never be recovered by it. `tests/install-staged-plist.bats:40` pins the broken command | **DETECTED here, NOT fixed here** — a bounced or un-recovered job reads S1/S2 and rows within one cycle. The fix touches row 1's files, so it is a **seam question routed to the coordinator**, not decided unilaterally (§9) |
| F20 | A job whose **designed verdict is a non-zero exit** is read as broken. `deploy-live` exits **1** to mean "no green stamp, nothing safe to deploy" — an S4 rule keyed on `exit != 0` alarms on it forever | manifest field `ok_exits` (default `0`; deploy-live `0,1`). S4 fires only on an exit **outside** the declared healthy set. Caught mid-build by verifying the lead's own claim with `--dry-run` |
| F21 | 🚨 The classifier boundary is **asymmetric** — agents are denied `launchctl enable` but NOT `bootout`/`disable`, and an agent used exactly that to dark 13 labels on 2026-07-26 | cannot be closed from inside this row (it is a permission-layer fact, row 6). It is a second, independent argument for **continuous** reconciliation over a one-shot audit: the fleet can be darkened at any moment by something that is allowed to do it. Surfaced to the operator; named here so no future design assumes the fleet only changes when a human changes it |

---

## §6 Bootstrap, rollout, kill switches

1. Land the manifest + reconciler + board leg + platter through the v2 fast lane, **continuously**,
   one atomic commit per component (never batched — the fast lane lands in seconds; never add corpus
   work to the land path).
2. **Zero-activation value first:** `cc-blockers` calls `cc-fleet` synchronously, so the moment the
   board leg lands, all 11 currently-broken labels become visible with no operator step at all. The
   launchd job is a latency optimisation, not the mechanism (§4.6).
3. **One** C10 operator step: `CONFIRM=1 bash ~/.claude/autonomy/pending-activation/18-fleet-activate.sh`.
   Until it is run, the board says so — degraded is loud, never silent.
4. The initial manifest classification is evidence-based, and every genuinely ambiguous job is
   declared `staged` (a decision surfaced) rather than `run` (an alarm guessed) — see §3.1.
5. Kill switches, all env, never revert-as-plan: `CC_FLEET_RECONCILE=off` (whole mechanism) ·
   `CC_FLEET_STALE_FACTOR` (S5 sensitivity) · unloading the reconcile plist (board keeps working).

---

## §7 Acceptance criteria — disk-truth reads, not narration

Each criterion names the file or command that proves it.

- **A1** `bin/cc-fleet --json` emits exactly one verdict line per manifest-declared label; the count
  equals `grep -vc '^#' launchd/fleet.manifest`. *Read:* both commands, compare integers.
- **A2** Every one of the 10 currently-disabled labels appears with `"state":"DISABLED"`.
  *Read:* `cc-fleet --json | jq -r 'select(.state=="DISABLED").subject' | sort` vs
  `launchctl print-disabled gui/$(id -u) | grep '=> disabled'`.
- **A3** `com.claude.deploy-live` is reported `FAILING` or `STALLED` — **not** healthy — while its
  `last exit code` is 1. *Read:* `cc-fleet --json | jq 'select(.subject|endswith("deploy-live"))'`
  beside `launchctl print gui/$(id -u)/com.claude.deploy-live | grep 'last exit'`.
- **A4** `~/.claude/bin/cc-blockers` renders ≥1 `fleet-inert` row while any declared-`run` label is
  not S6 — i.e. the board is **no longer empty** in the state measured in §2. *Read:* run it.
- **A5** `com.claude.lead-supervisor` is reported by the plist-parity leg as LIVE-ONLY.
  *Read:* `cc-fleet --plist-parity`; confirm `ls launchd/com.claude.lead-supervisor.plist` is absent.
- **A6** Positive control — with a manifest whose every declared label is stubbed healthy, `cc-fleet
  --json` emits **zero** rows and `--check` exits 0. *Read:* the suite's positive-control case
  (guards against a detector that fires on everything).
- **A7** `CC_FLEET_RECONCILE=off cc-fleet --json` emits zero rows and exits 0. *Read:* the command.
- **A8** The platter exists **byte-identical** in both queues. *Read:*
  `cmp docs/activation/pending-activation/18-fleet-activate.sh ~/.claude/autonomy/pending-activation/18-fleet-activate.sh`
  and `bash hooks/activation-watch.sh --parity` (rc 0).
- **A9** A bare (no `CONFIRM`) platter run mutates nothing and says so. *Read:* run it, then
  `launchctl print-disabled gui/$(id -u)` is unchanged (diff before/after).
- **A10** Manifest lint fails when a `launchd/*.plist` is undeclared. *Read:* RED-proof — add a
  fixture plist, lint exits nonzero; remove it, exits 0.
- **A11** *(accrues, post-C10)* after the operator runs the platter, `cc-fleet --check` exits 0 and
  every declared-`run` label shows `runs ≥ 1` within its own interval. *Read:*
  `cc-fleet --table`; `launchctl print gui/$(id -u)/<label> | grep runs`.
- **A12** *(the DoD metric, accrues)* no declared-`run` job is both non-executing and un-rowed for
  >24h. *Read:* the board's fleet rows vs `cc-fleet --table` on any two days.

---

## §8 Rejected alternatives (and why)

- **Write 12 more bespoke `cc-blockers` alarms, one per label.** The honest in-frame fix, and it is
  the frame that fails: coverage stays a property of who remembered, the 15th daemon is dark on
  arrival, and each copy re-implements the sensor logic with its own bugs. §1.2's "Mirrors
  `alarm_rows()` above deliberately" is the frame admitting it. Rejected as parameter motion.
- **Just enable the 10 disabled jobs and close the row.** Fixes today's symptom, leaves S3/S4/S5
  silent — `deploy-live` would stay broken and the live layer behind trunk. This is precisely the
  design the unexamined map cell would have produced (§1.6).
- **`KeepAlive` on every job so launchd restarts them.** Wrong instrument: `KeepAlive` cannot clear a
  disabled bit (S2), and on a fast-failing job it converts a silent failure into a hot restart loop —
  a *more expensive* degradation path, which R7 of the landing rebuild forbids as an amplifier.
- **A watchdog daemon that repairs the fleet automatically.** Attractive, and blocked by C10 on
  purpose: the mutation verbs are classifier-denied for agents, and a self-healing daemon that can
  `launchctl enable` is exactly the authority the boundary withholds. Also fails R10 — it would need
  a watchdog of its own. Reconcile-and-report is the correct division: the agent detects
  continuously, the operator actuates once.
- **Derive intent from `launchd/*.plist` alone, with no manifest.** Cheaper, and it cannot express
  `retired` or `staged`, so every deliberately-off job becomes a permanent false alarm and the board
  trains alarm-fatigue (F17). The three-valued declaration is the whole point.
- **JSON/YAML for the manifest.** Needs `jq`/a parser the reconciler must not depend on (R5 — the
  parser is a sensor that can fail, and this component must work when the box is degraded).
- **Fold this into `activation-watch.sh` as a 4th axis.** Wrong lifecycle: that hook is
  SessionStart-only and queue-scoped by design. The fleet needs a verdict available to the board, to
  a gate, and to a daemon — three consumers, so it is a `bin/` tool with a parseable contract, and
  `activation-watch` keeps owning the *queue* axes it already does well.

---

## §9 Seams consumed, not redesigned (R11)

Rows 1, 4, 5, 7 and 8 are **carried**: their unattended execution rides on this fleet. This design
consumes their contracts and redesigns none of them.

- **Row 1 (landing/deploy)** — owns `postland-verify` + `deploy-live` semantics and their two
  bespoke alarms. This row declares both in the manifest and reports their *daemon state*; it makes
  no claim about stamp verdicts, trunk redness, or deploy policy. **Finding handed back, not acted
  on:** `deploy-live` has never succeeded (§2) and `deploy-lag` cannot fire at 0 green stamps —
  routed to the coordinator for row 1, not fixed here.
- **Row 4 (registry/reaping)** — `com.chrisren.cc-reaper` is a **different label family**; the
  manifest covers it explicitly, because a `com.claude`-only grep wrongly concludes it is inert (map
  learning 2026-07-29). Row 4's session-beat oracle is landed-but-inert and is consumed fail-soft:
  nothing here reads it.
- **Row 5 (dispatch/discovery)** — `dispatcher` + `discovery` are now enabled and loaded; declared
  `run`. `dispatch_alarm_rows()` is untouched.
- **Row 7 (accounts/quota)** — `com.claude.relogin.plist` sits in `launchd/staged/`; declared
  `staged`, never `run`, and no routing logic is touched.
- **Row 8 (context economy)** — consumes recycle/handoff daemons; declared only, no behaviour change.
- **Row 10 (operator surface)** — owns the board renderer. This row adds rows in the **existing
  schema**; the renderer is not modified.

No seam dispute identified. Anything that becomes one goes to the coordinator, not decided here.

---

## §10 Close-out — landed, taken, rejected, and NOT done (2026-07-29)

**Landed, content-verified on origin/main** (never by count — `git ls-tree` + empty `git diff` per
path): `59f7eb38` design · `dc052a82` map row 12 + learnings · `bda59c54` the build (reconciler,
manifest, board rows, plist parity, platter, 3 suites) · `68f33d39` the scope + state corrections.
97 tests green under `/bin/bash` across cc-fleet (21) · cc-blockers-fleet (27) · fleet-activate (11)
· cc-blockers (38, trunk's own suite untouched — the additive proof).

**The metric, measured before and after.** Before: `cc-blockers` printed *"no safeguard-blocked
sessions surfaced"* while 10 of 14 declared jobs were dark. After: the board renders every declared
label not in its declared state, each with a paste-ready recover command. Coverage is now a property
of a manifest line, not of who remembered to write an alarm.

### Taken from the stranded work (coordinator's "take, do not rebuild")

A duplicate row-12 lead's archaeologist found `518d61dc` — `scripts/launchd-parity-lint.sh` (167 ln)
+ `tests/launchd-parity-lint.bats` (208 ln) — stranded 4 days on `tm/launchd` / `fix/infra-perfection`,
never landed, with `docs/research/STRANDED_EXPOSURE_2026-07-26.md:156` explicitly prescribing the
land. **This was a Phase-1 miss on my part**: the `search-branch-graveyard-before-building` rule
exists precisely for this and I did not run it. What was taken vs rejected, on the merits:

| Item | Verdict |
|---|---|
| `518d61dc` label-keyed indexing, reso-scope exclusion, VACUOUS-not-green, no `plutil -extract` | **CONVERGED INDEPENDENTLY** — `bin/cc-fleet` already implements all four. Its two named gaps (reads FILES only, never the disabled DB; no self-test, relying on the DISABLED `nightly-regression` — i.e. double-inert) are exactly what this rebuild adds. Nothing to cherry-pick into the reconciler. |
| `e360c309` / `a0e11648` / `687c2fd6` — `launchd/` SSOT capture for the 5 live-only plists | **TAKE, NOT DONE HERE.** This is the written fix for the LIVE-ONLY findings §10's parity leg now emits. Cherry-pick `-x` rather than re-author. Named as remainder R-2 below. |
| `2976b342` INFRA_PERFECTION_2026-07-25.md (328 ln) | Context, not code. Read before R-2. |

### NOT DONE — named, not hidden

- **R-1 `install.sh` launchd safety (coordinator ruling: ROW 12's, filed `c13dad7d5dbe`).**
  `install.sh:306-317` boots out every `launchd/*.plist` then bootstraps with **no `launchctl
  enable`**, swallowing every error (`2>/dev/null || true`); `deploy-live.sh:283-284` calls it on
  every 600s advance. The coordinator's sharpening is the part that makes it urgent and is recorded
  here verbatim because it is not obvious: **it only bites once things start working.** Deploy is
  fail-closed today, so `install.sh` is never invoked autonomously — but the moment a GREEN stamp
  exists, every advance bounces all plists including `postland-verify`, whose measured runs are
  3399-10112s against a 600s interval, so it can never finish, so no further green stamps, so the
  gate re-closes. **A self-extinguishing autonomy loop.** Fix = `enable` before `bootstrap`, do not
  swallow the verdict, and skip a label whose run-lock is held. Do NOT touch deploy's advance logic
  (row 1's). `tests/install-staged-plist.bats:40` pins the broken command and must change with it.
- **R-2** cherry-pick `e360c309`/`a0e11648`/`687c2fd6` to give the 5 live-only plists a repo SSOT.
- **R-3 the `runs`-cursor upgrade for S5.** Four declared-`run` jobs carry `evidence = -` because
  they have no per-run durable product, so S5 is unprovable for them (R8 applied honestly). A
  persisted per-label `runs` cursor would make it provable — launchd increments `runs` on every
  invocation regardless of output. Must handle a cursor DECREASE (re-bootstrap resets `runs` to 0)
  as "re-bootstrapped", never as "stalled".
- **R-4 the `NN-` activation prefix is not a total order.** `18-fleet-activate.sh` only exists
  because `17-` collided with another session's landed script. Renaming dodged the instance; the
  class remains. Go label-keyed or timestamp-keyed.
- **R-5 a fourth activation-watch axis: script mtime vs `.done` mtime.** `09-operator-readout-activate.sh`
  is 9.8h NEWER than its own `.done` — edited after being marked run, and axis 1 skips it forever. A
  `.done` is a claim about a file that no longer exists.
- **R-6 calibrate the 24h threshold.** Historical time-to-done is n=10, **median 24.8h**, mean 37.6h,
  oldest un-run 257.8h, 10 of 19 `.done` = 52.6%. A 24h alarm sits exactly at the median, so it
  fires on half of all healthy activations. Either declare that deliberate or widen it — but keep
  the measurement either way.
- **R-7** axis 1 emits `additionalContext` (model-only), never `systemMessage` (the human lever).

### Remainder re-verification (2026-07-31) — every row re-derived from disk, none inherited

The list above is preserved verbatim as written on 2026-07-29. Two days of sibling landings moved
several rows underneath it, so each was re-measured rather than re-read. **Where a row's *symptom*
and its *prescribed remedy* rotted in opposite directions, both halves are recorded** — the remedy
is the half that silently becomes wrong (memory `work-item-remedy-can-become-forbidden`).

| Row | Verdict 2026-07-31 | Evidence |
|---|---|---|
| **R-1** | **CLOSED** — `38da09ee`. Its *remedy as written was dangerous*; see below. | `install.sh` LaunchAgents block; `tests/install-fleet-activation.bats` (8 tests, 2 controls) |
| **R-2** | **CLOSED** — 0 live-only plists remain; landed by `45034362`/`9481b3c6`/`b369676f`/`a1d4da2f` rather than by the prescribed cherry-picks | every `~/Library/LaunchAgents/com.claude.*.plist` has a `launchd/` or `launchd/staged/` SSOT |
| **R-3** | **OPEN**, unchanged | S5 is gated solely on evidence mtime (`bin/cc-fleet:367`); `EV_PATH=""` returns at `:235`. No cursor is persisted anywhere — `P_RUNS` (`:225`) is never diffed or written. The 4 labels are `postland-verify`, `deploy-live`, `dispatcher`, `discovery` (`launchd/fleet.manifest:98-101`). `3448401e` *widened* the no-sensor population |
| **R-4** | **OPEN**, and now worse than "one dodged instance" | 5 colliding prefixes live in `docs/activation/pending-activation/`: `05`, `09`, `10` (×3), `17`, `20` |
| **R-5** | **OPEN as a class; its NAMED EXAMPLE is REFUTED** | Still only 3 axes — `age_axis:89`, `inert_axis:127`, `parity_axis:199`; axis 1 trusts marker existence at `:102` and never stats it. But `09-operator-readout-activate.sh`'s `.done` is now **96.9h *newer*** than the script, not 9.8h older — it was re-touched Jul 30. The class holds with two *different* members: `02-load-dispatcher` and `03-load-discovery`, each +21.1h |
| **R-6** | **OPEN**, partially mitigated | `MAX_AGE_H="${CC_ACTIVATION_MAX_AGE_H:-24}"` (`hooks/activation-watch.sh:43`) unchanged. The M3 change at `:90-97` made 24h a *partition* (a `ROTTING` sub-heading, `:119`) rather than a filter, which blunts the alarm-fatigue harm — but the calibration measurement R-6 said to keep either way is recorded nowhere in the hook |
| **R-7** | **OPEN, and wider than filed** | Single emission path `emit():81-87` → `additionalContext` only; `watch():254-272` concatenates **all three** axes through it. Zero `systemMessage` in the file, while five sibling hooks in this repo do use that lever |

**R-1's remedy had become the more dangerous half of the row.** The filed fix — "`enable` before
`bootstrap`" — is correct about the EIO symptom and, applied to that glob, would have **enabled all
7 `staged` labels including `desk-invariant` and `boot-resume`**, the two session generators §2.1
already names as the ones whose re-enable *reopens the 2026-07-26 incident*. This was not reasoned
to; it was **measured** — the pristine file was mutated with the prescription verbatim and run
against one DISABLED `staged` plist carrying the real generator's label:

```
pre-fix   bootout gui/501/com.claude.desk-invariant ; bootstrap …   (survives only on EIO)
NAIVE     enable gui/501/com.claude.desk-invariant                  ← clears the ONLY guard
          bootout … ; bootstrap …                                   ← generator starts
fixed     (no verb issued)
```

The disabled bit was the sole thing standing between a routine `install.sh` and that generator, and
R-1's prescription removes it. §2.1 predicted exactly this trap for a *mass re-enable* and answered it
structurally in the **platter**; nobody checked whether `install.sh` was a second, unguarded door to
the same room. It was, and it is the door that runs unattended every 600s.

Two side-findings, both now closed by the same commit: an unchanged, already-loaded job is no longer
touched at all (so a routine install is a launchd no-op), and a job **executing right now** is never
booted out — `postland-verify`'s run-lock was held while the fix was being written, i.e. the
mid-corpus bounce was live, not hypothetical. The gate also fails **closed** on a missing manifest,
never back to blanket bootstrap.

*Not attempted this session, and not blocked — R-3 through R-7 stay open with the evidence above.*

## Learnings (accumulate; never delete)

- 2026-07-29 **An alarm keyed on the subject's own success history cannot fire for a subject that
  never succeeded** — and "never succeeded once" is the population that matters. `deploy-live`'s only
  covering alarm needs a GREEN stamp; there have been 0 in 33. The `absence-alarm-needs-existence-evidence`
  law is right, but the evidence must come from a **declaration**, not from the subject's past. This is
  the row's central design law (§1.5) and it generalises to every "is X still working?" check in the repo.
- 2026-07-29 **A broken daemon gets quieter with age.** launchd throttles a fast-failing job
  (`minimum runtime = 10`), so `deploy-live` went from 59 loud failures to complete silence while
  still enabled, loaded and scheduled. Loudness is not conserved: a detector that keys on complaint
  volume, log growth, or error rate reads recovery where there is decay. Key on *declaration vs
  world*, which does not fade.
- 2026-07-29 **The coordinator's own measurement, verified the same morning, was stale by lunchtime**
  (12/2 → 10/4). Not an error — the subsystem's defining property. Any answer of the form "audit it
  and write down the result" is already wrong for this row; only a scheduled reconciler stays true.
- 2026-07-29 **`launchctl list | grep <label>` is the single most load-bearing wrong idiom in the
  repo.** It maps six real states onto one boolean, and four of the broken ones land on the healthy
  side. Every existing check uses it. `launchctl print` (plus the override db) is the read that
  distinguishes them.
- 2026-07-31 **A design can answer a trap at one door and leave a second door unguarded — and the
  unguarded one is usually the door that runs unattended.** §2.1 identified the mass-re-enable trap
  and answered it structurally in the *platter* (which touches only `expect = run`). But
  `install.sh` bootstraps the same glob, is invoked by `deploy-live.sh` every 600s, and had never
  heard of the manifest. The guarded and unguarded paths were written in the same session by the
  same reasoning. **When a design defends an invariant at one call site, enumerate every writer of
  that state before calling it structural** — "the platter refuses this by construction" was true
  and irrelevant to the actual risk.
- 2026-07-31 **A work item's prescribed remedy rots independently of its symptom, and the remedy is
  the half that rots dangerously.** R-1's symptom (a disabled `run` job is unrecoverable, EIO
  swallowed) stayed true for two days. Its remedy — "`enable` before `bootstrap`" — became the
  instruction that would have re-enabled both runaway session generators, because the manifest that
  made `run` and `staged` distinguishable landed *after* the remedy was written. A remedy written
  against a smaller state space silently mis-generalises when the state space grows. **Re-derive the
  remedy from current disk truth, never execute a filed one on faith** — and *run* the naive version
  rather than arguing about it: mutating the pristine file with the prescription verbatim and
  diffing the launchctl verb log showed it emitting `enable gui/501/com.claude.desk-invariant`, the
  one verb that clears the only guard the generator had. A verb log settles in one line what a
  paragraph of reasoning leaves arguable.
