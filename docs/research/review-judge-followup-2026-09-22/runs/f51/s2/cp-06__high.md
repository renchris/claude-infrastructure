I read the file end to end. Findings below, ordered by severity.

## Defects

**1. A cut or failed `git status` reads as a clean tree, so a dirty worktree can be reaped.**

Where: line 355
```bash
  [ -z "$(sup_git -C "$cwd" status --porcelain 2>/dev/null)" ] || return 1
```
Why: only the output is tested; the exit status of `git status` is discarded. When the probe is cut at the 15s bound (rc 124, the index.lock case the header names) or fails for any reason, the substitution is empty, `[ -z "" ]` is true, and the tree is treated as clean. If `rev-list --count` then returns 0 (or cherry/diff say landed), `work_landed` returns 0 and `reap_clean` deletes the telemetry row and clears the page for a session whose uncommitted work was never checked. This contradicts the function's own contract at lines 348 to 350 that a cut "return 1 ⇒ the caller PAGES".

**2. A checkpoint that never ran, or that failed, is recorded as a successful checkpoint and the DEAD page claims "checkpoint-preserved".**

Where: lines 325, 330, 338, 485
```bash
  if command -v teammate-checkpoint.sh >/dev/null 2>&1; then
    CC_CHECKPOINT_MEMBER="supervisor-$1" sup_bounded "$SUP_CKPT_TIMEOUT_S" teammate-checkpoint.sh "$cwd" >/dev/null 2>&1 || rc=$?
  idl checkpoint "\"sid\":\"$1\",\"cwd\":\"$cwd\",\"why\":\"dead-lead-preserve\""
    checkpoint_preserve "$sid" "$cwd"; page "$sid" DEAD "$why; worktree checkpoint-preserved"; echo 1; return
```
Why: `rc` stays 0 when the script is not on PATH, and only rc 124 is special-cased. Any other non-zero exit (git error, script abort, rc 1) falls through to the `checkpoint` success record at line 338. The script is resolved only through PATH, unlike cc-notify and timeout which get explicit fallbacks for launchd's minimal PATH, so under launchd it is likely absent and every stranded death logs a checkpoint that did not happen. The DEAD page text then asserts preservation unconditionally.

**3. When `date -r` fails, the reference file is stamped 1970, so every file in the worktree is "newer" and a dark lead is voided as fresh.**

Where: line 277
```bash
        touch -t "$(date -r "$since" +%Y%m%d%H%M.%S 2>/dev/null || echo 197001010000)" "$ref" 2>/dev/null
```
Why: `date -r <epoch>` is BSD only. On GNU date it is a file reference and fails, and the fallback sets the mtime to epoch 0. The `find -newer` then matches the first regular file, `verdict=fresh`, and `resolve_page` records `page_void` for a session that may have produced nothing. The file elsewhere carries a GNU fallback for `stat` at line 394, so a GNU host is an intended environment. This is the "fold into fresh would silently EXONERATE a genuinely hung lead" outcome the comment at line 260 rules out.

**4. A `mktemp` failure produces "dark", not "unknown", so an unobserved state escalates.**

Where: lines 275 to 276
```bash
      local ref; ref="$(mktemp 2>/dev/null)"
      if [ -n "$ref" ]; then
```
Why: if mktemp fails (full or unwritable TMPDIR), the file-mtime probe is skipped and `verdict` stays `dark`. `resolve_page` then calls `escalate_page`. The function's stated contract is that "we could not look" is the third state that must not escalate.

**5. The self-check's "unreadable ps ⇒ abstain" guard can never fire; an unreadable `ps` reads as zero live panes and re-arms the detector.**

Where: lines 592 to 597 and 606
```bash
  ps -wwEo command= 2>/dev/null | awk '
    END { print c+0 }'
  case "$live" in ''|*[!0-9]*) return 0 ;; esac
```
Why: when `ps` fails or prints nothing, awk still reaches END and prints `0`, which passes the numeric case. `delta` becomes `0 - enum`, which is at or below the tolerance, so line 610 overwrites the persistence state with `0 0`. A transient ps failure silently resets a blind-spot count that was about to page, and the abstain branch is dead code.

**6. Permission-pending pages fire for sessions the supervisor has already classified dead.**

Where: lines 552 to 557 and 375, and line 554
```bash
    if [ -f "$tel" ]; then
      if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
  rm -f "$TEL_DIR/$1.json" 2>/dev/null || true
```
Why: `sweep` runs `assess` before `sweep_permission_pending`. When `assess` reaps a clean-completed dead session, it deletes the telemetry row in the same sweep, so the beacon check finds no telemetry, cannot pid-check, and pages PERMISSION-PENDING for a dead session on every sweep until the 24h horizon. Separately, line 554 uses bare `kill -0` rather than `pid_alive_owner`, so a pid recycled to a non-claude process (which `assess` treats as DEAD at line 477) keeps the beacon alive and paging.

**7. The B-1 guard stops covering a past-threshold session once its telemetry goes stale, and the OK branch clears the standing page.**

Where: lines 515 and 520
```bash
  if [ "$used" -ge "$T" ] && [ "$age" -lt "$STALL_S" ]; then
  clear_page "$sid"; echo 0
```
Why: the header says B-1 covers a session "hung/working-past-boundary" that never Stops. A session in one long turn stops rendering the statusline, so `age` passes `STALL_S` after 30 minutes. If its transcript is warm, the STALL? branch is skipped, the B-1 test fails on the age clause, and control reaches `clear_page`, which removes the PAST-THRESHOLD page and its damping marker. The session is exactly the class B-1 claims, and it loses its page while it is most likely to be past the boundary.

**8. The owner check matches any process whose command line contains the substring "claude", not a claude session.**

Where: line 432
```bash
  ps -p "$p" -o command= 2>/dev/null | grep -qiF "$OWNER_PAT"
```
Why: `-F claude` is a fixed-substring, case-insensitive match against the full argv. A pid recycled to `bash ~/.claude/hooks/x.sh`, `tail ~/.claude/autonomy/supervisor.log`, or any tool operating under the `~/.claude` tree is counted as the original owner. The row then routes to STALL? rather than DEAD, so a stranded worktree is never checkpoint-preserved, and the "recycled to a NON-claude process ⇒ DEAD" claim at lines 423 to 427 does not hold for the common case in this ecosystem.

**9. The self-check's enumerated count includes dead rows, so stranded dead sessions mask an equal number of unseen live panes.**

Where: lines 632 and 607
```bash
      n=$((n+1)); r="$(assess "$f")"; found=$(( found + ${r:-0} ))
  delta=$(( live - enum ))
```
Why: `n` counts every telemetry file, including dead-pid rows that persist indefinitely (they are never GC'd, per line 453). With two stranded dead rows and two live panes missing from telemetry, `live - enum` is zero and no blind-spot is reported even though two live sessions have no pager coverage.
