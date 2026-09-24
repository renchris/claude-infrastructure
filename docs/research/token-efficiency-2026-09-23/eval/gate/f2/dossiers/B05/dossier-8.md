# Dossier 8

## Brief
```
Read /tmp/tokeff-gate/f2/tree/.claude/settings.json. How many entries are in permissions.allow, and how many of them start with "Bash(cc-"? List the cc- entries. Summarise in two sentences what the _why_converge note says the carve-out does NOT allow. numbers: {"allow_entries": N, "cc_entries": N}.
```

## Returned headline
permissions.allow has 37 entries, 16 of them start with "Bash(cc-" (cc-bats through cc-in-kitty as :* prefixes, plus the exact entry cc-do --list). The _why_converge carve-out uses exact-match entries, so the only command it admits is `CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh`: no --force, no --bootstrap, no other budget value and no extra flag.

## Returned numbers
`{"allow_entries": 37, "cc_entries": 16}`

## answer.md
# B05-r2: permissions.allow in /tmp/tokeff-gate/f2/tree/.claude/settings.json

Measured with `jq '.permissions.allow | length'` and `jq -r '.permissions.allow[] | select(startswith("Bash(cc-"))'`.

- permissions.allow entries: **37**
- Entries starting with `Bash(cc-`: **16**

## The cc- entries
1. Bash(cc-bats:*)
2. Bash(cc-backlog:*)
3. Bash(cc-custody:*)
4. Bash(cc-decide:*)
5. Bash(cc-await-ping:*)
6. Bash(cc-wait:*)
7. Bash(cc-sessions:*)
8. Bash(cc-context:*)
9. Bash(cc-pane:*)
10. Bash(cc-where:*)
11. Bash(cc-blockers:*)
12. Bash(cc-eligible:*)
13. Bash(cc-premise:*)
14. Bash(cc-claude-bin:*)
15. Bash(cc-in-kitty:*)
16. Bash(cc-do --list)

## What the _why_converge carve-out does NOT allow
The carve-out's entries are exact-match with no trailing `:*`, so they admit only the single spelling `CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh`. They do not allow `--force` (which takes the tip regardless of RED stamps and skips the T1/T1H/T2/T3 ladder), `--bootstrap`, any other lag-budget value, or even one extra flag.


## Tool calls (3) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree/.claude && jq '.permissions.allow | length' settings.json; jq -r '.permissions.allow[] | select(startswith(\"Bash(cc-\"))' settings.json; jq '.. | objects | select(has(\"_why_converge\")) | ._why_converge' settings.json; ls -la /tmp/tokeff-gate/f2/out/B05-r2/`
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
2. `Bash: {"command": "cat > /tmp/tokeff-gate/f2/out/B05-r2/answer.md <<'EOF'\n# B05-r2: permissions.allow in /tmp/tokeff-gate/f2/tree/.claude/settings.json\n\nMeasured with `jq '.permissions.allow | length'` and `jq -r '.permissions.allow[] | select(startswith(\"Bash(cc-\"))'`.\n\n- permissions.allow entries`
   → # B05-r2: permissions.allow in /tmp/tokeff-gate/f2/tree/.claude/settings.json

Measured with `jq '.permissions.allow | length'` and `jq -r '.permissions.allow[] | select(startswith("Bash(cc-"))'`.
3. `StructuredOutput: {"answer_path": "/tmp/tokeff-gate/f2/out/B05-r2/answer.md", "headline": "permissions.allow has 37 entries, 16 of them start with \"Bash(cc-\" (cc-bats through cc-in-kitty as :* prefixes, plus the exact entry cc-do --list). The _why_converge carve-out uses exact-match entries, so the only command it `
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
