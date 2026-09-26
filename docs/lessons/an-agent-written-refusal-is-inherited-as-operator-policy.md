# An agent-written refusal is inherited as operator policy

2026-09-26, from the Jev post-mortem (`docs/research/jev-postmortem-2026-09-26.md`, receipts `a3-wave.md` #1 and
`a5-counterfactual.md` #4-5).

**What happened.**

- **An agent wrote the refusal, and later briefs treated it as operator policy.** On 09-18 a research
  session wrote a table row: *"Anything with private data — transcripts, mailbox, the `msg` corpus —
  Refused regardless of price."* It was a sound judgment for the hobby plan, where the vendor offered
  no zero-retention. Three days later a 10-agent wave opened every brief with *"STANDING REFUSAL, not
  negotiable: no transcripts, no mailbox, no msg corpus, no customer data"*. No operator prompt had
  set it; it was the agent's own row, now carrying the operator's authority.
- **The refusal fenced off the best job for the model.** Outlook cleanup is a closed three-way
  verdict over short text, with a consumer that already exists and 2,716 unresolved rows. It was
  never re-examined.
- **The refusal's own premise was never re-asked.** The pivotal question, whether a paid plan with
  zero-retention would make that job acceptable, never reached the operator. The Pro fork was offered
  only for a different, lower-value corpus.

**The rule.** When a brief carries a restriction, it names who set it: the operator (quote and date)
or an agent (doc path), together with the premise it rests on.

- **Agent-authored limits are hypotheses tied to their premise.** "Refused because no ZDR on this
  plan" dissolves the moment ZDR is on the table, and the brief must say so.
- **Operator-authored limits are binding.** Nothing about a changed premise overrides them without
  asking.
- **Unlabelled limits get labelled first.** A successor that finds an unlabelled "not negotiable"
  greps the operator's prompts for its source before treating it as binding.
- **Why it matters.** Agent-written caution is the cheapest text in the system to produce and the
  most expensive to inherit. It silently narrows what every later session is allowed to consider,
  and it borrows authority it never had.
