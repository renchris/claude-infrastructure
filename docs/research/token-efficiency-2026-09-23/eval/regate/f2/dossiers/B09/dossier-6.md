# Dossier 6

## Brief
```
List the migrations in /tmp/tokeff-regate/f2/tree/migrations: files named NNNN-<slug>.sh. How many are there and what is the highest number? For the 3 highest-numbered, give the slug and one sentence on what each does (from its header comment). numbers: {"count": N, "highest": N}.
```

## Returned headline
There are 40 migration files named NNNN-<slug>.sh, and the highest number is 0037 (counted with ls | grep | wc -l). Because 0009, 0016 and 0021 each have two files, there are 37 distinct numbers. The top three are 0037 settings-parity, which makes every account's settings.json a symlink to one shared file; 0036 rules-situational-exclude, which stops one account from loading the situational rules file as an A/B test; and 0035 workflow-concurrency, which raises the Workflow tool's concurrent-agent limit to 12.

## Returned numbers
`{"count": 40, "highest": 37}`

## answer.md
# Migrations in /tmp/tokeff-regate/f2/tree/migrations

Measured with `ls | grep -E '^[0-9]{4}-.+\.sh$' | wc -l`: **40** files match `NNNN-<slug>.sh`. The only other entry in the directory is README.md. The highest number is **0037**.

The numbers run from 0001 to 0037, so there are 37 distinct numbers. Three numbers have two files each:
- 0009: claude-next-guardrail-parity, start-latency-router
- 0016: autonomy-sweep-band-plist, w3-hook-registration
- 0021: cwdchanged-slot-replace, fleet-hook-parity

The README says migrations run in lexical order, so the filename breaks each tie.

## The 3 highest-numbered migrations (from their header comments)

- **0037 `settings-parity`**: makes every Claude account use one settings.json. It backs up the four per-account copies, merges the approved differences into ~/.claude/settings.json, and then replaces each account's settings.json with a symlink to that file.
- **0036 `rules-situational-exclude`**: adds a `claudeMdExcludes` glob for `**/.claude/rules/agent-operating-lessons-situational.md` to one account's settings.json (default ~/.claude-tertiary). That account stops loading the situational half of the rules file, which saves about 24.5k tokens per context and makes it the test arm of an A/B comparison.
- **0035 `workflow-concurrency`**: sets `CLAUDE_CODE_WORKFLOW_MAX_CONCURRENT_AGENTS="12"` in every config dir's settings.json. This raises the Workflow tool's concurrent-agent limit from its default of 8 on this machine to 12, so a default 10-agent research wave runs in one round instead of two.

## Full list
0001-migrations-ledger-scaffold, 0002-curl-gate-scope-registration, 0003-cloud-fleet-link-drive, 0004-lead-deathwatch-l1-activation, 0005-goal-inert-watch-registration, 0006-coldcompile-admit-registration, 0007-mailbox-wake-arm-registration, 0008-auth-timeseries-activation, 0009-claude-next-guardrail-parity, 0009-start-latency-router, 0010-postland-band-plist, 0011-accounts-board-wiring, 0012-mailbox-wake-arm-stop-rearm, 0013-claude-next-hooks-unfork, 0014-subagent-stop-registration, 0015-memory-index-drain-registration, 0016-autonomy-sweep-band-plist, 0016-w3-hook-registration, 0017-filechanged-cwdchanged-registration, 0018-memory-index-drain-rotor-budget, 0019-hook-surface-registration, 0020-hook-surface-registration-w3d, 0021-cwdchanged-slot-replace, 0021-fleet-hook-parity, 0022-mitl-decider-shadow, 0023-todo-tools-and-task-hooks, 0024-unit-gate-registration, 0025-session-search-backfill-path, 0026-recover-inject-registration, 0027-handoff-claim-registration, 0028-ms365-graph-batch-matcher, 0029-frontier-gate-session-path, 0030-net-recover-arm-registration, 0031-resident-reload-flip, 0032-browse-mirror, 0033-mail-images-auto, 0034-artifact-off-fleetwide, 0035-workflow-concurrency, 0036-rules-situational-exclude, 0037-settings-parity (all `.sh`).


## Tool calls (4) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/migrations && ls | head -100; echo ---; ls | grep -E '^[0-9]{4}-.+\\.sh$' | wc -l; ls | grep -Ev '^[0-9]{4}-.+\\.sh$'; ls -d /tmp/tokeff-regate/f2/out/B09-r2/", "description": "List migration files and count matches"}`
   → Exit code 1
0001-migrations-ledger-scaffold.sh
0002-curl-gate-scope-registration.sh
0003-cloud-fleet-link-drive.sh
0004-lead-deathwatch-l1-activation.sh
0005-goal-inert-watch-registration.sh
0006-coldcompile-admit-registration.sh
0007-mailbox-wake-arm-registration.sh
0008-auth-timeseries-activation.
2. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/migrations && for f in 0035-*.sh 0036-*.sh 0037-*.sh; do echo \"=== $f\"; head -30 \"$f\"; done; grep -n -i -E 'number|NNNN|duplicate|collision' README.md | head", "description": "Read headers of top three migrations"}`
   → === 0035-workflow-concurrency.sh
#!/bin/bash
# migration-class: c10
# migration-step: raise the Workflow tool's per-run concurrent agent gate to 12 (env CLAUDE_CODE_WORKFLOW_MAX_CONCURRENT_AGENTS="12" in every config dir's settings.json) so a default 10-agent research wave runs in one round instead 
3. `Bash: {"command": "mkdir -p /tmp/tokeff-regate/f2/out/B09-r2 && cat > /tmp/tokeff-regate/f2/out/B09-r2/answer.md <<'EOF'\n# Migrations in /tmp/tokeff-regate/f2/tree/migrations\n\nMeasured with `ls | grep -E '^[0-9]{4}-.+\\.sh$' | wc -l`: **40** files match `NNNN-<slug>.sh`. The only other entry in the dir`
   → (Bash completed with no output)
4. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B09-r2/answer.md", "headline": "There are 40 migration files named NNNN-<slug>.sh, and the highest number is 0037 (counted with ls | grep | wc -l). Because 0009, 0016 and 0021 each have two files, there are 37 distinct numbers. The top three are 0037 settin`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
