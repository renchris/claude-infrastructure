I found three defects, all in the test logic. Line numbers come from my count of the brief's text, so they may be off by one.

**1. The anti-rot test passes when it checks nothing.**
- **What:** The test has no check that any fragment was actually verified, so an empty fragment list counts as success.
- **Where:** line 252, `    [ -n "$frag" ] || continue`, together with line 255, `  done <<< "$(modal_fragments)"`.
- **Why it is wrong:** `modal_fragments` (lines 242–246) expands `$CC_MODAL_MCP_HEADER` and the other three variables. Suppose the lib stops defining them under those names, sets them empty, or moves to a different mechanism. Every line is then blank and skipped, `missing` stays empty, and the test goes green having compared nothing to the binary. That is the silent, inert-matcher failure the file says it exists to catch. There is no count of fragments checked and no assertion that the list is non-empty.

**2. The negative control passes on any failure, not only on "string absent".**
- **What:** The control asserts only that the command exited non-zero, which does not distinguish grep's "no match" (1) from an error (2) or a failure of the `bash -c` invocation.
- **Where:** line 270, `  run bash -c "LC_ALL=C grep -qaF -- 'Do you trust the files in this folder' '$BIN'"`, and line 271, `  [ "$status" -ne 0 ] || false`.
- **Why it is wrong:** If `$BIN` is unreadable, is removed between resolution and use, or contains a `'` that breaks the quoting, grep or bash exits non-zero for a reason unrelated to the fragment. The control then reports "the anchor can fail" while proving nothing about the search. The test exists to show the grep can return "absent" on a real binary, but it only checks for some non-zero status. Only a status of exactly 1 would show that.

**3. "Every slug carries a remedy" is only tested for one real slug.**
- **What:** The test claims to cover every slug but checks the remedy for only `mcp-trust-modal` (plus an unknown slug).
- **Where:** line 189, `  run pane_modal_remedy mcp-trust-modal`, under the test named on line 188, `@test "every slug carries a remedy, and an unknown slug still yields one" {`.
- **Why it is wrong:** `workspace-trust-modal`, the other slug the suite says exists, is never passed to `pane_modal_remedy`. If its remedy is missing, empty, or wrong, the test still passes. The unknown-slug check at lines 192–194 only requires non-empty output, so a generic fallback would satisfy it for the trust slug as well.
