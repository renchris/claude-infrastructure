# D2 — What the cloud lane has DEMONSTRABLY landed

Read-only census, 2026-09-10. Repo `/Users/chrisren/Development/.worktrees/cloud-lane-research`
(= claude-infrastructure, `origin/main` fetched at start of run). Intermediates: `work-D2/`.
Ledger parsed record-at-a-time: **19,814 records, 0 parse failures** (`~/.claude/autonomy/backlog.jsonl`, 7,573,240 B).

---

## 0. Headline

**The cloud lane's single largest landed output category is the lane documenting its own mis-dispatch.**
Of 38 docs-only landings in the census, 17 (45%) are venue/eligibility self-reports — a VM explaining
that it was handed an item for a repo it does not have — and 9 more (24%) are "this row was already
cured before it was dispatched" disproofs. 26 of 38 = **68% of the lane's docs output is a report on
the dispatcher, not work on the item.** That output was not wasted: it caused two of `cc-eligible`'s
refusal arms to exist, and one of them (`ineligible-foreign-tree`, `5a3933b8a`, 2026-09-07) was
**landed by a cloud VM itself** (`Cloud-session: session_01BfczAewxAzzYHXZY3owcSM`).

Second headline: **the 88-declaration census undercounts the lane's landed work by 26 sessions, and
the undercount is code-biased** (§1.3). Third: **nothing the lane landed was ever reverted or
re-landed** (§5).

---

## 1. Census construction and its two failures

### 1.1 The 88

| source | n |
|---|---|
| `<id>.returned` with `outcome=returned` | 51 |
| `<id>.returned` with `outcome=returned-close-failed` | 28 |
| `<id>.retired` with `verdict=landed` | 9 |
| **total (disjoint)** | **88** |

All 88 have a `.decl`; all carry `item=` and `branch=`. Repo split: 85 claude-infrastructure,
2 `w2-cloud-rails` worktree, 1 `cloud-fleet` worktree. Accounts: next3 33 · next2 27 · next 16 · next4 11 · 1 blank.
77 distinct items (8 items consumed 19 sessions — §6).

### 1.2 Resolution of landed commits — 82 of 88

| method | n | basis |
|---|---|---|
| `Cloud-session:` trailer on `origin/main` | 74 | `scripts/cloud-reconcile.sh:60-80` re-authoring trailers |
| direct-ancestor (VM commits are literally on trunk, `noreply@anthropic.com` authorship intact) | 5 | branch head `--is-ancestor origin/main`, window bounded by the fire timestamp in the branch name |
| patch-equivalent (`git cherry` all `-`, matched to trunk by subject) | 3 | — |
| **resolved with >=1 landed sha** | **82** | 112 unique shas |
| branch-gone, content on trunk but authored by `Chris Ren`/`renchris` — NOT attributable to cloud | 3 | — |
| branch still carries 1 unlanded commit (`+` in `git cherry`) | 1 | `session_01SzF4CJzwo9h36xdksNMtZg` |
| duplicate dispatch, another session landed the item | 1 | `session_01XonMw4TEExCGDKwYoJqjau` |
| probe declaration, `branch=main` | 1 | `session_01VhevKS8tr3aRmULXtfW2xj` |

The trailer machinery landed **2026-08-10** (`25aa774af`), before the earliest census return (2026-08-14),
so *there is no pre-trailer era in this population* — a missing trailer means the land did not go
through `cloud-reconcile.sh`, not that trailers did not exist yet.

Separately, **88 commits on `origin/main` are authored `Claude <noreply@anthropic.com>` with no
Cloud-session trailer** — VM commits that reached trunk with the identity wall bypassed. 5 of the 88
census rows resolve through that path.

### 1.3 FAILURE 1 — the census misses 26 landed sessions, and they are the code-heavy ones

`git log origin/main --grep='Cloud-session:'` yields **131 commits / 100 distinct session ids**.
Only 74 of those ids are in the 88. The other **26 sessions landed real content and are invisible to
the census**: 20 have no `.returned` and no `.retired` at all (bare declarations), 4 are
`verdict=superseded`, 2 are `verdict=conflict`.

| population | n | docs-only | code-bearing | median lines |
|---|---|---|---|---|
| the 88 census (resolved) | 82 | 38 (46%) | 42 (51%) | 153 |
| **the 26 uncounted** | **26** | **9 (35%)** | **17 (65%)** | **203** |
| corrected total | 108 | 47 (44%) | 59 (55%) | — |

Named examples the census hides: `session_01BzDRWFV2BJY339B1` (4 commits, 1,039 L, code+tests),
`session_01SmqoG8E3DvcnXo73` (1,175 L), `session_01JYgTbz8pxkqPAjRq` (903 L,
`feat(capacity): a marginal-load sampler…`), `session_016pdJNFbqKecoi8ad` (809 L).
`session_01BfczAewxAzzYHXZY` is `verdict=conflict` and still landed 615 L including the
`cc-eligible` subject-foreign arm.

**Implication for the redesign:** any land-rate or composition figure derived from the
returned/retired stores understates code work. The stores record *whether the return arm closed the
loop*, not *whether content reached trunk*. Those are different questions and 26 sessions sit in the gap.

### 1.4 FAILURE 2 — `verdict=landed` cannot distinguish "landed" from "pushed nothing"

`scripts/cloud-retire-terminal.sh:248` sets `verdict=landed` when `git cherry $TRUNK <branch>` emits
zero `+` lines. A branch with **zero own commits** emits zero lines too. 4 of the 9 `retired-landed`
rows had `rev-list --count origin/main..head == 0`; they happened to be genuine (their VM commits are
ancestors of trunk), but an empty branch would be scored identically. The verdict is a correct
*terminal* test and an unsound *success* test.

---

## 2. Composition of what landed

### 2.1 Content type (82 resolved landings)

| content | n | share |
|---|---|---|
| docs-only | 36 | 44% |
| code + tests | 35 | 43% |
| tests-only | 4 | 5% |
| code (no tests) | 3 | 4% |
| docs + data | 2 | 2% |
| other | 2 | 2% |
| **docs-bearing only** | **38** | **46%** |
| **code-bearing** | **42** | **51%** |

Top-level dirs touched (file-touch counts): `docs` 117 · `tests` 90 · `scripts` 28 · `bin` 22 ·
`hooks` 17 · `skills` 3 · `commands` 2 · `migrations` 2 · one each of `model-config.yaml`,
`accounts.json`, `bus`, `launchd`. **231 distinct files ever landed.**

Docs sub-type across the 38 docs landings: `docs/research/` 41 file-touches · `docs/plans/` 15 ·
other `.md` 7. **19 brand-new files.**

### 2.2 Verdict/disproof artifacts vs implemented fixes

Classified from landed commit subjects (`work-D2/rows.json`, field `family`):

| family | docs landings | code landings |
|---|---|---|
| **venue / eligibility self-report** (VM says it got the wrong repo) | **17 (45%)** | 4 |
| **already-cured / phantom-row disproof** (the cure was on trunk before the dispatch) | **9 (24%)** | 1 |
| measurement / other finding | 12 (32%) | 37 |
| total | 38 | 42 |

Representative subjects, verbatim:
- `docs(venue): third burn of 38de29ec5e59 — the disproof landed on trunk and the item fired anyway`
- `docs(readiness): W2's cure was on trunk three days before its row was re-dispatched`
- `docs(enforcing-store): READINESS W3 landed six days before its dispatch, and the returner cannot close a no-op row`
- `docs(cloud): cc-eligible has no cross-repo arm — a project=reso item classifies eligible`
- `docs(capacity): post-land RED 1047cb5061e6 is a phantom — the sha in its title was never bisected`

So: **51% of landings are implemented fixes (code-bearing); 46% are docs, and 68% of those docs are
the lane diagnosing the dispatcher.** Only 12 of 82 landings (15%) are docs that are a *measurement
the item asked for* rather than a report on the lane's own routing.

### 2.3 Diff sizes

| | n | min | p25 | median | p75 | p90 | max | mean |
|---|---|---|---|---|---|---|---|---|
| lines, all landings | 82 | 2 | 78 | **153** | 340 | 522 | 1,083 | 236 |
| lines, docs landings | 38 | 2 | 66 | **88** | 133 | 214 | 526 | 117 |
| lines, code landings | 42 | 14 | 159 | **304** | 481 | 632 | 1,083 | 347 |
| files, all | 82 | 1 | 1 | 2 | 4 | 7 | 27 | 3.5 |
| files, code | 42 | 1 | 3 | 4 | 6 | 9 | 27 | 5.2 |

Code landings are ~3.5x the size of docs landings. The largest landed cloud unit in the census is
1,083 lines; the largest including the uncounted 26 is 1,175 lines (`session_01SmqoG8E3DvcnXo73`).

---

## 3. Latency

**Definition used:** push = committer date of the VM's own last commit (`Original-commit` sha,
all 130 resolvable locally). land = committer date of the re-authored commit on `origin/main`.
This *understates* trunk arrival slightly, because `ship-land` runs after the re-author. The
`.returned` `at=` field is **not** usable for this: `cloud-return.sh:1020` writes `at=$(now)` at the
DESK, so it is the desk's processing time, not the VM's finish.

### 3.1 push → land (the return arm's delivered latency on successes)

| slice | n | min | p25 | median | p75 | p90 | max |
|---|---|---|---|---|---|---|---|
| trailer rows (the return arm proper) | 74 | 0.08 h | 6.38 | **17.93 h** | 61.18 | 114.36 | **323.9 h** |
| all 82 (8 direct/patch rows are 0 by construction) | 82 | 0.00 | 2.66 | 15.02 | 58.75 | 103.49 | 323.9 |
| docs landings | 35 | 0.08 | 7.66 | **24.02 h** | 67.44 | 140.14 | 179.3 |
| code landings | 37 | 0.17 | 6.38 | **16.29 h** | 50.46 | 86.81 | 323.9 |

**Code lands FASTER than docs** (16.3 h vs 24.0 h median) — the opposite of what a
cheap-thing-fits-the-budget story predicts. The return arm's price gate is a *time* budget
(`cloud-return.sh:170,685-708`: `BUDGET_S`, `land_res`, `fits_bound`), not a diff-size gate, and it
does not sort by content type.

### 3.2 land → ledger close

| slice | n | p25 | median | p75 | p90 | max |
|---|---|---|---|---|---|---|
| all | 79 | 2.46 h | **15.80 h** | 112.06 | 249.74 | 307.3 h |
| `outcome=returned` | 46 | — | **4.8 h** | — | — | — |
| `outcome=returned-close-failed` | 25 | — | **17.4 h** | — | — | — |
| `verdict=landed` (retired) | 8 | — | **102.4 h** | — | — | — |

**0 rows were closed before their land** (i.e. the ledger never got ahead of trunk); **3 landed rows
were never closed at all.** The close-failure cost is a 3.6x median penalty (4.8 h → 17.4 h) and the
never-returned path a 21x penalty (102 h).

### 3.3 Why the close fails — 28 `returned-close-failed` rows, exactly two causes

| n | error (normalised) |
|---|---|
| **19** | `cc-backlog done: unknown id <id>` |
| **9** | `shell-init: error retrieving current directory: getcwd: cannot access parent directories` |

The first is structural, not flaky: the backlog ledger lives at `~/.claude/autonomy/backlog.jsonl`,
outside the repo the VM is given, so a VM's `cc-backlog done` runs against an empty store. **68% of
close failures are the VM being asked to write to a store it was never handed.**

---

## 4. Eligibility of what landed, under TODAY's classifier

`bin/cc-eligible why <id> --json`, run 2026-09-10 over the 77 distinct items:

| verdict | items | sessions |
|---|---|---|
| **eligible** | **45 (58%)** | 48 |
| ineligible-cross-repo | 13 | 16 |
| ineligible-parked | 5 | 9 |
| ineligible-deep-history | 4 | 4 |
| ineligible-box | 2 | 2 |
| ineligible-branch-banking | 2 | 2 |
| ineligible-external-deploy | 1 | 2 |
| ineligible-foreign-tree | 1 | 1 |
| ineligible-offbox-lane | 1 | 1 |
| unknown-item (probe/demo labels, not in the ledger) | 3 | 3 |
| **would be REFUSED today** | **29 of 77 = 38%** | 37 of 88 = 42% |

`cc-eligible` predates the whole population (first landed `f55c84bb9`, 2026-08-08), so this is
**classifier drift, not hindsight**. The arms that produce the refusals landed mid-population:

| arm | landed | by |
|---|---|---|
| `ineligible-deep-history` | 2026-08-11 `508c2b9db` | local |
| `ineligible-cross-repo` ("reach arm") | 2026-08-23 `460211b83` | local |
| `ineligible-parked` | 2026-08-30 `524806b9e` | a VM commit, no trailer |
| `ineligible-foreign-tree` | 2026-09-07 `5a3933b8a` | **a cloud VM** (`Cloud-session: session_01BfczAewxAzzYHXZY3owcSM`) |

The venue self-reports landed 2026-08-15 → 2026-09-01, i.e. **they straddle and precede the arms that
now refuse them.** 14 of the 29 refusals (13 cross-repo + 1 foreign-tree) are refusals by arms that
exist *because of* this population's own docs output.

**`ineligible-parked` (5) is not a capability wall.** Three of the five park tokens are the VM asking
the desk to finish a ledger write it could not do:
- `564d151b76e5` → `cc-backlog done 564d151b76e5 --evidence a299123b06d0…`
- `e981656df348` → `cc-backlog done e981656df348 --evidence 3fce569a`
- `78b76e1a8311` → `cc-permission-audit --prune (read-only dry run … that printout IS the result this row owes)`

Net: of 29 refusals, **~19 (14 venue-taught + 5 parked) are artefacts of the lane's own history**;
~10 (deep-history 4, box 2, branch-banking 2, external-deploy 1, offbox-lane 1) are genuine
capability walls the lane nevertheless got work onto trunk against.

---

## 5. Reverts and re-lands — none

Checked both directions over all 112 landed shas:
- `git log origin/main --grep=<short-sha>` → 14 shas cited by a later trunk commit; **0** with
  revert/re-land wording. All 14 are ordinary follow-on citations (e.g. `eb44fcc91` extending
  `1fc55c9c5`'s memory-index cap fix; `3a0721599 docs(readiness): W2's cure was on trunk three days
  before its row was re-dispatched` citing `a61cfa620`).
- `Revert "<landed subject>"` exact match over all 4,671 trunk commits → **0**.

One near-miss worth naming, and it is *not* one of ours: `0d27839c1 revert(ship-land): drop this
branch's comments-only hunk — a cloud VM cannot land a change to this file` (2026-08-29) — a
pre-emptive trim, not a revert of landed content.

**Nothing the cloud lane landed has been taken back.** On a 4,671-commit trunk with 317
revert-mentioning commits, that is a real quality signal, not an absence of scrutiny.

---

## 6. Duplicate dispatch

8 of the 77 items consumed 19 of the 88 sessions:
`38de29ec5e59` ×3, `4ce239d21d67` ×3, `e981656df348` ×3, `564d151b76e5` ×2, `96c57c1c4a6c` ×2,
`01ab05685857` ×2, `0dafb03ed73d` ×2, `485f8f87eb5f` ×2.

Ledger churn on the 77 landed items: **271 reopen events**, 32 items with >=1, max 44.
The top-churn items are exactly the cross-repo ones:

| reopens | item | title (truncated) |
|---|---|---|
| 44 | `ce7651b02a17` | reviewapp/api/auth.py: fresh PyJWKClient per token → pre-auth JWKS fetch amplification |
| 36 | `38de29ec5e59` | doc_classifier: the pinned uv toolchain wheel is fetched with no --require-hashes |
| 29 | `c07fb00eb9b6` | doc_classifier: S9 load-leg latent bundle |
| 23 | `f85fce7c26f5` | the cloud return/land arm died 2026-08-17T09:12:05Z |
| 18 | `70ed289c10fb` | wall_projection() assumes LINEAR weekly burn |

---

## 7. ADVERSARIAL PASS

**H1 — "the docs-only share is an artifact of the return arm's price gate; a code land was cut."**
The brief's hypothesis. **Partly refuted, partly confirmed, and the confirmed part is at a different
stage than proposed.**

**H1a REFUTED — the lander does not cut content.** Comparing every re-authored commit against its
`Original-commit`: **117 of 130 identical in files and lines · 11 shrunk by a median of 7 lines
(rebase context, e.g. `2d58e02ea` 14 L vs 26 L) · 2 grew.** Total lines removed across the entire
population: **65.** No landing was trimmed from code to docs.

**H1b CONFIRMED at the CONFLICT stage — the cut population is overwhelmingly code.**
Branch three-dot diffs (`origin/main...head`) across the whole declaration store (692 declarations):

| group | measurable | docs-only | code+tests | code | median lines | p90 | max | median files |
|---|---|---|---|---|---|---|---|---|
| **landed (88 census, actual landed diff)** | 82 | **44%** | 43% | 4% | **153** | 522 | 1,083 | 2 |
| **conflict-retired** | 133/133 | **12%** | **75%** | 13% | **363** | **1,723** | **3,616** | **5** |
| superseded-retired | 155/155 | 39% | 41% | 19% | 137 | 905 | 1,360 | 2 |
| land-refused, still open | 21/24 | — | — | — | 283 | 739 | 749 | 3 |

Conflict-retired branches are **88% code-bearing** against 47% among landings, carry **2.4x the median
line count** and a far fatter tail. Implied land rate by content:
**docs-only ~33% · code-bearing ~17% — code work dies at roughly twice the rate.**

**H1c — the mechanism is FILE HOTNESS x LATENCY, not size.** The files most often present in
conflict-retired branches, with their trunk churn over the same 60 days:

| branches | file | trunk commits / 60 d |
|---|---|---|
| 30 | `docs/plans/CLOUD_OBSERVABILITY.md` | 35 |
| **27** | **`scripts/handoff-fire.sh`** | **195** |
| 27 | `tests/handoff-fire-cloud.bats` | 9 |
| 18 | `bin/cc-offload` | 13 |
| 18 | `tests/cc-offload.bats` | 10 |

A 17.9 h median push→land window against a file taking ~3.3 trunk commits/day is a near-certain
rebase conflict. Size is a *correlate* (a bigger diff touches more hot files), not the cause; and the
same handful of files recurring across 27-30 distinct branches is the duplicate-dispatch loop of §6
re-colliding with the same wall.

**H2 — "is the census itself biased?"** Yes, against code, by 26 sessions (§1.3). Correcting for it
moves docs 46% → 44% and code 51% → 55%. The docs-heavy reading survives but is weaker than the raw
census implies, and every land-rate figure computed from the returned/retired stores alone is wrong
in the same direction.

**H3 — "did closes get counted that the cloud did not earn?"** No: 0 of 82 landed rows had a `done`
record predating the land, so no row was closed on someone else's work and then credited here. 3
landed rows are still open.

---

## 8. Answer to key question (iv), restated as a verdict

**What cloud has been good at, evidence-cited:**

1. **Single-file, low-contention, self-verifying units.** Median landed unit: 2 files, 153 lines.
   The code half (42 landings, median 304 lines, 4 files) is real implementation with tests —
   `feat(cc-eligible): the subject-foreign arm` (`5a3933b8a`, 368 L),
   `feat(capacity): a marginal-load sampler that refuses the number when it cannot be measured`
   (`session_01JYgTbz8pxkqPAjRq`, 903 L), `fix(land-lock): the landing mutex cannot be acquired on
   Linux` (`session_016ZdNictyBqHw1YDN`, 186 L). **Zero of the 112 landed shas were ever reverted or
   re-landed** (§5) — on a trunk carrying 317 revert-mentioning commits.
2. **Verdict and disproof work that needs reading, not machine state.** 38 docs landings, 19 new
   files, 41 `docs/research/` touches. The recurring, highest-value shape is *refuting a backlog row
   by reading trunk*: `docs(readiness): W2's cure was on trunk three days before its row was
   re-dispatched`, `docs(capacity): post-land RED 1047cb5061e6 is a phantom — the sha in its title
   was never bisected`, `docs(backlog-consolidation): superseded — the frontmatter was the only stale
   thing`. This is exactly the work a 50-commit shallow clone plus a reading model can do and a busy
   local session will not stop to do.
3. **Diagnosing its own dispatcher.** 17 venue self-reports produced `cc-eligible`'s cross-repo and
   foreign-tree arms; the foreign-tree arm was landed *by a VM* (§4). The lane's most reliable
   product to date is a specification of its own admission criteria.
4. **Fast when it works.** p25 push→land 6.4 h; 25% of landings reached trunk inside a working day
   of the VM's last commit, and the `returned` path closes the ledger row a median 4.8 h after the land.

**What cloud has NEVER landed:**

- **A single commit outside claude-infrastructure.** `renchris/reso-management-app` trunk: 7,205
  commits, **0** `Cloud-session:` trailers. `doc_classifier`: **0**. Yet 13 of the 77 items were
  reso/doc_classifier items and consumed at least 16 sessions and 109 reopen events (`ce7651b02a17`
  44, `38de29ec5e59` 36, `c07fb00eb9b6` 29). *The lane's most-dispatched work is work it has a 0%
  landing record on.*
- **Anything in the enforcement or install layer.** Of 231 distinct files ever touched:
  `githooks/` NEVER · `install.sh` NEVER · `CLAUDE.global.md` NEVER · `scripts/deploy-live.sh` NEVER ·
  `hooks/session-continue.sh` NEVER · `hooks/completion-assert.sh` NEVER. (It *has* landed into
  `scripts/ship-land.sh`, `hooks/validate-bash.sh`, `scripts/wrap-ledger.sh`, `bin/cc-backlog`,
  `bin/cc-eligible`, `scripts/cloud-return.sh`, `scripts/cloud-reconcile.sh`.)
- **A large multi-file unit.** Largest landed: 1,175 lines / 27 files. The 3,616-line, 27-file
  attempts are all in the conflict-retired pile.
- **A ledger close it could execute itself.** 19 of 28 close failures are
  `cc-backlog done: unknown id` — the store is not in the repo the VM receives.
- **Work on a hot file.** 27 branches aimed at `scripts/handoff-fire.sh` (195 trunk commits/60 d);
  the file appears in the conflict pile, not in the landed set's top paths.

**One-paragraph statement for the redesign.** Aim the VM at *one cold file in claude-infrastructure,
with the verdict written into a new `docs/research/*.md`, landed inside six hours.* That is the shape
the lane has a 33% land rate on, a zero-revert record on, and a median 4.8 h ledger close on. Do not
aim it at another repo (0 for 13 items, 109 reopens), at `handoff-fire.sh`-class hot files (27
branches, 0 landings), at units above ~500 lines (the p90 of the conflict pile is 1,723 lines and the
p90 of the landed pile is 522), or at anything whose deliverable is a write to
`~/.claude/autonomy/` (19 of 28 close failures). The return arm's own price gate is a time budget and
is not the filter — the filter is rebase conflict against a trunk taking ~3 commits/day on the files
the lane keeps choosing, compounded by a 17.9 h median push→land window.

---

## 9. Blockers, uncertainties, alternatives ruled out

- **Attribution ambiguity, 5 rows.** The `direct-ancestor` rows have no trailer, so a commit is
  attributed to the branch whose fire timestamp most recently precedes it. Two shas (`106897061`,
  and one in the patch-equiv set) are claimed by two concurrently-open branches; 114 sha-attributions
  over 112 unique shas. Affects 5 of 82 rows and no summary conclusion.
- **`push` is VM-last-commit, not VM-push.** Not recoverable: `cloud-return.sh:1020` stamps
  `at=$(now)` at the desk. **`land` is the re-author time, not the `ship-land` push time**, so
  push→land is a lower bound on trunk arrival.
- **44 of 88 branches are pruned from the remote**, so §7's branch-level table uses the 38 survivors
  for the landed group. The landed-diff figures (§2.3) come from trunk commits and are complete;
  only the branch-vs-branch size comparison is subset-based, and it agrees with the trunk-based one.
- **3 items are not in the ledger** (`wave-F ceiling probe A/B`, `cross-repo reach arm: round-trip
  proof`, `cc-offload fire-w3-demo.txt`) — probe/demo declarations, reported as `unknown-item`.
- **Ruled out: reading `outcome=`/`verdict=` as a landing oracle.** §1.3-1.4 — the stores both
  over- and under-report. Every landing figure here is anchored on a trunk commit.
- **Ruled out: `git cherry`'s `+` as the absence test** for the 6 unresolved rows; used per-path
  `git log origin/main -- <path>` plus authorship instead, which is what showed those 3 branch-gone
  rows' content was authored locally, not by the VM.
- **CLOSED (was a named gap): the reso/doc_classifier VMs never even pushed a branch.**
  `git ls-remote --heads origin 'refs/heads/claude/*'` returns **0 refs** in both
  `renchris/reso-management-app` and `renchris/doc_classifier`. So the 0-landings figure for those
  repos is not "landed nothing of what it pushed" — **nothing was ever pushed there at all.** The
  13 cross-repo items were worked in a claude-infrastructure clone and produced only the venue
  self-reports of §2.2.

---

## 10. Per-landing table (88 rows, sorted by land time)

`push→land` and `land→close` are hours. `resolution` names how the landed sha was found
(`trailer` = `Cloud-session:` provenance; `direct-ancestor` = VM commit on trunk with VM identity;
`patch-equiv-subject` = `git cherry` `-` matched to trunk by subject).

| # | session (short) | item | landed sha(s) on origin/main | content | files | ±lines | cc-eligible today | push→land h | land→close h | resolution |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | `013H8jXq4Njbg6` | `9fb09dded100` | cc265753f | docs-only | 1 (docs:1) | +25/-0 | eligible | 0.08 | 0.63 | trailer |
| 2 | `017ga3J7cGNKkq` | `e9a745a7ffb9` | a5f88ced4 48f21a8a8 | docs-only | 1 (docs:2) | +24/-1 | ineligible-box | 0.27 | 0.06 | trailer |
| 3 | `01HEudSuWY9hLk` | `cc-offload fire-w3-d` | 67dca77aa 9270197a8 | other | 2 (docs:1,tests:2) | +52/-0 | unknown-item | 0.1 | — | trailer |
| 4 | `01CCZcjYGJnLMu` | `0b4d4e8a1889` | 47cf3a8c3 | code+tests | 5 (code:2,docs:2,tests:1) | +210/-1 | eligible | 2.66 | 112.06 | trailer |
| 5 | `01CHL2GUxKQq2M` | `df2b6a40a5dc` | 845d18c17 | code+tests | 27 (code:2,tests:25) | +478/-2 | ineligible-branch-banking | 4.21 | 0.34 | trailer |
| 6 | `01Fe18fUexDNHQ` | `3709b1649792` | bc8327717 | code+tests | 3 (code:2,tests:1) | +144/-15 | eligible | 13.72 | 2.55 | trailer |
| 7 | `014LKP1UFU3iQj` | `6b42d1f49770` | 5f2f5431f | tests-only | 1 (tests:1) | +159/-75 | eligible | 16.29 | 0.47 | trailer |
| 8 | `017nvBWW17pCC3` | `82f59a765ec8` | ffa9c2d81 b24eb83b6 | code+tests | 4 (code:2,docs:1,tests:1) | +63/-15 | eligible | 7.79 | 0.47 | trailer |
| 9 | `019y27yi3FWCWm` | `45a847846571` | ee5d9de9a | code+tests | 4 (code:2,docs:1,tests:1) | +306/-23 | eligible | 2.99 | 52.57 | trailer |
| 10 | `01HdkJvMyTWT2t` | `73583e2519d6` | 7fa5eba14 e178b45c0 | code+tests | 4 (code:2,docs:1,tests:1) | +224/-8 | eligible | 6.07 | 10.6 | trailer |
| 11 | `01HMYbaZ6nVSiG` | `0095e83a191f` | 6394a3531 3b548c2f5 66fe6ad6b | other | 3 (docs:3,tests:1) | +198/-28 | eligible | 32.23 | 60.22 | trailer |
| 12 | `01Kc1QCCBaBipo` | `a81fd02ce4df` | 60796afc6 | docs-only | 1 (docs:1) | +75/-3 | eligible | 0.14 | 47.88 | trailer |
| 13 | `01MzQVcJeWXojo` | `1c45598a91be` | a61cfa620 aa1a831a3 4d3e4418e f1846afe5 10e321519 | code+tests | 8 (code:4,docs:4,tests:4) | +1014/-69 | eligible | 0.17 | 60.04 | trailer |
| 14 | `01Pn7VFV39WcZG` | `1eaa09cfa5a2` | 968ea4a1e | code+tests | 11 (code:3,data:1,docs:2,tests:5) | +420/-30 | ineligible-box | 21.28 | 58.27 | trailer |
| 15 | `01Q2e9U1BFqbgD` | `8ffb7c3b3b8c` | 7ab159ab8 | docs-only | 2 (docs:2) | +85/-4 | eligible | 43.37 | 45.99 | trailer |
| 16 | `01QmBkP5BH741J` | `15b99887cd5e` | 61826e193 | code+tests | 3 (code:2,tests:1) | +156/-5 | eligible | 50.46 | 58.15 | trailer |
| 17 | `011Pn75zVxsFzE` | `f401935c0bd4` | 6aa31d06a | code+tests | 4 (code:1,tests:3) | +122/-6 | eligible | 15.03 | 0.24 | trailer |
| 18 | `012Y2SatMMSESf` | `1047cb5061e6` | cb78acbc5 | docs-only | 1 (docs:1) | +40/-0 | ineligible-deep-history | 8.32 | 0.25 | trailer |
| 19 | `01AWm9gc8axRHD` | `e8a5750bc5f4` | 2d58e02ea | tests-only | 1 (tests:1) | +14/-0 | ineligible-deep-history | 8.47 | 27.74 | trailer |
| 20 | `01DHhTAv1vvLgF` | `1cc794cbc6c4` | da8e0a6be | docs-only | 1 (docs:1) | +85/-0 | ineligible-cross-repo | 10.07 | 39.12 | trailer |
| 21 | `012vkv9uAzqUdC` | `70ec97ddb82b` | 2d7b125d6 | code+tests | 3 (code:1,docs:1,tests:1) | +99/-115 | eligible | 4.93 | 0.87 | trailer |
| 22 | `013Sz55N56b61V` | `b585e86ea4e4` | cb46c724b | docs-only | 1 (docs:1) | +12/-3 | eligible | 1.85 | 0.43 | trailer |
| 23 | `01DfvBYfvHMQUG` | `b02e87582e96` | ba9141f11 | docs-only | 2 (docs:2) | +512/-14 | eligible | 2.4 | 8.77 | trailer |
| 24 | `01FN7HKx3WLjLK` | `aee48ef0ffcf` | 0d1a1de11 | code+tests | 5 (code:2,docs:1,tests:2) | +747/-39 | eligible | 27.73 | 22.21 | trailer |
| 25 | `01GRA7q3H5MruN` | `a3a070520f3d` | a7a158c24 | tests-only | 1 (tests:1) | +23/-0 | eligible | 22.12 | 21.72 | trailer |
| 26 | `019Xuzcud3SKmm` | `7a56de4c54ab` | a65ad411b 3d5ac1977 8003538df 1fc55c9c5 395363399 | code+tests | 9 (code:9,docs:1,tests:8) | +830/-154 | ineligible-cross-repo | 0.69 | 21.59 | trailer |
| 27 | `01HuryUuhJx6eP` | `8f59467c92b0` | 3e2b21aba | docs-only | 1 (docs:1) | +39/-0 | ineligible-foreign-tree | 7.66 | — | trailer |
| 28 | `01Jvf817fJ9ZqL` | `e08ad9ab1ff6` | f51f66416 | code+tests | 6 (code:2,docs:1,tests:3) | +613/-19 | eligible | 17.1 | 17.39 | trailer |
| 29 | `01NdSMV39H3Sf9` | `e020ebb2b8c7` | d7dc69bc6 | docs-only | 1 (docs:1) | +181/-0 | eligible | 15.02 | 16.34 | trailer |
| 30 | `01NuZUyNBEAwyu` | `60e940e30948` | 4f215d366 | code+tests | 4 (code:2,docs:1,tests:1) | +388/-4 | eligible | 21.58 | 15.8 | trailer |
| 31 | `011idcwNXpC1o5` | `84e48ded804a` | c571cf4de ff96d9289 | code+tests | 3 (code:1,docs:1,tests:1) | +185/-4 | eligible | 86.81 | 14.82 | trailer |
| 32 | `01SfE2f9EDtdgu` | `86fd4c20dd44` | bade951f0 | docs-only | 1 (docs:1) | +82/-1 | eligible | 50.53 | 2.42 | trailer |
| 33 | `01Sw14gFKZk2bL` | `1d25b0e07668` | cf2f8b406 | docs-only | 1 (docs:1) | +127/-0 | ineligible-branch-banking | 2.16 | 13.23 | trailer |
| 34 | `01ALrGPyAH1FkF` | `3118d712f668` | d16230020 dc4158ab6 7e7aa59e2 | code+tests | 20 (code:3,docs:14,tests:3) | +919/-12 | eligible | 0.39 | 2.29 | trailer |
| 35 | `01T1qX15FwryPU` | `9333991e4544` | d9df404db | docs-only | 2 (docs:2) | +110/-0 | eligible | 11.05 | 12.65 | trailer |
| 36 | `01UEzkn3D3dDrb` | `b0ce82d745be` | 7d1e54671 133e8e0b0 | code+tests | 6 (code:2,docs:2,tests:2) | +531/-2 | eligible | 18.76 | 12.39 | trailer |
| 37 | `01UvSuFZsMEgKn` | `d9d0012229b7` | 3c536c95c | code | 15 (code:1,docs:14) | +442/-2 | eligible | 67.85 | 12.27 | trailer |
| 38 | `01GsPHLDAnjjZU` | `cb8b9620ddef` | e33eb8ca5 | code+tests | 2 (code:1,tests:1) | +226/-2 | eligible | 103.49 | 2.79 | trailer |
| 39 | `01ByarSYiRHW33` | `ff6a95a1779b` | 6ac041e3d | code | 3 (code:1,docs:2) | +96/-2 | eligible | 64.73 | 2.17 | trailer |
| 40 | `016cCpabdJ362o` | `d29b73103189` | 6cedafbf5 | code+tests | 8 (code:4,docs:1,tests:3) | +489/-12 | eligible | 71.06 | 2.02 | trailer |
| 41 | `01RK9cH1DWgmBD` | `c07fb00eb9b6` | 2272f4d9e | docs-only | 1 (docs:1) | +147/-0 | ineligible-cross-repo | 10.74 | 0.62 | trailer |
| 42 | `01UxPxZWwH24jg` | `0e8a10c501af` | 3a0721599 | docs-only | 1 (docs:1) | +40/-0 | eligible | 58.75 | 0.44 | trailer |
| 43 | `01HPjoZESE7rpq` | `df003b95630b` | eee49e9ef | docs-only | 1 (docs:1) | +54/-0 | eligible | 2.57 | 1.22 | trailer |
| 44 | `018in35KSYj7iL` | `c33f3b1cb278` | ead1912a5 822fede38 | docs-only | 4 (docs:7) | +235/-79 | ineligible-cross-repo | 1.35 | 0.34 | trailer |
| 45 | `01XHLy85iNdrde` | `ce7651b02a17` | d36a226c8 | docs-only | 1 (docs:1) | +70/-0 | ineligible-cross-repo | 114.36 | 307.28 | trailer |
| 46 | `0131E71dtfWLdU` | `b0be87487228` | 10b6ffda2 | docs-only | 1 (docs:1) | +36/-0 | ineligible-cross-repo | 64.95 | 4.71 | trailer |
| 47 | `0122yzViP3rEY6` | `0dafb03ed73d` | d3ae5d47c | docs-only | 1 (docs:1) | +173/-0 | ineligible-cross-repo | 97.21 | 5.6 | trailer |
| 48 | `016obvRMpGszDE` | `4ce239d21d67` | fc7f4ac17 9a983e903 | code+tests | 3 (code:1,docs:1,tests:1) | +381/-2 | eligible | 0.0 | 15.26 | patch-equiv-subject |
| 49 | `016WJ8vGwckuC9` | `a1136cd016cb` | 486b27078 | docs+data | 1 (data:1) | +2/-0 | ineligible-cross-repo | 79.26 | 213.16 | trailer |
| 50 | `01LmYFcgKgawXp` | `4ce239d21d67` | fc7f4ac17 9a983e903 6e900ea67 14287ae8e | code+tests | 3 (code:1,docs:3,tests:1) | +486/-3 | eligible | 0.0 | 15.15 | direct-ancestor |
| 51 | `01TtPTPuwSzNq2` | `40c7207a96b1` | e3889b155 | docs-only | 1 (docs:1) | +195/-0 | ineligible-cross-repo | 67.44 | 250.91 | trailer |
| 52 | `0138tx3fZgRz8v` | `96c57c1c4a6c` | 501a121c2 | docs-only | 1 (docs:1) | +75/-0 | ineligible-external-deploy | 58.22 | 4.99 | trailer |
| 53 | `01FS2g63B54LZr` | `616d58ac42df` | a7bb22b27 | docs-only | 1 (docs:1) | +110/-0 | ineligible-cross-repo | 39.49 | 249.74 | trailer |
| 54 | `011n9HBG1LR3Lf` | `354c73ebd400` | 1225b1595 | docs-only | 1 (docs:1) | +119/-0 | eligible | 21.42 | 4.48 | trailer |
| 55 | `01WywrYd6WjzKm` | `4218bdea6601` | a7e11e1fa | tests-only | 1 (tests:1) | +52/-6 | ineligible-deep-history | 11.89 | 248.92 | trailer |
| 56 | `013KFzXCcXMZyh` | `33d9b33bbd28` | f514e15f7 | docs-only | 1 (docs:1) | +71/-3 | eligible | 9.06 | 4.24 | trailer |
| 57 | `01RMeKc74PjyA5` | `e981656df348` | e89918f2b | code | 1 (code:1) | +29/-2 | ineligible-parked | 8.07 | 248.63 | trailer |
| 58 | `01XrcKJ3WuEh6c` | `b82a4060b00f` | c4981f1f2 | code+tests | 2 (code:1,tests:1) | +339/-1 | ineligible-offbox-lane | 134.09 | 257.3 | trailer |
| 59 | `01NFiM3W3MZ3ZA` | `96c57c1c4a6c` | 4e72a745a | code+tests | 2 (code:1,tests:1) | +81/-0 | ineligible-external-deploy | 81.24 | 3.77 | trailer |
| 60 | `01E7VeX3ufisRT` | `485f8f87eb5f` | a7791f718 | docs-only | 2 (docs:2) | +76/-1 | ineligible-parked | 24.02 | 248.51 | trailer |
| 61 | `01TrJvH1xWZTUW` | `01ab05685857` | 2f165d9b1 | code+tests | 2 (code:1,tests:1) | +97/-17 | eligible | 9.85 | 247.87 | trailer |
| 62 | `01SM6qK5tjtBSG` | `4577c399bf95` | b66243cb1 | code+tests | 2 (code:1,tests:1) | +252/-1 | eligible | 2.68 | 2.46 | trailer |
| 63 | `01Cg9x2teA8bni` | `f85fce7c26f5` | a42f107aa | code+tests | 3 (code:2,tests:1) | +272/-7 | ineligible-parked | 16.61 | 247.44 | trailer |
| 64 | `01T1U9CrHbumQq` | `01ab05685857` | 1f5bd304d | code+tests | 3 (code:1,docs:1,tests:1) | +203/-4 | eligible | 13.15 | 247.29 | trailer |
| 65 | `01EAaEsczo6WBF` | `4ce239d21d67` | 0d426c1c0 cc87238f8 b0d209ba5 | code+tests | 3 (code:1,docs:2,tests:1) | +370/-3 | eligible | 6.38 | 5.29 | trailer |
| 66 | `01TxKeVZD8P4XH` | `564d151b76e5` | a299123b0 | docs-only | 5 (docs:5) | +122/-6 | ineligible-parked | 22.43 | 246.74 | trailer |
| 67 | `0146pnB6CFfVo4` | `a771a1611d28` | 0e1569952 | code+tests | 9 (code:3,docs:1,tests:5) | +396/-85 | eligible | 21.13 | 4.94 | trailer |
| 68 | `014gYqgj2273cA` | `0dafb03ed73d` | f143649df | docs-only | 1 (docs:1) | +66/-0 | ineligible-cross-repo | 179.28 | 249.41 | trailer |
| 69 | `01PoSKFsv2vsiT` | `21e2c1088736` | 8bfa48f85 | docs-only | 1 (docs:1) | +133/-0 | ineligible-cross-repo | 153.94 | 249.22 | trailer |
| 70 | `01FpeBf27xxHvW` | `38de29ec5e59` | c13929dae | docs-only | 1 (docs:1) | +107/-0 | ineligible-cross-repo | 142.53 | 306.62 | trailer |
| 71 | `01PzxqRPaQDmeE` | `38de29ec5e59` | aa61facf8 | docs-only | 1 (docs:1) | +87/-0 | ineligible-cross-repo | 140.14 | 306.5 | trailer |
| 72 | `01GyeNQEsrvKiR` | `20caf9661ea4` | c8113a6e8 | docs-only | 1 (docs:1) | +214/-0 | ineligible-cross-repo | 133.11 | 299.48 | trailer |
| 73 | `01YVFuBjBnbCZj` | `78b76e1a8311` | bd9ce93f3 02926ff14 | code+tests | 5 (code:1,docs:2,tests:3) | +434/-24 | ineligible-parked | 0.0 | 287.09 | patch-equiv-subject |
| 74 | `01XYN4jADaBBUB` | `e981656df348` | 954e5d387 | docs-only | 2 (docs:2) | +80/-3 | ineligible-parked | 0.0 | 111.98 | direct-ancestor |
| 75 | `01YKFuH3tm8gUX` | `485f8f87eb5f` | 106897061 | docs-only | 2 (docs:2) | +101/-0 | ineligible-parked | 0.0 | 92.78 | direct-ancestor |
| 76 | `01X1E8xV1v65Qa` | `e981656df348` | 853a1feea e77450ffd 2acdee96b | code+tests | 4 (code:2,docs:2,tests:2) | +336/-9 | ineligible-parked | 0.0 | 92.35 | direct-ancestor |
| 77 | `01XrowD6T3dBPe` | `564d151b76e5` | 8f268131f 06989a107 a9b1ecc92 16cd3a362 | docs-only | 5 (docs:6) | +292/-15 | ineligible-parked | 0.0 | 88.9 | direct-ancestor |
| 78 | `01Y6CYm6KezSik` | `0c8b39b67665` | f4ff996bd 0efcc073d | code+tests | 7 (code:3,docs:2,tests:2) | +515/-7 | eligible | 0.0 | 165.79 | patch-equiv-subject |
| 79 | `01AcrJ4ScWxmkB` | `9ce3c6350e2f` | ccf59f67c | docs+data | 6 (data:1,docs:5) | +198/-16 | eligible | 58.65 | — | trailer |
| 80 | `0176LAhzdY8H4z` | `70ed289c10fb` | 964571b7a | docs-only | 1 (docs:1) | +98/-0 | eligible | 59.52 | 0.16 | trailer |
| 81 | `016HDqJnCSz7RQ` | `ca97c678b18b` | afae201db | code+tests | 6 (code:3,tests:3) | +73/-16 | eligible | 61.18 | 0.23 | trailer |
| 82 | `015YbRpUxnAL3L` | `d1d51881cca1` | e5c9c46fa | code+tests | 4 (code:1,docs:1,tests:2) | +569/-8 | ineligible-deep-history | 323.91 | 44.43 | trailer |
| 83 | `01SzF4CJzwo9h3` | `38de29ec5e59` | — | (none landed) | 0 (—) | +0/-0 | ineligible-cross-repo | — | — | branch-unlanded |
| 84 | `013jDz3L8k6neU` | `d88c1640550f` | — | (none landed) | 0 (—) | +0/-0 | eligible | — | — | branch-gone |
| 85 | `01Fhiv1czXEaQX` | `4562ff2ad68e` | — | (none landed) | 0 (—) | +0/-0 | eligible | — | — | branch-gone |
| 86 | `01XonMw4TEExCG` | `cross-repo reach arm` | — | (none landed) | 0 (—) | +0/-0 | unknown-item | — | — | unmapped |
| 87 | `01VMwdAbwLif2E` | `abab60591342` | — | (none landed) | 0 (—) | +0/-0 | eligible | — | — | branch-gone |
| 88 | `01VhevKS8tr3aR` | `wave-F ceiling probe` | — | (none landed) | 0 (—) | +0/-0 | unknown-item | — | — | probe-branch-main |

---

Intermediates: `/private/tmp/claude-501/-Users-chrisren-Development--worktrees-cloud-lane-research/dc4eb0fa-3191-4b17-acc3-c3a1e6050e33/scratchpad/work-D2/{census,commits,resolved,rows,eligible,sizes}.json`, `trunk-log.tsv`, `ls-remote.txt`, `trailer-commits.raw`.
