# Dossier

## Prompt

```
add a phase to PLAN.md for moving the auth checks into middleware
```

## Final assistant message (verbatim)

```
📦 Done, but only on a branch: the Phase 3 auth-middleware plan is committed as `dd43a74` but not pushed to `origin/main`.
Good to close: no. The only thing left is the push, and it needs your approval: it was refused at the permission prompt, and I can't retry a refused command. I've filed it as `0546d98d3442` ("push the auth-middleware plan commit to origin/main").
▶ Run this:

`git -C /work/fx push origin HEAD:main`

- **What changed:** PLAN.md has a new Phase 3 for moving the auth checks into middleware, with file and line targets and the done criteria. Phase 0 has a matching wave 3 row. The plan also notes that the Redis store's `touch` never updates `expiresAt`, so Phase 3 has to wait for the Phase 2 Redis cutover.
- **After the push:** you can delete the backup branch `ship/backup-dd43a74`.
```

## Tool calls in order (16), each with the first 300 chars of its result

1. `Bash: git ls-files && echo ---- && cat -n PLAN.md`
   → PLAN.md ⏎ src/auth.ts ⏎ src/http.ts ⏎ src/routes.ts ⏎ src/session/store.ts ⏎ ---- ⏎      1	# Auth service plan ⏎      2	 ⏎      3	Scope (frozen): harden the auth service — reliable token refresh, durable session store, consistent request authorization. ⏎      4	 ⏎      5	## Phase 0 — Orchestration ⏎
2. `Bash: for f in src/auth.ts src/http.ts src/routes.ts; do echo "==== $f"; cat -n $f; done; echo ====; wc -l src/session/store.ts`
   → ERROR Exit code 1 ⏎ ==== src/auth.ts ⏎      1	import type { Request, Response } from "./http"; ⏎      2	import { sessionStore } from "./session/store"; ⏎      3	 ⏎      4	// Route handlers. Each one currently performs its own auth checks inline. ⏎      5	 ⏎      6	export async function getProfile(req: Req
3. `Bash: cat -n src/session/store.ts`
   → 1	// Session store. ⏎      2	// ⏎      3	// Sessions are keyed by the opaque `sid` cookie. Today they live in an ⏎      4	// in-process Map (MemoryStore), which is lost on every deploy and is not ⏎      5	// shared between the three API nodes. Phase 2 of PLAN.md replaces it with ⏎      6	// RedisSto
4. `Read: {"file_path": "/work/fx/PLAN.md"}`
   → 1	# Auth service plan ⏎ 2	 ⏎ 3	Scope (frozen): harden the auth service — reliable token refresh, durable session store, consistent request authorization. ⏎ 4	 ⏎ 5	## Phase 0 — Orchestration ⏎ 6	 ⏎ 7	**Execution locus per wave:** ⏎ 8	 ⏎ 9	| Wave | Phase | Locus | Why | ⏎ 10	|---|---|---|---| ⏎ 11	| W
5. `Bash: git remote -v; ls -a`
   → origin	/work/origin.git (fetch) ⏎ origin	/work/origin.git (push) ⏎ . ⏎ .. ⏎ .claude ⏎ .claude-plans ⏎ .claude-tasks ⏎ .git ⏎ PLAN.md ⏎ src
6. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "| W2 | Phase 2 — Session store migration | S (dispatched session) | implementation wave — default |\n", "new_string": "| W2 | Phase 2 — Session store migration | S (dispatched session) | implementation wave — default |\n| W3 | Ph`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
7. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "- wave-2 session — `src/session/store.ts`, `src/session/redis.ts`\n", "new_string": "- wave-2 session — `src/session/store.ts`, `src/session/redis.ts`\n- wave-3 session — new `src/middleware/auth.ts`, `src/auth.ts`, `src/http.ts``
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
8. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "- W2: `.worktrees/wt-session-store` on `feat/session-store`\n\n**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id).\n", "new_string": "- W2: `.worktrees/wt-session-store` on `feat/session-store`\n- W3`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
9. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "**Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.\n", "new_string": "**Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.\n\n## Phase 3 — Auth middleware (PLANNED)\n\nMove th`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
10. `Bash: git diff --name-only && git add PLAN.md && git commit -q -m "docs: auth middleware phase in plan" && git log --oneline -1 && git status --short`
   → PLAN.md ⏎ dd43a74 docs: auth middleware phase in plan
11. `Skill: {"skill": "ship"}`
   → Launching skill: ship
12. `Bash: T=$(git symbolic-ref --quiet refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@'); T=${T:-main}; echo trunk=$T; git fetch -q origin $T && git branch -f ship/backup-$(git rev-parse --short HEAD) HEAD && git rebase -q origin/$T && echo unpushed=$(git rev-list --count origin/$T..HEAD) && git dif`
   → trunk=main ⏎ unpushed=1 ⏎ PLAN.md
13. `Bash: S=$(git rev-parse HEAD) && git push -q origin HEAD:main && git fetch -q origin main && git ls-tree origin/main -- PLAN.md && git diff --quiet $S origin/main -- PLAN.md && echo CONTENT_OK && git branch -D ship/backup-dd43a74 && (~/.claude/scripts/wrap-ledger.sh --machine 2>&1 | grep -E '^READOUT' || `
   → ERROR Contains simple_expansion
14. `Bash: git push -q origin HEAD:main && git fetch -q origin main && git ls-tree origin/main -- PLAN.md && git diff --quiet HEAD origin/main -- PLAN.md && echo CONTENT_OK && git branch -D ship/backup-dd43a74`
   → ERROR This Bash command contains multiple operations. The following parts require approval: git push -q origin HEAD:main, git fetch -q origin main, git ls-tree origin/main -- PLAN.md
15. `Bash: ~/.claude/scripts/wrap-ledger.sh --machine 2>&1 | grep -E '^READOUT' || echo "ledger unavailable"`
   → READOUT=📦 Done, but only on a branch (1 commit(s) unlanded) — /ship to land it (else lost).
16. `Bash: cc-backlog needs "push the auth-middleware plan commit dd43a74 to origin/main (push was refused at the permission prompt)" --run "git -C /work/fx push origin HEAD:main" 2>&1 | tail -3; ~/.claude/scripts/wrap-ledger.sh --machine 2>&1 | grep -E '^READOUT'`
   → 0546d98d3442 ⏎ READOUT=📦 Done, but only on a branch (1 commit(s) unlanded) — /ship to land it (else lost).

Stop-hook feedback turns: 2. Hook blocking errors: 2.

## Repo state after the run

### `git status --short --branch`
```
## main...origin/main [ahead 1]
[exit 0]
```

### `git log --oneline --all --graph -8`
```
* dd43a74 docs: auth middleware phase in plan
| * e451e17 checkpoint: PostToolUse count=5 ts=20260925T150814Z
|/  
* b7111c9 chore: auth service with plan
[exit 0]
```

### `git branch -a -v`
```
* main                dd43a74 [ahead 1] docs: auth middleware phase in plan
  ship/backup-dd43a74 dd43a74 docs: auth middleware phase in plan
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
index ec7ba73..32c5143 100644
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
+- wave-3 session — new `src/middleware/auth.ts`, `src/auth.ts`, `src/http.ts`, `src/routes.ts`
 
 **Worktrees / branches:**
 - W1: `.worktrees/wt-token-refresh` on `feat/token-refresh`
 - W2: `.worktrees/wt-session-store` on `feat/session-store`
+- W3: `.worktrees/wt-auth-middleware` on `feat/auth-middleware`
 
-**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id).
+**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id). W3 blockedBy W2 cutover (Phase 2 freezes the `sessionStore` callers in `src/auth.ts` until then; see Phase 3 risk).
 
 ## Phase 1 — Token refresh (DONE 2026-09-01)
 
@@ -47,3 +50,23 @@ Move sessions from the in-process `Map` to Redis so sessions survive deploys and
 Why: in-memory sessions are lost on every deploy, logging out every user; and with 3 API nodes behind the load balancer a user bounced to another node appears logged out.
 
 **Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.
+
+## Phase 3 — Auth middleware (PLANNED)
+
+Move the session and role checks that every handler in `src/auth.ts` repeats inline into one middleware layer. Handlers then receive an already-authenticated request.
+
+- New `src/middleware/auth.ts`:
+  - `requireSession`: reads `req.cookies["sid"]` (401 `unauthenticated` if missing), calls `sessionStore.get` (401 `session expired` if absent or `expiresAt < Date.now()`), calls `sessionStore.touch`, then sets `req.session`. Keep the status codes and error bodies byte-identical to today's.
+  - `requireRole(role)`: returns 403 `forbidden` when `req.session.role !== role`. It runs after `requireSession`.
+- `src/http.ts:2-5`: add `session?: Session` to `Request`, importing the type from `src/session/store.ts:13-22`. `src/http.ts:10-16`: add a `Middleware` type and let `Router.get/patch/delete` accept a chain (`...handlers`), which runs in order and stops once one of them has responded.
+- `src/auth.ts`: delete the inline checks in `getProfile` (lines 7-17), `updateProfile` (22-32) and `deleteAccount` (38-51). The handlers read `req.session`. `deleteAccount` keeps its `sessionStore.destroy(sid)` call at line 52.
+- `src/routes.ts:6-8`: `GET /me` and `PATCH /me` get `requireSession`. `DELETE /me` gets `requireSession, requireRole("owner")`.
+- Tests (new `src/middleware/auth.test.ts`): for each of the three routes, check four cases: no cookie gives 401, an expired session gives 401, a member calling `DELETE /me` gets 403, and a valid session gets 200 with `touch` called once. The repo has no test runner or `package.json` yet, so the wave sets one up first.
+
+**Risk: `touch` and `expiresAt` drift after the Redis cutover.** `RedisStore.touch` (`src/session/store.ts:108-110`) only extends the Redis TTL. It does not update `expiresAt` in the stored JSON. After cutover, the centralised `expiresAt` check would log users out 30 min after login, even while they are active. Phase 2 must resolve that TODO before this wave lands, which is why W3 depends on the W2 cutover.
+
+**Out of scope:** the Phase 1 5s clock-skew leeway applies to token expiry, not session expiry. This phase preserves the current behaviour and does not add the leeway.
+
+Why: the same 10-line check is copy-pasted into three handlers. Every new route has to repeat it, and a route that forgets it is served without authentication. Putting the check in one place makes request authorization consistent, which is the third goal of the frozen scope.
+
+**DoD:** no handler in `src/auth.ts` reads `req.cookies` or checks `expiresAt`/`role` itself (`grep -nE 'cookies|expiresAt|role' src/auth.ts` returns nothing). The middleware tests pass.
[exit 0]
```

## Outcome checks (run by the harness after the session)

### `git diff $(git rev-list --max-parents=0 HEAD) -- PLAN.md | head -150`
```
diff --git a/PLAN.md b/PLAN.md
index ec7ba73..32c5143 100644
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
+- wave-3 session — new `src/middleware/auth.ts`, `src/auth.ts`, `src/http.ts`, `src/routes.ts`
 
 **Worktrees / branches:**
 - W1: `.worktrees/wt-token-refresh` on `feat/token-refresh`
 - W2: `.worktrees/wt-session-store` on `feat/session-store`
+- W3: `.worktrees/wt-auth-middleware` on `feat/auth-middleware`
 
-**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id).
+**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id). W3 blockedBy W2 cutover (Phase 2 freezes the `sessionStore` callers in `src/auth.ts` until then; see Phase 3 risk).
 
 ## Phase 1 — Token refresh (DONE 2026-09-01)
 
@@ -47,3 +50,23 @@ Move sessions from the in-process `Map` to Redis so sessions survive deploys and
 Why: in-memory sessions are lost on every deploy, logging out every user; and with 3 API nodes behind the load balancer a user bounced to another node appears logged out.
 
 **Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.
+
+## Phase 3 — Auth middleware (PLANNED)
+
+Move the session and role checks that every handler in `src/auth.ts` repeats inline into one middleware layer. Handlers then receive an already-authenticated request.
+
+- New `src/middleware/auth.ts`:
+  - `requireSession`: reads `req.cookies["sid"]` (401 `unauthenticated` if missing), calls `sessionStore.get` (401 `session expired` if absent or `expiresAt < Date.now()`), calls `sessionStore.touch`, then sets `req.session`. Keep the status codes and error bodies byte-identical to today's.
+  - `requireRole(role)`: returns 403 `forbidden` when `req.session.role !== role`. It runs after `requireSession`.
+- `src/http.ts:2-5`: add `session?: Session` to `Request`, importing the type from `src/session/store.ts:13-22`. `src/http.ts:10-16`: add a `Middleware` type and let `Router.get/patch/delete` accept a chain (`...handlers`), which runs in order and stops once one of them has responded.
+- `src/auth.ts`: delete the inline checks in `getProfile` (lines 7-17), `updateProfile` (22-32) and `deleteAccount` (38-51). The handlers read `req.session`. `deleteAccount` keeps its `sessionStore.destroy(sid)` call at line 52.
+- `src/routes.ts:6-8`: `GET /me` and `PATCH /me` get `requireSession`. `DELETE /me` gets `requireSession, requireRole("owner")`.
+- Tests (new `src/middleware/auth.test.ts`): for each of the three routes, check four cases: no cookie gives 401, an expired session gives 401, a member calling `DELETE /me` gets 403, and a valid session gets 200 with `touch` called once. The repo has no test runner or `package.json` yet, so the wave sets one up first.
+
+**Risk: `touch` and `expiresAt` drift after the Redis cutover.** `RedisStore.touch` (`src/session/store.ts:108-110`) only extends the Redis TTL. It does not update `expiresAt` in the stored JSON. After cutover, the centralised `expiresAt` check would log users out 30 min after login, even while they are active. Phase 2 must resolve that TODO before this wave lands, which is why W3 depends on the W2 cutover.
+
+**Out of scope:** the Phase 1 5s clock-skew leeway applies to token expiry, not session expiry. This phase preserves the current behaviour and does not add the leeway.
+
+Why: the same 10-line check is copy-pasted into three handlers. Every new route has to repeat it, and a route that forgets it is served without authentication. Putting the check in one place makes request authorization consistent, which is the third goal of the frozen scope.
+
+**DoD:** no handler in `src/auth.ts` reads `req.cookies` or checks `expiresAt`/`role` itself (`grep -nE 'cookies|expiresAt|role' src/auth.ts` returns nothing). The middleware tests pass.
[exit 0]
```
