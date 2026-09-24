# Dossier 2

## Brief
```
List the migrations in /tmp/tokeff-regate/f2/tree/migrations: files named NNNN-<slug>.sh. How many are there and what is the highest number? For the 3 highest-numbered, give the slug and one sentence on what each does (from its header comment). numbers: {"count": N, "highest": N}.
```

## Returned headline
There are 40 migration files and the highest number is 0037; 37 numbers are used because 0009, 0016 and 0021 each have two files. The top three are 0037-settings-parity (links every account to one settings.json), 0036-rules-situational-exclude (one account stops loading the situational rules file, as the test arm of an A/B comparison) and 0035-workflow-concurrency (Workflow concurrent-agent limit raised to 12).

## Returned numbers
`{"count": 40, "highest": 37}`

## answer.md
# Migrations in /tmp/tokeff-regate/f2/tree/migrations

**40 migration files (`NNNN-<slug>.sh`); the highest number is 0037.**

The only other file in the directory is `README.md`, which does not match the pattern. There are 37 distinct numbers (0001–0037, no gaps). Three numbers each have two files:
- 0009: `claude-next-guardrail-parity`, `start-latency-router`
- 0016: `autonomy-sweep-band-plist`, `w3-hook-registration`
- 0021: `cwdchanged-slot-replace`, `fleet-hook-parity`

## The 3 highest-numbered

| # | Slug | What it does (from its header) |
|---|------|------|
| 0037 | `settings-parity` | Makes every Claude account run one settings.json. It backs up the four account copies, folds the ruled differences into `~/.claude/settings.json`, and replaces each account's settings.json with a symlink to that file (operator ruling 2026-09-23: accounts are interchangeable). |
| 0036 | `rules-situational-exclude` | Adds the `claudeMdExcludes` glob `**/.claude/rules/agent-operating-lessons-situational.md` to one account's settings.json (default `~/.claude-tertiary`). That account stops loading the situational half of the rules, about 24.5k tokens per context, and acts as the A/B treatment arm of the rules split. |
| 0035 | `workflow-concurrency` | Sets `CLAUDE_CODE_WORKFLOW_MAX_CONCURRENT_AGENTS="12"` in every config dir's settings.json. This raises the Workflow tool's per-run concurrent-agent gate from the default of 8 on this box to 12, so a default 10-agent research wave runs in one round instead of two. |

All three are class `c10` migrations, because they edit settings.json.


## Tool calls (5) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/migrations && ls | grep -E '^[0-9]{4}-.+\\.sh$' | wc -l; ls | grep -E '^[0-9]{4}-.+\\.sh$' | sort | tail -5; ls | grep -vE '^[0-9]{4}-.+\\.sh$' | head", "description": "Count migration files and list highest"}`
   →       40
0033-mail-images-auto.sh
0034-artifact-off-fleetwide.sh
0035-workflow-concurrency.sh
0036-rules-situational-exclude.sh
0037-settings-parity.sh
README.md
2. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/migrations && ls | grep -E '^[0-9]{4}-.+\\.sh$' | cut -c1-4 | uniq -d; ls | grep -E '^[0-9]{4}-.+\\.sh$' | grep -E '^00(1[0-9]|2[0-9])' ; for f in 0035-*.sh 0036-*.sh 0037-*.sh; do echo \"== $f\"; head -30 \"$f\"; done", "description": "Check duplicate numb`
   → 0009
0016
0021
0010-postland-band-plist.sh
0011-accounts-board-wiring.sh
0012-mailbox-wake-arm-stop-rearm.sh
0013-claude-next-hooks-unfork.sh
0014-subagent-stop-registration.sh
0015-memory-index-drain-registration.sh
0016-autonomy-sweep-band-plist.sh
0016-w3-hook-registration.sh
0017-filechanged-cwd
3. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/migrations && ls | grep -E '^(0009|0016|0021)-'; ls | grep -E '^[0-9]{4}-.+\\.sh$' | cut -c1-4 | sort -u | wc -l; mkdir -p /tmp/tokeff-regate/f2/out/B09-r1", "description": "Show duplicate-numbered files and unique count"}`
   → 0009-claude-next-guardrail-parity.sh
0009-start-latency-router.sh
0016-autonomy-sweep-band-plist.sh
0016-w3-hook-registration.sh
0021-cwdchanged-slot-replace.sh
0021-fleet-hook-parity.sh
      37
4. `Bash: {"command": "cat > /tmp/tokeff-regate/f2/out/B09-r1/answer.md <<'EOF'\n# Migrations in /tmp/tokeff-regate/f2/tree/migrations\n\n**40 migration files (`NNNN-<slug>.sh`); the highest number is 0037.**\n\nThe only other file in the directory is `README.md`, which does not match the pattern. There are 3`
   → (Bash completed with no output)
5. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B09-r1/answer.md", "headline": "There are 40 migration files and the highest number is 0037; 37 numbers are used because 0009, 0016 and 0021 each have two files. The top three are 0037-settings-parity (links every account to one settings.json), 0036-rules-s`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
