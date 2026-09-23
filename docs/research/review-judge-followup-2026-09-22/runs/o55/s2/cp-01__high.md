# Review of `hooks/validate-bash.sh`: 19 defects

**1. The payload guard misses the "CMD went empty" case it was written for.**
- **Where:** line 40, `if ! CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null); then`
- **Why it is wrong:** The comment says an empty `CMD` must never pass silently. But `jq` exits 0 in two such cases: when stdin is empty, and when the payload is valid JSON without `.tool_input.command` (for example, a renamed field). In both cases `// empty` gives an empty `CMD`, the `if` is not taken, and no abstain line is logged. Every pattern then misses and the hook exits 0 with no signal.

**2. Unexpected return codes from `is_true_flag` are treated as "not a flag", so the check fails open.**
- **Where:** line 102, `[[ "$rc" == "0" || "$rc" == "2" ]] && return 0`
- **Why it is wrong:** The comment says "fail safe = block". But any status other than 0 or 2 falls through to `return 1`. That includes 127 (the function is not defined after `source`), 126, or a crashed helper's exit code. In those cases `--no-verify`, `--no-gpg-sign`, `--force` and `-f` are all silently allowed. The "fall back silently on a per-call basis" promised at line 45 does not exist.

**3. The legacy flag detector only matches an exact standalone token, so bundled short flags pass.**
- **Where:** line 107, `local pattern="(^|[[:space:]])${flag//./\\.}([[:space:]]|\$)"`
- **Why it is wrong:** With `VALIDATE_BASH_LEGACY=1`, or with the lib missing, `git add -Af secret.env` or `git add -fA` does not match `-f` between spaces. The force-add goes through.

**4. The hard deny misses a bare `rm -rf /` at the end of the command.**
- **Where:** line 116, `if echo "$CMD" | grep -qE '(rm[[:space:]]+-rf[[:space:]]+/[^a-zA-Z]|...`
- **Why it is wrong:** `/[^a-zA-Z]` needs one more character after the slash. The canonical `rm -rf /`, with nothing after it, does not match. It only reaches the rm-warn block at line 224, so the "catastrophic" deny becomes an `ask`.

**5. The system-damage deny only recognizes the exact spellings `-rf` and a bare `$HOME`.**
- **Where:** line 116, `rm[[:space:]]+-rf[[:space:]]+/[^a-zA-Z]|rm[[:space:]]+-rf[[:space:]]+\$HOME|rm[[:space:]]+-rf[[:space:]]+~(/|$|[[:space:]])`
- **Why it is wrong:** None of these are denied: `rm -fr /*`, `rm -Rf /*`, `rm -r -f /*`, `rm --recursive --force ~`, `rm -rf "$HOME"`, `rm -rf ${HOME}`. Some then get only an `ask` from the later block, and some get nothing (see item 17).

**6. The pkill/killall position test only recognizes a bare name, optionally after a plain `sudo`.**
- **Where:** line 138, `| grep -qE '^(sudo[[:space:]]+)?(pkill|killall)([[:space:]]|$)'; then`
- **Why it is wrong:** These all reach the program in command position but fail the test: `/usr/bin/pkill -f bats`, `\pkill -f bats`, `command pkill …`, `env pkill …`, `timeout 5 pkill …`, `nohup pkill …`, `xargs pkill …`, `sudo -n pkill …`. The whole clause is skipped, and the machine-wide kill goes through.

**7. The quote stripping works line by line, so quoted or heredoc message text can pass the position test.**
- **Where:** line 136, `CMD_NOQ=$(printf '%s' "$CMD" | sed -e "s/'[^']*'/''/g" -e 's/"[^"]*"/""/g')`
- **Why it is wrong:** `sed` works one line at a time, so a quote that spans lines is never removed. Heredoc bodies are never quoted at all. Consider a multi-line commit message such as `git commit -m "$(cat <<'EOF'` whose body has a line starting with `pkill -f bats …`. That line looks like command position, and the commit is denied for merely mentioning the command. This is the exact false positive the comment says is prevented.

**8. After the position test passes, the scan reads every pkill/killall in the original text, including quoted ones.**
- **Where:** line 139, `PK_OCCURRENCES=$(echo "$CMD" | grep -oE '(pkill|killall)[^;&|]*' || true)`
- **Why it is wrong:** Take `pkill -f myserver; git commit -m "note: never pkill -f bats"`. The harmless real `pkill` passes the position test. The quoted mention `pkill -f bats"` is then evaluated as a kill, and the command is denied. The decision rests on text the comment says only "MENTIONS the thing".

**9. Any mention of `.worktrees/` counts as "scoped to ONE worktree".**
- **Where:** line 147, `if echo "$pk" | grep -qE '\$PWD|\$\{PWD|\$\(pwd|`pwd|\$\(basename|(^|[[:space:]])-P[[:space:]]|\.worktrees/|(^|[^a-zA-Z0-9])wt-[a-zA-Z0-9]'; then`
- **Why it is wrong:** `pkill -f "\.worktrees/.*bats"` or `pkill -f ".worktrees/"` matches the bats processes of every worktree, which means every peer session. The line still lets it through as scoped. `$(basename` is accepted the same way, whatever it is the basename of.

**10. Accepting the hook's own directory basename as scope is wrong when that directory contains the worktrees.**
- **Where:** line 151, `if [[ -n "${PWD##*/}" ]] && echo "$pk" | grep -qF -- "${PWD##*/}"; then`
- **Why it is wrong:** Suppose the session runs in the main checkout, for example `.../reso`. Then `pkill -f "bats.*reso"` counts as self-scoped. But every worktree path (`reso/.worktrees/wt-*`) contains `reso`, so the kill hits every session's gates. The same happens when the basename is a short or common word that appears in the pattern, such as `tests` in `pkill -f "bats tests/"`.

**11. The DDL deny does not cover the class it names.**
- **Where:** line 164, `&& echo "$CMD" | grep -qiE '\b(DROP[[:space:]]+TABLE|DROP[[:space:]]+DATABASE|DROP[[:space:]]+INDEX|ALTER[[:space:]]+TABLE|CREATE[[:space:]]+TABLE|TRUNCATE[[:space:]]+TABLE)\b'; then`
- **Why it is wrong:** "All schema changes must go through Drizzle migrations", yet these pass even in a `sqlite3`/`turso` context: `CREATE INDEX`, `CREATE UNIQUE INDEX`, `CREATE VIEW`, `DROP VIEW`, `CREATE TRIGGER`, `DROP TRIGGER`. `DROP INDEX` is blocked while `CREATE INDEX` is not.

**12. The `--force` and `-f` checks are not tied to the `git add` clause.**
- **Where:** line 174, `if check_real_flag "--force" && echo "$CMD" | grep -qE 'git[[:space:]]+add\b'; then`, and line 177, `if check_real_flag "-f" && echo "$CMD" | grep -qE 'git[[:space:]]+add\b'; then`
- **Why it is wrong:** The flag check and the `git add` check run independently over the whole command. So `git add src/x.ts && rm -f tmp.log` and `git add . && git push --force-with-lease`-style compounds with `--force` are denied as "force-adding bypasses .gitignore", even though no force-add happened.

**13. The `git commit -n` check misses bundled short flags and global long options.**
- **Where:** line 196, `if echo "$CMD" | grep -qE 'git([[:space:]]+-[a-zA-Z]+[[:space:]]+[^[:space:]]+)*[[:space:]]+commit\b[^|&;]*[[:space:]]-n\b'; then`
- **Why it is wrong:** In `git commit -nm "msg"` and `git commit -anm "msg"`, `-n` is followed by a letter, so `-n\b` fails and the hooks are skipped. `git --no-pager commit -n` also passes, because `--no-pager` does not fit `-[a-zA-Z]+`, so `git` is never followed directly by `commit`.

**14. The same `git commit -n` regex fires on `-n` inside a quoted message body.**
- **Where:** line 196, same line as item 13.
- **Why it is wrong:** `[^|&;]*` runs straight through quotes. So `git commit -m "fix: pass -n to head"` is denied as a `--no-verify` bypass. This is the message-body false positive the file says it is aware of.

**15. The `git reset --hard` warning only matches when `--hard` directly follows `reset`, and `git` directly precedes it.**
- **Where:** line 203, `if echo "$CMD" | grep -qE 'git[[:space:]]+reset[[:space:]]+--hard\b'; then`
- **Why it is wrong:** `git reset -q --hard`, `git -C ../wt reset --hard` and `git --no-pager reset --hard` all destroy uncommitted work without the `ask`.

**16. The `git clean -x` warning only looks at the first flag bundle.**
- **Where:** line 209, `if echo "$CMD" | grep -qE 'git[[:space:]]+clean[[:space:]]+-[a-zA-Z]*[xX]'; then`
- **Why it is wrong:** The comment says "any flag bundle", but `git clean -f -x`, `git clean -fd -X` and `git clean -n -x` do not match, because the first bundle has no `x`. The ignored (paid) assets are deleted with no `ask`.

**17. The rm target check only reads the first operand, so the "compound escape hatch" is still open within a single rm.**
- **Where:** line 217, `RM_OCCURRENCES=$(echo "$CMD" | grep -oE 'rm[[:space:]]+-(r|rf|fr)[[:space:]]+[^[:space:];&|]+' || true)`
- **Why it is wrong:** `rm -rf node_modules src ~/Documents` captures only `node_modules`, which is on the safe list, and passes silently. The same regex also ignores `-R`, `-Rf`, `-rfv` and `--recursive`, so `rm -Rf src` gets no warning at all.

**18. A leading `/` is stripped before the safe-list match, so absolute system paths count as build artifacts.**
- **Where:** line 223, `target_stripped=$(echo "$target" | sed -E 's|^\./||; s|^/||')`
- **Why it is wrong:** `rm -rf /build`, `rm -rf /target`, `rm -rf /out` and `rm -rf /dist` become `build`, `target` and so on, which match `SAFE_RM_TARGETS`. The hard deny misses them too, since a letter follows `/`. Deleting top-level absolute directories passes with no deny and no warning.

**19. The safe-target match is a prefix match, so path traversal escapes it.**
- **Where:** line 224, `if ! echo "$target_stripped" | grep -qE "^${SAFE_RM_TARGETS}(/|$)"; then`
- **Why it is wrong:** `rm -rf node_modules/../src` and `rm -rf dist/../../..` start with a safe name followed by `/`. They are treated as build artifacts and pass without the `ask`, even though they delete source or parent directories.
