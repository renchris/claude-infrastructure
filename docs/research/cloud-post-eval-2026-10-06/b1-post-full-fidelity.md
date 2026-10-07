# B1 — "Claude Code in the cloud: a field guide to cloud sessions" at full fidelity

All sources fetched 2026-10-06 with `curl`. Line numbers refer to the local copies in `/tmp/cloud-blog-eval/`.

| Local file | Source | Notes |
|---|---|---|
| `b1-raw.html` | https://claude.dev/blog/claude-code-in-the-cloud/ | HTTP 200, 165,001 bytes (measured: `curl -w %{size_download}`) |
| `b1-text.md` | tag-stripped `b1-raw.html` (own python regex strip, links and code kept) | 321 lines, ~4,835 words (measured: `len(body.split())`) — this is the copy quoted as "post L<n>" below |
| `b1-post.md` | https://claude.dev/blog/claude-code-in-the-cloud.md (the post's own "Copy markdown" link) | 302 lines; used for figure alt text |
| `doc-claude-code-on-the-web.md` | https://code.claude.com/docs/en/claude-code-on-the-web.md | "web L<n>" |
| `doc-cloud-environments.md` | https://code.claude.com/docs/en/cloud-environments.md | "env L<n>" |
| `doc-routines.md` | https://code.claude.com/docs/en/routines.md | "rout L<n>" |
| `doc-fire.md` | https://platform.claude.com/docs/en/api/claude-code/routines-fire.md | "fire L<n>" |
| `doc-claude-projects.md`, `doc-settings.md`, `doc-web-quickstart.md`, `doc-cli-reference.md`, `doc-headless.md`, `doc-self-hosted-environments.md`, `doc-sht.md` (self-hosted-environments-testing), `doc-changelog.md` | code.claude.com/docs/en/<name>.md | targeted greps only |

Post metadata: title "Claude Code in the cloud: a field guide to cloud sessions", category "Playbooks", author Addy Osmani, published Oct 06 2026, 18 min read (post L7-L18; JSON-LD `datePublished":"2026-10-06"`). No `dateModified` found in the HTML.

Confidence labels: **documented** = quoted from the post or a docs page; **measured** = result of a command I ran; **inferred** = my reasoning, not stated by a source.

---

## 1. Answers to the four key questions

### Q1. Starting many sessions from a script/backlog, follow-ups, collecting results

| Topic | What the post says (verbatim) | What the post does NOT say | What the linked docs add |
|---|---|---|---|
| Starting many | "I started three cloud sessions within 16 seconds of each other, one per problem. I started them programmatically, and because tidepool isn't on GitHub, each session first recreated the repository from files in its prompt. With a real repository you'd skip that step, and from a terminal each session is one `claude --cloud` command." (post L54) | The mechanism behind "programmatically" is never named. No loop, no API, no flag for non-interactive creation, no session-id capture, no concurrency cap. | `-p` + `--cloud "<task>"` is REJECTED: "Claude Code rejects `--bg`, and rejects `--cloud` with a task description, with an error naming the conflict" (doc-headless.md L21). So the documented one-liner `claude --cloud "task"` is not a `-p` headless call. |
| Backlog workflow | Workflow 1 "Clear a backlog in parallel": "In the cloud, you'd start five sessions and review five branches." + three `claude --cloud "..."` lines (post L121-L128). "`claude --cloud` clones your GitHub remote at your current branch, so push your local commits first. While the VM starts, the CLI shows a live checklist of setup steps and queues anything you type." (post L130) | Nothing on draining a queue continuously, rate of creation, or backpressure. | "`--cloud` works with a single repository at a time." (web L96). Session creation failure guidance: "Retry after a minute, as capacity is provisioned on demand" (web L381). |
| Ticket shape | "Write each task as a self-contained ticket that states what's wrong, what done looks like, and how to prove it." (post L132) | — | — |
| Coordinator alternative | "a project (public beta for Pro and Max) runs a coordinator conversation that starts and tracks the cloud sessions for you. It then groups them by state: working, waiting on you, and ready for review." (post L134) | — | Projects: "The enforced limit is 200 new threads per day across your projects." (doc-claude-projects.md L407); not on Team/Enterprise (L10); a thread at plan limit "waits and continues on its own when the limit resets" (L399). |
| Other start surfaces | Table row "Start or follow from": cloud = "Browser, phone, Desktop, terminal, Slack, an API call or a schedule" (post L106). The "API call" is the routine endpoint (post L181). | No general "create session" API is described. | Routine `/fire` endpoint (section 4 below). `/fire` "is available to claude.ai users only and is not part of the Claude Platform API surface" (rout L230). |
| Follow-up to a running session | "You can queue a follow-up into a running session from any machine where you're logged in, including a CI job." + `claude -p "The integration tier is green now; rebase on main and push" --cloud <session-id>` (post L183-L186). FAQ: "Merge one branch, then send the next session a follow-up such as `claude -p "rebase on main and fix any conflicts" --cloud <session-id>`." (post L298) | Output format, error cases, whether it waits. | "The CLI queues the message into the session and exits without waiting for a reply." (web L178). stdin form: `echo "your message" \| claude -p --cloud <session-id>` (web L178). ID forms: `session_...`, `cse_...`, or the `claude.ai/code/<id>` URL (web L180). `--output-format json` → `{ok, session_id, url}` / `{ok: false, session_id, error}`; `stream-json` unsupported (web L196). Archived session refuses: "cloud session <id> is archived and cannot accept new messages" (web L413). Without `-p`: "Attaching to an existing cloud session is not enabled for your account." (web L411). |
| Collecting results | "When the work is done, it sits on a branch you can turn into a pull request." (post L37). "Ends with: A branch, and a pull request when you want one" (post L108). "Commits from cloud sessions carry a `Claude-Session` trailer that links back to the transcript." (post L282). "read Claude's summary before the diff" (post L272). `claude --teleport <session-id>` to pull branch + conversation locally (post L158-L161). "Create PR can open a full PR, a draft, or GitHub's compose page." (post L278) | No programmatic way to read a session's status, final reply, or result. No completion webhook. No CLI "list sessions"/"get status". | `CLAUDE_CODE_REMOTE_SESSION_ID` env var inside the session; `Claude-Session: <url>` trailer and PR-body session URL, disabled by `attribution.sessionUrl=false` (env L333-L335). Self-hosted test loop collects replies with a Stop hook writing `$E2E_REPLY_DIR/<session_id>.txt` on the runner (doc-sht.md L76-L85) — a self-hosted-only pattern. Routine run status: "A green status in the run list means the session started and exited without an infrastructure error. It does not mean the task in your prompt succeeded." (rout L306). |

Inferred (not in any source): the post's "live checklist ... queues anything you type" wording describes an interactive TTY surface for `claude --cloud "task"`; combined with the documented `-p` rejection, a scripted creator has three documented shapes only — (a) `claude --cloud "task"` without `-p`, (b) a routine `/fire` POST (returns `claude_code_session_id` + URL), (c) `claude -p ... --environment ccpool_... --output-format json` for self-hosted environments only ("Claude Code rejects Anthropic-hosted `env_` IDs passed to the flag", env L37).

### Q2. Is the flag really `--cloud`? Does the post mention `--remote`?

- `--cloud` is the flag. Measured: `grep -o -- '--cloud' b1-raw.html | wc -l` = 28; `grep -o -- '--remote' b1-raw.html | wc -l` = 0. The post never mentions `--remote`. The only "remote" in the post is "remote control" (4 hits, a different feature).
- Docs (2026-10-06): "The older `--remote` spelling still works as a deprecated alias for `--cloud`." (web L96); cli-reference row: "`--remote` | Deprecated alias for `--cloud`, including the existing-session form" (doc-cli-reference.md L119).
- "`--cloud` creates cloud sessions. `--remote-control` is unrelated" (web L101).
- Changelog (fetched 2026-10-06, newest entry 2.1.292 dated October 6, 2026): no entry names the `--cloud` flag or the `--remote` deprecation (measured: awk over `doc-changelog.md` for `-cloud|-remote[^-]` returns no flag entries). Nearest dated signal: 2.1.274 (September 17, 2026) "Changed the `/status` GitHub line to read "Cloud sessions", and `/web-setup`, `/ultrareview`, and teleport messages to say "cloud session" instead of "Claude Code on the web"" (doc-changelog.md L1617). The version that introduced `--cloud` is therefore not established.
- Repo check (measured: `git grep` in the worktree, non-doc files): `bin/cc-cloud:89` already references `claude -p "<msg>" --cloud <id> --output-format json`; no non-doc file invokes `claude --remote "<task>"` (the `--remote` hits in `bin/cc-cloud` and `tests/cc-cloud.bats` are that script's own `declare --remote <git-remote>` argument, unrelated).

### Q3. What the post presents as new / beta / preview

The post contains no "new in vX" or "recently changed" sentence. Status labels it does use:

| Item | Post wording | Line |
|---|---|---|
| Bonus credit | "Existing individual Pro and Max subscribers can claim a one-time bonus credit for cloud sessions, on top of their plan limits: $100 on Pro and $250 on Max. Claim it by October 7 at claude.ai/code/claim-credit or with `/claim-credit` in Claude Code. The credit expires on November 4. After it's used or expires, your plan's regular usage applies. It isn't eligible for Projects or Routines." | L41 |
| Projects | "a project (public beta for Pro and Max)"; links https://claude.com/blog/projects-redesigned | L134 |
| Routines | "A routine (research preview)" | L181 |
| Self-hosted environments | "in beta for Team and Enterprise, run cloud sessions on your organization's own infrastructure, so they can reach private networks" | L113 |
| Naming | The product is called "cloud session(s)" throughout; "Claude Code on the web" appears only in docs URLs. | — |

Things the post states without a "new" label that an August-era reader may not have (inference about novelty; each fact is documented): follow-up via `-p ... --cloud <session-id>`; bundle upload when no GitHub remote/App; API credentials held outside the VM on Pro/Max (post L264); prefilled-session URL (post L188); queued-message take-back (post L280); `/teleport` alias `/tp`; `/tasks` then `t`.

Docs version floors relevant to a v2.1.284 install (all at or below 2.1.284):

| Feature | Floor | Source |
|---|---|---|
| `/model`, `/effort`, `/color`, `/rename` with argument in cloud sessions | v2.1.205 | web L265 |
| Routine saved prompt delivered as the assigned task (before: "framed as an untrusted background notification and could refuse to act on it") | v2.1.213 | rout L77 |
| `/teleport` typed inside the cloud session prints the exact local command | v2.1.223 | web L208 |
| `--environment <ccpool id>` and `--ref <branch>` dispatch flags (self-hosted) | v2.1.224 | env L37, doc-sht.md L80 |
| GitHub trigger added from CLI via `/schedule` | v2.1.225 | rout L131 |
| `/schedule` run-history questions; Routines admin toggle hides `/schedule` | v2.1.227 | rout L322, L418 |
| `/fast` in cloud sessions | v2.1.271 | web L266 |

Changelog entries after 2.1.284 touching cloud sessions (measured line→version map via awk on `doc-changelog.md`): 2.1.285 "Fixed cloud session creation and `/remote-env` reading only the newest 20 of an account's environments" (L651); 2.1.285 "Fixed `/autofix-pr` and `/schedule` saying the Claude GitHub App is not installed on a repository whose install status had not been checked yet" (L662); 2.1.286 "Fixed routine runs whose cloud session never started showing as Succeeded ... they now show as Failed" (L617); 2.1.287 "Fixed occasional failures to fetch from or push to GitHub when GitHub briefly refused a newly issued access token" (L528); 2.1.290 "Improved the error shown when a cloud session is started without a claude.ai sign-in" (L245); 2.1.291 "Fixed a regression in 2.1.290 where cloud sessions could drop answers to permission prompts" (L109). The changelog was only grepped, not read end to end.

### Q4. Links the post points to

Docs links (all under https://code.claude.com/docs/en/): `claude-code-on-the-web` (+ anchors `#from-terminal-to-cloud`, `#environment-expired`, `#quick-setup-for-team-and-enterprise`, `#send-local-repositories-without-github`, `#limitations`, `#troubleshooting`, `#send-follow-ups-from-the-cli`), `web-quickstart` (+ `#connect-from-your-terminal`, `#no-repositories-appear-after-connecting-github`), `cloud-environments` (+ `#installed-tools`, `#github-proxy`, `#setup-scripts`), `settings#settings-in-cloud-sessions`, `permission-modes`, `self-hosted-environments`, `zero-data-retention`, `claude-projects`, `github-enterprise-server`, `data-usage`, `security`, `mobile`, `desktop#run-long-running-tasks-in-the-cloud`, `slack`.
Other links: https://claude.com/blog/projects-redesigned, https://claude.ai/admin-settings/claude-code, https://claude.ai/admin-settings/connectors, https://claude.ai/connect-github, https://claude.ai/settings/data-privacy-controls, https://www.anthropic.com/legal/promotion-credit-terms. Plain-text (unlinked) URLs: `claude.ai/code/claim-credit`, `claude.ai/code/routines`, `claude.ai/customize/connectors`, `claude.ai/code?prompt=...&repositories=...`.
The post has NO link to the routines docs page; routines are described in one paragraph (post L181) with no numbers.

---

## 2. Corrections to the lead's digest

| # | Digest claim | Verdict | Primary source |
|---|---|---|---|
| 1 | Fresh VM "~4 vCPU, 16 GB RAM, 30 GB disk" and a new branch | Correct. "The VM has about 4 vCPUs, 16 GB of RAM, and 30 GB of disk." (post L294). Docs: "approximate resource ceilings that may change over time" and "The VM may stop tasks that need significantly more memory" (env L373-L379). OS is Ubuntu 24.04 x86_64 (env L259) — post omits. | post L294 |
| 2 | "the session gets a short-lived credential for its own branch" | Post says it; docs CONTRADICT the branch scoping. Post: "a short-lived credential that can push only to its own working branch" (post L89). Docs: "Push restrictions: the proxy rejects branch deletions and pushes of anything other than a branch, such as a tag. It doesn't limit which branches a push can update. To do that, use branch protection rules or rulesets on GitHub." (env L242). Two same-day sources disagree; the docs page is the more specific one. Treat "can only push to its own branch" as unproven. | post L89 vs env L242 |
| 3 | "Idle VMs are reclaimed; reopening restores the conversation on a fresh VM" | Correct but incomplete. Docs describe two stages: "after a few minutes without activity, a session's VM pauses with its files saved. Your next message restores the same VM" then possibly "reclaimed" (env L81-L82). Not restored: "background work that was still running when the VM was reclaimed, such as subagents and shell commands" (web L422). A session waiting on an MCP connector approval/sign-in "counts as inactive ... and it can expire during that wait" (web L417). No duration is given for reclaim anywhere. | post L93; env L81; web L417-L422 |
| 4 | "CLAUDE.md, .claude/ skills and commands, .claude/settings.json hooks and .mcp.json travel; personal ~/.claude does not" | Correct with two omitted qualifiers. Post list is "`CLAUDE.md`, rules, skills, agents, and commands" (post L91) — digest dropped rules and agents. Hooks: "Repository hooks load in single-repository sessions." (post L258). Docs: hooks, permission rules and `.mcp.json` only "in a session with one repository" (env L272-L273); repo-declared plugins/marketplaces are NOT installed (env L276); transport `env` keys such as `NODE_EXTRA_CA_CERTS` ignored (env L282); "Cloud sessions automatically load skills you enable on claude.ai" (env L279). | post L91, L258, L300; env L269-L284 |
| 5 | `CLAUDE_CODE_REMOTE` check in a SessionStart hook | Correct. "Check `CLAUDE_CODE_REMOTE` if a step should run only in the cloud." (post L258). Docs: value is the string `true` (env L475, L484); hook cancelled after 600 s unless `timeout` set (env L388); hooks run "on every session including resumed" (env L436). | post L258 |
| 6 | CLI list: `claude --cloud "task"`; `claude --teleport [session-id]`; `claude -p "follow-up" --cloud <session-id>`; `/web-setup`; `/teleport` (`/tp`); `/autofix-pr`; `/schedule`; `/claim-credit` | All present in the post. Omitted from digest: `claude --permission-mode plan` (post L151), `/tasks` then `t` (post L161), `/login` (post L306), `BASH_DEFAULT_TIMEOUT_MS` / `BASH_MAX_TIMEOUT_MS` (post L144), `service postgresql start` (post L260), the prefilled URL (post L188). | post |
| 7 | Setup script "run as root, must exit 0 within ~5 minutes" | Conflates two separate constraints. Post: "It must exit 0 or the session won't start, and it should finish within about five minutes so the environment gets cached." (post L256). Five minutes is the caching budget, not a stated kill limit; docs: "If setup takes longer than roughly five minutes, the environment isn't cached." (env L419). Quickstart adds that over-budget scripts can "stall on the setup script step or fail with a generic container error" (doc-web-quickstart.md L259). | post L256; env L413-L419 |
| 8 | Snapshot "rebuilt when script/hosts change or every ~7 days" | Correct. "The cache rebuilds when you change the script or the allowed hosts, and about every seven days." (post L256). Omitted: "The cache stores files. Processes that were running don't survive it." (post L260). | post L256, L260 |
| 9 | Network levels "Trusted (default) / Custom / Full / None, changes reach running sessions in ~1 minute" | Correct. "Changes reach running sessions within about a minute." (post L262). Omitted: "Even at None, Claude Code still sends requests to the Anthropic API, so data can leave the VM that way, and the session can still push to its own branch. All outbound traffic passes through a proxy that logs hostnames." (post L194). | post L194, L262 |
| 10 | Routine triggers "schedule (hourly minimum), HTTP call, GitHub events" | Correct. "Triggers can be a schedule (hourly at most often), an HTTP call to the routine's own endpoint, or a GitHub event such as a pull request opening or a release." (post L181). Omitted from digest: "(research preview)"; "Routines run without approval prompts, and by default they push to `claude/`-prefixed branches."; creation also "in the Desktop app". | post L181 |
| 11 | "routines have separate hourly caps" | Correct, and the post gives NO numbers: "Routines have their own hourly caps" (post L284). Numbers are in docs only (section 4). | post L284 |
| 12 | "Projects can start up to 200 new threads daily" | Correct: "projects can start up to 200 new threads a day" (post L284); docs: "200 new threads per day across your projects" (doc-claude-projects.md L407). | post L284 |
| 13 | "Auto-fix for CI failures (/autofix-pr)" | Incomplete. Covers CI failures AND review comments; four entry points (CI bar toggle, `/autofix-pr` on the PR branch, mobile app, pasting a PR URL); needs the Claude GitHub App (post L175). Caveats: "Replies on review threads post under your GitHub username, labeled as Claude Code. Claude doesn't get notified about merge conflicts with the base branch, so ask it to rebase. Its comments can also trigger comment-driven automation such as Atlantis." (post L177). | post L175-L177 |
| 14 | "Parallel sessions draw plan limits proportionally" | Correct: "Parallel sessions draw on your plan limits in parallel, so five sessions use them about five times as fast as one." (post L284). | post L284 |
| 15 | "Cloud commits carry a Claude-Session trailer linking the transcript" | Correct (post L282). Docs add format `Claude-Session: <url>`, PR bodies also carry the URL, opt-out `attribution.sessionUrl=false` (env L335). | post L282 |
| 16 | GitHub paths: "... or a bundle upload with no push-back" | WRONG as stated. Post: "Claude Code uploads a bundle of your repository instead of cloning it. The session can push back only if your GitHub connection has push access to that repository." (post L232). No push-back applies to GitLab/Bitbucket: "the session can't push back to those hosts" (post L296). Bundle triggers: "a repository that has no GitHub remote, or one where the App isn't installed" (post L232). | post L232, L296 |
| 17 | "`/web-setup` with a gh token" | Correct but omits the capability gap: table row "`/web-setup` (your `gh` token) ... Auto-fix, GitHub triggers, projects: No, needs the App" (post L210); "On Team and Enterprise plans, an owner has to turn on Quick setup first." (post L228). | post L210, L228 |
| 18 | Credit "Pro $100, Max $250, claim by Oct 7, expires Nov 4, not usable for Projects or Routines" | Correct (post L41). Omitted: "Existing individual Pro and Max subscribers", "one-time", "on top of their plan limits", claim URL `claude.ai/code/claim-credit`. The claim deadline is the day after this report's date. Claiming is an account action and was not performed. | post L41 |
| 19 | (not in digest) Approvals in cloud | "Approvals: Local = Any mode, including per-command; Cloud = Auto, Accept edits or Plan" (post L107). Figure F alt text: "Claude Code in auto mode" (b1-post.md L71). | post L107 |
| 20 | (not in digest) Command time limits | "Foreground commands time out after 2 minutes by default (10 at most) and then keep running in the background for up to 30 more. You can raise the defaults with `BASH_DEFAULT_TIMEOUT_MS` and `BASH_MAX_TIMEOUT_MS` in the environment's variables." (post L144). Docs: exception "unless the command starts with `sleep`"; `BASH_DEFAULT_TIMEOUT_MS` above `1800000` also lengthens the background limit (env L387). | post L144; env L385-L392 |
| 21 | (not in digest) Availability | "Pro, Max, and Team plans, and Enterprise users with a premium seat or a Chat + Claude Code seat, signed in with a claude.ai account. They aren't available with a Console API key or a third-party provider." (post L288). ZDR orgs: cloud sessions off (post L111). | post L288, L111 |
| 22 | (not in digest) Secrets | "Environment variables are visible to anyone who uses the environment. On Pro and Max, an environment's API credentials attach a key to requests for the hosts you name, outside the VM, so the key never sits in a variable." (post L264). | post L264 |

---

## 3. Every command, flag, URL, limit and number in the post (verbatim sentence)

### Commands / flags / variables

| Item | Sentence | Post line |
|---|---|---|
| `claude --cloud "<task>"` | "With a real repository you'd skip that step, and from a terminal each session is one `claude --cloud` command." | L54 |
| same (3 demo prompts) | `claude --cloud "npm test fails maybe one run in four. Find the flaky test, fix the root cause in the code (not the test), and prove it by running the suite at least 30 times in a row."` (+ docs prompt, + logger prompt) | L57-L59 |
| same (backlog) | `claude --cloud "Fix the flaky test in auth.spec.ts"` / `"Update the API documentation"` / `"Refactor the logger to use structured output"` | L126-L128 |
| clone semantics | "`claude --cloud` clones your GitHub remote at your current branch, so push your local commits first. While the VM starts, the CLI shows a live checklist of setup steps and queues anything you type." | L130 |
| `claude --permission-mode plan` | code block with `# ...agree on the plan, save it to docs/migration-plan.md, commit and push...` then `claude --cloud "Execute the migration plan in docs/migration-plan.md"` | L151-L153 |
| `claude --teleport` / `claude --teleport <session-id>` | `claude --teleport            # pick a cloud session` | L158-L159 |
| teleport semantics | "Teleport checks that you're in the same repository, fetches the session's branch, checks it out, and loads the whole conversation into your terminal. You need a clean working tree (it offers to stash), and the branch has to be pushed. From inside Claude Code, `/teleport` (or `/tp`) opens the same picker, and `/tasks` then `t` works too. The Desktop app goes the other way, and its Open in menu sends a local session to the cloud." | L161 |
| `/autofix-pr` | "From the CI bar in a session at claude.ai/code, turn on Auto-fix. You can also run `/autofix-pr` on the PR branch in your terminal, ask the mobile app to watch the PR, or paste the PR URL into a session." | L175 |
| `/schedule` | "Create one at claude.ai/code/routines, in the Desktop app, or with `/schedule` in the CLI." | L181 |
| `claude -p "<msg>" --cloud <session-id>` | `claude -p "The integration tier is green now; rebase on main and push" --cloud <session-id>` | L186 |
| prefilled URL | "A URL such as `claude.ai/code?prompt=Triage+the+newest+issues&repositories=acme-labs/tidepool` opens claude.ai/code with the prompt and repository already filled in." | L188 |
| `/web-setup` | "If you already use the `gh` CLI, run `/web-setup` inside Claude Code to send your `gh` token to your Claude account. Sessions can then reach any repository that token can, with or without the App." | L228 |
| `/claim-credit` | "Claim it by October 7 at claude.ai/code/claim-credit or with `/claim-credit` in Claude Code." | L41 |
| `/login` | "Open claude.ai/code, or run `/login` in Claude Code with your claude.ai account." | L306 |
| `BASH_DEFAULT_TIMEOUT_MS`, `BASH_MAX_TIMEOUT_MS` | see row 20 above | L144 |
| `CLAUDE_CODE_REMOTE` | "Check `CLAUDE_CODE_REMOTE` if a step should run only in the cloud." | L258 |
| `service postgresql start` | "Ask Claude to run `service postgresql start`, or do it in a SessionStart hook." | L260 |
| `.claude/settings.json`, `.mcp.json`, `CLAUDE.md` | "commit skills and commands under `.claude/`, add project-scoped MCP servers to `.mcp.json`, and document test commands in `CLAUDE.md`." | L300 |
| `claude/` branch prefix | "Routines run without approval prompts, and by default they push to `claude/`-prefixed branches." | L181 |

### Numbers

| Number | Sentence | Post line |
|---|---|---|
| $100 / $250, Oct 7, Nov 4 | see row 18 | L41 |
| 16 s; 61, 65, 72 s; 87 s | "The sessions ran for 61, 65 and 72 seconds, and all three were done 87 seconds after the first one started. Recreating the repository took roughly a third to just over half of each run." (author's demo, tiny repo, not a product limit) | L45, L61 |
| 40 runs / 30 asked | "ran `npm test` 40 times in a row with zero failures" | L63, L132 |
| 2 min / 10 min / 30 min | row 20 | L144 |
| hourly | "a schedule (hourly at most often)" | L181 |
| ~5 minutes setup; ~7 days cache | "it should finish within about five minutes so the environment gets cached ... about every seven days" | L256 |
| ~1 minute | "Changes reach running sessions within about a minute." | L262 |
| 5x | "five sessions use them about five times as fast as one" | L284 |
| 200/day | "projects can start up to 200 new threads a day" | L284 |
| 4 vCPU / 16 GB / 30 GB | "The VM has about 4 vCPUs, 16 GB of RAM, and 30 GB of disk." | L294 |
| "Ten minutes of environment setup" | "Ten minutes of environment setup gives Claude a way to run those checks." | L250 |
| cost | "there's no separate charge for the cloud machine, and sessions draw on the same usage limits as the rest of Claude Code" / "Each of Claude's turns still counts toward your plan, but a long test run inside one command costs little." | L39, L144 |

The post states no cap on concurrent cloud sessions, no session lifetime, no idle-reclaim duration, and no numeric routine caps.

---

## 4. What the linked docs say that the post omitted (cloud sessions, routines, environments, network)

### Routines (https://code.claude.com/docs/en/routines, research preview)

| Fact | Quote | Line |
|---|---|---|
| Hourly caps (the numbers behind the post's "own hourly caps") | Scheduled runs incl. one-off: "100 per hour", per account, over limit "The run waits until the limit resets". "**Run now**, API fires, and setting a one-off routine to run again: 30 per hour", per routine, shared, "The action fails until the limit resets". Run now: 100/h per account. "API fires: 100 per hour ... Your account, counted separately from **Run now**". "None of these hourly limits has overage." | rout L382-L390 |
| GitHub events | "GitHub webhook events are subject to per-routine and per-account hourly caps. Events beyond the limit are dropped until the window resets." (no number given) | rout L237 |
| `/fire` endpoint | `POST https://api.anthropic.com/v1/claude_code/routines/trig_.../fire` with `Authorization: Bearer <routine-token>`, `anthropic-beta: experimental-cc-routine-2026-04-01`, `anthropic-version: 2023-06-01`, body `{"text": "..."}`; response `{"type":"routine_fire","claude_code_session_id":"session_...","claude_code_session_url":"https://claude.ai/code/session_..."}` | rout L202-L217 |
| `text` limits | "Maximum 65,536 characters." | fire L90 |
| `text` is untrusted | "It arrives wrapped in a `<routine-fire-payload>` block that labels it as untrusted data and tells Claude not to follow instructions inside it unless the routine's own prompt says to." / "a routine's saved prompt must opt in to acting on fire text" | rout L195-L197 |
| No idempotency | "Each successful request creates a new session. There is no idempotency key. If a webhook caller retries, the endpoint creates multiple sessions." | fire L144 |
| 429 | "An hourly fire limit for the routine or the account has been reached. The response includes a `Retry-After` header" | fire L132 |
| Paused routine | 400 `invalid_request_error` when "the routine is paused" | fire L128 |
| Token | "Each routine has its own token, scoped to triggering that routine only."; "The CLI cannot currently create or revoke tokens."; "Generating a new token revokes the previous one." | rout L189, L169; fire L140 |
| Beta header policy | "Breaking changes ship behind new dated beta header versions, and the two most recent previous header versions continue to work" | rout L223 |
| Min schedule | "The minimum interval is one hour; expressions that run more frequently are rejected."; on-the-hour runs "can start several minutes late" | rout L143-L145 |
| Clone/branch | "Each repository is cloned at the start of a run, starting from the default branch." / "Claude pushes its work to a branch prefixed with `claude/` unless your prompt directs it to push to another branch." | rout L83, L332 |
| Autonomy | "there is no permission-mode picker ... all without stopping for approval apart from some artifact actions" | rout L51 |
| Ownership | "Routines belong to your individual claude.ai account. They are not shared with teammates" | rout L65 |
| Connectors default | "all of your connected MCP connectors are included by default ... Claude can use every tool from an included connector, including writes, without asking for permission during a run." | rout L115 |
| GitHub outage | "the routine skips runs until you reconnect, for up to 72 hours ... After 72 hours without a connection, the routine turns off" | rout L328 |
| Over plan limit | "organizations with usage credits turned on can keep running routines on metered overage. Without usage credits, additional runs are rejected until your usage window resets." | rout L392 |
| Status semantics | green = "started and exited without an infrastructure error. It does not mean the task in your prompt succeeded." | rout L306 |
| Blocked host signature | "fail with `403` and `x-deny-reason: host_not_allowed`" | rout L348 |
| CLI management | "`/schedule list` ... `/schedule update` ... `/schedule run`"; alias `/routines`; `/schedule` unavailable inside a cloud session | rout L320, L127, L408 |
| GitHub trigger events | Pull request and Release only; filters author/title/body/base/head/labels/draft/merged; "two PR updates produce two independent sessions" | rout L234, L267-L285 |

### Cloud sessions page (https://code.claude.com/docs/en/claude-code-on-the-web)

| Fact | Quote | Line |
|---|---|---|
| Force bundle | "set `CCR_FORCE_BUNDLE=1`"; bundle "must be under 100 MB. Larger repositories fall back to bundling only the current branch, then to a single squashed snapshot of the working tree, and fail if the snapshot is still too large"; "Untracked files are not included"; needs git 2.31+ | web L143-L157 |
| Bundle refuses linked worktrees with sparse checkout, submodules, `--separate-git-dir`/`--shared`/`--reference` clones, reftable | "Start from the repository's main checkout instead." | web L160-L161 |
| Bundle even with `/web-setup` | "This applies even if you connected GitHub with `/web-setup`." (bundle is used when the App is not installed on the repo) | web L134 |
| Org policy | "Your organization's `allow_remote_sessions` policy must also be enabled." | web L183 |
| Teleport is a copy | "The terminal gets its own copy of the session: new work there stays local and doesn't appear in the cloud session" | web L210 |
| Slash commands in cloud | `/clear` not available; `/compact`, `/context` yes; `/plugin`, `/resume` not available | web L263-L275 |
| Auto-compaction | "Cloud sessions set `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` themselves ... That value overrides one you add"; use `CLAUDE_CODE_AUTO_COMPACT_WINDOW` instead | web L277-L279 |
| Subagents / agent teams | subagents work; `.claude/agents/` picked up; agent teams off unless `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` | web L281-L283 |
| Creation failure | "`Session creation failed` ... Retry after a minute, as capacity is provisioned on demand" | web L376-L381 |
| Rate limits | "cloud sessions share rate limits with all other Claude and Claude Code usage within your account. Running multiple tasks in parallel consumes more rate limits proportionately." | web L428 |
| Sharing on Pro/Max | visibility "**Private** and **Public**. Public visibility makes the session visible to any user logged into claude.ai" | web L308 |

### Environments and network (https://code.claude.com/docs/en/cloud-environments)

| Fact | Quote | Line |
|---|---|---|
| CLI environment selection | "Run `/remote-env` ... saves your choice to the `remote.defaultEnvironmentId` key in your user settings" (overridable by a higher-precedence layer such as a repo's project settings) | env L148 |
| Env var refresh | existing session "keeps the values it last read until its VM is next restored or rebuilt" | env L84 |
| `OTEL_*` not passed to commands | "except `OTEL_*` variables" | env L77 |
| GitHub proxy limits | GraphQL: "serves only a pinned set of GraphQL operations for pull-request workflows ... 403 ... `This GraphQL query is not enabled for this session`"; "Claude can't reach GitHub APIs that exist only in GraphQL, such as Projects v2"; "rejects branch deletions and pushes of anything other than a branch, such as a tag"; API scope limited to "repositories attached to the session" | env L242-L244 |
| `GH_TOKEN` | unset → reads as placeholder `proxy-injected`; set → "passes through to the container unchanged" and is readable by anyone using the environment | env L320-L325 |
| Paths that bypass the allowlist at every level | GitHub proxy, MCP connectors, API-credential hosts, Anthropic API | env L210-L215 |
| API credentials | Pro/Max only; Bearer default; never attached to GitHub, `api.anthropic.com`, public registries, setup-script requests | env L92-L144 |
| Installed tools | Python 3.x, Node 20/21/22 (22 on PATH), Ruby 3.1-3.3, PHP 8.3, OpenJDK 21, Go, Rust, GCC/Clang, Docker, PostgreSQL 16, Redis 7.0, git, gh, jq, yq, ripgrep, tmux; `check-tools` command; Bun has proxy issues | env L294-L312 |
| No shell | "You don't get a shell into the session VM. Claude runs every command for you" | env L345 |
| Setup script vs hook order | setup script "Before Claude Code launches, skipped when a cached environment exists"; SessionStart hooks "After Claude Code launches, on every session including resumed" | env L433-L437 |
| Setup script change vs existing sessions | "the setup script doesn't run when a session's VM is restored after being idle" | env L423 |
| Base image | "Replacing the base image entirely isn't supported yet." | env L498 |
| Archive, not delete | "You can't delete an environment, only archive it." | env L156 |

### Self-hosted dispatch (https://code.claude.com/docs/en/self-hosted-environments-testing, beta, Team/Enterprise)

- "Creates a session on the test environment with `claude -p "<prompt>" --environment <environment-id> --output-format json` ... The command creates the session, prints one line of JSON containing `session_id`, and exits without waiting for Claude's reply." (doc-sht.md L82). This is the only documented non-interactive create-and-return-id CLI form, and it is limited to `ccpool_` self-hosted IDs (env L37).

---

## 5. Post content the digest dropped entirely

- "Split parallel tasks along file boundaries, merge the branches in a sensible order, and expect a session to report problems that another session is already fixing." (post L79) — from the demo where the logger session hit the same race the cache session was fixing and "said in its summary that the suite wasn't clean" (post L67).
- "The sessions don't know about each other." (post L298).
- Stay-local criteria: local DB with real data, VPN-only service, GPU, phone simulator, hardware, tight visual loops, ZDR orgs (post L111).
- "The VM has no compute charge and its CPU isn't yours, so ask for thorough proof. Run the suite 200 times, bisect a regression across 50 commits, run the slow integration tier" (post L142).
- Habits: "One task, one session."; "Ask for evidence. Name the command that proves the task is done"; "Push before `claude --cloud`."; "Commit as you go on long tasks. Idle VMs can be reclaimed."; "Messages you send while Claude works queue up, and you can take a queued one back." (post L270-L280).
- Team/Enterprise owner checklist: GitHub connector at claude.ai/admin-settings/connectors, allow cloud sessions, install the App, Quick setup; IP allowlists and GHES need extra steps (post L236). "Every cloud session fails with an authentication error | Your Claude organization uses IP allowlisting | Ask support to exempt Anthropic-hosted services" (post L244).
- Data: "Anthropic stores the session transcript ... VMs are reclaimed after inactivity, and deleting a session removes its data." (post L290).
- Default environment: "Trusted network access, no variables and no setup script, which is enough for most JavaScript, Python, Go and Rust repositories." (post L254).

---

## 6. Adversarial self-pass

| Challenge | Outcome |
|---|---|
| Did tag stripping lose content (JS-rendered sections, collapsed FAQ)? | Cross-checked against the post's own `.md` export (`b1-post.md`, 302 lines, 5,145 whitespace tokens vs 4,835 in the stripped HTML; the difference is figure alt text and table pipes). Sections and tables match; FAQ answers are present in the static HTML. Figure images themselves were not viewed; only their alt text was read. |
| Is "can push only to its own working branch" really contradicted? | The post sentence (L89) and the docs sentence (env L242, "It doesn't limit which branches a push can update") are both dated 2026-10-06 and cannot both be literally true for Anthropic-hosted sessions. Not tested empirically (starting a session is out of scope). Reported as a disagreement, not resolved. |
| Is `--cloud "task"` really unusable headless? | Only the docs sentence (doc-headless.md L21) says `-p` + task is rejected. Whether `claude --cloud "task"` without `-p` exits cleanly with no TTY, and what it prints, is NOT established by any fetched source and was not run. The local `claude` binary was not found at `~/.local/bin/claude` and `command -v -a` failed in this shell, so `--help` was not read. |
| Could the post's "programmatically" mean the routine `/fire` API? | Possible; the post does not say. Inference only. The demo repo "isn't on GitHub" and sessions "recreated the repository from files in its prompt", which fits a prompt-only creation path rather than `claude --cloud` (which would bundle the local repo) — inference. |
| Are the routine numbers stable? | Routines are "in research preview. Behavior, limits, and the API surface may change." (rout L10). Numbers are as of 2026-10-06. |
| Alternatives considered for "collect results" | (a) session status/result API — not found in any fetched page; (b) Stop hook writing reply to disk — documented for self-hosted runners only; (c) branch + `Claude-Session` trailer + PR body URL — documented for all cloud sessions; (d) `claude --teleport <id>` — interactive, requires clean tree. Only (c) is a documented, non-interactive, Anthropic-hosted collection path. |

## 7. Gaps

- The mechanism the author used to start sessions "programmatically" is not stated.
- No source fetched documents a programmatic way to list cloud sessions or read a session's status/final reply for Anthropic-hosted sessions.
- No stated cap on concurrent cloud sessions; no idle-pause or reclaim duration beyond "a few minutes" (pause) and "a period of inactivity" (reclaim); no maximum session lifetime.
- GitHub-event trigger hourly caps have no number in the docs.
- The Claude Code version that introduced `--cloud` / deprecated `--remote` is not in the changelog text I grepped.
- Behaviour of `claude --cloud "task"` with no TTY (exit code, stdout, whether a session id is printed) is not documented in the fetched pages and was not run.
- Not fetched: https://claude.com/blog/projects-redesigned, the promotional credit terms page, `self-hosted-environments` body (only its testing sub-page was read), `data-usage`, `security`, `permission-modes`, `slack`, `mobile`, `desktop`.
- The changelog (984 KB) was grepped for cloud-session terms only, not read in full.
