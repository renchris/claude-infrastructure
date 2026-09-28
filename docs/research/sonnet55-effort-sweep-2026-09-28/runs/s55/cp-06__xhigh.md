I found six defects. I counted lines with `#!/bin/bash` as line 1.

**1. A failed or timed-out `git status` is read as "clean tree", so a dirty dead worktree can be reaped.**
- **What:** `work_landed` treats empty output from `git status --porcelain` as proof of a clean tree, without checking whether the command succeeded.
- **Where:** line 355: `  [ -z "$(sup_git -C "$cwd" status --porcelain 2>/dev/null)" ] || return 1`
- **Why it is wrong:** If `git status` is cut by the 15s bound (rc 124/137) or errors, it prints nothing, so `-z` is true and the check passes as "clean". This is likely on a huge tree, where status is slow but `rev-list` is fast. If the branch is then 0 ahead of trunk, `work_landed` returns 0. `assess` calls `reap_clean`, which deletes the telemetry row and clears the page, and never checkpoints or pages. Uncommitted work in a dead lead's worktree is dropped with no page. This contradicts the comment at lines 348-350 that a cut probe always returns 1.

**2. A checkpoint that never ran, or failed, is recorded and paged as "checkpoint-preserved".**
- **What:** `checkpoint_preserve` logs and announces a checkpoint even when nothing was checkpointed.
- **Where:**
  - line 324: `  [ -n "$cwd" ] && [ -d "$cwd" ] || return 0`
  - line 325: `  if command -v teammate-checkpoint.sh >/dev/null 2>&1; then`
  - line 330: `    CC_CHECKPOINT_MEMBER="supervisor-$1" sup_bounded "$SUP_CKPT_TIMEOUT_S" teammate-checkpoint.sh "$cwd" >/dev/null 2>&1 || rc=$?`
  - line 338: `  idl checkpoint "\"sid\":\"$1\",\"cwd\":\"$cwd\",\"why\":\"dead-lead-preserve\""`
  - line 485: `    checkpoint_preserve "$sid" "$cwd"; page "$sid" DEAD "$why; worktree checkpoint-preserved"; echo 1; return`
- **Why it is wrong:**
  - **Script not on PATH:** `teammate-checkpoint.sh` is found only by bare `command -v`. Under launchd's minimal PATH (which the file says excludes Homebrew) it is not found, so line 325 skips the call.
  - **Non-124 failure:** if the script runs and exits non-zero for any reason other than 124, `rc` is set but only 124 is checked at line 332.
  - **Missing cwd:** if `$cwd` is empty or gone, line 324 returns silently.
  - **Result:** in all three cases control reaches line 338 or returns, and the IDL says a dead-lead-preserve happened. Line 485 then pages the operator that the worktree is "checkpoint-preserved". The operator is told insurance exists when it does not.

**3. `timeout -k` reports a SIGKILLed command as 137, but every cut-detection check tests only for 124.**
- **What:** The code assumes a cut probe always returns rc 124, but with `-k` it returns 137 if the command ignored SIGTERM and had to be SIGKILLed.
- **Where:**
  - line 80: `  "$SUP_TIMEOUT_BIN" -k 5 "$s" "$@"`
  - line 269: `    [ "$rc" = 124 ] && { printf 'unknown'; return; }`
  - line 285: `        [ "$rc" = 124 ] && { printf 'unknown'; return; }`
  - line 332: `  if [ "$rc" = 124 ]; then`
- **Why it is wrong:** The comment at lines 75-76 says `-k` exists for forks that ignore TERM. Those are exactly the forks that end with rc 137, not 124.
  - **`reobserve_effects`:** a KILLed `git log` gives empty output, so the commit is not `fresh` and `verdict` stays `dark`. A KILLed `find` gives empty `hit`, also `dark`. The result is `dark`, which triggers `escalate_page` on an unobserved state. That is the false escalation the "unknown" state was added to prevent.
  - **`checkpoint_preserve`:** a KILLed checkpoint script skips the `checkpoint_timeout` record and logs a normal `checkpoint`.

**4. "Could not look" cases in `reobserve_effects` are returned as `dark`, not `unknown`.**
- **What:** If the file-walk probe cannot run, the function still returns `dark`.
- **Where:**
  - line 265: `  if [ -n "$cwd" ] && [ -d "$cwd" ]; then`
  - line 275: `      local ref; ref="$(mktemp 2>/dev/null)"`
  - line 276: `      if [ -n "$ref" ]; then`
- **Why it is wrong:** If `mktemp` fails (full or unwritable temp dir), line 276 skips the entire `find`. If `$cwd` is empty or missing, the whole block is skipped. In both cases `verdict` keeps its initial `dark`, and line 290 prints it. `resolve_page` then escalates, although nothing was observed. The header (lines 252-262) says `dark` must only mean "looked and found nothing", with unobserved states reported as `unknown`.

**5. The recycled-pid ownership test is a substring match on the whole command line.**
- **What:** `pid_alive_owner` accepts any live process whose full `ps` command contains "claude" anywhere.
- **Where:** line 432: `  ps -p "$p" -o command= 2>/dev/null | grep -qiF "$OWNER_PAT"`
- **Why it is wrong:** The check is meant to detect a pid recycled to a non-claude process. Any unrelated process with "claude" in its arguments passes it, for example something run from `~/.claude/...`, `tail -f ~/.claude/autonomy/supervisor.log`, or an editor on a file there. This tree's own tooling lives under `~/.claude`. Such a recycled pid is treated as the original owner, so the dead session takes the STALL?/GC path instead of DEAD. That skips the effect-verified checkpoint, and a stranded death can be silently GC'd at line 457.

**6. A telemetry row with no `pid` skips both the DEAD and STALL? checks and is classed OK.**
- **What:** The liveness guards are silently bypassed for rows where `.pid` is absent.
- **Where:**
  - line 477: `  if [ -n "$pid" ] && ! pid_alive_owner "$pid"; then`
  - line 497: `  if pid_alive_owner "$pid" && [ "$age" -ge "$STALL_S" ] && ! is_registered_desk "$sid"; then`
- **Why it is wrong:** With an empty `pid`, line 477 is false and `pid_alive_owner ""` at line 497 returns 1. Control falls to the final `clear_page "$sid"; echo 0`, which the code labels "fresh + below threshold + alive". This happens however stale the row is (days, say) and regardless of `cwd`. `gc_stale` also skips such a row, because `pid_alive_owner "$pid" || continue` fails on an empty pid. The row is never paged or reaped, and any standing page for it is cleared each sweep.
