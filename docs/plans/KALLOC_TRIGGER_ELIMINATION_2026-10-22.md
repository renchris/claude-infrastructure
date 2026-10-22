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

### W0+W1 measure and point fixes — open
### W2 agent-context-sync harness — routed
### W3 infra test suites — waiting on T-1
### W4 call sites — waiting on W3
### W5 loop — waiting on W1
