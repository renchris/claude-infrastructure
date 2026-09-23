# Review of `hooks/validate-bash.sh`

I found 17 defects. Most are guards that miss inputs they claim to cover. A few fire when they shouldn't.

---

### 1. Bare `rm -rf /` is not hard-denied

- **What:** The system-damage deny needs a character after the `/`, so the literal `rm -rf /` does not match.
- **Where:** line 115
  ```bash
  if echo "$CMD" | grep -qE '(rm[[:space:]]+-rf[[:space:]]+/[^a-zA-Z]|rm[[:space:]]+-rf[[:space:]]+\$HOME|rm[[:space:]]+-rf[[:space:]]+~(/|$|[[:space:]])|sudo[[:space:]]+rm|:\(\)\{[[:space:]]*:\|:&[[:space:]]*\};:)'; then
  ```
- **Why:** In `/[^a-zA-Z]`, the bracket must consume one character. When `/` ends the command (`rm -rf /`) or is followed by `;` inside a larger command, nothing matches. The command falls through to the rm-warn block and becomes an "ask" instead of the deny the message promises.

### 2. The system-damage deny misses common spellings of the same commands

- **What:** Only the exact spelling `-rf` with an unquoted `$HOME` or `/` is recognized.
- **Where:** line 115 (same line as above)
- **Why:** None of these match, so each is downgraded to an ask or passes:
  - `rm -fr /`, `rm -Rf /`, `rm -r -f /`, `rm --recursive --force /`
  - `rm -rf "$HOME"` or `rm -rf ${HOME}` (a quote or brace sits between the space and `$HOME`)
  - `:() { :|:& };:` (space before `{`)

### 3. The system-damage deny fires on any path under the home directory

- **What:** The same deny matches any path inside `~` or `$HOME`, not just the home directory itself.
- **Where:** line 115 (same line)
- **Why:**
  - `~(/|$|[[:space:]])` matches `~/`, so `rm -rf ~/project/node_modules` is hard-denied as "rm -rf ~".
  - `\$HOME` has no right boundary, so `rm -rf $HOME/tmp/x` and `rm -rf $HOMEBREW_CACHE` are also hard-denied as system damage.

### 4. The rm-warn only checks the first target

- **What:** The warn claims to close the compound-command escape hatch, but it inspects only the first target after `rm -rf`.
- **Where:** line 216
  ```bash
  RM_OCCURRENCES=$(echo "$CMD" | grep -oE 'rm[[:space:]]+-(r|rf|fr)[[:space:]]+[^[:space:];&|]+' || true)
  ```
- **Why:** `[^[:space:];&|]+` stops at the first space. `rm -rf node_modules src ~/work` extracts only `node_modules`, which is on the safe list. No warn is issued, and `src` and `~/work` are deleted without asking.

### 5. The rm-warn misses other recursive flag spellings

- **What:** The occurrence regex only knows `-r`, `-rf`, and `-fr`.
- **Where:** line 216 (same line)
- **Why:** `rm -Rf src`, `rm -rfv src`, `rm -rf -v src`→(target `-v`, warns, fine), but `rm --recursive --force src` and `rm -fR src` produce no occurrence at all. No warn is issued.

### 6. The safe-target check can be escaped with `..` and a leading `/`

- **What:** The safe-target test is a prefix match on an unnormalized path, and leading `/` is stripped before the test.
- **Where:** lines 222–223
  ```bash
      target_stripped=$(echo "$target" | sed -E 's|^\./||; s|^/||')
      if ! echo "$target_stripped" | grep -qE "^${SAFE_RM_TARGETS}(/|$)"; then
  ```
- **Why:**
  - `rm -rf node_modules/../src` and `rm -rf build/../..` match `^node_modules/` or `^build/` and are treated as safe, so the real parent directories are deleted without a warn.
  - `rm -rf /build` or `rm -rf /target` has its leading `/` stripped, so an absolute root-level directory is classified as a local build artifact.

### 7. Unknown return codes from `is_true_flag` are treated as "not a flag"

- **What:** Any return code other than 0 or 2 means "not a real flag". `HAVE_IS_TRUE_FLAG=1` is also set whether or not `source` succeeded. So a broken helper silently disables every argv-aware deny.
- **Where:** lines 50–51 and 101–102
  ```bash
    source "$LIB_DIR/is-true-flag.sh"
    HAVE_IS_TRUE_FLAG=1
  ```
  ```bash
      [[ "$rc" == "0" || "$rc" == "2" ]] && return 0
      return 1
  ```
- **Why:** Suppose the lib fails to define `is_true_flag` (syntax error, partial file), or it exits with another code (e.g. 127 because its interpreter is missing). Then `rc` is not 0 or 2, and `check_real_flag` returns 1. `--no-verify`, `--no-gpg-sign`, and `git add -f/--force` all pass with no log entry. This contradicts the "fail safe = block" intent. The "fall back silently on a per-call basis below" promised at line 44 does not exist.

### 8. The `git add -f` deny is not tied to the `git add` clause

- **What:** It checks for `-f` anywhere in the whole command and for `git add` anywhere in the whole command, independently.
- **Where:** line 176
  ```bash
  if check_real_flag "-f" && echo "$CMD" | grep -qE 'git[[:space:]]+add\b'; then
  ```
- **Why:**
  - False deny: `git add file && rm -f tmp.txt` is hard-denied as "git add -f".
  - Missed: bundled short options such as `git add -fA secret.env` or `git add -Af .` have no standalone `-f` token, so the force-add passes.

### 9. Commands with git global options or reordered flags bypass the git guards

- **What:** The `git add`, `git reset --hard`, and `git clean` guards require the subcommand, and for reset the flag, directly after `git`.
- **Where:**
  - line 173 (and 176)
    ```bash
    if check_real_flag "--force" && echo "$CMD" | grep -qE 'git[[:space:]]+add\b'; then
    ```
  - line 202
    ```bash
    if echo "$CMD" | grep -qE 'git[[:space:]]+reset[[:space:]]+--hard\b'; then
    ```
- **Why:** None of these match, so they are neither denied nor asked:
  - `git -C repo add -f x`
  - `git -C repo reset --hard`
  - `git reset -q --hard`
  - `git -c x=y clean -fdx`

### 10. `git clean` with `-x` as a separate flag is not caught

- **What:** The `git clean -x` warn only looks at the first flag bundle.
- **Where:** line 208
  ```bash
  if echo "$CMD" | grep -qE 'git[[:space:]]+clean[[:space:]]+-[a-zA-Z]*[xX]'; then
  ```
- **Why:** In `git clean -f -x` or `git clean -d -f -X`, the first bundle has no x. `[a-zA-Z]*` cannot cross the space, so gitignored files (the paid assets the comment names) are removed without an ask.

### 11. `git commit -n` misses bundled flags and git global options

- **What:** The deny requires `-n` as its own token directly after whitespace, and requires every global option to take an argument.
- **Where:** line 195
  ```bash
  if echo "$CMD" | grep -qE 'git([[:space:]]+-[a-zA-Z]+[[:space:]]+[^[:space:]]+)*[[:space:]]+commit\b[^|&;]*[[:space:]]-n\b'; then
  ```
- **Why:** All of these bypass the pre-commit hook without being denied:
  - `git commit -nm "msg"`: there is no word boundary between `n` and `m`.
  - `git commit -anm "msg"`: `-n` is not preceded by whitespace.
  - `git --no-pager commit -n`: the group only allows single-dash options.
  - `git -P commit -n`: the group consumes `commit` as `-P`'s "argument".

### 12. `git commit -n` fires on text inside the commit message

- **What:** The same regex scans into quoted message bodies.
- **Where:** line 195 (same line)
- **Why:** `[^|&;]*` runs through quotes. `git commit -m "support head -n flag"` contains ` -n` followed by a word boundary, so a legitimate commit is hard-denied as a `--no-verify` bypass.

### 13. Abbreviated long options bypass the `--no-verify` and `--no-gpg-sign` denies

- **What:** Both denies match only the full option spelling.
- **Where:** lines 183 and 188
  ```bash
  if check_real_flag "--no-verify"; then
  ```
  ```bash
  if check_real_flag "--no-gpg-sign"; then
  ```
- **Why:** Git's option parser accepts any unambiguous prefix of a long option. `git commit --no-veri -m x` and `git commit --no-gpg -m x` skip hooks and signing. They are not the literal `--no-verify` or `--no-gpg-sign` token, so both denies pass them.

### 14. The pkill command-position test misses shell keywords and wrappers

- **What:** The test only recognizes `pkill`/`killall` at the start of a clause, optionally after `sudo`.
- **Where:** line 137
  ```bash
       | grep -qE '^(sudo[[:space:]]+)?(pkill|killall)([[:space:]]|$)'; then
  ```
- **Why:** None of these reach the scope check:
  - `if true; then pkill -9 -f bats-core/bats; fi` (the clause starts with `then `)
  - `for i in 1; do pkill -f bats; done`
  - `env pkill -f bats`, `nohup pkill …`, `timeout 5 pkill …`, `command pkill …`
  - `xargs pkill`
  - `` `pkill -f bats` ``

  The exact machine-wide kill this clause exists to stop is allowed.

### 15. The pkill scope test accepts markers that don't limit the kill to one worktree

- **What:** A `.worktrees/` path or any `-P` counts as "scoped to ONE worktree", but neither names a specific worktree.
- **Where:** line 146
  ```bash
      if echo "$pk" | grep -qE '\$PWD|\$\{PWD|\$\(pwd|`pwd|\$\(basename|(^|[[:space:]])-P[[:space:]]|\.worktrees/|(^|[^a-zA-Z0-9])wt-[a-zA-Z0-9]'; then
  ```
- **Why:**
  - `pkill -f "bats.*\.worktrees/"` matches the gates of every session. They all run in worktrees under always-worktree isolation.
  - `pkill -P 1 -f bats` matches every orphaned bats machine-wide.
  - Both are treated as scoped and allowed.

### 16. The pkill "own worktree" check is a raw substring test on the directory name

- **What:** The kill counts as naming this session's worktree if the current directory's basename appears anywhere in it.
- **Where:** line 150
  ```bash
      if [[ -n "${PWD##*/}" ]] && echo "$pk" | grep -qF -- "${PWD##*/}"; then
  ```
- **Why:** If the basename is a substring of the unscoped pattern, the unscoped kill is exempted and allowed. For example, a checkout named `main`, `core`, `land`, or `bats` exempts `pkill -f "ship-land.sh --trunk main"` or `pkill -9 -f bats-core/bats`. Both are the incident commands the comment cites.

### 17. The DDL deny misses statements it claims to cover

- **What:** The deny claims "all schema changes", but its keyword list covers only a subset.
- **Where:** line 163
  ```bash
     && echo "$CMD" | grep -qiE '\b(DROP[[:space:]]+TABLE|DROP[[:space:]]+DATABASE|DROP[[:space:]]+INDEX|ALTER[[:space:]]+TABLE|CREATE[[:space:]]+TABLE|TRUNCATE[[:space:]]+TABLE)\b'; then
  ```
- **Why:**
  - `sqlite3 db "CREATE INDEX …"` and `CREATE UNIQUE INDEX` pass, even though `DROP INDEX` is blocked.
  - `CREATE VIEW`, `DROP VIEW`, `CREATE TRIGGER`, and `DROP TRIGGER` run through the database shell unblocked.

### 18. The audit log never records denied or asked commands

- **What:** The audit log write is only reached on the allow path.
- **Where:** line at end of file
  ```bash
  echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [$SID] $CMD" >> ~/.claude/logs/bash-commands.log
  ```
- **Why:** `deny()` and `warn()` both `exit 0` before reaching this line. Any "ask" command (`rm -rf src`, `git reset --hard`, `git clean -x`) that the user approves then runs but never appears in the audit log. These are the most destructive commands executed, and none of them are recorded.
