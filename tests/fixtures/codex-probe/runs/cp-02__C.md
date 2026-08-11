1. **What** — The self-test assertion counts 18 success lines but does not establish that 18 distinct checks actually ran.

   **Where** — Line 22:

   ```bash
     [ "$(printf '%s' "$output" | grep -c '^  ok ')" -eq 18 ]
   ```

   **Why it is wrong** — A self-test that executes one check repeatedly, skips another check, or merely prints 18 `ok` records exits successfully and passes this assertion.

2. **What** — Twelve normal hook invocations never assert the captured exit status.

   **Where** — Lines 36 and 75:

   ```bash
     CC_ACTIVATION_DIR="$Q" run "$H"
   ```

   Line 111:

   ```bash
     CC_ACTIVATION_DIR="$Q" CC_ACTIVATION_MIRROR_DIR="$M" run "$H"
   ```

   Line 207:

   ```bash
     CC_ACTIVATION_DIR="$Q" CC_ACTIVATION_AGE_FILTER=on run "$H"
   ```

   Lines 238 and 251:

   ```bash
     CC_ACTIVATION_DIR="$Q" CC_ACTIVATION_MIRROR_DIR="$w/docs/activation/pending-activation" run "$H"
   ```

   Line 262:

   ```bash
     CC_ACTIVATION_DIR="$Q" CC_ACTIVATION_MIRROR_DIR="$BATS_TEST_TMPDIR/bare-mirror" run "$H"
   ```

   Line 297:

   ```bash
     CC_ACTIVATION_DIR="$Q" CC_ACTIVATION_LAUNCHCTL_BIN="$(lcstub '' '')" run "$H"
   ```

   Line 305:

   ```bash
     CC_ACTIVATION_DIR="$Q" CC_ACTIVATION_LAUNCHCTL_BIN="$(lcstub 'com.chrisren.mailbox-gc' '')" run "$H"
   ```

   Line 314:

   ```bash
     CC_ACTIVATION_DIR="$Q" CC_ACTIVATION_LAUNCHCTL_BIN="$(lcstub '' 'com.claude.log-rotation')" run "$H"
   ```

   Line 316:

   ```bash
     CC_ACTIVATION_DIR="$Q" CC_ACTIVATION_LAUNCHCTL_BIN="$(lcstub '' '')" run "$H"
   ```

   Lines 323–324:

   ```bash
     CC_ACTIVATION_DIR="$Q" CC_ACTIVATION_INERT_SCOPE=claude \
       CC_ACTIVATION_LAUNCHCTL_BIN="$(lcstub '' '')" run "$H"
   ```

   **Why it is wrong** — Bats’ `run` captures a command’s failure in `$status` without failing the test, so these tests can succeed when the hook exits nonzero after printing an expected phrase; the negative-only M5 tests can even succeed after a silent crash.

3. **What** — The JSON assertions accept a stream containing multiple JSON documents despite claiming that the hook emits one SessionStart object.

   **Where** — Lines 37–38:

   ```bash
     printf '%s' "$output" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart"' >/dev/null
     printf '%s' "$output" | jq -e '.hookSpecificOutput.additionalContext | test("x-activate.sh")' >/dev/null
   ```

   Lines 170–172:

   ```bash
     printf '%s' "$output" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart"' >/dev/null
     printf '%s' "$output" | jq -e '.hookSpecificOutput.additionalContext | test("ACTIVATION QUEUE")' >/dev/null
     printf '%s' "$output" | jq -e '.hookSpecificOutput.additionalContext | test("ACTIVATION SSOT PARITY")' >/dev/null
   ```

   **Why it is wrong** — `jq` accepts consecutive JSON values and `-e` bases success on the last produced result, so an extra valid JSON object before a final matching object passes even though the hook contract requires one emit.

4. **What** — Assertions intended to match literal filenames, labels, and paths instead interpret them as regular expressions.

   **Where** — Lines 30, 38, 50, 77, 79–80, 94, 103, 112, 149, 158, 192, 209, 240–241, 253, 299, and 315–317, including:

   ```bash
     printf '%s' "$output" | grep -q 'p0-14-activate.sh'
     printf '%s' "$output" | jq -e '.hookSpecificOutput.additionalContext | test("x-activate.sh")' >/dev/null
     printf '%s' "$output" | grep -q 'fresh-activate.sh'
     printf '%s' "$output" | grep -q 'ROTTING (>24h, 1): stale-a.sh'
     printf '%s' "$output" | grep -q 'fresh-b.sh'
     ! printf '%s' "$output" | grep -q 'done-c.sh'
     printf '%s' "$output" | grep -q '12-only-live-activate.sh'
     printf '%s' "$output" | grep -q '09-only-repo-activate.sh'
     printf '%s' "$output" | grep -q '07-drift-activate.sh'
     printf '%s' "$output" | grep -q "$REPO/docs/activation/pending-activation"
     printf '%s' "$output" | grep -q 'only-live.sh'
     printf '%s' "$output" | grep -q 'b-new-activate.sh'
     ! printf '%s' "$output" | grep -q 'b-new-activate.sh' || false
     printf '%s' "$output" | grep -q 'landed-activate.sh'
     ! printf '%s' "$output" | grep -q "LIVE-ONLY — never committed, one .rm. from unrecoverable: landed-activate.sh" || false
     printf '%s' "$output" | grep -q 'never-committed-activate.sh'
     printf '%s' "$output" | grep -q 'com.chrisren.mailbox-gc'
     printf '%s' "$output" | grep -q 'com.claude.log-rotation \[DISABLED\]'
     printf '%s' "$output" | grep -q 'com.claude.log-rotation \[NOT-LOADED\]'
   ```

   **Why it is wrong** — Every unescaped `.` matches any character, and arbitrary metacharacters in `$REPO` are also active, so corrupted identifiers can satisfy positive assertions while valid paths containing regex syntax can make the symlink test fail.

5. **What** — The LIVE-ONLY and CONTENT-DRIFT tests do not isolate parity from the pending-queue axis as their comments claim.

   **Where** — Lines 91–95:

   ```bash
     stage "12-only-live-activate.sh"
     CC_ACTIVATION_DIR="$Q" CC_ACTIVATION_MIRROR_DIR="$M" run "$H"
     [ "$status" -eq 0 ]
     printf '%s' "$output" | grep -q '12-only-live-activate.sh'
     printf '%s' "$output" | grep -q 'LIVE-ONLY'
   ```

   Lines 109–113:

   ```bash
     printf '#!/bin/bash\n# LIVE\n' > "$Q/07-drift-activate.sh"
     printf '#!/bin/bash\n# REPO\n' > "$M/07-drift-activate.sh"
     CC_ACTIVATION_DIR="$Q" CC_ACTIVATION_MIRROR_DIR="$M" run "$H"
     printf '%s' "$output" | grep -q '07-drift-activate.sh'
     printf '%s' "$output" | grep -q 'CONTENT-DRIFT'
   ```

   **Why it is wrong** — Both live files are fresh and lack `.done` markers, so axis 1 also names them; a parity report that prints the class heading but omits the affected filename still passes because the filename grep is satisfied by axis 1.

6. **What** — The mixed-queue test does not prove that the fresh entry is listed under the FRESH partition or excluded from ROTTING.

   **Where** — Lines 77–79:

   ```bash
     printf '%s' "$output" | grep -q 'ROTTING (>24h, 1): stale-a.sh'
     printf '%s' "$output" | grep -q 'FRESH (<24h, 1)'
     printf '%s' "$output" | grep -q 'fresh-b.sh'
   ```

   **Why it is wrong** — Output containing the expected FRESH heading but listing `fresh-b.sh` elsewhere, including an additional ROTTING row, satisfies all three independent searches despite violating the claimed partitioning.

7. **What** — The M3 kill-switch test never verifies that the stale activation itself is reported.

   **Where** — Lines 205–209:

   ```bash
     stage "a-old-activate.sh" "$OLD"
     stage "b-new-activate.sh"
     CC_ACTIVATION_DIR="$Q" CC_ACTIVATION_AGE_FILTER=on run "$H"
     printf '%s' "$output" | grep -q 'staged >24h and NOT run'
     ! printf '%s' "$output" | grep -q 'b-new-activate.sh' || false
   ```

   **Why it is wrong** — An implementation that emits only a generic stale heading, omits `a-old-activate.sh`, and filters out the fresh file passes while failing to restore the old filter’s named result.

8. **What** — `mkmirror` can report successful fixture creation after its Git setup has failed.

   **Where** — Lines 223–228:

   ```bash
     git init -q --bare "$o"; git clone -q "$o" "$w" 2>/dev/null
     ( cd "$w" || exit 1; git config user.email t@e.com; git config user.name t; git checkout -q -b main
       mkdir -p docs/activation/pending-activation
       printf '#!/bin/bash\n# committed\n' > docs/activation/pending-activation/landed-activate.sh
       git add -A; git commit -q -m base; git push -q -u origin main ) >/dev/null 2>&1
     printf '%s' "$w"
   ```

   **Why it is wrong** — Under normal Bash command-substitution semantics, intermediate failures can continue to the unconditional final `printf`, making `w="$(mkmirror ...)"` succeed with a nonexistent or partially initialized checkout and causing later assertions to operate on an unproven fixture.

9. **What** — The M4 fixture claimed to represent a checkout behind trunk actually leaves the checkout ahead of `origin/main`.

   **Where** — Line 227:

   ```bash
       git add -A; git commit -q -m base; git push -q -u origin main ) >/dev/null 2>&1
   ```

   Lines 234–236:

   ```bash
     ( cd "$w"; git rm -q docs/activation/pending-activation/landed-activate.sh; git commit -q -m drop
       git reset -q --hard HEAD~1; git rm -q --cached docs/activation/pending-activation/landed-activate.sh
       rm -f docs/activation/pending-activation/landed-activate.sh; git commit -q -m "checkout behind" ) >/dev/null 2>&1
   ```

   **Why it is wrong** — The only pushed commit is `base`; after resetting to it, the test creates an unpushed deletion commit whose parent is `origin/main`, so local `main` is one commit ahead and a defect specific to an upstream-advanced/locally-behind checkout is never exercised.

10. **What** — The M4 verdict assertions can pass without proving that the fixture receives only the claimed classification.

    **Where** — Lines 239–243:

    ```bash
      printf '%s' "$output" | grep -q 'UNDEPLOYED-MIRROR'
      printf '%s' "$output" | grep -q 'landed-activate.sh'
      ! printf '%s' "$output" | grep -q "LIVE-ONLY — never committed, one .rm. from unrecoverable: landed-activate.sh" || false
      # …and it must NOT tell the operator to cp a committed file back into the repo
      printf '%s' "$output" | grep -q 'do NOT cp live->repo'
    ```

    Line 263:

    ```bash
      printf '%s' "$output" | grep -q 'UNCONFIRMED'
    ```

    Lines 273–274:

    ```bash
      printf '%s' "$output" | grep -q 'LIVE-ONLY'
      ! printf '%s' "$output" | grep -q 'UNDEPLOYED-MIRROR' || false
    ```

    **Why it is wrong** — The first case permits an erroneous LIVE-ONLY verdict with different wording, the unreadable case permits UNCONFIRMED alongside a confident verdict or without naming `orphan-activate.sh`, and the kill-switch case permits a generic LIVE-ONLY banner that omits `landed-activate.sh`.

11. **What** — `lcstub` can return a usable-looking path and success after failing to create or make the stub executable.

    **Where** — Line 289:

    ```bash
      } > "$f"; chmod +x "$f"; printf '%s' "$f"
    ```

    **Why it is wrong** — Because the function is called through command substitution and ends with an unconditional successful `printf`, a write or `chmod` failure can be hidden, leaving M5 tests to interpret an unexecutable stub’s empty/error behavior as launchctl state.

12. **What** — The launchctl stub models the disabled database with the wrong value syntax.

    **Where** — Line 286:

    ```bash
        printf '  print-disabled) for l in %s; do printf "\\t\\"%%s\\" => disabled\\n" "$l"; done ;;\n' "${2:-}"
    ```

    **Why it is wrong** — Real `launchctl print-disabled` represents an explicitly disabled label as `"label" => true`, not `=> disabled`, so code validated against this fixture can classify a genuinely disabled production label as merely NOT-LOADED and give the opposite operational advice.

13. **What** — The M5 loaded-label positive control does not enforce its stated “NO row” or quiet-output result.

    **Where** — Lines 305–306:

    ```bash
      CC_ACTIVATION_DIR="$Q" CC_ACTIVATION_LAUNCHCTL_BIN="$(lcstub 'com.chrisren.mailbox-gc' '')" run "$H"
      ! printf '%s' "$output" | grep -q 'CLAIMED-DONE BUT INERT' || false
    ```

    **Why it is wrong** — A loaded label can still be emitted in an erroneous state row or other output lacking that exact heading, and the test passes despite the axis not going quiet.

14. **What** — The M5 state test checks for the expected state in each run but never rejects the opposite state in the same output.

    **Where** — Lines 314–317:

    ```bash
      CC_ACTIVATION_DIR="$Q" CC_ACTIVATION_LAUNCHCTL_BIN="$(lcstub '' 'com.claude.log-rotation')" run "$H"
      printf '%s' "$output" | grep -q 'com.claude.log-rotation \[DISABLED\]'
      CC_ACTIVATION_DIR="$Q" CC_ACTIVATION_LAUNCHCTL_BIN="$(lcstub '' '')" run "$H"
      printf '%s' "$output" | grep -q 'com.claude.log-rotation \[NOT-LOADED\]'
    ```

    **Why it is wrong** — An implementation that emits both `[DISABLED]` and `[NOT-LOADED]` for every absent label passes both searches while still presenting the two opposite actions simultaneously.

15. **What** — The M5 kill-switch test proves only that `com.chrisren` becomes quiet, not that the requested `com.claude`-only checking remains active.

    **Where** — Lines 320–325:

    ```bash
    @test "M5 kill switch: CC_ACTIVATION_INERT_SCOPE=claude restores the com.claude-only pattern" {
      printf '#!/bin/bash\n# loads com.chrisren.mailbox-gc\n' > "$Q/13-gc-activate.sh"
      : > "$Q/13-gc-activate.sh.done"
      CC_ACTIVATION_DIR="$Q" CC_ACTIVATION_INERT_SCOPE=claude \
        CC_ACTIVATION_LAUNCHCTL_BIN="$(lcstub '' '')" run "$H"
      ! printf '%s' "$output" | grep -q 'CLAIMED-DONE BUT INERT' || false
    ```

    **Why it is wrong** — An implementation that disables axis 3 entirely whenever the switch equals `claude` passes this test, even though unloaded `com.claude` labels would also be silently ignored.