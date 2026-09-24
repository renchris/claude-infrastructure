# Dossier 6

## Brief
```
List the migrations in /tmp/tokeff-regate/f2/tree/migrations: files named NNNN-<slug>.sh. How many are there and what is the highest number? For the 3 highest-numbered, give the slug and one sentence on what each does (from its header comment). numbers: {"count": N, "highest": N}.
```

## Returned headline
There are 40 NNNN-<slug>.sh migrations, numbered up to 0037 (0009, 0016 and 0021 are each used twice); the three highest are 0035 workflow-concurrency (raises the Workflow agent limit to 12), 0036 rules-situational-exclude (one account stops loading the situational rules file) and 0037 settings-parity (every account shares one symlinked settings.json).

## Returned numbers
`{"count": 40, "highest": 37}`

## answer.md
# Migrations in /tmp/tokeff-regate/f2/tree/migrations

Measured with `ls | grep -E '^[0-9]{4}-.+\.sh$' | wc -l`.

- Count: 40 files match `NNNN-<slug>.sh` (README.md is the only other entry in the directory).
- Highest number: 0037.
- Three numbers appear twice, so there are 37 distinct numbers (0001-0037) across 40 files:
  - 0009: claude-next-guardrail-parity, start-latency-router
  - 0016: autonomy-sweep-band-plist, w3-hook-registration
  - 0021: cwdchanged-slot-replace, fleet-hook-parity

## The three highest-numbered migrations (from their header comments)

- **0037 settings-parity**: Makes every Claude account use one settings.json. It backs up the four account copies, merges the approved differences into ~/.claude/settings.json, and replaces each account's settings.json with a symlink to that file. The header cites an operator ruling of 2026-09-23 that accounts are interchangeable.
- **0036 rules-situational-exclude**: Adds a `claudeMdExcludes` glob for `**/.claude/rules/agent-operating-lessons-situational.md` to one account's settings.json (default ~/.claude-tertiary). That account then stops loading the situational half of the rules file, about 24.5k tokens per context, and serves as the test arm of the rules-split A/B.
- **0035 workflow-concurrency**: Sets `CLAUDE_CODE_WORKFLOW_MAX_CONCURRENT_AGENTS="12"` in every config dir's settings.json. This raises the Workflow tool's limit on agents running at once from the default 8 to 12, so a default 10-agent research wave runs in one round instead of two.

All three are class c10 migrations, meaning they edit settings.json.


## Tool calls (4) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/migrations && ls | head -50; echo; ls | grep -E '^[0-9]{4}-.+\\.sh$' | wc -l; ls | grep -vE '^[0-9]{4}-.+\\.sh$'; ls -d /tmp/tokeff-regate/f2/out/B09-r2 2>&1", "description": "List migrations directory and count matching files"}`
   → 0001-migrations-ledger-scaffold.sh
0002-curl-gate-scope-registration.sh
0003-cloud-fleet-link-drive.sh
0004-lead-deathwatch-l1-activation.sh
0005-goal-inert-watch-registration.sh
0006-coldcompile-admit-registration.sh
0007-mailbox-wake-arm-registration.sh
0008-auth-timeseries-activation.sh
0009-clau
2. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/migrations && for f in 0035-*.sh 0036-*.sh 0037-*.sh; do echo \"=== $f\"; head -25 \"$f\"; done", "description": "Show header comments of top three migrations"}`
   → === 0035-workflow-concurrency.sh
#!/bin/bash
# migration-class: c10
# migration-step: raise the Workflow tool's per-run concurrent agent gate to 12 (env CLAUDE_CODE_WORKFLOW_MAX_CONCURRENT_AGENTS="12" in every config dir's settings.json) so a default 10-agent research wave runs in one round instead 
3. `Bash: {"command": "cat > /tmp/tokeff-regate/f2/out/B09-r2/answer.md <<'EOF'\n# Migrations in /tmp/tokeff-regate/f2/tree/migrations\n\nMeasured with `ls | grep -E '^[0-9]{4}-.+\\.sh$' | wc -l`.\n\n- Count: 40 files match `NNNN-<slug>.sh` (README.md is the only other entry in the directory).\n- Highest numb`
   → (Bash completed with no output)
4. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B09-r2/answer.md", "headline": "There are 40 NNNN-<slug>.sh migrations, numbered up to 0037 (0009, 0016 and 0021 are each used twice); the three highest are 0035 workflow-concurrency (raises the Workflow agent limit to 12), 0036 rules-situational-exclude (o`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
