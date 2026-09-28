# X6 live delivery probe — #12 supersession clause in the memory nudge (Wave C, 2026-09-28)

Binary: Claude Code 2.1.280 (`/Users/chrisren/.claude-280/node_modules/.bin/claude`), `claude -p`, Haiku 4.5
(`claude-haiku-4-5-20251001`). Script: `nudge-supersession-run.sh` beside this file.

Command:

```
bash docs/research/truememory-2026-09-27/hook-probe/nudge-supersession-run.sh /Users/chrisren/.claude-280/node_modules/.bin/claude
```

Output:

```
2.1.280 (Claude Code)
nudge    ruling pending
control  NONE
```

| Arm | UserPromptSubmit hook | Answer | Reading |
|---|---|---|---|
| `nudge` | replays the nudge JSON that `hooks/memory-nudge.sh` rendered hermetically (fixture HOME/state/config/index, `MEMORY_NUDGE_INTERVAL=1`) | `ruling pending` | delivered: the model read the clause's words out of its context |
| `control` | none | `NONE` | the instrument can say no |

The question names the sentence's opening and asks for the two words after `Replaces: <practice> —`, so the
expected answer is not in the prompt. PASS.
