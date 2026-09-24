# Dossier 7

## Brief
```
List the migrations in /tmp/tokeff-regate/f2/tree/migrations: files named NNNN-<slug>.sh. How many are there and what is the highest number? For the 3 highest-numbered, give the slug and one sentence on what each does (from its header comment). numbers: {"count": N, "highest": N}.
```

## Returned headline
There are 40 NNNN-<slug>.sh migrations and the highest number is 0037. They use 37 distinct numbers because 0009, 0016 and 0021 each appear twice. The three highest are 0037 settings-parity, which makes every account share one settings.json via symlinks; 0036 rules-situational-exclude, which excludes the situational rules file on one account as an A/B arm; and 0035 workflow-concurrency, which raises the Workflow concurrent-agent limit to 12.

## Returned numbers
`{"count": 40, "highest": 37}`

## answer.md
# Migrations in /tmp/tokeff-regate/f2/tree/migrations

**Count: 40** files named `NNNN-<slug>.sh` (measured: `ls | grep -E '^[0-9]{4}-.+\.sh$' | wc -l`).
**Highest number: 0037** (measured: sorted listing). The only non-matching entry is `README.md`.

Numbers run 0001 to 0037. Three numbers are used twice, which is why there are 40 files but only 37
distinct numbers (measured: `cut -c1-4 | sort | uniq -d`):
- 0009: `0009-claude-next-guardrail-parity.sh`, `0009-start-latency-router.sh`
- 0016: `0016-autonomy-sweep-band-plist.sh`, `0016-w3-hook-registration.sh`
- 0021: `0021-cwdchanged-slot-replace.sh`, `0021-fleet-hook-parity.sh`

## The 3 highest-numbered (taken from each file's `migration-step` header)

- **0037 `settings-parity`**: Makes every Claude account use one settings.json. It backs up the four account copies, folds the ruled differences into `~/.claude/settings.json`, and replaces each account's settings.json with a symlink to it (operator ruling 2026-09-23: accounts are interchangeable).
- **0036 `rules-situational-exclude`**: Adds a `claudeMdExcludes` glob for `**/.claude/rules/agent-operating-lessons-situational.md` to one account's settings.json (default `~/.claude-tertiary`), so that account stops loading the situational half of the rules as the A/B arm of the rules split. The header measures this at about 24.5k fewer tokens per context.
- **0035 `workflow-concurrency`**: Sets `CLAUDE_CODE_WORKFLOW_MAX_CONCURRENT_AGENTS="12"` in every config dir's settings.json, raising the Workflow tool's per-run concurrent-agent gate from the default 8 on this machine to 12, so a default 10-agent research wave runs in one round instead of two.

All three are class c10 migrations, because each one edits settings.json.


## Tool calls (4) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/migrations && ls -la | head -50; echo; ls | grep -E '^[0-9]{4}-.+\\.sh$' | wc -l; ls | grep -E '^[0-9]{4}-.+\\.sh$' | sort | tail -5; ls /tmp/tokeff-regate/f2/out/B09-r7/ 2>&1", "description": "List migrations and count matching files"}`
   → Exit code 1
total 848
dr-xr-xr-x@ 43 chrisren  wheel   1376 Sep 24 12:36 .
dr-xr-xr-x@ 46 chrisren  wheel   1472 Sep 24 12:36 ..
-r-xr-xr-x@  1 chrisren  wheel   3698 Sep 24 00:14 0001-migrations-ledger-scaffold.sh
-r-xr-xr-x@  1 chrisren  wheel   3396 Sep 24 00:14 0002-curl-gate-scope-registration.
2. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/migrations && ls -A | grep -vE '^[0-9]{4}-.+\\.sh$'; ls | grep -E '^[0-9]{4}-' | cut -c1-4 | sort | uniq -d; for f in 0035* 0036* 0037*; do echo \"== $f\"; head -30 \"$f\"; done; grep -n -iE 'duplicate|collision|same number|0009|0016|0021' README.md | head"`
   → README.md
0009
0016
0021
== 0035-workflow-concurrency.sh
#!/bin/bash
# migration-class: c10
# migration-step: raise the Workflow tool's per-run concurrent agent gate to 12 (env CLAUDE_CODE_WORKFLOW_MAX_CONCURRENT_AGENTS="12" in every config dir's settings.json) so a default 10-agent research wave ru
3. `Bash: {"command": "mkdir -p /tmp/tokeff-regate/f2/out/B09-r7 && cat > /tmp/tokeff-regate/f2/out/B09-r7/answer.md <<'EOF'\n# Migrations in /tmp/tokeff-regate/f2/tree/migrations\n\n**Count: 40** files named `NNNN-<slug>.sh` (measured: `ls | grep -E '^[0-9]{4}-.+\\.sh$' | wc -l`).\n**Highest number: 0037** (`
   → (Bash completed with no output)
4. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B09-r7/answer.md", "headline": "There are 40 NNNN-<slug>.sh migrations and the highest number is 0037. They use 37 distinct numbers because 0009, 0016 and 0021 each appear twice. The three highest are 0037 settings-parity, which makes every account share on`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
