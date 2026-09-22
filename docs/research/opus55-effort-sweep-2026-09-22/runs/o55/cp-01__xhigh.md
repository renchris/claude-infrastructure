# Review: `hooks/validate-bash.sh`

I found 20 defects, ordered roughly by severity.

---

### 1. `rm` flag variants other than `-rf`, `-fr` and `-r` escape both the hard deny and the warn

**Where:** lines 115 and 215
```
if echo "$CMD" | grep -qE '(rm[[:space:]]+-rf[[:space:]]+/[^a-zA-Z]|rm[[:space:]]+-rf[[:space:]]+\$HOME|rm[[:space:]]+-rf[[:space:]]+~(/|$|[[:space:]])|sudo[[:space:]]+rm|:\(\)\{[[:space:]]*:\|:&[[:space:]]*\};:)'; then
```
```
RM_OCCURRENCES=$(echo "$CMD" | grep -oE 'rm[[:space:]]+-(r|rf|fr)[[:space:]]+[^[:space:];&|]+' || true)
```
**Why:** Both regexes are case-sensitive and require the flag bundle to be exactly `-rf`, `-fr` or `-r`, followed by whitespace.
- `rm -Rf ~`, `rm -Rf /*`, `rm -rfv src`, `rm -r -f ~`, `rm -f -r /*` and `rm --recursive --force ~` match neither regex.
- These commands therefore get no deny and no ask, and the hook exits 0 (allowed).

### 2. Only the first `rm -rf` target is inspected, so a safe first target hides every later one

**Where:** line 215 (same line as above), and line 115
**Why:** `[^[:space:];&|]+` captures one argument only. The hard deny also requires `/` or `~` to appear immediately after `-rf `.
- `rm -rf dist ~/` and `rm -rf node_modules /*` are not hard-denied.
- The single captured occurrence (`dist` or `node_modules`) is on the safe list, so no warn fires either.
- The command is allowed silently. This is the same compound escape hatch the comment at lines 211–213 claims to close, moved from clause level to argument level.

### 3. Bare `rm -rf /` is not hard-denied

**Where:** line 115 (quoted above)
**Why:** `/[^a-zA-Z]` needs one more character after the slash.
- When the command is exactly `rm -rf /` (or `/` is the last character on the line), nothing follows it, so the deny misses.
- The command falls through to the rm warn and becomes an "ask", even though the deny message names `rm -rf /` as blocked.

### 4. The safe-target check accepts path traversal and absolute paths

**Where:** lines 221–222
```
    target_stripped=$(echo "$target" | sed -E 's|^\./||; s|^/||')
```
```
    if ! echo "$target_stripped" | grep -qE "^${SAFE_RM_TARGETS}(/|$)"; then
```
**Why:** The check is a prefix match only.
- `rm -rf node_modules/../..` and `rm -rf dist/../src` match `^node_modules/` and `^dist/`, so they count as safe and run with no ask.
- The leading `/` is stripped, so absolute paths like `rm -rf /build` or `rm -rf /target` are also treated as repo build artifacts.

### 5. Quote stripping processes single quotes before double quotes, so an apostrophe can hide a real `pkill`

**Where:** line 134
```
CMD_NOQ=$(printf '%s' "$CMD" | sed -e "s/'[^']*'/''/g" -e 's/"[^"]*"/""/g')
```
**Why:** An apostrophe inside a double-quoted string gets paired with a later single quote.
- Input: `git commit -m "don't wait" && pkill -f bats && echo 'done'`.
- The first substitution swallows `'t wait" && pkill -f bats && echo '` and leaves `git commit -m "don''done'`.
- The position test never sees the unscoped `pkill`, and the command is allowed.

### 6. The command-position test only recognises `pkill`/`killall` at clause start or right after `sudo`

**Where:** line 136
```
     | grep -qE '^(sudo[[:space:]]+)?(pkill|killall)([[:space:]]|$)'; then
```
**Why:** Any prefix or wrapper defeats the test, and the whole clause is then skipped. Examples that run an unscoped machine-wide gate kill with no decision:
- Prefixes and wrappers: `timeout 5 pkill -f bats`, `xargs pkill`, `env pkill`, `nohup pkill`, `command pkill`.
- A full path: `/usr/bin/pkill -f bats`.
- Shell keywords: `if pkill …`, `then pkill …`, `do pkill …`, `! pkill …`, `{ pkill …; }`.
- Backtick substitution.

### 7. Occurrence extraction stops at `|`, which hides gate names placed after a regex alternation

**Where:** lines 137 and 141
```
  PK_OCCURRENCES=$(echo "$CMD" | grep -oE '(pkill|killall)[^;&|]*' || true)
```
```
    echo "$pk" | grep -qE '(bats|ship-land|postland-verify)' || continue
```
**Why:** `pkill` patterns are regexes, and `|` inside a quoted pattern is alternation, not a pipe.
- For `pkill -f 'node|bats'`, the occurrence is cut to `pkill -f 'node`.
- The gate-name test fails, the loop hits `continue`, and every bats process on the machine is killed with no deny.

### 8. The "scoped to ONE worktree" test accepts text that does not scope to one worktree

**Where:** lines 145 and 149
```
    if echo "$pk" | grep -qE '\$PWD|\$\{PWD|\$\(pwd|`pwd|\$\(basename|(^|[[:space:]])-P[[:space:]]|\.worktrees/|(^|[^a-zA-Z0-9])wt-[a-zA-Z0-9]'; then
```
```
    if [[ -n "${PWD##*/}" ]] && echo "$pk" | grep -qF -- "${PWD##*/}"; then
```
**Why:** Each of these is accepted as scoped but still kills peers' gates:
- **Bare `.worktrees/`:** `pkill -f ".worktrees/.*bats"` counts as scoped, but under always-worktree isolation it matches every session's worktree.
- **`-P` with any pid:** `-P 1` counts as scoped.
- **Basename substring:** the check only needs the cwd basename to appear anywhere in the text.
  - From the main checkout `myapp`, `pkill -f "myapp.*bats"` matches all `myapp/.worktrees/*` gates.
  - A short basename such as `core` matches `bats-core/bats`.

### 9. The position test and the target test read different text, so a quoted mention can cause a deny

**Where:** lines 136–137 (quoted above)
**Why:** The position test runs on the quote-stripped copy, but occurrences are pulled from the raw text.
- Input: `pkill -f my-dev-server && git commit -m "fix: never pkill bats"`.
- The unrelated real `pkill` passes the position gate.
- The `pkill bats"` inside the commit message is then extracted and denied.
- This is the exact message-body false positive the comment at lines 129–133 says the clause prevents.

### 10. The `git add -f/--force` denies fire when the flag belongs to a different command

**Where:** lines 172 and 175
```
if check_real_flag "--force" && echo "$CMD" | grep -qE 'git[[:space:]]+add\b'; then
```
```
if check_real_flag "-f" && echo "$CMD" | grep -qE 'git[[:space:]]+add\b'; then
```
**Why:** The flag test and the `git add` test are evaluated independently over the whole command.
- `rm -f out.log && git add .` is denied as "git add -f".
- `git add . && git push --force` is denied as "git add --force".

### 11. The `git add` pattern misses git global options, so `git add -f` gets through

**Where:** lines 172 and 175 (quoted above)
**Why:** `git[[:space:]]+add\b` requires `add` to follow `git` directly. `git -C . add -f .env` does not match, so the gitignore bypass the clause exists to block is allowed.

### 12. The `git commit -n` check misses bundled short flags and flag-only global options

**Where:** line 194
```
if echo "$CMD" | grep -qE 'git([[:space:]]+-[a-zA-Z]+[[:space:]]+[^[:space:]]+)*[[:space:]]+commit\b[^|&;]*[[:space:]]-n\b'; then
```
**Why:** Each of these skips the pre-commit hook and is allowed:
- **Bundled flags:** in `-nm` and `-an`, `-n` is followed by a word character, so `\b` fails. Examples: `git commit -nm "wip"`, `git commit -an -m x`.
- **Global options with no argument:** `git --no-pager commit -n` and `git -p commit -n` fail the prefix group.
- **Argument containing a space:** `git -C "my dir" commit -n` also fails the prefix group.

### 13. The `git commit -n` check matches `-n` inside a quoted message

**Where:** line 194 (quoted above)
**Why:** `[^|&;]*` runs through quoted message bodies. `git commit -m "fix head -n handling"` is denied as a `--no-verify` bypass even though no `-n` flag was passed to git.

### 14. `--no-verify` and `--no-gpg-sign` are only matched as exact tokens, but git accepts unique-prefix abbreviations

**Where:** lines 182 and 187
```
if check_real_flag "--no-verify"; then
```
```
if check_real_flag "--no-gpg-sign"; then
```
**Why:** Git's parse-options accepts any unique prefix of a long option. `git commit --no-veri` and `git commit --no-gpg` apply the bypass, but they are not the exact token checked, so they are allowed.

### 15. The `git clean -x` warn only inspects the first flag bundle

**Where:** line 207
```
if echo "$CMD" | grep -qE 'git[[:space:]]+clean[[:space:]]+-[a-zA-Z]*[xX]'; then
```
**Why:** `git clean -f -x`, `git clean -fd -X` and `git clean --force -x` put the `x` in a later argument. The regex fails on the space, and gitignored assets are deleted with no ask. The comment at line 206 says "any flag bundle".

### 16. The `git reset --hard` warn requires `--hard` directly after `reset`

**Where:** line 201
```
if echo "$CMD" | grep -qE 'git[[:space:]]+reset[[:space:]]+--hard\b'; then
```
**Why:** Each of these destroys uncommitted work with no ask:
- `git reset HEAD~1 --hard`
- `git reset -q --hard`
- `git -C . reset --hard`

### 17. A failing or missing `is_true_flag` is treated as "not a flag" instead of fail-safe

**Where:** lines 50–51 and 101–102
```
  source "$LIB_DIR/is-true-flag.sh"
```
```
  HAVE_IS_TRUE_FLAG=1
```
```
    [[ "$rc" == "0" || "$rc" == "2" ]] && return 0
```
```
    return 1
```
**Why:** `HAVE_IS_TRUE_FLAG=1` is set because the file exists, whether or not sourcing succeeded or defined the function.
- If the lib fails to load, is unreadable, or crashes, `is_true_flag` returns 127, 126 or another code.
- Every return code other than 0 or 2 maps to "substring only".
- The `--no-verify`, `--no-gpg-sign` and `-f/--force` denies then silently pass.
- The comment at line 44 promises a per-call fallback, but none exists.

### 18. An empty `CMD` still passes silently, which is the failure mode the jq guard claims to eliminate

**Where:** line 39
```
if ! CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null); then
```
**Why:** The guard only checks jq's exit status.
- Empty or whitespace-only stdin makes jq exit 0 with no output.
- A valid payload whose command lives under a different key yields empty output through `// empty`.
- In both cases `CMD` is empty, every pattern misses, the hook exits 0, and nothing is written to `validate-bash-unclear.log`. Lines 24–27 describe exactly this as the defect being fixed.

### 19. The audit log never records denied or asked commands

**Where:** lines 76, 89 and 241
```
  exit 0
```
```
  exit 0
```
```
echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [$SID] $CMD" >> ~/.claude/logs/bash-commands.log
```
**Why:** `deny()` and `warn()` both exit before the logging line.
- Commands that get an "ask" and are then approved by the user run but never appear in `bash-commands.log`.
- These are the most audit-relevant commands.

### 20. The DDL clause's "database context" is just word co-occurrence, and it misses schema changes outside its list

**Where:** lines 161–162
```
if echo "$CMD" | grep -qiE '\b(turso|sqlite3?|psql|mysql|mariadb|libsql|drizzle-kit[[:space:]]+(push|drop|migrate))\b' \
```
```
   && echo "$CMD" | grep -qiE '\b(DROP[[:space:]]+TABLE|DROP[[:space:]]+DATABASE|DROP[[:space:]]+INDEX|ALTER[[:space:]]+TABLE|CREATE[[:space:]]+TABLE|TRUNCATE[[:space:]]+TABLE)\b'; then
```
**Why:** The clause is wrong in both directions:
- **False positive:** `git commit -m "fix: stop sqlite3 from running DROP TABLE"` is denied, even though lines 157–158 claim commit messages that discuss DDL are exempt.
- **Missed schema changes:** `sqlite3 app.db "CREATE INDEX …"` (while `DROP INDEX` is in the list) and `DROP VIEW`, `CREATE VIEW` and `CREATE/DROP TRIGGER` are allowed. The deny message says "all schema changes must go through Drizzle migrations".

### 21. Other hard denies are over-broad: they match raw message text and subpaths

**Where:** lines 115 (quoted above) and 167
```
if echo "$CMD" | grep -qE 'drizzle-kit[[:space:]]+push'; then
```
**Why:** Each of these is hard-denied with a message describing something the command does not do:
- **Message text:** `git commit -m "docs: never run drizzle-kit push"` and `git commit -m "guard: block sudo rm"` match on raw text.
- **Home subpaths:** the `~(/…)` and `\$HOME` alternatives match any subpath, so `rm -rf ~/tmp/scratch` and `rm -rf $HOME/.cache/x` are denied as "rm -rf ~". For `/`, by contrast, subpaths are deliberately excluded.
- **Other `rm*` commands:** `sudo[[:space:]]+rm` also matches `sudo rmdir`.
