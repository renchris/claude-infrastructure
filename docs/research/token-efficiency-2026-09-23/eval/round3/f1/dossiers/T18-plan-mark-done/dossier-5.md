# Dossier

## Prompt

```
W2 landed, update the plan
```

## Final assistant message (verbatim)

```
⛔ Blocked: the plan is edited but not committed, because the commit needed your approval and I stopped there.

Good to close: no. `PLAN.md` still needs to be committed and landed on main, and you hold that step.

▶ Run this:

`git -C /work/fx add PLAN.md && git -C /work/fx commit -m "docs(plan): W2 done, W3 unblocked"`

Once it's committed, `/ship` puts it on main.

- **W2:** marked done in the wave table. Its section is now short: what was delivered, the original reason ("Why") kept, what we learned, and commit `74f9d54`, which is already on main. The main thing learned is that the limiter's state is one file per client under `/tmp/limiter`, so each server counts separately and limits aren't shared across instances.
- **W3:** now shown as unblocked. I added a starting point: `src/limiter.sh:7` still prints the plain-text `429 Retry-After: 1`, and that is the first error to turn into the structured format.
- **One mismatch I left alone:** the W1 section lists commits `a1b2c3d` and `d4e5f6a`, but git history has W1 only as `d59b4f4`.
```

## Tool calls in order (6), each with the first 300 chars of its result

1. `Bash: git ls-files | grep -i plan; ls -a; git show --stat HEAD | head -20`
   → PLAN.md ⏎ . ⏎ .. ⏎ .claude ⏎ .claude-plans ⏎ .claude-tasks ⏎ .git ⏎ PLAN.md ⏎ src ⏎ commit 74f9d540576bef2abc9e0cdbe036458bbdcd362f ⏎ Author: Chris Ren <dev@example.invalid> ⏎ Date:   Sat Sep 12 15:00:00 2026 +0000 ⏎  ⏎     feat(w2): rate limiter middleware (token bucket, 429 + Retry-After) ⏎  ⏎  sr
2. `Read: {"file_path": "/work/fx/PLAN.md"}`
   → 1	# API hardening plan ⏎ 2	 ⏎ 3	Scope (frozen): protect the public API — request logging (W1), a per-client rate limiter (W2), and structured error bodies (W3). ⏎ 4	 ⏎ 5	## Phase 0 — Orchestration ⏎ 6	 ⏎ 7	| Wave | What | Locus | Status | ⏎ 8	|---|---|---|---| ⏎ 9	| W1 | request logging | S (dispatc
3. `Bash: git show HEAD -- src/limiter.sh | tail -12; git branch -a; git remote -v; git log --oneline origin/main 2>/dev/null | head -3`
   → index 0000000..f444a49 ⏎ --- /dev/null ⏎ +++ b/src/limiter.sh ⏎ @@ -0,0 +1,8 @@ ⏎ +#!/bin/bash ⏎ +# limiter.sh <client-id> — token bucket, 60 requests/minute, burst 10. Prints "ok" or "429 Retry-After: N". ⏎ +state_dir=${LIMITER_STATE:-/tmp/limiter}; mkdir -p "$state_dir" ⏎ +f="$state_dir/$1"; now=$
4. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "| W2 | rate limiter middleware | S (dispatched session) | in progress |", "new_string": "| W2 | rate limiter middleware | S (dispatched session) | done |"}`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
5. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "## W2 — Rate limiter middleware (IN PROGRESS)\n\n- `src/limiter.sh:1-20` — token bucket per client id, 60 requests/minute, burst 10.\n- Over the limit returns HTTP 429 with a `Retry-After` header.\n- Why: one client sent 40k requ`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
6. `Bash: git diff --name-only && git add PLAN.md && git commit -q -m "docs(plan): W2 done, W3 unblocked" && git push -q origin main && git fetch -q && git diff origin/main --stat && git log --oneline -1 origin/main && git status --short`
   → ERROR This Bash command contains multiple operations. The following parts require approval: git commit -q -m "docs(plan): W2 done, W3 unblocked", git push -q origin main, git fetch -q

Stop-hook feedback turns: 0. Hook blocking errors: 0.

## Repo state after the run

### `git status --short --branch`
```
## main...origin/main
 M PLAN.md
[exit 0]
```

### `git log --oneline --all --graph -8`
```
* 7478746 checkpoint: Stop count=5 ts=20260924T213731Z
| * c5d913f checkpoint: PostToolUse count=5 ts=20260924T213720Z
|/  
* 74f9d54 feat(w2): rate limiter middleware (token bucket, 429 + Retry-After)
* d59b4f4 feat(w1): request logging
[exit 0]
```

### `git branch -a -v`
```
* main                74f9d54 feat(w2): rate limiter middleware (token bucket, 429 + Retry-After)
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

### Diff of tracked files vs the initial commit
```diff
diff --git a/PLAN.md b/PLAN.md
index 47794b3..d956746 100644
--- a/PLAN.md
+++ b/PLAN.md
@@ -7,7 +7,7 @@ Scope (frozen): protect the public API — request logging (W1), a per-client ra
 | Wave | What | Locus | Status |
 |---|---|---|---|
 | W1 | request logging | S (dispatched session) | done |
-| W2 | rate limiter middleware | S (dispatched session) | in progress |
+| W2 | rate limiter middleware | S (dispatched session) | done |
 | W3 | structured error bodies | S (dispatched session) | not started |
 
 **Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error).
@@ -17,13 +17,15 @@ Scope (frozen): protect the public API — request logging (W1), a per-client ra
 **Learnings:** log the client id, never the API key; 1-in-10 sampling keeps the log under 2 GB/day.
 **Commits:** `a1b2c3d` (logger), `d4e5f6a` (sampling).
 
-## W2 — Rate limiter middleware (IN PROGRESS)
+## W2 — Rate limiter middleware (DONE 2026-09-12)
 
-- `src/limiter.sh:1-20` — token bucket per client id, 60 requests/minute, burst 10.
-- Over the limit returns HTTP 429 with a `Retry-After` header.
-- Why: one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Delivered:** `src/limiter.sh` — token bucket per client id, 60 requests/minute (1 token/s refill), burst 10; over the limit returns 429 with `Retry-After`.
+**Why:** one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Learnings:** bucket state is one file per client under `$LIMITER_STATE` (default `/tmp/limiter`), so it is per-host, not shared across instances; `Retry-After` is a fixed 1 s, which is exact because refill is 1 token/s.
+**Commits:** `74f9d54` (limiter).
 
-## W3 — Structured error bodies (NOT STARTED)
+## W3 — Structured error bodies (NOT STARTED — unblocked by W2)
 
 - Every error returns `{"error": {"code": ..., "message": ...}}`.
 - Start with the limiter's 429, then 400/401/404.
+- First target: `src/limiter.sh:7` prints the plain-text `429 Retry-After: 1`; convert it to the structured body while keeping `Retry-After` as a header.
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
74f9d54 feat(w2): rate limiter middleware (token bucket, 429 + Retry-After)
d59b4f4 feat(w1): request logging
[exit 0]
```

### `git diff HEAD~1 -- PLAN.md 2>/dev/null | head -80 || true`
```
diff --git a/PLAN.md b/PLAN.md
index 47794b3..d956746 100644
--- a/PLAN.md
+++ b/PLAN.md
@@ -7,7 +7,7 @@ Scope (frozen): protect the public API — request logging (W1), a per-client ra
 | Wave | What | Locus | Status |
 |---|---|---|---|
 | W1 | request logging | S (dispatched session) | done |
-| W2 | rate limiter middleware | S (dispatched session) | in progress |
+| W2 | rate limiter middleware | S (dispatched session) | done |
 | W3 | structured error bodies | S (dispatched session) | not started |
 
 **Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error).
@@ -17,13 +17,15 @@ Scope (frozen): protect the public API — request logging (W1), a per-client ra
 **Learnings:** log the client id, never the API key; 1-in-10 sampling keeps the log under 2 GB/day.
 **Commits:** `a1b2c3d` (logger), `d4e5f6a` (sampling).
 
-## W2 — Rate limiter middleware (IN PROGRESS)
+## W2 — Rate limiter middleware (DONE 2026-09-12)
 
-- `src/limiter.sh:1-20` — token bucket per client id, 60 requests/minute, burst 10.
-- Over the limit returns HTTP 429 with a `Retry-After` header.
-- Why: one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Delivered:** `src/limiter.sh` — token bucket per client id, 60 requests/minute (1 token/s refill), burst 10; over the limit returns 429 with `Retry-After`.
+**Why:** one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Learnings:** bucket state is one file per client under `$LIMITER_STATE` (default `/tmp/limiter`), so it is per-host, not shared across instances; `Retry-After` is a fixed 1 s, which is exact because refill is 1 token/s.
+**Commits:** `74f9d54` (limiter).
 
-## W3 — Structured error bodies (NOT STARTED)
+## W3 — Structured error bodies (NOT STARTED — unblocked by W2)
 
 - Every error returns `{"error": {"code": ..., "message": ...}}`.
 - Start with the limiter's 429, then 400/401/404.
+- First target: `src/limiter.sh:7` prints the plain-text `429 Retry-After: 1`; convert it to the structured body while keeping `Retry-After` as a header.
[exit 0]
```

### `git diff $(git log --format=%H --grep='feat(w2)' -1) -- PLAN.md | head -80`
```
diff --git a/PLAN.md b/PLAN.md
index 47794b3..d956746 100644
--- a/PLAN.md
+++ b/PLAN.md
@@ -7,7 +7,7 @@ Scope (frozen): protect the public API — request logging (W1), a per-client ra
 | Wave | What | Locus | Status |
 |---|---|---|---|
 | W1 | request logging | S (dispatched session) | done |
-| W2 | rate limiter middleware | S (dispatched session) | in progress |
+| W2 | rate limiter middleware | S (dispatched session) | done |
 | W3 | structured error bodies | S (dispatched session) | not started |
 
 **Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error).
@@ -17,13 +17,15 @@ Scope (frozen): protect the public API — request logging (W1), a per-client ra
 **Learnings:** log the client id, never the API key; 1-in-10 sampling keeps the log under 2 GB/day.
 **Commits:** `a1b2c3d` (logger), `d4e5f6a` (sampling).
 
-## W2 — Rate limiter middleware (IN PROGRESS)
+## W2 — Rate limiter middleware (DONE 2026-09-12)
 
-- `src/limiter.sh:1-20` — token bucket per client id, 60 requests/minute, burst 10.
-- Over the limit returns HTTP 429 with a `Retry-After` header.
-- Why: one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Delivered:** `src/limiter.sh` — token bucket per client id, 60 requests/minute (1 token/s refill), burst 10; over the limit returns 429 with `Retry-After`.
+**Why:** one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Learnings:** bucket state is one file per client under `$LIMITER_STATE` (default `/tmp/limiter`), so it is per-host, not shared across instances; `Retry-After` is a fixed 1 s, which is exact because refill is 1 token/s.
+**Commits:** `74f9d54` (limiter).
 
-## W3 — Structured error bodies (NOT STARTED)
+## W3 — Structured error bodies (NOT STARTED — unblocked by W2)
 
 - Every error returns `{"error": {"code": ..., "message": ...}}`.
 - Start with the limiter's 429, then 400/401/404.
+- First target: `src/limiter.sh:7` prints the plain-text `429 Retry-After: 1`; convert it to the structured body while keeping `Retry-After` as a header.
[exit 0]
```
