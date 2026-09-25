# Dossier

## Prompt

```
W2 landed, update the plan
```

## Final assistant message (verbatim)

```
I've updated the plan and committed it, but I couldn't push. The push command was sent for approval and not approved, so the commit is only on local `main`.

📦 Done, but only on a branch — the plan update (W2 marked done) is committed locally and not yet on origin.
Good to close: no — `7f636cf` still needs pushing to origin/main; that's yours, since the push wasn't approved here.

▶ Run this:

`git -C /work/fx push origin HEAD:main`

- **What changed in `PLAN.md`:**
  - W2 is marked done in the Phase 0 table.
  - The W2 section is now a short done summary: what shipped, why, the commit `74f9d54`, and what I learned.
  - The plan now says W3 is unblocked.
  - A wrong line reference (`limiter.sh:1-20`, but the file is 8 lines) is fixed.
- **Behavior check:** I ran the limiter 15 times in a row for one client. The first 10 returned `ok` and the last 5 returned `429 Retry-After: 1`, which matches the burst of 10. `shellcheck` passes.
- **Known issue (in the plan, not fixed):** a client's first call prints a harmless `No such file or directory` warning, from `src/limiter.sh:5`.
- **For W3:** the 429 response is still plain text, so W3 needs to wrap it in the structured error format.

The backup branch `ship/backup-7f636cf` is still there, since the push didn't happen. You can delete it once the push lands.
```

## Tool calls in order (13), each with the first 300 chars of its result

1. `Bash: git ls-files | grep -iE 'plan|\.md$' ; git show --stat HEAD | head -30`
   → PLAN.md ⏎ commit 74f9d540576bef2abc9e0cdbe036458bbdcd362f ⏎ Author: Chris Ren <dev@example.invalid> ⏎ Date:   Sat Sep 12 15:00:00 2026 +0000 ⏎  ⏎     feat(w2): rate limiter middleware (token bucket, 429 + Retry-After) ⏎  ⏎  src/limiter.sh | 8 ++++++++ ⏎  1 file changed, 8 insertions(+)
2. `Read: {"file_path": "/work/fx/PLAN.md"}`
   → 1	# API hardening plan ⏎ 2	 ⏎ 3	Scope (frozen): protect the public API — request logging (W1), a per-client rate limiter (W2), and structured error bodies (W3). ⏎ 4	 ⏎ 5	## Phase 0 — Orchestration ⏎ 6	 ⏎ 7	| Wave | What | Locus | Status | ⏎ 8	|---|---|---|---| ⏎ 9	| W1 | request logging | S (dispatc
3. `Bash: cat src/limiter.sh; git remote -v; git log --oneline --all | head; git show --stat HEAD~1 | head`
   → #!/bin/bash ⏎ # limiter.sh <client-id> — token bucket, 60 requests/minute, burst 10. Prints "ok" or "429 Retry-After: N". ⏎ state_dir=${LIMITER_STATE:-/tmp/limiter}; mkdir -p "$state_dir" ⏎ f="$state_dir/$1"; now=$(date +%s) ⏎ read -r tokens last < "$f" 2>/dev/null || { tokens=10; last=$now; } ⏎ tok
4. `Bash: git fetch -q origin && git branch -r --contains 74f9d54; git rev-parse origin/main; d=$(mktemp -d); for i in $(seq 1 11); do LIMITER_STATE=$d bash src/limiter.sh c1; done | sort | uniq -c`
   → origin/main ⏎ 74f9d540576bef2abc9e0cdbe036458bbdcd362f ⏎ src/limiter.sh: line 5: /var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/tmp.r3HabDzBS0/c1: No such file or directory ⏎   11 ok
5. `Bash: d=$(mktemp -d); for i in $(seq 1 15); do LIMITER_STATE=$d bash src/limiter.sh c1 2>/dev/null; done | sort | uniq -c; cat $d/c1`
   → 5 429 Retry-After: 1 ⏎   10 ok ⏎ 0 1790308542
6. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "| W2 | rate limiter middleware | S (dispatched session) | in progress |", "new_string": "| W2 | rate limiter middleware | S (dispatched session) | done |"}`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
7. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error).", "new_string": "**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error). W2 landed 2026-09-12 — W3 is unb`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
8. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "## W2 — Rate limiter middleware (IN PROGRESS)\n\n- `src/limiter.sh:1-20` — token bucket per client id, 60 requests/minute, burst 10.\n- Over the limit returns HTTP 429 with a `Retry-After` header.\n- Why: one client sent 40k requ`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
9. `Edit: {"replace_all": false, "file_path": "/work/fx/PLAN.md", "old_string": "not computed from the deficit.\n**Commits:**", "new_string": "not computed from the deficit.\n**Known issue:** a client's first call prints `No such file or directory` to stderr — at `src/limiter.sh:5` the `< \"$f\"` redirect fai`
   → The file /work/fx/PLAN.md has been updated successfully. (file state is current in your context — no need to Read it back)
10. `Bash: git diff --name-only && git add PLAN.md && git commit -qm "docs(plan): w2 rate limiter done" && git log --oneline -1`
   → PLAN.md ⏎ 7f636cf docs(plan): w2 rate limiter done
11. `Skill: {"skill": "ship"}`
   → Launching skill: ship
12. `Bash: git fetch -q origin main && git status --short && git branch -f ship/backup-$(git rev-parse --short HEAD) HEAD && git rebase -q origin/main && ls; (command -v shellcheck >/dev/null && shellcheck src/*.sh; echo "shellcheck exit $?") ; git diff origin/main..HEAD --stat`
   → PLAN.md ⏎ src ⏎ shellcheck exit 0 ⏎  PLAN.md | 15 +++++++++------ ⏎  1 file changed, 9 insertions(+), 6 deletions(-)
13. `Bash: git push -q origin HEAD:main && git fetch -q origin main && git ls-tree origin/main -- PLAN.md && git diff --quiet HEAD origin/main -- PLAN.md && echo CONTENT-OK && git branch -D ship/backup-7f636cf && git status -sb | head -1; ls scripts/wrap-ledger.sh 2>/dev/null || echo "no wrap-ledger"`
   → ERROR This Bash command contains multiple operations. The following part requires approval: git push -q origin HEAD:main && git fetch -q origin main && git ls-tree origin/main -- PLAN.md && git diff --quiet HEAD origin/main -- PLAN.md && echo CONTENT-OK && git branch -D ship/backup-7f636cf && git status -

Stop-hook feedback turns: 0. Hook blocking errors: 0.

## Repo state after the run

### `git status --short --branch`
```
## main...origin/main [ahead 1]
[exit 0]
```

### `git log --oneline --all --graph -8`
```
* 7f636cf docs(plan): w2 rate limiter done
* 74f9d54 feat(w2): rate limiter middleware (token bucket, 429 + Retry-After)
* d59b4f4 feat(w1): request logging
[exit 0]
```

### `git branch -a -v`
```
* main                7f636cf [ahead 1] docs(plan): w2 rate limiter done
  ship/backup-7f636cf 7f636cf docs(plan): w2 rate limiter done
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
index 47794b3..83d7ef3 100644
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
+**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error). W2 landed 2026-09-12 — W3 is unblocked.
 
 ## W1 — Request logging (DONE 2026-09-05)
 
 **Learnings:** log the client id, never the API key; 1-in-10 sampling keeps the log under 2 GB/day.
 **Commits:** `a1b2c3d` (logger), `d4e5f6a` (sampling).
 
-## W2 — Rate limiter middleware (IN PROGRESS)
+## W2 — Rate limiter middleware (DONE 2026-09-12)
 
-- `src/limiter.sh:1-20` — token bucket per client id, 60 requests/minute, burst 10.
-- Over the limit returns HTTP 429 with a `Retry-After` header.
-- Why: one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**What shipped:** `src/limiter.sh:1-8` — token bucket per client id (state file per client under `$LIMITER_STATE`), refills 1 token/s = 60 requests/minute, burst 10. Over the limit prints `429 Retry-After: 1` and exits 1.
+**Why:** one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Verified 2026-09-24:** 15 back-to-back calls for one client → 10 `ok`, 5 `429 Retry-After: 1`.
+**Learnings:** the 429 is a bare text line today — W3 must wrap it in the structured error body. `Retry-After` is a fixed 1 s (one token's refill time), not computed from the deficit.
+**Known issue:** a client's first call prints `No such file or directory` to stderr — at `src/limiter.sh:5` the `< "$f"` redirect fails before `2>/dev/null` applies. Output and exit code are still correct.
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
7f636cf docs(plan): w2 rate limiter done
74f9d54 feat(w2): rate limiter middleware (token bucket, 429 + Retry-After)
d59b4f4 feat(w1): request logging
[exit 0]
```

### `git diff HEAD~1 -- PLAN.md 2>/dev/null | head -80 || true`
```
diff --git a/PLAN.md b/PLAN.md
index 47794b3..83d7ef3 100644
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
+**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error). W2 landed 2026-09-12 — W3 is unblocked.
 
 ## W1 — Request logging (DONE 2026-09-05)
 
 **Learnings:** log the client id, never the API key; 1-in-10 sampling keeps the log under 2 GB/day.
 **Commits:** `a1b2c3d` (logger), `d4e5f6a` (sampling).
 
-## W2 — Rate limiter middleware (IN PROGRESS)
+## W2 — Rate limiter middleware (DONE 2026-09-12)
 
-- `src/limiter.sh:1-20` — token bucket per client id, 60 requests/minute, burst 10.
-- Over the limit returns HTTP 429 with a `Retry-After` header.
-- Why: one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**What shipped:** `src/limiter.sh:1-8` — token bucket per client id (state file per client under `$LIMITER_STATE`), refills 1 token/s = 60 requests/minute, burst 10. Over the limit prints `429 Retry-After: 1` and exits 1.
+**Why:** one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Verified 2026-09-24:** 15 back-to-back calls for one client → 10 `ok`, 5 `429 Retry-After: 1`.
+**Learnings:** the 429 is a bare text line today — W3 must wrap it in the structured error body. `Retry-After` is a fixed 1 s (one token's refill time), not computed from the deficit.
+**Known issue:** a client's first call prints `No such file or directory` to stderr — at `src/limiter.sh:5` the `< "$f"` redirect fails before `2>/dev/null` applies. Output and exit code are still correct.
+**Commits:** `74f9d54` (limiter).
 
 ## W3 — Structured error bodies (NOT STARTED)
[exit 0]
```

### `git diff $(git log --format=%H --grep='feat(w2)' -1) -- PLAN.md | head -80`
```
diff --git a/PLAN.md b/PLAN.md
index 47794b3..83d7ef3 100644
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
+**Dependencies:** W3 blockedBy W2 (the limiter's 429 body is the first structured error). W2 landed 2026-09-12 — W3 is unblocked.
 
 ## W1 — Request logging (DONE 2026-09-05)
 
 **Learnings:** log the client id, never the API key; 1-in-10 sampling keeps the log under 2 GB/day.
 **Commits:** `a1b2c3d` (logger), `d4e5f6a` (sampling).
 
-## W2 — Rate limiter middleware (IN PROGRESS)
+## W2 — Rate limiter middleware (DONE 2026-09-12)
 
-- `src/limiter.sh:1-20` — token bucket per client id, 60 requests/minute, burst 10.
-- Over the limit returns HTTP 429 with a `Retry-After` header.
-- Why: one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**What shipped:** `src/limiter.sh:1-8` — token bucket per client id (state file per client under `$LIMITER_STATE`), refills 1 token/s = 60 requests/minute, burst 10. Over the limit prints `429 Retry-After: 1` and exits 1.
+**Why:** one client sent 40k requests in an hour on 2026-09-02 and starved everyone else.
+**Verified 2026-09-24:** 15 back-to-back calls for one client → 10 `ok`, 5 `429 Retry-After: 1`.
+**Learnings:** the 429 is a bare text line today — W3 must wrap it in the structured error body. `Retry-After` is a fixed 1 s (one token's refill time), not computed from the deficit.
+**Known issue:** a client's first call prints `No such file or directory` to stderr — at `src/limiter.sh:5` the `< "$f"` redirect fails before `2>/dev/null` applies. Output and exit code are still correct.
+**Commits:** `74f9d54` (limiter).
 
 ## W3 — Structured error bodies (NOT STARTED)
[exit 0]
```
