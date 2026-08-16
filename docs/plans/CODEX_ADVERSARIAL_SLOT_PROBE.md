---
status: complete
---

<!-- CLOSED 2026-08-11 (W4), frontmatter corrected 2026-08-15. The status log below already read
     "PROBE CLOSED — status: answered", but this frontmatter still said `open` — and it is the
     machine-readable SSOT that scripts/find-plan.sh and every `plan-open` falsifier read. So the
     plan kept minting an "advance CODEX ADVERSARIAL SLOT PROBE" backlog row four days after the
     probe had answered its question. The verdict is a REJECT, and on a REJECT the encoding IS the
     written rejection: model-config.yaml is deliberately untouched and roles.research_adversarial
     stays claude-fable-5. Uncertified means unrouted. -->


# CODEX ADVERSARIAL SLOT PROBE — certify (or reject) `gpt-5.6-sol` for `research_adversarial`

**Created:** 2026-08-10 · **Base:** `origin/main` · **Predecessor:** `MULTI_PROVIDER_PLANS.md`
(which made Codex reachable and proved its pin; this plan decides whether anything should ROUTE there)

**Scope (frozen):** run ONE probe answering ONE question — does `gpt-5.6-sol` earn the
`research_adversarial` slot currently held by `claude-fable-5`? Produce a certified ADOPT / REJECT /
SPLIT verdict recorded in `~/.claude/model-routing-freewin-probe.md`, and flip
`model-config.yaml roles.research_adversarial` **only** on a certified result. No other slot, no
other provider, no wiring of autonomous lanes.

**Standing constraint (operator, 2026-08-10):** *"We don't want to exhaust usage for the sake of
usage. $20 Codex is a drop in the bucket next to $200 × 4 Claude accounts. We want to optimally use
it for its traits that surpass Opus 5 / Fable 5 when called for."* ⇒ **Uncertified means unrouted.**
A mostly-unused Codex window is the CORRECT outcome of this plan, not a failure of it. The $20 is
not there to be spent; it is there to buy independence at the two or three moments independence is
worth more than raw capability.

---

## Phase 0 — Agent Team Orchestration

**EXECUTION LOCUS PER WAVE:**

| Wave | Locus | Why |
|---|---|---|
| W1 Brief corpus + harness adaptation | **S** (dispatched session) | default for an implementation wave |
| W2 Run the grid (candidate + incumbent outputs) | **S** | default; long-running, high token volume, must not sit in the lead's window |
| W3 Mixed-vendor judge panel + verdict | **S** | default; the judging is the deliverable and must be isolated from whoever produced the outputs |
| W4 Encode the verdict + guards | **L** (lead-inline) | a 2-line `model-config.yaml` edit + a ledger row; splitting it would cost more context than it saves |

**Lead context budget:** hold ≥50% for deciding. Each wave is one dispatched session, fired and
awaited, with `--goal` naming a measurable end state the session PRINTS.

**Dependency graph:** W1 → W2 → W3 → W4, strictly serial. W2 cannot start before the brief corpus is
frozen (a brief edited mid-run silently changes what the panel is comparing).

**Single owner per shared file:** `~/.claude/model-config.yaml` and
`~/.claude/model-routing-freewin-probe.md` are owned by W4 exclusively.

---

## The question this probe must answer — and why the existing harness does not ask it

`model-routing-freewin-probe.md` is a **substitution** instrument. Its decision rule is: panel TIE
**and** candidate cheaper ⇒ ADOPT (a free win); ANY reliable incumbent edge, even ~1% ⇒ REJECT. That
is exactly right for the slots it has certified (Sonnet-5 @max for the Workflow synthesis worker,
after @low/@med/@high/@xhigh were rejected).

🚨 **It is the wrong instrument for an adversarial slot, and using it unmodified would produce a
confidently wrong verdict.** Substitution asks *"is B as good as A?"* The adversarial slot's value is
not goodness-in-general, it is **catching what the other model misses**. Those come apart:

- A candidate can **lose head-to-head and still be worth routing**, if the defects it finds are ones
  the incumbent systematically misses. Its misses being *uncorrelated* is the product.
- A candidate can **tie head-to-head and be worth nothing**, if it finds the same defects the
  incumbent already finds. A tie means redundancy, and redundancy in a verification slot buys
  nothing at any price.

So this probe measures **complementarity**, not substitution: over a corpus of briefs with known
defects, what is the **non-overlap** of findings, and in whose favour?

**Why this matters more than a benchmark claim.** The only trait established as surpassing Opus 5
and Fable 5 is **decorrelation** — Opus cannot be independent of Opus, and Fable, being the same
family, cannot either. That is true by construction and needs no eval. Everything of the form
*"GPT-5.6 is better at X"* is unproven here and must not be routed on. This probe therefore tests
the one claim that has a mechanism behind it.

---

## W1 — Brief corpus (the measurement's foundation, and its main failure mode)

**Deliverable:** a frozen corpus of **8–10 real briefs** drawn from this repo's own history, each
with a **known ground-truth defect list**.

Source them from landed fixes where the defect is documented and the pre-fix tree is reachable —
this repo's `MEMORY.md` index is an unusually good corpus, because each entry names a defect that
survived a first look. Strong candidates (each already has a commit and a written mechanism):

- a falsifier that measured a SYMPTOM and passed for the wrong reason
- a guard whose denylist enumerated spellings rather than the class
- an exact-count assertion that red-lined on its own subject's growth
- a gate keyed on a metric that contained the leak it was measuring
- a probe that acted on absence without confirming presence

🚨 **The controls that make this corpus non-vacuous** — this repo has been bitten by each:

1. **A defect ALREADY fixed by a sibling mechanism makes a brief vacuously passable.** Pin the
   sibling axis inert, or the brief proves nothing (memory: *sibling guard voids the fixture*).
2. **The pre-fix tree must be the REAL artifact**, not a hand-reconstructed approximation — a
   hand-edited stand-in passes vacuously (memory: *control must replay the real artifact*).
3. **Include ≥2 briefs with NO defect.** A panel scoring only defective briefs cannot distinguish a
   good finder from a model that always reports something. False-positive rate is half the verdict
   in a verification slot, and the substitution harness does not measure it at all.

### W1 outcome (2026-08-10) — DELIVERED, and control 3 cost more than controls 1 and 2 combined

Corpus at `tests/fixtures/codex-probe/` — **9 briefs, 7 defective + 2 clean**, `manifest.json` plus
one `briefs/<id>.md` per brief. Ids are opaque (`cp-01`…`cp-09`) because the id appears in the brief;
the descriptive title lives in the manifest only. Mechanism spread, one brief each: a denylist
enumerating spellings · an exact-count assertion tripwiring its own suite's growth · a `verdict=OK`
certifying a precondition never measured · an assertion whose span is the whole repo · a page whose
success is the notifier's exit code rather than its delivery verdict · a lookup miss in the wrong
namespace booked as proven absence · a spawn time read from a registry that by construction cannot
hold it.

**Controls, as built.** Control 2 is *checked, not asserted*: every brief body is extracted
byte-for-byte from its `pre_fix_ref`, and `verify-corpus.sh` re-extracts and diffs. Control 1 is
pinned **by construction** — a brief is a self-contained text artifact (no repo, no suite, no lint,
no docs, no history, no execution), and each record's `sibling_axis_pinned` names the specific
sibling that would otherwise leak. Two are worth knowing: `cp-04`'s defect is stated almost verbatim
in `docs/research/terminal-for-30-panes-2026-07-31.md`, and `cp-02`'s assertion goes visibly red the
moment the suite is RUN. Three siblings are **anti-leaks** — the pre-fix test suites for `cp-01`,
`cp-06` and `cp-08` each *certify the defect as intended behaviour*, so a reviewer who found them
would be argued out of the finding.

🚨 **The finding that changes how W1 should have been scoped: "nobody ever fixed it" is not evidence
a file is sound.** Clean briefs were first selected on the only mechanical basis available — zero
subsequent commits to the path. Candidates were then put through an independent adversarial pass over
the same defect classes the corpus scores. **Thirteen were screened and nine were convicted** (as of 2026-08-10; the figure moved twice while late screens landed, so read it as a sample with its denominator, never as a census) — several
on scored classes, one on a defect already sitting in this repo's own red-team notes as an open
MED-HIGH finding, and one on an argument-parsing bug that spins forever at 100% CPU on a documented
flag. Two further candidates were rejected for **disclosure** rather than defects, before screening:
both were post-fix twins of `cp-01`, one narrating `cp-01`'s defect outright in its own comments and
the other sharing its subject matter, either of which would prime that brief in a single-context run.

The four survivors are `scripts/pool-floor.sh` (→ `cp-03`), `tests/pane-modal.bats` (→ `cp-07`),
`tests/origin-identity.bats` and `hooks/lib/origin-identity.sh`; the last two arrived after the corpus
was fixed and are held as **vetted alternates** should either seat be challenged in W3. The
surviving basis for `clean` is therefore **screened and not convicted**, recorded per record in
`screen`, and a screen only clears a candidate if it *executed* rather than reasoned — both survivors
were cleared by running the subject against real data and independently reimplementing the thing
under test. `cp-03` additionally carries a `known_findings_not_scored` entry: the screen disclosed one
real-but-inert imprecision, with an explicit instruction that an arm reporting it must be CREDITED,
not scored as a false positive.

Consequence for W3, and it is not a footnote: at a 9-in-13 base rate, a model reporting a defect on a
clean brief may well be **right**. The judge must adjudicate every such finding against the code
rather than trust the label.

*(Screening also produced nine unlogged real defects in live infrastructure as a by-product —
including a `--trunk`/`--keep`/`--restore` argument spin in `scripts/branch-reaper.sh`, a memo salt in
`scripts/lib/gate-memo.sh` that omits `.shellcheckrc` and so can carry a green earned under looser
policy, and a swallowed `git diff` failure in `hooks/lib/session-writes.sh` that flips a close gate
fail-GREEN. Reports are in this session's scratchpad. They are out of W1's scope and are NOT filed by
this plan — someone should triage them.)*

**Two run-time requirements W2 must honour, or the controls collapse.** (a) An arm gets the brief and
nothing else — no repo, no tools, no network; an arm that can `git log` the subject finds the fix.
(b) **One brief per fresh context** — nine briefs in one session makes a finding on brief N depend on
briefs 1..N-1.

**Gated, not just checked.** `tests/codex-probe-corpus.bats` pulls the checker onto the land gate,
with RED controls for an in-fence edit, an out-of-fence append, and an unreachable ref. The
out-of-fence mutant earned its keep immediately: the first checker compared only the fenced region
and stayed green while a line was appended after it.

---

## W2 — Run the grid

| Arm | Config | Role |
|---|---|---|
| A | `claude-fable-5` (frontier default) | **incumbent** — what the slot holds today |
| B | `gpt-5.6-sol` @ `xhigh` | candidate, parity with the pinned Codex default |
| C | `gpt-5.6-sol` @ `ultra` | candidate, max reasoning + automatic delegation |
| D | `claude-opus-5` @ `max` | **cost anchor** — the fallback the slot degrades to when the frontier window is inactive |

**Why arm D is not optional.** If Codex loses to Fable but ties Opus, the actionable finding is about
*Fable's* premium, not about Codex. Without D the probe cannot distinguish "Codex is weak" from
"Fable is not worth 2× here" — and the frontier-routing skill already records that the
Fable-over-Opus delta has narrowed, so that is a live possibility, not a hypothetical.

**Run each arm on every brief, outputs stored verbatim.** Record for each run: model, effort,
provider, and — for Codex — `primary.used_percent` before/after from the rollout, which is the only
consumption signal either vendor exposes (neither reports tokens or dollars; see
`MULTI_PROVIDER_PLANS.md` § W1). Cost comparison is therefore **DIRECTIONAL only**, exactly as the
existing probe already concedes.

---

## W3 — Judge panel, and the one correction that decides whether the probe is valid at all

Inherit the existing protocol: **blind, ≥3 independent judges, default-to-refute**, judges hold repo
access, cited lines spot-checked byte-for-byte.

🚨 **The judge panel MUST NOT be all-Claude.** The existing probe uses Opus-max judges, which is
sound when both arms are Anthropic models. Here the hypothesis under test *is* cross-family
independence — so an all-Anthropic panel shares priors with arm A and evaluates arm B from the
inside of the very correlation being measured. **Use a mixed panel** (Anthropic + `gpt-5.6-sol`
judges), and report per-vendor judge agreement as a first-class result. If the two vendors' judges
systematically disagree about the same output, that disagreement is itself the decorrelation signal
— and it is invisible to a single-vendor panel.

**Scoring, per brief:** true findings, missed findings, false positives, and — the load-bearing one
— **findings unique to each arm**.

**Decision rule (adapted, and deliberately different from the substitution rule):**

| Outcome | Verdict |
|---|---|
| Codex finds real defects Fable misses, at an acceptable false-positive rate | **ADOPT** for the slot, or **SPLIT** (run both, union the findings) if each finds what the other misses |
| Codex findings are a strict SUBSET of Fable's | **REJECT** — a tie here is redundancy, not a free win |
| Codex false-positive rate materially exceeds Fable's | **REJECT** — noise in a verification slot costs more than a miss |
| Fable ≈ Opus and both ≥ Codex | **REJECT for Codex**, and file the separate finding that the frontier premium is unearned in this slot |

---

## W4 — Encode the verdict (and the guards that stop it rotting)

- Record the verdict in `model-routing-freewin-probe.md` alongside T1/T2/T3, in the same table shape.
- Flip `model-config.yaml roles.research_adversarial` **only** on ADOPT/SPLIT. On REJECT, write the
  rejection down — a rejected candidate that is not recorded gets re-proposed every few months.
- **Certify per slot AND per effort.** The Sonnet precedent is the warning: rejected at four efforts,
  certified at one. A blanket "use Codex for adversarial work" would repeat that mistake in a new coat.
- **Window guard, if anything is adopted.** Gate any autonomous Codex call on
  `primary.used_percent` read from the newest rollout under `~/.codex/sessions/` — a file read, no
  API call. Under threshold ⇒ run; over ⇒ skip until `resets_at`. Codex's window is a single
  unburstable 7-day bucket with an explicit reset, so the guard is cheap and exact.

---

## Known risks / open questions

1. **`ultra`'s delegation is opaque and unbudgeted.** Measured 2026-08-10: subagent spawning
   (`thread_source: subagent`, named agents with their own threads) occurred at effort **`high`**,
   so delegation is a `multi_agent_version: v2` model capability and is NOT exclusive to `ultra`.
   One sample — treat arm C as *"max reasoning with delegation made automatic"*, not as
   *"delegation unlocked"*. Its consumption per call is unpredictable by design; the window guard
   is the containment.
2. **Corpus bias.** Briefs drawn from `MEMORY.md` are defects that a Claude-family model already
   missed once. That tilts the field toward the candidate. It is also the honest population — those
   are exactly the defects the slot exists to catch — but the verdict must state the tilt rather
   than quietly benefit from it.
3. **Sandbox.** `codex exec` defaults to `sandbox: read-only` (verified 2026-08-10), which suits a
   review/verify slot. Any adopted lane must keep it; never widen it for convenience.
4. **This probe spends real quota on both sides.** Run it deliberately, once, not iteratively.

## Status log

- **2026-08-11** — **W4 DONE. PROBE CLOSED — status: answered.** On a REJECT the encoding IS the
  written rejection, so `model-config.yaml` is deliberately untouched and `roles.research_adversarial`
  stays `claude-fable-5`. Verified: T4 in `~/.claude/model-routing-freewin-probe.md`, verdict doc on
  trunk, corpus and runs unmodified. **The standing rule holds, and this is what it looks like in
  practice: uncertified means unrouted.** Nothing routes to Codex; its weekly window stays ~idle,
  which was always the correct resting state rather than a failure to extract value.
  **What the $20 actually bought:** not capacity, and not the decorrelated verification this probe
  was written to certify — but a measured answer to *"should anything route here"*, which beats the
  assumption in either direction. Two results outlive the verdict:
  (a) **the decorrelation is real but sits at the JUDGING layer, not the finding layer** — Codex
  judges refute 49–69 citation claims per Codex arm where Anthropic judges refute 2–3, so a
  single-vendor panel would have reported one of those readings as a confident number without
  knowing the other existed. That is a reusable argument for mixed-vendor panels generally, and it
  survives the REJECT.
  (b) **the incumbent question inverted** — the probe went looking at the candidate and found the
  problem was the incumbent (T5).
  **Follow-ons, both filed rather than acted on:** T5 (Fable-vs-Opus in this slot — NOT equal-effort,
  so it needs its own probe before any reroute) and the four-account Fable probe failure met while
  firing the successor wave.
  🚨 **Do not read this REJECT as "Codex is weaker".** Against Fable ALONE it is not a subset — B
  finds 2 and C finds 3 that A misses. It is contained only once arm D (Opus 5) joins the union,
  because D finds every one of them. The verdict therefore rests on OPUS's strength, not on Codex's
  weakness, and a probe against a different incumbent could legitimately reach a different answer.
  Anyone re-proposing Codex for a verification slot should re-read that sentence first.
- **2026-08-11** — **W3 DONE. VERDICT: REJECT** `gpt-5.6-sol` for `roles.research_adversarial`.
  Full verdict + every table: `docs/research/codex-probe-w3-verdict-2026-08-11.md`. Recorded in
  `~/.claude/model-routing-freewin-probe.md` as **T4** (live dotfile, not repo-tracked — nothing to
  land there). `model-config.yaml` NOT touched; W4 owns the encoding, and on REJECT the encoding is
  the written rejection.
  **The one number:** over 36 anchored ground-truth defects, **not one was caught by a Codex arm and
  neither Claude arm** — at every vote threshold including the ≥1-judge union ceiling. Claude-only
  = 3. Recall A 9 · B 9 · C 10 · D 13 of 36. Union: A alone 9 · A∪B 11 · A∪C 12 · A∪B∪C 12 ·
  **A∪D 14** · A∪D∪B **14 (+0)**. Codex is *contained*, not complementary — the plan's REJECT row,
  reached on the family union rather than on the incumbent alone (against Fable ALONE it is not a
  subset: B finds 2 and C finds 3 that A misses — but arm D finds every one of them).
  **Panel:** blind 4-judge mixed-vendor (2× `claude-opus-5`@max, 2× `gpt-5.6-sol`@xhigh),
  per-(judge,brief) label permutation, all 144 label→arm bindings verified byte-identical
  post-hoc, default-to-refute, cites checked against the real tree. 36/36 cells scored.
  **Per-vendor agreement — the mandated first-class result, and it did not land where expected.**
  On the anchored scoring the vendors agree 98% cross vs 99% within (−1 pp) with **no own-family
  favouritism in either direction** — so the table the verdict rests on is judge-vendor-independent.
  The split is entirely on the *unscored/citation* axis, where Codex judges refute 49–69 claims per
  Codex arm and Anthropic judges refute 2–3. **The decorrelation this probe measured is at the
  JUDGING layer, not the finding layer**, and a single-vendor panel would have reported one of those
  readings as a confident number without knowing the other existed.
  **Mechanical fact under that split** (measured independently of both panels): of 1,420 quoted code
  lines across all 36 outputs, **zero are absent from the file — no arm fabricated code, Codex
  included**. But 33–40% of Codex's quoted lines sit >3 lines from the number it cites (Claude arms
  4–5%), degrading sharply above ~600-line files. Cheap fix if re-probed: line-numbered input.
  **Robust to the W2 scar** — dropping cp-01 + cp-02 for all arms (the reconstructed arm-C pair, and
  cp-01 is arm C's best brief) leaves Codex-only at 0 and D ahead of A. Including them is the choice
  that favours the candidate; it still loses.
  **Corpus bias stated, not benefited from:** briefs are `MEMORY.md` defects a Claude model already
  missed once, which tilts the field toward the candidate. It had the friendly field and returned no
  unique coverage.
  **W2 constraints honoured:** arm C is a real tier (C>B 7/9, 1.76×) but `ultra`'s relation to the
  enum's `max` is **UNESTABLISHED** — the W2 table's "max reasoning" wording is refuted and is not
  relied on here; isolation is *evidence* none of the arms read the repo, not proof none could; cost
  stays DIRECTIONAL and **no $/finding figure was computed**.
  🚨 **Follow-on, filed as T5 in the routing ledger — the frontier premium is unearned in this slot
  and inverted.** Cost anchor `claude-opus-5`@max beat incumbent `claude-fable-5`@xhigh on recall
  (13 v 9), pairwise non-overlap (5 v 1), unique hits (2 v 0) and citation accuracy (96% v 93%), at
  half the price. **Not equal-effort** (the arms ran the efforts the ladder assigns them), so this
  cannot separate "Opus 5 > Fable 5" from "max > xhigh" — the premium is *undemonstrated*, not
  disproven. T5 = re-run A vs D at matched effort over this same frozen corpus; the corpus, harness
  and judging pipeline all already exist.
- **2026-08-11** — **W2 DONE.** 36/36 runs (4 arms × 9 briefs), all `ok:true`, verbatim outputs +
  `index.json` at `tests/fixtures/codex-probe/runs/`, landed `5673145d`. Nothing scored — that is W3.
  Run conditions in `runs/README.md`; read it before judging. Three things W3 must carry:
  **(1) The two isolation regimes are NOT equivalent.** Claude arms are hard-denied (`--tools ""`
  removes the tools — a probe told to read the real `manifest.json` fabricated both the call and the
  contents; `num_turns=1` on 18/18 is the per-run control). Codex `-s read-only` denies *writes* and
  permits reads of the whole filesystem, so arms B/C were **measured, not denied**: 18/18 rollouts
  show zero `exec_command`/`function_call` items. Evidence none *did*, not proof none *could*.
  `--setting-sources ""` was load-bearing — this repo's `MEMORY.md` states cp-01's ground truth in
  one line.
  **(2) Arm C is a real tier, not a duplicate of B.** `ultra` is absent from the API's
  reasoning-effort enum (a bogus value 400s) yet completes and is echoed back verbatim — the exact
  accepted-and-ignored shape this corpus exists to catch. Paired reasoning tokens on the same brief:
  **C > B on 7/9, 1.76× in sum**, so B-vs-C is a legitimate comparison. Still open and not to be
  overclaimed: its relation to the enum's `max` is unestablished, so arm C is "more reasoning than
  `xhigh`", not "the maximum" the plan's W2 table assumed.
  **(3) Cost stays DIRECTIONAL.** Codex weekly `used_percent` 22.0 → 27.0 across 18 runs; per-run
  rollout token counts are the finer-grained substitute and have no Anthropic-side equivalent.
  *Two arm-C records (cp-01, cp-02) are RECONSTRUCTED — the orchestrator was killed three times
  mid-grid while its `codex exec` grandchild survived; outputs are the untouched files those runs
  wrote, timestamps came from disk. Separately, a launchd relaunch with a minimal PATH lost
  `timeout`, and because a failed cell still writes a record, one missing binary manufactured 25
  false `ok:false` "results" in ~40s that then SKIPPED the real runs — purged and re-run, and the
  runner now preflights its binaries. Both are in `runs/README.md` § Known limitations.*
- **2026-08-10** — **W1 DONE.** Frozen corpus at `tests/fixtures/codex-probe/` — 9 briefs (7 defective
  + 2 clean), 36 anchored ground-truth entries, every `pre_fix_ref` resolving and every brief body
  proven byte-identical to its ref. Gated by `tests/codex-probe-corpus.bats`. Detail + the
  clean-brief finding in the W1 outcome section above. **W2 must run each brief in a fresh context
  with no repo access** — both are stated there, and both are load-bearing. W2 not started.
- **2026-08-10** — Plan created. Not started. Predecessor `MULTI_PROVIDER_PLANS.md` complete: Codex
  CLI 0.147.0 pinned `gpt-5.6-sol` @ `xhigh` (proven), `pi-codex` authenticated on ChatGPT Plus,
  `/accounts --agents` renders provider state. Codex weekly window measured at 11–12% used with a
  single 7-day bucket resetting Mon 2026-08-17 20:08 — i.e. effectively idle, which is the correct
  resting state until this probe certifies a slot.
