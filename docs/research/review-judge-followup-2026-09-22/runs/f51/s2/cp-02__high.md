Six defects found. The most serious are two axis-2 tests whose filename assertions are satisfied by axis 1, and an M4 fixture that does not model the trunk-versus-checkout case it claims to prove.

**1. What:** The LIVE-ONLY and CONTENT-DRIFT tests stage fixtures without a `.done` marker, so axis 1 names the file and the filename assertion passes regardless of what axis 2 did.
**Where:** Lines 91 and 94, and lines 109 and 112.
```
  stage "12-only-live-activate.sh"
  printf '%s' "$output" | grep -q '12-only-live-activate.sh'
  printf '#!/bin/bash\n# LIVE\n' > "$Q/07-drift-activate.sh"
  printf '%s' "$output" | grep -q '07-drift-activate.sh'
```
**Why it is wrong:** The section header at lines 84 to 87 states that every axis-2 fixture is `.done`-marked so axis 1 stays silent and each finding is attributable to parity alone. These two tests break that invariant. A fresh un-done file is named under the FRESH partition by axis 1, so the name check passes even if axis 2 never classified the file at all. The remaining check only requires the class token to appear somewhere in the output, not next to the filename, so a parity axis that prints the token in a header or legend without naming the file passes both tests. Line 134 also stages without `.done`, though that test only checks the DID NOT RUN string, so the noise is harmless there.

**2. What:** The M4 fixtures leave the "landed" file in the local checkout's own commit history, so an adjudicator that never consults trunk still passes.
**Where:** Lines 235 to 237 and lines 270 to 271.
```
  ( cd "$w"; git rm -q docs/activation/pending-activation/landed-activate.sh; git commit -q -m drop
    git reset -q --hard HEAD~1; git rm -q --cached docs/activation/pending-activation/landed-activate.sh
    rm -f docs/activation/pending-activation/landed-activate.sh; git commit -q -m "checkout behind" ) >/dev/null 2>&1
```
**Why it is wrong:** The helper at line 222 commits the file in `base` and pushes, and this block then deletes it in a new local commit. The resulting checkout is ahead of trunk with a deletion, not behind it. Lines 235 and 236 are a round trip that changes nothing. The deploy-lag class the comment describes is a file that landed on trunk after the local HEAD and has never been in local history. In this fixture the file is in local history, so an implementation that answers "on trunk" by checking `git log -- path` locally, or any local ref, produces UNDEPLOYED-MIRROR here and LIVE-ONLY in the positive control at line 247, passing both tests without reading `origin/main`. The kill-switch test at line 268 shares the same shape.

**3. What:** The symlink test's negative assertion cannot fire for this fixture, and the positive assertion cannot distinguish a successful dereference from the fallback when the test checkout is the fallback checkout.
**Where:** Lines 145, 149, and 150.
```
  ln -s "$H" "$BATS_TEST_TMPDIR/linked.sh"
  printf '%s' "$output" | grep -q "$REPO/docs/activation/pending-activation"
  ! printf '%s' "$output" | grep -q '\.claude/docs/activation'
```
**Why it is wrong:** The comment says an undereferenced BASH_SOURCE yields a repo of `~/.claude`. Here the symlink lives under the bats temp dir, so an undereferenced source resolves to the temp dir, which never contains `.claude/docs/activation`. Line 150 therefore passes whether or not the dereference happened. Per the comment, a repo with no activation docs falls through the git gate to the shared fallback checkout. If the suite is run from that shared checkout, the fallback path equals the value derived at line 7 and line 149 passes on an undereferenced source too. Under that condition the test is vacuous for the exact regression it names.

**4. What:** The M3 kill-switch test never asserts that the stale entry survives the restored filter.
**Where:** Lines 208 and 209.
```
  printf '%s' "$output" | grep -q 'staged >24h and NOT run'
  ! printf '%s' "$output" | grep -q 'b-new-activate.sh' || false
```
**Why it is wrong:** The title claims the filter is restored "exactly," but the only positive check is a header string. A filter that emits the header with the whole-queue count and names nothing, or one that drops the stale entry along with the fresh one while still printing the header, passes. The file staged at line 205 is never grepped for.

**5. What:** The M4 negative assertion excludes one exact wording rather than the LIVE-ONLY class token, so a file reported under both classes passes.
**Where:** Line 242.
```
  ! printf '%s' "$output" | grep -q "LIVE-ONLY — never committed, one .rm. from unrecoverable: landed-activate.sh" || false
```
**Why it is wrong:** Elsewhere the suite treats the bare token as the class marker, as at lines 253 and 275. If the tool's LIVE-ONLY line for this file uses any other wording, such as a count, a different dash, or a different suffix, the negative never matches. An adjudicator that emits UNDEPLOYED-MIRROR and also still emits LIVE-ONLY for the same file satisfies lines 240, 241, and 244 and slips past 242.

**6. What:** The stage helper masks a failed timestamp change, and the "stale" test no longer asserts staleness, so a broken OLD value goes unnoticed in that test.
**Where:** Line 17, and lines 27 to 31.
```
stage() { printf '#!/bin/bash\n' > "$Q/$1"; [ -n "${2:-}" ] && touch -t "$2" "$Q/$1"; return 0; }
```
**Why it is wrong:** If the touch fails, the fixture is created fresh and the helper still returns success. Since M3 names fresh entries too, the test titled "stale (>24h) un-run activation" only greps for the filename and the queue banner, both of which a fresh file also produces. The test passes on the wrong partition. The only place a broken OLD is caught is the partition-count check at line 77, so the trigger is narrow, but this test's title no longer describes what it verifies.
