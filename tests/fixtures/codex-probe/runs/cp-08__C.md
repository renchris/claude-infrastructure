I found 20 defects.

1. **What** — Outcome records are best-effort even though every decision is claimed to be recorded.

   **Where** — Lines 132 and 144:

   ```bash
     mkdir -p "$RECORDS_DIR" 2>/dev/null || true
       > "$RECORDS_DIR/${ts}.json" 2>/dev/null || true
   ```

   **Why it is wrong** — If the directory is unwritable or the disk is full, recording silently fails and the script still returns the teardown decision as though the required audit record existed.

2. **What** — Teardown-marker failures are silently treated as successful marker writes.

   **Where** — Lines 162, 166, 170, and 172:

   ```bash
     mkdir -p "$_tm_dir" 2>/dev/null || true
         "$_tm_pane" "$_tm_sid" "$_tm_mode" "$_tm_ts" > "$_tm_dir/$_tm_sid.json" 2>/dev/null || true
         "$_tm_pane" "$_tm_sid" "$_tm_mode" "$_tm_ts" > "$_tm_dir/$_tm_pane.json" 2>/dev/null || true
     return 0
   ```

   **Why it is wrong** — When either marker cannot be written, teardown proceeds and may return success, while the target watchdog lacks the evidence needed to distinguish the deliberate teardown from a crash.

3. **What** — `pane_present` incorrectly uses list length as evidence that an enumeration is either blind or complete.

   **Where** — Lines 191–194:

   ```bash
     [ "$n" -eq 0 ] && return 2                        # zero enumerated ⇒ blind enumerator ⇒ indeterminate
     ids="$(printf '%s' "$lst" | jq -r '.[].id // empty' 2>/dev/null)" || return 2
     printf '%s\n' "$ids" | grep -qxF "$uuid" && return 0
     return 1
   ```

   **Why it is wrong** — A launchd reaper can legitimately observe no panes, causing an already-gone target to be reported indeterminate, while an incomplete but nonempty enumeration is treated as complete and can falsely verify an omitted surviving pane as gone.

4. **What** — Assignee resolution does not actually prove that `--agent-id` is a real argv token.

   **Where** — Lines 261–264:

   ```bash
       case " $rargs " in *" --agent-id "*) ;; *) continue ;; esac
       agid="${rargs#*--agent-id }"; agid="${agid%% *}"   # the token AFTER the real flag
       case "$agid" in
         *"@session-$lead") ;;                            # proves assignee OF THIS dead lead
   ```

   **Why it is wrong** — `ps ... args=` is flattened text without argument boundaries, so an unrelated `claude.exe` whose prose argument contains `--agent-id name@session-<lead>` is accepted as the assignee and can be killed.

5. **What** — Failure to enumerate processes on the target TTY is interpreted as zero foreign processes.

   **Where** — Lines 291 and 313:

   ```bash
     tbl="$("$PS_BIN" -t "$tty" -o pid=,ppid=,comm= 2>/dev/null)"
     echo "$fp"
   ```

   **Why it is wrong** — If the second `ps` command fails and produces no output, its status is ignored, both loops are empty, `fp` remains zero, and teardown proceeds without establishing TTY exclusivity.

6. **What** — The TTY guard treats processes as harmless interactive shells based only on their executable name.

   **Where** — Line 308:

   ```bash
       case "$base" in -zsh|zsh|-bash|bash|-sh|sh|login|tmux|screen|gitstatusd*|caffeinate) continue ;; esac
   ```

   **Why it is wrong** — A foreign noninteractive process such as `bash long-running-job.sh` has `comm` equal to `bash`, is silently excluded from the count, and may be terminated when the pane closes.

7. **What** — Resolving by name silently selects the first match when multiple sessions have the same name.

   **Where** — Lines 318–320:

   ```bash
     obj="$("$CC_SESSIONS" --all --json 2>/dev/null | jq -c --arg t "$t" \
        '(map(select(.paneUUID==$t)) + map(select(.name==$t))) | .[0] // empty' 2>/dev/null)"
     [ -n "$obj" ] || return 1
   ```

   **Why it is wrong** — With two rows sharing the requested name, array order alone determines which pane and process are torn down, even though the target is ambiguous.

8. **What** — The self-teardown guard is skipped when the invoking pane UUID cannot be determined.

   **Where** — Line 426:

   ```bash
     if [ -n "$SELF_UUID" ] && [ "$paneUUID" = "$SELF_UUID" ]; then
   ```

   **Why it is wrong** — If both `CC_TEARDOWN_SELF_UUID` and `ITERM_SESSION_ID` are absent or empty, targeting the invoking pane does not trigger this guard and the script can kill and close its own session.

9. **What** — Missing operands for the identity-pin options silently disable the requested checks.

   **Where** — Lines 382–383:

   ```bash
         --expect-pid)    [ $# -ge 2 ] && { EXPECT_PID="$2"; shift 2; } || shift ;;
         --expect-lstart) [ $# -ge 2 ] && { EXPECT_LSTART="$2"; shift 2; } || shift ;;
   ```

   **Why it is wrong** — If either option is the final argument, it is merely discarded; with no other pin populated, the identity-pin block is skipped and teardown can act despite the caller having requested identity protection.

10. **What** — An absent unregistered-assignee pane is reported as fully verified success without proving either target identity or process death.

    **Where** — Lines 411–412:

    ```bash
            1) record ALREADY-GONE idempotent "assignee pane '$TARGET' is absent from a READABLE it2 enumeration — nothing to close" 1
               say "OK — assignee pane already gone (idempotent success, exit 0)"; exit 0 ;;
    ```

    **Why it is wrong** — Any nonexistent or mistyped pane passed with `--assignee-of` reaches this success branch, and a detached surviving assignee process is also possible because no PID was discovered or checked.

11. **What** — An explicit start-time identity pin is silently ignored when the current start time cannot be read.

    **Where** — Lines 438–440:

    ```bash
       local now_lstart; now_lstart="$(pid_lstart "$pid")"
       if { [ -n "$EXPECT_PID" ] && [ "$pid" != "$EXPECT_PID" ]; } || \
          { [ -n "$EXPECT_LSTART" ] && [ -n "$now_lstart" ] && [ "$now_lstart" != "$EXPECT_LSTART" ]; }; then
    ```

    **Why it is wrong** — If `ps` transiently fails while a reused PID is alive, `now_lstart` is empty, the mismatch clause is false, and the successor can pass the identity guard.

12. **What** — `pid_alive` misclassifies missing or unprobeable PIDs as dead and terminated zombies as alive.

    **Where** — Lines 175, 322, 327, and 596–597:

    ```bash
    pid_alive()  { [ -n "${1:-}" ] && kill -0 "$1" 2>/dev/null; }
      pid="$(printf '%s'      "$obj" | jq -r '.pid // empty')"
      [ -n "$paneUUID" ] || return 1
      if ! pid_alive "$pid"; then
        proc_gone=1
    ```

    **Why it is wrong** — A row with no PID, an invalid PID, or a live PID returning `EPERM` can be certified process-gone without observation and produce exit 0 after the pane disappears, while a zombie makes `kill -0` succeed and can produce exit 5 even though execution has terminated.

13. **What** — A missing target transcript bypasses both the transcript-based adoption check and the presence-beat backstop.

    **Where** — Lines 487 and 494:

    ```bash
          atj="$(find_transcript "$sess_id" 2>/dev/null || true)"
          if [ -n "$atj" ]; then
    ```

    **Why it is wrong** — When an operator-controlled session has a missing or renamed transcript, `atj` is empty, the entire check is skipped, and the pane can be closed despite a recent operator prompt or presence beat.

14. **What** — The freshness lease classifies every normal invocation carrying the required done evidence as autonomous.

    **Where** — Lines 100, 120, 521, 524–525, and 531:

    ```bash
    DECIDED_AT=""
    cc-teardown <pane-uuid|name> --done-evidence <text> [--force-adopted]
      if [ "${CC_REAP_LEASE:-on}" != off ] && [ "$FORCE_ADOPTED" = 0 ] && [ -n "$done_ev" ]; then
        case "$DECIDED_AT" in
          ''|*[!0-9]*)
            exit 2 ;;
    ```

    **Why it is wrong** — The documented manual command necessarily has nonempty `done_ev` but supplies no documented `--decided-at`, so an otherwise safe manual teardown is refused as `lease-missing`.

15. **What** — TTY exclusivity is not checked at all when the registered target PID is already dead.

    **Where** — Line 560:

    ```bash
      if pid_alive "$pid"; then
    ```

    **Why it is wrong** — If Claude has exited but its pane contains a foreign live job such as `vim` or a script, this whole guard is skipped and the subsequent pane close can terminate that job.

16. **What** — The identity, adoption, work-safety, and TTY checks are mutable snapshots that are not made current at the point of action.

    **Where** — Lines 506, 548, 561, and 583:

    ```bash
              if [ "$iage" -lt "$INTERACTIVE_HOLD_S" ] && [ "$iep" -gt "$(( spawn_s + FIRE_PROMPT_SLACK_S ))" ]; then
      gate_out="$("$GATE" decide --cwd "$cwd" --done-evidence "$done_ev" 2>/dev/null)"; grc=$?
        local fc; fc="$(tty_foreign "$pid")"
        kill -TERM "$pid" 2>/dev/null || true
    ```

    **Why it is wrong** — An operator can type, the target can dirty its worktree or recycle its PID, or a foreign process can enter the TTY after its corresponding check but before `kill`, causing teardown to act on a premise that is no longer true.

17. **What** — A failed or interrupted teardown leaves a successful teardown marker attached to a still-live target.

    **Where** — Lines 576, 579, and 610–611:

    ```bash
      write_teardown_marker "$paneUUID" "$sess_id" teardown
      local lstart_before; lstart_before="$(pid_lstart "$pid")"
      record FAILED not-verified "effect-verify FAILED (re-observed): proc_gone=$proc_gone pane_gone=$pane_gone close_rc=$close_rc — LOUD, never a false success" 0
      say "FAIL — teardown NOT verified: proc_gone=$proc_gone pane_gone=$pane_gone close_rc=$close_rc (exit 5)"; exit 5
    ```

    **Why it is wrong** — If the script hangs or is interrupted before signaling, or both action legs fail and the target survives, the marker remains and can cause a later genuine crash to be classified as deliberate teardown.

18. **What** — The self-test ignores the script’s own symlink resolution when locating the safety gate.

    **Where** — Lines 624–625:

    ```bash
      SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
      GATE_SELF="$(cd "$(dirname "$0")" && pwd)/cc-teardown-safety-gate.sh"
    ```

    **Why it is wrong** — When `cc-teardown` is invoked through the supported lone symlink, `$0` names the symlink directory, so `GATE_SELF` points to a nonexistent sibling instead of the repository sibling and the self-test fails for the wrong reason.

19. **What** — The self-test’s normal iTerm enumeration can never represent a legitimate machine with zero panes.

    **Where** — Line 654:

    ```bash
      jq -n --slurpfile a "$PF" '($a[0] + ["DESK-PANE-PERSIST-0000"]) | unique | map({id: .})'; exit 0
    ```

    **Why it is wrong** — The mock always injects a desk pane, although the sanctioned launchd reaper has no invoking pane, so the idempotence test cannot expose the production misclassification of a valid empty enumeration.

20. **What** — The self-test assertion claiming that every decision branch records an outcome checks only the immediately preceding branch.

    **Where** — Lines 834–835:

    ```bash
      [ -n "$(last_decision)" ] && okp "no-silent-record: every decision branch writes an outcome record" \
        || badp "a decision was SILENT (no record) — an unauditable teardown"
    ```

    **Why it is wrong** — A record from the preceding identity-pin test makes this assertion pass even though unexercised branches, such as malformed-invocation and TTY-indeterminate paths, may produce no record.