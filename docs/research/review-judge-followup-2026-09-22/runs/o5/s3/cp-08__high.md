Read the file in full. Line numbers below count `#!/bin/bash` as line 1; the verbatim line is the anchor if my count drifts by one in the long comment blocks.

---

## 1. A resolved pid of `0` makes the kill legs signal cc-teardown's own process group

**What** — `resolve()` accepts whatever `.pid` the registry row holds without validating it is a positive integer, so a row with `"pid": 0` (jq's `//` does **not** filter `0`, only `null`/`false`) flows into `kill -0` / `kill -TERM` / `kill -KILL`, where `0` means "the sender's whole process group".

**Where** — 332, 182, 600, 603:
```
  pid="$(printf '%s'      "$obj" | jq -r '.pid // empty')"
pid_alive()  { [ -n "${1:-}" ] && kill -0 "$1" 2>/dev/null; }
    kill -TERM "$pid" 2>/dev/null || true
      kill -KILL "$pid" 2>/dev/null || true
```

**Why it is wrong** — With `pid="0"`, `pid_alive 0` runs `kill -0 0`, which succeeds (pid 0 = sender's process group), so the target is judged LIVE, the tty guard runs against a bogus pid, and step 3 executes `kill -TERM 0` followed by `kill -KILL 0` — SIGTERM/SIGKILL to every process in cc-teardown's process group, which includes cc-teardown itself and, when invoked from a desk session's Bash tool, its caller. A negative value behaves the same way (`kill -TERM -123` signals process group 123). `resolve_assignee` validates this (line 267, `case "$rpid" in *[!0-9]*) continue ;; esac`); `resolve()` does not.

---

## 2. An empty pid is reported as "process gone, effect-verified" without any process ever being observed

**What** — `pid_alive ""` returns false on the `[ -n ]` test alone, so a registry row with no `.pid` makes both the idempotent short-circuit and the effect-verify conclude the process leg is proven dead.

**Where** — 182, 459–462, 613–614:
```
pid_alive()  { [ -n "${1:-}" ] && kill -0 "$1" 2>/dev/null; }
  if ! pid_alive "$pid"; then
    pane_present "$paneUUID"; local pp0=$?
    if [ "$pp0" = 1 ]; then
      record ALREADY-GONE idempotent "pid $pid already dead AND pane $paneUUID already absent — nothing to do" 1
  if ! pid_alive "$pid"; then
    proc_gone=1
```

**Why it is wrong** — Given a resolvable row whose `pid` field is absent or `null` (the file's only requirement is a non-empty `paneUUID`, line 337), `pid=""`: the idempotent branch records `both_legs_verified: true` for a pid it never looked up, and on the acting path leg 1 signals nothing while verify sets `proc_gone=1` and reports `exit 0 — process gone AND pane absent`. If a claude process was in fact running in that pane, it is left alive (possibly reparented after the pane close) and the run reports a verified teardown — the exact "non-observation counted as proof" the header forbids.

---

## 3. The `--agent-id` "real argv token" guard is a substring test on the space-flattened argv, so prose satisfies it

**What** — Leg 3 tries to prove a token boundary using `case " $rargs " in *" --agent-id "*`, but `rargs` comes from `ps -o args=`, which joins argv with spaces and destroys token boundaries, so the literal text `--agent-id name@session-<lead>` inside a single prose argument passes the guard.

**Where** — 269–271:
```
    case " $rargs " in *" --agent-id "*) ;; *) continue ;; esac
    agid="${rargs#*--agent-id }"; agid="${agid%% *}"   # the token AFTER the real flag
```

**Why it is wrong** — The condition described in the function's own header (lines 229–231: a sibling live session on the same tty carrying `"--agent-id <name>@session-8891c11f"` inside a prose TASK argument) still passes: that process's argv[0] basename is `claude.exe` (it is a claude session, so line 268 does not exclude it), the flattened string contains `" --agent-id "` because the prose has spaces around it, and `agid` extracted from the prose ends in `@session-$lead` and is shape-valid. `resolve_assignee` then sets `pid` to that unrelated live session and returns 0 (adopted), and step 3 SIGTERM/SIGKILLs it. The guard does not cover the class its comment claims it covers, because no whitespace-based test on `ps -o args=` output can.

---

## 4. `agid` is extracted from a different occurrence than the one that was validated

**What** — `${rargs#*--agent-id }` is a shortest-left match that ignores the leading-space requirement enforced one line earlier, so the value checked at 273/276 can come from an occurrence that is not the validated token.

**Where** — 269–271 (same lines as above), specifically:
```
    agid="${rargs#*--agent-id }"; agid="${agid%% *}"   # the token AFTER the real flag
```

**Why it is wrong** — For an argv like `claude.exe --task "see --agent-id notes@session-XXXX" --agent-id worker@session-<lead>`, line 270 is satisfied by the *real* flag but line 271 extracts `notes@session-XXXX` from the prose; the `*"@session-$lead"` test then fails and `continue` skips a genuine, provable assignee (the leg reverts to REFUSE `assignee-unproven`). Symmetrically, for `--no-agent-id x@session-<lead> …`, the extraction keys off a substring of a different flag. The validation and the extraction are not tied to the same occurrence.

---

## 5. The FAIL-LOUD path leaves a `mode=teardown` marker on a session that is still alive

**What** — The marker is written unconditionally before acting and is never removed, so an `exit 5` (a leg survived) leaves a live session flagged to its own crash watchdog as deliberately torn down.

**Where** — 593, 627–628 (and 163–164 for the no-delete rule):
```
  write_teardown_marker "$paneUUID" "$sess_id" teardown
  record FAILED not-verified "effect-verify FAILED (re-observed): proc_gone=$proc_gone pane_gone=$pane_gone close_rc=$close_rc — LOUD, never a false success" 0
  say "FAIL — teardown NOT verified: proc_gone=$proc_gone pane_gone=$pane_gone close_rc=$close_rc (exit 5)"; exit 5
```

**Why it is wrong** — When the close fails (`IT2_CLOSE_REMOVES=0`-style reality: `close -f` returns non-zero or the pane survives, or the process survives SIGKILL), the target is still running with a marker on disk keyed to its sid and pane. `# Writers never delete markers; the reader GCs them.` means the marker persists for the reader's whole freshness window, so if that still-live session genuinely crashes in that window, `lead-crash-watchdog.sh classify_death` reads it as a deliberate teardown and suppresses the crash — precisely the harm the 2d comment (589–591) gives as the reason not to write the marker before the gates. The selftest pins this invariant only for DEFER (767–769), never for FAILED.

---

## 6. `tty_foreign` reports "tty exclusive" when the process table read produces nothing

**What** — An empty or failed `ps -t` enumeration makes both loops iterate zero rows and the function returns `0` foreign processes, i.e. proven exclusivity from an unreadable table; only an empty/`??` tty *name* fails closed.

**Where** — 300–301, 322, 583:
```
  { [ -z "$tty" ] || [ "$tty" = "??" ]; } && { echo -1; return; }
  tbl="$("$PS_BIN" -t "$tty" -o pid=,ppid=,comm= 2>/dev/null)"
  echo "$fp"
    if [ "${fc:-0}" -gt 0 ] 2>/dev/null; then
```

**Why it is wrong** — The target pid `$p` is by construction attached to `$tty`, so any enumeration that does not contain `$p` is a failed read, not an empty tty. If `ps -t` errors or the tty-name form returned by `ps -o tty=` is not accepted by `ps -t` on this platform, `tbl` is empty, `fp` stays 0, and step 2c concludes there are no foreign processes and proceeds to close a pane that may be shared with an operator's live process. This is the same "empty output means nothing is there" read that `pane_present` explicitly refuses at line 198 (`[ "$n" -eq 0 ] && return 2`).

---

## 7. The tty-exclusivity guard is skipped whenever the target process is already dead, but the pane is still closed

**What** — 2c is wrapped in `if pid_alive "$pid"`, so a pane whose claude process has exited is closed with no foreign-process check at all.

**Where** — 577, 587, 609:
```
  if pid_alive "$pid"; then
  fi
  local close_rc; cct_bounded "$IT2" session close -f -s "$paneUUID" >/dev/null 2>&1; close_rc=$?
```

**Why it is wrong** — Input: a registry row whose claude process has exited (crashed or quit) while the pane remains open and the operator is now using that pane's shell — e.g. running `vim` or a build. The idempotent short-circuit does not fire (the pane is present), the work-safety gate only inspects git state in `cwd`, and 2c is skipped because the pid is dead, so `it2 session close -f` closes the pane and SIGHUPs the operator's live process. The guard's stated job (line 24: "no foreign live process on the pane tty") does not cover the case in which a foreign process is most likely to own the tty.

---

## 8. The gate's raw exit status is re-emitted, so a missing or crashing gate exits with an undocumented code while recording DEFER

**What** — When the gate command fails for any reason, cc-teardown invents a decision label and then exits with the gate's own status verbatim.

**Where** — 565, 568–569, 573:
```
  gate_out="$("$GATE" decide --cwd "$cwd" --done-evidence "$done_ev" 2>/dev/null)"; grc=$?
    gdec="$(printf '%s'    "$gate_out" | jq -r '.decision // empty'    2>/dev/null)"
    [ -n "$gdec" ] || { [ "$grc" = 2 ] && gdec=REFUSE || gdec=DEFER; }
    say "$gdec — $greason (exit $grc)"; exit "$grc"
```

**Why it is wrong** — If `cc-teardown-safety-gate.sh` is absent or not executable — the deployment shape the header explicitly supports ("deploy only this one file", line 73) — the command substitution yields `grc=127` and empty output, so the run records `DEFER` with the fabricated reason `safety gate blocked teardown` and exits **127**, a status outside the documented `{0,2,5,10}` contract (lines 15–18). A caller such as cc-reaper that branches on 10/2/5/0 sees an unclassified status for what is actually a wiring failure; likewise a gate that crashes with rc 1 is reported as a policy DEFER with rc 1.

---

## 9. An empty first argument exits 0 — the success code — having done nothing and recorded nothing

**What** — The dispatcher's help pattern includes the empty string, so an invocation whose target expands to `""` prints usage and exits 0.

**Where** — 864 (and 407 for the branch it bypasses):
```
  -h|--help|"") usage; exit 0 ;;
  [ "${#args[@]}" -ge 1 ] || die "usage: cc-teardown <pane-uuid|name> --done-evidence <text>"
```

**Why it is wrong** — `cc-teardown "" --done-evidence "shipped abc123"` (a caller whose pane-uuid variable was empty) matches `""` on `${1:-}` before `main` ever runs: nothing is resolved, gated, killed or closed, no record is written (violating step 5, line 29), and the exit status is 0, which by line 15 means "torn down + BOTH legs effect-verified". An autonomous caller checking `rc -eq 0` books a verified reap that never happened. `main`'s own refusal for a missing target (line 407, exit 2) is unreachable for this input.

---

## 10. The self-guard is silently disabled when the invoking pane's UUID cannot be determined

**What** — The comparison is conjoined with `[ -n "$SELF_UUID" ]`, so "we cannot tell whether this is our own pane" proceeds instead of refusing.

**Where** — 86–87, 437:
```
_sid="${CC_TEARDOWN_SELF_UUID:-${ITERM_SESSION_ID:-}}"
SELF_UUID="${_sid##*:}"   # ITERM_SESSION_ID = "wNtMpK:<UUID>" → <UUID>; an injected bare UUID passes through
  if [ -n "$SELF_UUID" ] && [ "$paneUUID" = "$SELF_UUID" ]; then
```

**Why it is wrong** — If `ITERM_SESSION_ID` is not in the environment (a caller spawned with a sanitized env, `env -i`, a wrapper that scrubs iTerm variables) and `CC_TEARDOWN_SELF_UUID` is unset, `SELF_UUID=""` and the guard never performs a comparison, so a target that *is* the invoking session's pane passes straight through to the kill and close. The contract lists `self` under the fail-closed REFUSE family (line 17), but the unproven-identity case fails open; only the `--self` string literal is caught unconditionally.

---

## 11. A non-numeric staleness/skew setting silently disables the freshness lease

**What** — Both lease comparisons suppress `[`'s error, so a non-integer `CC_REAP_DECISION_MAX_STALE_S` turns the test into a silent "fresh" verdict rather than a refusal.

**Where** — 551, 556:
```
    if [ "$lease_age" -lt "$(( 0 - DECISION_FUTURE_SKEW_S ))" ] 2>/dev/null; then
    if [ "$lease_age" -gt "$DECISION_MAX_STALE_S" ] 2>/dev/null; then
```

**Where/why it is wrong** — With `CC_REAP_DECISION_MAX_STALE_S=60s` or `=off` (plausible, given the sibling kill switch is `CC_REAP_LEASE=off` and the documented form is `<n>`), `[ 5000 -gt 60s ]` exits 2 with its diagnostic sent to `/dev/null`; the `if` is false, so a decision of arbitrary age passes the lease and the reap proceeds. The check the lease exists to enforce is skipped with no record and no message — the "an opt-in lease is not a lease" failure it was written to prevent (line 100).

---

## 12. The lease's "autonomous caller" discriminator selects every caller, not autonomous ones

**What** — Autonomy is inferred from `-n "$done_ev"`, but `--done-evidence` is mandatory for any successful close, so the lease also applies to the operator/manual invocations the design states are exempt.

**Where** — 538, against the claim at 102 and the usage line at 124:
```
  if [ "${CC_REAP_LEASE:-on}" != off ] && [ "$FORCE_ADOPTED" = 0 ] && [ -n "$done_ev" ]; then
# Operator/manual closes are unaffected, and --force-adopted (operator-ONLY, no autonomous caller
cc-teardown <pane-uuid|name> --done-evidence <text> [--force-adopted]
```

**Why it is wrong** — A close without done-evidence is refused by the safety gate (proved by selftest scenario 5), so the population "closes that omit `--done-evidence`" contains no successful teardown; every invocation that can succeed carries done-evidence and is therefore subject to the lease. An operator running the documented command line without `--decided-at` gets `REFUSE lease-missing`, and the only exemption in the condition, `--force-adopted`, simultaneously disables the operator-adoption belt (line 479) — so satisfying the lease by hand costs the operator the adoption guard.

---

## 13. The selftest compares only `.decision`, and runs the adoption belt against the real host, so scenario 5 can pass on a refusal from a different branch

**What** — Scenario assertions check the exit code and `.decision` but never `.reason_kind`, while the operator-adoption belt is left armed against the host's real `cc-interactive.sh` / `cc-beat.sh` / `PROJECT_ROOTS` rather than mocks.

**Where** — 783–786, 484–489, 712–717:
```
  rc=0; run_td "$d/bin/ps_clean" "$SELF" "$U" >/dev/null 2>&1 || rc=$?
  [ "$rc" = 2 ] && [ "$(last_decision)" = REFUSE ] \
    && okp "missing done-evidence → REFUSE (exit 2) — done never inferred" \
    if [ -f "$INTERACTIVE_LIB" ]; then . "$INTERACTIVE_LIB" 2>/dev/null || true; fi
    for _b in "$HERE/../hooks/lib/cc-beat.sh" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/lib/cc-beat.sh" \
    CC_TEARDOWN_DIR="$d/tdmark" \
```

**Why it is wrong** — `run_td` steers `cc-sessions`, `it2`, `ps`, records and marker dir, but not `CC_INTERACTIVE_LIB`, `CC_CLASSIFY_PROJECT_ROOTS` or `CC_CLASSIFY_INTERACTIVE_HOLD_DISABLE`, so section 1c runs against host state (the file itself records this at 506: routing a case through `beat_or_refuse` "turned 7 of the 17 --selftest checks into REFUSE"). On a host where the who-oracle lib is not deployed but the beat system is live and the synthetic sid `s` has no beat, scenario 5's run exits 2 with `reason_kind=presence-unprovable` at the belt — before the safety gate — and the assertion at 784 passes because it only compares `REFUSE`, so the missing-done-evidence branch it claims to prove is never executed. The same blindness applies to scenarios 2 and 12, which both assert `5/FAILED` without distinguishing which leg failed, so scenario 12's "blind enumerator" claim is satisfied by any surviving-leg failure.
