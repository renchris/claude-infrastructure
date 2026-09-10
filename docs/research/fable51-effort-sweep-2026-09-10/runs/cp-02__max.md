Six defects found, all in how the tests assert or build their fixtures. The negation idioms, `stage` helper, and launchctl stub are sound.

**1. The M4 positive control cannot tell "absent from trunk" apart from UNCONFIRMED.**

Where, lines 253 and 255:
```
  printf '%s' "$output" | grep -q 'LIVE-ONLY'
  ! printf '%s' "$output" | grep -q 'UNDEPLOYED-MIRROR' || false
```
Why: The LIVE-ONLY test at lines 89-96 and the UNCONFIRMED test at lines 258-266 use the identical mirror shape, a plain directory with the live file absent, and demand 'LIVE-ONLY' and 'UNCONFIRMED' respectively. For both to pass, an UNCONFIRMED row must itself contain 'LIVE-ONLY'. So the control at 247 passes when the adjudicator returns UNCONFIRMED instead of "absent from trunk". The only text that separates the two verdicts, the "never committed, one `rm` from unrecoverable" message, is asserted solely as a negative at line 242, so nothing in the file proves it is ever emitted. An adjudicator that answers UNCONFIRMED for every file missing from trunk passes the tests at 232, 247 and 258 while silencing exactly the alarm the control exists to protect.

**2. `mkmirror` reports success no matter what git did.**

Where, lines 228, 229 and 250:
```
    git add -A; git commit -q -m base; git push -q -u origin main ) >/dev/null 2>&1
  printf '%s' "$w"
  w="$(mkmirror m4b)"
```
Why: Bash disables errexit inside `$(...)`, every git message is discarded, and the function ends with a `printf` that exits 0, so the assignment always succeeds. If the push fails, the checkout has no `origin/main` and the adjudicator has no trunk to read. That produces the UNCONFIRMED shape, and by defect 1 the positive control at 247 still passes. In the tests at 232 and 268 a half-built mirror does fail, but as a missing verdict rather than as a fixture error.

**3. Two axis-2 fixtures are not `.done`-marked, so axis 1 satisfies their filename assertions.**

Where, lines 84, 91, 94, 109 and 112:
```
# Fixtures are `.done`-MARKED throughout, so axis 1 stays silent and every finding below is
  stage "12-only-live-activate.sh"
  printf '%s' "$output" | grep -q '12-only-live-activate.sh'
  printf '#!/bin/bash\n# LIVE\n' > "$Q/07-drift-activate.sh"
  printf '%s' "$output" | grep -q '07-drift-activate.sh'
```
Why: Under M3 every un-run file is named under FRESH in the queue section. The filename greps at 94 and 112 therefore pass regardless of what the parity section prints. A LIVE-ONLY or CONTENT-DRIFT row that emits the class header with no filename, or with the wrong filename, passes both tests. The section comment states the isolation these fixtures were supposed to have.

**4. The M3 kill-switch test never checks that the stale entry is still named.**

Where, lines 208 and 209:
```
  printf '%s' "$output" | grep -q 'staged >24h and NOT run'
  ! printf '%s' "$output" | grep -q 'b-new-activate.sh' || false
```
Why: This is the only test that sets `CC_ACTIVATION_AGE_FILTER=on`. A restored filter that hides both entries but still prints the header, or counts the stale entry without listing it, passes a test titled "restores the >24h filter exactly".

**5. The stale test asserts nothing that depends on staleness.**

Where, lines 30 and 31:
```
  printf '%s' "$output" | grep -q 'p0-14-activate.sh'
  printf '%s' "$output" | grep -q 'ACTIVATION QUEUE'
```
Why: After M3, a fresh un-run file produces the same two strings. An age computation that classifies everything as FRESH passes this test, which claims >24h coverage in its title. Only the mixed test at 69 and the M3 test at 184 actually pin the ROTTING partition.

**6. The M4 deploy-lag fixture builds a checkout that is ahead of trunk, not behind it.**

Where, lines 234-237:
```
  # the checkout is BEHIND trunk for this path — the deploy-lag shape
  ( cd "$w"; git rm -q docs/activation/pending-activation/landed-activate.sh; git commit -q -m drop
    git reset -q --hard HEAD~1; git rm -q --cached docs/activation/pending-activation/landed-activate.sh
    rm -f docs/activation/pending-activation/landed-activate.sh; git commit -q -m "checkout behind" ) >/dev/null 2>&1
```
Why: The `rm`, `commit drop`, and `reset --hard HEAD~1` cancel out, and the final commit adds a deletion on top of base. The result is `main` one commit ahead of `origin/main`, the opposite of a checkout that trails trunk. The state the M4 section describes, trunk holding a commit the checkout lacks, is never constructed. If the hook's UNDEPLOYED-MIRROR verdict considers whether the checkout trails trunk, this fixture reads as "ahead" and the test fails for a fixture reason. If the hook only inspects the tree of `origin/main`, the test passes without exercising the deploy-lag case it is named for.
