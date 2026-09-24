# A5 — Replicache PUSH path: DB round-trip census

Read-only census of reso at `b2eea41b3` (worktree `reso-latency-ro`). Scope: `src/app/api/replicache-push/route.ts`,
`pushActionsBatch.ts`, `batchPrefetch.ts` (the push's only read phase), `operationBuilder*.ts`, `validators.ts`,
`tableServiceActions.ts`, `todoActions.ts`, the lead-12 watermark (`754a4693d`), the `mutation_log` append, and
the post-response poke / notification / guest-message work.

Unit of cost: **one sequential HTTPS POST to Turso**, i.e. one Hrana pipeline request. The per-POST stall hazard is
already on record (a ~0.9 s bounded stall attaches per POST, `e7fad21ba`, `drizzle/db.ts:280-282`), so removing a
sequential POST removes both its RTT and its stall ticket.

## Findings (ranked by latency saved × path frequency)

| id | where | path / heat | sequential POSTs now → after | change (short) | risk | conf |
|---|---|---|---|---|---|---|
| F1 | `route.ts:167` → `durable-limiter.ts:143` | every push (prod only) | limiter 2 → 1 (push 7 → 6) | pass `{ db }` to `checkPushRateLimitDurable` so it stops re-entering the session | none (same tenant handle the push already uses) | 90% |
| F2 | `route.ts:137,167,234` + `batchPrefetch.ts:696` | every push | prologue 3 waves → 1 wave (6 → 4) | fold the revocation check into the prefetch `userQuery`; run the limiter UPSERT at the same time as the prefetch | **auth**: revoked → 401 before any write; absent user row → 401, not 500 | A 80% / B 65% |
| F3 | `pushActionsBatch.ts:790` / `sharedActions.ts:92-160` | every push with ≥1 new mutation | tx 3 → 2 (processPushBatch 4 → 3) | put the ownership SELECT (and the legacy claim UPDATE) first in the apply window, using the lead-12 re-assert pattern; add `user_id` to the prefetch client-group read | ownership/TOCTOU; enqueue order | 85% |
| F4 | same tx | every push | tx 2 → 1 (processPushBatch 3 → 2) | send the whole tx as one `db.batch`, with SQL guard statements in place of the JS asserts | error mapping; needs `LibsqlBatchError.statementIndex` | 50% |
| F5 | `batchPrefetch.ts:1588-1590` | every push by a user with the global `promoter` role | prefetch 2 → 1 | move `getPromoterAssignedEventIDs` into the batch as a username-keyed join | none (same predicate) | 85% |
| F6 | `pushActionsBatch.ts:753-757,772` | pushes where every mutation is idempotency-skipped (503/abort retries, reconnect replays, lead-12 losers) | tx 3 → 0 | skip the tx when no mutation advanced; answer ownership from the prefetched `user_id` | ownership 403 must be kept; `last_modified` activity signal | 75% |
| F7 | `pushActionsBatch.ts:377,440-461,540-551` | Option C fallback (rare; `BatchFallbackTriggered`) | per mutation 4+N_ops → 2; plus 1 re-prefetch | pipeline each mutation's tx the way Option D's is (one window + COMMIT); fold the ownership read | ordering (already proven for D) | 80% |
| F8 | `notificationDispatch.ts:223-247,298-360,409-440` | post-response, on approval pushes, plus the Fly sweeper; sets approval-notification latency | ≈11 → ≈5 | claim with one `UPDATE … RETURNING`; batch the per-row reads; write delivery and `markSent` together | claim CAS must stay single-winner | 75% |
| F9 | `route.ts:336-341`, `venue-id-cache.ts:21-29` | every list/todo push on a cold venue-cache (per container, 60 s) | poke path 2 → 1 before the Soketi trigger | put `SELECT id FROM venue` into the prefetch batch when the cache is cold | none (it is a hint) | 70% |
| F10 | `batchPrefetch.ts:729-738` | every list/todo push | same POST, **unbounded payload** | narrow the read of every row in `list` to the referenced lists (`IN` + item/share subqueries) | authz: the lookup set must be complete | 65% |
| F11 | `batchPrefetch.ts:847-873` | every createReservation, updateReservation(table/party), and close-event push | same POST, tenant-wide payload | scope sections and `table` elements to the maps of the referenced tables and events | error-code drift, mapless events | 55% |
| F12 | `route.ts:193,238,421,467` | every push (measurement) | n/a | start `t0` at the top of the handler, as the pull route does (`replicache-pull/route.ts:36-43`) | none | 95% |
| F13 | `todoActions.ts:72-83,225-253,391-407` (client) | bulk list edits, shares | 2+ server pushes → 1 | bulk mutators (`updateMultipleTodos`, `createShares`), the same way `createMultipleTodos` and `deleteMultipleTodos` already work | ordering (keep in-mutator order) | 70% |
| F14 | `batchPrefetch.ts:1125` | the first push on a handle every 10 min (cold) | 2 concurrent POSTs → 1 | register the scoping-flag read in the batch when the memo is cold | none | 70% |
| F15 | `route.ts:408-411`, `guest-message-outbox.ts:507-567` | every push, **latent** (inert until W3 adds a transport) | 0 today → 4 after W3 → 1–2 | gate the call, and use a single-statement claim before W3 lands | none today | 80% |

**Steady-state count today** (prod, warm scoping flag, non-promoter, ≥1 new mutation): **7 sequential POSTs per
push, whatever the batch size.**
1. session revocation SELECT (`session.ts:167-175`),
2. the same SELECT again, inside the limiter (F1),
3. the limiter UPSERT … RETURNING,
4. the prefetch `db.batch`,
5. BEGIN + ownership SELECT (awaited on its own),
6. the apply window (watermark re-assert + all ops + `mutation_log` + outbox),
7. COMMIT.

For a promoter, add 1 (F5). Steps 2+3 are capped by the limiter's 50 ms `withTimeout` (`durable-limiter.ts:65,141`).
The 4 POSTs inside `processPushBatch` are pinned by `round-trips.test.ts:293-315`. The route prologue (1–3) is
covered by no test, because `route.test.ts:22-23` mocks both the session and the limiter.

**After F1+F2+F3: 3 POSTs. After F4 as well: 2.** Everything after the response (poke, drain) is extra.

## F1 — the limiter re-enters the session and pays the revocation SELECT a second time

- `route.ts:167` calls `checkPushRateLimitDurable(userID)` with no `db`. `durable-limiter.ts:143` then runs
  `opts?.db ?? await getDB()` → `getConnectionParams` (`drizzle/db.ts:195`, a `cache()`) → `getSubdomainAndGroup`
  (`tenantContext.ts:42`) → `getTenantFromSession` (`cookieActions.ts:23-26`) → `getServerActionSession` →
  `getValidatedSessionCached` (`session.ts:162-192`). That last function issues
  `SELECT credentials_version FROM user WHERE id=?`.
- `cache()` passes calls straight through inside a Route Handler on Next 16.3. `26f580187` established this for the
  identical chain, and `drizzle/db.ts:272-293` documents it. So the SELECT that `route.ts:137` already paid is paid
  again, serially, before the UPSERT. `26f580187` fixed `getDBAndGroup` on this route but left the limiter's own
  `getDB()` in place.
- Second-order cost: both round trips sit inside the 50 ms fail-open budget. Whenever the two together exceed
  50 ms, the push limiter **fails open**. Its protection goes dark exactly when Turso is slow, and the route still
  waits the full 50 ms for the timeout.
- **Change:** move `getDBAndGroupForSessionTenant(session.tenant)` (no network I/O: `getNamedDB` only resolves a pooled
  client, `db.ts:243-269`) above the limiter, then call `checkPushRateLimitDurable(userID, { db })`. The
  `DurableCheckOptions.db` seam already exists (`durable-limiter.ts:44-47`); the notification drainer uses it.
- **Regression test (fails today):** in `route.test.ts`, turn the limiter mock into a `vi.fn` and assert
  `toHaveBeenCalledWith('staff1', expect.objectContaining({ db: expect.anything() }))`. Stronger variant: under
  `NODE_ENV=production` with the `recordingLibsqlClient`, count statements that touch `credentials_version` on one
  push and assert 1 (today 2).
- Same pattern outside this axis: `peekDurableLimit` (`durable-limiter.ts:225`) and every other
  `createDurableLimiter` caller in a route handler (`api-route-limiters.ts:50-105`, `invite-limiter.ts`). Flag
  these for the pull and auth axes.

## F2 — the prologue is three serial waves that depend only on the sealed cookie

Today: session SELECT → limiter UPSERT → prefetch batch, each awaited in turn. All three need only
`session.user` / `session.tenant`, which come from the iron-session unseal. The unseal is AES + HMAC with no
network hop.

- **F2-A (conservative, −1 POST):** keep the validated session at `route.ts:137`. Then
  `const [rate, context] = await Promise.all([checkPushRateLimitDurable(userID, { db }), batchPrefetchContext(...)])`.
  If limited, return 429 before the transaction. This needs `processPushBatch` to accept a precomputed context, or
  the route to start the prefetch through an exported helper. Trade-off: a rate-limited request still pays one
  read-only prefetch batch. The limiter protects write volume and the transaction, so that is acceptable, but it
  weakens S-6 as a read-load shield. The limiter keeps its own 50 ms fail-open budget.
- **F2-B (full, a further −1 POST):** skip the separate revocation SELECT entirely. The prefetch `userQuery`
  (`batchPrefetch.ts:696-702`) already reads this user's row by username in the same batch. Add
  `credentialsVersion: user.credentialsVersion` to its projection and apply the `session.ts:176-181` rule
  (row absent ⇒ revoked; `(sealed ?? 0) < row` ⇒ revoked) before any write.
  - Needs an exported unvalidated unseal plus the compare function from `session.ts`. Keep the rule's single source
    of truth there; `session.ts:127-160` explains why it lives at unseal.
  - Must map both outcomes to **401 before the transaction**. Today a missing user row throws a plain `Error`
    (`batchPrefetch.ts:1220-1222`). That falls through Option D's catch into the Option C fallback, and then to 500.
  - Fail-open on a read *error* disappears. A prefetch read error already fails the push (5xx → Replicache retry),
    so the revocation path becomes stricter, not weaker.
- Result: wave 1 = {prefetch batch with revocation column, limiter UPSERT} run concurrently, then the transaction.
- **Tests (fail today):** a route-level recorder test asserting ≤2 sequential POSTs before the first transaction
  POST. A revoked-session test: push with a sealed `credentialsVersion` behind the row → 401 and **zero** statements
  on the transaction stream. An absent-row test → 401, not 500.
- **Rejected sub-variant:** putting the limiter UPSERT *inside* the prefetch `db.batch`. That turns the read batch
  into a write transaction (lock contention with concurrent pushes), and a limiter failure would fail the push,
  which breaks the deliberate fail-open (`durable-limiter.ts:185-189`).

## F3 — ownership gets its own POST ahead of the apply window

- `pushActionsBatch.ts:790` `await validateAndClaimOwnership(tx, …)`. Its `getClientGroup` `.get()`
  (`sharedActions.ts:48-68`) is awaited alone, so it travels as the first transaction POST (carrying BEGIN).
  `round-trips.test.ts:307-308` names it: "the prefetch batch, the ownership read (which carries BEGIN for free),
  the apply window, and COMMIT". Its return value is unused in Option D; only its throw matters.
- The lead-12 watermark re-assert (`:796-803`, `:830-840`) already shows the pattern that removes this POST: enqueue
  the read first on the same queue, let it ride the ops' POST, and assert after `Promise.all` while the transaction
  is still open. A failed assert rolls back everything the push wrote.
- **Change:**
  1. Add `userID: replicacheClientGroup.userID` to the prefetch `clientGroupQuery` (`batchPrefetch.ts:705-712`),
     which costs no extra POST. If the prefetched owner is non-null and not this user, throw
     `ClientGroupOwnershipError` **before opening the transaction** (a 403 with zero transaction POSTs).
  2. Inside the transaction, make `applied[0]` a queued
     `SELECT user_id FROM replicache_client_group WHERE id=?`. If the prefetch saw an existing row with a NULL
     `user_id`, put the atomic claim `UPDATE … SET user_id=? WHERE id=? AND user_id IS NULL` ahead of it.
  3. After `Promise.all`, assert: no row, or `user_id === userID`; otherwise throw `ClientGroupOwnershipError`.
     The throw inside the callback rolls back.
- **Correctness:** the check stays inside the same transaction and ahead of every write in execution order, so the
  TOCTOU argument at `:774-789` still holds. `tx.run` / builders are lazy thenables. `Promise.all` subscribes in
  array order, so array order is enqueue order is execution order (proven by `round-trips.test.ts:317-326`). The
  error class is still `ClientGroupOwnershipError`, so the route's 403 (`route.ts:439-451`) and the Option D
  rethrow (`pushActionsBatch.ts:885-887`) are unchanged.
  - One bounded change: if a foreign-owned push's ops *also* hit a constraint error, `Promise.all` may reject with
    the constraint error first. Option C's own ownership read then still ends in 403.
- **Tests:** `round-trips.test.ts:310` `toBe(4)` → `toBe(3)` fails today. The existing
  `sharedActions` / ownership tests (claim, foreign owner, new group) must stay green. Add one where the prefetch saw
  the group owned by the user, but it was deleted and re-created by a foreign user before the transaction →
  ownership error and zero rows written.

## F4 — the transaction as one `db.batch` (needs SQL guards)

- After F3 the transaction is {BEGIN + guards + ops, COMMIT} = 2 POSTs. COMMIT is its own request because JS must
  inspect the guard results before committing (`roundTripStream.ts:22-24`). A libsql `db.batch` is
  BEGIN / stmts / COMMIT in **one** request and aborts and rolls back on the first failing statement.
- The JS asserts would move into statements that *error* when the invariant fails, using only existing constraints.
  Example: the primary-key collision idiom
  `INSERT INTO replicache_client (id, …) SELECT id, … FROM replicache_client WHERE id=? AND last_mutation_id <> ?`.
  It inserts nothing when the watermark is unchanged and collides on the PK when it moved. The owner guard is
  analogous.
- **Blockers / verify first:** map a guard failure back to `WatermarkMovedError` / `ClientGroupOwnershipError`
  **before** `classifyBatchError` (`pushActionsBatch.ts:895`). Otherwise a guard trip reads as
  `constraint_violation` and falls into Option C, which lead 12 forbids for a lost watermark (`:889-893`). This
  needs the failing statement index; confirm `LibsqlBatchError.statementIndex` exists in `@libsql/client ^0.18`
  (no `node_modules` in the worktree to check). Otherwise make the failure path alone do one re-read to classify.
- Value: −1 POST on every push. Take it only after F3 lands and the guard mapping is proven by tests: a
  watermark-moved batch → 503, a foreign owner → 403, and neither reaches Option C.

## F5 — the promoter event lookup is a second, serial prefetch POST

- `batchPrefetch.ts:1588-1590` awaits `getPromoterAssignedEventIDs(db, promoterID)` (`venue-authz.ts:158-168`)
  **after** the batch resolves, because `promoterID` comes from the batch's `userQuery`.
- **Change:** register in the batch
  `SELECT pe.event_id FROM promoter_event pe JOIN promoter p ON p.id = pe.promoter_id JOIN user u ON u.id = p.user_id
  WHERE u.username = ? AND u.role = 'promoter'`.
  Indexed: the `promoter_event` PK leads with `promoter_id`, and there is `idx_promoter_user_id`. Keep the JS gate
  `role === 'promoter' && promoterID`, and use the rows only when it passes, so behaviour is identical (an invalid
  role already degrades to `door_staff`, `:1227`).
- **Test (fails today):** in `round-trips.test.ts` "batchPrefetch travels as ONE round trip", seed a
  `role:'promoter'` user with a promoter row and ≥1 `promoter_event`, then assert `posts() === 1` on a warm handle
  (today 2). Also assert that `assignedEventIDs` equals the serial result (the equivalence arm already used there).

## F6 — a push whose mutations were all already applied still opens a 3-POST transaction

- Every mutation below the watermark is skipped (`pushActionsBatch.ts:698-704`), but `buildMetadataOperations`
  always emits the client-group UPSERT, plus one client UPSERT per prefetched client (`operationBuilder.ts:3454-3491`).
  So `allOperations.length > 0` (`:772`) and the transaction runs: 3 POSTs that write only `last_modified`, and a
  no-op compare-and-set UPSERT.
- Such pushes are the retry population: create-custom-pusher's 30 s abort → 503 → re-push, lead-12
  `WatermarkMovedError` retries, and the reconnect replay of mutations not yet confirmed by a pull. They cluster in
  bad-network windows, where every POST is most expensive.
- **Change:** if `processedCount === 0`, return without a transaction. Use the prefetched `user_id` (F3.1) to keep
  the 403 for a foreign group. Side effect: `replicache_client_group.last_modified` is no longer bumped by a pure
  replay. `scripts/live-event.sh:107` reads it as an activity signal, but pulls bump it too. Accept that, or keep the
  bump only when stale by more than 60 s.
- **Test (fails today):** push the same 3 mutations twice; the second push records `posts() === 1` (prefetch only),
  today 4.

## F7 — Option C fallback still runs the serial per-statement awaits W3d removed from Option D

- Per mutation (`pushActionsBatch.ts:440-461`): BEGIN+ownership (1), watermark SELECT awaited alone (1),
  `allOps.reduce(await tx.run(op))` (N_ops), `mutation_log` insert (1), COMMIT (1). That is 4+N_ops POSTs per
  mutation; a 10-mutation, 2-op push is about 80 sequential POSTs.
- The recovery transaction (`:540-551`) repeats the reduce. The fallback also re-prefetches (`:377`, +1) and inserts
  the outbox separately (`:586`, +1). The ownership read repeats per mutation: the "authorization read that repeats
  across a batch" pattern.
- **Change:** apply Option D's window per mutation. `applied = [ownerGuard(F3), watermark, ...allOps, logInsert]`,
  then `Promise.all`, then the asserts: 2 POSTs per mutation. Order is proven by the same stream model.
- Rare path (`BatchFallbackTriggered` alarm), but when it fires the push can run tens of seconds and meet the client's
  30 s abort, which turns one fallback into a 503 retry storm.
- **Test (fails today):** force a non-transient Option D failure with a 3-mutation push, then assert
  `posts() ≤ 1 + 1 + 3×2 (+1 outbox)`.

## F8 — the notification drain is about 11 serial round trips before and after the Web Push call

Post-response (`route.ts:367-390`) and on the Fly sweeper. It sets the time until an approver's phone buzzes. On
Lambda, `after()` keeps the container busy, so every post-response POST also delays the next request routed to
that container.
- Claim, `:223-247`: SELECT candidates → UPDATE claim → SELECT claimed = 3 serial. Replace with one atomic
  statement: `UPDATE notification_outbox SET status='processing', locked_by=?, locked_at=? WHERE id IN (SELECT id
  FROM notification_outbox WHERE status='pending' AND next_attempt_at<=? LIMIT 50) AND status='pending' RETURNING *`.
  It is single-winner by the same `status='pending'` CAS, and `idx_notification_outbox_pending` serves the subquery.
- Per row, `:298-360`: {event, list, user} ‖ → recipients (`getApproverUserIDs`) → {pc, bc} counts ‖ → subscriptions.
  That is 4 dependent waves, but only the subscriptions read depends on the recipients. Put the first three into one
  `db.batch` (1 POST), then subscriptions (1). The three parallel `.get()` calls also cost 3 POSTs each wave; mind
  the `.get()` → `one()` trap under `db.batch` (`batchPrefetch.ts:611-614`).
- After send, `:409-440`: the delivery insert, then `markSent`, run serially. `Promise.allSettled` both (1 wave).
  The best-effort isolation of the delivery insert is kept because they are not one transaction.
- Result ≈ 11 → 5 sequential POSTs, plus the Web Push call.
- **Test:** `notificationDispatch.test.ts` with a recording client: one approval row → assert posts ≤ 5 (today ≈ 10–11),
  plus the existing double-claimer test for the single-winner property.

## F9 — the poke waits on a venue scan for almost every guest-list push

- `firePoke` treats any batch with `affected.listIDs` as "share-graph" (`route.ts:336`). Every createTodo, updateTodo
  (check-in), and delete/restore populates `listIDs` (`operationBuilder.ts:653,738,861,989,1072`), so a door check-in
  fans out and, on a cold cache (per container, TTL 60 s, `venue-id-cache.ts:19`), runs `SELECT id FROM venue` before
  the Soketi trigger.
- **Change:** when `analysis.hasListTodoMutations` and the tenant key is cold, register the venue read in the
  prefetch batch and prime `venueIDsCache`. The poke then starts with zero DB reads.
- Low value on Fly (long-lived processes). Higher on Amplify, where containers are short-lived (60.8% of first pulls
  land cold, `docs/infra-deploy/learnings.md`, `e7fad21ba`).

## F10 / F11 — payload, not round trips: two full-table prefetch reads on hot mutations

- **F10**, `batchPrefetch.ts:729-738`: `SELECT id, owner_id, approval_required FROM list` with **no WHERE**, on every
  list/todo/share push, including every door check-in. There is one list per event and the table never shrinks, so
  this grows without bound. Consumers only call `accessibleLists.get(id)` (`operationBuilder.ts:211,783,943`).
  - Narrow to `id IN (<arg listIDs>) OR id IN (SELECT list_id FROM item WHERE id IN (<todoIDs>)) OR id IN (SELECT
    list_id FROM share WHERE id IN (<shareIDs>))`. Same statement, same POST.
  - Risk: the lookup set must cover every `.get` key. Pin it with a test that wraps `accessibleLists` in a Map
    that throws on a `.get` of an unfetched id, run across one fixture per list/todo/share mutator.
  - Measure first: `SELECT count(*) FROM list` per tenant.
- **F11**, `:847-873`: all sections and every `table` element *tenant-wide, with `properties` JSON*, on every
  createReservation, table/party updateReservation, and event close. Scope with
  `table_map_id IN (SELECT table_map_id FROM floor_plan_element WHERE id IN (<tableIDs>) UNION SELECT table_map_id
  FROM event WHERE id IN (<eventIDs>))`.
  - Keep the targeted-by-id read (`:831-842`) unconditional, so `TABLE_NOT_FOUND` and `TABLE_NOT_ON_EVENT_MAP`
    (`operationBuilder.ts:1994-2012`) keep their current codes.
  - Watch newly created events in the same batch; the close-insight filter (`:1289-1291`) already scopes to one map.
  - Measure first: `SELECT count(*), sum(length(properties)) FROM floor_plan_element WHERE element_type='table'`.

## F12 — the push's server clock starts after the prologue it should be measuring

- `t0` is declared as `0` (`route.ts:193`) and set only at `:238`, after session (`:137`), limiter (`:167`) and
  handle resolution. `X-Server-Duration-Ms` (`:421`) and the `push` metric's `durationMs` (`:467`) therefore leave out
  every round trip F1 and F2 remove. The client then books that time as `networkLatencyMs`
  (`create-custom-pusher.ts`), the same misattribution the pull route fixed (I0, `replicache-pull/route.ts:36-43`).
- Also, a throw before `:238` (for example a bad body at `:224`) logs `durationMs = Date.now() - 0`, which is epoch
  milliseconds.
- **Change:** `const t0 = Date.now()` as the first line of `POST`. Land this **before** F1 and F2 so their saving is
  visible.
- **Test:** with a 30 ms delay on the mocked session, `X-Server-Duration-Ms ≥ 30`. Today it is about 0.

## F13 — client loops split one user action into several pushes

- `handleUpdateTodos`, `handleCompleteTodos`, `handleNewShares` and `handleDeleteShares` (`todoActions.ts:72-83,
  225-253,391-407`) each await N `rep.mutate` calls, about 8 ms each (`.claude/rules/replicache.md:292`).
- Replicache's `pushDelay` is 10 ms with `maxConnections: 1` (`operationBuilder.ts:1018-1020`). The first push
  leaves carrying 1–2 mutations, and the rest wait for it to return (about 7 POSTs server-side), then pay their own
  push. So N ≥ 3 almost always costs 2 pushes, and 2× the prologue.
- **Change:** bulk mutators that apply their items in order inside one mutator, like the existing
  `createMultipleTodos` and `deleteMultipleTodos`. Do not use unawaited mutates: `.claude/rules/replicache.md:274-288`
  forbids them.
- Server prefetch analysis handles multi-item args already for the existing bulk mutators.

## F14 / F15 — small or latent

- **F14:** `getScopingFlag(db)` (`batchPrefetch.ts:1125`, `venue-authz.ts:100-112`) is a separate POST running beside
  the batch when the per-handle memo (TTL 10 min) is cold. That is not an extra serial wave, but it is an extra stall
  ticket, and an extra TLS connection on a cold Oregon container (h1-only, `a5bb341ce`). Register it in the batch on
  a memo miss.
- **F15:** `scheduleGuestMessageDrain` runs on **every** push, with no gate (`route.ts:408-411`). Today it returns
  before any read because the sender is `null` (`guest-message-outbox.ts:511-517`). Once W3 registers a transport,
  every push adds reap UPDATE → candidates SELECT → claim UPDATE → claimed SELECT (4 serial, `:530-567`) of
  post-response Lambda busy time. Before W3, apply F8's single-statement claim and gate it (for example, only when a
  producer marked the tenant dirty, or at most once per N seconds per container).

## Rejected candidates (so no one redoes them)

| candidate | reason |
|---|---|
| Move the prefetch inside the transaction (one snapshot, no watermark re-assert) | Same POST count as F3 (BEGIN+reads, apply, COMMIT), and it holds the write transaction open across the JS build and one network RTT: more SQLITE_BUSY for concurrent pushes. |
| Put the limiter UPSERT in the prefetch `db.batch` | Couples a fail-open limiter to push success and makes the read batch a write transaction. See F2-A instead. |
| `runInResilientTransaction` for Option D | Explicitly DECIDED AGAINST (`pushActionsBatch.ts:861-872`): a commit-ack-loss retry would re-run non-idempotent ops. |
| Parallelize or reorder mutation application | Critical Rule 7. W3d already made it one ordered window (`round-trips.test.ts:317-326`). |
| Move poke / notify to `after()` | Already done: `route.ts:359,389` via `runAfterResponse` (`bb608c26e`, S-11/C-020). |
| `getDBAndGroup` → session tenant on push | Landed in `26f580187` (`route.ts:228-234`). F1 is the sibling that commit missed. |
| Batch the prefetch reads | Landed in W3d (`26f580187`), one `db.batch`. |
| Dedupe the origin/content-type "report" session reads (`route.ts:64,116`) | They sit on mismatch branches only; legitimate clients never reach them (49 days, zero content-type mismatches, `route.ts:89-99`). Each does repeat the revocation SELECT (the comments claiming "request-cached" are wrong in a route handler), but it is off the hot path. Fix the comments if touched. |
| Reuse Option D's context in Option C instead of re-prefetching | Saves 1 POST on a rare path, but it is stale after a failed transaction. F7 covers the real cost. |
| `tableServiceActions.ts` | Pull-side read fetchers (imported by `pullActions.ts:37` and the bottle-service seed). Nothing on the push path; belongs to the pull axis. |
| `todoActions.ts` server hops | None. Every handler is a local `rep.mutate`, with no server action. The only cost is F13. |
| `validators.ts`, `operationBuilder*.ts` | Zero `await`: pure SQL builders over the prefetched context. No per-mutation DB reads exist (analysis dedupes IDs into sets). |
| `mutation_log` / outbox appends | Ride the apply window (`pushActionsBatch.ts:831-837`), with zero added POSTs. The index write cost was measured as negligible (`drizzle/schema.ts` mutationLog comment). |
| Lead-12 watermark re-assert | Already rides the apply POST (`754a4693d`; the test holds 4 POSTs). No cost to remove. |

## Out-of-axis observation (correctness, not latency; lead should route)

- **Possible `client_group_version` collision across two clients (tabs) of one group.** Each push computes
  `state.clientGroupVersion` from its *prefetch*, which runs outside the transaction (`pushActionsBatch.ts:669,
  679`), and writes it blind (`operationBuilder.ts:3462-3468`, and `version` on the client row `:3476-3481`).
- The lead-12 re-assert checks only the watermarks of **advanced clients**. Two concurrent pushes advancing
  *different* clients of the same group both pass, and both write version V+1.
- The pull reports `lastMutationIDChanges` only for clients with `client_version > baseCVR.clientVersion`
  (`pullActions.ts:494-505`). A pull that lands between the two pushes records V+1 and can never report the second
  tab's watermark until that tab pushes a new mutation. A pure replay does not bump the version.
- Not verified end to end (60%). Worth a two-client test.

## Adversarial pass (what a hostile reviewer would say I skipped, and what I checked)

1. *"`cache()` might dedupe the limiter's session read after all."* I traced the full chain (F1) and relied on
   `26f580187` / `drizzle/db.ts:272-293`, which document pass-through in route handlers on 16.3, with a
   production-only defect. The route test mocks both functions, which is why this never surfaced.
2. *"F3's fold might let ops run for a foreign owner."* They run inside the same transaction and roll back. No
   statement has an effect outside the DB (the sync_cursor triggers are in-transaction), and F3.1 rejects the common
   case before the transaction opens.
3. *"Are there per-mutation authz reads hidden in the builders?"* `grep -c await` returns 0 for every
   `operationBuilder*.ts` and `validators.ts`. All authz inputs come from the one prefetch, and IDs are collected
   into sets by `analyzeMutations`. The only per-mutation repeated reads are in the Option C fallback (F7).
4. *"Isn't the poke work already post-response?"* Yes (confirmed). F8, F9 and F15 matter only for notification and
   poke freshness to *other* users, and for Lambda container busy time. They are ranked below the synchronous
   findings for that reason.
