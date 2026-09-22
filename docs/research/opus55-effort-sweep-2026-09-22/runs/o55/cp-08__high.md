# Review of `bin/cc-teardown`

Line numbers are counted from the `#!/bin/bash` line as line 1.

---

### 1. An empty first argument exits 0, which the contract defines as "torn down and verified"

- **What:** The top-level dispatch treats an empty first argument as a usage request and exits 0.
- **Where:** line 864: `  -h|--help|"") usage; exit 0 ;;`
- **Why it is wrong:** Suppose a caller runs `cc-teardown "$pane" --done-evidence …` and `$pane` is empty, for example because an upstream lookup failed. The script prints usage and exits 0. No record is written and nothing is torn down. The header documents exit 0 as "torn down + BOTH legs effect-verified", so the caller counts a no-op as a verified teardown.

### 2. A stale or recycled registry pid gets SIGTERM/SIGKILL when no identity pin is passed

- **What:** The pid read from a `cc-sessions --all` row is killed without proving it still belongs to the target pane. The row may be a retained, dead session.
- **Where:**
  - line 332: `  pid="$(printf '%s'      "$obj" | jq -r '.pid // empty')"`
  - line 596: `  local lstart_before; lstart_before="$(pid_lstart "$pid")"`
  - line 600: `    kill -TERM "$pid" 2>/dev/null || true`
- **Why it is wrong:**
  - Pinning is optional ("empty = no pin (back-compat)"), and `resolve` accepts retained rows.
  - If the session died and the OS reused its pid for an unrelated process, `pid_alive` is true and `tty_foreign` inspects that stranger's own tty. The stranger is the "target", so it counts 0 foreign processes.
  - `lstart_before` is sampled from the stranger itself. The "lstart pin beats pid-recycling" logic therefore only detects recycling after line 596, never before it.
  - Result: the unrelated process is TERM/KILLed, the pane is closed, and the run records TEARDOWN success.

### 3. An empty registry pid makes "process gone" pass vacuously

- **What:** When the resolved row has no `pid`, the process leg is marked verified without any process ever having been observed.
- **Where:** lines 613–614: `  if ! pid_alive "$pid"; then` / `    proc_gone=1`
- **Why it is wrong:** `pid_alive ""` returns false. As a result:
  - The idempotent check falls through.
  - The tty-exclusivity guard is skipped.
  - The kill is skipped.
  - `proc_gone=1` is set.

  A live claude in the pane is never identified or checked, yet the record reports "both legs effect-verified (re-observed): process gone". The assertion passes because the pid is empty, not because a process was observed gone.

### 4. The tty-exclusivity guard is skipped exactly when the pane is most likely to host other work

- **What:** The collateral-close guard runs only if the target pid is alive. The pane is still force-closed when the pid is dead.
- **Where:** line 577: `  if pid_alive "$pid"; then` (and the close at line 609: `  local close_rc; cct_bounded "$IT2" session close -f -s "$paneUUID" >/dev/null 2>&1; close_rc=$?`)
- **Why it is wrong:** Once claude has exited, the pane returns to its shell. The operator can then run anything in it (vim, a build, a REPL). With a dead pid and a present pane, execution skips 2c entirely and calls `it2 session close -f`, killing that foreign work. That is the collateral close the guard claims to prevent.

### 5. The teardown marker persists when the teardown fails, masking a live session's real crash

- **What:** The marker is written as if the close were inevitable, but on the FAIL path (exit 5) the target can still be alive, and writers never delete markers.
- **Where:**
  - line 593: `  write_teardown_marker "$paneUUID" "$sess_id" teardown`
  - line 628: `  say "FAIL — teardown NOT verified: proc_gone=$proc_gone pane_gone=$pane_gone close_rc=$close_rc (exit 5)"; exit 5`
- **Why it is wrong:** Suppose the process survives both TERM and KILL, or the pane survives the close. The session then lives on with a `mode=teardown` marker keyed to its sid and pane. For the reader's 30-minute freshness window, a genuine crash of that still-live session is classified as a deliberate teardown. The block comment says this is exactly the outcome the placement was meant to prevent.

### 6. The operator-adoption belt treats every who-oracle failure other than rc 2 as "nobody typed"

- **What:** Only `irc == 2` is routed to the fallback oracle. Any other failure rc, or rc 0 with non-numeric output, clears `iep` and passes the belt.
- **Where:**
  - line 511: `        if [ "$irc" = 2 ]; then`
  - line 517: `        case "${iep:-}" in ''|*[!0-9]*) iep="" ;; esac`
- **Why it is wrong:** Examples: the function exits 1 with garbage output, exits 127 because an internal dependency is missing, or exits 0 with malformed output. In each case `iep` becomes empty, no REFUSE fires, and the close proceeds. "Could not produce a valid epoch" is treated as the rc-1 fact "parsed, no operator turn" — the same "cannot read ≠ nobody typed" confusion the rc-2 branch was added to close.

### 7. The assignee path silently disarms the adoption belt when `--assignee-sid` is not passed

- **What:** `resolve_assignee` sets `sess_id` to an empty `ASSIGNEE_SID`. The belt then finds no transcript and passes without refusing or consulting the beat.
- **Where:**
  - line 288: `    sess_id="$ASSIGNEE_SID"`
  - line 509: `      if [ -n "$atj" ]; then`
- **Why it is wrong:** `find_transcript ""` returns 1, so `atj` is empty and the whole belt is skipped. An adopted assignee pane then reaches the close with no presence check at all. This contradicts the claim at line 416 that "every downstream gate then runs UNCHANGED and fully armed".

### 8. The argv identity check cannot tell a real `--agent-id` token from prose

- **What:** `ps -o args=` joins argv with spaces, so the "real argv token" test is still a substring match over flattened text.
- **Where:**
  - line 270: `    case " $rargs " in *" --agent-id "*) ;; *) continue ;; esac`
  - line 271: `    agid="${rargs#*--agent-id }"; agid="${agid%% *}"`
- **Why it is wrong:** Take a `claude.exe` process on the pane tty whose task or prose argument contains ` --agent-id x@session-<lead> `. It is indistinguishable from a real flag. Because the first occurrence wins, the prose copy can also shadow the real flag. The process is adopted and later killed on text evidence, which is the class of failure the header (lines 228–233) says this guard excludes.

### 9. `tty_foreign` fails open when the tty process table is unreadable

- **What:** An empty or failed `ps -t` read yields a foreign count of 0 ("exclusive") instead of -1 (indeterminate).
- **Where:** line 301: `  tbl="$("$PS_BIN" -t "$tty" -o pid=,ppid=,comm= 2>/dev/null)"`
- **Why it is wrong:** If `ps -t` fails or returns nothing after `ps -o tty=` succeeded, both loops iterate zero times and `echo "$fp"` prints 0. The function never checks that the target pid itself appears in the table. The guard therefore reports "no foreign processes" with no evidence, and the close proceeds.

### 10. A crashed or missing gate is recorded as DEFER and exits with an undocumented code

- **What:** Any nonzero gate rc other than 2 with no parsable JSON is recorded as `DEFER`, and the script exits with the gate's raw rc.
- **Where:**
  - line 569: `    [ -n "$gdec" ] || { [ "$grc" = 2 ] && gdec=REFUSE || gdec=DEFER; }`
  - line 573: `    say "$gdec — $greason (exit $grc)"; exit "$grc"`
- **Why it is wrong:** If the gate script is missing (127), not executable (126), or crashes (1), the record says DEFER, meaning a work-unsafe verdict to retry later. The exit code is outside the documented 0/2/5/10 set. A broken safety module is reported as a routine deferral instead of a fault.

### 11. The selftest resolves the gate path without following symlinks, unlike `main`

- **What:** `GATE_SELF` is built from the unresolved `$0`, while production resolves `HERE` through symlinks.
- **Where:** line 642: `  GATE_SELF="$(cd "$(dirname "$0")" && pwd)/cc-teardown-safety-gate.sh"`
- **Why it is wrong:** The header says to "deploy only this one file" as a `~/.claude/bin/cc-teardown` symlink. Run through that symlink, `--selftest` points `CC_TEARDOWN_GATE_BIN` at a nonexistent `~/.claude/bin/cc-teardown-safety-gate.sh`. Every gate call returns 127 and is recorded as DEFER. Scenarios then fail, or pass, for reasons unrelated to the branch under test.

### 12. The selftest is not hermetic, and several scenarios assert only `REFUSE`

- **What:** `run_td` does not steer `CC_INTERACTIVE_LIB`, `CC_CLASSIFY_PROJECT_ROOTS`, or the cc-beat lib lookup, so the adoption belt runs against the host's real hooks, transcripts, and beat state.
- **Where:** line 717: `    "$@" --decided-at "$(date +%s)"` (the environment block at lines 712–716 omits those variables); the assertion at line 784: `  [ "$rc" = 2 ] && [ "$(last_decision)" = REFUSE ] \`
- **Why it is wrong:** If `hooks/lib/cc-interactive.sh` is absent, or the host beat world is live with no beat for sid `s`, `beat_or_refuse` returns REFUSE for every scenario:
  - Scenarios 1–4, 10, and 12 fail spuriously.
  - Scenarios 5 and 13, which check only `decision == REFUSE` and not `reason_kind`, pass for the wrong reason (presence-unprovable rather than missing done-evidence or identity-pin).

### 13. The "no-silent-record" check proves only the last run wrote a record

- **What:** The assertion claims every decision branch writes a record but inspects only the record from the final scenario.
- **Where:** line 853: `  [ -n "$(last_decision)" ] && okp "no-silent-record: every decision branch writes an outcome record" \`
- **Why it is wrong:** `last_decision` reads whatever remains from scenario 13. Earlier branches such as ALREADY-GONE or the gate-DEFER path could stop recording and this check would still pass. It certifies a property it never measures.
