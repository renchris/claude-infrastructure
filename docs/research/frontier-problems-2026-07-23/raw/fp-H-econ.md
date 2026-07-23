<!-- source: /Users/chrisren/.claude-secondary/projects/-Users-chrisren-Development-claude-infrastructure/73e65906-646e-4a64-a899-4e2cdbbc62e0.jsonl
 turns=50 assistant_texts=9 last_stop=end_turn mail_injections=[] -->

Verified: all 4 account dirs are **real & distinct** (225/301/133/120 project subdirs; only `.claude-next` is the symlink) — the 24B/97.2% figures are not double-counted. Three findings locked: (1) **249,281 cache-read tokens per assistant turn average** — the dominant cost base; (2) **waiting-recycle: 538/538 records "abstained" — the recycle policy has NEVER fired**; (3) gate runs untimed, telemetry export has no latency field.

Running adversarial self-pass, then composing.

Adversarial pass integrated: (a) confirmed no double-count; (b) relabeled "handoff-successors" → fresh-context successors (can't prove exact read-duplication — flagged); (c) cold-reprocess is genuinely minor (0.11%) — that's the finding, not a gap; (d) wave end-to-end wall-clock remains unjoined — flagged, not fabricated; (e) the 97% hit rate is *good* — my point is the absolute 249K/turn base is the real lever and it's the least-measured.

---

# Economics of the claude-infrastructure context/time/token system

**Currency note:** operator is on Max subscription → real marginal $ ≈ 0 until quota/monthly-cap binds. The binding currencies are **quota-tokens** (5h/weekly/Fable %) and **wall-clock**. $ figures below are Opus list-equivalents (context, not spend). All numbers computed from the 4 real account dirs (`~/.claude{,-secondary,-tertiary,-quaternary}/projects`; `.claude-next`=symlink, excluded), 7-day window unless noted.

## (a) Economics table

| Loss source | Measured? (cite) | Magnitude (computed / unmeasured) | Lever |
|---|---|---|---|
| **Per-turn carried-context base** (the real cost) | Partial — tokens in transcripts; nothing aggregates cost/turn | **249,281 cache-read tok/turn avg** (23.4B ÷ 93,905 turns); 23.4B cache-read tok/wk = 97.24% of all input-side | Context trim / recycle — but see rot-policy row |
| **Cold-reprocess (TTL-expiry re-cache)** | Event **detected transiently** (`cache-expiry-warning.sh:21`), **never logged/priced** | **98 events, 27.1M re-cache tok/wk = 0.11% of input-side**; ×1.15 = 31.2M input-equiv (~$94 Sonnet / ~$468 Opus list-equiv) | idle-gap-aware TTL/keepalive — but token value tiny (see FP-5) |
| **Session-startup context load** | No — derivable from 1st-turn usage | **485 sessions/wk × mean 53,718 tok = 26.1M tok/wk** fixed restart tax (median 47K, max 106K) | fewer cold starts / lighter system+CLAUDE.md prefix |
| **Recycle re-orientation** | No — derived here; nothing measures it | **185/491 sessions (38%) are fresh-context successors**; median **236,710 re-cache tok in first 5 turns**; **59.3M tok/wk** total; **time-to-first-edit median 619s**, max 6,434s; 33% never edit in-window | measure it → weigh against rot (missing half) |
| **Recycle-decision policy validity** | Inputs logged (`idl.jsonl` burn_x100/forecast_min/used_pct/conv_age), **outcomes never** | **538/538 waiting-recycle records = "abstained" → policy has NEVER fired**; thresholds 35/50/75 are operator-asserted (`context-econ-2026-07-20.md:3-7`), zero prod validation | shadow-fire logging + outcome telemetry |
| **Model-generation wall-clock** | No — latent in transcript ts | median **8.4s/turn, p90 47s, p99 151s**; **~6.6h/3d on ONE account** (n=1226) → ~50h/wk fleet-wide | account routing by latency (missing input) |
| **Bash tool wall-clock** | Logged w/o duration (`log-bash.sh` = cmd+exit only) | median 2.5s, **p90 17.2s, max 591s**; 159 min/3d/1acct | timeout tuning; parallelization |
| **Gate-run wall-clock** (tsc/lint/bats) | **No** — `task-quality-gate.sh:221-222` uses `timeout` guard, never records duration | unmeasured | wrap gate w/ ts delta → log |
| **Wave end-to-end wall-clock** (spawn→all-done) | **No** — pieces exist (idl.jsonl spawn/complete events + task ts), unjoined | unmeasured | join spawn↔completion ts |
| **Quota false-cliff** (wave > concurrency) | Post-hoc (git `bef587a`) | 28-item backlog false-cliffed **every tick**, stranded ALL work while next4 at 0% 5h | fixed: slice wave to MAX_SPAWN |
| **Quota false-limit** (transient poll → hard-cap) | Post-hoc (memory `reference-claude-accounts-tooling.md:55`) | 2 accounts "rate-limited" + build "quota-stalled" when all 4 at 0-24% | fixed: `claude-accounts:530-533` |
| **Monthly-spend cap (no reset)** | Reactive only (`team-recovery…md:26`) | teammates died mid-wave; **no reset** — credit overflow dead until manual | model reset-time as scheduler input (missing) |
| **Statusline refresh / hook latency** | No (export has no latency field) | unmeasured (sibling owns hook-latency detail) | EPOCHREALTIME entry/exit log |

## (b) Computed numbers — commands & basis

**Cache distribution (7d, 4 real accounts)** — python3 over `~/.claude*/projects/*/*.jsonl`, `message.usage` summed, filtered `timestamp ≥ now-7d`:
- input-side total **24,073,107,141 tok**; cache_read **97.24%** (23.41B) · cache_create **2.75%** (661.7M) · raw-input **0.01%** (2.6M); output 167.2M; **93,905 assistant turns**.
- Per-model: opus-4-8 = 83,351 turns (20.5B read); fable-5 = 10,296 turns (2.89B read); haiku 113; opus-4-7 2.
- **Cache hit rate is already excellent (97.24%)** — cache hygiene is NOT the problem.

**Cold-reprocess detector** — per-file ts-ordered usage series; event = `cache_create>15000 AND gap-since-prev-turn>300s` (session idle → TTL expiry → full re-cache; context can't grow while the session's own turns are idle):
- **98 events / 27,119,563 re-cache tok**. Gap buckets: 5-10m=28ev/4.45M · 10-30m=19ev/6.71M · 30-60m=7ev/2.22M · 1-2h=12ev/3.35M · >2h=32ev/10.39M.
- Keepalive-favorable (gap<~52min crossover: `floor(G/4.5)·0.1x < 1.15x`): **5-60min = 54 ev / 13.4M tok** recoverable; >1h (44 ev/13.7M) → batch-at-wake (accept re-cache). **Idle-gap-aware scheduling saves ≤15.4M input-equiv/wk ≈ $23-231 list-equiv — <0.1% of spend.** Verdict: not worth building for tokens; real value is latency + nag-noise.

**Handoff/recycle succession** — first human turn matched handoff/continuation-bridge regex; first-5-turn usage + time-to-first-Edit from ts:
- **185 successors / 491 sessions (7d)**; median re-cache first-5-turns **236,710 tok**, in-side **294,236 tok**; **total 59.3M tok/wk**; time-to-first-edit median **619s** (10.3 min), max 6,434s (107 min); **61/185 (33%) never edited in-window**; orientation Read/Grep/Bash calls in first ≤5 turns range 22-107.
- *Caveat (adversarial):* label = "fresh-context successor loading a bridge/brief" (includes fired teammates + research subagents, not only desk self-handoffs). Exact read-**duplication** vs predecessor is **UNMEASURED** (needs pair-linking by slug/branch). Wall-clock (619s) and load (237K) hold regardless of label.

**Cache-expiry hooks — what they actually do:** `cache-expiry-tracker.sh` (Stop) = `date +%s > .last-interaction` (one timestamp). `cache-expiry-warning.sh` (UserPromptSubmit) = if `now-last>300s`, emit `additionalContext` nag (model-only). **Neither logs, aggregates, nor prices.** The nag says "reprocessed at uncached rate" for an event that is **~$0 real / <0.1% of spend / ~4/day fleet-wide** — measurement-free reaction to a mis-scaled problem. (This very session opened with that nag.)

## (c) Unified-scheduler inputs — exist vs missing

**EXIST today (readable now):**
- Per-session context fill% + input_tokens over time — `/tmp/cc-telemetry/<sid>.json` + `.hist` (fields: `used_pct`, `input_tokens`, `window`, `ts`; **no latency field**).
- Per-account quota headroom — `claude-accounts --json --rank` (5h/weekly/Fable %).
- Recycle **decision inputs** — `idl.jsonl` (`burn_x100`, `forecast_min`, `used_pct`, `conv_age`).
- Wave placement — `cc-wave-plan` greedy-decrement over accounts (fixed to slice ≤MAX_SPAWN, `bef587a`).
- Full token accounting — transcripts `message.usage` (post-hoc only).
- Supervisor sweep duration — `sweep_s` in idl.jsonl (the ONE wall-clock any tool records).

**MISSING (blocks a unified scheduler):**
1. **Cache-warmth as a live signal** — no per-session time-to-TTL-expiry exposed; the hook reacts at the next prompt (cache already gone). Can't do "act on X, cache expires in 40s" or "batch idle sessions at wake."
2. **Wall-clock/latency telemetry** — no tool-duration, gate-duration, model-latency, or wave-wall-clock aggregation (all latent in transcript ts; nothing reads them). Scheduler is blind to time → will mis-route to a token-cheap but slow account.
3. **Recycle outcome telemetry** — idl logs the decision, never the result; no feedback loop → 35/50/75 thresholds untunable (and never fired: 538/538 abstained).
4. **Re-orientation cost model** — nothing estimates the ~237K-tok/619s successor tax to weigh against rot → recycle decision is one-sided.
5. **Rot cost function** — no decision-quality-vs-fill signal exists at all (pure assertion).
6. **Monthly-spend-cap reset-time** — modeled reactively; needs forecast as a first-class constraint (no reset → hard wall).
7. **Shared objective function** — 4 controllers (cache-expiry / waiting-recycle / wave-plan+dispatch / claude-accounts) optimize disjoint axes with no common cost model.

## (d) CANDIDATE FRONTIER PROBLEMS

**FP-1 — The recycle policy optimizes a one-sided, unvalidated ledger**
- **Evidence:** `idl.jsonl` 538/538 waiting-recycle records = "abstained" (never fired); thresholds asserted from operator intent `context-econ-2026-07-20.md:3-7`, doc self-reports "0/2419 prod fires" (line 80). Re-orientation cost side is now measurable (185 successors, 237K tok, 619s median) but uncomputed anywhere.
- **Mechanism class:** missing feedback loop / unfalsifiable control policy.
- **Current mitigations + status:** two-stage shadow-default arming, damp-first (built, `waiting-recycle.sh`); **never armed live** → zero outcome data.
- **Why it resists normal fixes:** "decision quality vs context fill" has no ground-truth label; a session can't be A/B'd against its own counterfactual; rot is invisible until it causes a wrong decision.
- **Quantified cost:** measurable side = 59.3M re-orientation tok/wk + median 10min/successor to first productive action; unmeasurable side (rot) = unbounded.
- **Frontier-fix sketch:** pair-link predecessor→successor (slug/branch); use re-work / decision-reversal rate as a rot proxy; enable shadow-fire logging to accrue the missing outcome half; only then tune thresholds.
- **Confidence + stale-risk:** High (disk-truth); stale-risk **medium** (arming --live would start generating fire data).

**FP-2 — The dominant cost (249K cache-read/turn) has one lever, the least-instrumented**
- **Evidence:** 23.4B cache-read/wk = 97.24% of input-side (python aggregate); **249,281 tok/turn avg** (23.4B÷93,905); all optimization attention (cache-expiry hooks) targets the 0.11% cold-reprocess tail.
- **Mechanism class:** measurement/attention mismatch — effort on the tail, not the base.
- **Current mitigations + status:** recycle policy is the only base-lever, and it's shadow-mode (FP-1); cache-expiry hooks target the wrong 0.11%.
- **Why it resists normal fixes:** trimming carried context risks losing needed state (correctness); no per-token "was this cached segment attended this turn?" signal exists to trim safely.
- **Quantified cost:** ~$0.37 Opus-list/turn of pure re-read × 93,905 turns/wk (context, not spend); this IS the spend base under a metered key.
- **Frontier-fix sketch:** context-utility attribution (which cached prefix segments were referenced per turn) → evidence-based trimming + breakpoint placement; feeds the recycle objective.
- **Confidence + stale-risk:** High (arithmetic from disk); stale-risk **low** (structural).

**FP-3 — Wall-clock is fully latent yet entirely underived → any token/quota scheduler mis-routes on time**
- **Evidence:** model-gen median 8.4s/p99 151s, ~6.6h/3d/1acct (derived from transcript ts); Bash p90 17.2s/max 591s; gate runs untimed (`task-quality-gate.sh:221` timeout-guard only); telemetry export has no latency field (statusline JSON = used_pct/input_tokens/window/ts).
- **Mechanism class:** latent-but-unread telemetry (the data exists; nothing joins it).
- **Current mitigations + status:** only `sweep_s` (supervisor) is recorded; sibling owns hook-latency detail; otherwise none.
- **Why it resists normal fixes:** neglect + no consumer — but a scheduler that ignores wall-clock piles work on a token-cheap, latency-slow account, inflating operator-perceived time.
- **Quantified cost:** ~50h/wk fleet model-wait + ~25h/wk Bash (extrapolated); wave wall-clock unmeasured.
- **Frontier-fix sketch:** `cc-timing` post-hoc aggregator over transcript ts (zero new instrumentation) → per-tool/per-gate/per-wave latency; feed a λ·wall-clock term into wave placement.
- **Confidence + stale-risk:** High (derived); stale-risk **low**.

**FP-4 — Four disjoint economic controllers, no shared objective function**
- **Evidence:** cache-expiry hooks (TTL) vs waiting-recycle (fill/burn, `idl.jsonl`) vs cc-wave-plan/dispatch (quota) vs claude-accounts (headroom) are separate mechanisms; the quota axis alone already mis-fired twice — false-cliff (`bef587a`: stranded whole backlog) and false-limit (`reference-claude-accounts-tooling.md:55`: all 4 at 0-24% read as capped); monthly-spend cap has no reset (`team-recovery…md:26`).
- **Mechanism class:** unintegrated controllers, each built per-incident.
- **Current mitigations + status:** each hardened in isolation (bef587a landed; false-limit guard `claude-accounts:530-533`); no unifier (a static planner is sketched in `SESSION_AUTONOMY_RESEARCH.md:284` but not a live joint controller).
- **Why it resists normal fixes:** unification needs one cost model spanning tokens + cache-warmth + quota + wall-clock + re-orientation — i.e. it's blocked on the missing inputs of FP-1/2/3.
- **Quantified cost:** each incident stranded a full wave/backlog; recurring-class per `W0-W3_INTERVENTION_AUDIT.md:171`.
- **Frontier-fix sketch:** unified scheduler, objective = min(token-equiv + λ·wall-clock) s.t. quota + monthly-cap-reset constraints, with recycle / keepalive / route / TTL-choice as joint decision variables.
- **Confidence + stale-risk:** Medium-high; stale-risk **medium** (a unified planner may be in-flight in autonomy research).

**FP-5 — Cache-warmth is a reactive nag, not a schedulable signal (honest low-value verdict)**
- **Evidence:** `cache-expiry-warning.sh:21` fires at the *next* prompt (cache already expired); nothing exposes per-session time-to-TTL as a live input; 98 cold events/wk, 13.4M keepalive-recoverable tok (5-60min gaps).
- **Mechanism class:** reactive-not-predictive signal.
- **Current mitigations + status:** the 2 timestamp hooks (cheap, harmless) + the model-only nag; no predictive exposure.
- **Why it resists normal fixes:** keepalive/act-before-TTL needs a live per-session countdown the harness doesn't surface; the 1-hour cache TTL (2× write) would cover the 5-30min bucket but is a harness flag, not per-session controllable.
- **Quantified cost:** **token value ≤$23-231 list-equiv/wk (<0.1% spend) — NOT worth building for tokens**; real value is eliminating ~4/day operator-facing nags + successor cold-start latency.
- **Frontier-fix sketch:** expose per-session TTL-countdown in cc-telemetry; let the scheduler batch idle sessions at wake or 1h-TTL the ones in the 5-30min band — but justify on UX/latency, not token savings.
- **Confidence + stale-risk:** High on the token math (verdict: low-value); stale-risk **low**.

---

**Blockers / uncertainties (explicit):**
- Exact predecessor→successor read-**duplication**: UNMEASURED (needs slug/branch pair-linking). Re-orientation *load* (237K) and *time* (619s) are solid; the *redundant* fraction is not isolated.
- Wave end-to-end wall-clock: pieces exist (idl.jsonl spawn/complete + task ts) but I did not join them — flagged, not fabricated.
- $ figures are Opus list-equivalents; real marginal $≈0 under Max until quota/monthly-cap binds. True currency = quota-% + wall-clock.
- Model-gen latency includes API queue + client processing, not pure generation (can't separate from ts alone).
- Handoff-successor set may include teammate/subagent briefs (economically equivalent — all pay the fresh-context tax — but not all are desk self-handoffs).