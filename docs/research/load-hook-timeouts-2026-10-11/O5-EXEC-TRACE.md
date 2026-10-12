# O5 — who spawns ~30k processes a minute (exec trace, 2026-10-12)

**Answer: not the hooks.** In a 30 s root `eslogger exec` capture (22:47:24–22:47:54Z, 15,920 execs ≈ 31.8k/min), about 84% of all execs came from Claude Bash-tool sessions running the agent-context-sync repo's tests in its `b13/r5-*` worktrees, and all Claude Code hooks together were about 3–5%. Wave 3 (lead-crash watchdog to one kqueue watcher; PostToolUse consolidation) is therefore low value and stays parked.

| Source | Execs / 30 s | Share | What |
|---|---|---|---|
| agent-context-sync worktrees `b13/r5-e`, `r5-p`, `r5-rb`, `r5-b`, `r5-ra`, `r5-a` | ≈13,550 | ≈84% | three sessions alone 69%: `git` 5,675 (36% of the box), `xcodebuild` 771, `xcode-select` 227, plus `tr`/`sed`/`chmod` from its pytest fixtures |
| `scripts/postland-verify.sh` `shell_files()` | 1,173 | 7.4% | `$(head -1 …)` per tracked file, every verifier pass — **fixed** (builtin `read`, `tests/postland-shell-files.bats`) |
| every `~/.claude/hooks/*` script named in argv | ≈1,200 | ≈3–5% | largest single hooks ≈ 75 execs each (research-block, waiting-recycle, coldcompile-admit, memory-index-drain) |

Method: `o5-attribute.py <trace.jsonl>` (beside this file) groups each exec by cwd root, target binary, the script named in argv, and process session id; output `o5-attribution-2026-10-12T2247Z.txt`. Session leaders were read with single-pid `ps -p`: sids 30345/19028 are Claude Bash-tool `zsh -c` shells; sid 98498 is `postland-verify.sh --run-if-needed` (3h16m old at the time).

Caveats: one 30 s sample at the time it was taken (load ~25-60 then, not the 400-600 of the original investigation), so the mix during a hook-timeout storm may differ; the share for hooks counts only execs whose argv names a hook path (their child `jq`/`git` calls are attributed by binary, under the session's cwd).

Implication for the plan: the lever on spawn rate is concurrency of agent-context-sync test runs (O1's `PYTEST_XDIST_AUTO_NUM_WORKERS=3` cap reaches part of it; the `git`/`xcodebuild` calls per test are that repo's own fixture cost), not further hook work. Capture tooling: `/tmp/loadinv/o5-exec-trace.sh` (askpass + one root call; stop with SIGTERM — a non-interactive background job ignores SIGINT, which left the first capture running for 30+ min).
