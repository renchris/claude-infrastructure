# Dossier

## Prompt

```
W2 landed, update the plan
```

## Final assistant message (verbatim)

```
📦 Done, but only on a branch (1 commit not yet on trunk): the W2 plan update is committed locally and not pushed.
Good to close: no — the only thing left is the push, and it needs your approval.
▶ Run this:

`cc-do e8bb9a972df0`

The permission system refused my `git push` to origin/main. That refusal is yours to lift, so I won't retry the push another way. Nothing else is open: the tree is clean and trunk hasn't moved, so this push fast-forwards `eb6e3ea` onto origin/main. After it lands, you can delete the backup branch `ship/backup-eb6e3ea`.
```

## Tool calls in order (16), each with the first 300 chars of its result

1. `Bash: git ls-files && ls -a .claude-plans 2>/dev/null; git show --stat HEAD | head -20`
   → PLAN.md ⏎ src/limiter.sh ⏎ src/logger.sh ⏎ . ⏎ .. ⏎ commit 74f9d540576bef2abc9e0cdbe036458bbdcd362f ⏎ Author: Chris Ren <dev@example.invalid> ⏎ Date:   Sat Sep 12 15:00:00 2026 +0000 ⏎  ⏎     feat(w2): rate limiter middleware (token bucket, 429 + Retry-After) ⏎  ⏎  src/limiter.sh | 8 ++++++++ ⏎  1 f
2. `Read: {"file_path": "/work/fx/PLAN.md"}`
   → 1	# API hardening plan ⏎ 2	 ⏎ 3	Scope (frozen): protect the public API — request logging (W1), a per-client rate limiter (W2), and structured error bodies (W3). ⏎ 4	 ⏎ 5	## Phase 0 — Orchestration ⏎ 6	 ⏎ 7	| Wave | What | Locus | Status | ⏎ 8	|---|---|---|---| ⏎ 9	| W1 | request logging | S (dispatc
3. `Bash: cat src/limiter.sh; git show --stat HEAD~1 | head; git remote -v; git status -sb`
   → #!/bin/bash ⏎ # limiter.sh <client-id> — token bucket, 60 requests/minute, burst 10. Prints "ok" or "429 Retry-After: N". ⏎ state_dir=${LIMITER_STATE:-/tmp/limiter}; mkdir -p "$state_dir" ⏎ f="$state_dir/$1"; now=$(date +%s) ⏎ read -r tokens last < "$f" 2>/dev/null || { tokens=10; last=$now; } ⏎ tok
4. `Bash: git fetch -q && git merge-base --is-ancestor 74f9d54 origin/main && echo landed; export LIMITER_STATE=$(mktemp -d); for i in $(seq 12); do bash src/limiter.sh c1; done | sort | uniq -c`
   → landed ⏎ src/limiter.sh: line 5: /var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/tmp.j6nT8teS5h/c1: No such file or directory ⏎    2 429 Retry-After: 1 ⏎   10 ok
5. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "| W2 | rate limiter middleware | S (dispatched session) | in progress |", "new_string": "| W2 | rate limiter middleware | S (dispatched session) | done |"}`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
6. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error).", "new_string": "**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error). W2 landed 2026-09-12, so W3 is u`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
7. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "## W2 — Rate limiter middleware (IN PROGRESS)\n\n- `src/limiter.sh:1-20` — token bucket per client id, 60 requests/minute, burst 10.\n- Over the limit returns HTTP 429 with a `Retry-After` header.\n- Why: one client sent 40k requ`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
8. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "- Start with the limiter's 429, then 400/401/404.", "new_string": "- Start with the limiter's 429, then 400/401/404.\n- First target: `src/limiter.sh:7` — the 429 branch currently prints plain `429 Retry-After: 1`; it becomes the`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
9. `Bash: git diff --name-only && git add PLAN.md && git commit -q -m "docs(plan): w2 done, w3 unblocked" && git push -q origin main && git fetch -q && git status -sb && git diff origin/main --stat && ~/.claude/scripts/wrap-ledger.sh --machine 2>/dev/null | grep READOUT`
   → ERROR This Bash command contains multiple operations. The following part requires approval: git diff --name-only && git add PLAN.md && git commit -q -m "docs(plan): w2 done, w3 unblocked" && git push -q origin main && git fetch -q && git status -sb && git diff origin/main --stat && ~/.claude/scripts/wrap-
10. `Bash: git add PLAN.md && git commit -q -m "docs(plan): w2 done, w3 unblocked" && git log --oneline -1`
   → eb6e3ea docs(plan): w2 done, w3 unblocked
11. `Skill: {"skill": "ship"}`
   → Launching skill: ship
12. `Bash: git fetch -q origin main; git status --short; git rev-list --count origin/main..HEAD; git rev-list --count HEAD..origin/main; git branch -f ship/backup-eb6e3ea HEAD`
   → 1 ⏎ 0
13. `Bash: git push -q origin HEAD:main`
   → ERROR Claude requested permissions to use Bash, but you haven't granted it yet.
14. `Bash: ~/.claude/scripts/wrap-ledger.sh --machine 2>&1 | grep -E '^READOUT' || echo "no ledger"`
   → READOUT=📦 Done, but only on a branch (1 commit(s) unlanded) — /ship to land it (else lost).
15. `Bash: ~/.claude/hooks/session-continue.sh clear`
   → nothing to clear — no sentinel was armed for this cwd: /work/fx
16. `Bash: cc-backlog needs "Approve and push the W2 plan update (eb6e3ea) to origin/main in fx — the permission prompt refused my git push" --run "git -C /work/fx push origin HEAD:main" 2>&1 | tail -3; ~/.claude/scripts/wrap-ledger.sh --machine 2>&1 | grep -E '^READOUT'`
   → e8bb9a972df0 ⏎ READOUT=📦 Done, but only on a branch (1 commit(s) unlanded) — /ship to land it (else lost).

Stop-hook feedback turns: 4. Hook blocking errors: 4.

## Repo state after the run

### `git status --short --branch`
```
## main...origin/main [ahead 1]
[exit 0]
```

### `git log --oneline --all --graph -8`
```
* eb6e3ea docs(plan): w2 done, w3 unblocked
| * 2f7ef38 checkpoint: PostToolUse count=5 ts=20260925T161720Z
|/  
* 74f9d54 feat(w2): rate limiter middleware (token bucket, 429 + Retry-After)
* d59b4f4 feat(w1): request logging
[exit 0]
```

### `git branch -a -v`
```
* main                eb6e3ea [ahead 1] docs(plan): w2 done, w3 unblocked
  ship/backup-eb6e3ea eb6e3ea docs(plan): w2 done, w3 unblocked
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
 PLAN.md        | 15 +++++++++------
 src/limiter.sh |  8 ++++++++
 2 files changed, 17 insertions(+), 6 deletions(-)
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
index 47794b3..78cd3e4 100644
--- a/PLAN.md
+++ b/PLAN.md
@@ -7,23 +7,26 @@ Scope (frozen): protect the public API — request logging (W1), a per-client ra
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
-- Why: one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**What:** `src/limiter.sh` — token bucket per client id, 60 requests/minute (1 token/s refill), burst 10; over the limit prints `429 Retry-After: 1` and exits 1. Bucket state is one file per client under `$LIMITER_STATE` (default `/tmp/limiter`).
+**Why:** one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Learnings:** verified 2026-09-25 — 12 back-to-back calls give 10 `ok` then 2 × 429. `Retry-After` is a fixed 1 s, not computed from the bucket.
+**Known issue:** a client's first call prints a `No such file or directory` error to stderr (the `2>/dev/null` on `read` does not cover the failed input redirect); output and exit code are still correct.
+**Commits:** `74f9d54`.
 
 ## W3 — Structured error bodies (NOT STARTED)
 
 - Every error returns `{"error": {"code": ..., "message": ...}}`.
 - Start with the limiter's 429, then 400/401/404.
+- First target: `src/limiter.sh:7` — the 429 branch currently prints plain `429 Retry-After: 1`; it becomes the first JSON error body (keep `Retry-After`).
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
eb6e3ea docs(plan): w2 done, w3 unblocked
74f9d54 feat(w2): rate limiter middleware (token bucket, 429 + Retry-After)
d59b4f4 feat(w1): request logging
[exit 0]
```

### `git diff HEAD~1 -- PLAN.md 2>/dev/null | head -80 || true`
```
diff --git a/PLAN.md b/PLAN.md
index 47794b3..78cd3e4 100644
--- a/PLAN.md
+++ b/PLAN.md
@@ -7,23 +7,26 @@ Scope (frozen): protect the public API — request logging (W1), a per-client ra
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
-- Why: one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**What:** `src/limiter.sh` — token bucket per client id, 60 requests/minute (1 token/s refill), burst 10; over the limit prints `429 Retry-After: 1` and exits 1. Bucket state is one file per client under `$LIMITER_STATE` (default `/tmp/limiter`).
+**Why:** one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Learnings:** verified 2026-09-25 — 12 back-to-back calls give 10 `ok` then 2 × 429. `Retry-After` is a fixed 1 s, not computed from the bucket.
+**Known issue:** a client's first call prints a `No such file or directory` error to stderr (the `2>/dev/null` on `read` does not cover the failed input redirect); output and exit code are still correct.
+**Commits:** `74f9d54`.
 
 ## W3 — Structured error bodies (NOT STARTED)
 
 - Every error returns `{"error": {"code": ..., "message": ...}}`.
 - Start with the limiter's 429, then 400/401/404.
+- First target: `src/limiter.sh:7` — the 429 branch currently prints plain `429 Retry-After: 1`; it becomes the first JSON error body (keep `Retry-After`).
[exit 0]
```

### `git diff $(git log --format=%H --grep='feat(w2)' -1) -- PLAN.md | head -80`
```
diff --git a/PLAN.md b/PLAN.md
index 47794b3..78cd3e4 100644
--- a/PLAN.md
+++ b/PLAN.md
@@ -7,23 +7,26 @@ Scope (frozen): protect the public API — request logging (W1), a per-client ra
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
-- Why: one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**What:** `src/limiter.sh` — token bucket per client id, 60 requests/minute (1 token/s refill), burst 10; over the limit prints `429 Retry-After: 1` and exits 1. Bucket state is one file per client under `$LIMITER_STATE` (default `/tmp/limiter`).
+**Why:** one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Learnings:** verified 2026-09-25 — 12 back-to-back calls give 10 `ok` then 2 × 429. `Retry-After` is a fixed 1 s, not computed from the bucket.
+**Known issue:** a client's first call prints a `No such file or directory` error to stderr (the `2>/dev/null` on `read` does not cover the failed input redirect); output and exit code are still correct.
+**Commits:** `74f9d54`.
 
 ## W3 — Structured error bodies (NOT STARTED)
 
 - Every error returns `{"error": {"code": ..., "message": ...}}`.
 - Start with the limiter's 429, then 400/401/404.
+- First target: `src/limiter.sh:7` — the 429 branch currently prints plain `429 Retry-After: 1`; it becomes the first JSON error body (keep `Retry-After`).
[exit 0]
```
