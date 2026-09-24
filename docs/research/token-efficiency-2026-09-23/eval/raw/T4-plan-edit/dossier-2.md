# Dossier run-2

## Prompt

```
add a phase to PLAN.md for moving the auth checks into middleware
```

## Final assistant message (verbatim)

```
✅ Landed on trunk: `PLAN.md` now has Phase 3, "Auth middleware".
Good to close: yes — nothing of mine is open; follow-on: none

The new phase covers:
- **The change:** a new `src/middleware/auth.ts` with two wrappers. `requireSession` checks the cookie, looks up the session, checks expiry and refreshes it. `requireRole` checks the user's role. Each route in `src/routes.ts` is wrapped with them, and `Request` in `src/http.ts` gets a `session` field. This removes the three copied check blocks in `src/auth.ts:6-55`.
- **Decisions and reasons:** it wraps each handler instead of adding a middleware chain, because `Router` has none. The account-delete route now refreshes the session once right before destroying it, which is harmless. No status codes or error messages change.
- **Ordering:** it waits for the Redis session store migration (Phase 2). `src/session/store.ts:8-9` says callers in `src/auth.ts` can't change until that migration finishes.
- **Orchestration:** I added it to Phase 0 as its own wave, run as a dispatched session with its own worktree and branch. Its end state can be checked by a command: `grep -cE 'cookies\[|expiresAt' src/auth.ts` prints `0`, and the new tests in `src/middleware/auth.test.ts` pass. One catch: the repo has no test runner yet.

The commit is `5745794`. I checked by content that `origin/main` matches it, and the working tree is clean. No lint or test checks ran because the repo has no `package.json`.
```

## Tool calls in order (15)

1. `Skill: {"skill": "plan-conventions"}`
2. `Bash: git ls-files && echo ---- && cat -n PLAN.md`
3. `Bash: for f in src/auth.ts src/http.ts src/routes.ts; do echo "==== $f"; cat -n $f; done; echo ====; wc -l src/session/store.ts; ls package.json 2>/dev/null`
4. `Bash: grep -n "Session\b\|interface\|export" src/session/store.ts | head -20`
5. `Read: {"file_path": "/private/tmp/tokeff-eval/tasks/T4-plan-edit/fx-2/PLAN.md"}`
6. `Edit: {"replace_all": false, "file_path": "/private/tmp/tokeff-eval/tasks/T4-plan-edit/fx-2/PLAN.md", "old_string": "| W2 | Phase 2 — Session store migration | S (dispatched session) | implementation wave —`
7. `Edit: {"replace_all": false, "file_path": "/private/tmp/tokeff-eval/tasks/T4-plan-edit/fx-2/PLAN.md", "old_string": "- wave-2 session — `src/session/store.ts`, `src/session/redis.ts`\n", "new_string": "- wa`
8. `Edit: {"replace_all": false, "file_path": "/private/tmp/tokeff-eval/tasks/T4-plan-edit/fx-2/PLAN.md", "old_string": "- W2: `.worktrees/wt-session-store` on `feat/session-store`\n\n**Dependencies:** W2 block`
9. `Edit: {"replace_all": false, "file_path": "/private/tmp/tokeff-eval/tasks/T4-plan-edit/fx-2/PLAN.md", "old_string": "**Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.\n", "new_s`
10. `Bash: git diff --name-only && git add PLAN.md && git commit -q -m "docs: auth middleware phase in plan" && git log --oneline -1 && git status --short && git remote -v; ls scripts/wrap-ledger.sh 2>/dev/null `
11. `Skill: {"skill": "ship"}`
12. `Bash: git fetch -q origin main && echo "ahead: $(git rev-list --count origin/main..HEAD)" && git branch -f ship/backup-$(git rev-parse --short HEAD) HEAD && git rebase -q origin/main && git push -q origin H`
13. `Bash: git fetch -q origin main && git rev-list --count origin/main..HEAD && git branch -f ship/backup-5745794 HEAD && git rebase -q origin/main && git push -q origin HEAD:main && git fetch -q origin main &&`
14. `Bash: git -C /private/tmp/tokeff-eval/tasks/T4-plan-edit/fx-2 push origin HEAD:main`
15. `Bash: git -C /private/tmp/tokeff-eval/tasks/T4-plan-edit/fx-2 diff --stat origin/main HEAD -- PLAN.md; git -C /private/tmp/tokeff-eval/tasks/T4-plan-edit/fx-2 status -sb`

## State after the run

### `git status --short --branch`
```
## main...origin/main
[exit 0]
```

### `git log --oneline -5`
```
5745794 docs: auth middleware phase in plan
b7111c9 chore: auth service with plan
[exit 0]
```

### `git show --stat HEAD`
```
commit 5745794f363c262bec1cdbe464e69b78dba3d779
Author: Eval Fixture <fixture@example.invalid>
Date:   Wed Sep 23 21:34:21 2026 -0500

    docs: auth middleware phase in plan

 PLAN.md | 31 ++++++++++++++++++++++++++++++-
 1 file changed, 30 insertions(+), 1 deletion(-)
[exit 0]
```

### `git log --oneline origin/main -3`
```
5745794 docs: auth middleware phase in plan
b7111c9 chore: auth service with plan
[exit 0]
```

### `git --git-dir=$(git remote get-url origin) log --oneline -3 main`
```
5745794 docs: auth middleware phase in plan
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
- wave-3 session — `src/middleware/auth.ts` (new), `src/middleware/auth.test.ts` (new), `src/auth.ts`, `src/http.ts`, `src/routes.ts`

**Worktrees / branches:**
- W1: `.worktrees/wt-token-refresh` on `feat/token-refresh`
- W2: `.worktrees/wt-session-store` on `feat/session-store`
- W3: `.worktrees/wt-auth-middleware` on `feat/auth-middleware`

**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id). W3 blockedBy W2 (`src/session/store.ts:8-9` freezes the callers in `src/auth.ts` until the Redis cut-over; changing them mid-dual-write would muddy the comparison between the two stores).

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

Move the session and role checks out of the route handlers and into middleware, so every route authorizes the same way and new routes cannot forget a check.

Current state: each handler in `src/auth.ts` repeats the same block. `getProfile` (6-19), `updateProfile` (21-35) and `deleteAccount` (37-55) each read `req.cookies["sid"]`, return 401 `unauthenticated` when it is missing, look it up in `sessionStore`, and return 401 `session expired` when the session is missing or `expiresAt < Date.now()`. `getProfile` and `updateProfile` then call `sessionStore.touch`. `deleteAccount` also returns 403 `forbidden` unless `session.role === "owner"`.

- `src/http.ts:2-5` — add `session?: Session` to `Request` (import the type from `src/session/store.ts:13`) so middleware can pass the resolved session to the handler.
- New `src/middleware/auth.ts`:
  - `requireSession(h: Handler): Handler` runs the cookie, lookup, expiry and touch steps, sets `req.session`, then calls `h`. It keeps the current status codes and error bodies exactly.
  - `requireRole(role, h): Handler` wraps a handler that already has a session and returns 403 `forbidden` on a role mismatch.
  - Both return a `Handler`, so they compose as plain functions and `Router` (`src/http.ts:11-16`) needs no middleware chain.
- `src/auth.ts:6-55` — remove the inline checks. Handlers read `req.session!`, and `src/auth.ts` no longer imports `sessionStore` except for `deleteAccount`'s `destroy` call.
- `src/routes.ts:6-8` — wrap each route: `requireSession(getProfile)`, `requireSession(updateProfile)`, `requireSession(requireRole("owner", deleteAccount))`.
- New `src/middleware/auth.test.ts` — cover no cookie → 401, unknown sid → 401, expired → 401, valid → handler runs and `touch` is called, non-owner on DELETE → 403.

Decisions:
- Use handler wrappers, not a `Router.use()` chain. The router has no middleware concept, and wrapping each route keeps the protection visible where the route is registered.
- The middleware always calls `touch`, so `deleteAccount` now gets one extra `touch` right before `destroy`. This is harmless, and a single code path is worth more than keeping the old call order.
- Behavior stays the same, and the expiry comparison stays `expiresAt < Date.now()`. Phase 1's 5s clock-skew leeway covered token expiry, not sessions. If sessions need a leeway, it belongs in `requireSession` as a separate change.

Why: three copies of the same check have already drifted (only one handler checks the role, and one skips `touch`). The next route added would have to copy the block by hand, and a forgotten copy is an unauthenticated endpoint.

**Size:** one unit, about 5 files. It is below the 40–150K band, which is acceptable because the work is one indivisible refactor.

**Goal (W3):** no route handler in `src/auth.ts` reads `req.cookies` or checks `expiresAt`, and the middleware tests pass. Proven when `grep -cE 'cookies\[|expiresAt' src/auth.ts` prints `0` and the test run prints 0 failures. Do not change any status code, error body or `SessionStore` method.
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
index ec7ba73..a1237f0 100644
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
+- wave-3 session — `src/middleware/auth.ts` (new), `src/middleware/auth.test.ts` (new), `src/auth.ts`, `src/http.ts`, `src/routes.ts`
 
 **Worktrees / branches:**
 - W1: `.worktrees/wt-token-refresh` on `feat/token-refresh`
 - W2: `.worktrees/wt-session-store` on `feat/session-store`
+- W3: `.worktrees/wt-auth-middleware` on `feat/auth-middleware`
 
-**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id).
+**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id). W3 blockedBy W2 (`src/session/store.ts:8-9` freezes the callers in `src/auth.ts` until the Redis cut-over; changing them mid-dual-write would muddy the comparison between the two stores).
 
 ## Phase 1 — Token refresh (DONE 2026-09-01)
 
@@ -47,3 +50,29 @@ Move sessions from the in-process `Map` to Redis so sessions survive deploys and
 Why: in-memory sessions are lost on every deploy, logging out every user; and with 3 API nodes behind the load balancer a user bounced to another node appears logged out.
 
 **Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.
+
+## Phase 3 — Auth middleware (PLANNED)
+
+Move the session and role checks out of the route handlers and into middleware, so every route authorizes the same way and new routes cannot forget a check.
+
+Current state: each handler in `src/auth.ts` repeats the same block. `getProfile` (6-19), `updateProfile` (21-35) and `deleteAccount` (37-55) each read `req.cookies["sid"]`, return 401 `unauthenticated` when it is missing, look it up in `sessionStore`, and return 401 `session expired` when the session is missing or `expiresAt < Date.now()`. `getProfile` and `updateProfile` then call `sessionStore.touch`. `deleteAccount` also returns 403 `forbidden` unless `session.role === "owner"`.
+
+- `src/http.ts:2-5` — add `session?: Session` to `Request` (import the type from `src/session/store.ts:13`) so middleware can pass the resolved session to the handler.
+- New `src/middleware/auth.ts`:
+  - `requireSession(h: Handler): Handler` runs the cookie, lookup, expiry and touch steps, sets `req.session`, then calls `h`. It keeps the current status codes and error bodies exactly.
+  - `requireRole(role, h): Handler` wraps a handler that already has a session and returns 403 `forbidden` on a role mismatch.
+  - Both return a `Handler`, so they compose as plain functions and `Router` (`src/http.ts:11-16`) needs no middleware chain.
+- `src/auth.ts:6-55` — remove the inline checks. Handlers read `req.session!`, and `src/auth.ts` no longer imports `sessionStore` except for `deleteAccount`'s `destroy` call.
+- `src/routes.ts:6-8` — wrap each route: `requireSession(getProfile)`, `requireSession(updateProfile)`, `requireSession(requireRole("owner", deleteAccount))`.
+- New `src/middleware/auth.test.ts` — cover no cookie → 401, unknown sid → 401, expired → 401, valid → handler runs and `touch` is called, non-owner on DELETE → 403.
+
+Decisions:
+- Use handler wrappers, not a `Router.use()` chain. The router has no middleware concept, and wrapping each route keeps the protection visible where the route is registered.
+- The middleware always calls `touch`, so `deleteAccount` now gets one extra `touch` right before `destroy`. This is harmless, and a single code path is worth more than keeping the old call order.
+- Behavior stays the same, and the expiry comparison stays `expiresAt < Date.now()`. Phase 1's 5s clock-skew leeway covered token expiry, not sessions. If sessions need a leeway, it belongs in `requireSession` as a separate change.
+
+Why: three copies of the same check have already drifted (only one handler checks the role, and one skips `touch`). The next route added would have to copy the block by hand, and a forgotten copy is an unauthenticated endpoint.
+
+**Size:** one unit, about 5 files. It is below the 40–150K band, which is acceptable because the work is one indivisible refactor.
+
+**Goal (W3):** no route handler in `src/auth.ts` reads `req.cookies` or checks `expiresAt`, and the middleware tests pass. Proven when `grep -cE 'cookies\[|expiresAt' src/auth.ts` prints `0` and the test run prints 0 failures. Do not change any status code, error body or `SessionStore` method.
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
