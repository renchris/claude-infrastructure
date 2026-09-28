I found six defects in `tests/pane-modal.bats`; four are tests that can pass or skip for the wrong reason, and two are guards that do not cover what they claim to.

**1. The anti-rot enumeration covers only four hardcoded classes, contradicting its stated purpose.**
- **What:** The header promises that "a class added tomorrow is pinned tomorrow without anyone remembering to extend this file", but the fragment list restates the four variable names by hand.
- **Where:**
  - Lines 243–245: `printf '%s\n%s\n%s\n%s\n' \` / `"$CC_MODAL_MCP_HEADER" "$CC_MODAL_MCP_OPTION" \` / `"$CC_MODAL_TRUST_HEADER" "$CC_MODAL_TRUST_OPTION" | tr '|' '\n'`
  - Line 25: `unset CC_MODAL_MCP_HEADER CC_MODAL_MCP_OPTION CC_MODAL_TRUST_HEADER CC_MODAL_TRUST_OPTION`
- **Why it is wrong:** If the lib gains a third class with its own `CC_MODAL_<X>_HEADER` and `CC_MODAL_<X>_OPTION`, `modal_fragments` never emits its fragments. Its wording can rot out of the binary and the anchor stays green. The same fixed list in `setup()` means an inherited value for the new seam is not unset, so it silently replaces the subject.

**2. The anti-rot loop passes vacuously when no fragments are enumerated.**
- **What:** Empty fragments are skipped with no check that any fragment was actually verified.
- **Where:** Line 252: `[ -n "$frag" ] || continue`
- **Why it is wrong:** If the four variables are empty after `setup()`, `modal_fragments` yields only empty lines. This happens if the lib supplies its defaults inside the function rather than as variables at source time, or renames them. Every line is skipped, `missing` stays empty and the test passes with zero fragments checked. That is exactly the inert-matcher failure this arm exists to catch. The positive control at line 271 does not detect it, because it greps a fixed string.

**3. The positive control accepts any non-zero grep status, including an error.**
- **What:** The control asserts "not zero" rather than "not found".
- **Where:** Line 271: `[ "$status" -ne 0 ] || false`
- **Why it is wrong:** `grep -q` exits 1 for no match and 2 for an error. The command is `bash -c "... '$BIN'"`, so a `BIN` path containing a single quote gives a bash syntax error, and an unreadable file gives grep status 2. Both satisfy `-ne 0`, so the control goes green without ever proving the fragment is absent. The `-f` check inside `claude_binary` does not rule out an unreadable file.

**4. The remedy test claims to cover every slug but checks only one real slug.**
- **What:** The test title says "every slug carries a remedy", but `workspace-trust-modal` is never queried.
- **Where:** Line 189: `run pane_modal_remedy mcp-trust-modal` and line 192: `run pane_modal_remedy some-future-modal`
- **Why it is wrong:** If the lib's remedy function has no branch for `workspace-trust-modal`, or returns something useless for it, this test still passes. The only other call uses a made-up slug that just exercises the generic fallback.

**5. The newest-track selection never checks that the chosen track has a binary, so a bare newer dir disables the anchor.**
- **What:** The highest numeric `.claude-N` is chosen on the directory name alone, and only that track is searched for a binary.
- **Where:** Line 231: `if [ -z "$t" ] || [ "$n" -gt "$t" ]; then t="$n"; fi` and, downstream, line 238: `return 1`
- **Why it is wrong:** Suppose `~/.claude-221` exists as a config dir, a half-finished install, or an empty upgrade target, with no `node_modules/.../claude.exe` or `cli.js`. Then `t=221`, both `-f` probes fail and the function returns 1. The test then skips, even though 219 and 220 are installed, and the anchor stays off until that directory is removed.

**6. A misconfigured `CC_MODAL_ANCHOR_BIN` is reported as "no binary found" and skipped.**
- **What:** A deliberately set override that does not point at a file returns 1, which the caller turns into a skip with a message about `$HOME/.claude-*/`.
- **Where:** Lines 222–223: `[ -f "$CC_MODAL_ANCHOR_BIN" ] && { printf '%s' "$CC_MODAL_ANCHOR_BIN"; return 0; }` / `return 1`
- **Why it is wrong:** If the operator sets the override to a path that is mistyped, stale or unreadable, the drift check silently turns into a skip, and the skip text names the wrong cause. An explicit request to check a specific binary cannot be honoured, yet nothing fails.
