I read the file in full. Three defects.

**1. The anti-rot enumeration is hard-coded, not read out of the lib as claimed.**

Where, lines 246-250:
```bash
modal_fragments() {
  printf '%s\n%s\n%s\n%s\n' \
    "$CC_MODAL_MCP_HEADER" "$CC_MODAL_MCP_OPTION" \
    "$CC_MODAL_TRUST_HEADER" "$CC_MODAL_TRUST_OPTION" | tr '|' '\n'
}
```
Why it is wrong: the header comment and the anti-rot section both promise that "a class added tomorrow is pinned tomorrow without anyone remembering to extend this file." But the function names exactly four variables. A fifth modal class added to the lib under a new `CC_MODAL_*` name is never enumerated, so its fragments are never checked against the binary and the test stays green while that matcher rots. The same shape also hides a missing default: setup unsets all four variables, and if the lib fails to define one, the fragment is an empty string, which the loop at line 256 (`[ -n "$frag" ] || continue`) silently skips. The guard does not cover the class it says it covers.

**2. The positive control passes for the wrong reason on a grep error.**

Where, lines 275-276:
```bash
  run bash -c "LC_ALL=C grep -qaF -- 'Do you trust the files in this folder' '$BIN'"
  [ "$status" -ne 0 ] || false
```
Why it is wrong: this arm exists to prove the anchor above "CAN fail" and to catch "a bad path". But grep exits 2 on an unreadable or nonexistent file, and bash exits 2 on a syntax error if `$BIN` contains a single quote or otherwise breaks the interpolated command string. Every one of those outcomes satisfies `-ne 0`. The control therefore reads green in exactly the broken-invocation cases it claims to distinguish from a genuine absence. Only exit status 1 means "searched and did not find".

**3. An explicit override pointing at a missing file is downgraded to a skip.**

Where, lines 224-227 together with line 253:
```bash
  if [ -n "${CC_MODAL_ANCHOR_BIN:-}" ]; then
    [ -f "$CC_MODAL_ANCHOR_BIN" ] && { printf '%s' "$CC_MODAL_ANCHOR_BIN"; return 0; }
    return 1
  fi
```
```bash
  BIN="$(claude_binary)" || skip "no claude binary under \$HOME/.claude-*/ — the anchor cannot run, and that is a NON-VERDICT, not a pass"
```
Why it is wrong: the skip message asserts the reason is "no claude binary under $HOME/.claude-*/", but the same return code is produced when the operator deliberately set `CC_MODAL_ANCHOR_BIN` and the path is wrong. A typo in the pin, or a track removed after the pin was written, silently disables both anti-rot arms with a message that misreports the cause. The test that exists to catch drift against the binary is skipped precisely when the operator has told it which binary to use.
