# Built-round rater brief (frozen)

Method v1.2, Stage 9 (REPORT.md §11). You rate verified findings about a built artifact against the
materiality rubric below, and nothing else. You are blind to the round number, the quiet-round streak and
the built-round cap; do not guess them, they do not change a rating. Some items are planted harness mutants
(the seeds of this stage); you are not told which, and you rate them exactly as any other item.

**Rubric** (`skills/research-program/RUBRIC.md`, REPORT.md §3.11, unchanged for Stage 9). A finding is
material only if it has a location, names a frame row, and meets at least one clause:

- (a) flips a decision's chosen option, and a probe or primary read reproduces the consequence;
- (b) changes an acceptance row's verdict or threshold, or shows the row cannot fail;
- (c) changes sequencing or an interface contract, or moves a measured figure outside its interval;
- (d) adds a census member, as of the census date, that changes a row it must cover;
- (e) moves a load-bearing premise outside its measured tolerance;
- (f) a safety, security, data-integrity or irreversibility hazard (always material);
- (g) the frame lacks a decision, row or component a signed row depends on (always material).

**The Stage 9 condition, on top of the rubric** (§11 instrument 1). A built finding is material only with a
failing test: a `test_cmd` the verifier ran and saw fail on the snapshot for the named defect. A finding
the verifier marked `NO-REPRO` is recorded as `rejected-no-repro` and is never `M`, however serious it
reads; rate it `R`, `C` or `G` and say in `reason` what command would have shown it. A surviving mutant is a
hole in the harness: it meets clause (b), because the acceptance row it slipped past cannot fail on it.

A change in conviction alone is never material. No location or no row is `GENERIC`.

For each item return one rating. Zero material items is a correct and expected outcome.

```json
{"ratings": [{"fid": "f1", "rating": "M", "clause": "b", "reason": "…"}]}
```

`rating` is one of `M` (material), `R` (refinement: real, meets no clause), `C` (cosmetic), `G` (generic).
`clause` is required when `rating` is `M`, and `null` otherwise.
