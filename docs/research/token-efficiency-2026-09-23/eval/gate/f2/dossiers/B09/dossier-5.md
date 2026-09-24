# Dossier 5

## Brief
```
List the migrations in /tmp/tokeff-gate/f2/tree/migrations: files named NNNN-<slug>.sh. How many are there and what is the highest number? For the 3 highest-numbered, give the slug and one sentence on what each does (from its header comment). numbers: {"count": N, "highest": N}.
```

## Returned headline
There are 40 migration files and the highest number is 0037. Because 0009, 0016 and 0021 are each used twice, they cover 37 distinct numbers. The three highest are 0037 settings-parity (every account shares one settings.json through symlinks), 0036 rules-situational-exclude (one account stops loading the situational rules file, for an A/B test) and 0035 workflow-concurrency (the Workflow concurrency gate goes up to 12).

## Returned numbers
`{"count": 40, "highest": 37}`

## answer.md
# Migrations in /tmp/tokeff-gate/f2/tree/migrations

**40 migration files** match `NNNN-<slug>.sh`, and the **highest number is 0037**. The only non-matching entry is `README.md`.

The numbers run 0001–0037 with no gaps, but three numbers are used twice, so there are 37 distinct numbers across 40 files:
- 0009: `claude-next-guardrail-parity`, `start-latency-router`
- 0016: `autonomy-sweep-band-plist`, `w3-hook-registration`
- 0021: `cwdchanged-slot-replace`, `fleet-hook-parity`

## The 3 highest-numbered migrations (all `migration-class: c10`, which means they edit settings.json)

- **0037 — `settings-parity`**: Backs up the four account settings.json copies, merges the ruled differences into `~/.claude/settings.json`, and replaces each account's copy with a symlink to that one file, so every account runs the same settings (operator ruling 2026-09-23: accounts are interchangeable).
- **0036 — `rules-situational-exclude`**: Adds the `claudeMdExcludes` glob `**/.claude/rules/agent-operating-lessons-situational.md` to one account's settings.json (default `~/.claude-tertiary`). That account then stops loading the situational half of the rules file (about 24.5k tokens per context), which makes it the treatment arm of the rules-split A/B test.
- **0035 — `workflow-concurrency`**: Sets `CLAUDE_CODE_WORKFLOW_MAX_CONCURRENT_AGENTS="12"` in every config dir's settings.json. The Workflow tool's concurrency gate then rises from 8 (the default on this 10-core box) to 12, so a default 10-agent research wave runs in one round instead of two.


## Tool calls (5) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree/migrations && ls | grep -E '^[0-9]{4}-.*\\.sh$' | wc -l; ls | grep -E '^[0-9]{4}-.*\\.sh$' | sort | tail -5; ls | grep -vE '^[0-9]{4}-.*\\.sh$' | head -30", "description": "Count migrations and list highest-numbered"}`
   →       40
0033-mail-images-auto.sh
0034-artifact-off-fleetwide.sh
0035-workflow-concurrency.sh
0036-rules-situational-exclude.sh
0037-settings-parity.sh
README.md
2. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree/migrations && ls | grep -E '^[0-9]{4}-.*\\.sh$' | cut -c1-4 | sort | uniq -d; ls | grep -E '^[0-9]{4}-.*\\.sh$' | cut -c1-4 | tr '\\n' ' '; echo; for f in 0035-*.sh 0036-*.sh 0037-*.sh; do echo \"== $f\"; head -25 \"$f\"; done", "description": "Check numberin`
   → 0009
0016
0021
0001 0002 0003 0004 0005 0006 0007 0008 0009 0009 0010 0011 0012 0013 0014 0015 0016 0016 0017 0018 0019 0020 0021 0021 0022 0023 0024 0025 0026 0027 0028 0029 0030 0031 0032 0033 0034 0035 0036 0037 
== 0035-workflow-concurrency.sh
#!/bin/bash
# migration-class: c10
# migration-step:
3. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree/migrations && ls 0009-* 0016-* 0021-*; ls -la | head -3; mkdir -p /tmp/tokeff-gate/f2/out/B09-r4", "description": "List duplicate-numbered migrations"}`
   → 0009-claude-next-guardrail-parity.sh
0009-start-latency-router.sh
0016-autonomy-sweep-band-plist.sh
0016-w3-hook-registration.sh
0021-cwdchanged-slot-replace.sh
0021-fleet-hook-parity.sh
total 848
dr-xr-xr-x@ 43 chrisren  wheel   1376 Sep 24 00:14 .
dr-xr-xr-x@ 46 chrisren  wheel   1472 Sep 24 10:27
4. `Write: {"file_path": "/tmp/tokeff-gate/f2/out/B09-r4/answer.md", "content": "# Migrations in /tmp/tokeff-gate/f2/tree/migrations\n\n**40 migration files** match `NNNN-<slug>.sh`, and the **highest number is 0037**. The only non-matching entry is `README.md`.\n\nThe numbers run 0001–0037 with no gaps, but t`
   → File created successfully at: /tmp/tokeff-gate/f2/out/B09-r4/answer.md (file state is current in your context — no need to Read it back)
5. `StructuredOutput: {"answer_path": "/tmp/tokeff-gate/f2/out/B09-r4/answer.md", "headline": "There are 40 migration files and the highest number is 0037. Because 0009, 0016 and 0021 are each used twice, they cover 37 distinct numbers. The three highest are 0037 settings-parity (every account shares one settings.json th`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
