# Dossier 10

## Brief
```
Read /tmp/tokeff-gate/f2/tree/.claude/settings.json. How many entries are in permissions.allow, and how many of them start with "Bash(cc-"? List the cc- entries. Summarise in two sentences what the _why_converge note says the carve-out does NOT allow. numbers: {"allow_entries": N, "cc_entries": N}.
```

## Returned headline
permissions.allow has 37 entries and 16 of them start with "Bash(cc-". The _why_converge carve-out allows only the exact `CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh` and nothing else: no --force, no --bootstrap, no other budget value and no extra flags.

## Returned numbers
`{"allow_entries": 37, "cc_entries": 16}`

## answer.md
# B05 — permissions.allow in /tmp/tokeff-gate/f2/tree/.claude/settings.json

- `permissions.allow` has **37** entries.
- **16** of them start with `Bash(cc-`:

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
16. `Bash(cc-do --list)` (exact match, with no `:*`)

(Entries spelled `Bash(bin/cc-…)` are not counted, because they do not begin with `Bash(cc-`.)

## What `_why_converge` says the carve-out does NOT allow

Both converge entries match exactly, with no trailing `:*`. So they allow only `CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh` and nothing else. Specifically, they do not allow `--force` (which takes the trunk tip whatever its RED stamps and skips the T1/T1H/T2/T3 ladder), `--bootstrap`, any other budget value, or even one extra flag. Every other deploy-live invocation stays under the `_why_repo_tooling` exclusion and still prompts. Only the operator can grant this narrow exception. An agent may not widen it, because its rule is "an agent may not alter the gating and then deploy".


## Tool calls (3) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree/.claude && jq '.permissions.allow|length' settings.json && jq -r '.permissions.allow[]|select(startswith(\"Bash(cc-\"))' settings.json && jq '[.permissions.allow[]|select(startswith(\"Bash(cc-\"))]|length' settings.json && grep -n '_why_converge' settings.jso`
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
2. `Bash: {"command": "mkdir -p /tmp/tokeff-gate/f2/out/B05-r8 && cat > /tmp/tokeff-gate/f2/out/B05-r8/answer.md <<'EOF'\n# B05 — permissions.allow in /tmp/tokeff-gate/f2/tree/.claude/settings.json\n\n- `permissions.allow` has **37** entries.\n- **16** of them start with `Bash(cc-`:\n\n1. `Bash(cc-bats:*)`\n2`
   → (Bash completed with no output)
3. `StructuredOutput: {"answer_path": "/tmp/tokeff-gate/f2/out/B05-r8/answer.md", "headline": "permissions.allow has 37 entries and 16 of them start with \"Bash(cc-\". The _why_converge carve-out allows only the exact `CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh` and nothing else: no --force, no --bootstrap, `
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
