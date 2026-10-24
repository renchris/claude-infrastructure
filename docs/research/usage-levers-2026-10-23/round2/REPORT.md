# Round 2 — conviction research on the open decisions (2026-10-24)

Workflow `wf_32a12de5-152`: 4 researchers (2 on the cache-read question by different methods), each re-derived by an adversarial reviewer, then 1 reconciler; all on `workflow-lean`, ~1.24M subagent tokens. `measurements.json` holds every return verbatim; `scripts/` the analysis code (prefixed by slot). Intermediate outputs lived in `/tmp/usage-audit/r2/` and are not persisted.

## Reconciled decisions (verbatim)

## Reconciled decisions (2026-10-24)

**1. Do cache reads count against the Max plan quota?** (I merged the cache-read-weight and cache-read-quota slots into this one verdict.)
- **Answer: yes, at a discount.**
  - Weekly weight on Opus 5.5 (Sep 28 to Oct 24) is 0.0048 pp/Mtok [0.0036, 0.0056] (measured: fit4.py). The reviewer reproduced it with no account attribution at 0.0060 [0.0038, 0.0074] (measured: rfit.py).
  - That is 28-35% of the weekly meter. The 5h meter gives 0.018-0.020.
  - The Claude Code docs say long sessions re-read history "at the cached token rate" (costs.md:389-391).
- **Where the slots disagreed:**
  - The August "free/≈0" ruling was an upper bound (0.049). Its own table allows 64-76% of list price, which both reviewers checked. So it does not contradict the new fit.
  - Yesterday's lever 3-4 figures already used fitted weights of 0.0045-0.0067 (sk_bc_meter2.py). The new fit falls inside that range, so they hold if reads count. Do not halve them; that would count the discount twice.
  - The Opus 5 era cannot tell 0 from 0.005 (measured: o5_check.py). So "reads became charged when Opus 5.5 arrived" is not established.
- **Measured options:**
  - Reads charged at about 1/40 to 1/51 of a cache-write token (both fits; list price is about 1/15, estimated).
  - Reads free. The held-out week rejects this: RMSE 0.751 with reads at 0, against 0.559 with reads (fit4.py). Shifting tokens in time destroys the fit (R² -0.01 to -0.69, rfit.py).
- **Conviction: 90%** that context size costs quota. This is above the reviewers' 85 and 80 because the meter fit and the docs fail in different ways. 85% that the cost is the cache read itself, since a hidden classifier or long-context cost would fit the same way.
- **Disposition: OPERATOR.** 90% does not clear the >90% bar.
  - Receipt: one probe on an idle Opus 5.5 account with no tool calls, so no `serverClassifierRequest`, and about 500M cache reads. If reads are charged, expect +10pp on the 5h meter and +2.4pp weekly. If they are free, about +1pp.
  - IMPLEMENT now (95%, estimated from the August table's own numbers): reword "free/≈0" to "discounted, about 0.005 pp/Mtok weekly on Opus 5.5". Lines: USAGE_TELEMETRY_100P.md:152,179; token-efficiency REPORT.md:20,318; the bin/cc-quota-price docstring; the hooks/cache-expiry-warning.sh header. Keep the 0.049 constant.

**2. Should read-only Workflow slots be forced onto workflow-lean?**
- **Answer:** yes on the direction. The deny-once hook is not yet shown to be the right mechanism.
- **Evidence:**
  - The re-gate measured lean 84.4% cheaper per slot with equal correctness: 28/28 and 40/40 (GATE.md:139-170).
  - No setting changes the default agent; it is hard-coded in the binary.
  - Corrected for lean's +19.5% turns, the saving is about 241M tokens a week, roughly 3-4% of weekly usage, not 5.2% (estimated: costan.py).
- **Measured options:**
  - Deny-once hook: 72% (researcher), 65% (reviewer).
  - A hook that rewrites the script to add agentType (`updatedInput`): never weighed. It would silently take Skill/MCP from the 5.6% of slots that need the default (needs2.py).
  - Warn-only: 20%. Do nothing: 8%.
- **Broken claim:** the 2026-10-04 "deny" was a 5 s hook timeout, and the workflow ran anyway. A Workflow hook that times out lets the call through.
- **Conviction: 65%.** Decision 1 removes the reviewer's worst case (reads free, 44-62M a week), but the other doubts stand.
- **Disposition: OPERATOR.** Receipts:
  - A 3-day log-only shadow hook that records the deny verdict, what a rewrite would do, and hook latency against the 5 s timeout.
  - The F2 re-gate on 2.1.293, about $35 (GATE.md).

**3. Should idle cache rebuilds be fixed with a main-session keepalive and a subagent 270 s rule?**
- **Answer:** the diagnosis is right; both fixes as written are not.
- **Reproduced:**
  - 191 main-session rebuilds after 1-2h gaps, 49.6M tokens. 61-65% were idle with their own background job running.
  - Cause: the mailbox watcher (`--timeout 14340`) exits silently on timeout, and the 3300 s wake floor stands down while that hook is registered (session-continue.sh:688).
  - Subagent waits in slices of 270 s or less are safe: 3 rebuilds in 302 gaps of 270-300 s (reviewer's own scan).
- **Broken claims:**
  - (a) The keepalive as written would do nothing: mailbox-wake-arm.sh:203 exits when a watcher is already armed, and the watcher persists across turns (one ran 3h17m across 4 Stops).
  - (b) The timeout>270 s deny would hit 5,941 calls that finished in 270 s or less, to target 250 rebuilds (fgbtab.py).
- **Measured options for (b):** net +1.19% to +2.24% of weekly usage at meter-fit weights, -0.97% to +0.57% at API weights (deny cost assumed). Decision 1 makes the meter branch the relevant one.
- **Conviction: 60%.** **Disposition: OPERATOR.** Receipts:
  - An idle-scoped keepalive prototype that wakes about once per gap, timed from the gap start.
  - A narrowed subagent rule, with one week of denies counted against rebuilds avoided. Target: under 0.2% of weekly usage lost to wrongly denied calls.

**Which waves are unblocked**
- **A:** the binary pin (bin/cc-notify:682-683 to call cc-claude-bin) is not gated by any open item, so it can start. For lean enforcement, only the log-only shadow hook can start; deny-once waits on its receipt.
- **B:** blocked until both fixes are redesigned. The Phase 0 counts can run now.
- **C:** blocked until the decision 1 probe. The doc reword can start now.

**Your questions**
- **Agent types.** Built into 2.1.293 (measured: agentctx.py): workflow-subagent (the Workflow default, all tools plus CLAUDE.md, about 47.6k-token first request), general-purpose, Explore, Plan, statusline-setup and comment-thread-analyst. Defined in the repo's agents/: workflow-lean (about 9.2k-token first request, no CLAUDE.md, rules, memory, Skill or MCP), deep-research, deep-research-sonnet, frontier-derivation and research-decomposition-critic. Explore and Plan inside Workflows have not been measured.
- **What it changes for us.** Lean costs about 84% less per read-only slot at measured equal quality, worth about 3-4% of weekly usage (estimated).
- **Ultracode research on each point?** No. No point gets past 90% from more desk research; what is missing in each is one cheap test (the probe, the 3-day shadow run, a one-week count). Conviction in this answer: 85%. It would drop if a probe or shadow run came back ambiguous for reasons a source sweep could settle.

Files: /tmp/usage-audit/r2/reconcile/agenttypes.py, agentctx.py and their .out files. Nothing else was written.
