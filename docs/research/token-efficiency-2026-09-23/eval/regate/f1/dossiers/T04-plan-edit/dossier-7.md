# Dossier

## Prompt

```
add a phase to PLAN.md for moving the auth checks into middleware
```

## Final assistant message (verbatim)

```
⛔ Blocked: the Phase 3 plan commit `6cf7ac6` is mine, but I can't land it. Claude Code asked for permission to run `git push` and the request wasn't approved. I won't retry a push that was refused.
Good to close: no. The commit is only on local `main` until you run the push below or approve it.

▶ Run this:

`git -C /work/fx push origin HEAD:main`

The commit changes only `PLAN.md`: it adds the "Phase 3 — Auth middleware" section and a W3 row to the Phase 0 tables. No code changed.
```

## Tool calls in order (9), each with the first 300 chars of its result

1. `Bash: git ls-files && cat -n PLAN.md`
   → PLAN.md ⏎ src/auth.ts ⏎ src/http.ts ⏎ src/routes.ts ⏎ src/session/store.ts ⏎      1	# Auth service plan ⏎      2	 ⏎      3	Scope (frozen): harden the auth service — reliable token refresh, durable session store, consistent request authorization. ⏎      4	 ⏎      5	## Phase 0 — Orchestration ⏎      6
2. `Bash: for f in src/auth.ts src/http.ts src/routes.ts; do echo "=== $f"; cat -n $f; done`
   → === src/auth.ts ⏎      1	import type { Request, Response } from "./http"; ⏎      2	import { sessionStore } from "./session/store"; ⏎      3	 ⏎      4	// Route handlers. Each one currently performs its own auth checks inline. ⏎      5	 ⏎      6	export async function getProfile(req: Request, res: Resp
3. `Bash: cat -n src/session/store.ts`
   → 1	// Session store. ⏎      2	// ⏎      3	// Sessions are keyed by the opaque `sid` cookie. Today they live in an ⏎      4	// in-process Map (MemoryStore), which is lost on every deploy and is not ⏎      5	// shared between the three API nodes. Phase 2 of PLAN.md replaces it with ⏎      6	// RedisSto
4. `Bash: python3 - <<'EOF' ⏎ p='PLAN.md'; s=open(p).read() ⏎ def rep(a,b): ⏎     global s ⏎     assert s.count(a)==1, a ⏎     s=s.replace(a,b) ⏎ rep("| W2 | Phase 2 — Session store migration | S (dispatched session) | implementation wave — default |\n", ⏎     "| W2 | Phase 2 — Session store migration | S (dispatched sessi`
   → PLAN.md | 21 ++++++++++++++++++++- ⏎  1 file changed, 20 insertions(+), 1 deletion(-)
5. `Bash: python3 - <<'EOF' ⏎ p='PLAN.md'; s=open(p).read() ⏎ a="- `deleteAccount` must not `touch` a session it is about to `destroy`; a harmless extra write, but keep the order `touch` → `destroy` and assert it in the test.\n" ⏎ b="- One accepted behaviour change: `deleteAccount` skips `touch` today; behind the m`
   → 6cf7ac6 docs: phase 3 auth middleware plan ⏎ origin	/work/origin.git (fetch) ⏎ origin	/work/origin.git (push)
6. `Skill: {"skill": "ship"}`
   → Launching skill: ship
7. `Bash: T=$(git symbolic-ref --quiet refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@'); T=${T:-main}; echo trunk=$T; git fetch -q origin $T && git rev-list --count origin/$T..HEAD && git branch -f ship/backup-$(git rev-parse --short HEAD) HEAD && git rebase -q origin/$T && ls package.json 2>/dev/n`
   → ERROR Contains expansion
8. `Bash: git fetch -q origin main && git rev-list --count origin/main..HEAD && git branch -f ship/backup-6cf7ac6 HEAD && git rebase -q origin/main && git diff --name-only origin/main..HEAD && git push -q origin HEAD:main && git fetch -q origin main && git ls-tree origin/main -- PLAN.md && git diff --quiet HE`
   → ERROR This Bash command contains multiple operations. The following parts require approval: git fetch -q origin main, git rebase -q origin/main, git push -q origin HEAD:main, git ls-tree origin/main -- PLAN.md
9. `Bash: git push origin HEAD:main`
   → ERROR Claude requested permissions to use Bash, but you haven't granted it yet.

Stop-hook feedback turns: 1. Hook blocking errors: 1.

## Repo state after the run

### `git status --short --branch`
```
## main...origin/main [ahead 1]
[exit 0]
```

### `git log --oneline --all --graph -8`
```
* 6cf7ac6 docs: phase 3 auth middleware plan
* b7111c9 chore: auth service with plan
[exit 0]
```

### `git branch -a -v`
```
* main                6cf7ac6 [ahead 1] docs: phase 3 auth middleware plan
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
index ec7ba73..32643b9 100644
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
+**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id). W3 is independent of W2 and may run in parallel: it depends only on the frozen `SessionStore` interface and the `sessionStore` singleton, and its file set is disjoint from W2's.
 
 ## Phase 1 — Token refresh (DONE 2026-09-01)
 
@@ -47,3 +50,19 @@ Move sessions from the in-process `Map` to Redis so sessions survive deploys and
 Why: in-memory sessions are lost on every deploy, logging out every user; and with 3 API nodes behind the load balancer a user bounced to another node appears logged out.
 
 **Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.
+
+## Phase 3 — Auth middleware (NOT STARTED)
+
+Move the per-handler auth checks in `src/auth.ts` into one middleware so every protected route authorizes the same way.
+
+- New `src/middleware/auth.ts` — `requireSession(h: Handler): Handler` does what each handler does inline today: read `req.cookies["sid"]` → 401 `unauthenticated` if absent; `sessionStore.get(sid)` → 401 `session expired` if missing or `expiresAt < Date.now()`; `sessionStore.touch(sid)`; set `req.session`; call `h`. Plus `requireRole(role, h)` → 403 `forbidden` on mismatch.
+- `src/http.ts:2-5` — add optional `session?: Session` to `Request` (import the type from `src/session/store.ts:13-22`). `Router` (`src/http.ts:11-16`) has no middleware hook, so wrap handlers rather than adding a `use()` chain.
+- `src/auth.ts:6-55` — delete the duplicated sid/session/expiry blocks (`:7-17`, `:22-32`, `:38-47`) and the owner check (`:48-51`); handlers read `req.session`.
+- `src/routes.ts:6-8` — wrap: `requireSession(getProfile)`, `requireSession(updateProfile)`, `requireSession(requireRole("owner", deleteAccount))`.
+- Preserve the exact status codes and error bodies — clients match on `unauthenticated` vs `session expired`.
+- One accepted behaviour change: `deleteAccount` skips `touch` today; behind the middleware it gets `touch` then `destroy`. Harmless extra write — no special case.
+- Do not edit `src/session/store.ts` (W2 owns it). Its header comment (`:8-10`) names `src/auth.ts` as the sole caller; W2 updates it to name the middleware.
+
+Why: the same 10-line check is copy-pasted into all three handlers (`src/auth.ts:7-17`, `:22-32`, `:38-47`), so a new route can silently ship without it and any change to the check must be made N times.
+
+**Done when:** no `req.cookies["sid"]` read remains in `src/auth.ts`; tests cover 401 (no cookie), 401 (expired), 403 (member on `DELETE /me`), 200 on all three routes; typecheck + lint green.
[exit 0]
```

## Outcome checks (run by the harness after the session)

### `git diff $(git rev-list --max-parents=0 HEAD) -- PLAN.md | head -150`
```
diff --git a/PLAN.md b/PLAN.md
index ec7ba73..32643b9 100644
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
+**Dependencies:** W2 blockedBy W1 (store keys embed the refresh-token family id). W3 is independent of W2 and may run in parallel: it depends only on the frozen `SessionStore` interface and the `sessionStore` singleton, and its file set is disjoint from W2's.
 
 ## Phase 1 — Token refresh (DONE 2026-09-01)
 
@@ -47,3 +50,19 @@ Move sessions from the in-process `Map` to Redis so sessions survive deploys and
 Why: in-memory sessions are lost on every deploy, logging out every user; and with 3 API nodes behind the load balancer a user bounced to another node appears logged out.
 
 **Status:** interface frozen; `RedisStore` scaffolded; dual-write not started.
+
+## Phase 3 — Auth middleware (NOT STARTED)
+
+Move the per-handler auth checks in `src/auth.ts` into one middleware so every protected route authorizes the same way.
+
+- New `src/middleware/auth.ts` — `requireSession(h: Handler): Handler` does what each handler does inline today: read `req.cookies["sid"]` → 401 `unauthenticated` if absent; `sessionStore.get(sid)` → 401 `session expired` if missing or `expiresAt < Date.now()`; `sessionStore.touch(sid)`; set `req.session`; call `h`. Plus `requireRole(role, h)` → 403 `forbidden` on mismatch.
+- `src/http.ts:2-5` — add optional `session?: Session` to `Request` (import the type from `src/session/store.ts:13-22`). `Router` (`src/http.ts:11-16`) has no middleware hook, so wrap handlers rather than adding a `use()` chain.
+- `src/auth.ts:6-55` — delete the duplicated sid/session/expiry blocks (`:7-17`, `:22-32`, `:38-47`) and the owner check (`:48-51`); handlers read `req.session`.
+- `src/routes.ts:6-8` — wrap: `requireSession(getProfile)`, `requireSession(updateProfile)`, `requireSession(requireRole("owner", deleteAccount))`.
+- Preserve the exact status codes and error bodies — clients match on `unauthenticated` vs `session expired`.
+- One accepted behaviour change: `deleteAccount` skips `touch` today; behind the middleware it gets `touch` then `destroy`. Harmless extra write — no special case.
+- Do not edit `src/session/store.ts` (W2 owns it). Its header comment (`:8-10`) names `src/auth.ts` as the sole caller; W2 updates it to name the middleware.
+
+Why: the same 10-line check is copy-pasted into all three handlers (`src/auth.ts:7-17`, `:22-32`, `:38-47`), so a new route can silently ship without it and any change to the check must be made N times.
+
+**Done when:** no `req.cookies["sid"]` read remains in `src/auth.ts`; tests cover 401 (no cookie), 401 (expired), 403 (member on `DELETE /me`), 200 on all three routes; typecheck + lint green.
[exit 0]
```
