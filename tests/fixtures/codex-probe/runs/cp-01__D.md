# Review — `hooks/validate-bash.sh`

Line numbers are counted from `#!/bin/bash` = line 1.

---

## A. Deny gates that fail to fire (guard does not cover the class it claims)

### A1. `rm -rf /` with nothing after the slash is not denied

**Where** — line 116:
```bash
if echo "$CMD" | grep -qE '(rm[[:space:]]+-rf[[:space:]]+/[^a-zA-Z]|rm[[:space:]]+-rf[[:space:]]+\$HOME|rm[[:space:]]+-rf[[:space:]]+~(/|$|[[:space:]])|sudo[[:space:]]+rm|:\(\)\{[[:space:]]*:\|:&[[:space:]]*\};:)'; then
```

**Why** — the first alternative requires a character after `/` (`[^a-zA-Z]`), with no end-of-line alternative — unlike the `~` alternative right beside it, which has `(/|$|[[:space:]])`. For the command string `rm -rf /` (the canonical form, nothing following) there is no next character, so the alternative cannot match and the deny is skipped. The command then falls through to the rm-warn block at 217–229, where the target `/` strips to the empty string and fails the safe-list, so the single most catastrophic command in the file's threat model is downgraded from a hard block to a user "ask" prompt.

### A2. Only the literal flag spelling `-rf` is denied

**Where** — line 116 (same line as A1).

**Why** — every `rm` alternative hard-codes `-rf`. `rm -fr /x`, `rm -Rf /x`, `rm -rfv /x`, `rm -r -f /x` and `rm --recursive --force /x` all delete the same thing and none match. The author knew the orderings vary — the warn clause at line 217 accepts `-(r|rf|fr)` — so `rm -fr ~` and `rm -fr $HOME` reach only the "ask" path, not the deny.

### A3. `rm -rf "$HOME"` / `rm -rf ${HOME}` are not denied

**Where** — line 116 (same line as A1).

**Why** — the alternative is `rm[[:space:]]+-rf[[:space:]]+\$HOME`, which requires the literal characters `$HOME` immediately after the whitespace. The shell-idiomatic quoted form `rm -rf "$HOME"` puts a `"` there, and `rm -rf ${HOME}` puts `${`. Both wipe the home directory; neither matches, so both are only warned about, not blocked.

### A4. The fork-bomb pattern matches one exact spelling

**Where** — line 116 (same line as A1), fragment `:\(\)\{[[:space:]]*:\|:&[[:space:]]*\};:`.

**Why** — `:|:&` must be contiguous. The equally valid `:(){ : | : & };:` (spaces around the pipe and the ampersand) does not match, and neither does any renamed variant such as `b(){ b|b& };b`. The deny message claims to block "fork bomb"; it blocks one literal transcription of it.

### A5. The pkill position test only recognises `pkill` as the literal first word

**Where** — lines 137–138:
```bash
if printf '%s' "$CMD_NOQ" | sed 's/[&|()]/;/g' | tr ';' '\n' | sed 's/^[[:space:]]*//' \
     | grep -qE '^(sudo[[:space:]]+)?(pkill|killall)([[:space:]]|$)'; then
```

**Why** — the anchor admits only `pkill`/`killall`, optionally preceded by a bare `sudo`. `/usr/bin/pkill -9 -f bats-core/bats`, `command pkill -f bats`, `env pkill -f bats`, `sudo -n pkill -f bats`, and `xargs pkill -f bats` are all the machine-wide kill this clause exists to stop, and none of them opens the gate — the entire block, including the deny at 154, is skipped.

### A6. Apostrophes inside double-quoted text erase a real `pkill` before the position test sees it

**Where** — line 136:
```bash
CMD_NOQ=$(printf '%s' "$CMD" | sed -e "s/'[^']*'/''/g" -e 's/"[^"]*"/""/g')
```

**Why** — the single-quote pass runs first, globally, with no knowledge of double-quote context. Given
`git commit -m "don't panic" && pkill -9 -f bats && git commit -m "it's fixed"`,
the first pass pairs the apostrophe in `don't` with the apostrophe in `it's` and replaces everything between them — including `pkill -9 -f bats` — with `''`. `CMD_NOQ` becomes `git commit -m ""`, no line begins with `pkill`, the gate at 137 never opens, and the broad kill runs. Apostrophes in commit messages are ordinary, so this is reachable without adversarial intent.

### A7. The scope tests are substring searches over the whole clause, including comments and unrelated text

**Where** — lines 147 and 151:
```bash
    if echo "$pk" | grep -qE '\$PWD|\$\{PWD|\$\(pwd|`pwd|\$\(basename|(^|[[:space:]])-P[[:space:]]|\.worktrees/|(^|[^a-zA-Z0-9])wt-[a-zA-Z0-9]'; then
```
```bash
    if [[ -n "${PWD##*/}" ]] && echo "$pk" | grep -qF -- "${PWD##*/}"; then
```

**Why** — `$pk` is everything up to the next `;`, `&` or `|`, so a trailing shell comment is part of it. `pkill -9 -f bats-core/bats  # cleanup for wt-abc` matches `wt-[a-zA-Z0-9]` and is treated as worktree-scoped; `pkill -9 -f bats  # run from $(pwd)` matches `\$\(pwd`. Neither is scoped to anything — the `-f` pattern is still machine-wide, but the deny is skipped. Line 151 has the same shape: any occurrence whose text happens to contain the current directory's basename anywhere (e.g. `pkill -f "ship-land.sh --trunk main"` when run from a directory named `main` — the second of the two commands the header comment names as the root cause) is accepted as scoped.

### A8. `git commit -nm "msg"` bypasses the `-n` rule

**Where** — line 196:
```bash
if echo "$CMD" | grep -qE 'git([[:space:]]+-[a-zA-Z]+[[:space:]]+[^[:space:]]+)*[[:space:]]+commit\b[^|&;]*[[:space:]]-n\b'; then
```

**Why** — the final fragment requires `-n` to be preceded by whitespace. Bundled short options are standard git usage: `git commit -nm "msg"`, `git commit -an`, `git commit -amn "msg"` all pass `--no-verify` to git and none of them match, so the CLAUDE.md critical rule #2 guard is silently skipped.

### A9. `git clean` warn only inspects the first flag token

**Where** — line 209:
```bash
if echo "$CMD" | grep -qE 'git[[:space:]]+clean[[:space:]]+-[a-zA-Z]*[xX]'; then
```

**Why** — the pattern requires the bundle containing `x` to be the token immediately after `clean`. `git clean -fd -x`, `git clean --force -x` and `git clean -d -X` all remove gitignored files and none match, so the "may include paid assets" prompt never appears — despite the comment at 208 claiming it matches "any flag bundle containing x or X".

### A10. The rm-warn extraction misses common flag forms

**Where** — line 217:
```bash
RM_OCCURRENCES=$(echo "$CMD" | grep -oE 'rm[[:space:]]+-(r|rf|fr)[[:space:]]+[^[:space:];&|]+' || true)
```

**Why** — `-(r|rf|fr)` must be followed by whitespace, so `rm -rfv src`, `rm -Rf src`, `rm -r -f src` and `rm --recursive src` produce no occurrence at all. `RM_OCCURRENCES` is empty, the block is skipped, and a recursive delete of a non-artifact target proceeds with no prompt.

### A11. Stripping a leading `/` makes root-level paths look like build artifacts

**Where** — lines 223–224:
```bash
    target_stripped=$(echo "$target" | sed -E 's|^\./||; s|^/||')
```
```bash
    if ! echo "$target_stripped" | grep -qE "^${SAFE_RM_TARGETS}(/|$)"; then
```

**Why** — `rm -rf /build`, `rm -rf /target`, `rm -rf /out` and `rm -rf /dist` strip to `build`, `target`, `out`, `dist`, all of which are on the safe list, so the warn is skipped entirely. These are absolute paths at the filesystem root, not this project's build output. (Line 116 also misses them: `/b`, `/t`, `/o`, `/d` are letters, so `[^a-zA-Z]` fails.) The result is that a delete at `/` proceeds with no deny and no ask.

### A12. The safe-target match is prefix-only, so `..` segments escape it

**Where** — line 224 (same line as A11).

**Why** — the anchor is `^SAFE(/|$)`; anything after the first path component is unchecked. `rm -rf dist/../../src` and `rm -rf node_modules/../..` match `^dist(/…)` and `^node_modules(/…)` respectively, are classified as build artifacts, and delete targets outside the safe directory with no prompt.

### A13. The payload guard tests jq's exit status, not whether a command was actually extracted

**Where** — lines 40–42:
```bash
if ! CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null); then
  abstain_unclear "unparseable PreToolUse payload on stdin"
fi
```

**Why** — `jq` exits 0 when stdin is empty (zero inputs, no output) and when the JSON parses but `.tool_input.command` is absent or null. In both cases `CMD` is the empty string, every pattern below misses, and the script runs to `exit 0` at line 244 without calling `abstain_unclear` — which is exactly the "CMD went empty, EVERY danger pattern missed, and the hook exited 0" failure the comment at 24–27 says this block closes, and exactly the case that is supposed to leave the "one loud line". The condition the guard was written for is emptiness of `CMD`; what it actually tests is jq's exit status, which is a strict subset.

---

## B. Denials issued on the wrong premise

### B1. The system-damage check reads raw text, so mentions are blocked

**Where** — line 116 (see A1), fragment `sudo[[:space:]]+rm`.

**Why** — there is no command-position test on this clause. `git commit -m "docs: warn against sudo rm in the runbook"` matches `sudo[[:space:]]+rm` inside the quoted message body and is denied as "potential system damage". The comment at 131–133, twenty lines below, states that deciding on raw text is "the exact defect this clause exists to stop" — the clause immediately above it does precisely that.

### B2. A quoted *mention* of pkill is denied once any real pkill opens the gate

**Where** — line 139:
```bash
  PK_OCCURRENCES=$(echo "$CMD" | grep -oE '(pkill|killall)[^;&|]*' || true)
```

**Why** — the position test at 137–138 runs once, on the quote-stripped copy, for the command as a whole; occurrences are then extracted from the *original* `$CMD`, so text inside quotes becomes its own occurrence and is judged as if it were a command. For
`pkill -f "bats.*${PWD##*/}" && git commit -m "chore: stop using pkill -f bats"`,
occurrence 1 is correctly recognised as scoped, but occurrence 2 — `pkill -f bats"`, lifted out of the commit message — targets `bats`, matches no scope pattern, and triggers the deny at 154. A correctly scoped command is blocked because a message body mentions the thing it fixed.

### B3. `git add` and the force flag are matched independently across the whole command

**Where** — lines 174 and 177:
```bash
if check_real_flag "--force" && echo "$CMD" | grep -qE 'git[[:space:]]+add\b'; then
```
```bash
if check_real_flag "-f" && echo "$CMD" | grep -qE 'git[[:space:]]+add\b'; then
```

**Why** — the two conditions are never tied to the same clause, and `check_real_flag` scans all of `$CMD`. `git add -A && rm -f tmp.log` has a real `-f` argv token (belonging to `rm`) and contains `git add`, so it is denied with "git add -f blocked — gitignored files are intentionally excluded", which describes something the command does not do. Same for `git add . && npm ci --force`.

### B4. `-n` is matched anywhere in the clause, including inside the message body

**Where** — line 196 (see A8), fragment `[^|&;]*[[:space:]]-n\b`.

**Why** — after `git commit` the pattern accepts any run of non-`|&;` characters followed by ` -n`, with no quote awareness. `git commit -m "docs: explain the sed -n idiom"` matches the ` -n` inside the quoted message and is denied as a `--no-verify` bypass. The file makes quoted-body awareness its explicit design goal for `--no-verify` (comment at 182–183) and drops it here.

### B5. The DDL guard's stated commit-message exemption does not hold

**Where** — lines 163–164:
```bash
if echo "$CMD" | grep -qiE '\b(turso|sqlite3?|psql|mysql|mariadb|libsql|drizzle-kit[[:space:]]+(push|drop|migrate))\b' \
   && echo "$CMD" | grep -qiE '\b(DROP[[:space:]]+TABLE|DROP[[:space:]]+DATABASE|DROP[[:space:]]+INDEX|ALTER[[:space:]]+TABLE|CREATE[[:space:]]+TABLE|TRUNCATE[[:space:]]+TABLE)\b'; then
```

**Why** — both greps run over the entire command with no positional or clause-level linkage, so "database-command context" is only ever "the two strings co-occur somewhere in the text". The comment at 159–160 promises no false positive on `"fix: block DROP TABLE in migration"`, but `git commit -m "fix: block DROP TABLE in the sqlite migration"` satisfies both greps from a single quoted string and is denied; so is `sqlite3 app.db ".schema" && git commit -m "notes on CREATE TABLE"`.

---

## C. Audit trail

### C1. Denied and warned commands are never recorded in the audit log

**Where** — line 243 (reached only after every check passes); `deny()` line 77 and `warn()` line 90 both `exit 0` first:
```bash
echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [$SID] $CMD" >> ~/.claude/logs/bash-commands.log
```

**Why** — any command that triggers `deny` or `warn` exits from inside the function and never reaches line 243. The one log described as "Log command for audit" therefore contains every command the hook allowed and none that it acted on — the blocked attempts, which are the entries an audit would be looking for, are the only ones systematically absent.

### C2. The multi-line log problem the comment claims to have fixed is not fixed

**Where** — line 243 (same line as C1); claim at lines 237–239:
```bash
echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [$SID] $CMD" >> ~/.claude/logs/bash-commands.log
```

**Why** — `$CMD` is written raw. When the tool input is a multi-line command (heredoc, multi-line script), only its first line carries the timestamp and session prefix; the remaining lines are appended unprefixed and unescaped, so "no way to tell a continuation line from a new entry" — the stated defect — still holds, and a command containing a line that looks like `[2026-08-11T00:00:00Z] [sid] …` is indistinguishable from a genuine entry.