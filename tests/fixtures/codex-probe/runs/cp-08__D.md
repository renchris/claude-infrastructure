## Defects

---

### 1. `pane_present` treats a *partially* blind enumerator as proof of absence

**Where** — `pane_present`, lines ~198–201:
```bash
  [ "$n" -eq 0 ] && return 2                        # zero enumerated ⇒ blind enumerator ⇒ indeterminate
```
```bash
  printf '%s\n' "$ids" | grep -qxF "$uuid" && return 0
  return 1
```

**Why it is wrong** — The header (lines ~186–191) names the blindness causes as "detached desk / different GUI login / restoration-pending / buried sessions" — all **per-window / per-session** conditions — but the indeterminacy guard is a **whole-list** test (`n -eq 0`). Whenever the enumerator sees at least one pane (which, by the comment's own argument, is the normal case: "A machine running cc-teardown always holds >=1 pane (the invoking one)") but has not yet restored / cannot see the *target's* window, `n` is ≥1, the id is missing, and the function returns **1 = provably absent** for a live pane. That feeds two success paths: the step-6 short-circuit records `ALREADY-GONE ... "pane $paneUUID already absent"` with `both_legs_verified: true` and exits 0, and the step-4 verify sets `pane_gone=1` and records `TEARDOWN ... "pane absent"` — the exact false-success the "re-observation" design exists to prevent. The rule catches only the fully-empty instance of a class it describes as broader.

---

### 2. The `--agent-id` "argv token" guard is a text match and adopts a process that merely *mentions* the flag

**Where** — `resolve_assignee`, line ~270:
```bash
    case " $rargs " in *" --agent-id "*) ;; *) continue ;; esac
```

**Why it is wrong** — `rargs` comes from `ps -t "$base" -o pid=,args=`, which joins argv with spaces and carries **no argument boundaries**. The comment at lines ~228–233 claims this proves "a real `--agent-id` argv token" and cites the concrete failure it must prevent: a claude session whose *prose TASK argument* contains the literal string `--agent-id <name>@session-8891c11f`. That string, embedded in an argument, contains ` --agent-id ` with surrounding spaces and therefore **passes this case**. The other two legs do not exclude it either: such a host is itself `claude.exe`, so line ~269 passes, and the extracted `agid` (`foo@session-<lead>`) satisfies both the suffix test and the shaped-id test. `resolve_assignee` returns 0, `main` prints "identity proven from it2 pane liveness + argv", and step 3 sends `kill -TERM`/`kill -KILL` to an unrelated live session and closes its pane. The guard does not cover the class it names — flag-vs-argument is not recoverable from `ps args=` output.

---

### 3. The guard and the value extraction can match different occurrences of `--agent-id`

**Where** — `resolve_assignee`, lines ~270–271:
```bash
    case " $rargs " in *" --agent-id "*) ;; *) continue ;; esac
    agid="${rargs#*--agent-id }"; agid="${agid%% *}"   # the token AFTER the real flag
```

**Why it is wrong** — The `case` validates a **space-delimited** ` --agent-id `; the `${rargs#*--agent-id }` strip is anchored on nothing and consumes up to the **first** occurrence of the substring `--agent-id ` anywhere in the string, including one embedded in a longer flag or in an earlier argument. For argv such as `claude.exe --foo=--agent-id x ... --agent-id real@session-LEAD`, `agid` becomes `x`, the suffix test fails, the loop `continue`s, and a genuine assignee is skipped — the function returns 2 and `main` records `REFUSE assignee-unproven`, reproducing the "100% abstain BY CONSTRUCTION" inertness this function was written to end. In the mirror case (an earlier prose occurrence whose value *does* end in `@session-$lead`), the kill is authorized by a token that is not the process's real `--agent-id`.

---

### 4. An empty `pid` silently skips the tty-exclusivity guard and is then counted as "process gone"

**Where** — line ~182, plus the step-2c and step-4 tests:
```bash
pid_alive()  { [ -n "${1:-}" ] && kill -0 "$1" 2>/dev/null; }
```
```bash
  if pid_alive "$pid"; then
    local fc; fc="$(tty_foreign "$pid")"
```
```bash
  if ! pid_alive "$pid"; then
    proc_gone=1
```

**Why it is wrong** — `resolve()` succeeds on any row with a `paneUUID` (`[ -n "$paneUUID" ] || return 1`); `pid` is filled from `jq -r '.pid // empty'` and is `""` for a retained row with no/null pid. With `pid=""`, `pid_alive` is false purely because of its `-n` guard, so (a) step 2c's tty-exclusivity check is **skipped entirely** rather than fail-closed — contrast `tty_foreign`'s own `-1` → `DEFER tty-indeterminate` for the same "cannot tell" condition the header promises to defer on — and (b) step 4 sets `proc_gone=1`, asserting the process leg is verified when no process was ever identified, let alone re-observed. If the pane then closes, the run records `TEARDOWN ... "both legs effect-verified (re-observed)"` with `both_legs_verified: true` and exits 0, contradicting "only a re-observation counts."

---

### 5. The assignee already-gone branch reports both legs verified after observing only the pane

**Where** — `main`, step 1b-A, line ~422:
```bash
        1) record ALREADY-GONE idempotent "assignee pane '$TARGET' is absent from a READABLE it2 enumeration — nothing to close" 1
```

**Why it is wrong** — rc 1 from `resolve_assignee` is returned at leg 1 (`[ -n "$obj" ] || return 1`), before leg 3 ever runs, so **no pid was resolved and no process was checked**. The trailing `1` sets `both_legs_verified: true` in the record and the caller gets exit 0. If the assignee's pane is gone (or unseen) while its `claude.exe` still runs, the crash-watchdog caller is told the teardown is complete and stops. The registry path for the same claim is stricter: it requires `! pid_alive "$pid"` *and* `pp0 = 1` before recording the identical `ALREADY-GONE ... 1`.

---

### 6. The teardown marker is left in place on the FAIL-LOUD path, masking a genuine crash of a still-live session

**Where** — step 2d, and the exit-5 block:
```bash
  write_teardown_marker "$paneUUID" "$sess_id" teardown
```
```bash
  say "FAIL — teardown NOT verified: proc_gone=$proc_gone pane_gone=$pane_gone close_rc=$close_rc (exit 5)"; exit 5
```

**Why it is wrong** — Exit 5 means, by definition, that the process and/or the pane **survived**; the target is still live. The marker's own justification for late writing (step 2d comment) is that "a REFUSE/DEFER leaves the target ALIVE, and a stale marker would mask a genuine crash of that live session for the reader's whole 30-min freshness window." The exit-5 path produces precisely that state — a live session carrying a `mode=teardown` marker under both its sid and pane keys — and nothing removes it ("Writers never delete markers"). If that surviving session then genuinely crashes inside the reader's freshness window, `classify_death` reads the marker and classifies a real crash as a deliberate teardown. The selftest asserts no marker on DEFER (scenario 3) but never checks the FAIL path (scenario 2).

---

### 7. The gate's raw exit code is propagated, so cc-teardown can exit with codes outside its documented contract — including 5

**Where** — step 2:
```bash
  gate_out="$("$GATE" decide --cwd "$cwd" --done-evidence "$done_ev" 2>/dev/null)"; grc=$?
```
```bash
    say "$gdec — $greason (exit $grc)"; exit "$grc"
```

**Why it is wrong** — If `$GATE` is missing or not executable (the default is `HERE`-relative, and the selftest derives it from `$0` — see defect 9), the command substitution returns 127 with empty output. `gdec` then falls to `DEFER` (since `[ "$grc" = 2 ]` is false), the run **records `DEFER`** — and exits **127**, which is not one of the documented `0 / 2 / 5 / 10` codes, so a caller branching on 10 sees an unclassified failure rather than the DEFER that was recorded. Worse, if the gate ever exits 5, cc-teardown exits 5, whose documented meaning is "FAIL LOUD (acted, but effect-verify says the pane/process SURVIVED)" — reporting an action that never took place, from a path that never reached step 3.

---

### 8. `die` exits 2 (the REFUSE code) without writing any record

**Where** — line ~121 and its call sites, lines ~403 and ~407:
```bash
die()  { say "$*"; exit 2; }
```
```bash
      --*) die "unknown option '$1'" ;;
```
```bash
  [ "${#args[@]}" -ge 1 ] || die "usage: cc-teardown <pane-uuid|name> --done-evidence <text>"
```

**Why it is wrong** — A mistyped flag (`--done-evidance`) or a missing positional argument produces exit 2 with **no file in `$RECORDS_DIR`**, violating the stated invariant "NO silent teardown: every decision branch writes one outcome record" (line ~134) and step 5's "RECORD every branch." The `--self` arm of the same `case` records before exiting, showing the intended contract. Because exit 2 is the REFUSE code, an autonomous caller cannot distinguish a wiring bug from a policy verdict — the same mistake the file documents at lines ~211–213, where a watchdog counted a structural `REFUSE unknown-target` as "a *trusted* policy refusal" and abstained forever.

---

### 9. `--selftest` resolves the gate path from `$0` instead of the symlink-resolved `HERE`

**Where** — in `selftest`:
```bash
  GATE_SELF="$(cd "$(dirname "$0")" && pwd)/cc-teardown-safety-gate.sh"
```

**Why it is wrong** — Lines 74–79 deliberately walk `$0` through symlinks precisely because the supported deployment is a `~/.claude/bin/cc-teardown` symlink with the gate left in the repo `bin/` ("deploy only this one file"). Invoked through that symlink, `dirname "$0"` is `~/.claude/bin`, so `CC_TEARDOWN_GATE_BIN` points at a non-existent `~/.claude/bin/cc-teardown-safety-gate.sh`. Every gate-dependent scenario (1, 2, 3, 4, 10, 12) then returns 127/DEFER and reports `FAIL` — the suite goes red for a path-resolution artifact of the test harness, not for the branch each scenario claims to RED-prove, while the code under test is behaving correctly.

---

### 10. Selftest scenarios assert only the exit code and `decision`, so several can go green for a branch other than the one they name

**Where** — e.g. scenario 5:
```bash
  [ "$rc" = 2 ] && [ "$(last_decision)" = REFUSE ] \
    && okp "missing done-evidence → REFUSE (exit 2) — done never inferred" \
```
and `run_td`, which sets no `CC_INTERACTIVE_LIB`, `CC_CLASSIFY_PROJECT_ROOTS`, or `CC_CLASSIFY_INTERACTIVE_HOLD_DISABLE`:
```bash
    CC_TEARDOWN_DIR="$d/tdmark" \
    "$@" --decided-at "$(date +%s)"
```

**Why it is wrong** — `reason_kind` is recorded but never asserted, and every REFUSE branch (`self-literal`, `unknown-target`, `self`, `identity-pin`, `operator-adopted`, `presence-unprovable`, `lease-*`, and the gate's) yields the same `rc=2` / `decision=REFUSE` pair. Because the harness does not neutralize the adoption belt, the belt runs live against the operator's real environment: if `hooks/lib/cc-interactive.sh` is absent — which the file itself states is possible ("the WHO-primitive is hooks/lib/cc-interactive.sh (lands separately)") — and no `cc-beat.sh` is found, `beat_or_refuse` refuses **every** run at exit 2/REFUSE before the gate is ever called. Scenario 5 then prints `ok "missing done-evidence → REFUSE (exit 2) — done never inferred"` although done-evidence was never examined. The same harness also lets `find_transcript` search the real `$HOME/.claude/projects*` roots for `s.jsonl`, so scenario outcomes depend on state outside the temp dir.