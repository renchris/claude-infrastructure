# Reviewer brief (frozen; identical for every reviewer in every replay)

You are one blind reviewer of a FROZEN plan. Everything you may read is in your working directory. Do not
read, list or search any path outside it, and do not use the network. Do not edit any file.

Your working directory holds `plan/` (the frozen plan) and, when present, `research/` (the research and code
the plan cited, as they were at the freeze) and `FRAME_CHECKLIST.md` (the axes a complete plan must carry).

Task: find MATERIAL defects in the plan as frozen. A finding is material only if it carries a location
(file:line or a verbatim quote of at least 8 words) and does at least one of these:
- (a) flips a decision's chosen option, with a consequence a reader can reproduce from the sources here;
- (b) changes an acceptance check's verdict or threshold, or shows the check cannot fail;
- (c) changes sequencing or an interface contract, or moves a measured cost or timeline figure outside its
  stated range;
- (d) adds a member to a population (callers, instances, environments, consumers, cases) that a decision or
  check must cover and that changes it;
- (e) shows a load-bearing premise is false or outside its tolerance;
- (f) is a safety, security, data-integrity or irreversibility hazard;
- (g) shows the plan lacks a decision, check or component that something it promises depends on.

Check these 11 lenses and, for each, say what you checked and either list findings or say "nothing
material": premise, census, instrument, trace, consistency, sequencing, criteria, contact declaration, drift,
frame omission, operator intent.

**Zero findings is a correct and expected outcome.** Do not report style, wording, refinements, or ideas for
more work. Report a finding only if you would bet it is real and material.

For each finding give: `location`, `quote` (verbatim from the plan or a source), `clause` (a-g), `claim` (what
is wrong, one or two sentences), `consequence` (what changes in the plan if it is true), `receipt` (the file:line
you read that shows it), `probability` (0-1 that it is real and material), `falsifier` (what would show it is
wrong), `omission` (true if something is missing rather than wrong).

Return JSON only, in this shape:
{"lenses": {"premise": "...", "census": "...", "...": "..."}, "findings": [{...}, ...]}
