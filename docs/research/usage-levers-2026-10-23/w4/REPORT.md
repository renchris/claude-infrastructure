# W4 — would an earlier idle recycle save quota? (2026-10-24)

Scope (frozen): W4 of `docs/plans/USAGE_LEVERS.md` — a 14-day simulation of earlier idle recycles over
deduplicated main-session transcripts on all 4 accounts, a log-only advisory in the recycle rail, and
an operator decision filed on the thresholds.

**Verdict.** Recycling a session once it has been **idle 15 minutes at 150k tokens or more** would have
saved about **19.7 pp of weekly quota per week across the four accounts** (4.0–6.4 pp per account),
for **0.31 extra recycles per session** (412 of 1,679 sessions recycled at least once, at most 5 in
one session). The stated 35%/25% practice, if every session obeyed it, would save 9.1 pp/week. Today's
rails catch little of either: the transcripts hold 1,198 turn starts after ≥15 idle minutes at
≥350k context. The result holds under every read weight tried (17.4–21.8 pp/week).

## Method (`scan.py`, `sim.py`; data window 2026-10-10 07:43 → 2026-10-24 07:43 UTC)

- **Population.** Every main-session transcript (not under `subagents/`) touched in the window on
  next, next2, next3, next4: 1,720 files, 3.4 GB, 135,395 request rows → 135,312 unique request ids
  (83 duplicated inside an account, **0 across accounts**; the subagent copies the brief warned of sit
  under `subagents/` and are outside a main-session simulation by construction). 1,679 sessions,
  merged by `sessionId`, each request charged to its own account.
- **Recycle point.** A turn-start request (a prompt or a notice, never a `tool_result`) whose gap
  from the previous request is ≥ N minutes, with the session's (simulated) context at that idle point
  ≥ K. A long tool call is never a recycle point, so a working session is never drained.
- **Busy is not idle.** If one of the session's own background jobs (background Bash, Agent,
  Workflow; 5,008 intervals rebuilt from launch → completion notice) was running at idle minute N,
  there is no recycle: it would kill the job, and `handoff-fire` holds on it. `cc-await-ping`
  watchers and Monitors (5,507) are wake mechanisms and do not block. A job with no notice is taken
  to run to the end of the session. Ignoring this rule doubles the answer (41.1 pp/week), which is
  the main error a naive version of this simulation makes.
- **What a recycle costs.** (a) The predecessor's handoff request: a read of its context while the
  cache is warm (N ≤ 55 min), a full rewrite after. (b) The successor's re-prime, the **measured
  median first request of the 1,655 sessions that started in the window**: 43,779 written + 14,781
  read + 240 output (p90 written 64,888). (c) A second re-prime write if the successor idles past the
  1-hour cache before the next prompt. (d) **A pane that never resumes**: a session whose last request
  sits at ≥ K, idle ≥ N before the window end, with no self-close/recycle/exit in its tail, pays one
  recycle for nothing. Successor first turns grow 27.5k tokens against 30.2k for fresh sessions, so no
  re-orientation surcharge was measured.
- **What it saves.** After a recycle every later request in that session runs at context
  c − offset (offset = what the recycle dropped). Its new content is still written; the rest is a
  read. A compaction in the original resets the offset to 0.
- **Weights** (weekly meter, pp per Mtok): write 0.245, output 0.404, uncached input 389 (a
  per-request proxy) from round 2's `fit4`; reads from round 3's probe: **mid 0.0067**, low 0.0057,
  high 0.0076, and **tiered** (0.0048 at ≤200k, 0.0067 above: the long-context-premium reading of
  round 3's excess). Main sessions cost 248.6 pp/week under mid weights (next 79.7, next2 63.3,
  next3 62.0, next4 43.6).

## Results (pp of weekly quota saved per week; full grid in `sim.out`, `sim.json`)

Mid weights, all four accounts summed; recycles and pane-never-resumed recycles are 14-day counts.

| K \ N | 5 min | 15 min | 30 min | 45 min | 55 min | 60 min | 120 min |
|---|---|---|---|---|---|---|---|
| 100k | 22.3 | 20.7 | 17.7 | 16.9 | 16.3 | −0.1 | −2.3 |
| **150k** | 21.3 | **19.7** | 16.8 | 16.1 | 15.5 | 1.3 | −0.9 |
| 200k | 19.2 | 17.9 | 15.1 | 14.5 | 14.1 | 2.4 | 0.7 |
| 250k | 16.6 | 15.5 | 13.0 | 12.6 | 12.2 | 3.1 | 1.7 |
| 350k | 9.3 | 8.7 | 7.1 | 6.6 | 6.6 | 1.5 | 0.5 |

- **The 60-minute cliff is real.** Idle sessions are woken every ~55 minutes, so a gap of an hour is
  rare (564 at ≥150k against 3,531 at 15 min), and past 55 minutes the predecessor's handoff turn has
  to rewrite its whole context.
- **Where the saving comes from** (150k / 15 min): later requests at lower context +21.1 pp/week;
  the recycle turn itself +0.1 (the re-prime about cancels the rebuilds it avoids, 78 of them); panes
  that never resume −1.6.

**Candidate: K = 150k, N = 15 min.** Two rules the token price cannot see chose it. (1) N ≥ 15: the
rails already hold a recycle for 15 minutes after an interactive turn (`boundary-handoff.sh`
`CONV_S=900`); a 5-minute pause is usually the operator reading. (2) Each recycle risks work the
successor must redo, which no transcript prices, so among candidates within 5% of the best saving it
takes the fewest recycles: 150k gives 95% of 100k's saving with 34% fewer recycles (528 vs 806).

| 150k / 15 min | next | next2 | next3 | next4 | total |
|---|---|---|---|---|---|
| mid | 3.96 | 6.36 | 4.36 | 4.99 | **19.67** |
| low | 3.44 | 5.64 | 3.84 | 4.46 | 17.38 |
| high | 4.43 | 7.01 | 4.83 | 5.48 | 21.75 |
| tiered | 4.34 | 6.85 | 4.74 | 5.43 | 21.36 |
| re-prime at p90 (mid) | 3.17 | 5.33 | 3.58 | 4.27 | 16.35 |
| no pane-never-resumed cost (mid) | 4.51 | 6.82 | 4.70 | 5.21 | 21.24 |

Recycles: 310 mid-session + 218 never-resumed in 14 days; 0.314 per session; median 1, max 5 per
recycled session.

**Current practice fully applied** (350k after 15 min, or 250k after 60 min): 9.10 pp/week mid
(7.79–10.27 across weights; next 1.60, next2 3.20, next3 1.98, next4 2.32), 0.117 recycles per session.
"Keep" means 0 pp change from the transcripts, which already reflect the rails as they act today.

## What this does not price, and what would change it

- **Work the successor redoes after its first turn.** Successor and fresh sessions grow alike in
  their first turn, but nothing here measures rework later on. It is the main reason not to go below 150k.
- **The actuator.** An idle session runs no hook, so acting at idle minute 15 needs a wake: the
  idle-scoped keepalive W3 is building, or the existing 55-minute wake with N raised to 55, which
  still saves 15.5 pp/week at 150k (simulated).
- **A long-context premium** would make the case stronger, not weaker (tiered row).
- **Upper-bound effects.** A job still running when the operator typed is invisible here (its notice
  came later), and so is a pane the operator closed by hand; both overstate the saving a little.

## The log-only advisory (shipped in this wave)

`hooks/boundary-handoff.sh`, block "IDLE-RECYCLE SHADOW": at every Stop where the session's current
context is ≥150k, it reads the last 2 MB of the transcript and appends one line to
`~/.claude/logs/idle-recycle-shadow.jsonl` for the turn just finished: `gap_s`, `ctx_at_idle`,
`busy_notice`, `would_advise` (idle ≥15 min, ≥150k, not ended by a background job's notice). It
prints nothing and writes no IDL field, so every advisory and latch is byte-identical with it on or
off (`tests/boundary-handoff-idle-shadow.bats` pins that). It costs 2 processes and about 60 ms on a
42 MB transcript. Read it with
`jq -s 'map(select(.v=="ok")) | group_by(.would_advise) | map({would:.[0].would_advise, n:length})' ~/.claude/logs/idle-recycle-shadow.jsonl`;
its count of `would_advise:true` per day should come out near this simulation's 528/14 ≈ 38.

## Files

`scan.py` (transcripts → rows, job intervals; `python3 -I scan.py <acct> <projects> <start> <end> <out>`),
`sim.py` (`python3 -I sim.py <rows dir> --json sim.json`), `sim.out`, `sim.json`. The row files
(/tmp/usage-audit/w4/) are not persisted; re-running `scan.py` regenerates them.
