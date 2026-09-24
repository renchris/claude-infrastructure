# Dossier

## Prompt

```
add a phase to PLAN.md for moving the auth checks into middleware
```

## Final assistant message (verbatim)

```
I added Phase 3 (auth middleware) to `PLAN.md` and committed it locally as `2ad7258`, but it isn't on the remote yet. The push step needs your permission.

📦 Done, on a branch only — Phase 3 is committed locally but not pushed to trunk yet.
Good to close: no — the push to `origin/main` is waiting for your permission.

▶ Run this:

`git -C /work/fx pull --rebase -q origin main && git -C /work/fx push origin HEAD:main`

**What the new phase says**, based on the current code:
- **The problem:** the same session check is copy-pasted into all three handlers (`src/auth.ts:7-17`, `22-32`, `38-47`), plus an owner-only check at `48-51`.
- **The plan:** add `Request.session` and support for middleware on each route in `src/http.ts`. A new `src/middleware/auth.ts` provides two checks: one that requires a logged-in session, and `requireRole("owner")`. Remove the checks from the handlers and wire the middleware in `src/routes.ts:6-8`.
- **No behaviour change:** the 401 and 403 status codes and response bodies stay exactly the same. The one difference is that `DELETE /me` now refreshes the session before deleting it, which is harmless.
- **Phase 0 updated:** a new W3 row as a dispatched session, plus its owner, its worktree `feat/auth-middleware`, and its dependencies. It shares no files with Phase 2, so the two can run at the same time.
- **Risk found while reading the code:** `RedisStore.touch` doesn't update `expiresAt` yet (the Phase 2 TODO at `src/session/store.ts:108-111`). If that isn't fixed before the switch to Redis, users will be logged out 30 minutes after logging in no matter how active they are. The plan records this under Phase 2's interaction note.
```

## Tool calls in order (9), each with the first 300 chars of its result

1. `Bash: git ls-files && cat -n PLAN.md`
   → PLAN.md ⏎ src/auth.ts ⏎ src/http.ts ⏎ src/routes.ts ⏎ src/session/store.ts ⏎      1	# Auth service plan ⏎      2	 ⏎      3	Scope (frozen): harden the auth service — reliable token refresh, durable session store, consistent request authorization. ⏎      4	 ⏎      5	## Phase 0 — Orchestration ⏎      6
2. `Bash: for f in src/*.ts src/session/store.ts; do echo "=== $f"; cat -n "$f"; done`
   → === src/auth.ts ⏎      1	import type { Request, Response } from "./http"; ⏎      2	import { sessionStore } from "./session/store"; ⏎      3	 ⏎      4	// Route handlers. Each one currently performs its own auth checks inline. ⏎      5	 ⏎      6	export async function getProfile(req: Request, res: Resp
3. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "| W2 | Phase 2 — Session store migration | S (dispatched session) | implementation wave — default |", "new_string": "| W2 | Phase 2 — Session store migration | S (dispatched session) | implementation wave — default |\n| W3 | Phas`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
4. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "- wave-2 session — `src/session/store.ts`, `src/session/redis.ts`\n", "new_string": "- wave-2 session — `src/session/store.ts`, `src/session/redis.ts`\n- wave-3 session — `src/http.ts`, `src/middleware/auth.ts` (new), `src/auth.t`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
5. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "- W2: `.worktrees/wt-session-store` on `feat/session-store`\n\n**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id).", "new_string": "- W2: `.worktrees/wt-session-store` on `feat/session-store`\n- W3: `
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
6. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "**Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.", "new_string": "**Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.\n\n## Phase 3 — Auth middleware (NOT STARTED)\n\nMove `
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
7. `Bash: git diff --name-only && git add PLAN.md && git commit -q -m "docs: plan phase 3 — auth middleware" && git log --oneline -1 && git remote -v | head -2`
   → PLAN.md ⏎ 2ad7258 docs: plan phase 3 — auth middleware ⏎ origin	/work/origin.git (fetch) ⏎ origin	/work/origin.git (push)
8. `Skill: {"skill": "ship"}`
   → Launching skill: ship
9. `Bash: git fetch -q origin main && git branch -f ship/backup-2ad7258 HEAD && git rebase -q origin/main && git push -q origin HEAD:main && git fetch -q origin main && git ls-tree origin/main -- PLAN.md && git diff --stat HEAD origin/main -- PLAN.md && echo "diff-empty" && git branch -D ship/backup-2ad7258 &`
   → ERROR This Bash command contains multiple operations. The following parts require approval: git fetch -q origin main, git rebase -q origin/main, git push -q origin HEAD:main, git ls-tree origin/main -- PLAN.md

Stop-hook feedback turns: 0. Hook blocking errors: 0.

## Repo state after the run

### `git status --short --branch`
```
## main...origin/main [ahead 1]
[exit 0]
```

### `git log --oneline --all --graph -8`
```
* 2ad7258 docs: plan phase 3 — auth middleware
| * 4430513 checkpoint: PostToolUse count=5 ts=20260924T155254Z
|/  
* b7111c9 chore: auth service with plan
[exit 0]
```

### `git branch -a -v`
```
* main                2ad7258 [ahead 1] docs: plan phase 3 — auth middleware
  remotes/origin/main b7111c9 chore: auth service with plan
[exit 0]
```

### `git ls-remote origin 2>/dev/null || echo '(no origin)'`
```
b7111c975c7c2abe46d2551a2980ba993c8d98ca	refs/heads/main
[exit 0]
```

### `git diff $(git rev-list --max-parents=0 HEAD 2>/dev/null | tail -1) --stat -- . ':!.claude' 2>/dev/null`
```
 PLAN.md | 25 ++++++++++++++++++++++++-
 1 file changed, 24 insertions(+), 1 deletion(-)
[exit 0]
```

### `git ls-files --others --exclude-standard | grep -v '^.claude' || echo '(no untracked files)'`
```
(no untracked files)
[exit 0]
```

### Diff of tracked files vs the initial commit
```diff
diff --git a/PLAN.md b/PLAN.md
index ec7ba73..0cc9f85 100644
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
+- wave-3 session — `src/http.ts`, `src/middleware/auth.ts` (new), `src/auth.ts`, `src/routes.ts`
 
 **Worktrees / branches:**
 - W1: `.worktrees/wt-token-refresh` on `feat/token-refresh`
 - W2: `.worktrees/wt-session-store` on `feat/session-store`
+- W3: `.worktrees/wt-auth-middleware` on `feat/auth-middleware`
 
-**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id).
+**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id). W3 has no file overlap with W2 and uses only the frozen `SessionStore` interface, so it may run in parallel with W2 — but see the Phase 3 note on `touch`/`expiresAt`.
 
 ## Phase 1 — Token refresh (DONE 2026-09-01)
 
@@ -47,3 +50,23 @@ Move sessions from the in-process `Map` to Redis so sessions survive deploys and
 Why: in-memory sessions are lost on every deploy, logging out every user; and with 3 API nodes behind the load balancer a user bounced to another node appears logged out.
 
 **Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.
+
+## Phase 3 — Auth middleware (NOT STARTED)
+
+Move the per-handler auth checks out of the route handlers into reusable middleware, so every route is authorized the same way and a new route cannot silently ship without a check.
+
+- `src/http.ts:2-5` — add `session?: Session` to `Request` (import `Session` from `./session/store`).
+- `src/http.ts:10-16` — add `type Middleware = (req, res, next: () => Promise<void>) => Promise<void>`; let `get`/`patch`/`delete` accept `...middleware` before the handler, run in order, and stop the chain when a middleware responds without calling `next`.
+- New `src/middleware/auth.ts`:
+  - `requireSession` — the block duplicated at `src/auth.ts:7-17`, `22-32`, `38-47`: read `sid` cookie → `sessionStore.get` → expiry check → `sessionStore.touch` → set `req.session` → `next()`.
+  - `requireRole(role)` — the owner check at `src/auth.ts:48-51`.
+- `src/auth.ts:6-55` — strip the inline checks; handlers read `req.session!`. `deleteAccount` keeps its `sessionStore.destroy(sid)`.
+- `src/routes.ts:6-8` — wire `requireSession` on all three routes, plus `requireRole("owner")` on `DELETE /me`.
+
+**Behavior must not change:** same status codes and bodies — `401 {error:"unauthenticated"}` (no cookie), `401 {error:"session expired"}` (missing/expired), `403 {error:"forbidden"}` (non-owner delete). One deliberate difference: `DELETE /me` now calls `touch` before `destroy` (it skipped `touch` before) — harmless, since the session is destroyed right after.
+
+**Interaction with Phase 2:** the middleware's expiry check reads `session.expiresAt`, which `RedisStore.touch` does not yet bump (`src/session/store.ts:108-111` TODO). The TODO has to land before the Redis cut-over, or sessions on Redis will expire 30 min after login no matter how active the user is. That bug belongs to Phase 2; this phase adds no new dependency on it.
+
+**Verification:** per route — no cookie, unknown sid, expired session, happy path; plus member vs owner on `DELETE /me`. Response bodies must match the pre-change handlers exactly.
+
+Why: the same 10-line check is copy-pasted into all three handlers today, so a new handler that leaves it out is unauthenticated by default. Scope (frozen) already names "consistent request authorization".
[exit 0]
```

## Outcome checks (run by the harness after the session)

### `git diff $(git rev-list --max-parents=0 HEAD) -- PLAN.md | head -150`
```
diff --git a/PLAN.md b/PLAN.md
index ec7ba73..0cc9f85 100644
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
+- wave-3 session — `src/http.ts`, `src/middleware/auth.ts` (new), `src/auth.ts`, `src/routes.ts`
 
 **Worktrees / branches:**
 - W1: `.worktrees/wt-token-refresh` on `feat/token-refresh`
 - W2: `.worktrees/wt-session-store` on `feat/session-store`
+- W3: `.worktrees/wt-auth-middleware` on `feat/auth-middleware`
 
-**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id).
+**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id). W3 has no file overlap with W2 and uses only the frozen `SessionStore` interface, so it may run in parallel with W2 — but see the Phase 3 note on `touch`/`expiresAt`.
 
 ## Phase 1 — Token refresh (DONE 2026-09-01)
 
@@ -47,3 +50,23 @@ Move sessions from the in-process `Map` to Redis so sessions survive deploys and
 Why: in-memory sessions are lost on every deploy, logging out every user; and with 3 API nodes behind the load balancer a user bounced to another node appears logged out.
 
 **Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.
+
+## Phase 3 — Auth middleware (NOT STARTED)
+
+Move the per-handler auth checks out of the route handlers into reusable middleware, so every route is authorized the same way and a new route cannot silently ship without a check.
+
+- `src/http.ts:2-5` — add `session?: Session` to `Request` (import `Session` from `./session/store`).
+- `src/http.ts:10-16` — add `type Middleware = (req, res, next: () => Promise<void>) => Promise<void>`; let `get`/`patch`/`delete` accept `...middleware` before the handler, run in order, and stop the chain when a middleware responds without calling `next`.
+- New `src/middleware/auth.ts`:
+  - `requireSession` — the block duplicated at `src/auth.ts:7-17`, `22-32`, `38-47`: read `sid` cookie → `sessionStore.get` → expiry check → `sessionStore.touch` → set `req.session` → `next()`.
+  - `requireRole(role)` — the owner check at `src/auth.ts:48-51`.
+- `src/auth.ts:6-55` — strip the inline checks; handlers read `req.session!`. `deleteAccount` keeps its `sessionStore.destroy(sid)`.
+- `src/routes.ts:6-8` — wire `requireSession` on all three routes, plus `requireRole("owner")` on `DELETE /me`.
+
+**Behavior must not change:** same status codes and bodies — `401 {error:"unauthenticated"}` (no cookie), `401 {error:"session expired"}` (missing/expired), `403 {error:"forbidden"}` (non-owner delete). One deliberate difference: `DELETE /me` now calls `touch` before `destroy` (it skipped `touch` before) — harmless, since the session is destroyed right after.
+
+**Interaction with Phase 2:** the middleware's expiry check reads `session.expiresAt`, which `RedisStore.touch` does not yet bump (`src/session/store.ts:108-111` TODO). The TODO has to land before the Redis cut-over, or sessions on Redis will expire 30 min after login no matter how active the user is. That bug belongs to Phase 2; this phase adds no new dependency on it.
+
+**Verification:** per route — no cookie, unknown sid, expired session, happy path; plus member vs owner on `DELETE /me`. Response bodies must match the pre-change handlers exactly.
+
+Why: the same 10-line check is copy-pasted into all three handlers today, so a new handler that leaves it out is unauthenticated by default. Scope (frozen) already names "consistent request authorization".
[exit 0]
```
