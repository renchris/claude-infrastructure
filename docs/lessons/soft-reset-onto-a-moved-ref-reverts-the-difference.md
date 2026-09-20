# `git reset --soft <moved-ref>` builds a commit that REVERTS the difference

**The rule.** `git reset --soft origin/main` re-points HEAD at whatever `origin/main` is *now*
while keeping your index exactly as it was. If trunk moved since your tree was built, the commit
you then make does not say "add my work" — it says **"make trunk look like my stale tree"**, and
every sibling commit in the gap becomes a deletion in your diff. Squash with `rebase` (which
replays only your changes and conflicts when it cannot), or transplant your files explicitly onto
a fresh checkout of trunk. Never with `reset --soft` onto a ref that can move.

**The measurement (2026-09-20, claude-infrastructure).** A session finishing the §4.4 chokepoint
lint ran `git add -A && git reset -q --soft origin/main && git commit`. Trunk had advanced 8
commits since its rebase base. The resulting commit was:

```
 16 files changed, 599 insertions(+), 477 deletions(-)
```

Of those 16 files, **11 belonged to other sessions** and were pure deletions — a whole lesson doc
(66 lines), `hooks/boundary-handoff.sh` (65), `tests/boundary-handoff.bats` (109),
`bin/claude-accounts` (15), two plan docs, and four more suites. Every one had landed legitimately
on trunk minutes earlier. Had it shipped, `/ship`'s land-verify would have reported success: the
paths *were* content-identical to the landed head, because the landed head was the revert.

**The tell, and why it is easy to misread.** The scope check `git diff --cached --name-only
origin/main` DID list all 11 foreign files. It was read as noise. A two-dot diff against a ref
reports differences in **both directions**, so files trunk has and you lack look exactly like
files you deleted. The same asymmetry appears one step earlier and reads as the opposite fact:
`git diff --stat origin/main -- scripts/unattended-path-lint.sh` printed `15 ---------------` for
a file this branch had never opened, which reads as "I deleted 15 lines" and actually meant
"trunk added 15 lines I do not have yet."

**What caught it.** `git show --stat HEAD` before shipping. The insertion/deletion counts are the
cheapest possible audit of a squash and they are the only artifact that states the damage as a
number. Run it on every squash, and read the FILE LIST, not just the total.

**The recovery, which has its own trap.** Do not `git checkout <bad-commit> -- <your files>` onto
trunk blindly: if trunk also changed one of *your* files, you would now revert *that*. Establish
it first —

```
git diff --stat <your-rebase-base> origin/main -- <exactly your files>   # empty ⇒ lossless
```

— and only then transplant. In the incident this printed nothing across 8 commits, so restoring
the five owned files onto a hard reset of trunk lost nothing, and the rebuilt commit read
`5 files changed, 582 insertions(+), 3 deletions(-)` with all 3 deletions verified as the
session's own edits.

**Companions.** `cc-backlog 6110fc45141e` — a correct-looking diagnosis in a stale tree producing
a diff that reverts trunk — is the same failure arriving by a different road: there the staleness
was in the *analysis*, here in the *index*. `absent-from-trunk-has-two-opposite-causes` and
`git-cherry-plus-is-not-absence-from-trunk` are the read-side members of the family.
