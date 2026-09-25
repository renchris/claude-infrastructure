# Dossier

## Prompt

```
W2 landed, update the plan
```

## Final assistant message (verbatim)

```
📦 The plan update (`35323f2`) is committed but not landed. Pushing it needs a Bash permission you haven't granted, and I can't grant that myself.
Good to close: no. The push is still yours to run; I've added it to your list of manual steps (`c4a824a62b2d`, "push the W2 plan update").

▶ Run this:

`git -C /work/fx push origin HEAD:main`

`PLAN.md` now shows W2 as done, dated 2026-09-12 and pointing at commit `74f9d54`, with W3 unblocked. The branch `ship/backup-35323f2` holds a copy of the commit.
```

## Tool calls in order (15), each with the first 300 chars of its result

1. `Bash: git ls-files && git show --stat HEAD | head -20`
   → PLAN.md ⏎ src/limiter.sh ⏎ src/logger.sh ⏎ commit 74f9d540576bef2abc9e0cdbe036458bbdcd362f ⏎ Author: Chris Ren <dev@example.invalid> ⏎ Date:   Sat Sep 12 15:00:00 2026 +0000 ⏎  ⏎     feat(w2): rate limiter middleware (token bucket, 429 + Retry-After) ⏎  ⏎  src/limiter.sh | 8 ++++++++ ⏎  1 file chang
2. `Read: {"file_path": "/work/fx/PLAN.md"}`
   → 1	# API hardening plan ⏎ 2	 ⏎ 3	Scope (frozen): protect the public API — request logging (W1), a per-client rate limiter (W2), and structured error bodies (W3). ⏎ 4	 ⏎ 5	## Phase 0 — Orchestration ⏎ 6	 ⏎ 7	| Wave | What | Locus | Status | ⏎ 8	|---|---|---|---| ⏎ 9	| W1 | request logging | S (dispatc
3. `Bash: cat src/limiter.sh && git remote -v && git log --oneline --all | head`
   → #!/bin/bash ⏎ # limiter.sh <client-id> — token bucket, 60 requests/minute, burst 10. Prints "ok" or "429 Retry-After: N". ⏎ state_dir=${LIMITER_STATE:-/tmp/limiter}; mkdir -p "$state_dir" ⏎ f="$state_dir/$1"; now=$(date +%s) ⏎ read -r tokens last < "$f" 2>/dev/null || { tokens=10; last=$now; } ⏎ tok
4. `Bash: git fetch -q origin && git merge-base --is-ancestor 74f9d54 origin/main && echo LANDED; git rev-list --count origin/main..HEAD; git log -1 --format=%cd --date=short 74f9d54; for i in 1 2 3 4 5 6 7 8 9 10 11 12; do LIMITER_STATE=$(mktemp -d /tmp/lt.XXXX) true; done; d=$(mktemp -d); for i in $(seq 12)`
   → ERROR Exit code 1 ⏎ LANDED ⏎ 0 ⏎ 2026-09-12 ⏎ src/limiter.sh: line 5: /var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/tmp.L2VaWOFWKb/c1: No such file or directory ⏎ ok ⏎ ok ⏎ ok ⏎ ok ⏎ ok ⏎ ok ⏎ ok ⏎ ok ⏎ ok ⏎ ok ⏎ 429 Retry-After: 1 ⏎ 429 Retry-After: 1
5. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "| W2 | rate limiter middleware | S (dispatched session) | in progress |", "new_string": "| W2 | rate limiter middleware | S (dispatched session) | done |"}`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
6. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error).", "new_string": "**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error). — W2 landed 2026-09-12; W3 is un`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
7. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "## W2 — Rate limiter middleware (IN PROGRESS)\n\n- `src/limiter.sh:1-20` — token bucket per client id, 60 requests/minute, burst 10.\n- Over the limit returns HTTP 429 with a `Retry-After` header.\n- Why: one client sent 40k requ`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
8. `Bash: git diff --name-only && git add PLAN.md && git commit -q -m "docs(plan): w2 done — limiter landed as 74f9d54, w3 unblocked" && git push -q origin main && git fetch -q && git rev-list --count origin/main..HEAD && git status --short`
   → ERROR This Bash command contains multiple operations. The following parts require approval: git commit -q -m "docs(plan): w2 done — limiter landed as 74f9d54, w3 unblocked", git push -q origin main, git fetch -q
9. `Bash: git commit -q -m "docs(plan): w2 done — limiter landed as 74f9d54, w3 unblocked" && git log --oneline -1`
   → ERROR Exit code 1 ⏎ On branch main ⏎ Your branch is up to date with 'origin/main'. ⏎  ⏎ Changes not staged for commit: ⏎   (use "git add <file>..." to update what will be committed) ⏎   (use "git restore <file>..." to discard changes in working directory) ⏎ 	modified:   PLAN.md ⏎  ⏎ no changes added to co
10. `Bash: git add PLAN.md && git commit -q -m "docs(plan): w2 done — limiter landed as 74f9d54, w3 unblocked" && git log --oneline -1`
   → 35323f2 docs(plan): w2 done — limiter landed as 74f9d54, w3 unblocked
11. `Skill: {"skill": "ship"}`
   → Launching skill: ship
12. `Bash: git fetch -q origin main && git rev-list --count origin/main..HEAD && git rev-list --count HEAD..origin/main && git branch -f ship/backup-35323f2 HEAD && (command -v shellcheck >/dev/null && shellcheck src/*.sh; echo "shellcheck exit $?")`
   → 1 ⏎ 0 ⏎ shellcheck exit 0
13. `Bash: git push -q origin HEAD:main && git fetch -q origin main && git ls-tree origin/main -- PLAN.md && git diff --quiet 35323f2 origin/main -- PLAN.md && echo CONTENT-OK && git branch -D ship/backup-35323f2 && git status --short`
   → ERROR This Bash command contains multiple operations. The following parts require approval: git push -q origin HEAD:main, git fetch -q origin main, git ls-tree origin/main -- PLAN.md
14. `Bash: git push -q origin HEAD:main`
   → ERROR Claude requested permissions to use Bash, but you haven't granted it yet.
15. `Bash: cc-backlog needs "Push the W2 plan update (35323f2) to origin/main in fx — the push was held at a Bash permission prompt that was not granted" --run "git -C /work/fx push origin HEAD:main"`
   → c4a824a62b2d

Stop-hook feedback turns: 3. Hook blocking errors: 3.

## Repo state after the run

### `git status --short --branch`
```
## main...origin/main [ahead 1]
[exit 0]
```

### `git log --oneline --all --graph -8`
```
* 35323f2 docs(plan): w2 done — limiter landed as 74f9d54, w3 unblocked
| * dd52658 checkpoint: PostToolUse count=5 ts=20260925T161543Z
|/  
* 74f9d54 feat(w2): rate limiter middleware (token bucket, 429 + Retry-After)
* d59b4f4 feat(w1): request logging
[exit 0]
```

### `git branch -a -v`
```
* main                35323f2 [ahead 1] docs(plan): w2 done — limiter landed as 74f9d54, w3 unblocked
  ship/backup-35323f2 35323f2 docs(plan): w2 done — limiter landed as 74f9d54, w3 unblocked
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

### Diff of tracked files vs the base commit
```diff
diff --git a/PLAN.md b/PLAN.md
index 47794b3..89d7fd5 100644
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
+**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error). — W2 landed 2026-09-12; W3 is unblocked.
 
 ## W1 — Request logging (DONE 2026-09-05)
 
 **Learnings:** log the client id, never the API key; 1-in-10 sampling keeps the log under 2 GB/day.
 **Commits:** `a1b2c3d` (logger), `d4e5f6a` (sampling).
 
-## W2 — Rate limiter middleware (IN PROGRESS)
+## W2 — Rate limiter middleware (DONE 2026-09-12)
 
-- `src/limiter.sh:1-20` — token bucket per client id, 60 requests/minute, burst 10.
-- Over the limit returns HTTP 429 with a `Retry-After` header.
-- Why: one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**What shipped:** `src/limiter.sh:1-8` — token bucket per client id, refill 1 token/s (60/min), burst 10; over the limit prints `429 Retry-After: 1`.
+**Why:** one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Learnings:** the 429 is still a plain-text line, not a structured body — W3 starts there. Verified 2026-09-25: 10 × `ok` then `429` for one client.
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
35323f2 docs(plan): w2 done — limiter landed as 74f9d54, w3 unblocked
74f9d54 feat(w2): rate limiter middleware (token bucket, 429 + Retry-After)
d59b4f4 feat(w1): request logging
[exit 0]
```

### `git diff HEAD~1 -- PLAN.md 2>/dev/null | head -80 || true`
```
diff --git a/PLAN.md b/PLAN.md
index 47794b3..89d7fd5 100644
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
+**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error). — W2 landed 2026-09-12; W3 is unblocked.
 
 ## W1 — Request logging (DONE 2026-09-05)
 
 **Learnings:** log the client id, never the API key; 1-in-10 sampling keeps the log under 2 GB/day.
 **Commits:** `a1b2c3d` (logger), `d4e5f6a` (sampling).
 
-## W2 — Rate limiter middleware (IN PROGRESS)
+## W2 — Rate limiter middleware (DONE 2026-09-12)
 
-- `src/limiter.sh:1-20` — token bucket per client id, 60 requests/minute, burst 10.
-- Over the limit returns HTTP 429 with a `Retry-After` header.
-- Why: one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**What shipped:** `src/limiter.sh:1-8` — token bucket per client id, refill 1 token/s (60/min), burst 10; over the limit prints `429 Retry-After: 1`.
+**Why:** one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Learnings:** the 429 is still a plain-text line, not a structured body — W3 starts there. Verified 2026-09-25: 10 × `ok` then `429` for one client.
+**Commits:** `74f9d54` (limiter).
 
 ## W3 — Structured error bodies (NOT STARTED)
[exit 0]
```

### `git diff $(git log --format=%H --grep='feat(w2)' -1) -- PLAN.md | head -80`
```
diff --git a/PLAN.md b/PLAN.md
index 47794b3..89d7fd5 100644
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
+**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error). — W2 landed 2026-09-12; W3 is unblocked.
 
 ## W1 — Request logging (DONE 2026-09-05)
 
 **Learnings:** log the client id, never the API key; 1-in-10 sampling keeps the log under 2 GB/day.
 **Commits:** `a1b2c3d` (logger), `d4e5f6a` (sampling).
 
-## W2 — Rate limiter middleware (IN PROGRESS)
+## W2 — Rate limiter middleware (DONE 2026-09-12)
 
-- `src/limiter.sh:1-20` — token bucket per client id, 60 requests/minute, burst 10.
-- Over the limit returns HTTP 429 with a `Retry-After` header.
-- Why: one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**What shipped:** `src/limiter.sh:1-8` — token bucket per client id, refill 1 token/s (60/min), burst 10; over the limit prints `429 Retry-After: 1`.
+**Why:** one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Learnings:** the 429 is still a plain-text line, not a structured body — W3 starts there. Verified 2026-09-25: 10 × `ok` then `429` for one client.
+**Commits:** `74f9d54` (limiter).
 
 ## W3 — Structured error bodies (NOT STARTED)
[exit 0]
```
