# Usage-lever decisions — re-researched 2026-10-24

Answer first: none of the three decisions clears 90%, and all three are sign-off class (each registers
or changes a hook that wakes or denies, or changes an operator-stated practice). Recommendations:

| # | Decision | Recommendation | Net (pp/week, fleet of ~400) | Conviction | Tier |
|---|---|---|---|---|---|
| 1 | Should idle sessions recycle earlier than the 35%/25% practice? (`43da49891e75`) | Recycle at **200k** (not 150k) after 15 idle minutes, with guards G1-G6, after a 7-day fixed shadow | ~+11.1 (150k: ~+9.7) | 65% | signoff |
| 2 | Should the Workflow hook deny `agent()` calls that set no `agentType`? | **Not yet.** Fix the agentsync b13 round template to use `workflow-lean` (no hook, ~+9-10 while it runs); keep the hook in shadow, add resume/script-sha fields; re-gate lean on 2.1.293; deny-once only if lean needs ≤1.3x turns | hook alone +1 to +3.5 | 25-55% (deny as proposed) | signoff |
| 3a | Should `idle-keepalive.sh` start waking idle sessions? | **Keep log-only;** build a busy-scoped version (wake only while the session's own job runs; skip when a watcher fires first; end a gap only on a user/assistant record), shadow 7 days | redesign +3.9 to +5.1; today's code +2.3 to +3.8 | 65% | signoff |
| 3b | Should the subagent long-Bash rule deny instead of count? | Deny **only the poll-loop class**, with a foreground `timeout 260` message (not run_in_background, which trips the /goal gate) and an inner-timeout exemption | +1.4 to +5.2 (≈+0.4 all penalties stacked) | 68% | signoff |

Implemented without sign-off (above 90%, behavior-neutral): fixes that make the log-only shadows
measure correctly — see the plan's "Decision re-research" section. Method: workflows
`wf_0491f88f-c15` (idle recycle, 7 agents) and `wf_831969c9-3ab` (lean + idle cache, 10 agents),
each finding re-derived by adversarial reviewers; returns verbatim in `measurements.json`, code in
`scripts/` (intermediates under `/tmp` are not persisted).

## Decision 1 — idle recycle (verbatim reconciler output)

**Recommend (C): recycle at 200k tokens after 15 idle minutes, not 150k.** Go live only after a fixed shadow week confirms it, with guards G1-G6 below. Estimated net is about **11.1 pp/week**. That compares with 9.7 for 150k/15, 0 for keeping current practice (today's rails catch little), and 5.4 if current practice were fully applied (estimated, `net.py` → net.out).

1. **Gross saving.** With the measured 78k re-prime, 150k/15 saves 16.36 pp/week over 566 recycles per 14 days. 200k saves 15.39 over 368 recycles, 35% fewer. 250k saves 13.64 over 243. (Measured: `python3 -I -B /tmp/idle-recycle-risk/decide/rp90.py /tmp/usage-audit/w4` → rp90.out, which reruns sim.py with its p90 re-prime setting.)
2. **Newly priced costs at 150k, per week** (reviewer-adjusted): the successor's orientation turn 2.8, a handoff turn of about 3 requests 1.1, jobs that moved to the background mid-run 0.6, rework after turn 1 0.1, and the G4 hold 1.4. Scaled per recycle (estimated, net.out), each threshold costs 6.6 / 4.3 / 3.0, which leaves a net of 9.7 / 11.1 / 10.7.
3. **The operator risk sits below 200k.** Points at 150-200k are 177 of 310, but they hold 15 of 19 replies that need the predecessor's context, 7 of 10 replies that risk a wrong action, and 39 of 65 operator returns that continue the prior conversation. (Measured: `python3 -I -B /tmp/idle-recycle-risk/decide/bands.py` → bands.out, using the hand labels from (b) and the (c) review.) Clarifying round-trips drop from about 9.5 a week to about 2 (estimated, scaled by 4 of 19).
4. **Downside.** I stacked every pessimistic cost: orientation turns like the all-successor average (5.86), 5-request handoff turns (3.87), jobs without a completion notice treated as running (1.4), and a 1-hour operator-turn hold. Under that, 150k breaks even (-0.2) and 200k still nets 4.7 (estimated, net.out). Rework alone never flips the decision (0.1 to 1.3). Misses cost at most 0.25 pp/week of quota; the real cost is the operator's time.

**Guards required before going live:**
- **G1 Busy test.** Classify by the tool that launched the job, not by notice text. Watchers and Monitors do not count as busy. In-flight subagents, Workflows, and foreground Bash calls that moved to the background do. At 150k, 25 of 310 recycles would have killed a land, test suite or deploy (review c, adv/sim_autobg.out).
- **G2 Activity.** A non-empty composer or operator bash-mode input resets the idle clock. Allow one wake per gap: keepalive has already fired twice for one gap (c, ika.snapshot).
- **G3 Brief contents.** The brief carries:
  - the predecessor's final message, verbatim;
  - its open operator questions and handed-over steps;
  - its transcript path;
  - the peer watchers and Monitors to re-arm.
  If a short reply ("Yes", "Cancel", "Open for us") could match more than one item, the successor asks before acting.
- **G4 Pending-question hold.** Hold the recycle while the end of the final message has a "?", an AskUserQuestion, the GENUINE regex, or "Still yours" / "your call".
- **G5 Lazy orientation.** The successor sends one request and reads nothing until its first wake. This could win back up to about 2 pp/week; I did not count it.
- **G6 Fixed shadow for 7 days.** Run it with the G1 busy test, logging terminal idles, a pending-question flag, and the next operator prompt. Stop the policy if the median successor first turn exceeds 10 requests or file-touch rework exceeds 10k tokens.

**Conviction: 65%** (reviewers adjusted to 60/70/65) that 200k/15 with these guards nets at least 8 pp/week and beats 150k/15.
- **Up:** first live recycles with first turns of at most 5 requests and 8k tokens, and handoff turns of at most 3 requests; a replay of the 10 wrong-action cases with at most 2 failures, which removes the need for the 1-hour hold; a blind second labeller.
- **Down:** first turns near about 10 requests and 26k tokens; replay failures that force the 1-hour hold (200k net falls to 9.4); subagent cost landing near its +4.0 point estimate (90% interval -4.6 to +13.4).
- **Caveats:** the 200k risk counts come from the points of the 150k run, and costs are scaled linearly per recycle. The shadow week should recount both at 200k.

Files are in /tmp/idle-recycle-risk/decide/: rp90.py, rp90.out, bands.py, bands.out, net.py, net.out. That folder is a new key I created; I wrote nothing else.

## Decisions 2-3 — workflow-lean enforcement and idle cache (verbatim reconciler output)

All three decisions are sign-off class, because each one registers or changes a hook that denies or wakes. Fleet capacity is about 400 pp/week (measured by the numbers reviewer, inline over ~/.claude/logs/account-utilization.jsonl: 16 of 17 windows hit 100%). None of the figures below prices the 5h meter. I ran nothing new and wrote no files. Every number comes from the worker and reviewer scripts under /tmp/lean-idle/<key>/.

1. workflow-lean: should the Workflow hook deny scripts whose agent() calls set no agentType?
- Recommendation: not yet. First, fix the agentsync b13 round template to use workflow-lean, which is an ordinary edit with no hook. Keep the hook in shadow and add resumeFromRunId, script sha and repeat-in-session to its log row. Then re-gate lean on 2.1.293 with 2-3 briefs of 15+ turns (about $35). Switch to deny-once only if all three hold: lean needs at most 1.3x the default's turns, resumes always pass, and a /* needs-default */ marker is honored. Never auto-rewrite (option C): 48 of 275 would-deny runs needed Skill, MCP or a real commit (measured: analyze.py false_deny).
- Net: the hook alone is worth about +1 to +3.5 pp/week. It turns negative once lean needs 1.33-1.48x turns on long slots (estimated: review-numbers/split2.py). The finding's +14 to +22 used older binaries, where lean saved 91-113k prefix tokens; on 2.1.293 it saves 39-43k (measured: prefix.py). The b13 fix is worth about +9 to +10 pp/week while that loop runs (estimated: split2.py). No b13 run started on 10-24 (measured: inline over review-numbers/runs.jsonl).
- Resume hazard: if the model obeys a deny on a resume, the finished slots re-run. The 18 resumed would-deny runs held 72-78 pp of work over 30 days (measured: review-mechanism/resume_cost.py).
- Conviction: 25% that the deny pays as proposed (numbers reviewer; the mechanism reviewer said 55%). Up: the re-gate shows 1.3x turns or fewer, and a deny-once trial gets 80%+ edited resubmits. Down: 1.3x+ turns, or the b13 loop has stopped.
- Sign-off: yes for the hook. The b13 template edit is not sign-off unless the template lives under ~/.claude.

2. idle-keepalive: should idle-keepalive.sh wake idle sessions at minute 55 instead of only logging?
- Recommendation: keep it log-only and build a busy-scoped version with three rules. Wake only while the session's own background job runs. Skip the wake when a model watcher will fire before the cache expires. End a gap only on a new user or assistant record. Today the away_summary record that lands about 190 s into a gap kills 52% of timers (measured: rv/rcounts.py). Run the new version in shadow for 7 days, then measure about 20 live wakes to get their real cost.
- Net: the redesign is worth +3.9 to +5.1 pp/week fleet-wide, but only +0.1 to +0.4 on next4 (estimated on measured gaps: rv/rrep2.py). Switching the current code on today would give +2.3 to +3.8 (estimated: rv/rrep3.py). Its tail risk from dead panes is refuted: panes die 10-37 s after their last write (measured: review-mechanism/r6.py). So waiting gives up about 3 pp/week.
- Why wait anyway: today only 47% of rebuild gaps get a timer, which fails the plan's bar (rv/rcounts.py). At the mean wake cost the current code nets +1.56 / -0.03 at low / high read weights (rv/rrep3.py). The chime on every wake and the teammate-to-lead wakes are not priced.
- Conviction: 65% (numbers reviewer; the mechanism reviewer said 80%). Up: the probe shows wake turns of 3+ requests. Down to about 45%: a 1-hour write premium is confirmed (at a weight of about 0.33 the current code nets +3.2 to +4.0, rv/rrep_w.out), or the operator counts the roughly 3 pp/week given up while waiting.
- Sign-off: yes, because it is a hook that wakes sessions.

3. W3 subagent long-Bash: should the subagent rule from d9ffc3964 switch from counting to denying?
- Recommendation: deny only the poll-loop class. Keep long-runner (-0.2 to -3.0 pp/week) and waiter (-0.6 to -1.8) count-only (estimated: variants.py). Before switching, fix the deny message. It should tell the agent to re-issue the loop in the foreground as `timeout 260 bash -c '<loop>'` with a tool timeout of 270000 or less. It should not say run_in_background: that trips the /goal gate in validate-bash.sh, and 86 of 798 poll loops ran under a live goal (measured: goal_overlap.py). Also exempt commands that carry an inner timeout under 300 s: 765 calls, only 6 of them followed by a rebuild (measured: review-numbers/price.py).
- Net: the poll-loop deny is worth +1.4 to +5.2 pp/week fleet-wide (estimated: variants.py), and about +0.4 with every reviewer penalty stacked (estimated: price.py). Wrong denies cost 0.03-0.14 pp per account against the 0.2 bar (estimated: peracct.py). Quaternary reaches 0.24 if calls with copies under several accounts are charged to each of them (peracct_ub.py).
- Conviction: 68% (numbers reviewer; the mechanism reviewer said 70%). Up: a one-day trial on one account, including a session with a live /goal, shows agents re-issuing in foreground slices. Down: quaternary's wrong-deny cost reaches 0.2, the 5-minute write weight is 0.15 or less, or steady poll-loop rebuilds fall under 50/week (91.6 measured, variants.py).
- Sign-off: yes.
