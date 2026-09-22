Three defects, all in the anti-rot section. The dialog-matching tests above it look sound as far as this file shows.

---

### 1. The anti-rot test passes when no fragment was checked at all

**What:** The ANTI-ROT test never checks that `modal_fragments` produced any non-empty fragment, so it passes even if nothing was compared against the binary.

**Where:** lines in `modal_fragments` and in the ANTI-ROT loop:
```bash
    "$CC_MODAL_MCP_HEADER" "$CC_MODAL_MCP_OPTION" \
```
```bash
    [ -n "$frag" ] || continue
```
```bash
  if [ -n "$missing" ]; then
```

**Why it is wrong:**
- `setup()` unsets all four `CC_MODAL_*` variables before sourcing the lib.
- The fragments are read from those same global variables.
- Suppose the lib applies its defaults inside `pane_modal_reason`, for example as `${CC_MODAL_MCP_HEADER:-…}`, rather than assigning the globals when it is sourced. Then every variable is empty.
- The same happens if a future refactor renames the variables.
- In either case every line hits `continue` and `missing` stays empty. The test reports green having checked zero strings against the binary.
- This is exactly the silent, inert-matcher failure the header says this arm exists to catch.

### 2. The "positive control" does not exercise the mechanism it claims to prove

**What:** The control runs its own separate `grep` on a hard-coded string, so it cannot show that the ANTI-ROT test above it can fail.

**Where:**
```bash
  run bash -c "LC_ALL=C grep -qaF -- 'Do you trust the files in this folder' '$BIN'"
  [ "$status" -ne 0 ] || false
```

**Why it is wrong:**
- The comment says the control guards against the anchor test being "unfalsifiable-looking" because of "a bad path, a stray `|| true`".
- The control never goes through `modal_fragments`, the `while read` loop, the empty-fragment `continue`, or the `missing` / `false` reporting.
- So a stray `|| true`, a broken fragment split, or the empty-fragment vacuity in defect 1 would leave the anchor test always-green while this control still passes.
- It only proves that `grep -F` works on a string that is absent from the binary. It proves nothing about the anchor test.

### 3. An explicit binary override that points at a missing file skips instead of failing

**What:** When `CC_MODAL_ANCHOR_BIN` is set to a path that does not exist, `claude_binary` returns 1 and both anti-rot tests `skip`. A misconfiguration silently becomes a non-verdict.

**Where:**
```bash
    [ -f "$CC_MODAL_ANCHOR_BIN" ] && { printf '%s' "$CC_MODAL_ANCHOR_BIN"; return 0; }
    return 1
```
```bash
  BIN="$(claude_binary)" || skip "no claude binary under \$HOME/.claude-*/ — the anchor cannot run, and that is a NON-VERDICT, not a pass"
```

**Why it is wrong:**
- Take a box that pins a different binary and sets the override with a typo, or with a path that goes stale after an upgrade.
- The anchor never runs, and it never says the operator's explicit choice was invalid.
- The skip message it prints ("no claude binary under $HOME/.claude-*/") is also wrong for this case: the override was set, and the glob was never consulted.
- Bats counts skips as non-failures, so CI stays green and the drift check is off indefinitely.
- The same thing happens when the newest `.claude-N` directory exists but holds neither `bin/claude.exe` nor `cli.js`, such as a half-finished install. The function returns 1 without trying any older track that does have a binary. Every run then skips while a checkable binary sits on disk.
