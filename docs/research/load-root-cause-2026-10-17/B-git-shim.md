# B-git-shim: `/usr/bin/git` (xcrun shim) and `xcodebuild -license check`

Axis B of the 2026-10-17 load root-cause study. Read-only investigation, 2026-10-17 02:30-02:50 local.
Machine: Xcode 26.3 selected (`xcode-select -p` = `/Applications/Xcode.app/Contents/Developer`).

## Verdict

`xcodebuild -license check` does **not** run on every `/usr/bin/git` call. It runs on an **xcrun cache
miss**, and the license entry in that cache is keyed by `DEVELOPER_DIR|HOME`. Every test that gives git a
fresh HOME and reaches git through the `/usr/bin/git` shim pays one miss. A miss costs one `xcodebuild`
fork+exec (about 620M instructions, 80 ms CPU, 24 MB RSS) **plus a full rewrite of the per-user cache
`xcrun_db`, which has grown to 90 MB** holding 481,410 per-HOME entries. 87% of those entries come from
pytest (agent-context-sync's autouse fresh-HOME fixture plus `gitops.git_executable()`, which prefers
`/usr/bin/git`) and 12% from bats. The miss rate measured now is about 1.2 per second.

Its share of the load is small: about 1-1.5% of CPU and about 3-4% of new pids. It is not the cause of a
load of 400-500. It does dirty an estimated 100+ MB/s of page cache on a machine with 1.1 GB free, which is
pure waste. Removing it needs no throttling: run the same Apple git binary without going through the shim.

## 1. Per-call cost (MEASURED)

### 1a. Wall time, 20 runs each (`bash /tmp/bgshim-time.sh`, wrapped in gtimeout, load ~400 at the time)

| command | ms/call |
|---|---|
| `/usr/bin/git --version` (shim, cache hit) | 37.1 |
| `/opt/homebrew/bin/git --version` (2.54.0) | 20.2 |
| `/Applications/Xcode.app/Contents/Developer/usr/bin/git --version` (2.50.1, direct) | 33.9 |
| `DEVELOPER_DIR=/Library/Developer/CommandLineTools /usr/bin/git --version` | 45.9 |
| `/usr/bin/true` (baseline: fork+exec under this load) | 27.6 |

Wall time is dominated by load noise, so the instruction counts below are the reliable figures.

### 1b. Instructions retired (`/usr/bin/time -l`, `bash /tmp/bgshim-smalldb.sh`, 3 runs each)

| case | instructions | wall |
|---|---|---|
| Xcode git direct | 26.9-27.1M | 0.00 s |
| Homebrew git | 33.3-33.5M | 0.00 s |
| shim, cache **hit** (90 MB db) | 96.8-99.3M | 0.01-0.02 s |
| shim, cache hit (private 1 KB db) | 96.2-97.7M | 0.01-0.02 s |
| shim, **miss**, private 1 KB db (shim process only) | 98.9-99.9M | 0.10-0.13 s |
| shim, **miss**, shared 90 MB db (shim process only) | 176.0-177.0M, +0.03 s sys | 0.15-0.26 s |
| `xcodebuild -license check` alone (the miss's child) | 604-694M, 0.04 user + 0.04 sys, 24.3-24.6 MB RSS, ~2,480 page reclaims | 0.09-0.11 s |

What this shows:
- **A hit** costs about 70M instructions on top of running git directly (97M against 27M), about 3.6 times
  the work. It adds **no fork**: the shim execs the real git in place. Measured with `bash /tmp/bgshim-exec.sh`:
  pid 11498 showed as `/Applications/Xcode.app/Contents/Developer/usr/bin/git hash-object --stdin` with no
  children. Lookups in the 90 MB db cost no more than in a 1 KB db, so the lookup is constant-time.
- **A miss** adds one fork+exec of `xcodebuild` (about 620M instructions) and, against the shared db, about
  77M more instructions and 30 ms of sys time to rewrite the whole 90 MB file. That totals roughly 720M extra
  instructions per miss, about 26 times a direct git call.
- The child was seen directly. `bash /tmp/bgshim-child.sh` started `/usr/bin/git --version` under a fresh
  HOME, and `pgrep -P` 20 ms and 50 ms later showed
  `/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -license check` as its child. This matches the
  lead's observation.

## 2. Why the license check runs: the xcrun cache key (MEASURED plus binary strings)

- The cache is `$(getconf DARWIN_USER_TEMP_DIR)xcrun_db` =
  `/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/xcrun_db`. `xcrun_verbose=1` prints
  `xcrun_db = '...'`. Setting `TMPDIR` does **not** move it: measured with `TMPDIR=/tmp/bgshim-tmpd/`, the
  lookup still resolved in the /var/folders db and nothing was created in the new TMPDIR.
- Its size is **90,361,669 bytes** at 02:35 and **90,517,386** at 02:47 (`ls -la`, `stat -f %z`). `strings -n 6`
  gives 962,948 lines, including **481,410 distinct `<DEVELOPER_DIR>|<HOME>||<timestamp>` keys**. All of them
  have `DEVELOPER_DIR` = Xcode and the value `1771622773` (`date -r` = 20 Feb 2026 15:26), which is the
  mtime of `Xcode.app/.../usr/lib/libxcrun.dylib` (`ls -la`: Feb 20 2026).
- `strings /Applications/Xcode.app/Contents/Developer/usr/lib/libxcrun.dylib` contains the format string
  `%s|%s|%s|<timestamp>`, `HOME`, `-license`, `check`, `%s/usr/bin/xcodebuild`, and the environment knobs
  `xcrun_db` ("environment variable 'xcrun_db' is not absolute, ignoring"), `xcrun_nocache`,
  `xcrun_negative_cache`, `xcrun_verbose`, `xcrun_log`.
- What the shim does, as reconstructed from the measurements: it looks up `DEVELOPER_DIR|$HOME||<timestamp>`.
  On a miss it spawns `xcodebuild -license check`, then inserts the key and rewrites the db. Every new HOME
  path is a new key, so per-HOME misses are **by design**. Earlier misses do not make later ones cheaper, and
  the cache cannot be made to "stick" for HOME paths it has never seen.
- **Each miss rewrites the whole file**:
  - The inode changed across one miss: 2025945442 became 2025945763 (`ls -li` before and after).
  - Three orphaned temp files sit next to it: `xcrun_db-7NY1iNZC` 76,468,224 B (Oct 16 00:19),
    `xcrun_db-OgVthk38` 81,768,448 B (13:15) and `xcrun_db-YBWAVqVx` 87,494,656 B (21:07). That is 245 MB, each
    nearly the full db size and an exact multiple of 4096, which means rewrites that were interrupted.
  - The Roasbeef/loom PR #609 (cited below) independently describes "rewrites the whole database through a
    temporary file and a rename".
  - `/usr/bin/time -l` shows 0 block outputs because the writes are deferred page-cache writes that the kernel
    flushes later. That is consistent with the lead's finding that per-process I/O looks small while device
    I/O is high.
- **Breakdown of the 481,410 HOME keys** (awk over the strings dump):
  - pytest `pytest-of-chrisren/...`: 419,198 (87%). Of these, 316,257 match `popen-gwN/homeN` (xdist workers,
    `tmp_path_factory.mktemp("home")`) and 57,659 match `pytest-N/homeN`.
  - bats `bats-run-*/test/N/home`: 56,491 (12%)
  - other /var/folders: 4,573; /tmp: 1,145; real /Users HOMEs: 2.
- **Miss rate**:
  - Sampled with `bash /tmp/bgshim-rate.sh` and `stat`: +22,921 B in 120 s (02:40-02:42), then +71,857 B in
    306 s (02:42-02:47, with load already down to about 50). That is 190-235 B/s.
  - Bytes per entry: in a private db, 3 misses added 336 B (112 B each, with short keys). Pytest keys are about
    60 characters longer, so about 170 B each.
  - That gives **about 1.1-1.4 misses/s now**. The 26-hour average from the temp-file sizes is
    13.9 MB / 26.3 h = 147 B/s, about 0.9 misses/s, or about 80k misses per day.
- **The fix the brief suggests does work**: with `DEVELOPER_DIR=/Library/Developer/CommandLineTools`, a
  fresh-HOME call spawned no child, wrote no `<timestamp>` key (grep of the db for that HOME found nothing),
  and retired 103M instructions on a miss against 106M on a hit (`bash /tmp/bgshim-clt.sh`). The Command Line
  Tools have no `xcodebuild`, so there is nothing to check. Section 4 explains why this is still not the
  recommended route.
- **Cost of a cold cache, from outside sources**: lapcat measured that after `xcrun_db` was lost, the first
  rebuild took more than 10 s with syspolicyd near 100% CPU (code-signature checks). syspolicyd's 467 cumulative
  minutes in the lead's top list are consistent with the 1/s exec of a fresh, signed `xcodebuild`. That
  contribution is not measured here, because it needs root.

## 3. Call sites (file:line)

### agent-context-sync (`/Users/chrisren/Development/agent-context-sync`, HEAD e2a8e8df)

Fresh HOME for every test:
- `tests/conftest.py:131-150`: `_isolate_home`, autouse. Calls `tmp_path_factory.mktemp("home")` and
  `mp.setenv("HOME", ...)` for **every test**. This produces the `popen-gwN/homeN` keys.
- `tests/conftest.py:202-215`: session repo fixture, which uses its own HOME.

Shim chosen explicitly:
- `src/agentsync/gitops.py:133-157`: `_usr_bin_git_usable()` and `git_executable()` (`functools.cache`)
  **prefer `/usr/bin/git`**. They are called at `gitops.py:187`, `governance.py:714`, `governance.py:742` and
  `ops/doctor.py:187`. As a result every in-process git call made by a test goes through the shim under that
  test's fresh HOME, and the first such call in each test is a miss.
- `src/agentsync/ops/doctor.py:181-196`: falls back to `/usr/bin/git`, then to `shutil.which("git", path=LAUNCHD_PATH)`.
- `scripts/install.sh:525-536`: `git_ro()` hardcodes `/usr/bin/git`. It is the only git call path in
  install.sh, with 8 call sites (`grep -c git_ro` = 9 including the definition), behind the
  `xcode-select -p` guard at `install.sh:489`.

Tests that call `/usr/bin/git` directly:
- `tests/test_install_oneshot.py:3489` and `:3511`
- `tests/test_launcher.py:861`
- `tests/test_deploy_pack.py:1835-1846`: `_gits()` runs `/usr/bin/git` and the CLT git deliberately, to cover
  more than one git version.

Hermetic PATH (resolves `git` to the shim):
- `tests/test_deploy_pack.py:404, 1162, 1218, 1595, 1945, 2184, 3054, 3073, 3109`
- `tests/test_install_oneshot.py:2483, 2612, 2836, 2853, 4289, 7681, 8458`
- `tests/test_launcher.py:649`
- `tests/test_ocr.py:522, 1380`
- `tests/test_setup_report.py:10784`
- `tests/test_deploy_pack.py:274-279`: `tmp_home_env()` keeps the caller's PATH but sets a fresh HOME.

Product launchd PATH:
- `src/agentsync/ops/launchd.py:44` and `:95`, `src/agentsync/ops/doctor.py:178`,
  `src/agentsync/convert/pandoc.py:330`, `src/agentsync/convert/ocr.py:170`. All use `/usr/bin:/bin...`.
  In production HOME stays the same, so these pay only the hit overhead.

Scale: 3,028 `def test_` (`git grep -c`). The pytest-N counter is at 8,889 runs
(`ls .../pytest-of-chrisren`).

### claude-infrastructure (this worktree)

- `bin/cc-bats`: the bats shim. Every bats invocation goes through it (header `bin/cc-bats:19`; exports at
  `:131` and `:271`), so it is a single place where a run-wide environment variable could be set.
- 827 bats files set `HOME="$BATS_TEST_TMPDIR/home"` (922 lines; `git grep -c`).
- 42 test lines put `/usr/bin:/bin` ahead of Homebrew in PATH, which makes `git` the shim. Examples:
  - `tests/automode-land-probe.bats:20`
  - `tests/boot-resume-skip-retired.bats:17`
  - `tests/cc-board.bats:30`
  - `tests/cc-husk-sweep-identity.bats:19`
  - `tests/cc-qos-exec.bats:24`
  - `tests/cc-research-probe.bats:55`
  - `tests/claude-accounts-providers.bats:51`
  - `tests/deploy-live.bats:2730`
  - `tests/hook-profile.bats:62`, `:101`
  - `tests/lr-reset-poller-inplace.bats:588`
  - `tests/offbox-partition.bats:212`, `:224`

  The full list is the output of
  `git grep -n -E 'PATH="?[^"]*:/usr/bin:/bin' -- tests | grep -v 'opt/homebrew/bin[^"]*:/usr/bin'`.
- Scripts that put `/usr/bin` before `/opt/homebrew/bin`, so their `git` is the shim. They run under the
  real HOME (hits only) unless a test drives them:
  - `scripts/browse-mirror-sync.sh:60`
  - `scripts/cloud-land-arm-diagnose.sh:38`
  - `scripts/cloud-lane-liveness.sh:108`
  - `scripts/devserver-gc-run.sh:16`
  - `scripts/permission-harvest-run.sh:25`
  - `scripts/research-kit/jobs/research-job.sh:15`
  - `scripts/worktree-gc-infra-run.sh:18`
- No non-docs file in claude-infrastructure calls `/usr/bin/git` by absolute path (`git grep -n '/usr/bin/git\b'`
  found nothing outside docs/). `~/.claude/shims` and `~/.claude/bin` contain no `git`.

## 4. Fixes, ranked

### P0-1: `gitops.git_executable()` resolves the shim's target once per process

**Change.** At `src/agentsync/gitops.py:145-157`, when `_usr_bin_git_usable()` is true on darwin, run
`/usr/bin/xcrun --find git` once (5 s deadline). If the result is an absolute executable path, return it.
Otherwise return `/usr/bin/git`. The existing `functools.cache` holds the result for the life of the process.
- `--find` returns exactly the binary the shim would have exec'd (MEASURED:
  `/Applications/Xcode.app/Contents/Developer/usr/bin/git`, 2.50.1), so the outcome is the same git.
- The same pattern was merged in Roasbeef/loom PR #609 for the same cache-miss problem.

**Effect.**
- In-process git calls in a test no longer go through the shim, so the per-test miss disappears: one miss per
  xdist worker process instead of one per test.
- Every git call saves about 70M instructions (97M down to 27M, MEASURED), in production as well as in tests.

**Risk.**
- git no longer inherits `SDKROOT` from the shim. agentsync's git calls run no hooks that need it.
- If `xcode-select` is switched under a long-running daemon, the cached path is stale until restart. To guard
  against that, re-resolve when the cached path stops being executable.
- `CONTRACTS.md:2943-2944` (docstring) needs updating.
- `tests/test_gitops.py:42` still passes (the path is absolute and runs).
  `tests/test_ops_doctor.py:259-262` monkeypatches the function, so it is unaffected.

**Tests-only alternative with no product change.** A session-scoped conftest fixture resolves
`xcrun --find git` under the **real** HOME (a cache hit), and the autouse `_isolate_home` does
`mp.setattr(gitops, "git_executable", lambda: REAL_GIT)`. This removes all in-process misses, including the
per-worker one, but `test_gitops.py:42` would then have to call `git_executable.__wrapped__`.

### P0-2: `install.sh git_ro` resolves once per run

**Change.** At `scripts/install.sh:525-536`, on the first `git_ro` call (already behind the `xcode-select -p`
check at `:489`), set `GIT_RO_BIN="$(/usr/bin/xcrun --find git)"`, falling back to `/usr/bin/git`.

**Effect.** 8 shim call sites become 1 xcrun call per install.sh process. In a fresh HOME there is still one
miss per process, but the later calls no longer pay the hit overhead.

**Out.** Inheriting a pre-resolved path through an environment variable. CONTRACTS deliberately drops
`DEVELOPER_DIR` and similar variables so that the environment cannot choose which tools run
(`CONTRACTS.md:6638-6640`).

### P1-3: run-scoped private `xcrun_db` for test runs

**Change.** `bin/cc-bats` (the single bats entry point) and an early hook in agent-context-sync's conftest
(for example `pytest_configure`, so xdist workers and subprocesses inherit it) export
`xcrun_db=<run tmp>/xcrun_db`.
- The knob exists in libxcrun.dylib (strings above) and is honoured. MEASURED: `xcrun_db=/tmp/bgshim-smalldb/db`
  created a 1,092 B db, the verbose log showed it in use, and misses against it retired 99M instructions
  instead of 176M.

**Effect.**
- Each remaining miss rewrites about 1 KB instead of 90 MB. That removes about 77M instructions and 30 ms of
  sys time per miss (MEASURED).
- At about 1.2 misses/s it removes **an estimated 100-110 MB/s of page-cache dirtying** (90 MB × rate).
- The shared db stops growing from tests.
- It does **not** remove the `xcodebuild` fork, so it complements P0-1 and P0-2 rather than replacing them.

**Risk.**
- The knob is undocumented. If Apple drops it, behaviour falls back to the default db, which is today's state.
- A cold private db costs one lookup round per run (2 calls warmed it in the measurement).
- lapcat reports a cold rebuild can trigger seconds of syspolicyd work. Not observed here: the small-db warm-up
  was 2 calls of roughly 0.1 s each.

### P1-4: compact the shared cache once, then on a size trigger

**Change.** Run `xcrun --kill-cache` (man xcrun: "-k, --kill-cache  Removes the cache. Causes all values to be
re-cached.") and delete the three orphaned `xcrun_db-*` temp files (245 MB).

**Effect.** Each miss's rewrite drops from 90 MB to a few KB until the db regrows. The current regrowth is
about 14 MB/day (MEASURED from the temp-file sizes) and will be much slower after P0-1 to P1-3.

**Event-driven, not reactive.** An existing periodic or boot job runs `xcrun -k` when `xcrun_db` exceeds a
threshold (for example 8 MB), and removes `xcrun_db-*` files older than one hour.

**Authorisation.** Needs no sudo, but it changes a system cache, so it is outside this read-only brief and
needs the lead's or operator's approval.

**Risk.** One cold rebuild (seconds of syspolicyd according to lapcat).

### P2-5: hermetic bats PATHs keep Apple git without the shim

**Change.** `bin/cc-bats` creates a run-scoped directory holding `git -> $(xcrun --find git)` and exports it,
for example as `CC_BATS_GITBIN`. The 42 hermetic `PATH="$stub:/usr/bin:/bin"` sites opt in by putting it ahead
of `/usr/bin`. Because it is the same Apple git binary, the outcome is the same.

**Effect.** Removes most of the 12% of misses that come from bats.

**Why P2.** It edits many files for about 12% of misses, and P1-3 already takes the I/O half of those misses
off with no per-test edits.

### Rejected options

- **Resolve git once from the host PATH, which gives Homebrew 2.54.0.** This changes the git version under test.
  The product targets Apple git (`/usr/bin/git`), and the suite deliberately measures differences between git
  versions (`tests/test_deploy_pack.py:1835-1846`: M69 behaves differently on 2.39.5, 2.50 and 2.54). The
  result would not be equivalent. Resolve the shim's own target with `xcrun --find git` instead.
- **`DEVELOPER_DIR=/Library/Developer/CommandLineTools`.** MEASURED to remove the license check entirely, but:
  - git drops to **2.39.5 (Apple Git-154, Dec 2024)**.
  - `pkgutil --pkg-info=com.apple.pkg.CLTools_Executables` reports "No receipt", so this CLT copy is orphaned
    and Software Update will not update it.
  - CLT has no `xcodebuild`, which matters for the OCR and speech Swift build paths.
  - The behaviour is not equivalent.
- **`sudo xcode-select -s /Library/Developer/CommandLineTools`.** It has the same problems machine-wide and
  removes Xcode as the active developer directory for every tool. Rejected, operator-only.
- **Making the per-HOME license entry stick.** The key includes `$HOME` (MEASURED), so a new HOME can only be a
  hit if HOME paths are reused, which weakens test isolation. Pre-seeding keys for future paths would mean
  predicting `pytest-N` and `bats-run-*` names and writing Apple's undocumented binary format.
- **`xcrun_nocache` or `-n`.** They force a refresh, which is more work.
- **Pointing `TMPDIR` elsewhere.** xcrun ignores it (MEASURED).
- **Throttling the gates or demoting their QoS.** Out of scope under the operator's constraint.

## 5. Machine-wide savings (ESTIMATED from the measurements above)

| item | today | after P0-1 + P0-2 + P1-3 |
|---|---|---|
| `xcodebuild` fork+exec | ~1.2/s (db growth ÷ ~170 B/entry) ≈ 3-4% of the lead's ~30 new pids/s | about one per xdist worker per run, plus one per install.sh or CLI subprocess under a fresh HOME. Most of the 87% pytest share is removed. |
| CPU | ~1.2 × (80 ms xcodebuild + 30 ms rewrite) ≈ 0.13 cores ≈ 1.3% of 10 cores | most of it removed |
| page-cache dirtying from db rewrites | ~1.2 × 90 MB ≈ 100-110 MB/s ≈ 7-8% of the 1.4 GB/s iostat | about 0 (private KB-sized dbs) |
| per git call through the shim (hit) | 97M instr | 27M instr (-72%), no change in forks |
| /var/folders disk | 90 MB db + 245 MB orphaned temp files | KB (after P1-4) |

Shim calls exec the real git in place, so the fork saving comes only from the `xcodebuild` children, not
from the git calls themselves.

## 6. Open questions

- The machine-wide rate of shim **hits** could not be determined: counting them needs dtrace or fs_usage,
  which need root. A single `ps` snapshot at 02:45 caught no shim process.
- The device bytes actually flushed per rewrite could not be measured without root (fs_usage). They are
  estimated from the file size and the inode change.
- It is unknown whether concurrent rewrites lose entries (last writer wins on rename), causing repeat misses
  for the same HOME. The dump has no duplicate keys, which the format would hide anyway.
- The syspolicyd and amfid cost per `xcodebuild` exec was not measured.
- Why Apple keys the license entry by HOME is undocumented. A plausible inference is that `xcodebuild` reads
  per-user preferences.
- Whether `xcrun -k` here truncates the db or rebuilds it, and how long the first cold lookup takes, was not
  run, because that would mutate the cache.

## Side effects of this investigation

About 20 `<timestamp>` keys for `/tmp/bgshim-*` HOMEs were added to the shared `xcrun_db`. Small dirs and
scripts were left under `/tmp/bgshim-*`. No process was signalled and no test or reaper was run.

## Sources

- Roasbeef/loom PR #609, "run jailed git through the host-resolved binary on macOS": `/usr/bin/git` shim,
  `xcrun_db` keyed partly on HOME, whole-file rewrite via temp file and rename, fix is a one-time
  `xcrun --find git`. https://github.com/Roasbeef/loom/pull/609
- markjoyeuxcom/parley PR #63, "resolve the real Git outside the read guard instead of the xcrun shim": with a
  cold cache and full Xcode, the shim forks xcodebuild. https://github.com/markjoyeuxcom/parley/pull/63
- lapcat, "Why Xcode tools are slow after reboot": `xcrun_db` in the temp dir, emptied on reboot, a cold
  rebuild drives syspolicyd. https://lapcatsoftware.com/articles/xcrun.html
- `man xcrun`, for `-n/--no-cache` and `-k/--kill-cache`.
