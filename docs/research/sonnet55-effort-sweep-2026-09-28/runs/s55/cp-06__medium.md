Line numbers weren't supplied with the file, so I give the verbatim line and the enclosing function instead.

**1. A failed or cut `git status` is read as "clean tree", so a dirty worktree can be reaped.**
- **Where:** in `work_landed`: `[ -z "$(sup_git -C "$cwd" status --porcelain 2>/dev/null)" ] || return 1`
- **Why it is wrong:** The check tests only that the captured output is empty, not that git succeeded. If `status` is cut by the timeout, hits `index.lock` contention, or errors, its stdout is empty and the test passes as "clean". The later `rev-list`, `cherry` and `diff` calls can then succeed. A dead session with uncommitted work is judged shipped+clean, and `reap_clean` deletes its telemetry row and clears its page. The DEAD page and checkpoint never run. This contradicts the comment above the function, which says a cut is treated as "cannot prove clean".

**2. A probe that needed SIGKILL is not recognised as a cut, so an unobserved state becomes `dark` and escalates.**
- **Where:** in `reobserve_effects`: `[ "$rc" = 124 ] && { printf 'unknown'; return; }` (appears twice, after the `git log` and after the `find`).
- **Why it is wrong:** `sup_bounded` runs `timeout -k 5`, and the comment says it is there for forks that ignore TERM. When the KILL is needed, timeout(1) exits 137, not 124. In that case:
  - The `git log` output is empty, so `last_commit` is 0 and the verdict stays `dark`.
  - A `find` cut the same way leaves `hit` empty, so the result is `dark`.
  - `resolve_page` then calls `escalate_page`, the escalation on an unobserved state that the `unknown` verdict was added to prevent.

**3. A failed or missing checkpoint is recorded as a successful one, and the page still says it was preserved.**
- **Where:** in `checkpoint_preserve`:
  - `CC_CHECKPOINT_MEMBER="supervisor-$1" sup_bounded "$SUP_CKPT_TIMEOUT_S" teammate-checkpoint.sh "$cwd" >/dev/null 2>&1 || rc=$?`
  - `idl checkpoint "\"sid\":\"$1\",\"cwd\":\"$cwd\",\"why\":\"dead-lead-preserve\""`
  - In `assess`: `page "$sid" DEAD "$why; worktree checkpoint-preserved"`
- **Why it is wrong:** Only rc 124 is handled. If the script exits non-zero for any other reason, including 137 from the KILL, `rc` is set but never inspected. The same happens if `teammate-checkpoint.sh` is not on PATH (the `command -v` guard skips it) or if `cwd` is missing (the function returns early). In each case the "checkpoint" IDL record is written, and the DEAD page tells the operator the worktree is checkpoint-preserved. No checkpoint exists, so the operator is told a safety net is in place when it is not.

**4. If the reference file cannot be made or dated, the probe is skipped or run against the wrong time, and the result is `dark`.**
- **Where:** in `reobserve_effects`:
  - `local ref; ref="$(mktemp 2>/dev/null)"`
  - `if [ -n "$ref" ]; then`
  - `touch -t "$(date -r "$since" +%Y%m%d%H%M.%S 2>/dev/null || echo 197001010000)" "$ref" 2>/dev/null`
- **Why it is wrong:** There are two paths to a false `dark`:
  - If `mktemp` fails (full or unwritable tmp), the whole `find` is skipped and the verdict stays `dark`.
  - If `touch -t` fails, its error is discarded, `$ref` keeps its creation time (now), and `-newer "$ref"` matches nothing.
  
  Either way, a lead that is actually producing files is reported as effects-dark and escalated. That is the silence-reap this function exists to avoid, and it is not reported as `unknown`.

**5. A telemetry row with no `pid` is never checked for death or stall and is cleared as healthy.**
- **Where:** in `assess`:
  - `if [ -n "$pid" ] && ! pid_alive_owner "$pid"; then` (DEAD branch)
  - `if pid_alive_owner "$pid" && [ "$age" -ge "$STALL_S" ] && ! is_registered_desk "$sid"; then` (STALL? branch)
  - `clear_page "$sid"; echo 0` (OK branch)
- **Why it is wrong:** If a row has an empty or missing `.pid`, the DEAD branch is skipped because of `-n`. The STALL? branch is skipped because `pid_alive_owner ""` fails. `GC` skips the row too. A row of any age with a low `used_pct` reaches `clear_page` and counts as a healthy sweep. Nothing pages, checkpoints or logs that the row could not be checked.
