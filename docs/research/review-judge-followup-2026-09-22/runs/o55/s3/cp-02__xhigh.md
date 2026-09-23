# Review of `tests/activation-watch.bats`

Line numbers count the shebang as line 1. I found 11 defects, ordered roughly by severity. Items 1, 2, 4, 7 and 10 are the strongest.

---

### 1. LIVE-ONLY test: the filename assertion is satisfied by axis 1, not by the parity axis

- **What:** The fixture is fresh and has no `.done` marker, so axis 1 names the file. The filename grep passes whether or not the parity axis reports it.
- **Where:** lines 91, 94, 95
  ```
    stage "12-only-live-activate.sh"
    printf '%s' "$output" | grep -q '12-only-live-activate.sh'
    printf '%s' "$output" | grep -q 'LIVE-ONLY'
  ```
- **Why it is wrong:**
  - The section header (lines 84–85) promises that fixtures are `.done`-marked so every finding is attributable to parity alone.
  - Since M3, a fresh un-done entry is always named under FRESH (lines 47–51, 192). So line 94 passes even if the LIVE-ONLY row names the wrong file or no file.
  - Line 95 only proves the word `LIVE-ONLY` appears somewhere.
  - The mirror is also a plain non-git directory, which is the same shape as the UNCONFIRMED test (lines 262–265). For both tests to pass on one implementation, the unconfirmed-trunk output must contain "LIVE-ONLY". So this test no longer exercises a confirmed "never committed" verdict at all.

### 2. CONTENT-DRIFT test: same defect, and exit status is unchecked

- **What:** The live fixture has no `.done` marker, so axis 1 names `07-drift-activate.sh` and satisfies the filename grep regardless of the drift report.
- **Where:** lines 109, 112
  ```
    printf '#!/bin/bash\n# LIVE\n' > "$Q/07-drift-activate.sh"
    printf '%s' "$output" | grep -q '07-drift-activate.sh'
  ```
- **Why it is wrong:**
  - If CONTENT-DRIFT is printed without the file, or for a different file, the test still passes.
  - There is no `[ "$status" -eq 0 ]`, so a hook that reports drift and then exits non-zero also passes. That breaks the fail-open contract asserted everywhere else.

### 3. Unresolvable-mirror test: fixture not `.done`-marked (lower confidence)

- **What:** Axis 1 also fires in this test, so `DID NOT RUN` is not isolated to the parity axis.
- **Where:** lines 134, 138
  ```
    stage "x-activate.sh"
    printf '%s' "$output" | grep -q 'DID NOT RUN'
  ```
- **Why it is wrong:** The assertion is attributed to mirror resolution only on the assumption that no axis-1 text contains that phrase. Header lines 84–87 explicitly say this kind of borrowed isolation is "a coincidence".

### 4. Symlink test: the `~/.claude` negative assertion can never fire

- **What:** The symlink is created in `$BATS_TEST_TMPDIR`, so an un-dereferenced `BASH_SOURCE` resolves to the tmpdir's parent, never to a `.claude` directory.
- **Where:** lines 145, 150 (and 149)
  ```
    ln -s "$H" "$BATS_TEST_TMPDIR/linked.sh"
    ! printf '%s' "$output" | grep -q '\.claude/docs/activation'
  ```
- **Why it is wrong:**
  - The regression named in lines 142–143 is REPO=~/.claude. This fixture cannot produce that path, so line 150 passes whether dereferencing works or not.
  - Line 148 claims the test also proves the result is "not the FALLBACK_REPO shared checkout". Line 149 cannot distinguish the two when the suite runs from the shared checkout itself. In that case, a hook whose `.git` gate rejects the un-dereferenced path and falls back passes.

### 5. M4a: the LIVE-ONLY negative matches one unverified exact phrasing

- **What:** The negative matches only one exact rendering of the LIVE-ONLY line, and no test anywhere proves the hook emits that string.
- **Where:** line 242
  ```
    ! printf '%s' "$output" | grep -q "LIVE-ONLY — never committed, one .rm. from unrecoverable: landed-activate.sh" || false
  ```
- **Why it is wrong:** The pattern depends on the em dash, the wording, and the file being the first or only entry after `: `. M4b (line 253) greps only `LIVE-ONLY`. If the real wording or layout differs, a hook that misclassifies `landed-activate.sh` as LIVE-ONLY (while also printing UNDEPLOYED-MIRROR) passes.

### 6. M4a and M4 kill switch: fixtures build a checkout that is ahead of trunk, not behind it

- **What:** The fixture commands produce local `main` one unpushed commit ahead of `origin/main` and zero behind. That is the opposite of the "trails origin/main" shape the section claims to test.
- **Where:** lines 234–237 (and 270–271)
  ```
    # the checkout is BEHIND trunk for this path — the deploy-lag shape
    ( cd "$w"; git rm -q docs/activation/pending-activation/landed-activate.sh; git commit -q -m drop
      git reset -q --hard HEAD~1; git rm -q --cached docs/activation/pending-activation/landed-activate.sh
      rm -f docs/activation/pending-activation/landed-activate.sh; git commit -q -m "checkout behind" ) >/dev/null 2>&1
  ```
- **Why it is wrong:**
  - The `drop` commit followed by `reset --hard HEAD~1` is a net no-op. The remaining commit is a local deletion on top of trunk.
  - The deploy-lag case in lines 215–216 is never constructed. Only "present on origin/main, absent from the working tree" is tested.
  - Any adjudication logic that depends on the checkout actually being behind is untested.

### 7. M4b positive control accepts an UNCONFIRMED (unread-trunk) verdict

- **What:** The control never excludes UNCONFIRMED. So it passes when the adjudicator failed to read trunk, not only when it confirmed the file is absent.
- **Where:** lines 253, 255 (and 228)
  ```
    printf '%s' "$output" | grep -q 'LIVE-ONLY'
    ! printf '%s' "$output" | grep -q 'UNDEPLOYED-MIRROR' || false
  ```
- **Why it is wrong:**
  - As inferred in finding 1, the unreadable-trunk output also contains `LIVE-ONLY`.
  - An adjudicator that treats "not found on trunk" as "unreadable" therefore passes both M4a and this control.
  - `mkmirror` discards all git output (`... git push -q -u origin main ) >/dev/null 2>&1`) and nothing verifies the base commit or push landed. If the commit fails (for example because of a global signing config), there is no `origin/main`, the verdict is UNCONFIRMED, and this control still passes.

### 8. M3 kill switch: "restores the >24h filter exactly" is only half-checked

- **What:** The test never asserts that the stale entry is still named or that the count is 1.
- **Where:** lines 208–209
  ```
    printf '%s' "$output" | grep -q 'staged >24h and NOT run'
    ! printf '%s' "$output" | grep -q 'b-new-activate.sh' || false
  ```
- **Why it is wrong:** Two broken kill switches would pass:
  - one that prints the legacy header but names nothing (line 209 is trivially true for an empty list);
  - one that counts both entries but lists one.

  The exit status is also unchecked.

### 9. M5 positive control: a crash is indistinguishable from "the axis went quiet"

- **What:** The only assertion is an absence check. The exit status and the emptiness of the output are never checked.
- **Where:** lines 306–307
  ```
    CC_ACTIVATION_DIR="$Q" CC_ACTIVATION_LAUNCHCTL_BIN="$(lcstub 'com.chrisren.mailbox-gc' '')" run "$H"
    ! printf '%s' "$output" | grep -q 'CLAIMED-DONE BUT INERT' || false
  ```
- **Why it is wrong:** In this fixture everything is `.done`, the mirror is the queue, and the label is loaded, so the correct output is empty. If the hook dies while parsing the stub's loaded `list` row (non-zero exit, error text in `$output`), the test passes.

### 10. M5 DISABLED/NOT-LOADED test never checks that the other tag is absent

- **What:** Each run asserts only that its own tag appears, so "distinguished" is never tested.
- **Where:** lines 317, 319
  ```
    printf '%s' "$output" | grep -q 'com.claude.log-rotation \[DISABLED\]'
    printf '%s' "$output" | grep -q 'com.claude.log-rotation \[NOT-LOADED\]'
  ```
- **Why it is wrong:** The defect described in lines 311–312 is that a disabled label was reported as not-loaded, which sends the operator to `bootstrap`. A hook that still emits `[NOT-LOADED]` from the `launchctl list` check, alongside the new `[DISABLED]`, passes the first run.

### 11. M5 kill switch: only an absence check, with no proof that the com.claude scope still works

- **What:** The test passes if `CC_ACTIVATION_INERT_SCOPE=claude` disables axis 3 entirely or crashes the hook.
- **Where:** lines 325–327
  ```
    CC_ACTIVATION_DIR="$Q" CC_ACTIVATION_INERT_SCOPE=claude \
      CC_ACTIVATION_LAUNCHCTL_BIN="$(lcstub '' '')" run "$H"
    ! printf '%s' "$output" | grep -q 'CLAIMED-DONE BUT INERT' || false
  ```
- **Why it is wrong:** The title claims the switch "restores the com.claude-only pattern". Nothing shows a `com.claude.*` label is still flagged under this scope, and nothing checks exit status or output emptiness. A no-op or crashing axis passes.
