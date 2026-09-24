# Dossier

## Prompt

```
W2 landed, update the plan
```

## Final assistant message (verbatim)

```
📦 Done, but only on a branch (1 commit unlanded): the plan now marks W2 done; the push needs your approval.
Good to close: no. The plan commit `d048ad8` is committed locally but not on origin/main. Landing it is the step below.
▶ Run this:

`cd /work/fx && git fetch -q origin main && git rebase -q origin/main && git push -q origin HEAD:main && git fetch -q origin main && git diff --quiet HEAD origin/main -- PLAN.md && echo LANDED`

I checked that W2's limiter commit `74f9d54` is on origin/main before editing the plan. My push command was blocked pending approval, so I stopped instead of retrying it another way.

What changed in `PLAN.md`:
- **Phase 0 table:** W2 is marked done, and the note says W3 is no longer blocked.
- **W2 section:** it is now a short completed section. It keeps the reason for the limiter (a client sent 40k requests in an hour on 2026-09-02), says what shipped (60 requests a minute, burst of 10, a 429 with `Retry-After`), and records two limits of the current code:
  - Each client's count is a file under `/tmp/limiter`, so it is local to one host and resets on reboot.
  - `Retry-After` is always 1 second, not the actual wait time.

The W1 section lists commits `a1b2c3d` and `d4e5f6a`, but the only W1 commit in this repo's history is `d59b4f4`. I left that section unchanged.
```

## Tool calls in order (10), each with the first 300 chars of its result

1. `Bash: git ls-files | head -50 && git log --oneline -5 && git branch -a && git remote -v`
   → PLAN.md ⏎ src/limiter.sh ⏎ src/logger.sh ⏎ 74f9d54 feat(w2): rate limiter middleware (token bucket, 429 + Retry-After) ⏎ d59b4f4 feat(w1): request logging ⏎ * main ⏎   remotes/origin/main ⏎ origin	/work/origin.git (fetch) ⏎ origin	/work/origin.git (push)
2. `Read: {"file_path": "/work/fx/PLAN.md"}`
   → 1	# API hardening plan ⏎ 2	 ⏎ 3	Scope (frozen): protect the public API — request logging (W1), a per-client rate limiter (W2), and structured error bodies (W3). ⏎ 4	 ⏎ 5	## Phase 0 — Orchestration ⏎ 6	 ⏎ 7	| Wave | What | Locus | Status | ⏎ 8	|---|---|---|---| ⏎ 9	| W1 | request logging | S (dispatc
3. `Bash: git fetch -q && git merge-base --is-ancestor 74f9d54 origin/main && echo ON_TRUNK; git show --stat 74f9d54 | head -20; cat src/limiter.sh`
   → ON_TRUNK ⏎ commit 74f9d540576bef2abc9e0cdbe036458bbdcd362f ⏎ Author: Chris Ren <dev@example.invalid> ⏎ Date:   Sat Sep 12 15:00:00 2026 +0000 ⏎  ⏎     feat(w2): rate limiter middleware (token bucket, 429 + Retry-After) ⏎  ⏎  src/limiter.sh | 8 ++++++++ ⏎  1 file changed, 8 insertions(+) ⏎ #!/bin/bas
4. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "| W2 | rate limiter middleware | S (dispatched session) | in progress |", "new_string": "| W2 | rate limiter middleware | S (dispatched session) | done |"}`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
5. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error).", "new_string": "**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error). W2 landed 2026-09-12, so W3 is u`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
6. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "## W2 — Rate limiter middleware (IN PROGRESS)\n\n- `src/limiter.sh:1-20` — token bucket per client id, 60 requests/minute, burst 10.\n- Over the limit returns HTTP 429 with a `Retry-After` header.\n- Why: one client sent 40k requ`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
7. `Bash: git diff --name-only && git add PLAN.md && git commit -q -m "docs: mark w2 rate limiter done in plan" && git log --oneline -1`
   → PLAN.md ⏎ d048ad8 docs: mark w2 rate limiter done in plan
8. `Skill: {"skill": "ship"}`
   → Launching skill: ship
9. `Bash: git fetch -q origin main && git status --short && git branch -f ship/backup-d048ad8 HEAD && git rebase -q origin/main && (command -v shellcheck >/dev/null && shellcheck src/*.sh && echo SHELLCHECK_OK || echo "shellcheck absent") && git push -q origin HEAD:main && git fetch -q origin main && git ls-t`
   → ERROR This command uses shell operators that require approval for safety
10. `Bash: ~/.claude/scripts/wrap-ledger.sh --machine 2>&1 | grep -E '^READOUT' `
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
* d048ad8 docs: mark w2 rate limiter done in plan
| * cd945e8 checkpoint: PostToolUse count=5 ts=20260924T212952Z
|/  
* 74f9d54 feat(w2): rate limiter middleware (token bucket, 429 + Retry-After)
* d59b4f4 feat(w1): request logging
[exit 0]
```

### `git branch -a -v`
```
* main                d048ad8 [ahead 1] docs: mark w2 rate limiter done in plan
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

### Diff of tracked files vs the initial commit
```diff
diff --git a/PLAN.md b/PLAN.md
index 47794b3..6ce0525 100644
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
+**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error). W2 landed 2026-09-12, so W3 is unblocked.
 
 ## W1 — Request logging (DONE 2026-09-05)
 
 **Learnings:** log the client id, never the API key; 1-in-10 sampling keeps the log under 2 GB/day.
 **Commits:** `a1b2c3d` (logger), `d4e5f6a` (sampling).
 
-## W2 — Rate limiter middleware (IN PROGRESS)
+## W2 — Rate limiter middleware (DONE 2026-09-12)
 
-- `src/limiter.sh:1-20` — token bucket per client id, 60 requests/minute, burst 10.
-- Over the limit returns HTTP 429 with a `Retry-After` header.
-- Why: one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Why:** one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Shipped:** `src/limiter.sh:1-8` is a token bucket per client id: 60 requests/minute (it refills 1 token a second), burst 10. A client over the limit gets HTTP 429 with `Retry-After: 1`.
+**Learnings:** bucket state is one file per client under `$LIMITER_STATE` (default `/tmp/limiter`), so it is per-host and is lost on reboot. `Retry-After` is always 1s, not the real time until the next token.
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
d048ad8 docs: mark w2 rate limiter done in plan
74f9d54 feat(w2): rate limiter middleware (token bucket, 429 + Retry-After)
d59b4f4 feat(w1): request logging
[exit 0]
```

### `git diff HEAD~1 -- PLAN.md 2>/dev/null | head -80 || true`
```
diff --git a/PLAN.md b/PLAN.md
index 47794b3..6ce0525 100644
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
+**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error). W2 landed 2026-09-12, so W3 is unblocked.
 
 ## W1 — Request logging (DONE 2026-09-05)
 
 **Learnings:** log the client id, never the API key; 1-in-10 sampling keeps the log under 2 GB/day.
 **Commits:** `a1b2c3d` (logger), `d4e5f6a` (sampling).
 
-## W2 — Rate limiter middleware (IN PROGRESS)
+## W2 — Rate limiter middleware (DONE 2026-09-12)
 
-- `src/limiter.sh:1-20` — token bucket per client id, 60 requests/minute, burst 10.
-- Over the limit returns HTTP 429 with a `Retry-After` header.
-- Why: one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Why:** one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Shipped:** `src/limiter.sh:1-8` is a token bucket per client id: 60 requests/minute (it refills 1 token a second), burst 10. A client over the limit gets HTTP 429 with `Retry-After: 1`.
+**Learnings:** bucket state is one file per client under `$LIMITER_STATE` (default `/tmp/limiter`), so it is per-host and is lost on reboot. `Retry-After` is always 1s, not the real time until the next token.
+**Commits:** `74f9d54` (limiter).
 
 ## W3 — Structured error bodies (NOT STARTED)
[exit 0]
```

### `git diff $(git log --format=%H --grep='feat(w2)' -1) -- PLAN.md | head -80`
```
diff --git a/PLAN.md b/PLAN.md
index 47794b3..6ce0525 100644
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
+**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error). W2 landed 2026-09-12, so W3 is unblocked.
 
 ## W1 — Request logging (DONE 2026-09-05)
 
 **Learnings:** log the client id, never the API key; 1-in-10 sampling keeps the log under 2 GB/day.
 **Commits:** `a1b2c3d` (logger), `d4e5f6a` (sampling).
 
-## W2 — Rate limiter middleware (IN PROGRESS)
+## W2 — Rate limiter middleware (DONE 2026-09-12)
 
-- `src/limiter.sh:1-20` — token bucket per client id, 60 requests/minute, burst 10.
-- Over the limit returns HTTP 429 with a `Retry-After` header.
-- Why: one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Why:** one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Shipped:** `src/limiter.sh:1-8` is a token bucket per client id: 60 requests/minute (it refills 1 token a second), burst 10. A client over the limit gets HTTP 429 with `Retry-After: 1`.
+**Learnings:** bucket state is one file per client under `$LIMITER_STATE` (default `/tmp/limiter`), so it is per-host and is lost on reboot. `Retry-After` is always 1s, not the real time until the next token.
+**Commits:** `74f9d54` (limiter).
 
 ## W3 — Structured error bodies (NOT STARTED)
[exit 0]
```
