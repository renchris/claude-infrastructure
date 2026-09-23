Findings from a full read of `scripts/lead-supervisor.sh`. Nine defects, ordered by severity.

**1. A failed or timed-out `git status` reads as a clean tree, so a dead lead's dirty worktree can be reaped without checkpoint or page.**

Where, line 355:
```bash
  [ -z "$(sup_git -C "$cwd" status --porcelain 2>/dev/null)" ] || return 1
```
Why: the exit status of the substituted command is discarded. If `git status` is cut at the 15 s bound, hits an index.lock, or errors for any reason, its stdout is empty and the test passes as "clean". If `rev-list --count` then reports 0 ahead, `work_landed` returns 0, `assess` calls `reap_clean`, and the telemetry row is deleted with no checkpoint and no DEAD page. The comment block above the function claims a cut returns 1 on every git call. This line is the exception.

**2. A checkpoint that did not happen is recorded and paged as done.**

Where, lines 324, 325, 330, 338 and 485:
```bash
  [ -n "$cwd" ] && [ -d "$cwd" ] || return 0
  if command -v teammate-checkpoint.sh >/dev/null 2>&1; then
    CC_CHECKPOINT_MEMBER="supervisor-$1" sup_bounded "$SUP_CKPT_TIMEOUT_S" teammate-checkpoint.sh "$cwd" >/dev/null 2>&1 || rc=$?
  idl checkpoint "\"sid\":\"$1\",\"cwd\":\"$cwd\",\"why\":\"dead-lead-preserve\""
    checkpoint_preserve "$sid" "$cwd"; page "$sid" DEAD "$why; worktree checkpoint-preserved"; echo 1; return
```
Why: only rc 124 is handled. If the script is not on PATH, which is the launchd case the file itself warns about, the `if` is skipped, rc stays 0, and an IDL `checkpoint` record is written. If the script runs and fails with any non-124 rc, the same success record is written. If cwd is missing, the function returns before recording anything. In all three cases the DEAD page text still says "worktree checkpoint-preserved".

**3. The page deadline clock is per sid, not per state, so a STALL? page can be escalated in the same sweep it is raised.**

Where, lines 203 and 507 to 509:
```bash
  [ -f "$pf" ] || printf '%s\n' "$(now)" > "$pf"           # stamp the deadline clock on first page only
      local had_page=0; [ -f "$PAGEDIR/$sid.page" ] && had_page=1
      page "$sid" "STALL?" "pid alive but telemetry ${age}s + transcript ${tage}s stale — CANDIDATE; re-observing effects at deadline"
      [ "$had_page" = 1 ] && resolve_page "$sid" "$cwd"
```
Why: a session idle at or above the threshold is paged PAST-THRESHOLD, which creates the `.page` file. Thirty minutes later it becomes a STALL? candidate. The file already exists, so `had_page` is 1 and the stamp is not refreshed. `resolve_page` sees a deadline that expired long ago, re-reads effects since the old stamp, finds nothing, and pages ESCALATED immediately. That skips the 15 minute re-observation window and sends two notifies in one sweep, which is the storm the same-sweep guard was written to prevent.

**4. A telemetry row with no usable cwd is escalated as "effects-dark" though nothing was observed.**

Where, lines 265 and 290:
```bash
  if [ -n "$cwd" ] && [ -d "$cwd" ]; then
  printf '%s' "$verdict"
```
Why: when cwd is empty or not a directory the whole probe is skipped and the initial value `dark` is printed. `resolve_page` then calls `escalate_page`. The function's own contract says `unknown` means "we could not look", and this is exactly that case. The result is an escalation on an unproven premise every deadline for any session whose cwd is missing or deleted.

**5. The effects re-read falls back to a 1970 timestamp, which reads every file as fresh.**

Where, line 277:
```bash
        touch -t "$(date -r "$since" +%Y%m%d%H%M.%S 2>/dev/null || echo 197001010000)" "$ref" 2>/dev/null
```
Why: `date -r <epoch>` is BSD syntax. On GNU date it means "file modification time" and fails, and it also fails if `since` is empty from a truncated `.page` file. The fallback sets the reference mtime to 1970, so `find -newer` matches any file and the verdict is `fresh`. The function's comment says folding into fresh "would silently EXONERATE a genuinely hung lead". The script already carries a GNU `stat -c` fallback, so it is meant to run on both.

**6. The "unreadable ps" abstain guard in the self-check can never fire.**

Where, lines 597, 606 and 609 to 610:
```bash
    END { print c+0 }'
  case "$live" in ''|*[!0-9]*) return 0 ;; esac      # unreadable ps ⇒ ABSTAIN (no verdict), never a phantom Δ
  if [ "$delta" -le "$PANE_DELTA_TOL" ]; then
    _ensure; printf '0 0\n' > "$sf" 2>/dev/null || true   # re-arm on recovery
```
Why: awk's END block prints `0` even when `ps` fails and produces no input, so `live` is always numeric. A ps failure therefore yields delta of minus n, which passes the tolerance test and resets the persistence counter to zero. A blind spot that was one sweep from paging is silently re-armed by a transient ps error, and the check treats a failed observation as "zero live panes".

**7. A PAST-THRESHOLD page is cleared as OK while the session is still above threshold and still working.**

Where, lines 515 and 520:
```bash
  if [ "$used" -ge "$T" ] && [ "$age" -lt "$STALL_S" ]; then
  clear_page "$sid"; echo 0
```
Why: a session at or above the threshold inside a long turn stops rendering the statusline, so telemetry age crosses `STALL_S` while its transcript stays warm. The STALL? branch falls through on the warm transcript, the B-1 branch fails on the stale age, and the OK branch removes the page and the notify marker. The comment on the OK branch says "fresh + below threshold + alive", but this path is stale and above threshold. This is the "working past boundary, never Stops" case B-1 claims to cover. When telemetry refreshes at the next turn boundary the page is re-raised with a fresh notify, so each long turn produces another desk ping.

**8. The permission-beacon reap uses bare `kill -0`, so a recycled pid keeps a dead session's beacon paging.**

Where, line 554:
```bash
      if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
```
Why: the rest of the file treats a pid recycled to a non-claude process as dead via `pid_alive_owner`. This branch does not, so once the pid is reused the beacon survives until the 24 hour horizon and `page_permpend` sends a PERMISSION-PENDING page for a session that has exited. The comment on this branch claims it covers "owning session provably DEAD".

**9. cwd and sid are interpolated into IDL JSON unescaped, so a value containing a quote or backslash corrupts the outcome record.**

Where, lines 204, 335, 338, 374 and 457, for example:
```bash
  idl checkpoint "\"sid\":\"$1\",\"cwd\":\"$cwd\",\"why\":\"dead-lead-preserve\""
```
Why: `json_str` exists precisely to avoid this and is used for command strings, but these records embed the raw values. A cwd such as one containing `"` produces a malformed JSONL line, so the S-4 audit record for that page, reap, or checkpoint is unparseable and reads as absent to anything consuming the IDL.
