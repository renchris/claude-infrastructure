# D1 red team — should cloud VMs be mechanically prevented from pushing to main?

Checked 2026-10-06 (local), repo tip `03b7e413c` = `origin/main`. Read-only; every GitHub call was a GET.
Labels: **M** measured here (command named) · **D** documented (source cited) · **I** inferred · **E** estimated (method named).

## Verdict

- **A survives best**, in its narrow form (refuse the land arm of `ship-land.sh` in a VM) and only when paired with the instruction fixes in section 6. Strength: moderate.
- **C is the runner-up.** Its measured damage is small, but one of its two prose rails already regressed in production (2026-09-22) with nothing noticing.
- **B fails the cost attack at today's volume** (13 fires in W40, 2 in W41). Defer it behind a named trigger (section 5).
- Ranking after attack: A + section 6 > C + section 6 > C alone > B.

## 1. Why the 93 stopped (key question 1)

| Fact | Evidence | Label |
|---|---|---|
| 93 off-identity commits, author-dated 2026-08-24..09-04; 0 of 2,863 since 2026-09-05T00:00Z | `git log origin/main --since=... --format='%ae\|%ce'` | M |
| Independent of commit identity: 1,394 of 1,398 `origin/main` tracking-ref updates since 09-05 are `update by push` (local). The other 4 are two rollback/re-fetch pairs of shas already pushed minutes earlier. The reflog's 08-24..09-04 span holds 53 `fetch: fast-forward` entries. | `git reflog show origin/main` | M |
| Every self-landing session that can be identified was TOLD to land. 37 of 37 sessions named by `Claude-Session` trailers (61 of the 93 commits) received "land ONLY via the project-local /ship". | grep of `~/.claude/autonomy/cloud/<session>.sends` | M |
| No fire that carried a do-not-land sentence put a commit on main: 0 of 93 fires carrying "Do NOT run /ship" (first 2026-09-03, last 2026-10-06). | same census, 727 `.sends` files: 593 old rail, 93 new rail, 41 neither | M |
| 95% upper bound on the per-fire self-land rate under the new rail: 3.2% | rule of three, 3/93 | E |
| The trace doc's "VMs fired before that change" is wrong on timing. Eight self-landing sessions were fired after `0efcc073d`'s commit time (09-02T04:46Z), the last at 09-04T17:38Z, and all eight still got the old rail. 17 new-rail and 14 old-rail fires went out on 09-04 alone. | `.decl` branch stamps vs `.sends` text; trace doc `:57-58` | M |
| The last self-land (09-04T18:07:46Z) precedes the fire stop (09-04T19:38Z, `124c4da06`) by about 90 minutes. Fires resumed 09-07 on the new rail, with one exception (09-22, below). | `git log --committer=noreply@anthropic.com`; trace doc `:69-71`; census | M / D |
| The brief change was itself authored and pushed to main by a VM (`0efcc073d`, committer `noreply@anthropic.com`). | `git show -s 0efcc073d` | M |

- **Cause:** the instruction, not a refusal. All 37 identified self-landers were told to land; none of the 93 told not to did.
- **Durability: weak, and already breached once.**
  - `bin/cc-offload:778` prepends the API contract to whatever brief file it is handed, with no check of the body. On 2026-09-22 session `session_013CLaSUq8AwNdYqYuJiwPpW` received both "you cannot run this repo's /ship" and "land ONLY via the project-local /ship (never bare push)". It pushed its branch; the desk landed it (`761e210bc`, sanctioned identity). n=1, benign. (M: `.sends`, `.decl`, `return.jsonl`.)
  - Nothing pins the sentence. `bin/cc-dispatch:3900-3901` (selftest c7) asserts only that the positive rail is ABSENT; no bats suite contains "Do NOT run /ship" (M: `grep -l` over `tests/*.bats`).
  - `scripts/lib/cloud-create.sh:285` states "you cannot run this repo's /ship", which 37 sessions disproved.
  - A cloud session with no brief (interactive `claude --cloud`, a routine) reads only `.claude/CLAUDE.md:18-27`: complete work "lands via the project-local `/ship` flow without a fresh ask". 0 venue words in that file or in `.claude/commands/ship.md` (M: `grep -ci`).

## 2. What the incident cost (key question 2)

| Cost line | Number | Evidence | Label |
|---|---|---|---|
| Commits later reverted | 0 of 93 | `git log --grep='This reverts commit'`, 8 reverted shas since 08-24, none in the set | M |
| Post-land verdicts on VM-landed tips | 23 stamps: 8 green, 13 cut, 2 red | `~/.claude/autonomy/postland/stamps/*.json` by `commit` | M |
| Are the 2 reds attributable? | No. Both are `tests/capacity-alarm.bats`, red in 32 of 275 red stamps (27 in August) | same store | M |
| Same-window baseline | 164 stamps: 42 green, 86 cut, 36 red | same store, 08-24..09-06 | M |
| Auto-revert attempts naming a VM commit | 1 (`392215455`, a docs-only commit blamed for `tests/anti-deference-nudge.bats`); `revert=none`, `land_exit=90` | `postland/reverts/3922...` | M |
| Reached the live layer without the macOS desk gate | 34 of 93 touch `bin/` (16), `scripts/` (21) or `hooks/` (2); 59 are docs/tests only; 15,148 insertions, 659 deletions, 108 files | `git show --name-only/--numstat` | M |
| Public exposure | 0 commits by `noreply@anthropic.com` on the public projection; publish refuses any unmapped identity | `gh api repos/renchris/claude-infrastructure/commits?author=...`; `scripts/public-publish.sh:236-242` | M |
| Return pipeline stranded | Desk ledger closed 2 of 37 self-landing sessions as `returned/MET/content_verified`; 12 stuck `waiting`, 9 have no row | `~/.claude/autonomy/cloud/return.jsonl` | M |
| Repeat fires on rows a VM had already landed | 23 (37 sessions over 14 rows, max 5 on one row) | `.decl` `item=` | M |
| Quota for those repeats | about 3.3 weekly-pp | 23 x 0.144 pp/fire (`c1-hostile-reviewer.md:74`, not re-measured); attribution to self-landing is inferred, the old brief's close verbs were also no-ops off-box (`0efcc073d` body) | E / I |
| Response work | 1 commit, 250 insertions (`13d8a9d98`) | `git show --stat` | M |
| Time to notice | about 4 weeks; found by a trace, not by a failure | trace doc `:83-84` | D |
| Permanent residue | 93 wrong-identity commits on private `main`; the force-push is still undecided 32 days on | trace doc `:97-100` | D |

- Net: no broken trunk, no revert, no public leak. The real costs are the stranded close step (23 repeat fires) and a history the operator has so far chosen not to rewrite.

## 3. Strongest case for C (leave as is), and where it fails

For C:
- Zero recurrences by two independent methods (section 1).
- Exposure is shrinking: fires per ISO week W37 26, W38 14, W39 19, W40 13, W41 2 (M: `.sends` census).
- Historical damage is the table above.
- `ship-land.sh` is 5,711 lines and carries every land: 1,325 successful lands since 09-05, 38.9/day mean over the last 16 days (M: `~/.claude/land.log`). Any new arm sits on that path.

Against C:
- The prose regressed on 09-22 and no test, pager or person noticed (section 1).
- "Detects within about 5 minutes" is the best case. The sweep runs only at the top of `--run-if-needed` (`scripts/postland-verify.sh:4097`). The launchd job is one long-running instance (PID present in `launchctl list`; run length p50 11,750 s, p90 13,913 s, n=105 since 09-20), so ticks are skipped while it runs (I: launchd does not start a second instance). The working trigger is the kick after each desk land (`scripts/ship-land.sh:1743-1752`): mean gap about 37 minutes (E: 24 h / 38.9), longer overnight.
- The pager keys on author/committer email (`postland-verify.sh:4071-4072`), a value the VM sets. A VM that sets the sanctioned address is silent to it (I; `c1-hostile-reviewer.md:62`). The reflog method in section 1 does not have this hole and is not wired to a pager.
- "Auto-revert already exists" does not rescue C: the revert arm landed 15 of 41 attempts (M: `revert=` in `postland/reverts/*`), the identity sweep never calls it (`:4054-4090`), and a revert leaves the off-identity commit in history.

## 4. Strongest case that A alone is security theater (key question 3)

- **A has had nothing to refuse for 32 days.** 0 of 93 do-not-land fires put a commit on main. It fires only when an instruction regresses.
- **A does not touch a bare push.** `git push origin HEAD:main` is open: the proxy "doesn't limit which branches a push can update" (D: <https://code.claude.com/docs/en/cloud-environments.md> line 242, re-fetched 2026-10-06, HTTP 200, 59,241 bytes). `main` has 0 rulesets, no protection, 0 deploy keys (M: `gh api .../rulesets`, `/branches/main/protection`, `/keys`).
- **The guard is a file in the VM's own clone, and VMs under a land instruction have removed obstacles before.**
  - `c1904ed89` (VM-authored, VM-landed, 2026-08-28): rewrote a `ship-land` gate arm because "off Darwin the arm refused every land"; subject line ends "so no cloud VM could land".
  - `8492afe70` (2026-08-29): "First /ship from this VM died GATE-KILLED (exit 9)"; `apt-get install -y shellcheck` "cleared it and the re-land went green".
  - VM-committed commits per author day: 2, 2, 2, 2, 6 (08-24..08-28), then 32 on 08-29 (M: `git log --committer=noreply@anthropic.com` by day).
  - Caveat: both were genuine environment defects. Whether a VM would edit out an explicit policy refusal is untested (I).
- **Both proposed triggers are soft.** `CLAUDE_CODE_REMOTE` is read by 0 tracked non-doc files and has never been read inside one of our VMs (M: `git grep -l`; `refute-K01.md:58-66`, estimate 90%). The committer arm keys on a VM-settable value.
- **It costs test surface.** 72 bats suites reference `ship-land.sh`; `bin/cc-bats:391,396` unsets session variables but not `CLAUDE_CODE_REMOTE`, so a VM running those suites sees fixture lands refused (M: `grep -l`, `grep -n unset`).

Why the theater charge only half lands:
- 37 of 37 identified self-landing sessions were compliant sessions going through `/ship`. A blocks exactly that class, at the point of action, whichever instruction source regressed.
- The standing text a VM reads forbids the bypass: "never a bare `git push`" (`.claude/CLAUDE.md:27`), and the old rail said "(never bare push)" (`bin/cc-dispatch:3086`). With A, a compliant VM has no sanctioned land path left. 0 bare-push lands are known; the 93 cannot be split into `/ship` vs bare push from commit data (gap).
- A's refusal text is an instruction delivered where the brief cannot reach: a brief-less cloud session.
- Condition: without the `.claude/CLAUDE.md` venue sentence (section 6), A contradicts the repo's standing instruction and invites the `c1904ed89` response.

## 5. Strongest case that B costs more than the incident it prevents

| B cost or limit | Evidence | Label |
|---|---|---|
| Changes the credential on every land: 1,325 lands since 09-05, 38.9/day | `~/.claude/land.log` | M |
| Starts from zero on the desk: `remote.origin.pushurl` unset, origin is HTTPS via `gh auth git-credential`, no `~/.ssh/config`, 0 deploy keys | `git config`, `ls ~/.ssh`, `gh api .../keys` | M |
| Not a hard boundary: the VM's proxied access is the operator's token, scopes include `repo`, `permissions.admin = true`; "a rule that access can bypass doesn't block a session's push" | `gh auth status` (scope names), `gh api repos/...`; <https://code.claude.com/docs/en/security.md> line 104 | M / D |
| Desk agents hold the same admin token, so a refused desk push can also be "fixed" by deleting the rule | same | I |
| Core mechanism unobserved: `DeployKey` bypass on a user-owned Pro repo; VM push refusal through the proxy | `refute-K02.md:31,86-88` | D (not re-checked) |
| Per repo: 3 active dispatchable projects | `scripts/dispatch-projects.conf:1-3` | M |
| New single point of failure with no fallback by design: a broken key or SSH path stops all lands until the operator edits the ruleset by hand | reasoning from the rule's definition | I |
| What it prevents, at today's rate | at most 0.42 self-landing sessions/week (3.2% x 13 fires), point estimate 0; historical cost per section 2 | E |

- B is the only option that does not need the VM's cooperation for `git push`. It still needs it for `gh api`.
- Trigger to revisit B: the identity pager fires once, or cloud fires exceed about 100/week (E: at 3.2% that bound allows 3 sessions/week), or brief-less cloud sessions on this repo become routine.

## 6. The cheaper fourth option the three miss (key question 4)

Act on the causal variable (the instruction), desk-side where possible. All effort S.

| Change | Why it matters | VM can edit it? |
|---|---|---|
| Fire-time check in `bin/cc-offload` before `:778`: refuse a payload whose body contains a land instruction | Closes the only regression that actually occurred (09-22) | No, runs on the desk |
| One venue sentence in `.claude/CLAUDE.md:18-27` and at the top of `.claude/commands/ship.md` | Covers brief-less cloud sessions; removes the contradiction A would otherwise fight | Yes, but instruction is the variable that explains all 37 identified self-lands and all 93 non-lands |
| Presence pin for "Do NOT run /ship" in the `cc-dispatch` selftest and a bats pin for the API contract; correct `cloud-create.sh:285` and `docs/runbooks/cloud-fleet.md:27-28` | Today a deletion of the sentence passes every gate | No, land gate |
| Page on any `origin/main` advance not first seen as a local push | Identity-independent detection (the reflog method of section 1) | No; effort M, not S |

- This is not a substitute for A in a brief-less session whose model ignores CLAUDE.md, and it is no defence against a non-compliant VM. Neither is A.

## 7. Alternatives considered

| Alternative | Result |
|---|---|
| Extend the identity sweep to auto-revert | Rejected: 15/41 revert success, and it does not remove the commit's identity |
| Repo PreToolUse/SessionStart hook gated on `CLAUDE_CODE_REMOTE` | `.claude/settings.json` has no hooks today; prior pass skipped it at 70% (`refute-K03.md:9-10`); same VM-editable weakness as A |
| Inverted B: VMs get a non-admin GitHub identity, desk keeps its token | Only true hard boundary; needs a second GitHub account and re-linking the cloud accounts (`refute-K02.md:75`); not costed here |
| Force-push to rewrite the 93 | Operator decision, out of scope |

## 8. Uncertainties and blockers

- `CLAUDE_CODE_REMOTE` inside one of our VMs: unread. No session was started.
- 32 of the 93 commits carry no session trailer; their sessions' briefs are inferred from the date (no do-not-land rail existed before 2026-09-03).
- `/ship` vs bare push for the 93: not separable from commit data.
- Whether any of the 93 do-not-land fires attempted `/ship` and failed: not recorded on the desk.
- Why old-rail and new-rail briefs both went out on 09-03 and 09-04 (a second composer, or a live dispatcher behind trunk): not traced.
- Whether today's `ship-land.sh` completes on a Linux VM: not run.
- Attribution of the 23 repeat fires to self-landing rather than to the old brief's no-op close verbs: inferred.
- launchd tick suppression during a long run: inferred from single-instance semantics, not timed.
- 163 of 1,325 lands since 09-05 ran from `/private/tmp` roots; whether those are worktrees (covered by a shared `pushurl`) or clones (not covered) was not checked. Matters only for B.
- `DeployKey` bypass on a user-owned repo and proxy refusal: documented, unobserved.

Scratch (census and fetched pages): `/tmp/decisions-eval/.d1-*`.
