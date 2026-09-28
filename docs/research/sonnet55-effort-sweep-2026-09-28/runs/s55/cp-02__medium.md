I found one clear defect and one weaker one.

**1.**
- **What:** The axis-2 tests that claim `.done`-marked fixtures leave their name assertions unmarked, so axis 1 can satisfy the name checks on its own.
- **Where:**
  - Line: `  stage "12-only-live-activate.sh"` (LIVE-ONLY test)
  - Line: `  printf '#!/bin/bash\n# LIVE\n' > "$Q/07-drift-activate.sh"` (CONTENT-DRIFT test, with no `.done` file created)
  - Line: `  printf '%s' "$output" | grep -q '12-only-live-activate.sh'`
  - Line: `  printf '%s' "$output" | grep -q '07-drift-activate.sh'`
- **Why it is wrong:** The section header says fixtures "are `.done`-MARKED throughout, so axis 1 stays silent and every finding below is attributable to the parity axis alone." Neither fixture is marked. Axis 1 therefore lists each script as a pending FRESH activation. If axis 2 dropped the filename from its LIVE-ONLY or CONTENT-DRIFT rows, the bare-filename `grep -q` would still pass because of the axis-1 listing. The separate `grep -q 'LIVE-ONLY'` and `grep -q 'CONTENT-DRIFT'` only prove the label appears somewhere. They do not prove the file is named under it.

**2. (weaker)**
- **What:** The M5 "positive control" asserts only that a string is absent, with no check on exit status or on any output.
- **Where:** Line: `  ! printf '%s' "$output" | grep -q 'CLAIMED-DONE BUT INERT' || false` (in "M5 POSITIVE CONTROL: a LOADED label yields NO row")
- **Why it is wrong:** If the hook crashes, exits nonzero, or never reaches axis 3, `$output` lacks the string and the test passes. It cannot tell "the label was seen as loaded and produced no row" from "the axis never ran". The M5 kill-switch test's final assertion, `! printf '%s' "$output" | grep -q 'CLAIMED-DONE BUT INERT' || false`, has the same weakness.
