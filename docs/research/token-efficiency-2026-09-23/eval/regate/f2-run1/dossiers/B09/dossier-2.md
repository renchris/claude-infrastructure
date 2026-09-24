# Dossier 2

## Brief
```
List the migrations in /tmp/tokeff-regate/f2/tree/migrations: files named NNNN-<slug>.sh. How many are there and what is the highest number? For the 3 highest-numbered, give the slug and one sentence on what each does (from its header comment). numbers: {"count": N, "highest": N}.
```

## Returned headline
There are 40 migration files named NNNN-<slug>.sh and the highest number is 0037; numbers 0009, 0016 and 0021 are each used twice. The top three are 0037 settings-parity (all accounts share one symlinked settings.json), 0036 rules-situational-exclude (one account stops loading the situational rules file, as an A/B arm) and 0035 workflow-concurrency (the Workflow agent limit rises to 12).

## Returned numbers
`{"count": 40, "highest": 37}`

## answer.md
# Migrations in /tmp/tokeff-regate/f2/tree/migrations

**40 migration files** match `NNNN-<slug>.sh`; the **highest number is 0037**.

The count exceeds the highest number because three numbers are used twice (0009, 0016, 0021), so 37 distinct numbers (0001–0037) cover 40 files. The only other file in the directory is `README.md`.

## The 3 highest-numbered

| # | Slug | What it does (from its header) |
|---|------|------|
| 0037 | `settings-parity` | Gives every Claude account the same settings.json. It backs up the four per-account copies, merges the approved differences into `~/.claude/settings.json`, and replaces each account's file with a symlink to that one file. This follows the operator ruling of 2026-09-23 that accounts are interchangeable. |
| 0036 | `rules-situational-exclude` | Adds the `claudeMdExcludes` glob `**/.claude/rules/agent-operating-lessons-situational.md` to one account's settings.json (default `~/.claude-tertiary`). That account then loads only the resident half of the rules, about 24.5k fewer tokens per context. This is the treatment arm of an A/B test on the rules split. |
| 0035 | `workflow-concurrency` | Sets `CLAUDE_CODE_WORKFLOW_MAX_CONCURRENT_AGENTS="12"` in every config dir's settings.json. The Workflow tool's per-run agent limit rises from 8 (the default on this 10-core box) to 12, so a default 10-agent research wave runs in one round instead of two. |

All three are class `c10` because they edit settings.json.


## Tool calls (4) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/migrations && ls | grep -E '^[0-9]{4}-.+\\.sh$' | wc -l; ls | grep -E '^[0-9]{4}-.+\\.sh$' | sort | tail -5; ls | grep -vE '^[0-9]{4}-.+\\.sh$' | head -20", "description": "Count migration files and list highest"}`
   →       40
0033-mail-images-auto.sh
0034-artifact-off-fleetwide.sh
0035-workflow-concurrency.sh
0036-rules-situational-exclude.sh
0037-settings-parity.sh
README.md
2. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/migrations && ls | grep -E '^[0-9]{4}-.+\\.sh$' | cut -c1-4 | sort | uniq -d; ls | grep -E '^[0-9]{4}-.+\\.sh$' | cut -c1-4 | sort -u | wc -l; for f in 0035-*.sh 0036-*.sh 0037-*.sh; do echo \"=== $f\"; head -25 \"$f\"; done", "description": "Check duplicat`
   → 0009
0016
0021
      37
=== 0035-workflow-concurrency.sh
#!/bin/bash
# migration-class: c10
# migration-step: raise the Workflow tool's per-run concurrent agent gate to 12 (env CLAUDE_CODE_WORKFLOW_MAX_CONCURRENT_AGENTS="12" in every config dir's settings.json) so a default 10-agent research wave ru
3. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/migrations && ls | grep -E '^(0009|0016|0021)-'; mkdir -p /tmp/tokeff-regate/f2/out/B09-r1 && cat > /tmp/tokeff-regate/f2/out/B09-r1/answer.md <<'EOF'\n# Migrations in /tmp/tokeff-regate/f2/tree/migrations\n\n**40 migration files** match `NNNN-<slug>.sh`; t`
   → 0009-claude-next-guardrail-parity.sh
0009-start-latency-router.sh
0016-autonomy-sweep-band-plist.sh
0016-w3-hook-registration.sh
0021-cwdchanged-slot-replace.sh
0021-fleet-hook-parity.sh
4. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B09-r1/answer.md", "headline": "There are 40 migration files named NNNN-<slug>.sh and the highest number is 0037; numbers 0009, 0016 and 0021 are each used twice. The top three are 0037 settings-parity (all accounts share one symlinked settings.json), 0036 `
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
