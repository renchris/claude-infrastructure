# Pre-flight land-refusal predictor — the instrument, and the arithmetic that may kill the candidate

Backlog `911996892e1c`. Written off-box on a cloud VM, 2026-09-21T08:58Z, branch
`claude/fire-20260921T082747Z-37696-1`. Receipt this item cites:
`docs/research/jev-100p-2026-09-21/a10-prior-art-and-labels.md`.

**Zero Jev calls were made.** Every arm below ran against the local mock
(`tests/fixtures/jev-mock-gateway.mjs`) or against the repo's real static analyzers.

---

## 0. Premise and vintage, checked before anything was built

| check | result |
|---|---|
| falsifier `test -e scripts/jev/predict-land.sh` | exit 1 at dispatch — NOT refuted. The file did not exist; it does now, and this artifact is why. |
| tree vs trunk | `git rev-list --count HEAD..origin/main` = **0**, and 0 ahead. This checkout **was** trunk at `c0d42c88`. The checkout arrived SHALLOW and was `--unshallow`'d before any trunk read. |
| dispatcher vintage | `git rev-parse origin/main:bin/cc-dispatch` = `dc9130372d6332940388c2a17da7c65c1af3c3bd` = **EQUAL** to the blob named in the brief. The dispatcher that fired this session IS trunk. |

Nothing was already cured; nothing here re-derives a fix on trunk.

---

## 1. What is delivered, and what is not

**Delivered and verified (1,763 lines across four files):**

| file | what it is |
|---|---|
| `scripts/jev/predict-land.sh` | the six-phase driver: `census · null · sample · baseline · ask · score` (+ `arm-print`) |
| `scripts/jev/predict_land_corpus.py` | the corpus reader, the null arithmetic, the stratified sampler, AUROC/PR/bootstrap |
| `scripts/jev/predict_land_score.py` | the join and the three frozen acceptance conditions |
| `tests/jev-predict-land.bats` | 24 cases, 24 pass, plan line `1..24`, no skips |

**Not delivered, and it is the measurement itself:** no AUROC, no precision, no verdict on whether a
model can predict a land refusal. Two independent reasons, both genuinely off-limits from here:

1. **The corpus does not exist off-box.** `~/.claude/land.log` lives on the operator's machine. This
   VM has none, so there was nothing to sample and nothing to score.
2. **`ask` sends diffs, and that is the operator's call.** See §5.

Per `docs/lessons/a-cost-premise-is-per-arm-and-is-usually-false.md`, the park is scoped to those two
arms ONLY. Everything a mock or a local analyzer could serve was built AND RUN, not deferred.

---

## 2. Three defects in the receipt's own corpus join — found in the producer, before any code

A10 defines the corpus as `jq 'select(.tool=="ship-land" and .head and .base)'`. Read against
`scripts/ship-land.sh`'s `attest_land` and against `scripts/gate-red-census.sh`'s header (which
already enumerates five traps in reading this store), that selector admits three row classes it
should not. None is symmetric noise.

**(a) `stage:"round"` rows are not attempts.** ship-land.sh:165 — *"a terminal outcome, or an
INTERNAL stale-gate re-round. ABSENT ⇒ land"*. One land writes one row per round, so pooling them
counts a single land several times, weighted by how often siblings happened to move trunk.
`gate-red-census.sh` excludes them (its trap 5); the receipt's selector does not.

**(b) `exit 9` is a claim about the MACHINE, not the tree.** gate-red-census.sh trap 2, citing
ship-land.sh:2508: *"exit 6 is GATE RED … a verdict about the TREE. exit 9 is GATE-KILLED: the gate
died without earning a verdict — explicitly NOT evidence about your tree."* The census reports them
side by side and **never sums them**. `select(.exit != 0)` sums them.

**(c) `"?"` is a non-empty string, so `.head and .base` passes on rows with no diff.** `attest_land`
writes `"${ATTEST_HEAD:-?}"` when a land died before the shas resolved. jq's truthiness test admits
those rows; their diff does not exist. Measured on the real-diff fixture: 1 of 41 invocations.

### Why (a) and (b) are not noise — they cap RECALL

A pre-flight predictor reads a **diff**. A diff cannot determine a lock timeout, a push race, a
loaded box, or a missing binary. Every such row in the positive class is a refusal **no correct
instrument can ever catch**, so it does not blur the boundary — it lowers the ceiling:

```
recall ceiling = |positives a diff can determine| / |positives|
```

And A10's acceptance condition (b) is *"precision ≥ 0.85 at recall ≥ 0.20"*. **A recall floor is
meaningless until that ceiling is known**, and under the receipt's own label definition the ceiling
is strictly below 1 by construction. `predict-land.sh null` computes it and **refuses to spend**
(exit 5) when no perfect instrument could clear the bar — because the ceiling is a property of the
LABEL DEFINITION, not of the sample, so collecting more rows cannot reach it.

**The number itself is not in this document, because it cannot be: it needs land.log.** One command
on the desk produces it (§5). That is the single highest-value read in this whole item, it costs
nothing, and it runs before any call.

### And the coin, which A10 asked for and did not compute

> *"Before any of that, run the arithmetic Addendum 3 wishes it had run: at the sampled REFUSED
> rate, what would a PERFECT detector return, and what would a COIN return? Write both numbers down
> first."*

At prevalence *p*, a random warner firing on a fraction *f* of lands gets **recall f and precision p
at every operating point**. *f* buys recall; it never buys precision. So:

- the bar "precision ≥ 0.85" is a **lift of (0.85 − p)**, never a margin over 0.50;
- "always warn" reads nothing at all and scores **precision p at recall 1.00** — which is a *better*
  recall than the bar asks for. The bar is only meaningful because 0.85 > p;
- on A10's own stated split (2,597 landed / 3,689 refused, p ≈ 0.587) the required lift is ≈ **0.26**,
  not ≈ 0.35. The scorer therefore prints `coin_precision` beside **every** instrument, always.

### A fourth, structural: the two questions cannot share one sample

The `red` field **has a birthday** — 2026-08-08T20:56:59Z, before which it did not exist
(gate-red-census.sh trap 3). So the `choice`-over-arms question is scoreable only on rows after that
date, while A10 instructs the binary sample to span 2026-07 → 2026-09 precisely so it does not
measure today's gate config. **Those are different populations.** A single 1,200-row sample asked
both questions answers the arm question on a recency stratum of itself. `null` reports
`arm_scoreable_rows` and `arm_recall_ceiling` separately so this is priced rather than discovered.

---

## 3. What actually ran here, and the four defects it caught in MY code

Per `docs/lessons/mirroring-a-corpus-is-not-using-it.md` — building the pipeline proves nothing, only
an artifact built WITH it does. So the instrument was run end-to-end against **41 real commit pairs
from this repository's own trunk** (real diffs, so the analyzers did real work) with synthetic
labels covering every class. Four defects surfaced that no amount of re-reading had:

| # | defect | how it read before it was caught |
|---|---|---|
| 1 | recall ceiling printed **2.0** — "16 of 8 positives". The numerator counted the whole population while the denominator used the narrower positive predicate. | as enormous headroom. A ratio above 1 is the one direction that **waves the acceptance bar through**. Now intersected, and a ceiling outside [0,1] is reported as an INSTRUMENT FAULT with its own verdict, because "fix the arithmetic" and "re-define the positive class" demand opposite actions. |
| 2 | the baseline scored **7 of 25 clean trunk commits as HITS**. Materialising a file into a temp tree leaves the linter with no `.shellcheckrc`, so the two codes this repo waives repo-wide (SC2001, SC2015) fired on code the gate had passed. | as the model's comparator — i.e. the baseline was a **second authority running a stricter standard than the gate it stands in for**. A/B on one row: 2× SC2015 without the rc, clean with it. Fixed by taking `.shellcheckrc` **from the row's own head sha** (the policy is version-controlled; a 2026-07 row must be judged under the policy in force then). Hits dropped 7 → 2, and both survivors are genuine findings at those shas that a later commit fixed. |
| 3 | **the disclosure-class scan never ran.** The pattern begins `-----BEGIN`, so `grep -qE "$re"` parsed it as an **option**, printed "unrecognized option", and exited 2 — which is falsy in an `if`, so every row read as clean and **was sent**. | the summary line honestly reported `skipped (disclosure class) 0`, which is **exactly what a clean scan looks like**. A fail-open egress gate on the one check standing between an unpushed diff and a third party. Fixed with `-e`; and rc 2 is now separated from rc 1 and **aborts the run**, because a scanner that cannot run is a non-verdict over every remaining row, not a pass. |
| 4 | **SC1073** — a comment line beginning with the linter's own name is parsed as a directive and **voids the lint for the whole file**. | as a clean lint. Hit twice: once in the arm-selection comment, and again in the comment written to document the first. ship-land.sh:3246 already records this trap; it caught the paraphrase of itself one run later. |

Defect 3's fix is verified in **both** directions, since one alone proves nothing:

```
pattern matching every diff  → 3 rows skipped, 0 calls made
pattern grep cannot compile  → ⛔ ABORT rc 3, 0 rows sent
default pattern             → matches RSA / PRIVATE / OPENSSH key blocks, rc 1 on ordinary diff text
old invocation (no -e)      → rc 2 ⇒ falsy ⇒ would have SENT
```

### Everything that ran

| phase | result |
|---|---|
| `census` | 41 invocations / 1 round row / 1 non-invocation / 1 bad-JSON line — **all four counters exact-match `gate-red-census.sh --json`** |
| `null` | all three label definitions; every ceiling now in [0,1]; lift-over-coin printed |
| `sample` | 40 reachable → train 25 / holdout 15, proportional across all 12 (class × month) strata, none rounded away |
| `baseline` | 25 real diffs, 46 s, real `shellcheck` + `bash -n` + `bats-assert-liveness.py` |
| `ask` | 25 calls through the mock, all 7 questions answered, token consumed **before** the first real call |
| `score` | a CONSTANT predictor (mock returns 0.99 to everything) scored AUROC **0.500** and **failed all three conditions**; its best operating point was precision 0.8 = prevalence exactly, at recall 1.00 — i.e. the scorer correctly identified it as `always-warn` and minted no pass |

### Gate statics, run here

`shellcheck` 0 findings (and the suite asserts the absence of SC1072/SC1073, so "clean" cannot mean
"not read") · `bash -n` clean · `py_compile` clean · `bats-shellcheck-lint --range` clean ·
`bats-assert-liveness.py` **rc 0** · `self-path-lint` 0 new unresolved · `test-hermeticity-lint`
0 new leaks · `utc-stamp-lint` 0 lying stamps · `rules-hook-budget-lint` N/A (no `.claude/rules` change).

`tests/jev-predict-land.bats`: **24/24, plan line present, no skips.**

---

## 4. Two design deviations from the brief, stated rather than slipped in

**(i) The choice vocabulary is 11 keys, not 14.** The item says "a choice over the 14 red arms".
A10's own census names 7 arms and puts the rest in a "+8 more" tail. Giving every tail arm its own
key creates classes with near-zero support, which is
`docs/lessons/a-rubric-that-saturates-has-not-ranked-anything.md`: a question that cannot
discriminate on the population has not ranked it. The block uses the 8 arms with real support, plus
`other-arm` for the tail, plus `none`, plus — required by §2(b) — **`not-diff-determined`. Without
that key the closed vocabulary forces the model to name an arm for a refusal no diff caused**
(`docs/lessons/closed-vocabulary-swallows-an-unrecognized-value.md`).

**(ii) The vocabulary is static, not derived from the census at runtime.** Deriving it would make the
question TEXT vary per run, and two runs asking different questions are not comparable. Stated as a
limitation: if the arm distribution shifts materially, the block needs a deliberate edit and a
re-baseline, not an automatic one.

**(iii) Five aimed booleans plus a roll-up, and the run is built to say whether that helped.** A10
proposed one `noul`. Six questions cost 6× the tokens, so `score` reports `max(sub-booleans)` beside
the roll-up and gives a paired CI on the difference — if the roll-up wins, the decomposition was a
bill. `q_dead` aims deliberately at an arm a static analyzer already covers: it is a **positive
control on the baseline**. If the model does not lose that one to `bats-assert-liveness.py`, the
baseline is not running.

---

## 5. The operator-only remainder, and exactly how to run it

Both steps need the operator's box; neither can be done from a VM.

**Step 1 — free, no calls, and it may end the candidate.** Run on the desk:

```bash
bash scripts/jev/predict-land.sh census     # refuses if it disagrees with gate-red-census.sh
bash scripts/jev/predict-land.sh null       # the ceiling, the coin, and the refusal
```

If `null` exits 5, the acceptance bar is unreachable **by a perfect instrument** on that label
definition and no call should be made under it. The `gate-red` definition is the one to try next.

**Step 2 — the arm, and it is a genuine widening.** Every Jev consumer to date sends prose the
*model* wrote, or our own lessons. This sends a **diff of this repository**, and for a REFUSED land
that diff was by definition never pushed — bytes that may never have left the machine. ZDR is
Pro/Enterprise-only on this plan and 403s, so the call goes out under **standard retention**.

`scripts/jev/predict-land.sh arm-print` prints the command; **it does not run it, and an agent must
never write that token** (arm.sh's own rule, and this file obeys it). The token is separate from
`cc-jev arm`'s on purpose: `jev-batch.sh` dispatches to `promote-memory.sh` regardless of its
`corpus` field, so widening that token to name this corpus would hand a land-diff authorisation to
a consumer that sends memory files.

**One more constraint on step 2's comparator.** The baseline was exercised here under
**shellcheck 0.9.0**; the repo's `.shellcheckrc` header cites 0.11 behaviour, i.e. the desk's
version differs. Condition (c) compares the model against *this* comparator, so the baseline must be
re-run on the desk under the desk's own analyzers. `baseline` emits its versions as a header row for
exactly this reason. (A/B'd here on one file: 0.9.0 and 0.11.0 **agree on the finding** but return
**different exit codes for it** — 2 vs 1 — so neither the gate nor this baseline may ever key on
rc 1 vs rc 2. Both test zero/non-zero.)

---

## 6. Residuals, stated rather than hidden

- **No capability measurement exists.** Everything above is instrument correctness and corpus
  availability. Whether a model can do this is untouched, and a green suite must never be read as
  evidence that it can.
- **The synthetic labels in the end-to-end run measure nothing.** Real commit pairs were used so the
  analyzers did real work; the labels were assigned by a fixed pattern to exercise every path. No
  accuracy claim is derived from them, and none may be.
- **The recall-ceiling number is unmeasured.** Its mechanism is established from the producer's own
  code; its magnitude needs land.log. This is the one thing I would most want measured next.
- **Reachability was 100% on this fixture and will not be in production.** A10 measured ~77% of shas
  still reachable. `sample` reports `reachable / unreachable` per run and drops unreachable rows
  before allocation, so a stratum cannot be quietly deflated by rebased heads.
- **`bats-assert-liveness-fix.py` mis-fixed a control-flow shape.** It appended `|| false` to
  `[ cond ] && { assignments; }` — a plain conditional, not an assertion — which then failed the test
  whenever the condition was legitimately false. The gate's own message warns a uniform `|| false`
  is wrong "for the whole `A && <never-succeeds>` family" and says the fixer DECLINES rather than
  guess; here it did not decline. Worked around in this diff by restructuring to `if/fi` (the fixer
  was not modified — out of scope). **Reported, not filed**: a reader of this section should decide
  whether the analyzer's `and-absorbed` class should exclude brace bodies that only assign.
- **A pre-existing red on Linux, identical on trunk.** `tests/jev-evaluate.bats` case 22 fails with
  `date: invalid option -- 'v'` — `date -u -v+45d` is BSD syntax that GNU date rejects. Run in both
  arms (trunk at `origin/main` in a scratch worktree, and this branch): **identical failure**, so it
  is not this diff's. It would pass on macOS. The portable idiom is already in the repo
  (`arm.sh`: `date -u -v"+${TTL}M" … 2>/dev/null || date -u -d "+${TTL} minutes"`). Not fixed here —
  outside this item's frozen scope.
