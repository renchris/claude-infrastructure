# A8 — scope/gate adjudication of CF LEADS 5, 7, 14, 15

Read-only adjudication against `origin/main` of `reso-management-app`
(trunk tip at time of read: `d0a7a8068`). No edits, no commits, no index writes.
Every path below read via `git show origin/main:<path>` / `git grep origin/main`.

---

## VERDICT TABLE

| Lead | Verdict | Regime in which it bites |
|---|---|---|
| 5 | **CONFIRMED** (low-medium; latent) | only when `tenant_config.enable_venue_scoping = 1` |
| 7 | **CONFIRMED (source half) / BLOCKED-ON-DEPLOYMENT-FACT (impact half)** | live today, no flag needed |
| 14 | **CONFIRMED** (low; integrity-only, latent) | only under venue scoping, actor must be a venue-ADMIN |
| 15 | **CONFIRMED — NOT cured by `6e5465a4e` / `04157d23f`** (but the lead's implied REMEDY is inverted) | only under venue scoping |

Three of the four are *latent*: they arm when per-venue scoping is turned on.
`lib/auth/venue-authz.ts:61-62` states the flag is "OFF in every production tenant";
`drizzle/schema.ts:365` gives `enable_venue_scoping … .default(false)`. **The live per-tenant
value of that column is a DEPLOYMENT FACT, not readable from source.**

---

## LEAD 15 — checked FIRST, per brief. NOT CURED.

### What the two landed commits actually did

`6e5465a4e` ("bind guest erasure to a real guest, not a substring pattern") and
`04157d23f` ("erasure now reaches the phone and the message bodies") both landed in
`src/app/actions/replicache/operationBuilder.ts`. Read in full:

- `6e5465a4e` adds **one** TS guard at `operationBuilder.ts:1580-1583`
  (`context.existingGuestProfiles?.get(id) === undefined && !state.newlyCreatedGuestProfiles.has(id)`
  ⇒ `GUEST_PROFILE_NOT_FOUND`) and rewrites the `mutation_log` redaction's profile-id disjunct
  from a bare `instr()` into an `EXISTS (SELECT 1 FROM guest_profile gp WHERE gp.id = ${id} …)`
  (`:1623-1631`). Both are **identity binding** — "is this id a real guest" — on an axis
  orthogonal to venue.
- `04157d23f` *adds two more tenant-global deletes* to the cascade:
  `DELETE FROM guest_message_outbox WHERE guest_profile_id = ${id}` (`:1671`) and
  `DELETE FROM guest_channel_binding WHERE guest_profile_id = ${id}` (`:1679`).
  It **widens** the blast radius; it does not scope it.

### The tenant-global check survived, verbatim

```
operationBuilder.ts:1562   if (!isManagerOrAbove(context.auth.role, context.auth.isAdmin)) {
operationBuilder.ts:1563     return validationError(ERROR_MESSAGES.MANAGER_PLUS_ONLY)
operationBuilder.ts:1564   }
```

That is the **entire** authorization on the cascade. `context.auth.role` is the user's
*global* role — `resolveVenueRole` (`lib/auth/venue-authz.ts`) is never called here, and
`canAccessVenue` is never called here. The eleven statements it authorizes are all keyed on
`guest_profile_id` with **no venue predicate**:

```
operationBuilder.ts:1632  DELETE FROM bottle_order_item WHERE bottle_order_id IN (… reservation WHERE guest_profile_id = ${id})
operationBuilder.ts:1635  DELETE FROM bottle_order      WHERE reservation_id IN (SELECT id FROM reservation WHERE guest_profile_id = ${id})
operationBuilder.ts:1638  DELETE FROM reservation_guest WHERE reservation_id IN (SELECT id FROM reservation WHERE guest_profile_id = ${id})
operationBuilder.ts:1644  DELETE FROM reservation       WHERE guest_profile_id = ${id}      ← HARD delete, every venue
operationBuilder.ts:1646  DELETE FROM stored_bottle     WHERE guest_profile_id = ${id}      ← HARD delete, every venue
operationBuilder.ts:1671  DELETE FROM guest_message_outbox   WHERE guest_profile_id = ${id}
operationBuilder.ts:1679  DELETE FROM guest_channel_binding  WHERE guest_profile_id = ${id}
operationBuilder.ts:1688  DELETE FROM guest_profile     WHERE id = ${id}
```

### The venue-gated direct paths to the SAME rows

```
operationBuilder.ts:2555-2564  buildDeleteReservationOperation
    const venueWriteError = checkReservationVenueWrite(
      delResExisting?.eventID ?? delResNew?.eventID,
      delResExisting?.venueID ?? delResNew?.venueID,
      context)
    if (venueWriteError) return validationError(venueWriteError)

operationBuilder.ts:2863-2870  buildDeleteReservationGuestOperation — identical shape,
    and the manager+ check sits AFTER it (:2872), i.e. venue first.
```

`checkReservationVenueWrite` (`operationBuilder-shared.ts:582-593`) runs `checkVenueAccess`
→ `canAccessVenue` (`venue-authz.ts`), which under scoping returns false unless the venue is
in `auth.accessibleVenueIDs`. So:

> **A manager holding `user_venue_role` at venue A only cannot delete ONE of venue B's
> reservations directly (`:2557` refuses), but CAN delete ALL of them for a chosen guest
> via `deleteGuestProfile` (`:1562` does not look).**

The asymmetry is exact and file:line-able. LEAD 15 is **CONFIRMED**.

The push boundary does not save it: `lib/auth/venue-authz.ts:14-18` states the read gate is
at the pull route and **"The push WRITE gate is enforced PER-MUTATION inside the
operationBuilder builders"** — so the missing per-mutation check is the only check there was.

### 🚨 ADVERSARIAL FINDING — the lead's implied remedy is INVERTED. Do not venue-scope the deletes.

`guest_profile` has **no `venue_id` column** (`drizzle/schema.ts`, `export const guestProfile`:
`id, phone, email, name, nickname, vipTier, nationality, notes, lineID, totalSpend, visitCount,
…, createdByPromoterID, createdByUserID, noShowCount, flagStatus, …`). A guest is a **tenant-level
identity keyed on phone**, and legitimately holds reservations at several venues of one tenant.
The cascade's own header (`:1543-1554`) cites PIPEDA 2026-001 and argues that retaining
re-identifiable spend is *insufficient anonymization*. **Adding `AND venue_id IN (accessible)`
to those DELETEs would produce a legally INCOMPLETE erasure** — precisely the failure the
cascade exists to prevent. That is a regression wearing a fix's clothes.

The correct direction is to tighten **who may pull the lever**, so that the actor's authority
covers the blast radius the statement already has.

### Safest minimal fix (LEAD 15) — 🚨 OPERATOR-GATED, MUST NOT BE DRIVEN

Destructive + irreversible (hard DELETE, no restore path — the commit body for `6e5465a4e`
says so in terms: *"the table is append-only … the repository has no restore path"*), AND
auth-class. Both flags in `exhaust-improvements.md:212` ("Auth/sync findings → queue +
escalate, never silently land mid-sweep") and in the global escalation rule.

Exact edit, `src/app/actions/replicache/operationBuilder.ts`, replacing `:1562-1564`:

```ts
  // The cascade below is TENANT-GLOBAL by design (guest_profile has no venue_id; a PIPEDA
  // erasure must reach every venue). Its AUTHORITY must therefore be tenant-global too:
  // checkReservationVenueWrite gates every DIRECT delete of these same rows (:2557, :2863)
  // on canAccessVenue, so a venue-A-only manager must not reach venue B's rows through here.
  // No-op under grandfather (scopingEnabled false ⇒ no venue boundary exists to cross).
  if (!isManagerOrAbove(context.auth.role, context.auth.isAdmin)) {
    return validationError(ERROR_MESSAGES.MANAGER_PLUS_ONLY)
  }
  if (context.auth.scopingEnabled && !context.auth.isAdmin) {
    return validationError(ERROR_MESSAGES.ADMIN_ONLY)
  }
```

Properties: byte-neutral under grandfather (`scopingEnabled === false` ⇒ second clause never
fires ⇒ every production tenant today is unaffected); a strict tightening only in the scoped
regime; does not touch a single SQL statement, so erasure completeness is untouched.

*Rejected alternative:* per-venue enumeration ("manager at every venue where the guest has
rows") — needs a new prefetch (the guest's distinct venues) and turns a 0-round-trip builder
into a DB-reading one, violating the module's stated 0-round-trip principle
(`venue-authz.ts:9-18`). Not worth it for a latent finding.

---

## LEAD 7 — `invokeLambdaFunction`

### The authorization branch and the target arrive on DIFFERENT arguments

```
src/app/actions/auth/lambdaActions.ts:175-184
  const invokeLambdaFunction = async (
    subdomain: string,      ← ARG 1: the TARGET tenant
    group: string,          ← ARG 2: the TARGET tenant's Turso group
    firstName, lastName, email,
    invitingUserID: number | null,
    inviteID: string,
    crossTenant?: CrossTenantInvite,   ← ARG 8: chooses the AUTH BRANCH
  ): Promise<string> => {

lambdaActions.ts:187   if (crossTenant === undefined) await ensureAdminAccess()
lambdaActions.ts:188   else await ensurePlatformAccess()
```

They are **different arguments**, and the target is never compared to the session's sealed
tenant. `ensureAdminAccess()` (`accessActions.ts:58-64` → `hasAdminAccess` `:41-56`) reads
`getRegisteredUserFromCookieStorage()` then `getUserFromID()` against `getDB()` — the
**host-resolved REQUEST tenant**. It answers "is the caller an admin *of the tenant they are
browsing*". It says nothing about `subdomain`/`group`.

### It is a POST-able endpoint, not an internal helper

`lambdaActions.ts:1` is `'use server'`, and the module is imported by a **client component**:
`src/app/(app)/admin/(settings)/components/InviteForm.tsx:12` (`import { invokeLambdaFunction }`),
called at `:224`. The repo says so itself in
`src/app/actions/auth/__tests__/lambdaActions.test.ts:4-8`:
*"invokeLambdaFunction is exported from a 'use server' module that a client component
(InviteForm) imports directly — i.e. a POST-able server-action endpoint."*
Compare the deliberate counter-example at `authQueries.ts` ("NEVER add `'use server'` to this
file") — the repo already understands this exposure class.

### The concrete attack, one sentence

> An admin of tenant A POSTs the `invokeLambdaFunction` server action directly with
> `subdomain`/`group` set to **tenant B** and `crossTenant` omitted, whereupon
> `ensureAdminAccess()` passes on their tenant-A admin-ness and the RegisterProcessor Lambda
> is handed a tenant-B-branded invite payload addressed to an attacker-chosen email.

Two source-side effects are certain from this repo alone:

1. **Cross-tenant DB read.** `getPayloadInput` (`:146`) calls
   `getOrganizationNameFromSubdomain(subdomain, group)`, which is
   `const db = await getNamedDB(subdomain, group)` then `SELECT … FROM organization WHERE
   subdomain = ?` (`authQueries.ts`). So client-controlled args open the **victim tenant's
   database connection** and return its organization name into the payload. Small disclosure,
   but it *proves* the target tenant is unvalidated and reachable.
2. **Rate-limit bypass.** The resend path gates on `checkInviteResendLimit`
   (`databaseActions.ts:1170`) *before* it reaches the lambda action; a direct POST to
   `invokeLambdaFunction` never touches that counter.

`crossTenant` cannot be used to *weaken* the gate — supplying it selects the strictly narrower
`ensurePlatformAccess()` (`isPlatformEmail`). The defect is one-directional: the default
branch is too wide for the target it accepts.

### 🚨 THE DEPLOYMENT FACT THAT BOUNDS THE REST — name it, do not guess it

Everything above stops at "the Lambda receives a forged-tenant payload". Whether that becomes
**account takeover** or stays **branded phishing + a name disclosure** depends on two facts
that live outside this repository and **cannot be settled from source**:

- **(D-7a) What `RegisterProcessor` does with the payload.** If it only renders and sends an
  email, the emailed `inviteID` is inert: the matching `invitation` row is written by
  `sendInvitation` against the *caller's own* tenant DB (`InviteForm.tsx:204`, before the
  invoke at `:224`), so no credential exists in tenant B and registration would fail. If the
  Lambda itself provisions a Cognito user or writes the invitation row into the named tenant,
  the same call is **cross-tenant account creation**. The Lambda's source is not in this repo.
- **(D-7b) What the IAM policy behind `AWS_ACCESS_KEY_ID` permits.** The client is built at
  `lambdaActions.ts:47-54` from `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` /
  `AWS_DEFAULT_REGION` resolved out of the Amplify `process.env.secrets` blob
  (`getEnvVar`, `:18-37`). `FunctionName: 'RegisterProcessor'` is hardcoded (`:202`), so the
  IAM question is not *which* function but whether that role/function is partitioned per
  tenant at all.

Until D-7a and D-7b are answered by someone who can read the Lambda and the IAM policy, the
**source half is CONFIRMED and the impact half is BLOCKED-ON-DEPLOYMENT-FACT.**

### Safest minimal fix (LEAD 7) — 🚨 OPERATOR-GATED (auth-class), MUST NOT BE DRIVEN

Assert the target equals the sealed tenant on the non-cross-tenant branch. Byte-neutral for
the only legitimate caller: `InviteForm.tsx:222` obtains its `subdomain`/`group` by calling
`getSubdomainAndGroup()` itself, so a legitimate client's args already equal the session
tenant; `databaseActions.ts:1180` likewise. The `provisionActions.ts:335` caller passes
`{ hostUsername }`, i.e. takes the `else` branch, and is unaffected.

`src/app/actions/auth/lambdaActions.ts`, replacing `:187-188`:

```ts
  // Tenant-admin for the ordinary in-app invite; PLATFORM for a cross-tenant one.
  if (crossTenant === undefined) {
    await ensureAdminAccess()
    // 🚨 ensureAdminAccess answers "admin of the REQUEST's tenant" — it says nothing about
    // `subdomain`/`group`, which are separate, caller-supplied arguments on a POST-able
    // server action (this module is 'use server' and InviteForm imports it directly). Bind
    // the two: on this branch the target MUST be the caller's own sealed tenant.
    const { getSubdomainAndGroup } = await import('@actions/auth/tenantContext')
    const session = await getSubdomainAndGroup()
    if (subdomain !== session.subdomain || group !== session.group) {
      throw new Error('Access Denied: invite target is not this session\'s tenant')
    }
  } else {
    await ensurePlatformAccess()
  }
```

(Dynamic import mirrors the existing cycle-avoidance idiom at `accessActions.ts:51` and
`databaseActions.ts:1181`.) Pin it with a test beside the existing
`lambdaActions.test.ts:69 'invokeLambdaFunction admin gate'` describe block.

---

## LEAD 14 — `createEvent` and the cross-map binding gate

### `table_map_id` is caller-supplied and written unchecked

```
operationBuilder.ts:1187-1205  buildCreateEventOperation
  :1197-1201  const isVenueAdmin = context.auth.isAdmin
                || (context.auth.scopingEnabled && resolveVenueRole(context.auth, data.venueID) === 'admin')
              if (!isVenueAdmin) return validationError(ERROR_MESSAGES.ADMIN_ONLY)
  :1203      if (data.tableMapID && state.deletedTableMapIDs.has(data.tableMapID)) { … }   ← the ONLY check
  :1212-1225 INSERT INTO event (… table_map_id …) VALUES (… ${data.tableMapID} …)
```

`:1203` rejects only a map deleted **in the same batch**. There is no existence check and no
venue-coherence check. Confirmed.

### The gate the lead refers to, and how a foreign map satisfies it

The "cross-map binding gate" is `TABLE_NOT_ON_EVENT_MAP`, at two sites:

```
operationBuilder.ts:1968-1973  (createReservation)
  const eventMapID = context.existingEvents?.get(data.eventID)?.tableMapID
    ?? state.newlyCreatedEvents.get(data.eventID)?.tableMapID ?? null
  if (eventMapID !== null && tableElement.tableMapID !== eventMapID)
    return validationError(ERROR_MESSAGES.TABLE_NOT_ON_EVENT_MAP)

operationBuilder.ts:2215-2220  (updateReservation, on a table move) — identical
```

Its comment at `:1961-1967` names the threat in so many words: *"a forged cross-venue element
(S-08 class)"*. But the predicate is **map EQUALITY, not a venue check** — it asks
`tableElement.tableMapID === event.tableMapID`. `createEvent` writes **both operands**: set
your own event's `table_map_id` to venue B's map and every element of B's map satisfies the
gate. The gate is not bypassed; it is *satisfied by construction*.

The asymmetry is flagrant, because `updateEvent` — the sibling mutation — already does the
full three-step check on the same field:

```
operationBuilder.ts:1381-1393  (updateEvent)
  if (tableMapID !== null && tableMapID !== currentMapID) {
    const targetMap = context.existingTableMaps?.get(tableMapID)
    if (!targetMap) return validationError(ERROR_MESSAGES.TABLE_MAP_NOT_FOUND)     ← 1. existence
    const effectiveVenueID = venueID ?? currentVenueID ?? null
    if (effectiveVenueID !== null && targetMap.venueID !== effectiveVenueID)
      return validationError(ERROR_MESSAGES.MAP_VENUE_MISMATCH)                    ← 2. venue coherence
    if (context.eventsWithActiveReservations?.has(id)) { … }                       ← 3. active-res veto
  }
```

So the repo has already decided this rule and enforces it on `update` only. `createEvent` is
the unclosed half.

### 🚨 ADVERSARIAL PASS — what the attacker actually achieves: CORRUPT THEIR OWN, not READ ANOTHER'S

The brief asks which. I chased the read primitive and it is **closed on every path I could find**:

- **Replicache pull.** `tableServiceActions.ts:1315` `searchTableMaps(tx, scopeVenueIDs)` —
  "A: direct venue_id"; `:1326` `searchFloorPlanElements(tx, scopeVenueIDs)` — "B: inherited
  via tableMap". Both scoped by the venue set, not by the event's map. A foreign map's
  elements are never synced.
- **Floor-plan SSR seed.** `src/app/(app)/floor-plan/initialData.ts:613` resolves the URL
  event's map as `tableMaps.find((tm) => tm.id === urlEvent.tableMapID)` where `tableMaps`
  comes from `getSelectionCore(venueID)` → `db.select().from(tableMap).where(eq(tableMap.venueID, venueID))`
  (`:391`). A foreign id `find`s `undefined` ⇒ falls through to `defaultSelection`. And under
  scoping the URL event is not honoured at all (`:608-611`). So `fetchGeometry` (`:338-345`,
  itself venue-blind) is never handed a foreign map id.
- **Reverse direction (polluting venue B's views).** B's floor plan reads reservations joined
  through `event` with `eq(event.venueID, venueID)` (`initialData.ts:270`), so the attacker's
  reservations — which live on the attacker's own event at their own venue — never appear in B.

What remains is genuine but **integrity-only and largely self-inflicted**: the attacker's own
event carries a dangling/foreign `table_map_id`, so `buildEventInsightUpsert` (`:1258-1263`)
computes `tablesAvailable`/`capacityGuests` from **another venue's** floor-plan elements and
writes them into `event_insight` (a synced row) — corrupt analytics on their own event; and
their reservations bind to foreign element ids, which the section-capacity math
(`:1982-1990`) then evaluates against foreign sections.

**Severity bound, stated honestly:** `createEvent` is admin-gated at `:1197-1201`. Under
grandfather (`scopingEnabled === false`) the only passing actor is a **global admin**, who can
already do all of this and more. Under scoping the actor is a **per-venue admin** — so this is
a venue-admin → cross-venue integrity defect, latent until the flag flips. LOW severity, but
the fix is cheap and it restores a rule the repo already wrote down.

### Safest minimal fix (LEAD 14) — mirror `updateEvent`; NOT destructive, NOT auth-class

Two files. The prefetch currently registers `tableMapIDsToValidate` **only for updateEvent**
(`batchPrefetch.ts:406-407`), so `context.existingTableMaps` is empty on a create and a check
written alone would be vacuous (fail-open) — this is the trap to avoid.

1. `src/app/actions/replicache/batchPrefetch.ts`, in the `createEvent` case of
   `analyzeMutations` (add beside the existing create-event handling, mirroring `:406-407`):

```ts
        if (args.tableMapID != null) {
          analysis.tableMapIDsToValidate.add(args.tableMapID)
        }
```

2. `src/app/actions/replicache/operationBuilder.ts`, replacing `:1203-1205`:

```ts
  // Mirror updateEvent's steps 1-2 (:1381-1393): a create may not bind a map that does not
  // exist or that belongs to another venue. The cross-map binding gate at :1971 / :2218 is a
  // map-EQUALITY test, so an event carrying a foreign map makes every element of that map a
  // legal binding target — createEvent writes both operands. Step 3 (active-reservation veto)
  // has no analogue: a brand-new event has no reservations.
  if (data.tableMapID) {
    if (state.deletedTableMapIDs.has(data.tableMapID)) {
      return validationError(ERROR_MESSAGES.TABLE_MAP_NOT_FOUND)
    }
    const targetMap = context.existingTableMaps?.get(data.tableMapID)
    if (!targetMap) {
      return validationError(ERROR_MESSAGES.TABLE_MAP_NOT_FOUND)
    }
    if (targetMap.venueID !== data.venueID) {
      return validationError(ERROR_MESSAGES.MAP_VENUE_MISMATCH)
    }
  }
```

**Pre-land risk to verify (do not skip):** unlike `updateEvent`, this rejects rather than
degrades on an unresolvable map. Maps are written only by ops scripts (`:1377-1379`
"no client createTableMap"), so a real map always prefetches — but confirm no seed/import
path creates an event referencing a map in the *same* push batch, which would have no
`existingTableMaps` row. If one exists, add a `state.newlyCreatedTableMaps` escape or degrade
to the `updateEvent` fallback shape.

---

## LEAD 5 — the home SSR seed's venue-reachability gate

### The gate, and its ONE consumer

```
src/app/actions/homeStateActions.ts:219-229
  // F4 venue-scope gate for the SSR `activeData.events` seed (raw event rows ship
  // in the RSC/HTML payload). … `activeVenueID` comes from resolveActiveVenueRow which does
  // NO RBAC check, so a scoped user whose resolved active venue is one they have no
  // role at must NOT receive that venue's event rows the pull never syncs.
  const activeVenueInPullScope = !auth.scopingEnabled || auth.isAdmin
    || [...auth.accessibleVenueIDs].includes(activeVenueID)
```

`git show origin/main:src/app/actions/homeStateActions.ts | grep -n activeVenueInPullScope`
returns exactly two lines: the definition (`:228`) and **one** consumer:

```
homeStateActions.ts:404   events: activeVenueInPullScope ? liveVenueEvents.map(toReplicacheEvent) : [],
```

### Two other paths ship the IDENTICAL rows, ungated

The gated array and the ungated one are computed by **identical predicates over the same
source**, so they are the same rows:

```
homeStateActions.ts:232-233   const tonightEvents = venueEvents
                                .filter((e) => e.status !== 'archived' && isAccessibleEvent(e))
homeStateActions.ts:279       const liveVenueEvents = venueEvents
                                .filter((e) => e.status !== 'archived' && isAccessibleEvent(e))
```

- **Path A, same payload:** `homeStateActions.ts:350` `const tonight: TonightEntry[] =
  tonightEvents.map((e) => { … })` → `:373` `const rep = toReplicacheEvent(e)` → `:382`
  `event: rep`. The raw event row ships in `seed.tonight[i].event` of the **same** RSC payload
  whose `seed.activeData.events` the gate just emptied.
- **Path B, every authenticated route:** `getTonightEntriesSeed()` (`:456-526`) recomputes the
  same set (`:490-491` `.filter((e) => e.venueID === activeVenueID && e.status !== 'archived'
  && isAccessibleEvent(e))`) and returns `event: toReplicacheEvent(e)` at `:509/:518`, with
  **no reachability gate anywhere in the function**. Its header (`:449-451`) says it is
  *"Called once per authenticated route in LandingPageOrLoggedInApp"* — i.e. a wider surface
  than the home route the gate was written for. Live consumer:
  `src/app/(app)/layout.tsx:334` → `@components/LandingPageOrLoggedInApp`.

**So `activeVenueInPullScope` is inert as a leak control: it withholds one copy of the rows
while an identical copy ships beside it.** LEAD 5 is CONFIRMED as stated.

### How `activeVenueID` becomes unreachable in the first place (the gate's own premise, verified)

`resolveActiveVenueRow` (`lib/venue-resolution.ts:176-278`) *does* gate the cookie — the
client-writable `reso-venue` cookie is honoured only when `reachable.has(cookieValue)`
(`:268-271`). But two fall-throughs return an **unreachable** venue:

- `:276-277` `return await preferLocalSubdomain(activeVenues.filter((v) => reachable.has(v.id))) ?? activeVenues.at(0)`
  — when the user's reachable set contains no *active* venue, `activeVenues.at(0)` is whatever
  venue sorts first by `displayOrder`, reachable or not.
- `:256-259` a non-transient reachability failure returns `firstActive()`, ungated.

That is exactly the residual the `:228` gate was written to cover — and which it covers in one
of three places.

### What is IN an event row — the severity question, answered by columns

`toReplicacheEvent` (`homeStateActions.ts:110-124`) maps `drizzle/schema.ts:437` `event`:

| column | reading |
|---|---|
| `name`, `date`, `doorsOpen`, `status` | operational schedule — **includes `draft`** (unannounced events) |
| `defaultMinimum` | **commercial** — per-table minimum spend, whole dollars |
| `tierMinimums` | **commercial** — JSON per-event pricing override |
| `notes` | **internal free text**, no stated redaction contract |
| `wristbandAssignments` | operational JSON, `{sectionID: hexColor}` |
| `noShowCutoffTime`, `refundDeadline`, `tableMapID`, `artistProfileID` | operational config / FKs |
| `rowVersion`, `lastModified` | sync markers |

**Verdict on severity: NOT public-facing marketing data, and NOT guest/PII data either.** It is
tenant-internal *operational + commercial configuration* — unannounced draft events, per-event
pricing, staff notes. No guest name, phone, spend or reservation reaches these rows (the
reservation-derived fields in `TonightEntry` are counts and `pendingStaleTables` table ids, not
identities). So: **medium-low.** A cross-venue commercial-config disclosure inside one tenant,
not a PII breach. It would be materially worse if `event.notes` is used for guest-specific
remarks in practice — that is a content question about live data, not a schema question.

### Exploitability, stated honestly (the adversarial bound)

Three conditions must hold at once: (1) `enable_venue_scoping = 1` for the tenant; (2) the user
is a non-admin whose resolved active venue falls through to the unreachable branch above; and
(3) the foreign venue's events pass `isAccessibleEvent` — i.e. the user owns or is shared the
paired list (`accessibleListIDs`, `:211`), or is an assigned promoter. Condition (3) is where
`exhaust-improvements.md:188` matters, and it cuts **toward** the finding, not against it: the
share graph is deliberately **venue-unscoped** by Decision 4, which is precisely what lets a
venue-B user hold accessible lists whose events live at venue A.

### Safest minimal fix (LEAD 5) — authz-class; escalate, do not land mid-sweep

Move the gate to the single chokepoint — the event SET — instead of one consumer, and
replicate it in the narrow seed. Two edits, no new query, no new auth concept.

1. `src/app/actions/homeStateActions.ts`, at `:232` (gate the set, not the copy):

```ts
    // The gate belongs on the SET: `tonight[].event` (:382) and `activeData.events` (:404)
    // ship the SAME rows from identical predicates, so gating one copy withholds nothing.
    const tonightEvents = (activeVenueInPullScope ? venueEvents : [])
      .filter((e) => e.status !== 'archived' && isAccessibleEvent(e))
```

   …and apply the same `activeVenueInPullScope ? … : []` to `liveVenueEvents` at `:279`
   (then `:404` may drop its now-redundant ternary, or keep it as belt-and-braces).

2. `src/app/actions/homeStateActions.ts`, in `getTonightEntriesSeed` at `:490`, add the gate
   this function never had (`auth` is already in scope from `:471-475`):

```ts
    const activeVenueInPullScope = !auth.scopingEnabled || auth.isAdmin
      || auth.accessibleVenueIDs.has(activeVenueID)
    const tonightEvents = (activeVenueInPullScope ? allEvents : [])
      .filter((e) => e.venueID === activeVenueID && e.status !== 'archived' && isAccessibleEvent(e))
```

   (Note `accessibleVenueIDs` is a `Set` here — `.has()`, not the `[...].includes()` spread at
   `:229`; that spread is itself worth simplifying but is behaviourally identical.)

**Behavioural consequence, checked:** when the gate is false the rail and home panes paint
empty — which is *correct*, because the Replicache pull does not sync those events either, so
the client converges to empty at hydration. This preserves, rather than breaks, the repo's
stated `seed == pull` invariant (`.claude/rules/replicache.md`, cited at `:147`). Under
grandfather nothing changes at all.

Better still (but larger): hoist the gate into `resolveActiveVenueRow` so `activeVenueID` can
never *be* an unreachable venue — the `?? activeVenues.at(0)` at `venue-resolution.ts:277`
would return `undefined` for a scoped user with no reachable active venue. That fixes every
current and future consumer of the resolver (floor-plan, guests, bottle-service seeds all read
it) instead of the two here. It is the right fix and it is NOT minimal — propose it, do not
land it in the same change.

---

## DO-NOT-FIX cross-check (`.claude/commands/exhaust-improvements.md` §181-190)

Read in full. Nine landmines. Relevant findings:

- **`:188` "share-graph venue-unscoped reads — intentional (Decision 4, per-venue RBAC); a
  security lens WILL flag it; it is by-design."** This is the one the brief asks about.
  It covers the **SHARE GRAPH** — `list`/`share` reads not being venue-filtered, which is what
  makes `accessibleLists` (`homeStateActions.ts:211`, `:482`) span venues.
  - It does **NOT** cover LEAD 5. LEAD 5 is about **`event` rows** shipping in the SSR payload
    past a gate the repo itself wrote *for those rows*. The fix above changes no share-graph
    read and adds no venue filter to `list`/`share`; it gates the EVENT set on the axis
    `:219-227` already declares. Decision 4 is in fact the *reason* condition (3) of the
    exploit is satisfiable, not a licence for the leak.
  - It does **NOT** cover LEAD 15 — that is a WRITE path (hard DELETE), not a read, and the
    proposed fix is a role check, not a venue filter on a read.
- **`:189` `getServerActionSession` IS the auth check.** My LEAD 7 fix does not rename or
  replace it; it adds a tenant-identity assertion beside `ensureAdminAccess`. No conflict.
- **`:212-213` (Notes item 5), directly on point:** *"Auth/sync findings → queue + escalate,
  never silently land mid-sweep (CLAUDE.md escalation rule wins over 'just keep working').
  Surfacing + planning + flagging IS the correct disposition."*
  **All four leads are auth/authz-class. None should be landed by this pass.**
- `:205` (Notes item 3) — the security lens has previously re-derived the **S-13 venue-authz
  chokepoint owned by campaign C-004**. LEADS 5, 14 and 15 are all instances of that same
  seam. Per the File Update Rule quoted there: **INTEGRATE these three into the existing
  C-004 / S-13 ledger entry; do NOT orphan a new plan.** LEAD 7 is a different seam
  (cross-TENANT, not cross-venue) and warrants its own entry.

No other landmine is touched: nothing here involves `for...of` mutations, `<Suspense>`,
mission-control `rgba`, F6 warm-at-tap, the FloorPlanViewer barrel, or park-ui spreading.

---

## Fix-safety classification (for the operator)

| Lead | Destructive / irreversible? | Auth-session class? | May an agent drive it? |
|---|---|---|---|
| 5 | no | yes (authz scope) | **No** — escalate (`exhaust-improvements.md:212`) |
| 7 | no | **yes (auth gate, cross-tenant)** | **No** — operator-gated |
| 14 | no | partly (venue-coherence) | **No** — escalate; also needs the batchPrefetch companion edit or it is vacuous |
| 15 | **YES — hard DELETE, no restore path** | **yes** | **No** — operator-gated, both flags |

## Deployment facts named (not guessed)

- **D-7a** — what AWS Lambda `RegisterProcessor` does with the `{subdomain, location, host,
  firstName, lastName, email, inviteID}` payload: email-only (⇒ branded phishing +
  organization-name disclosure) vs. user/invitation provisioning (⇒ cross-tenant account
  creation). Lambda source is not in this repository.
- **D-7b** — whether the IAM policy attached to `AWS_ACCESS_KEY_ID` (resolved from the Amplify
  `process.env.secrets` blob, `lambdaActions.ts:18-37,47-54`) partitions `RegisterProcessor`
  invocation per tenant. Not readable from source.
- **D-5/14/15** — the live value of `tenant_config.enable_venue_scoping` per production tenant.
  Source *asserts* OFF everywhere (`venue-authz.ts:61-62`, default `false` at
  `drizzle/schema.ts:365`), and `floor-plan/initialData.ts:599` calls grandfather "every tenant
  today" — but an assertion in a comment is not a reading of the column. Whoever flips that
  flag arms LEADS 5, 14 and 15 simultaneously; all three should be closed *before* the flip,
  not after.
