---
status: in-progress
---

# Stop setting off the #! kernel leak (2026-10-22)

Scope (frozen): cut this Mac's data.kalloc.1024 leak from ~0.93 to ≤0.3 GiB/day without the macOS 27
upgrade, by removing `#!` execs at their sources (trampoline for by-name stubs, call-site fixes, lints)
and a census loop that keeps it fixed; measured per phase.

Why: macOS 15.8.1 still keeps ~1.1 KiB per `#!` exec (measured 2026-10-21); the operator ruled no
macOS 27 until a release explicitly ships the fix (decision `a172a41d0d79`). The kernel bug itself is
out of our reach (SIP; `docs/research/kalloc-longterm-2026-10-21/kernel.md`).

Evidence: `docs/research/kalloc-longterm-2026-10-21/REPORT.md` (8 axes, each critiqued; census of
34,157 real `#!` execs in 63 min, 2026-10-21 23:51-00:54). Shares: test and rehearsal harnesses 81%
(one agent-context-sync `launchctl-stub` alone 29%), our production tools 18%, Homebrew/npm/git <1%.
A hook daemon cuts load, not the leak (`daemon.md`).

## Phase 0 — orchestration

| Wave | Locus | Owns | Content |
|---|---|---|---|
| W0+W1 measure and point fixes | S | `scripts/kalloc-exec-census.sh` (new), `bin/cc-await-ping`, the 60 `shasum` call sites, `hooks/lib/shasum-direct.sh`, `migrations/0012,0036` call lines, `scripts/c10-batch.sh`, `bin/cc-kitty-bin`, `bin/it2-kitty`, `bin/cc-resume-layout.sh`, `hooks/session-end.sh`, `lr-fire-resume.sh` | REPORT §3 Phase 0 (T-1 trampoline cost; census tool tracked with env stripped, bounded, filtered) and Phase 1 table, except `~/.zshrc` (operator dotfile) |
| W2 agent-context-sync harness | owner session `agent-context-sync-16` (its repo, its CLAUDE.md) | that repo's tests and `scripts/install.sh` hashing | REPORT §3 Phase 2; routed by message, not fired from here |
| W3 infra test suites | S, after W1's T-1 verdict | `tools/cc-shim/`, `vendor/bats-core`, `tests/lib/cc-stub.bash`, top-12 test files, lint R4 | REPORT §3 Phase 3 |
| W4 call sites and Mach-O entries | S, after W3 | `scripts/lib/cc-run.sh`, `scripts/lib/cc-common.sh`, `scripts/exec-form-lint.sh`, `bin/it2`, `bin/cc-qos-exec` | REPORT §3 Phase 4 |
| W5 keep-it-fixed loop | S, after W1 | capacity-alarm SLO rows | REPORT §3 Phase 5 |

Lead: session 551eb39b fires W0+W1 and routes W2, then recycles; W3-W5 fire from the successor once
W1's T-1 verdict is on disk. Operator calls, not built: `~/.zshrc:504,508` session-root change; T-0's
clean-lineage window (`open -n -a kitty`); off-box CI (money); a root census LaunchDaemon.

## Waves

### W0+W1 measure and point fixes — built 2026-10-22 (session kte-w01)

- **Census tool** `scripts/kalloc-exec-census.sh` (`1615ea04c`, `tests/kalloc-exec-census.bats`): one
  bounded `sudo -A gtimeout -s INT`, filtered in the stream to script execs and an allow-list of fields;
  the bats test feeds secrets through a stubbed eslogger and proves none reach disk. The 26 GB file of
  2026-10-21 was already gone when this ran (its dirs are 0700).
- **T-1: PASS.** L − B = +0.020 ± 0.017 per exec (95% CI −0.012..+0.053), 12 interleaved pairs of 3000,
  shebang-parsing trampoline, +2.2 ms per call (`e40c43b41`, `measure.md` § T-1). W3 and W4 are unblocked.
- **Point fixes:** cc-await-ping → `env bash cc-kqwait` (`db5828bfe`); cc-in-kitty via `/bin/sh`
  (`bdd199890`); kitty resolvers unwrap Homebrew's cask wrapper (`96d43d707`); it2-kitty runner and the
  lr-fire-resume `cc-close-attrib` root through their interpreter (`07ad2628e`); cc-settings-parity through
  python3 in all 26 migrations that call it and in c10-batch, not only the three lines the REPORT named
  (`1ab1a938a`); shasum → `/sbin/sha{256,1}sum` (teammate sha, plus `31730cb2a`); launchd plists, the plist
  lint arm and the installed-plist migration (teammate ld).
- **Not built, and why:** `~/.zshrc:504,508,705-706` (operator dotfile); the `technical-analysis` and
  `reso-management-app` project hooks (other repos); T-0 (needs the operator's clean-lineage window).
  Same `exec "$CC_PANE_RUNNER"` root also sits at `scripts/handoff-fire.sh:1318` and
  `scripts/limit-recover/lr-lib.sh:1338`, and the `reso-resume-one` callers in `bin/cc-resume-layout.sh`
  and `scripts/boot-resume-launch.sh` run it by path: left to W4 (call sites), sized by T-0.
### W2 agent-context-sync harness — routed
### W3 infra test suites — waiting on T-1
### W4 call sites — waiting on W3
### W5 loop — waiting on W1
