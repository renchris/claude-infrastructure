# A4 — Push / Pusher leads 9, 16, 20 — adjudication

Read-only, against `origin/main` in `/Users/chrisren/Development/reso-management-app`
(no checkout, no edit, no index touch). Every citation is `git show origin/main:<path>` line
numbering. 2026-09-22.

| Lead | Verdict |
|---|---|
| 9 (a) credential | **CONFIRMED** — a Soketi/Pusher **SECRET** (the publish credential) is a repo literal, and the repo's own shipped bootstrapper *enforces* that it is the live identity |
| 9 (b) channel scope | **CONFIRMED as stated, but already held + correctly triaged as low** — channels are public, payload carries no rows |
| 16 | **CONFIRMED** — `saveSubscription` stores the endpoint with **zero** validation; all three named send-time bypasses land |
| 20 | **CONFIRMED** — no row cap, no concurrency bound, limiter meters CALLS on one of three send paths and fails open |

---

## LEAD 9 (a) — CREDENTIAL: is a PUBLISH credential a repository literal?

**Yes, and it is the live one.** The distinction the brief asks for is decisive here: this is not
a Pusher `key` (public by design). It is `secret`, the HMAC signing key for the Pusher-protocol
**backend/publish** API.

### The literal, by variable name and line

`lib/poke/send-poke.ts`, `getCredentials()` — every region falls back to the same three literals:

```
:173-175  appId: process.env.SOKETI_APP_ID_LOS_ANGELES || 'app-id',
          key:   process.env.SOKETI_APP_KEY_LOS_ANGELES || 'app-key',
          secret: process.env.SOKETI_APP_SECRET_LOS_ANGELES || 'app-secret',   ← PUBLISH SECRET
:181      secret: process.env.SOKETI_APP_SECRET_OREGON    || 'app-secret'
:187      secret: process.env.SOKETI_APP_SECRET_SINGAPORE || 'app-secret'
:193      secret: process.env.SOKETI_APP_SECRET_ASHBURN   || 'app-secret'
:199      secret: process.env.SOKETI_APP_SECRET_DALLAS    || 'app-secret'
:205      secret: process.env.SOKETI_APP_SECRET           || 'app-secret'   (default arm)
```

and `getFallbackCredentials()` repeats it at `:229, :235, :241, :247, :253`.

The **server side** carries the same literal, committed:
- `infrastructure/soketi-oregon/soketi-config.json:8-10` — `{"id":"app-id","key":"app-key","secret":"app-secret"}`
- `infrastructure/soketi-oregon/caddy-migration.sh:130` — same, for the EC2 Oregon box that serves live customers
- `infrastructure/soketi-{lax,singapore,iad,dfw}/fly.toml:12-13` — *"Soketi uses default credentials (app-id, app-key, app-secret) / This is safe for internal B2B app with public channels and empty poke payloads"*

### Why this is a live deployment fact and not a dormant fallback

Three independent in-repo statements, the last of which is **executable code**:

1. `lib/poke/send-poke.ts:101-104` — *"Oregon+Singapore run single-app Soketi where the placeholder
   `app-id`/`app-key`/`app-secret` ARE the real identity (SSM probe 2026-06-19), so asserting them
   would break ~6/8 tenants."* (This is why `requireHostInProd` at `:106-114` fails closed on the
   HOSTNAME and deliberately leaves the CREDENTIALS alone.)
2. `.claude/team-briefs/W1-region-app-secret-leg.md:57-59` — *"🚨 MUST NOT be set — assert their
   ABSENCE … `SOKETI_APP_{ID,KEY,SECRET}_<STEM>` — stock Soketi credentials ARE the identity …
   Setting a non-matching value BREAKS ALL POKES."*
3. **Shipped code enforcing it**: `scripts/setup/bootstrap-region.pure.ts:2312-2329`
   `decideForbiddenAppSecrets()` returns `ok:false` if a real `SOKETI_APP_SECRET_<STEM>` is present
   on a region app, with reason *"Stock Soketi credentials ARE the identity … BREAKS ALL POKES"*;
   pinned by `tests/bootstrap-region.test.ts:1373`. **The region bootstrapper refuses to stand up a
   region that has a non-default secret.** That is the repo actively maintaining the vulnerable
   state — so no deployment probe is needed to call this confirmed.

### Why the secret matters even though the channels are empty

The `fly.toml` safety note reasons only about the **read** direction (subscribe). The secret governs
the **write** direction, and that surface is publicly reachable:

- `infrastructure/soketi-lax/fly.toml:32-54` maps public **443 → internal 6001**, and 6001 is the
  single port serving *both* the WebSocket handshake *and* the Pusher HTTP backend API. `send-poke`
  itself uses exactly that path from AWS Amplify (`getPusherClient`, `:43` port `443`, `:57-58` host
  = the public hostname). Public hostnames are literals in the repo too:
  `send-poke.ts:130` `'sync-us-sw.reso.gl'`, `:136` `'sync-us-e.reso.gl'`, `:142` `'sync-us-c.reso.gl'`.
- `SOKETI_DEFAULT_APP_ENABLE_CLIENT_MESSAGES=false` (`fly.toml:15`) blocks client-side event
  injection — so the app secret is *the only thing* between the open internet and arbitrary publish.

What a holder of `app-id`/`app-key`/`app-secret` can do against `https://sync-us-sw.reso.gl`:

| Capability | Mechanism | Impact |
|---|---|---|
| Forge `deployment-event` on the static `deployments` channel | `listenActions.ts:506-511` binds `handleDeploymentEvent`; `:295-308` calls `resolveVersionMismatch({serverSHA: data.version})` then `reloadToLatest()` | **Fleet-wide forced reload.** `version-check.ts:149-160` compares SHAs only; `shouldReloadForVerdict:183-199` returns `true` for any SHA ≠ client's, because the handler passes no `serverTimestamp` so the rollback guard at `:187-197` cannot engage. Bounded only by the localStorage 3-strike reload-guard. |
| Forge `poke-event` on `${tenant}-venue-${venueID}` | `send-poke.ts:157-161` is the only legitimate publisher | Every connected client of that tenant runs a Replicache pull. Coalesced 2-deep (`listenActions.ts:261-286`) but attacker-paced: a request-amplification lever against the tenant's own API. |
| `GET /apps/app-id/channels` (Pusher read API) | `SOKETI_DEFAULT_APP_MAX_READ_REQ_PER_SEC=100` shows it is enabled | Enumerates live channel names = **tenant slugs + venue IDs + who is currently online**. This is disclosure the "empty payload" argument does not cover. |

### Fix — SPLIT, and the first half is OPERATOR-ONLY

🚨 **ROTATION IS CREDENTIAL-ROTATION CLASS. Do not drive it.** Changing the secret in code first
would *break all pokes for ~6/8 tenants* (the exact failure `send-poke.ts:103` and
`bootstrap-region.pure.ts:2322` both warn about). Order is mandatory:

1. **OPERATOR, first** — mint a per-region secret; set it on the Soketi side
   (`SOKETI_DEFAULT_APP_SECRET` / `SOKETI_DEFAULT_APP_KEY` / `SOKETI_DEFAULT_APP_ID` as Fly env or
   the EC2 Oregon `soketi-config.json`), *then* set `SOKETI_APP_{ID,KEY,SECRET}_<STEM>` in SSM +
   the region Fly apps. Both sides must flip together per region; a mismatch is a silent total sync
   outage with nothing in any log.
2. **Agent-drivable code fix, after rotation** — make the literal unreachable in production, in the
   shape the file already uses for hostnames:

   ```ts
   // lib/poke/send-poke.ts — new helper beside requireHostInProd (:106-114)
   const requireCredInProd = (resolved: string | undefined, label: string): string => {
     if (resolved) return resolved
     if (process.env.NODE_ENV === 'production') {
       throw new Error(`[poke] ${label} Soketi credential unset in production - refusing default`)
     }
     return label === 'appId' ? 'app-id' : label === 'key' ? 'app-key' : 'app-secret'
   }
   ```
   then replace each `process.env.X || 'app-secret'` at `:173-205` and `:227-253` with
   `requireCredInProd(process.env.X, 'secret')`. Dev/test behaviour unchanged (local Soketi keeps
   the stock app — `scripts/qa/ios-soketi-local.sh:39`, `scripts/qa/lib/sync-assert.mjs:33`).
3. **Same commit** — invert `decideForbiddenAppSecrets` (`bootstrap-region.pure.ts:2312-2329`) from
   *"these must be ABSENT"* to *"these must be PRESENT"*, and update
   `tests/bootstrap-region.test.ts:1373`. Leaving it as-is means the next region stood up
   re-introduces the default credential and the bootstrapper blesses it.
4. Also rotate `scripts/notify-deployment.sh:73-91`, which signs the `deployments` publish with the
   same `${SOKETI_APP_SECRET_*:-app-secret}` defaults from CI.

**Non-goal:** do not touch `.env.example` values as "the fix" — they are documentation of the stock
app and are correct for local dev.

---

## LEAD 9 (b) — CHANNEL SCOPE: are the poke channels public, and what rides them?

**Public: confirmed. Payload: no tenant rows — confirmed.**

- Channel name: `lib/poke-channel.ts:52-54` → `` `${tenant}-venue-${venueID}` `` — no `private-`,
  no `presence-` prefix.
- No auth endpoint anywhere: the client Pusher is constructed with `{cluster, wsHost, wsPort,
  forceTLS, enabledTransports}` and **no `authEndpoint` / `channelAuthorization` / `authorizer`** —
  `listenActions.ts:606-615` (primary) and `:184-190` (fallback).
- The repo already knows: `listenActions.ts:532-535` — *"NOTE: the channel is PUBLIC (no `private-`
  prefix / channelAuthorization); the namespace prevents venue-ID COLLISION, not adversarial
  cross-tenant subscription (held as C-009 — hypothetical timing-oracle harm, no payload data)"*.
  Independently restated in `lib/provisioning/provision-run-journal.ts:16-26`, which **rejected** a
  Soketi broadcast for the provisioning stream on exactly these grounds and notes a repo-wide sweep
  for `/pusher/auth|authEndpoint|authorizer|private-|presence-` returns **zero hits in `src/` and
  `lib/`**.

**What is actually published** — `send-poke.ts:100-105, 131-134`:
```ts
interface PokePayload { serverTimestamp: number; pushRequestId?: string }
```
That is it. No rows, no ids, no names. A subscriber learns *that* something changed in
`tenant/venue` and *when* — a timing/activity oracle (busy-night traffic analysis, cross-tenant
activity correlation), not data disclosure. The `deployments` channel carries `{version, timestamp}`
(`listenActions.ts:295`) — a git SHA, already public in the bundle as `NEXT_PUBLIC_GIT_SHA`.

**Verdict on 9(b): confirmed-as-described, and the existing C-009 triage (low, hold) is correct.**
The severity that matters is 9(a)'s PUBLISH capability, not 9(b)'s SUBSCRIBE capability. Note the
asymmetry the fly.toml comment misses: private channels would not fix 9(a), and rotating the secret
does not fix 9(b) — they are genuinely two items.

Minimal optional hardening for 9(b), **only after** 9(a) is rotated (it requires a channel-auth
endpoint + the secret on the server side, i.e. a new credential surface —
`provision-run-journal.ts:20-26` argues against it and that argument still holds): **do not do it
now.** The cheaper and strictly-positive half is to stop publishing the provisioning-style data on
any public channel, which the repo already does.

---

## LEAD 16 — `saveSubscription` SSRF

### Store time: is the endpoint validated at all?

**No. Not one check.** `src/app/actions/notifications/notificationActions.ts:218-280`:

- `:222-225` session gate (`getServerActionSession()`, `session.user` must exist) — **not** admin.
- `:230-249` uniqueness/ownership check on the endpoint.
- `:251-262` `INSERT` of `endpoint`, `auth`, `p256dh` **verbatim from the caller**.

No URL parse, no scheme check, no host check, no key-format check. The parameter type is
`{endpoint: string; keys: {auth: string; p256dh: string}}` and every byte is caller-controlled.

**It is network-reachable.** `'use server'` at `:1` makes every export a registered POST endpoint —
stated by the repo itself at `pushTransport.ts:3-9`. The UI caller
(`NotificationsContent.tsx:255, :316`) is irrelevant to reachability.

### The damning comparison — the repo already has the right predicate, on the sibling path

`src/app/api/notifications/subscribe/route.ts` writes **the same table** and validates properly:

```ts
:13-20  const ALLOWED_PUSH_DOMAINS = ['fcm.googleapis.com', 'updates.push.services.mozilla.com',
          'updates-autopush.stage.mozaws.net', 'web.push.apple.com', 'notify.windows.com',
          'wns2-par02p.notify.windows.com']
:22-30  isValidPushEndpoint() — https: only, then hostname === domain || endsWith('.'+domain)
:32-40  isValidAuthKey / isValidP256dhKey — base64url + length bounds
:136-151 reject 400 + logError('push-endpoint-invalid')
```
plus a same-origin CSRF gate (`:63-82`) and a Content-Type pin (`:104-126`).

Two writers into `push_subscription`, one strict, one with nothing. That asymmetry **is** the bug.
(The route's own comment at `:100-102` even notes the action path exists and bypasses it:
*"NotificationsContent.tsx calls the browser's `pushManager.subscribe()` and persists through a
`'use server'` action instead."*)

### Send time: the deny-list, and the three named bypasses

`src/app/actions/notifications/pushTransport.ts:64-80`:

```ts
64  function isPublicHttpsPushEndpoint(endpoint: string): boolean {
65-70   let url; try { url = new URL(endpoint) } catch { return false }
71      if (url.protocol !== 'https:') return false
72      const host = url.hostname.toLowerCase()
76      if (/^\d{1,3}(\.\d{1,3}){3}$/.test(host) || host.includes(':')) return false
77      if (host === 'localhost' || host.endsWith('.localhost') || host.endsWith('.internal')) return false
78      if (!host.includes('.')) return false
79      return true
80  }
```
Enforced at `:141` inside the fan-out map. It is a **deny-list of spellings**, not an allow-list.

| Bypass | Verdict | Deciding line |
|---|---|---|
| **Trailing-dot FQDN** `https://soketi-lax.internal./x` | **BYPASSED** | `:77` — `'soketi-lax.internal.'.endsWith('.internal')` is **false** (the string ends in `.`). WHATWG host parsing keeps the root-label dot in `hostname` (the IPv4 shorthand path at `:76` is unaffected: it only normalises numeric hosts). `localhost.` likewise defeats both `host === 'localhost'` and `.localhost`. DNS treats `x.` as the same absolute name. **This defeats exactly the private-hostname class this deployment uses** — Fly 6PN `<app>.internal`. |
| **Public DNS name resolving to a private address** | **BYPASSED** | `:64-80` as a whole — there is **no resolution step anywhere**. `evil.attacker.com` with an `A` record of `169.254.169.254` / `10.0.0.5` passes every line. Also a clean DNS-rebinding TOCTOU: validation is lexical at `:141`, connection happens at `:146`. |
| **Non-443 port** | **BYPASSED** | `:64-80` — `url.port` is never read. `https://internal-alb.attacker-controlled.com:8200/` passes. |

Two more that fall out of the same shape: `url.pathname`/`search` are unconstrained (the POST lands
on any path), and IPv4-literal coverage rests on the WHATWG canonicaliser rather than the regex
(`127.1`, `0x7f000001` are normalised to `127.0.0.1` before `:76` sees them — that part happens to
hold).

### What an attacker actually reaches — stated honestly

- **Precondition: an authenticated staff/operator account.** The guest session is a *separate*
  cookie (`lib/auth/guest-session.ts:96-104`, `getGuestSession()`) and does **not** populate
  `session.user`, so `saveSubscription`'s gate at `:222` is not satisfied by a guest claim. This is
  authenticated-insider SSRF, not anonymous.
- **Trigger is attacker-controlled without admin**: `lib/auth/credential-change-notifier.ts:87-91`
  selects the caller's **own** subscriptions and fans out on every passkey add (`:121-125`). So the
  attacker stores forged rows, then adds a passkey, and the server dials them on demand. The other
  two triggers are `sendTestNotification` (admin-only, `notificationActions.ts:91-93`) and the
  approval drainer (`notificationDispatch.ts:341`).
- **Method/shape:** a POST from the server's network position, TLS-only, with an encrypted body and
  VAPID headers. Blind — the response body never returns to the attacker.
- **The `https:` pin at `:71` is the one real mitigation** and it is load-bearing: AWS IMDS
  (169.254.169.254) and GCP `metadata.google.internal` are **HTTP-only**, so the classic
  cloud-metadata pivot does **not** land. What remains in reach is any internal service that speaks
  **TLS**: internal ALBs, a Kubernetes API, Vault-class services on non-standard ports, regional
  libsql/Turso endpoints — plus arbitrary outbound POST to attacker infrastructure (exfil channel /
  beaconing from inside the VPC).
- **Side channels that make the blindness partial:** an admin attacker reads `sent` vs `failed`
  counts straight out of `sendTestNotification`'s return (`:194-200`) — a per-endpoint boolean
  oracle, i.e. internal TLS **port scanning**. And a target answering 410/404 causes the server to
  `DELETE` the row (`pushTransport.ts:167-169`), a second observable bit.

### Fix — agent-drivable, not credential class

**Validate at STORE time with the predicate that already ships**, and harden the send-time guard as
defence in depth. Two edits, no new behaviour class.

1. Lift the route's validators into a shared, non-`'use server'` module (e.g.
   `lib/push/endpoint-validation.ts`) holding `ALLOWED_PUSH_DOMAINS`, `isValidPushEndpoint`,
   `isValidAuthKey`, `isValidP256dhKey` moved verbatim from
   `src/app/api/notifications/subscribe/route.ts:13-40`; import it in the route (no behaviour
   change) and in `notificationActions.ts`.

2. In `notificationActions.ts:218`, immediately after the session gate at `:225` and before the
   lookup at `:230`:

   ```ts
   if (!isValidPushEndpoint(subscription.endpoint)
       || !isValidAuthKey(subscription.keys.auth)
       || !isValidP256dhKey(subscription.keys.p256dh)) {
     logError({
       requestId: generateRequestId(), severity: 'warning', category: 'auth',
       errorType: 'push-endpoint-invalid', message: 'invalid push service endpoint rejected',
       tenant: extractTenant(process.env.NEXT_PUBLIC_TENANT || null), group: 'unknown',
       operation: 'saveSubscription', userID,
       metadata: { endpointPrefix: subscription.endpoint.substring(0, 50) },
     })
     return { errorMessage: 'Invalid push service endpoint' }
   }
   ```
   (`userID` is already destructured at `:227`; move that line above the check.)

   **Compatibility residual, stated rather than hidden:** the allow-list is 6 hosts. A browser whose
   push service is not on it (some Edge/WNS regional hosts, Samsung Internet, Brave) would now fail
   enrollment where it previously succeeded — but it *already* fails the `pushsubscriptionchange`
   re-subscribe path at `route.ts:136`, so the divergence is producing half-broken subscriptions
   today, not working ones. The `logError` above makes any such breakage visible on day one, which
   is why it is not optional. If the operator wants zero enrollment risk, mirror the route's
   knob convention — `PUSH_ENDPOINT_CHECK=report|enforce` defaulting to `enforce`, `report` logging
   without rejecting — same shape as `PUSH_ORIGIN_CHECK` (`route.ts:63`).

3. Defence in depth at `pushTransport.ts:72` — normalise the trailing dot before the host tests, so
   the existing deny-list stops being defeated by a spelling:
   ```ts
   const host = url.hostname.toLowerCase().replace(/\.$/, '')
   ```
   and add a port pin after `:71`: `if (url.port && url.port !== '443') return false`.
   This does **not** close the public-DNS-to-private-address arm — only the allow-list in (2) does.
   Leave the deny-list in place; per its comment at `:58-63` it is deliberately defence in depth.

4. There are **zero tests** for `isPublicHttpsPushEndpoint` today — the whole suite
   (`__tests__/notificationActions.test.ts:66-155`) tests TTL/urgency/prune/tally and never a
   rejected host. Add cases for each of the three bypasses while fixing.

---

## LEAD 20 — fan-out: row cap, concurrency bound, limiter semantics

### Per-user subscription-row cap — NONE

- `drizzle/schema.ts:309-318` — `endpoint` is `.unique()`, `userID` carries only
  `index('idx_push_subscription_user_id')`. No unique constraint, no count constraint.
- `notificationActions.ts:251-262` inserts unconditionally once the endpoint is new.
- `route.ts:203-214` likewise.

So one authenticated user may hold an unbounded number of rows, each with an arbitrary endpoint
(LEAD 16). The two leads compose: N forged rows × every send = N outbound requests.

### Concurrency bound — NONE, at two levels

- **Inner:** `pushTransport.ts:138-139` — `Promise.allSettled(subscriptions.map(async (sub) => …))`.
  Every subscription is dispatched simultaneously; Node's default agent has
  `maxSockets: Infinity`. (Contrast `send-poke.ts:33-44`, where the poke transport *does* cap at
  `maxSockets: 10` — the repo knows the pattern and did not apply it here.)
- **Outer:** `notificationDispatch.ts:409` — `Promise.allSettled(claimed.map(async (row) => …))`
  over up to `DRAIN_BATCH_LIMIT = 50` rows (`:170`), each running its own full inner fan-out.
  Worst case per sweep = 50 × |subscriptions of that row's recipients| concurrent TLS POSTs from a
  single Lambda/Fly instance. The only timeout is per-send, 10 s (`pushTransport.ts:155`).

### The limiter — CALLS, not messages, and only on one of three paths

- **Metering unit:** `notificationActions.ts:103` — `await checkWebPushRateLimitDurable(userID)` is
  invoked **once per `sendTestNotification` call**, before the fan-out at `:149`. The limiter's
  UPSERT increments `count` by exactly 1 (`durable-limiter.ts:136`) regardless of how many messages
  the call then emits. Budget `30/min` (`:24`, `PUSH_RATE_LIMIT_PER_MINUTE`). With N stored rows the
  real ceiling is **30 × N messages/min**, and N is uncapped (above). **It meters CALLS.**
- **Coverage:** the other two senders have **no limiter at all** —
  `notificationDispatch.ts:341` (the approval drainer, fired every 30 s per
  `src/instrumentation.ts`) and `lib/auth/credential-change-notifier.ts:121`. Also
  `saveSubscription` itself is unrated, so row creation is unbounded too.
- **Store budget and failure direction:** `durable-limiter.ts:46` `DEFAULT_TIMEOUT_MS = 50`,
  applied at `:118` and `:127-144` via `withTimeout`. On timeout or any store error the `catch` at
  `:162-167` returns **`{success: true, … failedOpen: true}` — it FAILS OPEN (allow)**. Documented
  as deliberate at `:11-13` and at `notificationActions.ts:33-35` (*"a dropped notification ≠ data
  loss"*).

  The sharp form: the counter lives in the **tenant's own Turso DB**, the same store the fan-out and
  the whole request path hammer. Under precisely the load where the limiter matters, that DB's p99
  crosses 50 ms and the limiter goes dark — an anti-correlated guard. `failedOpen` is surfaced but
  the fail-open **log is throttled to ≤1 per namespace per minute** (`:55-61`), and the flag is
  discarded by the only caller (`notificationActions.ts:103-104` reads `rl.success` only), so
  nothing meters *how dark*.

  This fail-open is a defensible *product* choice for a cost/UX limiter. It is not a defensible
  *security* boundary, which is what LEAD 16 turns it into: with forged endpoints, "allow on store
  timeout" means the SSRF amplifier is uncapped exactly when the system is loaded.

### Fix — three edits, all agent-drivable, ordered by value

1. **Per-user row cap (the one that bounds the blast radius).** In
   `notificationActions.ts` before the insert at `:251`, and in `route.ts` before `:203`:
   ```ts
   const MAX_SUBSCRIPTIONS_PER_USER = 20   // ~devices per operator; generous
   const owned = await db.select({ n: count() }).from(pushSubscription)
     .where(eq(pushSubscription.userID, userID)).get()
   if ((owned?.n ?? 0) >= MAX_SUBSCRIPTIONS_PER_USER) {
     return { errorMessage: 'Too many registered devices' }   // route: 409
   }
   ```
   Prefer this over evicting the oldest row: eviction is a silent way for an attacker to unsubscribe
   a real device.

2. **Concurrency bound in the transport.** `pushTransport.ts:138` — replace the flat
   `Promise.allSettled(subscriptions.map(…))` with a fixed-width worker pool (8–16) over the same
   per-sub closure, preserving the exact return shape (`sent`/`failed`/`deleted`/`results`) so the
   `:196-209` tally and every caller are untouched. Same discipline `send-poke.ts:33-44` already
   applies to the poke agent.

3. **Meter messages, not calls, and cover the uncovered paths.** Smallest correct change: move the
   limiter into `sendToSubscriptions` keyed per recipient `userID` and charge it
   `subscriptions.length`, i.e. give `createDurableLimiter` a `cost` parameter that the UPSERT adds
   instead of `+1` (`durable-limiter.ts:136`). Then every sender inherits it, including the drainer
   and the credential notifier.
   - **Do NOT flip the fail-open to fail-closed.** `durable-limiter.ts:11-13` is used by hot auth and
     sync paths; a fail-closed flip there would 429 legitimate traffic during any DB blip. The right
     answer is to remove the *need* for it as a security control (edits 1 + 2 + LEAD 16's allow-list)
     and to make the darkness measurable: propagate `failedOpen` into
     `notificationActions.ts:103` logging and emit a CloudWatch counter per occurrence rather than
     the ≤1/min throttled text log.

---

## DO-NOT-FIX check — `.claude/commands/exhaust-improvements.md`

Read at `§ DO-NOT-FIX landmines` (`:181-190`). **No fix above collides with any of the 8 entries.**
Item by item: sequential Replicache mutations (n/a), `<Suspense>` (n/a), mission-control `rgba`
(n/a), F6 warm-at-tap (n/a), FloorPlanViewer barrel (n/a), share-graph venue-unscoped reads (n/a —
different subsystem), `getServerActionSession` (my LEAD 16 fix *relies* on it and does not rename
it), park-ui prop spreading (n/a).

**The `pushManager.subscribe` note is at `:209-211`, not in the landmine list** — it is calibration
note 4 from the first run: *"The lone react-doctor error was a literal-token false match
(`pushManager.subscribe`)"*. That warns against fixing a **lexical token hit** on the string
`subscribe`. It does not reach these findings: LEAD 16 is a read of `saveSubscription`'s body
end-to-end against a sibling route that validates the same field, and `pushManager.subscribe` is a
*browser* API call in `NotificationsContent.tsx` that none of my edits touch. Distinguishing them is
exactly the discipline that note asks for.

**Two entries in that file that DO bind on disposition:**
- `:212` — *"Auth/sync findings → queue + escalate, never silently land mid-sweep (CLAUDE.md
  escalation rule wins over 'just keep working'). Surfacing + planning + flagging IS the correct
  disposition."* All three leads are auth/sync-class. Queue and escalate; do not land mid-sweep.
- `:204-207` — net-new findings often converge on an existing campaign; **integrate** into the
  existing ledger entry rather than orphaning a duplicate plan. LEAD 9(b) is already held as
  **C-009** (`listenActions.ts:534`, `docs/sync/README.md`) — 9(a) belongs *beside* C-009 as a
  distinct item, not folded into it, because C-009 is about SUBSCRIBE and 9(a) is about PUBLISH.

---

## Adversarial pass — what I went back and checked

1. **"The `app-secret` fallback is dead code; prod sets the env vars."** Checked and **refuted** by
   executable code: `bootstrap-region.pure.ts:2312-2329` *fails the region bootstrap if the real
   secret is set*, with a test pinning the message. The repo enforces the default.
2. **"The channels are empty, so who cares about the secret."** Checked the WRITE direction the
   fly.toml note never considers: `handleDeploymentEvent` → `reloadToLatest` with no rollback guard
   on the SHA path (`version-check.ts:183-199`, because the handler passes no `serverTimestamp`).
   Fleet-wide forced reload from an unauthenticated publish.
3. **"LEAD 16 is anonymous-reachable."** Checked and **bounded**: the guest session is a separate
   cookie (`lib/auth/guest-session.ts:96-104`) and does not satisfy `session.user`. Authenticated
   insider only — a real reduction in severity, stated rather than dropped.
4. **"The SSRF never fires without an admin."** Checked and **refuted**:
   `credential-change-notifier.ts:87-125` fans out to the caller's own rows on a passkey add, giving
   a non-admin attacker an on-demand trigger.
5. **"https-only makes the SSRF theoretical."** Checked: it genuinely kills the AWS/GCP metadata
   pivot (both HTTP-only). Said so. What survives is internal-TLS reach + outbound exfil + an
   admin-readable sent/failed port-scan oracle (`notificationActions.ts:194-200`).
6. **"The guard's IPv4 regex is trivially bypassable via `127.1` / hex."** Checked and **refuted** —
   WHATWG canonicalisation normalises those before `:76` sees them. The regex is not the weak part;
   the absence of DNS resolution and the trailing dot are.
7. **Test coverage of the guard.** Checked `__tests__/notificationActions.test.ts:66-155` — zero
   cases exercise `isPublicHttpsPushEndpoint`. The guard has never been red.

**Named uncertainty (one, and the verdict does not turn on it):** I did not execute
`new URL('https://a.internal.').hostname` in this read-only session. It is a spec-level claim
(WHATWG host parsing retains the root-label dot; the IPv4 shorthand normalisation at `:76` applies
only to numeric hosts) and a well-known SSRF bypass class. One-line falsifier for the fixer:
`node -e "console.log(new URL('https://a.internal.').hostname)"` — expect `a.internal.`. Even if it
returned `a.internal`, bypasses 2 (public DNS → private address) and 3 (non-443 port) stand on their
own, and the recommended fix is an allow-list that moots all three.

**Second uncertainty:** whether `web-push`'s HTTPS client follows redirects (a 30x from an
attacker's endpoint could widen reach). Not resolvable read-only without opening `node_modules`;
irrelevant under the allow-list fix, which is another reason to prefer it over patching the
deny-list.
