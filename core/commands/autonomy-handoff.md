---
description: Hand this session's work to a fresh context in the same terminal (autonomy core)
---
<!-- autonomy-core -->
Hand off to a fresh session so the work continues with an empty context. $ARGUMENTS

1. Commit finished work first (explicit paths, one commit per logical step). Uncommitted work that is
   not finished stays in the tree; say so in the bridge.
2. Write the bridge to `__AC_HOME__/handoffs/<YYYYMMDD-HHMM>-<short-topic>.md` with these sections, each
   short and concrete (file paths, commands, shas; nothing a successor could not act on):
   - **Scope (frozen)**: the one-line contract, plus any `Scope (grown)` lines.
   - **Done**: what is finished, with commit shas.
   - **Next**: the ordered remaining steps, the first one exact enough to start without reading anything else.
   - **Decisions and dead ends**: what was decided and why, and approaches already rejected, so the
     successor does not repeat them. This is the part only this context holds.
   - **Verify with**: the commands that prove the end state.
   - **Goal**: a `/goal` condition for the successor (`<end state> — proven by <command>; do not <constraint>`).
3. Clear auto-continue: `__AC_HOME__/bin/autonomy continue clear`.
4. Tell the user, as the last thing in your message, exactly:

   ▶ Run `/clear`, then paste:

   `Read <bridge path> and continue from its Next section.`

   (or, in a new terminal: `claude "Read <bridge path> and continue from its Next section."`)
