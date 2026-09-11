# The design-review perception pipeline was already built — verified by running it

**Date:** 2026-09-11 · **Machine:** cloud VM, Linux x86_64, Chromium 141.0.7390.37
**Row:** cc-backlog `badb132df232` — *"Build the design-review perception pipeline from the
cv-design-review-2026-08-26 findings: abstention router, fix detect_xcheck X2, re-run every new rule
against the clean control as a false-positive budget, and per-app rule weightings."*
**Verdict:** **ALREADY CURED.** All four scope items landed 2026-09-04, seven days before this row
was dispatched. Nothing was re-derived and no code was written.

---

## 1. The cure, asserted against trunk

Three commits, each `git merge-base --is-ancestor <sha> origin/main` → rc 0 (re-run to confirm):

| Cure sha | Date | Subject | Scope item it discharges |
|---|---|---|---|
| `c811b9415a9319b02668031853be407c5b177655` | 2026-09-04 | feat(bench): the abstention router, and what it refuses to ask | 1 (router) + 4 (per-app weightings) |
| `77d2b0b4b00e2e71c3c4a81e4e2e47f6bc03231f` | 2026-09-04 | fix(xcheck): both broken arms measured a rectangle where the element painted a shape | 2 (detect_xcheck X2) |
| `9a11c84feeef182beafda270e78a0de3a0e3d7f6` | 2026-09-04 | feat(bench): the false-positive budget, as a gate that can fail | 3 (FP budget vs the clean control) |

Trunk head at verification: `4d7a65d7`. This worktree was **0 commits behind `origin/main`**, so every
number below is a number about trunk itself, not about a stale tree.

**The item's own DoD ref already said so.** `docs/research/cv-design-review-2026-08-26/README.md`
§ 8.1 *"As built — 2026-09-04"* states items 1 and 2 of its build list are built, X2 is fixed and ON,
and the weightings exist. The row was filed against the § 8 **To add** list without reading the § 8.1
section directly beneath it that retires four of its five entries.

## 2. Files existing is not the deliverable — so I ran it

Per *cause refuted ≠ effect discharged*, the effect here is a working pipeline, and ancestry of a sha
does not measure that. The full run, end to end, on this machine:

```bash
pip install numpy pillow playwright
cd bench
python3 corpus/build_corpus.py  "$OUT"          # 13 pages: 1 control + 12 defects
BENCH_CHROMIUM=/opt/pw-browsers/chromium-1194/chrome-linux/chrome \
  python3 capture.py            "$OUT"          # 13 pages x 2 dpr, mean 194 ms/page
python3 detect_dom.py           "$OUT"
python3 detect_xcheck.py        "$OUT"
python3 route.py                "$OUT" --emit-crops
python3 score.py                "$OUT"          # THE GATE
python3 report.py               "$OUT" --app reso-management-app
```

`BENCH_CHROMIUM` was required and is the documented escape hatch: the pinned Playwright wants
`chromium-1234`, this image ships `chromium-1194`. The bench's own README names the variable, so this
is the hatch working, not a defect.

### Scope item → the measurement that discharges it

| # | Scope item | Measured on trunk, this machine |
|---|---|---|
| 1 | **Abstention router** — deterministic pass first, its INDETERMINATE set becomes the cropped VLM queue | `route.py` emits **12 T1 crops + 13 T2 gestalt calls over 13 pages**, 44,145 visual tokens on the API path. Matches the README's documented "12 crops on this corpus" exactly. The control still costs the unconditional call and the router says so. |
| 2 | **Fix detect_xcheck X2** — measure against the container, mask to the painted shape | Both fixes present at `detect_xcheck.py:29-35`, the container-relative arm at `:208-211`, the mask via `inkmask.painted_shape`. Measured: **control 0 FAIL, defect −2.00 px against a 1.25 px band derived from the capture** — the § 8.1 numbers to the digit. The old arm's signature defect (1.2/2.2 px reported *identically on control and defect*) is gone. The vertical axis abstains by name (+3.23 px is a font fact) rather than reporting it as a defect. |
| 3 | **Re-run every new rule against the clean control as an FP budget** | `score.py` → **✓ GATE PASSED**, exit 0. 0 control findings, 0 population drift, 0 dead mutants, 4,732 subject-checks across 13 rules. **11/11 screenable defects caught, 0 missed.** The rate is correctly **WITHHELD** at n=1 clean page (C18 ruling 2), i.e. the denominator enforces it rather than discipline. |
| 4 | **Per-app rule weightings** | `reso-landing-app` renders as **`[marketing-aesthetics]`**, EXCLUDING families K and G with the reason carried into the report ("a drift finding here reports that someone else's design system is not ours"). `reso-management-app` renders as **`[design-system-conformance]`**, putting K first *and* forcing it to ABSTAIN on `engine-has-no-token-source`. `reso-web-app` is `[mixed]`. A weighting is an admission and an order; no multiplier, no score. |

### The out-of-scope constraint holds

The row forbids any local VLM, specialist GUI-grounding model, or VLM-as-quality-gate (the June 2026
*taste-stays-human* ratification). Grepping the shipped pipeline —
`route.py score.py profiles.py detect_xcheck.py inkmask.py report.py`, 1,886 lines — for
`anthropic|openai|api_key|requests.post|httpx|mlx_vlm` returns **zero hits**. The one file that does
load a model, `bench_local_vlm.py`, is the standalone resolution/latency sweep and is not in the
pipeline path. The router *plans* vision calls and emits crops; it never makes one.

## 3. What this run adds that the record did not have

The README is emphatic that a pixel number belongs to one render — *"measured across two machines,
`findings_dom.json` was byte-identical while the X3 contrast pair moved 4.81/1.57 → 6.15/1.76. Same
verdicts, different numbers. Quote a number without its run and you are quoting a machine."*

This is a **third machine, across an architecture boundary** — Apple M1 Max arm64 → Linux x86_64, a
different Chromium build. Against the artifacts committed at `origin/main`:

| Artifact | macOS arm64 (committed) | Linux x86_64 (this run) | |
|---|---|---|---|
| `findings_dom.json` | `b33bfa4cb5e901c9` | `b33bfa4cb5e901c9` | **IDENTICAL** |
| `findings_xcheck.json` | `60fec89e3fd4dd8a` | `60fec89e3fd4dd8a` | **IDENTICAL** |
| `route-plan.json` | `409caeb1612a087b` | `409caeb1612a087b` | **IDENTICAL** |

So the **post-fix** cross-check is not merely "same verdict, different numbers" across machines — it
is byte-identical, including the X3 pair at 6.15:1 / 1.76:1 and X2 at −2.00 px. The 4.81/1.57 →
6.15/1.76 move the README records was the *modal-colour arm being replaced by the median arm*, not a
platform term; once the median fix landed, the platform term is zero on this corpus.

⚠️ **This does not retire the README's warning, and it must not be quoted as doing so.** Stability
here is manufactured, not free: `capture.py` pins sRGB, disables LCD text antialiasing, forces reduced
motion and awaits fonts precisely so the render is a function of the page rather than of the box. The
correct reading is that the pinning *works across architectures on this corpus* — a property of
`capture.py`, measured once, on 13 synthetic pages of 47 elements. A real route with webfonts,
subpixel positioning and platform emoji has not been tested and would be the thing to falsify it.

## 4. What is still open (and was never in this row's scope)

`bench/README.md` § "Known state" and § 8.1 already name these; none is part of `badb132df232`:

- **B0, the mined clean corpus** — the one that converts the FP claim from a bound into a rate.
  `score.py --clean-set` is the socket; it unlocks at n ≥ 16 with no code change.
- `xcheck-zero-ink` (X1) has no fixture and has never caught anything — reported NOT ADMITTED by the
  audit, left enabled (B19b).
- Cross-page collapse of the T1 queue (waits on U3), order-randomised comparison, motion, saliency.

## 5. Dispatcher vintage

`git rev-parse origin/main:bin/cc-dispatch` = `e61bcbfc657a44a20b03d7d52ab3e921fd138242`, **equal** to
the blob named in the brief. The dispatcher that fired this row **is** trunk, so no landed-vs-live
convergence gap is in play here — the row is stale against the research record, not against the
deploy layer.

## 6. Re-measuring this verdict

Per the repo's standing preference for a criterion plus the command over a perishable number: this
verdict is false the moment `score.py` stops exiting 0 or the artifact hashes move without a stated
cause. Re-derive with the § 2 block above; it needs only `numpy pillow playwright` and a Chromium
named by `BENCH_CHROMIUM`, and takes about a minute.

---

**Disposition:** close `badb132df232` as done, evidence `c811b941` + `77d2b0b4` + `9a11c84f`, verified
end-to-end at trunk `4d7a65d7` on 2026-09-11.
