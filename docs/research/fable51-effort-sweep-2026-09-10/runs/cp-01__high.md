Reviewing `hooks/validate-bash.sh` from the brief text only. Findings below, ordered roughly by severity.

**1. `rm -rf /` with nothing after it is only "ask", not "deny".**
- Where: line 116 `if echo "$CMD" | grep -qE '(rm[[:space:]]+-rf[[:space:]]+/[^a-zA-Z]|rm[[:space:]]+-rf[[:space:]]+\$HOME|rm[[:space:]]+-rf[[:space:]]+~(/|$|[[:space:]])|sudo[[:space:]]+rm|:\(\)\{[[:space:]]*:\|:&[[:space:]]*\};:)'; then`
- Why: the first alternative requires a character after the slash. A command that is exactly `rm -rf /` has none, so the deny does not fire. It then reaches line 217, where the target `/` is stripped to an empty string at line 223, fails the safe-target match at line 224, and produces a `warn` (permission "ask"). The same downgrade from deny to ask happens for `rm -fr /`, `rm -fr ~`, `rm -rf "$HOME"`, and `rm -r -f /`, because this regex only recognises the literal spelling `-rf` and an unquoted `$HOME`, while the rm clause at line 217 explicitly accepts `-fr` as an equivalent. The deny message claims to cover "rm -rf /, rm -rf ~".

**2. Only the first target of an `rm -rf` clause is inspected.**
- Where: line 217 `RM_OCCURRENCES=$(echo "$CMD" | grep -oE 'rm[[:space:]]+-(r|rf|fr)[[:space:]]+[^[:space:];&|]+' || true)`
- Why: the capture stops at the first whitespace, so `rm -rf node_modules src` yields the occurrence `rm -rf node_modules`. That target is safe, no warn is emitted, and `src` is deleted without a prompt. The comment says the per-occurrence loop closes the compound-command escape hatch, but a multi-target single clause is the same hatch.

**3. A safe target followed by `/..` is treated as safe.**
- Where: line 224 `if ! echo "$target_stripped" | grep -qE "^${SAFE_RM_TARGETS}(/|$)"; then`
- Why: `(/|$)` anchors only the prefix. `rm -rf dist/../src` or `rm -rf node_modules/../..` matches `^dist/` or `^node_modules/`, is classified as a build-artifact removal, and passes silently while deleting the parent tree.

**4. `git clean -x` warn only sees the first flag bundle.**
- Where: line 209 `if echo "$CMD" | grep -qE 'git[[:space:]]+clean[[:space:]]+-[a-zA-Z]*[xX]'; then`
- Why: the regex requires the bundle immediately after `clean` to contain `x`/`X`. `git clean -fd -x`, `git clean -f -d -X`, and `git clean --force -x` do not match, so gitignored files are removed with no "ask". The comment claims "any flag bundle".

**5. Bundled `-n` bypasses the `git commit -n` deny.**
- Where: line 196 `if echo "$CMD" | grep -qE 'git([[:space:]]+-[a-zA-Z]+[[:space:]]+[^[:space:]]+)*[[:space:]]+commit\b[^|&;]*[[:space:]]-n\b'; then`
- Why: the pattern needs `-n` as a standalone token. `git commit -anm "msg"` and `git commit -an -m "msg"` skip pre-commit hooks exactly like `--no-verify` and are not matched. The same regex also misses `git --no-pager commit -n`, because the intermediate-option group only accepts single-dash options.

**6. `-n` inside a quoted commit message is denied.**
- Where: line 196 (same line as above)
- Why: `[^|&;]*` runs across quotes, so `git commit -m "fix: sed -n usage"` matches and is denied as a hook bypass. The file header claims bypass-flag detection is aware of quoted message bodies, and the `--no-verify` clause is, but this clause decides on raw text.

**7. The `git add` force checks are not tied to the `git add` invocation.**
- Where: line 174 `if check_real_flag "--force" && echo "$CMD" | grep -qE 'git[[:space:]]+add\b'; then` and line 177 `if check_real_flag "-f" && echo "$CMD" | grep -qE 'git[[:space:]]+add\b'; then`
- Why: the two conditions are evaluated independently over the whole command. `git add . && git push --force` is denied with the reason "git add --force blocked", and `git add . && rm -f tmp.txt` is denied as "git add -f". Neither command force-adds anything.

**8. Bundled short flags bypass the `git add -f` deny.**
- Where: line 107 `local pattern="(^|[[:space:]])${flag//./\\.}([[:space:]]|\$)"`
- Why: `git add -Af .` and `git add -fA .` force-add ignored files, but `-Af` is not the token `-f`. The legacy regex requires `-f` bracketed by whitespace, and the argv-aware path at line 99 is by its own description a token match, so neither branch of `check_real_flag` fires.

**9. The pkill loop decides on raw text once any pkill is in command position.**
- Where: line 139 `PK_OCCURRENCES=$(echo "$CMD" | grep -oE '(pkill|killall)[^;&|]*' || true)` through line 154
- Why: the position test on line 137 correctly uses the quote-stripped copy, but the occurrence loop extracts every `pkill` substring from the original text. With `pkill -f "worker-${PWD##*/}"; git commit -m "chore: remove pkill -f bats helper"`, the first occurrence is scoped and skipped, the second is the text inside the commit message, it names `bats`, has no scope marker, and the whole command is denied. The block's own comment calls deciding on raw text "the exact defect this clause exists to stop".

**10. The command-position test only recognises a bare `pkill`/`killall` head.**
- Where: line 138 `| grep -qE '^(sudo[[:space:]]+)?(pkill|killall)([[:space:]]|$)'; then`
- Why: `/usr/bin/pkill -9 -f bats-core/bats`, `command pkill -f bats`, `exec pkill -f bats`, `sudo -n pkill -f bats`, and `FOO=1 pkill -f bats` all kill the same machine-wide processes but do not match the anchored head, so the deny never runs and the command is allowed.

**11. The "names this worktree" scope check is a substring match on the directory basename.**
- Where: line 151 `if [[ -n "${PWD##*/}" ]] && echo "$pk" | grep -qF -- "${PWD##*/}"; then`
- Why: if the session's cwd basename is a short or common word, any kill passes as scoped. With a checkout at `.../main`, the exact epidemic pattern quoted at line 124, `pkill -f "ship-land.sh --trunk main"`, contains `main` and is allowed. With a basename such as `a` or `t`, `pkill -9 -f bats` passes too.

**12. DDL check denies commands that merely mention a database tool and a keyword.**
- Where: lines 163 to 164 `if echo "$CMD" | grep -qiE '\b(turso|sqlite3?|psql|mysql|mariadb|libsql|drizzle-kit[[:space:]]+(push|drop|migrate))\b' \` / `&& echo "$CMD" | grep -qiE '\b(DROP[[:space:]]+TABLE|DROP[[:space:]]+DATABASE|DROP[[:space:]]+INDEX|ALTER[[:space:]]+TABLE|CREATE[[:space:]]+TABLE|TRUNCATE[[:space:]]+TABLE)\b'; then`
- Why: both greps are case-insensitive substring searches over the whole command, not a database-command context. `grep -rn "CREATE TABLE" src/db/sqlite.ts` and `git commit -m "fix: sqlite3 CREATE TABLE ordering"` are denied as DDL. The comment states commit messages discussing DDL are not false positives.

**13. The DDL keyword list does not cover the class the deny message claims.**
- Where: line 164 (same line as above) and line 165 `deny "DDL blocked — all schema changes must go through Drizzle migrations (pnpm generate). See CLAUDE.md critical rule #1."`
- Why: `sqlite3 app.db "CREATE INDEX idx ON t(c)"`, `DROP VIEW`, `CREATE VIEW`, `DROP TRIGGER`, and `ALTER INDEX` are schema changes that pass untouched, while the reason text asserts all schema changes are blocked.

**14. A payload with no command field is treated as a validated empty command, not an abstain.**
- Where: line 40 `if ! CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null); then`
- Why: `// empty` maps a missing or null field to an empty string with jq exit 0, and jq also exits 0 on empty stdin. A schema change, a field under a different key, or an empty payload therefore skips every pattern, writes nothing to the abstain log, and exits 0. That is the silent self-disable the comment block at lines 21 to 31 says this guard was added to prevent. Only a syntactically invalid JSON body reaches the abstain path.

**15. Abbreviated long options bypass the `--no-verify` and `--no-gpg-sign` denies.**
- Where: line 184 `if check_real_flag "--no-verify"; then` and line 189 `if check_real_flag "--no-gpg-sign"; then`
- Why: both checks look for the exact token. Git accepts any unambiguous prefix of a long option, so `git commit --no-verif -m x` and `git commit --no-gpg -m x` skip hooks and signing respectively but match neither the argv-aware nor the legacy regex path.
