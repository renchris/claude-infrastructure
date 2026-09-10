Reviewing the bats file text only, no tools needed. Here is what I found.

## Defects

**1. The M4 positive control and kill-switch tests cannot distinguish a real "LIVE-ONLY" verdict from an "UNCONFIRMED" one, so they pass even when trunk adjudication never ran.**

Where:
- Line 253: `printf '%s' "$output" | grep -q 'LIVE-ONLY'`
- Line 255: `! printf '%s' "$output" | grep -q 'UNDEPLOYED-MIRROR' || false`
- Line 275: `printf '%s' "$output" | grep -q 'LIVE-ONLY'`
- Line 276: `! printf '%s' "$output" | grep -q 'UNDEPLOYED-MIRROR' || false`

Why it is wrong: the file itself shows that a non-checkout mirror emits both the `LIVE-ONLY` token (line 95, mirror is a plain directory) and `UNCONFIRMED` (line 265, same shape). So the hook prints `LIVE-ONLY` on the unconfirmed path too. Neither test asserts the absence of `UNCONFIRMED`. If `mkmirror` produced a broken clone (see defect 4), or if the adjudicator regressed to always answering "cannot read trunk", both tests still pass. That is exactly the vacuous outcome the comment at lines 248-249 says the positive control exists to prevent, and it means the kill-switch test does not prove the switch restored the working-tree verdict rather than an unconfirmed one.

**2. The LIVE-ONLY fixture is not `.done`-marked, so the name assertion is satisfied by axis 1 rather than the parity axis the test claims to isolate.**

Where:
- Line 91: `stage "12-only-live-activate.sh"`
- Line 94: `printf '%s' "$output" | grep -q '12-only-live-activate.sh'`

Why it is wrong: the section header at lines 84-85 states fixtures are `.done`-marked throughout so every finding is attributable to axis 2. This fixture has no `.done` marker, so axis 1 names it under `FRESH` regardless of parity. Line 94 therefore passes even if axis 2 emitted a `LIVE-ONLY` heading with no filename, or named a different file. Nothing ties the filename and the `LIVE-ONLY` token to the same row.

**3. The negated LIVE-ONLY check in the M4 deploy-lag test is pinned to an exact prose string and passes vacuously on any other wording.**

Where:
- Line 242: `! printf '%s' "$output" | grep -q "LIVE-ONLY — never committed, one .rm. from unrecoverable: landed-activate.sh" || false`

Why it is wrong: the sibling kill-switch test at line 276 negates the bare token, but this one negates a full sentence including punctuation. If the hook emits `LIVE-ONLY` for the file with any different phrasing, or emits both an `UNDEPLOYED-MIRROR` row and a `LIVE-ONLY` row, the test passes while the file is misclassified in the damaging direction the M4 comment describes.

**4. `mkmirror` swallows every git error and always returns a path, so a half-built mirror is handed to the tests as if it were valid.**

Where:
- Line 224: `git init -q --bare "$o"; git clone -q "$o" "$w" 2>/dev/null`
- Line 228: `git add -A; git commit -q -m base; git push -q -u origin main ) >/dev/null 2>&1`
- Line 229: `printf '%s' "$w"`

Why it is wrong: the subshell has no error handling beyond the `cd`, and stdout and stderr are discarded. If the commit or push fails, for example because the clone of an empty bare repo lands on a different default branch than `main`, there is no `origin/main` to adjudicate against. The M4 deploy-lag test fails loudly, but the positive control and kill-switch tests still pass through the `UNCONFIRMED` path described in defect 1.

**5. The symlink test's negative assertion cannot fail for the defect it claims to guard against.**

Where:
- Line 145: `ln -s "$H" "$BATS_TEST_TMPDIR/linked.sh"`
- Line 150: `! printf '%s' "$output" | grep -q '\.claude/docs/activation'`

Why it is wrong: the comment at lines 142-144 models the failure as an underdereferenced `BASH_SOURCE` yielding `REPO=~/.claude`. The symlink here lives in `$BATS_TEST_TMPDIR`, so a naive resolution would yield a path under the temp dir, never one containing `.claude/docs/activation`. The negation is satisfied by construction. Only line 149 carries weight, and it does not exclude the case where the hook fell back to the shared `FALLBACK_REPO` and that checkout happens to be this one.

**6. `stage()` unconditionally returns 0, so a fixture that failed to be back-dated is silently used as if it were stale.**

Where:
- Line 17: `stage() { printf '#!/bin/bash\n' > "$Q/$1"; [ -n "${2:-}" ] && touch -t "$2" "$Q/$1"; return 0; }`

Why it is wrong: if `touch -t` rejects `$OLD`, the file keeps its current mtime and is fresh. The tests titled stale at lines 26-32 and 34-39 never assert `ROTTING`, and after the M3 change fresh entries are also named, so both pass on a fresh fixture. The failure is only caught indirectly by the mixed-queue assertion at line 77.

## Notes

The `!`-negations without `|| false` at lines 23, 80, and 150 are each the last statement of their test, so the function return status carries them. They are fragile but not defects as written.
