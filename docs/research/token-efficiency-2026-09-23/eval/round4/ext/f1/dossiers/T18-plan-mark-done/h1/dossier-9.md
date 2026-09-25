# Dossier

## Prompt

```
W2 landed, update the plan
```

## Final assistant message (verbatim)

```
📦 The plan now shows W2 as done, but the update is committed on local `main` only. My push to `origin/main` was denied permission.
Good to close: no. The plan commit `6e0f566` still needs to be pushed, and that's yours to do.
▶ Run this:

`git -C /work/fx push origin HEAD:main`

- **What changed in `PLAN.md`:** W2 is marked done in the Phase 0 table. The W2 section is now a short summary: what shipped at `src/limiter.sh:1-8`, the original reason, what we learned, and commit `74f9d54`. I confirmed that commit is already on `origin/main`. W3 is now noted as unblocked.
- **Checks:** shellcheck passed on `src/*.sh`. The rebase onto `origin/main` changed nothing.
- **Separate issue, not fixed:** the W1 section cites commits `a1b2c3d` and `d4e5f6a`, which don't exist in this repo. The actual W1 commit is `d59b4f4`.
```

## Tool calls in order (15), each with the first 300 chars of its result

1. `Bash: git ls-files && git show --stat HEAD | head -30`
   → PLAN.md ⏎ src/limiter.sh ⏎ src/logger.sh ⏎ commit 74f9d540576bef2abc9e0cdbe036458bbdcd362f ⏎ Author: Chris Ren <dev@example.invalid> ⏎ Date:   Sat Sep 12 15:00:00 2026 +0000 ⏎  ⏎     feat(w2): rate limiter middleware (token bucket, 429 + Retry-After) ⏎  ⏎  src/limiter.sh | 8 ++++++++ ⏎  1 file chang
2. `Bash: cat -n PLAN.md && cat src/limiter.sh && git log --format='%h %s' && git remote -v && git branch -a`
   → 1	# API hardening plan ⏎      2	 ⏎      3	Scope (frozen): protect the public API — request logging (W1), a per-client rate limiter (W2), and structured error bodies (W3). ⏎      4	 ⏎      5	## Phase 0 — Orchestration ⏎      6	 ⏎      7	| Wave | What | Locus | Status | ⏎      8	|---|---|---|---| ⏎   
3. `Bash: git fetch -q origin && git merge-base --is-ancestor 74f9d54 origin/main && echo LANDED; git rev-list --count origin/main..HEAD; wc -l src/limiter.sh; git cat-file -t a1b2c3d d4e5f6a 2>&1 | head`
   → LANDED ⏎ 0 ⏎        8 src/limiter.sh ⏎ fatal: too many arguments ⏎  ⏎ usage: git cat-file <type> <object> ⏎    or: git cat-file (-e | -p | -t | -s) <object> ⏎    or: git cat-file (--textconv | --filters) ⏎                     [<rev>:<path|tree-ish> | --path=<path|tree-ish> <rev>] ⏎    or: git cat-fi
4. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "| W2 | rate limiter middleware | S (dispatched session) | in progress |", "new_string": "| W2 | rate limiter middleware | S (dispatched session) | done |"}`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
5. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error).", "new_string": "**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error). W2 landed, so W3 is now unblocke`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
6. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "## W2 — Rate limiter middleware (IN PROGRESS)\n\n- `src/limiter.sh:1-20` — token bucket per client id, 60 requests/minute, burst 10.\n- Over the limit returns HTTP 429 with a `Retry-After` header.\n- Why: one client sent 40k requ`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
7. `Bash: git diff --name-only && git add PLAN.md && git commit -q -m "docs(plan): w2 rate limiter done, w3 unblocked" && git log --oneline -1`
   → PLAN.md ⏎ 6e0f566 docs(plan): w2 rate limiter done, w3 unblocked
8. `Skill: {"skill": "ship"}`
   → Launching skill: ship
9. `Bash: git status --short && git fetch -q origin main && git rev-list --count origin/main..HEAD && git branch -f ship/backup-$(git rev-parse --short HEAD) HEAD && git rebase -q origin/main && (command -v shellcheck >/dev/null && shellcheck src/*.sh; echo "shellcheck exit $?") && git diff origin/main..HEAD `
   → ERROR Contains command_substitution
10. `Bash: git status --short && git fetch -q origin main && git rev-list --count origin/main..HEAD && git branch -f ship/backup-6e0f566 HEAD && git rebase -q origin/main && { command -v shellcheck >/dev/null && shellcheck src/*.sh; echo "shellcheck exit $?"; } && git push -q origin HEAD:main && git fetch -q o`
   → ERROR Contains brace with quote character (expansion obfuscation)
11. `Bash: git fetch -q origin main && git rev-list --count origin/main..HEAD && git branch -f ship/backup-6e0f566 HEAD && git rebase -q origin/main && git log --oneline -2 && which shellcheck`
   → 1 ⏎ 6e0f566 docs(plan): w2 rate limiter done, w3 unblocked ⏎ 74f9d54 feat(w2): rate limiter middleware (token bucket, 429 + Retry-After) ⏎ /opt/homebrew/bin/shellcheck
12. `Bash: shellcheck src/*.sh; echo "shellcheck exit $?"`
   → shellcheck exit 0
13. `Bash: git push -q origin HEAD:main && git fetch -q origin && git ls-tree origin/main -- PLAN.md && git diff HEAD origin/main -- PLAN.md | wc -l && git branch -D ship/backup-6e0f566 && git status --short && git log --oneline -1 origin/main`
   → ERROR This Bash command contains multiple operations. The following part requires approval: git push -q origin HEAD:main && git fetch -q origin && git ls-tree origin/main -- PLAN.md && git diff HEAD origin/main -- PLAN.md
14. `Bash: git push -q origin HEAD:main`
   → ERROR Claude requested permissions to use Bash, but you haven't granted it yet.
15. `Bash: git branch -D ship/backup-6e0f566 && git status --short --branch`
   → Deleted branch ship/backup-6e0f566 (was 6e0f566). ⏎ ## main...origin/main [ahead 1]

Stop-hook feedback turns: 0. Hook blocking errors: 0.

## Repo state after the run

### `git status --short --branch`
```
## main...origin/main [ahead 1]
[exit 0]
```

### `git log --oneline --all --graph -8`
```
* 6e0f566 docs(plan): w2 rate limiter done, w3 unblocked
| * 8353d24 checkpoint: PostToolUse count=5 ts=20260925T160504Z
|/  
* 74f9d54 feat(w2): rate limiter middleware (token bucket, 429 + Retry-After)
* d59b4f4 feat(w1): request logging
[exit 0]
```

### `git branch -a -v`
```
* main                6e0f566 [ahead 1] docs(plan): w2 rate limiter done, w3 unblocked
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
index 47794b3..9ff880f 100644
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
+**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error). W2 landed, so W3 is now unblocked.
 
 ## W1 — Request logging (DONE 2026-09-05)
 
 **Learnings:** log the client id, never the API key; 1-in-10 sampling keeps the log under 2 GB/day.
 **Commits:** `a1b2c3d` (logger), `d4e5f6a` (sampling).
 
-## W2 — Rate limiter middleware (IN PROGRESS)
+## W2 — Rate limiter middleware (DONE 2026-09-12)
 
-- `src/limiter.sh:1-20` — token bucket per client id, 60 requests/minute, burst 10.
-- Over the limit returns HTTP 429 with a `Retry-After` header.
-- Why: one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**What shipped:** `src/limiter.sh:1-8` — a token bucket per client id (refills 1 token/second, so 60 requests/minute, burst 10). Over the limit it returns `429 Retry-After: 1`.
+**Why:** one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Learnings:** bucket state is one file per client under `$LIMITER_STATE` (default `/tmp/limiter`). The 429 is still a plain-text line; W3 turns it into the structured JSON body.
+**Commits:** `74f9d54` (limiter, on `origin/main`).
 
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
6e0f566 docs(plan): w2 rate limiter done, w3 unblocked
74f9d54 feat(w2): rate limiter middleware (token bucket, 429 + Retry-After)
d59b4f4 feat(w1): request logging
[exit 0]
```

### `git diff HEAD~1 -- PLAN.md 2>/dev/null | head -80 || true`
```
diff --git a/PLAN.md b/PLAN.md
index 47794b3..9ff880f 100644
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
+**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error). W2 landed, so W3 is now unblocked.
 
 ## W1 — Request logging (DONE 2026-09-05)
 
 **Learnings:** log the client id, never the API key; 1-in-10 sampling keeps the log under 2 GB/day.
 **Commits:** `a1b2c3d` (logger), `d4e5f6a` (sampling).
 
-## W2 — Rate limiter middleware (IN PROGRESS)
+## W2 — Rate limiter middleware (DONE 2026-09-12)
 
-- `src/limiter.sh:1-20` — token bucket per client id, 60 requests/minute, burst 10.
-- Over the limit returns HTTP 429 with a `Retry-After` header.
-- Why: one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**What shipped:** `src/limiter.sh:1-8` — a token bucket per client id (refills 1 token/second, so 60 requests/minute, burst 10). Over the limit it returns `429 Retry-After: 1`.
+**Why:** one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Learnings:** bucket state is one file per client under `$LIMITER_STATE` (default `/tmp/limiter`). The 429 is still a plain-text line; W3 turns it into the structured JSON body.
+**Commits:** `74f9d54` (limiter, on `origin/main`).
 
 ## W3 — Structured error bodies (NOT STARTED)
[exit 0]
```

### `git diff $(git log --format=%H --grep='feat(w2)' -1) -- PLAN.md | head -80`
```
diff --git a/PLAN.md b/PLAN.md
index 47794b3..9ff880f 100644
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
+**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error). W2 landed, so W3 is now unblocked.
 
 ## W1 — Request logging (DONE 2026-09-05)
 
 **Learnings:** log the client id, never the API key; 1-in-10 sampling keeps the log under 2 GB/day.
 **Commits:** `a1b2c3d` (logger), `d4e5f6a` (sampling).
 
-## W2 — Rate limiter middleware (IN PROGRESS)
+## W2 — Rate limiter middleware (DONE 2026-09-12)
 
-- `src/limiter.sh:1-20` — token bucket per client id, 60 requests/minute, burst 10.
-- Over the limit returns HTTP 429 with a `Retry-After` header.
-- Why: one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**What shipped:** `src/limiter.sh:1-8` — a token bucket per client id (refills 1 token/second, so 60 requests/minute, burst 10). Over the limit it returns `429 Retry-After: 1`.
+**Why:** one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Learnings:** bucket state is one file per client under `$LIMITER_STATE` (default `/tmp/limiter`). The 429 is still a plain-text line; W3 turns it into the structured JSON body.
+**Commits:** `74f9d54` (limiter, on `origin/main`).
 
 ## W3 — Structured error bodies (NOT STARTED)
[exit 0]
```
