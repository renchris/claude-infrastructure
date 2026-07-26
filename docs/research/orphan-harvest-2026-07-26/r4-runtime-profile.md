# r4-runtime-profile  (session 6b143fcc-60b2-418a-9007-816068b710ad)

Harvested 2026-07-26 from disk after lead a3f68174 self-closed leaving this teammate orphaned.
Last assistant turn: 2026-07-25T22:59:11.042Z
Total records: 310

---


## turn @ 2026-07-25T22:53:18.023Z

Running one cheap empirical probe to convert my static parallel-safety claim into evidence.

## turn @ 2026-07-25T22:57:51.718Z

No SendMessage tool in this context — delivering the report as my final output.

# Gate runtime profile — `bats tests/` (R4)

**Conditions (timings are RELATIVE, not absolute).** Machine load avg at start `15.10`, peaked `26.64/32.87`, ended `16.33`. 24–30 concurrent users. macOS, 10 cores, bats-core 1.13.0. Worktree `/private/tmp/wt-gate-reliability` @ `fix/gate-reliability`. **No file edited, nothing committed.**

## Headline

| Metric | Value |
|---|---|
| Suites | **118** `.bats` files (brief said 117) |
| Tests | **1,588** (brief said ~1,579) |
| Serial sum of individual runs | **1,710.2s = 28.5 min** |
| Loop wall (incl. harness) | 1,713s → harness overhead **2.8s total** |
| Mean / median per suite | 14.49s / **4.25s** |
| p75 / p90 / p95 / max | 9.92s / 17.94s / 35.87s / **628.51s** |
| Failed suites | **1** (`cc-reaper.bats`) — **flake, green on retry** |

**The distribution is pathologically concentrated:** 1 suite = 36.8% of total; top-5 = 54.0%; top-10 = 64.0%. The 65 suites under 5s together cost **141.2s = 8.3%**.

## Distribution

| Bucket | Suites | Cumulative |
|---|---|---|
| <1s | 11 | 11 |
| 1–2s | 28 | 39 (<2s) |
| 2–5s | 26 | 65 (<5s) |
| 5–15s | 33 | 98 (<15s) |
| 15–30s | 12 | 110 (<30s) |
| 30–60s | 4 | 114 |
| **>60s** | **4** | 118 |

## Failures + retry outcomes

**1. `cc-reaper.bats` — FLAKE (confirmed).**
- Main pass: `rc=1`, 628.51s, 1/78 failed — `not ok 12 finished (stamped) + landed + idle>settle + --reap`.
- Mechanism: **external SIGTERM**, not an assertion. `bats-exec-file: line 232: 77163 Terminated: 15`, failing inside helper `mock_classify` (`tests/cc-reaper.bats:129`). No `BATS_TEST_TIMEOUT` is configured anywhere in the repo, so bats did not send it.
- **Retry: `rc=0`, 78/78 pass, 254.88s.** Test 12 green.
- **Root cause NOT established.** Candidates and their disqualifying evidence: (a) *my measurement harness* — a tool-call timeout fired SIGTERM at ~15:21 while cc-reaper was mid-run; **but** the parent `run.sh` survived to completion, which a process-group kill would not permit; (b) *repo-side killer* — only one `pkill` exists in the whole tree (`scripts/reaper-e2e.sh:24`, manual-only), so not this; (c) transient tmpdir/write failure — disk is 31% full, no evidence. **Treat as an open item for the flake census (R3), not as a solved one.**

**2. `land-lock.bats` — REAL load/parallel-sensitive flake, found by the adversarial parallel probe (below), with a one-line fix.**
- Serial: green (4.25s). Under 4-way parallel: `not ok … DEAD holder reaped — acquires`.
- Root cause, `tests/land-lock.bats:59`:
  ```bash
  sleep 1 & dead=$!; kill "$dead" 2>/dev/null; wait "$dead" 2>/dev/null || true
  ```
  The `kill` is **unguarded**. When scheduling delay exceeds 1s (routine at load 16 with 4 bats processes), `sleep 1` has already exited, `kill` returns 1, and bats' errexit fails the test. The `wait` is guarded; the `kill` is not. Five lines earlier (`:54`) the *same idiom* is correctly written `kill "$live" 2>/dev/null || true`. **Fix: append `|| true` to line 59.**
- Side observation: bats emitted **both** `not ok 100` and `ok 100` for that test and the plan count mismatched (`1..167` vs 168 result lines), yet the invocation still exited `rc=1`. Worth a look if the redesign depends on bats exit codes under multi-file invocation.

## Per-file invocation overhead — it is NOT the explanation

- Measured floor: 5 runs of a 1-test empty suite → **0.147s** mean (0.142–0.153).
- 118 invocations × 0.147 = **~17.3s ≈ 1.0%** of the 1,710s sum. Loop harness adds 2.8s.
- **So sum-of-individual ≈ full-run + ~1%. Sharding costs essentially nothing.**
- The 28.5 min vs the doc's ~15 min is **machine load, not overhead**. Corroborated on identical work: `cc-reaper.bats` = **628.5s at load ~26 → 254.9s at load ~16** (**2.47×**). Every number below carries roughly that elasticity. Note also `docs/research/desk-audit-2026-07-18/p12-coverage.md:4` measured **305 tests / 31 files** on 2026-07-18 — the corpus is now **118 files / 1,588 tests** (198 commits touched `tests/` since 2026-07-15). If the ~15 min figure predates that growth, it is stale in the other direction too.

## Why the slow suites are slow — sleeps vs real work

**None of the top-5 are sleep-bound. All five are subprocess-fork-bound.** Proof that backgrounded sleeps are free: `mail-ack-consume.bats` has a `sleep 30 &` and runs in **1.48s**.

| # | Suite | s | tests | s/test | Cause |
|---|---|---|---|---|---|
| 1 | cc-reaper | 628.5 | 78 | 8.06 | **Real work.** `setup()` builds **5 real git repos** (`mkrepo`×4 + `mksquashland`, multi-commit + reset) *per test* × 78. Microbenchmarked at **1.36s × 78 ≈ 106s** for the simplified subset (true cost higher). Remaining ~6s/test = 78 `bin/cc-reaper` invocations. Its 4 `sleep 60` are **backgrounded PID fixtures killed immediately after `run`** — zero cost. |
| 2 | waiting-recycle | 81.1 | 95 | 0.85 | **Real work, and efficient.** 95 tests, 907 lines, no sleeps. Slow only by test count. Leave alone. |
| 3 | comms-drain-activate | 79.4 | 14 | 5.67 | **Real work.** Each test runs the activation script over JSON fixtures (jq + backup/restore churn). No sleeps. |
| 4 | lead-supervisor | 78.1 | **5** | **15.61** | **Real work, and 5× REDUNDANT.** All 5 tests run `bash scripts/lead-supervisor.sh --selftest` (the full 36+-check supervisor-e2e) and then grep *different strings out of the same output*. |
| 5 | cc-inbox-guard | 57.1 | 12 | 4.76 | **Real work.** 12 × `$G sweep`. No sleeps. |

**Actual blocking sleeps are a minor, mid-pack cost:** `cc-await-ping.bats` = 7 blocking sleeps ≈ 8s of its 13.2s (61%); `cc-run.bats` ≈ 4s of 15.65s. Everything else (`land-lock`, `desk-invariant`, `cc-respawn`, `lead-deathwatch`, `mail-ack-consume`) uses `sleep N &` as a live-PID fixture — non-blocking.

## Proposals

### (a) FAST lane — 24 suites, 59.7s, covers the highest-churn assets

Selected by greedy churn-density (90-day commit churn of the test file + its name-matched asset, per second of runtime), budget 60s:

```
handoff-fire-tab-window-typing  handoff-fire-validate  handoff-fire-payload-lint
handoff-fire-focus  handoff-fire-inject  handoff-fire-account-sweep
handoff-fire-completion-push  handoff-teardown-marker  notify-back
claude-accounts  cc-crash-report  lead-crash-watchdog  payload-lint
desk-assert-wiring  rotate-autonomy-logs  agent-teams-enforce
pre-session-validate  boot-resume-launch  session-end  deploy-parity
claude-kimi  mailbox-drain  exit-deadline  teammate-auto-shutdown
```
Total **59.7s**, 399 churn-points covered. It fully covers `scripts/handoff-fire.sh` — **the single most-modified asset in the repo (42 commits/90d)** — for 34.8s.

**Honest limitation, and it is the crux:** a *static* <60s lane **cannot** include the next four highest-churn assets, because their suites are the four heavyweights — `bin/cc-reaper` (churn 41 → 628s), `bin/cc-classify` (25 → 55.8s), `hooks/waiting-recycle.sh` (22 → 81.1s), `scripts/lead-supervisor.sh` (18 → 78.1s). **The most-touched code has the slowest tests.** So the fast lane is only sound as a *changed-path-selected* lane, and it is only viable at all if the heavyweights are optimized first (see (c)). A blind static fast lane would silently stop gating `cc-reaper` — the most-edited file in the repo.

### (b) 4-shard split — makespan is pinned at 10.5 min by one file

LPT bin-packing on measured seconds:

| Shard | Wall | Suites |
|---|---|---|
| 1 | **628.5s (10.5 min)** | `cc-reaper.bats` **alone** |
| 2 | 360.3s (6.0 min) | 39 suites |
| 3 | 360.7s (6.0 min) | 39 suites |
| 4 | 360.7s (6.0 min) | 39 suites |

**Sharding alone buys 28.5 → 10.5 min, and not one second more, until `cc-reaper.bats` is split.** Excluding it, the other 117 balance perfectly at 270s/shard (4.5 min) — so `cc-reaper` split into 4 files of ~20 tests each yields a **~6.5 min balanced makespan**. Full shard membership is in `/tmp/gate-profile/` (`results.tsv`, `rank.tsv`, per-suite logs in `logs/`).

**Two hard constraints on the shard design:**
1. **`bats --jobs` is unavailable** — it requires GNU `parallel` or `rush`; neither is installed (`parallel not found`). Also no `flock`. Shard by running N background `bats <file-list>` processes, or `brew install parallel` first. This **resolves the open question at `GATE_RELIABILITY_2026-07-25.md:90`.**
2. **Speedup on a loaded box is far below N.** Empirically, the 65 fast suites: 141.2s serial → **83.5s at 4-way parallel = 1.69×, not 4×**. At load ~16 on 10 cores the box is already saturated. Budget shards on ~1.7–2× realized, not 4×.

**Parallel-safety audit (this fills `GATE_RELIABILITY_2026-07-25.md:91` "parallel-safety of the 117 suites unaudited"):**
- *Static — clean.* Every suite that writes under `$HOME/.claude` sandboxes `HOME` first (`teammate-auto-shutdown.bats:19`, `handoff-teardown-marker.bats:17`, `session-end.bats:16`). The 60+ `/tmp/...` occurrences (`cc-reconcile.bats` etc.) are **string literals used as fake session cwd values in JSON**, not filesystem writes. **Zero** suites run `git` against the real repo working tree (35 suites use git, all in `BATS_TEST_TMPDIR`). No fixed ports, no shared lock dirs (`CC_REAPER_LOCKDIR`, `LAND_LOCK_DIR`, `LAND_LOG` all overridden per-test).
- *Empirical — one defect found.* 4-way parallel over the 65 fast suites: **607 ok in parallel vs 607 ok serially — identical test count, no lost/duplicated coverage, no state collision.** But one **timing** flake surfaced (`land-lock.bats:59`, above). **So the hazard class is timing races under contention, not shared-state collision** — which is the opposite of what the static audit predicted, and cheaper to fix.

### (c) Optimization levers, ranked by seconds returned per line changed

| # | Change | Saves | Risk |
|---|---|---|---|
| 1 | **Split `cc-reaper.bats`** (1,032 lines / 78 tests) into 3–4 files | unblocks sharding: **10.5 → ~6.5 min** makespan | none (mechanical) |
| 2 | **Hoist `cc-reaper` git fixtures** into `setup_file()` — build the 5 repos once into a template, `cp -R` per test | ~100–160s of 628s | low; tests that mutate need their own copy |
| 3 | **Hoist `lead-supervisor` `--selftest`** into `setup_file()`, cache output, let the 5 tests grep the cache | **78.1 → ~15.6s (−62s)** | none — the 5 tests already assert on identical output |
| 4 | `kill … \|\| true` at `land-lock.bats:59` | removes a real flake | none |
| 5 | Replace `cc-await-ping`'s 7 blocking sleeps with poll-until-condition | ~8s of 13.2s | low |
| 6 | Audit the other 21 suites that invoke a `--selftest`/e2e harness for the same redundancy as #3 (`cc-inbox-guard` 57s, `desk-invariant` 27.1s, `cc-teardown` 14.5s are the next candidates) | unquantified | low |

Items 1–3 alone plausibly take the serial suite from **28.5 → ~24 min** and the 4-shard makespan from **10.5 → ~6 min**, before any test-impact mapping.

### Bonus: `BATS_TEST_RETRIES` semantics — confirmed empirically (answers R7's open question at `:88-89`)

- **`BATS_TEST_RETRIES=1 bats file.bats` (env) does NOT work.** `bats-exec-file:10` hard-sets `export BATS_TEST_RETRIES=0`, clobbering the inherited value. Probed: flaky test still `not ok`.
- **Setting it inside the file works.** `setup_file() { export BATS_TEST_RETRIES=2; }` → probed flaky test retried and reported `ok 1`. Retry return code is `BATS_RETRY_RETURN_CODE=126` (`bats-exec-file:9`), driven by `bats_run_test_with_retries` (`:232-240`).
- **Implication for the redesign:** a global retry policy cannot be applied from the `/ship` command line. It requires either a per-file `setup_file` edit across 118 files, a shared helper sourced by every suite, or a wrapper that re-invokes failed *files*. File-level re-invocation is the cheapest given per-file overhead is only 0.147s.

## Blockers / uncertainties

1. **`cc-reaper`'s SIGTERM is unexplained.** Do not close it as "load flake" — the evidence contradicts the two obvious mechanisms. It may indicate the gate can be false-RED'd by an external signal, which is a reliability defect in its own right.
2. **All absolute numbers carry ~2.5× load elasticity.** Use the *relative* weights for shard design; re-measure on a quiet box before publishing an SLA.
3. **Not run:** a full single-invocation `bats tests/` under these conditions (one pass only, per brief), so the sum-vs-full-run comparison rests on the 0.147s invocation-floor measurement rather than a same-conditions A/B.
4. **Churn is a proxy for "most-touched", not for risk.** The fast-lane selection should be cross-checked against R1's test-impact mapping before it gates anything.

## Full table (118 rows, sorted desc)

Artifacts: `/tmp/gate-profile/results.tsv` (raw), `logs/*.log` (per-suite output), `logs/cc-reaper.RETRY.log`, `rank.tsv` (churn), `par-{a,b,c,d}.log` (parallel probe).

| # | Suite | s | tests | s/test | Result |
|---|---|---|---|---|---|
| 1 | cc-reaper.bats | 628.51 | 78 | 8.06 | **FAIL rc=1 → retry PASS 254.88s** |
| 2 | waiting-recycle.bats | 81.10 | 95 | 0.85 | pass |
| 3 | comms-drain-activate.bats | 79.41 | 14 | 5.67 | pass |
| 4 | lead-supervisor.bats | 78.07 | 5 | 15.61 | pass |
| 5 | cc-inbox-guard.bats | 57.07 | 12 | 4.76 | pass |
| 6 | cc-classify.bats | 55.77 | 52 | 1.07 | pass |
| 7 | cc-reconcile.bats | 35.87 | 27 | 1.33 | pass |
| 8 | land-gate-cas.bats | 30.02 | 8 | 3.75 | pass |
| 9 | desk-invariant.bats | 27.10 | 13 | 2.08 | pass |
| 10 | boot-resume.bats | 21.48 | 15 | 1.43 | pass |
| 11 | completion-assert.bats | 20.16 | 17 | 1.19 | pass |
| 12 | handoff-fire-completion-push.bats | 18.80 | 6 | 3.13 | pass |
| 13 | cc-notify.bats | 17.94 | 27 | 0.66 | pass |
| 14 | claude-accounts-core.bats | 17.17 | 33 | 0.52 | pass |
| 15 | anti-deference-nudge.bats | 16.89 | 35 | 0.48 | pass |
| 16 | lr-select.bats | 16.86 | 21 | 0.80 | pass |
| 17 | cc-dispatch.bats | 16.50 | 12 | 1.38 | pass |
| 18 | cc-discover.bats | 16.44 | 18 | 0.91 | pass |
| 19 | ship-land.bats | 16.36 | 17 | 0.96 | pass |
| 20 | cc-run.bats | 15.65 | 7 | 2.24 | pass |
| 21 | install-wire-hooks.bats | 14.76 | 7 | 2.11 | pass |
| 22 | desk-land.bats | 14.72 | 18 | 0.82 | pass |
| 23 | cc-teardown.bats | 14.52 | 8 | 1.81 | pass |
| 24 | cc-wave-plan.bats | 14.25 | 13 | 1.10 | pass |
| 25 | cc-digest.bats | 14.25 | 22 | 0.65 | pass |
| 26 | cc-await-ping.bats | 13.20 | 11 | 1.20 | pass |
| 27 | lr-reset-poller.bats | 13.02 | 17 | 0.77 | pass |
| 28 | reset-hard-shadow-allow.bats | 11.64 | 15 | 0.78 | pass |
| 29 | cc-backlog.bats | 10.42 | 41 | 0.25 | pass |
| 30 | delivery-verify.bats | 10.15 | 8 | 1.27 | pass |
| 31 | desk-recycle-durable.bats | 9.92 | 9 | 1.10 | pass |
| 32 | dod-persist.bats | 9.89 | 19 | 0.52 | pass |
| 33 | desk-assert.bats | 9.24 | 7 | 1.32 | pass |
| 34 | cc-route.bats | 8.89 | 8 | 1.11 | pass |
| 35 | handoff-fire-account-sweep.bats | 8.76 | 14 | 0.63 | pass |
| 36 | cc-respawn.bats | 8.53 | 8 | 1.07 | pass |
| 37 | fire-engagement.bats | 8.50 | 23 | 0.37 | pass |
| 38 | payload-lint-tool-parity.bats | 8.38 | 5 | 1.68 | pass |
| 39 | operator-readout.bats | 8.23 | 18 | 0.46 | pass |
| 40 | cc-announce.bats | 8.17 | 10 | 0.82 | pass |
| 41 | lead-deathwatch.bats | 7.59 | 5 | 1.52 | pass |
| 42 | handoff-disposition.bats | 7.45 | 24 | 0.31 | pass |
| 43 | lr-reset-poller-consolidate.bats | 7.13 | 10 | 0.71 | pass |
| 44 | cc-audit.bats | 6.73 | 26 | 0.26 | pass |
| 45 | wrap-ledger.bats | 6.68 | 11 | 0.61 | pass |
| 46 | cc-teardown-safety-gate.bats | 6.49 | 7 | 0.93 | pass |
| 47 | session-continue.bats | 6.34 | 21 | 0.30 | pass |
| 48 | cc-recover-safeguard.bats | 5.98 | 12 | 0.50 | pass |
| 49 | cc-wait.bats | 5.83 | 8 | 0.73 | pass |
| 50 | boundary-handoff.bats | 5.80 | 11 | 0.53 | pass |
| 51 | gate-manifest.bats | 5.72 | 33 | 0.17 | pass |
| 52 | handoff-selfclose.bats | 5.39 | 9 | 0.60 | pass |
| 53 | reap-guard.bats | 5.21 | 11 | 0.47 | pass |
| 54 | stranded-sweep.bats | 4.95 | 8 | 0.62 | pass |
| 55 | land-verify.bats | 4.92 | 5 | 0.98 | pass |
| 56 | teammate-auto-shutdown.bats | 4.87 | 6 | 0.81 | pass |
| 57 | cc-close-attrib.bats | 4.73 | 9 | 0.53 | pass |
| 58 | fire-autonomy.bats | 4.62 | 23 | 0.20 | pass |
| 59 | completion-push.bats | 4.45 | 5 | 0.89 | pass |
| 60 | land-lock.bats | 4.25 | 9 | 0.47 | pass (**flakes at 4-way parallel — see above**) |
| 61 | handoff-fire-inject.bats | 4.24 | 7 | 0.61 | pass |
| 62 | push-send.bats | 4.13 | 8 | 0.52 | pass |
| 63 | handoff-splitright.bats | 4.05 | 10 | 0.40 | pass |
| 64 | cc-permission-beacon.bats | 4.03 | 12 | 0.34 | pass |
| 65 | autonomy-sweep.bats | 4.03 | 8 | 0.50 | pass |
| 66 | task-quality-gate.bats | 3.99 | 10 | 0.40 | pass |
| 67 | cc-upgrade-gate.bats | 3.92 | 8 | 0.49 | pass |
| 68 | session-registry.bats | 3.62 | 14 | 0.26 | pass |
| 69 | claude-latest-stderr.bats | 3.32 | 4 | 0.83 | pass |
| 70 | mailbox-drain.bats | 3.25 | 17 | 0.19 | pass |
| 71 | desk-arm-live.bats | 2.78 | 7 | 0.40 | pass |
| 72 | cc-idl.bats | 2.76 | 16 | 0.17 | pass |
| 73 | lead-reconciler.bats | 2.37 | 5 | 0.47 | pass |
| 74 | cc-decide.bats | 2.37 | 18 | 0.13 | pass |
| 75 | idl-abstain-alarm.bats | 2.20 | 11 | 0.20 | pass |
| 76 | effort-parity.bats | 2.13 | 8 | 0.27 | pass |
| 77 | power-policy.bats | 2.06 | 16 | 0.13 | pass |
| 78 | team-orphan-reaper.bats | 2.01 | 8 | 0.25 | pass |
| 79 | mailbox-forward.bats | 2.00 | 13 | 0.15 | pass |
| 80 | lead-crash-watchdog.bats | 1.97 | 11 | 0.18 | pass |
| 81 | context-econ.bats | 1.96 | 17 | 0.12 | pass |
| 82 | settings-drift.bats | 1.95 | 7 | 0.28 | pass |
| 83 | wait-contract-lint.bats | 1.94 | 8 | 0.24 | pass |
| 84 | rm-safe-allowlist.bats | 1.86 | 12 | 0.15 | pass |
| 85 | desk-brief-ssot.bats | 1.76 | 14 | 0.13 | pass |
| 86 | cc-unattended-ask-guard.bats | 1.71 | 14 | 0.12 | pass |
| 87 | session-end.bats | 1.65 | 7 | 0.24 | pass |
| 88 | claude-kimi.bats | 1.62 | 13 | 0.12 | pass |
| 89 | activation-watch.bats | 1.61 | 7 | 0.23 | pass |
| 90 | agent-teams-enforce.bats | 1.55 | 8 | 0.19 | pass |
| 91 | claude-accounts.bats | 1.54 | 7 | 0.22 | pass |
| 92 | gate-classify.bats | 1.49 | 20 | 0.07 | pass |
| 93 | mail-ack-consume.bats | 1.48 | 5 | 0.30 | pass |
| 94 | ship-rail-push-allow.bats | 1.47 | 8 | 0.18 | pass |
| 95 | cc-blockers.bats | 1.43 | 8 | 0.18 | pass |
| 96 | find-plan-list-open.bats | 1.41 | 8 | 0.18 | pass |
| 97 | desk-register.bats | 1.41 | 13 | 0.11 | pass |
| 98 | settings-dedup-stop.bats | 1.39 | 10 | 0.14 | pass |
| 99 | plan-index.bats | 1.38 | 12 | 0.11 | pass |
| 100 | rotate-autonomy-logs.bats | 1.22 | 11 | 0.11 | pass |
| 101 | deploy-parity.bats | 1.14 | 8 | 0.14 | pass |
| 102 | notify-back.bats | 1.11 | 9 | 0.12 | pass |
| 103 | lr-team-audit.bats | 1.11 | 3 | 0.37 | pass |
| 104 | validate-plan-structure.bats | 1.09 | 8 | 0.14 | pass |
| 105 | kimi-frontend-ab.bats | 1.05 | 6 | 0.18 | pass |
| 106 | handoff-fire-focus.bats | 1.05 | 8 | 0.13 | pass |
| 107 | page-damp.bats | 1.03 | 10 | 0.10 | pass |
| 108 | pre-session-validate.bats | 0.96 | 5 | 0.19 | pass |
| 109 | exit-deadline.bats | 0.87 | 8 | 0.11 | pass |
| 110 | task-helpers-scope.bats | 0.85 | 7 | 0.12 | pass |
| 111 | payload-lint.bats | 0.82 | 10 | 0.08 | pass |
| 112 | handoff-fire-payload-lint.bats | 0.79 | 6 | 0.13 | pass |
| 113 | handoff-teardown-marker.bats | 0.76 | 7 | 0.11 | pass |
| 114 | boot-resume-launch.bats | 0.65 | 5 | 0.13 | pass |
| 115 | handoff-fire-validate.bats | 0.59 | 3 | 0.20 | pass |
| 116 | handoff-fire-tab-window-typing.bats | 0.56 | 7 | 0.08 | pass |
| 117 | desk-assert-wiring.bats | 0.51 | 8 | 0.06 | pass |
| 118 | cc-crash-report.bats | 0.43 | 4 | 0.11 | pass |

Stopped after one full pass + the sanctioned `cc-reaper` retry + the parallel-safety probe, per brief. Worktree untouched: no edits, no commits.

## turn @ 2026-07-25T22:59:11.042Z

**Note:** `SendMessage` is not exposed in this subagent context (ToolSearch finds no such tool — the harness delivers my final message to you directly). Delivering here.

# Gate runtime profile — `bats tests/` (R4)

## Load at run time (timings are RELATIVE, not absolute)

`uptime` at start: **`15:09 up 13 days, 26 users, load averages: 15.10 12.96 12.42`** · peaked **`26.64 / 32.87`** mid-run · end **`16.33 / 15.35`**. macOS, 10 cores, bats-core 1.13.0, worktree `/private/tmp/wt-gate-reliability` @ `fix/gate-reliability`. **No file edited, nothing committed.**

## Raw totals

| Metric | Value |
|---|---|
| Suites | **118** `.bats` files (brief said 117) |
| Tests | **1,588** (brief said ~1,579) |
| Serial sum of individual runs | **1,710.2s = 28.5 min** |
| Loop wall incl. harness | 1,713s → harness overhead **2.8s total** |
| Mean / median | 14.49s / **4.25s** |
| p75 / p90 / p95 / max | 9.92s / 17.94s / 35.87s / **628.51s** |
| Failed suites | **1** (`cc-reaper.bats`) — flake, green on retry |

**Concentration is the headline:** 1 suite = **36.8%** of total · top-5 = **54.0%** · top-10 = 64.0% · top-20 = 74.1%. The 65 suites under 5s together are **141.2s = 8.3%**.

| Bucket | Suites | Cumulative |
|---|---|---|
| <1s | 11 | 11 |
| 1–2s | 28 | 39 (<2s) |
| 2–5s | 26 | 65 (<5s) |
| 5–15s | 33 | 98 (<15s) |
| 15–30s | 12 | 110 (<30s) |
| 30–60s | 4 | 114 |
| **>60s** | **4** | 118 |

## Failed / flaked suites + retry outcomes

**1. `cc-reaper.bats` — FLAKE confirmed.** Main pass `rc=1`, 628.51s, 1/78 failed (`not ok 12 finished (stamped) + landed + idle>settle + --reap`). Not an assertion failure — an **external SIGTERM**: `bats-exec-file: line 232: 77163 Terminated: 15`, dying inside helper `mock_classify` (`tests/cc-reaper.bats:129`). No `BATS_TEST_TIMEOUT` exists anywhere in the repo, so bats did not send it. **Retry: `rc=0`, 78/78 pass, 254.88s.**
**Root cause NOT established** — flag for R3, don't close it. (a) my harness's tool-call timeout fired SIGTERM at ~15:21 while the suite ran — *but the parent `run.sh` survived*, which a process-group kill forbids; (b) repo-side killer — only one `pkill` in the tree (`scripts/reaper-e2e.sh:24`, manual-only); (c) transient write failure — disk 31% full, no evidence.

**2. `land-lock.bats` — REAL parallel/load flake, found by my adversarial probe, one-line fix.** Green serially (4.25s); `not ok … DEAD holder reaped — acquires` under 4-way parallel. Cause at **`tests/land-lock.bats:59`**:
```bash
sleep 1 & dead=$!; kill "$dead" 2>/dev/null; wait "$dead" 2>/dev/null || true
```
The `kill` is **unguarded**. Under contention >1s elapses, `sleep 1` has already exited, `kill` returns 1, bats errexit fails the test. The identical idiom five lines earlier (`:54`) is correctly written `kill "$live" 2>/dev/null || true`. **Fix: append `|| true` to line 59.** Side note: bats emitted both `not ok 100` and `ok 100` for it and the plan mismatched (`1..167` vs 168 result lines) while still exiting `rc=1` — worth checking if the redesign trusts bats exit codes on multi-file invocations.

## Per-file invocation overhead — NOT the explanation

- Floor measured: 5 runs of a 1-test empty suite = **0.147s** mean (0.142–0.153).
- 118 × 0.147 = **~17.3s ≈ 1.0%** of 1,710s. Loop harness adds 2.8s.
- **Sum-of-individual ≈ full-run + ~1%. Sharding is effectively free.**
- The 28.5 min vs your ~15 min is **load, not overhead** — proven on identical work: `cc-reaper.bats` **628.5s at load ~26 → 254.9s at load ~16 (2.47×)**. Also note `docs/research/desk-audit-2026-07-18/p12-coverage.md:4` measured **305 tests / 31 files** on 2026-07-18 vs **118 files / 1,588 tests** today (198 commits touched `tests/` since 07-15) — if ~15 min predates that growth it is stale in the other direction too.

## Why the slow suites are slow — **none of the top-5 are sleep-bound**

Proof backgrounded sleeps are free: `mail-ack-consume.bats` has `sleep 30 &` and runs in **1.48s**.

| Suite | s | tests | s/test | Cause |
|---|---|---|---|---|
| cc-reaper | 628.5 | 78 | 8.06 | **Real work.** `setup()` builds **5 real git repos per test** × 78 (microbenchmarked ≈1.36s × 78 ≈ 106s for the simplified subset). Its 4 `sleep 60` are backgrounded PID fixtures killed right after `run` — zero cost. |
| waiting-recycle | 81.1 | 95 | 0.85 | Real work, **efficient** — slow only by test count. Leave alone. |
| comms-drain-activate | 79.4 | 14 | 5.67 | Real work — jq/backup churn per test. No sleeps. |
| lead-supervisor | 78.1 | **5** | **15.61** | **Real work, 5× REDUNDANT** — all 5 tests run `scripts/lead-supervisor.sh --selftest` (full 36-check e2e) then grep different strings from the *same* output. |
| cc-inbox-guard | 57.1 | 12 | 4.76 | Real work — 12 × `$G sweep`. No sleeps. |

Actual blocking sleeps are mid-pack and minor: `cc-await-ping` ≈8s of 13.2s (61%), `cc-run` ≈4s of 15.65s. All others (`land-lock`, `desk-invariant`, `cc-respawn`, `lead-deathwatch`, `mail-ack-consume`) use `sleep N &` as live-PID fixtures.

## (a) FAST lane — 24 suites, **59.7s**

Greedy by churn-density (90-day churn of test file + name-matched asset, per second):
```
handoff-fire-tab-window-typing  handoff-fire-validate  handoff-fire-payload-lint
handoff-fire-focus  handoff-fire-inject  handoff-fire-account-sweep
handoff-fire-completion-push  handoff-teardown-marker  notify-back  claude-accounts
cc-crash-report  lead-crash-watchdog  payload-lint  desk-assert-wiring
rotate-autonomy-logs  agent-teams-enforce  pre-session-validate  boot-resume-launch
session-end  deploy-parity  claude-kimi  mailbox-drain  exit-deadline
teammate-auto-shutdown
```
Fully covers `scripts/handoff-fire.sh` — **the most-modified asset in the repo (42 commits/90d)** — for 34.8s.

**Crux limitation:** a *static* <60s lane **cannot** include the next four highest-churn assets, because their suites are the four heavyweights — `bin/cc-reaper` (churn 41 → 628s), `bin/cc-classify` (25 → 55.8s), `hooks/waiting-recycle.sh` (22 → 81.1s), `scripts/lead-supervisor.sh` (18 → 78.1s). **The most-touched code has the slowest tests.** Sound only as a *changed-path-selected* lane, and only after (c). A blind static lane would silently stop gating the repo's most-edited file.

## (b) 4-shard split — makespan pinned at 10.5 min by one file

| Shard | Wall | Suites |
|---|---|---|
| 1 | **628.5s (10.5 min)** | `cc-reaper.bats` **alone** |
| 2 | 360.3s (6.0 min) | 39 |
| 3 | 360.7s (6.0 min) | 39 |
| 4 | 360.7s (6.0 min) | 39 |

**Sharding alone buys 28.5 → 10.5 min and not one second more until `cc-reaper.bats` is split.** Excluding it the other 117 balance perfectly at **270s/shard (4.5 min)** → splitting cc-reaper into 4 files of ~20 tests gives a **~6.5 min balanced makespan**. Full membership lists in `/tmp/gate-profile/`.

**Two hard constraints:**
1. **`bats --jobs` is unavailable** — needs GNU `parallel` or `rush`; neither installed (`parallel not found`); no `flock` either. Shard via N background `bats <file-list>` processes, or `brew install parallel`. *(Resolves the open question at `GATE_RELIABILITY_2026-07-25.md:90`.)*
2. **Realized speedup ≪ N on a loaded box:** the 65 fast suites went 141.2s serial → **83.5s at 4-way = 1.69×, not 4×**. Budget ~1.7–2×.

**Parallel-safety audit** *(fills `GATE_RELIABILITY_2026-07-25.md:91` "parallel-safety unaudited")*: **static — clean.** Every suite writing under `$HOME/.claude` sandboxes `HOME` first (`teammate-auto-shutdown.bats:19`, `handoff-teardown-marker.bats:17`, `session-end.bats:16`); the 60+ `/tmp/...` hits are **string literals used as fake session cwds in JSON**, not writes; **zero** suites run git against the real worktree (35 use git, all in `BATS_TEST_TMPDIR`); no fixed ports or shared lock dirs. **Empirical — 607 ok parallel vs 607 ok serial (identical coverage, no state collision), but one timing flake surfaced** (`land-lock.bats:59`). **Hazard class is timing races under contention, not shared state** — the opposite of what the static audit predicted, and cheaper to fix.

## (c) Optimization levers, ranked

| # | Change | Saves | Risk |
|---|---|---|---|
| 1 | **Split `cc-reaper.bats`** (1,032 lines / 78 tests) into 3–4 files | makespan **10.5 → ~6.5 min** | none |
| 2 | **Hoist cc-reaper git fixtures** to `setup_file()` + `cp -R` per test | ~100–160s of 628s | low |
| 3 | **Hoist `lead-supervisor --selftest`** to `setup_file()`, tests grep cached output | **78.1 → ~15.6s (−62s)** | none |
| 4 | `\|\| true` on `land-lock.bats:59` | kills a real flake | none |
| 5 | `cc-await-ping`: 7 blocking sleeps → poll-until | ~8s of 13.2s | low |
| 6 | Audit the other 21 `--selftest`-invoking suites for the #3 redundancy (`cc-inbox-guard` 57s, `desk-invariant` 27.1s, `cc-teardown` 14.5s next) | unquantified | low |

1–3 alone: serial **28.5 → ~24 min**, 4-shard makespan **10.5 → ~6 min**, before any test-impact mapping.

## Bonus for R7 — `BATS_TEST_RETRIES` semantics, empirically confirmed

- **Env var does NOT work.** `bats-exec-file:10` hard-sets `export BATS_TEST_RETRIES=0`, clobbering the inherited value. Probed: flaky test still `not ok`.
- **In-file works.** `setup_file() { export BATS_TEST_RETRIES=2; }` → probed flaky test retried, reported `ok 1`. Retry code `BATS_RETRY_RETURN_CODE=126` (`bats-exec-file:9`), driver `bats_run_test_with_retries` (`:232-240`).
- **Implication:** a global retry policy **cannot** be set from the `/ship` command line. Options: per-file `setup_file` across 118 files, a shared sourced helper, or a wrapper that re-invokes failed *files* — the last is cheapest since per-file overhead is only 0.147s.

## Timing table — top 40 (full 118 rows in `/tmp/gate-profile/results.tsv`)

| # | Suite | s | tests | s/test |
|---|---|---|---|---|
| 1 | cc-reaper | **628.51** | 78 | 8.06 (**FAIL→retry pass 254.88**) |
| 2 | waiting-recycle | 81.10 | 95 | 0.85 |
| 3 | comms-drain-activate | 79.41 | 14 | 5.67 |
| 4 | lead-supervisor | 78.07 | 5 | 15.61 |
| 5 | cc-inbox-guard | 57.07 | 12 | 4.76 |
| 6 | cc-classify | 55.77 | 52 | 1.07 |
| 7 | cc-reconcile | 35.87 | 27 | 1.33 |
| 8 | land-gate-cas | 30.02 | 8 | 3.75 |
| 9 | desk-invariant | 27.10 | 13 | 2.08 |
| 10 | boot-resume | 21.48 | 15 | 1.43 |
| 11 | completion-assert | 20.16 | 17 | 1.19 |
| 12 | handoff-fire-completion-push | 18.80 | 6 | 3.13 |
| 13 | cc-notify | 17.94 | 27 | 0.66 |
| 14 | claude-accounts-core | 17.17 | 33 | 0.52 |
| 15 | anti-deference-nudge | 16.89 | 35 | 0.48 |
| 16 | lr-select | 16.86 | 21 | 0.80 |
| 17 | cc-dispatch | 16.50 | 12 | 1.38 |
| 18 | cc-discover | 16.44 | 18 | 0.91 |
| 19 | ship-land | 16.36 | 17 | 0.96 |
| 20 | cc-run | 15.65 | 7 | 2.24 |
| 21 | install-wire-hooks | 14.76 | 7 | 2.11 |
| 22 | desk-land | 14.72 | 18 | 0.82 |
| 23 | cc-teardown | 14.52 | 8 | 1.81 |
| 24 | cc-wave-plan | 14.25 | 13 | 1.10 |
| 25 | cc-digest | 14.25 | 22 | 0.65 |
| 26 | cc-await-ping | 13.20 | 11 | 1.20 |
| 27 | lr-reset-poller | 13.02 | 17 | 0.77 |
| 28 | reset-hard-shadow-allow | 11.64 | 15 | 0.78 |
| 29 | cc-backlog | 10.42 | 41 | 0.25 |
| 30 | delivery-verify | 10.15 | 8 | 1.27 |
| 31 | desk-recycle-durable | 9.92 | 9 | 1.10 |
| 32 | dod-persist | 9.89 | 19 | 0.52 |
| 33 | desk-assert | 9.24 | 7 | 1.32 |
| 34 | cc-route | 8.89 | 8 | 1.11 |
| 35 | handoff-fire-account-sweep | 8.76 | 14 | 0.63 |
| 36 | cc-respawn | 8.53 | 8 | 1.07 |
| 37 | fire-engagement | 8.50 | 23 | 0.37 |
| 38 | payload-lint-tool-parity | 8.38 | 5 | 1.68 |
| 39 | operator-readout | 8.23 | 18 | 0.46 |
| 40 | cc-announce | 8.17 | 10 | 0.82 |

*Rows 41–118 run 7.59s → 0.43s (tail: `cc-crash-report` 0.43, `desk-assert-wiring` 0.51, `handoff-fire-tab-window-typing` 0.56, `handoff-fire-validate` 0.59, `boot-resume-launch` 0.65).*

**Artifacts:** `/tmp/gate-profile/results.tsv` (raw TSV: suite, secs, rc, tests, fails) · `logs/*.log` (per-suite output) · `logs/cc-reaper.RETRY.log` · `rank.tsv` (churn-weighted) · `par-{a,b,c,d}.log` (parallel probe).

**Open uncertainties:** (1) cc-reaper's SIGTERM is unexplained — a gate that can be false-RED'd by an external signal is a reliability defect in itself; (2) all absolutes carry ~2.5× load elasticity — use relative weights, re-measure quiet before any SLA; (3) no same-conditions single-invocation `bats tests/` A/B (one pass only, per brief) — the overhead claim rests on the 0.147s floor measurement; (4) churn is a proxy for "most-touched", not risk — cross-check the fast lane against R1's test-impact map before it gates anything.

Done — no further work. Worktree untouched.
