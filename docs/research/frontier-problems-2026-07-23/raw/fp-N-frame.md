<!-- source: /Users/chrisren/.claude-secondary/projects/-Users-chrisren-Development-claude-infrastructure/914aaa37-3198-4ffc-8253-9d6d9980a81a.jsonl
 turns=50 assistant_texts=7 last_stop=end_turn mail_injections=[] -->

Saturated at 16 tool calls — next calls (reading hook bodies) are predictable and answer-invariant. Confirmed: 3 genuinely dead hooks (0 refs, unwired: `migrate-plans-index` 64 LOC, `reset-hard-shadow-allow` 183 LOC, `task-completed-index` 75 LOC = 322 LOC), resident rules ARE ~93% cache-read (token-$ tax is small; context-occupancy tax is real), and recycle thresholds are consistent (no contradiction there). Composing.

Adversarial self-pass complete — the failure-frame is RIGHT on three counts I concede below. Final report:

---

## VERDICT

**PARTIALLY — the failure-frame is missing a whole cost *class*, but not the one my brief assumed. Confidence: HIGH on the reframe, MEDIUM on "bigger."**

The 12 siblings are hunting real, recurring money — dropped commits, stranded reports, misroutes are documented and their guards earn their keep. The failure work is **not** wasted. But the failure taxonomy is structurally blind to the **dominant recurring cost: the maintenance-and-attention tax of a control layer that now spends ~10–14 commits/day maintaining *itself*.** No single "failure" captures it because every component is working as designed. The single biggest margin is not tax-vs-losses arithmetic — it's that **both failures and tax are downstream of one upstream generator (complexity growth), which the failure-frame treats as the *cure*, not the disease.**

Two limbs of my own counter-case are empirically **weak** and I concede them up front (adversarial pass, below): the token-dollar tax is largely cache-mitigated, and goal-displacement-by-output is refuted.

---

## Q1 — Steady-state tax vs failure losses (quantified)

**Empirical (measured):**

| Tax component | Measurement | Command basis |
|---|---|---|
| Resident rule mass | **18,830 tok/turn** in-repo (global 25,235c + **byte-identical project dup** 25,235c + .claude 2,167c + MEMORY index 17,033c = 69,670c) | `wc -c` + `diff -q` → "IDENTICAL (byte-for-byte)" |
| — of which one section | **Session Close Protocol = 8,848c = 35%** of the 25KB CLAUDE.md, loaded **2× in-repo** | `re.split('\n## ')` section sizing |
| Hook tax per tool call | **20 shell spawns** (11 PreToolUse + 9 PostToolUse) + 14 turn-boundary (5 UserPromptSubmit + 9 Stop) | `settings.json` hook-count parse |
| Control-layer size | **25,937 LOC** shell/py; 61 hooks, 39 bin, 70 scripts | `wc -l` on hooks+bin+scripts |
| Background daemons | **12 launchd** running 24/7 (dispatcher, discovery, autonomy-sweep, reaper, 2× session-search, nightly-regression, …) | `ls launchd/` |
| **Maintenance velocity** | **419 infra commits/30d (~14/day)**; 286/30d touch bin+scripts+hooks; **98 are `fix:`**; fix:feat ≈ **72:70** | `git log --since` path-filtered |

**Documented failure losses (from MEMORY, 44 entries):** dfacccd lost commit — 1, recovered same-day; 3 misrouted nudges; stranded wave-reports — harvestable, not lost; "19-crash storm" — **0 real** per the corrected forensics. Episodic, individually small, mostly recovered.

**Which is bigger:** The **maintenance limb** dominates. 419 infra commits/30d at even ~10 min agent+review each ≈ **~70 agent-hours/30d spent maintaining the maintainer** — an order of magnitude above the documented failure losses (a few hours, mostly recovered). *The hours/commit factor is theoretical (argued); the commit count is empirical.* **The token limb does NOT dominate** — see concession #1.

---

## Q2 — Over-instrumentation evidence

| Finding | Type | Evidence |
|---|---|---|
| **Duplicate CLAUDE.md** — project-root == global, byte-for-byte; both load in-repo | Empirical | `diff -q` IDENTICAL; both visible in *this agent's own* system-reminder |
| **Archaeological threshold layers** — superseded "500-800K" + "350-500K modal" coexist with live "150-250K" in ONE file | Empirical | `research-subagents/SKILL.md:361` vs `:400` vs `:410` |
| **3 dead hooks** — 0 external refs, unwired anywhere (settings/launchd/scripts) | Empirical | `migrate-plans-index.sh` (64 LOC, a *one-time migration* living in hooks/), `reset-hard-shadow-allow.sh` (183 LOC), `task-completed-index.sh` (75 LOC) = **322 LOC dead** |
| **Redundant Stop chain** — 5 of 9 Stop hooks each independently read git/gate state | Empirical | completion-assert + operator-readout + boundary-handoff + session-continue + waiting-recycle all in Stop; 5× redundant git reads/Stop |
| **Deletion-would-have-fixed** — dup CLAUDE.md fixed by *removing* a file, not adding a rule; the whole `config-mirror-assert.sh` hook exists to police a sync that a symlink would make structural | Argued+cited | `hooks/config-mirror-assert.sh` (16 LOC guarding "~/.claude/CLAUDE.md is a separate real file — sync manually") |

*Non-findings (adversarial honesty):* teammate cap "6 concurrent" is consistent across CLAUDE.md:143 + agent-teams SKILL:243. Recycle thresholds 25/35/50/75/85/90% are a consistent tiered ladder, **not** a contradiction. I did **not** find contradictory spawn rules.

---

## Q3 — Simplification kernel (highest tax+risk reduction, least capability loss)

1. **De-dup CLAUDE.md** → replace project-root copy with a 3-line pointer. Removes 25,235c×(in-repo sessions)/turn context. **Zero** capability loss. *(empirical basis)*
2. **Compress Session Close Protocol** (8,848c → ~2KB) — the fact-bound hooks (completion-assert, operator-readout) *already enforce* it; the prose is a second copy of hook behavior.
3. **Delete 3 dead hooks** (322 LOC, 0 refs).
4. **Merge the 5-hook Stop chain** into one readout process (1 git read, not 5).
5. **Prune archaeological threshold refs** in research-subagents SKILL.
6. **Fold attention surfaces** — cc-board already aggregates; cc-blockers/cc-crash-report/cc-context could be one banner.
7. **Structural-sync the config mirror** (symlink) → retires `config-mirror-assert.sh` + the manual-sync rule it polices.

**10×-smaller kernel keeping ~95% value:** the load-bearing safety is ~5 mechanisms — worktree isolation, land-lock + content-verify, session-register/reconcile, completion-assert Stop-gate, cache-expiry. These prevent the *irreversible* classes (lost commits, sibling-land drops, reaper-blindness). The other ~56 hooks / 12 daemons / 8KB protocol are convenience (readouts/boards), self-maintenance (indexes/sweeps/migrations), or archaeology. **~10 hooks + ~5 bin tools + a 5KB CLAUDE.md retains most irreversible-loss protection.**

---

## Q4 — Problems INVISIBLE to the failure taxonomy

- **Self-generation loop (the big one):** complexity added to catch failure *becomes* the surface that generates the next failure class. The dup CLAUDE.md, the archaeological thresholds, the 322 LOC of dead hooks, the "CORRECTED ×2" memory entries — each is an artifact of growth, each is "working as designed," so **no failure-hunt flags any of them.** This is precisely what the 12 siblings will miss.
- **Marginal-rule adherence decay (theoretical):** every incident → a new rule/hook (44 memory entries ≈ 44 incident-born artifacts; 98 fixes/30d). More resident rules → lower per-rule adherence → more incidents. The frame that says "add a guard" *is the loop's engine.*
- **Attention economics:** ≥8 surfaces demand operator reading (cc-board, cc-context, cc-crash-report, cc-blockers, claude-accounts, wrap ledger, operator-readout, FRONTIER_HOLES). The one-human-bottleneck is a **design assumption**, never a "failure."
- **Goal-displacement — REFUTED as stated:** project repos *out-commit* infra 4.6:1 (doc_classifier 1035 + reso 882 = 1917 vs infra 419/30d). Infra does **not** crowd out project output by volume. The honest residual: infra is a **~18% overhead layer** on total activity — real, but not starvation.

---

## Adversarial self-pass — where the failure-frame is RIGHT

1. **Token-$ tax is cache-mitigated.** Resident rules are **~93% cache-read** (`token-usage-from-transcripts.md`), so "18,830 tok re-processed every turn" overstates $ ~10×. The tax is **context-*occupancy*** (~4.7% of 400K effective), not dollars. My Q1 token limb is weak; the maintenance limb carries the verdict.
2. **Failures are real and recurring** — dropped commits, stranded reports, misroutes are documented; the guards catch genuine money. The failure work is not waste.
3. **1:1 fix:feat is normal** for a young, hot repo; many fixes repair *new* features, not reopened scars. The feedback-loop claim is suggestive (12/60d regression-language commits), not proven.

Net: the failure-frame is a *correct* frame that is *incomplete* — it optimizes the reversible-loss margin while blind to the complexity generator upstream of both failures and tax.

---

## CANDIDATE FRONTIER PROBLEMS

**FP-1 · Complexity self-generation loop (guard-begets-guard)**
- *Evidence:* dup CLAUDE.md (`diff -q` IDENTICAL, 25KB×2 in-repo); 44 incident-born memory entries + 98 fixes/30d (`git log`); 322 LOC dead hooks (0 refs).
- *Mechanism class:* positive-feedback / iatrogenic complexity.
- *Current mitigations + status:* compact-memory, harvest-skill exist but are *additive*; no deletion discipline. **Unmitigated.**
- *Why it resists normal fixes:* each guard is locally correct + "working as designed" → invisible to failure-hunting; the fix is *subtraction*, which the incident→rule reflex never proposes.
- *Quantified cost:* ~70 agent-hrs/30d self-maintenance (14 commits/day); 25,937 LOC to keep working.
- *Frontier-fix sketch:* a **deletion budget** — every new hook/rule must retire one, or carry a sunset date + a never-recurred-in-N-days auto-flag.
- *Confidence:* HIGH structure / MEDIUM cost. *Stale-risk:* low (measured on 30d window).

**FP-2 · Resident-rule context occupancy (the always-loaded 18.8K)**
- *Evidence:* 69,670c resident in-repo (`wc -c`); Session Close Protocol alone 8,848c = 35%, doubled by the dup.
- *Mechanism class:* fixed-overhead / attention crowd-out in the model's own window.
- *Current mitigations + status:* prompt-cache mitigates $ (~93% read) but **not** window occupancy. **Partially mitigated ($ only).**
- *Why it resists:* rules feel free once cached; occupancy cost is invisible until a long session hits the 400K cliff.
- *Quantified cost:* ~4.7% of effective context every session, before any work.
- *Frontier-fix sketch:* tier rules into *always-resident kernel* (≤5KB) vs *lazy-load-on-trigger* (the skill model, applied to CLAUDE.md itself); de-dup structurally via symlink.
- *Confidence:* HIGH (empirical). *Stale-risk:* low.

**FP-3 · Operator-attention as the unpriced bottleneck**
- *Evidence:* ≥8 daily read-surfaces (bin/ ls: cc-board, cc-context, cc-crash-report, claude-accounts, + cc-blockers/wrap/operator-readout/FRONTIER_HOLES); 12 launchd daemons emitting pages.
- *Mechanism class:* single-human-throughput design assumption.
- *Current mitigations + status:* cc-board aggregates; cc-blockers joins 3 stores. **Aggregated but not capped** — surfaces still grow per incident.
- *Why it resists:* the whole system is architected around one operator reading state; no failure surfaces "too much to read."
- *Quantified cost:* unpriced; grows monotonically with incident count (44 and climbing).
- *Frontier-fix sketch:* a single fail-closed "does anything need me?" oracle that *suppresses* all other surfaces when it reads clean — collapse 8 surfaces to 1 gated view.
- *Confidence:* MEDIUM (surfaces empirical, cost argued). *Stale-risk:* medium.

**Blockers/uncertainties:** hours-per-commit is an estimate; "in-repo session volume" (which scales the dup tax) not directly measured; some "unwired" hooks *are* launchd-invoked (excluded from the dead-3, which have 0 refs anywhere).