# Audit: the existing research-methodology machinery, and why re-asking "are we 100.00/100.00 complete?" keeps turning up one more hole

Scope: read-only audit of `/Users/chrisren/Development/claude-infrastructure` (paths below are relative to that repo unless absolute) plus transcript receipts from `~/.claude*/projects/*/*.jsonl`. Scratch scripts: `/tmp/rescomp/internal/reask_scan.py`, `session_prompts.py`, `assist_between.py`.

## 0. Answer first

The machinery defines when to stop spawning subagents inside one wave. It never defines when a research program is finished. Nothing declares the frame that "complete" is measured against, nothing estimates coverage with a number, and nothing carries the list of dimensions already covered from one re-ask to the next. Every gap-finding instrument is required to come back with a positive number of gaps: the critic names "1-3 missing axes", the negative-space trigger says "List 3", and the self-pass says "Find 2-3 gaps". The only way to drop a gap it names is to quote the user's own out-of-scope words. The operator's intake ("100.00/100.00 complete, covering, 100th-percentile absolute perfection") excludes nothing, so every gap it names gets researched.

On top of that:
- Each re-ask resets the per-invocation cap.
- The skill tells the model to treat a "re-check" as a reason to widen the search.
- The Follow-On Gate lets scope grow without limit.
- Mechanically, "complete" means zero unchecked `- [ ]` boxes in the DoD file, which a research DoD never has.

So each "are we done?" is a fresh, unanchored judgment by a generator that is required to produce holes. The loop is designed in, not accidental.

## 1. Every stop rule that exists (inventory)

| # | Rule | Where | What it actually bounds | Binding? |
|---|---|---|---|---|
| S1 | **OASIS**: stop spawning when (1) pairwise brief-cosine ≤ τ=0.6, (2) the adversarial pass returns refinements only, no new axis, (3) the cumulative-discovery curve fits `c·N^α`, α<1, and the next gain is < ε=0.5 unique findings, (4) the falsifiability check passes | `skills/research-subagents/SKILL.md:756-782` | Spawning within one wave. "If any one fails … spawn ONE more subagent on it" (`:778-779`) | Prose only. No code computes cosine, α or ε: a repo-wide grep for `cosine\|N\^α\|cumulative-discovery` in `*.sh/*.py/*.js/*.ts` finds nothing outside unrelated memory-eval and audio code |
| S2 | It explicitly **rejects** "two consecutive waves of agreement" as insufficient (a sign of false consensus) | `SKILL.md:758-763` | Removes the only dry-round-style stop | Deliberate |
| S3 | Pre-commitment falsification: "would the opposite flip my conclusion?" If no, stop | `SKILL.md:743-754`; `commands/research.md:101` | Whether to spawn one more subagent | The model judges it against its own current conclusion |
| S4 | Subagent saturation: stop when the next call would only refine what is already gathered | `SKILL.md:599`; `agents/deep-research.md:96-100`; brief stop-line `SKILL.md:318-321`, `:531-534` | Tool calls inside one worker | Worker's own judgment |
| S5 | Negative-space trigger, "List 3 with reasons". A dimension is dropped only if its reason is "explicitly out of scope per user intake", which must quote the user's words. Capped at 3 per invocation | `SKILL.md:796-803` | Declaring saturation | Always yields 3 candidates, and the only exit needs user-exclusion text |
| S6 | Wave 2 conditional gap-fill: spawn 3-8 subagents if any negative-space reason is "I forgot" or "not obviously relevant". "If all reasons are 'explicitly out of scope' → wave 1 stands" | `SKILL.md:819-828` | Whether a second wave runs | Same exit as S5 |
| S7 | Research-decomposition critic: COMPLETENESS must "name 1-3 plausible axes the decomposition is MISSING"; APPROVE or REVISE | `agents/research-decomposition-critic.md:37-40, 78-80` | Before the spawn only (Sonnet, `maxTurns: 10`, `:4,7`) | Quota-forced. Also barely used: spawned in 3 sessions (4 transcript files, one duplicated across config dirs, 2026-09-15/19/23) vs `deep-research` in 123 files. The skill mentions a "critic-gate" (`SKILL.md:145,156`) but never says how to invoke it, and `/research` never names it |
| S8 | Worker adversarial self-pass, "Find 2-3 gaps. Investigate them" | `agents/deep-research.md:180-190` | Inside each worker | Quota-forced |
| S9 | Frontier run: "If NEW is empty two runs in a row, say so — that is the signal to stop spending the window on sweeps" | `skills/frontier-run/SKILL.md:136-137` | Only Fable discovery sweeps | The only dry-round stop in the whole machinery, and it is advisory ("say so") |
| S10 | F2 conviction rule: below 90%, "research exhaustively", then implement if above 90% or ask | `CLAUDE.global.md:619` | Decisions, not coverage | "Exhaustively" is never defined; the conviction number is self-reported |
| S11 | Ground-up Phase 0: superlatives ("perfect", "100/100") are **banned** from the DoD because they "make completion unfalsifiable — the exemplar's Stop-hook thrashed on exactly this". Phase 5: "Never let an unfalsifiable 'perfection' clause keep the session hostage: state the ceiling and the accrual read, then stop" | `skills/ground-up/SKILL.md:14-18, 88-91` | Only `/ground-up` rebuilds | The one place the repo already names the root cause. It is absent from `/research`, research-subagents, plan-conventions and dod-persist |

## 2. What "complete" is defined against

- **For research: nothing.** Neither `/research` (`commands/research.md`, 105 lines) nor the skill (966 lines) defines a research deliverable's completeness. OASIS is scoped to "stop spawning" (`SKILL.md:766`). There is no declared frame and no denominator: no enumerated list of question-space dimensions that "covering" means covering, and no acceptance criteria for the plan.
- **For the session: a one-line frozen DoD.** "Close-time completeness is then a diff against that contract" (`CLAUDE.global.md:555-558`). A close question "asks about the task … diff the repo against it" (`CLAUDE.global.slim.md:259`). The contract is copied verbatim from the operator's ask, and `hooks/dod-persist.sh:1-15` exists to preserve "the 100/100 contract" through compaction. It carries the superlative faithfully and never checks whether it can be falsified. A repo grep for `superlative|unfalsifiable` in skills, commands and agents hits only `ground-up`.
- **Mechanically: unchecked checkboxes.** `scripts/wrap-ledger.sh:616-623` computes `REMAINDER` as the count of `^\s*[-*]\s+\[\s\]` lines in the DoD file. `/are-we-done` asks for "frozen-DoD remainder 0" (`commands/are-we-done.md:52-57`). A research DoD like "research to 100.00/100.00 …" has no boxes, so REMAINDER is 0 and the ledger can read ✅ while coverage is re-judged from scratch on every ask.
- **Growth has no limit.** A Follow-On Gate pass appends `Scope (grown): +<item>` and executes (`CLAUDE.global.md:569, 626-627`). F1 is judged under "100th-percentile completeness; nothing left on the table" (`:616-617`), so any net-positive discovered hole passes F1 by construction. "Bounded means SCOPED, never DEFERRED" (`:623-624`) caps each item, not how many items there are.

## 3. Is coverage ever estimated quantitatively?

No. OASIS criterion 3 names a quantitative form (`c·N^α`, ε=0.5), but:
- No instrument records per-agent unique findings.
- No code fits the curve.
- No transcript shows the fit being run.

A grep for `capture-recapture|Chao|Good-Turing|species richness|Lincoln` across the repo and 404 `docs/research` entries finds nothing. The only numbers attached to research are:
- the conviction % (a self-reported confidence in a decision, not a coverage estimate), at `CLAUDE.global.md:619`;
- the per-wave N (a spawn count), at `SKILL.md:69-81`.

Neither tells you what fraction of the question space is covered or how many unknown holes probably remain.

## 4. Are research artifacts persisted as a reusable ledger?

Only partly, and not as a coverage ledger.
- **Delivery:** each wave writes per-axis files to whatever path the brief names (field 7, `SKILL.md:231-240`). The artifact-reference pattern writes to `~/.claude/research-artifacts/<session>/` (`SKILL.md:895-899`; the directory holds 7 entries).
- **No index:** `docs/research/` has 404 entries and no index, README, or cross-wave "dimensions covered / claims settled / questions closed" register.
- **FRONTIER_HOLES.md:** the one real ledger, with statuses OPEN → IN-PANEL → CONFIRMED / REFUTED / SOLVED, and Resolved, Seam Registry and Campaign sections (`docs/research/FRONTIER_HOLES.md:1-6, 10, 138, 158, 166`). It records infra unknowns for Fable, not a project's research coverage, and holds 4 holes in total.
- **Other building blocks:** `facts.json` claim stores exist ad hoc (`docs/research/opus55-utilization-2026-09-22/facts.json`; `skills/cc-upgrade/utilize.md:45` lists "what the sources do NOT state"). `/ground-up` requires a REJECTED ALTERNATIVES section "(prevents relitigating)" (`skills/ground-up/SKILL.md:64-68`). These are the pieces of a ledger, but nothing wires them into `/research`.
- **Lessons already written about this failure shape:**
  - `docs/lessons/a-prior-partial-evaluation-reads-as-a-completed-one.md`: a verdict-shaped record that omits what was examined. A late completeness critic found the real comparator after 68 agent passes.
  - `docs/lessons/a-spec-that-forbids-invention-names-artifacts-a-crawl-will-miss.md`: a mirror was "complete by every check", and asking to affirm it found six missing artifacts.

## 5. The precise mechanism that permits "one more hole on every re-ask"

Seven parts. Each is necessary for the loop, and together they are sufficient.

1. **No declared frame, so no denominator.** Nothing enumerates the dimensions the research must cover before it starts. "Covering" therefore has no fixed referent, and each re-ask re-derives the frame from scratch (§2).
2. **Every gap-finding instrument is required to name gaps.** The critic must "name 1-3" (`research-decomposition-critic.md:37-38`). The negative-space trigger must "List 3" (`SKILL.md:798`). The worker must "Find 2-3 gaps" (`deep-research.md:187`). A generator that must always produce output cannot report "none", and OASIS criterion 2 ("adversarial null") depends on that report.
3. **The only exit from a named gap is the user's own exclusion words** (`SKILL.md:800-803, 826-828`). The operator's standing intake ("100.00/100.00 … absolute perfection … ALL our time/tokens") excludes nothing, so every forced candidate is promoted, whether the reason is "I forgot" or "not obviously relevant".
4. **Resets each time.** The cap is "3 dimensions per invocation" (`SKILL.md:802`), and the skill says a "re-check / re-investigate" framing "assumes prior work covered the axes … apply this rule more aggressively" (`SKILL.md:944-948`). A re-ask is instructed to widen, and it starts with a fresh quota of 3.
5. **No persisted coverage ledger.** What was examined, and why each candidate was ruled out, is not carried forward as a register the next ask must reconcile against (§4). So a previously rejected or already-covered dimension can come back as "new".
6. **The stop rule was explicitly weakened, and the replacement is not implemented.** "Two waves of agreement" was rejected (`SKILL.md:758-763`) and replaced by OASIS criteria 1 and 3, which nothing computes. The one dry-round rule (`frontier-run/SKILL.md:136-137`) is advisory and limited to Fable sweeps.
7. **"Complete" is not measurable at close, and scope can grow without limit.** The DoD carries the superlative verbatim (`dod-persist.sh:1-15`), mechanical completeness is a checkbox count (`wrap-ledger.sh:616-623`), and F1 passes any net-positive item under "nothing left on the table" (`CLAUDE.global.md:616-617, 626-627`). Nothing in the close protocol can say "research is finished". Only `/ground-up` bans the superlative (`ground-up/SKILL.md:16-18`), and it says why: completion becomes unfalsifiable and the Stop hook thrashes.

The quality-side mechanisms reinforce the loop. The skill's "Consensus at high-N is a measurement artifact" (`SKILL.md:359`) and "never accept consensus as evidence of correctness" (`:781-782`) are correct epistemics, but they remove agreement as a stop signal without supplying a replacement estimator.

## 6. Transcript receipts (the loop observed)

`reask_scan.py` over all 6 config roots, counting genuine human prompts deduped by session basename. It found **222** prompts matching `100.00/100.00`, `100th percentile … complete/perfect` or `are we 100/complete`. In **144** of them (65%), the final answer's first 220 characters carry a no / gap / remaining / actually marker. The marker is crude and also matches landing "no"s, so read 65% as an upper-bound indicator, not a rate.

Worked chain, session `989f6dbf` (`~/.claude-secondary/projects/-Users-chrisren-Development-claude-infrastructure/989f6dbf-0216-45d0-a061-f998c29ab27c.jsonl`, the VoiceInk / Willow latency plan):
- 2026-09-27T23:53:15, asked to explain why the plan is 100.00/100.00. 23:53:23: "The plan has one real gap … I'm adding that". 23:53:48: "the plan is complete, but it is not 100% certain … conviction … 85%".
- 23:56:55, "Anything to further research to reach 100.00/100.00?" This launched an 8-track workflow with a completeness critic at the end (03:16:41: "The completeness critic runs after it").
- 03:46:02: the review found an unexamined axis, a daily job pushing to the public fork.
- 05:21:27: "yes, there was more to research. It's now done … Nothing left can be settled by more desk research."
- 05:26:09, the re-ask "Have we completed and exhausted our research…?" 05:26:16: "No, not yet. One check remains", which found 20 defects (05:30:58).
- 05:27:05, the operator raised a new axis (the upstream version base). At 05:34:06 upstream v2.20 "changes what the plan measured and assumed". That is a frame dimension no stage ever declared, surfaced by the human.
- Conviction moved 85% → 75% → 90% across these turns, with no coverage number at any point.

Second chain, session `46d14e14` (`~/.claude-quaternary/projects/-Users-chrisren-Development-agent-context-sync/…jsonl`): an audit workflow ("six parallel reviewers … then a critic that looks for anything the reviewers missed", 2026-09-29T19:37), then v4 (09-30 05:29), v5 (06:20), "round 3's judge stage" (07:18), v6 (08:28 and 15:02). Each round is triggered by the previous round's critic.

## 7. What already exists that a fix can build on

- `skills/ground-up/SKILL.md:14-18, 64-68, 88-91`: the superlative ban, rejected alternatives, and closing on PROVEN / IN FLIGHT / ACCRUING buckets. Generalize these to `/research`.
- `skills/frontier-run/SKILL.md:116-121, 136-137`: CONFIRMED / NEW / REFUTED reconciliation against a hidden baseline, plus a two-dry-runs signal. Recording those tags per round gives the cumulative-discovery curve OASIS needs.
- `docs/research/FRONTIER_HOLES.md`: a status-machine ledger template to reuse as a per-project coverage register.
- `wrap-ledger.sh:616-623`: already counts `- [ ]` boxes. A research DoD written as a checklist of frame dimensions, each closed by a named artifact, would make completion mechanically readable with no new code.

## 8. Caveats

- Transcript counts cover what is retained on disk, and critic usage may be undercounted if Workflow `agent()` calls do not carry `subagent_type`.
- An earlier rg run used `-E` (which is `--encoding` in rg, not a regex flag) and returned 0 for everything. Only the corrected `-e` counts appear above.
- The 144/222 marker count is a crude text heuristic.
