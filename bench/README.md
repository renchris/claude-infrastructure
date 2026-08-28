# bench — the design-review perception pipeline

The runnable half of `docs/research/cv-design-review-2026-08-26/`. Everything here
is deterministic: no model, no GPU, no API key. The vision layer's job is what is
*left over* after this runs, and the router is the thing that decides what that
is.

```
python3 -m pip install numpy pillow playwright && playwright install chromium
bash run_bench.sh          # the whole pipeline, in order, with both gates
python3 selftest.py        # the arithmetic, in under a second, no browser
```

`run_bench.sh` exits non-zero if either gate fails. `PYTHON` and `CORPUS`
override the interpreter and the corpus directory.

## The stages, and what each one is for

| | File | In → out |
|---|---|---|
| build | `corpus/build_corpus.py` | → `corpus/out/pages/*.html` + `manifest.json`. One dashboard rendered thirteen ways: a clean control plus twelve variants, each carrying exactly one defect at a known location with a known magnitude. |
| capture | `capture.py` | pages → `shots/*.png` + `snapshots/*.json`. **One browser pass**, so the screenshot and the layout describe the same frame and a pixel finding can be argued against a DOM finding with no "maybe the page moved" escape hatch. |
| dom | `detect_dom.py` | snapshot → `findings_dom.json`. Nine general design-lint rules written against the page's own dominant convention, with an explicit `INDETERMINATE` verdict. |
| xcheck | `detect_xcheck.py` | snapshot + PNG → `findings_xcheck.json`. Not a third detector — a comparator that fires only where the DOM's claim and the rendered pixels disagree by more than a stated tolerance. |
| route | `route.py` | both findings files → `route-plan.json`. The abstention router. |
| score | `score.py` | findings + manifest → recall. Catches a rule that went **quiet**. |
| gate | `fp_budget.py` | clean pages → the ship gate. Catches a rule that went **loud**. |

`rules.py` is the registry every stage agrees on; `profiles.py` +
`review_profiles.json` are the per-app weightings.

## The two gates fail in opposite directions, and that is the design

`score.py` fails when a defect stops being found. `fp_budget.py` fails when a
rule fires on a page with no defect. A change that improves either at the other's
expense is the failure mode neither can see alone, which is why `run_bench.sh`
runs both and takes the worse answer.

Current state on this corpus:

```
score      11/11 reachable defects  (9/9 DOM-determined, 2/2 pixels-only)
           1 unreachable by construction, covered by the router's T2 question
fp_budget  0 asserted findings on the control
```

**The 2/2 pixels-only is now deterministic.** Both defects the DOM is blind to —
contrast over a gradient, and a mark's ink not centred in the shape around it —
are settled by the cross-check at zero model cost. Neither needs a crop, and
neither reaches the vision layer at all.

## The router, in one paragraph

`detect_dom` runs first. Its `INDETERMINATE` verdicts, minus whatever the
cross-check actually closed, collapsed by `(rule, backdrop signature)`, become
the vision layer's queue — cropped to the region in question, ranked by
consequence, and bounded by an image budget whose overflow is **printed** rather
than dropped. On top of that, one unconditional page-global question about the
six classes no rule can screen: hierarchy, gestalt, content-fit,
semantic-coherence, optical-alignment, readability.

Three properties are load-bearing and each has a test in `selftest.py`:

- **The subtraction is code.** `rules.RESOLVED_BY` is a table, so a rule added
  next month cannot quietly stop being subtracted.
- **It is gated on the cross-check having run.** A missing `findings_xcheck.json`
  makes the queue *grow*, because an empty file resolves nothing while looking
  exactly like nothing needing resolution.
- **If the answer has a number in it, the model does not get the question.**
  Settled numbers ride along in `facts`. `route._assert_never_list` re-checks the
  finished plan, and sharing a class with an unscreenable one does not grant a
  numeric rule a route.

## Per-app weightings

`review_profiles.json` carries review *intent* and a weight per rule per app —
`reso-landing-app` is a marketing-aesthetics problem, `reso-management-app` is a
design-system-conformance one, `reso-web-app` sits between. `python3 profiles.py`
prints the matrix; `--findings <file>` re-ranks a real findings file under one.

A weight ranks and never suppresses; `0.0` is the one exception and means the
rule is *off* for that app. Every profile must weight every registered rule, so
adding a rule to `rules.py` breaks all four until someone decides what it means
per app. Deliberately absent: any fact about an app's framework, CSS engine or
token map. Those are generated from a live read of the checkout, never authored
here.

## Adding a rule

1. Register it in `rules.py` — id, layer, class, whether its answer is a number
   or a judgement, and its intent. Nothing else will accept an unregistered id.
2. Give it a weight in every profile in `review_profiles.json`.
3. Emit it from a detector via that detector's `rep()`, and count its subjects
   with `note()` — a rule that evaluated zero subjects is unproven, not passing.
4. Run `bash run_bench.sh`. Both gates must be green before it ships.

## What is deliberately not here

No local VLM, no GUI-specialist model, and no VLM-as-quality-gate. The June 2026
campaign ratified that taste stays human and gates adjudicate correctness and
coverage only; the sanctioned role for a vision model here is advisory triage of
what the deterministic layer could not answer. `bench_local_vlm.py` and
`local_vlm_results.json` are the measurement that settled the first question and
are kept as evidence, not as a stage.
