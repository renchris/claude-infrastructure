I read the whole file and traced each decision path. Findings below, strongest first.

**1. Assignee identity is a substring match on flattened argv, not a real flag token.**
- What: `resolve_assignee` adopts (and later kills) any `claude.exe` process on the pane tty whose argument text merely contains `--agent-id <x>@session-<lead>`, which is exactly the prose false-positive the header says the guards prevent.
- Where: lines 270–271
  ```
      case " $rargs " in *" --agent-id "*) ;; *) continue ;; esac
      agid="${rargs#*--agent-id }"; agid="${agid%% *}"   # the token AFTER the real flag
  ```
- Why it is wrong: `ps -o args=` joins argv into one space-separated string, so argument boundaries are gone. A plain `claude.exe` session on the target tty launched with a prompt argument like `"... the --agent-id foo@session-<lead> flag ..."` passes line 270, line 271 extracts `foo@session-<lead>` from the prose, line 276 accepts it, and the process is adopted as an assignee of the dead lead and killed. Line 271 also takes the first occurrence, so a real assignee of a live lead B whose earlier argument text mentions `--agent-id x@session-A` is misattributed to lead A and killed when A dies.

**2. The tty-exclusivity guard reports "exclusive" when the process table is empty.**
- What: `tty_foreign` returns 0 foreign processes when `ps -t` produces no rows, so a failed table read passes the guard instead of being indeterminate.
- Where: lines 301 and 323
  ```
    tbl="$("$PS_BIN" -t "$tty" -o pid=,ppid=,comm= 2>/dev/null)"
    echo "$fp"
  ```
- Why it is wrong: The target pid itself must appear on its own tty, so an empty table can only mean the enumeration failed. Nothing checks that the target row is present. Both loops iterate over a single empty line, `fp` stays 0, main proceeds to kill and close on an unproven premise. The selftest tables at lines 698–699 never contain the target pid either, so the mocks pass without exercising the real shape.

**3. An empty session id silently disarms the operator-adoption belt.**
- What: When `sess_id` is empty, `find_transcript` returns nothing, the belt takes the "unresolvable transcript" proceed path, and no presence oracle (transcript or beat) is consulted at all.
- Where: lines 501 and 509
  ```
      atj="$(find_transcript "$sess_id" 2>/dev/null || true)"
      if [ -n "$atj" ]; then
  ```
- Why it is wrong: An `--assignee-of` call without `--assignee-sid` sets `sess_id=""` at line 288, and any registry row lacking `session_id` does the same. The comment at line 416 says every downstream gate runs "fully armed", but the belt proceeds straight to the close with no operator check. The header rationale for skipping (a renamed transcript) does not cover the case where there is no identity to look up.

**4. Assignee "already gone" reports both legs verified after observing only the pane.**
- What: When the assignee pane is absent, main exits 0 and records `both_legs_verified=1` without ever locating or checking the assignee process.
- Where: lines 422–423
  ```
          1) record ALREADY-GONE idempotent "assignee pane '$TARGET' is absent from a READABLE it2 enumeration — nothing to close" 1
             say "OK — assignee pane already gone (idempotent success, exit 0)"; exit 0 ;;
  ```
- Why it is wrong: `resolve_assignee` returns 1 before leg 3, so `pid` is empty and no `kill -0` ever runs. An orphaned `claude.exe --agent-id ...@session-<lead>` whose pane was closed keeps running, and the caller receives a verified success. The registry idempotent path at lines 459–464 requires a dead pid AND an absent pane; this path requires only the pane.

**5. Name resolution picks the first of possibly many same-named sessions.**
- What: `resolve` collapses all matches to the first element, so an ambiguous name resolves to an arbitrary session and every later gate runs against that session.
- Where: lines 328–329
  ```
    obj="$("$CC_SESSIONS" --all --json 2>/dev/null | jq -c --arg t "$t" \
       '(map(select(.paneUUID==$t)) + map(select(.name==$t))) | .[0] // empty' 2>/dev/null)"
  ```
- Why it is wrong: `--all` includes retained sessions, and names are not required to be unique. Given two rows named the same, the first wins silently, and its pane and pid are killed. There is no ambiguity refusal, and the identity pin at line 449 only helps when the caller supplies it.

**6. `pid_alive` treats "not permitted" as "does not exist".**
- What: A process the caller cannot signal is classified as dead, which feeds both the idempotent short-circuit and the effect-verify.
- Where: line 182
  ```
  pid_alive()  { [ -n "${1:-}" ] && kill -0 "$1" 2>/dev/null; }
  ```
- Why it is wrong: `kill -0` fails with EPERM for a live process owned by another uid. At line 613 that yields `proc_gone=1`, so if the pane close succeeds the run records TEARDOWN with both legs verified while the process is still running. The same happens at line 459, where a pid that only looks dead can produce an ALREADY-GONE success.

**7. Gate failures outside the {2,10} contract are recorded as DEFER and their raw exit code is forwarded.**
- What: Any non-zero gate exit that is not 2 becomes decision DEFER, and cc-teardown exits with the gate's code rather than 10.
- Where: lines 569 and 573
  ```
      [ -n "$gdec" ] || { [ "$grc" = 2 ] && gdec=REFUSE || gdec=DEFER; }
      say "$gdec — $greason (exit $grc)"; exit "$grc"
  ```
- Why it is wrong: If the gate script is missing or unexecutable, `grc` is 127 with empty output, the record says DEFER "safety gate blocked teardown", and the process exits 127. A wiring failure is reported as a policy defer, and the exit code is outside the documented 0/2/5/10 set that autonomous callers key on.

**8. Selftest scenario 5 accepts any REFUSE, not the one it claims to prove.**
- What: The "missing done-evidence" check asserts only exit 2 and decision REFUSE, so a refusal from an earlier belt satisfies it.
- Where: line 784
  ```
    [ "$rc" = 2 ] && [ "$(last_decision)" = REFUSE ] \
  ```
- Why it is wrong: The adoption belt runs before the gate. If the who-oracle library at `hooks/lib/cc-interactive.sh` is absent, `beat_or_refuse` refuses with `presence-unprovable` at line 498 before the gate ever sees the empty evidence, and the scenario passes for the wrong reason. `reason_kind` is recorded but never asserted.

**9. A FAILED teardown leaves the crash-watchdog marker on a live target.**
- What: The marker is written before acting and never removed, so an exit-5 run leaves a live session marked as deliberately torn down.
- Where: line 593
  ```
    write_teardown_marker "$paneUUID" "$sess_id" teardown
  ```
- Why it is wrong: The comment at lines 591–592 states a marker must not exist for a live target because it masks a genuine crash for the reader's freshness window. When the process survives KILL or the pane survives close, main exits 5 at line 628 with the marker still present, which is exactly that masked state.
