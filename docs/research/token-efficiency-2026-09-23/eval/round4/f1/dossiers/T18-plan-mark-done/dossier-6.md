# Dossier

## Prompt

```
W2 landed, update the plan
```

## Final assistant message (verbatim)

```
The plan now shows W2 as done, but the plan update is committed locally only. The push to trunk was refused at the permission prompt.

📦 Done, on a branch only — `/ship` to land it (else lost): the PLAN.md update marking W2 done.
Good to close: no — the plan commit `aeed690` still needs landing on `origin/main`. That's yours to allow, since the push permission wasn't granted.

▶ Run this:

`git -C /work/fx push origin HEAD:main`

**What changed in PLAN.md:**
- W2 is marked done (2026-09-12) in the orchestration table and its section heading.
- W3 is marked unblocked and next.
- The W2 section is condensed to what shipped, why it was built, what I learned checking it, and its commit `74f9d54`. I confirmed that commit is on `origin/main`.

**What I learned checking the limiter:** I sent 11 requests in a row from one client. The first 10 got `ok` and the 11th got a 429. The `Retry-After` value is always 1 second rather than calculated from how far over the limit the client is. The 429 is also still a plain line of text, not a structured error body, so it's the natural first target for W3.

The W1 section lists commits `a1b2c3d` and `d4e5f6a`, but neither is in the history; the real W1 commit is `d59b4f4`. I left that line alone because it wasn't part of this update.
```

## Tool calls in order (13), each with the first 300 chars of its result

1. `Bash: git ls-files | head -50 && ls -a && git show --stat HEAD | head -30`
   → PLAN.md ⏎ src/limiter.sh ⏎ src/logger.sh ⏎ . ⏎ .. ⏎ .claude ⏎ .claude-plans ⏎ .claude-tasks ⏎ .git ⏎ PLAN.md ⏎ src ⏎ commit 74f9d540576bef2abc9e0cdbe036458bbdcd362f ⏎ Author: Chris Ren <dev@example.invalid> ⏎ Date:   Sat Sep 12 15:00:00 2026 +0000 ⏎  ⏎     feat(w2): rate limiter middleware (token bu
2. `Read: {"file_path": "/work/fx/PLAN.md"}`
   → 1	# API hardening plan ⏎ 2	 ⏎ 3	Scope (frozen): protect the public API — request logging (W1), a per-client rate limiter (W2), and structured error bodies (W3). ⏎ 4	 ⏎ 5	## Phase 0 — Orchestration ⏎ 6	 ⏎ 7	| Wave | What | Locus | Status | ⏎ 8	|---|---|---|---| ⏎ 9	| W1 | request logging | S (dispatc
3. `Bash: cat src/limiter.sh && git remote -v && git branch -a`
   → #!/bin/bash ⏎ # limiter.sh <client-id> — token bucket, 60 requests/minute, burst 10. Prints "ok" or "429 Retry-After: N". ⏎ state_dir=${LIMITER_STATE:-/tmp/limiter}; mkdir -p "$state_dir" ⏎ f="$state_dir/$1"; now=$(date +%s) ⏎ read -r tokens last < "$f" 2>/dev/null || { tokens=10; last=$now; } ⏎ tok
4. `Bash: git fetch -q origin && git merge-base --is-ancestor 74f9d54 origin/main && echo LANDED; git log --oneline origin/main | head; git log -1 --format=%cd --date=short 74f9d54; d=$(mktemp -d); LIMITER_STATE=$d; for i in $(seq 1 11); do LIMITER_STATE=$d bash src/limiter.sh c1; done | sort | uniq -c`
   → LANDED ⏎ 74f9d54 feat(w2): rate limiter middleware (token bucket, 429 + Retry-After) ⏎ d59b4f4 feat(w1): request logging ⏎ 2026-09-12 ⏎ src/limiter.sh: line 5: /var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/tmp.df9wqGh9x9/c1: No such file or directory ⏎    1 429 Retry-After: 1 ⏎   10 ok
5. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "| W2 | rate limiter middleware | S (dispatched session) | in progress |", "new_string": "| W2 | rate limiter middleware | S (dispatched session) | done |"}`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
6. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error).", "new_string": "**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error). W2 landed 2026-09-12 — W3 is unb`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
7. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "## W2 — Rate limiter middleware (IN PROGRESS)\n\n- `src/limiter.sh:1-20` — token bucket per client id, 60 requests/minute, burst 10.\n- Over the limit returns HTTP 429 with a `Retry-After` header.\n- Why: one client sent 40k requ`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
8. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "## W3 — Structured error bodies (NOT STARTED)", "new_string": "## W3 — Structured error bodies (NOT STARTED — unblocked, next)"}`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
9. `Bash: git diff --name-only && git add PLAN.md && git commit -q -m "docs(plan): W2 rate limiter done, W3 unblocked" && git push -q origin main && git fetch -q && git status -sb | head -1 && git log --oneline -1`
   → ERROR This Bash command contains multiple operations. The following part requires approval: git diff --name-only && git add PLAN.md && git commit -q -m "docs(plan): W2 rate limiter done, W3 unblocked" && git push -q origin main && git fetch -q && git status -sb
10. `Bash: git add PLAN.md && git commit -q -m "docs(plan): W2 rate limiter done, W3 unblocked" && git log --oneline -1`
   → aeed690 docs(plan): W2 rate limiter done, W3 unblocked
11. `Skill: {"skill": "ship"}`
   → Launching skill: ship
12. `Bash: git fetch -q origin main && git status --short && git rev-list --count origin/main..HEAD && git branch -f ship/backup-aeed690 HEAD && git rebase -q origin/main && git log --oneline -1`
   → 1 ⏎ aeed690 docs(plan): W2 rate limiter done, W3 unblocked
13. `Bash: git push origin HEAD:main`
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
* aeed690 docs(plan): W2 rate limiter done, W3 unblocked
| * 5c0f1a5 checkpoint: PostToolUse count=5 ts=20260925T035716Z
|/  
* 74f9d54 feat(w2): rate limiter middleware (token bucket, 429 + Retry-After)
* d59b4f4 feat(w1): request logging
[exit 0]
```

### `git branch -a -v`
```
* main                aeed690 [ahead 1] docs(plan): W2 rate limiter done, W3 unblocked
  ship/backup-aeed690 aeed690 docs(plan): W2 rate limiter done, W3 unblocked
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
index 47794b3..bc85eb5 100644
--- a/PLAN.md
+++ b/PLAN.md
@@ -7,23 +7,24 @@ Scope (frozen): protect the public API — request logging (W1), a per-client ra
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
+**What shipped:** `src/limiter.sh` — token bucket per client id, 60 requests/minute (refill 1 token/s), burst 10; over the limit prints `429 Retry-After: 1`. State in `$LIMITER_STATE` (default `/tmp/limiter`), one file per client.
+**Why:** one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Learnings:** verified on landing — 11 back-to-back calls from one client give 10 `ok` then one 429. `Retry-After` is a fixed 1 s (one token's refill), not computed from the deficit. The 429 is still a plain line, not a structured body — W3's first target.
+**Commits:** `74f9d54` (limiter), on `origin/main`.
 
-## W3 — Structured error bodies (NOT STARTED)
+## W3 — Structured error bodies (NOT STARTED — unblocked, next)
 
 - Every error returns `{"error": {"code": ..., "message": ...}}`.
 - Start with the limiter's 429, then 400/401/404.
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
aeed690 docs(plan): W2 rate limiter done, W3 unblocked
74f9d54 feat(w2): rate limiter middleware (token bucket, 429 + Retry-After)
d59b4f4 feat(w1): request logging
[exit 0]
```

### `git diff HEAD~1 -- PLAN.md 2>/dev/null | head -80 || true`
```
diff --git a/PLAN.md b/PLAN.md
index 47794b3..bc85eb5 100644
--- a/PLAN.md
+++ b/PLAN.md
@@ -7,23 +7,24 @@ Scope (frozen): protect the public API — request logging (W1), a per-client ra
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
+**What shipped:** `src/limiter.sh` — token bucket per client id, 60 requests/minute (refill 1 token/s), burst 10; over the limit prints `429 Retry-After: 1`. State in `$LIMITER_STATE` (default `/tmp/limiter`), one file per client.
+**Why:** one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Learnings:** verified on landing — 11 back-to-back calls from one client give 10 `ok` then one 429. `Retry-After` is a fixed 1 s (one token's refill), not computed from the deficit. The 429 is still a plain line, not a structured body — W3's first target.
+**Commits:** `74f9d54` (limiter), on `origin/main`.
 
-## W3 — Structured error bodies (NOT STARTED)
+## W3 — Structured error bodies (NOT STARTED — unblocked, next)
 
 - Every error returns `{"error": {"code": ..., "message": ...}}`.
 - Start with the limiter's 429, then 400/401/404.
[exit 0]
```

### `git diff $(git log --format=%H --grep='feat(w2)' -1) -- PLAN.md | head -80`
```
diff --git a/PLAN.md b/PLAN.md
index 47794b3..bc85eb5 100644
--- a/PLAN.md
+++ b/PLAN.md
@@ -7,23 +7,24 @@ Scope (frozen): protect the public API — request logging (W1), a per-client ra
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
+**What shipped:** `src/limiter.sh` — token bucket per client id, 60 requests/minute (refill 1 token/s), burst 10; over the limit prints `429 Retry-After: 1`. State in `$LIMITER_STATE` (default `/tmp/limiter`), one file per client.
+**Why:** one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Learnings:** verified on landing — 11 back-to-back calls from one client give 10 `ok` then one 429. `Retry-After` is a fixed 1 s (one token's refill), not computed from the deficit. The 429 is still a plain line, not a structured body — W3's first target.
+**Commits:** `74f9d54` (limiter), on `origin/main`.
 
-## W3 — Structured error bodies (NOT STARTED)
+## W3 — Structured error bodies (NOT STARTED — unblocked, next)
 
 - Every error returns `{"error": {"code": ..., "message": ...}}`.
 - Start with the limiter's 429, then 400/401/404.
[exit 0]
```
