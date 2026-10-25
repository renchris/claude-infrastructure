# S11 — built-in `claude gateway` and the "gateway" (Cloud gateway) provider

Slot: S11-builtin-gateway. Date: 2026-10-25. Binary: Claude Code 2.1.293 (BUILD_TIME 2026-10-07T06:36:42Z, GIT_SHA 3abc54a9…, read from the embedded build constants).
Read-only study. No session launched, nothing written except this file and scratch under /tmp/mtam/S11/. No token or credential was read or printed.

## Method

- Source: `/tmp/mtam/cc293-src.js` (52,710,919 bytes, measured by `ls -la`). Grepped with byte offsets through a helper
  `/tmp/mtam/S11/g.py` (`python3 -I`, `re.finditer` over the file bytes, prints `d[s-w:s+w]` windows).
- The gateway server is a separate bun chunk, `/$bunfs/root/chunk-9927pzfe.js`, embedded in the same file. I cut it out by
  finding its `export{SOe as startGateway}` (offset 30,274,211) and the previous `// @bun` marker (offset 28,826,249), giving a
  1,448,011-byte slice saved as `/tmp/mtam/S11/gwchunk.js` (measured by the python slice). "chunk+N" below means offset N in that slice;
  "src+N" means offset N in cc293-src.js.
- `claude gateway --help` (allowed command) prints: `Usage: claude gateway [options] / Run the enterprise auth/telemetry gateway / --config <path> Path to gateway YAML config`.
- Docs: `https://docs.claude.com/en/docs/claude-code/llm-gateway` returns 301 to `https://code.claude.com/docs/en/llm-gateway` (fetched);
  also fetched `https://code.claude.com/docs/en/claude-apps-gateway` and `https://code.claude.com/docs/en/claude-apps-gateway-config`
  (first 100k of 140k chars). One standard web search.

## 1. What it is

Official name: **Claude apps gateway**. It runs from the `claude` binary itself. In the client it is called the "Cloud gateway".

- src+19,710,741: commander registration
  `s.command("gateway").description("Run the enterprise auth/telemetry gateway").requiredOption("--config <path>",…).action(async({config:g})=>{…let{startGateway:A}=await import("/$bunfs/root/chunk-9927pzfe.js") … R(await A(g),v6t)`
  and `s.hook("preSubcommand",(g,A)=>{if(A===v)UEo(!0)})`. UEo sets the `gatewayServerProcess` credential slot, which is what `ken()` returns.
- src+1,998,909: `lw={…, gateway:"Cloud gateway"}`. src+1,999,666:
  `function Pe(){if(co()||ken()||Cen())return"gateway"; return a.CLAUDE_CODE_USE_BEDROCK?"bedrock":…:"firstParty"}`. The provider is
  "gateway" when a gateway credential is in the slot (`co()`), when this process is the gateway server (`ken()`), or when host policy requires a gateway (`Cen()`).
- src+2,441,607 (settings schema): `forceLoginMethod: "claudeai" for Claude Pro/Max, "console" for Console billing, "gateway" for the Cloud gateway OIDC device flow`,
  plus `forceLoginGatewayUrl` ("Honored only from admin-controlled managed settings").
- Docs (claude-apps-gateway): "a self-hosted service that sits between your developers' Claude Code clients and your model provider.
  Developers sign in with your corporate identity provider (IdP) instead of holding API keys or cloud credentials. The gateway holds the upstream credential…"
  It ships in v2.1.195+.

## 2. Gateway YAML schema (chunk+1,288,500 to ~1,310,000; zod `bhe`)

Top-level keys, with their defaults as written in the source:
- `listen`: `host` (default "0.0.0.0"), `port` (default 8080), `tls{cert,key}`, `public_url` (required unless host is loopback), `trusted_proxies[]`.
- `access_control{allow_cidrs[],deny_cidrs[]}`, `limits{max_request_bytes=32MiB,…}`, `rate_limits{device_authorization,device_verify}`, `timeouts{upstream_ttfb_ms=120000}`.
- `upstreams[]` (min 1, ordered; each has an optional `name`, `headers`). The provider is a discriminated union:
  - `anthropic`: `base_url` (default `https://api.anthropic.com`), and `auth` is exactly one of:
    `{api_key}` | `{oauth_token}` | `{federation_rule_id, organization_id, identity_token_file, service_account_id?, workspace_id?}`; `forward_user_identity?`
    (refused for anthropic.com hosts "so user emails are never sent to Anthropic").
  - `bedrock`, `mantle`, `anthropicAws`, `anthropicGoogleCloud`, `vertex`, `foundry` (each with cloud credentials).
- `auto_include_builtin_models` (default true), `models[]{id,label?,description?,upstream_model{<upstreamName>: <model>}}`.
- `oidc` (**optional** in the schema): `issuer, client_id, client_secret | client_assertion(private_key_jwt), groups_claim, email_claim, scopes, allowed_email_domains, allowed_groups, google_groups, …`.
- `session{jwt_secret (string or array, each ≥32 chars), ttl_hours=1}` (required).
- `store{postgres_url (required, postgres://), username, password, max_connections=5, connect_timeout_seconds=5, readiness_grace_seconds}`.
  QL at chunk+1,314,130 rejects the old `dev:` key: "the gateway is Postgres-only".
- `telemetry{forward_to[]{url,headers,auth.google,metrics,logs,traces}, resource_attributes}`, `managed{settings|policies[]{match{groups,email_domain},cli,settings,desktop,serve_to_desktop}}`,
  `admin{read_keys,write_keys,admin_groups,…}`, `enforcement{fail_closed_on_error}`, `load_test_mode`, `cri{enabled,audience,jwks_url,issuer}`.

Config reload: the source has no SIGHUP handler and no file watch (`SIGHUP`, `watch(` and `config.reload` each have 0 hits in the chunk, measured). Docs: "The gateway reads the file once, at startup", and "Admin UI: Not available — Configuration is the YAML file; redeploy to change it."

## 3. What the gateway process does

`SOe` (startGateway) at chunk+1,409,755 does the following in order: loads the YAML, connects to Postgres (`jN(r.store.postgres_url,…)`), builds the
session-JWT keys (`me=TO(r.session.jwt_secret)`), runs OIDC discovery if `oidc` is present (`r.oidc?tS(r.oidc):null`), builds the upstream clients
(`wS(r.upstreams,…)`), builds the managed policies (`eN(r)`), and then listens on `listen.host:port`. It serves:
- the device-code OIDC sign-in and `/oauth/token` (grant `device_code` and `refresh_token`; refresh calls the IdP, `cn.refresh(...)`, then re-mints the JWT; chunk+1,431,684);
- `/managed/settings`, `/user/bootstrap` (Desktop), `/api/oauth/usage` (answered by its own spend module, not by the upstream), OTLP fan-out, `/v1/models`, and inference on `/v1/messages` and `/v1/messages/count_tokens`;
- `/healthz` and `/readyz`.

**Client authentication** (chunk+1,431,9xx):
`Tm=pe.headers.get("authorization"),Ju=Tm?.startsWith("Bearer ")?Tm.slice(7):null … Ht=await vg(Ju,me,De)`. On failure:
`Wt(401,"authentication_error","invalid token")`. `vg`/`MO` (chunk+1,226,950, 1,225,945) work as follows: HS256 JWT, `aud:"claude-gateway"`, `iss` = public_url, `kid` = sha256(secret)[:8],
claims `{sub,email,name,groups}`, expiry `ttl_hours`. A second admission path is "CRI" (customer-routed inference), which verifies against Anthropic JWKS.
The client's own credentials never reach the upstream. Upstream `applyAuth` first runs `n.delete("authorization"),n.delete("x-api-key")`.

**Upstream authentication** (`wS`, chunk+1,260,6xx):
```
if("oauth_token"in n.auth){let d=n.auth.oauth_token;return{kind:"raw",…applyAuth:async(p)=>{r(p),p.set("Authorization",`Bearer ${d}`),p.append("anthropic-beta",Zu)}…
```
with `Zu="oauth-2025-04-20"` (src+1,671,754). That is the claude.ai OAuth capability beta. So technically an `oauth_token` upstream is sent exactly the way a
subscription OAuth access token is sent. It is a **static string read once at startup**: there is no refresh path for `oauth_token`. Only the federation (WIF) variant
has a `TokenCache` and `invalidateAuth`. Docs confirm: "The bearer is read once at startup, so refresh by remounting the secret and restarting."

**Upstream selection** (`OS`, chunk+1,270,657; caller at chunk+1,437,581):
`rn=await OS(pe,Kt,Pm,r.models,r.auto_include_builtin_models,vw,…,{body:Un,…user:Ie})`. `Pm` is the **one global upstream list** built at boot.
The loop `for(let re of r){… _i(h,re,i,n,ee) …}` tries the upstreams in config order. It skips an upstream that does not resolve the model. It **fails over on 5xx/429/401/403/404 or a thrown error**
(`if(…(me.status>=500||me.status===429||me.status===401||me.status===403||me.status===404)){…continue}`), and keeps no record of failed upstreams (docs: "Every request starts at the first upstream").
The user identity `Ie={sub,email}` is passed only for `forward_user_identity` headers and Bedrock assume_role session names. **It is never used to choose an upstream.**
`managed.policies` select settings and `availableModels` per group, not an upstream.
- Model-to-upstream pinning (`_i` / `P1`, chunk+1,257,072): `c=s?.upstream_model[t.name]; if(c)return{ok:!0,model:c}`. For a **custom** model id
  (one that `mI()` does not recognise as a built-in), an upstream that is absent from `upstream_model` returns an error and is skipped. Docs: "Only a custom model `id`, one that isn't a built-in
  Claude model, skips the upstreams absent from its `upstream_model:` map."
- Response headers: `I1` (chunk ~1,259,9xx) drops every header starting `anthropic-ratelimit-`:
  `if(!t.includes(o)&&!o.startsWith("anthropic-ratelimit-"))r.set(n,i)`. So the client never sees the upstream's unified rate-limit/utilization headers.

## 4. Client side ("gateway" provider)

In EN(), the API client factory at src+8,643,522:
```
if(Pe()==="gateway"&&!co()&&!ken()){… throw new iwt("Not signed in to the Cloud gateway — run /login.","signin_required")}
…
if(Rt==="gateway"){await _6();let Qe=co();if(!Qe||FEo()&&!aYt())throw Qe?.unpinned?new iwt("Cloud gateway token expired — refresh ANTHROPIC_AUTH_TOKEN and restart.","token_expired"):new iwt(jAt,"session_expired");
 …return new Zme({...Ze,defaultHeaders:{...Et,...T_(),Authorization:`Bearer ${Qe.jwt}`},apiKey:null,baseURL:Qe.url,authToken:Qe.jwt,…})}
```
- `co()` (src+1,633,570) returns `n().host.credentialSlots.gatewayAuth()`, an in-memory slot shaped `{url,jwt,expiresAt,unpinned?,idpRefreshToken?,tokenEndpoint?,revocationEndpoint?,email?,hostVerdict?}`.
  `FEo()` is `expiresAt<=Date.now()`. `ken()` is the gateway-server-process flag.
- `_6()` (src ~4,609,0xx) works as follows. If `aYt()` holds (`CLAUDE_CODE_PROVIDER_MANAGED_BY_HOST && co()?.unpinned`), it re-runs `kl()`, which re-reads `ANTHROPIC_AUTH_TOKEN` or the descriptor/FD token
  and replaces the slot if the jwt differs. Otherwise it refreshes through `WH()` (POST `${url}/oauth/token`, grant refresh_token) only when the jwt is within `$H=300000` ms (5 min) of expiry.
  The refreshed credential is persisted with `zn().mutate(h=>({...h,enterpriseGateway:g}))`, which is secure storage, i.e. the same per-config-dir credential store.
- Env path `kl()`: `CLAUDE_CODE_USE_GATEWAY` + `ANTHROPIC_BASE_URL` + (`ANTHROPIC_AUTH_TOKEN` | `CLAUDE_CODE_GATEWAY_TOKEN_FILE_DESCRIPTOR` / bg snapshot via `Qit()`)
  produces `eQ({url,jwt,expiresAt:<jwt exp>,unpinned:!0})`. "Unpinned" means it came from the environment, so `/login` cannot refresh it. That is where the "refresh ANTHROPIC_AUTH_TOKEN and restart" message comes from.
- **Per-request re-read**: yes, as far as EN() is concerned. Every client build calls `_6()` and reads `co()` fresh, so a new jwt **and a new baseURL** placed in the
  slot take effect on the next client build. (That EN() runs per request comes from the brief's prior finding and was not re-verified here.) The slot changes only through
  /login, a refresh, or (when `CLAUDE_CODE_PROVIDER_MANAGED_BY_HOST`) a changed env/descriptor token. A changed jwt changes the *identity seen by the gateway*, not the upstream account.
- Docs list what gateway sessions lose: WebSearch is disabled, Remote Control is not available, feature-flag fetching is skipped, first-party optimisations (global cache scope, token-efficient tools) are off,
  and the prompt cache defaults to the 5-minute TTL. "Claude Code uses one sign-in at a time: a gateway sign-in takes the place of a Claude for Teams or Enterprise login." "The gateway token is the session's only credential … any earlier claude.ai login [is] ignored."

## 5. Docs on subscriptions

- llm-gateway ("Subscriptions and gateways"): "While a gateway credential variable or `apiKeyHelper` is active, requests carry that credential in place of a developer's claude.ai subscription login, and the subscription's usage limits don't apply to them … That traffic is billed per token to whoever owns the credential the gateway forwards, such as your organization's Anthropic Console account, or your Amazon Bedrock, Google Cloud's Agent Platform, or Microsoft Foundry account." It also says: "Setting only [ANTHROPIC_BASE_URL], without a gateway credential, doesn't replace the subscription … a saved claude.ai login remains the active credential … Gateways that pass this traffic on to Anthropic must forward the OAuth capability in `anthropic-beta`." That describes a *pass-through* proxy, which is not the built-in gateway: the built-in gateway strips the client's Authorization header.
- claude-apps-gateway: the upstream must be "Amazon Bedrock credentials, Claude Platform on AWS credentials, Google Cloud credentials, a Microsoft Foundry resource, or an Anthropic API key. Multiple upstreams are supported with failover." "They don't need a claude.ai account, an API key, or a subscription." It is positioned as an alternative to Claude Enterprise.
- claude-apps-gateway-config: `oauth_token` is "Use the bearer form when your org issues short-lived tokens instead of long-lived API keys", and its example is a WIF-exchanged token. Neither page mentions a Pro/Max or `setup-token` token as an upstream (per the WebFetch summary over the first 100k chars of the config page).

## 6. Answer

**Could it carry per-request account selection for subscription accounts?**
- Mechanically, only partly, and only in crude ways. The `anthropic` upstream accepts `auth.oauth_token` and sends it as `Bearer` plus `anthropic-beta: oauth-2025-04-20`.
  In principle, four `claude setup-token` long-lived tokens could be four upstreams. Two routing mechanisms would then exist:
  (a) **429 failover**: every request starts at upstream[0] and moves on when it gets 429/5xx/401/403/404. That is per-request, automatic and stateless, but it always tries the first account, cannot rebalance, and has no notion of session or user.
  (b) **custom model aliases** (`models: [{id: "opus-acct2", upstream_model: {acct2: claude-opus-…}}]`) pin a model id to one upstream. The account would then be chosen by whatever model id the client sends. Whether a running CC session changes its model id per request without disruption is untested.
- The gateway **cannot** choose an upstream per client, session or user: one global ordered list, with the identity unused for routing. Config is read once, there is no hot reload, and `oauth_token` is never refreshed, so normal ~8h Max access tokens would die. Only 1-year setup-tokens fit.
  It also needs Postgres, a jwt_secret, and in practice OIDC or a self-minted HS256 JWT given to the client through `CLAUDE_CODE_USE_GATEWAY`+`ANTHROPIC_AUTH_TOKEN`.
  It strips `anthropic-ratelimit-*` headers, so the client's own 5h/7d utilization view goes blind.
  Moving a live first-party session onto it means switching the session's provider to "gateway", which costs WebSearch, Remote Control, flags and 1h cache. A session that is already running on firstParty would need /login or a restart, which is the same disruption we are trying to avoid.
- **Official support**: built and documented for enterprise/API/cloud billing only. The docs say that gateway traffic does not use subscription limits and is billed per token to the owner of the forwarded credential. The documented Anthropic upstream credentials are a Console API key, an org-issued short-lived bearer (WIF example), or WIF. Using a Max subscription token as an upstream is not documented, not supported, and probably contrary to consumer terms (see S08). Treat it as unsupported.

## Open questions
- Does api.anthropic.com accept a `setup-token` OAuth token forwarded by the gateway (UA suffix `cc-gateway/<ver>`, client body otherwise unchanged)? Untested; testing would need a live run, which is outside this slot's rules.
- Does a running CC session read its model per API call, so that alias-based routing could switch accounts between requests without /model? Not checked.
- Would a non-builtin model id (alias) degrade the client's capability detection (context window, thinking, 1M)? Not checked.
- Was EN() per-request construction confirmed for gateway mode? Taken from the brief, not re-verified.
