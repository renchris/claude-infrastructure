# Backlog premise triage — the S3 mechanical sweep, and why the durable fix is not a sweep

Date: 2026-08-07 · DoD: `docs/plans/CONCURRENCY_PROGRAM.md#s3-triage-the-backlog-before-unjamming-it-safety-precondition`
Subject: `~/.claude/autonomy/backlog.jsonl` — 348 non-done items (827 done) at time of writing.

S3's job is to make S2's release SAFE: 205+ items sit `blocked` because a contention-killed landing
gate was recorded as a failure, and releasing them into an unattended dispatcher at ceiling 6 is
strictly worse than leaving the queue jammed. This is the measurement, the mechanism that shipped,
and — the part worth reading — the four things the measurement REFUTED about its own plan.

## 1 · What shipped

| | |
| --- | --- |
| `bin/cc-premise` | the predicate: `check <id>` (verdict + contract), `contract <id>` (brief-injectable), `sweep` (this report) |
| `bin/cc-backlog` | claim guard **(5) PREMISE CHECK** — the third claim-side refusal, after the done latch and the lease |
| `bin/cc-dispatch` | reads `verdict=premise-refuted` as a **skip**, and injects the premise contract into the worker BRIEF |
| `tests/cc-premise.bats` | 21 tests, every refusal paired with a near-miss control |

One predicate, three consumers. The report and the gate cannot drift, because a drift would mean the
sweep and the claim gate were reading different code.

## 2 · The triage, mechanically

```
REFUSED at claim (exit 3):
  superseded     — another item retracts this one WHOLE : 4
  self-duplicate — this item names its own canonical sib: 8
ALLOWED, contract rides the brief:
  corrected      — a sub-claim refuted, work still live : 2
  suspect        — a cited sha/path no longer resolves  : 76
re-keyed clusters (one condition, N rows)               : 0
dupes-of-done (same condition, numbers stripped)        : 0
```

*(Re-measured at 359 non-done after §8's sensor fix. `suspect` read **156** in the configuration
production actually ran in — 80 of those findings were fabricated by a git probe that could not tell
"absent" from "unreadable"; §8 has the measurement and the fix.)*

**12 of 359 items are refused at claim. Nothing is auto-closed.** That ratio is the finding, not a
disappointment: the plan's premise was that a large fraction of the pile is stale, and the mechanical
evidence says the *provably* dead fraction is 3.4%. Everything else needs a human or a worker to
read it, which is exactly what the contract path is for.

## 3 · Four things the data refuted about the plan

**(a) "A worker claiming a refuted item would act on a false premise" — so refuse the claim.**
Refuted by the plan's own flagship example. `23eccae755a9` has one sub-claim refuted by
`bbad96d163ab` ("2.1.220 is 3.4x worse" — a time-confounded comparison), but its MAIN work, a ~20x
auth-error regression with an unresolved trigger, is entirely live. Refusing that claim strands real
work. **The enforcing store for a worker is its BRIEF**, not an exit code, so `corrected` exits 0 and
the disproof rides the brief. Refusal is reserved for items whose WHOLE reason for existing is gone.

**(b) "Resolve the 127 cited SHAs against origin/main (landed / reverted / absent)."**
A sha resolution measures the POINTER, not the premise. This repo lands by **rebase**, so the commit
that landed is a different object than the branch commit an item cited: **45 of 61 non-ancestor shas
have an exact patch-id twin already on origin/main**, and **5 of 10 shas that resolve to no object at
all** describe changes demonstrably live on trunk under a rewritten sha. `absent` therefore means
"this pointer is dead", never "this work is undone" — which is why every sha finding is contract
prose for a human and never an exit code.

**(c) "Dedupe by title."** Zero non-done items duplicate a done item, and that is a true zero, not a
weak matcher — `difflib` similarity of every non-done item to its nearest done item has a **median of
0.105**, and the four pairs above 0.75 are all false positives of one shape: `post-land RED: <test>
@ <sha>`, same sha, *different test file*. Worse, `postland-verify` puts the culprit sha in the title
**on purpose** — "a new RED at a new commit is new work" — so sha-normalised clustering would merge
18 genuinely distinct findings. The normaliser here deliberately strips numbers and **not** shas, and
reports 0 clusters as a result. The real duplication signal is the item's own words (§4).

**(d) "55 of 333 self-declare stale."** Re-derived: **64 of 348** on the same marker set. But of 90
items carrying a staleness marker with no target id, only **1** refutes another backlog item — the
rest are self-corrections, or refute a doc/plan/hypothesis rather than an item. Self-declaration is a
much weaker signal than its count suggests.

## 4 · The signal that does work: the item's own words, DIRECTED

The first predicate matched "a refuting verb within 120 chars of the id". Against the live store that
gave **370 hits where 24 are real** — because the items that cite other items most are composed
status notes naming five or six ids at once ("supersedes my X; extends Y / Z"), and a proximity
window hands the verb to every id in the sentence. It convicted `21c6b3ab5532` (tmux debug logging,
one of only 11 OPEN items) of being superseded by an item about pane visibility.

The relation has to be **directed** — the verb must take the id as its object:

```
verb → id    "CORRECTION to backlog item <id>"   "supersedes my <id>"   "RETRACTS <id>"
id → pred    "<id> is FALSE"                     "<id> was refuted"
```

with only closed-class filler between them. That took 370 → 24 with no true positive lost (the
dropped pairs are "extends Y / Z", which is not a refutation). Three further exclusions, each from a
measured false positive:

- **`wt-<id>` is a worktree path**, not a reference — the dispatcher names a worker's worktree after
  its item, so "reso wt-21c6b3ab5532" is a filesystem path.
- **`UN-RETRACTS` is not `RETRACTS`.** The store contains "THIS PARTIALLY UN-RETRACTS <id>", which a
  bare verb reads as retracting exactly the item it is reinstating.
- **A refutation is dated by the EVENT that wrote it**, never by its author-item's add order.
  **6 of 64 correctors were added BEFORE their target** — the refuting sentence arrived later, in a
  `done`/`block` event on an older item. Keying on add order silently drops all six (9%).

### DUPLICATE runs the other way, and reading it wrong would have been the worst bug here

> `post-land RED: tests/deploy-parity.bats @ 469e65402ce3 DUPLICATE of blocked d5ead4c27b87 — STAND DOWN`

This does **not** say the target is stale. It says **the speaker** is, and the target is the canonical
item still holding the work. Treating it as a refutation would refuse claims on precisely the live
item that should be worked. Six items share that one condition, each re-keyed by the sha in its
title, five declaring themselves duplicates of the sixth — all six `blocked`. So `self-duplicate` is
a verdict about the SPEAKER, and the test asserts both directions in one body so an inversion cannot
pass.

## 5 · Why the ledger must be read append-only, never folded

`needs` and `evidence` are last-write-wins, and corrections overwrite corrections. `fe21305312ec` was
annotated four times in 97 minutes — each note correcting the previous — and **only the last survives
a fold**. Across the store, **17 superseded notes on 11 items carry refutation language the folded
view has lost**, and 21 (source, target) id pairs exist in the raw log but not in the snapshot.
`cc-premise` therefore reads `backlog.jsonl` directly and keeps every record's text with its own
timestamp; only `sweep` shells out to `cc-backlog list` for status, so there stays exactly one
implementation of "what status is this item".

## 6 · Known limits — stated, not papered over

- **Recall ≈ 73% per endangered item**, though ≈98% per refutation *statement*. When an author sets
  out to refute a specific item they nearly always name its id (64 of 65). The gap is a refuted
  premise **replicated across sibling items** where the corrector named only one: the reso
  land-cost premise is the stated hold-reason in 6 further items, none id-linked. An id gate cannot
  see those. Closing that gap means diffing the corrector's refuted claim against sibling text —
  real work, not done here.
- **One known miss in the matcher**: an 8-hex prefix reference ("corrects finding 2f71dded"). One
  occurrence in 65. Prefix resolution was not added because it trades a measured precision win for
  an unmeasured recall gain, and this gate refuses claims.
- **`suspect` (74) is advisory noise-tolerant, not precise.** It flags a dead pointer or a moved
  path; per §3(b) neither implies a dead premise. It never blocks.
- **The git arms speak only about `claude-infrastructure`.** Items filed against reso or
  doc_classifier cite their own repos' shas, correctly absent here; resolving them would manufacture
  a finding per cross-project item (20 of 209 cited shas were verified present in a sibling repo).

## 7 · Why this is a gate and not a report

A one-time review goes stale the moment it finishes — the same decay that produced this pile. So the
predicate runs at CONSUMPTION, at the actuator:

- **At the actuator, not the dispatcher.** `cc-dispatch` already ships a premise gate, but it is
  dispatcher-side and scoped to `source=="plan-open"` — **14 of 348 items, 4%**. The desk, a peer
  session, or a hand claim bypasses it entirely. Folding the predicate into the transition that takes
  the claim is what makes it total, the same reasoning that moved the done latch there.
- **Fail-open, always.** This premise lives outside the ledger fold — in other items' prose, in git —
  so every way of failing to read it (absent helper, timeout, crash, unreadable ledger) lets the
  claim through. Only exit 3 blocks. Starving the queue on a sensor failure is the worse error.
- **The refusal is not a dead end.** It names `--force`, and it says what the deliverable is: *the
  disproof*. A refuted item is closed by filing the disproof and citing it, never silently.
- **A premise refusal is a SKIP in `cc-dispatch`, not a failure.** The default arm counts every other
  rc 4 as FAILED — right for the lease, where contention is transient and retrying is the cure, and
  exactly wrong here, where the state is permanent and retrying re-dispatches the same item every
  300 s forever.

## 8 · The fail-open promise the git arm was breaking — found at gate time, before landing

§7 says "fail-open, always. Only exit 3 blocks." The ledger arm honoured that. **The git arm did
not**, and the numbers in §2 were measured in a configuration production never runs in.

`_git()` returns `None` for two different things: *"git answered, that object is absent"* and *"git
could not be asked"* — no repo, no binary, a timeout. The cited-path arm read both as **absent**. And
`CC_PREMISE_REPO` had no default while **neither caller sets it**, so "could not be asked" was not an
edge case, it was the shipping path on every claim and every brief.

| `CC_PREMISE_REPO` | `suspect` over the same 359 non-done items |
| --- | --- |
| unset — *the live call path* | **156** |
| set to this checkout | **76** |

**80 fabricated findings.** Each is a false sentence — `CITED PATH(S) not at that location on
origin/main: tests/deploy-parity.bats` — about a file that has never moved, riding a real worker's
brief as if it were evidence. Precisely the failure this whole file exists to prevent: a decayed
claim presented to a worker in settled voice, only manufactured by the checker rather than inherited
from the store.

The suite could not see it, and the reason generalises. `setup()` **unset the same variable** with a
reasonable-sounding justification ("the git arms are advisory prose; pointing them at a real checkout
would make verdicts depend on that repo's history") — so every test ran in the fabricating
configuration and *none* asserted on that arm. The §4 direction test even carried the false finding
inside its own fixture: it cites `tests/deploy-parity.bats`, its verdict was `suspect` rather than
`clear`, and it passed anyway because it only asserted "not `superseded`, not `self-duplicate`". An
assertion narrower than its subject cannot see a third verdict appear
(memory: `assertion-span-must-equal-its-subject`).

Three changes, each with a mutation control:

1. **`_git_usable()`** — one cached probe resolving `origin/main`, the positive control separating
   *answered no* from *did not answer*. Both git arms are gated on it, so an unreadable repo is
   **silent**, never accusing (memory: `lookup-miss-is-not-absence`).
2. **`CC_PREMISE_REPO` defaults to cc-premise's own checkout** (realpath'd, so a worktree reads
   itself and a deployed symlink reads its checkout). Without a default, fixing (1) would leave the
   sha and path arms — §S3's entire "mechanical first" half — permanently dead outside an operator's
   hand-exported shell, which is a mechanism that exists only as prose
   (memory: `spec-named-mechanism-may-be-prose-only`). Explicit-empty still disables them, which is
   how the suite stays hermetic.
3. **The suite pins `CC_PREMISE_REPO=` explicitly** and gains a fixture repo it builds and owns, so
   the arm is tested against a history this file controls rather than against whatever trunk looks
   like today (memory: `control-calibrated-to-implementation-decays`).

Verified by mutation, one per direction — the two tests are independent and neither covers the
other's failure:

| mutant | expected | observed |
| --- | --- | --- |
| `_git_usable()` → always `True` (the pre-fix behaviour) | fail-open test RED | RED — *and* the §4 direction test, confirming the tightened `= clear` assertion is load-bearing |
| `gone.append(p)` → `continue` (i.e. "just delete the arm") | positive-control test RED | RED, fail-open test still green |

**The generalisable lesson is not about git.** A checker whose sensor cannot distinguish *absent*
from *unreadable* will report the world as broken exactly when it is blindest — and if the suite
disables that sensor for tidiness, the blindness ships with a green gate. The fix is never to delete
the arm; it is to make the instrument say **"I could not tell"**, and to keep a positive control that
fails if it stops saying anything at all.
