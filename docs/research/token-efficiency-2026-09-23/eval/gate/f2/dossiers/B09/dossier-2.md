# Dossier 2

## Brief
```
List the migrations in /tmp/tokeff-gate/f2/tree/migrations: files named NNNN-<slug>.sh. How many are there and what is the highest number? For the 3 highest-numbered, give the slug and one sentence on what each does (from its header comment). numbers: {"count": N, "highest": N}.
```

## Returned headline
There are 40 NNNN-<slug>.sh migrations (0009, 0016 and 0021 each used twice) and the highest is 0037. The top three are 0037-settings-parity (one symlinked settings.json for every account), 0036-rules-situational-exclude (one account's claudeMdExcludes drops the situational rules file as an A/B arm) and 0035-workflow-concurrency (sets the workflow concurrent-agent limit to 12).

## Returned numbers
`{"count": 40, "highest": 37}`

## answer.md
# Migrations in /tmp/tokeff-gate/f2/tree/migrations

**40 files** match `NNNN-<slug>.sh`; the **highest number is 0037**. (40 files over 37 numbers because 0009, 0016 and 0021 each appear twice; README.md is the only other file.)

## The 3 highest-numbered

| # | slug | what it does (from its header) |
|---|---|---|
| 0037 | settings-parity | Makes every Claude account run one settings.json: backs up the four per-account copies, folds the ruled differences into `~/.claude/settings.json`, and replaces each account's settings.json with a symlink to it (operator ruling 2026-09-23 that accounts are interchangeable). |
| 0036 | rules-situational-exclude | Adds the `claudeMdExcludes` glob for `agent-operating-lessons-situational.md` to one account's settings.json (default `~/.claude-tertiary`), so that account loads only the resident rules half: the A/B arm of the rules split, saving ~24.5k tokens per context. |
| 0035 | workflow-concurrency | Sets `CLAUDE_CODE_WORKFLOW_MAX_CONCURRENT_AGENTS="12"` in every config dir's settings.json, so a default 10-agent research wave runs in one round instead of two (the binary's default gate on this box is 8). |

All three are class c10 (they edit settings.json).


## Tool calls (4) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree/migrations && ls | grep -E '^[0-9]{4}-.+\\.sh$' | wc -l; ls | grep -E '^[0-9]{4}-.+\\.sh$' | sort | tail -5; ls | grep -vE '^[0-9]{4}-.+\\.sh$' | head -20", "description": "Count and list numbered migration files"}`
   →       40
0033-mail-images-auto.sh
0034-artifact-off-fleetwide.sh
0035-workflow-concurrency.sh
0036-rules-situational-exclude.sh
0037-settings-parity.sh
README.md
2. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree/migrations && ls | grep -E '^[0-9]{4}-' | cut -c1-4 | sort | uniq -d; ls | head -3; for f in 0035-*.sh 0036-*.sh 0037-*.sh; do echo \"=== $f\"; head -25 \"$f\"; done", "description": "Check duplicate numbers and read top-3 headers"}`
   → 0009
0016
0021
0001-migrations-ledger-scaffold.sh
0002-curl-gate-scope-registration.sh
0003-cloud-fleet-link-drive.sh
=== 0035-workflow-concurrency.sh
#!/bin/bash
# migration-class: c10
# migration-step: raise the Workflow tool's per-run concurrent agent gate to 12 (env CLAUDE_CODE_WORKFLOW_MAX_CONC
3. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree/migrations && ls 0009-* 0016-* 0021-*; mkdir -p /tmp/tokeff-gate/f2/out/B09-r1 && cat > /tmp/tokeff-gate/f2/out/B09-r1/answer.md <<'EOF'\n# Migrations in /tmp/tokeff-gate/f2/tree/migrations\n\n**40 files** match `NNNN-<slug>.sh`; the **highest number is 0037*`
   → 0009-claude-next-guardrail-parity.sh
0009-start-latency-router.sh
0016-autonomy-sweep-band-plist.sh
0016-w3-hook-registration.sh
0021-cwdchanged-slot-replace.sh
0021-fleet-hook-parity.sh
4. `StructuredOutput: {"answer_path": "/tmp/tokeff-gate/f2/out/B09-r1/answer.md", "headline": "There are 40 NNNN-<slug>.sh migrations (0009, 0016 and 0021 each used twice) and the highest is 0037. The top three are 0037-settings-parity (one symlinked settings.json for every account), 0036-rules-situational-exclude (one a`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
