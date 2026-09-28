# Sites that execute `scripts/deploy-live.sh` (snapshot 47c3317eb, scoped to `hooks/`, `scripts/`, `bin/`)

I read the snapshot at `/tmp/s55/repo-47c3317eb`. The brief names `/tmp/o55probe-repo-47c3317eb`, which I didn't use.

**Method.** I grepped all three trees for the literal name and for the seam variables (`DEPLOY_SCRIPT`, `CC_DEPLOY_LIVE`, `DEPLOY_LIVE`, `deploy-now`). I then read each hit in context. Every claim below is from lines I read, not from comment summaries. I did not grep every possible way of building the path from parts. Any call whose path is computed without the literal `deploy-live` would not have surfaced.

## (a) Total: 7 distinct execution sites

Five resolve the path directly. Two run a string that arrives as data at runtime. If you count the two arms of `cc-do:358`/`359` as separate lines, the total is 8.

### 1. `scripts/deploy-now.sh:89` — `exec "$DEPLOY_LIVE" "$@"`
1. **Path resolution:** `DEPLOY_LIVE="${CC_DEPLOY_LIVE-$REPO/scripts/deploy-live.sh}"` at `scripts/deploy-now.sh:56`. The default uses `-`, not `:-`, so a set-but-empty override stays empty. `REPO="${CC_DEPLOY_REPO:-$HOME/Development/claude-infrastructure}"` is at `scripts/deploy-now.sh:52`.
2. **Guard:** `[ ! -x "$DEPLOY_LIVE" ]` aborts with `exit 1` at `scripts/deploy-now.sh:72-74`. There is no fallback to a raw fast-forward.
3. **Arguments:** all of the caller's `"$@"`, passed unchanged. `DEPLOY_REPO="$REPO"` is exported at line 60.
4. **Mode:** foreground, and it replaces the process, so nothing runs after it.
5. **Exit status:** the process becomes deploy-live, so its exit status is deploy-now's. Nothing wraps it.

### 2. `scripts/ship-land.sh:1739` — `subprocess.Popen(["bash", sys.argv[1]], …)`
1. **Path resolution:** `dl_script="$dl_repo/scripts/deploy-live.sh"` at `scripts/ship-land.sh:1730`. `dl_repo="${DEPLOY_REPO:-$HOME/Development/claude-infrastructure}"` is at line 1729. The script is passed to Python as `"$dl_script"` (`argv[1]`) at line 1741.
2. **Guards:**
   - The kick is skipped if `SHIP_LAND_CONVERGE=off` (`ship-land.sh:1727`).
   - It needs `[[ -f "$dl_script" ]]` (line 1731).
   - It needs `git -C "$dl_repo" cherry origin/"$TRUNK" HEAD` to return empty (lines 1732-1734).
3. **Arguments:** none. The child gets `cwd=$dl_repo`, an environment with `CC_DEPLOY_MAX_LAG_COMMITS=0` added (lines 1737-1738), and stdout/stderr appended to `converge-edge.log`.
4. **Mode:** detached. `start_new_session=True` (line 1741), `stdin=DEVNULL`, and no `wait()`.
5. **Exit status:** never read. `python3 … || true` (line 1741) only swallows a failure to spawn. The next line, `ship-land.sh:1742`, prints "converge kicked" and the land returns 0.

### 3. `bin/cc-do:184` — `dout="$(DEPLOY_REPO="$SHARED" bash "$dscript" --dry-run --offline 2>&1)"; drc=$?`
1. **Path resolution:** `dscript="$DEPLOY_SCRIPT"` at `bin/cc-do:165`. `DEPLOY_SCRIPT="${CC_DEPLOY_SCRIPT:-$HOME/.claude/scripts/deploy-live.sh}"` is at `bin/cc-do:89`. The fallback `[ -e "$dscript" ] || dscript="$SHARED/scripts/deploy-live.sh"` is at `bin/cc-do:166`.
2. **Arguments:** `--dry-run --offline`, with `DEPLOY_REPO` pinned to `$SHARED` in the environment.
3. **Mode:** foreground, inside a command substitution, with stderr merged into stdout. It only runs when `behind > 0`.
4. **Exit status:** captured as `drc`. Exit 0 emits a runnable `▶` row (`bin/cc-do:186-187`). Non-zero emits a `⊘` held row with the last output line as the reason (`bin/cc-do:194-198`).

### 4. `hooks/operator-readout.sh:534` — the same probe, in the hook
1. **Path resolution:** `dscript="$DEPLOY_SCRIPT"` at `hooks/operator-readout.sh:517`. `DEPLOY_SCRIPT="${CC_DEPLOY_SCRIPT:-$HOME/.claude/scripts/deploy-live.sh}"` is at `hooks/operator-readout.sh:314`. The fallback `[ -e "$dscript" ] || dscript="$SHARED/scripts/deploy-live.sh"` is at `hooks/operator-readout.sh:518`.
2. **Arguments and mode:** identical to site 3. It runs in the foreground inside `$(…)`, guarded by `behind > 0` (`hooks/operator-readout.sh:533`).
3. **Exit status:** `drc` decides between a `deploy` row and a `held` row, both written to `$steps_file` (`hooks/operator-readout.sh:535-544`). This hook only renders. It never runs the `▶` row.

### 5. `bin/cc-do:358` and `359` — `run_one`: `CONFIRM=1 bash "$1" </dev/null` or `bash "$1" </dev/null`
This is a generic dispatcher. It is handed the path at runtime.
1. **Path resolution:** `$1` is the `path` field read in `run_steps` (`bin/cc-do:383-389`). That field is the sixth argument of `emit deploy '▶' … "$dscript"` at `bin/cc-do:186-187`. It goes through `dscript` (165-166) and `DEPLOY_SCRIPT` (89), as in site 3. `emit` writes it at `bin/cc-do:148`.
2. **Which arm runs:** line 358 runs when the command starts with `CONFIRM=1 `. Line 359 otherwise, which is the deploy case.
3. **Arguments:** none. `stdin` is `/dev/null`.
4. **Mode:** foreground. It runs when `cc-do` is in run mode or `CC_DO_ASSUME_YES=1` (`bin/cc-do:525`), or after the interactive Y/n (`bin/cc-do:548`).
5. **Exit status:** `rc=$?`. For class `deploy`, a non-zero exit prints "SKIPPED … Continuing" and `run_one` returns 0 (`bin/cc-do:360-372`), so a refusal never halts the run. On success it prints `✓`.

### 6. `bin/cc-premise:1392` — `subprocess.run(["/bin/sh", "-c", cmd], …)` in `run_falsifier` (data-driven)
1. **Path resolution:** `cmd` is the item's stored `falsifier` field (`bin/cc-premise:1381-1383`). For post-deploy host-cut items, `deploy-live.sh` stores `"$HOME/.claude/scripts/deploy-live.sh" --falsify-host '<suite>'…`. That string is built at `scripts/deploy-live.sh:960-961`. It is stored via `--falsifier "$(fals_host "$1")"` at `scripts/deploy-live.sh:1046`, and `fals_host_set` does the same at `scripts/deploy-live.sh:1261`. `$HOME` is left unexpanded on purpose and resolves at probe time (`scripts/deploy-live.sh:1040-1043`).
2. **Arguments:** `--falsify-host <suite>…`, handled by the branch at `scripts/deploy-live.sh:337`.
3. **Mode:** foreground, captured, with a timeout (`FALSIFIER_TIMEOUT_S`) and `cwd=REPO`. The call is made from line 2310.
4. **Exit status:** exit 0 gives verdict `falsified`, which is the only blocking answer. Non-zero is advisory. A timeout or exception fails open by returning `None` (`bin/cc-premise:1393-1409`).
5. **Caveat:** it only fires for items that carry such a falsifier. `cc-premise` is generic and never names the script itself.

### 7. `bin/cc-do:454` — `bash -c "$cmd" </dev/null; rc=$?` in `run_backlog_row` (data-driven)
1. **Path resolution:** `$cmd` is the `--run` string stored on a backlog row. `deploy-live.sh` files such rows with `"$BACKLOG_BIN" needs "$title" --run "$run"` at `scripts/deploy-live.sh:812`. The `run` values are assigned at `scripts/deploy-live.sh:708, 728, 731, 734, 743, 746`. Each is `bash $DEPLOY_REPO/scripts/deploy-live.sh --dry-run --offline`, except line 734, which is `git -C … config --unset core.bare && bash …/deploy-live.sh --auto`.
2. **Mode:** foreground. It needs a typed `yes`, or `CC_DO_ASSUME_YES` (`bin/cc-do:451-452`); with no terminal it refuses (`bin/cc-do:437-447`).
3. **Exit status:** non-zero prints FAILED and returns 1, leaving the row open. Zero closes the row via `cc-backlog done` (`bin/cc-do:455-464`).

## (b) Near-misses rejected

**Help text, banners, board rows and "reason" blobs (shown to a human, never run):**
- `hooks/activation-watch.sh:471`, `:492` — `▶ bash $root/scripts/deploy-live.sh` is appended to an output string for the operator.
- `hooks/session-continue.sh:1191` — inside the `reason=` string of a ship-floor hook blob.
- `hooks/operator-readout.sh:536` — the printf that writes the `▶` row into `$steps_file`. The hook never executes rows.
- `hooks/operator-readout.sh:543` — the printf that writes the held row.
- `hooks/operator-readout.sh:887` — `dact=" → bash scripts/deploy-live.sh"` is display text.
- `hooks/lib/why-tier.sh:249` — advice text.
- `hooks/validate-bash.sh:1425`, `:1432` — `deny "…"` messages.
- `hooks/completion-assert.sh:782`, `:784` — a facts string.
- `scripts/wrap-ledger.sh:2068` — a READOUT string.
- `scripts/wrap-ledger.sh:2403` — a printf'd ledger action.
- `scripts/kitty-title-band-deploy.sh:193` — the text of a `die` message.
- `scripts/handoff-fire.sh:9153` — an echoed message.
- `scripts/handoff-fire.sh:12619` — a `rcy_tok_why` string.
- `scripts/limit-recover/lr-handoff.sh:802`, `:829` — echoed messages.
- `scripts/deploy-link-parity.sh:509` — the argument to `fix`, which prints a remedy.
- `scripts/deploy-parity-assert.sh:1459` — a printf'd remedy.
- `bin/cc-blockers:642` — the `recover_cmd` JSON field. It is a paste-ready remedy string, and I found no code here that runs it.
- `scripts/ship-land.sh:4511` — an echo.
- `scripts/deploy-parity-assert.sh:1081`, `:1366`, `:1368`, `:1382`, `:1435`, `:1456`, `:1497`, `:1504` — messages and report labels. The one at `:1504` is a `grep -c` command printed for a human to run.
- `scripts/wrap-ledger.sh:2068` is covered above. `scripts/backlog-consolidation/group.py:143`, `:148` is a regex and prose (see grep/lint patterns below).

**Advisory strings and page records inside `deploy-live.sh`:**
- `scripts/deploy-live.sh:708`, `:728`, `:731`, `:734`, `:743`, `:746` — `run=` assignments. They only become a page line (`:803`) and a `--run` argument on a stored backlog row (`:812`). Execution happens only through site 7.
- `scripts/deploy-live.sh:960` — a `printf` that builds the falsifier string. Execution happens only through site 6.

**Grep/lint patterns, ratchet entries, fixture literals:**
- `scripts/permission-gate-lint.sh:169` — a ratchet-table entry.
- `scripts/permission-gate-lint.sh:563`, `:589` — `mk` fixture bodies.
- `scripts/permission-gate-lint.sh:637` — fixture text.
- `scripts/permission-gate-lint.sh:720-722`, `:745-747`, `:770`, `:782` — ratchet-table entries passed to the lint's self-tests.
- `scripts/test-hermeticity-lint.sh:2338`, `:2560` — lint messages.
- `scripts/offbox-admission-lint.sh:274` — a lint message.
- `bin/cc-eligible:169` — a regex tuple.
- `bin/cc-reaper:878` — a whitelist name in a pipe-delimited pattern.
- `bin/cc-dispatch:1282` — a jq comparison against the string `"deploy-live"`, which is a source label.
- `scripts/backlog-consolidation/group.py:143`, `:148` — a regex and prose.

**Bare path assignments that are never invoked:**
- `hooks/operator-readout.sh:314` and `bin/cc-do:89` — the `DEPLOY_SCRIPT` seams. They are executed only through the sites above.
- `scripts/deploy-now.sh:56` — `DEPLOY_LIVE` is invoked at `:89` (site 1).
- `scripts/ship-land.sh:1730` — `dl_script` is invoked at `:1739` (site 2).

**`deploy-live.sh` referring to itself:**
- `scripts/deploy-live.sh:420`, `:434`, `:438`, `:440`, `:441`, `:752` and the other `deploy-live:` prefixes — message text.
- `scripts/deploy-live.sh:419` — `sed -n … "$0"` only reads its own header for `--help`.
- `scripts/deploy-live.sh:1047`, `:1262` — `--source deploy-live` is a label passed to `cc-backlog`.

**Comments:** `hooks/config-mirror-assert.sh:36`, `scripts/deploy-live.sh:28`, `:37`, `:498`, and the many `#` mentions in `scripts/deploy-now.sh`, `hooks/operator-readout.sh` and `scripts/ship-land.sh`.

## (c) Self re-exec and the scheduled entry point

**Does it re-exec itself? No.** In `scripts/deploy-live.sh`, `$0` appears only in the `--help` `sed` at `:419`. There is no `exec`, no `BASH_SOURCE`, and no `bash … deploy-live.sh` outside the `run=` strings at `:708-746` and the printf at `:960`. Both of those are strings that other tools run later (sites 6 and 7), not re-execs. The other hits from that search (`:554`, `:787`) are an `awk` `exit` and message text. This is a grep-based negative over the file, not a full read of it.

**The scheduled entry point is outside the scoped trees.** `launchd/com.claude.deploy-live.plist:38` runs `/bin/bash -c '… D="$HOME/.claude/scripts/deploy-live.sh"; [ -x "$D" ] || D="$HOME/Development/claude-infrastructure/scripts/deploy-live.sh"; exec "$D" --auto'`. `launchd/fleet.manifest:132` schedules it every 600s. `launchd/` is not one of `hooks/`, `scripts/` or `bin/`, so it is out of scope for the count.

Inside the scoped trees there is no scheduled or timer-driven caller. `scripts/deploy-now.sh:66-68` says the same about itself: no unattended caller, and the plist runs `deploy-live.sh --auto` directly. The one automated in-scope trigger is site 2. It is event-driven (once per green land) and detached, not scheduled.

## Stale citations I found

- `scripts/ship-land.sh:1704` cites `deploy-live.sh:2543` as the point where it "dies DIVERGED". At this snapshot, `:2467` is the DIVERGED block (`BLOCKED: $DIV_MSG`) and `:2541` is the untracked-collision block. I did not read `:2543` itself, so it is stale or at best unverified.
- I did not check the other cited lines: `deploy-live.sh:180` (the "no run lock" claim) in the same ship-land comment, and `operator-readout.sh:238-246` in the plist. I relied on neither.
