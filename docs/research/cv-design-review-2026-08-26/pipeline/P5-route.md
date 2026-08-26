# P5 — ROUTE: deciding what reaches Opus 5, in what form, with what context

**Stage position:** between the deterministic screen (P3 `detect_dom` + P4 `detect_xcheck`) and the
judging model. **Every model call is a routing decision**, and this stage is the only place in the
pipeline authorised to spend one.

**Governing constraint, restated so it cannot drift:** the judge is *advisory triage*, never a CI
gate (ratified June 2026). ROUTE therefore never emits a pass/fail. It emits **questions**, and a
question that could have been answered by arithmetic is a routing defect, not a model failure.

---

## 1. Contract

### 1.1 Inputs

ROUTE reads a completed **perceive directory** — one page, one viewport, one colour scheme — and
nothing else. It never touches a browser and never opens a network socket.

```
<perceive-dir>/
  manifest.json          # capture manifest (A9 §3 item 9): playwright ver, chromium UA, channel,
                         # flags, viewport, dpr, colorScheme, scrollbarPx, sha256, w×h, bytes
  page@1440x900.png      # the CLEAN viewport shot; clamp-safe by construction
  page.layout.json       # capture.py snapshot: {url,title,scroll{w,h},elements[…]}
  factpack.json          # A7 §3 extraction schema, ~3,073 bytes ≈ 854 tokens
  findings_dom.json      # [{rule,target,detail,severity}] from detect_dom.py
  findings_xcheck.json   # [{rule,target,detail,severity}] from detect_xcheck.py
  clip/                  # empty on entry; ROUTE writes crops here
```

Required fields ROUTE hard-asserts on entry, refusing (exit 2) if absent — each is load-bearing and
a missing one silently changes a verdict:

| Assertion | Why refusing beats defaulting |
|---|---|
| `manifest.dpr == manifest.forceDeviceScaleFactor` | A9 R1: unpinned scale drifts line boxes ~1.5 px over four paragraphs; **every geometric question ROUTE forwards would inherit a phantom offset**. |
| `manifest.clamp_safe == true` (`w≤2000 && h≤2000 && bytes≤3,932,160`) | A9 R3: over the clamp, Claude Code palette-quantises to 256 colours or JPEGs at q20 *without telling the session*. A colour question routed onto a quantised image is unanswerable and reads answerable. |
| `manifest.colorScheme` present | A9 R6: unset defaults to light; a dark-mode review in light theme voids every contrast question. |
| `findings_dom.json` exists (may be `[]`) | Absence-of-file and empty-list are different states — see §7.2. |

### 1.2 Outputs

Three artifacts, all on disk, all read by the agent through ordinary tools. No MCP server (A11 §2.3:
a dead stdio server *vanishes from the tool list*, so an outage in a layer whose job is to stop the
model guessing is indistinguishable from having nothing to check).

**(a) `route-plan.json`** — the decision record.

```json
{
  "schema": "design-route/1",
  "ok": true,
  "page": "dashboard",
  "budget": { "image_blocks_granted": 2, "image_blocks_ledger": 5, "ceiling": 12 },
  "settled": 14,
  "calls": [
    { "id": "C1", "kind": "global", "image": "page@1440x900.png",
      "visual_tokens": 3240, "asks": ["hierarchy","gestalt","content-fit","semantic-coherence"] },
    { "id": "C2", "kind": "region", "image": "clip/C2@700x440.png",
      "visual_tokens": 1600, "css_box": [24,612,700,440],
      "from": ["F07","F09"], "asks": ["contrast-indeterminate"] }
  ],
  "unrouted": [ { "id": "F21", "why": "budget", "class": "optical-alignment" } ],
  "coverage": { "dom": "complete", "pixel": "complete", "judgement": "planned" }
}
```

**(b) `clip/C<n>@<w>x<h>.png`** — one crop per region call, cut from the *same browser pass* as the
clean shot (P2 owns the re-clip; ROUTE emits the clip request, see §7.1).

**(c) `route-steps.sh`** — the ordered tool-call sequence the agent executes verbatim. This file is
the stage's actual product: **ordering is the stage's main lever and in Claude Code ordering is
tool-call order** (§5.1).

### 1.3 Failure modes, exhaustively

| exit | meaning | envelope |
|---|---|---|
| 0 | plan produced; may contain zero calls (a page that earns no model call is a normal outcome) | `ok:true` |
| 2 | input assertion failed (§1.1) — **the capture is not evidence** | `ok:false, "reason":"manifest.clamp_safe=false: 2880×1800, 4.9 MiB"` |
| 3 | screen layer absent *by failure* — refuse, do not degrade (§6.1) | `ok:false, "layers":{"dom":"unavailable"}` |
| 4 | image-block ledger exhausted and no subagent handle supplied (§4.2) | `ok:false, "reason":"ledger 12/12; pass --spawn-handle or start a fresh context"` |
| 5 | a call's crop cannot be made lossless at any size ≤966×966 CSS px (§4.3) | `ok:false` with the offending `css_box` |

ROUTE **never** exits 0 with `calls: []` because it could not decide. "Nothing earned a call" and
"could not compute a plan" use different channels — `null-result-must-not-use-the-error-channel`.

---

## 2. What triggers a model call

Five classes, and **only** five. Anything not matching one of them is settled by the screen and
forwarded as a *fact*, never as a question.

### T1 — INDETERMINATE residue *(conditional, rare by construction)*

A `detect_dom` finding whose verdict is the honest third answer — today only
`contrast-indeterminate` — **that `detect_xcheck` did not resolve**. The ordering matters and is the
cheapest win in the stage: on the corpus's gradient page the cross-check turned "unrepresentable"
into `4.81:1 at the left edge and 1.57:1 at the right`, a full verdict, **with no model call at
all**. So T1's population is not "every abstention" but "abstentions the free comparator could not
close", and on the 13-page corpus that is currently **zero pages**.

```
T1 = { f ∈ findings_dom : f.rule.endswith("-indeterminate") }
   − { f : ∃ x ∈ findings_xcheck, x.target == f.target ∧ x.rule.startswith("xcheck-") }
```

Routing T1 items that the cross-check *did* close would be spending 1,600 tokens to re-ask a
question already answered by 180 lines of NumPy. That is the single most likely way this stage
degrades over time, because new rules will add new abstentions and nobody re-runs the subtraction.
**The subtraction is code, not discipline.**

### T2 — Unscreenable question classes *(unconditional, page-level)*

Six classes for which no computed style is the answer. Each is on the list because the corpus
measured a real defect in it that no rule found, or because A7's schema explicitly cannot reach it:

| class | why the screen cannot answer it | corpus evidence |
|---|---|---|
| `hierarchy` | "primary" is a claim about relative visual weight across a whole frame; the DOM has no such relation | inverted action hierarchy — blind Claude 1/1, rules 0/1 |
| `gestalt` | grouping is proximity + similarity + enclosure interacting; each is measurable, their resolution is not | orphan legend (found blind, no rule was looking) |
| `content-fit` | whether a caption's *promise* matches the render is a language↔pixel comparison | table caption promised grey rows that did not exist |
| `semantic-coherence` | an unlabelled control is valid HTML with valid AX; the defect is that a human cannot tell what it does | unlabelled icon button, smallest hit target |
| `optical-alignment` | geometric centre ≠ optical centre; the compensation is deliberate and its absence is a judgement | the `optical-centering` variant — and the xcheck centroid arm that tried this is **PROVISIONAL and ships disabled** |
| `readability` | left-aligned numerics are geometrically perfect and read wrong | numeric columns whose digits did not line up |

T2 fires **once per page**, not once per finding, and it is the call that must never be cut for
budget. Three of the corpus's most valuable findings came from exactly this call, on a clean image,
with nobody looking for them. Cutting it converts the reviewer into a linter with a screenshot.

### T3 — Explicit request

The operator or a plan names a page/region and a question. Routed verbatim, budget-exempt, and the
only class permitted to exceed the per-page image cap. Recorded in `route-plan.json` with
`"kind":"explicit"` so a later audit can separate operator-driven spend from autonomous spend.

### T4 — Arbitration *(second-order, fires only after a judgement exists)*

The judge's blind answer **contradicts** a `layer:"dom"` finding, or two findings share a region and
the judgement is ambiguous about which element it means. Only then does a cropped second look earn
its 1,600 tokens (A11 §4 conclusion 2). Capped at **one arbitration per page**: a second
disagreement about the same page is a *rule* defect to file, not a third image to buy.

### T5 — No-DOM subjects

Canvas, WebGL, PDF comps, competitor screenshots, a video frame. There is no screen layer to run, so
every question is a model question. This is the one class where "the model is the primary
instrument" is true rather than a rationalisation — see §6.1, where it is the discriminator that
makes the degradation policy decidable.

### The NEVER list — what is deliberately not sent, and why

> **If the answer has a number in it, the model does not get the question.**

| Never routed | Where it is settled | Cost of routing it anyway |
|---|---|---|
| any distance, gap, offset, size, ratio | `getBoundingClientRect` / factpack B1, B5, B9 | Opus 5 scored **0/2** on sub-perceptual precision — a 1 px misalignment and a 5/255 colour drift. A model asked for a number it cannot see either abstains (wasted call) or invents one (a defect injected into a source edit). |
| contrast against a solid or layered backdrop | factpack B6 (`blendedBackgroundColors`, WCAG + APCA) | free and exact |
| contrast over a gradient/image | `detect_xcheck` left/right-third sampling | free and exact; **and the naive alternative is a confident false PASS** — CDP reported 10.36:1 where the text sits at 1.22:1 |
| token/palette membership | factpack B3 + the app's token source | set difference |
| animation duration/easing/delay | `getComputedTiming()` with `auto` resolved | an assert, not a vision task |
| **bounding boxes for anything** | the DOM | a model box is a 68-mAP estimate of an exact free value; **no published benchmark certifies box quality** (every ScreenSpot variant scores point-in-box, not IoU) |
| a score, grade, or ranking | nowhere — it is not asked | ratified June 2026: taste stays human. Rubric scoring shows **16–39% top-1 reversals from reordering alone** |
| the annotated overlay, as a standing input | not sent | a full second image (3,240 tok) delivering what `bbox_raster` delivers for ~840, and a critique cannot run on an image with rectangles painted over the subject |

---

## 3. Budget: the unit is the SESSION, not the request

### 3.1 The image ledger — the stage's sharpest constraint

The published cliff is *">20 image blocks in one request tightens the per-image cap and **rejects**
oversized images rather than downscaling them."* The routing consequence is not the obvious one.

**A Claude Code session re-sends its whole conversation on every turn.** An image `Read` on turn 3 is
still an image block in the request built on turn 14. So the ">20 in one request" budget is
**cumulative over the session**, not per model call — and it is spent by every unrelated screenshot
the agent takes while *fixing* what the review found, not only by the review itself.

Therefore ROUTE maintains `<perceive-root>/.image-ledger` (one line per block: `ts, sid, path, w, h,
visual_tokens`) and enforces:

| Number | Value | Reason for this value |
|---|---|---|
| `CEILING` | **12** blocks per session | The cliff is 20 and it fails by **rejection**, not degradation — an unrecoverable mid-review error, because you cannot un-send an image. 8 blocks of headroom is 40%, sized to the consumer: this agent *edits source* and will take its own before/after shots. |
| `PER_PAGE_MAX` | **2** blocks (1 global + 1 region) | The residue after screen + cross-check is empirically tiny — on the 13-page corpus, T1 is currently empty. A page needing three images is a page whose *rules* are missing, and the second finding is the signal to file that. |
| `ARBITRATION_MAX` | **1** per page | see T4 |

On `ledger + planned > CEILING`, ROUTE does **not** downgrade image quality and does **not** drop the
T2 global call. It **splits the review across contexts**: remaining pages go to a fresh research
subagent (its own window, its own ledger) whose brief is the identical `route-steps.sh`. Exit 4 when
no spawn handle was supplied. *Reason:* degrading the image is the fail-safe-mimics-healthy trap —
a quantised screenshot produces a review that reads exactly like a good one.

⚠️ **UNVERIFIED — the cumulative-count claim.** That conversation history re-sends image blocks is
how the Messages API works; that Claude Code counts *historical* blocks against the >20 rule is
inferred, not measured. **One probe settles it:** in a scratch session, `Read` 21 distinct
1200×800 PNGs in 21 separate turns and record whether turn 21 returns an API error naming the image
count. If it does not, `CEILING` can rise to ~18 and per-session batching gets cheaper; if it does,
this section is load-bearing exactly as written.

### 3.2 Which regions earn a call

Only T1 and T4 produce region calls, so the selection rule runs over a small set.

```python
def regions(t1, t4, snapshot):
    boxes = [css_rect(f.target, snapshot) for f in (t1 + t4)]
    clusters = merge_within(boxes, gap_px=32)      # 32 px == 4 × the 8 px grid unit
    scored = [(2*n_high(c) + 1*n_med(c) + 0.5*n_low(c), c) for c in clusters]
    picked = [c for _, c in sorted(scored, reverse=True)[:PER_PAGE_MAX - 1]]
    return [c for c in picked if fits_lossless(c)]  # else -> fold into the global call
```

**`gap_px = 32`.** Two findings closer than 32 CSS px are almost always inside one visual group, and
splitting a group across two crops asks the model to judge grouping with the group cut in half. 32
is the corpus's dominant large-gap tier and one step above the 24 px tier — merging inside one tier
preserves the group; merging across tiers would swallow the page.

**The severity weights (2 / 1 / 0.5)** are ordinal, not calibrated. Their only job is to break ties
toward `severity:"high"`, which in `detect_dom` is exactly the set {contrast, overflow,
touch-target, contrast-indeterminate} — the classes where being wrong ships a broken page.
**UNVERIFIED as a *ranking*:** we have never had ≥3 competing clusters on one page, so the weights
have never actually chosen. The probe is a corpus page carrying three simultaneous abstentions.

### 3.3 The lossless crop window — three ceilings, and the binding one is not the famous one

A crop must clear **all** of:

1. `w ≤ 2000 && h ≤ 2000` — Claude Code's client clamp (`O5.maxWidth/maxHeight`)
2. `bytes ≤ 3,932,160` — `O5.targetRawSize`; over it, PNG is re-encoded with `palette:true`, i.e.
   **quantised to ≤256 colours**, which silently destroys exactly the gradient evidence a T1 call
   exists to read
3. `⌈w/28⌉ × ⌈h/28⌉ ≤ 4784` — Opus 5's high-resolution visual-token tier

Ceiling 3 is the one nobody configures for and it binds *before* ceiling 1 on square crops. Solving
`⌈n/28⌉² ≤ 4784` gives `⌈n/28⌉ ≤ 69`, so **n ≤ 1932 px raster = 966×966 CSS px at DPR 2**. A
1000×1000 CSS @2 crop is 2000×2000 raster = **5,184 tokens — over the tier**, so the API resizes on
top of the client clamp and the crop you paid for is not the crop the model sees.

**ROUTE's crop rule, stated as the number it actually uses: 966×966 CSS px @ DPR 2, not 1000×1000.**
Derived from the two published caps (28-px patches; 4,784-token tier), not measured — but it is
arithmetic over published constants, and the failure it prevents is silent.

Non-square crops get more room: the real predicate is `⌈w/28⌉ × ⌈h/28⌉ ≤ 4784`, which admits e.g.
1400×880 (50 × 32 = 1,600 tok) comfortably. ROUTE always emits the *smallest* box containing the
cluster plus **16 px of CSS bleed** on each side — enough to include the boundary the finding is
about (an alignment claim needs the edge it is misaligned *from*) without importing a second group.

---

## 4. Request assembly

### 4.1 Image-before-text is unreachable in-session — and the Bash tool result is the fix

Anthropic's vision guidance is to place the image **before** the text that asks about it. In a
Claude Code session the agent cannot build a message array: an image arrives only as a `tool_result`
from `Read`, and the instruction that caused the `Read` necessarily precedes it. Naively, every
review is therefore text→image→answer — the wrong order, permanently.

**The lever is that a `Bash` tool result is also a block, and it can land *after* an image.** So
ROUTE delivers the question through the CLI rather than through the prompt:

```
user      : route directive (≤60 tok) — "execute route-steps.sh in order; withhold judgement
            until step N prints the question"
assistant : tool_use  Read  clip/C2@1400x880.png
user      : tool_result  [IMAGE]                      ← region, most specific, seen first
assistant : tool_use  Read  page@1440x900.png
user      : tool_result  [IMAGE]                      ← page context
assistant : tool_use  Bash  design-route <dir> --ask C1,C2
user      : tool_result  [TEXT: settled facts + factpack + the question]   ← AFTER both images
assistant : the judgement
```

Two ordering decisions inside that, both deliberate:

- **Region crop before the page shot.** The crop is the higher-detail evidence and the page shot is
  its context. Ordering specific→general keeps the last image before the question the one carrying
  the most pixels per CSS px. *(UNVERIFIED as a quality claim — no measurement here distinguishes
  the two orders. Probe: run the 13-page corpus both ways with a fixed prompt and compare the
  count of findings that name a wrong element.)*
- **The settled facts arrive with the question, not before the images.** Putting 854 tokens of
  factpack ahead of the pixels primes the model to *look for* what the numbers say, which is exactly
  the anchoring that produced Opus 5's zero false positives being the property most at risk.

### 4.2 The exact `--ask` output

This text is the stage's product as much as the plan is. It is emitted verbatim by
`design-route <dir> --ask <ids>`; nothing in it is generated prose. *(The SETTLED values below are
A7's measured `nextjs.org` factpack, shown for shape — the real block is filled from
`factpack.json`.)*

```text
=== SETTLED — do not re-derive, do not re-check, do not comment on ===
The browser computed these. They are arithmetic, and disagreeing with them is a
defect in your answer, not in them.

  spacing : 4px base, 78.5% on-grid, 26 distinct values; off-grid: 1.2 2 3 6 10 14 18 19 21 25
  type    : 11 sizes (16px x1618, 14px x197, 20px x73 ...), 3 weights, 4 families
            -- 4th family "Inter" appears on 4 nodes beside GeistSans on 1978. Flagged.
  palette : 33 distinct; 2 outside the token file (#2B6CB0 dE 2.4 from --blue-600)
  contrast: 99 text runs measured, 13 WCAG failures, worst 3.01:1 (listed in FINDINGS)
  targets : 72 interactive, 36 under 24px, smallest link "Docs" 33x20
  clipping: 1 subtree -- nav link text 76px inside a 66px box, overflow hidden
  edges   : 142 shared left edges; strongest columns at x = 120, 145, 221, 550

=== FINDINGS ALREADY MADE (14) — cite by id, do not restate ===
  F01 high  contrast        button.primary        3.01:1 vs 4.5:1 required
  F07 high  overflow        nav > a:nth-of-type(3) text clipped, 76px in 66px
  ... (compact form, ~70 chars each)

=== YOUR QUESTION ===
You are looking at ONE page of reso-management-app at 1440x900, light scheme,
captured at DPR 2 with the display scale pinned. Image 1 is the region at CSS
[24,612,700,440]. Image 2 is the whole viewport.

Answer ONLY these, and only from the pixels:

  1. HIERARCHY   - which element reads as the primary action, and is that the one
                   the page's content implies should be primary?
  2. GESTALT     - is anything grouped visually that is not related, or related
                   but not grouped?
  3. CONTENT-FIT - does any label, caption or heading promise something the render
                   does not deliver?
  4. SEMANTICS   - is there a control whose purpose a first-time user cannot
                   determine from what is on screen?
  5. READABILITY - is any content technically correct and still hard to read?
  6. REGION C2   - the backdrop under the text at [24,612,700,440] is a gradient,
                   so no single contrast ratio exists for it. At the LEFT end of
                   that text and at the RIGHT end, is the text legible? Answer
                   "legible" / "marginal" / "illegible" per end. Do NOT estimate
                   a ratio.

RULES
- Never state a distance, size, ratio, or coordinate. If your answer needs one,
  say which element and let the caller measure it.
- Name elements the way a person would ("the blue Save button, top right"), not
  by CSS path.
- If you see nothing wrong in a category, say "nothing" for that category. An
  empty answer is a real answer and is the expected one on a clean page.
- If you believe a SETTLED fact is wrong, do not argue -- emit
  DISPUTE <finding-id> <one sentence> and stop on that item.

Return JSON: [{"class":"hierarchy","verdict":"...","element":"...","confidence":"high|medium|low"}]
```

Four properties earn their words. **"Do NOT estimate a ratio"** exists because the measured failure
mode is a plausible number, not a refusal. **"An empty answer is the expected one on a clean page"**
defends the zero-false-positive baseline, which is the single most valuable measured property of
this judge and the one a leading question destroys. **`DISPUTE`** is the T4 trigger made explicit —
without a channel, a disagreement becomes an argument inside a free-text answer that nothing parses.
**Element naming in human terms** is what makes the answer actionable by an agent that will then
resolve it against the DOM itself.

### 4.3 Assembly pseudocode

```python
def plan(d: PerceiveDir, ledger: Ledger, opts) -> RoutePlan:
    assert_inputs(d)                                     # §1.1 -> exit 2

    if not d.has("findings_dom.json"):                   # absent != empty
        return refuse(3, layers={"dom": "unavailable"}) if d.dom_expected \
               else no_dom_mode(d)                       # §6.1 T5

    settled  = d.findings_dom + d.findings_xcheck
    t1       = indeterminate(d.findings_dom) - resolved_by(d.findings_xcheck)
    t2       = ["hierarchy","gestalt","content-fit","semantic-coherence",
                "optical-alignment","readability"]       # unconditional, page-level

    calls = [Call("C1", kind="global", image=d.page_png,
                  vt=visual_tokens(*raster(d.page_png)), asks=t2)]

    for i, c in enumerate(regions(t1, [], d.snapshot), start=2):
        box = bleed(c.css_box, 16)
        if not fits(box):                                # §3.3 three ceilings
            calls[0].asks.append(fold_into_global(c)); continue
        calls.append(Call(f"C{i}", kind="region",
                          image=d.clip_request(box),     # P2 re-clips; ROUTE never rasterises
                          vt=visual_tokens(*raster_of(box)), css_box=box,
                          from_=[f.id for f in c.findings], asks=[f.rule for f in c.findings]))

    need = sum(1 for _ in calls)
    if ledger.used + need > CEILING:                     # §3.1
        return split_to_subagent(calls, opts.spawn_handle) or refuse(4)

    write(d/"route-plan.json", RoutePlan(calls, settled=len(settled),
                                         unrouted=dropped, coverage=cov))
    write(d/"route-steps.sh", steps(calls))              # region crops first, page last,
    return plan                                          # then ONE `--ask` Bash call
```

`d.clip_request(box)` writes a request file rather than a PNG. **ROUTE never opens a browser** — a
crop taken in a second browser pass is a different frame (fonts, animation phase, scroll-reveal
state), and A9 R10's rule generalises: never argue two images from different capture passes.

---

## 5. Worked token budget — one real page

**Subject:** `reso-management-app` `/dashboard`, 1440×900, DPR 2, `colorScheme: light`. 14
deterministic findings, one surviving `contrast-indeterminate` cluster at CSS `[24,612,700,440]`.
Visual tokens are **exact** (`⌈w/28⌉ × ⌈h/28⌉`); text tokens are **estimated** at ~1 per 3.3 chars.

| # | Block | Raster | Arithmetic | Tokens | eff |
|---|---|---|---|---|---|
| 1 | route directive (text) | — | ~200 chars | **60** *(est.)* | — |
| 2 | `clip/C2@1464x944.png` — region, 16 px bleed | 1464×944 | 53 × 34 | **1,802** *(exact)* | **2.00×** |
| 3 | `page@1440x900.png` — clamped 2880×1800 → 2000×1250 | 2000×1250 | 72 × 45 | **3,240** *(exact)* | 1.39× |
| 4 | `--ask` SETTLED block (factpack, compact) | — | 3,073 B | **854** *(measured)* | — |
| 5 | `--ask` FINDINGS block, 14 × ~70 chars | — | 980 B | **297** *(est.)* | — |
| 6 | `--ask` QUESTION block (§4.2 verbatim) | — | ~1,900 B | **580** *(est.)* | — |
| | **stage input total** | | | **6,833** | |
| 7 | judgement JSON out, 6 classes | — | — | **~450** *(est.)* | — |

**The counterfactual, priced.** The shape this stage exists to prevent — one tall full-page shot,
plus a standing annotated overlay, plus verbose findings, no factpack:

| Block | Raster | Tokens | eff |
|---|---|---|---|
| full-page 1440×2500 @2 → clamped 1152×2000 | 1152×2000 | 3,024 | **0.80×** |
| annotated overlay, same dims | 1152×2000 | 3,024 | 0.80× |
| findings in the full §3.2 shape, 14 × 397 chars | — | ~1,684 | — |
| **total** | | **7,732** | |

**13% more expensive for strictly worse evidence.** The full-page shot delivers 0.80× effective
detail — *worse than a plain DPR-1 viewport shot* — the overlay spends a second full image painting
rectangles over the subject of a visual critique, and with no SETTLED block the model re-derives
numbers it scored 0/2 on. Every token of the difference is spent on the two things the substrate
says not to buy.

**A whole-app sweep, and where it stops fitting.** `reso-management-app`, 8 pages, one global call
each plus the ~2 region calls the residue actually produces:

```
10 image blocks   (8 global + 2 region)   -> ledger 10/12, 2 left for the agent's own shots
29,520 visual tokens  (8 × 3,240 + 2 × ~1,800)
13,848 text tokens    (8 × 1,731)
~43,850 input tokens for the full app
```

So **one app fits one context and three apps do not.** A 20-page sweep across all three repos is a
three-subagent job by arithmetic, decided before the first call rather than discovered at block 21 —
which is the entire reason the ledger is a file and not a variable.

---

## 6. Degradation — argued in both directions, because the answers differ

Collapsing these two into one "fallback" policy is the actual defect. They are not symmetric.

### 6.1 Screen layer unavailable, model available → **usually refuse; and the discriminator is not "is it up"**

The tempting policy is: rules are down, let the model look at the screenshot and report what it can.
**Reject it for the ordinary case.** Blind Opus 5 scores 2/4 on DOM-determined defects with **zero
false positives** — and zero-FP is precisely what makes the fallback dangerous. It does not emit
garbage a reader would notice; it emits a *shorter list that reads exactly like a clean page*. That
is `fail-safe-default-mimics-the-healthy-state` with the consumer being an agent that edits source.

**The argument for the other direction, stated fairly.** A refusal has a real cost: a review that
produces nothing is worth less than a review that produces the two of four it can still see, and a
policy that refuses too readily gets routed around by a human in a hurry. That argument is sound —
but it is an argument for *labelling*, not for silence, and the label has to survive being copied
into a commit message.

**So the discriminator is not availability, it is whether a DOM exists to lose:**

| condition | policy | envelope |
|---|---|---|
| `screen_absent_by_failure` — the page has a DOM, the extractor crashed / CDP refused / manifest failed its assertions | **exit 3, refuse the review.** Do not call the model. | `ok:false, layers.dom:"unavailable", unavailable_why:"<the real error>"` |
| `screen_absent_by_nature` (T5) — canvas, WebGL, PDF comp, competitor screenshot, video frame | **proceed, model-primary.** Nothing was lost because nothing was available. | `ok:true, layers.dom:"n-a-no-dom", coverage.dom:"not-applicable"` |
| `screen_partial` — `findings_dom` ran, `findings_xcheck` did not | **proceed, and re-admit to T1 every abstention the cross-check would have closed** | `coverage.pixel:"unavailable"` and T1 grows — the one case where a *larger* model queue is the correct response to a layer outage |

The third row is the subtle one and it is where a naive implementation silently loses defects: if the
cross-check is down and T1 still subtracts `resolved_by(findings_xcheck)`, an empty file resolves
nothing *and looks like nothing needed resolving*. The subtraction must be gated on the file
existing, not on its contents.

### 6.2 Model unavailable, screen available → **never refuse; report the hole as a class, not a count**

Emit the screen's findings complete and exit 0. They are 9/9 with zero false positives and their
value does not depend on a judge. Refusing here would throw away a perfect instrument because a
different one is down.

**But the counter-argument is real and must be answered in the output.** With the judge missing, the
report is systematically biased toward *violations* and away from *does this page make sense* — and
that is exactly where the three uninjected defects lived (orphan legend, unlabelled icon button,
left-aligned numerics). A consumer reading a findings list with no judgement findings in it will
read "no judgement defects", not "judgement not attempted". Absence of a class is not absence of
defects in that class.

So the envelope names the unreached classes explicitly, by name, never as a number:

```json
{ "ok": true, "exit": 0,
  "layers":   { "dom": "live", "pixel": "live", "judgement": "unavailable" },
  "coverage": { "not_examined": ["hierarchy","gestalt","content-fit",
                                 "semantic-coherence","optical-alignment","readability"],
                "note": "no model call was made; these six classes are UNEXAMINED, not clean" },
  "findings": [ /* complete */ ] }
```

And the P6 report stage must render `not_examined` in the report body, not in a footer.
`zero-claim-must-name-its-excluded-strata` — a "0 open" that hides a blocked stratum reads as
all-done.

---

## 7. Per-app routing weights

One harness, three rule weightings. The router reads `--profile` and changes only which T2 classes
are asked and how many region calls a page may earn.

| app | stack | token source ROUTE resolves | T2 emphasis | `PER_PAGE_MAX` |
|---|---|---|---|---|
| `reso-landing-app` | Next 14, purchased template | `tailwind.config.js` *(verified present)* | `hierarchy`, `gestalt`, `readability` — a template's conformance is someone else's system; the question is whether the marketing page *works* | 2 |
| `reso-management-app` | Next 16 / React 19 / Tailwind 4 | `src/app/globals.css` `@theme` block *(Tailwind 4 is CSS-first; there is no `tailwind.config.*`)* | `semantic-coherence`, `content-fit` — conformance is the deterministic layer's job and it does nearly all of it here, so the model's budget goes to what rules cannot reach | **1** — the screen is strongest here, so the residue is smallest |
| `reso-web-app` | Next 13 | **UNVERIFIED** — no `tailwind.config.*` and no `@theme` found at the root; probe: `grep -rl "@theme\|theme:" src app --include=*.css --include=*.ts` | all six, unweighted | 2 |

A missing token source is not a soft failure: without it, factpack **B3 (palette vs tokens)** degrades
from a set difference to a histogram, and `token-drift` findings stop existing. ROUTE emits
`coverage.dom: "partial-no-token-source"` rather than letting the class silently empty.

---

## 8. What this stage cannot do

| ROUTE cannot | Consequence | Owner |
|---|---|---|
| Rasterise anything | every crop must come from the original browser pass, or two images from different frames get argued against each other | **P2 CAPTURE** — must accept a `clip_request` and re-clip *within the same pass*, not re-navigate |
| Know whether a finding is *true* | it routes abstentions and unscreenable classes; it never adjudicates | **P3/P4 SCREEN** |
| Verify that a judgement is correct | the model's answer is advisory by ratified decision; ROUTE only records DISPUTE | **the human** — taste stays human |
| Deduplicate findings | it inherits `(id, claim)` keys; keying on `(rule, target)` swallowed a real colour-token drift in the corpus | **P3 SCREEN** |
| See a defect it has no class for | the six T2 classes are a list, and a list is a bet | **P7 EVAL** — the corpus is the only instrument that can grow the list, and every added rule must re-run the clean control before shipping |
| Measure its own false-positive rate | a router that graded itself would key on its own signal | **P7 EVAL**, against the ~20% FP credibility floor |
| Control block ordering directly | it can only sequence tool calls (§4.1) | inherent to Claude Code; the `--ask` channel is the workaround, not a fix |
| Reduce a page below one model call | the T2 global call is unconditional | by design — cutting it makes the reviewer a linter with a screenshot |

---

## 9. UNVERIFIED, each with the one probe that settles it

| # | Claim | Probe |
|---|---|---|
| U1 | The >20 image-block cliff counts blocks **cumulatively across conversation history**, not per request. Sets `CEILING = 12`. | Scratch session: `Read` 21 distinct 1200×800 PNGs across 21 turns. Does turn 21 return an API error naming the image count? If no, `CEILING` rises to ~18. |
| U2 | Region-crop-before-page-shot beats the reverse ordering. | Run the 13-page corpus both ways with the §4.2 prompt fixed; compare the count of findings naming a wrong element. |
| U3 | The severity weights (2 / 1 / 0.5) rank clusters correctly. | Build a corpus page carrying three simultaneous abstentions at different severities and check the picked cluster is the one a human picks. |
| U4 | 966×966 CSS @2 is the true lossless square. Derived from published caps, never measured end-to-end. | Capture 1932×1932 and 1933×1933 rasters; `Read` both; ask the model to transcribe 6 px text in a corner. A step change between them confirms the tier boundary fires where the arithmetic says. |
| U5 | `reso-web-app`'s design-token source. | `grep -rl "@theme\|theme:" src app --include=*.css --include=*.ts` in that repo. |
| U6 | That splitting a sweep across subagent contexts preserves review quality — a subagent sees the brief, not the lead's accumulated page-to-page context. | Review the same 8 pages once in one context and once split 4+4; compare finding sets. Cross-page consistency findings ("this button is styled differently from the same button on /settings") are the class at risk, and if the delta is real, cross-page questions must be hoisted into a separate final call carrying no images at all. |

---

## 10. Threshold summary

| Constant | Value | Reason |
|---|---|---|
| `CEILING` | 12 image blocks / session | cliff at 20 fails by **rejection**; 40% headroom for the agent's own shots (U1) |
| `PER_PAGE_MAX` | 2 (1 profile: 1) | residue after screen + cross-check is empirically ~0; a 3rd need indicts the rules |
| `ARBITRATION_MAX` | 1 / page | a second disagreement is a rule defect to file, not an image to buy |
| `gap_px` (cluster merge) | 32 CSS px | 4 × the 8 px grid unit; one gap tier above 24 — merges a group without swallowing the page |
| crop bleed | 16 CSS px per side | includes the boundary the finding is *about* without importing a neighbouring group |
| lossless square crop | **966×966 CSS @2** (1932 px raster) | `⌈n/28⌉² ≤ 4784` ⇒ 69 patches; 1000×1000 CSS @2 = 5,184 tok, **over the tier** |
| crop admissibility | `⌈w/28⌉ × ⌈h/28⌉ ≤ 4784` ∧ `w,h ≤ 2000` ∧ `bytes ≤ 3,932,160` | API tier · client clamp · palette-quantisation threshold |
| T2 classes | 6, fixed | each is a measured defect class no rule reached |
| severity weights | 2 / 1 / 0.5 | ordinal tie-break toward `high` = {contrast, overflow, touch-target, indeterminate} (U3) |
