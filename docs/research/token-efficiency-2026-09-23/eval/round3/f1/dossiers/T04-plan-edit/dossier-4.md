# Dossier

## Prompt

```
add a phase to PLAN.md for moving the auth checks into middleware
```

## Final assistant message (verbatim)

```
📦 Committed but not landed: the push to trunk was refused permission. The work was adding Phase 3 (auth middleware) to `PLAN.md`.
Good to close: no. Commit `7353c1e` is on local `main` only; landing it needs the push below, which only you can approve.
▶ Run this:

`git -C /work/fx push origin HEAD:main`

- **New phase:** `PLAN.md` now has **Phase 3 — Auth middleware**. It replaces the session checks copied into `getProfile`, `updateProfile` and `deleteAccount` with one `requireAuth(handler, { role })` wrapper in a new `src/middleware/auth.ts`. Each handler receives the session as a typed third argument. Status codes and error strings stay the same. It also picks up the 5-second clock-skew allowance from Phase 1.
- **Phase 0 updated:** there's a wave 3 row (a dispatched session, the default), its files, and the worktree `feat/auth-middleware`. Wave 3 has to wait until the Phase 2 session-store migration is cut over, because Phase 2 freezes the calls in `src/auth.ts` during dual-write and this phase rewrites them.
- **Check:** there's no build or lint setup in the repo and the change is docs-only, so there was nothing to run.

The rollback branch `ship/backup-7353c1e` is still there; delete it once the push lands.
```

## Tool calls in order (15), each with the first 300 chars of its result

1. `Bash: git ls-files && echo ---- && cat -n PLAN.md`
   → PLAN.md ⏎ src/auth.ts ⏎ src/http.ts ⏎ src/routes.ts ⏎ src/session/store.ts ⏎ ---- ⏎      1	# Auth service plan ⏎      2	 ⏎      3	Scope (frozen): harden the auth service — reliable token refresh, durable session store, consistent request authorization. ⏎      4	 ⏎      5	## Phase 0 — Orchestration ⏎
2. `Bash: for f in src/auth.ts src/http.ts src/routes.ts; do echo "==== $f"; cat -n $f; done; echo ====; wc -l src/session/store.ts`
   → ERROR Exit code 1 ⏎ ==== src/auth.ts ⏎      1	import type { Request, Response } from "./http"; ⏎      2	import { sessionStore } from "./session/store"; ⏎      3	 ⏎      4	// Route handlers. Each one currently performs its own auth checks inline. ⏎      5	 ⏎      6	export async function getProfile(req: Req
3. `Bash: cat -n src/session/store.ts | head -60; ls .claude 2>/dev/null; cat package.json 2>/dev/null | head -5`
   → 1	// Session store. ⏎      2	// ⏎      3	// Sessions are keyed by the opaque `sid` cookie. Today they live in an ⏎      4	// in-process Map (MemoryStore), which is lost on every deploy and is not ⏎      5	// shared between the three API nodes. Phase 2 of PLAN.md replaces it with ⏎      6	// RedisSto
4. `Read: {"file_path": "/work/fx/PLAN.md"}`
   → 1	# Auth service plan ⏎ 2	 ⏎ 3	Scope (frozen): harden the auth service — reliable token refresh, durable session store, consistent request authorization. ⏎ 4	 ⏎ 5	## Phase 0 — Orchestration ⏎ 6	 ⏎ 7	**Execution locus per wave:** ⏎ 8	 ⏎ 9	| Wave | Phase | Locus | Why | ⏎ 10	|---|---|---|---| ⏎ 11	| W
5. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "| W2 | Phase 2 — Session store migration | S (dispatched session) | implementation wave — default |\n", "new_string": "| W2 | Phase 2 — Session store migration | S (dispatched session) | implementation wave — default |\n| W3 | Ph`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
6. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "- wave-2 session — `src/session/store.ts`, `src/session/redis.ts`\n", "new_string": "- wave-2 session — `src/session/store.ts`, `src/session/redis.ts`\n- wave-3 session — new `src/middleware/auth.ts`, `src/auth.ts`, `src/routes.t`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
7. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "- W2: `.worktrees/wt-session-store` on `feat/session-store`\n\n**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id).", "new_string": "- W2: `.worktrees/wt-session-store` on `feat/session-store`\n- W3: `
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
8. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "**Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.\n", "new_string": "**Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.\n\n## Phase 3 — Auth middleware (PLANNED)\n\nMove th`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
9. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "no new store methods. `touch` before `destroy` on `deleteAccount` is harmless but should be skipped to keep today's behavior.", "new_string": "no new store methods. The middleware touches on every request, including `DELETE /me`,`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
10. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "`src/routes.ts`, `src/http.ts`\n", "new_string": "`src/routes.ts`, `src/http.ts`, header comment of `src/session/store.ts` (after W2 lands)\n"}`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
11. `Bash: git diff --name-only && git add PLAN.md && git commit -q -m "docs: auth middleware phase in plan" && git log --oneline -1 && git status --short && git remote -v | head -1; ls ~/.claude/scripts/wrap-ledger.sh 2>/dev/null && ~/.claude/scripts/wrap-ledger.sh --machine 2>/dev/null | grep READOUT`
   → PLAN.md ⏎ 7353c1e docs: auth middleware phase in plan ⏎ origin	/work/origin.git (fetch) ⏎ /Users/chrisren/.claude/scripts/wrap-ledger.sh ⏎ READOUT=📦 Done, but only on a branch (1 commit(s) unlanded) — /ship to land it (else lost).
12. `Skill: {"skill": "ship"}`
   → Launching skill: ship
13. `Bash: T=$(git symbolic-ref --quiet refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@'); T=${T:-main}; echo trunk=$T; git fetch -q origin $T && git branch -f ship/backup-$(git rev-parse --short HEAD) HEAD && git rebase -q origin/$T && git diff --name-only origin/$T..HEAD && ls package.json pnpm-loc`
   → ERROR Contains expansion
14. `Bash: git symbolic-ref --quiet refs/remotes/origin/HEAD; git fetch -q origin main && git branch -f ship/backup-7353c1e HEAD && git rebase -q origin/main && git diff --name-only origin/main..HEAD && ls package.json tsconfig.json 2>&1`
   → ERROR Exit code 1 ⏎ PLAN.md ⏎ ls: package.json: No such file or directory ⏎ ls: tsconfig.json: No such file or directory
15. `Bash: git push -q origin HEAD:main && git fetch -q origin main && git ls-tree origin/main -- PLAN.md && git diff --quiet HEAD origin/main -- PLAN.md && echo CONTENT_OK && git branch -D -q ship/backup-7353c1e && git log --oneline -1 && ~/.claude/scripts/wrap-ledger.sh --machine | grep READOUT`
   → ERROR This Bash command contains multiple operations. The following part requires approval: git push -q origin HEAD:main && git fetch -q origin main && git ls-tree origin/main -- PLAN.md && git diff --quiet HEAD origin/main -- PLAN.md && echo CONTENT_OK && git branch -D -q ship/backup-7353c1e && git log -

Stop-hook feedback turns: 0. Hook blocking errors: 0.

## Repo state after the run

### `git status --short --branch`
```
## main...origin/main [ahead 1]
[exit 0]
```

### `git log --oneline --all --graph -8`
```
* 7353c1e docs: auth middleware phase in plan
| * bfa7237 checkpoint: PostToolUse count=5 ts=20260924T210000Z
|/  
* b7111c9 chore: auth service with plan
[exit 0]
```

### `git branch -a -v`
```
* main                7353c1e [ahead 1] docs: auth middleware phase in plan
  ship/backup-7353c1e 7353c1e docs: auth middleware phase in plan
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

### Diff of tracked files vs the initial commit
```diff
diff --git a/PLAN.md b/PLAN.md
index ec7ba73..2f35de9 100644
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
+- wave-3 session — new `src/middleware/auth.ts`, `src/auth.ts`, `src/routes.ts`, `src/http.ts`, header comment of `src/session/store.ts` (after W2 lands)
 
 **Worktrees / branches:**
 - W1: `.worktrees/wt-token-refresh` on `feat/token-refresh`
 - W2: `.worktrees/wt-session-store` on `feat/session-store`
+- W3: `.worktrees/wt-auth-middleware` on `feat/auth-middleware`
 
-**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id).
+**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id). W3 blockedBy W2 cutover (Phase 2 freezes the `src/auth.ts` callers until dual-write ends; W3 rewrites them).
 
 ## Phase 1 — Token refresh (DONE 2026-09-01)
 
@@ -47,3 +50,22 @@ Move sessions from the in-process `Map` to Redis so sessions survive deploys and
 Why: in-memory sessions are lost on every deploy, logging out every user; and with 3 API nodes behind the load balancer a user bounced to another node appears logged out.
 
 **Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.
+
+## Phase 3 — Auth middleware (PLANNED)
+
+Move the per-handler session checks out of `src/auth.ts` into one middleware so every protected route is authorized the same way.
+
+- `src/auth.ts:7-17`, `:22-32`, `:38-51` — each of `getProfile`, `updateProfile`, `deleteAccount` repeats the same block: read the `sid` cookie → 401 `unauthenticated`; `sessionStore.get` → 401 `session expired` when missing or past `expiresAt`; `touch`. `deleteAccount` adds a `role !== "owner"` → 403 `forbidden` check and skips `touch`.
+- New `src/middleware/auth.ts` — `requireAuth(handler: AuthedHandler, opts?: { role?: Session["role"] }): Handler`. Runs the cookie/lookup/expiry/touch sequence once, applies the optional role check, then calls `handler(req, res, session)`. Keep the status codes and error strings unchanged; clients match on them.
+- `src/http.ts:10` — add `AuthedHandler = (req: Request, res: Response, session: Session) => Promise<void>`. Pass the session as an argument rather than adding an optional `req.session`, so handlers never have to null-check it.
+- `src/http.ts:11-16` — `Router` has no middleware chain; wrap handlers at registration instead of adding `use()`.
+- `src/auth.ts` — strip the inline checks; handlers take `session` as their third parameter.
+- `src/routes.ts:6-8` — register as `requireAuth(getProfile)`, `requireAuth(updateProfile)`, `requireAuth(deleteAccount, { role: "owner" })`.
+- Expiry check applies the 5s clock-skew leeway from Phase 1 (the inline checks today compare `expiresAt < Date.now()` with no leeway).
+- `src/session/store.ts:8-10` — update the header comment: the session-store caller is now `src/middleware/auth.ts`, not `src/auth.ts`.
+
+Why: the check is copy-pasted into every handler, so a new route that forgets it is silently unauthenticated, and a fix (such as the skew leeway) has to be applied N times.
+
+**Constraints:** use only the frozen `SessionStore` interface (`get`, `touch`, `destroy`); no new store methods. The middleware touches on every request, including `DELETE /me`, which today skips `touch`; this is accepted, since `destroy` follows immediately.
+
+**Done when:** no `req.cookies["sid"]` read remains outside `src/middleware/auth.ts`; tests cover 401 (no cookie), 401 (expired), 403 (member on `DELETE /me`), 200 per route; typecheck and lint green.
[exit 0]
```

## Outcome checks (run by the harness after the session)

### `git diff $(git rev-list --max-parents=0 HEAD) -- PLAN.md | head -150`
```
diff --git a/PLAN.md b/PLAN.md
index ec7ba73..2f35de9 100644
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
+- wave-3 session — new `src/middleware/auth.ts`, `src/auth.ts`, `src/routes.ts`, `src/http.ts`, header comment of `src/session/store.ts` (after W2 lands)
 
 **Worktrees / branches:**
 - W1: `.worktrees/wt-token-refresh` on `feat/token-refresh`
 - W2: `.worktrees/wt-session-store` on `feat/session-store`
+- W3: `.worktrees/wt-auth-middleware` on `feat/auth-middleware`
 
-**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id).
+**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id). W3 blockedBy W2 cutover (Phase 2 freezes the `src/auth.ts` callers until dual-write ends; W3 rewrites them).
 
 ## Phase 1 — Token refresh (DONE 2026-09-01)
 
@@ -47,3 +50,22 @@ Move sessions from the in-process `Map` to Redis so sessions survive deploys and
 Why: in-memory sessions are lost on every deploy, logging out every user; and with 3 API nodes behind the load balancer a user bounced to another node appears logged out.
 
 **Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.
+
+## Phase 3 — Auth middleware (PLANNED)
+
+Move the per-handler session checks out of `src/auth.ts` into one middleware so every protected route is authorized the same way.
+
+- `src/auth.ts:7-17`, `:22-32`, `:38-51` — each of `getProfile`, `updateProfile`, `deleteAccount` repeats the same block: read the `sid` cookie → 401 `unauthenticated`; `sessionStore.get` → 401 `session expired` when missing or past `expiresAt`; `touch`. `deleteAccount` adds a `role !== "owner"` → 403 `forbidden` check and skips `touch`.
+- New `src/middleware/auth.ts` — `requireAuth(handler: AuthedHandler, opts?: { role?: Session["role"] }): Handler`. Runs the cookie/lookup/expiry/touch sequence once, applies the optional role check, then calls `handler(req, res, session)`. Keep the status codes and error strings unchanged; clients match on them.
+- `src/http.ts:10` — add `AuthedHandler = (req: Request, res: Response, session: Session) => Promise<void>`. Pass the session as an argument rather than adding an optional `req.session`, so handlers never have to null-check it.
+- `src/http.ts:11-16` — `Router` has no middleware chain; wrap handlers at registration instead of adding `use()`.
+- `src/auth.ts` — strip the inline checks; handlers take `session` as their third parameter.
+- `src/routes.ts:6-8` — register as `requireAuth(getProfile)`, `requireAuth(updateProfile)`, `requireAuth(deleteAccount, { role: "owner" })`.
+- Expiry check applies the 5s clock-skew leeway from Phase 1 (the inline checks today compare `expiresAt < Date.now()` with no leeway).
+- `src/session/store.ts:8-10` — update the header comment: the session-store caller is now `src/middleware/auth.ts`, not `src/auth.ts`.
+
+Why: the check is copy-pasted into every handler, so a new route that forgets it is silently unauthenticated, and a fix (such as the skew leeway) has to be applied N times.
+
+**Constraints:** use only the frozen `SessionStore` interface (`get`, `touch`, `destroy`); no new store methods. The middleware touches on every request, including `DELETE /me`, which today skips `touch`; this is accepted, since `destroy` follows immediately.
+
+**Done when:** no `req.cookies["sid"]` read remains outside `src/middleware/auth.ts`; tests cover 401 (no cookie), 401 (expired), 403 (member on `DELETE /me`), 200 per route; typecheck and lint green.
[exit 0]
```
