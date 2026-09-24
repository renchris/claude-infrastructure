# Dossier 6

## Brief
```
List the migrations in /tmp/tokeff-gate/f2/tree/migrations: files named NNNN-<slug>.sh. How many are there and what is the highest number? For the 3 highest-numbered, give the slug and one sentence on what each does (from its header comment). numbers: {"count": N, "highest": N}.
```

## Returned headline
There are 40 migration files named NNNN-<slug>.sh and the highest number is 0037. Numbers 0001-0037 are all present, and 0009, 0016 and 0021 are each used by two files. The three highest are 0037 settings-parity (one symlinked settings.json for every account), 0036 rules-situational-exclude (one account stops loading the situational rules file, about 24.5k tokens saved per context) and 0035 workflow-concurrency (Workflow concurrent-agent limit raised from 8 to 12).

## Returned numbers
`{"count": 40, "highest": 37}`

## answer.md
# Migrations in /tmp/tokeff-gate/f2/tree/migrations

**Count: 40** migration files match `NNNN-<slug>.sh` (measured: `ls | grep -E '^[0-9]{4}-.+\.sh$' | wc -l`).
**Highest number: 0037** (`0037-settings-parity.sh`).

Numbers 0001–0037 are all present, which gives 37 distinct numbers. Three numbers are each used by two files, so the file count is 40:
- 0009: `0009-claude-next-guardrail-parity.sh`, `0009-start-latency-router.sh`
- 0016: `0016-autonomy-sweep-band-plist.sh`, `0016-w3-hook-registration.sh`
- 0021: `0021-cwdchanged-slot-replace.sh`, `0021-fleet-hook-parity.sh`

The only other entry in the directory is `README.md`, which is not a migration.

## The 3 highest-numbered migrations

- **0037, `settings-parity`**: Makes every Claude account use one settings.json. It backs up the four per-account copies, merges the approved differences into `~/.claude/settings.json`, and replaces each account's settings.json with a symlink to that file (operator ruling 2026-09-23: accounts are interchangeable).
- **0036, `rules-situational-exclude`**: Adds the `claudeMdExcludes` glob `**/.claude/rules/agent-operating-lessons-situational.md` to one account's settings.json (default `~/.claude-tertiary`). That account then loads only the resident half of the split rules file, which saves about 24.5k tokens per context. It is the A/B arm of the rules split.
- **0035, `workflow-concurrency`**: Sets `CLAUDE_CODE_WORKFLOW_MAX_CONCURRENT_AGENTS="12"` in every config dir's settings.json. This raises the Workflow tool's per-run concurrent-agent limit from 8 (the default on this machine) to 12, so a default 10-agent research wave runs in one round instead of two.


## Tool calls (5) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree/migrations && ls | grep -E '^[0-9]{4}-.+\\.sh$' | wc -l; ls | grep -E '^[0-9]{4}-.+\\.sh$' | sort | tail -5; ls | grep -vE '^[0-9]{4}-.+\\.sh$' | head; ls -d /tmp/tokeff-gate/f2/out/B09-r2 2>&1", "description": "Count and list migration files"}`
   →       40
0033-mail-images-auto.sh
0034-artifact-off-fleetwide.sh
0035-workflow-concurrency.sh
0036-rules-situational-exclude.sh
0037-settings-parity.sh
README.md
/tmp/tokeff-gate/f2/out/B09-r2
2. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree/migrations && ls | grep -E '^[0-9]{4}-.+\\.sh$' | cut -c1-4 | sort | uniq -c | awk '$1>1'; ls | grep -E '^[0-9]{4}-.+\\.sh$' | head -3; for f in 0035-*.sh 0036-*.sh 0037-*.sh; do echo \"== $f\"; head -25 \"$f\"; done", "description": "Check duplicate numbers `
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
3. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree/migrations && ls | grep -E '^(0009|0016|0021)-'; ls | grep -E '^[0-9]{4}-.+\\.sh$' | cut -c1-4 | sort -u | wc -l; ls -A | grep -vE '^[0-9]{4}-.+\\.sh$'", "description": "Show duplicate-numbered files and non-migration entries"}`
   → 0009-claude-next-guardrail-parity.sh
0009-start-latency-router.sh
0016-autonomy-sweep-band-plist.sh
0016-w3-hook-registration.sh
0021-cwdchanged-slot-replace.sh
0021-fleet-hook-parity.sh
      37
README.md
4. `Bash: {"command": "cat > /tmp/tokeff-gate/f2/out/B09-r2/answer.md <<'EOF'\n# Migrations in /tmp/tokeff-gate/f2/tree/migrations\n\n**Count: 40** migration files match `NNNN-<slug>.sh` (measured: `ls | grep -E '^[0-9]{4}-.+\\.sh$' | wc -l`).\n**Highest number: 0037** (`0037-settings-parity.sh`).\n\nNumbers `
   → (Bash completed with no output)
5. `StructuredOutput: {"answer_path": "/tmp/tokeff-gate/f2/out/B09-r2/answer.md", "headline": "There are 40 migration files named NNNN-<slug>.sh and the highest number is 0037. Numbers 0001-0037 are all present, and 0009, 0016 and 0021 are each used by two files. The three highest are 0037 settings-parity (one symlinked `
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
