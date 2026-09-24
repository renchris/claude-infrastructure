# A6 — server actions (`src/app/actions/**` except `replicache/**`): DB round-trip census

Repo: reso @ `b2eea41b3` (read-only worktree `reso-latency-ro`). Scope: every action module under
`src/app/actions/` other than `replicache/**`, plus the `lib/` code those actions delegate to when the
round trip is *caused* by the action's own call pattern (`lib/auth/login.ts`, `lib/auth/session.ts`,
`drizzle/db.ts` tenant resolution). Every claim is from source; nothing was run.

Notation: **S** = the `credentials_version` revocation SELECT in `getValidatedSessionCached`
(`lib/auth/session.ts:162-188`). **P** = a Turso *Platform API* HTTPS call
(`platformDB.databases.get`, `src/app/actions/auth/tenantContext.ts:87-91`; 5 s budget,
`lib/timeout.ts:114`; latency unmeasured). "Serial" = critical-path round trips in sequence.

## Findings table (ranked by latency saved × path frequency)

| id | where | path / heat | serial RTs now → after | change (one line) | risk | conf |
|---|---|---|---|---|---|---|
| A6-01 | `src/components/MobileNavBar.tsx:104` → `navWarmActions.ts:74` | every app load (client POST, 1.5 s after `navReady`) | ≈4 serial / ≈8 POSTs → **0** | Stop asking the server for the tonight hero: `App` already holds `tonightSeed` (`App.tsx:88,430`), whose `[0].event.id` is the identical pick | none (pure client) | 85 |
| A6-02 | `MobileNavBar.tsx:104` → `navWarmActions.ts:31` | every app load (client POST) | ≈5 serial → **0** | Drop `getFloorPlanWarmTarget` from `EXTRA_WARM_RESOLVERS`; its answer is always discarded | none | 80 |
| A6-03 | all client-invoked actions (`getDB()` / `getSubdomainAndGroup()` / `getRegisteredUserFromCookieStorage()` inside an action) | every action POST in production | +1 **S** per extra call: 2–5 extra serial per action (table §A6-03) → 1 total | `getActionContext()` = one validated session + `getNamedDB(session.tenant)`; thread `db` into helpers — the `eaa25e987` route-handler fix, generalised to actions | tenant isolation (use sealed tenant only) | 85 |
| A6-04 | pre-session tenant resolution `tenantContext.ts:69-99`, `sessionWrite.ts:46-86`, `lib/auth/login.ts:163,280` | every login (email-first: 3 P + finalize: 3 P); every `/login` mount (2 P); register submit (≈6 P) | 2–3 **P** serial per action → 0 (warm) | Process-level memo `subdomain → group` (TTL, evict on error) behind `getSubdomainAndGroup`, and `fetchTenantInfo` reuses it; log-only `tenant` reads the Host header (as `login.ts:214` already does) | mis-route after relocation ≤ TTL (evict-on-error) | 85 |
| A6-05 | `lib/auth/session.ts:169-173` + `accessActions.ts:41-56` + `listsSeedActions.ts:22-29` | every admin-gated action; `/lists` seed | +1 serial (`getUserFromID`, SELECT *) → 0 | Revocation SELECT also projects `role`; expose it as the fresh role; `hasAdminAccess`/`seedRoleIsAdmin` consume it | fail-open vs fail-closed polarity (see body) | 80 |
| A6-06 | `homeStateActions.ts:258-285`, `:140-143` | every home render (RSC) | same RTs; payload O(tenant history) → O(live) | Reservations only for `tonightEventIDs`; `getCachedAllEvents` adds `status != 'archived'` — archived rows are read by neither seed | none (unused rows) | 90 |
| A6-07 | `homeStateActions.ts:482-514` (+ `:196-285`) | **every authed route** (rail seed in `LandingPageOrLoggedInApp.tsx:137`) + home | 2 levels → 1 on venue-cache hit | Await the (usually `unstable_cache`-hit) venue row first, then ONE `db.batch([events(venue, !archived), items IN (SELECT id FROM event WHERE venue_id=? AND status!='archived')])` | seed==pull parity (same JS filters) | 70 |
| A6-08 | `listsSeedActions.ts:98-106` | every `/lists` render | same RTs; items leg ships every item row ever (7 cols) → one row per list | Replace the item leg with a `GROUP BY list_id` aggregate (total, checkedIn, pending, recency) | SQL/JS parity of 3 helpers | 80 |
| A6-09 | `recapSeedActions.ts:95-99` | every `/recap/[id]` view | 3 → 2 | Read `eventInsight` in the first phase (batch with the event row); gate afterwards | none (row never leaves unless gate passes) | 90 |
| A6-10 | `databaseActions.ts:638-850` `deleteUser` | admin, rare — but holds the tenant **write lock** | ≈22 serial (≈16 inside an interactive write tx) → 3 | Pre-read target+remover (1 batch), then the whole cascade as ONE atomic `db.batch` keyed by scalar subqueries on the username | atomicity kept (batch = tx); see body | 65 |
| A6-11 | `tenantConfigActions.ts:59-98,106-174` | admin (dismissSetup, venue settings) | 8 (9) → 2 | A6-03/05 preamble + `db.batch([update tenant_config, bumpSyncCursor])` instead of `db.transaction` (BEGIN+UPDATE, UPSERT, COMMIT = 3) | batch is atomic: C-003 same-tx invariant kept | 85 |
| A6-12 | `venueRoleActions.ts:109-204` | admin | set 9 → 2; remove 7 → 2 | Preamble; one batch `[select user id, select venue id, INSERT…SELECT WHERE EXISTS(user) AND EXISTS(venue)]`; tag bust from `session.tenant.subdomain` | error-message mapping from batch results | 80 |
| A6-13 | `databaseActions.ts:447-560` `deleteCredential` | per device revoke | 7 → 2 | Preamble; one batch `[select target, DELETE…(guards) RETURNING, UPDATE user … WHERE changes()>0, select remaining]` — also makes delete+version-bump atomic (today two autocommits) | `changes()` semantics in a Hrana batch — test on libsql | 70 |
| A6-14 | `databaseActions.ts:603-636` `getAllUsers` (client: `ShareListDialog.tsx:62`; RSC: team page) | share-dialog open; team page | 6 → 2 | Preamble; one query with `EXISTS(credential)` column instead of the serial anchor query; project the columns the picker uses | PII narrowing is a bonus | 80 |
| A6-15 | `databaseActions.ts:1028-1120` `sendInvitation` (+ revoke/resend/supersede/markSent) | admin | ≈11 → ≈4 | Preamble; batch `existingUser` + `existingInvitation` | none | 75 |
| A6-16 | `CardFormBody` register submit → 3 serial action POSTs (`checkInvitationByInviteID` → `checkUsernameAvailable` → `beginPasskeyRegistration`) | once per staff account | 3 POSTs (≈6 P + 2 limiter + 3 reads) → 1 POST | Fold both checks into `beginPasskeyRegistration` server-side | UX error precedence | 70 |
| A6-17 | `lib/auth/session.ts:162-188` (root of every authed request) | every authed RSC render and action | 1 serial S at the head → 0 on reads | Start reads from the unsealed tenant/user id in parallel with S; release nothing until S resolves; writes still await S | must never write/ship before S — review-heavy | 55 |
| A6-18 | `useLogout.ts:82` + `notificationActions.ts:263` | every logout | 3 serial before `/api/logout` → 0 extra | Send the endpoint in the `/api/logout` body and delete it there | none | 70 |
| A6-19 | `notificationActions.ts:198-261` `saveSubscription` | enabling push | 5 → 2 | Preamble; batch `[select existing, INSERT … ON CONFLICT(endpoint) DO NOTHING, cap DELETE guarded by EXISTS(new id)]` | ownership-conflict mapping | 65 |
| A6-20 | `MissionControl.tsx:73-77` → 3 history actions | platform staff home only | 3 parallel POSTs → 1 | One `db.batch` of the three scans behind one gate | none | 75 |
| A6-21 | `databaseActions.ts:188-281` `initializeDB` | provisioning only | 6 serial, non-atomic → 2, atomic | One `db.batch` of the five inserts | none | 80 |

Rejected candidates are listed at the end (§Rejected) so nobody redoes them.

## Cross-cutting mechanics (read first — they explain most counts)

**M1 — `React.cache()` is a pass-through inside a Server Action.** Next runs the action as
`workUnitAsyncStorage.run(requestStore, () => action.apply(null, args))`
(`next/dist/server/app-render/action-handler.js:984`, Next 16.2.12 source; the repo pins 16.3.5) —
outside React's flight request, so `cache()` memoises nothing. The repo already documents this
(`lib/auth/session.ts:112-115`, `drizzle/db.ts:190-193,271-289`) and fixed it for route handlers
only (`eaa25e987`, `getDBAndGroupForSessionTenant`, used by pull/push/sync-watermark — `drizzle/db.ts:290`).
**No action under `src/app/actions/` uses it** (`git grep getDBAndGroupForSessionTenant` → 4 route files).
Consequence in production: each of these inside a client-invoked action re-runs the unseal **and S**:
`getServerActionSession()`, `getRegisteredUserFromCookieStorage()` (`cookieActions.ts:7-11`),
`getTenantFromSession()`, `getSubdomainAndGroup()` (`tenantContext.ts:69`), and every `getDB()`
(`drizzle/db.ts:195-206` → `getSubdomainAndGroup`). Actions called *during an RSC render*
(seeds from pages) are unaffected — `cache()` works there.

**M2 — pre-session, every `getDB()` is a Platform API call.** With no sealed tenant,
`getSubdomainAndGroup` falls through to `platformDB.databases.get` (`tenantContext.ts:77-91`), with no
memo; in an action/route handler that repeats per `getDB()`. The code already calls this
"unacceptable on an action that auto-fires on every /login mount" (`lib/auth/login.ts:210-214`) and
avoided it for the log line — but the same action's rate limiter (`lib/rate-limit/durable-limiter.ts:145`,
`opts?.db ?? await getDB()`) and flag read (`login.ts:223`) still pay it.

**M3 — `db.transaction` on remote libsql costs k+1 round trips for k statements** (BEGIN rides with
the first statement, COMMIT is its own request: `@libsql/client` `lib-esm/hrana.js:27-52,193`) and
holds the tenant DB's write lock across all of them. `db.batch` is one POST and is itself atomic.

**M4 — admin gates re-read the caller's own row.** `ensureAdminAccess` → `hasAdminAccess` →
`getRegisteredUserFromCookieStorage` (S) + `getUserFromID` (`getDB` → S, then `SELECT *` from `user`)
(`accessActions.ts:41-56`, `authQueries.ts:56-70`). S already reads that exact row
(`session.ts:169-173`) but projects only `credentialsVersion`.

## Findings in detail

### A6-01 — the Lists-tab warm resolver recomputes a value the page already shipped
- `MobileNavBar.tsx:104,187` passes `getListWarmTarget` as a resolver; `useWarmNavTargets.ts:222-247`
  calls it on the first warm (1.5 s after `navReady`, `:71,339`) and again only after
  `WARM_TTL_MS = 21_000_000` (`:30`) — i.e. once per app load.
- `getListWarmTarget` (`navWarmActions.ts:74-78`) = `getTonightEntriesSeed()[0]` run as a **client
  POST** (M1: no dedupe). Cost: S → {venue: S + S(`resolveTenantKey`, `venue-resolution.ts:71-80`) +
  `unstable_cache` ‖ events: S + `SELECT * FROM event` ‖ auth: S + `prefetchAuthContext`} → items.
  ≈4 serial, ≈8 POSTs, all to learn one id.
- `App` already receives `tonightSeed` = `getTonightEntriesSeed()` from the same SSR render
  (`App.tsx:88,99,430`; `LandingPageOrLoggedInApp.tsx:137`), and the live value is `useTonight()`
  (`lib/create-tonight-context.tsx:61`). The docblock itself says the hero is "the SAME byRecencyThenId
  pick the NowPane hero and the F3 tonight seed use".
- Change: pass `heroListHref = tonightSeed[0] ? '/list/' + id : null` into `MobileNavBar` as a static
  target (MobileNavBar sits outside `TonightProvider`, `App.tsx:430-553`, so a prop or a tiny lifted
  context; keep the array memoised — it is an effect dependency). Delete `getListWarmTarget`.
- Test that fails today: render `MobileNavBar` with a stubbed `@actions/navWarmActions`; advance timers
  past `FIRST_WARM_DELAY_MS`; assert the action mock was called 0 times and `router.prefetch` received
  `/list/<seed hero>`.

### A6-02 — the Floor-tab resolver's answer is always discarded
- `FloorPlanHrefSync` (`lib/hooks/useFloorPlanHrefSync.ts:26-50`) already resolves the destination and
  writes `floorPlanHref`; `MobileNavBar` passes that href as a STATIC target (`:187`). The resolver
  (`useWarmNavTargets.ts:234-236`) calls it "the always-wasted case": on first warm `lastResolved` is
  empty, so it fires anyway, and the result equals the just-stamped static href (or is null for the
  showcase case, where `getDefaultEventID` also returns null). The tap navigates to `floorPlanHref`,
  never to the resolver's answer, so even a divergent answer warms a URL nobody taps.
- Cost per app load: S → `resolveActiveVenueID` (S + S) → `getSelectionCore` (S + batch) ≈5 serial.
- Change: `EXTRA_WARM_RESOLVERS = []` after A6-01 (delete the array and the param if unused).
- Test: same harness as A6-01 — `getFloorPlanWarmTarget` called 0 times over a first warm.
- Not claimed: `FloorPlanHrefSync`'s own call on a venue switch (a real user action) stays; making it
  local needs element counts in Replicache — floor-plan axis, not verified here.

### A6-03 — actions re-validate the session once per helper (M1)
Serial round trips for client-invoked actions today, logged in, production:

| action | preamble reads now (S / user) | body | total serial | after A6-03+05 |
|---|---|---|---|---|
| `dismissSetup` | S, S, S, user, S | tx ×3 | 8 | 2 (with A6-11) |
| `updateTenantConfig` | S, S, S, user, S | [count] + tx ×3 | 8–9 | 2–3 |
| `setUserVenueRole` | S, S, S, user, S | user, venue, upsert, S (bust) | 9 | 2 (A6-12) |
| `removeUserVenueRole` | S, S, S, user, S | delete, S (bust) | 7 | 2 |
| `updateUserRole` | (S‖S→S→user) , S, S | update | 6 | 2 |
| `deleteCredential` | S (`getSubdomainAndGroup`, `:456`), S, S | 4 statements | 7 | 2 (A6-13) |
| `revokeInvitation` | S, S, S, user, S, S | update | 6 | 2 |
| `getAllUsers` | S, S, user, S | users, creds | 6 | 2 (A6-14) |
| `getOperatorShiftDetail` | S, S | select | 3 | 2 |
| `removeSubscription` / `getDeviceCount` | S, S | 1 | 3 | 2 |
| `saveSubscription` | S, S | 3 | 5 | 2 (A6-19) |
| `getFloorPlanWarmTarget` / `getListWarmTarget` | see A6-01/02 | | 4–5 | 0 |

- Change: one `getActionContext()` in `lib/auth/` returning `{ session, db, tenant }` from ONE
  `getServerActionSession()` + `getDBAndGroupForSessionTenant(session.tenant)` (`drizzle/db.ts:290-296`).
  Give `ensureAdminAccess`/`ensurePlatformAccess`/`getUserFromID`/`bustReachabilityCache` an optional
  `ctx` so they stop re-entering the session. Keep `getDB()` as the fallback when `ctx` is absent.
- Correctness: tenant comes only from the sealed, just-validated session object — the property
  `getDBAndGroupForSessionTenant` enforces by type (object, not string). Non-production arm unchanged.
- Test (fails today): `NODE_ENV=production` + mocked `iron-session` unseal returning `{user, tenant}` +
  `recordingLibsqlClient` (`lib/db/__tests__/recordingLibsqlClient.ts:114`) behind `getNamedDB`; invoke
  `dismissSetup()` outside a React render; assert exactly ONE statement matching
  `select "credentials_version"`. Today: 4. Mirror for `setUserVenueRole` (today 5).

### A6-04 — pre-session tenant resolution hits the Platform API per `getDB()` (M2)
Counted per flow (P serial unless noted):
- `beginPasskeyLogin` → `getAuthenticationOptionsJSON` (`login.ts:159-190`): P (`:163`, used only for a
  log field) → `getUserFromEmail` (`getDB` → P, then SELECT) → `getCredentialsOfUser` (`getDB` → P, then
  SELECT). **3 P + 2 DB**, all serial.
- `/login` mount, `beginDiscoverablePasskeyLogin` (`login.ts:200-240`): limiter (`getDB` → P, upsert)
  → `getDB` (P) → flag read. **2 P + 2 DB** on every login-page view.
- Finalize (`/api/passkey-login` → `finalizeAssertion`, `login.ts:280-291`): P (`:280`) → `getDB` (P)
  → credential+user query → `authenticatedUserToCookieStorage` → `fetchTenantInfo` (P again,
  `sessionWrite.ts:46-64`, a hand-inlined second resolver) → A6-04b. **3 P**.
- Register submit: see A6-16 (≈6 P).
- Change: (a) a module-level `Map<subdomain, {group, expiresAt}>` inside `getSubdomainAndGroup`'s
  Platform-API arm (TTL ≈10 min; delete the entry when a query against that group fails); (b)
  `fetchTenantInfo` calls the same resolver (keep its fail-loud-no-default behaviour; note it defaults a
  missing `group` to `'los-angeles-group'` while `tenantContext.ts:92` defaults to an error string —
  unify on fail-loud); (c) log-only `tenant` fields read `host` (the pattern `login.ts:214` already uses).
  Do NOT switch to `lib/config/tenants.ts` alone: probe tenants such as `a1probe` resolve only via the
  Platform API by design (`docs/runbooks/A1_COLDLAUNCH_MONITOR.md:110-125`); manifest-first with
  Platform-API fallback is an optional second step.
- Also fold `getUserFromEmail` + `getCredentialsOfUser` into one statement
  (`credential WHERE user_id = (SELECT id FROM user WHERE email = ?)` plus the user row, or a batch):
  2 DB → 1. Keep the single `SIGN_IN_FAILED_MESSAGE` collision (`authQueries.ts:91`) intact.
- Test: stub `@lib/auth/platform-db`'s `databases.get` with a counter; call `beginPasskeyLogin` twice
  with an empty session; assert the counter is 1 (today 6).

**A6-04b — `fetchOrganizationName` opens a brand-new libsql client per login**
(`sessionWrite.ts:93-140`: `createDbClient` then `close()`), so every login pays a cold TCP+TLS+HTTP
handshake instead of the pooled connection, and retries once on `undefined` (`:167-170`). Use
`getNamedDB(subdomain, group)` via dynamic import (the same cycle-avoidance `session.ts:168` uses).
Conf 75 — the cycle comment dates from before `authQueries`/`tenantContext` were split out.

### A6-05 — fold the fresh role into the revocation read (M4)
- Change: `session.ts:169-173` selects `{ credentialsVersion, role }`; attach `freshRole` to the
  returned session (request-cached in RSC, one read per action with A6-03). `hasAdminAccess`
  (`accessActions.ts:41-56`) and `seedRoleIsAdmin` (`listsSeedActions.ts:22-29`) read it.
- Polarity (the one real risk): S **fails open** on a read error (`session.ts:182-184`) while admin
  checks **fail closed**. So `freshRole` must be `undefined` on the error path and `undefined` must mean
  "not admin" (or fall back to today's explicit `getUserFromID` read). The value is at least as fresh as
  today's (same row, earlier or equal instant within one request).
- Saves 1 serial RT + 1 POST per admin-gated action; on `/lists` it removes the parallel
  `getUserFromID` POST (the H-AUTH2 "must not share a batch" rule in `seeds-round-trips.test.ts:15-17`
  is respected — it leaves the data batch untouched).
- Also: `prefetchAuthContext` re-reads `user.role` (replicache axis — flag to that owner).
- Test: count `from "user"` statements for `dismissSetup` → expect 1 (today 2 of S-shape + 1 `select *`).

### A6-06 — the home seed reads rows neither seed uses
- `reservationEventIDs = union(venueEventIDs, tonightEventIDs)` (`homeStateActions.ts:258`) =
  every event of the venue **including archived**, but `linkedReservations` is consumed only as
  `own = … r.eventID === e.id` for `e ∈ tonightEvents` (`:373`). The union is a leftover from the first
  version, where Numbers counted reservations (`git show af5d6169c`, lines 203-233); Numbers is now
  guestlist-based (`:324-329`). So every home render pulls every non-deleted reservation in the venue's
  history, binding one `?` per event ever held.
- `getCachedAllEvents` (`:140-143`) is `SELECT * FROM event` — all venues, all history, JSON columns
  (`wristbandAssignments`, `tierMinimums`, `notes`). Both seeds drop archived rows in JS (`:244,:290,:504`).
- Change: `inArray(reservation.eventID, tonightEventIDs)` (and drop the union); add
  `ne(event.status, 'archived')` to `getCachedAllEvents`. Round trips unchanged; bytes O(history) → O(live).
- Test: fixture with an archived venue event carrying reservations; assert the recorded reservation
  statement's args exclude that id and the seed output is byte-identical (the equivalence harness in
  `seeds-round-trips.test.ts` already exists).

### A6-07 — the rail seed is two dependent levels on every authed route
- `getTonightEntriesSeed` (`:467-555`) runs on every authed RSC render. Level 1 = venue ‖ all events ‖
  auth scope; level 2 = `SELECT * FROM item WHERE list_id IN (tonightEventIDs)` (`:512-514`).
- In an RSC render the venue row is `unstable_cache`-served (`venue-resolution.ts:137-158`, 45 s TTL) and
  the session is already request-cached, so awaiting it first costs ~0 on a hit. Then one batch:
  `[events WHERE venue_id=? AND status!='archived', items WHERE list_id IN (SELECT id FROM event WHERE
  venue_id=? AND status!='archived')]` ‖ auth scope. Apply the existing accessibility/promoter/venue-scope
  filters in JS exactly as today; items of inaccessible lists are fetched but never serialised.
- Home (`getHomePaneSeed`) gets the same treatment: config, team count, events, items, reservations in
  ONE level-1 batch (it currently has two levels, `:204` and `:280`).
- Net: hit → 1 serial level instead of 2 on every authed route; miss → neutral (venue RT replaces the
  items RT). Keep `react.cache` sharing between the two seeds by caching the batch, not the events read.
- Risk: F4 seed==pull parity — unchanged predicates, applied to a superset. Conf 70 (depends on the
  hit rate of the 45 s venue cache, unmeasured).
- Test: recorded statements for `getTonightEntriesSeed` show ONE `batch` POST after the venue read (today
  two POSTs in sequence); output identical on the parity fixture (`tonight-seed-parity.test.ts`).

### A6-08 — `/lists` ships the whole item table to compute per-list sums
- `listsSeedActions.ts:98-106` selects 7 columns of **every** `item` row in the tenant (all lists, all
  history); the math is `computeKPIs`/`computePending`/`computeRecencyTs` (`lib/lists/grouping.ts:12-32`),
  all SQL-expressible over non-null columns (`drizzle/schema.ts` item: `complete`, `count`,
  `count_checked`, `approved`, `last_modified` NOT NULL; `completed_at` nullable).
- Change: item leg → `SELECT list_id, COUNT(*)+SUM(count) total, SUM(CASE WHEN complete THEN
  1+count_checked ELSE 0 END) checked_in, SUM(CASE WHEN approved THEN 0 ELSE 1 END) pending,
  MAX(MAX(last_modified), COALESCE(MAX(completed_at),0)) recency FROM item GROUP BY list_id`
  (served by `idx_item_list_ord`). Lists with no items keep zeros (today's `?? []`). Same statement count
  (the 4-statement batch the W3e test pins stays 4).
- Test: parity property test — random item sets, SQL aggregate vs the three JS helpers, equal.

### A6-09 — `/recap` reads the insight after the gate
- `recapSeedActions.ts:73-99`: phase 1 = auth ‖ event row; phase 2 = `eventInsight`. The insight
  depends only on `eventID` (a validated argument). Batch `[event, eventInsight]` ‖ auth; return
  `null` exactly as today if the gate fails. 3 serial → 2. Use `.all()`+`.at(0)` in the batch (the
  batched-`.get()` trap, commit `fa5e0a3c3`, noted at `listsSeedActions.ts:90-92`).
- Test: recorded POSTs after the session read: 1 batch + auth (today 2 sequential).

### A6-10 — `deleteUser`: ~16 awaited statements inside an interactive write transaction
- Preamble: `ensureAdminAccess` (S, S, user) → `ensurePlatformAccess` (S) → `getServerActionSession` (S)
  → `getDB` (S) = 6 serial before any work (`databaseActions.ts:638-714`).
- Body (`:715-830`): BEGIN+select target, select remover, 4 cascade writes, select client groups,
  3 group deletes, `bumpSyncCursor`, invitation revoke, credential delete, user delete, COMMIT ≈ 16
  serial POSTs **while holding the tenant's write lock** (M3) — every door-staff push to that tenant
  queues behind it.
- The code's own reason for a transaction (`:705-708`: "db.batch cannot express a read whose result
  feeds a later statement") is answered by scalar subqueries: every cascade statement can key on
  `(SELECT username FROM user WHERE id = ?)`, the reassignment on
  `(SELECT username FROM user WHERE id = <remover>)`, the group deletes on
  `IN (SELECT id FROM replicache_client_group WHERE user_id = (…))` (CVR and client rows before the
  groups). The user row is deleted last, so the subquery is stable for the whole batch, and a batch is
  one transaction. Pre-read `[target, remover]` in one batch for the `missing`/`no-remover` early
  returns; guard every write with `EXISTS(target) AND EXISTS(remover)` for the race.
- 22 → 3 serial (context read, pre-read batch, cascade batch); the write lock is held for one POST.
- Risk: RETURNING counts per statement must map to the same `outcome` fields; ordering asserted.
  Conf 65 — a decided-against comment exists, so this needs the owner's ruling, not a silent rewrite.
- Test: recorder shows one `batch` containing all cascade statements and zero `BEGIN`; the existing
  `deleteUserRevocation.test.ts` cases must pass unchanged.

### A6-11 — `dismissSetup` / `updateTenantConfig`
- `db.transaction` with 2 statements = 3 POSTs (M3). `db.batch([update, bumpSyncCursor stmt])` = 1 and
  keeps the C-003 "same tx" invariant (`tenantConfigActions.ts:54-58`) because a batch is a transaction.
  Needs a statement-returning variant of `bumpSyncCursor` (`lib/sync-cursor.ts:137-147` awaits on a tx).
- `updateTenantConfig`'s `count(*)` guard (`:133-144`) can ride in the same batch only if the UPDATE
  becomes conditional (`WHERE ? = 0 OR EXISTS (SELECT 1 FROM user_venue_role)`); otherwise leave it as
  its own read — it only runs when enabling scoping.
- With A6-03/05: 8 → 2. Callers: `MissionControlBody.tsx` (optimistic, so not user-blocking) and
  `VenueSettingsForm.tsx` (user waits on save).

### A6-12 — `setUserVenueRole` / `removeUserVenueRole`
- `setUserVenueRole` (`venueRoleActions.ts:109-170`): target user `SELECT *` then venue `SELECT *`
  serially (independent), upsert, then `bustReachabilityCache` → `getSubdomainAndGroup()` → S (`:84`)
  just to learn the subdomain the session already holds.
- Batch: `[SELECT id FROM user WHERE username=?, SELECT id FROM venue WHERE id=?, INSERT … SELECT
  … WHERE EXISTS(user) AND EXISTS(venue) ON CONFLICT … DO UPDATE]`; map the two reads to today's
  "User not found"/"Venue not found" messages. Bust with `session.tenant.subdomain`.
- Adjacent (not latency, conf 60): `revalidateTag(tag, 'max')` does not set `pathWasRevalidated`
  (`next/dist/server/web/spec-extension/revalidate.js:205-211`: only no-profile or `expire === 0`), so the
  action response does not re-render the page — good for latency — but a `max` profile is
  stale-while-revalidate, so the very next SSR read can still serve the stale reachability set the
  comment at `:39-51` says the bust exists to prevent. `updateTag` is the read-your-writes API in actions.

### A6-13 — `deleteCredential`
- Serial: S (`getSubdomainAndGroup`, only for logging, `:456`) → S → S (`getDB`) → select target →
  guarded DELETE … RETURNING → UPDATE `credentials_version` → select remaining (log only). 7.
- The DELETE's own WHERE already enforces ownership and the last-credential guard; the pre-select only
  picks the error message. One batch: `[select target, DELETE … RETURNING, UPDATE user SET
  credentials_version = credentials_version + 1 WHERE id = ? AND changes() > 0, SELECT COUNT(*) …]`.
  Bonus: today the delete and the version bump are two autocommits (`:496-530`); a crash between them
  leaves the revoked device's cookie valid until expiry. The batch closes that window.
- Tenant for logging: `session.tenant.subdomain`. 7 → 2. Verify `changes()` inside a libsql batch on a
  local file DB first (conf 70).

### A6-14 — `getAllUsers`
- `ShareListDialog.tsx:59-69` calls it on first open (users are not in Replicache — a server hop is
  required). Serial: S, S, user (admin gate), S (`getDB`), `SELECT * FROM user`, then the anchor
  `credential` query (`databaseActions.ts:620-634`).
- One statement: `SELECT <picker columns>, EXISTS(SELECT 1 FROM credential c WHERE c.user_id = user.id)
  AS has_credential FROM user`, filter anchors in JS. Today it ships whole `User` rows (email,
  credentialsVersion, colorMode) to a client that needs name/username. 6 → 2.
- Team page (RSC): `getAllUsers` and `getAllInvitations` each run `ensureAdminAccess` → two identical
  `getUserFromID` POSTs in one render (`team/page.tsx:31-33`; `getUserFromID` is not `cache()`d). A6-05
  removes both.

### A6-15 — invitation actions
- `sendInvitation` (`:1028-1120`): admin gate (3), `getRegisteredUserFromCookieStorage` (S), limiter
  (`getDB` S + upsert), [platform gate S], `getDB` (S), existing user, existing invitation, insert ≈ 11.
  Batch the two existence reads; A6-03/05 on the preamble; pass `ctx.db` into the limiter
  (`durable-limiter.ts:47` already accepts `opts.db`). ≈ 4.
- `revokeInvitation` 6 → 2, `markInvitationSent` 5 → 2, `resendInvitation` (Lambda dominates),
  `supersedeInvitation` (tx of 3 → keep; rare).

### A6-16 — register submit is three serial pre-session POSTs
- `formActions.ts` `handleRegisterFormSubmit`: `checkInvitationByInviteID` (limiter P+upsert, P, select)
  → `checkUsernameAvailable` (limiter P+upsert, P, select) → `beginPasskeyRegistration`
  (`getOrganizationName` → S-less P …). Fold the invitation and username checks into
  `beginPasskeyRegistration` and return the first error; `/api/register` re-validates everything
  server-side anyway. With A6-04 the P's vanish regardless. Once per account → low rank.

### A6-17 — the revocation read heads every authed request (cross-axis, lib/auth/session.ts)
- Every seed and action awaits S before its first data read (e.g. `homeStateActions.ts:172,468`,
  `listsSeedActions.ts:68`). The unsealed cookie already carries `user.id/username` and `tenant`
  (`session.ts:66-90`), which is all the reads need to start. Start S and the first data batch together;
  `await S` before returning or writing anything; discard on revoke. Alternative with zero extra POSTs:
  put S into the action's first `db.batch`.
- Saves 1 serial RT on every authed render/action. Conf 55: the invariant "nothing leaves and nothing is
  written before S" must be enforced structurally (a wrapper), not by review. Flag to the RSC-shell axis.

### A6-18 — logout waits on a push-unsubscribe action
- `useLogout.ts:78-88`: `await removeSubscription(endpoint)` (S, S, DELETE) then `fetch('/api/logout')`.
  Send `endpoint` in the logout POST body and delete it there before destroying the session. 3 serial → 0
  extra. Once per logout.

### A6-19 — `saveSubscription`
- S, S, select existing, insert, cap delete (`push-subscription-policy.ts:98-118`) = 5 serial. One batch
  `[select existing by endpoint, INSERT … ON CONFLICT(endpoint) DO NOTHING, cap DELETE … AND EXISTS
  (SELECT 1 FROM push_subscription WHERE id = :new)]`; map "existing row of another user" to today's
  conflict error from the first result. 5 → 2.

### A6-20 — platform-staff history cards
- `MissionControl.tsx:73-77` fans out three actions, each its own POST (`operationalHistoryActions.ts:84-96`,
  `loginHistoryActions.ts:49-59`, `notificationHistoryActions.ts:56-70`). They share one gate
  (`isPlatformEmail`), so one `db.batch` of the three scans = 1 POST. Platform staff only.

### A6-21 — `initializeDB`
- Six serial statements, five inserts not atomic (`databaseActions.ts:195-280`): a failure midway leaves
  a half-initialised tenant that the `rows.length === 0` guard then skips forever. One batch after the
  meta probe: 6 → 2 and atomic. Provisioning only.

## Client components that call a server action for data they already hold

| caller | action | data already local? | verdict |
|---|---|---|---|
| `MobileNavBar.tsx:104` | `getListWarmTarget` | yes — `tonightSeed` in `App`, live `useTonight()` | **A6-01**, make it zero |
| `MobileNavBar.tsx:104` | `getFloorPlanWarmTarget` | yes — `floorPlanHref` from `FloorPlanHrefSync` | **A6-02**, delete |
| `useFloorPlanHrefSync.ts:43` | `getFloorPlanWarmTarget` (venue switch) | partly (needs element counts) | keep; floor-plan axis |
| `ShareListDialog.tsx:62` | `getAllUsers` | no (users not synced) | keep hop, shrink it (A6-14) |
| `ManageVenueAccessDialog.tsx:125,137` | set/remove venue role | write | keep, A6-12 |
| `MissionControlBody.tsx` | `dismissSetup` | write, optimistic already | keep, A6-11 |
| `OperatorSessionsPane.tsx` | `getOperatorShiftDetail` | no (server-only `mutation_log.args`) | keep; A6-03 saves 1 |
| `useLogout.ts:82` | `removeSubscription` | n/a | fold into `/api/logout` (A6-18) |
| `NotificationsContent.tsx:255-373` | push actions | no (server-only) | keep; A6-03 |
| `create-replicache-context.tsx:2132,2146` | session recheck / meta | 401 path only | not hot |
| `useEmptyState.ts:43` | `getHomeInitialState` | — | comment only; the export has no live caller |

## Rejected candidates (checked, not worth doing — do not redo)
- **Batching the `/lists` fresh-role read with the data batch** — H-AUTH2 fold deliberately kept apart
  (`seeds-round-trips.test.ts:15-17`); A6-05 removes that read instead.
- **Re-batching home level 1 / lists legs** — landed in `c5ddd5afa` (W3e) and pinned by
  `seeds-round-trips.test.ts`.
- **Cross-request venue cache** — landed (`1ae39652d`, `venue-resolution.ts:137-158`).
- **`pushTransport` prune (`pushTransport.ts:113-119`) calling `getDB()` per expired endpoint** — only on
  410/404, parallel, and `src/instrumentation.ts:192-197` explicitly says not to change it for the sweep.
- **`revalidateTag` making actions re-render the page** — it does not with the `'max'` profile (A6-12 note).
- **`getOperationalSessionHistoryAllWindows` 90-day scan** — covering index, platform staff only.
- **`getDeviceCount` `SELECT *` to count** — rows capped per user (`MAX_PUSH_SUBSCRIPTIONS_PER_USER`).
- **`consumeInvitationAndRegister` / `supersedeInvitation` interactive transactions** — once per account;
  the CAS needs the read inside the write unit.
- **`registerUser`** — refuses in production (`databaseActions.ts:301-303`).
- **`provisionActions` / `platformActions` / `lambdaActions`** — platform staff, rare; Lambda and Platform
  API calls dominate, not tenant-DB round trips.
- **Tenant group from `lib/config/tenants.ts` only** — would break Platform-API-only tenants (`a1probe`);
  memo instead (A6-04).
- **`checkUsernameAvailable` per keystroke** — it runs once, on submit (`formActions.ts`), not on input.

## Adversarial pass (what a hostile reviewer would check)
1. *"Is `cache()` really a no-op in actions, or only in route handlers?"* — verified in Next's source:
   the action runs under `workUnitAsyncStorage.run` with no flight request
   (`action-handler.js:984`); page rendering happens only afterwards and only when
   `pathWasRevalidated` is set (`:987`). The repo states the same at `session.ts:112-115`. Residual: read
   against 16.2.12 source, repo pins 16.3.5 (conf 85). A6-03's test runs it for real.
2. *"A6-06 changes output?"* — no: every consumer of `venueEvents`/`linkedReservations` filters to
   non-archived tonight events (`:239-244,:290,:373`); archived rows and their reservations reach no field.
3. *"A6-04 memo breaks relocation/DR"* — a relocation changes the group; a memoised stale group points at
   a URL whose DB no longer answers, so evict-on-error plus a short TTL self-heals; the session path is
   unaffected (sealed tenant wins, `tenantContext.ts:69-72`). Login-time fail-loud behaviour is kept.
4. *"A6-01 staleness"* — the resolver's answer was at most 1.5 s newer than the SSR seed and was then
   cached for ~5.8 h (`WARM_TTL_MS`), so the seed is no staler in practice; the live `useTonight()` is
   fresher than either.

## Measurement gaps (named, not guessed)
- P latency (Platform API from Fly `lax/sin/dfw/iad` and Amplify Oregon) is unmeasured; the
  `tenant_resolution_complete` auth-flow event (`tenantContext.ts:93-98`) already logs `durationMs` —
  read it in Logs Insights before ranking A6-04 against A6-01.
- The 45 s venue `unstable_cache` hit rate decides A6-07's win; not instrumented.
