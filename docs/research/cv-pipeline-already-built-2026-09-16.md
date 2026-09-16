# The design-review perception pipeline was already built — verdict on cc-backlog `badb132df232`

**Date:** 2026-09-16 · **Verdict:** ALREADY CURED, landed 2026-09-04 · **Disposition:** close on the
shas below, no new code
**Measured on:** an Anthropic cloud VM (Linux x86_64, Chromium 141.0.7390.37) — a *third* machine,
which is what makes the reproduction below worth more than a re-read.

---

## The claim

The item asked for four things:

1. an **abstention router** — deterministic pass first, its `INDETERMINATE` set becoming the cropped
   VLM queue;
2. a **fix for `detect_xcheck` X2** — measure against the container, mask to the painted shape;
3. **every new rule re-run against the clean control** as a false-positive budget;
4. **per-app rule weightings** — `reso-landing-app` = marketing aesthetics, `reso-management-app` =
   design-system conformance.

All four landed on 2026-09-04, twelve days before this item was dispatched. Nothing here is new work.

## The cure, by sha

Each asserted with `git merge-base --is-ancestor <sha> origin/main` (all exit 0):

| Sha | Landed | What it carries | Scope item |
|---|---|---|---|
| `77d2b0b4b00e2e71c3c4a81e4e2e47f6bc03231f` | 2026-09-04T17:53Z | `fix(xcheck): both broken arms measured a rectangle where the element painted a shape` — adds `bench/inkmask.py` | **2** |
| `c811b9415a9319b02668031853be407c5b177655` | 2026-09-04T18:00Z | `feat(bench): the abstention router, and what it refuses to ask` — adds `bench/route.py`, `bench/profiles.py` | **1**, **4** |
| `9a11c84feeef182beafda270e78a0de3a0e3d7f6` | 2026-09-04T18:05Z | `feat(bench): the false-positive budget, as a gate that can fail` — adds `bench/score.py` | **3** |

The DoD ref's own § 8.1 (*"As built — 2026-09-04"*) is the record: *"Items 1 and 2 of the list above
are built, X2 is fixed and on, and the weightings exist."* The item was filed against the state of
that README **before** § 8.1 was appended, and nothing closed it afterwards.

**Dispatcher vintage:** `git rev-parse origin/main:bin/cc-dispatch` =
`27c461a5f1a4de551fdfbe2a619e28e696c13aaa` = the blob that composed this brief. **EQUAL** — the
dispatcher that fired is trunk, so this is not a landed-but-not-live discrepancy. The row is simply
stale.

## Why a re-read was not enough, and what was run instead

A README asserting its own completion is the weakest possible evidence, and this repo's corpus is
full of premises that were true when written and false later. So the pipeline was **executed
end-to-end** on a machine that has never run it, and every number the documents claim was checked
against what came out.

```
python3 corpus/build_corpus.py  OUT   # 13 pages: 1 control + 9 DOM + 3 pixels-only
BENCH_CHROMIUM=... python3 capture.py OUT
python3 detect_dom.py    OUT
python3 detect_xcheck.py OUT
python3 route.py         OUT --emit-crops
python3 score.py         OUT          # the gate
python3 report.py        OUT --app <each of the three>
```

### Every documented figure reproduced

| Claim in the record | Measured here | |
|---|---|---|
| X2 control offset `0.00 px` | control page: **0 FAIL** from `xcheck-optical-centre` | ✓ |
| X2 defect `−2.00 px`, band `1.25 px` | `ink mass sits 2.00px left of the container's centre (band 1.25px)` | ✓ |
| X2 vertical abstains at `+3.23 px` on the control | `vertical ink offset is +3.23px … this mark is a text glyph` → `INDETERMINATE` | ✓ |
| X3 gradient `6.15:1 / 1.76:1` (the second-machine numbers) | `6.15:1 … 1.76:1` | ✓ |
| T1 queue = **12 crops over 13 pages** | `12 T1 crop(s) + 13 T2 gestalt call(s)` | ✓ |
| `11/11` screenable defects caught, 0 missed | `11/11 screenable defects caught, 0 missed` | ✓ |
| 0 findings on the control | `0 FAIL on clean.html ✓` | ✓ |
| `xcheck-zero-ink` reported NOT ADMITTED | `⚠️ NO FIXTURE — not admitted by §1.4` | ✓ |
| The rate is withheld below n=16 | `rate: WITHHELD. n=1 clean page(s)` | ✓ |

That the X3 pair landed on the *second-machine* values (6.15/1.76) rather than the first-machine ones
(4.81/1.57) is itself a small confirmation: `bench/README.md` warns that *"every pixel number here is
a number about one render"*, and a third machine agreeing with the second on the verdict while the
first differs on the digits is exactly the behaviour it predicts.

### The gate was falsified, not just observed passing

A gate that has only ever been seen green certifies nothing — the run above could be a gate that
cannot fail. Both arms were therefore run, one variable:

| Arm | `findings_dom.json` | Result |
|---|---|---|
| **control** | as captured | `✓ GATE PASSED — 0 control finding(s)`, **rc 0** |
| **reddened** | one `contrast` FAIL cloned onto `clean` | `⛔ GATE FAILED — 1 control finding(s)`, **rc 1**, and it names the rule: `contrast … ⛔ fires on the control` |

The red arm also proves the attribution works: the gate does not merely count, it points at the rule
that fired. (`score.py`'s rc was read via `${PIPESTATUS[0]}`, not `$?` after a pipe.)

### The per-app weightings actually differentiate

Not a config file that parses — three visibly different reviews off one run:

- **`reso-landing-app`** `[marketing-aesthetics]` — `EXCLUDE` on families K and G. Its report has no
  `align-1px` and no `grid-offgrid` section at all, because a grid violation on a purchased template
  reports the vendor's decision, not ours.
- **`reso-management-app`** `[design-system-conformance]` — K weighted first *and* forced to
  `ABSTAIN`, carrying the measured reason (`engine-has-no-token-source`: Tailwind 4 emitting
  utilities from no declared token map). The app whose review *is* conformance is the one that
  cannot currently produce a conformance verdict, and the profile says so in the report rather than
  producing confident garbage.
- **`reso-web-app`** `[mixed]` — K abstains for a different measured reason
  (`class-names-not-invertible`: Chakra/Emotion runtime `css-<hash>` names).

No score, no rank, no multiplier anywhere — `profiles.py:237` sorts *"by consequence, then by
severity, then stably by subject. No sum, no score"*.

### The out-of-scope exclusions hold by construction

The item forbade any local VLM, any specialist GUI-grounding model, and any VLM-as-quality-gate (the
June 2026 *taste-stays-human* ratification). The check that settles it is the **import set** of the
seven shipped pipeline files (`route.py`, `profiles.py`, `score.py`, `detect_dom.py`,
`detect_xcheck.py`, `inkmask.py`, `report.py`), because a module that cannot reach the network
cannot call a model:

```
argparse  collections  json  math  pathlib  re  sys      (stdlib)
numpy  PIL.Image                                          (arrays and pixels)
profiles  inkmask                                         (local)
```

No HTTP client, no vendor SDK, no `mlx`. (A keyword grep for
`anthropic|openai|mlx|requests\.|http|api_key|client(` returns exactly one hit, and it is the English
word "requests" inside a comment at `route.py:351` describing the image ledger *"for whoever
assembles the requests"* — i.e. the pipeline hands a plan to a caller and does not make the call
itself. Stated as "zero hits" this would have been a claim slightly stronger than the measurement,
which is the habit this whole document is about.)

The pipeline decides what a model should be asked and never asks it. `bench_local_vlm.py` is the
2026-08-26 measurement harness that produced the *reject* verdict on local models; it is not on any
review path.

## What is genuinely still open — and is not this item

The record is explicit about its own residue, and none of it falls inside this item's frozen scope:

- **B0, the mined clean corpus.** This is the one that matters: it converts the false-positive claim
  from a *bound* into a *rate*. `score.py --clean-set` is the socket and the rate unlocks itself at
  n ≥ 16 with no code change. The gate's own output names it.
- Order-randomised comparison (§8 item 3), motion via `getComputedTiming()` (item 4), and saliency
  (item 5, blocked on the UMSI++ licence question).
- `xcheck-zero-ink` has no fixture and has never caught anything; it is left enabled and reported
  NOT ADMITTED, which is the honest state.
- The cross-page collapse of T1 (12 crops that are really one question thirteen times) waits on U3,
  because on real routes the pages differ and the saving may not exist.

Each deserves its own row. Re-deriving any of them under this item would have been the failure the
brief warns about.

## The lesson worth keeping

**A work item's referent can be discharged by a sibling's land, and nothing will close the row.**
The cure here is twelve days older than the dispatch, sits under the exact paths the item names, and
is documented in the very file the item cites as its DoD — and the row still fired a cloud VM at it.
The cheap probe that settles this class in under a minute, before any code is written, is
`git log --oneline --format='%h %ad %s' --date=short -- <the paths the item names> | tail`: three
commits dated *before the item was dispatched*, whose subject lines are the item's own scope
sentences, is a closed row that nobody closed.

The second half is that reading the README would have been enough to *believe* this and not enough
to *report* it. Running the pipeline is what turned "the document says it is built" into thirteen
reproduced figures and a gate falsified in both directions — and it cost one `pip install` and about
four minutes of wall clock.
