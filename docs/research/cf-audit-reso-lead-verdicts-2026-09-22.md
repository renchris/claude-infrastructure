# The 20 cloudflare leads, adjudicated to verdicts — 2026-09-22

Companion to [`cf-audit-reso-actions-2026-09-22.md`](cf-audit-reso-actions-2026-09-22.md) (the run
of record: 6 confirmed / 20 needs_validation) and
[`cf-audit-reso-uncovered-surfaces-2026-09-22.md`](cf-audit-reso-uncovered-surfaces-2026-09-22.md)
(W5's enumeration of the 19 units the run did not cover). Programme plan:
[`../plans/RESO_SECURITY_100P.md`](../plans/RESO_SECURITY_100P.md).

A lead is not a finding. Each entry below is resolved to **CONFIRMED**, **REJECTED** (with the
evidence that rejects it), or **BLOCKED-ON-DEPLOYMENT-FACT** (with the one fact named). Target is
reso `origin/main`, read via `git show origin/main:<path>` — never a working tree.

---

## The instrument that changed several verdicts

The audit's **structural fact #1** is that in the App Router every export of a `'use server'`
module is a network-reachable POST endpoint. That is directionally right and **too strong**, and at
least five leads inherited it as a premise. Next only registers the exports its build graph
actually reaches, and that is readable:

```bash
pnpm build && node scripts/audit-server-actions.mjs          # reso, landed this wave
```

`.next/server/server-reference-manifest.js` carries `filename` **and** `exportedName` beside every
action id. The sibling `.json` does **not** — it is keyed by hashed id with no names, so grepping a
name there proves nothing. An earlier pass lost time to exactly that, and to a chunk-grep whose
pattern missed `(0,t.registerServerReference)(`.

**The positive control is not optional and the script enforces it.** Every interesting result here
is a NEGATIVE ("X is not registered"), and a broken parser emits those in bulk, silently and
convincingly. `updateTenantConfig` is known-live (it is confirmed finding #5's subject), so if the
parser cannot find *it*, every negative in that run is an instrument artifact. The script exits 2
rather than reporting.

**Measured on a fresh `next@16.3.5` build of trunk: 92 registered actions** — 64 inside
`src/app/actions/`, 28 outside it.

| export | registered? | what it settles |
|---|---|---|
| `updateTenantConfig` | yes | **positive control** — instrument works |
| `getPlatformDB` | yes | lead 18 confirmed as a live endpoint |
| `setChallengeToCookieStorage` / `setDiscoverableChallengeToCookieStorage` | yes | lead 1 confirmed |
| `getNamedDB`, `getDBAndGroupForSessionTenant`, `getOpenedDatabaseURL` | yes | the DB layer is published |
| `setGuestSession` | **was yes, now no** | the hole this wave closed |
| `initializeDB` | no | **lead 4's reachability premise refuted** |
| `consumeInvitationAndRegister` | no | **lead 3's attack vector refuted** |
| `createEvent` | no | lead 14 is not a direct endpoint |
| `migrateDB`, `initializeDatabase` | no | two W5 candidates refuted |

🚨 **"Not registered" is a dated measurement, never a guarantee.** A later import from a reachable
graph registers an export with no change to the export itself. It also does **not** mean
unreachable: `consumeInvitationAndRegister` and `createEvent` are both reached through other
surfaces (the `/api/register` route handler and the Replicache push path respectively) — what is
refuted is the *direct-action* attack, not the function's existence on a request path.

This also corrects a stale artifact: a prior adjudication rested on a manifest built 2026-07-19
against `next@16.2.6` and recorded "a fresh build showing `initializeDB` registered flips lead 4 to
CONFIRMED CRITICAL" as unsettled. The fresh build above settles it — still unregistered.

---

## Verdict register

Severity is this wave's judgement of *reachable* impact, not the run's original ranking.

| # | Verdict | Evidence | Severity |
|---|---|---|---|
| 1 | **CONFIRMED** | `cookieActions.ts:29,:50` — the expected-challenge setters are registered actions, writing the slot read at `login.ts:92-97,:108`. `login.ts:135-137` says in the repo's own words that for synced iCloud passkeys signCount is permanently 0, so "this challenge is the SOLE replay defense". Precondition: one genuine captured assertion ⇒ replay-defence *removal*, not remote-unauth takeover | high |
| 2 | **CONFIRMED** (blast radius, not an authz hole) | `platformActions.ts:93` matches only `TENANTS[].dbName`, so `parent-schema-database-{lax,singapore,ashburn,dallas}` make `tenant` undefined and the refusal at `:94` never fires. Reachable only from a platform-email session (`:79`) | medium |
| 3 | **REJECTED** | Two independent bounds. `verifyRegistration` returns `{errorMessage}` when `!verification.verified` (`lib/auth/register.ts:135-137`), so the sole caller `api/register/route.ts:60-63,:85` cannot deliver an unverified object; and the function is **not** a registered action, so no direct POST exists. The missing re-test of `.verified` inside `consumeInvitationAndRegister` is real defence-in-depth debt with no reachable exploit | none (debt) |
| 4 | **REJECTED as a live endpoint** / **CONFIRMED as a latent injection** | `initializeDB` has no manifest id on a fresh `16.3.5` build. But `drizzle/db.ts:131` interpolates an unvalidated caller string into the libsql authority, and `@libsql/core` ends the authority at the first `/`, so `"evil.com/x"` would send `TURSO_AUTH_TOKEN_<GROUP>` to an attacker host once any query runs. The **live** endpoint on that same sink is `getNamedDB` (registered) | high (the sink) |
| 5 | **CONFIRMED** | `activeVenueInPullScope` (`homeStateActions.ts:228`) has one consumer (`:404`); `tonight[].event` ships the same rows from an identical predicate and `getTonightEntriesSeed` (`:456-526`) has no gate on a wider surface. Columns are tenant-internal operational + **commercial** config (per-table minimum, tier pricing, staff notes, unannounced drafts) — no guest PII | medium-low |
| 6 | **REJECTED — cured by `1e07c9035`** | `deleteUser` now deletes every `user_venue_role` row keyed on the departing handle inside the removal transaction (`databaseActions.ts:704-706`). The invitation genuinely pins no username and the invitee does choose it freely — but after the cascade there is nothing left to inherit | — |
| 7 | **CONFIRMED** (source) / **BLOCKED** (impact) | `lambdaActions.ts:187` picks the branch from `crossTenant` (arg 8) while the target rides `subdomain`/`group` (args 1-2, `:176-177`), never compared to the sealed tenant; `getPayloadInput:146` opens the victim tenant's DB. Blocked on the IAM policy behind `AWS_ACCESS_KEY_ID` and on what the `RegisterProcessor` Lambda does with the payload — neither is in this repo | high if IAM permits |
| 8 | **CONFIRMED** | Tenant-admin → org-wide control plane. `sendInvitation` is `ensureAdminAccess()`-only and writes a caller-chosen email (`databaseActions.ts:984-996`); `consumeInvitationAndRegister` copies it verbatim into `user.email` (`:1386`); `sessionWrite.ts:207` seals it into the cookie `isPlatformEmail` reads (`platformActions.ts:15`). `PLATFORM_EMAIL_DOMAIN` is a bare `endsWith`. The raw invite token returns to the caller (`:1004`) and the UI renders it as a copyable link, so **no mailbox control is needed** | **critical** |
| 9 | **CONFIRMED** (both halves) | The publish secret is the repo literal `'app-secret'` (`lib/poke/send-poke.ts:175-205`, `soketi-config.json:10`) and is the **live** identity by executable proof — `bootstrap-region.pure.ts:2312-2329` *fails* a bootstrap if a real secret is set. Channels are public but the payload is only `{serverTimestamp, pushRequestId}`, so subscribe is a timing oracle. Publish is the real reach: `handleDeploymentEvent` (`listenActions.ts:295-308`) reloads every connected client | **critical** (operator rotation) |
| 10 | **REJECTED — cured by `1e07c9035`** | Ownership is the username (`replicache-pull/route.ts:86`) and IS now released — `databaseActions.ts:746-756` deletes the client group plus its `replicache_client` / `replicache_cvr` children | — |
| 11 | **REJECTED — by design** | `guest_profile` has **no venue column at all** (`drizzle/schema.ts:553`; ratified as a shared entity in `docs/auth-tenancy/README.md:531-535`), so the tenant-wide read has no venue axis to scope by. The code asymmetry is real — pull passes the tenant-global role (`pullActions.ts:643`) while push uses `resolveVenueRole` (`operationBuilder-shared.ts:547,571`), and `pullActions.ts:21` imports `resolveVenueRole` and never calls it — but `:615-618` states why (an all-venues pull has no active venue) and the consequence claimed is the designed behaviour of a shared entity | — |
| 12 | **CONFIRMED** | Watermark read at `pushActionsBatch.ts:595` (SELECT at `batchPrefetch.ts:707-713`), transaction opens at `:697`, and the write at `operationBuilder.ts:3439-3442` is a blind `SET last_mutation_id = N` with no compare-and-set — while `pushActionsBatch.ts:780-781` asserts "atomic lastMutationID watermark" and is false as written. The vector is the product's **own** retry path: `create-custom-pusher.ts:107-110` aborts at 30 s and returns 503, so Replicache re-pushes while the Lambda still runs. Double-apply target is `updateBottleOrder` — `operationBuilder-bottleService.ts:534,:560` are the only two relative-arithmetic business writes in the tree, and the cancel direction has no clamp, inflating inventory above true stock | high |
| 13 | **CONFIRMED** | `pushActionsBatch.ts:462` persists `mutation.id` — the **client-chosen** id — after the "from the future" throw at `:352-356`. The durable watermark jumps from expected-1 to the client's id and every id in `[expected, mutation.id)` is idempotency-skipped forever at `:625-630`, silently, at HTTP 200. The repo names this exact harm in its own test comment (`pushActionsBatch.test.ts:412-415`, "silent drop of a check-in") for a different door into the same defect; the existing test exercises this path and never asserts the persisted watermark | high |
| 14 | **CONFIRMED** | `createEvent`'s only `tableMapID` check is the same-batch-deleted test (`operationBuilder.ts:1203`); `updateEvent` does existence **and** venue coherence at `:1381-1393`. Impact is corrupt-your-own, not read-another's: every read path is venue-scoped. Actor must already be an admin | low |
| 15 | **CONFIRMED — not cured** | `6e5465a4e` and `04157d23f` bind identity on an axis orthogonal to venue, and the second *widens* the blast radius (two more tenant-global deletes at `:1671`/`:1679`). The tenant-global check survives verbatim at `:1562`. A venue-A-only manager is refused **one** of venue B's reservations at `:2557` but gets **all** of them via `deleteGuestProfile` | high |
| 16 | **CONFIRMED** | `saveSubscription` (`notificationActions.ts:251-262`) stores the endpoint verbatim with zero validation while the sibling writer into the same table validates strictly (`api/notifications/subscribe/route.ts:13-40`). All three named bypasses of the send-time deny-list hold: trailing-dot FQDN at `pushTransport.ts:77`, no DNS resolution step at all (plus a rebinding TOCTOU), and `url.port` is never read. The `https:` pin does kill the HTTP-only cloud-metadata pivot | high |
| 17 | **CONFIRMED**, low | The docblock at `operationBuilder-shared.ts:418-421` promises unrecognized errors "collapse to a generic line"; the body ends `return raw` at `:431`. The single production call site (`pushActionsBatch.ts:437`) is a catch, so every string it sees is a thrown error — exactly the population the docblock wants collapsed — and curated `ERROR_MESSAGES` never reach it, so the existing pass-through test institutionalises a population that does not exist. Leaks schema identifiers (`no such column: …`), protocol internals and mutator field names to a client toast. **No** SQL text, row values, tenant ids or cross-user data | low (hygiene) |
| 18 | **CONFIRMED** (endpoint) / **REFUTED** (token disclosure) | `getPlatformDB` is registered and ungated. But `createClient` returns a **class instance**, and the production flight server refuses it — "Classes or null prototypes are not supported" — so the attacker gets a 500 digest, not the token. The risk is latent: any future `toJSON`/plain-object wrap removes an accidental guard | low / hygiene |
| 19 | **CONFIRMED** | `tenantContext.ts:32-37` (`LOCAL_TEST_*`) precedes both `getTenantFromSession` (`:39-42`) and the `NODE_ENV` branch (`:52`), so a set env var silently repoints away from an authenticated user's sealed tenant. It is the only runtime reader in the tree; no deploy config sets it and no check forbids it. Not remotely triggerable | medium (latent config) |
| 20 | **CONFIRMED** | No per-user row cap (`drizzle/schema.ts:309-318` makes only `endpoint` unique); no concurrency bound at two levels (`pushTransport.ts:138`, `notificationDispatch.ts:409`); the limiter meters **calls** not messages (`durable-limiter.ts:136`) and covers 1 of 3 senders; its 50 ms budget **fails open** (`:162-167`) and its counter lives in the same tenant DB the fan-out hammers, so it goes dark exactly under load | medium |

---

## What this wave changed on trunk

**`setGuestSession` is no longer a network endpoint.** `lib/auth/guest-session.ts` carried
`'use server'`, which published `setGuestSession` — two caller-supplied arguments written straight
into the guest session cookie, no authentication, no claim-token check. Its docblock says "called
ONLY after a claim token has been verified", which binds its internal callers and says nothing
about the caller a registered action has by construction. Because `_actions/submitOrder.ts:82-84`
makes that cookie the **sole** authority for which reservation a guest order belongs to, a writable
cookie made claim-token verification *bypassable*, not merely weak.

All three importers are server-side — `_actions/claim.ts`, `_actions/submitOrder.ts` (both
`'use server'`) and `t/[claimToken]/page.tsx` (an RSC) — so nothing needed these published.
Directive removed, `import 'server-only'` added to keep the build-time guarantee.

**Red-proof, both arms, same positive control:** registered before the change
(`--assert-absent setGuestSession` → exit 1), absent after (exit 0).

The `server-only` landmine recorded at `databaseActions.ts:68,:93` — the specifier is
bundler-vendored and plain Node cannot resolve it — was checked and does not reach here: it bites
only inside the tsx-run DB-setup graph, and no file under `scripts/` or `drizzle/` imports
guest-session.

---

## Disposition of the rest, and why it is not cowardice

reso's own calibration note 5 (`.claude/commands/exhaust-improvements.md`) reads: *"Auth/sync
findings → queue + escalate, never silently land mid-sweep."* Every remaining CONFIRMED lead is
auth/authz-class, so they are recorded here with a fix spec rather than driven. Two carry a further
bar:

- **Lead 9 is credential-rotation class.** Flipping the code first breaks all pokes for ~6 of 8
  tenants with nothing in any log — rotation must set both sides (Soketi env/config **and** SSM +
  region Fly secrets) per region, together, and only then does the code half land.
- **Lead 15 is destructive and irreversible** (hard deletes, no restore path), and its implied
  remedy is **inverted**: `guest_profile` has no `venue_id` and the cascade cites PIPEDA, so a
  venue-filtered erasure would be legally incomplete. The correct direction is to raise the *gate*
  to match the blast radius, never to narrow the deletes.

**Leads 5, 14 and 15 all arm the moment `tenant_config.enable_venue_scoping` flips on** — source
only asserts it is off (`venue-authz.ts:61-62`, default false). Close them before the flip.

Per calibration note 3, leads 5, 14 and 15 are instances of the **S-13 venue-authz** seam already
owned by campaign **C-004** and belong there rather than in a new plan; lead 7 is a distinct
cross-*tenant* seam. Lead 9(a) files **beside** C-009, not inside it — C-009 is subscribe, 9(a) is
publish.

**DO-NOT-FIX:** checked for every lead. No verdict here overturns any of the eight landmines.
`getServerActionSession` is untouched and unrenamed throughout.

---

## Three fixes are landable-now and are still NOT landed, deliberately

Leads 12 (second half), 13 and 17 each have a fix that is byte-identical on the normal path and
touches no authorization logic:

- **13** — at `pushActionsBatch.ts:462` persist `Math.min(mutation.id, prevLastMutationID + 1)`
  (`prevLastMutationID` is already in scope at `:340`). Diverges only on a gap.
- **12, second half** — add `WHERE last_mutation_id < ${lastMutationID}` to the UPSERT at
  `operationBuilder.ts:3439-3443`, making the watermark monotonic. This does **not** fix the
  double-apply on its own.
- **17** — replace `return raw` with a generic retry line, and rewrite the pass-through test whose
  premise is false for this function.

They are recorded rather than driven because reso's calibration note 5 covers **sync** as well as
auth, and all three sit on the live Replicache push path. Lead 12's *first* half — re-asserting the
watermark inside the transaction — additionally introduces a new 5xx at the transaction boundary,
which is a sync-contract change and squarely the operator's.

⚠️ Whichever way that ruling goes, **lead 12's fix must not parallelise mutation application**:
`for…of`+await on Replicache mutations is DO-NOT-FIX landmine #1, where `Promise.all` means silent
data loss.

## The one deployment fact that closes or arms four leads

**The live value of `tenant_config.enable_venue_scoping` in each active tenant DB.** The schema
default is false (`drizzle/schema.ts:365`) and `venue-authz.ts:63-64` *asserts* in a comment that it
is off in every production tenant — a claim with a shelf life, not a measurement. With it OFF,
`resolveVenueRole` returns the global role and push and pull agree exactly.

Leads **5, 14 and 15 arm the moment it flips on**, and lead **11 closes twice over** if it is off
everywhere. It is one read per tenant DB against a column that already exists. Close these before
the flip, not after.
