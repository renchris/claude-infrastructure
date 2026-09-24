# Dossier 4

## Brief
```
Read /tmp/tokeff-regate/f2/tree/.claude/settings.json. How many entries are in permissions.allow, and how many of them start with "Bash(cc-"? List the cc- entries. Summarise in two sentences what the _why_converge note says the carve-out does NOT allow. numbers: {"allow_entries": N, "cc_entries": N}.
```

## Returned headline
permissions.allow has 37 entries and 16 start with "Bash(cc-". The _why_converge carve-out is exact-match: it admits only `CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh`, and not --force, --bootstrap, another budget value or any extra flag.

## Returned numbers
`{"allow_entries": 37, "cc_entries": 16}`

## answer.md
# B05 — permissions.allow in /tmp/tokeff-regate/f2/tree/.claude/settings.json

`permissions.allow` has **37** entries. **16** of them start with `Bash(cc-`:

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
16. `Bash(cc-do --list)`. This is the only exact-match entry. It has no `:*`.

## What `_why_converge` says the carve-out does NOT allow

The two converge entries are exact-match with no trailing `:*`. They admit only `CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh`. They do not admit `--force`, which would take the tip regardless of RED stamps and bypass the T1/T1H/T2/T3 ladder. They also do not admit `--bootstrap`, any other budget value, or even one extra flag. The note also says the carve-out does not stop a converge from carrying every sibling commit below the target. It does not stamp the live tree until postland-verify catches up either. The note states that residual openly: it was already true of T2, and the only thing that changes is who decides when to converge.

Counted with `jq '.permissions.allow|length'` and `select(startswith("Bash(cc-"))`.


## Tool calls (3) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/.claude && jq '.permissions.allow|length' settings.json; jq -r '.permissions.allow[]|select(startswith(\"Bash(cc-\"))' settings.json; jq '[.permissions.allow[]|select(startswith(\"Bash(cc-\"))]|length' settings.json; grep -n '_why_converge' -A3 settings.jso`
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
2. `Bash: {"command": "mkdir -p /tmp/tokeff-regate/f2/out/B05-r1 && cat > /tmp/tokeff-regate/f2/out/B05-r1/answer.md <<'EOF'\n# B05 — permissions.allow in /tmp/tokeff-regate/f2/tree/.claude/settings.json\n\n`permissions.allow` has **37** entries. **16** of them start with `Bash(cc-`:\n\n1. `Bash(cc-bats:*)`\n`
   → (Bash completed with no output)
3. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B05-r1/answer.md", "headline": "permissions.allow has 37 entries and 16 start with \"Bash(cc-\". The _why_converge carve-out is exact-match: it admits only `CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh`, and not --force, --bootstrap, another budg`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
