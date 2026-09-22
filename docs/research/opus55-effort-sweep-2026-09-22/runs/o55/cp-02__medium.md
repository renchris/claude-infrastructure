# Review of `tests/activation-watch.bats`

I found four defects. Three are assertions that can pass for the wrong reason. The fourth is a fixture that breaks the isolation rule the file states for itself.

---

### 1. LIVE-ONLY test: the filename assertion can be satisfied by axis 1

**What:** The LIVE-ONLY fixture has no `.done` marker, so axis 1 also names the file. The filename grep therefore does not show that the parity axis reported it.

**Where:** lines 87 and 90
```
  stage "12-only-live-activate.sh"
```
```
  printf '%s' "$output" | grep -q '12-only-live-activate.sh'
```

**Why it is wrong:**
- The axis-2 header (lines 78–81) says fixtures are "`.done`-MARKED throughout, so axis 1 stays silent… freshness no longer buys silence".
- This fixture is unmarked and fresh, so axis 1 lists `12-only-live-activate.sh` under FRESH.
- Suppose the parity axis emitted a `LIVE-ONLY` header but omitted or misnamed the file. The name grep would still pass on the axis-1 line, and the separate `LIVE-ONLY` grep does not tie the label to this file.
- So "named (the unrecoverable class)" is not actually proven.

---

### 2. CONTENT-DRIFT test: same non-isolated fixture, and no exit-status check

**What:** The drift fixture is also unmarked, so the filename match can come from axis 1. The test also never checks `$status`.

**Where:** lines 104 and 107
```
  printf '#!/bin/bash\n# LIVE\n' > "$Q/07-drift-activate.sh"
```
```
  printf '%s' "$output" | grep -q '07-drift-activate.sh'
```

**Why it is wrong:**
- `07-drift-activate.sh` is fresh and has no `.done`, so axis 1 names it under FRESH.
- The filename assertion therefore holds even if the drift row names nothing, or names the wrong file.
- Because there is no `[ "$status" -eq 0 ]`, the test also passes if the hook exits non-zero after printing a partial emit containing `CONTENT-DRIFT`. Such an emit would break the SessionStart contract.

---

### 3. M5 POSITIVE CONTROL passes if the hook crashes or prints nothing

**What:** The "the axis can go quiet" control asserts only that a string is absent. It has no status check and no positive evidence that axis 3 ran.

**Where:** line 262
```
  ! printf '%s' "$output" | grep -q 'CLAIMED-DONE BUT INERT' || false
```

**Why it is wrong:**
- If the hook exits non-zero, errors on `CC_ACTIVATION_LAUNCHCTL_BIN`, or skips axis 3 entirely, `$output` has no `CLAIMED-DONE BUT INERT` and the test passes.
- The file's own principle (line 205: "The negative is not data without this") is that a quiet result only means something if the path demonstrably ran.
- Here a broken hook and a correct one look the same.

---

### 4. M5 kill-switch test passes if the hook crashes or prints nothing

**What:** Like #3, the kill-switch test has only a negative assertion, no status check, and nothing showing the hook ran with the switch applied.

**Where:** line 283
```
  ! printf '%s' "$output" | grep -q 'CLAIMED-DONE BUT INERT' || false
```

**Why it is wrong:**
- With `CC_ACTIVATION_INERT_SCOPE=claude`, any failure produces no `CLAIMED-DONE BUT INERT` line, and the test goes green. That includes a crash, a non-zero exit, or axis 3 being skipped.
- So the test does not prove that "restores the com.claude-only pattern". It only proves that the output lacks one string.
- Compare the other two kill switches: M3 (line 191) and M4 (line 244) each pair their negative with a positive grep that shows the restored behaviour actually happened.
