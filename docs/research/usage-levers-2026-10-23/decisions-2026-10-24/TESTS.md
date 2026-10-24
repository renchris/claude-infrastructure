# Conviction tests on the four usage-lever decisions (2026-10-24)

Workflow `wf_7582690a-1e6` (15 agents). Answer first: every test held or raised conviction; no
recommendation changed; none crosses 90%, all stay sign-off.

| Decision | Test | Conviction |
|---|---|---|
| Idle recycle at 200k after 15 idle min (`43da49891e75`) | blind relabel kappa 1.00 / 0.88; 0 of 10 wrong-action replays failed, so the 1-hour hold can go | 65% -> 70% |
| Block Workflow steps with no agent type (`a4c54d1744d1`) | lean re-gate on 2.1.293: 3/3 correct at 0.79x requests (upper bound 1.19x < 1.3x bar), ~0.43x cost | 40% -> 65% |
| Idle keepalive wakes (`c0f9d5368147`) | 943 real no-news wakes: median 3 requests, 0.0060 pp; 1-hour write premium 2.8% likely | 65% -> 70% |
| Block subagent poll loops (`3df527edd333`) | 20/20 simulated compliance; real deny history 75% re-issue-as-told, 0.6% retries; 5 of 20 samples were not waits | 68% -> 72% |

The agentsync B13 round scripts (written fresh each round by session 666022fd on next4) still run
their read-only slots on the default agent; the owner was notified with the evidence on 2026-10-24.
Test code: `tests-scripts/`; every return verbatim: `tests-measurements.json`.

## Reconciler output (verbatim)

Answer: no more broad research is needed. All four tests held or raised conviction, and none changed a recommendation. What is left is a few cheap offline checks, some build work, and then the 7-day shadow or a one-day trial.
(The scripts named below are in /tmp/conv-tests/<key>/. "est." marks an estimate; every other number is measured.)
Idle recycle 200k/15 (43da49891e75): a second labeller agreed with the first (kappa 1.00 on context-dependent, 0.88 on wrong-action; compare.py). Replaying the 10 wrong-action cases gave 0 wrong actions (done by hand, replay/actions.txt; 95% upper bound 27.8%, net_nohold.py).
  Conviction 65% -> 70%. Recommend 200k/15 with guards G1-G6 after the shadow week, and drop the 1-hour hold (central net 11.1 vs 9.4 pp/week, est., net_nohold.py).
Workflow block (a4c54d1744d1): lean passed all 3 briefs using 0.79x the default's requests (64/81; worst brief 1.045x; cost.py). The one-sided 95% bound is 1.19x (est., adjust.py), so the 1.3x turn bar is met.
  Block-once 25% (numbers reviewer) / 55% (mechanism reviewer) -> 65%. The b13 template fix is 85% likely to net more than +9 pp/week (est., split3.py). The b13 loop is still running with default agents (round 27 scripts have 0 agentType mentions; inline regex).
  Recommend: first fix how the b13 session writes its round scripts. That needs a sign-off check, because they live under ~/.claude-quaternary. Then build resume pass-through, the needs-default marker and deny-once state, and run a one-day trial.
Keepalive wake (c0f9d5368147): no-news wakes at 150k+ cost a median of 3 requests and 0.0060 pp (n=943, wakestats.out), which is what the finding already assumed. The chance of a 1-hour write premium at the list ratio is 2.8% (fit_tier.out).
  Conviction 65% -> 70%. Recommend: keep idle-keepalive.sh log-only and build the busy-scoped version, preferably the variant that also skips gaps with a watcher armed (+4.49 vs +3.12 pp/week for today's code, est., recompute.out). Then shadow it for 7 days.
Poll-loop block (3df527edd333): simulated compliance was 20/20 (grade.py; biased upward). In real history, a deny that names the form to re-issue got that form 75% of the time, with 0.6% retries (1,014 cases, split_rm.py). 5 of the 20 sampled denies were not waits at all (hand reading).
  Conviction 68% -> 72%. Recommend three fixes to the deny: a branch for non-wait calls, an "append echo rc=$?, repeat the same slice on 124" rule, and select(undef / time.sleep( added to the pattern.
  Then run two offline checks: settle which account owns each of the 352 cross-copied calls (this decides whether quaternary breaks the 0.2 bar), and re-price at a 5-minute write weight of about 0.20. Either check could move conviction 5-10 points (est.). Then run the one-day trial.
Only the shadow week or a live trial can settle these:
- Idle recycle: how big the successor's first turn is (5 requests / 8k tokens or less moves conviction up, about 10 / 26k moves it down), and the subagent cost. A fresh-session replay of 5 cases is optional and can be done offline.
- Keepalive: whether real wakes are answered in 1 request or 3, and how often they make the model act. Charging acting turns to the wake gives -0.25 for today's code, -0.74 for the redesign and +1.22 for the watcher-skip variant (est., recompute.out). This needs about 20 real wakes and your sign-off.
- Workflow block: the edited-resubmit rate under deny-once (the bar is 80%). Poll-loop: the second-deny rate, waits written without "sleep", and the wrong-deny cost per account.
One call is yours, not research's: whether the +2.6 to +3.9 pp/week that today's keepalive code would net (est., recompute.out) is worth giving up while the redesign is built and shadowed.
