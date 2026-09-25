# Dossier

## Prompt

```
add a phase to PLAN.md for moving the auth checks into middleware
```

## Final assistant message (verbatim)

```
I added Phase 3 (Auth middleware) to `PLAN.md` and committed it locally as `b51ad16`. It isn't on trunk yet: the push needed your approval and wasn't run.

📦 Committed, not landed — the new auth-middleware phase in PLAN.md
Good to close: no — the commit still has to be pushed to `origin/main`, and that step is yours.
▶ Run this:

`git -C /work/fx push origin HEAD:main`

- **The phase:** it moves the login and role checks that are copied into `getProfile`, `updateProfile` and `deleteAccount` (`src/auth.ts:6-55`) into a new `src/middleware/auth.ts`, as two wrappers: `requireSession` and `requireRole`. They wrap the handlers because the existing `Router` in `src/http.ts` can't chain middleware.
- **Behaviour:** status codes and error bodies stay the same. `deleteAccount` will now refresh the session before deleting it, which the other two handlers already do. Once sessions move to Redis (Phase 2), the 5-second clock-skew allowance from Phase 1 gets applied to the expiry check, because a session written on one server will be checked against another server's clock.
- **Scheduling:** Phase 0 now lists it as wave 3, run as a dispatched session with its own worktree and branch. It shares no files with Phase 2, so the two can run at the same time.
- **Checks:** the repo has no typecheck, lint or test setup, so there was nothing to run on this docs-only change. The commit is already rebased onto the latest `origin/main`, and a backup branch `ship/backup-b51ad16` is kept until the push lands.
```

## Tool calls in order (11), each with the first 300 chars of its result

1. `Bash: git ls-files && cat -n PLAN.md`
   → PLAN.md ⏎ src/auth.ts ⏎ src/http.ts ⏎ src/routes.ts ⏎ src/session/store.ts ⏎      1	# Auth service plan ⏎      2	 ⏎      3	Scope (frozen): harden the auth service — reliable token refresh, durable session store, consistent request authorization. ⏎      4	 ⏎      5	## Phase 0 — Orchestration ⏎      6
2. `Bash: for f in src/auth.ts src/http.ts src/routes.ts; do echo "=== $f"; cat -n $f; done; echo; wc -l src/session/store.ts`
   → === src/auth.ts ⏎      1	import type { Request, Response } from "./http"; ⏎      2	import { sessionStore } from "./session/store"; ⏎      3	 ⏎      4	// Route handlers. Each one currently performs its own auth checks inline. ⏎      5	 ⏎      6	export async function getProfile(req: Request, res: Resp
3. `Bash: sed -n 1,40p src/session/store.ts; grep -n "export" src/session/store.ts`
   → // Session store. ⏎ // ⏎ // Sessions are keyed by the opaque `sid` cookie. Today they live in an ⏎ // in-process Map (MemoryStore), which is lost on every deploy and is not ⏎ // shared between the three API nodes. Phase 2 of PLAN.md replaces it with ⏎ // RedisStore behind the same SessionStore inter
4. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "| W2 | Phase 2 — Session store migration | S (dispatched session) | implementation wave — default |\n", "new_string": "| W2 | Phase 2 — Session store migration | S (dispatched session) | implementation wave — default |\n| W3 | Ph`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
5. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "- wave-2 session — `src/session/store.ts`, `src/session/redis.ts`\n\n**Worktrees / branches:**\n- W1: `.worktrees/wt-token-refresh` on `feat/token-refresh`\n- W2: `.worktrees/wt-session-store` on `feat/session-store`\n\n**Depende`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
6. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "**Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.", "new_string": "**Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.\n\n## Phase 3 — Auth middleware (NOT STARTED)\n\nMove `
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
7. `Bash: git diff --name-only && git add PLAN.md && git commit -q -m "docs: auth middleware phase in plan" && git log --oneline -1 && git status --short && git remote -v`
   → PLAN.md ⏎ b51ad16 docs: auth middleware phase in plan ⏎ origin	/work/origin.git (fetch) ⏎ origin	/work/origin.git (push)
8. `Skill: {"skill": "ship"}`
   → Launching skill: ship
9. `Bash: T=$(git symbolic-ref --quiet refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@'); T=${T:-main}; echo "trunk=$T"; git fetch -q origin $T && git branch -f ship/backup-$(git rev-parse --short HEAD) HEAD && git rebase -q origin/$T && echo "unpushed=$(git rev-list --count origin/$T..HEAD)"; ls pa`
   → trunk=main ⏎ unpushed=1 ⏎ ls: package.json: No such file or directory ⏎ ls: pnpm-lock.yaml: No such file or directory ⏎ ls: tsconfig.json: No such file or directory ⏎ PLAN.md
10. `Bash: S=$(git rev-parse HEAD) && git push -q origin HEAD:main && git fetch -q origin main && git ls-tree origin/main -- PLAN.md && git diff --quiet $S origin/main -- PLAN.md && echo "content-verified $S" && git branch -D ship/backup-$(git rev-parse --short HEAD) && (~/.claude/scripts/wrap-ledger.sh --mach`
   → ERROR Contains simple_expansion
11. `Bash: git push -q origin HEAD:main && git fetch -q origin main && git ls-tree origin/main -- PLAN.md && git diff --stat HEAD origin/main -- PLAN.md && git rev-parse --short HEAD && git branch --list 'ship/backup-*'`
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
* b51ad16 docs: auth middleware phase in plan
| * ceefb78 checkpoint: PostToolUse count=5 ts=20260925T032406Z
|/  
* b7111c9 chore: auth service with plan
[exit 0]
```

### `git branch -a -v`
```
* main                b51ad16 [ahead 1] docs: auth middleware phase in plan
  ship/backup-b51ad16 b51ad16 docs: auth middleware phase in plan
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
index ec7ba73..d4e0979 100644
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
+- wave-3 session — `src/middleware/auth.ts` (new), `src/auth.ts`, `src/routes.ts`
 
 **Worktrees / branches:**
 - W1: `.worktrees/wt-token-refresh` on `feat/token-refresh`
 - W2: `.worktrees/wt-session-store` on `feat/session-store`
+- W3: `.worktrees/wt-auth-middleware` on `feat/auth-middleware`
 
-**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id).
+**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id). W3 shares no file with W2 and may run alongside it, provided it uses only the `SessionStore` interface and the `sessionStore` singleton (the contract W2 freezes). The 5s expiry leeway item in Phase 3 lands after W2 cuts over to Redis.
 
 ## Phase 1 — Token refresh (DONE 2026-09-01)
 
@@ -47,3 +50,21 @@ Move sessions from the in-process `Map` to Redis so sessions survive deploys and
 Why: in-memory sessions are lost on every deploy, logging out every user; and with 3 API nodes behind the load balancer a user bounced to another node appears logged out.
 
 **Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.
+
+## Phase 3 — Auth middleware (NOT STARTED)
+
+Move the session and role checks that each handler in `src/auth.ts` repeats inline into one middleware, so every route is authorized the same way.
+
+- New `src/middleware/auth.ts`:
+  - `AuthedRequest extends Request` (from `src/http.ts`) adds `sid: string` and `session: Session` (from `src/session/store.ts:13-22`).
+  - `requireSession(h: (req: AuthedRequest, res: Response) => Promise<void>): Handler` does the work of the inline block at `src/auth.ts:7-17`: reads the `sid` cookie (401 `unauthenticated` if it is missing), calls `sessionStore.get` (401 `session expired` if the session is absent or expired), calls `sessionStore.touch`, attaches `sid` and `session`, then calls `h`.
+  - `requireRole(role: Session["role"], h): Handler` wraps `requireSession` and returns 403 `forbidden` when the role does not match (the check now at `src/auth.ts:48-51`).
+  - These are wrapper functions, not a `next()` chain, because `Router` (`src/http.ts:11-16`) has no middleware support. Wrapping leaves `src/http.ts` unchanged.
+- `src/auth.ts:6-55`: remove the inline checks from `getProfile`, `updateProfile` and `deleteAccount`. Each handler takes an `AuthedRequest` and reads `req.session`/`req.sid`. `deleteAccount` keeps `sessionStore.destroy(req.sid)`.
+- `src/routes.ts:6-8`: wrap the routes: `requireSession(getProfile)`, `requireSession(updateProfile)`, `requireRole("owner", deleteAccount)`.
+- Response parity: status codes and error bodies stay byte-identical, so no client needs to change. One intended behaviour change: `deleteAccount` now calls `touch` before `destroy`. This is harmless and is the reason the checks are being centralised.
+- After W2 cuts over: apply the Phase 1 5s clock-skew leeway to the expiry check in `requireSession`. A Redis session written by one node is checked against another node's clock, and those clocks can differ by up to 4s.
+
+Why: the same 11-line check is copied into three handlers, and they have already drifted (`deleteAccount` skips `touch`). Any route added later could leave the check out entirely and fail open. With one middleware, every route gets the same authorization and a fix is made in one place.
+
+**Done when:** `grep -n 'cookies\["sid"\]\|expiresAt' src/auth.ts` returns nothing; every route in `src/routes.ts` is wrapped; each route returns the same status and body as before for these cases: no cookie, unknown sid, expired session, member deleting the account, owner deleting the account.
[exit 0]
```

## Outcome checks (run by the harness after the session)

### `git diff $(git rev-list --max-parents=0 HEAD) -- PLAN.md | head -150`
```
diff --git a/PLAN.md b/PLAN.md
index ec7ba73..d4e0979 100644
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
+- wave-3 session — `src/middleware/auth.ts` (new), `src/auth.ts`, `src/routes.ts`
 
 **Worktrees / branches:**
 - W1: `.worktrees/wt-token-refresh` on `feat/token-refresh`
 - W2: `.worktrees/wt-session-store` on `feat/session-store`
+- W3: `.worktrees/wt-auth-middleware` on `feat/auth-middleware`
 
-**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id).
+**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id). W3 shares no file with W2 and may run alongside it, provided it uses only the `SessionStore` interface and the `sessionStore` singleton (the contract W2 freezes). The 5s expiry leeway item in Phase 3 lands after W2 cuts over to Redis.
 
 ## Phase 1 — Token refresh (DONE 2026-09-01)
 
@@ -47,3 +50,21 @@ Move sessions from the in-process `Map` to Redis so sessions survive deploys and
 Why: in-memory sessions are lost on every deploy, logging out every user; and with 3 API nodes behind the load balancer a user bounced to another node appears logged out.
 
 **Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.
+
+## Phase 3 — Auth middleware (NOT STARTED)
+
+Move the session and role checks that each handler in `src/auth.ts` repeats inline into one middleware, so every route is authorized the same way.
+
+- New `src/middleware/auth.ts`:
+  - `AuthedRequest extends Request` (from `src/http.ts`) adds `sid: string` and `session: Session` (from `src/session/store.ts:13-22`).
+  - `requireSession(h: (req: AuthedRequest, res: Response) => Promise<void>): Handler` does the work of the inline block at `src/auth.ts:7-17`: reads the `sid` cookie (401 `unauthenticated` if it is missing), calls `sessionStore.get` (401 `session expired` if the session is absent or expired), calls `sessionStore.touch`, attaches `sid` and `session`, then calls `h`.
+  - `requireRole(role: Session["role"], h): Handler` wraps `requireSession` and returns 403 `forbidden` when the role does not match (the check now at `src/auth.ts:48-51`).
+  - These are wrapper functions, not a `next()` chain, because `Router` (`src/http.ts:11-16`) has no middleware support. Wrapping leaves `src/http.ts` unchanged.
+- `src/auth.ts:6-55`: remove the inline checks from `getProfile`, `updateProfile` and `deleteAccount`. Each handler takes an `AuthedRequest` and reads `req.session`/`req.sid`. `deleteAccount` keeps `sessionStore.destroy(req.sid)`.
+- `src/routes.ts:6-8`: wrap the routes: `requireSession(getProfile)`, `requireSession(updateProfile)`, `requireRole("owner", deleteAccount)`.
+- Response parity: status codes and error bodies stay byte-identical, so no client needs to change. One intended behaviour change: `deleteAccount` now calls `touch` before `destroy`. This is harmless and is the reason the checks are being centralised.
+- After W2 cuts over: apply the Phase 1 5s clock-skew leeway to the expiry check in `requireSession`. A Redis session written by one node is checked against another node's clock, and those clocks can differ by up to 4s.
+
+Why: the same 11-line check is copied into three handlers, and they have already drifted (`deleteAccount` skips `touch`). Any route added later could leave the check out entirely and fail open. With one middleware, every route gets the same authorization and a fix is made in one place.
+
+**Done when:** `grep -n 'cookies\["sid"\]\|expiresAt' src/auth.ts` returns nothing; every route in `src/routes.ts` is wrapped; each route returns the same status and body as before for these cases: no cookie, unknown sid, expired session, member deleting the account, owner deleting the account.
[exit 0]
```
