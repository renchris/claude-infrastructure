---
description: Start or resume a no-take-backs research program — intake, signed frame, certification, gate (skill research-program)
argument-hint: "[<slug> | new <slug>]"
---

Load the `research-program` skill and follow it. Argument: `$ARGUMENTS`.

- **`new <slug>`** — start a program: restore every vendor lane, then Stage 1 from the top (index and
  mine, `intake.py init`, the two rulings, the interview).
- **`<slug>`** — resume one. Read its state first and act on what it says, never on memory:
  - `scripts/research-kit/intake.py status --program <slug>` (stage 1 steps done or TODO);
  - `scripts/research-kit/gate.sh run --program <slug>` once frozen (every row with its evidence).
- **No argument** — list registered programs from `~/.claude/autonomy/research/programs.json` (read
  only; `gate.sh` is its only writer) and ask which one.

If the program is `certified`, a completeness or pushback question is answered by relaying
`scripts/research-kit/gate.sh --render --program <slug>` unchanged; do not research.
