## Findings

---

### 1. Three axis-2 tests are missing the `.done` marker their own section header guarantees, so axis 1 fires and supplies the name the parity assertion checks for

**Where** — lines 84, 91, 94 and 109, 112, and 134:

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

**Why it is wrong** — `stage` (line 17) writes only the script; no line writes `$Q/12-only-live-activate.sh.done`, `$Q/07-drift-activate.sh.done`, or `$Q/x-activate.sh.done`. Each of those fixtures is therefore fresh *and* un-run, which after M3 is exactly the state axis 1 names (see lines 41–53 and 184–193): axis 1 prints the file under `FRESH` into the same `$output`. So lines 94 and 112 are satisfied by axis-1 output alone. If the parity axis printed a `LIVE-ONLY` / `CONTENT-DRIFT` header with an empty name list, or named the wrong file, both tests still pass — the failure the header at line 85–87 says was deliberately eliminated ("borrowing another axis's quiet was never isolation").

---

### 2. The M4 negative assertion is scoped to one exact sentence rather than to the verdict class it claims to forbid

**Where** — line 242:

```
  ! printf '%s' "$output" | grep -q "LIVE-ONLY — never committed, one .rm. from unrecoverable: landed-activate.sh" || false
```

**Why it is wrong** — the output format pinned elsewhere in this file is `LABEL (…, N): names` (line 77: `'ROTTING (>24h, 1): stale-a.sh'`), i.e. the label line carries a parenthesised count, which this pattern does not allow for. Any difference between the hook's wording and this fixed single-line string — a count prefix, a different dash, or the file name on a following line — makes the pattern unmatchable. Under that condition the assertion is vacuously true, and the test reports success while the hook is still emitting the "never committed, one `rm` from unrecoverable" verdict for a file that exists on trunk, which is the entire regression M4 exists to prevent. Compare lines 255 and 276, where the sibling negative is asserted against the bare label.

---

### 3. The "unreadable trunk" test never asserts that the false verdict is withheld — only that the word `UNCONFIRMED` appears somewhere

**Where** — line 265 (fixture at 262–264):

```
  printf '%s' "$output" | grep -q 'UNCONFIRMED'
```

**Why it is wrong** — a hook that prints the full `LIVE-ONLY — never committed…` verdict plus the `cp live -> repo` platter and merely appends the word `UNCONFIRMED` passes this test. That is precisely the outcome the test's own comment (lines 260–261) says is wrong: "guess 'absent' and the board tells the operator to cp a committed file." Line 244 asserts `do NOT cp live->repo` for the adjudicated case; nothing equivalent is asserted here. Worse, this fixture — a live-only file against a mirror directory that is not a checkout — is structurally the same condition as lines 90–95, which *requires* `LIVE-ONLY` to be printed for it. The two tests can only both pass if the hook keeps emitting the unadjudicated LIVE-ONLY verdict, and neither test can detect that.

---

### 4. The M5 kill switch is proven only by an absence, against a fixture that contains no in-scope label

**Where** — line 327 (fixture at 323–326):

```
  ! printf '%s' "$output" | grep -q 'CLAIMED-DONE BUT INERT' || false
```

**Why it is wrong** — the only label in the fixture is `com.chrisren.mailbox-gc`. If `CC_ACTIVATION_INERT_SCOPE=claude` is unrecognised by the hook, or turns axis 3 off entirely, the output contains no INERT row at all and this assertion passes — so the test cannot distinguish "scope narrowed back to `com.claude`" (its stated claim) from "axis 3 disabled". The other two kill-switch tests pair a positive with the negative (lines 208 + 209; 275 + 276); this one has no positive assertion, and no `com.claude` label is staged that would have to keep firing.

---

### 5. The `~/.claude` guard in the symlink test cannot fail for any hook behaviour, because the symlink is not under `~/.claude`

**Where** — lines 145 and 150:

```
  ln -s "$H" "$BATS_TEST_TMPDIR/linked.sh"
```
```
  ! printf '%s' "$output" | grep -q '\.claude/docs/activation'
```

**Why it is wrong** — the regression named in the comment (lines 142–143) is an un-dereferenced `BASH_SOURCE` when the hook is invoked as `~/.claude/hooks/activation-watch.sh`, which yields `REPO=~/.claude`. With this fixture the entry point is `$BATS_TEST_TMPDIR/linked.sh`, so an un-dereferenced `BASH_SOURCE` yields `REPO=$BATS_TEST_TMPDIR` — `.claude/docs/activation` can never appear in the output, and line 150 passes regardless of whether the hook dereferences anything. The test does not reproduce the wiring it cites (816015ecb30b).

---

### 6. The "fail-open on absent queue dir" test is silent because its mirror is empty, not because the hook fails open

**Where** — lines 15, 64 and 66:

```
  export CC_ACTIVATION_MIRROR_DIR="$Q"
```
```
  CC_ACTIVATION_DIR="$BATS_TEST_TMPDIR/nope" run "$H"
```
```
  [ -z "$output" ]
```

**Why it is wrong** — this test stages nothing, so `$Q` (created at line 10, still exported as the mirror at line 15) is an existing but empty directory. The parity axis therefore has a resolvable mirror with zero entries and nothing to report no matter how it treats a missing live queue. In the production shape the mirror is populated, so an absent live queue makes every mirror entry `REPO-ONLY` — loud output, the opposite of the "silent, exit 0 (fail-open)" behaviour this test claims to establish, and a condition the fixture never puts to the hook.

---

### 7. The test named for the `>24h` class asserts nothing that depends on age

**Where** — lines 26, 30 and 31:

```
@test "stale (>24h) un-run activation → named in the additionalContext" {
```
```
  printf '%s' "$output" | grep -q 'p0-14-activate.sh'
```
```
  printf '%s' "$output" | grep -q 'ACTIVATION QUEUE'
```

**Why it is wrong** — after M3, an un-run entry of *any* age is named under the `ACTIVATION QUEUE` section (lines 41–53, 184–193), so both assertions hold for a fresh fixture. If the hook mis-partitions a 25-hour-old entry as `FRESH`, or if `touch -t "$OLD"` never took effect — line 17 discards `touch`'s exit status via `return 0`, so a fixture that was meant to be stale can be fresh with no signal — this test still reports success. Unlike its fresh counterpart (line 52) and the mixed-queue test (line 77), it never greps `ROTTING`, so the age class it is named for is not covered here.

---

### 8. The launchctl stub cannot emit an explicitly *enabled* override entry, so the `NOT-LOADED` half of the DISABLED/NOT-LOADED test is only exercised against an empty override DB

**Where** — lines 288, 318 and 319:

```
    printf '  print-disabled) for l in %s; do printf "\\t\\"%%s\\" => disabled\\n" "$l"; done ;;\n' "${2:-}"
```
```
  CC_ACTIVATION_DIR="$Q" CC_ACTIVATION_LAUNCHCTL_BIN="$(lcstub '' '')" run "$H"
```
```
  printf '%s' "$output" | grep -q 'com.claude.log-rotation \[NOT-LOADED\]'
```

**Why it is wrong** — the stub's `print-disabled` branch only ever prints `=> disabled` lines, and with `lcstub '' ''` it prints nothing at all. The real override DB also lists labels that are present and enabled (`"label" => enabled`), and this fixture can never produce that input. So "absent from the override DB" and "present and explicitly enabled" are indistinguishable to this test: an implementation that keys `[DISABLED]` off the label appearing anywhere in `print-disabled` output passes both halves here, while in production it would label an explicitly enabled job `[DISABLED]` and hand the operator the `enable` remedy — the exact mix-up the test title says it distinguishes.
