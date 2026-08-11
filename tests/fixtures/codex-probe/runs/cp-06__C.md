1. **What** — Failure to create the page deadline file is ignored, preventing the deadline re-observation from ever running.

   **Where** — Lines 193, 282, and 491–493:

   ```bash
     [ -f "$pf" ] || printf '%s\n' "$(now)" > "$pf"           # stamp the deadline clock on first page only
     [ -f "$pf" ] || return 0
         local had_page=0; [ -f "$PAGEDIR/$sid.page" ] && had_page=1
         page "$sid" "STALL?" "pid alive but telemetry ${age}s + transcript ${tage}s stale — CANDIDATE; re-observing effects at deadline"
         [ "$had_page" = 1 ] && resolve_page "$sid" "$cwd"
   ```

   **Why it is wrong** — If the page directory is unwritable or full, every sweep continues to report the page, but `had_page` remains zero and `resolve_page` immediately returns, so the incident can never become `ESCALATED`.

2. **What** — The effects re-read classifies several failed probes as `dark` because only exit status 124 is treated as `unknown`.

   **Where** — Lines 254–255, 261–263, 269–272, and 276:

   ```bash
       last_commit="$(sup_git -C "$cwd" log -1 --format=%ct 2>/dev/null)"; rc=$?
       [ "$rc" = 124 ] && { printf 'unknown'; return; }
         local ref; ref="$(mktemp 2>/dev/null)"
         if [ -n "$ref" ]; then
           touch -t "$(date -r "$since" +%Y%m%d%H%M.%S 2>/dev/null || echo 197001010000)" "$ref" 2>/dev/null
           hit="$(sup_bounded "$SUP_FIND_TIMEOUT_S" find "$cwd" \( -name .git -o -name tmp -o -name node_modules -o -name .venv -o -name venv -o -name __pycache__ -o -name .next -o -name dist -o -name .worktrees \) -prune -o -type f -newer "$ref" -print -quit 2>/dev/null)"; rc=$?
           rm -f "$ref"
           [ "$rc" = 124 ] && { printf 'unknown'; return; }
           [ -n "$hit" ] && verdict=fresh
     printf '%s' "$verdict"
   ```

   **Why it is wrong** — If `mktemp` fails, or Git/find exits with another error and no output, the code has not established that there were no effects, but it prints `dark` and the caller escalates the session.

3. **What** — A commit made after the page can be missed when it has the same whole-second timestamp as the page.

   **Where** — Lines 193, 254, and 256:

   ```bash
     [ -f "$pf" ] || printf '%s\n' "$(now)" > "$pf"           # stamp the deadline clock on first page only
       last_commit="$(sup_git -C "$cwd" log -1 --format=%ct 2>/dev/null)"; rc=$?
       [ "${last_commit:-0}" -gt "$since" ] 2>/dev/null && verdict=fresh
   ```

   **Why it is wrong** — Both timestamps have one-second resolution, so a pre-staged commit made later in the same second compares equal rather than greater; with no newer worktree file, it is reported as `dark`.

4. **What** — The DEAD checkpoint path can claim preservation when no successful checkpoint has been established.

   **Where** — Lines 309–311, 316, 318, 321–324, and 470:

   ```bash
     local cwd="$2" rc=0
     [ -n "$cwd" ] && [ -d "$cwd" ] || return 0
     if command -v teammate-checkpoint.sh >/dev/null 2>&1; then
       CC_CHECKPOINT_MEMBER="supervisor-$1" sup_bounded "$SUP_CKPT_TIMEOUT_S" teammate-checkpoint.sh "$cwd" >/dev/null 2>&1 || rc=$?
     if [ "$rc" = 124 ]; then
       idl checkpoint_timeout "\"sid\":\"$1\",\"cwd\":\"$cwd\",\"bound_s\":$SUP_CKPT_TIMEOUT_S,\"why\":\"teammate-checkpoint.sh exceeded its bound and was cut — the dead lead's worktree is NOT checkpoint-preserved; the DEAD page below still fires\""
       return 0
     fi
     idl checkpoint "\"sid\":\"$1\",\"cwd\":\"$cwd\",\"why\":\"dead-lead-preserve\""
       checkpoint_preserve "$sid" "$cwd"; page "$sid" DEAD "$why; worktree checkpoint-preserved"; echo 1; return
   ```

   **Why it is wrong** — A missing helper or any non-124 failure still produces a successful `checkpoint` record, while a missing worktree or recognized timeout skips preservation but the subsequent DEAD page nevertheless says it was checkpoint-preserved.

5. **What** — The clean-tree check ignores the exit status of `git status`, allowing an unproved tree to be treated as clean.

   **Where** — Lines 341–343:

   ```bash
     [ -z "$(sup_git -C "$cwd" status --porcelain 2>/dev/null)" ] || return 1
     local ahead; ahead="$(sup_git -C "$cwd" rev-list --count "$TRUNK"..HEAD 2>/dev/null)" || return 1
     [ "${ahead:-1}" = 0 ] && return 0                                 # fast path: 0 ahead by COUNT → landed
   ```

   **Why it is wrong** — If `git status` times out or otherwise fails without output, `-z` succeeds; if the later ahead count is zero, dirty or unreadable work is declared clean and the telemetry can be reaped.

6. **What** — The `git cherry` test can interpret an actual `+` match as no match because `pipefail` observes `printf` failing after `grep -q` exits early.

   **Where** — Lines 28 and 348:

   ```bash
   set -uo pipefail
       printf '%s\n' "$cherry_out" | grep -q '^+' || return 0
   ```

   **Why it is wrong** — With sufficiently large output and an early `+`, `grep -q` closes the pipe after matching and `printf` can receive SIGPIPE, making the pipeline nonzero and executing `return 0`; unlanded commits are then classified as landed.

7. **What** — The main page, checkpoint, reap, and GC records interpolate dynamic strings directly into JSON without encoding them.

   **Where** — Lines 194, 321, 324, 360, and 442:

   ```bash
     idl page "\"sid\":\"$1\",\"state\":\"$2\",\"detail\":\"$3\""
       idl checkpoint_timeout "\"sid\":\"$1\",\"cwd\":\"$cwd\",\"bound_s\":$SUP_CKPT_TIMEOUT_S,\"why\":\"teammate-checkpoint.sh exceeded its bound and was cut — the dead lead's worktree is NOT checkpoint-preserved; the DEAD page below still fires\""
     idl checkpoint "\"sid\":\"$1\",\"cwd\":\"$cwd\",\"why\":\"dead-lead-preserve\""
     idl reap "\"sid\":\"$1\",\"cwd\":\"$2\",\"why\":\"clean-completion-shipped-clean-worktree\""
       idl gc "\"sid\":\"${sid:-unknown}\",\"age\":$age,\"horizon\":$GC_S,\"pid\":\"${pid:-}\",\"why\":\"live-owner pid on telemetry ${age}s stale >= ${GC_S}s horizon — hung or pid-recycled owner; dropped the row so it stops re-paging every sweep\""
   ```

   **Why it is wrong** — A valid worktree path containing a quote, backslash, or newline, or an unexpected telemetry string with those characters, produces malformed or multi-line JSON instead of the required durable IDL record.

8. **What** — The clean-reap and GC paths report and count successful removal even when removal fails.

   **Where** — Lines 360–363 and 440–443:

   ```bash
     idl reap "\"sid\":\"$1\",\"cwd\":\"$2\",\"why\":\"clean-completion-shipped-clean-worktree\""
     rm -f "$TEL_DIR/$1.json" 2>/dev/null || true
     clear_page "$1"
     printf '%s  reap sid=%s (clean+landed — dispatched-worker lifecycle end)\n' "$(utc)" "$1" >> "$SUPLOG" 2>/dev/null || true
       rm -f "$f" 2>/dev/null || true
       [ -n "$sid" ] && clear_page "$sid"
       idl gc "\"sid\":\"${sid:-unknown}\",\"age\":$age,\"horizon\":$GC_S,\"pid\":\"${pid:-}\",\"why\":\"live-owner pid on telemetry ${age}s stale >= ${GC_S}s horizon — hung or pid-recycled owner; dropped the row so it stops re-paging every sweep\""
       g=$((g+1))
   ```

   **Why it is wrong** — If directory permissions or a filesystem error prevents deletion, the row remains, but the code clears its page, records a reap/GC, and increments the heartbeat’s GC count as though deletion succeeded.

9. **What** — GC deletes horizon-stale live-owner rows before the warm-transcript and registered-desk exemptions can assess them.

   **Where** — Lines 436–441 and 612:

   ```bash
       [ "$age" -ge "$GC_S" ] || continue
       pid="$(jq -r '.pid // empty' "$f" 2>/dev/null)"
       pid_alive_owner "$pid" || continue                              # GONE / recycled-non-owner → leave for assess()
       sid="$(jq -r '.session_id // empty' "$f" 2>/dev/null)"
       rm -f "$f" 2>/dev/null || true
       [ -n "$sid" ] && clear_page "$sid"
     gc="$(gc_stale)"                 # GC horizon-stale live-owner zombies FIRST — they are resolved, not a per-sweep finding
   ```

   **Why it is wrong** — A genuinely live session with a warm transcript, an idle registered desk, or a genuinely hung owner all satisfy this guard once telemetry reaches `GC_S`; their telemetry and standing page are removed before `assess` can distinguish or report them.

10. **What** — `pid_alive_owner` does not establish ownership because it accepts any live process whose command line contains `OWNER_PAT`.

    **Where** — Lines 88 and 415–416:

    ```bash
    OWNER_PAT="${CC_SUP_OWNER_PAT:-claude}"               # a live pid OWNS its telemetry row only if its process command matches this — kill -0 alone reads a RECYCLED pid as the original session (the STALL? zombie)
      [ -n "$p" ] && kill -0 "$p" 2>/dev/null || return 1
      ps -p "$p" -o command= 2>/dev/null | grep -qiF "$OWNER_PAT"
    ```

    **Why it is wrong** — If the PID is recycled to a newer Claude process or an unrelated process with `claude` in an argument or pathname, the old session is treated as its owner, so DEAD checkpoint/reap handling is skipped and the stale row may later be GC’d.

11. **What** — A telemetry row with an absent PID bypasses both DEAD and STALL classification and can be cleared as OK.

    **Where** — Lines 456, 462, 482, and 504:

    ```bash
      pid="$(jq -r '.pid // empty' "$f" 2>/dev/null)"
      if [ -n "$pid" ] && ! pid_alive_owner "$pid"; then
      if pid_alive_owner "$pid" && [ "$age" -ge "$STALL_S" ] && ! is_registered_desk "$sid"; then
      clear_page "$sid"; echo 0
    ```

    **Why it is wrong** — With a missing `.pid` and usage below the threshold, both ownership tests are false and execution reaches the OK branch, removing any existing page even though no live owner was proved.

12. **What** — The B-1 predicate never tests `NOT-STOPPING` and incorrectly makes fresh telemetry a requirement.

    **Where** — Lines 499–500:

    ```bash
      if [ "$used" -ge "$T" ] && [ "$age" -lt "$STALL_S" ]; then
        page "$sid" PAST-THRESHOLD "used ${used}% ≥ ${T}% and still running (not Stopping) — the boundary hook is blind here; advise /handoff"
    ```

    **Why it is wrong** — A fresh session already in its stopping path satisfies the condition and is falsely described as not stopping, while a genuinely live, non-stopping session with stale telemetry but a warm transcript fails the age test and is cleared without the promised threshold page.

13. **What** — Permission-beacon cleanup uses `kill -0` alone, so a recycled PID keeps a dead permission prompt alive.

    **Where** — Lines 537–540:

    ```bash
        if [ -f "$tel" ]; then
          pid="$(jq -r '.pid // empty' "$tel" 2>/dev/null)"
          if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
            rm -f "$bf" 2>/dev/null; clear_permpend "$sid"; continue
    ```

    **Why it is wrong** — If the original session dies and its PID is reused by any process, `kill -0` succeeds, so the orphan beacon is retained and can generate a `PERMISSION-PENDING` page for a prompt that no longer exists.

14. **What** — The telemetry side of the self-check counts JSON files rather than live, valid, distinct covered sessions.

    **Where** — Lines 591, 613–616, and 626:

    ```bash
      delta=$(( live - enum ))
      if [ -d "$TEL_DIR" ]; then
        for f in "$TEL_DIR"/*.json; do
          [ -e "$f" ] || continue
          n=$((n+1)); r="$(assess "$f")"; found=$(( found + ${r:-0} ))
      self_check "$n"
    ```

    **Why it is wrong** — A dead, malformed, duplicate, or even same-sweep-reaped row increases `enum`; for example, one dead persistent row can exactly mask one live pane with no telemetry, yielding delta zero and suppressing the blind-spot page.

15. **What** — A failed `ps` probe is converted to numeric zero, so self-check treats an unreadable live-process view as a successful zero count.

    **Where** — Lines 575–582 and 589–594:

    ```bash
    live_pane_count(){
      ps -wwEo command= 2>/dev/null | awk '
        { t0=$1
          if (t0!="claude" && t0!="claude.exe" && t0 !~ /\/claude$/ && t0 !~ /\/claude\.exe$/ && t0 !~ /cli\.js/) next
          for (i=2; i<=7 && i<=NF; i++) if ($i=="-p" || $i=="--print" || $i=="--version") next
          c++ }
        END { print c+0 }'
    }
      live="$(live_pane_count)"
      case "$live" in ''|*[!0-9]*) return 0 ;; esac      # unreadable ps ⇒ ABSTAIN (no verdict), never a phantom Δ
      delta=$(( live - enum ))
      sf="$PAGEDIR/selfcheck.state"
      if [ "$delta" -le "$PANE_DELTA_TOL" ]; then
        _ensure; printf '0 0\n' > "$sf" 2>/dev/null || true   # re-arm on recovery
    ```

    **Why it is wrong** — When `ps` fails, `awk` still executes its `END` block and prints `0`; the numeric check therefore does not abstain and the code can reset an existing blind-spot alarm as recovered.

16. **What** — The live-process classifier only checks arguments 2 through 7 for headless-mode flags.

    **Where** — Line 579:

    ```bash
          for (i=2; i<=7 && i<=NF; i++) if ($i=="-p" || $i=="--print" || $i=="--version") next
    ```

    **Why it is wrong** — A headless Claude invocation with `-p`, `--print`, or `--version` at field 8 or later is counted as an interactive pane, inflating `live` and potentially producing a false telemetry blind-spot page.

17. **What** — A self-check finding is never added to `found`, allowing the same sweep’s heartbeat to claim zero findings.

    **Where** — Lines 601, 623, and 626–627:

    ```bash
        idl selfcheck_page "\"live\":$live,\"enumerated\":$enum,\"delta\":$delta,\"persisted_sweeps\":$consec,\"why\":\"$delta live Claude pane(s) are absent from the supervisor's telemetry world-view — they have NO pager coverage on any path (DEAD/STALL?/PAST-THRESHOLD/permission-beacon all iterate that dir)\""
      pp="$(sweep_permission_pending)"; found=$(( found + ${pp:-0} ))
      self_check "$n"
      heartbeat "$n" "$found" "$gc"
    ```

    **Why it is wrong** — When telemetry and permission assessment find nothing but `self_check` emits `selfcheck_page`, `found` remains zero and the immediately following heartbeat falsely records an all-clear outcome.