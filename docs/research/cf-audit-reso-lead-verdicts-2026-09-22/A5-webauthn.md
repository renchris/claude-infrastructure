# A5 — WebAuthn / passkey registration + login integrity: adjudication of Cloudflare LEADs 1 and 3

Repo: `reso-management-app` @ `origin/main` (read-only; nothing checked out, no index touched).
Date: 2026-09-22. Framework: `next@16.3.5`, `@simplewebauthn/server@^13.3.2` (`package.json:162,148`).

---

## 0. The shared premise both leads rest on, and why it is SETTLED (not blocked)

Both leads reduce to one deployment fact: **is every export of a module-level `'use server'` file
a network-reachable POST endpoint in this build?**

It is, and reso has already measured it against its own build artifact — three separate in-repo
statements, one of them explicitly verified against `.next/server/server-reference-manifest.json`:

- `eslint-rules/no-ungated-db-export.mjs:3-5` — *"In Next.js App Router a module-level `'use server'`
  directive turns EVERY exported function into a registered POST endpoint."*
- `src/app/actions/auth/authQueries.ts:23-29` — *"Next.js registers all exports of a 'use server'
  module whenever ANY route graph imports them — **SERVER-SIDE importers count** (verified against
  `.next/server/server-reference-manifest.json`: these ids were live dispatch entries). … the only
  barrier was action-id obscurity, not a control."*
- `src/app/actions/auth/credentialDbWrites.ts:18-24` — *"As a `'use server'` export it was
  independently POST-able … a direct call with `{ userID: <victim>, publicKey: <attacker> }` would
  register an attacker's passkey against a victim's account (account takeover)."*

So neither verdict is BLOCKED-ON-DEPLOYMENT-FACT. The "server-side importers count" clause matters
specifically for LEAD 1: the challenge setters have **no** client importer, and that is not a
defence.

Corroborating: there is **no `middleware.ts`** in the repo (`src/middleware.ts` and `middleware.ts`
both absent on `origin/main`), and `next.config.ts` sets no `experimental.serverActions` restriction.
Next's built-in Origin/Host check on action dispatch is a CSRF control against a *victim's browser*;
it does nothing against an attacker issuing the POST themselves with a matching `Origin` header.

---

## 1. LEAD 3 — `consumeInvitationAndRegister` trusts a caller-supplied verifier output

### Verdict: **CONFIRMED as stated — but NOT "account takeover by construction".**

Every factual clause of the lead is true. The severity framing is refuted by one link:
the invite-token compare-and-swap.

### (a) Is the module `'use server'`?

Yes. `src/app/actions/auth/databaseActions.ts:1` is `'use server'`, and the module is imported by
live route graphs (`src/app/api/register/route.ts:4`, dozens of server pages). By §0 this registers
`consumeInvitationAndRegister` as a dispatchable action id. The repo already knows this and
allowlists it explicitly at `databaseActions.ts:1274-1278`:
`// C-007 allowlist: pre-auth invite consumption — gated by possession of a valid admin-issued invite token`.

### (b) Signature — which parameters are caller-supplied?

`databaseActions.ts:1279-1290`:

```ts
export const consumeInvitationAndRegister = async (
  inviteToken: string,
  email: string,
  username: string,
  verification: VerifiedRegistrationResponse,   // :1283  ← the verifier's OUTPUT, as a parameter
  isDiscoverable = false,
  authenticatorAttachment?: string,
): Promise<{ user: User; credentialID: number } | { errorMessage: string }> =>
```

**All six are caller-supplied.** Parameter 4 is exactly the return shape of
`@simplewebauthn/server`'s `verifyRegistrationResponse` — the type is imported at
`databaseActions.ts:3-5` — carrying `verified: boolean` and
`registrationInfo: { credential: { id, publicKey, transports }, aaguid, credentialDeviceType,
credentialBackedUp }`. Server-Action arguments are deserialised from the client's Flight payload;
nothing in the transport authenticates the object's provenance.

### (c) Does it test `verified === true`? — **NO.**

`git grep -n 'verified' origin/main -- src/app/actions/auth/databaseActions.ts` returns exactly ONE
hit, at `:244`, and it is a prose comment (*"absent from the verified result"*). There is no
`verification.verified` read anywhere in the 1700-line module.

What the function does instead (`databaseActions.ts:1306-1319`) is a **shape** guard only:

```ts
const { credential: webAuthnCredential, aaguid, credentialDeviceType, credentialBackedUp }
  = verification.registrationInfo ?? {}                       // :1306-1311
if (
  webAuthnCredential == null                                   // :1316
  || webAuthnCredential.id == null                             // :1317
  || webAuthnCredential.publicKey == null                      // :1318
) { … return { errorMessage: 'Unable to complete registration…' } }
```

Its own comment at `:1313` reads *"defensive runtime guards — verifier output is untrusted"* —
the module names the trust problem and then checks only presence, never the verdict.

### (d) Does it INSERT the caller's credential material? — **YES.**

`databaseActions.ts:1403-1419`, inside the transaction:

```ts
externalID: Buffer.from(isoBase64URL.toBuffer(credID)),     // :1408  ← caller's credential.id
publicKey: Buffer.from(credentialPublicKey),                // :1409  ← caller's credential.publicKey
aaguid,                                                      // :1410  ← caller's aaguid
isDiscoverable,                                              //        ← caller's 5th parameter
credentialDeviceType: credentialDeviceType ?? null,
backedUp: credentialBackedUp ?? null,
transports: webAuthnCredential.transports ? JSON.stringify(…) : null,
```

`signCount` is not supplied and defaults to 0 (`drizzle/schema.ts:118`).

### (e) Is there a trusted path, and does anything FORCE it?

There is a trusted path, and **nothing forces it.**

`src/app/api/register/route.ts:60` calls `verifyRegistration(registrationResponse)`
(`lib/auth/register.ts:90`), which reads the server-issued challenge from the session cookie
(`register.ts:99-102`), calls `verifyRegistrationResponse` with `expectedChallenge` /
`expectedOrigin` / `expectedRPID` / `requireUserVerification: true` (`register.ts:107-113`),
clears the one-time challenge in a `finally` on every outcome (`register.ts:122-131`), and
**rejects `verified === false` at `register.ts:136`**. Only then, at `route.ts:86`, does it pass the
result into `consumeInvitationAndRegister`.

That is a *convention*, enforced by nothing:

- **The type system cannot enforce it.** `VerifiedRegistrationResponse` is a structural TS interface
  with no brand/nominal tag; it is erased at runtime, and the Server-Action boundary deserialises
  an arbitrary JSON object into that slot. `verified: false` and `verified: undefined` are both
  assignable-shaped and both accepted.
- **There is no runtime check.** No session gate (registration is pre-auth by definition), no
  nonce, no server-side handoff token between `verifyRegistration` and `consumeInvitationAndRegister`.
- **The action is separately addressable.** The client never calls it (the browser POSTs
  `/api/register` — `src/app/actions/auth/formActions.ts:141-148`), but §0 establishes that
  non-client-referenced exports are still live manifest entries.

### The concrete attack, in one sentence

**A holder of any live invite token can POST directly to the `consumeInvitationAndRegister` action
id with a hand-written `{ verified: false, registrationInfo: { credential: { id, publicKey } } }`
object and have the server insert a credential it never verified — completing account creation with
a software keypair, no authenticator, no user-verification (`requireUserVerification: true`,
`register.ts:110`) and no origin/RP-ID binding.**

### What bounds it — and why "account takeover by construction" is REFUTED

The insert is unreachable without a live invitation. `databaseActions.ts:1362-1372` is an
UPDATE…RETURNING compare-and-swap requiring **all three** of:

```ts
inviteTokenMatch(inviteToken),        // :1367  sha256-at-rest match on an admin-issued token
eq(invitation.email, normalizedEmail),// :1368  the email must equal the invitation's
activeInviteWhere(now),               // :1370  status='pending' AND not expired
```

0 rows matched ⇒ `{ consumed: null }` ⇒ the whole transaction returns an error and writes nothing.
Invite tokens are 32 random bytes, hashed at rest, emailed once, and rate-limited
(`checkInviteTokenLimit`). Consequently:

- The attacker **cannot choose a victim.** `email` must equal the invitation row's email, and every
  user field is read from the DB row (`consumed.email/firstName/lastName/role`, `:1381-1390`), never
  from the caller.
- The attacker **cannot bind a credential to an existing account.** The function only ever INSERTs a
  new `user` row; `credential.userID = newUser.id` (`:1401`).
- The attacker **cannot collide onto a victim's credential.** `drizzle/schema.ts:115-116` declares
  `externalID` and `publicKey` both `.unique()`, and the whole thing is one `db.transaction`, so a
  collision rolls the CAS back (this is exercised: the test at
  `__tests__/consumeInvitationAndRegister.test.ts:170-172` pre-seeds a colliding row on purpose).
- The attacker gets **no session** from this call — the cookie write lives in the route
  (`route.ts:92`), not in the action.

So the residual, honest harm is: **the passkey-binding step of onboarding is forgeable by the
invitee**, which (i) strips user-verification and origin binding from account creation, (ii) lets a
stolen/forwarded invite link be redeemed headlessly by a script with no browser and no authenticator,
and (iii) lets the row's `aaguid` / `credentialDeviceType` / `backedUp` / `transports` device-provenance
fields be set to anything (they are display-only by design — `drizzle/schema.ts:136`). It is a
**missing second lock on a pre-auth endpoint**, not account takeover.

### The comparison that makes this unambiguous: reso already has the correct shape

There are three credential-insert sites. Exactly one of them checks `verified`, and it is the one
written most recently:

| site | `'use server'` export? | tests `verified`? | live in prod? |
|---|---|---|---|
| `lib/auth/upgrade.ts` `completePasskeyUpgrade:168` | yes | **YES — `:217` `!verification.verified`** (plus `getServerActionSession()` at `:178`, and it calls `verifyRegistration` itself) | yes |
| `databaseActions.ts` `registerUser:229` | yes | no | **no** — hard `NODE_ENV === 'production'` return at `:248-250`, before any DB access |
| `databaseActions.ts` `consumeInvitationAndRegister:1279` | yes | **no** | **YES** |

`upgrade.ts:215-221` is the byte-for-byte template for the fix, and it already carries the same
`@typescript-eslint/no-unnecessary-condition` disable for the same reason.

---

## 2. LEAD 1 — the expected-challenge slot has a network-callable setter

### Verdict: **CONFIRMED.**

### (a) The setter

`src/app/actions/auth/cookieActions.ts:1` is `'use server'`. Two exported, wholly ungated setters
take the expected challenge **as a caller-supplied string** and seal it into the iron-session cookie:

```ts
export const setChallengeToCookieStorage = async (challenge: string) => {   // :29
  const session = await getServerActionSession()
  session.challenge = challenge                                              // :31
  await session.save()
}

export const setDiscoverableChallengeToCookieStorage = async (challenge: string) => {  // :50
  const session = await getServerActionSession()
  session.discoverableChallenge = challenge                                  // :52
  await session.save()
}
```

No session gate, no role check, no value validation, no rate limit. `getServerActionSession()` on an
anonymous request returns a fresh empty session, and `.save()` mints the cookie — so an
**unauthenticated** caller can write the slot for their own browser.

The module IS in the client reference graph (`lib/create-replicache-context.tsx:1` is `'use client'`
and imports four other cookieActions exports at `:21-23`), so these action ids are unambiguously
minted; and per §0 server-side importers alone would suffice anyway.

Commit `962f11ba2` ("dedicated discoverableChallenge cookie slot") is the relevant context: it
**doubled** the exposure by adding a second settable slot (`:50`) rather than moving the first out of
the action surface.

### (b) These are the exact slots the verifier reads

- **Login.** `lib/auth/login.ts:92-97` reads `getDiscoverableChallengeFromCookieStorage()` or
  `getChallengeFromCookieStorage()` by mode, and feeds it straight in as `expectedChallenge` at
  `login.ts:108`. The legitimate writer is `login.ts:69` / `login.ts:227` — the same two setters,
  with SimpleWebAuthn's generated value.
- **Register.** `lib/auth/register.ts:99-102` → `expectedChallenge: challenge` at `register.ts:109`;
  written at `register.ts:164` from `generateRegistrationOptions`' output.
- The slots are declared in the iron-session type at `lib/auth/session.ts:46-56`, both documented as
  **"One-time challenge"**.

### (b continued) Can a captured assertion be replayed? — Yes. Trace, control by control.

1. Attacker POSTs the `setChallengeToCookieStorage` action id with the base64url challenge lifted
   from the captured assertion's `clientDataJSON` → their own session cookie now expects it.
2. Attacker POSTs `/api/passkey-login` with `{ email: <victim's>, authenticationResponse: <captured
   assertion, verbatim> }`, carrying that cookie.
3. `finalizeAssertion` (`login.ts:270`) resolves the credential by `externalID` from
   `authenticationResponse.id` (`login.ts:286-297`) — the victim's row.
4. `verifyAuthenticationStep` (`login.ts:83`) reads the attacker-planted challenge and calls
   `verifyAuthenticationResponse`.

Everything else that would have to hold, **holds by construction on a genuine assertion**:

| control | where | does it stop the replay? |
|---|---|---|
| `expectedChallenge` | `login.ts:108` | **No — this is the control the setter defeats.** |
| `expectedOrigin` | `login.ts:109` | No. A genuine assertion was signed at the real origin. |
| `expectedRPID` | `login.ts:110` | No. Same RP. |
| signature | SimpleWebAuthn | No. Genuine signature over genuine `clientDataJSON` + `authData`. |
| `requireUserVerification: true` | `login.ts:112` | No. The UV bit is set in the captured `authData`. |
| signCount regression | SimpleWebAuthn, vs `credential.signCount` | **No, for synced passkeys.** `login.ts:135-137` states it in the repo's own words: *"For synced iCloud passkeys the signCount is permanently 0, so the counter-regression check never runs and **this challenge is the SOLE replay defense**."* |
| `verified === false` gate | `login.ts:314` | No — a replayed genuine assertion is `verified: true`. |
| email binding (`mode: 'email-first'`) | `login.ts:324` | No. The attacker supplies the victim's email, which is what the DB-resolved user has. |
| userHandle binding (`mode: 'discoverable'`) | `login.ts:255-263`, `login.ts:330` | No. `stored === presented`, both taken from the genuine assertion — and the check short-circuits to `true` when either side is null, which is the case for every first-registration credential (`schema.ts:125-129`). |
| `/api/passkey-login` Origin check (S5) | `route.ts:43-45` | No. It is a CSRF control against a *victim's* browser; an attacker sending the POST sets `Origin` to the tenant origin themselves. |
| per-IP rate limit 30/300s | `route.ts:62-69` | No. One request suffices. |

5. `route.ts:105` calls `authenticatedUserToCookieStorage(result.user, result.credentialID)` →
   **the attacker holds the victim's session cookie.**

The one-time-ness that `register.ts:122-131` and `login.ts:131-142` go to real trouble to guarantee
(clear in a `finally` on every outcome) is **unconditionally undone by a single POST to `:29`.**
A cookie-sealing argument does not rescue this: the attacker is not forging the sealed cookie, they
are asking the server to write it for them.

### Exploitation precondition — stated plainly

The attack needs **one genuine past assertion** for the target credential. Assertions are not
protected by anything other than TLS in transit and the one-time challenge; WebAuthn's own model
treats an assertion as a single-use bearer token whose *only* anti-replay property is the challenge.
With `:29` and `:50` network-callable, an assertion becomes a **permanent reusable password** for
any synced passkey (signCount pinned at 0, so there is no second clock that ever invalidates it).
Realistic capture paths: XSS or a malicious extension on the login page, a compromised
reverse-proxy/TLS-terminating hop, a request-logging layer that records POST bodies, or a shared
door-iPad browser.

That precondition is why this is a **replay-defence removal**, not a remote-unauthenticated
takeover. It is nonetheless a true CONFIRMED finding: a server's expected-challenge slot must never
be writable by the network, and here it is, twice.

### (c) Is the slot server-generated-only or cookie-sealed? — No, and the sealing is irrelevant

REJECTED-by-that-route does **not** apply. The slot is cookie-sealed (iron-session) but is
*written on demand from a caller-supplied argument* at `cookieActions.ts:31` and `:52`.

### Why this one survived reso's own cleanup — the sharpest framing

reso ran exactly this de-actioning sweep on the *same file* and shipped three siblings:

- `src/app/actions/auth/sessionWrite.ts:1-26` — `authenticatedUserToCookieStorage` was extracted OUT
  of `cookieActions.ts` for precisely this reason: *"That directive registers EVERY export as a
  network-reachable POST endpoint … anyone able to invoke it with `{ role: 'admin' }` would have been
  handed a valid admin session cookie."*
- `src/app/actions/auth/authQueries.ts:20-33` — same move, `import 'server-only'`, *"NEVER add
  `'use server'` to this file."*
- `src/app/actions/auth/credentialDbWrites.ts:15-27` — same move, same instruction.

**The challenge setters are the member of that class that was left behind.** And the lint backstop
built to stop a recurrence, `reso-design/no-ungated-db-export`, keys on a **DB-access signal**
(`getDB()` / `db.` / `tx.` + a query method — `no-ungated-db-export.mjs:12-19`, `:53-57`). A pure
cookie-writing export touches no DB, so it is structurally invisible to the rule. The rule is not
broken; its population never included this shape.

---

## 3. Fix specs — OPERATOR-GATED, MUST NOT BE LANDED SILENTLY

🚨 **Both of these are auth/session-class changes. Under this programme's own rule —
`.claude/commands/exhaust-improvements.md:212`, *"Auth/sync findings → queue + escalate, never
silently land mid-sweep (CLAUDE.md escalation rule wins over 'just keep working')"* — and under the
global G2 escalation surface (auth/session), NEITHER may be landed without the operator's explicit
decision. What follows is a SPEC, not a change. Nothing in this session was edited or committed.**

### FIX 3 — `consumeInvitationAndRegister` must reject an unverified verdict

**Minimal, safest edit.** One file, one condition, no signature change, no route change, no caller
change. `src/app/actions/auth/databaseActions.ts:1315-1319` — add `verified` to the guard already
there, making it byte-identical in shape to the shipped exemplar at `lib/auth/upgrade.ts:215-220`:

```ts
  /* eslint-disable @typescript-eslint/no-unnecessary-condition */
  if (
    !verification.verified                       // ← ADD THIS LINE
    || webAuthnCredential == null
    || webAuthnCredential.id == null
    || webAuthnCredential.publicKey == null
  ) {
```

The existing error branch (`:1320-1329`) already logs `register_error` /
`error: 'invalid_credential_data'` and returns the generic message — no new branch needed. Consider
`error: 'unverified'` to match `upgrade.ts:227` so the two surfaces are distinguishable in the
auth-flow log; that is cosmetic and optional.

**Behaviour on the legitimate path: unchanged.** `/api/register` only reaches line 86 with an object
that already passed `register.ts:136`'s `if (!verification.verified) return { errorMessage }` — so
`verified` is always `true` there.

🚨 **MANDATORY COMPANION EDIT — without it this reds 6 tests.** The fixture
`makeVerification()` at `src/app/actions/auth/__tests__/consumeInvitationAndRegister.test.ts:174-181`
**omits `verified`** (it builds `{ registrationInfo: { credential: {id, publicKey}, aaguid } }` and
casts `as unknown as VerifiedRegistrationResponse`), so `verification.verified` is `undefined` and
every call at `:235, :269, :313, :329, :366, :386, :395` would take the new reject branch. Add
`verified: true,` to that object literal. A green suite after this fix without touching the fixture
would mean the guard is not being exercised.

**Recommended second edit, same class, zero risk:** apply the identical one-line guard to
`registerUser` at `databaseActions.ts:270-274`. It is prod-inert (`:248-250`), so this is
defence-in-depth against a future removal of that `NODE_ENV` gate.

**The structurally stronger fix, for the operator to weigh:** change the parameter type from
`VerifiedRegistrationResponse` to `RegistrationResponseJSON` and have
`consumeInvitationAndRegister` call `verifyRegistration` itself — i.e. make the unverified state
*unrepresentable* at the boundary rather than *checked* at it, which is what
`completePasskeyUpgrade` does (`upgrade.ts:16` imports `verifyRegistration`; `:178` gates on
session; `:217` gates on verified). Cost: it touches `register/route.ts:60-88`, moves the
`credProps.rk` / `authenticatorAttachment` reads (which must stay on the RAW response —
`route.ts:69-83`), and changes the dev branch too. **Recommendation: ship the one-line guard now;
file the type-level refactor separately.** A larger auth refactor under escalation is a worse trade
than closing the hole.

### FIX 1 — take the expected-challenge setters off the action surface

**The edit is a MOVE, not a logic change, and it has a shipped precedent three times over.**

Create `src/app/actions/auth/challengeStore.ts` beginning with `import 'server-only'` (NOT
`'use server'`) and carrying a header in the shape of `sessionWrite.ts:1-26`. Move all six challenge
accessors out of `cookieActions.ts:29-65` into it verbatim:

- `setChallengeToCookieStorage` (`:29`) and `setDiscoverableChallengeToCookieStorage` (`:50`) — the
  two that MUST move; they are the writable expected-challenge slots.
- `getChallengeFromCookieStorage` (`:35`), `getDiscoverableChallengeFromCookieStorage` (`:56`),
  `clearChallengeFromCookieStorage` (`:40`), `clearDiscoverableChallengeFromCookieStorage` (`:61`) —
  move with them for cohesion; they are lower-risk but belong to the same unit and leaving them
  behind re-creates the "one member left in the action module" failure that caused this.

Then repoint the three importers, all of which are **server modules** (no client import exists —
verified: `lib/create-replicache-context.tsx:21-23`, the only `'use client'` importer of
`cookieActions`, takes `clearCookies`, `getSessionMeta`, `getRegisteredUserFromCookieStorage`,
`slideSessionIfStale` and none of the challenge accessors):

- `lib/auth/login.ts:26-32`
- `lib/auth/register.ts:17-20`
- `lib/auth/upgrade.ts:11`

Test-mock paths must move with them: `lib/auth/login.test.ts:73`, `lib/auth/register.test.ts:51` and
`:106`, `lib/auth/upgrade.test.ts:47`, `lib/auth/credential-change-events.test.ts:41` all
`vi.mock('@actions/auth/cookieActions', …)` — each needs a second `vi.mock` on the new path (or the
mock retargeted). This is the only real work in the change.

**Behaviour change: none.** Every current caller is server-side, so `import 'server-only'` removes
the endpoints and nothing else — the same "zero behavior change" close `sessionWrite.ts:16-17`
records for its own move.

**Do NOT instead:** add a session check to `setChallengeToCookieStorage`. It is called pre-auth by
construction (login and registration both run before a session exists), so a gate cannot exist
there — which is exactly `sessionWrite.ts:20-21`'s argument that *"a gate cannot exist here, so the
endpoint must not."*

**Optional hardening, separate change:** extend `reso-design/no-ungated-db-export` (or add a sibling
rule) so the signal is not only DB access but also *writing a field of the iron-session object* in a
`'use server'` export. That would have caught this, and would catch the next one.

---

## 4. DO-NOT-FIX conflict check — `.claude/commands/exhaust-improvements.md:181-190`

Read in full. The ten landmines are: sequential `for…of` Replicache mutations; `<Suspense>`;
mission-control hardcoded `rgba`; F6 warm-at-tap stale continuity; FloorPlanViewer barrel API;
share-graph venue-unscoped reads; **`getServerActionSession` — IS the auth check (config
`serverAuthFunctionNames`); don't rename to satisfy a builtin list** (`:189`); park-ui prop spreading.

**Neither fix contradicts any of them.**

Specifically on `:189`: both fixes **preserve** `getServerActionSession` untouched. FIX 1 moves the
challenge accessors — which each call `getServerActionSession()` (`cookieActions.ts:30, 36, 41, 51,
57, 62`) — into a new module **calling it by the same name**. Nothing is renamed, nothing is
replaced with a different gate, and the `serverAuthFunctionNames` config and the
`no-ungated-db-export` `GATE_NAMES` set (`no-ungated-db-export.mjs:36`) both keep matching. FIX 3
adds no auth call at all.

One nearby item deserves an explicit non-collision note: `:188` "share-graph venue-unscoped reads —
intentional (Decision 4, per-venue RBAC); a security lens WILL flag it". That is a *different*
surface (`pullActions.ts` read path) and is not touched by either fix.

And `:212` is the governing instruction for disposition: **queue + escalate, never silently land.**

---

## 5. Adversarial pass — what I checked that neither lead named

Three axes I assumed irrelevant and then went and measured. Two came back clean; one is the reason
LEAD 3's severity is bounded.

1. **Is there a worse sibling — a session minter on the action surface?** This would outrank both
   leads. **Closed already.** `sessionWrite.ts` carries `import 'server-only'`, not `'use server'`
   (`:27` is the first import; there is no directive), and its header `:8-17` records that it was
   moved out of `cookieActions.ts` for exactly this reason. Its four callers are all routes.
2. **Is there an "add a passkey to an existing account" endpoint with the LEAD-3 shape?** That would
   be the true account-takeover primitive. **Closed already, twice over.**
   `insertDiscoverableCredential` (`credentialDbWrites.ts:39`) takes `userID` as a parameter but the
   module is `import 'server-only'` (`:1`) with a header that spells out the takeover it would be
   (`:18-24`); its sole caller `completePasskeyUpgrade` binds `userID = session.user.id` after
   `getServerActionSession()` (`upgrade.ts:178`) and after `!verification.verified` (`:217`).
3. **Does the dev-only `registerUser` bypass the invite gate in production?** It is a `'use server'`
   export with no invite gate and an unverified `verification` parameter — i.e. LEAD 3 with the CAS
   removed, which WOULD be unauthenticated admin account creation. **Broken by a real link:**
   `databaseActions.ts:248-250` hard-returns `'Legacy registration is not available.'` on
   `NODE_ENV === 'production'`, before any DB access. Likewise `/api/dev-login/route.ts:35` returns
   on `NODE_ENV !== 'development'`.
4. **Does anything force the LEAD-3 attack to be more than invite-gated?** I looked for the escape
   in four places and found none: the email is DB-sourced (`:1381-1390`), the role is DB-sourced,
   `externalID`/`publicKey` are `.unique()` (`schema.ts:115-116`) inside one transaction so a
   deliberate collision rolls back, and the action itself mints no cookie. This is what converts
   the lead's "account takeover by construction" into "forgeable passkey binding for an invitee".

**Residual uncertainty, stated rather than hidden:** I did not build the app, so I did not read
`.next/server/server-reference-manifest.json` on this machine to see these specific action ids as
live dispatch entries — the task forbids installs/builds. I am relying on reso's own recorded
measurement of exactly that file (`authQueries.ts:23-29`), taken against this same action surface.
If the operator wants the last link nailed down first-hand, the single check is: build, then
`jq 'keys' .next/server/server-reference-manifest.json | grep -c .` and confirm an id resolves to
`src/app/actions/auth/cookieActions.ts#setChallengeToCookieStorage`.
