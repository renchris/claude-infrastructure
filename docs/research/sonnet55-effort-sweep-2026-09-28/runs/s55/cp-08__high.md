I found six defects, listed most serious first. Line numbers were counted by hand from the top of the code block, so they may be off by a couple of lines. The quoted code is copied verbatim.

## 1. Assignee identity is read from flattened text, the failure the code says it prevents

**What:** `resolve_assignee` claims to prove identity from argv, but `ps args=` flattens argv into one string, so the `--agent-id` "token" is found by substring search over the whole command line.

**Where:** ≈278–279
```
    case " $rargs " in *" --agent-id "*) ;; *) continue ;; esac
    agid="${rargs#*--agent-id }"; agid="${agid%% *}"   # the token AFTER the real flag
```

**Why it is wrong:**
- Any `claude.exe` process whose prompt or task argument contains ` --agent-id x@session-<lead>` passes the `claude.exe` check and this match.
- `${rargs#*--agent-id }` takes the first occurrence, so prose that comes before the real flag wins.
- The header describes exactly this case, a sibling session whose prose TASK argument contained the literal string. The `claude.exe` check only excludes it when that sibling isn't itself a `claude.exe`.
- When it does pass, the process is adopted as a dead lead's assignee and killed.

## 2. Registry pid is killed with no proof it is still the pane's process

**What:** Without `--expect-pid` or `--expect-lstart`, the pid from the registry row is signalled on the premise that it still belongs to this pane's claude, and nothing checks that.

**Where:** ≈620, and the tty read in `tty_foreign` ≈312
```
    kill -TERM "$pid" 2>/dev/null || true
```
```
  tty="$("$PS_BIN" -o tty= -p "$p" 2>/dev/null | tr -d ' ')"
```

**Why it is wrong:**
- `resolve` also matches "retained" (dead) sessions, and the identity pin is optional ("empty = no pin").
- If a stale row's pid has been reused by an unrelated live process, `pid_alive` is true.
- `tty_foreign` then checks the tty of that pid, not the tty of the pane from it2, so it finds nothing foreign.
- The gates pass, and TERM then KILL go to the unrelated process.

## 3. tty-exclusivity check treats an unreadable process table as "no foreign process"

**What:** The table read has failures suppressed and no check that the target itself appears in it, so an empty table counts as tty-exclusive.

**Where:** ≈314 and ≈336
```
  tbl="$("$PS_BIN" -t "$tty" -o pid=,ppid=,comm= 2>/dev/null)"
```
```
  echo "$fp"
```

**Why it is wrong:**
- If `ps -t` fails or returns nothing, both loops iterate over nothing and `fp` stays 0.
- The guard reports 0 foreign processes and the close proceeds, though the tty was never actually observed.
- The selftest's `ps_clean` mock returns a table that does not contain the target pid, so the suite cannot tell this apart from a real clean tty.

## 4. Malformed freshness or adoption settings silently switch the guard off

**What:** Non-numeric values for the lease or hold settings disable the check instead of failing it.

**Where:** ≈575 and ≈499
```
    if [ "$lease_age" -gt "$DECISION_MAX_STALE_S" ] 2>/dev/null; then
```
```
  case "$INTERACTIVE_HOLD_S" in ''|*[!0-9]*|0) hold_on=0 ;; esac
```

**Why it is wrong:**
- If `CC_REAP_DECISION_MAX_STALE_S` is, say, `60s`, `[ ... -gt ... ]` errors with rc 2. The `2>/dev/null` hides the error, the `if` is false, and a stale decision proceeds. The lease's own comment says the safe direction must be the default.
- If `CC_CLASSIFY_INTERACTIVE_HOLD_S` is non-numeric, the operator-adoption belt is skipped with no warning, so live operator panes can be auto-closed.
- Only a literal `0` or the disable variable is meant to turn the belt off.

## 5. Gate failure is exited and recorded as if it were a defined verdict

**What:** When the gate exits with an undefined code, the script records it as a routine `DEFER` and exits with that raw code.

**Where:** ≈588 and ≈592
```
    [ -n "$gdec" ] || { [ "$grc" = 2 ] && gdec=REFUSE || gdec=DEFER; }
```
```
    say "$gdec — $greason (exit $grc)"; exit "$grc"
```

**Why it is wrong:**
- If the gate script is missing, not executable (rc 126 or 127), or crashes (rc 1), there is no JSON.
- The record says `DEFER` with the generic reason "safety gate blocked teardown", and the process exits 126, 127 or 1.
- The header contract only allows 0, 10, 2 and 5, so a caller sees either an undocumented code or an apparently normal deferral.
- A broken gate is therefore not distinguishable from "work-unsafe, try later".

## 6. Record write failure is swallowed, so a teardown can go unrecorded

**What:** The single decision record is written with all errors suppressed and no check that it exists.

**Where:** ≈149
```
    > "$RECORDS_DIR/${ts}.json" 2>/dev/null || true
```

**Why it is wrong:**
- If the records dir is unwritable or `jq` fails, the branch leaves no record, or an empty file.
- The script still exits normally, including exit 0 after a real kill and pane close.
- That breaks the header's "NO silent teardown: every decision branch writes one outcome record".
