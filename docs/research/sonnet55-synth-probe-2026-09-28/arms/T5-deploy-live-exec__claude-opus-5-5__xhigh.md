# Where `scripts/deploy-live.sh` is executed (snapshot 47c3317eb, scoped to `hooks/`, `scripts/`, `bin/`)

I found **7 distinct execution sites**. Five name or resolve the path themselves. The other two are generic dispatchers that run a command string which `deploy-live.sh` stored earlier. One further candidate is still open (`bin/cc-backlog:4308`, see the end).

## Execution sites

### 1. `hooks/operator-readout.sh:534`: the board's dry-run probe
- **Invocation:** `dout="$(DEPLOY_REPO="$SHARED" bash "$dscript" --dry-run --offline 2>&1)"; drc=$?` (`hooks/operator-readout.sh:534`)
- **How the path is resolved:**
  - `dscript` is declared local at `:505` and set to `"$DEPLOY_SCRIPT"` at `:517`.
  - `DEPLOY_SCRIPT="${CC_DEPLOY_SCRIPT:-$HOME/.claude/scripts/deploy-live.sh}"` (`:314`).
  - Fallback: `[ -e "$dscript" ] || dscript="$SHARED/scripts/deploy-live.sh"` (`:518`). I did not read where `SHARED` is defined in this file.
- **Arguments:** `--dry-run --offline`, with the environment variable `DEPLOY_REPO=$SHARED`. It is run as `bash <path>`, so the file does not need to be executable.
- **Mode:** foreground, inside a command substitution. stdout and stderr are both captured.
- **Guards:** it only runs if `$SHARED` is a git repo (`:504`), is on `main` or `master` (`:507`), and is more than 0 commits behind origin (`:532`).
- **Exit status:** if `drc` is 0, it writes a runnable `deploy ▶` row to `steps_file` (`:535-537`). Otherwise it writes a `held ⊘` row whose reason is the last output line with the `deploy-live: ` and `REFUSED — ` prefixes stripped (`:539-544`).

### 2. `bin/cc-do:184`: the same probe in `cc-do`
- **Invocation:** `dout="$(DEPLOY_REPO="$SHARED" bash "$dscript" --dry-run --offline 2>&1)"; drc=$?` (`bin/cc-do:184`)
- **How the path is resolved:**
  - `dscript` is declared local at `:154` and set to `"$DEPLOY_SCRIPT"` at `:165`.
  - `DEPLOY_SCRIPT="${CC_DEPLOY_SCRIPT:-$HOME/.claude/scripts/deploy-live.sh}"` (`:89`).
  - Fallback: `$SHARED/scripts/deploy-live.sh` (`:166`).
  - `SHARED="${CC_SHARED_CHECKOUT:-$HOME/Development/claude-infrastructure}"` (`:88`).
- **Arguments:** `--dry-run --offline`, with `DEPLOY_REPO=$SHARED`.
- **Mode:** foreground, inside a command substitution. Same guards as site 1 (`:157-167`).
- **Exit status:** if 0, it calls `emit deploy '▶' …` and puts `"$dscript"` in field 6, the path field (`:186-187`). Otherwise it emits a `⊘` row carrying the refusal reason (`:193-198`).

### 3. `bin/cc-do:359`: `cc-do` actually running the deploy step
- **Invocation:** `else bash "$1" </dev/null; rc=$?; fi`, inside `run_one` (`bin/cc-do:356-359`).
- **How the path is resolved:**
  - `$1` is `path`, passed by `run_steps` (`:389`).
  - `path` is field 6 of each line read from `$STEPS` (`:385`).
  - That field is written by `emit` (`:150`) with `"$dscript"`, and only on the ▶ branch of site 2 (`:186-187`). The value therefore comes from `:89`, `:165` and `:166`.
  - `run_steps` skips any row that is not ▶ (`:386`), so a `⊘` deploy row is never run.
  - The `CONFIRM=1` branch at `:358` is not taken, because a deploy row's `cmd` is `"bash …"` (`:187`).
- **Arguments:** none. It is run as `bash <path>` with stdin from `/dev/null`.
  - Unlike the probe, it does **not** pin `DEPLOY_REPO`. The script's own default applies: `DEPLOY_REPO="${DEPLOY_REPO:-$HOME/Development/claude-infrastructure}"` (`scripts/deploy-live.sh:122`).
  - So if `CC_SHARED_CHECKOUT` is overridden, the probe and the real run can be looking at different checkouts.
- **Mode:** foreground.
  - It runs from `run_steps` when `--run` or `CC_DO_ASSUME_YES=1` is given (`:525`), or after the interactive `[Y/n]` prompt (`:543-548`).
  - With a non-terminal stdin and neither of those set, it exits 3 and runs nothing (`:535-541`).
- **Exit status:**
  - Non-zero with class `deploy`: prints `SKIPPED …` and returns 0, so the remaining steps still run (`:369-373`).
  - Zero: prints `✓ <name>` (`:379`).

### 4. `scripts/deploy-now.sh:89`: the compatibility wrapper
- **Invocation:** `exec "$DEPLOY_LIVE" "$@"` (`scripts/deploy-now.sh:89`)
- **How the path is resolved:**
  - `DEPLOY_LIVE="${CC_DEPLOY_LIVE-$REPO/scripts/deploy-live.sh}"` (`:56`). This uses `-`, not `:-`, so an empty value is kept as empty.
  - `REPO="${CC_DEPLOY_REPO:-$HOME/Development/claude-infrastructure}"` (`:53`).
  - It also exports `DEPLOY_REPO="$REPO"` (`:60`).
  - Guards: `[ -d "$REPO" ]` (`:62`) and `[ ! -x "$DEPLOY_LIVE" ]` → exit 1 (`:72-78`).
- **Arguments:** all of the caller's arguments, passed through with `"$@"`. The script is exec'd directly, so it must be executable.
- **Mode:** foreground. `exec` replaces the wrapper's process.
- **Exit status:** not handled. `deploy-live.sh`'s exit status becomes the wrapper's exit status.
- **Callers:** none in scope. The only other reference is `install.sh:849`, which is out of scope and only creates a symlink (`link_file`).

### 5. `scripts/ship-land.sh:1736-1741` (the `Popen` call is at `:1739`): converge after a land
- **Invocation:** `python3 -c '…subprocess.Popen(["bash", sys.argv[1]], cwd=sys.argv[2], env=env, stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)' "$dl_script" "$dl_repo" "$dl_log" 2>/dev/null || true`
- **How the path is resolved:**
  - `dl_script="$dl_repo/scripts/deploy-live.sh"` (`:1730`).
  - `dl_repo="${DEPLOY_REPO:-$HOME/Development/claude-infrastructure}"` (`:1729`).
  - Guards: `SHIP_LAND_CONVERGE` is not `off` (`:1727`), `-f "$dl_script"` (`:1731`), and `git cherry origin/$TRUNK HEAD` is empty (`:1732-1733`).
- **Arguments:** none. The environment adds `CC_DEPLOY_MAX_LAG_COMMITS="0"` (`:1737`). The working directory is `dl_repo`. Output is appended to `dl_log="${POSTLAND_DIR:-$HOME/.claude/autonomy/postland}/converge-edge.log"` (`:1734`).
- **Mode:** detached. It starts a new session (`start_new_session=True`) and the `Popen` is never waited on.
- **Exit status:** never observed. Even a failure of `python3` itself is discarded by `2>/dev/null || true` (`:1741`), and the script then prints `✓ ship-land: live-layer converge kicked` regardless (`:1742`). This happens just before the final `LANDED` message and `return 0` (`:1749-1750`).

### 6. `bin/cc-do:454`: generic dispatcher for backlog commands, fed by `deploy-live.sh`
- **Invocation:** `bash -c "$cmd" </dev/null; rc=$?`, inside `run_backlog_row` (`bin/cc-do:405, 454`).
- **Where the command comes from:**
  - `cmd` is the row's `.run` field (`:415`), taken from `cc-backlog list --blocked --json` (`:413`).
  - `deploy-live.sh`'s `refusal_escalate` (`scripts/deploy-live.sh:698`) builds these `run` strings:
    - `bash $DEPLOY_REPO/scripts/deploy-live.sh --dry-run --offline` (`:728, :731, :743, :746`)
    - `CC_DEPLOY_SCAN=$(( depth + 50 )) bash $DEPLOY_REPO/scripts/deploy-live.sh --dry-run --offline` (`:708`)
    - `git -C $DEPLOY_REPO config --unset core.bare && bash $DEPLOY_REPO/scripts/deploy-live.sh --auto` (`:734`)
  - It files them with `"$BACKLOG_BIN" needs "$title" --run "$run"` (`:812`).
  - `BACKLOG_BIN="${CC_BACKLOG_BIN:-$HOME/.claude/bin/cc-backlog}"` (`:193`).
  - `DEPLOY_REPO` (`:122`) is expanded when the string is written, because it sits in double quotes. The stored path is therefore already absolute.
  - Rows created by `cc-backlog needs` have `status:"blocked"` (`bin/cc-backlog:3775`), so they are what `list --blocked` returns.
- **Arguments:** whatever the stored string contains, as listed above.
- **Mode:** foreground.
  - Triggered by `cc-do <12-hex id>` (`:470-473`), followed by a typed `yes` (`:450-452`) or with `CC_DO_ASSUME_YES=1` (`:435`).
  - With a non-terminal stdin, nothing runs (`:436-448`).
  - The slash-command and placeholder refusals (`:423-430`) do not match these strings.
- **Exit status:**
  - Non-zero: prints `FAILED`, leaves the row untouched, returns 1 (`:455-457`).
  - Zero: closes the row with `cc-backlog done … --evidence "cc-do ran: $cmd (exit 0)"` (`:459-461`).

### 7. `bin/cc-premise:1391-1392`: generic dispatcher for falsifier probes, fed by `deploy-live.sh`
- **Invocation:** `subprocess.run(["/bin/sh", "-c", cmd], capture_output=True, text=True, timeout=FALSIFIER_TIMEOUT_S, cwd=REPO or None)`, inside `run_falsifier` (`bin/cc-premise:1362`).
- **Where the command comes from:**
  - `cmd = (ent.get("falsifier") or "").strip()` (`:1387`).
  - `deploy-live.sh`'s `fals_host` builds the string `'"$HOME/.claude/scripts/deploy-live.sh" --falsify-host'` plus one single-quoted suite name per argument (`scripts/deploy-live.sh:949-961`).
  - `$HOME` is deliberately left unexpanded (`:960`), so `/bin/sh` resolves it at run time. There is no fallback to the repo copy, and the file is exec'd directly, so it must be executable.
  - The string is stored with `"$BACKLOG_BIN" add … --falsifier "$(fals_host "$1")"` (`:1044-1047`) and `--falsifier "$(fals_host_set "$red")"` (`:1259-1262`).
- **Arguments:** `--falsify-host '<suite>' ['<suite>' …]`. `deploy-live.sh` handles this mode at `:337`.
- **Mode:** foreground subprocess with output captured, bounded by a timeout (`FALSIFIER_TIMEOUT_S`, default 20, `:241`). It is gated by `FALSIFIER_ENABLED` (`CC_PREMISE_FALSIFIER`, `:246`). The working directory is `REPO` (`:129`).
- **Exit status:**
  - Any exception: returns `None` (`:1397-1399`).
  - Exit 0: returns a `"falsified"` verdict that tells the reader to close the item (`:1402-1411`).
  - Non-zero: falls through to code after `:1411`, which I did not read.
- **Callers:**
  - `assess()` (`:2252`) calls it at `:2310` when `run_probes` is true.
  - `cmd_check` (`:2657-2659`) is reached from `cc-backlog`'s claim path, `"$pbin" check "$id"` (`bin/cc-backlog:3046`).
  - `cmd_sweep` (`:3051`, `:3122-3123`) is reached from `scripts/autonomy-sweep.sh:1488` (`python3 "$_premise" sweep --json --record`), which runs at most once every 21600 s (`:1428-1435`).

## (a) Total

**7 distinct execution sites:**

| # | Site | Kind |
|---|------|------|
| 1 | `hooks/operator-readout.sh:534` | resolves the path itself |
| 2 | `bin/cc-do:184` | resolves the path itself |
| 3 | `bin/cc-do:359` | resolves the path itself |
| 4 | `scripts/deploy-now.sh:89` | resolves the path itself |
| 5 | `scripts/ship-land.sh:1739` | resolves the path itself |
| 6 | `bin/cc-do:454` | dispatcher of a stored string |
| 7 | `bin/cc-premise:1392` | dispatcher of a stored string |

Sites 6 and 7 are a judgement call. The brief excludes "an advisory string stored in a work item", but these stored strings are not only shown to a human: code actually executes them. If you exclude them, the total is **5**.

## (b) Rejected near-misses

**`hooks/`**
- `hooks/config-mirror-assert.sh:36`: a comment.
- `hooks/activation-watch.sh:466-467`: comments.
- `hooks/activation-watch.sh:471` and `:492`: `▶ bash …` text appended to the `out` message for the operator.
- `hooks/session-continue.sh:1191`: inside the `reason=` text of the hook (`:1187-1193`).
- `hooks/operator-readout.sh:314` and `:518`: path assignments used by site 1; not invocations themselves.
- `hooks/operator-readout.sh:536-537` and `:543-544`: board rows written to `steps_file` for display. I found no `bash -c`, `eval` or exec of `steps_file` in this file.
- `hooks/operator-readout.sh:510-529`: comments.
- `hooks/operator-readout.sh:887`: the `dact` hint text added to the status line (`:889-892`).
- `hooks/lib/why-tier.sh:249`: explanation text with a `<repo>` placeholder in it.
- `hooks/validate-bash.sh:1425` and `:1432`: text of `deny` messages.
- `hooks/completion-assert.sh:782` and `:784`: `facts=` text for the operator.

**`scripts/`**
- `scripts/deploy-now.sh:73` and `:87`: abort message and banner.
- `scripts/wrap-ledger.sh:2068` (`READOUT=` text) and `:2403` (printed next step): both operator-facing.
- `scripts/kitty-title-band-deploy.sh:193`: a `die` message.
- `scripts/permission-gate-lint.sh:169`: an entry in the lint's ratchet table.
- `scripts/permission-gate-lint.sh:526` and `:535`: help `echo`s.
- `scripts/permission-gate-lint.sh:563, 589, 637, 720-722, 745-747, 770, 782`: selftest fixture strings and ratchet strings.
- `scripts/ship-land.sh:4511`: an `echo` message.
- `scripts/handoff-fire.sh:9153` (an `echo`) and `:12619` (the `rcy_tok_why` reason string).
- `scripts/test-hermeticity-lint.sh:1687`: a grep pattern.
- `scripts/test-hermeticity-lint.sh:2338` and `:2560`: lint messages.
- `scripts/offbox-admission-lint.sh:274`: printed text.
- `scripts/deploy-link-parity.sh:509`: a remediation line passed to `fix`. I did not read the `fix` helper itself.
- `scripts/deploy-parity-assert.sh:1081, 1366, 1368, 1382, 1435, 1456, 1459, 1497, 1504`: `printf`/`report` text. `:1504` is a `grep -c` suggestion printed for the operator.
- `scripts/backlog-consolidation/group.py:143` (a regex) and `:148` (plain text).
- `scripts/limit-recover/lr-handoff.sh:802` and `:829`: stderr `echo`s.

**`bin/`**
- `bin/cc-venue:187`: docstring text.
- `bin/cc-reaper:878`: a process-name regex in `wl=`.
- `bin/cc-eligible:169`: a regex pattern.
- `bin/cc-blockers:642`: the `recover_cmd` field of a board row. The only consumers in scope display it (`bin/cc-blockers:1299, 1582, 1596`); none executes it.
- `bin/cc-do:89` and `:166`: path assignments used by sites 2 and 3.
- `bin/cc-do:186-187` and `:196-198`: the `bash ~/…` text in the `cmd` field is for display. Site 3 runs the separate path field, and `⊘` rows are never run (`:386`).
- `bin/cc-dispatch:1282`: a jq comparison against the source name `"deploy-live"`.
- `bin/cc-premise:1776`: the filing-day screen does not execute probes. It parses the probe into clauses and rejects script calls and absolute paths (`:1790-1793`).

**`scripts/deploy-live.sh` referring to itself**
- `:419`: `$0` is only read by `sed` to print the help text.
- `:708-746`: `run=` strings. They are written to a page's `next:` line (`:803`) and a backlog `--run` field (`:812`), but `deploy-live.sh` never runs them itself. They reach execution only through site 6.
- `:960`: the falsifier string. It is stored and never run by `deploy-live.sh`; it reaches execution only through site 7.
- `:420, 438-441, 2376` and other messages: text for the operator.
- `:2471`: `deploy-$DIV_CLASS.page` is a page file name, not this script.

## (c) Does it re-exec itself, and where is the unattended entry point?

**Re-exec:** no. The script contains no `exec` of its own path, no `bash "$0"` and no use of `BASH_SOURCE`. Its only `$0` use is the help `sed` at `scripts/deploy-live.sh:419`. It does, however, store two kinds of commands that run itself later in *another* process:
- falsifier probes (`:960`), run by `bin/cc-premise:1392`;
- escalation `--run` commands (`:708-746`, filed at `:812`), run by `bin/cc-do:454`.

**Unattended entry point:** the scheduled job that runs the actual deploy (`--auto`) is **outside** the three scoped trees: `launchd/com.claude.deploy-live.plist:34-38`.
- It runs `/bin/bash -c '…D="$HOME/.claude/scripts/deploy-live.sh"; [ -x "$D" ] || D="$HOME/Development/claude-infrastructure/scripts/deploy-live.sh"; exec "$D" --auto'`.
- It has `StartInterval 600` (`:41-42`) and `RunAtLoad` (`:44-45`).
- This matches the comment at `scripts/deploy-now.sh:69-71`, which I checked against the plist.

The word "only" in the brief does not quite hold. Two more unattended paths execute the script from lines inside the scoped trees:
1. **After every land:** `scripts/ship-land.sh:1736-1741` starts a detached run automatically after each successful land. It is triggered by the land, not by a schedule.
2. **On a schedule, via the falsifier:** `launchd/com.chrisren.autonomy-sweep.plist:24,26` (every 300 s, outside scope) runs `scripts/autonomy-sweep.sh:1488` → `cc-premise sweep` → `bin/cc-premise:1392` → `deploy-live.sh --falsify-host …`. The scheduler is outside scope, but the line that executes the script is inside. It runs the `--falsify-host` check, not a deploy.

## Stale comment citations

- `launchd/com.claude.deploy-live.plist:16` cites `hooks/operator-readout.sh:238-246` for the fallback fix. In this snapshot that code is at `hooks/operator-readout.sh:517-518`.
- `bin/cc-do:152` says it mirrors `hooks/operator-readout.sh §152-258`. The matching deploy code is at `hooks/operator-readout.sh:503-548`.

## Still open

- **Possible 8th site:** `bin/cc-backlog:4308` runs a probe with `/bin/sh -c "$probe"` inside the `falsify` subcommand. I ran out of my tool-call budget before confirming whether `cc-backlog add --falsifier` (which `deploy-live.sh` uses at `:1044-1047` and `:1259-1262`) goes through that code. If it does, it would be an 8th site: it would run `deploy-live.sh --falsify-host` while filing the item, from inside a `deploy-live` run.
- **Not traced:** `scripts/cloud-return.sh:406-407` and `scripts/registration-state.sh:171,189` also run stored strings with `bash -c`. I did not trace what feeds them, and found no link from them to `deploy-live.sh`.
