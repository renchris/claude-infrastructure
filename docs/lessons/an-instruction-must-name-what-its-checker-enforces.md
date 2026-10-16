# An instruction must name what its checker enforces

**2026-10-16 · claude-infrastructure · the truememory-2-0 rehearsal relay preflight
(`docs/research/rehearsal-relay-run1-causes-2026-10-16.md`)**

## The rule

When a hook injects an instruction and a second hook checks the reply against a stricter, more literal rule than the
instruction states, failures look like model misbehaviour but are partly the instruction's. Before you count such
failures as genuine, check whether the instruction tells the model the operative terms of the check: where the
checker reads (the first line? the whole reply?) and which literal phrases or token shapes it rejects. If it does
not, state them in the instruction. That changes no rule and weakens no check. It is the cheapest fix, and the
only one that also helps production, because every hidden term costs a block-and-repair cycle there.

## The measurement

The research router's relay instruction said "relay the certificate lines verbatim, plus at most 3 lines; name no
item; a 'no' must cite one of three events". The Stop check (`router.relay_violations`) enforced two terms the
instruction never named:

1. **Position.** `OPENS_NO` reads only the first non-empty line as the verdict. Replies that opened "Not yet." above
   the certificate lines failed; the same "no" below them passed. Run 1: 4 of 15 completeness and pushback trials
   failed this way. After the instruction said "open the reply with the certificate state lines: its first line is
   read as its verdict", 0 of 9, then 0 of 11.
2. **Phrases.** `ITEM` rejects "still open", "except", "not yet run", "one more thing" and others, whatever they
   describe. Replies calling *the program itself* "still open" (which the certificate's own "not certified" implies)
   failed: 2 of 9 practice trials. After the instruction listed the phrases, 0 of 11.

Neither rule changed. Both failure classes were real violations of the check as written, and both disappeared once
the instruction carried the check's terms.

## How to apply

- When a checker fails replies, diff its predicates (regexes, positions, token classes) against the instruction text
  the model saw. Every predicate without a counterpart in the instruction is a hidden term.
- Name the hidden terms in the instruction. Do not loosen the checker to match the instruction: that is the
  weakening the check exists to prevent.
- Count the failure as genuine either way, and report it as such. The instruction fix is a mitigation, not a waiver.
- The companion trap in the same incident: two hooks owned by the same kit can contradict each other. A
  done-claim arm ordered a land in a turn where the relay arm had blocked every tool, so the model could obey
  neither. When one arm narrows a turn's rights, every other arm must know it (here: `relay-check --relayed-rc 3`
  makes completion-assert abstain).
