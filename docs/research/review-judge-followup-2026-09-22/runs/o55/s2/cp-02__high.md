# Review: `tests/activation-watch.bats`

I found five defects. All are in the tests themselves: assertions that can pass without proving what the test name claims.

---

### 1. LIVE-ONLY and CONTENT-DRIFT fixtures are not `.done`-marked, so axis 1 names the file

**What:** The axis-2 section header says fixtures are `.done`-marked so every finding comes from the parity axis. These two tests stage un-marked scripts, so the "file is named" assertion is satisfied by axis 1's FRESH listing.

**Where:**
- Line 91: `  stage "12-only-live-activate.sh"`
- Line 94: `  printf '%s' "$output" | grep -q '12-only-live-activate.sh'`
- Line 109: `  printf '#!/bin/bash\n# LIVE\n' > "$Q/07-drift-activate.sh"`
- Line 112: `  printf '%s' "$output" | grep -q '07-drift-activate.sh'`

**Why it is wrong:** Since M3, axis 1 names every pending, un-`.done` script under FRESH (lines 41–52 and 184–192). Suppose axis 2 prints its `LIVE-ONLY` or `CONTENT-DRIFT` header but lists the wrong file, or no file. The filename grep still passes because axis 1 printed the name. So "→ named" is never shown for the parity axis, which is the isolation failure the header at lines 84–87 says it prevents.

---

### 2. The M4 negative assertion only matches one exact wording

**What:** The check that `landed-activate.sh` is *not* called LIVE-ONLY matches one full rendered sentence. It passes vacuously if the wording differs at all.

**Where:** Line 242: `  ! printf '%s' "$output" | grep -q "LIVE-ONLY — never committed, one .rm. from unrecoverable: landed-activate.sh" || false`

**Why it is wrong:** The negation holds whenever that exact string is missing. It would still pass if the tool wrongly reported the file as LIVE-ONLY with any other phrasing, for example:
- a different dash or separator,
- several names on the line (`...: a.sh landed-activate.sh`),
- the name on its own line.

The paired positive control (line 253, `grep -q 'LIVE-ONLY'`) never checks that this exact string is produced for a real live-only file. So nothing ties the negative to the tool's actual output format, and the misclassification it guards against can come back without the test failing.

---

### 3. The M5 kill-switch test only asserts an absence

**What:** The test claims `CC_ACTIVATION_INERT_SCOPE=claude` "restores the com.claude-only pattern". It only asserts that a com.chrisren label is *not* reported. There is no status check and no positive case.

**Where:** Line 327: `  ! printf '%s' "$output" | grep -q 'CLAIMED-DONE BUT INERT' || false`

**Why it is wrong:** The test passes in two situations where the switch is broken:
- **Axis 3 is switched off entirely.** Then com.claude labels are no longer detected either, but no com.claude fixture exists to catch that.
- **The hook exits non-zero or crashes.** `run` captures the error text, which does not contain `CLAIMED-DONE BUT INERT`, and `$status` is never checked.

In both cases the test reports "restored" without proving the com.claude pattern is still active.

---

### 4. The M5 positive control is also satisfied by a failed run

**What:** "A LOADED label yields NO row" is shown only by the absence of a string, with no `$status` check.

**Where:** Line 307: `  ! printf '%s' "$output" | grep -q 'CLAIMED-DONE BUT INERT' || false`

**Why it is wrong:** The test passes whenever the output lacks that string, including when the hook aborts. Examples: the stub launchctl output fails to parse, or the hook errors on the `print-disabled` call. So "the axis can go quiet" is not distinguished from "the axis crashed". The other quiet-path controls in this file (lines 120–121, 129–130, 200–201) do check `[ "$status" -eq 0 ]`; this one does not.

---

### 5. The "stale" test no longer tests staleness

**What:** After M3, the stale test's assertions are met by any pending entry, whatever its age.

**Where:**
- Line 30: `  printf '%s' "$output" | grep -q 'p0-14-activate.sh'`
- Line 31: `  printf '%s' "$output" | grep -q 'ACTIVATION QUEUE'`

**Why it is wrong:** Since M3, fresh entries are also named under the `ACTIVATION QUEUE` header. So the test passes even if:
- the >24h classification is broken and everything lands in FRESH, or
- the `$OLD` back-dating had no effect.

It never asserts `ROTTING`, so the "(>24h)" in its name is not tested here.
