# Dossier

## Prompt

```
add a phase to PLAN.md for moving the auth checks into middleware
```

## Final assistant message (verbatim)

```
📦 Done, but only on a branch (1 commit(s) unlanded): the new Phase 3 plan is committed locally as `45e2482`, but the push to `main` needs your approval.
Good to close: no — the one plan commit still has to be pushed to `main`; that step is yours.
▶ Run this:

`git -C /work/fx push origin HEAD:main`

**What's in `PLAN.md` now:**
- **Phase 3 — Auth checks into middleware.** A new `requireAuth(handler, { role, touch })` wrapper in `src/middleware/auth.ts` replaces the three copies of the session check in `src/auth.ts`. It keeps today's responses exactly: 401 for no cookie, 401 for an expired session, and 403 for the wrong role. It still extends the session on every request except account deletion, which never did. Each item gives the file and line range to change, the reason for the phase, and a check that proves it's done.
- **Phase 0:** added a third wave. It runs as a separate dispatched session in its own worktree on branch `feat/auth-middleware`, and waits until the Phase 2 Redis cutover is finished.
- **Two things for whoever picks up Phase 3:**
  - **Clock-skew leeway (undecided):** should session expiry get the same 5s allowance Phase 1 gave tokens? The plan's default is no, so this phase stays a pure refactor.
  - **Unfinished Redis `touch` (depends on Phase 2):** it doesn't yet update the session's stored expiry time. Until Phase 2 fixes that, the middleware's expiry check would log users out 30 minutes after login, however active they are.

A local backup branch, `ship/backup-45e2482`, is still there. Delete it once the push lands.
```

## Tool calls in order (14), each with the first 300 chars of its result

1. `Bash: git ls-files && echo ---- && cat -n PLAN.md`
   → PLAN.md ⏎ src/auth.ts ⏎ src/http.ts ⏎ src/routes.ts ⏎ src/session/store.ts ⏎ ---- ⏎      1	# Auth service plan ⏎      2	 ⏎      3	Scope (frozen): harden the auth service — reliable token refresh, durable session store, consistent request authorization. ⏎      4	 ⏎      5	## Phase 0 — Orchestration ⏎
2. `Bash: for f in src/auth.ts src/http.ts src/routes.ts src/session/store.ts; do echo "==== $f"; cat -n $f; done`
   → ==== src/auth.ts ⏎      1	import type { Request, Response } from "./http"; ⏎      2	import { sessionStore } from "./session/store"; ⏎      3	 ⏎      4	// Route handlers. Each one currently performs its own auth checks inline. ⏎      5	 ⏎      6	export async function getProfile(req: Request, res: Res
3. `Read: {"file_path": "/work/fx/PLAN.md"}`
   → 1	# Auth service plan ⏎ 2	 ⏎ 3	Scope (frozen): harden the auth service — reliable token refresh, durable session store, consistent request authorization. ⏎ 4	 ⏎ 5	## Phase 0 — Orchestration ⏎ 6	 ⏎ 7	**Execution locus per wave:** ⏎ 8	 ⏎ 9	| Wave | Phase | Locus | Why | ⏎ 10	|---|---|---|---| ⏎ 11	| W
4. `Skill: {"skill": "plan-conventions"}`
   → Launching skill: plan-conventions
5. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "| W2 | Phase 2 — Session store migration | S (dispatched session) | implementation wave — default |\n", "new_string": "| W2 | Phase 2 — Session store migration | S (dispatched session) | implementation wave — default |\n| W3 | Ph`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
6. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "- wave-2 session — `src/session/store.ts`, `src/session/redis.ts`\n", "new_string": "- wave-2 session — `src/session/store.ts`, `src/session/redis.ts`\n- wave-3 session — `src/middleware/auth.ts` (new), `src/http.ts`, `src/auth.t`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
7. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "- W2: `.worktrees/wt-session-store` on `feat/session-store`\n\n**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id).", "new_string": "- W2: `.worktrees/wt-session-store` on `feat/session-store`\n- W3: `
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
8. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "**Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.\n", "new_string": "**Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.\n\n## Phase 3 — Auth checks into middleware (PLANNED`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
9. `Bash: git diff --name-only && git add PLAN.md && git commit -q -m "docs: plan phase 3 for auth middleware" && git log --oneline -1 && git status --short && (git remote -v | head -1; echo "remotes above")`
   → PLAN.md ⏎ 45e2482 docs: plan phase 3 for auth middleware ⏎ origin	/work/origin.git (fetch) ⏎ remotes above
10. `Skill: {"skill": "ship"}`
   → Launching skill: ship
11. `Bash: T=$(git symbolic-ref --quiet refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@'); T=${T:-main}; echo trunk=$T; git fetch -q origin $T && git branch -f ship/backup-$(git rev-parse --short HEAD) HEAD && git rebase -q origin/$T && git diff --name-only origin/$T..HEAD && git push -q origin HEAD:`
   → ERROR Contains expansion
12. `Bash: git symbolic-ref --quiet refs/remotes/origin/HEAD; git fetch -q origin main && git branch -f ship/backup-45e2482 HEAD && git rebase -q origin/main && git diff --name-only origin/main..HEAD`
   → PLAN.md
13. `Bash: git push -q origin HEAD:main && git fetch -q origin main && git ls-tree origin/main -- PLAN.md && git diff --quiet HEAD origin/main -- PLAN.md && echo content-verified && git branch -D -q ship/backup-45e2482 && git log --oneline -1 origin/main && git status --short`
   → ERROR This Bash command contains multiple operations. The following parts require approval: git push -q origin HEAD:main, git fetch -q origin main, git ls-tree origin/main -- PLAN.md
14. `Bash: ~/.claude/scripts/wrap-ledger.sh --machine 2>&1 | grep -E '^READOUT' ; git log --oneline -2; git status --short`
   → READOUT=📦 Done, but only on a branch (1 commit(s) unlanded) — /ship to land it (else lost). ⏎ 45e2482 docs: plan phase 3 for auth middleware ⏎ b7111c9 chore: auth service with plan

Stop-hook feedback turns: 0. Hook blocking errors: 0.

## Repo state after the run

### `git status --short --branch`
```
## main...origin/main [ahead 1]
[exit 0]
```

### `git log --oneline --all --graph -8`
```
* 45e2482 docs: plan phase 3 for auth middleware
| * 23883fb checkpoint: PostToolUse count=5 ts=20260924T211220Z
|/  
* b7111c9 chore: auth service with plan
[exit 0]
```

### `git branch -a -v`
```
* main                45e2482 [ahead 1] docs: plan phase 3 for auth middleware
  ship/backup-45e2482 45e2482 docs: plan phase 3 for auth middleware
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
 PLAN.md | 29 ++++++++++++++++++++++++++++-
 1 file changed, 28 insertions(+), 1 deletion(-)
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
index ec7ba73..6c627bb 100644
--- a/PLAN.md
+++ b/PLAN.md
@@ -10,6 +10,9 @@ Scope (frozen): harden the auth service — reliable token refresh, durable sess
 |---|---|---|---|
 | W1 | Phase 1 — Token refresh | S (dispatched session) | implementation wave — default |
 | W2 | Phase 2 — Session store migration | S (dispatched session) | implementation wave — default |
+| W3 | Phase 3 — Auth checks into middleware | S (dispatched session) | implementation wave — default |
+
+**Task size:** W3 is one unit, 4 files (`src/middleware/auth.ts` new, `src/http.ts`, `src/auth.ts`, `src/routes.ts`), inside the 3–6-file band; do not split.
 
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
+**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id). W3 blockedBy W2 cutover: the files are disjoint, but Phase 2 freezes the `src/auth.ts` callers during dual-write so any session regression is attributable to the store, not to the refactor.
 
 ## Phase 1 — Token refresh (DONE 2026-09-01)
 
@@ -47,3 +52,25 @@ Move sessions from the in-process `Map` to Redis so sessions survive deploys and
 Why: in-memory sessions are lost on every deploy, logging out every user; and with 3 API nodes behind the load balancer a user bounced to another node appears logged out.
 
 **Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.
+
+## Phase 3 — Auth checks into middleware (PLANNED)
+
+Every handler in `src/auth.ts` repeats the same cookie → session lookup → expiry → touch block, so one handler that gets it wrong leaves a hole. This phase moves that block into one middleware and leaves the handlers with business logic only.
+
+- New `src/middleware/auth.ts` — `requireAuth(handler: AuthedHandler, opts?: { role?: Session["role"]; touch?: boolean }): Handler`. `Router` (`src/http.ts:11-16`) has no middleware chain, so wrap the handler instead of changing `Router`. The wrapper must keep today's responses exactly:
+  - no `sid` cookie → `401 { error: "unauthenticated" }` (`src/auth.ts:7-11`)
+  - session missing or `expiresAt < Date.now()` → `401 { error: "session expired" }` (`src/auth.ts:12-16`)
+  - `opts.role` set and `session.role` differs → `403 { error: "forbidden" }` (`src/auth.ts:48-51`), checked after the expiry check
+  - `opts.touch` (default `true`) → `sessionStore.touch(sid)` before the handler runs (`src/auth.ts:17`, `:32`)
+- `src/http.ts:2-5` — add `AuthedRequest extends Request { sid: string; session: Session }` and `AuthedHandler = (req: AuthedRequest, res: Response) => Promise<void>`. Leave `Request` itself unchanged so unauthenticated routes keep their type.
+- `src/auth.ts:6-55` — delete the inline blocks. Handlers read `req.session` and `req.sid`. `deleteAccount` keeps `sessionStore.destroy(req.sid)`.
+- `src/routes.ts:6-8` — `requireAuth(getProfile)`, `requireAuth(updateProfile)`, `requireAuth(deleteAccount, { role: "owner", touch: false })`. Today `deleteAccount` never calls touch, so `touch: false` keeps that.
+- The middleware uses only the `sessionStore` singleton and `SessionStore` interface (`src/session/store.ts:28-37`, `:119`), so it works on either backend and does not reopen the interface Phase 2 froze.
+
+Why: "consistent request authorization" is in the frozen scope, and three copies of the same check can drift apart. A new route that forgets the check is an open endpoint. With the middleware, protection is decided once in `routes.ts`.
+
+**Open question for the brief:** Phase 1 added a 5s clock-skew leeway to token expiry. Session `expiresAt` is set by whichever node last called `touch`, so the same skew applies here. The default is to keep the strict check so this phase stays a pure refactor. Adding the leeway would be its own commit.
+
+**Depends on:** Phase 2 cutover. Its `RedisStore.touch` TODO (`src/session/store.ts:109`) must also update the stored `expiresAt`. Otherwise the middleware's expiry check logs users out 30 min after login no matter how active they are.
+
+**Done when:** `grep -rn 'cookies\["sid"\]' src/` matches only `src/middleware/auth.ts`, the typecheck passes, and each of the five paths (no cookie, expired, wrong role, touch, no touch) has a test with the same status and body as before.
[exit 0]
```

## Outcome checks (run by the harness after the session)

### `git diff $(git rev-list --max-parents=0 HEAD) -- PLAN.md | head -150`
```
diff --git a/PLAN.md b/PLAN.md
index ec7ba73..6c627bb 100644
--- a/PLAN.md
+++ b/PLAN.md
@@ -10,6 +10,9 @@ Scope (frozen): harden the auth service — reliable token refresh, durable sess
 |---|---|---|---|
 | W1 | Phase 1 — Token refresh | S (dispatched session) | implementation wave — default |
 | W2 | Phase 2 — Session store migration | S (dispatched session) | implementation wave — default |
+| W3 | Phase 3 — Auth checks into middleware | S (dispatched session) | implementation wave — default |
+
+**Task size:** W3 is one unit, 4 files (`src/middleware/auth.ts` new, `src/http.ts`, `src/auth.ts`, `src/routes.ts`), inside the 3–6-file band; do not split.
 
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
+**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id). W3 blockedBy W2 cutover: the files are disjoint, but Phase 2 freezes the `src/auth.ts` callers during dual-write so any session regression is attributable to the store, not to the refactor.
 
 ## Phase 1 — Token refresh (DONE 2026-09-01)
 
@@ -47,3 +52,25 @@ Move sessions from the in-process `Map` to Redis so sessions survive deploys and
 Why: in-memory sessions are lost on every deploy, logging out every user; and with 3 API nodes behind the load balancer a user bounced to another node appears logged out.
 
 **Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.
+
+## Phase 3 — Auth checks into middleware (PLANNED)
+
+Every handler in `src/auth.ts` repeats the same cookie → session lookup → expiry → touch block, so one handler that gets it wrong leaves a hole. This phase moves that block into one middleware and leaves the handlers with business logic only.
+
+- New `src/middleware/auth.ts` — `requireAuth(handler: AuthedHandler, opts?: { role?: Session["role"]; touch?: boolean }): Handler`. `Router` (`src/http.ts:11-16`) has no middleware chain, so wrap the handler instead of changing `Router`. The wrapper must keep today's responses exactly:
+  - no `sid` cookie → `401 { error: "unauthenticated" }` (`src/auth.ts:7-11`)
+  - session missing or `expiresAt < Date.now()` → `401 { error: "session expired" }` (`src/auth.ts:12-16`)
+  - `opts.role` set and `session.role` differs → `403 { error: "forbidden" }` (`src/auth.ts:48-51`), checked after the expiry check
+  - `opts.touch` (default `true`) → `sessionStore.touch(sid)` before the handler runs (`src/auth.ts:17`, `:32`)
+- `src/http.ts:2-5` — add `AuthedRequest extends Request { sid: string; session: Session }` and `AuthedHandler = (req: AuthedRequest, res: Response) => Promise<void>`. Leave `Request` itself unchanged so unauthenticated routes keep their type.
+- `src/auth.ts:6-55` — delete the inline blocks. Handlers read `req.session` and `req.sid`. `deleteAccount` keeps `sessionStore.destroy(req.sid)`.
+- `src/routes.ts:6-8` — `requireAuth(getProfile)`, `requireAuth(updateProfile)`, `requireAuth(deleteAccount, { role: "owner", touch: false })`. Today `deleteAccount` never calls touch, so `touch: false` keeps that.
+- The middleware uses only the `sessionStore` singleton and `SessionStore` interface (`src/session/store.ts:28-37`, `:119`), so it works on either backend and does not reopen the interface Phase 2 froze.
+
+Why: "consistent request authorization" is in the frozen scope, and three copies of the same check can drift apart. A new route that forgets the check is an open endpoint. With the middleware, protection is decided once in `routes.ts`.
+
+**Open question for the brief:** Phase 1 added a 5s clock-skew leeway to token expiry. Session `expiresAt` is set by whichever node last called `touch`, so the same skew applies here. The default is to keep the strict check so this phase stays a pure refactor. Adding the leeway would be its own commit.
+
+**Depends on:** Phase 2 cutover. Its `RedisStore.touch` TODO (`src/session/store.ts:109`) must also update the stored `expiresAt`. Otherwise the middleware's expiry check logs users out 30 min after login no matter how active they are.
+
+**Done when:** `grep -rn 'cookies\["sid"\]' src/` matches only `src/middleware/auth.ts`, the typecheck passes, and each of the five paths (no cookie, expired, wrong role, touch, no touch) has a test with the same status and body as before.
[exit 0]
```
