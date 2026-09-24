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

## Status

| Wave | State | Evidence |
|---|---|---|
| R | IN PROGRESS — 10 agents fired 2026-09-23 | — |
