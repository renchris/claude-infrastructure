# Dossier 8

## Brief
```
Read /tmp/tokeff-regate/f2/tree/.claude/settings.json. How many entries are in permissions.allow, and how many of them start with "Bash(cc-"? List the cc- entries. Summarise in two sentences what the _why_converge note says the carve-out does NOT allow. numbers: {"allow_entries": N, "cc_entries": N}.
```

## Returned headline
permissions.allow has 37 entries and 16 of them start with "Bash(cc-" (measured with jq, checked by hand); the _why_converge carve-out allows only the exact spelling `CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh`, with no --force, no --bootstrap, no other budget value and no extra flags.

## Returned numbers
`{"allow_entries": 37, "cc_entries": 16}`

## answer.md
# B05-r2: permissions.allow in /tmp/tokeff-regate/f2/tree/.claude/settings.json

## Counts (measured with `jq '.permissions.allow | length'` and `map(select(startswith("Bash(cc-")))`, then checked by hand against the file)

- `permissions.allow` entries: **37**
- Entries that start with `Bash(cc-`: **16**

## The 16 `Bash(cc-` entries (in file order)

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
16. `Bash(cc-do --list)`. This one is exact-match and has no `:*`.

The count leaves out the `bin/`-prefixed spellings (`Bash(bin/cc-bats:*)`, `Bash(bin/cc-backlog:*)`, `Bash(bin/cc-await-ping:*)`) because they do not start with `Bash(cc-`.

## What `_why_converge` says the carve-out does NOT allow (two sentences)

Both converge entries are exact-match with no trailing `:*`. That means they allow only `CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh` (as a relative path or at the absolute checkout path) and nothing else: not `--force`, which takes the tip despite RED stamps and skips the T1/T1H/T2/T3 ladder, not `--bootstrap`, not a different budget value and not even one extra flag. The carve-out is one exception that the operator granted openly. It does not let an agent widen that grant, and it does not remove the residual risks: a converge still brings along every sibling commit below the target, and it leaves the live tree unstamped until postland-verify catches up.


## Tool calls (4) with the first 300 chars of each result
1. `Read: {"file_path": "/tmp/tokeff-regate/f2/tree/.claude/settings.json"}`
   → 1	{
2	  "_what": "PROJECT-scope settings for claude-infrastructure. Loaded only when a session's cwd is this repo (or a worktree of it), so nothing here ships to any other project. Deliberately minimal: the operator's ~/.claude/settings.json owns the fleet-wide hooks, deny/ask rules and statusline. 
2. `Bash: {"command": "jq -r '.permissions.allow | length, (map(select(startswith(\"Bash(cc-\"))) | length), (.[] | select(startswith(\"Bash(cc-\")))' /tmp/tokeff-regate/f2/tree/.claude/settings.json; ls -d /tmp/tokeff-regate/f2/out/B05-r2 2>&1", "description": "Count allow entries and cc- entries with jq"}`
   → 37
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
Bash(cc-do 
3. `Write: {"file_path": "/tmp/tokeff-regate/f2/out/B05-r2/answer.md", "content": "# B05-r2: permissions.allow in /tmp/tokeff-regate/f2/tree/.claude/settings.json\n\n## Counts (measured with `jq '.permissions.allow | length'` and `map(select(startswith(\"Bash(cc-\")))`, then checked by hand against the file)\n`
   → File created successfully at: /tmp/tokeff-regate/f2/out/B05-r2/answer.md (file state is current in your context — no need to Read it back)
4. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B05-r2/answer.md", "headline": "permissions.allow has 37 entries and 16 of them start with \"Bash(cc-\" (measured with jq, checked by hand); the _why_converge carve-out allows only the exact spelling `CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh``
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
