# /evolve-skill fixtures — pyramid-principle (starter set)

Fixture set for the `/evolve-skill pyramid-principle` spike. Each `*.md` here is ONE eval case with:
- `## input` — the task fed to the skill (a messy input + the target deliverable type).
- `## expected_behavior` — the rubric the LLM-judge scores against (1-5 + pass/fail criteria).

## How the spike uses these
`/evolve-skill pyramid-principle` will:
1. Run the current SKILL.md body against each `## input` via `claude-latest -p --bare`.
2. Score each output against its `## expected_behavior` (judge returns `{score, feedback}` via `--json-schema`).
3. Generate <=2 reflective variants of the skill body, seeded with the lowest-scoring cases.
4. Keep a variant ONLY if aggregate score STRICTLY beats baseline across >=2 reruns.
5. Emit the winning diff for human apply — it NEVER auto-writes the skill.

## The quality axes these fixtures reward
1. **Answer-first** — conclusion/recommendation leads, never buried.
2. **MECE grouping** — 3-5 non-overlapping support points covering all input facts.
3. **Outcome+method headings** — titles state WHAT result THROUGH what method.
4. **30-second scannability** — statement headings, no question/teaser headings.
5. **No invented facts** — gaps marked, numbers keep their qualifiers.
6. **Honesty under thin data** (case 04) — hold a position AND mark uncertainty; no false confidence.
7. **House style (reso)** — the framework is APPLIED but NOT NAMED in the deliverable body (no
   "Pyramid / MECE / SCQA / governing thought / key line"), per `feedback-pyramid-terms-invisible`.

## Coverage
| Case | Input type | Hardest axis tested |
|------|-----------|---------------------|
| 01 | rambling status → exec summary | answer-first + MECE + no metric inflation |
| 02 | pros/cons → approval memo | recommendation-first + mark-the-gap |
| 03 | buried-lede email | surface the ask + demote detail |
| 04 | thin-data decision | honesty: position + uncertainty, no false confidence |

## Run notes
SPIKE — one skill, 2-3 generations, hard `--max-budget-usd` cap. Cost ~$2-10/run. This is a STARTER
set: add cases over time and keep each rubric specific enough to score objectively. A run where NO
variant beats baseline is a valid, common, and useful outcome (it means the skill is already good on
these axes — do not force a mutation).
