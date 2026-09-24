# A10 — Measurement: how the round-trip programme will be PROVEN

Axis: the instruments, not the queries. Repo read at `b2eea41b3` (read-only; no test was run, so every
"now" count marked *est.* comes from reading the code and W0 has to measure it).
Answers: (1) is there a per-request round-trip counter usable in unit tests; (2) the best production signal
per path, with its recorded baseline; (3) a ratchet that fails when someone adds a query.

**Bottom line.** Round trips are already counted well at the UNIT level. There is a client recorder, a
transaction-stream recorder and a full-schema libSQL fixture, with negative controls. What nobody has
measured is the WHOLE REQUEST: every suite stubs session, limiter, auth prologue, venue resolution and
`getDB()`. That makes the production-only round trips structurally invisible to tests, and 62a8145c8 was one
of those. The counters also measure only POSTs. They have no notion of serial LEVELS (what the user waits for)
or of stream opens (where the ~0.9 s stall hazard attaches). The production counter `postsIssued` does not
count what its docstring says it counts. It is logged on the pull only and is missing its first round trip.
RSC pages, server actions, push and the watermark GET have no per-request round-trip signal at all.

---

## 1. Findings (measurement gaps and the latency costs they hide), ranked

Scoring: (the proof capability unlocked, or the ms saved) × path frequency.
Frequencies: pull is per 60 s poll per client, and per poke. Push is per mutation. RSC is per navigation. Actions are per click.

| id | file:line | path · heat | NOW → AFTER | change | correctness risk | red-on-today test | conf |
|---|---|---|---|---|---|---|---|
| M1 | `lib/db/__tests__/recordingLibsqlClient.ts:40-117`; `src/app/actions/replicache/__tests__/roundTripStream.ts:67-146` | all paths · every proof | instruments count POSTs only → count **levels** (serial depth), **posts**, **streams** | build `requestLedger` (§2.2): a barrier-stepped transport. Levels = the latency floor. Streams = stall exposure (hazard attaches to stream open, `docs/sync/README.md` "Measured 2026-09-05") | none (test-only) | self-test: `Promise.all` of 3 executes must read posts 3 / levels 1. `posts()` cannot express the levels half today | 90 |
| M2 | every round-trip suite stubs its neighbours: `round-trips.test.ts:45-65`, `seeds-round-trips.test.ts:47-77`, `replicache-push/route.test.ts:21-42` | pull, push, RSC · per request | whole-request total never asserted → asserted per path × arm | prod-arm request harness (§2.3). Run the REAL `drizzle/db` production branch over a recorder; mock only transport, cookies and headers | none (test-only) | `push(1 op)` whole-request ≤ 6 posts goes RED on today's code: M3's extra SELECT makes it 7 *est.* | 85 |
| M3 | `lib/rate-limit/durable-limiter.ts:145` (`opts?.db ?? await getDB()`), called without `db` at `src/app/api/replicache-push/route.ts:167` | **push · per mutation** (prod only) | session SELECT → [`getDB()` → `getConnectionParams` → `getSubdomainAndGroup` → `getTenantFromSession` → validated session: a **second `credentials_version` SELECT**] → UPSERT: **3 serial levels → 2** | pass `{ db }` from `getDBAndGroupForSessionTenant(session.tenant)` into `checkPushRateLimitDurable`, as the pull and push data paths already do (`drizzle/db.ts:272-301`). The option already exists (`durable-limiter.ts:47`) | tenant: the db is resolved from the SESSION tenant (same as the push data path), not the host. The 50 ms fail-open budget now covers 1 round trip, not 2, so the limiter fails open LESS | prod-arm harness `push(1 op)`: ledger shows `user` read twice before `rate_limit_counter` | 85 |
| M4 | `lib/db-instrumentation.ts:236-248` (tx `execute` counted per statement; `commit` passes through uncounted) | pull, push · every logged request | prod `postsIssued` ≠ POSTs: counts in-tx **statements**, not pipelined **windows**, and misses COMMIT. The W3d change path's 11-fetch window (`round-trips.test.ts:426`) logs 11 and should log 1 | count at the transport: wrap `fetch` at `drizzle/db.ts:69-72` (the keep-alive fetch plumbing is already there), so one increment = one HTTP request. Or make the tx proxy window-aware and count `commit`/`rollback` | wrapping `fetch` while `TURSO_KEEPALIVE` is off breaks the "byte-identical when flag off" invariant (`drizzle/db.ts:64-67`). A pass-through wrapper over `globalThis.fetch` should be behaviour-identical; verify on a Fly canary | extend `db-instrumentation.test.ts`: a tx with `Promise.all` of 3 executes then commit must read **2** (today 3) | 90 |
| M5 | `src/app/api/replicache-pull/route.ts:59` (session) and `:128` (durable peek) sit before `runWithDBContext` at `:220` | pull · per pull | logged `postsIssued` misses the session SELECT, the first round trip of every pull, and the one the 2026-09-05 wave found costs 39.4 % of the slow budget. Fix: 1 missing → 0 | open the DB context at the top of the handler (pass a mutable context object; `updateContextGroup` already mutates it) | none | route-level test: pull with an authenticated fake session must log `postsIssued` ≥ 1 more than `processPull`'s ledger | 90 |
| M6 | `src/app/api/replicache-push/route.ts:193,238,267,421,467` | push · per mutation | `t0` is set AFTER session, limiter, JSON parse and `getDB`, so push `durationMs` and `X-Server-Duration-Ms` exclude 2-3 DB round trips. The client's `networkLatencyMs` (`lib/rum/sync-types.ts:58-61`) books them as "network". An early throw logs `durationMs = Date.now() − 0 ≈ 1.76e12` | `const t0 = Date.now()` at handler top (the pull's I0 fix, pull `route.ts:43`). Add `sessionMs`, `limiterMs` and `postsIssued` to the push `logDBMetric` | none; the log fields are Logs-Insights/Loki only, so the filter quota is untouched | route test: a malformed-JSON push must log a finite `durationMs` (today ≈ epoch) | 90 |
| M7 | `src/components/LandingPageOrLoggedInApp.tsx:204-221` (`ssr_timing`); no `runWithDBContext` on any RSC path | **RSC · per navigation** | `ssr_timing` covers the layout only. It carries no round-trip count and has no consumer (0 hits in `grafana/`). Every RSC query logs `requestId: 'no-context'` | RSC ledger: `countPost` falls back to a React `cache(() => ({ postsIssued: 0 }))` object when there is no ALS context. The layout emits `doc-metrics/rsc_posts` from `after()`, which captures the ledger object, so page seeds are included | must never throw on the hot path (wrap like `run-after-response.ts` `logAfter`). Needs a check in a local prod build (`RESO_LAB_LOCAL_DB=1`) that the logged count equals the harness count | harness: layout+page `/floor-plan/[id]` doc-cold budget | 65 |
| M8 | no server-side timing on any hot server action (only auth-flow `durationMs`, `databaseActions.ts:137…`) | actions · per click | nothing → `db-metrics event:'action' {actionName, durationMs, postsIssued}` | `withActionLedger(name, fn)`: `runWithDBContext` + one log line. Add `'action'` to `parentOperation` (`lib/db-context.ts:12`). Apply only to the hot actions the other axes name | the wrapper must not swallow `redirect()` / `notFound()` throws: rethrow everything | harness: each wrapped action gets a budget row | 80 |
| M9 | `src/app/api/sync-watermark/route.ts:28-58` | watermark GET · per 60 s per client once cheap-poll is on | no metric at all. 3 posts / 2 levels *est.* (session, then 2 concurrent SELECTs, `lib/sync-cursor.ts:67-74`) → 2 / 2 with one `db.batch`, or 1 / 1 if the revocation read folds in | log `event:'watermark'` with `postsIssued`. Batch the two SELECTs | `batch(…,'read')` is one snapshot (`docs/sync/README.md`), no weaker than today's two unsynchronised reads | harness row `watermark GET` ≤ 2 posts goes RED at 3 | 80 |
| M10 | `grafana/alerting/loki-recording-rules.yaml:206,219,239,253,268`; `composite-health-sync-rules.yaml:67,84` | pull/push dashboards | `reso-dfw` is missing from every db-metrics selector, so Dallas pulls and pushes are invisible. `postsIssued` has no recording rule | add `reso-dfw`. Add recording-only rules `pull_posts_issued_avg:5m by fastPath` and `pull_fast_le300_ratio:5m` | SNS invariant: recording rules only, no alert (`.claude/rules/monitoring.md`) | `scripts/sync-loki-ruler-rules.sh lint` with a negative control (1d81c17b0 precedent) | 95 |
| M11 | `lib/run-after-response.ts` (inline fallback outside a request scope), used at `pullActions.ts:1029` | pull, push · test semantics | unit counts include post-response work: W3d's change-path `10` includes the CVR persist (`round-trips.test.ts:423-436`), which production runs AFTER the response | the harness mocks `next/server` `after` into a queue. Critical-path ledger first, then `drainAfter()` recorded separately | none | budget rows split `critical` / `deferred` | 90 |
| M12 | `DBMetricLog` has no deploy-SHA field (`lib/db-logger.ts:10-209`) | pull/push before/after proofs | before/after goes by wall-clock only, while Amplify has served a build weeks stale (`docs/infra-deploy/learnings.md`, 2026-09-06: harbour on 08-28 with 55 commits undeployed) | add `gitSha: GIT_SHA \|\| NEXT_PUBLIC_GIT_SHA` to pull/push/action/watermark logs. `ssr_timing` already has it (`LandingPageOrLoggedInApp.tsx:210`) | low cardinality; Loki/Logs-Insights only | unit: `logDBMetric` pull entry carries `gitSha` | 90 |

Also recorded for the proof plan (not ranked):

- **M13, the env-shape trap.** A suite that inherits a flag measures a different shape on a laptop than in the
  Amplify preBuild. Amplify build 1486 failed that way (`.claude/rules/replicache.md:441-447`). Every
  shape-changing flag must be stubbed on each arm: `REPLICACHE_PULL_CURSOR_GATE` (prod ON),
  `REPLICACHE_PULL_FAST_PATH` (ON), `REPLICACHE_PULL_WINDOW` (off), `REPLICACHE_PULL_LIMITER_DURABLE` (off),
  `TURSO_KEEPALIVE` (off), `VENUE_SCOPING_FLAG_TTL_MS`, `NODE_ENV=production` plus the `TURSO_AUTH_TOKEN_*`
  and org env (the prod arm of `getConnectionParams`, `drizzle/db.ts:204-222`), and `RESO_LAB_LOCAL_DB` unset.
- **M14, the withTimeout race.** The limiter's 50 ms `withTimeout` (`durable-limiter.ts:58`) can fire on a loaded
  box and fail open, which changes the count. The harness must stub `@lib/timeout` to pass through.

## 2. Q1 — the per-request DB round-trip counter

### 2.1 What exists (inventory)

| instrument | where | counts | covers | limits |
|---|---|---|---|---|
| `createInstrumentedClient().postsIssued` | `lib/db-instrumentation.ts:200-267` | lifetime total per client, plus per-request on the ALS context (`lib/db-context.ts:19`) | production; tests: `lib/__tests__/db-instrumentation{,-context}.test.ts` | in-tx statements not windows, no COMMIT (M4). Logged only by the pull (`route.ts:394`), without the session read (M5) |
| `recordingLibsqlClient` / `sequentialLibsqlClient` | `lib/db/__tests__/recordingLibsqlClient.ts` | trips `{kind, tables}`, `posts()`, `render()`; the sequential twin is the NEGATIVE CONTROL | seed suites (`src/app/actions/__tests__/seeds-round-trips.test.ts`, `src/app/(app)/guests/__tests__/seeds-round-trips.test.ts`) | client level only; no levels |
| `withTransactionRecording` (pipelined / serial) | `src/app/actions/replicache/__tests__/roundTripStream.ts` | Hrana windows modelled on `hrana-client` `stream.js`, COMMIT as a trip, submission-order hook | W3d pull/push (`round-trips.test.ts`), pinned under both cursor-gate arms | lives under one feature's `__tests__`, so it is not shared |
| issue/settle recorder | `src/app/actions/replicache/__tests__/pull-auth-context.test.ts:131-186` | ordinal issue/settle stamps; proves "one level" for one pair | R2 auth prologue | ad hoc; no general depth |
| `createFullSchemaLibsqlDb` | `lib/db/__tests__/fullSchemaLibsqlDb.ts` | substrate: every migration on a tmpfile libSQL; async `db.transaction` works | all of the above | none relevant |
| call a server component directly | `src/components/LandingPageOrLoggedInApp.test.tsx:61-80` | ordering of fan-out invocations | the (app) layout | every seed is mocked |

So yes, a counter exists for UNITS. It does not exist for REQUESTS, for LEVELS, or for RSC and actions in production.

### 2.2 Smallest thing to build: `lib/db/__tests__/requestLedger.ts` (~150 lines, test-only)

Move `roundTripStream.ts` beside the client recorder and merge them. Every POST, whether a client
`execute`, a client `batch`, a tx window or a COMMIT/ROLLBACK, goes through one `issue(kind, tables, run)`.

- **Barrier-stepped levels.** An issued POST is held. When the event loop drains (`setImmediate`, after all
  microtasks), every held POST is released as ONE level: run against the real fixture in issue order, then all
  resolved together. Anything issued in response lands in the next level, so `levels()` is the critical-path
  depth with no timers, which keeps it deterministic under load. The existing suites avoid wall-clock asserts
  for the same reason (`vitest.config.ts:19-58`).
- **Three numbers.** `posts()` = HTTP requests. `levels()` = serial depth, the latency floor at ≈ one Turso
  round trip each (86-380 ms post-idle by region and socket state, `lib/db/turso-keepalive.ts:6-8`).
  `streams()` = executes + batches + transactions, the stall-lottery tickets.
- **Two phases.** `critical` vs `deferred`. A `next/server` `after` mock queues callbacks. `drainAfter()` runs
  them under a fresh phase (M11).
- **Diagnosable failure.** `render()` prints `L1: batch user_venue_role+user · L2: execute replicache_client_group …`,
  so a red ratchet names the query that was added and the level it landed on.
- **Self-test** (`requestLedger.test.ts`), with controls:

  | shape | posts / levels / streams |
  |---|---|
  | 3 sequential executes | 3 / 3 / 3 |
  | `Promise.all` of 3 executes | 3 / 1 / 3 |
  | one `batch` of 3 | 1 / 1 / 1 |
  | tx: `Promise.all` of 3, then commit (pipelined) | 2 / 2 / 1 |
  | same tx, serial mode | 4 / 4 / 1 |
  | `after(() => execute)` | critical 0, deferred 1 |

  The serial-mode and sequential-transport arms are the negative controls: the same code must read higher.
- **Model vs wire.** The ledger is a MODEL of Hrana. M4's fetch-level counter is the wire. Calibrate the two
  once: W0 runs one pull and one push through the counting fetch against a scratch Turso DB, and the counts
  must match the ledger. That step needs operator approval (network + Turso). Until it is done, name the one
  known unmodelled request: the client's first-use protocol-version probe.

### 2.3 The prod-arm request harness: `lib/db/__tests__/prodArmHarness.ts`

`measureRequest({ mode: 'route' | 'action' | 'rsc', session, headers, cookies, env }, fn)`:

- `vi.mock('@libsql/client')`: `createClient` returns `ledger.client` over the fixture. `drizzle/db.ts` is left
  REAL, `vi.stubEnv('NODE_ENV','production')` plus the Turso org and token env. The production branch of
  `getConnectionParams` then runs, and with it the re-entry `drizzle/db.ts:285-287` calls "invisible in dev".
  M3 is exactly that class. So was the 62a8145c8 regression: an unconditional per-request SELECT that moved the
  pull residual p95 from 23 ms to 660-1,070 ms (`lib/db-logger.ts:56-62`).
  Run `vi.resetModules()` per case, because the prod connection cache is module-level (`drizzle/db.ts:42-47`).
- `iron-session` is mocked to a session `{ user, tenant, credentialsVersion }`, the pattern of
  `lib/auth/session.test.ts:34-44`. The revocation SELECT then runs for real against a seeded `user` row and
  is counted.
- React `cache`: in `route` and `action` mode, a pass-through, matching Next 16.3 (`drizzle/db.ts:275-277`,
  `lib/auth/session.ts:112-116`). In `rsc` mode, a request-scoped memo on AsyncLocalStorage, so per-render
  dedupe matches production. The pass-through mock that `session.test.ts` uses would over-count RSC.
- `next/cache` `unstable_cache`: a Map. The **cold** arm clears it. The **warm** arm replays the same tenant
  twice and measures request 2. Venue rows and the RUM config read through it (`lib/venue-resolution.ts:140-155`, `lib/rum/rum-config.ts:149`).
- Mocked to fixed values: `@lib/cache/dynamodb-store` / `getWarmed` (`null`, or a warm payload), `@lib/timeout`
  (pass-through, M14), the poke publish (network), and `next/headers`. `sec-fetch-dest` and the store-warm
  cookie drive `isWarmStoreRouterFetch` (`lib/replicache/store-warm.server.ts:80-86`), which gives the
  soft-nav-warm-store arm.
- Entry points: `POST`/`GET` exported from `route.ts` with a `NextRequest` (as `replicache-push/route.test.ts:69`
  already does), the action function itself, and for RSC `Promise.all([Layout({children:null}), Page(props)])`.
  An element walker then awaits any nested async server component.
  **Assumption to verify:** Next renders layout and page segments concurrently. If a W0 trace shows otherwise,
  run them sequentially.

## 3. Q2 — the production signal per path, and its recorded baseline

| path | best signal now | where it lands | recorded baseline (source) | gap / what W0 must add |
|---|---|---|---|---|
| **pull** (server) | `db-metrics event:'pull'`: `durationMs` (t0 at the top), `sessionMs`, `pullWorkMs`, `authUserMs`, `authVenueMs`, `cvrReadMs`, `ownershipMs`, `txOpenCommitMs`, `pullUnaccountedMs`, `postsIssued`, split by `fastPath`, `cvrSource`, `coldStart` (`lib/db-logger.ts:10-181`) | Loki `reso:loki:pull_p95_fast/change:5m` (`composite-health-sync-rules.yaml:63-93`; no dfw). CW `PullDurationFastPath/ChangePath` (Amplify only) | p95 **1,013 → 977 ms** after C-003. Warm fast-path mem-hit slow budget (n=1,690): **sessionMs 39.4 % + authUserMs 30.6 % + authVenueMs 11.3 %**, scans 7.5 %. Histogram peaks 900-999 ms, cliff at 1,000. A no-op pull issued **8 sequential POSTs, floor 2** (all `docs/sync/README.md` "Measured 2026-09-05"). Combined p50 112 / p95 1,016 ms (`.claude/rules/monitoring.md`, db-metrics-slow-pulls note). Warm `pullWorkMs` p95 ≈ 950 ms (`lib/db-logger.ts:73-76`). Alarm thresholds fast 400 / change 1,200 ms = 1.5 × observed p95 (`docs/runbooks/SYNC_PULL_HEALTH.md:20-21,51`) | **`postsIssued` baseline: not recorded anywhere.** The field landed 2026-09-05 (1d81c17b0) with no rule; W0 must query it. M4, M5, M10, M12 |
| **pull** (client) | `sync-latency operation:'pull'`: `latencyMs`, `serverDurationMs`, `networkLatencyMs`, `serverCold` (`lib/rum/sync-types.ts:31-120`) | Loki via `/api/logs` | session-start pull p95 **4,592 ms** (91 % return 97 B). A cold container adds p95 **3,790 ms** inside `networkLatencyMs` (`docs/sync/README.md`; `docs/observability/README.md:196-200`) | none; this is the user-felt number |
| **push** | server: `db-metrics event:'push_batch'` / `'push'` `durationMs` (t0 late, M6). Client: `sync-latency operation:'push'`, the 300 ms sync SLO (`reso:loki:slo_under_300ms_rate`, `recording-rules.yaml:107-117`) | Loki `reso:loki:push_duration_p95:5m` (no dfw). CW `PushBatchDuration` | **no push latency baseline in the repo docs** (searched `docs/`, `.claude/rules/`). Unit: `processPushBatch(10 ops)` = **4 POSTs** (`round-trips.test.ts:285-296`) | W0 must pull a 14-day push baseline from Loki. Add `postsIssued`, `sessionMs`, `limiterMs`, `gitSha` (M6, M12). Free existing proxy: the limiter's throttled fail-open log (`durable-limiter.ts:183`) says how often the pre-body segment exceeds 50 ms |
| **RSC page** | server: `doc-metrics event:'ssr_timing'` `{route, coldStart, warmHit, sessionMs, warmProbeMs, fanoutMs, seedsMs, totalMs, gitSha}`, layout only. Client: `cwv event:'nav-trace'` `rscTtfbMs`, `dataPaintMs`, `navOrdinal`, `navArm` (bce1ed57b, 10f95d22e) | nav-trace: Loki `reso:loki:nav1_{commit,dispatch_delay,rsc_ttfb,data_paint}_p75:5m` by tenant, dfw included (`loki-recording-rules.yaml:1191-1280`). `ssr_timing`: no consumer | Home TTFB **1,569 ms** (LCP path). /floor-plan cold TTFB p50 **≈2,488 ms** vs home **≈1,420 ms** before its fixes (`docs/floor-plan/learnings.md:328-334`). The acceptance FORM is fixed: **P(dataPaintMs ≤ 1000 ∣ navOrdinal = 1)** per tenant, n ≈ 152 per arm (`docs/observability/README.md:202-212`). Floor-plan `dataPaintMs` was never stamped before 10f95d22e (2026-09-19), so its baseline starts then | per-request RSC round-trip count (M7). A Loki rule for `ssr_timing` totalMs by route |
| **server action** | **none server-side.** Fly edge histogram `reso:edge_latency_p95:5m` has no path label, lax only (`recording-rules.yaml:17-30`) | none | none | M8 |
| **watermark GET** | none | none | none (flag `NEXT_PUBLIC_REPLICACHE_CHEAP_POLL` default off) | M9 |

Instruments ruled out as proof (reasons from the repo): CloudWatch client RUM and `scripts/rum-*.sh` (the
`check-latency` skill) cover n ≤ 14 over 7 days, Amplify tenants only, and 6 of 10 tenants write nothing to
CloudWatch (`docs/observability/README.md`, Measured 2026-09-05). The `check-latency` skill measures
client→Turso/Soketi probes, not request paths.

## 4. Q3 — the round-trip budget ratchet

**Files.** `tests/round-trip-budget.test.ts` + `tests/round-trip-budget.json`. This mirrors the repo's
bundle-budget ratchet (`tests/bundle-budget.test.ts`, `scripts/checks/bundle-budget.pure.ts`). It is enforced
where `test:unit` already gates: pre-push (`scripts/hooks/pre-push:133`) and the Amplify preBuild (`amplify.yml:37`).

**Semantics.** Integers are deterministic, so there is no slack.
1. **UP → RED.** `"<path>/<arm>: levels 5 → 6 (+1). New at L3: execute rate_limit_counter"`, with both `render()` ledgers printed.
2. **DOWN → RED** with `"ratchet: set budget to N"`. The budget edit lands in the same commit, so the diff IS the proof of the win. This is stricter than bundle-budget's advisory slack; round trips have no noise to absorb.
3. **UNBUDGETED → RED.** A new route handler under `src/app/api/**` that imports `drizzle/db`, or a
   `withActionLedger`-wrapped action, must declare a row.
4. **Every row carries a live negative control.** The same request over `sequentialLibsqlClient` plus serial
   tx mode must read a strictly higher `posts`, which proves the row can go red (W3d precedent, `round-trips.test.ts:299-318`).
5. **Arms are explicit.** `describe.each` over the flag matrix of M13. The ambient env is never inherited.

**Initial rows.** Values marked *est.* are read-derived. W0's first run REPLACES them with measurements before
any optimisation lands. That run is itself the baseline commit.

| row (path · arm) | critical levels / posts / streams NOW | target (owning axes) | how NOW was derived |
|---|---|---|---|
| pull · no-op · gate ON · CVR mem-hit · non-promoter · warm flag | **5 / 6 / 4** *est.*: L1 session `user` · L2 `user`+`user_venue_role` · L3 ownership(+BEGIN) · L4 watermark window · L5 COMMIT | **1 / 1 / 1**: one `batch('read')` carrying revocation, auth, ownership read and watermark (a read-only snapshot; no write on a no-op). Documented floor 2 | `round-trips.test.ts:337-340` (processPull fast = 3) + auth prologue 1 level/2 posts (`pull-auth-context.test.ts:120-160`) + session 1 |
| pull · no-op · gate OFF | 8 / 9 / 5 *est.* (processPull fast = 6) | same as above | `round-trips.test.ts:336` |
| pull · change path · gate ON · 10 entity types | critical ≈ 11 / 12 / 4 *est.*; deferred CVR persist 1 / 1 / 1 | ≤ 6 critical levels | processPull change = 10 incl. the deferred persist (`round-trips.test.ts:337,395-436`) |
| pull · promoter | measure (the authVenue tail adds ≥ 1 level, `lib/db-logger.ts:84-89`) | = non-promoter | W0 |
| push · 1 op · prod arm | **7 / 7 / 5** *est.*: session → session again (M3) → UPSERT → prefetch batch → ownership+BEGIN → apply window → COMMIT | ≤ 4 (fold the revocation SELECT and the limiter into the prefetch batch) | `round-trips.test.ts:285-296` (K = 4) + route reading |
| push · 1 op · dev arm (control that M3 is prod-only) | 6 / 6 / 4 *est.* | n/a (documents the dev/prod divergence) | same |
| push · 10 ops | 4 in processPushBatch (measured) + 3 prologue *est.* | ≤ 4 | measured part pinned today |
| watermark GET | 2 / 3 / 3 *est.* | 1 / 1 / 1 | `lib/sync-cursor.ts:67-74` |
| RSC `(app)` layout · doc · cold data-cache | ≥ 3 levels *est.*: L1 session SELECT · L2 joined fan-out (`LandingPageOrLoggedInApp.tsx:118-139`) · L3 `getDefaultEventID` / route seeds (`:188-193`) | ordinary page ≤ 2 levels (session read folded into the fan-out) | reading; W0 measures |
| RSC · each of `/`, `/lists`, `/guests`, `/floor-plan/[id]`, `/list/[id]` × {doc-cold, doc-warm-cache, softnav-warm-store} | measure | softnav-warm-store: 0 seed round trips beyond the session read (`isWarmStoreRouterFetch` skips seeds) | W0 |
| hot server actions (named by the action axes) | measure | per axis | W0 |

## 5. Production proof protocol (what "proven" means for each wave)

1. **Unit.** The ratchet row moves DOWN by exactly the claimed levels and posts in the same commit. Equality
   of returned rows is asserted against the sequential transport running the real function, as W3e/W3d do.
2. **Deploy identity.** Before reading any "after", confirm the serving SHA per app: `X-Deploy-SHA` on the pull
   response, `gitSha` on the logs (M12). Amplify has served weeks-stale builds (`docs/infra-deploy/learnings.md`).
3. **Deterministic field check.** `postsIssued` (fixed by M4 and M5) is an integer per request shape. Its MODE
   per (`event`, `fastPath`, `cvrSource`) must shift by exactly the unit delta within 1 h of deploy. A handful of
   requests suffices. No shift means the change did not ship, or the model is wrong: stop and look.
   LogQL: `{app=~"reso-lax|reso-sin|reso-iad|reso-dfw|reso-amplify"} |= "pull" | json | namespace="db-metrics" | event="pull" | fastPath="true" | line_format "{{.postsIssued}} {{.gitSha}}"`.
4. **Latency effect as a PROPORTION, not a small-n p95** (`docs/observability/README.md:210-212`, and the
   bimodality lesson in `.claude/rules/monitoring.md`): `P(durationMs ≤ 300 | fast path)` for pull,
   `P(push latencyMs ≤ 300)` (the existing SLO), `P(dataPaintMs ≤ 1000 | navOrdinal=1)` for RSC. Stratify by
   tenant and `coldStart`, 7 days before vs 7 days after. Stall exposure: the share of requests with any
   900-1,000 ms bucket hit should fall roughly in proportion to streams removed (the hazard is per stream open).
5. **Alarms untouched.** New rules are recording-only (SNS invariant). No new CloudWatch metric filters
   (quota 92/100, `.claude/rules/monitoring.md`).

## 6. Rejected candidates (so no one redoes them)

- **Playwright / dev server with `QUERY_LOGGING_MODE=all` as the counter.** The dev arm skips the prod
  re-entry (M3 is invisible there). `log-formatter` curates fields in dev (`db-instrumentation-context.test.ts:15-17`).
  It is slow and not deterministic.
- **Wall-clock asserts with injected latency (`setTimeout(D)` per POST).** They flake under the load this box
  runs at (`vitest.config.ts` notes). The barrier-stepped levels give the same depth deterministically.
- **`createTestDb` (better-sqlite3) as the substrate.** It rejects the async `db.transaction` the pull uses
  (`fullSchemaLibsqlDb.ts:4-9`). The `db.batch = Promise.all` shim some suites add
  (`getGuestBookSeed.seed-parallelism.test.ts:130-137`) cannot count posts.
- **A pass-through React `cache` mock for RSC budgets.** It over-counts against production's per-render dedupe.
  It is correct only for route and action mode.
- **p95 from CloudWatch RUM / `rum-*.sh` / the `check-latency` skill as acceptance.** n ≤ 14, Amplify only, wrong tenants.
- **Fly edge `reso:edge_latency_*` as a per-path signal.** No path label, lax only.
- **A Grafana alert on `postsIssued`.** It is a proof and diagnostic field. Paging on it violates the SNS invariant.
- **Snapshot-only ratchet (`toMatchSnapshot` of the ledger).** `-u` rubber-stamps regressions. Numbers live in
  JSON and are hard-asserted. The rendered ledger is printed for diagnosis only.
- **Counting at `execute` only (today's wrapper) as the production truth.** See M4. The fetch boundary is the only
  place where one increment = one request, by construction.

## 7. Adversarial pass (run before writing)

- *"Does levels even matter, if Turso cost is per POST?"* Both matter, differently. Each serial level costs
  ≥ 1 RTT (86-380 ms post-idle, `turso-keepalive.ts:6-8`). Each stream open is an independent draw on the
  ~0.9 s stall, hazard 4.56 % → 0.06 % as the stream stays open (`docs/sync/README.md`). A `Promise.all`
  change moves levels only. A batch change moves posts and streams. Hence three numbers.
- *"Is M3 real, or does cache() save it?"* The route handler runs pass-through `cache()` on Next 16.3
  (`drizzle/db.ts:275-277`). `getDB()` in the prod arm always goes through `getSubdomainAndGroup` →
  `getTenantFromSession` → `getServerActionSession` (`tenantContext.ts:69`, `cookieActions.ts:23-27`), and the
  limiter passes no `db` (`push route.ts:167`). The code says it is real. The harness will prove or refute it
  on its first run: the ledger shows `user` twice, or it does not.
- *"Do the existing unit pins already cover whole requests?"* No. Every one stubs its neighbours by design
  ("another unit's file", `seeds-round-trips.test.ts:14-24`), so no test owns the sum.
- *Unverified and named:* the ledger's Hrana model vs the wire (the W0 calibration in §2.2); Next
  layout/page render concurrency (§2.3); React `cache()` resolving inside the libSQL wrapper's async
  continuation during an RSC render (M7, confidence 65).
