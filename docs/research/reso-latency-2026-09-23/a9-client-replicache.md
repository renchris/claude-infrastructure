# a9 — client side: Replicache, subscriptions, client→server hops

Repo: reso @ `b2eea41b3` (read-only worktree `/Users/chrisren/Development/.worktrees/reso-latency-ro`).
Installed deps read from `/Users/chrisren/Development/reso-management-app/node_modules` (same SHA):
`next@16.3.5`, `replicache@15.3.0`, `iron-session-v8`.
House rules checked first: `.claude/rules/replicache.md` (pullInterval 60 s + iOS null toggle, Promise.all ban on
mutations, first-pull gate, watch-range narrowing decision table, index = fleet reload). Nothing below contradicts them.

## Findings table (ranked by latency saved × path frequency)

| id | where | path · frequency | RTs now → after | change (1 line) | conf |
|----|-------|------------------|-----------------|-----------------|------|
| C1 | `lib/create-replicache-context.tsx:421-441,604` → `lib/auth/session.ts:205-213` | every active client: 1 server action / 60 s; a cookie write every 30 min | per min: 1 extra HTTP hop + 1 Turso RT (credentialsVersion) → 0. Per 30 min: a current-route **RefreshAll** + whole prefetch-cache eviction + ~5 FULL re-prefetch RSC renders (layout + page seeds) → 0 | slide the session inside the pull route's response (it already reads the same session); delete the client server-action call | 85 |
| C2 | `lib/create-replicache-context.tsx:1597-1705` | iOS PWA wake: **every phone unlock** during service | WS reconnect (≥2-3 RTT to Soketi) **then** `/api/health` (1 RTT) **then** pull → WS and HTTP probes in parallel, then pull; on a WS timeout, still pull | run `waitForHTTPReady(3)` concurrently with `connect()`+`waitForPusherConnection`; skip only the resubscribe when WS is down | 75 |
| C3 | `lib/hooks/useFloorPlanHrefSync.ts:35-47` → `src/app/actions/navWarmActions.ts:31-37` | every in-session venue switch | 1 server action = HTTP hop + session RT + selection-core batch RT (≥2 sequential Turso RTs); Floor tab points at the OLD venue's event until it returns → 0 network, same commit | derive the default event locally in `FloorPlanDataProvider` from its already-subscribed `tableMaps`/`events` with the server's own pure `deriveDefaultSelection` | 75 |
| C4 | `src/components/MobileNavBar.tsx:104,184` → `navWarmActions.ts:31,74`, `homeStateActions.ts:467-514` | once per app start (+ after every C1 invalidation cascade) | 2 server actions, **serialized by Next's action queue** behind the C1 slide: ≈2 + ≥3 sequential Turso RTs (incl. `SELECT *` of the whole `event` table) before the hero list prefetch can start → 0 | pass both hrefs as static warm targets: `floorPlanHref` (already a target — the resolver is admittedly "always-wasted") and `/list/${useTonight()[0].event.id}` | 80 |
| C5 | `lib/create-replicache-context.tsx:1764-1765` | desktop/Android tab return (every `visibilitychange→visible`) | `/api/health` RTT (up to a 2000 ms abort) serial **before** the catch-up pull → pull immediately | drop the non-iOS `waitForHTTPReady(1)`; the pull response already carries `X-Deploy-SHA`/`X-Server-Version` and the puller already reloads on mismatch (`:628-643`) | 80 |
| C6 | `lib/create-replicache-context.tsx:1941-1976` | every `online` event (venue Wi-Fi flaps, VPN, sleep/wake) | queued offline mutations wait up to 5 s for the **poke** socket before `push({now:true})` → push at t=0 | fire `rep.push({now:true})` (and a first pull) before awaiting the socket; keep resubscribe after connect | 70 |
| C7 | `src/components/AppBadgeEffect.tsx:46-52` | shell, **every route**; body re-runs on every `todo/`,`list/`,`event/`,`share/` mutation (check-in = hottest write) | 4 full-prefix scans + per-list KPI/recency/`guestNames` string join for every list → 2 scans (`list/`,`todo/`), no strings | badge body = count of `!approved` todos whose `listID` is a live list | 70 |
| C8 | `src/app/(app)/floor-plan/FloorPlanShowcase.tsx:738-742` + `src/components/TodoApp.tsx:230-234` | `/floor-plan/[id]`, every todo mutation | 2 identical full `todo/` scans for the same list (`todosByList`) → 1 | expose TodoApp's keyed `todos` through `SelectedListProvider` (tagged `{forID}`) and read it in FloorPlanShowcase | 60 |
| C9 | `replicache/mutators.ts:91-95` (`todosByList`) | `/list/[id]` + `/floor-plan/[id]` roster, every todo mutation | full `todo/` scan per mutation → index-narrowed | add `todosByListID` index (fleet reload — coordinate per rule) | 55 |
| C10 | `src/components/_mission-control/HomeActiveDataProvider.tsx:106-110` | home, multi-venue tenants, every todo mutation in ANY venue | stage-2 `onData` always fires (array of every todo in every venue changes) → only on active-venue changes | return only todos whose `listID` ∈ active-venue events (dep `activeVenueID`) | 50 |
| C11 | `lib/create-tonight-context.tsx:46-50`, `src/hooks/useEventsForTonight.ts:38-45` | shell + WatchBanner, every minute | `now` in `dependencies` tears down + re-creates the subscription → full `event/`+`list/`+`todo/` rescan each minute ×2 → 0 idle rescans | subscribe without `now`; return per-event stale-candidate timestamps; apply the 2 h predicate in a `useMemo([entries, now])` | 45 |
| C12 | `src/app/(app)/guests/[id]/GuestDetailClient.tsx:144-160` | guest dossier open | full `floorPlanElement/` scan (all venues' geometry rows) for table labels → index scans of the active venue's maps | reuse `listTableMapsByVenue` + `floorPlanElementsByTableMap` (the `useActiveVenueSignals.ts:45-50` pattern) | 50 |

Network-hop findings (C1-C6) dominate; C7-C12 are main-thread CPU on the local store (no Turso), ranked below
them because the prewarm module measures today's stores at "~5 ms" per cold prefix read
(`create-replicache-context.tsx:1170-1180`), so each redundant scan is ms-scale, not 100 ms-scale.

---

## C1 — the session slide is a cookie-writing server action, and Next 16 answers a cookie write with a router refresh + a whole prefetch-cache eviction

**Now.** The puller calls `slideSessionThrottled()` on every 200 pull (`create-replicache-context.tsx:604`), a
60 s leading-edge throttle over the `'use server'` action `slideSessionIfStale` (`:437-441`,
`src/app/actions/auth/cookieActions.ts:20`). The action (`lib/auth/session.ts:205-213`):
1. `getServerActionSession()` → `getValidatedSessionCached` → **1 Turso RT** (`SELECT credentials_version`,
   `session.ts:161-166`) — on every call, including the 29-of-30 calls that then no-op.
2. Every 30 min (`SESSION_SLIDE_INTERVAL_MS`, `session-constants.ts:20`) → `session.save()` →
   `cookieHandler.set(...)` (`iron-session-v8/dist/index.js:665`).

What Next 16.3.5 does with step 2 (verified in installed source):
- Server: `getModifiedCookieValues(requestStore.mutableCookies).length` ⇒ `x-action-revalidated:
  ActionDidRevalidateStaticAndDynamic` (`next/dist/server/app-render/action-handler.js:117-120`).
- Client: `invalidateBfCache()`, **`invalidateEntirePrefetchCache()`**, `startRevalidationCooldown()`
  (`client/components/router-reducer/reducers/server-action-reducer.js:218-238`), then — no flight data,
  no redirect — `navigate(state, currentUrl, …, FreshnessPolicy.RefreshAll)` (`:297,333`), i.e. the same
  path as `router.refresh()` (`refresh-reducer.js:45`): a full RSC re-render of the current route, layout seeds
  included.
- `invalidateEntirePrefetchCache` → `pingInvalidationListeners` + `pingVisibleLinks`
  (`segment-cache/cache.js:229-234`) → `useWarmNavTargets`' `onInvalidate` deletes `lastWarmedAt`
  (`lib/hooks/useWarmNavTargets.ts:196-205,253-260`) → the next 60 s tick re-issues FULL prefetches of
  `/`, `/lists`, `/floor-plan/{id}`, `/guests` + the resolved hero list = ~5 cookie-authenticated RSC renders.
  The layout (`LandingPageOrLoggedInApp`) seeds run on each; only 4 page segments skip their seed on a warm
  store (`git grep store-warm.server`: floor-plan ×2, guests, lists).
- Between the eviction and the re-warm, a tab tap is a cold blocking navigation — the exact 275-847 ms
  symptom `useWarmNavTargets.ts:123-126` exists to remove. With `staleTimes` raised to 6 h (`295e790eb`),
  this slide is now the dominant reason a warm entry dies mid-shift: 12 evictions per 6 h shift per client.
- Also: server actions are serialized client-side (`app-router-instance.js:138-170`: a non-navigation action
  is appended behind the pending one). The slide fires on the **first** pull of every load (leading edge),
  so it sits at the head of the queue during the cold-load window, ahead of C4's two resolvers and any
  user-initiated action.

**After.** Slide inside `src/app/api/replicache-pull/route.ts` using the session object it already resolved
(`route.ts:59`): `if (session.sessionMeta && shouldSlideSession(now, last)) { session.sessionMeta = {…,
lastSlideTimestamp: now }; await session.save() }`. A Route Handler's cookie write is a plain `Set-Cookie` on a
`fetch` response — no router action, no `x-action-revalidated`, no refresh, no eviction. Remove
`slideSessionThrottled` + the `slideSessionIfStale` import from the context. Per minute: −1 HTTP hop, −1 Turso RT.
Per 30 min: −1 route refresh, −~5 FULL prefetch renders, and no cold-tap window.
(Alternative if the pull route must stay untouched: a `POST /api/session/slide` route handler called by `fetch`
— removes the cascade but keeps the per-minute RT. Inferior.)

**Correctness risk.** Auth: the pull route's session is the validated one (revocation check already ran), same
as today's action. `loginTimestamp` stays untouched (401 monitoring). Skip the slide on the `sys/warmth-pull`
sentinel short-circuit and on 401. SameSite=None/Secure cookie on a same-origin fetch response is honoured by
WebKit (the #255524 fix was about *sending*). Multi-tab concurrent pulls each re-seal — last write wins, both
seals valid. Keep the server-side 30-min predicate so the cookie is not re-issued per pull.

**Regression tests that fail today.** (a) Static: `create-replicache-context.tsx` imports no symbol from
`@app/actions/auth/cookieActions` other than the 401-path ones (today it imports `slideSessionIfStale`, `:22`).
(b) Route: pull with a session whose `lastSlideTimestamp` is now−31 min returns a `Set-Cookie` for the session
cookie and issues **no** extra DB statement (count through the stub DB); now−5 min returns none.
(c) Playwright/network: 3 min idle on `/list/{id}` with pokes → zero requests carrying a `Next-Action` header.

## C2 — iOS wake serializes two independent network probes before the catch-up pull

**Now** (`create-replicache-context.tsx`): disconnect → `await sleep(200 + jitter)` (`:1597`) → `connect()` →
`await waitForPusherConnection(…, 5000)` (`:1605`) → resubscribe → `await waitForHTTPReady(3)` (`:1650`) →
`rep.pull({now:true})` (`:1705`). The HTTP probe does not depend on the socket; its own comment says the two
layers initialise independently (`:1640-1648`). Worse, `if (!websocketReady) … return` (`:1607-1614`) skips the
pull entirely when Soketi is slow/down, so the unlocked phone shows pre-lock data until the restored 60 s
interval or the 15-20 s aggressive interval fires — the same "poke channel is not the sync channel" defect A5
already fixed for the `online` path (`:1947-1952`).

**After.** `const [ws, http] = await Promise.all([connectAndWait(), waitForHTTPReady(3)])`; resubscribe iff `ws`;
pull iff `http.ready` (version-mismatch branch unchanged). Saves ≈ min(WS handshake, health RTT) on every unlock;
removes a ≤60 s staleness tail on WS failure. The HTTP-before-pull rule is preserved (house rule "KEPT: HTTP
health check before pull").

**Risk.** A pull that lands before the resubscribe can miss a poke in the gap; the trailing coalesced pull on
the next poke / interval covers it — same exposure as today's `online` path. **Test:** fake timers, WS connect
resolves at 300 ms, health at 200 ms → `rep.pull` dispatched at ≈500 ms, not ≈700 ms; WS never connects → pull
still dispatched after health (today: never).

## C3 — a venue switch is "zero round-trip" except for the Floor tab

`setActiveVenueID` is a synchronous local flip (`lib/create-venue-context.tsx:131-150`), but `FloorPlanHrefSync`
re-resolves on every `activeVenueID` change through the server action `getFloorPlanWarmTarget`
(`useFloorPlanHrefSync.ts:35-47`): HTTP hop → validated session (1 RT) → `resolveActiveVenueID` → 
`getSelectionCore` batch (1 RT) → `deriveDefaultSelection` (`initialData.ts:439-463,692-697`). Until it returns,
`floorPlanHref` — and therefore `FloorPlanDataProvider.defaultEventID` (`create-floor-plan-data-context.tsx:217`)
and the MobileNavBar warm target — still names the **previous venue's** event.

**After.** `FloorPlanDataProvider` already holds the active venue's `tableMaps`, `events`, `tenantConfig` and
`activeVenue.defaultTableMapID`, and computes `defaultTableMapID` with the same `resolveTableMapID`
(`:249-260`). Move the pure `deriveDefaultSelection` to `lib/floor-plan/` (server imports it back — one algorithm,
no drift, the lesson recorded at `initialData.ts:431-438`), feed it the non-archived venue events sorted
`date DESC` (server order, `initialData.ts:392-394`) and a `tableMapIDsWithElements` set from one
`floorPlanElementsByTableMapID` first-key probe per map (only consulted in the no-pin fallback), and write
`setFloorPlanHref` from that. Keep the SSR `initialFloorPlanHref` for the first frame.

**Risk.** Promoter scope: the client's events are the pull's scoped subset, the server's `getSelectionCore` is
venue-scoped only — the client answer can differ for a scoped promoter (and is the one they can actually open).
Parity test required. **Tests:** (a) FloorPlanHrefSync with a mocked `getFloorPlanWarmTarget`: after a venue
switch the mock is called 0 times (today 1) and `floorPlanHref` is the new venue's event in the same commit.
(b) Fixture parity: shared `deriveDefaultSelection` over server-shaped and Replicache-shaped rows returns the same id.

## C4 — two startup server actions to learn two hrefs the client already holds

`useWarmNavTargets(['/', '/lists', floorPlanHref, '/guests'], EXTRA_WARM_RESOLVERS, navReady)`
(`MobileNavBar.tsx:184`) with `EXTRA_WARM_RESOLVERS = [getFloorPlanWarmTarget, getListWarmTarget]` (`:104`). On
the first warm both resolvers run (`lastResolved` is empty, `useWarmNavTargets.ts:237-240`):
- `getFloorPlanWarmTarget` — ≥2 sequential RTs; its answer equals the static `floorPlanHref` target already
  warmed moments earlier (the code comment at `useWarmNavTargets.ts:230-236` calls it "the always-wasted case").
- `getListWarmTarget` → `getTonightEntriesSeed()` (`homeStateActions.ts:467-514`): validated session (1 RT) →
  `Promise.all([venue row, getCachedAllEvents (SELECT * FROM event, all venues), auth scope])` (≥1 RT) →
  `SELECT * FROM item WHERE list_id IN …` (1 RT) — only to read `tonight[0].event.id`, which
  `TonightProvider` holds locally (`lib/create-tonight-context.tsx:50`, same `byRecencyThenId`).
- Next's action queue runs them one after another, behind C1's slide (see C1), so the hero list's FULL
  prefetch starts only after ~3 serialized actions (~6 sequential Turso RTs + 3 HTTP hops).

**After.** Drop `EXTRA_WARM_RESOLVERS`; pass `heroHref = tonight[0] ? '/list/' + tonight[0].event.id : ''` as a
static target (empty strings are already skipped, `useWarmNavTargets.ts:188`). `MobileNavBar` renders outside
`<TonightProvider>` (`App.tsx:430` vs `:553`) — widen the provider to wrap the nav (it sits inside
`VenueContextProvider` already). **Risk:** none for authz (the tonight set is the pulled set, F4). **Test:**
mount MobileNavBar with mocked actions → 0 calls to either resolver (today 2) and `router.prefetch` receives
`/list/{hero}`.

## C5 — desktop tab return awaits a health check whose only output the pull already carries

Non-iOS branch: "Quick version check (single attempt, **non-blocking** for pull)" (`:1764`) — but it is
`await`ed (`:1765`) before `rep.pull` (`:1803`), and `ready:false` is ignored (the pull runs anyway), so its sole
effect is the version check. The pull route sets `X-Deploy-SHA`/`X-Server-Version` on every 200
(`src/app/api/replicache-pull/route.ts:336,345`) and the puller reloads on mismatch (`:628-643`). **After:** pull
first; −1 RTT (−up to 2000 ms on a hung socket, the fetch's abort) per tab return. **Test:** health fetch mocked
to never resolve → `rep.pull` called within the same task as the visibility handler (today: after 2000 ms).

## C6 — the `online` handler drains queued offline mutations only after the poke socket connects

`handleOnline` awaits `waitForPusherConnection(…, 5000)` (`:1941`) before `rep.pull`/`rep.push({now:true})`
(`:1961,1976`). The push leg needs no socket. **After:** `rep.push({now:true})` first (offline check-ins land up to
5 s sooner on a flapping venue network), keep the socket wait only for resubscribe + the trailing pull.
**Test:** socket that never connects + reachable HTTP → `rep.push` called before 5 s elapses (today at 5 s + probe).

## C7-C12 — local-store scan hygiene (client CPU, no Turso)

- **C7 AppBadgeEffect** (`AppBadgeEffect.tsx:46-52`) runs `listsWithKPIs` — 4 prefix scans (`list/`, `event/`,
  `share/`, `todo/`, `mutators.ts:312-361`) plus per-list recency, KPIs and a `guestNames` join over every
  todo text — in the persistent shell, to produce `Σ pending`. `computePending` is `!approved` count
  (`lib/lists/grouping.ts:30-32`). Body: `ids = listLists → Set`; `count todos where !approved && ids.has(listID)`.
  Watch range drops `event/` and `share/`. Semantics identical. Test: a recording `ReadTransaction` shows prefixes
  `['list/','todo/']` only (today four).
- **C8** On `/floor-plan/[id]` TodoApp's `liveTodos` (`TodoApp.tsx:230-234`, `listID` = path id, `:105`) and
  FloorPlanShowcase's `eventTodos` (`FloorPlanShowcase.tsx:738-742`) are the same `todosByList` body. Publish the
  tagged `{forID, todos}` through `SelectedListProvider` (`TodoApp.tsx:426-428,482`); consume when
  `forID === displayEvent.id`, else keep the local subscription. Test: count `todo/` scans per mutation on the
  route = 1 (today 2).
- **C9** `todosByList` is a full `todo/` scan + filter (`mutators.ts:91-95`, "would be better to use an index").
  A `todosByListID` index (`prefix 'todo/'`, `jsonPointer '/listID'`; nanoid ids satisfy invariant 2) narrows
  both stages for the roster — the check-in screen. Cost per the rule: fleet `onUpdateNeeded` reload; batch with
  any other index change. Grouped consumers (Tonight, Home, `listsWithKPIs`) still need the full scan.
- **C10** `HomeActiveDataProvider` `todos` returns every todo in every venue (`:106-110`); any venue's check-in
  changes it, so the deep-equal gate never suppresses. Filter to `listID ∈ venue events` with
  `dependencies: [activeVenueID]`. Seed shape must match (`seed.todos`) — check `getHomePaneSeed` scopes the same way.
- **C11** `useMinuteTick` in `dependencies` (`useEventsForTonight.ts:43`) re-creates the subscription every
  minute; only `pendingStaleTables` depends on `now` (`mutators.ts:249-306`). The code comment accepts this
  as "one cheap re-scan"; the fix is optional and ranks last among network-free items.
- **C12** `liveLabelMaps` scans all `floorPlanElement/` rows tenant-wide (`GuestDetailClient.tsx:144-160`);
  promoter names stay tenant-wide. Behind a navigation, so low.

---

## Rejected candidates (do not redo)

| candidate | why rejected |
|-----------|--------------|
| Change `pullInterval: 60000` / the iOS null toggle | House rule "NEVER change" (`replicache.md` § pullInterval Lifecycle). |
| Enable `NEXT_PUBLIC_REPLICACHE_CHEAP_POLL` | Shipped W5b (`902c9fac1`), build-time flag; a deploy decision, not code. Note: the Fly `Dockerfile` does not set it (only `NEXT_PUBLIC_GIT_SHA`/`VAPID`), so Fly builds run blind 60 s pulls. Amplify state unknown offline. |
| `requestOptions.minDelayMs: 100` → Replicache default 30 (`Ro=30`, `replicache/out/chunk-B3SOU6MT.js`) | Only spaces consecutive requests of one loop (`maxConnections=1`) from the previous *start*; real pushes/pulls take >100 ms, so no measurable gain. |
| `pushDelay` | Unset ⇒ Replicache default 10 ms debounce. Nothing to win. |
| Suppress the pull a client's own push-poke triggers | Required for `lastMutationIDChanges` ack; coalescer (`listenActions.ts:247-285`) already bounds bursts to ≤2 pulls. |
| Parallelize mutations | Forbidden (`replicache.md` § Mutation Ordering). |
| Index-narrow `listEventsByVenue` / `listTableMapsByVenue` | No `venueID` index; rule's decision table says stage-2 gate suffices at these n. |
| Drop the iOS `waitForHTTPReady` entirely | House rule ("the real solution", Test #9). C2 only parallelizes it. |
| `useGeometrySeedRefresh` `router.refresh()` (`src/components/floor-plan/hooks/useGeometrySeedRefresh.ts:102`) | Fires at most once per distinct re-bake per client; rare. |
| `ShareListDialog` → `getAllUsers`, `OperatorSessionsPane` → `getOperatorShiftDetail`, `dismissSetup`, admin actions | Data not synced to Replicache (users, shift history) or rare admin writes; click-gated. |
| Duplicate `tenantConfig/default` subscriptions (useFeatureFlags, FloorPlanDataProvider, useEmptyState, bottles) | Single-key `tx.get`; negligible. |
| Warm-at-tap, floor-plan provider hoist, first-pull/nav gates, store prewarm, sync-lib deferral, socket-flap narrowing | Already landed (`e45ee5e16`, `295e790eb`, `90e1c70c2`, `663b04df2`, `e2bbda918`, `e115a799b`). |
| Venue-filter the share scan | House rule: share graph is cross-venue by design. |

## Adversarial pass (what was checked, not assumed)

- *"Does a cookie write in a Next 16 action really refresh the page?"* — Read the installed source:
  `skipPageRendering` stays true server-side (no RSC in the action response), but the header is set on cookie
  mutation and the client then runs a `RefreshAll` navigate + full prefetch eviction (C1 citations).
- *"Is iron-session's `save` actually a `cookies().set`?"* — `iron-session-v8/dist/index.js:655-665`: yes.
- *"Are the two resolvers really both called at startup?"* — `known` is undefined on the first cycle, so the
  `knownStillWarm` skip cannot apply (`useWarmNavTargets.ts:237-240`); Next queues the second action behind the
  first (`app-router-instance.js:158-167`).
- *"Is the non-iOS health check load-bearing for readiness?"* — `ready:false` is never read on that branch; only
  `versionMismatch` is, and the pull duplicates it (C5).
- *Not verified (needs runtime):* production todo counts per tenant (sizes C7-C11's CPU cost); the Amplify
  build's value of `NEXT_PUBLIC_REPLICACHE_CHEAP_POLL`; whether `selectReachableVenueIDs` is cache-served (affects
  C3/C4 RT count by ±1).
