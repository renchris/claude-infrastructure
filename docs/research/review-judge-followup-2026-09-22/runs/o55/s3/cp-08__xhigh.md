# Review: `bin/cc-teardown`

I found 11 defects. They are ordered roughly by severity. Line numbers count `#!/bin/bash` as line 1.

---

### 1. The `--agent-id` "real argv token" check is a substring match on space-joined argv

- **What:** `resolve_assignee` claims to prove identity from a real `--agent-id` argv token, but it tests a substring of the output of `ps -o args=`, which joins all argv elements with spaces.
- **Where:** lines 270–271
  ```
  case " $rargs " in *" --agent-id "*) ;; *) continue ;; esac
  agid="${rargs#*--agent-id }"; agid="${agid%% *}"   # the token AFTER the real flag
  ```
- **Why it is wrong:**
  - Suppose a non-assignee `claude.exe` on the target pane's tty has a prompt or task argument containing prose such as `… --agent-id foo@session-<lead> …`.
  - That prose satisfies the `" --agent-id "` test. `agid` is then taken from the first occurrence, which is the prose.
  - The value passes the `@session-$lead` check and the charset check, so the process is adopted and later TERM/KILLed.
  - This is exactly the sibling-session case that lines 229–233 say this guard prevents.

### 2. The tty-exclusivity guard is skipped whenever the registry pid is not alive

- **What:** The guard runs only for a live pid, so a pane whose claude has exited is force-closed without checking what else is running on it.
- **Where:**
  - line 577: `if pid_alive "$pid"; then`
  - line 609: `local close_rc; cct_bounded "$IT2" session close -f -s "$paneUUID" >/dev/null 2>&1; close_rc=$?`
- **Why it is wrong:**
  - Suppose the claude process exited but the pane is still present, for example it dropped back to a shell where an operator is now running vim or a dev server.
  - The idempotent short-circuit is not taken because the pane is present, and the whole tty check is skipped.
  - `close -f` then kills those foreign processes and the run is recorded as TEARDOWN with exit 0.
  - The header (lines 24–25) promises "no foreign live process on the pane tty beyond the target claude tree".

### 3. An empty or null registry pid makes the process leg "verified" without any observation

- **What:** When `.pid` is missing, the process leg is reported as gone even though no process was ever identified.
- **Where:**
  - line 332: `pid="$(printf '%s'      "$obj" | jq -r '.pid // empty')"`
  - lines 613–614: `if ! pid_alive "$pid"; then` / `proc_gone=1`
- **Why it is wrong:**
  - With `pid=""`, `pid_alive ""` is false. As a result:
    - no kill is sent;
    - the tty guard is skipped;
    - the idempotent path's pin check with only `--expect-lstart` passes, because `now_lstart` is empty;
    - `proc_gone=1` is set.
  - The record says TEARDOWN with `both_legs_verified=true`, or ALREADY-GONE "pid already dead", while the pane's real claude process was never found or checked.

### 4. The process leg acts on the registry pid without proving it belongs to the pane

- **What:** The kill targets whatever process currently holds the registry pid. The tty guard reads the tty from that pid rather than from the pane, and the "lstart pin" is taken after resolution.
- **Where:**
  - line 299: `tty="$("$PS_BIN" -o tty= -p "$p" 2>/dev/null | tr -d ' ')"`
  - line 596: `local lstart_before; lstart_before="$(pid_lstart "$pid")"`
  - line 600: `kill -TERM "$pid" 2>/dev/null || true`
- **Why it is wrong:**
  - Take a retained `cc-sessions --all` row whose pid has since been reused by an unrelated process on another tty, called with no `--expect-*` pin (every desk or manual call).
  - `pid_alive` is true.
  - `tty_foreign` inspects the stranger's own tty and marks the stranger as "the target tree", so it counts 0 foreign processes.
  - The stranger is sent TERM/KILL.
  - `lstart_before` is the stranger's own start time, so the "lstart pin beats pid-recycling" (line 598) protects nothing.
  - The result is recorded as TEARDOWN success.

### 5. Assignee "already gone" is reported as a both-legs-verified success with no process observed

- **What:** The assignee ALREADY-GONE path claims both legs were verified, but only the pane list was consulted.
- **Where:** line 422
  ```
  1) record ALREADY-GONE idempotent "assignee pane '$TARGET' is absent from a READABLE it2 enumeration — nothing to close" 1
  ```
- **Why it is wrong:**
  - `resolve_assignee` returns 1 only because no list entry has `.id == target`. No pid was ever found or checked.
  - A mistyped or wrong UUID, or an assignee whose `claude.exe` outlived its pane, still exits 0 with `both_legs_verified=true`.
  - Step 6 requires a dead pid as well as an absent pane.

### 6. A readable, non-empty list whose entries don't carry the target `.id` is treated as proof of absence

- **What:** The "never assume absent" rule only covers empty and unparseable lists, not a list that has no usable ids.
- **Where:**
  - lines 199–201:
    ```
    ids="$(printf '%s' "$lst" | jq -r '.[].id // empty' 2>/dev/null)" || return 2
    printf '%s\n' "$ids" | grep -qxF "$uuid" && return 0
    return 1
    ```
  - line 253: `[ -n "$obj" ] || return 1          # enumerator was READABLE and non-empty ⇒ a real absence`
- **Why it is wrong:**
  - If the entries lack `.id` (null, or a renamed key), then `n>0` but `ids` is empty.
  - Every pane reads as absent (rc 1). That produces a false ALREADY-GONE (exit 0), or a false "pane absent" at verify, giving TEARDOWN exit 0 while the pane survives.
  - This is the same blind-enumerator class that the zero-length rule exists to catch.

### 7. The effect-verify list read uses the 10 s bound that the file itself measured as too short under load

- **What:** `pane_present`, which is used for verification, keeps the default 10 s timeout even though a longer bound was deliberately added for the assignee resolver.
- **Where:**
  - line 194: `lst="$(cct_bounded "$IT2" session list --json 2>/dev/null)" || return 2`
  - line 619: `pane_present "$paneUUID"; local ppv=$?`
- **Why it is wrong:**
  - Lines 239–243 record that `it2 session list` took 10.59 s at 33 panes under load.
  - Immediately after a successful close, under the same load, the list call times out and `pane_present` returns 2, so `pane_gone=0`.
  - The run records FAILED and exits 5 ("pane SURVIVED") for a close that worked.
  - This bites the assignee path hardest, since it needed 30 s just to resolve.

### 8. A gate failure's exit code is passed through outside the documented contract

- **What:** When the gate fails, its exit code is passed straight through, while the decision recorded is a DEFER.
- **Where:**
  - line 569: `[ -n "$gdec" ] || { [ "$grc" = 2 ] && gdec=REFUSE || gdec=DEFER; }`
  - line 573: `say "$gdec — $greason (exit $grc)"; exit "$grc"`
- **Why it is wrong:**
  - A missing, crashed or killed gate (rc 127, 126, 1, 139, …) is recorded as DEFER but exits with that raw code. That is none of the documented 0, 10, 2 or 5.
  - A gate rc of 5 would tell the caller "acted, but the pane/process survived" when nothing was touched.

### 9. The selftest locates the gate without resolving symlinks

- **What:** The selftest builds the gate path from `$0` directly, ignoring the symlink resolution the script does for `HERE`.
- **Where:** line 642
  ```
  GATE_SELF="$(cd "$(dirname "$0")" && pwd)/cc-teardown-safety-gate.sh"
  ```
- **Why it is wrong:**
  - Run as `cc-teardown --selftest` through the `~/.claude/bin` symlink, which is the header's "deploy only this one file" setup, this points at a non-existent `~/.claude/bin/cc-teardown-safety-gate.sh`.
  - Every scenario that reaches the gate gets rc 127 and a DEFER record.
  - Scenarios 1, 1b, 2, 3, 4, 10 and 12 then fail for a reason unrelated to the code under test.

### 10. The selftest is not isolated from host belt inputs, and its REFUSE assertions don't check `reason_kind`

- **What:** The selftest takes the adoption belt's inputs from the host, and its REFUSE assertions accept any REFUSE regardless of reason.
- **Where:**
  - lines 710–718: `run_td` sets no `CC_INTERACTIVE_LIB`, `CC_CLASSIFY_PROJECT_ROOTS` or `HOME`.
  - line 784: `[ "$rc" = 2 ] && [ "$(last_decision)" = REFUSE ] \`
- **Why it is wrong:**
  - `INTERACTIVE_LIB`, `cc-beat.sh`, `PROJECT_ROOTS` and `CC_CLASSIFY_*` all come from the host.
  - On a host without `cc-interactive.sh` and without a live beat system, every scenario hits `beat_or_refuse` and gets a presence-unprovable REFUSE.
  - Test 5 ("missing done-evidence → REFUSE — done never inferred") then passes even if done-evidence enforcement were broken.
  - Meanwhile scenarios 1/2/3/4/10/12 fail for the wrong reason.

### 11. A malformed lease setting silently disables the lease

- **What:** Non-numeric lease values make the lease checks error out quietly, and the run proceeds.
- **Where:**
  - line 551: `if [ "$lease_age" -lt "$(( 0 - DECISION_FUTURE_SKEW_S ))" ] 2>/dev/null; then`
  - line 556: `if [ "$lease_age" -gt "$DECISION_MAX_STALE_S" ] 2>/dev/null; then`
- **Why it is wrong:**
  - With `CC_REAP_DECISION_MAX_STALE_S=60s`, or set to empty, `[` errors, its stderr is discarded, and the test evaluates false.
  - Decisions of any age then proceed to the kill.
  - This contradicts the stated rule that the lease is required and "the safe direction is the default".
