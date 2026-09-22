I found two defects. Both come from the same inconsistency in the file.

### 1. LIVE-ONLY test's name assertion is satisfied by axis 1, not axis 2
- **What:** The fixture is staged fresh and not `.done`-marked, so axis 1 names the script under FRESH, and the name check passes regardless of axis 2.
- **Where:** line 87 `stage "12-only-live-activate.sh"` (asserted at line 90 `printf '%s' "$output" | grep -q '12-only-live-activate.sh'`)
- **Why it is wrong:** The axis-2 banner says fixtures are `.done`-marked "so … every finding below is attributable to the parity axis alone." Since M3, a fresh, un-done entry is always named under FRESH. So if the parity axis stopped naming the file, the name grep would still pass. Only the bare `LIVE-ONLY` grep remains. That grep does not tie the label to this file, and it could match other text, such as the M4 UNCONFIRMED LIVE-ONLY wording that applies because `$M` is a non-checkout mirror. The assertion passes for the wrong reason.

### 2. The "unresolvable mirror" and `--parity` fixtures also break the `.done` isolation
- **What:** These fixtures are also staged un-done, which breaks the isolation the section header promises.
- **Where:**
  - line 136 `stage "x-activate.sh"`
  - line 161 `stage "only-live.sh"`
- **Why it is wrong:**
  - **Line 136:** The SessionStart run emits axis-1 output (FRESH x-activate.sh) alongside any parity output. The result is attributed to axis 2 but not isolated from axis 1.
  - **Line 161:** The `grep -q 'only-live.sh'` would be satisfied by an axis-1 FRESH line if `--parity` output includes axis 1. The status checks carry the real signal there, but the name assertion does not prove what it claims.

No other defects I can point at with confidence. The remaining `!`-negated assertions are either the final command or guarded with `|| false`, so they are not silently skipped.
