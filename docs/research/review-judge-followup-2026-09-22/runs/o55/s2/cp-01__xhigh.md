# Review of `hooks/validate-bash.sh`

I found 22 defects. They are grouped by area and numbered straight through. Line numbers count from `#!/bin/bash` as line 1.

## Hard deny and `rm` handling

**1. What:** The "system damage" deny does not match bare `rm -rf /`, quoted or braced `$HOME`, or any flag spelling other than exactly `-rf`.
**Where:** line 116
```bash
if echo "$CMD" | grep -qE '(rm[[:space:]]+-rf[[:space:]]+/[^a-zA-Z]|rm[[:space:]]+-rf[[:space:]]+\$HOME|rm[[:space:]]+-rf[[:space:]]+~(/|$|[[:space:]])|sudo[[:space:]]+rm|:\(\)\{[[:space:]]*:\|:&[[:space:]]*\};:)'; then
```
**Why:**
- `/[^a-zA-Z]` needs one more character after `/`. So `rm -rf /` at end of line (the example named in the deny message) does not match, and falls through to the `rm` warn block as an ask.
- `rm -rf "$HOME"` and `rm -rf ${HOME}` fail because a `"` or `{` sits between the whitespace and `$HOME`.
- `rm -fr /`, `rm -Rf ~`, `rm -rfv ~`, `rm -f -r ~` and `rm --recursive --force /` never hit this deny.
- `-Rf`, `-rfv`, `-f -r` and `--recursive` also escape the warn block (see #3), so they pass with no check at all.

**2. What:** The `rm` warn block checks only the first operand of each `rm`.
**Where:** line 217
```bash
RM_OCCURRENCES=$(echo "$CMD" | grep -oE 'rm[[:space:]]+-(r|rf|fr)[[:space:]]+[^[:space:];&|]+' || true)
```
**Why:** `[^[:space:];&|]+` stops at the first space. For `rm -rf node_modules src`, only `node_modules` is tested; it is safe, so the command passes silently and `src` is deleted. This is the same "one safe target hides an unsafe one" escape hatch the comment on lines 213–215 says was fixed.

**3. What:** The `rm` warn block only recognises the literal flag words `-r`, `-rf` and `-fr`.
**Where:** line 217 (same line as #2)
**Why:** `rm -Rf src`, `rm -rfv src`, `rm -rF src`, `rm -f -r src` and `rm --recursive --force src` produce no occurrence. They get no warn, and #1 shows they get no deny either.

**4. What:** The safe-target test accepts any path that merely starts with a safe name, including `..` traversal.
**Where:** lines 223–224
```bash
    target_stripped=$(echo "$target" | sed -E 's|^\./||; s|^/||')
    if ! echo "$target_stripped" | grep -qE "^${SAFE_RM_TARGETS}(/|$)"; then
```
**Why:**
- `rm -rf build/../..` matches `^build/` and is treated as a build artifact, so the parent of the cwd is deleted with no ask.
- Stripping a leading `/` also makes root-level `/target` or `/build` count as "safe".

## pkill / killall clause

**5. What:** The quote stripper removes single-quoted spans before double-quoted ones, with no awareness of nesting. An apostrophe inside double quotes can therefore erase a real `pkill` clause.
**Where:** line 136
```bash
CMD_NOQ=$(printf '%s' "$CMD" | sed -e "s/'[^']*'/''/g" -e 's/"[^"]*"/""/g')
```
**Why:** Take `git commit -m "don't retry"; pkill -9 -f bats-core/bats; echo 'done'`. The `'` in `don't` pairs with the opening `'` of `'done'`, so everything in between, including the real `pkill`, is deleted from `CMD_NOQ`. The position test on lines 137–138 then finds no `pkill`, and the machine-wide kill is allowed.

**6. What:** Occurrence extraction cuts at `|`, `;` and `&` even inside quotes, so the gate name can fall outside the examined text.
**Where:** line 139
```bash
  PK_OCCURRENCES=$(echo "$CMD" | grep -oE '(pkill|killall)[^;&|]*' || true)
```
**Why:** For `pkill -f "vite|bats"` the occurrence is `pkill -f "vite`. It contains no gate name, so it hits `continue` and no deny is issued, yet the command kills every bats process on the machine.

**7. What:** The command-position test and the target/scope test are not tied to the same clause.
**Where:** lines 137–139
```bash
if printf '%s' "$CMD_NOQ" | sed 's/[&|()]/;/g' | tr ';' '\n' | sed 's/^[[:space:]]*//' \
     | grep -qE '^(sudo[[:space:]]+)?(pkill|killall)([[:space:]]|$)'; then
  PK_OCCURRENCES=$(echo "$CMD" | grep -oE '(pkill|killall)[^;&|]*' || true)
```
**Why:** In `pkill -f vite; git commit -m "stop running pkill -f bats"`, the real `pkill -f vite` passes the position test. Every textual `pkill` in the original CMD, including the quoted mention `pkill -f bats"`, is then checked, and the command is denied. That is the exact "merely MENTIONS" false positive the comment on lines 131–135 says this design prevents.

**8. What:** A pattern counts as "scoped" if a scope token appears anywhere in the clause, or if the cwd basename appears anywhere in it. Neither proves that the kill pattern is restricted to one worktree.
**Where:** lines 147 and 151
```bash
    if echo "$pk" | grep -qE '\$PWD|\$\{PWD|\$\(pwd|`pwd|\$\(basename|(^|[[:space:]])-P[[:space:]]|\.worktrees/|(^|[^a-zA-Z0-9])wt-[a-zA-Z0-9]'; then
```
```bash
    if [[ -n "${PWD##*/}" ]] && echo "$pk" | grep -qF -- "${PWD##*/}"; then
```
**Why:**
- `pkill -9 -f bats-core/bats > "$PWD/kill.log"` contains `$PWD` only in a redirect, so it is exempted and still kills every session's gates.
- When the session runs in the main checkout (basename `myrepo`) and peer worktrees live under `myrepo/.worktrees/`, `pkill -f "bats.*myrepo"` passes as "own worktree" but matches every peer. That is also the form the deny message itself recommends.

**9. What:** The position test only recognises `pkill`/`killall` at clause start, optionally after a bare `sudo `.
**Where:** line 138
```bash
     | grep -qE '^(sudo[[:space:]]+)?(pkill|killall)([[:space:]]|$)'; then
```
**Why:** All of these fail the position test and are allowed without any target or scope check:
- `/usr/bin/pkill -f bats`
- `env pkill …`, `command pkill …`, `timeout 5 pkill …`, `nohup pkill …`, `xargs pkill …`
- `sudo -n pkill …`
- `{ pkill -f bats; }`
- `` `pkill -f bats` ``

## Flag checks

**10. What:** `check_real_flag` treats any `is_true_flag` exit code other than 0 or 2 as "flag absent". Also, `HAVE_IS_TRUE_FLAG=1` is set whether or not `source` succeeded. The "fall back silently on a per-call basis below" promised on lines 44–45 does not exist.
**Where:** lines 51–52 and 102–103
```bash
  source "$LIB_DIR/is-true-flag.sh"
  HAVE_IS_TRUE_FLAG=1
```
```bash
    [[ "$rc" == "0" || "$rc" == "2" ]] && return 0
    return 1
```
**Why:** Suppose the lib file exists but fails to define `is_true_flag` (syntax error or rename), or the function exits 126, 127 or some other error code. Then every call returns 1, and `--no-verify`, `--no-gpg-sign` and `git add -f` are all allowed with no log line and no regex fallback.

**11. What:** The `git commit -n` pattern misses bundled short options and flag-only global options.
**Where:** line 196
```bash
if echo "$CMD" | grep -qE 'git([[:space:]]+-[a-zA-Z]+[[:space:]]+[^[:space:]]+)*[[:space:]]+commit\b[^|&;]*[[:space:]]-n\b'; then
```
**Why:**
- `git commit -nm "msg"` and `git commit -an -m x` fail: `-n\b` needs a word boundary right after `n`, and ` -n` must start the token.
- `git --no-pager commit -n` and `git -P commit -n` fail because the global-option group requires a single-dash option followed by an argument.

All of these skip hooks without being blocked.

**12. What:** The same pattern matches `-n` inside a quoted commit message.
**Where:** line 196 (same line as #11)
**Why:** `[^|&;]*` spans quotes. So `git commit -m "docs: use head -n 5"` is denied as a `--no-verify` bypass, even though git never sees a `-n` flag.

**13. What:** The `git add` deny checks "flag present anywhere" and "`git add` present anywhere" independently.
**Where:** lines 174 and 177
```bash
if check_real_flag "--force" && echo "$CMD" | grep -qE 'git[[:space:]]+add\b'; then
```
```bash
if check_real_flag "-f" && echo "$CMD" | grep -qE 'git[[:space:]]+add\b'; then
```
**Why:** `git add . && docker compose -f dev.yml up`, `git add x && rm -f y` and `git add x && git push --force` are denied as "git add -f/--force", even though no `git add` is forced.

**14. What:** The `git add` head regex misses global options, and the exact-token flag check misses bundled short flags.
**Where:** lines 174 and 177 (same lines as #13)
**Why:**
- `git -C . add -f secret.env` does not match `git[[:space:]]+add` (compare the global-option handling on line 196), so the force-add passes.
- `git add -fA .` has no standalone `-f` token. The legacy regex certainly misses it, and an exact-token `is_true_flag "-f"` would too.

**15. What:** The `--no-verify` and `--no-gpg-sign` checks look for the exact long option, but git accepts unambiguous abbreviations of long options.
**Where:** lines 184 and 189
```bash
if check_real_flag "--no-verify"; then
```
```bash
if check_real_flag "--no-gpg-sign"; then
```
**Why:** `git commit --no-veri` and `git commit --no-gpg` are accepted by git's option parser. They are not the token being searched for, so hooks or signing are bypassed with no deny.

**16. What:** The legacy flag regex requires whitespace or end of line on both sides of the flag.
**Where:** lines 107–108
```bash
    local pattern="(^|[[:space:]])${flag//./\\.}([[:space:]]|\$)"
    echo "$CMD" | grep -qE "$pattern"
```
**Why:** In legacy mode, which is also used silently whenever the lib file is missing, `git commit -m x --no-verify;` and `git commit "--no-verify" -m x` both fail to match: `;` and `"` are not whitespace. The flag reaches git unblocked.

## Warn checks

**17. What:** The `git clean -x` warn inspects only the first flag bundle, despite the comment "any flag bundle".
**Where:** line 209
```bash
if echo "$CMD" | grep -qE 'git[[:space:]]+clean[[:space:]]+-[a-zA-Z]*[xX]'; then
```
**Why:** `git clean -f -x`, `git clean -fd -X` and `git clean -d -f -x` do not match. Gitignored "paid assets" are removed with no ask.

**18. What:** The `git reset --hard` warn only fires when `--hard` immediately follows `reset`.
**Where:** line 203
```bash
if echo "$CMD" | grep -qE 'git[[:space:]]+reset[[:space:]]+--hard\b'; then
```
**Why:** `git reset -q --hard`, `git reset HEAD~1 --hard` and `git -C x reset --hard` discard uncommitted work with no ask.

## DDL / drizzle

**19. What:** The "database-command context" and the `drizzle-kit push` checks read raw text, including quoted message bodies.
**Where:** lines 163–164 and 169
```bash
if echo "$CMD" | grep -qiE '\b(turso|sqlite3?|psql|mysql|mariadb|libsql|drizzle-kit[[:space:]]+(push|drop|migrate))\b' \
   && echo "$CMD" | grep -qiE '\b(DROP[[:space:]]+TABLE|DROP[[:space:]]+DATABASE|DROP[[:space:]]+INDEX|ALTER[[:space:]]+TABLE|CREATE[[:space:]]+TABLE|TRUNCATE[[:space:]]+TABLE)\b'; then
```
```bash
if echo "$CMD" | grep -qE 'drizzle-kit[[:space:]]+push'; then
```
**Why:** Both of these are hard-denied, although neither runs any DDL:
- `git commit -m "sqlite: never DROP TABLE by hand"`
- `git commit -m "remove drizzle-kit push script"`

This is the commit-message false positive the comment on lines 158–162 says the two-condition test avoids.

**20. What:** The DDL list does not cover the schema changes it claims to cover ("all schema changes").
**Where:** line 164 (the second line quoted in #19)
**Why:** `DROP INDEX` is listed but `CREATE INDEX` / `CREATE UNIQUE INDEX` are not. `CREATE TEMP TABLE`, `CREATE VIRTUAL TABLE`, `CREATE/DROP VIEW` and `CREATE/DROP TRIGGER` also do not match. So `sqlite3 app.db "CREATE INDEX i ON users(email)"` passes.

## Plumbing

**21. What:** The fail-open guard only detects a jq *failure*. An empty `CMD` from a parseable-but-empty or unexpected payload still disables every check silently.
**Where:** line 40
```bash
if ! CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null); then
```
**Why:** jq exits 0 on empty stdin, and `// empty` exits 0 when `.tool_input.command` is missing or null. In either case `CMD=""`, every pattern misses, and the hook exits 0 with no ABSTAIN line. That is the "silently disabled itself" state the comment on lines 21–31 says was fixed.

**22. What:** The audit log is written only for commands that received no decision. Every `deny` or `warn` exits before reaching it.
**Where:** line 243, together with `  exit 0` at lines 77 and 90
```bash
echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [$SID] $CMD" >> ~/.claude/logs/bash-commands.log
```
**Why:** A command that triggers `warn` (for example `rm -rf src`) and is then approved by the user and executed never appears in `bash-commands.log`. The destructive commands the audit exists to record are exactly the ones missing from it.
