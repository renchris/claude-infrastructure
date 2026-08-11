========== ANSWER ==========

I’ll map the launchd plists first, then follow only the invoked scripts and cross-check tests before making any coverage claims. After that I’ll rank the concrete findings by blast radius and likelihood.The launchd surface is about thirty plists, including three staged files. I’m extracting the invoked commands now so the audit stays scoped to the plists and their direct scripts.One broad search produced too much noise, so I’m narrowing it to mechanical facts: plist command lines, scripts with matching basenames, and test files that mention those subjects.The session-search jobs stand out because their launchd command lines pipe through `head` and append to a side log. I’m reading the hook and its tests before deciding whether that is a real fail-open path or already covered.The sweep script itself is reasonably guarded and has tests for the stale-lock and cadence behavior. The wrapper around it is not tested in the same way: the only plist assertion I found for that job checks `StartInterval`, not the `ProgramArguments` failure semantics.Next I’m checking the installed-copy versus checkout-path split. That is a design concern only if the repo itself shows launchd runs one surface while tests and source changes validate another.I’m also checking the persistent daemons separately from the periodic jobs. The risk shape is different: for daemon plists, small script-loop mistakes are amplified by `KeepAlive` and foreground scheduling.Lead-supervisor already has extensive guards around external commands and page delivery. I’m not going to report those as bugs; the plist scheduling choice is only worth mentioning if it is not pinned by tests and has a concrete load failure.I’m reading the destructive janitor wrappers next (`worktree-gc-infra` and `devserver-gc`). For these, the highest-risk bugs are usually activation gates that silently downgrade apply mode or error handlers that make launchd see success.The repo has a known staged/live split for LaunchAgents. I’m checking whether the current tests make that split safe, because a staged plist that is invisible to parity is a recurring inertness class, not a one-off typo.The worktree wrapper has strong behavioral tests, but I found one apparent code/test disagreement around the kill switch and observe mode. I’m treating that as uncertain unless the implementation comments make the intended behavior clear.The worktree wrapper’s intended observe behavior is actually implemented; the earlier disagreement was a different script. I’m dropping that as a finding and focusing on uncovered devserver-gc wrapper behavior.I found a clearer fail-open in the session sweep itself: it exits successfully before its own DB initialization path when the DB file is absent. I’m checking the tests for a missing-DB case before I make that coverage statement.I have enough to answer without editing anything. I’m going to keep the report to the highest-impact three findings, one per requested category, and include the exact searches where I’m making a coverage claim.**(1) DESIGN FLAWS**

1. **Staged launchd jobs are hidden from activation and from the generic manifest coverage path. Recurrence: inert-but-unreported jobs.**

   Failure scenario: a maintainer adds `launchd/staged/com.claude.foo.plist` for a C10 job and forgets a `fleet.manifest` row. The staged directory is intentionally outside `install.sh`’s top-level `launchd/*.plist` activation glob, but `tests/cc-fleet.bats` also only checks top-level plists. Result: the job is neither installed nor generically required to be declared, so it can remain built, tested, and unscheduled.

   Blast radius: any staged launchd mechanism, especially credential, deleting, or reaping jobs. Likelihood: high; the repo already documents this recurrence for relogin and several later plists.

   Sources: [launchd/staged/com.claude.relogin.plist:20-29](/private/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-FYHJ3S/repo/launchd/staged/com.claude.relogin.plist:20), [tests/cc-fleet.bats:535-539](/private/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-FYHJ3S/repo/tests/cc-fleet.bats:535), [tests/cc-fleet.bats:594-599](/private/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-FYHJ3S/repo/tests/cc-fleet.bats:594), [launchd/fleet.manifest:153-159](/private/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-FYHJ3S/repo/launchd/fleet.manifest:153)

**(2) LATENT BUGS**

2. **`session-index-sweep.sh` can report success while doing no indexing.**

   Failure scenario A: `~/.claude/session-index.db` is missing after deletion, restore, first install, or bad state cleanup. The script exits `0` at the “Fast exit if no DB” guard before reaching its own `session_index_init_db` call. Wrong outcome: launchd sees a healthy tick, but missed transcripts are never swept.

   Failure scenario B: the launchd wrapper pipes the sweep through `head -20` without `pipefail`. If the sweep prints diagnostics and exits nonzero, the pipeline status is still the `head`/append status, so launchd records success.

   Blast radius: session search and retention freshness; stale/missing transcript index rows can persist indefinitely. Likelihood: medium; missing DB/helper or wrapper failures are not the normal path, but this is exactly the class of launchd fail-open the repo has repeatedly guarded elsewhere.

   Sources: [launchd/com.claude.session-search-sweep.plist:7-14](/private/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-FYHJ3S/repo/launchd/com.claude.session-search-sweep.plist:7), [hooks/session-index-sweep.sh:22-32](/private/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-FYHJ3S/repo/hooks/session-index-sweep.sh:22), [hooks/session-index-sweep.sh:74-76](/private/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-FYHJ3S/repo/hooks/session-index-sweep.sh:74)

   Coverage searches:  
   `rg -n "missing.*(SESSION_INDEX_DB|session-index\\.db|DB)|no DB|Fast exit|rm -f .*session-index\\.db|SESSION_INDEX_DB.*missing" tests --glob '*.bats' --glob '*.test.sh'` found no covering test.  
   `rg -n "head -20|head -50|sweep-daemon|backfill-scheduled|session-search-sweep.*ProgramArguments|session-search-backfill.*ProgramArguments|ProgramArguments.*session-search" tests --glob '*.bats' --glob '*.test.sh'` found no session-search wrapper failure-semantics test.

**(3) VERIFICATION GAPS**

3. **`devserver-gc` tests cover the decision module, not the launchd-armed wrapper.**

   Failure scenario: remove `export DEVGC_ACT=1` from the plist, or break the wrapper’s `RC=3 → oracle-blind exit 3` mapping. `scripts/devserver-census.sh` tests still pass because they exercise the module directly. Wrong outcome: the hourly launchd job silently downgrades to dry-run observe mode, or an inoperable `lsof` path is not surfaced correctly by the scheduled job.

   Blast radius: idle Next dev servers keep accumulating, or the reaper’s liveness oracle failure is misreported. Likelihood: medium-high; the arming decision is a single string in the plist, and the runner explicitly defaults to dry-run when it is absent.

   Sources: [launchd/com.claude.devserver-gc.plist:19-23](/private/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-FYHJ3S/repo/launchd/com.claude.devserver-gc.plist:19), [launchd/com.claude.devserver-gc.plist:44-55](/private/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-FYHJ3S/repo/launchd/com.claude.devserver-gc.plist:44), [scripts/devserver-gc-run.sh:45-61](/private/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-FYHJ3S/repo/scripts/devserver-gc-run.sh:45), [tests/devserver-census.bats:61-124](/private/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-FYHJ3S/repo/tests/devserver-census.bats:61)

   Coverage search:  
   `rg -n "devserver-gc-run|DEVGC_ACT|com\\.claude\\.devserver-gc|devserver-gc\\.plist|verdict=oracle-blind" tests --glob '*.bats' --glob '*.test.sh'` found only a `cc-fleet.bats` comment hit, no executable test of the plist or wrapper.

========== SOURCES ==========
  - hooks/session-index-sweep.sh:22-32
  - hooks/session-index-sweep.sh:74-76
  - private/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-FYHJ3S/repo/hooks/session-index-sweep.sh:22
  - private/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-FYHJ3S/repo/hooks/session-index-sweep.sh:74
  - private/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-FYHJ3S/repo/scripts/devserver-gc-run.sh:45
  - scripts/devserver-gc-run.sh:45-61
