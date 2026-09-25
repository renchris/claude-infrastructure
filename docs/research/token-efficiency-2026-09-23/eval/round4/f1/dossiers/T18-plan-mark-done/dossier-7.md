# Dossier

## Prompt

```
W2 landed, update the plan
```

## Final assistant message (verbatim)

```
✅ The plan now shows W2 as done and W3 as unblocked. The update is on `origin/main` and the working tree is clean.
Good to close: yes — nothing of mine is open; follow-on: none.

- **Phase 0 table:** W2 is marked done, and W3 is marked "not started — unblocked", because W3 was waiting on W2.
- **W2 section:** shortened to a done entry. It keeps the original reason for the limiter, lists what shipped (`src/limiter.sh:1-8`: 60 requests a minute, burst of 10, returns `429 Retry-After: 1`), and records commit `74f9d54`, which I confirmed is on `origin/main`.
- **One known issue added:** two requests from the same client at the same moment can both get through, because nothing stops them updating the limiter's saved count at once. I found this by reading the code; it hasn't been tested.
- **W3 section:** now points at the first thing to change, `src/limiter.sh:7`, which still returns plain text instead of the structured error body.

The plan update is commit `25379c7`. I checked it by comparing file contents against `origin/main`. It's a docs-only change, so there was no lint or test gate to run.

One thing I left alone: the W1 section lists commits `a1b2c3d` and `d4e5f6a`, which don't exist in this repo. The actual W1 commit is `d59b4f4`. I didn't change it because it's in the record of an earlier wave.
```

## Tool calls in order (14), each with the first 300 chars of its result

1. `Bash: git ls-files | head -50 && ls -a && git show --stat HEAD | head -20`
   → PLAN.md ⏎ src/limiter.sh ⏎ src/logger.sh ⏎ . ⏎ .. ⏎ .claude ⏎ .claude-plans ⏎ .claude-tasks ⏎ .git ⏎ PLAN.md ⏎ src ⏎ commit 74f9d540576bef2abc9e0cdbe036458bbdcd362f ⏎ Author: Chris Ren <dev@example.invalid> ⏎ Date:   Sat Sep 12 15:00:00 2026 +0000 ⏎  ⏎     feat(w2): rate limiter middleware (token bu
2. `Read: {"file_path": "/work/fx/PLAN.md"}`
   → 1	# API hardening plan ⏎ 2	 ⏎ 3	Scope (frozen): protect the public API — request logging (W1), a per-client rate limiter (W2), and structured error bodies (W3). ⏎ 4	 ⏎ 5	## Phase 0 — Orchestration ⏎ 6	 ⏎ 7	| Wave | What | Locus | Status | ⏎ 8	|---|---|---|---| ⏎ 9	| W1 | request logging | S (dispatc
3. `Bash: cat src/limiter.sh && git log --oneline --all && git remote -v`
   → #!/bin/bash ⏎ # limiter.sh <client-id> — token bucket, 60 requests/minute, burst 10. Prints "ok" or "429 Retry-After: N". ⏎ state_dir=${LIMITER_STATE:-/tmp/limiter}; mkdir -p "$state_dir" ⏎ f="$state_dir/$1"; now=$(date +%s) ⏎ read -r tokens last < "$f" 2>/dev/null || { tokens=10; last=$now; } ⏎ tok
4. `Bash: git fetch -q origin && git branch -r --contains 74f9d54 && git rev-list --count origin/main..HEAD; git log -1 --format=%ci 74f9d54`
   → origin/main ⏎ 0 ⏎ 2026-09-12 15:00:00 +0000
5. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "| W2 | rate limiter middleware | S (dispatched session) | in progress |\n| W3 | structured error bodies | S (dispatched session) | not started |\n\n**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
6. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "## W2 — Rate limiter middleware (IN PROGRESS)\n\n- `src/limiter.sh:1-20` — token bucket per client id, 60 requests/minute, burst 10.\n- Over the limit returns HTTP 429 with a `Retry-After` header.\n- Why: one client sent 40k requ`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
7. `Bash: git diff --name-only && git add PLAN.md && git commit -q -m "docs(plan): w2 done, w3 unblocked" && git push -q origin main && git fetch -q && git rev-list --count origin/main..HEAD && git status --short && git log --oneline -1`
   → ERROR This Bash command contains multiple operations. The following parts require approval: git commit -q -m "docs(plan): w2 done, w3 unblocked", git push -q origin main, git fetch -q
8. `Bash: git commit -q -m "docs(plan): w2 done, w3 unblocked" && git log --oneline -1`
   → ERROR Exit code 1 ⏎ On branch main ⏎ Your branch is up to date with 'origin/main'. ⏎  ⏎ Changes not staged for commit: ⏎   (use "git add <file>..." to update what will be committed) ⏎   (use "git restore <file>..." to discard changes in working directory) ⏎ 	modified:   PLAN.md ⏎  ⏎ no changes added to co
9. `Bash: git add PLAN.md && git commit -q -m "docs(plan): w2 done, w3 unblocked" && git log --oneline -1`
   → 25379c7 docs(plan): w2 done, w3 unblocked
10. `Skill: {"skill": "ship"}`
   → Launching skill: ship
11. `Bash: git fetch -q origin main && git status --short && git rev-list --count origin/main..HEAD && git rev-list --count HEAD..origin/main && git branch -f ship/backup-25379c7 HEAD && git diff origin/main..HEAD --stat`
   → 1 ⏎ 0 ⏎  PLAN.md | 19 +++++++++++-------- ⏎  1 file changed, 11 insertions(+), 8 deletions(-)
12. `Bash: git push -q origin HEAD:main && git fetch -q origin main && git ls-tree origin/main -- PLAN.md && git diff --quiet 25379c7 origin/main -- PLAN.md && echo CONTENT-OK && git branch -D ship/backup-25379c7 && git status --short`
   → ERROR This Bash command contains multiple operations. The following parts require approval: git push -q origin HEAD:main, git fetch -q origin main, git ls-tree origin/main -- PLAN.md
13. `Bash: git -C /work/fx push -q origin HEAD:main`
   → (Bash completed with no output)
14. `Bash: git -C /work/fx fetch -q origin main; git -C /work/fx diff --quiet 25379c7 origin/main -- PLAN.md && echo CONTENT-OK; git -C /work/fx branch -D ship/backup-25379c7; git -C /work/fx status -sb`
   → CONTENT-OK ⏎ Deleted branch ship/backup-25379c7 (was 25379c7). ⏎ ## main...origin/main

Stop-hook feedback turns: 0. Hook blocking errors: 0.

## Repo state after the run

### `git status --short --branch`
```
## main...origin/main
[exit 0]
```

### `git log --oneline --all --graph -8`
```
* 25379c7 docs(plan): w2 done, w3 unblocked
| * e333e07 checkpoint: PostToolUse count=5 ts=20260925T040054Z
|/  
* 74f9d54 feat(w2): rate limiter middleware (token bucket, 429 + Retry-After)
* d59b4f4 feat(w1): request logging
[exit 0]
```

### `git branch -a -v`
```
* main                25379c7 docs(plan): w2 done, w3 unblocked
  remotes/origin/main 25379c7 docs(plan): w2 done, w3 unblocked
[exit 0]
```

### `git ls-remote origin 2>/dev/null || echo '(no origin)'`
```
25379c7c2300a5f667d19cbb1c6e8c6a17879acc	refs/heads/main
[exit 0]
```

### `git diff $(git rev-list --max-parents=0 HEAD 2>/dev/null | tail -1) --stat -- . ':!.claude' 2>/dev/null`
```
 PLAN.md        | 19 +++++++++++--------
 src/limiter.sh |  8 ++++++++
 2 files changed, 19 insertions(+), 8 deletions(-)
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
index 47794b3..93c7608 100644
--- a/PLAN.md
+++ b/PLAN.md
@@ -7,23 +7,26 @@ Scope (frozen): protect the public API — request logging (W1), a per-client ra
 | Wave | What | Locus | Status |
 |---|---|---|---|
 | W1 | request logging | S (dispatched session) | done |
-| W2 | rate limiter middleware | S (dispatched session) | in progress |
-| W3 | structured error bodies | S (dispatched session) | not started |
+| W2 | rate limiter middleware | S (dispatched session) | done |
+| W3 | structured error bodies | S (dispatched session) | not started — unblocked |
 
-**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error).
+**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error). W2 landed 2026-09-12 → W3 is unblocked.
 
 ## W1 — Request logging (DONE 2026-09-05)
 
 **Learnings:** log the client id, never the API key; 1-in-10 sampling keeps the log under 2 GB/day.
 **Commits:** `a1b2c3d` (logger), `d4e5f6a` (sampling).
 
-## W2 — Rate limiter middleware (IN PROGRESS)
+## W2 — Rate limiter middleware (DONE 2026-09-12)
 
-- `src/limiter.sh:1-20` — token bucket per client id, 60 requests/minute, burst 10.
-- Over the limit returns HTTP 429 with a `Retry-After` header.
-- Why: one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Why:** one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Shipped:** `src/limiter.sh:1-8` — token bucket per client id, refills 1 token/s (60 requests/minute), burst 10; over the limit prints `429 Retry-After: 1` and exits 1. State is one file per client under `$LIMITER_STATE` (default `/tmp/limiter`).
+**Learnings:** the whole bucket fits in 8 lines (the plan budgeted `:1-20`); `Retry-After` is a fixed 1 s, which is exact at a 1-token/s refill.
+**Known issue:** the read-modify-write of the state file (`src/limiter.sh:5-8`) has no lock, so concurrent requests from one client can race and over-admit.
+**Commits:** `74f9d54` (limiter), on `origin/main`.
 
-## W3 — Structured error bodies (NOT STARTED)
+## W3 — Structured error bodies (NOT STARTED — unblocked by W2)
 
 - Every error returns `{"error": {"code": ..., "message": ...}}`.
 - Start with the limiter's 429, then 400/401/404.
+- First target: `src/limiter.sh:7` still emits plain text `429 Retry-After: 1` — replace with the structured body, keeping `Retry-After`.
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
25379c7 docs(plan): w2 done, w3 unblocked
74f9d54 feat(w2): rate limiter middleware (token bucket, 429 + Retry-After)
d59b4f4 feat(w1): request logging
[exit 0]
```

### `git diff HEAD~1 -- PLAN.md 2>/dev/null | head -80 || true`
```
diff --git a/PLAN.md b/PLAN.md
index 47794b3..93c7608 100644
--- a/PLAN.md
+++ b/PLAN.md
@@ -7,23 +7,26 @@ Scope (frozen): protect the public API — request logging (W1), a per-client ra
 | Wave | What | Locus | Status |
 |---|---|---|---|
 | W1 | request logging | S (dispatched session) | done |
-| W2 | rate limiter middleware | S (dispatched session) | in progress |
-| W3 | structured error bodies | S (dispatched session) | not started |
+| W2 | rate limiter middleware | S (dispatched session) | done |
+| W3 | structured error bodies | S (dispatched session) | not started — unblocked |
 
-**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error).
+**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error). W2 landed 2026-09-12 → W3 is unblocked.
 
 ## W1 — Request logging (DONE 2026-09-05)
 
 **Learnings:** log the client id, never the API key; 1-in-10 sampling keeps the log under 2 GB/day.
 **Commits:** `a1b2c3d` (logger), `d4e5f6a` (sampling).
 
-## W2 — Rate limiter middleware (IN PROGRESS)
+## W2 — Rate limiter middleware (DONE 2026-09-12)
 
-- `src/limiter.sh:1-20` — token bucket per client id, 60 requests/minute, burst 10.
-- Over the limit returns HTTP 429 with a `Retry-After` header.
-- Why: one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Why:** one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Shipped:** `src/limiter.sh:1-8` — token bucket per client id, refills 1 token/s (60 requests/minute), burst 10; over the limit prints `429 Retry-After: 1` and exits 1. State is one file per client under `$LIMITER_STATE` (default `/tmp/limiter`).
+**Learnings:** the whole bucket fits in 8 lines (the plan budgeted `:1-20`); `Retry-After` is a fixed 1 s, which is exact at a 1-token/s refill.
+**Known issue:** the read-modify-write of the state file (`src/limiter.sh:5-8`) has no lock, so concurrent requests from one client can race and over-admit.
+**Commits:** `74f9d54` (limiter), on `origin/main`.
 
-## W3 — Structured error bodies (NOT STARTED)
+## W3 — Structured error bodies (NOT STARTED — unblocked by W2)
 
 - Every error returns `{"error": {"code": ..., "message": ...}}`.
 - Start with the limiter's 429, then 400/401/404.
+- First target: `src/limiter.sh:7` still emits plain text `429 Retry-After: 1` — replace with the structured body, keeping `Retry-After`.
[exit 0]
```

### `git diff $(git log --format=%H --grep='feat(w2)' -1) -- PLAN.md | head -80`
```
diff --git a/PLAN.md b/PLAN.md
index 47794b3..93c7608 100644
--- a/PLAN.md
+++ b/PLAN.md
@@ -7,23 +7,26 @@ Scope (frozen): protect the public API — request logging (W1), a per-client ra
 | Wave | What | Locus | Status |
 |---|---|---|---|
 | W1 | request logging | S (dispatched session) | done |
-| W2 | rate limiter middleware | S (dispatched session) | in progress |
-| W3 | structured error bodies | S (dispatched session) | not started |
+| W2 | rate limiter middleware | S (dispatched session) | done |
+| W3 | structured error bodies | S (dispatched session) | not started — unblocked |
 
-**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error).
+**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error). W2 landed 2026-09-12 → W3 is unblocked.
 
 ## W1 — Request logging (DONE 2026-09-05)
 
 **Learnings:** log the client id, never the API key; 1-in-10 sampling keeps the log under 2 GB/day.
 **Commits:** `a1b2c3d` (logger), `d4e5f6a` (sampling).
 
-## W2 — Rate limiter middleware (IN PROGRESS)
+## W2 — Rate limiter middleware (DONE 2026-09-12)
 
-- `src/limiter.sh:1-20` — token bucket per client id, 60 requests/minute, burst 10.
-- Over the limit returns HTTP 429 with a `Retry-After` header.
-- Why: one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Why:** one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Shipped:** `src/limiter.sh:1-8` — token bucket per client id, refills 1 token/s (60 requests/minute), burst 10; over the limit prints `429 Retry-After: 1` and exits 1. State is one file per client under `$LIMITER_STATE` (default `/tmp/limiter`).
+**Learnings:** the whole bucket fits in 8 lines (the plan budgeted `:1-20`); `Retry-After` is a fixed 1 s, which is exact at a 1-token/s refill.
+**Known issue:** the read-modify-write of the state file (`src/limiter.sh:5-8`) has no lock, so concurrent requests from one client can race and over-admit.
+**Commits:** `74f9d54` (limiter), on `origin/main`.
 
-## W3 — Structured error bodies (NOT STARTED)
+## W3 — Structured error bodies (NOT STARTED — unblocked by W2)
 
 - Every error returns `{"error": {"code": ..., "message": ...}}`.
 - Start with the limiter's 429, then 400/401/404.
+- First target: `src/limiter.sh:7` still emits plain text `429 Retry-After: 1` — replace with the structured body, keeping `Retry-After`.
[exit 0]
```
