# `bench/` — the design-review perception pipeline, and the instrument that grades it

Substrate: [`docs/research/cv-design-review-2026-08-26/`](../docs/research/cv-design-review-2026-08-26/README.md)
· contracts: `PIPELINE_SPEC.md` §1.4 (SCREEN), §1.5 (ROUTE), §2 C7 (collapse), §2 C18 (the FP gate).

**What this is for:** answering every design question that has a number in the answer, exactly and
for free, so the only thing a model is ever asked is the residue — and making that residue small,
cropped, and honest about what it could not answer.

**What it is not for, and this is settled:** no local VLM in the detection path, no specialist
GUI-grounding model, and no VLM as a quality gate. The June 2026 campaign ratified *taste stays
human; gates adjudicate correctness and coverage only*, and nothing here reopens it. `route.py`
produces a queue and a coverage deficit. It never scores, never ranks a design, and never gates.

---

## Run it

```bash
cd bench
pip install numpy pillow playwright          # once

python3 corpus/build_corpus.py corpus/out    # 13 pages: 1 control + 12 one-defect variants
python3 capture.py corpus/out --dpr 1,2      # one browser pass -> shots/ + snapshots/
python3 detect_dom.py   corpus/out           # the deterministic rules  -> findings_dom.json
python3 detect_xcheck.py corpus/out          # the DOM-vs-pixels comparator -> findings_xcheck.json
python3 fp_budget.py    corpus/out           # THE SHIP GATE. exit 1 = a rule fired on a clean page
python3 route.py corpus/out --profile reso-management
```

On a machine whose Chromium is pinned outside Playwright's own store (a CI image, a sandbox), pass
`--browser /path/to/chrome` to `capture.py` or set `$DR_CHROMIUM`.

`bats tests/design-review-perception.bats` runs the acceptance tests, including the negative
controls. They skip rather than fail when numpy/pillow are absent or the corpus is uncaptured — a
red for a missing dependency claims the rules are broken when nothing has been measured at all.

---

## The layers, and the one rule that keeps them apart

| Layer | File | Answers | Never ask it |
|---|---|---|---|
| Computed styles / box model | `detect_dom.py` | every question with a number in the answer | whether it looks good |
| DOM-vs-pixels comparator | `detect_xcheck.py` | only where the two descriptions **disagree** | anything either layer already settles |
| Pixels (a frontier VLM) | `route.py` builds its queue | hierarchy, gestalt, "does this make sense" | **any number** |

**The grounder supplies identity; the DOM supplies geometry.** A model-drawn box is an estimate of
something `getBoundingClientRect()` returns exactly, for free, with no hallucination risk. No
distance is ever computed from a box a model drew, and `route.py` enforces the corollary in code:
`_assert_no_numbers` raises rather than shipping a question whose answer is a number.

### The seam: an abstention is the deliverable, not a gap

`detect_dom.py`'s most valuable output is `contrast-indeterminate` — *"cannot compute a ratio,
backdrop is an image/gradient; 4.5:1 is UNVERIFIED for this text"*. Every silent pass that should
have been an abstention is a defect shipped. The abstention set is exactly the vision layer's job
queue, and collapsing it by class is what makes that queue affordable.

`type-scale-indeterminate` is the second one, and it exists because an app with no declared type
scale cannot be judged conformant *or* drifted. Abstaining is the honest answer; a confident FAIL
whose truth value depends on which resolver ran is worse than silence.

---

## `route.py` — the abstention router

Three triggers, and only three.

| | Trigger | On this corpus |
|---|---|---|
| **T1** | every `*-indeterminate`, **minus** what the cross-check resolved, **collapsed by `(rule, cause)`** | **0** — both abstentions are resolved deterministically |
| **T2** | the unscreenable classes the profile names, once per page, **never cut for budget** | 1–6 per page, by profile |
| **T3** | an explicit `--ask`, budget-exempt | 0 |

🚨 **The T1 subtraction is gated on `findings_xcheck.json` EXISTING, and T1 *grows* when it is
absent.** An empty resolution file resolves nothing and looks exactly like nothing needing
resolution — a silent, confident, smaller queue is the worst available response to a layer outage.
This is pinned by a test.

Crops come from the **archived master**, never a fresh render: a second browser pass photographs a
different frame, and a crop from a different frame cannot be argued against the snapshot beside it.
Each is clamped to the read envelope (`w,h ≤ 2000` ∧ `⌈w/28⌉·⌈h/28⌉ ≤ 4784` ∧ `≤ 3.75 MiB`) and
carries a caption stating its region label, its `eff`, and its own prohibitions — because a judge
that is not told its image cannot support a verdict will answer anyway.

Every page's plan carries `coverage: {abstentions, resolved_by_xcheck, abstention_classes,
adjudicated, unadjudicated_by_budget, forwarded_as_fact}`. **An unanswered question must be visible
as unanswered, not absent.**

---

## `fp_budget.py` — the ship gate

~20% false positives is where an AI reviewer loses credibility regardless of catch rate. Three
claims, kept separate on purpose:

1. **Absolute zero on the control is the gate**, enforceable at n = 1, run **unweighted**. A rule
   that fires on a page with no defect will fire on every page. The tool also asserts that no
   profile weights any rule to zero — a per-app knob that can hide a control hit is a knob for
   hiding evidence.
2. **No false-positive *rate* below n = 16 clean pages.** By the rule of three, 0 findings over n
   pages bounds the rate at 3/n: 300% at n=1, 37.5% at n=8 — nearly twice the cliff. 3/16 = 18.75%
   is the first n strictly under it. Below 16 the tool prints the **deficit** and refuses the rate.
3. **State the budget per 1,000 subject-checks**, never per run. One real page carries ~1,841
   subjects against this corpus's ~47; a per-run zero says little about a 105-route audit.

**Run this before shipping any new rule.** It is the only thing that decides whether one ships.

---

## `profiles.json` — one harness, three questions

`reso-landing-app` is a purchased marketing template; `reso-management-app` is an internal dashboard
on our own design system. Same rules, different weights, because a token-drift finding is
actionable in one and resolves to *"the vendor chose that"* in the other.

| | `reso-landing` | `reso-management` | `reso-web` |
|---|---|---|---|
| kind | marketing aesthetics | design-system conformance | mixed |
| `token-drift` | **0.15** (advisory) | **1.0** | 0.6 |
| `grid-violation` | **0.15** (advisory) | 0.9 | 0.5 |
| contrast · overflow · touch-target | 1.0 | 1.0 | 1.0 |
| T2 classes | hierarchy, gestalt, readability, semantic-coherence | content-fit, semantic-coherence | hierarchy, content-fit, semantic-coherence |
| image budget | 2 | 1 | 2 |

A weight may **rank** the report and **demote** a finding to `advisory`. It may never **suppress**
one, and it never touches the FP gate. `stack` is `null` in every profile by design: framework
versions are generated by a live `dr surface` read, and the spec's own worked example is a table
that banned prose as a source and then published three unmeasured cells in the fix.

---

## What the corpus grades, and what corrected it

`corpus/build_corpus.py` renders one dashboard thirteen ways — a clean control plus twelve variants,
each carrying exactly one defect at a known location with a known magnitude. Nine are fully
determined by the DOM; three are invisible to it by construction.

**A corpus needs its own control run before it is allowed to grade anything.** Corpus 1.1 exists
because two of its ground truths were false of the render:

- **`optical-centering`** compensated a U+25B6 font glyph by `translate(2px, 2px)`, a pair of
  numbers measured off one macOS font stack. Re-measured on Linux/DejaVu the vertical half was
  inverted: the *control* sat 3.48px below its container's centre against the *variant's* 1.48px.
  The mark is now a `clip-path` triangle whose centroid is derivable (`w/6` = exactly 2px) and
  identical on every platform.
- **`contrast-on-gradient`** put a white caption on a gradient — and the caption's glyphs occupied
  columns 2..299 of an 1168px box, entirely inside the gradient's dark end, at 10.4:1 falling to
  ~7:1. It **passed everywhere a reader looks**. The defect existed only in box pixels no glyph
  occupies. The caption is now right-aligned, and the magnitude states what is true of the text.

Both are the same failure the substrate is built to warn about: *a plausible number nobody checked.*
