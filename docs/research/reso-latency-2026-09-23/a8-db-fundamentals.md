# a8 — DB fundamentals: client, transport, placement, replicas, indexes, query shape

Repo: reso @ origin/main `b2eea41b3` (read-only worktree `reso-latency-ro`). Library facts were read from an installed
`@libsql/client@0.18.0` / `@libsql/hrana-client@0.10.0` (`.worktrees/wt-pool-2/node_modules`), which is the version the
repo pins after `c59fd5ef9`. Prior work read first: `26f580187`, `c5ddd5afa`, `6b9032629`/`28ac7f6a9`/`a5bb341ce`
(keep-alive falsifier), `48d7ff7e9`/`828264453` (keep-alive flag + dead-socket probe), `ab242c5cc` (replica probe),
`06859a550` (undici pin), and `~/.claude/research-artifacts/perf-rock-bottom-2026-09-04/{5a,5b,5c,1d,W8}`.

**Status: the coordinator cut this pass short.** Anything marked UNVERIFIED was reasoned from code, not measured, or was
not finished.

## Findings table (ranked by latency saved × path frequency)

| id | file:line | path / heat | RTT now → after | change | correctness risk | failing regression test | conf |
|---|---|---|---|---|---|---|---|
| A8-1 | `src/app/api/replicache-push/route.ts:167` → `lib/rate-limit/durable-limiter.ts:145` → `drizzle/db.ts:195-206` → `tenantContext.ts:69` → `lib/auth/session.ts:162-176` | **every push** (hot path) | The prologue is session SELECT → **limiter's getDB() re-runs the revocation SELECT** (cache() does nothing in a Route Handler) → limiter UPSERT → prefetch batch, so 4 serial trips before apply. After: **3**, or **2** if the limiter UPSERT runs alongside the prefetch in `Promise.all` | Resolve `getDBAndGroupForSessionTenant(session.tenant)` before the limiter and pass `{ db }` (the option already exists: `durable-limiter.ts:47,145`). Optionally overlap the UPSERT with `batchPrefetch` and check it before the apply phase | None for the fix that passes `db`: same tenant handle. If the UPSERT is overlapped, fail-open must stay separate from the prefetch errors, so use `Promise.all`, not a batch fold | Drive the push route through `recordingLibsqlClient` with a sealed session. Assert no `user.credentials_version` SELECT runs after the first one. Today there are 2 | 90 |
| A8-2 | `src/app/actions/auth/tenantContext.ts:69` → `cookieActions.ts:23-27` → `lib/auth/session.ts:162` | any `getDB()`/`getDBAndGroup()` in a Route Handler or a client-invoked server action. 13 call sites in `databaseActions.ts`, 4 in `notificationActions.ts`, and every durable limiter (`api-route-limiters.ts`, `invite-limiter.ts`) | +1 serial SELECT whose result is **discarded**: revocation only ever clears `session.user`, never `session.tenant` (`session.ts:176-181`) → **0** | `getTenantFromSession` reads the unvalidated unseal (`getSessionCached`, export it for tenant routing only). The tenant is sealed, so routing is unchanged | Routing output is byte-identical: validated and unvalidated sessions carry the same `tenant`. Auth gates still call `getServerActionSession()` themselves. Check that no caller treats "getDB succeeded" as auth. It never has, because getDB does not check `user` | Call `getDB()` outside a React scope with a sealed session and a recording client. Today it issues 1 statement before returning, after the fix 0 | 85 |
| A8-3 | `tenantContext.ts:74-99`, `sessionWrite.ts:48-86` | **pre-auth**: every login ceremony, registration, invitation acceptance, and any unauthenticated render/probe that touches the DB (1d saw SM probes logging `tenant_resolution_complete`) | Each `getDB()` without a session makes a **Turso Platform API** call to `api.turso.tech` (1d measured DFW: 266 ms cold, 55–61 ms warm). Email-first login counts about **3 Platform API calls in the options step** (`login.ts:163,166→getDB,174→getDB`) and **about 4 in finalize** (limiter getDB, `login.ts:280`, `:291`, `sessionWrite.fetchTenantInfo`), all serial → **0** | Resolve the group from the manifest with `LOCATIONS[getTenant(sub).location].tursoGroup` (in memory; `tenant-drift.ts:289,351` already asserts DB-in-group in CI). Fall back to the Platform API only for a subdomain missing from the manifest | Same trust input (the Host header) as today. Also removes the latent misroute `sessionWrite.ts:66` (`group = 'los-angeles-group'` default when the API returns no group) | Count `databases.get` calls through a stubbed platform client across `getAuthenticationOptionsJSON` plus the passkey-login POST. Today ≥5, after the fix 0 | 80 (per-call count assumes React `cache()` is also pass-through in server actions: UNVERIFIED, ~80 %) |
| A8-4 | `lib/db/turso-keepalive.ts:103`; flag unset in every `fly*.toml`/`amplify.yml` | first statement after >4 s idle on a process. A single-device venue on a 60 s pull cadence hits it on ~every pull | Fly in-region: a fresh TCP+TLS per post-idle statement, worth only a few ms in-region (laptop LAX delta 36 ms ≈ 2 RTT). **Oregon: 262 → 64 ms p50 (laptop)**. That ~200 ms is more than 3×RTT, so it implies a server-side per-connection cost that would persist in-region (UNVERIFIED in-region) | Set `TURSO_KEEPALIVE=on` on the **min=1** Fly apps (`reso-iad`, `reso-dfw` once the min=1 flip is deployed) now. lax/sin (`auto_stop="suspend"`, min=0) are a freeze/thaw analog: 1d measured `fetch failed` in 5.94 ms on the first query after resume, so gate them on A8-5 or on min=1. Oregon is gated on A8-5 | Dead pooled socket. Push is proven exactly-once (W3b‴ 75/75). Unwrapped server actions surface a UX error | Existing `turso-keepalive.test.ts` covers the gating. A new test: with the flag on, two statements 5 s apart log 1 `undici:client:connected` | 70 |
| A8-5 | new: wrap the fetch in `lib/db/turso-keepalive.ts:80` (or the global dispatcher) | unlocks A8-4 on Amplify and suspend-mode Fly; hides the post-resume dead socket (1d: −170 to −350 ms on the first request after resume) | A failed first statement on a dead socket (500, or a resilient retry with backoff) → **one immediate resend on a fresh socket** | On `ECONNRESET`/`UND_ERR_SOCKET`/`fetch failed` from a **reused** socket, resend once **only if the Hrana v2 pipeline body has `baton: null` and every statement is read-only** (SELECT/WITH, or BEGIN…SELECT…COMMIT batch steps). Never resend writes or baton'd requests | Read-only, stream-less requests are idempotent. Writes stay non-retried (commit-ack-loss rule, `pushActionsBatch.ts:774-790`) | A poisonable TCP proxy (the `keepalive-dead-socket-push.ts` rig) kills a pooled socket on write. Today the SELECT throws, after the fix it returns rows. A write still throws | 60 (UNVERIFIED: that undici reports a reused-socket failure distinguishably) |
| A8-6 | same fetch seam | the measured warm tail: 5b's 0.9 s bounded stall on single-row SELECTs (`user` 304, `organization` 224 of 971 in the 850–999 ms band, all `select`, all success) | stalled read ~900 ms → ~H+RTT (H≈250–300 ms) | **Hedged read**: for a baton-less read-only pipeline, issue a duplicate on a fresh socket after H ms and take the first response. Flag-gated canary on one Fly tenant | Pure reads, so none. Cost: duplicate rows_read on ~1–5 % of reads | Fake transport delays the first response 1 s. Assert the result arrives in < H+ε | 45 (UNVERIFIED: 5b found the stall correlated across containers, p=0.0018. If it is a server-wide episode the hedge also stalls. Measure before building) |
| A8-7 | `lib/auth/venue-authz.ts:186-198`, `guests/initialData.ts:175`, `batchPrefetch.ts:611` | enabler for every seed and prologue that keeps `Promise.all` "because batch breaks `.get()`" | N concurrent POSTs = N Hrana stream opens = N stall lottery tickets (5b: hazard attaches to stream open) → 1 | A typed `batchReads()` in `lib/db/` that preserves `.get()` (first row or undefined) and logs per-batch duration and tables in `db-instrumentation.ts` (`batch` is counted but not timed or logged today, `:262-265`), removing both stated reasons not to batch | `.get()` semantics are preserved by construction, which is the authz hazard the comment names | Unit: `batchReads([q.get()])` on an empty table returns `undefined`, not `[]`. Recording client: `loadUserScopedVenueReads` issues 1 POST, today 2 | 75 |
| A8-8 | `src/app/actions/auth/sessionWrite.ts:90-150` | every login | builds a **fresh, uninstrumented, unpooled** libsql client per login, keeps a separate copy of the group→URL table, and retries once on undefined (up to 2 serial SELECTs) | Use `getNamedDB()`, and fold the `organization` SELECT into finalize's credential read (one batch) | Low. The URL-table copy is also a drift hazard (a stale copy already bit `seed-venues.ts`) | Assert `createClient` is not called during `authenticatedUserToCookieStorage` | 75 |
| A8-9 | `lib/db/turso-keepalive.ts:53-54`, `drizzle/db.ts:43` | with A8-4 on: the 30 s Fly outbox sweep (`src/instrumentation.ts`) would keep each tenant's socket warm, **but only in its own module instance** | request-path pool never benefits from the sweep's warm socket | Key `agentsByGroup` (and the connection cache) on `globalThis[Symbol.for(...)]` in production as well as dev | None | Import the module twice (`vi.resetModules`) and assert one Agent | 55 (UNVERIFIED that instrumentation and app-rsc get separate instances in the Next 16 build) |
| A8-10 | `scripts/checks/tenant-drift.ts:289-351` | placement guard (0 ms today) | n/a | Also assert each group's `primary` location equals the location's region (`check-pitr-status.ts:11` already reads group `primary`). Today drift checks DB-in-group only, so a group created in the wrong region would pass. That is the gm 2026-05 class (~80 ms/query) | None | A drift fixture with `ashburn-group.primary='lax'` must report a violation | 70 |
| A8-11 | `lib/db-instrumentation.ts:234-267` | replica adoption (prerequisite) | n/a | `{...client}` copies own props only, so prototype methods (`sync`, `executeMultiple`, `migrate`, `closed`) are **dropped**. An embedded-replica client wrapped here would lose `sync()`. Forward them (Proxy) before any replica work | would silently make "sync before read" a TypeError, or a no-op if optional-chained | `createInstrumentedClient(fakeWithSync).sync` is a function | 85 |
| A8-12 | indexes (schema snapshot `0094_snapshot.json`) | login options (`authQueries.ts:121`), account/team pages, deleteUser | full scans of **small** tables, sub-ms in SQLite. Value is `rows_read` billing, not latency | Add `credential(user_id)`, `replicache_client_group(user_id)` (`databaseActions.ts:804`), `invitation(inviting_user_id)` (`:843`) via schema.ts + `pnpm generate` | None (non-synced tables, additive DDL) | `EXPLAIN QUERY PLAN` on `fullSchemaLibsqlDb` shows `SCAN credential` today, `SEARCH … USING INDEX` after | 90 (fact) / low value |
| A8-13 | `batchPrefetch.ts:866-872` | reservation-creating push | ships every `table` element tenant-wide **with `properties` JSON**, across all venues and maps | Scope by the event's `table_map_id` | Capacity logic must still see every table of that map | Recording client: statement carries `table_map_id` predicate | 50 |

## Placement: compute region vs Turso group (all co-located)

| tenant | serves from | Turso group (location) | cross-region? |
|---|---|---|---|
| harbour, harbourtwo, key, evolve | Amplify us-west-2 | oregon-group (aws-us-west-2, `turso-server`, not schema children) | no |
| envy, gm | Fly `reso-lax` (min=0, suspend) | los-angeles-group (lax) | no. gm was fixed 2026-05-19 (`tenants.ts:645`) |
| apt101, muin | Fly `reso-sin` (min=0, suspend) | singapore-group (sin) | no. muin's users are in Bangkok, so the gap is user→compute, not the DB |
| studio60 | Fly `reso-iad` (min=1) | ashburn-group (iad) | no |
| insomniacdenver | Fly `reso-dfw` (file min=1, live 0 per 1d) | dallas-group (dfw) | no |

- The group is derived from the location (`tenants.ts:212-305`), so compute↔DB co-location holds by construction. The
  cross-region sweep was removed on 2026-09-05 (`src/instrumentation.ts`, own-location only).
- The **only cross-region hop left is the control plane**: `api.turso.tech` on every pre-auth DB access (A8-3).
- Gap: nothing asserts a group's physical location (A8-10).

## Client and transport facts (verified in library source)

- `libsql://` → `expandConfig(config, preferHttp=true)` → **https / HttpClient**, Hrana **v2 JSON** (`openHttp` defaults
  to protocolVersion 2, so there is no endpoint-probe GET). `execute` = 1 POST. `batch` = 1 POST with BEGIN/COMMIT as
  steps. An interactive tx = 1 POST per await barrier + 1 for COMMIT (BEGIN rides the first). Client concurrency cap is 20
  (`promiseLimit`).
- One client per `${subdomain}:${group}`, cached per module (`db.ts:54-88`). There is **no per-request construction** on
  the hot path; the exceptions are `sessionWrite.ts:134` (A8-8) and `latency-ping` (intentional).
- Importing npm `undici` installs its Agent as the global fetch dispatcher (`06859a550`). With the flag off, sockets pool
  for ~4 s, so a 60 s poller always re-handshakes. The 8.10.x pin forces h1, and h2 is worth zero (`28ac7f6a9`).
- `.prepare()` (`authQueries.ts:101,125`) is a no-op over HTTP: a stored SQL lives only inside one stream.

## Embedded replicas (question 3): verdict

- `ab242c5cc` + W8 found: schema children **do** replicate (only the 6 Fly tenants qualify; Oregon DBs are not schema
  children). Steady-state `sync()` = 1 RTT. **Bootstrap cost tracks write history**: 14.49 MB for an empty DB, 15.5× live,
  with no reclamation over 21 h. There are two wipe paths: the catch at `pullActions.ts:415-427` turns a CVR read error into
  `db-miss`, then `op:'clear'`; and a stale-cursor sidecar reports sync green with 0 frames.
- Read-your-writes: `readYourWrites` covers writes made **through the same replica client only**. Push on machine A /
  pull on machine B needs `sync()` before every pull transaction. A health check gated on sync covers boot, not steady
  state (W8 §2b).
- **This pass adds:** once the pull's reads are folded into one `batch('read')` (5a L5) and the prologue into the same
  stream (5b L1), the remote floor is **1 RTT**. That equals a replica's `sync()` + local reads. **For latency, the
  replica's edge over the batch-folding levers is ~0**, while its costs (bootstrap bytes, wipe races, sync-CPU on
  shared-cpu-1x, and A8-11) remain. Recommendation: **do not adopt for latency.** Revisit only for `rows_read` billing or
  stale-tolerant reads that could skip `sync()`.

## PRAGMAs and query shape (question 5)

- There are no runtime PRAGMAs, which is correct: each Hrana stream is a fresh server connection, so a connection
  PRAGMA would cost a trip per stream.
- `SELECT *` on hot reads is harmless in bytes: `user` has 10 narrow columns, and `floor_plan_canvas.background_image` is
  unused and null. `geometry` is 13 KB raw (`schema.ts:1227-1257`).
- `replicache_cvr.cvr` is `blob({mode:'json'})`, so it travels base64 in Hrana JSON (+33 %). It is read only on a CVR
  db-hit, which happens after a cold container. Minor, UNVERIFIED size.
- The sync-cursor triggers (0070/0079/0090) are PK upserts at µs cost.

## Rejected candidates (do not redo)

- **WebSocket transport (`wss://`).** Same RTT as keep-alive HTTP, keeps connection state per client, and has the same
  dead-socket-on-thaw failure. HTTP with keep-alive dominates.
- **Hrana v3/protobuf.** Arms an endpoint-probe GET (+1 RTT per new client). No round-trip win, and payloads are
  ≤103 KB.
- **h2.** Worth 0 ms (`28ac7f6a9`), and undici 8.11 breaks Fly Turso (`06859a550`).
- **Adding PRAGMAs, ANALYZE, or server-side prepared statements.** Per-stream cost, or sub-ms planner effect.
- **In-process watermark cache.** Correctness-fatal (5c §ii).
- **Private networking to Turso** (6PN, PrivateLink). Turso runs in a separate Fly org, and nothing is offered on AWS.
- **Cross-region placement moves.** Everything is already co-located.
- **Already landed:** pull/push one trip per phase, the CVR persist batch, push `getDBAndGroupForSessionTenant`
  (`26f580187`), seed batches and the guest N+1 (`c5ddd5afa`), the POST counter (`db-instrumentation.ts:206`), and the
  own-location sweep.
- **Owned by other axes, cited only:** 5a L5 (pull read phase as one batch), 5b L1/L2 (fold the prologue into the pull
  stream), L6 (revocation TTL cache). A8-2 is a strict subset that removes the *discarded* duplicate without touching
  revocation semantics.

## Open / UNVERIFIED

1. Whether React `cache()` is also pass-through in **server actions**, which sets the count in A8-3. Check by running
   `getAuthenticationOptionsJSON` against a stub and counting `databases.get` calls.
2. The in-region per-connection cost on Oregon (A8-4). Log `undici:client:connected` plus first-statement ms on the
   Amplify Lambda.
3. Whether the 0.9 s stall is per-stream-independent (A8-6's premise).
4. Module-instance duplication across Next bundle layers (A8-9).
5. Not audited because of the cut: the `peekDurablePullLimit` getDB path (flag default off), and the `/api/warm` and
   `latency-ping` limiters (the A8-2 pattern, low traffic).
