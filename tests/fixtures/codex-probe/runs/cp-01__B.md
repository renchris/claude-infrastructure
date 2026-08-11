1. **What** — A valid JSON payload with a missing, null, false, or otherwise invalid `tool_input.command` is treated as successfully validated.

   **Where** — Line 40:

   ```bash
   if ! CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null); then
   ```

   **Why it is wrong** — For `{"tool_input":{}}`, `jq` succeeds and produces an empty string, so `abstain_unclear` is not called, every validation check sees an empty command, and the hook exits successfully without validating anything.

2. **What** — The supposedly non-silent abstention path can fail without leaving any signal.

   **Where** — Lines 33–37:

   ```bash
     mkdir -p "$HOME/.claude/logs" 2>/dev/null || true
     printf '%s\t%s\t%s\n' "$(date -u +%FT%TZ 2>/dev/null || echo '?')" \
       'validate-bash-ABSTAIN' "fail-open, command NOT validated: $1" \
       >> "$HOME/.claude/logs/validate-bash-unclear.log" 2>/dev/null || true
     exit 0
   ```

   **Why it is wrong** — If `$HOME` is unset, the directory is unwritable, or the filesystem is full, both failures are suppressed and the function exits 0 with no stdout, stderr, or audit record.

3. **What** — The helper is marked available without checking whether sourcing it succeeded or defined `is_true_flag`.

   **Where** — Lines 47 and 51–52:

   ```bash
   if [[ -f "$LIB_DIR/is-true-flag.sh" && "${VALIDATE_BASH_LEGACY:-0}" != "1" ]]; then
   ```

   ```bash
     source "$LIB_DIR/is-true-flag.sh"
     HAVE_IS_TRUE_FLAG=1
   ```

   **Why it is wrong** — If the file exists but is unreadable or returns before defining the function, later calls fail with status 127; that status is treated as “flag absent,” silently skipping every argv-aware flag prohibition.

4. **What** — The legacy flag matcher does not recognize real flag tokens adjacent to shell separators or quotes.

   **Where** — Lines 107–108:

   ```bash
       local pattern="(^|[[:space:]])${flag//./\\.}([[:space:]]|\$)"
       echo "$CMD" | grep -qE "$pattern"
   ```

   **Why it is wrong** — In legacy mode, `git commit --no-verify; echo done` and `git commit "--no-verify"` execute with a real `--no-verify` argument, but the following `;` or quote is neither whitespace nor end-of-string, so the prohibition is skipped.

5. **What** — The system-damage matcher fails to hard-deny several literal forms of the command classes it claims to cover.

   **Where** — Line 116:

   ```bash
   if echo "$CMD" | grep -qE '(rm[[:space:]]+-rf[[:space:]]+/[^a-zA-Z]|rm[[:space:]]+-rf[[:space:]]+\$HOME|rm[[:space:]]+-rf[[:space:]]+~(/|$|[[:space:]])|sudo[[:space:]]+rm|:\(\)\{[[:space:]]*:\|:&[[:space:]]*\};:)'; then
   ```

   **Why it is wrong** — Bare `rm -rf /` has no character after `/`, quoted `rm -rf "/"` does not place `/` immediately after whitespace, and `sudo -n rm file` does not place `rm` immediately after `sudo`; the first two fall through to an ask and the last can pass outright.

6. **What** — The system-damage matcher hard-denies inert textual mentions as though they were executable commands.

   **Where** — Line 116:

   ```bash
   if echo "$CMD" | grep -qE '(rm[[:space:]]+-rf[[:space:]]+/[^a-zA-Z]|rm[[:space:]]+-rf[[:space:]]+\$HOME|rm[[:space:]]+-rf[[:space:]]+~(/|$|[[:space:]])|sudo[[:space:]]+rm|:\(\)\{[[:space:]]*:\|:&[[:space:]]*\};:)'; then
   ```

   **Why it is wrong** — A command such as `git commit -m "document why sudo rm is forbidden"` is denied even though it executes no `sudo` or `rm`.

7. **What** — The broad-kill command-position test recognizes only bare `pkill` or `killall`, optionally preceded by bare `sudo`.

   **Where** — Lines 137–138:

   ```bash
   if printf '%s' "$CMD_NOQ" | sed 's/[&|()]/;/g' | tr ';' '\n' | sed 's/^[[:space:]]*//' \
        | grep -qE '^(sudo[[:space:]]+)?(pkill|killall)([[:space:]]|$)'; then
   ```

   **Why it is wrong** — Executable equivalents such as `/usr/bin/pkill -f bats`, `command pkill -f bats`, or `sudo -n pkill -f bats` do not match and therefore bypass the worktree-scoping guard.

8. **What** — Removing all quoted text from the command-position copy also removes quoted content that the shell executes.

   **Where** — Lines 136–138:

   ```bash
   CMD_NOQ=$(printf '%s' "$CMD" | sed -e "s/'[^']*'/''/g" -e 's/"[^"]*"/""/g')
   if printf '%s' "$CMD_NOQ" | sed 's/[&|()]/;/g' | tr ';' '\n' | sed 's/^[[:space:]]*//' \
        | grep -qE '^(sudo[[:space:]]+)?(pkill|killall)([[:space:]]|$)'; then
   ```

   **Why it is wrong** — `echo "$(pkill -f bats)"` executes the broad `pkill`, but the substitution is erased with the surrounding double-quoted text, leaving no command-position match.

9. **What** — Shell comments are included in the broad-kill target and scope analysis.

   **Where** — Lines 139, 143, and 147:

   ```bash
     PK_OCCURRENCES=$(echo "$CMD" | grep -oE '(pkill|killall)[^;&|]*' || true)
   ```

   ```bash
       echo "$pk" | grep -qE '(bats|ship-land|postland-verify)' || continue
   ```

   ```bash
       if echo "$pk" | grep -qE '\$PWD|\$\{PWD|\$\(pwd|`pwd|\$\(basename|(^|[[:space:]])-P[[:space:]]|\.worktrees/|(^|[^a-zA-Z0-9])wt-[a-zA-Z0-9]'; then
   ```

   **Why it is wrong** — `pkill -f bats # $PWD` executes a machine-wide kill but is accepted as scoped, while `pkill harmless # bats` can be denied as a gate-process kill even though `bats` is only a comment.

10. **What** — Merely containing a scope-looking token is treated as proof that the kill pattern is restricted to one worktree.

    **Where** — Lines 147 and 151:

    ```bash
       if echo "$pk" | grep -qE '\$PWD|\$\{PWD|\$\(pwd|`pwd|\$\(basename|(^|[[:space:]])-P[[:space:]]|\.worktrees/|(^|[^a-zA-Z0-9])wt-[a-zA-Z0-9]'; then
    ```

    ```bash
       if [[ -n "${PWD##*/}" ]] && echo "$pk" | grep -qF -- "${PWD##*/}"; then
    ```

    **Why it is wrong** — `pkill -P 1 -f bats` is accepted despite PID 1 not identifying one worktree, and a pattern such as `bats(.*/wt-one)?` is accepted even though the worktree-specific portion is optional and the pattern still matches every `bats` command.

11. **What** — The DDL “database-command context” test is only a pair of unrelated raw-text searches.

    **Where** — Lines 163–164:

    ```bash
   if echo "$CMD" | grep -qiE '\b(turso|sqlite3?|psql|mysql|mariadb|libsql|drizzle-kit[[:space:]]+(push|drop|migrate))\b' \
      && echo "$CMD" | grep -qiE '\b(DROP[[:space:]]+TABLE|DROP[[:space:]]+DATABASE|DROP[[:space:]]+INDEX|ALTER[[:space:]]+TABLE|CREATE[[:space:]]+TABLE|TRUNCATE[[:space:]]+TABLE)\b'; then
    ```

    **Why it is wrong** — `git commit -m "sqlite: reject DROP TABLE syntax"` satisfies both searches and is denied even though no database command executes any DDL.

12. **What** — The DDL detector covers only six literal two-word forms rather than all schema-changing DDL it claims to block.

    **Where** — Lines 163–164:

    ```bash
   if echo "$CMD" | grep -qiE '\b(turso|sqlite3?|psql|mysql|mariadb|libsql|drizzle-kit[[:space:]]+(push|drop|migrate))\b' \
      && echo "$CMD" | grep -qiE '\b(DROP[[:space:]]+TABLE|DROP[[:space:]]+DATABASE|DROP[[:space:]]+INDEX|ALTER[[:space:]]+TABLE|CREATE[[:space:]]+TABLE|TRUNCATE[[:space:]]+TABLE)\b'; then
    ```

    **Why it is wrong** — A real schema change such as `sqlite3 db.sqlite 'CREATE INDEX idx ON t(c)'` is not matched and is allowed.

13. **What** — The standalone `drizzle-kit push` prohibition triggers on inert text rather than an invocation.

    **Where** — Line 169:

    ```bash
   if echo "$CMD" | grep -qE 'drizzle-kit[[:space:]]+push'; then
    ```

    **Why it is wrong** — `git commit -m "ban drizzle-kit push"` is denied even though it does not run `drizzle-kit`.

14. **What** — The `git add` checks do not associate the detected force flag with the detected `git add` command.

    **Where** — Lines 174 and 177:

    ```bash
   if check_real_flag "--force" && echo "$CMD" | grep -qE 'git[[:space:]]+add\b'; then
    ```

    ```bash
   if check_real_flag "-f" && echo "$CMD" | grep -qE 'git[[:space:]]+add\b'; then
    ```

    **Why it is wrong** — In `rm -f old && git add new`, `-f` is a real argument in one command and `git add` occurs in another, yet the hook falsely reports and denies a force-add.

15. **What** — The `git add` context matcher misses valid invocations containing Git global options.

    **Where** — Lines 174 and 177:

    ```bash
   if check_real_flag "--force" && echo "$CMD" | grep -qE 'git[[:space:]]+add\b'; then
    ```

    ```bash
   if check_real_flag "-f" && echo "$CMD" | grep -qE 'git[[:space:]]+add\b'; then
    ```

    **Why it is wrong** — `git -C repo add -f ignored-file` performs a force-add, but the command contains no contiguous `git add`, so neither denial fires.

16. **What** — The `--no-verify` and `--no-gpg-sign` denials are not restricted to Git commands.

    **Where** — Lines 184 and 189:

    ```bash
   if check_real_flag "--no-verify"; then
    ```

    ```bash
   if check_real_flag "--no-gpg-sign"; then
    ```

    **Why it is wrong** — An unrelated active command such as `true --no-verify` or `true --no-gpg-sign` is denied as a Git-policy bypass even though no hook or signature policy is bypassed.

17. **What** — The `git commit -n` matcher does not distinguish an option from quoted message text or another non-option argument.

    **Where** — Line 196:

    ```bash
   if echo "$CMD" | grep -qE 'git([[:space:]]+-[a-zA-Z]+[[:space:]]+[^[:space:]]+)*[[:space:]]+commit\b[^|&;]*[[:space:]]-n\b'; then
    ```

    **Why it is wrong** — `git commit -m "document the -n option"` is falsely denied, while the shell-equivalent real option in `git commit "-n"` is missed because the hyphen is preceded by a quote rather than whitespace.

18. **What** — The `git reset --hard` check relies on one raw contiguous spelling instead of the executed Git argument structure.

    **Where** — Line 203:

    ```bash
   if echo "$CMD" | grep -qE 'git[[:space:]]+reset[[:space:]]+--hard\b'; then
    ```

    **Why it is wrong** — `git -C repo reset --hard` is not warned, while `git commit -m "discuss git reset --hard"` is warned even though it performs no reset.

19. **What** — The `git clean` check only recognizes an `x` or `X` in the first short-option bundle immediately following `git clean`.

    **Where** — Line 209:

    ```bash
   if echo "$CMD" | grep -qE 'git[[:space:]]+clean[[:space:]]+-[a-zA-Z]*[xX]'; then
    ```

    **Why it is wrong** — The valid destructive form `git clean -f -x` is not warned because `x` is in a later option token; the same raw matcher also warns inert text such as `git commit -m "avoid git clean -x"`.

20. **What** — The recursive-removal extractor recognizes only the exact bundles `-r`, `-rf`, and `-fr`.

    **Where** — Line 217:

    ```bash
   RM_OCCURRENCES=$(echo "$CMD" | grep -oE 'rm[[:space:]]+-(r|rf|fr)[[:space:]]+[^[:space:];&|]+' || true)
    ```

    **Why it is wrong** — A destructive equivalent such as `rm -rfv src` contains no matching occurrence and therefore passes without an ask.

21. **What** — The recursive-removal extractor examines only the first target operand of each `rm` command.

    **Where** — Line 217:

    ```bash
   RM_OCCURRENCES=$(echo "$CMD" | grep -oE 'rm[[:space:]]+-(r|rf|fr)[[:space:]]+[^[:space:];&|]+' || true)
    ```

    **Why it is wrong** — `rm -rf node_modules src` is recorded only as `rm -rf node_modules`; because that first target is whitelisted, the unsafe second target is deleted without an ask.

22. **What** — The safe-target test accepts paths lexically beginning with an allowed directory even when path traversal resolves outside it.

    **Where** — Lines 223–224:

    ```bash
       target_stripped=$(echo "$target" | sed -E 's|^\./||; s|^/||')
       if ! echo "$target_stripped" | grep -qE "^${SAFE_RM_TARGETS}(/|$)"; then
    ```

    **Why it is wrong** — With an existing `node_modules` directory, `rm -rf node_modules/../src` can delete `src`, but the lexical `node_modules/` prefix makes the guard classify it as safe.

23. **What** — The recursive-removal scanner treats quoted mentions as executable `rm` commands.

    **Where** — Lines 217 and 224:

    ```bash
   RM_OCCURRENCES=$(echo "$CMD" | grep -oE 'rm[[:space:]]+-(r|rf|fr)[[:space:]]+[^[:space:];&|]+' || true)
    ```

    ```bash
       if ! echo "$target_stripped" | grep -qE "^${SAFE_RM_TARGETS}(/|$)"; then
    ```

    **Why it is wrong** — `git commit -m "do not rm -rf src"` produces an occurrence whose target is non-safe and therefore prompts the user even though no removal executes.

24. **What** — The audit logger does not preserve one-record-per-line structure for multiline commands.

    **Where** — Line 243:

    ```bash
   echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [$SID] $CMD" >> ~/.claude/logs/bash-commands.log
    ```

    **Why it is wrong** — If `CMD` contains a newline, only its first line receives the timestamp and session prefix; subsequent lines remain indistinguishable from separate unprefixed log content, exactly the ambiguity the comments claim to eliminate.

25. **What** — Audit-log creation and writing failures are overwritten by an unconditional successful exit.

    **Where** — Lines 242–244:

    ```bash
   mkdir -p ~/.claude/logs
   echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [$SID] $CMD" >> ~/.claude/logs/bash-commands.log
   exit 0
    ```

    **Why it is wrong** — If the directory cannot be created or the log cannot be written, the final `exit 0` still reports success even though the command was not recorded for audit.