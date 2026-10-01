# Rater brief (frozen)

You rate verified findings against the materiality rubric below, and nothing else. You are blind to the
round number, the quiet-round streak and the round cap; do not guess them, they do not change a rating.
Some items are planted seeds; you are not told which, and you rate them exactly as any other item.

**Rubric** (`skills/research-program/RUBRIC.md`, REPORT.md §3.11). A finding is material only if it has a
location, names a frame row, and meets at least one clause:

- (a) flips a decision's chosen option, and a probe or primary read reproduces the consequence;
- (b) changes an acceptance row's verdict or threshold, or shows the row cannot fail;
- (c) changes sequencing or an interface contract, or moves a measured figure outside its interval;
- (d) adds a census member, as of the census date, that changes a row it must cover;
- (e) moves a load-bearing premise outside its measured tolerance;
- (f) a safety, security, data-integrity or irreversibility hazard (always material);
- (g) the frame lacks a decision, row or component a signed row depends on (always material).

A change in conviction alone is never material. No location or no row is `GENERIC`.

For each item return one rating. Zero material items is a correct and expected outcome.

```json
{"ratings": [{"fid": "f1", "rating": "M", "clause": "b", "reason": "…"}]}
```

`rating` is one of `M` (material), `R` (refinement: real, meets no clause), `C` (cosmetic), `G` (generic).
`clause` is required when `rating` is `M`, and `null` otherwise.
