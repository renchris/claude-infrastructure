I read the file in full. Below are the defects I can point at, ordered by severity. Line numbers are hand-counted from the text of the brief and may be off by one or two.

---

**1. An empty target is reported as a successful teardown (exit 0) with no record written.**

Where: line ~864
```bash
  -h|--help|"") usage; exit 0 ;;
```
Why: the top-level dispatcher treats an empty first argument exactly like `--help`. An autonomous caller that expands a null or missing JSON field into its target, for example `cc-teardown "$pane" --done-evidence ...` with `pane` empty, gets exit 0, which the documented contract defines as "torn down + both legs effect-verified". Nothing was resolved, gated, acted on, or recorded, and the "no silent branch" rule is broken. The same applies to a completely argument-less invocation.

---

**2. The tty-exclusivity guard is skipped entirely when the target pid is dead, so a pane with live foreign processes is force-closed.**

Where: line ~577
```bash
  if pid_alive "$pid"; then
```
Why: step 2c only runs when the claude process is alive. If the claude process has already exited but the pane is still present (an operator is now running vim, a build, or a shell job on that tty), the code falls through to the marker write and `it2 session close -f`, killing everything in the pane. The header claims the guard prevents "collateral close" of "foreign live process on the pane tty"; this class is exactly not covered. The pane's tty is available from the it2 list object, so the guard is computable without the pid.

---

**3. `tty_foreign` reports "0 foreign processes" when the tty process-table read fails or is empty.**

Where: line ~301
```bash
  tbl="$("$PS_BIN" -t "$tty" -o pid=,ppid=,comm= 2>/dev/null)"
```
Why: only the `-o tty=` lookup returns -1 (indeterminate). If `ps -t` fails (bad tty name, permission, timeout, a mock or wrapper that errors), `tbl` is empty, both loops iterate over nothing, and the function echoes 0. Main then treats the pane as tty-exclusive and proceeds to kill and close. A live target must itself appear in its own tty's table, so an empty table is proof the read failed, yet it is read as "nothing foreign".

---

**4. An empty or non-numeric registry pid is treated as a dead process, so the process leg is "verified" without any observation.**

Where: line 182 and line ~613
```bash
pid_alive()  { [ -n "${1:-}" ] && kill -0 "$1" 2>/dev/null; }
```
```bash
  if ! pid_alive "$pid"; then
```
Why: `resolve` only requires `paneUUID` to be non-empty; `pid` may be empty or garbage from a malformed registry row. `pid_alive` then returns false, so the idempotent branch can record ALREADY-GONE, the tty guard is skipped, no signal is ever sent, and effect-verify sets `proc_gone=1`. The record claims "process gone" and `both_legs_verified: true` for a process that was never identified, let alone re-observed.

---

**5. The assignee-adoption "already gone" branch records both legs as verified when only the pane was checked.**

Where: line ~422
```bash
        1) record ALREADY-GONE idempotent "assignee pane '$TARGET' is absent from a READABLE it2 enumeration — nothing to close" 1
```
Why: `resolve_assignee` returns 1 before leg 3 runs, so no pid was ever found and `pid_alive` was never consulted. The record still carries `both_legs_verified=1`. The documented idempotent rule is "already-gone pane AND dead pid"; here only the pane was observed.

---

**6. A name that matches more than one session resolves silently to the first match.**

Where: line 329
```bash
     '(map(select(.paneUUID==$t)) + map(select(.name==$t))) | .[0] // empty' 2>/dev/null)"
```
Why: `cc-sessions --all` includes retained sessions, and names are not unique. If two rows share the target name, `.[0]` picks whichever the registry lists first, and every downstream gate then runs against that row's pid, cwd, and pane. A caller intending the other session gets an unrelated pane killed with no indication the target was ambiguous.

---

**7. A gate binary that cannot be executed is recorded as a policy DEFER with a fabricated reason and exits with a code outside the contract.**

Where: lines ~569 and ~573
```bash
    [ -n "$gdec" ] || { [ "$grc" = 2 ] && gdec=REFUSE || gdec=DEFER; }
```
```bash
    say "$gdec — $greason (exit $grc)"; exit "$grc"
```
Why: if `$GATE` is missing or not executable, the command substitution yields rc 126 or 127 with empty output. The code then records `DEFER` with reason "safety gate blocked teardown" although no gate ran, and exits 126/127, which is none of the documented 0/2/5/10. The record misattributes a wiring failure to a safety verdict, and callers keyed on 10 vs 2 cannot classify the result.

---

**8. A non-numeric stale-lease limit silently disables the staleness check.**

Where: line ~556
```bash
    if [ "$lease_age" -gt "$DECISION_MAX_STALE_S" ] 2>/dev/null; then
```
Why: with `CC_REAP_DECISION_MAX_STALE_S` set to a non-integer, `[` errors, stderr is discarded, and the test is simply false. The teardown then proceeds on a decision of any age. The header names `CC_REAP_LEASE=off` as the only kill switch, but a malformed limit is an undocumented, silent one in the unsafe direction.

---

**9. The `--agent-id` value is extracted from the first `--agent-id ` substring in argv, not from the space-delimited flag the guard checked.**

Where: line ~271
```bash
    agid="${rargs#*--agent-id }"; agid="${agid%% *}"
```
Why: line 270 proves a space-delimited ` --agent-id ` token exists somewhere, but the `#*--agent-id ` expansion removes up to the first occurrence of the bare substring, which may be inside an earlier prose argument (the exact "TASK argument" case the comment describes) or a token like `--foo=--agent-id x`. The identity check on lines 272-276 is then applied to a token that is not the real flag's value. This is narrow: it needs a `claude.exe` process whose argv mentions `--agent-id` before its own flag.

---

**10. Selftest scenario 5 passes on any REFUSE, including one from a gate that runs before the one under test.**

Where: line ~784
```bash
  [ "$rc" = 2 ] && [ "$(last_decision)" = REFUSE ] \
```
Why: the operator-adoption belt (step 1c) runs before the safety gate and itself exits 2 with decision REFUSE when the who-lib or beat lib is absent or unreadable. The assertion checks only `decision`, not `reason_kind`, so a REFUSE from `presence-unprovable` or `operator-adopted` makes "missing done-evidence → REFUSE" report ok without the done-evidence check ever having been reached. This is the only scenario whose expected outcome sits behind the belt, and it is the one that cannot distinguish.

---

**11. The selftest locates its sibling gate through the unresolved `$0`, so it fails for the wrong reason when run via the deployed symlink.**

Where: line ~642
```bash
  GATE_SELF="$(cd "$(dirname "$0")" && pwd)/cc-teardown-safety-gate.sh"
```
Why: the header says only this file is deployed as a symlink and that `HERE` is resolved through symlinks precisely so the gate sibling is found. The selftest ignores `HERE` and uses the symlink's directory, where no gate exists. Scenarios 1, 2, 10, 12 then get a 127 "DEFER" from defect 7 and scenarios 3 and 4 get rc 127 instead of 10, so the suite goes red for a path problem rather than for any teardown behaviour.
