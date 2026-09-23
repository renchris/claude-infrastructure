## Defects

### 1. The axis-2 section's stated isolation invariant is not applied to three of its own tests, so the filename assertions are satisfied by axis-1 output

**Where** — lines 84, 91, 94, 109, 112, 134:
```
# Fixtures are `.done`-MARKED throughout, so axis 1 stays silent and every finding below is
```
```
  stage "12-only-live-activate.sh"
```
```
  printf '%s' "$output" | grep -q '12-only-live-activate.sh'
```
```
  printf '#!/bin/bash\n# LIVE\n' > "$Q/07-drift-activate.sh"
```
```
  printf '%s' "$output" | grep -q '07-drift-activate.sh'
```
```
  stage "x-activate.sh"
```

**Why it is wrong** — `12-only-live-activate.sh`, `07-drift-activate.sh` and `x-activate.sh` are staged with no `.done` marker. After M3, axis 1 partitions instead of filtering (proved by the test at lines 41–53: a fresh un-run script *is* named), so each of these fixtures is named by axis 1 in the FRESH partition. In the LIVE-ONLY and CONTENT-DRIFT tests the name-grep (94, 112) therefore matches axis-1 text, and the class-grep (95, 113) matches the class label anywhere in the emit: a parity axis that printed `LIVE-ONLY: (none)` or attributed the drift to the wrong filename passes both assertions unchanged. This is precisely the failure mode the section comment at 84–87 says has been ruled out.

### 2. `mkmirror` cannot report failure, and the two fixture subshells that consume it `cd` without a guard, so destructive git commands can run in the repository bats was launched from

**Where** — lines 229, 235–237, 270–271 (contrast line 225):
```
  printf '%s' "$w"
```
```
  ( cd "$w"; git rm -q docs/activation/pending-activation/landed-activate.sh; git commit -q -m drop
    git reset -q --hard HEAD~1; git rm -q --cached docs/activation/pending-activation/landed-activate.sh
    rm -f docs/activation/pending-activation/landed-activate.sh; git commit -q -m "checkout behind" ) >/dev/null 2>&1
```
```
  ( cd "$w"; git rm -q --cached docs/activation/pending-activation/landed-activate.sh
    rm -f docs/activation/pending-activation/landed-activate.sh; git commit -q -m "checkout behind" ) >/dev/null 2>&1
```
```
  ( cd "$w" || exit 1; git config user.email t@e.com; git config user.name t; git checkout -q -b main
```

**Why it is wrong** — `mkmirror`'s entire setup subshell is `>/dev/null 2>&1` and the function's exit status is that of `printf`, so if `git init`/`git clone`/`git commit`/`git push` fails, `mkmirror` still prints `$w` and returns 0. The caller then runs `cd "$w"` with no `|| exit 1` (unlike line 225, where the same author added the guard); when `$w` does not exist, `cd` fails and the remaining commands execute in the test's inherited cwd — normally the checkout under test, which does contain `docs/activation/pending-activation` (line 149). `git reset -q --hard HEAD~1` then always succeeds there, discarding the developer's uncommitted work and rewinding HEAD, and `git commit -q -m "checkout behind"` commits whatever happened to be staged — all silently, since stderr is discarded.

### 3. The M5 "POSITIVE CONTROL" asserts only an absence, with nothing proving the hook or the axis ran

**Where** — lines 306–307:
```
  CC_ACTIVATION_DIR="$Q" CC_ACTIVATION_LAUNCHCTL_BIN="$(lcstub 'com.chrisren.mailbox-gc' '')" run "$H"
  ! printf '%s' "$output" | grep -q 'CLAIMED-DONE BUT INERT' || false
```

**Why it is wrong** — there is no `[ "$status" -eq 0 ]` and no positive assertion. If `lcstub` fails to write its stub, if `$H` aborts before axis 3, or if axis 3 never emits a row for any input (the exact starvation defect a positive control exists to exclude), `$output` is empty and the single assertion passes. A control that passes when the controlled axis did not execute establishes nothing about the axis "going quiet" for the right reason. Compare the M3 positive control (lines 199–201), which does check both status and emptiness.

### 4. The M5 kill-switch test cannot distinguish "scope narrowed to `com.claude`" from "axis 3 disabled entirely"

**Where** — lines 325–327:
```
  CC_ACTIVATION_DIR="$Q" CC_ACTIVATION_INERT_SCOPE=claude \
    CC_ACTIVATION_LAUNCHCTL_BIN="$(lcstub '' '')" run "$H"
  ! printf '%s' "$output" | grep -q 'CLAIMED-DONE BUT INERT' || false
```

**Why it is wrong** — the only fixture in the queue names a `com.chrisren` label, and the only assertion is that its row disappears. A kill switch that suppressed the whole inert-label axis, or that never matched any label at all, produces identical output and passes. The claim in the test name ("restores the com.claude-only pattern") requires a `com.claude` label still producing a row under the same switch; nothing here checks that.

### 5. The M4 fixture does not build the "checkout behind trunk" shape it claims — the path is still present in the local branch's own history

**Where** — lines 234–237:
```
  # the checkout is BEHIND trunk for this path — the deploy-lag shape
  ( cd "$w"; git rm -q docs/activation/pending-activation/landed-activate.sh; git commit -q -m drop
    git reset -q --hard HEAD~1; git rm -q --cached docs/activation/pending-activation/landed-activate.sh
    rm -f docs/activation/pending-activation/landed-activate.sh; git commit -q -m "checkout behind" ) >/dev/null 2>&1
```

**Why it is wrong** — `git commit -m drop` is undone by `git reset --hard HEAD~1`, so those two commands are no-ops; the net state is the `base` commit (which contains `landed-activate.sh`) plus a *new local commit deleting it*. The checkout is therefore ahead of trunk with a deletion, not behind it, and the file remains reachable in the local branch's history. An adjudicator that answers "is this path anywhere in this repo's history" (`git log -- <path>`, `git rev-list --all`) — rather than consulting the trunk ref — returns "on trunk" here and passes, while failing the real deploy-lag case where the path exists only on `origin/main` and never in local history.

### 6. The axis-2 LIVE-ONLY test asserts the "never committed" class from a mirror containing no repository, which the file's own M4 case says cannot be adjudicated

**Where** — lines 90, 95 versus 264–265:
```
  M="$BATS_TEST_TMPDIR/mirror"; mkdir -p "$M"
```
```
  printf '%s' "$output" | grep -q 'LIVE-ONLY'
```
```
  CC_ACTIVATION_DIR="$Q" CC_ACTIVATION_MIRROR_DIR="$BATS_TEST_TMPDIR/bare-mirror" run "$H"
  printf '%s' "$output" | grep -q 'UNCONFIRMED'
```

**Why it is wrong** — both fixtures are the same shape: an empty non-checkout directory as the mirror plus a live-only file. The M4 test declares that shape yields UNCONFIRMED because there is no trunk ref. The axis-2 test nonetheless claims the file is "never committed… the unrecoverable class" on the strength of a substring match. Feed it a file that *is* committed on trunk and the test passes identically — it only ever proves "name absent from a directory", which is exactly the inference M4 was added to forbid.

### 7. The M4 guard against the "never committed" verdict is pinned to one exact sentence including the filename

**Where** — line 242:
```
  ! printf '%s' "$output" | grep -q "LIVE-ONLY — never committed, one .rm. from unrecoverable: landed-activate.sh" || false
```

**Why it is wrong** — the pattern requires the em-dash wording, the exact phrase, and `landed-activate.sh` immediately after `unrecoverable: `. If the tool emits the same wrong verdict with a count prefix, a different separator, or with `landed-activate.sh` listed second among several files, the grep does not match and the guard passes silently while the misreport it exists to catch is in the output. The corresponding guard in the positive control (line 255) is broad (`'UNDEPLOYED-MIRROR'`); this one is not.

### 8. The symlink test does not reproduce the mis-resolution it names, and compares a logical path against a dereferenced one

**Where** — lines 7, 145, 149–150:
```
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
```
```
  ln -s "$H" "$BATS_TEST_TMPDIR/linked.sh"
```
```
  printf '%s' "$output" | grep -q "$REPO/docs/activation/pending-activation"
  ! printf '%s' "$output" | grep -q '\.claude/docs/activation'
```

**Why it is wrong** — two things. (a) The link is created in `$BATS_TEST_TMPDIR`, not under `~/.claude`, so an underefed `BASH_SOURCE` resolves to the bats temp dir; the assertion at 150 cannot fail for the regression the test name and comment cite (only line 149 does real work). (b) `$REPO` is built with bash's *logical* `pwd`, while the behaviour under test is the hook dereferencing its own path. Whenever the checkout is reached through a symlinked component whose resolved form is not a suffix-extension of the logical one (e.g. `~/work` → `/Volumes/ext/work`), the hook prints the physical path, the substring grep at 149 misses, and the test fails even though the resolution was correct.
