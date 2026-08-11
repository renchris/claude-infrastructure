# W3 — Codex adversarial-slot probe: the judged grid and the verdict

**Date:** 2026-08-11 · **Plan:** `docs/plans/CODEX_ADVERSARIAL_SLOT_PROBE.md` § W3
**Inputs:** `tests/fixtures/codex-probe/` (9 briefs, 36 anchored ground-truth entries, 36 verbatim
arm outputs from W2) · **Deliverable:** ONE verdict for `roles.research_adversarial`, recorded in
`~/.claude/model-routing-freewin-probe.md` as T4.

**Scope (frozen):** score the 36 existing outputs, produce ONE verdict (ADOPT / SPLIT / REJECT),
record it in the routing ledger. Do NOT re-run the grid, do NOT flip `model-config.yaml` (W4 owns
that), do NOT edit the corpus.

---

## VERDICT — **REJECT** `gpt-5.6-sol` for `roles.research_adversarial`

**Not because it is worse. Because its findings are contained.** Over 36 anchored ground-truth
defects there is **not one** that a Codex arm caught and neither Claude arm caught — at *every*
vote threshold, including the most generous one possible (credit on a single judge's say-so). The
Claude family caught 3 that neither Codex arm did.

This is the plan's own REJECT criterion — *"Codex findings are a strict SUBSET of Fable's ⇒ REJECT,
a tie here is redundancy, not a free win"* — reached on the union rather than on the incumbent
alone, which is the stronger form:

| pairing for the slot | ground-truth defects caught |
|---|---|
| A alone (`claude-fable-5`, the incumbent) | 9 / 36 |
| A ∪ B (add `gpt-5.6-sol @xhigh`) | 11 / 36 |
| A ∪ C (add `gpt-5.6-sol @ultra`) | 12 / 36 |
| A ∪ B ∪ C (add *both* Codex arms) | 12 / 36 |
| **A ∪ D (add `claude-opus-5 @max` — already the slot's own fallback)** | **14 / 36** |
| A ∪ D ∪ B (then add Codex on top) | 14 / 36 — **+0** |

The decorrelation the slot exists to buy is real and it is worth buying. It is simply **not where
this probe expected to find it**: the biggest independent gain available to this slot comes from a
model already in the ladder, at no new vendor, no new quota bucket and no new sandbox. Adding Codex
*on top of* that pair moves coverage by zero.

**The corpus was tilted toward the candidate and it still lost.** Every brief is drawn from this
repo's `MEMORY.md` — defects a Claude-family model already missed once. That is the honest
population for this slot, and it is also a handicap on the Claude arms. The candidate had the
friendly field and returned no unique coverage on it.

---

## The panel

Four independent judges, mixed vendor, blind. Every judge saw the four arms relabelled `W/X/Y/Z`
under a **per-(judge, brief) permutation**, so no label is stable across judges or across briefs.

| judge | model | effort | role |
|---|---|---|---|
| JA1 | `claude-opus-5` | max | Anthropic-family judge |
| JA2 | `claude-opus-5` | max | Anthropic-family judge |
| JC1 | `gpt-5.6-sol` | xhigh | Codex-family judge |
| JC2 | `gpt-5.6-sol` | xhigh | Codex-family judge |

36/36 cells scored. Judges held repo access and were required to extract every cited line from the
real file at the brief's `pre_fix_ref` and compare byte-for-byte; default-to-refute; a finding that
matched a ground-truth *topic* but not its *mechanism* was explicitly not a hit.

**Limitations of the blinding, stated rather than assumed.** (a) Label-blinding is not
style-blinding — a judge that recognised house prose could infer a family, and nothing prevents
that. (b) Judges were *instructed* not to read `runs/` or `manifest.json`, which under a read-only
sandbox with filesystem read access is an instruction, not a control — the same weaker guarantee
W2 recorded for the Codex arms themselves. JC1 was observed excluding those paths explicitly from
its own `git grep`, which is evidence of compliance, not proof of it. (c) An Anthropic judge shares
a family with arms A and D exactly as a Codex judge shares one with B and C; that symmetry is why
the panel is mixed, and the own-family check below is what makes it auditable.

---

## 1. Ground-truth recall, per arm

Strict majority of judges (≥3 of 4) per cell.

| brief | subject | GT | A fable-5 | B sol@xhigh | C sol@ultra | D opus-5 |
|---|---|---|---|---|---|---|
| cp-01 | `hooks/validate-bash.sh` | 6 | 4 | 4 | 5 | 5 |
| cp-02 | `tests/activation-watch.bats` | 4 | 0 | 0 | 0 | 0 |
| cp-03 | `scripts/pool-floor.sh` (clean) | 0 | — | — | — | — |
| cp-04 | `scripts/terminal-bench.sh` | 6 | 3 | 3 | 3 | 3 |
| cp-05 | `tests/autonomy-sweep.bats` | 4 | 1 | 1 | 0 | 1 |
| cp-06 | `scripts/lead-supervisor.sh` | 6 | 0 | 0 | 0 | 0 |
| cp-07 | `tests/pane-modal.bats` (clean) | 0 | — | — | — | — |
| cp-08 | `bin/cc-teardown` | 5 | 0 | 1 | 2 | 2 |
| cp-09 | `hooks/teammate-auto-shutdown.sh` | 5 | 1 | 0 | 0 | 2 |
| **TOTAL** | | **36** | **9** (25%) | **9** (25%) | **10** (28%) | **13** (36%) |

**The ranking does not depend on the vote rule** — this was checked at every threshold:

| threshold | A | B | C | D | **Codex-only** | **Claude-only** |
|---|---|---|---|---|---|---|
| ≥1 judge (union ceiling) | 9 | 10 | 11 | 13 | **0** | 2 |
| ≥2 of 4 | 9 | 9 | 11 | 13 | **0** | 3 |
| ≥3 of 4 (strict majority) | 9 | 9 | 10 | 13 | **0** | 3 |
| unanimous (4 of 4) | 9 | 9 | 9 | 12 | **0** | 3 |

**22 of 36 ground-truth defects were found by no arm at all** (61%), including all 6 in cp-06 and
all 4 in cp-02. That is a fact about the corpus, not about any model: these are defects selected
*because* they survived a first look. Read every recall figure above against that ceiling.

### The near-miss that shows why "same topic" is not "same defect"

On cp-02 both Codex arms named the right line and the right construct — *"the self-test only counts
18 `ok` lines and does not establish that 18 distinct checks actually ran"* — while the actual
defect (GT-1) runs the other way: the `-eq 18` is a **tripwire on the suite's own growth**, going
red on every added check rather than on any regression. Three judges independently declined to
credit it, and they were right to. An adversarial slot that reports the adjacent weaker mechanism
has not caught the defect; it has produced a finding that will be closed as "already asserted".

---

## 2. Non-overlap — the deliverable

### Unique ground-truth hits (caught by exactly one arm)

| arm | unique | which |
|---|---|---|
| A `claude-fable-5` @xhigh | **0** | — |
| B `gpt-5.6-sol` @xhigh | **0** | — |
| C `gpt-5.6-sol` @ultra | **0** | — |
| D `claude-opus-5` @max | **2** | cp-01 #6, cp-09 #5 |

### Pairwise: how many defects row X caught that column Y missed

| X \ Y | A | B | C | D |
|---|---|---|---|---|
| **A** fable-5 | — | 2 | 2 | 1 |
| **B** sol@xhigh | 2 | — | 1 | 1 |
| **C** sol@ultra | 3 | 2 | — | 1 |
| **D** opus-5 | **5** | **5** | **4** | — |

Two things fall out of this table and they carry the verdict:

1. **Against the incumbent alone, Codex is NOT a strict subset** — B catches 2 and C catches 3 that
   Fable misses. Taken alone that reads like the SPLIT case the plan anticipated.
2. **Every one of those is also caught by arm D.** The family-level count is what settles it:
   Codex-only = **0**, Claude-only = **3**. The candidate's entire contribution is already inside
   the model this slot degrades to when the Fable window shuts.

Arm D's row is the other half of the story: it catches 5 that Fable misses, 5 that B misses and 4
that C misses, while no arm catches more than 1 that D misses.

---

## 3. The one dimension where Codex could have earned the slot — and why it cannot be certified

The Codex arms report roughly **twice the incumbent's volume**. Counting findings the way the
judges did (mean over the four judges, across all nine briefs):

| arm | findings reported | of which ground-truth | unscored-but-judged-real | judged FALSE POSITIVE |
|---|---|---|---|---|
| A `claude-fable-5` | 74.2 | 9 | 61.0 | 4.5 (6%) |
| B `gpt-5.6-sol` @xhigh | 141.0 | 9 | 101.2 | 30.2 (21%) |
| C `gpt-5.6-sol` @ultra | 146.8 | 10 | 105.5 | 31.8 (22%) |
| D `claude-opus-5` | 101.2 | 13 | 81.8 | 7.0 (7%) |

Most of that volume is *outside* the ground truth. If those extra findings are real, that is
non-overlap the ground-truth table cannot see, and it would be the candidate's case. Counting only
clusters a judge scored real **and** attributed to exactly one arm — the unscored analogue of the
unique-hit column:

| judge | A | B | C | D |
|---|---|---|---|---|
| JA1 (anthropic) | 7 | 21 | 25 | 15 |
| JA2 (anthropic) | 6 | 22 | 26 | 14 |
| JC1 (codex) | 12 | 9 | 10 | 21 |
| JC2 (codex) | 10 | 12 | 15 | 21 |
| **panel mean** | **8.8** | **16.0** | **19.0** | **17.8** |

Even at the panel mean — which averages across the disagreement rather than resolving it — the best
Codex arm (19.0) and the Claude anchor (17.8) are inside a rounding error of each other, and both
are roughly double the incumbent. The candidate's case on this axis is therefore *at most* "as good
as the model already in the ladder", and it rests on an average of two irreconcilable readings.

**The panel cannot agree whether they are real, and the split is exactly along vendor lines.**

| judge | vendor | clusters scored TRUE (unscored-but-real) | clusters scored FALSE POSITIVE |
|---|---|---|---|
| | | A / B / C / D | A / B / C / D |
| JA1 | anthropic | 65 / 128 / 140 / 88 | 2 / 3 / 2 / 6 |
| JA2 | anthropic | 65 / 130 / 140 / 90 | 2 / 2 / 2 / 5 |
| JC1 | codex | 58 / 67 / 74 / 75 | 6 / **65** / **69** / 9 |
| JC2 | codex | 57 / 85 / 97 / 77 | 8 / **49** / **52** / 8 |

The two vendors' judges do not merely differ in strictness — they **invert the ranking**, and they
do it consistently within each vendor. The Anthropic judges credit the Codex arms with the most
unique real findings (21–26 each, versus 6–7 for Fable) and refute 2–3 of their claims. The Codex
judges refute **49–69** of those same claims each and rank arm D top instead. Mean false-positive
rate over the whole panel lands at **21–22% for the Codex arms against 6–7% for the Claude arms** —
a number that exists only because two of the four judges see it, so it must not be quoted without
this paragraph attached.

**And this is the ONLY axis they split on.** On the anchored ground-truth scoring the same four
judges are in near-perfect agreement (§4): 98% cross-vendor against 99% within-vendor, a −1 pp
delta. The panel agrees almost completely about *what was found*; it disagrees violently about
*what counts as a finding*.

**The mechanical cause, measured independently of both judges.** Every quoted code line in all 36
outputs was extracted and matched against the real file at the brief's `pre_fix_ref`:

| arm | quoted line is AT the cited line | within 3 lines | **off by >3 lines** | not in the file at all | n |
|---|---|---|---|---|---|
| A `claude-fable-5` | 97 (93%) | 2 (2%) | 5 (5%) | **0** | 104 |
| B `gpt-5.6-sol` @xhigh | 202 (40%) | 99 (20%) | **202 (40%)** | **0** | 503 |
| C `gpt-5.6-sol` @ultra | 313 (51%) | 103 (17%) | **203 (33%)** | **0** | 619 |
| D `claude-opus-5` | 187 (96%) | 0 (0%) | 7 (4%) | **0** | 194 |

**No arm fabricated code.** Not one quoted line in 1,420 is absent from the file — the four
"missing" lines in arm A's output are `...` elisions, checked by hand. What the Codex arms get
wrong is *where the code is*: a third to two-fifths of their quoted lines sit more than three lines
from the number they cite. And it is not a constant offset that could be corrected mechanically —
the displacement distribution runs from +1 to beyond +80.

It **degrades with file length**, sharply:

| brief | file lines | B lines off by >3 | C lines off by >3 |
|---|---|---|---|
| cp-01 … cp-05, cp-07 | 185–411 | 0–6 | 0–6 |
| cp-06 | 652 | 77 | 73 |
| cp-08 | 867 | 39 | 53 |
| cp-09 | 982 | 83 | 71 |

So the judges were both applying the byte-for-byte citation rule honestly and reaching opposite
answers, because the rule is ambiguous between *"the cited line does not support the claim"* (a
false positive) and *"the line number is off by eleven"* (a real finding with a bad pointer). The
Codex judges read it the first way; the Anthropic judges the second.

**This is the decorrelation signal the mixed panel was mandated to surface, and it would have been
invisible to a single-vendor panel** — with either vendor alone this probe would have returned a
confident number and never known the other reading existed. It is worth being precise about *what*
decorrelated: not the **finding** layer, where the two families overlap almost completely and where
the ground-truth table above is judge-vendor-independent, but the **judging** layer, where they do
not share a threshold for what a citation has to do before a claim counts.

Note also which way it cuts. The Codex judges are the harsher ones **on the Codex arms** — this is
not vendor loyalty inverted into leniency, it is a genuinely different standard, applied by both
vendors to all four arms alike (§4, own-family check).

**Consequence for the verdict.** The only column where the candidate leads is the column the panel
cannot adjudicate. *Uncertified means unrouted* — that is REJECT, not a coin flip, and explicitly
not an ADOPT inferred from the friendlier judges.

**Operational note, independent of the verdict.** A 33–40% mis-located citation rate is a real cost
in a verification slot on files over ~600 lines, because the consumer of an adversarial finding
re-locates every claim by hand. It is also *cheap to fix* if this is ever re-probed: give the arm
line-numbered input instead of a bare code fence.

### Clean-brief control (cp-03, cp-07 — no ground truth)

No arm reported "no defects" on either clean brief; every arm reported findings on both. That is
not by itself a fault — 9 of 13 candidate "clean" files were convicted during W1 screening, so a
finding here may well be right, and the judges adjudicated each against the code rather than
against the label. Both clean briefs are short (185 and 273 lines), which is precisely where the
Codex citation problem does not bite; the false-positive counts there are low for every arm and do
not separate them.

---

## 4. Per-vendor judge agreement — and the panel's own validity check

This was mandated as a first-class result, and it turns out to be the thing that makes the verdict
trustworthy rather than merely stated.

**On the anchored ground-truth scoring the panel is effectively unanimous, across vendors.** Cell =
(brief, arm, ground-truth index) — did this judge credit that arm with that defect? 144 cells.

| pair | kind | agreement |
|---|---|---|
| JA1 ↔ JA2 | WITHIN-vendor (anthropic) | 99% (143/144) |
| JC1 ↔ JC2 | WITHIN-vendor (codex) | 99% (142/144) |
| JA1 ↔ JC1 | CROSS-vendor | 99% (143/144) |
| JA2 ↔ JC1 | CROSS-vendor | 99% (142/144) |
| JA1 ↔ JC2 | CROSS-vendor | 98% (141/144) |
| JA2 ↔ JC2 | CROSS-vendor | 97% (140/144) |

- mean WITHIN-vendor **99%** · mean CROSS-vendor **98%** · delta **−1 pp**

A large negative delta would have been the decorrelation signal at the judging layer. There isn't
one *here*. **Which arm caught which known defect is not a matter of judge vendor** — and that is
precisely the table the verdict rests on. The vendor split is confined to the unscored/citation
axis (§3), where the delta is enormous; had the panel been single-vendor, one of these two facts
would have been reported as if it were the other.

### Own-family favouritism — none, in either direction

| judge | credits to Claude arms (A+D) | credits to Codex arms (B+C) | skew |
|---|---|---|---|
| JA1 (anthropic) | 22 | 20 | −2 toward Claude |
| JA2 (anthropic) | 22 | 21 | −1 toward Claude |
| JC1 (codex) | 22 | 19 | −3 toward Claude |
| JC2 (codex) | 21 | 18 | −3 toward Claude |

Every judge of **both** vendors credits the Claude arms slightly more, and the Codex judges skew
*further* that way than the Anthropic ones. There is no measurable home-team effect to discount, so
the REJECT cannot be attributed to a panel stacked against the candidate — if anything the
candidate's own family judged it hardest.

---

## 5. Robustness — the two RECONSTRUCTED arm-C records

`cp-01__C` and `cp-02__C` are records rebuilt from disk after the W2 orchestrator was killed
mid-grid; the outputs are the untouched files those runs wrote, only the timestamps are
approximate. **They are INCLUDED in the headline numbers**, because the scored artifact is the
output text and that text is not in question.

The verdict is reported both ways, and it does not move:

| basis | A | B | C | D | Codex-only GT | Claude-only GT |
|---|---|---|---|---|---|---|
| all 9 briefs (reconstructed pair included) | 9 | 9 | 10 | 13 | **0** | 3 |
| 7 briefs (cp-01 + cp-02 dropped for **all** arms) | 5 | 5 | 5 | 8 | **0** | 2 |

Unique-GT hits move 0/0/0/**2** → 0/0/0/**1** on the reduced base; nothing else moves.

Dropping them costs arm C its best brief — cp-01, where it led the field on 5 of 6 — and the
verdict is unchanged in direction and in mechanism: **Codex-only stays 0**, arm D stays clear of
arm A, no Codex arm acquires a unique hit. **The verdict is robust to the scar**, and it is robust
in the direction that matters: the reconstructed records are the *candidate's* best cell, so
including them is the choice that favours the candidate, and it still loses.

---

## 6. The separate finding: the frontier premium is unearned in this slot — and inverted

This is a result about Fable, not a footnote about Codex.

`claude-opus-5 @max` (arm D) did not merely match `claude-fable-5 @xhigh` (arm A). It **beat** it on
every measure this probe took:

- ground-truth recall **13 vs 9** of 36;
- non-overlap **5–1 in D's favour** (D caught 5 defects A missed; A caught 1 D missed);
- unique hits **2 vs 0** — arm A is the only arm that caught nothing no one else caught;
- citation accuracy **96% vs 93% exact**, both with zero fabrication.

Fable costs 2× Opus 5 ($10/$50 vs $5/$25). On this corpus, in this slot, it is being paid a premium
to be **strictly dominated**. That is the live possibility the plan named when it insisted on arm D
— *"if Codex loses to Fable but ties Opus, the actionable finding is about Fable's premium"* — and
the measurement came in stronger than the hypothesis.

⚠️ **Bounded claim.** One corpus, nine briefs, one effort setting each, and the arms were run at the
efforts the ladder actually assigns them (`verify_judge: xhigh` for Fable, the plan's `max` for
Opus) — so this is *not* an equal-effort comparison and cannot separate "Opus 5 > Fable 5" from
"max > xhigh". It is enough to say the Fable premium is **not demonstrated** in this slot and that
an equal-effort A-vs-D re-probe is now the highest-value follow-on. It is not enough to reseat the
slot on this evidence alone, and this document does not.

---

## 7. Facts carried forward from W2 that constrain how the above must be read

1. **Arm C is not a silent alias of arm B** — paired reasoning tokens, C > B on 7/9 briefs, 1.76×
   in sum. B-vs-C is a legitimate comparison and the B→C = 0 row above is a real result.
   **But `ultra` is absent from the API's reasoning-effort enum, so its relation to `max` is
   UNESTABLISHED.** Arm C is *"more reasoning than `xhigh`"*, measured — **not** *"the maximum"*.
   The plan's own W2 table called it max-reasoning; **that assumption is REFUTED** and is not
   relied on anywhere in this verdict.
2. **Isolation is evidence, not proof, on the Codex side.** 18/18 Codex rollouts show zero
   `exec_command`/`function_call` items and the Claude arms ran `num_turns=1`. That is evidence
   none of them *did* read the repo. It is **not** proof none of them *could*: `codex exec -s
   read-only` denies writes and permits filesystem reads, so the brief's "use no other resource"
   was an instruction for arms B and C where it was a hard denial (`--tools ""`) for A and D. The
   asymmetry, if it biased anything, biased it **toward** the candidate — which the candidate did
   not convert.
3. **Cost is DIRECTIONAL only.** Codex weekly `used_percent` moved 22.0 → 27.0 across W2's 18 runs.
   Neither vendor reports tokens or dollars for these calls. **No $/finding figure is computed
   here**, and none should be quoted from this probe. (For the record, W3's own judging cost a
   further 22.0 → 37.0 → ~43% of the weekly Codex bucket across 18 judge runs — that is the cost of
   *judging*, not of the arms, and it is why the mixed panel is a per-probe instrument and not a
   standing one.)
4. **Corpus bias is real and is named, not benefited from** — see the verdict section.

---

## 8. What is NOT concluded

- **Not** that `gpt-5.6-sol` is a weak model. It matched the incumbent on ground-truth recall
  (9 vs 9 at `xhigh`, 10 vs 9 at `ultra`) while producing 3.5× the finding volume with zero
  fabricated code. It is rejected for **containment**, on the specific and narrow question of
  whether it adds coverage this slot does not already have.
- **Not** that cross-family independence is worthless. It is rejected *as measured on this corpus*,
  where the anchored population happened to be fully covered by the Claude family's union. A corpus
  built from defects that *Codex* already missed would test the converse and is not this probe.
- **Not** a verdict on any other slot. Per the Sonnet precedent, certification is **per slot and
  per effort**; nothing here licenses "use Codex for adversarial work" generally, and nothing here
  applies to `gpt-5.6-sol` outside `roles.research_adversarial`.
- **Not** a flip of `model-config.yaml`. W4 owns the encoding; on REJECT the encoding is the
  written rejection itself, so the candidate is not re-proposed in six months without new evidence.

---

## 9. Reproduction

Judging artifacts are in this session's scratchpad (`panel/`): `build_bundles.py` (blinded bundle
construction + `blind_key.json`), `run_judge.sh` / `run_wave.sh` (the two backends),
`out/<judge>/<brief>.json` (36 raw judge records), `aggregate.py` → `report.md` + `results.json`,
and `citation_accuracy.json`. The corpus and the 36 arm outputs are unmodified — W3 read them and
wrote nothing into `tests/fixtures/codex-probe/`.
