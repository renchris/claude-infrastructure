# a2 · RSC routes: DB round-trip census for every App Router segment

Axis: every `page.tsx` / `layout.tsx` / `loading.tsx` under `src/app/(app)`, `src/app/(guest)`, plus
the root auth shell (`src/components/LandingPageOrLoggedInApp.tsx`, rendered by `(app)/layout.tsx:334`).
Repo: reso `b2eea41b3` (read-only worktree `reso-latency-ro`). Framework facts were checked against the
installed `next@16.3.5` in `/Users/chrisren/Development/reso-management-app/node_modules` (same commit).
"RT" means one sequential Turso round trip on the critical path. `V` means `resolveActiveVenueID`: 0 RT
on a hit in its 45 s `unstable_cache`, 2 RT on a miss (3 for promoters). See §2.3.

## 1. Findings, ranked by latency saved × path frequency

| id | route · file:line | how hot | seq RT now → after | change (one line) | conf |
|---|---|---|---|---|---|
| F1 | `/bottle-service/[rid]` layout · `bottle-service/[reservationID]/_data/seed.ts:158-285` | every table-drawer open (a FULL prefetch, `table-flow/BottleServiceEntry.tsx:71-74`), plus every doc load or soft nav into service | **≈16-19 → 2-3**, and it holds a **write lock** the whole time | replace the interactive `db.transaction` with one read `db.batch` keyed on `reservationID` and `activeVenueID` | 85% |
| F2 | every authed page, plus the shell · `lib/auth/session.ts:162-190` | every authed RSC render: doc load, soft nav, FULL prefetch | **−1 on every route** | start the reads from the unsealed session and gate the render on the `credentials_version` check in the same `Promise.all` | 80% |
| F3 | `/guests/[id]` · `guests/[id]/page.tsx:29-37`, `guests/initialData.ts:278-409` | every guest-dossier open (live-event lookup). The FULL prefetch fires on `pointerover`/`focus` (`GuestBookClient.tsx:510-546`); on touch that is tap-down, so the seed chain IS the tap latency | **6-8 → 2-3** | seeds stop waiting on `V`; bookings becomes one subquery batch | 80% |
| F4 | `/t/[claimToken]` (guest QR) · `(guest)/t/[claimToken]/page.tsx`, `actions/auth/tenantContext.ts:74-88` | every guest scan or reload, and every guest server action | **1 Platform-API call + 3 → 1** | take the Turso group from the tenant manifest instead of `api.turso.tech`; claim, table and menu go in one batch | 85% |
| F5 | `/list/[id]` doc load · `list/[listIDSlug]/listDetailSeed.ts:64-83` | hard load, reload or PWA cold start on a list (the check-in surface) | **≈7 (in a write tx) → 1** | one read `db.batch` (list, share check, items, shares), with authz decided in JS | 85% |
| F6 | shell, all (app) doc loads · `LandingPageOrLoggedInApp.tsx:189-195` | every document load | **−1** | dispatch `getDefaultEventID` and `getFloorPlanTitleSeed` off the venue promise instead of after the whole fan-out | 85% |
| F7 | shell · `LandingPageOrLoggedInApp.tsx:83-97` | every document load | **−≤50 ms** (DynamoDB probe in front of 4 DB legs) | skip the remote warm probe when `sessionMeta.loginTimestamp` is older than the 10 s warm TTL plus a margin | 75% |
| F8 | `/` page + shell tonight seed · `actions/replicache/authContext.ts:155-247` (`prefetchAuthContext`) | home doc load and every `/` FULL prefetch (`MobileNavBar.tsx:187`) | **−1** (2 levels → 1) | issue the lists read beside the user row (the R2 pattern `prefetchPullAuthContext` already uses) and filter by role in JS | 75% |
| F9 | `/floor-plan/[id]`, `/floor-plan` cold render · `floor-plan/initialData.ts:254-297` | doc load or cold-store router fetch (the warm branch skips the seed) | **−1** for admin/manager/promoter; 0 for door_staff | `fetchRecentGuests` becomes one statement (it is the only 2-RT leg of the seed's first level) | 70% |
| F10 | `/guests` · `guests/page.tsx:45-54`, `guests/initialData.ts:199-208` | every `/guests` FULL prefetch and soft nav (warm branch); cold loads | warm **1+V → 1**; cold **3-5 → 1-3** | run the warm test before `resolveActiveVenueID` (as floor-plan W2 already does); fold `reservations` into the batch | 85% |
| F11 | `/` doc load · `homeStateActions.ts:512-514` and `:272-289` | home document load | 0 seq, **−1 POST** and one duplicate full-row read | both home seeds issue the same `SELECT * FROM item WHERE list_id IN (tonight)`; wrap one `cache()` reader and use a narrow projection | 90% |
| F12 | `/bottle-menu` layout · `_data/seed.ts:128-160` (`getCatalogSeed`) | bottle-menu opens | **≈7-10 → 2-3** + write lock | same fix as F1, catalog half only | 85% |
| F13 | every route that calls `V` · `lib/venue-resolution.ts:262-288` | venue-cache miss (45 s per tenant and user) | miss **2 → 1** | fire `selectReachableVenueIDs` and `selectActiveVenueRows` together; every branch reads the active rows | 85% |
| F14 | shell + `/admin` · `LandingPageOrLoggedInApp.tsx:135`, `admin/(settings)/page.tsx:47` | every doc load (1 POST); `/admin` doc load reads it twice | 0 seq; **−1 POST** (doc), −1 duplicate (admin) | `cache()` `getCredentialsOfUser`; add a narrow projection (no `publicKey`/`externalID` blobs) | 90% |
| F15 | shell · `lib/venue-resolution.ts:318-320` (`getInitialVenues`) | every doc load | 0 seq, −1 POST | serve all venue rows from one tag-invalidated cached selector that the active-rows selector also filters | 70% |
| F16 | `/lists` cold · `listsSeedActions.ts:93-114` | cold `/lists` loads | 1 (unchanged); bytes grow with tenant history | full-table scans of `list/event/share/item`; push the non-admin visibility filter and the `item` scope into SQL | 60% |

Cross-axis notes (not mine, but found here): the libsql default transaction mode is `"write"` =
`BEGIN IMMEDIATE` (§3 F1). Every read-only `db.transaction` in the repo holds the tenant write lock:
`guest-claim-issuer.ts:202`, `databaseActions.ts:715/1380/1523` and `tenantConfigActions.ts` need a
per-site check. The pull's `resilient-transaction.ts:63` belongs to the pull axis.

## 2. Framework ground truth (these facts change how each finding is ranked)

1. **Layout and page render concurrently on a document load.** A layout's `children` is a
   `LayoutRouter` placeholder. The page element sits in the sibling `parallelRouteCacheNodeSeedData`
   slot, so Flight renders it alongside the layout
   (`next/dist/server/app-render/create-component-tree.js:382-398,429-457`). A page's reads therefore
   do NOT queue behind `LandingPageOrLoggedInApp`'s fan-out. On a document load the critical path is
   `max(shell chain, page chain)`. Both chains start behind the same `cache()`d revocation read (F2).
2. **The root (app) layout does NOT re-run on a default soft nav or on a FULL prefetch** within
   `staleTimes.static` (6 h, `next.config.js:219`):
   - A soft nav sends the current router state (`segment-cache/navigation.js:250-255`,
     `FreshnessPolicy.Default`).
   - The server only renders from the first divergent or `refetch` segment
     (`walk-tree-with-flight-router-state.js:58-61`).
   - A FULL prefetch fulfils already-held layout segments from the BFCache
     (`segment-cache/cache.js:774-800`, `scheduler.js:1175-1260`).

   The comment "soft navs re-run this layout" (`LandingPageOrLoggedInApp.tsx:76`, commit `e07f5bf88`)
   is contradicted by that source. The shell re-runs only on a document load, on `router.refresh()`
   (`RefreshAll`) and after the 6 h BFCache expires. So F6, F7, F11, F14 and F15 are
   **document-load-only**, while every page finding also pays on soft navs and prefetches.
   Confidence 80%; the measurement that settles it is in §6.
3. **No Suspense or `loading.tsx` anywhere in (app).** This is a house rule (`(app)/error.tsx:18`,
   `admin/(settings)/components/ProvisioningConsole.tsx:52`). Every route is therefore one blocking
   flush, and every RT listed is directly on TTFB for a document load and on tap-to-commit for an
   unprefetched nav.
4. **All metadata is static; no `generateMetadata` exists** (grep for `generateMetadata` over
   `(app)` and `(guest)` finds comments only). `htmlLimitedBots: /.*/` (`next.config.js:64`) makes
   metadata blocking, so static metadata is what keeps it free. There are no metadata-duplicated reads.
5. **Every (app) route is dynamic** (the root layout reads `cookies()`/`headers()`,
   `(app)/layout.tsx:165,174`). `cacheComponents`/`'use cache'` are deferred (`next.config.js:128`).
   The only cross-request stores are `unstable_cache` (venue rows 45 s, `venue-resolution.ts:61`; RUM
   config 300 s, `rum-config.ts:152`) and the DynamoDB warm cache (10 s, `warm-cache.ts:45`).
6. **Inside an interactive libsql transaction, statements are serialized on one Hrana stream.**
   `Promise.all` inside a `tx` saves at most the pairs that enqueue in the same microtask
   (`@libsql/hrana-client/lib-esm/http/stream.js:128-268`). A `db.batch` is one POST and is itself
   executed atomically, so it keeps the snapshot consistency a read transaction was buying.

### 2.3 Shared prefix every authed render pays

| step | file:line | RT |
|---|---|---|
| iron-session unseal | `session.ts:116-125` | 0 (CPU) |
| **revocation read** `SELECT credentials_version FROM user WHERE id=?` | `session.ts:162-190` | **1**, `cache()`d per render |
| tenant from sealed session | `tenantContext.ts:68-71` | 0 |
| `V` hit / miss | `venue-resolution.ts:196-290` | 0 / 2 (ctx level → active rows); +1 promoter tail |
| `isWarmStoreRouterFetch` | `store-warm.server.ts` | 0 (header + cookie) |

## 3. Per-route table (sequential RT on the critical path)

Assumptions: cold store, warm-cache miss, admin or manager unless noted. "Shell" is
`LandingPageOrLoggedInApp` and runs on document loads only (§2.2).

| route | hot during event? | chain now | now | after |
|---|---|---|---|---|
| shell, any (app) doc load | every PWA cold start | revocation 1 → probe ≤50 ms → fan-out max(tonight 3, V, venues 1, creds 1) → seeds 1 | **5 + ≤50 ms** | **2-3** (F2, F6, F7, F8) |
| shell on `/list/[id]` | list cold start | max(above, 1 + listDetail tx ≈7) | **≈8** | **2-3** (F5) |
| shell on `/floor-plan/[id]` | yes | above + title seed 1-2 (list → share) | **5-6** | **2-3** (F6: the title seed's list id comes from the path, so dispatch it at `:62`) |
| `/` page (MissionControl) | yes, also FULL-prefetched | 1 → max(V, events 1, batch 1, authScope 2) → batch 1 | **4** | **2** (F2, F8) |
| `/lists` | yes | 1 → batch ‖ role 1 | **2** | **1** (F2) |
| `/lists` warm prefetch | per warm cycle | 1 | 1 | 1 |
| `/list/[id]` page | yes | 1 (page has no seed) | 1 | 1 |
| `/floor-plan/[id]` cold | yes | 1 → V → [promoterID 1] → max(selCore 1, config 1, recentGuests **2**, specGeom 1) → [geometry 1 on a speculation miss] | **3-6** | **1-3** (F2, F9) |
| `/floor-plan/[id]` warm | per soft nav | 1 | 1 | 1 |
| `/floor-plan` (base) cold | doc loads | 1 → V → level-1 (2) → geometry 1 | **4-6** | **2-4** |
| `/guests` warm prefetch or soft nav | per warm cycle | 1 → V (discarded) | **1-3** | **1** (F10) |
| `/guests` cold (admin) | yes | 1 → V → batch 1 → reservations 1 | **3-5** | **1-3** (F2, F10) |
| `/guests` cold (promoter) | yes | 1 → V → batch → promoterRow → guests → reservations | **5-7** | **1-3** |
| `/guests/[id]` | **yes (guest lookup)** | 1 → V → bookings: ctx 1 → venue ids 1 → events 1 → reservations 1 → batch 1 | **6-8** | **2-3** (F3) |
| `/bottle-service/[rid]` layout | **yes (table service)** | 1 → max(V, ctx 1-2) → tx ≈14-16 | **16-19** | **2-3** (F1) |
| `/bottle-service/[rid]/[itemID]` | grid → detail | layout shared (not re-run); page has no reads | 0 | 0 |
| `/bottle-menu` layout | sometimes | 1 → max(V, ctx) → tx ≈5-7 | **7-10** | **2-3** (F12) |
| `/t/[claimToken]` (guest) | **yes (guest QR)** | Platform API → claim 1 → table 1 → menu 1 | **1 HTTP + 3** | **1** (F4) |
| `/recap/[eventID]` | post-event | 1 → `[pull ctx 1-2 ‖ event 1]` → insight row 1 (`recapSeedActions.ts:62-99`) | 3-4 | 2-3 (F2) |
| `/admin/*` | no | 1 → 1 (creds / team `Promise.all` / venue / platform / device count). UNVERIFIED: counted from `await` lines only; the helper bodies were not read | 2 | 1 (F2) |
| `/register` | no | 0-1 | 0-1 | 0-1 |
| `(guest)/layout.tsx`, `(app)/error.tsx`, `floor-plan/error.tsx`, `bottle-service/.../error.tsx` | n/a | no reads | 0 | 0 |

## 4. Finding details

### F1 · bottle-service seed: ~16 statements serialized inside a write-locked interactive transaction
- **Now** (`_data/seed.ts:162-285`):
  1. `[resolveActiveVenueRow ‖ prefetchPullAuthContext]` (1-2).
  2. `db.transaction`: `BEGIN` + `resolveScopeVenueIDs` (1), then catalog id reads (1-2), catalog row
     reads (1-2) and `tenantConfig` (1).
  3. Gate join (1), `getReservations` (1), `getGuestProfiles` (1), order ids (1), `getBottleOrders`
     (1), draft item ids (1), draft items (1), settled item ids (1), settled items (1), `COMMIT` (1).

  drizzle calls `this.client.transaction()` with no mode (`drizzle-orm/libsql/session.js:61`). libsql
  defaults to `mode = "write"` (`@libsql/client/lib-esm/http.js:155`), which emits `BEGIN IMMEDIATE`
  (`@libsql/core/lib-esm/util.js:5`). So every drawer-open FULL prefetch
  (`BottleServiceEntry.tsx:71-74`) takes the tenant's write lock for about 16 network round trips. That
  lands in the middle of service, while pushes (check-ins, orders) contend for that same lock.
- **After**: after `[V ‖ ctx]`, issue one `db.batch` with every statement keyed on inputs that are
  already known:
  - `venue` ids (for scope);
  - categories and menu items by `activeVenueID` (full rows, no id-then-row hop);
  - tenant config;
  - the gate join;
  - the reservation;
  - the guest profile, via `WHERE id = (SELECT guest_profile_id FROM reservation WHERE id=?)`;
  - bottle orders by `reservation_id`;
  - bottle order items `WHERE bottle_order_id IN (SELECT id FROM bottle_order WHERE reservation_id=?)`.

  Then apply `scopeVenueIDs.includes(...)`, `eventActive` and the draft/settled partition in JS, and
  return `EMPTY`/null exactly where today's code does. A batch is atomic, so snapshot consistency is
  kept and no write lock is taken.
- **Risk**:
  - Out-of-scope rows are read into server memory and discarded. They never reach a return value, and
    F4 holds because the gate is evaluated before anything is returned.
  - drizzle's batch forces `.all()`, so `.get()` sites become `.at(0)`. See the warning at
    `authContext.ts:265-267`: never batch the `if (!row)` auth guard itself.
  - Keep `byIdAsc`/`strAsc` ordering in JS.
- **Test that fails today**: a gated stub DB, in the style of `floor-plan/__tests__/speculativeGeometry.test.ts`.
  Record every `execute`/`batch`/`transaction` call, hold each wave open, and assert that
  `getBottleSeeds` finishes in ≤ 2 waves after `[V ‖ ctx]` **and** calls `transaction` 0 times.
  Today it calls it once, with ≥ 12 waves inside.

### F2 · The revocation read is a serial prefix to every page and to the shell
- **Now**: `getRegisteredUserFromCookieStorage` → `getValidatedSessionCached` does a Turso read
  (`session.ts:168-174`) before it returns the user. Every page awaits it before starting its own
  reads (`lists/page.tsx:24`, `guests/page.tsx:24`, `guests/[id]/page.tsx:20`,
  `floor-plan/[id]/page.tsx:43`, `MissionControl.tsx:44`, `bottle-service/.../layout.tsx:21`), and so
  does the shell (`LandingPageOrLoggedInApp.tsx:46`).
- **After**: add `withValidatedUser(work)` in `lib/auth/session.ts`:
  1. Unseal (`getSessionCached`, no DB).
  2. If there is no user, return null.
  3. Otherwise `Promise.all([getValidatedSessionCached(), work(unsealed.user)])`.
  4. Return the result only if the validated session still has the user.

  Seeds take the user as an argument. The `'use server'` exports (`homeStateActions.ts`,
  `listsSeedActions.ts`) keep their validated entry point, and a new internal `build*(user)` holds the
  body. The public actions must not lose the check.
- **Risk**: auth. The revocation outcome still decides whether any byte is rendered. Reads for a
  revoked session run and are discarded, and there are no writes, provided F1, F5 and F12 remove the
  write-mode transactions first. Tenant isolation is unchanged: the tenant still comes from the
  HMAC-sealed cookie. The operator-ratified fail-open/fail-closed polarity (`session.ts:152-160`) is
  untouched.
- **Test**: with a gated DB where the revocation SELECT never resolves until released, assert the
  page's seed statement has already been *issued* (it is 0 today). A second test: with a
  revoked-version row, the page returns `LoginCard` and no seed data.

### F3 · `/guests/[id]`: every seed waits on `V`, and bookings is a 5-level chain
- **Now**: `page.tsx:29` awaits `V` before the `Promise.all`, although only bookings (for the JS
  `eventByID` filter) and locker need it. Profile and label maps need only the user.
  `fetchGuestBookingsSeed` then runs:
  1. `resolveReachableScope`: ctx (1), then venue ids (1).
  2. Events (1).
  3. Reservations (1).
  4. `[reservation_guest ‖ bottle_order]` batch (1).
- **After**:
  - Level 1: `[V, ctx, venue ids, profile, promoters]`. The venue-ids statement does not depend on
    ctx, so issue it always.
  - Level 2: one batch holding the bookings statements as subqueries, with locker and elements beside
    it:
    - reservations `WHERE guest_profile_id=? AND deleted_at IS NULL AND status NOT IN ('inquiry','deposit_pending') AND event_id IN (SELECT id FROM event WHERE status<>'archived' AND venue_id IN (…reachable…))`;
    - reservation_guest and bottle_order `WHERE reservation_id IN (<same subquery>)`;
    - events for the name/date map.

  Apply the promoter `assignedEventIDs` narrowing in JS after the batch, exactly as today.
- **Risk**: F4 seed == pull. Keep the reachable-set derivation identical, including the `['default']`
  fallback at `initialData.ts:285`.
- **Test**: a wave counter shows ≤ 3 waves from page entry (7-8 today).

### F4 · The guest QR page pays a Turso Platform API call on every view
- **Now**: guests carry no staff session, so `getDB` → `getConnectionParams` → `getSubdomainAndGroup`
  falls through to `platformDB.databases.get(...)` (`tenantContext.ts:74-88`, 5 s timeout,
  `lib/timeout.ts:114`). That is an HTTPS call to the Turso control plane on every guest render and
  every guest action, before the first query. The page then runs claim (1) → table (1) → menu (1)
  (`t/[claimToken]/page.tsx`).
- **After**:
  - Resolve the group from the canonical manifest, which is declared the single source of truth
    (`lib/config/tenants.ts:2-5`), using `LOCATIONS[getTenant(subdomain).location].tursoGroup`, the
    same shape as `getSoketiHostForSubdomain` at `:772`. Use the Platform API only for subdomains the
    manifest lacks.
  - Then issue one batch:
    - the claim → reservation → event → element join;
    - categories `WHERE venue_id = (SELECT e.venue_id FROM reservation r JOIN event e … WHERE r.id = (SELECT reservation_id FROM guest_claim WHERE <token match> AND status='active' AND expires_at>?))`;
    - items the same way.
- **Risk**: tenant isolation stays host-derived exactly as today. Manifest drift is warn-only (weekly
  `tenant-drift.yml`), so keep the Platform API as a fallback when the manifest entry is absent.
- **Test**: mock `@lib/auth/platform-db`, render the page for a manifest tenant, and assert
  `databases.get` is called 0 times (1 today). Assert a single `batch` call.

### F5 · `/list/[id]` document seed: a write-mode transaction of ~7 hops
- **Now** (`listDetailSeed.ts:64-83`):
  1. `BEGIN` + `getLists` (1).
  2. Share check (1; non-owner only).
  3. Item ids (1).
  4. Share ids (1).
  5. `getTodos` (1).
  6. `getShares` (1).
  7. `COMMIT` (1).

  It runs under `BEGIN IMMEDIATE` (see F1). The shell overlaps it with the fan-out
  (`LandingPageOrLoggedInApp.tsx:62-64`), but at ~7 RT it is the longest leg on a `/list/[id]` hard load.
- **After**: `db.batch([list by id, share(listID,userID), item columns WHERE list_id=?, share WHERE list_id=?])`,
  with the owner/admin/share decision in JS. That is 1 RT with no lock.
- **Test**: stub DB; `getListDetailSeed` issues 0 `transaction` calls and 1 `batch`.

### F6 · The shell's "seeds" phase runs after the whole fan-out
- `getDefaultEventID(initialVenueID)` and `getFloorPlanTitleSeed` start at `:189`, only after the
  `Promise.all` at `:120-139` resolves. The fan-out's long pole is the tonight seed (3 RT), while
  `initialVenueID` is ready at `V` (0 RT on a hit).
- **After**: build `venueP = warmedPromise.then(... resolveActiveVenueID())`, then
  `defaultEventP = venueP.then(getDefaultEventID)`, and put it inside the same `Promise.all`. For
  `/floor-plan/[id]` the title seed's list id comes from the path, so dispatch it at `:62` like
  `listDetailSeedPromise`. The G11 `cache()` sharing with the page's selection core
  (`initialData.ts:366-383`) is preserved.
- **Test**: extend `LandingPageOrLoggedInApp.test.tsx` (the W3f ordering test style). Hold the tonight
  seed pending and assert `getDefaultEventID` has already been invoked (it is 0 today).

### F7 · The warm probe gates every cold document load, but it can only hit in the 10 s after login
- `/api/warm` is fired only from the login gesture (`DevLoginButton.tsx:55`, `fireBeamRushFade.ts:137`),
  and the TTL is 10 s (`warm-cache.ts:45`). Yet all four DB legs chain off `warmedPromise` on every
  document load, which pays up to the 50 ms DynamoDB ceiling (`dynamodb-store.ts`), and the remote leg
  is cross-cloud from Fly.
- **After**: when `sessionMeta.loginTimestamp` is older than 30 s, skip the remote `dynamoGet`. The
  local-map check stays. A skipped probe can only lose a hit and never serves wrong data. Sessions
  without `sessionMeta` keep probing.
- **Test**: with `dynamoGet` stubbed pending and an old login timestamp, assert that `getTonightEntriesSeed`
  is invoked before the probe settles.

### F8 · `prefetchAuthContext` is two levels, while its pull twin is already one
- **Now**: the user row (1), then `[accessibleLists ‖ loadVenueAuthFields]` (1)
  (`authContext.ts:161-236`). Both home seeds reach it through `getCachedAuthScope`
  (`homeStateActions.ts:151`). `prefetchPullAuthContext` already folded the same shape to one level
  (R2, `:257-290`).
- **After**:
  - Level 1: `[user row, SELECT id, owner_id, approval_required, EXISTS(share …) AS shared FROM list, loadUserScopedVenueReads]`.
    Admins keep every row; non-admins keep `owner = me OR shared`.
  - Promoter tail unchanged.
  - Scope it as a home-seed variant if the push axis prefers to leave `prefetchAuthContext` alone.
- **Risk**: authz semantics must match `checkListAccess`. Batch-vs-`.get()` trap: use `Promise.all`,
  never `db.batch`, for the guard row.

### F9 · `fetchRecentGuests` is the 2-RT leg of the floor-plan seed's first level
- Recent reservation ids (1), then profiles (1) (`initialData.ts:266-297`). Every sibling leg is 1 RT
  (selection-core batch, config batch, speculative geometry).
- **After**: one statement:
  `SELECT r.guest_profile_id, r.last_modified, gp.* FROM reservation r JOIN event e … LEFT JOIN guest_profile gp ON gp.id = r.guest_profile_id WHERE … ORDER BY r.last_modified DESC LIMIT 48`.
  Dedupe the first 8 ids in JS, *then* apply the promoter predicate in JS. That preserves today's
  "take 8, then filter" semantics exactly.
- Promoters also pay `derivePromoterID` (1) before the level (`:490`); fold it in as a scalar subquery.
- door_staff short-circuits (`:264`), so it gains nothing.

### F10 · `/guests` resolves the venue before its warm test
- `guests/page.tsx:45-54` awaits `V` and only then checks `isWarmStoreRouterFetch`. On the warm branch
  the venue is unused, and every `/guests` FULL prefetch (`MobileNavBar.tsx:187`) pays 0-2 RT for
  nothing. `floor-plan/[id]/page.tsx:49-61` fixed exactly this (W2).
- On the cold path, fold `reservations` (`initialData.ts:199-208`) into the level-1 batch as
  `event_id IN (SELECT id FROM event WHERE venue_id=? AND status<>'archived')`. For promoters, fold
  `user → promoter → guests` into one statement with a scalar subquery.

### F11–F16 (smaller)
- **F11**: `getTonightEntriesSeed` (shell) and `getHomePaneSeed` (page) both read every `item` column
  for the same tonight list ids on a home document load. The filters are identical (`:503-510` vs
  `:238-244`). Use a `cache()`d `getTonightItems(idsKey)` with a narrow projection (list_id, complete,
  count, count_checked, approved, completed_at, last_modified).
- **F12**: `getCatalogSeed` has the same transaction shape as F1. Batch venue ids, categories, items and
  tenant config.
- **F13**: `resolveActiveVenueRow` awaits reachability (`:264-266`), then `activeRows()` (`:275/284`).
  Every branch reads the active rows, so start both cached selectors together and catch the parallel
  rejection so a transient reachability error still rethrows (`:269`).
- **F14**: the shell's `getCredentialsOfUser` does `SELECT *`, including the `public_key` and
  `external_id` blobs, and `/admin` issues it again (no `cache()`).
- **F15**: `getInitialVenues` is an uncached `SELECT *` on every document load, next to a 45 s cache
  of the same table's active rows.
- **F16**: `getListsPageSeed` scans the whole `item` table (all lists, all time).

## 5. Rejected candidates (do not redo)

| candidate | why rejected |
|---|---|
| Stream with `<Suspense>` or `loading.tsx` | House zero-Suspense rule (`(app)/error.tsx:18`, `ProvisioningConsole.tsx:52`; the iOS VT morph and the Zero-Latency Nav contract). It also only hides latency; it removes no RT. |
| `generateMetadata` duplicate reads | None exist; all metadata is static by design (`(app)/layout.tsx:80-131`, blocking metadata via `htmlLimitedBots`). |
| `'use cache'` / `cacheComponents` | Deferred in `next.config.js:128` (needs route migrations); it is not a round-trip lever on its own. |
| Cache the revocation check across requests | Changes the ratified revocation latency (`session.ts:128-160`). F2 gets the same RT back with no security change. |
| `unstable_cache` for the bottle catalog or the floor-plan selection core | Stock (`availableQuantity` → soldOut), event status and maps change mid-service. It would need tag invalidation on every write path; the stale-data risk outweighs one parallel POST. |
| Sequential `await params` / `searchParams` / `getUser` (`floor-plan/[id]/page.tsx:38-43`, `list/[listIDSlug]/page.tsx:32-33`) | No I/O on the first two; the promises are already resolved. |
| `useGeometrySeedRefresh` → `router.refresh()` re-running the shell (`useGeometrySeedRefresh.ts:94-103`) | Fires at most once per geometry-hash disagreement, which is rare. |
| `PrefetchAllBottles` N prefetches (`_ui/PrefetchAllBottles.tsx:46`) | AUTO prefetch with no `loading.tsx` short-circuits to the route tree (`walk-tree-with-flight-router-state.js:79-80`); zero DB. |
| Index for `credential.user_id` | The table holds a handful of rows per tenant. Every other hot predicate on this axis is indexed (`schema.ts:263,294,459,737-745,780,819,855,881,923,950,1196,1878`). |
| Warm-skip the home seed like `/lists` | The seed IS the first painted frame on a fresh mount (`store-warm.ts:5-36`); skipping trades a blank frame for bytes. |

## 6. Uncertainties and the measurement that settles each

- **§2.2 (the shell skips soft navs)**: in prod, compare the count of `doc-metrics/ssr_timing`
  lines with `route≠unknown` against the RSC request count per session. If the shell re-ran on soft
  navs, F6, F7, F11, F14 and F15 would also move up to per-navigation.
- **F1/F5/F12 lock contention**: Turso-side, correlate push `txOpenCommitMs` (db-logger) spikes with
  drawer-open timestamps during a live event.
- **Promise.all inside a tx** (§2.6): RT counts inside transactions use a range (1-2) because
  microtask enqueue timing decides pipelining. The batch rewrite removes the question.
- **`V` hit rate** during service is unmeasured. The per-route "after" ranges give the hit and miss
  bounds.
