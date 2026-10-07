# Refutation pass: K02 "Server-side rule on main with a distinct landing actor"

Checked 2026-10-06 (local). Repo read-only at `/Users/chrisren/Development/.worktrees/wt-cc-205652-27362`, HEAD `593a21fc3`. Nothing was created, fired or changed; every GitHub call was a `gh api` GET.

## Verdict

**Not refuted. `trial` stands; my conviction 45% (proposer 40%).**

The three facts the row rests on hold against primary sources, and the assumption the proposer called riskiest (deploy keys as bypass actors) is resolved in the row's favour by two GitHub primary sources. Four attempts to break it failed; two of them leave caveats that belong in the row (it is an accident guard, not a hard boundary; it moves no throughput). Six factual corrections below.

## 1. Does the cited file:line say what the row claims, today?

| Claim | Check | Result |
|---|---|---|
| "Still open: a VM can push `main`" | `docs/research/off-identity-commits-trace-2026-10-02.md:72-74` (Read) | Verbatim. Also `:62` "Stopped by instruction, not closed mechanically". |
| Trace doc ruled out only the Enterprise author-email rule | same file `:86-95` | Confirmed: section 5 discusses only the ruleset *metadata restriction*. No mention of "Restrict updates", bypass lists or deploy keys anywhere in the file. |
| Docs: use branch protection or rulesets; applied to "the GitHub access you connected" | `/tmp/cloud-blog-eval/doc-cloud-environments.md:242`, `.c1-doc-security.md:103`, `doc-routines.md:332` (sed) | All three verbatim. `:242`: the proxy "doesn't limit which branches a push can update". |
| No ruleset, no protection | `gh api repos/renchris/<repo>/rulesets` and `/branches/main/protection`, run by me 2026-10-06 | `[]` and HTTP 404 on **both** repos (see correction C1). `/keys` returns 0 deploy keys on both. |
| Private, owner User, plan pro | `gh api repos/renchris/claude-infrastructure-private` -> `private:true, owner.type:User`; `gh api user` -> `plan.name:"pro"` | Confirmed for the origin repo. |
| VM pushes with the operator's gh token, cited `scripts/cloud-websetup-drive.sh:22-27` | Read `:1-70` | **Citation drift** (C2): `:22-27` is trap T3 (never infer success from a clean pane). The supporting lines are `:2` (purpose), `:28-29` ("Connected as renchris"), and `doc-web-quickstart.md:93` ("reads the token that `gh auth token` prints ... sends the token to Anthropic"). The claim itself is right. |

## 2. Does the primary external source say what the row claims?

- **Plan eligibility, confirmed.** docs.github.com about-rulesets: "Rulesets are available in public repositories with GitHub Free and GitHub Free for organizations, and in public and private repositories with GitHub Pro, GitHub Team, and GitHub Enterprise Cloud." (curl 2026-10-06, same sentence on all three ruleset pages).
- **"Restrict updates", confirmed.** available-rules-for-rulesets: "If selected, only users with bypass permissions can push to branches or tags whose name matches the pattern you specify."
- **Bypass is opt-in, including for the repo admin.** about-rulesets: "you can allow certain users to bypass ... users with a certain role, such as repository administrator". So the operator's token is refused unless the admin role is listed. This is what makes the Claude docs sentence "a rule that access can bypass doesn't block" work in our favour.
- **Deploy keys ARE bypass actors. The proposer's riskiest assumption is resolved on documentation.**
  - GitHub changelog 2024-04-30: "Deploy keys are now supported as a bypass actor in repository rules, allowing additional granularity for your automations. Previously for deploy keys to bypass a ruleset the Repository Administrator role was required." <https://github.blog/changelog/2024-04-30-repository-updates-april-30th-2024/>
  - REST reference, `bypass_actors[].actor_type`: "Can be one of: Integration, OrganizationAdmin, RepositoryRole, Team, DeployKey, User"; "If actor_type is DeployKey, this [actor_id] should be null"; "pull_request is not applicable for the DeployKey actor type"; "OrganizationAdmin is not applicable for personal repositories". <https://docs.github.com/en/rest/repos/rules>
  - The proposer's observation is accurate about the page it fetched: the three ruleset UI pages contain 0 occurrences of "deploy key" (measured: `grep -c -i` on the curl copies). The UI list is stale relative to the REST schema.
- **Still unverified (what the trial is for):** that `DeployKey` bypass is honoured on a *user-owned* Pro private repo, and that a push from a cloud VM through Anthropic's proxy is refused by the rule. Both are documented, neither observed here. The REST text excludes only `OrganizationAdmin` for personal repositories.

## 3. Is the pain point still open as of the newest dated source?

Open, and no longer tracked.

- Newest statements: trace doc (2026-10-02) and `scripts/postland-verify.sh:4032-4038` (landed in `13d8a9d98`, 2026-10-01): "This cannot PREVENT one; it makes the next one LOUD within one 5-minute tick".
- `git log --since=2026-10-01 -i --grep` for ruleset / branch protection / deploy key / off-identity / CLAUDE_CODE_REMOTE returns only `13d8a9d98`. Nothing since closes it.
- Backlog row `8f4eae55a0c7` is `done` (closed won't-do for the Enterprise reason); no open row mentions a ruleset, branch protection or deploy key (measured: `bin/cc-backlog list --all --json`, 4,241 rows scanned).
- Observed incidence since the brief change: **0 of 2,817** commits on `origin/main` since 2026-09-05 carry `noreply@anthropic.com` as author or committer, and there is exactly 1 distinct author email in that range (measured: `git log origin/main --since=2026-09-05 --format='%ae|%ce'`). Last such commit: `da7ac9183`, 2026-09-04T18:07Z, matching trace doc `:70`.

So: prevention open, detection closed, zero recurrences in 32 days.

## 4. Would it move landed rows per unit of quota?

No. It is a guard on trunk integrity, not a throughput lever.

- Supply is the binding constraint: 4,241 rows = 4,120 done, 120 blocked, **1 open** (measured: same `cc-backlog` call). With few fires, exposure to a VM pushing `main` is small right now.
- What it buys is operator attention on the tail: the last occurrence left 93 commits whose cleanup needs a force-push of `main` that is still an open operator decision (trace doc `:97-100`).
- It is the only candidate whose enforcement does not depend on the VM cooperating. K01 (refuse the push arm of `ship-land.sh` under `CLAUDE_CODE_REMOTE`) covers the path that actually fired, but a raw `git push origin HEAD:main` from a VM never touches `ship-land.sh`, and K01's own riskiest assumption (the env var is set in sessions created through the private create path) is unverified. K02 holds regardless of what loads in the VM.

## 5. Attempts to break it, and how each came out

| Attack | Evidence | Outcome |
|---|---|---|
| We already do it | rulesets `[]`, protection 404, 0 deploy keys, both repos (measured) | Fails. Nothing exists. |
| Desk and VM are already distinct actors, so a simpler rule suffices | `git config`: `credential.https://github.com.helper = !/opt/homebrew/bin/gh auth git-credential`, remote is HTTPS; `/web-setup` uploads `gh auth token` (`doc-web-quickstart.md:93`) | Fails, and sharpens the row: desk and VM use **the same OAuth token**. No rule can tell them apart until one side changes credential. |
| The change breaks the land arm (the measured bottleneck) | Lands use `git worktree add` (`scripts/desk-land.sh:149`), so one `remote.origin.pushurl` in the shared config covers every worktree. `push_failure_kind` (`scripts/ship-land.sh:492-510`) already matches `ssh:` transport wording and keys non-ff on `! [rejected]` plus a fast-forward reason, so a rule rejection (`! [remote rejected]`) classifies as "refused", which is correct. No executable `gh pr merge` or contents/refs API write in `scripts bin hooks` (measured: `git grep`, 0 hits). `.github/workflows/hermetic.yml:71-72` is `contents: read`; `diagrams.yml` has no push step. | Fails. No main-updating path other than `git push` over `origin` was found. Not exhaustively proven: 48 `git push` mentions across 20 files were not each traced. |
| The rule does not actually stop a VM | `gh auth status`: token scopes include `repo` and `admin:public_key`; `gh api repos/...` reports `permissions.admin:true`. Claude docs `:242`: proxy substitutes "your real credentials" on API requests to attached repositories. | **Partly lands (reasoning, not observed).** The rule stops the `git push` accident, which is the class the trace doc describes ("a VM that ignores the brief, or a brief regression"). It is not a hard boundary: the same proxied token can administer the repo, so a VM could in principle edit or delete the ruleset through `gh api`. See C5. |

## 6. Corrections to the row

- **C1. Two repos, and the trace doc names the wrong one.** `renchris/claude-infrastructure` (the name at trace doc `:93`) is a **public** repo created 2026-09-27, the projection pushed by `scripts/public-publish.sh:247`; its `main` tip is `882e2f2ef`. The working origin is `renchris/claude-infrastructure-private` (`private:true`, created 2026-03-24, `main` = `593a21fc3` = local `origin/main`). The ruleset belongs on `-private`. The row's "repo private" is true only of that one.
- **C2. Citation.** `scripts/cloud-websetup-drive.sh:22-27` does not support the token claim; use `:2`, `:28-29` and `doc-web-quickstart.md:93`.
- **C3. Riskiest assumption is stale.** Deploy keys have been ruleset bypass actors since 2024-04-30 (changelog and REST schema above). The residual risk is narrower: personal-repo behaviour and the proxied VM push, both unobserved.
- **C4. "Not the operator's user identity" understates the work.** The desk today is that identity, by the same token. The concrete change is: generate a key, add it as a write deploy key on `-private`, point `remote.origin.pushurl` at an SSH host alias for it, then enable the rule. `DeployKey` bypass has `actor_id: null`, so it admits *every* deploy key on the repo.
- **C5. Scope of the guarantee.** Say "refuses a VM's `git push` to `main`", not "closes the route". Because `/web-setup` gave the VM an admin token, the admin API path stays open.
- **C6. Coverage is per repo.** A deploy key grants access to a single repository (GitHub deploy-key docs), and `scripts/dispatch-projects.conf` lists three dispatchable projects (`claude-infrastructure`, `doc_classifier`, `reso-management-app`). Each needs its own key and rule if the cloud venue serves it.

## 7. Alternatives considered

| Alternative | Why not preferred |
|---|---|
| Classic branch protection with "restrict who can push" | Organization-only. about-protected-branches (curl 2026-10-06): "You can enable branch restrictions in public repositories owned by a GitHub Free organization and in all repositories owned by an organization using GitHub Team or GitHub Enterprise Cloud." The repo is user-owned, so rulesets are the only Pro path. This is why the Claude docs phrase "branch protection rules or rulesets" reduces to rulesets for us. <https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches> |
| Invert it: keep the desk on the user token, give VMs a non-admin identity (machine-user collaborator, bypass list = operator as `User` actor, available since changelog 2026-05-07) | Leaves the land credential untouched and would be a hard boundary (VM token is not admin). Costs a second GitHub account and re-running `/web-setup` on three linked accounts (`~/.claude/autonomy/websetup/next{2,3,4}.linked`, measured `ls`). Worth naming as arm B of the trial; not checked further. |
| Switch VM access from `/web-setup` to the Claude GitHub App | Unverified how rulesets evaluate that token; the repo's own records call the App install state "UNKNOWN" (`docs/plans/MASTER_STRANDED_WORK.md:820`). |
| "Require signed commits" on `main` | Would need every local commit path to sign; `git config` shows no `commit.gpgsign` or signing key (measured). Larger change than a push URL. |
| Rely on K01 plus the pager | Covers the path that fired; leaves the raw push open and depends on an unverified env var. Reasonable if the trial is declined. |

## 8. Safe shape for the trial (described, not run)

Target a throwaway branch pattern (for example `ruleset-probe/*`) on `-private`, not `main`, so the land arm is never at risk: (1) user-token push refused, (2) deploy-key push admitted, (3) one cloud session's push to that branch refused. Step 3 spends one cloud session and is the only quota cost. "Evaluate" enforcement mode appears in the docs only next to metadata restrictions; its availability on Pro was not established, so the probe should not depend on it.

## 9. Uncertainties

- `DeployKey` bypass on a user-owned repo: documented by omission of an exclusion, not observed.
- VM push refusal through Anthropic's proxy: documented, not observed.
- Whether a VM can reach the ruleset admin endpoints through the proxy: inferred from the documented credential substitution and the token's scopes.
- Whether another machine or clone of the operator's lands to `main` outside this checkout's config: not checked.

## Sources

- <https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets>
- <https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets>
- <https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/creating-rulesets-for-a-repository>
- <https://docs.github.com/en/rest/repos/rules>
- <https://docs.github.com/en/authentication/connecting-to-github-with-ssh/managing-deploy-keys>
- <https://github.blog/changelog/2024-04-30-repository-updates-april-30th-2024/>
- <https://github.blog/changelog/2026-05-07-repository-rulesets-user-bypass-and-branch-renaming/>
- Text copies of the fetched pages: `/tmp/cloud-blog-eval/scratch/k02/*.txt`
