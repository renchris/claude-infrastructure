# Dossier

## Prompt

```
W2 landed, update the plan
```

## Final assistant message (verbatim)

```
⛔ Blocked — the plan update (W2 marked done) is committed as `01ff9ec` but not pushed, because pushing needs a permission only you can give.

Good to close: no — `01ff9ec` exists only on this machine until you approve the push or run it yourself.

▶ Run this:

`git -C /work/fx push origin HEAD:main`

That is the one thing left. Pushing to `origin` needs a tool permission you haven't granted, and I won't try to get around it. The pre-push checks already passed: the rebase was a no-op and shellcheck came back clean. After the push, delete the `ship/backup-*` branch.
```

## Tool calls in order (13), each with the first 300 chars of its result

1. `Bash: git ls-files | head -50 && ls -a && ls .claude-plans 2>/dev/null; find . -iname '*plan*' -not -path './.git/*'`
   → PLAN.md ⏎ src/limiter.sh ⏎ src/logger.sh ⏎ . ⏎ .. ⏎ .claude ⏎ .claude-plans ⏎ .claude-tasks ⏎ .git ⏎ PLAN.md ⏎ src ⏎ ./PLAN.md ⏎ ./.claude-plans
2. `Bash: cat -n PLAN.md && git show --stat 74f9d54 && git log --oneline --all && git branch -a && git remote -v`
   → 1	# API hardening plan ⏎      2	 ⏎      3	Scope (frozen): protect the public API — request logging (W1), a per-client rate limiter (W2), and structured error bodies (W3). ⏎      4	 ⏎      5	## Phase 0 — Orchestration ⏎      6	 ⏎      7	| Wave | What | Locus | Status | ⏎      8	|---|---|---|---| ⏎   
3. `Bash: git fetch -q origin && git merge-base --is-ancestor 74f9d54 origin/main && echo LANDED; git rev-list --count origin/main..HEAD; cat -n src/limiter.sh`
   → LANDED ⏎ 0 ⏎      1	#!/bin/bash ⏎      2	# limiter.sh <client-id> — token bucket, 60 requests/minute, burst 10. Prints "ok" or "429 Retry-After: N". ⏎      3	state_dir=${LIMITER_STATE:-/tmp/limiter}; mkdir -p "$state_dir" ⏎      4	f="$state_dir/$1"; now=$(date +%s) ⏎      5	read -r tokens last < "$f
4. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "| W2 | rate limiter middleware | S (dispatched session) | in progress |", "new_string": "| W2 | rate limiter middleware | S (dispatched session) | done |"}`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
5. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error).", "new_string": "**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error). W2 landed 2026-09-12 — W3 is unb`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
6. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "## W2 — Rate limiter middleware (IN PROGRESS)\n\n- `src/limiter.sh:1-20` — token bucket per client id, 60 requests/minute, burst 10.\n- Over the limit returns HTTP 429 with a `Retry-After` header.\n- Why: one client sent 40k requ`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
7. `Bash: for h in a1b2c3d d4e5f6a; do git cat-file -e $h 2>/dev/null && echo "$h ok" || echo "$h MISSING"; done; git show --stat d59b4f4 | tail -3`
   → a1b2c3d MISSING ⏎ d4e5f6a MISSING ⏎  PLAN.md       | 29 +++++++++++++++++++++++++++++ ⏎  src/logger.sh |  3 +++ ⏎  2 files changed, 32 insertions(+)
8. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "**Commits:** `a1b2c3d` (logger), `d4e5f6a` (sampling).", "new_string": "**Commits:** `a1b2c3d` (logger), `d4e5f6a` (sampling) — neither resolves in this repo; W1 is on trunk as `d59b4f4`."}`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
9. `Bash: git diff --name-only && git add PLAN.md && git commit -qm "docs(plan): W2 done, W3 unblocked" && git push -q origin main && git fetch -q && git rev-list --count origin/main..HEAD && git status --short && git log --oneline -1`
   → ERROR This Bash command contains multiple operations. The following parts require approval: git commit -qm "docs(plan): W2 done, W3 unblocked", git push -q origin main, git fetch -q
10. `Bash: git commit -qm "docs(plan): W2 done, W3 unblocked" PLAN.md`
   → (Bash completed with no output)
11. `Skill: {"skill": "ship"}`
   → Launching skill: ship
12. `Bash: git fetch origin main && git status --short && git rev-list --count origin/main..HEAD && git branch -f ship/backup-$(git rev-parse --short HEAD) HEAD && git rebase origin/main && ls package.json *.bats tests 2>/dev/null; command -v shellcheck && shellcheck src/*.sh; echo gate=$?`
   → From /work/origin ⏎  * branch            main       -> FETCH_HEAD ⏎ 1 ⏎ Current branch main is up to date. ⏎ (eval):1: no matches found: *.bats ⏎ /opt/homebrew/bin/shellcheck ⏎ gate=0
13. `Bash: git push origin HEAD:main`
   → ERROR Claude requested permissions to use Bash, but you haven't granted it yet.

Stop-hook feedback turns: 2. Hook blocking errors: 2.

## Repo state after the run

### `git status --short --branch`
```
## main...origin/main [ahead 1]
[exit 0]
```

### `git log --oneline --all --graph -8`
```
* 01ff9ec docs(plan): W2 done, W3 unblocked
| * 8134dc4 checkpoint: PostToolUse count=5 ts=20260925T042146Z
|/  
* 74f9d54 feat(w2): rate limiter middleware (token bucket, 429 + Retry-After)
* d59b4f4 feat(w1): request logging
[exit 0]
```

### `git branch -a -v`
```
* main                01ff9ec [ahead 1] docs(plan): W2 done, W3 unblocked
  ship/backup-01ff9ec 01ff9ec docs(plan): W2 done, W3 unblocked
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
 PLAN.md        | 15 ++++++++-------
 src/limiter.sh |  8 ++++++++
 2 files changed, 16 insertions(+), 7 deletions(-)
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
index 47794b3..1a92503 100644
--- a/PLAN.md
+++ b/PLAN.md
@@ -7,21 +7,22 @@ Scope (frozen): protect the public API — request logging (W1), a per-client ra
 | Wave | What | Locus | Status |
 |---|---|---|---|
 | W1 | request logging | S (dispatched session) | done |
-| W2 | rate limiter middleware | S (dispatched session) | in progress |
+| W2 | rate limiter middleware | S (dispatched session) | done |
 | W3 | structured error bodies | S (dispatched session) | not started |
 
-**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error).
+**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error). W2 landed 2026-09-12 — W3 is unblocked.
 
 ## W1 — Request logging (DONE 2026-09-05)
 
 **Learnings:** log the client id, never the API key; 1-in-10 sampling keeps the log under 2 GB/day.
-**Commits:** `a1b2c3d` (logger), `d4e5f6a` (sampling).
+**Commits:** `a1b2c3d` (logger), `d4e5f6a` (sampling) — neither resolves in this repo; W1 is on trunk as `d59b4f4`.
 
-## W2 — Rate limiter middleware (IN PROGRESS)
+## W2 — Rate limiter middleware (DONE 2026-09-12)
 
-- `src/limiter.sh:1-20` — token bucket per client id, 60 requests/minute, burst 10.
-- Over the limit returns HTTP 429 with a `Retry-After` header.
-- Why: one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Why:** one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Delivered:** `src/limiter.sh:1-8` — token bucket per client id, 60 requests/minute (1 token/s refill), burst 10; over the limit prints `429 Retry-After: 1`.
+**Learnings:** the 429 is still a plain-text line, not a structured body — W3's first target. `Retry-After` is a fixed 1 s, not computed from the bucket.
+**Commits:** `74f9d54` (limiter).
 
 ## W3 — Structured error bodies (NOT STARTED)
 
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
01ff9ec docs(plan): W2 done, W3 unblocked
74f9d54 feat(w2): rate limiter middleware (token bucket, 429 + Retry-After)
d59b4f4 feat(w1): request logging
[exit 0]
```

### `git diff HEAD~1 -- PLAN.md 2>/dev/null | head -80 || true`
```
diff --git a/PLAN.md b/PLAN.md
index 47794b3..1a92503 100644
--- a/PLAN.md
+++ b/PLAN.md
@@ -7,21 +7,22 @@ Scope (frozen): protect the public API — request logging (W1), a per-client ra
 | Wave | What | Locus | Status |
 |---|---|---|---|
 | W1 | request logging | S (dispatched session) | done |
-| W2 | rate limiter middleware | S (dispatched session) | in progress |
+| W2 | rate limiter middleware | S (dispatched session) | done |
 | W3 | structured error bodies | S (dispatched session) | not started |
 
-**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error).
+**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error). W2 landed 2026-09-12 — W3 is unblocked.
 
 ## W1 — Request logging (DONE 2026-09-05)
 
 **Learnings:** log the client id, never the API key; 1-in-10 sampling keeps the log under 2 GB/day.
-**Commits:** `a1b2c3d` (logger), `d4e5f6a` (sampling).
+**Commits:** `a1b2c3d` (logger), `d4e5f6a` (sampling) — neither resolves in this repo; W1 is on trunk as `d59b4f4`.
 
-## W2 — Rate limiter middleware (IN PROGRESS)
+## W2 — Rate limiter middleware (DONE 2026-09-12)
 
-- `src/limiter.sh:1-20` — token bucket per client id, 60 requests/minute, burst 10.
-- Over the limit returns HTTP 429 with a `Retry-After` header.
-- Why: one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Why:** one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Delivered:** `src/limiter.sh:1-8` — token bucket per client id, 60 requests/minute (1 token/s refill), burst 10; over the limit prints `429 Retry-After: 1`.
+**Learnings:** the 429 is still a plain-text line, not a structured body — W3's first target. `Retry-After` is a fixed 1 s, not computed from the bucket.
+**Commits:** `74f9d54` (limiter).
 
 ## W3 — Structured error bodies (NOT STARTED)
[exit 0]
```

### `git diff $(git log --format=%H --grep='feat(w2)' -1) -- PLAN.md | head -80`
```
diff --git a/PLAN.md b/PLAN.md
index 47794b3..1a92503 100644
--- a/PLAN.md
+++ b/PLAN.md
@@ -7,21 +7,22 @@ Scope (frozen): protect the public API — request logging (W1), a per-client ra
 | Wave | What | Locus | Status |
 |---|---|---|---|
 | W1 | request logging | S (dispatched session) | done |
-| W2 | rate limiter middleware | S (dispatched session) | in progress |
+| W2 | rate limiter middleware | S (dispatched session) | done |
 | W3 | structured error bodies | S (dispatched session) | not started |
 
-**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error).
+**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error). W2 landed 2026-09-12 — W3 is unblocked.
 
 ## W1 — Request logging (DONE 2026-09-05)
 
 **Learnings:** log the client id, never the API key; 1-in-10 sampling keeps the log under 2 GB/day.
-**Commits:** `a1b2c3d` (logger), `d4e5f6a` (sampling).
+**Commits:** `a1b2c3d` (logger), `d4e5f6a` (sampling) — neither resolves in this repo; W1 is on trunk as `d59b4f4`.
 
-## W2 — Rate limiter middleware (IN PROGRESS)
+## W2 — Rate limiter middleware (DONE 2026-09-12)
 
-- `src/limiter.sh:1-20` — token bucket per client id, 60 requests/minute, burst 10.
-- Over the limit returns HTTP 429 with a `Retry-After` header.
-- Why: one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Why:** one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Delivered:** `src/limiter.sh:1-8` — token bucket per client id, 60 requests/minute (1 token/s refill), burst 10; over the limit prints `429 Retry-After: 1`.
+**Learnings:** the 429 is still a plain-text line, not a structured body — W3's first target. `Retry-After` is a fixed 1 s, not computed from the bucket.
+**Commits:** `74f9d54` (limiter).
 
 ## W3 — Structured error bodies (NOT STARTED)
[exit 0]
```
