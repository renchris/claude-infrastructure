1. **What** — The self-test only counts 18 `ok` lines and does not establish that 18 distinct checks actually ran.

   **Where** — Lines 20–23:

   ```bash
     run "$H" --selftest
     [ "$status" -eq 0 ]
     [ "$(printf '%s' "$output" | grep -c '^  ok ')" -eq 18 ]
     ! printf '%s' "$output" | grep -q '^  FAIL'
   ```

   **Why it is wrong** — A broken self-test that executes one check repeatedly, or merely prints the same `ok` result 18 times, exits zero, and prints no matching `FAIL` line passes this test despite not running all 18 checks.

2. **What** — The JSON checks accept multiple top-level JSON values, so they do not establish a single valid SessionStart emission.

   **Where** — Lines 37–38 and 168–170:

   ```bash
     printf '%s' "$output" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart"' >/dev/null
     printf '%s' "$output" | jq -e '.hookSpecificOutput.additionalContext | test("x-activate.sh")' >/dev/null
   ```

   ```bash
     printf '%s' "$output" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart"' >/dev/null
     printf '%s' "$output" | jq -e '.hookSpecificOutput.additionalContext | test("ACTIVATION QUEUE")' >/dev/null
     printf '%s' "$output" | jq -e '.hookSpecificOutput.additionalContext | test("ACTIVATION SSOT PARITY")' >/dev/null
   ```

   **Why it is wrong** — `jq` accepts a stream of JSON values, so output containing the same conforming object twice passes every assertion even though the hook emitted two objects rather than the one object required by the contract and explicitly claimed by the second test.

3. **What** — The LIVE-ONLY and CONTENT-DRIFT fixtures are not `.done`-marked, so their filenames are also emitted by axis 1 and can satisfy the parity tests for the wrong reason.

   **Where** — Lines 89, 92–93, 107, and 110–111:

   ```bash
     stage "12-only-live-activate.sh"
   ```

   ```bash
     printf '%s' "$output" | grep -q '12-only-live-activate.sh'
     printf '%s' "$output" | grep -q 'LIVE-ONLY'
   ```

   ```bash
     printf '#!/bin/bash\n# LIVE\n' > "$Q/07-drift-activate.sh"
   ```

   ```bash
     printf '%s' "$output" | grep -q '07-drift-activate.sh'
     printf '%s' "$output" | grep -q 'CONTENT-DRIFT'
   ```

   **Why it is wrong** — Because both files are fresh and pending, axis 1 names them; if parity emits the relevant category heading but omits the affected filename, the separate greps still pass without proving that parity classified and named that file.

4. **What** — The M3 kill-switch test never verifies that the stale activation itself is retained by the restored age filter.

   **Where** — Lines 206–207:

   ```bash
     printf '%s' "$output" | grep -q 'staged >24h and NOT run'
     ! printf '%s' "$output" | grep -q 'b-new-activate.sh' || false
   ```

   **Why it is wrong** — If filter mode prints the generic stale headline, suppresses every activation name, and excludes the fresh file, both assertions pass even though `a-old-activate.sh` was incorrectly dropped.

5. **What** — `mkmirror` can return success and a checkout path after its repository construction has failed.

   **Where** — Lines 221–226:

   ```bash
     git init -q --bare "$o"; git clone -q "$o" "$w" 2>/dev/null
     ( cd "$w" || exit 1; git config user.email t@e.com; git config user.name t; git checkout -q -b main
       mkdir -p docs/activation/pending-activation
       printf '#!/bin/bash\n# committed\n' > docs/activation/pending-activation/landed-activate.sh
       git add -A; git commit -q -m base; git push -q -u origin main ) >/dev/null 2>&1
     printf '%s' "$w"
   ```

   **Why it is wrong** — An initialization, clone, commit, or push failure is neither checked nor propagated, and the final successful `printf` can make the command substitution succeed while subsequent tests operate on a checkout that lacks the trunk state they assume.

6. **What** — The `launchctl` stub accepts malformed invocations and reports success for unknown subcommands.

   **Where** — Lines 283–287:

   ```bash
       printf 'case "$1" in\n'
       printf '  list) for l in %s; do printf "%%s\\t0\\t%%s\\n" - "$l"; done ;;\n' "${1:-}"
       printf '  print-disabled) for l in %s; do printf "\\t\\"%%s\\" => disabled\\n" "$l"; done ;;\n' "${2:-}"
       printf 'esac\nexit 0\n'
   ```

   **Why it is wrong** — The generated stub examines only the subcommand, ignores its required arguments, and exits zero when no case matches, so code that invokes `launchctl` with a wrong domain, wrong arguments, or an unsupported command can appear to have made a successful query.

7. **What** — The M5 “no row” assertions check only for the section heading, not for the supposedly excluded label or row.

   **Where** — Lines 305 and 324:

   ```bash
     ! printf '%s' "$output" | grep -q 'CLAIMED-DONE BUT INERT' || false
   ```

   ```bash
     ! printf '%s' "$output" | grep -q 'CLAIMED-DONE BUT INERT' || false
   ```

   **Why it is wrong** — If the hook incorrectly emits a `com.chrisren.mailbox-gc` inert row without that exact heading, both the loaded-label positive control and the `claude`-scope kill-switch test pass despite the row they claim to prohibit being present.