# S09: external prior art for live account moves (multi-account Claude Code pooling, rotation, in-session switching)

Slot: S09-external-prior-art. Date: 2026-10-25. Author: worker agent, read-only.
Scope: web and GitHub research into open-source tools that pool or rotate Claude Pro/Max subscription accounts for Claude Code, plus the official client's documented ways to switch accounts in a running session. I spot-checked a few load-bearing external claims against the extracted 2.1.293 source (`/tmp/mtam/cc293-src.js`, byte offsets below).

Safety: I printed, copied and stored no credentials. I ran no keychain command, launched no claude process and touched no pane. The only repo file I wrote is this one. Scratch downloads (READMEs, source files, docs, issue dumps) are in `/tmp/mtam/S09-external-prior-art/`.

---

## 1. Answer (summary)

**Prior art does change accounts mid-turn without a transcript fork.** Every tool that does it uses the same mechanism: a local HTTP proxy or relay on `ANTHROPIC_BASE_URL` that replaces `Authorization` on each `/v1/messages` request. Each API call in a tool loop is a separate HTTP request, and the client holds the transcript. A proxy can therefore move a session to another account between any two API calls, including in the middle of a tool loop. The client never notices, never exits, and keeps writing the same transcript file.

Tools that do this:
- better-ccflare
- TeamClaude
- claude-rotate
- Van Damme-o-Matic (vdm, loekj/claude-acct-switcher)
- SmelterLabs claude-account-switcher (a per-session relay)

None of them can move a request that is already streaming. Failover happens on a 429 or 401 at the request boundary: the request is resent on another account before any bytes reach the client.

**What a move costs, from tool docs and issues:**
1. **Prompt cache.** The cache is scoped to an organization, so the first request after a move rewrites the whole prefix on the new account (cache write at 1.25-2x input instead of a cache read at about 0.1x).
2. **Thinking blocks.** According to TeamClaude's docs, Sonnet 5.5 thinking blocks are bound to an organization and are dropped on a cross-org request. I did not verify this.
3. **Message threads.** In 2.1.293, server-side message threads ("tether") are on only for a first-party base URL. On first-party, a `continue` sent to another account gets `404 thread_not_found`, and the client replays the turn with a `create`. Behind a localhost proxy, threads are off and every request is stateless, which makes a move cheap.
4. **Base-URL side effects.** A non-first-party base URL turns off Remote Control and message threads. It changes the beta headers sent (prompt-caching-scope, tool search), drops the large-context request (SmelterLabs), and leaves hosted MCPs that call `api.anthropic.com` directly without a valid OAuth token.
5. **Refresh-token races.** Anthropic refresh tokens are single-use and rotate. Two holders of one refresh token kill each other (`invalid_grant`). A successful refresh revokes the previous access token at once, which cswap #381 measured. Proxies avoid the race in one of two ways:
   - They hold separate grants: their own PKCE login (better-ccflare, TeamClaude `login`), or `claude setup-token` one-year tokens with no refresh at all (claude-rotate, SmelterLabs).
   - They serialize refreshes under a lock with compare-and-swap adoption (better-ccflare's in-flight map plus a CAS DB update; TeamClaude's advisory row lock).

   Tools that share the official client's refresh token (TeamClaude `import` or `importFrom`, ccproxy, claude-swap) report exactly these races.

**Moves that do not need a proxy:**
- **Credential-store swap** (claude-swap, Symbioose). A running session picks up a swapped store on its next request on Linux and Windows (file mtime check). On macOS it takes up to about 30 s (keychain cache). The hazard: the live process can later write its old account's refreshed credential back over the swapped store (cswap #117).
- **Hooks-module plugin** (SmelterLabs, measured on 2.1.286). A plugin can call `$.env.set` on `ANTHROPIC_BASE_URL` or `CLAUDE_CODE_OAUTH_TOKEN`, and the change takes effect per request. I confirmed in 2.1.293 that `env.set` writes `process.env` directly (offset 11552107). The plugin has to be loaded when the session starts, with `CLAUDE_CODE_ENABLE_FUNCTION_HOOKS=1`.
- **`/login` in a session.** The official docs say it "switches the current session to the new login". It needs a person at an idle prompt.

**Enforcement:**
- One public report links a ban to a pooling tool: TeamClaude #529, dated 2026-10-07. A MAX 5X account was suspended 54 minutes after being added to TeamClaude, and the reporter may have altered device or session IDs.
- On 2026-09-08 the better-ccflare maintainer kept "session-affinity" out of the default strategy and asked users for ban reports first.
- Anthropic's legal page says OAuth is "designed to support ordinary use of Claude Code" and that Anthropic "may enforce ... without prior notice". The press dates a policy update to 2026-02-19 and, from secondary sources, an enforcement statement to 2026-04-04.

---

## 2. Method and commands (key output)

All shell commands were wrapped in `timeout`. GitHub was read with the authenticated `gh` CLI (read-only `search`, `repo view`, `api .../readme|contents`, `issue view`), and docs with `curl` or WebFetch.

1. `gh search repos` (script `/tmp/mtam/S09-external-prior-art/ghs.sh`) for "ccflare", "claude multiple accounts", "claude-code-router", "claude account switcher", "claude max proxy" and "claude subscription proxy". Hits used below. Star counts are as reported by `gh repo view` on 2026-10-25 (measured):

   | Repo | Stars | Created |
   |---|---|---|
   | tombii/better-ccflare | 274 | 2025-09-29 |
   | snipeship/ccflare | 1052 | |
   | router-for-me/CLIProxyAPI | 56168 | |
   | KarpelesLab/teamclaude | 445 | |
   | doxaras/claude-rotate | 38 | |
   | starbaser/ccproxy | 355 | |
   | farion1231/cc-switch | 148424 | |
   | musistudio/claude-code-router | 37838 | |
   | SmelterLabs/claude-account-switcher | 5 | |
   | rameezimdad/claude-auto-switch | 1 | |
   | loekj/claude-acct-switcher | 14 | |
   | Symbioose/claude-account-switcher | 85 | |
   | realiti4/claude-swap | | |

2. `gh api repos/<r>/readme` saved READMEs to `/tmp/mtam/S09-external-prior-art/readmes/`. I also pulled the TeamClaude `docs/routing.md`, `docs/accounts.md` and `docs/compliance.md`, and the SmelterLabs `TECHNICAL-GUIDE.md`.
3. Source pulled from better-ccflare: `token-manager.ts`, `proxy-operations.ts`, `pending-rotation-registry.ts`. From CLIProxyAPI: `claude_executor_cloaking.go`.
4. Issue keyword searches (`gh search issues --repo ...`) and `gh issue view` on:
   - better-ccflare #240, #301, #135, #89, #283
   - teamclaude #529, #543, #395, #554, #476
   - claude-swap #86, #37, #117, #279, #381, #31, #58
   - anthropics/claude-code #103325, #76561, #41886, #43978, #26777, #89785, #100182, #91411, #104258
5. The official CHANGELOG (`gh api repos/anthropics/claude-code/contents/CHANGELOG.md`, 1,085,784 bytes, top entry 2.1.310) was grepped with `/tmp/mtam/S09-external-prior-art/cl.py`.
6. Docs fetched with curl:
   - https://code.claude.com/docs/en/env-vars.md
   - https://code.claude.com/docs/en/authentication.md
   - https://code.claude.com/docs/en/settings-reference.md
   - https://code.claude.com/docs/en/legal-and-compliance.md
7. Source spot-checks with `python3 -I` regex over `/tmp/mtam/cc293-src.js` (scripts `grepsrc.py` and `ctx.py`). Offsets are in section 5.

---

## 3. Tool-by-tool findings

### 3.1 better-ccflare (tombii/better-ccflare; fork of snipeship/ccflare)
- **Mechanism.** It is an `ANTHROPIC_BASE_URL` proxy. With a Claude CLI OAuth login, you "Set only the base URL - no API key needed!" (README L300-312). The maintainer's comment on #89 (2026-03-17) says `prepareHeaders` "only removes `authorization`, `x-api-key`, and `host` — everything else passes through as-is, including any billing system prompt block". The pooled account's token is injected in their place. Body and headers are otherwise untouched, including the `x-anthropic-billing-header` system block and `anthropic-beta`.
- **Accounts.** Each account is its own OAuth login, made with `better-ccflare --add-account <name> --mode claude-oauth` (README L345). The proxy holds that account's grant, separate from the CLI's.
- **Refresh.** The proxy owns refresh. `token-manager.ts` dedupes in-flight refreshes per account (`refreshInFlight` map, L345-363) and adopts a rotated refresh token from the DB before refreshing (L328-338). It treats `invalid_grant|invalid_refresh_token|refresh_token_reused` as definitive (L141-148). `pending-rotation-registry.ts` keeps a rotation that a provider call completed but that was not persisted, and writes it with CAS methods (`updateAccountTokensIfRefreshTokenMatches`).
- **429.** "429s always trigger slot failover regardless of content-type" (`proxy-operations.ts` L615). There are retry and backoff settings (`RETRY_ATTEMPTS=3`). It returns 503 when the whole pool is exhausted. It honours `retry-after` and `x-ratelimit-reset` (L182-201).
- **Session strategy.** The default `LB_STRATEGY=session` routes all traffic to one account for a 5 h window. #240 (OPEN, 2026-05-27): "a request for project A could follow project B newer session and recreate cache entries on a different account" (cache thrash). A `session-affinity` strategy exists. Maintainer, 2026-09-08: "has anyone running `session-affinity` in production hit increased account bans or anti-abuse flags ... The dashboard currently withholds it from the strategy dropdown with a warning about exactly that risk".
- **Failure modes in issues:**
  - #301 (2026-07-09): a stale local 429 cooldown locks out an account that works fine without the proxy.
  - #135 (2026-04-21): usage polling hits 429, followed by "460 consecutive auto-refresh attempts".
  - #283 (2026-06-26): hosted MCP `api.anthropic.com/v1/design/mcp` ignores `ANTHROPIC_BASE_URL`, so a client without a real claude.ai login gets 401.
  - #89 (2026-03-17): OAuth endpoints moved from console.anthropic.com to platform.claude.com, and new scopes are required.
- **Other.** README L406: "Claude OAuth accounts ... are automatically excluded from Codex CLI traffic — Anthropic bans these when used outside Claude CLI."

### 3.2 TeamClaude (KarpelesLab/teamclaude, being renamed TeamRouter)
- **Mechanism.** README "How it works": "The proxy picks an eligible account, injects that account's real token, and rewrites `account_uuid` in the body to match". On a quota 429, "the request is resent on another account, so the client never sees the limit". There is also an optional MITM forward proxy that catches hard-coded `api.anthropic.com` endpoints such as the Design MCP.
- **Identity.** Maintainer on #529 (2026-10-07): "TeamClaude does not modify `device_id` or `session_id`... the only field the proxy rewrites is `account_uuid` in `metadata.user_id`".
- **Refresh.** "Refreshes OAuth tokens before they expire and writes them back to config. Client refreshes pass through untouched." `routing.md` L15: "Client token refresh requests (`/v1/oauth/token`) are relayed to upstream untouched — the proxy and client manage their own token lifecycles independently."
  - Accounts come from `teamclaude login` (a separate grant) or from `teamclaude import` / `importFrom ~/.claude/.credentials.json`, which shares the CLI's grant.
  - accounts.md L215: an account goes to `error` when "upstream has rejected [its refresh token] — typically because the same account was signed in somewhere else, which rotates the token and kills the copy TeamClaude holds".
  - accounts.md L126: "A refresh rotates the token family, and two installs renewing one account at once would each invalidate the other's copy". They use an advisory row lock: one install renews and the others adopt.
  - #554 (2026-10-13) is a lock-bypass bug where both installs renewed, `refreshed: [["rt-a-1"],["rt-a-1"]]`, and "whichever copy lost the race holds a dead refresh token".
- **429 handling.** It separates a quota 429 (rotate) from a burst 429 (pace on the same account: "Rotating on a rate-limit 429 would just move the burst to the next account and throw away the first account's prompt cache"). A request-scoped 429 gets one hop. It can hold the request open until a reset (`holdSeconds`).
- **Session affinity.** Requests are keyed by `x-claude-code-session-id`, narrowed by a digest of the conversation's opening. With `distributeSessions`, each new conversation is pinned to an account per weekly bucket. `TC_ACCT` gives a hard pin per launch. #543 (2026-10-11) asks for a per-live-session switch (`teamclaude switch <acct> --session $CLAUDE_CODE_SESSION_ID`). The maintainer accepted the design: "a server-side map from session id to account name, resolved per request". This is **exactly a live per-session account move with no client involvement.**
- **Prompt cache** (routing.md L340-342): "Claude Code resends the full transcript every turn ... a mid-session switch is invisible to the client." "The prompt cache is scoped to the account/organization that created it ... the first turn after a switch is a cache miss ... No proxy can share a cache across organizations."
- **Thinking blocks** (routing.md L73-82): "Since Claude Sonnet 5.5, a thinking block is bound to the organization whose account produced it ... When a later request in the same conversation goes out on an account of a different organization, the API drops those earlier Sonnet 5.5 thinking blocks". They cite platform.claude.com/docs/en/build-with-claude/preserved-thinking. I did not open that page.
- **Message threads** (accounts.md "Message threads"): "the first `/v1/messages` body carries `thread: {"type": "create"}` ... every later one carries `thread: {"type": "continue"}` with only the new delta". On another account, a continue gets `404 thread_not_found` "and the client then resends the whole conversation" (routing.md L157-176). I confirmed this in the 2.1.293 source (section 5).
- **Base-URL gate.** #395 (2026-09-14): in base-URL mode, "Claude Code still requires a valid canonical OAuth login ... before it sends any request". When the local login expires, the client fails with "OAuth session expired and could not be refreshed" even though the pool is healthy.
- **Overage headers.** #476 (closed 2026-09-27): overage headers from another org's account reach the client, so a mixed-org pool triggers Claude Code's extra-usage dial. The proxy has to sanitize response headers per account.
- **Ban report.** #529 (2026-10-07): "My subscription account (MAX 5X) ... after adding it to TeamClaude, it was banned within just 54 minutes." The reporter asks whether "modifying the `Device_ID` and `Session_ID`" triggered it, which suggests they altered them. The maintainer says TeamClaude does not alter them. The cause is unknown.
- **Compliance doc.** It claims "Claude Code's own `/extra-usage` flow already offers signing into a different account when you hit a limit". I could not find this string in the 2.1.293 source (searched "Switch account", "Use another account", "Log in with another": 0 hits). Unverified.

### 3.3 claude-rotate (doxaras/claude-rotate)
- **Mechanism.** A Python server proxy. Devices set `CLAUDE_CODE_OAUTH_TOKEN=<device key>` and `ANTHROPIC_BASE_URL` to the proxy. The proxy checks the device key and "swaps in the active account's long-lived setup-token". Upstream accounts are `claude setup-token` one-year tokens.
- **Refresh.** "No automatic token renewal. Setup tokens last ~1 year and die silently". The refresh-race problem does not exist, because neither side holds a refresh token. The env token also stops the client from refreshing or needing a local login, which sidesteps the TeamClaude #395 gate.
- **429.** Quota 429: rotate. Burst 429: pace, without rotating, "prompt caches kept warm". It has hold-until-reset. Stress test (their claim): "100 requests in flight → exactly 1 switch".
- **Limits.** "One active account, globally." "Switches drop warm prompt caches." Telemetry depends on the undocumented `anthropic-ratelimit-unified-*` headers.
- **ToS note.** "Rotating accounts to work past limits is a gray area"; "pooling/sharing/reselling access ... = violation". It reviews claude-relay-service (Wei-Shaw), which is built for account sharing ("拼车", carpooling): "account bans around such services are regularly reported". That is a claim with no specific citation.

### 3.4 Van Damme-o-Matic (loekj/claude-acct-switcher, `vdm`)
- **Mechanism.** A local proxy on :3334 via `ANTHROPIC_BASE_URL`. "The proxy replaces the auth header with the chosen account's token and forwards to Anthropic. On 429, it retries on the next account and sends new requests there." Accounts are found by running `claude login` repeatedly. Background token refresh runs every 5 min. On 401 it "refreshes token, then switches".
- **Keychain login stays put.** "The Keychain login (which Claude Code's artifacts and claude.ai connectors use) stays where it is". When everything fails it falls back to passthrough with the client's own auth header, so Claude Code "trigger[s] its own re-auth flow".
- **Session affinity and cache.** Affinity per session and subagent while the cache is warm. "When a running session jumps to another account, its whole cache is written again there (1.25-2x the input price instead of ~0.1x)". There is a "cache doctor" and a keep-warm that resends a `max_tokens: 0` request before the cache expires. They state that Claude Code uses a 1 h cache for main sessions on a subscription and 5 min for subagents.

### 3.5 SmelterLabs/claude-account-switcher (per-session billing; the closest analogue to "move a live session")
- **Mechanism.** A loopback relay `127.0.0.1:48620/acct/<name>/v1/...` that swaps `Authorization: Bearer <setup-token>`, plus a **hooks-module plugin**. At `session.start`, `turn.start` and `prompt.submit`, the plugin sets `ANTHROPIC_BASE_URL=http://127.0.0.1:48620/acct/<name>` in-process. `/account <name>` or a button "switches the current session from its next message".
- **Measured** (TECHNICAL-GUIDE, 2026-10-04, Claude Code 2.1.286):
  - (2) "In a plain CLI engine, `$.env.set("CLAUDE_CODE_OAUTH_TOKEN", …)` from a plugin wins per request".
  - (3) In a Desktop session the env route is dead: a host-auth channel adopts the host credential into memory.
  - (4) "`ANTHROPIC_BASE_URL` is read per request even in a desktop session."
- **Rejected routes:** `apiKeyHelper` ("desktop sessions never call it", and "the OAuth-via-helper bug #97350 is open"); per-project settings `env`; swapping profile login files (needs a restart).
- **Side effects** of a routed session:
  - The usage panel and the startup email show the login account, not the routed one.
  - The setup-token is inference-only: `/api/oauth/profile` and `/api/oauth/usage` return 403.
  - claude.ai connectors, cloud routines and Remote Control stay on the app login.
  - "through the relay the engine seems not to request the large-context window it uses on the direct path, so a ~261k-token prompt got 'Prompt is too long' only when routed."
- **Requirements.** `CLAUDE_CODE_PLUGIN_DIRS` and `CLAUDE_CODE_ENABLE_FUNCTION_HOOKS=1` in settings env. "existing sessions do not load the plugin".

### 3.6 claude-swap / cswap (realiti4/claude-swap) and Symbioose/claude-account-switcher: credential-store swap
- **Mechanism.** They back up each account's credential and restore the chosen one into Claude Code's active slot: the keychain item `Claude Code-credentials` (Symbioose names its backups `claude-switcher:{email}`), or `.credentials.json`.
- **Live pickup** (claude-swap README Tips): "On Linux and Windows ... Claude Code re-reads them whenever that file changes, so the new account takes effect on your next message ... On macOS, credentials live in the Keychain, which Claude Code caches for about 30 seconds; a running session picks up the switch once that cache expires."
  - #37 (2026-06-05, maintainer): "Claude Code has a helper function that detects credential file mtime changes and refreshes the cache".
  - #86 (2026-07-04): a stale leftover `~/.claude/.credentials.json` next to an active keychain blocked the in-place pickup on macOS. Moving the file aside fixed it.
  - Official changelog 2.1.86: "macOS keychain cache extended from 5s to 30s".
- **Locks.** "Switches ... hold Claude Code's own credential locks while writing, so a swap never interleaves with a token refresh". Their `proper_lockfile` port had a double-takeover bug (#420).
- **Hazards in issues:**
  - #117 (2026-07-09): "The running session later refreshes its OAuth and writes **account 2's** refreshed credentials back over the live files (Claude Code doesn't know about the switch)". The live identity flipped back by itself, with the log line "Switched from account 2 to 2". I have not checked whether 2.1.293's `$hr()` CAS-save stops this; whether that save adopts a sibling's newer write or overwrites it is the question.
  - #381 (2026-09-21, measured): spending a refresh token that another holder also has "Anthropic revokes the predecessor access token as soon as the refresh succeeds. Every Claude Code session on the default login then fails on its next request". Superseded access tokens "hours away from their `expiresAt`" returned "401 OAuth access token has been [revoked]". Sessions showed "403 OAuth token does not meet scope requirement … Please run /login".
  - #279 (2026-08-25): fears about the keychain ACL under `security add-generic-password -U`. The maintainer checked the 2.1.263 binary and found it uses `security` for reads and writes, and that `-U` keeps the ACL.
  - README: "Do not run `/logout` first: current Claude Code may revoke the refresh token stored for the account you are leaving."
- **Ban questions.** #31 (2026-04-30) and #58 (2026-06-17) both ask about bans. The maintainer says switching is equivalent to manual logout/login. No ban reports.

### 3.7 claude-auto-switch (rameezimdad, 2026-10-21)
Its `StopFailure` hook runs when a turn fails with `rate_limit`. It saves the session ID, closes Claude Code, and runs `claude --resume <same id>` on the next config dir. This is **the same design as the incumbent `cc-lr move`**, triggered at turn failure, and gives no mid-turn capability.

### 3.8 Others (less relevant)
- **CLIProxyAPI** (router-for-me): wraps a Claude Code OAuth login as an OpenAI, Gemini or Claude API for other clients. It round-robins across multiple accounts. `claude_executor_cloaking.go` impersonates Claude Code: `injectFakeUserID`, `computeFingerprint` ("the 3-char build fingerprint that Claude Code embeds in cc_version"), and `generateBillingHeader` (x-anthropic-billing-header). This is the "third-party harness on subscription OAuth" pattern that Anthropic's legal page prohibits. It is not usable as a design model.
- **ccproxy** (starbaser): `anthropic_oauth` auth source that shares `~/.claude/.credentials.json` with the CLI and refreshes in-process. Its write is atomic (tmp, fsync, rename), but nothing stops a double refresh against one refresh token.
- **cc-switch** (farion1231): switches providers and config (hot-switching local proxies, failover). It is not a subscription-account pool.
- **claude-code-router** (musistudio): routes between models and providers. No subscription pooling found.
- **CCS** (kaitranntt/ccs): an account-switch wrapper via CLIProxyAPI. I did not inspect it.

---

## 4. Official client: documented ways to switch accounts in a running session

| Mechanism | Evidence | Mid-turn? |
|---|---|---|
| `/login` in a session | authentication.md L243: "If you run `/login` while the variable is set, Claude Code switches the current session to the new login". Changelog 2.1.118: "Fixed `/login` having no effect in a session launched with `CLAUDE_CODE_OAUTH_TOKEN` — the env token is now cleared so disk credentials take effect" | No. Interactive, needs an idle prompt. |
| Login made in another process is picked up | Changelog 2.1.281: "Fixed the 'Not logged in · Run /login' footer ... persisting in a session after logging in from another Claude Code process". Changelog 2.1.286: "Fixed macOS sessions still showing 'Not logged in' ... after `/login` succeeds in another Claude Code window when a leftover `~/.claude/.credentials.json` exists" | Yes, at the next request or after the cache TTL. Only within the same config dir or keychain item. |
| Credential change mid-session is a supported state | Changelog 2.1.271: "Fixed a cached organization policy being reused after switching accounts ... and the policy not refreshing until the hourly check when the credential changes mid-session". 2.1.268: "Fixed a running session silently switching to the organization's default model when another Claude Code process refreshed a stale model-access entry" | Implicitly. |
| Reactive refresh and re-read on 401 | Changelog 2.1.117: "the token is now refreshed reactively on 401". 2.1.0: "Fixed a race condition where stale OAuth tokens could be read from the keychain cache during concurrent token refresh attempts". 2.1.225: "Fixed a transient 401 replacing a long-lived `CLAUDE_CODE_OAUTH_TOKEN` with a stored login's short-lived token" | Yes, on the 401 path. |
| Keychain cache TTL | Changelog 2.1.86: "macOS keychain cache extended from 5s to 30s" | Bounds pickup latency. |
| `apiKeyHelper` TTL | settings-reference: output "sends ... as both the `X-Api-Key` and `Authorization: Bearer` headers"; reruns "After the cache lifetime, five minutes by default or ... `CLAUDE_CODE_API_KEY_HELPER_TTL_MS`", and on 401/403, and on an expired JWT (v2.1.246+). Changelog 0.2.74: "with a 5 minute TTL". But changelog 2.1.139: Remote Control, `/schedule`, claude.ai MCP connectors "are now disabled when `ANTHROPIC_API_KEY` / `apiKeyHelper` / `ANTHROPIC_AUTH_TOKEN` is set" | Per request, but it is an API-key path. SmelterLabs cites an open OAuth-via-helper bug, #97350, which I did not open. |
| `CLAUDE_CODE_OAUTH_401_WAIT_MS` | **Not documented** in env-vars.md (grep: 0 hits). Present in source at offsets 1799404 and 4661036 | n/a |
| `CLAUDE_CONFIG_DIR` per account | authentication.md L47-52 "Log in with multiple accounts" ... L211: "keys the macOS Keychain entry to that directory too" | No. Fixed at launch. |
| `ANTHROPIC_BASE_URL` | env-vars.md: "Override the API endpoint to route requests through a proxy or gateway ... As of v2.1.196, Remote Control is disabled when this points at a host other than `api.anthropic.com`" | Read per request (SmelterLabs, measured). |

Refresh-race bugs in the official tracker show the problem is still live in 2.1.29x-2.1.30x:
- #103325 (OPEN, 2026-10-19, 2.1.296-2.1.303): "the refresh token is single-use, two processes read the same one, both send it, the second gets `invalid_grant`, and the client treats that as a dead login".
- #76561 (OPEN, 2026-07-11): "Credential writes replace symlinks with private regular files" (atomic rename). "On refresh failure, the CLI overwrites the credentials file with a logged-out stub" (`expiresAt: 0`), which can clobber the shared source.
- #80085: "Repeated mid-session logouts on macOS with concurrent instances sharing one Keychain OAuth chain".
- #91009, #88947: more reports of the same race.
- Changelog fixes over time: 2.1.126 ("concurrent credential write could clear a valid OAuth refresh token"), 2.1.129, 2.1.133 ("parallel sessions all dead-ending at 401 after a refresh-token race wiped shared credentials"), 2.1.136, 2.1.248, 2.1.282.
- #41886 (2026-04-01, closed stale): quota appeared pooled per `organizationUuid`, and `.claude.json` `oauthAccount` leaked across `CLAUDE_CONFIG_DIR`s. This is relevant to the `account_uuid` in `metadata.user_id`.

Policy (legal-and-compliance.md L52-59):
- "OAuth authentication is intended exclusively for purchasers of Claude Free, Pro, Max, Team, and Enterprise subscription plans and is designed to support ordinary use of Claude Code and other native Anthropic applications."
- "developers may not collect, store, or intermediate Claude.ai credentials or session tokens."
- "Nor does it prevent an end user from signing in to the unmodified Claude Code binary with their own Claude subscription."
- "Anthropic reserves the right to take measures to enforce these restrictions and may do so without prior notice."

Press coverage: Anthropic updated its docs on 2026-02-19 (gigazine.net, winbuzzer.com and alternativeto.net articles listed in section 7). A Taiwanese secondary source reports an "official ban on third-party tools like OpenClaw" on 2026-04-04. Those reports concern third-party harnesses, not multiple accounts on the genuine client.

Ban reports in anthropics/claude-code with no link to any tool: #91411 (2026-09-02), #100182 (2026-10-07, blamed on a reconnect loop), #104258 (2026-10-22).

---

## 5. Source spot-checks in 2.1.293 (`/tmp/mtam/cc293-src.js`)

Command: `python3 -I /tmp/mtam/S09-external-prior-art/grepsrc.py <patterns>`. Hits and counts are measured.

- `thread_not_found` at 12372944. The error classifier `Hhe()` maps 404 `thread_not_found` to `"not_found"`. The retry resolver `go()`: `case"not_found":return Ye=!0,Hn("replay_not_found"),"retry:tether-replay"`, where `Hn` logs `[tether] forcing create for retry`. A continue that lands on the wrong account costs **one failed request plus a full replay as `create`**.
- The tether gate `ab()` at 12362076: `if(!nh())return!1;if(Pe()!=="firstParty")return!1; ... gcr()`, and `gcr()` returns `CLAUDE_CODE_TETHER_LIVE` if set, else `if(!Of())return!1;return C("tengu_curious_tower",!1)`.
- `Of()` at 2000767: `let e=process.env.ANTHROPIC_BASE_URL;if(!e)return!0;return $g(e)`, where `$g` checks host `["api.anthropic.com"]`. Message threads are therefore **off behind a localhost proxy** unless `CLAUDE_CODE_TETHER_LIVE` forces them. `CLAUDE_CODE_ASSUME_FIRST_PARTY_BASE_URL` exists (14 hits) and short-circuits a related check just before `Of`. `process.env` is read live in `Of`, not cached at module load. The gate result itself is memoized (`e.tetherLiveGate??=gcr()`), so a base-URL change mid-session does **not** turn threads off once they are on.
- `env.set` handler `EIo` at 11552107: `if(e.value===void 0)return delete process.env[e.name] ...; return process.env[e.name]=e.value`. A hooks-module plugin can mutate the live process environment. Hook events found near 4918706 include `turn.start`, `turn.step`, `tool.call`, `tool.check`, `classic.PreToolUse` and `clock.every`, so a per-step or timer hook exists. I did not check whether `env.set` can be called from those events.
- `CLAUDE_CODE_ENABLE_FUNCTION_HOOKS`: 2 hits (2251829, 5252824). `CLAUDE_CODE_PLUGIN_DIRS`: 17 hits.
- Host-auth markers SmelterLabs cites: `CLAUDE_CODE_HOST_AUTH_ENV_VAR` (17 hits), `host_auth_token_refresh` (6), `cli_worker_auth_refresh_adopted` (1, at 25899417).
- `tengu_oauth_401_recovered_from_keychain` at 4663853 and `CLAUDE_CODE_OAUTH_401_WAIT_MS` at 4661036 match the lead's read.
- `x-claude-code-session-id`: 0 literal hits (TeamClaude keys on this header; the header name may be built at runtime). `account_uuid`: 56 hits starting at 4159300.

---

## 6. Implications for a mid-turn account move (for the synthesis lead)

1. **The only proven mid-tool-loop, no-fork mechanism in the wild is per-request credential substitution at the HTTP layer.** It can sit in a proxy on `ANTHROPIC_BASE_URL`, or in-process through a plugin's `env.set`. Everything else (`/exit` + `--resume`, StopFailure + resume, `/login`) needs a turn boundary.
2. **Refresh ownership has to be one holder per refresh-token family.** Every tool that let both the client and the proxy refresh the same grant (TeamClaude import, ccproxy, claude-swap backups) reports `invalid_grant` logouts. The proven-safe patterns:
   - The proxy holds its own grants (a separate `/login` or PKCE per account), and the client keeps its own login only to pass the local gate.
   - `claude setup-token` one-year tokens, which never refresh. These are inference-only (403 on `/api/oauth/profile` and `/api/oauth/usage`).

   Copying a keychain credential from `next4`'s item into another config dir's item creates a second holder of one family. That is the same race, and Anthropic revokes the old access token immediately on the next refresh (cswap #381).
3. **Expect one cache rebuild per move and per conversation**, and for subagents too. If the client is on first-party threads, expect a thread replay as well. The rebuild hits the target account's quota at cache-write prices.
4. **Base-URL proxying changes client behaviour, and those changes are locked in at launch.** Message threads are off, the tether gate is memoized, Remote Control is off, the large-context request is dropped (SmelterLabs), hosted MCPs bypass the proxy, and some betas are not sent. Sessions that are already running were launched without a proxy, so a proxy cannot be added under them without a restart. That leaves only the credential-store path (keychain item or `.credentials.json` pickup, at most about 30 s on macOS) or the 401 recovery path for sessions running tonight.
5. **Enforcement risk is real but poorly documented.** There is one tool-linked ban report (TeamClaude #529), and maintainers are being cautious (better-ccflare #240). The policy line is "ordinary use of Claude Code" and no intermediation by third-party developers.

---

## 7. URLs cited
- https://github.com/tombii/better-ccflare (README; issues #89, #135, #240, #283, #301)
- https://github.com/snipeship/ccflare
- https://github.com/KarpelesLab/teamclaude (README; docs/routing.md, docs/accounts.md, docs/compliance.md; issues #395, #476, #529, #543, #554)
- https://github.com/doxaras/claude-rotate
- https://github.com/loekj/claude-acct-switcher
- https://github.com/SmelterLabs/claude-account-switcher (README, TECHNICAL-GUIDE.md)
- https://github.com/realiti4/claude-swap (README; issues #31, #37, #58, #86, #117, #279, #381)
- https://github.com/Symbioose/claude-account-switcher
- https://github.com/rameezimdad/claude-auto-switch
- https://github.com/router-for-me/CLIProxyAPI (internal/runtime/executor/claude_executor_cloaking.go)
- https://github.com/starbaser/ccproxy
- https://github.com/farion1231/cc-switch
- https://github.com/musistudio/claude-code-router
- https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md
- https://github.com/anthropics/claude-code/issues/103325, /76561, /41886, /43978, /26777, /89785, /80085, /91009, /100182, /91411, /104258
- https://code.claude.com/docs/en/authentication.md
- https://code.claude.com/docs/en/env-vars.md
- https://code.claude.com/docs/en/settings-reference.md
- https://code.claude.com/docs/en/legal-and-compliance.md
- https://gigazine.net/gsc_news/en/20260220-anthropic-third-party-block
- https://winbuzzer.com/2026/02/19/anthropic-bans-claude-subscription-oauth-in-third-party-apps-xcxwbn/
- https://alternativeto.net/news/2026/2/anthropic-officially-bans-using-subscription-authentication-for-third-party-claude-use
- https://en.kocpc.com.tw/?p=3671 (secondary, April 2026 claims; not an official source)

## 8. Open questions
- Does a 2.1.293 session started without a plugin re-read `CLAUDE_CODE_OAUTH_TOKEN` and `ANTHROPIC_BASE_URL` from `process.env` per request? Only the plugin route can mutate `process.env`, and plugins load only at session start.
- Can a hooks-module `env.set` be issued from `turn.step`, `tool.call` or `clock.every`, giving a true mid-tool-loop switch rather than one at `turn.start`?
- Does 2.1.293 `$hr()` CAS-save stop the cswap #117 write-back (a live process overwriting a swapped store with its old account's refreshed token)?
- Is the thinking-block organization binding (TeamClaude routing.md L73-82) real for the models the operator uses? I did not verify it on platform.claude.com.
- Are the operator's 4 accounts separate organizations? If any share an org, the quota is pooled (#41886) and a move between them buys nothing.
- What is the ban signal? Is it the `account_uuid` rewrite, concurrency, device_id/session_id changes, or nothing tool-specific? There is no public data beyond TeamClaude #529.
