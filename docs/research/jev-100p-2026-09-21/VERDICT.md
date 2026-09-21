# Jev, 100th-percentile utilisation — the decision and what it rests on

**2026-09-21.** Ten parallel research agents, two of them adversarial by design. **Nine of the ten
refuted their own family.** This file is the decision and the losers; the ten artifacts beside it
carry the measurements.

---

## The answer

**Build one thing: a comparative promotion pass over the 278 memory lessons that are reachable from
nothing, run by a launchd job that is inert until the operator arms one window.**

Landed and live: `scripts/jev/promote-memory.sh`, `scripts/jev/jev-batch.sh`, `scripts/jev/arm.sh`,
`launchd/com.claude.jev-batch.plist`, `docs/activation/pending-activation/44-jev-batch-activate.sh`,
`hooks/lib/jev.sh::jev_window_open`, `tests/jev-promote.bats` (21).

---

## Why every other candidate lost, in one line each

| family | the measurement that killed it | source |
|---|---|---|
| in-hook semantic verdicts elsewhere | `waiting-recycle`'s prose regexes fired **0 times in 2,417** reached evaluations; the one genuine second member (`agent-teams-enforce`) writes **no log row at all**, so its positive class has never been measured. Instrument it first — three lines, zero calls. | a1, a7 |
| backlog / decision / activation rows | "Is this premise still true?" is a question about the machine **today**. Jev sees a 900-character string. **0 of 12** hand-labelled open rows were decidable from row text; 11 needed a command. The useful judgment needs a *tool call* back, which the envelope forbids absolutely. | a2, a7 |
| commit-body quality | Base rate pinned at a boundary — **0%–3.7%** across two 500-commit windows five weeks apart. Bodies are immutable, so the output is unactionable by construction. One candidate is disqualified outright by the domain-reputation rule. | a3, a7 |
| plan premise rot | The brief had the halves backwards: **grep narrows 5,733 → 59 (97×)**, and of those 59 exactly **4** are genuine rot. Jev-first costs 1,415 calls here and ~13,000 machine-wide. A ~60-call rider, not a deliverable. | a4, a7 |
| decorative bats tests | `bats-assert-liveness.py` reports **0 dead in 718 files / 14,693 bodies** — and that zero is not luck, it is a ratchet **held at zero by a blocking land gate** with an automated fixer. The residual class has a free exact oracle: run the mutant. | a6, a7 |
| land-gate refusal prediction | The best-labelled surface in the fleet (**n=6,286**, balance **41/59**, **720.4 h** burned on 3,130 refused lands) and the biggest prize — but a NEW arm cannot be built, validated and tuned inside four days when every call is operator-run. **Filed**, not dropped: backlog `911996892e1c`. | a10 |

---

## Why the winner is the winner, and why it is not the obvious form of itself

`cc-jev rank` ran on 2026-09-21 and scored 140 indexed rules. **118 of them — 84.3% — came back
`often`**, on a four-level scale that never once used its top level, while `superseded` ranged
0.08–0.89 with **zero** rows in the ≥0.90 band `hooks/lib/jev.sh` defines as the only actionable
one. Every individual verdict was defensible. The ordering was worthless.

That is Addendum 4's finding one level up: the deference arm died of a property of its
**population**, not of the model, and nobody saw it until the answers were crosstabbed. Re-using
`bite` on 278 orphans would tie ~233 of them with 118 incumbents.

**So the question had to lose its scale.** Heats of five — *given these, which one* — then each
winner head-to-head against a **weak** incumbent. A forced choice cannot pile 84% into a bucket
because there is no bucket. It is also the shape the decision actually has: the index is **full**,
so "this orphan is good" changes nothing and "this orphan beats that incumbent" is an edit.

Three things ride along for free or nearly so:

- **`same_rule`**, a dedup boolean in the same call, on exactly the pairs where a dedup answer
  changes a decision. Standalone dedup is O(n²) = 89,676 pairs and stays refuted.
- **A discrimination report** on `cc-jev rank` itself: every question's max-bucket share, with
  anything ≥80% named NEAR-CONSTANT in the output. One run now tests its own rubric.
- **`--report`** on both tools: re-read any past run, no key, no route, no call.

## The control that can kill it, and it is not decoration

Two lessons in one state is a form **no existing call site uses**, so position bias here is
un-evidenced rather than known-absent. A sample of round 2 re-runs with the blocks swapped; above
**20% flips** the report says the design is REFUTED and to ignore the swap list.

Its first implementation indexed a `--slurpfile` as `$all[0]` — the first object, not the array —
so every row errored to stderr, stdout was empty, `wc -l` read 0, and the run printed
`0 of 2 pairs (0%) changed` with a ✓ PASS. **A broken control reporting the safe answer is worse
than no control.** Now computed in one `-s` pass; a jq failure renders NOT COMPUTED, never zero;
and its arithmetic is red-proofed on hand-built rows in both directions.

---

## Three corrections this wave produced, each to something we had written down as measured

1. **🚨 `score` was never blocked by the vendor.** Three places recorded it as rejected
   `invalid-response` "so the runtime schema is stricter than the published type". That round trip
   **never left 127.0.0.1**: the SDK's client-side `validateEvaluationAnswers` requires a complete
   probability distribution, and our own mock emitted one key for `score` while emitting the full
   map for `choice`. A/B through `evaluate.mjs` unmodified: one key → `invalid-response`, complete
   map → ok. Fixed, pinned by a test. *We still use `choice`* — refuting the objection is not
   establishing the claim, and the score **question** shape has still never been sent to the real
   route. (a9)
2. **The rate limit is ~14.8 calls/min, not ~6.** Measured over 146 consecutive calls in 593 s. The
   "~4 calls before throttling" in two scripts traces to **n=6, one burst, on the account's first
   ever Gateway request day** — and the two scripts already disagreed with each other. The run they
   budgeted at 24–73 minutes took **9.9**. (a9)
3. **The 2026-09-25 cliff is metered, not a cut-off, and no guard existed.** `CC_JEV_FREE_UNTIL` was
   read at exactly one line in the tree, inside a `printf` — displayed, never enforced. Now
   `jev_window_open`, failing **closed** on an unreadable clock, because a wrong refusal costs a
   re-run and a wrong approval costs a bill. (a9)

---

## The thing the red team said we would talk past, quoted so we cannot

> **"Most likely to be talked past: the unnoticed-output test.** It carries no number, and every
> family emits a plausible sorted JSONL."

And a8, independently: *"nothing reads the output. Propose the consumer or the schedule is
ceremony."*

The consumer here is the **swap list** — pairs of (promote this orphan, demote that weak incumbent),
one index slot each, which `cc-memory-rotate` decides today on mtime that its own header documents
as anti-correlated with durability. With no weak-incumbent anchors on disk the run **refuses**
rather than substituting an arbitrary incumbent, because a swap list built against a strong
incumbent recommends evicting a rule that is holding its slot correctly.

Refuse three phrasings on sight, per a7: *"it's offline so it's cheap to try"* (that sentence sold
§4 rank 3, which has since written 0 rows), *"a partial ranking beats nothing"*, and Addendum 4's
*"Jev has not been evaluated on any task other than deference"* — a gap in evidence, not a
candidate.

---

## The one thing that is the operator's

Decision packet **`ea7a241bdf78`**, conviction **88%**: may the scheduled job call out on its own,
or does it keep needing a per-window arming? A launchd job is **not** bound by the session
permission classifier — it is a daemon with no Claude Code process in the loop, and this machine
already POSTs briefs to `api.anthropic.com` every 300 s. So a bare timer here would silently convert
one typed command into a standing outbound flow of our engineering lessons under standard retention
(ZDR is Pro/Enterprise-only and 403s on this plan). Nobody decided that. The sentinel keeps the
*schedule* durable and the *consent* per-window.

## Re-derive, never re-quote

```
bash ~/Development/claude-infrastructure/bin/cc-jev rank --report ~/.claude/autonomy/jev-rank-20260921T050814Z.jsonl
comm -23 <(find -H "$MEM" -maxdepth 1 -name '*.md' ! -name 'MEMORY*.md' -exec basename {} \; | sort -u) \
         <(grep -o '](\([^)]*\.md\))' "$MEM/MEMORY.md" | sed 's/](//;s/)//' | xargs -n1 basename | sort -u) \
  | while read -r f; do grep -qF "$f" .claude/rules/agent-operating-lessons.md || echo "$f"; done | wc -l   # 278
cc-decide list --open | grep ea7a241bdf78
cc-backlog list --open | grep 911996892e1c
```
