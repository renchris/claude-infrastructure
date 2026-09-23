## Review — `hooks/validate-bash.sh`

I found 13 defects. Line numbers are counted from `#!/bin/bash` as line 1.

---

### 1. The canonical `rm -rf /` is not denied when it ends the command

**Where** — line 116:
```bash
if echo "$CMD" | grep -qE '(rm[[:space:]]+-rf[[:space:]]+/[^a-zA-Z]|rm[[:space:]]+-rf[[:space:]]+\$HOME|rm[[:space:]]+-rf[[:space:]]+~(/|$|[[:space:]])|sudo[[:space:]]+rm|:\(\)\{[[:space:]]*:\|:&[[:space:]]*\};:)'; then
```
**Why** — `[^a-zA-Z]` requires a character *after* the slash. For the exact command `rm -rf /` (nothing following), there is no character to match, so the first alternative fails, none of the others apply, and the hard deny is skipped. The command falls through to the `warn` clause at line 225 and is merely offered as an "ask". Note the `~` alternative on the same line explicitly handles end-of-string with `(/|$|[[:space:]])`; the `/` alternative does not. The same regex also misses `rm -fr /` and `rm -Rf /`, even though the warn-level extractor at line 217 knows `fr` is a real flag order.

---

### 2. `git add -f` deny fires on a `-f` belonging to a completely different command

**Where** — lines 174 and 177:
```bash
if check_real_flag "--force" && echo "$CMD" | grep -qE 'git[[:space:]]+add\b'; then
```
```bash
if check_real_flag "-f" && echo "$CMD" | grep -qE 'git[[:space:]]+add\b'; then
```
**Why** — the two conjuncts are evaluated against the whole command independently; nothing ties the flag to the `git add` clause. `rm -f tmp.txt && git add -A` has a real argv `-f` token and contains `git add`, so it is denied with "git add -f blocked — gitignored files are intentionally excluded", which is false. Likewise `git push --force && git add .`. This is the exact compound-command coupling error the file avoids elsewhere by per-clause extraction (lines 139, 217).

---

### 3. `git commit -n` regex matches `-n` inside the quoted commit message

**Where** — line 196:
```bash
if echo "$CMD" | grep -qE 'git([[:space:]]+-[a-zA-Z]+[[:space:]]+[^[:space:]]+)*[[:space:]]+commit\b[^|&;]*[[:space:]]-n\b'; then
```
**Why** — `[^|&;]*` happily spans quote characters and message text. `git commit -m "use head -n 20 to trim the log"` matches (`commit` … ` -n` followed by a word boundary) and is denied as "short form of --no-verify". The neighbouring `--no-verify` clause is explicitly argv-aware about quoted `-m` bodies; this clause decides on raw text and therefore blocks a legitimate commit.

---

### 4. `rm -rf` safety check only inspects the first target of each `rm`

**Where** — line 217:
```bash
RM_OCCURRENCES=$(echo "$CMD" | grep -oE 'rm[[:space:]]+-(r|rf|fr)[[:space:]]+[^[:space:];&|]+' || true)
```
**Why** — `[^[:space:];&|]+` stops at the first space, so only one path per `rm` is captured. `rm -rf node_modules src/` yields the occurrence `rm -rf node_modules`, whose target matches `SAFE_RM_TARGETS`, so the loop finds nothing unsafe and the command passes with no prompt — while `src/` is deleted. The comment at lines 213–215 claims per-clause extraction closed the "one clause matched a safe target" hole; the multi-argument form reopens it inside a single clause.

---

### 5. Stripping the leading `/` makes absolute root paths look like build artifacts

**Where** — line 223:
```bash
    target_stripped=$(echo "$target" | sed -E 's|^\./||; s|^/||')
```
**Why** — `rm -rf /build`, `rm -rf /out`, `rm -rf /target`, `rm -rf /coverage` become `build`, `out`, `target`, `coverage`, which match `SAFE_RM_TARGETS` at line 224, so no warning is emitted. A recursive delete of a top-level filesystem directory is classified as a build-artifact cleanup. (It is also not caught by the hard deny above, per defect 1's `[^a-zA-Z]` — `/b` is a letter.)

---

### 6. The safe-target prefix match accepts paths that escape the safe directory

**Where** — line 224:
```bash
    if ! echo "$target_stripped" | grep -qE "^${SAFE_RM_TARGETS}(/|$)"; then
```
**Why** — the check is anchored only at the start, so `node_modules/../../..` matches `^node_modules(/|$)` and is treated as safe. `rm -rf node_modules/../src` deletes `src` with no prompt. The guard proves "the path starts with a safe name", not "the path stays inside a safe directory", which is what it is used for.

---

### 7. The audit log records only the commands that were allowed

**Where** — line 243 (reached only after all checks pass), versus lines 78 and 91:
```bash
echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [$SID] $CMD" >> ~/.claude/logs/bash-commands.log
```
```bash
  exit 0
```
**Why** — `deny()` and `warn()` both `exit 0` from inside the function, so control never reaches the logging block. Every denied and every asked command — the fork bombs, the unscoped `pkill`s, the DDL attempts, i.e. precisely the events an audit log exists for — is absent from `bash-commands.log`. The log silently reads as a complete record of Bash activity while omitting a whole class.

---

### 8. Empty or truncated stdin still silently disables the validator, with no abstain record

**Where** — line 40:
```bash
if ! CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null); then
```
**Why** — `jq` exits 0 on empty input (it simply produces no output), and also exits 0 for a valid payload of `null`. In both cases `CMD` is empty, the `if !` branch is not taken, every danger pattern below misses, and the hook exits 0 — the exact "the bash validator silently disabled itself" failure described at lines 24–27, and with no line written to `validate-bash-unclear.log`. Only a *parse error* from jq is caught; a missing or empty command is not distinguished from a validated one.

---

### 9. DDL deny and `drizzle-kit push` deny decide on raw text, not database-command context

**Where** — lines 163–164 and 169:
```bash
if echo "$CMD" | grep -qiE '\b(turso|sqlite3?|psql|mysql|mariadb|libsql|drizzle-kit[[:space:]]+(push|drop|migrate))\b' \
   && echo "$CMD" | grep -qiE '\b(DROP[[:space:]]+TABLE|DROP[[:space:]]+DATABASE|DROP[[:space:]]+INDEX|ALTER[[:space:]]+TABLE|CREATE[[:space:]]+TABLE|TRUNCATE[[:space:]]+TABLE)\b'; then
```
```bash
if echo "$CMD" | grep -qE 'drizzle-kit[[:space:]]+push'; then
```
**Why** — the comment at lines 158–160 claims the conjunction establishes "DATABASE-COMMAND context", but it only establishes that both strings appear somewhere in the same text, with no position or quote awareness. `git commit -m "psql: document the CREATE TABLE migration"` satisfies both greps and is denied. `git commit -m "note: never run drizzle-kit push"` is denied by line 169 alone. The pkill clause two blocks earlier strips quotes precisely to avoid this; these clauses do not.

---

### 10. `pkill` occurrences are extracted from quoted message bodies

**Where** — line 139:
```bash
  PK_OCCURRENCES=$(echo "$CMD" | grep -oE '(pkill|killall)[^;&|]*' || true)
```
**Why** — the quote-stripping at line 136 is used only for the whole-command position test at lines 137–138; the per-occurrence loop reads the original `$CMD`. So once *any* real `pkill` exists in the command, mentions inside quoted text are also iterated. `pkill -f "bats.*$PWD" && git commit -m "fix: stop broad pkill -f bats"` passes the scope check on the real occurrence but then extracts `pkill -f bats"` from the commit message, which names a gate program and has no scope marker — and the command is denied. The clause's own comment (lines 131–133) states that a mere mention "merely MENTIONS the thing"; the extraction does not honour that.

---

### 11. The worktree-name exemption is an unanchored substring test

**Where** — line 151:
```bash
    if [[ -n "${PWD##*/}" ]] && echo "$pk" | grep -qF -- "${PWD##*/}"; then
```
**Why** — any occurrence containing the current directory's basename anywhere is treated as worktree-scoped. If the session's cwd basename is a short or common string, unrelated machine-wide kills are exempted: with cwd `.../main`, `pkill -f "ship-land.sh --trunk main"` — the second example the header cites as a root cause of the epidemic — matches and is waved through. A basename of `bats` exempts every `pkill -f bats...`. The test proves the string occurs, not that it scopes the selection.

---

### 12. `git clean -x` is missed whenever the `x` is not in the first flag bundle

**Where** — line 209:
```bash
if echo "$CMD" | grep -qE 'git[[:space:]]+clean[[:space:]]+-[a-zA-Z]*[xX]'; then
```
**Why** — the `-[a-zA-Z]*[xX]` must begin immediately after `git clean` plus whitespace. `git clean -f -d -x`, `git clean -d -X`, and `git clean --force -x` do not match, because the first token after `clean ` is `-f`/`-d`/`--force` and the regex cannot skip forward. Gitignored files (the "paid assets" the message names) are deleted with no prompt, despite the comment at line 208 claiming any bundle containing `x` is matched.

---

### 13. A missing `is_true_flag` function turns every argv-aware check into a silent pass

**Where** — lines 51–52 and 102:
```bash
  source "$LIB_DIR/is-true-flag.sh"
  HAVE_IS_TRUE_FLAG=1
```
```bash
    [[ "$rc" == "0" || "$rc" == "2" ]] && return 0
```
**Why** — `HAVE_IS_TRUE_FLAG=1` is set unconditionally after `source`, regardless of whether sourcing succeeded or whether the file actually defines `is_true_flag` (truncated file, early `return`, renamed function). `check_real_flag` then calls a non-existent command, `rc` is 127, which is neither `0` nor `2`, so the function returns 1 — "flag absent". Every `--force`, `-f`, `--no-verify` and `--no-gpg-sign` deny is skipped, with no fallback to the legacy regex and no abstain log entry. The stated posture for an undecidable flag is `rc=2 → fail safe = block` (line 101); the undecidable-because-the-helper-is-broken case fails open instead.
