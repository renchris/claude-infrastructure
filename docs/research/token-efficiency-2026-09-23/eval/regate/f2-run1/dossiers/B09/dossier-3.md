# Dossier 3

## Brief
```
List the migrations in /tmp/tokeff-regate/f2/tree/migrations: files named NNNN-<slug>.sh. How many are there and what is the highest number? For the 3 highest-numbered, give the slug and one sentence on what each does (from its header comment). numbers: {"count": N, "highest": N}.
```

## Returned headline
There are 40 migration files (counted with ls piped to grep and wc) and the highest number is 0037; numbers 0009, 0016 and 0021 are each used twice, so only 37 numbers are distinct. The top three are 0037 settings-parity (one shared settings.json for every account, via symlinks), 0036 rules-situational-exclude (one account stops loading the situational rules file, as an A/B test arm) and 0035 workflow-concurrency (Workflow agent limit raised to 12).

## Returned numbers
`{"count": 40, "highest": 37}`

## answer.md
# Migrations in /tmp/tokeff-regate/f2/tree/migrations

**Count: 40** files matching `NNNN-<slug>.sh`. The directory also holds `README.md`, which is not counted.
(Measured with `ls | grep -E '^[0-9]{4}-.+\.sh$' | wc -l`.)

**Highest number: 0037.**

Three numbers are used twice, so there are 40 files but only 37 distinct numbers (0001 to 0037):
- 0009: `claude-next-guardrail-parity`, `start-latency-router`
- 0016: `autonomy-sweep-band-plist`, `w3-hook-registration`
- 0021: `cwdchanged-slot-replace`, `fleet-hook-parity`

## The 3 highest-numbered

- **0037 `settings-parity`**: Backs up each account's own settings.json, merges their agreed differences into `~/.claude/settings.json`, and replaces each account's copy with a symlink to that one file, so every Claude account runs the same settings.
- **0036 `rules-situational-exclude`**: Adds the `claudeMdExcludes` glob `**/.claude/rules/agent-operating-lessons-situational.md` to one account's settings.json (default `~/.claude-tertiary`). That account then stops loading the situational half of the rules file, which saves about 24.5k tokens per context and serves as the A/B test arm.
- **0035 `workflow-concurrency`**: Sets `CLAUDE_CODE_WORKFLOW_MAX_CONCURRENT_AGENTS="12"` in every config dir's settings.json. This raises the Workflow tool's per-run agent limit from 8 on this machine to 12, so a default 10-agent research wave runs in one round instead of two.

## Full list
- 0001-migrations-ledger-scaffold.sh
- 0002-curl-gate-scope-registration.sh
- 0003-cloud-fleet-link-drive.sh
- 0004-lead-deathwatch-l1-activation.sh
- 0005-goal-inert-watch-registration.sh
- 0006-coldcompile-admit-registration.sh
- 0007-mailbox-wake-arm-registration.sh
- 0008-auth-timeseries-activation.sh
- 0009-claude-next-guardrail-parity.sh
- 0009-start-latency-router.sh
- 0010-postland-band-plist.sh
- 0011-accounts-board-wiring.sh
- 0012-mailbox-wake-arm-stop-rearm.sh
- 0013-claude-next-hooks-unfork.sh
- 0014-subagent-stop-registration.sh
- 0015-memory-index-drain-registration.sh
- 0016-autonomy-sweep-band-plist.sh
- 0016-w3-hook-registration.sh
- 0017-filechanged-cwdchanged-registration.sh
- 0018-memory-index-drain-rotor-budget.sh
- 0019-hook-surface-registration.sh
- 0020-hook-surface-registration-w3d.sh
- 0021-cwdchanged-slot-replace.sh
- 0021-fleet-hook-parity.sh
- 0022-mitl-decider-shadow.sh
- 0023-todo-tools-and-task-hooks.sh
- 0024-unit-gate-registration.sh
- 0025-session-search-backfill-path.sh
- 0026-recover-inject-registration.sh
- 0027-handoff-claim-registration.sh
- 0028-ms365-graph-batch-matcher.sh
- 0029-frontier-gate-session-path.sh
- 0030-net-recover-arm-registration.sh
- 0031-resident-reload-flip.sh
- 0032-browse-mirror.sh
- 0033-mail-images-auto.sh
- 0034-artifact-off-fleetwide.sh
- 0035-workflow-concurrency.sh
- 0036-rules-situational-exclude.sh
- 0037-settings-parity.sh


## Tool calls (4) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/migrations && ls | head -100; echo ---; ls | grep -E '^[0-9]{4}-.+\\.sh$' | wc -l; ls | grep -vE '^[0-9]{4}-.+\\.sh$'", "description": "List migration files and count matches"}`
   → 0001-migrations-ledger-scaffold.sh
0002-curl-gate-scope-registration.sh
0003-cloud-fleet-link-drive.sh
0004-lead-deathwatch-l1-activation.sh
0005-goal-inert-watch-registration.sh
0006-coldcompile-admit-registration.sh
0007-mailbox-wake-arm-registration.sh
0008-auth-timeseries-activation.sh
0009-clau
2. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/migrations && for f in 0035-* 0036-* 0037-*; do echo \"=== $f\"; head -25 \"$f\"; done; ls -a | grep -v '^\\.\\.\\?$' | wc -l", "description": "Read headers of three highest migrations"}`
   → === 0035-workflow-concurrency.sh
#!/bin/bash
# migration-class: c10
# migration-step: raise the Workflow tool's per-run concurrent agent gate to 12 (env CLAUDE_CODE_WORKFLOW_MAX_CONCURRENT_AGENTS="12" in every config dir's settings.json) so a default 10-agent research wave runs in one round instead 
3. `Bash: {"command": "mkdir -p /tmp/tokeff-regate/f2/out/B09-r3 && cat > /tmp/tokeff-regate/f2/out/B09-r3/answer.md <<'EOF'\n# Migrations in /tmp/tokeff-regate/f2/tree/migrations\n\n**Count: 40** files matching `NNNN-<slug>.sh`. The directory also holds `README.md`, which is not counted.\n(Measured with `ls `
   → - 0035-workflow-concurrency.sh
- 0036-rules-situational-exclude.sh
- 0037-settings-parity.sh
4. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B09-r3/answer.md", "headline": "There are 40 migration files (counted with ls piped to grep and wc) and the highest number is 0037; numbers 0009, 0016 and 0021 are each used twice, so only 37 numbers are distinct. The top three are 0037 settings-parity (one`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
