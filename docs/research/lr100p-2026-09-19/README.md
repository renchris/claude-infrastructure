# lr100p — 2026-09-19 research corpus (the n=5 production run)

Ground truth for the reopened `docs/plans/LIMIT_RECOVER_100P.md`. Produced by one Dynamic Workflow
(`wf_d48f0e74-15e`, 14 read-only research units on Opus 5/high → 3 designs → 9 adversarial critiques
→ synthesis on Fable 5.1/xhigh; the last two slots re-ran as `wf_74cd57c1-15f` after the lead itself
was limit-killed on next3 and transplanted in place to next2). Every claim is cited file:line or
`<command> => <output>` against the tree at `c1c637a4a`…`226b73888`; line numbers are a snapshot —
re-anchor on the quoted strings before editing.

- `research/U01…U14` — the measured chain, one unit per seam
- `design/D1…D3` — zero-touch · one-command · identity+observability
- `critique/<design>--<lens>` — latency · fault-tolerance · safety-blast-radius, each with `keeps`
- `PLAN_DRAFT.md` — the synthesis: architecture, waves W1–W7, DoD, dropped-with-reason, open decisions

Persisted here because `/private/tmp` is wiped at boot (docs/lessons/perishable-input-is-what-makes-a-wave-urgent.md).
