**17 defects found, listed in file order.**

---

**1.**
**What:** The payload guard only checks jq's exit status, so a payload that parses but has no command still leaves `CMD` empty, and the hook then passes silently.
**Where:** line 40
```bash
if ! CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null); then
```
**Why:** With empty stdin, `{}`, `null`, or a payload whose command field is missing or renamed, `jq … // empty` prints nothing and exits 0. `CMD` is empty, every pattern misses, no ABSTAIN line is written, and the hook exits 0. This is the "CMD went empty … silently disabled itself" failure that lines 21–31 say this block fixed.

**2.**
**What:** Any `is_true_flag` exit status other than 0 or 2 is treated as "flag not present", and the helper is marked available without checking that sourcing actually defined it.
**Where:** lines 51–52 and 102–103
```bash
  source "$LIB_DIR/is-true-flag.sh"
  HAVE_IS_TRUE_FLAG=1
    [[ "$rc" == "0" || "$rc" == "2" ]] && return 0
    return 1
```
**Why:** Suppose `lib/is-true-flag.sh` exists but fails part-way, for example through a syntax error, an early `return`, or a renamed function. Then `is_true_flag` returns 127 (as would any other failure status) and hits `return 1`. The `--force`, `-f`, `--no-verify` and `--no-gpg-sign` denies all pass silently. Nothing falls back to the regex path, and the error is not given the "fail safe = block" treatment that rc=2 gets.

**3.**
**What:** The system-damage deny misses ordinary spellings of the commands its own message names (`rm -rf /`, `rm -rf ~`).
**Where:** line 116
```bash
if echo "$CMD" | grep -qE '(rm[[:space:]]+-rf[[:space:]]+/[^a-zA-Z]|rm[[:space:]]+-rf[[:space:]]+\$HOME|rm[[:space:]]+-rf[[:space:]]+~(/|$|[[:space:]])|sudo[[:space:]]+rm|:\(\)\{[[:space:]]*:\|:&[[:space:]]*\};:)'; then
```
**Why:**
- (a) Bare `rm -rf /` at the end of the command or of a line is not denied. `/[^a-zA-Z]` needs one more character, and grep never matches the newline. The `~` alternative accepts `$`; the `/` one does not. So the command only reaches the rm-warn `ask` at line 225.
- (b) Quoted or braced targets are also only asked, not denied: `rm -rf "$HOME"`, `rm -rf "/"`, `rm -rf ${HOME}`. The same applies to `rm -fr /`.
- (c) `rm -Rf /` and `rm -Rf ~` match neither this regex nor the warn's `-(r|rf|fr)`, so they get no decision at all.

**4.**
**What:** Quote stripping removes single-quoted spans before double-quoted ones, so an apostrophe inside a double-quoted string pairs with a later `'` and erases the real command text between them.
**Where:** line 136
```bash
CMD_NOQ=$(printf '%s' "$CMD" | sed -e "s/'[^']*'/''/g" -e 's/"[^"]*"/""/g')
```
**Why:** `git commit -m "wip: don't land" ; pkill -f 'bats-core/bats'` becomes `git commit -m "wip: don''bats-core/bats'`. The `;` and the real `pkill` are gone, the position test finds nothing, and the machine-wide kill passes with no decision.

**5.**
**What:** The command-position test only recognises pkill/killall as the first word of a clause split on `& | ( ) ;`.
**Where:** lines 137–138
```bash
if printf '%s' "$CMD_NOQ" | sed 's/[&|()]/;/g' | tr ';' '\n' | sed 's/^[[:space:]]*//' \
     | grep -qE '^(sudo[[:space:]]+)?(pkill|killall)([[:space:]]|$)'; then
```
**Why:** `if pgrep -f bats >/dev/null; then pkill -f bats; fi` produces the clause `then pkill -f bats`, which does not match. The same happens with:
- `timeout 5 pkill -f bats-core/bats`
- `/usr/bin/pkill -9 -f bats-core/bats`
- `{ pkill -f bats; }`
- `` echo `pkill -f bats` ``

In each case the whole block is skipped and the unscoped kill passes.

**6.**
**What:** The occurrence scan takes raw substrings of the original command and cuts each at the first `;`, `&` or `|`, even inside quotes, so it truncates real kill patterns and also judges mentions in message bodies.
**Where:** line 139
```bash
  PK_OCCURRENCES=$(echo "$CMD" | grep -oE '(pkill|killall)[^;&|]*' || true)
```
**Why:**
- **Missed kill:** `pkill -f "vitest|bats"` yields only `pkill -f "vitest`. That has no gate name, so it is skipped, even though the alternation kills every bats process machine-wide.
- **Wrong deny:** `git commit -m "chore: stop using pkill -f bats" && pkill -f "bats.*${PWD##*/}"` is denied. The real kill uses the scoped form the deny message itself recommends, but the message-body occurrence `pkill -f bats" ` is unscoped. That is a raw-text decision, which lines 131–133 call the defect.

**7.**
**What:** The gate-target test checks whether the pkill text contains a gate program's full name, not whether the pkill pattern would match a gate's command line.
**Where:** line 143
```bash
    echo "$pk" | grep -qE '(bats|ship-land|postland-verify)' || continue
```
**Why:** `pkill -f` matches its pattern anywhere in each process's command line. So `pkill -f postland` or `pkill -f land.sh` kills every `postland-verify` or `ship-land.sh` gate machine-wide. Neither contains any of the three names, so `continue` skips them.

**8.**
**What:** The scope test accepts markers that do not confine the kill pattern to one worktree.
**Where:** line 147
```bash
    if echo "$pk" | grep -qE '\$PWD|\$\{PWD|\$\(pwd|`pwd|\$\(basename|(^|[[:space:]])-P[[:space:]]|\.worktrees/|(^|[^a-zA-Z0-9])wt-[a-zA-Z0-9]'; then
```
**Why:** `\.worktrees/` matches with no worktree name after it, and `$PWD` matches anywhere in the clause. Both of these skip the deny:
- `pkill -f "bats.*\.worktrees/"`, which matches every worktree's gates.
- `pkill -9 -f bats-core/bats 2>>"$PWD/kill.log"`, which is the incident's exact pattern with `$PWD` appearing only in a redirection.

**9.**
**What:** The "database-command context" test is a bare word match anywhere in the text, so message bodies and paths that mention a DB client next to DDL words are hard-denied.
**Where:** lines 163–164
```bash
if echo "$CMD" | grep -qiE '\b(turso|sqlite3?|psql|mysql|mariadb|libsql|drizzle-kit[[:space:]]+(push|drop|migrate))\b' \
   && echo "$CMD" | grep -qiE '\b(DROP[[:space:]]+TABLE|DROP[[:space:]]+DATABASE|DROP[[:space:]]+INDEX|ALTER[[:space:]]+TABLE|CREATE[[:space:]]+TABLE|TRUNCATE[[:space:]]+TABLE)\b'; then
```
**Why:** Both of these match both regexes and are denied as DDL:
- `git commit -m "fix(sqlite): quote identifiers in CREATE TABLE"`
- `grep -rn "CREATE TABLE" src/db/sqlite/`

The context condition that lines 158–160 rely on to spare commit messages is satisfied by the message text itself.

**10.**
**What:** The DDL keyword list leaves out common schema-changing statements.
**Where:** line 164
```bash
   && echo "$CMD" | grep -qiE '\b(DROP[[:space:]]+TABLE|DROP[[:space:]]+DATABASE|DROP[[:space:]]+INDEX|ALTER[[:space:]]+TABLE|CREATE[[:space:]]+TABLE|TRUNCATE[[:space:]]+TABLE)\b'; then
```
**Why:** `sqlite3 app.db "CREATE INDEX idx_email ON users(email)"` passes. So do `CREATE UNIQUE INDEX`, `CREATE/DROP VIEW` and `CREATE/DROP TRIGGER`. Yet `DROP INDEX` is listed, and the deny's premise is that all schema changes go through Drizzle migrations.

**11.**
**What:** The git-add force checks test for the flag and for `git add` separately across the whole command, so a `-f` or `--force` belonging to another command triggers the git-add deny.
**Where:** lines 174 and 177
```bash
if check_real_flag "--force" && echo "$CMD" | grep -qE 'git[[:space:]]+add\b'; then
if check_real_flag "-f" && echo "$CMD" | grep -qE 'git[[:space:]]+add\b'; then
```
**Why:** `rm -f .git/index.lock && git add -A` is denied as "git add -f blocked", and `git add . && git push --force` as "git add --force blocked". `check_real_flag` receives only the flag and the whole command, so nothing ties the flag to `git add`. In legacy mode the ` -f ` regex matches outright.

**12.**
**What:** The git add, reset and clean regexes require the subcommand to come directly after `git`, so any git global option in between defeats them.
**Where:** lines 174, 177, 203 and 209
```bash
if check_real_flag "--force" && echo "$CMD" | grep -qE 'git[[:space:]]+add\b'; then
if check_real_flag "-f" && echo "$CMD" | grep -qE 'git[[:space:]]+add\b'; then
if echo "$CMD" | grep -qE 'git[[:space:]]+reset[[:space:]]+--hard\b'; then
if echo "$CMD" | grep -qE 'git[[:space:]]+clean[[:space:]]+-[a-zA-Z]*[xX]'; then
```
**Why:** None of these gets a deny or ask:
- `git -C ../wt add -f .env`
- `git -C ../wt reset --hard`
- `git -C ../wt clean -fdx`

The `commit -n` regex at line 196 does allow for `-C <dir>`, so the gap is specific to these checks.

**13.**
**What:** The `git commit -n` check matches raw text on a single line instead of git's parsed options, so it misses real `-n` forms and fires on message text.
**Where:** line 196
```bash
if echo "$CMD" | grep -qE 'git([[:space:]]+-[a-zA-Z]+[[:space:]]+[^[:space:]]+)*[[:space:]]+commit\b[^|&;]*[[:space:]]-n\b'; then
```
**Why:**
- **Missed `-n` (hooks skipped, no deny):**
  - `git commit -nm "wip"` and `git commit -an -m wip`, because git expands bundled short options.
  - A `-n` on a continuation line (`git commit \` then `-n -m wip` on the next line), because grep works line by line.
- **Wrong deny:** `git commit -m "fix: handle sed -n output"` is hard-denied as a hook bypass because ` -n` appears in the message.

**14.**
**What:** The git-clean regex only looks at the first option word after `clean`.
**Where:** line 209
```bash
if echo "$CMD" | grep -qE 'git[[:space:]]+clean[[:space:]]+-[a-zA-Z]*[xX]'; then
```
**Why:** `git clean -f -x`, `git clean -fd -X` and `git clean -d -f -x` delete gitignored files with no ask, including the paid assets the comment mentions. The first word contains no x, and later words are never examined.

**15.**
**What:** The rm extraction only recognises the flag words `-r`, `-rf` and `-fr`, and only captures the first operand after them.
**Where:** line 217
```bash
RM_OCCURRENCES=$(echo "$CMD" | grep -oE 'rm[[:space:]]+-(r|rf|fr)[[:space:]]+[^[:space:];&|]+' || true)
```
**Why:**
- **First operand only:** `rm -rf node_modules src` yields `rm -rf node_modules`, which is safe, so there is no warn while `src` is deleted. `rm -rf dist ~` also escapes line 116, because the `~` is not directly after `-rf`. This is the "safe target hides an unsafe one" escape hatch that lines 213–215 claim to close.
- **Other flag spellings:** `rm -Rf src`, `rm -rfv src`, `rm -f -r src` and `rm --recursive --force src` produce no occurrence at all and pass with no decision.

**16.**
**What:** The safe-target test is a prefix match on a path whose leading `/` has been stripped, so paths that climb out of a safe directory, and absolute paths, are classed as build artifacts.
**Where:** lines 223–224
```bash
    target_stripped=$(echo "$target" | sed -E 's|^\./||; s|^/||')
    if ! echo "$target_stripped" | grep -qE "^${SAFE_RM_TARGETS}(/|$)"; then
```
**Why:** `rm -rf node_modules/../src` gives `node_modules/../src`, which matches `^(node_modules)(/|$)`, so there is no warn and `src` is deleted. `rm -rf /build` or `rm -rf /target` is reduced to `build` or `target` and treated as the project's own build output.

**17.**
**What:** The audit log line is only reached when no decision was emitted, because `deny()` and `warn()` exit first.
**Where:** lines 77 and 90 (identical), and line 243
```bash
  exit 0
echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [$SID] $CMD" >> ~/.claude/logs/bash-commands.log
```
**Why:** A command that got `ask` and was then approved runs but never appears in `bash-commands.log`. Examples are `git reset --hard` and `rm -rf src`. Denied attempts are not logged either. So the session-attributed audit trail leaves out exactly the destructive commands.
