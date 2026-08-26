# bench — the instrument

The corpus in here is not a nice-to-have. No published benchmark scores the property a
design reviewer needs — every ScreenSpot variant scores point-in-box rather than IoU, so a
model can score 96% with edges tens of pixels wrong, and ScreenSpot-Pro contains zero web
screenshots. This is the only instrument that measures what we actually do.

Findings and rationale: [`../docs/research/cv-design-review-2026-08-26/README.md`](../docs/research/cv-design-review-2026-08-26/README.md).

## Run it

```bash
pip install numpy pillow playwright     # then: playwright install chromium

python3 corpus/build_corpus.py corpus/out   # 13 pages: 1 control + 12 one-defect variants
python3 capture.py            corpus/out    # shots/ + snapshots/, one browser pass
python3 detect_dom.py         corpus/out    # 9 deterministic rules -> findings_dom.json
python3 detect_xcheck.py      corpus/out    # 3 NumPy cross-check arms -> findings_xcheck.json
python3 route.py              corpus/out    # the abstention router -> route_plan.json
python3 fp_budget.py          corpus/out    # THE GATE. exit 1 on any breach.
```

`fp_budget.py` is the one to run before shipping any rule. Everything else reports; it
decides.

## What each layer is for, and what it may not be asked

| | Answers | Never ask it |
|---|---|---|
| `detect_dom.py` | every question with a number in the answer — spacing, alignment, contrast on a solid backdrop, overflow, target size, token conformance | whether it looks good |
| `detect_xcheck.py` | where the DOM's claim and the rendered pixels **disagree** by more than a stated tolerance | anything either layer can answer alone |
| `route.py` → a model | hierarchy, grouping, "does this page make sense" | **any number** |

The third row is advisory and gates nothing — the June 2026 campaign ratified that taste
stays human and gates adjudicate correctness and coverage only. `route_plan.json` carries
`"never_gates": true` as a field, so wiring it into an exit code means deleting a line
someone can see in a diff.

## Scores on this corpus

9 DOM-determined defects, 2 pixels-only, plus one (`hierarchy-inversion`) that is a
judgement rather than a measurement and is deliberately out of reach of both layers.

| Layer | Catches | Findings on the clean control |
|---|---|---|
| `detect_dom.py` | 9 / 9 DOM-determined | **0** |
| `detect_xcheck.py` | 2 / 2 pixels-only reachable by measurement | **0** |
| routed to a model | the residue, 0 crop requests + 1 blind look per page | — |

The cross-check settles both `contrast-indeterminate` abstentions without a model call, so
the crop queue is empty on this corpus. `route.py --without-xcheck` re-runs the same routing
with that layer withheld and the queue becomes 1 — which is what the cross-check is worth,
as a number rather than a claim.

## Three traps this corpus has already sprung, all the same shape

Each was a plausible number nobody checked, and each was invisible until something else
disagreed with it. They are recorded because the next one will look like these.

1. **The control was not clean.** The first run flagged three real WCAG failures in the
   hand-authored baseline. The linter earned its keep before it saw an injected defect.
2. **Deduplicating findings by `(rule, target)` swallowed a real defect** — the key has to
   span the claim, not just its location.
3. **A detector's verdict turned on a font fallback.** `detect_xcheck`'s X3 arm took the
   *modal* colour of each third as the backdrop; under a gradient no backdrop colour
   repeats while antialiased text is one exact constant, so the mode can be the foreground.
   It then contrasts the text against itself, gets 1.00:1 at both ends and reports nothing.
   On macOS/Helvetica the backdrop won the mode and the arm fired; on Linux/DejaVu the ink
   won and the same arm went silent on the same page. Fixed by excluding ink first and
   taking the median.

   The same fallback made the **control** font-dependent: the optical-centering item's
   compensation was a constant measured against Helvetica's `▶` outline, so off macOS the
   clean page carried a 3.6px optical defect of its own. The mark is now drawn by CSS
   borders, whose ink centroid is exact arithmetic on every machine.

## Portability

`findings_dom.json` is byte-identical between macOS/Helvetica and Linux/DejaVu — the DOM
layer is font-independent in outcome, which is most of why it is the layer that does the
work. The pixel layers are not, and both of the corpus's pixels-only items are now specified
by CSS geometry rather than by font metrics so that they can be scored anywhere.

`capture.py` pins sRGB, disables LCD text, hides scrollbars, forces the device scale factor
and waits on `document.fonts`. Without the forced scale factor, headless and headed disagree
on line-box rounding by ~1.5px accumulated over four paragraphs, and every geometric finding
inherits a phantom offset that reads like a real 1px bug.
