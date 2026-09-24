# Dossier 5

## Brief
```
List the migrations in /tmp/tokeff-regate/f2/tree/migrations: files named NNNN-<slug>.sh. How many are there and what is the highest number? For the 3 highest-numbered, give the slug and one sentence on what each does (from its header comment). numbers: {"count": N, "highest": N}.
```

## Returned headline
There are 40 NNNN-<slug>.sh migrations and the highest number is 0037. They cover 37 distinct numbers because 0009, 0016 and 0021 are each used twice. The top three are 0037 settings-parity (one symlinked settings.json shared by all accounts), 0036 rules-situational-exclude (one account stops loading the situational rules file, as an A/B arm) and 0035 workflow-concurrency (Workflow agent limit raised to 12).

## Returned numbers
`{"count": 40, "highest": 37}`

## answer.md
# Migrations in /tmp/tokeff-regate/f2/tree/migrations

**There are 40 migration files named `NNNN-<slug>.sh`, and the highest number is 0037.**

The numbers run from 0001 to 0037, which gives 37 distinct numbers. Three numbers are used twice, and that accounts for the 3 extra files:
- 0009: `claude-next-guardrail-parity`, `start-latency-router`
- 0016: `autonomy-sweep-band-plist`, `w3-hook-registration`
- 0021: `cwdchanged-slot-replace`, `fleet-hook-parity`

The only other file in the directory is `README.md`, which is not a migration.

## The 3 highest-numbered

| # | Slug | What it does (from its header comment) |
|---|---|---|
| 0037 | `settings-parity` | Makes every Claude account use one settings.json: it backs up the four account copies, merges the differences the operator approved into `~/.claude/settings.json`, and replaces each account's file with a symlink to it (class c10). |
| 0036 | `rules-situational-exclude` | Adds the `claudeMdExcludes` glob `**/.claude/rules/agent-operating-lessons-situational.md` to one account's settings.json (by default `~/.claude-tertiary`). That account's sessions then skip the situational rules file, about 24.5k tokens per context, and serve as the test arm of an A/B on the rules split. |
| 0035 | `workflow-concurrency` | Sets `CLAUDE_CODE_WORKFLOW_MAX_CONCURRENT_AGENTS="12"` in every config dir's settings.json. The binary's default limit on this box is 8, and at 12 a default 10-agent research wave runs in one round instead of two. |


## Tool calls (5) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/migrations && ls | grep -E '^[0-9]{4}-.+\\.sh$' | wc -l; ls | grep -E '^[0-9]{4}-.+\\.sh$' | sort | tail -5; ls | grep -vE '^[0-9]{4}-.+\\.sh$' | head -20", "description": "Count and list migration files"}`
   →       40
0033-mail-images-auto.sh
0034-artifact-off-fleetwide.sh
0035-workflow-concurrency.sh
0036-rules-situational-exclude.sh
0037-settings-parity.sh
README.md
2. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/migrations && ls | grep -E '^[0-9]{4}-.+\\.sh$' | cut -c1-4 | sort | uniq -d; for f in 0035-*.sh 0036-*.sh 0037-*.sh; do echo \"== $f\"; sed -n '1,30p' \"$f\"; done", "description": "Check duplicate numbers and read top-3 headers"}`
   → 0009
0016
0021
== 0035-workflow-concurrency.sh
#!/bin/bash
# migration-class: c10
# migration-step: raise the Workflow tool's per-run concurrent agent gate to 12 (env CLAUDE_CODE_WORKFLOW_MAX_CONCURRENT_AGENTS="12" in every config dir's settings.json) so a default 10-agent research wave runs in one 
3. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/migrations && ls | grep -E '^[0-9]{4}-(.+)\\.sh$' | sort | grep -E '^(0009|0016|0021)'; ls | grep -E '^[0-9]{4}-.+\\.sh$' | cut -c1-4 | sort -u | wc -l; ls | grep -E '^[0-9]{4}-.+\\.sh$' | sort | head -3", "description": "Show duplicate-numbered migrations"`
   → 0009-claude-next-guardrail-parity.sh
0009-start-latency-router.sh
0016-autonomy-sweep-band-plist.sh
0016-w3-hook-registration.sh
0021-cwdchanged-slot-replace.sh
0021-fleet-hook-parity.sh
      37
0001-migrations-ledger-scaffold.sh
0002-curl-gate-scope-registration.sh
0003-cloud-fleet-link-drive.sh
4. `Bash: {"command": "mkdir -p /tmp/tokeff-regate/f2/out/B09-r4 && cat > /tmp/tokeff-regate/f2/out/B09-r4/answer.md <<'EOF'\n# Migrations in /tmp/tokeff-regate/f2/tree/migrations\n\n**There are 40 migration files named `NNNN-<slug>.sh`, and the highest number is 0037.**\n\nThe numbers run from 0001 to 0037, `
   → (Bash completed with no output)
5. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B09-r4/answer.md", "headline": "There are 40 NNNN-<slug>.sh migrations and the highest number is 0037. They cover 37 distinct numbers because 0009, 0016 and 0021 are each used twice. The top three are 0037 settings-parity (one symlinked settings.json shared`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
