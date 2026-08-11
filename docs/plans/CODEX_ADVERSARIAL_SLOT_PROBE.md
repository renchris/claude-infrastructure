---
status: open
---

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

- **2026-08-10** — Plan created. Not started. Predecessor `MULTI_PROVIDER_PLANS.md` complete: Codex
  CLI 0.147.0 pinned `gpt-5.6-sol` @ `xhigh` (proven), `pi-codex` authenticated on ChatGPT Plus,
  `/accounts --agents` renders provider state. Codex weekly window measured at 11–12% used with a
  single 7-day bucket resetting Mon 2026-08-17 20:08 — i.e. effectively idle, which is the correct
  resting state until this probe certifies a slot.
