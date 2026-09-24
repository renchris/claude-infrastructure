# Dossier 4

## Brief
```
List the migrations in /tmp/tokeff-regate/f2/tree/migrations: files named NNNN-<slug>.sh. How many are there and what is the highest number? For the 3 highest-numbered, give the slug and one sentence on what each does (from its header comment). numbers: {"count": N, "highest": N}.
```

## Returned headline
There are 40 migration files numbered NNNN-<slug>.sh, and the highest number is 0037 (numbers 0009, 0016 and 0021 are each used twice). The top three are 0037 settings-parity, which gives every account one shared settings.json by symlinking each account's copy to it; 0036 rules-situational-exclude, which stops one account from loading the situational rules file, about 24.5k tokens per session, as the test arm of an A/B comparison; and 0035 workflow-concurrency, which raises the Workflow agent concurrency limit to 12.

## Returned numbers
`{"count": 40, "highest": 37}`

## answer.md
# Migrations in /tmp/tokeff-regate/f2/tree/migrations

**40 migration files match `NNNN-<slug>.sh`. The highest number is 0037.** The directory also holds a `README.md`, which is not a migration.

The numbers run from 0001 to 0037, but three of them are used twice, so 37 distinct numbers cover 40 files:
- 0009: `claude-next-guardrail-parity` and `start-latency-router`
- 0016: `autonomy-sweep-band-plist` and `w3-hook-registration`
- 0021: `cwdchanged-slot-replace` and `fleet-hook-parity`

## The 3 highest-numbered migrations (taken from each file's header comment)

| # | Slug | What it does |
|---|------|--------------|
| 0037 | `settings-parity` | Makes every Claude account run one shared `settings.json`. It backs up the four account copies, merges their agreed differences into `~/.claude/settings.json`, and replaces each account's file with a symlink to that one file. |
| 0036 | `rules-situational-exclude` | Adds a `claudeMdExcludes` glob for `agent-operating-lessons-situational.md` to one account's `settings.json` (by default `~/.claude-tertiary`). That account then stops loading the situational half of the rules file, about 24.5k tokens per session, and serves as the test arm of an A/B comparison. |
| 0035 | `workflow-concurrency` | Sets `CLAUDE_CODE_WORKFLOW_MAX_CONCURRENT_AGENTS="12"` in every config dir's `settings.json`, up from the default of 8 on this machine. A standard 10-agent research wave then runs in one round instead of two. |

All three are class `c10` migrations, meaning they edit `settings.json`.


## Tool calls (4) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/migrations && ls | grep -E '^[0-9]{4}-.+\\.sh$' | sort | tee /dev/stderr | wc -l; ls | grep -vE '^[0-9]{4}-.+\\.sh$'", "description": "List numbered migration files and count them"}`
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
3. `Bash: {"command": "mkdir -p /tmp/tokeff-regate/f2/out/B09-r8 && cat > /tmp/tokeff-regate/f2/out/B09-r8/answer.md <<'EOF'\n# Migrations in /tmp/tokeff-regate/f2/tree/migrations\n\n**40 migration files match `NNNN-<slug>.sh`. The highest number is 0037.** The directory also holds a `README.md`, which is not`
   → (Bash completed with no output)
4. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B09-r8/answer.md", "headline": "There are 40 migration files numbered NNNN-<slug>.sh, and the highest number is 0037 (numbers 0009, 0016 and 0021 are each used twice). The top three are 0037 settings-parity, which gives every account one shared settings.jso`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
