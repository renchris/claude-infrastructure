## 1. Fixture subshells run destructive git commands after an unchecked `cd`

**What** — The M4 fixtures `cd` into the mirror checkout with no check that it worked, then run `git commit`, `git reset --hard` and `rm -f` in whatever directory they are actually in.

**Where**
- 235: `( cd "$w"; git rm -q docs/activation/pending-activation/landed-activate.sh; git commit -q -m drop`
- 236: `git reset -q --hard HEAD~1; git rm -q --cached docs/activation/pending-activation/landed-activate.sh`
- 237: `rm -f docs/activation/pending-activation/landed-activate.sh; git commit -q -m "checkout behind" ) >/dev/null 2>&1`
- 270: `( cd "$w"; git rm -q --cached docs/activation/pending-activation/landed-activate.sh`
- 271: `rm -f docs/activation/pending-activation/landed-activate.sh; git commit -q -m "checkout behind" ) >/dev/null 2>&1`

**Why it is wrong** — `mkmirror` prints `$w` even if `git clone` (line 224) failed, so `$w` may not exist. Then `cd` fails, `;` lets everything else run in bats' cwd, typically the repo being tested, and all output is sent to `/dev/null`. In that case:
- `git commit` commits whatever the user has staged under the message "drop".
- `git reset -q --hard HEAD~1` discards that commit, or the branch's real latest commit, plus all uncommitted work.

Line 225 does guard its `cd` with `|| exit 1`, so this was known to be needed. In the intended case the `reset --hard` only undoes the commit made on the previous line.

## 2. Axis-2 tests name-check a fixture that axis 1 also names

**What** — The LIVE-ONLY and CONTENT-DRIFT fixtures are not `.done`-marked, so axis 1 lists them as FRESH and the "named" assertions pass without axis 2 naming anything.

**Where**
- 91: `stage "12-only-live-activate.sh"`
- 94: `printf '%s' "$output" | grep -q '12-only-live-activate.sh'`
- 109: `printf '#!/bin/bash\n# LIVE\n' > "$Q/07-drift-activate.sh"`
- 112: `printf '%s' "$output" | grep -q '07-drift-activate.sh'`
- Contradicted by 84: ``# Fixtures are `.done`-MARKED throughout, so axis 1 stays silent and every finding below is``
- Also unmarked: 134 `stage "x-activate.sh"` and 155 `stage "only-live.sh"`.

**Why it is wrong** — Since M3, a fresh un-run entry is named under FRESH (lines 47-51, 184-192). So lines 94 and 112 succeed on axis-1 output alone. If axis 2 printed `LIVE-ONLY` or `CONTENT-DRIFT` without the file name, or with the wrong one, both tests still pass. Comment lines 84-87 state exactly this isolation rule.

## 3. M5 control and kill-switch tests assert only absence

**What** — Both tests check only that `CLAIMED-DONE BUT INERT` is absent, with no exit-status check and no positive assertion, so they pass when the hook prints nothing because it failed.

**Where**
- 307: `! printf '%s' "$output" | grep -q 'CLAIMED-DONE BUT INERT' || false`
- 327: `! printf '%s' "$output" | grep -q 'CLAIMED-DONE BUT INERT' || false`

**Why it is wrong** — If the hook is missing or not executable, crashes in the axis-3 code, or the axis is dead, `$output` lacks the string and both tests pass.
- "The axis can go quiet" (line 303) cannot be told apart from "the axis is dead".
- "Restores the com.claude-only pattern" (line 322) is never shown, because no com.claude label is asserted to still be flagged.
- The M3 control and the in-parity control (lines 129-130, 200-201) do check status and empty output; M4's controls assert positive rows.

## 4. `mkmirror` hides every git failure and always reports success

**What** — The fixture builder discards all git output and exit codes and always prints the checkout path, so M4 tests run on a fixture never verified to hold the committed file or an `origin/main`.

**Where**
- 224: `git init -q --bare "$o"; git clone -q "$o" "$w" 2>/dev/null`
- 228: `git add -A; git commit -q -m base; git push -q -u origin main ) >/dev/null 2>&1`
- 229: `printf '%s' "$w"`

**Why it is wrong** — If the clone, commit or push fails (for example under commit-signing or hook config), the function still returns 0 and the test proceeds. The M4 positive control (line 253) is meant to prove the adjudicator can still say "absent from trunk", but it asserts only `printf '%s' "$output" | grep -q 'LIVE-ONLY'`. Lines 95 and 265 expect `LIVE-ONLY` and `UNCONFIRMED` respectively for the same fixture shape, a live file absent from a plain-directory mirror. So on the tests' own evidence, `LIVE-ONLY` is also present when trunk could not be read. A broken fixture therefore passes the control, and the kill-switch test (lines 275-276) likewise.

## 5. M3 kill-switch test does not check the "exactly" it claims

**What** — The test claims the >24h filter is restored "exactly" but never asserts that the stale entry is still reported.

**Where**
- 208: `printf '%s' "$output" | grep -q 'staged >24h and NOT run'`
- 209: `! printf '%s' "$output" | grep -q 'b-new-activate.sh' || false`

**Why it is wrong** — With `CC_ACTIVATION_AGE_FILTER=on`, if the old-format header prints but `a-old-activate.sh` is missing from the list (or the list is empty), both assertions still pass. The entry that the filter is supposed to keep is never checked, and neither is the exit status.

## 6. `stage()` reports success when `touch` fails

**What** — The helper returns 0 unconditionally, so a failed `touch -t` leaves a fixture that was meant to be stale silently fresh.

**Where** — 17: `stage() { printf '#!/bin/bash\n' > "$Q/$1"; [ -n "${2:-}" ] && touch -t "$2" "$Q/$1"; return 0; }`

**Why it is wrong** — If `touch -t "$2"` fails, the file keeps mtime=now and no error is raised. The tests that expect silence for `.done`-marked stale entries (lines 55-61, `done-c.sh` at 74, and 195-202) still pass, but they never exercised "stale but marked done".
