# Dossier 3

## Brief
```
List the migrations in /tmp/tokeff-regate/f2/tree/migrations: files named NNNN-<slug>.sh. How many are there and what is the highest number? For the 3 highest-numbered, give the slug and one sentence on what each does (from its header comment). numbers: {"count": N, "highest": N}.
```

## Returned headline
There are 40 migration files named NNNN-<slug>.sh and the highest number is 0037. They use only the 37 numbers 0001-0037 because 0009, 0016 and 0021 each appear twice. The top three are 0037 settings-parity (every account's settings.json becomes a symlink to one file), 0036 rules-situational-exclude (one account stops loading the situational rules file for an A/B test) and 0035 workflow-concurrency (Workflow's concurrent-agent limit goes up to 12).

## Returned numbers
`{"count": 40, "highest": 37}`

## answer.md
# Migrations in /tmp/tokeff-regate/f2/tree/migrations

**Count: 40** files matching `NNNN-<slug>.sh` (measured: `ls | grep -E '^[0-9]{4}-.+\.sh$' | wc -l`).
**Highest number: 0037** (37).

Note: the 40 files use only 37 distinct numbers (0001-0037, no gaps), because three numbers are used twice:
- 0009: `claude-next-guardrail-parity`, `start-latency-router`
- 0016: `autonomy-sweep-band-plist`, `w3-hook-registration`
- 0021: `cwdchanged-slot-replace`, `fleet-hook-parity`

The directory also contains README.md, which is not a migration and is not counted.

## The 3 highest-numbered

1. **0037 `settings-parity`**: Makes every Claude account use one settings.json. It backs up the four account copies, merges the differences that were ruled on into `~/.claude/settings.json`, and replaces each account's settings.json with a symlink to that file (operator ruling 2026-09-23: accounts are interchangeable).
2. **0036 `rules-situational-exclude`**: Adds the `claudeMdExcludes` glob `**/.claude/rules/agent-operating-lessons-situational.md` to one account's settings.json (default `~/.claude-tertiary`), so sessions on that account stop loading the situational half of the rules file. This account is the test arm of the rules-split A/B and saves about 24.5k tokens per context.
3. **0035 `workflow-concurrency`**: Sets `CLAUDE_CODE_WORKFLOW_MAX_CONCURRENT_AGENTS="12"` in every config dir's settings.json, raising the Workflow tool's per-run concurrent-agent gate from the default of 8 on this box to 12. A default 10-agent research wave then runs in one round instead of two.


## Tool calls (4) with the first 300 chars of each result
1. `Bash: {"command": "ls -la /tmp/tokeff-regate/f2/tree/migrations | head -100; ls /tmp/tokeff-regate/f2/tree/migrations | wc -l; ls -d /tmp/tokeff-regate/f2/out/B09-r3/ 2>&1", "description": "List migrations directory and check output dir"}`
   → total 848
dr-xr-xr-x@ 43 chrisren  wheel   1376 Sep 24 12:36 .
dr-xr-xr-x@ 46 chrisren  wheel   1472 Sep 24 12:36 ..
-r-xr-xr-x@  1 chrisren  wheel   3698 Sep 24 00:14 0001-migrations-ledger-scaffold.sh
-r-xr-xr-x@  1 chrisren  wheel   3396 Sep 24 00:14 0002-curl-gate-scope-registration.sh
-r-xr-xr-
2. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/migrations; ls | grep -E '^[0-9]{4}-.+\\.sh$' | wc -l; ls | grep -E '^[0-9]{4}-.+\\.sh$' | cut -c1-4 | sort -u | wc -l; for f in 0035* 0036* 0037*; do echo \"=== $f\"; head -30 \"$f\"; done", "description": "Count migrations and read top headers"}`
   →       40
      37
=== 0035-workflow-concurrency.sh
#!/bin/bash
# migration-class: c10
# migration-step: raise the Workflow tool's per-run concurrent agent gate to 12 (env CLAUDE_CODE_WORKFLOW_MAX_CONCURRENT_AGENTS="12" in every config dir's settings.json) so a default 10-agent research wave runs in 
3. `Bash: {"command": "cat > /tmp/tokeff-regate/f2/out/B09-r3/answer.md <<'EOF'\n# Migrations in /tmp/tokeff-regate/f2/tree/migrations\n\n**Count: 40** files matching `NNNN-<slug>.sh` (measured: `ls | grep -E '^[0-9]{4}-.+\\.sh$' | wc -l`).\n**Highest number: 0037** (37).\n\nNote: the 40 files use only 37 dis`
   → (Bash completed with no output)
4. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B09-r3/answer.md", "headline": "There are 40 migration files named NNNN-<slug>.sh and the highest number is 0037. They use only the 37 numbers 0001-0037 because 0009, 0016 and 0021 each appear twice. The top three are 0037 settings-parity (every account's s`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
