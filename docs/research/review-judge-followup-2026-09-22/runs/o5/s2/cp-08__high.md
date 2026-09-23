## Review — `bin/cc-teardown`

Line numbers are counted from `#!/bin/bash` = line 1 and are approximate (±3); the verbatim line is the anchor.

---

### 1. The teardown marker is written before the kill and is never removed when the kill fails, so a still-live target carries a "deliberate teardown" marker

**Where** — line ~593, and the FAIL branch at ~627–628:
```bash
  write_teardown_marker "$paneUUID" "$sess_id" teardown
```
```bash
  record FAILED not-verified "effect-verify FAILED (re-observed): proc_gone=$proc_gone pane_gone=$pane_gone close_rc=$close_rc — LOUD, never a false success" 0
```

**Why it is wrong** — The marker's own comment (line ~590) justifies its placement by claiming the close "becomes inevitable" and that a marker on a live session "would mask a genuine crash of that live session for the reader's whole 30-min freshness window." The close is not inevitable: if `kill -TERM`/`kill -KILL` fails (target owned by another uid ⇒ EPERM, or the process is wedged in uninterruptible sleep), the code reaches the verify step with `proc_gone=0` and exits 5 — the target claude process is still running, and its `<sid>.json` / `<pane>.json` markers stay on disk. The very harm the comment cites (a live session masked from its own crash watchdog) is produced by the branch the guard does not cover. Writers "never delete markers" (line ~163), so nothing undoes it.

---

### 2. The safety gate's raw exit status is used as this script's exit status, so a broken gate exits with a code outside the documented contract while recording a policy decision

**Where** — lines ~565, ~569, ~573:
```bash
  gate_out="$("$GATE" decide --cwd "$cwd" --done-evidence "$done_ev" 2>/dev/null)"; grc=$?
```
```bash
    [ -n "$gdec" ] || { [ "$grc" = 2 ] && gdec=REFUSE || gdec=DEFER; }
```
```bash
    say "$gdec — $greason (exit $grc)"; exit "$grc"
```

**Why it is wrong** — If `$GATE` is missing or not executable (a deploy that copies only `cc-teardown`, which the header at line ~73 explicitly anticipates: "deploy only this one file"), `grc` is 127; a shell error inside the gate gives 1 or 2. The header contract is `0 | 2 | 5 | 10` only. The record is written as `DEFER` (a gate verdict that never happened) while the process exits 127, which cc-reaper's caller-side dispatch on 0/2/5/10 cannot classify. An infrastructure failure is reported as a safety-gate decision.

---

### 3. The jq `//` fallbacks for the gate's reason fields never fire in the case they exist for

**Where** — lines ~570–571:
```bash
    grk="$(printf '%s'     "$gate_out" | jq -r '.reason_kind // "gate"' 2>/dev/null)"
    greason="$(printf '%s' "$gate_out" | jq -r '.reason // "safety gate blocked teardown"' 2>/dev/null)"
```

**Why it is wrong** — The defaults are meant to cover a gate that returns non-zero without usable JSON. But when `gate_out` is empty (the gate crashed, was not found, or wrote only to stderr, which is discarded at line ~565), jq reads zero inputs and therefore emits zero outputs — the `//` alternative is never evaluated. `grk` and `greason` become empty strings, so the decision record carries `reason_kind:""`, `reason:""` and the operator sees `cc-teardown: DEFER —  (exit 127)`. The unauditable-record case is exactly the one the defaults were written for.

---

### 4. The `--agent-id` "real argv token" guard is still a substring match over flattened argv, so prose containing the flag adopts an unrelated live session

**Where** — lines ~270–271:
```bash
    case " $rargs " in *" --agent-id "*) ;; *) continue ;; esac
    agid="${rargs#*--agent-id }"; agid="${agid%% *}"   # the token AFTER the real flag
```

**Why it is wrong** — `ps -o args=` returns argv joined by spaces; there is no way to tell an argv element from text inside another element after that join, and nothing here tries. The header (lines ~229–233) states the requirement is "a real `--agent-id` argv token" and cites the concrete incident: a sibling claude session on ttys029 carrying `--agent-id <name>@session-8891c11f` inside a prose TASK argument. That sibling passes every leg — its argv[0] basename is `claude.exe` (line ~269), the space-delimited substring is present, the extracted token ends in `@session-$lead`, and the charset check at line ~276 passes for any ordinary `name@session-<sid>` string. The result is adoption, then `kill -TERM`/`kill -KILL`, of a live unrelated session. Separately, the guard and the extraction disagree: the `case` requires a space-preceded `--agent-id`, while `${rargs#*--agent-id }` takes the first occurrence anywhere, so an argv containing `--no-agent-id X … --agent-id Y` yields `X`.

---

### 5. `tty_foreign` reports "0 foreign processes" (proven exclusive) when the tty process table cannot be read

**Where** — lines ~301 and ~323:
```bash
  tbl="$("$PS_BIN" -t "$tty" -o pid=,ppid=,comm= 2>/dev/null)"
```
```bash
  echo "$fp"
```

**Why it is wrong** — The function's contract (line ~296) is "-1 = tty undeterminable (fail-closed)", but `-1` is returned only when the *tty name* is empty or `??`. If `ps -t "$tty"` fails, is truncated, or returns nothing (bad tty name, ps error, permissions), `tbl` is empty, both loops iterate over a single blank line, `fp` stays 0, and the caller at line ~583 reads that as "the pane tty is exclusive to the target" and proceeds to kill and close. An unreadable enumeration is converted into positive evidence of exclusivity — the same absence-is-not-evidence error that `pane_present` goes out of its way to avoid. There is also no check that the target pid itself appears in `tbl`, which would have detected the unreadable case.

---

### 6. The tty-exclusivity guard is skipped whenever the target process is already dead, but the pane is still force-closed

**Where** — lines ~577 and ~609:
```bash
  if pid_alive "$pid"; then
```
```bash
  local close_rc; cct_bounded "$IT2" session close -f -s "$paneUUID" >/dev/null 2>&1; close_rc=$?
```

**Why it is wrong** — Reaching line ~609 with a dead pid is a normal path: the idempotent short-circuit at line ~459 only exits when the pane is *also* absent, so "claude exited, pane still open" falls through. That is precisely the state in which an operator has reclaimed the pane and is running something in its shell. Because the tty is looked up through the dead target pid, the whole collateral-close guard is bypassed and `it2 session close -f` destroys whatever is running there. The guard claims to prevent "collateral close" but does not cover the case where the collateral is the only live thing on the pane.

---

### 7. An empty or unreadable pid makes leg 1 verify vacuously, and the run is recorded as "both legs effect-verified"

**Where** — lines ~613–614, ~623 (and the helper at line ~182):
```bash
  if ! pid_alive "$pid"; then
    proc_gone=1
```
```bash
    record TEARDOWN "done" "both legs effect-verified (re-observed): process gone AND pane absent; close_rc=$close_rc" 1
```

**Why it is wrong** — `pid_alive` returns false for two non-death conditions: an empty `$pid` (a registry row with `.pid` absent/null — `resolve` only requires `paneUUID`, line ~337) and `kill -0` failing with EPERM on a process owned by another uid. In both cases `proc_gone=1` without any process ever having been identified, signalled, or observed; if the pane then closes, the record asserts `both_legs_verified: true` and "process gone". A claude process that is still running is reported as a verified teardown — the false-success the file says it never produces.

---

### 8. The assignee already-gone branch records `both_legs_verified=1` although no process was ever examined

**Where** — line ~422:
```bash
        1) record ALREADY-GONE idempotent "assignee pane '$TARGET' is absent from a READABLE it2 enumeration — nothing to close" 1
```

**Why it is wrong** — `resolve_assignee` returns 1 at line ~253, before legs 2 and 3 run, so `pid` is still the empty string set at line ~412 and no process check of any kind has occurred. Contrast the registry idempotent path at line ~462, which reaches its `1` only after `pid_alive` proved the pid dead. Here the process leg is asserted verified on the strength of the pane leg alone; an assignee whose pane was closed while its `claude.exe` kept running is recorded as fully verified and exits 0.

---

### 9. The operator-adoption belt is silently inert for every `--assignee-of` call that omits `--assignee-sid`

**Where** — line ~288, with the claim at line ~416 and the skip at lines ~501/~509:
```bash
    sess_id="$ASSIGNEE_SID"
```
```bash
    # positive it2 + argv evidence, and every downstream gate then runs UNCHANGED and fully armed.
```
```bash
      atj="$(find_transcript "$sess_id" 2>/dev/null || true)"
```

**Why it is wrong** — `--assignee-sid` is optional (line ~117: "empty = off"), so on an adoption without it `sess_id` is `""`; `find_transcript` returns 1 immediately at line ~343, `atj` is empty, and the `if [ -n "$atj" ]` block is skipped entirely — no refusal, no beat fallback, no WARN. The belt whose stated job is "never auto-close a pane a human has typed into" becomes a no-op for exactly the population that has no registry row and therefore no other oracle, while the comment at line ~416 asserts every downstream gate runs "fully armed." An operator typing into an adopted assignee pane is closed.

---

### 10. A non-numeric freshness lease value silently disables the staleness check instead of failing closed

**Where** — line ~556:
```bash
    if [ "$lease_age" -gt "$DECISION_MAX_STALE_S" ] 2>/dev/null; then
```

**Why it is wrong** — With `CC_REAP_DECISION_MAX_STALE_S` set to anything non-integer (`300s`, `5 m`, `off`), `[ ... -gt ... ]` fails with "integer expression expected" and returns 2; the `2>/dev/null` hides the message and the non-zero status is read as "not stale." Every decision, of any age, passes the lease. The documented kill switch is `CC_REAP_LEASE=off`; a typo in the tuning variable produces the same effect with no diagnostic, in a check whose entire premise (lines ~97–100) is that the lease must not be optional.

---

### 11. Name resolution silently picks the first of several same-named sessions

**Where** — lines ~328–329:
```bash
  obj="$("$CC_SESSIONS" --all --json 2>/dev/null | jq -c --arg t "$t" \
     '(map(select(.paneUUID==$t)) + map(select(.name==$t))) | .[0] // empty' 2>/dev/null)"
```

**Why it is wrong** — `--all` includes retained rows, and session names are not unique (`reviewer`, `teammate`, etc.). When two or more rows share the requested name, `.[0]` returns an arbitrary one and the script proceeds to kill its pid and close its pane with no ambiguity check and nothing recorded about the collision. Every other unknown-identity condition in this file is fail-closed; an ambiguous name is instead resolved by position.

---

### 12. `--selftest` is not hermetic: several scenarios' outcomes depend on files outside the temp dir, and the belt/lease branches it advertises are never exercised

**Where** — lines ~484–489 (reached by every `run_td` scenario), against the claim at line ~19:
```bash
    if [ -f "$INTERACTIVE_LIB" ]; then . "$INTERACTIVE_LIB" 2>/dev/null || true; fi
```
```bash
    for _b in "$HERE/../hooks/lib/cc-beat.sh" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/lib/cc-beat.sh" \
```

**Why it is wrong** — `run_td` overrides `CC_TEARDOWN_SESSIONS_BIN`, `IT2_BIN`, `CC_TEARDOWN_GATE_BIN`, `CC_TEARDOWN_PS_BIN`, `CC_TEARDOWN_RECORDS_DIR` and `CC_TEARDOWN_DIR`, but not `CC_INTERACTIVE_LIB`, the beat-lib search path, or `CC_CLASSIFY_PROJECT_ROOTS`. So each scenario sources the host's real `hooks/lib/cc-interactive.sh` and `cc-beat.sh` and searches the host's real `~/.claude*/projects`. On a host where `cc-interactive.sh` is absent and the beat system is live, `beat_or_refuse` fires and every scenario exits 2 — tests 1, 2, 3, 4, 10, 12, 13 then report `badp` messages blaming the branch under test (e.g. "dirty tree not deferred") for a condition that has nothing to do with it. The header calls this "RED-proves every branch … no real session"; in fact the adoption belt (1c), the freshness lease (1d), assignee adoption, and the `tty-indeterminate` DEFER have no scenario at all, and the final GREEN banner is printed on that basis.
