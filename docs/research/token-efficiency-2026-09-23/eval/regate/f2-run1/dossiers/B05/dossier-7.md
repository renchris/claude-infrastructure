# Dossier 7

## Brief
```
Read /tmp/tokeff-regate/f2/tree/.claude/settings.json. How many entries are in permissions.allow, and how many of them start with "Bash(cc-"? List the cc- entries. Summarise in two sentences what the _why_converge note says the carve-out does NOT allow. numbers: {"allow_entries": N, "cc_entries": N}.
```

## Returned headline
permissions.allow has 37 entries and 16 of them start with "Bash(cc-" (checked with jq). The _why_converge carve-out allows only the exact command `CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh` (relative or absolute path). It does not allow --force, --bootstrap, any other budget value or any extra flag or argument.

## Returned numbers
`{"allow_entries": 37, "cc_entries": 16}`

## answer.md
# B05-r3: permissions.allow in /tmp/tokeff-regate/f2/tree/.claude/settings.json

## Counts (measured with `jq '.permissions.allow | length'` and a `startswith("Bash(cc-")` filter; hand count of lines 10-54 agrees)

- `permissions.allow` entries: **37**
- Entries starting with `Bash(cc-`: **16**

## The 16 cc- entries

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
16. `Bash(cc-do --list)`. This is the only exact-match entry, with no `:*`.

These 16 do not include the `bin/cc-*` spellings (`Bash(bin/cc-bats:*)`, `Bash(bin/cc-backlog:*)`, `Bash(bin/cc-await-ping:*)`), because they start with `Bash(bin/`, not `Bash(cc-`.

## What the _why_converge carve-out does NOT allow (two sentences)

Both deploy-live entries match exactly, with no trailing `:*`. So the only command they allow is `CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh` (either the relative path or the absolute path to the claude-infrastructure checkout). They do not allow `--force` (which takes the tip regardless of RED stamps and skips the T1/T1H/T2/T3 ladder), `--bootstrap`, any other `CC_DEPLOY_MAX_LAG_COMMITS` value, or even one extra flag or argument; all of those still prompt. The note also says the carve-out does not let an agent widen the grant itself, because it is one version-controlled exception granted by the operator. It also does not remove the residuals T2 already had: a converge still carries every sibling commit below the target, and the live tree stays unstamped until postland-verify catches up.


## Tool calls (4) with the first 300 chars of each result
1. `Read: {"file_path": "/tmp/tokeff-regate/f2/tree/.claude/settings.json"}`
   → 1	{
2	  "_what": "PROJECT-scope settings for claude-infrastructure. Loaded only when a session's cwd is this repo (or a worktree of it), so nothing here ships to any other project. Deliberately minimal: the operator's ~/.claude/settings.json owns the fleet-wide hooks, deny/ask rules and statusline. 
2. `Bash: {"command": "jq -r '.permissions.allow | length, ([.[]|select(startswith(\"Bash(cc-\"))]|length), (.[]|select(startswith(\"Bash(cc-\")))' /tmp/tokeff-regate/f2/tree/.claude/settings.json; ls -d /tmp/tokeff-regate/f2/out/B05-r3/ 2>&1", "description": "Count allow entries and cc- entries"}`
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
3. `Write: {"file_path": "/tmp/tokeff-regate/f2/out/B05-r3/answer.md", "content": "# B05-r3: permissions.allow in /tmp/tokeff-regate/f2/tree/.claude/settings.json\n\n## Counts (measured with `jq '.permissions.allow | length'` and a `startswith(\"Bash(cc-\")` filter; hand count of lines 10-54 agrees)\n\n- `perm`
   → File created successfully at: /tmp/tokeff-regate/f2/out/B05-r3/answer.md (file state is current in your context — no need to Read it back)
4. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B05-r3/answer.md", "headline": "permissions.allow has 37 entries and 16 of them start with \"Bash(cc-\" (checked with jq). The _why_converge carve-out allows only the exact command `CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh` (relative or absol`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
