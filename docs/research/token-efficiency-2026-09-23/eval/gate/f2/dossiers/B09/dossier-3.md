# Dossier 3

## Brief
```
List the migrations in /tmp/tokeff-gate/f2/tree/migrations: files named NNNN-<slug>.sh. How many are there and what is the highest number? For the 3 highest-numbered, give the slug and one sentence on what each does (from its header comment). numbers: {"count": N, "highest": N}.
```

## Returned headline
There are 40 migration files named NNNN-<slug>.sh, and the highest number is 0037. Numbers 0009, 0016 and 0021 each have two files, so there are 37 distinct numbers. The top three are 0037 settings-parity (every account uses one symlinked settings.json), 0036 rules-situational-exclude (one account stops loading the situational rules file, as an A/B test) and 0035 workflow-concurrency (raises the limit on Workflow agents running at once to 12).

## Returned numbers
`{"count": 40, "highest": 37}`

## answer.md
# Migrations in /tmp/tokeff-gate/f2/tree/migrations

Measured with `ls | grep -E '^[0-9]{4}-.+\.sh$'`: there are **40** migration files named `NNNN-<slug>.sh`. The highest number is **0037**. The directory also holds a `README.md`, which is not a migration.

The numbering runs from 0001 to 0037, which gives 37 distinct numbers. Three numbers are shared by two files each:
- 0009: `claude-next-guardrail-parity`, `start-latency-router`
- 0016: `autonomy-sweep-band-plist`, `w3-hook-registration`
- 0021: `cwdchanged-slot-replace`, `fleet-hook-parity`

## The 3 highest-numbered migrations

- **0037 `settings-parity`**: Backs up the four account copies of settings.json, folds the approved differences into ~/.claude/settings.json, and replaces each account's copy with a symlink to that one file, so every account runs the same settings.
- **0036 `rules-situational-exclude`**: Adds a `claudeMdExcludes` glob to one account's settings.json (default ~/.claude-tertiary), so that account stops loading `agent-operating-lessons-situational.md`. This is the A/B test arm of the rules split and saves about 24.5k tokens per context.
- **0035 `workflow-concurrency`**: Sets `CLAUDE_CODE_WORKFLOW_MAX_CONCURRENT_AGENTS="12"` in every config dir's settings.json. The limit is otherwise 8 on this machine, and raising it lets a default 10-agent research wave run in one round instead of two.


## Tool calls (5) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree/migrations && ls | grep -E '^[0-9]{4}-.+\\.sh$' | wc -l; ls | grep -E '^[0-9]{4}-.+\\.sh$' | sort | tail -3; ls | grep -vE '^[0-9]{4}-.+\\.sh$' | head; ls /tmp/tokeff-gate/f2/out/B09-r3/ 2>&1", "description": "Count migrations and list the highest three"}`
   →       40
0035-workflow-concurrency.sh
0036-rules-situational-exclude.sh
0037-settings-parity.sh
README.md
2. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree/migrations && ls | grep -E '^[0-9]{4}-.+\\.sh$' | cut -c1-4 | sort | uniq -c | awk '$1>1'; ls | grep -E '^[0-9]{4}-' | head -3; for f in 0035-*.sh 0036-*.sh 0037-*.sh; do echo \"== $f\"; head -25 \"$f\"; done", "description": "Check duplicate numbers and read`
   →    2 0009
   2 0016
   2 0021
0001-migrations-ledger-scaffold.sh
0002-curl-gate-scope-registration.sh
0003-cloud-fleet-link-drive.sh
== 0035-workflow-concurrency.sh
#!/bin/bash
# migration-class: c10
# migration-step: raise the Workflow tool's per-run concurrent agent gate to 12 (env CLAUDE_CODE_WOR
3. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree/migrations && ls | grep -E '^(0009|0016|0021)-'; ls | grep -E '^[0-9]{4}-.+\\.sh$' | cut -c1-4 | sort -u | wc -l", "description": "Show duplicate-numbered migrations and distinct count"}`
   → 0009-claude-next-guardrail-parity.sh
0009-start-latency-router.sh
0016-autonomy-sweep-band-plist.sh
0016-w3-hook-registration.sh
0021-cwdchanged-slot-replace.sh
0021-fleet-hook-parity.sh
      37
4. `Bash: {"command": "cat > /tmp/tokeff-gate/f2/out/B09-r3/answer.md <<'EOF'\n# Migrations in /tmp/tokeff-gate/f2/tree/migrations\n\nMeasured with `ls | grep -E '^[0-9]{4}-.+\\.sh$'`: there are **40** migration files named `NNNN-<slug>.sh`. The highest number is **0037**. The directory also holds a `README.m`
   → (Bash completed with no output)
5. `StructuredOutput: {"answer_path": "/tmp/tokeff-gate/f2/out/B09-r3/answer.md", "headline": "There are 40 migration files named NNNN-<slug>.sh, and the highest number is 0037. Numbers 0009, 0016 and 0021 each have two files, so there are 37 distinct numbers. The top three are 0037 settings-parity (every account uses on`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
