# Dossier 5

## Brief
```
Read /tmp/tokeff-regate/f2/tree/.claude/settings.json. How many entries are in permissions.allow, and how many of them start with "Bash(cc-"? List the cc- entries. Summarise in two sentences what the _why_converge note says the carve-out does NOT allow. numbers: {"allow_entries": N, "cc_entries": N}.
```

## Returned headline
permissions.allow has 37 entries and 16 of them start with "Bash(cc-"; the _why_converge carve-out matches exactly one command, `CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh`, and does not allow --force, --bootstrap, another budget value or any extra flag.

## Returned numbers
`{"allow_entries": 37, "cc_entries": 16}`

## answer.md
# B05 — permissions.allow in /tmp/tokeff-regate/f2/tree/.claude/settings.json

**`permissions.allow` has 37 entries, and 16 of them start with `Bash(cc-`.** All 37 are distinct.

Counted with `jq '.permissions.allow|length'` → 37, and with `jq '[.permissions.allow[]|select(startswith("Bash(cc-"))]|length'` → 16.

## The 16 `Bash(cc-` entries, in file order

1. `Bash(cc-bats:*)`
2. `Bash(cc-backlog:*)`
3. `Bash(cc-custody:*)`
4. `Bash(cc-decide:*)`
5. `Bash(cc-await-ping:*)`
6. `Bash(cc-wait:*)`
7. `Bash(cc-sessions:*)`
8. `Bash(cc-context:*)`
9. `Bash(cc-pane:*)`
10. `Bash(cc-where:*)`
11. `Bash(cc-blockers:*)`
12. `Bash(cc-eligible:*)`
13. `Bash(cc-premise:*)`
14. `Bash(cc-claude-bin:*)`
15. `Bash(cc-in-kitty:*)`
16. `Bash(cc-do --list)`

These do not count toward the 16, because they do not start with `Bash(cc-`: `Bash(bin/cc-bats:*)`, `Bash(bin/cc-backlog:*)` and `Bash(bin/cc-await-ping:*)`.

## What the `_why_converge` note says the carve-out does NOT allow

Both converge entries are exact matches with no trailing `:*`. So the only command they allow is `CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh` (as a relative path or as the absolute path to the shared checkout). They do not allow `--force`, which takes the trunk tip even with RED stamps and skips the T1/T1H/T2/T3 ladder. They also do not allow `--bootstrap`, a different budget value, or even one extra flag. The note says a wider pattern is exactly what would be dangerous. It also says the carve-out does not remove the residual risk: a converge still carries every sibling commit below the target, and the live tree stays unstamped until postland-verify catches up.


## Tool calls (4) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/.claude && jq '.permissions.allow | length' settings.json && jq -r '.permissions.allow[] | select(startswith(\"Bash(cc-\"))' settings.json && jq -r '.permissions.allow[]' settings.json && grep -n '_why_converge' -A3 settings.json; jq '.. | objects | ._why_c`
   → 37
Bash(cc-bats:*)
Bash(cc-backlog:*)
Bash(cc-custody:*)
Bash(cc-decide:*)
Bash(cc-await-ping:*)
Bash(cc-wait:*)
Bash(cc-sessions:*)
Bash(cc-context:*)
Bash(cc-pane:*)
Bash(cc-where:*)
Bash(cc-blockers:*)
Bash(cc-eligible:*)
Bash(cc-premise:*)
Bash(cc-claude-bin:*)
Bash(cc-in-kitty:*)
Bash(cc-do --l
2. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/.claude && jq '[.permissions.allow[]|select(startswith(\"Bash(cc-\"))]|length' settings.json; jq '.permissions.allow|length' settings.json; jq '.permissions.allow|unique|length' settings.json", "description": "Confirm counts of allow and cc- entries"}`
   → 16
37
37
3. `Bash: {"command": "mkdir -p /tmp/tokeff-regate/f2/out/B05-r5 && cat > /tmp/tokeff-regate/f2/out/B05-r5/answer.md <<'EOF'\n# B05 — permissions.allow in /tmp/tokeff-regate/f2/tree/.claude/settings.json\n\n**`permissions.allow` has 37 entries, and 16 of them start with `Bash(cc-`.** All 37 are distinct.\n\nC`
   → (Bash completed with no output)
4. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B05-r5/answer.md", "headline": "permissions.allow has 37 entries and 16 of them start with \"Bash(cc-\"; the _why_converge carve-out matches exactly one command, `CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh`, and does not allow --force, --bootst`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
