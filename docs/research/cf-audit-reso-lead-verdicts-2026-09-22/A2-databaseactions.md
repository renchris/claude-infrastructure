# A2 — adjudication of LEAD 4 (`initializeDB`) and LEAD 2 (`deleteDatabase`)

Read-only pass, 2026-09-22. Every citation is `git show origin/main:<path>` in
`/Users/chrisren/Development/reso-management-app`. No edits, no commits, no index touched.

---

## Verdicts

| Lead | Verdict | One-clause reason |
|---|---|---|
| **4** — `initializeDB` unauthenticated Server Action | **REJECTED as a live endpoint / CONFIRMED as a latent injection defect** | `initializeDB` has **no entry in the production `server-reference-manifest.json`** while 14 siblings from the same `'use server'` file do, so no `Next-Action` id exists to POST — but the identifier→URL composition it relies on (`drizzle/db.ts:131`) is genuinely unvalidated, and a *different* export of the same sink, `getNamedDB`, **IS** registered. |
| **2** — `deleteDatabase` serving guard scoped to the manifest | **CONFIRMED (guard gap), but it is a blast-radius defect, not an authz one** | `platformActions.ts:93` matches only `TENANTS[].dbName`; the four `parent-schema-database-*` DBs are in no manifest entry, so `tenant` is `undefined` and the refusal at `:94` never fires — reachable only from a platform-email session (`:79`), and backstopped by Turso per-DB delete protection. |

---

## LEAD 4 — `initializeDB` (`src/app/actions/auth/databaseActions.ts:135`)

### 1. Is there any session/authz check on the path?

**No. None, anywhere on the path.**

- `databaseActions.ts:1` is `'use server'`.
- `initializeDB` (`:135-141`) reads no session: its body is `getNamedDB(...)` → one `SELECT` → a
  conditional block of five `INSERT`s. There is no `getServerActionSession`, no
  `ensureAdminAccess`, no `getRegisteredUserFromCookieStorage`.
- The absence is **deliberate and documented**: `:129-134` carries a C-007 allowlist comment and
  `// eslint-disable-next-line reso-design/no-ungated-db-export -- pre-user bootstrap`. The repo's
  own lint rule (`eslint-rules/no-ungated-db-export.mjs`, enabled at `eslint.config.mjs:363`) would
  otherwise make this a build error.
- Nothing upstream authenticates either: `middleware.ts` sets `x-pathname` and a CSP nonce and
  **does no auth** (its whole body is the nonce branch; `middleware.ts:44-82`).
- The allowlist rationale is *accurate on the axis it considers* ("idempotent, reads/leaks no user
  data, runs before any user/session exists") and **silent on the axis that matters**: that the
  first parameter it forwards is a DNS label that is concatenated into a URL authority.

### 2. Which parameters are caller-supplied, and how do they reach the URL and the token?

All five are caller-supplied plain strings. Two are load-bearing:

```
initializeDB(organizationName, organizationDomain, group, timezone, currency)   :135-141
  └─ getNamedDB(organizationDomain, group)                                      :142
       └─ drizzle/db.ts:215 getNamedDB(organizationName, group)
            └─ :226 resolveGroupConfig(organizationName, group)
                 ├─ :131  url = `libsql://${organizationIdentifier}-database-${TURSO_ORGANIZATION_URL}`
                 │        (or the `…-database-renchris.aws-us-west-2.turso.io` form for oregon-group)
                 └─ :135-148  authToken = process.env.TURSO_AUTH_TOKEN_<GROUP>   ← group selects it
            └─ getOrCreateConnection(cacheKey, url, authToken, group)  :46-72
                 └─ createClient({ url, authToken })
```

- `organizationDomain` is interpolated into the URL with **zero validation** — no charset check, no
  regex, no manifest membership test. `drizzle/db.ts:117-124`'s own doc comment says
  "`getNamedDB` passes organizationName (**caller-supplied**)" — the hazard is already written down.
- `group` selects which group-wide Turso token is used (`:135-148`); an unrecognised group falls
  through to `process.env.TURSO_AUTH_TOKEN` and throws if unset (`:150-154`).
- `timezone` / `currency` are written verbatim into `tenant_config` and `venue` rows (`:186-187`,
  `:212-213`) with no validation.

**The injection is real at the library level, and I verified it in the installed dependency rather
than assuming it.** `@libsql/client@0.17.4` → `@libsql/core@0.17.4/lib-cjs/uri.js`:

```js
const AUTHORITY = "(?<authority>[^/?#]*)";
```

The authority ends at the **first `/`**. So `organizationDomain = "evil.example.com/x"` yields
`libsql://evil.example.com/x-database-renchris.turso.io`, which `parseUri` reads as
host `evil.example.com`, path `/x-database-renchris.turso.io`. `config.js:74-81` maps scheme
`libsql:` → `https:` (node entry passes `preferHttp = true`, `lib-cjs/node.js:28`), and
`lib-cjs/http.js:62,84` hands `config.authToken` to `hrana.openHttp`, which sends it as
`Authorization: Bearer <token>` on the first request. A `#` would be rejected
(`config.js:106-109`) and a `?` only tolerates `tls` / `authToken` keys (`config.js:54-61`), but
neither is needed — `/` alone is the vector.

**What the token is worth**: `TURSO_AUTH_TOKEN_<GROUP>` is the *group* credential — the same token
`resolveGroupConfig` hands to every tenant in that group, i.e. full read/write on every tenant
database in the region. `lib/provisioning/group-token-ssm.ts` (the SSM bridge) exists precisely
because it is a long-lived group credential.

### 3. What does the caller get back?

`Promise<void>` (`:141`). No token, no client handle, no connection params, no row data — the
`SELECT` at `:144-148` is consumed only as `rows.length` (`:150`). In production Next redacts
thrown Server Action errors to an opaque digest, so there is no error-text oracle either. The only
observable is latency. **No direct read exfiltration.**

### 4. Blast radius — does it WRITE?

**Yes, but only into an empty database.** `:150 if (rows.length === 0)` gates five inserts:
`replicache_meta` schemaVersion (`:151-157`), `organization` (`:159-168`) with
`subdomain = organizationDomain` and `name = organizationName`, `tenant_config` (`:170-190`),
`rum_config` with `updatedBy: 'initializeDB'` (`:192-201`), and `venue` id/slug `default` with
`name = organizationName` (`:203-224`).

Against any live tenant this is a **no-op**: every provisioned tenant has a `replicache_meta`
schemaVersion row (that is what `initializeDB` itself writes, and `lib/sync-cursor.ts:33` documents
the invariant). The write window is a tenant DB that exists, is migrated, and has not yet been
initialised — i.e. mid-provisioning, between `provision-venue` phase 3 and the org/config/venue
init phase. Narrow, but during that window an attacker would author the tenant's own organization
name and default venue name.

### 5. The concrete attack — and why it does not currently land

The attack a reviewer would write up is:

> POST the action with `organizationDomain = "attacker.example.com/"` and
> `group = "dallas-group"`. The server opens a libsql client against `attacker.example.com`,
> executes the `SELECT` at `:144`, and sends `TURSO_AUTH_TOKEN_DALLAS_GROUP` as a bearer token to
> the attacker. The attacker now holds read/write on every Dallas-group tenant database.

**It does not land today, and the reason is mechanical, not a control anyone wrote.**

Next dispatches a Server Action by looking the `Next-Action` header id up in the build's
server-reference manifest. The production build artifact present in this checkout —
`.next/server/server-reference-manifest.json`, Next **16.2.6**, Turbopack, built **2026-07-19**
(`.next/diagnostics/framework.json`) — contains **79** action entries. Exactly **14** come from
`databaseActions.ts`:

```
checkInvitationByInviteID, checkUsernameAvailable, deleteCredential, deleteUser,
getAllInvitations, getAllUsers, getSubdomainAndGroup, markInvitationSent, resendInvitation,
revokeInvitation, sendInvitation, supersedeInvitation, updateColorModeOfUser, updateUserRole
```

`initializeDB` is **absent**, as are `getOrganizationName`, `checkDBConnection`, `registerUser` and
`consumeInvitationAndRegister`. With no id in the manifest there is no value to put in
`Next-Action`, and the runtime refuses an unknown id. This matches the repo's own stated method:
`docs/plans/DOCS_CONSOLIDATION_100P.verdicts.tsv:481` — *"enumerate the server-action surface from
the build MANIFEST, not by reading source — a source grep under-reports the actual POST surface."*
Here it **over**-reports, in the same direction the C-007 lint rule assumes.

So the premise in the audit brief — *"`databaseActions.ts` begins with `'use server'`, so EVERY
export is a network-reachable POST endpoint"* — is **false for this build**. It is the right default
assumption and the wrong conclusion once the manifest is read.

#### The three things that make this a REJECTED-with-a-tripwire, not a clean acquittal

1. **The artifact is stale by two months and one minor version** (built on 16.2.6; `package.json:162`
   now pins `next@16.3.5`). Re-derive before relying on it:
   `python3 -c "import json;m=json.load(open('.next/server/server-reference-manifest.json'));print(sorted({(w['filename'],w['exportedName']) for v in m['node'].values() for w in v['workers'].values()}))"`
   after a fresh `pnpm build`.
2. **Whatever excluded it is not a control anyone owns.** I could not name the analysis: the
   registered set is *not* "exports imported by a client component" — `drizzle/db.ts`'s
   `getNamedDB`, `getDBAndGroup`, `default` and `evictConnectionByDb` are all registered and no
   client module imports `drizzle/db` (checked: zero `'use client'` files import it). So the
   inclusion rule is a Next build-graph internal. One client import of `initializeDB`, one Next
   upgrade, or `next dev` semantics leaking into a deployment flips it live **silently**.
3. **`next dev` registers everything.** Not a deployed surface, but it means a local dev server is
   the working exploit environment.

### 6. 🚨 The adversarial-pass finding: the same sink IS registered, via `getNamedDB`

`drizzle/db.ts:1` is `'use server'`, and `drizzle/db.ts:215 getNamedDB(organizationName, group)`
**is in the manifest** — a live, unauthenticated, network-reachable POST endpoint taking exactly the
two caller-supplied strings that compose the libsql URL and select the group token. So LEAD 4's
*mechanism* is confirmed at a file:line the lead did not name.

What it achieves, stated honestly rather than maximally:

- It **does** construct a libsql client against an attacker-chosen authority holding the real group
  token, and caches it (`drizzle/db.ts:46-72`).
- It **does not** put the token on the wire, because `getNamedDB` executes no query and
  `hrana.openHttp` is lazy — the bearer header is only sent on the first statement. `initializeDB`
  is what supplies the statement, and `initializeDB` is the one that is not reachable.
- Its standalone harm is **unauthenticated unbounded growth of `connectionCache`** — one `Map` entry
  per distinct `${name}:${group}`, never evicted (`:72`; only `evictConnectionByDb` removes, and it
  needs a handle) — i.e. a memory-exhaustion vector on a long-lived Node process.
- Its return value is a Drizzle handle, which cannot be flight-serialised, so the caller gets an
  error rather than a client.
- **Cache poisoning was checked and does not work**: `cacheKey` is `${organizationName}:${group}`
  and the URL is a deterministic function of the same two inputs (`:226-236`), so the key↔URL map is
  a bijection and a legitimate tenant's entry cannot be pre-filled with a hostile URL.

**Secondary, UNVERIFIED path to the same sink.** `domainActions.ts:47-70` `getSubdomain` returns
`host.split('.')[0]` off the raw `Host` header, and that value reaches `resolveGroupConfig` through
`getConnectionParams` (`drizzle/db.ts:173-176`). A `Host` of `foo/bar.reso.gl` would yield the
subdomain `foo/bar`. Whether such a Host survives CloudFront / Fly Proxy / Node's header validation
is **not established here** (no network was used), and `getSubdomainAndGroup` normally
short-circuits on the session-cached tenant (`tenantContext.ts:39-42`) and otherwise gates on a
Turso Platform API `databases.get(\`${subdomain}-database\`)` lookup that a bogus label would fail.
Named because it is the second independent reason to validate at the composition site.

### 7. Recommended fix

**Fix A (the load-bearing one — validate at the chokepoint, NOT in `databaseActions.ts`).**
In `drizzle/db.ts`, inside `resolveGroupConfig` (`:126-156`), before line 131:

```ts
if (!/^[a-z0-9][a-z0-9-]*$/.test(organizationIdentifier)) {
  throw new Error('Invalid database identifier')
}
```

- Closes URL-authority injection for **every** caller — `getDB`, `getNamedDB` (the live endpoint),
  `getDBAndGroupForSessionTenant`, `drizzle/migrate.ts`, and `initializeDB` if it is ever
  re-registered — rather than patching one of them.
- Behaviour-preserving against real data: all ten manifest subdomains
  (`harbour, harbourtwo, key, evolve, envy, gm, apt101, muin, studio60, insomniacdenver`,
  `lib/config/tenants.ts:492-709`) match; the `parent-schema-database-*` names are not passed here.
- **Not destructive, not migration-class, no operator gate.** It only ever refuses.
- A companion `group` allowlist check against the `tursoGroup` union is the natural second line, but
  the existing throw at `:150-154` already refuses an unknown group when no default token is set;
  keep them separate so the first fix stays one-line-reviewable.

**Fix B (remove the endpoint risk at the root — optional, larger, and it collides).**
Move `initializeDB` out of the `'use server'` module into a plain module (e.g.
`drizzle/initialize-db.ts`) and repoint `drizzle/initializeDatabase.ts:3`. Its only consumer is that
tsx script (`pnpm db:setup`), so nothing in the app graph changes, and the `server-only` constraint
recorded at `databaseActions.ts:61-72` is satisfied by the new module being plain. This deletes
`databaseActions.ts:129-225` and is a ~100-line move.

- **Not destructive, not migration-class.** But it is a large edit to a file another session landed
  in **today** (`1e07c9035`, 2026-09-22, `deleteUser` cascade). See §Collision below.

**Do NOT** "fix" this by adding a session gate to `initializeDB`: the function legitimately runs
pre-user and under a plain tsx script with no request scope (`:130-133`), so a
`getServerActionSession` call there would break `pnpm db:setup`, which
`docs/plans/…`/`databaseActions.ts:1554-1561` records as having previously stalled `postland-verify`
for six days. Fix A does not have this problem.

---

## LEAD 2 — `deleteDatabase` (`src/app/actions/auth/platformActions.ts:75`)

### What the guard actually tests

Two independent checks, and the lead's description elides the first:

1. **Authz, `:76-82`** — `getServerActionSession()` then
   `if (!session.user || !isPlatformEmail(session.user.email)) return new Error('Unauthorized')`.
   `isPlatformEmail` (`lib/auth/platform-email.ts:11-19`) matches `PERSONAL_PLATFORM_EMAIL` after
   plus-address normalisation, or a `PLATFORM_EMAIL_DOMAIN` suffix. **This is a real, correctly
   placed gate.** A tenant admin cannot reach it. LEAD 2 is therefore *not* an authz hole.
2. **The serving guard, `:93-101`** —
   ```ts
   const tenant = TENANTS.find((t) => t.dbName === databaseName)
   if (tenant && isServing(tenant)) { return new Error('Refusing to destroy …') }
   ```
   `isServing` is `t.status !== 'dormant'` (`lib/config/tenants.ts:798-800`). So the refusal fires
   **only when the name is an exact `dbName` match in the manifest**. `tenant === undefined` ⇒ the
   guard is vacuous and control falls through to `db.databases.delete(databaseName)` (`:105`) on the
   `TURSO_PLATFORM_API_AUTH_TOKEN` (`tenantContext.ts:21-27`).

The `tenant &&` short-circuit is **documented as deliberate** at `:87-92`: *"Orphan/unregistered DBs
(not in the manifest) are still deletable here (the typed-confirm UI guards the fat-finger)."* So
this is a known affordance, not an oversight — but the class it lets through was mis-scoped.

### What the platform token can destroy that the guard does not cover

All ten manifest tenants are `active` or `canary` (`lib/config/tenants.ts:495,505,516,540,630,640,653,663,680,707`) — **none is `dormant`**, so the guard covers all ten. Everything else in the Turso org is uncovered:

| Uncovered database | In `TENANTS`? | Consequence of deleting it |
|---|---|---|
| `parent-schema-database-lax` | no | destroys the schema parent for every LAX child tenant DB |
| `parent-schema-database-singapore` | no | same, SIN |
| `parent-schema-database-ashburn` | no | same, IAD |
| `parent-schema-database-dallas` | no | same, DFW — parent of `insomniacdenver-database` |
| `demo` | no | the one DB excluded from the 2026-08-21 protection sweep |
| `<tenant>-restore-<ts>` forks | no | an in-flight PITR restore artifact holding **live tenant data** (`lib/config/tenants.ts:18-21`, `docs/runbooks/TENANT_DB_RESTORE.md`) |
| a tenant DB provisioned before its manifest entry lands | no | mitigated by the manifest-ack registration gate (`:90-92`) |

Evidence the parents are real and are schema parents, not tenants:
`CLAUDE.md:382-383`, `.claude/skills/drizzle-migrations/SKILL.md:84-85`,
`docs/reference/FLYIO_LAX_ARCHITECTURE.md:55`,
`docs/plans/INSOMNIAC_DENVER_PROVISIONING.md:713` (*"`insomniacdenver-database` is a schema child of
`parent-schema-database-dallas` with 50 tables"*). They carry the DDL every child inherits
(`docs/data-model/README.md:151`), they are named `parent-schema-database-<region>` — **never
`<subdomain>-database`** — and `lib/config/tenants.ts` has no entry for any of them
(`grep -n dbName` returns exactly the ten `*-database` tenant names).

The manifest-based guard's shape is the defect: it is keyed on a **naming convention it does not
enforce** (`<subdomain>-database`) and is therefore structurally blind to every database whose name
does not follow it — which is exactly the set of infrastructure databases.

### The mitigation, stated so it is not mistaken for the fix

`docs/plans/INSOMNIAC_DENVER_PROVISIONING.md:706` records that on 2026-08-21 the operator ran a
per-database **Turso delete-protection** sweep (16/17, `demo` excluded) and that
`parent-schema-database-dallas` and `parent-schema-database-ashburn` were among four read back as
`Delete Protection on`. If that state still holds, the Platform API `databases.delete` at `:105`
would be **refused by Turso**, and `deleteDatabase` would surface the vendor error through
`:113-116`. Caveats worth keeping: the read-back was **sampled, 4 of 17** (the doc says so itself),
`parent-schema-database-lax` and `-singapore` were **not** among the four, the flag is mutable from
outside this repo, and I did not verify it live (no network this pass). Treat it as the reason the
severity is moderate, never as the reason not to fix the guard.

The typed-confirm in `PlatformContent.tsx:64-96` is client-side only and is explicitly *not* the
control — the component's own comment at `:64` defers to the *"authoritative server-side
serving-tenant guard in `deleteDatabase`"*, which is the guard that does not cover these names.

### Recommended fix

**Minimal, refusal-only, preserves the deliberate orphan-DB affordance.** In
`platformActions.ts`, insert between `:92` and `:93`:

```ts
// Infrastructure databases are not tenants and are in no manifest entry, so the
// TENANTS lookup below cannot see them. A schema parent carries the DDL every child
// tenant DB in its group inherits.
if (/^parent-schema-database-/.test(databaseName)) {
  return new Error(
    `Refusing to destroy ${databaseName}: it is a schema parent, not a tenant database. `
    + 'Every child tenant DB in its group inherits its DDL. Use the decommission-venue CLI.',
  )
}
```

- Prefer deriving the name set from `LOCATIONS`/`tursoGroup` in `lib/config/tenants.ts` over the
  regex, so region N+1 is covered with no edit — same principle the manifest already applies
  elsewhere (`lib/provisioning/group-token-ssm.ts:18-24`). The regex is the one-line version; the
  derivation is the correct one.
- **Not destructive, not migration-class, not operator-gated** — it only ever refuses, it cannot
  break a green path, and no live data is touched. Land-safe on its own.

**Stronger option, and it IS an operator call.** Invert the guard to an allowlist: refuse unless
`databaseName` matches a manifest entry that is `dormant`. This closes the whole class — parents,
`demo`, restore forks, and anything future — but it **removes an affordance the code deliberately
grants** (`:87-92`: orphan/unregistered DBs deletable from this console), so it is a policy change,
not a bug fix. Surface it; do not drive it.

**Second, smaller gap worth one line in whatever ledger takes this**: the guard matches `dbName`
**exactly**, so a `<tenant>-restore-<ts>` fork — which holds a live tenant's real rows — is
uncovered even though its parent tenant is `active`. A prefix test (`t.dbName` or
`` `${t.subdomain}-` ``) would cover it; whether that is wanted is the same policy question as above,
since deleting a finished restore fork is a legitimate cleanup.

---

## DO-NOT-FIX check (`.claude/commands/exhaust-improvements.md` § DO-NOT-FIX landmines, :181-190)

Read in full. **Neither fix collides with any of the eight landmines.** For the record:

- *"`getServerActionSession` IS the auth check"* (`:189`) — respected: neither fix renames or
  bypasses it; `deleteDatabase` keeps its `getServerActionSession` + `isPlatformEmail` gate verbatim.
- *"share-graph venue-unscoped reads — a security lens WILL flag it; it is by-design"* (`:188`) —
  a different subsystem; not touched.
- The remaining six (Replicache `for…of`, `<Suspense>`, mission-control `rgba`, F6 warm-at-tap,
  FloorPlanViewer barrel, park-ui spreading) are unrelated.

**One line from the same file DOES bind, and it is the disposition rule**: `:212-213` —
*"Auth/sync findings → queue + escalate, never silently land mid-sweep (CLAUDE.md escalation rule
wins over 'just keep working'). Surfacing + planning + flagging IS the correct disposition."*
This pass is read-only and surfaces only; nothing here was driven.

## Collision check against the 2026-09-22 land (`1e07c9035`)

`1e07c9035 fix(auth): deleteUser revokes the departed principal, not just their row` edits
`deleteUser` (`databaseActions.ts:584`) and the notification/list cascade — ~450 lines below
`initializeDB` (`:135-225`), no shared hunk.

Its commit body also states that **route (b), schema FOREIGN KEYs with `ON DELETE`, is pending an
operator ruling** because it needs four destructive table rebuilds across eight live tenant DBs —
a G2 escalation surface. Nothing recommended here goes near that: **Fix A** is one guard clause in
`drizzle/db.ts`, **Fix B** is a module move, and the **LEAD 2 fix** is one refusal branch in
`platformActions.ts`. Three different files, none of them the file that commit owns beyond Fix B.

**Single-owner consequence, stated plainly:** Fix A and the LEAD 2 fix touch files `1e07c9035` did
not. **Fix B rewrites ~100 lines of `databaseActions.ts` and should not be taken while that file has
a live owner** — it is also the least valuable of the three, since Fix A already closes the sink for
every caller.

## What I could not settle (named, not buried)

1. **The current production manifest.** The only build artifact available is 2026-07-19 / Next
   16.2.6; the pin is now 16.3.5. If a fresh `pnpm build` puts `initializeDB` in
   `server-reference-manifest.json`, LEAD 4 flips from REJECTED to **CONFIRMED CRITICAL** and Fix A
   becomes urgent rather than prophylactic. The one command is in §5 above.
2. **Why Next excluded it.** Not "no client import" — `getNamedDB` is registered with no client
   importer. The inclusion rule is a build-graph internal I did not identify, which is exactly why
   it cannot be treated as a control.
3. **Live Turso delete-protection state** on the four schema parents. The 2026-08-21 read was
   sampled 4/17 and did not include `-lax` or `-singapore`. No network was used this pass.
4. **Whether a `Host` header containing `/` survives the edge.** The `getSubdomain`
   `host.split('.')[0]` path (`domainActions.ts:67`) is a second, unverified route into the same
   unvalidated composition.
