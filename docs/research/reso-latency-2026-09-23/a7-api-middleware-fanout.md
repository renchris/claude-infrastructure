# A7: API routes, middleware, limiters, notification fan-out: latency census

Repo: reso at `origin/main` b2eea41b3 (read-only worktree `reso-latency-ro`). Scope: `middleware.ts`, every
`src/app/api/**` route except replicache-pull/push, `lib/rate-limit/*`, `lib/messaging/*`, poke and web-push
fan-out, and the sweepers. The pull and push routes are touched only where a limiter or fan-out helper runs
inside them.

**The same mechanism causes most of these findings.** In a Route Handler, `cache()` passes straight
through on Next 16.3 (`drizzle/db.ts:269-293`, `src/app/api/replicache-push/route.ts:226-231`;
`package.json` pins next 16.3.5). So every `getDB()` call re-enters `getServerActionSession()`
(`drizzle/db.ts:205` → `tenantContext.ts` → `cookieActions.ts:23-27` → `lib/auth/session.ts:161-185`) and
does one of two things:
- For an **authenticated** caller, it issues the `credentials_version` revocation SELECT a second time.
- For an **unauthenticated** caller (no tenant in the sealed session), it falls through to an **uncached
  Turso Platform API call** (`tenantContext.ts:76-90`).

The helpers in this axis call bare `getDB()` in several places: the durable limiter, the push-prune helper,
the subscribe and unsubscribe routes, and the login helpers.

## Findings (ranked by latency saved × path frequency)

| id | where | path / heat | sequential trips now → after | change | confidence |
|---|---|---|---|---|---|
| A7-01 | `src/components/LandingPageOrLoggedInApp.tsx:70-139`, `lib/warm-cache.ts`, `lib/cache/dynamodb-store.ts:29-60` | **every authenticated (app) layout render** (hard loads, and soft navs that re-run the layout) | A DynamoDB GetItem (≤50 ms budget) gates 4 of the 6 fan-out members → 0 | skip the probe when `sessionMeta.loginTimestamp` is older than ~30 s (a hit is impossible after that) | 80% |
| A7-02 | `lib/rate-limit/durable-limiter.ts:143-147` (`getDB()` in the check); hottest caller `replicache-push/route.ts:136-167` | **every push**; also latency-ping, warm, sendTestNotification | push pre-work: revocation → (revocation again + UPSERT) = 3 → 1 | the limiter resolves its DB from the sealed tenant, or takes `{db}`; the push route runs the limiter alongside the revocation check and `request.json()` | 90% |
| A7-03 | `src/app/api/sync-watermark/route.ts:31-49`, `lib/sync-cursor.ts:62-77` | every tab, every 60 s, plus on arm | 2 phases / 3 HTTP requests → 1 request | one `db.batch([revocation, max(lc), oob])`, or the revocation run in parallel with a batched watermark read | 85% |
| A7-04 | `src/app/actions/auth/tenantContext.ts:52-108`, `sessionWrite.ts:47-80`, `lib/auth/login.ts:217-224,280-291`, `passkey-login/route.ts:64-93` | **every login** (options + finalize), register, username-check, invite-token | 4-5 **Platform API** calls in series per finalize (+2-3 per options) → ≤1 per container per TTL | a process-level memo of `subdomain→group` (TTL plus in-flight dedupe), shared by `getSubdomainAndGroup` and `fetchTenantInfo`; optional registry-first like the sweeper | 85% (counts) / latency per call unmeasured |
| A7-05 | `lib/auth/session.ts:161-185` | **every authenticated API request** (pull, push, watermark, logs, actions) | 1 revocation trip per request → 0 when warm | an in-process short-TTL memo of `user.id → credentials_version`, invalidated locally by deleteCredential/deleteUser. **Needs an operator ruling** (a revocation delay of ≤TTL across containers) | 90% savings / ruling open |
| A7-06 | `src/app/api/logs/route.ts:569-570` | every authenticated RUM/sync/cwv beacon (≥2/min per active tab; sync-logger flushes every 10 events) | 1 → 0 | unseal-only session for the trust decision; full validation only if the body carries an auth-only namespace | 90% |
| A7-07 | `src/app/actions/replicache/notificationDispatch.ts:212-458` | every approval-creating or approval-resolving push (after() on Amplify; the Fly sweeper on retries) | claim 3 → 1; per row ~7 DB phases → 3 | a single-statement claim (`UPDATE … WHERE id IN (SELECT … LIMIT n) AND status='pending' RETURNING *`); one `db.batch` for event/list/actor/recipients/counts/subs; delivery insert and markSent in one batch | 75% |
| A7-08 | `src/app/actions/notifications/pushTransport.ts:112-119,175-178` | every 410/404 prune during a drain | in after(): +1 revocation trip; **in the Fly sweeper it throws** → the row is re-queued and re-sent to every live recipient | pass `db` into `sendToSubscriptions` (like `DurableCheckOptions.db`) | 80% |
| A7-09 | `src/app/actions/auth/sessionWrite.ts:86-150,166-176` | every login and registration | a new libsql client (cold TCP+TLS) plus `SELECT *` → a pooled `getNamedDB` and `select({name})`, started alongside the credential read | pooled handle, narrow select, overlapped | 80% |
| A7-10 | `src/app/api/warm/route.ts:34-61` | every login (fired by `execTightGesture` after auth) | revocation → revocation + UPSERT → 5 members, each re-running revocation → session tenant threaded through, limiter `{db}` | thread `getNamedDB(session.tenant)` through; the members take a db/tenant argument | 75% |
| A7-11 | `src/app/api/logout/route.ts:27-28` | every logout | 1 revocation trip before `destroy()` → 0 | an unvalidated unseal is enough to destroy | 90% |
| A7-12 | `src/app/api/notifications/subscribe/route.ts:34,136-173`, `unsubscribe/route.ts:106` | service-worker `pushsubscriptionchange` (rare, background) | subscribe: revocation + revocation again + (delete) + select + insert + cap = 5-6 → 2 | `getNamedDB(session.tenant)`; delete, insert and cap in one `db.batch` | 70% |
| A7-13 | `src/instrumentation.ts:189-230`, `lib/alerts/lead-alert-outbox.ts:282-299,441-444`, `lib/messaging/guest-message-outbox.ts:530-541` | Fly sweeper, every 30 s, per tenant (background); guest drain on every push **once W3 lands** | 3 empty-queue SELECTs in series per tenant → 1 batch; latent guest claim of 4 trips → 1 | batch the empty-probe reads; the same single-statement claim as A7-07 | 70% |
| A7-14 | `src/app/api/latency-ping/route.ts:72-117` | RUM, every 5 min × 2-3 endpoints | limiter re-entry (as A7-02); the ping builds a **fresh** client, so it measures TCP+TLS, not the query | covered by A7-02; decide whether the ping should measure a warm, pooled connection | 70% |

---

## A7-01: the warm-cache DynamoDB probe gates the fan-out on every authenticated render

- **Evidence.**
  - `getWarmed` (`lib/warm-cache.ts`) checks a per-process Map, then `dynamoGet`: a 50 ms timeout with
    `maxAttempts: 1` (`dynamodb-store.ts:29-60`).
  - The layout says the probe was "~50ms of the (app) layout's ~60ms"
    (`LandingPageOrLoggedInApp.tsx:73-81`). After e07f5bf88 it still gates `[tenant, getRUMConfig,
    resolveActiveVenueID]`, `getTonightEntriesSeed` and `getInitialVenues`, which all chain off
    `warmedPromise` (lines 124-138).
- **Why the probe almost always misses.**
  - `setWarmed` is reachable only from `/api/warm`, which is fired only by `execTightGesture` after
    login/register (`lib/fireBeamRushFade.ts:137`) and by the dev-only `DevLoginButton`.
  - The entry's TTL is 10 s from `storedAt` (`warm-cache.ts` `TTL_MS`).
  - So after about 10 s past login, **every** authenticated render pays the probe for a guaranteed miss. On
    Fly (dfw/iad/lax/sin), DynamoDB `us-west-2` sits across the continent or the Pacific, so the 50 ms
    budget is the likely outcome.
- **Change.** The sealed session already carries `sessionMeta.loginTimestamp`, which the sliding refresh
  never moves (`session.ts:99-107,194-203`).
  - If `Date.now() - loginTimestamp > 30_000`, set `warmedPromise = Promise.resolve(null)`.
  - 30 s is generous: `storedAt` is at most the warm route's duration past `loginTimestamp`, and the entry
    lives 10 s.
  - No DB, no network, and the payload is unchanged.
- **Saves.** Up to ~50 ms of critical path on every authenticated render after the first ~30 s, on every
  region. Amplify-in-region is smaller but still nonzero.
- **Risk.** None to auth or tenancy (a read-only cache skip). A render within 30 s still probes, so the
  login concealed-load is unchanged.
- **Test that fails today.** Render the layout helper with a session whose `loginTimestamp = now - 60s`,
  with `@lib/cache/dynamodb-store` mocked and counting `dynamoGet`. Assert 0 calls. Today it is 1.
- **Cross-axis.** The code lives in the (app) layout. The (app)-layout/RSC axis owner may report the same
  item; this axis found it through `/api/warm`.

## A7-02: the durable limiter re-enters the session through `getDB()`, and the push limiter runs in series

- **Evidence.**
  - `createDurableLimiter().check` does `opts?.db ?? await getDB()` inside the 50 ms timed thunk
    (`durable-limiter.ts:143-147`). In a route handler, `getDB()` re-runs the revocation SELECT (see the
    mechanism above).
  - The push route: `getServerActionSession()` (revocation #1, `route.ts:136`) → `checkPushRateLimitDurable(userID)`
    (revocation #2, then the UPSERT, `route.ts:167`) → `request.json()` → `getDBAndGroupForSessionTenant`
    (`route.ts:223`).
  - So **3 sequential Turso trips run before the push reads its body**. The push route already deleted the
    same duplicate for its own handle (`route.ts:224-231`), but the limiter re-introduces it.
  - The duplicate also sits inside the limiter's 50 ms fail-open budget. Two trips instead of one widen the
    window in which the push limiter goes dark, and each trip is a "lottery ticket on the ~1 s stall"
    (`drizzle/db.ts:279-281`).
- **Change (layered).**
  1. In the limiter, when `opts.db` is absent, resolve the tenant from an **unseal-only** read of the sealed
     session (`getSessionCached`, no revocation). If there is no sealed tenant, use the host-derived
     resolution memoized per A7-04. Revocation is irrelevant to choosing which tenant DB holds a counter.
  2. In the push route, `const db = await getNamedDB(session.tenant…)` first (no network), then
     `Promise.all([checkPushRateLimitDurable(userID, { db }), request.json()])`. This overlaps the UPSERT
     with receiving the body, which matters on slow venue Wi-Fi for multi-mutation batches.
  3. Optional, for the push-axis owner: start the limiter UPSERT **in parallel with** the revocation
     SELECT. Both need only the sealed `user.username` and tenant. A revoked session's push still bumps its
     own bucket (harmless) and is refused on the revocation verdict. Or send both in one `db.batch` (one
     HTTP POST, which matters on h1: see A7-03).
- **Saves.** One trip per push (steps 1-2), two with step 3. Plus one per latency-ping, warm and
  sendTestNotification check.
- **Risk.** The gate order is unchanged: the 429 still precedes any write, and fail-open semantics are
  unchanged. Tenant isolation holds because the counter DB comes from the HMAC-sealed tenant.
- **Test that fails today.** Mock `drizzle/db` `getNamedDB` to return a DB stub that records SQL text, and
  mock iron-session with a valid user and tenant. POST the push route with 1 mutation, then count
  statements matching `credentials_version`. Assert 1; today it is 2.
- **Also latent.** `peekDurableLimit` (`durable-limiter.ts:215-233`) has **no** `db` option, and the pull
  commit limiter runs in after(). Both re-enter the session. They are flag-gated off
  (`REPLICACHE_PULL_LIMITER_DURABLE`), so fix them before enabling.

## A7-03: `/api/sync-watermark` takes two phases and three requests where one will do

- **Evidence.** `getServerActionSession()` (revocation) is awaited, then `readSyncWatermarkNoTx` runs two
  SELECTs via `Promise.all` (`sync-cursor.ts:65-72`). The route's docstring says "single round trip on the
  cheap path". It is two sequential phases.
  - Node fetch plus `allowH2: false` (`lib/db/turso-keepalive.ts:11-14,110`) means the two concurrent
    SELECTs need **two sockets**. A single warm pooled socket forces a new TCP+TLS for the second one.
- **Change.**
  - Add `readSyncWatermarkBatch(db)` = `db.batch([max(mutation_log.id), sync_cursor.seq])`. `db.batch`
    already has precedent in `lib/floor-plan/assembleConfig.ts:122` and `floor-plan/initialData.ts:348`.
  - Either run it in `Promise.all` with the session validation, using the tenant from the sealed session and
    returning 401 before responding if `!user`, or fold the revocation statement into the same batch
    (requires exporting the revocation statement and verdict from `session.ts`).
- **Saves.** One sequential trip plus 1-2 HTTP requests per probe, per tab per minute. It is not directly
  user-visible (the interval bounds detection), but it is the highest-volume authenticated read in this
  axis, so the savings in Turso requests and stall exposure are large.
- **Risk.** Critical Rule 5 (`CLAUDE.md:96`) stays satisfied, because the session is still validated
  before any response. On the parallel variant, a revoked caller's watermark is read and discarded, and it
  leaks nothing. Monotonic-read reasoning (`sync-cursor.ts:98-123`) is unaffected, and batch atomicity only
  strengthens it.
- **Test that fails today.** A stub client counting `execute` and `batch` calls. Assert exactly 1 network
  call for an authenticated GET; today it is 3 (1 revocation + 2 SELECTs).

## A7-04: the unauthenticated login path resolves the tenant through the uncached Platform API, 4-5 times per login

- **Evidence.** When the session carries no tenant (every pre-login request),
  `getSubdomainAndGroup` does `platformDB.databases.get(`${subdomain}-database`)` over HTTPS to the Turso
  control plane on every call (`tenantContext.ts:76-90`, 5 s timeout). Nothing memoizes it.
  `fetchTenantInfo` (`sessionWrite.ts:47-80`) is a second, separately inlined copy that builds a fresh
  platform client per call.
- **Count for the email-free `POST /api/passkey-login` (route handler, so `cache()` passes through).**
  1. Limiter → `getDB()` → Platform API, **raced against 50 ms**.
  2. `getDB()` for the flag (`route.ts:91`) → Platform API.
  3. `finalizeAssertion` → `getSubdomainAndGroup()` (`login.ts:280`) → Platform API.
  4. `getDB()` (`login.ts:291`) → Platform API.
  5. `authenticatedUserToCookieStorage` → `fetchTenantInfo` → Platform API.
- **Count for the options action.** `getDiscoverableAuthenticationOptionsJSON`, which auto-fires on every
  `/login` mount, pays limiter → Platform API and `getDB()` → Platform API (`login.ts:217,223`). Its own
  comment at `login.ts:209-212` calls exactly this "unacceptable on an action that auto-fires on every
  /login mount", yet the two calls below the comment incur it.
- **The limiters are dark on these routes.** A cross-internet control-plane HTTPS call plus the UPSERT
  inside a **50 ms** budget will usually time out and fail **open**. So `checkPasskeyLoginLimit`,
  `checkRegisterLimit`, `checkDiscoverableOptionsLimit`, `checkUsernameAvailabilityLimit` and
  `checkInviteTokenLimit` likely enforce nothing while adding up to 50 ms each. Confidence 70%: this
  depends on the Platform API RTT, which nobody has measured.
- **Change.**
  - Add a module-level `Map<subdomain, {group, expiresAt, inflight?: Promise}>` inside
    `getSubdomainAndGroup`'s Platform-API arm, with a TTL of about 5-10 min.
  - Route `fetchTenantInfo` through it (or through a shared `resolveGroupForSubdomain`).
  - Optional first tier: `LOCATIONS[getTenant(sub).location].tursoGroup`. Production already routes the
    Fly sweeper by the registry (`src/instrumentation.ts:162`). Keep the Platform API as the fallback,
    because the docs say the serving plane deliberately does not depend on the manifest.
- **Saves.** 3-4 control-plane calls in series per login finalize and 1-2 per options fetch, after the
  first call on a warm container.
- **Measure first.** The existing `tenant_resolution_complete` auth-flow event records `durationMs`
  (`tenantContext.ts:93-98`). A Logs Insights p50/p99 of it gives the per-call cost.
- **Risk.** A group move (`DATABASE_REGION_SETUP.md:570-575`) takes ≤TTL to be seen. Logged-in sessions
  already cache the group for 12 h, so this is strictly fresher than the status quo. Tenant isolation holds
  because the key is the host subdomain, exactly as today.
- **Test that fails today.** Mock `@lib/auth/platform-db` so that `databases.get` counts calls. POST
  `/api/passkey-login` (email-free) twice with no session tenant, then assert ≤1 call in total. Today it is
  ≥8.

## A7-05: memoize the revocation verdict (systemic; needs an operator ruling)

- Every authenticated API request pays one `SELECT credentials_version FROM user WHERE id=?`
  (`session.ts:167-171`). That includes pull, push, watermark, logs and every server action.
- A per-process memo `Map<userId, {version, fetchedAt}>` with a TTL of about 15-30 s, invalidated locally
  inside `deleteCredential`/`deleteUser`, removes that trip on warm Fly processes and warm Lambda
  containers.
- The trade-off is that a revoke on container A reaches container B in ≤TTL instead of instantly. This was
  an operator-ratified control (Wave 1, 2026-08-19), so **do not ship without a ruling**.
- A fail-closed variant: memoize only "row present and version equal", never "absent".
- A7-02, A7-03, A7-06, A7-10 and A7-11 each remove *duplicate or unneeded* checks. This finding removes the
  one remaining check per request.

## A7-06: `/api/logs` validates revocation on every authenticated beacon

- `route.ts:569` runs `getServerActionSession()` only to choose between trusted pass-through and the
  sanitized, allowlisted unauth path.
- Beacons: rum-logger and sync-logger flush every 30 s or every 10 events (`lib/rum/rum-logger.ts:19-20`,
  `sync-logger.ts:26-27`), plus nav-trace and cwv.
- **Change.** Unseal only. Treat `Boolean(user)` as authenticated for the rum-latency, cwv, storage-quota
  and auth-nav namespaces, and run the full validation (1 trip) only when the body carries
  `error-tracking`, `sync-latency` or `auth-flow`.
- **Risk.** A revoked-but-unexpired cookie keeps the unsanitized path for unauth-allowed namespaces for
  ≤12 h (log-injection surface only). Name it and let security decide. The fallback is A7-05.
- **Test that fails today.** POST a `cwv`-only batch with a valid sealed session, then count revocation
  statements. Assert 0; today it is 1.

## A7-07: the notification drain (approval pushes) waits on a chain of trips before the Web Push POST

- **Claim.** `select ids` → `update … lockedBy` → `re-select` is 3 sequential trips (`notificationDispatch.ts:221-243`).
  SQLite/libsql supports `UPDATE … RETURNING`, so one statement does an atomic CAS claim:
  `UPDATE notification_outbox SET status='processing', locked_by=?, locked_at=? WHERE status='pending' AND id IN (SELECT id … LIMIT n) RETURNING *`.
- **Per row today.**
  1. `[event, list, actor]` (parallel)
  2. recipients (`getApproverUserIDs`, plus adders for resolved)
  3. `[pendingCount, badgeCount]`
  4. subs
  5. budget UPSERT
  6. send
  7. delivery insert
  8. markSent

  That is ~7 DB phases, all but the send in series.
- **After.**
  - One `db.batch` covers event, list, actor, recipients as a subquery, both counts, and subs joined on the
    recipient subquery. The row fields (`listID`, `itemIDs`, `creatorUserID`) are all known up front.
  - Then the budget UPSERT (it must stay a separate gate before send).
  - Then send.
  - Then one batch for the delivery insert plus markSent/backoff.
  - About 3 phases.
- **Saves.** About 5-7 sequential trips (≈100-250 ms at tens of ms each) before a door-staff approval push
  leaves the server. On Amplify this runs inside the push invocation's after(), so it also shortens how
  long the container stays busy.
- **Risk.** The claim stays a single-winner CAS (the LAX+SIN double-sweep safety at lines 199-205 is
  preserved). The delivery insert currently has its own try/catch so an audit failure never re-sends, so
  keep the markSent write independent of the insert: two statements in a batch fail together, so either
  keep them sequential or accept the batch semantics explicitly.
- **Test that fails today.** Use an in-memory libsql DB with 1 pending row, 1 approver and 1 subscription,
  with `webpush.sendNotification` stubbed. Count DB requests before the first `sendNotification` call.
  Assert ≤3; today it is ≥8.

## A7-08: the push-prune helper resolves the DB through the request, and it throws in the sweeper

- **Evidence.** `deleteSubscriptionByEndpoint` calls `getDB()` (`pushTransport.ts:112-113`). In the Fly
  sweeper (`src/instrumentation.ts` setInterval) there is no request scope. `getDB` → `getSubdomainAndGroup`
  → `getServerActionSession` → `cookies()` throws. The limiter's own comment warns about exactly this
  (`durable-limiter.ts:39-43`).
- **What follows the throw.**
  - It fires inside the `catch` at `pushTransport.ts:175-178`, so that task **rejects**, and the
    `allSettled` counts it as `failed`.
  - `drainNotificationOutbox` then `applyBackoff`s the row (`notificationDispatch.ts:432-434`).
  - The **whole row is re-sent to every live subscriber** on each retry, and the dead endpoint 410s again,
    until MAX_ATTEMPTS.
  - Topic and tag replacement hides some of this on devices, but it still costs repeated sends and delivery
    rows.
- **On the after() path.** Inside the route scope it works, but it pays an extra revocation trip.
- **Change.** Add `opts.db` to `sendToSubscriptions`, pass it from `drainNotificationOutbox` and
  `notifyCredentialAdded`, and delete by endpoint on that handle.
- **Why tests miss it.** `notificationDispatch.test.ts:370` mocks `getDB()`, so no test covers the
  no-request-scope case.
- **Test that fails today.** Make `getDB` throw (simulating no request scope), stub `sendNotification` to
  reject with `{statusCode: 410}`, and run `drainNotificationOutbox(db, t)`. Assert the row is `sent` and
  the subscription is deleted. Today it is re-queued `pending`.

## A7-09: the login org-name read opens a cold client and selects every column

- `fetchOrganizationName` does `createDbClient({url, authToken})` per call (a new TCP+TLS to Turso), then
  `select()` of the whole `organization` row, and only reads `.name` (`sessionWrite.ts:86-150`).
- It runs after the WebAuthn verify, in series.
- **Change.** A dynamic `import('drizzle/db')` → `getNamedDB(subdomain, group)`, the same cycle-break
  pattern as `session.ts:164`. Select `{ name }`.
  - The tenant is known before verification, so start the org read in parallel with `finalizeAssertion`
    and await it at cookie write. Discard it on failure.
- **Saves.** A TLS handshake (1-2 Turso RTTs) plus one sequential trip per login and registration.
- **Test that fails today.** Spy on `@libsql/client` `createClient`. Assert it is not called by
  `authenticatedUserToCookieStorage`; today it is called once.

## A7-10: `/api/warm` makes serial and duplicate revocation reads

- `getUser()` does revocation → `checkWarmLimit` does revocation + UPSERT → `Promise.allSettled` of 5
  helpers, of which `getTenantFromSession`, `resolveActiveVenueID`, `getInitialVenues` and
  `getTonightEntriesSeed` each re-enter the session (route-handler pass-through).
- It is fired once per login, behind a 1500 ms animation floor (`fireBeamRushFade.ts:137,175`), so it is
  mostly off the critical path. But a slow warm is a missed warm, which then pays the full cold fan-out at
  the destination.
- **Change.** Use `getNamedDB(session.tenant)` once, pass `{db}` to the limiter, and give the four members a
  tenant/db parameter. Combine this with A7-01. With the probe skipped after 30 s, the warm path is only
  consulted when it can hit.
- **Test that fails today.** Count revocation statements for one `POST /api/warm`. Assert 1; today it is
  ≥5.

## A7-11 to A7-14 (low heat)

- **A7-11, logout.** `getServerActionSession()` → `destroy()` validates revocation before destroying a
  cookie. Use the unvalidated unseal instead. Saves 1 trip on the logout gesture (the T=700 ms hard-nav
  path, `logout/route.ts:9-24`).
- **A7-12, subscribe/unsubscribe.**
  - Both call `getDB()` after `getSession()`, which duplicates the revocation read.
  - Subscribe then runs delete-old, select, insert and cap (`push-subscription-policy.ts:98-118`) in series.
  - `endpoint` is UNIQUE (`drizzle/schema.ts:312`), so the ownership check can be an `INSERT … ON CONFLICT
    (endpoint) DO NOTHING RETURNING` plus a conditional owner read, batched with the cap delete.
  - The only callers are the service worker's `pushsubscriptionchange` (`public/sw.js:197,221`), so the
    route is not user-visible. Take the `getNamedDB(session.tenant)` part and leave the batching optional.
- **A7-13, sweepers.**
  - Per tenant every 30 s (Fly only), the empty-queue path is 3 SELECTs in series: notification candidates,
    the lead-alert reap SELECT, and lead-alert candidates. One `db.batch` can do it.
  - The guest-message drain is inert today: `resolveGuestMessageSender()` returns null and
    `drainGuestMessages` short-circuits before any read (`guest-message-outbox.ts:511-517`). The push-route
    comment claiming "one indexed read" per push (`route.ts:386-387`) is therefore stale.
  - When W3 lands, every push will pay reap, select, update and re-select after the response. Use the
    single-statement claim from A7-07.
- **A7-14, latency-ping.** Besides the limiter re-entry (A7-02), the ping builds a fresh `createClient` per
  request (`route.ts:113-120`). `serverLatencyMs` therefore includes TCP+TLS setup, not the pooled-query
  latency the app actually sees. That is a measurement-validity note: decide which number RUM wants.

## Rejected candidates (do not redo)

| candidate | why rejected |
|---|---|
| `middleware.ts` has DB or network work | None. It only builds a nonce and CSP string (`lib/csp.ts:77-101`, microseconds). `api`, prefetch and static paths are excluded from the matcher. Skipping RSC requests too would save microseconds and risk the `x-pathname` contract. |
| `sendPoke` is slow | Pusher clients are cached per group and slot, keep-alive agents are in use, one `trigger` covers a ≤100-channel array, and it is already deferred via `runAfterResponse` (`route.ts:356`). Prior work f5a6de682 covered the publish step. |
| Moving the push durable limiter into after() | It is a gate; deferring it would make it advisory. A7-02 instead overlaps it with other work. |
| Reverting the push limiter to an in-memory Map | That was a no-op on Lambda (`durable-limiter.ts:4-6`, `CLAUDE.md:329-331`). |
| `create-custom-pusher.ts` redundant hops | One fetch per push, and the 429→503 remap is client-local. |
| Credential-change notifier's inline 3 s race (`credential-change-notifier.ts:36-50`) | Deliberate: after() is unsupported on Amplify and this is a security signal. Rare path. Only the `getDB()` re-entry is trimmable (fold it into A7-08's `db` plumbing). |
| Inline lead alert in `consumeInvitationAndRegister` (`databaseActions.ts:1693-1757`) | Deliberate and bounded (3 s, measured at 200-270 ms), on a rare path. |
| `/api/csp-report` and the unauthenticated `/api/logs` limiter | In-memory limiters, no DB. |
| `/api/health`, `/api/debug/vapid` | No DB beyond the admin session check (vapid). |
| "`/api/warm` is dead in production" (a first-pass hypothesis) | **False**: `execTightGesture` fires it after every passkey login and registration (`lib/fireBeamRushFade.ts:137`, `formActions.ts:151,237`). A7-01 and A7-10 are scoped accordingly. |
| Guest-message drain costs a read per push today | False today (null sender short-circuits). Latent only (A7-13). |

## Uncertainties and blockers

- **`cache()` pass-through inside server actions** (`login.ts` options and the invite actions) is asserted
  by `session.ts:111-114` but I did not verify it independently. If server actions *do* dedupe, the
  options-path counts in A7-04 drop by one call each. Route-handler pass-through is repo-verified
  (`drizzle/db.ts:275`).
- **Platform API and DynamoDB latency from each Fly region is unmeasured.** A7-01 and A7-04 give upper
  bounds plus an existing instrument (`warm_cache` `durationMs`, `tenant_resolution_complete`
  `durationMs`). Run those Logs Insights queries before ranking A7-04 above A7-02.
- **A7-05 and A7-06 are security trade-offs**, not pure performance. They are listed so the operator can
  rule on them, not for unilateral landing.
- **Owner overlap.** A7-02 step 3 is inside the push route, and A7-01 is in the (app) layout. Coordinate
  with those axes' owners.
