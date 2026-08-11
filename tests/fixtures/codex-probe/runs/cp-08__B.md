1. **What** — The self-teardown guard is silently disabled when neither self-UUID environment variable is populated.

   **Where** — Lines 84–85 and 429:

   ```bash
   _sid="${CC_TEARDOWN_SELF_UUID:-${ITERM_SESSION_ID:-}}"
   SELF_UUID="${_sid##*:}"   # ITERM_SESSION_ID = "wNtMpK:<UUID>" → <UUID>; an injected bare UUID passes through
   ```

   ```bash
     if [ -n "$SELF_UUID" ] && [ "$paneUUID" = "$SELF_UUID" ]; then
   ```

   **Why it is wrong** — When a live desk invokes the command without either variable, `SELF_UUID` is empty and its own pane passes the guard, allowing self-termination, especially with the adoption override.

2. **What** — Outcome recording is best-effort even though every decision branch is claimed to produce a record.

   **Where** — Lines 133 and 145:

   ```bash
     mkdir -p "$RECORDS_DIR" 2>/dev/null || true
   ```

   ```bash
       > "$RECORDS_DIR/${ts}.json" 2>/dev/null || true
   ```

   **Why it is wrong** — If the directory cannot be created or the file cannot be written, the failure is discarded and teardown continues or exits without the mandatory audit record.

3. **What** — A valid empty iTerm session list is always classified as unreadable rather than as proof that the target pane is absent.

   **Where** — Line 193:

   ```bash
     [ "$n" -eq 0 ] && return 2                        # zero enumerated ⇒ blind enumerator ⇒ indeterminate
   ```

   **Why it is wrong** — When a launchd reaper closes the last real pane, a fresh legitimate list is `[]`; verification then leaves `pane_gone=0` and reports exit 5 although the pane was successfully closed.

4. **What** — Assignee identity detection mistakes text inside an arbitrary argument for a real `--agent-id` argv token.

   **Where** — Lines 264–267 and 284:

   ```bash
       case " $rargs " in *" --agent-id "*) ;; *) continue ;; esac
       agid="${rargs#*--agent-id }"; agid="${agid%% *}"   # the token AFTER the real flag
       case "$agid" in
         *"@session-$lead") ;;                            # proves assignee OF THIS dead lead
   ```

   ```bash
     done < <("$PS_BIN" -t "$base" -o pid=,args= 2>/dev/null)
   ```

   **Why it is wrong** — `ps ... args=` provides one flattened textual representation without argv boundaries, so a task argument containing `--agent-id name@session-lead` can satisfy these tests and cause an unrelated `claude.exe` process to be adopted and killed.

5. **What** — Failure to enumerate the TTY process table is interpreted as proof that no foreign processes exist.

   **Where** — Lines 294 and 316:

   ```bash
     tbl="$("$PS_BIN" -t "$tty" -o pid=,ppid=,comm= 2>/dev/null)"
   ```

   ```bash
     echo "$fp"
   ```

   **Why it is wrong** — If `ps -t` fails or returns no data, its status is ignored, both loops see an empty table, and `tty_foreign` returns zero, allowing a shared pane to be closed without establishing exclusivity.

6. **What** — Resolving a non-unique session name silently selects the first match.

   **Where** — Lines 321–322:

   ```bash
     obj="$("$CC_SESSIONS" --all --json 2>/dev/null | jq -c --arg t "$t" \
        '(map(select(.paneUUID==$t)) + map(select(.name==$t))) | .[0] // empty' 2>/dev/null)"
   ```

   **Why it is wrong** — When two live sessions have the same name, their ordering determines which one is killed and closed even though the requested target is ambiguous.

7. **What** — An absent unregistered-assignee pane is reported as having both teardown legs verified without checking its process leg.

   **Where** — Lines 414–415:

   ```bash
           1) record ALREADY-GONE idempotent "assignee pane '$TARGET' is absent from a READABLE it2 enumeration — nothing to close" 1
              say "OK — assignee pane already gone (idempotent success, exit 0)"; exit 0 ;;
   ```

   **Why it is wrong** — An assignee process may remain orphaned or detached after its pane disappears, but this branch has not resolved or tested any PID and nevertheless exits successfully with `both_legs_verified=true`.

8. **What** — The identity pin proceeds when the requested launch-time observation cannot be obtained.

   **Where** — Lines 440–443:

   ```bash
     if [ -n "$EXPECT_PID" ] || [ -n "$EXPECT_LSTART" ]; then
       local now_lstart; now_lstart="$(pid_lstart "$pid")"
       if { [ -n "$EXPECT_PID" ] && [ "$pid" != "$EXPECT_PID" ]; } || \
          { [ -n "$EXPECT_LSTART" ] && [ -n "$now_lstart" ] && [ "$now_lstart" != "$EXPECT_LSTART" ]; }; then
   ```

   **Why it is wrong** — If `--expect-lstart` was supplied but `ps` fails and returns an empty `now_lstart`, the mismatch test is skipped and the script acts despite being unable to verify the pinned identity.

9. **What** — A malformed interactive-hold threshold disables the operator-adoption guard.

   **Where** — Line 473:

   ```bash
     case "$INTERACTIVE_HOLD_S" in ''|*[!0-9]*|0) hold_on=0 ;; esac
   ```

   **Why it is wrong** — A typo or malformed `CC_CLASSIFY_INTERACTIVE_HOLD_S` value silently turns off the safety belt, allowing an operator-adopted pane to proceed toward teardown.

10. **What** — A missing target transcript bypasses both operator-presence oracles.

    **Where** — Lines 493 and 501:

    ```bash
         atj="$(find_transcript "$sess_id" 2>/dev/null || true)"
    ```

    ```bash
         if [ -n "$atj" ]; then
    ```

    **Why it is wrong** — When the interactive library exists but the transcript cannot be found, the entire scan is skipped and `beat_or_refuse` is never called, so a live operator conversation can be closed without any proof of operator absence.

11. **What** — The documented manual invocation is incorrectly subjected to the autonomous decision-freshness lease.

    **Where** — Lines 121, 529, 533, and 537–539:

    ```bash
    cc-teardown <pane-uuid|name> --done-evidence <text> [--force-adopted]
    ```

    ```bash
      if [ "${CC_REAP_LEASE:-on}" != off ] && [ "$FORCE_ADOPTED" = 0 ] && [ -n "$done_ev" ]; then
    ```

    ```bash
          ''|*[!0-9]*)
    ```

    ```bash
            record REFUSE lease-missing "autonomous teardown carried no --decided-at; the decision-freshness lease (${DECISION_MAX_STALE_S}s) cannot be verified, so the close is refused. Callers must pass --decided-at \$(date +%s) taken immediately before the call" 0
            say "REFUSE — no --decided-at on an autonomous teardown: decision freshness unverifiable (exit 2). Pass --decided-at \$(date +%s) immediately before calling."
            exit 2 ;;
    ```

    **Why it is wrong** — Every successful manual call must provide done evidence, so the code labels it autonomous and refuses it for missing the undocumented `--decided-at` argument.

12. **What** — `--force-adopted` disables the freshness lease even though it is advertised as skipping only the adoption belt.

    **Where** — Lines 123, 471, and 529:

    ```bash
      --force-adopted   operator CLI ONLY — skip the operator-adoption belt (no autonomous caller passes it)
    ```

    ```bash
      [ "$FORCE_ADOPTED" = 1 ] && hold_on=0
    ```

    ```bash
      if [ "${CC_REAP_LEASE:-on}" != off ] && [ "$FORCE_ADOPTED" = 0 ] && [ -n "$done_ev" ]; then
    ```

    **Why it is wrong** — Supplying this option also makes the lease condition false, so a stale autonomous decision can act if a caller passes the supposedly adoption-only override.

13. **What** — A malformed maximum-staleness setting silently disables stale-decision rejection.

    **Where** — Lines 102 and 547:

    ```bash
    DECISION_MAX_STALE_S="${CC_REAP_DECISION_MAX_STALE_S:-60}"
    ```

    ```bash
        if [ "$lease_age" -gt "$DECISION_MAX_STALE_S" ] 2>/dev/null; then
    ```

    **Why it is wrong** — With a nonnumeric configured value, `[` returns an error that is suppressed and treated as a false condition, so arbitrarily stale decisions proceed.

14. **What** — Abnormal safety-gate failures are recorded as `DEFER` but returned using undocumented and inconsistent exit codes.

    **Where** — Lines 556, 560, and 564:

    ```bash
      gate_out="$("$GATE" decide --cwd "$cwd" --done-evidence "$done_ev" 2>/dev/null)"; grc=$?
    ```

    ```bash
        [ -n "$gdec" ] || { [ "$grc" = 2 ] && gdec=REFUSE || gdec=DEFER; }
    ```

    ```bash
        say "$gdec — $greason (exit $grc)"; exit "$grc"
    ```

    **Why it is wrong** — If the gate is missing, crashes, or returns another error such as 1 or 127, the record says `DEFER` while the process exits 1 or 127 instead of the documented defer status 10.

15. **What** — Registered-session PIDs are accepted without proving that the live PID still belongs to Claude or to the resolved pane.

    **Where** — Lines 325, 440, and 591:

    ```bash
      pid="$(printf '%s'      "$obj" | jq -r '.pid // empty')"
    ```

    ```bash
      if [ -n "$EXPECT_PID" ] || [ -n "$EXPECT_LSTART" ]; then
    ```

    ```bash
        kill -TERM "$pid" 2>/dev/null || true
    ```

    **Why it is wrong** — Without optional expectation arguments, a retained registry row whose PID has been reused by an unrelated process is treated as live, exempted as the target by the TTY check, and signalled.

16. **What** — The pane-recycle check is a time-of-check/time-of-use guard that is never repeated before the pane is closed.

    **Where** — Lines 441 and 600:

    ```bash
        local now_lstart; now_lstart="$(pid_lstart "$pid")"
    ```

    ```bash
      local close_rc; cct_bounded "$IT2" session close -f -s "$paneUUID" >/dev/null 2>&1; close_rc=$?
    ```

    **Why it is wrong** — If an in-place handoff installs a successor in the same pane after the identity check, the stored old PID can be observed dead, the successor pane is closed, and verification reports success against the old PID and shared UUID.

17. **What** — PID reuse during the termination polling window can cause `SIGKILL` to be sent to an unrelated replacement process.

    **Where** — Lines 591–595:

    ```bash
        kill -TERM "$pid" 2>/dev/null || true
        for _ in $(seq 1 $((TERM_GRACE_S * 5))); do pid_alive "$pid" || break; sleep 0.2; done
        if pid_alive "$pid"; then
          kill -KILL "$pid" 2>/dev/null || true
          for _ in $(seq 1 15); do pid_alive "$pid" || break; sleep 0.2; done
    ```

    **Why it is wrong** — If the target exits after `TERM` and its PID is reassigned before a poll, `kill -0` sees the replacement as alive and the script eventually kills that replacement without comparing its start time first.

18. **What** — The no-silent-record self-test checks only the immediately preceding branch while claiming to verify every decision branch.

    **Where** — Lines 843–844:

    ```bash
      [ -n "$(last_decision)" ] && okp "no-silent-record: every decision branch writes an outcome record" \
        || badp "a decision was SILENT (no record) — an unauditable teardown"
    ```

    **Why it is wrong** — The assertion passes whenever the identity-pin test left one record, even if any other teardown branch produces no record at all.