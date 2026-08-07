---
status: open
---

# Concurrency program — driving the fleet to durability and completion

**Status:** briefed 2026-08-07. Evidence: `docs/research/concurrency-census-2026-08-07.md`
(same branch — read it first; every number below comes from there).

---

## Phase 0 — Agent Team orchestration

**Roster is deliberately SMALL, and the reason is the plan's own subject matter:** every teammate is
a session, every session costs ~511 MB plus its gate runs, and the fleet is already oversubscribed
at 14-on-10. A wave sized by task count rather than by capacity would worsen the exact condition
this program exists to fix. Spawn waves, not a fleet.

| # | member | track | writes | worktree | model / effort |
| --- | --- | --- | --- | --- | --- |
| 1 | `gate-contention` | **S2** | `scripts/ship-land.sh`, `scripts/postland-verify.sh`, reso `package.json` lint script | own worktree | Opus @ max |
| 2 | `backlog-triage` | **S3** mechanical pass | a triage report + `cc-backlog` state changes | none (read-only) | Opus @ high |
| 3 | `dispatch-scope` | **S4** | `launchd/com.claude.dispatcher.plist`, `bin/cc-dispatch` | own worktree | Opus @ max |

**Dependency graph** (strict — later members are unsafe before earlier ones complete):

```text
S0 (operator, 1 line)  ─┐
                        ├─→ everything below can LAND autonomously
S1 (push branches)     ─┘    …but S1 does not wait for S0

S2 gate-contention ──→ S3 backlog-triage ──→ S4 dispatch-scope
   (releases items)      (must precede         (drains what
                          the release)          triage approved)
```

**Spawn wave order:** wave 1 = member 1 alone (S2 is the unlock and touches the gate every other
member depends on). Wave 2 = members 2 and 3 in parallel once S2 is green — they share no file.

🚨 **Member 1 is a SOLE-OWNER track.** It edits the landing gate itself, so no other session may
land while it is mid-change. Serialise it, and re-run its own gate after every rebase.

**Not teammates:** S1 (one `git push` loop — no code), S5 (an entitlement check plus an operator
decision), and the S3 *durable* half (a premise-check clause added to the worker protocol, which
belongs to whoever owns that protocol, not to a parallel worker).

**The operator's goal:** grow from ~14 concurrent Claude Code sessions toward **~100**, with queued
work firing autonomously overnight.

---

## 0 · The bootstrap deadlock — why nothing is finishing

This is not a list of independent tasks. It is one cycle, and naming it fixes the ordering:

```text
many concurrent sessions
  → concurrent full-suite LANDING gates
    → gates SIGTERM-killed by contention (zero assertion failures)
      → the land fails → the item is recorded `blocked` — a DURABLE state needing a manual unblock
        → the dispatcher starves (8 open vs 323 blocked) and cannot drain overnight
          → work is done in interactive sessions instead
            → more concurrent sessions  ⟲
```

**Every exit from this cycle runs through LANDING, and landing is currently free but blocked by
mechanism rather than cost** (LAND_SHIP_V2, 2026-08-02: Amplify `autoBuild:False` on `main`, Path F
filters `refs/heads/release`; `/ship` bills nothing, only `/deploy` spends money).

🔑 **The single most load-bearing defect: a land killed by contention and a land that genuinely
failed are recorded in the SAME state.** 205 of 333 backlog items sit `blocked` on "the worker
cannot land" / "persistent thrash". One documents its gate SIGTERM-killed on all four attempts with
**zero test failures across ~1,700 green executions**. That conflation is what converts a transient
load spike into permanent queue rot, and no amount of unjamming helps while it stands.

---

## 1 · The critical path, in dependency order

Each step unblocks the next. Do not reorder — later steps are unsafe or impossible before earlier ones.

### S0 · Unblock agent-driven landing — OPERATOR, one line

`.claude/commands/ship.md` carries `disable-model-invocation: true` in its frontmatter. That is a
harness-level block: **no agent can fire `/ship` in ANY session**, whatever policy says. It was
correct before 2026-08-02, when `/ship` *was* the deploy and every land billed Amplify + Fly.
LAND_SHIP_V2 removed the cost and rewrote that file's prose to *"free and agent-driven"* — but left
the flag, so the documentation and the mechanism have disagreed since, and the mechanism wins
silently.

```bash
sed -i '' '/^disable-model-invocation: true$/d' .claude/commands/ship.md
```

**`deploy.md` KEEPS the flag and must** — that is where the money and the door-staff-visible change
live. Landing is not deploying; v2's whole point is two decisions, so they get two gates.

⚠️ An agent cannot make this change itself — removing the flag that stops the agent from invoking a
command is self-granting, and the permission classifier correctly refuses it.

**Until S0 lands, every track below terminates in a manual paste.** It is the keystone.

### S1 · Bank the stranded work — pure durability, needs no gate

`scripts/land-status.sh` reports **2,304 commits across 199 branches that exist on NO remote** —
"one disk failure from gone." This needs no lint, no dispatcher, no capacity: the commits are
already made. Pushing a **non-`main`, non-`release`** branch triggers nothing (both deploy triggers
watch other refs), so this is free and safe by construction.

Do this BEFORE S2/S3 — it is the only step whose value is unconditional, and the only loss that is
irreversible.

### S2 · Make the landing gate survive concurrency — the actual unlock

Two changes, in order:

1. **Discriminate killed-from-failed.** A gate run terminated by SIGTERM/timeout with **zero
   assertion failures** did not FAIL — it could not RUN. It must retry or defer, never flip an item
   to `blocked`. Same discrimination the fleet already learned about `nice`/`taskpolicy`
   (deprioritising re-specifies every wall-clock timeout inside a suite, so it does not slow
   gracefully — it fails). **Read the failure TEXT, not the exit code.**
2. **Stop N worktrees paying N cold full-tree lints.** reso's `pnpm lint` is
   `eslint src/ lib/ replicache/ --cache --cache-location .eslintcache` — the cache is
   **worktree-local**, so it never amortises across the fleet. Two concurrent runs at ~2.4 GB each
   were measured in different worktrees. Share the cache, or scope the gate to changed files.
   (Only then consider a faster engine — see the census §4 on why an oxlint port cannot be
   byte-identical.)

Optionally serialise full-suite gates fleet-wide (one at a time) — the backlog item that failed four
times prescribes exactly this in its own words: *"when the machine is quiet, run ship-land.sh."*

### S3 · Triage the backlog BEFORE unjamming it — safety precondition

🚨 **Do not release 205 items into an unattended overnight dispatcher.** A jammed queue is *inert*;
205 stale items dispatched at ceiling 6 while nobody watches is strictly worse. Measured staleness:

| signal | count |
| --- | --- |
| items whose own text says CORRECTION / superseded / RETRACTED / "is FALSE" / stale | **55** (16.5%) |
| distinct SHAs cited in premises — mechanically checkable | **127** |
| items dated 2026-07-26 → 07-31, the window the jam accumulated in | **89** |

55 is only the **self-declared** rate; an item silently superseded does not announce it. A live
example already in the store: `bbad96d163ab` exists solely to record that `23eccae755a9`'s central
claim is **false — a time-confounded comparison**. A worker claiming the latter today would very
plausibly roll back a version on a refuted premise.

**Mechanical first** (scriptable, no reasoning): resolve the 127 SHAs against `origin/main`
(landed / reverted / absent); pair the explicit `CORRECTION to backlog item <id>` references and
flag their targets; age-bucket; dedupe by title.

**Then the durable fix, which is not a sweep:** a **premise-check at CLAIM time** in the worker
protocol. A one-time review goes stale the moment it finishes — the same decay that produced this.
A work item's premise is a CLAIM, not a fact: it is written out of context by construction, facts
decay, and imperative voice reads as settled. Verify (`git log --all -- <path>`,
`git cat-file -e origin/main:<path>`, `npm view <pkg> version`) and **when the premise is refuted,
the disproof IS the deliverable** — write it back into the store, never silently close.

This track is **read-only and perfectly parallel** — 333 independent items, no worktree, no shared
file. It is the one piece of this program that fans out cleanly.

#### S3 — LANDED 2026-08-07 (backlog `77fb892c4db5`)

Shipped: `bin/cc-premise` (the predicate — `check` / `contract` / `sweep`), claim guard **(5)
PREMISE CHECK** in `bin/cc-backlog`, `verdict=premise-refuted` read as a **skip** plus the premise
contract injected into the worker BRIEF in `bin/cc-dispatch`, and `tests/cc-premise.bats` (21 tests,
every refusal paired with a near-miss control). Full report + method:
`docs/research/backlog-premise-triage-2026-08-07.md`.

**Result: 12 of 359 items refuse at claim (4 superseded · 8 self-duplicate); 78 carry an advisory;
nothing is auto-closed.** Four of this section's own assumptions did not survive contact with the
data, and the mechanism is shaped by the refutations rather than by the plan:

1. **Refusing a "refuted" item is usually WRONG.** The flagship example above, `23eccae755a9`, has
   one refuted sub-claim and a live ~20x auth-error regression beside it — refusing that claim
   strands the work the item exists to do. A worker's enforcing store is its **brief**, not an exit
   code, so `corrected` allows the claim and the disproof rides the brief. Refusal is reserved for
   items whose WHOLE reason for existing is gone.
2. **Resolving the 127 SHAs measures a POINTER, not a premise.** This repo lands by rebase: 45 of 61
   non-ancestor shas have an exact patch-id twin already on trunk, and 5 of 10 fully-absent shas
   describe changes demonstrably live under a rewritten sha. `absent` never implies "undone", so
   every sha finding is contract prose, never an exit code.
3. **"Dedupe by title" finds nothing, and a stronger matcher would do harm.** Zero non-done items
   duplicate a done one (median similarity to nearest done item: 0.105). `postland-verify` puts the
   culprit sha in the title *on purpose* — a new RED at a new commit is new work — so sha-normalised
   clustering merges 18 genuinely distinct findings. The working signal is the item's own words.
4. **The 55 self-declared count overstates the signal.** Re-derived as 64 of 348, but of the 90
   marker-carrying items with no target id, exactly **1** refutes another backlog item.

The predicate that does work is a **directed** verb→id / id→predicate relation, not proximity: the
first cut matched "a refuting verb within 120 chars" and scored 370 hits where 24 were real,
convicting an OPEN item of being superseded by an unrelated one. Three exclusions each came from a
measured false positive — `wt-<id>` is a worktree path, `UN-RETRACTS` is not `RETRACTS`, and a
refutation is dated by the **event that wrote it** (6 of 64 correctors were added *before* their
target). `DUPLICATE of <id>` runs the other way and marks the **speaker** stale, never the target.

🚨 **The checker was itself manufacturing decayed claims — caught at the gate, before landing.** The
figures above were first measured with `CC_PREMISE_REPO` exported by hand; **neither `cc-backlog` nor
`cc-dispatch` sets it**, so production ran a different configuration. `_git()` returned the same
value for *"git answered: absent"* and *"git could not be asked"*, and the cited-path arm read both as
absent — convicting every cited path containing a slash. Over the same 359 items: **`suspect` = 156
unset vs 76 with a repo — 80 fabricated findings**, each a false sentence (`CITED PATH(S) not at that
location on origin/main: tests/deploy-parity.bats`) about a file that has never moved, riding a real
worker's brief as evidence. The suite was blind because `setup()` unset the same variable for
tidiness; the §4 direction test even carried the false finding *inside its own fixture* and passed,
because it asserted only "not superseded, not self-duplicate" and never `= clear`. Fixed with a
positive control (`_git_usable()` resolving `origin/main`), a realpath'd default repo — without which
fixing the first half would leave the whole "mechanical first" arm dead outside an operator's shell —
and a fixture repo the suite owns. Both directions are mutation-verified: reverting the control
reddens the fail-open test, deleting the arm reddens the positive-control test, and neither covers
the other. **Generalisable: a sensor that cannot tell *absent* from *unreadable* reports the world as
broken exactly when it is blindest, and a suite that disables it for tidiness ships that blindness
green.** Detail: `docs/research/backlog-premise-triage-2026-08-07.md` §8.

⚠️ **Known limit, carried forward as open work:** recall is ≈98% per refutation *statement* but
**≈73% per endangered item** — the gap is a refuted premise **copied into sibling items** that the
corrector never id-linked (the reso land-cost premise is the stated hold-reason in 6 further items,
none linked). Closing it means diffing a corrector's refuted claim against sibling text.

### S4 · Restore autonomous overnight drain

The dispatcher is healthy and starved, not missing: `com.claude.dispatcher`, `StartInterval` **300 s**,
`CC_DISPATCH_CEILING` **6**, admission `free_slots = max(0, CEILING − live_workers)`.

- After S2+S3 it drains on its own.
- ~~**Widen its scope.** `CC_DISPATCH_PROJECT="claude-infrastructure"` pins it to one project, so
  reso's **56** items and doc_classifier's **23** have no overnight path at all.~~
  **CLOSED 2026-08-07 — and this bullet's premise was ALREADY FALSE when it was written.** The
  widening landed in **`d249f460`** *(feat(dispatch): multi-project coverage — one queue, one
  ceiling, one lock)*, which is an ancestor of `origin/main`. It does not widen the env var: a
  `repo=` row in **`scripts/dispatch-projects.conf`** is unioned with `CC_DISPATCH_PROJECT`, so
  coverage is an agent action needing no plist edit and no `launchctl bootstrap` (C10). The plist's
  pin stays deliberately — a bad conf edit can never un-cover the incumbent.
- **Verified OPERATING in production, not merely landed** — live IDL pass `20260807T102125Z-3091`
  emitted real per-item verdicts for the foreign project: **3× `reso-management-app` `defer`
  (`at-ceiling`) + 1× `skip` (`already-done`)**. `at-ceiling` is the S2 ceiling, i.e. these items
  are *in the queue competing for slots* — the S4 symptom (no path at all) is gone; what remains is
  S2's throughput problem, which is a different track.
- **Residual leak found and closed: the label, not the mechanism.** One item sat under project
  `reso` — an alias hand-passed as an explicit `cc-backlog add --project reso` (source
  `wave7-close-2026-08-07`); `~/Development/reso` does not exist. It was journalled
  `{verdict:"skip", reason:"project-not-dispatched"}` on every pass and could never drain. Migrated
  `333aed941b6b` → **`0c9d92ba9a0a`** under `reso-management-app` (a mislabel is not a retraction —
  closing it would have destroyed a live OrderBar clipping defect), and `reso` declared in the conf
  as NEVER-DISPATCHABLE. Post-state: **`reso` open=0 · reso-management-app 59 · doc_classifier 23**,
  all inside the dispatch set; the dispatcher's uncovered-project warning is silent.
- ⚠️ **Why the premise went stale, and the generalisable trap.** This bullet's counts (56 / 23)
  matched the ledger almost exactly (58 / 23) — a *true metric beside a refuted cause*, which reads
  as corroboration and is the most persuasive way to be wrong. The fix had landed from a **sibling
  stream** between filing and dispatch; open item `0c5d47c863bf` is precisely "nothing re-checks
  whether an open item's requested fix already landed from a sibling". Check a work item's
  **remedy** against `origin/main` before building it, not just its symptom against the world.
- **Do not rebuild what exists**: `cc-backlog` / `cc-queue` / `cc-dispatch` are the sanctioned store,
  queue and dispatcher, and `com.claude.devserver-gc` already reaps dev servers — find out why five
  survived it before writing another. *(This warning earned its keep: the S4 remedy was already
  built, landed and running — searching the graveyard first is what turned a rebuild into a
  20-line declaration.)*

#### S4.1 · A refusal that reached only a journal — CLOSED (backlog `18323346082a`, 2026-08-07)

The drain is worthless if the workers it admits duplicate each other. Item `191d4d056c98` produced
**nine** sessions in ONE worktree (the filing said eight; forensics found a ninth, pane 358). Seven
of them were each told, by name, that they were duplicates —

```
{"hook":"session-register","disposition":"noop","reason":"incumbent live","item":"191d4d056c98"}
```

— and each did the whole item anyway, in one shared tree on one branch, while load hit **161.92 on
10 cores**. The ledger was never wrong: `cc-backlog`'s lease refused all seven correctly. **It had
no consumer.** A census of the executable tree found `verdict=noop-live-claimer` in exactly three
places — the producer (`bin/cc-backlog:1034`), one IDL write (`hooks/session-register.sh:220`), and
two tests asserting the string appears. `tests/session-register-reclaim.bats:184` was even NAMED
*"a second session in the worktree stands down"* while asserting only that the LEDGER was not
stolen, and was green throughout.

**Built** — `scripts/lib/worker-claim-gate.sh`, called from `hooks/check-edit-boundary.sh`
(PreToolUse | `Write|Edit|MultiEdit`, already in settings.json). A session in `wt-<id>` that does not
hold the lease is **denied its writes**, with `permissionDecisionReason` — which Claude Code feeds to
the model — naming the incumbent and the self-close command. Tests: 26 new (`worker-claim-gate` 18,
`worker-claim-gate-coverage` 8), 54/54 green across the four affected suites, six mutation controls
run and confirmed RED.

**Three things it deliberately does NOT do, each because the evidence refutes it:**

1. **It does not gate the spawn on the claim.** That is the item's first suggested remedy and
   **it already exists**: `bin/cc-dispatch:992-1005` claims before spawning and `continue`s on every
   non-zero rc, so the spawn is unreachable without a granted claim (`inventory-before-building`).
2. **It does not add a gate to `handoff-fire.sh` either — that would not have caught this storm.**
   Forensics is decisive and corrects both contemporaneous filings: there was **ONE compose and NINE
   spawns**, not nine fires and not "repeated fires reusing one prompt file". `handoff-fire.sh` mints
   a fresh `handoff-prompt-nb-XXXXXX` and appends a per-process `HANDOFF-ENGAGE-$$-…` marker on every
   invocation; only **two** such files exist in the window, and all nine first user messages are
   byte-identical at 2281 chars with **one** marker (`$$`=27022). So eight panes were launched around
   handoff-fire's front door, re-using an already-composed payload, taking no claim and leaving no
   stamp. cc-dispatch, `lead-supervisor.sh` (which contains no spawn primitive at all, despite its
   header claiming it "performs any respawn/close"), `waiting-recycle` (369 ticks, `not-armed` every
   one) and repeated handoff-fire are each independently falsified.
3. **It does not re-implement `claimer_live`.** The gate calls `cc-backlog reclaim` — the same atomic
   primitive `session-register.sh` calls, from the same identity — and branches on its documented
   `verdict=` contract, so whoever reclaims first owns the item and there is no second arbitration
   surface to race (`make-the-actuator-the-arbiter`).

**Why the enforcement is at the WRITE, and why it is not a message.** This repo already tried
telling a duplicate to stand down: `GROUND_UP_DISPATCH.md:615-628` records that the ruling sat
undrained because *"mailbox drain needs a turn boundary"* and the duplicate was deep in a tool loop —
the dead-letter shape, hit three times in one day. The same passage names where the damage lands:
*"The collision becomes real when either starts writing."* And SessionStart, where the refusal is
already known, **structurally cannot act** — on 2.1.114 its output schema is `additionalContext` ·
`sessionTitle` · `watchPaths` · `reloadSkills` · `systemMessage` · `terminalSequence`;
`{"continue":false}` has no effect, `{"decision":"block"}` is not a field, exit 2 prints and
proceeds. So `session-register.sh` stays the DETECTOR and the write is the ACTUATOR.

⚠️ **The gate carries NO refusal budget, and that is deliberate — do not "restore parity" with
`capacity-admit.sh`.** §9's law (no unbounded gate on an actuation path) is satisfied by a bound that
already exists elsewhere: the LEASE. The incumbent dying, or `cc-backlog reap` ageing the claim past
`LIVE_CLAIM_MAX_S`, releases the refusal automatically and the next write is admitted. Copying
capacity-admit's *admit-after-N-refusals* would mint the second worker this gate exists to prevent —
a capacity refusal denies a transient machine state the refusal cannot lower, this one denies a
standing FACT, and the unsafe direction is inverted between them.
`tests/worker-claim-gate.bats:13` and `…-coverage.bats:06` pin the absence structurally.

🔭 **Residual, filed not fixed** (backlog `1467ea1dad4f`): **the producer of those eight pane-spawns
is not recoverable from disk.** `dispatch-fires.log` and `handoffs.jsonl` can only count fires that go
through handoff-fire's front door, and this storm went around it — so an unlogged caller and an
undocumented detached child both remain live hypotheses, and nothing measured separates them. The
write gate makes that *safe* without making it *visible*: it catches every spawn path including the
unidentified one, which is exactly why it was chosen over gating any named path. Closing the
visibility gap needs one log line per pane-spawn carrying the caller's pid and ppid.

#### S4.2 · The residual, closed — CLOSED (backlog `1467ea1dad4f`, 2026-08-07)

**Built (1) — `scripts/lib/pane-spawn-log.sh`**, one row per surface created, into
`~/.claude/logs/pane-spawns.jsonl`. **Twenty spawn sites across nine files**, instrumented so that
ONE inference becomes sound: *a pane that exists with no row was spawned by something outside this
tree.* That is the sentence the two surviving hypotheses turn on, and it is worth exactly its
coverage — so `scripts/pane-spawn-coverage-lint.sh` (14/14 selftest, wired into `ship-land.sh`'s
always-run gate phase) blocks a land that adds a spawner without a row.

Three fields carry the identity, because the pid the item asked for names nothing months later —
it has been recycled and the process is gone:

| field | answers | discriminates |
|---|---|---|
| `pid` · `ppid` · `ppid_comm` | the literal ask | — |
| `chain` | which of OUR scripts delegated down to the primitive (`cc-dispatch>handoff-fire.sh>it2-kitty`), relayed through the environment | **hypothesis (a)**, an unlogged caller: a chain whose head is unexpected names it outright |
| `ancestry` | the real `pid:comm` walk from `$$` upward, ONE `ps` fork | **hypothesis (b)**, a detached child: re-parenting to pid 1, or a `launchd` top where `chain` claims an interactive origin |

`ancestry` reads `comm`, never `args` — argv on this box carries whole agent briefs, and a
table-wide `args=` read is the instrument that has already lied here (`pgrep-f-matches-agent-briefs`
counted 50 sessions that merely MENTIONED a string where the truth was 1).

**Built (2) — the fired-peer stamp gained a DURABLE KEY.** `mark_fired_peer` now also writes
`cc-fired/by-cwd/<sha>.json`, a pointer holding a pane id, and self-close's `absent` path can
**adopt** an orphaned record instead of refusing it. cwd is the INDEX; the fire MARKER is the PROOF.

Four decisions worth not re-litigating:

1. **The RECORD stays pane-keyed; only the LOOKUP gained a key.** Thirteen readers and twenty-plus
   test files construct `$FIRED_DIR/<pane>.json`, and `mark_fired_peer`'s own header declares the
   record ADDITIVE-ONLY because `cc-reaper` keys auto-reap on that exact path. Re-keying the store
   is a contract rebuild this item had no mandate for.
2. **A SUBDIRECTORY, not a sibling file.** Three readers enumerate with `"$FIRED_DIR"/*.json` and
   treat the FILENAME as a pane id — `cc-classify:406`, `selfclose_inventory_warn`, and
   `desk-invariant.sh:288`, which feeds max-mtime straight to `heal_role`. A second `.json` beside
   the records would have repointed the desk role at a hash. A glob does not recurse.
3. **A POINTER, not a copy.** `record_close_succession` writes `closedAt` to one path; a twin would
   keep `closedAt:null` forever and every liveness test reading it would see a spent stamp as OPEN.
4. **The marker is what makes adoption safe.** `find_open_stamp_for_cwd` could always FIND the
   orphan and deliberately refused to act, for a reason that is still correct: *"a cwd is not
   exclusive — an operator pane opened in the same worktree would match it too."* This does not
   overrule that; it adds the missing discriminator. `FIRE_MARKER` appears in exactly one session's
   transcript — the one that ingested that prompt — and an operator pane can never acquire one.
   Adoption requires the whole positive chain (orphan exists · OPEN · carries a marker · this pane's
   registry row resolves a sid · that sid's own transcript contains the marker); any link
   unresolvable ⇒ refuse exactly as before. `CC_SELFCLOSE_ADOPT=0` disables it (R8).

**The trap this change walked into, and the ratchet that now encodes it.** The first version put a
one-line `_spawn_log()` shim at the top of each file. **41 tests went red.** `as_tab`,
`spawn_frontmost`, `it2py`, `mark_fired_peer` and `lr-reset-poller`'s `spawn_gui` are all
sed-EXTRACTED as isolated units by their suites, which `eval` a function body with none of its
file's top-level definitions — so a shim call is `command not found` inside the unit under test.
`handoff-fire.sh` had already written the warning down (*"a new collaborator would be a 127 under
`set -e` — the trap this file has already paid for once"*) and it was read and walked into anyway.
The only accepted call form is now an inline `command -v` guard around the library function, and the
coverage lint **RED-cases a shim spelling** so it cannot come back.

Tests: 20 (`pane-spawn-log`) + 20 (`handoff-fired-cwd-index`) + a 14-case lint selftest.
Two further defects the work surfaced and fixed in-diff: a bare `$HOME` in the loader aborted
`kitty-split-launch.sh` under `set -u` (`addon-failure-exceeds-its-blast-radius` — the add-on must
fail no wider than itself), and a selftest probe read FALSE **on a match** because `… | grep -q`
under `pipefail` SIGPIPEs the producer and promotes 141 (`pipefail-inverts-early-exit-probe`).

⚠ **The coverage rule has a stated limit, not a hidden one.** It blocks on a primitive in a file with
NO logger call anywhere (no false positives by construction) and only NOTICES a primitive whose file
IS instrumented but whose occurrence is beyond the proximity window — because five of the twenty
sites are *declarations*, not invocations (`KARGS=(launch --type=os-window)` builds an argv issued 70
lines later; `set newTab to (create tab …)` sits inside a heredoc whose `osascript` call is above
it). Closing that would need heredoc- and array-aware parsing in bash, whose own failure mode is
silent. So: a SECOND uninstrumented spawn added to an ALREADY-instrumented file is a notice, not a
block. The notice names the file and line.

### S5 · Scale beyond this box — the only route to ~100

**100 local sessions is arithmetically unreachable**: 511 MB/session × 100 = **51.1 GB of 64 GB**,
before dev servers, before a 2.4 GB eslint, before macOS and a browser. No display-layer change
touches this — tmux saves ~0.6 cores and 0.6 GB (~2%) and costs a rewrite of the whole iTerm2-based
session lifecycle; a session switcher saves nothing if it is a view over the same processes.

So: **route repo-only work off-box.** Entitlement for remote/cloud execution is per-account and
gated — check `/accounts`, never assume. Viability is split (census §5): repo-only work ✅ · visual
design ❌ (needs the local browser + dev server) · anything about this box ❌ · branch banking ⚠️
(the 199 branches exist only here, which is the whole problem).

Cheap local wins meanwhile: **consolidate to one terminal emulator** (kitty *and* iTerm2 are both
running — 27% of a core), and stop dev servers when idle (1.9 GB each, five up).

#### S5a · The comms prerequisite — LANDED (backlog `5341a9e5fc4d`, 2026-08-07)

"Route repo-only work off-box" was blocked on something the census did not price: **the entire 2-way
comms stack is local-filesystem-only, and a sandbox can reach none of it.** Not "is awkward from" —
*cannot reach*. `cc-notify` appends to `~/.claude/mailbox/<pane-uuid>.md`; the session registry is
`~/.claude/cc-registry/<pane>.json` whose liveness signal is `kill -0` on a **local pid**;
`cc-backlog` is one untracked local JSONL; `cc-dispatch` spawns an **iTerm2 pane** via
`handoff-fire.sh`. None of them has a network transport of any kind. A cloud worker could not see
work, claim it, report it, or talk to a peer.

**Built: `bin/cc-bus` + `bus/`** — git as the bus, because it is the one channel a sandbox is
designed to reach, and because cloning the repo delivers the transport *and* the CLI in one
operation (nothing to install, no endpoint to authenticate beyond the remote it already has).

The load-bearing design property is the **one-writer law**: every file under `bus/actors/` has
exactly one writer, so shards cannot conflict. Measured with a positive control before the tool was
written, and pinned in `tests/cc-bus.bats`:

```text
two actors appending to ONE shared file  →  git pull --rebase  rc=1, CONFLICT
two actors appending to their OWN files  →  rc=0, clean merge, push OK, fold intact
```

State is the FOLD over all shards, last-transition-wins — the semantics `cc-backlog` already uses,
so this changes *where* records live and *how* they are partitioned, not what a record means.

**Two decisions worth not re-litigating:**

- **No wholesale migration.** The item said "move backlog + messages + session registry into the
  repo". Rejected on two independent counts. (1) *Publication* — the default bus is this repo, this
  repo is PUBLIC, and git history is not retractable; dumping 4,836 ledger records and 1,500+
  mailbox messages of the operator's back-traffic into it is not a transport change. (2)
  *Relevance* — a cloud worker needs the one item it was sent to do, and the registry is pane-uuid
  and pid keyed, so those rows cannot mean anything off-box even if copied. An item crosses when
  someone `offer`s it; a result crosses when a worker reports it; nothing crosses implicitly.
  `emit` enforces the publication rule on the write path: `$HOME` → `~`, and a secret-shaped record
  is **refused** (exit 3, nothing written), never silently redacted.
- **The claim stays local.** Complementary work under this same DoD ref
  (`docs/research/cloud-observability-2026-08-07.md`, backlog `191d4d056c98`) establishes that both
  local liveness oracles return *confident, wrong* verdicts about an off-box worker — so a cloud
  worker holding a **local** claim gets its item reopened and handed to a second worker. The bus
  avoids this by construction: a cloud worker claims on the **bus**; the local session that offered
  keeps the local claim. That is the "local proxy is the ledger participant" shape that doc
  prescribes, so the two designs compose rather than collide.

**Boundary with `refs/cc/*`:** that sibling design carries *liveness* (heartbeat/progress) over a
ref namespace — high-frequency, and it must NOT enter history. This bus carries *messages and work
transitions* — low-frequency, and the record trail IS the audit. The bus therefore has no heartbeat
kind, deliberately, so it never becomes a second and worse liveness oracle.

**The cloud environment, verified — three facts that FORCED the shape** (Anthropic's
cloud-environments docs + the shipped `sdk-tools.d.ts` + the changelog, 2026-08-07):

1. **A cloud VM has no `~/.claude`.** Only the repo's own `.claude/` arrives, since it is part of the
   clone; user-scope CLAUDE.md, skills, agents, commands and MCP servers do not carry over. So
   shipping the CLI *in the repo* is not tidiness — anything under `~/.claude/bin` is unreachable
   there by construction.
2. **GitHub Issues — the item's own alternative carrier — is refuted.** `gh` is not preinstalled and
   `GITHUB_TOKEN` reads as the literal placeholder `proxy-injected`. Recorded so it is not
   re-proposed.
3. **The channel is ASYMMETRIC.** here→cloud is a full git remote (clone/fetch unrestricted, and the
   VM clones from the *pushed* remote, not local disk — `sdk-tools.d.ts` L3764). cloud→here is a
   **one-branch pipe**: the GitHub proxy's push protection allows `git push` only against that
   session's own working branch. An off-box worker's records therefore cannot reach trunk by its own
   action, which is why reading the bus is `sync --gather` + `fold --refs` (read *out of* refs, never
   copied into the tree — copying another actor's shard would be the cross-write the one-writer law
   forbids).

⚠️ **This lands on the `refs/cc/*` heartbeat design and is the next experiment to run.** Whether push
protection is enforced per-*branch* (leaving `git push origin HEAD:refs/cc/…` a loophole) or
per-*refspec* (blocking it outright) is settled by no doc, changelog entry, or binary string. If
per-refspec, `refs/cc/*` cannot be written from a cloud VM at all and O1 must become a working-branch
commit — the shape that design rejected — or leave git. One `--cloud` session and one attempted ref
push decides it. This bus does not depend on the answer; that design does.

**What this does NOT establish.** Cloud entitlement is per-account and remains unverified — the same
limit §7 of the sibling doc records. Measured on this box: `hasRemoteEnvironment: true` appears in
`~/.claude-quaternary/.claude.json` (**account 4 only**; absent for accounts 1–3), and
`remote.defaultEnvironmentId` is absent everywhere, so `/remote-env` has never been run. Whether that
key means *entitlement* or merely *an environment record exists* is unverified, as is the org's
`allow_remote_sessions` policy (the binary carries `allow_remote_sessions policy denied` as a live
error path). `--cloud` is a real hidden flag on v2.1.220 and refuses without a TTY. This is the
prerequisite that must exist *before* cloud execution is used; it is not evidence that cloud
execution is available. Latency is push/pull, not poll: nothing arrives until someone syncs.
#### S5.1 · Cloud observability — DONE (backlog `191d4d056c98`, 2026-08-07)

**→ `docs/plans/CLOUD_OBSERVABILITY.md`** (design + measurements, with the command for each so they
can be re-measured rather than believed) and `docs/research/cloud-observability-2026-08-07.md`.
Built: `bin/cc-cloud` (fire-time capture) · `bin/cc-cloud-watch` (`ls-remote` observer).

Three results that change how S5 is sequenced:

1. **The local instruments do not go quiet off-box — they answer, wrongly.** ~80 of ~85 probes are
   structurally blind to a VM, and two *actuate* on the false reading: `cc-backlog`'s liveness
   oracles convicted a cloud claim as PROVEN-DEAD → `reopen` → `cc-dispatch`'s fire predicate → a
   second worker onto live work (fixed here: `--venue`, `0d173af4`); and
   `scripts/lead-supervisor.sh:437` returns `dark` for any cwd absent locally, so **every cloud
   session fired today would be paged as hung, forever** (measured with controls, fix filed
   separately — it touches a live daemon's escalation path).
2. **O1–O3 — session id, branch, deadline — exist only at the moment of the fire.** Nothing local
   records a cloud session, so un-captured they are gone and the session is unobservable *in
   principle*. This is the item's whole point, and it cannot be retrofitted onto sessions in flight.
3. **Silence is never death.** `ls-remote` separates absent (rc 0) from unreachable (rc 128), so the
   observer's own network failure cannot forge a death verdict. A repo-side channel may prove life;
   it may never prove death.

**Composes with S5a, and depends on it.** S5a's bus is how a cloud worker *participates*; this is how
it is *observed*. The split is deliberate on both sides: the bus carries messages and work
transitions (low-frequency, the trail IS the audit), `refs/cc/*` carries liveness (high-frequency,
must never enter history). S5a's "the claim stays local" is exactly this doc's local-proxy shape —
and it is the safer of the two answers to the `--venue` problem, because it never mints a cloud claim
at all.

⚠️ Still open and operator-gated: **entitlement**. `bin/claude-accounts` has no cloud concept, so
S5's "check `/accounts`, never assume" points at a surface with no such field.

🚧 **Correction to an earlier draft of this section** (kept, because the error is the reusable part):
it claimed *"neither installed binary exposes a `--cloud` verb"*, measured by
`claude --help | grep -ci cloud`. **False — `--cloud` is a real HIDDEN flag on 2.1.220**, so `--help`
is structurally incapable of seeing it, exactly as S5a reports. Re-measured with the control that
should have been there from the start: `--cloud` returns *"requires an interactive terminal"* while a
fabricated flag returns *"unknown option"* — the binary distinguishes them, so absence from `--help`
was never evidence of absence (memory: `lookup-miss-is-not-absence`). A `--help` scrape is a weak
oracle for a CLI that hides flags; probe the behaviour, and pair it with a known-absent control.

---

## 2 · What is NOT on this path

Recorded so they are not re-proposed:

- **A byte-identical oxlint/oxfmt/oxc port** of reso's eslint config. Rejected on categorical
  grounds, not effort — census §4. The 78 airbnb stylistic rules are a category mismatch with a
  formatter, and the 13 plugin/custom rule-uses (`@pandacss`, `reso-design`, tailwind) have no
  eslint-plugin ABI. Those 13 are precisely the ones that bite in practice.
- **A frontier-tier (Fable) session** for any of this. Every open question here is answerable by
  measurement, and the two that looked frontier-shaped dissolved once measured (the "load average
  is the wrong metric" hypothesis was built on a misreading; the oxlint question is a coverage audit).
- **`nice` / `taskpolicy` / QoS throttling** to shed load — it re-specifies every wall-clock timeout
  and fails suites rather than slowing them.
- **Building a second queue.** S4.

---

## 3 · Sequencing note

S0 is the operator's, and gates the automation of everything else. **S1 is independent of S0** and
should not wait for it — it is pure loss-avoidance and needs no gate. S2 → S3 → S4 is a strict
chain: contention-fix RELEASES the items, so triage must exist before the release, not after. S5 is
parallel to all of it and is the only track that changes the ceiling rather than the throughput.
