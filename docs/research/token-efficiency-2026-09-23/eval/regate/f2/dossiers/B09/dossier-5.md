# Dossier 5

## Brief
```
List the migrations in /tmp/tokeff-regate/f2/tree/migrations: files named NNNN-<slug>.sh. How many are there and what is the highest number? For the 3 highest-numbered, give the slug and one sentence on what each does (from its header comment). numbers: {"count": N, "highest": N}.
```

## Returned headline
The directory has 40 NNNN-<slug>.sh migrations numbered up to 0037, with 0009, 0016 and 0021 each used twice. The three highest are 0037 settings-parity (every account's settings.json becomes a symlink to one file), 0036 rules-situational-exclude (one account stops loading the situational rules, as an A/B arm) and 0035 workflow-concurrency (the Workflow concurrent-agent limit goes up to 12).

## Returned numbers
`{"count": 40, "highest": 37}`

## answer.md
# Migrations in /tmp/tokeff-regate/f2/tree/migrations

**Count: 40** files match `NNNN-<slug>.sh`. **Highest number: 0037.** The only other file in the directory is `README.md`.

The numbering runs 0001–0037, but three numbers are used twice, so the directory holds 40 files rather than 37:
- 0009: `claude-next-guardrail-parity`, `start-latency-router`
- 0016: `autonomy-sweep-band-plist`, `w3-hook-registration`
- 0021: `cwdchanged-slot-replace`, `fleet-hook-parity`

## The three highest-numbered migrations

1. **0037 — `settings-parity`**: Backs up the four account copies of settings.json, merges their agreed differences into `~/.claude/settings.json`, and replaces each account's settings.json with a symlink to that one file, so every account runs identical settings (operator ruling 2026-09-23).
2. **0036 — `rules-situational-exclude`**: Adds the `claudeMdExcludes` glob `**/.claude/rules/agent-operating-lessons-situational.md` to one account's settings.json (default `~/.claude-tertiary`). That account stops loading the situational half of the rules (~24.5k tokens per context) and becomes the treatment arm of an A/B test of the rules split.
3. **0035 — `workflow-concurrency`**: Sets `CLAUDE_CODE_WORKFLOW_MAX_CONCURRENT_AGENTS="12"` in every config dir's settings.json, which raises the Workflow tool's per-run concurrent-agent limit from the core-derived default of 8 to 12. A default 10-agent research wave then runs in one round instead of two.

All three are migration class `c10`, meaning they edit settings.json.


## Tool calls (4) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/migrations && ls | grep -E '^[0-9]{4}-.+\\.sh$' | sort | tee /dev/stderr | wc -l; ls | grep -vE '^[0-9]{4}-.+\\.sh$'", "description": "List numbered migration files and count them"}`
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
3. `Bash: {"command": "mkdir -p /tmp/tokeff-regate/f2/out/B09-r4 && cat > /tmp/tokeff-regate/f2/out/B09-r4/answer.md <<'EOF'\n# Migrations in /tmp/tokeff-regate/f2/tree/migrations\n\n**Count: 40** files match `NNNN-<slug>.sh`. **Highest number: 0037.** The only other file in the directory is `README.md`.\n\nT`
   → (Bash completed with no output)
4. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B09-r4/answer.md", "headline": "The directory has 40 NNNN-<slug>.sh migrations numbered up to 0037, with 0009, 0016 and 0021 each used twice. The three highest are 0037 settings-parity (every account's settings.json becomes a symlink to one file), 0036 rule`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
