# Review of `hooks/validate-bash.sh`

I found 22 defects, ordered roughly by severity. The worst are bare `rm -rf /` getting only an "ask", `rm -Rf ~` and `rm -rf node_modules ~` passing silently, and `git commit -nm` slipping past the `-n` guard.

---

### 1. Bare `rm -rf /` is not hard-denied
- **What:** The system-damage regex needs a character after the `/`, so the canonical `rm -rf /` is not denied.
- **Where:** line 116: `if echo "$CMD" | grep -qE '(rm[[:space:]]+-rf[[:space:]]+/[^a-zA-Z]|rm[[:space:]]+-rf[[:space:]]+\$HOME|rm[[:space:]]+-rf[[:space:]]+~(/|$|[[:space:]])|sudo[[:space:]]+rm|:\(\)\{[[:space:]]*:\|:&[[:space:]]*\};:)'; then`
- **Why:** For CMD `rm -rf /` (end of line), `/[^a-zA-Z]` cannot match. The command falls through to the rm-target loop, which only issues `warn`. A catastrophic command becomes an approvable "ask" instead of a deny. `~` has a `$` alternative; `/` does not.

### 2. Other `rm` flag spellings escape both the deny and the warn
- **What:** Both `rm` checks only recognise the literal spellings `-rf` (deny) and `-r`/`-rf`/`-fr` (warn).
- **Where:**
  - line 116 (above)
  - line 217: `RM_OCCURRENCES=$(echo "$CMD" | grep -oE 'rm[[:space:]]+-(r|rf|fr)[[:space:]]+[^[:space:];&|]+' || true)`
- **Why:**
  - `rm -Rf ~`, `rm -rfv ~` and `rm --recursive --force ~` match neither regex, so they pass with no deny and no ask.
  - `rm -fr /` and `rm -r -f /` only get an ask.
  - `rm -rf "$HOME"` and `rm -rf ${HOME}` miss the `\$HOME` alternative, which needs `$HOME` directly after the whitespace.

### 3. Only the first `rm` target is checked
- **What:** Each `rm` occurrence stops at the first whitespace, so later targets are never checked.
- **Where:** line 217 (above)
- **Why:** For `rm -rf node_modules ~` (or `rm -rf dist src`):
  - Line 116 doesn't match, because `~` is not directly after `-rf`.
  - The occurrence is `rm -rf node_modules`, which is a safe target.
  - Result: no warn, and the home directory (or `src`) is deleted silently. This is the same escape hatch the comment at lines 213–215 claims to close, one level down.

### 4. `git commit -n` guard misses bundled short flags
- **What:** `-n\b` needs a word boundary right after `n`, so bundles containing `-n` are missed.
- **Where:** line 196: `if echo "$CMD" | grep -qE 'git([[:space:]]+-[a-zA-Z]+[[:space:]]+[^[:space:]]+)*[[:space:]]+commit\b[^|&;]*[[:space:]]-n\b'; then`
- **Why:**
  - `git commit -nm "msg"` and `git commit -an -m x` skip pre-commit hooks and are not denied. `-nm` is the most common way to write this.
  - `git --no-pager commit -n` and `git -P commit -n` also escape, because the global-option group needs `-X value` pairs.

### 5. `git commit -n` guard fires on message text
- **What:** The same regex lets `[^|&;]*` run into the quoted message body.
- **Where:** line 196 (above)
- **Why:** `git commit -m "use head -n 5 in script"` matches ` -n` inside the message and is denied as `--no-verify`. This is the quoted-body false positive the file claims to avoid elsewhere.

### 6. `git add -f` / `--force` deny doesn't require the flag to belong to `git add`
- **What:** The "real flag" test and the `git add` test are independent checks on the whole command.
- **Where:**
  - line 174: `if check_real_flag "--force" && echo "$CMD" | grep -qE 'git[[:space:]]+add\b'; then`
  - line 177: `if check_real_flag "-f" && echo "$CMD" | grep -qE 'git[[:space:]]+add\b'; then`
- **Why:** These are denied as "git add -f blocked" even though no force-add happens:
  - `rm -f out.log && git add src/`
  - `git add . && docker compose -f x.yml up`
  - `git add -A && git push --force`

### 7. `git add -f` guard misses global options (and bundles in legacy mode)
- **What:** The `git add` guard doesn't allow global options between `git` and `add`.
- **Where:** lines 174 and 177, `grep -qE 'git[[:space:]]+add\b'`; line 107: `local pattern="(^|[[:space:]])${flag//./\\.}([[:space:]]|\$)"`
- **Why:**
  - `git -C ../wt add -f .env` never matches `git[[:space:]]+add`, so gitignored files get force-added. The `-n` check at line 196 explicitly handles global options; this one doesn't.
  - In legacy mode, `git add -Af` also escapes, because `-f` is only matched as a standalone token.

### 8. `is_true_flag` failure other than rc 2 fails open
- **What:** `HAVE_IS_TRUE_FLAG=1` is set without checking that sourcing succeeded or that the function exists. Any return code other than 0 or 2 is then treated as "not a real flag".
- **Where:**
  - line 52: `  HAVE_IS_TRUE_FLAG=1`
  - line 102: `    [[ "$rc" == "0" || "$rc" == "2" ]] && return 0`
  - line 103: `    return 1`
- **Why:** Suppose `is-true-flag.sh` exists but aborts before defining `is_true_flag` (syntax error, or an early `return`). Then `is_true_flag` returns 127, and `--no-verify`, `--no-gpg-sign` and `git add --force` are all silently allowed. The comment promises "unclear → fail safe = block".

### 9. Empty or field-less payload still disables the validator silently
- **What:** The payload guard only catches a non-zero exit from `jq`.
- **Where:** line 40: `if ! CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null); then`
- **Why:** Empty stdin, or valid JSON without `.tool_input.command` (for example a renamed field), makes `jq` exit 0 with no output. CMD becomes empty, every pattern misses, and the hook exits 0 with no ABSTAIN line. This is exactly the "CMD went empty… silently disabled itself" failure the block says it fixes.

### 10. Quote stripping pairs quotes across strings and erases real commands
- **What:** The single-quote strip runs before the double-quote strip and ignores nesting, so an apostrophe inside double quotes pairs with a later single quote.
- **Where:** line 136: `CMD_NOQ=$(printf '%s' "$CMD" | sed -e "s/'[^']*'/''/g" -e 's/"[^"]*"/""/g')`
- **Why:** In `git commit -m "don't regress"; pkill -f bats-core/bats; echo 'ok'`, everything from `'t` to `'ok'` is erased. The real `pkill` disappears from CMD_NOQ, the position test fails, and the machine-wide kill is allowed.

### 11. Command-position test only recognises `pkill` at clause start or after `sudo`
- **What:** The position test assumes `pkill`/`killall` is either the first word of a clause or directly after `sudo`.
- **Where:** line 138: `     | grep -qE '^(sudo[[:space:]]+)?(pkill|killall)([[:space:]]|$)'; then`
- **Why:** None of these are recognised, so each is allowed:
  - `for i in 1; do pkill -f bats-core/bats; done` (clause is `do pkill …`)
  - `if …; then pkill …`
  - `{ pkill …; }`
  - `/usr/bin/pkill -f bats`
  - `timeout 5 pkill …`
  - `xargs pkill`
  - `'pkill' -f bats` (the quote strip turns this into `''`)

### 12. `pkill` deny fires on quoted mentions once any real `pkill` exists
- **What:** Occurrences are extracted from the original CMD, so quoted mentions are judged as if they were commands.
- **Where:** line 139: `  PK_OCCURRENCES=$(echo "$CMD" | grep -oE '(pkill|killall)[^;&|]*' || true)`
- **Why:** In `pkill -f vite; git commit -m "docs: never pkill -f bats"`, the real `pkill` of vite passes the position test. The quoted `pkill -f bats"` is then extracted, judged unscoped, and the command is denied. This is the "decides on raw text" defect the comment says it prevents.

### 13. Worktree-name scope check is a substring match on the cwd basename
- **What:** The command counts as scoped if the cwd's last path component appears anywhere in it.
- **Where:** line 151: `    if [[ -n "${PWD##*/}" ]] && echo "$pk" | grep -qF -- "${PWD##*/}"; then`
- **Why:** With a cwd of `…/repo/main`, `pkill -f "ship-land.sh --trunk main"` (the comment's own machine-wide example, line 124) contains `main` and is allowed. Likewise a cwd ending in `tests` allows `pkill -f "bats tests/"`.

### 14. Scope regex accepts tokens that don't scope the kill
- **What:** The scope regex searches the whole clause and accepts a bare `.worktrees/` without a worktree name.
- **Where:** line 147: `    if echo "$pk" | grep -qE '\$PWD|\$\{PWD|\$\(pwd|`pwd|\$\(basename|(^|[[:space:]])-P[[:space:]]|\.worktrees/|(^|[^a-zA-Z0-9])wt-[a-zA-Z0-9]'; then`
- **Why:** Both of these are treated as scoped even though they match every session:
  - `pkill -9 -f bats-core/bats 2>>$PWD/kill.log` (the `$PWD` is only in a redirect)
  - `pkill -f '\.worktrees/.*ship-land'` (every worktree matches)

### 15. Gate-target test is textual
- **What:** Only patterns whose text contains `bats`, `ship-land` or `postland-verify` are considered gate kills.
- **Where:** line 143: `    echo "$pk" | grep -qE '(bats|ship-land|postland-verify)' || continue`
- **Why:** `pkill -f tests/` matches every `bats tests/…` command line, and `killall bash` kills every bats process, since bats runs under bash. Neither contains a gate name, so both pass, even though they kill all sessions' gates.

### 16. `git clean` check only inspects the first flag bundle
- **What:** The `x`/`X` must appear in the first flag bundle after `git clean`.
- **Where:** line 209: `if echo "$CMD" | grep -qE 'git[[:space:]]+clean[[:space:]]+-[a-zA-Z]*[xX]'; then`
- **Why:** `git clean -fd -x` and `git clean -f -X` remove gitignored files with no ask. This contradicts the comment "any flag bundle containing x or X".

### 17. `git reset --hard` warn requires `--hard` directly after `reset`
- **What:** The regex only matches when `--hard` immediately follows `reset`.
- **Where:** line 203: `if echo "$CMD" | grep -qE 'git[[:space:]]+reset[[:space:]]+--hard\b'; then`
- **Why:** These all discard uncommitted work with no ask:
  - `git reset HEAD~1 --hard`
  - `git reset -q --hard`
  - `git -C wt reset --hard`

### 18. DDL list does not cover all schema changes
- **What:** The DDL keyword list omits common schema-changing statements.
- **Where:** line 164: `   && echo "$CMD" | grep -qiE '\b(DROP[[:space:]]+TABLE|DROP[[:space:]]+DATABASE|DROP[[:space:]]+INDEX|ALTER[[:space:]]+TABLE|CREATE[[:space:]]+TABLE|TRUNCATE[[:space:]]+TABLE)\b'; then`
- **Why:** `sqlite3 local.db "CREATE INDEX idx ON users(email)"` is allowed, as are `CREATE UNIQUE INDEX`, `CREATE/DROP VIEW` and `CREATE/DROP TRIGGER`. These are schema changes that bypass migrations, contrary to "all schema changes must go through Drizzle migrations".

### 19. DDL and drizzle-kit denies fire on commit messages
- **What:** Both checks match raw text anywhere in the command.
- **Where:**
  - line 163: `if echo "$CMD" | grep -qiE '\b(turso|sqlite3?|psql|mysql|mariadb|libsql|drizzle-kit[[:space:]]+(push|drop|migrate))\b' \`
  - line 169: `if echo "$CMD" | grep -qE 'drizzle-kit[[:space:]]+push'; then`
- **Why:** Both of these are denied:
  - `git commit -m "fix: reject DROP TABLE sent via sqlite3"`
  - `git commit -m "docs: explain why drizzle-kit push is banned"`

  The comment at lines 158–160 claims commit messages discussing DDL are not blocked.

### 20. Abbreviated git long options bypass exact-token flag checks
- **What:** The flag checks match exact tokens, but git accepts unambiguous prefixes of long options.
- **Where:**
  - line 174: `if check_real_flag "--force" && ...`
  - line 184: `if check_real_flag "--no-verify"; then`
  - line 189: `if check_real_flag "--no-gpg-sign"; then`
- **Why:** `git commit --no-veri -m x`, `git commit --no-gpg …` and `git add --forc x` are honoured by git but don't match the exact tokens, so they are allowed.

### 21. `$HOME` alternative has no boundary
- **What:** `\$HOME` matches any variable whose name starts with `HOME`.
- **Where:** line 116 (above)
- **Why:** `rm -rf $HOMEBREW_CACHE/downloads` is hard-denied as "potential system damage (rm -rf ~)".

### 22. Audit log skips every denied or asked command
- **What:** `deny`/`warn` exit before the audit log is written, so only fully-allowed commands are recorded.
- **Where:**
  - line 90: `  exit 0` (in `warn`)
  - line 243: `echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [$SID] $CMD" >> ~/.claude/logs/bash-commands.log`
- **Why:** An "ask" command such as `git reset --hard` or `rm -rf src` that the user approves and runs never appears in `bash-commands.log`. The audit trail omits the most destructive commands that actually executed.
