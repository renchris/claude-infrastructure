# Review of `bin/cc-teardown`: defects found

Line numbers count the shebang as line 1. The most severe defects come first. The self-test defects are at the end.

---

### 1. An empty target exits 0, the "torn down + verified" code

- **What:** An empty first argument goes to `usage` and exits 0, the code the header defines as "torn down + BOTH legs effect-verified", and no record is written.
- **Where:** L864 — `  -h|--help|"") usage; exit 0 ;;`
- **Why it is wrong:** Suppose a caller runs `cc-teardown "$PANE" --done-evidence …` and `$PANE` is empty or unset. `"${1:-}"` is then `""`, so the script prints usage and exits 0. The caller reads success, but nothing was resolved, killed, closed or recorded.

### 2. The tty-exclusivity guard is skipped when the pid is dead or empty but the pane is still present

- **What:** The foreign-process guard only runs while the registry pid is alive. A pane that still exists, but whose claude has exited or whose row has no pid, is force-closed without checking what else is running in it.
- **Where:**
  - L577 — `  if pid_alive "$pid"; then`
  - L609 — `  local close_rc; cct_bounded "$IT2" session close -f -s "$paneUUID" >/dev/null 2>&1; close_rc=$?`
  - L613–614 — `  if ! pid_alive "$pid"; then` / `    proc_gone=1`
- **Why it is wrong:**
  - The idempotent short-circuit (L459–465) only exits when the pane is also absent. So "pid dead + pane present" falls through to `close -f` with no tty check.
  - Case A: the operator started something in that pane after claude exited, such as an editor or a dev server. The forced close kills it.
  - Case B: a `/handoff --recycle` successor booted in the pane before re-registering. The row still holds the old, dead pid, so the identity pin passes; L447–448 wrongly assumes this case "is the idempotent path". The forced close kills the successor.
  - In both cases `proc_gone=1` is set without any observation, and the script records TEARDOWN "both legs effect-verified" with exit 0.
  - If the guard had run on the dead pid, `tty_foreign` would have returned -1 and the script would DEFER.

### 3. The registry pid is killed without proof that it still belongs to the pane

- **What:** Nothing ties the registry `pid` to the target pane. `tty_foreign` takes the tty from the pid itself, not from the pane, and the lstart pin is optional.
- **Where:**
  - L332 — `  pid="$(printf '%s'      "$obj" | jq -r '.pid // empty')"`
  - L299 — `  tty="$("$PS_BIN" -o tty= -p "$p" 2>/dev/null | tr -d ' ')"`
  - L600 — `    kill -TERM "$pid" 2>/dev/null || true`
- **Why it is wrong:**
  - `resolve` reads `cc-sessions --all`, which includes retained rows.
  - A retained row's pid may since have been reused by an unrelated process: another pane's editor or claude, or even the invoking desk's own claude. The self-guard at L437 compares only pane UUIDs, so it does not catch the desk case.
  - That reused pid reads as alive. `tty_foreign` then inspects the stranger's own tty, where only its tree and shells appear, and returns 0.
  - The stranger gets TERM/KILLed. The pane close finds nothing, and verify sees "pid dead + pane absent", so the script exits 0 with TEARDOWN.
  - The "(lstart pin beats pid-recycling)" comment at L598 only compares against `lstart_before` from L596, which is captured after the reuse has already happened.

### 4. `--assignee-of` treats "no pane whose id equals TARGET" as proof the target is gone

- **What:** `resolve_assignee` returns "absent" whenever no `.id` equals TARGET. `main` turns that into ALREADY-GONE with `both_legs_verified=true` and exit 0.
- **Where:**
  - L253 — `  [ -n "$obj" ] || return 1          # enumerator was READABLE and non-empty ⇒ a real absence`
  - L422–423 — `        1) record ALREADY-GONE idempotent "assignee pane '$TARGET' is absent from a READABLE it2 enumeration — nothing to close" 1` / `           say "OK — assignee pane already gone (idempotent success, exit 0)"; exit 0 ;;`
- **Why it is wrong:**
  - TARGET is never checked to be a bare pane UUID. Usage allows `<pane-uuid|name>`, and L87 shows the `wNtMpK:<UUID>` form is in circulation.
  - So a name, agent id, typo or prefixed UUID never matches, and the script reports "already gone, both legs verified" while the assignee keeps running.
  - Even with a correct UUID, no process was ever observed, yet the record claims both legs were verified.

### 5. A partial it2 enumeration is read as proof of absence

- **What:** Only a zero-length list is treated as "blind". A non-empty list that is missing the target is taken as proof the target is absent. Yet the comment at L186–188 names per-session blindness causes: "restoration-pending / buried sessions".
- **Where:**
  - L198 — `  [ "$n" -eq 0 ] && return 2                        # zero enumerated ⇒ blind enumerator ⇒ indeterminate`
  - L200–201 — `  printf '%s\n' "$ids" | grep -qxF "$uuid" && return 0` / `  return 1`
  - L253, same logic inside `resolve_assignee`
- **Why it is wrong:**
  - A buried or not-yet-restored target pane is left out of `app.windows` while other panes are still listed, so `pane_present` returns 1.
  - With a dead pid, L461–463 then records ALREADY-GONE with exit 0 and leaves the pane in place.
  - `resolve_assignee` returns 1 and the script exits 0 with the assignee still alive.
  - In verify, a close that missed the pane still gives `pane_gone=1`, which is a false TEARDOWN.

### 6. The operator-adoption belt is skipped entirely when the transcript does not resolve

- **What:** When `find_transcript` finds nothing, the whole belt is bypassed and the beat oracle is never consulted. This contradicts `beat_or_refuse`'s own contract, which says a transcript that "did not resolve" is routed to it.
- **Where:**
  - L501 — `      atj="$(find_transcript "$sess_id" 2>/dev/null || true)"`
  - L509 — `      if [ -n "$atj" ]; then`
  - The contradicting contract, L357 — `#   (b) the lib is present but its answer is "unreadable" or its transcript did not resolve`
- **Why it is wrong:**
  - Triggers: an empty `sess_id` (an assignee adopted without `--assignee-sid`, L288, or a registry row with no `session_id`), or a transcript outside `PROJECT_ROOTS`.
  - In those cases the pane is closed with no presence check, even when the beat system is live and would show a recent operator prompt.
  - The lib-absent branch with the same empty sid refuses (L498), so the two branches treat the same condition inconsistently.

### 7. Who-oracle results other than rc 2 are treated as "nobody typed"

- **What:** Only exit code 2 counts as "unreadable". Any other failure, or rc 0 with non-numeric output, is silently treated as "no operator turn" and allows the close.
- **Where:**
  - L510 — `        iep="$(ci_last_interactive_epoch "$atj" 2>/dev/null)" || irc=$?`
  - L511 — `        if [ "$irc" = 2 ]; then`
  - L517 — `        case "${iep:-}" in ''|*[!0-9]*) iep="" ;; esac`
- **Why it is wrong:**
  - rc 124, rc 127 or a crash in the lib, or garbage output with rc 0, all end with `iep=""`. The belt then passes and the teardown proceeds.
  - L513–514 states that "Only the rc-1 world … is a FACT that may license a close."

### 8. The teardown marker is left on a target that survives

- **What:** The crash-watchdog marker is written before either leg acts and is never withdrawn. A FAIL where the process survived therefore leaves a live session masked.
- **Where:**
  - L593 — `  write_teardown_marker "$paneUUID" "$sess_id" teardown`
  - L627–628 — `  record FAILED not-verified …` / `…; exit 5`
- **Why it is wrong:**
  - The comment at L590–592 places the marker where "the close becomes inevitable" and says a marker on a live target would "mask a genuine crash".
  - But if TERM and then KILL both fail to kill the process (`proc_gone=0`, exit 5), the target stays alive with a `mode=teardown` marker.
  - A real crash of that session in the next 30 minutes is then classified as a deliberate teardown.

### 9. A name target silently resolves to the first matching row

- **What:** Name matches take `.[0]` from a live-or-retained list, with no uniqueness check.
- **Where:** L329 — `     '(map(select(.paneUUID==$t)) + map(select(.name==$t))) | .[0] // empty' 2>/dev/null)"`
- **Why it is wrong:**
  - Two rows can share a name, for example a retained dead row and a live session.
  - If the retained row comes first: dead pid + absent pane → ALREADY-GONE exit 0, while the intended session keeps running.
  - If a different live same-named session comes first: that session is the one torn down.

### 10. `tty_foreign` fails open when the process table cannot be read

- **What:** An empty or failed `ps -t` read produces a count of 0 ("exclusive") instead of -1 ("indeterminate").
- **Where:**
  - L301 — `  tbl="$("$PS_BIN" -t "$tty" -o pid=,ppid=,comm= 2>/dev/null)"`
  - L323 — `  echo "$fp"`
- **Why it is wrong:**
  - The table must contain at least the target pid itself, but that is never checked.
  - If `ps -t` fails, for example on a fork failure under the fork pile-up the header describes, `tbl` is empty and `fp=0`. The guard then passes and the pane is force-closed without its occupants ever being checked.

### 11. KILL escalation does not use the lstart pin

- **What:** The grace loop and `kill -KILL` go by pid liveness only.
- **Where:**
  - L601 — `    for _ in $(seq 1 $((TERM_GRACE_S * 5))); do pid_alive "$pid" || break; sleep 0.2; done`
  - L603 — `      kill -KILL "$pid" 2>/dev/null || true`
- **Why it is wrong:**
  - If the target exits on TERM and its pid is reused inside the grace window, `pid_alive` stays true and SIGKILL hits the new process.
  - `lstart_before` (L596) is only compared later, in verify, after the kill.

### 12. The assignee "real `--agent-id` argv token" check is actually a substring check

- **What:** `ps -o args=` joins argv with spaces, so the code cannot tell a real flag from the same text inside a prose argument.
- **Where:**
  - L270 — `    case " $rargs " in *" --agent-id "*) ;; *) continue ;; esac`
  - L271 — `    agid="${rargs#*--agent-id }"; agid="${agid%% *}"   # the token AFTER the real flag`
- **Why it is wrong:**
  - Take any `claude.exe` on the pane's tty whose prompt text contains `--agent-id x@session-<lead>`, the exact incident described at L230–232.
  - It passes every check and is adopted as the target and killed. Only the argv[0] test stands between it and a kill; the claimed "real token" proof does not exist.

### 13. The gate's raw exit code is passed through

- **What:** Any non-zero gate status is returned as cc-teardown's own exit code, while the record says DEFER or REFUSE.
- **Where:**
  - L569 — `    [ -n "$gdec" ] || { [ "$grc" = 2 ] && gdec=REFUSE || gdec=DEFER; }`
  - L573 — `    say "$gdec — $greason (exit $grc)"; exit "$grc"`
- **Why it is wrong:**
  - A missing, non-executable or crashing gate (rc 127, 126 or 1) is recorded as DEFER but exits with a code outside the documented 0/2/5/10 contract.
  - A gate that exits 5 would be read as "acted, pane survived" even though nothing was acted on.

### 14. False FAIL in two reachable conditions

- **What:** Verify (and the idempotent check) reports "indeterminate" in cases where the teardown succeeded.
- **Where:**
  - L198, as in #5
  - L619 — `  pane_present "$paneUUID"; local ppv=$?`
- **Why it is wrong:**
  - Cause (a): L189 assumes the invoking pane is always listed. That is false for the launchd-driven cc-reaper and the hook-spawned watchdog. If the target was the only enumerated pane, a successful close leaves `[]`, which reads as indeterminate → FAILED, exit 5.
  - Cause (b): verify uses the 10 s default timeout, which L239–241 says gets clipped under load (10.59 s measured). A real teardown then reports exit 5.

---

## Self-test defects

### 15. The self-test cannot find the gate when run through the deployed symlink

- **What:** `GATE_SELF` is derived from the unresolved `$0` instead of `$HERE`.
- **Where:** L642 — `  GATE_SELF="$(cd "$(dirname "$0")" && pwd)/cc-teardown-safety-gate.sh"`
- **Why it is wrong:**
  - The header's deploy model is a `~/.claude/bin/cc-teardown` symlink, with the note to "deploy only this one file".
  - Run through that symlink, `GATE_SELF` points at `~/.claude/bin/cc-teardown-safety-gate.sh`, which does not exist. Every gate call returns rc 127, recorded as DEFER.
  - Scenarios 1–5, 10 and 12 then fail because of the fixture, not the code.

### 16. The self-test is not hermetic, and scenario 5 asserts the wrong thing

- **What:** `run_td` never pins the belt's inputs, and scenario 5 accepts any REFUSE.
- **Where:**
  - L712–717, the `run_td` environment block (no `CC_INTERACTIVE_LIB`, `CC_CLASSIFY_PROJECT_ROOTS` or beat override)
  - L784 — `  [ "$rc" = 2 ] && [ "$(last_decision)" = REFUSE ] \`
- **Why it is wrong:**
  - The belt reads the host's real `~/.claude/projects` and real `cc-beat.sh`.
  - On a host where `hooks/lib/cc-interactive.sh` is absent (L475 says it "lands separately") and the beat is not live, every scenario that reaches the belt refuses with `presence-unprovable`.
  - Scenario 5 ("missing done-evidence → REFUSE") then passes for that unrelated reason, because it never checks `reason_kind`.
