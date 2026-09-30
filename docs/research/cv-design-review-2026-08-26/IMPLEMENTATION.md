# IMPLEMENTATION — the perception pipeline, built and measured

**Date:** 2026-08-29 · **Builds:** `README.md` §8 items 1 and 2, the X2 repair recorded in §2,
and the per-app weighting named in §8's closing paragraph.
**Scope (frozen):** abstention router · fix `detect_xcheck` X2 · re-run every rule against the
clean control as a false-positive budget · per-app rule weightings.
**Not in scope, and not reopened:** any local VLM, any specialist GUI-grounding model, any
VLM-as-quality-gate. The June 2026 campaign ratified taste-stays-human, §7 stands.

Everything below is a measurement taken by running the code in `bench/`, not an argument.

---

## The headline

| | Before | After |
|---|---|---|
| Abstentions reaching the model queue | undefined — no router existed | **2 of 2 resolved deterministically; 0 crop calls** |
| Model calls over the 13-page corpus | one per page, unrouted | **13** (one blind gestalt each), or **16** on the profile that abstains on tokens |
| X2 `clean` vs `optical-centering` | byte-identical finding | **0.2px right / 3.7px down** vs **1.8px left / 1.7px down** |
| X2 ink pixels on a 44px round button | ~340 (corners and rim) | **59** — the glyph, and nothing else |
| X3 on the gradient page, this host | **0 findings, silently** | **2 findings**, 6.15:1 → 1.73:1 and 6.00:1 → 1.71:1 |
| Control false positives, enabled rules | asserted in prose | **0**, asserted by a gate that exits 1 |

**One number is worth more than the rest.** `bench/corpus/out/findings_dom.json`, regenerated on a
Linux host with no Helvetica, is **byte-identical** to the file committed from the M1 Max. The
deterministic layer is host-invariant. Both pixel arms were not, and that is the whole story of
this round.

---

## 1. The abstention router — `bench/route.py`

The deterministic layer's most valuable output is an abstention, and until now nothing consumed
it. The router is the consumer, and it makes four decisions and no others.

1. **ASSERT.** A deterministic finding carries a number, so it is answered and never routed.
2. **SUBTRACT.** An abstention a cross-check arm *answered* leaves the queue. This is the whole
   economics: `xcheck-contrast-varies` settles contrast-over-a-gradient in NumPy, and takes the
   class out of the vision spend entirely.
3. **COLLAPSE.** What survives collapses by class, per page, into one crop request over the union
   of its target boxes. Five contrast abstentions in one hero are one question.
4. **FRAME.** Hierarchy, grouping and does-this-make-sense are page-global and structurally
   unreachable from a crop (`PIPELINE_SPEC` B17), so they get at most one blind whole-frame call.

Two contracts travel *with* the queue rather than living in a prompt file, because a prompt is
edited by whoever is in a hurry:

- every crop rect is a `getBoundingClientRect` union, padded and clamped. **No box a model drew
  can enter the queue**, because the queue has no field that could hold one.
- every routed item carries its own `prohibition` — *"do not report any number, distance, size,
  ratio or coordinate"*. The judge may not opine below the perceptual threshold and SCREEN may not
  opine above it, and the line that says so ships attached to the request.

There is **no code path from `judge_queue.<profile>.json` to a pass/fail verdict**. That is the mechanical
form of the June 2026 ruling, and `tests/design-review-router.bats` asserts it against the profile
file (no profile key may name a gate; `gestalt` may carry only `enabled` and `weight`).

### Measured, per profile, over the 13-page corpus

| profile | asserted | abstentions | resolved by cross-check | suppressed | crop calls | gestalt | model calls |
|---|---|---|---|---|---|---|---|
| `default` | 16 | 2 | **2** | 0 | **0** | 13 | **13** |
| `reso-landing-app` | 11 | 2 | **2** | **5** | **0** | 13 | **13** |
| `reso-management-app` | 13 | 5 | 2 | 0 | **3** | 13 | **16** |
| `reso-web-app` | 16 | 2 | **2** | 0 | **0** | 13 | **13** |

The `default`, landing and web rows are the claim the README made and could not yet show: **the
abstention set is small, and the cross-check empties it.** One model call per page, unchanged by
routing, and the gradient class never reaches a model.

The management row is the interesting one and it is not a regression — see §4.

---

## 2. The X2 repair — `bench/detect_xcheck.py`

Both defects the wave recorded are fixed, and each fix is checkable rather than asserted.

**(a) It measured against the element's own box.** `getBoundingClientRect` returns the
*post*-transform box, so a `translate` moved box and ink together and the offset was invariant
under the very compensation it was supposed to verify — `clean` and `optical-centering`, which
differ only by `transform: none`, produced the byte-identical finding. X2 now measures against the
**container that makes the centring claim**: the nearest ancestor whose computed style is
`display:flex|grid` with `align-items:center` and `justify-content:center`. No such ancestor means
there is no DOM claim to cross-check, and the rule abstains rather than emitting a bare pixel
statistic. The two pages now read `0.2px right / 3.7px down` and `1.8px left / 1.7px down`.

**(b) Its background was the crop's modal colour**, so on a round button the square crop's corners
counted as ink and swamped a 16px glyph. Ink is now (i) an analytic **rounded-rect mask** built
from the container's own `border-radius`, eroded by 1.5px to drop the antialiased rim, and (ii) a
test against the element's **declared** `color`. Ink falls from ~340 pixels to **59**, which is
exactly the triangle.

> The mask uses the clamped-distance form, not four corner circles. With `radius == w/2 == h/2` —
> the circle case X2 exists for — the four corner centres **collide**, and a per-corner
> formulation silently leaves half the shape unmasked. The first version of this fix had that bug
> and it presented as "the mask works" plus a centroid that would not move.

### The third defect, which the repair exposed — and why X2 still ships off

With the quantity finally correct, the control does not read zero. The corpus's optical
compensation is `translate(2px, 2px)`, hand-measured on macOS/Helvetica. On a host substituting
Liberation Sans, the glyph's ink sits **3.3px** left of its own box centre and is **vertically
centred**, so the true compensation is ~3.3px horizontal and ~0 vertical. The `clean` page
therefore carries a real ~2.4px optical error of its own, and any absolute threshold separating it
from the injected defect is a constant tuned to one machine's font stack.

Measured cost, with `--x2`: the arm fires on **13 of 13 pages, the control included**. It stays
off. `fp_budget.py` prints that as a number so the decision is re-derivable rather than
remembered.

**This is the README's own §1 lesson recurring**: a control is not clean until something disagrees
with it. There, three real WCAG failures were sitting in a hand-authored baseline. Here, a
hand-measured optical constant is wrong on any host without the font it was measured on. What
would revive X2 is a reference render to diff against — which makes it a VRT-shaped check with a
per-render baseline, not a standalone rule with a constant.

---

## 3. X3 was passing for the wrong reason, and this host proved it

**The number in README §2 — `4.81:1` at the left edge and `1.57:1` at the right — does not
reproduce.** On this host the arm returned **nothing at all**, silently, on the one page it was
built for.

The cause is a one-line assumption with no fallback. X3 sampled the backdrop as the **modal
colour** of each third of the text's crop. On a gradient the backdrop is a thousand colours
appearing a few times each, while the text is **one exact colour repeated** — so the modal colour
of the left third was the *text*, the arm computed `contrast(white, white) = 1.0` against
`1.26` on the right, and 0.26 fell under the 1.5-point threshold. It only ever fired because
Helvetica's antialiasing happened to leave fewer exactly-white pixels than the widest gradient
band; Liberation Sans does not, and the arm went quiet **with no error and no abstention**.

The fix is the same primitive as X2(b): the backdrop is the **median of the pixels that are not
this element's declared ink**. Both halves matter — excluding ink stops the text voting on its own
backdrop, and the median rather than the mode is what a gradient has. Now, on this host:

| page | left | right | verdict |
|---|---|---|---|
| `clean` (solid `blue700` hero) | 6.70:1 | 6.70:1 | quiet — delta 0 |
| `contrast-on-gradient`, hero title | **6.15:1** | **1.73:1** | fires |
| `contrast-on-gradient`, hero caption | **6.00:1** | **1.71:1** | fires |
| the other 11 pages | — | — | quiet |

The `6.70:1` on the control is a free cross-validation: it is exactly the figure README §1 records
for white on `blue-700` after the baseline was repaired.

**The generalisable finding, which is worth more than the arm:** a detector whose verdict turns on
the host's font stack is not measuring the page, and this one failed *silently* — no exception, no
abstention, a clean green run. That is the fail-safe-default-mimics-the-healthy-state trap the
README warns about in the `blendedBackgroundColors` case, arriving from a direction nobody was
watching. Any pixel arm added later needs a second host before its number is quotable.

---

## 4. Per-app rule weightings — `bench/profiles.json`

One review harness, three different problems. The weighting file makes that a data edit rather
than a fork.

| | `reso-landing-app` | `reso-management-app` | `reso-web-app` |
|---|---|---|---|
| stack | Next 14, purchased template | Next 16, React 19, Tailwind 4 | Next 13 |
| the problem | marketing aesthetics | design-system conformance | between |
| `token-drift`, `grid-violation` | **0.0 — suppressed** | 1.0 | 0.6 |
| `type-scale` | 0.3 | 1.0 | 0.6 |
| WCAG rules (`contrast`, `overflow`, `touch-target`) | 1.0 | 1.0 | 1.0 |
| `gestalt` | 1.0 | 0.4 | 0.7 |
| `tokens_authoritative` | true | **false** | true |

**Weight semantics, and the one direction a weight may not move.** `0.0` suppresses — the rule does
not appear in that app's report at all, reserved for findings that are structurally unactionable
there. Token drift inside a template nobody on the team authored is a true statement and a dead
letter, and *a re-reported true finding spends the same credibility as a wrong one*. `0 < w < 1`
demotes one severity rung. **A weight may lower a severity and may never raise one** — the rule
that measured the defect stays the authority on how bad it is; a profile only says how much this
app intends to act on it. Without that asymmetry the file becomes a second, un-measured severity
model competing with the first, and `tests/design-review-router.bats` red-proves it.

**`tokens_authoritative: false` is not a preference.** `PIPELINE_SPEC` §1.0 rules that token
conformance must **abstain rather than FAIL** wherever the winning declaration came from the
token-map-less Tailwind engine, and Tailwind 4 ships no token map. Setting it false demotes
`token-drift` from an assertion to an abstention, so it routes to the judge instead of failing —
which is the 3 crop calls in the management row of §1's table. **That is the mechanism working,
not a regression:** the management app trades three deterministic assertions it has no palette to
justify for three cropped questions it can actually answer, and the alternative was asserting
non-conformance against a palette the rule cannot see.

The landing row's 5 suppressed findings are the same mechanism from the other side — five true
statements that app will never act on, removed before they cost credibility.

---

## 5. The false-positive budget — `bench/fp_budget.py`

~20% FP is where an AI reviewer loses credibility regardless of catch rate, and the wave's two
zero-FP runs are the baseline to defend. Defending it needed a mechanism: the rule was written as
prose — *"every rule added must be re-run against the clean control before it ships"* — and prose
does not run.

```
FALSE-POSITIVE BUDGET   control = clean.html, 47 elements; corpus = 13 pages
rule                       dflt ctrl FP on-tgt off-tgt  verdict
contrast                     on       0      2       0  ships
contrast-indeterminate       on       0      1       1  ships
grid-violation               on       0      2       0  ships
misalignment                 on       0      1       0  ships
overflow                     on       0      3       0  ships
spacing-rhythm               on       0      1       0  ships
token-drift                  on       0      3       0  ships
touch-target                 on       0      1       0  ships
type-scale                   on       0      1       0  ships
xcheck-contrast-varies       on       0      1       1  ships
xcheck-optical-centre       off       1      2       1  stays off -- fires on 13/13 pages

enabled rules: 0 control finding(s) over 47 elements on 1 control page
= 0.0% of subject-checks, against the ~20% credibility cliff
verdict: CLEAN
```

Three properties, each a repair of something the wave got wrong once:

- **The control run is the gate.** Any enabled rule with a control finding exits 1.
- **A rule cannot ship unbudgeted.** `BUDGETED` is a registry; a rule name appearing in output
  without an entry exits 1 naming itself. Adding a rule and forgetting to measure it is now a red
  run rather than a silent widening of exposure. Red-proved by injecting a rule name.
- **The denominator is printed beside every rate.** The wave's own FP bound was computed on the
  wrong denominator (3/8 = 37.5%, not 3/13 = 23.1%) and the error was invisible because no
  denominator sat next to it.

**The off-target column is reported and deliberately does not gate.** A finding on an element the
variant did not touch is a false-positive *candidate*: injecting `#EFF6FF` on a button really does
create a real contrast failure on that button, and the rule reporting it is right. Both current
off-target entries are the `hero-title`, which sits on the same injected gradient as the
`hero-caption` the manifest names — correct findings on an element the manifest did not list.
Scoring those automatically would either credit noise or convict a correct detector, so they are
named for a human instead of counted by a machine.

**The control-subtraction key spans the claim, not just its location.** `detect_xcheck`'s reporting
still deduplicated on `(rule, target)`, which is the exact bug README §1 records — and it bit here:
under that key X2's finding on `optical-centering` is indistinguishable from its finding on the
control, because only the *number* differs. Both `fp_budget.py` and `detect_xcheck.py` now key on
`(rule, target, detail)`.

---

## 6. What runs, and how

```
cd bench
python3 -m venv .venv && .venv/bin/pip install numpy pillow playwright   # once
.venv/bin/python corpus/build_corpus.py corpus/out                        # 13 pages
.venv/bin/python capture.py corpus/out                                    # shots + snapshots
.venv/bin/python detect_dom.py corpus/out                                 # 9 rules
.venv/bin/python detect_xcheck.py corpus/out                              # X1 + X3 (add --x2)
.venv/bin/python fp_budget.py corpus/out                                  # the gate; exits 1 on breach
.venv/bin/python route.py corpus/out --profile reso-management-app        # -> judge_queue.<profile>.json
```

`capture.py` takes `BENCH_CHROMIUM=/path/to/chrome` to use an already-installed binary instead of
Playwright's `chromium` channel. That seam is what made §3 findable at all: a false-positive budget
nobody else can re-run is a claim, not a measurement, and the second host is what exposed both
pixel arms.

`route.py --selftest` needs **no** numpy, no Pillow and no browser — it is stdlib-only on purpose,
because the stage that decides what earns a model call is the stage whose mistakes cost money, and
a gate that has to provision a perception stack in order to check anything is a gate that gets
skipped. `tests/design-review-router.bats` runs it, plus three mutation checks that break a law and
assert the selftest goes red. A green selftest over an un-mutated file only says the file agrees
with itself.

---

## 7. What this did not touch

- **No local VLM, no GUI specialist, no VLM-as-gate.** §3, §5 and §7 stand unamended.
- **`bench/bench_local_vlm.py` and `local_vlm_results.json`** are untouched; they are the
  measurement that closed that question and re-running them changes nothing.
- **The north-star taste yardstick** promised by the June campaign is still absent. It remains the
  open gap README §7 names, and no code here substitutes for it.
- **B0, the mined clean corpus** (`PIPELINE_SPEC` §6 Tier 0) is not built. It is the ship gate for
  the spine and the denominator every FP claim wants; `fp_budget.py` is built to take it as its
  corpus directory unchanged, so B0 is a corpus to point it at rather than a rewrite.
