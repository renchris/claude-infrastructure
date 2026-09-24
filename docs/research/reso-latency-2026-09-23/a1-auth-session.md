# A1: per-request auth, session and tenant path: DB round-trip census

Repo `reso` @ `b2eea41b3`, read-only. Axis: `lib/auth/session.ts`, `cookieActions.ts`, `accessActions.ts`,
`tenantContext.ts`, `drizzle/db.ts`, `roleHelpers.ts`, `venue-authz.ts`, `middleware.ts`, and every caller
that re-reads the `user` row.

## 0. The fact the rest of this report depends on

**`React.cache()` does not dedupe inside a Server Action or a Route Handler on Next 16.3 / React 19.3.**
Verified in the installed framework (`next@16.3.0`, `node_modules/next`):
- `dist/server/app-render/action-handler.js:987`: the action runs as
  `workUnitAsyncStorage.run(requestStore, () => action.apply(null, args))`. No Flight request is active.
- `dist/compiled/react-server-dom-webpack/cjs/react-server-dom-webpack-server.node.development.js:6233-6238`:
  `getCacheForType` does `(cache = resolveRequest()) ? cache.cache : new Map()`. With no request, every call
  gets a **new Map**, so every `cache()`-wrapped function runs again.
- The repo already knows this for Route Handlers (`drizzle/db.ts:274-283`, `replicache-pull/route.ts:230`).
  `session.ts:113-115` says it for actions too. What nobody has costed is the consequence below.

**Consequence.** Outside an RSC render, each `getServerActionSession()` call is a fresh unseal plus a fresh
`SELECT credentials_version FROM user WHERE id=?` (`session.ts:162-188`). Each `getDB()` makes the same call
again through `getConnectionParams` → `getSubdomainAndGroup` → `getTenantFromSession` → `getServerActionSession`
(`db.ts:195-213`, `tenantContext.ts:69`, `cookieActions.ts:23-27`). That path runs only in production
(`db.ts:205`), so dev cannot show it.

## 1. Findings (ranked by latency saved × path frequency)

RT = one sequential Turso round trip (p50 is tens of ms; a cold socket costs 52-262 ms, per
`docs/infra-deploy/learnings.md:2270-2275`; p95 stalls reach about 1 s, per `db.ts:281-283`).

| id | where | path · frequency | serial RTs now → after | change | risk | conf |
|---|---|---|---|---|---|---|
| **A1-1** | `cookieActions.ts:23-27` (`getTenantFromSession`) | every `getDB()` in every server action and route handler that does not use `getDBAndGroupForSessionTenant` | +1 revocation SELECT per `getDB()` → **0** | read `.tenant` from the **unvalidated** unseal (`getSessionCached`), not the validated session | **none; the result is byte-identical**: validation only clears `.user` (`session.ts:177,181`), never `.tenant` | 95% |
| **A1-2** | `session.ts:116-190` | every server action / route handler that reads the session more than once (most do, see §3) | N revocation SELECTs → **1** per request | per-request memo keyed on the `await cookies()` object (WeakMap), with `cache()` kept for RSC | cross-request leak if keyed wrong; see §2 invariants | 90% |
| **A1-3** (operator-ordered) | `accessActions.ts:41-56` → `authQueries.ts:56-70` | every admin gate: 11 gates in `databaseActions.ts`, plus `tenantConfigActions.ts:33`, `venueRoleActions.ts:45`, `lambdaActions.ts:239`, `listsSeedActions.ts:22-29` | admin action: 4-5 serial same-row reads → **1** | fold `role` (+ promoterID, firstName) into the revocation SELECT; `hasAdminAccess` reads the folded role | admin fail-closed on read error must be kept (tri-state, §2) | 90% |
| **A1-4** | `replicache-pull/route.ts:59` + `pullActions.ts:858` → `authContext.ts:260-275` | **every pull** (60 s interval + every poke) | 2 serial levels on the same row (revocation by id, then the user⋈promoter read by username) → **1** | put `id, credentialsVersion` into the prefetch's user SELECT; the route checks them with the shared predicate; warmth pulls keep today's check | a revoked or deleted user must still get **401**, not 500 | 85% |
| **A1-5** | `replicache-push/route.ts:137,167` → `durable-limiter.ts:145` | **every push** | revocation (L1) → limiter [duplicate revocation + UPSERT, inside a 50 ms timeout] (L2) → prefetch (L3): **3 → 1** level | pass `{ db }` to `checkPushRateLimitDurable`; run limiter ∥ prefetch; fold `credentialsVersion` into `batchPrefetch.ts:694-701` | limiter must still be able to 429 before the write tx; see note | 85% |
| **A1-6** | `LandingPageOrLoggedInApp.tsx:46` → `homeStateActions.ts:151-153` → `authContext.ts:155-172` | **every authed page load** (layout) | tonight-seed leg: revocation (L1) → user⋈promoter (L2) → lists∥venue (L3) → **L1 → L2** | `prefetchAuthContext(db, username, preRead?)` takes the folded row from A1-3 | seed scope must still mirror the pull (F4) | 80% |
| **A1-7** | `durable-limiter.ts:129-187` + `tenantContext.ts:77-91` | **pre-session** requests (`/login` mount, login finalize, register, invite, username check) | limiter = Platform API (cross-internet) + UPSERT inside **50 ms** → almost always **times out and fails open** | resolve the group from the static manifest (`lib/config/tenants.ts` tenant→location→`tursoGroup`); Platform API only for off-manifest hosts; memo per request | **security, not only latency**: the S-4 login limiters are probably dark in prod today | 75% |
| **A1-8** | `login.ts:163,166,174` / `sessionWrite.ts:48,134,176-178` | each login (options + finalize) | about 4-5 sequential Platform API calls + a **fresh libsql client/TLS per login** (+1 on retry) → 0 Platform API calls, pooled client | same manifest resolution as A1-7; `fetchOrganizationName` → `getNamedDB` (pooled, label-validated) | a wrong manifest group is a loud auth failure, never a cross-tenant read (§4) | 80% |
| **A1-9** | `sync-watermark/route.ts:31,49` | every interval check (per client, about 60 s) | revocation → watermark: **2 → 1** level | unseal, then `Promise.all([validated, readSyncWatermarkNoTx])`; return only if validated | none. Do **not** `db.batch` it: that changes the fail-open polarity | 85% |
| **A1-10** | `session.ts:205-213` (`slideSessionIfStale`) | every active client, ≤ 1/min (`create-replicache-context.tsx:437-440`) | 1 revocation SELECT per call; 29 of 30 calls are no-ops → **0** when not due | check `shouldSlideSession` on the unvalidated unseal first; validate only when a save will happen | none. Save still requires a validated user | 90% |
| **A1-11** | `navWarmActions.ts:31-37` (`getFloorPlanWarmTarget`, called by all roles from `MobileNavBar`) | per cold nav-target refresh | 4 serial revocation SELECTs (`:32`, `venue-resolution.ts:232`, `:75-76`, `getDB` in `getDefaultEventID`) → **1** | A1-1 + A1-2 remove it, no call-site change | none | 90% |
| **A1-12** | `admin/(settings)/team/page.tsx:30-33` | admin Team page view | L2 = 2× `getUserFromID` (not cached) before users/invitations → **gone** | A1-3 | none | 90% |
| **A1-13** | `databaseActions.ts:447-545` (`deleteCredential`) | device removal (rare) | 7 serial (3 auth + read + DELETE + UPDATE + read) → 2 | A1-1/2, then `db.batch([DELETE…RETURNING, UPDATE … WHERE changes()>0, SELECT remaining])`; read the target only on failure, for the error message | **fixes a revocation hole**: today the DELETE and the version bump are not atomic | 70% |
| **A1-14** | `tenantConfigActions.ts:59-75` (`dismissSetup`), `:106-160` | admin (home checklist, venue settings) | 5 auth + interactive tx (BEGIN, UPDATE, UPSERT, COMMIT) → 1 + 1 | A1-3; tx → `db.batch([update, bumpSyncCursor-stmt])` (atomic, 1 POST) | the batch must keep both writes atomic (libsql batch is transactional) | 75% |
| **A1-15** | `venueRoleActions.ts:132-150,164,198` | admin venue-role edits | 5 auth + target user → venue (serial) + upsert + bust (1 more revocation read via `getSubdomainAndGroup`) → 1 + 1 + 1 | A1-1/2/3; target reads → `Promise.all`; the bust reads `session.tenant` | none | 80% |

**Totals for the three paths the brief named** (production; revocation SELECT = "rev"):

| path | now | after A1-1/2/3 (+6) |
|---|---|---|
| (a) signed-in RSC page load (home, cold, no warm hit) | L1 rev (serial, before the fan-out) → L2 user⋈promoter (tonight seed) → L3 lists∥venue. Same row read 2× (3× on a reachability-cache miss, `venue-resolution.ts:47`; 4× on `/lists`; 3× plus one level on `/admin/team`) | L1 folded read → L2 lists∥venue: **−1 level on the tonight leg, −1 to −3 statements** |
| (b) admin server action (`dismissSetup`) | rev → rev (`ensureAdminAccess`) → rev (`getUserFromID`→`getDB`) → `SELECT *` user → rev (`getDB`) = **5 serial same-row reads**, then 4 tx RTs | **1** read, then 1 batch = **2 RTs total (from 9)** |
| (c) staff server action (`getFloorPlanWarmTarget`; `renameCredential`) | 4 serial rev → work; 2 serial rev → UPDATE | 1 rev → work; 1 rev → UPDATE |
| middleware | 0 DB (CSP nonce only, `middleware.ts:43-80`) | n/a |

## 2. The fold, designed (A1-1/2/3, single owner: `lib/auth/session.ts`)

```ts
// lib/auth/session.ts — sketch, not a patch
type Live =
  | { kind: 'fresh', userId: number, role: UserRole, firstName: string,
      promoterID: string | null, credentialsVersion: number }
  | { kind: 'unverified', userId: number }      // read ERRORED (after bounded retry)

const memo = new WeakMap<object, Promise<{ session: IronSession<IronSessionData>, live: Live | null }>>()

const unseal = cache(async () => { const store = await cookies(); return { store, session: await getServerActionIronSession(opts, store) } })

async function validate(store): Promise<{ session, live }> {
  const { session } = await unseal()
  const { user, tenant } = session
  if (!user || !tenant) return { session, live: null }
  try {
    const { getNamedDB } = await import('drizzle/db')              // cycle-safe, as today
    const { runInResilientRead } = await import('@lib/db/resilient-read')
    const db = await getNamedDB(tenant.subdomain, tenant.group)
    const row = await runInResilientRead(db, () => db
      .select({ credentialsVersion: u.credentialsVersion, role: u.role, firstName: u.firstName,
                promoterID: promoter.id })
      .from(u).leftJoin(promoter, eq(promoter.userID, u.id))
      .where(eq(u.id, user.id)).get(),                              // .get(), NEVER db.batch (the [] trap)
      { label: 'session-validate', maxAttempts: 2 })
    if (!row || isStampRevoked(user.credentialsVersion, row.credentialsVersion)) {
      session.user = undefined; return { session, live: null }      // FAIL-CLOSED: absent row / revoked
    }
    const role = isValidUserRole(row.role) ? row.role : 'door_staff'
    return { session, live: { kind: 'fresh', userId: user.id, role, firstName: row.firstName,
                              promoterID: role === 'promoter' ? row.promoterID ?? null : null,
                              credentialsVersion: row.credentialsVersion } }
  } catch { return { session, live: { kind: 'unverified', userId: user.id } } }  // FAIL-OPEN for the session only
}

const getValidated = cache(async () => {           // cache() still dedupes an RSC render
  const { store } = await unseal()
  let p = memo.get(store); if (!p) { p = validate(store); memo.set(store, p) }  // store the PROMISE: concurrent callers dedupe
  return p
})
export const isStampRevoked = (sealed: number | undefined, live: number) => (sealed ?? 0) < live  // ONE predicate, shared by A1-4/5
export default async () => (await getValidated()).session
export const getUnvalidatedSession = async () => (await unseal()).session   // tenant, sessionMeta, destroy
export const getLiveUser = async (): Promise<Live | null> => {
  const { session, live } = await getValidated()
  return live && session.user?.id === live.userId ? live : null  // bound to the user it was read for
}
```

Consumers:
- `getTenantFromSession`, `getSessionMeta`, `clearCookies`, `api/logout` use `getUnvalidatedSession()`. Output is identical, 0 RT.
- `hasAdminAccess`: `const live = await getLiveUser(); return live?.kind === 'fresh' && live.role === 'admin'`.
  `getUserFromID` and its dynamic import go away. The same applies to `seedRoleIsAdmin` (`listsSeedActions.ts:22`).
- `prefetchAuthContext` / `getCachedAuthScope` accept `live` (role, promoterID, firstName) and skip their user read (A1-6).

**Security invariants. Each one needs a test (§5):**
1. **Absent row → fail-closed.** `session.user` is cleared and `hasAdminAccess` is false. Today: `session.ts:175-177` plus `getUserFromID` throws, then `false`. Same result.
2. **Read error → session fail-open, admin fail-closed.** The session keeps `.user` as today (`session.ts:183-185`), but `live.kind === 'unverified'`, so the admin gate denies. That is what today's `catch { return false }` does (`accessActions.ts:53-55`).
   ⚠️ Today these are two *independent* reads, so a blip on the first one alone still lets the admin through. With one read, a transient error denies more often. The `runInResilientRead` retry (maxAttempts 2) restores that availability. It also covers A1-8's concern: this read is the **first statement of every authenticated request**, which is exactly where a dead pooled socket lands (`learnings.md:2286-2302`).
3. **Same key.** Both reads use `user.id` (the PK). The role comes from the same row, a few ms earlier in the same request. That makes the check "fresh at gate time" in the sense H-AUTH1 requires.
4. **No cross-request sharing.** The memo key is the per-request cookie store (`cookies.js:101-123`: `userspaceMutableCookies` in the action/route phase, `cookies` in render). Never key on a string, a user id or a module global. A WeakMap drops the entry with the request. If identity turns out unstable, the memo only misses: correct, but slower.
5. **A login inside the request.** `sessionWrite.ts:207` sets `session.user` on the **same memoised object**. `getLiveUser` checks `live.userId === session.user.id`, so a newly minted user is never judged by the pre-login read (it gets `null`, meaning "not admin", so it fails closed).
6. **Phase change after a revalidating action.** The render phase gets a new cookie-store object, so it validates once more. Today it already does.
7. **The unvalidated unseal is never used for an authorization decision.** Only `.tenant`, `.sessionMeta` and destroy use it. The sealed tenant is HMAC-authentic whether or not the user was revoked, and today's code already routes a revoked session's `getDB()` to that same tenant.

**Pull and push (A1-4/5) do not use `getLiveUser`. They fold into their own prefetch**, because those prefetches already read the same row in their first level:
- Pull: add `id, credentialsVersion` to the `prefetchPullAuthContext` select (`authContext.ts:263-270`). The route passes `{ sealedId, sealedStamp }`. Then `row.id !== sealedId || isStampRevoked(...)` throws `SessionRevokedError`, and the route maps it to the existing 401 body and log (`route.ts:62-83`). An absent row must also map to **401**; today it throws inside prefetch, which becomes a 500. `isWarmthPull` keeps the validated call, because it short-circuits before `processPull` (`route.ts:242-262`).
- Push: the same fold goes into the `batchPrefetch` user query (`batchPrefetch.ts:694-701`), which is one POST. The check runs **after the prefetch and before `db.transaction`** (`pushActionsBatch.ts:669 → 773`), so a revoked session writes nothing. Limiter: `checkPushRateLimitDurable(userID, { db })` runs in `Promise.all` with the prefetch. A 429 simply discards the read.

## 3. Evidence: how many times one action re-reads the same row today

In production, with `cache()` pass-through (§0):

- `ensureAdminAccess` = rev (`accessActions.ts:42` → `cookieActions.ts:9`), then `getUserFromID` → `getDB` → rev (`authQueries.ts:57`), then `SELECT *` (`authQueries.ts:59-64`). That is 3 serial reads of `user` by id.
- `ensurePlatformOrAdminAccess` (`accessActions.ts:66-70`) adds a parallel rev. `updateUserRole` (`databaseActions.ts:944-950`) then adds `getServerActionSession` and `getDB`: **6 same-row statements over 5 levels** before its single UPDATE.
- `tenantConfigActions.dismissSetup`: its own session read (`:60`), then `callerIsAdmin` (3), then `getDB` (`:67`): **5 levels**.
- `venueRoleActions.setUserVenueRole`: `getRegisteredUserFromCookieStorage` (`:115`), then `callerIsAdmin` (3), then `getDB`, then `targetUser` (`:132`), then `targetVenue` (`:141`) serially, then the upsert, then `bustReachabilityCache` → `getSubdomainAndGroup` → rev (`:80-84`).
- `getListWarmTarget` → `getTonightEntriesSeed` in action context: rev (`homeStateActions.ts:468`), then `getDB`-rev, then `resolveActiveVenueRow` (rev plus tenant-rev), `getCachedAllEvents` (`getDB`-rev), `getCachedAuthScope` (`getDB`-rev, then user⋈promoter). About 4 extra reads of the same row.
- RSC seeds that take **cookie** roles (`floor-plan/initialData.ts`, `guests/initialData.ts`, `(settings)/layout.tsx:12`) could get the live role for free from `getLiveUser`. That closes the H-AUTH class of stale-role SSR disclosure at no RT cost. It is a bonus, not a latency finding.

## 4. Client, token and tenant lookups (the brief's two direct questions)

- **Is the libsql client recreated per request? No.** `db.ts:43-88` keeps a process-wide `Map` keyed on `${subdomain}:${group}`. It is shared by `getDB` and `getNamedDB` (`db.ts:262-268`) and dropped only on transient exhaustion (`evictConnectionByDb`, `db.ts:99-104`).
  **Exception:** `sessionWrite.ts:93-160` builds a raw `createDbClient` and `close()`s it on **every login**, twice when the org-name retry fires (`:176-178`). That costs a fresh TLS handshake per login and skips the `LIBSQL_LABEL` check (`db.ts:142-156`). Fix: `getNamedDB(subdomain, group)` (A1-8).
- **Sockets.** With `TURSO_KEEPALIVE` off (the default, `lib/db/turso-keepalive.ts`), Node's undici pools with about a 4 s idle timeout (`learnings.md:2372-2378`). So the first statement of any request after an idle gap pays TCP+TLS: Oregon p50 262 ms vs 64 ms pooled. Under A1-2/3 that statement is always the session read. Its `runInResilientRead` wrapper is therefore the natural "first statement of an unwrapped path is retried" that `learnings.md:2300-2302` names as the precondition for enabling the flag on Amplify. It is a partial precondition only: a second pooled dead socket can still hit statement 2. The operator's call stands.
- **Is any token resolved per request? Not over the network.** `resolveGroupConfig` (`db.ts:146-185`) reads `process.env` synchronously, and only when the connection is created (cache miss). SSM is used only in provisioning (`lib/provisioning/group-token-ssm.ts`).
- **Tenant resolution per request.**
  - With a sealed tenant: 0 network calls after A1-1.
  - **Without one** (every pre-session request): `getSubdomainAndGroup` → Turso **Platform API** `databases.get` (`tenantContext.ts:77-91`, 5 s timeout at `lib/timeout.ts:114`). It is **repeated on every `getDB()`** in actions and route handlers, because `getConnectionParams`' `cache()` does not apply there.
  - The repo already calls this "unacceptable on an action that auto-fires on every /login mount" (`login.ts:210-212`), yet the same action pays it twice, through `checkDiscoverableOptionsLimit` and `getDB()` (`login.ts:217,223`).
  - The group is static config: `getTenant(sub).location` → `LOCATIONS[loc].tursoGroup` (`lib/config/tenants.ts:234,263-298,750`), which provisioning already treats as the source of truth (`tenant-db-target.ts:52`).
  - Misroute safety: the DB host is `${sub}-database-…`, and the group only picks the token (and the Oregon host shape). A wrong group therefore fails auth loudly and can never read another tenant's DB.

## 5. Regression tests that FAIL on today's code

All of them use the existing harness in `lib/auth/session.test.ts:33-66`: `cache` stubbed to pass-through (which models an action or route handler), iron-session faked, and `drizzle/db` mocked with a statement counter.

| id | test | today | after |
|---|---|---|---|
| A1-1 | the session has a user and a tenant; `await getTenantFromSession()` → count `getNamedDB().select` | 1 | **0** |
| A1-2 | `cookies()` returns the same object; call `getServerActionSession()` 3× plus `Promise.all` of 2 → count | 5 | **1**; a second store object gives 2 (proves per-request keying) |
| A1-3 | mock `@actions/auth/authQueries` with a spy; `ensureAdminAccess()` → `getUserFromID` calls; total user-row statements | 1 spy, 2 statements | **0 spy, 1 statement** |
| A1-3 inv. | (i) row absent → throws Access Denied, `session.user` undefined; (ii) `get` throws twice → `session.user` kept **and** `ensureAdminAccess` throws; (iii) cookie role `admin`, live `manager` → throws; (iv) `get` throws once, then succeeds → admin allowed (retry) | (iv) fails today only if the retry is new | all pass |
| A1-4 | pull route test: stub DB counting `FROM "user"` statements per non-warmth pull; plus revoked stamp → **401**, and absent row → **401** | 2 (2 levels) | **1**; 401 / 401 |
| A1-5 | `replicache-push/route.test.ts`: assert `checkPushRateLimitDurable` got `{ db }` and the user-row statement count per push | `(userID)` only; 3 statements | `{ db }`; 1 |
| A1-6 | `getTonightEntriesSeed` in an RSC-like `cache` scope: count user-row statements | 2 | 1 |
| A1-7 | `NODE_ENV=production`, no sealed tenant, host `harbour.reso.gl`: `getSubdomainAndGroup()` → `platformDB.databases.get` calls | 1 (and 1 per `getDB()`) | **0** |
| A1-8 | `authenticatedUserToCookieStorage` → `@libsql/client` `createClient` calls | 1-2 | 0 |
| A1-9 | the user read is a deferred promise; assert the watermark read started before it resolved | sequential | concurrent |
| A1-10 | `lastSlideTimestamp = now`; `slideSessionIfStale()` → `getNamedDB` calls | 1 | **0**; the due case still validates and still refuses to save a revoked user |
| A1-13 | the DELETE succeeds and the UPDATE throws → the credential row count must be unchanged (atomic) | deleted, no bump | rolled back |

## 6. Rejected candidates (do not redo)

| candidate | why rejected |
|---|---|
| Skip the revocation SELECT on RSC reads and validate only on writes | Revocation has to end *read* access (the lost-phone case, `session.ts:127-137`). Security regression. |
| Cross-request TTL cache of `credentials_version` (like `getScopingFlag`, `venue-authz.ts:100-112`) | It would remove L1 from almost every request, but "Remove device" would then take up to TTL per container to bite. **Operator-gated**: needs a ruling on an acceptable revocation window. Not proposed. |
| `db.batch` for the fold or for sync-watermark | Drizzle's batch forces `executeMethod:'all'`, so `.get()` becomes a truthy `[]` and the absent-row guard stops working (`venue-authz.ts:186-190`, `authContext.ts:257-259`). It also merges the fail-open read with fail-closed work. Use `Promise.all` or a JOIN. |
| Put the revocation check in `slideSessionIfStale` instead of at unseal | The adversary would control whether it runs (`session.ts:135-137`). A1-10 only *orders* the throttle before the read. The check stays at unseal. |
| Speculative layout fan-out alongside the revocation read | Every seed calls `getServerActionSession()` internally and would wait on it anyway. The fold (A1-6) removes the level without speculative reads for revoked users. |
| `lib/auth/venue-authz.ts` `checkVenueAccess` / `assertUserCanAccessVenue` (3 serial reads when scoping is on) | **No live callers.** The pull gate was removed (`replicache-pull/route.ts:267-273`), and the push uses the in-memory `canAccessVenue`. It is dead code; delete it rather than optimize it. |
| `getScopingFlag` read | Already cached per db handle for 600 s and primed by the warmth pull (`venue-authz.ts:55-127`). |
| `middleware.ts` | 0 DB and 0 network (CSP nonce plus `x-pathname`). Excludes `/api` and prefetches. |
| `getNamedDB` vs `getDB` pool split | Already unified (`db.ts:262-267`). |
| The pull/push second revocation read via `getDBAndGroup` | Already fixed by `getDBAndGroupForSessionTenant` (`db.ts:271-301`). A1-1 generalizes that fix to every `getDB()` caller without touching call sites. |
| Moving `getUserFromID` into `cache()` | It dedupes only in RSC and still leaves one extra read per gate. The fold makes it zero everywhere. |

## 7. Adversarial pass (what a hostile reviewer would check)

1. *"The cookie-store object is not stable per request, so the memo never hits."* Checked in `next@16.3.0` `dist/server/request/cookies.js:101-123,146-152`. In production it returns `workUnitStore.asyncApiPromises.{cookies|mutableCookies}` (a cached promise) or a promise cached in a WeakMap keyed on the underlying store. Either way the awaited value is the same object for one request. If it were not, the memo would degrade to today's behaviour, never to a leak.
2. *"A1-1 changes behaviour for revoked sessions."* No. Today a revoked session's `getTenantFromSession` already returns the sealed tenant (validation clears only `.user`, `session.ts:177,181`). A1-1 just stops paying for a SELECT whose result was never consulted.
3. *"The durable limiters are fine; 50 ms is enough."* On pre-session requests, `getDB()` inside the timed closure (`durable-limiter.ts:143-147`) runs `getSubdomainAndGroup` → Platform API before the UPSERT. That is one cross-internet HTTPS call plus a Turso statement on a possibly cold socket (52-262 ms p50 by itself). On authenticated pushes the same closure adds a duplicate revocation SELECT. The limiter fails **open** on timeout (`:178-186`). **Not verified against production logs.** Confirm with the `rate-limit-fail-open` entries (throttled to 1/min/namespace, `:70-86`) before claiming the size of the security gap. The latency claim does not depend on it.
4. *"The fold makes admin gates flakier."* It does unless the retry is added, which is invariant 2 plus test A1-3(iv).

## 8. Coordination notes for the lead

- A1-4 and A1-5 sit in pull/push territory. If a sibling axis owns `replicache-pull`/`push`, hand these over, together with the shared `isStampRevoked` predicate, so revocation logic stays in one function.
- A1-14's tx→batch and A1-13's atomicity belong to the "transactions holding interactive round trips" pattern. They are listed here because they sit inside the admin paths this axis had to count.
- Recommended landing order: **A1-1** (behaviour-neutral, largest blast radius, one line) → **A1-2** → **A1-3** (the operator's fold) → A1-10 → A1-7/8 → A1-4/5/6/9.
