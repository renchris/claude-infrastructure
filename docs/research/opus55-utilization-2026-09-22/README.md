# Opus 5.5 — which model, at which effort, for which use case (2026-09-22)

**Answer.** Opus 5.5 is the default for every class of work this fleet runs, except two slots that
stay as they are for now: codebase retrieval (Explore, Haiku 4.5) and the bulk Workflow synthesis
worker (Sonnet 5 @max, pending a re-probe). The effort rung is not one number, because Opus 5.5's
effort curve has a different shape per task class:
- **medium** for scoped coding (its peak);
- **high** for leads, agentic work and research;
- **xhigh** for hard reasoning and long-horizon knowledge work;
- **low** only for gate-verified bulk work, never for research or reasoning.

**max** buys little over xhigh: usually 1–2 points at up to ~2× the output. The exception is
derivation-heavy math (ArXivMath +5.2); on Terminal-Bench 4.0 max scores below xhigh. On our own
review sweep max was unfit: it lost 2 of 9 cells to the output cap. Fable 5.1 stays as the
escalation tier. Of the four judge slots it held, our review sweep moved the two Workflow judges to
Opus 5.5 @xhigh (parity at ~0.4× the quota). The adversarial and review-gate slots stay on Fable,
because they run at the lead's effort and exist to catch what the Opus 5.5 worker misses.

**The rungs are ADVISORY: no code reads them yet.** The policy lives in `model-config.yaml` →
`effort_defaults.opus55_*`. Code reads only `effort_defaults.default` (high), `verify_judge` and
`settings_floor`, and of the roles only `roles.lead_default`. A session applies a rung by hand —
`--effort` on a fire, `/effort` on a lead, `effort:` on a Workflow `agent()` — see "Applying the
rungs in this harness". This document is the evidence for all of them.

## Sources and method

- **Operator-supplied (primary):**
  - [announcement](https://www.anthropic.com/claude-opus-5-5)
  - [Prompting Claude Opus 5.5](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5)
  - [System Card, 230 pp.](https://www-cdn.anthropic.com/fc1b44717c85dc068bc6ba5024219938094694bd/Claude%20Opus%205.5%20System%20Card.pdf)
- **Linked from the prompting guide (secondary):** effort, what's new, migration guide, models
  overview.
- **Method:**
  - Nine readers extracted page-cited facts; a second reader re-checked each one at its cited page.
    A reader's facts counted as unconfirmed until that check.
  - A completeness critic then raised three gaps, and each got a targeted re-read.
  - Result: **620 facts** → [`facts.json`](facts.json). Of the 462 the readers extracted, 454 were
    confirmed, 8 corrected and 0 unsupported; the verifiers added 158 the readers had missed.
  - Readers' notes are in [`notes/`](notes/); the repo census is in [`census/`](census/).
- **Units.** Every $ figure below is $list, read off the vendor's charts: per task, except per
  attempt for Terminal-Bench 4.0 and WANDR and estimated for GDPval-AA. The source is the System
  Card, or the announcement where the card only gives xhigh/max (Terminal-Bench 4.0, GDPval-AA,
  WANDR costs). This fleet is not billed in dollars (see "Currency").

## The table

Conviction is the author's number for "this is the right default today". Under the repo's F2 rule,
anything below 90% is research still owed; the last column says what would move it.

| Use case (our surface) | Model | Effort | Slack rung¹ | Evidence (vendor charts; "ann." = announcement) | Conv. | Moves it |
|---|---|---|---|---|---|---|
| Lead / orchestrator; fired wave lead | Opus 5.5 | **high** | xhigh on decision-heavy stretches | CursorBench 4.0: med 52.5 · high 56.0 (~$4) · xhigh 56.0 · max 57.8 (~$13). Terminal-Bench 4.0 (ann., $/attempt): med 57.6 · high 64.2 ($3.88) · xhigh 66.4 ($7.35) · max 64.8 | 85% | a lead-class probe |
| Long unattended implementation run | Opus 5.5 | **high** | xhigh when the work is novel | TB4 peaks at xhigh (+2.2 over high on the ann. chart, inside ±2.6 SE). FrontierSWE (~20 h/task, max): Opus 5.5 62.3 vs Fable 5.1 56.3. Effort docs (generic): xhigh for >30-min agentic work | 75% | a long-run A/B |
| Scoped coding wave (anchored briefs) | Opus 5.5 | **medium** — fire the wave's session with `--effort medium`; its teammates inherit it | none, medium is the peak | FrontierCode v1.1 (Cognition, run in Claude Code, graded on mergeability incl. scope): Main med 54.6 · high 54.0 · xhigh 51.4 · max 54.4 at ~9× medium's output tokens; Extended med 65.3 · max 63.6. A teammate spawned inside a `high` lead runs at high (54.0, within noise, ~1.4× the output) | 85% | — |
| Code-writing teammate, ambiguous multi-file | Opus 5.5 | **high** (the lead's) | max, only if measured | CursorBench: med 52.5 → high 56.0 | 80% | — |
| Mechanical, known-target edit | Opus 5.5 | **medium** (low only behind a gate) | none | FrontierCode low 47.3 vs med 54.6; CursorBench low 43.7 ≈ Opus 5 @medium at ~1/6 the cost | 75% | — |
| Code review / bug finding | Opus 5.5 (the `teammate_frontier` review-gate slot stays on Fable 5.1: it runs at the lead's effort, where Fable recalled 10 v 8) | **high** | xhigh | **Our review sweep** (recall /36, one sample, no pair distinguishable): low 6 · medium 8 · high 8 · xhigh 10 · max 9, and max is unfit (2/9 cells hit the output cap after 512K tokens). High costs ≈0.4× xhigh's quota. Guide: more bugs, fewer false alarms than Opus 5. Customer (Deloitte): at low, 72% of known bugs vs Opus 5 @high 56% | 80% | the repeated-sample follow-up (in flight) |
| Bounded verifier ("does p. X say Y") | Opus 5.5 | **high** | xhigh | This fact base: Opus 5.5 @high verifiers re-checked 462 claims at their cited pages, corrected 8 and added 158 missed ones. Its self-preference bias is +0.01 / +0.07 on a 10-pt scale. Our review sweep: xhigh ties Fable 5.1 @high (10 v 10) at ~0.4× its quota | 80% | the repeated-sample follow-up |
| Judge of HARD reasoning (derivation, architecture, proofs) | Opus 5.5 @xhigh, including the `workflow_judge` / `eval_judge` slots since 2026-09-22. **Fable 5.1 held** in `research_adversarial` and in `cc-route`'s judgment-dense and adversarial wave slots (see "Where Fable 5.1 still fits") | **xhigh** | max for math-like work | ArXivMath no tools: high 73.2 · xhigh 86.0 · max 91.2; with tools: high 79.4 · xhigh 94.7 · max 96.9. At **high** Opus 5.5 is BELOW both comparators here (with tools: Fable 87.7, Opus 5 88.6) and retakes the lead only at xhigh (94.7 vs 93.0). HLE no tools: high 59.6 · xhigh 62.8. **Our review sweep:** xhigh 10 = Fable 5.1 @high 10 (3 v 3 discordant items) at ~0.4× its quota | 85% | the repeated-sample follow-up: Opus 5 @max scored 13 in two panels, both judged by Opus 5 only |
| Breadth research worker (web) | Opus 5.5 | **high** | xhigh | WANDR (ann., $/attempt): med 62.8 · high 67.3 (≈ Opus 5 @xhigh 67.0 at ~1/3 its cost) · xhigh 71.3 · max 72.3; **low 31.2**. HLE with tools: med 63.0 · high 63.9 · xhigh 66.4 | 85% | — |
| Deep research / report synthesis | Opus 5.5 | **high** | xhigh | DRACO (n=100): med 83.9 · high 85.0 · xhigh 86.7 · max 87.4 — high→xhigh is +1.7 at ~2.5× the cost. Opus 5 LEADS at every rung from medium up (85.6 · 87.3 · 87.4 · 88.3), and Opus 5 @high (87.3, ~$8.5) beats Opus 5.5 @xhigh (86.7, ~$9) | 65% | a deep-research A/B: Opus 5.5 @high vs Opus 5 @high |
| Long-horizon knowledge work (analysis, docs, spreadsheets) | Opus 5.5 | **xhigh** | max | GDPval-AA (high from the ann. chart): high 1692 · xhigh 1820 · max 1846 (xhigh ≈ max on ~51% fewer output tokens). AA-Briefcase: high 1705 · xhigh 1780 · max 1822 | 80% | — |
| Chart and screenshot reading, UI verification | Opus 5.5 | **medium** (low only WITHOUT tools) | none | Chartography no tools: ~57 at the cheapest point → 64.4 at max; guide: without tools even low beats Opus 5 at its highest. With tools, our normal case: ~71.5 at the cheapest point vs 85.2 at the next, below Opus 5's best (83.4); guide: the model uses its tools "more effectively at higher effort levels" | 70% | — |
| Computer use / browser driving | Opus 5.5 | **medium** | xhigh | OSWorld 2.0 partial ~58 → 74 → 78 → 81 → 82 over five unlabelled points | 65% | — |
| Security review of OUR source code | Opus 5.5 (a `teammate_frontier` review-gate slot stays on Fable 5.1 until the sweep) | **xhigh** | — | Vulnerability discovery in source code is allowed. Defensive-traffic flag rate 4.5% (Opus 5 13.9%). Cyber-classifier hits fall back to Opus 4.8 | 75% | — |
| Codebase retrieval (Explore) | Haiku 4.5, **only if the spawn passes `model: "haiku"`**. An unpinned Explore runs the LEAD's model, capped at opus. Measured 2026-09-22 on 2.1.280 under an Opus 5.5 lead: unpinned → `claude-opus-5-5` on every turn; `model: "haiku"` → `claude-haiku-4-5-20251001`. Both answered an exact file:line lookup correctly | n/a (no effort param) | — | No Haiku-vs-Opus 5.5 quality data beyond that lookup; bounded file:line retrieval is quality-saturated. Haiku 4.5's floor is **2026-10-15**; Haiku 5.5 is announced for "the coming weeks" | 85% | stage Haiku 5.5 on release |
| Bulk Workflow synthesis worker | Sonnet 5 @max, unchanged for now | — | — | Certified vs **Opus 4.8** only. Every Sonnet 5 capability row in the card sits below Opus 5.5 except Toolathlon Pass@3 (84.3 vs 82.4, p.211), and Sonnet's win needs max, the output-heaviest rung. **Our re-probe, run 1 (confounded by unequal tools):** Opus 5.5 @xhigh beat Sonnet 3–1 on judged pairs, with about half the wrong claims | 65% that Opus 5.5 @xhigh ≥ Sonnet at equal tools | the equal-tools settle run (in flight; Open item 3) |
| Frontier escalation (ladder, `/frontier-run`) | Fable 5.1 | `fable51_*` | — | See next section | — | — |

¹ **Slack rung** is what "maximal utilization" means here. Weekly plan quota does not roll over. When
an account's week is forecast to strand (`claude-accounts` strand nowcast), move the classes that
keep paying one rung up. Never raise scoped coding (medium is its peak) or chart and screenshot
reading (flat); computer use keeps paying (OSWorld) and may go to xhigh. When quota binds, hold the
defaults and never drop research or reasoning to low.

## Where Fable 5.1 still fits

- **At matched effort, Opus 5.5 is at or above Fable 5.1 on most evaluations in the card, at a
  fraction of the cost.** Fable leads in four situations:
  - At **low effort**, at ~4–25× the cost: TB4 ~4.4×, CursorBench ~4.6×, GDPval ~6.7×, HLE ~7×,
    DRACO ~16×, WANDR ~19×, ArXivMath 13–25×; FrontierCode reports tokens only (~2× the output).
    Low-vs-low scores: FrontierCode 52.8 vs 47.3, WANDR 63.3 vs 31.2, DRACO 84.2 vs 72.5.
  - **Deep research (DRACO)**, from medium up by at most 1.8 points on 100 tasks: medium 85.7 vs
    83.9, high 86.5 vs 85.0, xhigh 86.9 vs 86.7, max 87.7 vs 87.4. Fable costs more at each rung.
  - **Derivation-heavy math (ArXivMath) and web breadth (WANDR) at medium and high.** ArXivMath
    with tools: medium 75.9 vs 67.1, high 87.7 vs 79.4; without tools: medium 67.1 vs 64.0, high
    tied at 73.2. WANDR medium 64.5 vs 62.8. Opus 5.5 leads from xhigh up (with tools 94.7 vs
    93.0), which is why hard reasoning runs at xhigh.
  - **Small or tied gaps:** OfficeQA 80.2 vs 78.9; Toolathlon tied at 77.8.
- **Where Fable is clearly worse:** 24-hour Lean formalization, at every team size (Fable 5.1
  0.16 → 0.53 vs Opus 5.5 0.39 → 0.68), and every coding and agentic-terminal chart above low.
- **Not in the card:** Fable 5.1's self-preference bias. The +0.17 / +0.10 in that figure is
  Mythos 5.1, and the card runs no alignment evaluation on Fable 5.1.
- **The vendor still says** to use Fable 5.1 "for demanding reasoning and long-horizon agentic
  work, or when Opus 5.5 at higher effort still falls short on your evals" (Models overview).
- **So Fable is an escalation, not a tier above the default.** What it buys now is a *different
  model's* blind spots. That matches the frontier ladder's T-a condition: still below 90%
  conviction after exhaustive research.
- **Judge slots — decided by our review sweep, 2026-09-22**
  ([`../opus55-effort-sweep-2026-09-22/`](../opus55-effort-sweep-2026-09-22/README.md): the same
  corpus and the same Opus 5 judge panel as the Fable 5.1 sweep; recall /36; one sample; no pair
  distinguishable). What decided each slot is the effort it can actually run at, and whether its
  job is to catch what the Opus 5.5 worker misses.
  - **`workflow_judge` and `eval_judge` moved to Opus 5.5 @xhigh (90%).** A Workflow `agent()`
    pins its own effort. At xhigh Opus 5.5 ties Fable 5.1 @high 10 v 10, with 3 discordant items
    each way, at ~0.4× the quota. The move also takes these slots off Fable's sub-cap.
  - **`research_adversarial` and `teammate_frontier` stay on Fable 5.1 (90%).** Both run at the
    LEAD's effort: in-process spawns and teammate panes inherit it. At high, Opus 5.5 recalls 8 to
    Fable's 10 (1 v 3 discordant). Both slots exist to catch what the Opus 5.5 @high worker misses,
    and the same model at the same effort is redundancy by construction.
  - **`cc-route`'s wave slots still route to Fable 5.1** (`frontier_access.model` @xhigh). The
    adversarial wave is a different-model check, like `research_adversarial`. The judgment-dense
    wave does the hard work itself. Our evals don't cover that class, and the vendor names Fable
    5.1 for "demanding reasoning", so it stays. Conviction that Opus 5.5 @xhigh would match it:
    85%. Only a judgment-dense probe would move that, and the payoff would be quota, not quality.
  - **Open, and measured on one sample only.**
    - Opus 5 @max was the best arm in two panels (12, 13). Every panel was Opus 5 judges, so an
      own-model lean is not excluded.
    - Opus 5 @high complements the Opus 5.5 worker exactly as much as Fable 5.1 @high does: each
      adds 3 items, union 11 either way. It does so at roughly a third of the quota.
    - A repeated-sample follow-up with a mixed-model panel decides both.
    (`docs/research/review-judge-followup-2026-09-22/`, in flight).

## Multi-agent economics (System Card §8.12)

- **Teams buy time, not a higher ceiling (ProgramBench).**
  - A pre-spawned 5-agent team reached score 0.6 about **2.7× sooner** than a single agent.
  - It spent ~2× the tokens. On-demand async subagents spent ~4–8×, the least token-efficient
    configuration tested.
  - That async setup is the shape of our in-process subagents and Workflow slots.
  - All three configurations converge near 0.95–0.97.
- **Research (DRACO) is the exception.** Unpressured teams scored ~2.5 higher than one agent, but
  finished slower.
- **To finish sooner, give a time budget; don't lower effort.** With `elapsed 340s / 1200s`
  appended to each turn, a 5-agent team at 0.5× the single agent's latency matched its quality
  about 2.8× faster. Lower effort does less work; a budget keeps more agents working in parallel.
  Under tight budgets, async leads collapse to a single agent, while fixed rosters stay parallel.
- **Team size is a wall-clock lever.** Going from 1 to 10 agents is the big quality step: +0.17 on
  the knowledge-base task, +0.27 on Lean. Going from 10 to 100 adds +0.02–0.04 but reaches it hours
  earlier.
- **Caveats.** All multi-agent runs used max effort. Latency is derived from token counts at fixed
  rates, not wall-clock, so rate-limited accounts will see smaller speedups.

## Currency: what binds, and what nobody has measured

- **The binding resource is weekly plan quota.** The fleet has no dollar exposure, and the meter
  does not follow list price. Cache reads draw ≈0 against it; output tokens and cache creation
  drive it (`census/L2b-quota-effort-method.md`).
- **The vendor's "40% less than Opus 5" is list dollars at each model's DEFAULT effort** (medium
  vs high). Much of it comes from cache reads, which cost us ~nothing, so a fleet that pins effort
  explicitly will not see the full 40%.
- **Output tokens are what we pay in.** Per FrontierCode task at matched effort, Opus 5.5 spends
  0.41–0.55× of Opus 5's output from low through high, 0.90× at xhigh and **1.68× at max**. Per
  TURN the guide points the other way, at every level: "At a given level, Claude Opus 5.5 tends to
  think more per turn than Claude Opus 5, especially at xhigh and max." Fewer turns per task can
  reconcile the two, so neither settles our draw at a pinned `high`. The meter read below does.
- **Opus 5.5's plan-quota draw per token is not stated by any source. We measured it on
  2026-09-22: ≈1.1× Opus 5, bounded [0.78, 1.72].** The review sweep read account `next4`'s meters
  around a single-model interval, against an in-situ Opus 5 control
  ([`../opus55-effort-sweep-2026-09-22/`](../opus55-effort-sweep-2026-09-22/README.md) § Quota
  draw per token). That bound EXCLUDES a Fable-like draw (3.2–3.7×), so Opus 5.5 is an Opus-class
  spend. It CANNOT tell 1.0 from the 0.8 list ratio, and the weekly meter alone resolves nothing
  at that volume. So, per task, what we save is output TOKENS (above), not a cheaper token.

## Applying the rungs in this harness

| Surface | How its effort is set | Status |
|---|---|---|
| Shell-launched lead | `~/.zshrc` `claude()` passes `--effort high` | ✅ matches `opus55_default` |
| Mid-session change | `/effort <level>`. Opus 5.5's tier carries `per_turn_effort` in 2.1.280, and one observed switch kept the prompt cache (129,652 tokens read, 6,564 written) | ✅ cheap on 5.5; on Opus 5 it re-wrote the cache |
| Waves planned by `cc-wave-plan` | `cc-route` → `effort_defaults.default` (high) | ✅ for wave leads. A scoped-coding or xhigh-class wave needs its `--effort` passed by hand, because nothing picks an `opus55_*` rung per slot |
| `/handoff` fires and `--recycle` (`handoff-fire.sh`) | the caller's `--effort` if passed, else the typed launcher's zshrc default (`CLAUDE_EFFORT`, high); no SSOT key is read | ✅, and pass `--effort medium` / `xhigh` to fire a wave at another rung |
| Teammate panes | the LEAD's live effort, as a CLI flag: 2.1.280's pane builder pushes `--effort <lead's level>` onto every teammate command line (read off the binary), outranking both the worktree `settings.local.json` that `scripts/set-teammate-effort.sh` writes and the config dir's `effortLevel` | ⚠️ `set-teammate-effort.sh` has no effect on 2.1.280 (and since 2026-09-22 the script says so on stderr instead of claiming the file binds). Per-teammate effort therefore means a per-WAVE session fired at that rung |
| Any xhigh/max session or slot | `CLAUDE_CODE_MAX_OUTPUT_TOKENS` (unset here) | ✅ measured 2026-09-22: with it unset, the client reports `maxOutputTokens: 128000` for claude-opus-5-5, the model maximum the guide recommends. A harness that caps output lower (the 09-10 sweep used 64000, and Fable 5.1 lost xhigh/max cells to it) must raise it: high→xhigh is ~2.3× the output on 5.5 |
| In-process subagents | inherit the lead's live effort (GH #25591) | ✅ high under a high lead |
| Workflow `agent()` | per-call `effort:` | ⚠️ always pass it; omitted = unmeasured on 2.1.280 |
| Hand-pinned model ids | use the alias `opus` | while any 2.1.260 session lives, a full `claude-opus-5-5` pin 400s there |

## Supervision changes that come with it (System Card §6; vs Opus 5)

- **Unattended runs are safer.**
  - Fewer destructive actions: 21% vs 42%.
  - More ask-instead-of-act: 35% vs 26%.
  - Fewer false completion claims: 1.14 vs 1.56.
  - Expect it to stop and ask more often.
- **Weaker points:**
  - It acts on instructions inside **user-pasted** text more often: 2.1% at default effort, 7.4%
    at max, 0% with pasted text marked. Our fire briefs arrive as user text, so wrap quoted
    untrusted content in `<pasted_content>` tags.
  - On impossible tasks it has the highest *successful* reward-hack rate of the three models:
    3.1% vs 1.9%.
  - One observed test-gaming case hid UI with `display:none !important`.
- **Early stops.** The guide says a text-only end of turn is a progress report, not completion,
  and recommends 2–3 automatic continuations, then stop. Our session-continue arms are unbounded
  by design. This is a harness question, noted here, not decided here.
- **Safeguard fallback changes which model answers a turn.**
  - Cyber → Opus 4.8; bio and frontier-LLM R&D → Opus 5.
  - Benign agentic benchmarks: 2.5% of requests fell back on Terminal-Bench 4.0 and 3.9% on
    Terminal-Bench-Science.
  - Adversarial coding-injection tests: 46% of rollouts (Gray Swan) and 64% of requests (Shade
    adaptive coding) went to Opus 4.8.
  - In Shade, every successful attack came through those fallback turns (0 of 2,872 answered
    directly). In Gray Swan, none of the 1,310 fallback rollouts was successfully attacked.

## Not stated by the sources — measure, don't assume

- Plan-quota draw per token. We measured it instead: ≈1.1× Opus 5, bounded [0.78, 1.72] (see
  "Currency").
- Claude Code's own default effort for Opus 5.5 (only the API default, medium, is stated).
- Long-context degradation curves.
- Mixed-model or below-max-effort agent teams.
- Per-effort rates for most alignment metrics.
- An Opus 5 retirement date. The Models overview lists Opus 5 among current models and gives no
  lifecycle row; the staging note's "LEGACY" is not supported by these sources.

## Open items

1. ✅ **Review-class effort sweep + quota-draw read — DONE 2026-09-22** (landed `501e4490e`,
   [`../opus55-effort-sweep-2026-09-22/`](../opus55-effort-sweep-2026-09-22/README.md)). It
   decided the four Fable-held slots (see "Judge slots"), fed the review and verifier rows, and
   measured the draw (see "Currency").
2. ✅ **reso team-brief pins — DONE 2026-09-22 (reso 80f481be4).** 62 member pins in 40 files now
   read `model: opus`, which each lead's binary resolves. `claude-bump-models --apply` was
   deliberately not run: it would have written the full id where 2.1.260 leads read it. The team
   brief schema's `model:` comment was the last full-id pin. It now names the alias and the
   allowlist key (reso `d86ac7610`), which leaves `claude-lint-models.sh --all` with nothing to flag.
3. **Freewin re-probe for the Sonnet 5 synthesis slot**, with Opus 5.5 as the comparator.
   - **Run 1 — INCONCLUSIVE** (landed `d5383f12c`,
     [`../opus55-synth-reprobe-2026-09-22/`](../opus55-synth-reprobe-2026-09-22/README.md)). The
     cause was a tool confound, not noise. Workflow subagents on 2.1.280 have no Grep or Glob, so
     Sonnet 5 @max searched with read-only Bash while Opus 5.5 obeyed the brief and used Read only.
   - What held despite that, on 6 HARD briefs with 3 blind judges:
     - Opus 5.5 @xhigh beat Sonnet 5 @max 3–1 (1 tie, 1 no majority); Opus 5.5 @high tied 3–3.
     - Sonnet made about 2× the wrong claims (55 vs 25 at xhigh, 29 at high).
     - Sonnet's key-recall lead (88.5% vs 83.1%) sits on the find-every-site brief, exactly where
       grep pays.
   - Directional conviction: 65% that xhigh ≥ Sonnet at equal tools; 50% for high.
   - **Settle run IN FLIGHT** on branch `feat/synth-settle-run`. It is the same corpus and judges
     with one change: every arm gets Read plus read-only Bash.
   - `roles.workflow_synthesis_worker` stays Sonnet 5 @max until the settle run reports.
4. **Settings effort drift** (`next`, `next4` at low). It reaches only non-wrapped surfaces (IDE,
   bare `claude -p`), never a teammate on 2.1.280. It is an authority-ceiling surface, realigned by
   the operator via migration.
5. **Stage Sonnet 5.5 / Haiku 5.5 on release**, through the `/model-upgrade` Step 0 binary gate.
6. ✅ **`scripts/set-teammate-effort.sh`'s premise is false on 2.1.280 — CORRECTED 2026-09-22.**
   The lead's `--effort` CLI flag outranks the settings file it writes, so it no longer sets a
   teammate's effort. The script now warns and names the lever that does work: fire the wave's
   own session at the rung. The two SSOT comments that presented it as the per-member lever carry
   the same dated correction.
7. **Review-class follow-up** — repeated samples and a mixed-model judge panel, IN FLIGHT on
   branch `feat/review-judge-followup`. It asks two questions.
   - Q1: is Opus 5 @max genuinely the best judge config (13 v 10, one sample, Opus-5 judges)?
   - Q2: is Opus 5 @high a better adversarial complement to the Opus 5.5 worker than Fable 5.1?
   Either answer can move `workflow_judge` / `eval_judge` / `research_adversarial` again.
