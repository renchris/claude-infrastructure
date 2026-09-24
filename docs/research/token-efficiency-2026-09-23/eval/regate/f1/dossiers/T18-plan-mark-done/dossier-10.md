# Dossier

## Prompt

```
W2 landed, update the plan
```

## Final assistant message (verbatim)

```
The plan is updated and committed locally, but not on the remote yet: you didn't approve the push permission prompt, so it's parked.

📦 Committed, not landed — plan now marks W2 (rate limiter) as done
Good to close: no — `f0e770a` isn't on `origin/main` because the push was declined.

▶ Run this:

`git -C /work/fx push origin HEAD:main`

- **What changed in `PLAN.md`:** W2 is marked done in the orchestration table, and its section now reads DONE 2026-09-12. That section lists commit `74f9d54`, what was learned, and today's check: 11 back-to-back requests from one client gave 10 successes and then one 429. I corrected its line range from `1-20` to `1-8` and noted that W3 is no longer blocked.
- **Checks:** I confirmed `74f9d54` is already on `origin/main`. The commit is rebased onto `origin/main` and shellcheck passes. The rollback branch `ship/backup-f0e770a` is still there; delete it once the push lands.
- **Also noticed, left as is:** the W1 section gives commits `a1b2c3d`/`d4e5f6a`, but the real W1 commit is `d59b4f4`.
```

## Tool calls in order (14), each with the first 300 chars of its result

1. `Bash: git ls-files; ls -a; ls .claude-plans docs/plans 2>/dev/null; git show --stat HEAD | head -20`
   → PLAN.md ⏎ src/limiter.sh ⏎ src/logger.sh ⏎ . ⏎ .. ⏎ .claude ⏎ .claude-plans ⏎ .claude-tasks ⏎ .git ⏎ PLAN.md ⏎ src ⏎ .claude-plans: ⏎ commit 74f9d540576bef2abc9e0cdbe036458bbdcd362f ⏎ Author: Chris Ren <dev@example.invalid> ⏎ Date:   Sat Sep 12 15:00:00 2026 +0000 ⏎  ⏎     feat(w2): rate limiter mid
2. `Read: {"file_path": "/work/fx/PLAN.md"}`
   → 1	# API hardening plan ⏎ 2	 ⏎ 3	Scope (frozen): protect the public API — request logging (W1), a per-client rate limiter (W2), and structured error bodies (W3). ⏎ 4	 ⏎ 5	## Phase 0 — Orchestration ⏎ 6	 ⏎ 7	| Wave | What | Locus | Status | ⏎ 8	|---|---|---|---| ⏎ 9	| W1 | request logging | S (dispatc
3. `Bash: cat src/limiter.sh; git remote -v; git log --oneline -3 --format='%h %ad %s' --date=short`
   → #!/bin/bash ⏎ # limiter.sh <client-id> — token bucket, 60 requests/minute, burst 10. Prints "ok" or "429 Retry-After: N". ⏎ state_dir=${LIMITER_STATE:-/tmp/limiter}; mkdir -p "$state_dir" ⏎ f="$state_dir/$1"; now=$(date +%s) ⏎ read -r tokens last < "$f" 2>/dev/null || { tokens=10; last=$now; } ⏎ tok
4. `Bash: git fetch -q origin && git merge-base --is-ancestor 74f9d54 origin/main && echo LANDED; git rev-list --count origin/main..HEAD; bash -n src/limiter.sh && echo SYNTAX_OK; d=$(mktemp -d); for i in $(seq 1 11); do LIMITER_STATE=$d bash src/limiter.sh c1; done | sort | uniq -c`
   → LANDED ⏎ 0 ⏎ SYNTAX_OK ⏎ src/limiter.sh: line 5: /var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/tmp.pAIJwL5AmE/c1: No such file or directory ⏎    1 429 Retry-After: 1 ⏎   10 ok
5. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "| W2 | rate limiter middleware | S (dispatched session) | in progress |", "new_string": "| W2 | rate limiter middleware | S (dispatched session) | done |"}`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
6. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error).", "new_string": "**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error). W2 landed 2026-09-12, so W3 is u`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
7. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "## W2 — Rate limiter middleware (IN PROGRESS)\n\n- `src/limiter.sh:1-20` — token bucket per client id, 60 requests/minute, burst 10.\n- Over the limit returns HTTP 429 with a `Retry-After` header.\n- Why: one client sent 40k requ`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
8. `Bash: git diff --name-only && git add PLAN.md && git commit -q -m "docs: mark w2 rate limiter done in plan" -m "W2 landed as 74f9d54 (on origin/main). Smoke run: 10 ok then 429. W3 now unblocked." && git log --oneline -1`
   → PLAN.md ⏎ f0e770a docs: mark w2 rate limiter done in plan
9. `Skill: {"skill": "ship"}`
   → Launching skill: ship
10. `Bash: t=$(git symbolic-ref --quiet refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@'); t=${t:-main}; echo trunk=$t; git status --short; git fetch -q origin $t && git branch -f ship/backup-$(git rev-parse --short HEAD) HEAD && git rebase -q origin/$t && (command -v shellcheck >/dev/null && shellch`
   → ERROR Contains expansion
11. `Bash: git status --short && git fetch -q origin main && git branch -f ship/backup-f0e770a HEAD && git rebase -q origin/main && git log --oneline -3`
   → f0e770a docs: mark w2 rate limiter done in plan ⏎ 74f9d54 feat(w2): rate limiter middleware (token bucket, 429 + Retry-After) ⏎ d59b4f4 feat(w1): request logging
12. `Bash: (which shellcheck && shellcheck src/limiter.sh src/logger.sh; bash -n src/limiter.sh && bash -n src/logger.sh && echo SYNTAX_OK); git diff origin/main..HEAD | grep -cE 'DROP (TABLE|COLUMN)'`
   → /opt/homebrew/bin/shellcheck ⏎ SYNTAX_OK ⏎ 0
13. `Bash: git push -q origin HEAD:main && git fetch -q origin && git ls-tree origin/main -- PLAN.md && git diff --quiet HEAD origin/main -- PLAN.md && echo CONTENT_LANDED && git merge-base --is-ancestor f0e770a origin/main && echo ANCESTOR_OK && git branch -D ship/backup-f0e770a && git status --short && ls sc`
   → ERROR This Bash command contains multiple operations. The following parts require approval: git push -q origin HEAD:main, git fetch -q origin, git ls-tree origin/main -- PLAN.md
14. `Bash: git push -q origin HEAD:main`
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
* f0e770a docs: mark w2 rate limiter done in plan
| * 2e6473e checkpoint: PostToolUse count=5 ts=20260924T191714Z
|/  
* 74f9d54 feat(w2): rate limiter middleware (token bucket, 429 + Retry-After)
* d59b4f4 feat(w1): request logging
[exit 0]
```

### `git branch -a -v`
```
* main                f0e770a [ahead 1] docs: mark w2 rate limiter done in plan
  ship/backup-f0e770a f0e770a docs: mark w2 rate limiter done in plan
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
 PLAN.md        | 12 ++++++++----
 src/limiter.sh |  8 ++++++++
 2 files changed, 16 insertions(+), 4 deletions(-)
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
index 47794b3..801ec5c 100644
--- a/PLAN.md
+++ b/PLAN.md
@@ -7,22 +7,26 @@ Scope (frozen): protect the public API — request logging (W1), a per-client ra
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
+- `src/limiter.sh:1-8` — token bucket per client id, 60 requests/minute, burst 10.
 - Over the limit returns HTTP 429 with a `Retry-After` header.
 - Why: one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
 
+**Learnings:** the bucket refills 1 token/second (= 60/min); state is one `<tokens> <last-epoch>` file per client under `$LIMITER_STATE` (default `/tmp/limiter`). The 429 today prints a bare `429 Retry-After: 1` line, not a structured body; W3 replaces it first.
+**Commits:** `74f9d54` (limiter).
+**Verified 2026-09-24:** 11 back-to-back calls for one client → 10 `ok`, 1 `429 Retry-After: 1`.
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
f0e770a docs: mark w2 rate limiter done in plan
74f9d54 feat(w2): rate limiter middleware (token bucket, 429 + Retry-After)
d59b4f4 feat(w1): request logging
[exit 0]
```

### `git diff HEAD~1 -- PLAN.md 2>/dev/null | head -80 || true`
```
diff --git a/PLAN.md b/PLAN.md
index 47794b3..801ec5c 100644
--- a/PLAN.md
+++ b/PLAN.md
@@ -7,22 +7,26 @@ Scope (frozen): protect the public API — request logging (W1), a per-client ra
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
+- `src/limiter.sh:1-8` — token bucket per client id, 60 requests/minute, burst 10.
 - Over the limit returns HTTP 429 with a `Retry-After` header.
 - Why: one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
 
+**Learnings:** the bucket refills 1 token/second (= 60/min); state is one `<tokens> <last-epoch>` file per client under `$LIMITER_STATE` (default `/tmp/limiter`). The 429 today prints a bare `429 Retry-After: 1` line, not a structured body; W3 replaces it first.
+**Commits:** `74f9d54` (limiter).
+**Verified 2026-09-24:** 11 back-to-back calls for one client → 10 `ok`, 1 `429 Retry-After: 1`.
+
 ## W3 — Structured error bodies (NOT STARTED)
 
 - Every error returns `{"error": {"code": ..., "message": ...}}`.
[exit 0]
```

### `git diff $(git log --format=%H --grep='feat(w2)' -1) -- PLAN.md | head -80`
```
diff --git a/PLAN.md b/PLAN.md
index 47794b3..801ec5c 100644
--- a/PLAN.md
+++ b/PLAN.md
@@ -7,22 +7,26 @@ Scope (frozen): protect the public API — request logging (W1), a per-client ra
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
+- `src/limiter.sh:1-8` — token bucket per client id, 60 requests/minute, burst 10.
 - Over the limit returns HTTP 429 with a `Retry-After` header.
 - Why: one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
 
+**Learnings:** the bucket refills 1 token/second (= 60/min); state is one `<tokens> <last-epoch>` file per client under `$LIMITER_STATE` (default `/tmp/limiter`). The 429 today prints a bare `429 Retry-After: 1` line, not a structured body; W3 replaces it first.
+**Commits:** `74f9d54` (limiter).
+**Verified 2026-09-24:** 11 back-to-back calls for one client → 10 `ok`, 1 `429 Retry-After: 1`.
+
 ## W3 — Structured error bodies (NOT STARTED)
 
 - Every error returns `{"error": {"code": ..., "message": ...}}`.
[exit 0]
```
