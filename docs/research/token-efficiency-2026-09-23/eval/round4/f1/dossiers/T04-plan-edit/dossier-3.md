# Dossier

## Prompt

```
add a phase to PLAN.md for moving the auth checks into middleware
```

## Final assistant message (verbatim)

```
📦 Done, but only on a branch (1 commit unlanded): I added Phase 3 (auth middleware) to PLAN.md and committed it, but the push needed your approval, so it hasn't landed.
Good to close: no — commit `c9e33a2` is on local `main` only; you need to push it.
▶ Run this:

`git -C /work/fx push origin HEAD:main`

- **Phase 3 in PLAN.md:** it replaces the auth check that is copied into all three handlers in `src/auth.ts` with two middleware functions in a new `src/middleware/auth.ts`. `requireSession` returns the same 401 responses and refreshes the session. `requireRole("owner")` returns the 403 on `DELETE /me`. The phase gives the line ranges to change in `src/http.ts` and `src/routes.ts`, and ends with a test-based "Done when" check.
- **Orchestration section:** the new phase runs as a separate dispatched session with its own worktree. It waits until the session-store move to Redis finishes, because that phase forbids changing the handlers in `src/auth.ts` while it runs.
- **Recorded behavior change:** `deleteAccount` will now refresh the session before destroying it, which is harmless.
- **Backup:** the rebase was a no-op, so the backup branch `ship/backup-c9e33a2` is identical to the commit. Delete it once the push is confirmed.
```

## Tool calls in order (13), each with the first 300 chars of its result

1. `Bash: git ls-files && echo --- && cat -n PLAN.md`
   → PLAN.md ⏎ src/auth.ts ⏎ src/http.ts ⏎ src/routes.ts ⏎ src/session/store.ts ⏎ --- ⏎      1	# Auth service plan ⏎      2	 ⏎      3	Scope (frozen): harden the auth service — reliable token refresh, durable session store, consistent request authorization. ⏎      4	 ⏎      5	## Phase 0 — Orchestration ⏎ 
2. `Bash: for f in src/auth.ts src/http.ts src/routes.ts; do echo "=== $f"; cat -n $f; done; echo "=== store head"; sed -n 1,40p src/session/store.ts`
   → === src/auth.ts ⏎      1	import type { Request, Response } from "./http"; ⏎      2	import { sessionStore } from "./session/store"; ⏎      3	 ⏎      4	// Route handlers. Each one currently performs its own auth checks inline. ⏎      5	 ⏎      6	export async function getProfile(req: Request, res: Resp
3. `Read: {"file_path": "/work/fx/PLAN.md"}`
   → 1	# Auth service plan ⏎ 2	 ⏎ 3	Scope (frozen): harden the auth service — reliable token refresh, durable session store, consistent request authorization. ⏎ 4	 ⏎ 5	## Phase 0 — Orchestration ⏎ 6	 ⏎ 7	**Execution locus per wave:** ⏎ 8	 ⏎ 9	| Wave | Phase | Locus | Why | ⏎ 10	|---|---|---|---| ⏎ 11	| W
4. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "| W2 | Phase 2 — Session store migration | S (dispatched session) | implementation wave — default |\n", "new_string": "| W2 | Phase 2 — Session store migration | S (dispatched session) | implementation wave — default |\n| W3 | Ph`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
5. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "- wave-2 session — `src/session/store.ts`, `src/session/redis.ts`\n", "new_string": "- wave-2 session — `src/session/store.ts`, `src/session/redis.ts`\n- wave-3 session — `src/middleware/auth.ts`, `src/http.ts`, `src/routes.ts`, `
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
6. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "- W2: `.worktrees/wt-session-store` on `feat/session-store`\n\n**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id).", "new_string": "- W2: `.worktrees/wt-session-store` on `feat/session-store`\n- W3: `
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
7. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "**Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.", "new_string": "**Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.\n\n## Phase 3 — Auth middleware (PLANNED)\n\nMove the `
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
8. `Bash: git diff --name-only && git add PLAN.md && git commit -qm "docs: phase 3 auth middleware plan" && git log --oneline -1 && git status --short && git remote -v`
   → PLAN.md ⏎ c9e33a2 docs: phase 3 auth middleware plan ⏎ origin	/work/origin.git (fetch) ⏎ origin	/work/origin.git (push)
9. `Skill: {"skill": "ship"}`
   → Launching skill: ship
10. `Bash: T=$(git symbolic-ref --quiet refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@'); T=${T:-main}; echo trunk=$T; git fetch -q origin $T && git branch -f ship/backup-$(git rev-parse --short HEAD) HEAD && git rebase -q origin/$T && git diff --name-only origin/$T..HEAD && ls package.json pnpm-loc`
   → ERROR Contains expansion
11. `Bash: git symbolic-ref --quiet refs/remotes/origin/HEAD; git fetch -q origin main && git branch -f ship/backup-c9e33a2 HEAD && git rebase -q origin/main && git diff --name-only origin/main..HEAD && ls package.json tsconfig.json 2>&1`
   → ERROR Exit code 1 ⏎ PLAN.md ⏎ ls: package.json: No such file or directory ⏎ ls: tsconfig.json: No such file or directory
12. `Bash: git push -q origin HEAD:main && git fetch -q origin main && git ls-tree origin/main -- PLAN.md && git diff --quiet HEAD origin/main -- PLAN.md && echo CONTENT-OK && git branch -D ship/backup-c9e33a2 && git log --oneline -1 origin/main && git status --short`
   → ERROR This Bash command contains multiple operations. The following parts require approval: git push -q origin HEAD:main, git fetch -q origin main, git ls-tree origin/main -- PLAN.md
13. `Bash: ~/.claude/scripts/wrap-ledger.sh --machine 2>&1 | grep -E '^READOUT' || echo "no ledger available"`
   → READOUT=📦 Done, but only on a branch (1 commit(s) unlanded) — /ship to land it (else lost).

Stop-hook feedback turns: 0. Hook blocking errors: 0.

## Repo state after the run

### `git status --short --branch`
```
## main...origin/main [ahead 1]
[exit 0]
```

### `git log --oneline --all --graph -8`
```
* c9e33a2 docs: phase 3 auth middleware plan
| * 65b4487 checkpoint: PostToolUse count=5 ts=20260925T032219Z
|/  
* b7111c9 chore: auth service with plan
[exit 0]
```

### `git branch -a -v`
```
* main                c9e33a2 [ahead 1] docs: phase 3 auth middleware plan
  ship/backup-c9e33a2 c9e33a2 docs: phase 3 auth middleware plan
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
index ec7ba73..310e946 100644
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
+- wave-3 session — `src/middleware/auth.ts`, `src/http.ts`, `src/routes.ts`, `src/auth.ts`
 
 **Worktrees / branches:**
 - W1: `.worktrees/wt-token-refresh` on `feat/token-refresh`
 - W2: `.worktrees/wt-session-store` on `feat/session-store`
+- W3: `.worktrees/wt-auth-middleware` on `feat/auth-middleware`
 
-**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id).
+**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id). W3 blockedBy W2 cutover (Phase 2 freezes `src/auth.ts` callers during dual-write; W3 rewrites them).
 
 ## Phase 1 — Token refresh (DONE 2026-09-01)
 
@@ -47,3 +50,23 @@ Move sessions from the in-process `Map` to Redis so sessions survive deploys and
 Why: in-memory sessions are lost on every deploy, logging out every user; and with 3 API nodes behind the load balancer a user bounced to another node appears logged out.
 
 **Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.
+
+## Phase 3 — Auth middleware (PLANNED)
+
+Move the per-handler auth checks into reusable middleware so every protected route authorizes the same way.
+
+- `src/auth.ts:7-17`, `22-32`, `38-47` — the same cookie → `sessionStore.get` → expiry → 401 block is copied into `getProfile`, `updateProfile` and `deleteAccount`. Replace all three with a `requireSession` middleware.
+- `src/auth.ts:48-51` — the inline `role !== "owner"` → 403 check in `deleteAccount` becomes `requireRole("owner")`.
+- New `src/middleware/auth.ts`:
+  - `requireSession`: reads `req.cookies["sid"]`; returns 401 `unauthenticated` when the cookie is missing and 401 `session expired` when the session is missing or `expiresAt < Date.now()`; calls `sessionStore.touch(sid)`; attaches `req.session` and `req.sid`. Keep both error bodies byte-identical, because clients match on them.
+  - `requireRole(role)`: returns 403 `forbidden` unless `req.session.role === role`; must run after `requireSession`.
+- `src/http.ts:2-5` — add optional `session?: Session` and `sid?: string` to `Request`. Add a `Middleware` type (`(req, res, next) => Promise<void>`).
+- `src/http.ts:13-15` — `get`, `patch` and `delete` accept `...middleware` before the handler and run them in order, stopping on the first response.
+- `src/routes.ts:6-8` — wire `requireSession` on all three `/me` routes, plus `requireRole("owner")` on `DELETE /me`.
+- Handlers read `req.session!` / `req.sid!` and keep only business logic. `deleteAccount` still calls `sessionStore.destroy(req.sid!)`.
+
+Behavior change to accept: `deleteAccount` currently skips `touch`. Under middleware it touches first and then destroys, which is harmless.
+
+Why: three copies of the same check have already started to drift (only `deleteAccount` skips `touch`), and any new route can forget the check entirely. Centralizing it gives Scope's "consistent request authorization" a single enforcement point.
+
+**Done when:** no `cookies["sid"]` or `expiresAt` reads are left in `src/auth.ts`; tests cover the matrix for each route (no cookie, expired session, member on `DELETE /me`, owner on `DELETE /me`) with unchanged status codes and bodies; typecheck and lint are green.
[exit 0]
```

## Outcome checks (run by the harness after the session)

### `git diff $(git rev-list --max-parents=0 HEAD) -- PLAN.md | head -150`
```
diff --git a/PLAN.md b/PLAN.md
index ec7ba73..310e946 100644
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
+- wave-3 session — `src/middleware/auth.ts`, `src/http.ts`, `src/routes.ts`, `src/auth.ts`
 
 **Worktrees / branches:**
 - W1: `.worktrees/wt-token-refresh` on `feat/token-refresh`
 - W2: `.worktrees/wt-session-store` on `feat/session-store`
+- W3: `.worktrees/wt-auth-middleware` on `feat/auth-middleware`
 
-**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id).
+**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id). W3 blockedBy W2 cutover (Phase 2 freezes `src/auth.ts` callers during dual-write; W3 rewrites them).
 
 ## Phase 1 — Token refresh (DONE 2026-09-01)
 
@@ -47,3 +50,23 @@ Move sessions from the in-process `Map` to Redis so sessions survive deploys and
 Why: in-memory sessions are lost on every deploy, logging out every user; and with 3 API nodes behind the load balancer a user bounced to another node appears logged out.
 
 **Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.
+
+## Phase 3 — Auth middleware (PLANNED)
+
+Move the per-handler auth checks into reusable middleware so every protected route authorizes the same way.
+
+- `src/auth.ts:7-17`, `22-32`, `38-47` — the same cookie → `sessionStore.get` → expiry → 401 block is copied into `getProfile`, `updateProfile` and `deleteAccount`. Replace all three with a `requireSession` middleware.
+- `src/auth.ts:48-51` — the inline `role !== "owner"` → 403 check in `deleteAccount` becomes `requireRole("owner")`.
+- New `src/middleware/auth.ts`:
+  - `requireSession`: reads `req.cookies["sid"]`; returns 401 `unauthenticated` when the cookie is missing and 401 `session expired` when the session is missing or `expiresAt < Date.now()`; calls `sessionStore.touch(sid)`; attaches `req.session` and `req.sid`. Keep both error bodies byte-identical, because clients match on them.
+  - `requireRole(role)`: returns 403 `forbidden` unless `req.session.role === role`; must run after `requireSession`.
+- `src/http.ts:2-5` — add optional `session?: Session` and `sid?: string` to `Request`. Add a `Middleware` type (`(req, res, next) => Promise<void>`).
+- `src/http.ts:13-15` — `get`, `patch` and `delete` accept `...middleware` before the handler and run them in order, stopping on the first response.
+- `src/routes.ts:6-8` — wire `requireSession` on all three `/me` routes, plus `requireRole("owner")` on `DELETE /me`.
+- Handlers read `req.session!` / `req.sid!` and keep only business logic. `deleteAccount` still calls `sessionStore.destroy(req.sid!)`.
+
+Behavior change to accept: `deleteAccount` currently skips `touch`. Under middleware it touches first and then destroys, which is harmless.
+
+Why: three copies of the same check have already started to drift (only `deleteAccount` skips `touch`), and any new route can forget the check entirely. Centralizing it gives Scope's "consistent request authorization" a single enforcement point.
+
+**Done when:** no `cookies["sid"]` or `expiresAt` reads are left in `src/auth.ts`; tests cover the matrix for each route (no cookie, expired session, member on `DELETE /me`, owner on `DELETE /me`) with unchanged status codes and bodies; typecheck and lint are green.
[exit 0]
```
