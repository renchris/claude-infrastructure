# Dossier

## Prompt

```
add a phase to PLAN.md for moving the auth checks into middleware
```

## Final assistant message (verbatim)

```
📦 Done, but only on a branch: the Phase 3 auth-middleware plan is committed and not yet pushed.
Good to close: no. Commit `fb67411` still has to be pushed to `origin/main`. The push step needs your approval, so it's your move.
▶ Run this:

`cd /work/fx && git fetch -q origin main && git rebase -q origin/main && git push -q origin HEAD:main && git diff --quiet HEAD origin/main -- PLAN.md && echo landed`

`PLAN.md` now has a Phase 3 section for moving the auth checks into middleware:
- **What it builds:** a new `src/middleware/auth.ts` with `requireSession` and `requireRole`, plus small changes in `src/http.ts` so routes can run middleware in order. The repeated check is then removed from the three handlers in `src/auth.ts`, and each route in `src/routes.ts` gets the middleware it needs.
- **Rules it sets:** responses stay exactly the same (same status codes and error messages). It doesn't add the 5s clock-skew allowance to session expiry. It doesn't touch `src/session/store.ts`, which belongs to Phase 2.
- **Orchestration section:** a new wave, W3, runs as its own dispatched session on `feat/auth-middleware`. It can run alongside Phase 2 because the two share no files.
- **Definition of done:** a search check, a clean typecheck, and handler tests covering both 401 cases, the 403 case and the success case.
```

## Tool calls in order (13), each with the first 300 chars of its result

1. `Bash: git ls-files && echo --- && cat -n PLAN.md`
   → PLAN.md ⏎ src/auth.ts ⏎ src/http.ts ⏎ src/routes.ts ⏎ src/session/store.ts ⏎ --- ⏎      1	# Auth service plan ⏎      2	 ⏎      3	Scope (frozen): harden the auth service — reliable token refresh, durable session store, consistent request authorization. ⏎      4	 ⏎      5	## Phase 0 — Orchestration ⏎ 
2. `Bash: for f in src/auth.ts src/http.ts src/routes.ts; do echo "=== $f"; cat -n $f; done; echo; wc -l src/session/store.ts`
   → === src/auth.ts ⏎      1	import type { Request, Response } from "./http"; ⏎      2	import { sessionStore } from "./session/store"; ⏎      3	 ⏎      4	// Route handlers. Each one currently performs its own auth checks inline. ⏎      5	 ⏎      6	export async function getProfile(req: Request, res: Resp
3. `Bash: grep -n "interface\|role\|expiresAt\|export" src/session/store.ts; ls package.json 2>&1`
   → ERROR Exit code 1 ⏎ 6:// RedisStore behind the same SessionStore interface. ⏎ 8:// Callers (src/auth.ts) depend ONLY on the SessionStore interface and the ⏎ 9:// exported `sessionStore` singleton; neither may change during the ⏎ 13:export interface Session { ⏎ 18:  /** Account role; "owner" may delete the
4. `Read: {"file_path": "/work/fx/PLAN.md"}`
   → 1	# Auth service plan ⏎ 2	 ⏎ 3	Scope (frozen): harden the auth service — reliable token refresh, durable session store, consistent request authorization. ⏎ 4	 ⏎ 5	## Phase 0 — Orchestration ⏎ 6	 ⏎ 7	**Execution locus per wave:** ⏎ 8	 ⏎ 9	| Wave | Phase | Locus | Why | ⏎ 10	|---|---|---|---| ⏎ 11	| W
5. `Read: {"file_path": "/work/fx/src/session/store.ts", "offset": 10, "limit": 30}`
   → 10	// migration. ⏎ 11	 ⏎ 12	/** A logged-in user's session. */ ⏎ 13	export interface Session { ⏎ 14	  /** Stable user id. */ ⏎ 15	  userId: string; ⏎ 16	  /** Primary email, cached for display. */ ⏎ 17	  email: string; ⏎ 18	  /** Account role; "owner" may delete the account. */ ⏎ 19	  role: "owner" 
6. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "| W2 | Phase 2 — Session store migration | S (dispatched session) | implementation wave — default |\n", "new_string": "| W2 | Phase 2 — Session store migration | S (dispatched session) | implementation wave — default |\n| W3 | Ph`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
7. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "- wave-2 session — `src/session/store.ts`, `src/session/redis.ts`\n", "new_string": "- wave-2 session — `src/session/store.ts`, `src/session/redis.ts`\n- wave-3 session — `src/middleware/auth.ts` (new), `src/http.ts`, `src/auth.t`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
8. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "- W2: `.worktrees/wt-session-store` on `feat/session-store`\n\n**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id).\n", "new_string": "- W2: `.worktrees/wt-session-store` on `feat/session-store`\n- W3`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
9. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "**Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.\n", "new_string": "**Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.\n\n## Phase 3 — Auth middleware (PLANNED)\n\nMove th`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
10. `Bash: git diff --name-only && git add PLAN.md && git commit -qm "docs: phase 3 auth middleware plan" && git log --oneline -1 && git remote -v && git status --short`
   → PLAN.md ⏎ fb67411 docs: phase 3 auth middleware plan ⏎ origin	/work/origin.git (fetch) ⏎ origin	/work/origin.git (push)
11. `Skill: {"skill": "ship"}`
   → Launching skill: ship
12. `Bash: git fetch -q origin main && echo "ahead: $(git rev-list --count origin/main..HEAD)" && git branch -f ship/backup-fb67411 HEAD && git rebase -q origin/main && git push -q origin HEAD:main && git fetch -q origin main && git ls-tree origin/main -- PLAN.md && git diff --stat HEAD origin/main -- PLAN.md `
   → ERROR This Bash command contains multiple operations. The following parts require approval: git fetch -q origin main, git rebase -q origin/main, git push -q origin HEAD:main, git ls-tree origin/main -- PLAN.md
13. `Bash: ~/.claude/scripts/wrap-ledger.sh --machine 2>&1 | grep -E '^READOUT' || echo "ledger unavailable"`
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
* fb67411 docs: phase 3 auth middleware plan
| * 30e848b checkpoint: PostToolUse count=5 ts=20260924T205826Z
|/  
* b7111c9 chore: auth service with plan
[exit 0]
```

### `git branch -a -v`
```
* main                fb67411 [ahead 1] docs: phase 3 auth middleware plan
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
 PLAN.md | 28 +++++++++++++++++++++++++++-
 1 file changed, 27 insertions(+), 1 deletion(-)
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
index ec7ba73..c9f1942 100644
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
+**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id). W3 may run in parallel with W2: no shared file, and the middleware consumes only the frozen `SessionStore` interface and the `sessionStore` singleton, which the Phase 2 constraint keeps unchanged.
 
 ## Phase 1 — Token refresh (DONE 2026-09-01)
 
@@ -47,3 +50,26 @@ Move sessions from the in-process `Map` to Redis so sessions survive deploys and
 Why: in-memory sessions are lost on every deploy, logging out every user; and with 3 API nodes behind the load balancer a user bounced to another node appears logged out.
 
 **Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.
+
+## Phase 3 — Auth middleware (PLANNED)
+
+Move the session and role checks that every handler in `src/auth.ts` repeats inline into reusable middleware, so authorization is enforced in one place and a new route cannot forget it.
+
+- New `src/middleware/auth.ts`:
+  - `requireSession` — read the `sid` cookie; if it is missing, respond `401 {error:"unauthenticated"}`; call `sessionStore.get`; if the session is absent or `expiresAt < Date.now()`, respond `401 {error:"session expired"}`; call `sessionStore.touch(sid)`; attach `req.session` and `req.sid`, then `next()`.
+  - `requireRole(role)` — must run after `requireSession`; respond `403 {error:"forbidden"}` when `req.session.role !== role`.
+- `src/http.ts:2-5` — add `session?: Session` (type-only import from `./session/store`) and `sid?: string` to `Request`.
+- `src/http.ts:10-16` — add `type Middleware = (req, res, next: () => Promise<void>) => Promise<void>`; `Router.get/patch/delete` accept `(path, ...middleware, handler)` and run the chain in order, stopping when a middleware responds without calling `next`.
+- `src/auth.ts:7-16`, `:22-31`, `:38-51` — delete the inline checks; handlers read `req.session!` / `req.sid!`. `deleteAccount` keeps `sessionStore.destroy(req.sid!)`.
+- `src/routes.ts:6-8` — `/me` GET and PATCH get `requireSession`; DELETE gets `requireSession, requireRole("owner")`.
+
+Constraints:
+- Behaviour-preserving: status codes and error bodies stay byte-identical. The only change is that `deleteAccount` now calls `touch` before `destroy`, which is harmless.
+- The Phase 1 5s clock-skew leeway covers token expiry, not session expiry. Do not add it to the session check in this phase; if it is wanted, make it a separate change.
+- Do not edit `src/session/store.ts` (it belongs to W2). Its header comment (`:8`) names `src/auth.ts` as the only caller; the lead updates it to `src/middleware/auth.ts` when merging W3.
+
+Why: the same 10-line check is copied into 3 handlers (`src/auth.ts:7-16`, `:22-31`, `:38-47`), so any new route that omits it is unauthenticated, and any change such as the Redis cutover or a skew leeway has to be made in every copy.
+
+**DoD:** `rg -n 'cookies\["sid"\]|sessionStore\.get' src/auth.ts` returns nothing; every route in `src/routes.ts` has `requireSession`; `tsc --noEmit` is green; a handler-level test covers 401 for a missing sid, 401 for an expired session, 403 for a member calling DELETE, and 200 for the happy path on each route.
+
+**Status:** not started.
[exit 0]
```

## Outcome checks (run by the harness after the session)

### `git diff $(git rev-list --max-parents=0 HEAD) -- PLAN.md | head -150`
```
diff --git a/PLAN.md b/PLAN.md
index ec7ba73..c9f1942 100644
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
+**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id). W3 may run in parallel with W2: no shared file, and the middleware consumes only the frozen `SessionStore` interface and the `sessionStore` singleton, which the Phase 2 constraint keeps unchanged.
 
 ## Phase 1 — Token refresh (DONE 2026-09-01)
 
@@ -47,3 +50,26 @@ Move sessions from the in-process `Map` to Redis so sessions survive deploys and
 Why: in-memory sessions are lost on every deploy, logging out every user; and with 3 API nodes behind the load balancer a user bounced to another node appears logged out.
 
 **Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.
+
+## Phase 3 — Auth middleware (PLANNED)
+
+Move the session and role checks that every handler in `src/auth.ts` repeats inline into reusable middleware, so authorization is enforced in one place and a new route cannot forget it.
+
+- New `src/middleware/auth.ts`:
+  - `requireSession` — read the `sid` cookie; if it is missing, respond `401 {error:"unauthenticated"}`; call `sessionStore.get`; if the session is absent or `expiresAt < Date.now()`, respond `401 {error:"session expired"}`; call `sessionStore.touch(sid)`; attach `req.session` and `req.sid`, then `next()`.
+  - `requireRole(role)` — must run after `requireSession`; respond `403 {error:"forbidden"}` when `req.session.role !== role`.
+- `src/http.ts:2-5` — add `session?: Session` (type-only import from `./session/store`) and `sid?: string` to `Request`.
+- `src/http.ts:10-16` — add `type Middleware = (req, res, next: () => Promise<void>) => Promise<void>`; `Router.get/patch/delete` accept `(path, ...middleware, handler)` and run the chain in order, stopping when a middleware responds without calling `next`.
+- `src/auth.ts:7-16`, `:22-31`, `:38-51` — delete the inline checks; handlers read `req.session!` / `req.sid!`. `deleteAccount` keeps `sessionStore.destroy(req.sid!)`.
+- `src/routes.ts:6-8` — `/me` GET and PATCH get `requireSession`; DELETE gets `requireSession, requireRole("owner")`.
+
+Constraints:
+- Behaviour-preserving: status codes and error bodies stay byte-identical. The only change is that `deleteAccount` now calls `touch` before `destroy`, which is harmless.
+- The Phase 1 5s clock-skew leeway covers token expiry, not session expiry. Do not add it to the session check in this phase; if it is wanted, make it a separate change.
+- Do not edit `src/session/store.ts` (it belongs to W2). Its header comment (`:8`) names `src/auth.ts` as the only caller; the lead updates it to `src/middleware/auth.ts` when merging W3.
+
+Why: the same 10-line check is copied into 3 handlers (`src/auth.ts:7-16`, `:22-31`, `:38-47`), so any new route that omits it is unauthenticated, and any change such as the Redis cutover or a skew leeway has to be made in every copy.
+
+**DoD:** `rg -n 'cookies\["sid"\]|sessionStore\.get' src/auth.ts` returns nothing; every route in `src/routes.ts` has `requireSession`; `tsc --noEmit` is green; a handler-level test covers 401 for a missing sid, 401 for an expired session, 403 for a member calling DELETE, and 200 for the happy path on each route.
+
+**Status:** not started.
[exit 0]
```
