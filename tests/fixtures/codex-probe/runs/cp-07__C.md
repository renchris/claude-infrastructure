1.

- **What** — The remedy test claims to cover every modal slug but never calls `pane_modal_remedy` with the known `workspace-trust-modal` slug.
- **Where** — Lines 187–193:
  ```bash
  @test "every slug carries a remedy, and an unknown slug still yields one" {
    run pane_modal_remedy mcp-trust-modal
    [ "$status" -eq 0 ] || false
    echo "$output" | grep -q 'enabledMcpjsonServers' || false
    run pane_modal_remedy some-future-modal
    [ "$status" -eq 0 ] || false
    [ -n "$output" ] || false
  }
  ```
- **Why it is wrong** — If the explicit `workspace-trust-modal` branch fails, returns nothing, or returns the wrong remedy while the MCP and fallback branches work, this test still passes.

2.

- **What** — The anti-rot loop silently ignores empty pattern values and empty alternatives.
- **Where** — Lines 244 and 251:
  ```bash
      "$CC_MODAL_TRUST_HEADER" "$CC_MODAL_TRUST_OPTION" | tr '|' '\n'
      [ -n "$frag" ] || continue
  ```
- **Why it is wrong** — If a pattern is empty or contains an empty alternative such as a trailing `|`, the corresponding matcher arm is not validated at all, and the anti-rot test can succeed despite the invalid enumeration.

3.

- **What** — The main anti-rot check treats a `grep` execution error as proof that a fragment is absent.
- **Where** — Lines 252–258:
  ```bash
      LC_ALL=C grep -qaF -- "$frag" "$BIN" || missing="$missing
    $frag"
  ```
  ```bash
      echo "These fragments are NOT in $BIN — the matcher for them is INERT:$missing"
      echo "Claude Code reworded a dialog. Re-read the strings out of the binary and update"
      echo "hooks/lib/pane-modal.sh; do not delete this test to make it green."
  ```
- **Why it is wrong** — If `grep` returns status 2 because the file is unreadable or an I/O error occurs, the code reports that Claude reworded the dialog and directs the user to change the matcher, although absence was never established.

4.

- **What** — The purported positive control does not exercise the anti-rot loop it claims to validate.
- **Where** — Lines 252 and 269:
  ```bash
      LC_ALL=C grep -qaF -- "$frag" "$BIN" || missing="$missing
  ```
  ```bash
    run bash -c "LC_ALL=C grep -qaF -- 'Do you trust the files in this folder' '$BIN'"
  ```
- **Why it is wrong** — The second command is an independent restatement, so the loop can validate zero fragments or its own `grep` can be made ineffective while this separate command still fails and the positive-control test passes.

5.

- **What** — The binary path is inserted unescaped into shell source passed to `bash -c`.
- **Where** — Line 269:
  ```bash
    run bash -c "LC_ALL=C grep -qaF -- 'Do you trust the files in this folder' '$BIN'"
  ```
- **Why it is wrong** — If `$BIN` contains a single quote, which is valid in a pathname and can arrive through `CC_MODAL_ANCHOR_BIN` or `REAL_HOME`, the generated command is misparsed and may execute unintended shell text instead of searching that file.

6.

- **What** — The positive control accepts every nonzero exit status as confirmation that the sentinel string is absent.
- **Where** — Line 270:
  ```bash
    [ "$status" -ne 0 ] || false
  ```
- **Why it is wrong** — A shell syntax error, missing `grep`, unreadable binary, or other execution failure returns a nonzero status other than the expected no-match result, causing the test to pass without proving the string is absent.