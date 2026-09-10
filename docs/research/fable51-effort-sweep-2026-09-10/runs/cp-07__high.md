Reviewing `tests/pane-modal.bats` from the brief text only.

I found four defects, all in the anti-rot section. The dialog-classification tests themselves are consistent with what they claim to test.

**1. The anti-rot test can pass having checked nothing.**

- **Where:** lines 25, 244–245, 252
  ```bash
  unset CC_MODAL_MCP_HEADER CC_MODAL_MCP_OPTION CC_MODAL_TRUST_HEADER CC_MODAL_TRUST_OPTION
  "$CC_MODAL_MCP_HEADER" "$CC_MODAL_MCP_OPTION" \
  [ -n "$frag" ] || continue
  ```
- **Why it is wrong:** The header comment says the fragments are read out of the lib, but the code reads four shell variables that setup explicitly unset. If the sourced lib does not materialize its defaults into those exact variables at source time, for example because it expands `${VAR:-default}` inside the function or keeps defaults in differently named variables, every line from `modal_fragments` is empty, the `continue` skips all of them, `missing` stays empty, and the test goes green with zero greps run. There is no assertion that at least one fragment was examined, so the arm that exists to catch silent rot is itself capable of silently doing nothing.

**2. The positive control accepts a grep error as proof the string is absent.**

- **Where:** lines 270–271
  ```bash
  run bash -c "LC_ALL=C grep -qaF -- 'Do you trust the files in this folder' '$BIN'"
  [ "$status" -ne 0 ] || false
  ```
- **Why it is wrong:** `grep` exits 1 for no match and 2 for an error such as an unreadable file or a mangled path. The assertion only requires non-zero, so a control whose grep could not read the binary at all passes as "the anchor CAN fail". The comment says this arm exists to catch a bad path, but a bad path produces exit 2 and passes.

**3. An explicit but wrong override is downgraded to a skip.**

- **Where:** lines 221–223 and 249
  ```bash
  [ -f "$CC_MODAL_ANCHOR_BIN" ] && { printf '%s' "$CC_MODAL_ANCHOR_BIN"; return 0; }
  return 1
  BIN="$(claude_binary)" || skip "no claude binary under \$HOME/.claude-*/ — the anchor cannot run, and that is a NON-VERDICT, not a pass"
  ```
- **Why it is wrong:** When the operator sets `CC_MODAL_ANCHOR_BIN` to a path that does not exist, the function returns 1 and the test skips with a message about the `$HOME/.claude-*` glob that was never consulted. A deliberate pin to a missing file is a configuration error, not "no binary installed", and it is reported as a non-verdict rather than a failure. On a box that relies on the override, the anti-rot check disappears without anyone being told.

**4. Regex patterns are grepped as fixed strings.**

- **Where:** lines 245 and 253
  ```bash
  "$CC_MODAL_TRUST_HEADER" "$CC_MODAL_TRUST_OPTION" | tr '|' '\n'
  LC_ALL=C grep -qaF -- "$frag" "$BIN" || missing="$missing
  ```
- **Why it is wrong:** The seams test at lines 113–114 proves the patterns are regexes, since `.*` is honoured. The fragment splitter only handles top-level `|`, and the grep uses `-F`. Any pattern that uses a group like `(a|b)`, an escaped metacharacter such as `\?` for the trust header's question mark, or a bracket class is searched for literally, including its backslashes and parentheses. Such a fragment will never be found in the binary, so the test reports rot for a matcher that is live, and the operator is told to rewrite a correct pattern.
