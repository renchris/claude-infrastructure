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
