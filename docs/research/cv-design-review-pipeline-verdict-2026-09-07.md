# Verdict: the design-review perception pipeline was already built

**Date:** 2026-09-07 · **Row:** `cc-backlog badb132df232` · **Verdict:** CURED ON TRUNK — no code work
performed, none needed.
**Subject:** `docs/research/cv-design-review-2026-08-26/README.md` § 8 "What to build".

The row asked for four things. All four landed on 2026-09-04, three days before the row was
dispatched, and the row's own DoD reference already records them in its § 8.1 "As built". This
document is the independent check that § 8.1 is true, because a research record asserting its own
completion is exactly the claim § 7 of that README says gets believed and should not be.

## The four asks, and the commit that closed each

Every sha below returns exit 0 from `git merge-base --is-ancestor <sha> origin/main`.

| Ask, as the row worded it | Cure | What it contains |
|---|---|---|
| abstention router — deterministic pass first, its INDETERMINATE set becomes the cropped VLM queue | `c811b9415a93` | `bench/route.py` (449 lines) |
| fix `detect_xcheck` X2 — measure against the container, mask to the painted shape | `77d2b0b4b00e` | `bench/inkmask.py` (new, 172 lines) + `bench/detect_xcheck.py` rewrite |
| re-run every new rule against the clean control as a false-positive budget | `9a11c84feeef` | `bench/score.py` (483 lines), the gate that exits non-zero |
| per-app rule weightings (landing = marketing aesthetics, management = design-system conformance) | `c811b9415a93` | `bench/profiles.py` (284 lines) + `bench/report.py` |

Both X2 defects the README named as "known, and neither is done" are fixed in `77d2b0b4b00e`, by the
two mechanisms the row specified: the offset is measured against the **container's** centre rather
than the element's own post-transform box, and the ink is taken from a **painted-shape mask**
(`inkmask.py`) rather than the square crop's modal colour.

## What was actually run

Clean checkout at `origin/main`, `pip install numpy pillow playwright`, then the seven commands in
`bench/README.md` verbatim, into a scratch output directory:

```
corpus/build_corpus.py → capture.py → detect_dom.py → detect_xcheck.py → route.py → score.py → report.py
```

Results:

- **`detect_dom.py`** — control `clean.html` → 0 findings. All 9 DOM-determined defects caught.
- **`detect_xcheck.py`** — control → 0 FAIL, 1 abstention (the vertical axis, by name). X2 fires on
  `optical-centering` at **−2.00 px against a 1.25 px derived band**, and is silent on the control.
  That is the fix working: the old arm reported 1.2/2.2 px left *identically on all thirteen pages*.
- **`score.py`** — `✓ GATE PASSED`, exit 0: 0 control findings, 0 population drift, 0 dead mutants,
  **11/11 screenable defects caught, 0 missed**. It still reports `xcheck-zero-ink` as NOT ADMITTED
  (no fixture, has never caught anything) and still **withholds the FP rate** at n=1 clean page — both
  are the designed behaviour, not failures.
- **`report.py`** — `reso-management-app` renders `[design-system-conformance]` and puts family K
  first *while forcing it to ABSTAIN* ("engine-has-no-token-source"); `reso-landing-app` renders
  `[marketing-aesthetics]` and **EXCLUDES** families K and G with the reason carried into the report.
  The two named apps are weighted the two ways the row asked for.

`findings_dom.json`, `findings_xcheck.json` and `route-plan.json` from this run are **byte-identical**
to the copies committed on trunk.

## The out-of-scope constraints held in the shipped code

The row forbade a local VLM, a specialist GUI-grounding model, and any VLM-as-quality-gate. Checked
rather than assumed: `route.py`, `score.py`, `report.py`, `profiles.py`, `detect_dom.py`,
`detect_xcheck.py` and `inkmask.py` contain **zero** references to `mlx`, `torch`, `transformers`, any
provider SDK, or any HTTP client. `score.py` contains no reference to vision at all — the gate is
purely deterministic, and the router emits a *queue* for a human-adjudicated call, never a verdict.
The June 2026 "taste stays human" ratification is intact.

## Two limits on this verification, stated so nobody inherits them as stronger

**This is a clean-checkout re-run, not a third-machine reproduction.** The `run.json` committed on
trunk and the one this run produced name the *same* environment class — Linux x86_64, Chromium
`141.0.7390.37`, the same `/opt/pw-browsers/chromium-1194` executable, same viewport, same resolved
font metric (239.15 px). Byte-identity across two runs of the same image is a reproducibility result,
not a portability one. The genuinely different machine is the README's M1 Max, whose X3 pair reads
4.81/1.57 where both Linux runs read 6.15/1.76 — same verdicts, different numbers, exactly as
`bench/README.md` warns. What this run establishes is that the pipeline rebuilds and passes its own
gate from nothing but the repo and three pip packages.

**"Still unbuilt" in § 8.1 is not this row's scope.** Order-randomised comparison, motion,
saliency, and B0 (the mined clean corpus that would convert the FP bound into a measurement) are
items 3–5 of the README's build list. This row named items 1, 2, the X2 fix and the weightings. Those
are done; the others were never in it, and this verdict does not close them.

## Dispatcher vintage

`bin/cc-dispatch` at `origin/main` is blob `98ab38f51f7ac82a043e522d3a9601ff9f460528` — **equal** to
the bytes that composed this brief. The dispatcher that fired this row is trunk, so no landed-is-not-
live gap applies to the dispatch path here.

## Why the row was open at all

Not a stale-tree artifact — the checkout was at trunk (`HEAD..origin/main` = 0) before any read. The
cures landed 2026-09-04 and the row was simply never closed against them. The lesson is the cheap
one: § 8.1 was written *in* the cure commits' own document, so the row's DoD reference already
contained its own answer, and three days of dispatch eligibility passed without anything reading it.
