<!-- arm B = claude-opus-5-5 @high · brief T5-deploy-live-exec · settle run 1 (wf_e43f474d-ad0) · raw worker output, verbatim -->

# Where `scripts/deploy-live.sh` actually runs (snapshot 47c3317eb)

**Method and its limits.** I ran `grep -rn deploy-live` over `hooks/ scripts/ bin/`, which returned 273 lines. I dropped every line that starts with `#`, then read the code around every line that was left. I also followed four indirect paths: the `CC_DEPLOY_SCRIPT`, `CC_DEPLOY_LIVE` and `DEPLOY_REPO` variables, and backlog rows that store a command which other code later runs (`--run`, `--falsifier`). I did not read each comment-only hit one by one; the comment filter excluded them.

## Execution sites

### A. Sites where the path is fixed in the code

**1. `hooks/operator-readout.sh:534`**
```
dout="$(DEPLOY_REPO="$SHARED" bash "$dscript" --dry-run --offline 2>&1)"; drc=$?
```
- **Path:** `dscript="$DEPLOY_SCRIPT"` (:517).
  - `DEPLOY_SCRIPT="${CC_DEPLOY_SCRIPT:-$HOME/.claude/scripts/deploy-live.sh}"` (:314).
  - Fallback: `[ -e "$dscript" ] || dscript="$SHARED/scripts/deploy-live.sh"` (:518).
  - `SHARED="${CC_SHARED_CHECKOUT:-$HOME/Development/claude-infrastructure}"` (:297).
- **Arguments:** `--dry-run --offline`, with `DEPLOY_REPO=$SHARED` set in the environment.
- **When it runs:** only if the shared checkout is on `main` or `master` (:507) and is behind its origin (`behind -gt 0`, :533).
- **Mode:** foreground, inside a command substitution. Stdout and stderr are both captured.
- **Exit status:** `drc` 0 writes a runnable `deploy ▶` row (:535-537). Non-zero writes a `held ⊘` row whose text is the last output line, with the `deploy-live: ` and `REFUSED — ` prefixes stripped (:539-544).

**2. `bin/cc-do:184`**
- **Invocation:** the same probe line as site 1.
- **Path:** `dscript` (:165) takes `DEPLOY_SCRIPT` (:89, same default as site 1). Fallback to `$SHARED/scripts/deploy-live.sh` (:166), with `SHARED` from :88.
- **Arguments:** `--dry-run --offline`, with `DEPLOY_REPO=$SHARED`.
- **Mode:** command substitution.
- **Exit status:** 0 emits a `▶` row whose last field is the path `$dscript` (:186-187). Non-zero emits a `⊘` row that is never run (:196-198).

**3. `bin/cc-do:358`, in `run_one`**
```
else bash "$1" </dev/null; rc=$?; fi
```
- **Path:** `$1` is the row's path field. For a deploy row that field is `"$dscript"` (:187), so it resolves exactly as in site 2 (:165-166, :88-89).
- **How it is reached:** `run_steps` runs only `▶` rows (:383-389, :386).
  - It is called at :525 when `--run` is given or `CC_DO_ASSUME_YES=1` is set.
  - Otherwise it is called at :548 after the operator answers the `[Y/n]` prompt.
  - With no terminal on stdin it exits 3 and runs nothing (the block between :525 and :548).
  - The `CONFIRM=1` branch (:357) is not taken, because a deploy row's command starts with `bash ` (:187).
- **Arguments:** none.
- **Mode:** foreground, stdin set to `/dev/null`.
- **Exit status:** a non-zero exit on a deploy row prints `SKIPPED` and returns 0, so the rest of the list keeps running (~:360-372). Only rows of class `activation` get a `.done` marker (~:378).

**4. `scripts/deploy-now.sh:89`**
```
exec "$DEPLOY_LIVE" "$@"
```
- **Path:** `DEPLOY_LIVE="${CC_DEPLOY_LIVE-$REPO/scripts/deploy-live.sh}"` (:56). It uses `-`, not `:-`, so setting the variable to an empty string is honoured.
  - `REPO="${CC_DEPLOY_REPO:-$HOME/Development/claude-infrastructure}"` (:53).
  - `export DEPLOY_REPO="$REPO"` (:60).
- **Check first:** `[ ! -x "$DEPLOY_LIVE" ]` aborts with exit 1 (:72-78).
- **Arguments:** everything the caller passed, unchanged.
- **Mode:** `exec` replaces the process, in the foreground.
- **Exit status:** deploy-live's exit status becomes deploy-now's exit status.
- **Callers:** no in-scope code runs `deploy-now.sh`. Every other hit for it is a comment.

**5. `scripts/ship-land.sh:1739`**, inside the `python3 -c` block that starts at :1736
```
subprocess.Popen(["bash", sys.argv[1]], cwd=sys.argv[2], env=env, stdin=DEVNULL, stdout=log, stderr=STDOUT, start_new_session=True)
```
- **Path:** `sys.argv[1]` is `dl_script="$dl_repo/scripts/deploy-live.sh"` (:1730).
  - `dl_repo="${DEPLOY_REPO:-$HOME/Development/claude-infrastructure}"` (:1729).
- **When it runs:** all three must hold:
  - `SHIP_LAND_CONVERGE` is not `off` (:1727);
  - `-f "$dl_script"` is true (:1731);
  - `git -C "$dl_repo" cherry origin/$TRUNK HEAD` returns empty output (:1732-1733).
- **Arguments:** none. The environment adds `CC_DEPLOY_MAX_LAG_COMMITS="0"` (:1737), and the working directory is `dl_repo`.
- **Mode:** detached, in a new session. Output is appended to `converge-edge.log` (:1734).
- **Exit status:** never collected, because the `Popen` handle is never waited on. The python launcher's own failure is swallowed by `2>/dev/null || true` (:1741), and the script prints "converge kicked" regardless (:1742).

### B. Generic runners that get the path from a backlog row written by `deploy-live.sh`

**6. `bin/cc-premise:1392`**, in `run_falsifier` (:1362)
```
subprocess.run(["/bin/sh", "-c", cmd], capture_output=True, timeout=FALSIFIER_TIMEOUT_S, cwd=REPO or None)
```
- **Path:** `cmd` is the row's `falsifier` field (:1387). `deploy-live.sh` writes that field as `"$HOME/.claude/scripts/deploy-live.sh" --falsify-host <suite…>`:
  - the string is built in `fals_host` (:960);
  - it is stored through `cc-backlog add --falsifier` at `deploy-live.sh:1043-1047` and `:1259-1262`.
  - `$HOME` is expanded when the probe runs, not when it is stored.
- **When it runs:** on the claim path (`run_falsifier(...) if run_probes`, :2310).
- **Arguments:** `--falsify-host <suites>`, handled by the branch at `deploy-live.sh:337`.
- **Mode:** foreground, with a timeout and output captured.
- **Exit status:** 0 means the condition is gone and blocks the claim as `falsified` (:1400-). Non-zero is advisory only. A timeout or exception returns `None`, so the claim goes ahead (:1393-1398).

**7. `bin/cc-do:454`**, in `run_backlog_row`
```
bash -c "$cmd" </dev/null; rc=$?
```
- **Path:** `cmd` is the row's `.run` field (:415). `deploy-live.sh:812` files `cc-backlog needs "$title" --run "$run"`, and `$run` is built at :708-746 as one of:
  - `bash $DEPLOY_REPO/scripts/deploy-live.sh --dry-run --offline` (:728, :731, :743, :746);
  - `CC_DEPLOY_SCAN=… bash …/deploy-live.sh --dry-run --offline` (:708);
  - `git -C … config --unset core.bare && bash …/deploy-live.sh --auto` (:734).
- **When it runs:** only for `cc-do <12-hex-id>` (:469-471). It needs a typed `yes`, or `CC_DO_ASSUME_YES=1`. With no terminal on stdin it returns 3 and runs nothing.
- **Mode:** foreground.
- **Exit status:** non-zero prints `FAILED`, returns 1 and leaves the row open. Zero closes the row with `cc-backlog done`.

## (a) Total

**7 distinct execution sites.** Five have the path fixed in code: `operator-readout.sh:534`, `cc-do:184`, `cc-do:358`, `deploy-now.sh:89` and `ship-land.sh:1739`. Two are generic runners whose target arrives as row data: `cc-premise:1392` and `cc-do:454`.

If "an advisory string stored in a work item" is read as also excluding the code that later runs that string, sites 6 and 7 drop out and the count is 5.

## (b) Rejected near-misses

**Text shown to a human** (advisory strings, deny reasons, banners, help):
- `hooks/activation-watch.sh:471`, `:492`: advisory text built into `out=`.
- `hooks/session-continue.sh:1191`: inside a Stop-hook `reason=` string.
- `hooks/operator-readout.sh:536-537`, `:543`, `:887`: text of rendered board rows.
- `hooks/validate-bash.sh:1425`, `:1432`: `deny` reason text.
- `hooks/completion-assert.sh:782`, `:784`: a `facts=` message string.
- `hooks/lib/why-tier.sh:249`: help text.
- `scripts/deploy-now.sh:73`, `:87`: an error message and a stderr banner.
- `scripts/kitty-title-band-deploy.sh:193`: a `die` message.
- `scripts/wrap-ledger.sh:2068`, `:2403`: readout text.
- `scripts/permission-gate-lint.sh:526`, `:535`: help `echo`.
- `scripts/ship-land.sh:4511`: `echo` to stderr.
- `scripts/handoff-fire.sh:9153`, `:12619`: an `echo` and a reason string.
- `scripts/test-hermeticity-lint.sh:2338`, `:2560`: lint messages.
- `scripts/deploy-parity-assert.sh:1081`, `1366`, `1368`, `1382`, `1435`, `1456`, `1459`, `1497`, `1504`: `report`/`printf` text.
- `scripts/deploy-link-parity.sh:509`: a `fix` suggestion string.
- `scripts/offbox-admission-lint.sh:274`: a message.
- `scripts/limit-recover/lr-handoff.sh:802`, `:829`: `echo` hints.
- `bin/cc-blockers:642`: a `recover_cmd` field in JSON output.
- `bin/cc-venue:187`: docstring.
- `scripts/cloud-answer.py:302`: only prints `rec['run']`.

**Patterns, ratchet entries and fixtures:**
- `scripts/permission-gate-lint.sh:169`: ratchet entry.
- `scripts/permission-gate-lint.sh:563`, `:589`, `:637`: fixture literals.
- `scripts/permission-gate-lint.sh:720-722`, `:745-747`, `:770`, `:782`: lint self-test arguments.
- `scripts/backlog-consolidation/group.py:143`, `:148`: regex and description.
- `bin/cc-eligible:169`: regex.
- `bin/cc-reaper:878`: allowlist regex.
- `bin/cc-dispatch:1282`: `.source` string match.
- `scripts/host-suites.manifest:1`, `:7`, `:156`: comments.

**Path assignments that never run anything by themselves:**
- `operator-readout.sh:314`, `:518`; `cc-do:89`, `:166`; `deploy-now.sh:56`; `ship-land.sh:1730`. Each is consumed by a site listed above.

**Lines that store a command without running it:**
- `deploy-live.sh:708-746`: builds `run=` strings for a page and a backlog row.
- `deploy-live.sh:812`: `cc-backlog needs --run`.
- `deploy-live.sh:960`, `:1043-1047`, `:1259-1262`: store the falsifier. `cc-backlog`'s add path only records `--falsifier` (:1898, :2275-2279).

**Nearby code that runs something, but never this path:**
- `bin/cc-backlog:4308`: runs `/bin/sh -c "$probe"`, but only in the `falsify` command with a probe the caller supplies. Nothing in scope passes it this path.
- `bin/cc-premise:1776` (`filing_day_screen`): turns a probe into git-grep clauses and refuses script calls (:1791-1794). It never runs the probe.
- `bin/cc-do:357`: the `CONFIRM=1` branch, which a deploy row never takes.
- `bin/cc-do:497` (`run_stem`): handles class `activation` only, and only files from `ACT_DIR`.

## (c) Does it re-exec itself, and where does the scheduled entry point live?

**Self re-exec: no.** In `deploy-live.sh` itself:
- The script's only lines that name `deploy-live` outside comments are strings: `printf`/`say`/`die` (:420, :434, :438-441), the stored run strings (:708-746) and the falsifier string (:960).
- `$0` is used only by `--help` (:419).
- The one other process it launches directly is `/bin/bash "$PARITY_ASSERT"` (:1483).

There is one indirect case: the falsifier it stores names itself, and `cc-premise:1392` later starts it as a separate process. That happens later, on a different process's claim path. It is not a re-exec.

**Scheduled entry point: outside the three trees.** The timer is `launchd/com.claude.deploy-live.plist:34-38`:
```
/bin/bash -c '… D="$HOME/.claude/scripts/deploy-live.sh"; [ -x "$D" ] || D="$HOME/Development/claude-infrastructure/scripts/deploy-live.sh"; exec "$D" --auto'
```
Three in-scope sites run without a human, but they are triggered by events rather than by a schedule:
- site 5, after every land;
- site 1, from a hook;
- site 6, when a backlog row is claimed.

## Stale citations found in comments
- `scripts/ship-land.sh` says `deploy-live.sh:2543` "dies DIVERGED". In this snapshot the DIVERGED block prints at `deploy-live.sh:2467`, and :2541 is the UNTRACKED COLLISION message.
- `scripts/deploy-live.sh:185` describes deploy-now as "`deploy-live.sh --force`". `deploy-now.sh:89` only forwards `"$@"` and adds no `--force`.
- The plist comment (:16) cites `hooks/operator-readout.sh:238-246` for the missing-file fallback check (I11). The check is actually at :509-518.
- `bin/cc-do` says it mirrors "operator-readout.sh §152-258". The matching code is at :503-546.