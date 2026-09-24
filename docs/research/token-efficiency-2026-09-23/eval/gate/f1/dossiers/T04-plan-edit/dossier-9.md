# Dossier

## Prompt

```
add a phase to PLAN.md for moving the auth checks into middleware
```

## Final assistant message (verbatim)

```
📦 I've added a new Phase 3 for the auth middleware to `PLAN.md` and committed it as `d5a7b10`, but it isn't on trunk yet: the push to `origin/main` needs your approval.

Good to close: no — the plan is written and committed, but it isn't landed until you approve the push.

▶ Run this:

`git -C /work/fx push origin HEAD:main`

What Phase 3 plans:
- **One shared check:** the same cookie, session-lookup and expiry check is copied into all three handlers in `src/auth.ts` (lines 7-17, 22-32, 38-47). Phase 3 replaces the copies with two wrappers in a new `src/middleware/auth.ts`: `requireSession` and `requireRole("owner")`.
- **No router changes:** the wrappers are applied where routes are registered in `src/routes.ts`, because the existing `Router` has no middleware chain.
- **Handlers get the session from the request:** `Request` gains a `session?` field.
- **Clients see no difference:** status codes and error bodies stay exactly the same. The one behaviour change is that `deleteAccount` will now refresh the session just before destroying it, which is harmless.
- **Done when:** `src/auth.ts` no longer reads the `sid` cookie, and tests cover the missing, unknown, expired, wrong-role and happy-path cases for all three routes.

I also added a W3 row to Phase 0 with its own worktree and branch. W3 can run alongside W2 (the session-store migration): they share no files, and W3 only relies on the session-store interface, which Phase 2 has already frozen.

The repo has no build, lint or test tooling, so this docs-only change had no checks to run.
```

## Tool calls in order (12), each with the first 300 chars of its result

1. `Bash: git ls-files && cat -n PLAN.md`
   → PLAN.md ⏎ src/auth.ts ⏎ src/http.ts ⏎ src/routes.ts ⏎ src/session/store.ts ⏎      1	# Auth service plan ⏎      2	 ⏎      3	Scope (frozen): harden the auth service — reliable token refresh, durable session store, consistent request authorization. ⏎      4	 ⏎      5	## Phase 0 — Orchestration ⏎      6
2. `Bash: for f in src/auth.ts src/http.ts src/routes.ts; do echo "=== $f"; cat -n $f; done; echo "=== store"; wc -l src/session/store.ts`
   → === src/auth.ts ⏎      1	import type { Request, Response } from "./http"; ⏎      2	import { sessionStore } from "./session/store"; ⏎      3	 ⏎      4	// Route handlers. Each one currently performs its own auth checks inline. ⏎      5	 ⏎      6	export async function getProfile(req: Request, res: Resp
3. `Bash: sed -n 1,40p src/session/store.ts; grep -n "export" src/session/store.ts`
   → // Session store. ⏎ // ⏎ // Sessions are keyed by the opaque `sid` cookie. Today they live in an ⏎ // in-process Map (MemoryStore), which is lost on every deploy and is not ⏎ // shared between the three API nodes. Phase 2 of PLAN.md replaces it with ⏎ // RedisStore behind the same SessionStore inter
4. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "| W2 | Phase 2 — Session store migration | S (dispatched session) | implementation wave — default |\n", "new_string": "| W2 | Phase 2 — Session store migration | S (dispatched session) | implementation wave — default |\n| W3 | Ph`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
5. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "- wave-2 session — `src/session/store.ts`, `src/session/redis.ts`\n", "new_string": "- wave-2 session — `src/session/store.ts`, `src/session/redis.ts`\n- wave-3 session — `src/middleware/auth.ts` (new), `src/auth.ts`, `src/http.t`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
6. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "- W2: `.worktrees/wt-session-store` on `feat/session-store`\n\n**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id).", "new_string": "- W2: `.worktrees/wt-session-store` on `feat/session-store`\n- W3: `
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
7. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "**Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.", "new_string": "**Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.\n\n## Phase 3 — Auth middleware (PLANNED)\n\nMove the `
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
8. `Bash: git diff --name-only && git add PLAN.md && git commit -qm "docs: auth middleware phase in plan" && git log --oneline -1 && git remote -v | head -1; git status --short`
   → PLAN.md ⏎ d5a7b10 docs: auth middleware phase in plan ⏎ origin	/work/origin.git (fetch)
9. `Skill: {"skill": "ship"}`
   → Launching skill: ship
10. `Bash: T=$(git symbolic-ref --quiet refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@'); T=${T:-main}; echo trunk=$T; git fetch -q origin $T && git rev-list --count origin/$T..HEAD && git branch -f ship/backup-$(git rev-parse --short HEAD) HEAD && git rebase -q origin/$T && ls package.json pnpm-loc`
   → trunk=main ⏎ 1 ⏎ ls: package.json: No such file or directory ⏎ ls: pnpm-lock.yaml: No such file or directory ⏎ ls: tsconfig.json: No such file or directory ⏎  PLAN.md | 23 ++++++++++++++++++++++- ⏎  1 file changed, 22 insertions(+), 1 deletion(-)
11. `Bash: S=$(git rev-parse HEAD) && git push -q origin HEAD:main && git fetch -q origin main && git ls-tree origin/main -- PLAN.md && git diff --quiet $S origin/main -- PLAN.md && echo CONTENT-OK && git branch -D ship/backup-$(git rev-parse --short HEAD) && git status --short && git rev-list --count origin/m`
   → ERROR Contains simple_expansion
12. `Bash: git push -q origin HEAD:main && git fetch -q origin main && git ls-tree origin/main -- PLAN.md && git diff --quiet HEAD origin/main -- PLAN.md && echo CONTENT-OK && git branch -D ship/backup-d5a7b10 && git status --short && git rev-list --count origin/main..HEAD`
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
* d5a7b10 docs: auth middleware phase in plan
| * fac5a18 checkpoint: PostToolUse count=5 ts=20260924T154551Z
|/  
* b7111c9 chore: auth service with plan
[exit 0]
```

### `git branch -a -v`
```
* main                d5a7b10 [ahead 1] docs: auth middleware phase in plan
  ship/backup-d5a7b10 d5a7b10 docs: auth middleware phase in plan
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
index ec7ba73..a773f3b 100644
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
+- wave-3 session — `src/middleware/auth.ts` (new), `src/auth.ts`, `src/http.ts`, `src/routes.ts`
 
 **Worktrees / branches:**
 - W1: `.worktrees/wt-token-refresh` on `feat/token-refresh`
 - W2: `.worktrees/wt-session-store` on `feat/session-store`
+- W3: `.worktrees/wt-auth-middleware` on `feat/auth-middleware`
 
-**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id).
+**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id). W3 has no file overlap with W2 and depends only on the frozen `SessionStore` interface, so it may run in parallel with W2.
 
 ## Phase 1 — Token refresh (DONE 2026-09-01)
 
@@ -47,3 +50,21 @@ Move sessions from the in-process `Map` to Redis so sessions survive deploys and
 Why: in-memory sessions are lost on every deploy, logging out every user; and with 3 API nodes behind the load balancer a user bounced to another node appears logged out.
 
 **Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.
+
+## Phase 3 — Auth middleware (PLANNED)
+
+Move the per-handler auth checks into reusable middleware so every protected route authorizes the same way.
+
+- `src/auth.ts:7-17`, `:22-32`, `:38-47` — the same cookie → `sessionStore.get` → expiry check is copy-pasted into `getProfile`, `updateProfile` and `deleteAccount`. Delete these blocks; handlers read the session from the request instead.
+- `src/auth.ts:48-51` — the `role !== "owner"` check in `deleteAccount` becomes `requireRole("owner")`.
+- `src/http.ts:2-5` — add `session?: Session` to `Request` (import `Session` from `src/session/store.ts`; interface itself unchanged).
+- New `src/middleware/auth.ts`:
+  - `requireSession(handler: Handler): Handler` — reads `sid`, loads the session, rejects missing (401 `unauthenticated`) or expired (401 `session expired`), calls `sessionStore.touch(sid)`, sets `req.session`, then calls `handler`.
+  - `requireRole(role: Session["role"], handler: Handler): Handler` — composes over `requireSession`; 403 `forbidden` on mismatch.
+- `src/routes.ts:6-8` — wrap at registration: `requireSession(getProfile)`, `requireSession(updateProfile)`, `requireRole("owner", deleteAccount)`. `Router` (`src/http.ts:11-16`) has no middleware chain, so wrapping handlers is the fit — no router changes.
+- Keep response codes and error bodies byte-identical; clients match on them.
+- Behaviour change to note: `deleteAccount` does not `touch` today; under the middleware it will, just before `destroy` — harmless.
+
+Why: three copies of the same check drift independently (only one of them checks role), and every new route must remember to re-implement it. One middleware makes "consistent request authorization" from the frozen scope true by construction.
+
+**Done when:** no `req.cookies["sid"]` read remains in `src/auth.ts`; tests cover missing cookie, unknown sid, expired session, wrong role, and the happy path for each of the three routes.
[exit 0]
```

## Outcome checks (run by the harness after the session)

### `git diff $(git rev-list --max-parents=0 HEAD) -- PLAN.md | head -150`
```
diff --git a/PLAN.md b/PLAN.md
index ec7ba73..a773f3b 100644
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
+- wave-3 session — `src/middleware/auth.ts` (new), `src/auth.ts`, `src/http.ts`, `src/routes.ts`
 
 **Worktrees / branches:**
 - W1: `.worktrees/wt-token-refresh` on `feat/token-refresh`
 - W2: `.worktrees/wt-session-store` on `feat/session-store`
+- W3: `.worktrees/wt-auth-middleware` on `feat/auth-middleware`
 
-**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id).
+**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id). W3 has no file overlap with W2 and depends only on the frozen `SessionStore` interface, so it may run in parallel with W2.
 
 ## Phase 1 — Token refresh (DONE 2026-09-01)
 
@@ -47,3 +50,21 @@ Move sessions from the in-process `Map` to Redis so sessions survive deploys and
 Why: in-memory sessions are lost on every deploy, logging out every user; and with 3 API nodes behind the load balancer a user bounced to another node appears logged out.
 
 **Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.
+
+## Phase 3 — Auth middleware (PLANNED)
+
+Move the per-handler auth checks into reusable middleware so every protected route authorizes the same way.
+
+- `src/auth.ts:7-17`, `:22-32`, `:38-47` — the same cookie → `sessionStore.get` → expiry check is copy-pasted into `getProfile`, `updateProfile` and `deleteAccount`. Delete these blocks; handlers read the session from the request instead.
+- `src/auth.ts:48-51` — the `role !== "owner"` check in `deleteAccount` becomes `requireRole("owner")`.
+- `src/http.ts:2-5` — add `session?: Session` to `Request` (import `Session` from `src/session/store.ts`; interface itself unchanged).
+- New `src/middleware/auth.ts`:
+  - `requireSession(handler: Handler): Handler` — reads `sid`, loads the session, rejects missing (401 `unauthenticated`) or expired (401 `session expired`), calls `sessionStore.touch(sid)`, sets `req.session`, then calls `handler`.
+  - `requireRole(role: Session["role"], handler: Handler): Handler` — composes over `requireSession`; 403 `forbidden` on mismatch.
+- `src/routes.ts:6-8` — wrap at registration: `requireSession(getProfile)`, `requireSession(updateProfile)`, `requireRole("owner", deleteAccount)`. `Router` (`src/http.ts:11-16`) has no middleware chain, so wrapping handlers is the fit — no router changes.
+- Keep response codes and error bodies byte-identical; clients match on them.
+- Behaviour change to note: `deleteAccount` does not `touch` today; under the middleware it will, just before `destroy` — harmless.
+
+Why: three copies of the same check drift independently (only one of them checks role), and every new route must remember to re-implement it. One middleware makes "consistent request authorization" from the frozen scope true by construction.
+
+**Done when:** no `req.cookies["sid"]` read remains in `src/auth.ts`; tests cover missing cookie, unknown sid, expired session, wrong role, and the happy path for each of the three routes.
[exit 0]
```
