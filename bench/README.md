# The design-review perception bench

Five files build a ground-truth corpus, photograph it, run every deterministic
rule over it, route what the rules honestly cannot answer to an eye, and refuse
to ship a rule that fires on a page with no defect.

The findings, the architecture and the decision that governs all of it are in
`../docs/research/cv-design-review-2026-08-26/` — `README.md` for what was
measured, `PIPELINE_SPEC.md` for the contracts and the rulings this code obeys.
The one-line version: **the browser answers every question with a number in it,
the eye answers the rest, and taste stays human** — nothing here is a quality
gate, and no local model is in the path.

## Run it

```bash
pip install numpy pillow playwright && playwright install chromium
python3 corpus/build_corpus.py corpus/out     # 13 pages: 1 control + 12 defects
python3 capture.py corpus/out                 # shots + snapshots + run_env.json
python3 detect_dom.py corpus/out              # 9 general rules, 1 with an abstention
python3 detect_xcheck.py corpus/out           # X1 + X3 (add --x2 for the centroid arm)
python3 route_abstain.py corpus/out --app reso-management-app
python3 fp_budget.py corpus/out               # the ship gate; exits 1 on any control finding
```

`BENCH_CHROMIUM=/path/to/chrome` replaces the `chromium` channel where the
browser lives outside Playwright's download tree (containers, CI images).

## What each file is for

| File | Job | The number it holds up |
|---|---|---|
| `corpus/build_corpus.py` | 13 pages, one injected defect each, `detectable_by` split | 9 DOM-determined, 3 pixels-only, 1 clean control |
| `capture.py` | one browser pass → screenshot + layout snapshot + render env | the snapshot describes the frame that was photographed, so pixel and DOM findings can be argued against each other |
| `detect_dom.py` | 9 design-lint rules, with an explicit `INDETERMINATE` | 9/9 DOM-determined defects, 0 control false positives |
| `detect_xcheck.py` | the DOM-vs-pixels comparator: X1 zero-ink, X2 centroid, X3 contrast-real | X3 resolves contrast-over-a-gradient deterministically, 0 control FP |
| `route_abstain.py` | the abstention router: what the rules could not answer becomes a cropped queue for an eye | T1 = 0 on this corpus, because the cross-check closes both abstentions |
| `fp_budget.py` | every rule re-run against the clean control | zero on the control is the ship gate, enforced at n=1 |
| `profiles.json` · `profiles.py` | per-app rule weightings — three apps, three problems, one harness | a profile may reorder and it may abstain, and nothing else |
| `bench_local_vlm.py` | the resolution/latency sweep that ruled local models out | 21–66 s/screenshot; correct at 1 of 3 resolutions |

## The four things the 2026-08-27 pass changed

**X2 measures a real quantity now, and still ships disabled.** The centroid arm
had two defects, both found by trying to validate it. It compared a glyph's ink
to the glyph's *own* box, and `getBoundingClientRect` returns the post-transform
box — so an optical compensation moved box and ink together and the number was
invariant under the exact thing it existed to verify (measured: `span.glyph`
reported 2.1px left on all thirteen pages, compensated and uncompensated alike).
And its background was the crop's modal colour, so a round button's square-crop
corners counted as ink and swamped a 16px glyph.

It now measures against the **container**, inside a **flood-filled painted-shape
mask**, against that shape's own centroid, with the shape's antialiased rim
eroded away. Validating *that* found a third thing worth writing down: a purely
chromatic shape mask deletes ink that matches the page background — a white glyph
on a blue button on a white page — and deletes it from the reference shape too,
which attenuated a known 2.0px offset to 0.6px. The mask has to be geometric.

With all three closed the arm reads **0.0px horizontal on the control and 2.0px
left on the variant** — the corpus's injected `translate(2px, 2px)` to the
hundredth.

It stays behind `--x2` anyway, and the reason is now a measurement rather than a
doubt: the corpus's compensation constant was authored against macOS Helvetica
metrics, and on a Linux render where `Helvetica` resolves through fontconfig to
Liberation Sans (`run_env.json` records the probe widths) the *control's* glyph
genuinely sits 2.5px low. The arm correctly says so — a true finding that is
still a control false positive under a gate that is absolute at n=1. Run
`fp_budget.py --x2` on your own machine before enabling it.

**X3 stopped depending on the platform to be right.** It sampled "the modal
non-ink colour" behind the text, and the code took the plain mode. On a smooth
gradient no backdrop colour repeats, so the mode of the band *is* the text
colour — the one colour with many identical pixels. The check then computed the
text against itself, returned ~1:1 on both sides, and went silent on the only
defect it exists to catch. It did that on Linux while passing on macOS, which is
the worst available failure shape: a silent pass that looks like a clean page and
varies by machine. Excluding the foreground before taking the mode restores the
documented result (**4.81:1 left, 2.07:1 right** at dpr 1.5) with zero control
false positives.

**The abstention router exists, and on this corpus it routes nothing.** That is
the intended answer, not a broken build: `detect_dom` abstains twice on the
gradient page, `detect_xcheck` closes both, and T1 falls to 0 — the whole point
of the cross-check. The subtraction is **gated on the cross-check file
existing**, so an outage makes the queue *grow* rather than silently shrink to
nothing; `route-plan.json`'s `degradation` block says which happened. T2 — the
six classes no rule can screen — is unconditional and budget-exempt. Every
routed question is checked against a NEVER list at build time, so a question with
a number in its answer raises instead of shipping. (It caught the author's own
first draft, which said "not as a measurement".)

**Per-app weightings are policy, and they are constrained to two verbs.** A
profile may **reorder** and it may **abstain**. It cannot change a finding's
truth, mint or soften a severity, or turn a rule off quietly — a withheld rule
emits an `INDETERMINATE` naming the profile and the reason. `reso-management-app`
weights conformance ×2 and judgement ×0.5; `reso-landing-app` inverts that
(×0.25 / ×2) because grading a purchased template against our tokens measures the
purchase, not the page; both keep accessibility at ×1.5, because that is
correctness rather than taste. Each row carries a `basis`, and C11's ruling
applies: a live surface read of the checkout beats this file automatically.

## The two rules a new rule has to obey

1. **Run it against the clean control before it ships.** `fp_budget.py` exits 1
   on any finding on a page with no defect. There is no baseline-diff
   suppression, because subtracting the control's own findings from every other
   page is exactly how a noisy rule survives.
2. **Add its subject domain to the census.** A finding count with no denominator
   cannot be compared between two corpora. One page here puts 47 elements to a
   rule; one real route puts 1,841 — false positives scale with subjects, not
   with pages, so the budget is stated per 1,000 subject-checks.

`fp_budget.py` will not print a false-positive *rate* below 16 clean pages
(3/16 = 18.75% is the first rule-of-three bound under the ~20% credibility
cliff). Below that it prints the deficit. The way to close it is the mined clean
corpus — screens from the apps' own git history that shipped and were never
touched by a visual-bug fix, where every finding is a false positive by
construction. Point `fp_budget.py` at those corpus directories as extra
positional arguments when they exist.
