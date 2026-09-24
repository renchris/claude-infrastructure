# A3: seeds and prefetch, a round-trip census (reso @ b2eea41b3)

Axis: server-computed seeds that feed `useSubscribe` defaults, plus every prefetch. That covers the layout
shell seeds (`LandingPageOrLoggedInApp`), the page seeds (floor-plan, guests, lists, home, list detail,
bottle-service, recap), the nav warm resolvers, `/api/warm`, `batchPrefetch` (push), and the
store-warm / first-pull / prewarm modules. The work is read-only: every count below comes from reading the source.
Counting rules follow `~/.claude/research-artifacts/perf-rock-bottom-2026-09-04/5a-round-trip-ledger.md` §A,
which was measured against the real drizzle 0.45.2 and @libsql/client 0.17.4 stack:
- each `execute` costs 1 POST.
- a `db.batch` costs 1 POST, with BEGIN and COMMIT free.
- an interactive `db.transaction` costs 1 POST per sequential await, plus 1 for the COMMIT.
- concurrent statements inside one transaction coalesce into 1 POST.
- "Level" means one serial wait on Turso. Latency scales with levels and tail exposure scales with POSTs.

Premise checks done first. Already landed, so not re-proposed here: c5ddd5afa (four seed batches and the
guest-detail N+1), b5aaa213c + 9880d6fb3 (warm-store seed skip on `Sec-Fetch-Dest: empty`), G11 (the layout
and the floor-plan page share one `cache()`d `getSelectionCore`), L-3 (speculative floor-plan geometry),
W3f (the warm probe moved into the fan-out), 1ae39652d (venue selectors under `unstable_cache`, 45 s), and
the W3d PrefetchBatch in `batchPrefetch`. The layout and the page render **concurrently**: in census 3c the
page seed finished 43 ms before the layout. On a document load the layout is therefore usually the critical
path, and page-seed wins pay off on cold soft navs, FULL prefetches, and routes whose seed is longer than the layout.

## Findings (ranked by latency saved × path frequency)

| id | where | path · frequency | levels (POSTs) now → after | change | risk | conf |
|---|---|---|---|---|---|---|
| R1 | `src/components/LandingPageOrLoggedInApp.tsx:189-195` | every authed **document load**, all routes | +1 level after the whole fan-out → 0 | chain `getDefaultEventID` (and the base-route title seed) on the venue promise, not on the joined fan-out. Dispatch the `/floor-plan/[id]` title seed at T0 as `listDetailSeed` already is | none (same functions, same authz) | 85% |
| R2 | `src/app/actions/replicache/authContext.ts:155-247` (via `homeStateActions.ts:151-154`) | every doc load (tonight seed in layout) + home page | 2 levels (4-5 POSTs) → 1 level (1 POST) | none of level 2 needs the user row: read all lists + my shares + uvr + flag + promoter-events-by-username beside the user row in one `db.batch`, then filter in memory | authz moves from SQL to JS; parity test required | 80% |
| R3 | `LandingPageOrLoggedInApp.tsx:83-138` | every doc load that is not a login arrival | +≤50 ms DynamoDB probe gates venue/tonight/venues/RUM → 0 | skip `getWarmed` when `session.sessionMeta.loginTimestamp` is older than ~60 s. The entry lives 10 s and is written only at login | none. Fail-safe is a cold fetch, which is today's miss path | 85% |
| R4 | `homeStateActions.ts:512-514` (+ home L2 `:280`) | every doc load (tonight seed); home | items level +1 → 0 | issue the items read in level 1 as `item.listID IN (SELECT id FROM event WHERE status!='archived' …)` next to `allEvents`, then filter by venue + accessibility in JS | over-fetches items of other venues' live lists, which never ship | 65% |
| R5 | `lib/venue-resolution.ts:237-288` | every seeded render on a venue-cache miss (45 s TTL per container × user) | 2 levels → 1 | start `activeRows()` before awaiting reachability. It is needed on every branch | none (same values) | 90% |
| R6 | `src/app/(app)/list/[listIDSlug]/listDetailSeed.ts:64-87` | `/list/[id]` document loads (critical path there) | interactive tx: 5-7 sequential POSTs → 1 batch | `db.batch([list, myShare, itemsByListID, sharesByListID])`, then authorize in memory. Drop the id-then-fetch double reads | none (batch = one snapshot, ledger §A.2) | 85% |
| R7 | `src/app/(app)/bottle-service/[reservationID]/_data/seed.ts:180-300` (+ `getCatalogSeed :140-160`) | bottle-service entry + its FULL prefetch at every drawer open; bottle-menu | 9-14 in-tx POSTs + 2-3 pre-tx levels → 1 batch + 1 auth level | subqueries by `reservationID`/`venueID`; gate in memory; split draft/settled items in JS | medium: many shapes; deep-equal vs the legacy seed | 75% |
| R8 | `src/app/(app)/floor-plan/initialData.ts:266-291, 490` | floor-plan cold render (cold soft nav, FULL prefetch, doc load when the page is longer than the layout) | round 1 is 2 levels even on a speculation hit (3 for promoters) → 1 | `fetchRecentGuests` as one batch (recency + profiles `IN (subquery LIMIT 48)`); make only recentGuests wait on `derivePromoterID` | low | 85% |
| R9 | `src/app/(app)/guests/[id]/page.tsx:29-37`, `guests/initialData.ts:278-398` | every `/guests/[id]` view (no warm branch) | venue → auth → venues → events → reservations → enrichment ≈ 5-6 levels → 2 | start profile + label seeds and `resolveReachableScope` at T0; bookings = one batch after auth, with event/venue subqueries | medium: reachable-set SQL must mirror `resolveScopeVenueIDs` incl. the `'default'` fallback | 75% |
| R10 | `src/components/MobileNavBar.tsx:104,187`, `src/app/actions/navWarmActions.ts:33-76` | once per app mount, 1.5 s after `navReady` (inside the cold-load window) | 2 server actions ≈ 1 + ~3 levels and 1 + ~4 levels (~10 POSTs) → 0 | the client already holds both answers: `useFloorPlanNav().floorPlanHref` (layout-computed) and `tonightSeed[0].event.id` | none | 80% |
| R11 | `authContext.ts:257`, `venue-resolution.ts:47-51`, `guests/initialData.ts:278`, bottle `seed.ts:148,195`, `recapSeedActions.ts:74`, `homeStateActions.ts:151` | doc loads of guests-detail / bottle / recap / home (and any venue-cache miss) | 2-3 auth computations per request → 1 | one `cache()`d request-scoped `getRequestAuth(username)` that returns the full AuthContext; derive `PullAuthContext` from it | low: the React cache is per request | 70% |
| R12 | `src/app/(app)/guests/initialData.ts:160-209` | `/guests` document load / cold soft nav | admin 2 levels → 1; promoter 4 → 2 | reservations via `eventID IN (SELECT id FROM event WHERE venueID=? AND status!='archived')` inside the level-1 batch | low (the admin arm is exact) | 75% |
| R13 | `homeStateActions.ts:275-284` vs `:512-514` | every `/` document load | 2 identical `item WHERE listID IN (tonight)` reads → 1 | `cache()` a `getTonightItems(key)` shared by both seeds | none | 85% |
| R14 | `LandingPageOrLoggedInApp.tsx:135`, `admin/(settings)/page.tsx:47` | every doc load (+ 2 identical reads on an `/admin` doc load) | 1 POST (tail ticket) + payload → 0 | the credentials are read only by the lazily-mounted `AccountModal` (`AccountAvatar.tsx:236-246`). Fetch on intent, and `cache()` the helper | modal-open latency unless prefetched on pointerdown | 70% |
| R15 | `lib/venue-resolution.ts:318-345` vs `:137-144` | every doc load | 2 reads of `venue` (1 cached + 1 uncached) → 1 cached | one `unstable_cache`d all-rows selector; `activeRows = rows.filter(isActive)` | seed staleness ≤ 45 s (already accepted for activeRows) | 65% |
| R16 | `src/app/(app)/guests/page.tsx:46-54` | every warm `/guests` soft nav / prefetch | 0-2 wasted levels → 0 | check `isWarmStoreRouterFetch()` before `resolveActiveVenueID()`, as floor-plan does | none | 90% |
| R17 | `src/app/actions/replicache/batchPrefetch.ts:1586-1590` | every push by a promoter | batch + 1 serial level → batch only | register `promoterEvent ⋈ promoter ⋈ user WHERE username=?` in the PrefetchBatch; keep rows whose promoterID equals the resolved one | low | 80% |
| R18 | `src/app/(app)/floor-plan/titleSeed.ts:56-66` | floor-plan doc load by a non-admin non-owner | 2 levels → 1 | `list LEFT JOIN share ON (share.listID=list.id AND share.userID=?)` | none | 85% |
| R19 | `src/app/actions/recapSeedActions.ts:73-100` | `/recap/[id]` view (low) | 2 levels → 1 | read the insight in level 1 (`event LEFT JOIN eventInsight`), authorize after | none (the discarded row never ships) | 85% |
| R20 | `src/app/api/warm/route.ts:34-65` | once per login (off the critical path: 1.5 s animation) | ~20 POSTs, depth ~8 (ledger) → ~3 | a Route Handler, so `cache()` is pass-through: resolve session, tenant and venue once and pass them down | low | 70% |
| R21 | `src/app/actions/listsSeedActions.ts:22-30, 94-114` | `/lists` doc load / cold soft nav | batch ∥ `getUserFromID` = 2 POSTs → 1; the full `item` scan → per-list aggregates | put `select role from user where id=?` (`.all().at(0)`) in the batch; `GROUP BY listID` for KPIs (measure the `item` row count first) | the aggregates need a deep-equal test | 60% |
| R22 | `lib/auth/session.ts:162-187` | **every** authed RSC request (doc, soft nav, prefetch) | revocation SELECT is a hard serial prefix of every seed | (a) widen it to return role/firstName/promoterID and let the auth contexts skip their user-row read; or (b) overlap level-1 seed reads with it and discard on revoke | **security, the operator's call** | 55% |
| R23 | cross-cutting | every request with a wide level 1 | ~6-8 parallel single-statement POSTs in the layout's level 1 → 1 pipelined POST | a request-scoped client that coalesces same-tick `execute`s into one Hrana pipeline (per-statement errors, no `.get()` hazard, since it sits below drizzle) | architectural; needs a probe | 40% |

Aggregate for the hottest path, the `(app)` layout on a document load:
- **Today:** revocation (1) → DynamoDB probe (≤50 ms) → tonight seed (3: `max(venue 0-2, allEvents 1, auth 2)` + items 1) → L2 (`getDefaultEventID` 1, title seed 1-2) ≈ **5-6 Turso levels + 50 ms**.
- **After R1+R2+R3+R4+R5:** revocation (1) → `max(venue 0-1 → selection core 1, auth+events+items 1)` ≈ **2-3 levels**.

At the repo's measured per-statement median of 158 ms (the >100 ms population, `floor-plan/initialData.ts:506-509`), that is roughly 400-500 ms off the TTFB of every authed document load.

---

## Details

### R1: layout level 2 waits on the whole fan-out
- Today (`LandingPageOrLoggedInApp.tsx:120-195`): `getDefaultEventID(initialVenueID)` and `getFloorPlanTitleSeed` start only
  after `Promise.all` of warm probe + RUM + venue + credentials + tonight seed + venues settles. The tonight seed is 3 levels.
  `getDefaultEventID` needs **only** `initialVenueID`. On `/floor-plan/[id]` (114/114 production floor-plan
  doc loads, `initialData.ts:504`) the title seed needs **no** venue: `titleSeed.ts:45-48` takes the listID from the path.
- Change: `const venueP = warmedPromise.then(w => w ? w.initialVenueID : resolveActiveVenueID())`, then
  `defaultEventIDP = venueP.then(v => v ? getDefaultEventID(v) : null)`, started inside the fan-out. Dispatch the
  `[id]` title seed at T0 beside `listDetailSeedPromise`.
- Option (60%): issue `getSelectionCore(cookieVenueID)` speculatively at T0 and keep it only if the resolved
  venue equals the cookie's. This is the L-3 pattern: a forged cookie's rows are discarded and never ship.
- Test: render `LandingPageOrLoggedInApp` with the fan-out members mocked as deferreds. Assert that
  `getDefaultEventID` is called **before** the tonight-seed deferred resolves. It fails today because the call
  site is after the `await Promise.all`.

### R2: `prefetchAuthContext` has a level it does not need
- Level 1 is the user row (`authContext.ts:162-172`). Level 2 is `accessibleLists ∥ loadVenueAuthFields` (`:229-232`).
  The non-admin list query keys on `userID` (the username) alone. The admin branch is "all lists". The uvr and flag
  reads key on nothing from the row. Promoter events need `promoterID`, which can come by username.
  `prefetchPullAuthContext` already made this move for uvr and flag (R2 of `88e39e963514`, `:268-293`). The
  push-free variant was never given it, and it is the one the **layout** runs on every doc load.
- Change: one `db.batch`:
  - the user row (`.all().at(0)`, so the `if (!row)` guard stays live, per commit fa5e0a3c3),
  - `select id, ownerID, approvalRequired from list` (the lists table is small; `/lists` already scans it whole,
    `listsSeedActions.ts:95`),
  - `select listID from share where userID=?`,
  - `user_venue_role where userID=?`,
  - `promoterEvent ⋈ promoter ⋈ user where username=?` (projecting `promoterID`).
  Then in JS:
  - admin → all lists; else `ownerID===userID || shared.has(id)`.
  - `assignedEventIDs` = rows whose `promoterID === row.promoterID` when `role==='promoter'`. This keeps parity with the
    arbitrary-pick LEFT JOIN, because `promoter.userID` is non-unique (`authContext.ts:183-188`).
  - The flag stays `getScopingFlag` (memoised).
- Test: in `recordingLibsqlClient` + `createFullSchemaLibsqlDb`, run `prefetchAuthContext` for admin, owner, sharee,
  promoter, and a missing user. Assert `posts() === 1` (plus 1 on a cold flag) and deep-equal against
  `sequentialLibsqlClient` running the legacy function. It fails today: 3-5 POSTs.

### R3: the warm probe taxes every non-login document load
- `getWarmed` reads the local Map, then DynamoDB, bounded at 50 ms (`lib/cache/dynamodb-store.ts:29-39`). The four
  fan-out members that branch on `warmed` start only after it settles (`:125-138`). W3f's own note measured the probe
  at "~50 ms of the layout's ~60 ms". On Fly, `fly*.toml` sets no AWS region or credentials. The client either
  fails its credential chain or crosses to `us-west-2`: sin and iad cannot reach it in 50 ms. **Not measured
  per region.** The existing `warm_cache` log line (`durationMs`, `hit`) answers it: query `durationMs` p50 by host.
- The entry has a 10 s TTL (`lib/warm-cache.ts:45`) and is written only by `/api/warm`, which fires at the login
  click (`fireBeamRushFade.ts:137`, `DevLoginButton.tsx:55`). `session.sessionMeta.loginTimestamp`
  (`sessionWrite.ts:228`) bounds it: if `now - loginTimestamp > 60 s`, no entry can exist.
- Change: `warmedPromise = recentLogin ? getWarmed(...) : Promise.resolve(null)`.
- Test: mock `@lib/warm-cache`. Give the session a `loginTimestamp` of 5 minutes ago and assert `getWarmed` is not
  called. It fails today because the probe is unconditional.

### R4: the tonight seed's items level
- `getTonightEntriesSeed`: `[venue, allEvents, auth]` → items (`homeStateActions.ts:482-514`). The items read depends
  on `tonightEventIDs`, which is venue + non-archived + accessible. Issue
  `item WHERE listID IN (SELECT id FROM event WHERE status != 'archived')` in level 1 (in the same batch as
  `allEvents` if R11's auth batch absorbs it), then keep only the items of `tonightEventIDs` in JS.
- Superset cost: the items of other venues' non-archived lists. That is zero on single-venue tenants (5/7 active
  tenants have no venue row, `tableServiceActions.ts:152`).
- The alternative when the venue is a cache hit: add `AND venue_id = ?`. That is exact, but it re-couples to the
  venue resolution.
- Test: a POST/level recorder over the tonight seed. Assert that no trip is issued after the auth trip resolves.
  The current shape issues items strictly after.

### R5: venue resolver serialises two independent cached reads
- `resolveActiveVenueRow` awaits `selectReachableVenueIDs` (`venue-resolution.ts:262-267`). A miss runs
  `prefetchPullAuthContext`, which is 1 level (2 for promoters). Only after that does it call `activeRows()`
  (`:274-284`). Every branch reads `activeRows` (the username-less branch at `:254` does, and the catch branch goes
  to `firstActive`).
- Change: `const activeP = activeRows()` before the reachability await, with a `.catch` that
  re-raises inside each branch that consumes it.
- Hot: every seeded page (`floor-plan`, `guests`, `guests/[id]`, `bottle-service`, home via `getCachedVenueRow`)
  and the layout. The miss rate is high on Amplify: a 45 s TTL, per-container caches, and sporadic document loads.
- Test: `tenant === null` path (uncached, deterministic) with a level recorder. Assert that the active-rows statement
  is issued before the reachability trip resolves.

### R6: `getListDetailSeed` is an interactive transaction of sequential awaits
- `listDetailSeed.ts:64-87` runs these in one transaction: `getLists`, then share-check (non-admin, non-owner), then
  item IDs, then share IDs, then `getTodos(ids)`, then `getShares(ids)`, then COMMIT. That is 5-7 POSTs. The
  id-then-fetch pairs select the same rows twice.
- The layout dispatches it early (`LandingPageOrLoggedInApp.tsx:62-64`), but at 5-7 levels it outlasts the ~4-level fan-out, so it is the
  `/list/[id]` document-load critical path.
- Change: `db.batch([listByID, shareFor(listID,user), itemsByListID (Todo projection), sharesByListID])`. Return null
  when the list is absent or (non-admin && owner≠user && no share). The rows of an unauthorized list are dropped
  before return, so nothing ships.
- Test: `recordingLibsqlClient` gives `posts() === 1` for admin, owner, sharee and outsider (null). Deep-equal
  against the legacy function on `sequentialLibsqlClient`. It fails today: 6-7.
  Caveat: the legacy `inArray(item.id, ids)` read and a `WHERE listID=?` read carry no ORDER BY, so their row order can
  differ. Either compare order-insensitively (TodoApp sorts with `sortTodos`) or add `ORDER BY id` to both arms.

### R7: `getBottleSeeds` / `getCatalogSeed`
- The pre-transaction work is `[resolveActiveVenueRow, prefetchPullAuthContext]` (`seed.ts:191`). Inside the
  transaction there are sequential awaits at `:208, 112, 119, 127, 222, 247, 250, 262, 264, 280, 283, 293, 296`, plus
  COMMIT. That is 9 POSTs with no orders and 14 with draft + settled orders.
- Everything keys on `activeVenueID` or `reservationID`, so it collapses to one `db.batch` of:
  - venues (for `resolveScopeVenueIDs`);
  - categories and menu items by `venueID` (full rows, no id pass);
  - tenantConfig;
  - the gate row (`reservation ⋈ event`);
  - the reservation;
  - `guestProfile WHERE id = (SELECT guestProfileID FROM reservation WHERE id=?)`;
  - `bottleOrder WHERE reservationID=?`;
  - `bottleOrderItem WHERE bottleOrderID IN (SELECT id FROM bottleOrder WHERE reservationID=?)`.
  Then apply the scope and event gate in JS and split draft and settled items.
  `getCatalogSeed` becomes 1 batch.
- Hot: a FULL prefetch per drawer open (`BottleServiceEntry.tsx:68-73`). The "slow first press" returns whenever the
  tap beats a ~14-trip prefetch.
- Test: a fixture reservation with a draft order and 2 settled orders. Assert `posts() <= 2` excluding auth, and
  deep-equal against legacy via `sequentialLibsqlClient`. It fails today (≥13).

### R8: floor-plan round 1 is two levels deep
- `fetchRecentGuests` runs recency (`:266-273`), then profiles (`:288-292`), sequentially. Its siblings
  (`getSelectionCore`, config, speculative geometry) are one POST each, so recentGuests is round 1's critical path
  and the L-3 speculation only reaches 2 levels. `derivePromoterID` (`:490`) blocks all of round 1 for promoters,
  although only recentGuests reads it.
- Change: `db.batch([recencyQ, guestProfile WHERE id IN (<recencyQ ids subquery, LIMIT 48>) [AND createdByPromoterID = ?]])`.
  The dedup and order still come from `recencyQ`, so the output is identical. Pass a promise of promoterID into
  recentGuests only.
- Test: with `recordingLibsqlClient` on `getFloorPlanInitialData(..., urlEventID, hints)` (a speculation hit),
  assert that every trip is issued before the first resolves. The existing warmSeed payload fixture works.

### R9: `/guests/[id]` waterfall
- The page awaits `resolveActiveVenueID()` before all four seeds (`page.tsx:29`). The profile seed and the label-maps
  seed never read it.
- Bookings is a chain: `resolveReachableScope` (auth 1 + venue list 1) → events (`:310`) → reservations (`:326`)
  → enrichment batch (`:360`).
- Change: the page starts `fetchGuestProfileSeed`, `fetchGuestLabelMapsSeed`, and `resolveReachableScope(username)`
  at T0 and joins the venue only for bookings and locker.
  - Bookings becomes one batch: reservations ⋈ event with `event.venueID IN (reachable)`, then guests and orders by
    `reservationID IN (subquery)`.
  - When reachable is "all venues", use `venueID IN (SELECT id FROM venue)`, or `='default'` when the venue table is
    empty. That mirrors `resolveScopeVenueIDs`.
- Test: extend `guests/__tests__/seeds-round-trips.test.ts` with a level assertion. Deep-equal is already in place there.

### R10: two redundant server-action hops per app mount
- `EXTRA_WARM_RESOLVERS = [getFloorPlanWarmTarget, getListWarmTarget]` (`MobileNavBar.tsx:104`) runs once per
  mount (`WARM_TTL_MS` 5.8 h). Both answers are already on the client:
  - `getFloorPlanWarmTarget` recomputes venue + selection core. That is `initialFloorPlanHref`, which the layout
    already computed and `FloorPlanHrefSync` keeps current on venue change.
  - `getListWarmTarget` runs the **entire** tonight seed (`navWarmActions.ts:75`) to read `tonight[0].event.id`,
    which is `App`'s `tonightSeed[0]`.
- Each call also pays session revocation and a Lambda invocation, 1.5 s after `navReady`, in the window the
  first pull is using.
- Change: add `defaultFloorPlanHref` to the hrefs list, and pass the hero id from `App` (`MobileNavBar` sits
  outside `TonightProvider`, `App.tsx:430-553`, so pass it as a prop or hoist the provider).
- Test: mount MobileNavBar with `navWarmActions` spied on. Assert 0 calls. It fails today: 2.

### R11: the same request computes auth context 2-3 times
- On a guest-detail, bottle, recap or home document load, the layout runs `prefetchAuthContext` (tonight). The page
  runs `prefetchPullAuthContext` (`resolveReachableScope`, bottle `:148/:195`, recap `:74`), and a venue-cache miss
  runs it a third time inside `unstable_cache`. None of these are shared, because the React `cache()` exists only
  per call site (`homeStateActions.ts:151`, `guests/initialData.ts:278`).
- Change: one exported `cache()`d `getRequestAuthContext(username)` that returns the superset. The seeds pick fields
  from it. Ledger L8 proposed the per-request half; only the guest-detail call site got it.
- Test: render the guest-detail page and the layout seeds in one React request scope (vitest with `cache` active).
  Count user-row statements: it should be 1, and today it is ≥2.

### R12: the guests tab reservations level
- c5ddd5afa left `reservations` as its own level (`initialData.ts:199-209`), because `liveEventIDs` is computed in JS.
  Expressed as `eventID IN (SELECT id FROM event WHERE venue_id=? AND status!='archived')`, it joins the level-1
  batch.
- The promoter arm (user → promoter → guests, `:179-195`) can use the R2 username-join shape. Filter by the resolved
  promoterID in JS so the arbitrary pick keeps parity.
- Test: the existing `seeds-round-trips.test.ts` bars go from 2 to 1 (admin) and from 4 to ≤2 (promoter).

### R13: a duplicate items read on home
- On `/`, the layout's `getTonightEntriesSeed` (`:512`) and the page's `getHomePaneSeed` (`:275-284`) issue the same
  `SELECT * FROM item WHERE listID IN (tonightEventIDs)`: the event set, the filter and the order are identical.
  Neither is `cache()`d.
- Change: `const getTonightItems = cache((ids: string) => …)`, keyed on the joined ids.
- Test: render both seeds in one request scope over a recorder and count `item` statements. Expect 1; today it is 2.

### R14: credentials fetched on every document load for a modal
- `getCredentialsOfUser(user.id)` sits in the fan-out (`:135`). Its only consumer is the `AccountModal`, which
  `AccountAvatar.tsx:236` mounts only after a click. On `/admin` the settings page re-issues it uncached (`page.tsx:47`).
- Change: a session-validated action fetched on the same intent handler that warms the chunk (`:198-200`). At
  minimum, `cache()` the helper.
- Test: layout render with `getCredentialsOfUser` spied on. Expect 0 calls; today there is 1.

### R15: two reads of `venue` per document load
- `getInitialVenues` is uncached and selects all rows (`:318-320`). The resolver's active rows come from a
  45 s `unstable_cache` (`:137-144`).
- Change: one cached all-rows selector keyed exactly like `selectActiveVenueRows`, with active rows as a stable
  `filter(isActive)`. Note that `venueRowsTag` is never revalidated today (`lib/cache/tags.ts:37` has no
  `revalidateTag` caller), so a venue edit shows ≤45 s of stale seed until the first pull hands off. That is the same
  staleness the resolver already accepts.

### R16: the `/guests` warm branch pays for venue resolution
- `page.tsx:46` awaits `resolveActiveVenueID()` before `isWarmStoreRouterFetch()` (`:53`). The venue is unused
  when warm. Reorder so the warm check runs first, as `floor-plan/page.tsx` and `lists/page.tsx` already do.
- Test: mock the warm check to true, spy on `resolveActiveVenueID`, expect 0 calls.

### R17: the promoter tail in the push prefetch
- `batchPrefetch.ts:1586-1590` issues `getPromoterAssignedEventIDs` after the batch, for promoters. Register the
  username-join read in `PrefetchBatch` (conditional on nothing) and filter by the resolved promoterID. The same tail
  exists in `completeVenueAuthFields` (`venue-authz.ts:185-199`), which is on the pull axis.
- Test: `batchPrefetchContext` for a promoter over a recorder. Expect `posts() === 1`; today it is 2.

### R18 / R19: title seed and recap
- R18 `titleSeed.ts:56-66`: the share check follows the list read. Use one `LEFT JOIN share`. Test: a non-owner
  sharee costs 1 POST (2 today).
- R19 `recapSeedActions.ts:95-99`: the insight follows the auth + event level. Fetch it with the event (a `LEFT JOIN`).
  An unauthorized result is dropped before return. Test: 1 level beyond auth (2 today).

### R20: `/api/warm`
- The file is unchanged since the ledger measured ~20 POSTs at depth ~8. Every `cache()` is pass-through in a Route
  Handler, so the session revocation, tenant and venue resolution re-run per helper.
- Change: resolve once and pass values down (the `getDBAndGroupForSessionTenant` precedent, `drizzle/db.ts:262`).
- It sits off the critical path (the 1.5 s login animation) but loads Turso at every login. Its output is consumed
  only when it lands before the layout's probe.

### R21: lists seed
- `seedRoleIsAdmin` issues `getUserFromID` (`SELECT *` of the user row) as a second parallel POST (`:113`). Put
  `select role from user where id=?` in the batch.
- The batch reads **every `item` row** in the tenant (`:98-106`) to compute per-list KPIs. `computeKPIs`,
  `computePending` and `computeRecencyTs` (`lib/lists/grouping.ts:12-32`) are all SQL-aggregable
  (`SUM/COUNT/MAX … GROUP BY listID`). Measure the `item` row count first. The win scales with history.

### R22: the revocation read is the serial prefix of everything (the operator's call)
- `getValidatedSessionCached` (`session.ts:162-187`) issues `SELECT credentialsVersion FROM user WHERE id=?` before
  any seed can start, because every seed reads the validated session.
- (a) Return `role, firstName, username, promoterID` from the same statement (LEFT JOIN promoter). The request
  auth context (R11) can then skip its user-row read. That removes a POST, and a level wherever the user row still
  gates.
- (b) Start level-1 seed reads on the sealed identity in parallel and discard them on revoke. That saves 1 level on
  every authed RSC request, but seed code runs under a revoked identity (reads only, nothing ships). The alternative,
  ledger L6 (a TTL cache on the revocation read), is an open operator decision and is not repeated here.

### R23: coalescing concurrent reads (architectural, measure first)
- The layout's level 1 today is 6-8 independent single-statement POSTs (user row, uvr, events, venues, credentials,
  plus venue-miss reads). Each one is an independent "~1 s stall ticket" (the c5ddd5afa rationale).
- A request-scoped wrapper that queues `execute`s issued in the same microtask and sends them as one Hrana
  **pipeline** would return per-statement results and errors. It is not a `batch`, so there is no transaction, and
  the `.get()`→`[]` hazard does not apply because it sits below drizzle. That turns N POSTs into 1 without touching
  any seed.
- Needs a probe (does `@libsql/client` expose a non-transactional pipelined stream?) and the instrumentation
  proxy (`lib/db-instrumentation.ts:233`).

## Rejected candidates (do not redo)
- **Narrowing `getCachedAllEvents` (`SELECT * FROM event`, all venues).** The schema documents the table as
  ~10-50 rows (`drizzle/schema.ts`, event indexes). Filtering by venue would put it back behind venue resolution.
  c5ddd5afa already rejected folding it (it would move a POST, not remove one).
- **Deduping `resolveActiveVenueRow` / `getSelectionCore` between the layout and the page.** Both are already
  `cache()`d and shared (G11; census 3c:161).
- **"The seed duplicates the first pull."** It is inherent. `useSubscribe`'s `default:` is what paints the first commit of
  every fresh mount (`replicache.md` § "A seed's decisive consumer"), and the pull is a separate request. Sharing
  auth or scope across requests is ledger L6/L8, an operator decision on staleness and revocation.
- **Extending the warm-store skip to `/`, `/guests/[id]`, `/list/[id]`, bottle-service.** Per the `store-warm.ts:5-36`
  correction, skipping a seed blanks the first frame of a fresh mount unless a shell-hoisted data layer re-keys at
  tap. That is a frame decision, not a latency one.
- **`first-pull-gate.ts`, `prewarm-store.ts`, `store-warm*.ts`.** Client-only or request-header reads, with 0 Turso
  trips. The prewarm is already one idle IDB scan per turn.
- **A narrower `getSelectionCore` projection for non-floor-plan routes.** It is 1 POST either way over tiny tables,
  and it would split the G11 cache sharing with the page.
- **`getScopingFlag` in the push batch.** It is memoised for 600 s and primed by the warmth pull, so it is 0 POSTs warm.
- **`useGeometrySeedRefresh` → `router.refresh()`.** It re-renders the full tree, layout seeds included (~15 POSTs),
  but fires at most once per distinct geometry mismatch.
- **`slideSessionIfStale` action re-render.** It fires at most once per 30 min, and it belongs to the session axis
  (ledger L7).
- **"Snapshot" as an objection to batching R6/R7.** It is false: `db.batch` runs as a single transaction and gives
  one snapshot (ledger §A.2).

## Instrument needed for the level assertions
`recordingLibsqlClient` counts POSTs but not depth. Add a `depth` field: on issue,
`depth = 1 + max(depth of trips already resolved)`. Then assert `max depth` alongside `posts()`. For
deterministic in-memory libsql, this reproduces the await-chain depth, and the de-optimised
`sequentialLibsqlClient` remains the negative control.
