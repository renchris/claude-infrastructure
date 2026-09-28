# Execution sites of `scripts/deploy-live.sh` (hooks/, scripts/, bin/)

The brief names `/tmp/o55probe-repo-47c3317eb`, but I read the pinned snapshot at `/tmp/s55/repo-47c3317eb`. I stopped at the 25-call bound, so a few things below are marked unverified.

## Execution sites

**Total: 6 verified, and 1 more unverified candidate (`bin/cc-premise`, see below).** Sites 1–5 always run the script when reached. Site 6 runs it only if a stored backlog row carries a deploy-live command.

### 1. `scripts/ship-land.sh:1739` — detached converge kick after a land
- **Invocation:** `subprocess.Popen(["bash", sys.argv[1]], …)` inside `python3 -c '…'` (`scripts/ship-land.sh:1736-1741`).
- **Path resolution:**
  - `sys.argv[1]` is `"$dl_script"`, passed at `scripts/ship-land.sh:1741`.
  - `dl_script="$dl_repo/scripts/deploy-live.sh"` is at `scripts/ship-land.sh:1730`.
  - `dl_repo="${DEPLOY_REPO:-$HOME/Development/claude-infrastructure}"` is at `scripts/ship-land.sh:1729`. That is the fallback default.
- **Guards:**
  - `SHIP_LAND_CONVERGE:-on` must not be `off` (`scripts/ship-land.sh:1727`).
  - `[[ -f "$dl_script" ]]` must hold (`scripts/ship-land.sh:1731`).
  - `git cherry origin/"$TRUNK" HEAD` in the shared checkout must be empty (`scripts/ship-land.sh:1732-1733`).
- **Arguments:**
  - There are no script arguments.
  - The environment gets `CC_DEPLOY_MAX_LAG_COMMITS="0"` (`scripts/ship-land.sh:1737`).
  - `cwd=$dl_repo` is `sys.argv[2]` (`scripts/ship-land.sh:1739`).
  - stdin is `DEVNULL` and stdout goes to a log file. The log is `sys.argv[3]`, which is `$dl_log`, set at `scripts/ship-land.sh:1734` to `${POSTLAND_DIR:-$HOME/.claude/autonomy/postland}/converge-edge.log`. stderr is merged into stdout (`scripts/ship-land.sh:1738-1740`).
- **Mode:** detached, with `start_new_session=True` (`scripts/ship-land.sh:1740`). `Popen` is never waited on.
- **Exit status:** never observed. The python3 wrapper ends in `2>/dev/null || true` (`scripts/ship-land.sh:1741`). The next line unconditionally prints `✓ … converge kicked` (`scripts/ship-land.sh:1742`).

### 2. `scripts/deploy-now.sh:89` — `exec "$DEPLOY_LIVE" "$@"`
- **Path resolution:**
  - `DEPLOY_LIVE="${CC_DEPLOY_LIVE-$REPO/scripts/deploy-live.sh}"` is at `scripts/deploy-now.sh:56`. It uses `-` rather than `:-`, so a set-but-empty value is honoured.
  - `REPO="${CC_DEPLOY_REPO:-$HOME/Development/claude-infrastructure}"` is at `scripts/deploy-now.sh:53`.
  - `[ ! -x "$DEPLOY_LIVE" ]` aborts with exit 1 (`scripts/deploy-now.sh:72-78`).
- **Arguments:** `"$@"` is forwarded verbatim (`scripts/deploy-now.sh:89`). `export DEPLOY_REPO="$REPO"` is set first (`scripts/deploy-now.sh:60`).
- **Mode:** foreground, and `exec` replaces the shell, so deploy-live's exit status becomes the process's exit status. There is no caller-side handling.
- **Callers:** no non-comment reference to `deploy-now` exists elsewhere in `hooks/`, `scripts/` or `bin/`. Nothing in scope calls this script.

### 3. `hooks/operator-readout.sh:534` — `--dry-run --offline` probe
- **Invocation:** `dout="$(DEPLOY_REPO="$SHARED" bash "$dscript" --dry-run --offline 2>&1)"; drc=$?`
- **Path resolution:**
  - `dscript="$DEPLOY_SCRIPT"` is at `hooks/operator-readout.sh:517`.
  - `DEPLOY_SCRIPT="${CC_DEPLOY_SCRIPT:-$HOME/.claude/scripts/deploy-live.sh}"` is at `hooks/operator-readout.sh:314`.
  - The fallback `[ -e "$dscript" ] || dscript="$SHARED/scripts/deploy-live.sh"` is at `hooks/operator-readout.sh:518`.
  - `SHARED="${CC_SHARED_CHECKOUT:-$HOME/Development/claude-infrastructure}"` is at `hooks/operator-readout.sh:297`.
- **Guards:** the shared checkout must be on `main` or `master` (`hooks/operator-readout.sh:507`) and `behind > 0` (`hooks/operator-readout.sh:532`).
- **Arguments:** `--dry-run --offline`, with `DEPLOY_REPO="$SHARED"` as a per-command environment prefix.
- **Mode:** foreground, inside `$(…)`, with stderr merged into stdout.
- **Exit status:** `drc=$?` is captured at `hooks/operator-readout.sh:534`. Zero writes a `▶` row (`hooks/operator-readout.sh:535-537`). Non-zero writes a `held` row containing the last output line, or `exit $drc` if that is empty (`hooks/operator-readout.sh:538-544`). It never fails the hook.

### 4. `bin/cc-do:184` — same probe, same shape
- **Invocation:** `dout="$(DEPLOY_REPO="$SHARED" bash "$dscript" --dry-run --offline 2>&1)"; drc=$?`
- **Path resolution:**
  - `dscript="$DEPLOY_SCRIPT"` is at `bin/cc-do:165`.
  - `DEPLOY_SCRIPT="${CC_DEPLOY_SCRIPT:-$HOME/.claude/scripts/deploy-live.sh}"` is at `bin/cc-do:89`.
  - The fallback `[ -e "$dscript" ] || dscript="$SHARED/scripts/deploy-live.sh"` is at `bin/cc-do:166`.
  - `SHARED="${CC_SHARED_CHECKOUT:-…/claude-infrastructure}"` is at `bin/cc-do:88`.
- **Guards:** the checkout must be on `main` or `master` (`bin/cc-do:159`) and `behind > 0` (`bin/cc-do:167`).
- **Mode:** foreground, in a command substitution, with stderr merged.
- **Exit status:** `drc=$?`. Zero emits a `▶` row whose sixth field, `$dscript`, is the runnable path (`bin/cc-do:185-187`). Non-zero emits a `⊘` row that `run_steps` never runs (`bin/cc-do:188-198`).

### 5. `bin/cc-do:359` — generic dispatcher, handed the path at runtime
- **Invocation:** `else bash "$1" </dev/null; rc=$?; fi`, in `run_one` (`bin/cc-do:356-359`).
- **Path resolution:**
  - `$1` is `$path`, passed by `run_steps` at `bin/cc-do:389` and read from `$STEPS` at `bin/cc-do:385`.
  - That field was written by `emit()` (`bin/cc-do:150`) with `"$dscript"` as field 6 (`bin/cc-do:186-187`).
  - The default chain is the same as site 4.
  - Only `▶` rows are run (`bin/cc-do:386`).
- **Arguments:** none, and stdin is `</dev/null`.
  - The `CONFIRM=1` branch at `bin/cc-do:358` is not taken. The deploy row's `cmd` is `bash …`, which doesn't start with `CONFIRM=1 `.
- **Mode:** foreground.
- **Exit status:** `rc=$?`. For class `deploy`, a non-zero rc prints `SKIPPED` and does `return 0`, so the run continues (`bin/cc-do:369-373`). For other classes it prints `FAILED` and returns 1 (`bin/cc-do:374-376`).
- **Reached by:** `run_steps` at `bin/cc-do:525` (`--run` or `CC_DO_ASSUME_YES=1`) or `bin/cc-do:548` (after a tty `[Y/n]`). A non-tty caller gets exit 3 and nothing runs (`bin/cc-do:535-540`).

### 6. `bin/cc-do:454` — `bash -c "$cmd" </dev/null; rc=$?` (data-dependent)
- **What it is:** `run_backlog_row` executes a blocked backlog row's stored `.run` string (`bin/cc-do:415`).
- **Path resolution:**
  - Nothing in `cc-do` names the script here. The string comes from `deploy-live.sh:708,728,731,734,743,746` (`run="… bash $DEPLOY_REPO/scripts/deploy-live.sh …"`).
  - `deploy-live.sh` files it with `cc-backlog needs "$title" --run "$run"` (`scripts/deploy-live.sh:812`).
  - `$DEPLOY_REPO` defaults at `scripts/deploy-live.sh:122`.
- **Arguments:** `--dry-run --offline` (lines 708, 728, 731, 743, 746), or `--auto` after `git … config --unset core.bare &&` (line 734). Line 708 also prefixes `CC_DEPLOY_SCAN=…`.
- **Mode:** foreground.
- **Gate:** a typed `yes`, or `CC_DO_ASSUME_YES=1` (`bin/cc-do:435-453`). A non-tty caller gets exit 3 (`bin/cc-do:436-448`).
- **Exit status:** non-zero prints `FAILED` and returns 1 with the row untouched (`bin/cc-do:455-458`). Zero runs `cc-backlog done` (`bin/cc-do:459`).
- **Reachability:** it runs deploy-live only if such a row exists and the operator names its id.

### Unverified candidate (not counted): `bin/cc-premise`
- `scripts/deploy-live.sh:960` builds `"$HOME/.claude/scripts/deploy-live.sh" --falsify-host <suite>`. It is stored as a backlog `--falsifier` (`scripts/deploy-live.sh:1044-1047`, and by the same pattern at `scripts/deploy-live.sh:1262`, which I did not read).
- The comment at `scripts/deploy-live.sh:1041` says `cc-premise` runs the stored string through `/bin/sh -c`.
- I did not read the runner (`run_falsifier`, `bin/cc-premise:1362`). A pattern grep of `bin/cc-premise` for `sh -c|bash -c|eval ` found no non-comment hits. It does show `subprocess.run` at `bin/cc-premise:645` and `bin/cc-premise:676`.
- If `run_falsifier` really executes stored falsifiers, the total becomes 7.

## (a) Total distinct execution sites
**6 verified** (`scripts/ship-land.sh:1739`, `scripts/deploy-now.sh:89`, `hooks/operator-readout.sh:534`, `bin/cc-do:184`, `bin/cc-do:359`, `bin/cc-do:454`). Site 6 is conditional on stored data. One more candidate is unverified.

## (b) Near-misses rejected

**Comments**
- `hooks/config-mirror-assert.sh:36` — comment.
- `hooks/activation-watch.sh:466-467` — comment.
- `hooks/operator-readout.sh:510-512,526,871` — comment.
- `scripts/deploy-now.sh:3,18,25-27,33,46,54,69` — comments.
  - The `:69` claim, that launchd execs `deploy-live.sh --auto` directly, is correct. See the plist at (c).
- `scripts/deploy-live.sh:13,28,37,161,183,185,498,564,1093,1286,1318` — comments.
- `scripts/wrap-ledger.sh:77-148,1288-1823,2063,2075` — comments.
- `scripts/permission-gate-lint.sh:10,112-118,147,526-535,558,584` — comments and echoed text.
- `scripts/postland-verify.sh:207,365,874,883,1030,1556,1571,1599,1805,2110,4525` — comments.
- `scripts/deploy-parity-assert.sh:33,211,256,273,425,433,449-468,604,645,991,1025,1111,1227,1287-1300,1334-1435` — comments.
- `scripts/deploy-parity-assert.sh:1462-1481,1509,1518` — comments.
- `scripts/test-hermeticity-lint.sh:132,428-486,976` — comments.
- `scripts/kitty-setup.sh:57,232` — comments.
- `scripts/test-walltime-lint.sh:153` — comment.
- `scripts/new-worktree.sh:9,11` — comments.
- `scripts/browse-mirror-sync.sh:103` — comment.
- `scripts/test-afunix-path-lint.sh:22` — comment.
- `scripts/host-suites.manifest:1,7,156` — comments in a data file that `deploy-live` reads.
- `hooks/validate-bash.sh:1274,1380,1402` — comments.
- `bin/cc-do:29,169` and `bin/cc-do:162` — comments.

**Text that only reaches a human**
- `hooks/activation-watch.sh:471,492` — advisory lines appended to `out`.
- `hooks/session-continue.sh:1191` — inside the hook `reason` blob (`hooks/session-continue.sh:1183-1194`). The `\$(git rev-parse …)` is escaped, so it is never expanded.
- `hooks/validate-bash.sh:1425,1432` — `deny "…"` reason strings.
- `hooks/lib/why-tier.sh:249` — explanatory text.
- `hooks/operator-readout.sh:536,543` — rendered board rows written to `$steps_file`.
- `hooks/operator-readout.sh:887` — display suffix `dact=" → bash scripts/deploy-live.sh"`.
- `hooks/completion-assert.sh:782,784` — `facts=` strings.
- `scripts/wrap-ledger.sh:2068` — `READOUT=` string.
- `scripts/wrap-ledger.sh:2403` — `printf` of a display line.
- `scripts/handoff-fire.sh:9153` — `echo … >&2`.
- `scripts/handoff-fire.sh:12619` — `rcy_tok_why=` string (read at `scripts/handoff-fire.sh:12612-12622`).
- `scripts/deploy-link-parity.sh:509` — `fix "bash …"`. `fix()` only appends to `FIXES` (`scripts/deploy-link-parity.sh:159`).
- `scripts/deploy-parity-assert.sh:1366,1368,1435` — report text.
- `scripts/deploy-parity-assert.sh:1459` — a `printf` to stderr.
- `scripts/deploy-parity-assert.sh:1504` — a `printf` that prints a `grep -c … deploy-live.sh` line for the operator. It reads the file, it does not run it.
- `scripts/deploy-live.sh:420,434,438,440,441,752,1398,1402,1418,2091,2395,2467,2504,2541,2631` — its own banners.
- `scripts/deploy-live.sh:2376` — its own banner.
- `scripts/kitty-title-band-deploy.sh:193` — `die` message.
- `scripts/offbox-admission-lint.sh:274` — `printf` message.
- `bin/cc-venue:187` — descriptive text.

**Stored or escalation strings**
- `scripts/deploy-live.sh:708,728,731,734,743,746` — `run=` string assignments.
  - They are printed at `scripts/deploy-live.sh:803` and stored at `scripts/deploy-live.sh:812`. They are executed only via site 6.
- `scripts/deploy-live.sh:960,1044-1047` — stored falsifier string. See the `cc-premise` candidate.
- `bin/cc-blockers:642` — a blockers-board JSON row whose `recover_cmd` names the script.
  - I saw consumers at `bin/cc-blockers:1299,1582,1596`, all rendered through `cell(...)`. I did not read `bin/cc-blockers:1137`.

**Grep/lint patterns, ratchet tables, fixtures**
- `scripts/permission-gate-lint.sh:104` — glob `scripts/deploy-*` in `EMBEDDED_SET`.
- `scripts/permission-gate-lint.sh:169` — ratchet table entry.
- `scripts/permission-gate-lint.sh:563,589` — fixture builders (`mk … scripts/deploy-live.sh '…'`).
- `scripts/permission-gate-lint.sh:637` — a `printf` inside the fixture text.
- `scripts/permission-gate-lint.sh:720-722,745-747,770,782` — selftest literals.
- `scripts/test-hermeticity-lint.sh:1687` — grep pattern.
- `scripts/test-hermeticity-lint.sh:2338,2559-2569` — messages.
- `scripts/test-hermeticity-lint.sh:3025,3038,3064,3987,3991` — selftest fixtures.
- `bin/cc-eligible:169` — regex tuple.
- `bin/cc-reaper:878` — whitelist string.
- `bin/cc-dispatch:1282` — jq `.source == "deploy-live"` label comparison.

**Bare path assignments that are never invoked**
- `bin/cc-blockers:186` — `DEPLOY_REPO="${DEPLOY_REPO:-…}"`. It is used only for `git -C`, for `postland-verify`, and for other scripts (`bin/cc-blockers:228,272,349,533,545,627,691,1349`), never for `deploy-live.sh`.
- The `DEPLOY_SCRIPT` assignments at `hooks/operator-readout.sh:314` and `bin/cc-do:89` do get invoked. They are covered by sites 3–5.

**`deploy-live.sh` referring to itself**
- `scripts/deploy-live.sh:419` — `sed -n … "$0"` reads its own text for `--help`. It does not run it.
- `scripts/deploy-live.sh:554` — awk `$0`.
- `scripts/deploy-live.sh:1483` — `/bin/bash "$PARITY_ASSERT"` is a different script.
- `scripts/deploy-live.sh:708-746` — the `run=` strings above.

**Stale citations noted**
- `scripts/permission-harvest-run.sh:329` says `bin/cc-do:436` runs `bash -c "$cmd"`. The actual line is `bin/cc-do:454`.
- The `scripts/ship-land.sh:1703,1719` citations into `deploy-live.sh` (`:2543`, `:180`) were not verified, and I do not rely on them.

## (c) Self re-exec, and the scheduled entry point

**Does `deploy-live.sh` re-exec itself? No, as far as I could establish.**
- A grep of `scripts/deploy-live.sh` for `exec`, `$0`, `BASH_SOURCE`, `nohup`, `setsid`, `disown`, `bash "$`, `bash $` and `source`, excluding comment lines, found:
  - `scripts/deploy-live.sh:419` (`sed … "$0"`, a read of its own text);
  - `scripts/deploy-live.sh:554` (an awk `$0`);
  - `scripts/deploy-live.sh:1483` (`/bin/bash "$PARITY_ASSERT"`, a different script);
  - the string assignments at `scripts/deploy-live.sh:708-746`.
- That was a pattern grep, not a read of the whole file. `--falsify-host` is a mode branch in the same process at `scripts/deploy-live.sh:337`. I saw only that grep line.

**Where does the scheduled entry live?** Outside the three scoped trees.
- `launchd/com.claude.deploy-live.plist:38` runs `D="$HOME/.claude/scripts/deploy-live.sh"; [ -x "$D" ] || D="$HOME/Development/claude-infrastructure/scripts/deploy-live.sh"; exec "$D" --auto`.
  - It has `StartInterval` (`launchd/com.claude.deploy-live.plist:41`) and `RunAtLoad` (`launchd/com.claude.deploy-live.plist:44`).
  - I did not read the interval value. The plist header comment says 600s.
  - `launchd/` is at the repo root, not under `hooks/`, `scripts/` or `bin/`.
- Every scheduled run therefore comes from that plist.
- The premise "the only unattended entry point" is not quite right. `scripts/ship-land.sh:1739` is unattended too. It is a detached kick fired by a land, not by a timer, and it lives inside `scripts/`.
