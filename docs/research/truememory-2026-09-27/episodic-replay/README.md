# Episodic cue — fire rate and replay (#18, truememory §3.18)

`hooks/lib/episodic_cue.sh` adds one line to the memory nudge when a typed prompt refers to earlier
work, pointing at `claude-search '<nouns>'`. It is PROVISIONAL (#35 found no gain for push consumers):
it stays only if the nightly `scripts/episodic-cue-outcome.py` shows fires followed by a search.

Files:

- `targets.jsonl`: the 4 cited misses (gap-2.md:54-57), with the real prompt text from
  `~/.claude/history-union.jsonl`, the prompt time, the incident session and the gold criterion.
- `fire-rate.sh`: scores every typed prompt in the history with the lib's own jq program.
- `replay.sh`: runs the lib's query for each target through claude-search's engine against a
  `.backup` copy of the index (a search writes `search_log`, so the live DB is never queried).

## Fire rate (2026-09-28, `bash fire-rate.sh`)

Typed = the `display` field, entries starting with `<` or `/` dropped, then the lib's own eligibility.

| Window | Eligible prompts | Fired | Rate |
|---|---|---|---|
| All history (2025-10-04 to 2026-09-28) | 29,818 | 84 | 0.28% |
| Last 30 days | 3,205 | 14 | 0.44% |

Target is at most ~1.5%; the research's narrow set fired on 35 of 2,650 (1.3%). The 4 targets fire
4 of 4: #78 `like-we-did`, #88 `used-it-times`, #106 `time-ago`, #110 `done-before` (also pinned in
`tests/episodic-cue.bats`). By eye, 10 of the 14 thirty-day fires are genuine references to earlier
work; the other 4 are a personal errand ("a few days ago"), a question about usage ("how much have we
used Jev"), and two machine-written continuation briefs that pass the `<`-prefix test. One tightening came from this run:
`last-session` first matched "the previous session" in recycle briefs, and fired 20 times in 30 days
(0.62%) before it was narrowed to "last session" / "a previous session".

## Replay, before state (2026-09-28, before the workflow-indexing item #18a)

Results are filtered to sessions created before the prompt and not the incident session itself,
because claude-search's own `--before` is silently ignored (`--before 2026-09-27` returned 09-27T20:10Z
and 09-28 sessions).

| Miss | Query the cue derives | Gold | Top 5, plain | Top 5, --deep-search |
|---|---|---|---|---|
| #78 | `bennu highland guest wifi code hours` | the Houndstooth Rock Rose sitting (09-13) | not found | not found |
| #88 | `git history particularly prompted using diff` | an exhaust-improvements run | not found | not found |
| #106 | `dyanmic workflow pierre jouet engufled self-recycles` | the pinterest Dynamic Workflow | not found | not found |
| #110 | `truememory github buildingjoshbetter extracting applying current` | true negative | nothing (correct) | nothing (correct) |

Before state: 0 of 3 golds reachable; #110 stays a true negative. #78's top hit is a sibling session
at the same café three minutes earlier, not the past sitting the operator meant. #88's prompt never
names the skill ("we used it"), so no noun query can reach it. #106's gold lives only in workflow
result JSON, which #18a is to index, and the prompt misspells the brand ("Pierre Jouet" for
Perrier-Jouët), so only "pinterest" or "dynamic workflow" could match it. The lead re-runs
`bash replay.sh` after #18a is live and adds the after state here.
