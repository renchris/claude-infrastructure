# The 19 surfaces the 2026-09-22 Cloudflare audit did not cover — enumerated

**All 19 recorded uncovered units are enumerated below with their four recorded fields, read against
reso `origin/main`, and ranked by downstream relevance to the run's 6 confirmed findings and 20
leads — and the enumeration turned up three things the record itself does not say.** First, **17 of
the 19 were never opened**: every `out_of_scope` unit carries `reviewed_paths: []`, so its `reason`
is the parent's pre-hunt hypothesis, not a reading, and at least one is refuted by the file it
cites. Second, **the uncovered SET is incomplete** — three network-reachable surfaces carry no
ledger unit at all, in neither the covered nor the uncovered column, and one of them
(`src/app/api/replicache-pull/route.ts#POST`) is the sibling of a surface that got two units.
Third, **two readings match the shape the brief names as stop-surface-now** and were reported to the
lead before this document was finished, as candidates and not as findings.

This is a record of **absence of coverage, never absence of defects.** Under reso rule **P2** a
negative search suppresses nothing and under **P3** another producer's coverage does not transfer;
neither does a *reason for not looking*. Nothing below is called clean. Where a reading produced
something that looks live it is labelled **CANDIDATE** and is unverified — this pass executed no
target code, exactly as the parent run could not.

Source of truth: `~/security-audit-skill/reso-src-app-actions/run-1/coverage-ledger.json`, filtered
to `status ∈ {out_of_scope, deferred, blocked}` — 17 + 1 + 1 = 19. The parent write-up
(`cf-audit-reso-actions-2026-09-22.md` § "What this run did NOT cover, by unit") is a rendering of
that filter and agrees with it.

**Coverage is per UNIT — a `surface × boundary × attack-class` tuple — not per file.** A file opened
under one attack class was not thereby examined under all of them, and several files below appear in
the run's *covered* set under a different tuple. That is why `lib/auth/session.ts` can be both the
subject of confirmed finding #1 and an uncovered surface.

---

## Target, and the drift check

- Audit sha: `f87d878d06a0fe89f8916601fb3a5ee3d2f645a9`.
- reso `origin/main` when this was written: `d10b8c1ccc1a8e34c6e58a9d42a06b2c26badc14`, **6 commits
  ahead**.
- `git diff --name-only f87d878d0..origin/main` = `.claude/rules/bottle-generation-ledger.md`,
  `scripts/data/bottle-catalog.ts`, `scripts/data/bottle-image-manifest.json`. **No file named by
  any of the 19 changed**, so every line number and quotation below is true at the audit sha and at
  `origin/main` alike. Four sibling sessions were landing security fixes concurrently; none had
  landed at the time of this read, so a later reader must re-check rather than re-quote.

Read read-only via `git show origin/main:<path>`. No file in `~/Development/reso-management-app` was
written.

---

## Three corrections to the record, before the units

### C1 — 17 of 19 units were never opened, so `reason` is a hypothesis

Every one of the 17 `out_of_scope` units carries `reviewed_paths: []`. Only the **blocked** unit
(#15) has a reviewed set — nine files, because a hunter genuinely worked it — and the **deferred**
unit (#14) was partially read by a sibling unit under a different attack class. So for 17 of 19 the
`unresolved` text is a scope decision written from the outside.

That is not a criticism of the run — recording a surface you did not open is precisely the behaviour
P2 demands — but it changes how the field must be read, and it is demonstrable:

> **Unit 1's reason says** *"amplify.yml:32 curls a jq binary over the network before pnpm migrate
> runs against real Turso."*
>
> **`amplify.yml` at the audit sha** puts the curl at **line 35**, not 32, and lines 31–35 read:
> *"SHA256-pinned (jq 1.7.1 immutable tag) + verified BEFORE chmod: this runs immediately before
> `pnpm migrate` with full-fleet `TURSO_AUTH_TOKEN_*` in scope, so a tampered / MITM'd binary fails
> the build (fail-closed) and never executes"* — followed by an arch-detected `sha256sum -c -` that
> gates the `chmod +x`. Line 32 *is* the comment that refutes the concern.

The file was byte-identical at the audit sha, so this is not drift. The unit's *surface* remains
genuinely uncovered; its stated *reason* does not survive contact with the file.

**Consequence for a later pass:** treat every `reason` on these 17 as a lead to check, never as a
finding to inherit.

### C2 — one path in the 19 does not exist; two known boundary errors are NOT in the 19

`src/middleware.ts` (unit 19) **does not exist** at `origin/main`. The file is `middleware.ts` at
the repository root (`git ls-tree` returns exactly `middleware.ts` and `tests/middleware.test.ts`).
A later pass following the `coverage_id` literally finds nothing and is at risk of recording a
false "not applicable" — the failure mode P2 exists to prevent.

On the brief's instruction to prefer a `parent_boundary_correction` over the parent's hypothesis:
**neither of the ledger's two recorded corrections falls inside the 19.** Both sit on units that
reached a verdict — `pushActionsBatch.ts#push batch entrypoint` (boundary named
`lib/rate-limit/push-limiter.ts`, a file that does not exist; the real control is
`checkPushRateLimitDurable`, `lib/rate-limit/durable-limiter.ts:237`) and `todoActions.ts#list
mutations` (boundary named `authContext.ts#checkListAccess`, a dead export; the live gate is
`validateListAccess`, `operationBuilder-shared.ts:497-505`). Both are still *relevant* here, because
the corrected push limiter is the control on unit 17/18's entry point — so it is recorded, and no
unit below is rendered against a wrong parent hypothesis.

**One boundary inside the 19 is wrong, and this pass corrects it:** see unit 9.

### C3 — three network-reachable surfaces carry no ledger unit at all

A repo-wide census of modules whose **first line** is `'use server'` returns **35** (tests excluded):
18 inside `src/app/actions/` — matching the run's own count of the in-scope endpoint surface — and
17 outside it. Fifteen of those 17 appear somewhere in the 19. **Two do not**, and neither does the
sibling of a route that got two units:

| Unrecorded surface | Why it matters | Status in the ledger |
|---|---|---|
| **`src/app/api/replicache-pull/route.ts#POST`** | The push route got **two** `out_of_scope` units (#17, #18); the pull route got **none** — it appears only inside other units' prose. Unit 18's own text says *"the sibling pull route likely shares it."* codex-security recorded it `deferred_replicache_pull` in July, and under P3 that transfers nothing. | mentioned in 6 units, **surface of 0** |
| **`drizzle/migrate.ts`** | 13 lines, line 1 `'use server'`, `export default migrateDB = async (organizationName: string, group: string)` → `getNamedDB(organizationName, group)` → `migrate(db, …)`. An ungated schema-migration runner against a caller-named tenant database. | **0 mentions** |
| **`drizzle/initializeDatabase.ts`** | 10 lines, line 1 `'use server'`, no exports; its module **body** calls `initializeDB('Good Night','gn','local-development')` at import time. | 1 incidental mention, **surface of 0** |

**Reachability, stated honestly.** `drizzle/migrate.ts` is a **knip entry point** (`knip.json:11`),
i.e. declared as a root consumed from outside the import graph, and nothing in the app imports it;
`drizzle/initializeDatabase.ts` is invoked by `pnpm init-db` via `npx tsx` (`package.json:32`). So
both are most likely CLI files that happen to carry a `'use server'` directive and are most likely
tree-shaken out of the Next server bundle — in which case they receive no action id and are not
endpoints. **"Most likely" is the whole point: that fact lives in
`.next/server/server-reference-manifest.json`, which needs a build, and no producer has ever
recorded either file.** The pull route needs no such caveat — it is a live route handler.

---

## The ranking

Ranked by what the brief asks for: downstream relevance to the 6 confirmed findings and the 20
leads, plus whether the surface is an *entry point above* a lead rather than a peer of one. The
recorded status is carried but does not drive the rank — two `out_of_scope` units outrank the
`blocked` one.

| # | Unit (surface) | Rec. status | Network-reachable today | Why it ranks here |
|---|---|---|---|---|
| 1 | `lib/messaging/guest-message-outbox.ts#enqueue and drain` | out_of_scope | no (plain module; reached from the push route) | The store in which **confirmed #4**'s erasure gap persists, and its recorded boundary is **wrong** — see below |
| 2 | `lib/auth/**#module 'use server' exports` | out_of_scope | **yes** — 9 modules, all POST endpoints | Contains `setGuestSession`, **stop-surface candidate A** |
| 3 | `drizzle/db.ts#getNamedDB` | out_of_scope | **yes** | The sink of **lead 4** and the shape of **lead 18**, ungated; **stop-surface candidate B** |
| 4 | `drizzle/db.ts#getDBAndGroupForSessionTenant` | out_of_scope | **yes** | Its stated control is a *compile-time type*; it is the DB selector of BOTH replicache routes and the decisive fact under unit 15 |
| 5 | `src/app/api/replicache-push/route.ts#POST` × header tenant/venue | out_of_scope | **yes** | Entry point above **leads 9, 12, 13, 17**; envelope-vs-payload confirmed at source |
| 6 | `src/app/actions/replicache/pullActions.ts#pull entrypoint` | **blocked** | no (`import 'server-only'`; entry is the pull route) | Carries **lead 11**; its blocker *is* unit 4's fact |
| 7 | `lib/auth/session.ts#getValidatedSessionCached` | out_of_scope | module is `'use server'`; this fn is private | The predicate under every gate in the run's scope. **Confirmed #1** is one of its three fail-opens |
| 8 | `src/app/api/replicache-push/route.ts#POST` × session boundary | out_of_scope | **yes** | The caller of the entire in-scope replicache library; inherits nothing from codex (P3) |
| 9 | `src/app/(guest)/t/[claimToken]/_actions#guest claim surface` | out_of_scope | **yes** (2 modules) | Lowest-trust principal in the product; the ledger calls it the highest-value remainder |
| 10 | `operationalHistoryActions.ts#getOperatorShiftDetail` | **deferred** | **yes** | **In scope.** Only reader of raw `mutation_log.args`; downstream of **confirmed #3**; its sole gate is the one **lead 8** contests |
| 11 | `drizzle/rp.ts#getRelayingPartySettings` | out_of_scope | **yes** | WebAuthn `rpID`/`origin` from the unvalidated Host; above **leads 1 and 3** |
| 12 | `lib/venue-resolution.ts#getInitialVenues` | out_of_scope | **yes** | Ungated `'use server'` export returning tenant venue config incl. financial rates; above **lead 5** |
| 13 | `lib/auth/venue-authz.ts#getScopingFlag` | out_of_scope | no | The switch deciding whether **any** venue gate runs; **confirmed #5** can flip it, **lead 11** rides it |
| 14 | `src/app/api/notifications/subscribe/route.ts#POST` | out_of_scope | **yes** | The control **lead 16** is measured *against*, so its own correctness is load-bearing |
| 15 | `lib/auth/credential-change-notifier.ts#notifyCredentialAdded` | out_of_scope | no (`import 'server-only'`) | Third caller of the web-push transport; above **lead 20** |
| 16 | `src/app/(app)/**#SSR seed consumers of resolveActiveVenueRow` | out_of_scope | mixed — see below | Above **lead 5**; reachability is **not uniform** across its three paths |
| 17 | `src/middleware.ts#request middleware` | out_of_scope | n/a — path wrong (C2) | Low downstream relevance, **high false-negative risk**: its recorded attack class is not what this file does |
| 18 | `amplify.yml#build pipeline` | out_of_scope | no | Genuinely uncovered class, no auditor owns it — but the recorded reason is refuted (C1) |
| 19 | `src/app/(app)/admin/(settings)/deviceActions.ts#module exports` | out_of_scope | **yes** (1 export) | One gated export; lowest downstream relevance of the 19 |

Addenda from C3, ranked in the same terms: **A1 `replicache-pull/route.ts#POST`** would sit at ~5;
**A2 `drizzle/migrate.ts`** is unrankable until registration is settled — high if registered,
inert if not; **A3 `drizzle/initializeDatabase.ts`** low.

---

## The 19, in rank order

Each carries: **what it is today** (entry point + reachability at `origin/main`) · **recorded
reason** (the ledger's own words) · **boundary** · **the one experiment**.

### 1 — `lib/messaging/guest-message-outbox.ts#enqueue and drain`

- **Recorded** — status `out_of_scope`, wave 2, class
  `DATA-ISOLATION-AND-LIFECYCLE.md#Retention and queued-work overrun`, boundary
  `lib/messaging/guest-message-consent-gate.ts#consent gate`.
- **Reason, verbatim:** *"Outside scope_paths. Raised by h12-replicache-logic: the guest-message
  queue stores a resolved recipient address and a message payload per guest and is reachable from
  the push route (`scheduleGuestMessageDrain` is imported at `src/app/api/replicache-push/route.ts:12-14`).
  It is the store in which one half of the erasure gap this run found actually persists, and its
  send-time consent re-read is the control deciding whether a revoked or erased guest can still be
  messaged. NOT covered."*
- **Today:** 703 lines, **no directive** — neither `'use server'` nor `import 'server-only'`, so it
  is not itself an endpoint. Its network entry is `POST /api/replicache-push`, which calls
  `void scheduleGuestMessageDrain(db, resolveGuestMessageSender())` at `route.ts:409`. Exports
  `enqueueGuestMessage` (:366, takes the caller's `tx`), `drainGuestMessages` (:507),
  `markGuestMessageSent` (:456), `scheduleGuestMessageDrain` (:669).
- 🔧 **BOUNDARY CORRECTION (this pass).** The recorded boundary names the consent gate, and the
  consent gate governs **enqueue only**. `enqueueGuestMessage` calls `liveConsentMatch` (:371) and
  `authoriseGuestSend` (:384) and refuses without a live `guest_consent` row. **`drainGuestMessages`
  performs no consent re-read of any kind** — `liveConsentMatch` / `authoriseGuestSend` /
  `guestConsent` occur in this file only at :371–:389. The drain's sole per-row gate before
  `send(row)` (:594) is `if (row.staleAfter <= Date.now())` (:582), default
  `DEFAULT_STALE_AFTER_MS = 3_600_000` (:96), caller-settable. **Read this unit as having the
  boundary `guest-message-outbox.ts#staleAfter`, not the consent gate.**
- **CANDIDATE, downstream of confirmed #4.** Confirmed #4 establishes that guest erasure leaves
  `guest_message_outbox` rows — recipient **and** body — in place. With no send-time consent or
  existence re-read, a message queued before an erasure is delivered to the erased guest's E.164
  afterwards, for up to `staleAfter`. **Not asserted:** the module header states there is no vendor
  SDK and no HTTP to any provider, and *"Unconfigured means the drain does nothing at all"* — the
  sender is injected (`resolveGuestMessageSender()`), so whether any live sender exists in the
  deployed environment is a deployment fact this pass cannot settle, and it is the difference
  between a live leak and an inert queue.
- **The one experiment:** enqueue one message, run the erasure cascade for that
  `guest_profile_id`, then drain with an instrumented `GuestMessageSender`, and assert on whether
  `send` is called and with what recipient. Settles the whole unit in one run; needs a sandbox.

### 2 — `lib/auth/**#module 'use server' exports`

- **Recorded** — `out_of_scope`, wave 1, class `ATTACK-CLASSES.md#Access control`, boundary
  `lib/auth/session.ts#getServerActionSession`.
- **Reason, verbatim:** *"Outside scope_paths. Nine further true 'use server' modules live under
  `lib/` and are registered POST endpoints exactly like the in-scope ones; three carry
  `no-ungated-db-export` eslint-disable escapes (`lib/auth/login.ts:189,461,474`;
  `lib/venue-resolution.ts:305`; `lib/feature-flags.ts:31`). Not covered by this run."*
- **Today — the count is exactly right.** Nine modules under `lib/` have `'use server'` as their
  first line: `auth/aaguid.ts`, `auth/guest-session.ts`, `auth/login.ts`, `auth/register.ts`,
  `auth/session.ts`, `auth/upgrade.ts`, `feature-flags.ts`, `tenant-display.ts`,
  `venue-resolution.ts`. Every exported async function on each is a POST endpoint by the same rule
  that is the parent run's entire spine.
- 🚨 **CANDIDATE A — reported to the lead before this document was finished.**
  `lib/auth/guest-session.ts` is `'use server'` (line 1) and exports
  **`setGuestSession(reservationID: string, guestClaimID: number)`** at :107 — a session **minter**,
  taking two serializable arguments, writing the sealed `reso-guest-table` cookie via
  `session.save()`. Its own docblock at :106 reads *"Mint the session. Called ONLY after a claim
  token has been verified"* — a true statement about its **internal** callers and silent about the
  caller a `'use server'` export has by construction. If it is registered, it mints a guest table
  session for an arbitrary `reservationID` with **no claim token and no rate limit**, bypassing
  every compensating control `claim.ts:64-76` enumerates (sha256-at-rest matching, active+unexpired
  row, existence-blind failure, per-claim durable rate limit). The module's own sibling
  `getGuestSession` (:96) validates only the cookie's *shape*, and `submitOrder.ts:83` trusts the
  cookie's `reservationID`.
  **The build-time backstop is structurally blind to it:** `eslint-rules/no-ungated-db-export.mjs`
  reports an export only when it finds a **DB-access signal** (`getDB()`, or `db.`/`tx.` + a query
  method, transitively) with no gate. `setGuestSession` touches no database — it writes a cookie —
  so no signal, no report, no disable comment needed.
  **Not asserted:** whether Next registers this export is a property of the built
  `server-reference-manifest`, not of the source.
- **The one experiment:** build, then grep `.next/server/server-reference-manifest.json` for an id
  bound to `setGuestSession`; if present, POST it with a `reservationID` read from another table's
  reservation and check whether the returned cookie authorises `submitGuestOrder` against it.
- **Residual for the same unit, not covered by that experiment:** `login.ts:189/461/474` and
  `feature-flags.ts:31` carry acknowledged pre-auth escapes whose *justifications* nobody has
  re-read; `session.ts` exports `slideSessionIfStale` (:184), a caller-triggerable session-window
  extension; `aaguid.ts` and `tenant-display.ts` have never been examined under any class.

### 3 — `drizzle/db.ts#getNamedDB`

- **Recorded** — `out_of_scope`, wave 1, class
  `DATA-ISOLATION-AND-LIFECYCLE.md#Missing tenant or owner enforcement`, boundary
  `lib/config/tenants.ts#TENANTS manifest`.
- **Reason, verbatim:** *"Outside scope_paths, but it is the SINK of the in-scope Host-header
  tenant-resolution path. In-scope hunters trace INTO it and may cite it as evidence; the module
  itself is not enumerated by this run."*
- **Today:** `drizzle/db.ts` line 1 is `'use server'`, so **every** export is a POST endpoint —
  `evictConnectionByDb` (:88), `getOpenedDatabaseURL` (:108), `getDBAndGroup` (:204), `getNamedDB`
  (:215), `getDBAndGroupForSessionTenant` (:267), `getServerID` (:278) and default `getDB` (:280).
  `getNamedDB(organizationName: string, group: string)` reads **no session**, applies **no gate**,
  and passes both strings to `resolveGroupConfig` (:126), which composes the libsql URL
  (`libsql://${organizationIdentifier}-database-…`) and selects the group's token from
  `TURSO_AUTH_TOKEN_{SINGAPORE,OREGON,LOS_ANGELES,ASHBURN,DALLAS}_GROUP`.
- 🚨 **CANDIDATE B — reported to the lead.** This is the shape of **lead 4** (*"`initializeDB` is an
  unauthenticated Server Action whose caller-supplied database identifier and group compose the
  libsql URL and select the group-wide Turso token"*) — except that here the composing function is
  **itself** the exported endpoint, one frame below the action lead 4 names. It is also the shape of
  **lead 18** (`getPlatformDB`, an ungated action returning a control-plane client). The module's own
  author states the premise at :104-106, guarding `getOpenedDatabaseURL` because *"`'use server'`
  makes every export of this module a callable endpoint, and a connection url is not something a
  production endpoint should be willing to say"* — the reasoning is applied to the URL reader and not
  to the connection openers beside it.
  **Same eslint blindness as candidate A:** these exports *return a handle* and issue no query, so
  the rule's DB-access signal never fires.
  **Not asserted:** a Server Action's return value must be serializable and a Drizzle handle is not,
  so a POST would execute the action and then fail to serialize — which bounds what an attacker
  *reads back*, not what the action *does*. Settling that needs a build and a POST.
- **The one experiment:** build; confirm the ids in `server-reference-manifest.json`; POST
  `getNamedDB` with another tenant's subdomain and a group name and observe (a) whether the action
  executes, (b) what the response carries, (c) whether the connection is cached under
  `${organizationName}:${group}` (:239) where a *subsequent* same-key caller would reuse it.

### 4 — `drizzle/db.ts#getDBAndGroupForSessionTenant`

- **Recorded** — `out_of_scope`, wave 2, class
  `DATA-ISOLATION-AND-LIFECYCLE.md#Composite-key and namespace collision`, boundary
  `lib/auth/session.ts#session.tenant optional field`.
- **Reason, verbatim:** *"Outside scope_paths. Raised by h11-replicache-read-path as its one BLOCKED
  residue: `getDBAndGroupForSessionTenant` is typed to take a session OBJECT precisely so a
  host-derived tenant cannot be passed, but its first statement falls back to `getDBAndGroup()`
  (Host-derived) whenever the argument is undefined, and `tenant` is an OPTIONAL field on the
  session type. The same absence also short-circuits the credentialsVersion revocation check. Who
  can mint or retain a tenant-less session, and whether the deployed edge pins Host to the session
  subdomain, are NOT settled by this run."*
- **Today:** confirmed verbatim. `db.ts:270` is `if (!tenant) return getDBAndGroup()`, and
  `getDBAndGroup` resolves through `getSubdomainAndGroup()` (:178) — the Host path. Both replicache
  routes call it: `replicache-push/route.ts:233` and `replicache-pull/route.ts:233`.
- **The observation the reason does not make.** `db.ts:260-263` states the control in as many words:
  *"The parameter is the session tenant OBJECT, never a string, so passing a HOST-DERIVED tenant is
  a compile error rather than something review has to catch — host-derived selection is the only way
  this could breach tenant isolation."* **That control is a TypeScript type, and this is a runtime
  POST endpoint (unit 3).** Types are erased at runtime, which is the parent run's own structural
  fact #1 — *"there is no runtime schema validation anywhere in it"* — so a direct caller supplies
  `{subdomain, group}` as plain JSON and the compile-time guarantee never executes. The comment's
  own sentence names the consequence: host-derived selection is *the only way this could breach
  tenant isolation*.
- **The one experiment:** two arms. (a) Can a session exist with `user` set and `tenant` absent —
  replay a legacy iron-session cookie, and check whether any deployed edge pins `Host` to the
  session's subdomain. (b) POST `getDBAndGroupForSessionTenant` directly with a forged tenant object
  and observe which database opens. Arm (b) needs only a build; arm (a) needs deployment facts.

### 5 — `src/app/api/replicache-push/route.ts#POST` × header tenant and venue selection

- **Recorded** — `out_of_scope`, wave 2, class
  `PROTOCOLS-RPC-AND-MESSAGING.md#Envelope and payload identity mismatch`, boundary
  `src/app/api/replicache-push/route.ts#tenant and venue selection from request headers`.
- **Reason, verbatim:** *"Outside scope_paths. Raised by h09-replicache-push-protocol: ONE handler
  uses TWO different tenant sources — `session.tenant` selects the tenant DATABASE (`route.ts:233`)
  while `extractTenant(request.headers.get('host'))` (`route.ts:27`) supplies the tenant component of
  the poke topic, the structured log tenant field and the error-handler context; the venue component
  comes from the client-supplied `X-Active-Venue-ID` header defaulted to 'default'.
  `pokeTenantFromHost` has no manifest allowlist and collapses a dotless or absent host to 'unknown'.
  The classic envelope-versus-payload identity mismatch; the sibling pull route likely shares it.
  NOT covered."*
- **Today — every clause confirmed at source, with the line numbers.** `route.ts:27`
  `const tenant = extractTenant(request.headers.get('host'))`; `lib/db-logger.ts:240-242`
  `extractTenant` is a pass-through to `pokeTenantFromHost`; `lib/poke-channel.ts:29-49` returns
  `'unknown'` for an absent host, `host.split('.')[0]` for anything with a dot, and `'local'` for
  `localhost`/`127.0.0.1` — **no manifest allowlist anywhere**. `route.ts:214`
  `const activeVenueID = request.headers.get('X-Active-Venue-ID') ?? undefined`, and the `'default'`
  the reason names appears at the poke call site, `route.ts:340`:
  `sendPoke(userID, group, tenant, activeVenueID ?? 'default', requestId, extraVenueIDs)`. The
  channel name is `` `${tenant}-venue-${venueID}` `` (`poke-channel.ts:51`), i.e. **both components
  are client-controlled headers** while the data being mutated comes from the session's database.
- **Above four leads, not one.** Lead 9 (public Pusher channels with a repository-literal publish
  credential) is the *transport* whose topic this surface names; leads 12, 13 and 17 are all
  properties of the batch this handler dispatches.
- **The one experiment:** POST a push with `Host: <other-tenant>.reso.gl` and
  `X-Active-Venue-ID: <another venue>` under a valid session, then subscribe to
  `<other-tenant>-venue-<another venue>` on Pusher and observe whether the poke — and the log line
  attributing the mutation — land in the wrong tenant's topic.

### 6 — `src/app/actions/replicache/pullActions.ts#pull entrypoint` (BLOCKED)

- **Recorded** — status `blocked`, wave 1, agent `h11-replicache-read-path`, class
  `DATA-ISOLATION-AND-LIFECYCLE.md#Missing tenant or owner enforcement`, boundary
  `src/app/actions/replicache/authContext.ts#prefetchPullAuthContext`. **The only one of the 19 with
  a non-empty `reviewed_paths`** — nine files.
- **Reason, verbatim (two unresolved):** *"Whether an authenticated pull can reach `drizzle/db.ts:270`
  with `session.tenant` undefined. `lib/auth/session.ts:76` makes `tenant` optional, and that branch
  selects the tenant database from the Host header instead of the session; combined with a username
  that exists in the host-named tenant, it would read another tenant's database under this session.
  Source cannot settle whether any live or legacy iron-session cookie lacks the tenant field, nor
  whether the deployed edge pins Host to the session's own subdomain."* · *"Whether
  `REPLICACHE_PULL_CURSOR_GATE` is 'on' in any deployed environment. The value is an env var read at
  `pullActions.ts:577` and is the switch that decides whether the pull's revocation behaviour depends
  on the sync watermark's trigger coverage at all."*
- **Today:** `pullActions.ts` is 1,052 lines and begins `import 'server-only'` — it is **not** an
  endpoint. Its network entry is `POST /api/replicache-pull` (`route.ts:36`), which resolves the DB
  at `route.ts:233` through exactly the function in unit 4.
- **Its blocker is unit 4's fact.** Both unresolved questions are deployment facts, and the first is
  word-for-word unit 4's question. The two should be worked as one.
- **The one experiment:** the same two arms as unit 4, plus one read of the deployed environment for
  `REPLICACHE_PULL_CURSOR_GATE`. If arm (b) of unit 4 shows the tenant object is caller-supplied at
  the endpoint, the "legacy cookie" question stops being the only route to the branch.

### 7 — `lib/auth/session.ts#getValidatedSessionCached`

- **Recorded** — `out_of_scope`, wave 2, class
  `DATA-ISOLATION-AND-LIFECYCLE.md#Stale authorization and derived copy use`, boundary
  `lib/auth/session.ts#credentialsVersion revocation check`.
- **Reason, verbatim:** *"Outside scope_paths, and it is the layer every gate in `src/app/actions`
  ultimately rests on. Raised independently by h03 and h05: the revocation check is guarded on
  `row &&` at :159, so a user row DELETED by `deleteUser` leaves `session.user` intact; the catch at
  :162-164 is fail-open on a read error; and :147 returns early for any sealed payload lacking a
  tenant, skipping the check entirely. The in-scope CONSEQUENCES are covered by this run's
  candidates; the predicate itself is not enumerated here."*
- **Today — all three fail-opens confirmed at the stated lines.** :144 `getValidatedSessionCached` is
  module-private; :147 `if (!user || !tenant) return session`; :159
  `if (row && (user.credentialsVersion ?? 0) < row.credentialsVersion)`; :162-164 bare `catch {}`
  documented as fail-open at :139-142 (*"Failing closed would sign out an entire venue mid-shift on a
  DB blip"*). The module is `'use server'`, so its endpoints are `slideSessionIfStale` (:184) and the
  default export `getServerActionSession` (:194); the predicate itself is reached through them and
  through every importer.
- **Why the distinction matters.** **Confirmed #1** is the `row &&` arm — one of three. The `!tenant`
  early return (:147) and the `catch` (:162) are the other two, and neither is the subject of a
  finding: a fix to :159 alone leaves both live. The :147 arm is also the *same* condition unit 4 and
  unit 6 turn on, so one sealed payload without a tenant skips revocation **and** selects the
  database from the Host header.
- **The one experiment:** seal three payloads — user+tenant with a stale `credentialsVersion`,
  user+**no** tenant, and user+tenant against a DB that errors — and assert which of the three
  resolves to a live `session.user`. Runs offline against the module; needs only `node_modules`.

### 8 — `src/app/api/replicache-push/route.ts#POST` × session boundary

- **Recorded** — `out_of_scope`, wave 1, class
  `PROTOCOLS-RPC-AND-MESSAGING.md#Envelope and payload identity mismatch`, boundary
  `lib/auth/session.ts#getServerActionSession`.
- **Reason, verbatim:** *"Outside scope_paths (`src/app/actions/`). It is the caller of the in-scope
  replicache library and was only partially covered by codex-security (replicache-pull recorded
  `deferred_replicache_pull`); it inherits nothing from that run under rule P3."*
- **Today:** 482 lines. `POST` at :25. Session gate → 401 at :150-160; `const { username: userID } =
  user` at :162 — **keyed on the recyclable username**, the run's structural fact #2 and the
  mechanism of **lead 10**. Rate limit `checkPushRateLimitDurable(userID)` at :166 — this is the
  control the ledger's **first `parent_boundary_correction`** identifies (`durable-limiter.ts:237`),
  so the corrected boundary is the one that governs here. CSRF same-origin gate at :34-77 and
  Content-Type pin at :79-127, **both defaulting to `'report'`**
  (`process.env.PUSH_ORIGIN_CHECK ?? 'report'`, :34) — logging, not enforcing, unless the deployed
  environment sets `enforce`.
- **The one experiment:** read the deployed `PUSH_ORIGIN_CHECK`. If it is unset or `report`, the
  CSRF posture of the whole push surface is report-only, and every lead about push replay
  (12, 13) gains a cross-origin delivery path. One environment read settles it.

### 9 — `src/app/(guest)/t/[claimToken]/_actions#guest claim surface`

- **Recorded** — `out_of_scope`, wave 1, class `ATTACK-CLASSES.md#Access control`, boundary
  `lib/auth/guest-session.ts#guest session`.
- **Reason, verbatim:** *"Outside scope_paths, and it is the LOWEST-trust surface in the product: an
  unauthenticated guest holding only a claim token, with an acknowledged pre-auth
  `no-ungated-db-export` escape at `claim.ts:77`. Highest-value remainder for a next run."*
- **Today:** two `'use server'` modules. `claim.ts:78` `claimGuestTable(rawToken)` — pre-auth by
  design, with the escape at :77 and a 23-line rationale at :54-76 enumerating five compensating
  controls; the implementation matches the rationale line for line (sha256-at-rest match at :81,
  `status='active'` + unexpired at :94, per-claim durable rate limit at :100, one frozen `FAILURE`
  object on every failure path, raw token never logged at :113). `submitOrder.ts:74`
  `submitGuestOrder` reads `getGuestSession()` at :83.
- **Open question this pass surfaces, not a claim:** `claim.ts:105-108` sets `claimedAt` and
  `updatedAt` but **does not change `status`**, which remains `'active'` — so the `where` at :94
  still matches on a later call and one token appears to mint unbounded guest sessions until
  `expiresAt`. That may be the intended lifecycle (a table's guests share a QR), and nothing here
  settles it. Its consequence is bounded by candidate A: if `setGuestSession` is directly callable,
  the token lifecycle stops mattering at all.
- **The one experiment:** replay one valid claim token N times and assert on the number of distinct
  sealed cookies minted and on the `guest_claim` row's terminal state.

### 10 — `src/app/actions/operationalHistoryActions.ts#getOperatorShiftDetail` (DEFERRED)

- **Recorded** — status `deferred`, reason code `late_uncovered_no_remaining_wave`, wave 2, class
  `DATA-ISOLATION-AND-LIFECYCLE.md#Analytics, logs, traces, and diagnostics as alternate readers`,
  boundary `lib/operational-detail.ts#formatOperationalDetail projection`.
- **Reason, verbatim:** *"IN SCOPE but DEFERRED — surfaced too late in the run to fund a hunter, and
  recorded rather than silently dropped. Raised by h12-replicache-logic: `getOperatorShiftDetail` is
  the ONLY reader of raw `mutation_log.args`, the server-only blob the schema labels as possibly
  containing guest PII, and it is the downstream half of BOTH the erasure redaction and the
  over-redaction candidate this run reports. h07-seed-history covered this file under Enumeration and
  aggregate oracles and verified the gate placement and the allow-list projection, but the READER
  side of that store — how much PII a platform-gated operator sees through
  `lib/operational-detail.ts` — is a distinct boundary that no unit owns."*
- **Today:** `operationalHistoryActions.ts` is `'use server'`; `getOperatorShiftDetail` at :142 is a
  POST endpoint. Its sole authorization is `if (!isPlatformEmail(session.user.email))` at :149 —
  matching its sibling at :76. The docblock at :134-138 states the PII contract and calls the email
  *"the AUTHORITATIVE session email."* `lib/operational-detail.ts` is a plain module: a per-mutator
  allow-list returning a projected **string**, coarse-by-default for unknown mutators (:106-107),
  with `sanitizeErrorReason` (:123) for the raw error text.
- **Why it ranks above six `out_of_scope` units.** It is the **only in-scope** member of the 19; it
  is the reader of the store **confirmed #3** writes into with an unvalidated `instr()` pattern; and
  its one gate is precisely the gate **lead 8** contests — *"platform-operator authority is decided by
  an email string a tenant admin writes into their own tenant's user table."* If lead 8 confirms, a
  tenant admin reaches this reader. The gate also reads the **sealed cookie's** email, which is the
  same class as **confirmed #5** (sealed role, not live role) on a different column.
- **The one experiment:** feed `formatOperationalDetail` the raw `args` of every mutator that writes
  guest PII and diff the projected string against the allow-list — the question is what the
  coarse-by-default branch emits for a mutator the allow-list does not name.

### 11 — `drizzle/rp.ts#getRelayingPartySettings`

- **Recorded** — `out_of_scope`, wave 2, class
  `WEB-PROTOCOL-AND-AUTH.md#WebAuthn and passkey verification`, boundary
  `src/app/actions/auth/domainActions.ts#getSubdomain`.
- **Reason, verbatim:** *"Outside scope_paths (`src/app/actions/`). Raised by h04-auth-tenant-resolution:
  the WebAuthn relying-party id and expected origin are derived from the same unvalidated Host header
  this run traced as a tenant-database selector (`rpID = ${subdomain}.${PASSKEY_AUTHENTICATION_RPID}`),
  so the ceremony's expected values are request-controlled on both registration and login, and
  `rp.ts:15-26` carries dev branches with no `NODE_ENV` guard exactly as `domainActions.ts:51-66`
  does. Its use as a DATABASE selector is covered by this run; its use as an AUTHENTICATION parameter
  is a different boundary and is NOT covered."*
- **Today:** 40 lines, `'use server'`, one default export. Confirmed: `rpID`/`origin` are built from
  `getSubdomain()` + `getRootDomain()` + `getProtocol()` (:9-13), and the three dev branches —
  `localhost:` (:15), the literal LAN address `172.16.47.249:` (:20), and
  `ngrok-free.app`/`ngrok.io` (:24) — carry **no `NODE_ENV` guard**, so a request whose Host matches
  any of them selects a dev branch wherever this runs. The production arm (:28-29) is
  `${subdomain}.${PASSKEY_AUTHENTICATION_RPID || 'reso.gl'}`.
- **Above two leads.** Lead 1 (replayable WebAuthn challenge slot) and lead 3
  (`consumeInvitationAndRegister` trusting a caller-supplied verification result) both concern the
  ceremony whose **expected values this function supplies**. A pass that confirms either without
  covering this is reasoning about a ceremony with one input unexamined.
- **The one experiment:** issue a registration and a login with `Host: x.ngrok-free.app` and with a
  dotless host, and record the `rpID`/`origin` the ceremony verifies against versus the ones the
  client asserted.

### 12 — `lib/venue-resolution.ts#getInitialVenues`

- **Recorded** — `out_of_scope`, wave 2, class
  `DATA-ISOLATION-AND-LIFECYCLE.md#Missing tenant or owner enforcement`, boundary
  `lib/auth/session.ts#getServerActionSession`.
- **Reason, verbatim:** *"Outside scope_paths. Raised by h07-seed-history: `lib/venue-resolution.ts`
  carries a module-level 'use server' directive, so `getInitialVenues` is a registered POST endpoint
  that reads no session and applies no gate, returning every venue row of the Host-resolved tenant
  including tax rate, gratuity rate, deposit percent and bottle storage fee. Its eslint-disable at
  :305 justifies the exemption as an SSR seed the pull syncs to authed clients anyway, but nothing on
  the path establishes that the caller IS authed. NOT covered by this run."*
- **Today — confirmed field by field.** :1 `'use server'`; :305 the disable with the justification
  *"SSR seed of own-tenant venue config"* and a three-line C-007 allowlist note at :302-304;
  :306-335 `getInitialVenues` calls `getDB()` and returns every `venue` row mapped to 24 fields
  including `taxRateBps`, `gratuityRateBps`, `autoGratuity`, `defaultDepositPercent`,
  `bottleStorageFee`. It reads no session — `getServerActionSession` is imported at :14 but used by
  `resolveActiveVenueRow` (:220), a different export.
- **The tenant it returns is Host-resolved**, via `getDB()` → `getConnectionParams` →
  `getSubdomainAndGroup()`, so the caller chooses which tenant's config to read by setting Host —
  the same axis as units 3, 4, 5 and 11. Above **lead 5**.
- **The one experiment:** POST `getInitialVenues` with no session cookie and `Host:` set to each
  tenant in the manifest, and diff the returned rows against what that tenant's authed pull delivers.

### 13 — `lib/auth/venue-authz.ts#getScopingFlag`

- **Recorded** — `out_of_scope`, wave 2, class
  `DATA-ISOLATION-AND-LIFECYCLE.md#Stale authorization and derived copy use`, boundary
  `lib/auth/venue-authz.ts#FLAG_TTL_MS module cache`.
- **Reason, verbatim:** *"Outside scope_paths. Raised by h10-replicache-write-authz: the module-level
  TTL cache that decides whether ANY venue gate runs is a distinct boundary from `canAccessVenue`.
  Cross-tenant bleed was refuted in-run (the WeakMap key is the per-tenant drizzle singleton), but the
  OFF→ON staleness window applies to the WRITE path as well as the documented read path, so for up to
  FLAG_TTL_MS after a rollout flip every per-mutation venue gate still returns allow. Cache-key
  identity across warm Lambda invocations and `primeScopingFlag`'s swallowed error are NOT covered."*
- **Today:** the module has **no** directive (not an endpoint). `FLAG_TTL_MS` defaults to `600_000`
  (:82-85, overridable by `VENUE_SCOPING_FLAG_TTL_MS`, `0` disables caching); the cache is a
  module-level `WeakMap` keyed on the `db` handle (:88); `getScopingFlag` (:100-112) returns the
  cached value inside the TTL; `primeScopingFlag` (:121-127) swallows every error; `canAccessVenue`
  is at :289 and the gate that consults the flag returns `true` when it is off (:310).
- **An observation the reason does not make:** `:109` is `const value = cfg?.enabled ?? false` — a
  **missing `tenant_config` row yields `false`, i.e. scoping OFF, i.e. every venue gate allows.**
  Whether provisioning guarantees the singleton row exists in every live tenant database is a
  data-state fact this pass cannot settle, and it is a different question from the TTL window.
- **Interaction with confirmed #5,** which establishes that `updateTenantConfig` authorizes on the
  sealed cookie role and can set `enableVenueScoping` false: a flip to **false** takes effect for
  new reads immediately, while a flip to **true** is invisible to a warm container for up to
  `FLAG_TTL_MS`. The two directions are not symmetric and only one is documented (:76-81).
- **The one experiment:** flip the flag on, and within the TTL issue a push mutation from a
  venue-demoted user on a warm container; assert on whether `canAccessVenue` denies.

### 14 — `src/app/api/notifications/subscribe/route.ts#POST`

- **Recorded** — `out_of_scope`, wave 2, class `ATTACK-CLASSES.md#Access control`, boundary
  `src/app/api/notifications/subscribe/route.ts#ALLOWED_PUSH_DOMAINS`.
- **Reason, verbatim:** *"Outside scope_paths. Raised by h08-notifications: a second, structurally
  different write path into `push_subscription` with its own origin check, content-type gate,
  ALLOWED_PUSH_DOMAINS allowlist and key-format validation, plus an `oldEndpoint`
  delete-then-insert replacement and a 409 conflict path. It is the control the in-scope action path
  diverges from, so its own correctness is load-bearing on that comparison and is NOT covered here."*
- **Today:** 239 lines. `POST` at :46; session gate at :57-58; origin gate at :62-76 and content-type
  pin at :84-112, **both defaulting to `'report'`** exactly as the push route does; the allowlist at
  :13-26 matches with `url.hostname === domain || url.hostname.endsWith('.'+domain)`; the row is
  keyed `userID: session.user.username` (:146, :158) — the recyclable handle again, which is the
  mechanism of **confirmed #2**'s surviving push delivery; `oldEndpoint` replacement at :162-166;
  409 at :200.
- **Why its own correctness is load-bearing.** **Lead 16** says `saveSubscription` stores a
  caller-supplied endpoint URL with no validation and that the *send-time* deny-list is passed by a
  trailing-dot FQDN, a private-pointing public DNS name, or a non-443 port. The comparison that makes
  lead 16 a defect is *"this route has an allowlist and the action does not"* — so an untested
  allowlist is an untested premise. The `endsWith('.'+domain)` form and the report-only origin gate
  are the two places to look first.
- **The one experiment:** drive the allowlist with the same corpus lead 16's `validation_plan` uses
  against the send-time deny-list, and diff which inputs each accepts.

### 15 — `lib/auth/credential-change-notifier.ts#notifyCredentialAdded`

- **Recorded** — `out_of_scope`, wave 2, class
  `RESOURCE-EXHAUSTION-AND-AVAILABILITY.md#Retry storm and fail-open amplification`, boundary
  `src/app/actions/notifications/pushTransport.ts#sendToSubscriptions`.
- **Reason, verbatim:** *"Outside scope_paths. Raised by h08-notifications: a third caller of the
  web-push transport, reached from the credential-change path rather than from an admin action,
  fanning out over the same unvalidated and uncapped `push_subscription` rows. It carries neither the
  admin gate nor the 30/min limiter that bounded the in-scope `sendTestNotification` trigger, so the
  bounds question this run settled for one trigger is OPEN for this one."*
- **Today:** the module is `import 'server-only'` (:30) and its header at :4 states the choice
  explicitly — *"Server-internal. `import 'server-only'`, never `'use server'`"* — so it is **not** an
  endpoint, and the reason does not claim it is. Its one production caller is `lib/auth/upgrade.ts:291`
  (`completePasskeyUpgrade`, itself a `'use server'` export), so the reachable path is
  POST → `completePasskeyUpgrade` → `notifyCredentialAdded` → `sendToSubscriptions` (:121).
- **The bound it does carry, which the reason does not mention:** a `NOTIFY_BUDGET_MS` race (:110-132)
  with a distinct `TIMED_OUT` sentinel, a timer cleared in `finally`, and a top-level `catch` that
  returns `EMPTY` (:141-145). So the *retry-storm* half of its attack class is bounded; the
  **fan-out** half is not — the subscription rows are selected with no cap (:87-91), which is exactly
  **lead 20**'s *"no per-user row cap and no concurrency bound."*
- **The one experiment:** seed N `push_subscription` rows for one username and call
  `completePasskeyUpgrade`; measure sends issued and wall time against `NOTIFY_BUDGET_MS`, and whether
  the budget expiring leaves sends in flight.

### 16 — `src/app/(app)/**#SSR seed consumers of resolveActiveVenueRow`

- **Recorded** — `out_of_scope`, wave 2, class
  `DATA-ISOLATION-AND-LIFECYCLE.md#Missing tenant or owner enforcement`, boundary
  `lib/auth/venue-authz.ts#canAccessVenue`.
- **Reason, verbatim:** *"Outside scope_paths. Raised by h07-seed-history: the unreachable-venue state
  produced by `lib/venue-resolution.ts:277`'s `?? activeVenues.at(0)` last-resort fallback reaches at
  least three further SSR seeds outside `src/app/actions/`. `floor-plan/initialData.ts:383-413` and
  `:692-698` filter on venueID with no authorization at all. Whether each re-derives the reachable
  set or trusts the resolved venue is the same question this run answered for the home seeds, on
  files it may not assign."*
- **Today — and the reachability is NOT uniform across the three paths**, which the unit's single
  boundary hides:
  - `src/app/(app)/floor-plan/initialData.ts` — `import 'server-only'` (:5), **not** an endpoint.
    `getSelectionCore(venueID)` at :383 and `getDefaultEventID(venueID)` at :692 confirmed: six
    queries filtered on `venueID` with **no authorization call anywhere in either**.
  - `src/app/(app)/guests/initialData.ts` — **no directive at all**, not an endpoint; it does import
    `prefetchPullAuthContext` (:14), so an authorization context is at least present on this path.
  - `src/app/(app)/bottle-service/[reservationID]/_data/seed.ts` — **`'use server'` (:1)**, so
    `getCatalogSeed` (:131) and `getBottleSeeds` (:169) **are POST endpoints**; both read
    `getServerActionSession()` (:133, :171) and both carry an in-file comment (:96, :203) conceding
    *"activeVenueID comes from `resolveActiveVenueRow` (no RBAC)."*
  The fallback the reason names is confirmed at `venue-resolution.ts:276-277`:
  `preferLocalSubdomain(activeVenues.filter(v => reachable.has(v.id))) ?? activeVenues.at(0)` — the
  last-resort arm returns a venue that is **not** in the reachable set.
- **The one experiment:** give a user a reachable set that is empty for the tenant, then load each of
  the three seeds and record which venue's rows come back — `activeVenues.at(0)`'s or none.

### 17 — `src/middleware.ts#request middleware`  ⚠ path error, see C2

- **Recorded** — `out_of_scope`, wave 1, class
  `WEB-PROTOCOL-AND-AUTH.md#Host and forwarded-header trust`, boundary `src/middleware.ts#matcher`.
- **Reason, verbatim:** *"Outside scope_paths. Covered by codex-security at `e6ead3ce5` (2026-07-29),
  but under rule P3 this cloudflare run inherits nothing from that record; it is simply not covered
  here."*
- **Today:** the file is **`middleware.ts` at the repository root**, 107 lines. It does two things:
  sets `x-pathname` on the forwarded request (:60-61), and in production only (:63) generates a
  per-request CSP nonce and sets the policy on both the forwarded request and the response
  (:67-79). **It performs no authentication, no authorization, no tenant resolution, and no Host or
  `x-forwarded-host` validation of any kind.** Its `matcher` (:82-107) — the recorded boundary, and
  it *is* real — excludes `_next/static`, `_next/image`, `favicon`, `sw.js`,
  `manifest.webmanifest`, **`api`**, `preview` and `vt-ref`.
- **The false-negative risk, which is why this is worth a row despite ranking 17th.** A later pass
  told to examine *Host and forwarded-header trust* at `src/middleware.ts` will find no file; if it
  resolves the path and reads `middleware.ts`, it will correctly find no Host handling and may record
  the class as not applicable. **Neither outcome is true of the repository**, where Host trust is
  live in `domainActions.getSubdomain`, `drizzle/db.ts`, `drizzle/rp.ts` and `pokeTenantFromHost`
  (units 3, 4, 5, 11 above). And the matcher's `api` exclusion means every surface in units 5, 8 and
  14, plus addendum A1, runs with **no middleware at all**.
- **The one experiment:** none needed for the path correction. For the class: enumerate every reader
  of `host` / `x-forwarded-host` repo-wide and test each against a forged value — the class belongs
  to those readers, not to this file.

### 18 — `amplify.yml#build pipeline`

- **Recorded** — `out_of_scope`, wave 1, class
  `SUPPLY-CHAIN-AND-RELEASE.md#Untrusted code in a privileged workflow`, boundary
  `scripts/land-status.sh#deploy gate`.
- **Reason, verbatim:** *"Outside scope_paths. The applicability mapping scores supply-chain/release
  medium-high for reso and records that no auditor covers it; this scoped run does not change that.
  `amplify.yml:32` curls a jq binary over the network before `pnpm migrate` runs against real Turso."*
- **Today — the stated concern is refuted by the file itself (see C1).** The curl is at :35, not :32,
  and it is SHA256-pinned per architecture with `sha256sum -c -` gating the `chmod +x`, in a
  fail-closed `||` chain, documented at :31-34 in terms that name the exact risk. Line 32 is part of
  that comment.
- **What remains genuinely uncovered** — the *class*, which the first sentence of the reason states
  correctly and which no auditor owns: `corepack prepare pnpm@11.11.0 --activate` (:21) overriding
  `package.json`'s `packageManager` and needing hand-sync across three files (:10-19 records a
  six-week skew from exactly this); `pnpm install --frozen-lockfile` (:23) under
  `pnpm-workspace.yaml`'s `allowBuilds`; and the flag-gated parallel path (:54-60) that forks
  `pnpm migrate` against the whole fleet concurrently with `next build`, with
  `TURSO_AUTH_TOKEN_*` for every group in scope.
- **The one experiment:** not a runtime one. Diff the three pinned pnpm versions
  (`amplify.yml:21`, `Dockerfile:14`, `package.json#packageManager`) and enumerate every
  `allowBuilds` entry against its package's install scripts — the class is a static one.

### 19 — `src/app/(app)/admin/(settings)/deviceActions.ts#module exports`

- **Recorded** — `out_of_scope`, wave 1, class
  `WEB-PROTOCOL-AND-AUTH.md#WebAuthn and passkey verification`, boundary
  `lib/auth/session.ts#getServerActionSession`.
- **Reason, verbatim:** *"Outside scope_paths. Two further 'use server' modules sit under `src/app/`
  but outside `src/app/actions/`; `deviceActions.ts` touches the credential/device surface."*
- **Today:** 62 lines, `'use server'`, **one** export — `renameCredential(credentialID, name)` at
  :25. Session read at :29, `userID` taken from the session and never from input (:31),
  `Number.isInteger` on the id (:33), name normalised (:34), and the ownership predicate placed
  **inside** the single `UPDATE` (:42) with the docblock at :20-23 naming the TOCTOU reason. The
  unit's "two further modules" are this one and `bottle-service/…/_data/seed.ts`, which is covered
  under unit 16 above.
- **Not a clean verdict — a scope statement.** This is the lowest-downstream-relevance member of the
  19: one export, a display-name write, gated. Its recorded attack class (WebAuthn/passkey
  verification) barely engages a rename. But no unit examined it, and P2 forbids converting "we
  looked and it seemed fine" into coverage.
- **The one experiment:** assert `renameCredential` returns the same `'Device not found.'` for a
  foreign `credentialID` as for a non-existent one — i.e. that the zero-row result is not an
  existence oracle.

---

## The candidates this pass produced

Recorded here so they are not lost, and **none of them is a finding.** No target code was executed;
each needs the experiment named beside it.

**Three of them turn on one shared fact and the lead owns it** (ruling 2026-09-22): whether Next
registers a given `'use server'` export as a callable action is readable from a built
`.next/server/server-reference-manifest.json`, which needs a `pnpm build` in reso. That build
contends with the wave-1 land queue, so the lead runs it once the four branches land. **This wave
does not run it and does not enter the reso repo.** § Manifest lookup keys below is the hand-off.

| # | Where | Shape | Escalated |
|---|---|---|---|
| CAND-1 | `lib/auth/guest-session.ts:107` `setGuestSession` (unit 2) | `'use server'` export minting a guest session from two caller-supplied arguments; docblock's "called ONLY after a claim token has been verified" governs internal callers only; eslint backstop blind (no DB signal) | **yes** — lead, before this doc |
| CAND-2 | `drizzle/db.ts:215` `getNamedDB` + `:267` `getDBAndGroupForSessionTenant` (units 3, 4) | `'use server'` exports opening a connection to a caller-named tenant DB with that group's token; the stated control on the second is a compile-time **type** on a runtime endpoint; eslint backstop blind (returns a handle, issues no query) | **yes** — lead, before this doc |
| CAND-3 | `guest-message-outbox.ts` drain (unit 1) | No send-time consent or existence re-read; the only per-row gate is `staleAfter`. Downstream of **confirmed #4**. Bounded by whether a live sender is configured | in this doc |
| CAND-4 | `drizzle/migrate.ts` (C3) | `'use server'` module exporting an ungated migration runner against a caller-named database; in **zero** ledger units; a knip **entry point**, so probably outside the Next bundle — which is the fact to settle | in this doc |
| CAND-5 | `venue-authz.ts:109` `cfg?.enabled ?? false` (unit 13) | A missing `tenant_config` row yields scoping OFF, i.e. every venue gate allows. Data-state fact, unsettled | in this doc |
| CAND-6 | `claim.ts:105-108` (unit 9) | `claimedAt` is set but `status` stays `'active'`, so the `where` at :94 still matches — one token may mint unbounded sessions until `expiresAt`. May be the intended lifecycle | in this doc |
| CAND-7 | `replicache-pull/route.ts` (C3/A1) | The pull route has **0** `checkSameOrigin`/`requireJsonContentType` call sites against the push route's **4**, while the session cookie is `SameSite=none` in production — the exact condition the push route's own comment (:29-33) gives for needing the gate | in this doc |

---

## Manifest lookup keys — the hand-off for CAND-1, CAND-2 and CAND-4

For the lead's post-land `pnpm build`. Every row is *exact export name · `file:line` · the one
question the manifest answers.*

⚠ **The manifest keys actions by a HASHED id, not by export name, so this is a two-step lookup, and
step 1 is the one that can silently return nothing.** A bare
`grep setGuestSession .next/server/server-reference-manifest.json` finding no match means *nothing
about registration* — the name is not what the file holds.

```
STEP 1 — is the module in the server bundle at all, and is the export wrapped?
  grep -rl '<exportName>' .next/server/ | head
  # then, in the chunk that matched, find the id bound to it:
  grep -o 'registerServerReference([^)]*<exportName>[^)]*)' <chunk>
  # (Next wraps a registered action as registerServerReference(fn, "<id>", null);
  #  an export present in the bundle but NOT so wrapped is code, not an endpoint.)

STEP 2 — is that id in the manifest's dispatch map?
  jq '.node | keys' .next/server/server-reference-manifest.json | grep '<id>'
```

🚨 **Run the positive control in the same pass, or a row of "not found" is uninterpretable.**
`updateTenantConfig` (`src/app/actions/tenantConfigActions.ts`) is a **known-live** action — it is
the subject of **confirmed finding #5**, which rests on it being a reachable endpoint. If the recipe
above cannot find *it*, the recipe is wrong and every negative below is an instrument artifact, not
a fact. A null from a blind instrument is not absence.

| Cand | Export(s) to look up | `file:line` | The one question the manifest answers |
|---|---|---|---|
| **CTRL** | `updateTenantConfig` | `src/app/actions/tenantConfigActions.ts` (confirmed #5 cites `:37`, `:78`) | Does the recipe find a known-live action? **If no, stop — every result below is void.** |
| **CAND-1** | `setGuestSession` | `lib/auth/guest-session.ts:107` | Can a guest table session be minted by POST, for an arbitrary `reservationID`, with no claim token? |
| CAND-1b | `clearGuestSession` · `getGuestSession` | `lib/auth/guest-session.ts:118` · `:96` | Same module — is the whole guest-session namespace POST-callable, i.e. can a third party destroy or read a guest's session? |
| **CAND-2** | `getNamedDB` | `drizzle/db.ts:215` | Can an unauthenticated POST open a connection to a **caller-named** tenant database using that group's Turso token? |
| CAND-2b | `getDBAndGroupForSessionTenant` | `drizzle/db.ts:267` | Is the "session tenant OBJECT, never a string" control (`:260-263`) reachable as an endpoint — where the type is erased and the caller supplies the object? |
| CAND-2c | `getDBAndGroup` · `getOpenedDatabaseURL` · `evictConnectionByDb` · `getServerID` · default `getDB` | `drizzle/db.ts:204` · `:108` · `:88` · `:278` · `:280` | Which of the module's seven exports carry an id — i.e. how wide is the surface the `'use server'` at `db.ts:1` opens? (`getOpenedDatabaseURL` is already guarded on `NODE_ENV`; `evictConnectionByDb` is a cache eviction an outsider could drive.) |
| **CAND-4** | default `migrateDB` | `drizzle/migrate.ts:7` (def) · `:13` (`export default`) | Is this module in the bundle at all, or tree-shaken as its knip **entry-point** status (`knip.json:11`) suggests? If it carries an id, an ungated schema migration runs against a caller-named database. |
| CAND-4b | *(no exports)* | `drizzle/initializeDatabase.ts:10` | Different question — not "is there an endpoint" but "is the module in the server bundle", since its **body** calls `initializeDB('Good Night','gn','local-development')` at import time. |

**How to read each outcome.** *Id present* ⇒ the candidate is live as described and becomes a
finding for a fix wave. *Module in the bundle but the export not wrapped* ⇒ the candidate is
refuted on reachability and the shape is a latent hazard for the next edit — record it, do not fix
it. *Module absent from the bundle* ⇒ refuted, and the `'use server'` directive on that file is
directive hygiene, worth deleting so the next reader is not misled.

---

## What a later whole-repo pass must do

1. **Do not inherit any of the 19 as covered, and do not inherit their reasons either** (C1). Each
   `reason` is a lead to re-check; one of them is already refuted by its own file.
2. **Fix the record before working it:** `src/middleware.ts` → `middleware.ts` (C2); read unit 1's
   boundary as `guest-message-outbox.ts#staleAfter`; read the two `parent_boundary_correction`s on
   the *candidate* units as the live controls (`durable-limiter.ts:237`,
   `operationBuilder-shared.ts:497-505`) — they govern unit 8's entry point.
3. **Add the three unrecorded surfaces to the unit set** (C3) — `replicache-pull/route.ts#POST`
   first, and settle `drizzle/migrate.ts`'s and `drizzle/initializeDatabase.ts`'s registration from a
   built `server-reference-manifest.json` rather than from the source.
4. **Run the four experiments that need only a build, first** — they settle six units between them:
   the manifest read (candidates 1, 2, 4 → units 2, 3, 4, and C3 — **owned by the programme lead**,
   post-land, per § Manifest lookup keys, which carries the recipe and the positive control), the
   sealed-payload triple (unit 7), the allowlist corpus diff (unit 14 and lead 16), and the
   erasure-then-drain run (unit 1 and confirmed #4).
5. **Then the deployment reads**, each of which settles a question no amount of source can:
   `PUSH_ORIGIN_CHECK`, `REPLICACHE_PULL_CURSOR_GATE`, `VENUE_SCOPING_FLAG_TTL_MS`, whether any live
   tenant has `enable_venue_scoping` on, and whether `guest_message_outbox` has a configured sender.
6. **Record `enumeration_complete[cloudflare, reso]` only for the scope actually enumerated** — this
   document enumerates *uncovered units*, which is not the same as auditing them, and nothing here
   may be counted as absence of a defect.

---

## Provenance

Produced by W5 of `RESO_SECURITY_100P` (`docs/plans/RESO_SECURITY_100P.md` § Wave 5), a
non-fix wave: no file in `~/Development/reso-management-app` was written, no migration was run, no
credential was read. Ledger row appended to
[`codex-security-scans/LEDGER.md`](./codex-security-scans/LEDGER.md) § Cloudflare.
