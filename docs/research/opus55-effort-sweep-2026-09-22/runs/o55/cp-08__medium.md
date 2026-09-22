# Review of `bin/cc-teardown`: 7 defects found

Line numbers are counted by hand from the brief and may be off by a line or two. The quoted code is verbatim.

---

### 1. `tty_foreign` treats an unreadable tty process table as "zero foreign processes"

- **What:** If `ps -t` fails or prints nothing, the function returns a foreign count of `0` (exclusive) instead of `-1` (indeterminate).
- **Where:** ~L301 and ~L323
  ```
    tbl="$("$PS_BIN" -t "$tty" -o pid=,ppid=,comm= 2>/dev/null)"
  ```
  ```
    echo "$fp"
  ```
- **Why it is wrong:** The tty itself resolved (a non-empty tty that is not `??`), but `ps -t` can still fail: the ps call errors or times out, the tty format is rejected, or the table comes back empty.
  - In that case both loops iterate over nothing, `fp` stays `0`, and it echoes `0`.
  - The caller reads `0` as "no foreign process" and proceeds to kill the target and close the pane.
  - The guard fails open. The header says the tty-indeterminate case must DEFER (exit 10).

### 2. The tty-exclusivity guard is skipped when the target pid is dead, but the pane is closed anyway

- **What:** The collateral-process guard only runs when the target pid is alive. The pane close (leg 2) runs no matter what, and it kills everything on that tty.
- **Where:** ~L576 and ~L608
  ```
    if pid_alive "$pid"; then
  ```
  ```
    local close_rc; cct_bounded "$IT2" session close -f -s "$paneUUID" >/dev/null 2>&1; close_rc=$?
  ```
- **Why it is wrong:** Take a claude process that has already exited, whose pane is still present. The idempotent shortcut does not fire because the pane is present.
  - If the pane's shell is now running a foreign job (for example the operator ran `vim` or a build after claude exited), `tty_foreign` is never consulted.
  - `session close -f` then force-closes the pane and kills that foreign work.
  - This is the exact collateral close the guard claims to prevent.

### 3. An empty or unknown `pid` is treated as a proven-dead process

- **What:** When the registry row has no pid, `pid_alive ""` returns false. Every "process dead" check then passes without the process ever being observed.
- **Where:** ~L182, ~L458–461, ~L612–613
  ```
  pid_alive()  { [ -n "${1:-}" ] && kill -0 "$1" 2>/dev/null; }
  ```
  ```
    if ! pid_alive "$pid"; then
  ```
  ```
        record ALREADY-GONE idempotent "pid $pid already dead AND pane $paneUUID already absent — nothing to do" 1
  ```
  ```
    if ! pid_alive "$pid"; then
      proc_gone=1
  ```
- **Why it is wrong:** `resolve()` accepts a row with `.pid` missing or null (`pid=""`); only `paneUUID` is required. For such a row:
  - The idempotent path records "pid already dead", with `both_legs_verified=1`.
  - Alternatively, the tty guard is skipped, no kill is sent, and effect-verify sets `proc_gone=1`. The result is a `TEARDOWN` "both legs effect-verified" success.
  - In neither case was any process observed. This is a success reported on an unproven premise.

### 4. Assignee "already gone" reports both legs verified without observing any process

- **What:** When `resolve_assignee` returns 1 (pane absent), the script exits 0 with `both_legs_verified=1`, even though no pid was ever identified or checked.
- **Where:** ~L421–422
  ```
          1) record ALREADY-GONE idempotent "assignee pane '$TARGET' is absent from a READABLE it2 enumeration — nothing to close" 1
  ```
- **Why it is wrong:** The header defines idempotent success as "already-gone pane **+ dead pid**".
  - Here only pane absence is proven. The assignee's `claude.exe` may still be alive, for example if it was detached or survived the pane going away.
  - The record nonetheless asserts both legs verified. This is a false success.

### 5. The assignee identity check matches a substring of the space-joined args, not a real argv token

- **What:** The `--agent-id` test and the extraction of its value both operate on the flattened `args=` string. A `--agent-id x@session-<lead>` that appears inside a prose argument is indistinguishable from the real flag.
- **Where:** ~L271–272
  ```
      case " $rargs " in *" --agent-id "*) ;; *) continue ;; esac
      agid="${rargs#*--agent-id }"; agid="${agid%% *}"   # the token AFTER the real flag
  ```
- **Why it is wrong:** `ps -o args=` joins argv with spaces, so argument boundaries are lost.
  - Consider any `claude.exe` process on that tty whose task or prompt argument contains the text ` --agent-id foo@session-<lead> `, such as the ttys029 incident the comment cites.
  - That process passes the `claude.exe` argv[0] check, the "flag" check, the `@session-$lead` suffix check, and the charset check.
  - The script then adopts it and kills it. The header comment claims this exact class is guarded against, and it is not.
  - Separately, `${rargs#*--agent-id }` picks the *first* occurrence, which may be the prose one rather than the real flag.

### 6. Without `--assignee-sid`, the operator-adoption belt is silently disarmed for adopted assignees

- **What:** `resolve_assignee` sets `sess_id="$ASSIGNEE_SID"`. When that is empty, `find_transcript` returns nothing and the belt proceeds without ever checking.
- **Where:** ~L288 and ~L500 / ~L508
  ```
      sess_id="$ASSIGNEE_SID"
  ```
  ```
        atj="$(find_transcript "$sess_id" 2>/dev/null || true)"
  ```
  ```
        if [ -n "$atj" ]; then
  ```
- **Why it is wrong:** Suppose a caller passes `--assignee-of` but not `--assignee-sid`, which the parser permits.
  - `find_transcript ""` returns 1 immediately, so `atj` is empty and the whole WHO check is skipped.
  - No refusal is issued and no beat oracle is consulted.
  - An assignee pane that an operator is actively typing into can therefore be auto-closed. The usage text claims `--assignee-sid` is what keeps the belt armed, but nothing enforces its presence.

### 7. Selftest check 11 claims "every decision branch writes an outcome record" but only checks the last run

- **What:** The assertion inspects just the single record left by the final scenario (test 13), so it passes regardless of whether other branches write records.
- **Where:** ~L852
  ```
    [ -n "$(last_decision)" ] && okp "no-silent-record: every decision branch writes an outcome record" \
  ```
- **Why it is wrong:** Suppose any branch other than the identity-pin REFUSE stopped writing its record, for example the TEARDOWN, DEFER, or ALREADY-GONE `record` call were removed.
  - Check 11 would still print `ok`, because it only inspects the identity-pin REFUSE record from test 13.
  - The assertion passes for the wrong reason, and it does not prove the property it names.
