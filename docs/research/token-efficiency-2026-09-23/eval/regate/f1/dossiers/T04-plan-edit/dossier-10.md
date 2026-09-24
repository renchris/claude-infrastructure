# Dossier

## Prompt

```
add a phase to PLAN.md for moving the auth checks into middleware
```

## Final assistant message (verbatim)

```
This is deliberately parked: `0ab590d` is committed but not pushed. Pushing to origin needs your approval, and I won't retry it or work around that. I'm handing you the land command instead.

Good to close: no — `0ab590d` is only on the local branch until you run the push below.

▶ Run this:

`git -C /work/fx pull --rebase -q origin main && git -C /work/fx push origin HEAD:main`

`PLAN.md` now has Phase 3 (auth checks into middleware), which waits on the Phase 2 cutover. Details are in `git show 0ab590d`.
```

## Tool calls in order (10), each with the first 300 chars of its result

1. `Bash: git ls-files && cat -n PLAN.md`
   → PLAN.md ⏎ src/auth.ts ⏎ src/http.ts ⏎ src/routes.ts ⏎ src/session/store.ts ⏎      1	# Auth service plan ⏎      2	 ⏎      3	Scope (frozen): harden the auth service — reliable token refresh, durable session store, consistent request authorization. ⏎      4	 ⏎      5	## Phase 0 — Orchestration ⏎      6
2. `Bash: for f in src/auth.ts src/http.ts src/routes.ts src/session/store.ts; do echo "=== $f"; cat -n $f; done`
   → === src/auth.ts ⏎      1	import type { Request, Response } from "./http"; ⏎      2	import { sessionStore } from "./session/store"; ⏎      3	 ⏎      4	// Route handlers. Each one currently performs its own auth checks inline. ⏎      5	 ⏎      6	export async function getProfile(req: Request, res: Resp
3. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "| W2 | Phase 2 — Session store migration | S (dispatched session) | implementation wave — default |\n", "new_string": "| W2 | Phase 2 — Session store migration | S (dispatched session) | implementation wave — default |\n| W3 | Ph`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
4. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "- wave-2 session — `src/session/store.ts`, `src/session/redis.ts`\n", "new_string": "- wave-2 session — `src/session/store.ts`, `src/session/redis.ts`\n- wave-3 session — `src/middleware/auth.ts` (new), `src/http.ts`, `src/auth.t`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
5. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "- W2: `.worktrees/wt-session-store` on `feat/session-store`\n\n**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id).\n", "new_string": "- W2: `.worktrees/wt-session-store` on `feat/session-store`\n- W3`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
6. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "**Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.", "new_string": "**Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.\n\n## Phase 3 — Auth checks into middleware (NOT START`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
7. `Bash: git diff --name-only && git add PLAN.md && git commit -q -m "docs: plan phase 3 — auth checks into middleware" && git log --oneline -1 && git status --short && git remote -v`
   → PLAN.md ⏎ 0ab590d docs: plan phase 3 — auth checks into middleware ⏎ origin	/work/origin.git (fetch) ⏎ origin	/work/origin.git (push)
8. `Skill: {"skill": "ship"}`
   → Launching skill: ship
9. `Bash: T=$(git symbolic-ref --quiet refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@'); T=${T:-main}; echo "trunk=$T"; git fetch -q origin $T && git rev-list --count origin/$T..HEAD && git branch -f ship/backup-$(git rev-parse --short HEAD) HEAD && git rebase -q origin/$T && ls package.json 2>/dev`
   → ERROR Contains expansion
10. `Bash: git fetch -q origin main && git rev-list --count origin/main..HEAD && git branch -f ship/backup-0ab590d HEAD && git rebase -q origin/main && git push -q origin HEAD:main && git fetch -q origin main && git ls-tree origin/main -- PLAN.md && git diff --stat HEAD origin/main -- PLAN.md && echo content-v`
   → ERROR This Bash command contains multiple operations. The following parts require approval: git fetch -q origin main, git rebase -q origin/main, git push -q origin HEAD:main, git ls-tree origin/main -- PLAN.md

Stop-hook feedback turns: 1. Hook blocking errors: 1.

## Repo state after the run

### `git status --short --branch`
```
## main...origin/main [ahead 1]
[exit 0]
```

### `git log --oneline --all --graph -8`
```
* 0ab590d docs: plan phase 3 — auth checks into middleware
| * 697aa31 checkpoint: PostToolUse count=5 ts=20260924T184858Z
|/  
* b7111c9 chore: auth service with plan
[exit 0]
```

### `git branch -a -v`
```
* main                0ab590d [ahead 1] docs: plan phase 3 — auth checks into middleware
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
 PLAN.md | 23 ++++++++++++++++++++++-
 1 file changed, 22 insertions(+), 1 deletion(-)
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
index ec7ba73..be05011 100644
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
+- wave-3 session — `src/middleware/auth.ts` (new), `src/http.ts`, `src/auth.ts`, `src/routes.ts`
 
 **Worktrees / branches:**
 - W1: `.worktrees/wt-token-refresh` on `feat/token-refresh`
 - W2: `.worktrees/wt-session-store` on `feat/session-store`
+- W3: `.worktrees/wt-auth-middleware` on `feat/auth-middleware`
 
-**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id).
+**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id). W3 blockedBy W2 cutover — Phase 2 forbids caller changes in `src/auth.ts` during the migration, and W3 rewrites exactly those callers.
 
 ## Phase 1 — Token refresh (DONE 2026-09-01)
 
@@ -47,3 +50,21 @@ Move sessions from the in-process `Map` to Redis so sessions survive deploys and
 Why: in-memory sessions are lost on every deploy, logging out every user; and with 3 API nodes behind the load balancer a user bounced to another node appears logged out.
 
 **Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.
+
+## Phase 3 — Auth checks into middleware (NOT STARTED)
+
+Replace the auth checks copy-pasted into every handler with one middleware, so authorization is enforced by the router rather than remembered per route.
+
+- `src/auth.ts:6-51` — `getProfile`, `updateProfile`, `deleteAccount` each repeat the same block: read `sid` cookie → 401 `unauthenticated`; `sessionStore.get` + expiry check → 401 `session expired`; `touch` (`:17`, `:32`). Strip these blocks; handlers read `req.session` instead.
+- `src/auth.ts:48-51` — the `role !== "owner"` → 403 `forbidden` check moves to a `requireRole("owner")` middleware.
+- New `src/middleware/auth.ts` — `requireSession(handler)` and `requireRole(role)(handler)` wrappers returning a `Handler`. Preserve the exact status codes and error bodies (`unauthenticated` vs `session expired` vs `forbidden`) — clients may branch on them.
+- `src/http.ts:2-5` — add optional `session?: Session` to `Request` (populated only by `requireSession`).
+- `src/http.ts:11-16` — `Router` has no middleware hook; use handler composition (wrappers) rather than adding a `use()` chain, keeping `Router` unchanged.
+- `src/routes.ts:6-8` — wrap each registration: `/me` GET/PATCH in `requireSession`, DELETE in `requireSession` + `requireRole("owner")`.
+- `touch` semantics: today `deleteAccount` does not touch (it destroys). Middleware touches on every authenticated request except where the handler destroys the session — keep that behaviour, don't add a touch-then-destroy.
+
+Why: three handlers carry three copies of the same check, and any new route that forgets it is silently unauthenticated — the frozen scope's "consistent request authorization" is not achievable while the check is opt-in per handler.
+
+**Verification:** per-route tests for no cookie (401 `unauthenticated`), expired session (401 `session expired`), member on DELETE `/me` (403 `forbidden`), owner/valid paths unchanged; plus a test that every route in `buildRouter()` is wrapped.
+
+**Status:** not started; blocked on Phase 2 cutover.
[exit 0]
```

## Outcome checks (run by the harness after the session)

### `git diff $(git rev-list --max-parents=0 HEAD) -- PLAN.md | head -150`
```
diff --git a/PLAN.md b/PLAN.md
index ec7ba73..be05011 100644
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
+- wave-3 session — `src/middleware/auth.ts` (new), `src/http.ts`, `src/auth.ts`, `src/routes.ts`
 
 **Worktrees / branches:**
 - W1: `.worktrees/wt-token-refresh` on `feat/token-refresh`
 - W2: `.worktrees/wt-session-store` on `feat/session-store`
+- W3: `.worktrees/wt-auth-middleware` on `feat/auth-middleware`
 
-**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id).
+**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id). W3 blockedBy W2 cutover — Phase 2 forbids caller changes in `src/auth.ts` during the migration, and W3 rewrites exactly those callers.
 
 ## Phase 1 — Token refresh (DONE 2026-09-01)
 
@@ -47,3 +50,21 @@ Move sessions from the in-process `Map` to Redis so sessions survive deploys and
 Why: in-memory sessions are lost on every deploy, logging out every user; and with 3 API nodes behind the load balancer a user bounced to another node appears logged out.
 
 **Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.
+
+## Phase 3 — Auth checks into middleware (NOT STARTED)
+
+Replace the auth checks copy-pasted into every handler with one middleware, so authorization is enforced by the router rather than remembered per route.
+
+- `src/auth.ts:6-51` — `getProfile`, `updateProfile`, `deleteAccount` each repeat the same block: read `sid` cookie → 401 `unauthenticated`; `sessionStore.get` + expiry check → 401 `session expired`; `touch` (`:17`, `:32`). Strip these blocks; handlers read `req.session` instead.
+- `src/auth.ts:48-51` — the `role !== "owner"` → 403 `forbidden` check moves to a `requireRole("owner")` middleware.
+- New `src/middleware/auth.ts` — `requireSession(handler)` and `requireRole(role)(handler)` wrappers returning a `Handler`. Preserve the exact status codes and error bodies (`unauthenticated` vs `session expired` vs `forbidden`) — clients may branch on them.
+- `src/http.ts:2-5` — add optional `session?: Session` to `Request` (populated only by `requireSession`).
+- `src/http.ts:11-16` — `Router` has no middleware hook; use handler composition (wrappers) rather than adding a `use()` chain, keeping `Router` unchanged.
+- `src/routes.ts:6-8` — wrap each registration: `/me` GET/PATCH in `requireSession`, DELETE in `requireSession` + `requireRole("owner")`.
+- `touch` semantics: today `deleteAccount` does not touch (it destroys). Middleware touches on every authenticated request except where the handler destroys the session — keep that behaviour, don't add a touch-then-destroy.
+
+Why: three handlers carry three copies of the same check, and any new route that forgets it is silently unauthenticated — the frozen scope's "consistent request authorization" is not achievable while the check is opt-in per handler.
+
+**Verification:** per-route tests for no cookie (401 `unauthenticated`), expired session (401 `session expired`), member on DELETE `/me` (403 `forbidden`), owner/valid paths unchanged; plus a test that every route in `buildRouter()` is wrapped.
+
+**Status:** not started; blocked on Phase 2 cutover.
[exit 0]
```
