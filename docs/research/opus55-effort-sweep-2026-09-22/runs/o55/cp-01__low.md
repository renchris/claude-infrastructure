# Review of `hooks/validate-bash.sh`

I found 8 defects.

---

### 1. A bare `rm -rf /` escapes the hard deny

- **What:** The system-damage regex needs a character after the `/`, so `rm -rf /` at the end of the command is not denied.
- **Where:** line with
  `if echo "$CMD" | grep -qE '(rm[[:space:]]+-rf[[:space:]]+/[^a-zA-Z]|rm[[:space:]]+-rf[[:space:]]+\$HOME|...`
- **Why it is wrong:**
  - `/[^a-zA-Z]` requires one more non-letter character after the slash.
  - For the command `rm -rf /` (or `sudo`-less `... && rm -rf /`), there is no such character, so the alternative fails.
  - The command then falls through to the rm warn block. There the target strips to empty and gets only an "ask", so a catastrophic deny is downgraded to a prompt.

### 2. Only the first operand of `rm -rf` is checked

- **What:** Only the first path after `rm -rf` is checked against the safe list.
- **Where:** `RM_OCCURRENCES=$(echo "$CMD" | grep -oE 'rm[[:space:]]+-(r|rf|fr)[[:space:]]+[^[:space:];&|]+' || true)`
- **Why it is wrong:**
  - Take `rm -rf dist src ~/work`. The match captures only `dist`, which is safe, so no warning is raised.
  - `src` and `~/work` are deleted unchecked. This is the same escape-hatch class that the per-clause comment claims to close.

### 3. Other spellings of `rm -rf` are not recognised

- **What:** The rm guards (both deny and warn) only recognise the exact spellings `-r`, `-rf` and `-fr`.
- **Where:**
  - `rm[[:space:]]+-(r|rf|fr)[[:space:]]+` in the `RM_OCCURRENCES` line
  - `rm[[:space:]]+-rf[[:space:]]+` in the system-damage line
- **Why it is wrong:** These forms all pass with no deny and no ask:
  - `rm -Rf ~`
  - `rm -r -f /`
  - `rm -rfv src`
  - `rm --recursive --force ~`

### 4. Absolute paths and traversal pass as "safe" targets

- **What:** The safe-target test strips a leading `/` and matches only a prefix, so absolute paths and `..` traversal count as safe.
- **Where:**
  - `target_stripped=$(echo "$target" | sed -E 's|^\./||; s|^/||')`
  - `if ! echo "$target_stripped" | grep -qE "^${SAFE_RM_TARGETS}(/|$)"; then`
- **Why it is wrong:**
  - `rm -rf /build` or `rm -rf /target` (root-level directories) are treated as build artifacts.
  - `rm -rf node_modules/../src` matches `node_modules/` and passes silently.

### 5. Bundled short flags to `git add` are missed

- **What:** `git add -f` detection misses bundled short flags.
- **Where:** `if check_real_flag "-f" && echo "$CMD" | grep -qE 'git[[:space:]]+add\b'; then`
- **Why it is wrong:**
  - `git add -Af secret.env` or `git add -fA` contains no standalone `-f` token.
  - The force-add bypass of `.gitignore` is therefore not blocked.

### 6. `git add` and `-f` are not required to be in the same command

- **What:** The same `git add` checks look for the flag and `git add` independently anywhere in the command.
- **Where:** the same two `if check_real_flag "--force" / "-f" && ... 'git[[:space:]]+add\b'` lines.
- **Why it is wrong:**
  - `git add . && rm -f tmp.txt` is denied as "git add -f".
  - This is a false deny: the decision is taken on an unproven premise, since the flag is attributed to `git add` when it belongs to `rm`.

### 7. The "worktree-scoped" exemption can match unrelated text

- **What:** The exemption accepts any occurrence whose text contains the current directory's basename as a substring.
- **Where:** `if [[ -n "${PWD##*/}" ]] && echo "$pk" | grep -qF -- "${PWD##*/}"; then`
- **Why it is wrong:**
  - If the session's cwd basename is a common word such as `tests`, `bats` or `app`, the exemption fires on unscoped commands.
  - Example: with cwd `.../tests`, `pkill -f "bats tests/"` is considered scoped and allowed.
  - That command kills every peer's gate, which is exactly the machine-wide kill the clause exists to deny.

### 8. Denied and asked commands are never written to the audit log

- **What:** Commands that are denied or asked are never logged.
- **Where:**
  - `exit 0` inside `deny()`/`warn()`
  - the final `echo "[$(date -u ...)] [$SID] $CMD" >> ~/.claude/logs/bash-commands.log`
- **Why it is wrong:**
  - `deny` and `warn` exit before the logging block runs.
  - Every blocked or prompted command, which are the security-relevant ones, is missing from `bash-commands.log`. The trail records only the commands that were allowed.
