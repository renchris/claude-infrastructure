# The KPMG brand kit, as far as public sources establish it

Extracted 2026-08-08. Every value below carries a provenance tier. The full 400 KB research
corpus — ten axes, each with its sources and its open questions — is at
`lakehouse-lecture/docs/research/KPMG-BRAND-2026-08-08/`.

**Tiers.** **T1** = read out of a file KPMG itself serves or publishes. **T2** = strong secondary
(the foundry, design press, a brand book on a public host). **T3** = aggregator (frequently
wrong; corroboration only). **T4** = inference, labelled as such.

> **2026-08-09 — the governing source changed.** *KPMG Brand guidelines, March 2022* (publication
> 138005-G, 137 of 137 pages) was obtained in full. It is the rulebook the values below were being
> inferred toward, and it now governs colour, gradients, typography and accessibility outright.
> Read `docs/research/KPMG-SYSTEM-2026-08-08/BUILD-SPEC-FY22.md` first; per-page citations are in
> the eight `FY22-*` section files.
>
> Most of what follows survived contact with the book unchanged, which is worth stating — the
> palette, the hexes, the neutrals, the geometry and the contrast arithmetic were all right. Three
> things did not, and each is marked **superseded** in place below rather than deleted: the claim
> that no published KPMG accessibility standard exists, the three-typeface rule naming Univers, and
> the treatment of the extended palette as nine colours available for general use.
>
> **Two marks are used throughout, and the second must never be silently promoted to the first:**
> **[stated]** = the book's own words. **[measured]** = pixel measurement of the book's artwork,
> which is evidence of what KPMG did, not of what KPMG permits. The lesson that produced this
> distinction is in `S7-fy22-brandbook.md` § 3: *sampling outputs tells you what someone did; only
> the rulebook tells you what is allowed.*

---

## What is settled, what is contested, what is unknown

**Settled (T1).** The eight-colour primary palette and its hex values — **nine** counting Gray 1,
which the FY22 book prints as a brand colour and not merely as a neutral. The ~~nine~~ **eight**
-colour chart-only extended palette (the count was wrong; see below). The five-step neutral ramp. Slide geometry. The type system and the
Arial rule for PowerPoint. The identity of the display face. The current legal entity wording.
The footer's three-object structure and its measurements. Headline register.

**Contested.** The capitalisation of the brand line: KPMG UK sets `KPMG. Make the Difference.`,
KPMG US sets `difference`. Do not silently pick one. Heading case also splits by member firm —
UK is emphatically sentence case, US runs Title Case in its own navigation.

**Unknown, and not publicly obtainable.** ~~CMYK and Pantone for every colour except KPMG Blue.
Any published KPMG accessibility standard — none exists in public material.~~ Whether tints and
shades of brand colours are permitted. These live behind Brand Central
(`kpmgbrandcentral.brandwizard.net`), which is SSO-gated.

> **Superseded 2026-08-09, and this was the single worst entry in the file.** The FY22 book carries
> **CMYK for all twenty-one palette colours** (pp.51–52) and an **eleven-page accessibility
> appendix** (pp.126–136) in which KPMG publishes its own WCAG tables. Both are recorded below.
> Pantone is still given for two colours only, so that half of the sentence stands.
>
> The mechanism is worth keeping, because it will recur: "not found in public material" was a true
> statement about a search and was then filed as a fact about the world. It stayed filed for as
> long as nobody looked again. A negative provenance claim expires the moment a new source lands,
> and nothing in the file made that expiry visible.

> **The trap this document exists to prevent.** KPMG changed its palette in **2022**. Essentially
> every colour-aggregator site still serves the superseded pre-2022 values — `#005EB8`,
> `#0091DA`, `#483698`, `#C6007E`. Those return **zero hits** in KPMG's live stylesheet. A deck
> built from a colour picker is an off-brand deck, and nobody will be able to say why it looks
> wrong next to real KPMG material.

> **The same trap, aimed at this file.** The FY22 book is dated **March 2022** and is being used in
> **2026**. That is a four-year gap — shorter than the one that made the 2015 book dangerous, but
> the same kind of gap. Two current documents (a 2026 Luxembourg report, a 2023 India deck) are
> consistent with FY22, which is **evidence and not proof**. Whether KPMG UK deviates from the
> global book is likewise unestablished, and the engagement is UK. Treat the whole of this file as
> live-until-refuted, and if a newer edition surfaces, mark rather than rewrite — the record of how
> each error was found is what stops the next reader rebuilding it.

---

## Colour

### Primary palette — T1

Named source: a KPMG-hosted stylesheet whose own first line reads
`/* KPMG 2022 brand colours - CM Updated 2022-10-03 */`, recovered via web.archive.org and
byte-identical across snapshots 2023-02 → 2024-12.

**Provenance caveat, added after adversarial review.** That file is **KPMG Canada's** — its
path is `/content/dam/kpmg/ca/…` and every selector is prefixed `.ca-`. It is a member-firm
utility stylesheet, not a global token file. The palette nonetheless stands at T1 because the
**global** kpmg.com bundle carries the identical values, and because the logo SVG
(`fill="#00338d"`) and colour operators decoded from three KPMG report PDFs agree. But member
firms genuinely do diverge in usage, so the distinction is stated rather than elided.

**Name-collision hazard.** "Light purple" means `#6D2077` (dark aubergine) in the 2019 palette
and `#B497FF` (pale lavender) in the 2022 one. Always pair the name with the hex.

| Name | Role | HEX | RGB | CMYK | Pantone |
|---|---|---|---|---|---|
| KPMG Blue | Master brand; the logo; headlines on light | `#00338D` | 0, 51, 141 | 100/72/0/12 | **287 C** |
| Cobalt | Primary accent; now co-lead with KPMG Blue | `#1E49E2` | 30, 73, 226 | 100/60/0/0 | — |
| Pacific blue | Accent; chart series 3 | `#00B8F5` | 0, 184, 245 | 76/0/0/4 | — |
| Light blue | Tint; type and accent on dark | `#ACEAFF` | 172, 234, 255 | 20/0/0/2 | — |
| Purple | Accent; visited links | `#7213EA` | 114, 19, 234 | 80/90/0/0 | — |
| Pink | Accent; use sparingly | `#FD349C` | 253, 52, 156 | 0/94/0/0 | — |
| Dark blue | The dark ground | `#0C233C` | 12, 35, 60 | 100/76/12/70 | **289 C** |
| Gray 1 | Body copy; the ninth brand colour, not a neutral | `#333333` | 51, 51, 51 | 0/0/0/90 | — |
| White | Ground | `#FFFFFF` | 255, 255, 255 | 0/0/0/0 | — |

**CMYK and Pantone added 2026-08-09 from FY22 pp.51–52 [stated].** Pantone is given for **two
colours only** — KPMG Blue 287 C and Dark Blue 289 C — and the book says so deliberately: *"The use
of Pantone may be rare, with the exception of the logo color."* Do not go looking for the other
seven; they are not withheld, they do not exist.

Two rules travel with those numbers and both bear on a deck [stated, p.51]: the system is
**digital-first, RGB/HEX**, and *"an incorrect application of RGB colors in a CMYK document setup
can result in off-brand values"*; CMYK is **reserved for professionally printed material**. A PPTX
is an RGB document and should stay one.

Every chip on pp.51–52 was sampled at chip centre and compared to the printed hex: **21 of 21 match
within compression noise** (largest single-channel delta 1). The printed values are the real ones —
which is what makes the aggregator trap below diagnosable rather than merely suspected.

**Gray 1 is listed as a brand colour, not a neutral** [stated, p.52 — it appears in the Grays family
of the same specification table as the blues, and p.51 permits it for body copy alongside black].
The distinction matters only in one place: it is one of the seven **font** colours KPMG tests in its
own accessibility appendix, so it carries a published compliance record that a mere neutral does not.

**Cobalt is a co-equal primary — but KPMG Blue remains the most-used ink overall.** An earlier
draft of this document said Cobalt dominates; adversarial re-measurement across the full content
streams of three flagship documents refuted that as one document generalised to the system:

| Document | `#00338D` | `#1E49E2` |
|---|---|---|
| Transparency Report FY25 (KPMG International) | **285** | 100 |
| UK Insurance CEO Outlook (UK) | 98 | **121** |
| US CEO Outlook AM&PE (US) | **101** | 73 |

Cobalt outranks KPMG Blue in *some* current documents — notably the UK one — and by ~3:1 the
other way in KPMG International's own flagship. **Use both as primaries. A deck built on KPMG
Blue alone under-uses Cobalt; a deck that inverts them is equally wrong.**

**The dark ground is `#0C233C`, not `#00338D`.** Using the logo blue as a page background is a
common and visible error.

### Extended palette — chart and infographic use ONLY, T1

**Eight colours [stated, pp.48, 52, 53]:**

| HEX | The book's name | CMYK |
|---|---|---|
| `#76D2FF` | Blue | 42/0/0/4 |
| `#510DBC` | Dark Purple | 96/100/0/0 |
| `#B497FF` | Light Purple | 34/42/0/0 |
| `#AB0D82` | Dark Pink | 38/100/0/0 |
| `#FFA3DA` | Light Pink | 0/43/0/0 |
| `#098E7E` | Dark Green | 90/8/60/6 |
| `#00C0AE` | Green | 74/0/26/4 |
| `#63EBDA` | Light Green | 52/0/26/0 |

KPMG's own heading for these is "additional colours for infographics and charts". They are **not
brand colours** and must never appear as page furniture.

**Corrected 2026-08-09 — the list was nine and the ninth does not exist.** `#985AED` "med purple"
was carried here and is **named nowhere in the FY22 colour section**; the book's purple family is
`#510DBC` / `#7213EA` / `#B497FF` and no fourth step. Remove it from any palette file that holds
it. It is the same class of error as the pre-2022 aggregator values below — a plausible
interpolation between two real colours, which is exactly the kind that survives review.

**And the restriction is a stated prohibition, not a heading we inferred one from** [stated, p.53
rule 4]: *"Don't use secondary colors for type — the secondary palette is reserved for data."* The
book's rejected example is green headings. This is the sharpest rule in the section for a deck
builder, because **a colour here can be on-palette, perfectly legible, and still forbidden as a
field or as type** — `#63EBDA` on Dark Blue measures 10.92:1 and passes every contrast check that
will ever be run against it. No automated palette or contrast gate can see this. It has to be
carried as data on the colour itself.

Two more prohibitions from the same page bind a deck [stated, p.53]: *"Don't use gradients for
typography; gradients are only used for backgrounds"* (rule 3), and *"Don't use a competitive color
set i.e., Deloitte green, PwC reds, and EY yellow"* (rule 8) — the book's own worked example of the
last is Dark Blue ground with yellow type, which it says reads as EY.

**Traffic-light colours, presentation use only** [stated, p.52]: Red `#ED2124` · Yellow `#F1C44D` ·
Green `#269924`, *"only as necessary to indicate stop, caution, go"*. Note the name collision — this
Green is not the palette Green `#00C0AE`. Rule 7 forbids using them as a replacement for brand
colours.

### Neutrals — T1, and the part fan-made palettes always omit

| Name | Role | HEX |
|---|---|---|
| Gray 1 | **Body text.** The live `--text-color` token | `#333333` |
| Gray 2 | Secondary text, footnotes | `#666666` |
| Gray 3 | Chart axis labels | `#989898` |
| Gray 4 | Disabled state | `#B2B2B2` |
| Gray 5 | Rules, borders, **chart tracks** | `#E5E5E5` |

`#F5F6FA` is the correct off-white surface, but it is a **web UI colour, not a brand colour**.

All five greys are confirmed at T1 by FY22 p.52, with CMYK — Gray 1 `0/0/0/90`, Gray 2 `0/0/0/70`,
Gray 3 `0/0/0/50`, Gray 4 `0/0/0/30`, Gray 5 `0/0/0/10`. The book permits them *"as support in
infographics and charts"* and *"for information hierarchy within our system, such as to highlight
and separate content"* [stated, p.49] — so unlike the eight chart colours above, the greys are not
data-only. Gray 5 `#E5E5E5` is also the sanctioned light ground behind a portrait [measured, p.76].

### Colour proportion — the page-rhythm rule, and the only hard number in the section

The book prints its palette as stacked bands **whose heights are the intended proportions**, and
repeats the same chart three times (pp.43, 44, 48 — identical within 1 px, so it is the system
chart and not a one-off illustration). Measured by pixel run-length down the p.44 band column:

| KPMG Blue | Cobalt | White | Light Blue | Pacific | Dark Blue | Purple | Pink |
|---|---|---|---|---|---|---|---|
| **33%** | **33%** | 9% | 8% | 8% | 3% | 3% | 3% |

**Two blues carry two-thirds of the system** [measured, p.44]. The stated principle is that the
proportions are *"flexible; color use can shift within a given layout, but overall the system should
prioritize KPMG Blue/Cobalt Blue"*.

**The one number the book states in words** [stated, p.44]: *"Use Dark Blue, Pink and Purple in
small amounts (occupying **no more than 2-3% of color use at a time**) allowing us to keep our
priority blues the main focus."* The measured bands read 2.78 / 2.95 / 3.13 — the drawn ratio and
the written rule agree, which is the strongest form of confirmation available in a document like
this.

Two consequences a deck builder will hit immediately. **White is a counted colour at ~9%, not
whatever is left over** — but read that as white-as-applied-colour, since p.44's own annotation
says white *"is used extensively for type and backgrounds, and is the canvas for our clean
backgrounds"*. And **Cobalt and Light Blue are sanctioned type colours** [stated, p.44 — *"Cobalt
Blue can be used for type"*, *"Light Blue is also used for type"*]; any rule of ours that treats
KPMG Blue as the only permitted ink is stricter than the book, which is a defensible place to be
but should not be mistaken for compliance.

Where the proportion applies — a page, a spread, a document — is **never stated**. The book says
"within the system" and "overall". The safe reading for a deck is per-document, with the 2–3% cap
holding per slide.

### The two gradients, and inventing a third is forbidden

[stated, p.46] — specification, not observation:

| | Stops | Geometry |
|---|---|---|
| **Primary** | Purple `#7213EA` → Cobalt `#1E49E2` | 0% / 100%, midpoint 50%, 0°, linear |
| **Support** | Pacific `#00B8F5` → Light Blue `#ACEAFF` | 0% / 100%, midpoint 50%, 0°, linear |

**Never radial.** Flipping is permitted *"judiciously"*, and must maintain location and midpoint.
**Support never appears without primary**; support is **always opaque**; **the primary is the one
that interacts with imagery**. Gradients are never used for typography [p.53 rule 3] and never
behind graphs. The book's two example compositions put one gradient on the ground and the other in
the window — that is the page shape.

*(The p.46 artwork prints `Location: 0%` at both ends of both gradients, four times. It is a
slider-readout artefact; the body copy's 0%/100% governs, and the rendered swatches are opaque at
both ends.)*

> **Superseded — and this one was ours, made the same day it was corrected.** An earlier build
> extended the gradient-adjacency guard with four pairs sampled off member-firm documents —
> Purple→Pacific, Dark blue→Light purple, Cobalt→Dark blue, Deep purple→Light purple — under the
> argument that *"a refusal that meets a real observation is an out-of-date record, not a
> conflict."* **All four are disallowed by p.46, and three of the five original rows were
> unsanctioned too.** The reasoning is sound in general and was wrong here: a brand book is not a
> record of observations, it is the rule the observations are meant to follow. Generalising from a
> member firm's output is the precise error that produced the rejected deck in the first place —
> committed a second time, one layer down, inside the guard built to prevent it. The set is now the
> two gradients the book names, and nothing else. (`S7-fy22-brandbook.md` § 3.)

### Contrast — computed, and the half of the palette that is illegal as text

**KPMG publishes its own WCAG tables and commits to AA** [stated, pp.126–136]. This is the fact the
"unknown" entry at the top of this file got wrong for months, and it changes how every number below
should be read: these are no longer *our* contrast computations held against a standard KPMG never
named — they are, for the overlapping rows, KPMG's own published verdicts.

| | The book's answer | Page |
|---|---|---|
| Conformance level | **AA. Only AA.** p.129: *"the test results for AA for our five font colors."* | 128–136 |
| AAA | **Never mentioned anywhere in the book.** No AAA column, no AAA threshold, no aspiration to it. | — |
| What is tested | Three separate verdict columns — **normal text**, **large text**, and **graphical objects / UI components** (WCAG 1.4.11 non-text contrast) | 130–136 |
| Normal-text threshold | **4.5:1** — boundary rows confirm it: 4.64 Pass, 4.36 Fail | 130–136 |
| Large-text and graphical threshold | **3.0:1**, and the same number governs both columns — 3.11 Pass, 2.99 Fail. Across 100+ rows the two verdicts never disagree | 130–136 |
| "Large text" defined | *"14 point (typically 18.66px) and bold or larger, or 18 point (typically 24px) or larger"* | 68 |

The appendix is **foreground-first**: each of pp.130–136 fixes one *font* colour and walks it across
every background. The seven font colours are the entire set KPMG tests — KPMG Blue, White, Cobalt,
Light Blue, Dark Blue, Black `#000000`, Gray 1. (p.129 says *"our five font colors"* and then lists
seven; an internal miscount, one of several the appendix carries.)

**The book's arithmetic is correct.** Sixteen rows were spot-checked against an independent WCAG
relative-luminance implementation and reproduce the printed figure exactly — 2.88, 2.12, 2.35, 5.74,
12.08, 11.30, 6.76, 12.63, 15.89, 21.0, 5.14, 2.29, 2.38, 4.05 — with two rounding differences
(4.37 vs 4.38, 3.41 vs 3.42). So the tables below and KPMG's do not merely agree in verdict; they
agree in value. Where a pair appears in both, cite the book.

**A standing instruction sits outside the appendix and applies to everything here** [stated, pp.49
and 80, the same note box printed twice]: *"Always ensure that type color and background use are
compliant according to the accessibility requirements in your market. Type size should also be
considered when meeting accessibility requirements; required sizing can vary depending on the type
and background colors in use."*

Two independent implementations agree on these to within 0.005. **On white** — the "AAA" verdicts
are statements about WCAG, not about KPMG, which commits to AA and nothing above it:

| Foreground | Ratio | Verdict at body size |
|---|---|---|
| Dark blue `#0C233C` | 15.89 | AAA |
| Gray 1 `#333333` | 12.63 | AAA |
| KPMG Blue `#00338D` | 11.30 | AAA |
| Purple `#7213EA` | 7.01 | AAA, only just |
| Cobalt `#1E49E2` | 6.76 | AA |
| Gray 2 `#666666` | 5.74 | AA |
| Pink `#FD349C` | 3.42 | **large text only** |
| Gray 3 `#989898` | 2.88 | **FAIL at every size** |
| Light purple `#B497FF` | 2.38 | **FAIL** |
| Pacific blue `#00B8F5` | 2.29 | **FAIL** |
| Light blue `#ACEAFF` | 1.32 | **FAIL** |

**On Dark blue `#0C233C`:** white 15.89 · Light blue 12.08 · Light green 10.92 · Pacific blue
6.94 · Light purple 6.67 · Pink 4.65 · **Cobalt 2.35 FAIL** · **Purple 2.27 FAIL** ·
**KPMG Blue 1.41 FAIL**.

**On KPMG Blue `#00338D`:** white 11.30 · Light blue 8.59 · Pacific blue 4.94 · **Cobalt 1.67
FAIL**.

**On Pacific blue `#00B8F5` — treat it as a LIGHT ground, never a dark one.** Dark blue 6.94 ·
Gray 1 5.52 · KPMG Blue 4.94 · **white 2.29 FAIL**. White type on Pacific blue is illegal at
every size and is the single easiest mistake to make with this palette.

**Two deliberate consequences encoded in `brands/kpmg.json`:**

1. The `faint` role maps to Gray 2 `#666666`, not Gray 3 `#989898`. KPMG uses Gray 3 for muted
   text; at 2.88:1 it fails AA at every size, and a source line nobody can read is not a source
   line. Gray 3 is kept for non-text marks only. **This is the only deviation from KPMG's own
   palette in the file, and it is deliberate.**
2. The accent inverts on dark grounds — Light blue rather than Cobalt — because the mid blue on
   the dark blue ground is illegal.

> **Both records stand, and the first one is now stronger, not weaker.** The FY22 appendix prints
> **2.88:1 as a Fail in all three columns itself** — p.131, the White font-colour table, white type
> on a Gray 3 field; contrast is symmetric, so it is the same number this file computed. The book
> likewise prints 2.12:1 (Gray 4) and 2.35:1 (Cobalt on Dark Blue) as Fails of its own accord.
>
> So the *refusal* is compliance, not deviation. Anything previously logged as "a deviation from
> KPMG on accessibility" was mis-filed: **KPMG agrees the pair fails.** The genuine deviation is
> only ever the **replacement value we choose** — here, Gray 2 `#666666` at 5.74:1, which KPMG's
> own p.131 also prints as a Pass. Consequence 2 is the same shape: the book prints Cobalt-on-Dark
> Blue at 2.35:1 Fail, so inverting to Light Blue is following KPMG, and only the specific
> substitute is ours.
>
> This is a better position to be in than the file previously claimed, and it is worth being precise
> about why: a deviation costs an argument every time it is questioned, and three of ours turned
> out not to be deviations at all.

**One place the book contradicts itself, and a deck has to pick.** p.68 restricts Cobalt-on-white
to 18 pt and above, while the appendix's own Cobalt table (p.132) scores that pair **6.76:1, Pass
for normal text**. The appendix is the measured instrument and the later, more specific statement;
p.68 is a prose caution. **Follow the appendix, and treat p.68 as advice that happens to agree with
the projection rider below** — at 6.76:1 Cobalt body copy is legal and still not a good idea in a
lit room.

**Projection caveat.** WCAG assumes a screen. A conference projector in a lit room loses a great
deal of contrast. Treat 3.0 as the legal floor and **4.5 as the practical one** for anything a
140-person room has to read.

### Data visualization — T1, observed in three KPMG reports

Series order: **KPMG Blue → Cobalt → Pacific blue → Purple → Light purple.** Bars sit on
`#E5E5E5` tracks with `#989898` axis labels. The `accent1`–`accent6` mapping in the brand file
follows this order, so a native chart comes out in KPMG's sequence with no configuration.

**One stated rule governs the series, and it is about value rather than hue** [stated, p.53 rule 6]:
*"Don't use all-light tones or all-dark tones within infographics and charts; ensure you mix light,
mid and dark to achieve good contrast and legibility."* The order above satisfies it by accident —
check any series you add against it deliberately.

**The `#989898` axis labels are the one place this file still sets type in a colour it elsewhere
refuses.** At 2.88:1 on white they fail AA at every size, by KPMG's own p.131. Axis labels are small
text in a lit room, which is the worst case, not an exception to it. Use Gray 2 `#666666` (5.74:1,
a Pass on the same page) and keep Gray 3 for the non-text marks it was reserved for.

---

## Typography

~~**KPMG's own rule, verbatim (T1):** *"We use three typefaces for communications: KPMG Font,
Univers and Arial. KPMG Font is used for headlines. Univers is used for subheads and body copy.
**Arial is used for subheads and body copy in PowerPoint**, Word, e-communications and
websites."*~~

~~**So Arial is not a fallback in a deck. It is the mandated face.** Setting a KPMG deck in Arial
is following the rule.~~

> **Superseded 2026-08-09 — the quotation is genuine and belongs to the previous system.** **Univers
> is gone.** FY22 names **KPMG Bold** for display, **Arial** for desktop and Office, and **Open Sans
> Condensed / Regular** for web and app. Univers was central to the 2015 book and appears nowhere in
> the 2022 one.
>
> And the conclusion drawn from the old quotation was the wrong shape. FY22 splits the PowerPoint
> faces **by role** [stated, p.58]: **KPMG Bold for headlines, Arial for body copy**, Arial
> Italic/Bold for support. **Arial appears in a headline row nowhere in the book.** So setting
> display type in Arial is a **workaround forced by not holding the licensed face** — not
> compliance. State it that way rather than citing the guidance as permission. The rest of the old
> reading survives: Arial for body copy in a deck is exactly right, and is what KPMG specifies.

**The stated type scale — desktop** [stated, p.63]:

| Level | Face | Size |
|---|---|---|
| Headline | KPMG Bold | 48–60 pt |
| Subheadline | KPMG Bold | 24–30 pt |
| Lead paragraph | Arial / Arial Bold | 14–20 pt |
| Body | Arial / Arial Bold | 8–12 pt |

**Sentence case only; left-aligned only** [stated three times — pp.61, 63, 69]: *"The KPMG style is
sentence case for all copy; we do not use ALL CAPS or Title Case"* · *"All type within our
communications should be set left-aligned"* · *"Don't center type and do not right-align type."*
**A centred title slide violates this**, and so does a Title Case headline. It is the only
orthographic rule in the book, and it sits inside the typography section rather than the voice
section — which is why a search of the voice pages misses it.

**No leading, line-height, tracking, measure or ragging is specified anywhere in the book**
[absent]. Everything this package holds on those is inferred and must stay labelled as such.

**The "KPMG Font" is Giorgio Sans, rebadged (T1).** The load-bearing proof is that
`KPMG-Extralight` and `GiorgioSans-Extralight` appear embedded in the *same* KPMG file sharing
**byte-identical hinting parameters** (BlueValues `[-5, 0, 567, 572, 678, 683]`, OtherBlues
`[-95, -90]`, StdHW 22, StdVW 25) — reproduced independently. An earlier draft also cited a
*"Giorgio is a trademark of Commercial Type"* string in `KPMG-Bold`; that was **not
reproducible** on re-extraction (subsetting strips name records) and should not be cited. The
CFF Notice `© 2009 Commercial Type.` is present. It is a licensed commercial face.

**You cannot embed the brand faces — for a simpler reason than an earlier draft claimed.**
That draft asserted OS/2 `fsType = 0x0004` (*Preview & Print only*) enforces it. Adversarial
re-measurement read **three different fsType values for the same family across three documents**
(`0x0008` editable on KPMG-Bold, `0x000E` — malformed — on Univers), which is not three licences
but evidence the measurement is invalid: these are *subset* fonts regenerated by
Distiller/InDesign, which rewrites OS/2. A licence conclusion must not rest on it.

The real reason is stronger and needs no EULA analysis: **KPMG Font and Univers for KPMG are
proprietary cuts not licensed to us at all.** We cannot embed them because we do not have them.
Use Arial, which KPMG's own guidance mandates for PowerPoint anyway.

**The dating risk, and it is the sharpest fact on this axis.** The display weight flipped from
Extralight to **Bold** between 2019 and 2023. Documents up to 2019 embed `KPMG-Extralight` with
nothing bolder; every document from 2023-10 onward embeds `KPMG-Bold` and no light weight at
all. **A deck set in hairline display type will look a decade old.**

**Measured type scale (T1, read from content streams):** cover title **88pt**, slide H1
**44–45pt**, subhead **22pt**, body **11–14pt**, footer **6–7pt**, page number **~10pt**. Cover
titles are left-aligned with **negative leading — 73.9pt on 88pt type, a ratio of 0.84**.

*Demoted, not withdrawn.* These are real measurements off the CEO-Outlook **report** family — one
genre, at document density, and now outranked by the stated p.63 scale for any question the book
answers. Keep them for the two things the book does not state: the **negative-leading ratio**, which
is the only evidence we have on display leading at all, and the footer and page-number sizes. Note
that the measured H1 of 44–45 pt sits **below** the book's stated 48–60 pt headline range — a report
sets smaller than a slide, which is what you would expect and is worth remembering before citing a
report measurement at a deck.

> **One deliberate deviation.** KPMG's measured 11–14pt body is *document* density — correct for
> a deck read at a desk, far too small for a 140-person room. This package holds a **14pt floor
> and a 20pt body**. Stated rather than silently applied.

---

## Deck anatomy

**Geometry: 13.333 × 7.5in = 960 × 540pt = 12192000 × 6858000 EMU.** Measured identically on
eight KPMG decks from four member firms, 2022–2025. Zero instances of the old 10 × 5.63in 16:9.
A minority A4-paper geometry (10.833 × 7.5in) exists for brochure-style decks; it is not 16:9.

**Margins: ~78.5pt (1.09in, 8.2% of width), symmetric.** Noticeably wider than instinct suggests,
and that air is part of why the house style reads as composed. Reserve the bottom ~45–50pt for
the footer band.

> **The book's own slides run tighter, and the two numbers do not reconcile.** Every element on the
> nine PowerPoint slides of FY22 p.113 starts between **x 0.023 and x 0.055** of slide width —
> 22–53 pt on a 960 pt slide, against the 78.5 pt measured off shipped member-firm decks. Both
> measurements are sound; they are measuring different things. The book expresses the margin as
> **1 × the KPMG logo's height** rather than as a page percentage, so the brand-book exemplars are
> set to that rule and the shipped decks are set wider. This package holds 78.5 pt; that is a
> choice for a 140-person room, and `composition.md` § The window carries the logo-height system it
> departs from.

**The footer is three separate objects and it is the compliance surface (T1, two decks agreeing
to sub-point precision):**

| Element | Position | Size |
|---|---|---|
| KPMG logo | x = 79.0pt, 38.5 × 15.5pt | — |
| Copyright + entity sentence | x = 148.5pt, indented clear of the logo | 6–7pt Arial |
| `Document Classification: KPMG Public` | x = 749.3pt | 6pt |
| Page number | right ink edge 79pt from the right | ~10pt |

Numbering is plain arabic — no "Page", no "of N". The **cover is not numbered** and numbering
begins at 2. The **back cover carries the classification but no number**.

**The footer is not carried by every slide.** FY22 p.113 shows logo-and-footer as two mutually
exclusive states — a cover or statement slide carries the logo top-left and **no footer at all**;
a content slide carries the footer and **no top-left logo**. Never both. The rule and the measured
band positions are in `composition.md` § Furniture.

**The classification string is a value, not a constant.** The structure above is right; the word
varies with the document. KPMG's own brand-book slides read `Document Classification: KPMG
Confidential`, our reference decks read `KPMG Public`. Set it to what the document actually is.

**The entity sentence, current form — getting this wrong is a real compliance error:**

> *…a member firm of the KPMG global organization of independent member firms affiliated with*
> ***KPMG International Limited, a private English company limited by guarantee.***

The superseded form — *"KPMG International Cooperative ("KPMG International"), a Swiss entity"* —
was still in KPMG's own decks in July 2020 and is wrong now. KPMG International Limited was
incorporated 2020-02-20, UK company number 12474966.

`{member_firm}` and `{firm_form}` **vary by member firm and must not be guessed**: "KPMG LLP, a
Delaware limited liability partnership" (US); "KPMG Phoomchai Business Advisory Ltd., a Thai
limited liability company" (Thailand).

---

## Voice

**A KPMG headline is a claim with a verb, not a topic label.** Of 160 current KPMG International
press-release headlines: **0 are questions**, 46% carry a finite verb, 35% carry a digit, median
10 words. *"Payments sector sees smaller number of bigger deals in 2025"* is the house form;
*"Payments overview"* is not a KPMG headline at all.

> **The median is right for the corpus it came from and wrong for a slide.** Real slide headlines
> in the FY22 book run **2–12 words, median 3** [measured, 13 exemplars]. The constraint is
> typographic, not editorial: 48–60 pt type will not hold ten words. Carry the *form* from the press
> releases — verb-led claim, never a topic label, never a question — and the *length* from the
> slides.

**The book's three voice principles** [stated]: **Smart, Clear, Confident**. Two consequences that
bear directly on a teaching deck. Headline questions are a body-copy device, **not a headline
form**, which corroborates the zero-questions measurement above from the rulebook side. And the
book's insight checklist explicitly rejects the **instructional register** — *"Companies should
invest in…"* — which is precisely the register a teaching deck reaches for by default. Terminal
periods follow grammar, not house preference.

**Sentence case for headings**, with every apparent exception resolving to a proper noun — but
this splits by member firm. KPMG UK is emphatically sentence case; KPMG US runs Title Case in
its own navigation. Pick the register of the firm you are presenting into and hold it.

**Current lines:** brand line `KPMG. Make the Difference.` (capitalisation contested, see above);
purpose `Inspire Confidence. Empower Change.` Both are live and do different jobs.

---

## Governance — read this before shipping anything

Two findings from the public terms, and they change what you build rather than merely annotating
it.

**1. The rejection risk is inverted.** The danger is not being insufficiently on-brand — it is
being **too** on-brand. A deck carrying the KPMG logo, the brand line, and KPMG's copyright *is*
a KPMG-branded artifact produced by an unlicensed third party that never went through brand
review. Rejection triggers: the logo anywhere; the brand line used as your own; KPMG's copyright
on your slides; cover architecture close enough to be mistaken for a KPMG report.

*The design instruction that follows:* make the deck **compatible** with the room and **legible
as yours**. Palette, type discipline, sentence case, restrained register — yes. Logo and brand
line — no. Your own mark on the cover. This is what `licensed=False` does, and why it is the
default.

**2. kpmg.com's terms prohibit AI/ML use of Site materials (T1).** The clause expressly forbids
using Site materials *"for any machine learning or artificial intelligence purpose, including
without limitation training, retraining, fine-tuning, evaluation, inference, or generation of
outputs"*, and separately prohibits automated scraping.

*The clean path, and it costs almost nothing:* derive the **style** — sentence case, verb-led
headlines, the register, the date format. Style is not copyrightable and carries no risk. **Do
not reproduce KPMG page content, report text, statistics or imagery in a deck.** If a KPMG figure
is genuinely needed, cite it as any publication would. And do not demo an agent scraping kpmg.com
live on stage.

**Implied endorsement is separately prohibited.** No "in partnership with KPMG", no
"KPMG-approved". Safe framing: *"Delivered at KPMG Lakehouse, September 2026"* — a statement of
fact about place and date.

*This is research, not legal advice. For anything consequential, get a real view.*
