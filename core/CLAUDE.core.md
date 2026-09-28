# Autonomy core — how to run long and finish

These rules make a session drive its work to a finished, verified, committed state on its own, stop
only for real decisions, and close with a state line taken from git rather than from memory. Three
hooks back them: auto-continue, a completion gate, and a backup before every Write. The command line
is `__AC_HOME__/bin/autonomy`.

## Freeze the scope first

The first time a task will change files, restate the ask as one line, `Scope (frozen): …`, in the plan
or in chat. At the end, "done" means that line is met; it is not a fresh judgment. If the scope cannot
be reconstructed, ask.

## Drive to done without asking

- Inside the frozen scope, keep going: finish, run the project's checks (tests, typecheck, lint), fix
  what fails (up to about two debugging cycles, then commit what works and report), and commit.
- Commit as you go: one commit per finished logical step, staging explicit paths only. Never commit
  changes you did not make.
- A follow-on you discover (a bug next to yours, a missing test) is done now, without asking, when it
  is clearly net-positive, well understood, as safe as the main task and small. Note it as
  `Scope (grown): +<item>`. Otherwise mention it in one line and drop it.
- Stop and ask only for a real decision: something destructive or irreversible, auth or security, a
  choice between options with different outcomes for the user, or information you cannot find. State
  the decision in one sentence with your recommendation and how sure you are, in percent.
- Offering in-scope work ("say the word and I'll do X") is not a close. Do it, or say why not.

## Keep working instead of stopping

- If you would stop with in-scope work left, arm the next step:
  `__AC_HOME__/bin/autonomy continue set "<the one next step>"`. The stop turns into another turn with
  that step (at most 8 in a row; re-arming resets the count).
- Clear it as soon as the work is finished, blocked on the user, or out of scope:
  `__AC_HOME__/bin/autonomy continue clear`.
- The completion gate blocks a stop once when your message says "done" but git still shows
  uncommitted tracked changes or unpushed commits. Finish the work, or say plainly what remains.

## Use /goal for long runs

`/goal <condition>` (built into Claude Code) keeps a session taking turns until a separate evaluator
judges the condition met. It only sees what the session prints, so write the condition in three parts:

    <one measurable end state> — proven by <a command the session runs and prints>; do not <constraint>

Example: `all tests in tests/api pass and the branch is pushed — proven by printing the pytest summary
and git status -sb; do not change the public API`. A condition that names an activity or perfection
("continue until 100% perfect") never clears. A goal is checked only when the session stops, so a
session that hands off or ends mid-turn is never evaluated.

## Context is a budget

Check fill with `/context`. From about 50%, plan a pause point; before about 75%, commit, write down
what a fresh session would need, and hand off with `/handoff`. Never ride a session into the context
limit: the session then fails every later turn.

## Files that accumulate decisions

Plans, design docs, research notes and CLAUDE.md files are integrated, never overwritten: use Edit
for changes and appended sections, and Write only to create a file. Every Write that replaces a file
is backed up first; `__AC_HOME__/bin/autonomy restore <path>` puts the newest copy back.

## Close every turn that changed files with a readout

Run `__AC_HOME__/bin/autonomy ledger` (or `/wrap`) and start the close with its `READOUT` glyph:

- 🔧 loose ends: uncommitted changes, or a check failed. Not a close: keep going.
- 📦 committed but not pushed: push it if pushing is how this project lands work; otherwise say so.
- ✅ clean and pushed: say it plainly, without hedging.

Line 2 answers `Good to close: yes` or `Good to close: no — <what remains, and who owns it>`. Claim
"done" only when the frozen scope is met, the checks ran green this turn, and the ledger reads ✅.
