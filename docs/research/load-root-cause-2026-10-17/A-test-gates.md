# Axis A: test-gate oversubscription (agent-context-sync pytest gates, claude-infrastructure bats gates)

Date: 2026-10-17, 02:33-02:50 CDT (07:33-07:50Z). Read-only. I killed nothing, ran no tests and edited nothing
except this file. Every number is tagged MEASURED (with the command) or ESTIMATED (with the method).

## Verdict

The four concurrent `-n auto` gates are a real throughput loss, but most of the waste is not the worker count.
Three things together cost more machine work than they buy:

1. **Every full suite runs at least twice per lane, and sometimes three times.** The lane runs its gate
   (`/tmp/r13{p,b,rb}-gate.sh`, full suite, unlocked, so four ran at once). Then the land runs the full gate again
   under `lockf /tmp/b13-r13-land.lock` after a rebase. The lead's land command runs `test_deploy_pack.py`
   twice. Runs killed by compressor-sentinel are restarted from zero.
2. **Each test makes a per-HOME miss in the xcrun cache.** `_isolate_home` gives every test a new HOME, and
   every `/usr/bin/git` call goes through the xcrun shim. That cache is now 90 MB, and 87% of its HOME-keyed
   entries are pytest tmp HOMEs. On each miss xcrun writes the whole file again and replaces it.
3. **Oversubscription costs more than linear.** About 40 xdist workers each drive bash/git process trees, with
   the vnode table full and a compressor in the tens of GB. Four suites took 29-40 min each, while one suite on
   this machine takes 6-10 min. The memory pressure then triggers sentinel kills, which waste more runs.

Machine work drops the most when the duplicate full runs are removed first (R3, R4, R5) and the xcrun churn is
fixed (R1). The cores can then be shared through a crash-safe, test-granular token pool (R2) instead of 4×10
free-running workers. None of these lowers any session's priority. Each one either removes duplicate work or
reaches the same verdict with fewer forks or bytes.

## Q1. How long the suite takes, and the oversubscription penalty

### Measurements

| Run | Tests | pytest wall | Conditions | Source |
|---|---|---|---|---|
| 2026-10-06 local `-n auto` | 2089 | 114-139 s | load 37-130 | `docs/plans/test-suite-performance.md` (agent-context-sync) "Measurements" table |
| 2026-10-06 local serial | 2089 | 661 s | load 21 | same |
| 2026-10-08 local `-n auto` | 3322 / 3332 | 263.56 s / 266.72 s | unknown load | MEASURED: `grep 'passed.* in' ~/.cache/agentsync-bring-back/gate-b10.log gate-b11.log` |
| 2026-10-14 05:20 local `-n auto` | 4258 | 554.55 s (9:14) | early morning | MEASURED: `/tmp/r9d-pytest.log` last summary line |
| CI `macos-15`, 3 vCPU, 2026-10-17 run 39012861804 | 4601 | 893.22 s (14:53) | dedicated runner | MEASURED: `gh run view 39012861804 --log \| grep passed` |
| **4 concurrent lane gates, 2026-10-17 00:15-00:55 CDT** | 4602-4617 | **1762 s, 1858 s, 2044 s, 2402 s** (29:22, 30:58, 34:04, 40:01) | load ~365-520 (lead) | MEASURED: last line of `/tmp/r13d-pytest5.log`, `/tmp/r13p-pytest4.log`, `/tmp/r13b-pytest4.log`, `/tmp/ra-pytest4.log` |
| 2026-10-16 13:29 / 14:24 lane gates | 4483 / 4492 | 2344 s / 2157 s | concurrent lanes | MEASURED: `/tmp/r12b-pytest.log`, `/tmp/r12e-pytest2.log` |
| One land gate (r13-d, pid 24945), 2026-10-17 02:25-02:39 | ~4600 | ~13-15 min | load 73-140, one other suite starting | MEASURED: `ps -o etime -p 24945` showed 12:58 at 02:38; the pid was gone at 02:40 |

The suite has grown from 1499 to 3028 `def test_` functions since 2026-10-06 (MEASURED: `grep -cE '^def test_|^    def test_'`
over `tests/*.py` at HEAD and at `455c67a7`; 4601 collected items with parametrisation). `scripts/install.sh` grew
from 1821 to 5104 lines (MEASURED: `git show 455c67a7:scripts/install.sh | wc -l`; `wc -l`).

### Estimates

- **Solo wall on this machine today: 6-10 min** (ESTIMATED). Scaling the 2026-10-08 measurement linearly
  (265 s × 4601/3330) gives about 366 s. The 2026-10-14 run at 4258 tests took 555 s, which scales to about
  600 s. I could not get an idle-box run, so this stays a range.
- **CPU work per suite: about 1650-2700 core-seconds** (ESTIMATED). The upper bound is 3 CI vCPU × 893 s. The
  lower bound is the 2026-10-06 per-file seconds/test × today's per-file test counts.
- **Oversubscription penalty.** The four concurrent gates gave 4 suites in about 40 min, roughly 6 suites/hour.
  If the same suites ran back to back at the solo wall they would finish in 24-40 min, 6-10 suites/hour. So
  concurrency gave between 0% and 40% less aggregate throughput (ESTIMATED from the two measured rows above).
- **Per-session wall time.** Each concurrent gate took 29-40 min, mean 33.6 min. A queue that is first in,
  first out at the test level would finish them at k × (6-10) min, mean 15-25 min (ESTIMATED). With that queue,
  even the last gate finishes no later than today's mean.
- **Waste from kills, MEASURED.** Two of those lanes' previous runs (`/tmp/r13d-pytest4.log`,
  `/tmp/ra-pytest3.log`, born 00:05:38/00:05:57, last write 00:14:59 CDT) died with xdist
  `OSError: cannot send (already closed?)`. `/tmp/claude-compressor-sentinel.stderr.log` line 1436 reads
  `2026-10-17T05:14:53Z ... KILL-ESCALATE reason=retrip-over-debt killed=4`, which is 6 s earlier (05:14:59Z =
  00:14:59 CDT). Two runs of about 9 min each were thrown away and restarted, and the restarts are why all four
  gates overlapped from 00:15. Line 1433 also shows `held=17` SIGSTOPped processes from 05:06:58Z to 05:09:38Z.
  Memory pressure from oversubscribed gates is therefore paid twice: in thrash, and in runs that are killed and
  run again.

## Q2. What dominates the cost of each test

### "install.sh --report-only calling itself" is not recursion

`scripts/install.sh` never runs itself again. `grep -nE '(bash|exec|/bin/bash)[^#]*("\$0"|\$SELF_FILE|\$SELF\b|BASH_SOURCE)'`
finds nothing; `SELF_FILE` is only read by awk (`install.sh:808`, `:1258`). The chains in ps are bash **forks**.
A forked subshell keeps the parent's argv, so `$(...)`, `( ... )`, `>(tee ...)` and every pipeline stage show
up as another `install.sh --report-only`. The file has 398 `$(` command substitutions, 15 process substitutions
and about 617 ` | ` pipes (MEASURED: `grep -o` counts). Per call site:

- `install.sh:1012-1025` `with_timeout`: a subshell plus `sleep`, for each of 11 call sites.
- `install.sh:1031-1046` `with_progress`: `sleep 0.2` polling.
- `install.sh:1137-1144`: `exec > >(tee -a ...)` twice per run, which are the paired `tee` processes in ps.
- The launchd wait loop, `install.sh:4940-4994`: 8-10 command substitutions plus the launchctl stub per
  iteration. The tests poll it at `AGENTSYNC_WAIT_POLL_SECONDS=0.05` (`tests/test_install_oneshot.py:278`),
  which is 20 iterations/s.

A ps snapshot shows a 5-deep chain, pids 23694→25476→25490→25499→25503→25505 (MEASURED:
`ps -axo pid,ppid,... > /tmp/agtest-ps.txt`). One running gate had 69 descendant processes: 21 bash, 14
`(bash)` forks, 10 Python workers, 4 tee, 4 awk and others (MEASURED: awk ancestry walk over the same snapshot).

### Which tests are expensive

- `test_install_oneshot.py` has 277 test functions (81 on 2026-10-06) and 351 `install_sh(` calls. Each runs
  the real 5104-line installer under `/bin/bash` 3.2 (`tests/test_install_oneshot.py:300-317`) with
  `PATH={stubbin}:/usr/bin:/bin:/usr/sbin:/sbin` (`:273`).
- `test_setup_report.py` grew from 58 to 267 tests, `test_cycle.py` from 22 to 188, and `test_deploy_pack.py`
  from 56 to 144 (MEASURED: per-file `grep -c` at HEAD and at 455c67a7).
- On 2026-10-06 the cycle tests' time was the product's own git work: 13 `run_cycle` calls made 265 `git`
  subprocesses, 5.9 of 11 s (`docs/plans/test-suite-performance.md`, "Where the serial ... goes").

### The git shim and the xcrun cache are a large per-test cost that the suite does not need

- `src/agentsync/gitops.py:133-149`: `git_executable()` **prefers `/usr/bin/git`**, the xcrun shim.
  `src/agentsync/setup_report.py:3445` hard-codes it, and the install.sh tests' PATH puts `/usr/bin` first
  after the stubs.
- **Shim cost on a cache hit, MEASURED with `/usr/bin/time -l`.** `/usr/bin/git --version` retires 96.5-102.3M
  instructions. Calling `/Applications/Xcode.app/Contents/Developer/usr/bin/git --version` directly retires
  27.0M, the same binary at 2.50.1 (Apple Git-155). The wall times, timed over 10 calls each, were 76 ms vs
  18-19 ms at load about 135.
- **The cache is keyed by HOME.** `$(getconf DARWIN_USER_TEMP_DIR)xcrun_db` is 90,434,510 bytes (MEASURED
  `ls -la`), and three more 76-87 MB `xcrun_db-XXXX` temp copies sit beside it. A strings dump of it made by a
  sibling lane (`/tmp/bgshim-xcrundb-strings.txt`, 02:36) has 481,410 `devdir|HOME||<timestamp>` keys. Of these,
  **419,198 (87%) are pytest tmp HOMEs** and most of the rest are claude-infrastructure postland bats HOMEs
  (MEASURED: `grep -c '<timestamp>'`, `grep -c pytest-of`). `_isolate_home` (`tests/conftest.py:133-151`) makes
  a new HOME for every test, so a test's first shim call is a miss every time.
- **A miss rewrites the whole file.** `strings .../usr/lib/libxcrun.dylib` lists
  "couldn't replace cache file '%s' with newly written file '%s'", "couldn't map new cache file", and
  "lookup resolved with 'xcodebuild -find'". A loop of `stat -f '%i %z'` taken every 5 s over 30 s shows a new
  inode in all 7 samples and growth of 8,040 B (MEASURED). That is about 1.4 new HOMEs per second at about
  188 B per HOME (90.5 MB / 481K). At roughly one 90 MB rewrite per miss, that is **about 125 MB/s of cache
  rewrite with one gate running**, and about 4 times that with four (ESTIMATED). The new file is written
  through mmap, so the write-back is charged to the kernel. That fits the lead's observation that the 1.4 GB/s
  of iostat traffic is mostly root/kernel and only about 5 MB/s per user process. This is a hypothesis, and
  `fs_usage` (sudo) would confirm it.
- **A miss also spawns `xcodebuild`.** The 2026-10-12 eslogger trace
  (`docs/research/load-hook-timeouts-2026-10-11/O5-EXEC-TRACE.md:7`) counted 5,675 `git`, 771 `xcodebuild`
  and 227 `xcode-select` execs per 30 s from these worktrees. agent-context-sync tests were **about 84% of all
  execs on the machine** at that time.
- **Rejected: `DEVELOPER_DIR=/Library/Developer/CommandLineTools`.** That git is 2.39.5 (Apple Git-154), not
  2.50.1 (MEASURED `--version`), so it would not be the same outcome. `DEVELOPER_DIR` set to the Xcode
  developer dir saves nothing on a hit: 98.3M vs 102.3M instructions (MEASURED).

### Memory

Gate workers had 52-204 MB RSS each (MEASURED, ps snapshot of the 10 workers under pid 24945), so 40 workers
hold roughly 4-5 GB. The lead measured the compressor at 21 GB, and the sentinel kills followed (above).

## Q3. Designs that reach the same verdict with less machine work

### R1 (P0). A per-worker xcrun cache in tests

Set the `xcrun_db` environment variable to an absolute per-worker path, `tmp_path_factory.getbasetemp()/"xcrun_db"`.
Put it in `_isolate_home` (`tests/conftest.py:133-151`) and in every explicit `env={...}` dict that drops
`os.environ`: the `env` fixture at `tests/test_install_oneshot.py:263-283`, 15 `env = {`/`env={` sites in that
file, `tests/test_deploy_pack.py:404,1162,1218,1595,1945` and `tests/test_install_next_line.py:42`.

- **Same outcome:** the same shim resolves the same binary, and only the location of the lookup cache moves.
  libxcrun honours the variable when it is absolute ("environment variable 'xcrun_db' is not absolute,
  ignoring").
- **Effect:** each miss rewrites a file of a few KB instead of 90 MB. The user's main cache stops gaining
  about 4K entries per suite, so every shim call on the machine (git, cc, make, xcrun from every session and
  daemon) stops paying for a cache that keeps growing.
- **What it does not remove:** the per-new-HOME `xcodebuild` spawn.
- **Operator option:** `xcrun --kill-cache` once afterwards resets the 90 MB file. That writes user state, so
  it is the operator's call.
- **claude-infrastructure:** its bats HOMEs are the other 13% of the entries, so the same variable belongs in
  its bats test-HOME setup.

### R2 (P0). A machine-wide, crash-safe, test-granular token pool instead of 4×10 free-running workers

The pool is `~/.cache/test-slots/slot.{0..T-1}`, where each slot file is held with `fcntl.flock`. A
`pytest_runtest_protocol` hookwrapper in `tests/conftest.py` takes a free slot (non-blocking scan, then a
blocking `flock` on one slot) around each test's setup/call/teardown, and releases it afterwards.

- It is active only when `PYTEST_XDIST_WORKER` is set, so a single-test debug run is unchanged.
  `AGENTSYNC_TEST_SLOTS=off` turns it off.
- `AGENTSYNC_TEST_SLOT_HELD=1` is exported to children so a nested run never waits on its parent's token.
  No nested pytest exists today (MEASURED: `grep -ln '"pytest"\|pytest.main' tests/*.py` finds only
  test_ops_launchd's text).
- The kernel releases a flock when its process dies, so a sentinel SIGKILL cannot leak tokens. The FIFO
  protocol of the GNU make jobserver loses a token on every kill, and the sentinel kills processes (above).
- Keep `-n auto`. Workers that wait for a slot cost RSS only.
- **The throughput argument the brief requires:** measured concurrency gave 4 suites in about 40 min. A
  work-conserving pool approaches the back-to-back solo rate, 4 × 6-10 min = 24-40 min, so aggregate is equal
  or better and mean completion drops from 33.6 to about 15-25 min (ESTIMATED). The pool is work-conserving:
  a lone gate gets all T slots, so a solo gate is not slower. That is the difference from the static cap
  rejected below.
- **Load effects:** live process trees drop from up to 40 to at most T. That cuts compressor pressure and
  vnode churn, and with them the sentinel kills that wasted about 18 min of a gate's work at 05:14Z.
- **Start at T = hw.ncpu = 10**, then measure.
- **R1 and R2 together:** R1 makes each slot cheaper. R2 bounds the number of slots in use at once.

### R3 (P1). A gate verdict cache keyed on the tree, with in-flight de-duplication

Add one repo script, for example `scripts/gate.sh`, run by the CLAUDE.md gate list (`CLAUDE.md:7-24`). It
would replace the ad hoc `/tmp/r13*-gate.sh` and `/tmp/ra-land-gate.sh` copies.

- **Key:** `git rev-parse HEAD^{tree}`, which covers uv.lock, the tests and the scripts, plus a salt of
  gate.sh's blob and the tool versions (python, uv, bash, `/usr/bin/git`, pandoc, node, `sw_vers`). The cache
  is off when `git status --porcelain` is non-empty.
- **Store:** `$(git rev-parse --git-common-dir)/gate-verdicts/<key>`, shared by every worktree. Green only,
  each entry restating its own key. This is the invariant set already proven in claude-infrastructure's
  `scripts/lib/gate-memo.sh:23-36`.
- **In-flight de-duplication:** `flock <key>.lock`. A second worktree at the same tree waits for the first and
  reads its verdict instead of running a second full suite at the same moment.
- **Where hits happen:** a land rebase that was a no-op (lane already on origin/main), the lead re-gating a
  lane tip, and a re-run after a sentinel kill when the green steps can be skipped. Landed lanes sit at main
  commits: r13-p=b28a873d, r13-rb=44360797, r13-e=7b51f3cf, r12-d=579261da (MEASURED
  `git -C <wt> rev-parse --short HEAD`, all main SHAs).
- **Hit rate:** unknown. Log keys for a round before claiming a number.

### R4 (P1). Stop running test_deploy_pack twice in the land command

The lead's land command (live pid 30634, inside `lockf /tmp/b13-r13-land.lock`) runs
`pytest -n 4 tests/test_deploy_pack.py` and then the whole suite with `-n auto`. The second run includes the
first.

- **Change:** keep the fail-fast subset and pass `--deselect`/`--ignore=tests/test_deploy_pack.py` to the
  full run. The same tests, on the same tree, in the same gate, give the same verdict.
- **Effect:** saves test_deploy_pack's share on every land. That is 144 of 3028 test functions with 100
  subprocess or installer sites, about 5-10% of the suite (ESTIMATED from counts).
- Put it in R3's script so it stops being retyped.

### R5 (P1). Lane gates select affected tests; the land gate stays the full suite (it already is serialized)

Today each lane runs a full unlocked gate. Four of them overlapped on 2026-10-17, and then the land repeats
the full suite under the land lock on the rebased tree. The lane's full verdict is superseded every time, and
`COMMON12.md:51-52` says that in rounds 8-12 "every queued push after the first was rejected ... re-run the
gate".

- **Proposal:** the lane pre-gate runs the static checks plus the test files mapped from the changed paths.
  The mapping is conservative: any change under `scripts/install.sh` or `src/agentsync/{cycle,gitops,publish}`
  selects every test that references it, and anything unmapped selects the full suite. The land gate under
  the lock stays exactly as it is.
- **Same verdict for what lands:** the land gate is unchanged.
- **Faster lanes:** reaching land becomes queue wait plus one full suite, instead of a 30-40 min contended
  full suite plus the queue plus one full suite.
- **Prior evidence that touched-file tests catch the reds:** "over 8 full runs ... the full suite caught
  nothing the touched files' own tests missed" (`docs/plans/test-suite-performance.md`, facts list).
- **Not pytest-testmon:** see the rejections below.
- **Effect:** local full suites per lane drop from 2 or more to 1 or more, about 40-50% fewer full-suite
  core-seconds per round (ESTIMATED from the flow above).
- **Owner:** the workflow text is in `~/.cache/agentsync-bring-back/b13/lanes/COMMON12.md`, which is not a
  repo file, so the lead changes it.

### R6 (P2). Fewer poll forks in timeout-path installer tests

Tests that wait for a timeout, for example `tests/test_install_oneshot.py:461,475` with
`AGENTSYNC_WAIT_SECONDS=1`, poll at 0.05 s with 8-10 forks per iteration. Their wall time is fixed by
`WAIT_SECONDS`, so a 0.5 s poll in those tests alone keeps both the verdict and the wall time and removes
about 90% of their poll forks (ESTIMATED). Success-path tests keep 0.05 s.

### R7 (P2). Product: resolve the git shim once per process

`git_executable()` (`src/agentsync/gitops.py:145-149`, already `functools.cache`d) could return
`xcrun --find git` once per process instead of `/usr/bin/git`. It is the same binary, and a new launchd run
is a new process, so a later `xcode-select -s` still takes effect. Each shim call would save about 70M
instructions, measured at hit cost. This affects the product as well as the tests, so it is the
agent-context-sync owner's decision.

## Q4. Does the claude-infrastructure side decide parallelism or coordinate across sessions?

- **`bin/cc-bats`.** It demotes with `taskpolicy -c utility` (`bin/cc-bats:713-731`) and adds an admission
  rule that **refuses** with rc 75 when at least `CC_BATS_MAX_ROOTS` (default 2, `:465`) bats roots are live
  AND load/core is at least 2.0 (`:466`, `:626-690`). The registry is `~/.claude/state/bats-roots.d`. This
  coordinates across sessions only by demotion and refusal, which is the kind of mechanism the operator has
  ruled out. There is no jobserver or semaphore. No bats `--jobs` is used anywhere (MEASURED:
  `git grep -- '--jobs'` over bin/scripts/hooks/lib finds only cc-cloud and cc-memory-extract).
- **`scripts/ship-land.sh` `run_gate` (`:3418`).** The blob-keyed statics memo
  (`scripts/lib/gate-memo.sh:1-60`, store in the git common dir), affected-only "smoke" suites chosen by
  `gate-select.sh` under a wall budget (`run_smoke`, `:2464`), and an invariant of no bats under the land
  lock (`:2506`). Smoke suites run with `CC_BATS_MAX_ROOTS=0` (`:2343-2378`), which is safe because the land
  lock admits one land gate per repo. The full corpus belongs to the `postland-verify.sh` singleton
  (`run.lock.d`, cc-bats-exempt at `scripts/postland-verify.sh:191-224`).
  - So claude-infrastructure already uses three of the designs this axis recommends for agent-context-sync:
    a verdict memo, affected-only selection at land with the full run deferred to one singleton, and
    serialized land gates. Nothing coordinates **across repos**. A bats corpus and four pytest suites can run
    at once with no shared budget.
- **PYTEST_XDIST_AUTO_NUM_WORKERS=3.** Migration `migrations/0064-prompt-hook-timeout-and-pytest-cap.sh`
  (commit 870767fe8) would set it. It is **not applied**: `grep PYTEST_XDIST ~/.claude/settings.json
  ~/.claude-*/settings.json` returns nothing, and the live gates ran 10 workers (MEASURED).
- **R8 (P2).** Move cc-bats from refusal to the same flock slot pool as R2 (bats `--jobs` chosen from free
  slots), so that bats and pytest share one budget. Also apply R1's `xcrun_db` to its bats test HOMEs.

## Share of load

- **Execs:** about 84% of all execs on the machine came from agent-context-sync test runs (MEASURED
  2026-10-12, a 30 s root eslogger trace, O5-EXEC-TRACE.md:7). Today's ps is consistent: 40 of 82 Python
  processes were xdist workers (lead), and one gate had 69 descendants.
- **Load:** the 1-min load average was 365-520 with four full suites (lead). I saw 135 at 02:33 with one full
  suite plus one starting, and 43.9-73.7 at 02:40-02:48 with one 4-worker suite (MEASURED `uptime`). That is
  consistent with the gates being the majority of load during the episode. It does not prove it, because
  other processes changed over the same window.
- **Disk:** the xcrun cache rewrite is an ESTIMATED 125 MB/s per active gate. It is unconfirmed until
  `fs_usage` attributes the kernel write-back.

## Considered and rejected

- **The `PYTEST_XDIST_AUTO_NUM_WORKERS=3` static cap (migration 0064).** A lone gate would get 3 of 10 cores,
  about 3.3 times slower, which is a cap the operator has ruled out. R2's work-conserving pool does what it
  was for without slowing a solo gate.
- **nice, taskpolicy or QoS demotion, cc-bats-style refusal, sentinel kills.** The operator has ruled these
  out. The kills also measurably waste work (05:14:53Z: two gates of about 9 min each restarted).
- **One whole-suite FIFO lock across lane gates.** Not work-conserving: a suite's own tail and idle phases
  strand cores, and every lane would queue behind full suites. A pool at test granularity rebalances by
  itself.
- **The GNU make jobserver FIFO protocol.** Tokens leak on SIGKILL. xdist does not speak it either.
- **pytest-testmon.** It selects tests from coverage.py data, which sees only Python. The 351+ installer runs
  are bash run as subprocesses, and bash has no coverage, so a change to `install.sh` would deselect the
  tests that exercise it. Coverage of Python subprocesses also needs extra setup
  ([pytest-cov: subprocess support](https://pytest-cov.readthedocs.io/en/latest/subprocess-support.html);
  [pytest-testmon on PyPI](https://pypi.org/project/pytest-testmon/0.9.16)). That makes it unsafe here,
  unlike R5's conservative path map.
- **`DEVELOPER_DIR=CLT`.** A different git, so not the same outcome (Q2).
- **Shared synced-repo fixtures.** Already refuted: inode-keyed manifests read a copied tree as a mass delete
  (`docs/plans/test-suite-performance.md`, watch items).
- **"Fix install.sh's recursion".** There is no recursion; what ps shows is forks (Q2).
- **A merge-queue batch, one full suite for several lanes, bisecting on red.** The throughput gain could be
  larger, but intermediate commits on main would lose their own local verdict. That is a policy change for
  the repo owner, so I left it out of the recommendations.

## Source for the xdist knobs

[pytest-xdist: distribution](https://pytest-xdist.readthedocs.io/en/stable/distribution.html). `-n auto` uses
the number of physical cores. `PYTEST_XDIST_AUTO_NUM_WORKERS` and the `pytest_xdist_auto_num_workers` conftest
hook override it, and the hook takes priority over the variable.

## Checks (none of these were run here; each is read-only or runs tests and is for the operator or the owner)

- **R1:**
  1. `xcrun_db=/tmp/x1/db /usr/bin/time -l /usr/bin/git --version` twice. The second call is a hit on a tiny
     cache: compare its instructions with the 96-102M measured on the 90 MB cache.
  2. During a suite with R1, `stat -f %z $(getconf DARWIN_USER_TEMP_DIR)xcrun_db` should stay flat.
- **R2:** two concurrent `pytest -n auto` runs at the same tree, with the pool on and with it off. Record each
  wall time, the sum, `vm_stat` compressor pages and the sentinel log. Then repeat with T in {8, 10, 12, 16}.
- **R3:** log `key hit/miss` for one round, then count hits.
- **R5:** in the next round, compare reds caught by the selected pre-gate with reds caught at the land gate.

## Skeptic check of R4 (evidence lens, 2026-10-17, read-only)

- **Mechanism: confirmed.** pid 30634 is gone, but the same pattern was running live as pid 43740 (child of
  zsh 43694, etime 08:43): `lockf /tmp/b13-r13-land.lock bash -c '... uv run --locked pytest -q -p no:cacheprovider
  -n 4 tests/test_deploy_pack.py 2>&1 | tail -2 && ruff ... && mypy src && uv run --locked pytest -q -p
  no:cacheprovider -n auto 2>&1 | tail -2 && ...'` (MEASURED: `ps -axo pid,ppid,etime,command | grep -E
  "lockf|deploy_pack|b13-r13-land"`). The second run collects the first's tests again.
- **Not universal.** The other live land gate, `/tmp/ra-land-gate.sh` (pid 29275 under the same lock), runs the
  suite once (`-n 4`, no subset). The duplication is in some lead-typed land commands only. Neither
  `git grep test_deploy_pack` in claude-infrastructure nor `git grep "n 4 tests/test_deploy_pack"` in
  agent-context-sync docs/CLAUDE.md finds a source: the command is retyped ad hoc, and `scripts/gate.sh` (R3)
  does not exist yet (MEASURED `ls`). The fix lands only via R3 or the lead's land template.
- **Counts: confirmed.** 144 `def test_` in tests/test_deploy_pack.py, 3028 across tests/ (MEASURED `grep -c` /
  `grep -rh | wc -l` at agent-context-sync e2a8e8df); 59 at d50389b6 (2026-10-06).
- **Magnitude: overstated.** 144/3028 is 4.8% by function count, the bottom of the "5-10%" band, not its middle.
  By time it is likely less: on 2026-10-06 the junit per-file table (`docs/plans/test-suite-performance.md:59-74`)
  did not list test_deploy_pack among the 12 slowest files (90% of 649 s serial); it sat in "the other 32 files,
  63 s". It has since grown 59 -> 144 tests, but test_install_oneshot (81 -> 277, 408 subprocess/`install_sh(`
  sites) and test_setup_report/test_cycle grew faster. ESTIMATED share of serial suite time: 2-5%, i.e. roughly
  20-60 s off a 13-15 min loaded land gate, only on lands that use this command.
- **Equivalence: holds.** Same tree, same lock, `_isolate_home` per-test isolation (agent-context-sync
  CLAUDE.md:28-31); subset + `--ignore` full run is the same set. No test asserts collection size (not checked
  exhaustively).
- **Verdict:** real, zero-risk, but small; P1 is too high (P3), and the deliverable is a line in R3's script /
  the lead's land template, not a repo change today.
