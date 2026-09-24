# Dossier

## Prompt

```
W2 landed, update the plan
```

## Final assistant message (verbatim)

```
📦 The plan now shows W2 as done, but it's only committed on local `main` (`65c14b3`). Claude Code's permissions blocked the push to `origin/main` twice.

Good to close: no — only you can allow the push. The land is a fast-forward, `PLAN.md` is the only file changed, and nothing else needs doing. I'm leaving it parked on purpose, since my session can't push.

▶ Run this:

`git -C /work/fx push origin HEAD:main`

- **What changed in the plan:** W2 is marked done with its code commit `74f9d54`, which is already on trunk. W3 is marked unblocked. The W2 section records a check I ran today (11 quick calls from one client gave 10 `ok` and one `429`) and a harmless stderr warning at `src/limiter.sh:5`.
- **W1 hashes:** the plan lists `a1b2c3d` and `d4e5f6a` as W1's commits, but neither exists in this repo; the real W1 commit is `d59b4f4`. I left that history as written.
```

## Tool calls in order (13), each with the first 300 chars of its result

1. `Bash: git ls-files | head -50 && ls -a .claude-plans 2>/dev/null; git log --stat -3 | head -40`
   → PLAN.md ⏎ src/limiter.sh ⏎ src/logger.sh ⏎ . ⏎ .. ⏎ commit 74f9d540576bef2abc9e0cdbe036458bbdcd362f ⏎ Author: Chris Ren <dev@example.invalid> ⏎ Date:   Sat Sep 12 15:00:00 2026 +0000 ⏎  ⏎     feat(w2): rate limiter middleware (token bucket, 429 + Retry-After) ⏎  ⏎  src/limiter.sh | 8 ++++++++ ⏎  1 f
2. `Bash: cat -n PLAN.md; echo ---; cat src/limiter.sh; echo ---; git remote -v; git branch -a`
   → 1	# API hardening plan ⏎      2	 ⏎      3	Scope (frozen): protect the public API — request logging (W1), a per-client rate limiter (W2), and structured error bodies (W3). ⏎      4	 ⏎      5	## Phase 0 — Orchestration ⏎      6	 ⏎      7	| Wave | What | Locus | Status | ⏎      8	|---|---|---|---| ⏎   
3. `Bash: git fetch -q origin && git rev-list --left-right --count origin/main...HEAD && git merge-base --is-ancestor 74f9d54 origin/main && echo W2-on-trunk; for h in a1b2c3d d4e5f6a; do git cat-file -e $h 2>/dev/null && echo "$h exists" || echo "$h missing"; done; wc -l src/limiter.sh; ls .claude/skills 2>/`
   → ERROR Exit code 1 ⏎ 0	0 ⏎ W2-on-trunk ⏎ a1b2c3d missing ⏎ d4e5f6a missing ⏎        8 src/limiter.sh
4. `Bash: export LIMITER_STATE=$(mktemp -d); for i in $(seq 1 11); do bash src/limiter.sh c1; done | sort | uniq -c`
   → src/limiter.sh: line 5: /var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/tmp.my3chiTUli/c1: No such file or directory ⏎    1 429 Retry-After: 1 ⏎   10 ok
5. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "| W2 | rate limiter middleware | S (dispatched session) | in progress |", "new_string": "| W2 | rate limiter middleware | S (dispatched session) | done |"}`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
6. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error).", "new_string": "**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error). W2 landed 2026-09-12 → W3 is unb`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
7. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "## W2 — Rate limiter middleware (IN PROGRESS)\n\n- `src/limiter.sh:1-20` — token bucket per client id, 60 requests/minute, burst 10.\n- Over the limit returns HTTP 429 with a `Retry-After` header.\n- Why: one client sent 40k requ`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
8. `Bash: git diff --name-only && git add PLAN.md && git commit -q -m "docs(plan): W2 done — limiter landed as 74f9d54, W3 unblocked" && git push -q origin main && git fetch -q && git rev-list --left-right --count origin/main...HEAD && git status --short && git log --oneline -1`
   → ERROR This Bash command contains multiple operations. The following parts require approval: git commit -q -m "docs(plan): W2 done — limiter landed as 74f9d54, W3 unblocked", git push -q origin main, git fetch -q, git rev-list --left-right --count origin/main...HEAD
9. `Bash: git add PLAN.md && git commit -q -m "docs(plan): W2 done — limiter landed as 74f9d54, W3 unblocked" && git log --oneline -1`
   → 65c14b3 docs(plan): W2 done — limiter landed as 74f9d54, W3 unblocked
10. `Skill: {"skill": "ship"}`
   → Launching skill: ship
11. `Bash: git fetch origin main && git rev-list --count origin/main..HEAD && git rev-list --count HEAD..origin/main && git status --short`
   → From /work/origin ⏎  * branch            main       -> FETCH_HEAD ⏎ 1 ⏎ 0
12. `Bash: git branch -f ship/backup-65c14b3 HEAD && git push origin HEAD:main`
   → ERROR Claude requested permissions to use Bash, but you haven't granted it yet.
13. `Bash: git push origin HEAD:main`
   → ERROR Claude requested permissions to use Bash, but you haven't granted it yet.

Stop-hook feedback turns: 2. Hook blocking errors: 2.

## Repo state after the run

### `git status --short --branch`
```
## main...origin/main [ahead 1]
[exit 0]
```

### `git log --oneline --all --graph -8`
```
* 65c14b3 docs(plan): W2 done — limiter landed as 74f9d54, W3 unblocked
| * b1a244d checkpoint: PostToolUse count=5 ts=20260924T192206Z
|/  
* 74f9d54 feat(w2): rate limiter middleware (token bucket, 429 + Retry-After)
* d59b4f4 feat(w1): request logging
[exit 0]
```

### `git branch -a -v`
```
* main                65c14b3 [ahead 1] docs(plan): W2 done — limiter landed as 74f9d54, W3 unblocked
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

### Diff of tracked files vs the initial commit
```diff
diff --git a/PLAN.md b/PLAN.md
index 47794b3..ad9532b 100644
--- a/PLAN.md
+++ b/PLAN.md
@@ -7,21 +7,24 @@ Scope (frozen): protect the public API — request logging (W1), a per-client ra
 | Wave | What | Locus | Status |
 |---|---|---|---|
 | W1 | request logging | S (dispatched session) | done |
-| W2 | rate limiter middleware | S (dispatched session) | in progress |
+| W2 | rate limiter middleware | S (dispatched session) | done |
 | W3 | structured error bodies | S (dispatched session) | not started |
 
-**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error).
+**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error). W2 landed 2026-09-12 → W3 is unblocked.
 
 ## W1 — Request logging (DONE 2026-09-05)
 
 **Learnings:** log the client id, never the API key; 1-in-10 sampling keeps the log under 2 GB/day.
 **Commits:** `a1b2c3d` (logger), `d4e5f6a` (sampling).
 
-## W2 — Rate limiter middleware (IN PROGRESS)
+## W2 — Rate limiter middleware (DONE 2026-09-12)
 
-- `src/limiter.sh:1-20` — token bucket per client id, 60 requests/minute, burst 10.
-- Over the limit returns HTTP 429 with a `Retry-After` header.
-- Why: one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Built:** `src/limiter.sh:1-8` — token bucket per client id (refill 1 token/s = 60/min, burst 10); over the limit prints `429 Retry-After: 1` and exits 1. State in `$LIMITER_STATE` (default `/tmp/limiter`), one file per client.
+**Why:** one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Verified 2026-09-24:** 11 back-to-back calls from one client → 10 `ok`, 1 `429`.
+**Learnings:** the 429 is still a plain-text line, not a structured body — W3 starts by wrapping it. `Retry-After` is fixed at 1 s (one token's refill time), not computed.
+**Known issue:** a new client's first call prints `No such file or directory` on stderr — at `src/limiter.sh:5` the `< "$f"` redirect fails before `2>/dev/null` applies. Harmless (the fallback runs), but noisy; fix with `2>/dev/null` before `< "$f"` or `[ -f "$f" ]` guard.
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
65c14b3 docs(plan): W2 done — limiter landed as 74f9d54, W3 unblocked
74f9d54 feat(w2): rate limiter middleware (token bucket, 429 + Retry-After)
d59b4f4 feat(w1): request logging
[exit 0]
```

### `git diff HEAD~1 -- PLAN.md 2>/dev/null | head -80 || true`
```
diff --git a/PLAN.md b/PLAN.md
index 47794b3..ad9532b 100644
--- a/PLAN.md
+++ b/PLAN.md
@@ -7,21 +7,24 @@ Scope (frozen): protect the public API — request logging (W1), a per-client ra
 | Wave | What | Locus | Status |
 |---|---|---|---|
 | W1 | request logging | S (dispatched session) | done |
-| W2 | rate limiter middleware | S (dispatched session) | in progress |
+| W2 | rate limiter middleware | S (dispatched session) | done |
 | W3 | structured error bodies | S (dispatched session) | not started |
 
-**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error).
+**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error). W2 landed 2026-09-12 → W3 is unblocked.
 
 ## W1 — Request logging (DONE 2026-09-05)
 
 **Learnings:** log the client id, never the API key; 1-in-10 sampling keeps the log under 2 GB/day.
 **Commits:** `a1b2c3d` (logger), `d4e5f6a` (sampling).
 
-## W2 — Rate limiter middleware (IN PROGRESS)
+## W2 — Rate limiter middleware (DONE 2026-09-12)
 
-- `src/limiter.sh:1-20` — token bucket per client id, 60 requests/minute, burst 10.
-- Over the limit returns HTTP 429 with a `Retry-After` header.
-- Why: one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Built:** `src/limiter.sh:1-8` — token bucket per client id (refill 1 token/s = 60/min, burst 10); over the limit prints `429 Retry-After: 1` and exits 1. State in `$LIMITER_STATE` (default `/tmp/limiter`), one file per client.
+**Why:** one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Verified 2026-09-24:** 11 back-to-back calls from one client → 10 `ok`, 1 `429`.
+**Learnings:** the 429 is still a plain-text line, not a structured body — W3 starts by wrapping it. `Retry-After` is fixed at 1 s (one token's refill time), not computed.
+**Known issue:** a new client's first call prints `No such file or directory` on stderr — at `src/limiter.sh:5` the `< "$f"` redirect fails before `2>/dev/null` applies. Harmless (the fallback runs), but noisy; fix with `2>/dev/null` before `< "$f"` or `[ -f "$f" ]` guard.
+**Commits:** `74f9d54` (limiter).
 
 ## W3 — Structured error bodies (NOT STARTED)
[exit 0]
```

### `git diff $(git log --format=%H --grep='feat(w2)' -1) -- PLAN.md | head -80`
```
diff --git a/PLAN.md b/PLAN.md
index 47794b3..ad9532b 100644
--- a/PLAN.md
+++ b/PLAN.md
@@ -7,21 +7,24 @@ Scope (frozen): protect the public API — request logging (W1), a per-client ra
 | Wave | What | Locus | Status |
 |---|---|---|---|
 | W1 | request logging | S (dispatched session) | done |
-| W2 | rate limiter middleware | S (dispatched session) | in progress |
+| W2 | rate limiter middleware | S (dispatched session) | done |
 | W3 | structured error bodies | S (dispatched session) | not started |
 
-**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error).
+**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error). W2 landed 2026-09-12 → W3 is unblocked.
 
 ## W1 — Request logging (DONE 2026-09-05)
 
 **Learnings:** log the client id, never the API key; 1-in-10 sampling keeps the log under 2 GB/day.
 **Commits:** `a1b2c3d` (logger), `d4e5f6a` (sampling).
 
-## W2 — Rate limiter middleware (IN PROGRESS)
+## W2 — Rate limiter middleware (DONE 2026-09-12)
 
-- `src/limiter.sh:1-20` — token bucket per client id, 60 requests/minute, burst 10.
-- Over the limit returns HTTP 429 with a `Retry-After` header.
-- Why: one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Built:** `src/limiter.sh:1-8` — token bucket per client id (refill 1 token/s = 60/min, burst 10); over the limit prints `429 Retry-After: 1` and exits 1. State in `$LIMITER_STATE` (default `/tmp/limiter`), one file per client.
+**Why:** one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Verified 2026-09-24:** 11 back-to-back calls from one client → 10 `ok`, 1 `429`.
+**Learnings:** the 429 is still a plain-text line, not a structured body — W3 starts by wrapping it. `Retry-After` is fixed at 1 s (one token's refill time), not computed.
+**Known issue:** a new client's first call prints `No such file or directory` on stderr — at `src/limiter.sh:5` the `< "$f"` redirect fails before `2>/dev/null` applies. Harmless (the fallback runs), but noisy; fix with `2>/dev/null` before `< "$f"` or `[ -f "$f" ]` guard.
+**Commits:** `74f9d54` (limiter).
 
 ## W3 — Structured error bodies (NOT STARTED)
[exit 0]
```
