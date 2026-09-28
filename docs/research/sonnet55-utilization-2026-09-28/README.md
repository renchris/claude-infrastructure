# Sonnet 5.5 + Claude Code 2.1.284 — which model, at which effort, for which use case (2026-09-28)

**Answer.** Advance the binary to 2.1.284, bump `versions.sonnet_latest` to Sonnet 5.5, and **move no
role onto it.** Opus 5.5 stays the default for every class this fleet runs, at the rungs set on
2026-09-22 (`effort_defaults.opus55_*`). Sonnet 5.5 is a large step over Sonnet 5 and, on our review
corpus, it ties Opus 5.5 at every effort level. But in each slot where we could test a substitution it
either lost (synthesis worker, 0 of 6 briefs won) or tied without adding anything (review, as a second
reviewer). The vendor's own per-effort coding charts put Opus 5.5 ahead at matched cost. What it
offers is a cheaper rung for work that is already at parity, and that pays only when plan quota
binds. It draws 0.62× Opus 5.5 per output token, which is more per list dollar than Opus, not less (§ Quota).

The same research turned up four things that matter regardless of Sonnet:

1. **Both 5.5 models run at MEDIUM whenever `--effort` is omitted.** This holds on 2.1.280 and on
   2.1.284, and our user-level `effortLevel: high` never reached them. Migration 0044 pins
   Opus 5.5 to high.
2. **`agent-teams-enforce.sh` fails open on 20–27% of Agent calls.** It takes 1.9–3.6 s against a
   5 s timeout, so the teammate model policy has been leaking.
3. **`mailbox-drain` hands the lead's peer mail to subagents and loses it** (27 subagent
   transcripts in 7 days).
4. **`cc-classify` no longer recognises a 5.5-generation refusal.**

All four are being fixed by the harness wave (§ Harness changes).

The upgrade skills are consolidated into one, `/cc-upgrade`. It is landed and live (§ Skills).

## Sources and method

- **Operator-supplied (primary):**
  - [announcement](https://www.anthropic.com/claude-sonnet-5-5)
  - [System Card, 148 pp.](https://www-cdn.anthropic.com/870c8f525702625d2c62fc6dd04c857e3250bec1/Claude%20Sonnet%205.5%20System%20Card.pdf)
  - [Prompting Claude Sonnet 5.5](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5-5)
- **Linked from those (secondary):** what's new in Sonnet 5.5, the migration guide, effort, preserved
  thinking, and the models overview.
- **Facts.** Eight page-range readers over the card read every figure at native resolution; two
  readers covered the vendor pages. A second reader then re-checked every fact at its cited page.
  Result: 599 read, 570 confirmed, 29 corrected, 0 unsupported, and 169 added by the verifiers
  ([`notes/card-*.md`](notes/), [`notes/vendor-docs.md`](notes/vendor-docs.md)).
- **Critic.** A completeness critic ([`notes/critic.md`](notes/critic.md)) named ten gaps. The
  decision-relevant ones were closed by measurement, not by argument:
  - our own Sonnet 5.5 arms on two corpora (below);
  - six live probes, each re-checked by a skeptic ([`notes/probe-*.md`](notes/)).
- **Binary.**
  - The 2.1.281–2.1.284 CHANGELOG was read on three axes plus an adversary sweep of the tracker
    ([`notes/cc284-*.md`](notes/)).
  - `scripts/cc-upgrade-gate.sh` ran on `~/.claude-284` against both models the fleet will run
    there.
- **Currency.** `$` figures are `$list` read from the vendor's charts. This fleet is billed in
  weekly plan quota, not dollars. The quota measurement is § Quota.

## The table

Conviction is the author's number for "this is the right routing today". Anything below 90% is
research still owed, and the last column says what would move it. Every row except the last two
**keeps the 2026-09-22 routing**. The evidence column says what Sonnet 5.5 showed there.

| Use case (our surface) | Model @ effort | Sonnet 5.5 evidence | Conv. | Moves it |
|---|---|---|---|---|
| Lead / orchestrator; fired wave lead | Opus 5.5 @high | The prompting guide: "For the hardest long-horizon work, an Opus model is the better choice." The card's Pass³ reliability is 68.5, the lowest of the frontier set (p.135). | 95% | — |
| Long unattended implementation | Opus 5.5 @high (xhigh if novel) | Long-horizon coding evidence is max-only or unlabelled (SWE-Bench Pro, FrontierSWE v2, ProgramBench: Opus +11.5). At low/medium, Sonnet 5.5 checks in before multipart work is done. | 90% | — |
| Scoped coding wave | Opus 5.5 @medium | FrontierCode (vendor, `$list`/task): Opus medium **54.6 @ $0.80**; Sonnet medium 36.5 @ $0.24, high 49.4 @ $0.42, xhigh 52.1 @ $1.59, max 46.2 @ $20.78. CursorBench: Opus medium 52.5 @ $2.91; Sonnet xhigh 53.1 @ $3.88. No Sonnet rung beats Opus medium at equal or lower cost, and in plan points Sonnet costs ~1.2× Opus per list $ (§ Quota). | 92% | — |
| Code-writing teammate, ambiguous | Opus 5.5 @high | Same charts. Sonnet teammates are also policy-denied (not in `non_firstParty_max`). | 90% | — |
| Mechanical, known-target edit | Opus 5.5 @medium (low behind a gate) | FrontierCode: Opus low 47.3 @ $0.40 vs Sonnet high 49.4 @ $0.42, i.e. parity at equal `$list`, which in plan points (Sonnet ~1.2× per list $) tips to Opus. | 88% | — |
| Code review / bug finding | Opus 5.5 @xhigh; Fable 5.1 stays the complement | **Ours:** Sonnet 5.5 low 9 · medium 9 · high 8 · xhigh 11 · max 10 (/36) vs Opus 5.5 8 · 9 · 10 (medium/high/xhigh) in the same panel; no pair distinguishable (p ≥ 0.38). As a second reviewer it adds +2, Fable adds +4. | 88% | a larger review corpus: n=36 cannot separate any arm |
| Bounded verifier | Opus 5.5 @high | Not measured directly. The review parity suggests Sonnet 5.5 @medium would tie. | 80% | a bounded-verification A/B |
| Hard-reasoning judge | Opus 5.5 @xhigh | HLE: Opus dominates at every cost point (card p.119–120). | 92% | — |
| Breadth research worker | Opus 5.5 @high | DRACO above ~$1 and WANDR: Opus ahead (p.121–122). Sonnet low collapses on wide search (WANDR low 10.0 vs Sonnet 5 low 22.8). | 90% | — |
| Workflow bulk synthesis worker | Opus 5.5 @xhigh | **Ours:** Opus 5.5 @xhigh beat Sonnet 5.5 @xhigh 5-0-1, @high 5-0-1, @medium 6-0-0 (per-brief majorities, equal tools). Bad-citation rate 1.2–2.1% vs 4.5–14.6%. | 90% | — |
| Codebase retrieval (Explore) | Haiku 4.5 via `model: "haiku"` | The card has no Haiku comparator. Haiku 4.5's retirement floor is 2026-10-15, and Haiku 5.5 is announced for "the coming weeks". | 75% | the Haiku 5.5 release, a Sonnet-vs-Haiku retrieval probe |
| Visual / chart reading | Opus 5.5 @medium plus a crop tool | Chartography: tools add +28.6 points, and Opus leads without tools (p.125–126). Brief visual slots to crop and re-Read. | 80% | — |
| Adversarial slot | Fable 5.1 | Sonnet 5.5's errors are not decorrelated from Opus 5.5's (+2 vs Fable +4 as a complement). | 88% | — |
| **Any surface that runs Sonnet 5.5 anyway** (the alias `sonnet` on 2.1.284, a probe) | Sonnet 5.5 @high (`sonnet55_default`); @medium for scoped agentic (`sonnet55_agentic_scoped`) | Claude Code's default for it is medium, and user `effortLevel` does not reach it (measured). Always pass effort. | 90% | — |
| **Cheap review first-pass, only where quota binds** | Sonnet 5.5 @low (`sonnet55_review`) | 9/36 at a median 4.8K output tokens vs Opus 5.5 @xhigh 10/36 at 36.5K; at 0.62× per token that is ≈8% of the incumbent's draw (§ Quota). | 80% | a larger review corpus; a quota-bound week to use it in |

**max** is a key for neither model. Sonnet 5.5 max lost 3 of 9 review cells to the 128K output
cap, and it scores below xhigh on FrontierCode because it launches review subagents and edits out
of scope (announcement, footnote 2).

## Quota

**Sonnet 5.5 draws 0.62× Opus 5.5 per output token from the 5h plan meter.** Details:

- **Bounds:** the integer bound is [0.49, 0.76]; the skeptic's Monte Carlo 95% interval is
  [0.54, 0.70] (P(ratio ≤ 0.5) ≈ 1e-5).
- **Method:** next4, 2.1.284, effort high, `--tools ""`. An in-situ Sonnet / Opus / Sonnet burn with
  6-minute holds between phases.
  - Sonnet: 4.96 5h-pp per M output in **both** phases (1.61M tokens each, +8 pp each).
  - Opus 5.5: 8.05 5h-pp per M output (1.36M tokens, +11 pp). The 09-22 sweep measured 8.67 with an
    overlapping bound.
- **Clean run:** foreign `-p` processes were 0 at every sample, and every hold ended flat.
- **Caveat:** the sampler served 2 stale readings (429 poll throttling). Neither fell on a window
  boundary that changes a number.
- **Weekly meter:** it moved too little to bound anything on its own.

- **What it means.** 0.62 is **above** the 0.5× list-price ratio. Per list dollar, Sonnet costs about
  **1.2×** the plan points Opus does ([0.99, 1.53]).
  - So every vendor `$/task` chart overstates Sonnet's saving in the currency we pay in.
  - Where Opus already wins at matched `$` (coding), it wins by more here.
  - The one place Sonnet buys anything is where it ties on far fewer tokens. On review at low, its
    median output was 4.8K tokens against 36.5K for Opus 5.5 @xhigh, a draw of ≈8% of the
    incumbent's. That is the `sonnet55_review` / `sonnet55_cheap` row.
  - Weekly quota strands on most accounts most weeks (the `claude-accounts` strand nowcast), so that
    saving is usually worth nothing. Hence "only where quota binds".
- **Side measurement.** The 5h:weekly exchange rate was 5.4× (4.5–7.0), not the 4.0× that the
  existing draw math assumes. It is recorded here; that math is not re-derived.

## Measured in our harness

### Review class

- **Corpus:** `tests/fixtures/codex-probe/`, 9 briefs with 36 anchored defects.
- **Harness:** the 09-22 harness copied verbatim (`run-arms.sh` with `--tools ""` and no
  settings/memory; `claude-opus-5 @xhigh` 3-judge blind panel; strict-majority headline). Anchors
  were re-judged in the same panel.
- **Delta:** the only difference is the binary, `~/.claude-284`, because 2.1.280 lacks client-side
  recognition of the id.
- **Files:** [`../sonnet55-effort-sweep-2026-09-28/`](../sonnet55-effort-sweep-2026-09-28/),
  specifically `table.txt`, `paired.txt` and `union.txt`.
- **Positive control:** median output tokens rise with effort: 4.8K → 6.3K → 15.1K → 33.3K → 111K.

### Synthesis-worker class

- **Corpus:** the six frozen briefs and key from `opus55-synth-reprobe-2026-09-22/corpus/`.
- **Snapshot:** rebuilt with `git archive 47c3317eb`. The 09-22 snapshot had been eroded by the /tmp
  cleaner.
- **Arms:** all four ran headless on 2.1.284 with one tool rule (Read plus allowlisted read-only
  Bash; anything else is denied under `-p`).
- **Judges:** blind 4-way. Two Opus 5.5 judges and one Opus 5 judge. The Opus 5 judge saw the same
  score gaps (+1.50 / +1.67 / +2.50 vs +1.50 / +1.58 / +2.42), so own-family preference does not
  explain the result.
- **Files:** [`../sonnet55-synth-probe-2026-09-28/`](../sonnet55-synth-probe-2026-09-28/)
  (`table.md`, `judges/`).
- **A void first run is kept** in `void-run1-briefs-missing/`. The briefs directory had been emptied,
  so every arm answered "no brief". It is recorded rather than deleted.

### Probes

Each probe was re-checked by a skeptic; details are in `notes/probe-*.md`.

| Probe | Finding | Instrument |
|---|---|---|
| Effort binding | With no `--effort`, both 5.5 models send `medium` on 2.1.280 and 2.1.284. Top-level user `effortLevel` is ignored for 5.5 ids (a legacy-list gate in the binary), while `modelSettings.<model>.effortLevel` binds. Agent-tool subagents inherit the lead's effort. Frontmatter `effort` is honoured via `subagent_type` and ignored via `--agent`. Workflow `agent({effort})` is honoured. `between_tools` is reachable only through `CLAUDE_CODE_EXTRA_BODY` + `CLAUDE_CODE_DISABLE_THINKING` (process-wide; not adopted). | a logging reverse proxy on `ANTHROPIC_BASE_URL`, with positive control low→low, xhigh→xhigh |
| Schema'd agents | 0 of 40 Sonnet 5.5 agents at low/medium came back null, schema-failed, wrong or `max_tokens`-stopped (49 of 49 in total). Claude Code demotes forced `tool_choice` to `auto`. | headless 2.1.284 lead running a Workflow |
| Teammates | Sonnet 5.5 holds auto mode as a teammate (discriminating pair). Our hook denies it by policy but **fails open**: 1.9–3.6 s against a 5 s timeout, and 96 + 14 + 10 `hook_cancelled` spawns in 7 days went through. `classifier_model` was stale: the client classifier is `claude-sonnet-5`. | hook run directly; live spawns; proxy |
| Ultracode / trust / 2.1.280 | 2.1.280 **serves** `claude-sonnet-5-5` headless (HTTP 200). The `ultracode` keyword pins no effort on either build. 284 flipped no `hasTrustDialogAccepted` (0 of 749 + 477 projects), which is low power against an intermittent upstream bug. | proxy; `.claude.json` diff |
| Refusals | 1 cyber refusal in 15 security-worded Sonnet 5.5 runs, and 0 in 75 ordinary outputs. All 3 Opus 5.5 controls refused. A mid-stream refusal can end `end_turn` with a declined answer, and `cc-classify`'s text signatures miss the new wording. | real transcripts |
| Quota draw | § Quota | 5h/weekly meter, in-situ A/B |

## Harness changes

All of these adapt the harness to Sonnet 5.5's documented behaviour, or fix what the probes exposed.

- **Landed with this doc:**
  - [`../../../model-config.yaml`](../../../model-config.yaml) § SONNET 5.5, `effort_defaults.sonnet55_*`,
    `pricing_per_mtok`, `classifier_model`, and the upgrade-skill pointer;
  - `migrations/0044-effort-modelsettings-55.sh` (c10, staged for the operator);
  - `docs/activation/pending-activation/47-sonnet55-cc284-activate.sh` (launcher binary 2.1.280 →
    2.1.284, operator-run).
- **Harness wave** (dispatched session, branch `feat/sonnet55-harness`):
  - `mailbox-drain` skips subagent payloads;
  - plan-defaults and teams pointers emit once;
  - the `agent-teams-enforce` hot path is profiled and cut (or a staged timeout migration);
  - effort is pinned on `model: sonnet` agents;
  - `cc-classify` gets the 5.5 refusal wording plus a structural refusal signal;
  - Sonnet-aware account moves;
  - explicit `--effort` on headless re-fires;
  - last-JSON-value parsing in `cc-memory-extract`.
- **Deliberately unchanged:**
  - CC's own per-tool token countdown. The vendor ships it, and no misread was observed on Opus 5.5
    (2 of 18,816 provenance mentions, both correct).
  - `switchModelsOnFlag: false`. A refusal blocks visibly instead of silently downgrading the session
    to Sonnet 5.
  - `auto_mode_allowlist`. No role wants a Sonnet teammate, and an entry would also admit `sonnet` →
    Sonnet 5 on 2.1.280.

## Binary: 2.1.280 → 2.1.284

**ADVANCE.** The Opus 5.5 precedent governs: the ≥7-day churn bar is a proxy for field evidence, and
the gate is the evidence itself. `cc-upgrade-gate` read GREEN 14/0/1 on 2.1.284, both × Sonnet 5.5
and × Opus 5.5, across all four accounts. The only skip is #14 authstore, unchanged since 2.1.220.

The held-open issues are not discharged:

- #84974, #85264, #85015, #84224, #85497 and #85764 are OPEN.
- #85154, #85412 and #85690 were closed as stale, not fixed.

Nothing in 2.1.281–2.1.284 restores a spawn cap, so `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1` and
`DISABLE_AUTOUPDATER=1` stay.

Cautions carried:

- the `sonnet` alias changes meaning (284 L5);
- ultracode no longer forces xhigh (284 L67; measured: it never pinned effort for us);
- `rm -rf "$(…)"` now asks, then denies after 2 min (281 L327/L430). Ban it by name in subagent
  briefs;
- open #97888 (trust flag reverting);
- #97763 (subagent `output_tokens` undercount: re-derive usage from `modelUsage`, not subagent
  JSONL);
- #97687 (an Opus subagent silently falls back to opus-4-8 after a cyber refusal).

The MANIFEST rows for 2.1.281–2.1.284 are `skip` for the legacy `claude-prev` lane. The fleet pin
moves through activation 47.

## Skills

**Consolidated. The router is landed and live at `skills/cc-upgrade/`**
(f87d661e4 167396653 e497b250c e5a83f809):

- The router `SKILL.md` routes by trigger (model / harness / both) to lane files: `audit.md`,
  `holds.md`, `gate.md`, `model.md`, `keying.md`, `utilize.md`, `feature.md`.
- The three old names are one-cycle `disable-model-invocation` stubs that forward to it.
- `bin/cc-model-registered` turns the binary gate into code: an mmap byte scan with a positive
  control, exit 0 / 1 / 2.

The reasoning is in [`notes/skills-consolidation.md`](notes/skills-consolidation.md):

1. **A model release has been a binary event four times running.** "New model" usually means
   "both".
2. **The three skills disagreed on their running order.**
3. **They all loaded at once**: about 13.8K tokens of bodies and 732 characters of listing.
4. **Compaction cut the largest one mid-Case-B.**

The gate now also runs once per model the fleet will run on the candidate, not once per release.
This run is the example: Sonnet 5.5 is not the lead model, so a single gate run would never have
tested the Opus 5.5 lead on 2.1.284.

Auto-load probe: 4 of 6 phrasings invoked it. It missed "which model at which effort now" and
"frontier access lapsed" ([`../cc-upgrade-skill-2026-09-28.md`](../cc-upgrade-skill-2026-09-28.md)).
Those two phrasings belong more to `frontier-routing` and to this table than to an upgrade, so the
description is left as it is.

## What the sources do not state

No key may claim any of the following:

- the plan-quota draw of Sonnet 5.5 relative to Opus 5.5 (measured here instead, § Quota);
- a Haiku comparator on any capability benchmark;
- Sonnet 5.5 on long unattended runs at a labelled effort;
- whether Sonnet 5.5's refusal fallback is sticky for a whole Claude Code session with
  `switchModelsOnFlag: true` (the card says session-scoped; no refusal occurred in our two `true`
  runs to observe it).
