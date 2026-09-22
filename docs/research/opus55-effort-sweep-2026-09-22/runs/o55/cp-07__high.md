# Review of `tests/pane-modal.bats`: five defects

Five defects. All of them are in the anti-rot arm or its setup. I found nothing wrong in the classifier tests themselves (lines 70–195).

---

### 1. The fragment list is hard-coded, so a new modal class is never checked

**What:** `modal_fragments` names the four existing pattern variables explicitly. The anti-rot arm therefore covers only the MCP and trust classes, not "whatever the enumeration currently says".

**Where:** lines 243–245
```
  printf '%s\n%s\n%s\n%s\n' \
    "$CC_MODAL_MCP_HEADER" "$CC_MODAL_MCP_OPTION" \
    "$CC_MODAL_TRUST_HEADER" "$CC_MODAL_TRUST_OPTION" | tr '|' '\n'
```

**Why it is wrong:** Suppose someone adds a third class to `hooks/lib/pane-modal.sh`, for example `CC_MODAL_FOO_HEADER` and `CC_MODAL_FOO_OPTION`. Its fragments are never grepped against the binary, and the ANTI-ROT test stays green. The file header (lines 15–16) and line 199 claim the opposite: "a class added tomorrow is pinned tomorrow without anyone remembering to extend this file". A stale fragment in the new class would be the silent, inert-matcher failure this arm exists to catch.

---

### 2. `setup` pins only four variables, so a new class's env seam is not pinned

**What:** The `unset` list is hard-coded to the same four variables, so a new class's pattern variables are not reset before the lib is sourced.

**Where:** line 25
```
  unset CC_MODAL_MCP_HEADER CC_MODAL_MCP_OPTION CC_MODAL_TRUST_HEADER CC_MODAL_TRUST_OPTION
```

**Why it is wrong:** If a new class's variable is set in the invoking environment, the lib picks up that inherited value instead of its default. The suite then tests the ambient value, which is the exact failure the M11 comment (lines 23–24) says this line prevents.

---

### 3. The ANTI-ROT test can pass without checking any fragment

**What:** Empty fragments are skipped, and nothing asserts that at least one fragment was actually grepped. An empty fragment set therefore produces a pass.

**Where:** line 252 (inside lines 251–255)
```
    [ -n "$frag" ] || continue
```

**Why it is wrong:** `setup` unsets all four variables (line 25) before sourcing the lib. The test only means something if the lib assigns them globally when sourced. Two cases break that:
- the lib applies its defaults only inside `pane_modal_reason` (for example `${CC_MODAL_MCP_HEADER:-…}` at call time), or
- the lib renames a variable.

In either case `modal_fragments` emits blank lines, every iteration hits `continue`, `missing` stays empty, and the test reports green after checking nothing. The positive control (defect 4) does not run this loop, so nothing catches the vacuous pass.

---

### 4. The positive control passes for the wrong reason and does not test the anchor

**What:** The control asserts only that grep's status is non-zero. A grep *error* satisfies that just as well as a genuine "string absent". The control also runs its own grep rather than the anchor's fragment loop.

**Where:** line 271 (with line 270)
```
  [ "$status" -ne 0 ] || false
```
```
  run bash -c "LC_ALL=C grep -qaF -- 'Do you trust the files in this folder' '$BIN'"
```

**Why it is wrong:** Several conditions produce a non-zero status and make the control pass:
- `$BIN` is missing or unreadable, so grep exits 2.
- `$BIN` contains a `'`, so the `bash -c` string fails to parse.

The comment at line 266 lists "a bad path" as the fault this control guards against. A bad path actually makes it pass. Separately, the control never calls `modal_fragments` or the `while … || missing=` loop from lines 251–255. It cannot show that "the anchor above CAN fail": a broken loop (as in defect 3) would leave this control green.

---

### 5. A broken `CC_MODAL_ANCHOR_BIN` override is skipped, and the skip gives the wrong reason

**What:** When the override variable is set but points at a non-existent file, `claude_binary` returns 1. The test then skips with a message saying no binary was found under `$HOME/.claude-*/`, a location that was never searched.

**Where:** lines 222–223 and 249
```
    [ -f "$CC_MODAL_ANCHOR_BIN" ] && { printf '%s' "$CC_MODAL_ANCHOR_BIN"; return 0; }
    return 1
```
```
  BIN="$(claude_binary)" || skip "no claude binary under \$HOME/.claude-*/ — the anchor cannot run, and that is a NON-VERDICT, not a pass"
```

**Why it is wrong:** Take a box that pins a binary via the override and has a typo in the path. The drift check is dropped as a skip, not a failure, and the skip message points the operator at the `$HOME/.claude-*` glob instead of the misconfigured override. The installed tracks are never consulted.
