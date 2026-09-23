# D: what reso's land-time verification costs, and which part is avoidable

**Scope.** reso-management-app land path: `scripts/ship-land.sh` (typecheck, then the union suite) followed by `git push`, which fires `scripts/hooks/pre-push`, which runs the full `pnpm test:unit`.
**Snapshot.** `~/.reso/land.log` v3 rows 2026-09-14T03:57Z → 2026-09-23T05:10Z. The 7-day window is `ts_start ≥ 2026-09-16T04:59Z`, the same cut as `census2.py`.
**Nothing was run.** Every timing comes from an existing log, and each table names its log. Code citations are `origin/main` @ `108be1a7b`. The shared checkout was read with `git show` only.

---

## Verdict

1. **Every code round runs the unit suite twice on the same tree.** First, ship-land runs the union (`ship-land.sh:512-622`, p50 **150 s**). Then the push fires the hook, which runs the full suite again (`pre-push:130-150`, about **163 s** p50, inferred as push_s minus 4 s). The union selects a subset of what the full suite runs. The presubmit token the union writes has **no reader**: `pre-push` at origin/main and the canonical `~/.reso/land-tools` copy contain no token check, and the §3.4 hook-skip exists only in `docs/infra-deploy/learnings.md:2655-2690`. Even that design skips only on `mode=="full"`, so a union token could never retire the hook's run. In the window, 47 of the 50 tokens in `~/.reso/presubmit/` are union tokens, and none was consumed.
2. **The always-run set is almost the whole cost of a union run.** It is 159/419 specs (38%) but **92% of the full suite's test-phase time** (326 of 354 s). The union's wall time does not respond to diff size: p50 144 / 148 / 157 s for <10 / 10-30 / 30+ diff-selected files at similar load. Two classes make up that set's cost. **23 shell-out harness specs** (188 s, 53% of the entire suite) test bash scripts that a `src|lib` diff cannot reach. **48 DB-fixture specs** (117 s) apply all 95 migrations for each fixture call.
3. **The three slowest spec files are 40% of the whole suite.** They are `ship-land.test.ts` (64 s median, 106 s max), `worktree-pool-ownership.test.ts` (45 s) and `mem-leash.test.ts` (33 s). All three are node-environment shell-out tests of land infrastructure. None is a jsdom or DB suite. jsdom accounts for 47 files and 20 s of test phase, plus 17-55 s of environment setup per full run.
4. **Typecheck is already incremental.** `tsconfig.json:21` sets `incremental: true`, `.gitignore:53` ignores `*.tsbuildinfo`, and all 8 surviving landing worktrees hold a warm `tsconfig.tsbuildinfo`. What remains is a cold first check in each new per-task worktree (p50 82 s against 34 s warm) plus load. Project references on a warm worktree could save at most about 4 s per run.
5. **Avoidable time per code land is about 600-650 s of a 970 s mean (p50: about 275 of 468 s).** The duplicate suite is about 460 s, path-keying the shell-out harness specs about 140-170 s, and typecheck warmth plus a same-tree skip about 30 s. Before this is actioned: 6 rounds in the window passed the union and failed the hook's full suite. 3 were an environment red (fixed-port EADDRINUSE), 1 looks like a load flake, and 2 are unresolved. None is a demonstrated selector miss.

---

## (a) Full suite: every recoverable run

### A1. Background verifier cells: `~/.reso/verify-logs/*/test-unit.log`

Settings for these runs: 3 workers (`VITEST_MAX_FORKS=3`), `nice -n 19`, `CI=true` (retry 2) and `VITEST_TIMEOUT_FACTOR=32` (`postland-verify.sh:448-451`). These are cold cells.

| Log dir | Start (UTC) | Files | Tests | **Wall s** | Worker-sum s (tests / import / env) | load1 during run (source) |
|---|---|---|---|---|---|---|
| bfd3e4b5b257-1788799358 | 09-07 16:45 | 381 | 4,858 | **99** | 264 (198/41/17) | ~24 (land.log v2 row 16:14Z) |
| 4d8c78e23f59-1788891664 | 09-08 18:24 | 381 | 4,862 | **161** | 442 (314/78/29) | n/a (no sampler before 09-13) |
| --force-1788907619 | 09-08 22:50 | 381 | 4,862 | **136** | 376 (274/62/23) | n/a |
| 4d8c78e23f59-1788908564 | 09-08 23:05 | 381 | 4,862 | **142** | 386 (279/66/25) | n/a; 1 forks-worker terminate timeout (`round-trips.test.ts`) |
| b6c2cd3f8409-1788925936 | 09-09 03:56 | 381 | 4,862 | **243** | 679 (514/101/40) | ~74-79 (v2 rows 03:51Z / 04:43Z) |
| dec92dd1b41a-1788928988 | 09-09 04:46 | 381 | 4,862 | **233** | 635 (506/79/29) | ~79 (v2 row 04:43Z) |
| 6c360d9c5-1789363936 | 09-14 05:34 | 382 | 4,875 | **126** | 344 (273/43/19) | 15-22, mean 18 (`load.jsonl`) |
| 06ce6fee5013-1789834775 | 09-19 16:22 | 385 | 4,902 | **197** | 536 (353/105/55) | 20-31, mean 26 |
| ae8d16122a49-1789839388 | 09-19 17:39 | 387 | 4,918 (1 skip) | **157** | 434 (343/55/22) | 23-30, mean 26 |
| 7f84a45c20c1-1789866442 | 09-20 01:12 | 391 | 4,977 (1 skip) | **203** | 570 (448/70/30) | 46-61, mean 54 |

- The verifier has not run since 09-20. `gl.reso.postland-verify` is not installed; `launchctl list` shows only `com.claude.postland-verify`, which is infrastructure's verifier. The design's "full suite in the scheduled verifier" backstop is therefore not in place.
- Worker-time splits as follows: test phase 66-80%, import 12-20%, environment 5-10%. Overhead is about 0.17-0.48 s per file (p50 ~0.3). Worker-sum divided by wall is about 2.7 on all ten runs, so 3 workers are nearly saturated.

### A2. Land-time full-mode rounds: `land.log` `suite_mode=="full"`

These ran with 4 workers at normal priority, admitted through `cc-sem reso-land` (k=1). The `wt-pool-7` rounds are also the 3 full-mode tokens in `~/.reso/presubmit/`.

| ts_start (UTC) | Worktree | Files | suite_s | sem_wait_s | load1_entry |
|---|---|---|---|---|---|
| 09-19 16:08 | wt-cc-095358 | 385 | 127 | 0 | 19 |
| 09-19 16:13 | wt-cc-095358 | 385 | 121 | 0 | 13 |
| 09-19 18:58 | wt-pool-3 | 390 | 137 | 0 | 42 |
| 09-22 18:56 | wt-pool-7 | 396 | 305 | 0 | 266 |
| 09-22 19:08 | wt-pool-7 | 396 | 226 | 105 | 237 |
| 09-22 19:22 | wt-pool-7 | 396 | 291 | 228 | 158 |
| 09-22 19:38 r1/r2/r3 | wt-pool-7 | 396 / 398 / 399 | 246 / 215 / 133 | 190 / 0 / 0 | 242 (at entry) |

For the 7-day window, full-mode suite_s p50 is **215 s** (n=9).

### A3. Hook full suite implied by push time (the most frequent full run)

Settings: `pre-push:136` running `pnpm test:unit` (package.json:126, `cc-sem general` with k=3, then `vitest run`), 4 workers (`vitest.config.ts:15,101`, 10 cores).

Implied hook suite = `push_s(code round) − push_s(non-code round, p50 4 s)`. This includes any wait in the general queue.

| load1_entry | [0,30) | [30,80) | [80,150) | [150,220) | [220,400) |
|---|---|---|---|---|---|
| push_s, union rounds, p50 (n) | 129 (11) | 155 (17) | 187 (14) | 189 (3) | 226 (13) |
| **implied hook full suite** | **~125** | **~151** | **~183** | **~185** | **~221** |
| union suite_s, p50 (n) | 101 (12) | 142 (17) | 158 (15) | 201 (4) | 170 (15) |
| land-time full suite_s, p50 (n) | 124 (2) | 137 (1) | n/a | 291 (1) | 226 (5) |

- **Load scaling.** With 4 workers at normal priority, full-suite wall is about 120-135 s at load <45 and about 215-305 s at load 160-270. That is roughly 1.8-2.2 times slower at 5-10 times the load. The niced 3-worker verifier degrades faster: 99-126 s at load ~18-24, 233-243 s at ~75-79.
- **Growth.** The suite went from 381 files / 4,858 tests (09-07) to 391 / 4,977 (09-20), to 396-399 files in the 09-22 full rounds, to **419 specs** on origin/main today (include globs `vitest.config.ts:104-121`). That is about 38 files in 16 days.

---

## (b) Slowest 20 spec files

**Source:** the vitest results cache `node_modules/.vite/vitest/<hash>/results.json` in 25 reso worktrees (mtimes 06-19 → 09-23). Each value is the file's last test-phase `duration` in that worktree. Medians and maxima are taken across worktrees. The cache excludes import, collect and environment time (see A1 for those phases).

**Class definitions:**
- **DB-fixture:** imports `createTestDb` (`src/app/actions/replicache/__tests__/fixtures/testDb.ts:60-95`) or `createFullSchemaLibsqlDb` (`lib/db/__tests__/fullSchemaLibsqlDb.ts:69-95`). Both apply all 95 `drizzle/migrations/*.sql` on every call. The libSQL fixture also writes a `/tmp/fullschema-*.sqlite` file (`:92`).
- **shell-out:** the spec itself calls `spawnSync`/`execSync` against a bash SUT.

| # | Spec | Median s | Max s | n | Env | Class | Always-run? | Cumulative % of suite |
|---|---|---|---|---|---|---|---|---|
| 1 | scripts/\_\_tests\_\_/ship-land.test.ts | 64.1 | 105.8 | 15 | node | shell-out (ship-land.sh, ship-reconcile.sh) | Y | 18% |
| 2 | scripts/\_\_tests\_\_/worktree-pool-ownership.test.ts | 45.2 | 84.9 | 15 | node | shell-out (worktree-pool.sh) | Y | 31% |
| 3 | scripts/\_\_tests\_\_/mem-leash.test.ts | 32.6 | 42.1 | 15 | node | shell-out (mem-leash.sh) | Y | 40% |
| 4 | scripts/\_\_tests\_\_/deploy-release.test.ts | 15.2 | 29.0 | 15 | node | shell-out (deploy-release.sh) | Y | 44% |
| 5 | src/app/actions/replicache/\_\_tests\_\_/round-trips.test.ts | 11.6 | 36.8 | 8 | node | DB-fixture (libSQL full schema) | Y | 48% |
| 6 | scripts/\_\_tests\_\_/provision-venue-anchor-drift.test.ts | 10.7 | 13.4 | 8 | node | DB-fixture | Y | 51% |
| 7 | src/app/(app)/guests/\_\_tests\_\_/seeds-round-trips.test.ts | 10.0 | 21.3 | 8 | node | DB-fixture | Y | 53% |
| 8 | tests/floor-plan/venuePresetNamespace.test.ts | 9.1 | 16.7 | 8 | node | DB-fixture | Y | 56% |
| 9 | scripts/\_\_tests\_\_/ship-reconcile-conflict.test.ts | 8.6 | 22.1 | 15 | node | shell-out (ship-reconcile.sh) | Y | 58% |
| 10 | src/app/(app)/floor-plan/\_\_tests\_\_/keyedSeedHandoff.test.tsx | 8.6 | 11.9 | 8 | **jsdom** | jsdom | Y | 61% |
| 11 | scripts/\_\_tests\_\_/provision-venue-table-map-scope.test.ts | 8.5 | 14.6 | 8 | node | DB-fixture | Y | 63% |
| 12 | src/app/(app)/list/[listIDSlug]/listDetailSeed.test.ts | 8.0 | 30.6 | 22 | node | own `@libsql/client` (not the fixture) | **N** | 65% |
| 13 | src/app/actions/\_\_tests\_\_/seeds-round-trips.test.ts | 7.1 | 12.7 | 8 | node | DB-fixture | Y | 67% |
| 14 | tests/floor-plan/localTierNamespace.test.ts | 7.1 | 16.9 | 11 | node | DB-fixture | Y | 69% |
| 15 | lib/db/\_\_tests\_\_/fullSchemaLibsqlDb.test.ts | 7.0 | 16.8 | 17 | node | DB-fixture | Y | 71% |
| 16 | scripts/\_\_tests\_\_/postland-verify.test.ts | 6.2 | 11.5 | 15 | node | shell-out (postland-verify.sh) | Y | 73% |
| 17 | scripts/\_\_tests\_\_/gate-boot-preflight.test.ts | 4.3 | 6.0 | 15 | node | shell-out | Y | 74% |
| 18 | src/app/actions/replicache/\_\_tests\_\_/bottle-service-venue-authz.test.ts | 4.2 | 10.4 | 16 | node | DB-fixture | Y | 76% |
| 19 | scripts/\_\_tests\_\_/presubmit-always.test.ts | 4.0 | 10.0 | 8 | node | fs walk (runs the generator twice) | Y | 77% |
| 20 | src/app/actions/replicache/\_\_tests\_\_/pushActionsBatch-overlap.test.ts | 3.8 | 9.4 | 3 | node | DB-fixture | Y | 78% |

**Class totals** (test phase, 419 specs, 354 s):

| Class | Always-run: files / s | Not always-run: files / s |
|---|---|---|
| shell-out harness | 23 / **188** | 0 / 0 |
| DB-fixture | 48 / **117** | 0 / 0 |
| other node (fs-read or pure) | 82 / 11 | 220 / 20 |
| jsdom | 6 / 10 | 40 / 8 |
| **Total** | **159 / 326 (92%)** | **260 / 28 (8%)** |

- **The dominant files are not jsdom.** 19 of the top 20 are node-environment specs. jsdom's larger cost is environment setup, which the cache cannot see: 17-55 s of worker-time per full run (A1 `environment` column), about 0.4-1.2 s per jsdom file.
- **Every DB-fixture spec is always-run.** The fixture's `readdirSync`/`readFileSync` of `drizzle/migrations` matches `SIDE_INPUT_RE`, and that match propagates through each importer's closure.
- **Per-test fixture cost (reasoning, not measured).** `round-trips.test.ts` has 6 tests with 4 `beforeEach` hooks, at 11.6 s median, which is about 2 s per test. That fits one full-schema migrate per test. A per-worker migrated template copied per test (the pattern `scripts/db-ensure.sh` already uses for dev databases) is an unmeasured lever.

---

## (c) The union suite: always-run set and diff-related share

### What `tests/presubmit-always.txt` holds and how it is kept honest

- **Contents.** 159 lines: `src/` 61, `scripts/__tests__/` 42, `tests/` 29, `lib/` 27. By class: 23 shell-out, 48 DB-fixture, 6 jsdom, 82 other fs-reading or pure node specs.
- **Generator** (`scripts/checks/presubmit-always.ts`):
  - It reads the include globs from `vitest.config.ts` itself (`:43-56`).
  - It walks the matching spec files (`:86-98`).
  - It selects a spec if the spec **or any module in its first-party import closure** (a breadth-first walk with tsconfig `paths` resolution, `:191-211`) matches `SIDE_INPUT_RE` (`:105`: `execSync|spawnSync|spawn\(|execFile|child_process|readFileSync|readFile\(|from ['"]node:fs|fs\.promises|readdirSync`).
  - It writes sorted output (`:229-240`).
- **Validator** (`scripts/__tests__/presubmit-always.test.ts:17-61`, itself in the set):
  - The committed file must equal the generator's output.
  - The file must be sorted and deduplicated.
  - Positive control for the transitive arm: `venueSvgData` and `venueContentBounds`.
  - Negative control: the generator must not select every spec.
  - The include globs must be read from the config, not restated.
- **Growth.** 146/382 = 38.2% (`8a950731f`, 09-13) → 159/419 = 37.9% (`754a4693d`, 09-22), across 13 regenerations. The design expected **109/381 = 28.6%** (`learnings.md:2649`).
- **The rule over-selects by construction.** A spec is "always-run" if anything in its closure touches the filesystem. It does not check whether that input can change without a TS diff. The shell-out specs' real inputs are `scripts/*.sh`, and the DB-fixture specs' real inputs are `drizzle/migrations/*.sql`. Both are paths visible in the diff.

### What share of a union run the always-run set costs

| Measure | Value | Source |
|---|---|---|
| Always-run share of **files** in a union run | p10 72% · **p50 89%** · p90 99% | land.log `suite_files` against `always_n` at each round's `head` (`git show <head>:tests/presubmit-always.txt`) |
| Always-run share of **test-phase time** | ≥ 99% at p50: diff-selected extras are only cheap node/jsdom specs (~0.1-0.2 s each) | results caches |
| Always-run share of **worker-time**, test phase plus ~0.3 s/file overhead | **~98% at p50 extras, ~94% at p90** | arithmetic: 326 + 159×0.3 = 374 s, against +18 (p50) or +62 (p90) extra files × ~0.4 s |
| **Empirical check:** union suite_s against diff-selected file count | extras <10: p50 **144 s** (n=20, load 86) · 10-30: **148 s** (n=23, load 104) · ≥30: **157 s** (n=20, load 108) | land.log, 7 days |
| Union vs full suite_s at matched load | load <30: 101 vs 124 (**0.81**) · load ≥220: 170 vs 226 (**0.75**) | A3. Modelled 380/480 worker-s = **0.79** |

### Selection-size distribution (land.log, 7 days, union rounds n=63)

| | p10 | p25 | p50 | p75 | p90 | max |
|---|---|---|---|---|---|---|
| `suite_files` | 153 | 157 | **172** | 212 | 217 | 273 |
| diff-related extras (`suite_files − always_n@head`) | 2 | 3 | **18** | 58 | 62 | 127 |
| `suite_s` | 98 | 118 | **150** | 176 | 204 | 238 |
| `sem_wait_s`, reso-land queue (all suite rounds, n=72) | 0 | 0 | 0 | 89 | 148 | 267 |

- Extras histogram: 0 → 3 rounds; 1-10 → 17; 11-30 → 23; 31-60 → 11; 61+ → 9.
- `always_n` at head ranged 146-159: mode 155 (15 rounds), then 149 (9 rounds).
- **Discrepancy with the lead's figure.** The lead's "union suite_s 112 (n=61)" reproduces only as p50(`suite_s − sem_wait_s`) = 117 (n=65). `ship-land.sh:570-572` already subtracts the admission wait, so that is a double subtraction. The correct union p50 is **150 s**; for landed rows only it is 140, and for push-rc=0 rounds 133.

---

## (d) Typecheck

**Status: incremental is already on and warm.**
- `tsconfig.json:14` sets `noEmit: true` and `:21` sets `incremental: true`. There is no `tsBuildInfoFile`, so TypeScript writes `./tsconfig.tsbuildinfo`, which `.gitignore:53` ignores.
- Warm buildinfo files of about 2 MB exist in 36 worktrees, including all **8 of 8** surviving worktrees that landed in the window (`wt-pool-2/3/5/7/8`, `wt-sec-w6-*`). The other 17 landing worktrees were reaped.
- `ship-land.sh:644-651` runs `pnpm typecheck` (package.json:82, `tsc --noEmit`) once per tree per process (`TSC_GREEN_TREE`, `:494`) and skips ranges tsc cannot read (`:489-500`).

**Measured phase costs, quiet box** (`docs/design/open.md:3094-3098`, reso's own record):

| State | Wall | Program | Bind | Check |
|---|---|---|---|---|
| cold (no tsbuildinfo) | 38.8 s | 3.51 s | 0.86 s | 33.82 s |
| unchanged tree | 4.4-4.6 s | 3.02 s | 0.85 s | none |
| one file edited | 5.5-7.9 s | 2.85-3.38 s | 0.81-1.01 s | 1.09-2.02 s |

The Program stage loads 7,814 files, 6,094 of them `node_modules` `.d.ts`. `@aws-sdk/client-ec2` alone is 1,037 files, pulled in by 2 repo files (`open.md:1359`).

**At land** (land.log, 7 days): `tsc_s` p10 9 · p25 20 · **p50 42** · p75 69 · p90 111 · max 276, over n=101 runs (22 skipped), 5,335 s in total.

| Split | n | p50 | p50 at load <40 | Minimum |
|---|---|---|---|---|
| First tsc in a worktree (cold) | 14 | **82 s** | 47 s | 42 s (matches the 38.8 s cold figure) |
| Later tsc in the same worktree (warm) | 88 | **34 s** | 14 s (p25 8) | 5 s (matches the 5.5-7.9 s warm figure) |
| By load1_entry | | <30: 21 · 30-80: 42 · 80-150: 50 · 150-220: 52 · ≥220: 64 | | |

**Estimated savings on typecheck:**

| Lever | Saving | Basis |
|---|---|---|
| Turn on incremental | **0** | Already on |
| Seed a warm `tsconfig.tsbuildinfo` into each new worktree (copied from trunk or the pool) | about 48 s per first land; **≈670 s/week, ≈15-21 s per code land** | (82 − 34) × 14 first runs per week. *Theoretical:* buildinfo paths are relative and file versions are content hashes, so a copy should carry over; not tested |
| Cross-process same-tree skip (the token already records `"typecheck"` in `proof_set`) | **≈12 s per code land** (379 s/week) | 8 tsc re-runs in the window on a tree an earlier attempt had already passed |
| Project references on a warm worktree | **≤ ~4 s per run**, only if all Program + Bind work were avoided | The one-edit cost is Program + Bind (3.7-4.4 s) more than Check (1.1-2.0 s). Referenced projects need `composite` and declaration emit, which conflicts with the current single-project `noEmit`. Poor return for a restructure |
| TypeScript 7 native checker | Unmeasured | `open.md:3204`: a side-by-side `typescript-7: npm:typescript@7.0.2` alias was "still NOT RUN" |

**The real driver of typecheck time is load and repetition.** Warm tsc is 14 s at load <40 and 64 s at ≥220. It runs 2.3 times per code land because of CAS retries.

---

## (e) Avoidable seconds per code land

**Population.** 32 landed code units in the window (branch attempts grouped up to the attempt that landed, with at least one union or full round). Values are per-unit sums across rounds; the unit averages 2.4 rounds.

| Stage | Mean s | p50 s | Runs per land | Source |
|---|---|---|---|---|
| reconcile | 3 | 2 | 2.4 | `reconcile_s` |
| typecheck | 138 | 86 | 2.3 | `tsc_s` |
| reso-land queue (union only, k=1) | 103 | 0 | n/a | `sem_wait_s` |
| land-time suite (union or full) | 356 | 188 | 2.2 | `suite_s` |
| push (hook full suite + gates + network) | 369 | 182 | 2.0 | `push_s`; hook ≈ push − 4 s = 361 mean |
| **Total verify-stage spend** | **970** | **468** | | |

**Lever 1: remove one copy of the duplicated suite.**
- **1a. Drop the land-time union and keep the hook's full suite as the verdict.** Saves suite plus queue: **356 + 103 = 459 s mean** (188 p50). No land-time coverage is lost, because the hook runs a superset on the same tree.
- **1b. Keep the union and let the hook skip on a green union token.** This requires relaxing §3.4's `mode=="full"` condition. It saves the hook's copy, about **361 s mean** (178 p50). Land-time coverage narrows to union plus a verifier that is not currently scheduled.
- **1c. The design's W3b.** Run the full suite once before the push and have the hook skip on the full-mode token. The per-round suite rises by about +63 s (215 against 152 p50), and each push drops about 163 s. Net ≈ −(2.0 × 180) + (2.2 × 63) ≈ **−220 s mean**, plus the smaller race window described below.

**Lever 2: path-key the 23 shell-out harness specs** (188 s test phase, 53% of the full suite). Run them when the diff touches `scripts/**`, not on every run. Their SUTs are bash scripts (`ship-land.test.ts:27-28` drives `scripts/ship-land.sh` over throwaway git fixtures), which a `src|lib|replicache` range cannot reach.
- **Under 1a** (they leave the hook's full run): −195 of ~480 worker-s ≈ 40% of each hook suite. About 65-70 s × 2.0 pushes ≈ **130-145 s mean.**
- **Under 1b** (they leave the union): −195 of ~380 worker-s ≈ 50%. About 78 s × 2.2 rounds ≈ **170 s mean.**
- **Coverage.** A scripts-only range currently runs **no** unit suite at land or in the hook (`ship-land.sh:629`, `pre-push:69`). These specs therefore run only when unrelated app code lands, and can then convict that land. Path-keying moves them to the ranges that can break them. It adds suite time to scripts-only lands, which the operator's "never add to landing load" ruling constrains (`ship-land.sh:653-657`).

**Lever 3: typecheck.** Seeded buildinfo (≈15-21 s) plus a same-tree skip (≈12 s) ≈ **30 s mean.**

**Total, first order:**
- Path 1a+2+3: 459 + ~140 + ~30 ≈ **~630 s of 970 s mean (≈65%)**.
- p50 basis: 188 + ~70 + ~15 ≈ **~275 of 468 s**.
- Path 1b+2+3: ≈ 560 s mean, with narrower coverage.

**Second order (a model, not a measurement): a shorter push window means fewer lost races.**
- Of 66 code pushes, **25 (38%) lost the compare-and-set race on `main`**: 18 non-fast-forward and 7 `cannot lock ref`. All of them had already paid the hook's full suite; 35 rejected code pushes consumed 6,931 s of push time. Of 48 non-code pushes, 3 (6%) lost the race.
- Treat racing lands as a Poisson process over the window from reconcile to ref update (about 419 s p50). That gives λ ≈ 1/880 s. For a non-code window of about 45 s, the model predicts a 5% race rate, against 6% observed.
- Taking the union and its queue out of that window (1a, about 204 s per round) gives P(race) ≈ 22%, and expected attempts fall from 1.61 to 1.28 (−21%). That is about another **~70 s** per code land on the remaining spend.

---

## The 6 rounds where the union passed and the hook's full suite failed

These are land.log rows with `push_tail` "unit tests failed".

| Rounds | What happened | Evidence | Verdict |
|---|---|---|---|
| 3 × `sec-w6-w4a7b-deaction` (02:54Z, load 148; 03:46Z, load 35; 03:52Z, load 21) | `scripts/__tests__/qa-nightly-probe.test.ts` bound fixed ports 31411-31415. A concurrent sibling suite held them, causing EADDRINUSE. The spec **is** always-run and had passed in the union. | Commit `0c0b1b37c` message: "it rejected 3 of W4a-7b's 4 land attempts, all else green" | **Environment false red in the hook** |
| 1 × `sec-w1d-livehrole` (19:30Z, load 320) | The union ran 151 files (always 149 + the 2 diff specs, including `venueRoleActions.test.ts`) and passed. The session transcript shows a 392-file run with 1 failed file and FAIL lines for `venueRoleActions.test.ts`. | land.log, `git show cdcbe4e94`, transcript `cba35be4…jsonl` | Same spec passed in the union and failed in the hook at load 320: likely a flake, **not** a selector miss (not fully verified) |
| 2 × `sec-w1a-opbuilder` (18:53Z, load 275; 19:17Z, load 135) | Cause not recoverable: `push_tail` keeps only 3 lines, and no transcript failure was found | none | **Unresolved** |

**What this means:** in this window the hook's full suite added two to three environment or flake rejections; no case shows it catching a real regression the union missed. The 2 unresolved rounds keep this from being proven.

---

## Alternatives considered and ruled out

- **`forceRerunTriggers` or a vitest `project` in place of the generated list.** Ruled out by the generator's own header: `forceRerunTriggers` is all-or-nothing (`presubmit-always.ts:26-27`).
- **`--assumeChangesOnlyAffectDirectDependencies` for tsc.** Refuted in-repo at 1.00× (`open.md:1360`).
- **Trimming the tsc Program by excluding `scripts/`.** 1.18-1.32× (−1.0 to −1.5 s), but it is a coverage trade that stops checking those files; the doc escalated it rather than taking it (`open.md:1359`).
- **Raising workers above 4.** The cap is load-bearing: the 2026-08-05 memory panic and fork-start starvation (`vitest.config.ts:56-101`).
- **Blaming jsdom for the suite's cost.** Refuted by the class totals in (b): jsdom is 20 s of test phase against 188 s shell-out and 117 s DB-fixture.

## Uncertainties and blockers

- **Per-file cache values** are the last run in each worktree at mixed loads, test phase only. The union/full ratio cross-checks (0.79 modelled against 0.75-0.81 observed) and the tests-phase sums (354 s against 353 s in the 09-19 verify run) agree, but import cost per file is not separable.
- **Hook suite time is inferred** as push_s − 4 s. It includes general-slot queueing (k=3) and the hook's other gates, which take about 4 s on non-code pushes.
- **Lever 2's wall-time savings are modelled** from worker-time at an effective parallelism of 2.7-3.4, not measured.
- **The Poisson race model has one out-of-sample check** (non-code pushes, n=48).
- **land.log was growing during analysis.** Counts can differ by ±2 rows between tables (for example, union n=63 against 65).
- **Verifier runs from 09-07 to 09-09 predate the load sampler.** Their loads are land.log v2 `load1` values from within about 30-60 minutes.
