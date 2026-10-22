# Repo census: which of OUR `#!` scripts still run by path, and how often (2026-10-22)

Axis: repo-census (static), weighted by frequency. Checkout read: `~/Development/claude-infrastructure`
on `main`, clean, HEAD `c9ce6fbac` (`git status --short` => empty, `git log --oneline -1`).
Everything here is read-only. The only file written is this one. Labels: **MEASURED** means I ran
the command and it printed the number. **ESTIMATED** means I derived the number and the method is
named. **INFERRED** means I reasoned it from code and did not run it.

## Answer

1. **The hook commands themselves no longer trigger the leak.** All 104 hook commands in
   `~/.claude/settings.json` start with `/bin/bash`, `/usr/bin/env bash` or `/usr/bin/env python3`, or
   are the inline commands `true`/`date`. Same in `.claude-next`, `-secondary`, `-tertiary` and
   `-quaternary` (0 bare commands in each). The status line is `/bin/bash ~/.claude/statusline.sh`.
   MEASURED with a python/json walk of each settings.json. The doc's "24 still bare" line
   (`panic-…-shebang-leak.md:315`) is out of date.
2. **On the per-tool-call hook path, I found no nested by-path `#!` exec two levels down** for
   PreToolUse Bash (10 hooks), PreToolUse `*`, PostToolUse `[]`/Bash, PostToolBatch or the status
   line. This agrees with the doc's xtrace census (`:258-260`). The remaining hook-path triggers sit
   on **Stop, SessionStart and SessionEnd**. Each is about 1-3 execs per event: `cc-decide` through
   `wrap-ledger.sh`, `cc-research`, `cc-await-ping`, which then loops `cc-kqwait`, and the 10
   session-start-dispatch children. See the table.
3. **The steady load of OUR scripts is not on the hook path.** It is in loops and tools:
   `cc-await-ping` → `cc-kqwait` (≈43k/day), the QoS shim `cc-qos-exec`, which models call by name
   as `agent-browser`, `shellcheck` and similar (≈11k/day), `claude-accounts` from two launchd jobs
   (≈5k/day), the land-gate pipeline in worktrees (≈40k/day), and **our test suites' `#!` stubs plus
   Homebrew bats-core internals (≈170k/day while suites run)**.
4. **Calibration (MEASURED, read-only, from the root census another agent started):** a 40.5-minute
   sample has 23,793 `#!` execs from real workload, which is **9.8/s, about 0.85M/day**. That matches
   the post-0070 leak of 9-12 elements/s. claude-infrastructure owns about **40%** of them: main
   checkout 14%, worktree copies 5%, our bats stubs and bats-core 20%. **About 49% is another
   project's test suite** (agent-context-sync pytest stubs, rehearsals, its shasum), which a
   rewrite of this repo cannot touch.
5. **Is a mechanical rewrite to `bash <path>` safe?** Only in one form: prefix the callee's
   **own shebang, verbatim**. That gives the exact argv the kernel builds today, so `$0`,
   `BASH_SOURCE`, `__file__`, `ps`/`pgrep -f`, `$!`, exec and exit codes stay the same (MEASURED: a
   launchd `#!` exec shows as `/bin/bash /Users/…/compressor-sentinel.sh` in `ps`). A blanket
   `/bin/bash` is NOT safe: it downgrades 182 `env bash` scripts to bash 3.2. A rewrite to
   `bash NAME` is NOT safe either, because bash looks in the cwd first. And 164 of the 265
   variable call sites take a `${CC_X_BIN:-…}` test seam, so they need a runner that reads the
   shebang, not a hard-coded prefix.

## 1. The universe (MEASURED)

| Measure | Value | Command |
|---|---|---|
| `#!` files under hooks/ bin/ scripts/ (recursive, symlinks excluded) | 705, of which 615 are executable | `os.walk` + first 2 bytes + `os.access(X_OK)` |
| Shebangs of the 615 | 311 `#!/bin/bash`, 182 `#!/usr/bin/env bash`, 116 `#!/usr/bin/env python3`, 4 `#!/usr/bin/python3`, 2 `#!/bin/sh`; **none carry flags** | same walk, first line |
| Executable files with no shebang | 0 | same |
| `~/.claude/bin` names that resolve into the checkout | 156. Nine are **aliases of a `#!` shim**: `agent-browser convert ffmpeg ffprobe magick pytest shellcheck tesseract` → `bin/cc-qos-exec`, and `bats` → `bin/cc-bats` | `readlink` loop over `~/.claude/bin` |
| `~/.claude/bin` is the first PATH entry | yes | `echo $PATH` |
| Untracked hook files live in `~/.claude/hooks` (not in the repo) | `web-entrypoint-ladder.sh`, `net-context-stamp.sh`. Both call only Mach-O tools (jq, sed, route, arp, networksetup) | `ls -la`, `grep` |
| Shared git hooks, run by git on every commit/push in every worktree | `.git/hooks/{pre-commit,commit-msg,pre-merge-commit,pre-push}`, all `#!/usr/bin/env bash` | `head -1` |

The doc's "~570" (`:26`) counted top-level files. The recursive count, which includes `hooks/lib`,
`scripts/lib` and the subdirs, is 615.

## 2. Event rates used for weighting (MEASURED, 24 h ending 2026-10-22 ~05:00Z)

| Event | Per day | Source |
|---|---|---|
| Tool calls, all | 36,277 (Bash 30,708; Read 1,615; Edit 1,266; Write 683; WebSearch 455; Agent 124) | transcripts in 5 config dirs, `"type":"tool_use"` with timestamp in window (736 files) |
| of which in subagents | 21,921 | same, path contains `/subagents` |
| UserPromptSubmit | 1,136 | `hook-timing.jsonl`, 7 hooks × 1,136 rows |
| Stop (≈ main end_turn) | 1,886 | transcripts, `"stop_reason":"end_turn"`, main only |
| SessionStart | 138 (261 startup / 59 resume / 1 fork over the file tail) | `session-start-dispatch.jsonl` |
| SessionEnd | ~194 | `sessions.log` "Session ended" since 10-21 00:00 local |
| CwdChanged / InstructionsLoaded / ConfigChange / FileChanged | 1,028 / 598 / 137 / 117 | their own logs, `awk '$1>=cut'` |
| Bash commands typed by sessions | 22,775 logged since 2026-10-21T05:15Z | `bash-commands.log` lines with the `[ts] [sid]` prefix |
| Commits across all refs | 492 (70 on origin/main) | `git rev-list --all --since='24 hours ago' --count` |
| Live `cc-await-ping` loops right now | 43 | `ps -axo … \| grep -c '[c]c-await-ping'` |

## 3. Static call graph (MEASURED counts, heuristic precision)

Method: a python lexer over 842 shell and python files in hooks/ bin/ scripts/ (tests/ and
fixtures/ excluded). It drops comments, heredoc bodies and quoted prose, splits on
`| || && ; then do else &`, extracts `$( )` and backticks, strips the prefixes
`exec/timeout N/nice/taskpolicy/env VAR=/VAR=`, and resolves the command word three ways: a
path ending in a repo `#!` basename, a bare name on `~/.claude/bin`, or a `"$VAR"` whose assignment
(including `${CC_X:-default}` and `command -v NAME`) resolves into the repo. Python:
`[exe, …]` lists near `subprocess`/`_run`.

| Result | Value |
|---|---|
| By-path (bare) `#!` call sites | **402** in 142 caller files, reaching 116 distinct callees |
| by form | 265 `"$VAR"`, 57 literal path, 55 bare name via PATH, 25 python list |
| path form | 258 variable/other, 55 bare NAME, 50 checkout-relative (`$(dirname "$0")`, `$HERE`, `$REPO`), 25 python, 14 literal `~/.claude/...` |
| VAR sites by assignment | 164 env seam `${CC_X_BIN:-default}`, 51 other, 37 checkout-relative, 8 `~/.claude` path, 3 `command -v` |
| callee shebang per site | 219 `/bin/bash`, 122 `/usr/bin/env bash`, 48 `/usr/bin/env python3`, 9 `/bin/sh`, 4 `/usr/bin/python3` |
| sites already explicit (`bash X`, `python3 X`) | 156 (INTERP edges), plus 282 `source`/`.` edges |

Precision (ESTIMATED by hand-reading a random 30-45-site sample at each iteration): about 75-85%
true by-path execs in the final version. The rest are mostly strings that look like commands
(`printf`, `deny "…"`, regex literals), already filtered where the line matched those words.
**Recall gaps found by hand (INFERRED, so the static numbers are a floor):**
- Timeout wrappers through a variable or function: `_bounded 5 "$bin"` (`scripts/wrap-ledger.sh:1497`),
  `"$_OR_RP_TO" -k 1 "$_OR_RP_S" "$_OR_RP_BIN"` (`hooks/operator-readout.sh:775`) and
  `sup_bounded … "$NOTIFY_BIN"` (`scripts/lead-supervisor.sh:434`). A grep for that shape found ≥ 29
  more sites (`grep -rnE '(_bounded|timeout…)\s+…"\$…BIN'` => 29).
- Two-variable paths: `( "$DIR/$c" < … ) &` (`hooks/session-start-dispatch.sh:183`, 10 children).
- Candidate loops that pick a binary and run it later: `for _c in … cc-await-ping; do … _ping="$_c"`
  (`hooks/mailbox-wake-arm.sh:210-214`, run at `:234`).
The eslogger cross-check in §4 is what ranks the rows, not this graph.

### Hook entries, two levels down (static, plus the hand-found gaps)

| Event (per day) | Nested by-path `#!` (caller:line → callee) | Condition |
|---|---|---|
| PreToolUse Bash ×10, PreToolUse `*`, PostToolUse `[]`, PostToolBatch, statusLine | none found | n/a |
| PostToolUse Bash (30,708) | `waiting-recycle.sh:686` → `hooks/push-critical.sh`; `:1528` → `scripts/handoff-fire.sh` (which nests `cc-notify`, `cc-in-kitty`, `claude-accounts`, `desk-land.sh`…); `:1348` → `dod-persist.sh` | only on the recycle path (INFERRED from code) |
| Stop (1,886) | `completion-assert.sh:646` and `boundary-handoff.sh:540` run `bash "$WRAP"` (safe), and **`wrap-ledger.sh:1497` then runs `_bounded 5 "$bin"` → `bin/cc-decide`** | every Stop that reaches the ledger: ≈2 per Stop |
| Stop | `operator-readout.sh:775-776` → `bin/cc-research pending --json` (python) | every Stop where the resolver succeeds |
| Stop | `handoff-claim-assert.sh:96` → `bin/cc-cannot` → `bin/cc-owner` (`cc-cannot:195`) | only when a claim is present |
| Stop + SessionStart | `mailbox-wake-arm.sh:234` `"$_ping" …` → `bin/cc-await-ping`, which **loops `"$KQ_BIN"` → `bin/cc-kqwait`** (`cc-await-ping:913`, timeout capped at INTERVAL=15 s when a file has no baseline, `:909`) | each arm, then a re-exec every ≤15 s for up to 3h59m |
| SessionStart (138) | `session-start-dispatch.sh:183` `"$DIR/$c"` × 10 children (all bash shebangs) | every start: ≈1.4k/day ESTIMATED (138 × 10) |
| SessionStart | `lead-crash-watchdog.sh:2053` → `cc-pane-close` → `kitty-fullscreen-guard`, `cc-kitty-socket` | rare branch |
| SessionEnd (~194) | `session-end.sh:104` → `bin/cc-in-kitty` (`/bin/sh`) | every end |

### launchd agents (MEASURED plists via `plutil -convert json -o -`, 37 com.claude loaded)

The top-level exec of most agents is itself a `#!` exec: `bash -c 'exec "$HOME/.claude/scripts/x.sh"'`,
`zsh -lc '~/.claude/scripts/x.sh'`, or `perl -e '…exec @ARGV' N "$HOME/.claude/bin/claude-accounts"`.
`zsh -l` also runs `~/.zprofile:1` `eval "$(/opt/homebrew/bin/brew shellenv)"`, and `brew` is
`#!/bin/bash -pu`, so each `zsh -lc` job is 2 `#!` execs. Already explicit: boot-resume,
lead-supervisor, research-*, lr-recon-watchdog, lr-reset-poller, watch-pandacss.

| Agent | Trigger | Top-level `#!` per run | Nested by-path (static) |
|---|---|---|---|
| accounts-local | StartInterval 20 + WatchPaths | 1 (claude-accounts, python) | `claude-accounts:11384` → `cc-startup-health` (subprocess list) |
| accounts-keepwarm | 180 | 1 | same |
| capacity-alarm | 60 | 1 | none found |
| session-search-sweep | 60 | 1 (`~/.claude/hooks/session-index-sweep.sh`) | `:315` → `cc-history-union`, `:363` → `cc-memory-read-ledger` |
| dispatcher (cc-dispatch) | 300 | 1 | 11 L1 sites (`cc-custody`, `cc-cloud`, `cc-venue`, `cc-offload`, `handoff-fire.sh`, `cc-premise`) + 24 L2 |
| autonomy-sweep, cc-reaper | 300, zsh -l | 2 each | cc-reaper: `cc-teardown`, `cc-kitty-socket`, `teammate-checkpoint.sh`; sweep L2: `cc-cloud`, `cc-notify`, `cc-backlog`, `cc-pane`, `cc-custody` |
| postland-verify, desk-invariant, fseventsd, coreaudiod, browser-spin-guard, auth-timeseries | 300 | 1 | postland: `cc-notify`, `cc-backlog`, lints; desk: `push-critical.sh`, `handoff-fire.sh`, `desk-recycle-invariant.sh` |
| teammate-reap-alarm | 600 | 2 (two scripts by path in the `-c` string) | `pane-close-retry.sh`, `cc-kitty-bin`, `cc-kitty-socket` |
| deploy-live, qos-census, worktree-gc-infra, browse-mirror | 600 | 1 | deploy-live: `cc-backlog`, `deploy-migrations.sh`, `cc-kitty-reload` |
| compressor-sentinel (KeepAlive, 10 s tick) | 8,640 ticks | 0 (started once) | **`/usr/bin/shasum -a 256` at `compressor-sentinel.sh:1888`**, a perl `#!` |
| lead-supervisor (KeepAlive, 30 s sweep) | 2,880 sweeps | 0 | `shasum` via `command -v` (`:121-129`); `cc-notify` only when paging |

ESTIMATED top-level total: about **11.9k/day upper bound**. That is the sum of 86400/StartInterval ×
`#!` per run over the loaded agents. Real numbers are lower because a still-running job skips
its interval: capacity-alarm measured 17 runs in 34 min, about 720/day, against 1,440.

## 4. Cross-check against the root exec census (MEASURED, read-only)

File: `~/.cache/kalloc-exec-census/20261021T235112/exec.jsonl`, eslogger exec. It was **still being
written at 05:31Z, 40 min into a planned 10-minute run** (8.7 GB at 00:14 CDT). Only events with
`event.exec.script != null` are counted (`grep -F '"script":{'` then a json parse).
**Contamination:** from about 05:15Z, 20,934 script execs (46.8% of the window) came from
`~/.cache/kalloc-longterm-ab/`, the sibling measurement agent's A/B harness. They are excluded below.

Window 04:51:16Z→05:31:46Z (2,430 s), real workload = 44,727 − 20,934 = **23,793 `#!` execs = 9.8/s
≈ 846k/day**. The earlier, uncontaminated 24.6-min slice was 17,467 = 11.85/s.

| Owner class | execs | share |
|---|---|---|
| claude-infrastructure, main checkout / `~/.claude` | 3,356 | 14.1% |
| claude-infrastructure, worktree copies (land/postland gates) | 1,181 | 5.0% |
| claude-infrastructure, bats tmp stubs (`postland-run…/stub/jq`, `readlink`, `python3`…) | 3,498 | 14.7% |
| Homebrew bats-core libexec (`bats-exec-test`, `-file`, `-suite`…), run by our `cc-bats` | 1,311 | 5.5% |
| Homebrew kitty wrapper (`/opt/homebrew/bin/kitty` = `#!/bin/bash` `exec …/kitty.app/…/kitty`) | 100 | 0.4% |
| `/usr/bin/shasum` (perl `#!`), other cwd | 588 | 2.5% |
| **agent-context-sync** pytest stubs (cwd `~/Development/agent-context-sync`) | 9,164 | 38.5% |
| agentsync rehearsals in `/private/tmp` + its shasum | 1,460 + 1,035 | 10.5% |
| other `/tmp` test probes, TrueMemory venvs, misc | ~1,700 | ~7% |

## 5. Ranked table: our scripts run by path

Est./day = census count in the 04:51:16-05:25:29Z window (2,053 s) × 42.1 (MEASURED sample,
linearly scaled; workload-dependent). For rows the census did not see, the static estimate is
named. "Safe" means the rewrite with the callee's verbatim shebang prefix.

| # | Script (shebang) | Who runs it by path | Est./day | Mechanical rewrite safe? |
|---|---|---|---|---|
| 1 | **our bats tmp stubs** (`#!/bin/bash`/`/bin/sh` files the tests write: 1,287 + 278 + 156 + 8 py, `grep` over tests/*.bats) + **bats-core libexec** | the code under test calls `jq`, `readlink`… by name and resolves the stub; bats-core execs its own libexec by path | 124k + 47k (40.5-min window × 35.6) | **No.** The call site is production code calling a system name. Needs a test-side design: function stubs, compiled stubs, or a patched/vendored bats-core. Not a call-site rewrite |
| 2 | `bin/cc-kqwait` (`env bash`) | `bin/cc-await-ping:913` `"$KQ_BIN" … &` in its wait loop (`KQ_BIN` from `:853-854`); cc-await-ping is armed by `hooks/mailbox-wake-arm.sh:234` (Stop/SessionStart) and `mailbox-drain.sh:500`, and typed 456×/day | **43.4k** (1,032) | **Yes, one site:** `/usr/bin/env bash "$KQ_BIN"`. cc-kqwait exports `CC_KQWAIT_SELF="$0"` and `$BASH` (`:257`), and both come out identical. Better still, resolve the compiled `current-$HOSTTYPE` once per loop |
| 3 | land/postland gate scripts in worktrees: `gate-manifest.sh` 79, `unattended-path-lint.sh` 112, `land-verify.sh` 51, `ship-land.sh` 50, `land-lock.sh` 46, `settings-drift-assert.sh` 42, `ship-backup-reap.sh` 42, `stranded-sweep.sh` 40, `bats-kill-guard-lint.sh` 37, `cc-instruction-budget` 72, `hooks/accounts-board.sh` 82, `tests/fixtures/hb-kitty-ps` 210… | `scripts/ship-land.sh` and `postland-verify.sh` (e.g. `PRELINTS=(scripts/…lint.sh …)` `:600`), run from each worktree | ≈40k (1,181 wt copies in 40.5 min) | **Mostly yes.** Gate code, every site in two files. The fixture row is test-only. Watch the env seams ship-land takes for its lints |
| 4 | `bin/cc-settings-parity` (`env python3`) | `migrations/0012:206`, `0036:52` `"$parity" check`, `scripts/c10-batch.sh:137` `"$1/.claude/bin/cc-settings-parity"` (parent: Homebrew bash, i.e. a rehearsal run) | 13.1k (312), **transient** | Yes: `/usr/bin/env python3 "$parity"`. `hooks/config-mirror-assert.sh:77` already does `python3 "$par"`. `CC_SETTINGS_PARITY_BIN` seam → use a runner |
| 5 | `bin/cc-backlog` (`/bin/bash`) | ~130 static sites: `ship-land.sh` (`bl`, `:1362`, `:1403`), `deploy-live.sh:1056`, `postland-verify.sh:962`, `cc-dispatch`, `drain-chain-assert.sh:355`, `worktree-gc.sh:1008`, python `cc-venue:397,537` `_run([exe,…])`, plus 193 typed/day | 11.2k (98 main + 168 wt) | VAR sites take `CC_BACKLOG_BIN`; tests stub it → **runner, not a literal prefix**. Python: `["/bin/bash", exe, …]` |
| 6 | `bin/cc-qos-exec` (`/bin/bash`) = `agent-browser`, `shellcheck`, `pytest`, `bats`, `ffmpeg`, `magick`… | by NAME: models type `agent-browser` 1,573×/day, `shellcheck` 57, `magick` 29 (bash-commands.log); `ship-land.sh:3493` `shellcheck "${sc_todo[@]}"`; `task-quality-gate.sh:182`; `cc-bats` | 10.6k (252) | **No call-site fix exists.** Callers include models and other tools. This is exactly the compiled-launcher case: rewrite `cc-qos-exec` itself as Mach-O. It already dispatches on `${0##*/}` and walks PATH past itself (`:48-102`) |
| 7 | `bin/claude-accounts` (`env python3`) | launchd `accounts-local` (20 s) + `accounts-keepwarm` (180 s) via `perl … exec @ARGV`; `lr-reset-poller.sh:816`, `lr-fleet.sh:717`, `handoff-fire.sh:17107`, `cc-context:117` | 5.8k (137; 111 with a perl parent) | **Yes:** in both plists, `exec @ARGV` of `/usr/bin/env python3 "$HOME/.claude/bin/claude-accounts"`. That is ≈4.8k/day for two plist edits |
| 8 | `bin/cc-decide` (`/bin/bash`) | `scripts/wrap-ledger.sh:1497` `_bounded 5 "$bin" list --open --class C --json` (×2 per Stop, through completion-assert and boundary-handoff); `hooks/anti-deference-nudge.sh:96`; `lr-reset-poller.sh:1179` | 4.9k (117; 59 wt) | Yes with a runner: `CC_DECIDE_BIN` seam (`wrap-ledger.sh:1334`) |
| 9 | `bin/cc-in-kitty` (`/bin/sh`) | `~/.zshrc:706` (every interactive zsh, including each session's shell snapshot), `hooks/session-end.sh:104`, `handoff-fire.sh:2336` | 4.0k (96) | Yes: `/bin/sh "$HOME/.claude/bin/cc-in-kitty"`. `CC_IN_KITTY_BIN` seam at session-end |
| 10 | `bin/cc-kitty-bin` (`env bash`) **and the Homebrew `kitty` wrapper it returns** | `$(cc-kitty-bin)` in `boot-resume-launch.sh:139`, `pane-close-retry.sh:112`, `render-census.sh:230`, `lr-reset-poller.sh:888`…; cc-kitty-bin prints `command -v kitty` first, which is `/opt/homebrew/bin/kitty` (`#!/bin/bash`) | 2.5k + 3.6k | **Yes, and cheap:** put `/Applications/kitty.app/Contents/MacOS/kitty` (Mach-O, MEASURED with `file`) first in cc-kitty-bin's list. That removes the wrapper exec from every `"$KITTY" @ …` call |
| 11 | `bin/cc-claude-bin` (`env bash`) | python `cc-model-registered:53` `subprocess.run([resolver])`, `cc-notify:685`, `scripts/lib/cloud-create.sh:121`, `hooks/session-start.sh:276` | 2.6k (62) | Yes (python: `["/usr/bin/env","bash",resolver]`) |
| 12 | `~/.claude/bin/it2` (untracked real file, `#!/bin/bash`) and `bin/it2-kitty` (`env bash`) | **Claude Code itself** (parent `claude.exe`, 15 of 58) for agent-team panes; our scripts under gtimeout; `reso-keepalive:231` `"$KT" session send` | 2.4k + 1.4k | No call-site fix for the Claude Code half. Compiled shim at `~/.claude/bin/it2` |
| 13 | `bin/cc-custody`, `cc-resume-debt`, `cc-research` (Stop: `operator-readout.sh:775`), `cc-sessions`, `cc-bats`, `cc-await-ping`, `cc-notify`, `capacity-alarm.sh` | as in §3 | 0.7-1.7k each (17-40) | Yes with a runner. Most are VAR + seam |
| 14 | `/usr/bin/shasum` (perl `#!`, not ours, called by our code) | `compressor-sentinel.sh:1888` (10 s loop: 26 in 24.6 min ≈ 1.5k/day), `lead-supervisor.sh:121-129` (≈640/day), gate scripts | ≈2-5k of ours | Yes: `/usr/bin/perl /usr/bin/shasum …`, the pattern `hooks/lib/shasum-direct.sh` already uses |
| 15 | session-start-dispatch's 10 children (`hooks/session-start-dispatch.sh:183`) | every SessionStart | ≈1.4k (static: 138 × 10) | Yes: `CC_SSD_CHILDREN` seam → runner |
| 16 | launchd top-level `#!` (`exec "$HOME/.claude/scripts/…"`, `zsh -lc` + brew) | 30 plists, §3 | ≤11.9k (static) | **Yes:** plist ProgramArguments `[interp, script]`, as boot-resume and lead-supervisor already do. Under `zsh -l`, also `brew shellenv` |
| 17 | `.git/hooks/pre-commit`, `commit-msg` (`env bash`) | git, per commit, every worktree | ≈300 + 300 (7 + 7 in 34 min); ≤1k static (492 commits) | Not by a call-site change (git execs the hook). Low value |

For scale: rows 2, 4-12, 14-16, the main-checkout tools, are what a rewrite of this repo reaches,
**≈1.9/s, about 19% of the real stream** (main 14.1% + worktree copies 5.0%). Row 1 (tests, 20%)
needs its own design. 49% belongs to another project.

## 6. Rewrite safety rules (what makes `bash <path>` safe or not)

- **Safe form: `<callee's shebang verbatim> <same path string> args`.** For `#!/usr/bin/env bash`
  the kernel builds `["/usr/bin/env","bash",path,…]` and env then execs bash with `["bash",path,…]`.
  The explicit form produces the same argv. `env` is Mach-O, so the extra hop does not leak. That
  keeps `$0`/`BASH_SOURCE[0]` (133 bash files use `$0` to find their location, 180 use
  `BASH_SOURCE`), `sys.argv[0]`/`__file__` (73 python files), the `[[ BASH_SOURCE == $0 ]]` main
  guards (8 files), `$BASH` (cc-kqwait re-exec), `ps`/`pgrep -f` matching (MEASURED: pid 2936
  `comm=/bin/bash args=/bin/bash …/compressor-sentinel.sh`, which a launchd `#!` exec started),
  `&`/`$!`, `exec` (30 files `exec` a path), and exit codes. `set -e` (55 files) does not cross a
  process boundary either way. INFERRED from execve semantics.
- **Unsafe 1, a blanket `/bin/bash`:** 182 scripts are `#!/usr/bin/env bash`. The census shows
  both `/bin/bash` and `/opt/homebrew/Cellar/bash/5.3.15/bin/bash` as parents, so the PATH bash is
  5.3 for many callers. Forcing 3.2 changes behaviour. See rule "Deployment interpreter ≠ yours"
  (`.claude/rules/agent-operating-lessons.md:47`).
- **Unsafe 2, `bash NAME` for by-name calls** (55 static sites, ~4.1k typed/day): given a bare
  script name, bash opens the file in the **current directory first**, then searches PATH (bash
  manual, INVOCATION; not measured here). A rewrite has to resolve the path first
  (`command -v`). At the PATH layer only a launcher fixes it.
- **Unsafe 3, a literal prefix on seam-variable sites** (164 of 265 VAR sites take
  `${CC_X_BIN:-…}`): tests inject stubs of other kinds (8 python3 and 156 `/bin/sh` stub writers
  in tests/*.bats). Use one sourced runner that reads line 1 and execs the named interpreter, and
  passes Mach-O through unchanged.
- **Python sites** (25): `[exe, …]` → `[interp, exe, …]`. Check `executable=` and `shell=True` callers.
- **Lint at the land gate (INFERRED):** the static matcher reaches about 75-85% precision and
  misses wrapped calls (`_bounded`, `"$TO" -k`, `"$DIR/$c"`, candidate loops). A lint that tries to
  infer `#!`-ness at each site will be noisy and leaky. An enforceable rule has two parts. First,
  every repo-to-repo exec of a variable goes through the runner, and the lint flags a `"$*BIN"`,
  `"$*_bin"` or `"$DIR/…"` word in command position. Second, the existing `hook-shebang-lint.sh`
  is extended to plist ProgramArguments.

## 7. Where a compiled launcher helps (INFERRED from the forms above)

- A launcher placed at **`~/.claude/bin/<name>`** catches every by-name call: models' typed
  commands (~4.1k/day), Claude Code's `it2`, the 9 QoS aliases, and `command -v` resolutions. It
  catches none of the checkout-relative (50 + 37 VAR), literal-checkout (`$_ca_root/bin/cc-kqwait`,
  the top row) or worktree-copy forms. If it execs `[shebang-interp, <checkout>/bin/<name>, …]`,
  `$0` becomes the checkout path instead of the `~/.claude/bin` symlink path. Scripts that already
  resolve their symlink see no change (lesson "Symlinked $0 splits siblings", situational rules
  `:69`).
- Replacing **`bin/<name>` in the checkout** with a launcher means the real script lives at a
  different path, so `$0`, `BASH_SOURCE` and `__file__` all change. That breaks the 133 + 180 + 73
  files above unless the real scripts keep the same directory depth. Same-directory sibling lookups
  would then execute the moved real scripts by path and leak again. Not mechanical.

## 8. Concerns and deviations

- §4 and the ranking use the root census file, which another agent produced. I only read it. It
  overran its 10-minute plan (still growing at 05:31Z), and the sibling A/B harness contaminated it
  from about 05:15Z. I excluded that harness by path. The window is one 40-min workload mix, with
  one agent-context-sync pytest run dominant. The shares will move between hours.
- The static graph is a floor (§3 recall gaps). The est./day column is a sample scaled ×42 or ×36,
  not a 24 h count.
- One stray scratch file, `/tmp/null-check-not-written` (604 lines, a `find` listing), was created
  by a mistaken redirect of mine and removed with `rm -f` right away. Nothing else was written
  outside this file.

## Critique

Adversarial review, 2026-10-22 05:45-06:15Z. Read-only: I re-ran the cited commands and made four
streaming passes over `~/.cache/kalloc-exec-census/20261021T235112/exec.jsonl` (`grep -F '"script":{'`
piped to `python3 -I -c`, results kept in memory). The only file I wrote is this section. Main HEAD
is now `503da95d7`, not `c9ce6fbac`. None of the files cited below changed between the two
(`git diff --stat`). Note: eslogger escapes `/` as `\/` in its JSON, so a `grep -F '/hooks/'` on the
raw file matches nothing. Every path filter below runs after `json.loads`.

### Verdicts on the main claims

| # | Claim | Verdict | Evidence (M = measured, I = inferred) |
|---|---|---|---|
| 1 | All 104 hook commands, in all user config dirs, carry an explicit interpreter | **CONFIRMED for the five user-level `settings.json` files. INCOMPLETE as a "the hooks are clean" claim** | M: a json walk of each of the five files gives 104 commands each: `/bin/bash` 80, `/usr/bin/env` 21 (20 `env bash`, 1 `env python3`), `true` 1, `date` 2. statusLine is `/bin/bash ~/.claude/statusline.sh`. **Missed: project-level hooks.** `~/Development/technical-analysis/.claude/settings.json` registers PreToolUse `Bash` → `$CLAUDE_PROJECT_DIR/.claude/hooks/block_live_orders.py` (`#!/usr/bin/env python3`), PostToolUse `Write\|Edit` → `post_write_verify.sh` (`#!/usr/bin/env bash`) and SessionStart → `session_market_clock.sh`, all by bare path. `reso-management-app/.claude/settings.local.json` does the same with PostToolUse → `uidotsh-audit.sh` (`#!/bin/bash`). No live `claude` has either directory as its cwd right now (`lsof -a -d cwd -c claude`), so they cost about 0 today. The first session opened there costs ~1 per Bash call, and 0070 and `hook-shebang-lint.sh` do not cover these files. |
| 2 | No by-path `#!` on the per-tool-call hook path; what remains is Stop/SessionStart/SessionEnd | **CONFIRMED AT RUNTIME** (the report only had the static graph) | M: 554 census `#!` execs had `/hooks/` in their script path over 60.8 min (04:53-05:54Z). **None of them is a PreToolUse, PostToolUse or statusline script.** If the ~19 per-Bash hooks were still bare, the expected count is ≈24k (I: 30,708 Bash/day × 19 × 60.8/1440). The main-checkout hooks that do appear are session-start-dispatch's children, 6 each (`setup-plan-symlinks`, `session-start`, `escalation-watch`, `accounts-board`, `config-mirror-assert`, `session-index-start`, `frontier-status`, `activation-watch`, `recycle-failed-inject`; `setup-task-symlinks` 9). That is ≈1.4k/day for the 10 (I, linear), which matches the report's static 138 × 10. Git hooks: pre-commit 10, commit-msg 10, pre-push 4 (≈240/240/95 a day). **Two overstatements:** `session-end.sh:104` runs `cc-in-kitty` only for an agent-team member (gated by `_se_member`, `:61-100`), not "every end". `~/.zshrc:705-706` runs it only when `KITTY_WINDOW_ID` is set and `$PPID != $KITTY_PID`, not on "every interactive zsh". |
| 3 | `cc-await-ping:913` → `cc-kqwait` is our top single trigger at ≈43k/day, in "43 live wait loops" | **COUNT CONFIRMED. LOOP COUNT WRONG.** One proposed fix is unsafe. | M: 1,216 `bin/cc-kqwait` execs in the 2,430 s window, every caller `/bin/bash`, every path in the main checkout (via `_ca_root`, `:853`). That is 43.2k/day (I, linear). The next path of ours is `bats-exec-test` at 827. **The 43 is a grep artefact.** `ps -axo args \| grep -c '[c]c-await-ping'` also matches each loop's python `cc-await-ping-sender` helper and the zsh/timeout wrappers. At 06:05Z it printed 34, but only 14 were `/bin/bash …/cc-await-ping` (12 were `Python - …/cc-await-ping-sender.<pid>`). So each loop re-execs `cc-kqwait` roughly every 30-40 s (I). The `/usr/bin/env bash "$KQ_BIN"` fix holds. **Reject the "better still, call `current-$HOSTTYPE` directly" variant:** the binary's stale-source guard runs only when the wrapper exports `CC_KQWAIT_SRC` (`cc-kqwait:139-141`, `:257`). Called directly, it silently runs a stale build after a source change. |
| 4 | Calibration: 23,793 real `#!` execs in 40.5 min (9.8/s, ≈846k/day); claude-infrastructure ≈40%, agent-context-sync ≈49% | **CONFIRMED, and the census is complete** | M: my recount gives total 44,576, A/B 20,783, **real 23,793** (the report's total and A/B are each 151 higher; the net is identical). Ours: 3,356 + 1,181 + 3,498 + 1,311 = 39.3%. **Drops ruled out:** over 2,245,720 exec events through ~05:54Z, `seq_num` is missing 4 values (`grep -oE '"(seq_num\|time)":…' \| awk` gap scan). So eslogger lost nothing, and the 05:20-05:30 dip in real execs (3,148 against 6.4-7.5k in earlier bins) is the workload, not loss. Minor: "main checkout 14.1%" includes ~330 execs (≈1.4%) of `~/.claude/autonomy/postland/wt-run-19481/…` (the `hb-kitty-ps` fixture and others). These are test copies, so production is ≈12.7% + 5.0%. |
| 5 | The 49% and the 20% come from "one 40-min mix, one pytest run dominant"; tests cost "≈170k/day while suites run" | **REFUTED in the cautious direction: both test streams are steady** | M: postland-verify runs almost back-to-back. `runner.log` shows 8 completions between 10-21 04:50Z and 10-22 03:08Z, with `run_s` 2,723-15,715. The current run (pid 19481, etime 3:28:32 at 05:52Z) began 03:30:31Z with 1,166 suites and a 22,145-test plan. "While suites run" therefore means about always. The census also holds 19 distinct `bats-run-*` dirs and 47 distinct `pytest-of-chrisren/pytest-N` basetemps, not one run. After the A/B ended (05:40-05:50Z), the top five paths are still agentsync pytest stubs (`…/launchctl-stub` under `/private/tmp/z76verify/{a,b}` 480 + 480, `r23z77fix` 180) and its `/usr/bin/shasum`. The share itself swings, though: agent-context-sync by cwd was 67% of the 04:50 bin and 18% of the 05:20 and 05:40 bins, as its runs moved to `/tmp` clones. Read the shares as ±20 points. |
| 6 | Land gates in worktrees ≈40k/day | **WEAK: one land** | M: 774 of the 1,181 worktree execs (65%) come from a single worktree, `rrp-t3-prep`. The ×35.6 scaling assumes one such land every 40 min. Size it as lands/day × ~800 instead (I). |
| 7 | `cc-qos-exec` needs a compiled launcher; `cc-kitty-bin` reorder; `claude-accounts` plist edits | **CONFIRMED** | M: `cc-qos-exec:48-105` walks PATH and `exec`s the real tool. Real targets: `agent-browser` resolves to Mach-O (`…/agent-browser-darwin-arm64`), so a Mach-O shim removes it entirely. `pytest` (python `#!`) and `bats` (bats-core `#!`) still cost one more each. `cc-kitty-bin:34-37` tries `command -v kitty` first, and `/opt/homebrew/bin/kitty` is `#!/bin/bash` + `exec …/kitty.app/…/kitty` (`file`). Both accounts plists `exec /usr/bin/perl -e '…exec @ARGV' N "$HOME/.claude/bin/claude-accounts"` (`plutil -convert json`). |
| 8 | Verbatim-shebang prefix is the only safe rewrite; `bash NAME` searches cwd first | **CONFIRMED, with one softening** | M: `man bash` lines 141-143, in both 3.2 and 5.3: "Bash first attempts to open the file in the current directory". Softening: Unsafe 1 says forcing `/bin/bash` "changes behaviour" for 182 scripts. The measure critique found **0** bash-4-only constructs outside comments in the `env bash` files (`measure.md:128`). The risk is fidelity, not wholesale breakage. The rule still stands for the 120 python scripts and for exactness. |
| 9 | Recall gaps: `_bounded`/timeout wrappers | **CONFIRMED and sized** | M, caller split of 34,157 non-A/B `#!` execs (04:51 to ~05:55Z, `process.executable.path`): `/bin/bash` 69.2%, Homebrew bash 5.3 16.7%, **`gtimeout` 3.8%**, python 3.4%, `/bin/zsh` 2.3%, `/usr/bin/env` 1.1%, `taskpolicy` 1.0%, perl 0.9%, git 0.8%, uv 0.3%, `claude.exe` 0.1%. So ≥6% of all `#!` execs come through a relay (gtimeout/env/taskpolicy/nice/lockf/nohup). Any lint has to look through those prefixes. |

### Cheaper or more robust levers the report missed

1. **Run the hermetic bats partition off the box. This lever already exists in the repo.**
   `.github/workflows/hermetic.yml` runs hourly (`cron: '17 * * * *'`) on `macos-latest` shards.
   `scripts/offbox-partition.sh` defines the partition as `tests/*.bats` minus `host-suites.manifest`
   (3 suites) minus `offbox-excluded.manifest` (47 entries). By that arithmetic, ≈96% of the suites
   could prove green on GitHub's kernel instead of this one (I). Today on-box postland-verify runs
   all 1,166 suites back to back (row 5). Our test stream (bats stubs plus bats-core, ≈20% of real
   `#!` execs, M row 4) would then fall to the ~50 host-coupled and excluded suites, and load would
   drop with it. No call-site edits are needed. Precondition (I): the newest pulled off-box record
   is from Aug 13 (`ls -la ~/.claude/autonomy/postland/offbox/`), so the producer looks dormant;
   check `scripts/offbox-green-pull.sh status` first. Moving the gate is the operator's call
   (deploy-live T1H tier).
2. **Vendor bats-core with explicit-interpreter internals.** Per test,
   `bats-exec-file:236` runs `if "$BATS_LIBEXEC/bats-exec-test" "$@" "$try_number"`, and per run
   `bats:517,522` runs `exec bats-exec-suite`, plus `bats-exec-suite:141,314,323`. All are
   `#!/usr/bin/env bash`. Changing those 6 sites to `"$BASH" …` removes 1 `#!` per test (827 in the
   window, 3.5% of real; M). Patching the Homebrew Cellar does not last, because `brew upgrade`
   overwrites it. A pinned vendored copy run by `cc-bats` does last.
3. **For the stubs, design before codemod.** There is no shared stub writer: 21 `mkstub`, 5 `make_stub`,
   5 `install_stub` and 2 `write_stub` uses, against 2,201 shebang/stub-writer lines in tests/*.bats
   (M, `grep`). The derived ratio is ≈4 stub execs per bats test (3,498/827). The obvious cheap fix
   is shebang-less stubs, which bash runs itself on ENOEXEC with no `#!` exec. The repo forbids
   them on purpose: CPython walks past them to the real binary
   (`.claude/rules/agent-operating-lessons-situational.md:184`). The safe central pattern is one
   compiled trampoline plus a `stub/<name>.sh` body, which keeps Python callers sealed.
4. **The single biggest lever on the box is in agent-context-sync, the operator's own repo.** In
   that repo the callers of its stubs are mostly bash, not Python (python is 3.4% of all callers;
   M row 9). The fix there is its stub design (same pattern as 3), not a `subprocess` monkeypatch.
   Its `/usr/bin/shasum` alone was 1,035 execs in the window (4.3% of real; M). A one-line
   `/usr/bin/perl /usr/bin/shasum` or `hashlib` change removes it. "No change in this repo can
   reach it" is true, but it should not drop out of the Mac-level plan.
5. **Untested, call-site-independent alternative: a caller-side bash that handles `#!` in user
   space.** bash's `shell_execve` calls `execve()` first and reads the `#!` line only on ENOEXEC
   (GNU `execute_cmd.c:6133,6140`; the fallback `execute_shell_script` is at `:6001-6043` and is
   compiled only `#if !defined (HAVE_HASH_BANG_EXEC)`, `:5989,6223-6225`; fetched from
   git.savannah.gnu.org). A build that runs that check before `execve` would turn every child
   `#!` exec of that shell into Mach-O execs. 86% of `#!` execs have a bash caller (M row 9), and
   that includes test stubs and third-party scripts. Cost and risk (I): it covers only callers that
   run under the patched build. `/bin/bash` (69.2%) is SIP-sealed, so our `#!/bin/bash` scripts,
   the 0070 hook prefixes and the plists would need to name the build. It is a shell fork to
   maintain, and its argv must match XNU's. The 16.7% Homebrew-5.3 slice would need only a PATH
   shadow. I rank it below 1-4, but it is the only option that does not depend on finding every
   call site.
6. **Enforcement has to be a runtime measure, not only a lint.** The report itself shows that `ps`
   cannot tell a `#!` exec from `/bin/bash <path>`, and ≥6% of execs come through relays (row 9).
   Static matching is a floor. The durable regression guard is a periodic root census or the
   existing per-Bash-call zone rate (`scripts/kalloc-leak-rate.sh`). For the census, start and
   stop eslogger under one `sudo` (`measure.md:130`) and filter after JSON decoding.

### Inferred but stated as measured

- §6, "`env` is Mach-O, so the extra hop does not leak": not measured. `measure.md` says the env
  relay path is INFERRED ≈ 0.
- Summary 3's "43 live wait loops": a measured number, but of the wrong thing (row 3).
- Answer 2, "no nested by-path `#!` two levels down": static at 75-85% precision. It holds, but
  only my runtime pass above measures it.
- "≈2 per Stop" (`wrap-ledger.sh:1497` via two hooks), "SessionEnd every end", "every interactive
  zsh": read from code, and the last two are wrong as stated (row 2).
- The Est./day column is labelled "MEASURED sample". Its rows are linear extrapolations of one land
  (row 6) and of a steady test stream mislabelled as episodic (row 5). Equal weighting per `#!`
  assumes ~1 element each. That fits the fleet rate (9.8/s × ~1.07 ≈ 10.5/s vs 9-12/s), but the
  first-in-lineage question is open (`measure.md:124,144`).

### Concerns

- eslogger has since stopped. `exec.jsonl` froze at 26,355,420,016 B, mtime 00:54:20 CDT
  (05:54Z), and `summary.txt` was written at 01:00 CDT (`ls -la`, `stat`). That summary uses
  `DUR=600` and the A/B paths are in it (`measure.md:130`). Do not read its per-hour rates as
  real. The full file now spans 04:51:16-05:54:16Z (63 min), so a cleaner second sample is the
  05:40-05:54Z tail, after the A/B ended.
- Off-axis, seen in passing: `$HOME` holds two stray directories, `'.claude:'` and one whose name is
  `.claude` + newline + "⚠ ship-land: stranded-sweep flags commit(s)…". They are the mark of an
  unquoted `mkdir` of captured output, created 2026-07-31 and 08-13 (`os.lstat` mtimes). I did not
  touch them.
- Deviation: my long passes ran as harness background tasks, whose stdout the harness keeps under
  `/private/tmp/claude-501/…/tasks/`. I wrote no other file and ran no `#!` leak arms.
