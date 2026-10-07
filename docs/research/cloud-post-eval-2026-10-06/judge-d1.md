# Decision 1 verdict: should cloud session VMs be mechanically stopped from pushing to main?

Judged 2026-10-06 at repo tip `03b7e413c`. Read-only: no ruleset, key, push or cloud session was created.
Labels: **measured** = I ran it today (command named), **documented** = a primary source says it, **inferred** = reasoned, not observed.

## Recommendation

**Take option A now, in a tightened form, and hold option B in reserve behind a named trigger.** Conviction: **70%**.

The tightened option A is one small change set:

1. **The guard.** The land script (`scripts/ship-land.sh`, line 5538, exit code 2 "preflight refusal") refuses a real land when the environment variable `CLAUDE_CODE_REMOTE` is `true`. Drop the proposed committer-email test (`noreply@anthropic.com`).
2. **A test-fixture exemption.** The guard skips when the remote named `origin` is a folder on the same disk, so the land tests still pass when a cloud session runs them.
3. **Words that agree with the guard.** Add one "not from a cloud session" sentence to the tracked project instructions (`.claude/CLAUDE.md`, lines 18-27) and the ship command file (`.claude/commands/ship.md`); correct the two false sentences ("you cannot run this repo's /ship" at `scripts/lib/cloud-create.sh:285`; "the VM can push its own working branch and nothing else" at `docs/runbooks/cloud-fleet.md:27-28`).
4. **A free measurement.** Add an environment readout to the body of the boot commit every cloud session already pushes (`scripts/lib/cloud-create.sh:291`), so the next ordinary launch proves the variable is really set.

## Why

| # | Reason | Evidence | Label |
|---|---|---|---|
| 1 | Every self-landing we can trace was a cloud session doing what it was told, through the land script. The guard blocks exactly that path. | 37 of 37 identifiable self-landing sessions had been told "land ONLY via the project-local /ship" (red-team census, not re-derived by me). 0 of 93 launches told "Do NOT run /ship" put a commit on main; I recounted the split: 727 launch records, 93 new wording, 593 old wording (`grep -l` over `~/.claude/autonomy/cloud/*.sends`). | measured |
| 2 | Words alone already slipped once, and the standing instructions still say "land". | One launch on 2026-09-22 carried both the do-not-land contract and the old land instruction (`grep -l`, 1 file). The tracked project instructions and the ship command file mention cloud 0 times (`grep -ci`). 0 test files pin the do-not-land sentence (`grep -l` over `tests/*.bats`). | measured |
| 3 | The environment-variable trigger is safe on the Mac; the email trigger is not reliable. | Anthropic's docs: the variable is `true` in a cloud session and "never `true` locally" (`code.claude.com/docs/en/cloud-environments.md` lines 475-493, `env-vars.md` line 360; re-fetched today, HTTP 200), and they tell Claude to read the sibling session-ID variable from a shell command (lines 333-340). Unset in this session (`env`, 0 keys). Email: 48 of 341 surviving cloud branches (14.1%) never commit as `noreply@anthropic.com`; 11 of 104 cloud-made commits on main carry the operator's own address (`git log` grouped by committer and time zone). | documented / measured |
| 4 | Option B costs more than it buys today and is not a real barrier. | Cloud sessions act with the operator's own GitHub token (docs lines 240-241), that token is a repo admin (`gh api`, `permissions.admin: true`), and admins can edit or delete rulesets (GitHub "managing rulesets" page). B also moves every land (about 39 a day, 100 worktrees sharing one git config; researcher-measured) onto a new credential, and deploy-key bypass on a personally owned repo is documented only by not being excluded. Nothing outside the Mac has moved main since 2026-09-05: 0 of 2,863 commits carry a UTC stamp; 1,409 of 1,413 updates of the main tracking ref are local pushes and the other 4 re-observe local pushes (`git log --date=format:%z`, tracking-ref log). | documented / measured |

## Options

| Option | Outcome | Cost |
|---|---|---|
| A as written (guard keyed on the variable and/or the `noreply` email, plus runbook fix) | Stops a compliant session's land. The email half misses about 1 in 7 cloud sessions and would refuse about 219 land tests (static estimate, 21 suites) when a cloud session runs them. | Small. Risk: the last refusal of this shape (2026-09-28) broke automated cloud lands for two days (`scripts/cloud-return-lane.sh:189-195`). |
| **A tightened (recommended)** | Stops the one path every traced self-land used, including sessions launched with no brief. Does not stop a typed `git push` to main or a session that edits the guard out. | Small, no operator action, no change to the Mac's landing path (0 local or CI processes carry the variable). |
| B (A plus a GitHub rule on main with a deploy key as the only bypass) | Also refuses a typed push to main. Does not stop a session that edits the rule first. Covers 1 of 3 dispatchable repos. | Operator must create a key and a rule by hand; a wrong step stops every land until fixed; the natural wiring silently turns off the local identity check (`githooks/pre-push:81-84`). |
| C (leave as is) | Relies on wording that slipped once and a pager that compares only email addresses (`scripts/postland-verify.sh:4071-4072`), so it cannot see the 11-commit class. | Zero today. |

No option costs money: rulesets are included in GitHub Pro (documented), and the measurement rides a launch that happens anyway.

## What would flip it

**One cloud-made commit reaching main after 2026-09-05 by any route** (the pager, a UTC-stamped commit, or a main update the Mac did not push). That moves me to a server-side rule, preferably the variant where cloud sessions get a non-admin GitHub identity, because B as written leaves the admin token in the session.
Smaller switch, same option: if the boot-commit readout shows the variable is not set in our sessions, change the trigger to "Linux and running as root" (what cloud sessions have recorded about themselves).

## Did the research move the prior?

A 62% to 70%; B 45% to 25%.

- A up: the instruction census (reason 1), the 2026-09-22 slip (reason 2), and zero local exposure (reason 3).
- A held back: the variable has never been recorded by one of our sessions; the email trigger had to be dropped.
- B down: the cloud session holds the admin token that can undo the rule, and the rule's key mechanism is unobserved on a personal repo.

**Disagreement resolved.** The signal researcher leaned toward B because the email trigger leaks 14%. The ruleset researcher and the red team leaned toward A. I confirmed the 14.1% and the 104 count myself, so the facts stand, but I side with the other two on the conclusion: the leak is a reason to drop the email trigger, not to add the rule. The variable trigger does not depend on identity, and B's own protection depends on the session not using a token it holds.

**Corrections to the brief.** Main carries 104 cloud-made commits, not 93: 93 under the wrong identity plus 11 under the operator's own (`git log origin/main --date=format:%z`, all between 2026-08-24 and 2026-09-04). "0 of 2,817" is 0 of 2,863 with an explicit midnight-UTC start. "Detects within about 5 minutes" holds only for wrong-email commits; the red team's 37-minute mean is reasoned, not timed.

## Still unknown, and what settles it

| Unknown | Settled only by | Cheap and reversible? |
|---|---|---|
| Is the variable visible to a shell command in our cloud sessions? | The boot-commit readout on the next ordinary launch (22 launches declared in the last 7 days, `find -mtime -7`). | Yes: one line, no extra launch, revert to undo. |
| Does every land test use a local-folder remote? | Running the 21 land suites once on the Mac with the variable set to `true`. | Yes: local, no cloud session. |
| Will a session told to land edit the guard out? Two sessions rewrote a failing gate in August; both were real defects. | Only a recurrence would show it. The refusal text should say it is policy and name the right action (push the branch). | Not testable safely. |
| Did the 104 arrive through the land script or typed pushes? | Not recoverable from commit data. | No. |
| Does deploy-key bypass work on a personal repo, and can a session edit rulesets through the proxy? | A throwaway-branch rule with one key and three pushes. Needed only if B is triggered. | Cheap, but needs the operator's GitHub settings. |
| Does today's land script even run to completion on a Linux cloud session? | Not run. | Not without a deliberate launch. |

Scratch files I added: `/tmp/decisions-eval/.judge-d1-cloud-env.md`, `.judge-d1-envvars.md`, `.judge-d1-heads.txt`. The repo worktree is untouched.
