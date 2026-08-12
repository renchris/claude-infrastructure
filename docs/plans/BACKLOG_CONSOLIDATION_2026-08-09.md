---
status: open
---

# Backlog consolidation — 460 items → 6 master efforts

## Phase 0 — Agent Team Orchestration

**EXECUTION LOCUS PER WAVE: `S` (dispatched handoff session) for every master item — the default.**
Each of M1–M6 is a multi-hour implementation effort, so its detail must land in its OWN context, not
in the lead's. One `/handoff` session per master, fired and awaited:

```
scripts/handoff-fire.sh --prompt-file /tmp/fire-<master-id>.txt \
    --worktree <branch> --notify-back "${ITERM_SESSION_ID##*:}" --account auto --split-right
```

The triage wave that PRODUCED this document ran at locus `T`-equivalent (10 read-only research
subagents, no `name:`) — correct there, because each returned a small report and the synthesis had to
happen against all ten at once. That does not generalise to the implementation waves below.

| wave | master | locus | worktree | may run concurrently with |
|---|---|---|---|---|
| 1 | M3 fleet footprint `66ef300dd0b4` | S | `fix/fleet-footprint` | nothing — it changes spawn/teardown under everything else |
| 2 | M1 convergence deadlock `3b22efbc2340` | S | `fix/convergence-deadlock` | M6 |
| 3 | M2 fire gate `1b00d62958a6` | S | `feat/dispatch-fire-gate` | M4, M5 |
| 3 | M4 stranded work `0328e7cc5742` | S | *(lands existing branches; no new worktree)* | M2, M5 |
| 3 | M5 enforcing store `70cc9f44040f` | S | `fix/enforcing-store` | M2, M4 |
| any | M6 account facts `b22e519e06cb` | S | `fix/account-derivation` | anything |

**Ordering constraint, not preference.** M3 first because a kernel panic destroys every live session
at once — 4 in 7 days. M1 before M2 because a gate that admits correctly into a pipeline that cannot
converge still changes nothing; that is the whole lesson of this document.

**Lead's context budget + succession point.** The lead holds ≥50% of its window for deciding, never
for implementation detail. Succession point: after each wave's completion ping, before reading any
worker's diff — recycle if everything of value is on disk.

**Measured 2026-08-09/10 against `origin/main` @ `51bdb524`.** Trunk advanced to `83fe0b84` during
this pass — the fleet is active, so **re-derive any figure below with its falsifier rather than
quoting it** (repo memory: `published-figure-decays-with-its-source`, where a p95 had a 36h
half-life). Method: all 460 open items partitioned
into 16 disjoint clusters (conservation-checked), triaged by a 10-agent read-only wave against
today's tree, every item carrying exactly one verdict, synthesized here. Verdict coverage is
machine-verified: `verify.py` fails if any item is unadjudicated.

**Filed as live backlog rows** (`source=backlog-consolidation-2026-08-09`), each under its own
condition slug so the condition lease admits one worker per effort:

| master | id | condition |
|---|---|---|
| M3 fleet footprint | `66ef300dd0b4` | `master-fleet-footprint` |
| M1 convergence deadlock | `3b22efbc2340` | `master-convergence-deadlock` |
| M2 fire gate | `1b00d62958a6` | `master-fire-gate` |
| M4 stranded work | `0328e7cc5742` | `master-stranded-work` |
| M5 enforcing store | `70cc9f44040f` | `master-enforcing-store` |
| M6 account facts | `b22e519e06cb` | `master-account-facts` |

Working artifacts (triage reports, citation graph, prune list) are staged at
`/tmp/backlog-consolidation/` — **ephemeral**; the durable record is this file.

## Why the backlog grew — the loop, with a measurement at every step

This is the finding that reorganises everything else. The pile is not badly ordered; it is being
**fed** by an unfixed generator sitting downstream of a deployer that structurally cannot run.

```
  ①  peers SIGKILL each other's gates (unscoped pkill -f bats)
        └─► false REDs                                    [root cause a0718a5d78b3 — FIXES LANDED]
  ②  green rate 3/124 stamps = 2.4%
  ③  last GREEN stamp is 252 commits back; deploy-live SCAN_N=200
        └─► deployer REFUSES: "no GREEN stamp among the newest 200 commits"
  ④  live ~/.claude layer never converges → landed fixes do not run
  ⑤  same defects reproduce → postland mints ONE ITEM PER SHA          [generator 07e6e3888e9c]
  ⑥  items dispatch workers → workers contend ──────────────► back to ①
```

Independently re-measured by the lead, not taken on report:

| fact | value | how |
|---|---|---|
| last-green → trunk distance | **252 commits** | `git rev-list --count 71e96bcb..origin/main` |
| deployer scan window | **200 commits** | `deploy-live.sh:76` `SCAN_N` |
| shared checkout behind trunk | **19 commits** | `git rev-list --count HEAD..origin/main` |
| generator still minting | **8 rows on 2026-08-09**, 45 since 07-30 | `source=="postland-verify"` by `lastTs` |
| `deploy-parity.bats` duplicate rows | **18** | title cluster after sha-strip |
| unlanded patches stranded | **114 across 34 branches** | `git cherry origin/main <branch>` per worktree |
| worktree directories | **553** (425 registered in claude-infrastructure) | `git worktree list` + `ls ~/Development/.worktrees` |

⚠️ **Two different lag numbers, both real, do not conflate them.** The land/gate agent wrote "252
commits are landed on trunk and not running." The *staleness* of already-symlinked files is **19**
(the checkout's own distance from trunk, since `~/.claude/{bin,scripts,hooks}` are per-file symlinks
into it). The **252** is the *green-stamp* distance, which is what jams the deployer. Only the second
is a deadlock.

## Triage result

| | count | share |
|---|---|---|
| PRUNE — dead, fixed, superseded | 96 | 21% |
| MERGE — absorbed by a canonical sibling | 34 | 7% |
| UPDATE — work live, stated facts stale | 67 | 15% |
| KEEP — premise verified true today | 186 | 40% |
| *(reso slice outstanding)* | 77 | 17% |

**130 of 383 adjudicated items (34%) can be closed without doing any work.** The land/gate cluster
was 59% dead on its own — it holds the duplicate-mint wreckage.

---

# WAVE OUTCOMES — 2026-08-10 (INTEGRATE-only; the proposals below are preserved unchanged)

All six masters were fired as dispatched sessions. What follows is what they FOUND, recorded here
because three of the findings refute reasoning in the sections beneath this one — and the refuted
version is left standing on purpose, so the correction is legible rather than invisible.

| master | state | landed | the finding that mattered |
|---|---|---|---|
| M3 fleet footprint | **done** | `77d33bdc` | spawn budget + depth cap at the actuator; janitor verified BY EFFECT (worktrees 558→252, 319 removed). Its real defect was **three consecutive SILENT failures** — exit 0, no row — while the population tripled. |
| M6 account facts | **done** | `3be72af4` | one derivation per fact + a 13/13 test that reds if a consumer re-derives; auth recorder scheduled with a durable store; machine floor measured at 30 sustained over 11,440 samples. |
| M1 convergence | **done** | `7693854c` | **the root cause was NOT `SCAN_N`.** See below — this refutes §"Why the backlog grew". |
| M2 fire gate | claimed | — | in flight |
| M4 stranded work | running | — | in flight |
| M5 enforcing store | running | — | in flight |

## M1's finding refutes this document's own diagnosis, and that is the most useful thing in it

§"Why the backlog grew" (below) attributes the frozen live layer to the green stamp falling outside
`deploy-live.sh:76`'s 200-commit scan window, and tracks the distance widening 252→262→283→297→323→350.
**Every one of those measurements was real and none of them was the cause.**

`merge-base --is-ancestor X X` is TRUE. So the T1 check matched live HEAD against *itself*, set
`TARGET=HEAD`, and the `if [ -z "$TARGET" ]` wrapper then skipped T1H **and** T2 entirely — the lag
budget was **structurally unreachable**. One green stamp froze the layer where *zero* greens did not,
at exit 0 and silent under `--auto`, which is worse than the loud refusal three peers hit. Fixed by
requiring a target strictly above the layer; green-on-HEAD became a benign exit placed *after* the
budget arms. Mutation-controlled: restoring the reflexive match reds G1/G4/G5 while control G2 stays
green. 74/74 deploy-live, 265 green across six suites.

**The generalisable lesson, and it recurred four times in one session:** a falsifier that measures a
*symptom* passes and fails for the wrong reasons. The green-stamp distance was a real number, moving
in the real direction, downstream of the actual defect — and no amount of watching it move would ever
have found the reflexive ancestor match.

## What the lead built while the wave ran — the by-default machinery, now WIRED

The frozen DoD's parts 4 and 5 belonged to no master. They are landed **and called**:

| landed | what |
|---|---|
| `a7bf7068` | `cc-backlog add --falsifier '<cmd>'` + `cc-premise` re-runs it at CLAIM time. exit 0 = condition GONE = the only direction that refuses; non-zero = still live, advisory, with the probe's output carried into the contract; unaskable = **fails OPEN**. First real refusal: item `bc0f2abe078b`, `verdict=falsified`, exit 3. |
| `62592045` | `backlog-ratchet.sh` — falsifier coverage (leading) and age-at-close **median AND p75** (lagging). The p75 is not decoration: median 0.1d vs p75 2.2d / max 19.7d, so a median-only report reads "healthy" for exactly the population it exists to catch. |
| `596b39a7` | `backlog-consolidation-trigger.sh` — detects the duplicate shape. Exact-match finds nothing *by construction* (ids hash project+title+source), so it normalises shas/digits out. Its positive control lives in the fixture because the live store has zero clusters post-prune — a detector verified only against a clean store is indistinguishable from a broken one. |
| `8371b206` | **the caller.** All three landed INERT — nothing invoked them, which is the exact failure this document describes, committed by the change documenting it. Wired into `autonomy-sweep.sh` *above* its nothing-new early exit, because rot is precisely the condition that produces no pages while it accumulates. |
| `b2d58539` | a trunk red that was not ours: `mirror-kpmg-deck.sh` derived its root from an unresolved `$0`, taking `self-path-lint --selftest` red and blocking any land in its scope. Through the live layer that resolves to `~/.claude`, so it would have mirrored into the wrong tree — never failing, only on the deployed path. |

## Two criteria in the driving goal were themselves wrong, and were corrected against evidence

Recorded because the corrections are the same defect class as the work: **(2)** tested the
green-stamp distance, a symptom M1 disproved — replaced by *live lag 0 AND the converger advances*,
since `deploy-live` rc 0 also means "nothing to do". **(3)** counted `ls ~/Development/.worktrees`
(259) which spans THREE repos; 137 are reso/doc_classifier and **80 of those hold unlanded commits**,
so "under 100" was unreachable without destroying other repos' work. Replaced by the owned
population against its own janitor ceiling: **116/150, `OK bounded and fresh`**.

---

# The master items

Ordered by the only ranking that does not decay: what each one unblocks, measured. Each carries a
**falsifier** — one command whose exit 0 means the whole effort is unnecessary. That is what lets it
re-validate itself at fire time weeks from now, instead of being trusted because it was written down.

## M1 — Break the convergence deadlock so landed work actually runs

**Absorbs:** the land/gate KEEP set + `M-landgate-1`, `M-testcorpus-1`, `07e6e3888e9c` (generator),
`M-landgate-2`. **Retires 57 items in the land/gate cluster alone.**

**Why one effort:** ③④⑤ above are one causal chain. Fixing the generator without fixing the deployer
just slows the minting; fixing the deployer without fixing the generator leaves 18-row clusters
arriving forever. The suite must give a verdict about the *tree*, not about its own harness, or
neither holds.

**Order:** (1) make a green stamp reachable at trunk velocity — either widen the scan window or make
`postland-verify` certify a tree rather than a commit; (2) re-key backlog ids on
`(project, suite, source)` so re-reds fold into ONE item and the sha becomes a field; (3) drain the
existing 18-row cluster to its canonical id.

**Falsifier:** `bash scripts/deploy-live.sh --dry-run` exits 0 with a green stamp inside the window.

## M2 — Nothing fires until it is provably current, unclaimed, and lands in a fresh tree

**Absorbs:** the dispatch KEEP set (43 items) + `M-dispatch-1`, `M-testcorpus-3`, `M-session-1`.

**Why one effort:** this is the gate you asked for, and it is one predicate at one chokepoint —
`cc-premise`, called from `cc-backlog claim`. Freshness, clustering and ranking are three reads at
the same call site; split across three efforts they drift.

**Order:** (1) `--falsifier` field on `cc-backlog add`, emitted for free by the four machine
generators (162 of 460 items); (2) cluster-as-dispatch-unit in the decision phase; (3) derived rank
from the citation graph (142 edges, already computable); (4) worktree base-freshness guard.

**Falsifier:** `cc-premise check <any stale id>` returns a freshness verdict derived from a re-run
falsifier, not from filing-time prose.

### M2 — LANDED 2026-08-10 (`a7bf7068` · `ae5ff79d` · `8c67b17c`)

Falsifier PASSES: `cc-premise check bc0f2abe078b` → `verdict=falsified`, rc 3, from a command re-run
against today's tree. All four ordered arms are in, plus the plan-open title decay (`82a6c1894384`).

| # | Arm | Where | Landed |
|---|---|---|---|
| 1 | `--falsifier` at write, re-run at claim | `cc-backlog add`, `cc-premise` | `a7bf7068` |
| 1b | DERIVED falsifier for `source=="plan-open"` | `cc-premise` | `8c67b17c` |
| 2 | cluster-as-dispatch-unit | `cc-dispatch` decision pass | `ae5ff79d` |
| 3 | derived rank | `cc-dispatch` `order_dispatchable` | `ae5ff79d` |
| 4 | worktree base-freshness | `cc-dispatch` `warm_worktree` + the pre-existing-dir path | `ae5ff79d` |
| — | plan-open TITLE re-derivation (`82a6c1894384`) | `cc-premise contract` | `8c67b17c` |

**Re-measured at start, and three of the plan's numbers had moved** — record them, because the
design was argued from the old ones:

- The store is **1584 items / 259 open / 110 blocked**, not 460. Priority and severity fields: still
  **0**, so the FIFO diagnosis holds exactly.
- **Clustering saves 3 admissions today, not 17.** The 18-row `deploy-parity` pile that motivates
  the design is `blocked`, and blocked items were already filtered at dispatch step 1. One
  multi-member cluster survives in the open set (4 rows, the MEMORY.md-index condition). The arm is
  a standing guard against a pile re-forming, not a fix for a pile now in the queue.
- **In-degree must be counted over the WHOLE fold**, not the open set: open-vs-open yields 20 edges
  over 16 items where the full fold yields **101 edges over 68 of 259** — a 5x collapse, because a
  citation is nearly always written INTO a `done` or `blocked` record. The narrower version would
  have looked like a working signal.

**Rank is lexicographic, not weighted** — thrash > land-rail > in-degree > recurrence > oldest ts.
Coefficients nobody can defend are indistinguishable from arbitrary ones; a strict precedence is
arguable one clause at a time. Effect on the live queue: **249 of 259 items change position**, the
largest single move being 178 places.

**Two corrections the cluster key cost, both kept as comments because both are the rule:**
`[0-9a-f]{7,40}` also matches "defaced" and "cabbage", so a hex run must carry a digit; and keying
on the normalised title unconditionally made every UNTITLED row share one key and collapse into one
cluster (8 existing v2 assertions went red, correctly — the absence of a discriminator is not
evidence of sameness). An inferred cluster now needs three surviving alphabetic tokens AND two
distinct raw titles: the inference is only licensed when a MEASUREMENT is what split the rows, which
byte-identical titles disprove. A declared `--condition` bypasses that bar.

**Freshness had two holes, not one.** A reused `wt-<id>` branch was checked out at its old tip with
the base never consulted, so the `fetch` above it bought nothing; and a pre-existing worktree
directory short-circuited provisioning entirely, so `warm_worktree`'s guard could not see it by
construction. Both now read three states and only a PROVEN-stale tree refuses. A stale branch
carrying nothing is fast-forwarded; one carrying commits is refused and the item reopened — never
rebased or deleted, because an unattended dispatcher must not destroy work it did not create.

**A latent defect in `a7bf7068` surfaced and is fixed:** `cmd_contract` gated on `verdict=="clear"`,
so a STILL-LIVE stored falsifier's output was dropped from the worker's brief — the one channel this
file's header calls the enforcing store — although `run_falsifier`'s docstring promises it rides
there. The gate is now `lines`. The same read restored `falsified` to the sweep report, where it was
in `BLOCKING` but had no bucket and so could not be counted.

**Not taken, filed instead:** `--falsifier` emission from `postland-verify` and `deploy-live`
(`d0a1bb8717cf`). Both generators live in `scripts/postland-verify.sh` / `scripts/deploy-live.sh`,
owned by the concurrently-running M1 (`3b22efbc2340`). The `needs` generator (107 rows) has no
machine oracle at all — its `--run` command PERFORMS the operator step, so running it as a probe
would execute the thing it was meant to test.

**Verification.** 24 new tests (12 `cc-dispatch-firegate.bats`, each paired against the pre-M2
artifact recovered by `git archive` from `a7bf7068`; 12 `cc-premise-plan-open.bats`, mutation-checked
— the derived arm inert reds 3, the snapshot inert reds 2). 156 pre-existing tests still green
across 7 dispatch suites and 2 premise suites; in-script selftest 168/0. Every arm has a kill switch
(`CC_DISPATCH_RANK` / `_CLUSTER` / `_WT_FRESH`, `CC_PREMISE_PLAN_SNAPSHOT`) and fails open to the
incumbent behaviour.

### M2 follow-on — EMISSION: the generators now feed the mechanism (`087d4198c594`, 2026-08-11)

`a7bf7068` built the re-run and nothing fed it. Six days later
`cc-backlog list --all --json | jq '[.[]|select(.falsifier)]|length'` still read **0** over 1670
items, and all 84 `premise refuted` rows in the IDL were the older declared-obsolescence path — an
item explicitly retracted by another item, never a probe re-run. The field existed, the caller
existed, the tests passed, and the coverage was zero because emission was left to a later pass.

**The invisible half, and it is the finding.** The zero was not only under-emission. `falsifier` was
never added to `cc-backlog`'s `list --json` **whitelist fold**, so the canonical projection every
consumer reads — including the item's own success check above — **dropped the field on the way out.**
cc-premise reads the RAW records, which is why its re-run always worked and why nothing noticed.
A field a producer writes and the canonical projection silently drops cannot be told apart from a
field no producer writes. Both halves had to be fixed for either to be measurable. The empty case is
`del(.falsifier)` rather than `""`, because **jq treats the empty string as truthy** — a ""-carrying
key would have made the coverage metric read 100% the moment the field became visible.

| Generator | Emits | Probe, and its ONE success state |
|---|---|---|
| `cc-discover` C2 `plan-open` | always | `plan-phase-scan.sh <plan> --falsify` — 0 ⇔ the plan holds no work to advance (terminal frontmatter, **or** zero not-DONE sections above level 1) |
| `postland-verify.sh` × 3 sites | AUTO-REVERT INERT · AUTO-REVERT `<outcome>` · HUNG | `postland-verify.sh --falsify-red <suite> <sha>` — 0 ⇔ a full-corpus green CONTAINS that commit **and** its span covered that suite |
| `deploy-live.sh` × 2 sites | HOST CUT · HOST RED (single-suite sets only) | `deploy-live.sh --falsify-host <suite>` — 0 ⇔ the live layer no longer runs that suite at all |
| `cc-backlog needs` | **nothing, by design** | pass-through `--falsifier` for a caller that has a real check; an operator step has no machine oracle and `--run` PERFORMS the step |

**Four places the obvious probe was refused, each for a measured reason** — this is the item's real
content, since every one of them would have shipped an exit 0 with two meanings:

- **`post-land RED:` gets NO stored probe.** That population already has a DERIVED arm in cc-premise
  computing the same last-green predicate, and cc-premise's composition rule is that a stored probe
  OUTRANKS a derived one. Storing an equal probe there shadows a tested arm and buys a second
  implementation to keep in sync. The three sites with no derived arm are where a probe is the
  difference between a re-run and no question at all.
- **Neither postland nor deploy-live RE-RUNS the suite.** cc-premise bounds a probe at 20s; one
  corpus suite runs ~50 min and a host suite is bounded at 3600s. A probe honest enough to hold one
  would hold a claim hostage; one that fits is a permanent non-verdict wearing a measurement's
  clothes.
- **deploy-live does not read `HOST_CUTS` either**, though it looks like postland's `last-green`.
  That file records only NON-verdicts and is rebuilt per tick, so "no row" is reachable from "it
  passed", "no deploy has run since" and "pruned to nothing" — and the middle one is a false
  retraction. The narrow question it CAN answer is the one it asks. There is no host-green ledger;
  if one is ever written, that is the better probe.
- **A multi-suite HOST RED set gets nothing.** The item's premise is about the SET; answering it
  with evidence about one member is the same defect wearing a helpful face.

**Two would-be silent retractions, caught by writing the state table first.** `POSTLAND_VERIFY=off`
exits 0, and under the falsifier contract exit 0 MEANS "premise gone" — beneath that arm, one env
var would have retracted every item postland-verify ever filed, so `--falsify-red` dispatches ABOVE
the kill switch. And an ABSENT host manifest is the EMPTY set by the partition contract, which is
safe for the VERIFIER and catastrophic here (every host suite would read as "no longer run"), so
`--falsify-host` reports "could not ask" on it. The two consumers part company on that emptiness
deliberately.

**The plan-open probe reads the frontmatter FIRST**, which is what makes it safe to store at all: an
emitted probe shadows `run_derived_plan_falsifier`, so a probe testing only remaining sections would
have silently REMOVED a retraction that already worked. Clause (a) makes it a strict superset;
clause (b) — re-deriving from the plan's REMAINING sections — is what `82a6c1894384` asked for, and
it dissolves the "advance README hero banner" class of item that every other signal passes.

**Verification.** `tests/falsifier-emission.bats`, 14/14. §2 is the DoD's third clause implemented as
a state matrix: each probe is driven through its full reachable state space, every state is labelled
premise-FALSE / premise-TRUE / COULD-NOT-ASK, and `assert_state` pins **exit 0 to premise-FALSE
alone** — so a probe that ever reaches 0 from a still-live or unanswerable state fails loudly rather
than defaulting into the success arm.

**Two defects the convergence window itself exposed, both landed** — and both are the same shape as
the emission bug: a mechanism that is present, wired, and silently answering the wrong question.

- **A stale deployed scanner could forge a retraction** (`93ae4c40`). `plan-phase-scan.sh` takes its
  FORMAT as a second positional with a silent default, so a copy predating `--falsify` does not
  reject the flag — it prints a section dump and **exits 0**, which the falsifier contract reads as
  "premise gone, refuse the claim". cc-discover and the scanner are per-file symlinks advanced by ONE
  fast-forward and so cannot skew in the steady state; a session running the NEW cc-discover from a
  worktree while `~/.claude` has not converged CAN, and it would mint plan-open items that retract
  themselves on first read. `--falsify` now prints `FALSIFIED` and the emitted probe tests that WORD,
  so an older binary answers "still live" — the safe direction. `--falsify-red` and `--falsify-host`
  never had the hole: their scripts dispatch on a closed verb set, and an unknown verb exits non-zero.
- **The refusal row named the verdict and never the signal** (`94b054d1`). `verdict=premise-refuted`
  is written both for a probe RE-RUN that exited 0 (a measurement against today's tree) and for
  another item DECLARING this one obsolete (filing-time prose). Measured on the live ledger: **51
  such rows, not one saying which.** So the re-run mechanism was unobservable from outside no matter
  how often it fired — the same defect as an unread premise, one layer up. `claim_excerpt` now
  appends the contract's own headline marker verbatim (`-oE`, never paraphrased); an absent marker
  means an absent clause, because a row that cannot name its cause must say nothing rather than
  assert the commonest one.

**Measured after landing.** Coverage went **0 → 7** on the live store, and the jump is only partly
new emission: five of those seven items ALREADY carried probes in the raw records and were invisible
because the fold dropped the field. A live `cc-backlog claim` on one was refused with
`verdict=premise-refuted` citing `FALSIFIER PASSED — it exited 0 just now, against today's tree`, and
a freshly minted `plan-open` item carrying the emitted probe re-ran it to a STILL-LIVE verdict with
today's 14-of-16 not-DONE sections in place of its filing-day title.

**Filed, not done:** the 430 pre-existing `plan-open` items (9 of them open) can never gain a probe —
`cc-backlog add` is idempotent on project+title+source, so a re-add of an existing key returns the id
and writes nothing. Backfilling needs a verb that appends a falsifier to an EXISTING item, and the
status fold reads an unknown event as `open`, so a naive `event:"falsifier"` record would reopen done
work. Out of scope here (this item is emission at ADD time); filed as its own row.

## M3 — The fleet bounds its own footprint, so the box stops panicking

**Absorbs:** `M-panes-1`, `M-panes-2`, `M-tail-1`, `M-memhooks-C3`, the immortal-worktree half of
`M-tail-2`. **Highest urgency of any item here:** 4 kernel watchdog panics in a week, most recent
2026-08-09. A panic destroys every live session at once — it outranks everything by blast radius.

**Why one effort:** a pane born unbounded, a pane that cannot self-close, and a worktree nothing
retires are the same missing invariant — no component owns its own teardown. 553 worktree
directories and a spawn path that once fanned to 224 sessions are the two ends of it.

**Falsifier:** a spawn-depth cap is enforced at the actuator AND `ls ~/Development/.worktrees | wc -l`
is bounded by a reaper that runs.

## M4 — Recover the 114 stranded patches, and make stranding impossible

**Absorbs:** `M-session-1`'s sweep half, the doc_classifier landing-rail item (`M-docclf-1` — 10 days
of finished gate-green work with no agent-executable rail).

**Why one effort:** work that is done and unlanded is pure loss, and it is the *cheapest* value in
this whole document — it needs landing, not building. 114 patches across 34 branches, top holders
`deskless` (17) and `fix/accounts-eval-bin-resolver` (9).

**Falsifier:** the per-worktree `git cherry origin/main` sum is 0.

## M5 — A conclusion reaches the thing it governs

**Absorbs:** `M-memhooks-C1`, `M-memhooks-C2`, `M-testcorpus-2`, `M-session-2`.

**Why one effort:** a hook that never registered, a MEMORY.md truncated past the loader cap
(26382 B vs 24985 B, newest 4 entries invisible), and a message that never wakes a session are one
failure — an advisory store with no path to the enforcing one.

**Falsifier:** MEMORY.md under the cap AND every staged hook registration present in live
`settings.json`.

## M6 — Accounts and runtime facts get one derivation their consumers agree on

**Absorbs:** `M-accounts-1/2/3`. Lowest urgency: all four accounts measured healthy today, no login
cliff inside 20 days. Safe to run unattended, no interaction with anything above.

**Falsifier:** `claude-accounts --readout` and every consumer derive identical values from
`accounts.json`.

---

## Not master items — the operator pile

`M-panes-3` (4 calls no gate can make), `M-session-3` (3 items no agent can drive), `M-tail-3` (9
operator-gated dead ends). These are **filed**, never fired: they need a credential, a `launchctl`
action, or a value judgment. They belong in the `👤` rendered block, not in a dispatch wave.

## Landmine

`docs/ground-up-payloads/LOCUS-GAP-BRIEF-2026-08-08.md` is **untracked** — no history, absent from
`origin/main`, present only in the shared checkout's working tree. An item depends on it. The next
`git clean` destroys it.

## Firing order

M3 → M1 → M2 → M4 → M5 → M6. M3 first because a panic costs every live session; M1 before M2 because
a gate that admits correctly into a pipeline that cannot converge still changes nothing.

## CURRENCY (2026-08-11) — concurrency was fixed; what the dispatcher fires was still triaged against yesterday's tree

**The gap, and why it could not close itself.** `a7bf7068` added `--falsifier` and made `cc-premise`
re-run it at claim; `fe6ebd0f` / `e20fd010` / `94b054d1` made the four generators emit one at add
time and fixed the reader (the field was missing from `cc-backlog list --json`'s whitelist fold, so
five items already carrying probes were invisible to every count). Emission was fixed **going
forward**. The ~450 rows already in the store were not merely un-backfilled — they were
**unreachable**: `cmd_add` resolves the id, hits `has_id`, and returns rc 0 *before* it writes
anything, so `add --falsifier` aimed at an existing row is a silent, successful no-op. There was no
writer that could reach them. Measured at the start of the pass: **461 open, 6 with a probe, 1.3%**.

**What landed.** `cc-backlog falsify <id> --probe` (`3206c955`) — an event-agnostic `event:"falsify"`
record, shaped so it lands in the CARRY-FORWARD arm of every existing fold rather than in someone's
`*)` default. Plus `signal=<verdict>` on the claim-time refusal line, because `cc-dispatch` builds
its IDL row from `claim_excerpt` (head -1, 200 chars) and every refusal therefore read identically.
Then `--clear` + a cc-premise fold fix (`60a8f0cc`) — see the false retraction below.

**The backfill.** Ten workers proposed a probe per item over the 259 open `claude-infrastructure`
rows, each executing its own probe and reporting the exit code; the lead re-ran all 156 from the
*stored string* (0 mismatches — this is what catches a probe whose unescaped `$` expands and turns
an intended non-zero into a silent exit 0). 103 items got **no probe, deliberately**: investigations,
design calls, multi-part conditions where a single token would retract the unfinished half. The
`needs` class gets none by design — no machine oracle exists, and `--run` *performs* the operator
step rather than testing it.

| | before | after |
|---|---|---|
| all open rows | 6 / 461 = **1.3%** | 154 / 474 = **32.5%** |
| dispatchable rows (`status=="open"`) | — | 153 / 300 = **51.0%** |

The denominator moved 461 → 474 during the pass: sibling sessions kept filing. Both figures are
`cc-backlog list --open --json` read through the **deployed** binary, not the worktree copy. They are
the **post-adversarial** numbers — coverage peaked at 35.7% and was cut back to 32.5% by the pass
below, which is the direction that should be trusted: a probe removed for being undiscriminating is
coverage that was never real.

**THE ADVERSARIAL PASS, and it changed the answer.** Every one of the 26 force-stored probes was
re-read against its item's title by a reviewer briefed to REFUTE and to default to refuted. **16 of
26 were refuted** — and the lead's own 5-item spot check had caught only 1 of them, because it
sampled for the failure mode already found (a downstream symptom) and missed the commoner one:

> **the grep was already true at filing.** `918e9bac60b6`'s lint landed 2026-08-06 and the item was
> filed 08-10; `80e6637dfd9e`'s `default: high` landed 8 days before its item; `8e07e87770ce`'s
> string entered the file 5 minutes before. A probe that was already passing on filing day
> discriminates **nothing** — it would have retracted the item the moment it was written. It is not
> weak coverage, it is anti-coverage: it reads as a checked item and is a guaranteed false retraction.

The second refuted class is the **half-fix**: `d40d148d0333` and `594dcaa4e976` state a two-part
condition (code branch present AND no resident idle agent process) and the probe covered only the
code half — which landed 2 minutes before filing, while rc=67 refusals continued for another day.
`d0a1bb8717cf` is the sharpest: its grep matched the *rare* generator sites while the dominant one
(`postland-verify:2249`, the "post-land RED" filer) still stores no probe at all.

All 16 were **cleared**, not rewritten — `--clear` is what made that possible, and it is why the flag
exists. 10 survive as genuine retractions.

**The re-run is live, and one IDL row proves it.** Of 75 `premise refuted` rows (4 distinct items),
**6 belong to `bc0f2abe078b`, whose refusal came from a stored probe re-run**, verified by running
`cc-premise check` on it and reading its own words — *"FALSIFIER PASSED … It exited 0 just now,
against today's tree, not at filing time"*. The other 69 rows are the old declared-obsolescence path
(`verdict=superseded`). That classification had to be re-derived by hand, item by item, because those
rows do not say which arm fired.

⚠️ **CORRECTION — the sentence that used to stand here was wrong about the tree, and the mistake is
the instructive part.** It read *"that is exactly what `signal=` removes"*, i.e. that this session
first closed the gap. It did not. **`94b054d1` had already closed it**, on trunk, before this pass
began: its `claim_excerpt` appends `· cause: <marker>` to the IDL row, discriminating **four** states
(`FALSIFIER PASSED` · `DERIVED FALSIFIER` · `DECLARES ITSELF A DUPLICATE` · `SUPERSEDED BY`) — finer
than the two-state `signal=` added here. Its commit subject even says so: *"the refusal row named the
verdict and never the signal that produced it."*

How the claim survived being written: `94b054d1` was **landed but not yet live** while the ledger was
being measured. Every row examined at 09:08 came from the pre-`94b054d1` dispatcher and genuinely
carried no cause; the first row with one appears at **13:16:06Z** (`bc0f2abe078b … · cause: FALSIFIER
PASSED`). So the observation was true of the ROWS and false of the MECHANISM — and this plan's own
brief compounded it by summarising `94b054d1` as the whitelist-fold fix alone. Reading a commit
through someone's summary instead of its diff is the repo's own standing lesson
(memory: `read-the-diff-not-the-commit-subject`), and it cost a duplicated mechanism here.

What `signal=` is actually worth, stated at its real size: it is **not harmful** (`cause` is grepped
from the whole stderr file, not from line 1, and line 1 runs ~80 of its 200-char bound, so nothing is
truncated) and it is **narrower than advertised** — a complement for the DIRECT-caller path, where a
worker or a human runs `cc-backlog claim` and no dispatcher is present to extract a cause. On the
dispatcher path it is redundant with a better mechanism. The real deliverables of this session are
`falsify` and `--clear`, not this.

**THE FALSE RETRACTION, found by using the verb on the same day it landed.** `eef88daa030a`'s item is
*"the deploy converger REFUSES every land, because no green tree descends from live HEAD"*. Its
proposed probe was `git merge-base --is-ancestor baaf0117546b HEAD` — whether **one** commit had
reached the checkout. It exits 0. But `scripts/deploy-live.sh` was run twice during this very pass
and declined **both times**, with that condition fully intact. A downstream symptom, not the
mechanism the title names — the same two-success-state shape this plan's own landmine section warns
about, in the same subsystem.

There was no correct replacement to write: the mechanism-true probe is `deploy-live.sh --dry-run`,
and that returns 0 for *"the deadlock is resolved"* **and** for *"at trunk tip, nothing to deploy"*.
So the honest end state is **no probe**, and the verb could only overwrite. Hence `--clear`, whose
real content is the *spelling*: an explicit `falsifier:""`. The two readers folded that differently
and in the worst possible direction — `cc-backlog`'s `($r.falsifier // $p.falsifier)` passes `""`
through and clears, while `cc-premise` keyed on **truthiness** and skipped the record, so
`list --json` would report no probe while cc-premise went on retracting claims with the one its owner
deleted, invisibly. cc-premise now folds on **presence**. The control asks cc-premise itself rather
than re-implementing its fold, and is RED-proven against the pre-fix code.

**Standing exclusions, named rather than silently dropped.** Five probes that shell out to `bats`
were not stored: each would take a `cc-bats` execution root on every claim, contending with the
ceiling (2 roots) that deferred this session's own test runs three times. The **10 surviving**
force-stored probes exit 0 now, so the verb refuses them by default. They are **not** closed here:
the disproof is the deliverable, and the claim-time refusal hands the next reader the probe, the run,
and the `done --evidence` line to close with. Closing them on second-hand evidence would be the
weaker move — and the adversarial pass is exactly why: 16 of 26 such "evidence" claims did not
survive a reader briefed to refute them.

**The generalisable rule this pass earned.** A falsifier must be able to distinguish the fix, not
merely agree with the world. Two screens, and only the first was built in:

1. *Does it pass now?* — the verb's own exit-0 refusal. Catches the ambiguous probe.
2. **Did it already pass on the day the item was filed?** — nothing checks this, and it is the
   commoner failure by 8 instances to 2. A probe is only coverage if it would have FAILED at filing
   time. The cheap mechanical form is `git log -S<token> --before=<item lastTs>`: a token already in
   the tree at filing cannot be the remedy's signature.

   🚨 **CORRECTED 2026-08-11 by W2, which BUILT this and found the prescribed form defective.**
   `git log --before=` filters on the **AUTHOR** date, and in this repo an author date routinely
   precedes the landing by days. Worked example, and it is the one this plan itself got wrong:
   `cb7f8e3fa` was **authored 2026-08-01** and **committed 2026-08-10 22:04**, while item
   `80e6637dfd9e` was filed **2026-08-09 21:01** — so the prescribed command sees an 08-01 date,
   concludes "already in the tree at filing", and CONVICTS a probe that in fact discriminated
   perfectly. Verified against the filing-day tree: at trunk `51bdb524` (2026-08-09) the file still
   read *"Our global default:max is WRONG-SIGNED for Opus 5"* — the fix had not landed.
   **The correct instrument reconstructs the filing-day TREE** (`git show <trunk-as-of-ts>:<path>`),
   not the commit log. A date in a log is a claim about when someone WROTE a change; only the tree
   says what the repo actually contained. `bin/cc-premise screen` does it the tree way.

**Still open, and not caused by this pass.** `deploy-live.sh` refuses to converge the live layer (no
green tree descends from live HEAD); lag was 12 commits, inside the 25-commit / 6h degrade budget,
and this diff adds no file to the live layer, so nothing here is inert. That refusal is the
anti-rollback gate working and is already filed ~20 times over (`22200e4962d0` quotes the identical
message; `b79591064f75` and `16c864bd34a8` are about the `🚀` rung being unreachable for exactly this
reason). No new duplicate was filed.

---

# READINESS (2026-08-11) — why the one-time triage keeps being re-minted, and the four things that make it stop

**The operator's ask, frozen:** *"I want the backlog to always be in a consolidated, finalized,
updated, and ready-to-fire state before any fires"* — i.e. no recurring heroic triage, ever again.

**The law is already settled and already written down in this repo.** `bin/cc-premise`'s own header
states it: *"A one-time review goes stale the moment it finishes — that decay is precisely what
produced the pile it would be reviewing. The durable form has to run at CONSUMPTION, every time."*
M2 built that for ONE property (premise currency) and it works. **This section is about the other
three, and about the instrument that was supposed to tell us they were rotting.**

## The generator, stated exactly

Readiness has four properties. Minting is continuous; three of the four are checked by a batch.

| property | question | mechanism today | consumption-time? |
|---|---|---|---|
| premise currency | is the claim still true vs today's tree? | `cc-premise` re-run at `claim` (M2) | ✅ yes |
| **probe trustworthiness** | would the probe have FAILED on filing day? | **nothing** | ❌ unbuilt |
| **venue label** | where can this run? | `bin/cc-venue`, hand-invoked | ❌ one-shot batch |
| **cluster identity** | is this one effort or five rows? | trigger DETECTS ≥5, files an item | ❌ detector, not actuator |

A batch over a growing stream must be re-run forever. That is `#152`, and it is why it will be
re-minted a third time unless the shape changes rather than the effort.

## Four measurements, taken 2026-08-11 on the live store

1. **The ratchet — the one always-on guard on backlog rot — is dead, and has never once been green.**
   `coverage_high_water` is latched at **100.0%** (recorded 07:12:51Z); live coverage is **51.5%**
   (157 of 305), so `--assert` returns **rc=1 every run**. `autonomy-sweep` journals it every 300 s
   and **3 of 3 recorded `ratchet_rc` values are `"1"`** — documented in the sweep as *"ratchet saw
   coverage FALL"*. An alarm that fires unconditionally carries exactly as many bits as one that
   cannot fire (MEMORY: `alarm-polarity-and-attention-budget`). **This is why nobody saw the decay.**
2. **100% is unreachable by construction, so the GREEN state does not exist.** The CURRENCY pass
   deliberately left 103 items unprobed (investigations, design calls, multi-part conditions), and
   the `needs` class has no machine oracle by design. A ratchet whose healthy state the population
   cannot attain is the `cap-whose-population-is-empty` defect: *prove the green event can happen.*
3. ⚠️ **RETRACTED — this measurement was the analyst's error, and it is the most useful line here.**
   It read: *"168 open `needs` rows sit in the ratchet's `live` set; only 1 is dispatchable… they
   drag a firing-readiness metric they are not part of"*, concluding coverage was **28.7% and
   falling** from 32.5%. All of that is **false**. `needs` rows are born **BLOCKED**
   (`bin/cc-backlog:544` — the verb files them blocked and deliberately skips the dispatch kick), so
   the ratchet's `live` = open ∨ claimed had already excluded 167 of the 168. The 505-row figure
   came from `cc-backlog list --open`, whose projection **includes 198 blocked rows** — so the
   polluted denominator was mine, not the script's. **Correct numbers: 304 open + 3 claimed = 307
   live, 157 with a probe = 51.5%** — which is *up* from the CURRENCY pass's 51.0%, not down.
   Coverage was never falling. Invoking `positive-control-the-denominator` while failing to control
   the denominator is precisely how this class survives; the `$probeable` exclusion shipped anyway
   as defence-in-depth (one `needs` row is open today, so a reopen CAN put the class back in `live`)
   and the census now prints the excluded count so it can never again be assumed non-zero.
4. **Minting is fast but its pressure on the FIRING set is much smaller than the raw count.**
   Adds/day: 26 · 75 · 39 · 146 · 126 · 92 · 156 · **225** — but 132 of the last 225 are `needs`,
   which are born blocked and never dispatched. They grow the *store*, not the queue. The
   consolidation lever is therefore real but **second-order**, and the store-size figure must never
   again be quoted as if it were queue pressure (same defect as #3, one level up).

## The design — readiness is a PRECONDITION OF ADMISSION, keyed on an invalidator, never on a clock

**R1 · One conjunction, at the one seam.** `cc-dispatch`'s admission set is ≤ `CC_DISPATCH_MAX_SPAWN`
(default 2). Checking readiness there costs **O(2) per pass, never O(505)** — which is the whole
reason it can be always-on. `ready = premise-standing ∧ probe-trustworthy ∧ venue-current ∧
cluster-resolved`. Enforcement lives at the chokepoint that IS the act
(MEMORY: `enforcement-must-live-at-the-chokepoint`).

**R2 · A verdict is keyed on the trunk sha it was computed against, and voided by a PATH-INTERSECTING
move — not by age.** Store `readyAt: <sha>`. Void iff
`git diff --name-only <readyAt>..origin/main` intersects the item's cited path set. Trunk moving
elsewhere costs nothing; trunk moving *under the item* voids it instantly. This is the exact answer
to *"written hours/days/weeks before, with significant diff changes since"* — such an item is
**mechanically unfireable until re-derived**, whatever its age. 🚨 **An EMPTY path set is always
void, never always fresh** — an item citing nothing has proven nothing survived (the fail-open trap
this repo keeps paying for).

**R3 · Not-ready must be REPAIRABLE, never a drop.** A void item is re-derived in place and fires on
the next pass. A gate that silently shreds work is worse than the staleness it prevents; ship it
**advisory-first** (journal the verdict, admit anyway), measure the would-block rate, then flip to
enforcing — the same ratchet discipline M2 used.

**R4 · The second screen, which the CURRENCY pass specified and nothing built.** Its own words:
*"Did it already pass on the day the item was filed? — nothing checks this, and it is the commoner
failure by 8 instances to 2."* ⚠️ The mechanical form given there — `git log -S<token>
--before=<item lastTs>` — is **defective and was corrected by W2 on delivery**: `--before` filters
AUTHOR dates, so a change authored before an item and landed after it reads as "already passing".
Reconstruct the filing-day TREE instead. See the CURRENCY correction above for the worked case
— a token already in the tree at filing cannot be the remedy's signature. **16 of 26 hand-reviewed
probes were refuted for exactly this**, and the lead's own spot check caught 1 of the 16. Unbuilt,
every future coverage push re-manufactures anti-coverage: rows that read as checked and are a
guaranteed false retraction.

**R5 · Fix the instrument before trusting anything measured through it.** Correct denominator
(dispatchable, not `live`), re-baseline the high-water, and refuse to record a high-water from a
denominator below a floor — so a degenerate read can never again latch a target the population
cannot reach. ⚠️ MEMORY: `corrected-instrument-can-lie-again` — re-check it after the fix rather
than assuming the correction took.

**R6 · Consolidation ACTS on the mechanical half.** `cc-backlog` already has `--condition` re-keying.
Rows differing only by an embedded sha/digit fold into their condition master with **no judgment
required**; only semantically-distinct clusters escalate to a decision. A detector that files an
item asking a human to consolidate is one more row in the pile it is measuring.

**R7 · Brake the mint.** The dominant generator (`needs`, 132/225) should be **condition-keyed so a
recurrence UPDATES rather than MINTS**. This is the only lever that changes the denominator's slope,
and every other number here is a ratio over that denominator.

## Phase 0 · Agent Team Orchestration

**EXECUTION LOCUS PER WAVE.** W0 is **L** (lead-inline): it is the instrument every other wave is
measured through, it is one file plus its suite, and doing it first is what makes W1–W3 verifiable at
all. W1–W3 are **S** (dispatched sessions, the default) — each is a multi-file implementation whose
detail belongs in its own context.

| Wave | Locus | Deliverable | Depends on |
|---|---|---|---|
| **W0 · the instrument** | L | ratchet: dispatchable denominator · re-baseline · floor guard so an unreachable target cannot latch | — |
| **W1 · the conjunction** | S | `readyAt` + the admission-seam gate (advisory-first) + `cc-venue`'s missing caller | W0 |
| **W2 · the second screen** | S | filing-day discrimination (`git log -S… --before=`), retro-scan of the 145 stored probes | W0 |
| **W3 · act, and brake** | S | consolidation actuator (condition-fold) + `needs` condition-keying | W0 |

W1/W2/W3 are independent (different files, no ordering dependency) and fire concurrently after W0.
**Lead context budget:** recycle at the seam after W0 lands and the three are fired.

**Anti-goal:** a readiness gate that stalls the dispatcher. 219 open rows carry no venue label today;
a fail-closed gate shipped enforcing on day one would admit nothing. Advisory-first is not timidity,
it is the only way to learn the would-block rate before it becomes a wall.

## W2 — LANDED 2026-08-11 (`295f6240a`) · the second screen exists, and it corrected the plan that specified it

`bin/cc-premise screen <id>|--all` returns three verdicts — DISCRIMINATING · ANTI-COVERAGE ·
**UNDECIDABLE, first-class and the default on every failure path** — and is wired ONE-WAY into
`assess`, so an anti-coverage falsifier can no longer retract an item. 113/113 cc-premise cases
green; **12 of 13 new cases RED against `origin/main`**, the 13th green by design (it is the
preservation control).

| | result |
|---|---|
| positive control | `918e9bac60b6` + `8e07e87770ce` → ANTI-COVERAGE, evidence shas `da81f555` / `bdb3fe750` |
| replay over the 16 hand-refuted probes | 4 ANTI-COVERAGE · 9 DISCRIMINATING · 3 UNDECIDABLE — and it found **2 the brief never named** (`9a25cbc24799`, `97de2797ccf5`) |
| live retro-scan, 163 stored probes | 86 DISCRIMINATING · **0 ANTI-COVERAGE** · 77 UNDECIDABLE · nothing cleared |

🚨 **The finding worth carrying: the wave's own brief named THREE anti-coverage items and one of
them was innocent.** `80e6637dfd9e` is DISCRIMINATING, and the false conviction came from the
instrument this plan prescribed — see the CORRECTED block in § CURRENCY. A remedy specified in a
plan is a claim like any other; W2's deliverable refuted its own brief's evidence, which is the
outcome an adversarial screen is supposed to produce and the reason it was built to report rather
than to auto-clear.

**0 ANTI-COVERAGE on the live store is a real number, not a broken screen** — the 16 refuted probes
were `--clear`ed by the CURRENCY pass, so the population it would convict was already removed. The
replay over those 16 is what proves the screen can still fire; a live-store zero on its own could
not (MEMORY: `positive-control-the-denominator`). The 77 UNDECIDABLE are the honest remainder and
are where the next increment of trust lives.

**Not this wave's, and not filed twice:** `deploy-live` still refuses (NO-GREEN-AHEAD, lag 24/1h,
inside budget) — pre-existing, already filed 17× (`903e7ae67621` et al).

## W1 — LANDED 2026-08-11 (`9dd6f7a4c` · `056f5d9d8` / `5ac7990d9`) · and the measurement says DO NOT enforce yet

Readiness is now computed for each item the dispatcher is about to ADMIT, keyed on the trunk sha and
voided by a path-intersecting diff, with `cc-venue` gaining `paths` (the cited path set, taken from
cc-premise's own extractor rather than a second implementation). 136/136 green across
`tests/cc-dispatch-*.bats` + `tests/cc-venue*.bats`; 30 new cases, 30/30 RED against
`git show origin/main:<file>`, 3 mutants, 0 dead assertions.

🚨 **THE MEASUREMENT IS THE DELIVERABLE, AND IT REFUTES THE OBVIOUS NEXT STEP.** Two passes over the
live store with every write suppressed: **would-block 100% on pass 1** (nothing certified yet) →
**60% on pass 2**. So flipping `CC_DISPATCH_READY_GATE` to `enforce` today would **block 3 admissions
in 5**. This is exactly the anti-goal § READINESS names, and advisory-first is the only reason the
number could be learned at all rather than discovered as a stalled dispatcher.

**And the residual is not what the design assumed.** 6 of 10 verdicts are **cites-nothing**, not
staleness — i.e. the binding constraint is R2's deliberate fail-closed rule (*"an EMPTY path set is
ALWAYS VOID… an item citing nothing has proven nothing survived"*), working exactly as specified and
hitting a store whose items mostly do not name their files. **The cure is item CITATIONS, not a
weaker gate** — do NOT relax R2 to make the number look better; that would restore precisely the
fail-open trap it was written to close. Citation coverage is therefore the next ratchet target, and
it is the metric that gates the advisory→enforce flip.

⚠️ **The plan's own "219 unlabelled" figure was stale and is retired.** Re-measured at W1's return:
**312 open+claimed, 281 carrying a `venuePlan`, 31 without** — the venue arm is NOT the binding one,
so the anti-goal's original justification has moved even though the anti-goal itself stands (the
60% now comes from citations). Third time this document's figures have decayed under it
(MEMORY: `published-figure-decays-with-its-source`): **re-derive, never quote.**

**A defect W1 found in its own diff, and it is the sharpest thing in this wave.** Widening the admit
loop's delimited read from 3 to 5 fields hit **tab-is-IFS-whitespace**: an empty cluster key let
`venuePlan` slide into `$dclus`, so two unrelated items "clustered" on the string `local` and one
deferred the other as a phantom sibling. Silent, and it would have looked like the readiness gate
correctly deferring work. Separator is now `\037`; cases 28/29 pin both halves.

**Not live yet, and not this wave's to fix:** `deploy-live` refuses (no GREEN tree descends from live
HEAD `32355a9b1`, lag 25/2h inside the 25/6h budget), so `~/.claude/bin/cc-dispatch` still runs the
old bytes. Fleet-wide converger state, already filed ~17×; no duplicate row was created.
