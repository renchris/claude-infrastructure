# Context-economics: continuous recycle policy (2026-07-20)

**Operator goal (verbatim intent):** every session — the desk orchestrator first — must know
*intelligently, not via one hardcoded threshold*, when to recycle its context: take the **free win**
when idle even at lower fill; **hold** when the context holds live value, until a good pause-point;
and under high work volume + 2-way comms, **find a pause-point before** rot degrades decisions or
100% exhaustion breaks the session.

## What already existed (and stays)

`hooks/waiting-recycle.sh` (Fable panel 2026-07-19 + tiers 4ce6ffc0194f) already implements the
skeleton: Tier-1 idle free-win at an adaptive threshold (35→25 over idle hours), Tier-2 busy-medium
silent queue, Tier-3 busy-force drain at 75%, hard-hold pages, two-stage advisory→deterministic-fire,
damp-first arming. `hooks/boundary-handoff.sh` advises /handoff for ALL sessions at a committed+green
Stop ≥73%. Every safety property (false-negative bias, latches, cooldowns, shadow-default) is kept.

## The three gaps this closes

1. **Mid-conversation recycle (value blindness).** An active operator exchange leaves NO git/mailbox
   trace → S1–S5 classify the desk SAFE/idle → the free-win path can deterministically `/exit` the
   pane *mid-conversation* (the observed "74% mid-conversation" awkwardness — that fill was reached
   DURING an exchange the tiers could not see). The context's *value* was never a signal.
2. **No velocity awareness.** T_BUSY=75 is static. At high burn (heavy tool traffic, big pastes) a
   session can cross 75→90 inside one long turn — the forced drain arrives too late. At near-zero
   burn, 75 is needlessly early. "Find a point before exhaustion" requires a *forecast*, not a level.
3. **Busy silence between 50% and 75%.** Tier-2 queues silently; the model is never told to *plan*
   a pause-point while the choice is cheap. The operator named ≥50% as "getting high" — that is
   where pause-point planning must start, as an advisory to the intelligence that can actually
   judge a good boundary (the model), not as a force.

## New signals (hooks/lib/context-econ.sh — shared by both hooks)

| Signal | Source | Function |
|---|---|---|
| **burn** (pct-points/min ×100) | consumer-side sample history `<tel>.hist`, appended on each hook evaluation from the statusline telemetry (`/tmp/cc-telemetry/<sid>.json`); dedup by ts; reset on fill-drop (compaction) | `ce_sample` + `ce_burn` |
| **forecast_min** (minutes to the 88% wall at current burn) | derived from burn; `-1` when unknown/flat (≥2 samples spanning ≥120s required — sparse data degrades to legacy behavior, never to a guess) | `ce_burn` |
| **conversation recency** (age of last *interactive* turn) | bounded transcript tail (2MB); interactive = `type=="user"`, `isMeta≠true`, string/text content, no `tool_result`, not matching the auto-traffic regex (`<task-notification>`, `<local-command-stdout>`, `Stop hook feedback:` — session-continue/goal auto-drive re-prompts are `isMeta:true` AND prefix-excluded, two independent axes — plus our own `⟳/⚑/⚠` advisory glyphs) | `ce_last_interactive_age` |

Ground truth for the taxonomy was sampled from production transcripts (2026-07-20): human turns are
string-content `isMeta:null`; Stop-hook feedback is `isMeta:true` prefixed `"Stop hook feedback:"`;
tool results are content-array `tool_result` items. cc-notify peer injections arrive as typed text —
they COUNT as interactive (2-way coordination is exactly what deserves a hold), and are additionally
covered by the S4 mailbox hold.

## Policy composition (onto the existing tiers)

- **S6 conversation-hold (SOFT, new).** Fresh interactive turn (< `CC_WR_CONV_HOLD_S`, default 900s)
  ⇒ hold. Below the busy ceiling the recycle *waits for the exchange to quiet* (the "hold at valuable
  context until a pause-point"); at/above the busy ceiling it behaves like every soft hold — the
  forced drain still recycles (riding to the wall mid-conversation is strictly worse: the wall
  destroys the same conversation PLUS the session). Soft, never hard: a conversation is
  disk-recoverable through the transcript + the model-authored /handoff payload at Stage 1.
- **Forecast-driven early busy trigger.** `high_ctx` now fires at `used ≥ T_BUSY` **or**
  `used ≥ T_BUSY_MIN (60) ∧ 0 ≤ forecast_min ≤ LEAD_MIN (20)`. A fast-burning busy session gets the
  advisory→drain ladder while there is still lead time for the model to pick its own pause-point;
  a flat session keeps the static ceiling. Exec-gating is UNCHANGED (`--live --busy-force`) — the
  early trigger widens only advisory/shadow/page behavior, inside the established damp-first envelope.
- **Busy-medium pause-point nudge (advisory-only, new).** BUSY + soft-hold + `used ≥ T_NUDGE (50)`
  ⇒ one paced advisory ("plan the pause-point: commit → persist decisions → /handoff at the next
  natural boundary"), own pacer, re-arms every +10% fill (the boundary-handoff B-2 shape — silence
  again would be the bug). Never escalates to a fire from this branch; the idle path / busy ceiling
  keep that role. Conversation-aware wording when the soft hold IS the conversation.
- **All-sessions boundary advisory upgraded.** `boundary-handoff.sh` fires early on the same
  forecast (`used ≥ T_MIN (55) ∧ forecast ≤ LEAD`) and, when an exchange is in flight, keeps advising
  but tells the model to finish the exchange + persist FIRST — wording, not suppression (at ≥73% the
  advisory must not vanish mid-dialogue; the model is the pause-point judge).
- **Idle free-win**: unchanged (adaptive 35→25 already implements "very idle at lower context ⇒
  take it"); conversation-hold now correctly EXCLUDES a live exchange from "idle".
- **Model-side stewardship (the intelligent half).** A resident CLAUDE.md § makes every session treat
  context as a budget at every natural pause: idle ≥ ~35% ⇒ free-win /handoff; rich exchange ⇒ finish,
  persist (dod-persist / plan / memory), THEN recycle; heavy build ⇒ plan the drain before ~75%; never
  ride past ~85%; hook advisories are authoritative rails — act on the FIRST one. Hooks are the rails;
  the model is the judgment. Neither alone reaches 100th percentile.

## Why not an ML/scoring framework

The "intelligence" here is (a) *multi-signal* deterministic rails with honest uncertainty handling
(unknown burn ⇒ legacy behavior), plus (b) the MODEL as the pause-point judge, prompted early enough
to act — not a learned scorer. A scorer would be untestable in bats, unauditable in IDL, and would
re-introduce the exact "model must notice" failure the two-stage design killed (0/2419 prod fires).
Every new behavior is observable in `idl.jsonl` (`burn_x100`, `forecast_min`, `conv_age_s` fields).

## Safety envelope (unchanged invariants)

- New HOLD (S6) only ever *reduces* firing — ships live.
- New TRIGGERS widen advisory/shadow/page only; the busy EXEC still needs `arm --live --busy-force`;
  the idle EXEC still needs `arm --live`. Blast radius of a wrong early advisory = one block message.
- Sparse/absent history, missing lib, unreadable transcript ⇒ byte-identical legacy behavior
  (`command -v` guards; every seam falls to the pre-upgrade value).
- False-negative bias preserved: unknown ⇒ hold/legacy, never ⇒ fire.

## Knobs (env; all optional)

`CC_CE_WIN_S` 900 · `CC_CE_WALL` 88 · `CC_CE_MIN_SPAN_S` 120 · `CC_CE_TAIL_BYTES` 2000000 ·
`CC_CE_HIST_MAX` 120 · `CC_CE_AUTO_RX` (exclusion regex override) ·
`CC_WR_CONV_HOLD_S` 900 · `CC_WR_T_BUSY_MIN` 60 · `CC_WR_LEAD_MIN` 20 · `CC_WR_T_NUDGE` 50 ·
`CC_WR_NUDGE_REARM` 10 · `CC_BOUNDARY_T_MIN` 55 · `CC_BOUNDARY_LEAD_MIN` 20

## Follow-ons (named, not silently dropped)

- Statusline burn/forecast display segment (cc-context already shows fill; velocity display is a
  free observability win).
- Reaper-side "very idle builder" free-win closure is already owned by cc-reaper (finished+landed
  workers); no change here.
- `CC_WR_HARD_T` two-tier ≥80% relax (F1, prior panel) still deferred — composes cleanly with the
  forecast trigger when taken up.
