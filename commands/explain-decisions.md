---
description: Itemize every open decision, answer-first (Pyramid Principle) — each with a recommendation and a conviction %; research exhaustively wherever that would move a conviction
argument-hint: [optional scope, e.g. a plan path or topic]
---

short and concise, Pyramid Principles leading with the answer: explain each itemized decision, provide your recommendation, and your conviction % of that recommendation. If exhaustive research moves your conviction one way or another, exhaustively research now.

Then dispose of every decision:

1. Write the report to a durable path (a repo's `docs/research/<slug>/` or `~/.claude/autonomy/research/<slug>/`), never `/tmp`. It is the receipt.
2. Close each packet the re-check proves settled or duplicate at >90%: `cc-decide action <id> --evidence "<why>"`.
3. Implement each recommendation above 90% that is in none of the sign-off classes: escalation surface, money, credentials or permissions, self-modification, irreversible or production-mutating, third-party contact or publishing.
4. Stamp every remaining open packet: `cc-decide recheck <id> --conviction N --receipt <report> --recommendation "<one line>" --tier signoff|default|nochange`.
   - An item above 90% that is in a sign-off class cannot be stamped. Name it first on line 1.
   - Skip this step inside an active research program.
5. Close with these three lines:
   - Line 1: `❌ Good to close: no — research done, implementation pending: <N> decision(s) wait on your sign-off — first, <decision in plain English>, <conviction>%.`
   - Line 2: the ledger's rung, relayed verbatim (`~/.claude/scripts/wrap-ledger.sh --machine` `READOUT`), e.g. `⛔ Blocked — research done, implementation pending: <N> decision(s) need your call: cc-decide list --open`.
   - Line 3: `Reply approve or veto for each; on approval this pane recycles into implementation.`

$ARGUMENTS
