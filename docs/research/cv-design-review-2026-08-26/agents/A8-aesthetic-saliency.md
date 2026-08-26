# A8 — Aesthetic & perceptual quality signals that are NOT an LLM opinion

Scope: can any model or metric score visual hierarchy, attention flow, clutter, balance, or colour
harmony on a UI screenshot, independent of a language model — and is any of it strong enough to gate
a design decision? Researched 2026-08-26. Every correlation below is quoted with its paper and its
sample size; where a number could not be sourced it is marked UNSOURCED rather than repeated.

---

## Verdict first

**No metric in this literature can gate "does it look good."** The ceiling is not the models — it is
the construct. Twenty trained designers judging 600 UI pairs agree only **62.4 %** of the time
(Krippendorff's alpha = **0.248**; four-way alpha = **0.114**; 28.5 % of pairs draw >=96 % disagreement) —
DesignPref, [arXiv:2511.20513](https://arxiv.org/pdf/2511.20513) sec. 3. A metric cannot be more valid
than the thing it is regressed on.

**Three narrower signals are real and worth running.** They gate *specific defects*, one-sided, never
a beauty score:

| | Signal | Gate it can carry |
|---|---|---|
| 1 | **UEyes-trained saliency (UMSI++)** — CC **0.833** vs human gaze | "the primary action is not in the predicted attention mass" |
| 2 | **Feature Congestion delta** on a paired before/after render | "this change made the screen measurably more cluttered" |
| 3 | **WCAG 2.x contrast ratio** (not a model — a spec) | "this text is unreadable" |

**The one that survives "just ask a frontier VLM"** is #1, and it is the *only* one with a head-to-head
measurement: on the identical UEyes test set with the identical metric, UMSI++ scores **CC 0.833**
while the best frontier VLM (GPT-5.4, 7 s duration) scores **CC 0.408** — UIGaze,
[arXiv:2604.26352](https://arxiv.org/pdf/2604.26352) sec. 4. A 2x gap on the same instrument. Everything
else in this document loses that argument or has never been put in the ring.

---

## The table

Runnability column assumes Apple Silicon (arm64 macOS), local, no cloud.

| Model / metric | What it predicts | Validation against humans (n) | Apple Silicon | Input | License |
|---|---|---|---|---|---|
| **AIM** (Aalto Interface Metrics), 26 metric modules | Bundle: clutter, colour, layout, saliency | Inherited from its sources; the *service* has never been validated as a whole | NO as shipped — pins `tensorflow==1.15.5`, `Keras==2.3.1`, `numpy==1.18.5`, `paddlepaddle==2.4.1`, Py3.7. No arm64 wheels for TF 1.15. Pure-numpy metrics port fine | URL (Selenium+Chrome) or PNG | MIT |
| **Feature Congestion** (AIM m8; Rosenholtz JoV 2007 7(2):17) | Perceived visual clutter | **r = 0.92, R2 = 0.85** (log space) vs paired-comparison clutter scale, **29 participants, 11 website screenshots** (10 after outlier removal) — Lafleur & Rummel, [dl.gi.de](https://dl.gi.de/server/api/core/bitstreams/e1cd9626-7621-41ff-8472-ad7e78c2b081/content) | YES — `pip install visual-clutter`; `pyrtools` 1.0.10 ships `macosx_11_0_arm64` wheels | PNG | MIT (AIM) |
| **Subband Entropy** (AIM m7; same paper) | Clutter as image redundancy | Same paper; no separate UI-specific coefficient published | YES same package | PNG | MIT |
| **Colourfulness** (Hasler & Susstrunk 2003; AIM m15) | Perceived colourfulness | **r = 0.95**, 84 images / 20 observers (original); re-tested **r = 0.71** against 450-website mean ratings (n=548) — Reinecke CHI'13 | YES ~20 lines of numpy | PNG | MIT |
| **Reinecke complexity + colourfulness -> appeal** (CHI 2013) | First-impression visual appeal at 500 ms | complexity model **r = .80, R2 = .65**; colourfulness **r = .88, R2 = .78**; appeal **adj. R2 = .48** — but that is a *mixed-effects* model including demographic interactions and per-participant random effects. **450 websites, 548 raters** — [PDF](https://iis.seas.harvard.edu/papers/2013/reinecke13aesthetics.pdf) | YES (classical CV; no weights released) | PNG | n/a — reimplement |
| **Miniukovich & De Angeli 8 metrics** (CHI 2015) — clutter, colour range, dominant colours, figure-ground contrast, contour congestion, symmetry, grid quality, white space. The backbone of AIM's layout family | GUI aesthetics rating | best-fit regressions explain **<=49 %** of webpage variance (**N = 62**) and **<=32 %** of iPhone-app variance *with app genre included* (**N = 53**) — [DOI](https://doi.org/10.1145/2702123.2702575) | YES (numpy/opencv) | PNG (+ segmentation) | MIT via AIM |
| **UMSI** (Fosco et al., UIST 2020; AIM m9) | Visual *importance* on graphic designs | GDI: **R2 0.781, CC 0.915, KL 0.086**. Imp1k: **R2 0.115, CC 0.875, KL 0.164** — [arXiv:2008.02912](https://arxiv.org/pdf/2008.02912) Tables 1-2. Imp1k = 1,000 designs (200 each: webpages/ClueWeb09, mobile UIs/RICO, posters, infographics, ads), **249 MTurk annotators**, ground truth = *mouse-painted masks*, not gaze | NO in AIM (TF 1.15 `.h5`); YES if reimplemented in torch | PNG | MIT (AIM wrapper) |
| **UMSI++ / SAM trained on UEyes** (Jiang et al., CHI 2023) | Human gaze saliency on UIs | **CC 0.833 +/- .078, AUC-J 0.905, SIM 0.733, KL 1.166**. Baselines on same set: SAM-pretrained CC 0.522, **UMSI-pretrained CC 0.431**, GBVS CC 0.314. Ground truth: **62 participants, 1,980 UIs**, Gazepoint GP3 HD, 7 s viewing, 1920x1200 — [PDF](https://yuejiang-nj.github.io/Publications/2023CHI_UEyes/paper.pdf) Table 1 | YES PyTorch/MPS (weights at userinterfaces.aalto.fi/ueyeschi23); repo last pushed 2024-07-16, **no license file** | PNG | UNLICENSED repo — clear before commercial use |
| **DeepGaze IIE** (Linardos & Kummerer, ICCV 2021) | Natural-image gaze | MIT1003: 93 % of explainable information gain; AUC 88.3, sAUC 79.4, CC 82.4 — **on photographs**. No published UI evaluation | YES PyTorch | PNG | MIT (`matthias-k/DeepGaze`) |
| **SUM** (WACV 2025 oral) | Unified saliency incl. a "UI/web" domain token | Reports per-domain results; **not evaluated on UEyes**, so not comparable to the row above | YES (Mamba kernels are the risk on MPS) | PNG + domain id | check repo |
| **MD-EAM** (AIM m30; Wang et al., TVCG 2023) | Attention at 0.5/3/5 s on *information visualisations* | Trained on MASSVIS charts. No UI validation | NO in AIM (Keras `.hdf5`) | PNG | MIT (wrapper) |
| **UIClip** (Wu et al., UIST 2024) | UI *design quality* + description relevance, pairwise | **BetterApp 63.2 %** (real human-rated pairs, 201 test pairs, 12 designers, **Krippendorff alpha = 0.37**); **JitterWeb 87.1 %** (synthetic injected defects); avg 75.12 %. GPT-4V on the same task: **51.58 %** (chance). LLaVA-1.6-13B 54.59 % — [arXiv:2404.12500](https://arxiv.org/pdf/2404.12500) | YES trivially — CLIP ViT-B/32, ~0.2 B params, `transformers` | PNG **+ a natural-language description of the screen** | MIT (`biglab/uiclip_jitteredwebsites-2-224-paraphrased`) |
| **Calista** (IJHCS 2023) | Website aesthetics score | **PCC 0.78 [0.69, 0.85]** (rating-based I); comparison-based 0.70 [0.58, 0.79] | YES (weights downloadable) | PNG | MIT |
| **TOCHI 2023 rating-distribution CNN** | Full *distribution* of aesthetics ratings | cross-validated **LCC = 0.752** — [DOI](https://dl.acm.org/doi/10.1145/3569889) | YES if weights released (not verified) | PNG | unverified |
| **Webthetics** (IJHCS 2019) | Webpage aesthetics | Secondary sources report LCC ~0.75-0.85; **primary PDF unreachable — treat as UNSOURCED** | YES | PNG | see repo |
| **NIMA** (AIM m18; Talebi & Milanfar 2018) | Photo aesthetic + technical quality | **SRCC 0.612** on AVA (255k DPChallenge photos). **Zero UI validation anywhere** | YES via `pyiqa` (torch, MPS) | PNG | model permissive; `pyiqa` **PolyForm Noncommercial 1.0.0** |
| **MUSIQ** | Photo quality/aesthetics, multi-scale | SRCC 0.726 (AVA) | YES `pyiqa` | PNG | PolyForm NC (toolkit) |
| **VILA / VILA-R** | Photo aesthetics from user comments | SRCC 0.774 / PLCC 0.774 (AVA) — [arXiv:2303.14302](https://arxiv.org/pdf/2303.14302) | partial | PNG | Apache-2.0 (Google) |
| **Q-Align / ARNIQA / CLIP-IQA / TOPIQ** | Photo quality, LMM-scored | AVA/KonIQ SOTA; **all photographic** | YES `pyiqa` | PNG | PolyForm NC (toolkit) |
| **LAION aesthetic predictor V2** | "Aesthetic" 1-10 | Linear head on CLIP ViT-L/14 over AVA + SAC + LAION-Logos. Architecture and dataset weighting chosen **by the author's visual inspection** — audited in [arXiv:2601.09896](https://arxiv.org/pdf/2601.09896). No published correlation on anything that is not a photo or an AI art generation | YES trivially | PNG | MIT |
| **Colour harmony** (AIM m20; Cohen-Or SIGGRAPH 2006) | Distance to nearest of 8 hue templates | **None on UI.** The source is a *harmonisation algorithm*, not a perceptual scale | YES | PNG | MIT (wrapper) |
| **WAVE** (AIM m10; Palmer & Schloss PNAS 2010) | Mean colour preference | Preference values from an object-association study; AIM's own docstring warns they are sociocultural and may not transfer | YES | PNG | MIT |
| **Grid quality / white space** (AIM m21/m22) | Alignment of detected blocks; whitespace fraction | Only the <=49 % aggregate from Miniukovich CHI'15; no per-metric coefficient published | YES but depends on segmentation (AIM uses PaddleOCR + UIED — **the arm64 blocker**) | PNG | MIT |
| **Ngo 14 measures** (Information Sciences 2003) — balance, equilibrium, symmetry, sequence, cohesion, unity, proportion, simplicity, density, regularity, economy, homogeneity, rhythm, order | Screen aesthetics from element geometry | Purchase et al. (AUIC 2011, **15 web pages**) found only a *subset* predicted appeal ranks; object placement did, most measures did not | YES (needs element boxes) | DOM or segmentation | n/a — reimplement |
| **WCAG 2.x contrast ratio** | Text legibility | Not a correlation — a normative spec with conformance thresholds | YES deterministic, no model | computed colours (DOM) or pixels | W3C |
| **APCA (Lc)** | Perceptual contrast incl. size/weight/polarity | **Still not normative.** WCAG 3.0 remains a Working Draft in 2026 and its contrast algorithm is undetermined; APCA was exploratory and the exploratory items were removed in the July 2023 update — [Roselli, April 2026](https://adrianroselli.com/2026/04/wcag3-contrast-as-of-april-2026.html) | YES | colours | see APCA terms |

---

## What the numbers actually mean — validity teardown

**A metric with no human validation on UI is a number, not a measurement.** By that test:

- **Has UI validation:** Feature Congestion (n=11 stimuli), Reinecke complexity/colourfulness (n=450
  sites), Miniukovich's 8 (n=62/53 raters), UEyes saliency family (n=62 raters / 1,980 UIs), UIClip
  (n=201 real pairs / 12 designers), Calista, TOCHI-2023.
- **Has NO UI validation:** every photo-aesthetics model (NIMA, MUSIQ, VILA, Q-Align, ARNIQA, LAION),
  colour harmony, WAVE, MD-EAM, DeepGaze IIE, all of Ngo except the Purchase subset.

Four specific traps:

1. **Feature Congestion's r = 0.92 rests on 11 screenshots**, deliberately sampled *equidistant* across
   the FC range 2.61-13.15 to maximise spread, with one removed as an outlier — and it was removed
   **because its vertical alignment was bad**, i.e. precisely the design property we care about. The
   paper also reports the relationship is **flat below FC ~= 9**: "variations of Feature Congestion
   below a critical value of about 9 have only limited effect on the perceived clutter." Well-designed
   dashboards live below 9. The metric detects *catastrophe*, not *craft*.
2. **Reinecke's 48 % is not 48 % from the image.** It is a linear mixed-effects model with
   `StimulusID` and `ParticipantID` as random effects plus interactions of age/education with the two
   image models, predicting appeal after **500 ms** exposure. It is a first-impression model, and the
   authors say so: "our findings may not generalize to predict user's 'long-term' appeal."
3. **UMSI's own headline hides its weakest number.** R2 = 0.781 on GDI (posters/ads) collapses to
   **R2 = 0.115 on Imp1k**, the set that actually contains webpages and mobile UIs. And AIM ships the
   *pretrained* UMSI as its saliency metric (m9) — the exact checkpoint UEyes measured at
   **CC 0.431 on UI gaze, worse than a generic photo-saliency model (SAM, CC 0.522)**.
4. **UIClip's 87.1 % is not a beauty score.** JitterWeb is synthetic: colour swaps, size jitter,
   misalignment injected into a working page. 87 % is "can you spot a deliberately corrupted render."
   On real human-rated pairs (BetterApp) the same model gets **63.2 %** against a designer alpha of 0.37.

**Photo aesthetics on a dashboard screenshot: state it plainly.** NIMA/MUSIQ/VILA/LAION are trained
on AVA (DPChallenge photo contest), SAC (Discord AI-art votes), KonIQ. Their latent construct is
photographic — depth of field, subject framing, exposure, colour grading. A dashboard has none of
these. There is no published correlation between any of them and any human UI-quality judgement, and
the one adjacent data point is damning: **OpenAI CLIP B/32, the backbone under LAION's aesthetic
head, scores 46.68 % — below chance — and SRCC -0.009 on UI design preference** (DesignPref Table).
Running NIMA on a screenshot produces a number that moves. It does not produce a measurement.
AIM ships NIMA as m18 anyway; that is a packaging decision, not evidence.

**Unmeasured validity threat nobody in this literature addresses: resolution and fold.** Every UI
dataset here is a fixed-aspect above-the-fold capture (UEyes at 1920x1200; Imp1k explicitly filtered
out "skewed aspect ratios"). A real dashboard screenshot is tall, text-dense, and mostly light.
Resizing it to a model's input makes the metric a function of an image the human never saw. I found
no paper measuring the stability of any of these scores under viewport change, re-render, or scroll
position. Treat any absolute score as uncalibrated for tall screenshots until you measure it yourself.

---

## Combining a numeric signal with an LLM critique

The failure mode you are escaping — "ask Claude for a 1-10" — is not fixed by handing Claude a second
number. A number in the prompt becomes an anchor the model rationalises around, which is the same
vacuity with a citation attached. Four combinations that actually add information:

**1. Give the model the saliency *map*, not the saliency *score*.** Render the UMSI++/UEyes heatmap
as a second image and pass both. The VLM is measurably bad at predicting gaze (CC 0.408 best-in-class,
Gemini 3.1 Pro at 0.144, UI-TARS 1.5 at -0.008 on mobile) and measurably good at reasoning about what
a screen is *for*. The map supplies the axis it cannot compute; the model supplies the intent it can.
This is the one place the specialist model is strictly additive.

**2. Convert saliency into a decision-relevant statistic before it reaches the model.** Not
"saliency = 0.83". Instead: *"the element you named as the primary action captures 4 % of predicted
attention mass; the largest single mass (31 %) falls on the hero illustration."* That is a falsifiable
claim about hierarchy, computed without an opinion, and it is exactly the "visual hierarchy /
attention flow" half of the question. Fix the threshold before you look.

**3. Everything else enters as a PAIRED DELTA with a pre-registered rule.** Both UIClip and
DesignPref evaluate *pairwise*, because that is where the signal is: absolute UI aesthetic scores are
uncalibrated, pairwise ones are merely noisy. Run each metric on before/after renders of the same
page and report deltas with a direction and a threshold decided in advance — delta-FeatureCongestion,
delta-UIClip-preference, delta-contrast-failure-count. A delta is auditable; a score is a vibe.

**4. Forbid the model from re-scoring.** The prompt says: these numeric signals are evidence; do not
produce your own aesthetic score; either explain a specific flagged delta or declare the flag a false
positive and say why. This removes the scoring degree of freedom entirely rather than trying to
debias it — which is the only reliable answer to self-preference bias.

Pipeline shape that follows from the evidence:

```
render -> (a) deterministic gates: WCAG contrast, overflow, tap-target size  -> hard fail
       -> (b) UMSI++ saliency map + attention-mass-on-primary-action          -> image + one statistic
       -> (c) delta Feature Congestion vs baseline render                     -> one-sided tripwire
       -> (d) UIClip pairwise vs baseline render (needs a description string) -> one-sided tripwire
       -> VLM critique, given (a)-(d) as evidence, banned from emitting a score
```

Cost: (b) is ~90 M params, (d) ~200 M — both well under a second on an M-series GPU. (c) is pure
numpy. The whole numeric layer is cheaper than one VLM call.

---

## Adversarial pass — the strongest case that all of this is worse than asking a frontier VLM

I ran this argument as hard as I could. It wins on most rows.

1. **The ground truth is barely there.** DesignPref: trained designers agree 62.4 % binary,
   alpha = 0.248. Any model regressed on aggregated designer preference is fitting a consensus no
   individual designer holds. A frontier VLM at **57.70 %** (GPT-5 zero-shot, SRCC 0.216) is *within
   5 points of the human-human ceiling* and beats UIClip-pretrained (55.07 %, SRCC 0.126) and every
   non-personalised CLIP variant. On "which of these two is better", the specialist is already losing.
2. **Nearly every metric is proxy-of-a-proxy.** Colour harmony measures distance to a hue template
   nobody validated on UI. WAVE measures 2010 Berkeley colour preferences. NIMA measures photo-contest
   taste. Grid quality measures alignment of boxes found by an OCR pipeline that itself fails on
   modern UIs. A VLM asked "is the hierarchy clear" is at least aimed at the question.
3. **The strong numbers are on the wrong task.** UIClip's 87 % is defect detection. Feature
   Congestion's 0.92 is on 11 hand-picked stimuli spanning a range real designs do not span. UMSI's
   0.915 CC is on posters. Strip the tasks nobody asked about and the validated surface nearly vanishes.
4. **Operational cost is real and asymmetric.** AIM does not install on this hardware —
   `tensorflow==1.15.5` has no arm64 wheel, last commit 2023-06-11, 36 open issues — and `pyiqa` is
   PolyForm **Noncommercial**. Standing up the numeric layer is days of work whose payoff is a signal
   that, per (1), a VLM call already matches.
5. **The vacuity you are fleeing reappears.** A metric reading 4.7 that shifts to 4.9 after a redesign
   is exactly as uninterpretable as "7/10", with the added harm that it *looks* objective.

**What survives.** Exactly one thing, and it survives because it was actually measured head-to-head:

> **UEyes-trained saliency (UMSI++).** Same test set, same metric, same images:
> **UMSI++ CC = 0.833** vs **GPT-5.4 CC = 0.408**; the runner-up VLMs are far worse
> (Claude Opus 4.6 0.344, Qwen 3.5 Plus 0.337, Gemini 3.1 Pro 0.144, UI-TARS 1.5 0.086 with
> **CC = -0.008 on mobile**). Note also the temporal structure the VLM cannot fake: GPT-5.4 goes
> 0.217 (1 s) -> 0.326 (3 s) -> 0.408 (7 s), i.e. it approximates *deliberate* looking and is worst at
> the reflexive first second — precisely the window where visual hierarchy either works or does not.

Saliency is the one axis where the VLM's advantage (semantic reasoning) is the *wrong* tool, because
early gaze is pre-semantic. That is why the gap is 2x and why it is the only defensible non-LLM signal.

Runner-up, kept for a different reason: **WCAG contrast**, because it is not a model at all. It is a
spec with a threshold, it is deterministic, it is legally load-bearing, and a VLM reading colours off
a screenshot will get it wrong. It cannot tell you a design is good; it can tell you a design is
non-conformant, which is a gate.

---

## Can any of it gate a design decision? Honest answer

- **Gate "is this design good": NO.** Not with anything here, and not with an LLM either. The
  construct's inter-rater reliability (alpha = 0.248 among designers) makes a pass/fail threshold
  arbitrary by construction.
- **Gate "did this change break the hierarchy": YES, one-sided.** UMSI++ attention mass on the
  declared primary element, thresholded, computed on before/after renders. Fires rarely; when it
  fires it names a specific element.
- **Gate "did this change make it measurably more cluttered": YES, one-sided, coarse.** Delta Feature
  Congestion, large increases only — the source paper says the measure is insensitive below FC ~= 9,
  so a *decrease* proves nothing.
- **Gate "is this text readable": YES.** WCAG contrast ratio, deterministic. Do not use APCA as a gate
  yet — as of April 2026 WCAG 3.0 is still a Working Draft and its contrast algorithm is undetermined.
- **Everything else: advisory evidence for a critique, never a gate.** Colourfulness, colour harmony,
  white space, grid quality, NIMA, LAION aesthetic. Report as deltas if at all; never a headline score.

**The sharpest reframe:** stop trying to measure beauty and start measuring *whether the design does
the job it claims*. "The CTA you named captures 4 % of predicted attention" is a measurement.
"This UI scores 7.2" is not, whoever produced it.

---

## Blockers / uncertainties, named

- **UEyes model weights carry no license file** (repo `YueJiang-nj/UEyes-CHI2023`, last push
  2024-07-16, no LICENSE). Dataset is CC on Zenodo; the *weights* legal status is unresolved.
- **`pyiqa` is PolyForm Noncommercial 1.0.0** — fine for internal tooling, not a product feature.
  Individual weights (NIMA, MUSIQ) carry their own separate terms.
- **AIM's segmentation-dependent metrics (grid quality, white space, m24/m25) need PaddleOCR +
  paddlepaddle on arm64**, the hardest install in the stack. If you want those metrics, budget for
  reimplementing segmentation, not for installing AIM.
- **Webthetics' correlation is UNSOURCED here** — primary PDF 404'd from the CUHK mirror and
  ResearchGate blocked. Do not cite the 0.85 figure.
- **No published stability data** for any of these scores under viewport/resolution change. Measure
  test-retest on your own renders before trusting a delta threshold.
- **UMSI++ weights were not downloaded or executed in this pass** — CC 0.833 is the paper's number on
  the paper's split. Whether it holds on tall dark-mode dashboards is unmeasured and is the first
  thing to check empirically.
- **AesEval-Bench** ([arXiv:2603.01083](https://arxiv.org/abs/2603.01083), 2026) benchmarks VLMs on
  graphic-design aesthetics across 4 dimensions / 12 indicators / 3 tasks and reports "clear
  performance gaps"; the landing page carries no extractable numbers and the PDF was not parsed here.
  Worth a follow-up if the VLM-side baseline matters.

---

## AIM's full metric inventory (read from `aalto-ui/aim@aim2`, `backend/aim/metrics/`)

m1 PNG file size · m2 JPEG file size · m3 distinct RGB values · m4 contour density · m5 figure-ground
contrast · m6 contour congestion · m7 subband entropy · m8 feature congestion · m9 UMSI · m10 WAVE ·
m11 static colour clusters · m12 dynamic colour clusters · m13 luminance SD · m14 CIELAB avg/SD ·
m15 colourfulness (Hasler & Susstrunk) · m16 HSV avg/SD · m17 distinct H/S/V · m18 NIMA ·
m19 distinct RGB per dynamic cluster · m20 colour harmony · m21 grid quality · m22 white space ·
m23 colour blindness · m24 legacy segmentation · m25 UIED segmentation · m30 MD-EAM.
(Repo MIT; default branch `aim2`; last commit 2023-06-11; 36 open issues.)

---

## Sources

- Aalto Interface Metrics — [github.com/aalto-ui/aim](https://github.com/aalto-ui/aim) · [interfacemetrics.aalto.fi](https://interfacemetrics.aalto.fi/) · [UIST'18 adjunct](https://dl.acm.org/doi/10.1145/3266037.3266087)
- Miniukovich & De Angeli, *Computation of Interface Aesthetics*, CHI 2015 — [doi:10.1145/2702123.2702575](https://doi.org/10.1145/2702123.2702575)
- Reinecke et al., *Predicting Users' First Impressions of Website Aesthetics*, CHI 2013 — [PDF](https://iis.seas.harvard.edu/papers/2013/reinecke13aesthetics.pdf)
- Rosenholtz, Li & Nakano, *Measuring visual clutter*, J. Vision 2007 7(2):17 — [doi:10.1167/7.2.17](https://doi.org/10.1167/7.2.17)
- Lafleur & Rummel, *Predicting Perceived Screen Clutter by Feature Congestion* — [PDF](https://dl.gi.de/server/api/core/bitstreams/e1cd9626-7621-41ff-8472-ad7e78c2b081/content)
- Fosco et al., *Predicting Visual Importance Across Graphic Design Types* (UMSI/Imp1k), UIST 2020 — [arXiv:2008.02912](https://arxiv.org/pdf/2008.02912)
- Jiang et al., *UEyes: Understanding Visual Saliency across User Interface Types*, CHI 2023 — [PDF](https://yuejiang-nj.github.io/Publications/2023CHI_UEyes/paper.pdf) · [dataset](https://zenodo.org/records/8010312)
- Wu et al., *UIClip: A Data-driven Model for Assessing User Interface Design*, UIST 2024 — [arXiv:2404.12500](https://arxiv.org/pdf/2404.12500) · [weights](https://huggingface.co/biglab/uiclip_jitteredwebsites-2-224-paraphrased)
- *DesignPref: Capturing Personal Preferences in Visual Design Generation* — [arXiv:2511.20513](https://arxiv.org/pdf/2511.20513)
- *UIGaze: How Closely Can VLMs Approximate Human Visual Attention on User Interfaces?* — [arXiv:2604.26352](https://arxiv.org/pdf/2604.26352)
- Duan et al., *UICrit*, UIST 2024 — [arXiv:2407.08850](https://arxiv.org/abs/2407.08850) (983 mobile UIs, 3,059 critiques, 7 designers; 55 % gain in LLM feedback quality from few-shot + visual prompting)
- Linardos & Kummerer, *DeepGaze IIE*, ICCV 2021 — [arXiv:2105.12441](https://arxiv.org/pdf/2105.12441)
- Hosseini et al., *SUM: Saliency Unification through Mamba*, WACV 2025 — [arXiv:2406.17815](https://arxiv.org/html/2406.17815)
- *Predicting Rating Distributions of Website Aesthetics with Deep Learning*, TOCHI 2023 — [doi:10.1145/3569889](https://dl.acm.org/doi/10.1145/3569889)
- Calista — [github.com/calista-ai/website-aesthetics-research](https://github.com/calista-ai/website-aesthetics-research) (MIT)
- Talebi & Milanfar, *NIMA*, TIP 2018 — [doi:10.1109/TIP.2018.2831899](https://doi.org/10.1109/TIP.2018.2831899) · VILA — [arXiv:2303.14302](https://arxiv.org/pdf/2303.14302) · Q-Align — [arXiv:2312.17090](https://arxiv.org/html/2312.17090) · UNIAA — [arXiv:2404.09619](https://arxiv.org/pdf/2404.09619)
- `IQA-PyTorch` / `pyiqa` — [github.com/chaofengc/IQA-PyTorch](https://github.com/chaofengc/IQA-PyTorch) (PolyForm Noncommercial 1.0.0)
- LAION-Aesthetics audit — [arXiv:2601.09896](https://arxiv.org/pdf/2601.09896)
- Ngo et al., *Modelling interface aesthetics*, Information Sciences 2003 · Purchase et al., AUIC 2011 — [CRPIT 117:19-28](https://crpit.scem.westernsydney.edu.au/abstracts/CRPITV117Purchase.html)
- Roselli, *WCAG3 Contrast as of April 2026* — [adrianroselli.com](https://adrianroselli.com/2026/04/wcag3-contrast-as-of-april-2026.html)
