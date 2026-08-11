1. **What** — The “all six event dirs” test covers only five directories, omitting `CC_ANNOUNCE_ALARM_DIR`.

   **Where** — Lines 163–168 and 173–177:
   ```bash
   @test "all six event dirs: records past the horizon are reaped, young ones kept" {
     mk_old   "$CC_PAGES_DIR/old.page";                 mk_young "$CC_PAGES_DIR/new.page"
     mk_old   "$CC_COMMS_ALARM_DIR/old.json";           mk_young "$CC_COMMS_ALARM_DIR/new.json"
     mk_old   "$CC_PUSH_RECORDS_DIR/old.json";          mk_young "$CC_PUSH_RECORDS_DIR/new.json"
     mk_old   "$CC_COMPLETION_RECORDS_DIR/old.json";    mk_young "$CC_COMPLETION_RECORDS_DIR/new.json"
     mk_old   "$CC_TEARDOWN_RECORDS_DIR/old.json";      mk_young "$CC_TEARDOWN_RECORDS_DIR/new.json"
   ```
   ```bash
     [ ! -f "$CC_PAGES_DIR/old.page" ];              [ -f "$CC_PAGES_DIR/new.page" ]
     [ ! -f "$CC_COMMS_ALARM_DIR/old.json" ];        [ -f "$CC_COMMS_ALARM_DIR/new.json" ]
     [ ! -f "$CC_PUSH_RECORDS_DIR/old.json" ];       [ -f "$CC_PUSH_RECORDS_DIR/new.json" ]
     [ ! -f "$CC_COMPLETION_RECORDS_DIR/old.json" ]; [ -f "$CC_COMPLETION_RECORDS_DIR/new.json" ]
     [ ! -f "$CC_TEARDOWN_RECORDS_DIR/old.json" ];   [ -f "$CC_TEARDOWN_RECORDS_DIR/new.json" ]
   ```

   **Why it is wrong** — If announce-alarm records are never reaped, or young announce alarms are incorrectly deleted, every age-reap test still passes because that directory is never populated or inspected.

2. **What** — The seven-day-horizon test proves only that a particular string occurs somewhere in the script, not that seven days is the effective horizon.

   **Where** — Lines 215–216:
   ```bash
     run bash -c "grep -c 'CC_EVENT_TTL_DAYS:-7' '$SWEEP'"
     [ "$status" -eq 0 ]
   ```

   **Why it is wrong** — The string can occur in a comment, dead branch, or unused assignment while the effective TTL is different; for example, a one-day TTL plus a stale occurrence of this string would still reap the nine-day-old fixtures, retain the new fixtures, exceed the stated 6,000-second lint floor, and let all these tests pass.

3. **What** — Several commands executed through Bats’ `run` helper have their exit statuses silently ignored.

   **Where** — Lines 118, 129, 131, 145, 244, 258, 268–269, 278, 290, and 382:
   ```bash
     run bash "$CC_BACKLOG_BIN" list --open
   ```
   ```bash
     run bash "$SWEEP"
   ```
   ```bash
     run bash "$SWEEP"
   ```
   ```bash
     run bash "$SWEEP"
   ```
   ```bash
     run bash "$CC_BACKLOG_BIN" list --open
   ```
   ```bash
     run bash "$CC_BACKLOG_BIN" list --open
   ```
   ```bash
     run bash "$SWEEP"
     run bash "$CC_BACKLOG_BIN" list --open
   ```
   ```bash
     run jq -r 'select(.source=="autonomy-sweep") | .project' "$CC_BACKLOG_FILE"
   ```
   ```bash
     run jq -r 'select(.source=="autonomy-sweep") | .project + "|" + .title' "$CC_BACKLOG_FILE"
   ```
   ```bash
     run bash "$SWEEP"
   ```

   **Why it is wrong** — Bats’ `run` captures a nonzero status without failing the test; therefore a sweep can perform the checked side effect and then fail, or `cc-backlog list` can fail with empty output and satisfy the negative greps, while the test reports success.

4. **What** — The `osascript` stub treats every invocation as successful without validating or even retaining the script sent on standard input.

   **Where** — Lines 56–57 and 331:
   ```bash
   cat >/dev/null
   printf '%s\n' "$*" >> "$OSA_LOG"
   ```
   ```bash
     [ -s "$OSA_LOG" ]                        # something was actually put in front of a human
   ```

   **Why it is wrong** — If the sweep invokes `osascript` with empty or invalid notification code, the stub discards that code, writes at least a newline to the log, and exits successfully, so the test accepts `"delivered":true` even though the production invocation would display nothing or fail.

5. **What** — The test claiming to prevent a repeated Notification Center storm checks the desk-notify count rather than the Notification Center invocation count.

   **Where** — Lines 334–337:
   ```bash
     # marked seen ⇒ no re-surface, so the channel cannot become a per-sweep notification storm
     run bash "$SWEEP"
     [ "$status" -eq 0 ]
     [ "$(notify_count)" -eq 1 ]
   ```

   **Why it is wrong** — If the second sweep incorrectly invokes `osascript` again without invoking `cc-notify`, `notify_count` remains one and the test passes even though another OS notification was posted.