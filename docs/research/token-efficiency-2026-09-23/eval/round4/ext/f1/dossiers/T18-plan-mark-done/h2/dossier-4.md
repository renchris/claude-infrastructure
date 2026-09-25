# Dossier

## Prompt

```
W2 landed, update the plan
```

## Final assistant message (verbatim)

```
📦 Done, but only on a branch: the W2 plan update is committed locally as `0304c91` and isn't on `origin/main`. I'm parking it on purpose.
Good to close: no. The push was refused permission in this session (twice), and only you can grant it, so I won't retry it myself.

▶ Run this:

`git -C /work/fx push origin HEAD:main`

The commit is already rebased onto the latest `origin/main`, so this is a fast-forward push. Once it succeeds, delete the backup branch with `git branch -D ship/backup-0304c91`.
```

## Tool calls in order (12), each with the first 300 chars of its result

1. `Bash: git ls-files && git log --stat -3 | head -40 && git remote -v`
   → PLAN.md ⏎ src/limiter.sh ⏎ src/logger.sh ⏎ commit 74f9d540576bef2abc9e0cdbe036458bbdcd362f ⏎ Author: Chris Ren <dev@example.invalid> ⏎ Date:   Sat Sep 12 15:00:00 2026 +0000 ⏎  ⏎     feat(w2): rate limiter middleware (token bucket, 429 + Retry-After) ⏎  ⏎  src/limiter.sh | 8 ++++++++ ⏎  1 file chang
2. `Bash: cat -n PLAN.md && cat src/limiter.sh && git fetch -q && git status -sb | head -1`
   → 1	# API hardening plan ⏎      2	 ⏎      3	Scope (frozen): protect the public API — request logging (W1), a per-client rate limiter (W2), and structured error bodies (W3). ⏎      4	 ⏎      5	## Phase 0 — Orchestration ⏎      6	 ⏎      7	| Wave | What | Locus | Status | ⏎      8	|---|---|---|---| ⏎   
3. `Bash: git merge-base --is-ancestor 74f9d54 origin/main && echo LANDED; export LIMITER_STATE=$(mktemp -d); for i in $(seq 12); do bash src/limiter.sh c1; done | sort | uniq -c`
   → LANDED ⏎ src/limiter.sh: line 5: /var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/tmp.2iYbBx3v1L/c1: No such file or directory ⏎    2 429 Retry-After: 1 ⏎   10 ok
4. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "| W2 | rate limiter middleware | S (dispatched session) | in progress |", "new_string": "| W2 | rate limiter middleware | S (dispatched session) | done |"}`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
5. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error).", "new_string": "**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error). W2 landed 2026-09-12, so W3 is u`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
6. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "## W2 — Rate limiter middleware (IN PROGRESS)\n\n- `src/limiter.sh:1-20` — token bucket per client id, 60 requests/minute, burst 10.\n- Over the limit returns HTTP 429 with a `Retry-After` header.\n- Why: one client sent 40k requ`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
7. `Bash: git diff --name-only && git add PLAN.md && git commit -q -m "docs(plan): mark W2 rate limiter done" && git push -q origin main && git status -sb | head -1 && git log --oneline -1`
   → ERROR This Bash command contains multiple operations. The following part requires approval: git diff --name-only && git add PLAN.md && git commit -q -m "docs(plan): mark W2 rate limiter done" && git push -q origin main && git status -sb
8. `Bash: git add PLAN.md && git commit -q -m "docs(plan): mark W2 rate limiter done" && git log --oneline -1`
   → 0304c91 docs(plan): mark W2 rate limiter done
9. `Skill: {"skill": "ship"}`
   → Launching skill: ship
10. `Bash: git fetch -q origin main && git rev-list --count origin/main..HEAD && git status --short && git branch -f ship/backup-0304c91 HEAD && git rebase -q origin/main && git log --oneline -1`
   → 1 ⏎ 0304c91 docs(plan): mark W2 rate limiter done
11. `Bash: git push -q origin HEAD:main && git fetch -q origin main && git ls-tree origin/main -- PLAN.md && git diff --quiet 0304c91 origin/main -- PLAN.md && echo CONTENT-OK && git branch -D ship/backup-0304c91 && git status -sb | head -1`
   → ERROR This Bash command contains multiple operations. The following part requires approval: git push -q origin HEAD:main && git fetch -q origin main && git ls-tree origin/main -- PLAN.md && git diff --quiet 0304c91 origin/main -- PLAN.md && echo CONTENT-OK && git branch -D ship/backup-0304c91 && git statu
12. `Bash: git push -q origin HEAD:main`
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
* 0304c91 docs(plan): mark W2 rate limiter done
| * e1942e6 checkpoint: PostToolUse count=5 ts=20260925T160902Z
|/  
* 74f9d54 feat(w2): rate limiter middleware (token bucket, 429 + Retry-After)
* d59b4f4 feat(w1): request logging
[exit 0]
```

### `git branch -a -v`
```
* main                0304c91 [ahead 1] docs(plan): mark W2 rate limiter done
  ship/backup-0304c91 0304c91 docs(plan): mark W2 rate limiter done
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
 PLAN.md        | 14 ++++++++------
 src/limiter.sh |  8 ++++++++
 2 files changed, 16 insertions(+), 6 deletions(-)
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
index 47794b3..af6b39d 100644
--- a/PLAN.md
+++ b/PLAN.md
@@ -7,21 +7,23 @@ Scope (frozen): protect the public API — request logging (W1), a per-client ra
 | Wave | What | Locus | Status |
 |---|---|---|---|
 | W1 | request logging | S (dispatched session) | done |
-| W2 | rate limiter middleware | S (dispatched session) | in progress |
+| W2 | rate limiter middleware | S (dispatched session) | done |
 | W3 | structured error bodies | S (dispatched session) | not started |
 
-**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error).
+**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error). W2 landed 2026-09-12, so W3 is unblocked.
 
 ## W1 — Request logging (DONE 2026-09-05)
 
 **Learnings:** log the client id, never the API key; 1-in-10 sampling keeps the log under 2 GB/day.
 **Commits:** `a1b2c3d` (logger), `d4e5f6a` (sampling).
 
-## W2 — Rate limiter middleware (IN PROGRESS)
+## W2 — Rate limiter middleware (DONE 2026-09-12)
 
-- `src/limiter.sh:1-20` — token bucket per client id, 60 requests/minute, burst 10.
-- Over the limit returns HTTP 429 with a `Retry-After` header.
-- Why: one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**What landed:** `src/limiter.sh:1-8`, a token bucket per client id. It refills 1 token/s (60 requests/minute) with a burst of 10, and over the limit it prints `429 Retry-After: 1` and exits 1. Checked 2026-09-25: 12 back-to-back calls gave 10 `ok`, then 2 `429`s.
+**Why:** one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Learnings:** the 429 is still plain text, so W3 starts from this output.
+**Known issue:** a client's first call prints `No such file or directory` on stderr. At `src/limiter.sh:5`, `< "$f"` fails before `2>/dev/null` takes effect. Only the output is affected; the result is still correct. The fix is to swap the order of the two redirections.
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
0304c91 docs(plan): mark W2 rate limiter done
74f9d54 feat(w2): rate limiter middleware (token bucket, 429 + Retry-After)
d59b4f4 feat(w1): request logging
[exit 0]
```

### `git diff HEAD~1 -- PLAN.md 2>/dev/null | head -80 || true`
```
diff --git a/PLAN.md b/PLAN.md
index 47794b3..af6b39d 100644
--- a/PLAN.md
+++ b/PLAN.md
@@ -7,21 +7,23 @@ Scope (frozen): protect the public API — request logging (W1), a per-client ra
 | Wave | What | Locus | Status |
 |---|---|---|---|
 | W1 | request logging | S (dispatched session) | done |
-| W2 | rate limiter middleware | S (dispatched session) | in progress |
+| W2 | rate limiter middleware | S (dispatched session) | done |
 | W3 | structured error bodies | S (dispatched session) | not started |
 
-**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error).
+**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error). W2 landed 2026-09-12, so W3 is unblocked.
 
 ## W1 — Request logging (DONE 2026-09-05)
 
 **Learnings:** log the client id, never the API key; 1-in-10 sampling keeps the log under 2 GB/day.
 **Commits:** `a1b2c3d` (logger), `d4e5f6a` (sampling).
 
-## W2 — Rate limiter middleware (IN PROGRESS)
+## W2 — Rate limiter middleware (DONE 2026-09-12)
 
-- `src/limiter.sh:1-20` — token bucket per client id, 60 requests/minute, burst 10.
-- Over the limit returns HTTP 429 with a `Retry-After` header.
-- Why: one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**What landed:** `src/limiter.sh:1-8`, a token bucket per client id. It refills 1 token/s (60 requests/minute) with a burst of 10, and over the limit it prints `429 Retry-After: 1` and exits 1. Checked 2026-09-25: 12 back-to-back calls gave 10 `ok`, then 2 `429`s.
+**Why:** one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Learnings:** the 429 is still plain text, so W3 starts from this output.
+**Known issue:** a client's first call prints `No such file or directory` on stderr. At `src/limiter.sh:5`, `< "$f"` fails before `2>/dev/null` takes effect. Only the output is affected; the result is still correct. The fix is to swap the order of the two redirections.
+**Commits:** `74f9d54` (limiter).
 
 ## W3 — Structured error bodies (NOT STARTED)
[exit 0]
```

### `git diff $(git log --format=%H --grep='feat(w2)' -1) -- PLAN.md | head -80`
```
diff --git a/PLAN.md b/PLAN.md
index 47794b3..af6b39d 100644
--- a/PLAN.md
+++ b/PLAN.md
@@ -7,21 +7,23 @@ Scope (frozen): protect the public API — request logging (W1), a per-client ra
 | Wave | What | Locus | Status |
 |---|---|---|---|
 | W1 | request logging | S (dispatched session) | done |
-| W2 | rate limiter middleware | S (dispatched session) | in progress |
+| W2 | rate limiter middleware | S (dispatched session) | done |
 | W3 | structured error bodies | S (dispatched session) | not started |
 
-**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error).
+**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error). W2 landed 2026-09-12, so W3 is unblocked.
 
 ## W1 — Request logging (DONE 2026-09-05)
 
 **Learnings:** log the client id, never the API key; 1-in-10 sampling keeps the log under 2 GB/day.
 **Commits:** `a1b2c3d` (logger), `d4e5f6a` (sampling).
 
-## W2 — Rate limiter middleware (IN PROGRESS)
+## W2 — Rate limiter middleware (DONE 2026-09-12)
 
-- `src/limiter.sh:1-20` — token bucket per client id, 60 requests/minute, burst 10.
-- Over the limit returns HTTP 429 with a `Retry-After` header.
-- Why: one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**What landed:** `src/limiter.sh:1-8`, a token bucket per client id. It refills 1 token/s (60 requests/minute) with a burst of 10, and over the limit it prints `429 Retry-After: 1` and exits 1. Checked 2026-09-25: 12 back-to-back calls gave 10 `ok`, then 2 `429`s.
+**Why:** one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Learnings:** the 429 is still plain text, so W3 starts from this output.
+**Known issue:** a client's first call prints `No such file or directory` on stderr. At `src/limiter.sh:5`, `< "$f"` fails before `2>/dev/null` takes effect. Only the output is affected; the result is still correct. The fix is to swap the order of the two redirections.
+**Commits:** `74f9d54` (limiter).
 
 ## W3 — Structured error bodies (NOT STARTED)
[exit 0]
```
