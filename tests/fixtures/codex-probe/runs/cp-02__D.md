I read the full file. Six defects.

---

### 1. Two tests assert contradictory verdicts for structurally identical fixtures

**What** — The axis-2 LIVE-ONLY test and the M4 UNREADABLE-trunk test build the same fixture (a live-only file against an empty, non-git mirror directory) and assert two different, mutually exclusive verdicts.

**Where** — lines 89–96 vs. lines 258–266:
```bash
  M="$BATS_TEST_TMPDIR/mirror"; mkdir -p "$M"
  stage "12-only-live-activate.sh"
```
```bash
  printf '%s' "$output" | grep -q 'LIVE-ONLY'
```
vs.
```bash
  mkdir -p "$BATS_TEST_TMPDIR/bare-mirror"
  printf '#!/bin/bash\n' > "$Q/orphan-activate.sh"; : > "$Q/orphan-activate.sh.done"
```
```bash
  printf '%s' "$output" | grep -q 'UNCONFIRMED'
```

**Why it is wrong** — `$BATS_TEST_TMPDIR/mirror` and `$BATS_TEST_TMPDIR/bare-mirror` are both plain `mkdir -p` directories with no `.git` and no trunk ref; in both cases the live file is absent from the mirror. Per the M4 test's own stated rule ("A non-checkout mirror has no trunk ref to adjudicate against"), line 95 is asserting the LIVE-ONLY verdict for an input the hook is required to report as UNCONFIRMED. Either line 95 is now failing, or the hook emits a single string carrying both tokens — in which case line 95 no longer proves "the unrecoverable class" and line 265 no longer proves the hook withheld a verdict. The same non-git mirror is used at lines 108, 117, 125, 154 and 166.

---

### 2. Axis-2 isolation invariant is violated by four of its own fixtures

**What** — The axis-2 section declares all its fixtures are `.done`-marked so axis 1 stays silent, but four fixtures have no `.done` marker, so axis 1 fires and produces the very strings the parity assertions grep for.

**Where** — line 84 states the invariant:
```bash
# Fixtures are `.done`-MARKED throughout, so axis 1 stays silent and every finding below is
```
Unmarked fixtures at lines 91, 109, 134, 155:
```bash
  stage "12-only-live-activate.sh"
```
```bash
  printf '#!/bin/bash\n# LIVE\n' > "$Q/07-drift-activate.sh"
```
```bash
  stage "x-activate.sh"
```
```bash
  stage "only-live.sh"
```

**Why it is wrong** — Since M3 turned the age gate into a partition (lines 184–193 pin this), a fresh un-run entry is now named under FRESH rather than filtered out. So for line 91 and line 109 the queue file is named by axis 1's FRESH partition regardless of what the parity axis does. The filename assertions at lines 94 and 112:
```bash
  printf '%s' "$output" | grep -q '12-only-live-activate.sh'
```
```bash
  printf '%s' "$output" | grep -q '07-drift-activate.sh'
```
therefore pass on axis-1 output alone. Neither test proves the parity axis named the file; a parity axis that emitted a bare `LIVE-ONLY:`/`CONTENT-DRIFT:` header with an empty file list would pass both.

---

### 3. The M4 regression guard is pinned to an exact sentence, so the regression it names survives any rewording

**What** — The negative assertion that proves a committed file is *not* misreported as never-committed matches a full literal sentence rather than the verdict token, so the misclassification passes the test if the message text changes at all.

**Where** — line 242:
```bash
  ! printf '%s' "$output" | grep -q "LIVE-ONLY — never committed, one .rm. from unrecoverable: landed-activate.sh" || false
```

**Why it is wrong** — The hook emits a bare `LIVE-ONLY` token; the sibling positive control at line 253 greps for exactly that, and line 255 uses the short form `! ... grep -q 'UNDEPLOYED-MIRROR' || false`. Line 242 instead requires the em dash, the phrase "never committed, one", the backticked `rm` (already wildcarded as `.rm.`), the word "unrecoverable", the colon, and the filename, all contiguous. Change the separator, insert a count or a bullet, or reflow the row, and a hook that has regressed to calling `landed-activate.sh` LIVE-ONLY still passes lines 240–244 — the M4 defect is exactly the one this line exists to catch.

---

### 4. `lcstub` cannot express an *enabled* override, so `[DISABLED]` is never distinguished from "listed in the override DB"

**What** — The launchctl stub only ever emits `=> disabled` lines, so a hook that decides DISABLED by the label's mere presence in `print-disabled` output passes the test that claims to verify the DISABLED state.

**Where** — line 288, and the assertion it feeds at line 317:
```bash
    printf '  print-disabled) for l in %s; do printf "\\t\\"%%s\\" => disabled\\n" "$l"; done ;;\n' "${2:-}"
```
```bash
  printf '%s' "$output" | grep -q 'com.claude.log-rotation \[DISABLED\]'
```

**Why it is wrong** — `launchctl print-disabled` lists every service with an override entry, disabled *and* enabled. The stub's `$2` parameter is the only thing that puts a label in that output, and it is hardcoded to render as `=> disabled`; there is no way to construct a fixture where a label appears in `print-disabled` but is not disabled. So the two candidate parsers — "grep the label" and "grep the label followed by `=> disabled`" — are indistinguishable under this suite. A hook using the first would tag every service with an *enabled* override as `[DISABLED]` and send the operator to `enable` a service that is already enabled, with no test failing.

---

### 5. The M5 kill switch proves only that the chrisren label went away, not that the claude scope survives

**What** — The kill-switch test asserts a single negative, so it passes if `CC_ACTIVATION_INERT_SCOPE=claude` disables the entire axis 3 rather than narrowing its label pattern.

**Where** — lines 322–328, whole body:
```bash
  printf '#!/bin/bash\n# loads com.chrisren.mailbox-gc\n' > "$Q/13-gc-activate.sh"
  : > "$Q/13-gc-activate.sh.done"
  CC_ACTIVATION_DIR="$Q" CC_ACTIVATION_INERT_SCOPE=claude \
    CC_ACTIVATION_LAUNCHCTL_BIN="$(lcstub '' '')" run "$H"
  ! printf '%s' "$output" | grep -q 'CLAIMED-DONE BUT INERT' || false
```

**Why it is wrong** — The only fixture is a `com.chrisren.*` label, and the only assertion is that no INERT row appears. Any implementation of the flag that produces no INERT row passes: scope narrowed to `com.claude.*` (correct), axis 3 skipped entirely, the launchctl invocation erroring out, or the hook exiting early — there is no `[ "$status" -eq 0 ]` either. The two other kill switches assert in both directions (line 208 + 209 for M3, line 275 + 276 for M4); this one has no `com.claude.*` fixture to show the narrowed pattern still fires, so "restores the com.claude-only pattern" is half-unverified.

---

### 6. `$REPO` is a logical path but the symlink test compares it against the hook's dereferenced path

**What** — The symlink test's positive assertion compares the hook's physically-resolved mirror path against a `$REPO` computed with logical `pwd`, so it fails whenever the checkout is reached through any symlinked path component — including `/tmp` on macOS.

**Where** — line 7, and the assertion at line 149:
```bash
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
```
```bash
  printf '%s' "$output" | grep -q "$REPO/docs/activation/pending-activation"
```

**Why it is wrong** — `cd` + `pwd` without `-P` preserves the logical path it was handed, so `$REPO` is whatever prefix `$BATS_TEST_FILENAME` carried. The behavior under test at line 147 is precisely that the hook dereferences its own path, which yields the physical prefix. On macOS `/tmp` is a symlink to `/private/tmp`: invoke the suite as `bats /tmp/…/tests/activation-watch.bats` and `$REPO` is `/tmp/…` while the hook correctly prints `/private/tmp/…`, so line 149 reports a failure for a hook that resolved the mirror exactly as the test title demands. The same mismatch occurs for any deployment where the checkout itself sits behind a symlink — the deployment shape the test's own comment at line 142 describes.