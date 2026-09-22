# A7 — Replicache sync-path leads 11/12/13/17, adjudicated

Read-only adjudication against `origin/main` in `reso-management-app`, 2026-09-22.
All citations are `origin/main:<path>:<line>`. No edits, no commits, no index writes.

## Verdict table

| Lead | Verdict | One-line basis |
|---|---|---|
| 11 — pull uses tenant-global role, push per-venue | **REJECTED-BY-DESIGN** (+ inert under a deployment fact) | `guest_profile` has no venue column at all — tenant-shared by ratified architecture |
| 12 — watermark read outside the applying transaction | **CONFIRMED** | prefetch at `pushActionsBatch.ts:595`, transaction at `:697`; watermark write is a blind SET |
| 13 — gap-error consume persists the client-chosen id | **CONFIRMED** | `pushActionsBatch.ts:462` writes `mutation.id` after a "from the future" throw |
| 17 — `toClientSafeMutationError` contradicts its docblock | **CONFIRMED, LOW severity** | docblock says collapse, body says `return raw` (`operationBuilder-shared.ts:431`) |

---

## LEAD 11 — REJECTED-BY-DESIGN

### The asymmetry is real in code

**PULL** resolves visibility from the tenant-global `user.role`:

- `pullActions.ts:643-644` passes `authContext.role` / `authContext.isAdmin` into
  `searchTableServiceEntities`.
- Those come from `prefetchPullAuthContext` (`authContext.ts:288-289`), which reads
  `user.role` — the tenant-global column — and never consults `venueRoles`.
- `tableServiceActions.ts:1317` → `searchGuestProfiles(tx, role, isAdmin, promoterID)`.
- `tableServiceActions.ts:272-278`:

  ```ts
  // Admin/manager see all guests
  if (isAdmin || role === 'admin' || role === 'manager') {
    const rows = await tx
      .select({ id: guestProfile.id, rowVersion: guestProfile.rowVersion })
      .from(guestProfile)
      .all()          // ← no WHERE. The whole tenant's guest CRM.
    return rows
  }
  ```

**PUSH** resolves visibility from the per-venue role:

- `operationBuilder-shared.ts:547` — `const effectiveRole = venueID ? resolveVenueRole(auth, venueID) : auth.role`
- `operationBuilder-shared.ts:571` — same shape for the write gate.
- `venue-authz.ts:277-280` — `resolveVenueRole` returns `auth.venueRoles.get(venueID) ?? auth.role`,
  i.e. **a per-venue row WINS over the global role** (`venue-authz.ts:135`).

A corroborating tell: `pullActions.ts:21` **imports `resolveVenueRole` and never calls it** — it is
the only occurrence of the symbol in that file. Per-venue role resolution was wired into the pull's
imports and is dead there.

The reason is stated in the code: `pullActions.ts:615-618` — *"Promoter narrowing keys on the GLOBAL
role now — there is no single active venue under the all-venues pull."* The pull was refactored to an
all-venues CVR (`pullActions.ts:96-104`), so it has no venue to resolve a role against.

### Why the verdict is still REJECTED-BY-DESIGN

The lead's *consequence* claim — "a venue-demoted user is still sent the whole tenant's guest CRM" —
is the designed behaviour of a tenant-shared entity, not a scoping failure, because **there is no
venue axis on the entity to scope by**:

- `docs/auth-tenancy/README.md:531-535`:
  > *"Venue scoping is deliberately asymmetric: venueID is a real FK on 7 tables (tableMap, event,
  > bottleCategory, storedBottle, floorPlanTier, floorPlanPricingPreset, bottleMenuItem);
  > **guestProfile**/promoter/artistProfile/user/credential/session/organization **are SHARED with no
  > venueID**; and section, floorPlanElement, floorPlanCanvas, reservation, bottleOrder,
  > promoterCommission inherit scope through the FK chain."*
- Verified against the schema: `drizzle/schema.ts:553` `sqliteTable('guest_profile', …)` — the table
  body carries no `venue_id` column.
- `tableServiceActions.ts:1268` classifies it the same way: *"Category D (shared) unfiltered."*

This is the same family as reso's DO-NOT-FIX landmine and the plans ledger's by-design entry —
`plans/README.md:300-308` lists *"share-graph venue-unscoped reads"* under **By-design (cleared with
evidence)**. The lead is that item wearing a new name, extended from the share graph to the guest
CRM, and the guest CRM's venue-unscoped read has a stronger justification than the share graph's:
the column does not exist.

Venue **access** is not the leak here either — it *is* enforced on the pull:
`pullActions.ts:611-614` threads `accessibleVenueIDs` into `VenueScoping`, and every venue-keyed
entity (`tableMap`, `event`, `reservation`, `bottleOrder`, …) is filtered by
`resolveScopeVenueIDs` (`tableServiceActions.ts:1284`). Only the seven schema-shared entities are
tenant-wide, by design.

**Residual worth recording (not a defect, a design gap):** under an *enabled* scoping rollout, a user
who is globally `manager` but demoted to `door_staff` at every venue they can reach would still
receive all guest profiles on the pull while being treated as `door_staff` on the push. There is no
"correct" per-venue answer available — you would have to define an effective role as an aggregate
(min/max) over the reachable venue set. That is a product decision, not a bug fix, and it should be
filed as one rather than patched.

### 🚩 DEPLOYMENT FACT I CANNOT READ FROM SOURCE

**The live value of `tenant_config.enable_venue_scoping` in each of the ~10 active tenant
databases.**

This decides whether the asymmetry exists *at all* in production:

- Schema default is OFF — `drizzle/schema.ts:365`:
  `enableVenueScoping: integer('enable_venue_scoping', { mode: 'boolean' }).notNull().default(false)`
- With the flag **false**, `resolveVenueRole` returns `auth.role` unchanged (`venue-authz.ts:278`,
  `if (!auth.scopingEnabled) return auth.role`) and `canAccessVenue` allows everything
  (`venue-authz.ts:290`). **Push and pull then use the identical global role and there is no
  asymmetry whatsoever.**
- `venue-authz.ts:63-64` *asserts* the deployment state in a comment: *"The flag is a deliberate
  rollout switch — **OFF in every production tenant**, flipped at most once per rollout and never
  during live traffic."*

A source comment is a claim with a shelf life, not a measurement. To settle it, read the live value
per tenant (one row each, `tenant_config` id `'default'`). If it is OFF everywhere, LEAD 11 is inert
in production on top of being by-design, and the residual above is pre-emptive work for a future
rollout rather than a live gap.

---

## LEAD 12 — CONFIRMED

### The read is outside the transaction that applies the batch

| | Location | Code |
|---|---|---|
| **Watermark READ** | `pushActionsBatch.ts:595` | `const context = await batchPrefetchContext(db, clientGroupID, userID, mutations)` |
| ↳ the actual SELECT | `batchPrefetch.ts:707-713` | `.select({ …, lastMutationID: replicacheClient.lastMutationID }).from(replicacheClient).where(inArray(replicacheClient.id, [...analysis.clientIDsToFetch]))` |
| ↳ into state | `batchPrefetch.ts:1255` → `initializeInMemoryState` (`operationBuilder.ts:370`) | seeds `state.lastMutationIDByClient` |
| **Idempotency DECISION** | `pushActionsBatch.ts:621-630` | `const currentLastMutationID = state.lastMutationIDByClient.get(mutation.clientID) ?? 0` … `if (mutation.id < expectedMutationID) continue` — pure in-memory, from the pre-transaction read |
| **TRANSACTION opens** | `pushActionsBatch.ts:697` | `await db.transaction(async (tx) => {` |
| **Watermark WRITE** | `operationBuilder.ts:3439-3442` | `ON CONFLICT(id) DO UPDATE SET last_mutation_id = ${lastMutationID}, …` — **unconditional. No `WHERE last_mutation_id < …`. Not a compare-and-set.** |

The gap is 102 lines and one full Turso round-trip wide. The codebase already recognises this exact
hazard class and fixed it for the *neighbouring* concern — `pushActionsBatch.ts:698-714` carries a
16-line comment explaining why **ownership** validation was moved inside the transaction
("TOCTOU = Time-Of-Check-Time-Of-Use vulnerability"). The idempotency watermark was not given the
same treatment.

The code also states the opposite as fact. `pushActionsBatch.ts:780-781`:

> *"Boundary re-push is idempotent via the **atomic lastMutationID watermark**, so rethrow-to-boundary
> is the safe path here."*

That sentence is false as written: the watermark write is a blind SET and its governing read is
outside the transaction. The re-push is idempotent only when the retry's *prefetch* happens after the
first push committed — i.e. for a strictly sequential retry, not a concurrent one.

`validateAndClaimOwnership` does not accidentally serialise the two pushes: in the steady state
(Case 3, existing group with an owner) it is a **pure read plus a comparison** — `getClientGroup(tx,
clientGroupID)` then `if (clientGroup.userID !== userID) throw` (`sharedActions.ts`). No write, no
lock taken before the operations are queued.

### The concurrency vector is the product's own retry path, not a hypothetical

`lib/create-custom-pusher.ts:107-110`:

```ts
// 30s timeout: prevents silent hangs on congested WiFi (Lost In Dreams incident)
// On abort, falls through to catch → returns 503 → Replicache retries with backoff
const controller = new AbortController()
const timeoutId = setTimeout(() => controller.abort(), 30000)
```

The abort cancels the **client's** fetch. It does not cancel the server's in-flight Lambda. So:

1. t=0 — push P1 sent, carrying `{clientID: c, mutation.id: N}`.
2. Server stalls (this repo documents ~500-1000 ms Turso round-trips as routine —
   `venue-authz.ts:63`, `authContext.ts:121-134` — and the comment above names a real congested-WiFi
   incident).
3. t=30 s — client aborts, pusher returns 503, Replicache retries with backoff.
4. P2 arrives with the **same** `clientID` and the **same** `mutation.id`.
5. P2's prefetch (`:595`) reads `last_mutation_id = N-1` — P1 has not committed.
6. Both build the same operations. Both transactions commit. **The batch applies twice.**

A second, cheaper vector: any authenticated staff user can simply replay their own captured push body
concurrently. The durable rate limiter is 100 requests / 60 s per user (`route.ts:166-173`) and
performs no deduplication. Blast radius is confined to their own client group
(`validateAndClaimOwnership` binds `clientGroupID` to `userID`), which is the same client group whose
inventory writes are tenant-visible.

### The concrete double-apply: bottle-order inventory

Most mutations survive a replay — that is deliberate and documented. `operationBuilder-spend.ts:106-107`:
*"Every aggregate is RECOMPUTED from the live reservation table (**idempotent under Replicache
replay**), never incremented."* Absolute `SET col = value`, `INSERT … ON CONFLICT`, and recomputed
aggregates are all replay-safe.

**Exactly two statements in the whole replicache action tree perform relative arithmetic on a business
value** (everything else matching `col = col ± …` is `row_version = row_version + 1`, a monotone
counter that is harmless to bump twice). Both are in `updateBottleOrder`:

**`operationBuilder-bottleService.ts:531-549` — the decrement:**

```ts
if (status === 'confirmed' && priorResolved === 'draft') {
  sideEffects.push(sql`
    UPDATE ${bottleMenuItem} SET
      available_quantity = MAX(0, available_quantity - COALESCE((
        SELECT SUM(${bottleOrderItem}.quantity) …
      ), 0)),
      …
    WHERE available_quantity IS NOT NULL
      AND (SELECT status FROM ${bottleOrder} WHERE id = ${id}) = 'confirmed'
      …`)
}
```

**`operationBuilder-bottleService.ts:557-575` — the restock**, identical shape with
`available_quantity = available_quantity + COALESCE(…)` and, per its own comment,
*"No MAX clamp: restock adds back exactly what the confirm subtracted."*

Why a replay defeats both gates:

- The **emission** gate is `priorResolved` — a JS value read in the pre-transaction prefetch
  (`operationBuilder-bottleService.ts:435`, `const priorResolved = enrichedOrder?.status ?? …`, where
  `enrichedOrder` comes from `context.existingBottleOrders`, populated at `batchPrefetch.ts:1064,
  1461-1469`, i.e. the *same* stale Phase-1 read). On P2 it is still `'draft'`, so the decrement op
  **is emitted**.
- The **SQL** gate is `(SELECT status FROM bottle_order WHERE id = …) = 'confirmed'`, read live. P1
  already committed `'confirmed'`, so the gate is **true**.
- The status write itself *is* idempotent (`:481-488` reads the live prior status via the subquery at
  `:457`, so the CASE falls to `ELSE status`) — which is precisely what leaves the side-effect gate
  satisfied on the replay.

Result: `available_quantity` is decremented twice for a single confirm, or incremented twice for a
single cancel. The confirm direction is clamped at zero (`MAX(0, …)`) and silently under-reports
stock; the **cancel direction has no clamp and inflates stock above the true count**, which then
defeats the oversell guard at `:467-473` and lets a subsequent confirm sell bottles that do not
exist.

The code half-anticipated this. `operationBuilder-bottleService.ts:530`:
*"MAX(0, …) is a backstop for the rare cross-batch race."* The clamp bounds the damage of the race; it
does not prevent it, and the restock direction has no equivalent.

### Fix

**Tier B — the actual fix for LEAD 12. Operator-gated.**

Re-assert the watermark *inside* the transaction, exactly as ownership already is. In
`pushActionsBatch.ts`, immediately after `await validateAndClaimOwnership(tx, clientGroupID, userID)`
(`:714`):

```ts
// TOCTOU twin of the ownership check above. The idempotency watermark governing this
// batch was read in Phase 1 (batchPrefetchContext, :595) — OUTSIDE this transaction — so a
// concurrent duplicate push (the 30s pusher abort + Replicache retry,
// create-custom-pusher.ts:107-110) can re-apply relative-arithmetic side-effects
// (operationBuilder-bottleService.ts:534,560). Re-read and abort if it moved.
// Sequential for...of + await BY DESIGN — never Promise.all (Critical Rule #3).
for (const [clientID, baseline] of prefetchedBaselines) {
  // eslint-disable-next-line no-await-in-loop
  const row = await tx.select({ lastMutationID: replicacheClient.lastMutationID })
    .from(replicacheClient).where(eq(replicacheClient.id, clientID)).get()
  if ((row?.lastMutationID ?? 0) !== baseline) {
    throw new ConcurrentPushError(clientGroupID, clientID)
  }
}
```

where `prefetchedBaselines` is the snapshot of `state.lastMutationIDByClient` taken **before** the
Phase-2 loop mutates it (`:619-671`) — capture it at `:618` as
`new Map(state.lastMutationIDByClient)`.

Honouring DO-NOT-FIX fact (a): this is a `for…of` + `await` read guard with the inline
`no-await-in-loop` disable the repo already uses. It must **not** be `Promise.all`ed, and it does not
touch mutation application ordering at all. `N` is the number of distinct `clientID`s in the batch,
typically 1.

`ConcurrentPushError` must be handled like `ClientGroupOwnershipError`, **not** like a validation
error — add a rethrow branch beside `pushActionsBatch.ts:803` (Option D catch) *and* beside the
Option C rethrows at `:409-430`. It must never fall through to Option C, which would re-run the batch
and consume it. Route it to a 5xx so Replicache retries (the retry's fresh prefetch then reads the
advanced watermark and idempotency-skips correctly).

Why operator-gated: it introduces a new 5xx failure mode on the live sync path, it sits in the
authorization/transaction boundary CLAUDE.md requires an ask for, and it adds one awaited statement
(a real serialization point) inside the hot transaction.

**Tier A — independent hardening, landable now.** Make the watermark monotonic in
`operationBuilder.ts:3439-3443`:

```sql
ON CONFLICT(id) DO UPDATE SET
  last_mutation_id = ${lastMutationID},
  version = ${state.clientGroupVersion},
  last_modified = ${batchTimestamp}
WHERE ${replicacheClient}.last_mutation_id < ${lastMutationID}
```

(SQLite supports a `WHERE` on the `DO UPDATE` clause.) This makes the watermark unable to move
backwards. **Be clear about what it does not do:** it does not fix LEAD 12's double-apply, because
the side-effect statements are queued and executed in the same transaction regardless of whether the
metadata UPSERT ends up a no-op. Its real value is as the second half of LEAD 13's fix.

---

## LEAD 13 — CONFIRMED

### The path

1. **Option D** detects the gap and aborts the batch — `pushActionsBatch.ts:633-642`:

   ```ts
   if (mutation.id > expectedMutationID) {
     console.error(`[Option D] Mutation ${mutation.id} is from the future (expected ${expectedMutationID})`)
     throw new Error(`Mutation ${mutation.id} is from the future - aborting. …`)
   }
   ```

2. That throw is caught at `:768`. It is not `SQLITE_BUSY` (`:771`), not transient
   (`:792` → `isTransientDbError`, whose permanent shapes are `unique` / `foreign key` / `constraint`,
   `lib/db/transient-errors.ts:69-71`), not `ClientGroupOwnershipError` (`:803`). So it falls through
   to **Option C** at `:838`.

3. **Option C** re-prefetches (`:323`) and hits the same gap — `pushActionsBatch.ts:352-356`:

   ```ts
   if (mutation.id > expectedMutationID) {
     throw new Error(`Mutation ${mutation.id} is from the future (expected ${expectedMutationID})`)
   }
   ```

4. Caught at `:405`, passes all three rethrow guards (`:409`, `:417`, `:427`), records the error at
   `:437-440`, then reaches the consume block — **`pushActionsBatch.ts:460-479`**:

   ```ts
   const permanentErrorMessage = error instanceof Error ? error.message : String(error)
   try {
     state.lastMutationIDByClient.set(mutation.clientID, mutation.id)   // ← :462 THE CLIENT-CHOSEN ID
     state.clientGroupVersion += 1
     const ts = Date.now()
     const metadataOps = buildMetadataOperations(push.clientGroupID, state, userID, ts)
     await db.transaction(async (tx) => { … })                           // ← :467 durably persisted
   }
   ```

5. `buildMetadataOperations` writes it straight through —
   `operationBuilder.ts:3430-3443`, `last_mutation_id = ${lastMutationID}` where `lastMutationID` is
   the value just set at `:462`.

### The consequence, precisely

The server's durable watermark for that client jumps from `expected-1` to the **client-supplied**
`mutation.id`. Every mutation id in the half-open interval `[expected, mutation.id)` is now
permanently unreachable: any later push carrying one takes the idempotency skip at
`pushActionsBatch.ts:625-630` ("already processed - skipping") or `:346-350`, silently, forever, with
no error and a 200 response. Mutations *after* the gap continue to process normally — the loss is
exactly the gap.

The repository states this harm in its own words. `pushActionsBatch.test.ts:412-415`, on a *different*
door into the same defect:

> *"Pre-fix, m2 reads the leaked id 1, succeeds, persists lastMutationID 2, and **the client's retry
> of m1 is idempotency-skipped forever (silent drop of a check-in)**."*

That fix (the `metaErr` rollback at `:480-500`) stopped m2 from *inheriting* m1's leaked bump. It did
not stop m2's own catch at `:462` from writing its own client-chosen id `2` while `1` was never
committed — the same silent drop, through a different door. The existing suite does not close it:
`pushActionsBatch.test.ts:210-223` exercises exactly this path (`id: 5` against an expected `1`) and
asserts only `usedFallback`, `fallbackReason`, `success` and `errors`. **It never asserts the
persisted watermark value.** Its comment at `:217-219` says "still marked processed", which is the
author's intent ("consume it so it does not retry forever") — the mechanism consumes it at the
client's id, which is the defect.

Reachability: `pushActionsBatch.ts:638-640` names dev server restarts. In production a gap arises from
any client/server divergence — a restored-from-backup tenant DB against a surviving IndexedDB, a
partially-rebased local mutation log, or a client that pushes an arbitrary `mutation.id` (the push
body is entirely client-controlled and the id is never bounds-checked against anything but the
in-memory expectation). An authenticated user can wreck only their own client group's watermark, so
this is a **data-loss** finding rather than a cross-user security one.

### Fix

**Landable now — the watermark may never advance by more than one per consumed mutation.**
`pushActionsBatch.ts:462`:

```ts
// was: state.lastMutationIDByClient.set(mutation.clientID, mutation.id)
// A consumed mutation advances the watermark by exactly ONE. Writing the CLIENT-CHOSEN id
// here (the "from the future" path, :352-356) jumps the watermark over the whole gap, and
// every id inside it is then idempotency-skipped forever at :625 — a silent drop.
const consumed = Math.min(mutation.id, prevLastMutationID + 1)
state.lastMutationIDByClient.set(mutation.clientID, consumed)
```

`prevLastMutationID` is already in scope — captured at `:340` for the rollback path.

For an ordinary permanent mutator failure `mutation.id === prevLastMutationID + 1`, so this is
byte-identical to today's behaviour; it diverges only on a genuine gap. It is compatible with the
existing suite: `pushActionsBatch.test.ts:210-223` asserts nothing that changes.

Pair it with **Tier A** from LEAD 12 (the monotonic `WHERE last_mutation_id < …` on the UPSERT) so
the invariant is enforced at the storage layer too, not only in the builder.

**Operator-gated half — what the client is told about the gap.** With the above, a genuinely
future mutation is no longer consumed, so the client re-pushes it: the zombie-retry loop that SF-1 /
#899 was written to prevent (`pushActionsBatch.ts:453-459`). The correct Replicache-protocol answer to
a gap is not a silent skip and not an infinite retry — it is to tell the client its state is
unrecoverable and force a reset (`ClientStateNotFound`). That is a sync-contract change and belongs to
the operator. Until it is decided, the landable half converts *permanent silent loss* into *a visible,
recoverable stall*, which is strictly the better failure.

---

## LEAD 17 — CONFIRMED (contradiction real; severity LOW)

### Docblock vs body

`operationBuilder-shared.ts:418-421` — the docblock:

> *"**Unrecognized errors collapse to a generic line rather than passing through** — an unknown DB
> error is exactly the case where the raw text is most likely to be noise or to leak internals. The
> raw string is still logged verbatim by the caller's `logError`, so observability is unchanged."*

`operationBuilder-shared.ts:423-432` — the body:

```ts
export const toClientSafeMutationError = (raw: string): string => {
  if (raw.includes('idx_reservation_event_table_active')) {
    return ERROR_MESSAGES.TABLE_ALREADY_BOOKED
  }
  // A constraint we have no curated wording for: say what happened, name nothing.
  if (raw.includes('SQLITE_CONSTRAINT')) {
    return 'That change conflicts with the current state — someone may have edited it first.'
  }
  return raw          // ← :431. Everything else passes through verbatim.
}
```

A two-entry denylist with a permissive default. The docblock describes an allowlist. The lead is
correct on the facts.

The contradiction is *institutionalised* by the test —
`__tests__/clientSafeMutationError.test.ts:37-42`:

```ts
it('passes a non-constraint message through — those are already curated upstream', () => {
  const raw = ERROR_MESSAGES.GUEST_BANNED_CHECK_IN
  expect(toClientSafeMutationError(raw)).toBe(raw)
})
```

That test encodes a population that does not reach this function. Curated `ERROR_MESSAGES` values
travel as `result.error` and are written into the errors map **directly**, never through this
function — `pushActionsBatch.ts:372` (Option C) and `:657` (Option D). The function has exactly **one**
production call site, `pushActionsBatch.ts:437-440`, and it is inside the Option C `catch` — so every
string it ever sees is a **thrown** error, which is precisely the population the docblock wants
collapsed.

### What actually reaches the client

The path is real and ends at a visible toast:

`pushActionsBatch.ts:437` `errors.set(…)` → `BatchPushResult.errors` → `route.ts:414-417`
`responseBody.validationErrors = result.errors` → HTTP **200** JSON →
`create-custom-pusher.ts:194-205` maps each entry to `{ mutationName, message }` →
`create-replicache-context.tsx:1011-1014` `showToast.error(title, message)`.

Enumerating honestly what the verbatim branch can carry:

| Class | Example | Reaches client? | Sensitivity |
|---|---|---|---|
| SQL constraint text + index names | `SQLITE_CONSTRAINT_UNIQUE: … index 'idx_…'` | **No** — curated at `:424`/`:428` | — |
| Schema identifiers from a statement error | `SQLITE_ERROR: no such column: available_quantity` (post-migration skew) | **Yes** | Low — table/column names |
| Protocol internals | `Mutation 5 is from the future (expected 1)` (`:353`) | **Yes** | Low — own client's state |
| Programmer errors in mutators | `TypeError: Cannot read properties of undefined (reading 'venueID')` | **Yes** | Low/moderate — internal field names and code shape, useful for mapping the mutator surface |
| **SQL statement text** | — | **No** — libsql error messages do not embed the prepared statement | — |
| **Row values** | — | **No** — SQLite constraint messages name `table.column`, never the value | — |
| **Tenant identifiers / other users' data** | — | **No** — nothing on this path interpolates tenant or cross-user data into a message | — |

So: **no cross-tenant and no cross-user data disclosure.** The exposure is internal schema and error
text shown in a toast to an already-authenticated staff user of that tenant. That is a hygiene defect
and a contradicted contract, not a data leak. Severity **LOW** — it is worth fixing because the fix
is three lines and the docblock already promises it, not because anything sensitive is escaping
today.

### Fix — landable now

`operationBuilder-shared.ts:431`, make the body match its own docblock:

```ts
  // Anything else is a THROWN error (this function's only call site is the Option C
  // catch, pushActionsBatch.ts:437) — collapse it. Curated ERROR_MESSAGES values never
  // reach here; they travel as `result.error` (pushActionsBatch.ts:372, :657).
  // The raw string is still logged verbatim by the caller's logError (:442-451).
  return 'That change could not be saved. Please try again.'
```

Required companion edit: `__tests__/clientSafeMutationError.test.ts:37-42` must be rewritten. It
asserts the pass-through this fix removes, and its stated premise ("those are already curated
upstream") is false for this function's actual population. Replace it with a test asserting that an
uncurated thrown message — e.g. `SQLITE_ERROR: no such column: available_quantity` — does **not**
reach the caller, and add a positive control that the two curated branches still fire.

Note for whoever lands it: door staff currently see the generic constraint line for the common
races, so this change alters the toast text only for genuine server faults — which today display an
internal error string and after the fix display a retry prompt. No behavioural coupling, no protocol
change.

---

## Landability summary

| Lead | Fix | Landable now? |
|---|---|---|
| 11 | none — by-design; file the effective-role-under-scoping question as a product decision | n/a |
| 12 Tier A | monotonic watermark UPSERT, `operationBuilder.ts:3439-3443` | **Yes** — additive guard, no protocol change |
| 12 Tier B | in-transaction watermark re-assert + `ConcurrentPushError`, `pushActionsBatch.ts:714` | **No — operator-gated.** New 5xx on the live sync path; authorization/transaction boundary |
| 13 landable half | `Math.min(mutation.id, prev + 1)` at `pushActionsBatch.ts:462` | **Yes** — no-op on the normal path, existing suite unaffected |
| 13 gated half | tell the client its state is unrecoverable (`ClientStateNotFound`) instead of looping | **No — operator-gated.** Sync-contract change |
| 17 | replace `return raw` with the generic line + rewrite one test | **Yes** |

DO-NOT-FIX compliance: no proposed change converts a sequential `for…of` + `await` over mutations
into `Promise.all` (fact a). The one new loop introduced (LEAD 12 Tier B) is a sequential read guard
carrying the repo's existing `no-await-in-loop` disable, and it does not touch mutation application.
LEAD 11 is resolved as the by-design read fact (b) predicted it might be.

## Method notes for whoever picks this up

- Everything above is read from `origin/main` via `git show` / `git grep`. Nothing was executed; the
  shared detached-HEAD checkout was never touched.
- Two claims rest on **source comments asserting deployment state** and must be re-measured, never
  re-quoted: `venue-authz.ts:63` ("OFF in every production tenant") and the Turso latency figures at
  `authContext.ts:121-134`. The first is the blocking deployment fact for LEAD 11.
- The most useful single check that is *not* in this document: confirm with a live read whether any
  tenant has `enable_venue_scoping = 1`. If none does, LEAD 11 closes twice over and the
  effective-role design gap becomes pre-rollout work rather than a live one.
