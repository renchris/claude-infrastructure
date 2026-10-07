# B2 — Official-docs contract for cloud sessions and routines (as an unattended pipeline meets it)

Fetched 2026-10-06 with `curl` from code.claude.com/docs (`.md` endpoints), platform.claude.com, and the blog. Local copies: `/tmp/cloud-blog-eval/docs/*.md`. Doc pages are undated living pages; the changelog is dated (newest entry 2.1.292, 2026-10-06). Labels: **DOC** = stated by the cited page, **INF** = my inference, **BLOG** = only in the blog post, **REPO** = read in the worktree (not re-measured).

Short page keys used below:

| Key | URL |
|---|---|
| WEB | https://code.claude.com/docs/en/claude-code-on-the-web |
| ENV | https://code.claude.com/docs/en/cloud-environments |
| RTN | https://code.claude.com/docs/en/routines |
| FIRE | https://platform.claude.com/docs/en/api/claude-code/routines-fire |
| QS | https://code.claude.com/docs/en/web-quickstart |
| PROJ | https://code.claude.com/docs/en/claude-projects |
| HEADLESS | https://code.claude.com/docs/en/headless |
| CLI | https://code.claude.com/docs/en/cli-reference |
| SHTEST | https://code.claude.com/docs/en/self-hosted-environments-testing |
| SEC | https://code.claude.com/docs/en/security |
| SET | https://code.claude.com/docs/en/settings |
| CMD | https://code.claude.com/docs/en/commands |
| CHG | https://code.claude.com/docs/en/changelog |
| BLOG | https://claude.dev/blog/claude-code-in-the-cloud/ (Addy Osmani, 2026-10-06) |

## 0. Headline

- The only **documented, token-authenticated, non-TTY** way to start an Anthropic-hosted cloud session is a routine's `/fire` endpoint: per-routine bearer token, body `{"text": ≤65,536 chars}`, returns `session_id` + URL, capped at 30 fires/hour per routine and 100/hour per account, no idempotency key (FIRE, RTN).
- `claude -p` **rejects** `--cloud "<task>"` (HEADLESS); `claude -p ... --environment` works headlessly but only for self-hosted `ccpool_` environments, a Team/Enterprise beta (CLI, SHTEST).
- No doc describes a session-read API, a concurrency cap for plain cloud sessions, or the clone depth. Results come back through git/GitHub (branch, PR, `Claude-Session` trailer) or a hook you install.

## 1. Routines

| Question | Contract | Source |
|---|---|---|
| Status | Research preview; "behavior, limits, and the API surface may change" | DOC RTN |
| Plans | Pro, Max, Team, Enterprise; owned by an individual account, not shared; runs count against that account | DOC RTN |
| Trigger types | Schedule (recurring or one-off), API (HTTP POST), GitHub event (pull request, release categories only). Combinable on one routine | DOC RTN |
| Minimum interval | One hour; cron set with `/schedule update`; faster expressions rejected. On-the-hour runs "can start several minutes late" | DOC RTN |
| Hourly caps (no overage on any) | Scheduled incl. one-off: 100/h per account, excess **waits**. Run now + API fire + one-off re-arm: 30/h **per routine** (shared count), excess **fails**. Run now/re-arm: 100/h per account. API fires: 100/h per account, counted separately | DOC RTN "Usage and limits" |
| GitHub-event caps | "per-routine and per-account hourly caps"; excess events **dropped**; numbers not published | DOC RTN |
| Daily cap | None documented for routines | DOC (absence) RTN |
| API auth | `Authorization: Bearer <routine-token>`, one token per routine, scope = fire that routine only, no read access. Shown once; regenerating revokes the old one. Not a Claude API key | DOC FIRE |
| Endpoint | `POST https://api.anthropic.com/v1/claude_code/routines/{trig_…}/fire`, header `anthropic-version: 2023-06-01` required | DOC FIRE |
| Beta header | RTN's curl sample sends `anthropic-beta: experimental-cc-routine-2026-04-01`; FIRE says requests work with and without it. **Two pages disagree; FIRE is the reference** | DOC RTN vs FIRE |
| Payload | Optional `text` string, max 65,536 chars, unparsed; unknown fields ignored. Arrives wrapped in `<routine-fire-payload>` labelled untrusted; the saved prompt must explicitly tell Claude to act on it | DOC FIRE, RTN |
| Response | 200 `{type:"routine_fire", claude_code_session_id, claude_code_session_url}`; returns at session creation, does not wait or stream | DOC FIRE |
| Errors | 400 (bad version, text too long, **routine paused**), 401, 403, 404, 429 with `Retry-After`, 500, 503 (not 529) | DOC FIRE |
| Idempotency | None. A retried POST creates another session | DOC FIRE |
| Create/fire from CLI | `/schedule` creates **scheduled** routines and (v2.1.225+) GitHub triggers; `/schedule list|update|run`; run-history questions (v2.1.227+). **API triggers and tokens: web only**; "no public API for token management" | DOC RTN, FIRE |
| `/schedule` availability | Slash command inside a claude.ai-subscription session; hidden with API key/third-party provider; unavailable inside a cloud session | DOC RTN troubleshooting |
| Run mode | Fully autonomous: no permission-mode picker, no approval stops (except some artifact actions); all connected MCP connectors included by default | DOC RTN |
| Repos / branch | Clones each repo on every run from the **default branch**; pushes to `claude/`-prefixed branch unless the prompt says otherwise | DOC RTN |
| Status meaning | Green = session started and exited without infrastructure error, **not** task success | DOC RTN |
| GitHub connection loss | Runs skipped up to 72 h, then the routine turns off | DOC RTN |
| Subscription paused | Routines held; must be re-enabled manually | DOC RTN |

- INF: a fired routine cannot be pointed at a base branch through the API; the only per-run variable is `text`, so branch/row selection must be written into the saved prompt as "read it from the payload".
- INF: one routine sustains at most 30 dispatches/hour = 720/day; an account at most 100 API fires/hour. A drain lane needing more needs several routines and still stops at 100/h per account.
- INF: `claude -p "msg" --cloud <session_id>` should work on the `session_…` id that `/fire` returns, since WEB says follow-ups work on a running cloud session "wherever it executes"; no page states this for routine runs specifically.

## 2. Cloud sessions

| Question | Contract | Source |
|---|---|---|
| Plans | Pro, Max, Team; Enterprise premium or Chat+Claude Code seats. Blocked by ZDR, HIPAA config, third-party providers, org IP allowlist, `allow_remote_sessions` off | DOC WEB |
| Start from terminal | `claude --cloud "<task>"` (`--remote` is a deprecated alias). Shows a live provisioning checklist; one repo per command | DOC WEB, CLI |
| Start headlessly | `-p` **rejects** `--cloud` with a task description (and `--bg`), "with an error naming the conflict" | DOC HEADLESS |
| Headless dispatch that exists | `claude -p "<prompt>" --environment ccpool_… [--ref <branch>] --output-format json` prints one JSON line with `session_id` and exits. Self-hosted environments only (Team/Enterprise public beta); `env_` ids are rejected by the flag. v2.1.224+ | DOC CLI, SHTEST, ENV |
| Follow-up, headless | `claude -p "msg" --cloud <session_id|url>` (stdin accepted) queues one message and exits without waiting. `--output-format json` → `{ok, session_id, url}` or `{ok:false, session_id, error}`; `stream-json` unsupported; config errors go to stderr without JSON | DOC WEB |
| Follow-up failure strings | `Session not found: <id>`; `cloud session <id> is archived and cannot accept new messages`; policy and provider errors | DOC WEB |
| Auth for dispatch/follow-up | claude.ai OAuth only; API keys refused. The `user:sessions:claude_code` scope is capped server-side at 30 days: re-run `claude auth login` every 30 days. `claude setup-token` (1-year) is inference-only and does not cover it. `CLAUDE_CODE_OAUTH_REFRESH_TOKEN` + `CLAUDE_CODE_OAUTH_SCOPES` provision a login without a browser, same 30-day cap. "No long-lived CI token for this today" | DOC SHTEST "Authenticate from CI" |
| What is cloned | Current directory's GitHub remote at the **current branch** (not the local checkout; push first). Web/mobile: branch selector per repo | DOC WEB, QS |
| No remote / App not installed | CLI uploads a git bundle: <100 MB, falls back to current branch, then squashed snapshot; untracked files excluded; needs git ≥2.31; refuses submodule, `--separate-git-dir`, `core.worktree`, reftable, and **sparse linked worktrees**. `CCR_FORCE_BUNDLE=1` forces it. This applies "even if you connected GitHub with `/web-setup`" | DOC WEB |
| Clone depth | **Not documented** on any fetched page (grep for shallow/depth: no hit) | DOC (absence) |
| Branch | "Each task gets its own session and its own branch" | DOC QS |
| Credential | Real GitHub token stays on Anthropic servers; VM holds "a short-lived credential scoped to that session"; GitHub proxy swaps it | DOC SEC, ENV |
| Push scope | Proxy rejects branch **deletions** and non-branch pushes (tags). "It doesn't limit which branches a push can update" — GitHub branch protection/rulesets applied to the connected access decide. A rule that access can bypass does not block the push | DOC ENV "GitHub proxy", SEC |
| Push scope, conflict | BLOG says the credential "can push only to its own working branch". The repo runbook says the same (REPO `docs/runbooks/cloud-fleet.md:23-24`). Current docs say otherwise. **Unresolved; not measured here** | BLOG vs DOC |
| PR creation | Built-in GitHub tools plus `gh` (pre-installed, `GH_TOKEN` reads `proxy-injected`); web UI "Create PR" (full, draft, or compose page). Proxy serves only a pinned GraphQL set; Projects v2 unreachable; REST fallback `gh api repos/{owner}/{repo}/...` | DOC ENV, QS |
| GitHub API scope | Only repositories attached to the session (403 otherwise) | DOC ENV |
| Permission modes | Auto (if org allows), Accept edits, Plan. No Manual, no Bypass | DOC QS |
| Concurrency | Each `--cloud` is an independent parallel session. **No numeric cap published** for plain sessions | DOC WEB (absence of cap) |
| Projects cap | 200 new threads/day across projects (enforced). Projects: Pro/Max public beta, gradual rollout, no CLI surface | DOC PROJ |
| Idle | VM **pauses** "after a few minutes without activity" with files saved; next message restores the same VM. A paused VM "can later be reclaimed"; reclaim timing **not published** | DOC ENV |
| After reclaim | Conversation restored on a fresh VM; background work (subagents, shell commands) lost. Waiting on an MCP approval/sign-in counts as inactive | DOC WEB "Environment expired" |
| Session-creation failure | `Session creation failed` = no VM allocated; "retry after a minute, capacity is provisioned on demand" | DOC WEB |
| VM | Ubuntu 24.04 x86_64, ~4 vCPU / 16 GB / 30 GB ("approximate ... may change") | DOC ENV |
| Command timeouts | Bash default 2 min, max 10 min, then moved to background for up to 30 more minutes; raise with `BASH_DEFAULT_TIMEOUT_MS` / `BASH_MAX_TIMEOUT_MS` as environment variables | DOC ENV |
| Compaction | Cloud sessions set `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` themselves; yours is ignored. `CLAUDE_CODE_AUTO_COMPACT_WINDOW` is honoured | DOC WEB |

### Result retrieval (no read API is documented)

| Channel | What you get | Source |
|---|---|---|
| Git branch / PR on GitHub | The work itself; commits carry `Claude-Session: <url>`; PR body carries the session URL (`attribution.sessionUrl=false` removes both) | DOC ENV |
| `CLAUDE_CODE_REMOTE_SESSION_ID` | `cse_…` inside the VM; same id as `session_…` with the prefix swapped | DOC ENV, SHTEST |
| Stop hook | `last_assistant_message` in hook stdin. Documented pattern: POST it to an endpoint you control (SHTEST "Remote test runners"). For Anthropic-hosted sessions the hook must be in the repo's `.claude/settings.json` and the endpoint host must be in the environment allowlist | DOC SHTEST (pattern); INF (hosted application) |
| `claude --teleport <id>` | Branch + full conversation into a local terminal. Needs clean tree, same repo, pushed branch, same account; offers to stash | DOC WEB |
| `/schedule` run history | Lists a routine's runs and reads a run's log (v2.1.227+); interactive slash command | DOC RTN |
| Routine status | Infra-level only (see §1) | DOC RTN |
| Raw sessions API | REPO: `scripts/cloud-create-api.py` already calls `/v1/sessions`, `/v1/code/sessions/<id>`, `/v1/environment_providers` with `ccr-byoc-2025-07-29`. Only the self-hosted **pools** endpoints under that beta header appear in docs (SHTEST); the session create/read endpoints do not | REPO + DOC (absence) |

## 3. Environments

| Question | Contract | Source |
|---|---|---|
| Where configured | Environment selector at claude.ai/code or Desktop; "no settings page or direct URL"; cannot be created or edited from the CLI. `/remote-env` only picks the CLI default (`remote.defaultEnvironmentId`) | DOC ENV |
| CLI environment choice | `/remote-env` pick → else the Anthropic-hosted environment → else first non-bridge entry | DOC ENV |
| Setup script | Bash, root, Ubuntu 24.04, runs before Claude Code launches. Non-zero exit = session fails to start | DOC ENV |
| Five-minute rule | Over ~5 min the result **is not cached** (ENV); QS adds that sessions may "stall ... or fail with a generic container error" | DOC ENV, QS |
| Snapshot cache | Filesystem only (no processes). Rebuilt when the script or allowed hosts change, and at ~7-day expiry. Not re-run on idle restore | DOC ENV |
| Setup-script limits | Agent-proxy API credentials are **not** attached during setup; GitHub release assets only from attached repos | DOC ENV |
| Env vars | `.env` format; readable by anyone using the environment (not a secret store). Read at creation and on each VM restore/rebuild; edits do not reach a running VM until then. `OTEL_*` not passed to commands | DOC ENV |
| Secrets | "API credentials" (Pro/Max only, Anthropic-hosted only): bearer/custom header attached by the agent proxy per host, never visible in the VM; add/delete only. Never attached to GitHub, `api.anthropic.com`, npm/jsr/PyPI/crates index/Go proxy hosts, setup-script requests, telemetry | DOC ENV |
| Own `GH_TOKEN` | If set as an env var it passes through unchanged, but the proxy's GraphQL restriction still applies | DOC ENV |
| Network levels | None / Trusted (default) / Full / Custom (optionally plus defaults). Changes reach running sessions "within about a minute" | DOC ENV |
| Always reachable | GitHub (own proxy), enabled MCP connectors (via Anthropic), API-credential hosts, Anthropic API — at every level, including None | DOC ENV |
| Blocked request | `403` with `x-deny-reason: host_not_allowed` | DOC RTN |
| Default allowlist | Anthropic, GitHub/GitLab/Bitbucket, Docker Hub/gcr/ghcr/mcr/ECR public, `*.googleapis.com`, `*.amazonaws.com`, Azure, npm/yarn/jsr, PyPI, RubyGems, crates, Go, Maven/Gradle, NuGet, pub.dev, hex, CPAN, CocoaPods, Hackage, Swift, Ubuntu/launchpad/nixos, k8s, HashiCorp, Anaconda, Apache, nodejs.org, Datadog, Honeycomb, sourceforge, packagecloud, Google Fonts, schemastore, `*.modelcontextprotocol.io`. Full list in ENV "Default allowed domains" | DOC ENV |
| Proxy caveat | All egress through a security proxy; Bun package fetch is a named incompatibility | DOC ENV |
| Environment listing | Before 2.1.285, session creation and `/remote-env` read only the newest 20 environments | DOC CHG 2.1.285 (2026-09-29) |

### What the repo contributes

| Item | Loaded? | Source |
|---|---|---|
| `CLAUDE.md`, `.claude/rules/`, `.claude/skills/`, `.claude/agents/`, `.claude/commands/` | Yes | DOC ENV |
| `.claude/settings.json` hooks + permission rules | Yes, **single-repo sessions only**; a multi-repo session starts above the clones and reads none | DOC ENV, SET |
| `.mcp.json` | Yes, single-repo sessions only | DOC ENV |
| `enabledPlugins` / `extraKnownMarketplaces` in repo settings | **Not installed** | DOC ENV |
| `.claude/settings.local.json`, `~/.claude/*`, `~/.claude.json` MCP servers | No | DOC SET, ENV |
| Transport keys in settings `env` (`NODE_EXTRA_CA_CERTS`, mTLS) | Ignored | DOC ENV |
| Server-managed org settings | Yes | DOC ENV |
| Skills enabled on claude.ai | Auto-loaded | DOC ENV |
| SessionStart hook | Runs after launch on every start **and resume**; 600 s cancel unless `timeout` set; gate on `CLAUDE_CODE_REMOTE=true` | DOC ENV |

## 4. Billing

| Question | Contract | Source |
|---|---|---|
| Quota | Cloud sessions "share rate limits with all other Claude and Claude Code usage within your account"; parallel sessions consume proportionally | DOC WEB "Limitations" |
| VM charge | "No separate compute charge for the cloud VM" | DOC WEB |
| Routines | "Draw down subscription usage the same way interactive sessions do"; billing line = "Claude Code subscription usage on claude.ai" | DOC RTN, FIRE |
| Separate caps | Only the hourly start caps in §1 and Projects' 200 threads/day. No Max-specific session quota documented | DOC RTN, PROJ |
| At the limit, routines | With usage credits on: continue on metered overage. Without: runs **rejected** until the window resets | DOC RTN |
| At the limit, Project threads | Thread waits and continues on its own at reset; credits used only if you turned them on | DOC PROJ |
| Cache lifetime | One hour on subscription, five minutes once drawing usage credits | DOC https://code.claude.com/docs/en/costs |
| Promotional credit | BLOG only: one-time, existing individual Pro $100 / Max $250, claim by 2026-10-07 at claude.ai/code/claim-credit or `/claim-credit`, expires 2026-11-04, "isn't eligible for Projects or Routines". `/claim-credit` is absent from CMD and from every fetched docs page; the claim URL returned 403 to curl (measured: `curl -w %{http_code}`), so terms were not read | BLOG; DOC (absence) |

## 5. Releases after v2.1.284 that touch this contract (CHG, dated)

| Version (date) | Change |
|---|---|
| 2.1.285 (09-29) | Session creation and `/remote-env` no longer limited to newest 20 environments; MCP server name `widgets` reserved in cloud sessions; `MCP_DISCOVERY_CACHE=1` as an environment variable reuses connector tool lists after restart |
| 2.1.286 (09-30) | Routine runs whose session never started now show **Failed** (were Succeeded); late runs show "Due"; cloud sessions with very large histories no longer fail to wake |
| 2.1.287 (10-01) | Fixed occasional fetch/push failures when GitHub briefly refused a newly issued token; fixed conversation loss on restart during compaction |
| 2.1.288 (10-02) | Built-in `gh api` when the image lacks `gh` |
| 2.1.290 (10-05) | `--environment` creates sessions via "the current Sessions API"; `--teleport` stash no longer deletes files in a folder that replaced a tracked file; clearer error for cloud start without claude.ai sign-in; built-in `gh api` refuses non-github.com `GH_HOST` |
| 2.1.291 (10-06) | Fixes a 2.1.290 regression where cloud sessions could drop permission-prompt answers |
| 2.1.292 (10-06) | Routine runs no longer stay "running" for hours after finishing; restarted cloud sessions are told which background agents they can resume |

- INF: these are reliability fixes on the session/VM side; none adds a new dispatch or read surface. The in-VM Claude Code version is Anthropic's, not the pipeline's local v2.1.284.

## 6. Blog digest checked against docs

| Digest claim | Verdict |
|---|---|
| Fresh VM ~4 vCPU/16 GB/30 GB, new branch | Confirmed (ENV, QS) |
| Token outside VM, short-lived credential | Confirmed (SEC) |
| "for its own branch" / push only to own branch | **Contradicted by ENV/SEC** (see §2) |
| Repo config travels, `~/.claude` does not | Confirmed, with the single-repo caveat for hooks and `.mcp.json` |
| `claude -p "follow-up" --cloud <id>` | Confirmed (WEB) |
| `/claim-credit` | Not in docs |
| Setup script root, exit 0, ~5 min, 7-day rebuild | Confirmed (ENV) |
| Network levels, ~1 minute propagation | Confirmed (ENV) |
| Routines hourly minimum, three trigger types, hourly caps | Confirmed; numbers in §1 |
| 200 new threads/day for Projects | Confirmed (PROJ) |
| Bundle upload "no push-back" | Imprecise: push-back works when the GitHub connection has push access (WEB); only non-GitHub hosts cannot be pushed to |
| GitHub App needed for auto-fix and triggers | Confirmed; `/web-setup` does not enable webhooks (RTN) |

## 7. Alternatives considered

- **`claude -p --cloud "<task>"` as the dispatch**: ruled out, HEADLESS says it is rejected.
- **`--environment` headless dispatch**: ruled out for a Pro/Max account; `ccpool_` only, Team/Enterprise beta.
- **Pre-fill URL (`claude.ai/code?prompt=…&repositories=…&environment=…`)**: opens a form; needs a browser submit (QS).
- **Projects as the dispatcher**: no CLI/API surface, 200 threads/day, rollout-gated (PROJ).

## 8. Not determined

- Clone depth; reclaim timing; any concurrency ceiling on plain cloud sessions; GitHub-event cap numbers.
- Whether the push-scope restriction the repo runbook records still holds (docs say no restriction at the proxy).
- Whether `claude --cloud "<task>"` without `-p` works with no TTY; docs only describe the interactive checklist. The local `claude` binary was not found at `~/.local/bin/claude`, so `--help` was not read.
- Promotional-credit terms and whether credit applies to sessions created through the raw API or `--cloud`.
- Whether `/fire`-created sessions accept `claude -p --cloud <id>` follow-ups.
- support.claude.com articles were not fetched; one web search surfaced no page with credit or cap details beyond the docs.
