I read the file in full. Findings, in decreasing order of confidence.

**1. The `--agent-id` value is taken from the first occurrence of the string, not from the real flag, so a prose match can adopt and kill the wrong assignee.**

Where: lines 270 to 271
```bash
    case " $rargs " in *" --agent-id "*) ;; *) continue ;; esac
    agid="${rargs#*--agent-id }"; agid="${agid%% *}"   # the token AFTER the real flag
```
Why: the existence check only proves the substring appears somewhere in argv. The prefix strip then takes the token after the first occurrence. If a `claude.exe` assignee of a different lead carries the text `--agent-id x@session-<this-lead>` inside an earlier prose argument, that prose token is extracted, matches the lead pattern and the character-class check, and the unrelated assignee is adopted, gated, and killed. This is exactly the substring case the header comment says the guard exists to reject.

**2. The tty-exclusivity guard is skipped entirely when the target pid is dead but the pane is still open, so a forced close can kill foreign processes.**

Where: line 577
```bash
  if pid_alive "$pid"; then
```
Why: if claude has exited but the pane survives and now hosts another live process on that tty, the guard never runs because the tty is only derived from the dead pid. The script proceeds to `session close -f`, which terminates the foreign process, and then reports a verified success. The pane tty is available from the it2 list object, so this class is not covered.

**3. An empty tty process table is treated as "no foreign processes" instead of indeterminate.**

Where: line 301
```bash
  tbl="$("$PS_BIN" -t "$tty" -o pid=,ppid=,comm= 2>/dev/null)"
```
Why: the rc of `ps -t` is discarded. If it fails or returns nothing, both loops see no rows, the count is 0, and the guard passes. The target itself is known to be alive on that tty, so an empty table is inconsistent and should read as undeterminable, like the `-1` path at line 300, rather than exclusive.

**4. `pid_alive` reports "dead" for an empty pid and for a permission-denied signal, and effect-verify accepts that as a verified process leg.**

Where: line 182 and lines 613 to 614
```bash
pid_alive()  { [ -n "${1:-}" ] && kill -0 "$1" 2>/dev/null; }
```
```bash
  if ! pid_alive "$pid"; then
    proc_gone=1
```
Why: a registry row with no pid, or a pid owned by another uid where `kill -0` fails with EPERM, makes `pid_alive` return false without any observation. The process leg is then marked gone and the run exits 0 as "effect-verified" even though the target process may still be running. The same conflation makes the idempotent short-circuit at line 459 fire on an unobserved premise.

**5. A gate that fails to execute is recorded as DEFER and exits with a code outside the documented contract.**

Where: lines 565 to 573
```bash
  gate_out="$("$GATE" decide --cwd "$cwd" --done-evidence "$done_ev" 2>/dev/null)"; grc=$?
```
```bash
    [ -n "$gdec" ] || { [ "$grc" = 2 ] && gdec=REFUSE || gdec=DEFER; }
```
```bash
    say "$gdec — $greason (exit $grc)"; exit "$grc"
```
Why: if the gate binary is missing or not executable, the substitution yields rc 126 or 127 with no JSON. The branch then records a DEFER decision, which the header defines as a work-safety verdict, and exits 127 rather than 10 or 2. A caller keying on the documented exit codes, or reading the record, is told the tree was work-unsafe when in fact no safety check ran.
