# Execution sites for `scripts/deploy-live.sh` in `hooks/`, `scripts/` and `bin/`

There are **5 distinct execution sites** inside the three scoped trees. `deploy-live.sh` never re-execs itself. The only unattended scheduled entry point is the launchd plist, which is outside all three trees.

I read every non-comment hit for `deploy-live` in the three trees. I did not read the whole of `deploy-live.sh`. For the re-exec question I grepped it for `exec`, `bash`, `nohup`, `setsid`, `$0` and `BASH_SOURCE`. Stale `file:line` citations in comments were not relied on.

## Execution sites

### 1. `scripts/deploy-now.sh:89`: `exec "$DEPLOY_LIVE" "$@"`
- **Path resolution:**
  - `DEPLOY_LIVE="${CC_DEPLOY_LIVE-$REPO/scripts/deploy-live.sh}"` at `scripts/deploy-now.sh:56`.
  - The `-` (not `:-`) form means a set-but-empty `CC_DEPLOY_LIVE` is kept as empty.
  - `REPO="${CC_DEPLOY_REPO:-$HOME/Development/claude-infrastructure}"` at `scripts/deploy-now.sh:53`.
  - `DEPLOY_REPO="$REPO"` is exported at `scripts/deploy-now.sh:61`, which is `deploy-live.sh`'s own repo variable.
- **Arguments:** whatever the caller passed (`"$@"`). Nothing is added.
- **Mode:** foreground, and `exec` replaces the shell process.
- **Exit status:** the shell is gone, so the target's status becomes the wrapper's status.
- **Guard before the call:** `[ ! -x "$DEPLOY_LIVE" ]` aborts with exit 1 (`scripts/deploy-now.sh:72-77`).

### 2. `scripts/ship-land.sh:1739`: `subprocess.Popen(["bash", sys.argv[1]], …)` inside `python3 -c` (starts at `:1736`)
- **Path resolution:**
  - `dl_script="$dl_repo/scripts/deploy-live.sh"` at `scripts/ship-land.sh:1730`.
  - `dl_repo="${DEPLOY_REPO:-$HOME/Development/claude-infrastructure}"` at `scripts/ship-land.sh:1729`.
  - The script is passed to Python as `sys.argv[1]` (`scripts/ship-land.sh:1742`, the `"$dl_script"` argument that follows the closing quote of the `python3 -c` program).
- **Guards:** the call is skipped unless `SHIP_LAND_CONVERGE` is not `off` (`:1726`), `[[ -f "$dl_script" ]]`, and `git cherry origin/$TRUNK HEAD` is empty (`:1731-1733`).
- **Arguments:** none. `CC_DEPLOY_MAX_LAG_COMMITS=0` is set in the child environment (`:1737`).
- **Mode:** detached. It uses `Popen` with `start_new_session=True`, `stdin=DEVNULL`, and stdout and stderr appended to `converge-edge.log` (`:1738-1741`). It is never waited on.
- **Exit status:** never seen. The `python3 -c … || true` wrapper discards the launcher's own failure. The line after it unconditionally echoes "converge kicked" (`:1743-1744`), and the function later returns 0.

### 3. `hooks/operator-readout.sh:534`: `dout="$(DEPLOY_REPO="$SHARED" bash "$dscript" --dry-run --offline 2>&1)"; drc=$?`
- **Path resolution:**
  - `dscript="$DEPLOY_SCRIPT"` at `:517`.
  - `DEPLOY_SCRIPT="${CC_DEPLOY_SCRIPT:-$HOME/.claude/scripts/deploy-live.sh}"` at `:314`.
  - Fallback at `:518`: `[ -e "$dscript" ] || dscript="$SHARED/scripts/deploy-live.sh"`.
  - `SHARED="${CC_SHARED_CHECKOUT:-$HOME/Development/claude-infrastructure}"` at `:297`.
- **Arguments:** `--dry-run --offline`, with `DEPLOY_REPO=$SHARED` in the environment.
- **Mode:** foreground, inside a command substitution, with stderr merged into stdout. It only runs when `behind > 0` (`:522` region).
- **Exit status:** captured as `drc`. On 0 it renders a `deploy ▶` row (`:535-537`). On non-zero it renders a `held ⊘` row that quotes the last line of output (`:539-544`).

### 4. `bin/cc-do:184`: `dout="$(DEPLOY_REPO="$SHARED" bash "$dscript" --dry-run --offline 2>&1)"; drc=$?`
- **Path resolution:**
  - `dscript="$DEPLOY_SCRIPT"` at `bin/cc-do:165`.
  - `DEPLOY_SCRIPT="${CC_DEPLOY_SCRIPT:-$HOME/.claude/scripts/deploy-live.sh}"` at `bin/cc-do:89`.
  - Fallback at `bin/cc-do:166`: `[ -e "$dscript" ] || dscript="$SHARED/scripts/deploy-live.sh"`.
  - `SHARED="${CC_SHARED_CHECKOUT:-…claude-infrastructure}"` at `bin/cc-do:88`.
- **Arguments, mode and exit status:** same as site 3. On rc 0 it emits a `▶` row (`bin/cc-do:186`). Otherwise it emits a `⊘` row (`bin/cc-do:196`).

### 5. `bin/cc-do:358-359`: `bash "$1" </dev/null` in `run_one`, a generic dispatcher handed the path at runtime
- **Path resolution:**
  - `$1` is the `path` field (field 6) of a board row. `run_steps` reads it at `bin/cc-do:383-390` and calls `run_one "$path" …`.
  - For the deploy row, that field is `"$dscript"` from the `emit deploy '▶'` at `bin/cc-do:186`, so it is the `dscript` chain from site 4.
  - `run_steps` skips any row whose mark is not `▶` (`bin/cc-do:386`). The `⊘` row emitted at `:196` carries the same path but is never run.
- **Arguments:** none, only `bash <path>` with `stdin` from `/dev/null`. The `CONFIRM=1` branch at `:358` applies only to activation commands.
- **Mode:** foreground.
- **Exit status:** on non-zero, if the row class is `deploy`, `run_one` prints "SKIPPED" and **returns 0**, so the run continues (`bin/cc-do:365-372`). This is the only site that deliberately swallows a refusal.
- **Not a site:** `bin/cc-do:454` (`bash -c "$cmd"`) runs a backlog row's `--run` command, which I did not trace to `deploy-live.sh`.

## (b) Near-misses rejected

**Comments**
- `hooks/activation-watch.sh:466-467` — comment.
- `hooks/operator-readout.sh:510-512, 526` — comment.
- `bin/cc-do:162-164, 168-183` — comments.
- `scripts/ship-land.sh:1721` — comment.
- `scripts/deploy-now.sh:64-70` — comment. It states that the plist execs `deploy-live.sh --auto` directly.

**Text shown to a human**
- `hooks/activation-watch.sh:471, 492` — advisory `▶ bash $root/scripts/deploy-live.sh` strings.
- `hooks/session-continue.sh:1191` — text inside the hook's `reason` blob.
- `hooks/operator-readout.sh:536` and `:887` — the rendered board row and the `dact` string.
- `hooks/completion-assert.sh:782-784` — advisory facts string.
- `hooks/lib/why-tier.sh:249` — help text.
- `bin/cc-blockers:642` — `recover_cmd` printed into a JSON record.
- `scripts/wrap-ledger.sh:2068, 2403` — readout text.
- `scripts/handoff-fire.sh:9153, 12619` — echo and reason text.
- `scripts/limit-recover/lr-handoff.sh:802, 829` — echo text.
- `scripts/deploy-link-parity.sh:509` — `fix "…"` advisory.
- `scripts/kitty-title-band-deploy.sh:193` — `die` message.
- `scripts/deploy-parity-assert.sh:1081, 1366-1382, 1435, 1456-1459, 1497-1504` — `printf` and `report` text. `:1459` names `--dry-run` as a hint, and `:1504` is a `grep -c` hint for the operator.
- `scripts/ship-land.sh:4511` — echo text.
- `scripts/offbox-admission-lint.sh:274` — printf text.
- `hooks/validate-bash.sh:1425, 1432` — deny messages.

**Advisory strings stored in a work item, from `deploy-live.sh` itself**
- `scripts/deploy-live.sh:708, 728, 731, 734, 743, 746` assign `run="… bash $DEPLOY_REPO/scripts/deploy-live.sh …"`.
- `$run` is only printed (`:803`) or passed as `cc-backlog needs … --run "$run"` (`:811-812`). It is never executed there.

**Grep, lint, ratchet or fixture literals**
- `scripts/permission-gate-lint.sh:169, 563, 589, 720-722, 745-747, 770, 782` — ratchet-table entries and fixture literals.
- `scripts/test-hermeticity-lint.sh:2338, 2560` — lint messages.
- `bin/cc-eligible:169` — a regex.
- `scripts/backlog-consolidation/group.py:143, 148` — a regex and text.
- `bin/cc-reaper:878` — a process-name allowlist.
- `bin/cc-dispatch:1282` — a `jq` comparison against a source name.
- `bin/cc-venue:187` — a comment or doc string.

**Bare path assignments never invoked**
- `hooks/operator-readout.sh:314, 517-518` — the assignments alone. The invocation is `:534`.
- `bin/cc-do:89, 165-166` — the assignments alone. The invocations are `:184` and `:358-359`.
- `scripts/ship-land.sh:1730` — the assignment alone. The invocation is `:1739`.

**Self-reference**
- `scripts/deploy-live.sh:419` — `sed -n … "$0"` for `--help`. It reads the file and does not run it.

**Other**
- `scripts/install.sh` — this file does not exist. `install.sh` is at the repo root, outside the scoped trees. Its hits are comments (for example `install.sh:1416`, which cites `deploy-live.sh:2233`). I did not verify that citation. The `install.sh:849` hit is a symlink of `deploy-now.sh`, not an execution.

## (c) Re-exec and the scheduled entry point

**Does `deploy-live.sh` re-exec itself?** Not that I found. I grepped it for `exec`, `bash`, `nohup`, `setsid`, `$0` and `BASH_SOURCE`. The only `$0` use is the read-only `sed` at `scripts/deploy-live.sh:419`, and the only `bash …/deploy-live.sh` lines are the stored advisory strings at `:708-746`. I did not read the whole file, so this rests on that grep.

**The unattended entry point is outside the three trees.**
- `launchd/com.claude.deploy-live.plist:38` runs `/bin/bash -c '… D="$HOME/.claude/scripts/deploy-live.sh"; [ -x "$D" ] || D="$HOME/Development/claude-infrastructure/scripts/deploy-live.sh"; exec "$D" --auto'`.
- That is a top-level `launchd/` directory, not under `hooks/`, `scripts/` or `bin/`. It is the only scheduled or unattended path I found.
- Of the in-scope sites, `ship-land.sh:1739` is unattended in the sense that it runs detached with no human watching. But it fires only as a side effect of a land, not on a schedule.
