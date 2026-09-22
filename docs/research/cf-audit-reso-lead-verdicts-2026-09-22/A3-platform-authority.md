# LEAD 8 — platform-operator authority is decided by tenant-writable data

**VERDICT: CONFIRMED.** Every link in the chain closes. A tenant admin, using only the
shipped Admin → Team UI (no crafted request, no server-action forgery), mints a second
account whose `user.email` they choose, logs into it, and that session passes
`isPlatformEmail()` — which is the *sole* gate on the Turso **control plane** for the
whole fleet.

Adjudicated read-only against `origin/main` in `/Users/chrisren/Development/reso-management-app`
on 2026-09-22. Every citation is `git show origin/main:<path>`.

---

## 1. The chain, link by link

### (a) What makes an email "platform" — `lib/auth/platform-email.ts:11-18`

```ts
export const isPlatformEmail = (email: string): boolean => {
  const normalized = normalizeEmail(email)              // :12  — LOCAL normalizer, strips +tag
  const personalEmail = process.env.PERSONAL_PLATFORM_EMAIL
  const domainPattern = process.env.PLATFORM_EMAIL_DOMAIN

  if (personalEmail && normalized === normalizeEmail(personalEmail)) return true
  if (domainPattern && normalized.endsWith(domainPattern.toLowerCase())) return true
  return false
}
```

Two env-var arms. **The env vars themselves are NOT tenant-writable — that half of the
link is sound.** What is tenant-writable is the *left-hand operand*: the email string the
predicate is applied to. So the question is not "can a tenant set the rule", it is "can a
tenant supply a string that satisfies the rule", and the answer is yes on **both** arms:

| arm | how a tenant admin satisfies it |
|---|---|
| **suffix** — `normalized.endsWith(PLATFORM_EMAIL_DOMAIN)` | `PLATFORM_EMAIL_DOMAIN` is `@reso.gl` (`.env.example:191`, and verified live in production SSM `/amplify/djnbdqpvc08g4/main/` on 2026-08-07 per `docs/plans/DOCS_CONSOLIDATION_100P.verdicts.tsv:1023`). The **whole domain is the credential** — there is no local-part allowlist. Any string ending `@reso.gl` wins. |
| **exact** — `PERSONAL_PLATFORM_EMAIL` | The local `normalizeEmail` (`:6-9`) strips `/\+.*$/`, while the auth-canonical one (`lib/auth/normalize-email.ts:12-14`, NFKC + lowercase + trim) does **not**. The gate is therefore strictly **LOOSER than the store**: `ren.chris+anything@outlook.com` is a distinct row for uniqueness purposes and collapses to the operator's address at the gate. |

Deployment fact, not assumed: both vars are `APP_INVARIANT_KEYS` on **every** region app —
`scripts/setup/bootstrap-region.pure.ts:2111-2113` (`PERSONAL_PLATFORM_EMAIL`,
`PLATFORM_EMAIL_DOMAIN`), alongside `TURSO_PLATFORM_API_AUTH_TOKEN` at `:2100`. So the
predicate is live and the control-plane token is present on every deployment that serves
any tenant.

**This mechanism has already bitten this repo once, and the record is in-tree.**
`src/app/actions/auth/databaseActions.ts:531-534`:

> `admin+<sub>@reso.gl` — the original (… phase 5). Removed by `04fdc74b8`, which found
> that `isPlatformEmail()` strips plus-addressing before matching, so it normalised to
> `admin@reso.gl` and **made the phantom PLATFORM-PRIVILEGED in every tenant**.

That fix changed the *provisioner's chosen string*. It did not change the *mechanism* —
a `@reso.gl` value in a tenant's own `user.email` column still confers fleet-wide platform
authority. The accidental instance was removed; the deliberate one is what this lead names.

### (b) Where `session.user.email` comes from — the TENANT database, sealed at login

`src/app/actions/auth/sessionWrite.ts:207-211`:

```ts
session.user = {
  id: user.id,
  email: user.email,        // ← the tenant DB's user row, verbatim
  username: user.username,
  role: ...,
```

`user` here is a full row selected from the **tenant** database (`getDB()` resolves by
subdomain; `authenticatedUserToCookieStorage` is called by `/api/register/route.ts:98`
and by the passkey-login route). It is sealed into the iron-session cookie
(`lib/auth/session.ts:26-38`) and read back by `getRegisteredUserFromCookieStorage`
(`src/app/actions/auth/cookieActions.ts:7-11`).

`hasPlatformAccess` (`src/app/actions/auth/accessActions.ts:25-31`) reads that **cookie**
value with no re-read from the DB — note the asymmetry with its sibling
`hasAdminAccess` (`:39-56`), which was deliberately hardened by H-AUTH1 to re-read the
role fresh *"fail-closed if the row is gone"*. The platform check never got that
treatment. (This does not create the escalation, but it means a platform-shaped row that
is later corrected still holds authority for up to the 12h session TTL.)

### (c) Write paths to `user.email` — exactly two, and one is live in production

`git grep -n "insert(drizzleUser)"` over `origin/main` returns **two** sites, and there is
**no** `update(...).set({ email })` anywhere in `src/` or `lib/` (no `updateUser`, no
Replicache mutator touches the `user` table):

| site | reachable in production? | email source |
|---|---|---|
| `databaseActions.ts:301` (`registerUser`) | **NO** — hard `return { errorMessage: 'Legacy registration is not available.' }` when `NODE_ENV === 'production'`, before any DB read (`:247-249`). Prod-inert. | client param |
| `databaseActions.ts:1386` (`consumeInvitationAndRegister`) | **YES** — the production branch of `/api/register/route.ts:96-98` | `consumed.email` — the **invitation row** |

So the only production writer takes the email from the `invitation` row. Who writes the
`invitation` row?

`databaseActions.ts:921-927`:

```ts
export const sendInvitation = async (
  firstName: string, lastName: string, email: string, role: UserRole,
): Promise<{ rawToken: string; invitingUserID: number } | { errorMessage: string }> => {
  await ensureAdminAccess()
```

**`ensureAdminAccess()` only** — tenant admin, not platform. `email` and `role` are
caller-supplied and are written straight into the row (`:984-996`). The one content check
is RT-F9 (`:944-951`): refuse if that exact normalized email already has a `user` row *in
this tenant*. That blocks re-use of an address already taken here; it does nothing about
`attacker-anything@reso.gl`, and nothing about the operator's own address in a tenant
where it has no row.

### (d) Verdict on the chain — CLOSED

```
tenant admin (any of the 10 tenants)
  └─ sendInvitation("A","B","x@reso.gl", "admin")        databaseActions.ts:921  [ensureAdminAccess]
       └─ invitation row  { email: 'x@reso.gl', role: 'admin' }
       └─ returns { rawToken }                            :1004  ← to the ADMIN, not to the mailbox
  └─ opens  <origin>/register?invite=<rawToken>           InviteForm.tsx:219
       └─ WebAuthn ceremony with the ATTACKER's own passkey, username of their choosing
       └─ consumeInvitationAndRegister                    :1386
            └─ INSERT user { email: consumed.email = 'x@reso.gl', role: 'admin' }
       └─ authenticatedUserToCookieStorage                sessionWrite.ts:207
            └─ session.user.email = 'x@reso.gl'
  └─ isPlatformEmail('x@reso.gl') === true                platform-email.ts:16
```

No link is broken. Nothing in the path verifies control of the mailbox — the invite token
**is** the capability, and `sendInvitation` hands it to the admin who created it. The
attacker never needs to receive an email, never needs to forge a server action, and never
leaves the product's own UI.

**Blast radius of the resulting session** (everything gated on `isPlatformEmail` /
`ensurePlatformAccess`, which is email-only — role is irrelevant to it):

- `platformActions.getAllGroups` (`:15`) / `getAllDatabases` (`:57`) — enumerate **every**
  Turso group and database in the org, all tenants.
- `platformActions.deleteDatabase` (`:79`) — destroy a tenant database. Its only content
  guard (`:90-99`) refuses names present in the `TENANTS` manifest with `isServing`.
  **`parent-schema-database-lax` and `parent-schema-database-singapore` are not in the
  manifest** (`git show origin/main:lib/config/tenants.ts | grep parent-schema` → empty;
  the manifest's ten `dbName` entries are all `<sub>-database`), so the shared parent
  schemas every Fly child inherits are destroyable in one call.
- `provisionActions.*` — `requirePlatform()` (`:59-65`) is the same predicate:
  `startProvisionRun` (`:114`), `sendFirstAdminInvite` (`:307`).
- `databaseActions.deleteUser` (`:596`) — the platform-staff-only member removal.
- `lambdaActions` (`:188`).
- The control-plane client itself: `getPlatformDB` (`tenantContext.ts:21-27`) is
  `TURSO_PLATFORM_API_AUTH_TOKEN`, an **org-wide** token present on every region app.

There is **no host/path gate** in front of any of this: `middleware.ts` matches only for
CSP (`:83`, no auth or admin/platform handling), and `/admin/(settings)/platform/page.tsx:23`
gates on the same `isPlatformEmail`. So the escalated session reaches the console from
whichever tenant host it logged into.

Finally, the repo states the very invariant this breaks —
`platformActions.ts:11-13`:

> Platform-only: cross-tenant Turso group/DB operations gate on platform email …
> **NOT tenant-admin — a tenant admin must not enumerate or destroy infrastructure
> outside their tenant.**

This is a violation of a written invariant, not a severity judgement call.

---

## 2. The second half — `sendInvitation` returns the raw token

**Yes, and it is worse than "returns to its caller": the UI renders it as a clickable
link.**

- `databaseActions.ts:1004` — `return { rawToken, invitingUserID: caller.id }` on the
  create path; `:975` returns a freshly **rotated** raw token for an orphaned pending
  invite.
- `InviteForm.tsx:204-219` — the admin's browser receives it and builds
  `` `${window.location.origin}/register?invite=${rawToken}` ``, shown in a show-once panel.
- `InvitationsList.tsx:61, 98, 126` — `buildInviteUrl(rawToken)` behind a **"reveal"**
  action fed by `resendInvitation` (`databaseActions.ts:1151`, `ensureAdminAccess`, mints
  and returns a fresh raw token on every call). So an admin can re-mint and reveal the
  token of an invitation *intended for someone else*, invalidating the real invitee's copy
  in the process (`:1210-1216` overwrites `externalID` with the new hash).

What a tenant admin can do with a raw token, from the consume path
(`consumeInvitationAndRegister`, `:1279-1400`, and `api/register/route.ts`):

| field of the new account | chosen by |
|---|---|
| **email** | the ADMIN, at `sendInvitation` (written to the invitation row, copied to `user.email` at `:1386`) |
| **role** (incl. `admin`) | the ADMIN, same call |
| first/last name | the ADMIN |
| **username** | the REGISTRANT, free text, `trimmedUsername` (`:1293`), only length/uniqueness checked |
| **passkey** | the REGISTRANT's own authenticator |
| tenant | fixed — the host the register request hits |

The CAS at `:1362-1370` requires the client-supplied `email` to equal the invitation row's,
so the registrant cannot *change* the email — but they do not need to: the admin already
chose it. The design note at `:1424-1427` ("the address is `consumed.email` … the only one
of the two that cannot be influenced by the caller") is true of the *registrant* and
silently false of the *inviting admin*, who is the attacker here.

**Not a viable variant (checked, ruled out):** enrolling a passkey onto the surviving
`admin+<sub>@reso.gl` bootstrap-anchor row that still exists in all 8 pre-2026-08-23
tenants (`databaseActions.ts:537-545`). `insertDiscoverableCredential` is `server-only`
(`credentialDbWrites.ts:1, 15-27`), not a `'use server'` export, and its sole caller binds
`userID = session.user.id` (`lib/auth/upgrade.ts`). Login requires a credential row, and
the anchor has none. That path is genuinely closed — the header comment explains exactly
why, and it is the pattern the fix below should be modelled on.

---

## 3. Recommended fix

🚨 **OPERATOR-GATED. This is auth/session-class.** It touches the platform-authority
decision and the invitation flow — G2 escalation surface in the global CLAUDE.md, and
`exhaust-improvements.md` note 5 verbatim: *"Auth/sync findings → queue + escalate, never
silently land mid-sweep."* Nothing below was applied; this is read-only analysis.

### Why "tighten the pattern" is NOT the fix

The obvious repair — drop the `endsWith` suffix arm and keep only an exact allowlist —
**does not close the chain.** An exact allowlist is still matched against a
tenant-writable string, and `PERSONAL_PLATFORM_EMAIL` has no `user` row in most tenants,
so RT-F9 does not block inviting it. A tenant admin invites the operator's own address in
their tenant and escalates identically. The suffix arm widens the attack (any local part)
but is not what creates it. **The data source is the defect.**

### Fix A — the chokepoint guard (minimal, self-contained, closes the live path today)

The only production writer of a platform-shaped `user.email` is the invitation row, and the
only writer of that is `sendInvitation`. Refuse to *create* one unless the caller is
already platform. Exact edit, `src/app/actions/auth/databaseActions.ts`, immediately after
`const normalizedEmail = normalizeEmail(email)` (`:937`) and before the RT-F9 read:

```ts
// Platform authority is decided by `isPlatformEmail(session.user.email)`, and the only
// production writer of `user.email` is this invitation row (consumeInvitationAndRegister
// :1386). A tenant admin who may mint a platform-shaped address is therefore a platform
// operator by construction — the same defect `04fdc74b8` fixed for the provisioning
// anchor (:531-534), reachable here deliberately instead of accidentally.
if (isPlatformEmail(normalizedEmail) && !(await hasPlatformAccess())) {
  return { errorMessage: 'Unable to process this invitation request.' }
}
```

Requires exporting `hasPlatformAccess` from `accessActions.ts` (today only the `ensure*`
wrappers are exported, `:77-81`) — or calling `ensurePlatformAccess()` in a try/catch,
which changes the throw shape; the boolean is cleaner. `isPlatformEmail` is already
imported there via `accessActions`; add the direct import from `@lib/auth/platform-email`.

Note the message is deliberately the same generic string `sendInvitation` already returns
at `:982`, so the guard is not an oracle for `PLATFORM_EMAIL_DOMAIN`.

**Belt-and-braces companion** (same class, one line) in `consumeInvitationAndRegister`,
after the CAS at `:1370`: refuse when `isPlatformEmail(consumed.email)` and the row's
`invitingUserID` does not resolve to a platform user — this covers invitation rows already
sitting `pending` in the fleet from before the guard lands, which Fix A cannot retroactively
remove.

**Residual Fix A does not cover, stated rather than hidden:** it re-uses the same loose
`isPlatformEmail` on the write side as on the read side, so the two can never disagree —
that is its virtue — but it leaves platform authority *resting on tenant data*. Any future
write path to `user.email` (an admin "edit member" feature, a data migration, a support
tool, a direct Turso write by anyone holding a tenant token) re-opens the chain with no
test failing. It buys time; it does not restore the invariant.

### Fix B — move the decision off tenant-writable data (the actual repair)

Decide platform authority on something a tenant cannot write. In descending order of
strength:

1. **Credential public key allowlist.** Bind platform authority to the WebAuthn credential,
   not the email: an env/SSM list of base64url SHA-256 digests of the operator's credential
   public keys, compared at the platform gate against the `credential` row for
   `session.user.credentialID`. A tenant admin can enrol *their own* passkey and cannot
   produce the operator's public key, so the operand is unforgeable — and the repo already
   proved this shape works, at `credentialDbWrites.ts:15-27`. Cost: the operator must
   enrol in each tenant they administer, and the digest list is a real operational artifact.
2. **Control-plane principal table.** A row in a database the tenant app can only *read*
   (or a signed claim minted by the control plane), keyed on `(subdomain, user.id, email)`
   — all three compared. Weaker than (1): row ids are predictable, so it rests on the
   attacker being unable to occupy a specific id in a specific tenant.
3. **Exact allowlist only, suffix arm deleted.** Necessary hygiene, *insufficient alone*
   (see above). Do this **with** Fix A, never instead of it.

Whatever is chosen, the two `normalizeEmail` implementations must be reconciled — a gate
that normalizes more aggressively than the store it reads from is a standing
false-accept generator, independent of this lead
(`platform-email.ts:6-9` vs `lib/auth/normalize-email.ts:12-14`;
already documented as a known divergence at `lib/alerts/lead-classify.pure.ts:35-52`).

### Two adjacent gaps surfaced in passing (not part of the verdict, worth filing)

- **`hasPlatformAccess` trusts the sealed cookie** (`accessActions.ts:25-31`) while its
  sibling `hasAdminAccess` re-reads the DB (`:39-56`, H-AUTH1). Correcting a
  platform-shaped row does not end the session it minted for up to 12h.
- **No durable audit of platform actions.** `deleteDatabase` success emits nothing;
  `sendInvitation` logs `console.warn("Created invitation <id>")` (`:1003`) with no actor
  and no address; `logAccessDenied` (`:11-22`) records denials and *deliberately omits
  identity*. After a successful escalation there is no record naming who did it.

---

## 4. DO-NOT-FIX check — `.claude/commands/exhaust-improvements.md` § DO-NOT-FIX landmines (`:181-190`)

Read in full. **No conflict.**

| landmine | applies? |
|---|---|
| Sequential `for...of`+await on Replicache mutations | no |
| `<Suspense>` banned | no |
| mission-control hardcoded `rgba` | no |
| F6 warm-at-tap stale-continuity | no |
| FloorPlanViewer barrel API | no |
| share-graph venue-unscoped reads (by-design; "a security lens WILL flag it") | **no** — different surface; this finding is cross-*tenant* control plane, not per-venue RBAC |
| **`getServerActionSession` IS the auth check — don't rename** | **acknowledged and respected.** Neither fix renames, wraps, or removes it; `platformActions.ts` keeps calling it, and Fix A adds a check *after* it |
| park-ui prop spreading | no |

Note 5 of the calibration section (`:212-213`) *mandates* the disposition taken here:
surface, plan, escalate — do not land mid-sweep.

---

## 5. Adversarial self-pass — what I tried to break this with

| challenge | result |
|---|---|
| "Maybe `registerUser` is the real hole (ungated, arbitrary email, `admin: true`)." | Refuted. Prod-inert at `:247-249` before any DB access. |
| "Maybe `isPlatformEmail` reads something the tenant cannot influence at all." | Half-true and it is the trap: the **rule** is env-side and safe, the **operand** is tenant DB data. The lead's framing is correct. |
| "Maybe `PLATFORM_EMAIL_DOMAIN` is unset in production, making this latent." | Refuted twice: `APP_INVARIANT_KEYS` (`bootstrap-region.pure.ts:2111-2113`) requires it on every region app, and it was read live from production SSM as `@reso.gl` (verdicts.tsv:1023). And the `PERSONAL_PLATFORM_EMAIL` arm works even if the suffix arm were unset. |
| "Maybe an `update user.email` path exists that is *better* than the invite dance." | None exists — two inserts, zero email updates, no Replicache mutator on `user`. The invite path is the only one, which is why Fix A has a single chokepoint. |
| "Maybe the surviving `admin+<sub>@reso.gl` anchor rows are the easier attack." | Refuted. No credential, and credential insertion is `server-only` + session-bound (`credentialDbWrites.ts:15-27`). Those rows are inert — but they are live proof the mechanism confers authority. |
| "Maybe middleware or a host check confines `/admin/platform` to a platform tenant." | Refuted. `middleware.ts` is CSP-only (`:83` matcher); the page gates on the same predicate (`platform/page.tsx:23`). |
| "Maybe `deleteDatabase`'s serving guard contains the damage." | Partly — it protects manifest tenants that are `isServing`. It does **not** protect `parent-schema-database-*` (absent from `lib/config/tenants.ts`) or any `dormant` tenant, and it does not constrain `getAllGroups`/`getAllDatabases`/`provisionActions` at all. |
| "Maybe this is already filed and accepted." | Adjacent findings are recorded in `docs/plans/DOCS_CONSOLIDATION_100P.verdicts.tsv:1023` (quoting `docs/research/tenant-provisioning-100p/H1-threat-model.md`, which is **not present on `origin/main` today** — the path returns nothing). That note reaches the *bare-`endsWith`* and *two-normalizers* facts. I found **no** record anywhere in-tree of the **invite→register→escalate chain** being traced end-to-end or accepted. Treat this as net-new. |

---

## 6. One-line reproduction, for whoever validates this

From any tenant with an admin session: Admin → Team → Invite, `email = qa-probe+1@reso.gl`,
role `Admin` → copy the revealed `/register?invite=…` link → open it in a fresh profile →
create a passkey, pick any username → land on `/admin/platform` and observe every Turso
group and database in the org. **Do not run this against production**; it writes a real
user row into a live tenant and the removal verb (`deleteUser`) is itself platform-gated.
