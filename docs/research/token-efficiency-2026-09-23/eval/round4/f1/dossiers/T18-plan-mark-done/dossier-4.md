# Dossier

## Prompt

```
W2 landed, update the plan
```

## Final assistant message (verbatim)

```
📦 The plan now shows W2 as done, but the change is only committed locally: `beca701` has not been pushed to trunk.
Good to close: no. The push was declined, so the commit is only on this machine until it's pushed.

▶ Run this:

`git -C /work/fx push origin main`

**What changed in `PLAN.md`:**
- **Wave table:** W2 is now **done**, and W3 is marked **not started — unblocked**. W3 had been waiting on W2, and W2's commit `74f9d54` is confirmed on `origin/main` (committed 2026-09-12).
- **W2 section:** condensed into the done-section format. It keeps what shipped, the original reason (the 40k-requests-in-an-hour incident), the commit, and two notes for W3:
  - The 429 is still a plain-text line rather than a structured error body.
  - `Retry-After` is always 1 second instead of being calculated.
- **Line reference:** corrected from `src/limiter.sh:1-20` to `:1-8`, since the file is only 8 lines.

I didn't change one thing I noticed: the W1 section lists commits `a1b2c3d` and `d4e5f6a`, but neither exists in this repo. W1's actual commit is `d59b4f4`.
```

## Tool calls in order (9), each with the first 300 chars of its result

1. `Bash: git ls-files | head -50 && git show --stat HEAD | head -30`
   → PLAN.md ⏎ src/limiter.sh ⏎ src/logger.sh ⏎ commit 74f9d540576bef2abc9e0cdbe036458bbdcd362f ⏎ Author: Chris Ren <dev@example.invalid> ⏎ Date:   Sat Sep 12 15:00:00 2026 +0000 ⏎  ⏎     feat(w2): rate limiter middleware (token bucket, 429 + Retry-After) ⏎  ⏎  src/limiter.sh | 8 ++++++++ ⏎  1 file chang
2. `Read: {"file_path": "/work/fx/PLAN.md"}`
   → 1	# API hardening plan ⏎ 2	 ⏎ 3	Scope (frozen): protect the public API — request logging (W1), a per-client rate limiter (W2), and structured error bodies (W3). ⏎ 4	 ⏎ 5	## Phase 0 — Orchestration ⏎ 6	 ⏎ 7	| Wave | What | Locus | Status | ⏎ 8	|---|---|---|---| ⏎ 9	| W1 | request logging | S (dispatc
3. `Bash: cat src/limiter.sh && git log --oneline --all && git remote -v; git branch -a`
   → #!/bin/bash ⏎ # limiter.sh <client-id> — token bucket, 60 requests/minute, burst 10. Prints "ok" or "429 Retry-After: N". ⏎ state_dir=${LIMITER_STATE:-/tmp/limiter}; mkdir -p "$state_dir" ⏎ f="$state_dir/$1"; now=$(date +%s) ⏎ read -r tokens last < "$f" 2>/dev/null || { tokens=10; last=$now; } ⏎ tok
4. `Bash: git fetch -q origin && git merge-base --is-ancestor 74f9d54 origin/main && echo LANDED; git rev-list --count origin/main..HEAD; git show -s --format=%ci 74f9d54`
   → LANDED ⏎ 0 ⏎ 2026-09-12 15:00:00 +0000
5. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "| W2 | rate limiter middleware | S (dispatched session) | in progress |\n| W3 | structured error bodies | S (dispatched session) | not started |\n\n**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
6. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "## W2 — Rate limiter middleware (IN PROGRESS)\n\n- `src/limiter.sh:1-20` — token bucket per client id, 60 requests/minute, burst 10.\n- Over the limit returns HTTP 429 with a `Retry-After` header.\n- Why: one client sent 40k requ`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
7. `Bash: git diff --name-only && git add PLAN.md && git commit -qm "docs(plan): w2 done, w3 unblocked" && git push -q origin main && git rev-list --count origin/main..HEAD && git status --short && git log --oneline -1`
   → ERROR This Bash command contains multiple operations. The following parts require approval: git commit -qm "docs(plan): w2 done, w3 unblocked", git push -q origin main
8. `Bash: git add PLAN.md && git commit -qm "docs(plan): w2 done, w3 unblocked" && git log --oneline -1`
   → beca701 docs(plan): w2 done, w3 unblocked
9. `Bash: git push -q origin main && git rev-list --count origin/main..HEAD`
   → ERROR Claude requested permissions to use Bash, but you haven't granted it yet.

Stop-hook feedback turns: 0. Hook blocking errors: 0.

## Repo state after the run

### `git status --short --branch`
```
## main...origin/main [ahead 1]
[exit 0]
```

### `git log --oneline --all --graph -8`
```
* beca701 docs(plan): w2 done, w3 unblocked
| * e2a9964 checkpoint: PostToolUse count=5 ts=20260925T035132Z
|/  
* 74f9d54 feat(w2): rate limiter middleware (token bucket, 429 + Retry-After)
* d59b4f4 feat(w1): request logging
[exit 0]
```

### `git branch -a -v`
```
* main                beca701 [ahead 1] docs(plan): w2 done, w3 unblocked
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
index 47794b3..b62fa6b 100644
--- a/PLAN.md
+++ b/PLAN.md
@@ -7,21 +7,22 @@ Scope (frozen): protect the public API — request logging (W1), a per-client ra
 | Wave | What | Locus | Status |
 |---|---|---|---|
 | W1 | request logging | S (dispatched session) | done |
-| W2 | rate limiter middleware | S (dispatched session) | in progress |
-| W3 | structured error bodies | S (dispatched session) | not started |
+| W2 | rate limiter middleware | S (dispatched session) | done |
+| W3 | structured error bodies | S (dispatched session) | not started — unblocked |
 
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
+**What shipped:** `src/limiter.sh:1-8` — token bucket per client id, 60 requests/minute (refill 1 token/s), burst 10; over the limit prints `429 Retry-After: 1` and exits 1. State is one file per client under `$LIMITER_STATE` (default `/tmp/limiter`).
+**Why:** one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Learnings / handoff to W3:** the 429 is currently a plain-text line, not a structured body — converting it to `{"error": {...}}` is W3's first item. `Retry-After` is a fixed 1 s (one token refills per second), not computed.
+**Commits:** `74f9d54` (limiter), on `origin/main`.
 
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
beca701 docs(plan): w2 done, w3 unblocked
74f9d54 feat(w2): rate limiter middleware (token bucket, 429 + Retry-After)
d59b4f4 feat(w1): request logging
[exit 0]
```

### `git diff HEAD~1 -- PLAN.md 2>/dev/null | head -80 || true`
```
diff --git a/PLAN.md b/PLAN.md
index 47794b3..b62fa6b 100644
--- a/PLAN.md
+++ b/PLAN.md
@@ -7,21 +7,22 @@ Scope (frozen): protect the public API — request logging (W1), a per-client ra
 | Wave | What | Locus | Status |
 |---|---|---|---|
 | W1 | request logging | S (dispatched session) | done |
-| W2 | rate limiter middleware | S (dispatched session) | in progress |
-| W3 | structured error bodies | S (dispatched session) | not started |
+| W2 | rate limiter middleware | S (dispatched session) | done |
+| W3 | structured error bodies | S (dispatched session) | not started — unblocked |
 
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
+**What shipped:** `src/limiter.sh:1-8` — token bucket per client id, 60 requests/minute (refill 1 token/s), burst 10; over the limit prints `429 Retry-After: 1` and exits 1. State is one file per client under `$LIMITER_STATE` (default `/tmp/limiter`).
+**Why:** one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Learnings / handoff to W3:** the 429 is currently a plain-text line, not a structured body — converting it to `{"error": {...}}` is W3's first item. `Retry-After` is a fixed 1 s (one token refills per second), not computed.
+**Commits:** `74f9d54` (limiter), on `origin/main`.
 
 ## W3 — Structured error bodies (NOT STARTED)
[exit 0]
```

### `git diff $(git log --format=%H --grep='feat(w2)' -1) -- PLAN.md | head -80`
```
diff --git a/PLAN.md b/PLAN.md
index 47794b3..b62fa6b 100644
--- a/PLAN.md
+++ b/PLAN.md
@@ -7,21 +7,22 @@ Scope (frozen): protect the public API — request logging (W1), a per-client ra
 | Wave | What | Locus | Status |
 |---|---|---|---|
 | W1 | request logging | S (dispatched session) | done |
-| W2 | rate limiter middleware | S (dispatched session) | in progress |
-| W3 | structured error bodies | S (dispatched session) | not started |
+| W2 | rate limiter middleware | S (dispatched session) | done |
+| W3 | structured error bodies | S (dispatched session) | not started — unblocked |
 
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
+**What shipped:** `src/limiter.sh:1-8` — token bucket per client id, 60 requests/minute (refill 1 token/s), burst 10; over the limit prints `429 Retry-After: 1` and exits 1. State is one file per client under `$LIMITER_STATE` (default `/tmp/limiter`).
+**Why:** one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Learnings / handoff to W3:** the 429 is currently a plain-text line, not a structured body — converting it to `{"error": {...}}` is W3's first item. `Retry-After` is a fixed 1 s (one token refills per second), not computed.
+**Commits:** `74f9d54` (limiter), on `origin/main`.
 
 ## W3 — Structured error bodies (NOT STARTED)
[exit 0]
```
