# A5 — What else in the lessons/memory corpus is worth a Jev pass

Subagent A5, 2026-09-21. Read-only. Repo: `claude-infrastructure`.
Question: §4 rank 3 (lesson/memory relevance ranking). `cc-jev rank` covers one slice — what else,
and which slice is the most valuable per call.

---

## VERDICT (one slice)

**Run a COMPARATIVE promotion pass over the 278 un-indexed topic files — orphan vs incumbent,
`choice` over a 2-key map, with a free-riding `same_rule` dedup boolean in the same call.**
~144 calls, **~11 minutes of wall clock at the throughput this repo actually measured**, ~1,400 B of
state per call. Candidate (a) in the brief, but **NOT in the form the brief states it**, and the
reason is measured below.

**Everything else is refuted, and one of them is refuted by evidence that lands on `cc-jev rank`
itself.** The headline finding of this report is not about a new slice at all:

> 🚨 **`cc-jev rank` already RAN, to completion, at 2026-09-21T05:08Z — and both of its questions
> came back effectively degenerate.** `bite`: **118 of 140 = 84.3% "often"**, 21 "occasionally", 1
> "almost-never", and **0 "nearly-always"** — a 4-level scale using 3 levels with 84% of the mass in
> one bucket. `superseded`: range **0.08–0.89, mean 0.28, and ZERO rows at or above the 0.90 band
> that `hooks/lib/jev.sh` defines as the only actionable one** ("act only in the tail, abstain
> everywhere else"). By its own library's rule, `superseded` produced **0 verdicts**.
> File: `~/.claude/autonomy/jev-rank-20260921T050814Z.jsonl`, 140 rows.

That result is what makes the promotion slice the right answer and what disqualifies the obvious
version of it. An ABSOLUTE 4-level scale over this corpus does not discriminate; a FORCED
COMPARISON does, and it is the shape the eviction decision actually has.

---

## 1. Corpus counts — verified two ways

The brief warned about BSD `find` skipping a symlinked start dir without `-H` and BSD `grep -r` not
walking the symlink layer. Both traps are live here and I hit the first one:
`~/.claude-secondary/projects/-Users-chrisren-Development-claude-infrastructure/memory` is a
**symlink** to the `~/.claude` path. `find $SEC/memory` returns **0**; `find -H $SEC/memory` returns
**501**. Every count below is taken on the `~/.claude` canonical path with `-H`, and cross-checked
with a `ls -1 | grep -c` that does not walk at all.

### Machine-wide

| Quantity | Value | Second method |
|---|---|---|
| project memory dirs under `~/.claude/projects` | **213** | — |
| project dirs that have a `MEMORY.md` at all | **35** (16.4%) | — |
| memory `*.md`, all depths | **1,686** | — |
| memory `*.md`, top level only | **1,652** | — |
| resolvable-indexed across all 35 indexes | **459** | — |
| **un-indexed machine-wide** | **1,193** | — |
| `~/.claude-next` (same figure — it is the same store) | 1,686 | symlinked `projects/` |

Largest two: `reso-management-app` **821**, `claude-infrastructure` **501**.
(The brief's "1,663 topic files" is within measurement drift of 1,652/1,686; "141 index slots" is
**146** today.)

### This repo's slice — the population any Jev pass would actually touch

| Quantity | Value | How checked twice |
|---|---|---|
| `…/claude-infrastructure/memory/*.md` top level | **480** | `ls -1 \| grep -c '\.md$'` = 480; `find -H -maxdepth 1` = 480 |
| `…/memory/archive/*.md` (index snapshots, not lessons) | **21** | `ls -1 archive` |
| total, all depths | **501** | `find -H` |
| resolvable links in `MEMORY.md` | **146** | `grep -c '](.*\.md)'` = 146; distinct targets = 146; targets that exist = 146 → **0 broken index links** |
| **un-indexed top-level topic files** | **334** | `comm -23 all indexed` |
| …minus those named in `.claude/rules/*.md` or `CLAUDE.global.md` | −57 | per-basename `grep -F` |
| **ORPHANS — unreachable from any always-loaded surface** | **278** | `comm` |
| of those 278, named in an `archive/MEMORY_ARCHIVE_*` index | **267** | `grep -F` over concatenated archives |
| named in NO index, NO rules file, NO archive | **11** | `comm` |
| named nowhere in the repo tree either | **1** | `grep -r` over `docs scripts tests bin hooks skills commands` |

⚠️ **The brief's framing "most lessons are reachable from nothing" is overstated and I am correcting
it rather than inheriting it.** 267 of the 278 are recorded in an archive index — they are
*deliberate demotions* by `cc-memory-rotate`, not losses. **But the runtime conclusion survives
intact:** `memory/archive/*.md` does not auto-load into any session, so all 278 are unreachable *by
an agent at work*, which is the only reachability the ranking is about.

### Index cap pressure — the char cap binds, the line cap does not

`MEMORY.md` = **24,410 chars / 157 lines** against a loader cap of **25,000 chars / 200 lines**
(`bin/cc-memory-rotate:227,236`, documenting Anthropic's "first 200 lines or 25KB, whichever comes
first"). That is **97.6% of the char cap** and 78.5% of the line cap. At the mean index-line length
of ~155 chars, **headroom is ~3.8 lines.** (Raw `wc -c`; the rotor compares a *stripped, trimmed*
index, so true headroom is marginally larger. Direction unaffected.)

🚨 **Checked and REFUTED so nobody re-chases it:** the "4 MiB HARD / 150k cosmetic" ceilings in
`.claude/rules/agent-operating-lessons.md` do **not** contradict the "25,000 / 200" ceilings in
`cc-memory-rotate`. They govern **two different surfaces** — the former the always-loaded
`.claude/rules/*.md` file, the latter the `MEMORY.md` index (`cc-memory-rotate:251-255` states the
split explicitly). Not a cross-file contradiction; do not file one.

### The rules file — candidate (c)'s population

| Quantity | Value |
|---|---|
| `- ` bullets in `.claude/rules/agent-operating-lessons.md` | **169** (not ~120) |
| …with a markdown link | 147 |
| …link → `../../docs/lessons/` | **121**, of which broken: **0** |
| …link → a bare slug | **26**, of which broken *as relative links*: **26** |
| …prose-only, no link | 22 |
| `docs/lessons/*.md` files | **121** — and **0** of them are unreferenced by the rules file |
| bullets over the file's own ~350-char budget | **71 of 169 (42%)** |
| bullet length | min 131 · p25 324 · med 339 · p75 371 · p90 404 · max 1,373 |

Minor defect worth one line to the lead, **not** a Jev job: the 26 bare-slug links
(`[Release ≠ !trip](release-predicate-must-not-negate-the-trip.md)`) resolve against
`.claude/rules/`, where nothing exists. **All 26 targets do exist — in the memory dir.** So the
bodies are fine and only the relative prefix is wrong. Fix is `sed`, not a model.

---

## 2. Ranked table of slices

Throughput is the **measured** rate, not the brief's planning assumption. The completed 140-row run
took **594 s wall clock → 4.24 s/row → 14.1 calls/min**, with no rate-limit backoff visible in the
timing (3 s scripted gap + ~1.2 s round trip). **That is 2.35× the 6/min the brief budgets against**,
and it moves every candidate below from "fits in four days" to "fits in one sitting."

| # | Slice | Population | Calls | Wall clock @14.1/min | Base rate | Value if it works | Verdict |
|---|---|---|---|---|---|---|---|
| **1** | **(a′) Promotion, COMPARATIVE** — orphan vs weakest incumbent, `choice` 2-key + free `same_rule` boolean | 278 orphans | **144** (56 heats + 56 head-to-head + 12 calibration + 20 bias control) | **~11 min** | **75% A / 25% B** (hand-labelled, §3) | Turns the 22 demotion candidates the existing run produced into an *executable* swap list. Today they are unusable: evicting a rule to gain empty space is strictly worse than leaving it. | **RUN THIS** |
| 2 | (b) Dedup, as a standalone pass | 424 (146+278) | O(n²) = 89,676 pairs; with a tf-idf prefilter ≈ 400–800 | 30–60 min | ~20% (§3: 4 of 20) | Real, but partly covered by `superseded` — which produced 0 actionable rows | **Refuted standalone (O(n²) / prefilter is a second unvalidated instrument) — but it RIDES SLICE 1 FOR FREE.** See §4. |
| 3 | (a) Promotion, ABSOLUTE — re-use the existing `bite` question on the 278 | 278 | 278 | ~20 min | **Measured 84% one bucket, 0% top bucket** | ~233 orphans would tie with 118 incumbents. Un-rankable. | **REFUTED by the existing run's own distribution** (refutation test (a) and (d) both) |
| 4 | (c) Hook-quality boolean over the rules file | 169 bullets | 169 | ~12 min | **0 of 21 hand-labelled fail** (§3b) | — | **REFUTED: base rate ≈ 0.** The brief's own example of a bad hook (`Empty vs no-surface — two states look alike`) **no longer exists as a bullet** — it survives only inside the file's header as the *cautionary illustration*, and line 90 already carries the expanded form. Commit `d67a81c89` rewrote the file on 2026-09-17. `scripts/rules-hook-budget-lint.sh` already gates the two mechanical failure shapes at the land. |
| 5 | (d) Cross-file contradiction | 424 | O(n²) | — | The one contradiction I went looking for (§1) dissolved on inspection — two surfaces, not two claims | — | **REFUTED: O(n²) and base rate ≈ 0** |
| 6 | *(mine)* Re-score `superseded` at a usable calibration | 140 existing rows | 0 new | 0 | max 0.89, **0 ≥ 0.90** | — | **Not a new slice — a defect in the shipped one.** See §5. |
| 7 | *(mine)* Extend to `reso-management-app` (821 files) | 821 | ~430 | ~31 min | unknown | Larger corpus, but a different repo's index and no session in this repo can read its cap pressure | **Park** — correct sequencing is: prove the instrument here, then port |

---

## 3. Hand-labels

### 3a. The winning candidate — 20 orphan-vs-incumbent comparisons

Anchor (B) = `line-count-is-blind-to-prose-in-table-cells.md`, an incumbent the completed run scored
**`occasionally`, superseded 0.16** — i.e. the weakest *defensible* slot-holder, which makes a win
for A literally the eviction decision. Sample = every 13th orphan. Labels are mine, against the
question "whose absence would more often cause a future agent here to make a mistake".

| # | Orphan | Winner | Why |
|---|---|---|---|
| 1 | `absolution-tokens-and-two-phase-teardown` | **A** | manufacturing crash-lookalikes is a live recurring class here |
| 2 | `argv-census-must-not-carry-its-pattern-in-argv` | **A** | …but **`same_rule` = TRUE** vs indexed `census-matches-itself` + `pgrep-f-matches-agent-briefs` |
| 3 | `bounded-gate-unbounded-by-compliance` | **A** | a real gate class; narrow but recurs |
| 4 | `classifier-ceiling-is-a-terminal-state` | **A** | auto-mode denials are hit constantly |
| 5 | `contract-prose-can-understate-the-mechanism` | **A** | **`same_rule` ~TRUE** vs indexed `spec-named-mechanism-may-be-prose-only` |
| 6 | `desk-autonomy-dormancy-staged-not-loaded` | **B** | a STATE fact ("staged, C10"), perishable — the anti-capture class |
| 7 | `discriminating-retry-must-move-away-from-the-noise` | **A** | generalizable |
| 8 | `exemption-unit-coarser-than-what-it-exempts` | **A** | 29 tests exempted to accommodate 2 — a gate-design rule |
| 9 | `frontier-window-ssot-discipline` | **A** | two real incidents; "never hardcode" recurs |
| 10 | `guard-sample-fields-bound-its-blind-spot` | **A** | fields-not-thresholds is a durable rule |
| 11 | `implicit-team-lifecycle-discipline` | **A** | directly actionable; version-pinned, so partly perishable |
| 12 | `kitty-split-anchors-active-tab-not-caller` | **A** | tool-specific but hit repeatedly here |
| 13 | `metric-denominator-discarded` | **A** | **`same_rule` ~TRUE** vs indexed `positive-control-the-denominator` |
| 14 | `opus-5-staged-adoption` | **B** | **already false** — Opus 5 is the default per `CLAUDE.md § Frontier Tier Routing` |
| 15 | `plutil-extract-clobbers-input` | **A** | destroyed 5 LaunchAgents plists; a destructive-command trap |
| 16 | `reader-census-picks-mode-vs-relocation` | **B** | genuinely marginal; narrow |
| 17 | `reference-screenshot-clipboard-watcher` | **B** | environment-specific and already FIXED — anti-capture class |
| 18 | `safe-direction-invariant-is-an-accumulator` | **A** | "a one-sided invariant has no counter-pressure" — strong |
| 19 | `session-signals-do-not-measure-background-runtime` | **A** | **`same_rule` ~TRUE** vs indexed `turn-adjacency-is-not-wall-clock-adjacency` |
| 20 | `subagent-stop-has-two-shapes` | **A** | opposite exposure by shape; recurring |

**Base rate: A 15/20 = 75%, B 5/20 = 25%. `same_rule` fired 4/20 = 20%.**

Neither is near 0 or 1, so **neither is refuted**. Two properties matter beyond the raw number:

- **The 25% B-rate validates the question's polarity.** Three of the five B-wins (#6, #14, #17) are
  exactly the classes `CLAUDE.md § Memory Hygiene — Anti-Capture List` says never to promote:
  environment-specific one-offs and perishable state. The question separates them without being
  told to. #14 is *already factually false*.
- **A forced comparison cannot fail degenerately the way the absolute scale did.** If it returns
  100% A, that is a verdict ("the anchor is wrong — re-anchor higher"); if 100% B, that is also a
  verdict ("stop demoting; no orphan earns a slot"). Both are informative. The absolute `bite`
  scale's 84%-in-one-bucket outcome is informative about *nothing*.

### 3b. Candidate (c) — 21 hand-labels, systematic sample (every 8th bullet)

Standard applied is the file's own: *"does this hook state a rule an agent could act on without
opening the body?"*

Clear PASS (18): lines 47, 55, 63, 71, 79, 97, 107, 115, 123, 135, 159, 167, 176, 184, 192, 200,
208, 216.
Borderline but still actionable (3): line 37 (`fail-loud into launchd stderr IS silent` — the rule
is the first clause, the rest is incident), line 143 (`Recovery needs hysteresis` — the rule is in
the title, the body states only the consequence), line 151 (`a harness may SAY the run was
incomplete in a line no verdict-deriver reads` — states a fact, implies the action).
**Clear FAIL: 0 of 21.**

**Base rate ≈ 0 → INERT BY CONSTRUCTION, per the brief's own refutation test (a).** The 2026-09-17
tiering commit already did this work by hand, and the land gate holds the line going forward. The
residual — 71 of 169 bullets over the 350-char budget — is a *shape* problem the lint already owns,
and it blocks only on the land's own added lines (deliberately: attribution by reachability is the
polarity this repo has measured as wrong).

---

## 4. The design, and the literal strings

Copy `scripts/jev/rank-memory.sh` exactly: self-resolving `$0` through the symlink farm, `--yes`
consent on the command line, ZDR static refusal, **one preflight call before committing to N**,
`mkdir -p` on the output dir with a loud failure, exponential backoff on `rate-limited`, a VISIBLE
`x` per verdict-less call, **abort after `CC_JEV_RANK_MAX_CONSEC_SKIP` consecutive misses**, JSONL
rows, and **never mutate the subject**. Proposed entry point: `cc-jev promote`.

### 🚨 The single most important mechanical finding: Jev does not have to return a string

Refutation test (c) in the brief — *"it needs a string back (e.g. 'rewrite this hook' — Jev cannot)"*
— is the obvious objection to a promotion pass, because a promoted file needs an index hook and Jev
emits only `boolean` and `choice`.

**It is closed by measurement: 278 of 278 orphans (100%) already carry a frontmatter `description:`
that states the rule in one sentence.** Mean **205 chars**, median **189**, p25 163, p75 217, max
1,335; only 38 of 278 exceed 250 chars. The index's own mean line is ~155 chars. **The hook already
exists on disk for every candidate.** Promotion is therefore a pure `choice` problem: pick the
winner, paste its `description` in as the index line. Same for the 146 incumbents (146/146 carry
one).

This also shrinks the payload. Round 1 sends *descriptions only* — five at ~205 B = ~1,100 B of
state against `CC_JEV_MAX_STATE_B=24000` (`hooks/lib/jev.sh:81`) and the 32k-token ceiling. Round 2
sends description + first ~1,200 B of body for two files ≈ 2,800 B.

### Round 1 — heats of 5 (56 calls)

`choice` over a 5-key map `a`…`e`, state carries the five `description` strings labelled A–E.

```
instructions:
"Five engineering lessons from one codebase's own memory are listed as A through E. The index that
makes a lesson reachable to a future agent is at a hard cap, so only some of these can ever be
loaded. Choose the ONE whose absence would most often cause a future agent working in this codebase
to make a real mistake. Judge the RULE each one states — not how well it is written, not how recent
it is, and not how dramatic its incident was."

criteria:
  a: "A states the rule that would most often prevent a real mistake here"
  b: "B states the rule that would most often prevent a real mistake here"
  c: "C states the rule that would most often prevent a real mistake here"
  d: "D states the rule that would most often prevent a real mistake here"
  e: "E states the rule that would most often prevent a real mistake here"
```

A heat discards 4 of 5, which is correct for this problem: there are **~22 slots at most** (the 21
`occasionally` + 1 `almost-never` the completed run identified), so the top ~56 is already a
generous shortlist and a full ranking of 278 would be paying for an order nobody will use.

### Round 2 — head-to-head vs the incumbent anchor, with the dedup passenger (56 calls)

Two questions in ONE call — `rank-memory.sh` already proves the two-question shape works, and this
is where candidate (b) becomes free.

```
instructions (choice `winner`):
"Two engineering lessons from one codebase's memory are given as block A and block B. Exactly one
index slot is available and the index is at a hard cap, so one of them will be reachable to a
future agent and the other will not. Choose the one whose absence would more often cause a future
agent working in this codebase to make a real mistake. Judge the RULE each block states, not how
well it is written and not how recent it is."

criteria:
  a: "the rule in block A would more often prevent a real mistake here; B restates something
      obvious, applies only to one situation that has already been fixed, or describes a tool,
      path or version that has since been replaced"
  b: "the rule in block B would more often prevent a real mistake here; A restates something
      obvious, applies only to one situation that has already been fixed, or describes a tool,
      path or version that has since been replaced"

instructions (boolean `same_rule`):
"Do block A and block B state the SAME underlying rule, differing only in the incident used to
illustrate it?"

criteria:
  true:  "one is a restatement of the other's rule; keeping both in a capped index would be
          redundant"
  false: "they state different rules, even if both concern the same subsystem or the same tool"
```

**`same_rule` is candidate (b) obtained for zero marginal calls**, on exactly the pairs where a
dedup answer changes a decision: a challenger about to displace an incumbent. Standalone dedup is
O(n²) = 89,676 pairs and is properly refuted; as a passenger it is free and targeted. My hand-labels
hit 4 in 20 (20%), so it will not come back empty.

### Controls — 32 calls, and they are not optional

| Control | Calls | What it refutes |
|---|---|---|
| **Preflight**, one call, verbatim from `rank-memory.sh` | 1 | a dead route reporting "0 of 278" as a well-formatted verdict |
| **Calibration**, 12 calls: 6 known-strong orphans and 6 known-perishable ones (#6, #14, #17 above are three) against the anchor | 12 | an imported threshold sitting outside the output range — the exact failure `hooks/lib/jev.sh` records at 0.98, and the failure `bite`'s 4-level scale is having right now |
| **Position-bias**, 20 calls: re-run 20 round-2 pairs with A and B swapped | 20 | Jev preferring the first slot. Two lessons in one state is a form no existing call site uses; if the swapped run disagrees more than ~20% of the time, the comparative design is dead and the report must say so. **This is the control that can kill the proposal.** |

**Total: 56 + 56 + 32 = 144 calls ≈ 10.2 min of calls at the measured 14.1/min; budget 20–30 min
wall clock with backoff.** The four-day window (ends 2026-09-25) is not a constraint on this at all.

### Envelope compliance

| Envelope bound | This design |
|---|---|
| `boolean` / `choice` only, no `score` | ✅ `choice` (5-key, then 2-key) + `boolean`. No `score`. |
| no strings, lists, spans, objects back | ✅ — and §4's frontmatter finding is why the hook does not need one |
| 32,000-token state ceiling | ✅ ~1,100 B round 1, ~2,800 B round 2, vs `CC_JEV_MAX_STATE_B=24000` |
| ~6 calls/min free tier | ✅ and the real measured rate is 14.1/min |
| ZDR → 403; STANDARD retention | ✅ same static refusal + `--yes` as `rank-memory.sh` |
| DECOMPOSED-EXTRACTOR beats terminal-verdict | ✅ two decomposed questions per call; **no** "should this be promoted?" terminal verdict |
| domain-reputation anchoring | ✅ payload is plain in-repo engineering prose with no URL, no domain, no wrapper |
| standing refusal (no transcripts / mailbox / `msg` / customer data) | ✅ our own engineering lessons only, same corpus `rank-memory.sh` already sends under `--yes` |
| agent cannot make the call | ✅ operator-run or scheduled, exactly as `cc-jev rank` |
| four days | ✅ ~20–30 min |

---

## 5. Two things the lead should act on that are not new slices

**5a. `superseded` is shipping inert, and it is the same defect `jev.sh` documents at 0.98.**
Over 140 rows it ranges 0.08–0.89 with mean 0.28 and **0 rows ≥ 0.90** — the threshold
`hooks/lib/jev.sh` names as the only actionable band. Only 4 rows even clear 0.50. `jev.sh` itself
records this failure mode in its own header (*"0.98 was imported from a DIFFERENT task's calibration
and was unreachable here"*) and the repo carries it as a lesson
(`an-imported-threshold-can-sit-above-the-model-s-output-range`). **The same shape is live in
`rank-memory.sh` right now.** Either re-derive a usable cut from the 140 measured rows (the top of
the distribution is a clean tail: 0.89, 0.86, and two others above 0.5 — those 4 *are* the signal)
or say in the script that `superseded` is a ranking input, never a threshold. Cost: zero calls, the
data is already on disk.

**5b. 6 of the 146 indexed rules were never scored** and the run reports "SCORED 140 of 146" without
naming them. They are: `a-plan-is-not-a-queue`, `damping-store-understates-emission-volume`,
`discriminator-scoped-to-a-window-yields-two-verdicts`, `gate-log-tail-hides-the-first-failure`,
`lossless-fallback-hides-its-dead-primary`, `predicate-error-exit-is-indistinguishable-from-false`.
Six re-runs. Worth doing before any eviction decision reads the list as complete.

---

## 6. Adversarial pass — what I went looking for, including what refuted me

| What I checked | Result |
|---|---|
| Does `cc-jev rank` already cover the proposal? (refutation (d)) | **Yes, for the incumbent half — and its output is degenerate.** This reshaped the entire answer: it killed candidate (a)-as-stated and forced the comparative design. |
| Does promotion need a string back? (refutation (c)) | **No.** 278/278 orphans carry a frontmatter `description`, mean 205 chars. Closed. |
| Is the "reachable from nothing" premise true? | **Overstated.** 267 of 278 are recorded archive demotions. Runtime unreachability survives; "lost" does not. |
| Is there a cross-file contradiction on the caps? | **No** — two surfaces (`MEMORY.md` 25k/200 vs `.claude/rules/*.md` 4 MiB/150k), stated explicitly at `cc-memory-rotate:251-255`. Do not file this. |
| Does a promotion actuator exist? | **No.** `cc-memory-rotate` demotes only; restore is "paste the line back". The consumer of a promotion list is a human paste — **identical to the existing rank's consumer**, so this is a stated limit, not a new one. |
| Is the throughput assumption right? | **No** — 14.1 calls/min measured, not 6. Every wall-clock figure in the brief is 2.35× pessimistic. |
| Are the 26 bare-slug links in the rules file a real loss? | **No** — all 26 targets exist in the memory dir; only the relative prefix is wrong. `sed` fix, one line to the lead. |
| What could still kill the winning slice? | **Position bias.** Two lessons in one `state` is a form no existing call site uses, and Jev could simply prefer slot A. The 20-call swapped control is designed to catch exactly that, and it must run **before** the 56-call round 2, not after. |

**Does its absence get noticed?** Yes, and the mechanism is concrete: the existing run produced 22
demotion candidates against ~3.8 index lines of headroom. **Nobody will execute those 22 evictions
without a promotion list, because evicting a real rule to gain empty space is strictly worse than
leaving it.** The 140-row artifact is inert today for that reason alone. The promotion pass is what
converts it into a swap list — and a swap is a decision somebody will actually take.
