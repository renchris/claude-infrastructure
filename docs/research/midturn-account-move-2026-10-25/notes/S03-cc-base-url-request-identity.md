# S03 — cc base URL / request identity (what a local proxy sees and must rewrite)

Slot: S03-cc-base-url-request-identity
CC version: 2.1.293 (Bun binary `~/.claude-293/.../bin/claude.exe`, built 2026-10-07, GIT_SHA 3abc54a9…).
Source read: `/tmp/mtam/cc293-src.js` (52 MB minified). All offsets below are byte offsets into that file unless marked "binary".

READ-ONLY run. No credentials printed. No panes touched. No sessions launched. Scratch scripts in `/tmp/mtam/S03/`.

## Method

- Built grep helpers `/tmp/mtam/S03/g.py` (regex → byte offset + context window) and `at.py` (slice at offset). Ran with `python3 -I`, every call wrapped in `timeout 60`.
- Enumerated endpoint path literals with `/tmp/mtam/S03/ep.py` and `ep2.py`.
- Cross-checked against Anthropic's own "Claude Code gateway compatibility guide" (`https://code.claude.com/docs/en/llm-gateway-protocol`, saved to `/tmp/mtam/S03/gwdoc.txt`) and two reverse-engineering writeups for the `cch` attestation (devday.kr, socket.dev diff — unofficial).
- Searched the native binary (`bin.py`) for the `cch=`/`x-anthropic-billing-header` strings to confirm the attestation path is compiled in.

---

## (1) Does an OAuth (subscription) session honor ANTHROPIC_BASE_URL / ANTHROPIC_UNIX_SOCKET, and what is gated on a first-party base URL

### Honored: YES.

Provider selection `Pe()` (@2000346) returns `"firstParty"` unless a cloud-provider env var is set — `ANTHROPIC_BASE_URL` does NOT change the provider; an OAuth/claude.ai login stays `firstParty`. The base URL is applied directly to the SDK client:

- Client factory `EN({...})` (@8638580): for the subscription branch (`Me` = isSubscriber), the returned client is `new Zme({apiKey:Ne.apiKey, authToken:Ne.authToken, ...a.ANTHROPIC_BASE_URL?{baseURL:a.ANTHROPIC_BASE_URL}:!1, ...})` (@8650496). So the OAuth bearer is sent to whatever `ANTHROPIC_BASE_URL` points at. **A localhost proxy set via ANTHROPIC_BASE_URL receives the live subscription bearer on /v1/messages.** (load-bearing)
- `ANTHROPIC_UNIX_SOCKET`: `Ji()` fetch-options builder (@2092360) returns `{...o, unix:i}` when `a.ANTHROPIC_UNIX_SOCKET` is set and `forAnthropicAPI`. So inference can be routed over a unix domain socket. But note `rl()` (@4625893): when `ANTHROPIC_UNIX_SOCKET` is set, OAuth is considered "enabled" only if `CLAUDE_CODE_OAUTH_TOKEN` is also set (`if(a.ANTHROPIC_UNIX_SOCKET)return!!a.CLAUDE_CODE_OAUTH_TOKEN`). A plain claude.ai keychain login over a bare unix socket is treated as no-auth / ssh-placeholder (`eys()` @3817119, `S7t="ssh-placeholder"`). So **ANTHROPIC_BASE_URL=http://127.0.0.1:PORT is the clean lever for a subscription session; ANTHROPIC_UNIX_SOCKET additionally wants CLAUDE_CODE_OAUTH_TOKEN and flips many features to thirdParty.**

### The first-party gate: `Of()` / `pi()` / `Sl()`

- `$g(e)` (@2001?): host must be exactly `api.anthropic.com` (`return["api.anthropic.com"].includes(t)`).
- `Of()` (@2000918): `ANTHROPIC_BASE_URL` unset → true; else `$g(base)`.
- `pi()` (@2000869): `_CLAUDE_CODE_ASSUME_FIRST_PARTY_BASE_URL` set → true, else `Of()`.
- `Sl()` (@2000799): `Pe()==="firstParty" && pi()` — "first-party backend" master gate.
- So pointing `ANTHROPIC_BASE_URL` at `http://127.0.0.1:…` makes `Of()/pi()/Sl()` all **false** — UNLESS you also set `_CLAUDE_CODE_ASSUME_FIRST_PARTY_BASE_URL=1`, which forces `pi()=true` (but NOT `Of()`; some paths check `Of()` directly, e.g. `qzt()` @8640029, and Remote Control explicitly says the assume flag "does not apply to Remote Control" @7923314). (load-bearing — the assume flag re-enables most but not all first-party features behind a proxy.)

Counts (measured via g.py TOTAL): `pi()` 54 call sites, `Sl()` 36, `Of()` 24, `ANTHROPIC_UNIX_SOCKET` 56.

### What a non-first-party base URL disables / changes (each is a behavior the proxy design must accept or neutralize)

- **Attribution/billing header `cch` + gateway-hint billing stamps** gated on `firstParty&&pi()` (@5434119, see (2)).
- **Gateway hint headers** (`x-claude-code-request-class`, `-agent-type`, `-compaction`, `-context-compacted`, `-prev-tool-durations`, `-prompt-id`): `Skn()` (@8638xxx) returns false on a custom base URL unless `CLAUDE_CODE_GATEWAY_HINT_HEADERS=1` (gwdoc lines 133-143). Off by default behind a proxy.
- **Model discovery / `/v1/models` picker augmentation**: `Ud()` requires `pi()` false → disabled unless gateway model discovery flag (@4294332; gwdoc §Model discovery, `GET /v1/models?limit=1000`).
- **Served model catalog** (`X1()`/`oa()` @4308563) returns null when `!Sl()`.
- **Fine-grained tool streaming** default off behind custom base URL (`vCt()` @10531483; gwdoc line 210).
- **Tool search optimistic default** disabled when `firstParty&&!pi()` (@5990996).
- **Usage/limit UI, `/api/oauth/usage` polling, policy-limit reads, cache keepalive, memory sync, error reporting, crimson/vector image sizing, model fallback stamps, extra-usage, team/teleport, Remote Control bridge** — all guard on `pi()`/`Of()`/`Sl()` (see call-site dump in `/tmp/mtam/S03/pi.txt`, `of.txt`, `sl.txt`). Notable:
  - `/api/claude_code/policy_limits` read `sio()` requires `firstParty&&Of()` (@16189114) — returns null behind proxy.
  - Usage fetch `zF()`/`hH()` require `_t()&&xf()` (@8976xxx); still hit `${BASE_API_URL}/api/oauth/usage` — i.e. the hard-coded `cn().BASE_API_URL=https://api.anthropic.com`, NOT ANTHROPIC_BASE_URL (see (3)).
  - `BG()` CCR remote-control bridge: `false` when `ANTHROPIC_UNIX_SOCKET` or `!Of()` (@7913009).
  - `l5()` (@11585202) classifies the "effective provider" as `thirdParty` when `!pi()` (except ssh-remote unix socket), which flips auto-mode server classifier eligibility.
- **Managed-policy lookup** can refuse: "the session's configuration (such as a custom ANTHROPIC_BASE_URL) prevents the policy lookup" (@2689365). Under `allowedProviders` managed settings, a custom base URL may be rejected outright (@4027906). If the operator's org pushes managed settings this is a hard blocker.

Net for the design: a localhost HTTP proxy at `ANTHROPIC_BASE_URL` is honored for inference and carries the live OAuth bearer, but **turns off the first-party-only telemetry/UX** unless `_CLAUDE_CODE_ASSUME_FIRST_PARTY_BASE_URL=1` is also set. The proxy must forward (not strip) `anthropic-beta`, `anthropic-version`, `cache_control`, and all body fields to avoid breaking inference (gwdoc §Feature pass-through).

---

## (2) Every identity-bearing header and body field on a /v1/messages request

Client default headers assembled in `EN()` (@8638580) via `ww()`, `lwt()`, `T_()`, `dL()`, then `.beta.messages.create(..., metadata:KWe())`.

### Headers

- **`Authorization: Bearer <oauth access token>`** — the subscription bearer. Set by `Xcs()` (@5435037): `isSubscriber ? {apiKey:null, authToken: oauthAccessToken}`. This is THE account selector. (load-bearing: swapping this bearer per-request is the whole mechanism.)
- **`anthropic-beta`** — includes OAuth capability value `Zu="oauth-2025-04-20"` (@1671759). The gwdoc (line 124, 274) states that for a claude.ai login this header "carries an OAuth capability that the upstream requires, and **stripping it fails those requests with 401**." So a proxy must keep `anthropic-beta` intact even when it rewrites the bearer. Beta set also carries feature betas (context-management, interleaved-thinking, effort-…, claude-code-20250219, tool betas).
- **`x-api-key`** — NOT set in the subscription path (`apiKey:null`). Present only for API-key auth. Irrelevant to the Max-account case.
- **`anthropic-version: 2023-06-01`** (gwdoc line 123).
- **`User-Agent`** = `VH()` (@4094553): `claude-cli/2.1.293 (external, cli)` plus optional `agent-sdk/…`, `client-app/…`, `workload/…`. Not account-specific.
- **`x-app`** = `"cli-bg"` (background) or `"cli"` (`ww()` @8638580). Not account-specific.
- **`X-Claude-Code-Session-Id`** (header const `iTt`, @4273752) = `K()` = session UUID. Per-session, NOT per-account. Stays constant across an account move within one session.
- **`x-claude-code-agent-id` / `-parent-agent-id`** — subagent IDs (only on subagent requests). Not a user id.
- **`x-claude-remote-session-id` / `x-claude-remote-container-id` / `x-client-app` / `x-claude-remote-session-origin`** — only when the matching env vars are set (remote/SDK). Not relevant here.
- **Gateway-hint headers** `x-claude-code-request-class`, `-agent-type`, `-compaction`, `-context-compacted`, `-prev-tool-durations`, `-prompt-id` — only when `Skn()` true (first-party default, or hint-headers flag). Carry request-class/tool-timing/prompt-UUID, no account id.
- **`x-anthropic-additional-protection: true`** only if `CLAUDE_CODE_ADDITIONAL_PROTECTION` env set.
- **No `x-organization-uuid` on /v1/messages.** `x-organization-uuid` appears only on `auth:"teleport-org"` side calls in `gr()` (@4427?: `b={...zYt(ee),"x-organization-uuid":Q}`), not on inference. Org is derived server-side from the bearer.

### Body fields

- **`metadata.user_id`** — built by `KWe()` (@8876959) as a JSON string of:
  `{ ti?, device_id:sI(), account_uuid: (CLAUDE_CODE_ACCOUNT_UUID if remote) || iL()?.accountUuid || Mn()?.accountUuid || "", session_id:K(), parent_session_id?, tk? }`.
  - `account_uuid` = the signed-in account's UUID. `iL()` (@4676059) = `BEo()` = `credentialSlots.authenticatedAccount()` (@1634249); `Mn()` (@4676059) = `ce().oauthAccount`. **This is the per-account field embedded in the body.** (load-bearing: if the proxy swaps only the Authorization bearer but leaves the body's `metadata.user_id.account_uuid` pointing at the old account, the request carries a mismatched account identifier. Server likely bills by bearer, but the mismatch is observable and may be validated.)
  - `device_id` = `sI()` (@4575567) = a random 32-byte hex stored as `generatedUserID` in config state — a stable per-config-dir pseudo-id, **not** a real hardware device id. Each config dir (next/next2/…) has its own.
  - `session_id` = session UUID (same as the header).
  - There is a length cap (`dE`); when extra metadata pushes over, it drops user-supplied keys first.
- **`model`, `messages`, `system` (with attribution block), `max_tokens`, `thinking`, `output_config`, `context_management`, `tools`, `cache_control`, `safeguards`** — standard; the gwdoc warns body rewriting breaks beta/body pairing and preserved-thinking (`bound to a different conversation`). A proxy must pass the body through unchanged except for whatever it deliberately rewrites.

### Client attestation / signing — the `cch` billing hash (IMPORTANT)

- `wio()` (@5433446) builds `x-anthropic-billing-header: cc_version=2.1.293; cc_entrypoint=…; cch=00000; cc_workload=…; …`. The `cch=00000` placeholder is emitted only when `m==="firstParty"&&pi()||m==="vertex"` (@5434119). The string is confirmed compiled into the native binary (`bin.py`: `cch=00000` at binary offset 80288561 and `x-anthropic-billing-header` at 80152940 / 80288788).
- Per unofficial RE (devday.kr, socket.dev diff for a nearby version): Bun's native (Zig) HTTP layer rewrites the `00000` placeholder in-flight with an **xxHash64 of a canonicalized projection of the request body** (reset cch to zeros, blank model value, drop fallback fields + max_tokens, compact-JSON re-serialize), masked to ~20 bits. Seeds/salt are undocumented and change per version. (NOT confirmed in our own source read beyond the placeholder string; treat algorithm as medium-confidence third-party.)
- Design consequences (load-bearing):
  1. The attribution block is prepended to the `system` array; `api.anthropic.com` strips it positionally only if forwarded unchanged and first. A proxy that reorders/merges system blocks pushes it into the prompt and the cache key (gwdoc §System prompt attribution block).
  2. If the proxy **rewrites the body** (e.g. to fix `metadata.user_id.account_uuid`), any native `cch` recomputation happens on the ORIGINAL body before the proxy sees it (the client computes it, then sends). The proxy sits downstream of the native rewrite, so it receives a body whose `cch` already matches that body. If the proxy then mutates the body, the `cch` no longer matches — the server may reject/untrust. Safest: set `CLAUDE_CODE_ATTRIBUTION_HEADER=0` (gwdoc line 192, env opt-out honored unless the ignoreEnvOptOut auto-mode-classifier exception at @5433456 applies) so no `cch` is sent, OR rewrite only headers (Authorization) and leave the body byte-identical.
  3. Because the placeholder is gated on `firstParty&&pi()`, pointing at a plain proxy without the assume flag already **omits `cch`** — convenient. With `_CLAUDE_CODE_ASSUME_FIRST_PARTY_BASE_URL=1`, `pi()` becomes true and `cch` comes back (but `Pe()` is still firstParty so `m==="firstParty"&&pi()` is true → placeholder emitted). So the assume flag re-introduces the attestation constraint.

---

## (3) Every OTHER endpoint called with the OAuth token during a session, and cross-account risk if the bearer is swapped

Key fact: side endpoints resolve their base URL from **`cn().BASE_API_URL` = hard-coded `https://api.anthropic.com`** (@1672000), NOT from `ANTHROPIC_BASE_URL`. So a proxy on `ANTHROPIC_BASE_URL` sees **only `/v1/messages` (+ `/v1/messages/count_tokens`, `/v1/models`, `HEAD /api/hello`)**. The identity/usage/profile endpoints go straight to api.anthropic.com with whatever bearer `mn()` currently returns. (load-bearing: the proxy cannot intercept these; they will carry the CURRENT keychain bearer, which the mid-turn-move design is trying to change.)

Endpoints found (enumerated via ep.py/ep2.py; base = `cn().BASE_API_URL` unless noted):

- **Inference (via ANTHROPIC_BASE_URL)**: `/v1/messages`, `/v1/messages/count_tokens` (optional), `/v1/models?limit=1000` (discovery, treats redirect as failure, 3s timeout), `HEAD /api/hello` + `/v1/oauth/hello` (preconnect — skipped when a proxy/cert is configured, `@18469395`).
- **Profile / identity (api.anthropic.com, OAuth bearer)**: `/api/oauth/profile` (`qVe()` @4582519, `Authorization: Bearer`), `/api/claude_cli_profile` (@4582087, uses x-api-key + account_uuid param), `/api/oauth/validate` (`mf()` @4583532, Bearer). Break/leak: if bearer swapped, these would report the OTHER account's profile → the UI's displayed plan/email would drift from the account the transcript thinks it is on. They are not on the proxy path so they keep the keychain bearer.
- **Usage / limits (api.anthropic.com, Bearer)**: `/api/oauth/usage` (+ `?at_wall=1`, `?cedar_ember=1`) `zF()` @8975920; `/api/claude_code/policy_limits` `sio()` @16189114. Both validate against `Mn()?.accountUuid` — `D6o()`/`g7n()` (@9767xxx) drop cached utilization if `accountUuid` differs from the stored one. So a bearer swap mid-session **invalidates the usage cache and can show the wrong account's limits** (or none).
- **Settings sync**: `/api/claude_code/settings` `ne()` @18431805 (managed settings).
- **Telemetry / metrics**: `/api/claude_code/metrics` (@27278430), `/api/event_logging/v2/batch` (@4476203), `/v1/metrics`, OTLP `…/worker/otlp/…`. Carry OAuth; low-risk but would attribute telemetry to the swapped account.
- **MCP proxy**: `MCP_PROXY_URL=https://mcp-proxy.anthropic.com`, path `/v1/mcp/{server_id}` (@1673116); `/v1/mcp_servers?limit=1000`; `api/organizations/${n}/mcp/start-auth/…`.
- **File upload / download**: `/v1/files`, `/v1/files/{id}/content` — base is `r.baseUrl||Zd()` (@8907368), uses its own `wE()` headers, NOT ANTHROPIC_BASE_URL. `/api/oauth/file_upload`.
- **Team / memory**: `/v1/memory_stores/…?beta=true` (@8139664+), `/v1/code/local/memory/credential`, `/v1/code/memory/…`, `CLAUDE_CODE_MEMORY_API_BASE_URL` override (`rr` list @2239490). Memory credential renewal rejects on 401/429 (@6023403) — a bearer swap can drop org memory.
- **Roles / API-key mint**: `ROLES_URL=…/api/oauth/claude_cli/roles`, `API_KEY_URL=…/api/oauth/claude_cli/create_api_key`.
- **Bridge / remote control / sessions**: `/v1/code/sessions/…` (events, archive, worker, device, remote, move-to-cloud @44900399), `/v1/environments/…`, `/v1/session_ingress/session/…`, `/v1/code/agent-proxy`, `v1/code/auth/refresh`, `v1/code/.well-known/jwks.json`. These use `auth:"teleport-org"` → add `x-organization-uuid` (org-scoped) and a per-account bearer. A mid-session bearer swap to a DIFFERENT org's account would 401/403 these (the org UUID in the URL/path `:orgUUID` wouldn't match).
- **OAuth token refresh**: `TOKEN_URL=https://platform.claude.com/v1/oauth/token` (@3804334), `K_r="/v1/oauth/token"`.

Cross-account leak summary: because the side endpoints bypass the proxy and read the LIVE keychain bearer via `mn()`, the only robust way to move the account for EVERYTHING (not just inference) is to change what `mn()`/`zn().read()` return — i.e. the keychain/credential store the lead already mapped (y$/jhr/$hr/BRs). A base-URL proxy alone moves inference billing but leaves profile/usage/limits/telemetry/bridge on the original account. (load-bearing for the overall design: a proxy is NOT a complete account move.)

---

## (4) How rate-limit response headers and 429 are consumed; whether a proxy retrying a 429 on another account is invisible

The client reads `anthropic-ratelimit-unified-*` on every response (138 header-name occurrences; parsers at @9745700 `dLn()`, @9757586 `unt()`/`_Te()`/`vLn()`). Fields read:
- `-status` (allowed / allowed_warning / rejected), `-reset`, `-representative-claim` (five_hour / seven_day / seven_day_opus / seven_day_sonnet / seven_day_overage_included), `-overage-status`, `-overage-reset`, `-overage-disabled-reason`, `-overage-scope`, `-overage-in-use`, `-fallback`, `-upgrade-paths`, `-{5h,7d,7d_oi,overage}-utilization/-reset/-surpassed-threshold`, grace `-grace-{5h,7d}-utilization`, low-priority `-slow-*`.
- Consumed into a `pTe`/`_nt` state object (`@9766xxx`) that drives the usage UI, "wrap up / grace window" banners (`N6o`), weekly/opus/sonnet limit messages, the `/model` fallback prompt, and the status line. `D6o()` keys the cache on `Mn()?.accountUuid`.

429 handling:
- `Ee()` (@3753010): a response is a rate-limit if `status===429 || message includes "rate_limit_error"`.
- Retryability `@12403350`: `status===429 → return !_t()||Lye()||Fnn(e)`. For a claude.ai subscriber (`_t()` true) that is NOT enterprise, a 429 is generally **NOT auto-retried** unless `Fnn()` (429 with no claim headers and no overage-disabled-reason) — i.e. a bare transient 429 is retried, but a usage-limit 429 (carrying unified claim headers) is surfaced to the user, not retried. On retry the persistent-retry loop (`@12397300`) honors `retry-after` / `anthropic-ratelimit-unified-status==="rejected"` and can wait up to `NKe=21600000ms` (6h) with `onQuotaWindowWait`.
- `retry-after` (gwdoc line 180): integer seconds; a value >60 outside the retry-watchdog stops retries and shows the error immediately.

Is a proxy retrying a 429 on another account invisible to the client? **Partly, with a catch.** If the proxy catches an upstream 429, transparently re-issues the same body to the SECOND account, and returns that account's 200 with ITS `anthropic-ratelimit-unified-*` headers, the client just sees a successful 200 — the retry itself is invisible (the client never saw the 429). BUT:
- The returned unified headers now describe the SECOND account's limits. The client's usage state and the `D6o()` cache are keyed on `Mn()?.accountUuid`, which still reflects the FIRST account (the keychain bearer the client THINKS it's using). The utilization will be stored/compared under the wrong account_uuid and may be discarded (`g7n()` resets cache on uuid mismatch @9767?) — so the usage UI can show stale/blank limits but will not error. (load-bearing: a proxy can mask 429s by account-hopping, but the in-client usage meter will be wrong because account identity is tracked client-side by `Mn().accountUuid`, not by the proxy.)
- If the proxy forwards the first account's 429 unchanged, the client surfaces the limit and (for a subscriber usage-limit) does NOT retry — so the move must happen at the proxy, before the client sees the 429.

---

## (5) TLS pinning / server verification — does a localhost http proxy break it?

- **No cert pin on the first-party inference path.** The default HTTPS agent uses standard `checkServerIdentity` (node `tls` `Mp`/`tC`) over the system+bundled CA set (`wL()`=`X().certificates()` @2078?, `st()` @2078681 honoring `NODE_EXTRA_CA_CERTS` and `CLAUDE_CODE_CERT_STORE`). Fingerprint pinning (`MC()` @4018449, error "gateway TLS certificate does not match the pinned fingerprint") is applied ONLY to a saved **gateway** sign-in via `iye()`, and `iye()` explicitly **skips the pin when an HTTPS proxy is in use** ("per-request cert pin not applied (known gap; list the gateway in NO_PROXY to pin)"). So first-party api.anthropic.com is NOT fingerprint-pinned.
- **A localhost HTTP proxy via `ANTHROPIC_BASE_URL=http://127.0.0.1:PORT` does no TLS at all** — `Ji()` passes the base URL straight to Bun `fetch`; `$c()` (@4490?) only matters for the api-key env-bearer shortcut. HTTP localhost works.
- **`HTTPS_PROXY`/`HTTP_PROXY` honored**: `Ji()` (@2092360) reads `hf()` (proxy URL) and sets `{proxy:{url,headers:{Proxy-Authorization}}}` + `bPt()`; `QS()` (@2093?) installs an axios interceptor and `undici` global dispatcher. Proxy auth helper via `CLAUDE_CODE_ENABLE_PROXY_AUTH_HELPER`. For an HTTPS MITM proxy you must add your CA via `NODE_EXTRA_CA_CERTS` (TOTAL 42 refs) or `CLAUDE_CODE_CERT_STORE`; otherwise `rejectUnauthorized` (default true) fails the TLS handshake to the proxy's forged cert. Client cert to upstream via `CLAUDE_CODE_CLIENT_CERT`/`_KEY` (mTLS, `Z()` @7789832).
- SSRF guard `JO.connect` (@30065924) blocks loopback/metadata hosts for the HttpsProxyAgent path with `ol()` on — but that is for the gateway-host-check / proxy agent, not for `ANTHROPIC_BASE_URL` inference. The plain `ANTHROPIC_BASE_URL=http://127.0.0.1` fetch path is not SSRF-blocked.

Conclusion: **a localhost proxy does NOT hit a TLS pin on the subscription inference path.** Either ANTHROPIC_BASE_URL=http://localhost (no TLS) or HTTPS_PROXY + NODE_EXTRA_CA_CERTS works.

---

## Bottom line for the mid-turn account-move design

- A local proxy at `ANTHROPIC_BASE_URL` CAN see the live OAuth bearer on `/v1/messages` and swap the `Authorization: Bearer` header per request to bill a different Max account — no TLS pin blocks it. This is a viable per-request billing-account switch for INFERENCE, and it needs no `/exit`, no resume, no transcript fork.
- Costs/constraints the design must handle: (a) `_CLAUDE_CODE_ASSUME_FIRST_PARTY_BASE_URL=1` needed to keep first-party UX, but that re-enables the `cch` attestation whose body-hash the proxy must not invalidate (prefer header-only swap + `CLAUDE_CODE_ATTRIBUTION_HEADER=0`); (b) `anthropic-beta: oauth-2025-04-20` must be preserved or requests 401; (c) `metadata.user_id.account_uuid` in the body still names the client's believed account — a bearer-only swap creates a body/bearer account mismatch; (d) all non-inference endpoints (profile, usage, limits, telemetry, bridge, memory, files) bypass the proxy and use the live keychain bearer via `mn()`, so the proxy is NOT a complete account move — usage meters, limits, and org-scoped session/bridge calls stay on the original account and can 401/403 or show wrong data; (e) a proxy can mask a 429 by retrying on another account invisibly, but the client's usage state (keyed on `Mn().accountUuid`) will be wrong.
- The only way to move EVERYTHING (not just inference billing) remains changing what the credential store returns (`mn()`/`zn().read()` + the y$/$hr/BRs adoption paths the lead already mapped), which a proxy cannot substitute for.
