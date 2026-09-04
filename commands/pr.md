Open a PR whose first line is the answer.

## The body

**Line 1 is the answer** — one sentence saying what is now true that was not, in the
reviewer's terms. Not a heading, not a bullet, not "Summary of changes". If they read only
that line, they should know whether this matters to them.

Then only what changes their review, and nothing else:

- **Why**, if line 1 does not already imply it.
- **What to check** — the risk, and the command you ran. State results as facts, not
  checkboxes: `618 tests pass, tsc clean`, never `- [ ] tests passing`. A checkbox is a
  promise; a result is evidence.
- **What they would otherwise have to ask for** — one line each, or a path/sha to read.

Omit any section that would be empty. Do not restate the diff or list your commits — the
reviewer has both, better rendered, one click away.

**Cut, do not compress.** Reasoning, dead ends and measurements belong in the commit body
(`git show <sha>`) or a linked doc. Over 400 words `hooks/pr-pyramid-gate.sh` refuses the
body — that is a signal to move detail out, never to squeeze sentences into fragments or
arrow chains.

## Steps

1. `git diff <base>...HEAD` — read what you actually changed, not what you meant to.
2. Run the repo's gate (tests, lint, and any repo-specific check). Red ⇒ fix before opening.
3. `gh pr create --title "<lowercase, conventional-commit style>" --body "<the above>"`

The gate blocks a body that opens with a heading, a bullet, or boilerplate. To bypass it for
one call: `CC_PR_PYRAMID=off gh pr create …`

Additional context: $ARGUMENTS
