# Dossier 4

## Brief
```
List the migrations in /tmp/tokeff-regate/f2/tree/migrations: files named NNNN-<slug>.sh. How many are there and what is the highest number? For the 3 highest-numbered, give the slug and one sentence on what each does (from its header comment). numbers: {"count": N, "highest": N}.
```

## Returned headline
There are 40 migrations named NNNN-<slug>.sh and the highest is 0037 (numbers 0009, 0016 and 0021 are each used twice). The top three are 0037 settings-parity (all accounts share one symlinked settings.json), 0036 rules-situational-exclude (one account stops loading the situational rules file) and 0035 workflow-concurrency (the Workflow agent limit goes up to 12).

## Returned numbers
`{"count": 40, "highest": 37}`

## answer.md
# Migrations in /tmp/tokeff-regate/f2/tree/migrations

There are **40** files named `NNNN-<slug>.sh`, and the highest number is **0037**. The only other file in the directory is `README.md`.

Three numbers are used twice, so the 40 files cover 37 distinct numbers (0001–0037):
- 0009: `claude-next-guardrail-parity` and `start-latency-router`
- 0016: `autonomy-sweep-band-plist` and `w3-hook-registration`
- 0021: `cwdchanged-slot-replace` and `fleet-hook-parity`

## The three highest-numbered

| # | Slug | What it does (from its header) |
|---|------|------|
| 0037 | `settings-parity` | Makes every Claude account use one settings.json. It backs up the four per-account copies, merges the ruled differences into `~/.claude/settings.json`, and replaces each account's settings.json with a symlink to that file (operator ruling 2026-09-23: accounts are interchangeable). |
| 0036 | `rules-situational-exclude` | Adds the `claudeMdExcludes` glob `**/.claude/rules/agent-operating-lessons-situational.md` to one account's settings.json (default `~/.claude-tertiary`). That account then loads only the resident half of the split rules file, which saves about 24.5k tokens per context and serves as the A/B arm. |
| 0035 | `workflow-concurrency` | Sets `CLAUDE_CODE_WORKFLOW_MAX_CONCURRENT_AGENTS="12"` in every config dir's settings.json, raising the Workflow tool's per-run agent gate from 8 (the default on this 10-core machine). A default 10-agent research wave then runs in one round instead of two. |

All three are class `c10`: they edit settings.json.


## Tool calls (4) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/migrations && ls | grep -E '^[0-9]{4}-.+\\.sh$' | sort; echo; ls | grep -E '^[0-9]{4}-.+\\.sh$' | wc -l; echo; ls | grep -vE '^[0-9]{4}-.+\\.sh$'", "description": "List numbered migration scripts and count them"}`
   → 0001-migrations-ledger-scaffold.sh
0002-curl-gate-scope-registration.sh
0003-cloud-fleet-link-drive.sh
0004-lead-deathwatch-l1-activation.sh
0005-goal-inert-watch-registration.sh
0006-coldcompile-admit-registration.sh
0007-mailbox-wake-arm-registration.sh
0008-auth-timeseries-activation.sh
0009-clau
2. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/migrations && for f in 0035-*.sh 0036-*.sh 0037-*.sh; do echo \"=== $f\"; head -30 \"$f\"; done", "description": "Show header comments of the three highest migrations"}`
   → === 0035-workflow-concurrency.sh
#!/bin/bash
# migration-class: c10
# migration-step: raise the Workflow tool's per-run concurrent agent gate to 12 (env CLAUDE_CODE_WORKFLOW_MAX_CONCURRENT_AGENTS="12" in every config dir's settings.json) so a default 10-agent research wave runs in one round instead 
3. `Bash: {"command": "mkdir -p /tmp/tokeff-regate/f2/out/B09-r8 && cat > /tmp/tokeff-regate/f2/out/B09-r8/answer.md <<'EOF'\n# Migrations in /tmp/tokeff-regate/f2/tree/migrations\n\nThere are **40** files named `NNNN-<slug>.sh`, and the highest number is **0037**. The only other file in the directory is `REA`
   → (Bash completed with no output)
4. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B09-r8/answer.md", "headline": "There are 40 migrations named NNNN-<slug>.sh and the highest is 0037 (numbers 0009, 0016 and 0021 are each used twice). The top three are 0037 settings-parity (all accounts share one symlinked settings.json), 0036 rules-situa`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
