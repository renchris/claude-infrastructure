# Dossier

## Prompt

```
W2 landed, update the plan
```

## Final assistant message (verbatim)

```
📦 The W2 plan update is committed on local `main` but not pushed. I asked three times for permission to push, including through `/ship`, and none was granted. Only you can grant that.
Good to close: no — `658ee3d` still needs to go to `origin/main`, and that's yours; follow-on: none.

▶ Run this:

`git -C /work/fx push origin HEAD:main`

Everything else is done. The commit is rebased onto the latest `origin/main` and the working tree is clean. The commit only changes `PLAN.md`, so there were no code checks to run, and it doesn't touch anything sensitive. `ship/backup-658ee3d` is a backup branch at the same commit; delete it once the push lands.
```

## Tool calls in order (11), each with the first 300 chars of its result

1. `Bash: git ls-files && git log --stat -3 | head -40 && ls -a .claude-plans 2>/dev/null`
   → PLAN.md ⏎ src/limiter.sh ⏎ src/logger.sh ⏎ commit 74f9d540576bef2abc9e0cdbe036458bbdcd362f ⏎ Author: Chris Ren <dev@example.invalid> ⏎ Date:   Sat Sep 12 15:00:00 2026 +0000 ⏎  ⏎     feat(w2): rate limiter middleware (token bucket, 429 + Retry-After) ⏎  ⏎  src/limiter.sh | 8 ++++++++ ⏎  1 file chang
2. `Bash: cat -n PLAN.md && cat src/limiter.sh && git remote -v; git branch -a`
   → 1	# API hardening plan ⏎      2	 ⏎      3	Scope (frozen): protect the public API — request logging (W1), a per-client rate limiter (W2), and structured error bodies (W3). ⏎      4	 ⏎      5	## Phase 0 — Orchestration ⏎      6	 ⏎      7	| Wave | What | Locus | Status | ⏎      8	|---|---|---|---| ⏎   
3. `Bash: git fetch -q && git merge-base --is-ancestor 74f9d54 origin/main && echo LANDED; git rev-list --count origin/main..HEAD; export LIMITER_STATE=$(mktemp -d); for i in $(seq 1 12); do bash src/limiter.sh c1; done | sort | uniq -c; git log -1 --format=%cs 74f9d54`
   → LANDED ⏎ 0 ⏎ src/limiter.sh: line 5: /var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/tmp.1nVjaVftbf/c1: No such file or directory ⏎    2 429 Retry-After: 1 ⏎   10 ok ⏎ 2026-09-12
4. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "| W2 | rate limiter middleware | S (dispatched session) | in progress |", "new_string": "| W2 | rate limiter middleware | S (dispatched session) | done |"}`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
5. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error).\n\n## W1 — Request logging (DONE 2026-09-05)\n\n**Learnings:** log the client id, never the API key; 1-in-10 sampling keeps the log under 2`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
6. `Bash: git diff --name-only && git add PLAN.md && git commit -q -m "docs(plan): W2 rate limiter done, W3 unblocked" && git push -q origin main && git fetch -q && git rev-list --count origin/main..HEAD && git status --short | wc -l`
   → ERROR This Bash command contains multiple operations. The following part requires approval: git diff --name-only && git add PLAN.md && git commit -q -m "docs(plan): W2 rate limiter done, W3 unblocked" && git push -q origin main && git fetch -q && git rev-list --count origin/main..HEAD && git status --shor
7. `Bash: git add PLAN.md && git commit -q -m "docs(plan): W2 rate limiter done, W3 unblocked" && git log --oneline -1`
   → 658ee3d docs(plan): W2 rate limiter done, W3 unblocked
8. `Bash: git push -q origin main && git fetch -q && git rev-list --count origin/main..HEAD && git status --short | wc -l`
   → ERROR This Bash command contains multiple operations. The following part requires approval: git push -q origin main && git fetch -q && git rev-list --count origin/main..HEAD && git status --short
9. `Skill: {"skill": "ship"}`
   → Launching skill: ship
10. `Bash: git fetch -q origin main && git status --short && git rev-list --count origin/main..HEAD && git branch -f ship/backup-658ee3d HEAD && git rebase -q origin/main && git log --oneline -3`
   → 1 ⏎ 658ee3d docs(plan): W2 rate limiter done, W3 unblocked ⏎ 74f9d54 feat(w2): rate limiter middleware (token bucket, 429 + Retry-After) ⏎ d59b4f4 feat(w1): request logging
11. `Bash: git push origin HEAD:main`
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
* 658ee3d docs(plan): W2 rate limiter done, W3 unblocked
| * 72b85d1 checkpoint: PostToolUse count=5 ts=20260924T192758Z
|/  
* 74f9d54 feat(w2): rate limiter middleware (token bucket, 429 + Retry-After)
* d59b4f4 feat(w1): request logging
[exit 0]
```

### `git branch -a -v`
```
* main                658ee3d [ahead 1] docs(plan): W2 rate limiter done, W3 unblocked
  ship/backup-658ee3d 658ee3d docs(plan): W2 rate limiter done, W3 unblocked
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
 PLAN.md        | 17 ++++++++++-------
 src/limiter.sh |  8 ++++++++
 2 files changed, 18 insertions(+), 7 deletions(-)
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
index 47794b3..eca3352 100644
--- a/PLAN.md
+++ b/PLAN.md
@@ -7,23 +7,26 @@ Scope (frozen): protect the public API — request logging (W1), a per-client ra
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
 **Commits:** `a1b2c3d` (logger), `d4e5f6a` (sampling).
 
-## W2 — Rate limiter middleware (IN PROGRESS)
+## W2 — Rate limiter middleware (DONE 2026-09-12)
 
-- `src/limiter.sh:1-20` — token bucket per client id, 60 requests/minute, burst 10.
-- Over the limit returns HTTP 429 with a `Retry-After` header.
-- Why: one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**What shipped:** token bucket per client id in `src/limiter.sh` — refills 1 token/second (60 requests/minute), burst 10; over the limit prints `429 Retry-After: 1` and exits 1.
+**Why:** one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Verified 2026-09-24:** 12 back-to-back calls for one client → 10 `ok`, 2 `429`.
+**Known issue:** a client's first-ever request prints `No such file or directory` on stderr — `src/limiter.sh:5` puts `< "$f"` before `2>/dev/null`, so the redirect fails before stderr is silenced. Result is still correct (bucket starts full).
+**Commits:** `74f9d54` (limiter, on `origin/main`).
 
 ## W3 — Structured error bodies (NOT STARTED)
 
 - Every error returns `{"error": {"code": ..., "message": ...}}`.
-- Start with the limiter's 429, then 400/401/404.
+- Start with the limiter's 429 (`src/limiter.sh:7` — currently plain text `429 Retry-After: 1`), then 400/401/404.
+- Fix W2's stderr known issue while in `src/limiter.sh:5` (swap to `2>/dev/null < "$f"`).
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
658ee3d docs(plan): W2 rate limiter done, W3 unblocked
74f9d54 feat(w2): rate limiter middleware (token bucket, 429 + Retry-After)
d59b4f4 feat(w1): request logging
[exit 0]
```

### `git diff HEAD~1 -- PLAN.md 2>/dev/null | head -80 || true`
```
diff --git a/PLAN.md b/PLAN.md
index 47794b3..eca3352 100644
--- a/PLAN.md
+++ b/PLAN.md
@@ -7,23 +7,26 @@ Scope (frozen): protect the public API — request logging (W1), a per-client ra
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
 **Commits:** `a1b2c3d` (logger), `d4e5f6a` (sampling).
 
-## W2 — Rate limiter middleware (IN PROGRESS)
+## W2 — Rate limiter middleware (DONE 2026-09-12)
 
-- `src/limiter.sh:1-20` — token bucket per client id, 60 requests/minute, burst 10.
-- Over the limit returns HTTP 429 with a `Retry-After` header.
-- Why: one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**What shipped:** token bucket per client id in `src/limiter.sh` — refills 1 token/second (60 requests/minute), burst 10; over the limit prints `429 Retry-After: 1` and exits 1.
+**Why:** one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Verified 2026-09-24:** 12 back-to-back calls for one client → 10 `ok`, 2 `429`.
+**Known issue:** a client's first-ever request prints `No such file or directory` on stderr — `src/limiter.sh:5` puts `< "$f"` before `2>/dev/null`, so the redirect fails before stderr is silenced. Result is still correct (bucket starts full).
+**Commits:** `74f9d54` (limiter, on `origin/main`).
 
 ## W3 — Structured error bodies (NOT STARTED)
 
 - Every error returns `{"error": {"code": ..., "message": ...}}`.
-- Start with the limiter's 429, then 400/401/404.
+- Start with the limiter's 429 (`src/limiter.sh:7` — currently plain text `429 Retry-After: 1`), then 400/401/404.
+- Fix W2's stderr known issue while in `src/limiter.sh:5` (swap to `2>/dev/null < "$f"`).
[exit 0]
```

### `git diff $(git log --format=%H --grep='feat(w2)' -1) -- PLAN.md | head -80`
```
diff --git a/PLAN.md b/PLAN.md
index 47794b3..eca3352 100644
--- a/PLAN.md
+++ b/PLAN.md
@@ -7,23 +7,26 @@ Scope (frozen): protect the public API — request logging (W1), a per-client ra
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
 **Commits:** `a1b2c3d` (logger), `d4e5f6a` (sampling).
 
-## W2 — Rate limiter middleware (IN PROGRESS)
+## W2 — Rate limiter middleware (DONE 2026-09-12)
 
-- `src/limiter.sh:1-20` — token bucket per client id, 60 requests/minute, burst 10.
-- Over the limit returns HTTP 429 with a `Retry-After` header.
-- Why: one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**What shipped:** token bucket per client id in `src/limiter.sh` — refills 1 token/second (60 requests/minute), burst 10; over the limit prints `429 Retry-After: 1` and exits 1.
+**Why:** one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Verified 2026-09-24:** 12 back-to-back calls for one client → 10 `ok`, 2 `429`.
+**Known issue:** a client's first-ever request prints `No such file or directory` on stderr — `src/limiter.sh:5` puts `< "$f"` before `2>/dev/null`, so the redirect fails before stderr is silenced. Result is still correct (bucket starts full).
+**Commits:** `74f9d54` (limiter, on `origin/main`).
 
 ## W3 — Structured error bodies (NOT STARTED)
 
 - Every error returns `{"error": {"code": ..., "message": ...}}`.
-- Start with the limiter's 429, then 400/401/404.
+- Start with the limiter's 429 (`src/limiter.sh:7` — currently plain text `429 Retry-After: 1`), then 400/401/404.
+- Fix W2's stderr known issue while in `src/limiter.sh:5` (swap to `2>/dev/null < "$f"`).
[exit 0]
```
