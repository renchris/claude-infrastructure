# A4 — Replicache PULL path: round-trip census (2026-09-23)

Repo: `reso-latency-ro` @ `b2eea41b3` (read-only). Axis: `POST /api/replicache-pull` end to end, the C-003 gate,
the cheap watermark poll, and client pull frequency. "RT" = one sequential HTTPS POST to Turso (Hrana v2 over HTTP;
concurrent statements inside one interactive tx coalesce into one POST, measured in `26f580187`). Each RT costs
~53-263 ms p50 per statement (LAX/Oregon, `48d7ff7e9` table) **and** is an independent ticket on the ~1 s
server-side stall whose hazard attaches to Hrana *stream open* (`docs/sync/README.md:339-350`).

## Findings (ranked by latency saved × path frequency)

| id | where | path / frequency | seq RTs now → after | change (one line) | risk | conf |
|---|---|---|---|---|---|---|
| F1 | `pullActions.ts:557-606` | every gated pull (prod: gate ON) | no-op 3→2 in-tx; fast/change path −2 | issue ownership ∥ watermark (∥ cheap L1 scans) in the tx's first POST instead of three awaits | low (reads only before check) | 90% |
| F2 | `pullActions.ts:858-863`, `authContext.ts:257-298` | every pull | −1 to −3 (auth level, promoter tail, CVR db read) | run auth reads + CVR read INSIDE the pull tx, in the same first POST as F1 | medium (auth ordering, instrumentation) | 80% |
| F3 | `route.ts:59`, `session.ts:162-192` | every pull | −1 | fold the `credentials_version` revocation read into the F2 first POST (select it with the user row) | medium-high (Critical Rule 5 wording; needs security sign-off) | 70% |
| F7 | `watermark-poll.ts:52`, `Dockerfile:79-134`, `sync-watermark/route.ts` | ~92% of all pulls (interval) | 5-7 → 2 per client-minute | turn `NEXT_PUBLIC_REPLICACHE_CHEAP_POLL` on — **after** adding `X-Deploy-SHA` to the probe (prereq) | medium (deploy detection, idle slide) | 75% |
| F5 | `tableServiceActions.ts:1273-1291`, `:140-180`, `:1095-1125` | every fast-path + change-path pull | scan windows 3(4)→1: −2 (−3) | L5: express scope-venue set, active-event set, floor-plan version fallback as SQL subqueries so all 21 meta scans are one window | medium (authz predicate equivalence) | 80% |
| F6 | `watermark-poll.ts:161-210`, `create-replicache-context.tsx:1250-1256,576` | cheap poll ON: 1 redundant pull per write-containing minute per client + 1 per poller `start()` | redundant full pull (5-7 RT) → 0 | feed each successful pull's cookie `{lc,oob}` into the poller's `lastSeen`; baseline from cookie, not a pull | low (monotonic watermark) | 85% |
| F8 | `sync-watermark/route.ts:31-55`, `sync-cursor.ts:67-80` | every probe (1/client/60 s when F7 on) | 2 levels / 3 POSTs → 1 POST | one scalar-subquery statement: credentials_version + max(mutation_log.id) + sync_cursor.seq | low-medium | 80% |
| F11 | `create-replicache-context.tsx:1750-1803` | every non-iOS wake (visibility→visible) | +1 client→origin RT before the pull → 0 | drop the awaited `/api/health` pre-check on non-iOS; the pull response already carries `X-Deploy-SHA` (`:632-648`) | low | 75% |
| F10 | `venue-authz.ts:218-233` via `authContext.ts:293` | every promoter pull in a grandfather (scoping-off) tenant; also 4 seed paths | +1 → 0 | skip `promoter_event` read when `!userScoped.scopingEnabled` (every consumer gates on it) | low | 85% |
| F9 | `create-replicache-context.tsx:437-440,604`, `session.ts:205-213` | ≤1 extra request per client-minute (29/30 server no-ops) | +1 HTTP req +1 DB RT (off critical path) → 0 | slide the session inside the pull route (it already holds the session) and set the cookie on the pull response | low | 70% |
| F12 | `pullActions.ts:782-787` | cold first pull / scope change (op:clear) | −1 (fetch window) + id upload | when `previousCVR === undefined` fetch full rows via the search predicate as a subquery, skip meta→ids→fetch | medium | 55% |
| F13 | `tableServiceActions.ts:1220-1235`, `assembleConfig.ts:67-101` | change path when floor-plan config version moves, multi-venue tenants | 0 RT; 6×(N−1) redundant whole-table SELECTs | hoist the 6 venue-independent config tables out of the per-venue loop | low | 80% |
| F14 | `recencyWindow.ts:36-110` | windowed first pull (flag `REPLICACHE_PULL_WINDOW`, OFF) | 5 levels → 1-2 | run tableMap ∥ reservations; subquery reservationGuest/section/element/canvas | low | 70% |
| F15 | `drizzle/db.ts:65-72` (`TURSO_KEEPALIVE`) | first statement(s) of every post-idle pull on Fly | ~27-199 ms per post-idle socket (measured) | operator decision: enable on Fly only (pull path is retry-safe) | ops | 60% |
| F4 | `pullActions.ts:886` | no-op pull | 2→1 (drops COMMIT) | gate check as one read `db.batch`, interactive tx only on fall-through | +1 RT on every gate MISS | conditional — see § F4 |

**Totals** (production shape: gate ON, cheap poll OFF, non-promoter, scoping-flag cached):

| pull kind | today (seq RTs) | after F1+F2+F3 | after F1+F2+F3+F5 |
|---|---|---|---|
| (a) C-003 no-op | **5** mem-hit CVR / **6** db-hit / **7** promoter+db-hit | **2** (BEGIN+everything, COMMIT) | 2 |
| fast path (watermark moved, nothing visible) | **8** mem-hit / 9 db-hit | 4 | **3** |
| (b) change path | **10** mem-hit / 11 db-hit (+1 if no `floor_plan_config_version` row, +1 promoter) | 6 | **5** (+ CVR persist after response) |
| (c) cold first pull (no cookie) | **10** | 6 | **4** (gate cannot fire ⇒ whole scan rides POST 1 via F1b) |

"After" columns assume F1 includes F1b (speculative `searchClients` + venue ids in POST 1).

The W3d test pins only the *in-tx* slice (`round-trips.test.ts:403-410`: gate ON no-op = 3, change = 10) because it
stubs `prefetchPullAuthContext` to 0 RT (`:52-66`), runs the fast path on a mem-hit CVR, and never goes through the
route's session read. The route-level counts above are what a user waits for.

## How today's counts are derived (read, not measured)

Route → `processPull`, gate ON (SSM, `.claude/rules/replicache.md:419-431`):

1. `route.ts:59` `getServerActionSession()` → `session.ts:170-174` `SELECT credentials_version FROM user WHERE id=?` — 1 RT (plain `execute`, own stream).
2. `route.ts:233` `getDBAndGroupForSessionTenant` — 0 RT (cached client, `drizzle/db.ts:295-301`).
3. `pullActions.ts:858` `prefetchPullAuthContext` level 1: user⋈promoter `.get()` ∥ `user_venue_role` ∥ scoping flag (10-min cache, `venue-authz.ts:82`) — 1 RT (2-3 concurrent POSTs/streams).
4. `authContext.ts:293` promoter tail `promoter_event` — +1 RT for `role==='promoter'` only.
5. `pullActions.ts:861` CVR read — 0 on mem-hit, 1 on miss. **Serial behind auth by design** (`:849-852`: scope key needs authContext; "cost is one extra serial round-trip").
6. tx POST 1: BEGIN + `validateAndClaimOwnership` (`:558`) — 1.
7. tx POST 2: `readSyncWatermark` (`:580`) — 1. **Awaited after ownership although independent.**
8. Gate hit → return → COMMIT — 1. Total no-op = 1+1+(0|1)+1+1+1 = **5-6** (+1 promoter).
9. Gate miss → scan: POST 3 = `searchClients` ∥ app union ∥ `resolveScopeVenueIDs` (`tableServiceActions.ts:1286`); POST 4 = `searchEvents` (`:1291`); POST 5 = 17 searches (`:1312`); +1 when the `floor_plan_config_version` row is absent (`:1111-1123` legacy fallback).
10. Fast path → COMMIT. Change path → fetch window (`:786`, 1) → `putClientGroup` (`:787`, 1, P-7 by design) → COMMIT (1). CVR persist `db.batch` runs in `after()` (`:1029`) — 0 user-visible.

---

## F1 — pipeline ownership, watermark and cheap L1 scans into the tx's first POST

`pullForChanges` awaits `validateAndClaimOwnership` (`pullActions.ts:558`) and only then `readSyncWatermark`
(`:580`); the scans wait on both. None depends on another's *value* except that nothing may be **returned** before
ownership is validated. Change:

```ts
const [baseClientGroupRecord, watermark] = await Promise.all([
  validateAndClaimOwnership(tx, clientGroupID, userID),
  cursorGateEnabled ? readSyncWatermark(tx) : Promise.resolve(undefined),
])
```

Extension (F1b): when the gate *cannot* fire — `previousCVR === undefined` or `!isCursorCookie(cookie)` (cold pull,
db-miss, pre-gate cookie) — also start `searchClients` and `resolveScopeVenueIDs` in that same POST. When it *can*
fire, speculatively issuing only the two cheap statements (client rows for one group; venue ids) is still net
positive because the gate misses on 66-83% of pulls (`docs/sync/README.md:333-338`); keep the app union (all
lists/shares/items for admins) out of the speculative set.

- RTs: gate-ON no-op 3→2 in-tx (route total 5→4); fast/change path −2 (ownership, watermark, L1 become one POST).
- Correctness: ownership still evaluated before anything is returned or written; `ClientGroupOwnershipError` rejects
  the `Promise.all` → rollback. Legacy claim UPDATE (`sharedActions.ts:120-129`) still runs after the read, inside the
  tx. Watermark stays inside the tx snapshot (the `sync-cursor.ts:87-90` requirement).
- Regression test (fails today): `round-trips.test.ts` gate-ON arm — assert `m.rec.trips[0].tables` contains both
  `replicache_client_group` and `mutation_log`/`sync_cursor`, and `fastPathPosts` = 2 (today 3, `:406`).

## F2 — move the pre-tx prologue (auth + CVR) into that first POST

The docs already name this as the open lever ("folding the pre-transaction reads INTO the pull transaction (4 stream
opens → 1)", `docs/sync/README.md:348-350`); nothing on trunk does it. Concretely:

- Add a tx-scoped `loadPullAuthContextTx(tx, userID)` (same statements as `authContext.ts:272-293`, typed on
  `Querier`/`Transaction`). `.get()` is fine inside an interactive tx — the 🚨 at `authContext.ts:268-270` is about
  `db.batch` only. Keep the `if (!row) throw` guard.
- Break the CVR→auth dependency: read `WHERE client_group_id=? AND "order"=?` (PK prefix `(cg, scope_key, order)`,
  `drizzle/schema.ts:231`; rows per group are bounded by the 1-day TTL) and pick the row whose `scope_key` equals
  `cvrScopeKey(authContext)` in JS; no match ⇒ `db-miss` exactly as today. (Alternative: stamp a short scope-key hash
  on the cookie and do an exact PK lookup; a forged value only selects a CVR of the caller's own validated group and
  is re-checked against the computed key.)
- Promoter tail: fold into the same POST with a subquery keyed on username
  (`promoter_event.promoter_id = (SELECT p.id FROM promoter p JOIN user u ON p.user_id=u.id WHERE u.username=? ORDER BY p.id LIMIT 1)`)
  and add the same `ORDER BY p.id` to the user⋈promoter read so both pick the same promoter
  (`authContext.ts:186-192` notes the join is non-unique). Or combine with F10.
- The in-memory CVR cache hit still skips the CVR statement.
- Knock-on: `pullTimings.authUserMs/authVenueMs/cvrReadMs` collapse into the first POST; `pullUnaccountedMs`
  (`route.ts:427-430`) must be re-derived or it goes permanently negative-clamped.
- Bonus: the auth reads become covered by `runInResilientTransaction`'s transient retry (today an auth-read stream
  reset fails the pull outright).
- RTs: −1 (auth level) −1 (db-hit CVR) −1 (promoter). Stream opens per pull 4-6 → 2 (session + tx).
- Risk: medium. The auth reads now run under the pull's tx (deferred BEGIN, reads take no RESERVED lock, P-7
  unaffected). Seven other callers of `prefetchPullAuthContext` are untouched.
- Regression test (fails today): un-mock `../authContext` in a new `round-trips.test.ts` case, reset the CVR memory
  cache (needs a `resetCVRMemoryCacheForTests` export), persist a CVR, pull with its cookie; assert the FIRST recorded
  trip contains `user`, `user_venue_role`, `replicache_cvr`, `replicache_client_group` together and total trips ≤ 2 on
  the no-op. Today `user` and `replicache_client_group` are in different trips.

## F3 — fold the revocation check into the same POST

`session.ts:170-174` reads `user.credentials_version` by `user.id`; 20 ms later `authContext.ts:273-280` reads the
same `user` row by `username`. Same DB (`session.ts:168-169` uses the session tenant, as does the route). Add
`credentialsVersion` and `id` to the F2 user read, have the pull route call an unvalidated unseal
(`getSessionCached`-equivalent), and in JS: row absent → 401; `row.id !== session.user.id` → 401;
`(session.user.credentialsVersion ?? 0) < row.credentialsVersion` → 401 (identical predicates, `session.ts:175-183`).
Nothing is returned or written before the check.

- RTs: −1 on every pull; no-op reaches the documented floor of 2 (`docs/sync/README.md:356`).
- Risk: medium-high, needs security sign-off. (1) Critical Rule 5 / `api-security.md:13` says validate the session
  before touching a tenant DB; here other reads share the POST with the validating read. (2) Semantics shift from
  fail-OPEN on a read error (`session.ts:184-186`) to "pull fails, Replicache retries" — stricter, not looser.
  (3) Must be pull-route-only; the validated default elsewhere stays.
- Regression test (fails today): route test with a recording client; assert the statement selecting
  `credentials_version` shares a POST with the `user_venue_role` read, and a revoked session (column bumped) still
  returns 401 with zero entity/CVR/ownership reads *acted upon* (no `replicache_client_group` write, no 200).

## F4 — (conditional) a no-op with no COMMIT

After F1-F3 the no-op is BEGIN+reads, then COMMIT. A read `db.batch` (`BEGIN TRANSACTION READONLY`…`COMMIT` in one
request, `docs/sync/README.md:356-358`) makes the no-op 1 RT, but every gate **miss** then pays the batch *plus* the
interactive tx (+1). Gate hit rate is 17-34% today (`docs/sync/README.md:333-338`) ⇒ net negative now. Revisit only
after F7+F6, when pulls that reach the server are mostly delta-driven and the hit rate is re-measured. Must use array
results (`.get()`-in-batch inverts guards, `26f580187`).

## F5 — L5: one scan window instead of three (four)

`searchTableServiceEntities` has two dependency levels before the 17-way `Promise.all`
(`tableServiceActions.ts:1286`, `:1291`) plus the legacy fallback (`:1117`). All three are expressible in SQL:

- scope venues, grandfather/admin: `venue_id IN (SELECT id FROM venue UNION ALL SELECT 'default' WHERE NOT EXISTS (SELECT 1 FROM venue))`
  (reproduces the empty-table fallback, `:143-178`); scoped non-admin: the JS set as today (0 RT already).
- active events: `event_id IN (SELECT id FROM event WHERE status <> 'archived' AND venue_id IN (<scope>) [AND id IN (<promoterEventIDs>)])`
  — the 5 event-inherited searches (reservation, reservationGuest, bottleOrder, bottleOrderItem, eventInsight) already
  use nested subqueries (`:357-371`, `:869-885`), so this is the same pattern one level up.
- floor-plan version: `COALESCE((SELECT version FROM floor_plan_config_version LIMIT 1), (SELECT row_version FROM tenant_floor_plan_config LIMIT 1))`;
  per-venue expansion uses venue ids from `venueMeta` (same window) with the `'default'` fallback.
- `venue-table-empty-fallback` warning derivable from `venueMeta.length === 0` under grandfather/admin.
- RTs: −2 on every fast-path and change-path pull (−3 where the version row is absent). With F1b, the entire scan can
  ride the first POST on pulls where the gate cannot fire.
- Risk: the scope predicate must stay single-sourced — build the subquery from the same function that today returns
  the id list, so the authz predicate cannot fork (the seed-mirror rule, `.claude/rules/replicache.md:114`).
  `pullActions.test.ts` + `tableServiceActions-scope.test.ts` pin visibility.
- Regression test (fails today): gate-OFF arm `changePathPosts` 9 → 6 and `trips.slice(1, 5)` scan phase length 4 → 1
  (`round-trips.test.ts:452-469`); plus an empty-`venue` fixture asserting the `'default'` fallback still syncs events.

## F7 — the cheap poll is written but (almost certainly) not on

`watermark-poll.ts:52` reads `NEXT_PUBLIC_REPLICACHE_CHEAP_POLL` at build time; default off. No repo artifact turns it
on (`git grep` finds only `docs/sync/README.md:301` "default off"); the Fly build passes only `GIT_SHA` and the VAPID
secret (`Dockerfile:82-83,131-134`, `scripts/release-fly.sh:514-515`). Only an untracked `.env` in the Docker context
(`.dockerignore:16-17` excludes `.env*.local` only) or an Amplify branch var could enable it — verify by grepping a
served client chunk before acting. Meanwhile 91.9% of pulls are interval pulls and 99.1% of those are no-ops
(`902c9fac1`): each costs 5-7 seq RTs server-side; the probe costs 2 (1 after F8).

**Prerequisites before flipping (both found in this pass):**
1. **Deploy detection regresses.** The 60 s interval pull is the stale-bundle safety net
   (`.claude/rules/replicache.md:309-312`); the pull puller reloads on `X-Deploy-SHA` (`create-replicache-context.tsx:632-648`).
   The probe route sets no such header (`sync-watermark/route.ts:48-52`) and `fetchSyncWatermark` reads none
   (`watermark-poll.ts:77-95`). Add `X-Deploy-SHA` to the probe and the same `resolveVersionMismatch` check.
2. **Idle sessions stop sliding.** The slide rides only on 200 pulls (`create-replicache-context.tsx:604`); with the
   poll on, an idle-but-open client pulls only on deltas, so a quiet 12 h shift can hard-expire. Slide from the probe
   route too (or F9).
- Test (fails today): `sync-watermark-route.test.ts` asserts the response carries `X-Deploy-SHA`; a poller test asserts a
  mismatching SHA triggers reload.

## F6 — the poller never learns what pulls already fetched

`lastSeen` is written only from probe results (`watermark-poll.ts:188-206`). Every write reaches the client by poke →
pull (cookie now stamped with the new `{lc,oob}`, `pullActions.ts:932`), yet the next probe compares against the
*old* `lastSeen`, sees a delta and fires a second, redundant pull (a C-003 no-op at 5-7 RTs). Also `start()` always
baselines with a real pull (`:180-187`, `:212-219`), and `start()` runs on every Pusher `connected`
(`create-replicache-context.tsx:1276-1279`) — so page load = constructor pull + baseline pull, and every reconnect
adds one.

Change: `poller.observePulled(w)` called from the puller on each 200 (the raw cookie is already read at
`create-replicache-context.tsx:576-582`); `lastSeen = w` when `w` ≥ `lastSeen` component-wise. Seed the baseline from
the last pulled cookie instead of a pull; if no pull has completed yet, defer the baseline to the first pull's
completion instead of issuing another. Sound for the same reason the module's own invariant is
(`watermark-poll.ts:145-150`): the cookie watermark was read in the same tx snapshot as the scan that produced the
patch, so every write ≤ it is delivered; both components are monotonic (`sync-cursor.ts:112-125`).
- Test (fails today): after `observePulled({lc:5,oob:2})`, a probe returning `{5,2}` yields 0 `triggerPull` calls;
  `start()` with a known pulled watermark and an equal probe yields 0 pulls (today: 1 baseline pull).

## F8 — the probe route is 2 levels / 3 POSTs

`GET /api/sync-watermark`: session revocation SELECT (1) then `readSyncWatermarkNoTx` = two concurrent plain
`execute`s (2 POSTs, 2 streams, `sync-cursor.ts:67-80`). One statement does it:
`SELECT (SELECT credentials_version FROM user WHERE id=?) cv, (SELECT max(id) FROM mutation_log) lc, (SELECT seq FROM sync_cursor WHERE id='default') oob`
— `cv` NULL → 401, stale → 401, else return `{lc,oob}`. `max(id)` on the INTEGER PK is a b-tree edge read.
- Risk: same Rule-5 framing as F3 (values are returned only after the check); monotonic stale-low argument unchanged
  (`sync-cursor.ts:98-125`).
- Test (fails today): route test with the recording client: authorized probe = 1 POST (today 3 across 2 levels).

## F11 — non-iOS wake pays a health check before the pull

`create-replicache-context.tsx:1763` awaits `waitForHTTPReady(1)` (`/api/health`, no DB) then pulls (`:1803`). The
comment says "non-blocking for pull" but it is awaited. Non-iOS has no stuck-socket issue (`:1751-1754`) and the pull
response already performs the same version check (`:632-648`). Drop the pre-check on non-iOS (keep iOS, where it is a
readiness probe). Saves one client→origin RTT on every desktop/Android foreground — the moment the user is waiting.
- Test (fails today): visibility handler test, non-iOS UA: `fetch('/api/health')` is not called before the pull.

## F10 — promoter tail read even when nothing will use it

`completeVenueAuthFields` reads `promoter_event` whenever `role==='promoter'` (`venue-authz.ts:224-226`). Every
consumer of `assignedEventIDs` from this context gates on `scopingEnabled`: pull `pullActions.ts:619-622`, guests
`initialData.ts:317`, recap `recapSeedActions.ts:90-93`, home `homeStateActions.ts:227,494`, bottle seed `seed.ts:155,203`.
Grandfather (scoping off) is "the default for all prod tenants" (`tableServiceActions.ts:133`). Gate the read on
`base.scopingEnabled` (known at that point). −1 RT per promoter pull and per promoter seed render.
(Push sibling: `batchPrefetch.ts:1588` has the same serial tail; out of axis.)
- Test (fails today): `pull-auth-context.test.ts` — promoter, scoping off → zero `promoter_event` statements.

## F9 — the session slide is a separate request after pulls

Every 200 pull calls `slideSessionThrottled()` (`create-replicache-context.tsx:604`, 60 s client throttle, `:437`) →
server action `slideSessionIfStale` → `getServerActionSession()` → revocation SELECT (1 DB RT) → 29 of 30 return
without saving (`session.ts:205-213`, 30-min interval). The pull route already holds the validated session: call the
same `shouldSlideSession` there and `session.save()` onto the pull response. Removes up to one HTTP request + one DB
RT + (on Amplify) a Lambda invocation per client-minute; off the critical path, so this is load not latency.
- Test (fails today): route test with a stale `lastSlideTimestamp` → response carries `Set-Cookie`; puller test → no
  `slideSessionIfStale` call.

## F12 — cold first pull does meta → ids → fetch

With no base CVR every visible row is a put, yet the pull scans `(id,row_version)` then ships every id back in
`inArray` fetches (`pullActions.ts:782-786`). When `previousCVR === undefined`, fetch full rows with
`inArray(table.id, <search subquery>)` (the search as an un-executed subquery keeps one predicate source) and build
`nextCVR` from the returned `rowVersion` (every `getX` select includes it). −1 RT on cold/scope-change pulls and no id
upload. Only 55% because first pulls are small (≤226 rows, `docs/sync/README.md:388-392`) and the fold touches all
21 fetchers; do it after F5, which builds the same subqueries.

## F13 — floor-plan config assembled N times

`getTenantFloorPlanConfigs` runs `assembleFloorPlanConfig` per venue (`tableServiceActions.ts:1229-1234`); 6 of its 8
SELECTs are venue-independent full-table reads (`assembleConfig.ts:82-89`: preset tiers, colors, display modes,
section config, flags, version). Same window (0 RT) but 6×(N−1) redundant statements and rows on every config-version
bump, which re-syncs every venue together (`:1103-1107`). Read the 6 once, the 2 venue-scoped per venue.

## F14 — windowed first pull is 5 serial levels (flag OFF)

`computeRecencyWindow`: events → reservations → reservation guests → table maps → {sections, elements, canvases}
(`recencyWindow.ts:36-110`). Table maps depend only on the event rows yet wait behind reservations; reservation guests
and the three table-map children are subquery-able. 5 → 2 levels. Only matters if `REPLICACHE_PULL_WINDOW` is turned on
(`.claude/rules/replicache.md:511`), where these levels would otherwise erase the window's benefit.

## F15 — keep-alive (existing flag, operator's call)

Node's fetch drops Turso sockets after ~4 s idle (`docs/infra-deploy/learnings.md:2372-2376`), so every 60 s pull
opens fresh TCP+TLS on its first statement(s) (auth level = 2-3 parallel sockets). `TURSO_KEEPALIVE` exists, default
off (`48d7ff7e9`: LAX 80→53 ms, Oregon 263→64 ms per post-idle statement). The pull is retry-safe on a dead socket
(`runInResilientTransaction`, plus Replicache re-pull on 5xx), and Fly has no freeze/thaw. Not a code change;
listed so the pull's share of the argument is on record. Not a fix for the ~1 s stall (refuted, `6b9032629`).

---

## Pull frequency (client)

| trigger | site | notes |
|---|---|---|
| interval 60 s | Replicache watchdog = `pullInterval` | 91.9% of pulls, 99.1% no-op (`902c9fac1`). F7. |
| poke | `listenActions.ts:336` coalesced, ≤2 per burst | necessary; `rep.pull()` (not `now`) — see rejected R1. |
| poller baseline / delta | `watermark-poll.ts` | only if F7 on; redundant without F6. |
| visibility / online wake | `create-replicache-context.tsx:1705,1803` | preceded by `/api/health` (F11). |
| initial | Replicache constructor | + poller baseline when F7 on (F6). |
| backfill | `:1042-1065` | only with `REPLICACHE_PULL_WINDOW`. |
| aggressive 15-20 s | Pusher down | real pulls by design (`watermark-poll.ts:20-24`). |

Tenant-global watermark: any write in the tenant moves `{lc,oob}` for every client, so the gate hits only 17-34%
(`docs/sync/README.md:333-338`) and, with F7, every write in any venue triggers a scan pull on every client. A
per-scope watermark would fix that but needs triggers that resolve venue per table (21 tables) — deferred, not proposed.

## Rejected candidates (do not redo)

- **R1 poke → `pull({now:true})`.** Replicache 15.3.0's pull loop has `debounceDelay=0` and `minDelayMs=30`
  (`replicache/out/chunk-B3SOU6MT.js`: `Yt=class …{debounceDelay=0`, `Ro=30`); a non-`now` send only adds
  `waitForVisible()`. Gain ≤30 ms; cost = pulls from hidden tabs. The docs line flagging it (`docs/sync/README.md:369-371`) overstates it.
- **R2 `putClientGroup` into the fetch window.** P-7: would take the write lock across the read phase (`pullActions.ts:774-781`).
- **R3 CVR persist inside the pull tx / earlier.** Already post-response via `after()` (`:1029`), 0 user-visible RT.
- **R4 scan and fetch in separate snapshots** (read batch then write tx). Violates the one-snapshot invariant
  (`resilient-transaction.ts:4-8`); tearing is self-healing but the rule is stated as MUST.
- **R5 `db.batch` for the auth prologue.** `.get()` in a batch returns `[]` and inverts the no-user guard
  (`authContext.ts:268-270`); F2 uses the tx's pipelining instead.
- **R6 row_version diff in SQL via `json_each(cvr)`.** Would fold scan+fetch (−1 RT) but ships the whole base CVR
  per pull and needs a changed-row projection for 21 serializers; blast radius ≫ one RT. Revisit after F5/F12.
- **R7 concurrent body parse + session.** Body is <1 KB; `bodyParseMs` ≈ 0.
- **R8 durable limiter peek** (`route.ts:156-157`) — flag off; if enabled, run it concurrently with the auth level.
- **R9 watermark as one statement inside the tx.** Already one POST (pipelined `Promise.all`); only the probe (F8) gains.
- **R10 indexes.** Every hot predicate is indexed: `user_username_unique`, `idx_uvr_user`, `idx_promoter_user_id`,
  `promoter_event` PK `(promoter_id, event_id)`, `idx_replicache_client_group_version`, CVR PK, `sync_cursor` PK,
  `idx_event_venue_id`, `idx_reservation_event_id`, `idx_table_map_venue_id`, `idx_section_table_map_id`,
  `idx_floor_plan_*_table_map_id`, `idx_guest_profile_version`/`_promoter_version`, `idx_item_list_version`
  (`lib/generated/schema-ddl.ts`). No missing index found.
- **R11 over-fetched columns in `getX`.** All fetchers use explicit column lists matching the wire type
  (e.g. `tableServiceActions.ts:608-658`); the only whole-table reads are F13's.
- **R12 keep-alive as the stall fix.** Refuted (`6b9032629`); F15 is the per-statement saving only.
- **R13 embedded replica / payload-in-poke.** Separate program (`ab242c5cc`) / refuted (`docs/sync/README.md:373-381`).

## Adversarial pass (what a hostile reviewer would say)

1. *"Your 'today' counts are derived, not measured."* True. `postsIssued` (`lib/db-instrumentation.ts:191-205`)
   counts one per in-tx `execute` and omits BEGIN/COMMIT, so it measures neither levels nor COMMIT, and the W3d test
   stubs the prologue. The regression tests above are also the missing instrument: each asserts trip *membership*
   through `recordingLibsqlClient`/`withTransactionRecording`, not a statement count.
2. *"Pipelining ownership with other reads breaks the TOCTOU fix."* Checked: TOCTOU is about the ownership read and
   the `putClientGroup` write sharing one tx (`sharedActions.ts:74-76`); F1/F2 keep both in the tx and gate every
   return/write on the result. The claim UPDATE stays sequential after its read.
3. *"The cheap poll might already be on."* Could not be disproved from the repo (untracked `.env` in the Docker
   context, Amplify console `NEXT_PUBLIC_*` do reach the bundle, `.claude/rules/replicache.md:417`). F7 says verify
   from a served chunk first; F6 and the two prerequisites stand either way.
4. *"Moving auth into the tx lengthens the tx."* By one POST that it replaces outside; reads under deferred BEGIN take
   no write lock, so P-7's lock window is unchanged.

## Blockers / uncertainties

- No live measurement possible from this worktree (read-only, no network). Latency per RT from `48d7ff7e9`; mix
  (17-34% gate hits, 91.9% interval) from `docs/sync/README.md` / `902c9fac1`.
- F3/F8 need a security ruling on Critical Rule 5's wording for a same-POST validating read.
- Production state of `NEXT_PUBLIC_REPLICACHE_CHEAP_POLL` unknown (F7).
