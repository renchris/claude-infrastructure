1. **What** — A page can be permanently marked as notified even though no notification was ever attempted or delivered.

   **Where** — Lines 150, 167, and 213–214:

   ```bash
       damp_should_send "${PAGE_TO:-role:$PAGE_TO_FILE}" "$fp" || return 0   # suppressed, but still "handled"
     [ -n "$fp" ] && command -v damp_forget >/dev/null 2>&1 && damp_forget "${PAGE_TO:-role:$PAGE_TO_FILE}" "$fp"
     if send_page "⚠️ SUPERVISOR PAGE — session $1 is $2: $3 (operator/delegated-live-session recovers; supervisor never auto-acts)" "page:$1:$2"; then
       printf '%s\n' "$2" > "$nf"                             # recorded only on a cc-notify-CONFIRMED enqueue
   ```

   **Why it is wrong** — The damping marker is created before notification; if the process dies before sending, or `damp_forget` fails after a rejected send, the next call is damping-suppressed and returns 0, causing `page` to write `.notified` despite there having been no confirmed enqueue.

2. **What** — The deadline timestamp is shared between unrelated page states, so a new stall can be resolved immediately against an older incident’s clock.

   **Where** — Lines 196 and 493–495:

   ```bash
     [ -f "$pf" ] || printf '%s\n' "$(now)" > "$pf"           # stamp the deadline clock on first page only
         local had_page=0; [ -f "$PAGEDIR/$sid.page" ] && had_page=1
         page "$sid" "STALL?" "pid alive but telemetry ${age}s + transcript ${tage}s stale — CANDIDATE; re-observing effects at deadline"
         [ "$had_page" = 1 ] && resolve_page "$sid" "$cwd"
   ```

   **Why it is wrong** — If a `PAST-THRESHOLD` page already exists when the session later becomes a `STALL?`, `page` retains the old timestamp and `had_page` triggers immediate resolution, potentially escalating without waiting `DEADLINE_S` after the stall was detected and using effects from the wrong observation interval.

3. **What** — Failures of the effects probes other than exit status 124 are treated as proof that the session is dark.

   **Where** — Lines 260–261 and 267–281:

   ```bash
       last_commit="$(sup_git -C "$cwd" log -1 --format=%ct 2>/dev/null)"; rc=$?
       [ "$rc" = 124 ] && { printf 'unknown'; return; }
         local ref; ref="$(mktemp 2>/dev/null)"
         if [ -n "$ref" ]; then
           touch -t "$(date -r "$since" +%Y%m%d%H%M.%S 2>/dev/null || echo 197001010000)" "$ref" 2>/dev/null
           local hit
           hit="$(sup_bounded "$SUP_FIND_TIMEOUT_S" find "$cwd" \( -name .git -o -name tmp -o -name node_modules -o -name .venv -o -name venv -o -name __pycache__ -o -name .next -o -name dist -o -name .worktrees \) -prune -o -type f -newer "$ref" -print -quit 2>/dev/null)"; rc=$?
           rm -f "$ref"
           [ "$rc" = 124 ] && { printf 'unknown'; return; }
           [ -n "$hit" ] && verdict=fresh
         fi
       fi
     fi
     printf '%s' "$verdict"
   ```

   **Why it is wrong** — A Git error such as 128, a timeout killed with status 137, a failed `mktemp`/`touch`, or a non-124 `find` error leaves `verdict=dark`; `resolve_page` then escalates while the code never successfully established the absence of effects.

4. **What** — Work performed exclusively inside any pruned directory is classified as no work.

   **Where** — Line 274:

   ```bash
           hit="$(sup_bounded "$SUP_FIND_TIMEOUT_S" find "$cwd" \( -name .git -o -name tmp -o -name node_modules -o -name .venv -o -name venv -o -name __pycache__ -o -name .next -o -name dist -o -name .worktrees \) -prune -o -type f -newer "$ref" -print -quit 2>/dev/null)"; rc=$?
   ```

   **Why it is wrong** — If the session modifies an uncommitted tracked or untracked file under a directory named `tmp`, `dist`, or another pruned name, the walk cannot see it and can escalate the session as effects-dark.

5. **What** — Second-resolution page timestamps misclassify effects occurring within the same second as the page.

   **Where** — Lines 174, 196, 262, and 269:

   ```bash
   now(){ date +%s; }
     [ -f "$pf" ] || printf '%s\n' "$(now)" > "$pf"           # stamp the deadline clock on first page only
       [ "${last_commit:-0}" -gt "$since" ] 2>/dev/null && verdict=fresh
           touch -t "$(date -r "$since" +%Y%m%d%H%M.%S 2>/dev/null || echo 197001010000)" "$ref" 2>/dev/null
   ```

   **Why it is wrong** — A commit made after the page but during the same epoch second has `last_commit == since` and is missed, while a file modified before the page but later than the start of that same second is newer than the reference and is falsely accepted as post-page work.

6. **What** — Effects created by another process are attributed to the supervised session.

   **Where** — Lines 260 and 274:

   ```bash
       last_commit="$(sup_git -C "$cwd" log -1 --format=%ct 2>/dev/null)"; rc=$?
           hit="$(sup_bounded "$SUP_FIND_TIMEOUT_S" find "$cwd" \( -name .git -o -name tmp -o -name node_modules -o -name .venv -o -name venv -o -name __pycache__ -o -name .next -o -name dist -o -name .worktrees \) -prune -o -type f -newer "$ref" -print -quit 2>/dev/null)"; rc=$?
   ```

   **Why it is wrong** — If another session, build process, or file watcher commits or touches a file in the same worktree after the page, `reobserve_effects` returns `fresh` and voids the page even if the target session remains hung.

7. **What** — A failed or absent checkpoint operation is recorded and announced as successful preservation.

   **Where** — Lines 316, 321, 323, 329, and 472:

   ```bash
     if command -v teammate-checkpoint.sh >/dev/null 2>&1; then
       CC_CHECKPOINT_MEMBER="supervisor-$1" sup_bounded "$SUP_CKPT_TIMEOUT_S" teammate-checkpoint.sh "$cwd" >/dev/null 2>&1 || rc=$?
     if [ "$rc" = 124 ]; then
     idl checkpoint "\"sid\":\"$1\",\"cwd\":\"$cwd\",\"why\":\"dead-lead-preserve\""
       checkpoint_preserve "$sid" "$cwd"; page "$sid" DEAD "$why; worktree checkpoint-preserved"; echo 1; return
   ```

   **Why it is wrong** — If the script is unavailable, exits with any nonzero status other than 124, is killed with status 137, or the worktree directory is missing, no checkpoint is established, yet the IDL or the DEAD page still claims that it was preserved.

8. **What** — `work_landed` treats a failed or timed-out status check with empty output as a clean worktree.

   **Where** — Line 345:

   ```bash
     [ -z "$(sup_git -C "$cwd" status --porcelain 2>/dev/null)" ] || return 1
   ```

   **Why it is wrong** — The test examines only captured output and discards `sup_git`’s exit status, so a timeout or Git error that emits no stdout passes the cleanliness check and can cause an unverified or dirty worktree to be reaped as completed.

9. **What** — The `git cherry` fast return can declare unlanded merge-only content landed.

   **Where** — Lines 351–352:

   ```bash
     if cherry_out="$(sup_git -C "$cwd" cherry "$TRUNK" HEAD 2>/dev/null)"; then
       printf '%s\n' "$cherry_out" | grep -q '^+' || return 0
   ```

   **Why it is wrong** — `git cherry` does not represent merge commits through ordinary patch IDs, so an ahead merge containing unique conflict-resolution content can produce no `+` line; the function returns 0 before the subsequent tree comparison and `reap_clean` can discard its telemetry.

10. **What** — PID ownership is inferred from a command-line substring rather than the identity of the original process.

    **Where** — Lines 419–420:

    ```bash
      [ -n "$p" ] && kill -0 "$p" 2>/dev/null || return 1
      ps -p "$p" -o command= 2>/dev/null | grep -qiF "$OWNER_PAT"
    ```

    **Why it is wrong** — If the PID has been reused by a newer Claude process, or by an unrelated command containing the word `claude`, the dead original session is treated as a live owner, bypassing its DEAD checkpoint/page path.

11. **What** — Horizon GC removes and clears the page for live owners it cannot distinguish from genuinely hung sessions, including the registered monitoring desk.

    **Where** — Lines 438–443 and 612:

    ```bash
        [ "$age" -ge "$GC_S" ] || continue
        pid="$(jq -r '.pid // empty' "$f" 2>/dev/null)"
        pid_alive_owner "$pid" || continue                              # GONE / recycled-non-owner → leave for assess()
        sid="$(jq -r '.session_id // empty' "$f" 2>/dev/null)"
        rm -f "$f" 2>/dev/null || true
        [ -n "$sid" ] && clear_page "$sid"
      gc="$(gc_stale)"                 # GC horizon-stale live-owner zombies FIRST — they are resolved, not a per-sweep finding
    ```

    **Why it is wrong** — A legitimately idle registered desk or the original genuinely hung Claude process satisfies both age and command-match tests, so its row and page are deleted before `assess` can apply the desk exemption; the live session then loses normal coverage and can instead trigger the blind-world self-check.

12. **What** — A telemetry row with no PID is treated as healthy or described as still running without any liveness proof.

    **Where** — Lines 464, 484, 501, and 506:

    ```bash
      if [ -n "$pid" ] && ! pid_alive_owner "$pid"; then
      if pid_alive_owner "$pid" && [ "$age" -ge "$STALL_S" ] && ! is_registered_desk "$sid"; then
      if [ "$used" -ge "$T" ] && [ "$age" -lt "$STALL_S" ]; then
      clear_page "$sid"; echo 0
    ```

    **Why it is wrong** — With an empty `.pid`, the DEAD and STALL branches are skipped; a below-threshold row is cleared as OK, while a fresh above-threshold row is paged with the unsupported assertion that it is “still running.”

13. **What** — The past-threshold guard silently misses live, productive sessions whose telemetry is stale.

    **Where** — Lines 484–486, 501, and 506:

    ```bash
      if pid_alive_owner "$pid" && [ "$age" -ge "$STALL_S" ] && ! is_registered_desk "$sid"; then
        local tage; tage="$(transcript_age "$cwd" "$cfg" "$sid")"
        if [ "$tage" -ge "$STALL_S" ]; then
      if [ "$used" -ge "$T" ] && [ "$age" -lt "$STALL_S" ]; then
      clear_page "$sid"; echo 0
    ```

    **Why it is wrong** — When `used >= T`, the PID is alive, telemetry age is at least `STALL_S`, and the transcript is warm, the stall candidate is correctly rejected but the threshold condition also rejects the row solely because telemetry is stale, so the code clears the page and produces no B-1 finding.

14. **What** — Permission-pending cleanup can page a session that is already dead.

    **Where** — Lines 537–552:

    ```bash
        tel="$TEL_DIR/$sid.json"
        if [ -f "$tel" ]; then
          pid="$(jq -r '.pid // empty' "$tel" 2>/dev/null)"
          if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
            rm -f "$bf" 2>/dev/null; clear_permpend "$sid"; continue
          fi
        fi
        if [ "$age" -ge "$PERMPEND_NOTICE_S" ]; then
          cmd="$(beacon_cmd "$bf")"
          page_permpend "$sid" "$cmd" "$ts" "$age"
    ```

    **Why it is wrong** — A reused PID makes `kill -0` succeed even though the original session died, and a clean dead session has its telemetry removed earlier in the sweep so the death test is skipped entirely; in either case a surviving beacon is reported as a live permission blockage until its horizon expires.

15. **What** — The telemetry self-check compares live processes against all telemetry files rather than telemetry-covered live sessions.

    **Where** — Lines 591, 614–616, and 626:

    ```bash
      delta=$(( live - enum ))
        for f in "$TEL_DIR"/*.json; do
          [ -e "$f" ] || continue
          n=$((n+1)); r="$(assess "$f")"; found=$(( found + ${r:-0} ))
      self_check "$n"
    ```

    **Why it is wrong** — Dead, duplicate, malformed, or subsequently reaped rows are included in `n`, so one such row can numerically cancel one live pane missing from telemetry and suppress the blind-spot page.

16. **What** — Failure to read the process table is interpreted as a valid live-pane count of zero rather than an indeterminate result.

    **Where** — Lines 576–581 and 589–594:

    ```bash
      ps -wwEo command= 2>/dev/null | awk '
        { t0=$1
          if (t0!="claude" && t0!="claude.exe" && t0 !~ /\/claude$/ && t0 !~ /\/claude\.exe$/ && t0 !~ /cli\.js/) next
          for (i=2; i<=7 && i<=NF; i++) if ($i=="-p" || $i=="--print" || $i=="--version") next
          c++ }
        END { print c+0 }'
      live="$(live_pane_count)"
      case "$live" in ''|*[!0-9]*) return 0 ;; esac      # unreadable ps ⇒ ABSTAIN (no verdict), never a phantom Δ
      delta=$(( live - enum ))
      sf="$PAGEDIR/selfcheck.state"
      if [ "$delta" -le "$PANE_DELTA_TOL" ]; then
        _ensure; printf '0 0\n' > "$sf" 2>/dev/null || true   # re-arm on recovery
    ```

    **Why it is wrong** — Even when `ps` fails, `awk` executes its `END` block and prints `0`; the ignored nonzero pipeline status leaves a numeric `live`, so the code takes the recovery branch and resets self-check state instead of abstaining.

17. **What** — Headless Claude invocations are excluded only when their identifying option occurs among arguments 2 through 7.

    **Where** — Line 579:

    ```bash
          for (i=2; i<=7 && i<=NF; i++) if ($i=="-p" || $i=="--print" || $i=="--version") next
    ```

    **Why it is wrong** — A valid invocation with `-p`, `--print`, or `--version` after the seventh field is counted as an interactive pane, so a sufficiently long-running one-shot process can create a false missing-telemetry alarm.

18. **What** — The self-check falsely reports that permission-beacon coverage depends on telemetry.

    **Where** — Lines 529–530 and 601:

    ```bash
      [ -d "$dir" ] || { echo 0; return; }
      for bf in "$dir"/*.json; do
        idl selfcheck_page "\"live\":$live,\"enumerated\":$enum,\"delta\":$delta,\"persisted_sweeps\":$consec,\"why\":\"$delta live Claude pane(s) are absent from the supervisor's telemetry world-view — they have NO pager coverage on any path (DEAD/STALL?/PAST-THRESHOLD/permission-beacon all iterate that dir)\""
    ```

    **Why it is wrong** — Permission beacons are enumerated directly from `PERMPEND_DIR`, independently of `TEL_DIR`, so the operator-facing diagnostic incorrectly says that this coverage is absent.

19. **What** — Failure to create the durable page timestamp is ignored, preventing deadline resolution while the page can still be treated as handled.

    **Where** — Lines 180 and 196:

    ```bash
    _ensure(){ mkdir -p "$(dirname "$IDL")" "$(dirname "$SUPLOG")" "$PAGEDIR" 2>/dev/null || true; }
      [ -f "$pf" ] || printf '%s\n' "$(now)" > "$pf"           # stamp the deadline clock on first page only
    ```

    **Why it is wrong** — If directory creation or the page-file write fails, execution continues through notification, but later sweeps keep seeing no pre-existing page and therefore never call `resolve_page` for that incident.

20. **What** — Valid filesystem paths and telemetry values are inserted into IDL JSON without JSON encoding.

    **Where** — Lines 326, 329, and 364:

    ```bash
        idl checkpoint_timeout "\"sid\":\"$1\",\"cwd\":\"$cwd\",\"bound_s\":$SUP_CKPT_TIMEOUT_S,\"why\":\"teammate-checkpoint.sh exceeded its bound and was cut — the dead lead's worktree is NOT checkpoint-preserved; the DEAD page below still fires\""
      idl checkpoint "\"sid\":\"$1\",\"cwd\":\"$cwd\",\"why\":\"dead-lead-preserve\""
      idl reap "\"sid\":\"$1\",\"cwd\":\"$2\",\"why\":\"clean-completion-shipped-clean-worktree\""
    ```

    **Why it is wrong** — A legal `cwd` containing a quote, backslash, or newline produces malformed JSON or splits one event across lines, corrupting the audit stream.

21. **What** — Cleanup operations claim successful removal even when `rm` fails.

    **Where** — Lines 217, 365–367, and 442–445:

    ```bash
    clear_page(){ rm -f "$PAGEDIR/$1.page" "$PAGEDIR/$1.notified" 2>/dev/null || true; }
      rm -f "$TEL_DIR/$1.json" 2>/dev/null || true
      clear_page "$1"
      printf '%s  reap sid=%s (clean+landed — dispatched-worker lifecycle end)\n' "$(utc)" "$1" >> "$SUPLOG" 2>/dev/null || true
        rm -f "$f" 2>/dev/null || true
        [ -n "$sid" ] && clear_page "$sid"
        idl gc "\"sid\":\"${sid:-unknown}\",\"age\":$age,\"horizon\":$GC_S,\"pid\":\"${pid:-}\",\"why\":\"live-owner pid on telemetry ${age}s stale >= ${GC_S}s horizon — hung or pid-recycled owner; dropped the row so it stops re-paging every sweep\""
        g=$((g+1))
    ```

    **Why it is wrong** — With an unwritable directory or other deletion error, the telemetry or page state remains, but the function logs a reap or GC, increments the GC count, and returns success as though the state had been removed.

22. **What** — An unvalidated telemetry session ID is used directly in paths that are written and deleted.

    **Where** — Lines 195, 217, 365, and 453:

    ```bash
      local pf="$PAGEDIR/$1.page" nf="$PAGEDIR/$1.notified"
    clear_page(){ rm -f "$PAGEDIR/$1.page" "$PAGEDIR/$1.notified" 2>/dev/null || true; }
      rm -f "$TEL_DIR/$1.json" 2>/dev/null || true
      sid="$(jq -r '.session_id // empty' "$f" 2>/dev/null)"; [ -n "$sid" ] || { echo 0; return; }
    ```

    **Why it is wrong** — A telemetry row whose nonempty `session_id` contains `/` or `..` can make page creation, page cleanup, or clean reaping access files outside the intended page or telemetry directory.