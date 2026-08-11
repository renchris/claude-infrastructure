You are W1 of the READINESS wave in claude-infrastructure. Read
docs/plans/BACKLOG_CONSOLIDATION_2026-08-09.md § "READINESS (2026-08-11)" FIRST — it is the
design and it is authoritative. Landed already: W0 (the ratchet instrument, c61ee7147).

GOAL: make readiness a PRECONDITION OF ADMISSION in the dispatcher, advisory-first.

FILES YOU OWN (do not edit any other tracked file; W2 owns bin/cc-premise, W3 owns
bin/cc-backlog + scripts/backlog-consolidation-trigger.sh):
  bin/cc-dispatch      · the admission seam
  bin/cc-venue         · the producer that today has NO automatic caller
  tests/cc-dispatch-*.bats, tests/cc-venue*.bats

BUILD, in this order:

1. READINESS CONJUNCTION at the admission seam. `cc-dispatch`'s admit path is around
   bin/cc-dispatch:1210-1410 (`order_dispatchable` → the admit loop → `fire_args` at ~1416).
   For each item about to be ADMITTED (<= CC_DISPATCH_MAX_SPAWN, default 2 — so this is O(2)
   per pass and must never become a store-wide sweep), compute:
     ready = premise-standing AND venue-current AND cluster-resolved
   The premise arm already exists (the claim-time cc-premise call, ~1404). Add the other two.

2. THE VERDICT IS KEYED ON THE TRUNK SHA, NOT ON AGE. Record `readyAt: <sha>` in the
   DISPATCHER'S OWN decision journal (the IDL / decision rows) — NOT on the backlog ledger.
   The ledger is evidence; a derived cache belongs in the decider. Void the verdict iff
   `git diff --name-only <readyAt>..origin/main` INTERSECTS the item's cited path set.
   🚨 An EMPTY path set is ALWAYS VOID, never always-fresh — an item citing nothing has proven
   nothing survived. This is the fail-open trap; a test must pin it.

3. ADVISORY-FIRST, and this is not optional. 219 of the open rows carry no venue label today,
   so a fail-closed gate shipped enforcing would admit nothing. Ship it journalling the verdict
   and admitting anyway, behind CC_DISPATCH_READY_GATE=advisory|enforce (default advisory).
   Print the would-block RATE in the summary IDL row so the flip is a measurement, not a guess.

4. NOT-READY MUST BE REPAIRABLE. A void item is re-derived in place and eligible next pass.
   Never drop, never mark done. A gate that silently shreds work is worse than the staleness.

5. cc-venue's MISSING CALLER. `cc-venue run` has zero automatic callers today (verified: only
   bin/cc-dispatch:1483 READS venuePlan). Wire it at TWO points, neither a full sweep:
   (a) the existing debounced write path — bin/cc-backlog:3670 `dispatch_kick` already fires a
       decision pass on `add`; label the NEW row only.
   (b) at admission, re-label an item whose venue verdict is void.
   Do NOT add a periodic full-store `cc-venue run` — that re-creates the batch this wave exists
   to delete.

DoD — every one of these, proven by a command you RUN and PRINT:
  · `bats tests/cc-dispatch-*.bats tests/cc-venue*.bats` green, and each NEW case RED-proven
    against the pre-fix subject recovered with `git show origin/main:<file>`.
  · one mutant per NEW guard site (a green suite that credits no site proves nothing).
  · `cc-dispatch --dry-run` prints a readiness verdict per candidate and admits as before.
  · the would-block rate is printed and is a real number, not 0-because-unreachable.
  · landed via `bash scripts/ship-land.sh` from your worktree, content-verified on origin/main
    with `git ls-tree` / `git show origin/main:<path>` — NEVER by commit count.

CONSTRAINTS: never commit in ~/Development/claude-infrastructure (shared checkout, other
sessions' branches — this repo's .claude/CLAUDE.md forbids it); work only in your worktree.
The land gate is strict and will red you on shellcheck SC2016, dead /Users/chrisren/.claude/bin/cc-bats assertions, and
hermeticity — read its output, it names the file and the fix. Stop and message the lead on any
issue you cannot resolve inside your owned files.
