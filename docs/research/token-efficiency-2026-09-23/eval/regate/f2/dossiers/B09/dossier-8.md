# Dossier 8

## Brief
```
List the migrations in /tmp/tokeff-regate/f2/tree/migrations: files named NNNN-<slug>.sh. How many are there and what is the highest number? For the 3 highest-numbered, give the slug and one sentence on what each does (from its header comment). numbers: {"count": N, "highest": N}.
```

## Returned headline
There are 40 NNNN-<slug>.sh migrations and the highest is 0037 (0009, 0016 and 0021 are each used twice, so only 37 numbers are distinct). The top three are 0037 settings-parity (all accounts share one settings.json via symlinks), 0036 rules-situational-exclude (one account stops loading the situational rules file, as an A/B test arm) and 0035 workflow-concurrency (raises the Workflow limit on agents running at once to 12).

## Returned numbers
`{"count": 40, "highest": 37}`

## answer.md
# Migrations in /tmp/tokeff-regate/f2/tree/migrations

Measured with `ls | grep -E '^[0-9]{4}-.+\.sh$' | wc -l`.

- **Count:** 40 files match `NNNN-<slug>.sh`. README.md is not one of them.
- **Highest number:** 0037
- **Note:** three numbers are used twice, so there are only 37 distinct numbers (0001–0037):
  - 0009: `claude-next-guardrail-parity` and `start-latency-router`
  - 0016: `autonomy-sweep-band-plist` and `w3-hook-registration`
  - 0021: `cwdchanged-slot-replace` and `fleet-hook-parity`

## The three highest-numbered migrations

(The summaries come from each file's `migration-step` header comment.)

- **0037 `settings-parity`**: Gives every Claude account the same settings. It backs up the four account copies of settings.json, merges the approved differences into `~/.claude/settings.json`, and replaces each account's settings.json with a symlink to that one file (operator ruling 2026-09-23: accounts are interchangeable).
- **0036 `rules-situational-exclude`**: Adds a `claudeMdExcludes` glob for `**/.claude/rules/agent-operating-lessons-situational.md` to one account's settings.json (default `~/.claude-tertiary`). That account's sessions then load only the resident half of the split rules, which makes it the test arm of an A/B test (about 24.5k fewer tokens per context).
- **0035 `workflow-concurrency`**: Sets `CLAUDE_CODE_WORKFLOW_MAX_CONCURRENT_AGENTS="12"` in every config dir's settings.json. This raises the Workflow tool's limit on agents running at once from the default of 8 on this machine to 12, so a default 10-agent research wave runs in one round instead of two.


## Tool calls (4) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/migrations && ls -la; ls | grep -E '^[0-9]{4}-.+\\.sh$' | wc -l; ls /tmp/tokeff-regate/f2/out/B09-r6/ 2>&1", "description": "List migration files and count matches"}`
   → total 848
dr-xr-xr-x@ 43 chrisren  wheel   1376 Sep 24 12:36 .
dr-xr-xr-x@ 46 chrisren  wheel   1472 Sep 24 12:36 ..
-r-xr-xr-x@  1 chrisren  wheel   3698 Sep 24 00:14 0001-migrations-ledger-scaffold.sh
-r-xr-xr-x@  1 chrisren  wheel   3396 Sep 24 00:14 0002-curl-gate-scope-registration.sh
-r-xr-xr-
2. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/migrations && for f in 0035* 0036* 0037*; do echo \"=== $f\"; head -30 \"$f\"; done", "description": "Show header comments of top three migrations"}`
   → === 0035-workflow-concurrency.sh
#!/bin/bash
# migration-class: c10
# migration-step: raise the Workflow tool's per-run concurrent agent gate to 12 (env CLAUDE_CODE_WORKFLOW_MAX_CONCURRENT_AGENTS="12" in every config dir's settings.json) so a default 10-agent research wave runs in one round instead 
3. `Bash: {"command": "cat > /tmp/tokeff-regate/f2/out/B09-r6/answer.md <<'EOF'\n# Migrations in /tmp/tokeff-regate/f2/tree/migrations\n\nMeasured with `ls | grep -E '^[0-9]{4}-.+\\.sh$' | wc -l`.\n\n- **Count:** 40 files match `NNNN-<slug>.sh`. README.md is not one of them.\n- **Highest number:** 0037\n- **N`
   → # Migrations in /tmp/tokeff-regate/f2/tree/migrations

Measured with `ls | grep -E '^[0-9]{4}-.+\.sh$' | wc -l`.
4. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B09-r6/answer.md", "headline": "There are 40 NNNN-<slug>.sh migrations and the highest is 0037 (0009, 0016 and 0021 are each used twice, so only 37 numbers are distinct). The top three are 0037 settings-parity (all accounts share one settings.json via symli`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
