I found three defects in `bin/cc-teardown`.

---

### Defect 1

1. **What:** A target whose registry row has no pid is treated as "process already dead". Its process leg then counts as verified, even though nothing was ever killed or checked.

2. **Where:** line in `pid_alive`, used by the idempotent check, the kill leg and the effect-verify:
   ```
   pid_alive()  { [ -n "${1:-}" ] && kill -0 "$1" 2>/dev/null; }
   ```
   and in step 4:
   ```
     if ! pid_alive "$pid"; then
       proc_gone=1
   ```

3. **Why it is wrong:**
   - **Trigger:** `resolve()` sets `pid=""` whenever the cc-sessions row lacks `.pid`, which its `// empty` allows. The row still has a `paneUUID`, so resolve succeeds.
   - **What follows:**
     - `pid_alive ""` returns false.
     - The tty-exclusivity guard (2c) is skipped entirely.
     - `kill -TERM` is skipped.
     - `proc_gone=1` is set without any re-observation.
   - **Result:** The pane is force-closed and recorded as `TEARDOWN` with `both_legs_verified: true`. Meanwhile any claude process in that pane was never identified, killed or verified gone. An unknown pid is read as proof of absence, and a success is reported for a leg that never ran.

---

### Defect 2

1. **What:** The assignee identity check does not prove that `--agent-id` is a real argv token. It matches a space-delimited substring in the flattened `ps -o args=` string, so prose text containing that substring passes.

2. **Where:** in `resolve_assignee`:
   ```
       case " $rargs " in *" --agent-id "*) ;; *) continue ;; esac
       agid="${rargs#*--agent-id }"; agid="${agid%% *}"   # the token AFTER the real flag
   ```

3. **Why it is wrong:**
   - `ps -o args=` joins argv with spaces, so argument boundaries are lost.
   - The comment describes the known case: a `claude.exe` process whose prose task argument contains `... --agent-id foo@session-<lead> ...`.
   - That process has `argv[0]` basename `claude.exe`, so it passes the first check.
   - It also contains ` --agent-id `, and the following word is the well-shaped `foo@session-<lead>`.
   - All the checks therefore pass. The unrelated live session is adopted, its pid is killed and its pane is closed.
   - The guard does not cover the class it claims to cover: "text is never evidence".

---

### Defect 3

1. **What:** When the gate exits with a status other than 0, 2 or 10, that status is passed straight through as the script's exit code, while the decision is recorded as DEFER. Some exits also skip the decision record.

2. **Where:**
   ```
       [ -n "$gdec" ] || { [ "$grc" = 2 ] && gdec=REFUSE || gdec=DEFER; }
   ...
       say "$gdec — $greason (exit $grc)"; exit "$grc"
   ```
   and
   ```
   die()  { say "$*"; exit 2; }
   ```
   (used for `--*) die "unknown option '$1'"` and the missing-target usage path).

3. **Why it is wrong:**
   - **Gate pass-through:**
     - If the gate binary is missing or not executable, it returns 126 or 127. A crashing gate returns 1.
     - The record says `DEFER`, but the process exits 127 or 1. That is not in the documented 0/10/2/5 contract.
     - A caller keyed on 10 or 2 cannot classify the outcome, so the recorded decision and the reported exit disagree.
   - **Unrecorded refusals:** The unknown-option and missing-target paths `die` with exit 2 (REFUSE) without calling `record`. This breaks the stated invariant "every decision branch writes one outcome record", and the refusal is not auditable.
