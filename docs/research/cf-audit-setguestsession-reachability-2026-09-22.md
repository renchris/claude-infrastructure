# setGuestSession is a network-callable, unauthenticated Server Action — measured 2026-09-22

Target: reso origin/main 4a6457901 (wave-1 landed tree), built in
/Users/chrisren/Development/.worktrees/wt-sec-w1d-livehrole with `CI=true pnpm build` (exit 0).

## Instrument, with its positive control

`.next/server/server-reference-manifest.json` carries 92 `node` action ids and NO export names.
Names come from the server chunks, where Turbopack emits
`(0,t.registerServerReference)(<local>,"<id>",null)` plus a separate export map. A first attempt
matched `registerServerReference\s*\(` and found 0 of 92 — the call is `(0,t.registerServerReference)(`,
so the pattern missed the closing paren. THE POSITIVE CONTROL CAUGHT THAT: `updateTenantConfig`
is known-live (confirmed finding #5) and came back ABSENT, which means every negative in that
run was an instrument artifact.

Corrected pattern, 129 exported names mapped to action ids:

| export | action id | in manifest |
|---|---|---|
| `updateTenantConfig` (POSITIVE CONTROL) | `40ce5f040ad17e6a0f321ddceec13d9b200d869713` | yes |
| `setGuestSession` | `60cc25f636e3a77235479f1627aa168986a6796417` | yes |
| `getNamedDB` | `603764b5a4c4081d987342b09e1562154e49447651` | yes |
| `getDBAndGroup` | `009515a73a768d7bea49bee09ef7367b862fb2ffa1` | yes |
| `getDBAndGroupForSessionTenant` | `4024a88bf2ce1d594174137f70706cbf97a08d0e64` | yes |
| `getPlatformDB` | `00472381642c8a46a2812191211a03494a37199d4b` | yes |
| `deleteDatabase` | `40e760d00290a845ea481c2bd4077e7e96a62e45f1` | yes |
| `migrateDB` | — | NOT REGISTERED (tree-shaken, as predicted) |
| `initializeDatabase` | — | NOT REGISTERED |
| `initializeDB` | registered | ABSENT from manifest — unresolved |

## The chain

1. `lib/auth/guest-session.ts` line 1 is `'use server'`; `setGuestSession(reservationID: string,
   guestClaimID: number)` is an exported async function whose whole body is: read the guest session,
   assign both caller-supplied values, save. **No authentication, no authorization, no claim-token
   check.** Its docblock says "Called ONLY after a claim token has been verified" — a statement about
   its internal callers, which does not bind a network caller.
2. It is registered and present in the manifest, so it is a callable POST endpoint.
3. `src/app/(guest)/t/[claimToken]/_actions/submitOrder.ts:82` states the invariant in its own words:
   *"The claim cookie is the ONLY authority for which reservation this is — the caller-supplied id
   must agree with it, never override it."* Line 84 enforces
   `guest.reservationID !== input.reservationID`.
4. So the sole authority for the guest order path is a cookie an unauthenticated caller can write
   directly, which makes the claim-token verification bypassable rather than merely weak.

## What is NOT proven

No POST was executed against a running server: there is no sandbox on this box, and firing one at
production is out of bounds. The evidence is source + build-output. The remaining step is a single
POST of the registered action id against a running instance.

`deleteDatabase` is callable but PROPERLY GATED (`getServerActionSession` + `isPlatformEmail`), so
lead 2's question is about the serving-guard's scope, not about authentication.
`getPlatformDB` is callable and has NO gate at all; it builds the Turso control-plane client from
`TURSO_PLATFORM_API_AUTH_TOKEN`. Whether the token itself crosses the wire depends on whether the
returned client serialises, which was not tested.
