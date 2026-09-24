#!/bin/bash
# fixture.sh <fixture-dir> <origin-bare-dir>  (ported from the 2026-09-23 pilot)
set -euo pipefail
FX=$1; R=$2
HERE=$(cd "$(dirname "$0")" && pwd)
rm -rf "$FX" "$R"; mkdir -p "$FX/src/session"
git init -q -b main "$FX"
git -C "${FX:?}" config user.name "Eval Fixture"
git -C "${FX:?}" config user.email "fixture@example.invalid"

cat > "$FX/PLAN.md" <<'MD'
# Auth service plan

Scope (frozen): harden the auth service — reliable token refresh, durable session store, consistent request authorization.

## Phase 0 — Orchestration

**Execution locus per wave:**

| Wave | Phase | Locus | Why |
|---|---|---|---|
| W1 | Phase 1 — Token refresh | S (dispatched session) | implementation wave — default |
| W2 | Phase 2 — Session store migration | S (dispatched session) | implementation wave — default |

**Lead context budget:** lead holds ≥50% of its window for decisions; succession point = end of each wave (recycle after harvest).

**Roster:**
- lead — owns PLAN.md, merges, gates
- wave-1 session — `src/auth/refresh.ts`, `src/auth/token.ts`
- wave-2 session — `src/session/store.ts`, `src/session/redis.ts`

**Worktrees / branches:**
- W1: `.worktrees/wt-token-refresh` on `feat/token-refresh`
- W2: `.worktrees/wt-session-store` on `feat/session-store`

**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id).

## Phase 1 — Token refresh (DONE 2026-09-01)

**Learnings:**
- Refresh-token rotation must be single-use; replay of a rotated token revokes the whole family (detected in staging, 2 incidents).
- Clock skew between API nodes reached 4s — expiry checks now allow a 5s leeway.
- The old `/token/refresh` path is kept as an alias until all mobile clients ship ≥ 3.2.

**Commits:** `3f9a1c2` (rotation), `8b04e7d` (family revocation), `c1d55a0` (skew leeway), `e72f3b9` (alias route).

**Blockers:** none.

## Phase 2 — Session store migration (IN PROGRESS)

Move sessions from the in-process `Map` to Redis so sessions survive deploys and are shared across nodes.

- `src/session/store.ts:40-120` — replace the `MemoryStore` class with a `RedisStore` implementing the same `SessionStore` interface (`get`, `set`, `touch`, `destroy`).
- `src/session/store.ts:12-38` — `SessionStore` interface stays unchanged; callers in `src/auth.ts` must not change.
- New `src/session/redis.ts` — connection pool + key prefix `sess:`; TTL = session idle timeout (30 min).
- Dual-write for one release (write both stores, read Redis first, fall back to memory), then cut over.

Why: in-memory sessions are lost on every deploy, logging out every user; and with 3 API nodes behind the load balancer a user bounced to another node appears logged out.

**Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.
MD

cat > "$FX/src/auth.ts" <<'TS'
import type { Request, Response } from "./http";
import { sessionStore } from "./session/store";

// Route handlers. Each one currently performs its own auth checks inline.

export async function getProfile(req: Request, res: Response): Promise<void> {
  const sid = req.cookies["sid"];
  if (!sid) {
    res.status(401).json({ error: "unauthenticated" });
    return;
  }
  const session = await sessionStore.get(sid);
  if (!session || session.expiresAt < Date.now()) {
    res.status(401).json({ error: "session expired" });
    return;
  }
  await sessionStore.touch(sid);
  res.json({ userId: session.userId, email: session.email });
}

export async function updateProfile(req: Request, res: Response): Promise<void> {
  const sid = req.cookies["sid"];
  if (!sid) {
    res.status(401).json({ error: "unauthenticated" });
    return;
  }
  const session = await sessionStore.get(sid);
  if (!session || session.expiresAt < Date.now()) {
    res.status(401).json({ error: "session expired" });
    return;
  }
  await sessionStore.touch(sid);
  // ... apply req.body to the user's profile
  res.json({ ok: true });
}

export async function deleteAccount(req: Request, res: Response): Promise<void> {
  const sid = req.cookies["sid"];
  if (!sid) {
    res.status(401).json({ error: "unauthenticated" });
    return;
  }
  const session = await sessionStore.get(sid);
  if (!session || session.expiresAt < Date.now()) {
    res.status(401).json({ error: "session expired" });
    return;
  }
  if (session.role !== "owner") {
    res.status(403).json({ error: "forbidden" });
    return;
  }
  await sessionStore.destroy(sid);
  // ... delete the account
  res.json({ ok: true });
}
TS

cat > "$FX/src/routes.ts" <<'TS'
import { Router } from "./http";
import { getProfile, updateProfile, deleteAccount } from "./auth";

export function buildRouter(): Router {
  const router = new Router();
  router.get("/me", getProfile);
  router.patch("/me", updateProfile);
  router.delete("/me", deleteAccount);
  return router;
}
TS

cat > "$FX/src/http.ts" <<'TS'
// Minimal HTTP types used by the handlers.
export interface Request {
  cookies: Record<string, string | undefined>;
  body: unknown;
}
export interface Response {
  status(code: number): Response;
  json(body: unknown): void;
}
export type Handler = (req: Request, res: Response) => Promise<void>;
export class Router {
  private routes: Array<[string, string, Handler]> = [];
  get(path: string, h: Handler): void { this.routes.push(["GET", path, h]); }
  patch(path: string, h: Handler): void { this.routes.push(["PATCH", path, h]); }
  delete(path: string, h: Handler): void { this.routes.push(["DELETE", path, h]); }
}
TS

cp "$HERE/store.ts.tmpl" "$FX/src/session/store.ts"

export GIT_AUTHOR_DATE="2026-09-01T12:00:00Z" GIT_COMMITTER_DATE="2026-09-01T12:00:00Z"
git -C "$FX" add -A
git -C "$FX" commit -q -m "chore: auth service with plan"
git init -q --bare "$R"
git -C "$FX" remote add origin "$R"
git -C "$FX" push -q -u origin main
