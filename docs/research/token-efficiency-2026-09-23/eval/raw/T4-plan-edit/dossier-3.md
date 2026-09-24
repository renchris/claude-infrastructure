# Dossier run-3

## Prompt

```
add a phase to PLAN.md for moving the auth checks into middleware
```

## Final assistant message (verbatim)

```
📦 The Phase 3 plan edit is committed as `912ea97` but not pushed. I'm leaving it unpushed on purpose: the push to `origin/main` needed your approval and didn't get it, so trying again in another form would get around your call.
Good to close: no — `912ea97` still needs to be pushed to `origin/main`, and that step is yours.

▶ Run this:

`git -C /private/tmp/tokeff-eval/tasks/T4-plan-edit/fx-3 pull --rebase -q origin main && git -C /private/tmp/tokeff-eval/tasks/T4-plan-edit/fx-3 push origin HEAD:main`
```

## Tool calls in order (10)

1. `Skill: {"skill": "plan-conventions"}`
2. `Bash: git ls-files && echo ---- && cat -n PLAN.md`
3. `Bash: for f in src/auth.ts src/http.ts src/routes.ts; do echo "==== $f"; cat -n $f; done; echo ====; grep -n "" src/session/store.ts | head -40`
4. `Edit: {"replace_all": false, "file_path": "/private/tmp/tokeff-eval/tasks/T4-plan-edit/fx-3/PLAN.md", "old_string": "| W2 | Phase 2 — Session store migration | S (dispatched session) | implementation wave —`
5. `Edit: {"replace_all": false, "file_path": "/private/tmp/tokeff-eval/tasks/T4-plan-edit/fx-3/PLAN.md", "old_string": "- wave-2 session — `src/session/store.ts`, `src/session/redis.ts`\n\n**Worktrees / branch`
6. `Edit: {"replace_all": false, "file_path": "/private/tmp/tokeff-eval/tasks/T4-plan-edit/fx-3/PLAN.md", "old_string": "**Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.", "new_str`
7. `Bash: git diff --name-only && git add PLAN.md && git commit -q -m "docs: auth middleware phase in plan" && git log --oneline -1 && git status --short && (git remote -v | head -1 || true)`
8. `Skill: {"skill": "ship"}`
9. `Bash: git fetch -q origin main && git rev-list --count origin/main..HEAD && git rebase -q origin/main && git push -q origin HEAD:main && git fetch -q origin main && git ls-tree origin/main -- PLAN.md && git`
10. `Bash: ~/.claude/hooks/session-continue.sh clear`

## State after the run

### `git status --short --branch`
```
## main...origin/main [ahead 1]
[exit 0]
```

### `git log --oneline -5`
```
912ea97 docs: auth middleware phase in plan
b7111c9 chore: auth service with plan
[exit 0]
```

### `git show --stat HEAD`
```
commit 912ea97635866127d3a4c96e3f565319cb3d5c64
Author: Eval Fixture <fixture@example.invalid>
Date:   Wed Sep 23 21:35:45 2026 -0500

    docs: auth middleware phase in plan

 PLAN.md | 31 ++++++++++++++++++++++++++++++-
 1 file changed, 30 insertions(+), 1 deletion(-)
[exit 0]
```

### `git log --oneline origin/main -3`
```
b7111c9 chore: auth service with plan
[exit 0]
```

### `git --git-dir=$(git remote get-url origin) log --oneline -3 main`
```
b7111c9 chore: auth service with plan
[exit 0]
```

### `git branch -a`
```
* main
  remotes/origin/main
[exit 0]
```

### `git ls-files`
```
PLAN.md
src/auth.ts
src/http.ts
src/routes.ts
src/session/store.ts
[exit 0]
```

### `git diff --stat HEAD`
```

[exit 0]
```

### Final `PLAN.md`
```
# Auth service plan

Scope (frozen): harden the auth service — reliable token refresh, durable session store, consistent request authorization.

## Phase 0 — Orchestration

**Execution locus per wave:**

| Wave | Phase | Locus | Why |
|---|---|---|---|
| W1 | Phase 1 — Token refresh | S (dispatched session) | implementation wave — default |
| W2 | Phase 2 — Session store migration | S (dispatched session) | implementation wave — default |
| W3 | Phase 3 — Auth middleware | S (dispatched session) | implementation wave — default |

**Lead context budget:** lead holds ≥50% of its window for decisions; succession point = end of each wave (recycle after harvest).

**Roster:**
- lead — owns PLAN.md, merges, gates
- wave-1 session — `src/auth/refresh.ts`, `src/auth/token.ts`
- wave-2 session — `src/session/store.ts`, `src/session/redis.ts`
- wave-3 session — `src/middleware/auth.ts` (new), `src/auth.ts`, `src/http.ts`, `src/routes.ts`

**Worktrees / branches:**
- W1: `.worktrees/wt-token-refresh` on `feat/token-refresh`
- W2: `.worktrees/wt-session-store` on `feat/session-store`
- W3: `.worktrees/wt-auth-middleware` on `feat/auth-middleware`

**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id). W3 has no blockedBy: it only calls the frozen `SessionStore` interface and its files are disjoint from W2's, so it can run in parallel with W2.

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

## Phase 3 — Auth middleware (PLANNED)

Move the auth checks that every handler repeats inline into one middleware, so request authorization is enforced in one place and a new route cannot forget it.

Current state:
- `src/auth.ts:6-19`, `:21-35`, `:37-55` — `getProfile`, `updateProfile` and `deleteAccount` each repeat the same block: read `req.cookies["sid"]` → 401 `unauthenticated` if missing → `sessionStore.get` → 401 `session expired` if missing or `expiresAt < Date.now()`.
- `src/auth.ts:17`, `:32` — `getProfile` and `updateProfile` call `sessionStore.touch(sid)`; `deleteAccount` does not (it destroys the session at `:52`).
- `src/auth.ts:48-51` — `deleteAccount` alone adds a role check: 403 `forbidden` unless `session.role === "owner"`.
- `src/http.ts:10-16` — `Router` stores bare `Handler`s and has no middleware hook; `Request` (`:2-5`) has no `session` field.

Changes:
- New `src/middleware/auth.ts` — `requireAuth(handler, opts?: { role?: string; touch?: boolean })` returns a `Handler` that runs the sid → session → expiry checks, then the optional role check, then `touch` (default `true`), then calls `handler` with the session attached to `req`.
- `src/http.ts:2-5` — add `session?: Session` to `Request`, or an `AuthedRequest` type that extends it with a required `session`; the typed variant is preferred so handlers need no null check.
- `src/auth.ts` — strip the inline checks; handlers read `req.session`. `deleteAccount` keeps its `sessionStore.destroy(sid)` call.
- `src/routes.ts:6-8` — wrap each route: `requireAuth(getProfile)`, `requireAuth(updateProfile)`, `requireAuth(deleteAccount, { role: "owner", touch: false })`.

Constraints:
- Behaviour-preserving: same status codes, same error bodies (`unauthenticated`, `session expired`, `forbidden`), same touch/no-touch per route. Any change to expiry semantics (e.g. adding the 5s skew leeway from Phase 1) is a separate decision, not part of this phase.
- Use only the frozen `SessionStore` methods (`get`, `touch`, `destroy`) so the phase is unaffected by Phase 2's switch to Redis.

Trade-off: a per-route wrapper was chosen over adding a middleware chain to `Router`. It is explicit at each route and needs no change to `Router`; the cost is that a route registered without `requireAuth` is unprotected. If routes multiply, move to a router-level default-deny with an explicit `public()` opt-out.

Why: three copies of the same check drift apart (only `deleteAccount` skips `touch`, and only it checks the role), and the "consistent request authorization" goal in the frozen scope needs a single enforcement point.

**Done when:** each of the three routes returns the same status and body as before for no cookie, an unknown sid, an expired session and a valid session, plus a non-owner calling `DELETE /me`; and `src/auth.ts` has no remaining reference to `req.cookies`.
[exit 0]
```

## Outcome checks (run by the harness after the session)

### `git diff --stat b7111c975c7c2abe46d2551a2980ba993c8d98ca -- . ':!.claude'`
```
 PLAN.md | 31 ++++++++++++++++++++++++++++++-
 1 file changed, 30 insertions(+), 1 deletion(-)
[exit 0]
```

### `git diff b7111c975c7c2abe46d2551a2980ba993c8d98ca -- PLAN.md`
```
diff --git a/PLAN.md b/PLAN.md
index ec7ba73..edc96f3 100644
--- a/PLAN.md
+++ b/PLAN.md
@@ -10,6 +10,7 @@ Scope (frozen): harden the auth service — reliable token refresh, durable sess
 |---|---|---|---|
 | W1 | Phase 1 — Token refresh | S (dispatched session) | implementation wave — default |
 | W2 | Phase 2 — Session store migration | S (dispatched session) | implementation wave — default |
+| W3 | Phase 3 — Auth middleware | S (dispatched session) | implementation wave — default |
 
 **Lead context budget:** lead holds ≥50% of its window for decisions; succession point = end of each wave (recycle after harvest).
 
@@ -17,12 +18,14 @@ Scope (frozen): harden the auth service — reliable token refresh, durable sess
 - lead — owns PLAN.md, merges, gates
 - wave-1 session — `src/auth/refresh.ts`, `src/auth/token.ts`
 - wave-2 session — `src/session/store.ts`, `src/session/redis.ts`
+- wave-3 session — `src/middleware/auth.ts` (new), `src/auth.ts`, `src/http.ts`, `src/routes.ts`
 
 **Worktrees / branches:**
 - W1: `.worktrees/wt-token-refresh` on `feat/token-refresh`
 - W2: `.worktrees/wt-session-store` on `feat/session-store`
+- W3: `.worktrees/wt-auth-middleware` on `feat/auth-middleware`
 
-**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id).
+**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id). W3 has no blockedBy: it only calls the frozen `SessionStore` interface and its files are disjoint from W2's, so it can run in parallel with W2.
 
 ## Phase 1 — Token refresh (DONE 2026-09-01)
 
@@ -47,3 +50,29 @@ Move sessions from the in-process `Map` to Redis so sessions survive deploys and
 Why: in-memory sessions are lost on every deploy, logging out every user; and with 3 API nodes behind the load balancer a user bounced to another node appears logged out.
 
 **Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.
+
+## Phase 3 — Auth middleware (PLANNED)
+
+Move the auth checks that every handler repeats inline into one middleware, so request authorization is enforced in one place and a new route cannot forget it.
+
+Current state:
+- `src/auth.ts:6-19`, `:21-35`, `:37-55` — `getProfile`, `updateProfile` and `deleteAccount` each repeat the same block: read `req.cookies["sid"]` → 401 `unauthenticated` if missing → `sessionStore.get` → 401 `session expired` if missing or `expiresAt < Date.now()`.
+- `src/auth.ts:17`, `:32` — `getProfile` and `updateProfile` call `sessionStore.touch(sid)`; `deleteAccount` does not (it destroys the session at `:52`).
+- `src/auth.ts:48-51` — `deleteAccount` alone adds a role check: 403 `forbidden` unless `session.role === "owner"`.
+- `src/http.ts:10-16` — `Router` stores bare `Handler`s and has no middleware hook; `Request` (`:2-5`) has no `session` field.
+
+Changes:
+- New `src/middleware/auth.ts` — `requireAuth(handler, opts?: { role?: string; touch?: boolean })` returns a `Handler` that runs the sid → session → expiry checks, then the optional role check, then `touch` (default `true`), then calls `handler` with the session attached to `req`.
+- `src/http.ts:2-5` — add `session?: Session` to `Request`, or an `AuthedRequest` type that extends it with a required `session`; the typed variant is preferred so handlers need no null check.
+- `src/auth.ts` — strip the inline checks; handlers read `req.session`. `deleteAccount` keeps its `sessionStore.destroy(sid)` call.
+- `src/routes.ts:6-8` — wrap each route: `requireAuth(getProfile)`, `requireAuth(updateProfile)`, `requireAuth(deleteAccount, { role: "owner", touch: false })`.
+
+Constraints:
+- Behaviour-preserving: same status codes, same error bodies (`unauthenticated`, `session expired`, `forbidden`), same touch/no-touch per route. Any change to expiry semantics (e.g. adding the 5s skew leeway from Phase 1) is a separate decision, not part of this phase.
+- Use only the frozen `SessionStore` methods (`get`, `touch`, `destroy`) so the phase is unaffected by Phase 2's switch to Redis.
+
+Trade-off: a per-route wrapper was chosen over adding a middleware chain to `Router`. It is explicit at each route and needs no change to `Router`; the cost is that a route registered without `requireAuth` is unprotected. If routes multiply, move to a router-level default-deny with an explicit `public()` opt-out.
+
+Why: three copies of the same check drift apart (only `deleteAccount` skips `touch`, and only it checks the role), and the "consistent request authorization" goal in the frozen scope needs a single enforcement point.
+
+**Done when:** each of the three routes returns the same status and body as before for no cookie, an unknown sid, an expired session and a valid session, plus a non-owner calling `DELETE /me`; and `src/auth.ts` has no remaining reference to `req.cookies`.
[exit 0]
```

### `git diff --stat b7111c975c7c2abe46d2551a2980ba993c8d98ca -- src`
```

[exit 0]
```

### `grep -n '^## ' PLAN.md`
```
5:## Phase 0 — Orchestration
30:## Phase 1 — Token refresh (DONE 2026-09-01)
41:## Phase 2 — Session store migration (IN PROGRESS)
54:## Phase 3 — Auth middleware (PLANNED)
[exit 0]
```

### `git diff b7111c975c7c2abe46d2551a2980ba993c8d98ca -- PLAN.md | grep '^-[^-]' | wc -l | tr -d ' '; echo '(^ count of pre-existing PLAN.md lines removed or changed)'`
```
1
(^ count of pre-existing PLAN.md lines removed or changed)
[exit 0]
```

### `git status --short --untracked-files=all | grep -v '^?? .claude/' || echo '(clean apart from harness files)'`
```
(clean apart from harness files)
[exit 0]
```
