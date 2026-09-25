# Dossier

## Prompt

```
add a phase to PLAN.md for moving the auth checks into middleware
```

## Final assistant message (verbatim)

```
I added Phase 3 (auth middleware) to `PLAN.md` and committed it, but it isn't on the remote yet: the push to `origin/main` needs your permission and wasn't approved in this session.

📦 Done, but only on local `main` — land it or it stays on this machine only.
Good to close: no — the one commit needs pushing; follow-on: none.

▶ Run this:

`git -C /work/fx push origin HEAD:main`

- **The new phase:** it covers the check block that's pasted into all three handlers (`src/auth.ts:7-17`, `:22-32`, `:38-47`). It moves into a new `src/middleware/auth.ts` that provides `requireSession`, plus `requireRole("owner")` to replace the owner check in `deleteAccount`. `Request` in `src/http.ts` gets a `session` field. Each route in `src/routes.ts` gets wrapped when it's registered, because `Router` has no way to add middleware. One test covers all three routes and checks that the 401/403 responses stay exactly the same.
- **Phase 0 updated:** a W3 row (dispatched session), roster and worktree entries, and a dependency: W3 waits for the Phase 2 cutover. That's because Phase 2 freezes the callers in `src/auth.ts`, and the expiry check depends on the planned fix to `RedisStore.touch`.
- **Receipt:** commit `072f12e` (`docs: phase 3 auth middleware plan`), already rebased onto `origin/main`. There's no build or test setup in this repo, so nothing could be run against it. A backup branch `ship/backup-072f12e` is still there; you can delete it once the push lands.
```

## Tool calls in order (11), each with the first 300 chars of its result

1. `Bash: git ls-files && cat -n PLAN.md`
   → PLAN.md ⏎ src/auth.ts ⏎ src/http.ts ⏎ src/routes.ts ⏎ src/session/store.ts ⏎      1	# Auth service plan ⏎      2	 ⏎      3	Scope (frozen): harden the auth service — reliable token refresh, durable session store, consistent request authorization. ⏎      4	 ⏎      5	## Phase 0 — Orchestration ⏎      6
2. `Bash: for f in src/*.ts src/session/store.ts; do echo "=== $f"; cat -n $f; done`
   → === src/auth.ts ⏎      1	import type { Request, Response } from "./http"; ⏎      2	import { sessionStore } from "./session/store"; ⏎      3	 ⏎      4	// Route handlers. Each one currently performs its own auth checks inline. ⏎      5	 ⏎      6	export async function getProfile(req: Request, res: Resp
3. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "| W2 | Phase 2 — Session store migration | S (dispatched session) | implementation wave — default |", "new_string": "| W2 | Phase 2 — Session store migration | S (dispatched session) | implementation wave — default |\n| W3 | Phas`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
4. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "- wave-2 session — `src/session/store.ts`, `src/session/redis.ts`\n", "new_string": "- wave-2 session — `src/session/store.ts`, `src/session/redis.ts`\n- wave-3 session — `src/middleware/auth.ts` (new), `src/http.ts`, `src/routes`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
5. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "- W2: `.worktrees/wt-session-store` on `feat/session-store`\n\n**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id).", "new_string": "- W2: `.worktrees/wt-session-store` on `feat/session-store`\n- W3: `
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
6. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "**Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.", "new_string": "**Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.\n\n## Phase 3 — Auth middleware (NOT STARTED)\n\nMove `
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
7. `Bash: git diff --name-only && git add PLAN.md && git commit -q -m "docs: phase 3 auth middleware plan" && git log --oneline -1 && git status --short && git remote -v`
   → PLAN.md ⏎ 072f12e docs: phase 3 auth middleware plan ⏎ origin	/work/origin.git (fetch) ⏎ origin	/work/origin.git (push)
8. `Skill: {"skill": "ship"}`
   → Launching skill: ship
9. `Bash: T=$(git symbolic-ref --quiet refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@'); T=${T:-main}; echo "trunk=$T"; git fetch -q origin $T && git branch -f ship/backup-$(git rev-parse --short HEAD) HEAD && git rebase -q origin/$T && echo "unpushed=$(git rev-list --count origin/$T..HEAD)"; ls pa`
   → trunk=main ⏎ unpushed=1 ⏎ ls: package.json: No such file or directory ⏎ ls: pnpm-lock.yaml: No such file or directory ⏎ ls: tsconfig.json: No such file or directory
10. `Bash: S=$(git rev-parse HEAD) && git push -q origin HEAD:main && git fetch -q origin main && git ls-tree --name-only origin/main -- PLAN.md && git diff --quiet $S origin/main -- PLAN.md && echo "content-verified $(git rev-parse --short $S)" && git branch -D -q ship/backup-$(git rev-parse --short ORIG_HEAD`
   → ERROR Contains simple_expansion
11. `Bash: git push -q origin HEAD:main && git fetch -q origin main && git ls-tree --name-only origin/main -- PLAN.md && git diff --quiet HEAD origin/main -- PLAN.md && echo content-verified && git status -sb | head -1`
   → ERROR This Bash command contains multiple operations. The following part requires approval: git push -q origin HEAD:main && git fetch -q origin main && git ls-tree --name-only origin/main -- PLAN.md && git diff --quiet HEAD origin/main -- PLAN.md && echo content-verified && git status -sb

Stop-hook feedback turns: 0. Hook blocking errors: 0.

## Repo state after the run

### `git status --short --branch`
```
## main...origin/main [ahead 1]
[exit 0]
```

### `git log --oneline --all --graph -8`
```
* 072f12e docs: phase 3 auth middleware plan
| * 2f148be checkpoint: PostToolUse count=5 ts=20260925T032844Z
|/  
* b7111c9 chore: auth service with plan
[exit 0]
```

### `git branch -a -v`
```
* main                072f12e [ahead 1] docs: phase 3 auth middleware plan
  ship/backup-072f12e 072f12e docs: phase 3 auth middleware plan
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
 PLAN.md | 20 +++++++++++++++++++-
 1 file changed, 19 insertions(+), 1 deletion(-)
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
index ec7ba73..0de5221 100644
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
+**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id). W3 blockedBy W2 cutover (Phase 2 freezes `src/auth.ts` callers during the migration, and the middleware's expiry check relies on `RedisStore.touch` bumping `expiresAt`).
 
 ## Phase 1 — Token refresh (DONE 2026-09-01)
 
@@ -47,3 +50,18 @@ Move sessions from the in-process `Map` to Redis so sessions survive deploys and
 Why: in-memory sessions are lost on every deploy, logging out every user; and with 3 API nodes behind the load balancer a user bounced to another node appears logged out.
 
 **Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.
+
+## Phase 3 — Auth middleware (NOT STARTED)
+
+Move the per-handler session checks out of `src/auth.ts` into one middleware layer so every protected route authorizes the same way.
+
+- `src/auth.ts:7-17`, `:22-32`, `:38-47` — the same block (read `sid` cookie → 401 `unauthenticated`; `sessionStore.get` → 401 `session expired` if absent or `expiresAt < Date.now()`; `touch`) is copy-pasted into `getProfile`, `updateProfile`, `deleteAccount`. Delete it from all three.
+- `src/auth.ts:48-51` — the inline `role !== "owner"` → 403 `forbidden` check in `deleteAccount` moves to a role guard.
+- New `src/middleware/auth.ts` — `requireSession(handler): Handler` wraps a handler, runs the check above once, and attaches the session to the request; `requireRole("owner")(handler)` layers the 403 on top. Keep status codes and error bodies byte-identical to today's.
+- `src/http.ts:2-5` — add `session?: Session` to `Request` (or an `AuthedRequest` type the wrapped handler receives, so handlers get a non-optional `session`). `Router` (`:11-16`) has no middleware hook; composing wrappers avoids adding one.
+- `src/routes.ts:6-8` — wrap at registration: `router.get("/me", requireSession(getProfile))`, `router.delete("/me", requireSession(requireRole("owner")(deleteAccount)))`. Handlers then read `req.session` only.
+- Tests: one table-driven test over all three routes × {no cookie, unknown sid, expired, member on DELETE, valid} asserting the same 401/403/200 responses as before the move.
+
+Why: three copies of the same check have already drifted in shape (only `deleteAccount` has a role check, and it skips `touch`), and any new route must remember to paste the block — a missed paste is an unauthenticated endpoint.
+
+**Watch:** `deleteAccount` currently does not `touch` before `destroy`; touching in the middleware first is harmless but should be a deliberate choice, not an accident.
[exit 0]
```

## Outcome checks (run by the harness after the session)

### `git diff $(git rev-list --max-parents=0 HEAD) -- PLAN.md | head -150`
```
diff --git a/PLAN.md b/PLAN.md
index ec7ba73..0de5221 100644
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
+**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id). W3 blockedBy W2 cutover (Phase 2 freezes `src/auth.ts` callers during the migration, and the middleware's expiry check relies on `RedisStore.touch` bumping `expiresAt`).
 
 ## Phase 1 — Token refresh (DONE 2026-09-01)
 
@@ -47,3 +50,18 @@ Move sessions from the in-process `Map` to Redis so sessions survive deploys and
 Why: in-memory sessions are lost on every deploy, logging out every user; and with 3 API nodes behind the load balancer a user bounced to another node appears logged out.
 
 **Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.
+
+## Phase 3 — Auth middleware (NOT STARTED)
+
+Move the per-handler session checks out of `src/auth.ts` into one middleware layer so every protected route authorizes the same way.
+
+- `src/auth.ts:7-17`, `:22-32`, `:38-47` — the same block (read `sid` cookie → 401 `unauthenticated`; `sessionStore.get` → 401 `session expired` if absent or `expiresAt < Date.now()`; `touch`) is copy-pasted into `getProfile`, `updateProfile`, `deleteAccount`. Delete it from all three.
+- `src/auth.ts:48-51` — the inline `role !== "owner"` → 403 `forbidden` check in `deleteAccount` moves to a role guard.
+- New `src/middleware/auth.ts` — `requireSession(handler): Handler` wraps a handler, runs the check above once, and attaches the session to the request; `requireRole("owner")(handler)` layers the 403 on top. Keep status codes and error bodies byte-identical to today's.
+- `src/http.ts:2-5` — add `session?: Session` to `Request` (or an `AuthedRequest` type the wrapped handler receives, so handlers get a non-optional `session`). `Router` (`:11-16`) has no middleware hook; composing wrappers avoids adding one.
+- `src/routes.ts:6-8` — wrap at registration: `router.get("/me", requireSession(getProfile))`, `router.delete("/me", requireSession(requireRole("owner")(deleteAccount)))`. Handlers then read `req.session` only.
+- Tests: one table-driven test over all three routes × {no cookie, unknown sid, expired, member on DELETE, valid} asserting the same 401/403/200 responses as before the move.
+
+Why: three copies of the same check have already drifted in shape (only `deleteAccount` has a role check, and it skips `touch`), and any new route must remember to paste the block — a missed paste is an unauthenticated endpoint.
+
+**Watch:** `deleteAccount` currently does not `touch` before `destroy`; touching in the middleware first is harmless but should be a deliberate choice, not an accident.
[exit 0]
```
