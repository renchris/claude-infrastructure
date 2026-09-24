# Dossier 1

## Brief
```
List the migrations in /tmp/tokeff-gate/f2/tree/migrations: files named NNNN-<slug>.sh. How many are there and what is the highest number? For the 3 highest-numbered, give the slug and one sentence on what each does (from its header comment). numbers: {"count": N, "highest": N}.
```

## Returned headline
There are 40 NNNN-<slug>.sh migrations and the highest number is 0037; numbers 0009, 0016 and 0021 are each used twice. The top three are 0037 settings-parity (every account shares one symlinked settings.json), 0036 rules-situational-exclude (one account stops loading the situational rules file, as an A/B arm) and 0035 workflow-concurrency (the Workflow concurrent-agent gate rises to 12).

## Returned numbers
`{"count": 40, "highest": 37}`

## answer.md
# Migrations in /tmp/tokeff-gate/f2/tree/migrations

**40 migration files** match `NNNN-<slug>.sh`; the **highest number is 0037**. Numbers run 0001-0037,
but three numbers are used twice, so 40 files cover 37 distinct numbers:
- 0009: `claude-next-guardrail-parity`, `start-latency-router`
- 0016: `autonomy-sweep-band-plist`, `w3-hook-registration`
- 0021: `cwdchanged-slot-replace`, `fleet-hook-parity`

(`README.md` is the only other file in the directory and is not counted.)

## The three highest-numbered

| # | Slug | What it does (from the header comment) |
|---|------|------|
| 0037 | `settings-parity` | Makes every Claude account run ONE settings.json: it backs up the four per-account copies, merges the agreed differences into `~/.claude/settings.json`, and replaces each account's settings.json with a symlink to that file (operator ruling 2026-09-23: accounts are interchangeable). |
| 0036 | `rules-situational-exclude` | Adds the `claudeMdExcludes` glob `**/.claude/rules/agent-operating-lessons-situational.md` to ONE account's settings.json (default `~/.claude-tertiary`). That account then stops loading the situational half of the rules (~24.5k tokens per context), which makes it the treatment arm of the rules-split A/B. |
| 0035 | `workflow-concurrency` | Sets `CLAUDE_CODE_WORKFLOW_MAX_CONCURRENT_AGENTS="12"` in every config dir's settings.json. This raises the Workflow tool's concurrent-agent gate from the default of 8 on this box to 12, so a default 10-agent research wave runs in one round instead of two. |

All three are class `c10` (they edit settings.json).


## Tool calls (4) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree/migrations && ls | grep -E '^[0-9]{4}-.*\\.sh$' | sort | tee /dev/stderr | wc -l; ls | grep -vE '^[0-9]{4}-.*\\.sh$'", "description": "List numbered migration scripts and count them"}`
   → 0001-migrations-ledger-scaffold.sh
0002-curl-gate-scope-registration.sh
0003-cloud-fleet-link-drive.sh
0004-lead-deathwatch-l1-activation.sh
0005-goal-inert-watch-registration.sh
0006-coldcompile-admit-registration.sh
0007-mailbox-wake-arm-registration.sh
0008-auth-timeseries-activation.sh
0009-clau
2. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree/migrations && for f in 0035-*.sh 0036-*.sh 0037-*.sh; do echo \"=== $f\"; head -30 \"$f\"; done", "description": "Read header comments of the three highest migrations"}`
   → === 0035-workflow-concurrency.sh
#!/bin/bash
# migration-class: c10
# migration-step: raise the Workflow tool's per-run concurrent agent gate to 12 (env CLAUDE_CODE_WORKFLOW_MAX_CONCURRENT_AGENTS="12" in every config dir's settings.json) so a default 10-agent research wave runs in one round instead 
3. `Bash: {"command": "mkdir -p /tmp/tokeff-gate/f2/out/B09-r5 && cat > /tmp/tokeff-gate/f2/out/B09-r5/answer.md <<'EOF'\n# Migrations in /tmp/tokeff-gate/f2/tree/migrations\n\n**40 migration files** match `NNNN-<slug>.sh`; the **highest number is 0037**. Numbers run 0001-0037,\nbut three numbers are used twi`
   → ok
4. `StructuredOutput: {"answer_path": "/tmp/tokeff-gate/f2/out/B09-r5/answer.md", "headline": "There are 40 NNNN-<slug>.sh migrations and the highest number is 0037; numbers 0009, 0016 and 0021 are each used twice. The top three are 0037 settings-parity (every account shares one symlinked settings.json), 0036 rules-situa`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
