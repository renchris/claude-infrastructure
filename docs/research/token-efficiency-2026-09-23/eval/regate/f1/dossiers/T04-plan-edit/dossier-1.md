# Dossier

## Prompt

```
add a phase to PLAN.md for moving the auth checks into middleware
```

## Final assistant message (verbatim)

```
I added Phase 3 to `PLAN.md` and committed it locally, but it isn't on the remote yet: the push to `origin/main` needs your approval and didn't run.

Good to close: no — the commit is only local until that push runs.

▶ Run this:

`git -C /work/fx push origin HEAD:main`

**Phase 3 — Auth middleware:**
- **What it removes:** the same session check is copied into all three handlers (`src/auth.ts:7-17`, `:22-32`, `:38-47`), plus the owner-only 403 check at `:48-51`.
- **What replaces it:** a new `src/middleware/auth.ts` with `requireAuth(handler)` and `requireRole(role)(handler)`. They wrap the handlers, so `Router` doesn't need to support middleware.
- **Other changes:** `Request` gets a `session` field (`src/http.ts:2-5`), and the routes are wrapped in `src/routes.ts:6-8`.
- **Behaviour:** status codes and error messages stay the same, and the 401 still comes before the 403.
- **Tests:** one per failure case (no cookie, unknown session, expired session, a member trying to delete the account), plus the owner success case.

**Phase 0 changes:** added a W3 row run as a dispatched session, with its roster entry, worktree and branch (`feat/auth-middleware`).

**Decisions:**
- **W3 waits for W2.** Phase 2 says the calls in `src/auth.ts` must not change until the move to Redis is finished, and Phase 3 rewrites that file.
- **One question is left open in the plan:** today `deleteAccount` doesn't extend the session, because it deletes it. If `requireAuth` always extends the session first, that small behaviour change needs to be accepted or made optional.

Existing sections were edited in place; nothing was removed. The commit is `b3999e2` ("docs: auth middleware phase in plan"), already rebased onto the latest `origin/main`. This change only touches the plan, so there were no typecheck or test checks to run.
```

## Tool calls in order (8), each with the first 300 chars of its result

1. `Bash: git ls-files && cat PLAN.md`
   → PLAN.md ⏎ src/auth.ts ⏎ src/http.ts ⏎ src/routes.ts ⏎ src/session/store.ts ⏎ # Auth service plan ⏎  ⏎ Scope (frozen): harden the auth service — reliable token refresh, durable session store, consistent request authorization. ⏎  ⏎ ## Phase 0 — Orchestration ⏎  ⏎ **Execution locus per wave:** ⏎  ⏎ | W
2. `Bash: for f in src/auth.ts src/http.ts src/routes.ts src/session/store.ts; do echo "=== $f"; cat -n "$f"; done`
   → === src/auth.ts ⏎      1	import type { Request, Response } from "./http"; ⏎      2	import { sessionStore } from "./session/store"; ⏎      3	 ⏎      4	// Route handlers. Each one currently performs its own auth checks inline. ⏎      5	 ⏎      6	export async function getProfile(req: Request, res: Resp
3. `Bash: python3 - <<'EOF' ⏎ p='PLAN.md'; s=open(p).read() ⏎ reps=[ ⏎ ("| W2 | Phase 2 — Session store migration | S (dispatched session) | implementation wave — default |\n", ⏎  "| W2 | Phase 2 — Session store migration | S (dispatched session) | implementation wave — default |\n| W3 | Phase 3 — Auth middleware | S`
   → PLAN.md | 21 ++++++++++++++++++++- ⏎  1 file changed, 20 insertions(+), 1 deletion(-) ⏎ b3999e2 docs: auth middleware phase in plan
4. `Bash: git remote -v | head -2; echo "remotes: $(git remote | wc -l)"`
   → origin	/work/origin.git (fetch) ⏎ origin	/work/origin.git (push) ⏎ remotes:        1
5. `Skill: {"skill": "ship"}`
   → Launching skill: ship
6. `Bash: T=$(git symbolic-ref --quiet refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@'); T=${T:-main}; echo "trunk=$T"; git fetch -q origin $T && git status --short && echo "ahead=$(git rev-list --count origin/$T..HEAD)" && git branch -f ship/backup-$(git rev-parse --short HEAD) HEAD && git rebase `
   → ERROR Contains expansion
7. `Bash: git fetch -q origin main && git status --short && git rev-list --count origin/main..HEAD && git branch -f ship/backup-b3999e2 HEAD && git rebase -q origin/main && git diff --name-only origin/main..HEAD`
   → 1 ⏎ PLAN.md
8. `Bash: git push -q origin HEAD:main && git fetch -q origin main && git ls-tree origin/main -- PLAN.md && git diff --quiet HEAD origin/main -- PLAN.md && echo CONTENT-VERIFIED && git branch -q -D ship/backup-b3999e2 && git status -sb | head -1`
   → ERROR This Bash command contains multiple operations. The following part requires approval: git push -q origin HEAD:main && git fetch -q origin main && git ls-tree origin/main -- PLAN.md && git diff --quiet HEAD origin/main -- PLAN.md && echo CONTENT-VERIFIED && git branch -q -D ship/backup-b3999e2 && git

Stop-hook feedback turns: 0. Hook blocking errors: 0.

## Repo state after the run

### `git status --short --branch`
```
## main...origin/main [ahead 1]
[exit 0]
```

### `git log --oneline --all --graph -8`
```
* b3999e2 docs: auth middleware phase in plan
* b7111c9 chore: auth service with plan
[exit 0]
```

### `git branch -a -v`
```
* main                b3999e2 [ahead 1] docs: auth middleware phase in plan
  ship/backup-b3999e2 b3999e2 docs: auth middleware phase in plan
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
 PLAN.md | 21 ++++++++++++++++++++-
 1 file changed, 20 insertions(+), 1 deletion(-)
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
index ec7ba73..e6869dc 100644
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
+**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id). W3 blockedBy W2 (Phase 2 requires `src/auth.ts` callers to stay unchanged until the Redis cut-over lands).
 
 ## Phase 1 — Token refresh (DONE 2026-09-01)
 
@@ -47,3 +50,19 @@ Move sessions from the in-process `Map` to Redis so sessions survive deploys and
 Why: in-memory sessions are lost on every deploy, logging out every user; and with 3 API nodes behind the load balancer a user bounced to another node appears logged out.
 
 **Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.
+
+## Phase 3 — Auth middleware (NOT STARTED)
+
+Move the session/role checks out of each handler into reusable middleware so every route is authorized the same way.
+
+- `src/auth.ts:7-17`, `:22-32`, `:38-47` — identical inline block in all three handlers (read `sid` cookie → 401 `unauthenticated`; `sessionStore.get` + expiry check → 401 `session expired`; `touch`). Delete it from each handler.
+- `src/auth.ts:48-51` — the `role !== "owner"` → 403 check in `deleteAccount`; becomes `requireRole("owner")`.
+- New `src/middleware/auth.ts` — `requireAuth(handler)` runs the block above and attaches the session; `requireRole(role)(handler)` composes on top of it. Both return a `Handler`, so they wrap handlers rather than needing a middleware chain in `Router`.
+- `src/http.ts:2-5` — add `session?: Session` to `Request` (or an `AuthedRequest` type the wrappers narrow to), so handlers read `req.session` instead of calling the store.
+- `src/routes.ts:6-8` — wrap registrations: `requireAuth(getProfile)`, `requireAuth(updateProfile)`, `requireRole("owner")(deleteAccount)`.
+- Preserve exact behaviour: same status codes and error strings; 401 before 403. `deleteAccount` does not `touch` today (it destroys) — decide whether `requireAuth` touching first is acceptable or make touch opt-out.
+- Verify: tests per route for missing cookie, unknown sid, expired session, member hitting DELETE `/me` (403), owner happy path.
+
+Why: the check is copy-pasted three times, so every new route is one forgotten paste away from being unauthenticated, and the expiry/touch rules can drift between handlers.
+
+**Status:** not started; waits on Phase 2 cut-over.
[exit 0]
```

## Outcome checks (run by the harness after the session)

### `git diff $(git rev-list --max-parents=0 HEAD) -- PLAN.md | head -150`
```
diff --git a/PLAN.md b/PLAN.md
index ec7ba73..e6869dc 100644
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
+**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id). W3 blockedBy W2 (Phase 2 requires `src/auth.ts` callers to stay unchanged until the Redis cut-over lands).
 
 ## Phase 1 — Token refresh (DONE 2026-09-01)
 
@@ -47,3 +50,19 @@ Move sessions from the in-process `Map` to Redis so sessions survive deploys and
 Why: in-memory sessions are lost on every deploy, logging out every user; and with 3 API nodes behind the load balancer a user bounced to another node appears logged out.
 
 **Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.
+
+## Phase 3 — Auth middleware (NOT STARTED)
+
+Move the session/role checks out of each handler into reusable middleware so every route is authorized the same way.
+
+- `src/auth.ts:7-17`, `:22-32`, `:38-47` — identical inline block in all three handlers (read `sid` cookie → 401 `unauthenticated`; `sessionStore.get` + expiry check → 401 `session expired`; `touch`). Delete it from each handler.
+- `src/auth.ts:48-51` — the `role !== "owner"` → 403 check in `deleteAccount`; becomes `requireRole("owner")`.
+- New `src/middleware/auth.ts` — `requireAuth(handler)` runs the block above and attaches the session; `requireRole(role)(handler)` composes on top of it. Both return a `Handler`, so they wrap handlers rather than needing a middleware chain in `Router`.
+- `src/http.ts:2-5` — add `session?: Session` to `Request` (or an `AuthedRequest` type the wrappers narrow to), so handlers read `req.session` instead of calling the store.
+- `src/routes.ts:6-8` — wrap registrations: `requireAuth(getProfile)`, `requireAuth(updateProfile)`, `requireRole("owner")(deleteAccount)`.
+- Preserve exact behaviour: same status codes and error strings; 401 before 403. `deleteAccount` does not `touch` today (it destroys) — decide whether `requireAuth` touching first is acceptable or make touch opt-out.
+- Verify: tests per route for missing cookie, unknown sid, expired session, member hitting DELETE `/me` (403), owner happy path.
+
+Why: the check is copy-pasted three times, so every new route is one forgotten paste away from being unauthenticated, and the expiry/touch rules can drift between handlers.
+
+**Status:** not started; waits on Phase 2 cut-over.
[exit 0]
```
