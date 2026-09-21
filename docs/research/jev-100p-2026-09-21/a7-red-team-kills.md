# A7 — RED TEAM: kill list for the six Jev candidate families

**2026-09-21. Read-only. Every number below was measured on this machine today; commands to
re-derive are inline. Nothing here is argued where it could be counted.**

**Verdict up front: five of six families are DEAD. One is WOUNDED and survives only in a form 1/10th
the size its proposers will describe. The single most dangerous family is (e) memory ranking, because
it is the one that reproduces rank 1's anti-correlation failure exactly, and it is already built and
already shipping zero rows.**

---

## 0. The prior, restated so it binds

Rank 1 of `jev-at-cost-api-2026-09-18.md` §4 was the only candidate ever built. It failed on real
traffic in a way no threshold could rescue: over **160 real closes**, `p >= 0.90` selected 4 rows and
`class == 'drivable'` selected 6 rows, and **the two sets were disjoint** (Addendum 4). The arm was
not slightly mis-tuned — *the more confident Jev was that work was being handed back, the more likely
it was to classify the wall as legitimate.* The shape of the data, not the constant, was the defect.

Three structural facts from the envelope do most of the killing below, so they are stated once:

| Fact | Consequence for a candidate family |
|---|---|
| **Jev has no tools.** It is a pure text→probability (or text→key) function. | Any question whose answer lives on the filesystem, in a process, or at a vendor is **unanswerable in principle**, not merely inaccurately answered. |
| **Jev cannot emit a string.** `boolean` and `choice` only; `score` is declared in the SDK and rejected `invalid-response` by the runtime (measured, `a0ceab890`). | Any family whose *useful* output is a rewrite, a falsifier command, a correction, or a rationale is out on the answer shape alone. |
| **The control that embarrasses everyone: a two-line regex scored 91.6% where Jev's full decomposition scored 95.0%.** | In this repo the static control is usually not hypothetical — it is **already shipped**, and in three of six families it is the incumbent. |

**Measured throughput, for every wall-clock claim below:** `cc-jev rank` was clocked at **146 calls ≈
70 minutes** (`5acaeea16` commit body) — ~2.1 calls/min, not the nominal 6. The free window closes
**2026-09-25**. That is the real budget: roughly **one pass of ≤200 items**, once.

---

## (a) In-hook semantic verdicts on a hook other than anti-deference

### The strongest kill argument
The 2026-09-18 doc partitioned the hook surface once and found exactly two semantic members, one of
which (`completion-assert` authorship) was then refuted structurally. Family (a) is the claim that a
**third** exists. I re-ran the partition independently and found one plausible candidate —
`waiting-recycle`, which carries two large prose regexes (`ROT_TELLS` at `hooks/waiting-recycle.sh:1079`
and `GENUINE` at `:1147`). It is the hottest hook on the machine: **110,401 of 154,439 IDL decisions
(72%)**.

And it is inert in exactly rank 1's shape. The semantic branch sits *downstream of a structural arming
conjunct that almost never opens.*

```
{ cat ~/.claude/autonomy/idl.jsonl; gunzip -c ~/.claude/autonomy/idl.jsonl.*.gz; } \
  | jq -rc 'select(.hook=="waiting-recycle")|[.disposition,.reason]|@tsv' | sort | uniq -c | sort -rn
```

| waiting-recycle, 10.6 days | count |
|---|---|
| total decisions | **110,401** |
| `abstained / not-armed` — never reads the message at all | **79,748 (72.2%)** |
| rows where the text branch was **reached** (reason carries `rot=`) | **2,417 (2.2%)** |
| of those, `rot=1` — the semantic regex firing | **0** |
| `open-decision-hold` — the `GENUINE` regex firing | **0** |
| non-abstain dispositions of any kind | **17** (7 fired, 2 escalated, 8 gc) |

### Measured base rate and P(zero fires)
Observed positives on the reached population: **0 of 2,417**. Rule of three ⇒ 95% upper bound on the
true rate = `3/2417 = 0.124%`. A **perfect** detector operating at that upper bound:

| run size | P(zero fires) |
|---|---|
| 160 | **82.0%** |
| 200 | **78.0%** |
| 400 | 60.8% |

At the only run size the 4-day free window affords, a flawless replacement for this regex returns zero
**four times in five**. That is base-rate inertness by construction, and it is the same arithmetic
Addendum 3 had to be corrected for not doing.

Every other text-touching hook is structural on inspection, not semantic:

| hook | what it does with `last_assistant_message` |
|---|---|
| `stop-failure-marker` (`:104`) | matches vendor-fixed error strings (`Not logged in · Please run /login`) |
| `subagent-stop` (`:93`) | extracts the report body as a *field*; makes no judgment about it |
| `handoff-claim-assert` (`:58`) | `case "$MSG" in *"▶"*)` — one literal glyph |
| `session-continue` (`:351`) | the kill-switch phrase — **the population already refuted** in Addendum A |
| `boundary-handoff`, `goal-inert-watch`, `dispatch-assert` | thresholds, git reads, stamps, pids |

### Regex baseline
Not applicable in the usual sense: the incumbent regexes already exist and their measured fire rate is
**0/2,417**. There is nothing for a classifier to beat. A classifier at 100% recall over a population
with no positives is indistinguishable from an unplugged cable — which is precisely
`fail-safe-default-mimics-the-healthy-state`, already in this repo's rules.

### Anti-correlation
The caller-side conjunction would be `armed_and_fresh AND jev_says_rot`. These terms are **negatively
related by construction and the hook's own comment says so**: `:1082-1085` records that the rot-tell
must be floored at `used_pct >= ROT_FLOOR` because *"the shipped regex matches HEALTHY watch narration
('re-checking which sessions are still running')"* — i.e. the prose tell is loudest exactly when the
structural condition is absent. This is rank 1's failure with different variable names.

### Named consumer
`waiting-recycle` already fires 7 times in 110,401. Adding a semantic arm to a hook whose actuation
rate is 0.006% changes nothing any consumer observes.

### **VERDICT: DEAD.**

---

## (b) Backlog / decision / pending-activation row revalidation

### The strongest kill argument
**The decisive quantity is never in the prompt.** A row's premise is a claim about the world; Jev can
only read the row's prose. I hand-labelled 12 open rows drawn at random (seed 7) against the question
*"is this row's premise decidable from the row text alone, with no filesystem, no process table, no
vendor?"*

| row | premise | text-decidable? |
|---|---|---|
| `f36bc0986c43` | cloud session stalled, branch ref frozen 63 min | no — needs the ref |
| `93e2f7730466` | plan still holds work | no — **and it already carries a shell falsifier** |
| `e61141117af5` | FileChanged/CwdChanged not wired | no — needs `grep settings.json` |
| `762df4cd78b5` | AI Gateway key not created | no — needs the env / agent-secrets |
| `724a2d2682d5` | 487 LOC vs a 400 cap — "a taste call" | no — operator's |
| `71bd004cc416` | announce reached no live lead, pane 390 dead | no — needs the pane table |
| `b9aaea42cd4d` | wrong shipping address at a vendor | no — real world |
| `4a4b97a2585e` | watch-file has no producer | no — needs `grep` |
| `19e28a3a5741` | 3.5 GB of /tmp to reclaim | no — needs `du` |
| `532fbee4d4a8` | two hooks livelock each other | no — needs the code |
| `9381bf26d754` | rule by eye on two emote candidates | no — operator's eyes |
| `78290b95a07d` | cloud session waiting to be landed | no — needs the branch |

**0 of 12.** Not one. Eleven need a command; the twelfth already *has* the command.

### Measured base rate
- Open rows: **354** of 3,728 distinct ids (`event != done` on the last record).
- Rows carrying `needs` — i.e. **operator-gated**: **337 / 354 = 95.2%**. A revalidation verdict on an
  operator-gated row changes nothing an agent may do.
- Rows carrying a `falsifier`: **37 / 354 = 10.5%**. Rows carrying a `premise` field: **12 / 354 = 3.4%**.
- Decisions store: **264 packets, 51 open** — every one class B/C with `veto_deadline` and
  `default_if_no_veto`; **76 are already `expired-actioned`**, so the date mechanism demonstrably works.
- pending-activation: **54 scripts, 44 `.done` markers**. `ls *.done` separates run from unrun.

The real gap here is not inference. **89.5% of open rows were filed without a falsifier** — an
*authoring* deficit. Fixing it requires emitting a shell command, which is a **string**, which Jev
cannot produce. The family's own remedy is outside the answer shape.

### Regex baseline
```bash
# date-rot, whole store, one pass
jq -r 'select(.falsifier)|.id' ~/.claude/autonomy/backlog.jsonl | sort -u | while read i; do
  cc-premise run_falsifier "$i"; done        # the SHIPPED re-check, already run at claim time
# operator-gated split
jq -r 'select(.needs)|.id' ~/.claude/autonomy/backlog.jsonl | sort -u | wc -l     # 337
```
`bin/cc-premise` already re-runs the stored falsifier **at claim time** and refuses the claim on exit 0.
The mechanism exists, is load-bearing, and is deterministic.

### Anti-correlation
Conjunction: `jev_says_stale AND row_is_agent_drivable`. The rows a language model will most confidently
call stale are the ones written most tentatively — and 95.2% of open rows are operator-gated *precisely
because* they were hard to settle, so they are written at maximum hedge. The two terms plausibly oppose.

### Named consumer
The operator, via `cc-backlog list --blocked` — which already renders all 353 rows in full. A ranked
JSONL beside it is a second, worse copy of a list they already have. `a-row-you-file-carries-the-same-burden`
and `alarm-polarity-and-attention-budget` both apply.

### **VERDICT: DEAD.**

---

## (c) Commit-body quality and over-claim detection

### The strongest kill argument
**The output is unactionable by construction.** A commit body is immutable once landed; amending it means
rewriting published history, which this fleet's Git Safety forbids outright. So a detection tomorrow
changes *nothing* about the commit it names. The only actionable placement is a pre-commit gate — which
is family (a), i.e. blocking a commit on a probabilistic verdict, on the surface where the repo's own
rule is **"Never use `--no-verify` to bypass pre-commit hooks."** A fail-open probabilistic blocker is
either inert or it stops real work.

The second kill: **over-claim is not a property of the prose.** These bodies say *"Measured 2026-09-15,
one variable, both arms: load/core 1.92 ⇒ 60/7; re-run at 18.16 ⇒ 67/0."* Whether that is an over-claim
requires **running it**. Jev would be scoring prose *confidence*, and this repo's prose is uniformly
confident-with-receipts.

### Measured base rate
- Commits, 30 days: **1,939**; with a body: **1,814 (93.6%)**.
- **Realized** over-claims — commits whose subject is a correction/refutation/withdrawal of an earlier
  claim: `git log --since=30.days --format='%s' | grep -ciE '(correct|refut|was (false|wrong)|rotted|withdraw|retract)'`
  ⇒ **65 / 1,939 = 3.4%**. Every one I read was discovered by **running something**, never by re-reading prose.
- Hand-label of 12 randomly drawn bodies for "this body over-claims": **0 of 12.** (Honest limit: n=12
  gives only a ≤22.9% upper bound — this is the weakest base-rate estimate in the document, and it is
  *not* what kills the family. The consumer argument is.)
- Diff sizes, last 300 commits: median 6,450 B, p90 34,143 B; **89.7% fit under 32 KB**. So the 32k state
  ceiling is **not** a binding kill here, and I will not pretend it is.

### Regex baseline
```bash
git log --since=30.days --format='%H %s' | grep -iE '(correct|refut|rotted|withdraw|retract|was (false|wrong))'
```
65 rows, 0.2 s, and they are the *ground truth* the family wants to predict. More to the point the repo
already gates the real risk from three sides: `completion-assert.sh` blocks a false-done against the live
ledger, `/ship` content-verifies the land, and `postland-verify` re-runs the suites. A semantic reader of
the prose adds a fourth opinion on a question three mechanisms already answer with facts.

### Anti-correlation
Conjunction: `jev_says_overclaim AND the_claim_is_actually_false`. Directly opposed on this corpus — the
bodies that read most assertive are the ones carrying the most measurement, and the ones that read hedged
are the corrections that are already right. Expect the classifier to index on rhetorical register and
thereby select the *best* commit bodies in the repo.

### Named consumer
None. Nobody re-reads landed commit bodies for accuracy; the `git show <sha>` tier is read forward, when
someone is chasing a specific change. A ranked list of suspect bodies has no reader and no available action.

### **VERDICT: DEAD.**

---

## (d) Plan-section premise rot

### The strongest kill argument
**The incumbent is not a hypothetical regex — it is shipped, stored on every plan-open row, and re-run at
claim time.** `scripts/plan-phase-scan.sh --falsify` (`:47-110`) is a deterministic plan-premise falsifier
with a positive control (zero sections ⇒ exit 2, never a green), a shadowing rule making it a strict
superset of `cc-premise`'s derived arm, and a version-identity guard (it prints the token `FALSIFIED`
rather than relying on an exit code an older deployed copy would fake). It was built in direct response to
backlog `82a6c1894384`, whose trigger incident was a row sitting open twelve days under a stale title.

Building a semantic premise-rot detector here is re-implementing a tool whose entire design history is a
record of the traps a naive version falls into.

### Measured base rate
```bash
for f in docs/plans/*.md; do bash scripts/plan-phase-scan.sh "$f"; done   # 90 plans
```
| | |
|---|---|
| plans | **90** (7.94 MB; median 44 KB; **11 of 90 exceed 128 KB ≈ the 32k state ceiling**) |
| sections | **2,185** |
| `PENDING` | **1,944 = 89.0%** |
| `DONE` | 235 · `SUPERSEDED` | 6 |

**89% PENDING is base-rate inertness from the other end.** Asked "has this section's premise rotted?" over
a population that is 89% one class, Jev will either say yes nearly everywhere (useless) or no nearly
everywhere (inert), and it has no way to check either answer. Neither outcome is a ranking.

### Regex baseline — two lines, and it already beats the proposal
```bash
for f in docs/plans/*.md; do echo "$(( ($(date +%s) - $(git log -1 --format=%ct -- "$f")) / 86400 )) $f"; done | sort -rn
```
| staleness | plans |
|---|---|
| untouched > 7 d | **77 / 90 = 86%** |
| untouched > 14 d | 57 / 90 = 63% |
| untouched > 30 d | **50 / 90 = 56%** |
| median | **34 days** · max 71 |

A one-line `git log -1` ranks all 90 plans by staleness in under a second, at zero calls, with a number a
reader can check. Combined with `--falsify`'s exit code this is a complete, deterministic answer.

### Anti-correlation
Conjunction: `jev_says_premise_rotted AND the_section_is_still_open`. The sections a model most confidently
calls rotted are the ones written with the most specific perishable detail (a sha, a count, a date) — and
in this repo those are exactly the sections *most* carefully maintained, because their specificity is what
makes rot visible and fixable. The vaguest sections rot silently and read fine.

### Named consumer
`cc-premise` at claim time — and it already has a probe it trusts, which by its own composition rule
(**a stored probe SHADOWS a derived one**) would *displace* rather than complement a Jev arm. Inserting a
weaker, non-deterministic probe into a slot whose design rule is "a fast path must never be weaker than
what it shadows" is a regression, not a feature.

### **VERDICT: DEAD.**

---

## (e) Memory / lesson ranking beyond the indexed 146

### The strongest kill argument
**It is already built, it has already run, and it has produced zero rows — and the reason it produced zero
rows is the exact family of failure this whole investigation is about.** `cc-jev rank` landed as
`a0ceab890`; it was run against the live index and made **224 calls, 0 rows written**, because ZDR fails
closed on a hobby plan and each 403 incremented `skipped` silently. The fix commit `5acaeea16` names the
shape itself: *"a ranker that treats a dead route as 146 independent shrugs… A FAILURE THAT RENDERS AS A
RESULT."* That is three instances of the same defect in one tool.

The second kill is the incumbent, and it is stronger than anywhere else in this document. `bin/cc-memory-rotate`
already implements `durability_rank()`:

```
rank 0  the author DECLARED it dead: `superseded_by:` in the topic frontmatter
rank 1  no executable consumer found
rank 2  cited BY NAME in shipped code or an always-loaded rules file — a LIVE OPERATING RULE
```

Rank 1/2 **is the grep**, and its header records that it was already A/B'd against the obvious alternative:
*"Measured 2026-09-04 on the exact 25-entry set age-ordering would have taken at the next breach: 24 of them
are cited BY NAME in shipped code… age is not merely uninformative, it is ANTI-correlated with durability."*
The winning signal was found, measured, and shipped, without a model.

### Measured base rate — I re-ran the grep control myself, 20 seconds, 3,122 files
```python
names = re.findall(r'\]\(([a-z0-9\-]+)\.md\)', open(MEM+'/MEMORY.md').read())   # 146
# count files in the repo containing each slug
```
| | |
|---|---|
| indexed slugs | **146** |
| **zero in-repo citation** (rank-1 demotion pool, computed free) | **39 / 146 = 26.7%** |
| exactly one citation | 16 / 146 = 11.0% |
| median citations | **4** · p90 34 · max 150 |

A ten-line grep partitions the entire index into a 39-item demotion pool and a 107-item keep set. That is
the whole of what the ranker was built to produce, at zero calls.

### 🚨 Anti-correlation — this is the family most at risk, and the risk is MEASURED
Look at *who* is in the zero-citation pool:

```
feedback-parallelize-by-default · feedback-oversight-outranks-throughput
feedback-unmeasured-is-not-unreal · feedback-drive-credential-and-setup-acquisition
feedback-no-artificial-timelines-drive-to-completion · feedback-accounts-before-handoff
```

**7 of the 39 (18%) are `feedback-`/`reference-` prefixed — the operator's own standing directives.** They
are the highest-value entries in the index and they have zero code citations *because they govern an agent's
judgment rather than a script.* Jev's question — *"how often would this rule change what an engineer or agent
actually DOES here?"* — would score these **highest**, precisely where the citation grep scores them **lowest**.

The caller-side conjunction is `low_citation AND jev_says_low_value`. On the stratum that decides the
eviction, **the two terms are negatively related.** This is rank 1's `p>=0.90 AND class=='drivable'` with
the nouns changed, and it is the finding the lead most needs to see before someone builds this a second time.

The correction is, once again, a grep: `grep -v '^feedback-\|^reference-'` cuts the pool from 39 to **32**
and removes the entire anti-correlated stratum for free.

### Wall clock against the 4-day window
At the measured **146 calls ≈ 70 min**:

| population | calls | wall clock |
|---|---|---|
| indexed index | 146 | ~70 min |
| 334 unindexed topic files | 334 | ~2.7 h |
| 480 files in this one memory dir | 480 | ~3.8 h |
| 3,374 memory `.md` fleet-wide | 3,374 | **~27 h** |

Only the first two fit the window at all, and neither leaves room for the second pass a calibration needs.

### Named consumer — the one real one in this document
`cc-memory-rotate`'s eviction order, at the next index breach. And there **is** a genuinely undecided
sub-question the grep cannot answer: *within* the 32 zero-citation non-`feedback` entries, what is the
eviction order? The tool's current tiebreak is `mtime`, and **the tool's own header says mtime is
anti-correlated with durability.** So one slot — an ordering over 32 items, ~20 minutes of calls, with a
named consumer and a concrete action (which entry dies at the next breach) — is real.

That is 1/10th of what this family will be proposed as. Everything above the 32-item tiebreak is already
served by a grep that was measured to beat the alternative.

### **VERDICT: WOUNDED — survives ONLY as an ordering over the 32 zero-citation, non-`feedback` topic files,
feeding `durability_rank()`'s mtime tiebreak. Any proposal larger than 32 calls is the anti-correlated
version and must be refused.**

---

## (f) Decorative-test detection in `tests/*.bats`

### The strongest kill argument
**The static analyzer already exists, already ran, and the mechanical class is swept to zero.**

```
$ python3 scripts/bats-assert-liveness.py --summary
── 0 dead assertion(s) in 0 of 718 file(s)
```

`scripts/bats-assert-liveness.py` is a block-position analyzer calibrated to the *oldest* bash a suite may
meet (bash 3.2 errexit exemptions for `[[ ]]`, `(( ))`, `! cmd`), conservative in the safe direction, with
a fixer (`bats-assert-liveness-fix.py`), a ratchet suite (`tests/bats-assert-liveness.bats`), and a research
record (`docs/research/BATS_DEAD_ASSERTIONS_2026-07-25.md`). It reports **0 dead across 718 files and
14,693 `@test` bodies.**

The second kill is better: **the residual class has a free, exact oracle.** A test that asserts but whose
assertion is vacuous — an "equivalence guard" — is detected by **building the mutant and running it**. The
repo already carries that rule as a standing lesson (`green-in-both-arms-is-an-equivalence-guard-not-a-red-proof`:
*"its death is the only evidence of power"*) and a companion warning that one dead class found is not the
last (`one-dead-assertion-class-found-is-not-the-last-one`). Mutation testing is deterministic, costs $0,
and answers *exactly* the question. Jev reading a test body can only guess at what running it would prove.

### Measured base rate
My own crude 3-line control over all 14,693 bodies:

| | |
|---|---|
| `@test` bodies | **14,693** in 718 files |
| dead assertions per the shipped analyzer | **0** |
| bodies with no assertion-shaped token (`[[`, `[ `, `assert`, `fail`, `\|\| false`, `((`, `grep -q`, `==`, `-eq`) | **274 = 1.9%** |
| bodies containing a bare `skip` | 21 |

Spot-reading the 274 (e.g. `tests/test-hermeticity-lint.bats`, `tests/cc-backlog.bats`) shows nearly all of
them delegate to a named helper that asserts internally — so the true residual after one more line of regex
is a small fraction of 1.9%. At a 1% positive rate and n=200, a *perfect* detector fires ~2 times; at the
more likely 0.2%, P(zero fires at n=200) = **67%**.

### Anti-correlation
Conjunction: `jev_says_decorative AND the_test_actually_survives_its_mutant`. Opposed on this corpus: the
most thorough tests here are the ones with long setup and a single terse final assertion (the *only* live
position under bash 3.2), which reads decorative; the ones littered with mid-body `[[ ]]` look rigorous and
are the ones the analyzer was written to convict.

### Named consumer
`scripts/bats-assert-liveness.py` is already wired into the land gate as a ratchet. A second, probabilistic
opinion has no slot: a ratchet that cannot be trusted to be deterministic cannot gate a land, and one that
does not gate a land is a report nobody opens.

### **VERDICT: DEAD.**

---

## Summary table

| family | base rate (measured) | P(zero fires @ n≈200) | static incumbent | anti-correlation risk | consumer | verdict |
|---|---|---|---|---|---|---|
| **(a)** in-hook semantic, other hooks | **0 / 2,417** reached (≤0.124%, rule of 3) | **78%** | the regexes themselves, firing 0× | **high** — hook's own comment says the tell fires when the structural arm is absent | actuation 7 / 110,401 | **DEAD** |
| **(b)** backlog / decision / activation rows | **0 / 12** text-decidable; 95.2% operator-gated | n/a — unanswerable in principle | `cc-premise run_falsifier`, shipped, at claim time | medium | the operator, who already has the list | **DEAD** |
| **(c)** commit-body over-claim | 65/1,939 = 3.4% realized, all found by running; 0/12 hand-labelled from prose | ~0.1% (but irrelevant) | `git log \| grep -iE 'correct\|refut'` + three shipped gates | **high** — indexes on register, selects the best bodies | **none** — history is immutable | **DEAD** |
| **(d)** plan-section premise rot | **1,944 / 2,185 = 89% PENDING** | inert at either pole | `plan-phase-scan.sh --falsify`, stored per row | medium-high | `cc-premise` — whose rule would *shadow* a weaker probe | **DEAD** |
| **(e)** memory / lesson ranking | **39 / 146 = 26.7%** zero-citation, by grep, in 20 s | — | `cc-memory-rotate durability_rank()`, A/B'd vs age | 🚨 **highest, measured** — 18% of the pool is `feedback-*` operator directives | `durability_rank()` mtime tiebreak | **WOUNDED** (32 items only) |
| **(f)** decorative `.bats` tests | **0 dead / 14,693 bodies**; 1.9% crude-flag residual | **67%** at 0.2% | `bats-assert-liveness.py` + ratchet, already at land gate | high | already occupied by a deterministic ratchet | **DEAD** |

---

## SURVIVORS, ranked (the whole list)

**1. (e), and only in this shape:** an ordering over the **32** zero-citation, non-`feedback`/`reference`
indexed topic files, emitted as a `choice` over ordered keys, feeding the `mtime` tiebreak inside
`cc-memory-rotate`'s `durability_rank()` — the one slot in this repo where a signal is *known to be missing*
and the incumbent tiebreak is *documented by its own author to be anti-correlated*. **32 calls, ~20 minutes,
one named consumer, one concrete action** (which entry is evicted at the next MEMORY.md breach). Anything
larger is the anti-correlated version.

**That is the list.** Five families are dead and the sixth survives at 32 calls. If the wave returns a
ranking with three or four "promising" families on it, the ranking is the 2026-09-18 §4 event repeating.

---

## The kill shot the lead is most likely to talk itself past

**The UNNOTICED-OUTPUT TEST.** The other three are numeric and therefore hard to wave away — a base rate is
a count, a regex baseline is a command that runs, an anti-correlation is a 2×2 someone can print. But "who
is the consumer, and what action changes?" has no number attached, and every one of these families produces
an output that *looks* useful: a ranked JSONL, sorted, with probabilities, formatted. The lead will accept
"a future session reading the report" as a consumer, and this repo's own corpus already says that is not
one — `detector-with-no-owner-is-not-an-actuator`, and `closures ≠ value delivered (40–55% of closures were
no-ops)`.

Three specific phrasings to refuse on sight, because each is a consumer-test failure wearing a justification:

1. *"It's offline and precomputable, so it's cheap to try."* — Cheapness is not a consumer. §4 rank 3 was
   sold on exactly this sentence and it is the family that has since made 224 calls and written 0 rows.
2. *"Even a partial ranking is better than nothing."* — Only if something reads it. `durability_rank()`
   reads a rank; `cc-backlog list` does not; nothing at all reads a commit-body score.
3. *"Addendum 4 itself says Jev has not been evaluated on any task other than deference detection."* — That
   sentence was written to stop someone re-opening the deference question, not as an invitation to open five
   more. It names a **gap in evidence**, which is not the same as a **candidate**.

And one specific trap on the numbers: the lead will read family (e)'s 26.7% zero-citation figure as evidence
that **there is plenty to rank**. It is the opposite — it is evidence that the **grep already ranked it**,
and the only residue is the 32-item tiebreak.

## Re-derive, never re-quote

```bash
# (a) the reached population and its zero positives
{ cat ~/.claude/autonomy/idl.jsonl; gunzip -c ~/.claude/autonomy/idl.jsonl.*.gz; } \
  | jq -rc 'select(.hook=="waiting-recycle")|.reason' > /tmp/wr.txt
grep -c 'rot=' /tmp/wr.txt; grep -c 'rot=1' /tmp/wr.txt; grep -c 'open-decision-hold' /tmp/wr.txt

# (b) open rows, operator-gated share, falsifier coverage
jq -r '.id' ~/.claude/autonomy/backlog.jsonl | sort -u | wc -l

# (c) realized over-claims
git log --since=30.days --format='%s' | grep -ciE '(correct|refut|rotted|withdraw|retract|was (false|wrong))'

# (d) section census + the free staleness rank
for f in docs/plans/*.md; do bash scripts/plan-phase-scan.sh "$f"; done | grep -c '"status": "PENDING"'
for f in docs/plans/*.md; do echo "$(( ($(date +%s) - $(git log -1 --format=%ct -- "$f")) / 86400 )) $f"; done | sort -rn

# (e) the grep that already ranks the index
#     (slug list from MEMORY.md link targets; count files in the repo containing each)

# (f) the incumbent, at land-gate settings
python3 scripts/bats-assert-liveness.py --summary
```
