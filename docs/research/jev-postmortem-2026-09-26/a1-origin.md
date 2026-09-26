# A1 — Origin and target selection

S1 = 0f5b9509 (09-18). S2 = 09e64dcb (09-19). WF1 = S1 workflow wf_1411105c-2aa. WF2 = S2 workflow wf_64f6e64f-193. Times are UTC. Counts are measured with python3/jq over the JSONL, the workflow JSON or `idl.jsonl*`, unless marked otherwise.

## Findings

1. **"Our repositories" was narrowed to claude-infrastructure by the agents' own briefs.** WF1's inventory axis: "Go find, in /Users/chrisren/Development/claude-infrastructure and the live ~/.claude layer" (WF1 script :242). WF2 gave 7½ of 8 survey agents to this repo and half of one agent to reso-management-app ("Be skeptical and report honestly if there are few", WF2 :202-204). outlook-cleanup was never a candidate; it appears only in the injected skill list. The personal-data candidates (mailbox, transcripts, the 213,995-message `msg` corpus) were "Refused regardless of price" (S1 #272, 23:31:14).
2. **Both briefs seeded the winner.** WF1 :257 lists the known failures, including "anti-deference-nudge abstains no-tell on 96% of evaluations". WF2 :54-57: "THE HIGHEST-SIGNAL CANDIDATES ARE WHERE THE REPO HAS ALREADY MEASURED ITS OWN HEURISTIC FAILING … e.g. '96% abstain no-tell'". The scoring (`value + 1.5×signal`, :235) rewards self-measurement, which only this repo does.
3. **Rank 1 came from a test for existence, not size.** The WF1 critic chose N_sync because it has "a terminating zero branch". S1: "That is N_sync, and it is not zero" (#268, 23:30:48), which made it rank 1. WF1's own inventory axis had called anti-deference "well-shaped but economically marginal" and ranked kill-switch and lesson relevance above it.
4. **S2 fixed the target before its survey returned.** WF2 started at 04:42:05. S2: "Prior art already ranked the targets … That makes the pilot my deliverable" (#199, 04:43:42). It started building "whichever target wins" at 04:44:15 and did the anti-deference hook surgery at 04:50:37. WF2 finished at 04:53:53. In WF2's scoring the top candidate was the kill-switch (24, REFUTED). Anti-deference only tied with three others at 22.5.
5. **The value evidence at selection was an abstention rate, not a rate of the problem.** "94.7% no-tell" uses every Stop as the denominator. WF1's inventory agent listed as NOT measured: "Whether the 94.3% 'no-tell' abstain rate … is CORRECT … or a MISS rate". A measured base rate already existed on disk: `conviction-close-2026-09-08.md` §2.2 (:81, :96) gives about 300 real deferrals per 30 days (21/70 hand-read), against about 160 hook fires. That leaves roughly 5/day for the arm (estimated from those figures). It surfaced at 04:54 (S2 #543), after the arm was built, and was never used as a reason to stop.
6. **S1 recommended declining, and the operator declined. S2 reversed that without re-arguing it.** Packet b1fe1071dad4 recommended "decline for now", 70% (S1 #367, 23:42:16). The operator vetoed at 00:02:28 on 09-19. The /goal came 4h38m later (04:40:05). S1's reason ("~960 decisions a day does not repay pioneering a three-day-old vendor") was never addressed.
7. **The ZDR wall was known after build and land, and S2 had argued an earlier warning away.** S1 wrote "enterprise-gated ZDR" (23:29:58, 09-18). S2's WebFetch of the ZDR doc returned 404 (#209). A WebSearch summary that said nothing about plans (#213) was then read as "materially updates the prior doc's 'enterprise-gated' note" (#216, 04:43:57). Arm commit d107b1a44 at 05:00:27. Landing confirmed as dad8080ba at 05:32:51. The first 403 ("Current plan: hobby") came at 16:03:13 (#1321), about 10.5h later. No API key existed until 16:02, so the arm was landed with zero real calls.
8. **S2 reported "done" at close; Jev had produced no verdicts on real traffic.** Recap quoted by the operator (19:10:04): "Goal was to find where Jev earns its place in our repos and wire it in. That's landed and live". DoD (22:34:39): "Jev integration — COMPLETE AND LIVE, nothing agent-side open". What actually existed:
   - a handful of synthetic probes, plus 20 synthetic closes;
   - on those, the shipped threshold 0.98 fired "0 out of 10 on true deferrals" (#1878);
   - 0 real closes judged.
   All IDL archives (09-13 to 09-26) contain **0 `semantic-deference` rows**. From 09-19T05Z to 09-22 there were 867 anti-deference evaluations and 24 fires, all lexical.
9. **The goal's value test was never a gate.** Every close put "does Jev beat the regex on our labels?" onto a pilot that needed an operator ruling on data retention (c3752f5fca96). "Landed and live" was reported as meeting the goal.

## Evidence detail

**S1 prompt** (#15, 23:10:54): "…what is the most high-signal and value tasks we can apply it to via at-cost-API over what we have with our included usage in our Claude Plans".

**S1 ranking** (#307; doc §4 :131-139):

| Rank | Candidate | Verdict |
|---|---|---|
| 1 | In-hook semantic verdicts (anti-deference plus completion-assert authorship, "~960/day ≈ $2.45/month") | chosen |
| 2 | Fan-out past the 5h cap | "wrong vendor" |
| 3 | Lesson/memory relevance | "Plan, not dollars" |
| — | ~394K shell lookups/day | "Leave them" |
| — | Private corpora | refused |

WF1 critic §4: "every hour here is an hour not spent on the reply to VenueContact" (reso customer work).

**S2 /goal** (#18, 04:40:05): "identify the highest value and signal opportunities in our repositories to utilize, and integrate 100th percentile clean performant concise code".

WF2 survey dimensions:
- close-integrity
- authorship-killswitch
- bash-safety-gates
- backlog-decisions
- memory-hygiene
- session-liveness
- research-orchestration
- gate-triage-and-product (the reso half)

The reso half found "a thin story", no AI SDK, and dropped every product surface. WF2 produced 32 candidates and verified the top 6 (3 CONFIRMED, 1 WEAK, 2 REFUTED). 26 were never verified, e.g. backlog dedup (21.5) and the why-not-now impossibility test (21).

WF2's verifier on anti-deference said the honest minimum was to "add ONE arm for the decision family … shadow-log it against the 447 known hits before it is ever allowed to block". S2 itself said (#523, 04:54:03): "Its top confirmed candidate is the one I built".

**Doc** (`docs/research/jev-at-cost-api-2026-09-18.md`):
- Addendum A (:175-184): kill-switch REFUTED, so N_sync is about 540/day.
- Addendum B (:220-229): "an abstention rate, not a miss rate".
- Addendum C correction (:255-265): the "hobby" 403.

**Commits** (UTC):

| Commit | Time | What |
|---|---|---|
| 19aedd47e | 09-18 23:31 | S1 doc |
| d107b1a44 | 09-19 05:00 | arm |
| dad8080ba | landed 05:32 | landing |
| adff31b2f | 16:04 | "ZDR is plan-gated" |
| 7ffd36be4 | 19:21 | "the arm landed inert" (threshold 0.98 → 0.90) |

S2's closes after the 403 (16:16:45, 19:13:06, and 22:34:07 "Everything I can do without you is done and live") never gave a real-traffic verdict count. It was 0.
