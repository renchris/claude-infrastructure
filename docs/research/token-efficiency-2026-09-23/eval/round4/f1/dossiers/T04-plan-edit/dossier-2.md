# Dossier

## Prompt

```
add a phase to PLAN.md for moving the auth checks into middleware
```

## Final assistant message (verbatim)

```
📦 Committed on `main`, not landed: the push to origin needs your approval.
Good to close: no — the push to origin is waiting on you.
▶ Run this:

`git -C /work/fx push origin HEAD:main`

PLAN.md now has a **Phase 3 — Auth middleware** section, plus a W3 row in the orchestration table with its own worktree and branch.

- **What it does:** adds a new `src/middleware/auth.ts` with two wrappers, `requireSession` and `requireRole`. The session and role checks are removed from the three handlers in `src/auth.ts` (lines 6–55), and the routes in `src/routes.ts` are wrapped.
- **Design points:** they're wrappers rather than a middleware chain because `Router` has no middleware support. `AuthedRequest` carries `sid` separately because `Session` has no id field and Phase 2 froze that interface.
- **Behavior:** status codes, error bodies and check order stay the same. The one accepted difference is that `deleteAccount` now gets a harmless `touch` before its `destroy`.
- **Done when:** a grep for `cookies["sid"]` or `sessionStore.get` in `src/auth.ts` returns nothing, and a test for each path gives the same response as before.
- **Scheduling:** it can run alongside the session-store migration, since the two share no files.

The commit is `d9c8e2c`, rebased onto `origin/main`. It changes only PLAN.md and the repo has no typecheck, lint or tests, so no gate ran. The backup branch `ship/backup-d9c8e2c` is still there. Delete it once the push lands.
```

## Tool calls in order (14), each with the first 300 chars of its result

1. `Bash: git ls-files && cat -n PLAN.md`
   → PLAN.md ⏎ src/auth.ts ⏎ src/http.ts ⏎ src/routes.ts ⏎ src/session/store.ts ⏎      1	# Auth service plan ⏎      2	 ⏎      3	Scope (frozen): harden the auth service — reliable token refresh, durable session store, consistent request authorization. ⏎      4	 ⏎      5	## Phase 0 — Orchestration ⏎      6
2. `Bash: for f in src/auth.ts src/http.ts src/routes.ts; do echo "=== $f"; cat -n $f; done; wc -l src/session/store.ts`
   → === src/auth.ts ⏎      1	import type { Request, Response } from "./http"; ⏎      2	import { sessionStore } from "./session/store"; ⏎      3	 ⏎      4	// Route handlers. Each one currently performs its own auth checks inline. ⏎      5	 ⏎      6	export async function getProfile(req: Request, res: Resp
3. `Bash: grep -n "interface\|export\|role\|expiresAt" src/session/store.ts`
   → 6:// RedisStore behind the same SessionStore interface. ⏎ 8:// Callers (src/auth.ts) depend ONLY on the SessionStore interface and the ⏎ 9:// exported `sessionStore` singleton; neither may change during the ⏎ 13:export interface Session { ⏎ 18:  /** Account role; "owner" may delete the account. */ ⏎
4. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "| W2 | Phase 2 — Session store migration | S (dispatched session) | implementation wave — default |", "new_string": "| W2 | Phase 2 — Session store migration | S (dispatched session) | implementation wave — default |\n| W3 | Phas`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
5. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "- wave-2 session — `src/session/store.ts`, `src/session/redis.ts`\n", "new_string": "- wave-2 session — `src/session/store.ts`, `src/session/redis.ts`\n- wave-3 session — `src/middleware/auth.ts` (new), `src/http.ts`, `src/auth.t`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
6. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "- W2: `.worktrees/wt-session-store` on `feat/session-store`\n\n**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id).", "new_string": "- W2: `.worktrees/wt-session-store` on `feat/session-store`\n- W3: `
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
7. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "**Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.", "new_string": "**Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.\n\n## Phase 3 — Auth middleware (PLANNED)\n\nMove the `
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
8. `Bash: sed -n 13,22p src/session/store.ts; git remote -v`
   → export interface Session { ⏎   /** Stable user id. */ ⏎   userId: string; ⏎   /** Primary email, cached for display. */ ⏎   email: string; ⏎   /** Account role; "owner" may delete the account. */ ⏎   role: "owner" | "member"; ⏎   /** Epoch ms after which the session is no longer valid. */ ⏎   expire
9. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "- `src/http.ts:2-10` — add `AuthedRequest extends Request { session: Session }` and `AuthedHandler`, so handlers read `req.session` with no optional check.\n- `src/auth.ts:6-55` — delete the inline blocks (`:7-17`, `:22-32`, `:38`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
10. `Bash: git diff --name-only && git add PLAN.md && git commit -q -m "docs: auth middleware phase in plan" && git log --oneline -1`
   → PLAN.md ⏎ d9c8e2c docs: auth middleware phase in plan
11. `Skill: {"skill": "ship"}`
   → Launching skill: ship
12. `Bash: T=$(git symbolic-ref --quiet refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@'); T=${T:-main}; echo "trunk=$T"; git fetch -q origin $T && git status --short && echo "ahead=$(git rev-list --count origin/$T..HEAD)" && git branch -f ship/backup-$(git rev-parse --short HEAD) HEAD && git rebase `
   → trunk=main ⏎ ahead=1 ⏎ ls: package.json: No such file or directory ⏎ ls: pnpm-lock.yaml: No such file or directory ⏎ ls: tsconfig.json: No such file or directory ⏎ PLAN.md
13. `Bash: S=$(git rev-parse HEAD) && git push -q origin HEAD:main && git fetch -q origin main && git ls-tree origin/main -- PLAN.md && git diff --quiet $S origin/main -- PLAN.md && echo "content-verified $S" && git branch -D ship/backup-$(git rev-parse --short HEAD) && ~/.claude/scripts/wrap-ledger.sh --machi`
   → ERROR Contains simple_expansion
14. `Bash: git push -q origin HEAD:main && git fetch -q origin main && git ls-tree origin/main -- PLAN.md && git diff --stat HEAD origin/main -- PLAN.md && git rev-parse --short HEAD`
   → ERROR This Bash command contains multiple operations. The following parts require approval: git push -q origin HEAD:main, git fetch -q origin main, git ls-tree origin/main -- PLAN.md

Stop-hook feedback turns: 0. Hook blocking errors: 0.

## Repo state after the run

### `git status --short --branch`
```
## main...origin/main [ahead 1]
[exit 0]
```

### `git log --oneline --all --graph -8`
```
* d9c8e2c docs: auth middleware phase in plan
| * 8373fc7 checkpoint: PostToolUse count=5 ts=20260925T033713Z
|/  
* b7111c9 chore: auth service with plan
[exit 0]
```

### `git branch -a -v`
```
* main                d9c8e2c [ahead 1] docs: auth middleware phase in plan
  ship/backup-d9c8e2c d9c8e2c docs: auth middleware phase in plan
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
index ec7ba73..0028f5f 100644
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
+**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id). W3 may run alongside W2: no shared files, and W3 calls the store only through the frozen `SessionStore` interface (`get`, `touch`, `destroy`).
 
 ## Phase 1 — Token refresh (DONE 2026-09-01)
 
@@ -47,3 +50,23 @@ Move sessions from the in-process `Map` to Redis so sessions survive deploys and
 Why: in-memory sessions are lost on every deploy, logging out every user; and with 3 API nodes behind the load balancer a user bounced to another node appears logged out.
 
 **Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.
+
+## Phase 3 — Auth middleware (PLANNED)
+
+Move the session and role checks that every handler repeats inline into reusable middleware, so a new route cannot ship without them.
+
+- New `src/middleware/auth.ts`:
+  - `requireSession(h: AuthedHandler): Handler` — reads `req.cookies["sid"]`; no sid → `401 {error:"unauthenticated"}`; `sessionStore.get(sid)` missing or `expiresAt < Date.now()` → `401 {error:"session expired"}`; else `sessionStore.touch(sid)`, attach the session, call `h`.
+  - `requireRole(role: Session["role"], h: AuthedHandler): AuthedHandler` — mismatch → `403 {error:"forbidden"}`.
+  - Wrappers, not a chain: `Router` (`src/http.ts:11-16`) has no middleware support, and adding one is out of scope.
+- `src/http.ts:2-10` — add `AuthedRequest extends Request { sid: string; session: Session }` and `AuthedHandler`, so handlers read `req.session` with no optional check. `sid` is carried separately because `Session` (`src/session/store.ts:13-22`) has no id field and that interface is frozen by Phase 2.
+- `src/auth.ts:6-55` — delete the inline blocks (`:7-17`, `:22-32`, `:38-51`); handlers take `AuthedRequest` and use `req.session`. `deleteAccount` keeps `sessionStore.destroy(req.sid)`.
+- `src/routes.ts:6-8` — wrap: `requireSession(getProfile)`, `requireSession(updateProfile)`, `requireSession(requireRole("owner", deleteAccount))`.
+
+Behavior must not change: the same status codes, the same error bodies, and the same check order (session before role). One accepted difference: `deleteAccount` now gets a `touch` before its `destroy`, which is harmless.
+
+**Done when:** `grep -n 'cookies\["sid"\]\|sessionStore.get' src/auth.ts` returns nothing, and a test per path (no sid, unknown sid, expired sid, member deleting, owner deleting, valid get/patch) gives the same responses as before the change.
+
+Why: three copies of the same 10-line check have already drifted (only `deleteAccount` skips `touch`), and every new route is one forgotten copy away from being unauthenticated. This is the "consistent request authorization" item in the frozen scope.
+
+**Status:** not started.
[exit 0]
```

## Outcome checks (run by the harness after the session)

### `git diff $(git rev-list --max-parents=0 HEAD) -- PLAN.md | head -150`
```
diff --git a/PLAN.md b/PLAN.md
index ec7ba73..0028f5f 100644
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
+**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id). W3 may run alongside W2: no shared files, and W3 calls the store only through the frozen `SessionStore` interface (`get`, `touch`, `destroy`).
 
 ## Phase 1 — Token refresh (DONE 2026-09-01)
 
@@ -47,3 +50,23 @@ Move sessions from the in-process `Map` to Redis so sessions survive deploys and
 Why: in-memory sessions are lost on every deploy, logging out every user; and with 3 API nodes behind the load balancer a user bounced to another node appears logged out.
 
 **Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.
+
+## Phase 3 — Auth middleware (PLANNED)
+
+Move the session and role checks that every handler repeats inline into reusable middleware, so a new route cannot ship without them.
+
+- New `src/middleware/auth.ts`:
+  - `requireSession(h: AuthedHandler): Handler` — reads `req.cookies["sid"]`; no sid → `401 {error:"unauthenticated"}`; `sessionStore.get(sid)` missing or `expiresAt < Date.now()` → `401 {error:"session expired"}`; else `sessionStore.touch(sid)`, attach the session, call `h`.
+  - `requireRole(role: Session["role"], h: AuthedHandler): AuthedHandler` — mismatch → `403 {error:"forbidden"}`.
+  - Wrappers, not a chain: `Router` (`src/http.ts:11-16`) has no middleware support, and adding one is out of scope.
+- `src/http.ts:2-10` — add `AuthedRequest extends Request { sid: string; session: Session }` and `AuthedHandler`, so handlers read `req.session` with no optional check. `sid` is carried separately because `Session` (`src/session/store.ts:13-22`) has no id field and that interface is frozen by Phase 2.
+- `src/auth.ts:6-55` — delete the inline blocks (`:7-17`, `:22-32`, `:38-51`); handlers take `AuthedRequest` and use `req.session`. `deleteAccount` keeps `sessionStore.destroy(req.sid)`.
+- `src/routes.ts:6-8` — wrap: `requireSession(getProfile)`, `requireSession(updateProfile)`, `requireSession(requireRole("owner", deleteAccount))`.
+
+Behavior must not change: the same status codes, the same error bodies, and the same check order (session before role). One accepted difference: `deleteAccount` now gets a `touch` before its `destroy`, which is harmless.
+
+**Done when:** `grep -n 'cookies\["sid"\]\|sessionStore.get' src/auth.ts` returns nothing, and a test per path (no sid, unknown sid, expired sid, member deleting, owner deleting, valid get/patch) gives the same responses as before the change.
+
+Why: three copies of the same 10-line check have already drifted (only `deleteAccount` skips `touch`), and every new route is one forgotten copy away from being unauthenticated. This is the "consistent request authorization" item in the frozen scope.
+
+**Status:** not started.
[exit 0]
```
