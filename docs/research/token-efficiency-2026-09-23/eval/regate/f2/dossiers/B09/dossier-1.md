# Dossier 1

## Brief
```
List the migrations in /tmp/tokeff-regate/f2/tree/migrations: files named NNNN-<slug>.sh. How many are there and what is the highest number? For the 3 highest-numbered, give the slug and one sentence on what each does (from its header comment). numbers: {"count": N, "highest": N}.
```

## Returned headline
There are 40 migration files, numbered 0001 to 0037; three numbers are used twice (0009, 0016, 0021). The top three are 0037 settings-parity (all accounts share one settings.json via symlinks), 0036 rules-situational-exclude (one account stops loading the situational rules file, as an A/B test) and 0035 workflow-concurrency (the Workflow agent limit goes up to 12).

## Returned numbers
`{"count": 40, "highest": 37}`

## answer.md
# Migrations in /tmp/tokeff-regate/f2/tree/migrations

**40 migration files** match `NNNN-<slug>.sh`, and the **highest number is 0037**. The only other file in the directory is `README.md`, which does not match the pattern.

The count is higher than the highest number because three numbers are used twice:
- 0009: `claude-next-guardrail-parity`, `start-latency-router`
- 0016: `autonomy-sweep-band-plist`, `w3-hook-registration`
- 0021: `cwdchanged-slot-replace`, `fleet-hook-parity`

0001 through 0037 has no gaps, so 37 distinct numbers plus 3 duplicates makes 40 files.

## The three highest-numbered

All three are class c10, meaning they edit settings.json and the operator has to run them.

| # | slug | what it does (from its header) |
|---|------|------|
| 0037 | `settings-parity` | Makes every Claude account use one settings.json. It backs up the four account copies, merges the approved differences into `~/.claude/settings.json`, and replaces each account's settings.json with a symlink to that file. |
| 0036 | `rules-situational-exclude` | Adds a `claudeMdExcludes` glob for `**/.claude/rules/agent-operating-lessons-situational.md` to one account's settings.json (default `~/.claude-tertiary`). That account stops loading the situational rules half, saving about 24.5k tokens per context, and serves as the test arm of an A/B test of the rules split. |
| 0035 | `workflow-concurrency` | Sets `CLAUDE_CODE_WORKFLOW_MAX_CONCURRENT_AGENTS="12"` in every config dir's settings.json. The default limit on this box is 8, so a 10-agent research wave currently needs two rounds; at 12 it runs in one. |

## Full list
0001-migrations-ledger-scaffold, 0002-curl-gate-scope-registration, 0003-cloud-fleet-link-drive, 0004-lead-deathwatch-l1-activation, 0005-goal-inert-watch-registration, 0006-coldcompile-admit-registration, 0007-mailbox-wake-arm-registration, 0008-auth-timeseries-activation, 0009-claude-next-guardrail-parity, 0009-start-latency-router, 0010-postland-band-plist, 0011-accounts-board-wiring, 0012-mailbox-wake-arm-stop-rearm, 0013-claude-next-hooks-unfork, 0014-subagent-stop-registration, 0015-memory-index-drain-registration, 0016-autonomy-sweep-band-plist, 0016-w3-hook-registration, 0017-filechanged-cwdchanged-registration, 0018-memory-index-drain-rotor-budget, 0019-hook-surface-registration, 0020-hook-surface-registration-w3d, 0021-cwdchanged-slot-replace, 0021-fleet-hook-parity, 0022-mitl-decider-shadow, 0023-todo-tools-and-task-hooks, 0024-unit-gate-registration, 0025-session-search-backfill-path, 0026-recover-inject-registration, 0027-handoff-claim-registration, 0028-ms365-graph-batch-matcher, 0029-frontier-gate-session-path, 0030-net-recover-arm-registration, 0031-resident-reload-flip, 0032-browse-mirror, 0033-mail-images-auto, 0034-artifact-off-fleetwide, 0035-workflow-concurrency, 0036-rules-situational-exclude, 0037-settings-parity (all `.sh`).


## Tool calls (4) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/migrations && ls | grep -E '^[0-9]{4}-.+\\.sh$' | sort | tee /dev/stderr | wc -l; ls | grep -vE '^[0-9]{4}-.+\\.sh$'", "description": "List numbered migration scripts and count them"}`
   → 0001-migrations-ledger-scaffold.sh
0002-curl-gate-scope-registration.sh
0003-cloud-fleet-link-drive.sh
0004-lead-deathwatch-l1-activation.sh
0005-goal-inert-watch-registration.sh
0006-coldcompile-admit-registration.sh
0007-mailbox-wake-arm-registration.sh
0008-auth-timeseries-activation.sh
0009-clau
2. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/migrations && for f in 0035-*.sh 0036-*.sh 0037-*.sh; do echo \"=== $f\"; head -30 \"$f\"; done", "description": "Read header comments of the three highest migrations"}`
   → === 0035-workflow-concurrency.sh
#!/bin/bash
# migration-class: c10
# migration-step: raise the Workflow tool's per-run concurrent agent gate to 12 (env CLAUDE_CODE_WORKFLOW_MAX_CONCURRENT_AGENTS="12" in every config dir's settings.json) so a default 10-agent research wave runs in one round instead 
3. `Bash: {"command": "mkdir -p /tmp/tokeff-regate/f2/out/B09-r5 && cat > /tmp/tokeff-regate/f2/out/B09-r5/answer.md <<'EOF'\n# Migrations in /tmp/tokeff-regate/f2/tree/migrations\n\n**40 migration files** match `NNNN-<slug>.sh`, and the **highest number is 0037**. The only other file in the directory is `REA`
   → (Bash completed with no output)
4. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B09-r5/answer.md", "headline": "There are 40 migration files, numbered 0001 to 0037; three numbers are used twice (0009, 0016, 0021). The top three are 0037 settings-parity (all accounts share one settings.json via symlinks), 0036 rules-situational-exclude `
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
