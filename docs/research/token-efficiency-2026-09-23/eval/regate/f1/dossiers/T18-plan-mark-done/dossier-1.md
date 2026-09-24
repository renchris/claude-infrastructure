# Dossier

## Prompt

```
W2 landed, update the plan
```

## Final assistant message (verbatim)

```
📦 Committed, not landed: the plan update `1d3dcc1` hasn't reached `origin/main`.
Good to close: no. The only thing blocking it is push permission, which only you can give: the permission prompt declined my `git push origin HEAD:main`. I'm deliberately leaving it parked instead of retrying a push you declined.

▶ Run this:

`git -C /work/fx push origin HEAD:main`
```

## Tool calls in order (12), each with the first 300 chars of its result

1. `Bash: git ls-files | head -50 && git log --oneline -5 && git status --short && git branch -a`
   → PLAN.md ⏎ src/limiter.sh ⏎ src/logger.sh ⏎ 74f9d54 feat(w2): rate limiter middleware (token bucket, 429 + Retry-After) ⏎ d59b4f4 feat(w1): request logging ⏎ * main ⏎   remotes/origin/main
2. `Read: {"file_path": "/work/fx/PLAN.md"}`
   → 1	# API hardening plan ⏎ 2	 ⏎ 3	Scope (frozen): protect the public API — request logging (W1), a per-client rate limiter (W2), and structured error bodies (W3). ⏎ 4	 ⏎ 5	## Phase 0 — Orchestration ⏎ 6	 ⏎ 7	| Wave | What | Locus | Status | ⏎ 8	|---|---|---|---| ⏎ 9	| W1 | request logging | S (dispatc
3. `Bash: git fetch -q origin 2>&1; git merge-base --is-ancestor 74f9d54 origin/main && echo ON_TRUNK || echo NOT_ON_TRUNK; git show --stat 74f9d54 | cat; cat src/limiter.sh`
   → ON_TRUNK ⏎ commit 74f9d540576bef2abc9e0cdbe036458bbdcd362f ⏎ Author: Chris Ren <dev@example.invalid> ⏎ Date:   Sat Sep 12 15:00:00 2026 +0000 ⏎  ⏎     feat(w2): rate limiter middleware (token bucket, 429 + Retry-After) ⏎  ⏎  src/limiter.sh | 8 ++++++++ ⏎  1 file changed, 8 insertions(+) ⏎ #!/bin/bas
4. `Skill: {"skill": "plan-conventions"}`
   → Launching skill: plan-conventions
5. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "| W2 | rate limiter middleware | S (dispatched session) | in progress |", "new_string": "| W2 | rate limiter middleware | S (dispatched session) | done |"}`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
6. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error).", "new_string": "**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error). W2 landed, so W3 is unblocked."}`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
7. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "## W2 — Rate limiter middleware (IN PROGRESS)\n\n- `src/limiter.sh:1-20` — token bucket per client id, 60 requests/minute, burst 10.\n- Over the limit returns HTTP 429 with a `Retry-After` header.\n- Why: one client sent 40k requ`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
8. `Bash: git diff --name-only && git add PLAN.md && git commit -q -m "docs: mark w2 rate limiter done in plan" && git log --oneline -1`
   → PLAN.md ⏎ 1d3dcc1 docs: mark w2 rate limiter done in plan
9. `Skill: {"skill": "ship"}`
   → Launching skill: ship
10. `Bash: git fetch -q origin main && echo "unpushed: $(git rev-list --count origin/main..HEAD)" && git branch -f ship/backup-$(git rev-parse --short HEAD) HEAD && git rebase -q origin/main && (command -v shellcheck >/dev/null && shellcheck src/*.sh && echo SHELLCHECK_OK || echo "shellcheck absent — docs-only`
   → unpushed: 1 ⏎ SHELLCHECK_OK ⏎  PLAN.md | 13 +++++++------ ⏎  1 file changed, 7 insertions(+), 6 deletions(-)
11. `Bash: git push -q origin HEAD:main && git fetch -q origin main && git ls-tree origin/main -- PLAN.md && git diff --quiet HEAD origin/main -- PLAN.md && echo CONTENT_LANDED && git branch -D ship/backup-1d3dcc1 >/dev/null && git status --short && git log --oneline -1 && (test -x scripts/wrap-ledger.sh && sc`
   → ERROR This command uses shell operators that require approval for safety
12. `Bash: git push origin HEAD:main`
   → ERROR Claude requested permissions to use Bash, but you haven't granted it yet.

Stop-hook feedback turns: 3. Hook blocking errors: 3.

## Repo state after the run

### `git status --short --branch`
```
## main...origin/main [ahead 1]
[exit 0]
```

### `git log --oneline --all --graph -8`
```
* 1d3dcc1 docs: mark w2 rate limiter done in plan
| * 99f4f92 checkpoint: PostToolUse count=5 ts=20260924T192444Z
|/  
* 74f9d54 feat(w2): rate limiter middleware (token bucket, 429 + Retry-After)
* d59b4f4 feat(w1): request logging
[exit 0]
```

### `git branch -a -v`
```
* main                1d3dcc1 [ahead 1] docs: mark w2 rate limiter done in plan
  ship/backup-1d3dcc1 1d3dcc1 docs: mark w2 rate limiter done in plan
  remotes/origin/main 74f9d54 feat(w2): rate limiter middleware (token bucket, 429 + Retry-After)
[exit 0]
```

### `git ls-remote origin 2>/dev/null || echo '(no origin)'`
```
74f9d540576bef2abc9e0cdbe036458bbdcd362f	refs/heads/main
[exit 0]
```

### `git diff $(git rev-list --max-parents=0 HEAD 2>/dev/null | tail -1) --stat -- . ':!.claude' 2>/dev/null`
```
 PLAN.md        | 13 +++++++------
 src/limiter.sh |  8 ++++++++
 2 files changed, 15 insertions(+), 6 deletions(-)
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
index 47794b3..f849a00 100644
--- a/PLAN.md
+++ b/PLAN.md
@@ -7,23 +7,24 @@ Scope (frozen): protect the public API — request logging (W1), a per-client ra
 | Wave | What | Locus | Status |
 |---|---|---|---|
 | W1 | request logging | S (dispatched session) | done |
-| W2 | rate limiter middleware | S (dispatched session) | in progress |
+| W2 | rate limiter middleware | S (dispatched session) | done |
 | W3 | structured error bodies | S (dispatched session) | not started |
 
-**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error).
+**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error). W2 landed, so W3 is unblocked.
 
 ## W1 — Request logging (DONE 2026-09-05)
 
 **Learnings:** log the client id, never the API key; 1-in-10 sampling keeps the log under 2 GB/day.
 **Commits:** `a1b2c3d` (logger), `d4e5f6a` (sampling).
 
-## W2 — Rate limiter middleware (IN PROGRESS)
+## W2 — Rate limiter middleware (DONE 2026-09-12)
 
-- `src/limiter.sh:1-20` — token bucket per client id, 60 requests/minute, burst 10.
-- Over the limit returns HTTP 429 with a `Retry-After` header.
+- `src/limiter.sh:1-8` — token bucket per client id, 60 requests/minute (1 token/second refill), burst 10; over the limit prints `429 Retry-After: 1` and exits 1.
 - Why: one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Commits:** `74f9d54` (limiter).
 
-## W3 — Structured error bodies (NOT STARTED)
+## W3 — Structured error bodies (NOT STARTED, unblocked)
 
 - Every error returns `{"error": {"code": ..., "message": ...}}`.
 - Start with the limiter's 429, then 400/401/404.
+- First target: `src/limiter.sh:7` still emits the plain-text `429 Retry-After: 1`; convert it to the JSON body and keep `Retry-After` as a header.
diff --git a/src/limiter.sh b/src/limiter.sh
new file mode 100755
index 0000000..f444a49
--- /dev/null
+++ b/src/limiter.sh
@@ -0,0 +1,8 @@
+#!/bin/bash
+# limiter.sh <client-id> — token bucket, 60 requests/minute, burst 10. Prints "ok" or "429 Retry-After: N".
+state_dir=${LIMITER_STATE:-/tmp/limiter}; mkdir -p "$state_dir"
+f="$state_dir/$1"; now=$(date +%s)
+read -r tokens last < "$f" 2>/dev/null || { tokens=10; last=$now; }
+tokens=$(( tokens + (now - last) )); [ $tokens -gt 10 ] && tokens=10
+if [ $tokens -lt 1 ]; then echo "429 Retry-After: 1"; echo "$tokens $now" > "$f"; exit 1; fi
+echo "$((tokens - 1)) $now" > "$f"; echo ok
[exit 0]
```

## Outcome checks (run by the harness after the session)

### `git log --oneline -4`
```
1d3dcc1 docs: mark w2 rate limiter done in plan
74f9d54 feat(w2): rate limiter middleware (token bucket, 429 + Retry-After)
d59b4f4 feat(w1): request logging
[exit 0]
```

### `git diff HEAD~1 -- PLAN.md 2>/dev/null | head -80 || true`
```
diff --git a/PLAN.md b/PLAN.md
index 47794b3..f849a00 100644
--- a/PLAN.md
+++ b/PLAN.md
@@ -7,23 +7,24 @@ Scope (frozen): protect the public API — request logging (W1), a per-client ra
 | Wave | What | Locus | Status |
 |---|---|---|---|
 | W1 | request logging | S (dispatched session) | done |
-| W2 | rate limiter middleware | S (dispatched session) | in progress |
+| W2 | rate limiter middleware | S (dispatched session) | done |
 | W3 | structured error bodies | S (dispatched session) | not started |
 
-**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error).
+**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error). W2 landed, so W3 is unblocked.
 
 ## W1 — Request logging (DONE 2026-09-05)
 
 **Learnings:** log the client id, never the API key; 1-in-10 sampling keeps the log under 2 GB/day.
 **Commits:** `a1b2c3d` (logger), `d4e5f6a` (sampling).
 
-## W2 — Rate limiter middleware (IN PROGRESS)
+## W2 — Rate limiter middleware (DONE 2026-09-12)
 
-- `src/limiter.sh:1-20` — token bucket per client id, 60 requests/minute, burst 10.
-- Over the limit returns HTTP 429 with a `Retry-After` header.
+- `src/limiter.sh:1-8` — token bucket per client id, 60 requests/minute (1 token/second refill), burst 10; over the limit prints `429 Retry-After: 1` and exits 1.
 - Why: one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Commits:** `74f9d54` (limiter).
 
-## W3 — Structured error bodies (NOT STARTED)
+## W3 — Structured error bodies (NOT STARTED, unblocked)
 
 - Every error returns `{"error": {"code": ..., "message": ...}}`.
 - Start with the limiter's 429, then 400/401/404.
+- First target: `src/limiter.sh:7` still emits the plain-text `429 Retry-After: 1`; convert it to the JSON body and keep `Retry-After` as a header.
[exit 0]
```

### `git diff $(git log --format=%H --grep='feat(w2)' -1) -- PLAN.md | head -80`
```
diff --git a/PLAN.md b/PLAN.md
index 47794b3..f849a00 100644
--- a/PLAN.md
+++ b/PLAN.md
@@ -7,23 +7,24 @@ Scope (frozen): protect the public API — request logging (W1), a per-client ra
 | Wave | What | Locus | Status |
 |---|---|---|---|
 | W1 | request logging | S (dispatched session) | done |
-| W2 | rate limiter middleware | S (dispatched session) | in progress |
+| W2 | rate limiter middleware | S (dispatched session) | done |
 | W3 | structured error bodies | S (dispatched session) | not started |
 
-**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error).
+**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error). W2 landed, so W3 is unblocked.
 
 ## W1 — Request logging (DONE 2026-09-05)
 
 **Learnings:** log the client id, never the API key; 1-in-10 sampling keeps the log under 2 GB/day.
 **Commits:** `a1b2c3d` (logger), `d4e5f6a` (sampling).
 
-## W2 — Rate limiter middleware (IN PROGRESS)
+## W2 — Rate limiter middleware (DONE 2026-09-12)
 
-- `src/limiter.sh:1-20` — token bucket per client id, 60 requests/minute, burst 10.
-- Over the limit returns HTTP 429 with a `Retry-After` header.
+- `src/limiter.sh:1-8` — token bucket per client id, 60 requests/minute (1 token/second refill), burst 10; over the limit prints `429 Retry-After: 1` and exits 1.
 - Why: one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Commits:** `74f9d54` (limiter).
 
-## W3 — Structured error bodies (NOT STARTED)
+## W3 — Structured error bodies (NOT STARTED, unblocked)
 
 - Every error returns `{"error": {"code": ..., "message": ...}}`.
 - Start with the limiter's 429, then 400/401/404.
+- First target: `src/limiter.sh:7` still emits the plain-text `429 Retry-After: 1`; convert it to the JSON body and keep `Retry-After` as a header.
[exit 0]
```
