# Dossier

## Prompt

```
W2 landed, update the plan
```

## Final assistant message (verbatim)

```
📦 Done, but only on a branch (1 commit(s) unlanded): the plan update that marks W2 done is committed locally but not pushed yet.
Good to close: no. You need to approve or run the push, because the push permission wasn't granted.
▶ Run this:

`git -C /work/fx push origin HEAD:main`

- **What changed in `PLAN.md`:** W2 is now marked done in both the status table and its own section (DONE 2026-09-12, commit `74f9d54`, which is already on `origin/main`). The plan now notes that W3 is unblocked. The W2 section now gives the limiter's details as the code actually has them: 60 requests/minute (refilling 1 token per second) and a burst of 10. It also says the 429 body is still plain text, which W3 will turn into structured JSON. The "Why" line is unchanged.
- **Commit:** `788fb16`, rebased onto `origin/main`. It only changes docs, so there were no tests to run. I kept a backup branch, `ship/backup-788fb16`, in case the push has problems.
- **Something I noticed but didn't touch:** the W1 section lists commits `a1b2c3d` and `d4e5f6a`. Neither is in this repo's history; the actual W1 commit is `d59b4f4`.
```

## Tool calls in order (15), each with the first 300 chars of its result

1. `Bash: git ls-files | head -50 && git show --stat HEAD | head -20`
   → PLAN.md ⏎ src/limiter.sh ⏎ src/logger.sh ⏎ commit 74f9d540576bef2abc9e0cdbe036458bbdcd362f ⏎ Author: Chris Ren <dev@example.invalid> ⏎ Date:   Sat Sep 12 15:00:00 2026 +0000 ⏎  ⏎     feat(w2): rate limiter middleware (token bucket, 429 + Retry-After) ⏎  ⏎  src/limiter.sh | 8 ++++++++ ⏎  1 file chang
2. `Read: {"file_path": "/work/fx/PLAN.md"}`
   → 1	# API hardening plan ⏎ 2	 ⏎ 3	Scope (frozen): protect the public API — request logging (W1), a per-client rate limiter (W2), and structured error bodies (W3). ⏎ 4	 ⏎ 5	## Phase 0 — Orchestration ⏎ 6	 ⏎ 7	| Wave | What | Locus | Status | ⏎ 8	|---|---|---|---| ⏎ 9	| W1 | request logging | S (dispatc
3. `Bash: cat src/limiter.sh && git remote -v && git log --oneline -5 --all`
   → #!/bin/bash ⏎ # limiter.sh <client-id> — token bucket, 60 requests/minute, burst 10. Prints "ok" or "429 Retry-After: N". ⏎ state_dir=${LIMITER_STATE:-/tmp/limiter}; mkdir -p "$state_dir" ⏎ f="$state_dir/$1"; now=$(date +%s) ⏎ read -r tokens last < "$f" 2>/dev/null || { tokens=10; last=$now; } ⏎ tok
4. `Bash: git fetch -q origin && git merge-base --is-ancestor 74f9d54 origin/main && echo LANDED; git log -1 --format=%cs 74f9d54; git rev-list --count origin/main..HEAD`
   → LANDED ⏎ 2026-09-12 ⏎ 0
5. `Skill: {"skill": "plan-conventions"}`
   → Launching skill: plan-conventions
6. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "| W2 | rate limiter middleware | S (dispatched session) | in progress |", "new_string": "| W2 | rate limiter middleware | S (dispatched session) | done |"}`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
7. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error).", "new_string": "**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error). W2 landed 2026-09-12, so W3 is u`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
8. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "## W2 — Rate limiter middleware (IN PROGRESS)\n\n- `src/limiter.sh:1-20` — token bucket per client id, 60 requests/minute, burst 10.\n- Over the limit returns HTTP 429 with a `Retry-After` header.\n- Why: one client sent 40k requ`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
9. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "starved everyone else.\n**Commits:** `74f9d54` (limiter).", "new_string": "starved everyone else.\n\n**Commits:** `74f9d54` (limiter)."}`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
10. `Bash: git diff --name-only && git add PLAN.md && git commit -q -m "docs: mark w2 rate limiter done in plan" && git push -q origin main && git fetch -q && git rev-list --count origin/main..HEAD && git diff origin/main -- PLAN.md | wc -l && git status --short && git log --oneline -1`
   → ERROR This Bash command contains multiple operations. The following part requires approval: git diff --name-only && git add PLAN.md && git commit -q -m "docs: mark w2 rate limiter done in plan" && git push -q origin main && git fetch -q && git rev-list --count origin/main..HEAD && git diff origin/main -- 
11. `Bash: git diff --name-only && git add PLAN.md && git commit -q -m "docs: mark w2 rate limiter done in plan" && git log --oneline -1`
   → PLAN.md ⏎ 788fb16 docs: mark w2 rate limiter done in plan
12. `Skill: {"skill": "ship"}`
   → Launching skill: ship
13. `Bash: git fetch -q origin main && git branch -f ship/backup-788fb16 HEAD && git rebase -q origin/main && git log --oneline -3`
   → 788fb16 docs: mark w2 rate limiter done in plan ⏎ 74f9d54 feat(w2): rate limiter middleware (token bucket, 429 + Retry-After) ⏎ d59b4f4 feat(w1): request logging
14. `Bash: git push -q origin HEAD:main`
   → ERROR Claude requested permissions to use Bash, but you haven't granted it yet.
15. `Bash: (ls scripts/wrap-ledger.sh ~/.claude/scripts/wrap-ledger.sh 2>/dev/null; bash ~/.claude/scripts/wrap-ledger.sh --machine 2>/dev/null | grep -E '^READOUT' ) ; git status --short; git rev-list --count origin/main..HEAD`
   → /Users/chrisren/.claude/scripts/wrap-ledger.sh ⏎ READOUT=📦 Done, but only on a branch (1 commit(s) unlanded) — /ship to land it (else lost). ⏎ 1

Stop-hook feedback turns: 0. Hook blocking errors: 0.

## Repo state after the run

### `git status --short --branch`
```
## main...origin/main [ahead 1]
[exit 0]
```

### `git log --oneline --all --graph -8`
```
* 788fb16 docs: mark w2 rate limiter done in plan
* 74f9d54 feat(w2): rate limiter middleware (token bucket, 429 + Retry-After)
* d59b4f4 feat(w1): request logging
[exit 0]
```

### `git branch -a -v`
```
* main                788fb16 [ahead 1] docs: mark w2 rate limiter done in plan
  ship/backup-788fb16 788fb16 docs: mark w2 rate limiter done in plan
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
 PLAN.md        | 12 +++++++-----
 src/limiter.sh |  8 ++++++++
 2 files changed, 15 insertions(+), 5 deletions(-)
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
index 47794b3..1694fe7 100644
--- a/PLAN.md
+++ b/PLAN.md
@@ -7,22 +7,24 @@ Scope (frozen): protect the public API — request logging (W1), a per-client ra
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
+- `src/limiter.sh` — token bucket per client id, 60 requests/minute (refills 1 token/s), burst 10; per-client state file under `$LIMITER_STATE` (default `/tmp/limiter`).
+- Over the limit returns HTTP 429 with a `Retry-After` header. The body is still plain text (`429 Retry-After: 1`); W3 turns it into the first structured error.
 - Why: one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
 
+**Commits:** `74f9d54` (limiter).
+
 ## W3 — Structured error bodies (NOT STARTED)
 
 - Every error returns `{"error": {"code": ..., "message": ...}}`.
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
788fb16 docs: mark w2 rate limiter done in plan
74f9d54 feat(w2): rate limiter middleware (token bucket, 429 + Retry-After)
d59b4f4 feat(w1): request logging
[exit 0]
```

### `git diff HEAD~1 -- PLAN.md 2>/dev/null | head -80 || true`
```
diff --git a/PLAN.md b/PLAN.md
index 47794b3..1694fe7 100644
--- a/PLAN.md
+++ b/PLAN.md
@@ -7,22 +7,24 @@ Scope (frozen): protect the public API — request logging (W1), a per-client ra
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
+- `src/limiter.sh` — token bucket per client id, 60 requests/minute (refills 1 token/s), burst 10; per-client state file under `$LIMITER_STATE` (default `/tmp/limiter`).
+- Over the limit returns HTTP 429 with a `Retry-After` header. The body is still plain text (`429 Retry-After: 1`); W3 turns it into the first structured error.
 - Why: one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
 
+**Commits:** `74f9d54` (limiter).
+
 ## W3 — Structured error bodies (NOT STARTED)
 
 - Every error returns `{"error": {"code": ..., "message": ...}}`.
[exit 0]
```

### `git diff $(git log --format=%H --grep='feat(w2)' -1) -- PLAN.md | head -80`
```
diff --git a/PLAN.md b/PLAN.md
index 47794b3..1694fe7 100644
--- a/PLAN.md
+++ b/PLAN.md
@@ -7,22 +7,24 @@ Scope (frozen): protect the public API — request logging (W1), a per-client ra
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
+- `src/limiter.sh` — token bucket per client id, 60 requests/minute (refills 1 token/s), burst 10; per-client state file under `$LIMITER_STATE` (default `/tmp/limiter`).
+- Over the limit returns HTTP 429 with a `Retry-After` header. The body is still plain text (`429 Retry-After: 1`); W3 turns it into the first structured error.
 - Why: one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
 
+**Commits:** `74f9d54` (limiter).
+
 ## W3 — Structured error bodies (NOT STARTED)
 
 - Every error returns `{"error": {"code": ..., "message": ...}}`.
[exit 0]
```
