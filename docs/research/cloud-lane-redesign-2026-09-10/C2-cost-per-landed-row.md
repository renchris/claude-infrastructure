# C2 — Cost per LANDED backlog row: cloud lane vs local dispatched lane

Measured 2026-09-10. Read-only. No fire, no POST, no ledger mutation.
Intermediates: `$S/work-C2/` (pop.json, usage30.json, usage_extra15.json, local_usage15_full.json,
grid.txt, robust.txt, final.txt, docs_vs_code.txt, selection.txt, venueplan.txt).

## 0 · Headline

**On medians, the cloud lane costs 1.2–2.1× local per landed row. On means the direction is NOT
invariant (0.71×–2.11×).** The multiplier is not a token-efficiency property of the VM — per FIRE
cloud is *cheaper* (pop-weighted mean $5.63 vs local $21.38). The whole difference is the **re-fire
multiplier**: cloud burns **4.27 declarations per distinct backlog item** against local's **1.47**
on the identical metric, same window, same instrument shape.

| | per fire (pop-wtd) | fires per landed row | per landed row |
|---|---|---|---|
| **cloud** | $5.63 mean / $4.67 med | **7.78** (692 decl ÷ 89 landings) | **$43.80** / $36.30 |
| **local** (general dispatched, +subagents) | $21.38 mean / $12.33 med | **1.48** (566 claims ÷ 382 done) | **$31.67** / $18.27 |
| **local** (backlog-row fires only, +subagents) | $27.32 mean / $13.40 med | 1.48 | $40.48 / $19.86 |

$ = price-weighted MTok-equivalence at Opus 5 list ($5 in / $25 out / $0.50 cache-read / $6.25
cache-write). **An equivalence, not a bill** — every one of these tokens is drawn from a Max-plan
weekly meter, not invoiced. Cross-validated below against the control plane's own `cost_usd`.

---

## 1 · Instrument and population

**Cloud reader.** `scripts/cloud-create-api.py` has NO usage verb — `--verify` (`:493-540`) prints
the §13.3 acceptance pair and `post_turn_summary`, and drops `external_metadata` on the floor. Its
`get_session()` (`:325-336`) IS the reader, so `$S/work-C2/usage_read.py` imports that function and
`creds()` (`:428`) unmodified and reads `external_metadata.usage`. **Auth worked** — no fallback to
the three pre-tabulated sessions in `docs/plans/CLOUD_BACKLOG_PIPELINE.md:120-135` was needed.

`external_metadata.usage` carries a **fifth key nobody has used: `cost_usd`.** The control plane
prices its own sessions.

**Cloud population** — `~/.claude/autonomy/cloud/`, 692 `.decl`, 678 `.retired`, 80 `.returned`,
**0 parse failures** (record-at-a-time, `census.py`).

| stratum | n | definition |
|---|---|---|
| landed | 89 | has `.returned` OR `verdict=landed` |
| **bare-retired** | **279** | `.retired` exists with NO `verdict=` key — the mass sweeps |
| superseded | 154 | |
| conflict | 133 | |
| gone | 23 | |
| never-retired | 14 | |

⚠️ The brief's "10 landed / 10 superseded / 10 conflict" covers 376 of 692 (54%). I extended the
sample by 10 + 5 (same seed) into `bare-retired` and `gone` to reach **98.0% strata coverage** —
without it the population mean is unreachable and the 279-row bare-retired bloc (40% of every
declaration ever fired) is unpriced. n=44 cloud sessions read, **1 API error** (HTTP 404,
`session_01YcTifmgrKh3KFYuz45Rret` — record deleted server-side), **3 sessions returned no `usage`
object at all** (`usage_keys=[]`, all `gone`/`bare-retired`; scored 0).

**Local population.** The brief's named sources do not exist in the shape described:
`~/.claude/autonomy/idl.jsonl` has schema `{ts,hook,sid,disposition,reason}` — its 919 `fired` rows
are **hook firings** (session-continue 420, stop-failure-marker 277), not dispatch fires, and there
is no `cc-dispatch` `hook` value and no `detail` field. `~/.claude/logs/handoffs.jsonl` is rotated
to **2026-09-09 → 09-10 only** and 826 of its 1,073 rows are `under_test:true`. Both are unusable
for an 08-12→09-04 window.

**Substituted instrument (stronger):** every dispatched session's transcript carries the fire's
`HANDOFF-ENGAGE-<pane>-<epoch>-<pid>` marker in its first non-meta user message. Scanning all
**2,656 transcripts** across the five config dirs found **557 dispatched local sessions**
(2026-08: 217, 2026-09: 340), 0 head parse failures. 203 fall in the cloud sample's own
declared_at window (2026-08-12 → 2026-09-04); n=15 drawn with `random.seed(20260910)`.

Usage summed per `message.usage`, **once per `message.id`** (A/B doc §1 method). 0 parse failures
across all 15 transcripts.

---

## 2 · (i) Per-arm token table

### Cloud — by stratum, `external_metadata.usage`

| stratum | n | input | output | cache read | cache write | $wtd mean | $wtd med |
|---|---|---|---|---|---|---|---|
| landed | 10 | 303 | 51,060 | 11,518,360 | 176,437 | **8.140** | 6.647 |
| conflict | 10 | 181 | 55,143 | **14,564,177** | 199,205 | **9.907** | 8.424 |
| bare-retired | 10 | 377 | 26,029 | 5,679,943 | 115,134 | **4.212** | 2.085 |
| superseded | 10 | 86 | 25,002 | 4,759,795 | 138,058 | **3.868** | 4.137 |
| gone | 4 | 5 | 844 | 142,842 | 32,188 | **0.294** | 0.170 |
| **population-weighted** | — | **246** | **33,938** | **7,792,282** | **142,066** | **5.634** | **4.668** |

Spread within a stratum is ~10×: landed runs $1.96 (`…4zdFkDtFrNkM`, 2.48M cache-read) to $21.13
(`…ikd3KVGCnEjL`, 33.1M).

### Local — dispatched sessions, transcript `message.usage`

| arm | n | input | output | cache read | cache write | $wtd mean | $wtd med |
|---|---|---|---|---|---|---|---|
| general, main transcript only | 15 | 185 | 70,943 | 20,639,567 | 308,941 | 14.025 | 11.951 |
| general, **+ subagent sidecars** | 15 | 324 | 76,705 | **30,289,277** | 689,780 | **21.375** | **12.327** |
| backlog-row fires only, +sub | 15 | — | — | — | — | 27.320 | 13.403 |

🚨 **The main transcript is an UNDERCOUNT and this is the adversarial pass's biggest correction.**
Subagent turns write to `projects/<slug>/<sid>/**.jsonl`, invisible to a transcript sum
(`isSidechain` was 0 in all 15 — the memory rule *"Subagents in own files"* holds). 2 of 15
sessions had sidecars; one (`161874bb`, 25 files) added **$97.0** to a $12.0 main transcript.
Mean +52.4%, **median +3.1%** — the correction is entirely a tail effect.

**Model control:** every sampled local transcript is `claude-opus-5`. The cloud control plane
returns `last_served_model: null` on completed sessions, so the cloud arm's model is **assumed**
from lane config, not verified. Named as a threat.

### Price-weight validation

`cost_usd / my-weighted` over 41 sessions: **mean 1.118, median 1.110**, range 0.931–1.353. Solving
for the cache-read rate that best fits `cost_usd` at fixed in=5/out=25/cw=6.25 gives **$0.550/MTok**
against Opus 5 list $0.50. My weighting is within ~11% of what Anthropic's own control plane
computes for the same sessions — a genuine external check, not a self-consistency one.

---

## 3 · (ii) Fires per landed row

| metric | value | source |
|---|---|---|
| cloud declarations ÷ landings, all-time | **7.78** (692 ÷ 89) | declaration store |
| same, C-doc's count | 7.82 (688 ÷ 88) | `C-cloud-pipeline.md` §3 |
| cloud declarations ÷ **distinct item** | **4.22** (675 ÷ 160) | declaration store |
| local claims ÷ done, venue-tagged | **1.48** (566 ÷ 382) | `backlog.jsonl`, 19,815 lines, **0 parse fail** |
| local dispatched fires ÷ distinct item, **same window** | **1.47** (84 ÷ 57) | transcript scan |
| local dispatched fires ÷ distinct item, all-time | 1.41 (169 ÷ 120) | transcript scan |

**The like-for-like number is fires-per-distinct-item: cloud 4.27 (pre-gate) vs local 1.47 — a 2.9×
re-fire tax.** Same unit, same window, same instrument shape. The declarations÷landings figure
(7.78) mixes the re-fire tax with a separate *land-failure* tax and should not be read as one thing.

Cloud's re-fire distribution is extreme: item `01ab05685857` was declared **38 times**,
`0c8b39b67665` 33×, `70ed289c10fb` 30×. Local's worst in-window item is 9×.

### The 2026-09-04 gate cut, and why it cannot be priced

The already-declared gate is `bin/cc-dispatch:2116` — *"this item already has an unlanded cloud
declaration; it needs that session's result returned, not a second session"* — landed
**`124c4da06` 2026-09-04T13:50Z**.

| | declarations | distinct items | decl/item | landings | decl/landing |
|---|---|---|---|---|---|
| pre-gate | 688 | 157 | **4.27** | 89 | 7.73 |
| **post-gate** | **4** | 4 | **1.00** | **0** | **unmeasurable** |

**The gate worked and simultaneously made itself unmeasurable.** Re-fires per item fell 4.27 → 1.00,
but the lane's duty cycle collapsed with it (09-04: 31 declarations · 09-05, 09-06: 0 · 09-07: 5 ·
09-09: 1 · 09-10: 4) and **zero post-gate declarations have landed**. There is no post-cure
landings denominator and n=4 could not support one if there were. Any post-cure per-landed-row
figure is a projection from the pre-cure per-fire cost times an assumed conversion.

---

## 4 · (iii) Tokens per landed row

Cloud, population-weighted × 7.78; local (+subagents) × 1.48:

| axis | cloud /fire | cloud /landed row | local /fire | local /landed row | cloud÷local |
|---|---|---|---|---|---|
| input | 246 | 1,910 | 324 | 480 | 4.0× |
| output | 33,938 | 263,868 | 76,705 | 113,653 | 2.3× |
| **cache read** | 7,792,282 | **60,584,996** | 30,289,277 | **44,879,622** | **1.35×** |
| cache write | 142,066 | 1,104,563 | 689,780 | 1,022,048 | 1.08× |
| **$wtd** | **5.634** | **43.80** | **21.375** | **31.67** | **1.38×** |

Cache read is 88–95% of the weighted cost in both arms — the 08-11 A/B's finding that "cache reads
dominate" reproduces at population scale.

---

## 5 · (iv) Sensitivity

### Full robustness grid — the direction is NOT invariant on means

| cloud landing denominator | local arm | mean ratio | median ratio |
|---|---|---|---|
| 692/89 (declaration store) | general, main only | 2.11× | 2.05× |
| 692/89 | general, +sub | 1.38× | 1.99× |
| 692/89 | backlog-row, main only | 1.21× | 1.83× |
| 692/89 | backlog-row, +sub | 1.08× | 1.83× |
| **692/135 (backlog ledger `done`)** | general, main only | 1.39× | 1.35× |
| 692/135 | general, +sub | **0.91×** | 1.31× |
| 692/135 | backlog-row, main only | **0.80×** | 1.20× |
| 692/135 | backlog-row, +sub | **0.71×** | 1.20× |

**Medians: 1.20×–2.05×, direction invariant. Means: 0.71×–2.11×, direction FLIPS.** The mean is
dominated by local outliers (one backlog-row session cost $142); the median is the defensible
statistic. Reporting only the mean would have produced a 2.1× headline that a second store
overturns.

**The two stores disagree on cloud landings and the disagreement is 1.5×.** The declaration store
says 89; `backlog.jsonl` says 135 cloud-venue items reached `done` (852 claims, 147 distinct, 91.8%
conversion). `C-cloud-pipeline.md` §4 already names this. I report both denominators rather than
picking one.

### Post-cure fire rate

| assumption | cloud $/landed (mean) | cloud $/landed (med) |
|---|---|---|
| all-time 7.78 | 43.80 | 36.30 |
| C-doc last-7d 2.65 | 14.95 | 12.39 |
| post-gate re-fire 1.11, land conversion held at 1.0 | 6.25 | 5.18 |

At the post-gate re-fire rate **and** a hypothetical perfect land conversion, cloud would be
**$5.18–6.25 per landed row against local's $18.27** — a 3× advantage. That is the size of the prize
and it is entirely contingent on the 381 pushed-but-unlanded branches becoming landable.

### Docs-only vs code — the sample supports it for cloud only

Classifying all 89 landed declarations by `git diff --name-only $(merge-base origin/main <branch>)`:
**19 docs-only · 20 code · 6 empty-diff · 44 ref-absent** (branch deleted post-land — a real 49%
coverage hole).

| landing kind | n sampled | $wtd mean | $wtd med | cache-read med |
|---|---|---|---|---|
| docs-only | 4 | **4.489** | 4.741 | 6,139,458 |
| code | 4 | **12.743** | 10.843 | 15,629,228 |

**A code landing costs 2.8× a docs-only landing.** Code landings touch a median of 3 files (mean
3.5, max 9). The local arm **cannot** be classified the same way — its work lands through `/ship`
from worktree branches that are pruned, so there is no surviving ref to diff. Reported as cannot-tell.

---

## 6 · (iv-b) Does waste cost full price? — **No, and conflict costs MORE than success**

| stratum | $ vs landed | reading |
|---|---|---|
| **conflict** | **1.22×** | a conflicting session spends **more** than a landing one |
| landed | 1.00× | |
| bare-retired | 0.52× | |
| superseded | 0.48× | |
| gone | 0.04× | |

**Superseded waste is roughly half-price** — a session that discovers the item is already done
stops early. Its 3.87/8.14 = 48% is the lane's one working economy.

**Conflict waste is worse than full price.** A conflicting session does *all* the work (14.6M
cache-read, the highest of any stratum, above landed's 11.5M), pushes it, and the land is then
refused by a trunk it cannot see. It pays the full task and delivers nothing. All 133 conflict
branches are ahead of trunk.

**Branch-state census over every declaration** (430 of 692 refs present locally):

| stratum | ahead of trunk | merged/empty | ref absent |
|---|---|---|---|
| conflict | **133** | 0 | 0 |
| superseded | **154** | 0 | 0 |
| bare-retired | 43 | 43 | 193 |
| landed | 39 | 5 | 45 |

**381 declarations pushed work that is ahead of trunk.** This reproduces C-doc §3's 379 at a fresh
window. ⚠️ Ancestry over-counts: 39 of 89 *known-landed* branches also read "ahead", because a
rebasing land rewrites the patch-id (memory: `cherry + ≠ absent`). So 381 is an **upper bound** on
unlanded-with-work; the conflict + superseded 287 is the solid floor since neither verdict is
compatible with having landed.

**This is the interpretive crux.** Cloud's 7.78 fires/landing is not a statement about VM token
efficiency. It decomposes into a 4.27× re-fire tax (cured 2026-09-04) and a land-failure tax on
~287–381 branches whose cause is documented and non-token: *"the rebase onto the trunk conflicted —
resolving it needs the trunk the VM's shallow clone cannot see"* and the noreply@anthropic.com
identity gate (`C-cloud-pipeline.md` §3; 631 of 675 refusals routed to nobody).

---

## 7 · Adversarial self-pass

**(a) The selection effect is large and it works AGAINST my conclusion — measured, not assumed.**
`backlog.jsonl` `venue` events (1,205 records, `venuePlan`/`venueWhy`) show **only 134 of 977
distinct items (13.7%) are cloud-eligible.** Exclusion reasons, per distinct item: `ineligible-box`
505 (pane/hook/spawn) · `ineligible-deep-history` 231 · `ineligible-cross-repo` 186 ·
`ineligible-branch-banking` 179 · `ineligible-visual` 111.

Cloud therefore gets a pre-screened, box-independent, shallow-history subset — **the easier work.**
Corroborated by item-shape: cloud items' `add` titles are **median 160 chars** vs local's **434** —
a 2.7× specification-size gap. **Bound: cloud's per-fire cost is biased DOWN by an amount at least
as large as the 2.1×/2.7× task-size gap.** Since cloud still loses per landed row on medians, the
selection effect cannot be what produces the result — it is working to hide it.

**(b) The brief's own arithmetic mixes two units and the mix is measurable.** "local: claims ÷ dones"
divides a *ledger* count by a *ledger* count, but the numerator I price is a *dispatched fire*. Of
158 distinct backlog ids found in local dispatched-fire briefs, only **24 appear in the venue=local
claim set**; 106 are venue-untagged and 43 are in no claim set at all. `B-local-pipeline.md` §4c
already measured the same gap from the other side (`cc-dispatch action=claimed` = 0/1/0 while local
claims ran 86/38). **Remedy applied:** the like-for-like figure in §3 is fires-per-distinct-item
(cloud 4.27 / local 1.47), computed from the same instrument on both sides, which does not depend on
the claim ledger at all.

**(c) The 08-11 A/B's 0.81× reproduces, and my population 0.26× does not contradict it.** Restricted
to *comparable completed work* — cloud code-landings ($12.74 mean) vs local main-transcript
($14.03) — the ratio is **0.91×**, close to the A/B's 0.81× (n=2). The population per-fire ratio
(5.63/21.38 = 0.26×) is a task-shape artefact, not a venue effect. **Per-fire venue cost is at
parity; only conversion differs.** That is the finding.

**(d) My own summary line was wrong and I caught it by reading my table.** `robust.txt` printed
*"every one > 1.0"* while its own grid contains 0.71, 0.80 and 0.91. Corrected in §5; the mean-based
direction is not invariant.

---

## 8 · (v) What could not be measured, and why

| | why |
|---|---|
| **Post-cure cloud cost per landed row** | The 2026-09-04 gate cut re-fires 4.27→1.00 **and** the lane's duty cycle to ~0. 4 post-gate declarations, **0 landings**. No denominator exists. |
| **Which cloud landing count is right (89 vs 135)** | Declaration store and `backlog.jsonl` disagree by 1.5×. Both reported; the ratio spans that gap. |
| **Whether cloud `usage` includes VM-side subagent turns** | No field distinguishes them and no VM transcript is reachable. If it excludes them, cloud per-fire is an undercount and cloud looks *worse*. |
| **Cloud model identity** | `last_served_model` is `null` on every completed session read. Assumed `claude-opus-5` from lane config. Local verified per-message. |
| **Docs-vs-code for the local arm** | Worktree branches are pruned after `/ship`; no ref survives to diff. |
| **Docs-vs-code for 44 of 89 cloud landings** | `origin/claude/fire-*` ref deleted post-land. |
| **Whether 381 "ahead of trunk" is really unlanded** | Ancestry over-counts — 39 of 89 known-landed branches also read ahead (rebasing land rewrites patch-id). Floor 287 (conflict+superseded), ceiling 381. |
| **`~/.claude/logs/handoffs.jsonl` before 09-09** | Rotated away; no `.gz` sibling exists. The transcript-marker scan replaces it and reaches further back (08-12). |
| **1 cloud session** | HTTP 404, record deleted server-side. |
| **3 cloud sessions' usage** | Returned no `usage` object (`usage_keys=[]`); scored 0, all `gone`/`bare-retired`. |
| **Parse failures** | **Zero** across `pop.json` (692 files), `backlog.jsonl` (19,815), `handoffs.jsonl` (1,073), `idl.jsonl` (115,182), custody (1,818), and all 75 transcripts. One transcript vanished between scan and re-read (`w4-cost-ab/9769f585…`) — a live-fleet race, not a parse failure. |

---

## 9 · The one number that decides the lane

**Cloud's per-fire token cost is at parity with local (0.81–0.91× on matched work). Its cost per
landed row is 1.2–2.1× worse purely because 692 fires produced 89 landings.** The 4.27× re-fire tax
is already cured and unmeasured; the remaining tax is 287–381 branches carrying finished, pushed work
that a shallow clone cannot rebase and an identity gate refuses. **Neither is a token problem, so
neither is fixable by spending differently — and both are fixable without touching the VM.** At the
post-gate re-fire rate with landings restored, the same measurements put cloud at **$5.18–6.25 per
landed row against local's $18.27**.
