1. **What** — A syntactically valid payload with a missing or non-string command is silently treated as a successfully validated empty command.

   **Where** — Line 40:

   ```bash
   if ! CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null); then
   ```

   **Why it is wrong** — For `{"tool_input":{}}`, `jq` emits nothing but exits successfully, so abstention is skipped, every check sees an empty `CMD`, and the hook exits 0 as though validation occurred.

2. **What** — The “never silently” abstention path can suppress a failed audit write and still report success.

   **Where** — Lines 34–37:

   ```bash
     printf '%s\t%s\t%s\n' "$(date -u +%FT%TZ 2>/dev/null || echo '?')" \
       'validate-bash-ABSTAIN' "fail-open, command NOT validated: $1" \
       >> "$HOME/.claude/logs/validate-bash-unclear.log" 2>/dev/null || true
     exit 0
   ```

   **Why it is wrong** — If the file opens but the write fails, such as from a full filesystem or I/O error, the diagnostic is redirected away, `|| true` erases the failure, and the function exits 0 without leaving the promised signal.

3. **What** — The shlex helper is marked available without verifying that sourcing succeeded, and unexpected helper failures are treated as “flag absent.”

   **Where** — Lines 51–52 and 99–103:

   ```bash
     source "$LIB_DIR/is-true-flag.sh"
     HAVE_IS_TRUE_FLAG=1
   ```

   ```bash
       is_true_flag "$flag" "$CMD"
       local rc=$?
       [[ "$rc" == "0" || "$rc" == "2" ]] && return 0
       return 1
   ```

   **Why it is wrong** — If the file exists but is unreadable, malformed, or does not define `is_true_flag`, the later call returns an unexpected status such as 127, which is converted to “no flag,” allowing protected flags through instead of using the fallback.

4. **What** — The legacy flag detector does not recognize shell operators as token boundaries and also mistakes whitespace-delimited text inside quotes for argv flags.

   **Where** — Lines 107–108:

   ```bash
       local pattern="(^|[[:space:]])${flag//./\\.}([[:space:]]|\$)"
       echo "$CMD" | grep -qE "$pattern"
   ```

   **Why it is wrong** — In legacy mode, `git commit --no-verify; true` is allowed because `;` is not an accepted trailing boundary, while `git commit -m "avoid --no-verify please"` is denied because the inert message substring is surrounded by spaces.

5. **What** — Several predicates use raw textual occurrence as proof of executable syntax, causing inert text to trigger decisions while shell-equivalent quoted words evade them.

   **Where** — Lines 116, 163–164, 169, 196, 203, 209, and 217:

   ```bash
   if echo "$CMD" | grep -qE '(rm[[:space:]]+-rf[[:space:]]+/[^a-zA-Z]|rm[[:space:]]+-rf[[:space:]]+\$HOME|rm[[:space:]]+-rf[[:space:]]+~(/|$|[[:space:]])|sudo[[:space:]]+rm|:\(\)\{[[:space:]]*:\|:&[[:space:]]*\};:)'; then
   if echo "$CMD" | grep -qiE '\b(turso|sqlite3?|psql|mysql|mariadb|libsql|drizzle-kit[[:space:]]+(push|drop|migrate))\b' \
      && echo "$CMD" | grep -qiE '\b(DROP[[:space:]]+TABLE|DROP[[:space:]]+DATABASE|DROP[[:space:]]+INDEX|ALTER[[:space:]]+TABLE|CREATE[[:space:]]+TABLE|TRUNCATE[[:space:]]+TABLE)\b'; then
   if echo "$CMD" | grep -qE 'drizzle-kit[[:space:]]+push'; then
   if echo "$CMD" | grep -qE 'git([[:space:]]+-[a-zA-Z]+[[:space:]]+[^[:space:]]+)*[[:space:]]+commit\b[^|&;]*[[:space:]]-n\b'; then
   if echo "$CMD" | grep -qE 'git[[:space:]]+reset[[:space:]]+--hard\b'; then
   if echo "$CMD" | grep -qE 'git[[:space:]]+clean[[:space:]]+-[a-zA-Z]*[xX]'; then
   RM_OCCURRENCES=$(echo "$CMD" | grep -oE 'rm[[:space:]]+-(r|rf|fr)[[:space:]]+[^[:space:];&|]+' || true)
   ```

   **Why it is wrong** — For example, `git commit -m "document sqlite3 DROP TABLE"` is denied and `printf '%s' 'git reset --hard'` is warned despite containing only data, while `r""m -rf /*` executes `rm` after Bash word concatenation but matches neither `rm` guard.

6. **What** — The catastrophic system-damage matcher misses ordinary commands belonging to the classes it claims to hard-deny.

   **Where** — Line 116:

   ```bash
   if echo "$CMD" | grep -qE '(rm[[:space:]]+-rf[[:space:]]+/[^a-zA-Z]|rm[[:space:]]+-rf[[:space:]]+\$HOME|rm[[:space:]]+-rf[[:space:]]+~(/|$|[[:space:]])|sudo[[:space:]]+rm|:\(\)\{[[:space:]]*:\|:&[[:space:]]*\};:)'; then
   ```

   **Why it is wrong** — Exact `rm -rf /` has no character after `/` for `[^a-zA-Z]` and therefore receives only the later warning, while `sudo -n rm -rf /etc` does not match the adjacent `sudo rm` alternative and likewise escapes the required hard deny.

7. **What** — The pkill command-position detector removes executable quoted content and recognizes only bare names or a directly adjacent `sudo`.

   **Where** — Lines 136–138:

   ```bash
   CMD_NOQ=$(printf '%s' "$CMD" | sed -e "s/'[^']*'/''/g" -e 's/"[^"]*"/""/g')
   if printf '%s' "$CMD_NOQ" | sed 's/[&|()]/;/g' | tr ';' '\n' | sed 's/^[[:space:]]*//' \
        | grep -qE '^(sudo[[:space:]]+)?(pkill|killall)([[:space:]]|$)'; then
   ```

   **Why it is wrong** — `"pkill" -f bats`, `/usr/bin/pkill -f bats`, `command pkill -f bats`, and `bash -c "pkill -f bats"` can all execute a broad kill, but none produces a segment beginning with the accepted pattern.

8. **What** — The pkill position test is global, while subsequent target checks process every textual occurrence, including occurrences never proven to be commands.

   **Where** — Lines 137–139 and 143:

   ```bash
   if printf '%s' "$CMD_NOQ" | sed 's/[&|()]/;/g' | tr ';' '\n' | sed 's/^[[:space:]]*//' \
        | grep -qE '^(sudo[[:space:]]+)?(pkill|killall)([[:space:]]|$)'; then
     PK_OCCURRENCES=$(echo "$CMD" | grep -oE '(pkill|killall)[^;&|]*' || true)
   ```

   ```bash
       echo "$pk" | grep -qE '(bats|ship-land|postland-verify)' || continue
   ```

   **Why it is wrong** — `pkill harmless; printf '%s' 'pkill -f bats'` passes the global position test because of the first command, then the quoted second occurrence is treated as an unscoped gate kill and the harmless compound command is denied.

9. **What** — Pkill targets are inferred by truncating raw text at regex metacharacters and then searching for literal name substrings, which does not establish what the pkill regular expression matches.

   **Where** — Lines 139 and 143:

   ```bash
     PK_OCCURRENCES=$(echo "$CMD" | grep -oE '(pkill|killall)[^;&|]*' || true)
   ```

   ```bash
       echo "$pk" | grep -qE '(bats|ship-land|postland-verify)' || continue
   ```

   **Why it is wrong** — `pkill -f 'unrelated|bats'` is truncated before `bats`, and `pkill -f 'bat[s]'` contains no literal `bats`, so both gate-targeting patterns pass; conversely, `pkill -f 'not-bats'` is denied solely because its unrelated pattern contains that substring.

10. **What** — The pkill scope checks accept the mere textual presence of a scope-looking fragment without proving that it constrains the kill to one worktree.

    **Where** — Lines 139, 147, and 151:

    ```bash
      PK_OCCURRENCES=$(echo "$CMD" | grep -oE '(pkill|killall)[^;&|]*' || true)
    ```

    ```bash
        if echo "$pk" | grep -qE '\$PWD|\$\{PWD|\$\(pwd|`pwd|\$\(basename|(^|[[:space:]])-P[[:space:]]|\.worktrees/|(^|[^a-zA-Z0-9])wt-[a-zA-Z0-9]'; then
    ```

    ```bash
        if [[ -n "${PWD##*/}" ]] && echo "$pk" | grep -qF -- "${PWD##*/}"; then
    ```

    **Why it is wrong** — `pkill -f bats # $PWD` is accepted because the ignored shell comment supplies `$PWD`, and `pkill -f '\.worktrees/.*bats'` is accepted because it contains `.worktrees/` even though that pattern targets bats processes in every worktree.

11. **What** — The DDL predicate covers only a small set of literal adjacent keyword pairs rather than all schema-changing commands it claims to block.

    **Where** — Lines 163–164:

    ```bash
    if echo "$CMD" | grep -qiE '\b(turso|sqlite3?|psql|mysql|mariadb|libsql|drizzle-kit[[:space:]]+(push|drop|migrate))\b' \
       && echo "$CMD" | grep -qiE '\b(DROP[[:space:]]+TABLE|DROP[[:space:]]+DATABASE|DROP[[:space:]]+INDEX|ALTER[[:space:]]+TABLE|CREATE[[:space:]]+TABLE|TRUNCATE[[:space:]]+TABLE)\b'; then
    ```

    **Why it is wrong** — `psql -c 'CREATE INDEX i ON t(c)'` performs DDL but is absent from the list, while `psql -c $'DROP\nTABLE t'` becomes a valid `DROP TABLE` at execution but the raw command has no matching whitespace between the keywords.

12. **What** — The `git add` decision associates a force flag found anywhere in the compound command with a `git add` occurrence found anywhere else.

    **Where** — Lines 174 and 177:

    ```bash
    if check_real_flag "--force" && echo "$CMD" | grep -qE 'git[[:space:]]+add\b'; then
    if check_real_flag "-f" && echo "$CMD" | grep -qE 'git[[:space:]]+add\b'; then
    ```

    **Why it is wrong** — `git add README && git push --force` is denied as force-adding even though the `git add` is ordinary and `--force` belongs to `git push`.

13. **What** — The Git command recognizers omit valid global-option forms and therefore skip the protected operation.

    **Where** — Lines 174, 177, 196, 203, and 209:

    ```bash
    if check_real_flag "--force" && echo "$CMD" | grep -qE 'git[[:space:]]+add\b'; then
    if check_real_flag "-f" && echo "$CMD" | grep -qE 'git[[:space:]]+add\b'; then
    if echo "$CMD" | grep -qE 'git([[:space:]]+-[a-zA-Z]+[[:space:]]+[^[:space:]]+)*[[:space:]]+commit\b[^|&;]*[[:space:]]-n\b'; then
    if echo "$CMD" | grep -qE 'git[[:space:]]+reset[[:space:]]+--hard\b'; then
    if echo "$CMD" | grep -qE 'git[[:space:]]+clean[[:space:]]+-[a-zA-Z]*[xX]'; then
    ```

    **Why it is wrong** — Valid commands such as `git -C repo add -f ignored`, `git --no-pager commit -n`, `git -C repo reset --hard`, and `git -C repo clean -fx` fail their respective context regexes and pass without the intended decision.

14. **What** — The short `-n` guard recognizes only a standalone token and misses `-n` bundled with another valid Git short option.

    **Where** — Line 196:

    ```bash
    if echo "$CMD" | grep -qE 'git([[:space:]]+-[a-zA-Z]+[[:space:]]+[^[:space:]]+)*[[:space:]]+commit\b[^|&;]*[[:space:]]-n\b'; then
    ```

    **Why it is wrong** — `git commit -an -m x` is parsed by Git as including `-n`, but the source contains no whitespace-delimited `-n`, so the pre-commit-hook bypass is allowed.

15. **What** — The `git clean` matcher examines only the first short-option bundle immediately after `clean`, not an `-x` or `-X` appearing later.

    **Where** — Line 209:

    ```bash
    if echo "$CMD" | grep -qE 'git[[:space:]]+clean[[:space:]]+-[a-zA-Z]*[xX]'; then
    ```

    **Why it is wrong** — `git clean -f -x` is the ordinary destructive spelling with force and ignored-file removal, but the first bundle is only `-f`, so the warning is skipped.

16. **What** — The rm recognizers miss valid recursive-force option bundles containing additional options.

    **Where** — Lines 116 and 217:

    ```bash
    if echo "$CMD" | grep -qE '(rm[[:space:]]+-rf[[:space:]]+/[^a-zA-Z]|rm[[:space:]]+-rf[[:space:]]+\$HOME|rm[[:space:]]+-rf[[:space:]]+~(/|$|[[:space:]])|sudo[[:space:]]+rm|:\(\)\{[[:space:]]*:\|:&[[:space:]]*\};:)'; then
    ```

    ```bash
    RM_OCCURRENCES=$(echo "$CMD" | grep -oE 'rm[[:space:]]+-(r|rf|fr)[[:space:]]+[^[:space:];&|]+' || true)
    ```

    **Why it is wrong** — `rm -rfv /*` performs the same recursive forced deletion with verbosity, but `v` prevents both expressions from matching, so it receives neither the hard deny nor the warning.

17. **What** — The rm extraction checks only the first operand, allowing later unsafe operands whenever the first is allowlisted.

    **Where** — Lines 217, 220, 223–224:

    ```bash
    RM_OCCURRENCES=$(echo "$CMD" | grep -oE 'rm[[:space:]]+-(r|rf|fr)[[:space:]]+[^[:space:];&|]+' || true)
    ```

    ```bash
        target=$(echo "$occurrence" | sed -E 's/^rm[[:space:]]+-(r|rf|fr)[[:space:]]+//')
        target_stripped=$(echo "$target" | sed -E 's|^\./||; s|^/||')
        if ! echo "$target_stripped" | grep -qE "^${SAFE_RM_TARGETS}(/|$)"; then
    ```

    **Why it is wrong** — For `rm -rf node_modules src`, extraction stops after `node_modules`, classifies that operand as safe, ignores `src`, and allows both directories to be removed without warning.

18. **What** — The safe-rm test accepts a lexical allowlisted prefix even when `..` makes the actual target leave that directory.

    **Where** — Lines 223–224:

    ```bash
        target_stripped=$(echo "$target" | sed -E 's|^\./||; s|^/||')
        if ! echo "$target_stripped" | grep -qE "^${SAFE_RM_TARGETS}(/|$)"; then
    ```

    **Why it is wrong** — When `node_modules` exists, `rm -rf node_modules/../src` resolves to `src`, but the textual prefix `node_modules/` makes the check classify it as a safe build-artifact target.

19. **What** — Quoting or redundantly qualifying an allowlisted rm target makes the code warn for the wrong reason.

    **Where** — Lines 220 and 223–225:

    ```bash
        target=$(echo "$occurrence" | sed -E 's/^rm[[:space:]]+-(r|rf|fr)[[:space:]]+//')
        target_stripped=$(echo "$target" | sed -E 's|^\./||; s|^/||')
        if ! echo "$target_stripped" | grep -qE "^${SAFE_RM_TARGETS}(/|$)"; then
          warn "rm -rf on non-build-artifact target: '$target'. Verify intentional."
    ```

    **Why it is wrong** — `rm -rf "node_modules"` leaves the quotes in `target`, and `rm -rf ././node_modules` removes only one leading `./`, so both safe targets fail the allowlist and incorrectly produce an ask decision.

20. **What** — The audit entry does not encode newlines or delimiters in either the session ID or command, so it does not preserve the claimed one-record-per-line attribution.

    **Where** — Lines 240 and 243:

    ```bash
    SID=$(printf '%s' "$INPUT" | jq -r '.session_id // "-"' 2>/dev/null)
    echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [$SID] $CMD" >> ~/.claude/logs/bash-commands.log
    ```

    **Why it is wrong** — A legitimate multiline Bash command produces unprefixed continuation lines, while a session ID containing an encoded newline can inject apparent records, making the log’s line structure and session attribution ambiguous.