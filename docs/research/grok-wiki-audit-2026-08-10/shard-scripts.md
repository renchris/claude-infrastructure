========== ANSWER ==========

I’ll audit `scripts/` and `bin/` as the subject area, then use tests/docs only as context. I’ll first map the files and test references so any coverage claims are backed by repo-wide searches.The repo has a large shell-heavy operational surface: dozens of entrypoints in `bin/` and many gate/reaper/deploy scripts. I’m narrowing on shared control paths, gates, validators, and error handlers because those are where a single defect can repeatedly affect many commands.There is enough surface area that I’m going to split the audit mentally by subsystem: deployment/landing, session/process orchestration, and shared safety libraries. I’ll keep the final findings limited to defects grounded in lines I actually inspect.The runtime has real sub-agents available, and your prompt explicitly allowed delegation. I’m spawning three bounded read-only auditors for independent slices while I inspect shared paths locally.One recurring pattern is already visible: several tools write real JSON but then read it back with regex/sed/awk extractors. I’m checking whether that is just a constrained internal format or whether free-text fields can cross that reader boundary and change behavior.I’m also checking candidate findings against existing tests, because several files have unusually detailed regression suites. Anything already covered well won’t be reported as a verification gap, and anything intentionally fail-open needs to be wrong in a concrete scenario before I’ll call it a bug.A few tempting “fail-open” branches are explicitly tested as policy, so I’m not treating them as bugs. I’m looking instead for places where the code’s stated contract and the executable branch differ, or where tests only prove a producer wrote something but never prove the consumer can read it.The `deploy-live` path does have a dedicated suite, so I’m not going to claim it is untested wholesale. For verification gaps, I’m focusing on narrower missing assertions, like tests that validate JSON is written but never drive the affected reader path.The bus reader issue is stronger than a test gap: `bin/cc-bus` writes escaped JSON strings, then all human/bridge views read strings with patterns that stop at the first `"` byte. That means a message containing a quote is stored correctly but delivered/truncated incorrectly.I’m doing a final pass over the high-risk actuators, especially teardown/reaper/dispatch, to avoid over-indexing on one subsystem. The final answer will stay scoped to `scripts/` and `bin/`; hooks only appear where they are consumers/context for a `scripts/lib` finding.I’ve mapped the scripts/bin surface and found a few high-signal candidates. I’m letting the delegated scans finish so I can cross-check coverage claims before ranking the final three categories.One delegated scan turned up process-matching and timeout issues in the orchestration bins. I’m validating those against the actual source and test searches now so the final answer only includes findings I can ground directly.The respawn finding is real on the source lines: the matcher is literal-substring based, not token-boundary based. I’m checking whether existing Bats suites already exercise that failure mode before deciding whether it belongs as a bug, a verification gap, or both.Existing `cc-bus` tests prove the writer emits valid JSON for hostile text, but the consumer-side paths are still using regex extraction. That makes it a strong design finding and also a focused verification gap because the current test stops before the broken read path.The deployment knob issue is also confirmed: the comment says `0` disables either half, but the comparison treats `HOST_CUT_MAX=0` as “already at threshold.” I’m keeping that in the latent-bug bucket unless a stronger existing test contradicts it.Ranks are global, by blast radius x likelihood.

**(1) DESIGN FLAWS**

1. **Rank 1: `cc-bus` has a split-brain JSON contract: structured writer, regex readers.**  
   Recurrence: every new consumer has to remember which JSON escapes it cannot safely read. `json_escape` writes escaped strings, but `json_field`, `cmd_work`, `cmd_actors`, `cmd_inbox`, `cmd_drain`, and `cmd_offer` parse with `sed`/`awk` string matches.  
   Scenario: `cc-bus post peer 'he said "hi\there"\nthen...'` writes valid JSON, but `inbox`/`drain` read `body` only until the escaped quote and deliver/truncate the wrong text. `work --json` can also print unescaped evidence back into JSON.  
   Blast radius: off-box work offers, done evidence, inbox delivery, and actor/work summaries. Likelihood: high, because quotes/backslashes/newlines are normal human text and already appear in tests as valid producer input.  
   Evidence: [bin/cc-bus:191-195](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/bin/cc-bus:191), [bin/cc-bus:246-254](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/bin/cc-bus:246), [bin/cc-bus:313-317](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/bin/cc-bus:313), [bin/cc-bus:418-436](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/bin/cc-bus:418), [bin/cc-bus:595-608](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/bin/cc-bus:595).

2. **Rank 3: `deploy-live.sh` is a self-mutating deploy actuator with one-deploy-late post-merge behavior.**  
   Recurrence: fixes to any function parsed before the fast-forward cannot affect the deploy that lands them. The script documents this directly, then continues into `install.sh`, migrations, and host checks without re-exec.  
   Scenario: a commit fixes `host_checks` or migration convergence; the running process fast-forwards to that commit, but still executes the old in-memory function and files the old page/backlog outcome. The fix works only on the next deploy.  
   Blast radius: live deploy diagnostics, post-deploy host pages, migration convergence reporting. Likelihood: medium; it only fires when `deploy-live.sh` post-merge behavior changes, but this file is a central maintenance surface.  
   Evidence: [scripts/deploy-live.sh:1048-1069](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/deploy-live.sh:1048), [scripts/deploy-live.sh:1095-1121](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/deploy-live.sh:1095).

**(2) LATENT BUGS**

3. **Rank 2: `cc-relogin-poll` timeout cannot guarantee a timeout.**  
   Scenario: `CC_RELOGIN_POLL_TIMEOUT_S=10` and `cc-relogin` hangs while trapping/ignoring `TERM`. The watchdog sends only `TERM` to the direct child, then the parent waits unbounded; state and result logging happen only after `wait "$cp"` returns.  
   Blast radius: hourly launchd cadence can wedge on one account, stop attempt accounting, and overlap later ticks. Likelihood: medium-high; this is exactly an error-handler path around an auth automation child.  
   Evidence: [bin/cc-relogin-poll:1-4](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/bin/cc-relogin-poll:1), [bin/cc-relogin-poll:448-457](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/bin/cc-relogin-poll:448).

4. **Rank 4: `cc-respawn` member verification matches substrings, not argv tokens.**  
   Scenario: `verify-spawned --member api` sees a running process with `--agent-name api-worker`; `grep -F "--agent-name api"` returns a pid, so the tool declares the `api` successor live even though only `api-worker` exists. Conversely, `verify-stopped --member api` can fail forever because a prefix sibling is live.  
   Blast radius: respawn protocol can falsely mark GO delivered or block a valid respawn. Likelihood: medium; it requires shared prefixes, which are common in role-style names.  
   Evidence: [bin/cc-respawn:143-167](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/bin/cc-respawn:143), [bin/cc-respawn:183-195](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/bin/cc-respawn:183).

5. **Rank 5: `CC_DEPLOY_HOST_CUT_MAX=0` is documented as disable, but pages immediately.**  
   Scenario: operator sets `CC_DEPLOY_HOST_CUT_MAX=0` expecting to disable the cut-threshold half. On first no-verdict host run, `cn >= HOST_CUT_MAX` is true and `host_cut_page` fires immediately; cooloff logic also treats every row as past threshold.  
   Blast radius: deploy host-check paging/backlog noise and possible suite suppression contrary to operator intent. Likelihood: lower; it requires using the documented escape hatch.  
   Evidence: [scripts/deploy-live.sh:162-177](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/deploy-live.sh:162), [scripts/deploy-live.sh:335-340](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/deploy-live.sh:335), [scripts/deploy-live.sh:459-464](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/deploy-live.sh:459).

**(3) VERIFICATION GAPS**

6. **Rank 6: `cc-bus` hostile-string test stops at producer validity, so broken consumers stay green.**  
   Scenario: the current test loads the raw shard with Python and proves the body is valid JSON; it never calls `inbox`, `drain`, `offer`, `work --json`, or `actors --json` with that hostile body/evidence. The current regex-reader defect would still pass.  
   Blast radius: same as Rank 1. Likelihood: high because the test already creates the failing input shape.  
   Evidence: [tests/cc-bus.bats:79-88](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/tests/cc-bus.bats:79), [tests/cc-bus.bats:243-283](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/tests/cc-bus.bats:243).  
   Coverage search with no covering hit: `bash -lc 'shopt -s nullglob; rg -n "cc-bus.*(inbox|drain|offer|work --json|actors --json).*quote|(inbox|drain|offer|work --json|actors --json).*cc-bus.*quote|quotes.*(inbox|drain|offer|work --json|actors --json)|body containing quotes.*(inbox|drain)" tests/*.bats tests/*.test.sh'`

7. **Rank 7: host CUT tests cover default threshold and `COOLOFF=0`, not `CUT_MAX=0`.**  
   Scenario: the suite can pass while the documented `CC_DEPLOY_HOST_CUT_MAX=0` disable path is broken, because every threshold test uses the default max of 3 and the only zero-knob test sets `CC_DEPLOY_HOST_CUT_COOLOFF=0`.  
   Blast radius: missed regression on deploy-live’s operator escape hatch. Likelihood: medium-low; only maintainers changing cut logic or relying on the disable knob hit it.  
   Evidence: [tests/deploy-live.bats:575-591](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/tests/deploy-live.bats:575), [tests/deploy-live.bats:651-657](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/tests/deploy-live.bats:651).  
   Coverage search with no covering hit: `bash -lc 'shopt -s nullglob; rg -n "CC_DEPLOY_HOST_CUT_MAX=0|HOST_CUT_MAX=0|CUT_MAX=0|cut max.*0|0.*cut max|MAX.*disables" tests/*.bats tests/*.test.sh'`

8. **Rank 8: `cc-respawn` tests prove absence and exact presence, but not sibling-name ambiguity.**  
   Scenario: tests pass if `verify-spawned --member api` accepts `--agent-name api-worker`, because no test creates a prefix sibling and asks for the shorter member.  
   Blast radius: missed regression on respawn delivery truth. Likelihood: medium with prefix-style agent names.  
   Evidence: [tests/cc-respawn.bats:56-59](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/tests/cc-respawn.bats:56), [bin/cc-respawn:251-255](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/bin/cc-respawn:251).  
   Coverage search with no covering hit: `bash -lc 'shopt -s nullglob; rg -n "(cc-respawn|verify-spawned|verify-stopped).*(prefix|substring|token|agent-name.*abc|agent-name.*tm-|partial)|(prefix|substring|token|agent-name.*abc|agent-name.*tm-|partial).*(cc-respawn|verify-spawned|verify-stopped)" tests/*.bats tests/*.test.sh'`Late delegated results arrived after my answer. I’m going to validate the source lines myself and then provide a corrected consolidated audit, because several of these are likely higher-impact than the process-bin issues I ranked earlier.The late reports validate two especially important guard failures: `land-verify.sh` can return green on an invalid range, and two `ship-land` non-verdict branches route to tree-red despite their own message saying they are not tree claims. I’m checking the test coverage claims now.The migration race is less isolated than a normal missing lock because `deploy-live.sh` explicitly permits manual overlap and invokes migrations both before fetch and after advance. I’m also validating the worker-claim nested-CWD claim since that could be a hot-path collision gate.The coverage searches for the newly validated gaps came back empty for the specific failure modes: invalid land-verify ranges, AF_UNIX/TSV exit-2 routing, postland PID reuse, worker nested CWD, and cc-bus hostile-string consumers. I’m consolidating the ranking now.Late subagent results arrived after my first answer. This supersedes that ranking.

**(1) DESIGN FLAWS**

**Rank 3: `cc-bus` has a structured writer but regex readers.**  
Recurrence: every new consumer can silently diverge from the JSON contract. The writer escapes arbitrary strings, but readers extract fields with `sed`/`awk` patterns that stop at escaped quotes and do not unescape values.  
Scenario: `cc-bus post peer 'he said "hi\there"\nthen...'` writes valid JSON; `inbox` or `drain` reads a truncated `body`, and `work --json` can re-emit unescaped evidence as invalid JSON.  
Blast radius: off-box inbox, drain delivery, work ledger summaries, offers. Likelihood: high; human messages/evidence commonly contain quotes, backslashes, or newlines.  
Evidence: [bin/cc-bus:191](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/bin/cc-bus:191), [bin/cc-bus:246](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/bin/cc-bus:246), [bin/cc-bus:313](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/bin/cc-bus:313), [bin/cc-bus:373](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/bin/cc-bus:373), [bin/cc-bus:418](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/bin/cc-bus:418), [bin/cc-bus:595](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/bin/cc-bus:595).

**Rank 4: deploy migrations use a check-then-run ledger as the concurrency boundary.**  
Recurrence: idempotence is enforced after execution, not by an atomic claim before execution. `deploy-live.sh` explicitly has no run lock for manual `deploy-now` overlap, and migrations run both before fetch and after advance.  
Scenario: launchd deploy is in `migrations_converge`; operator runs `deploy-now`. Both see no `$STATE/applied/$name.json`, both run the same mechanical migration, then both record applied.  
Blast radius: shared live migration state. Likelihood: moderate; manual deploy overlap is explicitly allowed, and migrations are hot deploy-path code.  
Evidence: [scripts/deploy-live.sh:131](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/deploy-live.sh:131), [scripts/deploy-live.sh:136](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/deploy-live.sh:136), [scripts/deploy-live.sh:637](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/deploy-live.sh:637), [scripts/deploy-live.sh:1118](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/deploy-live.sh:1118), [scripts/deploy-migrations.sh:323](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/deploy-migrations.sh:323), [scripts/deploy-migrations.sh:328](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/deploy-migrations.sh:328), [scripts/deploy-migrations.sh:357](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/deploy-migrations.sh:357).

**Rank 7: `deploy-live.sh` is a self-mutating actuator with one-deploy-late behavior.**  
Recurrence: post-merge fixes to the deploy script cannot affect the deploy that lands them, because bash already parsed the old functions before the fast-forward.  
Scenario: commit fixes `host_checks`; deploy fast-forwards to that commit, then runs the old parsed `host_checks` and files the old page/backlog result.  
Blast radius: live deploy diagnostics, host checks, migration convergence reporting. Likelihood: medium-low; only fires when post-merge behavior in `deploy-live.sh` changes.  
Evidence: [scripts/deploy-live.sh:1048](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/deploy-live.sh:1048), [scripts/deploy-live.sh:1063](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/deploy-live.sh:1063), [scripts/deploy-live.sh:1095](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/deploy-live.sh:1095), [scripts/deploy-live.sh:1118](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/deploy-live.sh:1118).

**(2) LATENT BUGS**

**Rank 1: `land-verify.sh` fails open on invalid ranges.**  
Scenario: `git diff --name-only -z "$RANGE"` runs in process substitution with stderr suppressed and no status check. For `definitely-not-a-rev..also-not-a-rev`, the loop reads zero paths and exits success: I ran it and got `✓ land-verify: 0 path(s) ...` with `rc=0`.  
Blast radius: post-push content verification in `ship-land` can declare “landed” when it could not enumerate the landed range. Likelihood: low on nominal refs, higher during caller bugs, pruned refs, or fetch/rebase anomalies.  
Evidence: [scripts/land-verify.sh:52](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/land-verify.sh:52), [scripts/land-verify.sh:74](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/land-verify.sh:74), [scripts/land-verify.sh:83](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/land-verify.sh:83), [scripts/ship-land.sh:2216](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/ship-land.sh:2216).

**Rank 2: worker-claim gate admits nested dispatch worktree CWDs.**  
Scenario: a worker in `/.../wt-aaaaaaaaaaaa/src` calls a write/agent hook. The gate derives the item from only the basename, sees `src`, returns admit, and never consults `cc-backlog`; duplicate-worker/live-incumbent refusal is bypassed.  
Blast radius: multi-worker collision prevention for dispatched worktrees. Likelihood: high; workers commonly `cd` into subdirectories before editing.  
Evidence: [scripts/lib/worker-claim-gate.sh:250](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/lib/worker-claim-gate.sh:250), [scripts/lib/worker-claim-gate.sh:252](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/lib/worker-claim-gate.sh:252), [scripts/lib/worker-claim-gate.sh:253](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/lib/worker-claim-gate.sh:253).

**Rank 5: two `ship-land` non-verdict arms raise tree-red.**  
Scenario: AF_UNIX lint or TSV-pad lint exits `2`. The code prints that this is a “NON-VERDICT,” then calls `gate_red`, which sets `GATE_RED=1`; final routing returns red exit `6` instead of retryable killed exit `9`. Nearby exit-2 arms correctly set `GATE_KILLED=1`.  
Blast radius: landing path misclassifies machine/tool failure as author-fixable red, skewing gate results and blocking retry semantics. Likelihood: moderate; these lints run in the hot gate path.  
Evidence: [scripts/ship-land.sh:223](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/ship-land.sh:223), [scripts/ship-land.sh:1429](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/ship-land.sh:1429), [scripts/ship-land.sh:1431](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/ship-land.sh:1431), [scripts/ship-land.sh:1432](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/ship-land.sh:1432), [scripts/ship-land.sh:1924](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/ship-land.sh:1924), [scripts/ship-land.sh:1926](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/ship-land.sh:1926), [scripts/ship-land.sh:2074](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/ship-land.sh:2074).

**Rank 6: postland mutex can wedge on PID reuse.**  
Scenario: verifier dies after writing `run.lock.d/pid`; later an unrelated process gets that PID. `try_acquire` treats any `kill -0` success as a live holder forever, so `--run-if-needed` and `--run` quietly abstain and never stamp the current tree. `land-lock.sh` records `lstart` to avoid this exact class.  
Blast radius: postland verification can stop indefinitely, starving deploy-live of fresh verdicts. Likelihood: low-to-moderate; needs PID reuse on a long-running/high-churn host.  
Evidence: [scripts/postland-verify.sh:697](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/postland-verify.sh:697), [scripts/postland-verify.sh:703](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/postland-verify.sh:703), [scripts/postland-verify.sh:2394](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/postland-verify.sh:2394), [scripts/postland-verify.sh:2419](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/postland-verify.sh:2419), [scripts/land-lock.sh:84](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/land-lock.sh:84), [scripts/land-lock.sh:104](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/land-lock.sh:104).

**(3) VERIFICATION GAPS**

**Rank 8: `land-verify` tests do not cover invalid/unresolvable ranges.**  
Current tests cover green, dropped file, differing content, deletion, and no argument; they would still pass with the fail-open invalid-range behavior above.  
Evidence: [tests/land-verify.bats:24](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/tests/land-verify.bats:24), [tests/land-verify.bats:100](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/tests/land-verify.bats:100).  
Coverage search with no covering hit: `bash -lc 'shopt -s nullglob; rg -n "land-verify\\.sh.*(bad|invalid|unknown|missing).*range|bad .*land-verify range|invalid .*land-verify range|LAND_VERIFY=.*bad|land-verify.*git diff.*fails|land-verify.*0 path\\(s\\).*bad" tests/*.bats tests/*.test.sh'`

**Rank 9: worker-claim tests cover root worktree CWD, not nested CWD.**  
The tests exercise `wt-$id` as the current directory and ordinary non-worktree controls, but not `wt-$id/subdir`; they would pass while subdirectory writes bypass the claim gate.  
Evidence: [tests/worker-claim-gate.bats:95](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/tests/worker-claim-gate.bats:95), [tests/worker-claim-gate.bats:155](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/tests/worker-claim-gate.bats:155), [tests/worker-claim-gate-coverage.bats:252](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/tests/worker-claim-gate-coverage.bats:252), [tests/worker-claim-gate-coverage.bats:278](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/tests/worker-claim-gate-coverage.bats:278).  
Coverage search with no covering hit: `bash -lc 'shopt -s nullglob; rg -n "worker-claim.*subdir|subdir.*worker-claim|cc_worker_claim_admit .*sub|wt-[0-9a-f]{12}/[^ \\\\\\\"'\"'\"']+|subdir.*wt-[0-9a-f]{12}|wt-[0-9a-f]{12}.*subdir|nested cwd.*worker|worker.*nested cwd" tests/*.bats tests/*.test.sh'`

**Rank 10: `cc-bus` hostile-string tests stop before the consumer paths.**  
The test proves the emitted shard is valid JSON, but never calls `inbox`, `drain`, `offer`, `work --json`, or `actors --json` with hostile strings; the regex-reader bug remains green.  
Evidence: [tests/cc-bus.bats:79](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/tests/cc-bus.bats:79), [tests/cc-bus.bats:243](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/tests/cc-bus.bats:243), [tests/cc-bus.bats:252](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/tests/cc-bus.bats:252).  
Coverage search with no covering hit: `bash -lc 'shopt -s nullglob; rg -n "cc-bus.*(inbox|drain|offer|work --json|actors --json).*quote|(inbox|drain|offer|work --json|actors --json).*cc-bus.*quote|quotes.*(inbox|drain|offer|work --json|actors --json)|body containing quotes.*(inbox|drain)" tests/*.bats tests/*.test.sh'`

**Rank 11: `ship-land` has no AF_UNIX/TSV exit-2 routing test.**  
A suite that forces AF_UNIX or TSV-pad lint to exit `2` would catch the current “NON-VERDICT then `gate_red`” mismatch; current searches found no such coverage.  
Evidence: [scripts/ship-land.sh:1431](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/ship-land.sh:1431), [scripts/ship-land.sh:1925](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/ship-land.sh:1925).  
Coverage search with no covering hit: `bash -lc 'shopt -s nullglob; rg -n "afunix-path-lint could not RUN|SHIP_LAND_AFUNIX_LINT|afunix.*NON-VERDICT|afunix.*GATE_KILLED|test-afunix-path-lint.*exit 2|tsv-pad-lint could not RUN|SHIP_LAND_TSVPAD_LINT|tsv-pad.*NON-VERDICT|tsv-pad.*GATE_KILLED|tsv-pad.*exit 2" tests/*.bats tests/*.test.sh'`

**Rank 12: postland mutex tests cover live/dead PID, not recycled PID identity.**  
The suite proves a live pid blocks and a dead pid is reaped, but not that a live unrelated process reusing a dead holder’s pid is distinguished from the original holder.  
Evidence: [tests/postland-verify.bats:483](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/tests/postland-verify.bats:483), [tests/postland-verify.bats:496](/var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/tests/postland-verify.bats:496).  
Coverage search with no covering hit: `bash -lc 'shopt -s nullglob; rg -n "postland.*(recycled|lstart|pid reuse)|run\\.lock\\.d/lstart|run\\.lock\\.d.*lstart|lstart.*run\\.lock\\.d" tests/*.bats tests/*.test.sh'`

========== SOURCES ==========
  - scripts/deploy-live.sh:1048
  - scripts/deploy-live.sh:1048-1069
  - scripts/deploy-live.sh:1063
  - scripts/deploy-live.sh:1095
  - scripts/deploy-live.sh:1095-1121
  - scripts/deploy-live.sh:1118
  - scripts/deploy-live.sh:131
  - scripts/deploy-live.sh:136
  - scripts/deploy-live.sh:162-177
  - scripts/deploy-live.sh:335-340
  - scripts/deploy-live.sh:459-464
  - scripts/deploy-live.sh:637
  - scripts/deploy-migrations.sh:323
  - scripts/deploy-migrations.sh:328
  - scripts/deploy-migrations.sh:357
  - scripts/land-lock.sh:104
  - scripts/land-lock.sh:84
  - scripts/land-verify.sh:52
  - scripts/land-verify.sh:74
  - scripts/land-verify.sh:83
  - scripts/lib/worker-claim-gate.sh:250
  - scripts/lib/worker-claim-gate.sh:252
  - scripts/lib/worker-claim-gate.sh:253
  - scripts/postland-verify.sh:2394
  - scripts/postland-verify.sh:2419
  - scripts/postland-verify.sh:697
  - scripts/postland-verify.sh:703
  - scripts/ship-land.sh:1429
  - scripts/ship-land.sh:1431
  - scripts/ship-land.sh:1432
  - scripts/ship-land.sh:1924
  - scripts/ship-land.sh:1925
  - scripts/ship-land.sh:1926
  - scripts/ship-land.sh:2074
  - scripts/ship-land.sh:2216
  - scripts/ship-land.sh:223
  - var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/deploy-live.sh:1048
  - var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/deploy-live.sh:1063
  - var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/deploy-live.sh:1095
  - var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/deploy-live.sh:1118
  - var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/deploy-live.sh:131
  - var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/deploy-live.sh:136
  - var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/deploy-live.sh:162
  - var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/deploy-live.sh:335
  - var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/deploy-live.sh:459
  - var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/deploy-live.sh:637
  - var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/deploy-migrations.sh:323
  - var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/deploy-migrations.sh:328
  - var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/deploy-migrations.sh:357
  - var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/land-lock.sh:104
  - var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/land-lock.sh:84
  - var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/land-verify.sh:52
  - var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/land-verify.sh:74
  - var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/land-verify.sh:83
  - var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/lib/worker-claim-gate.sh:250
  - var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/lib/worker-claim-gate.sh:252
  - var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/lib/worker-claim-gate.sh:253
  - var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/postland-verify.sh:2394
  - var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/postland-verify.sh:2419
  - var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/postland-verify.sh:697
  - var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/postland-verify.sh:703
  - var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/ship-land.sh:1429
  - var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/ship-land.sh:1431
  - var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/ship-land.sh:1432
  - var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/ship-land.sh:1924
  - var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/ship-land.sh:1925
  - var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/ship-land.sh:1926
  - var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/ship-land.sh:2074
  - var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/ship-land.sh:2216
  - var/folders/0s/t55zvgts2qqb78fbqgn8ldy40000gn/T/grok-wiki-local-cli-workspace-nt3nZx/repo/scripts/ship-land.sh:223
