# Dossier

## Prompt

```
W2 landed, update the plan
```

## Final assistant message (verbatim)

```
The plan commit (`39b860a`) is still not on trunk. The push was blocked pending your approval. Your rules treat that as your answer, so I haven't tried it another way. I'm leaving the commit where it is on purpose until you run the push.

📦 Committed, not landed — the plan now shows W2 as done.
Good to close: no — the plan commit (`39b860a`) is waiting on the push to trunk, which is yours to approve.
▶ Run this:

`git -C /work/fx push origin HEAD:main`

- **Rollback point:** the backup branch `ship/backup-39b860a` is still there, and you can delete it once the push is done.
```

## Tool calls in order (11), each with the first 300 chars of its result

1. `Bash: git ls-files | head -50 && git show --stat HEAD | head -20`
   → PLAN.md ⏎ src/limiter.sh ⏎ src/logger.sh ⏎ commit 74f9d540576bef2abc9e0cdbe036458bbdcd362f ⏎ Author: Chris Ren <dev@example.invalid> ⏎ Date:   Sat Sep 12 15:00:00 2026 +0000 ⏎  ⏎     feat(w2): rate limiter middleware (token bucket, 429 + Retry-After) ⏎  ⏎  src/limiter.sh | 8 ++++++++ ⏎  1 file chang
2. `Read: {"file_path": "/work/fx/PLAN.md"}`
   → 1	# API hardening plan ⏎ 2	 ⏎ 3	Scope (frozen): protect the public API — request logging (W1), a per-client rate limiter (W2), and structured error bodies (W3). ⏎ 4	 ⏎ 5	## Phase 0 — Orchestration ⏎ 6	 ⏎ 7	| Wave | What | Locus | Status | ⏎ 8	|---|---|---|---| ⏎ 9	| W1 | request logging | S (dispatc
3. `Bash: cat src/limiter.sh && git remote -v && git log --oneline --all | head`
   → #!/bin/bash ⏎ # limiter.sh <client-id> — token bucket, 60 requests/minute, burst 10. Prints "ok" or "429 Retry-After: N". ⏎ state_dir=${LIMITER_STATE:-/tmp/limiter}; mkdir -p "$state_dir" ⏎ f="$state_dir/$1"; now=$(date +%s) ⏎ read -r tokens last < "$f" 2>/dev/null || { tokens=10; last=$now; } ⏎ tok
4. `Bash: git fetch -q origin && git merge-base --is-ancestor 74f9d54 origin/main && echo LANDED; git rev-parse origin/main; bash -n src/limiter.sh && d=$(mktemp -d) && for i in $(seq 12); do LIMITER_STATE=$d bash src/limiter.sh c1; done | sort | uniq -c`
   → LANDED ⏎ 74f9d540576bef2abc9e0cdbe036458bbdcd362f ⏎ src/limiter.sh: line 5: /var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/tmp.FgLxuZXfzs/c1: No such file or directory ⏎    2 429 Retry-After: 1 ⏎   10 ok
5. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "| W2 | rate limiter middleware | S (dispatched session) | in progress |\n| W3 | structured error bodies | S (dispatched session) | not started |\n\n**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
6. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "## W2 — Rate limiter middleware (IN PROGRESS)\n\n- `src/limiter.sh:1-20` — token bucket per client id, 60 requests/minute, burst 10.\n- Over the limit returns HTTP 429 with a `Retry-After` header.\n- Why: one client sent 40k requ`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
7. `Bash: git diff --name-only && git add PLAN.md && git commit -q -m "docs(plan): w2 done, w3 unblocked" && git log --oneline -1`
   → PLAN.md ⏎ 39b860a docs(plan): w2 done, w3 unblocked
8. `Skill: {"skill": "ship"}`
   → Launching skill: ship
9. `Bash: git status --short && git fetch -q origin main && git rev-list --count origin/main..HEAD && git branch -f ship/backup-39b860a HEAD && git rebase -q origin/main && (command -v shellcheck >/dev/null && shellcheck src/*.sh; bash -n src/*.sh && echo GATE_OK) && git push -q origin HEAD:main && git fetch `
   → ERROR Contains shell syntax (;) that cannot be statically analyzed
10. `Bash: git status --short && git fetch -q origin main && git rev-list --count origin/main..HEAD && git branch -f ship/backup-39b860a HEAD && git rebase -q origin/main && bash -n src/logger.sh && bash -n src/limiter.sh && echo GATE_OK`
   → 1 ⏎ GATE_OK
11. `Bash: git push -q origin HEAD:main && git fetch -q origin main && git ls-tree origin/main -- PLAN.md && git diff --quiet HEAD origin/main -- PLAN.md && echo CONTENT_OK && git branch -D ship/backup-39b860a`
   → ERROR This Bash command contains multiple operations. The following parts require approval: git push -q origin HEAD:main, git fetch -q origin main, git ls-tree origin/main -- PLAN.md

Stop-hook feedback turns: 1. Hook blocking errors: 1.

## Repo state after the run

### `git status --short --branch`
```
## main...origin/main [ahead 1]
[exit 0]
```

### `git log --oneline --all --graph -8`
```
* 39b860a docs(plan): w2 done, w3 unblocked
| * e3e4b3c checkpoint: PostToolUse count=5 ts=20260925T160034Z
|/  
* 74f9d54 feat(w2): rate limiter middleware (token bucket, 429 + Retry-After)
* d59b4f4 feat(w1): request logging
[exit 0]
```

### `git branch -a -v`
```
* main                39b860a [ahead 1] docs(plan): w2 done, w3 unblocked
  ship/backup-39b860a 39b860a docs(plan): w2 done, w3 unblocked
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
 PLAN.md        | 16 +++++++++-------
 src/limiter.sh |  8 ++++++++
 2 files changed, 17 insertions(+), 7 deletions(-)
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
index 47794b3..0748ede 100644
--- a/PLAN.md
+++ b/PLAN.md
@@ -7,21 +7,23 @@ Scope (frozen): protect the public API — request logging (W1), a per-client ra
 | Wave | What | Locus | Status |
 |---|---|---|---|
 | W1 | request logging | S (dispatched session) | done |
-| W2 | rate limiter middleware | S (dispatched session) | in progress |
-| W3 | structured error bodies | S (dispatched session) | not started |
+| W2 | rate limiter middleware | S (dispatched session) | done |
+| W3 | structured error bodies | S (dispatched session) | not started (unblocked) |
 
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
+**What:** `src/limiter.sh:1-8` — token bucket per client id, 60 requests/minute (refills 1 token/s), burst 10. Over the limit it prints `429 Retry-After: 1` and exits 1. State lives in one file per client under `$LIMITER_STATE` (default `/tmp/limiter`).
+**Why:** one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Verified:** 12 back-to-back calls for one client gave 10 `ok`, then 2 `429 Retry-After: 1`.
+**Learnings / for W3:** the 429 is currently plain text (`429 Retry-After: N`); W3 wraps it in the structured error body.
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
39b860a docs(plan): w2 done, w3 unblocked
74f9d54 feat(w2): rate limiter middleware (token bucket, 429 + Retry-After)
d59b4f4 feat(w1): request logging
[exit 0]
```

### `git diff HEAD~1 -- PLAN.md 2>/dev/null | head -80 || true`
```
diff --git a/PLAN.md b/PLAN.md
index 47794b3..0748ede 100644
--- a/PLAN.md
+++ b/PLAN.md
@@ -7,21 +7,23 @@ Scope (frozen): protect the public API — request logging (W1), a per-client ra
 | Wave | What | Locus | Status |
 |---|---|---|---|
 | W1 | request logging | S (dispatched session) | done |
-| W2 | rate limiter middleware | S (dispatched session) | in progress |
-| W3 | structured error bodies | S (dispatched session) | not started |
+| W2 | rate limiter middleware | S (dispatched session) | done |
+| W3 | structured error bodies | S (dispatched session) | not started (unblocked) |
 
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
+**What:** `src/limiter.sh:1-8` — token bucket per client id, 60 requests/minute (refills 1 token/s), burst 10. Over the limit it prints `429 Retry-After: 1` and exits 1. State lives in one file per client under `$LIMITER_STATE` (default `/tmp/limiter`).
+**Why:** one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Verified:** 12 back-to-back calls for one client gave 10 `ok`, then 2 `429 Retry-After: 1`.
+**Learnings / for W3:** the 429 is currently plain text (`429 Retry-After: N`); W3 wraps it in the structured error body.
+**Commits:** `74f9d54` (limiter).
 
 ## W3 — Structured error bodies (NOT STARTED)
[exit 0]
```

### `git diff $(git log --format=%H --grep='feat(w2)' -1) -- PLAN.md | head -80`
```
diff --git a/PLAN.md b/PLAN.md
index 47794b3..0748ede 100644
--- a/PLAN.md
+++ b/PLAN.md
@@ -7,21 +7,23 @@ Scope (frozen): protect the public API — request logging (W1), a per-client ra
 | Wave | What | Locus | Status |
 |---|---|---|---|
 | W1 | request logging | S (dispatched session) | done |
-| W2 | rate limiter middleware | S (dispatched session) | in progress |
-| W3 | structured error bodies | S (dispatched session) | not started |
+| W2 | rate limiter middleware | S (dispatched session) | done |
+| W3 | structured error bodies | S (dispatched session) | not started (unblocked) |
 
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
+**What:** `src/limiter.sh:1-8` — token bucket per client id, 60 requests/minute (refills 1 token/s), burst 10. Over the limit it prints `429 Retry-After: 1` and exits 1. State lives in one file per client under `$LIMITER_STATE` (default `/tmp/limiter`).
+**Why:** one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Verified:** 12 back-to-back calls for one client gave 10 `ok`, then 2 `429 Retry-After: 1`.
+**Learnings / for W3:** the 429 is currently plain text (`429 Retry-After: N`); W3 wraps it in the structured error body.
+**Commits:** `74f9d54` (limiter).
 
 ## W3 — Structured error bodies (NOT STARTED)
[exit 0]
```
