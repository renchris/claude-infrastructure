# B1 — Autopsy of the 381 ahead-of-trunk `claude/fire-*` branches

Measured 2026-09-10 20:26-21:10Z in `/Users/chrisren/Development/.worktrees/cloud-lane-research`
against `origin/main = 7ae2500a4` (2026-09-10T15:00:33-05:00). Read-only; 430 refs fetched into
`refs/cc-research-b1/*` and deleted at the end. Intermediates: `$S/work-B1/`.

> **Trunk moved during the run.** `origin/main` advanced `7ae2500a4 → ce089b609` (a sibling land)
> between the fetch and the teardown. Every figure here is computed against `7ae2500a4` and is therefore
> internally consistent but one land stale; the direction of the drift only raises today's conflict rate,
> so it cannot weaken the conclusion.

## Headline

**Latency is the cause, and the measurement is longitudinal, not cross-sectional.** Replaying each
branch's merge against *the trunk commit that existed at its own push* shows **93.4% of the 381
stranded branches were landable at the moment they were pushed** and **90.0% one hour later**. Today
5.5% are. The `conflict` and `superseded` retire verdicts are both **effects of elapsed time**, not
independent causes — they are true labels applied to a population that had already been left too long.

**But the delay was not the lander losing a race — it was the lander never running.** The observed
median lag from a branch's last push to the *first land-shaped event of any kind* is **207 h (8.6
days)**; only **2.9%** got one within 1 h. And 99.1% of the 1,016 recorded `land-refused` rows are
**rc 70 (re-authoring failed)** and **rc 65 (could not fetch the branch as a local head)** — only
**9 rows in the entire ledger are rc 5, the rebase conflict**. The arm that produced the stranding is
a re-authoring/fetch defect plus a budget-deferral loop, and `conflict` is what the branches became
while that defect went uncured.

---

## (i) Cause table — all 381 ahead-of-trunk tips

Population: `git ls-remote --heads origin 'claude/fire-*'` = 430 refs; 49 have `rev-list --count
<merge-base>..<ref> == 0` (nothing unique) leaving **381 ahead of trunk**. Cause = `git merge-tree
--write-tree origin/main <ref>` (rc 1 = conflict; the same instrument `scripts/cloud-return.sh:655-663`
uses) × the folded item status from `bin/cc-backlog list --all --json`.

| cause | n | % | docs-only | code |
|---|---:|---:|---:|---:|
| conflict + item `done` | 249 | 65.4% | 48 | 201 |
| clean-rebase + item `done` (**superseded**) | 78 | 20.5% | 47 | 31 |
| conflict + item `open` | 20 | 5.2% | 0 | 20 |
| conflict + item `blocked` | 13 | 3.4% | 9 | 4 |
| **clean-rebase + item open/claimed (landable now)** | **12** | **3.1%** | 4 | 8 |
| clean-rebase + item not in ledger (`cc-offload` probe briefs) | 8 | 2.1% | 1 | 7 |
| clean-rebase + item `blocked` | 1 | 0.3% | 0 | 1 |
| **TOTAL** | **381** | | **109** | **272** |

- **boot-commit-only: 0.** No ahead-of-trunk branch has an empty diff against its merge-base. A subject
  grep for `boot` returns 12 branches, but every one is a *feature named* "boot beacon / boot contract"
  touching 3-14 real files — the loose regex is a false-positive trap. The nearest analog to "no work"
  is 4 branches whose sole file is `tools/b2v-probe/claude-fire-*.txt` (a burst-probe artifact).
- **undeclared: 0.** Every one of the 381 joins to a `~/.claude/autonomy/cloud/*.decl`. 8 carry an
  `item=` that is a brief *filename* rather than a backlog id (`cc-offload ab-brief.txt`, etc.) — the
  `cc-offload` lane, not `cc-dispatch`.
- **already-landed-by-content: 9** of 381 have every touched path byte-identical on trunk
  (`git diff --quiet origin/main <ref> -- <path>` for every path). Small, because
  `cloud-retire-terminal.sh`'s `landed` verdict and `branch-prune-landed.sh` already remove that class.
- **Positive control on my instrument: 133/133.** Every declaration the lane itself retired with
  `verdict=conflict` reproduces as merge-tree rc 1 under my run. No disagreement in that direction.
  In the other direction the lane's `superseded` (155) splits 107 conflict / 48 clean — expected, since
  supersession is judged on the ledger and never on the tree.

**The pile is not 381 pieces of work — it is at most 87, and 11 are live.** The 381 branches resolve to
**87 distinct items**; 274 of them (72%) belong to items with **8 or more sibling branches**, topped by
one item fired **33 times** (`01ab05685857`, postland-verify INERT) and another **32** times
(`0c8b39b67665`, the CLOUD_OBSERVABILITY boot contract). Only **11 distinct items** have at least one
merge-clean branch and a non-`done` status.

---

## (ii) Conflict rate vs trunk distance — the brief's buckets are degenerate, and the cross-section is confounded

`git rev-list --count <merge-base>..origin/main`, today:

| trunk distance (commits) | n | conflict | rate |
|---|---:|---:|---:|
| 0-25 | 1 | 0 | 0% |
| 26-100 | 1 | 0 | 0% |
| 101-300 | 1 | 0 | 0% |
| 301-1000 | 264 | 214 | 81.1% |
| 1000+ | 114 | 68 | 59.6% |

99.2% of the population sits in the top two buckets, so the requested table carries almost no
information — and what it does carry points the **wrong way**: median trunk distance is **884 for
conflicting** branches against **978 for clean** ones. Finer buckets are non-monotone:
`<=300` 0% · `301-600` 36% · `601-900` 87% · `901-1200` 77% · `1201-1500` 25% · `1501-2000` 87% ·
`2000+` 50%.

**Why: trunk moved 2,807 commits in 35 days (80.3/day, mean 3.35/h, median inter-commit gap 6.6 min,
p90 32 min, max 21 h).** Every stranded branch is therefore ~900 commits behind whatever its age, so
distance-today has almost no variance to explain conflict with, while it *does* correlate with the
cohort's file mix (the older cohort is 60% docs-only, and a docs file added at a new path cannot
conflict). A cross-sectional bucket table cannot separate those. It should not be used to argue either
side; §(iv) replaces it.

---

## (iii) Conflict rate vs age since last push — same confounding, same verdict

| age since last push | n | conflict | rate |
|---|---:|---:|---:|
| 0-1 d | 2 | 0 | 0% |
| 1-3 d | 1 | 0 | 0% |
| 3-7 d | 32 | 13 | 40.6% |
| 7-14 d | 128 | 112 | 87.5% |
| 14-21 d | 160 | 122 | 76.2% |
| 21-60 d | 58 | 35 | 60.3% |

Non-monotone, and median age is **14.3 d for conflicting** vs **16.0 d for clean**. The 7-14 d spike is
the sibling-multiplicity cohort (below), which is *younger* than the rest. Age range 0.06-30.1 d.

### Supersession timing (key question iii)

Keyed on the **first `done` transition** in `~/.claude/autonomy/backlog.jsonl` (19,818 records / 3,413
ids / **0 parse failures**), which is tighter than the fold's `lastTs`:

- **median 208.5 h (8.7 days)** from the branch's last push to its item closing.
- within 1 h: **4.6%** · within 24 h: **10.4%** · within 72 h: **21.7%**.
- **14 (4.3%) items were already `done` before the branch pushed** — a genuinely timing-independent
  supersession residual.
- Who closed them, by the done record's `evidence` signature: **81.3% a local session / other
  evidence**, 17.7% *refuted / premise-retracted*, 0.6% explicit superseded/duplicate, and only
  **0.3% (1 branch) names a sibling `claude/fire-` branch**. `closedSession` is set on 44%.
- Reading: supersession is overwhelmingly **the desk closing the item itself while the cloud branch
  sat**, not a sibling cloud branch winning a race. The lane lost to the local fleet, not to itself.
  (Caveat: `evidence` is prose; the classifier is a keyword partition, and "local session / other" is a
  residual bucket, not a positive identification.)

---

## (iv) Counterfactual — real replay, not an estimate

For every branch, `git merge-tree --write-tree <trunk sha that existed at push+Δ> <ref>`, plus the
item's first `done` transition compared to push+Δ. 381 branches × 7 offsets, 0 NA.

| land attempted at | median trunk commits gained | CONFLICT | SUPERSEDED | either | **LANDABLE** |
|---|---:|---:|---:|---:|---:|
| the push itself (t+0) | 0 | 3.1% | 3.7% | 6.6% | **93.4%** |
| **t + 1 hour** | **2** | **6.3%** | **3.9%** | **10.0%** | **90.0%** |
| t + 6 hours | 13 | 9.2% | 5.0% | 13.1% | 86.9% |
| t + 24 hours | 46 | 25.2% | 8.9% | 30.7% | 69.3% |
| t + 3 days | 123 | 44.6% | 18.6% | 53.3% | 46.7% |
| t + 7 days | 311 | 60.9% | 32.3% | 71.9% | 28.1% |
| **today (actual)** | **900** | **74.0%** | **85.8%** | **94.5%** | **5.5%** |

Exposure per window (trunk commits landing after a push): t+1h median 2 / mean 2.6 / p90 7 ·
t+24h median 46 / p90 110 · t+7d median 311 / p90 567.

Onset, per branch, among the 369 clean at their own push: 3.3% first conflict by t+1h, 3.5% more by
t+6h, 16.5% by t+24h, 20.6% by t+3d, 16.8% by t+7d, 12.5% only later, and **26.8% have never
conflicted**.

**At the observed median lag of 207 h the model lands on the t+7d row — and that is what the ledger
shows: 60% of branches were already conflicted the first time the lane touched them.**

### The observed lag, and what the lander actually said

From `~/.claude/autonomy/cloud/return.jsonl` (3,035 records, **0 parse failures**), joined per branch:

- **106 of 381 (28%) never received a land-shaped event at all**; 42 have no return-ledger row at all.
- First land-shaped outcome for the other 275: `land-deferred` **174** · `land-refused` **49** ·
  `returned` 30 · `land-cut` 19 · `land-conflict` 3.
- **Lag push → first land-shaped event: median 207.1 h, p25 79.5 h, p75 231.1 h, p90 263.9 h.**
  Within 1 h: **2.9%** · 6 h: 8.0% · 24 h: 14.9% · 72 h: 24.0% · 7 d: 33.5%.
- **Merge-clean at that first attempt: 110 of 275 (40%)** — and 44 of those 110 (40%) have conflicted
  since. Broken out: `land-deferred` 33% clean-then · `land-refused rc 70` 22% · `returned` 83% ·
  `land-cut` 84% · `land-refused rc 5` 0%.
- `land_rc` over all 1,016 `land-refused` rows: **rc 70 ×763** (re-authoring failed —
  `scripts/cloud-reconcile.sh:822`, "this range is authored by someone GitHub cannot attribute, so
  githooks/pre-push would refuse the push"), **rc 65 ×239** (`:809-811`, could not fetch the branch as
  a local head / retired declaration), **rc 5 ×9** (rebase conflict), rc 143 ×3, rc 6 ×1, rc 69 ×1.
- The one documented rc-70 cause — a reaped inherited `TMPDIR`, fixed `33cf5df17` 2026-08-17, whose own
  comment says "*five of the 39 stuck cloud branches were refused for this and nothing about their
  content was ever wrong*" — **did not close it**: 225 rc-70 and 100 rc-65 refusals are dated *after*
  that commit.
- All 271 `land-deferred` rows carry one `why`: "*the land was never STARTED because its measured price
  does not fit what is left of the bound this caller set*" — the budget arm, not the tree.
- **The lane has landed nothing since 2026-09-07.** 09-08 → 09-10 outcomes are only `abstain`,
  `pass-scope`, `waiting` and **`land-refused-cached` (10, 6, 14/day)** — the deliberate latch at
  `cloud-return.sh:625-637` ("already REFUSED on this exact branch head; not re-asking until it
  moves"). Its documented falsifier is *the VM pushes again*, and a retired VM never does, so for this
  population the latch is permanent by construction. 90 distinct branches ever reached `returned`
  (146 records in 2026-08, 35 in 2026-09).

---

## (v) Landable now

21 branches are merge-clean against `origin/main` today with a non-`done` item; 1 delivers content
already fully on trunk, leaving **20 carrying novel content across 10 distinct units of work** —
**4 docs-only, 16 code**. Cross-checked with a second, independent instrument (`git format-patch
<merge-base>..<ref> | git apply --cached --3way --check` against a throwaway index): 19/21 agree; the
2 disagreements are both *already-applied* files (`docs/research/cloud-vm-reachability-2026-08-23.md`,
`docs/parks/9ce3c6350e2f.md` — byte-identical on trunk), which a rebase drops as empty. merge-tree is
right there and `apply --3way` mints the false conflict.

**Unit 1 — `1f6208064577` "Desk router: inherit the last sweep's k so a starved ps census stops
excluding the whole fleet" [open] — 7 clean branches, one unit of work. Pick ONE.**
`bin/claude-accounts` + `docs/research/desk-router-abstention-2026-09-01.md` in all seven, plus tests.
- `claude/fire-20260904T170832Z-32559-1` (6 d, 5 files: `bin/claude-accounts`, the research doc,
  `tests/account-fact-derivation.bats`, `tests/claude-accounts-core.bats`, `tests/claude-accounts.bats`)
- `claude/fire-20260904T105305Z-58678-1` (6 d, 6 files, adds `scripts/pool-floor.sh`,
  `tests/account-census-inheritance.bats`, `tests/handoff-fire-account-sweep.bats`) — 2 commits
- `claude/fire-20260903T235525Z-18437-1` (6 d, 5 files, + `scripts/desk-strand-replay.py`, `scripts/handoff-fire.sh`)
- `claude/fire-20260903T164436Z-45303-1` (7 d, 5 files, same shape)
- `claude/fire-20260903T083656Z-91310-1` (7 d, 3 files, `tests/claude-accounts-k-inherit.bats`)
- `claude/fire-20260902T052138Z-77815-1` (8 d, 3 files, same)
- `claude/fire-20260901T183237Z-34341-1` (9 d, 5 files, `tests/claude-accounts-stale-k.bats`, `tests/handoff-fire-account-sweep.bats`)

**Units 2-6 — one clean branch each, backlog item still open:**

| branch | age | item | files |
|---|---:|---|---|
| `claude/fire-20260910T123101Z-19701-1` | 0 d | `9f8a985115a9` post-land RED: `tests/cc-read-twitter.bats::parse_id` accepts every URL shape X serves | `tests/cc-read-twitter.bats` (CODE) |
| `claude/fire-20260909T004425Z-75839-1` | 1 d | `8e67a1fa2d40` post-land RED: `tests/deploy-parity.bats::LITERAL INSTALL COVERAGE` | `docs/research/literal-install-coverage-cured-2026-09-09.md` (DOCS) |
| `claude/fire-20260907T062706Z-17724-1` | 3 d | `64c150ba2a8e` advance BACKLOG_ZERO — the two 24/7 drains | `docs/plans/BACKLOG_ZERO_2026-09-04.md`, `docs/plans/CLOUD_BACKLOG_PIPELINE.md`, `docs/research/backlog-zero-close-2026-09-07.md` (DOCS) |
| `claude/fire-20260907T063547Z-45873-1` | 3 d | `badb132df232` design-review perception pipeline (the item's *other* 16 branches all conflict) | `docs/research/cv-design-review-pipeline-verdict-2026-09-07.md` (DOCS) |
| `claude/fire-20260910T185102Z-27906-1` | 0 d | `2a65b9bf722d` [claimed] ProposeGoal is default-off upstream | `docs/research/propose-goal-flag-recheck-2026-09-10.md` (DOCS) |

**Unit 7 — item `9ce3c6350e2f` is `blocked`, so this is a judgment call, not a free land:**
`claude/fire-20260904T193754Z-36841-1` (6 d) — `docs/parks/9ce3c6350e2f.md`,
`docs/research/frontier-track-gate-2026-09-04.md`, `model-config.yaml`, `skills/agent-teams/SKILL.md`,
`skills/frontier-run/SKILL.md`, `skills/research-subagents/SKILL.md`. **Only `model-config.yaml`
differs from trunk** — the other five paths are byte-identical, so the deliverable is a one-file diff.

**Units 8-10 — the `cc-offload` probe lane, item is a brief filename with no ledger row.** Almost
certainly disposable, not deliverable:
- `claude/fire-20260819T135022Z-48051-{1,2,3,4}` — one `tools/b2v-probe/claude-fire-*.txt` each (burst probe)
- `claude/fire-20260811T180903Z-57078-1` and `-2` — `tools/cost-ab-probe/{__init__,wordfreq,test_wordfreq}.py`
- `claude/fire-20260819T132512Z-24086-1` — `tools/b2-quota-probe/{__init__,rangefmt,test_rangefmt}.py`
- `claude/fire-20260823T212516Z-9432-1` — `docs/research/cloud-vm-reachability-2026-08-23.md`,
  **already byte-identical on trunk: nothing to land.**

---

## Adversarial pass — "it is the hot files, not the timing"

The reading under which latency is *not* the cause: cloud VMs are all pointed at the same few
subsystems, so their branches collide with trunk over the same hot files whenever they are landed, and
acting fast would not have helped. **Tested three ways; refuted as the primary mechanism, confirmed as
a rate multiplier.**

**Test 1 — the discriminating prediction. If hot files conflict regardless of timing, they conflict at
t+0.** Conflict-at-own-push, stratified by the maximum 35-day trunk churn of the files the branch
touches (`git log origin/main --since='35 days ago' --name-only`, 1,945 distinct files):

| file heat (max trunk commits / 35 d) | n | t+0 | t+1h | t+6h | t+24h | t+3d | t+7d | today |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 0 — trunk never touched any of its files | 18 | 0% | 0% | 0% | 0% | 0% | 0% | **0%** |
| 1-5 | 34 | 3% | 3% | 6% | 15% | 32% | 47% | 68% |
| 6-20 | 136 | 0% | 0% | 2% | 25% | 52% | 64% | 65% |
| 21-60 | 91 | 1% | 8% | 12% | 29% | 48% | 77% | 89% |
| 61+ (hottest) | 102 | **10%** | 16% | 19% | 30% | 43% | 58% | 87% |

Even the hottest stratum is only 10% at push and 30% at +24 h. The cold stratum is 0% forever — 23
branch-touches on `bench/fp_budget.py` and `bench/profiles.json`, zero conflicts, the clean control.
`rho(file-heat, time-to-conflict) = -0.246`: heat sets the **clock rate**, not the outcome.

**Test 2 — are the top-conflicting files the ones trunk churns daily? No.** Per-file conflict rate over
files touched by ≥8 branches, against trunk's own churn:

| trunk churn | files | branch-touches | conflicts | rate |
|---|---:|---:|---:|---:|
| 0 / 35 d | 2 | 23 | 0 | **0.0%** |
| 1-10 / 35 d | 33 | 413 | 295 | **71.4%** |
| 11-40 | 19 | 364 | 272 | 74.7% |
| 41-120 | 3 | 83 | 66 | 79.5% |
| 121+ | 1 | 31 | 25 | 80.6% |

A file trunk touches **once or twice in 35 days** conflicts at 71%, against 81% for
`docs/plans/BACKLOG_DRAIN_24_7.md` at 12 commits/day. The top offenders are not the hot files:
`bench/route.py` (churn 1) conflicts on **14/14** branches that touch it, `bench/detect_xcheck.py`
(churn 2) on 16/16, `docs/research/cv-design-review-2026-08-26/README.md` (churn 4) on 16/16. The
single hottest file accounts for only 8.9% of the 282 conflicting branches;
`scripts/handoff-fire.sh` (105 commits, the hottest *code* file) for 17.7%. 35% of conflicting branches
conflict on exactly one file.

**Test 3 — what those files actually are: sibling collisions.** The real accelerant is **duplicate
fires on one item**, not trunk churn.

| sibling branches on the same item | n | t+0 | t+1h | t+24h | t+7d | today | median age | median trunk-dist |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 (solo) | 53 | 4% | 13% | 32% | 49% | 57% | 22.0 d | 1437 |
| 2-7 | 54 | 0% | 0% | 13% | 22% | 30% | 19.3 d | 1246 |
| 8+ | 274 | 4% | 6% | 26% | 71% | **86%** | **13.9 d** | **882** |

The 8+ stratum is the **youngest and closest to trunk** and yet the most conflicted. Latency-matched to
7-21 days old: solo 28.6% conflict today, 2-7 36.4%, **8+ 88.1%** — while at t+24h the same 8+ set is
only 26.6%. So the mechanism is: N VMs are fired at one item, they write near-identical text to the
same files, one wins (or the desk closes the item), and the other N-1 now conflict *against their own
duplicate*. That is still latency — it needs elapsed time to bite, and at t+1h it is 6% — but it is a
second, independent driver that a per-file churn model does not see. `bench/route.py` conflicting
14/14 is exactly this: one brief, fourteen VMs, one landing.

**Verdict:** latency is necessary and near-sufficient (93.4% landable at push; 90.0% at t+1h; 0% for
cold files ever). File heat and sibling multiplicity are *rate multipliers on the latency clock*, not
alternatives to it. The timing-independent residual is **3.1% conflict** (12 branches, 10 of which
touch `docs/plans/BACKLOG_DRAIN_24_7.md`) plus **3.7% supersession** (14 items already `done` before
the branch pushed) — 6.6% total.

---

## Alternatives considered and ruled out

- **`git cherry` / patch-id for landedness** — ruled out on the brief's own citation
  (`docs/research/cloud-shallow-horizon-2026-08-29.md` §3): the lane re-authors before pushing, so
  patch-ids differ for content that is verbatim on trunk. Used byte-level `git diff --quiet
  origin/main <ref> -- <path>` per path instead; it found 9 fully-on-trunk branches where the lane's
  own `landed` verdict claimed only 9 declarations, i.e. it agrees.
- **`git apply --3way --check` as the primary conflict oracle** — ruled out: it mints a false conflict
  on already-applied content (2 of 21, diagnosed above). Kept as a cross-check only.
- **Cross-sectional distance/age bucketing as the latency evidence** (the brief's (ii)/(iii)) — computed
  and reported, then set aside: 99.2% of the population sits in two buckets, the curves are
  non-monotone, and conflicting branches are *closer* to trunk than clean ones. Replaced with the
  per-branch longitudinal replay, where each branch is its own control.
- **Estimating the 1-hour trunk distance from gap statistics** (the brief's suggested method) — replaced
  by exact replay against the historical trunk sha. The gap statistics are reported anyway (median 6.6
  min, 3.35 commits/h) and agree: median exact gain at t+1h is 2 commits.
- **Subject-regex detection of boot-commit-only branches** — ruled out after measurement: 12 false
  positives, 0 true positives. Used empty-diff-vs-merge-base instead (answer: 0).
- **`lastTs` from the fold as the item-close time** — kept as a sanity check but superseded by the first
  `done` transition in `backlog.jsonl` (median 208.5 h vs 220.7 h; within-1h 4.6% vs 0.3%).

## Blockers and uncertainties, named

1. **merge-tree is a merge; the lander does a rebase.** They can disagree in both directions. I use
   merge-tree because it is the instrument the lane's own pre-check uses
   (`scripts/cloud-return.sh:655-663`), so my verdicts describe what the lane would decide. A rebase
   re-verdict for the 20 landable branches would need a worktree, which is outside this brief's
   read-only boundary.
2. **"Landable" is the merge step only.** A merge-clean branch can still be gate-RED (`ship-land` exit
   6) or fail re-authoring (rc 70). Empirically gate-red is rare on this population — **1 of 1,016
   refusals was rc 6** — but rc 70 is *not* rare and is *not* fixed, so the 20-branch figure is an
   upper bound on what a lander repaired only for latency would take.
3. **Selection bias in the denominator.** The 381 are survivors; the branches that landed were pruned
   (154 rows across 6 prune manifests; 90 distinct branches ever reached `returned`). "93.4% landable
   at push" is a statement about the **stranded** population, not about all cloud work.
4. **The supersession attributor is a keyword partition over free-text `evidence`.** "local session /
   other evidence" (81.3%) is a residual bucket. The strong claim it supports is the negative one —
   only 1 of 327 done records names a sibling `claude/fire-` branch — not a positive identification of
   the closer.
5. **rc 70/65 semantics read from `scripts/cloud-reconcile.sh:809-823`** and its 914-line
   `FAILED_RC=70` disagreement fallback; a multi-branch sweep whose failures disagree also reports 70,
   so some rc-70 rows may aggregate a different underlying code.
6. **Parse failures: 0 everywhere.** 692 `.decl` files, `return.jsonl` 3,035 records,
   `backlog.jsonl` 19,818 records, `cc-backlog list --all --json` 3,411 folded rows. 678 `.retired`
   files exist against 320 matching live declarations (the rest were gc-archived); 358 of the retired
   markers carry `retired_at=` with **no `verdict=` line at all**, so the lane's own verdict census is
   incomplete for 358 declarations — that gap is why §(i) recomputes the cause instead of reading it.

## Reproduction

```
git fetch origin '+refs/heads/claude/fire-*:refs/cc-research-b1/*'
bash $S/work-B1/census.sh          # per-branch merge-base/ahead/distance/merge-tree/paths
bash $S/work-B1/counterfactual.sh  # replay at push+{0,1h,6h,24h,3d,7d} and today
bash $S/work-B1/atattempt.sh       # merge state at the first land-shaped event
git for-each-ref refs/cc-research-b1 --format='%(refname)' | xargs -n1 git update-ref -d
```

Artifacts: `census.tsv` (431) · `decls.tsv` (693) · `join.tsv` (382) · `cf.tsv` (382) ·
`conflictpaths.tsv` (843) · `novelty.tsv` · `attempts.tsv` · `atattempt2.tsv` (276) ·
`trunk-churn.txt` · `trunk-timeline.txt` · `analysis{1..15}.txt`, all under `$S/work-B1/`.
