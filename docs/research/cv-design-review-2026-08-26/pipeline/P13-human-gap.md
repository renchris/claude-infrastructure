# P13 — THE HUMAN GAP

**Stage owner:** `bin/cv-gap` (plain CLI, JSON to disk — same surface rule as every other stage).
**Position:** bookends the pipeline. `cv-gap enumerate` runs **before P1 CAPTURE**; `cv-gap label`
runs **after P7 ARBITRATE** and owns the last bytes of every report.
**Date:** 2026-08-26 · **Substrate:** `../README.md`, `../agents/A15-hostile-review.md` (M1, M2,
M5, M6, M7), `../agents/A12-prior-art.md` (§ii.3, §c), `../agents/A8-aesthetic-saliency.md`
(saliency + the anchor rule), `../agents/A13-corpus-audit.md` (row 25, the never-written yardstick),
and hard reads of the three target repos taken today.

**The framing this stage refuses.** A gap analysis that ships as prose is the exact failure A15
names: *"it sees fine, critiques plausibly, and nothing improves."* So the gap analysis ships as an
executable. P13 detects nothing. It does two things a detector cannot: it **enumerates the review
surface** so the pipeline knows what it never photographed, and it **stamps every report with what
was not looked at**. A pipeline that cannot say what it did not see is not advisory, it is
misleading — and the June 2026 ruling (*taste stays human; gates adjudicate correctness/coverage
only*) makes coverage this stage's charter, not an afterthought.

---

## 0. CONTRACT

### 0.1 Invocation

```bash
# PHASE A — before P1. Reads the repo, not the browser. No network, no Chromium.
cv-gap enumerate --repo /Users/chrisren/Development/reso-management-app \
                 --app reso-management-app \
                 --out out/surface.json

# PHASE B — after P7. Reads the run dir, never re-opens a page.
cv-gap label --run /tmp/dp-a1b2 \
             --surface out/surface.json \
             --intent  docs/design-system/ \
             --suppressions .design-exceptions.jsonl \
             --out /tmp/dp-a1b2/coverage.json

# PHASE C — after a fix lands. The only honest second-order check.
cv-gap regress --before /tmp/dp-a1b2 --after /tmp/dp-c3d4 --commit 9f21c0a
```

### 0.2 Inputs

| | Input | Type | Required | If absent |
|---|---|---|---|---|
| I1 | `--repo` | path to a Next.js app root | phase A | exit 2. There is no browser-only path to absence. |
| I2 | `--run` | a completed P7 run dir (`findings/`, `run.json`) | phase B | exit 2 |
| I3 | `--intent` | dir or file: the app's own design-intent artifacts | phase B | **`intent: null` in output and a `NO-ORACLE` banner — never a silent default to the model's priors** (A12 §ii.3) |
| I4 | `--suppressions` | JSONL in the **repo**, not the tool | phase B | treated as empty; every finding is `new` on the first run, which is correct and loud |
| I5 | `--task-map` | `{route: "one sentence naming the user's job"}` | optional | the task-fit question is **not asked**, and is listed as unreviewed |

### 0.3 Outputs

| | Artifact | Consumer |
|---|---|---|
| O1 | `surface.json` — the (route × auth × data-state × viewport × theme) universe, plus the **absent-artifact ledger** | P1's `--states`, and the coverage denominator |
| O2 | `coverage.json` — reviewed/total per axis, per-gap reachability verdicts, suppression outcomes | P7's report renderer |
| O3 | **the `UNREVIEWED` block** (§9) — plain text, prepended to any human- or agent-readable report | the acting agent, and the operator |
| O4 | `regress.json` — findings present in `after` and absent in `before`, keyed to the fix commit | the agent that made the fix |

### 0.4 Exit codes

`0` clean · `2` bad input · `3` **coverage floor breached** (a declared axis has 0 captures — §2.3)
· `4` a suppression's falsifier fired (a deliberate exception is no longer deliberate — §7.3).
**Never a design verdict.** P13 cannot fail a build for taste; it can fail one for *lying about
coverage*, which is a correctness claim and therefore inside the June ruling.

### 0.5 What P13 must never do

No finding, no score, no severity, no ranking. Every sentence it writes is either a count over an
enumerated set or a verbatim quote from an on-disk artifact. The moment it produces an opinion it
becomes the eighth detector and stops being the auditor of the other seven.

---

## 1. GAP — reviewing against intent and brand rather than rules

**What the designer does.** Asks whether the screen is *this product's* screen. Not "is 4.5:1 met"
but "is this the register we chose". The rule set is downstream of a decision the rules do not
contain.

**Verdict: REACHABLE, and it is the cheapest unbuilt thing in the pipeline — because it is an INPUT
problem, not a model problem.** Measured today: `reso-management-app/docs/design-system/` holds
`constraints.json` (128 lines, generated seed), `CONSTRAINTS.md` (58 lines, "paste-ready", explicitly
authored as a prompt block) and `VOICE_AND_CONTENT.md` (127 lines). 313 lines total, ≈2.9k tokens.
**No stage in P1–P8 reads any of them.** P6-PROMPT's input table has `app_profile: landing |
management | web` — a three-valued enum standing in for a document that already exists on disk. A12
§ii.3 is unambiguous: *"Nobody who ships lets the model supply the standard from its own priors."*

**Mechanism.** Add one slot to the P6 gestalt and adjudicate templates, resolved by P13:

```jsonc
"intent": {
  "source": ["docs/design-system/CONSTRAINTS.md", "docs/design-system/VOICE_AND_CONTENT.md"],
  "sha256": "…",                       // so a stale critique is detectable after the doc changes
  "verbatim": "<the file bytes, unsummarised>",
  "operator": "door staff working a dark, loud nightclub at the rope, under social \
pressure, reading at a glance"          // VOICE_AND_CONTENT.md line 7, quoted not paraphrased
}
```

Verbatim, never summarised: a paraphrase of the standard *is* the model supplying the standard from
its priors, one indirection later. 2.9k tokens against a 1,100–1,600-token screenshot is affordable
by the same argument the README already makes for the 854-token fact-pack.

**The per-app split, and it is not uniform** (A15 M7, confirmed by today's reads):

| App | Intent oracle on disk | P13 verdict |
|---|---|---|
| `reso-management-app` | `docs/design-system/*` + `panda.config.ts` + `src/mc-tokens.generated.ts` | **REACHABLE NOW.** Ship the slot. |
| `reso-landing-app` | `tailwind.config.js` only — the purchased "radiant" template *is* the oracle | **REACHABLE as drift**, not as conformance: the reference is a baseline render, so this routes to P7's `control_hash` lane, not to a prompt. |
| `reso-web-app` | nothing found | **OUT OF REACH until a human writes 20 lines.** P13 emits `NO-ORACLE` and every judgement finding on this app is labelled *unanchored*. |

**Honest limit.** The never-written north-star yardstick (`DESIGN_PAGE_METHODOLOGY_PHASE1B_NORTHSTAR.md`,
A13 row 25 — absent, no add-commit in `git log --all`) is the same class one level up: the campaign
ratified that you cannot design without it, then closed without producing it. P13 cannot mint it. It
can only turn its absence into a printed line — the difference between an unanswered question and an
unasked one.

---

## 2. GAP — noticing what is ABSENT

**What the designer does.** Sees the state nobody built. A screenshot cannot contain the evidence,
because the evidence is a page that was never rendered.

**Verdict: SPLIT, and the split is the sharpest decision in this stage.** Absence has two species
with different reachability, and conflating them is why the pipeline currently has neither.

### 2.1 Enumerable absence — REACHABLE, deterministically, at 100% recall and 0 FP

A state the *framework has a name for* is a filesystem question, not a vision question. Next.js App
Router names them: `loading.tsx`, `error.tsx`, `not-found.tsx`, `global-error.tsx`. Measured in
`reso-management-app/src/app/(app)` today:

| Special file | Count | Against 16 `page.tsx` |
|---|---|---|
| `loading.tsx` | **0** | every route falls back to whatever the parent streams — no route in the product has a designed loading state |
| `error.tsx` | 2 | `bottle-service/[reservationID]`, `floor-plan` |
| `not-found.tsx` | 1 | `bottle-service/[reservationID]/[itemID]` |
| `global-error.tsx` | 1 | root |

That table is `find`, it costs milliseconds, it has no false positives *by construction*, and **no
stage in P1–P8 can produce it, because every one of them starts from a URL.** A15 M5 named the
missing owner ("nobody owns what gets photographed"); this is its cheapest half. The rule:

> For each route segment R with a `page.tsx`, and each state S in {loading, error, not-found}: if no
> `S.tsx` exists at R or any ancestor of R, emit `absent_state{route:R, state:S, inherits_from:<the
> nearest ancestor or null>}`. `inherits_from:null` ⇒ the state is genuinely undesigned; a non-null
> ancestor ⇒ it is *shared*, which is a design decision and merely reported.

Extend the same shape to any framework convention the repo declares — an `EmptyState` component that
exists (`src/components/_mission-control/EmptyStatePreviewPanel.tsx` does) but is imported by zero
route under `(app)` is the same finding in a different graph.

### 2.2 Unnameable absence — PARTIALLY REACHABLE, and Opus 5 already does it unprompted

The other species has no framework name: *there is no way to undo this*, *the caption promises grey
rows that do not exist*. That second one is not hypothetical — it is one of the three real defects
the blind Opus 5 pass found that nobody injected and no rule was looking for. **An orphan legend is
an absence finding**: the page asserts a thing, and the thing is absent. The capability is already
present at ~1 per 13 pages with zero false positives, and the pipeline currently gets it by accident.

Make it deliberate: a named branch in P6's gestalt template, worded so the model hunts a broken
*promise* rather than missing features generally.

```text
ABSENCE BRANCH — answer before you look for defects.
List every promise this page makes about content or state that the page does not keep:
a label, caption, legend, count, tab, filter, or heading that implies something the frame
does not show. For each, quote the promising text verbatim and name what is missing.
If a promise is kept, do not list it. If you are inferring a feature the product might
want, that is NOT a promise — do not list it.
```

The last sentence is load-bearing: without it this branch becomes a feature-request generator, and
a feature request is the highest-cost false positive available, because an agent will build it.

### 2.3 What is genuinely out of reach

**Recall on absence is not computable.** There is no denominator for the set of things that do not
exist, so no coverage number over §2.2 is admissible and P13 must never print one. §2.1 *does* have
a denominator (routes × named states), so it is the only absence claim allowed to carry a
percentage. Exit code `3` fires when a declared surface axis has zero captures — a coverage lie —
never when §2.2 returns empty.

---

## 3. GAP — does this page serve the user's task at all

**What the designer does.** Knows the job. "This is a door host at the rope with a guest in front of
them" is a fact that changes every verdict on the page, and it is nowhere in a screenshot, a DOM
snapshot, or a token file.

**Verdict: HUMAN-IN-THE-LOOP, and the human contribution is one sentence per route, authored once.**

Grounding for the pessimism: WebDevJudge puts humans at 84.82% and the best model at 66.06% on
whether an implementation actually serves a stated intent — an 18.8-point gap on the task where the
intent *was supplied*. Ours is not supplied at all: nothing in P1–P8's inputs carries a user goal.
Asking an unbounded "does this serve the user" invites the model to invent a user, and an invented
user rationalises whatever is on screen.

**Mechanism — declare the task, then ask a bounded question about it.** `--task-map`:

```jsonc
{ "/": "See which of tonight's reservations have not arrived, and seat a walk-in.",
  "/floor-plan": "Find a free table for a party of 6 in the next 30 minutes.",
  "/guests/[id]": "Decide whether to comp this guest, from their history." }
```

16 routes × one sentence is an afternoon, once. The prompt then asks only what a bounded question can
carry:

```text
TASK: "<the declared sentence>"
Answer exactly three things. (1) Name the single element that starts this task, and say
whether it is visible without scrolling. (2) Name every element on this page that is not
used by this task. (3) State one thing the task needs that this page does not show.
If the task cannot be started on this page at all, say so as your first word: CANNOT.
```

(1) is verifiable against P3's fact-pack (does the named element's `rect.y + h` fall inside the
first viewport height) — so it is a claim the pipeline can check rather than accept, which is the
only reason it is allowed. (2) is the honest form of "is this page cluttered" and needs no taste. (3)
is §2.2's absence branch narrowed by a task, which is where absence findings are most reliable.

**Without a `--task-map` entry, the question is not asked** and the route is listed in the
`UNREVIEWED` block as `task-fit: not declared`. It is never asked with an inferred task. The
inference is exactly the failure mode: a model that guesses the user's job will always conclude the
page serves it.

**What P13 cannot do here:** it cannot tell you the declared task is the *wrong* task. That is
product judgement and is not in any artifact on disk. It stays with the operator, permanently.

---

## 4. GAP — reading the page as a whole, pre-analytically, in one glance

**What the designer does.** Takes in the frame before parsing it, and knows within a second whether
the hierarchy works. This is not fast analysis; it is a different faculty.

**Verdict: REACHABLE IN PART, and — this is the second sharp decision — the mechanism is *not* the
VLM, and the pipeline's own crop-refinement strategy is actively hostile to it.**

Two measurements make the point. First, the specialist that wins is precisely the pre-semantic one:
UI-trained **UMSI++ scores CC 0.833** on early gaze against the best frontier VLM at **0.408** (Opus
4.6 0.344, Gemini 3.1 Pro 0.144), and the VLM *improves with longer simulated viewing* (0.217 at 1 s
→ 0.408 at 7 s) — backwards for the reflexive first second. The gap is mechanistic, not a scaling
artefact. So the unresolved UEyes/UMSI++ licence is not a nice-to-have; it is the gate on whether
this gap is reachable at all.

Second, the pipeline's best-evidenced lever fights it. Crop-refinement took ScreenSeekeR 18.9% →
48.1% with no model change, and **a crop destroys the glance by construction** — gestalt is a
property of the whole frame. Capture physics push the same way: a 2500 px-tall full-page shot
delivers 0.80× effective detail, so every detail question wants a crop.

**Mechanism — the squint pass.** Resolve the conflict by making it two passes with disjoint
authority rather than one compromise. P13 requires the run to contain a *deliberately degraded*
whole-page frame:

```bash
# from P1's archival master, not a re-capture
magick full@2x.png -colorspace sRGB -resize 512x -strip squint.png
```

**Why 512 px on the long edge, precisely.** At 512 px wide, a 1440 px CSS layout is scaled 0.356×, so
14 px body text renders at ~5 px — below the ~7 px threshold at which glyph identity survives, so
the frame carries block structure, mass, and colour and carries *no readable text*. That is the
property being bought: the pass cannot smuggle detail findings back in, because the detail is
physically absent. Token cost is `⌈512/28⌉ × ⌈890/28⌉ = 19 × 32 = 608` visual tokens — under half a
clamp-safe shot, so the squint pass is cheaper than the crop it complements.

The prompt for this pass carries a hard prohibition:

```text
This image is deliberately too small to read. Do not report anything that requires
reading text, and do not guess at any text. Answer only: what does the eye land on
first, second, third; where is the visual weight; is there a region that reads as
one block but is two things, or as two blocks but is one thing.
Any finding that names a specific number, colour value, or piece of text is invalid
here — say "needs the full frame" instead.
```

**UNVERIFIED.** Whether Opus 5's gestalt findings survive at 512 px. **The one probe that settles
it:** re-run the existing 13-page blind pass at 512 px long edge and compare against the recorded
baseline. The pass is real if the two judgement/gestalt defects (inverted action hierarchy, washed-out
text over a gradient) still land and the two sub-perceptual ones (1 px misalignment, 5/255 drift)
still miss. If the gestalt defects *also* vanish, the squint pass is a fiction and this gap reverts
to licence-blocked saliency alone.

---

## 5. GAP — a taste reference built from thousands of examples

**What the designer does.** Compares against an internalised library — thousands of screens seen,
ranked, argued about — and says "this is a 2019 dashboard".

**Verdict: the general reference is REACHABLE and already present; the operator's reference is
HUMAN-IN-THE-LOOP; the *score* is out of reach and must stay that way.**

The model already carries a large taste prior — the likeliest explanation for the three unprompted
real findings (orphan legend, unlabelled smallest-hit-target icon button, left-aligned numeric
columns). None is a rule violation; each is a judgement that the page does not match how such pages
are built. That capability is bought and paid for.

What it cannot carry is *this operator's* reference. Two supply routes, ranked:

1. **The repo's own history is the only in-distribution corpus that exists.** A15 M4's by-product:
   every visual regression caught, reverted or fixed is a free labelled example. Mine
   `git log -p --follow` over `src/components/_mission-control/` for commits whose message matches
   `fix\(.*(visual|design|layout|contrast|spacing)` and whose diff touches only style properties;
   each yields a before/after pair on a real screen of ours. This is the eval set A15 M1 says nothing
   downstream is meaningful without, and it is also the taste corpus.
2. **UICrit as a prior, never as an oracle** — 3,059 designer critiques over 983 screens, few-shot
   prompting yielding ~55% quality gains. Its distribution is mobile, ours is a dark desktop
   dashboard, so it calibrates the *form* of a critique (specific, located, one claim) and not its
   content.

**And the hard prohibition, which is the third sharp decision: taste enters as a paired delta against
a named reference render, never as a number.** A8: a number in the prompt *"becomes an anchor the
model rationalises around — the same vacuity with a citation attached."* The measurements agree from
three directions: rubric scoring shows **16–39% top-1 ranking reversals from reordering alone**;
order-invariant consistent accuracy is **~30–37%** against a 25% chance baseline; and absolute MLLM
design scoring runs 38% against 77% pairwise. V1 already died here, plateaued at **78/100 on a
self-assigned scale with no external referent**. P13 therefore refuses any run whose findings carry a
numeric aesthetic score, at exit `2`, before the report is rendered — the one place this stage has
veto power, and it is a correctness veto, not a taste one.

---

## 6. GAP — knowing which violations are deliberate

**What the designer does.** Recognises the intentional break. The one 44 px control that is
deliberately not on the 8 px grid because it aligns to something else.

**Verdict: FULLY REACHABLE, mechanically, and it is the highest-priority build in this stage —
because without it the pipeline dies of the death V2 already died.** V2 was built in a two-day burst
(commits `07bf25f40`, `8be4f3425`, 2026-03-21) and then shows zero substantive change in five
months. A reviewer that reprints the same standing findings every run carries zero information.

**Measured today: there is no channel for a deliberate exception in any of the three apps.** A grep
for `design-ok|@design-allow|design-lint-disable|design-exempt` across all three trees returns
nothing. Every intentional violation the pipeline finds will be re-reported forever, starting on run
two. Against a ~20% false-positive budget — the level at which an AI reviewer loses credibility
regardless of catch rate — a re-reported known-and-accepted finding spends the same credibility as a
wrong one, even though it was true.

**Mechanism.** A suppression store that lives **in the repo, beside the code**, because a deliberate
choice must travel with the thing it was deliberate about and die when that thing is deleted:

```jsonc
// .design-exceptions.jsonl — one object per line, appended, never rewritten
{"fingerprint":"sha1(route|selector|rule)",
 "route":"/floor-plan", "selector":"section.legend > button.icon", "rule":"target-size",
 "why":"36px is the tallest control that fits the rope-side one-hand reach zone; the 44px \
version pushed the table grid below the fold",     // REQUIRED, prose, no id-only entries
 "falsifier":"selector_absent | rule_span_changed | intent_sha_changed",
 "intent_sha":"…", "author":"chrisren", "opened":"2026-08-26"}
```

Three properties, each earning its place:

- **`why` is required and is prose.** An exception with no stated reason is indistinguishable from a
  finding someone got tired of. P13 rejects an entry without it (exit `2`).
- **It expires by falsifier, not by date.** `selector_absent` retires the exception when the element
  is gone; `rule_span_changed` retires it when the rule's claim changes underneath it — the
  assertion-span failure, which the corpus already reproduced live when a `(rule, target)` dedup key
  silently swallowed a real colour-token drift. A suppression keyed on a claim that has since changed
  meaning is a hole, not a decision. Firing a falsifier is exit `4`.
- **The default report shows only `new` + `regressed`.** P7 already fingerprints on
  `(route, selector, rule)`; P13 partitions each run's findings into `new · known · suppressed ·
  regressed · fixed` and renders the last three as counts only. `--all` shows the rest. Counting
  NOT-success is the operator's own alarm-polarity rule, and it is the difference between a report
  read on run twenty and one that is not.

**Limit:** the pipeline can never *infer* deliberateness. Every exception is authored by a human, one
line, at the moment they decide. P13 makes that line cheap and makes its absence loud; it does not
guess.

---

## 7. GAP — caring about the second-order consequences of a fix

**What the designer does.** "Raise that contrast and you break the tier hierarchy — gold stops
reading as special." The reviewer holds the whole system while judging one element.

**Verdict: OUT OF REACH as prediction. FULLY REACHABLE as verification — and converting one into the
other is the whole move.**

A model asked to forecast the downstream effect of a CSS change is speculating, and the ceiling
measurement is unforgiving: DiffSpot — *one property mutated, what changed* — tops out at **47.2%**
for the best of thirteen models, with hard-tier recall below 23% for every model and `line-height`
median recall at **4.0%**. That is the identical inference in the easier direction (the change is
shown, not hypothesised) and it is at chance for the hard cases. The prescribed-remedy-worse-than-the-bug
failure is not a hypothetical here; it is one of this operator's standing lessons.

**Mechanism — `cv-gap regress`.** Re-run the pipeline after the fix and diff the finding sets. Any
finding present in `after` and absent in `before` is a second-order consequence, attributed to the
fix commit, and reported as such. This is measurement, not prediction, and it is the only honest
form available.

The acceptance rule has to be wider than the fix, and this is where the failure hides:

> A fix is accepted only when, for **every** rule — not merely the one that was fixed — the `after`
> run's finding count is ≤ the `before` run's, **on every captured surface tuple**, not only the one
> the finding was on.

Both halves are load-bearing. Scoping to the fixed rule is the assertion-span failure: the fix that
raises one contrast ratio is exactly the fix that changes a token used in eleven other places.
Scoping to the one page is the coverage failure: §8's tuple universe is the denominator, and a fix
verified on one route is verified on one route.

A12's convergence table backs the shape — intrinsic iterate-until-satisfied *degrades*, while
iteration against an **external structural signal** converges (bbox IoU 0.120→0.357; a practitioner
report of UI-fix tasks going 10–15 iterations → 2–3 once the agent had live computed-style access).
The re-run *is* that external signal.

**Limit:** a consequence with no detector stays invisible. If nothing in P4 measures "gold has
stopped reading as special", the regression diff will be silent about it, and P13's coverage block
must therefore name the rule set the diff was computed over — a clean `regress.json` means *no
change on the rules we run*, never *no harm done*.

---

## 8. `surface.json` — the denominator, without which no coverage claim is meaningful

Phase A output. It exists because a review of the logged-out homepage at 1440 px reviews the
marketing screenshot, not the product (A15 M5).

```jsonc
{ "app": "reso-management-app", "git_sha": "…", "generated": "2026-08-26T…",
  "routes": [ { "path": "/floor-plan", "file": "src/app/(app)/floor-plan/page.tsx",
                "dynamic": false, "auth": "required",
                "states_declared": ["error"],            // from the filesystem
                "states_absent":  ["loading","not-found"],
                "task": "Find a free table for a party of 6 in the next 30 minutes." } ],
  "axes": { "viewport": ["1440x900","768x1024","390x844"],
            "theme": ["dark","light"],                    // both exist: constraints.json carries
                                                          // hex AND hexLight
            "data": ["seeded-busy","empty","error"] },     // "empty" is a state, not an edge case
  "tuples_total": 288,                                     // routes x viewport x theme x data
  "tuples_capturable_without_a_human": 96                  // auth+seed scripts that exist today
}
```

The two totals are separate on purpose. `tuples_total` is the honest denominator; the second is what
the pipeline can currently reach unaided. The ratio — not any recall figure — is the number that
tells the operator how much of the product has never been looked at.

---

## 9. The `UNREVIEWED` block — the shipped output of this stage

Rendered by P13, prepended verbatim to every report, generated from `coverage.json` with no prose
authored at report time. This is what "honestly labelling its own output where it cannot see" means
in bytes.

```text
UNREVIEWED — what this report did not look at
  surface     18 of 288 tuples captured (6.3%). Not captured: theme=light (0/144),
              data=empty (0/96), viewport=390x844 (0/96).
  intent      anchored — docs/design-system/CONSTRAINTS.md @ 4f1c…, VOICE_AND_CONTENT.md @ 9ab2…
  task-fit    asked on 3 of 12 routes; 9 routes have no declared task and were not asked.
  absence     named states checked deterministically (16 routes x 3 states).
              Unnamed absences are NOT measurable — no recall figure exists for this class.
  glance      squint pass RAN. Saliency: NOT RUN (UMSI++ licence unresolved) — no
              attention-mass claim in this report is measured; the model's own guess at
              gaze is CC 0.408 against a specialist's 0.833 and is not reported.
  precision   sub-perceptual defects (<2px offsets, <8/255 colour drift) are outside the
              judge's measured ability (0 of 2 on our corpus) and outside the DOM layer's
              (INDETERMINATE, not PASS). Nothing here clears them.
  suppressed  4 known-and-accepted findings hidden; 0 falsifiers fired. --all to see them.
  taste       NOT ADJUDICATED. No score is produced, by ruling (June 2026).
```

Three rules govern it. Every line is a count over an enumerated set or a named absent capability.
Anything the pipeline cannot verify says **NOT RUN** or **NOT MEASURABLE**, never nothing — the
fail-safe-default-mimics-the-healthy-state trap is the one this block exists to defeat. And it is
**prepended**, not appended: the operator's own close-message measurement is that a verdict placed
last is read after the decision is already made.

---

## 10. Ledger — the seven gaps, their verdicts, and who owns what P13 cannot

| # | Gap | Verdict | P13 builds | Owned elsewhere |
|---|---|---|---|---|
| 1 | intent & brand | **REACHABLE** (management), drift-only (landing), no-oracle (web) | the `intent` slot + `NO-ORACLE` banner | P6 carries it verbatim into the prompt; **a human writes web-app's 20 lines, and the north-star** |
| 2 | absence | **SPLIT** — named states reachable at 0 FP; unnamed partially, unmeasurable | the filesystem ledger + the promise-branch wording | P6 runs the branch; P1 photographs states P13 enumerated |
| 3 | task fit | **HUMAN-IN-LOOP** — one sentence per route | `--task-map` plumbing + the bounded 3-part question | operator authors the sentences; only they can say the task is *wrong* |
| 4 | the glance | **PART-REACHABLE**, not by the VLM | the 512 px squint frame + its prohibition prompt | P1 mints the frame; **saliency is licence-blocked and that licence is the gate** |
| 5 | taste reference | prior present; operator's reference human; **score out of reach** | the no-score veto (exit 2) + the git-mined pair corpus | P7 owns pairwise framing; taste stays human, permanently |
| 6 | deliberate violations | **FULLY REACHABLE** — and the priority build | `.design-exceptions.jsonl`, falsifiers, new/known partition | P7 supplies the fingerprint; a human authors each `why` |
| 7 | second-order | prediction **OUT OF REACH**; verification **reachable** | `cv-gap regress` + the all-rules/all-tuples acceptance rule | the agent re-runs; a consequence with no detector stays invisible |

## 11. UNVERIFIED, and the single probe that settles each

| Claim | Probe |
|---|---|
| Opus 5's gestalt findings survive a 512 px squint frame | re-run the 13-page blind pass at 512 px; the pass is real iff the 2 judgement defects still land and the 2 sub-perceptual ones still miss |
| 2.9k tokens of verbatim intent improves findings rather than anchoring them | run the corpus twice, with and without the `intent` slot, and count findings that quote a constraint the page does not violate — anchoring shows up as *confirmation*, not as noise |
| the promise-branch does not become a feature-request generator | run it on the clean control; any non-empty output on a page with no broken promise is an FP, and the branch ships only at zero |
| `git log` yields enough style-only fix pairs to be a corpus | count matching commits in `reso-management-app`; under ~40 pairs it is an anecdote, not an eval set |

---

**One-line summary.** P13 detects nothing and vetoes two things: a report that scores taste, and a
report that does not say what it never looked at. Of the seven things a senior designer does that
this pipeline does not, four are reachable today and three of those are reachable *without a model
call at all* — they were missed because every stage upstream begins at a URL, and the missing
faculties begin in the repo.
