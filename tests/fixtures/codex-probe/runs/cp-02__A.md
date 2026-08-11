I read the whole file. The shell mechanics are largely sound — notably, every `!`-negated grep is either the final command of its test or protected with `|| false`, so the classic bats silent-negation trap is avoided throughout. The defects I can point at are all in fixture setup and assertion attribution: tests that no longer prove what they claim, and two that can pass vacuously. I found four.

---

**Defect 1 — Two tests in the same file demand different verdicts for the same input, so at least one of them passes (or would fail) for the wrong reason.**

**Where:** lines 90–95 versus lines 262–265:

```bash
  M="$BATS_TEST_TMPDIR/mirror"; mkdir -p "$M"
  stage "12-only-live-activate.sh"
  ...
  printf '%s' "$output" | grep -q 'LIVE-ONLY'
```
```bash
  mkdir -p "$BATS_TEST_TMPDIR/bare-mirror"
  ...
  printf '%s' "$output" | grep -q 'UNCONFIRMED'
```

**Why it is wrong:** Both tests give the hook the identical parity-relevant input: a live script present in the queue and a mirror that is an empty plain directory with no git checkout behind it (`mkdir -p` under `$BATS_TEST_TMPDIR` in both cases; the only fixture difference is the `.done` marker, which belongs to axis 1). The M4 test, and its comment at lines 259–261, establish the contract that a non-checkout mirror has no trunk to adjudicate against and that guessing "absent" (i.e., LIVE-ONLY) is wrong — the verdict must be UNCONFIRMED. Yet the earlier test requires the string `LIVE-ONLY` for exactly that input. Both tests can pass simultaneously only if the UNCONFIRMED report happens to also contain the token `LIVE-ONLY` — in which case the earlier test, titled "staged live but never committed → named (the unrecoverable class)", passes on an *unconfirmed* verdict and never proves the confirmed classification it names, and the M4 test (which asserts only the presence of `UNCONFIRMED`, never the absence of a confident verdict) cannot detect a tool that confidently claims LIVE-ONLY alongside the UNCONFIRMED note. If the tokens are exclusive instead, one of the two tests must fail. Either way, one of these assertions is not testing the class its test claims to cover.

---

**Defect 2 — Three axis-2 fixtures are not `.done`-marked, violating the section's stated isolation contract, and in two tests this lets the filename assertions be satisfied by axis-1 output instead of the parity axis under test.**

**Where:** the contract at lines 84–85:

```bash
# Fixtures are `.done`-MARKED throughout, so axis 1 stays silent and every finding below is
# attributable to the parity axis alone. ...
```

violated at line 91, line 109, and line 134:

```bash
  stage "12-only-live-activate.sh"
```
```bash
  printf '#!/bin/bash\n# LIVE\n' > "$Q/07-drift-activate.sh"
```
```bash
  stage "x-activate.sh"
```

**Why it is wrong:** None of these three fixtures gets a `.done` marker, so — as the header itself explains — under M3's partition-not-filter behavior, axis 1 names each of them in the FRESH partition of the same output. In the LIVE-ONLY test, `grep -q '12-only-live-activate.sh'` (line 94) is then satisfied by the axis-1 FRESH row even if the parity axis names nothing; the only remaining parity-attributable assertion is the bare token `LIVE-ONLY`, which an always-printed section label or count header (e.g., "LIVE-ONLY (0):") would satisfy with zero findings. The same holds for `grep -q '07-drift-activate.sh'` (line 112) in the CONTENT-DRIFT test. A parity axis that classifies correctly but drops or mangles the filename — the very thing "named" is supposed to pin — passes both tests. The `x-activate.sh` case (line 134) doesn't corrupt its own assertion (`DID NOT RUN` is parity-specific text) but still breaks the precondition the section header claims for every test below it.

---

**Defect 3 — Two tests consist solely of a negative grep with no status or positive assertion, so a hook that crashes and emits nothing passes them.**

**Where:** line 307 (the only assertion in "M5 POSITIVE CONTROL") and line 327 (the only assertion in "M5 kill switch"):

```bash
  ! printf '%s' "$output" | grep -q 'CLAIMED-DONE BUT INERT' || false
```

**Why it is wrong:** If `run "$H"` fails outright — the hook aborts on an unset variable, the generated launchctl stub is broken, any nonzero exit with empty output — `$output` contains no `CLAIMED-DONE BUT INERT`, the negation succeeds, and the test passes. Neither test checks `[ "$status" -eq 0 ]` nor any positive output, so a total failure of the hook is reported as the desired quiet behavior. The file's own M3 positive control (lines 200–201) shows the intended pattern — it pins both `status -eq 0` and `[ -z "$output" ]` — and these two tests omit it.

---

**Defect 4 — The DISABLED-versus-NOT-LOADED test never asserts the two states are mutually exclusive, so a tool that maps both states to the same combined output passes a test whose entire claim is that they are distinguished.**

**Where:** lines 316–319:

```bash
  CC_ACTIVATION_DIR="$Q" CC_ACTIVATION_LAUNCHCTL_BIN="$(lcstub '' 'com.claude.log-rotation')" run "$H"
  printf '%s' "$output" | grep -q 'com.claude.log-rotation \[DISABLED\]'
  CC_ACTIVATION_DIR="$Q" CC_ACTIVATION_LAUNCHCTL_BIN="$(lcstub '' '')" run "$H"
  printf '%s' "$output" | grep -q 'com.claude.log-rotation \[NOT-LOADED\]'
```

**Why it is wrong:** The first run never asserts the absence of `[NOT-LOADED]`, and the second run never asserts the absence of `[DISABLED]`. A hook that emits both rows for the label in both states — that is, one that does *not* distinguish disabled from not-loaded and would still send the operator to the wrong fix (`bootstrap` versus `enable`, per the test's own comment) — satisfies all four greps. The test's title ("DISABLED is distinguished from NOT-LOADED — they have OPPOSITE fixes") claims a discrimination that the assertions do not enforce.

---

Everything else I checked held up: the `stage`/`lcstub`/`mkmirror` helpers generate what they intend (including the empty `for l in ; do` word list, which is valid bash), the env-prefix-before-`run` pattern works for exporting to the hook, the m4a/m4c git choreography really does produce "file on origin/main, absent from the working tree", and the mid-test negations that need `|| false` all have it.