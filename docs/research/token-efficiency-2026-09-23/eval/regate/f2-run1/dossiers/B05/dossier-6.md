# Dossier 6

## Brief
```
Read /tmp/tokeff-regate/f2/tree/.claude/settings.json. How many entries are in permissions.allow, and how many of them start with "Bash(cc-"? List the cc- entries. Summarise in two sentences what the _why_converge note says the carve-out does NOT allow. numbers: {"allow_entries": N, "cc_entries": N}.
```

## Returned headline
permissions.allow has 37 entries and 16 of them start with "Bash(cc-" (counted with jq and checked by hand); _why_converge says its two exact-match entries allow only `CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh` and nothing else, so no --force, no --bootstrap, no other budget value and no extra flag.

## Returned numbers
`{"allow_entries": 37, "cc_entries": 16}`

## answer.md
# B05-r6: permissions.allow in /tmp/tokeff-regate/f2/tree/.claude/settings.json

Counts were measured with `jq '.permissions.allow | length'` and `jq 'map(select(startswith("Bash(cc-")))'`, then checked by reading the file by hand.

- permissions.allow has **37** entries.
- **16** of them start with `Bash(cc-`. The `bin/cc-*` spellings do not count because they start with `Bash(bin/`.

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
The carve-out's two entries are exact-match with no trailing `:*`. They allow only `CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh` (as a relative path or at its absolute path) and nothing else: no `--force` (which would bypass the T1/T1H/T2/T3 ladder and RED stamps), no `--bootstrap`, no other budget value and no extra flag. The note also says the carve-out does not let an agent widen the grant for itself, because the operator gave this one exception openly under version control. It does not remove the residual risks either: a converge still carries every sibling commit below the target, and the live tree stays unstamped until postland-verify catches up.


## Tool calls (4) with the first 300 chars of each result
1. `Read: {"file_path": "/tmp/tokeff-regate/f2/tree/.claude/settings.json"}`
   → 1	{
2	  "_what": "PROJECT-scope settings for claude-infrastructure. Loaded only when a session's cwd is this repo (or a worktree of it), so nothing here ships to any other project. Deliberately minimal: the operator's ~/.claude/settings.json owns the fleet-wide hooks, deny/ask rules and statusline. 
2. `Bash: {"command": "jq -r '.permissions.allow | length, (map(select(startswith(\"Bash(cc-\"))) | length), (.[] | select(startswith(\"Bash(cc-\")))' /tmp/tokeff-regate/f2/tree/.claude/settings.json; ls -la /tmp/tokeff-regate/f2/out/B05-r6/ 2>&1", "description": "Count allow entries and cc- entries with jq"}`
   → Exit code 1
37
16
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
3. `Bash: {"command": "mkdir -p /tmp/tokeff-regate/f2/out/B05-r6 && cat > /tmp/tokeff-regate/f2/out/B05-r6/answer.md <<'EOF'\n# B05-r6: permissions.allow in /tmp/tokeff-regate/f2/tree/.claude/settings.json\n\nCounts were measured with `jq '.permissions.allow | length'` and `jq 'map(select(startswith(\"Bash(cc`
   → (Bash completed with no output)
4. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B05-r6/answer.md", "headline": "permissions.allow has 37 entries and 16 of them start with \"Bash(cc-\" (counted with jq and checked by hand); _why_converge says its two exact-match entries allow only `CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
