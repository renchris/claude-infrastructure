I read the whole file. Below are the defects I can point at in the code, ordered by impact.

**1. A cut or failed `git status` reads as a clean worktree in `work_landed`**

- **Where:** line 355
  ```bash
  [ -z "$(sup_git -C "$cwd" status --porcelain 2>/dev/null)" ] || return 1
  ```
- **Why it is wrong:** The test looks only at stdout, never at the exit code. When the bounded `git status` is cut at the 15s bound (rc 124, exactly the index-lock/large-tree stall this file describes), or fails for any other reason, its stdout is empty, so the dirty check passes. If `rev-list`, `cherry`, or `diff --quiet` then succeed, the function returns 0 and the DEAD path calls `reap_clean`, which deletes the telemetry row and clears the page for a worktree that may hold uncommitted work. This contradicts the contract stated at lines 348 to 350, that a timed-out probe must return 1 and page. Only the `rev-list` line (356) actually checks the exit code.

**2. `checkpoint_preserve` reports a checkpoint that did not happen, and the DEAD page always claims one**

- **Where:** lines 325, 330, 338, and 485
  ```bash
  if command -v teammate-checkpoint.sh >/dev/null 2>&1; then
  ```
  ```bash
      CC_CHECKPOINT_MEMBER="supervisor-$1" sup_bounded "$SUP_CKPT_TIMEOUT_S" teammate-checkpoint.sh "$cwd" >/dev/null 2>&1 || rc=$?
  ```
  ```bash
    idl checkpoint "\"sid\":\"$1\",\"cwd\":\"$cwd\",\"why\":\"dead-lead-preserve\""
  ```
  ```bash
      checkpoint_preserve "$sid" "$cwd"; page "$sid" DEAD "$why; worktree checkpoint-preserved"; echo 1; return
  ```
- **Why it is wrong:** Only rc 124 is treated as a non-checkpoint. If `teammate-checkpoint.sh` is not on PATH, `rc` stays 0 and line 338 records a successful `checkpoint`. If the script runs and fails with any other non-zero rc (a git error, a dirty-index abort), line 338 still records success. If `cwd` is empty or missing, line 324 returns silently with no record at all. In every one of these cases, and also in the rc 124 case, line 485 pages the operator with the text "worktree checkpoint-preserved". The insurance the DEAD page promises is absent and both the IDL and the page say it is present.

**3. A missing or empty `cwd` is reported as an observed "dark" re-read and escalated**

- **Where:** lines 264 to 265 and 318
  ```bash
    local cwd="$2" since="$3" verdict=dark rc=0
    if [ -n "$cwd" ] && [ -d "$cwd" ]; then
  ```
  ```bash
    page "$1" ESCALATED "no work-products across the page deadline; supervisor re-read confirms dark (still not auto-acting)"
  ```
- **Why it is wrong:** When the telemetry row has no `cwd`, or the directory no longer exists (worktree removed, volume unmounted), the entire body is skipped and the function prints the initial value `dark` without looking at anything. `resolve_page` then calls `escalate_page`, which writes a `page_escalate` record and a page saying the re-read "confirms dark". The file defines a third `unknown` state precisely so that an unobserved condition is never escalated, but the no-cwd case bypasses it. Since the `.page` stamp is never reset on escalation, this repeats every sweep.

**4. The page deadline clock is shared across page states, so a first STALL? sweep can escalate immediately**

- **Where:** lines 203 and 507 to 509
  ```bash
    [ -f "$pf" ] || printf '%s\n' "$(now)" > "$pf"           # stamp the deadline clock on first page only
  ```
  ```bash
        local had_page=0; [ -f "$PAGEDIR/$sid.page" ] && had_page=1
        page "$sid" "STALL?" "pid alive but telemetry ${age}s + transcript ${tage}s stale — CANDIDATE; re-observing effects at deadline"
        [ "$had_page" = 1 ] && resolve_page "$sid" "$cwd"
  ```
- **Why it is wrong:** A session that was paged PAST-THRESHOLD while fresh keeps that `.page` file, stamped at the first threshold page. If the session then goes telemetry-stale for `STALL_S` (30m) and enters the STALL? branch, `had_page` is 1 because of the threshold page, `page()` does not re-stamp, and `resolve_page` computes elapsed time from the old stamp, which already exceeds the 15m deadline. The re-read and, if dark, the ESCALATED page happen in the same sweep as the very first STALL? page. This is the same-sweep escalate that the guard's comment says it prevents, and it produces two notifies in one sweep because the marker held PAST-THRESHOLD.

**5. The `date -r` fallback makes every effects re-read "fresh"**

- **Where:** line 277
  ```bash
        touch -t "$(date -r "$since" +%Y%m%d%H%M.%S 2>/dev/null || echo 197001010000)" "$ref" 2>/dev/null
  ```
- **Why it is wrong:** If `date -r <epoch>` fails, the reference file is stamped at 1970, so `find -newer` matches the first regular file it sees and the verdict is `fresh`. On GNU date `-r` takes a filename, so it fails on every call there. The function's own header (line 260) says folding an unobserved state into `fresh` "would silently EXONERATE a genuinely hung lead"; this fallback does exactly that. A truly dark lead is voided at every deadline and never escalated. The file already carries a GNU fallback for `stat` at line 394, so a non-BSD host is within its intended range.

**6. `pid_alive_owner` matches the owner pattern anywhere in the full command line**

- **Where:** line 432
  ```bash
    ps -p "$p" -o command= 2>/dev/null | grep -qiF "$OWNER_PAT"
  ```
- **Why it is wrong:** The default pattern is the fixed substring `claude`, tested against the whole command line including arguments. Any process whose arguments mention a path under `~/.claude` qualifies: this daemon itself (`bash ~/.claude/hooks/lead-supervisor.sh`), `tail -f ~/.claude/autonomy/supervisor.log`, an editor opened on a file in that tree. A dead session whose pid is recycled to such a process is classified as a live owner, so it takes the STALL? branch and escalates instead of the DEAD branch, and the row survives until the 6h GC. The checkpoint insurance the DEAD path provides is skipped for that row.

**7. The permission-beacon reap uses bare `kill -0`, which the file elsewhere says lies**

- **Where:** line 554
  ```bash
        if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
  ```
- **Why it is wrong:** A session that dies with a beacon outstanding and whose pid is then recycled passes `kill -0`, so the beacon is not reaped. It falls through to the notice check and pages the operator with "PERMISSION-PENDING", and keeps paging on each new sweep's IDL record, for up to the 24h horizon, for a prompt that no longer exists. The same recycled-pid class is handled by `pid_alive_owner` in `assess`, but not here.

**8. Raw `cwd` is spliced into IDL JSON without encoding**

- **Where:** lines 335, 338, 374, and 457
  ```bash
    idl checkpoint "\"sid\":\"$1\",\"cwd\":\"$cwd\",\"why\":\"dead-lead-preserve\""
  ```
  ```bash
    idl reap "\"sid\":\"$1\",\"cwd\":\"$2\",\"why\":\"clean-completion-shipped-clean-worktree\""
  ```
- **Why it is wrong:** A working directory containing a double quote or backslash produces an unparseable IDL line, so the outcome record for that reap, checkpoint, or GC is lost to any reader of the log. The file defines `json_str` for exactly this reason (lines 183 to 185) and uses it for the beacon command and page target, but not for `cwd`.
