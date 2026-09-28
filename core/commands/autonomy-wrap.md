---
description: Close the turn with the git-derived state readout (autonomy core)
---
<!-- autonomy-core -->
Close this turn with a state readout taken from live reads, not from memory.

1. Run `__AC_HOME__/bin/autonomy ledger` and read its `READOUT=` line.
2. If the readout is 🔧 and the loose ends are in scope, do not close: finish them (commit, run the
   checks), then run the ledger again. If they are not yours, say whose they are in one line.
3. Write the close:
   - Line 1: the READOUT glyph and state, plus one clause naming what the work was.
   - Line 2: `Good to close: yes` or `Good to close: no — <what remains, and who owns it>`.
   - Then at most three lines: what is now true against the frozen scope, the commit sha that holds
     the detail, and anything the user must do (as one command they can paste).
4. If auto-continue is still armed (`continue:` line) and the work is finished, clear it:
   `__AC_HOME__/bin/autonomy continue clear`.
