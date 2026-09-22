# Review of `tests/pane-modal.bats`

I found 9 defects. They are ordered roughly by severity.

---

### 1. The anti-rot test passes with zero fragments checked

**What:** The ANTI-ROT test skips empty fragments and never asserts that at least one fragment was actually checked, so it can go green having checked nothing.

**Where:**
- Line 252: `    [ -n "$frag" ] || continue`
- Line 256: `  if [ -n "$missing" ]; then`

**Why it is wrong:**
- `setup()` unsets all four `CC_MODAL_*` variables (line 25). So `modal_fragments` only sees values if sourcing the lib assigns those variables at source time.
- The lib might instead supply its defaults at call time, for example `${CC_MODAL_MCP_HEADER:-…}` inside `pane_modal_reason`. It might also rename one of these variables.
- In either case the affected fragments are empty, the loop `continue`s past them, and `missing` stays empty. The test passes.
- That is the silent, inert-matcher failure the header (lines 12–14) says this arm exists to catch.

---

### 2. A class added tomorrow is not pinned, despite the header's claim

**What:** `modal_fragments` hard-codes the four current variable names. The header says a class added tomorrow is pinned automatically, but it is not.

**Where:**
- Lines 244–245: `    "$CC_MODAL_MCP_HEADER" "$CC_MODAL_MCP_OPTION" \` / `    "$CC_MODAL_TRUST_HEADER" "$CC_MODAL_TRUST_OPTION" | tr '|' '\n'`
- The claim is at lines 15–16: `fragments OUT OF THE LIB rather than restating them, so a class added tomorrow is pinned` / `tomorrow without anyone remembering to extend this file.`

**Why it is wrong:**
- Suppose the lib gains a third class, for example `CC_MODAL_FOO_HEADER`/`CC_MODAL_FOO_OPTION`.
- Its fragments are never emitted, so they are never grepped against the binary.
- If that class's wording drifts, the ANTI-ROT test stays green. The new class is unpinned until someone remembers to extend this file, which is exactly what the header says will not be needed.

---

### 3. The environment pin covers only the four named seams

**What:** The M11 environment pin unsets only the four known pattern seams, so a new class's seam is inherited from the ambient environment.

**Where:** Line 25: `  unset CC_MODAL_MCP_HEADER CC_MODAL_MCP_OPTION CC_MODAL_TRUST_HEADER CC_MODAL_TRUST_OPTION`

**Why it is wrong:**
- Take any seam the lib adds beyond these four, set in the invoking shell.
- Its inherited value silently replaces the pattern under test.
- This is the failure lines 23–24 say the pin prevents.

---

### 4. The anti-rot positive control counts a grep error as success

**What:** The positive control accepts any non-zero exit, so a grep *error* passes as proof that the fragment is absent.

**Where:**
- Line 270: `  run bash -c "LC_ALL=C grep -qaF -- 'Do you trust the files in this folder' '$BIN'"`
- Line 271: `  [ "$status" -ne 0 ] || false`

**Why it is wrong:**
- grep exits 2 on an error. That happens if `$BIN` is unreadable (for example, a permissions problem).
- `bash -c` also exits 2 on a syntax error. That happens if `$BIN` contains a `'`, which breaks the single-quoting.
- Either way `status` is 2 and the control passes, even though no search ran.
- Line 266 names "a bad path" as the case this control guards against, yet a bad path is exactly what it passes.

---

### 5. The anti-rot positive control never exercises the anti-rot test

**What:** The positive control runs its own standalone grep, so it cannot show that the ANTI-ROT test is able to fail.

**Where:** Line 270: `  run bash -c "LC_ALL=C grep -qaF -- 'Do you trust the files in this folder' '$BIN'"`

**Why it is wrong:**
- Lines 265–266 say this arm catches "a stray `|| true`" in the anchor test.
- But it never runs `modal_fragments`, the `while` loop, the `missing` accumulation, or the final `false` from lines 249–261.
- A stray `|| true` on line 253 would leave this control green. So would an empty-fragment short-circuit (defect #1) or a broken `if` at line 256.

---

### 6. The "unanchored" positive control also changes the pattern text

**What:** The "unanchored" control replaces the pattern *text* as well as removing the anchor, so it does not prove the anchor is what refuses the RED-PROOF prose.

**Where:**
- Line 113: `  CC_MODAL_MCP_HEADER=".*New MCP server found"`
- Line 114: `  CC_MODAL_MCP_OPTION=".*Use this MCP server"`

**Why it is wrong:**
- Suppose the lib's defaults are longer or different, for example a header of `New MCP server found in this project:` with the colon.
- Then the RED-PROOF prose (lines 105–106) is refused because the text does not match, not because of the anchor.
- This control still fires, because it swapped in shorter hand-written text.
- So "the anchor is load-bearing" is asserted without isolating the anchor. The control is not `.*` plus the lib's own pattern.

---

### 7. The "replaces, not adds" test cannot tell which override replaced

**What:** The test overrides header *and* option together, so its check that the default no longer matches passes even if one of the two overrides is additive.

**Where:**
- Lines 177–178: `  CC_MODAL_MCP_HEADER="Totally New Dialog"` / `  CC_MODAL_MCP_OPTION="press 1 to continue"`
- Lines 184–185: `  run classify "$(mcp_screen)"` / `  [ "$status" -eq 1 ] || false`

**Why it is wrong:**
- Suppose the lib appends the header override to its default (`default|override`) but replaces the option.
- `mcp_screen` still matches the header. It fails the option, because "press 1 to continue" is not on screen, so `status` is 1 and the test passes.
- The mirror case, option additive and header replaced, also passes.
- Only "at least one of the two replaces" is proven, not the stated property for a pattern.

---

### 8. "Every slug carries a remedy" checks only one slug

**What:** The test only checks `mcp-trust-modal`. The `workspace-trust-modal` slug is never checked.

**Where:** Line 189: `  run pane_modal_remedy mcp-trust-modal` (the only real slug exercised, lines 188–194)

**Why it is wrong:**
- Suppose `pane_modal_remedy` has no arm for `workspace-trust-modal`, or a misspelled one.
- It falls through to the generic unknown-slug remedy, and every assertion here still passes.
- That slug's operator-facing remedy is wrong or missing with nothing red.

---

### 9. The cross-satisfy test covers only one direction

**What:** The per-class conjunction is tested in one direction only (MCP header + trust option). Trust header + MCP option is never tried.

**Where:**
- Line 158: `  run classify "New MCP server found in this project`
- Line 159: `1. Yes, I trust this folder"`

**Why it is wrong:**
- Suppose the lib's trust rule is `TRUST_HEADER && (TRUST_OPTION || MCP_OPTION)`.
- A pane showing the trust header in prose next to a quoted MCP menu line would then be reported wedged as `workspace-trust-modal`.
- This test passes, because its input has no trust header.

---

## Lower-severity defects

### 10. The "unreadable pane" test feeds a readable, empty pane

**What:** The test does not feed an unreadable pane. `classify` turns `""` into a single newline.

**Where:**
- Line 170: `  run classify ""`
- Line 66: `classify() { printf '%s\n' "$1" | pane_modal_reason; }`

**Why it is wrong:**
- A failed capture yields zero bytes, or no stdin at all.
- This test only covers "a readable pane with one blank line", so how `pane_modal_reason` behaves on truly empty input is untested despite the test's name.

### 11. One stray directory or a wrong override disables the anti-rot arm

**What:** Two cases degrade the anti-rot arm to a skip:
- the numerically newest `.claude-N` entry exists but holds no binary;
- `CC_MODAL_ANCHOR_BIN` is set but points at a missing file.

In both cases the skip message says no binary exists under `$HOME/.claude-*`.

**Where:**
- Line 233: `  [ -n "$t" ] || return 1`
- Lines 236–238: `    [ -f "$p" ] && { printf '%s' "$p"; return 0; }` … `  return 1`
- Line 223: `    return 1`

**Why it is wrong:**
- One stray or half-installed `.claude-999` (it is not even checked to be a directory) wins the numeric max. Every later run then skips both anti-rot tests, even though real binaries sit in `.claude-220`.
- An explicit but mistyped override is reported as "no claude binary under $HOME/.claude-*/". The skip reason names the wrong cause for a check that is being skipped.
