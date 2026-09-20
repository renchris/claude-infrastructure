# An own-scope gate is blind to a counted pin that lives outside your diff

**The rule.** A land gate that blocks only on the files in your own diff cannot see a test in
ANOTHER file whose assertion is a COUNT over a file you changed. Adding one more occurrence of a
repeated construct — an alarm site, a hook registration, an exported name, a `case` arm — moves
that count, the gate says nothing, and trunk goes red for whoever lands next. Before landing a new
occurrence of a construct that appears several times in one file, grep `tests/` for a count over
that file's path.

## The incident (2026-09-20, claude-infrastructure)

W2 of `LIMIT_RECOVER_100P` added a seventh `hf_alarm` site to `scripts/handoff-fire.sh` — the boot
wait's 60 s abstention arm, class `recycle-boot-indeterminate`. Its own six-round land gate was
green: every ratchet it ran was scoped to the diff, and `tests/handoff-alarm-records.bats` was not
in the diff. That suite pins `[ "$(grep -c '^    hf_alarm ' "$FIRE")" -eq 6 ]`.

Trunk went red, and the wave that caused it never saw it. A **sibling session** (pane 198) hit it on
an unrelated docs-only land ~1 h later, triaged it to `file:line` with the exact fix, and mailed it
over. Two suites were red; the second was the same author's brand-new suite missing one hermeticity
pin, named by a *different* suite's pin-guard — i.e. both reds lived outside the diff that caused
them.

**This was the third time for this same pin.** Its own comment already records two 2026-08-25
commits that "moved it without saying so and left this suite red on trunk for ~23h". A construct
that has gone red three times from the same cause is not a discipline problem.

## Why the pin is still right

The pin is deliberate and says so: it does not track the file, it **forces a new alarm site to be a
decision somebody writes down**. Raising the count without recording the sha and the class would
discard exactly what it exists to collect. The correct fix is the one the comment asks for — raise
the number AND write down which site and why its class is distinct — not to loosen the assertion.

## What to do

- **When you add the Nth occurrence of anything:** `grep -rn "grep -c.*<file>" tests/` before you
  land. A counted pin is cheap to find and expensive to leave red.
- **When you write a counted pin:** name, in the comment, the construct it counts and the command
  that finds it, so the next author can locate it from their own side.
- **When a sibling hands you a trunk red:** it is yours if your diff moved the count, regardless of
  whether your gate could see it. Attribute by cause, not by what the gate reported.

## Companions

- `docs/lessons/gate-red-on-a-file-your-diff-touches-is-not-a-red-on-your-diff.md` — the converse:
  a whole-tree gate naming your file proves nothing until the failing LINES sit in your hunks.
- `docs/lessons/a-ratchet-s-culprit-is-in-its-output-not-in-the-range.md` — whole-tree ratchets
  carry no reachability information; read the failing assertion's printed path.
- `docs/lessons/a-gate-s-surface-is-not-its-traffic.md` — a gate proven reachable on the surface it
  names is not a gate the work still crosses.
