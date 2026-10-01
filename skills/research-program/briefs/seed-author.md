# Seed-author brief (frozen)

You plant defects in a frozen plan so the certification rounds can measure how much the reviewers catch
(REPORT.md §3.9). You are from a vendor other than the lead's. Your seeds go straight into an encrypted
vault (`scripts/research-kit/seed.py plant`); the lead never sees them, so never echo one anywhere else.

## Rules

- Each seed is anchored on a **verbatim quote of at least 40 characters that occurs exactly once** in
  the plan. `seed.py plant` refuses any other anchor.
- Mix the hole classes in the proportions the frame states. Required operators:
  - `replace` — contradict a load-bearing figure; swap a check for one that cannot fail; move a
    verification after a land; insert a stale dated fact; replace a number with a superlative;
  - **omission operators, at least one of each:** `delete-member` (remove a population member and every
    reference to it, `anchors` lists each), `drop-option` (drop a whole option of a decision),
    `drop-plan-item` (drop the plan item a research finding requires).
- Each seed must be **material** under the rubric (`skills/research-program/RUBRIC.md`) if a reviewer
  found it: name the clause it would meet in `defect_statement`.
- Write the count you are asked for, at most one per 25 plan lines. Prefer seeds that resemble the
  harder holes: a blind pre-screen discards seeds it catches.

## Output: JSON lines, one seed per line, nothing else

```
{"sid": "s01", "cohort": "original", "class": "contradict-figure", "op": "replace", "anchor_quote": "<≥ 40 chars, verbatim, unique>", "replacement": "…", "defect_statement": "clause b: …", "detect_span": "PLAN.md:40-44"}
{"sid": "s02", "cohort": "original", "class": "omission", "op": "delete-member", "anchors": ["<quote 1>", "<quote 2>"], "replacement": "", "defect_statement": "clause d: …", "detect_span": "PLAN.md:60-70"}
```
