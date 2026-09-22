## Review — `bin/cc-teardown`

Nine defects. Line numbers are from the file as presented (line 1 = `#!/bin/bash`); each is quoted verbatim so it can be located even if my count drifts by a line.

---

### 1. An empty target argument exits 0 — the documented "torn down + verified" code — without acting or recording

**Where** — line 864 (dispatcher):
```bash
  -h|--help|"") usage; exit 0 ;;
```

**Why it is wrong** — `cc-teardown "" --done-evidence "shipped"` (an autonomous caller whose `$uuid` variable came back empty — exactly the failure mode `cc-reaper` can have) matches the `""` branch, prints usage, and exits **0**. Per the contract at line 15, `exit 0` means "torn down + BOTH legs effect-verified". Nothing was killed, nothing was closed, and no record was written, yet a caller keying on the exit code records a verified teardown. Every other non-actionable invocation (`--self`, unknown target, self pane) exits 2; the empty target is the one that reports success.

---

### 2. The `--agent-id` "real argv token" guard is a plain substring match on flattened `ps args=` output — the exact class the comment says it excludes

**Where** — lines 270–271:
```bash
    case " $rargs " in *" --agent-id "*) ;; *) continue ;; esac
    agid="${rargs#*--agent-id }"; agid="${agid%% *}"   # the token AFTER the real flag
```

**Why it is wrong** — `rargs` comes from `ps -t "$base" -o pid=,args=` (line 291), which joins all of argv into one space-separated string. There is no way to distinguish a real flag from text inside an argument in that string, so the case pattern matches prose too. The scenario the header cites at lines 230–233 — a claude session carrying the literal text `--agent-id <name>@session-8891c11f` inside a prompt/TASK argument — satisfies this guard; it also satisfies the other guard (line 269, `argv[0]` basename `claude.exe`, because it *is* a claude session), the suffix check at line 273, and the shape check at line 276. `resolve_assignee` then returns 0 and `main` proceeds to SIGTERM/SIGKILL that pid and close its pane. The "positive identity proof" is text matching. Additionally, `${rargs#*--agent-id }` takes the **first** occurrence, so when prose precedes the genuine flag, the extracted `agid` is the prose fragment, not the real agent id.

---

### 3. On the assignee path, `sess_id` is taken from the caller's `--assignee-sid` and is never tied to the pid/pane actually adopted, so the operator-adoption belt inspects a different session

**Where** — line 288 (inside the proven-identity block) and line 501 (the belt's only input):
```bash
    sess_id="$ASSIGNEE_SID"
```
```bash
      atj="$(find_transcript "$sess_id" 2>/dev/null || true)"
```

**Why it is wrong** — `resolve_assignee` proves pane → tty → pid, but nothing links `ASSIGNEE_SID` to that pid. If the pane's occupant is not the sid the caller claimed (the assignee exited and the operator started a new session in that pane; or leg 3 matched the wrong process per defect 2), the belt reads the *claimed* sid's transcript — typically absent or stale — concludes no recent operator prompt, and licenses the close of a pane whose live conversation was never examined. The usage text at line 129 states `--assignee-sid` "keeps the operator-adoption belt ARMED"; it is armed against unverified evidence.

---

### 4. The teardown marker is written before the kill and is left in place on the FAIL-LOUD path, where the target is still alive

**Where** — line 593, with the outcome at line 628:
```bash
  write_teardown_marker "$paneUUID" "$sess_id" teardown
```
```bash
  say "FAIL — teardown NOT verified: proc_gone=$proc_gone pane_gone=$pane_gone close_rc=$close_rc (exit 5)"; exit 5
```

**Why it is wrong** — When the process survives TERM+KILL (or the pane close fails), `proc_gone`/`pane_gone` are 0 and the script exits 5 with the target **alive** — but the marker file(s) written at line 593 remain, and nothing deletes them (line 163: "Writers never delete markers"). The stated invariant at lines 591–592 and asserted by the selftest at lines 767–769 is that a marker is never left on a live pane, because it masks a genuine crash for the reader's 30-minute freshness window. The DEFER/REFUSE paths honour that invariant; the FAIL path violates it, so a real crash of that surviving session within the window is classified as a deliberate teardown and gets no recovery.

---

### 5. The assignee "already gone" branch records `both_legs_verified=1` and exits 0 having observed only the pane

**Where** — line 422:
```bash
        1) record ALREADY-GONE idempotent "assignee pane '$TARGET' is absent from a READABLE it2 enumeration — nothing to close" 1
```

**Why it is wrong** — `resolve_assignee` returns 1 as soon as the pane is not in a readable enumeration (line 253), before it ever reaches leg 3; no pid has been identified, and no process check is performed. If the pane was closed (by the operator, or by iTerm2) while the assignee's `claude.exe` kept running — the orphan case — this branch reports exit 0 with `both_legs_verified: true` and the process runs on forever. Compare the registry path at lines 459–464, which requires a dead pid **and** an absent pane before claiming the same outcome. The record also carries `paneUUID: null` and `pid: null`, since the globals were cleared at line 412 and never set.

---

### 6. A broken or missing safety gate is reported as DEFER but exits with the gate's raw status, outside the documented exit contract

**Where** — lines 565 and 573:
```bash
  gate_out="$("$GATE" decide --cwd "$cwd" --done-evidence "$done_ev" 2>/dev/null)"; grc=$?
```
```bash
    say "$gdec — $greason (exit $grc)"; exit "$grc"
```

**Why it is wrong** — If `$GATE` does not exist (the deploy-one-file case the header at lines 72–73 anticipates), is not executable, or dies on a signal, `grc` is 127/126/128+n and `gate_out` is empty. Line 569 then defaults `gdec=DEFER`, so the record and the message claim a *work-safety* deferral, and the process exits 127 — not 10. Callers matching the documented set `{0,2,5,10}` (lines 15–18) see neither a defer nor a refusal for what is actually an infrastructure failure; a caller treating "not 10 and not 2" as an anomaly or as success is misled.

---

### 7. `pane_present` returns "absent" when the list is a non-empty array from which no `.id` can be extracted

**Where** — lines 199–201:
```bash
  ids="$(printf '%s' "$lst" | jq -r '.[].id // empty' 2>/dev/null)" || return 2
  printf '%s\n' "$ids" | grep -qxF "$uuid" && return 0
  return 1
```

**Why it is wrong** — The guards above check only that the payload is an array of length > 0 (lines 196–198). If the elements carry a different key than `.id` — a producer-shape change, or the nested/`sessions` shape — `jq` succeeds with **empty output** and the function falls through to `return 1` = ABSENT, the one verdict its own header (lines 185, 190) says it must never give on an unreadable list. Consequences are precisely the two the header names: a false ALREADY-GONE success at line 461, or `pane_gone=1` at line 620 producing a verified-teardown exit 0 while the pane is still open. "Array non-empty" is not "ids readable".

---

### 8. Two mandatory fail-closed mechanisms silently switch off on malformed numeric env values

**Where** — line 481 and line 556:
```bash
  case "$INTERACTIVE_HOLD_S" in ''|*[!0-9]*|0) hold_on=0 ;; esac
```
```bash
    if [ "$lease_age" -gt "$DECISION_MAX_STALE_S" ] 2>/dev/null; then
```

**Why it is wrong** — With `CC_CLASSIFY_INTERACTIVE_HOLD_S=6h` (or any non-digit value), line 481 sets `hold_on=0` and the entire operator-adoption belt — including its fail-closed `beat_or_refuse` paths — is skipped, so a pane with a live operator conversation proceeds straight to the gate and the kill. Similarly, with `CC_REAP_DECISION_MAX_STALE_S=1m`, `[` at line 556 exits 2 (usage error) with the diagnostic swallowed by `2>/dev/null`; the `if` reads false and the staleness check never fires, so arbitrarily stale decisions are acted on. Both contradict the design statements at lines 100–101 ("The lease is REQUIRED (not optional)... an opt-in lease is not a lease") — a typo in one env var, not an explicit kill switch, disables the protection.

---

### 9. The `die` exit paths refuse at exit 2 without writing a decision record

**Where** — lines 403 and 407:
```bash
      --*) die "unknown option '$1'" ;;
```
```bash
  [ "${#args[@]}" -ge 1 ] || die "usage: cc-teardown <pane-uuid|name> --done-evidence <text>"
```

**Why it is wrong** — Both emit exit 2, which the contract at line 17 and the record family define as a REFUSE, but `die` (line 121) never calls `record`. Step 5 (line 29) and the comment at line 134 state that *every* decision branch writes one outcome record, and the selftest check at line 853 asserts "no-silent-record". An autonomous caller that passes a misspelled flag, or whose target argument is lost, gets a REFUSE exit code with no auditable record at all — the refusal is invisible to the `~/.claude/cc-teardown/` sink an operator reads to reconstruct what the actuator decided.
