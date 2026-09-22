<!-- arm B = claude-opus-5-5 @high · brief T5-deploy-live-exec · raw worker output, verbatim -->

# Execution sites of `scripts/deploy-live.sh` at snapshot 47c3317eb

**This list is not exhaustive. Six in-scope sites were confirmed, so treat 6 as a lower bound.** Grep and Glob were not available in this session; `ToolSearch("select:Grep,Glob")` returned "No matching deferred tools found". The brief forbids Bash, so I could only open files I expected to matter and read them. Files read in full or in part: `scripts/deploy-live.sh` (all 2730 lines), `scripts/deploy-now.sh`, `bin/cc-do` (all), `hooks/operator-readout.sh` (lines 180–899), `bin/cc-premise` (lines 1–300, 560–889, 1000–1329, 1380–1929), `hooks/validate-bash.sh` (lines 1325–1384) and `launchd/com.claude.deploy-live.plist`. I did not read `scripts/wrap-ledger.sh`, `scripts/ship-land.sh`, `bin/cc-backlog`, `bin/cc-dispatch`, `bin/cc-blockers`, `scripts/autonomy-sweep.sh` or anything else in `hooks/`, `scripts/` or `bin/`.

## The six sites

### 1. `scripts/deploy-now.sh:89` — `exec "$DEPLOY_LIVE" "$@"`
- **How the path is resolved:**
  - `DEPLOY_LIVE="${CC_DEPLOY_LIVE-$REPO/scripts/deploy-live.sh}"` (:56). It uses `-` rather than `:-`, so setting it to an empty string is honoured.
  - `REPO="${CC_DEPLOY_REPO:-$HOME/Development/claude-infrastructure}"` (:53).
  - `export DEPLOY_REPO="$REPO"` (:60).
  - If the path is not executable, the script exits 1 with no fallback (:72-78).
- **Arguments:** every caller argument is passed through unchanged (:89). A banner goes to stderr unless `--auto` or `--offline` is present (:83-87).
- **Mode:** foreground. `exec` replaces the process, so there is no child.
- **Exit status:** it becomes `deploy-now.sh`'s own exit status. Nothing after line 89 runs.

### 2. `hooks/operator-readout.sh:534` — `dout="$(DEPLOY_REPO="$SHARED" bash "$dscript" --dry-run --offline 2>&1)"; drc=$?`
- **How the path is resolved:**
  - `dscript="$DEPLOY_SCRIPT"` (:517).
  - `DEPLOY_SCRIPT="${CC_DEPLOY_SCRIPT:-$HOME/.claude/scripts/deploy-live.sh}"` (:314).
  - Fallback: `[ -e "$dscript" ] || dscript="$SHARED/scripts/deploy-live.sh"` (:518).
  - `SHARED="${CC_SHARED_CHECKOUT:-$HOME/Development/claude-infrastructure}"` (:297).
- **When it runs:** only if `$SHARED` is a git repo (:504), its branch is `main` or `master` (:507), and it is more than 0 commits behind (:532).
- **Arguments:** `--dry-run --offline`, with `DEPLOY_REPO=$SHARED` in the environment. In `deploy-live.sh`, `--offline` forces `DRY_RUN=1` (:429).
- **Mode:** inside a command substitution, with stderr merged into stdout.
- **Exit status:**
  - `drc==0` writes a runnable `deploy ▶` row (:535-537).
  - Anything else writes a `held ⊘` row carrying the last output line, stripped and cut to 96 characters (:538-545).

### 3. `bin/cc-do:184` — `dout="$(DEPLOY_REPO="$SHARED" bash "$dscript" --dry-run --offline 2>&1)"; drc=$?`
- **How the path is resolved:**
  - `dscript="$DEPLOY_SCRIPT"` (:165).
  - `DEPLOY_SCRIPT="${CC_DEPLOY_SCRIPT:-$HOME/.claude/scripts/deploy-live.sh}"` (:89).
  - Fallback: `$SHARED/scripts/deploy-live.sh` (:166).
  - `SHARED="${CC_SHARED_CHECKOUT:-…/claude-infrastructure}"` (:88).
- **When it runs:** same three conditions as site 2 (:157, :159, :167).
- **Arguments:** `--dry-run --offline`, with `DEPLOY_REPO=$SHARED`.
- **Mode:** inside a command substitution.
- **Exit status:**
  - 0 emits a `deploy ▶` row whose path field is `$dscript` (:185-187).
  - Anything else emits a `⊘` row with the reason cut to 110 characters (:193-198). Execution only ever runs `▶` rows (:386).

### 4. `bin/cc-do:359` — `bash "$1" </dev/null; rc=$?` (in `run_one`)
- **How the path is resolved:**
  - `$1` is the row's path field, passed by `run_steps` (:389).
  - For a deploy row that field is `$dscript`, emitted at :186-187 and resolved as in site 3.
  - Line :358 is the `CONFIRM=1` branch. It is not taken for a deploy row, because that row's command starts with `bash ` (:187).
- **Arguments:** none. This is a real, fetching, non-dry run.
  - `DEPLOY_REPO` is not set here, although the probe at :184 does set it. With `CC_SHARED_CHECKOUT` overridden, the probe and the real run can refer to different checkouts.
- **Mode:** foreground, with stdin from `/dev/null`.
- **How it is reached:**
  - Via :525 (`--run` or `CC_DO_ASSUME_YES=1`), or via :548 after the `[Y/n]` prompt (:543-547).
  - With stdin not a terminal, it exits 3 and runs nothing (:535-541).
- **Exit status:**
  - A non-zero exit on a deploy row prints SKIPPED and `return 0`, so the run continues (:369-373).
  - Zero prints ✓ (:379).

### 5. `bin/cc-do:454` — `bash -c "$cmd" </dev/null; rc=$?` (in `run_backlog_row`, a generic dispatcher)
- **How the command is resolved:**
  - `cmd` is the blocked backlog row's `.run` field (:413-415), for an id given as `cc-do <12-hex id>` (:470-472, :502).
  - It reaches `deploy-live.sh` because `deploy-live.sh` files such rows itself: `"$BACKLOG_BIN" needs "$title" --run "$run"` (:811-812).
  - The stored `run` strings are at :708, :728, :731, :743 and :746 (`bash $DEPLOY_REPO/scripts/deploy-live.sh --dry-run --offline`, plus a `CC_DEPLOY_SCAN=…` prefix at :708).
  - The string at :734 is `git -C $DEPLOY_REPO config --unset core.bare && bash $DEPLOY_REPO/scripts/deploy-live.sh --auto`, which is a real `--auto` run. `$DEPLOY_REPO` is expanded at filing time.
- **Guards:** it refuses an empty command, a slash command, or one containing a placeholder (:418-430). It needs a typed `yes` or `CC_DO_ASSUME_YES=1`; with stdin not a terminal it exits 3 (:435-453).
- **Mode:** foreground, with stdin from `/dev/null`.
- **Exit status:**
  - Non-zero prints FAILED, returns 1 and leaves the row open (:455-457).
  - Zero runs `cc-backlog done` (:459).

### 6. `bin/cc-premise:1392` — `subprocess.run(["/bin/sh", "-c", cmd], capture_output=True, …, timeout=FALSIFIER_TIMEOUT_S, cwd=REPO or None)` (a generic dispatcher)
- **How the command is resolved:**
  - `cmd` is the item's stored `falsifier` (:1387).
  - `deploy-live.sh` writes `"$HOME/.claude/scripts/deploy-live.sh" --falsify-host '<suite>'…` (:960-961).
  - `$HOME` is left unexpanded on purpose and expands in `/bin/sh` when the probe runs.
  - It is stored on HOST CUT rows (:1044-1047) and HOST RED rows (:1259-1262, through `fals_host_set` at :975-982).
- **Arguments:** `--falsify-host <suite>…`. That branch returns before any fetch, merge or write (:337-409).
- **Mode:** foreground child with output captured. The timeout defaults to 20 s (:241). The kill switch is `CC_PREMISE_FALSIFIER` (:246).
- **Exit status:**
  - 0 gives the verdict `"falsified"` (:1402-1411), which is in `BLOCKING` (:236).
  - rc 2, 124, 126 or 127 gives `"clear"` meaning the question could not be asked (:1444-1452, set at :266).
  - Any other non-zero gives `"clear"` meaning not refuted (:1453-1460).
  - An exception or timeout returns `None` (:1397-1399).
- **Caveat:** the enclosing function header was not in the lines I read. It is named `run_falsifier` only by the reference at :1464. Its callers (the `cc-backlog` claim, `cc-dispatch`, per the docstring at :9-11) were not verified.

## (a) Total

**6 distinct execution sites in scope**, as a lower bound: sites 1–4 name the path directly, and sites 5 and 6 are generic dispatchers handed a string at runtime.

## (b) Near-misses rejected

| path:line | reason |
|---|---|
| `scripts/deploy-live.sh:28` | a comment |
| `scripts/deploy-live.sh:419` | `sed -n … "$0"` prints the help text; it reads itself and does not run itself |
| `scripts/deploy-live.sh:708, 728, 731, 734, 743, 746` | `run=` advisory strings stored in a work item (their only executor is site 5) |
| `scripts/deploy-live.sh:803` | a `next:` line in a page file, shown to a human |
| `scripts/deploy-live.sh:960` | `printf` builds a stored falsifier string (its executor is site 6) |
| `scripts/deploy-live.sh:2376` | an `asay` advisory message shown to a human |
| `hooks/operator-readout.sh:536-537` | text of a rendered operator-board row |
| `hooks/operator-readout.sh:887` | the `dact=" → bash scripts/deploy-live.sh"` header string |
| `hooks/operator-readout.sh:871` | a comment |
| `bin/cc-do:187, 197` | display `cmd` fields; execution reads the path field, never `cmd` |
| `bin/cc-do:29, 162-183` | comments |
| `scripts/deploy-now.sh:87` | a stderr banner |
| `scripts/deploy-now.sh:69-71` | a comment |
| `hooks/validate-bash.sh:1380-1382` | a comment about `deploy-live.sh`'s own `merge` spelling |
| `launchd/com.claude.deploy-live.plist:38` | a real execution site, but outside the three scoped trees |

## (c) Self re-exec and the scheduled entry point

- **`deploy-live.sh` never re-execs itself.**
  - Across all 2730 lines, the only use of `$0` is the help `sed` at :419.
  - The comment at :2580 records that re-exec after the fast-forward was "Deliberately NOT done".
  - The processes it does start are other programs: the off-box pull (:2071), parity-assert (:1483), migrations (:1755, :1758), bats (:1100), `cc-kitty-reload` (:1938, :1942), `install.sh` (:2665) and `cc-backlog` (:812, :1044, :1259).
- **The one confirmed unattended/scheduled entry point is outside the scoped trees.** `launchd/com.claude.deploy-live.plist:38` runs `D="$HOME/.claude/scripts/deploy-live.sh"; [ -x "$D" ] || D="…/scripts/deploy-live.sh"; exec "$D" --auto` every 600 s (:41-42) and at load (:44-45).
  - It calls `deploy-live.sh` directly, not through `deploy-now.sh`, which matches `deploy-now.sh:69-71`.
  - One unverified possibility sits in scope: if an automated caller runs `cc-premise` falsifiers, site 6 would be an unattended in-scope path. It would only reach the read-only `--falsify-host` branch.

## Stale citations found in this snapshot

- `deploy-live.sh:14` cites `hooks/validate-bash.sh:1352` as the arm that denies an ungated advance. Line 1352 is actually `_ffg_resolve`'s check for runtime expansions (:1349-1352).
- `deploy-live.sh:2567-2568` says `host_checks()` is defined "at 151, called at 391". It is defined at :1050 and called at :2723.
- `deploy-live.sh:1679` says `checkout-not-a-worktree` is at ":540". It is at :658-661.
- `plist:16` cites `operator-readout.sh:238-246` for the fallback. The fallback is at :517-518.
- `cc-do:152` cites `operator-readout.sh §152-258`. The deploy leg is at :503-548.
