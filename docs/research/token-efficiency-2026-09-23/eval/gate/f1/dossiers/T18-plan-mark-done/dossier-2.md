# Dossier

## Prompt

```
W2 landed, update the plan
```

## Final assistant message (verbatim)

```
📦 The plan update is committed but not pushed (1 commit not yet on the remote). The push to origin/main was blocked at the permission prompt.
Good to close: no — the push to origin/main still needs your approval.
▶ Run this:

`git -C /work/fx push origin HEAD:main`

- **What changed in `PLAN.md`:** W2 is now marked done (2026-09-12), with a Learnings section and its commit `74f9d54`. W3 is marked unblocked. The limiter's line range is corrected to `src/limiter.sh:1-8`.
- **Checks:** `74f9d54` is on origin/main. I ran the limiter just now: 12 back-to-back calls gave 10 `ok` then two `429 Retry-After: 1`. shellcheck passes.
- **Where it is:** local commit `87d1ab9`, rebased onto the latest origin/main. A backup branch `ship/backup-87d1ab9` is there in case you need to roll back; delete it once the push lands.
```

## Tool calls in order (13), each with the first 300 chars of its result

1. `Bash: git ls-files | head -50 && git show --stat HEAD | head -20`
   → PLAN.md ⏎ src/limiter.sh ⏎ src/logger.sh ⏎ commit 74f9d540576bef2abc9e0cdbe036458bbdcd362f ⏎ Author: Chris Ren <dev@example.invalid> ⏎ Date:   Sat Sep 12 15:00:00 2026 +0000 ⏎  ⏎     feat(w2): rate limiter middleware (token bucket, 429 + Retry-After) ⏎  ⏎  src/limiter.sh | 8 ++++++++ ⏎  1 file chang
2. `Read: {"file_path": "/work/fx/PLAN.md"}`
   → 1	# API hardening plan ⏎ 2	 ⏎ 3	Scope (frozen): protect the public API — request logging (W1), a per-client rate limiter (W2), and structured error bodies (W3). ⏎ 4	 ⏎ 5	## Phase 0 — Orchestration ⏎ 6	 ⏎ 7	| Wave | What | Locus | Status | ⏎ 8	|---|---|---|---| ⏎ 9	| W1 | request logging | S (dispatc
3. `Bash: cat src/limiter.sh; git remote -v; git branch -a`
   → #!/bin/bash ⏎ # limiter.sh <client-id> — token bucket, 60 requests/minute, burst 10. Prints "ok" or "429 Retry-After: N". ⏎ state_dir=${LIMITER_STATE:-/tmp/limiter}; mkdir -p "$state_dir" ⏎ f="$state_dir/$1"; now=$(date +%s) ⏎ read -r tokens last < "$f" 2>/dev/null || { tokens=10; last=$now; } ⏎ tok
4. `Bash: git fetch -q origin && git log --oneline origin/main -5 && git merge-base --is-ancestor 74f9d54 origin/main && echo LANDED; git cat-file -t a1b2c3d d4e5f6a 2>&1; bash src/limiter.sh t1 >/dev/null; for i in $(seq 12); do LIMITER_STATE=/tmp/lim-$$ bash src/limiter.sh c; done | sort | uniq -c`
   → 74f9d54 feat(w2): rate limiter middleware (token bucket, 429 + Retry-After) ⏎ d59b4f4 feat(w1): request logging ⏎ LANDED ⏎ fatal: too many arguments ⏎  ⏎ usage: git cat-file <type> <object> ⏎    or: git cat-file (-e | -p | -t | -s) <object> ⏎    or: git cat-file (--textconv | --filters) ⏎           
5. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "| W2 | rate limiter middleware | S (dispatched session) | in progress |\n| W3 | structured error bodies | S (dispatched session) | not started |\n\n**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
6. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "## W2 — Rate limiter middleware (IN PROGRESS)\n\n- `src/limiter.sh:1-20` — token bucket per client id, 60 requests/minute, burst 10.\n- Over the limit returns HTTP 429 with a `Retry-After` header.\n- Why: one client sent 40k requ`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
7. `Bash: git diff --name-only && git add PLAN.md && git commit -q -m "docs(plan): mark w2 rate limiter done, unblock w3" && git push -q origin main && git fetch -q && git diff origin/main --stat && git log --oneline -1 && git status --short`
   → ERROR This Bash command contains multiple operations. The following parts require approval: git commit -q -m "docs(plan): mark w2 rate limiter done, unblock w3", git push -q origin main, git fetch -q
8. `Bash: git add PLAN.md && git commit -q -m "docs(plan): mark w2 rate limiter done, unblock w3" && git log --oneline -1 && git status --short`
   → 87d1ab9 docs(plan): mark w2 rate limiter done, unblock w3
9. `Skill: {"skill": "ship"}`
   → Launching skill: ship
10. `Bash: git fetch origin main && git rev-list --count origin/main..HEAD && git status --short && git branch -f ship/backup-87d1ab9 HEAD && git rebase origin/main && (command -v shellcheck >/dev/null && shellcheck src/*.sh; echo "shellcheck exit $?")`
   → From /work/origin ⏎  * branch            main       -> FETCH_HEAD ⏎ 1 ⏎ Current branch main is up to date. ⏎ shellcheck exit 0
11. `Bash: git push origin HEAD:main`
   → ERROR Claude requested permissions to use Bash, but you haven't granted it yet.
12. `Bash: ls scripts/wrap-ledger.sh ~/.claude/scripts/wrap-ledger.sh 2>&1; git status --short; git rev-list --count origin/main..HEAD`
   → ls: scripts/wrap-ledger.sh: No such file or directory ⏎ /Users/chrisren/.claude/scripts/wrap-ledger.sh ⏎ 1
13. `Bash: bash ~/.claude/scripts/wrap-ledger.sh --machine 2>&1 | grep -E '^READOUT' `
   → READOUT=📦 Done, but only on a branch (1 commit(s) unlanded) — /ship to land it (else lost).

Stop-hook feedback turns: 0. Hook blocking errors: 0.

## Repo state after the run

### `git status --short --branch`
```
## main...origin/main [ahead 1]
[exit 0]
```

### `git log --oneline --all --graph -8`
```
* 87d1ab9 docs(plan): mark w2 rate limiter done, unblock w3
| * 200c917 checkpoint: PostToolUse count=5 ts=20260924T161322Z
|/  
* 74f9d54 feat(w2): rate limiter middleware (token bucket, 429 + Retry-After)
* d59b4f4 feat(w1): request logging
[exit 0]
```

### `git branch -a -v`
```
* main                87d1ab9 [ahead 1] docs(plan): mark w2 rate limiter done, unblock w3
  ship/backup-87d1ab9 87d1ab9 docs(plan): mark w2 rate limiter done, unblock w3
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
 PLAN.md        | 13 ++++++++-----
 src/limiter.sh |  8 ++++++++
 2 files changed, 16 insertions(+), 5 deletions(-)
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
index 47794b3..e60eadb 100644
--- a/PLAN.md
+++ b/PLAN.md
@@ -7,22 +7,25 @@ Scope (frozen): protect the public API — request logging (W1), a per-client ra
 | Wave | What | Locus | Status |
 |---|---|---|---|
 | W1 | request logging | S (dispatched session) | done |
-| W2 | rate limiter middleware | S (dispatched session) | in progress |
-| W3 | structured error bodies | S (dispatched session) | not started |
+| W2 | rate limiter middleware | S (dispatched session) | done |
+| W3 | structured error bodies | S (dispatched session) | not started (unblocked) |
 
-**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error).
+**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error). W2 landed 2026-09-12, so W3 is ready to start.
 
 ## W1 — Request logging (DONE 2026-09-05)
 
 **Learnings:** log the client id, never the API key; 1-in-10 sampling keeps the log under 2 GB/day.
 **Commits:** `a1b2c3d` (logger), `d4e5f6a` (sampling).
 
-## W2 — Rate limiter middleware (IN PROGRESS)
+## W2 — Rate limiter middleware (DONE 2026-09-12)
 
-- `src/limiter.sh:1-20` — token bucket per client id, 60 requests/minute, burst 10.
+- `src/limiter.sh:1-8` — token bucket per client id, 60 requests/minute (1 token/s refill), burst 10; state in `$LIMITER_STATE` (default `/tmp/limiter`).
 - Over the limit returns HTTP 429 with a `Retry-After` header.
 - Why: one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
 
+**Learnings:** 12 back-to-back calls for one client give 10 `ok` then 2 `429 Retry-After: 1` (verified 2026-09-24). A client's first call prints a harmless "No such file" to stderr because the state file does not exist yet. The 429 is still a plain-text line, not a structured body; W3 starts there.
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
87d1ab9 docs(plan): mark w2 rate limiter done, unblock w3
74f9d54 feat(w2): rate limiter middleware (token bucket, 429 + Retry-After)
d59b4f4 feat(w1): request logging
[exit 0]
```

### `git diff HEAD~1 -- PLAN.md 2>/dev/null | head -80 || true`
```
diff --git a/PLAN.md b/PLAN.md
index 47794b3..e60eadb 100644
--- a/PLAN.md
+++ b/PLAN.md
@@ -7,22 +7,25 @@ Scope (frozen): protect the public API — request logging (W1), a per-client ra
 | Wave | What | Locus | Status |
 |---|---|---|---|
 | W1 | request logging | S (dispatched session) | done |
-| W2 | rate limiter middleware | S (dispatched session) | in progress |
-| W3 | structured error bodies | S (dispatched session) | not started |
+| W2 | rate limiter middleware | S (dispatched session) | done |
+| W3 | structured error bodies | S (dispatched session) | not started (unblocked) |
 
-**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error).
+**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error). W2 landed 2026-09-12, so W3 is ready to start.
 
 ## W1 — Request logging (DONE 2026-09-05)
 
 **Learnings:** log the client id, never the API key; 1-in-10 sampling keeps the log under 2 GB/day.
 **Commits:** `a1b2c3d` (logger), `d4e5f6a` (sampling).
 
-## W2 — Rate limiter middleware (IN PROGRESS)
+## W2 — Rate limiter middleware (DONE 2026-09-12)
 
-- `src/limiter.sh:1-20` — token bucket per client id, 60 requests/minute, burst 10.
+- `src/limiter.sh:1-8` — token bucket per client id, 60 requests/minute (1 token/s refill), burst 10; state in `$LIMITER_STATE` (default `/tmp/limiter`).
 - Over the limit returns HTTP 429 with a `Retry-After` header.
 - Why: one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
 
+**Learnings:** 12 back-to-back calls for one client give 10 `ok` then 2 `429 Retry-After: 1` (verified 2026-09-24). A client's first call prints a harmless "No such file" to stderr because the state file does not exist yet. The 429 is still a plain-text line, not a structured body; W3 starts there.
+**Commits:** `74f9d54` (limiter).
+
 ## W3 — Structured error bodies (NOT STARTED)
 
 - Every error returns `{"error": {"code": ..., "message": ...}}`.
[exit 0]
```

### `git diff $(git log --format=%H --grep='feat(w2)' -1) -- PLAN.md | head -80`
```
diff --git a/PLAN.md b/PLAN.md
index 47794b3..e60eadb 100644
--- a/PLAN.md
+++ b/PLAN.md
@@ -7,22 +7,25 @@ Scope (frozen): protect the public API — request logging (W1), a per-client ra
 | Wave | What | Locus | Status |
 |---|---|---|---|
 | W1 | request logging | S (dispatched session) | done |
-| W2 | rate limiter middleware | S (dispatched session) | in progress |
-| W3 | structured error bodies | S (dispatched session) | not started |
+| W2 | rate limiter middleware | S (dispatched session) | done |
+| W3 | structured error bodies | S (dispatched session) | not started (unblocked) |
 
-**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error).
+**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error). W2 landed 2026-09-12, so W3 is ready to start.
 
 ## W1 — Request logging (DONE 2026-09-05)
 
 **Learnings:** log the client id, never the API key; 1-in-10 sampling keeps the log under 2 GB/day.
 **Commits:** `a1b2c3d` (logger), `d4e5f6a` (sampling).
 
-## W2 — Rate limiter middleware (IN PROGRESS)
+## W2 — Rate limiter middleware (DONE 2026-09-12)
 
-- `src/limiter.sh:1-20` — token bucket per client id, 60 requests/minute, burst 10.
+- `src/limiter.sh:1-8` — token bucket per client id, 60 requests/minute (1 token/s refill), burst 10; state in `$LIMITER_STATE` (default `/tmp/limiter`).
 - Over the limit returns HTTP 429 with a `Retry-After` header.
 - Why: one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
 
+**Learnings:** 12 back-to-back calls for one client give 10 `ok` then 2 `429 Retry-After: 1` (verified 2026-09-24). A client's first call prints a harmless "No such file" to stderr because the state file does not exist yet. The 429 is still a plain-text line, not a structured body; W3 starts there.
+**Commits:** `74f9d54` (limiter).
+
 ## W3 — Structured error bodies (NOT STARTED)
 
 - Every error returns `{"error": {"code": ..., "message": ...}}`.
[exit 0]
```
