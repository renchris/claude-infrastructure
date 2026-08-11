---
status: closed
created: 2026-08-11
owner: desk
verdict: NO-ACTUATION-IS-ZERO
---

# Are we at 100th-percentile context economy? — NO

**Question.** Under the operator's stated policy — *no artificial context cap; keep context small via
understanding, handoff and self-recycling at optimal pause-points* — is this fleet at 100th-percentile
agent-system behavior?

**Method.** 13 agents, 0 errors, 2.17M subagent tokens, 515 tool calls, ~39 min (`wf_5e9f820e-438`).
Six axes, each followed by a skeptic tasked to refute its load-bearing claim, then this verdict.
Read-only. Per-axis evidence: [`context-economy-100p-2026-08-11/`](context-economy-100p-2026-08-11/).

| Axis | Rating | Skeptic | Findings |
|---|---|---|---|
| [`instrument`](context-economy-100p-2026-08-11/instrument.md) | NO | REFUTED | 15 |
| [`outcome-record`](context-economy-100p-2026-08-11/outcome-record.md) | NO | REFUTED | 12 |
| [`actuators`](context-economy-100p-2026-08-11/actuators.md) | NO | REFUTED | 20 |
| [`announced-not-fired`](context-economy-100p-2026-08-11/announced-not-fired.md) | NO | REFUTED | 12 |
| [`state-of-the-art`](context-economy-100p-2026-08-11/state-of-the-art.md) | NO | REFUTED | 14 |
| [`cost-model`](context-economy-100p-2026-08-11/cost-model.md) | PARTIAL | REFUTED | 12 |

---

# NO — the discipline is at 100th percentile and the actuation is at zero: every recycle in the recorded window was chosen by a model, not fired by the system, and three independently-sufficient blockers keep it that way.

**Scope of the answer.** The operator's policy has two halves — *understanding/doctrine* and *mechanism*. On doctrine this fleet is ahead of every harness surveyed. On mechanism it is advisory-only, and the deterministic rails that were built to make the decision unmissable have never once reached their fire condition. Today's good outcome (zero context deaths in 8 days) is real and is produced by model discipline, not by the system being proactive.

---

## What is genuinely best-in-class

Not manufactured humility — these are things nothing else surveyed does.

- **A pre-wall succession *policy*, not an overflow handler.** The three-way Recycle / Handoff / Hold table in `CLAUDE.md` § Session Close Protocol, with the Hold branch defined so its first action converts it into a Recycle. Codex CLI, OpenCode, OpenHands, Cursor and Amp all act only *at* overflow; none has a decision procedure before it. [MEASURED — repo read + vendor docs]
- **Offloading has three units and the biggest one charges work to a *different* window.** One dispatched `/handoff` session per implementation wave, lead retains ≥50%. Anthropic documents only subagent offloading (code.claude.com/docs/en/costs); `openai/codex#23218` is still *requesting* an agent-controlled task transition that `handoff-fire.sh` already has. [MEASURED]
- **A durable decision ledger for context events.** `~/.claude/autonomy/idl.jsonl` ≈ 48,800 rows, one record per hook evaluation, carrying hook · verdict · used_pct · trigger. No surveyed harness records context-management decisions at all; Claude Code itself records only `compactMetadata` inside the transcript. This is the instrument that made this whole audit possible. [MEASURED]
- **Deliberate anti-summarization on recovery**, with a harness-specific measured reason: `skills/resume-sessions/SKILL.md:104-110` always answers the large-session dialog with "Resume full session as-is" because option 1 runs `/compact` and drops the session-scoped `/goal` Stop hook. Field default is to accept the summary. [MEASURED]
- **The outcome distribution is healthy and improving.** Over 2,904 ended sessions in 30 days across all four accounts (instrument: JSON-parsed transcripts, occupancy = `input_tokens + cache_creation_input_tokens + cache_read_input_tokens`): median peak 190K, p95 558K falling to 433K over the last 7 days; deaths 5 sessions / 8 `Prompt is too long` events (0.17%), newest 2026-08-02, none in 8 days. Self-recycle rate rises 0.3% → 35.8% as peak occupancy climbs 100K → 800K, **and that survives a turn-count control** (holding assistant messages at 100–200: 0.3% → 1.7% → 30.0%), so it is not an algebraic restatement of session length. The agents really are recycling *because* they are full. [MEASURED]
- **Manual `/compact` is extinct** — 3 of 3,037 sessions carry an `isCompactSummary` record (0.1%). The fleet is not coping by summarizing. [MEASURED]

That last cluster is the fair reading of the operator's policy working: **detail is preserved, windows run to 400–800K without incident, and succession is by brief rather than by lossy summary.**

---

## The gaps, ranked by how much they threaten the stated policy

### G1 — Zero automatic actuation. The system is 100% "proactive as an agent", 0% "proactive as a system". *(the disqualifier)*

Three blockers, each sufficient on its own:

1. **`boundary-handoff.sh` — the only rail wired to every session — has fired 0 times in 1,341 evaluations over 296 distinct sessions.** Its complete abstain-reason set is `below-threshold` 845 · `team-assignee` 245 · `gate-not-green-at-head` 150 · `no-telemetry` 73 · `stale-telemetry` 20 · `dirty-tree` 10 · `no-cwd` 1. **Not one reason downstream of `hooks/boundary-handoff.sh:317` has ever appeared** — no `live-teammates`, no `latched`, no fire. Line 317 is `[ "$green" = "$head" ] || abstain "gate-not-green-at-head"`. I verified the marker live this turn: `gate-green` = `145fab7d`, `HEAD` = `699bbb74`, **62 commits apart**, and it lives in the shared common gitdir so every worktree reads the same stale value. The 150 records are all *past-threshold* sessions (the fill abstain fires earlier, at :286) — i.e. **eligible sessions, silenced by a marker only a background daemon can advance.** [MEASURED — idl.jsonl + 8 gz rotations; `git rev-list --count 145fab7d..HEAD` = 62, run this turn]
2. **`waiting-recycle.sh` fired 8 times in 34,097 evaluations (0.023%) and all 8 were advisory nudges, zero recycles.** 26,128 abstains are `not-armed`. Its arm-by-default keys on `$HOME/.claude/cc-roles/desk`, which does not exist; the only role file is an empty `orchestrator`. Its one auto-exec arm is keyed on `sha1("$CLAUDE_CONFIG_DIR|$CWD")` and the single live sentinel resolves to `~/.claude|claude-infrastructure` — a config dir **zero live sessions use** (live census: `.claude-secondary` 23, `.claude-quaternary` 11, `.claude-next` 7, `.claude-tertiary` 3, `~/.claude` 0). The pair that *is* used is explicitly disarmed, dated 2026-07-31T17:58:44Z — 118 seconds after the last successful auto-recycle. [MEASURED]
3. **Consequence, measured on the outcome not the mechanism:** `~/.claude/logs/handoffs.jsonl` records 8 `recycle-engaged` rows in the last 2.4 days; `recycle-events.jsonl` records **0 `executed`** over the same window. **8 of 8 recycles were agent-initiated.** The deterministic recycle has executed 3 times in the fleet's entire recorded history, none in the last 10 days. [MEASURED]

*Mitigating and worth stating:* when an advisory does reach a session, the session acts — 3 of the 8 busy-nudges are followed by an agent recycle within minutes. **The defect is reach, not persuasion.**

**Shortest fix:** one line at `hooks/boundary-handoff.sh:317` — demote `gate-green` from a hard abstain to a reported field. The precedent, the rationale and the policy citation are already written in the sibling: `scripts/wrap-ledger.sh:528-544` ("the land path structurally cannot move it … RUNG=✅ was UNREACHABLE in this repo for five days") citing `CLAUDE.md`'s own "waiting on a trunk-wide stamp you do not control is not diligence, it is a hang." The free-win arm landed in `boundary-handoff` the same day, into the un-fixed copy. Then either `touch ~/.claude/cc-roles/desk` or widen `waiting-recycle`'s arm past the desk role. **Effort: ~1–2 h.**

### G2 — Both rails key on fill% (tokens ÷ window); the hazard is an absolute token count.

The death band is a cliff, not a gradient: of 18 sessions reaching ≥800K peak occupancy, 4 died (22%); of the 4 reaching ≥950K, **4 died — 100%, no survivors**. "Deaths are 0.17%" averages a near-certainty over a population that almost never goes near it. Meanwhile `T=73` is 73% of a denominator the fleet cannot durably reconstruct, and I confirmed this turn that **neither hook contains any absolute-token axis** — `boundary-handoff.sh:105-106` has `SIZE_MB=25` and `RSS_MB=1500` but no `TOK_K`. The data is already in the row: a live telemetry record reads `"window":1000000,"used_pct":45,"input_tokens":445224` — occupancy is present, and matches used_pct exactly. [MEASURED — grep of both hooks + live `/tmp/cc-telemetry` read, this turn]

**Shortest fix:** add `TOK_K="${CC_BOUNDARY_TOK_K:-700}"` beside the existing size axis and fire on `.input_tokens ≥ TOK_K × 1000`, with a +50K re-arm dimension in the existing latch. Window-independent, telemetry-shaped data already written, no new producer. It would have been in range for 4 of the 5 deaths. **Effort: ~30 lines, ≤1 h.**

> 🚨 **G2's REMEDY IS REFUTED — do not implement `TOK_K`** (measured 2026-08-11 at implementation time).
> The *finding* above is true; the *remedy* does not follow from it. Live census of `/tmp/cc-telemetry`:
> **47 of 47 sessions run `window=1000000`, and `used_pct` equals `input_tokens ÷ window` in all 47**
> (0 rows off by >2 pp; highest live occupancy `used_pct 70 / input_tokens 702450`). With a uniform
> window, `TOK_K=700` **is** `used_pct=70` — the "new absolute axis" is an algebraic restatement of the
> existing one, and `T=73` is strictly *stricter*: it fires at 730K, **before** the 800K death band.
> `boundary-handoff.sh:52` had already recorded this exact objection to `input_tokens` ("an algebraic
> restatement of used_pct, NOT a size signal"), and the analysis above re-derived past it.
>
> **The deaths were never a threshold problem.** `T=73` would have fired for every one of them. They
> died because the rail could not fire *at all* — `gate-not-green-at-head` suppressed it, which is G1.
> Fixing G1 covers the death band; `TOK_K` would add a second name for the same trigger and a second
> thing to keep in sync. *(Generalisable: a true statistic beside a wrong cause manufactures
> corroboration — cf. memory `wrong-cause-corroborated-by-true-metric`. The distinguishing question was
> one command: are the windows actually uniform?)*
>
> Revisit only if a heterogeneous window appears here — and note a 200K-window session would hit `T=73`
> at 146K absolute, early but harmless, since this rail only ever advises.

### G3 — There is no net at the ceiling, and it was switched off against the fleet's own ratified decision.

`"autoCompactEnabled": false` is set in **all five** settings roots — I read them this turn (`~/.claude`, `.claude-next`, `.claude-secondary`, `.claude-tertiary`, `.claude-quaternary`) — and is shipped in `settings-templates/settings.example.json:14`. The running binary's default is `true`. The repo's own decision record says the opposite: `docs/research/SESSION_AUTONOMY_RESEARCH.md:138` D-F — *"Never disable auto-compact (survival backstop)"*. `autoCompactWindow` (documented range 100,000–1,000,000, a **brake position, not a window size** — exactly the lever the operator's policy permits) is set nowhere. [MEASURED, this turn]

**Caveat that changes the fix's shape:** compaction is lossy summarization, which cuts against "without losing important details", and the fleet's own panel measured that *"imperfect recycle WITH a handoff brief strictly dominates certain 90% auto-compaction WITHOUT one"* (`desk-self-handoff-2026-07-19/panel-findings.md:63`). So auto-compact is the **last-resort net beneath** the G2 mechanical recycle, not a substitute for it. Set `autoCompactWindow` at 850–900K so the token arm at 700K always fires first, and add a `# Compact instructions` section to `CLAUDE.md` (currently absent) so a compaction that does run preserves the frozen DoD, the open decision and the landed shas. **Effort: <1 h, reversibility ~1.0.** Resolve the UNKNOWN below first.

### G4 — Instrumentation: live reads are fine; *retrospective* and *failure-case* reads are blind.

Two corrections to the brief's premises, both load-bearing:

- **Live fill is not the problem the ground truth implies.** The harness supplies `context_window.used_percentage` directly; `statusline.sh:63-64,134` merely copies it. No window arithmetic happens at decision time. Measured on the fleet's own decision log: `boundary-handoff` reached the telemetry read in 187 of 246 evaluations and only **10 (5.3%, 3 of 53 sessions)** were telemetry-blind — and 9 of those 10 are one requeuing session. `waiting-recycle` independently reads 88% fresh at decision time (96 `fresh=1` vs 13 `fresh=0`). An instant snapshot of live processes shows 45% stale, but that population is dominated by idle sessions — writer (TUI redraw) and reader (Stop / PostToolUse) share the same turn boundary, so the signal is freshest exactly when it is read. **The "45% blind" framing is refuted.** [MEASURED]
- **The genuine residuals are three, and all are cheap.** (a) *No stale fallback:* both hooks hard-abstain above `AGE_MAX=180`, while a sibling already built the substitute — `scripts/lead-supervisor.sh:552-560` `transcript_age()` explicitly replaces telemetry age with transcript mtime — and it is simply not wired in (~40 lines). One live case: a session with a 4-second-old transcript and a 602-second-old row. (b) *Retrospective denominator is gone:* the window is in no transcript and no SessionStart hook, and the durable store built to preserve it — `recycle-events.jsonl`, 2,545 rows — is **98.8% bats-fixture records** (2,515 rows, sids `s1..s7`/`b1..b11`/`fw1`, every one `window:null`) written into the live store by tests. Fix: point the suites at `CC_WR_STATE_DIR`, and have `statusline.sh` upsert one durable `{sid, window, model}` line per session. (c) *The failure this axis exists for is structurally invisible:* `emit_recycle_event` runs inside the detached `__recycle` re-exec (`handoff-fire.sh:650-668`), so a session that dies **before** invoking `handoff-fire` leaves no row of any class. Fix: emit an `intent` row at entry — one line, and the announced-vs-fired rate becomes measurable within a week.

*On "announced but never fired":* the failure is real but the memory index's transcript signature has a **~50% false-positive rate** — of 4 candidate cases inside the fire-log window, 2 were successful recycles whose firing turn was never flushed (`/exit` kills the process first). Headline: 150 sessions wrote a successor brief, 112 (75%) followed with a `handoff-fire` call, 38 did not, 14 end at the brief's tool_result — and that 14 is an upper bound contaminated ~2:1. The claimed "20,864-token escape cost" is **refuted**: that measures the `/handoff` *skill*, which the disposition table assigns to the Handoff row; the Recycle row's command is `handoff-fire.sh --recycle`, and an 83-byte payload passes every gate. There is no cheap *sanctioned* one-call recycle documented, which is worth adding (`--carry-dod`, composing the payload from disk as `waiting-recycle.sh:1102-1129` already does), but it is a convenience gap, not the mechanism of a death.

### G5 — The repo publishes a number that argues for the cap the operator just rejected.

`docs/research/memory-econ-rearchitecture-2026-08-10/session-cost.md:114` ranks disabling the 1M window as the **#1 lever**, score 0.95 reversibility, worth "−274 MB of ceiling / −4.1 GB of tail", on a coefficient of 0.343 MB per K-token. That coefficient does not reproduce: a causal probe (fresh process, real token loads, same `vmmap --summary` instrument) measured 0.045–0.060 MB/K-token, a within-session fixed-effects panel measured 0.098–0.147, and today's live fleet over-predicts the highest-token session by 216 MB (81%). The published figure is an **RSS-shaped** coefficient (rss slope 0.302 vs footprint slope 0.019 in the same panel) fitted on an age-matched cohort where the window variable had **zero variance** (all 21 sessions at 1,000,000). Left uncorrected, a future session will re-derive the cap recommendation from it. **Effort: correct 4 line-references, ~30 min.**

---

## Shortest path to 100th percentile, ranked by (gain × reversibility) / effort

| # | Change | File:line | Gain | Rev. | Effort | Why it ranks here |
|---|---|---|---|---|---|---|
| 1 | Demote `gate-green` from hard abstain to reported field | `hooks/boundary-handoff.sh:317` | Unblocks the fleet-wide rail's *only* untaken path; 150 eligible evals in 3 days | 1.0 | 15 min | One line; the fix, rationale and precedent are already written in `wrap-ledger.sh:528-544` |
| 2 | Add absolute-token arm `TOK_K=700` | `hooks/boundary-handoff.sh:105` | Covers 4 of 5 historical deaths; window-independent | 1.0 | ~1 h | Data already in the telemetry row (`input_tokens`); parallels the existing size axis |
| 3 | Emit an `intent` row at `handoff-fire` entry | `scripts/handoff-fire.sh:~650` | Makes announced-vs-fired measurable for the first time | 1.0 | 15 min | Until this lands, no claim about recycle compliance is verifiable in either direction |
| 4 | Arm `waiting-recycle` for real sessions (`touch cc-roles/desk` or widen the gate) | `hooks/waiting-recycle.sh:205,402` | Converts 26,128 `not-armed` abstains into evaluations | 0.9 | 30 min | Resolve the 2026-07-31 disarm UNKNOWN first — it may be a deliberate rollback |
| 5 | `autoCompactEnabled: true` + `autoCompactWindow: 875000` + `# Compact instructions` | 5 × `settings.json`, `CLAUDE.md`, `settings.example.json:14` | Last-resort net in the 57%-mortality band | 1.0 | <1 h | Restores the fleet's own D-F decision; brake *position*, not a cap — gated on the UNKNOWN below |
| 6 | Stale-telemetry fallback to transcript mtime | `boundary-handoff.sh:196`, `waiting-recycle.sh:621` | Closes the live-but-blind case (602 s row on a 4 s transcript) | 0.9 | ~40 lines | The substitute is already built and running in `lead-supervisor.sh:552-560` |
| 7 | Point bats suites at a fixture store; durable `{sid,window}` index | test suites + `statusline.sh:129-138` | Ends 98.8% test pollution; restores the retrospective denominator | 1.0 | ~1 h | Makes every future audit cheaper; no runtime behaviour change |
| 8 | Correct the 0.343 MB/K-token coefficient and the G7 row | `session-cost.md:55,60,114,163`; `memory-econ-…md:259` | Removes a standing recommendation to do the thing the operator rejected | 1.0 | 30 min | Pure documentation; prevents re-litigation |

Items 1–3 are ~90 minutes total and move the system from *zero* automatic actuation to *some*, plus the ability to measure whether it worked. **Do them as one wave.**

---

## Adjudicating the rejection of a static 200K cap

**The operator is correct, and the evidence is stronger than the case they made — but the reason in the brief is wrong and must be replaced.**

- **The window *setting* costs 0 MB.** Interleaved A/B probe, 4 reps each, identical prompt/model/cwd, peak `vmmap` physical footprint: 1M-eligible = 190.5 MB mean (186.9 / 193.7 / 191.7 / 189.6); `CLAUDE_CODE_DISABLE_1M_CONTEXT=1` = 192.9 MB mean (192.9 / 192.8 / 191.5 / 194.2). The **capped** arm is nominally *higher*, inside a 7 MB within-arm spread. There is no preallocation by window size. [MEASURED — own probe]
- **So a cap can act only by bounding tokens, and bounding tokens is worth ≤45 MB per session** — the entire prize from 1M all the way to zero, at the causally-measured slope. Moving the recycle threshold across the whole 30–60% band is worth ~110 MB across a 16-session fleet: **0.17% of 64 GiB**. Machine state at measurement: 12.6 GB free + 22.8 GB inactive, **0.00 M swap in use**. Memory is not a binding constraint anywhere on this curve. [MEASURED]
- **The brief's own premise — "recycling discipline and a static cap reach the same memory outcome by different means" — is false in both directions.** A cap cannot reclaim the dominant variable term (per-session activity residue, +7 to +118 MB, median +53, which tracks neither age nor tokens); only a process restart does, and a recycle *is* exit-then-relaunch (`handoff-fire.sh:5877`). But equally: **recycling is not a memory lever either.** Σ footprint over the live fleet is 4.49 GB, ~62% of it a per-process floor a fresh single-turn process already pays (188–202 MB). The whole above-floor term is ~1.6 GB against 34.5 GB of reclaimable headroom.
- **The decisive argument is capability, not megabytes.** The terminal failure — `Prompt is too long` — is a pure token-count event with zero memory content, and a 200K cap would *increase* its frequency by five-fold-ing the handoff rate while destroying the "high-signal detail up to 1M" the policy exists to protect. **The memory cost model should be retired from this decision, not re-fitted.**

One honest caveat: the 27–45 MB context term at a *full* 1M window is **extrapolated, not measured** — nothing on this box has been observed above 679K / 68% fill, and the probe was refused at 300K. The direction is certain; the last significant figure is not.

---

## What remains UNKNOWN, and the cheapest measurement for each

| Unknown | Why it matters | Cheapest resolution |
|---|---|---|
| **Why `autoCompactEnabled` was set to `false`** — no rationale anywhere in the repo; `git log -S` returns only checkpoint noise | Gates item 5. If the reason is real (e.g. compaction dropping session-scoped `/goal` hooks, which `resume-sessions:104-110` documents for the resume path), the fix is a high `autoCompactWindow`, not a naive flip | Ask the operator — 1 question. Failing that, one headless probe with it enabled at an 875K brake |
| **Why the `~/.claude-next\|claude-infrastructure` auto-recycle was disarmed 118 s after the last successful fire** | Decides whether item 4 is safe or is re-opening a known wound | Same: one operator question, or read the session transcript at 2026-07-31T17:56–17:59 |
| **The true announced-vs-fired rate** — `emit_recycle_event` landed ~2 days ago and runs *inside* the detached re-exec, so the whole failure class is invisible | This is the fleet's own named memory entry; nobody can currently say if it is 1% or 25% | Item 3 (intent row at entry), then read one week of `handoffs.jsonl` |
| **Whether the ~0.1% of sessions that reach ≥880K are rescued by anything at all** — 4 of 7 died there | The only band where mortality is not near-zero | Falls out of items 2 + 5 within a week |
| **The 5-vs-7 death count discrepancy** (strict `isApiErrorMessage` classifier finds 5 sessions / 8 events; `CONTEXT_ECONOMY_V2` reports 7 / 10) | Small, but it is the fleet's headline safety number | Re-run the strict classifier over archived/deleted transcripts; ~20 min |
| **What the +7…+118 MB per-session activity residue is, and whether a recycle actually clears it** | The only memory term worth anything; currently a residual, not a measurement | One `vmmap --summary` before and after a single `handoff-fire.sh --recycle`; ~5 min |
| **Whether `/tmp/cc-telemetry/*.hist` (61 per-session fill trajectories since the last boot) is supported or accidental** | It is the best trajectory data on the box and nothing consumes it | `rg` for a consumer; if none, wire it into `cc-ctx-audit` |

---

**The one-sentence form.** The doctrine, the succession architecture and the decision ledger are genuinely at 100th percentile and ahead of every comparable system; the actuation layer is not at the 50th — three rails exist, all three are correctly deployed and byte-identical to HEAD, and **not one of them has ever fired a recycle**, so the fleet's excellent outcome is the models obeying a well-written rule, with nothing underneath it if they stop.