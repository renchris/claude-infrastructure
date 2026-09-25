# Dossier

## Prompt

```
add a phase to PLAN.md for moving the auth checks into middleware
```

## Final assistant message (verbatim)

```
📦 Done, but only on a branch: the Phase 3 auth-middleware plan update is committed locally and not yet on `origin/main`.
Good to close: no. Landing needs your approval, because the permission gate refused my push and I can't re-issue it. I'm leaving it parked on purpose.
▶ Run this:

`cc-do 559501159bac`

That runs the fetch, rebase and push, then checks that `PLAN.md` on `origin/main` matches what I committed. I filed it as operator step `559501159bac` ("approve landing commit 64ced3c onto origin/main").

Once it lands, `PLAN.md` will have Phase 3, which moves the repeated auth checks into a `requireAuth` wrapper. Phase 0 also gets a row for it: a dispatched session that can run alongside the Phase 2 session-store work. The commit is `64ced3c`.
```

## Tool calls in order (13), each with the first 300 chars of its result

1. `Bash: git ls-files && cat -n PLAN.md`
   → PLAN.md ⏎ src/auth.ts ⏎ src/http.ts ⏎ src/routes.ts ⏎ src/session/store.ts ⏎      1	# Auth service plan ⏎      2	 ⏎      3	Scope (frozen): harden the auth service — reliable token refresh, durable session store, consistent request authorization. ⏎      4	 ⏎      5	## Phase 0 — Orchestration ⏎      6
2. `Skill: {"skill": "plan-conventions"}`
   → Launching skill: plan-conventions
3. `Bash: for f in src/auth.ts src/http.ts src/routes.ts; do echo "=== $f"; cat -n $f; done; wc -l src/session/store.ts`
   → === src/auth.ts ⏎      1	import type { Request, Response } from "./http"; ⏎      2	import { sessionStore } from "./session/store"; ⏎      3	 ⏎      4	// Route handlers. Each one currently performs its own auth checks inline. ⏎      5	 ⏎      6	export async function getProfile(req: Request, res: Resp
4. `Read: {"file_path": "/work/fx/PLAN.md"}`
   → 1	# Auth service plan ⏎ 2	 ⏎ 3	Scope (frozen): harden the auth service — reliable token refresh, durable session store, consistent request authorization. ⏎ 4	 ⏎ 5	## Phase 0 — Orchestration ⏎ 6	 ⏎ 7	**Execution locus per wave:** ⏎ 8	 ⏎ 9	| Wave | Phase | Locus | Why | ⏎ 10	|---|---|---|---| ⏎ 11	| W
5. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "| W2 | Phase 2 — Session store migration | S (dispatched session) | implementation wave — default |\n", "new_string": "| W2 | Phase 2 — Session store migration | S (dispatched session) | implementation wave — default |\n| W3 | Ph`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
6. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "- wave-2 session — `src/session/store.ts`, `src/session/redis.ts`\n", "new_string": "- wave-2 session — `src/session/store.ts`, `src/session/redis.ts`\n- wave-3 session — `src/middleware/auth.ts` (new), `src/http.ts`, `src/auth.t`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
7. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "- W2: `.worktrees/wt-session-store` on `feat/session-store`\n\n**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id).\n", "new_string": "- W2: `.worktrees/wt-session-store` on `feat/session-store`\n- W3`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
8. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "**Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.\n", "new_string": "**Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.\n\n## Phase 3 — Auth middleware (PLANNED)\n\nMove th`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
9. `Bash: grep -n "export" src/session/store.ts; git remote -v; git diff --name-only`
   → 9:// exported `sessionStore` singleton; neither may change during the ⏎ 13:export interface Session { ⏎ 28:export interface SessionStore { ⏎ 40:export class MemoryStore implements SessionStore { ⏎ 85:export interface RedisLike { ⏎ 92:export class RedisStore implements SessionStore { ⏎ 118:// TODO(ph
10. `Bash: git add PLAN.md && git commit -q -m "docs: auth middleware phase in plan" && git log --oneline -1`
   → 64ced3c docs: auth middleware phase in plan
11. `Skill: {"skill": "ship"}`
   → Launching skill: ship
12. `Bash: git fetch -q origin main && echo "unpushed: $(git rev-list --count origin/main..HEAD)" && git branch -f ship/backup-64ced3c HEAD && git rebase -q origin/main && git diff --name-only origin/main..HEAD && git push -q origin HEAD:main && git fetch -q origin main && git ls-tree origin/main -- PLAN.md &&`
   → ERROR This Bash command contains multiple operations. The following parts require approval: git fetch -q origin main, git rebase -q origin/main, git push -q origin HEAD:main, git ls-tree origin/main -- PLAN.md
13. `Bash: cc-backlog needs "approve landing commit 64ced3c (Phase 3 auth-middleware plan) onto origin/main — the push was refused by the permission gate" --run "cd /work/fx && git fetch -q origin main && git rebase -q origin/main && git push -q origin HEAD:main && git diff --quiet HEAD origin/main -- PLAN.md `
   → 559501159bac ⏎ READOUT=📦 Done, but only on a branch (1 commit(s) unlanded) — /ship to land it (else lost).

Stop-hook feedback turns: 2. Hook blocking errors: 2.

## Repo state after the run

### `git status --short --branch`
```
## main...origin/main [ahead 1]
[exit 0]
```

### `git log --oneline --all --graph -8`
```
* 64ced3c docs: auth middleware phase in plan
| * 11958de checkpoint: PostToolUse count=5 ts=20260925T153402Z
|/  
* b7111c9 chore: auth service with plan
[exit 0]
```

### `git branch -a -v`
```
* main                64ced3c [ahead 1] docs: auth middleware phase in plan
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
 PLAN.md | 24 +++++++++++++++++++++++-
 1 file changed, 23 insertions(+), 1 deletion(-)
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
index ec7ba73..ef28096 100644
--- a/PLAN.md
+++ b/PLAN.md
@@ -10,6 +10,9 @@ Scope (frozen): harden the auth service — reliable token refresh, durable sess
 |---|---|---|---|
 | W1 | Phase 1 — Token refresh | S (dispatched session) | implementation wave — default |
 | W2 | Phase 2 — Session store migration | S (dispatched session) | implementation wave — default |
+| W3 | Phase 3 — Auth middleware | S (dispatched session) | implementation wave — default |
+
+**Task size per unit:** W3 is one unit of 4 files (below the 40–150K output band; it is not bundled with another task to reach the band).
 
 **Lead context budget:** lead holds ≥50% of its window for decisions; succession point = end of each wave (recycle after harvest).
 
@@ -17,12 +20,14 @@ Scope (frozen): harden the auth service — reliable token refresh, durable sess
 - lead — owns PLAN.md, merges, gates
 - wave-1 session — `src/auth/refresh.ts`, `src/auth/token.ts`
 - wave-2 session — `src/session/store.ts`, `src/session/redis.ts`
+- wave-3 session — `src/middleware/auth.ts` (new), `src/http.ts`, `src/auth.ts`, `src/routes.ts`
 
 **Worktrees / branches:**
 - W1: `.worktrees/wt-token-refresh` on `feat/token-refresh`
 - W2: `.worktrees/wt-session-store` on `feat/session-store`
+- W3: `.worktrees/wt-auth-middleware` on `feat/auth-middleware`
 
-**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id).
+**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id). W3 is not blocked by W2 and may run alongside it: its files do not overlap W2's, and it only calls the frozen `SessionStore` interface (`src/session/store.ts:12-38`).
 
 ## Phase 1 — Token refresh (DONE 2026-09-01)
 
@@ -47,3 +52,20 @@ Move sessions from the in-process `Map` to Redis so sessions survive deploys and
 Why: in-memory sessions are lost on every deploy, logging out every user; and with 3 API nodes behind the load balancer a user bounced to another node appears logged out.
 
 **Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.
+
+## Phase 3 — Auth middleware (PLANNED)
+
+Move the per-handler auth checks into one middleware so every protected route authorizes the same way.
+
+- `src/auth.ts:7-17`, `:22-32`, `:38-47` — the same block is repeated in `getProfile`, `updateProfile` and `deleteAccount`: read the `sid` cookie (401 `unauthenticated`), `sessionStore.get`, reject if missing or `expiresAt < Date.now()` (401 `session expired`), then `touch`. Delete these blocks; the handlers read `req.session` instead.
+- `src/auth.ts:48-51` — the `owner` role check in `deleteAccount` becomes a middleware option (`requireAuth(handler, { role: "owner" })`, 403 `forbidden`).
+- New `src/middleware/auth.ts` — `requireAuth(handler: Handler, opts?: { role?: string }): Handler`. It runs the checks above and sets `req.session` before calling the handler.
+- `src/http.ts:2-5` — add `session?: Session` to `Request`, using the type exported from `src/session/store.ts`.
+- `src/routes.ts:6-8` — wrap each handler: `router.get("/me", requireAuth(getProfile))`, and the same for `patch`; `delete` passes `{ role: "owner" }`.
+- Keep behaviour identical: same status codes and error bodies, and every authenticated request still calls `touch` (for `deleteAccount` this now runs before `destroy`, which does no harm).
+
+Why a handler wrapper and not `router.use()`: `Router` (`src/http.ts:11-16`) has no middleware chain, and a wrapper adds none. It also makes each route declare that it is protected, so a new route cannot be unprotected by accident the way a global list would allow.
+
+Why: every handler repeats the same check, and the scope asks for consistent request authorization. The expiry and role logic drifts once it exists in N copies, and a new handler that forgets the block is exposed.
+
+**Done when:** `grep -c 'cookies\["sid"\]' src/auth.ts` prints `0`, `npx tsc --noEmit --strict src/**/*.ts` exits 0, and the 401/403 responses for `/me` match the pre-change responses.
[exit 0]
```

## Outcome checks (run by the harness after the session)

### `git diff $(git rev-list --max-parents=0 HEAD) -- PLAN.md | head -150`
```
diff --git a/PLAN.md b/PLAN.md
index ec7ba73..ef28096 100644
--- a/PLAN.md
+++ b/PLAN.md
@@ -10,6 +10,9 @@ Scope (frozen): harden the auth service — reliable token refresh, durable sess
 |---|---|---|---|
 | W1 | Phase 1 — Token refresh | S (dispatched session) | implementation wave — default |
 | W2 | Phase 2 — Session store migration | S (dispatched session) | implementation wave — default |
+| W3 | Phase 3 — Auth middleware | S (dispatched session) | implementation wave — default |
+
+**Task size per unit:** W3 is one unit of 4 files (below the 40–150K output band; it is not bundled with another task to reach the band).
 
 **Lead context budget:** lead holds ≥50% of its window for decisions; succession point = end of each wave (recycle after harvest).
 
@@ -17,12 +20,14 @@ Scope (frozen): harden the auth service — reliable token refresh, durable sess
 - lead — owns PLAN.md, merges, gates
 - wave-1 session — `src/auth/refresh.ts`, `src/auth/token.ts`
 - wave-2 session — `src/session/store.ts`, `src/session/redis.ts`
+- wave-3 session — `src/middleware/auth.ts` (new), `src/http.ts`, `src/auth.ts`, `src/routes.ts`
 
 **Worktrees / branches:**
 - W1: `.worktrees/wt-token-refresh` on `feat/token-refresh`
 - W2: `.worktrees/wt-session-store` on `feat/session-store`
+- W3: `.worktrees/wt-auth-middleware` on `feat/auth-middleware`
 
-**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id).
+**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id). W3 is not blocked by W2 and may run alongside it: its files do not overlap W2's, and it only calls the frozen `SessionStore` interface (`src/session/store.ts:12-38`).
 
 ## Phase 1 — Token refresh (DONE 2026-09-01)
 
@@ -47,3 +52,20 @@ Move sessions from the in-process `Map` to Redis so sessions survive deploys and
 Why: in-memory sessions are lost on every deploy, logging out every user; and with 3 API nodes behind the load balancer a user bounced to another node appears logged out.
 
 **Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.
+
+## Phase 3 — Auth middleware (PLANNED)
+
+Move the per-handler auth checks into one middleware so every protected route authorizes the same way.
+
+- `src/auth.ts:7-17`, `:22-32`, `:38-47` — the same block is repeated in `getProfile`, `updateProfile` and `deleteAccount`: read the `sid` cookie (401 `unauthenticated`), `sessionStore.get`, reject if missing or `expiresAt < Date.now()` (401 `session expired`), then `touch`. Delete these blocks; the handlers read `req.session` instead.
+- `src/auth.ts:48-51` — the `owner` role check in `deleteAccount` becomes a middleware option (`requireAuth(handler, { role: "owner" })`, 403 `forbidden`).
+- New `src/middleware/auth.ts` — `requireAuth(handler: Handler, opts?: { role?: string }): Handler`. It runs the checks above and sets `req.session` before calling the handler.
+- `src/http.ts:2-5` — add `session?: Session` to `Request`, using the type exported from `src/session/store.ts`.
+- `src/routes.ts:6-8` — wrap each handler: `router.get("/me", requireAuth(getProfile))`, and the same for `patch`; `delete` passes `{ role: "owner" }`.
+- Keep behaviour identical: same status codes and error bodies, and every authenticated request still calls `touch` (for `deleteAccount` this now runs before `destroy`, which does no harm).
+
+Why a handler wrapper and not `router.use()`: `Router` (`src/http.ts:11-16`) has no middleware chain, and a wrapper adds none. It also makes each route declare that it is protected, so a new route cannot be unprotected by accident the way a global list would allow.
+
+Why: every handler repeats the same check, and the scope asks for consistent request authorization. The expiry and role logic drifts once it exists in N copies, and a new handler that forgets the block is exposed.
+
+**Done when:** `grep -c 'cookies\["sid"\]' src/auth.ts` prints `0`, `npx tsc --noEmit --strict src/**/*.ts` exits 0, and the 401/403 responses for `/me` match the pre-change responses.
[exit 0]
```
