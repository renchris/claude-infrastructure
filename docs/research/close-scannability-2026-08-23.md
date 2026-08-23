# CLOSE SCANNABILITY — W1 measurement

**Measured 2026-08-23** against the live transcript corpus, as the first act of
[CLOSE_SCANNABILITY_2026-08-23](../plans/CLOSE_SCANNABILITY_2026-08-23.md) W1. The plan named three
defects from ONE session and required the base rate before any hook changed. This is that base rate.

**The headline, first.** Among closes that ask the operator to do something, **the act is stated as
its own line only 45% of the time, never at line 1 (1 of 190), at a median of line 6** — and the
difference is not cosmetic: when the act IS its own line the operator acts **35.4%** of the time,
when it is not, **9.4%** (p = 2.7e-05, Fisher exact, runnability held fixed). The failure mode is
**position, not absence and not styling**: 40.5% of these closes already carry the proven `▶` marker
and **not one of them puts the act at line 1**.

**Scope consequence, stated up front (the plan invited this).** The plan's D3 — "multi-step physical
acts have no canonical single-act form, and that is the true novel gap" — is **rare: 5 of 190
act-required closes (2.6%) contain no command styling at all**. Designing a new non-runnable-act
form would be building against a problem that is not there. W2 is scoped down to the defect the
numbers actually show, and the `▶` marker is reused rather than replaced — see § What W2 should
build.

---

## Method

| | |
|---|---|
| Corpus | all four per-account transcript roots (`~/.claude`, `-secondary`, `-tertiary`, `-quaternary`) |
| Window | transcripts with mtime within 14 days of 2026-08-23 — **1,373 files** |
| Turn-final assistant messages found | **4,089** |
| … carrying no ledger rung glyph | 434 in the scanned prefix (see *Population*) |
| **Population under study** | **the 300 most recent rung-carrying closes** |
| Script | `scratchpad/measure_closes.py` + `refine.py` (measurement only — nothing here is shipped) |

**A close** = the last main-agent (`isSidechain != true`) assistant text record of a turn: the
assistant text immediately followed, in record order, by a human user record or by EOF.

**Population.** Restricted to closes carrying a ledger rung glyph (`⛔📤🔧📦🚀👤✅`), because the rung
is what marks a write-turn readout — the population this work is about. Closes carrying no rung are
counted but not analysed; they are the separate "58% of stops assert nothing" finding that
CLOSE_INTEGRITY already owns.

### Two instrument corrections that changed the conclusion

Recording them because the first-pass answer was wrong in both directions, and the corrected
instrument is the only reason the result is trustworthy.

1. **A `<task-notification>` is not a human.** Machine injections ride the user channel. Counting
   them as "the operator replied" inflated the reply denominator by ~15% with records that say
   nothing about whether a close was legible (MEMORY.md `positive-control-the-denominator`). They
   are now excluded, along with system-reminders, handoff pings and command wrappers.

2. **The outcome measure is ACTED-vs-ASKED, not "was the reply a question".** The corpus records the
   operator *running* a handed-over command as a `<bash-input>` user record — direct, unambiguous
   evidence that a close was silver-plattered successfully. The first pass asked only "was the reply
   a clarifying question" and measured **1.8% vs a 1.1% control** — i.e. almost nothing, because it
   was measuring ordinary conversation and throwing the positive evidence away. With ACTED counted,
   the same data separates cleanly. **The plan's assumed outcome measure — the round-trip — is the
   wrong one, and that is a finding: the operator mostly does not ask, they just do not act.**

### What the instrument cannot see — stated, not hidden

- **"Act required" is inferred**, from three signals: a `⛔`/`👤` rung, a `▶` marker line, or
  handoff prose (the same phrase family `completion-assert.sh` D1 uses, with its negation-stripping).
  A close that hands over work in wording none of the three match is invisible here, so 63.3% is a
  **floor**, not a ceiling.
- **"Act line index" is a proxy for unambiguity.** It is the first non-empty line that is a `▶`
  marker, an inline-code span alone on its line, or an operator-directed imperative at line start.
  A line that states the act in some other shape scores as "never".
- **ACTED undercounts.** An operator who acts in a GUI, on the phone, or in another pane leaves no
  record. This biases *against* the finding — the real gap between the buckets is at least as large
  as measured, not smaller.
- **The population mixes origin and peer sessions.** A fired peer's close has no operator reading
  it. Those closes mostly land in "no human reply" and drop out of the outcome analysis by
  construction, but they remain in the position analysis.

---

## Results

### The population

```
turn-final assistant messages          4,089
population under study (rung-carrying)   300

RUNG DISTRIBUTION
  ⛔    51  (17.0%)      🚀    11  ( 3.7%)
  📤     1  ( 0.3%)      👤    80  (26.7%)
  🔧    24  ( 8.0%)      ✅   125  (41.7%)
  📦     8  ( 2.7%)

OPERATOR ACT REQUIRED: 190/300 (63.3%)
  by trigger: rung ⛔/👤 = 131 · ▶ run-marker = 74 · handoff prose = 119
```

### R1 — the metric this work moves: where the act first becomes unambiguous

```
ACT LINE INDEX (n=190, closes requiring an operator act)
  line     1:    1  (  0.5%)
  line   2-3:   14  (  7.4%)  ##
  line   4-6:   34  ( 17.9%)  #######
  line  7-12:   28  ( 14.7%)  #####
  line   >12:    9  (  4.7%)  #
  line never:  104  ( 54.7%)  #####################
  median (where stated at all): 6      p90: 13
```

**One close in 190 puts the act at line 1.** The operator's requirement — "scan one line" — is met
0.5% of the time.

Per rung, the defect is uniform rather than concentrated, which forecloses the cheapest possible
scope-down (fixing one rung):

```
  ⛔  n= 51  line1= 1 (2.0%)  never= 32 (62.7%)  median= 7
  🔧  n= 13  line1= 0         never= 11 (84.6%)  median=15
  📦  n=  1  line1= 0         never=  0          median= 6
  🚀  n=  3  line1= 0         never=  1 (33.3%)  median= 7
  👤  n= 80  line1= 0         never= 38 (47.5%)  median= 6
  ✅  n= 42  line1= 0         never= 22 (52.4%)  median= 4
```

`⛔` and `👤` together are **131 of the 190** act-required closes and carry the two worst absolute
counts. They are also the two rungs whose *definition* is "the operator must act", so they are where
an assert can demand an act line without ever having to guess.

### R2 — the "never stated as one line" bucket is not one thing

```
  total                                            104
  (b1) act IS in line 1, welded into a compound     26  (25.0%)
  (b2) act in lines 2-6, welded into prose          50  (48.1%)
  (a)  no operator-act verb in the first 6 lines    28  (26.9%)
```

**73% of the "never" bucket does contain the act — welded into a sentence.** This is the operator's
complaint exactly, and the plan's R1 evidence is a member of (b1): a close whose line 1 read
`⛔ Blocked on you — resend the SevenRooms code, tick "Trust this browser", then close that Chrome
window` — three acts in one sentence, in line 1 — and which still drew *"Whats blocked on me? Be
explicit"*. The information was present. No single line was the act.

### R3 — the outcome: does the operator actually act?

```
OUTCOME OF THE OPERATOR'S NEXT MESSAGE
  act-required closes      n=169   ACTED  36 (21.3%)   ASKED  5 ( 3.0%)
  CONTROL no-act closes    n= 53   ACTED   1 ( 1.9%)   ASKED  3 ( 5.7%)
```

The control is the instrument's own positive control: closes that require no act draw an ACTED reply
1.9% of the time, so the ACTED signal is measuring the thing and not background noise.

```
  by where the act first becomes unambiguous:
  line 1-3            n= 13   ACTED  5 (38.5%)   ASKED 0
  line 4-6            n= 31   ACTED 10 (32.3%)   ASKED 0
  line 7+             n= 35   ACTED 13 (37.1%)   ASKED 1
  never as one line   n= 90   ACTED  8 ( 8.9%)   ASKED 4
```

**The cliff is between "is a line" and "is not a line" — not between line 1 and line 7.** Any
position beats no position by ~4×, and the three stated-position buckets are flat within noise.
Within the "never" bucket, the worst sub-case is the one the operator complained about:

```
  (b1) welded into line 1  n=24   ACTED  1 ( 4.2%)
  (b2) welded, lines 2-6   n=40   ACTED  3 ( 7.5%)
  (a)  no act verb         n=26   ACTED  4 (15.4%)
```

An act welded into line 1 is acted on **less often than a close with no act verb at all**. Putting
the act in the first line does not help; putting it *on its own* line is what helps.

### R4 — decorrelation: is this just "commands are easier to act on"?

The obvious confound: an act that is its own line is more likely to *be a pasteable command*, and
commands are intrinsically easier to act on. Holding runnability fixed kills it.

```
Among the 185 act-required closes that ALL contain a command (backtick span or ▶):
   act IS its own line   : ACTED 28/79 = 35.4%
   act NEVER its own line: ACTED  8/85 =  9.4%
   Fisher exact, two-tailed: p = 2.7e-05
```

Position moves the outcome by 3.8× **within a population where every close contains a command**. The
converse arm cannot be run — only 5 act-required closes contain no command at all — and that
un-runnable arm's emptiness is itself R5.

### R5 — the plan's hypothesised novel gap (D3) is rare

```
act-required closes with NO command styling anywhere: 5/190 = 2.6%
  (all 5 also never state the act as its own line)
```

The plan's D3 said the true novel gap is that a physical/GUI sequence has no `cc-do` equivalent, so
it degrades to prose. It does degrade to prose — but it is **2.6% of the population**. Building a
new canonical form for it would be a design against 5 observations.

### R6 — the existing machinery, and precisely what it does not do

```
EXISTING MACHINERY PRESENT IN ACT-REQUIRED CLOSES (n=190)
  '▶' run-marker line                    77  (40.5%)
  inline-code span alone on a line       67  (35.3%)
  cc-do named                            18  ( 9.5%)
  rendered OPERATOR ▸ block              15  ( 7.9%)

Closes carrying a ▶ marker: 77 · median act line 6 · at line 1: 0
```

**The `▶` marker is present in two of five act-required closes and has never once put the act at
line 1.** The 2026-08-01 work solved *styling* — is this text a command, is it drag-copyable — and
solved it correctly. It said nothing about *where the marker goes*, and nothing enforced a position.
That is the whole of the remaining gap.

### R7 — the marker has already generalised past "Run this" (measured, not assumed)

The plan asked for the equivalent of `▶ Run this:` for a non-runnable act, and required that any
rendering claim be measured. The corpus answers it: **the operator's act-marker is already `▶`, and
it is already used for acts that are not commands.** 81 occurrences, 19 distinct labels:

```
  40  ▶ Run this:            6  ▶ Look here:          1  ▶ Reopen and tap:
  11  ▶ cc-do   [N runnable] 2  ▶ Test it here:       1  ▶ Reply with this to unblock it:
   6  ▶ Open this:           1  ▶ Check this:         1  ▶ Reload and re-run the scan:
```

So W2 must **not** mint a new glyph. It reuses the form that is already screenshot-verified and
already learned.

**One measurement trap this exposes: 13 of the 81 `▶` occurrences are INSIDE a fenced block** — the
` ▶ cc-do   [13 runnable]` line of the rendered `OPERATOR ▸` readout, which sits at the top of a
close as a verbatim paste. A matcher that looks for `▶` naively will match that line, at line 3,
and pass a close whose real act is at line 11 (observed twice in the sample). **Any matcher must
skip fenced regions.**

---

## What W2 should build — scoped by the numbers above

**Keep** (the plan's core direction, and the numbers support it):

- The demand is for **one line that IS the act**, placed near the top, on the two rungs whose
  definition is "the operator must act" — `⛔` and `👤`, 131 of 190 act-required closes.
- It hangs off `completion-assert.sh`'s existing latched-and-capped arm, with the matcher in
  `hooks/lib/close-shape.sh` beside the origin-close matchers. No new Stop hook.

**Change, on the evidence:**

- **Reuse `▶`; do not invent a form** (R7). Accept an `ACT:` label as the alternative for an act with
  nothing to paste, so the 2.6% non-runnable case has a legal shape without a design of its own.
- **The matcher must skip fenced blocks** (R7), or the rendered `OPERATOR ▸` block is a bypass.
- **Position is "within the first few lines", not "line 1"** (R3): line 1 is already owned by the
  rung, and the outcome data shows the cliff is own-line-vs-not, with position 1 / 4-6 / 7+ flat
  within noise. Demanding literal line 1 would fight the rung for the same row and buy nothing
  measurable.

**Drop:**

- The plan's D3 line of work — a new canonical form for multi-step physical acts (R5, n=5). Recorded
  here so a later session does not re-derive it as missing; the `ACT:` alternative above covers the
  case at a fraction of the cost.

**Do not claim:** that `▶` at line 2 *renders* more visibly than `▶` at line 6. That is a rendering
claim and this work did not measure rendering — it reuses the 2026-08-01 screenshot-verified span
form byte-for-byte and measures **position behaviourally**, via whether the operator acted. The
2026-08-01 fence regression is the standing reminder of what an unmeasured rendering claim costs.

---

## Reproduce

```
python3 scratchpad/measure_closes.py 14 300     # population + position distribution
python3 scratchpad/refine.py                    # outcome, splits, decorrelation
```

Both are measurement-only and are deliberately not shipped: they read a corpus whose window
(`mtime >= 14d`) moves, so re-running on a later date samples a different population. Every figure
above is dated 2026-08-23 and decays with its source (MEMORY.md `published-figure-decays-with-its-source`).
