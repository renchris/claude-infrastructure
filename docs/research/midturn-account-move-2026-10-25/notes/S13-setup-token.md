# S13 — what `claude setup-token` mints, and whether four of them can back a per-request account-switching proxy

Slot: S13-setup-token. Date: 2026-10-25. Subject: Claude Code 2.1.293 (BUILD_TIME 2026-10-07T06:36:42Z, GIT_SHA 3abc54a9).

## Method

- Source: `/tmp/mtam/cc293-src.js` (52,710,919 bytes, measured with `ls -la`). I searched it with byte offsets using `python3 -I` and `re.finditer`, then printed windows of `d[s-a:s+b]`. The helper scripts are in `/tmp/mtam/S13/` (`g.py` counts pattern hits, `w.py` prints a window, `ctx.py` prints context for each hit, `def.py` prints function definitions). Every command was wrapped in `timeout 60`.
- The only binary invocations were `claude setup-token --help` and `claude auth login --help`.
- Docs fetched: https://code.claude.com/docs/en/authentication and https://support.claude.com/en/articles/10310342-how-do-i-log-out-of-all-active-sessions. I also fetched three claudeissues.com mirrors of GitHub issues: #22995, #48373 and #92529.
- No token or credential was read, printed or written. No keychain call was made.
- Minified names collide across chunks, so `xf`, `W7`, `dr` and `J2` each have several unrelated definitions. Every name cited below is pinned to the offset of the definition that I checked belongs to the auth chunk.

Hit counts (measured, `g.py`):

| pattern | hits |
|---|---|
| `setup-token` | 27 |
| `long-lived` | 14 |
| `inference-only` | 2 |
| `inference_only` | 2 |
| `user:inference` | 7 |
| `31536000` | 6 |
| `CLAUDE_CODE_OAUTH_TOKEN` | 136 |
| `OAUTH_401_WAIT` | 2 |
| `keeping the user-supplied` | 1 |
| `user:profile` | 6 |

## Findings with offsets

### 1. Constants and scopes (offset ~1,671,526)

```
var jJ=31536000;var ASo=Math.round(jJ/86400),xA="user:inference",K9="user:profile",vlt="user:plugins",...
function $1n(t){return Array.isArray(t)&&t.includes(xA)}
var E="org:create_api_key",Zu="oauth-2025-04-20",c=[E,K9],r=[K9,xA,"user:sessions:claude_code","user:mcp_servers","user:file_upload"];
```

- `jJ` is 31,536,000 s, which is 365 days.
- A normal `/login` requests `org:create_api_key user:profile user:inference user:sessions:claude_code user:mcp_servers user:file_upload user:plugins` (`TSo()` together with `klt()`).
- OAuth config: `CLAUDE_AI_AUTHORIZE_URL: https://claude.com/cai/oauth/authorize`, `TOKEN_URL: https://platform.claude.com/v1/oauth/token`, `MANUAL_REDIRECT_URL: https://platform.claude.com/oauth/code/callback`, and the same `CLIENT_ID 9d1c250a-…` that `/login` uses.

### 2. The command handler `EIs` (offset ~28,506,039)

```
function R(c){return{ok:!0,days:ASo,seconds:jJ}}
async function EIs(c,d){i("tengu_setup_token_command",{});let t=R(d?.expiresInDays); ...
  hLe(!0) ... "setup-token creates a long-lived Claude.ai subscription token, which this policy does not permit."
  ... e(_,{..., mode:"setup-token", expiresIn:t.seconds, urlOutdent:1})
```

- The lifetime is hard-coded to 365 days. `R()` ignores `expiresInDays`, and `setup-token --help` lists only `-h` (measured). There is no flag to change it.
- The command is refused when `forceLoginMethod` or `allowedProviders` policy forbids it.
- It renders an Ink TUI, the `ConsoleOAuthFlow` component in chunk-8w81t5xr. If an env or API-key credential already exists, it only shows a warning and continues.

### 3. The flow in the `YSe` component (offset ~28,162,761 to 28,170,120)

- With `mode==="setup-token"`, the component starts in state `ready_to_start` and forces `loginWithClaudeAi=true`, so the flow goes to claude.ai and not to Console.
- The OAuth call is:
  `_e.startOAuthFlow(cb,{loginWithClaudeAi:u,inferenceOnly:_==="setup-token",expiresIn:_==="setup-token"?v??jJ:void 0,orgUUID:Ne})`
- Unlike `/login`, it does not pass `forceLoginOrgUUID` through `ge`. The docs confirm this: setup-token "enforce[s] only forceLoginMethod".
- On success:
  `if(_==="setup-token")B({state:"success",token:me.accessToken,expiresAt:me.expiresAt??void 0})`
  Only the access token is displayed ("Your OAuth token (valid for 1 year)… Store this token securely. You won't be able to see it again… export CLAUDE_CODE_OAUTH_TOKEN=<token>").
- The persistence call `h1e(...)` sits in the `else` branch, so setup-token never writes the keychain or `.credentials.json`. Any refresh token in the response is dropped.

### 4. The authorize URL and token exchange (offsets ~4,699,000 and ~23,636,000)

- `Ngr(...)`: `let N=T?T.scopes:h?[xA]:TSo();` When `inferenceOnly` is set, the scope parameter is exactly `user:inference`.
- `Plo(...)`: `if(h!==void 0)w.expires_in=h;` The authorization-code exchange POSTs `expires_in: 31536000` to `TOKEN_URL`.
- `x$.startOAuthFlow` opens a localhost callback listener. It prints a manual URL whose redirect is `platform.claude.com/oauth/code/callback`, then calls `Hs(p)` to open the browser. It waits for either the localhost callback or a pasted `code#state`.
- `formatTokens` copies `refresh_token` and `refresh_token_expires_in` if the server returns them, but the setup-token branch ignores both.

### 5. How the client treats an inference-only grant with no refresh token (`Bhr`, offset ~4,654,000)

```
if(!t2(e.scopes))return i("tengu_oauth_tokens_not_claude_ai",{}),{success:!0};
if(!e.refreshToken||!e.expiresAt)return i("tengu_oauth_tokens_inference_only",{}),{success:!0};
```

The client names a claude.ai grant that has no refresh token "inference_only". This strongly suggests the server issues long-lived inference-only grants without a refresh token. That is an inference from the event name and has not been checked on the wire.

### 6. How `CLAUDE_CODE_OAUTH_TOKEN` is consumed (`m$`, offset ~4,655,135)

```
if(a.CLAUDE_CODE_OAUTH_TOKEN)return{accessToken:a.CLAUDE_CODE_OAUTH_TOKEN,refreshToken:null,expiresAt:null,scopes:Dk(),
  subscriptionType:a.CLAUDE_CODE_SUBSCRIPTION_TYPE||null,rateLimitTier:a.CLAUDE_CODE_RATE_LIMIT_TIER||null};
function Dk(e=["user:inference"]){return hA()??[...e]}   // hA = CLAUDE_CODE_OAUTH_SCOPES override
```

- An env token takes precedence over the keychain: `mn()` and `b$()` return it first.
- Its `refreshToken` is null, so there is no refresh, no keychain read and no keychain write.
- `Cst()` and `dqe()` return false when `CLAUDE_CODE_OAUTH_TOKEN` is set, which turns off the credential-change watch and the bg-snapshot plan lookup.
- `subscriptionType` and `rateLimitTier` are null unless the operator sets `CLAUDE_CODE_SUBSCRIPTION_TYPE` and `CLAUDE_CODE_RATE_LIMIT_TIER`. Without user:profile the profile cannot be fetched to fill them.
- `dr()` (offset 4,677,058) returns `e.subscriptionType??BA()??null`. With an env token the plan is therefore unknown to the client unless those env vars are set.

### 7. Feature gates that check scopes (auth-chunk helpers at offset ~4,673,249)

The helpers:

- `_t()`: `rl()&&t2(scopes)`. It means "claude.ai subscriber" and is TRUE for a setup-token, because the token carries user:inference.
- `xf()`: `scopes.includes("user:profile")`. It is FALSE for a setup-token.
- `W7(s)`: checks for a single scope.
- `LA()`: true for profile, office or ccr_inference.

Features lost with only `user:inference` (offsets measured):

| feature | gate | offset |
|---|---|---|
| `/usage` utilization fetch (`/api/oauth/usage`) | `if(!_t()\|\|!xf())return{}` | 8,976,581; also 23,435,632, 30,763,844 ("no_profile_scope") |
| Profile fetch / org UUID lookup | `!xf()` | 4,705,811; 4,706,494 |
| Bootstrap (model options, model access, org default model) | tries scopeless bearer; on 403 "Skipped: 403 for OAuth token without profile scope" | 18,241,010 |
| Fast-mode org check (`/api/claude_code_penguin_mode`) | `gd()=xf()\|\|(ccr_inference…)`. Without it, no prefetch; falls back to cached `penguinModeOrgEnabled` in that config's `.claude.json`, else "disabled (preference, guess)". Bypass: `CLAUDE_CODE_SKIP_FAST_MODE_ORG_CHECK` | 4,252,476; 4,263,533 |
| claude.ai MCP connectors | `scopes.includes("user:mcp_servers")`, "inference token lacks user:mcp_servers scope" | 11,810,447; 36,803,808 |
| Team/org memory sync | `Kl()` returns "scope" unless `W7(xA)&&W7(K9)` | 6,007,258; 6,060,676 |
| Claude in Chrome | `cAe()` needs profile, office or ccr_inference: "OAuth token has no scope accepted by /api/oauth/validate" | 8,545,271 |
| Metrics status, referral, cloud peer, GitHub app check | `xf()` | 23,504,141; 8,961,921; 25,464,632; 10,890,670 |
| Plan-gated client features | `dr()===null` gives "plan_unreadable" (e.g. 9,233,888). Remote-control eligibility treats a null plan like team/enterprise (5,248,438). `LMn` model-entitlement fallback needs `dr()` in pro/max/team (4,314,515). | — |
| Remote Control, `/v1/code/*`, `RemoteTrigger` | need `user:sessions:claude_code`. The docs say a setup-token "can't establish Remote Control sessions or fetch claude.ai connectors". Issue #92529 lists sessions-scope endpoints. | docs |

The docs also say: "It can only make model requests … MCP servers you configure locally still work."

### 8. 401 handling with an env token (`y$`, offset ~4,661,048 to 4,663,700)

The order of recovery:

1. The SDK `getOAuthToken` callback (`oSe`), if one exists, is the only in-process rotation path.
2. If `Pfs()` holds (env token set, not a remote session, no `ANTHROPIC_UNIX_SOCKET`), the client logs: "OAuth 401: keeping the user-supplied CLAUDE_CODE_OAUTH_TOKEN instead of adopting the stored credential. Mint a fresh token with `claude setup-token` and restart with it, or unset the variable and run /login." It never falls back to the keychain.
3. It waits `h$()` = `CLAUDE_CODE_OAUTH_401_WAIT_MS`. The default is 0 locally and `cp` only in remote sessions. During the wait, `BRs` polls `process.env.CLAUDE_CODE_OAUTH_TOKEN`, which is in-process env that nothing outside the process can change, and the CCR fd token.
4. Otherwise it returns false and the request fails. In remote children only, `CLAUDE_CODE_AUTH_FAIL_EXIT_MS` (default 600,000 ms) leads to `process.exit(1)` ("zombie exit").

Consequence: a local session with an env token cannot be re-pointed mid-flight from outside. The only way to switch accounts is something on the wire, such as a proxy.

### 9. A related headless path (offset ~28,716,451)

`claude auth login` accepts `CLAUDE_CODE_OAUTH_REFRESH_TOKEN` with `CLAUDE_CODE_OAUTH_SCOPES` and runs `aye(refresh,{scopes,expiresIn:jJ,...})`, then stores the result. This is a non-browser login from an existing refresh token. It shows that the token endpoint also accepts `expires_in` on the refresh grant. It is not part of setup-token.

### 10. Prior art in the binary for an auth-injecting forwarder

`ANTHROPIC_UNIX_SOCKET` combined with `CLAUDE_CODE_OAUTH_TOKEN=ssh-placeholder` is how `claude ssh` works (`eys`, offset 3,817,119). The client's own explanation at offset 4,026,914 reads: "This session sends every request through a local socket (ANTHROPIC_UNIX_SOCKET) — as a `claude ssh` session does, or to a forwarder of your own". There are also "the claude ssh launcher injects a different credential" and `tunnelCredentialEpoch` handling (offset 16,219,316). Under the socket, bootstrap is skipped (18,241,010) and 401 handling does not take the `Pfs()` "keep env token" path. These are outside this slot's question, but relevant to the proxy design.

### 11. Metadata caveat (offset ~8,876,959)

`metadata.user_id` is JSON that includes `account_uuid` taken from the client's cached `oauthAccount`, plus `device_id` and `session_id`. If a proxy swaps the bearer to another account, this field no longer matches the bearer's account unless the proxy rewrites it. I have not checked how the server reacts to a mismatch.

## Answers

### (1) Lifetime, scopes, refresh

- An access token lasting 365 days (`expires_in=31536000`, fixed and not configurable in 2.1.293), with scope exactly `user:inference`, issued to the standard Claude Code client_id through the claude.ai authorize endpoint. Confidence 0.95, from source.
- No refresh token is kept or used. The CLI shows only `accessToken`, and the env-token path hard-codes `refreshToken:null`. Whether the server even returns one is not shown on the wire; `tengu_oauth_tokens_inference_only` suggests it does not. Confidence 0.85.
- There is no rotation. When the year is up you mint a new token.

### (2) Billing, limits and models

- The docs say the token "authenticates with your Claude subscription and requires a Pro, Max, Team, or Enterprise plan".
- Server-side quota is keyed by the account/org behind the bearer. I infer, without a measurement, that it shares the same 5-hour and weekly unified buckets as that account's `/login` sessions; nothing in the client separates the two.
- Model entitlement (Opus, Fable with its 1M native window, fast mode) is decided by the server per org. The client side has these differences:
  - Bootstrap model data may be missing because the scopeless call can get a 403.
  - Without `CLAUDE_CODE_SUBSCRIPTION_TYPE=max`, `dr()` is null. That marks the plan unreadable and disables the `LMn` fallback entitlement.
  - The fast-mode org check is skipped and falls back to the cache or `CLAUDE_CODE_SKIP_FAST_MODE_ORG_CHECK`. Fast mode bills to usage credits anyway.
- Lost client features (section 7): `/usage` utilization, profile/org lookup, claude.ai MCP connectors, Remote Control and sessions APIs, org memory sync, Claude in Chrome, metrics/referral and others.
- Utilization is still visible from the `anthropic-ratelimit-unified-*` response headers on each inference call.

### (3) How many, revocation, effect on other logins

- I found no per-account cap. Issue #92529 reports an account with "228 live OAuth tokens … only 54 ever carried user:sessions:claude_code". That is a third-party report and suggests a large number of concurrent grants is tolerated.
- Revocation: claude.ai Settings > Claude Code (or Settings > Account sessions), using the trash icon. "Log out of all active sessions" also revokes "tokens created with setup-token for continuous integration (CI)" (support article 10310342).
- There is no CLI list or revoke. Feature request #48373 was closed as a duplicate; #22995, asking for a dashboard and per-token revoke, was closed "not planned".
- Minting does not touch the local stored login: the persistence branch is skipped and there is no revoke call. Server-side, each authorization-code exchange is a separate grant. I found no evidence that minting revokes other grants.
- A password change or "log out of all sessions" kills every setup-token as well.

### (4) Is a browser needed?

- Yes: a human has to complete the claude.ai sign-in and consent in a browser. The browser can be on another machine, using the manual URL and pasting `code#state` at "Paste code here if prompted >".
- The command renders an Ink TUI and needs an interactive terminal for the paste. It cannot run unattended: there is no flag, no refresh-token path and no client-credentials grant.
- Once minted, the token can be used unattended for up to a year. Renewal means a human repeats the flow once a year per account.

### (5) What happens on a 401 with an env token

See section 8. The client keeps the env token and does not fall back to the keychain. It waits only if `CLAUDE_CODE_OAUTH_401_WAIT_MS` is set, polling in-process env. Otherwise the request fails, with the hint to re-run `claude setup-token`.

## Conclusion: four setup-tokens held by a local proxy

**Yes, with caveats.**

Each setup-token is an independent, refresh-less grant with a one-year lifetime. A proxy holding four of them, one per account, owns no refresh token. It therefore cannot take part in the single-use refresh-token rotation that the official clients do through each config dir's keychain item. Nothing the proxy does writes or invalidates `Claude Code-credentials-<hash>`. It can set `Authorization: Bearer <token for account N>` on each `/v1/messages` request, so account choice is per request, including mid-turn between two API calls.

Caveats that matter to the design:

- (a) The proxy has only inference scope, so per-account quota is visible only from response rate-limit headers, not from `/api/oauth/usage`.
- (b) Prompt cache is per org (the client tags system blocks `cacheScope:"org"`). The first request after a switch re-writes the whole cached prefix on the new account, which costs quota.
- (c) `metadata.user_id.account_uuid` will name the client's cached account, not the bearer's.
- (d) How the client reaches the proxy (`ANTHROPIC_BASE_URL` or `ANTHROPIC_UNIX_SOCKET`) changes which client features stay on. For example, `pi()` is false under a non-anthropic base URL.
- (e) Server-side policy/ToS on routing one session across four subscriptions is S08's question.
- (f) "Log out of all sessions" or a password change on an account silently kills that account's proxy token. The proxy must treat a 401 as "this account is gone" and must not wait for a rotation.

## Sources

- https://code.claude.com/docs/en/authentication ("Generate a long-lived token"; precedence item 5; "enforce only forceLoginMethod")
- https://support.claude.com/en/articles/10310342-how-do-i-log-out-of-all-active-sessions
- https://claudeissues.com/issue/92529-setup-token-intermittently-issues-cli-oauth-tokens-missing-user-sessions-claude
- https://claudeissues.com/issue/48373-feature-request-claude-setup-token-list-and-revoke-id-subcommands
- https://claudeissues.com/issue/22995-feature-add-centralized-session-token-management-dashboard-for-claude-code-max-s
