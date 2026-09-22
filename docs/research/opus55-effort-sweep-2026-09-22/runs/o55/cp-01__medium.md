# Review of `hooks/validate-bash.sh`

I found 13 defects.

---

**1. A broken library makes every argv-aware check pass silently**

- **What:** `HAVE_IS_TRUE_FLAG=1` is set whether or not the `source` succeeded, and any return code other than 0 or 2 is treated as "not a flag".
- **Where:**
  - Line 50–51: `source "$LIB_DIR/is-true-flag.sh"` / `HAVE_IS_TRUE_FLAG=1`
  - Line 101–102: `[[ "$rc" == "0" || "$rc" == "2" ]] && return 0` / `return 1`
- **Why it is wrong:** Suppose `lib/is-true-flag.sh` exists but has a syntax error, or no longer defines `is_true_flag`. Then `is_true_flag` returns 127, and `check_real_flag` returns 1 for every flag. As a result, `--no-verify`, `--no-gpg-sign`, `git add -f` and `git add --force` are all allowed. Nothing is logged, even though the comment claims "unclear" cases fail safe.

---

**2. Bare `rm -rf /` is not hard-denied**

- **What:** The root-delete pattern needs at least one more character after `/`.
- **Where:** Line 115: `if echo "$CMD" | grep -qE '(rm[[:space:]]+-rf[[:space:]]+/[^a-zA-Z]|rm[[:space:]]+-rf[[:space:]]+\$HOME|...`
- **Why it is wrong:**
  - `rm -rf /` at the end of the command has nothing after `/`, so `/[^a-zA-Z]` fails. The command falls through to the rm clause and only gets an "ask", despite the deny message naming `rm -rf /`.
  - `rm -fr /` and `rm -r -f /` are not matched by this pattern at all.

---

**3. `rm -rf ~/<anything>` is hard-denied as "system damage"**

- **What:** `~(/|$|[[:space:]])` matches `~/` followed by any path.
- **Where:** Line 115, same line as above: `...rm[[:space:]]+-rf[[:space:]]+~(/|$|[[:space:]])...`
- **Why it is wrong:** `rm -rf ~/tmp/scratch` is denied as if it were `rm -rf ~`.

---

**4. A `|` inside a quoted pkill pattern hides the gate name**

- **What:** Kill occurrences are cut at the first `|`, even when that `|` is inside a quoted regex.
- **Where:** Line 137: `PK_OCCURRENCES=$(echo "$CMD" | grep -oE '(pkill|killall)[^;&|]*' || true)`
- **Why it is wrong:** For `pkill -f 'x|bats-core/bats'`, the captured occurrence is `pkill -f 'x`. It contains no gate name, so line 141 `continue`s. The machine-wide kill is allowed.

---

**5. The command-position test misses common ways to invoke pkill/killall**

- **What:** Only a bare `pkill`/`killall`, optionally preceded by a plain `sudo `, counts as being in command position.
- **Where:** Line 136: `| grep -qE '^(sudo[[:space:]]+)?(pkill|killall)([[:space:]]|$)'; then`
- **Why it is wrong:** These all skip the unscoped-gate-kill deny entirely:
  - `/usr/bin/pkill -f bats`
  - `sudo -n pkill -f bats`
  - `env pkill ...`, `nohup pkill ...`, `timeout 5 pkill ...`
  - `xargs pkill`

---

**6. The "own worktree name" exemption is a raw substring test**

- **What:** Any occurrence that contains the basename of `$PWD` anywhere is treated as scoped.
- **Where:** Line 149: `if [[ -n "${PWD##*/}" ]] && echo "$pk" | grep -qF -- "${PWD##*/}"; then`
- **Why it is wrong:** Take a session whose directory is named `main` (or `tests`, `bats`, `src`, …). The documented epidemic command `pkill -f "ship-land.sh --trunk main"` contains `main`, so it is exempted and kills gates machine-wide.

---

**7. The target test reads raw text, including quoted message bodies**

- **What:** Once any real pkill is present, occurrences are also collected from quoted text.
- **Where:** Line 137 (same line as #4): `PK_OCCURRENCES=$(echo "$CMD" | grep -oE '(pkill|killall)[^;&|]*' || true)`
- **Why it is wrong:** `pkill myserver; git commit -m "stop pkill -f bats"` is denied. The real pkill passes the position test, and then the message-body text supplies the gate target. This is the raw-text decision the comment says the clause avoids.

---

**8. The DDL guard misses schema changes and still blocks commit messages that mention a DB tool**

- **What:** The DDL keyword list is incomplete, and the "database context" test also runs on raw text.
- **Where:** Lines 161–162:
  - `if echo "$CMD" | grep -qiE '\b(turso|sqlite3?|psql|mysql|mariadb|libsql|drizzle-kit[[:space:]]+(push|drop|migrate))\b' \`
  - `&& echo "$CMD" | grep -qiE '\b(DROP[[:space:]]+TABLE|DROP[[:space:]]+DATABASE|DROP[[:space:]]+INDEX|ALTER[[:space:]]+TABLE|CREATE[[:space:]]+TABLE|TRUNCATE[[:space:]]+TABLE)\b'; then`
- **Why it is wrong:**
  - `sqlite3 db "CREATE INDEX ..."`, `CREATE VIEW`, `DROP VIEW` and `CREATE TRIGGER` are all allowed, although the rule says "all schema changes".
  - `git commit -m "fix: block DROP TABLE in sqlite3"` is denied, which is the false positive the comment claims to avoid.

---

**9. The `git add -f/--force` guard ties the flag to `git add` without checking they are in the same command**

- **What:** The flag check and the `git add` check look at the whole command string independently.
- **Where:**
  - Line 172: `if check_real_flag "--force" && echo "$CMD" | grep -qE 'git[[:space:]]+add\b'; then`
  - Line 175: `if check_real_flag "-f" && echo "$CMD" | grep -qE 'git[[:space:]]+add\b'; then`
- **Why it is wrong:**
  - `git add . && rm -f tmp.txt` and `git add . && git push --force` are denied as "git add -f".
  - `git add -Af x`, `git add -fA` and `git -C dir add -f x` are allowed. The bundled token is not `-f`, and `git -C dir add` does not match `git[[:space:]]+add`.

---

**10. `git commit -n` detection misses bundled and long-global forms, and matches message bodies**

- **What:** `-n` has to be a standalone token preceded by whitespace, and only `-x value` style global options are allowed between `git` and `commit`.
- **Where:** Line 194: `if echo "$CMD" | grep -qE 'git([[:space:]]+-[a-zA-Z]+[[:space:]]+[^[:space:]]+)*[[:space:]]+commit\b[^|&;]*[[:space:]]-n\b'; then`
- **Why it is wrong:**
  - These all skip pre-commit hooks without being caught:
    - `git commit -nm "msg"` (no word boundary between `n` and `m`)
    - `git commit -an -m x` (no whitespace directly before `-n`)
    - `git --no-pager commit -n` (long global option)
  - `git commit -m "handle -n flag"` is denied.

---

**11. `git clean -x` is missed when `x` is in a later flag group**

- **What:** Only the first flag group after `git clean` is inspected.
- **Where:** Line 207: `if echo "$CMD" | grep -qE 'git[[:space:]]+clean[[:space:]]+-[a-zA-Z]*[xX]'; then`
- **Why it is wrong:** `git clean -f -x` and `git clean -fd -X` run with no warning. `[a-zA-Z]*` cannot cross the space after `-f`.

---

**12. The rm-rf per-occurrence check only sees the first target and is fooled by traversal and absolute paths**

- **What:** Each occurrence captures one target, the result is then prefix-matched against the safe list, and a leading `/` is stripped first.
- **Where:**
  - Line 215: `RM_OCCURRENCES=$(echo "$CMD" | grep -oE 'rm[[:space:]]+-(r|rf|fr)[[:space:]]+[^[:space:];&|]+' || true)`
  - Line 221: `target_stripped=$(echo "$target" | sed -E 's|^\./||; s|^/||')`
  - Line 222: `if ! echo "$target_stripped" | grep -qE "^${SAFE_RM_TARGETS}(/|$)"; then`
- **Why it is wrong:** These all pass without any prompt:
  - `rm -rf node_modules src` (only `node_modules` is checked)
  - `rm -rf dist/../src`
  - `rm -rf /build` (the absolute path is stripped to `build`)
  - `rm -Rf src` and `rm -rfv src` (the flag forms are not matched at all)

---

**13. Commands the hook sent to "ask" are never written to the audit log**

- **What:** `warn` exits before the logging block runs.
- **Where:**
  - Line 89: `exit 0` (inside `warn`)
  - Line 241: `echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [$SID] $CMD" >> ~/.claude/logs/bash-commands.log`
- **Why it is wrong:** When the user approves an ask for `git reset --hard`, `git clean -x` or a non-artifact `rm -rf`, the command runs but never reaches the audit log. These are exactly the destructive commands that most need an audit trail.
