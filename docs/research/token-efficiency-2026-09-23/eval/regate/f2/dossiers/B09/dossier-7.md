# Dossier 7

## Brief
```
List the migrations in /tmp/tokeff-regate/f2/tree/migrations: files named NNNN-<slug>.sh. How many are there and what is the highest number? For the 3 highest-numbered, give the slug and one sentence on what each does (from its header comment). numbers: {"count": N, "highest": N}.
```

## Returned headline
There are 40 migrations and the highest number is 0037 (counted with ls | grep -cE '^[0-9]{4}-.+\.sh$'). Numbers 0009, 0016 and 0021 each appear twice, so there are 37 distinct numbers. The three highest are 0037 settings-parity (every account's settings.json becomes a symlink to one shared file), 0036 rules-situational-exclude (one account stops loading the situational half of the rules, as the test arm of an A/B) and 0035 workflow-concurrency (raises the per-run Workflow agent limit to 12).

## Returned numbers
`{"count": 40, "highest": 37}`

## answer.md
# Migrations in /tmp/tokeff-regate/f2/tree/migrations

**Count: 40** migration files matching `NNNN-<slug>.sh` (measured: `ls | grep -cE '^[0-9]{4}-.+\.sh$'`; the only other file is README.md).
**Highest number: 0037.**

Note: numbers are not unique. Three numbers are used twice (0009, 0016, 0021), so 40 files use 37 distinct numbers (0001-0037).

## The 3 highest-numbered

| # | Slug | What it does (from header `migration-step`) |
|---|------|---------------------------------------------|
| 0037 | settings-parity | Makes every Claude account use one settings.json: it backs up the four account copies, merges the approved differences into ~/.claude/settings.json, and replaces each account's settings.json with a symlink to that file. |
| 0036 | rules-situational-exclude | Adds the `claudeMdExcludes` glob `**/.claude/rules/agent-operating-lessons-situational.md` to one account's settings.json (default ~/.claude-tertiary), so only that account stops loading the situational half of the rules (the A/B arm of the rules split). |
| 0035 | workflow-concurrency | Sets `CLAUDE_CODE_WORKFLOW_MAX_CONCURRENT_AGENTS="12"` in every config dir's settings.json. This raises the Workflow tool's per-run concurrent-agent limit from 8 on this machine to 12, so a default 10-agent research wave runs in one round. |

All three are class c10, because each one edits settings.json.

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
1. `Bash: {"command": "ls -la /tmp/tokeff-regate/f2/tree/migrations | head -100; ls /tmp/tokeff-regate/f2/tree/migrations | wc -l; ls /tmp/tokeff-regate/f2/out/B09-r7/ 2>&1", "description": "List migrations directory and output dir"}`
   → total 848
dr-xr-xr-x@ 43 chrisren  wheel   1376 Sep 24 12:36 .
dr-xr-xr-x@ 46 chrisren  wheel   1472 Sep 24 12:36 ..
-r-xr-xr-x@  1 chrisren  wheel   3698 Sep 24 00:14 0001-migrations-ledger-scaffold.sh
-r-xr-xr-x@  1 chrisren  wheel   3396 Sep 24 00:14 0002-curl-gate-scope-registration.sh
-r-xr-xr-
2. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/migrations; ls | grep -cE '^[0-9]{4}-.+\\.sh$'; for f in 0035* 0036* 0037*; do echo \"== $f\"; head -30 \"$f\"; done; ls -ld /tmp/tokeff-regate/f2/out/B09-r7", "description": "Count migrations and read top-3 headers"}`
   → 40
== 0035-workflow-concurrency.sh
#!/bin/bash
# migration-class: c10
# migration-step: raise the Workflow tool's per-run concurrent agent gate to 12 (env CLAUDE_CODE_WORKFLOW_MAX_CONCURRENT_AGENTS="12" in every config dir's settings.json) so a default 10-agent research wave runs in one round instea
3. `Bash: {"command": "cat > /tmp/tokeff-regate/f2/out/B09-r7/answer.md <<'EOF'\n# Migrations in /tmp/tokeff-regate/f2/tree/migrations\n\n**Count: 40** migration files matching `NNNN-<slug>.sh` (measured: `ls | grep -cE '^[0-9]{4}-.+\\.sh$'`; the only other file is README.md).\n**Highest number: 0037.**\n\nNo`
   →       58 /tmp/tokeff-regate/f2/out/B09-r7/answer.md
4. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B09-r7/answer.md", "headline": "There are 40 migrations and the highest number is 0037 (counted with ls | grep -cE '^[0-9]{4}-.+\\.sh$'). Numbers 0009, 0016 and 0021 each appear twice, so there are 37 distinct numbers. The three highest are 0037 settings-pa`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
