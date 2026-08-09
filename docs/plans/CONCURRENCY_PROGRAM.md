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

### 0.1 · The engine, named — and it is NOT the landing gate (backlog `98e0e325b3ed`, 2026-08-07)

The diagnosis above is right about the SHAPE and wrong about the SUBJECT, and the correction matters
because it moves the fix off S2's critical path entirely. Measured on the live store the same day:

| | |
| --- | --- |
| items blocked `persistent thrash — … the worker cannot land` | **228** (64% of all blocked) |
| …whose every counted claim→reopen pair was authored by ONE identity on both sides | **228 / 228** |
| …that never held a claim for even the 90 s thrash window — **no worker ever ran** | **182 / 228** |
| fast claim→reopen pairs across the WHOLE ledger: same-author / different-author | **691 / 14** |
| `cc-dispatch` verdicts in one live 2 h window: `spawn rc=9 (reopened)` vs `fired` | **36 vs 5** |

**No land was involved.** `cc-dispatch` claims an item BEFORE it fires and rolls its own claim back on
every failure path — `bin/cc-dispatch` compose-fail, worktree-fail, spawn rc≠0. That writes
`claim → reopen` seconds apart, which is byte-for-byte the shape `cc-backlog reap` rule B reads as
*"a worker keeps bouncing off this item"*. Two of them and the item is `blocked` — the OPERATOR-ONLY
state, which `cc-dispatch` excludes from the wave by construction. rc 9 is the **fire capacity gate**,
whose own refusal text is *"Shed load first (close finished panes / let the wave drain), then
re-fire"*: a condition its producer explicitly asks the caller to retry.

So the real cycle is one step shorter and one layer lower than §0 draws it:

```text
many concurrent sessions  →  fire CAPACITY GATE refuses the spawn (rc 9, "shed load, then re-fire")
  →  cc-dispatch self-releases its own uncommenced claim  (claim → reopen, seconds apart)
    →  2 of those ⇒ reap rule B ⇒ `blocked` + "the worker cannot land" — a sentence about a worker
       that was never fired
      →  the item leaves the autonomous queue PERMANENTLY (8 open vs 356 blocked, and climbing)
        →  the work moves back into interactive sessions  ⟲
```

**Why it went unseen for a week.** Rule B is the only rule in `reap` that fires on TRAIL SHAPE ALONE
— its own comment says so (*"Both oracles are `-` (never asked)"*) — while every other rule in the
same file is three-valued and abstains on a non-verdict. And the verdict it writes is prose that
READS like a finding: an operator scanning 228 rows saying "the worker cannot land" sees a landing
problem, which is exactly the conclusion §0 drew. A true metric (the gate really was being killed by
contention, elsewhere) beside a wrong cause manufactures corroboration.

**Fixed** — `cc-backlog reopen --self-release spawn-fail|compose-fail|worktree-fail`, asserted by
`cc-dispatch` on all three rollback paths, and excluded from rule B's `fastFail` fold. The flag is
closed-set and claimer-authenticated because it SUPPRESSES a guard; the exclusion is positive
evidence only (a same-author heuristic is what found the bug and is deliberately not the predicate);
and the suppressed count is PRINTED every sweep, because it is real news about the machine even
though it is not news about the item. Retroactive repair of the 228:
`scripts/thrash-block-recover.sh` (dry-run by default, re-derives per item, never a hardcoded list).

🚦 **The repair is SEQUENCED behind the live layer, and running it early is worse than not running
it.** `~/.claude/bin/cc-backlog` symlinks into `~/Development/claude-infrastructure`, so the reap
that actually sweeps is the LIVE checkout's copy — not trunk's. Measured at land time: the fix is on
trunk, the live checkout is **13 commits behind**, and `cc-backlog-reap` had run **90 seconds
earlier**. Unblocking 233 items against a live binary that still carries the old rule B does not fix
them; it appends 233 `unblock` records to an append-only ledger and hands them straight back to the
next sweep, which re-blocks them. So the order is **land → converge → apply**, and the dry run
(`scripts/thrash-block-recover.sh`, no flags) is the safe thing to run at any time.

> **Correction (2026-08-07, measured while applying `f06c9bb61933`): the ORDER is right, the stated
> MECHANISM is not.** Re-block does *not* come from the historical rows. The live binary already
> carries the unblock watermark — `reap`'s fold cuts `fastFail` at the LAST `block`/`unblock` record
> (`$cut`, `bin/cc-backlog:1711-1718`, whose own comment names this: *"a deliberate `unblock` is
> re-blocked by the very next reap on pre-unblock history … unblock never survives cc-reaper"*). An
> `unblock` therefore moves the watermark and the 238 historical pairs become uncountable.
> The real re-block vector is **fresh, post-unblock dispatcher self-releases**: released items
> re-enter the wave, the live `cc-dispatch` still reopens with a bare `--by` (its two `self-release`
> mentions are comments, `bin/cc-dispatch:1059,1102`), the live `reap` has no `selfRelease`
> exclusion, so each rc-9 refusal writes a *countable* fast pair — and at the measured 36 rc-9 vs 5
> fired per 2 h, two pairs per item arrive fast. Early application is still worse; it just fails one
> layer later, and one layer harder to see.



⛔ Convergence is currently **refused, by a cause outside this work**: `deploy-live.sh` is
fail-closed on a GREEN post-land stamp and `cc-blockers` reports `trunk-red PERSISTENT-RED — newest
5 all red, 2 green of 88 ever`, last green **2026-08-04**. None of the five newest red stamps names
any subject in this diff; the three suites here that appear anywhere in the historical red set were
last red 3-8 days ago and all ran green this session. Queued as backlog `f06c9bb61933`, whose premise
is a live re-read (`grep -c selfRelease "$(readlink -f ~/.claude/bin/cc-backlog)"`) rather than a
date — so it becomes actionable the moment the live layer advances, and refuses itself if it has not.

> **Update (2026-08-07, same day): that ⛔ is no longer the state — the wall dissolved before the
> item was worked.** `deploy-live.sh` was rebuilt (DEPLOY_LANE_GROUND_UP §2.2) precisely because a
> green-only gate deadlocks by construction — its own header measures *534 identical refusals, 276
> launchd runs all exit 1, live layer 91 commits stale, ZERO pages*. It now selects across three
> tiers: **T1 VERIFIED** (newest green descendant) → **T2 DEGRADED** (T1 empty *and* lag past budget
> ⇒ newest NOT-RED commit, under a loud banner + a page) → **T3 BLOCKED** (all red). So convergence
> is **budgeted and autonomous**, not indefinitely refused: `com.claude.deploy-live` (`--auto`,
> `StartInterval` 600 s, verified loaded) advances the live layer the moment
> `CC_DEPLOY_MAX_LAG_COMMITS` (25) or `CC_DEPLOY_MAX_LAG_HOURS` (6) trips, whichever comes first.
>
> Read at 10:42: lag **14 commits / 5 h**, i.e. *inside* the budget — so the refusal seen at that
> moment is the gate working, not a blocker. Note the hours clock is integer-floored and compared
> `-gt 6`, so it authorises at **7 full hours** past the live commit's committer date, not 6.
> `--force` / `--bootstrap` / a lowered budget remain the **operator's** escape hatches: an agent
> taking one to make its own item dispatchable is laundering the gate, and is not the sanctioned path.



⚠️ **This does not retire S2.** Gate contention is real and still unfixed; what changed is that it is
no longer the thing jamming the QUEUE. S2 governs throughput once items are dispatchable again.

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

#### S5-CEILING · The off-box ceiling, measured 2026-08-08 — and it is NOT the number this section expected

**Verdict: the ceiling is UNMEASURED, and the blocker is not quota. It is create RELIABILITY.**
No number is published here, deliberately: §7's discipline is a measurement with its command, and
"~15 sessions" is folklore precisely because a number once got published without one.

**What WAS proven — and it is the load-bearing half.** A cloud session can be created with **no
human in the loop**: `session_01VhevKS8tr3aRmULXtfW2xj`, created from a script, captured, declared,
and confirmed observable. Two conditions, both non-obvious:

- **The create requires a PTY.** Measured: `Error: --cloud requires an interactive terminal.
  Non-interactive invocations (piped stdout, …) run locally and would silently ignore --cloud.` A
  probe captures stdout by construction, so the naive form is refused on its own capture. `script -q
  /dev/null <cmd>` satisfies it and still allows capture. ⚠️ **Do not look for a flag to suppress
  this check**: the refusal says the run would otherwise *"silently ignore --cloud"* and execute
  **locally** — a fleet that believes it is off-box while every session runs on this machine, which
  is the exact inverse of what this section is for. The check is a guard against a far worse
  failure than the one it causes.
- **The SEND arm needs no pty** (§6.3, stdin closed, `{ok:true}`). Create and send are gated
  differently; conflating them loses one of them a gate it needs.

**What BLOCKED the ceiling measurement.** The create is **intermittent**: 1 of 4 attempts succeeded
inside a ~15-minute window on `next3`, all from the same box. The three failures are all
`Error: Bundle upload failed: Socket is closed after 3 attempts. Please setup GitHub on
https://claude.ai/code` — i.e. the CLI fell back to **bundle mode**, which §6.5 of
`CLOUD_OBSERVABILITY.md` establishes is what happens *when the GitHub link is unavailable*. So a
ramp cannot distinguish "the account hit its limit" from "this attempt fell back to bundle mode",
and a ceiling read off that ramp would be measuring flakiness.

⚠️ **An unresolved confound, recorded rather than resolved, because resolving it costs quota per
data point.** The one success ran with `CLAUDE_CONFIG_DIR` **inherited**; the three failures ran
with it **re-exported through `env` at the identical value**. That correlation is perfect and it is
also n=1 on the success side, against a failure mode whose own text (`Socket is closed after 3
attempts`) reads as a transport flake. **Both readings fit every observation**, and picking one
would be a wrong cause corroborated by a true metric. Next measurement should hold `env` fixed and
re-run the same invocation several times, before anything is concluded about the environment.

**Two refuted hypotheses, recorded so they are not re-run:**

| Hypothesis | Test | Result |
| --- | --- | --- |
| A linked git **worktree** breaks the CLI's repo/GitHub detection (its `.git` is a file, not a dir) | same create from the main checkout | **REFUTED** — identical failure |

🚨 **This row was RIGHT, and a later section of this same document re-raised the hypothesis it had
already killed.** §S5.2 filed the worktree story as `SUSPECTED, NOT ESTABLISHED` — against a table,
six hundred lines up, recording the *same* hypothesis tested the *same* way and refuted. §S5.3
(2026-08-09) then re-refuted it a third time, with an instrument. The repo already knows the rule
for two oracles in contradiction (`[[spec-named-mechanism-may-be-prose-only]]`: one is stale, and
the shipping side wins) — the gap is that the rule was only ever applied ACROSS artifacts, never
WITHIN one. A long plan document is not one oracle; it is a stack of them at different dates, and a
new finding has to be checked against its own file's refuted list before it is filed as open. Cost
of not doing that here: a measurement re-run twice and a remedy prescribed for a dead cause.
| The marker set tells you which accounts can create | `next2.linked` exists; its create fell back to bundle mode | **REFUTED** — the marker is a progress log, not a capability |

**Re-measure with** (both arms; the control first, and never skip it):

```
scripts/cloud-ceiling-probe.sh --control --confirm          # validate the classifier, free
scripts/cloud-ceiling-probe.sh --account <acct> --max N --confirm
```

The control needs an account at ≥99% weekly — a **known** quota refusal — and it refuses to pass
without one. On 2026-08-08 the only such account (`next2`) could not create at all, so the
classifier's quota patterns remain **UNVALIDATED**; that alone forbids publishing a ceiling.
(the 199 branches exist only here, which is the whole problem).

Cheap local wins meanwhile: **consolidate to one terminal emulator** (kitty *and* iTerm2 are both
running — 27% of a core), and stop dev servers when idle (1.9 GB each, five up).

🔑 **What going off-box actually buys, and what it does not (settled by primary source 2026-08-07).**
The arithmetic above prices RAM, so it implies the cap *moves* off-box. It does — but only one of the
two caps:

- **Claude Code on the web is subscription-billed**, and its own limits section is explicit:
  *"Claude Code on the web shares rate limits with all other Claude and Claude Code usage within your
  account. Running multiple tasks in parallel consumes more rate limits proportionately. There is no
  separate compute charge for the cloud VM."*
- So off-box **relieves CPU and RAM, not tokens.** The binding constraint moves from 64 GB / core
  count to **per-account rate limits across the 4 accounts** — which is a real win (the 51.1 GB wall
  is absolute; rate limits are four-way shardable and refill), but it is not free concurrency, and a
  ~100-session target has to be priced against four accounts' limits rather than against a VM count.
  Live headroom is `claude-accounts` / `/accounts`, never an assumption — measured 2026-08-07 the four
  accounts sat at 75% · 76% · 25% · 99% weekly, i.e. **one of the four was already effectively
  unusable**. Rate-limit headroom is the scheduling input, and it is volatile.
- Docs state **no numeric per-account concurrent cloud-session cap** — UNVERIFIED, and worth measuring
  rather than assuming; it is the number that decides the fan-out width.

❌ **Claude Managed Agents is OUT for this fleet — settled, do not re-investigate.** It was the
obvious candidate for "route work off-box" and it does not fit on any subscription: prerequisite #1 is
*"A Claude API key"* (`platform.claude.com/docs/en/managed-agents/overview.md` § Beta access), and it
bills standard model token rates **plus $0.08 per session-hour**
(`…/about-claude/pricing.md` § Claude Managed Agents pricing). There is no subscription-backed path.
Claude Code on the web is the surface to build on, and it is the one this section's route already
assumes.

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

⚠️ ~~**This lands on the `refs/cc/*` heartbeat design and is the next experiment to run.** Whether push
protection is enforced per-*branch* (leaving `git push origin HEAD:refs/cc/…` a loophole) or
per-*refspec* (blocking it outright) is settled by no doc, changelog entry, or binary string.~~ If
per-refspec, `refs/cc/*` cannot be written from a cloud VM at all and O1 must become a working-branch
commit — the shape that design rejected — or leave git. ~~One `--cloud` session and one attempted ref
push decides it.~~ This bus does not depend on the answer; that design does.

✅ **RESOLVED 2026-08-08 (item `40b46a34e1ce`) — treat it as per-REFSPEC. `refs/cc/*` is out, and the
consequence this paragraph pre-committed to now binds: O1 becomes a working-branch commit or leaves
git.** The strike-through above is the part that was wrong on its facts, and it is the instructive
half: **"settled by no doc" was false when written.** Anthropic's cloud-environments page states the
rule in one line, under *GitHub proxy*:

> **Push protection**: `git push` works only against the session's current working branch; cloning,
> fetching, and PR operations work normally.
> — <https://code.claude.com/docs/en/cloud-environments>

`refs/cc/heartbeat/<id>` is not the session's current working branch. **The lesson is about search,
not about git:** the claim "no doc settles this" is a claim about a *corpus you searched*, and the
searched corpus here was `sdk-tools.d.ts`, the changelog and the binary's strings — the three places
this program had been finding everything else. The vendor's own configuration docs were never read.
A negative existence claim is only as strong as the sources it enumerates, so **state the sources or
do not make the claim** (`[[lookup-miss-is-not-absence]]`, applied to documentation).

🔑 **And the answer was already on disk, in shipping code, while this paragraph called it open.**
`bin/cc-bus:31` — landed as part of the very commit (`37796b13`) this section says "does not depend
on the answer" — carries the comment: *"a `refs/cc/*` beat ref is precisely what push protection
blocks."* Its author read the same push-protection rule and drew the same conclusion. So the repo
held **two oracles in contradiction**: a plan doc saying *unsettled, needs an experiment*, and a live
program saying *settled, here is the consequence*. The shipping side was right, which is the
resolution rule this repo already knows (`[[spec-named-mechanism-may-be-prose-only]]`: when two
oracles disagree, one is stale and the shipping side wins). **Cost of not checking: two cloud
sessions and a day of watching a remote for a ref that could never appear.** The cheap prevention was
one `grep -rn 'refs/cc' bin/`, which is the same *search the code before running the experiment* rule
as `[[search-branch-graveyard-before-building]]` — it applies to settling questions, not just to
building things.

⚠️ **Honest limit — this is the vendor's stated rule, not a measurement of the proxy.** The loophole
hypothesis (enforcement that checks `refs/heads/*` only, leaving `refs/cc/*` unexamined) is
**untested**: the probe never reached the proxy, because **no cloud session this box creates has ever
been observed to execute** — 11 sessions, ≥2 accounts, longest 17h, zero remote-visible actions
(`cloud-observability-2026-08-07.md` §4.7). That gap is not a reason to keep the design alive.
A heartbeat built on an undocumented gap in a stated security control fails **silently** the day the
gap closes, and silent failure is the one mode the O1 design exists to prevent.

🚨 **The bigger finding is the one that blocked the measurement, and it outranks this item.**
§S5.2 measured that quota does not gate cloud *create*, and noted that *"creating a session and
running tokens through it are different questions, and only the first has been measured."* The second
is now measured, and the answer is **zero**. Until one cloud session is observed doing work,
**cloud capacity is not capacity** and nothing downstream of "a cloud worker does X" should be built.
Filed as its own item; it is a precondition for S5, not a detail of it.

**What this does NOT establish.** ~~Cloud entitlement is per-account and remains unverified~~ — the same
limit §7 of the sibling doc records. Measured on this box: `hasRemoteEnvironment: true` appears in
`~/.claude-quaternary/.claude.json` (**account 4 only**; absent for accounts 1–3), and
`remote.defaultEnvironmentId` is absent everywhere, so `/remote-env` has never been run. ~~Whether that
key means *entitlement* or merely *an environment record exists* is unverified~~, as is the org's
`allow_remote_sessions` policy (the binary carries `allow_remote_sessions policy denied` as a live
error path). ~~`--cloud` is a real hidden flag on v2.1.220 and refuses without a TTY.~~ This is the
prerequisite that must exist *before* cloud execution is used; it is not evidence that cloud
execution is available. Latency is push/pull, not poll: nothing arrives until someone syncs.

**↑ Three of those claims were RESOLVED 2026-08-07 (later same day). Full measurements + controls:
`CLOUD_OBSERVABILITY.md` §6.1–6.7 and §7.1. In brief:**

1. **`hasRemoteEnvironment: true` is a RECORD, not entitlement.** Account 4 — the only one carrying
   the key — is gated *identically* to accounts 1–3: interactive attach refuses
   `Attaching to an existing cloud session is not enabled for your account` on **all four**. The gate
   is checked *before* session-id validation, so a fake id probes it without creating anything.
2. **"refuses without a TTY" was half right, and the half that is wrong is the load-bearing one.**
   `--cloud` is polymorphic: an *id-shaped* argument addresses an existing session, anything else is
   read as a new session's task **description**. The create path is interactive-only; the send path
   is **not**. `claude -p "<msg>" --cloud <id> --output-format json` runs headless with no pty — the
   bundle's own telemetry calls it `cloud_attach_headless`. The refusal that reads as a TTY
   requirement is what you get when a mis-shaped id silently falls through to the create path. **So
   `cc-notify` has an off-box send transport** (design: `CLOUD_OBSERVABILITY.md` §9.2). Whether a
   message actually *reaches* a live session is UNPROVEN — it needs an id we cannot yet mint.
3. **The `--cloud` verb genuinely is absent on the pinned 2.1.114** and present-hidden on
   2.1.215/219/220 — so this section and §6 of the sibling doc were never in conflict, only
   version-split. `--remote` is its alias. Do not re-litigate this without re-measuring the parser
   (`--help` cannot see a hidden flag, which is how the sibling doc's controlled measurement still
   got it wrong).

⚠️ **One S5a fact is now contradicted by a live measurement and needs adjudicating.** Fact 3 above
states, citing `sdk-tools.d.ts` L3764, that "the VM clones from the *pushed* remote, not local disk".
The CLI create path fails with `Bundle upload failed: … Please setup GitHub on https://claude.ai/code`
— i.e. it **uploads a bundle of the local tree**. Both can hold for *different* surfaces (a
cloud-environment session cloning the remote vs the CLI's `--cloud` shipping a bundle), but they
cannot both describe the CLI route, and the difference decides whether an unpushed branch is invisible
off-box. Left as an open contradiction, not a decided fact; the first successful fire settles it
(`CLOUD_OBSERVABILITY.md` §6.5, §9.4 item 4).

**Why the `refs/cc/*` experiment below is still unrun, now with a named cause.** It needs one live
cloud session, and no programmatic fire path is open today: CLI create is blocked on connecting GitHub
at `claude.ai/code`, and the routines `/fire` endpoint — **proven to exist**, unauthenticated `401` vs
a `404` control on a sibling path, and subscription-billed with no `--cloud` verb or TTY in the way —
is blocked on minting a per-routine bearer token. Both are **web-only operator actions**, one action
each. Interactive attach is blocked by an **Anthropic-side rollout** and is not clearable here.

**↑ That named cause is SPENT, and the replacement is worse (2026-08-08).** The CLI create path
opened (§6.5 of the sibling doc) and two sessions were fired for this very experiment, on two
accounts, one of them `--verify`-linked. Neither ran. So the blocker moved from *"we cannot start a
cloud session"* to *"a started cloud session does nothing observable"* — 11 declared, 0 actions,
longest 17h. **A named cause that gets cleared is not the same as a problem that gets solved**: this
paragraph's diagnosis was correct and its clearing bought no measurement.

#### S5.2 · The measured ceiling — MEASURED 2026-08-08, and the honest answer is a LOWER BOUND (gate G7)

**The command, so this is re-run rather than believed** (§7 discipline). Every create spends real
quota; `--confirm` is mandatory and `--max` has no default:

```bash
scripts/cloud-ceiling-probe.sh --account <acct> --max <N> --confirm   # ramp
scripts/cloud-ceiling-probe.sh --control --confirm                    # validate the classifier
scripts/cloud-ceiling-probe.sh --report                               # re-print the ledger
```
Ledger: `~/.claude/autonomy/cloud/ceiling-probe.jsonl`, one row per attempt, each carrying `run`
and `cwd`.

**THE NUMBER: ≥ 2 concurrent cloud creates on ONE account, and NO ceiling was reached.** Reported as
required even though it is disappointing — it is a *lower bound*, not the ceiling, because the ramp
ran out of the budget it was given rather than out of quota. A lower bound is still worth publishing
because, unlike a ceiling, it does not depend on the classifier being right: it counts successes.

Two findings matter more than the number:

1. 🚨 **Weekly quota does not gate cloud CREATE.** `next2` sat at **100% weekly** (`claude-accounts`
   reporting `weekly LIMITED`) and created **four** cloud sessions across four runs. So the premise
   this program has been sequencing on — *"cloud relieves CPU and RAM, not tokens; the ceiling moves
   from 64 GB to per-account rate limits"* — is **not observable at the create boundary**. Creating a
   session and running tokens through it are different questions, and only the first has been
   measured. **The `--control` arm is consequently VOID, and there is no free known-refusal left to
   validate the classifier against**: the control's entire design assumed a 100%-weekly account would
   be refused, and it is not. So anything published as a *ceiling* from this instrument remains
   unvalidated; only lower bounds are safe today.

2. ⚠️ **A create from a git WORKTREE fails where the same account from the main checkout succeeds.**
   The refusal is `Error: Bundle upload failed: Socket is closed after 3 attempts. Please set up
   GitHub on https://claude.ai/code` — which names GitHub and is therefore easy to misread as the
   §6.5 linking blocker returning. It is not: linking is done, and the same account created a session
   seconds earlier.

   | cwd | `.git` | ramps | result |
   |---|---|---|---|
   | `.worktrees/cloud-100pct` | a **file** (86 B gitdir pointer) | 3 | every ramp hit `Bundle upload failed`; 2 of 5 creates got through |
   | `~/Development/claude-infrastructure` | a **directory** | 1 | 2/2 created back-to-back, no refusal |

   **STATUS: SUSPECTED, NOT ESTABLISHED.** 3-of-3 against 0-of-1 is a real asymmetry on a plausible
   mechanism — a bundle upload walking a `.git` that is a pointer into another tree — but the main
   checkout has n=1 ramp and one worktree create did succeed, so "back-to-back creates are simply
   flaky" is not excluded. Filed, not asserted.

   **It gates G5 whichever explanation wins.** This repo's standing rule is that every concurrent
   writer session gets its own worktree, and Agent Teams isolate teammates in worktrees by
   construction. So the *default* configuration for firing cloud work is exactly the one that failed
   here. ~~`handoff-fire.sh --cloud` must fire the create from the **main checkout**~~ — or measure this
   properly first — rather than inheriting the caller's worktree cwd and hoping.

   🚨 **REFUTED 2026-08-09 — the worktree was never the variable, and the prescribed remedy would
   have fixed nothing. → §S5.3.** The strike-through above is the load-bearing part: firing from the
   main checkout is a change with a cost (every cloud fire would have to leave the caller's tree)
   bought against a cause that does not exist. Both halves of the asymmetry dissolved on measurement —
   the main checkout fails with the *identical* error, and the worktree creates successfully.

**What the instrument itself cost, recorded because it is the transferable part.** The probe landed
at `66ef4d8c` with no test suite and **four** stacked defects, each of which alone made a measurement
impossible, and every one of which failed in the direction that looks like honest abstention rather
than like a bug:

| # | Defect | Why it was invisible |
|---|---|---|
| 1 | `fire_one` emitted no trailing newline; both consumers are `read`, which returns 1 at EOF under `set -e` | Died **after** firing the create — quota spent, verdict never printed. The ledger held a `ramp-start` with zero `attempt` rows. |
| 2 | The create path is interactive-only; `fire_one` ran under `$( )` | Refused on **every** account before quota was consulted, and the three-outcome classifier had to call it `refused-other` ⇒ *"classifier WRONG"*, convicting the one component that was right. |
| 3 | The pty fix used `script(1)`, which calls `tcgetattr` on its **own** stdin | Works from an interactive shell; dies `Operation not supported on socket` from an agent call, cron, launchd or CI — i.e. everywhere a measurement rig actually runs. |
| 4 | ANSI stripping deleted cursor-forward (`CSI n C`), which a TUI emits **instead of** runs of spaces | Fused a live refusal into `Error:Bundleuploadfailed:Socketisclosed…`. Every quota pattern contains a space, so a real ceiling would have matched nothing and been reported as a network non-verdict. |

A fifth was found in the ledger rather than the code: rows carried no run id, and the file is shared
across concurrent sessions — so two interleaved 2-create runs read exactly like one 4-create run. For
a measurement that **is** a count of rows, that is not lost provenance, it is a doubled ceiling.

⚠️ **Attribution, because it is itself a finding.** Defects 1, 2 and 4 were found and fixed
*independently and concurrently* by a sibling session, which landed first (`4a3c07af`, `200198ac`) —
two sessions converged on the same three bugs within the same hours, from the same evidence, neither
aware of the other. Defects 3 and 5, and the `refused-harness` state, are this branch's delta on top
of theirs. Three things worth carrying:

- The convergence is **evidence about the defects, not about the sessions**: bugs that two
  independent readers both hit on first live contact are load-bearing, not incidental.
- It cost a real merge conflict and a rebuild-on-top, and the cheap prevention existed the whole
  time — `git log --all --oneline -- <path>` before starting on a file this active. The repo already
  knows this rule for abandoned branches; the lesson here is that it applies just as hard to
  *concurrent* work.
- Where the two implementations disagreed, the merge kept **the measured one**. The sibling's
  `script(1)` allocator is correct interactively but dies `tcgetattr … Operation not supported on
  socket` under an agent call, cron or launchd — measured here, which is why `scripts/lib/pty-run.py`
  is now first and `script` is the fallback. Neither side was wrong about its own evidence; only one
  side had run it headless.

All five are fixed and pinned by `tests/cloud-ceiling-probe.bats` (18 tests, RED-verified at 9
failures before the first fix). A fourth outcome, `refused-harness`, now sits **ahead of** the quota
arm, so a fault in our own rig can never be published as a property of the fleet.

#### S5.3 · The worktree discriminator — SETTLED 2026-08-09, and the cause is bundle SIZE, not cwd

**The command, free, spends nothing** (this is the half §S5.2 could not have run, because it did not
know the bundle was reproducible locally):

```bash
scripts/cloud-bundle-probe.sh --measure                       # FREE — rebuilds the real artifact
scripts/cloud-bundle-probe.sh --ab --account <a> --rounds N --confirm   # live, interleaved arms
scripts/cloud-bundle-probe.sh --report
```
Ledger: `~/.claude/autonomy/cloud/bundle-probe.jsonl`, every row carrying `run`, `arm` and `cwd`.

**VERDICT: the worktree hypothesis is REFUTED, on two independent legs.**

*Leg 1 — mechanism, measured for free.* The CLI's bundle is built by plain `git bundle create`, so
the artifact it uploads can be rebuilt locally and weighed. The tier arithmetic, read out of the
2.1.220 binary: `sizeBytes = size-pack × 1024`, cap `104857600` (100 MiB), `--all` unless
`sizeBytes > cap`, then `HEAD` unless `sizeBytes > 3×cap`, then a squashed root.

| cwd | `.git` | size-pack | tier | bundle |
|---|---|---|---|---|
| `.worktrees/cloud-hardening` | **file** (89 B gitdir pointer) | 119,522,304 | head | **99,778,280 B (95% of cap)** |
| `~/Development/claude-infrastructure` | **directory** | 119,522,304 | head | **99,712,572 B (95% of cap)** |

`size-pack` is a property of the **object store**, and a linked worktree *shares* it — its `.git`
file points at `<main>/.git/worktrees/<name>`, whose `objects` is the common dir. So both cwds take
the same tier and upload bundles differing by **0.07%**. The proposed mechanism — "a bundle upload
walking a `.git` that is a pointer" — cannot operate: the pointer is resolved by git before a single
byte is bundled.

*Leg 2 — the live A/B, interleaved so a transient window cannot land on one arm.*

| round | `wt` (worktree) | `main` (main checkout) |
|---|---|---|
| 1 | `Bundle upload failed: Socket is closed after 3 attempts` | **the identical refusal** |
| 2 | created | created |
| 3 | created | created |

Failures cluster by **round**, not by cwd. Both halves of §S5.2's asymmetry dissolved: the main
checkout fails with the same error, and the worktree creates. Totals across this session, one
account, 11 fires: `wt` 2 created / 2 refused, `main` 3 created / 1 refused — and the earlier
3-of-3-vs-0-of-1 is what a ~50%-reliable step looks like at n=4.

**What is actually wrong: a ~95 MiB upload with 3 retries, riding at 95% of a 100 MiB cap.** That is
marginal by construction, which is exactly why it presents as intermittent and why it invites a
cause-of-the-week. The GitHub sentence in the refusal is not evidence of a broken link either — the
CLI appends `. Please setup GitHub on https://claude.ai/code` to a **transport** failure whenever a
GitHub remote was detected, which is how §S5.2 read a 95 MiB timeout as a §6.5 linking regression.

**Why the bundle exists at all, and the one lever that removes it.** The create path bundles only
when it cannot use a GitHub source. The branch is `x = appInstalled`, from a preflight
`GET /api/oauth/organizations/{org}/code/repos/{owner}/{repo}` → `status.app_installed`. When the
Claude **GitHub App is installed on the repository**, the session is created with a
`git_repository` source and **no bundle is uploaded at all** — the 95 MiB step, and this whole
failure class, disappears. When it is not, the CLI falls back to seeding from local HEAD.
⚠️ **This also resolves the §S5a contradiction left open** ("the VM clones from the pushed remote"
vs "it uploads a bundle"): both are true, on the two branches of this one conditional.

**So the remedy for G5 is a RETRY, plus getting off bundle mode — not a cwd change.**
`handoff-fire.sh --cloud` inheriting the caller's worktree is fine and needs no change; what it
needs is to not treat the first `Bundle upload failed` as terminal. Measured this session, a
retry-until-created loop reached a session on attempt 2 of 4 twice over.

⚠️ **Not established, and named rather than smoothed over:** whether this repo's App preflight fails
*deterministically* (App not installed) or *transiently* is not separated here. The two produce the
same bundle fallback, and the deterministic instrument for it — calling the preflight endpoint
directly — needs the account's OAuth token out of the Keychain, which this session was correctly
blocked from reading. `gh` cannot answer it either (listing App installations needs an
App-authorised token; ours returns 403).

**The size positive control was DESIGNED AND NOT RUN, and the reason is methodological.** A
one-commit repo whose bundle is kilobytes is the arm that would make size *causal* rather than
merely *implicated*. A fresh directory stops on Claude Code's folder-trust prompt and never reaches
a create — costing nothing, yielding nothing. Both ways past it disqualify it as a control:
`--dangerously-skip-permissions` makes the arm differ from `wt`/`main` in something other than
bundle size, and pre-seeding `hasTrustDialogAccepted` is a read-modify-write of an account
`.claude.json` a live session may be writing. It is `--arms wt,main,small`, opt-in, behind one
interactive trust of the control directory. Until it runs, "size is the cause" is a **mechanism plus
a refuted alternative**, not a demonstrated dose-response.

#### S5.4 · The replacement calibration control — THERE IS NONE, and the ceiling is unmeasurable by this instrument

**VERDICT, stated as the brief demanded rather than papered over: no free known-refusal is reachable
today, so `scripts/cloud-ceiling-probe.sh` cannot validate its quota classifier, and NO CEILING from
it is publishable. The lower bound (≥2, §S5.2) stands, because it counts successes and never
consults the classifier at all.**

*Candidates enumerated, so this is a searched space and not an assertion:*

| Candidate known-refusal | Free? | Verdict |
|---|---|---|
| An account at 100% weekly | yes | **VOID — measured.** `next2` at 100% weekly created **four** sessions. Weekly quota does not gate cloud create. |
| An account at its 5-hour cap | no | Untested, and not free — it costs burning an account's session quota. Expected to fail the same way: the create boundary is not where session quota binds. |
| A logged-out / invalid-token account | yes | Reachable, but yields an **auth** refusal. Validates that the classifier does not OVER-match; says nothing about its quota patterns. |
| `allow_remote_sessions policy denied` | n/a | A **policy** refusal, same category as auth — and not reachable on these accounts anyway. |
| Feeding the classifier a synthetic refusal string | yes | **Vacuous.** The question is whether our patterns match *the API's real string*, and a string we invented cannot answer it (`[[control-must-replay-the-real-artifact]]`). |

🚨 **The deeper reason, which outranks "we lack a control": the instrument may be hunting an event
that does not occur.** The ramp's whole design assumes a concurrency ceiling *surfaces as a refusal
at create time*. Two measurements now say it may not: weekly quota demonstrably does not gate create,
and the vendor documents no numeric per-account concurrent-session cap. If create is not capped, then
`refused-quota` is an outcome with **no reachable instance**, the ramp can only ever exhaust its own
`--max` — which is exactly what it did — and "an unvalidated classifier" understates the problem. So
the ceiling is marked **UNMEASURABLE BY THIS INSTRUMENT**, not merely unmeasured.

**What would change that, named so this is falsifiable:** one observation, anywhere, of a cloud
*create* refused for a limit — in a log, from another account, or after the vendor introduces a cap.
That string is the missing artifact; until it exists, there is nothing to calibrate against.

✅ **What IS validatable, and it is the half that actually protects this program: SPECIFICITY, not
sensitivity.** The two error directions are not symmetric. A false `refused-quota` **publishes a
fabricated ceiling** — the exact failure this subsystem keeps having. A false `refused-other` merely
abstains and costs a re-run. We cannot prove the classifier catches a real quota refusal (no
instance exists), but we CAN prove it does not *invent* one — and §S5.3 handed us the material: a
live, reliably reproducible, non-quota refusal (`Bundle upload failed: Socket is closed after 3
attempts`) that the classifier must never call quota. That is a real positive control over a real
artifact, and it bounds the only error that can put a wrong number in this document.

**Concrete consequence for the probe:** `refused-bundle` belongs as its own outcome, ordered AHEAD of
the quota arm, exactly as `refused-harness` was placed ahead of it for the same reason — a transport
failure must never reach the quota patterns at all. Implemented in `scripts/cloud-bundle-probe.sh`
and to be adopted by `cloud-ceiling-probe.sh`.

#### S5.5 · T2 (one real round trip) and T3 (token load) — BLOCKED, on a wall that is now named

**T3 is blocked ON T2, and T2 is blocked on a session that never executes.** Recorded plainly
because a number here would be the very thing this section exists to prevent.

- **Creates now work** (§S5.3) — with a retry, on demand, from either cwd. That is new; the create
  path was the wall for the whole prior program and it is no longer the wall.
- **Execution still does not.** Across this session 6 sessions were created and declared
  (`session_01YNvu…`, `01TaP5…`, `01FBfk…`, `016CX8…`, `01UWce…`, and the round-trip fire
  `session_01XtCjjRVvZpadMH7ZfK8jsQ`), joining the 11 already on the books. `cc-cloud --check`
  reports `NOT-STARTED`/`ABANDONED`; the round-trip session was still `BOOTING — no ref yet, 12m
  into a 15m budget` when this was written, and `git ls-remote origin 'refs/heads/claude/*'` was
  empty. **Zero observable actions, now across 17 sessions.** (Stated at 12m rather than 15m
  deliberately — the budget had not expired, so this is "no ref yet", not "never".)
- ⚠️ **One instrument caveat that must not be lost:** five of this session's six probes were given
  deliberately no-op tasks ("print the repository name and stop"), so `no-ref` is what they would
  produce *even if they ran perfectly*. `no-ref` therefore does NOT discriminate "never executed"
  from "executed and had nothing to push". Only `session_01XtCjjRVvZpadMH7ZfK8jsQ` was given a task
  that MUST produce a branch, and it is the only one whose silence is evidence.
- **The likely mechanism, from §S5.3's decompilation and NOT yet confirmed:** in bundle mode the VM
  is seeded from an uploaded bundle of local HEAD, not from a GitHub clone — so it has no GitHub
  remote to push a `claude/*` branch back to, and G6's landing arm has nothing to reconcile. That
  would make "cloud work cannot return" a *consequence* of the same missing GitHub App install that
  forces bundle mode. It is a hypothesis with a mechanism, filed as such — it is not established, and
  §S5.2's own history is what happens when a plausible mechanism gets promoted early.
- **T3 (token load) is consequently NOT MEASURED, and no figure is published.** Creating a session
  and running tokens through it remain different questions; the second still has no instance.

#### S5.1 · Cloud observability — DONE (backlog `191d4d056c98`, 2026-08-07)

**→ `docs/plans/CLOUD_OBSERVABILITY.md`** (design + measurements, with the command for each so they
can be re-measured rather than believed) and `docs/research/cloud-observability-2026-08-07.md`.
Built: `bin/cc-cloud` — fire-time capture (`preflight`/`declare`) *and* the `ls-remote` observer
(`poll`/`--json`/`--table`/`--check`), one tool.

*(This line read "`bin/cc-cloud` (fire-time capture) · `bin/cc-cloud-watch` (`ls-remote` observer)"
until 2026-08-07. Both halves were wrong: the two were not a division of labour but two independent
implementations of the SAME observable set, written by two sessions of the 9-way dispatch storm on
`191d4d056c98` and landed in one commit, each doing fire-time capture AND observation. Two tools
over one observable set drift, and a caller cannot tell which is authoritative — `cc-cloud-watch`
was deleted and its two verbs with no home in `cc-cloud` (`preflight`, `list`) plus the one
behaviour it had and `cc-cloud` did not (a fire-time baseline sha, without which a declaration onto
a re-used branch name reads healthy for the whole 6h life budget) were migrated in. Backlog
`163676679912`.)*

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
transitions (low-frequency, the trail IS the audit), ~~`refs/cc/*` carries liveness (high-frequency,
must never enter history)~~ — **the liveness half lost its carrier 2026-08-08 (§S5a): a cloud VM
cannot write `refs/cc/*`. The split itself survives and is still right; only the liveness transport
is now unassigned** (candidates: a working-branch commit, or the non-git session-events surface in
`cloud-observability-2026-08-07.md` §4.6). S5a's "the claim stays local" is exactly this doc's local-proxy shape —
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

---

## S6 · The measured path from ~12 to 150 — occupancy, bursts, render (2026-08-09)

Evidence: `docs/research/session-capacity-ceiling-2026-08-09.md` (§10–§12 carry the corrections).
Every number here was measured on this box today. **S5's premise is superseded** — see S6.0.

### S6-Phase 0 · Agent Team orchestration — EXECUTION LOCUS PER WAVE

| Wave | Locus | Why | Owns (single-owner files) |
|---|---|---|---|
| **A** — idle sessions free (poller consolidation) — **CLOSED 2026-08-09, see §S6.3-MEASURED** | **S** — dispatched handoff session | Implementation wave; its audit + design + tests must not land in the lead's window. Largest lever, everything downstream is quoted against its slope. **Outcome: measured, not built** — idle sessions already cost 0.0031 vs a 0.02 target, the poller census was argv contamination, and the consolidation was declined as a 1.6%-of-budget payoff against the wake path. | **instruments only** — `scripts/occupancy-probe.sh`, `scripts/idle-slope-sweep.sh`, `tests/{occupancy-probe,idle-slope-sweep}.bats`. It did **not** touch any poller call-site, hook, or session tooling ⇒ that surface stays free for B. |
| **C** — bound toolchain ignition | **S** — dispatched handoff session | Independent subsystem (toolchain admission), disjoint from A's files ⇒ safe to run CONCURRENTLY with A. | cold-compile admission path + worker-pool cap |
| **B** — cut active occupancy (serialise hooks, cache git) | **S**, but **SERIALISED AFTER A** | B edits the same hook/session tooling A restructures. Same-hunk conflict is near-certain; worktrees do not prevent it. Single owner per shared file ⇒ B waits. | hook dispatch + git-state cache |
| **D** — gate terms | **OPERATOR** | Adds a REFUSING term to the box-wide spawn path (G2 escalation). Also needs A+B's measured slopes to set thresholds — dispatching it before them would invent numbers. | — |
| **E** — headless / render | **S**, parallel | Disjoint from A/B/C. Precondition: confirm headless retains hooks + `cc-notify`. | launch path |
| **F** — off-box create | **S**, parallel | S5's blocker, unchanged. | `cc-cloud` create |

**Lead's context budget + succession point.** The lead (this session) holds ≥50% of its window for
deciding, and absorbs only each wave's completion ping — never its implementation detail. Succession
point: once A and C report, the lead either dispatches B or recycles into it.

🚨 **Binding constraints inherited by EVERY wave** (from the 2026-08-09 capacity brief):
never register a hook, never load launchd, never run an activation — **stage it as a `c10` migration**
(`migrations/README.md`) and stop. Do not change `CC_FIRE_MAX_LOAD_PER_CORE` or any gate default as a
side effect. Anything touching spawn/fire/close tooling strands real work box-wide if wrong, so every
behavioural change needs a test **AND** a mutation check that fails when the change is neutered.

### S6.0 · The correction that reopens the local track

S5 states *"100 local sessions is arithmetically unreachable: 511 MB/session × 100 = 51.1 GB."*
**The 511 MB is `ps` RSS**, which charges the ~992 MB of shared read-only libraries once per session.
Against `vmmap` phys_footprint (corroborated by `top`'s MEM column on 4/4 processes): **216 MB fresh,
median 232 MB, mean 283 MB**. So 100 sessions ≈ **23 GB, not 51 GB**, and 150 ≈ **35 GB**.
RAM is *not* what stops the local track. S5's off-box conclusion stands on its own merits (and its
create-reliability blocker is unchanged), but its stated *reason* no longer holds.

### S6.1 · Three independent walls, each with its own term

| # | Wall | The term | Measured today | Binds at |
|---|---|---|---|---|
| 1 | **Lag / admission** | `load = mean simultaneously-runnable threads` | **1.6 threads/session** | **~12 sessions** (20 ÷ 1.6) |
| 2 | **Crash** | compressor **segment** exhaustion, ignited by spawned toolchains | waves of 372 → 736 procs, 38.9–44.7 GB | ~1–2 concurrent cold compiles |
| 3 | **Render** | WindowServer + kitty CPU per visible pane | 0.42 cores at ~17 panes = **0.025 cores/pane** | ~20 panes (0.5 cores) |

Walls 1 and 3 cause *lag*; wall 2 causes the *crash*. They are attacked separately.

🚨 **The reframe that makes 150 tractable: fork RATE is not a capacity variable — occupancy is.**
Measured cross-over: 2,376 forks/s at concurrency 4 adds **+1.6** load; 1,255 forks/s at concurrency 16
adds **+17.5**. Rate down 1.9×, load up 11×. So *"make hooks fork less"* buys nothing on its own.
**`occupancy = concurrency × duration`**, and either factor delivers the win.

### S6.2 · The design point — 150 RESIDENT, ~10 ACTIVE

150 sessions all *actively working* is not achievable and never will be on this box: inference alone
is 150 × 0.058 = **8.7 cores**, plus 3.7 cores of render, against 10. But a session **blocked on the
API contributes ~0 runnable threads**. So the target is residency, with active concurrency bounded:

```
load budget                             20   (gate ceiling, 2.0/core)
150 idle sessions × 0.02 target        = 3.0
remaining for active work              = 17
active sessions at 1.6 each            ≈ 10        ⇒  150 resident, ~10 active
```
**This is the single most important change in framing: the gate today limits RESIDENT sessions via
load; it should limit ACTIVE sessions and let residency be cheap.** Everything below serves that.

Memory budget at the design point, and it is tight — this is what forces S6.5:
```
150 sessions × 232 MB      ≈ 35 GB
macOS + render + baseline  ≈ 10 GB      (browsers CLOSED; Dia alone was 5.0 GB)
                             -------
remaining for bursts       ≈ 19 GB      vs a measured 372-proc wave ≈ 23 GB
                                        vs a measured 736-proc wave ≈ 45 GB
```
⇒ **At 150 resident there is no room for even ONE unbounded cold compile.** Burst bounding is not an
optimisation on this path, it is a precondition.

### S6.3 · Phase A — make idle sessions free  ⟵ *start here; largest lever*

An idle session must cost ~0. Today it does not: measured concurrently at 12–19 sessions were **19
`cc-reaper`, 20 `cc-await-ping`, 6 `cc-reconcile`, 37 `sleep` processes** — per-session pollers that
run whether or not the session is doing anything. That is the population that multiplies by 150.

- **Do:** consolidate per-session pollers into ONE box-wide daemon that services all sessions
  (fleet-wide reaper/reconcile/await already have single-daemon precedent in `compressor-sentinel`).
- **Target:** idle-session occupancy ≤ **0.02** runnable threads.
- **Verify (the decisive test):** launch N idle sessions, sweep N, regress load on N. **The slope
  must fall from the measured 1.6 to ≤0.1.** Slope, not absolute load — absolute drifts with ambient.

#### S6.3-MEASURED · Phase A — CLOSED 2026-08-09, target already met, premise refuted

Everything above this line is the brief as written. It was executed, and the measurement refutes it.
Evidence: `docs/research/idle-session-occupancy-2026-08-09.md`. Instruments landed:
`scripts/occupancy-probe.sh`, `scripts/idle-slope-sweep.sh` (+ suites, both with mutation checks).

**An idle resident session costs 0.0031 runnable threads against the ≤0.02 target — 6× under, with
no change made.** At 150 resident the whole fleet plus every poller is **0.46 runnable threads**
against a ceiling of 20.

| Term | Measured | Method |
|---|---|---|
| idle `claude` process | 0.00067 | Δcpu/Δwall, n=6 truly-idle sessions |
| `cc-await-ping` (15 s poll) | 0.00216 | cpu/wall over a 60 s real run |
| `lead-crash-watchdog` (30 s poll) | 0.00024 | 200-iteration timing of the loop body |
| **idle session, total** | **0.00307** | — |

🚨 **The per-session poller census in S6.3 was argv contamination.** Re-measured with a
command-position predicate: `cc-reaper` **0** (not 19), `cc-reconcile` **0** (not 6),
`cc-await-ping` **1** (not 20). Both sweepers are ONE box-wide launchd job
(`com.chrisren.cc-reaper`, `StartInterval 300`, `mkdir` mutex, skip-not-queue) with **zero** hook
call sites. The contaminating string is *in this plan and in the wave's own brief* — every session
carrying it matched itself once per pane, plus `tests/cc-reaper.bats` by pathname. This fleet's
indexed `pgrep-f-matches-agent-briefs` failure, committed against the number a wave was scoped on.
The real per-session population is **two** processes: `lead-crash-watchdog.sh` (SessionStart, no
matcher, 1:1 with sessions) and `cc-await-ping` (armed on demand; the wake floor at
`hooks/session-continue.sh:351` blocks Stop until it is, so a steady-state resident carries one).

**The 1.6 is an ACTIVE-session number, exactly as S6.2 already says** (*"a session blocked on the API
contributes ~0"*). The model decomposes: idle = **0.0031**, active ≈ 1.6 (~0.09 resident + ~1.5 fork
churn from short-lived processes). Phase A's subject was 500× below the figure quoted against it.

**Consolidation NOT built, and the reason is the trade, not the difficulty.** Payoff 0.33 runnable
threads at 150 — **1.6% of the budget**. Cost: `cc-await-ping`'s wake IS the watcher process exiting
(the only channel that re-invokes an idle model), so a box-wide daemon cannot replace the waiter,
only its polling; its `.watching` marker gates `cc-notify`'s verdict, the drain nudge, and the
Stop-blocking wake floor — stop re-stamping one key and that session can never Stop. 53 test files
reference the pair. Against the wave's own "strands real work box-wide if wrong" constraint that is
the wrong trade. *Cheap lever priced but not fired:* `cc-await-ping` at 60 s instead of 15 s is a 4×
cut, bounded above by `CC_WATCH_FRESH_S=90`; it spends peer-mail wake latency (≤15 s → ≤60 s) to buy
0.24 of 20, which is a responsiveness call, not a capacity fix.

⚠️ **The decisive test was RUN. It refutes 1.6 and cannot estimate 0.003 — and both halves matter.**
Sweep over N ∈ {0,3,6,9}, 120 s settle, 60 s measure: **load1 slope −0.141 (R² 0.383)**, mean-runnable
slope −0.438. Negative is not physical; it is ambient decay across the 13-minute run, larger than the
effect and running against it. At the *briefed* 1.6, nine sessions would have added **+14.4 load** —
8× the 1.7 ambient swing, unmissable. Load at N=9 came in **below** N=0. So the acceptance criterion
("slope ≤0.1") is satisfied on the arithmetic, but **must not be read as a win**: nothing was changed,
and it passes because the quantity was never large. Per-process Δcpu/Δwall carries the point estimate
instead — another session's `git` cannot enter a `claude` process's own CPU counter.

🚨 **The wall at 150 resident is PTYS, not load — and no wave in S6 owns it.** Measured this session:
**33 ptys at 15 `claude` processes = 2.2/session** ⇒ **330 of `kern.tty.ptmx_max` 511** at 150, before
any teaming burst, against load at 0.46 of 20 (43× headroom). Pollers hold no ptys; panes do, so
Phase A could never have touched it. C-CAP-2 (pty-less substrate) is the named candidate.

### S6.4 · Phase B — cut active-session occupancy

- **Serialise** each session's hooks (one at a time) rather than shrinking their count — per S6.1 the
  count is not the variable.
- **Shorten** what holds a slot: a hook's `git rev-parse` costs **17.95 ms** against **2.20 ms** for
  bare `bash -c :` — an **8.2× occupancy saving** on every git-bearing hook. Cache branch/status
  per turn instead of re-shelling per hook.
- **Target:** active-session occupancy 1.6 → ~0.5, which raises the active ceiling from ~10 to ~30.

### S6.5 · Phase C — bound toolchain ignition  ⟵ *this is the crash fix, and it is non-optional*

Ignition in all six panics is a dev-toolchain burst (`next dev` cold compile / `next-server` postcss
worker pools), never session count. Per S6.2 the burst budget at 150 resident is ~19 GB.

- **Do:** admission-serialise cold compiles to **1 concurrent**, and cap the worker pool
  (`workerThreads` remedy already identified). The `compressor-sentinel` SIGSTOP actuator (armed
  2026-08-09, 40 MB floor, `ACT_CAP=400`) is the **backstop, not the fix** — it acts only after
  segments climb, and it has ~10 s of exposure on a >400-member wave.
- **Not the lever:** raising `ACT_CAP`. Its 40 procs/s stop capacity already beats the worst measured
  3.9 procs/s storm growth by ~10×, and it excludes `claude` by construction, so it can never bind on
  session count.
- **Verify:** run a deliberate cold compile at design-point residency; `seg_pct` must stay < 15%.

### S6.6 · Phase D — fix what the gate measures

Two term changes, both evidence-backed, both **operator's call** (they gate spawn box-wide):

1. **Admit on ACTIVE concurrency, not load.** Load conflates residency with activity, which is exactly
   what S6.2 needs to separate.
2. **Replace the memory term.** The current one — `free+speculative+inactive+purgeable ≥ 4 GB` — has
   fired **0 times in 127 refusals** and *cannot* bind: it counts dirty-anonymous inactive pages as
   free. Measured side by side on the quiet box: gate term **40.55 GB → ADMIT**, segment term
   **0.00%**; at the panic those were **29.79 GB → still ADMIT** against segments at **100%**.
   The replacement needs no inventing — `compressor-sentinel.sh` already computes it every 10 s
   (`occupied_pages ÷ 4` + `swap_used ÷ 65536`, exact). ⚠️ It is a **burst guard, not a capacity
   term** — a steady-state session compresses nothing — so **both** terms are needed.

### S6.7 · Phase E — render, and Phase F — the remainder

- **E:** at 0.025 cores/pane, 150 visible panes is 3.7 cores. Keep **≤20 visible kitty panes**; the
  rest run headless/detached (render cost 0). Confirm the headless launch path retains hooks and
  `cc-notify` before committing to it.
- **F:** whatever will not fit locally goes off-box per S5 — still blocked on the **create step**
  (17 declared sessions, zero ever executed, one head on `origin`).

### S6.8 · What is NOT achievable, stated plainly

- **150 simultaneously-ACTIVE local sessions.** 8.7 cores of inference + 3.7 of render > 10. Not a
  tuning problem.
- **150 resident with unbounded toolchain bursts.** The RAM arithmetic in S6.2 forecloses it.
- **Any gain from the Spotlight/worktree levers.** `~/Development/.worktrees` returns **0** indexed
  files (dot-directories are never indexed) — already free. A full `find` over all 382 worktrees
  moves load **+4.5%**. Disk and FS are not capacity variables on this box.
- **`taskpolicy`/QoS throttling** — already rejected in §2 and re-confirmed: `-c background` is an
  84–89× tax.

### S6.9 · Sequencing

**A → B → C** are independent of S0–S5 and can start immediately; **A first**, because it is the only
one that changes the *residency* slope and every later number is quoted against it. **C must land
before residency is actually pushed past ~30**, or the first cold compile takes the box down. **D**
follows A and B (it needs their measured slopes to set thresholds). **E** and **F** are parallel.

**REVISED 2026-08-09, after A ran** (§S6.3-MEASURED). A is **CLOSED — measured, not built**: the
residency slope is **~0.003/session, not 1.6**, so A never had a slope to change and B is no longer
waiting on one. Re-order accordingly:

- **B is now the only load lever and should start immediately** — it is unblocked, since the reason
  it was serialised after A (shared hook/session tooling) is moot once A ships no behavioural change.
  A's files are instruments only (`scripts/occupancy-probe.sh`, `scripts/idle-slope-sweep.sh` and
  their suites); **A touched no hook, no poller, and no session tooling**, so B inherits a clean tree
  and owns that surface outright.
- **C is unchanged and is now the highest-value wave**, since burst survival — not residency — is
  what the arithmetic says binds.
- **D's thresholds**: A's half is measured and negligible. D still needs B's active-session number.
- **A new term belongs on this list and is owned by nobody: ptys.** 2.2/session measured ⇒ 330 of
  511 at 150 resident, while load sits at 0.46 of 20. It binds ~43× sooner than the term this whole
  section is written in.
