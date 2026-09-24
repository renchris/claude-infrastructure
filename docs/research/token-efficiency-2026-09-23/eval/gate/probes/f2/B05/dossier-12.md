# Dossier 12

## Brief
```
Read /tmp/tokeff-gate/f2/tree/.claude/settings.json. How many entries are in permissions.allow, and how many of them start with "Bash(cc-"? List the cc- entries. Summarise in two sentences what the _why_converge note says the carve-out does NOT allow. numbers: {"allow_entries": N, "cc_entries": N}.
```

## Returned headline
permissions.allow has 37 entries, 16 of them Bash(cc-…); the _why_converge carve-out admits only the exact spelling `CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh`, and never --force, --bootstrap, another budget value or any extra flag.

## Returned numbers
`{"allow_entries": 37, "cc_entries": 16}`

## answer.md
# B05 — permissions.allow in /tmp/tokeff-gate/f2/tree/.claude/settings.json

- `permissions.allow` entries: **37**
- Entries starting with `Bash(cc-`: **16**

## The cc- entries
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
16. `Bash(cc-do --list)` (exact match, no `:*`)

## What `_why_converge` says the carve-out does NOT allow
Both deploy-live entries are exact-match with no trailing `:*`, so they admit only `CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh` and nothing else — not `--force` (which takes trunk's tip regardless of RED stamps and bypasses the T1/T1H/T2/T3 ladder), not `--bootstrap`, not any other budget value, and not a single extra flag. The note frames that narrowness as the safeguard: the grant is one spelling from the operator, and any widening of it (by an agent, for itself) is exactly what would be dangerous.


## Tool calls (3) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree/.claude && jq '.permissions.allow|length' settings.json && jq -r '.permissions.allow[]|select(startswith(\"Bash(cc-\"))' settings.json && jq -r '.. | objects | to_entries[] | select(.key|test(\"_why_converge\")) | .value' settings.json; ls /tmp/tokeff-gate/f2`
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
2. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree/.claude && jq '[.permissions.allow[]|select(startswith(\"Bash(cc-\"))]|length' settings.json && cat > /tmp/tokeff-gate/f2/out/B05-r5/answer.md <<'EOF'\n# B05 — permissions.allow in /tmp/tokeff-gate/f2/tree/.claude/settings.json\n\n- `permissions.allow` entrie`
   → 16
3. `StructuredOutput: {"answer_path": "/tmp/tokeff-gate/f2/out/B05-r5/answer.md", "headline": "permissions.allow has 37 entries, 16 of them Bash(cc-…); the _why_converge carve-out admits only the exact spelling `CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh`, and never --force, --bootstrap, another budget value`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
