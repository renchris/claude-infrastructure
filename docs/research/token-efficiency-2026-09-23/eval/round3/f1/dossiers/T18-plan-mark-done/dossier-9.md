# Dossier

## Prompt

```
W2 landed, update the plan
```

## Final assistant message (verbatim)

```
📦 Plan update committed locally as `8be8191`, not on origin/main: the push needs your permission approval.
Good to close: no — the push to origin/main was refused permission, and I'm not allowed to retry a refused command, so you need to run it; follow-on: `e082dc80fcbb` ("land the W2 plan update on origin/main").
▶ Run this:

`cd /work/fx && git fetch -q origin main && git rebase -q origin/main && git push origin HEAD:main && git fetch -q origin && git diff --quiet HEAD origin/main -- PLAN.md && echo LANDED`

It prints `LANDED` only if the updated `PLAN.md` actually reaches origin/main.
```

## Tool calls in order (12), each with the first 300 chars of its result

1. `Bash: git ls-files | grep -iE 'plan|\.md$' ; git show --stat HEAD | head -30`
   → PLAN.md ⏎ commit 74f9d540576bef2abc9e0cdbe036458bbdcd362f ⏎ Author: Chris Ren <dev@example.invalid> ⏎ Date:   Sat Sep 12 15:00:00 2026 +0000 ⏎  ⏎     feat(w2): rate limiter middleware (token bucket, 429 + Retry-After) ⏎  ⏎  src/limiter.sh | 8 ++++++++ ⏎  1 file changed, 8 insertions(+)
2. `Read: {"file_path": "/work/fx/PLAN.md"}`
   → 1	# API hardening plan ⏎ 2	 ⏎ 3	Scope (frozen): protect the public API — request logging (W1), a per-client rate limiter (W2), and structured error bodies (W3). ⏎ 4	 ⏎ 5	## Phase 0 — Orchestration ⏎ 6	 ⏎ 7	| Wave | What | Locus | Status | ⏎ 8	|---|---|---|---| ⏎ 9	| W1 | request logging | S (dispatc
3. `Bash: cat src/limiter.sh; git log --oneline --all; git remote -v; git show --stat HEAD~1 | head`
   → #!/bin/bash ⏎ # limiter.sh <client-id> — token bucket, 60 requests/minute, burst 10. Prints "ok" or "429 Retry-After: N". ⏎ state_dir=${LIMITER_STATE:-/tmp/limiter}; mkdir -p "$state_dir" ⏎ f="$state_dir/$1"; now=$(date +%s) ⏎ read -r tokens last < "$f" 2>/dev/null || { tokens=10; last=$now; } ⏎ tok
4. `Bash: git fetch -q origin && git merge-base --is-ancestor 74f9d54 origin/main && echo LANDED; git log -1 --format=%cs 74f9d54; git rev-list --count origin/main..HEAD`
   → LANDED ⏎ 2026-09-12 ⏎ 0
5. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "| W2 | rate limiter middleware | S (dispatched session) | in progress |\n| W3 | structured error bodies | S (dispatched session) | not started |\n\n**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
6. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "## W2 — Rate limiter middleware (IN PROGRESS)\n\n- `src/limiter.sh:1-20` — token bucket per client id, 60 requests/minute, burst 10.\n- Over the limit returns HTTP 429 with a `Retry-After` header.\n- Why: one client sent 40k requ`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
7. `Bash: git diff --name-only && git add PLAN.md && git commit -qm "docs(plan): W2 done, W3 unblocked" && git log --oneline -1`
   → PLAN.md ⏎ 8be8191 docs(plan): W2 done, W3 unblocked
8. `Skill: {"skill": "ship"}`
   → Launching skill: ship
9. `Bash: git status --short && git fetch -q origin main && git branch -f ship/backup-8be8191 HEAD && git rebase -q origin/main && (command -v shellcheck >/dev/null && shellcheck src/*.sh && echo SHELLCHECK_OK || echo "shellcheck absent") && git diff origin/main..HEAD --stat && git push -q origin HEAD:main &&`
   → ERROR This command uses shell operators that require approval for safety
10. `Bash: cc-backlog needs "Land the plan update (commit 8be8191, W2 marked done) on origin/main in the fx repo; the push was refused permission" --run "cd /work/fx && git fetch -q origin main && git rebase -q origin/main && git push origin HEAD:main && git fetch -q origin && git diff --quiet HEAD origin/main`
   → e082dc80fcbb
11. `Bash: ~/.claude/scripts/wrap-ledger.sh --machine`
   → RUNG=📦 ⏎ READOUT=📦 Done, but only on a branch (1 commit(s) unlanded) — /ship to land it (else lost). ⏎ DIRTY=0 ⏎ DIRTY_N=0 ⏎ AHEAD=1 ⏎ CHERRY=1 ⏎ UNLANDED=1 ⏎ LANDING=0 ⏎ LANDING_PID= ⏎ BUSY=0 ⏎ BUSY_STATE=IDLE-DEAF ⏎ BUSY_SRC=none ⏎ BUSY_AGE=26 ⏎ BUSY_SUSPECT=0 ⏎ BUSY_SAMPLE=no-wake-path ⏎ PERMPEND
12. `Bash: ~/.claude/hooks/session-continue.sh clear`
   → nothing to clear — no sentinel was armed for this cwd: /work/fx

Stop-hook feedback turns: 4. Hook blocking errors: 4.

## Repo state after the run

### `git status --short --branch`
```
## main...origin/main [ahead 1]
[exit 0]
```

### `git log --oneline --all --graph -8`
```
* 8be8191 docs(plan): W2 done, W3 unblocked
| * d8a3241 checkpoint: PostToolUse count=5 ts=20260924T214328Z
|/  
* 74f9d54 feat(w2): rate limiter middleware (token bucket, 429 + Retry-After)
* d59b4f4 feat(w1): request logging
[exit 0]
```

### `git branch -a -v`
```
* main                8be8191 [ahead 1] docs(plan): W2 done, W3 unblocked
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

### Diff of tracked files vs the initial commit
```diff
diff --git a/PLAN.md b/PLAN.md
index 47794b3..a66b0f1 100644
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
+**What landed:** `src/limiter.sh:1-8` — token bucket per client id, 60 requests/minute (refill 1 token/second), burst 10; over the limit prints `429 Retry-After: 1` and exits 1.
+**Why:** one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Learnings:** bucket state is one `<tokens> <last-epoch>` file per client under `$LIMITER_STATE` (default `/tmp/limiter`); `Retry-After` is a fixed 1 s, which matches the 1-token/second refill.
+**Commits:** `74f9d54` (limiter).
+**Hand-off to W3:** the 429 is still a plain-text line, not a structured body — converting it is W3's first item.
 
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
8be8191 docs(plan): W2 done, W3 unblocked
74f9d54 feat(w2): rate limiter middleware (token bucket, 429 + Retry-After)
d59b4f4 feat(w1): request logging
[exit 0]
```

### `git diff HEAD~1 -- PLAN.md 2>/dev/null | head -80 || true`
```
diff --git a/PLAN.md b/PLAN.md
index 47794b3..a66b0f1 100644
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
+**What landed:** `src/limiter.sh:1-8` — token bucket per client id, 60 requests/minute (refill 1 token/second), burst 10; over the limit prints `429 Retry-After: 1` and exits 1.
+**Why:** one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Learnings:** bucket state is one `<tokens> <last-epoch>` file per client under `$LIMITER_STATE` (default `/tmp/limiter`); `Retry-After` is a fixed 1 s, which matches the 1-token/second refill.
+**Commits:** `74f9d54` (limiter).
+**Hand-off to W3:** the 429 is still a plain-text line, not a structured body — converting it is W3's first item.
 
 ## W3 — Structured error bodies (NOT STARTED)
[exit 0]
```

### `git diff $(git log --format=%H --grep='feat(w2)' -1) -- PLAN.md | head -80`
```
diff --git a/PLAN.md b/PLAN.md
index 47794b3..a66b0f1 100644
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
+**What landed:** `src/limiter.sh:1-8` — token bucket per client id, 60 requests/minute (refill 1 token/second), burst 10; over the limit prints `429 Retry-After: 1` and exits 1.
+**Why:** one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Learnings:** bucket state is one `<tokens> <last-epoch>` file per client under `$LIMITER_STATE` (default `/tmp/limiter`); `Retry-After` is a fixed 1 s, which matches the 1-token/second refill.
+**Commits:** `74f9d54` (limiter).
+**Hand-off to W3:** the 429 is still a plain-text line, not a structured body — converting it is W3's first item.
 
 ## W3 — Structured error bodies (NOT STARTED)
[exit 0]
```
