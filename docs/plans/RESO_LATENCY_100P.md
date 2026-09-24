---
status: in-progress
---

# RESO_LATENCY_100P — every avoidable database round trip and latency cost in reso, removed

**Scope (frozen, 2026-09-23):** operator directive, verbatim: *"Yes, please for this situation, and
all queries, with React Server Components + NextJS App Router, Replicache + replicache-react,
general database fundamentals: best practices and patterns, please 100th percentile optimize for
latency and database roundtrips."* So: (1) fold the admin role read into the per-request
session-revocation read (`lib/auth/session.ts` + `src/app/actions/auth/accessActions.ts`), and
(2) every query path in reso optimised for latency and round trips — RSC/App Router data loading,
Replicache pull/push and the replicache-react client, server actions, API routes and middleware,
and the database layer itself (client, placement, indexes). Each change is measured before/after
with a round-trip count, pinned by a test that fails on the parent, and landed on reso trunk.
Not in scope: `/deploy` (the operator's; landing in reso is free, deploying spends).

**Why this plan lives in claude-infrastructure:** same reason as `RESO_SECURITY_100P.md` — reso's
`docs/` is under the consolidation programme's add-requires-delete gate, and `.claude-plans/` there
is gitignored.

## Phase 0 — Agent Team Orchestration

**Execution locus per wave:**
- **R (research) — L, lead-fired read-only subagents.** Ten axes, one file each, under
  `docs/research/reso-latency-2026-09-23/`. Why L: read-only, returns one-line pointers, synthesis
  must happen on the lead.
- **Implementation waves — S, one dispatched session per wave** (the default), each on its own reso
  worktree off `origin/main`, landing via reso `/ship`. Waves are cut from the synthesis so that no
  two sessions own the same file.

**Lead context budget + succession point:** lead holds ≥50% for synthesis and wave firing; recycle
after the waves are fired and custody is recorded.

## Research wave (R) — axes

| Axis | File | Owns |
|---|---|---|
| a1 | `a1-auth-session.md` | per-request session/tenant/auth reads, the admin-role fold |
| a2 | `a2-rsc-routes.md` | page/layout waterfalls, cache() dedupe, streaming |
| a3 | `a3-seeds-prefetch.md` | useSubscribe server seeds, prefetch, store warm |
| a4 | `a4-replicache-pull.md` | pull route, CVR, watermark gate |
| a5 | `a5-replicache-push.md` | push route, operationBuilder, idempotency, pokes |
| a6 | `a6-server-actions.md` | non-replicache server actions |
| a7 | `a7-api-middleware-fanout.md` | middleware, API routes, messaging, notification fan-out, limiter |
| a8 | `a8-db-fundamentals.md` | libsql client, region placement, embedded replicas, indexes |
| a9 | `a9-client-replicache.md` | useSubscribe patterns, mutators, pull/push cadence |
| a10 | `a10-measurement.md` | round-trip counter, production signals, budget ratchet |

## Waves — cut from the research by FILE OWNERSHIP (one owner per file)

Research returned ~180 findings across ten files. They are cut into ten implementation waves so that no
two concurrent sessions share a file. Many findings are one defect seen from several paths; the most
common one is the per-request revocation SELECT, which is repeated by every `getDB()` inside a request (A1-1/A1-2,
A6-03, A7-05, A8-2, F2, R22, pull F3). It is fixed once, in W1a.

**Batch 1 — fired now (no dependencies between them):**

| Wave | Owns (summary) | Findings |
|---|---|---|
| **W1a** session core + admin fold | `lib/auth/session.ts`, `cookieActions.ts`, `accessActions.ts`, `authQueries.ts`, team page, logout/logs routes | A1-1/2/3/10s/11/12 · A6-03/05/17 · A7-05/06/11 · A8-2 · a2 F2 · R22 · pull F3. **Publishes** the shared revocation predicate + folded row type batch 2 builds on |
| **W0** round-trip ledger | recorder, roundTripStream, db-logger, db-context, grafana, NEW per-path budget files | M1, M2, M7/M8 (helpers), M10, M11, M12 |
| **W6** Replicache client | `create-replicache-context.tsx`, `mutators.ts`, subscription call sites | C1c, C2, C3, C5–C12 · pull F6, F11, F9c |
| **W4b** route seeds | bottle-service seed, guests, list detail, floor-plan, recap, lists, guest QR page | a2 F1/3/4p/5/9/10/12/16 · R6/7/8/9/12/16/18/19/21 · A6-08/09 |
| **W7** DB transport | `drizzle/db.ts`, `turso-keepalive.ts`, `db-instrumentation.ts`, fly tomls, sweeper, latency-ping | A8-4/5/6/7/9/10/11 · pull F15 · M4 · A7-13/14 |

**Batch 2 — fired after W1a lands (they consume its predicate):**

| Wave | Owns (summary) | Findings |
|---|---|---|
| **W1b** pre-session + login | `tenantContext.ts`, `sessionWrite.ts`, `lib/auth/login.ts`, `durable-limiter.ts`, register flow | A1-7 (**security: the S-4 login limiters are probably dark in prod** — a 50 ms timeout around a Platform API call fails open), A1-8, A6-04, A6-16, A7-04/09/10, A8-3/8, a2 F4 (tenant half), R20 |
| **W2** pull + watermark | pull route, `pullActions.ts`, `authContext.ts`, `recencyWindow.ts`, sync-watermark route, `sync-cursor.ts`, `watermark-poll.ts`, `tableServiceActions.ts` | a4 F1/2/4/5/7/8/10/12/13/14 · A1-4, A1-9 · A7-03 · M5, M9 |
| **W3** push | push route, `pushActionsBatch.ts`, `sharedActions.ts`, `batchPrefetch.ts`, `notificationDispatch.ts`, `pushTransport.ts`, `venue-id-cache.ts`, `todoActions.ts` | a5 F1–F15 · A1-5 · A7-02c/07/08 · A8-1/13 · M3, M6 · R17 |
| **W4a** shell + home + nav | `LandingPageOrLoggedInApp.tsx`, `homeStateActions.ts`, `navWarmActions.ts`, `MobileNavBar.tsx`, `venue-resolution.ts`, warm route | a2 F6/7/8/11/13/14/15 · R1–R5, R10, R11, R13–R15, R23 · A1-6 · A6-01/02/06/07 · A7-01 · C4 · M7 wiring |
| **W5** admin + other actions | `databaseActions.ts`, `tenantConfigActions.ts`, `venueRoleActions.ts`, `notificationActions.ts`, subscribe routes, MissionControl, useLogout | A1-13/14/15 · A6-10–16, 18–21 · A7-12 |

**Rejected at plan level:** A8-12 (indexes) — small tables with sub-millisecond scans, and adding them needs a schema
migration on a live fleet for no measurable gain.

**Firing:** `handoff-fire.sh --repo ~/Development/reso-management-app --worktree <branch> --notify-back 495
--prompt-file /tmp/fire-lat-<wave>.txt --goal …`, one session per wave; briefs = `/tmp/fire-lat-<wave>.head` +
`/tmp/fire-lat-common.md`. Box load was ~178 at fire time, so two batches of five.

## Status

| Wave | State | Evidence |
|---|---|---|
| R | ✅ DONE — 10 files, ~180 findings | `docs/research/reso-latency-2026-09-23/` |
| Batch 1 (W1a, W0, W6, W4b, W7) | RUNNING — fired 2026-09-23 23:40 CDT, all five goals armed+verified | panes W1a 670 · W0 671 · W6 672 · W7 673 · W4b 674 |
| Hand-over W6 → W2 | W6's C1c/F9c (client session slide) and F6 (poller API) need W2's files; W6 lands the rest and specs them in its close, W2 does server halves then the client wiring after W6 lands | W6 ping 23:43 |
| **W1a** | ✅ **LANDED** reso `ffa66dd4e` (13 paths content-verified, 436/436 unit green). One user-row read per request (WeakMap memo on the cookie store); admin gate 3→1, platform-or-admin+getDB 5→1, Team page prefix 10→1, logout 1→0. Published `lib/auth/session-revocation.ts` (`isSessionRevoked`, `SessionUserRow`) + `getSessionUserState`/`getSessionUserRow`. REJECTED: A7-05 TTL memo (it would delay revocation), A7-06 logs unseal-only (trusts a revoked cookie). Speculative overlap (reads ∥ revocation) ruled compliant with Critical Rule 5 by the lead and granted to W4a | pane 670 |
| **W6** | ✅ **LANDED** reso `327f81c5b` (21 paths, 5202/5202). Badge scans 4→2; home todos venue-scoped; minute tick no longer rescans; floor-plan todo scans 2→1; wake paths pull without awaiting probes (C2 C5 C6 F11); venue switch 0 server actions. REJECTED C9 (new client index forces a fleet reload), C12 (would drop cross-venue labels). Handed C1c/F9c/F6 to W2 | pane 672 |
| **W1b** | ✅ **LANDED** reso `f961588b4` (5327 green). 🚨 **A1-7 CONFIRMED: the pre-session login limiters were failing OPEN in production** — prod CloudWatch 14 d: tenant resolution p50 178 ms, min 71 ms, above the 50 ms limiter budget, so register/passkey-login/options/username/invite/guest-claim limits never applied (47 throttled fail-open lines). Fixed: group from the manifest, resolution outside the budget; test 11/11 fail-open → 0/11. Platform API calls on login 3→0, /login mount 2→0; per-login fresh libsql client → pooled. **Residual:** the limiter's own store write can still exceed 50 ms on a cold socket, so a cold container's first check may fail open. Live at the next /deploy | pane 676 |
| Batch 2 (W1b, W2, W3, W4a, W5) | RUNNING — fired 2026-09-24 00:10–00:30 CDT, all goals armed | W1b 676 · W3 677 · W2 678 · W5 681 · W4a (see log) |
| Ownership rulings | warm route + R20 → W4a; A6-16 register fold → W5 (+ formActions.ts, passkeyCeremonyActions.ts); W5 granted logout route (A6-18) and the three history action files (A6-20) | pings 00:19–00:24 |
