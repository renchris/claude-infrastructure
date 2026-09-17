# Model routing decision — Fable 5.1 as default vs Opus 5 @ high

**Date:** 2026-09-16 · **Synthesis of:** 7 evidence axes + 4 adversarial skeptics
**Question (operator, verbatim):** *"It seems like Fable 5.1 on lower reasoning efforts covers
intelligence AND cost against Opus 5 at higher reasoning efforts. Is there any reason to keep Opus 5
high as our starting model? Should we update our SSOT model orchestration any differently than it is
now? ex. /model-upgrade"*

---

## 1. THE ANSWER

**Yes — keep `claude-opus-5 @ high` as the default, and the reason is not intelligence, it is
capacity arithmetic.** Fable is not a separate budget. It is a **sub-cap of the same weekly bucket,
hard-bounded at 50%** (`accounts.json frontier.coupling = 0.5`, verified by me this session), and it
draws that shared bucket **~3.2–3.7× faster per token** than Opus 5. So a week spent entirely on
Fable ends at `fable 100 / weekly 50` and locks out with **half the fleet's weekly capacity
unspendable**. That is true at *any* quality level, which means Fable 5.1 is arithmetically
disqualified as a DEFAULT before the intelligence question is even reached.

**Conviction: 93%.** Above the operator's 90% threshold, so this is implemented, not asked.

**But the operator's instinct is pointing at something real, and it is on the effort axis.** At
*matched* effort rung Fable 5.1 does appear modestly more capable than Opus 5 — consistently, across
two independent instrument families. What fails is the *cross-rung* step (Fable at a LOWER rung
covering Opus at a HIGHER rung), which is the specific claim the premise makes. And the genuinely
actionable finding underneath all of this is that **the configuration we are arguing about is not
uniformly deployed**: `effort-parity-assert.sh` is RED on **4 of 5 config dirs** right now.

---

## 2. THE PREMISE, ADJUDICATED IN THREE PARTS

The premise — *"Fable 5.1 at lower effort covers intelligence AND cost vs Opus 5 at higher effort"* —
contains three separable claims. They resolve differently.

### 2a. INTELLIGENCE — partly supported, but not in the form the premise needs

**At MATCHED rung, Fable 5.1 leads. This is the strongest pro-Fable finding in the dossier and it is
stronger than the operator stated it.**

CursorBench 4.0, matched label both sides (QUOTED, vendor-adjacent; transcription verified by two
independent fetches and by the A1 skeptic's own re-fetch):

| rung | Fable 5.1 | Opus 5 | Δ score | Δ cost (list $) |
|---|---|---|---|---|
| Low | 45.1% | 40.7% | **+4.4** | +12% |
| Medium | 46.8% | 43.3% | **+3.5** | +1.6% |
| High | 49.2% | 44.7% | **+4.5** | +0.9% |
| xHigh | 51.6% | 46.1% | **+5.5** | +14% |
| Max | 51.8% | 46.6% | **+5.2** | +45% |

Anthropic's own system card corroborates from a different instrument — matched **medium** across five
effort-resolved charts (pixel-measured by A2, independently re-read by its skeptic, positive-controlled
against printed score labels): CursorBench +3.7, HLE[tools] +2.2, HLE[no-tools] +2.0, FrontierCode dead
tie, DRACO tie. **Fable ahead on 3, tied on 2, behind on 0.**

**A synthesis observation neither agent computed:** the CursorBench ordering is 5-for-5 in the same
direction. Under a true null that is P = 1/32 ≈ 0.031. The rungs are *not* independent (same tasks,
same model family, correlated harness), so treat that as an upper bound on the evidence — but the
*consistency* is worth more than any single cell, and it is what survives the absence of confidence
intervals. Two independent instrument families agreeing on direction at matched rung is real signal.

**What fails is the cross-rung step — and that is precisely the operator's claim.** The A2 skeptic
computed Fable @low vs Opus @high across all five card charts: **−0.5 (CursorBench), +3.1
(FrontierCode), −2.7 (HLE tools), −2.3 (HLE no-tools), −2.9 (DRACO)** — the claim **fails on four of
five at low**. At medium it splits: wins CursorBench (+1.3), ties both HLE charts (+0.2 / +0.4, against
an HLE SE of ~1.4pp at n=2,500), loses DRACO (−2.2). The one clean win, FrontierCode, is confounded:
Opus 5 @medium (63.62) *ties* Fable @medium (63.58), so that chart is a statement about Opus's own
non-monotonicity, not about model choice.

**What the vendor itself prescribes — never quoted by the axis that had it open:**
> *"For most workloads, start with Claude Opus 5. Use Claude Fable 5.1 for demanding reasoning and
> long-horizon agentic work, or when your evals on Claude Opus 5 at higher effort still fall short."*
> — `whats-new-fable-5-1`, opening paragraph
> *"Tuning effort is often a better lever than switching models. On Claude Fable 5.1 and Claude Opus 5,
> start with the default (high) and adjust up or down based on your evals."* — `choosing-a-model`

So `claude-opus-5 @high` is **not** an unvalidated local choice. It is Opus 5's own documented default
and Anthropic's prescribed starting point, and the vendor's prescribed order is the **opposite** of the
proposal: raise Opus 5's effort first; switch model only if xhigh/max still falls short.

**What our own measurement can and cannot establish.** The 2026-09-10 sweep (MEASURED, ours, 45 cells,
~$182) reported Opus 5 @max 12/36 against best-Fable 10/36. The A4 skeptic **confirmed the direction
and destroyed the significance**: paired over 25 defects the discordant split is 4–2, exact sign test
**p = 0.6875**; at brief level 2W/0L/3T, p = 0.50; vote-level permutation p = 0.53. The design's
prospective power at the effect it was read as showing is ~13–25%. Root cause: **21 of 36 ground-truth
defects were found by no arm at all**, so most cells are uninformative 0–0 ties.
It **can** establish: Opus 5 @max is not *worse* than Fable 5.1 on anchored single-file review, and
effort above medium buys no recall on Fable 5.1 for that class.
It **cannot** establish: that Opus wins; that any arm ties (the fleet's own lexicographic rule requires
a ≥3-judge panel to *call* a tie, and no judge was ever asked); or anything about our actual default —
**the Opus arm ran @max, cross-run from 2026-08-11, and no `o5@high` arm label exists anywhere in
`docs/research/`** (I grepped it myself).
And its isolation recipe — `--tools ""`, `--setting-sources ""`, `num_turns=1`, neutral cwd — deliberately
excludes the single most distinctive property of this fleet's real workload: a ~94KB always-resident
instruction set plus a large hook chain. **Nobody, vendor or us, has measured either model under that.**

**Intelligence verdict: Fable 5.1 is probably modestly better per effort label; the cross-rung claim
is not supported; and at our actual configuration the comparison has never been run.**

### 2b. DOLLAR COST — refuted at matched rung; parity on our own profile with an undetermined sign

The operator's cost intuition comes from Fable 5.1's cache-read price cut ($0.25/MTok vs Opus 5's
$0.50/MTok — 0.025× base input vs 0.1×), which is genuinely the dominant input line on a long agentic
turn. It is a real effect and the 2× sticker really is misleading.

But **at matched rung Opus 5 is cheaper on 5 of 5 CursorBench rungs and on 4 of 5 system-card charts.**
Every "dominance" cell in the operator's reading is produced by taking a *lower* rung for Fable and a
*higher* rung for Opus. A1 originally read this as an inversion of the 3.2-era cost ordering; its
skeptic refuted that — the ratio **narrowed (1.61× → 1.45× at max), it did not invert**.

On our **own** token profile the answer is parity, and the sign is genuinely undetermined:
- A4 (MEASURED, 25% fixed-seed census of all four config dirs): Opus $0.1607/turn vs Fable $0.1523 =
  Fable 5% cheaper.
- Its skeptic corrected the **cache-write TTL multiplier** — 60.7% of this fleet's `opus-5@high` cache
  writes are `ephemeral_1h`, billed at **2× base input, not the 1.25× five-minute rate** — flipping it
  to **Opus 1–6% cheaper** in all three dedupe/sample variants. This is the **sixth** instance of that
  exact error in this repo (`usage-telemetry-100p-2026-08-16/critic.md:39` names five priors).
- But the 1h share has itself moved **99.7% → 85.1% → 60.7% in one month**, and the crossover sits at
  ~50%. A verdict whose sign turns on a fleet-configuration variable that has moved 40 points in a
  month is not a verdict.

**Dollar verdict: parity, ±6%, sign undetermined. And it is irrelevant** — `accounts.json`
`spend.usage_credits_authorized = false` and `frontier.credits_authorized = false` (verified). The
fleet has **zero dollar exposure**. Every dollar chart in the launch post, the system card and
CursorBench is about an economy we are not billed in.

### 2c. QUOTA COST — refuted decisively. This is the whole answer.

The only scarce resource is **4 × 100 weekly percentage points**. Three independent findings, each
verified:

**(i) Fable is a SUB-CAP of the same bucket, not a separate one.** MEASURED: 28,572 samples across 4
accounts, **0 violations** of the 0.5 coupling — and the skeptic checked that violations were
*expressible* (7,940 rows carry `fable > 0` with `weekly < 49`, where a violation is arithmetically
possible), with 618 rows sitting hard against the boundary. Config truth: `accounts.json
frontier.coupling = 0.5`, commented *"fable_cap/weekly_cap per SSOT ≤50% of weekly usage limits"*
(I read it). Vendor confirms: *"You can use up to 50% of your weekly usage limits on Fable models"* ·
*"They draw from your plan's regular weekly usage limits and use them **faster** than other Claude
models."*

**(ii) The exchange rate is ~3.2–3.7× per token, not the ~2× the launcher warns about.** A3 measured
2.5–2.8×; its skeptic found the census had **no `message.id` dedup** (Claude Code writes one transcript
line per content block, each carrying the identical complete usage object) and the inflation is
**model-dependent** — Fable output inflated 6.21× vs Opus's 3.41× on the same corpus — so it does not
cancel in a ratio, and it biased in the direction that made Fable look cheaper. Corrected, the figure
survives **three independent denominators with a passing positive control**: weekly meter 3.71×,
price-list out-of-sample 3.6×, and the 5-hour meter 3.25× (which A3 had called unobservable and which
is actually the *better*-conditioned instrument, 1,730 ticks vs 384). Four accounts, non-overlapping.

**(iii) The structural ceiling, and it is biting in the live fleet right now.** Live meters I read this
session: `weekly/fable` = **94/7 · 41/13 · 6/0 · 100/76**. The fourth account is at **weekly 100 with 24
points of Fable sub-cap unspendable**, because the sub-cap is bounded by the general weekly remainder
(`f_eff = min(0.5·(1−fable_pct/100), w_rem)`, `bin/claude-accounts:3481`) — `--rank fable` already
reports it `fable-exhausted` at fable 76%. **Today's abundant Fable headroom is a selection effect of
Fable being opt-in.** Under a default flip the fable meter would track the weekly meter and hit its
half-ceiling first, at which point the fleet has half a week left that *only a non-Fable model can
spend* — and the designed Opus down-tier is exactly what the flip deleted.

**Quota verdict: the operator's cost half is refuted, and the refutation is dispositive independent of
quality.** Even granting the matched-rung intelligence edge in full, the trade is *"+3.5 to +4.5pp on a
benchmark with no confidence intervals, for 3.2–3.7× the only currency we spend, capped at half the
week."* That is not close.

---

## 3. THE HARNESS: four blockers that would fire on day one

Three axes (A5 harness, A6 mechanics, A7 architecture) had **no skeptic run**, so I verified their
load-bearing code sites myself. All four cited `handoff-fire.sh` Fable arms reproduce verbatim.

1. **Every fire/handoff ranks accounts on the Fable lane, and an empty lane HALTS rather than
   degrades.** `handoff-fire.sh:9030` `case "$MODEL" in claude-fable-5*) kind=fable`, then rc 2 →
   `return 1` → caller halts with *"NO account routable for fable"* (`:9038-9041`, read). With one
   account already `fable-exhausted`, that path is reachable **today**.
2. **Account re-picking stops fleet-wide.** `handoff-fire.sh:8765` — `recycle_repick()` early-returns
   for any fable model. ⚠️ **Correction to A7, which had no skeptic:** A7 says this *"REFUSES every
   in-place recycle."* It does not. The recycle proceeds; what stops is the account **re-pick** — so
   the use-it-or-lose-it rebalancer (the `headroom/T**γ` scorer that exists precisely because unused
   weekly quota is decaying inventory) goes dark. A5's framing is the correct one.
3. **The frontier spawn cap stops meaning anything.** `hooks/frontier-spawn-gate.sh` caps at 6
   fable spawns/session and refuses the 7th with *"park the hole"*. Under a flip its population
   **inverts**: spawns naming no model are ungated (`:23` exits 0 on empty), so the cap *disarms* for
   correct spawns while *over-firing* on legacy explicit ones. It cannot express "cap frontier use"
   when frontier is the baseline.
4. **The per-fire entitlement probe becomes a ~$1/account Fable probe.** `handoff-fire.sh:9157`
   switches the probe from `claude-haiku-4-5` to the fire model; the in-file measurement (2026-09-08)
   prices four Fable 5.1 probes at ~1 USD of cache creation each — paid on up to 4 accounts, every fire
   and every recycle, before any work.

**And one hard prerequisite that is not a code change:** `scripts/limit-reset-safety-gate.sh:114-121`
states that the **Fable-scoped limit message's verbatim shape has never been captured**, so it
classifies as `other_api_error` → **NEVER PARKED** → the limit-recovery poller is blind to it. That is
acceptable while Fable is a reserve. It is not acceptable when it becomes the commonest limit event on
the box.

---

## 4. ON `/model-upgrade` SPECIFICALLY

**The runbook does not cover this case, and invoking it would read green while checking nothing.**
`skills/model-upgrade/SKILL.md` has exactly three cases — A lateral bump, B tier insertion, C
downgrade/window-end — and a *default-tier repoint* matches none: `versions.opus_latest` and
`versions.frontier_latest` both stay correct and unchanged; only `roles.*` moves.

Worse, its verification block (`SKILL.md:228-238`) is **structurally blind** to a role change:
`claude-bump-models` builds its pairs only from `versions.<family>_{prior,latest}`, and
`claude-lint-models.sh` builds its stale set only from keys matching `test("_prior$")`. A role edit
writes neither, so both tools run with an **empty working set** and report clean. The flip's only real
error signal would be **fleet-wide Fable-meter exhaustion days later**.

Separately: the one way to make `claude-bump-models` actually execute this is
`--from-to claude-opus-5 claude-fable-5-1`, which rewrites **64 `claude-opus-5` literals across 62
team-brief files in the reso repo** — mutating a *second repository's primary checkout* working tree.
`model-config.yaml:586` actively instructs this wrong path.

---

## 5. SSOT CHANGES JUSTIFIED ON THEIR OWN EVIDENCE (regardless of the headline)

These do not depend on the flip decision. Several are repairs to things that are wrong *today*.

**C1 — `effort_defaults.settings_floor` is unenforced on 4 of 5 config dirs. MEASURED BY ME.**
`bash scripts/effort-parity-assert.sh` →
`BELOW .claude=medium · .claude-next=low · .claude-tertiary=medium · .claude-quaternary=low` against
floor `high`, plus `DRIFT zshrc launcher --effort {CLAUDE_DEFAULT_EFFORT:-max} != SSOT high`.
**This is the most decision-relevant fact in the whole dossier**: we spent a session arguing about
"Opus 5 @ high" and it is only true where the launcher passes `--effort high` explicitly. Every
non-wrapped surface on four of five accounts resolves *medium or low*. The script itself calls these an
authority-ceiling (class-C) surface → **operator step**, file with `cc-backlog needs`.

**C2 — The prose layer is two model generations stale.** `skills/frontier-routing/SKILL.md:6,9`
*"Default model = Opus 4.8 @ effort max"*; same in `frontier-run:9,66`, `frontier-hole:8`,
`frontier-campaign:59`, `agent-teams:43,223`, `research-subagents:446,583` — **and inside the SSOT
itself at `model-config.yaml:589`**, whose comment reads *"Opus 5 @ effort max"* beside a value that is
`high`. These load into live sessions and state a false default. No blocker; pure repair.

**C3 — `max_fable_spawns_per_session` rests on a figure that matches no board.**
`model-config.yaml:749` cites a *"CursorBench $18-vs-$15 band per task"* matching **neither** 3.2 nor
4.0. Per this repo's own rule (*a resident rule restating a perishable fact cannot learn it changed ⇒
delegate it*), replace the number with **the criterion plus the command that re-measures it**, exactly
as the ship-policy table names no repo.

**C4 — The D6 "Opus 5 ≈ Fable at HALF cost" re-do is owed and this session did it.**
`model-config.yaml:542-543` already carries *"⚠️ That verdict is BASE-RATE-ONLY; re-check it against
Fable 5.1's 0.025× cache reads before reusing it."* Answer: **parity, ±6%, sign undetermined**, with the
1h cache-write share (99.7% → 85.1% → 60.7% in a month, crossover ~50%) named as the variable the sign
turns on. Land the measurement *and* its instability.

**C5 — Our cost tooling cannot price Fable, by construction.** `pricing_per_mtok` is positional
`[input, output]` and `SKILL.md:150-152` forbids changing the arity, so the cache-read multiplier lives
**only in a YAML comment** (`model-config.yaml:533-537`) and **no consumer reads it** — not
`cc-quota-price`, not `claude-accounts` scoring. The one economic fact the flip argument rests on is
invisible to every cost consumer. Companion: the cache-**write** TTL split is the sixth repeat of one
error class; a shared rate-card helper carrying `{input, output, cache_read, cache_write_5m,
cache_write_1h}` closes both.

**C6 — `fable51_capability_sensitive`'s justification is refuted two lines below itself.**
`model-config.yaml:832` reads *"gains over Fable 5 are largest at the HIGHER settings"*; `:838-839`
says *"✅ MEASURED 2026-09-10 … the sentence above is now HISTORY"*. Anyone reading 832 alone inherits a
refuted sentence. Mark it refuted **in place**, louder. Record beside it that **the 64K output cap binds
above `high` on Fable 5.1** (sweep: xhigh continued in 3/9 cells; max in 4/6 and produced *no review* on
cp-09 after 256K tokens / 47 min / $15.16) — so the Fable effort ladder has **two usable rungs, not five**.

**C7 — `per_turn_effort` is Fable-5.1-only in the 2.1.260 client registry.** This refutes
`model-config.yaml`'s *"Also supported on Opus 5"* at the client layer, and it is the **strongest
genuinely novel pro-Fable fact in the dossier**: Fable 5.1 is the only model in our stack that can
change effort mid-conversation without invalidating the prompt cache. Record it accurately whichever
way the default goes — if routing ever moves to the effort axis, this is the enabling capability.

**C8 — Two routers disagree about which meter the default lane bills, TODAY.** `bin/cc-route:184-193`
keys the meter on **SLOT**; `handoff-fire.sh:9030` keys it on **MODEL**. Any model-keyed lane run
through cc-route is routed against the wrong meter now — not only under a flip. Third-order:
`cc-route:196-217` emits `$lead_model` as the *"designed Opus fallback"*, which under a Fable
`lead_default` would degrade Fable→Fable while the reason string still says "Opus fallback".

**C9 — A sixth default-model emitter sits in nobody's checklist.**
`~/.claude-quaternary/settings.json:412` carries `"model": "opus[1m]"`; the other four dirs have no
`model` key. It is a silent divergence from the launcher's explicit `--model` today, and would have
silently kept one whole account on Opus after any flip.

**C10 — The upgrade path cannot auto-fix its own launcher assertions.**
`lib/cc-upgrade-gate/check05_launcher.sh:122-126` hardcodes **both** `--model claude-opus-5` and
`--effort high`, while `templates/model-classification.json`'s `update` list covers `agents/*.md`,
README, plans and memory — **not** `bin/ scripts/ hooks/ lib/`. Any future model or effort change reds
the gate and cannot be auto-repaired. Structural gap, worth closing regardless.

**C11 — The frontier tier is dormant and its pins are unmeasured.** `FRONTIER_HOLES.md`: **0 OPEN
holes, 4 panels ever, last ledger write 38 days ago, 6 campaign candidates none launched.** Five roles
are pinned to frontier (`frontier_discovery`, `teammate_frontier`, `research_adversarial`,
`workflow_judge`, `eval_judge`) and **none has been measured for Fable 5.1** — three of them
(`research_adversarial`, `workflow_judge`, `eval_judge`) are entirely outside CursorBench's scope.
⚠️ **State this as an open conflict, not a conclusion.** A1 proposed that the SSOT has its frontier
pins backwards (Fable pinned to review, where our sweep says it is worse; Opus kept on the lead, where
CursorBench says Fable is better). Its skeptic refuted the *reasoning* — CursorBench 3.1 added code
review and bugfinding, and versions are additive, so the two instruments **overlap on the exact axis
where they disagree**. Overlapping instruments that disagree require **adjudication**, not a
complementary synthesis. The hypothesis is live; the argument for it is not.

---

## 6. BLOCKERS — what must be true before ANY flip

| # | Blocker | The command or reading that clears it |
|---|---|---|
| B1 | **Fable-scoped limit message has never been captured**, so limit-recovery is blind to it (`limit-reset-safety-gate.sh:114-121`). Hard prerequisite, not a follow-on. | Capture one real Fable-scoped limit message and fixture-ize it into the `limit-reset-safety-gate` bats suite. |
| B2 | **The 0.5 coupling and the ~3.2–3.7× exchange rate.** The coupling is the unmovable half: below a 100% plan inclusion, Fable cannot be a default at any quality. | `claude-accounts --json` before/after a fixed synthetic workload on ONE idle account per model, with a `message.id`-deduped token census split by class; re-read `accounts.json frontier.coupling` against whatever Anthropic currently publishes. |
| B3 | **Opus 5 @high has never been quality-benchmarked**, by us or the vendor, on our corpus. `routing-economics.md` R2 specified this on 2026-08-16; it has sat **31 days unrun**. | `SWEEP_CONFIG_DIR=<acct> ./run-arms.sh` with `--model claude-opus-5 --effort high` over the frozen `tests/fixtures/codex-probe/` corpus, same `judge.py` panel. ~$15–25. |
| B4 | **The close contract is a lexical gate calibrated on Opus-5-era closes** (613 + 300 closes, 2026-08-23). Fable 5.1's documented deltas — less chat formatting, denser prose — attack the line-1 rung glyph, the literal `good to close`, and the `▶` act line inside a 3-line window. | Run 5.1 headless over a corpus of close-shaped prompts and execute `close_shape_missing` / `close_act_missing` against its output. Both libs are hermetic via `CC_VERDICT_WINDOW` / `CC_ACT_WINDOW`. **No flip required — cheapest and highest-value outstanding measurement.** |
| B5 | **Fire halts and repick dies** (`handoff-fire.sh:9030`/`:9038-9041`, `:8765`), plus the cc-route↔handoff-fire meter disagreement (C8). | Code change, not a measurement: decide whether a Fable default gets a `kind=general` exception, and resolve which key owns the meter. |
| B6 | **The frontier spawn cap's population inverts** — the gate cannot express "cap frontier use" when frontier is the baseline. | Operator decision: re-key onto effort tier, onto `fable_pct` headroom, or retire. Not measurable. |
| B7 | **The flip mechanism is unspecified and pivots the whole blast radius** (SSOT role repoint vs `~/.zshrc:499,503` literal vs `CLAUDE_NEXT_MODEL` export). Only the SSOT route reaches agent frontmatter and arms the spawn gate. | Choose the route, then re-run `grep -rn 'claude-fable-5\|claude-opus-5' bin/ scripts/ hooks/ lib/ commands/ agents/`. |
| B8 | **`fable_5_1_prompt_bundle` / `fable_5_mitigations` silently change the system prompt Claude Code sends**, and Anthropic's bundled `/code-review` skill has measured budget cells for opus-4-8/opus-5/sonnet-5 and **no Fable entry at all**. | Dump both bundles out of `claude.exe` 2.1.260 and diff against `opus_5_prompt_bundle`. |
| B9 | **Safety regression on exactly our architecture.** Card: *"slightly more willing than Opus 5 to bypass approval gates"*, *"launching subagents with permission checks disabled"* (<0.01% of completions), *"accepts unverifiable claims of authorization more readily than Opus 5"*. Plus in-line classifiers returning `stop_reason: refusal` on benign work — 3.4% of Toolathlon trajectories — with **base64 in tool output** a named trigger, and **26.2% of our recent transcripts carry base64 blocks** (measured by the A2 skeptic). | Count `stop_reason: "refusal"` and server-side fallback events across existing frontier-tier sessions in `~/.claude/logs` — the data may already be on disk. |

---

## 7. THE EXPERIMENT — because the intelligence half genuinely is "we do not know"

Two arms, both cheap, both run **before** any routing change. Neither requires a flip.

**EXP-1 — close the incumbent gap (~$15–25, one evening).**
Add ONE arm to the existing frozen rig: `claude-opus-5 @high` over the 36-defect
`tests/fixtures/codex-probe/` corpus, same `run-arms.sh`, same 3-judge `judge.py` panel, same
quota-fault exclusion.
*What it settles:* whether our own headline number is about our own default at all.
*What it cannot settle:* the flip. The design's prospective power at a 12pp effect is ~13–25%, so it
can neither certify a difference nor certify a tie. **Report it as a paired sign test over the 25
paired defects with the discordant count stated — never as a recall total**, which is how the original
result got over-read.

**EXP-2 — the one that could actually move routing: ONE role, two weekly reset cycles.**
Move `roles.research_worker` (`model-config.yaml:638`) to `claude-fable-5-1 @ medium`.
*Why that role:* high-volume (N=10 waves are the standing default), self-verifying, already on
`auto_mode_allowlist.non_firstParty_max` so `hooks/agent-teams-enforce.sh` passes unedited, **not**
`lead_default` so cc-route's slot→meter keying stays correct, and it is a one-line symlinked revert.
*Measured:* (a) Δ`fable_pct`/Δ`weekly_pct` per wave from `claude-accounts --json`, over **two** full
fable sub-window resets — `fable_reset_h` is 55–128h and **not aligned to the weekly reset**, so one
cycle cannot separate *"we have headroom"* from *"we sampled a fresh sub-window"*; (b) tokens per
completed unit, **deduped on `message.id`**, split by class with `cache_creation` broken into
`ephemeral_5m` vs `ephemeral_1h`; (c) quality on the frozen anchored corpus at every vote threshold;
(d) 1-min load per cell as a covariate, adjudicated by **Spearman, never max/min**.
*Decision rule, fixed before the run:* ADOPT **for that role only** iff quality ≥ Opus@high at every
vote threshold **AND** measured per-token quota ratio < 1.5 **AND** zero `fable-exhausted` rank
refusals across both cycles. Any one failing → revert the line and record the number.
*Cost bound:* one account, stop at `fable_pct` 40.

**Note on staging:** there is no staging pattern for a *routing* decision. `frontier_staged`/
`opus_staged` stage a RELEASE and are invisible to both `claude-bump-models` and
`claude-lint-models.sh` (both key on `*_latest`/`*_prior` only); `accounts.json` accounts carry no
model field. **The role ladder is the only available A/B surface.**

---

## 8. WHAT WE STILL DO NOT KNOW

1. **Opus 5 @high quality, against anything.** Our production default, never benchmarked. Specified
   31 days ago (R2), unrun.
2. **Whether the Max weekly meter is token-weighted or price-weighted**, and whether the cache-read
   discount reaches a subscriber *at all*. Three in-repo sources disagree; the repo's own standing
   instruction is *"do not use the cache-read price as a reason to prefer either plan until the weekly
   meter is fitted."*
3. **Whether the CursorBench ordering transfers out of Cursor's scaffold** into Claude Code's, with a
   ~94KB always-resident instruction set and a large hook chain. Untested by anyone, including us —
   and our own sweep deliberately excluded it (`--setting-sources ""`).
4. **The statistical weight of every CursorBench gap.** No n, no runs/task, no CI, no error bars, no
   harness or grader disclosure. At p=0.455, a 2.1pp gap needs ~4,320 tasks/arm; a 4.5pp gap ~705.
   The feasibility bound (43 configs × n × ~$5/task) makes n ≤ ~200 likely, at which 4.5pp is ~1.4 SE.
5. **Fabrication / false-positive rate at reduced effort on Fable 5.1.** Our sweep scored **recall
   only**. T1's certified finding is that *every* reduced-effort config fabricated. A "medium is a
   free win" reading is unprotected against exactly that failure mode.
6. **Derivation-panel quality** — the frontier tier's *actual routed job*. The SSOT names this hole by
   name and asks for a re-probe before restoring xhigh. Nothing has run.
7. **The verbatim shape of a Fable-scoped limit message.** Never captured (B1).
8. **Whether the three unskepticked axes hold.** A5/A6/A7 had no adversarial pass. I verified their
   four load-bearing `handoff-fire.sh` sites myself and **found one overstatement** (A7's "refuses every
   recycle" — it skips the account re-pick, §3.2). Treat their remaining claims as one-armed.
9. **Whether `effort:` in `.claude/agents/*.md` frontmatter is APPLIED** to an in-process Agent spawn
   or merely accepted as a recognised key. If applied, per-slot effort routing is buildable today
   without a Dynamic Workflow — one spawn probe, one minute, and it is the first thing to run if
   effort becomes the routing axis.

---

## 9. ONE-LINE SUMMARY FOR THE OPERATOR

Keep `claude-opus-5 @ high`. Fable 5.1 is probably a little smarter *per effort label* — two
independent instruments agree on that — but you cannot drop a rung to pay for it (the cross-rung claim
fails on 4 of 5 vendor charts at low), and in the only currency this fleet spends it costs **3.2–3.7×
per token against a bucket it can never use more than half of**. The real finding is on the effort
axis: **`effort-parity-assert` is RED on 4 of 5 config dirs right now**, so the default we were
debating is not what four of five accounts actually resolve.
