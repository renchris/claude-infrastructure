# D1 lens: is option B (ruleset on main, deploy key as only bypass) feasible, and what must the desk change?

Checked 2026-10-06. Observational only: every GitHub call was a `gh api` GET, nothing created, pushed or toggled. Repo read at `/Users/chrisren/Development/.worktrees/wt-cc-205652-27362` (origin/main `03b7e413c`). Labels: **M** measured (command named), **D** documented (source named), **I** inferred. Fetched page copies: `/tmp/decisions-eval/scratch-d1/*.txt`.

## Headline

- B is feasible on documentation and needs **zero mandatory repo code changes**: all 5 land paths end in two `git push origin HEAD:$TRUNK` lines, so one `remote.origin.pushurl` in one shared git config moves every lander. Not observed on a user-owned repo; needs a 3-push probe before it touches `main`.
- B is an **accident guard, not a boundary**: the VM-side credential is the operator's admin OAuth token, and the documented proxy passes REST calls on the attached repo, so the same token can disable the ruleset.
- The obvious way to wire the deploy key (an SSH host alias) **silently switches off the local pre-push identity guard** (`githooks/pre-push:81-84`). Avoidable, but it is a trap the earlier K02 write-up walked into.

## Q1. Availability on a private, user-owned, Pro repo

| Question | Answer | Evidence | Label |
|---|---|---|---|
| Repo facts | `private:true`, `owner.type:User`, plan `pro`, `permissions.admin:true` | `gh api repos/renchris/claude-infrastructure-private`, `gh api user` | M |
| Current server state | rulesets `[]`, rules for main `[]`, protection HTTP 404 "Branch not protected", 0 deploy keys, 1 collaborator (`renchris`, admin) | `gh api .../rulesets`, `.../rules/branches/main`, `.../branches/main/protection`, `.../keys`, `.../collaborators` | M |
| Rulesets on private + Pro | "Rulesets are available in public repositories with GitHub Free and GitHub Free for organizations, and in public and private repositories with GitHub Pro, GitHub Team, and GitHub Enterprise Cloud." | <https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets> (scratch `about-rulesets.txt:147`) | D |
| Pro is the personal-account plan | "GitHub Pro: In addition to the features available with GitHub Free for personal accounts, GitHub Pro includes: ..." | <https://docs.github.com/en/get-started/learning-about-github/githubs-plans> (scratch `plans.txt:160-170`) | D |
| "Restrict updates" | "If selected, only users with bypass permissions can push to branches or tags whose name matches the pattern you specify." No plan caveat on this rule; the only plan caveats on the page are push rulesets (Team) | <https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets> (scratch `available-rules.txt:173-174,148`) | D |
| Deploy key as bypass actor | "Deploy keys are now supported as a bypass actor in repository rules ... Previously for deploy keys to bypass a ruleset the Repository Administrator role was required." | <https://github.blog/changelog/2024-04-30-repository-updates-april-30th-2024/> | D |
| REST schema | `actor_type` "Can be one of: Integration, OrganizationAdmin, RepositoryRole, Team, DeployKey, User"; "If actor_type is DeployKey, this [actor_id] should be null. OrganizationAdmin is not applicable for personal repositories."; "pull_request is not applicable for the DeployKey actor type" | <https://docs.github.com/en/rest/repos/rules> (scratch `rest-rules.txt:479,482,484`); same text in the OpenAPI source, `api.github.com.yaml:101993-102025` | D |
| Org-only caveat | The only personal-repository exclusion in REST, OpenAPI and GraphQL (`RepositoryRulesetBypassActorInput`, `schema.docs.graphql:58460-58500`) is `OrganizationAdmin`. Nothing excludes `DeployKey`. | same sources | D (by non-exclusion) |
| UI docs lag | The four ruleset UI pages mention "deploy key" 0 times; the UI bypass list names roles, teams, GitHub Apps, Dependabot only. Create through REST, not the modal. | `grep -c -i 'deploy key'` on the 4 scratch copies; `creating-rulesets.txt:192-197` | M |
| No dry-run mode | "evaluate is only available with GitHub Enterprise" | `rest-rules.txt:473` | D |
| Feature gate looks open | `GET .../rulesets` returns 200 `[]`, `X-Accepted-OAuth-Scopes: repo` | `gh api -i` | M (that 200 means "enabled" is I) |

- **Not established:** that `DeployKey` bypass is honoured on a user-owned repo. Zero community reports found either way (`gh api search/issues` on `community/community`, 3 queries, 0 hits, M).
- Classic branch protection cannot do this here: "You can enable branch restrictions in public repositories owned by a GitHub Free organization and in all repositories owned by an organization using GitHub Team or GitHub Enterprise Cloud" (about-protected-branches, re-fetched, D). Rulesets are the only route.

## Q2. How the desk pushes today, and every pusher a ruleset would touch

**Transport (M, `git remote -v`, `git config --show-origin`):**

| Item | Value |
|---|---|
| origin fetch and push URL | `https://github.com/renchris/claude-infrastructure-private.git`; no `pushurl`, no `url.*.insteadOf` |
| Credential | `credential.https://github.com.helper = !/opt/homebrew/bin/gh auth git-credential` (in `~/.gitconfig`), username `renchris` |
| Identity on the wire | gh OAuth token, scopes `admin:public_key, codespace, gist, read:org, repo, user, workflow` (`gh auth status`, `X-OAuth-Scopes`) |
| Same token as the VMs | `/web-setup` "reads the token that `gh auth token` prints ... and sends the token to Anthropic" (<https://code.claude.com/docs/en/web-quickstart>, line 93, re-fetched, D). Desk and VM are indistinguishable to GitHub today. |
| Shared config | git common dir `/Users/chrisren/Development/claude-infrastructure/.git`, 100 worktrees (line count of `git worktree list`), `extensions.worktreeConfig` unset: one config governs every lander |
| SSH state | `~/.ssh/config` absent; `id_ed25519.pub` is registered on account `renchris` (boolean compare against `gh api user/keys`); `github.com:22` and `ssh.github.com:443` both answer with an SSH banner (`curl telnet://`); no `sandbox` key in `~/.claude/settings.json` |
| Volume | 719 commits reached `origin/main` in the last 7 days (line count of `git log origin/main --since='7 days ago' --oneline`), about 103 per day (computed) |

**Pushers:**

| Path | file:line | Updates `main` on `-private`? | Blocked by rule? | Needs |
|---|---|---|---|---|
| Land rail | `scripts/ship-land.sh:5248`, `:5330` (`git_net push origin "HEAD:$TRUNK"`) | Yes, the only executable push to trunk found | Yes | pushurl via deploy key; nothing in code |
| `/ship` | `.claude/commands/ship.md:115-119` -> ship-land | via rail | via rail | none |
| Desk land | `scripts/desk-land.sh:200-208` -> ship-land | via rail | via rail | none |
| Handoff land | `scripts/handoff-fire.sh:10729` -> desk-land | via rail | via rail | none |
| Cloud return | `scripts/cloud-return.sh:756` -> `cloud-reconcile.sh:831` -> desk-land (`:134`) | via rail | via rail | none |
| Postland auto-revert | `scripts/postland-verify.sh:3299` -> `$REPO_SHIP` (`:640` "the ONLY pusher"); runs under launchd (`launchd/com.claude.postland-verify.plist`) | via rail | via rail | key usable with no TTY and no agent prompt |
| `scripts/land-lock.sh` | no git network call (`grep`: only `rev-parse`, `:44,:50,:284`) | No | No | none |
| `scripts/deploy-live.sh` | fetch + `merge --ff-only` only (`:2006`, `:2626`) | No (reads) | No | none; fetch URL stays HTTPS |
| `scripts/public-publish.sh` | `:247`, target `https://github.com/$SLUG.git` (`public-publish-tick.sh:50`) | No, pushes the public repo `renchris/claude-infrastructure` | No | none (that repo also has rulesets `[]`, 0 keys, M) |
| Branch prune | `scripts/branch-prune-landed.sh:228` (`push origin --delete`) | No (non-main) | No | rides pushurl; a write deploy key can delete branches |
| Feature-branch pushes | e.g. `scripts/handoff-fire.sh:14085` | No | No | ride pushurl too (side effect: every push from the box becomes a deploy-key push) |
| `bin/cc-bus:757` bare `git push` | pushes the current branch's upstream | Only if run on main | Then yes | 0 automated callers of `cc-bus sync` in `bin scripts hooks launchd` (M, `git grep`) |
| Model-typed `git push origin HEAD:main` | allowed shape in `hooks/ship-rail-push-allow.sh:11-13`, but the settings ask rule still refuses it (`:31-37`) | Yes if it ran | Yes unless SSH-routed | none |
| Owner in the web UI (edit file, merge PR) | n/a | Yes | Yes, owner is not in the bypass list under B | accept, or flip the ruleset off for the moment |
| GitHub Actions | `hermetic.yml:71-72` `contents: read`; `diagrams.yml` has no commit or push step | No | No | none |
| API ref writes | 0 hits for `gh pr merge`, `git/refs`, `/merges`, `/contents/` writes in `bin scripts hooks githooks .github launchd` (M) | No | n/a | none |

**Minimum desk change (described, not run), in the only safe order:**

1. Generate a dedicated keypair with no passphrase prompt path (launchd auto-revert has no TTY).
2. Add the public half as a **write** deploy key on `-private` (owner-only action per <https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/repository-access-and-collaboration/permission-levels-for-a-personal-account-repository>, D).
3. `remote.origin.pushurl = git@github.com:renchris/claude-infrastructure-private.git` in the shared config, plus a **repo-local** `core.sshCommand` carrying `-i <key> -o IdentitiesOnly=yes` and the keepalive options the global one has today (`~/.gitconfig`: `ssh -o ServerAliveInterval=30 -o ServerAliveCountMax=120`).
4. Land once over SSH with no ruleset (proves the key path under real load).
5. Only then create the ruleset: target `~DEFAULT_BRANCH`, rules `update` + `deletion` + `non_fast_forward`, `bypass_actors: [{"actor_type":"DeployKey","actor_id":null,"bypass_mode":"always"}]`, `enforcement: active` (field names per `rest-rules.txt:473-517,632`).

**Traps in that change:**

| Trap | Evidence | Label |
|---|---|---|
| A host alias disables the pre-push identity guard. The hook exits 0 "out of scope, silent" unless the push URL matches `*github.com/renchris/*` or `*github.com:renchris/*`. `git@github-land:renchris/...` matches neither. | `githooks/pre-push:74-84`; installed copy is byte-identical (`cmp` against `.git/hooks/pre-push`) | M (code); that git passes the pushurl as `$2` is I |
| Plain `git@github.com` authenticates as the **user**, not the key: `id_ed25519` is a default identity and is on the account, so the push is judged as `renchris` and refused. `IdentitiesOnly` is mandatory. | key booleans above | M inputs, I conclusion |
| A rule refusal is misreported. `! [remote rejected]` does not match `'! \[rejected\]'`, so it classifies "refused" and the message blames "almost always the pre-push hook". Exit 7 and verbatim output are still correct. | `scripts/ship-land.sh:494-509`, `:5268` | M (code); the GitHub wording is I |
| `DeployKey` bypass has `actor_id: null`: it admits **every** write deploy key on the repo, present or future. | `rest-rules.txt:479` | D |
| Per repo. "Deploy keys only grant access to a single repository"; `scripts/dispatch-projects.conf` lists 3 dispatchable projects. B on `-private` covers 1 of 3. | deploy-keys doc (`deploy-keys.txt:132`); conf file | D / M |
| No code reads the push URL: 0 hits for `get-url --push`, `pushurl`, `pushInsteadOf`. `remote get-url origin` consumers (`bin/cc-offload:476,707`, `scripts/git-identity-assert.sh:255`, `scripts/wrap-ledger.sh:1900`) keep seeing HTTPS. | `git grep` | M |

## Q3. Can the VM-side credential undo the ruleset?

| Link in the chain | Quote or fact | Source | Label |
|---|---|---|---|
| VM pushes are judged as the connected access | "GitHub applies them to the GitHub access you connected, so a rule that access can bypass doesn't block a run's push" | `/tmp/cloud-blog-eval/doc-routines.md:332` (prior copy, read today) | D |
| Proxy does not pick branches | "It doesn't limit which branches a push can update. To do that, use branch protection rules or rulesets on GitHub." | <https://code.claude.com/docs/en/cloud-environments> line 242, re-fetched | D |
| VM REST calls carry the real token | "requests from the built-in GitHub tools, and from `gh` under the `proxy-injected` placeholder, go out with your real credentials substituted" (line 241); scope limit is per repository only (line 243); only GraphQL is filtered, and the 403 "names the REST fallback, `gh api repos/{owner}/{repo}/...`" (line 244) | same page, lines 241-244 | D |
| Inside a VM the token is the operator | "the proxy-injected token authenticates as `renchris`" | `docs/plans/CLOUD_OBSERVABILITY.md:1688-1689` (an earlier session's observation, not re-run) | D |
| That token administers the repo | `permissions.admin:true`; admin-gated `GET .../keys` returns 200; scope `repo` | `gh api`, `gh api -i` | M |
| Admins manage rulesets regardless of bypass list | "People with admin access to a repository ... can create, edit, and delete rulesets for a repository." | `managing-rulesets.txt:146` | D |

- **Conclusion (I, not observed):** a VM can `PUT` `enforcement: disabled`, `DELETE` the ruleset, or add `RepositoryRole` admin to `bypass_actors`. It can also `POST .../keys` to register its own write deploy key, which the null-id `DeployKey` bypass would admit (whether a VM has SSH egress is unknown).
- **What B adds over A:**

| VM behaviour | A (guard in ship-land.sh) | B (A + ruleset) |
|---|---|---|
| Runs `/ship` (the path behind the historical off-identity lands, trace doc `:55-58`) | refused | refused twice |
| Raw `git push origin HEAD:main` or `<branch>:main` | **not covered** | refused server-side |
| A's detection misses (env var absent, branch cut before the guard landed) | not covered | refused server-side |
| Edits the ruleset through `gh api`, then pushes | not covered | **not covered** |

- Base rate: 0 of 2,813 commits on `origin/main` since 2026-09-05 carry `noreply@anthropic.com` (M, `git log origin/main --since=2026-09-05 --format='%ae %ce'` piped through `sort` and `uniq -c`; the brief's 2,817 is the same query earlier in the day, the window rolls). All-time 88 commits are anthropic-authored and committed, last `da7ac9183` 2026-09-04T18:07:46Z (M; the brief's 93 was not reproduced by email match).

## Q4. Failure modes

| Failure | Effect | Recovery | Label |
|---|---|---|---|
| Deploy key file lost or unreadable | Every land on the box exits 7 "refused" (`ship-land.sh:501` keeps an ssh publickey refusal out of "transport"). All 100 worktrees share the config, so all landers stop. Fetch, gate and `deploy-live` keep working. Auto-revert cannot land and pages instead. | Owner disables the ruleset in Settings -> Rules, or `gh api` PUT from the desk; unset `pushurl`. Minutes. | I from M code |
| `DeployKey` bypass not honoured on a personal repo | Same total stop the moment the ruleset goes active | Same | I |
| SSH presents the user key (no `IdentitiesOnly`) | Same total stop | Fix `core.sshCommand` | I |
| Host alias used | No stop. The pre-push identity guard is silently off for every push | Use `github.com` in the pushurl | M (code) |
| Owner locked out? | No. Ruleset administration follows admin access, not the bypass list; "Repositories owned by personal accounts have a single owner who has full control" | Web UI or API | D |
| Hung push holding the land lock | Bounded: in-lock net calls run under `timeout` 60 s (`ship-land.sh:448-460`) | none needed | M |

- The exposure during an outage is about 4 commits per hour of blocked landing (103 per day, computed from the 7-day count).
- The same admin token that weakens B against a VM is what makes recovery a one-liner. There is no configuration of B on this account where one holds and the other does not.

## Alternatives considered

| Alternative | Verdict | Evidence |
|---|---|---|
| Invert B: keep the desk on the owner token with bypass = `RepositoryRole` admin; give VMs a non-admin identity (machine-user collaborator) | Dominates B on both axes if a hard boundary is wanted: desk push path untouched, and "Personal repositories always grant collaborators read/write access" with ruleset and deploy-key management owner-only. Costs a second GitHub account and re-running `/web-setup` on 3 linked Claude accounts (`ls ~/.claude/autonomy/websetup/`: next2, next3, next4). Not probed. | `deploy-keys.txt:188,198`; personal-permissions page; `managing-rulesets.txt:146` |
| Dedicated `land` remote instead of `pushurl` | Keeps feature-branch pushes on HTTPS; needs a code change at `ship-land.sh:5248,5330` | code read |
| Host alias in `~/.ssh/config` | Rejected: pre-push guard trap above | `githooks/pre-push:81-84` |
| Classic branch protection push restriction | Organization-only | about-protected-branches |
| Evaluate mode first | Enterprise-only | `rest-rules.txt:473` |

## Blockers and uncertainties

- **Unobserved, decides feasibility:** `DeployKey` bypass on a user-owned repo. Cheapest test is a ruleset on a throwaway pattern (for example `ruleset-probe/*`): token push refused, key push admitted, one VM push refused. That is 1 key, 1 ruleset, 3 pushes, 1 cloud session; `main` never at risk.
- **Unobserved, decides value:** whether the proxy passes ruleset and deploy-key REST writes from a VM. Documentation says nothing filters them.
- Whether a deploy-key push still triggers `hermetic.yml` / `diagrams.yml`, and what bypass banner lines git prints on each land: not checked.
- Whether any other machine or clone lands to this repo outside the one shared config: one clone found on this box; off-box not checked.
- 14 `git push` mentions outside the named scripts were read for shape; fixtures pushing to temp bare remotes were not individually traced beyond their file context.
