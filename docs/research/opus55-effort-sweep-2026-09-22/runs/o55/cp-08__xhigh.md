Line numbers are counted from line 1 (`#!/bin/bash`) of the file as given in the brief. Findings are ordered roughly by severity.

---

**1. The assignee identity "proof" from argv cannot tell real argv tokens from words inside a prose argument**
- **What:** `resolve_assignee` looks for a "real `--agent-id` argv token" in `ps -o args=` output. That output joins every argv element with spaces, so the check is exactly the substring match the comments say it prevents.
- **Where:** lines 270–271 (input from line 291)
  `    case " $rargs " in *" --agent-id "*) ;; *) continue ;; esac`
  `    agid="${rargs#*--agent-id }"; agid="${agid%% *}"   # the token AFTER the real flag`
- **Why it is wrong:** Take a `claude.exe` process on the pane tty whose task or prompt argument contains the text `--agent-id foo@session-<lead>`. This is the incident described at lines 231–232.
  - Line 270 matches it.
  - Line 271 extracts `foo@session-<lead>`.
  - That value passes the suffix check (273) and the shape check (276).
  - The unrelated session is adopted and then killed.
  - Separately, line 271 strips up to the *first* `--agent-id ` substring anywhere in the string, including one such as `x--agent-id `. That need not be the token line 270 matched, so a process whose real flag names a different lead can be adopted through an earlier prose occurrence.

**2. An empty target argument exits 0, which the contract defines as "torn down + verified"**
- **What:** The dispatcher sends an empty first argument to `usage; exit 0` instead of into `main`.
- **Where:** line 864
  `  -h|--help|"") usage; exit 0 ;;`
- **Why it is wrong:** `${1:-}` is also empty when `$1` is the empty string.
  - A caller running `cc-teardown "$pane" --done-evidence … --decided-at …` with an empty `$pane` gets exit 0.
  - Nothing is acted on and no record is written.
  - `main`'s REFUSE path (line 407) is never reached.
  - The caller reads "torn down + both legs verified" (line 15).

**3. The tty-exclusivity guard is skipped whenever the target pid is dead, but the pane is still force-closed**
- **What:** The foreign-process check only runs when `pid_alive`, yet leg 2 closes the pane with `-f` regardless.
- **Where:** line 577
  `  if pid_alive "$pid"; then`
- **Why it is wrong:** Suppose claude exited and the pane is back at a shell running something else (for example vim, make, or a long job).
  - The idempotent check (459–465) does not exit because the pane is still present.
  - The guard at 577 is skipped.
  - Line 609 `it2 session close -f` kills those foreign processes.
  - The header (lines 23–25) says the guard ensures "no foreign live process on the pane tty beyond the target claude tree… ALL hold else DEFER". The same happens when `pid` is empty.

**4. The registry pid is never proven to still belong to the session or pane before it is signalled**
- **What:** Without `--expect-*`, the pid from a `cc-sessions --all` row is assumed to be the session's claude process.
- **Where:** line 600, with the lstart capture at line 596
  `    kill -TERM "$pid" 2>/dev/null || true`
  `  local lstart_before; lstart_before="$(pid_lstart "$pid")"`
- **Why it is wrong:** `--all` includes retained (dead) sessions (line 431), and their pids can be recycled.
  - For a retained row whose pid now belongs to an unrelated process, `pid_alive` is true.
  - `tty_foreign` inspects that stranger's *own* tty, not the pane's. If that tty holds only shells, it passes.
  - `lstart_before` is taken from the stranger, so the "lstart pin beats pid-recycling" claim (line 598) cannot detect it.
  - The unrelated process gets TERM, then KILL, and verify reports `proc_gone=1`.
  - `started_ms` from the row is available but never compared.

**5. An unresolvable transcript bypasses the adoption belt entirely, without consulting the beat oracle**
- **What:** When `find_transcript` fails, the belt does nothing: it neither refuses nor asks the second oracle.
- **Where:** line 509
  `      if [ -n "$atj" ]; then`
- **Why it is wrong:** This happens whenever the transcript cannot be found. That includes an empty `sess_id`: a row without `session_id`, or an assignee adopted without `--assignee-sid` (line 288).
  - A pane whose presence beat shows an operator prompt seconds ago proceeds to close.
  - `beat_or_refuse`'s header (357–360) says the "transcript did not resolve" gap is routed to the beat oracle, and that before C‑SC‑1 it "fell straight through the belt to the CLOSE". It still does.
  - The rationale at 502–508 only covers not *refusing* when the beat world is down. It does not justify ignoring a *live* beat.

**6. The teardown marker is written before an action that can still fail and leave the target alive**
- **What:** The marker is dropped on the premise that the close is "inevitable", but the exit‑5 path exists precisely because it is not.
- **Where:** line 593
  `  write_teardown_marker "$paneUUID" "$sess_id" teardown`
- **Why it is wrong:** If TERM and KILL do not kill the process, `proc_gone=0` and the script exits 5 (627–628).
  - The target is alive but carries a deliberate-teardown marker.
  - By the file's own reasoning (589–592), that masks a genuine crash of the live session for the reader's 30‑minute window.

**7. The lease's "autonomous" discriminator also catches every operator or desk close**
- **What:** The lease applies whenever `--done-evidence` is non-empty, but every close that can succeed must carry done-evidence.
- **Where:** line 538
  `  if [ "${CC_REAP_LEASE:-on}" != off ] && [ "$FORCE_ADOPTED" = 0 ] && [ -n "$done_ev" ]; then`
- **Why it is wrong:** The gate REFUSEs any call without done-evidence (line 17; selftest #5).
  - An operator or desk invocation that follows the documented usage (line 124, which has no `--decided-at`) is always refused with `lease-missing`.
  - Line 102 claims "Operator/manual closes are unaffected".

**8. Gate failures propagate raw exit codes outside the 0/10/2/5 contract, and the code disagrees with the recorded decision**
- **What:** Any nonzero gate rc is recorded as DEFER or REFUSE, but the script exits with the gate's raw rc.
- **Where:** lines 569 and 573
  `    [ -n "$gdec" ] || { [ "$grc" = 2 ] && gdec=REFUSE || gdec=DEFER; }`
  `    say "$gdec — $greason (exit $grc)"; exit "$grc"`
- **Why it is wrong:**
  - A crashing gate (rc 1) or a missing or non-executable gate (126/127) is recorded as DEFER but exits 1/126/127. The caller cannot map that to the contract.
  - A gate exiting 5 would be reported as "acted, but pane/process survived" when nothing was done.

**9. An empty pid makes the process leg "verified" without any process ever being identified**
- **What:** `resolve` accepts a row with no pid, and `pid_alive ""` is false, so an empty pid reads as "dead".
- **Where:** line 613, and line 337 (which only requires `paneUUID`)
  `  if ! pid_alive "$pid"; then`
  `  [ -n "$paneUUID" ] || return 1`
- **Why it is wrong:** For a registry row lacking `pid`:
  - Line 459 treats it as already dead, and the record reads "pid  already dead".
  - Line 613 sets `proc_gone=1`.
  - A TEARDOWN or ALREADY-GONE is recorded with `both_legs_verified=true`, although the process leg was never observed.

**10. Assignee "already gone" records both legs verified when only pane absence was checked**
- **What:** The assignee absent path records `both_legs_verified=1` and exits 0 with no process observation.
- **Where:** line 422
  `        1) record ALREADY-GONE idempotent "assignee pane '$TARGET' is absent from a READABLE it2 enumeration — nothing to close" 1`
- **Why it is wrong:**
  - `resolve_assignee` returns 1 purely from it2 list absence. No pid is known, contrary to the "already-gone pane + dead pid" definition at line 30.
  - With `--assignee-of`, a mistyped or nonexistent UUID also becomes exit‑0 success instead of the unknown-target REFUSE promised at line 22.

**11. A jq failure in `resolve_assignee` is read as proven absence**
- **What:** Errors from the `select(.id==$t)` extraction are discarded and the resulting empty string is treated as "real absence".
- **Where:** lines 252–253
  `  obj="$(printf '%s' "$lst" | jq -c --arg t "$uuid" '.[] | select(.id==$t)' 2>/dev/null | head -1)"`
  `  [ -n "$obj" ] || return 1          # enumerator was READABLE and non-empty ⇒ a real absence`
- **Why it is wrong:**
  - If any array element before the target is not an object (a string or number), jq aborts, `obj` is empty, and the function returns 1.
  - The result is ALREADY-GONE with exit 0 on a live pane.
  - `pane_present` treats the same jq failure as indeterminate (line 199).

**12. Name resolution silently picks the first of multiple matches**
- **What:** Ambiguous names are not refused; `.[0]` picks one arbitrarily, including retained dead rows.
- **Where:** line 329
  `     '(map(select(.paneUUID==$t)) + map(select(.name==$t))) | .[0] // empty' 2>/dev/null)"`
- **Why it is wrong:** When two rows share a name, one a retained dead session and one live:
  - Picking the dead one yields ALREADY-GONE with exit 0 while the intended live session is untouched.
  - Otherwise a different live session than the caller meant is torn down.

**13. A malformed hold value silently disables the whole operator-adoption belt**
- **What:** A non-numeric `INTERACTIVE_HOLD_S` sets `hold_on=0`, which skips every belt check, including the R3 refuse path.
- **Where:** line 481
  `  case "$INTERACTIVE_HOLD_S" in ''|*[!0-9]*|0) hold_on=0 ;; esac`
- **Why it is wrong:**
  - Setting `CC_CLASSIFY_INTERACTIVE_HOLD_S=6h` or `21600s` turns off the guard against closing live operator conversations, with no warning and no record.
  - The documented disable switch is a separate variable (line 480).

**14. A malformed lease bound silently passes every decision**
- **What:** The stale check suppresses the integer-comparison error, so a bad bound reads as "not stale".
- **Where:** line 556
  `    if [ "$lease_age" -gt "$DECISION_MAX_STALE_S" ] 2>/dev/null; then`
- **Why it is wrong:** With `CC_REAP_DECISION_MAX_STALE_S=60s`, the test errors with rc 2, which is treated as false. A decision of any age is accepted.

**15. `tty_foreign` reports "exclusive" when the tty process table could not be read**
- **What:** An empty or failed `ps -t` result yields a count of 0, not the fail-closed `-1`.
- **Where:** line 301
  `  tbl="$("$PS_BIN" -t "$tty" -o pid=,ppid=,comm= 2>/dev/null)"`
- **Why it is wrong:**
  - If this `ps` fails or returns nothing, both loops run zero times and the function echoes `0`.
  - Line 583 treats that as proven exclusivity.
  - The table not even containing the target pid itself is never detected.

**16. The identity pin treats "lstart unreadable" as "pid dead"**
- **What:** The lstart comparison is skipped whenever `pid_lstart` returns empty, whether or not the pid is alive.
- **Where:** line 452
  `       { [ -n "$EXPECT_LSTART" ] && [ -n "$now_lstart" ] && [ "$now_lstart" != "$EXPECT_LSTART" ]; }; then`
- **Why it is wrong:**
  - If `ps` fails or returns nothing for a *live*, recycled pid, the pin passes.
  - `pid_alive` is then true, so the script proceeds to kill the successor the pin exists to protect.
  - The comment at 448 equates empty lstart with a dead pid without checking.

**17. The selftest locates the gate from the unresolved `$0`**
- **What:** `GATE_SELF` is derived from `dirname "$0"`, not from the symlink-resolved `$HERE`.
- **Where:** line 642
  `  GATE_SELF="$(cd "$(dirname "$0")" && pwd)/cc-teardown-safety-gate.sh"`
- **Why it is wrong:**
  - Run as `~/.claude/bin/cc-teardown --selftest` under the documented symlink-only deploy (line 73), this points `CC_TEARDOWN_GATE_BIN` at a nonexistent `~/.claude/bin/cc-teardown-safety-gate.sh`.
  - Every gate call then exits 127.
  - The scenarios that reach the gate fail red for a reason unrelated to the branch each one tests.
