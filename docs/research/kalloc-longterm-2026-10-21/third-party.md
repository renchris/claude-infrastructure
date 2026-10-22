# Third-party `#!` triggers on this Mac (kalloc long-term, axis: third-party)

Date: 2026-10-22 00:10 CDT. Host: MacBookPro18,2, macOS 15.8.1 (24H32). Read-only work: no repo, settings,
launchd or session was changed. Every number is labelled MEASURED (with the command or input) or ESTIMATED/INFERRED
(with the method).

## Answer

1. **Third-party files are about 15% of the `#!` execs, and almost none of them run on their own.** MEASURED from the
   root census `~/.cache/kalloc-exec-census/20261021T235112/exec.jsonl`, strict window 2026-10-22 04:51:16-05:01:16Z
   (600 s): 373,132 execs (622/s), **6,997 `#!` execs (11.66/s)**. Execs of files we do not own: **1,075 (15.4%)**.
   - `/usr/bin/shasum` (Apple, `#!/usr/bin/perl`): 906 (12.9% of all `#!`; 84% of the third-party share)
   - Homebrew `bats-core` libexec chain: 93 (1.3%)
   - Homebrew cask wrapper `/opt/homebrew/Caskroom/kitty/0.48.2/.homebrew-command-wrappers/kitty`: 44 (0.6%)
   - node `#!/usr/bin/env node` JS (an MCP server and `npm-cli.js`): 11 (0.2%)
   - Python console-script wrappers: 10 (0.1%)
   - `brew`: 8. `man`, `tmp_cleaner`: 3.
   - git hooks (our identity gate in `.git/hooks`): 4 (0.06%)
2. **Who starts them.** Our own code starts nearly all of these execs. MEASURED attribution (exec `cwd`, argv, process group):
   - shasum: 691 of 906 had cwd `/Users/chrisren/Development/agent-context-sync`. That is the agentsync test suite
     running `scripts/install.sh`, which calls `/usr/bin/shasum -a 256` by absolute path
     (`agent-context-sync/scripts/install.sh:1051`, `:4401`; `launcher/build.sh:57`). Most of the remaining ~215
     ran in our worktrees (`tm-upstream-wt` 63, `accounts-board-band` 26, `rrp-t3-prep` 17, `wt-cc-000146-45877` 16).
     Argv: `-a 256` 772, plain `shasum` (SHA-1) 131, `-a 1` 3.
   - The kitty wrapper is always called as `/opt/homebrew/bin/kitty @ …` (`ls`, `launch`, `get-text`, `action`),
     under `timeout 15`/`timeout -k 3 10`. Our resolvers pick it first: `bin/cc-kitty-bin:34-37` and
     `bin/it2-kitty:173-176` try `command -v kitty` and then `/opt/homebrew/bin/kitty` before
     `/Applications/kitty.app/Contents/MacOS/kitty`. `bin/cc-resume-layout.sh:128` puts `/opt/homebrew/bin/kitty`
     first. 17 files call `cc-kitty-bin` (`git grep -l cc-kitty-bin -- hooks bin scripts | wc -l`). On PATH,
     `/opt/homebrew/bin` (entry 16) comes before `/Applications/kitty.app/Contents/MacOS` (entry 47), so a bare
     `kitty` or `kitten` also hits the `#!/bin/bash` wrapper.
   - Our test runs start bats: `timeout -k 10 300 /opt/homebrew/bin/bats tests/….bats` from session shells.
     `bats-exec-file:236` runs `"$BATS_LIBEXEC/bats-exec-test"` by path, which is one `#!` exec per test.
   - The node execs are Claude Code starting the MCP server
     `…/node_modules/@softeria/ms-365-mcp-server/dist/index.js` (6) and `npm-cli.js` (4), with `claude.exe` as the
     direct parent, at session or MCP start.
   - Work no tool of ours started: `brew` (8), `man` (2), `tmp_cleaner` (1), about 0.3% of `#!` execs.
3. **No `#!` exec on Claude Code's per-tool-call path, from kitty, or from launchd's top-level programs.** MEASURED:
   - claude.exe's direct children in the window were `bash` 2,884, `sh` 1,455, `git` 501, `readlink` 301, `env` 253,
     `jq` 249 and so on. All are Mach-O. The only `#!` children were the MCP/npm starts above, plus about 10 test-stub
     rows that may be pid-reuse noise.
   - kitty and kitten had no `#!` children beyond one noise row.
   - Of the 84 LaunchAgents (`plutil -extract ProgramArguments.0`), every `com.claude.*` job starts Mach-O
     `/bin/bash` or `/bin/zsh`. Only 4 agents start a `#!` file directly: `com.agent-secrets.smoke`,
     `com.voiceink.autoupdate`, `com.voiceink.keepalive` (KeepAlive) and `sh.brew.natural-tts` (KeepAlive). These
     run once per (re)start, so their cost is negligible.
   - The launchd-rooted `#!` execs in the census are our scripts (`lr-reset-poller.sh`, `cc-dispatch`,
     `evidence5.sh`) calling things by path.
   - Claude Code itself is Mach-O: `~/.claude-293/node_modules/.bin/claude -> …/claude-code/bin/claude.exe`
     (`file -L`: Mach-O 64-bit arm64).
4. **Most of this window's leak was in test fixtures, not third-party files or our bin/.** MEASURED, same window:
   - pytest `tmp` stubs: 2,658 (38.0%). The top names are `launchctl-stub` 1,458, `python` 386, `scutil` 295 and
     `uv` 281, all under `…/T/pytest-of-chrisren/pytest-680/`, from the agentsync tests.
   - The agentsync rehearsal sandboxes `/private/tmp/agentsync-rehearsal-v31-*`: 1,018 (14.5%).
   - Bats test stubs (`postland-run.*`, `bats-run-*`, `T/tmp.*`: `jq`, `readlink`, `python3`, `kitty`, `grep`,
     `dirname`, `lsof`): 714 (10.2%).
   - Other tmp files (`/private/tmp/r23h.*` and others): 515 (7.4%).
   - Our `claude-infrastructure` files (repo, `~/.claude`, `.worktrees`): 1,011 (14.4%). The top one is
     `bin/cc-kqwait` with 384.

   A shim for `bin/` and `scripts/` alone would have covered about 14% of this window.
5. **The census accounts for the whole leak rate (INFERRED).**
   - 11.66 `#!`/s × 1.098 elements/exec (15.8.1 A/B, `~/.cache/kalloc-158-ab/`) ≈ 12.8 elements/s.
   - The capacity-alarm series (`~/.claude/logs/kalloc-zone-series.tsv`, bytes/1024) read 11.07 elements/s from
     03:49:30 to 04:25:00Z and 7.92/s from 04:25:00 to 04:48:27Z, against the doc's post-0070 9-12/s.
   - So `#!` execs explain the observed residual growth. No other leak source is needed.

## Daily estimate of the third-party share (ESTIMATED)

Method: the 600 s census rates × 86,400 s × 1.098 elements/exec × 1 KiB. This is one 10-minute window during a heavy
agentsync pytest run. The mix depends on the workload; the volume matches the measured daily rate.

| Source | `#!`/s (measured) | Elements/day (est.) | GiB/day (est.) | Who decides the call |
|---|---|---|---|---|
| All `#!` | 11.66 | ~1.11M | ~1.06 | (the doc measures ~0.92-0.97 GiB/day on this boot) |
| Third-party files, total | 1.79 | ~170k | ~0.16 | almost all our code |
| ↳ `/usr/bin/shasum` | 1.51 | ~143k | ~0.14 | agentsync `install.sh` (76%), our scripts |
| ↳ bats-core chain | 0.155 | ~15k | ~0.014 | our test runs |
| ↳ Homebrew kitty wrapper | 0.073 | ~7k | ~0.007 | `cc-kitty-bin`, `it2-kitty`, `cc-resume-layout.sh` |
| ↳ node, python, brew, man, git hooks | 0.06 | ~6k | ~0.005 | Claude Code MCP start, operator, git |
| Test fixtures in tmp (ours, not third-party) | 8.18 | ~776k | ~0.74 | agentsync pytest/rehearsal, infra bats |

Uncertainty: the shasum and fixture rows scale with how much agentsync and bats testing runs. A quiet day could have
both near zero. Kitty, MCP and git-hook rows scale with fleet activity and are small in any case.

## Static inventory: Mach-O vs `#!` per PATH directory (MEASURED)

Method: each unique `$PATH` entry of this session. For every executable regular file (symlinks followed), I read the
first bytes and counted Mach-O magic vs `#!`. This is equivalent to `file -L -b` for this split; I spot-checked
with `file -L -b` on `claude`, `node`, `npx`, `npm`, `pnpm`, `uv`, `git`, `gh`, `jq`, `rg`, `python3` and `/sbin/sha256`.

| PATH dir | exec | Mach-O | `#!` | main `#!` interpreters |
|---|---|---|---|---|
| `~/.claude/bin` (ours) | 161 | 1 | 160 | /bin/bash 68, env python3 48, env bash 41 |
| `~/.opencode/bin` | 1 | 1 | 0 | |
| `~/Library/Caches/fnm_multishells/*/bin` | 17 | 2 | 15 | env node 15 (npm, npx, corepack, pnpm…) |
| `~/.bun/bin` | 2 | 2 | 0 | |
| `~/.antigravity/antigravity/bin` | 2 | 0 | 2 | env bash |
| `~/.turso` | 2 | 2 | 0 | |
| `~/.foundry/bin` | 5 | 4 | 1 | env bash |
| `~/.yarn/bin` | 5 | 0 | 3 | env node, /bin/sh |
| `~/.config/yarn/global/node_modules/.bin` | 3 | 0 | 3 | env node |
| `~/Library/Python/3.11/bin` (pip --user entry points) | 52 | 1 | 51 | python3.11 37, /usr/local/bin/python3 12 |
| `~/.local/bin` (uv tools: mflux, meeteval, …) | 56 | 7 | 49 | uv-tool python 42, env python3, env bash |
| `~/bin` (operator's own) | 44 | 3 | 41 | env bash 18, /bin/bash 11, env python3 9 |
| `~/.claude/shims` | 1 | 0 | 1 | `it2` -> `~/.claude/bin/it2` (/bin/bash) |
| `/Library/Frameworks/Python.framework/…/3.11/bin` | 47 | 4 | 43 | python3.11, python3 |
| `/opt/homebrew/bin` | 1008 | 791 | 217 | /bin/sh 76, python3.14 22, python3.12 18, /bin/bash 16 |
| `/opt/homebrew/sbin` | 11 | 8 | 3 | /bin/sh |
| `/usr/local/bin` | 85 | 35 | 50 | python2.7 14, python3.11 10, env node 8, perl 6 |
| `/usr/bin` | 914 | 652 | 262 | perl 142, /bin/sh 73, dtrace 23, ruby 8 |
| `/bin` | 37 | 37 | 0 | |
| `/usr/sbin` | 220 | 197 | 23 | /bin/sh 18 |
| `/sbin` | 74 | 73 | 1 | |
| `~/Library/pnpm` | 7 | 0 | 7 | /bin/sh (cmd-shim: claude 2.0.5, mintlify, rush, soketi) |
| `~/.aftman/bin`, `~/.cargo/bin`, `kitty.app/Contents/MacOS`, cryptex/Apple dirs | 23 | 23 | 0 | |
| `/opt/homebrew/opt/fzf/bin` | 3 | 1 | 2 | env bash |

Project `node_modules/.bin`, MEASURED (Python header read over `~/Development/*/node_modules/.bin` and
`~/Development/*/*/node_modules/.bin`, 129 directories): **2,920 `#!`, 9 Mach-O**, 19 broken links. Every
`npx <tool>` and every `pnpm`/`npm run` script that calls a `.bin` entry is one `#!/usr/bin/env node` exec. The census
saw almost none of these in the window (node 11 in total).

`#!` files that a bare name resolves to, MEASURED (`head -c2` per file):
- `kitty`, `kitten`: Homebrew cask wrappers, `#!/bin/bash` + `exec /Applications/kitty.app/Contents/MacOS/…`.
- Node tools: `npm`, `npx`, `pnpm`, `corepack` (`#!/usr/bin/env node`, fnm and Homebrew node).
- Homebrew: `brew` (`#!/bin/bash -pu`), `bats`, `pip3*`, `yt-dlp`, `gcloud`, `gsutil`, `bq`, `az`, `fastmcp`,
  `uvicorn`, `httpx`, `openai`, `mcp`, `ms-365-mcp-server`, `mosh` (`env perl`).
- `/usr/local/bin`: `code` and `cursor` (`env bash`), `tailscale` (`#!/bin/sh` wrapper), `npm`, `npx`, `yarn`.
- `/usr/bin`: `shasum` (perl), `man`, `zless`, `zdiff`, `ssh-copy-id`, `curl-config`, `xml2-config`, and the POSIX
  builtin wrappers `command`, `type`, `cd`, `read`, `wait`, `hash`, `getopts`, `ulimit`, `umask`, `alias`, `jobs`,
  `fg`, `bg`. Each is `#!/bin/sh` + `builtin …`, so an external exec through `env`, `xargs`, `find -exec` or
  `timeout` is a `#!` exec.

Git hooks, MEASURED (scan of `~/Development/*/.git/hooks` and `core.hooksPath`):
- About 95 repos have `pre-commit`, `pre-merge-commit` and `pre-push`. Many also have `commit-msg`.
- These are our `cc-git-identity-gate` hooks (`#!/usr/bin/env bash`, installed by `scripts/git-identity-assert.sh`),
  not husky.
- Repos with husky or a custom `core.hooksPath`: `next.js`, `panda`, `umami`, `zag`, `finance-ai-web-app`,
  `libsql-client-ts`, `solarbeam-interface`, `reso-management-app` (`~/.reso/land-tools/scripts/hooks`).
- git runs a hook by path, so each commit costs 2 `#!` execs and each push 1. The census saw 4 in 600 s.

## Fixes, from the scalable end (INFERRED unless marked)

1. **One compiled trampoline, used everywhere a `#!` file must be found by name.** A small Mach-O launcher reads the
   real file's `#!` line and calls `execv(interp, [interp, opt?, script, args…])`. The trampoline is Mach-O and
   `/bin/bash` (or perl, python, node) is Mach-O, so no `#!` exec happens.

   Expected cost per call: ~0. The basis is the doc's `/usr/bin/true` arm (−0.02 ± 0.02) and the `/bin/bash leaf.sh`
   arm (0.007 ± 0.101). The trampoline itself is unmeasured, and the measurement axis should A/B it.

   Places for the same binary, with this window's share of `#!` execs:
   - **Test-fixture stubs (~70% here).** Have the pytest and bats stub writers copy or hardlink the trampoline as
     `<name>` and write the body to `<name>.sh`. This also covers the agentsync rehearsals.
   - **Our `bin/` and `scripts/` (14%).**
   - **A PATH-front shim dir for third-party names called bare.** Candidates: `kitty`, `kitten` (straight to the app
     binary), `npm`, `npx`, `pnpm`, `corepack` (node + JS), `brew`. `~/.claude/shims` already exists at PATH entry 13,
     ahead of `/opt/homebrew/bin` (entry 16).

   Code signing: Apple Silicon needs a signature, and `ld` signs ad-hoc by default. A copy or hardlink keeps the
   signature. NOT verified on this box.
2. **Absolute-path third-party calls need code changes, not PATH shims.** The largest third-party item, `shasum`, is
   called as `/usr/bin/shasum`. `/sbin/sha256sum`, `/sbin/sha1sum` and `/sbin/sha256` are Mach-O and ship with
   macOS 15. MEASURED: `echo x | /sbin/sha256sum` prints `<hex>  -`, the same format as `shasum -a 256`, and
   `/sbin/sha256 -q` prints the bare hash.

   Convert:
   - agentsync `scripts/install.sh:1051`, `:4401` and `launcher/build.sh:57`. This removes about 76% of this window's
     shasum.
   - In infra: 54 files call `shasum`, and only 6 source `hooks/lib/shasum-direct.sh`
     (`git grep -l` counts). `shasum-direct` is a shell function, so it does not reach `xargs shasum`, `find -exec`,
     python `subprocess` or a script that does not source it. Calling `/sbin/sha256sum` directly does.
3. **Kitty resolution: a one-line reorder in three files.** Try `/Applications/kitty.app/Contents/MacOS/kitty` first
   in `bin/cc-kitty-bin:34`, `bin/it2-kitty:173` and `bin/cc-resume-layout.sh:128`, as `bin/cc-limited:1118` and
   `scripts/lib/restore-heartbeat.sh:158` already do for kitten. Or move `kitty.app/Contents/MacOS` ahead of
   `/opt/homebrew/bin` on PATH. Saves ~0.07 `#!`/s (est. ~7k elements/day).
4. **Land-gate lint, fed by the census.** Refuse new `/usr/bin/shasum`, bare `shasum`, `/opt/homebrew/bin/kitt(y|en)`,
   bare `npx` in hooks, bin and scripts, and `#!` stubs written by test helpers. Generate the denylist from each
   census: any third-party `#!` path above N execs per 10 min becomes a lint row. Re-run the census after each
   wave.
5. **bats.** `bats-exec-file:236` runs `bats-exec-test` by path, once per test (0.155/s here). Options: vendor
   bats-core into the repo with that line changed to `bash "$BATS_LIBEXEC/bats-exec-test"` (and likewise for
   `bats-exec-suite:323`, `bats-exec-file`), or run fewer, larger test files. Patching the Homebrew Cellar copy is
   lost on the next `brew upgrade`.
6. **MCP servers started from a `#!` JS file.** Configure `command: node`, `args: [<abs>/dist/index.js]` instead of
   the bin name, for `ms-365-mcp-server` and any other `npx`-style server. This is small: once per session or MCP
   start.
7. **Leave alone (below 0.1% each):** Python and uv console scripts, `brew`, `man`, git hooks, and the four `#!`
   LaunchAgents. If the git hooks are ever wanted, the hook file itself would have to become the trampoline, since
   git runs hooks by path.

## Caveats

- The census is a single 10-minute window during heavy agentsync pytest and rehearsal activity plus an infra bats
  run. The category mix will move with the workload. Re-run it at a quiet hour and during a postland or nightly
  regression to bound the shasum and fixture rows.
- Attributing a parent by pid is unreliable: forks emit no ES exec event, and pids are reused. Lines of the form
  "shasum parent = `/usr/bin/tr`" are artifacts and were not used. The attributions above rest on the exec's own
  `cwd`, argv and process group, which are reliable.
- The first analysis pass read the file while eslogger was still writing (window to 05:03:22Z, 8,349 `#!`). All
  figures above come from the strict 600 s window.
- **The census overran.** At 00:11 CDT `eslogger` (pids 90947/90981) was still recording. The census script's
  `sudo -A pkill` (pid 24146) is waiting on an osascript password dialog (pid 24190). `exec.jsonl` was 7.6 GB and
  growing by ~6 MB/s, and `summary.txt` had not been written. This axis did not touch it.

## Critique

Adversarial review, 2026-10-22 00:25 CDT, read-only. I re-ran the census counts with my own streaming Python pass over
`exec.jsonl`. A row is a `#!` exec when `event.exec.script` is non-null, and the caller is `process.executable.path`:
the image the same pid had before the exec, so pid reuse cannot affect it. I also re-read every cited source line and
re-ran the format checks.

### Verdicts on the main claims

1. **Census totals and category split: CONFIRMED (MEASURED).** Strict window 04:51:16-05:01:16Z: 373,132 execs and
   6,997 `#!`, identical to the doc. Every category also matches: pytest-tmp 2,658, rehearsal 1,018, infra 1,011,
   shasum 906, bats stubs 714, other tmp 515, bats-core 93, kitty wrapper 44, node 11, brew 8. Small errors:
   - The 4 git hooks are listed under "files we do not own", but they are our identity gate in
     `claude-infrastructure/.git/hooks` and `.worktrees/tm-upstream-clone/.git/hooks`. They already sit inside infra's
     1,011, and the 1,075 total leaves them out, so the bullet list and the total disagree.
   - `bin/cc-kqwait` had 326 execs in the strict window, not 384. The 384 probably comes from the first, longer pass.
   - LaunchAgents: there are 78 plists. The 84 directory entries include 6 `.bak`, `.disabled` and `.pre-*` files
     (`ls ~/Library/LaunchAgents | grep -v '\.plist$'`). The 4 `#!` agents are confirmed (head -c2 of
     ProgramArguments.0).
   - 60 infra files call `shasum`, not 54 (`git grep -l shasum -- hooks bin scripts | wc -l` at 3d9085132 and in
     this worktree). 11 of them call `/usr/bin/shasum` by absolute path. 6 files mention `shasum-direct`, and one of
     them is the lib itself, so it has 5 consumers.
2. **"Python console-script wrappers: 10 (0.1%)": UNDERSTATED (MEASURED).** 367 `#!` execs (5.2%) have a Python
   binary as their interpreter. 286 of them are the uv-generated `agentsync` console script in the rehearsal sandboxes
   (`#!…/uv/python/cpython-3.11.17…/python3.11`), which the doc files under "rehearsal". uv writes them, so a
   trampoline in the stub writers does not reach them. To cover them, call `<venv python> -m agentsync`, or point the
   rehearsal at a trampoline (INFERRED).
3. **"Test fixtures ~70%, fixable in the stub writers": PARTLY REFUTED.** The 14.5% rehearsal share is mostly not
   stubs. Its top names are `agentsync` 278 (uv console script), `sb` 179, `install.sh` 170 and `run.sh` 132: the
   product's installed scripts and the rehearsal harness (MEASURED). The stub-writer change reaches pytest-tmp (38.0%),
   bats stubs (10.2%) and the stub part of other-tmp (`launchctl-stub` 160, `python` 139, `uv` 79, `scutil` 32). That
   is about **55%, not 70%** (INFERRED coverage).
4. **"A shim for bin/ and scripts/ would have covered ~14%": true only if each entry file becomes the Mach-O.** Of
   the 1,007 infra `#!` execs (git hooks excluded), the path passed to exec (args[1], or args[2] under `env`) was:
   - `~/.claude/bin` or `~/.claude/shims`: 183 (18%)
   - the repo's absolute path: 417
   - a worktree's absolute path: 239
   - other `~/.claude/` paths: 125
   - relative: 32

   (MEASURED.) A shim dir at the front of PATH therefore reaches at most ~18% of the 14%, about 2.6% of all `#!`. The
   full 14% needs the file at each path to become Mach-O. That means a build step in every checkout, every worktree and
   every postland copy (`~/.claude/autonomy/postland/wt-run-19481/bin/cc-memory-rotate` is in the census). The other
   route is a codemod that moves callers to a launcher prefix. The doc's "behind our bin/ entries" names neither.
5. **Claim 3, "Claude Code starts no `#!` on its per-call path": MOSTLY CONFIRMED, but one row class is misread.**
   - Counted by pre-exec image, claude.exe made about 20.7k execs in the window: `sh` 14,771, `git` 4,979, `zsh` 672,
     `security` 117 and so on (MEASURED).
   - That is 5-10 times the doc's "bash 2,884, sh 1,455, git 501". A pid→image map built only from in-window exec
     events would miss the ~40 long-lived claude.exe processes that started before the census (INFERRED cause).
   - claude.exe's own `#!` execs numbered 21: `ms-365-mcp-server` 6, `npm-cli.js` 4, and
     **`~/.claude/shims/it2 session` 11** (a symlink to `~/.claude/bin/it2`, `#!/bin/bash`).
   - The doc calls about 10 such rows "test-stub rows that may be pid-reuse noise". They are real Claude Code
     teammate-pane calls, made into the very shim dir the doc proposes for trampolines.
   - Each call then runs the pip `it2` (`#!…/python3.11`, 4 in the window) and `bin/it2-kitty` (21). The total is
     small, about 0.06/s, but it is the only `#!` on Claude Code's own call path, and the file is ours.
6. **Claim 5, "the census accounts for the leak": CONFIRMED, and the match is closer than the doc shows.** The doc
   compared against zone intervals before the census.
   - The interval that overlaps it in `~/.claude/logs/kalloc-zone-series.tsv` is 04:48:27-05:08:49Z: 371,637 →
     387,915 elements, **13.32 el/s**. This is raw `data.kalloc.1024`, not cred-corrected.
   - The census over 04:51:16-05:08:49Z had 11,894 `#!` in 1,053 s, 11.30/s. At 1.098 elements each that is
     **12.40 el/s, 93% of the measured rate** (MEASURED inputs, INFERRED match).
   - The same window had 60,845 non-platform Mach-O execs (101/s): Homebrew `jq` 24,835, `git` 17,609, `bash` 3,959,
     `claude.exe` 3,370, and our own `~/.cache/cc-kqwait/…/cc-kqwait` 326.
   - The ~0.9 el/s left unexplained caps the cost of a non-platform, ad-hoc-signed Mach-O exec at roughly 0.01-0.03
     elements (INFERRED; cred noise not removed). That is indirect support for the trampoline premise.
7. **"The trampoline is unmeasured, and code signing is NOT verified": partly settled.**
   - Signing: `codesign -dv ~/.cache/cc-kqwait/cd59cf435412e852-arm64/cc-kqwait` reports
     `flags=0x20002(adhoc,linker-signed)` and `location=embedded`, and that binary ran 326 times in the window. So a
     clang-built ad-hoc binary runs on this box (MEASURED). Whether a copy or hardlink keeps its signature is still
     untested. The signature is embedded in the file, so it should travel with a copy (INFERRED).
   - The measurement axis is A/B-testing the premise now (`~/.cache/kalloc-longterm-ab/rows-n3000.tsv`, cycle 1 only,
     still running, eslogger up). Per exec:
     - S, `#!` leaf by path: 2,967/3,000 = 0.99
     - B, `/bin/bash leaf`: 0.065
     - L, Mach-O `launch` → `/bin/bash leaf`: 159/3,000 = **0.053**
     - C, `#!` parent → `#!` leaf: 7,516/3,000 = 2.51 per unit, i.e. 1.25 per `#!`

     This is one cycle, not a verdict. The C row hints that nested `#!` execs cost more than 1 each, in which case the
     doc's flat 1.098 is low for chains (INFERRED, n=1).
   - `launch.c` hard-codes `/bin/bash`, while the doc's design reads the `#!` line. These parts of that design remain
     untested: the single optional shebang argument, `#!/usr/bin/env -S`, `#!/bin/bash -pu` (brew), and interpreters
     that are themselves scripts.
8. **shasum → `/sbin/sha256sum`: CONFIRMED, with one caveat.** Output is identical for stdin, for files and for `-b`
   (the `*` marker), and a missing file exits 1 in both (MEASURED). `/sbin/sha256sum -c` with no file argument prints
   usage, while `-c -` works (MEASURED). Neither repo uses `shasum -c` (git grep). All 906 shasum execs ran
   `/usr/bin/perl` with args[1] = `/usr/bin/shasum`. Argv cannot separate bare calls from absolute ones, because bash
   passes the resolved path either way.
9. **Kitty: CONFIRMED.** The cited lines are accurate. The wrapper is `#!/bin/bash` +
   `exec "/Applications/kitty.app/Contents/MacOS/kitty" "$@"`. A cheaper fix than a trampoline: a symlink
   `~/.claude/shims/kitty -> /Applications/kitty.app/Contents/MacOS/kitty` (and one for `kitten`). Exec through it is
   a Mach-O exec, it needs no build, and `command -v kitty`, which `cc-kitty-bin` and `it2-kitty` try first, returns
   it. `cc-resume-layout.sh:128` still needs its reorder. Whether kitty runs correctly through a symlink is untested
   (INFERRED).
10. **bats `bats-exec-file:236`: CONFIRMED** (bats-core 1.13.0). In addition, `bats:118` puts `$BATS_LIBEXEC` first on
    PATH, so a PATH shim cannot catch `bats-exec-suite` or `bats-exec-file` either. Vendoring is the only route, as the
    doc says.

### Cheaper or more robust options the doc missed

a. **Two agentsync test helpers start the window's largest single source.**
   - Stub names in tmp, rehearsal excluded (MEASURED): `launchctl-stub` 1,618 (23.1%), `python` 525, `uv` 360,
     `scutil` 327, `agentsync` 257. Together that is 3,087 (44%).
   - `launchctl-stub`, `uv` and `scutil` are written by `_write_exe` (`agent-context-sync/tests/test_install_oneshot.py:310`,
     63 calls) and `_exe` (`tests/test_install_next_line.py:36`). The launchctl stub reaches the installer through
     `$AGENTSYNC_LAUNCHCTL` (`scripts/install.sh:982`). The writers of the `python` and `agentsync` stubs were not
     traced.
   - Changing those helpers to keep the body in a sidecar and copy the trampoline in as the stub is the cheapest
     high-yield change in this window. With the 3 agentsync `/usr/bin/shasum` lines (740 shasum execs had an agentsync
     or rehearsal cwd), the agentsync repo held **~55% of this window's `#!`**, against 14% for the bin/ shim
     (INFERRED from grep plus census names).
   - bash ran 2,547 of the 2,658 pytest-tmp stubs (MEASURED), so `export -f` function stubs are a zero-exec
     alternative. They do not survive `timeout`, `env` or `command -v`.
b. **Infra bats stubs have no single point to change.** The tests contain 4,131 `#!` literal lines across 1,245 files,
   and only 21 files `load` a helper (git grep). The lever there is the land-gate lint plus a stub helper for new
   tests, not a one-place edit.
c. **The trampoline's build pattern already exists.** `bin/cc-kqwait` and `bin/cc-jetsam-exec` embed C source and build
   it with clang into a sha-keyed `~/.cache` dir (`bin/cc-kqwait:26-35`, `:286-288`). Reuse that instead of new build
   machinery. `bin/cc-kqwait` is also the top infra `#!` (0.54/s, est. ~0.045 GiB/day), and its `#!` wrapper exists
   only to find the cached binary.
d. **Two trampoline design gaps.**
   - A stub found through PATH gets a bare `argv[0]`, so the trampoline must find its own file with
     `_NSGetExecutablePath` or `proc_pidpath`.
   - The body's `$0` becomes the sidecar path. That breaks stubs that dispatch on `$0`, unless the sidecar sits in the
     same dir with a predictable name.
e. **The census tool.** It overran because its stop step needs a second sudo: `sudo -A pkill` waits on a dialog. At
   05:24:40Z eslogger (pid 90981) was still recording, and `exec.jsonl` was 12.85 GB, growing about 6.6 MB/s (~24 GB/h).
   There is 3.8 TiB free, so disk is not urgent. A census that bounds itself under its one sudo, e.g.
   `sudo -A timeout 600 eslogger exec`, would need no second prompt. The doc's fix 4 depends on re-running the census
   after every wave, so this matters (MEASURED sizes; INFERRED fix).
f. **Lineage: an untested lever.**
   - In issue #66020 (comment of 2026-09-25), willmcginnis reports from 26.6.2 that the first `#!` exec in a lineage
     costs 0.01-0.37 and later ones cost ~1. Photon measured 0.016, 0.99, 2.00 and 3.01 KiB at depths 1-4
     (`gh api repos/anthropics/claude-code/issues/66020/comments`).
   - Here the S arm's parent is `/bin/bash run.sh`, yet it costs 0.99. But this session's ancestry includes
     `bash ~/.claude/bin/cc-close-attrib` and an `expect` launcher (`ps` chain), so whether 15.8.1 gives a first-exec
     discount is untested.
   - If it does, sessions and launchd jobs started with no `#!` ancestor would make every single-level `#!` cheap
     without touching the 570 scripts. The test is an S arm run from a launchd `/bin/bash` job (unmeasured).

### Net verdict

The recount reproduces every census number, and the core recommendation stands: one Mach-O trampoline plus a
census-fed lint. Three framing errors need fixing:
1. Stub writers reach about 55% of the window, not 70%.
2. The bin/ and scripts/ 14% needs in-place Mach-O entries. A PATH shim reaches about 2.6%.
3. The claude.exe `it2` rows are real, not noise.

In this window the highest-yield first move was in agentsync: two test helpers and three shasum lines. The bin/ shim
comes after that. All shares come from one test-heavy 10-minute window.
