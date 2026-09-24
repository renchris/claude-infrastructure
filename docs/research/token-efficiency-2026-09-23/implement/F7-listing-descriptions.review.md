# F7-listing-descriptions: adversarial review

Reviewed 2026-09-23 against the worktree diff of the owned paths only.

## Verdict

The edit is correct and in scope. All 55 files change only their `description` field. Every
description meets its length limit, every frontmatter now parses as strict YAML, and the simulated
listing drops from 48,406 to 22,885 chars, fitting the 30,000 budget with 63 of 63 own entries
described. No blocking defect was found. The main gap is that nothing stops the descriptions from
growing back.

## What was checked, and how

| Check | Method | Result |
|---|---|---|
| Scope | For each changed file, compared `git show HEAD:<f>` with the worktree: body after the frontmatter byte-equal, and every frontmatter key other than `description` equal when parsed with `yaml.safe_load` | 55 files. Body unchanged and other keys unchanged in all of them. The 7 files whose old frontmatter was not strict YAML were checked with `git diff -U0`: one `description` line changed, nothing else |
| Length limits | Parsed length of the new `description` | Skills and commands: max 250 (cc-version-audit, exactly 250). New one-liners for the six commands with no frontmatter: 135-147. Agents: 229 / 249 / 251 (total 729) |
| Strict YAML | `yaml.safe_load` on every owned frontmatter | 0 failures (7 before). The only escapes used are 12 instances of `\"` inside double-quoted scalars |
| Listing before/after | `/tmp/f7_verify.py` run on the worktree, and on a `git archive HEAD` export, with `~/.claude-secondary/.claude.json` scores | Before: 48,406 full, rendered 29,991 in priority mode, 40/63 own described. After: 22,885, fits, 63/63 described, 7,115 chars headroom. The implementer reported 36/63 and 22,992. The difference comes from score decay since their run and another worker's edit to the compact-memory description |
| Trigger phrases seen in prompts (`listings_raw/triggers.json`) | Compared against the new text | Kept: "Not logged in" (account-relogin), "silver platter", "stuck", "switch accounts", "fable". Reworded: "update the plan" is now "updating a plan". Dropped: limit-recover's "Not logged in · please run /login" (see minor 4) |
| Claims in the new descriptions | Grepped bodies, and old descriptions where the claim came from them | desk/claude-desk, pr's 400 words, ship's backup step, account-relogin's email-code fallback, permission-harvest's cc-do step, the outlook-cleanup soak, the Signal aesthetic and the red-team gate are all in the bodies. evolve-skill's "~$2-10" and repo-wiki's "15 styles" come from the old descriptions |
| Consumers | `git grep` for description parsers and for mirrored copies of the old description text | No executable code reads these descriptions. `tests/agents-omit-claudemd.bats` test 3 checks only a length ceiling. No mirrored copies exist |
| Shell / Python | — | No shell or Python files changed, so bash -n, shellcheck and py_compile do not apply |

Tests run (HOME set to a scratch directory, `nice -n 10`):

- `agents-omit-claudemd.bats`: plan 1..3, 1 failure. Test 2 fails on `workflow-lean.md`, another worker's file. The three F7 agents pass tests 2 and 3.
- `slash-command-keywords.bats`: 1..3, 0 failures.
- `desk-brief-ssot.bats`: 1..24, 0 failures.
- `completion-assert.bats --filter 'KILL-SWITCH isMeta'`: 1..2, 0 failures. This test feeds the whole of `commands/ship.md`, now with frontmatter, in as a command body.
- `session-continue.bats --filter '(a2)'`: 1..5, 0 failures.
- `install-mirror-symlink.bats`: 1..7, stopped by the 240 s timeout after 2 passed and 0 failed. It tests symlinks, not description text.

## Findings

**Major 1: nothing guards against regrowth.** No test was added. Test 3 of `agents-omit-claudemd.bats`
still allows 1367 / 885 / 532 bytes, so the three agent descriptions could grow back by about 2,000
chars without a failure. No test pins skill or command descriptions to 250 chars, or to strict YAML.
The listing already grew to 49k once, and a regrowth past about 30k silently brings back name-only
entries. There is no mutation control either, so no current test fails if this diff is reverted.
The fix, which needs files outside F7's ownership:
- Add a hermetic `tests/skill-listing-budget.bats`. It should parse `skills/*/SKILL.md` and
  `commands/*.md` and assert: description ≤ 250 chars, or ≤ 150 for a command whose description
  was derived from its body; strict YAML; and a repo-owned listing total at or below a stated
  headroom line. Prove it goes red by running it against `git show HEAD~:<file>` copies.
- Lower the test-3 ceilings to the new lengths (229 / 249 / 251 plus a small margin).

**Minor 2: line-number citations into `commands/ship.md` are now off by 3.** The new 3-line
frontmatter moved "stop here" from line 42 to 45, and "git push origin HEAD:<trunk>" from 43 to 46.
These comments now point at the wrong lines:
- `hooks/completion-assert.sh:193`
- `hooks/session-continue.sh:371`
- `hooks/ship-rail-push-allow.sh:13`
- `tests/completion-assert.bats:1907`
- `tests/session-continue.bats:235`
- `docs/SHIP-RAIL-PUSH-ALLOW-ACTIVATION.md:30`
- `docs/activation/pending-activation/05-ship-rail-push-allow-activate.sh:6`

`hooks/activation-watch.sh:457` also says the file is 55 lines; it is now 58. Re-key each citation
on its quoted phrase rather than on a new number, as `docs/lessons/superseded-stranded-and-the-falsifier-cannot-tell-them-apart.md` (c) says. All of these files are outside F7's ownership.

**Minor 3: `ship`'s "Invoking it authorizes the push" is now read before invocation.** The listing
shows this sentence to the model before any call. The body says it about a user typing `/ship`. In a
repo whose CLAUDE.md says landing costs money, a model could read its own Skill call as the
authorization. Suggested fix: "Typing /ship is the user's authorization to push", or drop the
clause, which the body already carries.

**Minor 4: limit-recover and recover lost their error-string triggers.** The dropped strings include
"You've hit your session/weekly limit", "API Error: Can't reach the API server" and "agent stalled on
all N attempts". `triggers.json` counts only typed prompts. These strings reach the model as tool
output and task notifications, which that measurement cannot see, so "unused" is not established for
them. limit-recover had 11 Skill calls, which the model makes. Before rollout, check what preceded
those 11 calls with `listings_usage.py`. If error text did, restore one or two literal strings. There
is room: 247 chars against 250.

**Minor 5: the saving is an upper bound.** 29% of listings carry reso-only skills
(`measure/listings.md` gaps). Those contexts stay at about 31k, over the budget, and save nothing, so
the expected saving is about 71% of the stated $199 / $104 per 14 days (about $141 / $74). The
implementer did flag reso. Fixing the live-only `cafe-wifi-optimization` description (frees about
1,300 chars) would bring reso under the budget too.

**Minor 6: `outlook-cleanup` still renders about 440 chars.** Its `when_to_use` field (273 chars) is
appended after " - ". The task forbade editing other frontmatter keys, so this remains as residual
text. Fold it into the description in a follow-up.

**Minor 7: one open issue in the implementer's report is refuted.** It says deploy-check, fix-lint,
pr, review, scaffold and ship "may become callable through the Skill tool" once they have a
description. All six are already in the live model-invocable listing, most of them name-only, so
nothing about invocability changes. What changes is that five of them are now described, which makes
a model-initiated call somewhat more likely.

**Minor 8: two items touched the compact-memory description.** Another item rewrote the
`commands/compact-memory.md` description to about 224 chars, alongside its body edit. By the letter,
that field is F7's: the exclusion names `skills/compact-memory`, which does not exist. The
implementer's note that it is "337 chars, left alone" is now stale. The lead should commit that
description change with exactly one of the two items.

**Minor 9: frontier-derivation dropped a condition.** It now says "the lead passes model \"fable\""
without the old "while frontier_access.active". deep-research keeps "may … per model-config.yaml". A
small loss of accuracy.

**Minor 10: the evidence script lives in `/tmp`.** `/tmp/f7_verify.py` backs every before/after
number and will not survive a reboot. Copy it to `docs/research/token-efficiency-2026-09-23/scripts/listings_f7_verify.py`.

**Accepted: no runtime flag.** Description text cannot be switched per session. Rollback means
reverting the commit, and the A/B comparison has to be before-and-after on `listings_usage.py`.
