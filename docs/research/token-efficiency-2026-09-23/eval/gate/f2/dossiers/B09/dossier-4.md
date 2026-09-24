# Dossier 4

## Brief
```
List the migrations in /tmp/tokeff-gate/f2/tree/migrations: files named NNNN-<slug>.sh. How many are there and what is the highest number? For the 3 highest-numbered, give the slug and one sentence on what each does (from its header comment). numbers: {"count": N, "highest": N}.
```

## Returned headline
There are 40 NNNN-<slug>.sh migrations and the highest number is 0037. Only 37 distinct numbers are used because 0009, 0016 and 0021 each appear twice. The top three are 0037 settings-parity (one settings.json, symlinked into every account), 0036 rules-situational-exclude (a claudeMdExcludes glob on one account as the A/B arm of the rules split) and 0035 workflow-concurrency (raises the Workflow concurrent-agent limit to 12).

## Returned numbers
`{"count": 40, "highest": 37}`

## answer.md
# Migrations in /tmp/tokeff-gate/f2/tree/migrations

**40 migration files (`NNNN-<slug>.sh`); the highest number is 0037.** (README.md is the only other file.)

Note: 40 files but only 37 distinct numbers — three numbers are used twice:
- 0009: `claude-next-guardrail-parity`, `start-latency-router`
- 0016: `autonomy-sweep-band-plist`, `w3-hook-registration`
- 0021: `cwdchanged-slot-replace`, `fleet-hook-parity`

## The 3 highest-numbered

| # | Slug | What it does (from its header) |
|---|---|---|
| 0037 | `settings-parity` | Makes every Claude account run one settings.json: backs up the four account copies, folds the ruled differences into `~/.claude/settings.json`, and replaces each account's settings.json with a symlink to it (operator ruling 2026-09-23: accounts are interchangeable). |
| 0036 | `rules-situational-exclude` | Adds the `claudeMdExcludes` glob `**/.claude/rules/agent-operating-lessons-situational.md` to one account's settings.json (default `~/.claude-tertiary`) so that account stops loading the situational rules half, as the A/B arm of the rules split. |
| 0035 | `workflow-concurrency` | Raises the Workflow tool's per-run concurrent-agent gate to 12 (`CLAUDE_CODE_WORKFLOW_MAX_CONCURRENT_AGENTS="12"` in every config dir's settings.json) so a default 10-agent research wave runs in one round instead of two. |

All three are class `c10` (they edit settings.json).

Source: `ls /tmp/tokeff-gate/f2/tree/migrations | grep -E '^[0-9]{4}-.+\.sh$' | wc -l` => 40; headers read with `head -25`.


## Tool calls (4) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree/migrations && ls | grep -E '^[0-9]{4}-.+\\.sh$' | sort | tee /dev/stderr | wc -l; ls | grep -vE '^[0-9]{4}-.+\\.sh$'", "description": "List migration files and count them"}`
   → 0001-migrations-ledger-scaffold.sh
0002-curl-gate-scope-registration.sh
0003-cloud-fleet-link-drive.sh
0004-lead-deathwatch-l1-activation.sh
0005-goal-inert-watch-registration.sh
0006-coldcompile-admit-registration.sh
0007-mailbox-wake-arm-registration.sh
0008-auth-timeseries-activation.sh
0009-clau
2. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree/migrations && for f in 0035-*.sh 0036-*.sh 0037-*.sh; do echo \"== $f\"; head -25 \"$f\"; done", "description": "Read header comments of the three highest migrations"}`
   → == 0035-workflow-concurrency.sh
#!/bin/bash
# migration-class: c10
# migration-step: raise the Workflow tool's per-run concurrent agent gate to 12 (env CLAUDE_CODE_WORKFLOW_MAX_CONCURRENT_AGENTS="12" in every config dir's settings.json) so a default 10-agent research wave runs in one round instead o
3. `Bash: {"command": "mkdir -p /tmp/tokeff-gate/f2/out/B09-r8 && cat > /tmp/tokeff-gate/f2/out/B09-r8/answer.md <<'EOF'\n# Migrations in /tmp/tokeff-gate/f2/tree/migrations\n\n**40 migration files (`NNNN-<slug>.sh`); the highest number is 0037.** (README.md is the only other file.)\n\nNote: 40 files but only`
   → (Bash completed with no output)
4. `StructuredOutput: {"answer_path": "/tmp/tokeff-gate/f2/out/B09-r8/answer.md", "headline": "There are 40 NNNN-<slug>.sh migrations and the highest number is 0037. Only 37 distinct numbers are used because 0009, 0016 and 0021 each appear twice. The top three are 0037 settings-parity (one settings.json, symlinked into e`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
