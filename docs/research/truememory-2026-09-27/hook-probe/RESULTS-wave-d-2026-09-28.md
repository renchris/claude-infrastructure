# X6 live delivery probes — Wave D (2026-09-28)

## #18 episodic cue in the memory nudge

Binary: Claude Code 2.1.280 (`/Users/chrisren/.claude-280/node_modules/.bin/claude`), `claude -p`, Haiku 4.5
(`claude-haiku-4-5-20251001`). Script: `episodic-run.sh` beside this file. Run against the `tma-d-episodic`
worktree with the owner's `hooks/memory-nudge.sh` hunk applied UNCOMMITTED (the hunk that sources
`hooks/lib/episodic_cue.sh` and prints the cue-only JSON on a non-due prompt).

Command:

```
bash docs/research/truememory-2026-09-27/hook-probe/episodic-run.sh /Users/chrisren/.claude-280/node_modules/.bin/claude
```

Output:

```
2.1.280 (Claude Code)
cue      zebra-lantern migration
control  NONE
```

| Arm | UserPromptSubmit hook | Answer | Reading |
|---|---|---|---|
| `cue` | replays the JSON `hooks/memory-nudge.sh` rendered hermetically from the prompt "like we did before with the zebra-lantern migration" on a non-due count (`MEMORY_NUDGE_INTERVAL=1000`), so it carries the cue alone | `zebra-lantern migration` | delivered: the model read the query out of the cue line in its context |
| `control` | none | `NONE` | the instrument can say no |

The question asks for the text between the single quotes of a line beginning "EPISODIC CUE", so the
expected answer (an invented topic) is not in the prompt. PASS.
