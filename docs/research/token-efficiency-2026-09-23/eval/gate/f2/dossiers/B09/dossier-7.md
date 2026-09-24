# Dossier 7

## Brief
```
List the migrations in /tmp/tokeff-gate/f2/tree/migrations: files named NNNN-<slug>.sh. How many are there and what is the highest number? For the 3 highest-numbered, give the slug and one sentence on what each does (from its header comment). numbers: {"count": N, "highest": N}.
```

## Returned headline
There are 40 NNNN-<slug>.sh migrations, numbered up to 0037 (only 37 distinct numbers, because 0009, 0016 and 0021 are each used twice); the top three are 0037 settings-parity (one symlinked settings.json for every account), 0036 rules-situational-exclude (drops the situational rules file on one account as an A/B arm) and 0035 workflow-concurrency (raises the Workflow agent limit to 12).

## Returned numbers
`{"count": 40, "highest": 37}`

## answer.md
# Migrations in /tmp/tokeff-gate/f2/tree/migrations

**Count: 40** files matching `NNNN-<slug>.sh` (measured: `ls | grep -E '^[0-9]{4}-.+\.sh$' | wc -l`). The only other file in the directory is README.md.
**Highest number: 0037** (37).

Note: the files use only 37 distinct numbers, because three numbers are each used by two files:
- 0009: `claude-next-guardrail-parity`, `start-latency-router`
- 0016: `autonomy-sweep-band-plist`, `w3-hook-registration`
- 0021: `cwdchanged-slot-replace`, `fleet-hook-parity`

## The 3 highest-numbered

- **0037 `settings-parity`**: Makes every Claude account run one settings.json. It backs up the four per-account copies, folds the approved differences into `~/.claude/settings.json`, and replaces each account's settings.json with a symlink to that file (operator ruling 2026-09-23: accounts are interchangeable).
- **0036 `rules-situational-exclude`**: Adds a `claudeMdExcludes` glob for `**/.claude/rules/agent-operating-lessons-situational.md` to one account's settings.json (default `~/.claude-tertiary`). That account then loads only the resident half of the split rules file (about 24.5k fewer tokens per context), which makes it the A/B arm.
- **0035 `workflow-concurrency`**: Sets `CLAUDE_CODE_WORKFLOW_MAX_CONCURRENT_AGENTS="12"` in every config dir's settings.json. This raises the Workflow tool's concurrent-agent limit from the default of 8 on this machine to 12, so a default 10-agent research wave runs in one round instead of two.


## Tool calls (5) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree/migrations && ls | grep -E '^[0-9]{4}-.+\\.sh$' | wc -l; ls | grep -E '^[0-9]{4}-.+\\.sh$' | sort | tail -5; ls | grep -vE '^[0-9]{4}-.+\\.sh$' | head; ls -d /tmp/tokeff-gate/f2/out/B09-r7 2>&1", "description": "Count migrations and list highest numbered"}`
   →       40
0033-mail-images-auto.sh
0034-artifact-off-fleetwide.sh
0035-workflow-concurrency.sh
0036-rules-situational-exclude.sh
0037-settings-parity.sh
README.md
/tmp/tokeff-gate/f2/out/B09-r7
2. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree/migrations && ls | grep -E '^[0-9]{4}-.+\\.sh$' | sort | head -3; ls | grep -E '^[0-9]{4}' | cut -c1-4 | sort | uniq -d; for f in 0035* 0036* 0037*; do echo \"== $f\"; head -25 \"$f\"; done", "description": "Check duplicates and read top-3 headers"}`
   → 0001-migrations-ledger-scaffold.sh
0002-curl-gate-scope-registration.sh
0003-cloud-fleet-link-drive.sh
0009
0016
0021
== 0035-workflow-concurrency.sh
#!/bin/bash
# migration-class: c10
# migration-step: raise the Workflow tool's per-run concurrent agent gate to 12 (env CLAUDE_CODE_WORKFLOW_MAX_CONCU
3. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree/migrations && ls | grep -E '^(0009|0016|0021)'; ls | grep -E '^[0-9]{4}' | cut -c1-4 | sort -u | wc -l", "description": "Show duplicate-numbered migrations"}`
   → 0009-claude-next-guardrail-parity.sh
0009-start-latency-router.sh
0016-autonomy-sweep-band-plist.sh
0016-w3-hook-registration.sh
0021-cwdchanged-slot-replace.sh
0021-fleet-hook-parity.sh
      37
4. `Bash: {"command": "cat > /tmp/tokeff-gate/f2/out/B09-r7/answer.md <<'EOF'\n# Migrations in /tmp/tokeff-gate/f2/tree/migrations\n\n**Count: 40** files matching `NNNN-<slug>.sh` (measured: `ls | grep -E '^[0-9]{4}-.+\\.sh$' | wc -l`). The only other file in the directory is README.md.\n**Highest number: 003`
   → (Bash completed with no output)
5. `StructuredOutput: {"answer_path": "/tmp/tokeff-gate/f2/out/B09-r7/answer.md", "headline": "There are 40 NNNN-<slug>.sh migrations, numbered up to 0037 (only 37 distinct numbers, because 0009, 0016 and 0021 are each used twice); the top three are 0037 settings-parity (one symlinked settings.json for every account), 00`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
