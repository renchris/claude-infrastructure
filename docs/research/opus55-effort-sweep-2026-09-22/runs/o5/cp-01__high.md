# Review — `hooks/validate-bash.sh`

Line numbers are as counted from the brief (1 = `#!/bin/bash`). Quoted lines are verbatim.

---

### 1. The bare `rm -rf /` is not denied — it falls through to a mere "ask"

**Where** — line 116:
```bash
if echo "$CMD" | grep -qE '(rm[[:space:]]+-rf[[:space:]]+/[^a-zA-Z]|rm[[:space:]]+-rf[[:space:]]+\$HOME|rm[[:space:]]+-rf[[:space:]]+~(/|$|[[:space:]])|sudo[[:space:]]+rm|:\(\)\{[[:space:]]*:\|:&[[:space:]]*\};:)'; then
```

**Why it is wrong** — `/[^a-zA-Z]` requires a character *after* the slash. For the command `rm -rf /` the `/` is the last character of the line, so `[^a-zA-Z]` has nothing to consume and the alternative does not match. The same clause also only spells `-rf`, so `rm -fr /`, `rm -Rf /` and `rm -r -f /` miss as well (contrast line 217, which does handle `fr`). These land instead in the warn block at line 224 and produce `permissionDecision: "ask"` — the headline case of the "catastrophic" deny is downgraded to a prompt.

---

### 2. The `rm -rf` warn clause inspects only the first target of each occurrence

**Where** — line 217:
```bash
RM_OCCURRENCES=$(echo "$CMD" | grep -oE 'rm[[:space:]]+-(r|rf|fr)[[:space:]]+[^[:space:];&|]+' || true)
```

**Why it is wrong** — `[^[:space:];&|]+` stops at the first whitespace, so only one argument is captured per `rm`. `rm -rf node_modules src` yields the single occurrence `rm -rf node_modules`, which matches `SAFE_RM_TARGETS`, so the loop finds nothing unsafe and the hook exits 0 — `src` is deleted with no prompt. This is the same "one clause matched a safe target" escape hatch the comment on lines 213-215 claims to have closed, just moved from clause level to argument level.

---

### 3. Stripping a leading `/` makes absolute paths look like build artifacts

**Where** — lines 223-224:
```bash
    target_stripped=$(echo "$target" | sed -E 's|^\./||; s|^/||')
    if ! echo "$target_stripped" | grep -qE "^${SAFE_RM_TARGETS}(/|$)"; then
```

**Why it is wrong** — `rm -rf /out`, `rm -rf /build`, `rm -rf /target`, `rm -rf /dist` become `out`, `build`, `target`, `dist` after the strip, match `SAFE_RM_TARGETS`, and pass with no warning at all (and they are not caught by clause 1 either, since `/o` is a letter). Separately, the anchor only constrains the *prefix*: `rm -rf dist/../../..` matches `^dist(/|$)` and is classified as a safe build-artifact removal.

---

### 4. `git clean` check only examines the first flag token

**Where** — line 209:
```bash
if echo "$CMD" | grep -qE 'git[[:space:]]+clean[[:space:]]+-[a-zA-Z]*[xX]'; then
```

**Why it is wrong** — the `-[a-zA-Z]*[xX]` bundle must sit immediately after `git clean`. `git clean -f -x`, `git clean -d -X`, and `git clean --force -x` do not match, yet they delete exactly the gitignored files (the "paid assets" in the warn text) the clause exists to prompt about. The comment on line 208 claims "any flag bundle containing x or X after `git clean -`"; only the first bundle is checked.

---

### 5. Bundled `-n` evades the `git commit -n` deny

**Where** — line 196:
```bash
if echo "$CMD" | grep -qE 'git([[:space:]]+-[a-zA-Z]+[[:space:]]+[^[:space:]]+)*[[:space:]]+commit\b[^|&;]*[[:space:]]-n\b'; then
```

**Why it is wrong** — the trailing `\b` after `-n` requires a non-word character next. `git commit -nm "msg"` is valid git short-option bundling (`-n` plus `-m msg`) and skips the pre-commit hooks, but `-nm` fails the `\b` test, so nothing matches. `check_real_flag "--no-verify"` at line 184 does not cover it either. The bypass the clause exists to block goes through.

---

### 6. The same `-n` regex fires on `-n` inside a quoted commit message

**Where** — line 196 (same line as above):
```bash
if echo "$CMD" | grep -qE 'git([[:space:]]+-[a-zA-Z]+[[:space:]]+[^[:space:]]+)*[[:space:]]+commit\b[^|&;]*[[:space:]]-n\b'; then
```

**Why it is wrong** — `[^|&;]*` happily crosses quote boundaries. `git commit -m "add head -n 5 to the script"` matches (`commit` … ` -n` followed by a space) and is denied with "git commit -n blocked — short form of --no-verify", even though git receives no `-n`. Lines 182-183 and 131-135 state that quoted message bodies are explicitly not to be decided on; this clause does exactly that.

---

### 7. `git add -f/--force` denies on a flag that belongs to a different command

**Where** — lines 174 and 177:
```bash
if check_real_flag "--force" && echo "$CMD" | grep -qE 'git[[:space:]]+add\b'; then
```
```bash
if check_real_flag "-f" && echo "$CMD" | grep -qE 'git[[:space:]]+add\b'; then
```

**Why it is wrong** — the two conditions are evaluated over the whole command independently; nothing ties the flag to the `git add` clause. `git add -A && grep -f patterns.txt build.log` is denied with "git add -f blocked — gitignored files are intentionally excluded", and `git add . && git push --force` is denied with the `git add --force` message. The premise ("this flag was passed to `git add`") is never established, and the reported reason is false.

---

### 8. The pkill occurrence list is built from the raw command, bypassing the position test

**Where** — line 139:
```bash
  PK_OCCURRENCES=$(echo "$CMD" | grep -oE '(pkill|killall)[^;&|]*' || true)
```

**Why it is wrong** — the command-position gate on lines 137-138 runs on the quote-stripped `CMD_NOQ`, but once any one `pkill` passes it, the occurrence list is re-extracted from the original `$CMD` with a plain substring match. For
`pkill -f "bats.*wt-foo" && git commit -m "chore: stop pkill bats sprees"`
the gate opens on the real, properly scoped kill, then the second "occurrence" `pkill bats sprees"` is harvested from the commit message, matches `bats` at line 143, matches no scope pattern at lines 147/151, and is denied. Lines 131-135 assert the opposite behaviour ("Deciding on raw text is the exact defect this clause exists to stop").

---

### 9. Command-position test misses `pkill` after a shell keyword or wrapper

**Where** — lines 137-138:
```bash
if printf '%s' "$CMD_NOQ" | sed 's/[&|()]/;/g' | tr ';' '\n' | sed 's/^[[:space:]]*//' \
     | grep -qE '^(sudo[[:space:]]+)?(pkill|killall)([[:space:]]|$)'; then
```

**Why it is wrong** — only a bare `sudo` prefix is tolerated, and only `&`, `|`, `(`, `)`, `;` split statements. `if true; then pkill -9 -f bats-core/bats; fi`, `for w in a; do pkill -f bats; done`, `xargs pkill -f bats`, and `nohup pkill -f bats` all leave the segment starting with `then`/`do`/`xargs`/`nohup`, so the anchored match fails and the entire unscoped-kill guard — deny included — is skipped for a machine-wide kill that does execute.

---

### 10. A sourced-but-broken helper silently disables every flag check

**Where** — lines 51-52 and 99-103:
```bash
  source "$LIB_DIR/is-true-flag.sh"
  HAVE_IS_TRUE_FLAG=1
```
```bash
    is_true_flag "$flag" "$CMD"
    local rc=$?
    # rc=0 → real flag; rc=1 → substring only; rc=2 → unclear (fail safe = block)
    [[ "$rc" == "0" || "$rc" == "2" ]] && return 0
    return 1
```

**Why it is wrong** — `HAVE_IS_TRUE_FLAG=1` is set on the mere *existence* of the file; `source` failing part-way, or the file defining the function under a different name, is never detected (no `declare -F is_true_flag` check). `is_true_flag` then exits 127 ("command not found"), which is neither 0 nor 2, so `check_real_flag` returns 1 = "flag not present". `--no-verify`, `--no-gpg-sign` and `git add -f` are all silently allowed. Any unexpected exit code from the helper (crash, `set -u` abort) fails open the same way, which inverts the "unclear → fail safe = block" contract stated on line 101.

---

### 11. The jq guard checks jq's exit status, not whether a command was extracted

**Where** — lines 40-42:
```bash
if ! CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null); then
  abstain_unclear "unparseable PreToolUse payload on stdin"
fi
```

**Why it is wrong** — `jq` exits 0 on empty stdin (no input values, filter never runs) and on any well-formed JSON whose `.tool_input.command` is absent or renamed. In both cases `CMD` is the empty string, every `grep` below misses, the hook exits 0, and `abstain_unclear` is never called — no line in `validate-bash-unclear.log`. That is precisely the failure described on lines 24-26 ("CMD went empty, EVERY danger pattern missed … silently disabled itself"), which this block is supposed to make loud.

---

### 12. Denied and warned commands are never written to the audit log

**Where** — lines 77, 90 and 243:
```bash
  exit 0
```
```bash
echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [$SID] $CMD" >> ~/.claude/logs/bash-commands.log
```

**Why it is wrong** — `deny()` and `warn()` both `exit 0` from inside the function, so control never reaches line 243. Every command that trips a rule — the `rm -rf /`, the unscoped `pkill`, the DDL, the `--no-verify` — is absent from `bash-commands.log`; the file labelled "Log command for audit" contains only the commands that passed. Post-incident, the log shows no trace of the events it would be consulted for.

---

### 13. The multi-line log fix does not actually anchor multi-line commands

**Where** — line 243:
```bash
echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [$SID] $CMD" >> ~/.claude/logs/bash-commands.log
```

**Why it is wrong** — `$CMD` is unquoted-for-content: an embedded newline is emitted as a newline, so a heredoc or multi-line command still writes N lines of which only the first carries the timestamp and session id. Lines 237-239 claim the change fixes "a multi-line command shredded the line structure with no way to tell a continuation line from a new entry" and makes entries "greppable by session" — continuation lines remain unattributed, and a continuation line beginning with `[` is still indistinguishable from a new entry.

---

### 14. `drizzle-kit push` is denied on raw text, including inside quoted strings

**Where** — line 169:
```bash
if echo "$CMD" | grep -qE 'drizzle-kit[[:space:]]+push'; then
```

**Why it is wrong** — no quote or command-position awareness at all. `git commit -m "revert drizzle-kit push, use pnpm generate"` and `grep -r "drizzle-kit push" docs/` are denied with "drizzle-kit push bypasses migration history". The same class affects the DDL clause on lines 163-164: its two conditions are independent greps over the whole command, so `git commit -m "migration: CREATE TABLE users for sqlite3"` satisfies both and is denied — the comment on lines 159-160 claims commit messages discussing DDL are safe, but that only holds for messages that happen not to name a database tool.

---

### 15. The "own worktree" escape hatch is an unanchored substring test

**Where** — line 151:
```bash
    if [[ -n "${PWD##*/}" ]] && echo "$pk" | grep -qF -- "${PWD##*/}"; then
```

**Why it is wrong** — the only check is `-n` on the basename; there is no check that the basename is a worktree-shaped or distinctive name. Any session whose cwd basename is a string that appears in the kill pattern for unrelated reasons — e.g. cwd `…/bats`, or cwd `…/main` running `pkill -f "bats main"` — gets `continue`d and the machine-wide `pkill -9 -f bats` proceeds unblocked, which is the exact event (lines 121-127) the clause was written after.
