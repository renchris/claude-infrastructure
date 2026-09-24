# Dossier 8

## Brief
```
List the migrations in /tmp/tokeff-gate/f2/tree/migrations: files named NNNN-<slug>.sh. How many are there and what is the highest number? For the 3 highest-numbered, give the slug and one sentence on what each does (from its header comment). numbers: {"count": N, "highest": N}.
```

## Returned headline
There are 40 migration files named NNNN-<slug>.sh and the highest is 0037 (settings-parity). They cover 37 distinct numbers because 0009, 0016 and 0021 are each used twice. The top three are 0037 settings-parity (one symlinked settings.json for every account), 0036 rules-situational-exclude (one account stops loading the situational rules file, as the A/B arm) and 0035 workflow-concurrency (the Workflow concurrent-agent limit goes to 12).

## Returned numbers
`{"count": 40, "highest": 37}`

## answer.md
# Migrations in /tmp/tokeff-gate/f2/tree/migrations

Measured with `ls | grep -E '^[0-9]{4}-.+\.sh$'` (the only other entry is README.md).

- **Count: 40** migration files named NNNN-<slug>.sh.
- **Highest number: 0037** (37).
- Numbers run 0001-0037, i.e. 37 distinct numbers; the count exceeds the highest number because three numbers are used twice: 0009, 0016 and 0021.

## The 3 highest-numbered

| # | slug | what it does (from header) |
|---|------|----------------------------|
| 0037 | settings-parity | Makes every Claude account run one settings.json: backs up the four account copies, folds the ruled differences into ~/.claude/settings.json, and replaces each account's settings.json with a symlink to it (verified by `cc-settings-parity check`). |
| 0036 | rules-situational-exclude | Adds the claudeMdExcludes glob `**/.claude/rules/agent-operating-lessons-situational.md` to one account's settings.json (default ~/.claude-tertiary) so that account stops loading the situational half of the rules, the A/B arm of the rules split (~24.5k tokens per context). |
| 0035 | workflow-concurrency | Sets env CLAUDE_CODE_WORKFLOW_MAX_CONCURRENT_AGENTS="12" in every config dir's settings.json so a default 10-agent research wave runs in one round instead of queuing behind the default gate of 8. |


## Tool calls (4) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree/migrations && ls | grep -E '^[0-9]{4}-.+\\.sh$' | wc -l; ls | grep -E '^[0-9]{4}-.+\\.sh$' | sort | tail -3; ls | grep -vE '^[0-9]{4}-.+\\.sh$' | head; ls -d /tmp/tokeff-gate/f2/out/B09-r6 2>&1", "description": "Count migrations and list top three"}`
   →       40
0035-workflow-concurrency.sh
0036-rules-situational-exclude.sh
0037-settings-parity.sh
README.md
/tmp/tokeff-gate/f2/out/B09-r6
2. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree/migrations && ls | grep -E '^[0-9]{4}-.+\\.sh$' | cut -c1-4 | uniq -c | awk '$1>1'; ls | grep -E '^[0-9]{4}-' | grep -v '\\.sh$'; for f in 0035-*.sh 0036-*.sh 0037-*.sh; do echo \"== $f\"; head -25 \"$f\"; done", "description": "Check duplicate numbers and re`
   →    2 0009
   2 0016
   2 0021
== 0035-workflow-concurrency.sh
#!/bin/bash
# migration-class: c10
# migration-step: raise the Workflow tool's per-run concurrent agent gate to 12 (env CLAUDE_CODE_WORKFLOW_MAX_CONCURRENT_AGENTS="12" in every config dir's settings.json) so a default 10-agent research wa
3. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree/migrations && ls 0009-* 0016-* 0021-*; ls | grep -E '^[0-9]{4}-.+\\.sh$' | cut -c1-4 | sort -u | wc -l\ncat > /tmp/tokeff-gate/f2/out/B09-r6/answer.md <<'EOF'\n# Migrations in /tmp/tokeff-gate/f2/tree/migrations\n\nMeasured with `ls | grep -E '^[0-9]{4}-.+\\.`
   → 0009-claude-next-guardrail-parity.sh
0009-start-latency-router.sh
0016-autonomy-sweep-band-plist.sh
0016-w3-hook-registration.sh
0021-cwdchanged-slot-replace.sh
0021-fleet-hook-parity.sh
      37
4. `StructuredOutput: {"answer_path": "/tmp/tokeff-gate/f2/out/B09-r6/answer.md", "headline": "There are 40 migration files named NNNN-<slug>.sh and the highest is 0037 (settings-parity). They cover 37 distinct numbers because 0009, 0016 and 0021 are each used twice. The top three are 0037 settings-parity (one symlinked `
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
