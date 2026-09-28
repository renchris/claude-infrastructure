Line numbers count `#!/bin/bash` as line 1. I read the file only; nothing was run.

**1. An empty first argument prints usage and reports success.**
- **Where:** line 862, `  -h|--help|"") usage; exit 0 ;;`
- **Why it is wrong:** `"${1:-}"` is `""` both when there are no arguments and when the first argument is an empty string. A caller such as `cc-teardown "$pane" --done-evidence "$ev" --decided-at ...` with an empty `$pane` matches this arm. It prints usage and exits 0, and exit 0 is documented as "torn down + BOTH legs effect-verified". No record is written and nothing is checked, so the caller reads a failed invocation as a completed teardown.

**2. The assignee "already gone" branch declares success from pane absence alone, without looking at the process.**
- **Where:** line 420, `        1) record ALREADY-GONE idempotent "assignee pane '$TARGET' is absent from a READABLE it2 enumeration — nothing to close" 1`
- **Why it is wrong:** The registry path requires a dead pid and an absent pane (lines 457-461). This path drops the process leg and records `both_legs_verified=1`. Line 196 only treats an entirely empty list as blind. A list that is non-empty but missing the target, for example a buried pane or a different window model, gives `resolve_assignee` a `return 1`. The claude.exe assignee is then reported gone and exit 0 is returned while it is still running.

**3. The "real `--agent-id` argv token" check is a substring test on flattened text.**
- **Where:** line 268, `    case " $rargs " in *" --agent-id "*) ;; *) continue ;; esac`, with line 269, `    agid="${rargs#*--agent-id }"; agid="${agid%% *}"   # the token AFTER the real flag`
- **Why it is wrong:** `ps args=` joins argv into one string, so `--agent-id x@session-<lead>` inside a prose argument looks the same as the real flag. Any process whose argv[0] basename is `claude.exe` and whose arguments contain that text is adopted. The comment at lines 226-231 says identity is "proven from argv, not from text", but the code cannot tell the two apart. The wrongly adopted process is then killed and its pane force-closed.

**4. An empty pid is counted as a verified-dead process.**
- **Where:** line 611, `  if ! pid_alive "$pid"; then`, and line 612, `    proc_gone=1`
- **Why it is wrong:** `resolve()` sets `pid` to `""` when the registry row has no `.pid`. `pid_alive ""` is false, so the tty guard at line 575 is skipped and no process is killed. The pane is force-closed, and once it is absent the run records TEARDOWN with "process gone" and `both_legs_verified=1`. No process was ever identified or observed, so the process leg is unverified.

**5. The tty-exclusivity guard covers only a live target, but the pane is force-closed regardless.**
- **Where:** line 575, `  if pid_alive "$pid"; then`, with line 607, `  local close_rc; cct_bounded "$IT2" session close -f -s "$paneUUID" >/dev/null 2>&1; close_rc=$?`
- **Why it is wrong:** When the registry pid is dead (or empty) and the pane is still present, no foreign-process check runs. This can happen after an unpinned recycle or when the pane is running a shell or other work. `close -f` then closes it anyway. The guard claims to prevent collateral closes but skips exactly the case where the recorded target no longer describes what is in the pane.

**6. Pane absence is treated as proven by any non-empty list that omits the UUID.**
- **Where:** line 196, `  [ "$n" -eq 0 ] && return 2`, and line 199, `  return 1`
- **Why it is wrong:** The comment at lines 184-186 says the enumerator is blind to detached, restoration-pending and buried sessions. The code detects only the case where the whole list is empty. A partly blind enumerator that still lists the desk's own pane returns non-empty without the target, so `pane_present` returns 1 (absent). That yields a false ALREADY-GONE (line 460) or a false pane-verified TEARDOWN (lines 617-622) for a pane that still exists.

**7. Malformed freshness or hold settings silently switch off a safety check.**
- **Where:** line 554, `    if [ "$lease_age" -gt "$DECISION_MAX_STALE_S" ] 2>/dev/null; then`, and line 479, `  case "$INTERACTIVE_HOLD_S" in ''|*[!0-9]*|0) hold_on=0 ;; esac`
- **Why it is wrong:** If `CC_REAP_DECISION_MAX_STALE_S` is set to a non-number such as `60s`, `[ ... -gt ... ]` errors, `2>/dev/null` hides the error, and the condition counts as false. Stale decisions then pass with no warning. If `CC_CLASSIFY_INTERACTIVE_HOLD_S` is set to a non-number such as `6h`, the operator-adoption belt is turned off, again silently. The documented kill switches are the explicit `off` and `DISABLE=1` values, not typos.

**8. The gate's own exit code is passed through, so the exit contract breaks and the record can disagree.**
- **Where:** line 571, `    say "$gdec — $greason (exit $grc)"; exit "$grc"`
- **Why it is wrong:** The gate may exit with any non-zero code: 127 if it is missing, 1 on a crash, 5 or something else on its own. Lines 566-567 record such a case as DEFER (or REFUSE if rc is 2), but the script exits with the raw code. A gate that returns 5 makes cc-teardown report "acted but the pane/process survived" when nothing was acted on. A gate crash escapes the documented 0/2/5/10 set.

**9. The self-target selftest passes for any REFUSE, so it may not exercise the self-guard.**
- **Where:** line 799, `  [ "$rc" = 2 ] && [ "$(last_decision)" = REFUSE ] \`
- **Why it is wrong:** The check does not read `reason_kind`. The fixture (line 796) uses `cwd:"/tmp"`, and `/tmp` is not a repo, so a gate refusal can produce REFUSE with rc 2. If the self-guard at lines 435-438 were removed, the test could still pass through the gate's refusal.
