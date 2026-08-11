You are W3 of the READINESS wave in claude-infrastructure. Read
docs/plans/BACKLOG_CONSOLIDATION_2026-08-09.md § "READINESS (2026-08-11)" R6 and R7 FIRST.
W0 landed already (c61ee7147).

GOAL: make consolidation ACT rather than detect, and brake the mint at its source.

FILES YOU OWN (do not edit any other tracked file; W1 owns bin/cc-dispatch + bin/cc-venue,
W2 owns bin/cc-premise):
  scripts/backlog-consolidation-trigger.sh
  bin/cc-backlog
  tests/backlog-consolidation*.bats, tests/cc-backlog*.bats

BUILD:

1. THE ACTUATOR. Today the trigger DETECTS clusters at threshold 5 and files ONE item asking a
   human to consolidate — i.e. a detector that answers a pile by adding to it. `cc-backlog`
   already has `--condition <slug>` re-keying, which re-keys an item's hash to project+condition
   so a recurrence UPDATES instead of MINTING. Rows that differ ONLY by an embedded sha/digit
   (which is exactly what the trigger's normalisation already identifies — it strips shas and
   digits before grouping, see its header) can be folded into a condition master with NO judgment.
   Fold those automatically. Only SEMANTICALLY distinct clusters — different titles, same effort —
   escalate to a filed decision.
   🚨 Read the trigger's own header on the two corrections its cluster key already cost:
   `[0-9a-f]{7,40}` also matches "defaced" and "cabbage" so a hex run must carry a digit; and
   keying on the normalised title unconditionally made every UNTITLED row collapse into one
   cluster. An inferred cluster needs three surviving alphabetic tokens AND two distinct raw
   titles. A DECLARED --condition bypasses that bar. Do not re-litigate these; inherit them.

2. THE MINT BRAKE. `needs` is the dominant generator — 132 of the 225 rows minted on 2026-08-11.
   Each is an operator step, born BLOCKED (bin/cc-backlog:544), so they grow the STORE without
   growing the queue — but they grow it without bound. Where a `needs` row RECURS (the same
   operator step re-discovered by a later session), it should be condition-keyed so the second
   filing updates the first instead of minting a sibling. Measure how many of the 167 open `needs`
   rows are recurrences before you build, and PRINT that number: if it is small, say so and scope
   the brake down rather than building a mechanism for a population that does not exist.

3. NEVER DESTRUCTIVE. A fold must be an append-only event that the existing fold rule carries
   (the store is append-only evidence — `cc-backlog`'s header is explicit). No row is rewritten,
   nothing is deleted, and an item absorbed into a master must remain traceable to it.

DoD — every one proven by a command you RUN and PRINT:
  · `bats tests/backlog-consolidation*.bats tests/cc-backlog*.bats` green; each NEW case
    RED-proven against the pre-fix subject from `git show origin/main:<file>`.
  · the recurrence measurement from step 2, printed as a number with the query that produced it.
  · a DRY-RUN over the live store showing exactly what would fold and what would escalate,
    with conservation checked: no item disappears, the before/after open count reconciles.
  · the trigger's positive control still passes — note its header says the live store has ZERO
    clusters at threshold 5 today, so the control lives in the FIXTURE. Your actuator needs the
    same treatment: prove it on a fixture, demonstrate it dry on the live store.
  · landed via `bash scripts/ship-land.sh` from your worktree, content-verified with
    `git show origin/main:<path>` — NEVER by commit count.

CONSTRAINTS: never commit in ~/Development/claude-infrastructure (shared checkout — this repo's
.claude/CLAUDE.md forbids it); work only in your worktree. bin/cc-backlog is the fleet's ledger
and every session on this box writes to it — a bug here is fleet-wide, so prefer refusing to
folding when a case is ambiguous. Stop and message the lead on anything you cannot resolve inside
your owned files.
