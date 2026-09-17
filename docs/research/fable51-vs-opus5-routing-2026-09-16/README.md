# Fable 5.1 @ low/medium vs Opus 5 @ high — should the fleet default move?

**Asked** 2026-09-16 by the operator, citing cursorbench, the Fable/Mythos 5.1 system card, and the
launch post: *"It seems like Fable 5.1 on lower reasoning efforts covers intelligence AND cost against
Opus 5 at higher reasoning efforts. Is there any reason to keep Opus 5 high as our starting model?"*

**Answer: keep `claude-opus-5 @ high`. The disqualifier is capacity arithmetic, not intelligence.**
Conviction 93%. Method: 12 agents — 7 evidence axes, 4 adversarial skeptics, 1 synthesis
(workflow `wf_6a986290-b5a`, 3.1M tokens, 477 tool calls).

## The three claims resolve differently

| Half of the premise | Verdict |
|---|---|
| **Intelligence, at MATCHED effort rung** | **Supported.** CursorBench 4.0 puts Fable 5.1 ahead at all five rungs (+4.4/+3.5/+4.5/+5.5/+5.2pp); the card's five effort-resolved charts are 3 ahead, 2 tied, 0 behind at matched medium. |
| **Intelligence, CROSS-rung (the actual premise)** | **Fails.** Fable@low vs Opus@high across the card's five charts: −0.5, +3.1, −2.7, −2.3, −2.9 — loses 4 of 5. At medium it splits, and the one clean win (FrontierCode) is confounded because Opus@medium ties Fable@medium there. |
| **Cost** | **Refuted in the currency we actually spend.** See below. |

## Why cost is the whole answer

This fleet has **zero dollar exposure** — `accounts.json` `spend.usage_credits_authorized: false`
AND `frontier.credits_authorized: false` (both verified directly). Every dollar chart in the launch
post, the system card and CursorBench describes an economy we are not billed in. The only scarce
resource is **4 × 100 weekly percentage points**.

In that currency:

1. **Fable is not a separate budget.** `accounts.json` `frontier.coupling: 0.5`, whose own comment
   reads *"coupling = fable_cap/weekly_cap per SSOT '<=50% of weekly usage limits'"*. It is a
   **sub-cap of the same weekly bucket**, hard-bounded at half.
2. **It draws that shared bucket ~3.2–3.7× faster per token** (corrected upward from a first pass by
   a skeptic who found the census lacked `message.id` dedup; the corrected figure survives three
   independent denominators — weekly 3.71×, price-list out-of-sample 3.6×, 5-hour meter 3.25×).
3. **Therefore a Fable-only week ends at `fable 100 / weekly 50`** with half the fleet's weekly
   capacity permanently unspendable, *at any quality level*. That disqualifies Fable as a DEFAULT
   before the intelligence question is reached.

This is biting live, not hypothetically: the fleet reads `weekly/fable = 94/7 · 41/13 · 6/0 · 100/76`
— the fourth account holds 24 points of Fable sub-cap it cannot spend because general weekly hit 100
first.

Anthropic prescribes the opposite order from the proposal: *"For most workloads, start with Claude
Opus 5… Tuning effort is often a better lever than switching models."*

## What our own prior measurement can and cannot say

`docs/research/fable51-effort-sweep-2026-09-10/` reported Opus 5 @max 12/36 beating every Fable 5.1
effort. **Do not cite that as "Opus wins."** Its skeptic confirmed the direction and destroyed the
significance: paired 4–2 discordant, **exact sign test p = 0.6875**, with 21 of 36 defects found by
no arm at all. And its Opus arm ran `@max`, cross-run from a month earlier.

> **`claude-opus-5 @high` — our production default — has never been quality-benchmarked, by us or by
> the vendor, on any corpus.** Specified as R2 on 2026-08-16; unrun since.

## The live defect this surfaced

`scripts/effort-parity-assert.sh` is **RED on 4 of 5 config dirs** (reproduced this session):
`.claude=medium`, `.claude-next=low`, `.claude-tertiary=medium`, `.claude-quaternary=low` against a
floor of `high`, plus a launcher DRIFT row. **"Opus 5 @ high" is only true where the launcher passes
`--effort high` explicitly** — every non-wrapped surface on four of five accounts resolves medium or
low. Realigning the five `settings.json` is an authority-ceiling (class-C) operator step; the script
says so itself.

## Nine blockers, if a flip is ever reconsidered

B1 Fable-scoped limit message shape never captured (limit-recovery poller is blind to it) ·
B2 the 0.5 coupling — the unmovable half · B3 Opus 5 @high unbenchmarked ·
B4 the close contract is a lexical gate calibrated on Opus-5-era closes, and 5.1's denser-prose /
less-formatting deltas attack exactly the rung glyph and the `▶` act line, both BLOCKING Stop hooks ·
B5 `handoff-fire.sh:9030` halts the caller on a fable rank refusal and `:8765` kills account re-pick ·
B6 the frontier spawn cap's population inverts (it exits 0 on empty `.tool_input.model`) ·
B7 the flip route is unspecified and pivots the blast radius · B8 a Fable default silently changes the
system prompt bundle CC sends · B9 the card reports 5.1 is *"slightly more willing than Opus 5 to
bypass approval gates"* and *"accepts unverifiable claims of authorization somewhat more readily"*.

## The one genuinely novel pro-Fable finding

`per_turn_effort` is **Fable-5.1-only** in the 2.1.260 client registry (opus-5's capability list lacks
it; the client carries a latch: *"model rejected output_config.effort; latching unsupported and
retrying without it"*). Fable 5.1 is the only model in our stack that can change effort
mid-conversation without invalidating the prompt cache. If routing ever moves to the effort axis,
that is the enabling capability. Note the SSOT and the bundled `claude-api` skill disagree here — a
live A/B settles it.

## Re-derive

Full dossier: `SYNTHESIS.md`, seven axis files `A1`–`A7`, four skeptic files `V-*`,
instruments in `instruments/`. The two load-bearing facts are one command each:

    python3 -c "import json;d=json.load(open('$HOME/.claude/accounts.json'));print(d['frontier'],d['spend'])"
    bash scripts/effort-parity-assert.sh

**Do not quote the 3.2–3.7× ratio or any weekly/fable percentage from this document as current** —
both perish. Re-measure them with the commands above.
