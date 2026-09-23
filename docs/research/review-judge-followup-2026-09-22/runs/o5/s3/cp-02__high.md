## Review — `tests/activation-watch.bats`

I found eight defects. Line numbers are counted from `#!/usr/bin/env bats` as line 1.

---

### 1. Two tests assert contradictory verdicts for the same input class (plain-directory mirror + live-only file)

**What** — The axis-2 `LIVE-ONLY` test asserts the verdict `LIVE-ONLY` for a mirror that is a bare temp directory, while the M4/I7 test asserts that exactly that configuration must yield `UNCONFIRMED`; at most one of the two can be passing for the reason it states.

**Where** — lines 90–95 vs. lines 262–265:
```bash
  M="$BATS_TEST_TMPDIR/mirror"; mkdir -p "$M"
```
```bash
  printf '%s' "$output" | grep -q 'LIVE-ONLY'
```
```bash
  mkdir -p "$BATS_TEST_TMPDIR/bare-mirror"
```
```bash
  printf '%s' "$output" | grep -q 'UNCONFIRMED'
```

**Why it is wrong** — Both fixtures are the identical shape: a live file present in `$Q`, a mirror directory under `$BATS_TEST_TMPDIR` that is not inside any git checkout, and no `CC_ACTIVATION_REPO`. The M4 comment states the rule explicitly: "A non-checkout mirror has no trunk ref to adjudicate against, and guessing either way is wrong." The discriminator in the working M4 pair is checkout-ness (M4b's mirror at line 252 *is* a checkout and is asserted `LIVE-ONLY`; the bare dir at line 264 is asserted `UNCONFIRMED`). Line 95 therefore asserts the forbidden guess. If the tool honours M4, line 95 can only be matching a string that is not the verdict for that file (a section header or legend), i.e. the oldest LIVE-ONLY test survived the M4 change by matching the wrong text. The same latent problem sits at line 157–158 (`--parity` drift against the same non-checkout mirror).

---

### 2. The `UNCONFIRMED` test does not exclude the verdict it exists to prevent

**What** — The I7 test asserts only that the string `UNCONFIRMED` appears somewhere, never that the wrong verdict and its damaging remediation are absent.

**Where** — line 265:
```bash
  printf '%s' "$output" | grep -q 'UNCONFIRMED'
```

**Why it is wrong** — Its own comment names the two failure modes: "guess 'on trunk' and the unrecoverable alarm dies, guess 'absent' and the board tells the operator to cp a committed file." A board that prints `LIVE-ONLY — never committed … cp live->repo` for `orphan-activate.sh` **and** an `UNCONFIRMED` note elsewhere (a footer, another row, a legend) passes this test. The precise harm — the `cp live->repo` directive on an unadjudicated file — is never asserted against, even though the sibling test at line 244 shows exactly how to assert it.

---

### 3. The M4 negative assertion is pinned to one exact sentence, so it excludes nothing

**What** — The "must not say never committed" guard greps for a full literal verdict sentence instead of the verdict class, so almost any rendering of a `LIVE-ONLY` verdict slips past it.

**Where** — line 242:
```bash
  ! printf '%s' "$output" | grep -q "LIVE-ONLY — never committed, one .rm. from unrecoverable: landed-activate.sh" || false
```

**Why it is wrong** — The match requires the em dash, the exact wording, and `landed-activate.sh` immediately after `: ` on the same line. If the tool renders `LIVE-ONLY (1): landed-activate.sh`, or lists the file second in a multi-file line, or re-words the clause, the negative passes while the operator is still being told the file was never committed. The sibling tests at lines 255 and 276 assert on the bare class token (`UNDEPLOYED-MIRROR`); this one does not, so the regression it was written for is not actually fenced.

---

### 4. Axis-2 isolation is broken in three fixtures, so filename assertions can be satisfied by axis 1

**What** — The axis-2 section declares its fixtures are `.done`-marked throughout so that findings are attributable to the parity axis alone, but three fixtures carry no `.done` marker and are fresh, so axis 1 fires and names the very file the parity assertion greps for.

**Where** — line 84 (the stated invariant), violated at lines 91, 109 and 134:
```bash
# Fixtures are `.done`-MARKED throughout, so axis 1 stays silent and every finding below is
```
```bash
  stage "12-only-live-activate.sh"
```
```bash
  printf '#!/bin/bash\n# LIVE\n' > "$Q/07-drift-activate.sh"
```
```bash
  stage "x-activate.sh"
```

**Why it is wrong** — Since M3 made axis 1 partition instead of filter (the file says so at lines 85–86), an un-`.done` fresh file is always listed under `FRESH`. So `grep -q '12-only-live-activate.sh'` (line 94) and `grep -q '07-drift-activate.sh'` (line 112) are satisfied by the axis-1 partition even if axis 2 names nothing at all; only the class token on the following line still carries information. The two assertions that are supposed to prove "this file was named by the parity axis" prove nothing about the parity axis.

---

### 5. The M5 kill-switch test passes if the hook produces no output at all

**What** — The `CC_ACTIVATION_INERT_SCOPE=claude` test consists of a single negative grep, with no status check and no positive assertion that the hook ran.

**Where** — lines 325–327:
```bash
  CC_ACTIVATION_DIR="$Q" CC_ACTIVATION_INERT_SCOPE=claude \
    CC_ACTIVATION_LAUNCHCTL_BIN="$(lcstub '' '')" run "$H"
  ! printf '%s' "$output" | grep -q 'CLAIMED-DONE BUT INERT' || false
```

**Why it is wrong** — If the hook rejects the `CC_ACTIVATION_INERT_SCOPE` value, aborts on the stub, or exits non-zero before emitting anything, `$output` is empty, the negative grep succeeds, and the test reports that the kill switch works. The other two kill-switch tests anchor themselves with a positive assertion first (line 208 `'staged >24h and NOT run'`, line 275 `'LIVE-ONLY'`); this one has no anchor, so it cannot distinguish "switch restored the narrow scope" from "hook did nothing."

---

### 6. The `launchctl` stub never emits an *enabled* override entry, so DISABLED vs NOT-LOADED is not actually discriminated

**What** — `lcstub`'s `print-disabled` branch only ever prints labels in the `=> disabled` state; a label that is present in the override DB but enabled cannot be represented, so the `[NOT-LOADED]` case is exercised only against a completely empty override listing.

**Where** — line 288, used at lines 316–319:
```bash
    printf '  print-disabled) for l in %s; do printf "\\t\\"%%s\\" => disabled\\n" "$l"; done ;;\n' "${2:-}"
```
```bash
  printf '%s' "$output" | grep -q 'com.claude.log-rotation \[DISABLED\]'
  CC_ACTIVATION_DIR="$Q" CC_ACTIVATION_LAUNCHCTL_BIN="$(lcstub '' '')" run "$H"
  printf '%s' "$output" | grep -q 'com.claude.log-rotation \[NOT-LOADED\]'
```

**Why it is wrong** — In the second half the label is absent from `print-disabled` output entirely, not present-and-enabled. A hook that decides `DISABLED` by merely finding the label name anywhere in the `print-disabled` output — ignoring the state token — passes both halves of this test, yet on a real machine, where `print-disabled` lists overridden labels in both states, it reports every enabled-but-not-loaded label as `[DISABLED]` and sends the operator to `enable` when the answer is `bootstrap`. That is precisely the inversion the test's own comment says it exists to catch.

---

### 7. The symlink test compares a logically-resolved `$REPO` against a physically-resolved path

**What** — `$REPO` is built with a logical `cd`/`pwd`, while the behaviour under test is that the hook physically dereferences `BASH_SOURCE`; if any component of the checkout path is a symlink the two strings differ.

**Where** — line 7 and line 149:
```bash
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
```
```bash
  printf '%s' "$output" | grep -q "$REPO/docs/activation/pending-activation"
```

**Why it is wrong** — `cd` without `-P` and bash's `pwd` keep the logical path. If the checkout is reached through a symlinked component (on macOS, anything under `/tmp` → `/private/tmp`, or a symlinked home), `$REPO` is `/tmp/checkout` while a correctly deref'ing hook prints `/private/tmp/checkout/docs/activation/pending-activation`. The grep then fails and the test reports a symlink-resolution regression that did not happen — the check fails for the wrong reason, on the one axis where symlinks are the subject. Secondarily, `$REPO` is interpolated unquoted into a basic regex, so `.` and other metacharacters in the path match loosely.

---

### 8. The M4 "deploy-lag" fixture builds the opposite ancestry from the one it documents, and three of its commands are inert

**What** — The comment says the checkout is *behind* trunk, but the fixture leaves the clone one commit *ahead* of `origin/main` with a local deletion; the preceding `git rm`/`commit`/`reset --hard` trio cancels out and contributes nothing.

**Where** — lines 234–237:
```bash
  # the checkout is BEHIND trunk for this path — the deploy-lag shape
  ( cd "$w"; git rm -q docs/activation/pending-activation/landed-activate.sh; git commit -q -m drop
    git reset -q --hard HEAD~1; git rm -q --cached docs/activation/pending-activation/landed-activate.sh
    rm -f docs/activation/pending-activation/landed-activate.sh; git commit -q -m "checkout behind" ) >/dev/null 2>&1
```

**Why it is wrong** — `git reset -q --hard HEAD~1` discards the `drop` commit and restores the file, so the first two commands are dead; the net state is the same as the kill-switch fixture at lines 270–271. More importantly, "behind trunk" means `origin/main` has commits the checkout lacks; here `origin/main` is the base commit and local `main` is a descendant that deletes the path. An adjudicator that gates on ancestry (e.g. "is HEAD behind `@{upstream}`?" before consulting trunk) sees a checkout that is *ahead with an intentional deletion* — a shape for which `UNDEPLOYED-MIRROR` is the wrong answer — so the test only exercises the intended path if the adjudicator happens to reduce to a bare `origin/main:<path>` existence check. The claim in the test name is not established by the fixture.
