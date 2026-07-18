# P12 — Verification Coverage Map (asset ↔ test ↔ execution)

**Scope (frozen):** what is *proven* vs merely *written* across bin/ (24), hooks/ (47), scripts/ (51).
**Method:** fixed-string reverse-index of every asset against the test corpus (tests/*.bats · scripts/*e2e*.sh · *gate*.sh · *lint*.sh · hooks/tests/ · test-overwrite-guard.sh · smoke-test.sh · plan-phase-scan-tests/), plus LIVE runs: full `bats tests/` (305 tests), all 8 un-hold gates, reaper-horizon-lint, `bash -n` sweep. Empirical (ran/read) unless tagged (inferred).

**THREE DISTINCT TRUTHS — labeled per row:** `test EXISTS` ≠ `test PROVES the effect` ≠ `test RUNS automatically`. All three are separately false somewhere in this stack.

## Headline
- **bats suite is GREEN today:** 305 tests, exit 0 (`bats tests/` 2026-07-18). What is written passes.
- **NO automatic test execution at commit.** No `.git/hooks/pre-commit`, no `.github/workflows`, no Makefile/package.json, no launchd test job. Tests run **only at LAND** via the `/ship` command gate (`.claude/commands/ship.md:39`: `shellcheck` + `bats tests/` + `bash -n` + `py_compile *.py`). A bare `git commit`/`git push` bypasses everything.
- **The 7 e2e harnesses, 9 un-hold gates, 6 lints are MANUAL** — `/ship` runs `bats tests/` only, not `scripts/*e2e*.sh` / `*gate*.sh` / `*lint*.sh`.
- **51 hooks FIRE automatically** (8 events in `~/.claude/settings.json`) but their **tests do not** run automatically — operational ≠ verified.
- **~52 of ~98 testable components have NO test.** Dominant hole: hooks (37/47 uncovered).
- **The one live autonomous loop:** launchd `com.chrisren.cc-reaper` runs `cc-reaper sweep --reap` every 300s (operational, pre-gated; not a test).

---

## 1. THE MATRIX

Legend — Effect column: **PROVES** (discriminating fixture, durable product) · **surface** (exit/echo only) · **n/a** (component, not a test). Run: **land** = `/ship` bats gate · **manual** · **launchd** · **event** (fires as a hook) · **never**.

### bin/ (24)
| Asset | Covering test/gate | State | Effect | Runs | Notes |
|---|---|---|---|---|---|
| cc-announce | cc-announce.bats, completion-push.bats | GREEN | PROVES | land+manual | operator push primitive (F1) |
| cc-await-ping | cc-await-ping.bats, cc-wait.bats | GREEN | PROVES | land+manual | |
| cc-bind | bind-gate-e2e.sh | UNKNOWN | surface | manual | e2e not gate-referenced; unrun this session |
| cc-board | *(gates mention only)* | UNKNOWN | n/a | never | no dedicated behavioral test → WEAK |
| cc-classify | **cc-classify.bats (20 tests)** | GREEN | **PROVES** | land | 7 causes + DEAD-successor refusal + Gap A/B discriminators |
| cc-context | telemetry-e2e.sh *(mention)* | UNKNOWN | surface | manual | horizon declared in reaper-horizon-lint only |
| cc-deathwatch-kqueue | — | **NONE** | none | never | **python3, no test**; L1 death-instant mechanism; ship `*.py` glob misses extensionless file |
| cc-notify | cc-notify.bats (+8 refs) | GREEN | PROVES | land | most-referenced primitive |
| cc-reaper | cc-reaper.bats, reaper-e2e.sh | GREEN(bats) | PROVES | land+**launchd** | the live `--reap` loop; e2e unrun this session |
| cc-respawn | cc-respawn.bats | GREEN | PROVES | land | |
| cc-route | cc-route.bats | GREEN | PROVES | land | |
| cc-run | cc-run.bats | GREEN | PROVES | land | |
| cc-sessions | session-registry.bats (+5) | GREEN | PROVES | land | registry reader |
| cc-teardown | cc-teardown.bats, reaper-e2e.sh | GREEN | PROVES | land | own gate re-run |
| cc-teardown-safety-gate.sh | cc-teardown-safety-gate.bats | GREEN | PROVES | land | |
| cc-wait | cc-wait.bats, wait-contract-lint.bats | GREEN | PROVES | land | |
| claude-accounts | lr-reset-poller.bats *(mock)* | PARTIAL | surface | land | exercised via mock; no dedicated suite |
| claude-bump-models | claude-lint-models.sh *(lint)* | WEAK | n/a | manual | static-lint only |
| claude-kimi | claude-kimi.bats | GREEN | PROVES | land | |
| claude-latest | — | **NONE** | none | never | version launcher |
| claude-update | — | **NONE** | none | never | |
| claude-versions | smoke-test.sh *(partial)* | WEAK | surface | manual | pre-promote gate touches it |
| it2-wrapper | — | **NONE** | none | never | **iTerm2 keystroke API — handoff-fire depends on it; critical, untested** |
| browsermcp-wrapper.sh | — | **NONE** | none | never | out-of-desk-loop |

### hooks/ (47) — 8 covered, 2 weak, 37 uncovered. All wired ones FIRE on events (operational) regardless of test state.
| Asset | Covering test | State | Effect | Notes |
|---|---|---|---|---|
| anti-deference-nudge.sh | anti-deference-nudge.bats | GREEN | PROVES | emits {fired\|abstained} |
| backup-before-write.sh | **test-overwrite-guard.sh (26 scenarios)** | GREEN(manual) | PROVES | OVERWRITE GUARD; harness NOT in `/ship` (manual only) |
| boundary-handoff.sh | boundary-hook-e2e.sh | GREEN* | PROVES | *transitively via premortem B-2/B-3 |
| rm-safe-allowlist.sh | rm-safe-allowlist.bats | GREEN | PROVES | |
| session-deregister.sh | session-registry.bats | GREEN | PROVES | |
| session-register.sh | session-registry.bats, p8-e2e.sh | GREEN | PROVES | registry spine (P8) |
| validate-bash.sh | hooks/tests/validate-bash.test.sh | UNKNOWN | surface | own harness; not in `/ship` (manual) |
| waiting-recycle.sh | **waiting-recycle.bats (30+ tests)** | GREEN | **PROVES** | rot-fires vs healthy-silent corpus + abstained IDL |
| session-continue.sh | never-stuck-gate.sh *(mention)* | WEAK | n/a | composition-gate reference only |
| teammate-auto-shutdown.sh | reaper-safety-gate.sh *(mention)* | WEAK | n/a | |
| **UNCOVERED (37)** | — | **NONE** | none | *fire on events, no test:* agent-teams-enforce, cache-expiry-tracker, cache-expiry-warning, check-edit-boundary, config-mirror-assert, frontier-spawn-gate, frontier-status, git-worktree-guard, harvest-skill-end, **lead-crash-watchdog**, **live-session-registry**, log-bash, memory-nudge, migrate-plans-index, notify, plan-agent-teams-default, plan-index-update, plan-pin-session, plan-version-commit, post-file-edit, pre-session-validate, **push-critical**, research-precognition-nudge, session-end, session-index-end, session-index-start, session-index-sweep, session-save-id, session-start, setup-plan-symlinks, setup-task-symlinks, **smart-bash-allowlist**, task-completed-index, task-mutation-index, task-quality-gate, teammate-checkpoint, validate-plan-structure |

### scripts/ (51) — split: TEST-HARNESS (is a test) vs COMPONENT (needs a test)
**Test-harness scripts (24) — these ARE the tests; none run automatically except transitively at `/ship` (bats only):**
- e2e (7): bind-gate-e2e, boundary-hook-e2e, handoff-selfclose-e2e, p8-e2e, reaper-e2e, supervisor-e2e, telemetry-e2e
- un-hold gates (9): comms-safety-gate, limit-reset-safety-gate, never-stuck-gate, premortem-gate, reaper-safety-gate, respawn-safety-gate, route-safety-gate, session-lifecycle-safety-gate, wait-safety-gate
- lints (6): claude-lint-models, pane-id-lint, payload-lint, reaper-horizon-lint, s3b-lint, wait-contract-lint
- overwrite/version harnesses (2): test-overwrite-guard, smoke-test

| Component script | Covering test | State | Effect | Notes |
|---|---|---|---|---|
| completion-push.sh | completion-push.bats | GREEN | PROVES | F5 |
| exit-deadline.sh | exit-deadline.bats | GREEN | PROVES | F4 deadline tighten |
| handoff-disposition.sh | handoff-disposition.bats | GREEN | PROVES | |
| handoff-fire.sh | fire-autonomy + notify-back + handoff-splitright + cc-classify + waiting-recycle .bats + handoff-selfclose-e2e | GREEN | **PROVES** | heaviest coverage; pre_trust/notify-back/self-retire discriminators |
| kimi-frontend-ab.sh | kimi-frontend-ab.bats | GREEN | PROVES | |
| land-lock.sh | land-lock.bats | GREEN | PROVES | concurrent-land safety |
| lead-deathwatch.sh | lead-deathwatch.bats | GREEN | PROVES | |
| lead-reconciler.sh | lead-reconciler.bats | GREEN | PROVES | selftest RED-provable |
| lead-supervisor.sh | supervisor-e2e.sh | GREEN* | PROVES | *transitively via premortem B-1/S-3/S-3b/S-4 |
| limit-recover | lr-reset-poller.bats | PARTIAL | surface | poller path only |
| payload-lint.sh | payload-lint.bats | GREEN | PROVES | also a lint |
| plan-phase-scan.sh | plan-phase-scan-tests/run.sh | UNKNOWN | surface | own runner; not in `/ship` |
| reap-guard.sh | **reap-guard.bats + --selftest** | GREEN | **PROVES** | backdated-commit discriminator (R-b) |
| restore-file.sh | test-overwrite-guard.sh | GREEN(manual) | PROVES | overwrite recovery |
| stranded-sweep.sh | stranded-sweep.bats | GREEN | PROVES | |
| wait-contract-lint.sh | wait-contract-lint.bats | GREEN | PROVES | also a lint |
| **UNCOVERED (10)** | — | **NONE** | none | auto-revert-getAppState-patch, current-session-plan, find-plan, prune-backups, record-version, **restic-claude-archive-backup**(launchd), set-teammate-effort, **team-orphan-reaper**(orphan-worktree reaper), watch-claude-code-2118-hold(launchd), watch-getAppState-fix(launchd) |

**Coverage stats:** ~98 testable components (122 assets − 24 harness scripts). Well-covered ≈ 38 · weak/partial ≈ 7 · **NONE ≈ 52**. Hooks dominate the hole (37/47). bin critical-uncovered: it2-wrapper, cc-deathwatch-kqueue.

---

## 2. RED-BY-DESIGN / UN-HOLD REGISTRY (live-run 2026-07-18)
| Gate | Bars | State | Un-holds when |
|---|---|---|---|
| **premortem-gate.sh** (RUNTIME PHASE) | B-1/2/3, S-1/2/3/3b/4 | **RED — 7 met · 1 failed** | S-1 fails: reaper-horizon-lint flags `hooks/waiting-recycle.sh` UNDECLARED reaper-on-evidence. Un-holds when horizon declared + justified |
| **wait-safety-gate.sh** (NEVER-WAIT-ON-DEAD, L0–L4) | 13 criteria | **RED — 12 met · 1 failed** | L0 fails **only because it depends on premortem (p8/d2 not green)**. Same root as above |
| respawn-safety-gate.sh (RS-a..f, B1-a) | 2 | **GREEN** (0 failed) | met; activation-free (lead-invoked tooling) |
| route-safety-gate.sh (RT-a..f, B1-b) | 2 | **GREEN** | met; activation-free |
| reaper-safety-gate.sh (R-a/b/c) | 1 | **GREEN** | reap-guard selftest GREEN; deploy = C10 |
| comms-safety-gate.sh (F1..F5) | 5 | **GREEN** | met; wiring at C10 |
| limit-reset-safety-gate.sh (B1-d, LR) | 1 | **GREEN** | proven; plist + LR_POLLER_AUTOFIRE=1 = operator hand-steps |
| session-lifecycle-safety-gate.sh (CL/RP/TD) | 3 | **GREEN** | safe to activate; deploy = C10 |

**Whole runtime-phase un-hold is held RED by ONE undeclared horizon** (waiting-recycle.sh, added 6708aee). The gate is working as designed — it caught a new recycler that reaps on evidence without a declared horizon. 5 GREEN gates are "activation C10-queued" = built+proven, deployment pending. **Tension resolved:** the reaper launchd IS deployed (`sweep --reap`/300s) — the C10 operator step was taken for cc-reaper; safety rests on cc-classify (20 bats) + cc-teardown gate + reap-guard birth-grace.

---

## 3. EXECUTION TRUTH
- **Commit-time:** nothing. `.git/hooks/` empty (non-sample). No pre-commit framework.
- **CI:** none. `.github/workflows` empty; no Makefile / package.json / justfile / run-tests.sh.
- **Land-time (`/ship` only):** `shellcheck` changed *.sh + **`bats tests/`** + `bash -n` changed *.sh + `py_compile` changed *.py. Covers the 31 bats (305 tests). **Excludes** all 7 e2e harnesses, 9 gates, 6 lints. `*.py` glob **misses** extensionless python (`bin/cc-deathwatch-kqueue`).
- **launchd:** only `com.chrisren.cc-reaper` (`cc-reaper sweep --reap`, 300s) touches repo runtime — operational, not a test. Others: restic backup, getAppState/2118 watchers, screenshot-clipboard — none run tests.
- **Hooks:** 51 fire on 8 events (`~/.claude/settings.json`) — operational execution, zero test execution.
- **Net:** un-hold gates + e2e + lints run **only when a human/agent invokes them** (premortem-gate.sh:16 "Run it when someone proposes to un-hold"). No standing regression signal between lands.

---

## 4. RED-PROOF SPOT-CHECK (5 suites — do fixtures PROVE the effect?)
| Suite | Verdict | Discriminator (the case that MUST fail if detector breaks) |
|---|---|---|
| tests/cc-classify.bats | **PROVES** | DEAD-successor → NOT handed-off-lead (L77-82); dirty tree → owned-wait not finished (L102-108); coordination-abandoned reapable past horizon vs stays never-reap under horizon (L147/157); bridge-session false-positive guard (L84). Real git repos w/ `origin/main` ref = LANDED; DEAD pid=4000000>maxproc |
| tests/waiting-recycle.bats | **PROVES** | rot-tell fires @40% vs healthy narration silent @40% (L59/64); 9-msg rot corpus MUST-fire vs 10-msg healthy MUST-be-silent (L155/175); threshold 55 fires@60 silent@54; **abstained IDL record** (L232) proves didn't-fire≠never-evaluated |
| tests/notify-back.bats | **PROVES** | shasum before/after proves caller file NEVER mutated (L34-40); copy ≠ original (L42); trailer content asserted (L29) |
| tests/fire-autonomy.bats | **PROVES** | reads durable .claude.json product; canonicalized path stored NOT raw (L30-33); surgical merge preserves keys (L44-51); byte-identical idempotency (L53-59) |
| tests/reap-guard.bats | **PROVES** | **backdated `GIT_COMMITTER_DATE` so commit predates spawn → DEFER** (L41) vs commit-after-spawn → REAP (L33) — the exact effect-read-predicate-red-proof pattern; outcome-record durable-product assert (L47-54) |

**All 5 prove the EFFECT with discriminating fixtures + durable products** — no surface-only theater. Matches house discipline (effect-read-predicate-red-proof.md). No stdin-eating-guard anti-pattern found in any hook (adversarial grep, §7).

---

## 5. GAPS
| ID | Locus | FM | Sev | Scenario | Fix sketch |
|---|---|---|---|---|---|
| G-P12-1 | execution-truth (no pre-commit/CI) | 24x7 | **P0** | A broken detector lands via bare `git push` (bypasses `/ship`) or a mid-session commit; no regression signal until next manual land | Add pre-push git hook OR launchd nightly `bats tests/ && scripts/*e2e*.sh` with cc-notify on RED |
| G-P12-2 | e2e/gates/lints manual-only | 24x7 | **P0** | 7 e2e + 9 gates + 6 lints never run between lands; a regression in supervisor/telemetry/reaper spine is invisible | Fold `scripts/*e2e*.sh` + gates into a `make check` run by the same nightly/land path |
| G-P12-3 | bin/it2-wrapper | FM1 | **P0** | handoff-fire's keystroke API untested; a silent break = fires that never engage (cf. cold-worktree-fire race memory) | Add it2-wrapper.bats: dry-run keystroke composition + session-resolve |
| G-P12-4 | bin/cc-deathwatch-kqueue | FM1 | **P1** | python L1 death-instant mechanism, zero tests; ship `*.py` glob skips extensionless file so not even py_compile'd at land | Rename `.py` or add explicit py_compile; add a kqueue-fires-on-death fixture |
| G-P12-5 | hooks/ 37 uncovered | FM2 | **P1** | lead-crash-watchdog, live-session-registry, push-critical, git-worktree-guard, smart-bash-allowlist fire on every event untested; a silent hook failure degrades the desk invisibly | Prioritize the 5 named safety hooks; assert emit + exit-0-on-garbage-stdin |
| G-P12-6 | premortem S-1 (waiting-recycle horizon) | 24x7 | **P1** | runtime-phase un-hold held RED; waiting-recycle recycles on telemetry evidence without a declared horizon → could recycle a desk whose evidence the supervisor still needs | Declare waiting-recycle horizon in reaper-horizon-lint `$DECLARED` + justify vs 6000s floor |
| G-P12-7 | abstained==100% alarm | 24x7 | P2 | premortem SHIP-GATE requires alarm on inert-by-construction checks; emit side exists (boundary-handoff, anti-deference, waiting-recycle IDL) but no confirmed runtime ALARM wiring | Wire an IDL sweep that pages on abstained==100% over N≥10 |
| G-P12-8 | team-orphan-reaper.sh, restic backup | FM2 | P2 | orphan-worktree reaper + backup script untested; silent failure leaks worktrees / loses archives | Add smoke tests; assert dry-run enumerates before delete |

---

## 6. TASK CANDIDATES
| ID | Action | Acceptance | Depends-on |
|---|---|---|---|
| T-P12-1 | Add standing regression run (launchd nightly OR pre-push) executing `bats tests/` + all `scripts/*e2e*.sh` + gates, cc-notify on RED | RED suite pages the operator within one interval; artifact log written | — |
| T-P12-2 | Declare `hooks/waiting-recycle.sh` horizon in reaper-horizon-lint `$DECLARED` | reaper-horizon-lint GREEN → premortem-gate + wait-safety-gate flip GREEN | inspect waiting-recycle telemetry horizon |
| T-P12-3 | it2-wrapper.bats — keystroke composition + session-id resolution dry-run | ≥5 tests GREEN; covers `\r`-submit invariant | — |
| T-P12-4 | Make cc-deathwatch-kqueue land-gated: rename `.py` or add explicit py_compile; add death-fires fixture | `/ship` compiles it; 1 behavioral test GREEN | — |
| T-P12-5 | Safety-hook test batch: lead-crash-watchdog, live-session-registry, push-critical, git-worktree-guard, smart-bash-allowlist | each: emit assert + garbage-stdin→exit-0 | — |
| T-P12-6 | Fold test-overwrite-guard.sh + validate-bash.test.sh + plan-phase-scan-tests into the `/ship`/nightly run | all three execute in the standing gate | T-P12-1 |

---

## 7. ADVERSARIAL SELF-PASS
- *"Hooks fire but are untested — did I conflate run-state with test-state?"* → No; §3 separates them. 51 wired hooks = operational; test coverage is orthogonal and mostly absent.
- *"Did I assume the bats suite passes without running it?"* → Ran it: 305/305 GREEN, exit 0.
- *"Are the e2e harnesses actually green?"* → telemetry-e2e, p8-e2e, supervisor-e2e, boundary-hook-e2e are **transitively asserted GREEN** by the premortem/wait gates I ran (S-2/B-1/B-2/S-3). bind-gate-e2e, reaper-e2e, handoff-selfclose-e2e are **UNKNOWN** (not gate-referenced, unrun this session) — flagged, not assumed.
- *"stdin-eating-guard anti-pattern (blind-check-generators memory) in untested hooks?"* → grepped all 47 hooks for stdin-read + python-heredoc co-occurrence: **none**. Clean.
- *"Is the syntax-fail (cc-deathwatch-kqueue) real?"* → False positive: it's python3, not bash. Zero real shell syntax failures. But it surfaced a real gap (G-P12-4): untested + land-gate-skipped.
- *"Does 'activation C10-queued' mean the reaper isn't live?"* → No — resolved by reading the launchd plist: `cc-reaper sweep --reap`/300s IS deployed. The gate text lags the deployment.

## Uncertainties (explicit)
- e2e run-state for bind-gate-e2e / reaper-e2e / handoff-selfclose-e2e: **UNKNOWN** (not run this session; not gate-covered). [theoretical]
- Whether the abstained==100% ALARM is wired at runtime (emit side confirmed; alarm side not found). [theoretical]
- claude-accounts / limit-recover coverage is PARTIAL via mocks — real-path (network/keychain) unexercised. [empirical-partial]
- "Well-covered ≈38 / weak ≈7 / NONE ≈52" counts are ±3 at the harness/component boundary (some lints double as tested components). [derived]
- reaper launchd interval (300s) vs reaper-horizon-lint floor (600s sweep×10=6000s): the lint's "sweep" constant may differ from the launchd interval — not reconciled here. [theoretical]
