Five defects found.

**1. The M4 "checkout behind" fixture builds a checkout that is ahead of trunk, not behind it.**

Where, lines 235-237:
```
  ( cd "$w"; git rm -q docs/activation/pending-activation/landed-activate.sh; git commit -q -m drop
    git reset -q --hard HEAD~1; git rm -q --cached docs/activation/pending-activation/landed-activate.sh
    rm -f docs/activation/pending-activation/landed-activate.sh; git commit -q -m "checkout behind" ) >/dev/null 2>&1
```
Why: after mkmirror, local main and origin/main are the same base commit containing the file. The rm, commit, reset sequence on lines 235-236 restores base exactly and is a no-op, which makes this fixture identical to the kill-switch fixture on lines 270-271. The final commit deletes the file on local main, leaving local one commit ahead of origin/main with the file still reachable from HEAD~1. The deploy-lag shape described on lines 215-216 and 234 is the opposite: origin/main gained the file in a commit the checkout has not received, so the file is in no commit reachable from local HEAD. An adjudicator that asks whether the path ever appears in local history answers "on trunk" here and "never committed" in production. It passes this test and the positive control on line 247 while still producing the F8 misreport the test exists to prevent.

**2. Two M5 tests assert only the absence of a token and pass when the hook crashes.**

Where, lines 306-307:
```
  CC_ACTIVATION_DIR="$Q" CC_ACTIVATION_LAUNCHCTL_BIN="$(lcstub 'com.chrisren.mailbox-gc' '')" run "$H"
  ! printf '%s' "$output" | grep -q 'CLAIMED-DONE BUT INERT' || false
```
and lines 325-327:
```
  ! printf '%s' "$output" | grep -q 'CLAIMED-DONE BUT INERT' || false
```
Why: neither test checks `$status` or asserts anything positive. `run` captures stderr and never fails by itself, so if the stub cannot execute, the parser dies on a non-empty `list` output, or the scope=claude branch errors, the output is an error message or empty, the token is absent, and the test passes. Line 303 is the only test that feeds a loaded label into the parser and line 322 is the only test of the scope kill switch. A crash in exactly the path each test covers is reported as success.

**3. The LIVE-ONLY assertions do not exclude the UNCONFIRMED verdict.**

Where, line 95 and line 253:
```
  printf '%s' "$output" | grep -q 'LIVE-ONLY'
```
Why: line 258 establishes that a plain directory under BATS_TEST_TMPDIR used as the mirror yields UNCONFIRMED. Line 90 builds the mirror for test 89 the same way. For both tests to pass, the hook's UNCONFIRMED rendering must also contain "LIVE-ONLY", so the grep on line 95 is satisfied by the could-not-check path rather than by the "never committed" adjudication the title claims. Test 247 is the stated positive control for trunk adjudication, yet it only excludes UNDEPLOYED-MIRROR on line 255. An adjudicator that maps "path missing on trunk" and "trunk unreadable" to the same non-zero git result and reports UNCONFIRMED passes both 232 and 247. That is the I7 failure mode described on lines 259-261.

**4. Two axis-2 fixtures are not .done-marked, so axis 1 satisfies their filename assertions.**

Where, line 91 and line 109:
```
  stage "12-only-live-activate.sh"
```
```
  printf '#!/bin/bash\n# LIVE\n' > "$Q/07-drift-activate.sh"
```
Why: line 84 states every fixture in the section is .done-marked so findings are attributable to parity alone. A fresh un-done file is named under FRESH by axis 1, as test 41 proves. The name greps on lines 94 and 112 therefore pass even if the LIVE-ONLY or CONTENT-DRIFT row names a different file or nothing, because the token greps on lines 95 and 113 are independent checks, unlike the combined pattern used on line 77.

**5. mkmirror cannot report failure, so the M4 tests run on an unverified fixture.**

Where, lines 228-229:
```
    git add -A; git commit -q -m base; git push -q -u origin main ) >/dev/null 2>&1
  printf '%s' "$w"
```
Why: the function is invoked through command substitution on lines 233, 250 and 269. Bash does not propagate errexit into `$(...)` unless inherit_errexit is set, and this file does not set it. Both git redirections on lines 224 and 228 discard stderr, and the final printf returns 0, so the substitution succeeds whatever git did. If commit or push fails, `$w` is a clone with an untracked file and no origin/main. Test 232 then fails on an assertion with no hint that the fixture is broken, and test 247 can pass through the UNCONFIRMED path from defect 3 without exercising adjudication at all.
