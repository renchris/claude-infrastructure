# A5: the counterfactual. What Jev could have done

Read-only; `msg stats` (local SQLite) was the only tool run against a private store.

## Findings

1. **What Jev is.** Jev is a typed judge, not a generator. It takes one `state` plus named questions and returns `boolean` (one probability), `choice` (one key from a caller map, with its probabilities) or `score` (a level with a full distribution). No strings, lists or tool calls. The state cap is 32k tokens on the Gateway route, which is **16,000 bytes** in practice (Add.5 C3). The measured rate is **~14.8 calls/min**, about 21k/day (Add.5 C2: 146 calls in 593 s). Its one proven asset is a high-precision tail: at p≥0.98 it auto-decides 7% at 97.8% on a 2,000-email phishing bench (§2). In short, a bulk classifier for short text whose only independent benchmark was email.

2. **Every search was bounded to the infra repo.** The operator's first ask was open: "what is the most high-signal and value tasks we can apply it to" (S1, 09-18T23:10). S2 narrowed this to "opportunities in our repositories" (09-19T04:40). The S4 brief then asked "what are Jev's primitives actually worth pointing at in **THIS fleet**?" (09-21T05:40). All 10 axes of the 100p wave (a1–a10) are about claude-infrastructure. VERDICT.md's loser table has no product, customer or personal family.

3. **The product repo was checked once and dropped.** Receipt: S2 workflow `wf_64f6e64f-193`, agent `a414155f5dd9fa5e5`, brief part (B). It found "AI SDK: ABSENT" in reso-management-app and rejected these surfaces:
   - `parseGuestEntry.ts`: "output is prose … runs per keystroke".
   - Bottle image review: "the state is an IMAGE".
   - Deck ruling: "geometric rather than semantic … the operator's alone".
   - Bottle-menu match: "the real blocker … is a missing contact … not a classifier".
   - `audit-runbook-links.sh` relevance: called "Jev-shaped (boolean, batch, advisory)" but "NONE-MEASURED". It was not pursued.

   All 32 candidates the workflow returned are claude-infrastructure files (measured). The rejections are sound.

4. **The mailbox and the `msg` corpus were refused on day one and never revisited.** At-cost §4 row: "Anything with private data — transcripts, mailbox, the 213,995-message `msg` corpus — **Refused regardless of price.** New sub-processor, US-only unbounded retention, enterprise-gated ZDR." §C: "This does **not** reopen the mailbox." a8:150–151 says "never … no jev caller touches ms365 / `msg`". No Jev doc treats Outlook as a candidate (grep of the 41 docs mentioning jev: "outlook" appears only in privacy lists).

5. **The ZDR/Pro fork was scoped too narrowly to reopen that refusal.** S2 offered "Pro at ~$20/mo" only for "our own agent's closing prose (never customer data, never the mailbox)" (S2 16:16, 17:45). No transcript or doc asks the operator whether Pro ZDR would make the mailbox job acceptable.

6. **The most Jev-shaped job was sitting half-finished in `personal/outlook-cleanup`.**
   - It is a closed 3-way `KEEP|DELETE|ABSTAIN` verdict over subject+bodyPreview, median **293 chars** (measured: python over `messages.jsonl`).
   - The consumer already exists: quarantine, soak, purge.
   - It **does spend Claude quota per message**. 31,837 of 36,470 verdicts are `source: sonnet-subagent` (measured). The skill prices Path B at "~$15-25 from claude.ai usage credits".
   - State as of this investigation: **2,716 ABSTAIN** rows unresolved. The **2,885-message quarantine has sat unpurged since 05-22** (`state.json` `purge_ts: null`). The inventory has not been refreshed since 05-21.

7. **None of the customer deliverables was Jev-shaped.** All 5 mission rows were created 09-07 (`created_at` 1788806928) and all have `ask_sent_at: null`. `cc-mission list` on 09-26 shows **5/5 STALE**: live-url blocked-operator, fleet bottle-menu blocked-operator (business mailbox logged out), Church bottle-menu needs-source with the ask unsent, and two floor plans drafted but "untouched 6d". The blockers are an email, a floor-plan ruling and a login, not inference.

8. **The S1 refuter said this on 09-18, and it never reached the doc.** Agent `a2658192eeac8bc0`: "all five customer deliverables blocked on one email, one ruling and one contact name … every hour here is an hour not spent on the reply to VenueContact that discharges three mission-board rows." Agent `a72d70b8`: "none needs a single token." Neither quote appears in the at-cost doc or the 100p dir (grep: 0 hits). S4: "Not working the mission board's three customer rows … this session's mandate was explicitly Jev" (09-21T10:29).

9. **reso-management-app was quiet during Jev's peak, but the lull predates Jev.** `git log`, author date: 09-11→14: 122 commits; 09-15→18: 3; 09-19→21 (Jev peak): 60; 09-22→25: 385.

10. **The one product job that ran in the window was never framed as a Jev job.** It was the reso test-audit on 09-25 (`b888cea96`, which retired or repaired vacuous tests: `a1a474566`, `0d1e7c7ff`, `705c0d306`), done with Claude. Jev was never applied to it. The chosen Jev job (memory promotion) produced 19 swaps and applied 0, so it has no consumer that acted.

## Candidate table

Throughput assumes 14.8 calls/min (measured, Add.5 C2).

| # | Job | Consumer that acts | Calls (method) | Outcome type | Considered? |
|---|---|---|---|---|---|
| 1 | **Outlook re-run**: Jev `choice` over the 2,716 ABSTAINs plus mail since 05-21. Auto-apply at p≥0.98, with Sonnet only on the remainder | Existing skill: quarantine → soak → purge (also unblocks the 2,885 purge) | ~4,700: 2,716 measured + ~2,000 new (estimated from ~490/mo Oct-25–Mar-26 inbox rate × 4 mo). ~5.3 h | Personal. Moves real mail and saves Sonnet quota. Not business | **Refused**, §4 "regardless of price". Never re-asked under Pro ZDR |
| 2 | `msg`/chat.db thread triage: "awaits my reply?" / "is this a lead?" | Operator's reply queue | 1,234 live messages (measured, `msg stats`). Thread count lower | Weak business value. The known stale ask (Evolve) came by Instagram DM, which is not in `msg` | **Refused**, §4 and a8:151 |
| 3 | reso test-audit pre-filter: per test, choice of vacuous/duplicate/keep | 09-25 test-audit campaign commits | 563 test files (measured, `git ls-files`). Cases are more | Engineering hygiene, not customer-facing | **Not considered** for reso. The infra twin was killed in a6: "mutation … ANSWERS the question Jev would only RANK" |
| 4 | reso lesson promotion (port of the shipped job) | reso memory index | ~430 calls, ~31 min (a5's own estimate, 821 files) | Agent quality, not customer-facing | **Parked** in a5:129: "prove the instrument here, then port". The instrument's 19 swaps were never applied |
| 5 | reso runbook-link relevance: "does this runbook describe this alarm?" | `audit-runbook-links.sh` gate | Tens (estimated). One per runbook link | Ops reliability for the live fleet | **Named as Jev-shaped, dropped** as NONE-MEASURED (S2 `a414155f`) |
| 6 | Customer mission rows (floor plans, bottle menus, live-url) | Venues | 0. Blockers are operator acts | Direct business value | **Not Jev-shaped.** The S1 refuter said so on 09-18 and was not carried forward |

**Bottom line.** No customer or business outcome was available to Jev: the customer work was blocked on the operator, not on classification. The one job that would have produced a concrete, used outcome in the window was the Outlook cleanup (#1). It is personal, and it was excluded before any work began by a privacy refusal that was right on the hobby plan. Nobody asked whether $20/mo Pro ZDR would make it acceptable.
