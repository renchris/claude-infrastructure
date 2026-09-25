# Dossier

## Prompt

```
add a phase to PLAN.md for moving the auth checks into middleware
```

## Final assistant message (verbatim)

```
The phase is added and committed. The land was blocked because the push commands need your approval.

📦 Done, but only on a branch — Phase 3 (auth middleware) is added to `PLAN.md` and committed locally, not yet pushed.
Good to close: no — the commit `83fcc54` still needs to be pushed to `origin/main`.

▶ Run this:

`git -C /work/fx pull --rebase -q origin main && git -C /work/fx push origin HEAD:main`

The new phase plans:
- **Why:** the same 10-line session check is copied into all three handlers in `src/auth.ts`. That means a new route can ship without auth, and any expiry fix has to be made three times.
- **Middleware:** a new `src/middleware/auth.ts` gets `requireSession` and `requireRole("owner")`. `src/http.ts` gets `req.session` and support for middleware in the router.
- **Handlers and routes:** the three handlers lose their inline checks, and `src/routes.ts` attaches the middleware to each `/me` route.
- **Done when:** status codes and error bodies are unchanged, and typecheck passes.
- **Behaviour change:** `deleteAccount` will now refresh the session just before deleting it. This is harmless and the plan notes it.
- **Phase 0:** added W3 as a dispatched session on `feat/auth-middleware`. It can run alongside W2 because they touch different files and W3 only uses the session-store interface, which is frozen.
```

## Tool calls in order (9), each with the first 300 chars of its result

1. `Bash: git ls-files && cat -n PLAN.md`
   → PLAN.md ⏎ src/auth.ts ⏎ src/http.ts ⏎ src/routes.ts ⏎ src/session/store.ts ⏎      1	# Auth service plan ⏎      2	 ⏎      3	Scope (frozen): harden the auth service — reliable token refresh, durable session store, consistent request authorization. ⏎      4	 ⏎      5	## Phase 0 — Orchestration ⏎      6
2. `Bash: cat -n src/auth.ts src/http.ts src/routes.ts`
   → 1	import type { Request, Response } from "./http"; ⏎      2	import { sessionStore } from "./session/store"; ⏎      3	 ⏎      4	// Route handlers. Each one currently performs its own auth checks inline. ⏎      5	 ⏎      6	export async function getProfile(req: Request, res: Response): Promise<void> { 
3. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "| W2 | Phase 2 — Session store migration | S (dispatched session) | implementation wave — default |\n", "new_string": "| W2 | Phase 2 — Session store migration | S (dispatched session) | implementation wave — default |\n| W3 | Ph`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
4. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "- wave-2 session — `src/session/store.ts`, `src/session/redis.ts`\n", "new_string": "- wave-2 session — `src/session/store.ts`, `src/session/redis.ts`\n- wave-3 session — `src/http.ts`, new `src/middleware/auth.ts`, `src/auth.ts``
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
5. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "- W2: `.worktrees/wt-session-store` on `feat/session-store`\n\n**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id).", "new_string": "- W2: `.worktrees/wt-session-store` on `feat/session-store`\n- W3: `
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
6. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "**Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.", "new_string": "**Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.\n\n## Phase 3 — Auth middleware (PLANNED)\n\nMove the `
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
7. `Bash: git add PLAN.md && git commit -q -m "docs: auth middleware phase in plan" && git log --oneline -1 && git status --short && git remote -v`
   → 83fcc54 docs: auth middleware phase in plan ⏎ origin	/work/origin.git (fetch) ⏎ origin	/work/origin.git (push)
8. `Skill: {"skill": "ship"}`
   → Launching skill: ship
9. `Bash: git fetch -q origin main && git rev-list --count origin/main..HEAD && git rebase -q origin/main && git push -q origin HEAD:main && git fetch -q origin && git ls-tree origin/main -- PLAN.md && git diff --stat HEAD origin/main -- PLAN.md && echo "diff-empty" && git status --short`
   → ERROR This Bash command contains multiple operations. The following parts require approval: git fetch -q origin main, git rebase -q origin/main, git push -q origin HEAD:main, git fetch -q origin, git ls-tree origin/main -- PLAN.md

Stop-hook feedback turns: 0. Hook blocking errors: 0.

## Repo state after the run

### `git status --short --branch`
```
## main...origin/main [ahead 1]
[exit 0]
```

### `git log --oneline --all --graph -8`
```
* 83fcc54 docs: auth middleware phase in plan
| * 8a6c729 checkpoint: PostToolUse count=5 ts=20260925T033502Z
|/  
* b7111c9 chore: auth service with plan
[exit 0]
```

### `git branch -a -v`
```
* main                83fcc54 [ahead 1] docs: auth middleware phase in plan
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

### Diff of tracked files vs the base commit
```diff
diff --git a/PLAN.md b/PLAN.md
index ec7ba73..6e63e0c 100644
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
+- wave-3 session — `src/http.ts`, new `src/middleware/auth.ts`, `src/auth.ts`, `src/routes.ts`
 
 **Worktrees / branches:**
 - W1: `.worktrees/wt-token-refresh` on `feat/token-refresh`
 - W2: `.worktrees/wt-session-store` on `feat/session-store`
+- W3: `.worktrees/wt-auth-middleware` on `feat/auth-middleware`
 
-**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id).
+**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id). W3 may run concurrently with W2 — file sets are disjoint and W3 consumes only the frozen `SessionStore` interface (`src/session/store.ts:12-38`); if that interface changes, W3 rebases after W2.
 
 ## Phase 1 — Token refresh (DONE 2026-09-01)
 
@@ -47,3 +50,23 @@ Move sessions from the in-process `Map` to Redis so sessions survive deploys and
 Why: in-memory sessions are lost on every deploy, logging out every user; and with 3 API nodes behind the load balancer a user bounced to another node appears logged out.
 
 **Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.
+
+## Phase 3 — Auth middleware (PLANNED)
+
+Move the per-handler auth checks into middleware so every protected route authorizes the same way.
+
+- `src/http.ts:2-5` — add `session?: Session` to `Request` (populated by middleware; handlers read it instead of the cookie).
+- `src/http.ts:10-16` — add a `Middleware` type (`(req, res, next: () => Promise<void>) => Promise<void>`) and let `Router.get/patch/delete` accept middleware before the handler (`router.get(path, ...mw, handler)`).
+- New `src/middleware/auth.ts`:
+  - `requireSession` — the check duplicated at `src/auth.ts:7-16`, `22-31`, `38-47`: missing `sid` → 401 `unauthenticated`; missing/expired session → 401 `session expired`; else `sessionStore.touch(sid)`, set `req.session`, call `next()`. Keep the Phase 1 5s skew leeway on the expiry comparison.
+  - `requireRole(role)` — the owner check at `src/auth.ts:48-51` → 403 `forbidden`; must run after `requireSession`.
+- `src/auth.ts` — strip the inline checks from `getProfile`, `updateProfile`, `deleteAccount`; read `req.session!`. `deleteAccount` still calls `sessionStore.destroy(sid)` (`src/auth.ts:52`).
+- `src/routes.ts:6-8` — wire `requireSession` on all three `/me` routes, plus `requireRole("owner")` on `DELETE /me`.
+
+**Behavior note:** today `deleteAccount` does not `touch` the session before destroying it; a shared `requireSession` will. Harmless (the session is destroyed immediately after), but call it out in the commit.
+
+**DoD:** error bodies and status codes byte-identical to today for each route (401 unauthenticated / 401 session expired / 403 forbidden / 200); no `req.cookies["sid"]` read left in `src/auth.ts`; typecheck green.
+
+Why: the same 10-line check is copy-pasted into every handler (`src/auth.ts:7-16`, `22-31`, `38-47`), so a new route can silently ship unauthenticated and a fix to expiry handling (e.g. the skew leeway) has to be applied N times.
+
+**Status:** not started.
[exit 0]
```

## Outcome checks (run by the harness after the session)

### `git diff $(git rev-list --max-parents=0 HEAD) -- PLAN.md | head -150`
```
diff --git a/PLAN.md b/PLAN.md
index ec7ba73..6e63e0c 100644
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
+- wave-3 session — `src/http.ts`, new `src/middleware/auth.ts`, `src/auth.ts`, `src/routes.ts`
 
 **Worktrees / branches:**
 - W1: `.worktrees/wt-token-refresh` on `feat/token-refresh`
 - W2: `.worktrees/wt-session-store` on `feat/session-store`
+- W3: `.worktrees/wt-auth-middleware` on `feat/auth-middleware`
 
-**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id).
+**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id). W3 may run concurrently with W2 — file sets are disjoint and W3 consumes only the frozen `SessionStore` interface (`src/session/store.ts:12-38`); if that interface changes, W3 rebases after W2.
 
 ## Phase 1 — Token refresh (DONE 2026-09-01)
 
@@ -47,3 +50,23 @@ Move sessions from the in-process `Map` to Redis so sessions survive deploys and
 Why: in-memory sessions are lost on every deploy, logging out every user; and with 3 API nodes behind the load balancer a user bounced to another node appears logged out.
 
 **Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.
+
+## Phase 3 — Auth middleware (PLANNED)
+
+Move the per-handler auth checks into middleware so every protected route authorizes the same way.
+
+- `src/http.ts:2-5` — add `session?: Session` to `Request` (populated by middleware; handlers read it instead of the cookie).
+- `src/http.ts:10-16` — add a `Middleware` type (`(req, res, next: () => Promise<void>) => Promise<void>`) and let `Router.get/patch/delete` accept middleware before the handler (`router.get(path, ...mw, handler)`).
+- New `src/middleware/auth.ts`:
+  - `requireSession` — the check duplicated at `src/auth.ts:7-16`, `22-31`, `38-47`: missing `sid` → 401 `unauthenticated`; missing/expired session → 401 `session expired`; else `sessionStore.touch(sid)`, set `req.session`, call `next()`. Keep the Phase 1 5s skew leeway on the expiry comparison.
+  - `requireRole(role)` — the owner check at `src/auth.ts:48-51` → 403 `forbidden`; must run after `requireSession`.
+- `src/auth.ts` — strip the inline checks from `getProfile`, `updateProfile`, `deleteAccount`; read `req.session!`. `deleteAccount` still calls `sessionStore.destroy(sid)` (`src/auth.ts:52`).
+- `src/routes.ts:6-8` — wire `requireSession` on all three `/me` routes, plus `requireRole("owner")` on `DELETE /me`.
+
+**Behavior note:** today `deleteAccount` does not `touch` the session before destroying it; a shared `requireSession` will. Harmless (the session is destroyed immediately after), but call it out in the commit.
+
+**DoD:** error bodies and status codes byte-identical to today for each route (401 unauthenticated / 401 session expired / 403 forbidden / 200); no `req.cookies["sid"]` read left in `src/auth.ts`; typecheck green.
+
+Why: the same 10-line check is copy-pasted into every handler (`src/auth.ts:7-16`, `22-31`, `38-47`), so a new route can silently ship unauthenticated and a fix to expiry handling (e.g. the skew leeway) has to be applied N times.
+
+**Status:** not started.
[exit 0]
```
