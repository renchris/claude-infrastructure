# Dossier 1

## Brief
```
List the migrations in /tmp/tokeff-regate/f2/tree/migrations: files named NNNN-<slug>.sh. How many are there and what is the highest number? For the 3 highest-numbered, give the slug and one sentence on what each does (from its header comment). numbers: {"count": N, "highest": N}.
```

## Returned headline
There are 40 NNNN-<slug>.sh migrations, numbered up to 0037 (0009, 0016 and 0021 are each used twice). The three highest are 0037 settings-parity (one symlinked settings.json for every account), 0036 rules-situational-exclude (one account stops loading the situational rules file, as an A/B arm) and 0035 workflow-concurrency (raises the Workflow agent cap to 12).

## Returned numbers
`{"count": 40, "highest": 37}`

## answer.md
# Migrations in /tmp/tokeff-regate/f2/tree/migrations

**40 files match `NNNN-<slug>.sh`; the highest number is 0037.** (The only non-matching file is README.md.)

Numbers run 0001-0037, and three are used twice: 0009 (claude-next-guardrail-parity, start-latency-router), 0016 (autonomy-sweep-band-plist, w3-hook-registration) and 0021 (cwdchanged-slot-replace, fleet-hook-parity). That makes 37 distinct numbers across 40 files.

## The 3 highest-numbered

- **0037 — settings-parity**: makes every Claude account use one settings.json. It backs up the four per-account copies, merges the approved differences into `~/.claude/settings.json`, and replaces each account's file with a symlink to it.
- **0036 — rules-situational-exclude**: adds a `claudeMdExcludes` glob for `agent-operating-lessons-situational.md` to one account's settings.json (by default `~/.claude-tertiary`). That account stops loading the situational half of the rules, which is the A/B arm of the rules split and saves about 24.5k tokens per context.
- **0035 — workflow-concurrency**: sets `CLAUDE_CODE_WORKFLOW_MAX_CONCURRENT_AGENTS="12"` in every config dir's settings.json. A default 10-agent research wave then runs in one round instead of two; the default cap on this 10-core box is 8.


## Tool calls (4) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/migrations && ls | grep -E '^[0-9]{4}-.+\\.sh$' | sort; echo; ls | grep -E '^[0-9]{4}-.+\\.sh$' | wc -l; ls | grep -vE '^[0-9]{4}-.+\\.sh$'", "description": "List numbered migration scripts and count them"}`
   → 0001-migrations-ledger-scaffold.sh
0002-curl-gate-scope-registration.sh
0003-cloud-fleet-link-drive.sh
0004-lead-deathwatch-l1-activation.sh
0005-goal-inert-watch-registration.sh
0006-coldcompile-admit-registration.sh
0007-mailbox-wake-arm-registration.sh
0008-auth-timeseries-activation.sh
0009-clau
2. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/migrations && for f in 0035-*.sh 0036-*.sh 0037-*.sh; do echo \"== $f\"; sed -n '1,30p' \"$f\"; done", "description": "Read header comments of the three highest migrations"}`
   → == 0035-workflow-concurrency.sh
#!/bin/bash
# migration-class: c10
# migration-step: raise the Workflow tool's per-run concurrent agent gate to 12 (env CLAUDE_CODE_WORKFLOW_MAX_CONCURRENT_AGENTS="12" in every config dir's settings.json) so a default 10-agent research wave runs in one round instead o
3. `Bash: {"command": "mkdir -p /tmp/tokeff-regate/f2/out/B09-r5 && cat > /tmp/tokeff-regate/f2/out/B09-r5/answer.md <<'EOF'\n# Migrations in /tmp/tokeff-regate/f2/tree/migrations\n\n**40 files match `NNNN-<slug>.sh`; the highest number is 0037.** (The only non-matching file is README.md.)\n\nNumbers run 0001`
   → (Bash completed with no output)
4. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B09-r5/answer.md", "headline": "There are 40 NNNN-<slug>.sh migrations, numbered up to 0037 (0009, 0016 and 0021 are each used twice). The three highest are 0037 settings-parity (one symlinked settings.json for every account), 0036 rules-situational-exclude`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
