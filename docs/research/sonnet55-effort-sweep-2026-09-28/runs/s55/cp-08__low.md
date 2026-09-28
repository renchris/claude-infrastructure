I found three defects. I counted line numbers by eye, so they are approximate; the quoted code is exact.

**1. The tty-exclusivity guard is skipped when the recorded pid is dead, but the pane is still closed with `-f`.**
- **What:** The check for foreign processes on the pane tty runs only if the registry pid is alive, yet the pane close runs unconditionally.
- **Where:** ~line 566, `if pid_alive "$pid"; then` (the 2c block). The close is at ~line 597: `cct_bounded "$IT2" session close -f -s "$paneUUID" >/dev/null 2>&1; close_rc=$?`
- **Why it is wrong:** Take a registry row whose pid is dead or empty while the pane is still present. This happens when the pane has recycled, or when the row has no `.pid`. The idempotent short-circuit only exits when the pane is absent, so this case falls through. The tty guard is skipped, and the identity pin only applies if the caller passed `--expect-*`. The `-f` close then kills whatever now runs in that pane, such as a successor claude or an operator's vim. The effect-verify still reports success: `proc_gone` is 1 because the recorded pid is dead, and the pane is now absent. The result is an exit 0 "verified" teardown of a pane whose occupant was never proven to be the target.

**2. A non-numeric freshness-lease setting silently disables the staleness check.**
- **What:** The stale-decision comparison suppresses its own error, so a bad `CC_REAP_DECISION_MAX_STALE_S` makes it a no-op.
- **Where:** ~line 551, `if [ "$lease_age" -gt "$DECISION_MAX_STALE_S" ] 2>/dev/null; then`. The future-skew check on ~line 543 has the same form: `if [ "$lease_age" -lt "$(( 0 - DECISION_FUTURE_SKEW_S ))" ] 2>/dev/null; then`
- **Why it is wrong:** If the env var is set to something like `60s` or `abc`, `[ -gt ]` fails with a usage error (rc 2). Stderr is discarded, and the `if` treats that as false. A decision that is hours old passes the "REQUIRED" lease and proceeds to kill. The failure is silent, which is the opposite of the fail-closed intent.

**3. The safety-gate failure path can exit with codes outside the documented contract.**
- **What:** The gate's exit code is passed straight through, and an unreadable or crashed gate is recorded as a legitimate DEFER.
- **Where:** ~line 561, `[ -n "$gdec" ] || { [ "$grc" = 2 ] && gdec=REFUSE || gdec=DEFER; }` followed by `say "$gdec — $greason (exit $grc)"; exit "$grc"`
- **Why it is wrong:** If the gate binary is missing or not executable, or it crashes, `grc` is 126, 127 or 1 and the output is empty. The script records a DEFER with the placeholder reason "safety gate blocked teardown" and exits 127 or similar. That is not one of the documented 0, 10, 2 or 5. The record says DEFER (work-unsafe) while the real cause is a broken gate. A caller that treats only 10 as a defer, or any non-zero as a hard failure, misclassifies it.
