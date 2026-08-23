# CLOSE SHAPE — W3: the structure of the whole close message

**Measured 2026-08-23** against all four per-account transcript stores. W3 to
[close-scannability-2026-08-23](close-scannability-2026-08-23.md)'s W1/W2, which measured and fixed
exactly ONE line — the act. This measures the other ~350 words: the wall the operator screenshotted.

**The headline, first. The word cap was the wrong instrument, and half of it ran backwards.** Holding
"the act is its own line" fixed, close length does not predict whether the operator acts
(Mann-Whitney **p = 0.39** on n = 409; logistic `log(words)` **β = −0.22, p = 0.11** on n = 873, in a
fit where `act_is_line` carries **β = +2.73, p = 7.3e-31**). An independent instrument with the
*opposite* outcome measure agrees: `r(words, round-trip) = −0.0097`, flat across all ten deciles.
And the `line 1 ≤ 30 words` half is not merely unsupported — closes whose line 1 **exceeds** 30 words
are acted on **more** often, 56.1% vs 42.5% (Fisher **p = 0.035**, OR 1.73). The cap is replaced by
an **admissibility rule** (one slot, one fact, and the fact must change what the operator does or
name a store a command reads back) plus a **screen bound** (one 24-row pane).

**What the operator asked for, verbatim, since it is the specification:**

> *"carry as much high-value detail as possible while being as short and concise and actionable as
> possible (ie. cut the fluff, leading with the answer, clear to read, dont have to scan large walls
> of text to understand what happened, what are the outcomes, and what are the waiting
> decisions/actions/commands to continue to full completion and session close)"*
> *"Again, the recap message is a good example but it cant only be that"*

That second clause is the whole difficulty. A 40-word recap is a good TOP and a bad WHOLE: it cannot
carry a landed sha, a gate verdict, a command to paste, or a blocking decision. **The design problem
was never line 1. It was the structure below it.**

---

## Method

| | |
|---|---|
| Corpus | four per-account roots — `~/.claude/projects` 893 · `-secondary` 938 · `-tertiary` 797 · `-quaternary` 974 = **3,602** `.jsonl` at `-maxdepth 2`. `~/.claude-next/projects` is a **symlink to the first**, excluded by realpath so it is never double-counted |
| Turn-final assistant messages | **13,541** |
| Rung-carrying closes (the population) | **5,805** — uncapped, vs W1's 300 |
| Act-required | 1,960 (33.8%) |
| Act-required **with a human reply** — the outcome n | **873** (209 ACTED) — 5.2× W1's n=169 |
| Instrument | `scripts/measure-closes.py` — **committed this time** (W1's was not, and was gone) |

Five parallel measurement axes plus one independent extension, then three competing designs, each
attacked by two adversarial lenses (dead-pointer and regression), then a synthesis with a three-case
control. **All three designs were refuted** — 8, 9 and 7 fatal flaws and 3, 7 and 8 dead pointers.
The shipped design is the synthesis of what survived.

### Instrument corrections that changed a conclusion

Recorded because each one moved a number, and two moved a verdict.

1. **W1's ACTED-vs-ASKED correction is carried, and extended.** Excluding `<task-notification>` from
   the reply denominator is not the same as scoring a close "no reply" because a machine injection
   landed first. The parser now scans forward over machine records to the first *human* record, or
   stops at an assistant record (the session carried on by itself). Effect: +6 human replies of 650
   machine-followed closes — small, and it *confirms* W1's caveat that those are fired peers with no
   operator reading them.
2. **A close's text can span several records.** One API response is written per content block, so
   text blocks are concatenated within a `message.id` group. Taking only the last record would have
   truncated the very variable being measured.
3. **A fluff plateau was a bucketing artifact, and it inverted the conclusion.** Ten equal-n buckets
   gave a top bucket spanning 457–6,722 words; the midpoint marginal then read +1.70 facts/100 words
   and looked exactly like the predicted plateau. Capping the tail at 1,200 words with 20 buckets
   removes it entirely — **fact density is flat**. There is no empirical fluff line.

### The positive control reproduces before anything is claimed

```
  act-required closes   n= 873  ACTED 209 (23.9%)
  CONTROL no-act closes n=1084  ACTED  38 ( 3.5%)   [W1: 1.9%]

  W1 R4 replication (runnability held fixed — every close contains a command):
     act IS its own line    ACTED 185/407 = 45.5%   [W1: 35.4%]
     act NEVER its own line ACTED  24/451 =  5.3%   [W1:  9.4%]
     Fisher exact two-tailed p = 5.73e-46  OR = 14.83
```

---

## Results

### R1 — length is not the variable, in either direction

Within the act-is-a-line stratum the median ACTED close is 288 words and the median not-ACTED close
is 286 (p = 0.39, n = 409); by lines, 9 vs 10 (p = 0.23). The null survives every decorrelation arm
that could have masked a real effect: inside each rung separately (all p > 0.06), inside the runnable
stratum (p = 0.37), and inside each of the two eras the corpus spans (p = 0.29 and p = 0.44 — checked
because July has both *longer* closes and a *higher* ACTED rate, which is the classic way to
manufacture a null by pooling).

**Do not read this as "shorter is worse" either.** The finding is that length is not the variable,
and that a rule spending its authority on word counts is spending it on nothing.

### R2 — the `line 1 ≤ 30 words` cap runs backwards

56.1% (46/82) vs 42.5% (139/327), Fisher p = 0.035, OR 1.73; stable on the rank test (median line-1
length 22 words for ACTED vs 19, p = 0.008). The honest reading is a **specificity confound** —
a longer line 1 is usually a more specific one, and specificity is what CLAUDE.md's own "idea, not a
category" rule already demands. Either way there is no arm in which a 30-word line-1 cap does work.

### R3 — what DOES predict failure: an unresolved named thing, not a long one

A **107-word** close obeying every structural rule and a **407-word** close drew the *verbatim
identical* operator reply. The largest measured effect on this surface is opacity: **≥2 unexpanded
hex ids → 49.2% vs 33.6% failure, +15.5pp, p = 0.0001**, surviving stratification — roughly 10× the
predictive power of length, which is null. The second is fragmentation: `>3 headings` at 10.5% vs
46.9% ACTED (p = 0.0016), the only structural feature of twelve to survive Bonferroni, and it
survives adjustment for length while length goes inert. **n = 19 — flagged as a follow-up, not shipped
as a rule.**

### R4 — the C/S/O contract: one of its four lines earns its place

`Good to close:` is **not derivable from the rung**. Over 613 closes carrying it, the rung predicts
the verdict only **73.4%** of the time; **48 of 313 `✅` closes answer "no"** (git says complete-and-live,
the model says do not close — a fact no renderer computes), **39 of 97 `👤` answer "yes"**, `🚀` splits
47/53, and **17.6% carry no rung glyph at all**, making the verdict the only close decision in the
message. **51.4%** carry follow-on ids no renderer computes.

`Complication:` / `Solution:` / `Outcome:` do not. Where the block is under a third of the close —
i.e. wherever a real body exists above it — `Outcome:` is novel **1 time in 7** and `Solution:`
**2 in 7**; their apparent 80/70/70% novelty is an artifact of the block *being* the whole close in a
third of cases. Scored on whether the line changes the operator's next action, the four run 1/30,
0/30, ~3/30 and **30/30**. The block's median cost is **119 words** against a close budget that was
**120**.

**Position is the other half of the failure.** The verdict sits as the **last non-empty line in
90.7%** of closes. A 173-word close with `✅` at line 1, whose literal last line read
`Good to close: yes — complete, landed, no loose ends; follow-on: none.`, drew the operator's entire
next message: **"Good to close?"**. Eight such instances are in the corpus, the most recent the same
day this was measured.

**Honest limit, not laundered:** ACTED cannot evaluate C/S/O. It is a *comprehension* contract and
the corpus records no comprehension outcome; its own contingency table is a clean, adequately-powered
null (OR 0.96, p = 1.0, n = 90/783). What that bounds is narrow and still decisive for the design:
**C/S/O is not a substitute for the act line, and demanding it does not help the operator act.** The
information test above — novel-fact rate against the body — is what convicts it, not the null.

### R5 — line 1 is already machine-rendered, and nothing checked

`scripts/wrap-ledger.sh:1039` emits a complete line-1 sentence in a field named `READOUT`, computed
from live git/gate/DoD/decision reads. `hooks/operator-readout.sh:818-819` already composes the exact
Minto *idea* line CLAUDE.md holds up as its aspiration — `13 runnable now, 207 need your call` — from
a real partition of disjoint counts. **That string is not an aspiration; it is production output of a
shipped renderer.** Two files instruct the model to relay `READOUT` verbatim.

**Measured compliance: 3 of 167 = 1.8%.** `grep -n READOUT hooks/completion-assert.sh` returned zero
lines. The seam was not missing capability — it was missing enforcement.

But it must be **containment, not equality**: the renderer yields a Minto *idea* when its fact is
itself the conclusion (`⛔ Blocked — need your call: <the decision>`) and a *category* whenever its
fact is a count over a population it cannot name (`22 uncommitted change(s)`, `N step(s) need you`) —
three of seven rungs, including `👤`. A byte-equal line 1 would make the ideal close illegal.

### R6 — reachability, the veto axis

48 of 58 proposals in the prior session died on fake shortening — text routed to a `--why <topic>`
flag that three emitters proposed and none implemented. So every drop was audited by execution.

| Detail dropped | Its store | The ONE command | Reachable? |
|---|---|---|---|
| governing state (rung · dirty · gate · landedness · live-lag · goal) | live git + gate reads | `/wrap` — 8 lines / 100 words; `--full` for 13 rows | **yes** |
| operator-owned actions and decisions | `~/.claude/autonomy/{backlog.jsonl,decisions/,pending-activation/}` | `/wrap` renders the counted block; `cc-do --list` · `cc-decide list --open` · `cc-backlog list --blocked` expand it | **yes** |
| why the work was done, what changed, the evidence | the commit body | `git show <sha>` — 45 of 50 recent commits carry a body, mean 252 words | **yes, conditionally** |
| design decisions, rejected approaches, measurements | `docs/plans/*.md` · `docs/research/*.md` | open the named path | **yes, if a doc was written** |
| reasoning, dead ends, synthesis never committed and never in a doc | **nowhere** | **none exists** | **NO** |

Two limits that a design must not launder:

- **`/wrap --full` is NOT the narrative tier.** All 13 rows are repository state; zero words about
  the work.
- **`/wrap` cannot render `👤` or a session-filed `⛔`.** Measured:
  `Blocked on you: unknown — session id unresolvable (not counted)`. `commands/wrap.md` documents
  this deliberately — guessing the session id from `.last-session-id` would attribute a sibling's
  steps. So **what is mine vs yours is the one fact that may never be dropped**, because nothing can
  retrieve it afterward.
- **No shipped command reads a session's own narrative back.** 96 entries in `bin/`; the ones that
  touch transcripts consume them to compute a verdict, never to show one. Scrollback is the only
  route.

**The rule this yields, and it is the admissibility rule the section ships:** detail may be dropped
only into a store a named command can read back. Detail with no such destination must be **put** into
one before the close, or **kept** in it. It may never be dropped on the promise that it is available.

---

## The control

Three real past closes, three shapes, measured with the census instrument's own `measure()`.

| case | words | non-blank lines | rendered rows @100 cols | facts | governing state at non-blank line |
|---|---|---|---|---|---|
| **(a) BEFORE** — the motivating close | 353 | 15 | 39 | 19 | **15** (last line) |
| **(a) AFTER** | **144** | **4** | **15** | 14 | **1** |
| **(b) BEFORE** — a measured re-ask failure | 229 | 9 | 24 | 11 | 1 |
| **(b) AFTER** | **203** | **5** | **18** | **11** | 1 |
| **(c) BEFORE** — a 72-word close that already worked | 72 | 5 | 13 | 6 | 2 |
| **(c) AFTER** | 81 | 5 | **12** | **6** | **1** |

Case (c) is the control's control: the design must not make a good short close worse. It costs +9
words and still returns −1 rendered row and zero facts lost, while correcting the rung from `✅` to
`⛔`.

**The five dropped facts in case (a) were each audited, and the operator acted on none of them.** One
audit result is worth stating on its own: the original close cited `c155510fb` as the sibling commit
that cleared its wedge, and `git merge-base --is-ancestor c155510fb origin/main` returns **NO** —
`git branch -a --contains` is empty. It resolves in that checkout and nowhere else. **Citing it was
the defect; dropping it is the fix.** That is why S5 requires a cited sha to answer the ancestry test
before it may be named.

**A limit not laundered:** for case (b) the AFTER is *not* claimed to prevent the operator's
`Are we good to close?`. That BEFORE's line 1 already said "close whenever you like", so the
improvement is the withdrawal moving up beside the assertion rather than sitting in the last
paragraph. Whether relocation fixes the re-ask is a **prediction, not a measurement** — see the
falsifier.

---

## The falsifier

The design's central bet is that **moving the verdict from last to second** reduces the re-ask. That
is the one load-bearing claim here that is *not* measured, because no corpus of second-line verdicts
exists yet — only 1.1% of the 613 compliant closes put it at position ≤3.

**The check, runnable once the new shape has produced closes:**

```
python3 scripts/measure-closes.py --days 30 --limit 0
```

Compare the re-ask rate for closes whose verdict is at non-blank position ≤3 against those where it
is last. If the rate does not fall, the relocation bought nothing and `CC_VERDICT_WINDOW` should stay
at 0 permanently — or the verdict should go back to the end, which costs one line to revert.

🚨 **This falsifier expires unless the instrument is maintained.** W1's scripts were never committed
and were gone within a day, which is why this pass had to rebuild the instrument from a prose Method
section. `scripts/measure-closes.py` ships in this commit for exactly that reason. Every figure here
decays with its source (MEMORY.md `published-figure-decays-with-its-source`) — **re-run it, do not
quote it.**

---

## What was NOT built, and why

- **`CC_VERDICT_WINDOW` ships at 0 (position-free).** Measured, not timid: only 1.1% of currently
  compliant closes have the verdict at position ≤3, so switching the window on in the same commit
  that moves the template would fail 5 of 9 compliant closes in a 700-close replay. Move the
  placement, re-measure, then set the window. The fence-skip added to `close_shape_missing` is what
  makes turning it on possible later.
- **No `BLOCKED_WHAT` field was added to `wrap-ledger --machine`.** It was proposed, and it is
  unnecessary: `READOUT`'s `⛔` tail already *is* `BLOCKED_WHAT` (`scripts/wrap-ledger.sh:959`), so
  the section's claim holds against the shipped renderer without a new field.
- **The `>3 headings` fragmentation signal was not made a rule.** It is the strongest residual and it
  rests on n = 19. Re-measure it on fresh data with a pre-registered threshold first.
- **No narrative-tier reader was built.** The gap is real and named in R6; building it is a separate
  change with its own evidence. Until it exists, the admissibility rule's last row says **"nowhere"**
  out loud rather than pointing at a flag nobody wrote — which is the precedent this whole axis
  exists to avoid.

## What the instrument cannot see

- Everything W1 could not see: act-required is *inferred*, so 33.8% is a floor; ACTED undercounts
  (a GUI, phone or other-pane action leaves no record); the population mixes origin and peer sessions.
- **A word count is not a reading time.** Length here is words and lines; it is blind to wrap width,
  terminal size, and how much sits above the fold — plausibly the variable the operator's complaint
  is actually about. That is why acceptance test 2 is **rendered rows**, not words. A null on word
  count is not a null on visual bulk.
- **Fact count is a proxy dominated by backtick spans (62.7%).** A close relaying one rendered block
  accrues many "facts" that are one artifact.
- **This is one operator, two months, one machine.**
