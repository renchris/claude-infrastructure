I read the whole file. It has defects — thirteen, ordered below by severity.

---

### 1. The decision-freshness lease fires on every operator invocation, so the documented command can never succeed

**Where** — line 538, plus the usage text it contradicts at line 124:
```bash
  if [ "${CC_REAP_LEASE:-on}" != off ] && [ "$FORCE_ADOPTED" = 0 ] && [ -n "$done_ev" ]; then
```
```bash
cc-teardown <pane-uuid|name> --done-evidence <text> [--force-adopted]
```

**Why it is wrong** — The lease's discriminator for "autonomous caller" is `[ -n "$done_ev" ]` (per the comment at line 101, "Autonomous = passes --done-evidence"). But the safety gate *refuses* any close without done-evidence, so every invocation that could possibly succeed — operator or reaper — carries `--done-evidence`. Run the exact line printed by `--help`, `cc-teardown <uuid> --done-evidence "shipped abc123"`, and `DECIDED_AT` is empty, matching `''` at line 542: REFUSE `lease-missing`, exit 2. The claim at line 102 ("Operator/manual closes are unaffected") is false, and the only documented usage form is unusable as printed.

---

### 2. The "real `--agent-id` argv token" proof is a substring match on flattened argv — the exact prose case it claims to exclude

**Where** — lines 270–271:
```bash
    case " $rargs " in *" --agent-id "*) ;; *) continue ;; esac
    agid="${rargs#*--agent-id }"; agid="${agid%% *}"   # the token AFTER the real flag
```

**Why it is wrong** — `rargs` comes from `ps -o args=`, which flattens argv into one space-joined string; there is no way to tell a real flag token from text inside another argument. The header comment (lines 228–233) says a sibling session carried the literal string `--agent-id <name>@session-8891c11f` inside a prose TASK argument and that "a substring match would have adopted — then killed — an unrelated live session". That prose is surrounded by spaces, so it matches `*" --agent-id "*`; the `${rargs#*--agent-id }` expansion then takes the **first** occurrence in the string, i.e. the prose one. The `claude.exe` argv[0] check does not exclude it either — the process hosting the prose *is* a claude session. So a live, unrelated `claude.exe` on the pane's tty whose prompt text mentions the flag is adopted at line 277 and killed at line 600/603.

---

### 3. `tty_foreign` reads a failed/empty `ps -t` table as "tty is exclusive" instead of indeterminate

**Where** — lines 301 and 323:
```bash
  tbl="$("$PS_BIN" -t "$tty" -o pid=,ppid=,comm= 2>/dev/null)"
```
```bash
  echo "$fp"
```

**Why it is wrong** — `tbl` is never checked. If `ps -t` fails or returns nothing (bad tty string, ps error, a tty released between the two `ps` calls), both loops read a single empty line, `fp` stays `0`, and the caller at line 583 concludes the pane is tty-exclusive and proceeds to kill and close. The target process is by construction on that tty, so an empty table can only mean the enumeration failed — the identical "zero enumerated ⇒ blind enumerator" case that `pane_present` (line 198) fails closed on. Here it fails open: an unreadable table is used as proof of exclusivity.

---

### 4. The assignee already-gone branch records `both_legs_verified=1` having observed only the pane

**Where** — line 422:
```bash
        1) record ALREADY-GONE idempotent "assignee pane '$TARGET' is absent from a READABLE it2 enumeration — nothing to close" 1
```

**Why it is wrong** — `resolve_assignee` returns 1 at line 253, *before* leg 3 ever runs, so `pid` was never resolved and no process was ever observed. Step 6 of the contract is "already-gone pane **and** dead pid ⇒ success" (line 30), and the registry path at line 459 enforces both. Here a single observation is recorded as both legs verified and exits 0. If the assignee's `claude.exe` survived its pane's disappearance (orphaned, or the pane closed while the child kept running), the lead-crash watchdog counts it as reaped and the process runs forever.

---

### 5. An empty pid is treated as "process gone" rather than "process unobserved"

**Where** — line 182, consumed at lines 613–614:
```bash
pid_alive()  { [ -n "${1:-}" ] && kill -0 "$1" 2>/dev/null; }
```
```bash
  if ! pid_alive "$pid"; then
    proc_gone=1
```

**Why it is wrong** — `resolve` accepts a row with no `pid` (line 332 yields `""`; only `paneUUID` is required at line 337). For that target, `pid_alive ""` returns false, so: the idempotent branch at line 462 records ALREADY-GONE with `both_legs_verified=1` on a process it never looked at, and the effect-verify sets `proc_gone=1` with no observation at all, producing `record TEARDOWN "done" "both legs effect-verified (re-observed): process gone AND pane absent"` at line 623 while a live claude may still be running. "We have no pid" is being converted into "the process is dead" — the same inference the file's own header (line 11) forbids.

---

### 6. The gate branch normalizes the decision but exits with the gate's raw return code

**Where** — line 573:
```bash
    say "$gdec — $greason (exit $grc)"; exit "$grc"
```

**Why it is wrong** — Line 569 exists precisely because the gate may produce no JSON (crash, missing file), and it synthesizes `gdec=DEFER` for any `grc` other than 2. But the exit status is then passed through unnormalized. If `$GATE` is absent or not executable, `grc=127`; if it dies on a signal or an internal error, `grc` is 1 or 126. The record says `DEFER`, the process exits 127, and the caller — which maps 10=DEFER, 2=REFUSE, 5=FAIL per lines 15–18 — sees an exit code outside the documented set and cannot classify the outcome.

---

### 7. The tty-exclusivity guard is skipped exactly when the pane is most likely to have been reclaimed

**Where** — line 577:
```bash
  if pid_alive "$pid"; then
```

**Why it is wrong** — The collateral damage the guard exists to prevent ("refusing collateral close", line 584) is caused by the **pane close** at line 609, which runs unconditionally. When the target's claude has already exited but the pane is still open — the state in which an operator has gotten their shell back and started a build, an editor, or an ssh session in that pane — lines 578–586 are skipped entirely and the pane is closed with no foreign-process check, killing whatever is running there. Compare line 579: when the pid *is* alive and the tty merely can't be resolved, the code fails closed with DEFER. A dead target gets no check at all.

---

### 8. The teardown marker is written before the kill and never removed when the teardown fails

**Where** — line 593, reached before the FAIL path at line 628:
```bash
  write_teardown_marker "$paneUUID" "$sess_id" teardown
```
```bash
  say "FAIL — teardown NOT verified: proc_gone=$proc_gone pane_gone=$pane_gone close_rc=$close_rc (exit 5)"; exit 5
```

**Why it is wrong** — The comment at lines 591–592 states the marker must not be written while the target is alive, because a stale marker "would mask a genuine crash of that live session for the reader's whole 30-min freshness window". The exit-5 path is exactly that state: the kill did not take and/or the close did not take, the target is still alive, the marker has been written, and line 163 says writers never delete markers. If that surviving session genuinely crashes within the reader's freshness window, the watchdog reads the stale `mode=teardown` marker and classifies the crash as a deliberate close, suppressing recovery — the precise failure the guard was written to prevent.

---

### 9. `pane_present`'s blind-enumerator guard checks array length, not whether any ids were extracted

**Where** — lines 199–201:
```bash
  ids="$(printf '%s' "$lst" | jq -r '.[].id // empty' 2>/dev/null)" || return 2
  printf '%s\n' "$ids" | grep -qxF "$uuid" && return 0
  return 1
```

**Why it is wrong** — If the list is a readable array of N objects that carry no `.id` key (a renamed field, a schema change in `it2`, a version skew between the shim and this caller), `jq` exits 0 with empty output, the `n -eq 0` guard at line 198 does not fire because `length` is N, and every lookup falls through to `return 1` — "absent". That is the false-gone verdict the whole function is built to prevent: it would produce a false ALREADY-GONE at line 461 and, worse, a false `pane_gone=1` at line 620, reporting a fleet-wide "torn down + effect-verified" on live panes.

---

### 10. The self-guard silently disappears when neither self-UUID source is set

**Where** — line 437:
```bash
  if [ -n "$SELF_UUID" ] && [ "$paneUUID" = "$SELF_UUID" ]; then
```

**Why it is wrong** — `SELF_UUID` derives from `CC_TEARDOWN_SELF_UUID` or `ITERM_SESSION_ID` (line 86). If both are unset — a session whose environment does not carry `ITERM_SESSION_ID` through to the spawned tool process, or any caller that scrubs the environment — the whole comparison is skipped and a target that *is* the invoking session's pane proceeds to kill and close. The file lists `self` as a fail-closed REFUSE (line 17); here it is a fail-open skip with no record and no warning, and the failure mode is the script killing itself mid-run, before effect-verify.

---

### 11. The selftest resolves the safety gate from `$0` instead of the symlink-resolved directory, so it fails through the deployed symlink

**Where** — line 642, forced into every run at line 713:
```bash
  GATE_SELF="$(cd "$(dirname "$0")" && pwd)/cc-teardown-safety-gate.sh"
```
```bash
    CC_TEARDOWN_GATE_BIN="$GATE_SELF" CC_TEARDOWN_PS_BIN="$psbin" \
```

**Why it is wrong** — Lines 72–82 resolve `$0` through symlinks specifically so that a `~/.claude/bin/cc-teardown` symlink finds its gate sibling in the repo `bin/`. The selftest bypasses `HERE` and uses `dirname "$0"`, which for a symlinked invocation is `~/.claude/bin`, where no gate exists. `CC_TEARDOWN_GATE_BIN` then overrides the correct default, so `$GATE` returns 127, scenario 1 records DEFER and exits 127 instead of 0/TEARDOWN, and `--selftest` reports FAIL on working code — a test failing for the wrong reason, in the one deployment shape the header says is supported.

---

### 12. A non-numeric lease env value silently disables the staleness check instead of failing closed

**Where** — lines 551 and 556:
```bash
    if [ "$lease_age" -lt "$(( 0 - DECISION_FUTURE_SKEW_S ))" ] 2>/dev/null; then
```
```bash
    if [ "$lease_age" -gt "$DECISION_MAX_STALE_S" ] 2>/dev/null; then
```

**Why it is wrong** — `CC_REAP_DECISION_MAX_STALE_S` is a documented operator knob (line 103). Set it to anything non-numeric — `60s`, `1m`, a trailing space — and `[ ... -gt ... ]` exits 2 with its error redirected to `/dev/null` by the very `2>/dev/null` on the line; a non-zero status reads as "not stale", so the branch is skipped and every stale decision is accepted. The lease that "is REQUIRED (not optional)" (line 100) is then off with no message and no record. `DECIDED_AT` itself is validated at line 541; the thresholds it is compared against are not.

---

### 13. Two exit-2 paths decline without writing a record

**Where** — lines 403 and 407:
```bash
      --*) die "unknown option '$1'" ;;
```
```bash
  [ "${#args[@]}" -ge 1 ] || die "usage: cc-teardown <pane-uuid|name> --done-evidence <text>"
```

**Why it is wrong** — `die` (line 121) prints to stderr and exits 2, which is the REFUSE code in this script's contract. Line 134 states "NO silent teardown: every decision branch writes one outcome record", and every other exit-2 site calls `record` first. An autonomous caller that passes a flag this version does not know (or a target argument that got consumed by a preceding option-with-value, e.g. `--done-evidence` as the final argument) gets a REFUSE-coded exit with nothing in `$RECORDS_DIR` — an unauditable decline that looks identical to a policy refusal in the caller's exit-code handling but leaves no trace for the operator reading the records directory.
