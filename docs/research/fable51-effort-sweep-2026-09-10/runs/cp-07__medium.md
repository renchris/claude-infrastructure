Reviewing the bats file for defects, using only the brief text.

**Defect 1**

- **What:** The anti-rot positive control accepts a grep error as proof that the string is absent, so it passes for the wrong reason.
- **Where:** line 268
  ```
  [ "$status" -ne 0 ] || false
  ```
- **Why it is wrong:** `grep` exits 1 for "no match" and 2 for an error such as an unreadable file or a bad path. The comment says this arm exists to prove that a bad path or a stuck `grep` would not read the same as a real absence, yet an erroring `grep` yields status 2 and satisfies `-ne 0`. Under exactly the fault the control claims to catch, it goes green.

**Defect 2**

- **What:** The anti-rot anchor test passes vacuously when the enumeration yields no fragments, so it cannot detect the case where it has nothing to audit.
- **Where:** lines 244 and 246
  ```
    [ -n "$frag" ] || continue
  ```
  ```
    LC_ALL=C grep -qaF -- "$frag" "$BIN" || missing="$missing
  ```
- **Why it is wrong:** `modal_fragments` expands the four `CC_MODAL_*` variables in the bats shell. `setup()` unsets them before sourcing the lib, so they are only populated if the lib assigns them at source time. If the lib reads them as call-time defaults instead, or a future change renames a variable, every line is empty, every line is skipped, `missing` stays empty, and the test reports green having checked nothing. The test never asserts that at least one fragment was checked.

**Defect 3**

- **What:** A `CC_MODAL_ANCHOR_BIN` override pointing at a missing file turns the anchor into a skip rather than a failure, with a message that misstates the cause.
- **Where:** lines 208 to 209 and 239
  ```
      [ -f "$CC_MODAL_ANCHOR_BIN" ] && { printf '%s' "$CC_MODAL_ANCHOR_BIN"; return 0; }
      return 1
  ```
  ```
    BIN="$(claude_binary)" || skip "no claude binary under \$HOME/.claude-*/ — the anchor cannot run, and that is a NON-VERDICT, not a pass"
  ```
- **Why it is wrong:** When the operator sets the override to a wrong path, `claude_binary` returns 1 without consulting the `.claude-*` tracks, and both anti-rot tests skip. The skip text blames the absence of installed tracks, which is false. A misconfigured explicit pin is a failure of the test harness, but it is reported as a benign non-verdict, and the rot check is silently not run.

**Defect 4**

- **What:** The anchor test conflates a grep error with a fragment being absent and tells the maintainer that the dialog was reworded.
- **Where:** lines 246 and 250
  ```
    LC_ALL=C grep -qaF -- "$frag" "$BIN" || missing="$missing
  ```
  ```
      echo "Claude Code reworded a dialog. Re-read the strings out of the binary and update"
  ```
- **Why it is wrong:** If `$BIN` exists but is unreadable, `grep` exits 2 for every fragment and every fragment lands in `missing`. The test then goes red with an instruction to rewrite the lib's strings, when nothing about the strings has changed. The failure is real but the reported cause is wrong, and following the printed remedy would damage a correct enumeration.

**Defect 5**

- **What:** The test that claims to cover an unreadable pane only exercises an empty pane.
- **Where:** lines 169 to 171
  ```
  @test "an unreadable pane fails CLOSED to not-wedged, never to wedged" {
    run classify ""
    [ "$status" -eq 1 ] || false
  ```
- **Why it is wrong:** `classify ""` feeds a single newline to `pane_modal_reason`. That is a readable pane with no content, not a failed capture. Whatever the callers in `cc-spawn-verify` and `handoff-fire.sh` feed the function when `tmux capture-pane` fails, this test does not produce it, so the "fails closed" claim for that class is unproven.

No other defects found. The rest of the file's assertions use `[ ]` with `|| false` as the header prescribes, each bats test runs in its own process so the env overrides in individual tests do not leak, and the numeric track selection in `claude_binary` correctly rejects the unmatched literal glob.
