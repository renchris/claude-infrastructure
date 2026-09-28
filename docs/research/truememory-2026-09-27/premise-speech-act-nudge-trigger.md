# Premise check: speech-act-nudge-trigger (lens = premise)

Verdict: REJECT (conviction 72). There is a real gap in reach. The gap in value is not evidenced, and the regex as proposed catches none of the cases it was designed for.

## 1. Do we already have it?  No.
- hooks/memory-nudge.sh:46 reads `INTERVAL=${MEMORY_NUDGE_INTERVAL:-12}`. The only triggers are at :494-502: `COUNT % INTERVAL == 0`, plus `COUNT == 1` when the index is over its limit. Nothing in the hook reads prompt content (MEASURED, by reading the file).
- UserPromptSubmit hooks that do match prompt text with a regex already exist: hooks/handoff-intent-nudge.sh:40 and hooks/research-precognition-nudge.sh:18-19. So the mechanism has precedent in this repo. Neither of them targets memory.
- There is no prior attempt. `git log --all -G "i told you|from now on\b|keep forgetting|speech.?act|correction.?(detect|trigger|nudge)"` found only 9a65c7913/bc8f95b32, which are backlog-triage docs and unrelated. The memory branches (gu-memory-knowledge, fix/memory-budget-recover, reland/memory-budget) are all about the budget (MEASURED).
- The plan does not consider this idea. docs/plans/MEMORY_KNOWLEDGE_V2.md F3 (:212) names the reach gap. Its answer, M2, was "fire on STATE (budget fill) ... on an event with 100% reach". R7 (:262-265) rejects SessionEnd. Neither §4 nor §7.5 considers a trigger based on prompt content (MEASURED).
- No decision ledger exists for the nudge. grep `decision.ledger` over hooks/memory-nudge.sh and bin/ returned nothing, so the proposal's A/B instrument would also have to be built (MEASURED).

## 2. Is the gap real? Reach: yes. Value: no.
The reach numbers check out against the notes: 86.7% of live counters sit at 1 (our-write.md:158), 9.6% of sessions are ever nudged, and P(write | never nudged) is 2.4% (our-write.md:140-141). Everything below was MEASURED by /tmp/tm-research/premise-speechact/probe.py and probe2.py, run over prompts-typed.jsonl: 2,650 prompts, of which 1,887 remain after the proposal's injected-text skips.

(a) The regex as proposed has 4 hits in 30 days and none is a standing rule (probe.out):
    - 2 are "last time" episodic references (696eb098), 1 is "we already went over how to wrap it" (dacebc4c), and 1 is "helped last time" (dacebc4c).
    - The `^`-anchored arm misses all four "Remember:" restatements, because each one sits mid-prompt after other text or a pasted quote.
    - Stripping trailing questions removes "keep forgetting every single time?" and "flip flopping ... two days??".
    - `flip-flop` needs a hyphen, but the operator types "flip flopping".

(b) A corrected variant is unanchored, uses sentence-start "remember", and accepts "flip[- ]flop". It has 11 hits (probe2.out). Classified by hand:
    - It finds 1 new standing rule that was never captured: b8fcf245 (3 typed prompts), "Remember commands given to a user is something that you can't run". No memory write happened in that session, and no store contains the rule.
    - It finds 2 standing rules that were ALREADY stored before the operator restated them:
      - "Remember: Pyramid Principles" (fa6a131b) is already in ~/.claude/CLAUDE.md:625 and in several project memories (convert-pdf-to-md/pyramid-principle-presentations.md, fde-endpoint-business-case/fde-email-rules.md).
      - "Remember: ... human sourced the images" (bc3d026d, 09-21) is already in reso-management-app/.claude/rules/bottle-reference-sourcing.md, which landed 09-11 (ebfc88fc2) with :332-334 "keep human".
      - These two failed at compliance or recall, not at capture. The nudge's own text would at best produce a no-op, and at worst a duplicate, which the anti-capture rule forbids.
    - It finds 5 frustration or regression complaints: flip-flop x3, keep-forgetting, and "like normal". Kitty flip-flop had already become the 09-17 OPERATOR RULING lesson (our-usage.md:156). These are recall or regression failures, not rules waiting to be written.
    - It has 3 false positives or briefs: "every single time" (d71e8e48), a 5,200-char dispatch brief (d481201f), and "we already" (dacebc4c).
    => That is about 1 capturable new rule per month across 1,887 typed prompts (ESTIMATED from a single hand classification).

(c) "Pyramid Principles" appears in about 40 typed prompts (MEASURED by substring count). The operator uses it as a per-prompt output directive. It is already stored, so it is not a memory miss.

(d) The 10 memory-miss complaints (our-usage.md:149-159) are episodic retrieval failures: "retrieve that research", "like we did before with wifi", "i feel like youre not reading our memory". A nudge that asks for capture at the moment of the complaint does not address any of them.

## 3. Consequence
The measured costs point at recall and compliance of rules that already exist, not at capture when a rule is stated. The candidate's benefit would be about 1 case a month. It would also need a new ledger to be measurable. If anyone revisits it, it needs the corrected regex (unanchored, sentence-start remember, `flip[- ]flop`, no trailing-question drop on complaint phrases), and the frustration class should go to a regression or lesson path, not a capture nudge.
