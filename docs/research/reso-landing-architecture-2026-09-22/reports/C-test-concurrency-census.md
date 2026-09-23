# C: vitest suite concurrency census (reso-management-app @ origin/main 108be1a7b)

**Question.** Which tests in the vitest include globs are unsafe to run concurrently with another copy of the suite from another worktree on the same machine, and what lint would keep new ones out?

## Verdict

1. **Nothing in the tree is certain to collide any more.** I scanned all 419 files the include globs match (`vitest.config.ts:104-121`; `scripts/tests/**` matches 0 files).
   - All 3 socket suites bind port 0: `deploy-status-health.test.ts:111`, `qa-nightly-probe.test.ts:43,52`, `static-brotli.test.ts:91`.
   - None of the 30 `/tmp/...` literals is a fixed name: 29 add pid plus a random suffix or `Date.now()`, and 1 adds the pid only.
   - All 18 `tmpdir()` sites go through `mkdtemp`.
   - No test calls `launchctl`, `security`, `defaults` or `git config --global`, or starts a daemon.
2. **One test still changes state that other worktrees share:** `postland-verify.test.ts:82` and `:96`. These two cases run the verifier without the `POSTLAND_TIP_REF` hook that lets a test skip the fetch. So `postland-verify.sh:552-553` runs a real `git fetch origin main` in the real worktree, which updates the shared ref `refs/remotes/origin/main`. That fetch can collide with the same test in another worktree, or with a real land's fetch. `ship-land.sh:277` exits 2 when its fetch fails. **Possible** (low probability: git retries a locked ref for 100 ms by default). The file is in the always-run list (line 49).
3. **The biggest remaining risk is machine load, and the pre-push run gets no retries.**
   - `ship-land.sh:869` pushes without `CI=true`, so the pre-push full suite runs with `retry: 0` and a 15 s `testTimeout`, with no `TIMEOUT_FACTOR` (`vitest.config.ts` ~54-56).
   - The post-land verifier, by contrast, runs with `CI=true` and a timeout factor of 32 (`postland-verify.sh:448-449`).
   - Tests with timing waits or heavy process spawning are therefore the likeliest false failures at load 135-320. Examples: `mem-leash.test.ts:322,327` and `deploy-release.test.ts` (measured at 81 s).
4. **Unrelated to concurrency, but a real bug:** `scripts/__tests__/window-named-properties.test.ts:4` imports `generate-window-named-properties.ts`. That module calls `main()` at top level with no guard (`:131-136`), and `main()` rewrites the committed `eslint-rules/window-named-properties.json` (`:41,126`).
   - The staleness check at `:20-27` compares the regenerated list against a file that was just overwritten with that same list, so **it can never fail**.
   - There is also a possible race inside one suite run: `eslint-rules/no-window-named-property-id.test.ts:6` imports the same JSON from a parallel worker and could read it mid-write.

## Scope, method, and how many suites actually run at once

- **Method.** I searched `origin/main` with `git grep` (`:(glob)` pathspecs, 419 files, matching vitest's `**` semantics). I read the lines of every hazard row. For every test that runs a repo script, I followed the call into the script: `postland-verify.sh`, `ship-land.sh`, `deploy-release.sh`, `ship-reconcile.sh`, `worktree-pool.sh`, `mem-leash.sh`, `gate-boot-preflight.sh`, `scripts/hooks/pre-commit`, `lead-alert-phase0.sh`, `deploy-status.sh`, `turso-safe.sh` and `locations.sh`. I also checked the scripts modules that tests import. I ran no tests.
- **Test isolation.** The config sets neither `pool` nor `isolate`, so vitest's defaults apply: separate forked processes with per-file isolation. `process.env` changes, `process.chdir` and fake timers therefore stay inside one process. They cannot cross test files, and they cannot cross suites.
- **Real concurrency ceiling.**
  - `pnpm test:unit` wraps vitest in a machine-wide semaphore, `cc-sem general`, with 3 slots (`package.json:126`, `cc-sem.sh:90`).
  - The land-time union suite runs under `cc-sem reso-land` with 1 slot (`cc-sem.sh:88`, `ship-land.sh:547-548`).
  - The postland verifier runs on its own, and a bare `vitest` call bypasses cc-sem entirely.
  - So in practice N ≤ 3 full suites, plus 1 union suite, plus the verifier, plus any ad-hoc runs.

### The six pre-push rejections (from `~/.reso/land.log`, read-only)

The log has 113 land records since 2026-09-16T05:00Z. Six were rejected by the pre-push unit tests, each with the push_tail `❌ unit tests failed`.

| ts (UTC) | branch | lands overlapping in time | load1 at entry/exit | Cause |
|---|---|---|---|---|
| 09-22 18:53:21 | sec-w1a-opbuilder | 1 | 275/261 | **unattributed** (push_tail cut off, `fail_specs: []`) |
| 09-22 19:17:58 | sec-w1a-opbuilder | 4 | 135/276 | **unattributed** |
| 09-22 19:30:51 | sec-w1d-livehrole | 4 | 320/238 | **unattributed** |
| 09-23 02:54:48 | sec-w6-w4a7b-deaction | 5 | 148/124 | fixed ports in qa-nightly-probe (commit message of 0c0b1b37c: "rejected 3 of W4a-7b's 4") |
| 09-23 03:46:15 | sec-w6-w4a7b-deaction | 1 | 35/24 | same |
| 09-23 03:52:18 | sec-w6-w4a7b-deaction | 2 | 21/20 | same |

- All 6 rejections overlapped at least one other land.
- All 6 predate the port fix, which landed 2026-09-23T04:05Z.
- The three unattributed ones ran at load 135-320. That fits the old fixed-port collision just as well as a timeout caused by load. The logs cannot tell the two apart.

## (a) Hazard table

| file:line | hazard class | exact construct | collides how | in presubmit-always.txt? | fix pattern |
|---|---|---|---|---|---|
| `scripts/__tests__/postland-verify.test.ts:82`, `:96` (→ `scripts/postland-verify.sh:551-554`) | shared git common dir + network | `verify(['--run-if-needed'])` with no `POSTLAND_TIP_REF`, `cwd: ROOT` (the real worktree), which runs `git fetch origin main --quiet 2>/dev/null \|\| true` | **possible**. Every concurrent full suite and every real land fetch takes the lock on `refs/remotes/origin/main`, which all worktrees share. The script ignores its own fetch failure, but a real land does not: `ship-land.sh:277` exits 2. Git's default 100 ms ref-lock retry keeps this rare. `worktree-pool.sh:196-203` records that these fetch races have happened before. A network that silently drops packets can also push the test past 15 s. | yes (line 49) | Pass the hook that already exists: resolve `tip` once and call `verify(['--run-if-needed'], { POSTLAND_TIP_REF: tip })`, as the block at `:325-390` already does. |
| `scripts/__tests__/mem-leash.test.ts:316-329` | load / wall-clock | `setTimeout(() => child.kill('SIGTERM'), 2_000)`, then a fixed 500 ms sleep, then `pgrep -f leash-sigterm-${pid}` | **possible under load**. If bash has not set up its SIGTERM handler within 2 s, the exit code is not 143. If killing the process group takes longer than 500 ms, `pgrep` still finds processes. | yes (47) | Wait for the child to print its marker line before sending SIGTERM. Replace the fixed 500 ms with polling `pgrep` until it returns nothing, up to a deadline. |
| `scripts/__tests__/qa-nightly-probe.test.ts:102-107` | load / wall-clock | `expect(elapsed).toBeLessThan(5000)` around a 400 ms probe timeout | possible (low): about 4.6 s of scheduling slack | yes (56) | Keep, or scale the bound by `VITEST_TIMEOUT_FACTOR`. |
| `scripts/__tests__/qa-nightly-probe.test.ts:50-56` (`closedPort`) | port race (check-then-use gap) | grab a port-0 socket, close it, then probe the freed port and expect `down` | possible (very low): another process could bind that freed port within the 600 ms probe | yes (56) | Acceptable as is. Alternative: use `127.0.0.1:1`, as `deploy-status-health.test.ts:140` does. |
| `scripts/__tests__/deploy-status-health.test.ts:140` | fixed port assumed closed | `probe('127.0.0.1:1')` | none: no suite ever binds :1 | yes (35) | none; the lint should allow `:1` |
| `scripts/__tests__/deploy-release.test.ts:152` (and the file's fixture setup) | load (heavy process spawning) | 5 × (`git add` + `commit` + `push`) plus a bash script, with a 15 s default timeout | **possible**. This test took 81 s at load ~22 with lowered process priority (comment in `vitest.config.ts` ~45-49). The pre-push run gives it no retry. | yes (34) | Batch the fixture's git work (one commit script or `git fast-import`), or give it an explicit per-test timeout multiplied by `TIMEOUT_FACTOR`. |
| `ship-land.test.ts`, `worktree-pool-ownership.test.ts`, `postland-verify.test.ts`, `ship-reconcile-conflict.test.ts`, `hook-node-env.test.ts` (whole files) | load (heavy process spawning) | many `git`/`bash` spawns per test; fixtures are temp repos, so no shared state | possible; **unverified** (not measured, since no tests were run) | yes (60, 69, 49, 61, 45) | Same as above. |
| `scripts/__tests__/window-named-properties.test.ts:4` (→ `scripts/generate-window-named-properties.ts:41,126,131-136`) | working-tree write on import, to a tracked file | importing the module runs `try { main() }` with no entry guard, and `main()` does `writeFileSync(resolve(process.cwd(),'eslint-rules/window-named-properties.json'))` | Across worktrees: **none** (the path follows each worktree's cwd). Within one suite run: **possible** partial read, because `eslint-rules/no-window-named-property-id.test.ts:6` imports the JSON in a parallel worker while it is being truncated and rewritten. **It also makes the staleness check at `:20-27` impossible to fail.** | writer yes (68); reader **no** (runs only via `vitest related` or the pre-push full suite) | Add an entry guard like the ones in `verify-ps-import.ts:271` and `psd-paths-to-floor-plan.ts`: `if (import.meta.url === pathToFileURL(process.argv[1]).href) main()`. |
| `scripts/__tests__/hook-node-env.test.ts:193-203` | runs the real pre-commit hook | `/bin/sh scripts/hooks/pre-commit` in ROOT, with the real `HOME` and `GIT_DIR=ROOT/.git` | none across suites: the index is per worktree, and the hook uses `mktemp` (`pre-commit:176,208`) | yes (45) | none needed |
| `scripts/__tests__/mem-leash.test.ts:123,228,291,316` | real HOME, default directory | these four spawns omit `RESO_LEASH_DIR`, so the script's default is `${HOME}/.reso/leash` (`mem-leash.sh:116`) | none: the directory is written only when the leash trips (`mem-leash.sh:225-239`), and none of these four cases can trip (memory reads as 0, a broken `ps`, or the same-process-group refusal) | yes (47) | Pass `RESO_LEASH_DIR` on every call anyway, as a safeguard. |
| `scripts/__tests__/gate-boot-preflight.test.ts:58-62` | inherits the caller's environment (not a concurrency issue) | `...process.env`, so a caller's `RESO_GATE_FORCE=1` makes the script exit 0 early (`gate-boot-preflight.sh:3-4`) | none across suites; a wrong pass is possible if the caller's env sets it | yes (42) | Clear `RESO_GATE_*` from the test's env. |

### Checked and found safe (evidence for the "no certain collisions" verdict)

- **Sockets.** Only 3 files import `node:net`/`http`/`https`. All three bind 0 and read the assigned port back. The `localhost:3000` / `127.0.0.1:6001` strings elsewhere are inputs to pure functions or mocked errors (e.g. `lib/poke-channel.test.ts:17-42`, `pokeActions.test.ts:29`).
- **Temp paths.**
  - 29 `/tmp/<tag>-${process.pid}-<random or Date.now>.sqlite` sites across 24 files, plus the helper `lib/db/__tests__/fullSchemaLibsqlDb.ts:92`.
  - 1 pid-only site, `source-art-chroma.test.ts:109`. It is safe because a pid is unique among live processes, but it leaves one PNG behind per run.
  - 18 `mkdtemp` sites across 15 files.
- **Databases.** `testDb.ts:92` uses `:memory:`. An unmocked `getDB` opens `file:sqlite.db` relative to each worktree (`drizzle/db.ts:215-220`). Worktree databases are copied from a template, never symlinked (`db-ensure.sh` header).
- **Scripts driven against fixtures.**
  - `ship-land`, `deploy-release` and `postland-verify` override `HOME` with a `mkdtemp` directory (`:46`, `:42`, `:60`).
  - `worktree-pool-ownership` overrides `RESO_STATE_DIR` and `RESO_WT_ROOT` (`:75-76`).
  - All git fixtures are `mkdtemp` repos with `GIT_*` cleared.
  - `deploy-release --dry-run` exits (`deploy-release.sh:197-199`) before `aws` or `curl` run.
  - `lead-alert-phase0 --dry-run` uses a `mktemp` work dir and stubbed `curl`/`flyctl`.
- **Process-table queries.** Both `pgrep` markers include `${process.pid}` (`mem-leash.test.ts:200,315`).
- **Network.** No unmocked calls to external hosts. `tenant-reachability.test.ts:185-206` injects its `fetchImpl`, `fly-certs.test.ts:106-135` injects its config reader, and `static-brotli` fetches its own port-0 server.

## (b) Counts per class (419 files)

| Class | Sites / files | Certain | Possible | None | Always-run? |
|---|---|---|---|---|---|
| Fixed TCP/UDP listen port | 0 / 0 (3 socket files, all port 0) | 0 | 0 | 3 files | all 3 yes |
| Fixed port assumed closed | 1 / 1 | 0 | 0 | 1 | yes |
| Port race (grab, release, probe) | 1 / 1 | 0 | 1 (very low) | 0 | yes |
| Fixed `/tmp` name, or `tmpdir()` plus a fixed name | 0 | 0 | 0 | — | — |
| Temp path scoped by pid (+ random) | 30 / 25 | 0 | 0 | 30 | several |
| `mkdtemp` | 18 / 15 | 0 | 0 | 18 | most |
| Writes to the real `$HOME` / `~/.reso` | 0 reachable (4 calls fall back to the default dir, but none can trip) | 0 | 0 | 4 calls | yes |
| Real `HOME` passed to a spawned script (read only) | 9 files | 0 | 0 | 9 | all yes |
| Shared git common dir or network | 1 file / 2 tests | 0 | 2 | — | yes |
| Repo working-tree write | 1 (tracked file, on import) | 0 | 1 (within one suite) | — | writer yes, reader no |
| Shared sqlite/libsql file | 0 | 0 | 0 | — | — |
| Lock directories / singletons | 2 (both under a temp dir) | 0 | 0 | 2 | yes |
| Process-table queries (`pgrep`/`pkill`) | 2 (pid-scoped) | 0 | 0 | 2 | yes |
| `launchctl`, `security`, `defaults`, `osascript`, `git config --global`, daemons | 0 | 0 | 0 | — | — |
| `process.env` changes (assign, delete, `stubEnv`) | 34 files | 0 | 0 | 34 (stay in-process) | — |
| `process.chdir` | 0 | — | — | — | — |
| Fake timers / `setSystemTime` / `stubGlobal` | 20 / 7 / 26 files | 0 | 0 | all (per file) | — |
| Wall-clock asserts or sleeps that race another process | 3 sites | 0 | 3 | — | all yes |
| Heavy spawning that is sensitive to load | 6+ files | 0 | possible (unmeasured) | — | all yes |

- **Always-run list vs `vitest related`.** Every row above that can hold a machine-state hazard is already in `tests/presubmit-always.txt`. The only exception is the within-suite reader, `eslint-rules/no-window-named-property-id.test.ts`.
- **Why that overlap is structural.** `scripts/checks/presubmit-always.ts:105` (`SIDE_INPUT_RE` = spawn, `child_process`, `readFileSync`, `node:fs`, `readdirSync`) pulls any test that spawns a process or reads the filesystem into the always-run set, including through its local imports. So the files that can hold a machine-state hazard are, by construction, the ones exposed on every code land.
- **The gap in that selection.** A test that only opens sockets (imports `node:net`/`http` but never reads the filesystem or spawns) is not selected. A new fixed-port test like that would reach lands only through `vitest related` and the pre-push full suite.
- **Existing checks.** Nothing in `scripts/checks/` (20 files) checks for concurrency hazards. `presubmit-always.ts` only chooses which tests always run; it does not check them.

## (c) Proposed lint

"Current hits" are the results of running each regex against origin/main now.

| # | Rule | Check | Current hits | False-positive notes | Where to enforce |
|---|---|---|---|---|---|
| L1 | No fixed listen port | ERE `\.listen\( *([1-9][0-9]*\|[A-Z_]{3,})` and `WebSocketServer\(\{[^}]*port: *[1-9]`. AST version: the first argument of `.listen()` on a value from `createServer` / `net.createServer` / `new WebSocketServer` must be a literal `0` or absent. | 0 | `host:port` strings in URL-parsing tests are not `.listen(` call sites, so they are not matched. The `[A-Z_]{3,}` branch flags a constant that was itself read back from port 0; the AST version resolves that. | ESLint rule (pre-commit on staged files) plus the full-tree meta-test |
| L2 | No fixed temp path | (a) ERE `['"\`](/private)?/tmp/[^'"\`$]*['"\`]`; (b) a `` `(/private)?/tmp/…` `` template with no `process.pid`, `random` or `randomUUID`; (c) `(join\|resolve)\((os\.)?tmpdir\(\), *['"]` not wrapped in `mkdtemp(Sync)?(` | 0 / 0 / 0 | pid-only templates (`source-art-chroma:109`) pass (b), which is fine since a pid is unique among live processes. A stricter policy ("new code uses `mkdtemp`") would flag it. | ESLint |
| L3 | No real-repo git writes or network | Flag `spawn*/exec*('git', [verb …])` where verb is one of fetch, push, pull, gc, worktree, update-ref, stash, notes, remote, or `config` without `--get`, and `cwd` does not come from a `mkdtemp` result. Also, for any `bash <repo script>` spawned with `cwd: ROOT\|REPO_ROOT`, search the script for `git (-C \S+ )?(fetch\|push\|worktree (add\|remove\|prune)\|gc\|update-ref)`. If found, require the test to pass the script's documented test-only env var, or to have an allowlist entry with a reason. | 1 (`postland-verify.sh:553` via `postland-verify.test.ts:82,96`) | The temp-repo git fixtures (`ship-land`, `deploy-release`, `worktree-pool-ownership`, `ship-reconcile-conflict`) must pass. Telling them apart needs to follow where `cwd` came from, so this belongs in a meta-test, not a regex. | Meta-test |
| L4 | No machine-global commands | ERE `(spawnSync\|execFileSync\|execSync\|spawn\|execFile)\(['"](launchctl\|security\|defaults\|pkill\|killall\|osascript)['"]`, `config['"], *['"]--global`, `config --global` | 0 | Mentions inside comments or strings are not call sites. | ESLint |
| L5 | Scripts spawned with the real HOME must not write under HOME | For `bash\|sh <repo script>` spawns whose `env` has no `HOME:` key, search the script for writes under `$HOME/` or `~/` (`>`, `>>`, `mkdir`, `mv`, `cp`). If any exist, require a `HOME` override or the script's own dir override (`RESO_LEASH_DIR`, `RESO_STATE_DIR`) on every call. | 0 certain; 4 advisory (`mem-leash.test.ts:123,228,291,316`) | Many scripts only read HOME to build PATH (`hook-node-env.sh:69-72,114`), so the check must look for writes, not reads. | Meta-test |
| L6 | Modules that tests import have no unguarded top-level side effects | AST, over each test's local import closure (reuse `presubmit-always.ts` IMPORT_RE and its closure walk, `:173-203`): flag a top-level ExpressionStatement or TryStatement that calls `main()` (or runs fs/spawn) outside an entry-guard `if` | 1 (`generate-window-named-properties.ts:131-136`) | The regex version over-matches: 124 hits across `scripts/`, including calls inside guard blocks. Use the AST only, and allow pure top-level initialisers. | Meta-test |
| L7 | Process-table queries scoped to this process | ERE `['"](pgrep\|pkill)['"]`: the pattern argument must include `process.pid` or a constant built from it in the same file | 2 (both pass) | Needs a lookup of how the marker constant is defined. | ESLint (warn) |
| L8 | No tight wall-clock assertions or sleeps against other processes | `toBeLessThan(OrEqual)?\( *[0-9_]{1,6} *\)` on a line mentioning `elapsed`, `Date.now`, `performance.now` or `t0`; `setTimeout\([^,]+, *[0-9_]{3,5}\)` in a test that also spawns a process | 3 (`qa-nightly-probe:107`, `mem-leash:322,327`) | Exclude fake-timer tests (`advanceTimersByTime*`), which are deterministic. | ESLint warn plus a meta-test report |

**Where to enforce.**
- **Pre-commit, single-file rules (L1, L2, L4, L7, L8).** Write them as a custom ESLint rule, e.g. `reso/test-concurrency-hygiene`, in `eslint-rules/` alongside the existing rule tests (`eslint-rules/*.test.ts`), scoped to the include globs in `eslint.config.mjs`. The pre-commit hook already runs ESLint on staged files, so violations are caught before they ever land.
- **Land gate and postland, cross-file rules (L3, L5, L6).** Put them in a meta-test, e.g. `scripts/__tests__/test-concurrency-hygiene.test.ts`, with an allowlist that records a reason for each entry, the way `check-reachability.test.ts` does.
  - Because the meta-test reads files, `SIDE_INPUT_RE` pulls it into `tests/presubmit-always.txt` automatically. That means it runs on every code land and on every verifier run.
- **Not lintable: load.** The fix for the load class is how the land runs, not test code. `ship-land.sh:869` could push with the same tolerance the verifier uses (`CI=true` → `retry: 2`, and a `VITEST_TIMEOUT_FACTOR`). That is outside this census, but it now controls the remaining risk.

## Options I ruled out

- **`process.env` / `chdir` / fake timers as cross-suite hazards:** ruled out. The default process isolation keeps them in-process (34 / 0 / 20 files).
- **Repo-relative writes as cross-worktree hazards:** ruled out. Each worktree is its own directory. `node_modules` files are hardlinks into the shared pnpm store, but no test writes under `node_modules` (grep: 0).
- **External network or shared remote databases:** ruled out. No unmocked external fetch was found, and the database layer resolves to a per-worktree file in tests.
- **Rewriting `mem-leash`'s `ps` stub:** not needed. The stub reports every process group, but the leash adds up only its own child's group.

## Not verified, and what blocked it

- The 3 unattributed rejections (sec-w1a-opbuilder ×2, sec-w1d-livehrole). `land.log` keeps only the last lines of push output, and permission was denied to read those sessions' transcripts. Both a fixed-port collision and a load timeout fit the evidence.
- Load sensitivity of `ship-land`, `worktree-pool-ownership`, `postland-verify` and `hook-node-env` is not measured, because the brief ruled out running tests.
- Not scanned:
  - `scripts/checks/fabricated-menu.sh` (spawned by `fabricated-menu.test.ts:33`), for writes.
  - Whether sourcing `hook-node-env.sh` makes fnm write per-shell directories. I believe any such directories are named per invocation, but did not confirm it.
  - Whether any test imports `verify-ps-import-visual.ts`, which matched the L6 regex.
- The L6 check covers only the 10 scripts modules that script tests import. Modules under `lib/` and `src/` that do I/O at import time were not audited.
- Whether agent session environments export `CI` is unknown. If they do, the pre-push run would already get `retry: 2`.
