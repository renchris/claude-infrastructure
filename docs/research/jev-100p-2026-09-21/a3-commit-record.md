# A3 — Is there a Jev deliverable over the commit/land record? — 2026-09-21

**VERDICT: NO on all four candidates, and the refutation is candidate (a)'s own stated one —
the base rate is 0.3%.** Over the 306 code-touching commits in the last 500 on trunk, **one**
has a body under 20 words. Over the 299 in a window a month older, eleven (3.7%). The population
the close protocol delegates to — a `fix`/`feat`/`test` commit whose narrative a close dropped —
carries a **370-word mean body, 0% bodyless**. There is nothing for a judge to find.

The residual defect that *is* real is **not about bodies at all**: 277 of the 1,692 commit shas
cited across `docs/**.md` (16.4%) are **not ancestors of `origin/main`**. Those pointers resolve
in this checkout and in no clone. That is the actual "deletion wearing a pointer's clothes,"
it is `git merge-base --is-ancestor` in a loop, and it needs zero model. **§8 specifies it.**

---

## 1. Corpus — measured, not quoted

`git log --format='%H%x09%s' origin/main | wc -l` → **5,339** commits (5,311 since 2026-06-01).
Body = `git log -1 --format='%b'`, blank lines stripped, `wc -w`.

### 1.1 Last 500 commits on trunk

| metric | value |
|---|---|
| n | 500 |
| mean body words | **301.9** |
| median (p50) | 277 |
| p10 / p25 / p75 / p90 | 62 / 169 / 419 / 537 |
| max | 1,632 |
| bodyless (0 words) | **36 (7.2%)** |
| short (<20 words) | 37 (7.4%) |
| <50 words | 42 (8.4%) |
| ≥200 words | **344 (68.8%)** |

CLAUDE.md § S5 says *"45 of 50 recent commits carry a body, mean 252 words… 1 in 10 commits is
bodyless."* Both halves replicate at n=500 (7.2% vs "1 in 10", 302 vs 252 words). **What the
resident figure does not say is where the 7.2% lands** — and that is the whole answer.

### 1.2 The bodyless population is 100% structural

By conventional-commit type over the same 500:

| type | n | mean body words | short (<20w) |
|---|---|---|---|
| `fix` | 167 | 365.3 | **0 (0%)** |
| `feat` | 76 | 456.6 | **0 (0%)** |
| `test` | 50 | 269.6 | **0 (0%)** |
| `chore` | 2 | 158.5 | **0 (0%)** |
| `perf` / `patch` / `plan` | 3 | 116–196 | **0 (0%)** |
| `docs` | 189 | 202.7 | **33 (17%)** |
| `memory` | 8 | 219.1 | 2 (25%) |
| `research` | 4 | 214.2 | 1 (25%) |
| `Revert "fix…"` | 1 | 4.0 | 1 (100%) |

Of the 37 short commits, **36 touch only `.md` files** (verified per-commit with
`git show --name-only | grep -vc '\.md$'`). Their breakdown: `docs(plan)` 18, `docs(research)` 6,
`docs(rules)` 3, `docs(lessons)` 3, `docs(lr100p)` 2, `memory(rules)` 2, others 3.

The single non-`.md` short commit in 500 is a `Revert "fix(effort-parity)…"` — git's own
generated revert message.

**A `docs(plan)` commit appending 4 lines to `LIMIT_RECOVER_100P.md` has no missing narrative
tier: its diff IS the narrative.** Asking a model whether such a body "states its why" is asking
about a commit whose entire content is prose the reader is about to read anyway.

### 1.3 The older corpus is not worse enough to change this

Commits 2001–2500 back from the tip (2026-08-15 → 2026-08-21):

| window | code commits | mean body words | short (<20w) |
|---|---|---|---|
| newest 500 | 306 | 370.0 | **1 (0.3%)** |
| 2001–2500 | 299 | 380.0 | **11 (3.7%)** |

So the defect's prevalence across a 5-week span is **0.3%–3.7%**, and it is trending down.
This is the brief's own refutation criterion (a): *"base rate near 0 or 1 ⇒ the arm is inert by
construction — a disqualification, not a tuning problem."*

---

## 2. My 20 hand-labels

The 20 most recent commits on `origin/main` (2026-09-20/21), labelled by reading subject, `--stat`
and body. `WHY` = does the body name a cause and what changes for a reader. `SUBJ` = does the
subject accurately describe the diff. `OVER` = does the body assert something the diff refutes.
`SCOPE` = is the diff free of changes the subject/body do not describe (repo rule G4).

| # | sha | type | words | WHY | SUBJ | OVER | SCOPE |
|---|---|---|---|---|---|---|---|
| 1 | `5acaeea16` | fix(cc-jev rank) | 218 | ✓ | ✓ | – | ✓ |
| 2 | `b912cd0c3` | test(cc-limited) | 233 | ✓ | ✓ | – | ✓ |
| 3 | `8c336e581` | docs(plan) | **0** | n/a | ✓ | – | ✓ |
| 4 | `62d222011` | docs(plan) | **0** | n/a | ✓ | – | ✓ |
| 5 | `a0ceab890` | feat(cc-jev) | 372 | ✓ | ✓ | – | ✓ |
| 6 | `d6d560833` | docs(lessons) | 297 | ✓ | ✓ | – | ✓ |
| 7 | `de470fd79` | feat(vendor) | 306 | ✓ | ✓ | – | ✓ |
| 8 | `82af0f03b` | fix(cc-jev) | 316 | ✓ | ✓ | – | ✓ |
| 9 | `ea5012b30` | docs(plan) | **0** | n/a | ✓ | – | ✓ |
| 10 | `9a130dc0f` | test(headless-address) | 152 | ✓ | ✓ | – | ✓ |
| 11 | `2653cbc9f` | fix(lr-ingest-verify) | 221 | ✓ | ✓ | – | ✓ |
| 12 | `9c5ca57bd` | test(w3i) | 62 | ✓ | ✓ | – | ✓ |
| 13 | `53b7c3508` | test(w3i) | 128 | ✓ | ✓ | – | ✓ |
| 14 | `7a95cea7a` | test(w3i) | 85 | ✓ | ✓ | – | ✓ |
| 15 | `0073e5a58` | test(w3i) | 117 | ✓ | ✓ | – | ✓ |
| 16 | `f96e5362e` | docs(plan) | **0** | n/a | ✓ | – | ✓ |
| 17 | `84e749550` | docs(w3i) | 341 | ✓ | ✓ | – | ✓ |
| 18 | `1e472302f` | fix(session-continue) | 405 | ✓ | ✓ | – | ✓ |
| 19 | `2046b1020` | fix(lr-ingest-verify) | 507 | ✓ | ✓ | – | ✓ |
| 20 | `a30670d88` | feat(lr-handoff) | 289 | ✓ | ✓ | – | ✓ |

**Base rates: WHY 16/16 = 100% (of bodied commits). SUBJ 20/20 = 100%. OVER 0/20 = 0%.
SCOPE 20/20 = 100%.** Every arm is pinned to a boundary. All five bodyless commits are
`docs(plan)`/`docs(…)` appends to a plan file.

The bodies are not merely present, they are *dense*: #19 carries a per-clause FAIL histogram
over 69 real bundles, names twelve mutants by identifier and reports 12/12 killed; #18 pastes
its RED verbatim, names four mutants and explains why the second test case is non-redundant.
This is the corpus a judge would be asked to improve.

**One under-delivery I found, and it is not what the brief predicted.** #3's *subject* —
`docs(plan): lr100p §9 — correct the residual-7 claim; it rotted in 40 minutes` — carries the
whole narrative, and the body is empty. The body is not under-delivering; the **subject is
over-delivering**, i.e. the repo has already routed the narrative to the tier that is always
present. Six of my 20 subjects run 70+ characters and function as one-line bodies.

---

## 3. Candidate-by-candidate

### (a) Does the body state its WHY, or only restate the diff? — **DEAD, base rate 0%**
16/16 bodied commits state a cause. 0/306 code commits in the last 500 are bodiless. Even at the
older window's 3.7% the mechanical detector — `git log -1 --format='%b' | wc -w` — has precision
1.0 and recall 1.0 on that exact defect. Jev at AUROC 0.982 (its best measured decomposed figure,
`jev-at-cost-api-2026-09-18.md` §2) cannot beat 1.0, and at a 0.3–3.7% prevalence its precision
at usable recall is poor by base-rate arithmetic. **Refuted by the brief's own criterion (d):
`git show` already answers it structurally.**

### (b) Does the body over-claim against its own diff? — **DISQUALIFIED BY THE ENVELOPE**
Two independent kills.

**(b-i) The verifiable claims are mechanical; the falsifiable ones are not in the diff.**
Censusing the claim tokens in my 20 bodies: `rc 0` ×5, `shellcheck clean` ×4, `42/42` ×2,
`KILLED 12/12`, `KILLED 4/4`, `31/31 green`, `29/29 green`, `26/26 green`, `13/13`, `69 of 69`,
`68 of 68`, `67 of 69`, `10 of 69`. **Every one of these is the outcome of a run that happened
outside git.** No amount of diff reading can refute "42/42 off-box, 27s" or "KILLED 12/12,
survivors none". The subset that *is* checkable — "Suite 30 → 42", "Tests 30-31 added" — is
checkable by `grep -c '^@test'`. I verified one: `2046b1020` claims *Suite 30 -> 42*;
`git show 2046b1020^:tests/lr-ingest-verify.bats | grep -c '^@test'` → **30**, and at the commit
→ **42**. True, and proved without a model.

**(b-ii) 🚨 This is the domain-reputation failure mode, transposed.** The envelope disqualifies
*"any task where hostile/unusual content arrives in a reputable wrapper."* A 400-word commit body
in this repo — conventional-commit subject, RED-verbatim block, named mutants, per-clause
histogram, a `Gates:` footer — **is a maximum-reputation wrapper**. The phishing bench measured
Jev at **1.5%** detection for hostile content inside a Google Docs wrapper and **17%** inside
GitHub Pages, while flagging **45% of legitimate** third-party-tool mail as hostile. Arm (b) asks
Jev to find an unsupported assertion inside exactly that kind of wrapper, over a corpus that is
**99.7% legitimate**. The predicted behaviour is near-zero recall plus a false-positive rate that
would make the report unreadable. **DISQUALIFIED — say so and move on.**

A mechanical version of (b) was built and measured anyway, to price the honest control:
over the last 200 commits, **105 bodies name ≥1 repo path**, 236 paths named in total, and
**157 (66.5%) of those paths are not in the commit's own diff** — because they are *citations*
(`handoff-fire.sh:7753`, `bin/cc-pane-headless:124`), which is correct behaviour, not over-claim.
A naive path-presence detector therefore runs at a **66% false-positive rate**. Separating
"cited as evidence" from "claimed as changed" is a genuine semantic judgment — and it is a
judgment about a *citation convention*, whose defect rate in my hand-labels is 0.

### (c) Is the SUBJECT an accurate description of the diff? — **DEAD, base rate ~0%**
Hand-labels: 20/20 accurate. Mechanically, over 300 commits the conventional-commit **scope token
names a path in the commit's own diff in 271 cases (90.3%)**. The 29 misses are wave labels
(`w3p` ×7, `w3i` ×4, `w2` ×3, `lr100p` ×3) — a deliberate convention, not a defect. Zero misses
were a subject naming the wrong subsystem.

The resident memory `read-the-diff-not-the-commit-subject` is a rule about **how a reader should
read**, not a claim that this repo's subjects are wrong. It is being mis-cited as evidence of a
defect rate that does not exist here.

### (d) Which landed commits assert a measurement later contradicted? — **the only arm with a
non-boundary base rate, and it fails on cost + on the string ceiling**

**47 of 500 bodies (9.4%) announce a correction** of a prior claim (matcher: `was false|was
wrong|refuted|corrects the prior|rotted|had been false|supersedes|…`). **222 of 500 (44.4%) cite
a hex sha.** So the repo corrects itself loudly and often — commit #3 in my sample is literally
`correct the residual-7 claim; it rotted in 40 minutes`.

The class Jev would add is the *unannounced* contradiction, which requires pairwise comparison.
Priced: over 200 commits there are **217 adjacent same-file pairs** and **1,098 full within-file
pairwise combinations** across 162 distinct files (379 file-touch rows; p50 files/commit = 2).
Extrapolated to 500 commits: ~543 adjacent / ~2,750 full. Two bodies at p50 1,731 bytes each fit
the ceiling trivially, so it is **not** ceiling-bound.

It dies on three things instead:
1. **The output is unusable without a string.** `pair (X,Y) contradiction p=0.87` tells you two
   commits disagree somewhere in 900 words. The human then reads both. That is the rank-memory
   pattern and is acceptable — but at a base rate I hand-estimate near 0 (the 217 adjacent pairs
   are overwhelmingly "this commit builds on that one"), the read cost is all cost.
2. **Adjacency is the wrong join.** A measurement contradicted *four months later in a different
   file* is the interesting case, and the pre-filter that makes the budget tractable is exactly
   the filter that excludes it.
3. **Already covered, better, elsewhere.** The repo's own live instruments for this are
   `cc-premise` (falsifiers), `postland-verify`, and the `--falsifier` field on backlog rows —
   each of which re-derives a premise by *running a command*, not by comparing two prose bodies.
   Prose-vs-prose is the weakest available oracle for a question the repo already answers by
   execution.

### (e–h) My own candidates, all evaluated

| | candidate | verdict |
|---|---|---|
| (e) | Does the body name an operator-owned step that was never filed? (the `👤` leak) | Needs a **string** back to join against `~/.claude/autonomy/backlog.jsonl`. Jev cannot emit one. **Envelope-disqualified.** |
| (f) | Is the diff free of changes the subject/body do not describe? (rule G4, scope-metastasis) | 20/20 clean. p50 = **2 files**, p90 = 4. The ≥8-file tail (21 of 500) is legitimately wide by construction — a 179-file vendor mirror, a 75-file rules tiering. Base rate ~0. **Dead.** |
| (g) | Does line 1 lead with the outcome? | Style, not value. Its absence would not be noticed. **Dead.** |
| (h) | Is the `Gates: … n/a` footer consistent with the file types touched? | **Mechanically checkable and I ran it.** 9 commits in 500 claim "docs only / tsc-lint n/a"; 6 touch a non-doc file — all six are `feat(vendor)`/`feat(mail)` adding `.webp`/`.svg` binary assets, for which "tsc/lint n/a" is **true**. 0 real defects, and the arm is a `grep` anyway. **Dead.** |

---

## 4. Ceiling fit, and the byte cap I would use (for a revival, not a recommendation)

Measured over the same 500 commits:

| | mean | p25 | p50 | p75 | p90 | p95 | max |
|---|---|---|---|---|---|---|---|
| full diff `-U3` bytes | 25,196 | 3,721 | **7,144** | 14,625 | 37,355 | 58,819 | 1,264,090 |
| `--stat` bytes | 249 | — | 148 | — | 328 | — | 12,158 (p99 1,969) |
| body bytes | — | — | 1,731 | — | 3,390 | — | 10,357 |
| files changed | — | — | 2 | — | 4 | — | 179 |

Fit against a 32,000-token state ceiling. Unified-diff text on this corpus is code-and-shell-heavy
at ≈3.2 chars/token, so 32k tokens ≈ 102 KB — but the ceiling covers **state + the longest
question**, and the vendor's own docs disagree with OpenRouter's `context_length` on whether the
request budget is 64k or 32k (unresolved, `jev-at-cost-api-2026-09-18.md` §2). Budget conservatively.

**The cap I would use: `CC_JEV_COMMIT_DIFF_CAP_B=60000`**, head-truncated, with body (p90 3.4 KB)
and `--stat` (p99 2 KB) sent whole.

| diff cap | commits fitting untruncated |
|---|---|
| 30 KB | 439 / 500 (**87.8%**) |
| **60 KB** | 476 / 500 (**95.2%**) |
| 100 KB | 487 / 500 (97.4%) |

At 60 KB: 60,000 + 3,400 + 2,000 = 65.4 KB ≈ **20.4k tokens**, a 36% margin under 32k even if the
ceiling is state-only. `--stat` alone fits for **499/500 (99.8%)** at an 8 KB cap, so a
stat-only arm is ceiling-free — but `--stat` cannot support any of (a)–(d): it shows path and
line counts, never content.

---

## 5. The literal strings, if the arm were ever revived

Copying `scripts/jev/rank-memory.sh`'s spec shape exactly (`choice` over ORDERED keys, never
`score`; ordering lives caller-side). State = `<subject>\n\n<body>\n\n<--stat>\n\n<diff head -c 60000>`.

```jsonc
{ "state": "<subject+body+stat+capped diff>", "questions": {

  "names_cause": { "type": "boolean",
    "instructions": "Does this commit message state WHY the change was made — a defect, an incident, a measurement, or a rule it enforces — as opposed to only describing WHAT the diff does?",
    "criteria": { "true": "it names a cause, a triggering incident, a measurement, or a rule the change enforces",
                  "false": "it only paraphrases the diff, lists files, or states an intention with no cause" } },

  "names_reader_delta": { "type": "boolean",
    "instructions": "Does the message tell a future reader what is now DIFFERENT for them — a behaviour, a contract, a command, a failure mode that is gone?",
    "criteria": { "true": "a reader could act differently tomorrow because of something stated here",
                  "false": "nothing here changes what a reader would do" } },

  "cites_evidence": { "type": "boolean",
    "instructions": "Does the message cite specific evidence — a file:line, a measured number, a verbatim error, a test count, a prior commit?",
    "criteria": { "true": "at least one concrete, checkable citation appears",
                  "false": "the claims are stated without any checkable reference" } },

  "subject_fidelity": { "type": "choice",
    "instructions": "How accurately does the SUBJECT line describe the DIFF below it? Judge only the subject against the diff; ignore the body.",
    "criteria": { "accurate": "the subject names what the diff actually changes",
                  "understates": "the diff does materially more than the subject says",
                  "overstates": "the subject claims more than the diff delivers",
                  "wrong-subsystem": "the subject names a component the diff does not touch" } },

  "claim_unsupported": { "type": "boolean",
    "instructions": "Does the message make a factual claim about THIS DIFF's CONTENT that the diff below contradicts? Ignore claims about test runs, timings, or work done outside the diff — those are unverifiable here and are NOT unsupported.",
    "criteria": { "true": "a stated fact about the diff's own content is contradicted by the diff",
                  "false": "every claim about the diff's content is consistent with it" } }
} }
```

**Caller-side rule** (the decomposed-extractor discipline: the model never emits the verdict):

```
p_why   = min(names_cause, names_reader_delta)          # conjunctive: a cause with no delta is a note
flag_A  = (p_why < 0.50) AND (body_words >= 20)         # <20w is the mechanical arm's job, not Jev's
flag_C  = subject_fidelity IN {overstates, wrong-subsystem}
flag_B  = (claim_unsupported >= 0.90)                    # the measured high-precision tail; never lower
rank    = sort desc by (flag_B, flag_C, 1 - p_why, 1 - cites_evidence)
```

Population gate, and it is the load-bearing line: **run only on commits touching ≥1 non-`.md`
file AND carrying ≥20 body words.** That is 305 of the last 500. Without it the run spends 37%
of its calls telling you that `docs(plan)` appends have short bodies.

---

## 6. Call budget and wall clock

Free tier ≈ **6 calls/min**, and `rank-memory.sh` budgets `N/6` to `N/2` minutes with
`CC_JEV_RANK_GAP=3` plus exponential backoff.

| arm | population | calls | wall clock |
|---|---|---|---|
| (a)+(b)+(c) one pass, last 500 commits, gated per §5 | 305 | **305** | 51–153 min |
| same over the whole trunk (5,339) | ~3,260 | 3,260 | **9–27 h** |
| (d) adjacent same-file pairs, last 500 | ~543 | 543 | 91–272 min |
| (d) full within-file pairwise, last 500 | ~2,750 | 2,750 | 7.6–23 h |

The 500-commit single pass is affordable inside the four-day window. **It is not affordable in
attention**: at a 0.3% base rate it returns ~1 true positive, buried in whatever false-positive
rate the reputable-wrapper anchoring produces.

---

## 7. Where it would run, and the price of each venue

| venue | verdict |
|---|---|
| **`/ship` land gate (blocking)** | **NO, and it is not close.** Blocking a land on a model's opinion of prose is a categorically bigger claim than anything shipped here. The land gate is already the repo's tightest chokepoint (§ `the-blocking-gate-was-stricter-than-the-repo-s-own-verifier`), it runs `CC_BATS_MAX_ROOTS=0` under the machine-wide land-lock, and adding a ~0.5 s network round-trip that can 403 puts a third-party dependency on the critical path of every land. The repo already ate this exact defect: `82af0f03b` records that the *retired* deference arm still spends a doomed round-trip on every no-tell close. |
| **post-land hook (advisory)** | Cheapest correct venue **if** an arm existed. One call per landed commit, never blocking, writing a JSONL beside `postland-verify`'s output. But at 63 commits/day × 0.3% it surfaces one row every 6 months. |
| **nightly launchd batch** | The venue that matches the shape — a batch ranker, `rank-memory.sh`'s own pattern. Would run under `com.claude.nightly-regression.plist`, whose PATH does not reach `/sbin` (see `0073e5a58`) — so resolve every binary absolutely. Correct venue, no cargo to carry. |

---

## 8. What to build instead — Jev-free, and its absence IS noticed

**277 of 1,692 commit shas cited in `docs/**.md` are not ancestors of `origin/main`.**

Method: `grep -rhoE '\b[0-9a-f]{9,40}\b' docs/ --include='*.md' | sort -u`, keep those where
`git cat-file -e <h>^{commit}` succeeds (1,692), then test
`git merge-base --is-ancestor <h> origin/main`. 277 fail.

By token length: 256 are 9-hex, 15 are 12-hex, 5 are full 40-hex. `git branch -a --contains`
returns **empty** for most — they are reachable only from this checkout's reflog and
`ship/backup-*` refs. Sampled:

| cited sha | its subject | containing refs | cited in |
|---|---|---|---|
| `041aaf280` | docs(cursor-crashpad): the signature was on trunk all along | *none* | `docs/research/cloud-lane-redesign-2026-09-10/A2-reach-flow.md` |
| `0824716f65e7` | perf(kitty): throttle redraws at high pane count | *none* | `docs/research/session-closure-and-resume-2026-08-02.md` |
| `0a131da73` | feat(capacity): the presence beat consulted at SPAWN | `ship/backup-53b766120`, `w4/spawn-presence` | `docs/plans/MASTER_STRANDED_WORK.md` |
| `1260708b3` | feat(test-hermeticity-lint): rule 9 | `ship/backup-df081b1b0` | `docs/lessons/a-fixture-s-hermeticity-ends-…md` |
| `15f8d5054` | fix(tests): restore the closing brace Round A dropped | *none* | `docs/plans/LIMIT_RECOVER_100P.md`, `…/W2.md` |

**This is the defect CLAUDE.md § S5 names by name** — *"a sha on no branch (a sibling's, or one
an ancestor-rewriting land replaced) resolves in your checkout and nowhere else. Before citing
one it must answer `git merge-base --is-ancestor <sha> origin/main`."* The rule is written; it is
enforced nowhere. Grepping `merge-base --is-ancestor` across `scripts/ hooks/ bin/` returns
`postland-verify.sh`, `wrap-ledger.sh`, `ship-backup-reap.sh`, `browse-mirror-sync.sh`,
`worktree-gc.sh`, `land-content-verify.sh` and others — **none of which audits `docs/` citations.**

🚨 **The correct check is content-level, not ref-level.** The resident memory
`cited-sha-may-not-survive-the-land` is exactly this population: a rebasing land rewrites the
object, so `--is-ancestor` rc 1 reads as "never landed" over content that IS on trunk. So the
auditor must be two-stage — `--is-ancestor` first, then, on failure, a content test
(`git log --all --oneline --grep` on the subject, or `git cherry`-equivalent by subject +
`--name-only` set) before flagging. **277 is the upper bound, not the count.** Narrowing it is
the first task and needs no model either.

Shape it exactly like `rank-memory.sh`: refuses before doing work (a repo with no `origin/main`
is a refusal, not a 0), reports the unresolvable tokens rather than skipping them silently, writes
JSONL, and never edits a doc. Venue: the nightly batch, or an advisory arm on `postland-verify`.

---

## 9. Adversarial self-pass — what I checked because it would have refuted me

1. **"You measured the repo at its best."** Ran the same measurement 2,000 commits back
   (2026-08-15/21, §1.3). Code-commit short rate there is 3.7%, not 0.3% — an order of magnitude
   worse and still an order of magnitude too low to justify a per-commit model pass. If the trend
   ran the other way the verdict would have changed; it does not.
2. **"The base rate is low, but Jev is cheap — just run it."** Priced in §6. The blocker is not
   dollars (this fleet has zero dollar exposure, `spend.usage_credits_authorized=false`) and not
   quota (Jev is off-plan). The blocker is **attention**: §7's `alarm-polarity` rule — an alarm
   that fires on ~1 of 305 rows, mixed with reputation-anchored false positives, carries fewer
   bits than one that never fires. That is the repo's own standing rule against this exact trade.
3. **"You dismissed (b) with a vendor anecdote."** No — with the envelope's own mandatory
   disqualifier, and with a measured mechanical control (§3 b-ii: 66.5% of body-named paths are
   legitimately absent from the diff, so even the *mechanical* version of (b) is 2/3 noise).
4. **"Maybe the value is in the 5,339-commit history, not the recent 500."** The older window
   refutes the direction, and the citation audit in §8 already covers the whole history — at
   1,692 cited shas over all of `docs/`, which is the correct corpus for a question about
   *whether the pointers resolve*.
5. **"Is `git show` really enough for (a)?"** Yes, and I proved the harder half too:
   `2046b1020`'s "Suite 30 → 42" claim is verifiable by `grep -c '^@test'` at the commit and its
   parent (30 → 42, true). The claims a model would be needed for are the ones whose evidence is
   a test run that git never saw.
6. **Gap I could not close.** I did not label (d) by hand over a real pair sample — I priced it
   and refuted it on join-shape and on the string ceiling, not on a measured base rate. If
   someone wants to revive (d), the honest next step is 30 hand-labelled adjacent same-file pairs.
   I state that as unrun rather than burying it: **arm (d)'s base rate is estimated, not
   measured.** Everything else here is measured.

---

## 10. Verdict

> **NO Jev deliverable exists over the commit/land record.** Candidates (a), (c), (f), (g), (h)
> are dead on a base rate pinned at a boundary (0%–3.7%, measured across two 500-commit windows
> five weeks apart). Candidate (b) is **disqualified by the envelope's domain-reputation rule** —
> it asks for hostile content detection inside a maximally reputable wrapper, which is the one
> shape the envelope forbids outright. Candidate (e) needs a string the primitives cannot emit.
> Candidate (d) is the only non-boundary arm and fails on join shape, on an unmeasured base rate,
> and on being already answered by execution (`cc-premise`, `--falsifier`) rather than by
> prose comparison.
>
> **The premise in the brief is the thing that is false.** CLAUDE.md §S5 worries that bodies may
> not hold what a close drops. Measured: the bodies hold it — 370-word mean over 306 consecutive
> code commits, 0% bodyless. **The tier that is broken is the POINTER, not the body**: 16.4% of
> shas cited in `docs/` do not resolve from trunk. That is `git merge-base --is-ancestor` plus a
> content-level second stage, it is specified in §8, and it is the one thing here whose absence
> we would notice — because a future reader following one of those 277 citations gets nothing,
> and gets it silently.
