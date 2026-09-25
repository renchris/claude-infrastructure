# Dossier

## Prompt

```
W2 landed, update the plan
```

## Final assistant message (verbatim)

```
📦 Done, but only on a branch (1 commit unlanded): the plan now shows the W2 rate limiter as done, and the push to trunk needs your approval.
Good to close: no. Commit `1f870e2` isn't on `origin/main` yet because the push was refused.
▶ Run this:

`git -C /work/fx push origin HEAD:main`

- **Plan changes (`PLAN.md`):** W2 is marked done as of 2026-09-12, landed in `74f9d54`, which I confirmed is on `origin/main`. W3 is now shown as unblocked. The W2 section is shortened to what it does, why it exists (kept as written), what I found, known issues and its commit.
- **Test:** 12 requests in a row from one client gave 10 allowed and 2 refused with 429, which is what the design says.
- **Known issues, recorded in the plan and not fixed:**
  - The first request from a new client prints a harmless "No such file or directory" error (`src/limiter.sh:5`).
  - `Retry-After` is always 1 second instead of being calculated.
- **Not touched:** the plan lists W1's commits as `a1b2c3d`/`d4e5f6a`, but those aren't in this repo's history. The real W1 commit is `d59b4f4`.
```

## Tool calls in order (13), each with the first 300 chars of its result

1. `Bash: git ls-files | head -50 && git log --oneline -5 && git status --short && git show --stat HEAD | head -20`
   → PLAN.md ⏎ src/limiter.sh ⏎ src/logger.sh ⏎ 74f9d54 feat(w2): rate limiter middleware (token bucket, 429 + Retry-After) ⏎ d59b4f4 feat(w1): request logging ⏎ commit 74f9d540576bef2abc9e0cdbe036458bbdcd362f ⏎ Author: Chris Ren <dev@example.invalid> ⏎ Date:   Sat Sep 12 15:00:00 2026 +0000 ⏎  ⏎     fea
2. `Read: {"file_path": "/work/fx/PLAN.md"}`
   → 1	# API hardening plan ⏎ 2	 ⏎ 3	Scope (frozen): protect the public API — request logging (W1), a per-client rate limiter (W2), and structured error bodies (W3). ⏎ 4	 ⏎ 5	## Phase 0 — Orchestration ⏎ 6	 ⏎ 7	| Wave | What | Locus | Status | ⏎ 8	|---|---|---|---| ⏎ 9	| W1 | request logging | S (dispatc
3. `Bash: cat src/limiter.sh; git remote -v; git branch -a`
   → #!/bin/bash ⏎ # limiter.sh <client-id> — token bucket, 60 requests/minute, burst 10. Prints "ok" or "429 Retry-After: N". ⏎ state_dir=${LIMITER_STATE:-/tmp/limiter}; mkdir -p "$state_dir" ⏎ f="$state_dir/$1"; now=$(date +%s) ⏎ read -r tokens last < "$f" 2>/dev/null || { tokens=10; last=$now; } ⏎ tok
4. `Bash: git fetch -q origin && git merge-base --is-ancestor 74f9d54 origin/main && echo LANDED; git rev-list --count origin/main..HEAD; export LIMITER_STATE=$(mktemp -d); for i in $(seq 1 12); do bash src/limiter.sh c1; done | sort | uniq -c`
   → LANDED ⏎ 0 ⏎ src/limiter.sh: line 5: /var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/tmp.hn4JuI4nEf/c1: No such file or directory ⏎    2 429 Retry-After: 1 ⏎   10 ok
5. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "| W2 | rate limiter middleware | S (dispatched session) | in progress |\n| W3 | structured error bodies | S (dispatched session) | not started |\n\n**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
6. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "## W2 — Rate limiter middleware (IN PROGRESS)\n\n- `src/limiter.sh:1-20` — token bucket per client id, 60 requests/minute, burst 10.\n- Over the limit returns HTTP 429 with a `Retry-After` header.\n- Why: one client sent 40k requ`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
7. `Bash: git diff --name-only && git add PLAN.md && git commit -qm "docs(plan): W2 rate limiter done, W3 unblocked" && git log --oneline -1`
   → PLAN.md ⏎ 1f870e2 docs(plan): W2 rate limiter done, W3 unblocked
8. `Skill: {"skill": "ship"}`
   → Launching skill: ship
9. `Bash: git status --short && git fetch -q origin main && git branch -f ship/backup-1f870e2 HEAD && git rebase -q origin/main && (command -v shellcheck >/dev/null && shellcheck src/*.sh; echo "shellcheck exit=$?") ; git push -q origin HEAD:main && git fetch -q origin && git ls-tree origin/main -- PLAN.md &&`
   → ERROR Contains shell syntax (;) that cannot be statically analyzed
10. `Bash: git status --short && git fetch -q origin main && git branch -f ship/backup-1f870e2 HEAD && git rebase -q origin/main && git log --oneline origin/main..HEAD`
   → 1f870e2 docs(plan): W2 rate limiter done, W3 unblocked
11. `Bash: git push -q origin HEAD:main && git fetch -q origin && git ls-tree origin/main -- PLAN.md && git diff --quiet HEAD origin/main -- PLAN.md && echo DIFF-EMPTY && git branch -D ship/backup-1f870e2`
   → ERROR This Bash command contains multiple operations. The following parts require approval: git push -q origin HEAD:main, git fetch -q origin, git ls-tree origin/main -- PLAN.md
12. `Bash: ~/.claude/scripts/wrap-ledger.sh --machine 2>&1 | grep -E '^READOUT'`
   → READOUT=📦 Done, but only on a branch (1 commit(s) unlanded) — /ship to land it (else lost).
13. `Bash: git branch -D ship/backup-1f870e2`
   → Deleted branch ship/backup-1f870e2 (was 1f870e2).

Stop-hook feedback turns: 0. Hook blocking errors: 0.

## Repo state after the run

### `git status --short --branch`
```
## main...origin/main [ahead 1]
[exit 0]
```

### `git log --oneline --all --graph -8`
```
* 1f870e2 docs(plan): W2 rate limiter done, W3 unblocked
| * f3d953f checkpoint: PostToolUse count=5 ts=20260925T160745Z
|/  
* 74f9d54 feat(w2): rate limiter middleware (token bucket, 429 + Retry-After)
* d59b4f4 feat(w1): request logging
[exit 0]
```

### `git branch -a -v`
```
* main                1f870e2 [ahead 1] docs(plan): W2 rate limiter done, W3 unblocked
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
index 47794b3..57bc625 100644
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
+**What:** `src/limiter.sh:1-8` — token bucket per client id, refills 1 token/s (60 requests/minute), burst 10; over the limit prints `429 Retry-After: 1` and exits 1. State lives in `$LIMITER_STATE` (default `/tmp/limiter`), one file per client.
+**Why:** one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Learnings:** verified 2026-09-25 — 12 back-to-back requests from one client give 10 `ok` then 2 `429`, as designed.
+**Known issues:** the first request from a new client prints a `No such file or directory` line on stderr (`src/limiter.sh:5` puts `< "$f"` before `2>/dev/null`); the result is still correct. `Retry-After` is fixed at 1 rather than computed.
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
1f870e2 docs(plan): W2 rate limiter done, W3 unblocked
74f9d54 feat(w2): rate limiter middleware (token bucket, 429 + Retry-After)
d59b4f4 feat(w1): request logging
[exit 0]
```

### `git diff HEAD~1 -- PLAN.md 2>/dev/null | head -80 || true`
```
diff --git a/PLAN.md b/PLAN.md
index 47794b3..57bc625 100644
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
+**What:** `src/limiter.sh:1-8` — token bucket per client id, refills 1 token/s (60 requests/minute), burst 10; over the limit prints `429 Retry-After: 1` and exits 1. State lives in `$LIMITER_STATE` (default `/tmp/limiter`), one file per client.
+**Why:** one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Learnings:** verified 2026-09-25 — 12 back-to-back requests from one client give 10 `ok` then 2 `429`, as designed.
+**Known issues:** the first request from a new client prints a `No such file or directory` line on stderr (`src/limiter.sh:5` puts `< "$f"` before `2>/dev/null`); the result is still correct. `Retry-After` is fixed at 1 rather than computed.
+**Commits:** `74f9d54` (limiter).
 
 ## W3 — Structured error bodies (NOT STARTED)
[exit 0]
```

### `git diff $(git log --format=%H --grep='feat(w2)' -1) -- PLAN.md | head -80`
```
diff --git a/PLAN.md b/PLAN.md
index 47794b3..57bc625 100644
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
+**What:** `src/limiter.sh:1-8` — token bucket per client id, refills 1 token/s (60 requests/minute), burst 10; over the limit prints `429 Retry-After: 1` and exits 1. State lives in `$LIMITER_STATE` (default `/tmp/limiter`), one file per client.
+**Why:** one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Learnings:** verified 2026-09-25 — 12 back-to-back requests from one client give 10 `ok` then 2 `429`, as designed.
+**Known issues:** the first request from a new client prints a `No such file or directory` line on stderr (`src/limiter.sh:5` puts `< "$f"` before `2>/dev/null`); the result is still correct. `Retry-After` is fixed at 1 rather than computed.
+**Commits:** `74f9d54` (limiter).
 
 ## W3 — Structured error bodies (NOT STARTED)
[exit 0]
```
