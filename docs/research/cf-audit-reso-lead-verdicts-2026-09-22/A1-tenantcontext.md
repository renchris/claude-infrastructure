# A1 — adjudication of Cloudflare security-audit LEADS 18 & 19 (`src/app/actions/auth/tenantContext.ts`)

Read-only. All source read via `git -C /Users/chrisren/Development/reso-management-app show origin/main:<path>`.
Build artefacts read from the local `.next/` (BUILD_ID `Zr4pNxqmlzMZgpy7JM1Z_`, built **Jul 19 2026** — stale
relative to today's `origin/main`; used only for **structural** facts, never for a current-ID claim).
No edits, no commits, no index touch.

---

## VERDICTS

| Lead | Verdict | Severity as adjudicated |
|---|---|---|
| **18** — `getPlatformDB` is an ungated Server Action returning the Turso control-plane client | **CONFIRMED as an ungated, build-registered action endpoint. The token-disclosure half is REFUTED.** | **LOW / hygiene** (was reported as high) |
| **19** — `LOCAL_TEST_*` precede the `NODE_ENV` branch and the sealed session tenant | **CONFIRMED as a code fact, exactly as stated.** Not remotely triggerable. | **MEDIUM latent** (config-fragility / defence-in-depth) |

---

## Q1 — LEAD 18 reachability: can the Turso client actually cross the RSC boundary?

### 1a. It IS a registered endpoint — measured, not inferred

`.next/server/server-reference-manifest.json` (production node manifest, 79 actions) contains:

```
0071d11693d1b7f0a3646c4e10a1ef8394ab8ae47d
  → { exportedName: "getPlatformDB", filename: "src/app/actions/auth/tenantContext.ts" }
    registered under app/(app)/admin/(settings)/page, …/notifications/page, …/platform/page, …
```

So Next does **not** tree-shake an exported `'use server'` function that no client component imports.
The reachability premise of the lead is confirmed at the build layer, not merely at the source layer.
There is also **no perimeter in front of it**: `middleware.ts` (repo root) is CSP-nonce only — its whole
body sets `x-pathname` + a CSP header and its matcher explicitly *excludes* `api`; it performs no auth.
`next.config.ts` sets no `experimental.serverActions` block, so only Next's default Origin==Host CSRF
check applies, which a direct `curl` satisfies trivially.

### 1b. But the ID is not published, and the return cannot serialise

**Action-ID discoverability.** I grepped all 7,980,483 bytes of `.next/static/**/*.js` for each of the 79
manifest IDs. **37 of 79 appear** in client JS (positive control passes — `clearCookies`,
`slideSessionIfStale`, `updateColorModeOfUser`, … are all there). `getPlatformDB`'s ID is **not** one of
them. Neither is `getSubdomainAndGroup`'s *tenantContext* ID — that export reaches the client only
through a **second, distinct** ID registered under `databaseActions.ts` (`7f14932fe2d3…`, client-visible),
which is the one `InviteForm.tsx` calls. IDs are 42 hex chars (168 bit) and salted per build
(`encryptionKey` is present in the manifest), so they are neither derivable from source nor brute-forceable.

**Serialisation.** `createClient` from `@tursodatabase/api` returns a `TursoClient` **class instance**
(`node_modules/@tursodatabase/api/dist/index.d.ts:306`, `declare function createClient(config: TursoConfig): TursoClient`).
The compiled bundle confirms the token sits on a **plain own enumerable field** — every sub-client does
`constructor(config) { this.config = config }` (`dist/index.js`, `ApiTokenClient`/`OrganizationClient`/…),
so at runtime `turso.databases.config.token === process.env.TURSO_PLATFORM_API_AUTH_TOKEN`. TypeScript's
`private config` is compile-time only and erases.

That plain field is nevertheless unreachable over the wire, because React's flight server rejects the
*instance* before it ever descends into it. From the **production** bundle Next actually ships
(`node_modules/next/dist/compiled/react-server-dom-webpack/cjs/react-server-dom-webpack-server.node.production.js`,
React 19.2.8 / Next 16.3.5):

```js
request = getPrototypeOf(value);
if (request !== ObjectPrototype$1 && (null === request || null !== getPrototypeOf(request)))
  throw Error("Only plain objects, and a few built-ins, can be passed to Client Components from Server Components. Classes or null prototypes are not supported." + describeObjectForErrorMessage(parent, parentPropertyName));
```

For a `TursoClient`: `proto = TursoClient.prototype ≠ ObjectPrototype`, and
`getPrototypeOf(TursoClient.prototype) = Object.prototype ≠ null` → the guard is satisfied → **throws**.
This is in the production file, not a DEV-only warning.

### 1c. Precisely what an attacker does and does not get

Given the ID (which is not obtainable from any shipped asset):

* **DOES**: cause the server to execute `createDatabase({org, token})`. The compiled constructor only
  assigns `this.config`; it issues **no network call**. Then flight serialisation throws, Next's `onError`
  converts it to an opaque digest, and the caller receives a 500 with no payload.
* **DOES NOT**: obtain `TURSO_PLATFORM_API_AUTH_TOKEN`, `TURSO_ORGANIZATION_NAME`, any group/database
  listing, or any control-plane mutation. The three call sites that actually *use* the client
  (`platformActions.ts:18/60/102`) are each gated on `!session.user || !isPlatformEmail(session.user.email)`.
* **Residual**: a near-zero-cost CPU/alloc endpoint (no DoS value), and a *latent* trap — the day anyone
  changes `getPlatformDB` to return `{ token, org }`, or adds a `toJSON`, or the caller wraps it in a
  plain object, the guard stops firing and the token becomes a plain string on the wire. That latent
  trap is the real reason to fix this.

**Correction to the brief's ESTABLISHED list:** `getAllGroups` **is** exported from `platformActions.ts`
(`export { getAllDatabases, deleteDatabase, getAllGroups }`, final statement of the file). It is therefore
its own action endpoint — but it is gated identically on `isPlatformEmail`, so nothing in the verdict moves.

---

## Q2 — LEAD 18 safe fix shape

### 2a. An auth gate inside `getPlatformDB` WOULD break login — verified

`tenantContext.ts:47-50`:

```ts
const [subdomain, platformDB] = await Promise.all([
  getSubdomain(),
  getPlatformDB(),
])
```

This runs on the **no-session** path only (`:39-42` returns early when `getTenantFromSession()` is truthy),
i.e. exactly the login flow the comment at `:46` names. A `session.user`/`isPlatformEmail` gate inside
`getPlatformDB` would return `null`/throw there, and `platformDB.databases.get(...)` at `:57` would fail
for **every** unauthenticated visitor — the login page itself. Fix (c) is disqualified on that alone.

### 2b. Fix (b) — dropping `'use server'` from tenantContext.ts

Two independent problems.

1. **It does not remove the endpoint.** `databaseActions.ts:72` does `export { getSubdomainAndGroup }` from
   a `'use server'` module, so the client-reachable ID lives there regardless. Meanwhile `getPlatformDB`'s
   own exposure would go away only if the transform reliably declines to re-register it — true, but the
   change does far more than needed and rests on re-export transform behaviour that has historically been
   buggy.
2. **The client-bundle guarantee would be replaced by nothing.** Today `'use server'` is what *structurally*
   prevents `tenantContext.ts` (and with it `@tursodatabase/api`, `iron-session` via `cookieActions`) from
   ever landing in a client chunk. The natural replacement — `import 'server-only'` — is a **documented
   reso landmine**: `databaseActions.ts` carries the comment verbatim at its import block and again at its
   `getOrganizationName` dynamic import —

   > "`server-only` is a bundler-vendored specifier Next resolves but plain Node cannot. Eagerly importing
   > authQueries here dragged it into the tsx-run DB-setup graph (`drizzle/initializeDatabase.ts` →
   > `databaseActions.initializeDB`), which crashed with `Cannot find module 'server-only'`."

   `drizzle/db.ts:6` imports `tenantContext`, and `initializeDatabase.ts` imports `databaseActions`, so
   `tenantContext` sits squarely inside that tsx graph. Adding `server-only` there breaks `pnpm db:setup`
   on fresh worktrees. **Fix (b) is therefore the worst of the three: it removes a guarantee and cannot
   restore it.**

### 2c. Fix (a) — RECOMMENDED. Move the helper out; it stops being an export of an action module

The repo has already made this exact call, one file over, and wrote down why. `domainActions.ts:31-39`:

> "Composition lives in `lib/auth/device-label.ts` — pure, and unit-tested there. It cannot be exported
> from HERE for testing: **this module is `'use server'`, so any export becomes a callable server-action
> endpoint**, and minting one on an auth module to reach a string builder is a bad trade."

`getPlatformDB` is the same shape with a real secret behind it. The exact edit:

1. **New file** `lib/turso/platform-client.ts` (plain module — **no** `'use server'`, **no** `import 'server-only'`):

```ts
import { createClient as createDatabase } from '@tursodatabase/api'

/** Turso Platform API client (control-plane: tenant database/group metadata). */
export const getPlatformDB = async () => createDatabase({
  org: process.env.TURSO_ORGANIZATION_NAME || '',
  token: process.env.TURSO_PLATFORM_API_AUTH_TOKEN || '',
})
```

2. **`tenantContext.ts`** — delete `:18-27` and the `createClient as createDatabase` import at `:3`; add
   `import { getPlatformDB } from '@lib/turso/platform-client'`. Nothing else in the file changes; `:49`
   keeps working.
3. **`platformActions.ts:3`** — repoint to `@lib/turso/platform-client`. Its three call sites
   (`:18`, `:60`, `:102`) are untouched.

Why this is safe, point by point:

* **Cycle architecture preserved.** The comment at `tenantContext.ts:10-16` says `getPlatformDB` lives
  there only because `getSubdomainAndGroup` needs it and putting it back in `db.ts` re-creates
  `db.ts → tenantContext → db.ts`. `lib/turso/` imports nothing from the app, so it introduces no edge at all.
* **No `server-only` landmine.** The new module deliberately omits it, so `pnpm db:setup` is unaffected.
* **No secret-leak risk from omitting it.** Next's client build replaces `process.env` with the
  `NEXT_PUBLIC_*` set only, so even a hypothetical client import inlines `undefined`, not the token. And
  no client module imports it: the complete importer set of `tenantContext` today is `drizzle/db.ts:6`,
  `lib/auth/upgrade.ts:17`, `databaseActions.ts:48`, `venueRoleActions.ts:7`, dynamic imports in
  `lib/rum/rum-config.ts:195` and `lib/venue-resolution.ts:63`, plus tests — **none** is `'use client'`.
  (The one client caller in the graph, `InviteForm.tsx:1` `'use client'` → `:10`, imports
  `getSubdomainAndGroup` from `databaseActions`, not `getPlatformDB`, and is unaffected.)
* **No test churn.** No test in the tree imports `getPlatformDB`; every `vi.mock('…/tenantContext')`
  stubs only `getSubdomainAndGroup`.
* **The endpoint disappears** — `getPlatformDB` stops being an export of a `'use server'` module, so the
  manifest entry `0071d116…` is not minted on the next build. That is directly checkable post-fix with
  the same grep used above.

**Ranking: (a) ≫ (c) ≫ (b).** (c) breaks login. (b) trades a structural guarantee for one it cannot
re-establish without breaking `db:setup`.

**Optional hardening, out of scope for these two leads but worth filing:** there is no lint/test asserting
the *export surface* of `src/app/actions/**` (`git grep` for `server-action-surface`/`actionSurface`
returns nothing). A snapshot test over `server-reference-manifest.json` would turn "a helper accidentally
became an endpoint" from a review question into a gate.

---

## Q3 — LEAD 19 blast radius and safe fix

### 3a. The precedence claim is exactly true

`tenantContext.ts`: `LOCAL_TEST_*` at **:32-37** → `getTenantFromSession()` at **:39-42** → the
`NODE_ENV === 'development'` branch at **:52**. So when both env vars are set, the function returns before
it ever consults the authenticated session's sealed tenant, and `drizzle/db.ts:178` (`const { subdomain, group } =
await getSubdomainAndGroup()`) opens the **pinned** tenant's database for a user whose session says a
different tenant. Every read and every write on that request goes to the wrong tenant, silently, with a
valid session. That is a cross-tenant data-exposure shape.

### 3b. Blast radius is bounded by who can set the vars

`LOCAL_TEST_*` are process env, set at build/deploy time — **not attacker-controllable**, so this is not
remotely triggerable. Full reader census (`git grep` over the whole tree): `tenantContext.ts:32-36` is the
**only** runtime reader. Everything else is documentation — `.env.example:13/256-261`,
`docs/reference/ENVIRONMENT_VARIABLES.md:143-144,296-302`, `docs/reference/INFRA_ACCESS.md:291-292`,
`docs/runbooks/A1_COLDLAUNCH_MONITOR.md:115`, `grafana/synthetics/a1-coldlaunch.js:106` (a comment).

`lib/provisioning/tenant-db-target.ts:41` **does not read `LOCAL_TEST_*`** — its reference to
`tenantContext.ts:21-27` is about `TURSO_ORGANIZATION_NAME` being uniform across environments, i.e. it
cites the `getPlatformDB` body, not the override. No coupling, nothing to change there.

No committed deploy config sets them (`git grep -i LOCAL_TEST` over `fly*.toml`, `amplify*`, `*.yml`,
`Dockerfile*`, `scripts/`, `.github/` returns nothing) and **no check forbids them** — `scripts/checks/`
has no guard. So the exposure is: one stray Amplify/Fly environment variable, with nothing between it and
a silent fleet-wide tenant repoint. Whether any live environment carries one is an out-of-band deployment
fact I cannot read from the repo; the *code* offers no defence either way.

### 3c. Does moving the branch below `getTenantFromSession()` preserve the workflow? — YES

The workflow the comment protects is `LOCAL_TEST_SUBDOMAIN=time LOCAL_TEST_GROUP=los-angeles-group pnpm
build && pnpm start` (`INFRA_ACCESS.md:291`), i.e. `NODE_ENV=production` on localhost. Two sub-cases,
and the reorder survives both:

* **No session (pre-login, anonymous browsing, the landing page, the login flow itself).**
  `getTenantFromSession()` returns `undefined` → the `LOCAL_TEST_*` branch fires exactly as before, still
  *above* `getSubdomain()`/`getPlatformDB()`/the `NODE_ENV` branch. Behaviour identical. This is the
  case the workflow is actually for.
* **A session exists.** Then `session.tenant` was sealed at login by `sessionWrite.ts:48` `fetchTenantInfo`
  — a **second, independent, module-private resolver that does not read `LOCAL_TEST_*` at all** (it goes
  straight to `getSubdomain()` + a fresh `createPlatformClient` + `databases.get(\`${subdomain}-database\`)`,
  `:49-66`). So on `time.localhost:3000` the seal is `{subdomain:'time', group:'los-angeles-group'}` —
  *the same values the pin would have produced*, so the reorder is a no-op. On bare `localhost:3000`,
  `getSubdomain()` returns `''` (`domainActions.ts:49-51`), `databases.get('-database')` fails and
  `fetchTenantInfo` **re-throws by design** (`:73-86`, "CRITICAL: do not silently route to
  los-angeles-group"), so login cannot complete and no session is ever sealed — the case collapses back
  into the first one. `A1_COLDLAUNCH_MONITOR.md:115` records this same divergence independently
  ("Dead-end #2: the `LOCAL_TEST_SUBDOMAIN` pin fixes `getDB()` but NOT the login path").
  Neither local session shim can manufacture a counterexample: `/api/dev-login` is hard-gated on
  `process.env.NODE_ENV !== 'development' → 404` (`route.ts:34-36`) and cannot run under this workflow at
  all; `/api/load-test-login` is fail-closed on `LOAD_TEST_SECRET` + a tenant allowlist.

**Recommended edit — move `:30-37` to sit immediately after `:42`:**

```ts
export const getSubdomainAndGroup = async (): Promise<{ subdomain: string; group: string; }> => {
  // An authenticated session's sealed tenant ALWAYS wins. The LOCAL_TEST_* override below is a
  // local-development convenience and must never be able to repoint a real user's database.
  const cachedTenant = await getTenantFromSession()
  if (cachedTenant) {
    return cachedTenant
  }

  // Local production testing override (pnpm build && pnpm start)
  // Set LOCAL_TEST_SUBDOMAIN and LOCAL_TEST_GROUP to test against production databases locally.
  // Deliberately BELOW the session check: it seeds the pre-login/anonymous path only, which is the
  // only path the documented workflow (INFRA_ACCESS.md:291) actually needs — `fetchTenantInfo`
  // (sessionWrite.ts:48) ignores LOCAL_TEST_* when it seals the session, so the two agree by
  // construction on a real tenant host and disagree only where login could not have succeeded.
  if (process.env.LOCAL_TEST_SUBDOMAIN && process.env.LOCAL_TEST_GROUP) {
    return { subdomain: process.env.LOCAL_TEST_SUBDOMAIN, group: process.env.LOCAL_TEST_GROUP }
  }
  …unchanged from `const startTime = performance.now()` onward
}
```

There is already in-repo precedent for the session-first ordering: `src/app/api/warm/route.ts:65`
does `tenantFromSession ?? await getSubdomainAndGroup()`.

**One residual, worth a doc line rather than code:** a **stale** session cookie minted under a *previous*
pin would now win over a *new* pin on the same host. Remedy is "clear cookies when changing
`LOCAL_TEST_*`". Small, local, and strictly safer than the present behaviour.

**Why a bare `NODE_ENV` guard is wrong:** the branch is explicitly *meant* to run under
`NODE_ENV=production` (`pnpm build && pnpm start`), so `if (process.env.NODE_ENV !== 'production')`
deletes the feature and `if (NODE_ENV === 'production') return` deletes it too. The precedence fix keeps
the feature and removes only the dangerous ordering. **Defence-in-depth complement** (optional, additive):
a `scripts/checks/` assertion that `LOCAL_TEST_*` are unset whenever the host is not localhost — the
guard class that does not exist today.

---

## Q4 — DO-NOT-FIX landmines

Read `.claude/commands/exhaust-improvements.md` § "DO-NOT-FIX landmines (verbatim…)", line 181 and the
eight bullets below it: sequential `for…of`+await on Replicache mutations · `<Suspense>` · mission-control
hardcoded `rgba` · F6 warm-at-tap stale-continuity · FloorPlanViewer public barrel API · share-graph
venue-unscoped reads · **`getServerActionSession` — "IS the auth check (config `serverAuthFunctionNames`);
don't rename to satisfy a builtin list"** · park-ui prop spreading.

**Neither fix touches any of them.** The closest is the `getServerActionSession` bullet, and both fixes
respect it: fix (a) **adds no auth call at all** (it removes an endpoint instead of gating one), and
fix (b/LEAD 19) changes only the *order* of two existing resolutions — `getServerActionSession` is reached
unchanged via `getTenantFromSession` → `cookieActions.ts` and is neither renamed nor bypassed.

**One live constraint does bind, from the same file's calibration notes, item 5:**

> "**Auth/sync findings → queue + escalate, never silently land mid-sweep** (CLAUDE.md escalation rule
> wins over 'just keep working'). Surfacing + planning + flagging IS the correct disposition."

Both of these are auth-path findings. They should be filed and escalated rather than landed inside a
sweep — which matches this task's own read-only constraint.

---

## Method warnings for whoever implements this

* **The action IDs in this document are from a Jul 19 2026 build and are salted per build.** Do not quote
  `0071d116…` as a current fact. Re-derive: `python3 -c "import json;m=json.load(open('.next/server/server-reference-manifest.json'));print([ (k,w) for k,v in m['node'].items() for w in v['workers'].values() if 'tenantContext' in w['filename']][:4])"`.
  The *structural* claims (registered-not-tree-shaken; ID absent from client chunks, 37/79 present as a
  positive control) are what survive a rebuild.
* **`private config` in the `.d.ts` is erasure, not protection.** I only established the token is on a
  plain runtime field by reading the compiled `dist/index.js` constructors. Read the compiled output, not
  the types, whenever the question is "what is on the wire".
* **The brief's ESTABLISHED list says `getAllGroups` is not exported. It is** (`platformActions.ts`, final
  statement). Verdicts unchanged because it is `isPlatformEmail`-gated, but the list is wrong on that line.
* **There are TWO tenant resolvers, not one.** `getSubdomainAndGroup` (tenantContext.ts:29) and
  `fetchTenantInfo` (sessionWrite.ts:48). They diverge on `LOCAL_TEST_*` and agree on everything else.
  Any future change to tenant resolution that touches only one of them is half a change.
