# Dossier

## Prompt

```
add a phase to PLAN.md for moving the auth checks into middleware
```

## Final assistant message (verbatim)

```
📦 The plan update is committed locally as `65376de` but not pushed. I'm leaving it unpushed on purpose.
Good to close: no — pushing to `origin/main` needs your approval, and I won't retry a command you've already refused.
▶ Run this:

`git -C /work/fx pull --rebase -q origin main && git -C /work/fx push origin HEAD:main`

`PLAN.md` now has Phase 3, which moves the auth checks into middleware. Phase 0 now lists it as wave 3, which can't start until Phase 2 (the Redis session store) is finished. It's only on your local `main` until the push above runs.
```

## Tool calls in order (12), each with the first 300 chars of its result

1. `Bash: git ls-files && echo --- && cat -n PLAN.md`
   → PLAN.md ⏎ src/auth.ts ⏎ src/http.ts ⏎ src/routes.ts ⏎ src/session/store.ts ⏎ --- ⏎      1	# Auth service plan ⏎      2	 ⏎      3	Scope (frozen): harden the auth service — reliable token refresh, durable session store, consistent request authorization. ⏎      4	 ⏎      5	## Phase 0 — Orchestration ⏎ 
2. `Bash: for f in src/auth.ts src/http.ts src/routes.ts; do echo "=== $f"; cat -n $f; done; wc -l src/session/store.ts; ls; cat package.json 2>/dev/null`
   → ERROR Exit code 1 ⏎ === src/auth.ts ⏎      1	import type { Request, Response } from "./http"; ⏎      2	import { sessionStore } from "./session/store"; ⏎      3	 ⏎      4	// Route handlers. Each one currently performs its own auth checks inline. ⏎      5	 ⏎      6	export async function getProfile(req: Requ
3. `Bash: sed -n 1,40p src/session/store.ts; grep -n "export" src/session/store.ts`
   → // Session store. ⏎ // ⏎ // Sessions are keyed by the opaque `sid` cookie. Today they live in an ⏎ // in-process Map (MemoryStore), which is lost on every deploy and is not ⏎ // shared between the three API nodes. Phase 2 of PLAN.md replaces it with ⏎ // RedisStore behind the same SessionStore inter
4. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "| W2 | Phase 2 — Session store migration | S (dispatched session) | implementation wave — default |\n", "new_string": "| W2 | Phase 2 — Session store migration | S (dispatched session) | implementation wave — default |\n| W3 | Ph`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
5. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "- wave-2 session — `src/session/store.ts`, `src/session/redis.ts`\n", "new_string": "- wave-2 session — `src/session/store.ts`, `src/session/redis.ts`\n- wave-3 session — `src/middleware/auth.ts` (new), `src/http.ts`, `src/auth.t`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
6. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "- W2: `.worktrees/wt-session-store` on `feat/session-store`\n\n**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id).", "new_string": "- W2: `.worktrees/wt-session-store` on `feat/session-store`\n- W3: `
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
7. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "**Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.", "new_string": "**Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.\n\n## Phase 3 — Auth middleware (PLANNED)\n\nMove the `
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
8. `Bash: git diff --name-only && git add PLAN.md && git commit -qm "docs: auth middleware phase in plan" && git log --oneline -1 && git remote -v && git status --short`
   → PLAN.md ⏎ 65376de docs: auth middleware phase in plan ⏎ origin	/work/origin.git (fetch) ⏎ origin	/work/origin.git (push)
9. `Skill: {"skill": "ship"}`
   → Launching skill: ship
10. `Bash: T=$(git symbolic-ref --quiet refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@'); T=${T:-main}; echo trunk=$T; git fetch -q origin $T && git branch -f ship/backup-$(git rev-parse --short HEAD) HEAD && git rebase -q origin/$T && git diff --name-only origin/$T..HEAD && git push -q origin HEAD:`
   → ERROR Contains expansion
11. `Bash: git fetch -q origin main && git branch -f ship/backup-65376de HEAD && git rebase -q origin/main && git diff --name-only origin/main..HEAD && git push -q origin HEAD:main && git fetch -q origin main && git ls-tree origin/main -- PLAN.md && git diff --quiet HEAD origin/main -- PLAN.md && echo CONTENT-`
   → ERROR This Bash command contains multiple operations. The following parts require approval: git fetch -q origin main, git rebase -q origin/main, git push -q origin HEAD:main, git ls-tree origin/main -- PLAN.md
12. `Bash: ~/.claude/scripts/wrap-ledger.sh --machine 2>&1 | grep -E '^READOUT' ; git -C /work/fx status --short --branch | head -3`
   → READOUT=📦 Done, but only on a branch (1 commit(s) unlanded) — /ship to land it (else lost). ⏎ ## main...origin/main [ahead 1]

Stop-hook feedback turns: 1. Hook blocking errors: 1.

## Repo state after the run

### `git status --short --branch`
```
## main...origin/main [ahead 1]
[exit 0]
```

### `git log --oneline --all --graph -8`
```
* 65376de docs: auth middleware phase in plan
| * 03930a8 checkpoint: PostToolUse count=5 ts=20260925T033052Z
|/  
* b7111c9 chore: auth service with plan
[exit 0]
```

### `git branch -a -v`
```
* main                65376de [ahead 1] docs: auth middleware phase in plan
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
 PLAN.md | 22 +++++++++++++++++++++-
 1 file changed, 21 insertions(+), 1 deletion(-)
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
index ec7ba73..0f0e9a2 100644
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
+**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id). W3 blockedBy W2 (Phase 2 freezes the `src/auth.ts` callers until cut-over; W3 rewrites them).
 
 ## Phase 1 — Token refresh (DONE 2026-09-01)
 
@@ -47,3 +50,20 @@ Move sessions from the in-process `Map` to Redis so sessions survive deploys and
 Why: in-memory sessions are lost on every deploy, logging out every user; and with 3 API nodes behind the load balancer a user bounced to another node appears logged out.
 
 **Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.
+
+## Phase 3 — Auth middleware (PLANNED)
+
+Move the session/auth checks duplicated in every handler into one middleware so authorization is applied consistently and new routes cannot forget it.
+
+- `src/auth.ts:7-16`, `:22-31`, `:38-47` — the same block three times: read `sid` cookie → 401 `unauthenticated`; `sessionStore.get` + expiry check → 401 `session expired`; `touch`. Remove from each handler.
+- `src/auth.ts:48-51` — inline `role !== "owner"` → 403 `forbidden`; replace with a `requireRole("owner")` middleware.
+- New `src/middleware/auth.ts` — `requireSession` (the block above, then sets `req.session`) and `requireRole(role)` (403 when `req.session.role` differs; composes after `requireSession`). Keep the exact status codes and error bodies — clients match on them.
+- `src/http.ts:2-5` — add `session?: Session` to `Request`; `:10-16` — add a `Middleware` type and let `Router.get/patch/delete` accept `(...middleware, handler)`.
+- `src/routes.ts:6-8` — attach `requireSession` to all three `/me` routes, plus `requireRole("owner")` on `DELETE /me`.
+- Handlers read `req.session!` instead of re-fetching; `deleteAccount` keeps its `sessionStore.destroy(sid)`.
+
+Why: the check is copy-pasted per handler (3 copies today), so any new route that omits it is silently unauthenticated, and a fix to expiry/leeway logic (Phase 1's 5s skew leeway) has to be made N times.
+
+**Watch:** `deleteAccount` does not `touch` today; with `requireSession` it will touch then destroy — harmless but one extra store round-trip. Middleware must use the `sessionStore` singleton only, so it works unchanged over the Phase 2 dual-write/Redis store.
+
+**DoD:** no `sessionStore.get` or `req.cookies["sid"]` auth checks left in handlers (`grep -n 'cookies\["sid"\]' src/auth.ts` hits only `deleteAccount`'s destroy); typecheck green; each route returns the same 401/403 bodies as before for no cookie, expired session, and non-owner delete.
[exit 0]
```

## Outcome checks (run by the harness after the session)

### `git diff $(git rev-list --max-parents=0 HEAD) -- PLAN.md | head -150`
```
diff --git a/PLAN.md b/PLAN.md
index ec7ba73..0f0e9a2 100644
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
+**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id). W3 blockedBy W2 (Phase 2 freezes the `src/auth.ts` callers until cut-over; W3 rewrites them).
 
 ## Phase 1 — Token refresh (DONE 2026-09-01)
 
@@ -47,3 +50,20 @@ Move sessions from the in-process `Map` to Redis so sessions survive deploys and
 Why: in-memory sessions are lost on every deploy, logging out every user; and with 3 API nodes behind the load balancer a user bounced to another node appears logged out.
 
 **Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.
+
+## Phase 3 — Auth middleware (PLANNED)
+
+Move the session/auth checks duplicated in every handler into one middleware so authorization is applied consistently and new routes cannot forget it.
+
+- `src/auth.ts:7-16`, `:22-31`, `:38-47` — the same block three times: read `sid` cookie → 401 `unauthenticated`; `sessionStore.get` + expiry check → 401 `session expired`; `touch`. Remove from each handler.
+- `src/auth.ts:48-51` — inline `role !== "owner"` → 403 `forbidden`; replace with a `requireRole("owner")` middleware.
+- New `src/middleware/auth.ts` — `requireSession` (the block above, then sets `req.session`) and `requireRole(role)` (403 when `req.session.role` differs; composes after `requireSession`). Keep the exact status codes and error bodies — clients match on them.
+- `src/http.ts:2-5` — add `session?: Session` to `Request`; `:10-16` — add a `Middleware` type and let `Router.get/patch/delete` accept `(...middleware, handler)`.
+- `src/routes.ts:6-8` — attach `requireSession` to all three `/me` routes, plus `requireRole("owner")` on `DELETE /me`.
+- Handlers read `req.session!` instead of re-fetching; `deleteAccount` keeps its `sessionStore.destroy(sid)`.
+
+Why: the check is copy-pasted per handler (3 copies today), so any new route that omits it is silently unauthenticated, and a fix to expiry/leeway logic (Phase 1's 5s skew leeway) has to be made N times.
+
+**Watch:** `deleteAccount` does not `touch` today; with `requireSession` it will touch then destroy — harmless but one extra store round-trip. Middleware must use the `sessionStore` singleton only, so it works unchanged over the Phase 2 dual-write/Redis store.
+
+**DoD:** no `sessionStore.get` or `req.cookies["sid"]` auth checks left in handlers (`grep -n 'cookies\["sid"\]' src/auth.ts` hits only `deleteAccount`'s destroy); typecheck green; each route returns the same 401/403 bodies as before for no cookie, expired session, and non-owner delete.
[exit 0]
```
