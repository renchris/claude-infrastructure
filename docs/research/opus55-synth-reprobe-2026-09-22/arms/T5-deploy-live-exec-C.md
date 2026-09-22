<!-- arm C = claude-opus-5-5 @xhigh · brief T5-deploy-live-exec · raw worker output, verbatim -->

# Execution sites of `scripts/deploy-live.sh` at 47c3317eb (hooks/, scripts/, bin/)

**Coverage limit:** this worker had no Grep or Glob tool, only Read, and a 25-call budget. So this is a set of verified sites, not a guaranteed-complete census.

- **Read in full:** `scripts/deploy-live.sh` (1–2729), `scripts/deploy-now.sh`, `bin/cc-do` (1–549), `launchd/com.claude.deploy-live.plist`.
- **Read in part:** `hooks/operator-readout.sh` 200–849, `bin/cc-premise` 1–962, 1000–1419 and 2880–3594, `bin/cc-backlog` 1–260 and 1500–2359, `hooks/validate-bash.sh` 1325–1453, `scripts/wrap-ledger.sh` 1–669 and 2170–2445.
- **Not opened:** every other file in the three trees, for example `scripts/ship-land.sh`, `scripts/postland-verify.sh`, `scripts/autonomy-sweep.sh`, `bin/cc-blockers` and `bin/cc-dispatch`.

## Execution sites

| # | Invocation line | How the target path is resolved | Args / flags | Mode | What the caller does with the exit status |
|---|---|---|---|---|---|
| 1 | `scripts/deploy-now.sh:89` `exec "$DEPLOY_LIVE" "$@"` | `DEPLOY_LIVE="${CC_DEPLOY_LIVE-$REPO/scripts/deploy-live.sh}"` (:56). It uses `-`, not `:-`, so an empty value is honoured (:54-55). `REPO="${CC_DEPLOY_REPO:-$HOME/Development/claude-infrastructure}"` (:53), and `export DEPLOY_REPO="$REPO"` (:60). If the target is not executable the script aborts with exit 1 and has no fallback (:72-78). | All caller args pass straight through (`"$@"`), e.g. `--force` or `--auto` (:6, :84-86) | Foreground `exec`: the process is replaced | It becomes deploy-now's own exit status; nothing runs after `exec` |
| 2 | `hooks/operator-readout.sh:534` `dout="$(DEPLOY_REPO="$SHARED" bash "$dscript" --dry-run --offline 2>&1)"; drc=$?` | `dscript="$DEPLOY_SCRIPT"` (:517). `DEPLOY_SCRIPT="${CC_DEPLOY_SCRIPT:-$HOME/.claude/scripts/deploy-live.sh}"` (:314). Fallback: `[ -e "$dscript" ] \|\| dscript="$SHARED/scripts/deploy-live.sh"` (:518). `SHARED="${CC_SHARED_CHECKOUT:-$HOME/Development/claude-infrastructure}"` (:297). Runs only if `$SHARED` is a git repo (:504), is on branch main or master (:507), and is behind (:508, :532). | `--dry-run --offline`, with env `DEPLOY_REPO=$SHARED`; stderr merged into stdout | Command substitution inside `render_block` (:468); this is the Stop-hook path | `0`: it appends a runnable `deploy ▶ bash <dscript>` board row (:535-537). Non-zero: it appends a `held ⊘` row whose reason is the last output line, prefixes stripped and truncated to 96 chars (:538-544). |
| 3 | `bin/cc-do:184` (same shape as site 2) | `dscript="$DEPLOY_SCRIPT"` (:165). `DEPLOY_SCRIPT="${CC_DEPLOY_SCRIPT:-$HOME/.claude/scripts/deploy-live.sh}"` (:89). Fallback to `$SHARED/scripts/deploy-live.sh` (:166). `SHARED` is set at :88. Same guards as site 2 (:157, :159, :167). | `--dry-run --offline`, env `DEPLOY_REPO=$SHARED` | Command substitution in `collect()` (:153). `collect` is called for every non-stem mode (:504). | `0`: it emits a `▶` deploy row whose 6th field (path) is `$dscript` (:186-187). Non-zero: it emits a `⊘` row (:196-198), which is never executed (:191-192). |
| 4 | `bin/cc-do:359` `bash "$1" </dev/null; rc=$?` (inside `run_one`) | Generic dispatcher. `$1` is the path field of a `▶` row, read by `run_steps` (:385-386) and passed at :389. For the deploy row that value is `$dscript` from site 3 (:187). The `CONFIRM=1` branch at :358 is not taken, because the deploy command is plain `bash …`. | None. `DEPLOY_REPO` is **not** pinned here, unlike :184, so deploy-live falls back to its own default (`deploy-live.sh:122`). | Foreground, stdin `/dev/null`. It is reached through `--run` or `CC_DO_ASSUME_YES=1` (:525), or through the interactive `Y` prompt (:543-548). With no TTY it refuses and exits 3 (:535-540). | For the deploy class, non-zero prints "SKIPPED" to stderr and returns 0, so the run continues (:369-373). `0` prints "✓" (:379). |
| 5 | `bin/cc-do:454` `bash -c "$cmd" </dev/null; rc=$?` (inside `run_backlog_row`) | Generic dispatcher. `cmd` is the stored `.run` of a blocked backlog row (:413-415). deploy-live.sh files such rows itself: `needs "$title" --run "$run"` (`deploy-live.sh:812`). The `run` strings name `bash $DEPLOY_REPO/scripts/deploy-live.sh` at :708, :728, :731, :734, :743 and :746, with the path baked in at filing time from `DEPLOY_REPO` (:122). | `--dry-run --offline` (:708 also adds a `CC_DEPLOY_SCAN=` prefix, :728, :731, :743, :746), or `--auto` after `git config --unset core.bare &&` (:734) | Foreground, stdin `/dev/null`. It is reached only through `cc-do <12-hex id>` (:470-473), after a typed `yes` (:450-452) or with `CC_DO_ASSUME_YES=1` (:435). It refuses without a TTY (:436-448), refuses slash commands (:423-426) and refuses placeholders (:427-430). | Non-zero prints "FAILED", leaves the row untouched and returns 1 (:455-457). `0` closes the row with `cc-backlog done` (:459-461). |
| 6 | `bin/cc-premise:1391-1396` `subprocess.run(["/bin/sh","-c",cmd], capture_output=True, text=True, timeout=FALSIFIER_TIMEOUT_S, cwd=REPO or None)` (inside `run_falsifier`) | Generic dispatcher. `cmd = ent["falsifier"]` (:1387), taken last-write-wins from the raw ledger (:523-524; store path at :98-100). deploy-live.sh stores `"$HOME/.claude/scripts/deploy-live.sh" --falsify-host '<suite>'…` (`fals_host`, :960-961). `$HOME` is left unexpanded, so `/bin/sh` resolves it at probe time (:956-959). The strings are filed by `add --falsifier` at :1044-1047 and :1259-1262. | `--falsify-host <suite> [<suite>…]`, each quoted by `fals_sq` (:948) | Foreground subprocess, output captured and cut to 300 chars (:1401). Timeout from `CC_PREMISE_FALSIFIER_TIMEOUT`, default 20 s (:241). Kill switch at :246 and :1385. | `0` gives `falsified` (:1402-1411), a blocking verdict (:236). `sweep --close-falsified` can then run `cc-backlog done` (:2904-2926). Non-zero is advisory "not refuted" (:1412-1419). Exit codes 2/124/126/127 mean "unaskable" (:254-266). A timeout or exception returns None, i.e. fail-open (:1397-1399). |

Notes on the table:
- **Site 6 callers:** only partly read. `cmd_sweep` calls `assess(…, run_probes=…)` at :3122, and `_close_falsified` calls `assess` at :2904. That `assess` calls `run_falsifier` is stated only in a comment (:2887-2888); the `assess` body was not read.
- **Site 6 exit contract on the deploy-live side:** `0` means every named suite is gone (:405-408), `1` means still live (:406), `2` means could not ask (:339-340, :372-375).
- **Dry runs are not write-free:** `--offline` forces `DRY_RUN=1` (:429), but `link_refresh` still runs `deploy-parity-assert` (:1483). It also calls `copy_drift_notice` (:1493), which writes a page and a signature marker with no `DRY_RUN` check (:1396-1423). So sites 2 and 3 can write `$PAGES_DIR/deploy-copy-drift.page`.

## (a) Total

**6 execution sites** are verified in scope.

Sites 4–6 are generic dispatchers that are handed deploy-live at runtime. Site 5 runs only after an operator's typed `yes`. If operator-confirmed dispatch is excluded, the count is 5.

## (b) Rejected near-misses

- `scripts/deploy-live.sh:419`: `sed -n '2,/^set -uo/p' "$0"` reads its own file for `--help`; it does not execute it.
- `scripts/deploy-live.sh:28`, `:185`, `:1813-1814`, `:2580`: comments.
- `scripts/deploy-live.sh:708`, `:728`, `:731`, `:734`, `:743`, `:746`: `run=` advisory strings. They go into the escalation page's `next:` line (:803) and into a `cc-backlog needs --run` row (:812). Their executor is site 5.
- `scripts/deploy-live.sh:960`: `fals_host` prints a stored falsifier string. Its executor is site 6.
- `scripts/deploy-live.sh:2376`: an `asay` log advisory (`CC_DEPLOY_MAX_LAG_COMMITS=0 bash …/deploy-live.sh`).
- `scripts/deploy-now.sh:5-6` are comments. `:73` is a human-facing abort message. `:87` is a stderr banner.
- `hooks/operator-readout.sh:536` is the rendered `deploy ▶ bash <dscript>` board row. `:543` is the held-row text. `:510-516` are comments.
- `bin/cc-do:187` and `:197` are the display `cmd` or label fields; execution reads the path field, not `cmd` (:148-149). `:28-29` are comments.
- `hooks/validate-bash.sh:1432`: a hook deny-reason blob ("Run the one sanctioned advance instead — … bash $ffg_shared/scripts/deploy-live.sh"). `:1380-1383` is a comment.
- `scripts/wrap-ledger.sh:2403`: the `rung_next` advisory `bash scripts/deploy-live.sh — …`, printed at :2391. `:88-89` and `:130-141` are comments.
- `bin/cc-backlog` `cmd_add`: `--falsifier` is only stored, never run (:1898, :2273-2285). The update arm refuses to write a falsifier at all (:2221-2227). So deploy-live's own filings do not execute the probe when they are filed.
- `bin/cc-premise` `cmd_screen` (:3416-3512): it calls `filing_day_screen`, whose body was not read. A comment (:3507-3509) says probes that call out-of-repo scripts come back UNDECIDABLE. Whether it executes them is unverified.
- `launchd/com.claude.deploy-live.plist:38`: a real execution, but in `launchd/`, outside the scope.

## (c) Self re-exec and the scheduled entry point

**deploy-live.sh never re-execs itself.**
- `$0` appears only in the help-text `sed` read (:419).
- The post-merge banner says re-exec'ing after the fast-forward is "Deliberately NOT done" (:2580-2585). The code after it (:2593-2729) confirms this: it starts no copy of itself.
- Its child processes are `deploy-parity-assert` (:1483), `deploy-migrations` (:1755, :1758), `offbox-green-pull` (:2071), `cc-kitty-reload` (:1938, :1942), bats (:1100) and `install.sh` (:2665). None of these is deploy-live.
- It spawns new copies of itself only indirectly: rows and falsifiers it files are later run by sites 5 and 6.

**The only scheduled entry point that performs a real advance is outside scope.** It is `launchd/com.claude.deploy-live.plist:38`:
`/bin/bash -c '…D="$HOME/.claude/scripts/deploy-live.sh"; [ -x "$D" ] || D="$HOME/Development/claude-infrastructure/scripts/deploy-live.sh"; exec "$D" --auto'`, with `StartInterval` 600 (:41-42) and `RunAtLoad` (:44-45). `deploy-now.sh:68-71` agrees that deploy-now has no unattended caller.

Inside the scoped trees, deploy-live still runs unattended, but only in its decision-only modes:
- **Site 2** runs `--dry-run --offline` from the Stop hook.
- **Site 6** runs `--falsify-host` from claim/sweep. That its callers are the cc-backlog claim guard and autonomy-sweep is stated only in comments (`bin/cc-premise:9-11`, `:431-437`), not verified in code.

## Stale citations found

| Comment | Cites | Actual location |
|---|---|---|
| `deploy-live.sh:14-15` | `validate-bash.sh:1352` | `:1432` |
| plist comment :16 | `operator-readout.sh:238-246` | `:510-518` |
| `cc-do:152` | readout `§152-258` | `:503-548` |
| `deploy-live.sh:2567-2568` | `host_checks` "at 151, called at 391" | defined `:1050`, called `:2723` |
