# Dossier

## Prompt

```
add a phase to PLAN.md for moving the auth checks into middleware
```

## Final assistant message (verbatim)

```
📦 Phase 3 (auth middleware) is added to PLAN.md and committed as `fb16f0e`, but it's only on local `main`. The push to origin was blocked because Bash wasn't given permission to run it.

Good to close: no. The commit still has to be pushed to origin; nothing else is left.

▶ Run this:

`git -C /work/fx push origin HEAD:main`

What the new phase says:
- **The change:** the same session check (read the `sid` cookie, look up the session, check expiry) is copied into all three handlers in `src/auth.ts`. It moves into a new `src/middleware/auth.ts`, which provides a `requireSession` wrapper and a `requireRole("owner")` wrapper. `Request` gets a `session` field, and `src/routes.ts` wraps each handler when it's registered. The error responses stay exactly the same.
- **Ordering:** it runs as a third wave, W3, in its own dispatched session, and only after Phase 2 finishes. Phase 2 says the code in `src/auth.ts` that calls the session store must not change while sessions are written to both stores, and Phase 3 rewrites that code.
- **One behaviour change:** `deleteAccount` doesn't refresh the session today. Under the middleware it will refresh it just before deleting it, which does no harm. The plan says so, so a reviewer doesn't flag it.
- **Tests:** a 401 when there's no cookie or the session has expired, a 200 when the session is valid, a 403 when a non-owner calls `DELETE /me`, and a grep confirming no cookie checks are left in `src/auth.ts`.

The Phase 0 table, roster, worktrees and dependencies are updated to include W3.
```

## Tool calls in order (10), each with the first 300 chars of its result

1. `Bash: git ls-files && cat -n PLAN.md`
   → PLAN.md ⏎ src/auth.ts ⏎ src/http.ts ⏎ src/routes.ts ⏎ src/session/store.ts ⏎      1	# Auth service plan ⏎      2	 ⏎      3	Scope (frozen): harden the auth service — reliable token refresh, durable session store, consistent request authorization. ⏎      4	 ⏎      5	## Phase 0 — Orchestration ⏎      6
2. `Bash: for f in src/auth.ts src/http.ts src/routes.ts; do echo "=== $f"; cat -n $f; done`
   → === src/auth.ts ⏎      1	import type { Request, Response } from "./http"; ⏎      2	import { sessionStore } from "./session/store"; ⏎      3	 ⏎      4	// Route handlers. Each one currently performs its own auth checks inline. ⏎      5	 ⏎      6	export async function getProfile(req: Request, res: Resp
3. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "| W2 | Phase 2 — Session store migration | S (dispatched session) | implementation wave — default |\n", "new_string": "| W2 | Phase 2 — Session store migration | S (dispatched session) | implementation wave — default |\n| W3 | Ph`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
4. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "- wave-2 session — `src/session/store.ts`, `src/session/redis.ts`\n", "new_string": "- wave-2 session — `src/session/store.ts`, `src/session/redis.ts`\n- wave-3 session — `src/middleware/auth.ts` (new), `src/http.ts`, `src/auth.t`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
5. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "- W2: `.worktrees/wt-session-store` on `feat/session-store`\n\n**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id).", "new_string": "- W2: `.worktrees/wt-session-store` on `feat/session-store`\n- W3: `
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
6. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "**Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.", "new_string": "**Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.\n\n## Phase 3 — Auth middleware (PLANNED)\n\nMove the `
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
7. `Bash: git diff --name-only && git add PLAN.md && git commit -qm "docs: plan phase 3 for auth middleware" && git log --oneline -1 && git remote -v`
   → PLAN.md ⏎ fb16f0e docs: plan phase 3 for auth middleware ⏎ origin	/work/origin.git (fetch) ⏎ origin	/work/origin.git (push)
8. `Skill: {"skill": "ship"}`
   → Launching skill: ship
9. `Bash: git fetch -q origin main && git rev-list --count origin/main..HEAD && git branch -f ship/backup-fb16f0e HEAD && git rebase -q origin/main && git push -q origin HEAD:main && git fetch -q origin main && git ls-tree origin/main -- PLAN.md && git diff --stat HEAD origin/main -- PLAN.md && echo "diff-emp`
   → ERROR This Bash command contains multiple operations. The following parts require approval: git fetch -q origin main, git rebase -q origin/main, git push -q origin HEAD:main, git ls-tree origin/main -- PLAN.md
10. `Bash: git push origin HEAD:main`
   → ERROR Claude requested permissions to use Bash, but you haven't granted it yet.

Stop-hook feedback turns: 0. Hook blocking errors: 0.

## Repo state after the run

### `git status --short --branch`
```
## main...origin/main [ahead 1]
[exit 0]
```

### `git log --oneline --all --graph -8`
```
* fb16f0e docs: plan phase 3 for auth middleware
| * 17a1776 checkpoint: PostToolUse count=5 ts=20260925T033233Z
|/  
* b7111c9 chore: auth service with plan
[exit 0]
```

### `git branch -a -v`
```
* main                fb16f0e [ahead 1] docs: plan phase 3 for auth middleware
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
index ec7ba73..1e0e3e6 100644
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
+**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id). W3 blockedBy W2 (Phase 2 freezes `src/auth.ts` callers during dual-write; W3 rewrites them).
 
 ## Phase 1 — Token refresh (DONE 2026-09-01)
 
@@ -47,3 +50,21 @@ Move sessions from the in-process `Map` to Redis so sessions survive deploys and
 Why: in-memory sessions are lost on every deploy, logging out every user; and with 3 API nodes behind the load balancer a user bounced to another node appears logged out.
 
 **Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.
+
+## Phase 3 — Auth middleware (PLANNED)
+
+Move the per-handler auth checks into middleware so every route authorizes the same way.
+
+- `src/auth.ts:7-16`, `:22-31`, `:38-47` — the same cookie → `sessionStore.get` → expiry check is copy-pasted into `getProfile`, `updateProfile`, `deleteAccount`. Delete all three copies; handlers read `req.session` instead.
+- `src/auth.ts:48-51` — the inline `role !== "owner"` 403 check moves to a role guard.
+- New `src/middleware/auth.ts`:
+  - `requireSession(h: Handler): Handler` — reads `sid` cookie; 401 `unauthenticated` if absent, 401 `session expired` if missing/expired; calls `sessionStore.touch(sid)`; sets `req.session` and `req.sid`, then calls `h`. Error bodies stay byte-identical to today's.
+  - `requireRole(role, h: Handler): Handler` — wraps `requireSession`; 403 `forbidden` on mismatch.
+- `src/http.ts:2-5` — add optional `session?: Session` and `sid?: string` to `Request` (import `Session` type from `src/session/store.ts:12-38`, interface unchanged).
+- `src/routes.ts:6-8` — wrap: `requireSession(getProfile)`, `requireSession(updateProfile)`, `requireRole("owner", deleteAccount)`. `Router` (`src/http.ts:11-16`) has no middleware chain; wrapping at registration keeps it that way.
+
+Behavior note: `deleteAccount` never called `touch` today; under the middleware it will touch then `destroy` — harmless, but called out so the reviewer doesn't flag it.
+
+Why: three hand-copied checks drift (one already differs — no `touch` in `deleteAccount`), and any new route that forgets the block ships unauthenticated. Scope (frozen) already names "consistent request authorization".
+
+**Verify:** each route returns 401 with no cookie, 401 with an expired session, 200 with a valid one; `DELETE /me` returns 403 for a non-owner; `grep -n 'cookies\["sid"\]' src/auth.ts` returns nothing.
[exit 0]
```

## Outcome checks (run by the harness after the session)

### `git diff $(git rev-list --max-parents=0 HEAD) -- PLAN.md | head -150`
```
diff --git a/PLAN.md b/PLAN.md
index ec7ba73..1e0e3e6 100644
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
+**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id). W3 blockedBy W2 (Phase 2 freezes `src/auth.ts` callers during dual-write; W3 rewrites them).
 
 ## Phase 1 — Token refresh (DONE 2026-09-01)
 
@@ -47,3 +50,21 @@ Move sessions from the in-process `Map` to Redis so sessions survive deploys and
 Why: in-memory sessions are lost on every deploy, logging out every user; and with 3 API nodes behind the load balancer a user bounced to another node appears logged out.
 
 **Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.
+
+## Phase 3 — Auth middleware (PLANNED)
+
+Move the per-handler auth checks into middleware so every route authorizes the same way.
+
+- `src/auth.ts:7-16`, `:22-31`, `:38-47` — the same cookie → `sessionStore.get` → expiry check is copy-pasted into `getProfile`, `updateProfile`, `deleteAccount`. Delete all three copies; handlers read `req.session` instead.
+- `src/auth.ts:48-51` — the inline `role !== "owner"` 403 check moves to a role guard.
+- New `src/middleware/auth.ts`:
+  - `requireSession(h: Handler): Handler` — reads `sid` cookie; 401 `unauthenticated` if absent, 401 `session expired` if missing/expired; calls `sessionStore.touch(sid)`; sets `req.session` and `req.sid`, then calls `h`. Error bodies stay byte-identical to today's.
+  - `requireRole(role, h: Handler): Handler` — wraps `requireSession`; 403 `forbidden` on mismatch.
+- `src/http.ts:2-5` — add optional `session?: Session` and `sid?: string` to `Request` (import `Session` type from `src/session/store.ts:12-38`, interface unchanged).
+- `src/routes.ts:6-8` — wrap: `requireSession(getProfile)`, `requireSession(updateProfile)`, `requireRole("owner", deleteAccount)`. `Router` (`src/http.ts:11-16`) has no middleware chain; wrapping at registration keeps it that way.
+
+Behavior note: `deleteAccount` never called `touch` today; under the middleware it will touch then `destroy` — harmless, but called out so the reviewer doesn't flag it.
+
+Why: three hand-copied checks drift (one already differs — no `touch` in `deleteAccount`), and any new route that forgets the block ships unauthenticated. Scope (frozen) already names "consistent request authorization".
+
+**Verify:** each route returns 401 with no cookie, 401 with an expired session, 200 with a valid one; `DELETE /me` returns 403 for a non-owner; `grep -n 'cookies\["sid"\]' src/auth.ts` returns nothing.
[exit 0]
```
