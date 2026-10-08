# Row 15 after Haiku 5.5: what to do next (decision research, 2026-10-08)

Produced by workflow `wf_7fd65e4a-17f` (four read-only research slots, a synthesis, a refuting critic and a steelman critic, a final revision), run by the research-program lead. Written to disk by the lead because the workflow slot could not write files. Supersedes the load-bounded re-read recommended in decision packet `416e61ae1569`.

**Recommendation (80% conviction): spend no sealed data yet. Run two jobs on tuning data only, both inside tonight's low-load window: (1) trace and fix the warm classifier daemon's stall bursts, which caused the fallback failure; (2) tune Claude Haiku 5.5 as the careful call, under a selection rule committed before the first call. Then ask the operator once for one sealed read of whichever configuration that rule picks. This replaces the 'load-bounded-reread' option filed in decision 416e61ae1569.**

Gate row 15 is the re-ask classifier ('router') check that every research certificate needs. It failed its one sealed read on 2026-10-07 (the E1i wave) only on the fallback ceiling: 105 of 695 items (0.15) against a limit of 0.10. Every recall miss was one of those fallbacks.

Why this course, in three points:

1. The failure was stall bursts that hit BOTH classifier calls together. Neither a load bound nor a faster careful model removes them for certain.
   - A fallback happens only when neither call has a label by 9 s (router.py:589-603), and the fast Sonnet call normally answers in about 2 s.
   - The 106 inferred timeouts sit in 31 gaps, and 84 of them fall in 12 runs of 3 or more items in a row.
   - The longest run is 19 items over 171 s, at load 116 to 253. The next is 15 items over 135 s, and one run of 5 came at load 56.
2. Haiku 5.5 is already the live careful call, and it is untuned.
   - The flip landed at 22:32 CDT. Since about 22:48 the daemon has served claude-haiku-5-5 on the unmanaged claude 2.1.291 with no --effort.
   - It is the right careful-call candidate on speed, and speed matters for recall: the careful call missed the 8.5 s hold on 20-50% of rows.
   - Its accuracy on our labels is unmeasured.
3. Both jobs spend no sealed data and fit one night. The first one also decides whether row 15 needs a load bound at all, which removes one of the operator rulings if the fix holds at real load.

Glossary:
- 'Fast call' is claude-sonnet-5-5 with thinking off ('sonnet-off').
- 'Careful call' is the second, thinking-on call.
- 'Union' means the router relays if either call says relay.
- 'v3' and 'v4' are the sealed held-out sets.
- 'Regex-missed' is the stratum of subtle re-asks that the regex misses.
- '0059' is the migration that restarts the warm daemon.

On the operator's hint ('Haiku 5.5 likely takes over for your indecision between Haiku and Sonnet'):
- YES for the careful call on speed. The permission-decider consult took 5.0-6.1 s on Haiku 5.5 against 8.2-15.3 s on Haiku 4.5 (haiku55-flip README.md:114-118). Sonnet thinking-on is already out on quality (regex-missed 37/42; result-e1i.txt:7).
- NO for the fast call. Thinking cannot be turned off on claude 2.1.293 (notes/bin293-probes.md:120-127, :178).
- It does NOT fix the fallback failure, which was common-mode stall bursts.

EVIDENCE (read live at 22:53 CDT 2026-10-07)

The live state:
- git ls-remote origin main returns bc7894fe2 (22:32:50 CDT), which contains the flip d0ffee48a.
- ~/.claude/model-config.yaml:140 reads 'haiku_latest: claude-haiku-5-5 # FLIPPED 2026-10-07'.
- Daemon pid 48698. Its careful workers, pids 52235 and 52342 (started 22:48:27), run '/opt/homebrew/bin/claude -p --model claude-haiku-5-5' with no --effort.
- router.classifier_config() returns 983448663980, and router.haiku_model() returns claude-haiku-5-5.
- The lead offered the choice and the flip session took '(a)': bash-execution.log:165537, :165570, :165636. The 0059 restart is at :165807.
- Load read 33.45 / 57.38 / 135.30.

How a fallback happens:
- router.py:589-603: while no call has a label, the router waits until the full deadline and returns None.
- heldout.py:554-567 kills the router at 9 s by its own clock.

Timing trace (reading-v4-2026-10-07.trace.jsonl; timing fields only, 594 rows):
- Inter-item overhead: median 0.06 s, p90 0.11 s, maximum 0.27 s. The 148 rows answered at the hold delivered at 8.50-8.51 s, so load does not eat the 0.5 s margin (router.py:203-207).
- Inferred timeouts: 106 in 31 gaps.
- Careful call cut at the hold on rows where the fast call said non-relay (the router's relay set is completeness and pushback): 14 of 71 (20%) at load 40 or under, 50 of 190 (26%) at load 40-60, and 84 of 167 (50%) above 60.
- The fast call stalled on 3 answered rows.
- The careful call returned 4 non-labels: 'I'll read that fi…' twice, 'I can't access fi…' once and 'NONE' once.
- The 91 rows at load 40 or under fall in 7 clusters, two of which hold 68.
- No answered row took the cold path.

Daemon defects:
- classifier-warm.py:345-349: the canary calls pool.take() from the serving pool, and POOL = 2 (:87).
- :360-371: a 30 s slow canary counts as a failure, and 3 in a row make the daemon quit.
- :434-438: every slow prompt triggers an immediate canary.
- The plist sets no ProcessType.
- The err log repeats 'careful readiness round-trip 3 failed … exiting', but it has no timestamps, so the exits cannot be placed in the read window.

Method and plan:
- REPORT.md:1104: the cap row's exit is to fix the router 'as tooling'.
- RESEARCH_PROGRAM_BUILD.md:1276: no re-read on FAIL, and no third read of v3.
- :1281-1284: a new haiku_latest is 'an unmeasured classifier … needs its own re-read'.
- :1321: v4 sealed regex-matched=all.
- :1376: all 105 fallbacks ran 9.00-9.03 s.
- Gate row 15 re-runs heldout.evaluate() on every gate (lib/gate_rows_b.py:352-361).

Tuning:
- result-e1i.txt:3: sonnet-off recall 154/163, regex-missed 34/42, 32 wrong non-relay labels.
- result-e1i.txt:6: union(sonnet-off, haiku-on) scored 162/163, 41/42 and relay decision 229/240.
- result-e1i.txt:7: union with Sonnet thinking-on scored regex-missed 37/42.

Haiku 5.5 (sibling research, under haiku55-flip/docs/research/haiku55-upgrade-2026-10-07/):
- README.md:114-118: the decider consult took 5.0-6.1 s against 8.2-15.3 s for Haiku 4.5 (n=4 each).
- notes/bin293-probes.md:178: the default effort is medium on 2.1.293.
- notes/gap-02.md:149-152: 2.1.291 does not register the model, and a static read of 2.1.284 suggests it falls back to effort 'high'.
- UPGRADE.md:17: registration counts; 2.1.291 has 0.

CRITIQUES AND RESOLUTION

Critique 1 (verdict: revise):
- 1. The flip has landed. ACCEPTED, verified.
- 2. The daemon already runs Haiku 5.5. ACCEPTED, verified. 'Pin keeps 05e87273a59c, no restart' was false and is dropped.
- 3. The lead coordinated choice '(a)'. ACCEPTED, verified. Pinning back is no longer drivable.
- 4. The pin's urgency was overstated. ACCEPTED: there is no blocking program and is-active exits 1. The pin now follows the tuning result.
- 5. The as-built arm is missing. ACCEPTED as a diagnostic arm, REBUTTED as primary. As-built runs an unregistered model on an unmanaged npm binary, so the next update changes it silently. The certified configuration must be pinned.
- 6. Warm latency can be measured with no restart. ACCEPTED.
- 7. The odds are false precision. ACCEPTED: A and B are now presented as tied (0.75 and 0.76), with one pre-committed primary arm.
- 8. A load bound still leaves the careful cut. ACCEPTED, verified exactly (14/71, 50/190, 84/167). Tuning's 41/42 already applied the same 8.5 s cut, so it transfers at low load. This is the speed case for Haiku 5.5.
- 9. The 4 non-label answers. ACCEPTED: logging INVALID reasons is mandatory.
- 10. The packet correction misses the live state, and the retirement-date claim is weak. ACCEPTED: the retirement date is now stated as a lower bound, not an error.
- 11. Conviction gating stalls the tuning work. ACCEPTED: the harness, rule, tuning run and latency check are at 91-92.
- 12. The citation fix. ACCEPTED: it now cites the row by name.

Critique 2 (verdict: revise):
- 1. The causal premise is wrong; fallbacks are bursts in both calls. ACCEPTED, verified. PARTLY REBUTTED: a faster careful call still matters for recall, because of the careful cut, though not for fallbacks.
- 2. Load does not eat the margin. ACCEPTED, verified (overhead maximum 0.27 s); that claim is withdrawn.
- 3. The receipt's method error. ACCEPTED, verified: t is the classify start.
- 4. The flip is stale. ACCEPTED.
- 5. Four tooling defects. ACCEPTED as real in code. REBUTTED only as proven causes: there are no timestamps and fallbacks are untraced, so instrumentation comes first and the fix stays at 82.
- 6. B's tuning cannot see the failure. ACCEPTED: this is why G adds the warm, real-load validation.
- 7. The odds are overstated. ACCEPTED: all odds are lowered.
- Better option G: ACCEPTED as the backbone, with three changes. (i) The cold hedge and ProcessType are measured before they are kept, because both add CPU pressure at load 60-250. (ii) 'No load bound' applies only if the real-load bar passes. (iii) Haiku 5.5 tuning runs alongside, not after.

Why the recommendation sits at 80 and not higher:
- The regex-missed floor of 24 of 25 caps every read at about 0.88-0.93.
- The daemon fix may not find the burst cause if it is upstream (the err log shows 'Not logged in'), which would leave a load bound.
- D (stop until fresh data in 2027) is a defensible instrument-integrity choice for the operator.

UNKNOWNS
- The cause of the bursts: daemon self-exit, pool starvation, cold starts under load, or upstream API or account stalls.
- What 2.1.291 sends for claude-haiku-5-5 with no --effort: effort high or medium, and the thinking shape.
- Haiku 5.5 on our brief: latency, relay decision, regex-missed rescues, refusals and stability.
- Whether the stream-json warm path on 2.1.291 emits the unrecognized_model warning on stdout.
- Whether the operator frames this as 'fixed as tooling' or as a third attempt.
- How many regex-matched and regex-missed prompts have arrived since the v4 seal (2026-10-06 23:17).
- What 'sessions 50 and 73' refer to. 50 is likely activation 50 (commit 04c1159d2, launcher 2.1.284 to 2.1.293); 73 was not traced.
