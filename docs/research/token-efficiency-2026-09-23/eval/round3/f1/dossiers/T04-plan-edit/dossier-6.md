# Dossier

## Prompt

```
add a phase to PLAN.md for moving the auth checks into middleware
```

## Final assistant message (verbatim)

```
📦 Done, but only on a branch (1 commit unlanded): I'm deliberately leaving the plan commit `c8111ff` unpushed until you approve it.

Good to close: no — only you can push `c8111ff` to `origin/main`.

▶ Run this:

`git -C /work/fx pull --rebase -q origin main && git -C /work/fx push origin HEAD:main`

The push needs your approval and was refused for this session, and I won't try to push another way. The step is filed as `aa0474a22e6e` ("push the auth-middleware plan commit").
```

## Tool calls in order (14), each with the first 300 chars of its result

1. `Bash: git ls-files && cat -n PLAN.md`
   → PLAN.md ⏎ src/auth.ts ⏎ src/http.ts ⏎ src/routes.ts ⏎ src/session/store.ts ⏎      1	# Auth service plan ⏎      2	 ⏎      3	Scope (frozen): harden the auth service — reliable token refresh, durable session store, consistent request authorization. ⏎      4	 ⏎      5	## Phase 0 — Orchestration ⏎      6
2. `Bash: for f in src/auth.ts src/http.ts src/routes.ts; do echo "=== $f"; cat -n $f; done; wc -l src/session/store.ts`
   → === src/auth.ts ⏎      1	import type { Request, Response } from "./http"; ⏎      2	import { sessionStore } from "./session/store"; ⏎      3	 ⏎      4	// Route handlers. Each one currently performs its own auth checks inline. ⏎      5	 ⏎      6	export async function getProfile(req: Request, res: Resp
3. `Bash: sed -n 1,40p src/session/store.ts; grep -n "export" src/session/store.ts`
   → // Session store. ⏎ // ⏎ // Sessions are keyed by the opaque `sid` cookie. Today they live in an ⏎ // in-process Map (MemoryStore), which is lost on every deploy and is not ⏎ // shared between the three API nodes. Phase 2 of PLAN.md replaces it with ⏎ // RedisStore behind the same SessionStore inter
4. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "| W2 | Phase 2 — Session store migration | S (dispatched session) | implementation wave — default |\n", "new_string": "| W2 | Phase 2 — Session store migration | S (dispatched session) | implementation wave — default |\n| W3 | Ph`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
5. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "- wave-2 session — `src/session/store.ts`, `src/session/redis.ts`\n", "new_string": "- wave-2 session — `src/session/store.ts`, `src/session/redis.ts`\n- wave-3 session — `src/middleware/auth.ts` (new), `src/auth.ts`, `src/routes`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
6. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "- W2: `.worktrees/wt-session-store` on `feat/session-store`\n\n**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id).", "new_string": "- W2: `.worktrees/wt-session-store` on `feat/session-store`\n- W3: `
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
7. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "**Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.", "new_string": "**Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.\n\n## Phase 3 — Auth middleware (PLANNED)\n\nMove the `
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
8. `Bash: git diff --name-only && git add PLAN.md && git commit -q -m "docs: auth middleware phase in plan" && git log --oneline -1 && git status --short; git remote -v`
   → PLAN.md ⏎ c8111ff docs: auth middleware phase in plan ⏎ origin	/work/origin.git (fetch) ⏎ origin	/work/origin.git (push)
9. `Skill: {"skill": "ship"}`
   → Launching skill: ship
10. `Bash: T=$(git symbolic-ref --quiet refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@'); T=${T:-main}; echo "trunk=$T"; git fetch -q origin $T && git rev-list --count origin/$T..HEAD && git branch -f ship/backup-$(git rev-parse --short HEAD) HEAD && git rebase -q origin/$T && ls package.json 2>/dev`
   → ERROR Contains expansion
11. `Bash: git fetch -q origin main && git rev-list --count origin/main..HEAD && git branch -f ship/backup-c8111ff HEAD && git rebase -q origin/main && git push -q origin HEAD:main && git fetch -q origin main && git ls-tree origin/main -- PLAN.md && git diff --quiet HEAD origin/main -- PLAN.md && echo CONTENT-`
   → ERROR This Bash command contains multiple operations. The following parts require approval: git fetch -q origin main, git rebase -q origin/main, git push -q origin HEAD:main, git ls-tree origin/main -- PLAN.md
12. `Bash: cc-backlog needs "push the auth-middleware plan commit c8111ff to origin/main in the fx fixture repo (push refused for approval)" --run "git -C /work/fx pull --rebase -q origin main && git -C /work/fx push origin HEAD:main"`
   → aa0474a22e6e
13. `Bash: ~/.claude/scripts/wrap-ledger.sh --machine | grep '^READOUT'`
   → READOUT=📦 Done, but only on a branch (1 commit(s) unlanded) — /ship to land it (else lost).
14. `Bash: ~/.claude/hooks/session-continue.sh clear`
   → nothing to clear — no sentinel was armed for this cwd: /work/fx

Stop-hook feedback turns: 3. Hook blocking errors: 3.

## Repo state after the run

### `git status --short --branch`
```
## main...origin/main [ahead 1]
[exit 0]
```

### `git log --oneline --all --graph -8`
```
* c8111ff docs: auth middleware phase in plan
| * 7ed35e7 checkpoint: PostToolUse count=5 ts=20260924T210426Z
|/  
* b7111c9 chore: auth service with plan
[exit 0]
```

### `git branch -a -v`
```
* main                c8111ff [ahead 1] docs: auth middleware phase in plan
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
 PLAN.md | 19 ++++++++++++++++++-
 1 file changed, 18 insertions(+), 1 deletion(-)
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
index ec7ba73..fa8eaa5 100644
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
+**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id). W3 blockedBy W2 (Phase 2 freezes the callers in `src/auth.ts` until cut-over; W3 rewrites them).
 
 ## Phase 1 — Token refresh (DONE 2026-09-01)
 
@@ -47,3 +50,17 @@ Move sessions from the in-process `Map` to Redis so sessions survive deploys and
 Why: in-memory sessions are lost on every deploy, logging out every user; and with 3 API nodes behind the load balancer a user bounced to another node appears logged out.
 
 **Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.
+
+## Phase 3 — Auth middleware (PLANNED)
+
+Move the per-handler session and role checks into one middleware so every route is authorized the same way.
+
+- `src/auth.ts:7-16`, `:22-31`, `:38-47` — the same cookie → `sessionStore.get` → expiry check is copied into `getProfile`, `updateProfile` and `deleteAccount`; `:48-51` is the only role check (`owner` for `deleteAccount`).
+- New `src/middleware/auth.ts` — `requireAuth(handler, opts?: { role?: Session["role"]; touch?: boolean })` returns a `Handler`: reads `req.cookies["sid"]`, 401 `unauthenticated` when missing, 401 `session expired` when absent or `expiresAt < Date.now()`, 403 `forbidden` on role mismatch, calls `sessionStore.touch(sid)` unless `touch: false`, sets `req.session` / `req.sid`, then calls the handler. Keep the error bodies byte-identical to today's.
+- `src/http.ts:2-5` — add optional `session?: Session` and `sid?: string` to `Request`. `Router` (`:11-16`) has no `use()`, so wrap per route rather than adding a middleware chain.
+- `src/routes.ts:6-8` — `router.get("/me", requireAuth(getProfile))`, `router.patch("/me", requireAuth(updateProfile))`, `router.delete("/me", requireAuth(deleteAccount, { role: "owner", touch: false }))`.
+- `src/auth.ts` — strip the inline checks; handlers read `req.session!` / `req.sid!`. `deleteAccount` still calls `sessionStore.destroy(req.sid!)`.
+
+Why: three copies of the check have already diverged (`deleteAccount` skips `touch`), and each new route must remember to copy it; a missed copy is an unauthenticated endpoint.
+
+**Done when:** no `req.cookies["sid"]` remains in `src/auth.ts`; each route in `src/routes.ts` is wrapped in `requireAuth`; tests cover 401 missing cookie, 401 expired, 403 non-owner delete, 200 happy path per route; typecheck and lint green.
[exit 0]
```

## Outcome checks (run by the harness after the session)

### `git diff $(git rev-list --max-parents=0 HEAD) -- PLAN.md | head -150`
```
diff --git a/PLAN.md b/PLAN.md
index ec7ba73..fa8eaa5 100644
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
+**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id). W3 blockedBy W2 (Phase 2 freezes the callers in `src/auth.ts` until cut-over; W3 rewrites them).
 
 ## Phase 1 — Token refresh (DONE 2026-09-01)
 
@@ -47,3 +50,17 @@ Move sessions from the in-process `Map` to Redis so sessions survive deploys and
 Why: in-memory sessions are lost on every deploy, logging out every user; and with 3 API nodes behind the load balancer a user bounced to another node appears logged out.
 
 **Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.
+
+## Phase 3 — Auth middleware (PLANNED)
+
+Move the per-handler session and role checks into one middleware so every route is authorized the same way.
+
+- `src/auth.ts:7-16`, `:22-31`, `:38-47` — the same cookie → `sessionStore.get` → expiry check is copied into `getProfile`, `updateProfile` and `deleteAccount`; `:48-51` is the only role check (`owner` for `deleteAccount`).
+- New `src/middleware/auth.ts` — `requireAuth(handler, opts?: { role?: Session["role"]; touch?: boolean })` returns a `Handler`: reads `req.cookies["sid"]`, 401 `unauthenticated` when missing, 401 `session expired` when absent or `expiresAt < Date.now()`, 403 `forbidden` on role mismatch, calls `sessionStore.touch(sid)` unless `touch: false`, sets `req.session` / `req.sid`, then calls the handler. Keep the error bodies byte-identical to today's.
+- `src/http.ts:2-5` — add optional `session?: Session` and `sid?: string` to `Request`. `Router` (`:11-16`) has no `use()`, so wrap per route rather than adding a middleware chain.
+- `src/routes.ts:6-8` — `router.get("/me", requireAuth(getProfile))`, `router.patch("/me", requireAuth(updateProfile))`, `router.delete("/me", requireAuth(deleteAccount, { role: "owner", touch: false }))`.
+- `src/auth.ts` — strip the inline checks; handlers read `req.session!` / `req.sid!`. `deleteAccount` still calls `sessionStore.destroy(req.sid!)`.
+
+Why: three copies of the check have already diverged (`deleteAccount` skips `touch`), and each new route must remember to copy it; a missed copy is an unauthenticated endpoint.
+
+**Done when:** no `req.cookies["sid"]` remains in `src/auth.ts`; each route in `src/routes.ts` is wrapped in `requireAuth`; tests cover 401 missing cookie, 401 expired, 403 non-owner delete, 200 happy path per route; typecheck and lint green.
[exit 0]
```
