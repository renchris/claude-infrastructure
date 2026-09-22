<!-- arm A = claude-sonnet-5 @max · brief T5-deploy-live-exec · raw worker output, verbatim -->

## Execution sites for `scripts/deploy-live.sh` in hooks/, scripts/, bin/

Five distinct sites actually run the script as a process. (A sixth candidate mechanism — `bin/cc-do`'s generic step-runner — turned out to contain two separate sites, listed as #3 and #4.)

### 1. `scripts/deploy-now.sh:89` — `exec "$DEPLOY_LIVE" "$@"`
- **Resolution**: `DEPLOY_LIVE` set at `scripts/deploy-now.sh:56` — `DEPLOY_LIVE="${CC_DEPLOY_LIVE-$REPO/scripts/deploy-live.sh}"` (note `-` not `:-`, deliberately, per the comment at :54-55, so a caller-set empty string is honored). `REPO` set at `scripts/deploy-now.sh:53` — `REPO="${CC_DEPLOY_REPO:-$HOME/Development/claude-infrastructure}"`. Guarded at `:72` (`if [ ! -x "$DEPLOY_LIVE" ]`) with no fallback — the file's header states at `:33` "THERE IS NO RAW-FF FALLBACK, deliberately."
- **Args**: `"$@"` — every flag deploy-now.sh itself received, passed straight through (comment `:6`).
- **Mode**: `exec` — replaces deploy-now.sh's own process image (not a fork, not a substitution, not detached); `:89` is the file's last line.
- **Exit status**: since `exec` never returns on success, deploy-live.sh's exit code *becomes* deploy-now.sh's exit code; nothing downstream inspects it.
- Corroboration this is the *sole* unattended-caller-free entrypoint for humans: `scripts/deploy-now.sh:69-71` states in-file "this file has NO unattended caller — launchd/com.claude.deploy-live.plist execs scripts/deploy-live.sh --auto directly."

### 2. `hooks/operator-readout.sh:534` — dry-run probe
```
dout="$(DEPLOY_REPO="$SHARED" bash "$dscript" --dry-run --offline 2>&1)"; drc=$?
```
- **Resolution**: `dscript` at `:517` (`dscript="$DEPLOY_SCRIPT"`) ← `DEPLOY_SCRIPT` at `:314` (`DEPLOY_SCRIPT="${CC_DEPLOY_SCRIPT:-$HOME/.claude/scripts/deploy-live.sh}"`); fallback at `:518` (`[ -e "$dscript" ] || dscript="$SHARED/scripts/deploy-live.sh"`) ← `SHARED` at `:297` (`SHARED="${CC_SHARED_CHECKOUT:-$HOME/Development/claude-infrastructure}"`). Gated on `behind -gt 0` at `:532`.
- **Args**: `--dry-run --offline`; env `DEPLOY_REPO="$SHARED"`.
- **Mode**: inside a command substitution `$( … )`, stderr merged (`2>&1`), synchronous/foreground.
- **Exit status**: `drc=$?`; branch at `:535` — 0 ⇒ append a `▶` row naming `dscript` to `steps_file` (`:536-537`); nonzero ⇒ tail of `dout` becomes `dwhy` and a `⊘ HELD` row is appended instead (`:539-544`). This call only decides what gets **rendered**; it never converges anything itself.

### 3. `bin/cc-do:184` — dry-run probe (inside `collect()`)
```
dout="$(DEPLOY_REPO="$SHARED" bash "$dscript" --dry-run --offline 2>&1)"; drc=$?
```
- **Resolution**: `dscript` at `:165` ← `DEPLOY_SCRIPT` at `:89` (`DEPLOY_SCRIPT="${CC_DEPLOY_SCRIPT:-$HOME/.claude/scripts/deploy-live.sh}"`); fallback at `:166` ← `SHARED` at `:88` (`SHARED="${CC_SHARED_CHECKOUT:-$HOME/Development/claude-infrastructure}"`). Gated on `behind -gt 0` at `:167`.
- **Args**: `--dry-run --offline`; env `DEPLOY_REPO="$SHARED"`.
- **Mode**: command substitution, `2>&1` merged, foreground.
- **Exit status**: `drc=$?`; branch at `:185` — 0 ⇒ `emit deploy '▶' … "$dscript"` (`:186-187`), which writes a row into `$STEPS` with `mark='▶'` and `path="$dscript"`, making it eligible for real execution (site 4); nonzero ⇒ `emit deploy '⊘' …` (`:196-198`), and `:191-192`'s own comment confirms "`run_steps` never executes it."

### 4. `bin/cc-do:359` — the real run, via a generic dispatcher
```
run_one() { …
358:  if [ "${2#CONFIRM=1 }" != "$2" ]; then CONFIRM=1 bash "$1" </dev/null; rc=$?
359:  else bash "$1" </dev/null; rc=$?; fi
```
This is exactly the "generic dispatcher … handed the path at runtime" the brief describes. `run_steps()` (`:383-393`) reads every `$STEPS` row and, for each with `mark = '▶'` (`:386`), calls `run_one "$path" "$cmd" "$cls" "$name"` (`:389`). For the deploy row, `$path` is the *same* `"$dscript"` written by site 3's `emit … "$dscript"` (`:186-187`) — never re-derived. `run_steps` itself fires from `:525` (`[ "$MODE" = run ] || [ "${CC_DO_ASSUME_YES:-0}" = 1 ]` — i.e. `cc-do --run`) or `:548` (after an interactive `[Y/n]` confirm at `:543`).
- **Resolution**: as traced through sites 3→2's shared chain (`:186-187` ← `:165-166` ← `:89`/`:88`), arriving as `run_one`'s positional `$1`.
- **Args**: **none** — `bash "$1" </dev/null` carries no flags at all (not even `--auto`); the display string `$cmd` ("bash $(tildify "$dscript")", built at `:186-187`) is print-only at `:388` and is never `eval`'d — `:148-149`'s comment states this is deliberate. The `CONFIRM=1` branch at `:358` is never taken for this target since the deploy row's `cmd` never begins with `CONFIRM=1 `.
- **Mode**: plain foreground `bash "$1"`, stdin from `/dev/null`; not a substitution, not backgrounded.
- **Exit status**: `rc=$?` (`:359`). Because `$3` (class) `= deploy`, a nonzero `rc` is deliberately swallowed at `:369-373` (printed as `SKIPPED`, returns 0) so a deploy refusal never halts the rest of the batch — unlike other classes, which propagate failure and stop (`:374-376`).

### 5. `scripts/ship-land.sh:1739` (one statement, `:1736-1741`) — detached converge kick
```python
1736:      python3 -c 'import os,subprocess,sys
1737: env = dict(os.environ, CC_DEPLOY_MAX_LAG_COMMITS="0")
1738: with open(sys.argv[3], "a") as log:
1739:     subprocess.Popen(["bash", sys.argv[1]], cwd=sys.argv[2], env=env,
1740:                      stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT,
1741:                      start_new_session=True)' "$dl_script" "$dl_repo" "$dl_log" 2>/dev/null || true
```
- **Resolution**: `dl_script` at `:1730` (`dl_script="$dl_repo/scripts/deploy-live.sh"`) ← `dl_repo` at `:1729` (`dl_repo="${DEPLOY_REPO:-$HOME/Development/claude-infrastructure}"`). Guarded by `:1731` (`[[ -f "$dl_script" ]]`), an ancestry check at `:1732-1733` (`dl_cherry="$(git -C "$dl_repo" cherry origin/"$TRUNK" HEAD …)" && [[ -z "$dl_cherry" ]]`), and the kill switch at `:1727` (`[[ "${SHIP_LAND_CONVERGE:-on}" != "off" ]]`).
- **Args**: none on argv (`["bash", sys.argv[1]]`); env = `os.environ` plus `CC_DEPLOY_MAX_LAG_COMMITS="0"` (the "degraded tier," per `:1723-1725`); `cwd=dl_repo`.
- **Mode**: **detached** — `start_new_session=True`, stdin `DEVNULL`, stdout/stderr to a log file (`dl_log`, resolved `:1734` as `"${POSTLAND_DIR:-$HOME/.claude/autonomy/postland}/converge-edge.log"`); the `Popen` is never waited on.
- **Exit status**: never read by ship-land.sh — `:1716-1718`'s comment says this is deliberate ("a land that has already content-verified must never be turned red by what happens after it"). The trailing `2>/dev/null || true` on `:1741` only suppresses a failure of `python3` itself, not of the spawned deploy-live.sh.

---

## (a) Total distinct execution sites in scope: **5**
`scripts/deploy-now.sh:89` · `hooks/operator-readout.sh:534` · `bin/cc-do:184` · `bin/cc-do:359` · `scripts/ship-land.sh:1739` (statement `1736-1741`).

## (b) Near-misses rejected

**Comment mentions** (the large majority of the ~300 raw hits; each line read directly, `#`- or `"""`-prefixed prose that names no executable syntax): `hooks/config-mirror-assert.sh:36`; `hooks/activation-watch.sh:466-467`; `hooks/validate-bash.sh:1274,1380,1402`; `scripts/postland-verify.sh` (all ~11 hits, e.g. `:1571,1599,1806,2110`); `scripts/deploy-live.sh`'s own header/body comments (`:2,13,28,37,161,183,185,498,564,1093,1256,1286,1318,1333,1398,1402,1418,1451,1810,1813,2583` — self-reference, see (c)); `scripts/wrap-ledger.sh` (~25 hits, e.g. `:77,95,135,1454-1455,1722,1744`); `scripts/deploy-parity-assert.sh` (~35 hits, e.g. `:33,212,1389-1391` — the last explicitly states this script *refuses* to call deploy-live.sh, to avoid recursion); `scripts/ship-land.sh` comment lines (`:999,1002,1068-1069,1719,2631,3711,4016`); `scripts/nightly-regression.sh:81,467,647,688,808`; `scripts/offbox-admission-lint.sh:21,146`; `scripts/deploy-migrations.sh:15,56,205`; `scripts/browse-mirror-sync.sh:103`; `scripts/kitty-setup.sh:57,232`; `scripts/test-walltime-lint.sh:153`; `scripts/test-afunix-path-lint.sh:22`; `scripts/new-worktree.sh:9,11`; `scripts/test-hermeticity-lint.sh:428-486` (a *lint* auditing ship-land.sh's own spawn from the outside — read in full, it executes nothing itself); `scripts/offbox-green-pull.sh:11-24`; `scripts/growth-coverage-lint.sh:57`; `scripts/lib/cc-common.sh:87`; `scripts/bats-assert-liveness.py:200`; `bin/cc-owner:8-9`; `bin/cc-kitty-reload:32,55,74`; `bin/cc-blockers` prose lines (`:57,182,197,224,227,265,515,551,563,574,581-584,612,669,688,720,651`); `bin/cc-premise:1528,2544`; `bin/cc-memory-rotate:75`; `bin/cc-backlog:355,1705,1796,1919,3659,3716,4166,4250`; `bin/cc-venue:187`; `bin/cc-fleet:296-297`; `bin/cc-reaper:910`; `bin/cc-cannot:187-188`; `bin/cc-dispatch:1189`.

**Human-facing / hook "reason" / rendered-board / stored-advisory text** (real syntax, but the output is text a person or a work item reads, never a subprocess call):
- `hooks/activation-watch.sh:471,492` — building `out=` operator-board text (`▶ bash …`), never invoked.
- `hooks/session-continue.sh:1191` — inside `reason="🚀 SHIP FLOOR … bash \$(…)/scripts/deploy-live.sh …"`, fed to `jq -nc --arg r "$reason" '{decision:"block",reason:$r}'` at `:1197` — a hook "reason" blob.
- `hooks/operator-readout.sh:536,543,871,887` — `printf`s that render the operator board's `▶`/`⊘`/`🚀` rows from the *result* of site 2; text only.
- `hooks/validate-bash.sh:1425,1432` — `deny "…"` messages suggesting the command to a blocked human.
- `hooks/completion-assert.sh:782,784` — `facts=` advisory strings for a completion ledger.
- `hooks/lib/why-tier.sh:249` — inside a `cat <<'WHY' … WHY` help-text heredoc.
- `scripts/deploy-now.sh:73-76,87` — abort/banner messages printed around the real site (`:89`), never execution themselves.
- `scripts/wrap-ledger.sh:2403` — `printf 'bash scripts/deploy-live.sh — %s…'` renders a ledger row.
- `scripts/kitty-title-band-deploy.sh:193` — `die "… run scripts/deploy-live.sh first"`.
- `scripts/handoff-fire.sh:9153,12619` — `echo`/`rcy_tok_why=` advisory strings to stderr.
- `scripts/deploy-link-parity.sh:509` — `fix "bash …/deploy-live.sh …"`; confirmed by reading `fix()`'s own definition at `:159` — `fix() { FIXES="${FIXES} ▶ $1"$'\n'; }` — it only appends to a report string, never executes.
- `scripts/deploy-parity-assert.sh:1459,1504,1081,1382` — advisory `printf`s pointing a human at the command.
- `scripts/limit-recover/lr-handoff.sh:802,829` — `echo "lr-handoff: converge, then re-run: bash …" >&2`.
- `bin/cc-blockers:642` — a `printf` building a JSON blocker record whose `"recover_cmd"` field is an advisory string, never executed.
- `bin/cc-do:89,163,166,169,175` — `DEPLOY_SCRIPT=`/fallback/comment lines that *feed* site 3/4 but are not themselves invocation lines.
- `scripts/deploy-live.sh:698-824` (`refusal_escalate()`) — the `run=` case-statement (e.g. `:708,728,731,734,743,746`) builds an advisory string used only at `:803` (`printf 'next: %s\n' "$run"`, into a `.page` file) and `:811-813` (filed as `cc-backlog … --run "$run"`, a work-item's stored field) — never `eval`'d or otherwise executed. This is also the "`deploy-live.sh` referring to itself" case — see (c).

**Grep/lint pattern, ratchet-table entry, or test-fixture literal**:
- `scripts/permission-gate-lint.sh:169` — `scripts/deploy-live.sh 8`, a ratchet-table row (context `:112-118` shows this file tracking a per-file allowed-count that moved `10→9→8`).
- `scripts/permission-gate-lint.sh:563,589` — `mk unbounded scripts/deploy-live.sh '…'` / `mk declared scripts/deploy-live.sh '…'`, calls into this file's own embedded self-test harness (`mk`/`green`/`red`/`expect`, confirmed by the surrounding test-case functions at `:720-722,745-747,770,782`) that manufacture *synthetic fixture files* named `scripts/deploy-live.sh` to test the lint tool — never the real script.
- `bin/cc-eligible:169` — `("deploy-live", r"\bdeploy-live\b")`, one row of a `(label, regex)` classification table for backlog-item text, confirmed by reading the surrounding list (`:155-179`).
- `scripts/backlog-consolidation/group.py:143-148` — a classification regex containing `deploy-live` as one alternative.

**A bare path assignment that is never invoked**: none found in scope — every path variable traced (`DEPLOY_SCRIPT`, `dscript`, `DEPLOY_LIVE`, `dl_script`) resolves into one of the five sites above; I found no orphaned assignment.

**`deploy-live.sh` referring to itself, never re-executing**: `scripts/deploy-live.sh:708,728,731,734,743,746` (the `run=` self-reference strings inside `refusal_escalate()`, filed to a page/backlog record, per above) — see (c) for the direct answer.

## (c)
- **Does `scripts/deploy-live.sh` ever re-exec itself?** **No.** Every self-reference found (`scripts/deploy-live.sh:708-746`) builds an advisory string that is only `printf`'d to a `.page` file (`:803`) or stored as a backlog row's `--run` field (`:811-813`) — text for a human or for `cc-do` to run later, never `eval`'d, never re-invoked in-process. No `exec "$0"`, no `bash "$0"`, no self-`Popen` exists anywhere in the file.
- **Where does the only unattended/scheduled entry point live?** **Outside the three scoped trees.** It is `launchd/com.claude.deploy-live.plist` (a top-level `launchd/` directory, not `hooks/`, `scripts/`, or `bin/`). Its `ProgramArguments` is a self-contained `/bin/bash -c` one-liner that resolves and execs the target *without going through any of the five in-scope sites*: `export PATH=…; D="$HOME/.claude/scripts/deploy-live.sh"; [ -x "$D" ] || D="$HOME/Development/claude-infrastructure/scripts/deploy-live.sh"; exec "$D" --auto` (plist lines 34-39), on `StartInterval 600` with `RunAtLoad true` (plist lines 41-45). This is independently corroborated from inside scope by `scripts/deploy-now.sh:69-70` ("this file has NO unattended caller — launchd/com.claude.deploy-live.plist execs scripts/deploy-live.sh --auto directly") and by the plist's own top comment (lines 3-9, 15-22). None of the five in-scope sites is itself timer/schedule-driven: site 1 is human-invoked, sites 2-3 fire reactively (a Stop-hook render / an explicit `cc-do` call), site 4 fires on explicit confirm or `--run`, and site 5 fires once per successful land (event-driven, not interval-driven).
