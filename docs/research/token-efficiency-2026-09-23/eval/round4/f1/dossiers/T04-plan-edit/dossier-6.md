# Dossier

## Prompt

```
add a phase to PLAN.md for moving the auth checks into middleware
```

## Final assistant message (verbatim)

```
📦 Done, but only on a branch (1 commit not landed): Phase 3 (auth checks into middleware) is added to `PLAN.md` and committed as `5a86a02`, but it isn't pushed yet.
Good to close: no. Landing needs your approval, because the push command was refused and I haven't retried it.
▶ Run this:

`git -C /work/fx fetch origin main && git -C /work/fx rebase origin/main && git -C /work/fx push origin HEAD:main`

What the new phase says:
- **Phase 0 additions:** it runs as wave W3 in its own dispatched session, on the `feat/auth-middleware` worktree. It can't start until Phase 2 finishes, because Phase 2 doesn't allow changes to `src/auth.ts` until the Redis switch. The middleware's expiry check also needs `RedisStore.touch` to update `expiresAt`.
- **Phase 3:** a new `requireAuth(handler, { role?, touch? })` wrapper in `src/middleware/auth.ts` replaces the three copied checks in `src/auth.ts`. It handles the 401 and 403 responses, the owner-role check and session touch, and sets `req.session`. It wraps each handler in `src/routes.ts`, because the `Router` has no middleware chain. `deleteAccount` passes `touch: false`. Before it can land, tests have to cover every status path, and all responses must stay exactly the same.
```

## Tool calls in order (12), each with the first 300 chars of its result

1. `Bash: git ls-files && cat -n PLAN.md`
   → PLAN.md ⏎ src/auth.ts ⏎ src/http.ts ⏎ src/routes.ts ⏎ src/session/store.ts ⏎      1	# Auth service plan ⏎      2	 ⏎      3	Scope (frozen): harden the auth service — reliable token refresh, durable session store, consistent request authorization. ⏎      4	 ⏎      5	## Phase 0 — Orchestration ⏎      6
2. `Bash: for f in src/auth.ts src/http.ts src/routes.ts src/session/store.ts; do echo "=== $f"; cat -n $f; done`
   → === src/auth.ts ⏎      1	import type { Request, Response } from "./http"; ⏎      2	import { sessionStore } from "./session/store"; ⏎      3	 ⏎      4	// Route handlers. Each one currently performs its own auth checks inline. ⏎      5	 ⏎      6	export async function getProfile(req: Request, res: Resp
3. `Read: {"file_path": "/work/fx/PLAN.md"}`
   → 1	# Auth service plan ⏎ 2	 ⏎ 3	Scope (frozen): harden the auth service — reliable token refresh, durable session store, consistent request authorization. ⏎ 4	 ⏎ 5	## Phase 0 — Orchestration ⏎ 6	 ⏎ 7	**Execution locus per wave:** ⏎ 8	 ⏎ 9	| Wave | Phase | Locus | Why | ⏎ 10	|---|---|---|---| ⏎ 11	| W
4. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "| W2 | Phase 2 — Session store migration | S (dispatched session) | implementation wave — default |\n", "new_string": "| W2 | Phase 2 — Session store migration | S (dispatched session) | implementation wave — default |\n| W3 | Ph`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
5. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "- wave-2 session — `src/session/store.ts`, `src/session/redis.ts`\n", "new_string": "- wave-2 session — `src/session/store.ts`, `src/session/redis.ts`\n- wave-3 session — `src/middleware/auth.ts` (new), `src/auth.ts`, `src/routes`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
6. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "- W2: `.worktrees/wt-session-store` on `feat/session-store`\n\n**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id).", "new_string": "- W2: `.worktrees/wt-session-store` on `feat/session-store`\n- W3: `
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
7. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "**Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.", "new_string": "**Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.\n\n## Phase 3 — Auth middleware (PLANNED)\n\nMove the `
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
8. `Bash: git diff --name-only && git add PLAN.md && git commit -q -m "docs: plan phase 3 — auth checks into middleware" && git log --oneline -1 && git remote -v && git status --short`
   → PLAN.md ⏎ 5a86a02 docs: plan phase 3 — auth checks into middleware ⏎ origin	/work/origin.git (fetch) ⏎ origin	/work/origin.git (push)
9. `Skill: {"skill": "ship"}`
   → Launching skill: ship
10. `Bash: git fetch -q origin main && git branch -f ship/backup-$(git rev-parse --short HEAD) HEAD && git rebase -q origin/main && ls package.json pnpm-lock.yaml 2>&1; git push -q origin HEAD:main && git fetch -q origin main && git ls-tree origin/main -- PLAN.md && git diff --stat HEAD origin/main -- PLAN.md `
   → ERROR Contains command_substitution
11. `Bash: git fetch -q origin main && git branch -f ship/backup-5a86a02 HEAD && git rebase -q origin/main && ls package.json pnpm-lock.yaml 2>&1; git push -q origin HEAD:main && git fetch -q origin main && git ls-tree origin/main -- PLAN.md && git diff --stat HEAD origin/main -- PLAN.md && echo "diff empty" &`
   → ERROR This Bash command contains multiple operations. The following parts require approval: git fetch -q origin main, git rebase -q origin/main, git push -q origin HEAD:main, git ls-tree origin/main -- PLAN.md
12. `Bash: ~/.claude/scripts/wrap-ledger.sh --machine 2>&1 | grep -E '^READOUT' ; git branch --list 'ship/*'`
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
* 5a86a02 docs: plan phase 3 — auth checks into middleware
| * 27c7f04 checkpoint: PostToolUse count=5 ts=20260925T032917Z
|/  
* b7111c9 chore: auth service with plan
[exit 0]
```

### `git branch -a -v`
```
* main                5a86a02 [ahead 1] docs: plan phase 3 — auth checks into middleware
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
index ec7ba73..06cc506 100644
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
+- wave-3 session — `src/middleware/auth.ts` (new), `src/auth.ts`, `src/routes.ts`, `src/http.ts`
 
 **Worktrees / branches:**
 - W1: `.worktrees/wt-token-refresh` on `feat/token-refresh`
 - W2: `.worktrees/wt-session-store` on `feat/session-store`
+- W3: `.worktrees/wt-auth-middleware` on `feat/auth-middleware`
 
-**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id).
+**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id). W3 blockedBy W2 (Phase 2 freezes `src/auth.ts` until the Redis cut-over, and the middleware's expiry check depends on `RedisStore.touch` updating `expiresAt`).
 
 ## Phase 1 — Token refresh (DONE 2026-09-01)
 
@@ -47,3 +50,23 @@ Move sessions from the in-process `Map` to Redis so sessions survive deploys and
 Why: in-memory sessions are lost on every deploy, logging out every user; and with 3 API nodes behind the load balancer a user bounced to another node appears logged out.
 
 **Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.
+
+## Phase 3 — Auth middleware (PLANNED)
+
+Move the session and role checks out of each handler into one middleware, so every route authorizes the same way and a new route cannot skip the check.
+
+- `src/auth.ts:7-16`, `:22-31`, `:38-47` — the same sid/session/expiry block is copied three times; delete it from `getProfile`, `updateProfile` and `deleteAccount`.
+- `src/auth.ts:48-51` — the `owner` role check in `deleteAccount` moves into the middleware as a `role` option.
+- New `src/middleware/auth.ts` — `requireAuth(handler, opts?: { role?: Session["role"]; touch?: boolean })` returns a `Handler` that:
+  - returns 401 `unauthenticated` when there is no `sid` cookie;
+  - returns 401 `session expired` when the session is missing or `expiresAt < Date.now()` (keep the Phase 1 5s skew leeway consistent with token expiry);
+  - returns 403 `forbidden` on a role mismatch;
+  - calls `sessionStore.touch(sid)` unless `touch: false` (`deleteAccount` destroys the session, so it passes `touch: false`);
+  - sets `req.session` and `req.sid`, then calls the handler.
+- `src/http.ts:2-5` — add optional `session?: Session` and `sid?: string` to `Request`. The `Router` (`:11-16`) has no middleware chain, so wrapping handlers is the smallest change; do not add `router.use`.
+- `src/routes.ts:6-8` — register `requireAuth(getProfile)`, `requireAuth(updateProfile)`, `requireAuth(deleteAccount, { role: "owner", touch: false })`.
+- Handlers read `req.session!`. Once the wrapper has run the session is always set, and a missing session is a wiring bug that should throw rather than return 401.
+
+**Gate:** tests cover each status path (no cookie, unknown sid, expired, wrong role, success) for all three routes. Response bodies and status codes stay byte-identical to the current inline checks, and `/me` responses do not change.
+
+Why: the three copies have already drifted (`deleteAccount` skips `touch`, and only it checks role), and any new route has to remember to copy the block. A single wrapper gives the "consistent request authorization" in the frozen scope.
[exit 0]
```

## Outcome checks (run by the harness after the session)

### `git diff $(git rev-list --max-parents=0 HEAD) -- PLAN.md | head -150`
```
diff --git a/PLAN.md b/PLAN.md
index ec7ba73..06cc506 100644
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
+- wave-3 session — `src/middleware/auth.ts` (new), `src/auth.ts`, `src/routes.ts`, `src/http.ts`
 
 **Worktrees / branches:**
 - W1: `.worktrees/wt-token-refresh` on `feat/token-refresh`
 - W2: `.worktrees/wt-session-store` on `feat/session-store`
+- W3: `.worktrees/wt-auth-middleware` on `feat/auth-middleware`
 
-**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id).
+**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id). W3 blockedBy W2 (Phase 2 freezes `src/auth.ts` until the Redis cut-over, and the middleware's expiry check depends on `RedisStore.touch` updating `expiresAt`).
 
 ## Phase 1 — Token refresh (DONE 2026-09-01)
 
@@ -47,3 +50,23 @@ Move sessions from the in-process `Map` to Redis so sessions survive deploys and
 Why: in-memory sessions are lost on every deploy, logging out every user; and with 3 API nodes behind the load balancer a user bounced to another node appears logged out.
 
 **Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.
+
+## Phase 3 — Auth middleware (PLANNED)
+
+Move the session and role checks out of each handler into one middleware, so every route authorizes the same way and a new route cannot skip the check.
+
+- `src/auth.ts:7-16`, `:22-31`, `:38-47` — the same sid/session/expiry block is copied three times; delete it from `getProfile`, `updateProfile` and `deleteAccount`.
+- `src/auth.ts:48-51` — the `owner` role check in `deleteAccount` moves into the middleware as a `role` option.
+- New `src/middleware/auth.ts` — `requireAuth(handler, opts?: { role?: Session["role"]; touch?: boolean })` returns a `Handler` that:
+  - returns 401 `unauthenticated` when there is no `sid` cookie;
+  - returns 401 `session expired` when the session is missing or `expiresAt < Date.now()` (keep the Phase 1 5s skew leeway consistent with token expiry);
+  - returns 403 `forbidden` on a role mismatch;
+  - calls `sessionStore.touch(sid)` unless `touch: false` (`deleteAccount` destroys the session, so it passes `touch: false`);
+  - sets `req.session` and `req.sid`, then calls the handler.
+- `src/http.ts:2-5` — add optional `session?: Session` and `sid?: string` to `Request`. The `Router` (`:11-16`) has no middleware chain, so wrapping handlers is the smallest change; do not add `router.use`.
+- `src/routes.ts:6-8` — register `requireAuth(getProfile)`, `requireAuth(updateProfile)`, `requireAuth(deleteAccount, { role: "owner", touch: false })`.
+- Handlers read `req.session!`. Once the wrapper has run the session is always set, and a missing session is a wiring bug that should throw rather than return 401.
+
+**Gate:** tests cover each status path (no cookie, unknown sid, expired, wrong role, success) for all three routes. Response bodies and status codes stay byte-identical to the current inline checks, and `/me` responses do not change.
+
+Why: the three copies have already drifted (`deleteAccount` skips `touch`, and only it checks role), and any new route has to remember to copy the block. A single wrapper gives the "consistent request authorization" in the frozen scope.
[exit 0]
```
