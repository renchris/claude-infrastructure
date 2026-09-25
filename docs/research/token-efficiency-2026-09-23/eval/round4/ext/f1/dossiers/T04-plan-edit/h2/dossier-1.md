# Dossier

## Prompt

```
add a phase to PLAN.md for moving the auth checks into middleware
```

## Final assistant message (verbatim)

```
📦 The Phase 3 plan change is committed as `94f2ce2` on `main` but hasn't been pushed. It's parked on purpose because the push needs your approval.
Good to close: no — the commit still has to land on `origin/main`, and only you can approve that push; follow-on: none.

▶ Run this:

`git fetch -q origin main && git rebase -q origin/main && git push -q origin HEAD:main && git diff --quiet HEAD origin/main -- PLAN.md && echo LANDED`

I'm not queuing the Phase 3 middleware code as separate work: you asked only for the plan entry, and `PLAN.md` records the whole phase for whoever runs it.
```

## Tool calls in order (12), each with the first 300 chars of its result

1. `Bash: git ls-files && echo ---- && cat -n PLAN.md`
   → PLAN.md ⏎ src/auth.ts ⏎ src/http.ts ⏎ src/routes.ts ⏎ src/session/store.ts ⏎ ---- ⏎      1	# Auth service plan ⏎      2	 ⏎      3	Scope (frozen): harden the auth service — reliable token refresh, durable session store, consistent request authorization. ⏎      4	 ⏎      5	## Phase 0 — Orchestration ⏎
2. `Bash: for f in src/auth.ts src/http.ts src/routes.ts; do echo "==== $f"; cat -n $f; done; echo "==== store"; wc -l src/session/store.ts`
   → ==== src/auth.ts ⏎      1	import type { Request, Response } from "./http"; ⏎      2	import { sessionStore } from "./session/store"; ⏎      3	 ⏎      4	// Route handlers. Each one currently performs its own auth checks inline. ⏎      5	 ⏎      6	export async function getProfile(req: Request, res: Res
3. `Bash: sed -n 1,40p src/session/store.ts; grep -n "export" src/session/store.ts`
   → // Session store. ⏎ // ⏎ // Sessions are keyed by the opaque `sid` cookie. Today they live in an ⏎ // in-process Map (MemoryStore), which is lost on every deploy and is not ⏎ // shared between the three API nodes. Phase 2 of PLAN.md replaces it with ⏎ // RedisStore behind the same SessionStore inter
4. `Read: {"file_path": "/work/fx/PLAN.md"}`
   → 1	# Auth service plan ⏎ 2	 ⏎ 3	Scope (frozen): harden the auth service — reliable token refresh, durable session store, consistent request authorization. ⏎ 4	 ⏎ 5	## Phase 0 — Orchestration ⏎ 6	 ⏎ 7	**Execution locus per wave:** ⏎ 8	 ⏎ 9	| Wave | Phase | Locus | Why | ⏎ 10	|---|---|---|---| ⏎ 11	| W
5. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "| W2 | Phase 2 — Session store migration | S (dispatched session) | implementation wave — default |\n", "new_string": "| W2 | Phase 2 — Session store migration | S (dispatched session) | implementation wave — default |\n| W3 | Ph`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
6. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "- wave-2 session — `src/session/store.ts`, `src/session/redis.ts`\n", "new_string": "- wave-2 session — `src/session/store.ts`, `src/session/redis.ts`\n- wave-3 session — `src/middleware/auth.ts` (new), `src/http.ts`, `src/routes`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
7. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "- W2: `.worktrees/wt-session-store` on `feat/session-store`\n\n**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id).\n", "new_string": "- W2: `.worktrees/wt-session-store` on `feat/session-store`\n- W3`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
8. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "**Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.\n", "new_string": "**Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.\n\n## Phase 3 — Auth middleware (PLANNED)\n\nMove th`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
9. `Bash: git diff --name-only && git add PLAN.md && git commit -q -m "docs: auth middleware phase in plan" && git log --oneline -1 && git status --short && git remote -v`
   → PLAN.md ⏎ 94f2ce2 docs: auth middleware phase in plan ⏎ origin	/work/origin.git (fetch) ⏎ origin	/work/origin.git (push)
10. `Skill: {"skill": "ship"}`
   → Launching skill: ship
11. `Bash: T=$(git symbolic-ref --quiet refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@'); T=${T:-main}; echo trunk=$T; git fetch -q origin $T && git rev-list --count origin/$T..HEAD && git branch -f ship/backup-$(git rev-parse --short HEAD) HEAD && git rebase -q origin/$T && git diff --name-only ori`
   → ERROR Contains expansion
12. `Bash: git fetch -q origin main && git rev-list --count origin/main..HEAD && git branch -f ship/backup-94f2ce2 HEAD && git rebase -q origin/main && git diff --name-only origin/main..HEAD && git push -q origin HEAD:main && git fetch -q origin main && git ls-tree origin/main -- PLAN.md && git diff --quiet HE`
   → ERROR This Bash command contains multiple operations. The following parts require approval: git fetch -q origin main, git rebase -q origin/main, git push -q origin HEAD:main, git ls-tree origin/main -- PLAN.md

Stop-hook feedback turns: 3. Hook blocking errors: 3.

## Repo state after the run

### `git status --short --branch`
```
## main...origin/main [ahead 1]
[exit 0]
```

### `git log --oneline --all --graph -8`
```
* 94f2ce2 docs: auth middleware phase in plan
| * b6e68bb checkpoint: PostToolUse count=5 ts=20260925T151428Z
|/  
* b7111c9 chore: auth service with plan
[exit 0]
```

### `git branch -a -v`
```
* main                94f2ce2 [ahead 1] docs: auth middleware phase in plan
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

### Diff of tracked files vs the base commit
```diff
diff --git a/PLAN.md b/PLAN.md
index ec7ba73..30668cd 100644
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
+- wave-3 session — `src/middleware/auth.ts` (new), `src/http.ts`, `src/routes.ts`, `src/auth.ts`
 
 **Worktrees / branches:**
 - W1: `.worktrees/wt-token-refresh` on `feat/token-refresh`
 - W2: `.worktrees/wt-session-store` on `feat/session-store`
+- W3: `.worktrees/wt-auth-middleware` on `feat/auth-middleware`
 
-**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id).
+**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id). W3 is independent of W2 and may run concurrently: no shared file, and the middleware calls only the frozen `SessionStore` interface (`get`, `touch`). Whichever of W2/W3 merges second, the lead updates the caller comment at `src/session/store.ts:8-10` (it names `src/auth.ts`; after W3 the caller is `src/middleware/auth.ts`).
 
 ## Phase 1 — Token refresh (DONE 2026-09-01)
 
@@ -47,3 +50,21 @@ Move sessions from the in-process `Map` to Redis so sessions survive deploys and
 Why: in-memory sessions are lost on every deploy, logging out every user; and with 3 API nodes behind the load balancer a user bounced to another node appears logged out.
 
 **Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.
+
+## Phase 3 — Auth middleware (PLANNED)
+
+Move the session and role checks out of the route handlers into middleware that runs before them, so every protected route is authorized the same way.
+
+- New `src/middleware/auth.ts`:
+  - `requireSession` — read `req.cookies["sid"]` (missing → 401 `{ error: "unauthenticated" }`); `sessionStore.get(sid)` (missing or `expiresAt < Date.now()` → 401 `{ error: "session expired" }`); `sessionStore.touch(sid)`; attach `req.sid` and `req.session`, then call `next()`.
+  - `requireRole(role: Session["role"])` — runs after `requireSession`; `req.session.role !== role` → 403 `{ error: "forbidden" }`.
+- `src/http.ts:2-5` — add optional `sid?: string` and `session?: Session` to `Request` (import `Session` from `./session/store`).
+- `src/http.ts:10-16` — add `Middleware = (req, res, next: () => Promise<void>) => Promise<void>`; `get`/`patch`/`delete` accept `...middleware` before the final `Handler` and run them in order, stopping at the first one that responds without calling `next`.
+- `src/routes.ts:6-8` — `GET /me` and `PATCH /me` get `requireSession`; `DELETE /me` gets `requireSession, requireRole("owner")`.
+- `src/auth.ts:7-17`, `:22-32`, `:38-51` — delete the inline checks; handlers read `req.session!` / `req.sid!`. `deleteAccount` keeps `sessionStore.destroy(req.sid!)` (`:52`).
+- Keep status codes and error bodies byte-identical to today's; clients match on them.
+- Behaviour change to accept: `DELETE /me` now calls `touch` before `destroy` (today it skips `touch`). Harmless — the session is destroyed in the same request.
+
+Why: the same 10-line check is copy-pasted into all three handlers (`src/auth.ts:7-16`, `:22-31`, `:38-47`); a new route that forgets it is silently unauthenticated. Middleware makes authorization declarative at the route table, which is the "consistent request authorization" item of the frozen scope.
+
+**Verification:** tests for each route covering no cookie → 401, unknown/expired sid → 401, member on `DELETE /me` → 403, valid session → 200 with `touch` called; typecheck clean.
[exit 0]
```

## Outcome checks (run by the harness after the session)

### `git diff $(git rev-list --max-parents=0 HEAD) -- PLAN.md | head -150`
```
diff --git a/PLAN.md b/PLAN.md
index ec7ba73..30668cd 100644
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
+- wave-3 session — `src/middleware/auth.ts` (new), `src/http.ts`, `src/routes.ts`, `src/auth.ts`
 
 **Worktrees / branches:**
 - W1: `.worktrees/wt-token-refresh` on `feat/token-refresh`
 - W2: `.worktrees/wt-session-store` on `feat/session-store`
+- W3: `.worktrees/wt-auth-middleware` on `feat/auth-middleware`
 
-**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id).
+**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id). W3 is independent of W2 and may run concurrently: no shared file, and the middleware calls only the frozen `SessionStore` interface (`get`, `touch`). Whichever of W2/W3 merges second, the lead updates the caller comment at `src/session/store.ts:8-10` (it names `src/auth.ts`; after W3 the caller is `src/middleware/auth.ts`).
 
 ## Phase 1 — Token refresh (DONE 2026-09-01)
 
@@ -47,3 +50,21 @@ Move sessions from the in-process `Map` to Redis so sessions survive deploys and
 Why: in-memory sessions are lost on every deploy, logging out every user; and with 3 API nodes behind the load balancer a user bounced to another node appears logged out.
 
 **Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.
+
+## Phase 3 — Auth middleware (PLANNED)
+
+Move the session and role checks out of the route handlers into middleware that runs before them, so every protected route is authorized the same way.
+
+- New `src/middleware/auth.ts`:
+  - `requireSession` — read `req.cookies["sid"]` (missing → 401 `{ error: "unauthenticated" }`); `sessionStore.get(sid)` (missing or `expiresAt < Date.now()` → 401 `{ error: "session expired" }`); `sessionStore.touch(sid)`; attach `req.sid` and `req.session`, then call `next()`.
+  - `requireRole(role: Session["role"])` — runs after `requireSession`; `req.session.role !== role` → 403 `{ error: "forbidden" }`.
+- `src/http.ts:2-5` — add optional `sid?: string` and `session?: Session` to `Request` (import `Session` from `./session/store`).
+- `src/http.ts:10-16` — add `Middleware = (req, res, next: () => Promise<void>) => Promise<void>`; `get`/`patch`/`delete` accept `...middleware` before the final `Handler` and run them in order, stopping at the first one that responds without calling `next`.
+- `src/routes.ts:6-8` — `GET /me` and `PATCH /me` get `requireSession`; `DELETE /me` gets `requireSession, requireRole("owner")`.
+- `src/auth.ts:7-17`, `:22-32`, `:38-51` — delete the inline checks; handlers read `req.session!` / `req.sid!`. `deleteAccount` keeps `sessionStore.destroy(req.sid!)` (`:52`).
+- Keep status codes and error bodies byte-identical to today's; clients match on them.
+- Behaviour change to accept: `DELETE /me` now calls `touch` before `destroy` (today it skips `touch`). Harmless — the session is destroyed in the same request.
+
+Why: the same 10-line check is copy-pasted into all three handlers (`src/auth.ts:7-16`, `:22-31`, `:38-47`); a new route that forgets it is silently unauthenticated. Middleware makes authorization declarative at the route table, which is the "consistent request authorization" item of the frozen scope.
+
+**Verification:** tests for each route covering no cookie → 401, unknown/expired sid → 401, member on `DELETE /me` → 403, valid session → 200 with `touch` called; typecheck clean.
[exit 0]
```
