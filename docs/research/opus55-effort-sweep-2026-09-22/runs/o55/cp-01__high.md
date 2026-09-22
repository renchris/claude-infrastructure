# Review of `hooks/validate-bash.sh`

I found 16 defects, listed in line order.

---

### 1. An empty or missing command is never flagged as unvalidated

- **Where:** lines 39–41
  ```
  if ! CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null); then
  ```
- **Why it is wrong:** The guard only catches a non-zero exit from jq. Two inputs slip through:
  - Empty stdin: jq exits 0 and prints nothing.
  - Valid JSON without `.tool_input.command` (for example, a renamed field): `// empty` makes jq exit 0.

  In both cases `CMD` is empty, every pattern misses, and the hook exits 0 with no ABSTAIN line. This is exactly the "CMD went empty, the validator silently disabled itself" failure the block says it prevents.

### 2. `rm -rf /` at the end of the command is not hard-denied

- **Where:** line 115
  ```
  if echo "$CMD" | grep -qE '(rm[[:space:]]+-rf[[:space:]]+/[^a-zA-Z]|rm[[:space:]]+-rf[[:space:]]+\$HOME|rm[[:space:]]+-rf[[:space:]]+~(/|$|[[:space:]])|sudo[[:space:]]+rm|:\(\)\{[[:space:]]*:\|:&[[:space:]]*\};:)'; then
  ```
- **Why it is wrong:** `/[^a-zA-Z]` needs one more character after the `/`.
  - The literal command `rm -rf /`, with nothing after the slash, does not match.
  - Nor do variants the pattern doesn't cover: `rm -fr /`, `rm -Rf /`, `rm -rf "$HOME"`, `rm -rf ${HOME}`.

  These fall through to the rm-occurrence block (line 223) and get only an "ask" instead of the claimed hard deny.

### 3. The pkill command-position test misses common command positions

- **Where:** lines 135–136
  ```
  if printf '%s' "$CMD_NOQ" | sed 's/[&|()]/;/g' | tr ';' '\n' | sed 's/^[[:space:]]*//' \
       | grep -qE '^(sudo[[:space:]]+)?(pkill|killall)([[:space:]]|$)'; then
  ```
- **Why it is wrong:** Only a clause *starting* with `pkill`/`killall` (optionally after `sudo`) counts. The whole check is skipped and the machine-wide kill runs for:
  - `if pkill -f bats; then …`
  - `for …; do pkill -9 -f bats-core/bats; done`
  - `{ pkill -f bats; }`
  - `! pkill …`
  - `timeout 5 pkill -f bats`, `env pkill …`, `nohup pkill …`

### 4. Quote stripping works per line, so multi-line message bodies count as command position

- **Where:** line 134
  ```
  CMD_NOQ=$(printf '%s' "$CMD" | sed -e "s/'[^']*'/''/g" -e 's/"[^"]*"/""/g')
  ```
- **Why it is wrong:** `sed` works one line at a time, so a quoted string that spans lines is never stripped. Example:
  ```
  git commit -m "fix
  pkill bats is gone"
  ```
  Line 2 then starts with `pkill` and passes the position test. The target test finds `bats` and the commit is denied. This is the "merely MENTIONS" false positive the clause says it avoids.

### 5. Target and scope tests run on every textual occurrence, including quoted mentions

- **Where:** line 137
  ```
  PK_OCCURRENCES=$(echo "$CMD" | grep -oE '(pkill|killall)[^;&|]*' || true)
  ```
- **Why it is wrong:** Once any real `pkill` is in command position, every occurrence in the raw `CMD` is checked, including ones inside quoted message bodies. Example:
  ```
  pkill node; git commit -m "stop using pkill bats"
  ```
  This is denied because of the message text, not the actual kill.

### 6. The "names this worktree" exemption is a raw substring match on the cwd basename

- **Where:** line 149
  ```
      if [[ -n "${PWD##*/}" ]] && echo "$pk" | grep -qF -- "${PWD##*/}"; then
  ```
- **Why it is wrong:** If the session's directory basename happens to occur in an unscoped pattern, the pattern is treated as scoped and allowed. Examples:
  - cwd `…/tests` with `pkill -f "bats tests/"` (the comment's own example of a real broad pattern).
  - cwd `…/main` with `pkill -f "ship-land.sh --trunk main"`.

  Either way, every session's gates are killed.

### 7. The DDL "context" test is two independent substring tests, so commit messages still trigger it

- **Where:** lines 161–162
  ```
  if echo "$CMD" | grep -qiE '\b(turso|sqlite3?|psql|mysql|mariadb|libsql|drizzle-kit[[:space:]]+(push|drop|migrate))\b' \
     && echo "$CMD" | grep -qiE '\b(DROP[[:space:]]+TABLE|DROP[[:space:]]+DATABASE|DROP[[:space:]]+INDEX|ALTER[[:space:]]+TABLE|CREATE[[:space:]]+TABLE|TRUNCATE[[:space:]]+TABLE)\b'; then
  ```
- **Why it is wrong:**
  - **False positive:** `git commit -m "fix: block DROP TABLE via sqlite3"` is denied, contrary to the stated goal of not blocking commit messages that discuss DDL.
  - **Missed DDL:** The "any mechanism" clause misses `CREATE INDEX`, `DROP VIEW`, `DROP SCHEMA` (MySQL's synonym for `DROP DATABASE`), and `DROP TRIGGER` passed to `sqlite3`/`psql`.

### 8. The `git add -f/--force` checks don't tie the flag to the `git add` clause

- **Where:** lines 172 and 175
  ```
  if check_real_flag "--force" && echo "$CMD" | grep -qE 'git[[:space:]]+add\b'; then
  ```
  ```
  if check_real_flag "-f" && echo "$CMD" | grep -qE 'git[[:space:]]+add\b'; then
  ```
- **Why it is wrong:** Any `-f`/`--force` anywhere in the command plus any `git add` anywhere triggers the deny. Examples:
  - `git add . && rm -f tmp.txt`
  - `git add x && git push --force-with-lease=… -f`

  Both are denied with the false reason "git add -f blocked".

### 9. `git add`, `git reset`, and `git clean` checks miss git global options before the subcommand

- **Where:** lines 172/175, 201, 207
  ```
  echo "$CMD" | grep -qE 'git[[:space:]]+add\b'
  ```
  ```
  if echo "$CMD" | grep -qE 'git[[:space:]]+reset[[:space:]]+--hard\b'; then
  ```
  ```
  if echo "$CMD" | grep -qE 'git[[:space:]]+clean[[:space:]]+-[a-zA-Z]*[xX]'; then
  ```
- **Why it is wrong:** These require `git` to be followed directly by the subcommand. The following bypass all three guards:
  - `git -C . add -f .env`
  - `git -C repo reset --hard`
  - `git -c x=y clean -fdx`

  The `commit -n` regex at line 194 does allow for global options, so the gap is inconsistent.

### 10. Abbreviated long options bypass the `--no-verify` / `--no-gpg-sign` token match

- **Where:** lines 182 and 187
  ```
  if check_real_flag "--no-verify"; then
  ```
  ```
  if check_real_flag "--no-gpg-sign"; then
  ```
- **Why it is wrong:** git's option parser accepts unique prefixes of long options. `git commit --no-verif -m x` or `git commit --no-gpg -m x` skips hooks or signing, and neither token equals the exact flag string being searched for.

### 11. The `git commit -n` regex misses bundled short flags

- **Where:** line 194
  ```
  if echo "$CMD" | grep -qE 'git([[:space:]]+-[a-zA-Z]+[[:space:]]+[^[:space:]]+)*[[:space:]]+commit\b[^|&;]*[[:space:]]-n\b'; then
  ```
- **Why it is wrong:** `[[:space:]]-n\b` needs `-n` as its own token. Neither of these matches, yet both skip pre-commit hooks:
  - `git commit -an -m x` (`n` is not right after the space-dash)
  - `git commit -nm "x"` (no word boundary between `n` and `m`)

### 12. The same `-n` regex fires on message bodies

- **Where:** line 194 (same line as #11)
- **Why it is wrong:** `[^|&;]*` runs across quoted text. `git commit -m "fix head -n parsing"` contains ` -n` after `commit` and is denied as a `--no-verify` bypass. The comment says only head position matters, but quoted bodies are not excluded.

### 13. The `git reset --hard` warning only fires when `--hard` is the first argument

- **Where:** line 201
  ```
  if echo "$CMD" | grep -qE 'git[[:space:]]+reset[[:space:]]+--hard\b'; then
  ```
- **Why it is wrong:** `git reset -q --hard HEAD~1` or `git reset --quiet --hard` destroys work with no warning.

### 14. The `git clean` check only inspects the first flag bundle

- **Where:** line 207
  ```
  if echo "$CMD" | grep -qE 'git[[:space:]]+clean[[:space:]]+-[a-zA-Z]*[xX]'; then
  ```
- **Why it is wrong:** The pattern ends at the first non-letter after `clean -`. `git clean -f -x` and `git clean -fd -X` don't match, so gitignored assets are removed with no warning. This contradicts "Match any flag bundle containing x".

### 15. The rm-rf allowlist checks only the first target and allows path traversal

- **Where:** lines 215 and 222
  ```
  RM_OCCURRENCES=$(echo "$CMD" | grep -oE 'rm[[:space:]]+-(r|rf|fr)[[:space:]]+[^[:space:];&|]+' || true)
  ```
  ```
      if ! echo "$target_stripped" | grep -qE "^${SAFE_RM_TARGETS}(/|$)"; then
  ```
- **Why it is wrong:**
  - **Only the first target is checked.** `rm -rf node_modules src` checks only `node_modules` and silently deletes `src`. This is the same escape hatch the comment says was closed, just within one clause.
  - **Traversal passes the allowlist.** `rm -rf dist/../src` or `rm -rf node_modules/../..` passes because the target starts with a safe name followed by `/`.
  - **Other flag spellings are never inspected.** `-Rf`, `-rfv`, `--recursive --force`, and `-fR` produce no occurrence at all.

### 16. Denied and asked commands are never written to the audit log

- **Where:** lines 76 / 89 (`exit 0` inside `deny`/`warn`) versus line 241
  ```
  echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [$SID] $CMD" >> ~/.claude/logs/bash-commands.log
  ```
- **Why it is wrong:** `deny()` and `warn()` exit before the logging line. Any command that hits a warn, which the user then approves and which does execute (`git reset --hard`, `rm -rf src`, `git clean -x`), is missing from the audit log. Those are the riskiest commands that actually run. Denied attempts are also unrecorded.
