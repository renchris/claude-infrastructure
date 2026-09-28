I found five defects.

**1. A failed or cut `git status` reads as a clean worktree.**
- **What:** `work_landed` treats empty output from `git status --porcelain` as "clean" and never checks the fork's exit status.
- **Where:** line 357: `  [ -z "$(sup_git -C "$cwd" status --porcelain 2>/dev/null)" ] || return 1`
- **Why it is wrong:** If the bounded git call is cut (rc 124/137), or git errors, stdout is empty and the test passes. The comment above the function claims a cut is treated like any other failure and returns 1, but only `rev-list` is rc-checked. A dead lead with a dirty tree and a slow git can then pass the "clean" gate. If its HEAD is 0 ahead or the diff is empty, `reap_clean` runs. That deletes the telemetry row and skips the DEAD page and its checkpoint, so uncommitted work is dropped with no page.

**2. A checkpoint that never happened is recorded as one.**
- **What:** `checkpoint_preserve` logs a `checkpoint` IDL record, and the caller pages "worktree checkpoint-preserved", when no checkpoint ran or it failed.
- **Where:** lines 326 and 331, with the record at line 340 and the page text at line 488.
  - Line 326: `  if command -v teammate-checkpoint.sh >/dev/null 2>&1; then`
  - Line 331: `    CC_CHECKPOINT_MEMBER="supervisor-$1" sup_bounded "$SUP_CKPT_TIMEOUT_S" teammate-checkpoint.sh "$cwd" >/dev/null 2>&1 || rc=$?`
  - Line 340: `  idl checkpoint "\"sid\":\"$1\",\"cwd\":\"$cwd\",\"why\":\"dead-lead-preserve\""`
  - Line 488: `    checkpoint_preserve "$sid" "$cwd"; page "$sid" DEAD "$why; worktree checkpoint-preserved"`
- **Why it is wrong:**
  - **Not on PATH:** under launchd's minimal PATH, `teammate-checkpoint.sh` is not found, so the `if` is skipped, `rc` stays 0, and the function records `checkpoint`.
  - **Non-124 failure:** if the script exits non-zero (e.g. 1 or 137), only `rc = 124` is handled, so the failure is also recorded as a success.
  - **Result:** the DEAD page tells the operator the worktree is preserved, and the audit trail agrees, when nothing was preserved.

**3. A `timeout -k` KILL exit (137) is never recognised as "cut".**
- **What:** every cut check compares the exit status to 124 only.
- **Where:**
  - line 80: `  "$SUP_TIMEOUT_BIN" -k 5 "$s" "$@"`
  - line 270: `    [ "$rc" = 124 ] && { printf 'unknown'; return; }`
  - line 286: `        [ "$rc" = 124 ] && { printf 'unknown'; return; }`
- **Why it is wrong:** with `-k`, a child that ignores TERM and is killed by the follow-up KILL yields exit status 137, not 124. The comment at line 75 names this case, a wedged client that ignores TERM. In `reobserve_effects`, a `git log` or `find` cut this way returns rc 137, so `last_commit` and `hit` are empty. The verdict stays `dark`, `resolve_page` escalates on a probe that never answered, and the `unknown` path meant to prevent this is bypassed. The same gap makes a KILL-cut checkpoint (line 333) look like an ordinary success (see 2).

**4. `reobserve_effects` reports "dark" when it could not look.**
- **What:** if `mktemp` fails, or the `cwd` no longer exists, the effects probe is skipped and the default verdict `dark` is printed.
- **Where:** line 276: `      local ref; ref="$(mktemp 2>/dev/null)"` (the `if [ -n "$ref" ]` at line 277 has no else), and line 266: `  if [ -n "$cwd" ] && [ -d "$cwd" ]; then`
- **Why it is wrong:** the function's own contract says `dark` means "none observed" and `unknown` means "we could not look". With a full or unwritable temp dir, a missing `cwd`, or an unreadable tree, no find ever runs, yet the result is `dark`. `resolve_page` then calls `escalate_page` on a live, possibly productive lead. That is the silence-reap that S-3b exists to prevent.

**5. The self-check's "enumerated" count includes dead and reaped rows.**
- **What:** `n` counts every telemetry row, including rows whose pid is gone, and the result is compared against the live-pane count.
- **Where:** line 635: `      n=$((n+1)); r="$(assess "$f")"; found=$(( found + ${r:-0} ))`, which feeds `self_check "$n"`.
- **Why it is wrong:** `self_check` alarms on `live − enum`, meant as live panes with no telemetry row. A stranded-dead row (kept and paged as DEAD) or a row reaped this sweep still increments `n`. With 2 live panes, 1 visible and 1 not, plus 1 dead row, `enum` = 2 and `delta` = 0, so the blind-spot page is suppressed and the sweep emits an all-clear heartbeat while a live pane has no coverage.

Line numbers come from counting the pasted text by hand, so they may be off by a few.
