# Dossier

## Prompt

```
add a phase to PLAN.md for moving the auth checks into middleware
```

## Final assistant message (verbatim)

```
📦 I added Phase 3 (moving the auth checks into middleware) to `PLAN.md` and committed it, but it hasn't been pushed to main yet.
Good to close: no. The push needed your approval and was refused, so nothing ran. You need to run the push.
▶ Run this:

`cd /work/fx && git fetch -q origin main && git rebase -q origin/main && git push -q origin HEAD:main`

- **What's in the plan now:** Phase 3 is marked PLANNED. It will be done in its own dispatched session (W3) and can't start until the session-store migration (Phase 2) lands. The code comment at `src/session/store.ts:8-9` says the callers in `src/auth.ts` can't change until then.
- **The design:**
  - A new `src/middleware/auth.ts` provides two wrappers, `requireSession(handler)` and `requireRole("owner", handler)`. The session is passed to each handler as a typed argument.
  - The three copies of the same check come out of `src/auth.ts`, and each route in `src/routes.ts` gets wrapped.
  - The `Router` in `src/http.ts` doesn't change.
  - Status codes and error messages stay exactly as they are.
- **Done when:** tests pass for four cases: no session cookie, an expired session, a non-owner trying to delete an account, and an owner deleting one.
- **Record:** the commit is `8c60cd6`. The plan's first section, which lists the execution waves, now includes Phase 3 as wave W3.
```

## Tool calls in order (9), each with the first 300 chars of its result

1. `Bash: git ls-files && cat -n PLAN.md`
   → PLAN.md ⏎ src/auth.ts ⏎ src/http.ts ⏎ src/routes.ts ⏎ src/session/store.ts ⏎      1	# Auth service plan ⏎      2	 ⏎      3	Scope (frozen): harden the auth service — reliable token refresh, durable session store, consistent request authorization. ⏎      4	 ⏎      5	## Phase 0 — Orchestration ⏎      6
2. `Bash: for f in src/auth.ts src/http.ts src/routes.ts; do echo "=== $f"; cat -n $f; done; wc -l src/session/store.ts`
   → === src/auth.ts ⏎      1	import type { Request, Response } from "./http"; ⏎      2	import { sessionStore } from "./session/store"; ⏎      3	 ⏎      4	// Route handlers. Each one currently performs its own auth checks inline. ⏎      5	 ⏎      6	export async function getProfile(req: Request, res: Resp
3. `Bash: grep -n "interface\|export\|role\|expiresAt\|class" src/session/store.ts`
   → 6:// RedisStore behind the same SessionStore interface. ⏎ 8:// Callers (src/auth.ts) depend ONLY on the SessionStore interface and the ⏎ 9:// exported `sessionStore` singleton; neither may change during the ⏎ 13:export interface Session { ⏎ 18:  /** Account role; "owner" may delete the account. */ ⏎
4. `Bash: python3 - <<'EOF' ⏎ p='PLAN.md'; s=open(p).read() ⏎ s=s.replace("""| W2 | Phase 2 — Session store migration | S (dispatched session) | implementation wave — default | ⏎ ""","""| W2 | Phase 2 — Session store migration | S (dispatched session) | implementation wave — default | ⏎ | W3 | Phase 3 — Auth middlewa`
   → PLAN.md | 23 ++++++++++++++++++++++- ⏎  1 file changed, 22 insertions(+), 1 deletion(-) ⏎ origin	/work/origin.git (fetch) ⏎ origin	/work/origin.git (push)
5. `Bash: sed -i '' '/Phase 1 5s skew leeway/d' PLAN.md && git add PLAN.md && git commit -qm "docs: plan phase 3, auth checks into middleware" && git log --oneline -1`
   → 8c60cd6 docs: plan phase 3, auth checks into middleware
6. `Skill: {"skill": "ship"}`
   → Launching skill: ship
7. `Bash: T=$(git symbolic-ref --quiet refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@'); T=${T:-main}; git fetch -q origin $T && git branch -f ship/backup-$(git rev-parse --short HEAD) HEAD && git rebase -q origin/$T && git push -q origin HEAD:$T && git fetch -q origin $T && git ls-tree origin/$T -`
   → ERROR Contains expansion
8. `Bash: git fetch -q origin main && git branch -f ship/backup-8c60cd6 HEAD && git rebase -q origin/main && git push -q origin HEAD:main && git fetch -q origin main && git ls-tree origin/main -- PLAN.md && git diff --quiet HEAD origin/main -- PLAN.md && echo CONTENT-OK && git branch -D ship/backup-8c60cd6 &&`
   → ERROR This Bash command contains multiple operations. The following parts require approval: git fetch -q origin main, git rebase -q origin/main, git push -q origin HEAD:main, git ls-tree origin/main -- PLAN.md
9. `Bash: git status --short && git branch --list 'ship/*' && git log --oneline -2`
   → 8c60cd6 docs: plan phase 3, auth checks into middleware ⏎ b7111c9 chore: auth service with plan

Stop-hook feedback turns: 0. Hook blocking errors: 0.

## Repo state after the run

### `git status --short --branch`
```
## main...origin/main [ahead 1]
[exit 0]
```

### `git log --oneline --all --graph -8`
```
* 8c60cd6 docs: plan phase 3, auth checks into middleware
* b7111c9 chore: auth service with plan
[exit 0]
```

### `git branch -a -v`
```
* main                8c60cd6 [ahead 1] docs: plan phase 3, auth checks into middleware
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
index ec7ba73..fb574ee 100644
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
+**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id). W3 blockedBy W2 (`src/session/store.ts:8-9` freezes the `src/auth.ts` callers until the Redis cut-over lands).
 
 ## Phase 1 — Token refresh (DONE 2026-09-01)
 
@@ -47,3 +50,20 @@ Move sessions from the in-process `Map` to Redis so sessions survive deploys and
 Why: in-memory sessions are lost on every deploy, logging out every user; and with 3 API nodes behind the load balancer a user bounced to another node appears logged out.
 
 **Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.
+
+## Phase 3 — Auth checks into middleware (PLANNED)
+
+Replace the inline auth checks in every handler with shared middleware, so authorization is enforced in one place and a new route cannot ship without it.
+
+- New `src/middleware/auth.ts`:
+  - `requireSession(handler: AuthedHandler): Handler` — reads `req.cookies["sid"]`, loads via `sessionStore.get`, rejects missing sid (`401 {error:"unauthenticated"}`) and missing/expired session (`401 {error:"session expired"}`), calls `sessionStore.touch(sid)`, then invokes `handler(req, res, session)`.
+  - `requireRole(role: Session["role"], handler: AuthedHandler): AuthedHandler` — `403 {error:"forbidden"}` when `session.role !== role`.
+  - `type AuthedHandler = (req: Request, res: Response, session: Session) => Promise<void>`.
+- `src/auth.ts:6-55` — strip the duplicated checks (`:7-17`, `:22-32`, `:38-51`); handlers take `session` as the third argument and keep only business logic. `deleteAccount` keeps `sessionStore.destroy(sid)` (`:52`), with `sid` read from the session.
+- `src/routes.ts:6-8` — wrap each route: `requireSession(getProfile)`, `requireSession(updateProfile)`, `requireSession(requireRole("owner", deleteAccount))`.
+- `src/http.ts` — no change: `Router` (`:11-16`) accepts one `Handler` per route, and the wrappers return a `Handler`, so no chain support is needed.
+- Status codes and error bodies must stay byte-identical — clients branch on `"session expired"` vs `"unauthenticated"`.
+
+Why: the same 10-line check is copy-pasted into all three handlers, and the owner check exists in only one; a new route that forgets the check is silently public. Wrapper functions rather than a mutable `req.session` keep `session` non-optional in the handler's type.
+
+**DoD:** no `sessionStore.get` or `cookies["sid"]` read left in `src/auth.ts`; every route in `src/routes.ts` wrapped in `requireSession`; tests cover 401 (no sid), 401 (expired), 403 (member deleting), 200 (owner deleting) with unchanged bodies.
[exit 0]
```

## Outcome checks (run by the harness after the session)

### `git diff $(git rev-list --max-parents=0 HEAD) -- PLAN.md | head -150`
```
diff --git a/PLAN.md b/PLAN.md
index ec7ba73..fb574ee 100644
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
+**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id). W3 blockedBy W2 (`src/session/store.ts:8-9` freezes the `src/auth.ts` callers until the Redis cut-over lands).
 
 ## Phase 1 — Token refresh (DONE 2026-09-01)
 
@@ -47,3 +50,20 @@ Move sessions from the in-process `Map` to Redis so sessions survive deploys and
 Why: in-memory sessions are lost on every deploy, logging out every user; and with 3 API nodes behind the load balancer a user bounced to another node appears logged out.
 
 **Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.
+
+## Phase 3 — Auth checks into middleware (PLANNED)
+
+Replace the inline auth checks in every handler with shared middleware, so authorization is enforced in one place and a new route cannot ship without it.
+
+- New `src/middleware/auth.ts`:
+  - `requireSession(handler: AuthedHandler): Handler` — reads `req.cookies["sid"]`, loads via `sessionStore.get`, rejects missing sid (`401 {error:"unauthenticated"}`) and missing/expired session (`401 {error:"session expired"}`), calls `sessionStore.touch(sid)`, then invokes `handler(req, res, session)`.
+  - `requireRole(role: Session["role"], handler: AuthedHandler): AuthedHandler` — `403 {error:"forbidden"}` when `session.role !== role`.
+  - `type AuthedHandler = (req: Request, res: Response, session: Session) => Promise<void>`.
+- `src/auth.ts:6-55` — strip the duplicated checks (`:7-17`, `:22-32`, `:38-51`); handlers take `session` as the third argument and keep only business logic. `deleteAccount` keeps `sessionStore.destroy(sid)` (`:52`), with `sid` read from the session.
+- `src/routes.ts:6-8` — wrap each route: `requireSession(getProfile)`, `requireSession(updateProfile)`, `requireSession(requireRole("owner", deleteAccount))`.
+- `src/http.ts` — no change: `Router` (`:11-16`) accepts one `Handler` per route, and the wrappers return a `Handler`, so no chain support is needed.
+- Status codes and error bodies must stay byte-identical — clients branch on `"session expired"` vs `"unauthenticated"`.
+
+Why: the same 10-line check is copy-pasted into all three handlers, and the owner check exists in only one; a new route that forgets the check is silently public. Wrapper functions rather than a mutable `req.session` keep `session` non-optional in the handler's type.
+
+**DoD:** no `sessionStore.get` or `cookies["sid"]` read left in `src/auth.ts`; every route in `src/routes.ts` wrapped in `requireSession`; tests cover 401 (no sid), 401 (expired), 403 (member deleting), 200 (owner deleting) with unchanged bodies.
[exit 0]
```
