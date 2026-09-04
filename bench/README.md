# `bench/` — the design-review perception pipeline

The instrument for `docs/research/cv-design-review-2026-08-26/`. It is the only
thing we have that measures what a design review actually does, and it is the
gate every rule has to pass before it ships.

Nothing here calls a model. The pipeline decides **what a model should be asked**
and, more importantly, what it should not be — every question with a number in
the answer is settled deterministically and forwarded as a value.

## Run it

```bash
pip install numpy pillow playwright        # once
python3 corpus/build_corpus.py corpus/out  # 13 pages: 1 control + 12 defects
python3 capture.py corpus/out              # screenshots + layout snapshots, one pass
python3 detect_dom.py corpus/out           # 9 deterministic rules, three-valued
python3 detect_xcheck.py corpus/out        # X1/X2/X3: DOM vs pixels, only where they disagree
python3 route.py corpus/out --emit-crops   # the abstention router -> route-plan.json
python3 score.py corpus/out                # THE GATE. exits non-zero on a control finding
python3 report.py corpus/out --app reso-management-app
```

`BENCH_CHROMIUM=/path/to/chrome` names the browser when Playwright's own channel
is not the one installed. The run records what it used in `corpus/out/run.json`,
because **every pixel number here is a number about one render**: measured across
two machines, `findings_dom.json` was byte-identical while the X3 contrast pair
moved 4.81/1.57 → 6.15/1.76. Same verdicts, different numbers. Quote a number
without its run and you are quoting a machine.

## What each file is for

| File | Job | The thing it refuses to do |
|---|---|---|
| `corpus/build_corpus.py` | 13 ground-truth pages, one injected defect each, `detectable_by` split | — |
| `capture.py` | one browser pass → PNG + layout/style snapshot of *the same frame* | guess the browser; it records it |
| `detect_dom.py` | 9 general design-lint rules, PASS / FAIL / **INDETERMINATE** | return a pass where it cannot measure |
| `inkmask.py` | separate the pixels an element PAINTED from the rectangle it occupies | fall back to the rectangle when its assumption fails — it returns a reason |
| `detect_xcheck.py` | fire only where the DOM's claim and the render disagree | opine on the vertical axis of a text glyph |
| `route.py` | abstentions → the vision layer's queue, cropped and captioned | ask the model anything with a number in the answer |
| `profiles.py` | per-app admission and order | produce a score, or assert a stack fact from prose |
| `score.py` | the false-positive budget and the rule-admission test | print a rate below n=16 clean pages |
| `report.py` | render a run under one app's profile | read a route plan built for a different app |

## The three things a reader should not have to re-derive

**An abstention is not a false positive, and the two are never summed.** A FAIL on
the control disqualifies a rule; an INDETERMINATE on the control is the rule
saying what it cannot see, which is the property this whole layer exists for.
`score.py` prints them as separate lines and gates on the first only.

**Zero on the control is a gate, not a rate.** It refutes a bad rule at n=1 and
certifies nothing. The rate stays withheld until `--clean-set` supplies 16 clean
pages, and that is enforced by the denominator rather than by discipline. The
corpus also censuses ~364 subject-checks per page against ~1,841 on a real route,
so the zero was measured at roughly 1/35th of the target's subject density.

**A per-app weighting is an admission and an order, never a multiplier.** The
landing app EXCLUDES conformance families because a token-drift finding on a
purchased template reports that the vendor's design system is not ours. The
management app puts them first and makes them ABSTAIN, because its Tailwind half
emits utilities from no declared token map — so the one app whose review *is*
conformance is the one that currently cannot produce a conformance verdict, and
weighting it up without that would have produced the most confident garbage in
the programme.

## Known state, and what would change it

- `xcheck-zero-ink` (X1) has **no fixture and has never caught anything**. It is
  reported NOT ADMITTED by the audit and left enabled; build its fixture the
  first time it finds something (B19b).
- **T1 is 12 crops on this corpus, not the 0 the spec records.** X2's honest
  vertical abstention created a real queue. Twelve questions of one class are not
  twelve questions — the per-page collapse and the fold hold them at one image
  each — but on a corpus of 13 near-identical pages they are also *the same*
  question thirteen times. A cross-page collapse is the fix and it waits on U3,
  because on real routes the pages differ and the saving may not exist.
- The rate, the mined clean corpus (B0), and every probe in §7 are unrun. The
  numbers here are about 13 pages of 47 elements each.
