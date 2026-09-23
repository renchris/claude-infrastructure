<!-- arm C = claude-opus-5-5 @xhigh · brief T5-deploy-live-exec · settle run 1 (wf_e43f474d-ad0) · raw worker output, verbatim -->

## Execution sites of `scripts/deploy-live.sh` at snapshot 47c3317eb

The snapshot has **6 distinct execution sites** inside `hooks/`, `scripts/` and `bin/`. Three perform a real deploy: `ship-land`, `deploy-now` and `cc-do run_one`. Two are `--dry-run --offline` probes. One is a falsifier dispatcher that runs the `--falsify-host` probe mode. The only scheduled entry point is outside the three trees, in `launchd/`.

Method: I listed every `deploy-live` line in the three trees (316 hits) and dropped comment-only lines. I then traced every variable that holds the path: `DEPLOY_SCRIPT`, `dscript`, `DEPLOY_LIVE`, `dl_script` and `path`. I also traced every generic `sh -c` / `bash -c` / `subprocess` executor that could be handed the path.

### Site 1: `scripts/ship-land.sh:1736` (`python3 -c`; `Popen` at :1739)
1. **Where:** `post_release_finish()` (`scripts/ship-land.sh:1600`), after a content-verified land.
2. **How the path resolves:** `Popen(["bash", sys.argv[1]], …)` (`:1739`). Here `sys.argv[1]` is `"$dl_script"` (`:1741`).
   - `dl_script="$dl_repo/scripts/deploy-live.sh"` (`:1730`).
   - `dl_repo="${DEPLOY_REPO:-$HOME/Development/claude-infrastructure}"` (`:1729`).
   - The kick only happens if all of these hold: `SHIP_LAND_CONVERGE` is not `off` (`:1727`), the file exists (`:1731`), and `git -C "$dl_repo" cherry origin/$TRUNK HEAD` returns rc 0 with empty output (`:1732-1733`).
3. **Arguments:** none. The environment is `os.environ` plus `CC_DEPLOY_MAX_LAG_COMMITS="0"` (`:1737`). `cwd=dl_repo`.
4. **Mode:** detached. `start_new_session=True`, stdin is `DEVNULL`, and stdout and stderr are appended to `converge-edge.log` (`:1734`, `:1738-1741`). It is never waited on.
5. **Exit status:** never collected. The launcher's own status is discarded (`2>/dev/null || true`, `:1741`), and `✓ … converge kicked` is printed unconditionally (`:1742`).

### Site 2: `scripts/deploy-now.sh:89`
1. **Invocation:** `exec "$DEPLOY_LIVE" "$@"`.
2. **How the path resolves:**
   - `DEPLOY_LIVE="${CC_DEPLOY_LIVE-$REPO/scripts/deploy-live.sh}"` (`:56`). It uses `-`, so a set-but-empty value is honoured.
   - `REPO="${CC_DEPLOY_REPO:-$HOME/Development/claude-infrastructure}"` (`:53`).
   - `export DEPLOY_REPO="$REPO"` (`:60`).
   - It aborts before the exec if `$REPO` is missing (`:62`) or `$DEPLOY_LIVE` is not executable (`:72-77`).
3. **Arguments:** all of its own argv is passed through. A banner goes to stderr unless `--auto` or `--offline` is given (`:83-87`).
4. **Mode:** foreground, replacing the process (`exec`).
5. **Exit status:** it becomes `deploy-now`'s own exit status.
- There is no non-comment caller of `deploy-now` anywhere in the three trees (grep came back empty).

### Site 3: `hooks/operator-readout.sh:534`
1. **Invocation:** `dout="$(DEPLOY_REPO="$SHARED" bash "$dscript" --dry-run --offline 2>&1)"; drc=$?`, inside `render_block()` (`:468`).
2. **How the path resolves:**
   - `dscript="$DEPLOY_SCRIPT"` (`:517`), with fallback `[ -e "$dscript" ] || dscript="$SHARED/scripts/deploy-live.sh"` (`:518`).
   - `DEPLOY_SCRIPT="${CC_DEPLOY_SCRIPT:-$HOME/.claude/scripts/deploy-live.sh}"` (`:314`).
   - `SHARED="${CC_SHARED_CHECKOUT:-$HOME/Development/claude-infrastructure}"` (`:297`).
   - It runs only when the shared checkout is on main/master and `behind > 0` (`:507-509`, `:532`).
3. **Arguments:** `--dry-run --offline`, with env `DEPLOY_REPO=$SHARED`.
4. **Mode:** command substitution (stdout and stderr captured).
5. **Exit status:** rc 0 writes a `▶ bash …` deploy row (`:535-537`). Non-zero writes a `held ⊘` row whose reason is the last output line (`:538-544`).

### Site 4: `bin/cc-do:184`
1. **Invocation:** the same probe as site 3, inside `collect()` (`:153`).
2. **How the path resolves:**
   - `dscript="$DEPLOY_SCRIPT"` (`:165`), with fallback to `$SHARED/scripts/deploy-live.sh` (`:166`).
   - `DEPLOY_SCRIPT="${CC_DEPLOY_SCRIPT:-$HOME/.claude/scripts/deploy-live.sh}"` (`:89`).
   - `SHARED="${CC_SHARED_CHECKOUT:-…/claude-infrastructure}"` (`:88`).
   - It is gated on `behind > 0` (`:167`).
3. **Arguments:** `--dry-run --offline`, with env `DEPLOY_REPO=$SHARED`.
4. **Mode:** command substitution.
5. **Exit status:** rc 0 emits a runnable `▶` row whose 6th field (`path`) is `"$dscript"` (`:185-187`). Non-zero emits a `⊘` row that `run_steps` skips (`:193-198`, `:386`).

### Site 5: `bin/cc-do:359`, a generic dispatcher handed the path at runtime
1. **Invocation:** `else bash "$1" </dev/null; rc=$?` in `run_one()` (`:356`).
2. **How the path resolves:**
   - `$1` is the `path` field read by `run_steps` (`:385`) and passed at `:389`.
   - That field is the `"$dscript"` emitted at `:186-187` (site 4's resolution).
   - The displayed `cmd` string (`bash ~/…`) is **not** what runs.
   - The `CONFIRM=1 bash "$1"` arm (`:358`) is not taken for the deploy row, because its `cmd` does not start with `CONFIRM=1 `.
3. **Arguments:** none.
4. **Mode:** foreground, stdin `/dev/null`.
   - It runs via `run_steps` from `--run` or `CC_DO_ASSUME_YES=1` (`:525`), or after the interactive `[Y/n]` (`:543-548`).
   - If stdin is not a tty, it exits 3 before running anything (`:535-540`).
5. **Exit status:** for class `deploy`, non-zero prints `SKIPPED` and returns 0, so the run continues (`:360`, `:369-372`). Zero prints `✓` (`:379`).

### Site 6: `bin/cc-premise:1391-1392`, a falsifier dispatcher handed the path through stored data
1. **Invocation:** `subprocess.run(["/bin/sh", "-c", cmd], capture_output=True, …)` in `run_falsifier()` (`:1362`). It is called from `assess()` (`:2252`) at `:2310`.
2. **How the path resolves:**
   - `cmd = ent.get("falsifier")` (`:1387`), which is a stored backlog field.
   - `deploy-live.sh` writes that field itself: `fals_host` prints `"$HOME/.claude/scripts/deploy-live.sh" --falsify-host '<suite>'…` (`scripts/deploy-live.sh:960-961`), and this is stored via `"$BACKLOG_BIN" add … --falsifier "$(fals_host "$1")"` (`:1044-1047`).
   - `$HOME` is expanded by `/bin/sh` when the probe runs.
   - `cwd=REPO` (`:129`, `CC_PREMISE_REPO`). Timeout is `FALSIFIER_TIMEOUT_S` (`:241`, default 20). Kill switch is `CC_PREMISE_FALSIFIER` (`:246`).
   - Upstream: `cc-backlog`'s claim path runs `pout="$("$pbin" check "$id" 2>&1)"` (`bin/cc-backlog:3046`, in `cmd_transition` `:2480`). `pbin` defaults to the sibling `cc-premise` (`bin/cc-backlog:3579`). I did not trace `check` → `assess` inside `cc-premise`.
3. **Arguments:** `--falsify-host <suite>...`. That mode is handled at `scripts/deploy-live.sh:337` and always exits at `:339-408`, before the argument loop and deploy body (`:411`).
4. **Mode:** synchronous and captured, the equivalent of a command substitution.
5. **Exit status:** 0 means verdict `falsified` (`:1402-1403`). A timeout or exception returns `None`, which fails open (`:1397-1399`).

### (a) Total
**6** (the table below lists 5 lines; `bin/cc-do` has two sites). Two more generic dispatchers could run the script but no code in scope hands them its path, so I did not count them:
- `bin/cc-do:454` runs `bash -c "$cmd"` for a backlog row's `--run`. None of the non-comment `deploy-live` lines in scope passes it as a `--run` argument.
- `bin/cc-backlog:4308` runs `/bin/sh -c "$probe"`, but only on the argv probe of `cc-backlog falsify`. No caller in scope passes one.

### (b) Near-misses rejected
| path:line | reason |
|---|---|
| `hooks/operator-readout.sh:314`, `:518` | path assignment and fallback; they feed site 3 but invoke nothing themselves |
| `hooks/operator-readout.sh:536-537`, `:541`, `:543-544` | rendered board row text and string stripping; nothing in the readout executes it |
| `hooks/operator-readout.sh:887` | `dact=" → bash scripts/deploy-live.sh"` is a display fragment |
| `hooks/activation-watch.sh:471`, `:492` | appended to the advisory `out` text |
| `hooks/session-continue.sh:1191` | inside the Stop-hook `reason="…"` blob (`:1187-1193`) |
| `hooks/validate-bash.sh:1425`, `:1432` | `deny` reason text |
| `hooks/completion-assert.sh:782`, `:784` | `facts` string |
| `hooks/lib/why-tier.sh:249` | help text |
| `scripts/deploy-now.sh:56` / `:73` / `:87` | path assignment (feeds site 2) / error echo / banner |
| `scripts/ship-land.sh:1730` / `:4511` | path assignment (feeds site 1) / stderr echo |
| `scripts/wrap-ledger.sh:2068`, `:2403` | readout string and advisory printf |
| `scripts/kitty-title-band-deploy.sh:193` | `die` message |
| `scripts/handoff-fire.sh:9153`, `:12619` | echo and advisory `rcy_tok_why` string |
| `scripts/deploy-link-parity.sh:509` | `fix()` only appends to the `FIXES` display string (`:159`) |
| `scripts/limit-recover/lr-handoff.sh:802`, `:829` | stderr echo |
| `scripts/deploy-parity-assert.sh:1081`, `:1366`, `:1368`, `:1382`, `:1435`, `:1456`, `:1459`, `:1497`, `:1504` | printf/report text; `:1459` prints the `--dry-run` command for a human |
| `scripts/offbox-admission-lint.sh:274` | printf |
| `scripts/test-hermeticity-lint.sh:2338`, `:2560` | lint messages |
| `scripts/permission-gate-lint.sh:169` | ratchet-table entry |
| `scripts/permission-gate-lint.sh:104` | `EMBEDDED_SET` lint glob `scripts/deploy-*` |
| `scripts/permission-gate-lint.sh:526`, `:535` | echo text |
| `scripts/permission-gate-lint.sh:563`, `:589`, `:637`, `:720-722`, `:745-747`, `:770`, `:782` | selftest fixture literals |
| `scripts/backlog-consolidation/group.py:143`, `:148` | regex and string |
| `scripts/host-suites.manifest:1`, `:7`, `:156` | comment lines in a data manifest |
| `scripts/deploy-live.sh:708-746` | `run=` strings in the escalation/page record |
| `scripts/deploy-live.sh:960`, `:1047` | stores the falsifier string; it is executed by site 6, not here |
| `scripts/deploy-live.sh:419` | `sed … "$0"` reads its own header for `--help`; not an exec |
| `scripts/deploy-live.sh:1483` | runs `$PARITY_ASSERT`, not itself |
| `scripts/deploy-live.sh:2471` | page filename `deploy-$DIV_CLASS.page` |
| `bin/cc-do:89`, `:166` | assignment and fallback (feed sites 4 and 5) |
| `bin/cc-do:186-187`, `:196-198` | the `cmd` field is display text; only field 6 is executed |
| `bin/cc-do:194` | string stripping |
| `bin/cc-blockers:642` | `recover_cmd` JSON field, rendered only as a board cell (`:1299`, `:1582`, `:1596`) |
| `bin/cc-eligible:169` | regex |
| `bin/cc-reaper:878` | whitelist regex `wl=` |
| `bin/cc-dispatch:1282` | jq `.source == "deploy-live"` comparison |
| `bin/cc-venue:187` | prose |
| all remaining hits (e.g. `postland-verify.sh`, `nightly-regression.sh`, `offbox-green-pull.sh`, `deploy-migrations.sh`, `bin/cc-backlog`, `cc-kitty-reload`, `cc-premise`, `cc-owner`, `cc-fleet`, `cc-cannot`) | comment lines |

### (c) Self re-exec and the scheduled entry point
- **Self re-exec:** none. `deploy-live.sh`'s only uses of `$0`/`exec` are the help `sed` (`:419`) and running `deploy-parity-assert` (`:1483`). Its `--falsify-host` mode is started by a separate process, `cc-premise` (site 6), from strings it stored earlier. That is not a self re-exec.
- **Scheduled entry point:** it lives **outside** the three trees, in `launchd/com.claude.deploy-live.plist:36-38`. That runs `/bin/bash -c '…D="$HOME/.claude/scripts/deploy-live.sh"; [ -x "$D" ] || D="$HOME/Development/claude-infrastructure/scripts/deploy-live.sh"; exec "$D" --auto'`, every 600s (`:41-42`) and at load (`:44-45`).
- **Automatic but not scheduled, inside scope:** the ship-land kick (site 1, once per land), the Stop-hook dry-run (site 3), and the falsifier probe on the claim path (site 6).

### Stale citations found in comments
- `scripts/ship-land.sh:1703` says "deploy-live.sh:2543 dies DIVERGED". At this snapshot the DIVERGED message is at `deploy-live.sh:2467`, and `:2541` is UNTRACKED COLLISION.
- `launchd/com.claude.deploy-live.plist:16` cites `hooks/operator-readout.sh:238-246` for the fallback. The code is at `:517-518`.
- `bin/cc-do:152` says "mirror hooks/operator-readout.sh §152-258". The deploy producer is at `:503-547`.
- I did not verify, and did not rely on, `ship-land.sh:1719`'s claim about `deploy-live.sh:180`.