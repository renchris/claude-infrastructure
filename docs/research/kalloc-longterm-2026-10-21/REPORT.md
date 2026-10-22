# The `#!` kernel leak, long term: what to build (synthesis, 2026-10-22)

**Inputs:**
- the eight axis files in `~/.claude/autonomy/research/kalloc-longterm-2026-10-21/`, each read with its Critique;
- `docs/research/panic-2026-10-18-zone-map-shebang-leak.md`;
- the root exec census at `~/.cache/kalloc-exec-census/20261021T235112/`.

The census `summary.txt` exists but is wrong as written:
- it counts the A/B test harness (`leaf.sh` 24,025 and `parentC.sh` 12,013 of its 70,195 `#!` execs);
- it computes `per_hour` from a 600-second window, but eslogger ran 63 minutes (`summary.txt` lines 1-4; `measure.md` Critique row 9).

I recounted every share below from `exec.jsonl` directly (§7). Labels: MEASURED, REPORTED, ESTIMATED and INFERRED, as in the brief.

## 1. Answer

**What to build.** Build one small compiled launcher, a "trampoline": a Mach-O binary that reads a script's `#!` line and runs that interpreter with the script as its argument, so the kernel never takes its `#!` path.
- Use it wherever a `#!` file has to be found by name, starting with test stubs, which is where the leak is now.
- Fix every call we own at the call site.
- Hold both in place with a lint at the landing gate and a leak-rate alarm that re-runs the root census whenever the rate goes back up.

**Why the bin/scripts shim alone is aimed at the wrong place.** In the 63-minute census:
- Test and rehearsal harnesses caused **81%** of the 34,157 real `#!` execs.
- One agent-context-sync `launchctl-stub`, which that repo's installer tests poll every 0.05 s, caused **29%** by itself.
- Our production tools caused 18%. Homebrew, npm and git hooks together caused under 1%.
- Our own code mostly calls checkout and worktree paths directly, so a shim behind `~/.claude/bin` reaches only about 5%.
- `scripts/` and `hooks/` cannot be shimmed in place at all, because bash refuses a Mach-O file handed to it as a script.

**Why this is the most scalable, long-term option.**
- One binary fixes every by-name case, in any repo, with no per-script logic.
- The lint stops new by-path calls when they land.
- The census loop finds what the lint cannot see, so the fix keeps up with a workload whose mix moved 3-8x between 10-minute windows.

**Expected rate after the build (ESTIMATED): about 0.1 GiB/day, range 0.05-0.3, against 0.93 today.** That is under the 0.3 GiB/day line where the leak stops setting when the Mac reboots. At 0.1 GiB/day the ceiling is about 200 days away, so ordinary update reboots reset the zone first.

**Run a one-day lineage test first.** If macOS 15.8.1 only charges a `#!` exec that already has a `#!` ancestor, as two 26.x Macs do, then changing three lines in the session launchers removes a further 17-44% for free.

## 2. Ranked options

"Cut" is each option's share of the census window's 34,157 real `#!` execs (04:51:16-05:54:20Z). The window is a single hour with heavy test activity, and class shares swung up to 8x between 10-minute bins.

| # | Option | Leak cut | Basis | Effort | Risk | Maintenance |
|---|---|---|---|---|---|---|
| 1 | **agent-context-sync harness:** write stubs as trampoline links (`_write_exe` at `tests/test_install_oneshot.py:310`, `_exe` at `tests/test_install_next_line.py:36`, `tests/test_launcher.py:570`); run `python -m agentsync`; use `/sbin/sha256sum` for its 3 `shasum` lines | **≈53%** (launchctl-stub 28.6, scutil 5.7, python stub 5.7, agentsync 5.2, shasum 3.9, uv 3.7) | MEASURED share; the class ran 5-71% per bin | S (one repo) | Low (test-only) | Low |
| 2 | **Start the session roots through their interpreter:** `~/.zshrc:504,508`, `lr-fire-resume.sh:1740`, the caller of `reso-resume-one`, `it2-kitty:1300` | 0 if every `#!` costs; **17-44%** if 15.8.1 charges only a `#!` with a `#!` ancestor (p ≈ 0.5) | ESTIMATED (`shim.md` Critique 7b) | XS + test T-0 | Low (argv unchanged) | None |
| 3 | Call `cc-kqwait` from `cc-await-ping` through its own interpreter (`bin/cc-await-ping:913`) | **5.2%** (1,780); 2-5% in every window | MEASURED | XS | Low | None |
| 4 | Other one-line fixes (§3 Phase 1): `shasum` → `/sbin/sha256sum`/`sha1sum` (60 files), with no hash in the beacon gate; `cc-settings-parity` via python3; the `claude-accounts` plist relays; `cc-in-kitty`; kitty's app binary first | **≈6.4%**; about 10% during a beacon prompt storm | MEASURED | S | Low (identical output, measured) | 1 lint row |
| 5 | Vendored bats-core with `"$BASH"` at its 6 libexec calls, plus an upstream PR | **5.3%** (1,820) | MEASURED | S | Low-med | Vendor copy until upstream ships |
| 6 | Infra bats stubs through a `cc_stub` helper and the trampoline; top 12 test files first; ratchet lint R4 | **≈10-12%** (the top 12 files hold 79% of bats `#!` execs) | MEASURED / ESTIMATED | M (649 test files write `#!` stubs) | Low-med | Ratchet lint |
| 7 | Our own call sites through a fork-free `cc_run` runner, a `resolve_bin` remap, and lints R2/R3 (scripts, hooks, launchd mains) | **≈7-9%** | ESTIMATED | M-L, worked down in census order | Med (164 env-seam sites; bash 3.2 empty-array trap) | Ratchet lint |
| 8 | Mach-O entries for names that code we don't control calls: `~/.claude/bin/it2` (Claude Code's team-pane call) and `cc-qos-exec` (names models type) | **≈1%** | MEASURED | S | Med (PATH-walker loop; the `qos-rewrite.sh:188` `-ef` check) | Low |
| 9 | Blanket in-place shim of every `~/.claude/bin` entry | **≤5.3%**, mostly overlapping rows 2, 4 and 8 | MEASURED route share | M | Med-high (explicit-interpreter callers fail with 126; deploy-parity checks) | Med. Only if ≥3% remains after rows 1-8 |
| 10 | Run the hermetic bats partition off-box on GitHub macOS runners | up to **22%** | MEASURED share | S-M | Med (changes the deploy evidence chain) | **Costs money** (private repo; workflow dormant since 2026-09-27). Operator call |
| 11 | Hook daemon, compiled hook dispatcher, exec-form hooks, the `if` field | **0 for the leak** (load only) | MEASURED (`daemon.md` E1-E2, C5) | M-high | n/a | Out of scope |
| 12 | Run portable suites in a Linux VM or container | unknown | unmeasured | L | High | High |
| 13 | Wrap Homebrew, npm, git hooks and uv entry points globally | **≤0.5%** | MEASURED | M | Med | **Reject** |
| 14 | Patched bash that handles `#!` itself | at most the 16.7% Homebrew-bash slice; `/bin/bash` (69.2% of callers) is protected by SIP | MEASURED caller split | L | High (a shell fork) | **Reject** |
| 15 | DYLD interposition, shebang-less stubs, polyglot scripts | n/a | SIP strips `DYLD_*`; CPython and posix_spawn do not fall back on ENOEXEC | n/a | n/a | **Reject** |
| 16 | Developer Tools exemption for kitty, or Gatekeeper off | unknown (my guess: 20-30% chance it helps) | INFERRED | XS | Weakens security | Diagnostic only |
| 17 | macOS 27 | ≈0 per exec | REPORTED (3 short tests) | n/a | Operator ruled no | n/a |

## 3. The recommended build

Each phase is one dispatched session. Phase 2 runs in `~/Development/agent-context-sync`, under that repo's own CLAUDE.md. Phase 1 can run in parallel with Phase 0. Phases 3 and 4 wait for test T-1's verdict on the trampoline.

**Phase 0: measure first.** One day, no repo change, at most 8 MiB of leak spent on tests.

- **T-0, the lineage test.** Run arm S (`leaf.sh` by path) and arm B (`/bin/bash leaf.sh`), 4 × 1,000 each, interleaved, in two places:
  - from a clean root: `open -n -a kitty --args /bin/bash <runner>`. Kitty started this way is a Mach-O whose parent is launchd (MEASURED: `ps -p 1881` → ppid 1);
  - from inside a session.

  Read the zone with one `zprint` snapshot per reading: `zprint | awk '$1=="data.kalloc.1024"{k=$7} $1=="cred"{c=$7} END{print k-c}'`. One snapshot varies by 9-39 elements between reads, against 479 for two separate calls (`measure.md` Critique). T-0 opens a window, so it needs the operator's OK.
- **T-1, the trampoline's own cost.** Compare arm L (trampoline → leaf) with arm B over at least 8 pairs. Neither arm runs a `#!` exec, so this spends no leak budget. Today's measurement is L − B = +0.04 to +0.10 ± 0.11 per exec. It passes below 0.1.
- **Track the census tool as `scripts/kalloc-exec-census.sh`.** Today it lives at `/tmp/kalloc-exec-census.sh`, which a reboot deletes. Three changes:
  - one sudo call that bounds itself: `sudo -A gtimeout -s INT "$DUR" /usr/bin/eslogger exec`;
  - filter in the stream with `rg --line-buffered -F '"script":{'`, then `jq -c` keeping only time, script, caller, cwd, `args[0:3]` and the three env keys `BATS_TEST_FILENAME`, `PYTEST_CURRENT_TEST` and `CLAUDE_PROJECT_DIR`. That shrinks 26 GB an hour to a few MB and stops it storing secrets;
  - exclude `~/.cache/kalloc-longterm-ab/` and use the real window length.
- Run three census windows: a night, an ordinary afternoon and a land wave.

**Phase 1: point fixes in claude-infrastructure** (≈12% of the window, plus row 2's possible cut)

| Fix | File:line | Test |
|---|---|---|
| `/usr/bin/env bash "$KQ_BIN"`. Keep cc-kqwait's stale-binary guard; do not exec `current-$HOSTTYPE` directly | `bin/cc-await-ping:913` (assigned at `:853-854`; guard at `bin/cc-kqwait:135-141,257,261`) | bats checks argv; the census row reads 0 |
| `shasum -a 256` → `/sbin/sha256sum`, bare `shasum` → `/sbin/sha1sum`, with a `sha256sum` fallback for Linux CI. Cost: 2.5-2.8 ms CPU against 13.6-14 ms through perl | 60 files (11 call it by absolute path); `hooks/cc-permission-beacon.sh:193` compares the two strings directly; `hooks/waiting-recycle.sh:406,423,436`; `hooks/dispatch-assert.sh:163`; drop the perl path in `hooks/lib/shasum-direct.sh` | Fixture asserts identical bytes; lint refuses `shasum` |
| Run `cc-settings-parity` via `/usr/bin/env python3` | `migrations/0012:206`, `migrations/0036:52`, `scripts/c10-batch.sh:137` | Migration selftests |
| Launchd jobs: give the 2 `claude-accounts` perl relays an interpreter; turn the 22 by-path mains into `[their own shebang interpreter, script]` (migration 0070's rule) | `launchd/*.plist` + one migration | Extend `scripts/hook-shebang-lint.sh` to plists (lint R3) |
| Run `cc-in-kitty` via `/bin/sh` | `hooks/session-end.sh:104`; `~/.zshrc:705-706` (operator dotfile) | n/a |
| Try kitty's app binary before the Homebrew wrapper | `bin/cc-kitty-bin:34-37`, `bin/it2-kitty:173-176`, `bin/cc-resume-layout.sh:128` | bats |
| Start the session roots through their interpreter: `/usr/bin/env bash "$HOME/.claude/bin/cc-close-attrib"` | `~/.zshrc:504,508` (operator applies or approves); `lr-fire-resume.sh:1740` (`$wrap`, set at `:1181`); the caller of `reso-resume-one`; `bin/it2-kitty:1300` | `ps` argv unchanged; T-0 sizes the saving |
| Project hooks that migration 0070 never reached | `technical-analysis/.claude/settings.json` (3 hooks), `reso-management-app/.claude/settings.local.json` (1) | ≈0 today |

**Phase 2: agent-context-sync** (≈53% of this window, while its test campaigns run)

- **Vendor the trampoline** as `tests/support/exec_trampoline.c`. It is the parsing core of the `cc-shim` spec in `shim.md` §3, checked against Apple's xnu source.
  - A pytest session fixture builds it once with `cc -Os`. The compiler signs it ad hoc, and such binaries already run on this Mac (`cc-kqwait`).
  - Without a compiler, the fixture falls back to plain `#!` stubs.
- **Change the two stub helpers and `test_launcher.py:570`.**
  - Write each stub's body to `<dir>/../.<dir>-real/<name>`, and make `<dir>/<name>` a symlink to the trampoline.
  - The file name stays the same. Use symlinks, not hard links.
- **Why `launchctl-stub` is so large.** `scripts/install.sh:982` runs `LAUNCHCTL="${AGENTSYNC_LAUNCHCTL:-/bin/launchctl}"`, and `:984` polls it every `AGENTSYNC_WAIT_POLL_SECONDS` (default 3 s). The tests set 0.05 s. In production the target is `/bin/launchctl`, a Mach-O, so only the tests pay.
- **Hashing.** Move `scripts/install.sh:1051,4401` and `launcher/build.sh:57` to `/sbin/sha256sum`. `tests/test_deploy_pack.py:6524` pins the old string and must change with it.
- **Rehearsals.** Run the console script as `<venv>/bin/python -m agentsync`, and run `sb`, `run.sh` and `install.sh` through `bash`.
- **Test.** A differential test runs each stub once through the kernel and once through the trampoline, and asserts the same stdout, exit code and argv.

**Phase 3: infra test suites** (≈15-17%)

- **`tools/cc-shim/cc-shim.c`** implements the `shim.md` §3 spec, plus the fixes its critique asked for:
  - refuse a file with no newline in its first 512 bytes;
  - resolve `env NAME` from the caller's PATH at run time;
  - guard against the same process re-executing itself more than 16 times.
- **`tools/cc-shim/build.sh`** builds into `~/.cache/cc-shim/<sha16>-<arch>/`, links it as `~/.claude/libexec/cc-shim`, and runs `--selftest`. It follows the same cache layout as `bin/cc-kqwait:286-299`. Keep one binary at one fixed path, so macOS's security check stays cached.
- **Vendor bats-core 1.13.0** under `vendor/bats-core`, and put `"$BASH"` in front of the six internal calls: `bats-exec-file:236`, `bats:517,522`, `bats-exec-suite:141,314,323` (MEASURED by grep). `bin/cc-bats` runs the vendored copy.
- **`tests/lib/cc-stub.bash`** provides `cc_stub DIR NAME BODY`, falling back to a plain `#!` stub when `$CC_SHIM` is unset. Convert test files in census order: `boot-resume` 1,387, `boundary-handoff-forks` 898, `ship-land` 751, `bash-hook-trims-forks` 561, `autonomy-sweep` 445, `accounts-board` 413, then the next six. The top 12 files hold 5,781 of 7,352 bats `#!` execs.
- **Lint R4** is a ratchet: no new inline `#!` stubs, against a baseline of 649 files.
- **Tests.** `tests/cc-shim.bats` checks the shim against the kernel's own behaviour:
  - shebang forms: `-e`, `env`, CRLF line endings, lines of 511, 512 and 513 bytes, no newline, `#!` alone;
  - failure cases: a missing interpreter, an interpreter that is itself a script, no +x, a dangling `-real` link;
  - a rebuild while 10,000 execs run.

  Add `tests/cc-stub.bats` alongside it.

**Phase 4: our own call sites, and Mach-O entries for outside callers** (≈8%)

- **`scripts/lib/cc-run.sh`** provides `cc_run` and `cc_argv`, plus a Python version for the 25 subprocess sites.
  - It is fork-free and safe on bash 3.2: it reads line 1 with `read -r` and execs the interpreter. A Mach-O target passes through unchanged.
  - Use `${a[@]+"${a[@]}"}` for arrays that may be empty under `set -u`.
  - It adds no exec, unlike the trampoline's +3.5 ms, so it is the right tool on hot paths.
- **`scripts/lib/cc-common.sh:35` `resolve_bin`** maps `<repo>/bin/<name>` and `.bin-real` candidates to the runner.
- **Lint R2, `scripts/exec-form-lint.sh`,** sits beside the HOOK SHEBANG arm in `scripts/ship-land.sh:3907`.
  - It flags a tracked `#!` file run by path, including through `exec`, `timeout`, `gtimeout`, `nohup`, `taskpolicy`, `env`, `xargs` and `find -exec`. At least 6% of `#!` execs come through relays like these.
  - Work down the 402 static call sites in census order.
- **Mach-O entries for outside callers.**
  - Make `~/.claude/bin/it2` a Mach-O; Claude Code itself calls it.
  - Rewrite `cc-qos-exec` as a Mach-O.
  - Patch `bin/cc-qos-exec:62`, `bin/cc-bats` and `hooks/qos-rewrite.sh:188` to skip the shim when they walk PATH.
- **Do not build the blanket `~/.claude/bin` shim** unless the census still shows at least 3% on that route.

**Phase 5: the loop that keeps it fixed**

- **Target:** the 7-day median rate per boot stays at or below 0.30 GiB/day.
  - The inputs already exist and need no root: the slope in `kalloc-zone.state` and `scripts/kalloc-leak-rate.sh` (growth per Bash call).
  - It breaches when the 24-hour slope passes 0.45 GiB/day, or growth per Bash call passes 1.5x the last boot's.
- **On a breach**, file one operator row that carries the census command:
  `cc-backlog needs … --class needs-human --run "bash scripts/kalloc-exec-census.sh 600"`.
- **After each census**, the summary ranks the sources and drafts lint rows for any new path above N execs per 10 minutes.
- **Optional, the operator's call:** a root LaunchDaemon that runs the bounded census weekly.
- **Keep the safety net** as it is: the zone alarm, plus rebooting on the forecast under ruling `95563f6aa4dc` (authrestart timed from the zone alarm).

**Expected rate after each phase** (ESTIMATED; cumulative cut applied to 0.93 GiB/day)

| After | Cumulative cut | GiB/day | Days to the 20 GiB ceiling |
|---|---|---|---|
| today | n/a | 0.93 | 21 |
| Phase 1 | ≈12% (+17-44% if T-0 confirms the lineage effect) | ≈0.82 (≈0.5 with it) | 24 |
| Phase 2 | ≈65% | ≈0.33 | 61 |
| Phase 3 | ≈81% | ≈0.18 | 111 |
| Phase 4 | ≈89% | **≈0.10** | 200 |

On days when agent-context-sync runs no test campaigns, the starting rate is about 0.4 GiB/day, and Phases 1, 3 and 4 carry the cut.

## 4. What stays out of reach: the kernel

- **Where it happens.** The kernel takes its interpreter branch only for a `#!` image. That branch sets `ip_scriptvp`, which every MAC policy's credential-label update receives (SOURCE: xnu-11417.140.69 `bsd/kern/kern_exec.c:2394-2441,6736-6744,6826-6845`; `kern_credential.c:4364-4377`).
- **Which code allocates.** `AppleSystemPolicy::credLabelUpdateExecve` allocated 801 times against 1 in a test (REPORTED: willmcginnis, SIP-off 26.6.2 VM, #66020). On 15.8.1 this is INFERRED.
- **Why we can't patch it.** AppleSystemPolicy is closed source inside the sealed boot kernel collection, and SIP plus the sealed system volume block patching or loading anything beside it.
- **No setting turns it off.**
  - The MAC enforce sysctls are read-only (`security/mac.h:104-110`).
  - None of AppleSystemPolicy's 19 sysctl entries switches the hook off, and none counts script execs. So finding the source still needs root (MEASURED).
  - Boot-args need Reduced Security.
- **Leaked memory only comes back with a reboot.** The same `leaf.sh` run 3,000 times still kept 1.1 elements each.
- **The ceiling is fixed** at about 20 GiB, 20,955,520 elements (`scripts/capacity-alarm.sh:386`).
- **Upgrading only moves the leak.**
  - On 26.3 it lands in `data_shared.kalloc.1024` instead.
  - The only reported fix is 27.0, from three short tests.
  - Apple's notes for 27, 27.0.1 and the 27.2 RC list no such fix (MEASURED), so the operator's exit condition "a release that explicitly fixes it" will probably never be met.
  - A measurable condition could replace it: a 24-hour per-exec A/B on the candidate build reading under 0.05, on both zones, including a clean-lineage arm. That is the operator's decision.
- **Diagnostics, not fixes:** the Developer Tools exemption and turning Gatekeeper off.
- **A second, separate leak is dormant here.** An XNU error path, a failed hard-link path lookup, leaks a `vfs.namei` element (`bsd/vfs/vfs_cache.c:739-759,800,890`). Its log line `vn_getpath failed` reads 0 now (MEASURED); keep that count as an alarm input.

## 5. Upstream asks

1. **Apple Feedback** (operator task `21b1f5db2cd8`, needs the operator's Apple ID). Include:
   - the no-root repro (panic doc lines 89-94);
   - the 15.8.1 figures, 1.098 ± 0.104 against 0.007 ± 0.101, and 15.7.9's 0.94-1.07;
   - the call path `ip_scriptvp` → `mac_cred_label_update_execve` → `credLabelUpdateExecve`;
   - the 10-18 panic file;
   - a request for a 15.x backport.

   Post the FB number on #66020 so others can file duplicates against it. Correct `apple-feedback-compressor-panic-draft.md` first.
2. **bats-core PR:** call its internal scripts through `"$BASH"` at the 6 sites. Every bats user on a Mac pays about 1 element per test.
3. **A new, focused Claude Code issue**, not another comment on #66020. Ask for:
   - hooks and the status line to start a script's `#!` interpreter directly;
   - the docs' at least 5 exec-form examples that name a bare `.sh` to be fixed;
   - the bundled plugins in #95673 to put `bash` in front of their scripts.

   It is worth about 0 to us today (0 of 104 hooks are bare). It is insurance.
4. **A #66020 comment** with the 15.8.1 figure, the T-0 verdict (nobody has lineage data for 15.x yet) and the census method.
5. **Optional:**
   - Homebrew: install cask commands as symlinks, not `#!` wrapper scripts;
   - uv: a Mach-O launcher for console scripts on macOS.

## 6. Open questions, with conviction

| # | Question | Belief | What settles it |
|---|---|---|---|
| Q1 | Is the first `#!` in a clean lineage free on 15.8.1? | 50% (every 15.x measurement so far ran under a session already started by a `#!` script) | T-0 |
| Q2 | Does the trampoline retain under 0.1 per exec? | 80% | T-1 |
| Q3 | Do test harnesses stay above 50% of the daily `#!` stream? | 65% (the census hour ran at 3.8x the day's mean Bash rate; bins ranged 5-71%) | 3 more census windows |
| Q4 | Will agent-context-sync's test campaigns keep running for weeks? | 60% | That repo's plan |
| Q5 | Is there a leak source other than `#!` above 15%? | 20% (matched windows: 0.79-1.04 elements per `#!`) | Census against single-snapshot reads |
| Q6 | Does moving `$0` into `.<dir>-real/` break anything? | 85% no | T-2 and T-3 |
| Q7 | Is off-box CI worth the money? | operator's call | Price the macOS runner minutes |

My conviction in the recommendation:
- **85%** in the direction: one trampoline, call-site fixes, a lint, and the census loop; no daemon, and no wrapping of third-party tools.
- **75%** in the phase order.
- **75%** that the end state is at or below 0.3 GiB/day, and **55%** that it reaches about 0.1.

## 7. The census, re-derived (MEASURED)

**Method:** `rg -F '"script":{' exec.jsonl | python3 -I -c …` (10 s for 26.4 GB), classified on script path, cwd, the test env keys and the caller.

**Window:** 3,784 s, 34,157 real `#!` execs, 9.03 per second.
- The A/B harness's 36,038 execs are excluded.
- Over the bracketing zone readings, the leak excluding the A/B's ≈41.8k elements came to ≈7.7 elements/s, against 9.7 predicted.
- That ratio, ≈0.8, says `#!` execs explain nearly all of the leak.

| Class | Execs | Share | 10-min bins |
|---|---|---|---|
| A. agent-context-sync tests and rehearsals | 20,037 | 58.7% | 5-71% |
| B. infra bats (stubs 4,132, bats-core 1,820, repo copies 1,495, shasum 129) | 7,576 | 22.2% | 10-58% |
| C. infra production (main checkout 4,633, worktrees 956) | 5,589 | 16.4% | 9-36% |
| D. `/usr/bin/shasum` from our production code | 645 | 1.9% | 1-4% |
| E. Homebrew kitty wrapper | 132 | 0.4% | 0-1% |
| Everything else | 178 | 0.5% | n/a |

- **A, by name:** launchctl-stub 9,784, scutil 1,951, python 1,938, agentsync 1,784, shasum 1,323, uv 1,277. Bash was the caller for 18,369 of them.
- **C, top paths:** `cc-kqwait` 1,780, `cc-settings-parity` 781, `claude-accounts` 258, `cc-backlog` 205, `cc-in-kitty` 198.
- **C, by the path the caller used:** checkout absolute path 2,253, `~/.claude/bin` 1,822, worktree absolute path 694, `~/.claude/{hooks,scripts}` 541, relative 279.
- **B:** 7,352 ran under a bats test, and the top 12 files account for 79%.
- **Live state at 01:16 CDT:** eslogger has stopped. The zone holds 449,715 elements (0.43 GiB), the state file reads 0.93 GiB/day, and the projected ceiling date is 2026-11-12.

## 8. Axis claims the critiques overturned

- The in-place bin shim reaches about 3-5%, not all calls by name.
- A `~/.claude/bin/shasum` link misses agent-context-sync, which calls `/usr/bin/shasum` by absolute path.
- "On 15.x the first `#!` in a lineage leaks too" was never tested. Every arm ran under the `cc-close-attrib` `#!` root.
- The trampoline adds about 3.5 ms per exec under load, not 1 ms or less.
- No `env bash` script uses bash-4 syntax.
- The `#!` execs left on the hook path were mostly one session's 38-minute permission-prompt storm.
- The standing reboot rule already exists (`95563f6aa4dc`), and `--arm-restart` has landed (`3d9085132`).
- `ps` cannot tell a `#!` exec from `/bin/bash <path>`, so any regression guard has to be the census or the zone rate.