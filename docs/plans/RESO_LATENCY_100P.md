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
| **W4b** | ✅ **LANDED** reso `c68e6c849`, `629e74f03` (29 paths). Two read paths held a WRITE LOCK and no longer do: table drawer 17 POSTs / 15 levels in a write tx → 1/1; list seed 6-7 in BEGIN IMMEDIATE → 1 batch. Bottle-menu catalog 8→1; guest dossier 5 levels → 2; guest book promoter 4→1; guest QR 3 levels → 1 (bad/expired/other-tenant tokens yield 0 rows, pinned); list items shipped 52 → 8 rows. NOT DONE: F16's list/share/event scoping (would put the role read ahead of the batch) | pane 674 |
| **W2** | ✅ **LANDED** reso `8ee9d2e10` (server), `e0a89a169` (client), 24 paths. Revocation folded into the pull tx's first POST: **no-op pull 5→2 POSTs, change path 12→6**; revoked/absent/stale → 401 (also fixes a 500 on a renamed username). Scan windows 4→1; floor-plan config 24→12 stmts; recency window 5→2 levels; watermark probe 3 POSTs/2 levels → 1 statement. The pull route and probe now slide the session, and the client's per-minute slide request is gone (C1c/F9c); `observePulled` stops the redundant post-poke pull (F6). REJECTED: F4 (read-batch costs +1 RT on every gate miss at a 17-34% hit rate), F12 (CVR-from-fetch diverges from the scan ⇒ perpetual change path), F1b | pane 678 |
| **W8 — cheap poll ON (follow-on, Scope grown)** | FIRED after W7 landed (W7 owns `amplify.yml`/fly env lines). The biggest single lever left: 91.9% of pulls are 60 s interval pulls and 99.1% of those are no-ops; the cheap poll replaces each with a 1-statement probe. W2 landed both prerequisites (probe carries `X-Deploy-SHA`; probe slides the session). W8: verify the client wires the probe's deploy SHA to the stale-bundle reload, set `NEXT_PUBLIC_REPLICACHE_CHEAP_POLL` in the Dockerfile build args and `amplify.yml`, confirm by grepping a built client chunk, delete the now-callerless `lib/throttle-leading.ts`; wire M7 (`logRscLedgerAfterResponse` from the (app) layout, helper landed in `lib/request-ledger.ts`) and verify in a local prod build that `rsc_posts` equals the rsc-shell budget (W0's open question: does React per-render cache survive the libSQL async continuation). Live at the next /deploy | — |
| **W5** | ✅ **LANDED** reso `c4bcec849`..`d019df139` (12 commits, 35 paths, 5710 unit green, build + action audit 0). 🚨 **Two atomicity holes closed:** `deleteCredential`'s delete and version bump were not atomic (an injected bump failure left the credential deleted — now rolled back), and `initializeDB` left 4 half-written rows on failure (now one atomic batch). deleteUser 12→1 POSTs with RESO_SECURITY_100P's cascade semantics intact; deleteCredential 4→1; tenant config 3→1; venue role 3→1; subscribe 4→1; logout 2 requests→1; register submit 3 action POSTs→1; operator sessions seed 3→1; getAllUsers 2→1; sendInvitation 3→2. REJECTED none | pane 681 |
| **W4a** | ✅ **LANDED** reso `1a79ce011`, `da6e720f0`, `ebac46bea`. Tonight rail seed (every authed route) 4→1 levels and home seed 4→1; shell fans out beside the revocation verdict; venue-cache miss 2→1; one auth computation per render (user-row reads 3→1); nav first warm 2 server actions→0; /api/warm 5→3. Speculative overlap adopted in every W4b seed, with a revoked-session test at each site (/guests 2→1, /guests/[id] 3→2, /lists 2→1, recap 2→1, floor-plan/[id] 2→1, table drawer 2→1). REJECTED R23 (pipelining client below drizzle; levels already 1). NOT DONE: M7 wiring (→ W8) | pane 682 |
| **W0** | ✅ **LANDED** reso `f1f9daebb` (5878 green). `requestLedger` counts posts/levels/streams; per-path budget files (pull, push, watermark, rsc-shell, admin-action) plus a coverage gate for unbudgeted DB routes. Measured b2eea41b3 → ebac46bea: no-op pull 5 levels→2; watermark 2→1; shell cold 4 levels / 12 posts → 2/5; getAllUsers 5→2; dismissSetup 8→2; push 7→6 (W3 pending). Grafana: `reso-dfw` added to all 11 db-metrics selectors (Dallas was invisible). `gitSha` on every db-metrics line. UNVERIFIED (→ W8): whether React per-render cache survives the libSQL async continuation in a real RSC render | pane 671 |
| Stalls | W0, W3 and W7 sat on permission prompts (a hook `rm -r` ask on their own scratch path; the `git stash drop` ask rule). Operator unblocked them; the root cause went to its own track, PERMISSION_PROMPT_CONSOLIDATION (pane 690, fired 2026-09-24) | — |
| **W7** | ✅ **LANDED** reso `8110d9af1` (30 paths, 5936 unit green). **TURSO_KEEPALIVE on in all 4 Fly tomls — re-measured Oregon post-idle first statement 264→63 ms p50 (≥900 ms tail 12.5%→0%), LAX 90→57 ms; live at the next /deploy.** Safe read-only resend on a dead socket (writes never resent); round trips counted at the fetch transport (M4); one pool shared across module instances; sweeper idle tenant 3→1 request, outbox claims 4→1; latency-ping rides the app transport. REJECTED: Amplify keepalive (every post-idle Lambda invocation follows a freeze — unmeasurable gain), A8-6 hedged reads (stalls correlate across containers, p=0.0018, and attach to stream open — a hedge buys the hazard) | pane 673 |
| **W3** | ✅ **LANDED** reso `df60a337e`, `28a5b0058` (18 paths). **Whole push request 6→2 levels, 6→3 posts**; revocation folded into the prefetch (a deleted account now gets 401, not 500); the write tx is ONE batch with raising guards; a pure replay opens no write (3 levels→1); fallback 28→7 posts; notification drain 11→4 before send; push timing now starts at the top of the handler (it was logging 1.79e12 ms on an early throw). REJECTED with evidence: F10/F11 payload narrowing (would silently consume legitimate mutations), F13 bulk mutators (a sync-contract change across un-owned files), F14/F15/M6 (0 serial levels, inert, or needs an un-owned logger field). Doc follow-on (push ownership now `ownershipGuardStatements`) → W8 | pane 677 |
| **W8** | ✅ **LANDED** reso `2bba10b1d` (11 paths + 2 deletions, 5609/5609). **The cheap poll is ON in both production builds** (Dockerfile ARG default + amplify.yml; it was OFF everywhere — Amplify env and SSM read-only confirmed). Found and fixed a real gap first: the probe's `X-Deploy-SHA` was never wired (the poller was built without `onDeploySHA`), so turning the poll on would have broken stale-bundle reload — now a stale SHA escalates to one real pull that runs the existing reload guard. Idle slide pinned (10 idle intervals = 11 probes, 0 pulls). M7: the layout emits `rsc_posts`; W0's question answered YES in a local prod build (/lists 7=7, / 6=6, /floor-plan 9=9). Deleted `lib/throttle-leading.ts`. Push ownership docs updated. Live at the next /deploy | pane 691 |
| **W9 — unblock the Oregon deploy (Scope grown)** | ✅ **LANDED** 2026-09-24: amplify.yml runs `CI=true VITEST_TIMEOUT_FACTOR=4 pnpm test:unit:build` = test:unit minus 8 land-pipeline tooling suites (they run at land time via ship-land); local run 505 files / 5844 passed, 0 failed; no app test excluded. **Premise corrected by W9: not flaky — deterministic `shasum: command not found` on Amplify Linux** (fixed in the suites too: 9682616e0, b3708a399); 1494's lead-alert-outbox failure was a test upper-bound bug already fixed and is KEPT in the gate. Evidence that set the scope: land-status: **DEPLOY FROZEN** — Amplify jobs 1496 (f1f9daebb) and 1494 FAILED in `pnpm test:unit` on the land-pipeline tooling suites (land-turn, ship-land, pre-push-verdict: ~5 s CodeBuild timeouts), while 1495 passed the same suites ⇒ flaky in CodeBuild, not our app code. Every fix in this programme reaches production only through that build | pane 692 |
| **PROGRAMME** | ✅ **COMPLETE on reso trunk.** Every wave landed and content-verified; ~180 findings each FIXED with a red-on-parent round-trip test or REJECTED with evidence (recorded per wave above). **Nothing is live until the operator's next `/deploy`** (Fly + Amplify; landing is free, deploying spends) — that deploy also carries TURSO_KEEPALIVE on Fly, the cheap poll, and the W1b login-limiter security fix. Headline, measured on W0's ledger: no-op pull 5→2 posts; push 6→2 levels; tonight/home seeds 4→1 levels; shell cold 4 levels/12 posts → 2/5; table drawer 17 posts in a write tx → 1 with no tx; admin gate 3→1 reads; Oregon post-idle first statement 264→63 ms p50. Follow-on track: PERMISSION_PROMPT_CONSOLIDATION (pane 690) for the prompts that stalled W0/W3/W7 | — | — fired 2026-09-24 00:10–00:30 CDT, all goals armed | W1b 676 · W3 677 · W2 678 · W5 681 · W4a (see log) |
| Ownership rulings | warm route + R20 → W4a; A6-16 register fold → W5 (+ formActions.ts, passkeyCeremonyActions.ts); W5 granted logout route (A6-18) and the three history action files (A6-20) | pings 00:19–00:24 |

### Deploy state and W10 (added 2026-09-24 14:00 CDT)

- `origin/release` = `2bba10b1d` (W8) — deployed outside this session ~13:20. Fly regions follow `release`; **Oregon
  did NOT converge**: Amplify job 1497 (2bba10b1d) was killed at the 30-min build limit. Its `pnpm test:unit` went silent
  after ~80 of ~513 files (last line 18:34:38Z) — a HANG, not a failure. Oregon still serves 1495's `9682616e0`.
- W9 (landed after `2bba10b1d`, so not in that build) excludes the 8 land-tooling suites; they had not started when the
  build hung, so they are suspects, not the proven cause. The verifier run of the same sha also lost a vitest worker to
  SIGSEGV in the notificationActions tests.
- **W10** (pane 696, fired 14:00 CDT): find the hung / crashing tests, fix them at the cause, and bound the test step so
  a hang fails fast with the file's name. Then a verifier-green sha ⇒ `bash scripts/deploy-release.sh` (the operator's).
- **Operator note:** `/deploy` is a reso-session slash command; from a shell (`!`) the equivalent is
  `bash scripts/deploy-release.sh` in the reso checkout (no keyboard prompt; migration drops need
  `DEPLOY_CONFIRMED_DROP`). My earlier close handed `/deploy` as a shell command, which was wrong.
- **2026-09-24 14:34 CDT — operator ruled "deploy e94fa15b4 now"** (every verifier gate had passed; the design-gate
  Playwright runner hung after its last test, so no stamp was written). `DEPLOY_REQUIRE_GREEN=off
  scripts/deploy-release.sh --sha e94fa15b4` moved `release` 2bba10b1d → e94fa15b4, no migrations. **Amplify job 1498
  FAILED at the 30-min limit again, but for a different reason:** every test passed (503 files) and `next build`
  succeeded; the job ran out of time uploading its cache (30m19s). Unit tests took 1150 s in Amplify vs 528 s locally,
  and **this programme's round-trip/level tests are the slowest files (48–95 s each, ~1,000 of 2,057 test-seconds)** —
  probably barrier/level detection on timers that W9's `VITEST_TIMEOUT_FACTOR=4` multiplies. Handed to W10 as its top
  item. Immediate unblock staged for the operator (auto mode refused the agent a production build-config write):
  `/tmp/reso-oregon-build-timeout.sh --confirm oregon` raises `_BUILD_TIMEOUT` to 60 and re-runs the e94fa15b4 build.
- **W10 ✅ LANDED** reso `e51daae22` (12 paths). The Amplify overrun was NOT timers (the level ledger uses setImmediate
  only — hypothesis rejected with evidence): `createFullSchemaLibsqlDb` replayed 1,028 DDL statements per call (~5.4 s on
  CodeBuild, 62 suites) → template built once + byte copy; the 14 slow files 381 s → 16 s; the build's test command 507/507
  files in 212 s at load 223. The notificationActions SIGSEGV was a libsql 0.5.29 double close after a full replay
  (1/12 → 0/55). A main-process vitest watchdog (`VITEST_FILE_BOUND_S=300`) names a hung file; amplify.yml bounds the
  test step at 15 min. **Design-gate hang:** pnpm 11.27.1 runs scripts in a new session, so Playwright's group kill
  missed `next dev` (re-parented to launchd, holding the runner's stdout) → webServer execs next directly, teardown
  watchdog, globalTimeout 40 m. The verifier stamped `e94fa15b4` GREEN once the hung run cleared; `1f9cc09af` RED
  (pre-fix). Next: a green stamp on `e51daae22` → `scripts/deploy-release.sh` (operator-authorized 14:34), which should
  fit inside Amplify's 30-min limit without the staged timeout raise.
- **W10's watchdog stamped `e51daae22` RED in the verifier** (it SIGKILLed the LIVE ship-land and rotate-soketi-key
  suites at 300 s, measured from queue time, in the niced full-suite lane). A lead-inline fix (make the bound opt-in,
  `1f222d1cd`, red-on-parent proven) conflicted at land with a sibling's better fix already on trunk — `1a5dcda31`
  (DEPLOY_GATE_BUDGET): convict per-file SILENCE not age, and floor the bound at the caller's declared band (300 s on
  Amplify, ~1,440 s in the verifier). Mine is SUPERSEDED and dropped (local branch `lat-w11-watchdog-optin`, never
  pushed). Deploy now waits on the first green stamp newer than `e94fa15b4`.
- **17:08–17:23 CDT — `2580b40f8` stamped GREEN and deployed** (`scripts/deploy-release.sh`, verified, no migrations).
  **Oregon LIVE**: Amplify job 1499 SUCCEED in 13m40s (was 30m+ before W10); harbour + key serve `2580b40`.
  **Fly LAX/SIN/IAD FAILED**: Path F `flyctl-deploy-failed-after-3-attempts` in all three — `next build` type-checks
  the image context, and this programme's co-located tests + `vitest.setup.ts` shipped while the `lib/**/__tests__`
  helpers they import did not (TS2307). The fourth occurrence of that trap (63cfb4c83, 88af9bfe1, dec92dd1b).
  **W12 (lead-inline) LANDED `620120294`**: `.dockerignore` now excludes the SHAPE (`**/__tests__`, `**/*.test.ts(x)`,
  `vitest.*`), and `tests/docker-context-imports.test.ts` replays the context statically and fails naming any
  shipped file that imports an unshipped one (red on the parent with exactly the runner's TS2307 set; 3/3 green).
  Dallas (`reso-dfw`) is deliberately outside Path F until insomniacdenver launches (`deploy-regions.ts`).
  Next: a green stamp containing `620120294` → `deploy-release.sh` → Path F rebuilds LAX/SIN/IAD.
