<!-- source: /Users/chrisren/.claude-secondary/projects/-Users-chrisren-Development-claude-infrastructure/e99a935d-77e5-4531-9c95-a084038e210e.jsonl
 turns=61 assistant_texts=8 last_stop=end_turn mail_injections=[] -->

Saturation reached. Final falsifiability check: reading the remaining large plans (ORCHESTRATOR_DESK_24X7, SESSION_AUTONOMY_PLAN) would surface more "staged-but-inert" items — predictable, maps to root-cause-1, wouldn't change the ledger or candidates. **Stopping exploration** (~29 tool calls, ~120K context). Composing.

---

# Prior-Art + In-Flight Ledger — frontier-problems investigation

**Every claim labeled `[MAIN]` / `[branch:X]` / `[checkpoint-ref]` / `[transcript]` / `[live-fs]`.** Base = checkout @ `ef7f7a4` == origin/main.

## (c) FRONTIER-HARD-2026-07-20 WHEREABOUTS — verdict FIRST (Q3)

**Verdict: PRODUCED-BUT-SYNTHESIS-STRANDED. 13/13 axis reports exist; the ranked portfolio was drafted but never committed; nothing landed to main; FRONTIER_HOLES.md never integrated.** This is itself a live instance of root-cause-1 (last-mile landing gap) + the `wave-report-harvest-from-disk` strand class in MEMORY.

| Artifact | Where it actually is | Reachable? |
|---|---|---|
| 13 axis reports (`fr-01`…`fr-13`, minus `fr-08`) + `BRIEF.md` + `SHEPHERD-NOTES.md` | **Dangling checkpoint ref** `refs/checkpoints/claude-infrastructure/20260720T082438Z` = commit `38c6efb` (count=111, wave-completion tip) `[checkpoint-ref]` | `git branch --contains 38c6efb` = **empty**; no branch head contains them. Recoverable only via the checkpoint ref. |
| Reports are REAL (not stubs) | `fr-02-liveness` = 135 lines w/ full ranked-rows + "Could not determine"; `fr-11-context` = 182 lines `[checkpoint-ref]` | Confirmed substantive |
| `SYNTHESIS.md` (the DoD deliverable #1) | **Nowhere in git** — `git log --all -- '**/SYNTHESIS.md'` = empty `[all-refs]` | Never committed |
| Fable synthesizer's portfolio WORK | Stranded in **3 transcripts**: `7728e86e` (1.18MB), `489d1192` (1.02MB), `e99a935d` (356KB) — each carries synthesis signatures (generator-leverage / why-frontier / SYNTHESIS.md) `[transcript]` | Exists but invisible to anyone reading the repo |
| `frontier-synthesis` branch (the synthesizer's designated branch) | `refs/heads/frontier-synthesis` = `4052d02`, **0 commits ahead of main**; tree carries only an **unmodified** `FRONTIER_HOLES.md` `[branch:frontier-synthesis]` | Created-from-main, never advanced — an empty strand |
| FRONTIER_HOLES.md integration | `[MAIN]` has ONLY the 07-19 desk-self-handoff holes (H-DSH-1/2, C-DSH-1/2). **Zero** 07-20 frontier-hard holes. | Never integrated |
| 65 transcripts reference `frontier-hard-2026-07-20` `[transcript]` | wave agents + shepherd + successor | — |

**Recovery path for the synthesizer (you/lead):** `git show 38c6efb:docs/research/frontier-hard-2026-07-20/<fr-NN>.md` gives all 13 reports directly; the drafted portfolio prose is in transcript `7728e86e`/`489d1192`. The wave's intellectual output is NOT lost — it is unlanded. **This means the current investigation is a re-synthesis of an already-run 13-axis wave, not a first pass.** The 13 axes + the predecessor's T-A…T-G theses (below) ARE prior frontier-problem identification — treat them as the baseline to add delta against.

## (a) MASTER PROBLEM LEDGER

Statuses: **landed** (sha on main) · **parked** (on unlanded branch) · **staged-inert** (built, not activated live) · **regressed/stale-on-main** · **open**.

| # | Problem | First identified | Status | Evidence |
|---|---|---|---|---|
| P1 | **Last-mile activation/deploy gap — the failure GENERATOR**: fixes land + go gate-green then never take effect (unlinked files, unloaded plists, staged-not-`.done` scripts, daemons running pre-fix code) | `[MAIN]` desk-audit theme A (07-18); re-measured `[branch:infra-reliability-audit]` root-cause-1 | **open (structural)** | `infra-audit synthesis.md` RC1; **39 tracked files unlinked live** (v1-verified 07-23: 18 scripts/12 bin/8 hooks/1 cmd); MEMORY `deploy-lag-checkout-behind-origin` |
| P2 | **Activation itself caused a regression**: reap-guard activation flipped `teammate-auto-shutdown.sh` 100755→**100644 (DISARMED)** at the exact mtime of `01-reap-guard-insert-activate.sh.done`; also uncommitted (`git checkout` reverts it) | `[checkpoint-ref]` `fr-02-liveness` §3 (07-20) | **open, P0** | `fr-02` tail: "reap-guard activation disarmed the reaper it was hardening"; `[live-fs]` `~/.claude/autonomy/pending-activation/01-*.done` present |
| P3 | **Liveness/identity verified on the wrong key** (pane-UUID/pid-slot/name/mtime/process-pattern, not sessionId×live-CC×real-turn); in-place recycle defeats the checks | `[MAIN]` desk-audit theme F + G-P3/P5 (07-18); formalized `[branch]` root-cause-3 | **parked** (fixes on branches) + **open** | `handoff-fire.sh:1049` (any-node match), `:1044` vs `:681-690` (verify→close 180s TOCTOU); a2/a7/v1 |
| P4 | **Detection ≠ delivery ≠ actuation**: every watcher ends in a disk record no one reads; desk never woken with contrary evidence | `[MAIN]` desk-audit theme B (07-18) | **open** | `synthesis.md` theme B; G-P2-1/2-3/5-3 |
| P5 | **Prose-load-bearing invariants**: failure-critical rules (content-verify, land-lock, engagement-verify, DoD-carry, mailbox-drain) enforced by decaying model attention, not code | `[MAIN]` desk-audit theme C (07-18); T-B `[checkpoint-ref]` BRIEF | **partial** (some code-enforced) + **open** | theme C; SHEPHERD-NOTES law-composition defect (completion-assert × handoff disposition nag-loop) |
| P6 | **Per-session resources, no lifecycle owner** (memory leaks): 21GB `/tmp/claude-501` TMPDIRs, 85MB idl.jsonl, 93 watchdog pidfiles (83 stale), 34/43 worktrees leaked, unbounded transcripts/session-index | `[MAIN]` K01/K04 register; quantified `[branch]` root-cause-2 | **open** | `synthesis.md` RC2 table (all v1-verified) |
| P7 | **Unguarded hot paths / SPOFs**: `lead-supervisor.sh:452-467` ZERO timeout guards (one hung `git/find` ends all supervision, −9 observed); per-session watchdogs unsupervised, no singleton (1 death logged ≤5×) | `[branch:infra-reliability-audit]` root-cause-4 (07-22) | **parked/open** | `synthesis.md` RC4; a8/a13; V6 (no launchd KeepAlive → "absence is the alarm" has no reader) |
| P8 | **Operator-felt "crash to shell" — re-diagnosed 3×** (see box below) | `[MAIN]` OOM theory (07-22, superseded); `[branch]` version-regression (corrected) | **stale-on-main** | see crash box |
| P9 | **2-way comms message-loss**: live-idle-no-watcher (dominant receive-loss), crash-stranded boxes (only graceful path writes `.forward`), name-keyed boxes bypass guard (+285 unacked); **78% of all mail unacked (1,401)**, 0 armed watchers at survey | `[MAIN]` HANDOFF_BACKCHANNEL (07-10) → cross-session-mail v3 (07-20) | **parked** (v1/v2 landed, v3 open) | `cross-session-mail-2026-07-20.md` verdict; `session-continue.sh:93-96` vs `:156-170`; MEMORY `cross-session-mail-v3` |
| P10 | **Worker-liveness-blind claim ledger (V1)**: cc-dispatch claims under the cron dispatcher's pid (exits in seconds) → `claimer_live` ~always false → age-only reaping; live 91-min worker double-dispatched, dead-at-min-5 strands 85min | `[branch:infra-reliability-audit]` V1 (07-22) | **open** | `cc-dispatch:58,261`; `cc-backlog:357-359,420,447-448` |
| P11 | **Session sprawl → machine RAM exhaustion**: recovery resurrected **39 live sessions / 8.8GB RSS / 60MB free RAM / 24GB swap** | `[MAIN]` SESSION_SPRAWL plan (07-21) | **landed/DONE** (one-session-per-worktree) | `SESSION_SPRAWL_CONSOLIDATION_PLAN.md` (status: complete) |
| P12 | **Context-economy recycle timing** (value-blind mid-conversation recycle; free-win-when-idle; pause-point-before-rot) | `[MAIN]` context-econ (07-20) | **landed** (waiting-recycle tiers) + refinements open | `context-econ-2026-07-20.md`; MEMORY `context-econ-recycle-policy` |
| P13 | **Deterministic desk self-recycle actuation** (arm step was model-diligence → 0/2419 fires) | `[MAIN]` FRONTIER_HOLES H-DSH-1/2 (Fable panel 07-19) | **SOLVED-PATH-KNOWN**, core built `[branch:feat/desk-self-handoff-trigger]` | `FRONTIER_HOLES.md:20-36`; MEMORY `desk-self-handoff-trigger` |
| P14 | **Autonomy spine staged-not-loaded** (dispatcher/discovery built but launchctl-inert) | `[MAIN]` MEMORY `desk-autonomy-dormancy` | **partially resolved** — `01/02/03-*.done` present `[live-fs]`; **04–09 still un-`.done`** | `~/.claude/autonomy/pending-activation/` |
| P15 | **P8 registration ruling OPEN-unacked**; SessionStart spine conditions unverified across 5 mirrored config dirs | `[MAIN]` P8-GO ruling (07-14) | **open-unacked** | `docs/rulings/P8-GO.md:3` "status: OPEN — unacked" |
| P16 | **Skill deployment economics**: `pyramid-principle-full` spent 1M+ tokens (uncapped input body + rework loop) | `[MAIN]` pyramid-deployment (07-20) | **landed** (execution contract in SKILL.md) | `pyramid-deployment-2026-07-20.md` |
| P17 | **Content→action trust boundary** (T-D): worker-authored text → desk actuation / fired prompts / `--run` commands / memory, no provenance typing anywhere | `[checkpoint-ref]` BRIEF T-D + `fr-08` (07-20) | **open** (fr-08 report stranded) | BRIEF T-D; SHEPHERD-NOTES feeds T-B/T-D |
| P18 | **Adversarial completeness verification** (T-E): every completeness defense routes through the compromised model's own judgment/phrasing (opt-in continuation loop; tool-blind `/goal` evaluator) | `[MAIN]` desk-audit a19 D-1..D-12; T-E `[checkpoint-ref]` BRIEF | **open** | BRIEF T-E; a19 escapes |

### Crash re-diagnosis (P8) — 3 distinct theories, DON'T re-litigate as one frontier problem
- **(a) Giant-transcript single-process OOM** — `[MAIN]` `session-crash-diagnosis-2026-07-22.md` ("per-session bloat → single-process OOM", 520MB peak RSS, jetsam-oom). **SUPERSEDED.** Demoted to defense-in-depth (invariant I5).
- **(b) CC 2.1.207 vendor version regression** — `[branch:handoff-memory-review]` `handoff-memory-review-2026-07-22.md` + MEMORY (corrected): crash rate by version 0.02%→4.76%→4.76%→1.56%, 100/100 mid-Bash, median 1.27MB, jetsam-zero. **Primary lever = pin CC to 2.1.183.** SOLVED-PATH-KNOWN, **unlanded** (correction lives only on branch + MEMORY; main still shows theory (a)).
- **(c) Session-sprawl RAM exhaustion** — `[MAIN]` SESSION_SPRAWL (P11). **DONE.**
- **Steer:** crash-elimination is NOT a frontier problem — it's a version pin (external) + a DONE sprawl fix + demoted OOM. Don't propose it as a Fable-class item.

## (b) BRANCH LEDGER (unlanded feature branches; counts = `git rev-list main..<branch>`)

| Branch | Purpose | Goal-axis | State | Stranded-risk |
|---|---|---|---|---|
| `docs/infra-reliability-audit-2026-07-22` (11) | The 15-agent audit doc + crash forensics code (session-end GC, crash-watchdog claude_version, claude-latest stderr tee, deploy-parity-assert) | crash / memory / silent-failure | **complete-unlanded** | **HIGH** — carries the corrected crash doc + forensics this whole investigation leans on. **Supersets** `feat/handoff-memory-review` (shares its 9 SHAs `b026894..65d533b` + adds `e78d31d`,`fe52c1f`). Landing BOTH separately = the dfacccd double-land pattern. |
| `feat/handoff-memory-review` (9) | Crash forensics subset (false-crash pidfile reap, stderr capture, rm-race guard, session-end straggler GC) | crash / memory | **subsumed** by the audit branch | **MED** — its 9 commits are ancestors of the audit branch; land via the superset, not independently |
| `feat/autonomy-100` (14) | Autonomy-to-100% drive + class-C escalation packet + board dogfood | silent-failure / autonomy | **complete-unlanded** (worktrees `wt-autonomy-100`, `.worktrees/autonomy-crux`) | **MED-HIGH** — largest feature branch; touches board/escalation that `board-runnable-commands` also touches → semantic conflict + drop risk |
| `feat/board-runnable-commands` (19) | Operator Board renders `▶ run` by construction + `cc-blockers --lint` fail-closed | silent-failure / operator-surface | **complete-unlanded, PARKED for operator land** (MEMORY `cc-blockers-board`, `feedback-silver-platter`) | **MED** — overlaps cc-blockers/board with autonomy-100 |
| `feat/two-way-session-comms` (10) | 2-way comms + `limit-recover` skill | 2-way comms | **complete-unlanded** | **HIGH** — literally the branch family of the **2026-07-11 dfacccd incident** (sibling land dropped `dfacccd`); verify by CONTENT not count before landing |
| `feat/desk-dispatcher` (2) | L4 dispatcher spine (backlog-pull→quota→spawn) | autonomy | **mostly-landed** (dispatcher activated: `02-load-dispatcher-*.done` `[live-fs]`) | **LOW** |
| `frontier-synthesis` (0) | Designated Fable synthesizer branch for the frontier-hard wave | frontier-synthesis | **STRANDED-EMPTY** — 0 ahead, no SYNTHESIS.md ever committed | **N/A** (nothing to strand — the strand IS the missing synthesis) |
| `feat/session-scoped-close` (ahead-1) · `fix/reaper-desk-registration` (ahead-1) | close-rung vocab lint · desk-scoped stale-row heal | silent-failure | small-unlanded | LOW |

**Two REF-ACCUMULATION GC classes (themselves instances of P6):**
- **`ship/backup-*` refs** (~40+, 1–57 commits each, e.g. `ship/backup-1a27b1d`=57) — auto-snapshots from `/ship`. Never GC'd. `[all-refs]`
- **`refs/checkpoints/*`** (hundreds; per-worktree-name-scoped) — autosave commits; **also the SOLE home of the stranded frontier-hard reports.** `[all-refs]`
- **`wt-*` tracking branches** (~15, duplicate feature-branch tips) + 228 total `git branch -a`. Worktree list shows **34/43 worktrees fully merged yet un-pruned** (matches RC2's "34/43 leaked").

## (d) CANDIDATE FRONTIER PROBLEMS (add delta against these — they are the re-synthesis baseline)

**FP-1 — Fleet-wide truth layer: liveness/state inferred from mendacious indirect signals**
- **Evidence:** `[branch:infra-audit]` root-cause-3 ("liveness verified on the wrong key"; `handoff-fire.sh:1049` any-node match, `:1044` verify→close TOCTOU); `[MAIN]` FRONTIER_HOLES C-DSH-1 (07-19, "event-sourced attestation with causal stamps"); `[checkpoint-ref]` BRIEF T-A + `fr-02-liveness` (undecidable residue); MEMORY `desk-read-transcript-before-asserting-WHY` (3 wrong causal claims from indirect signals in one day).
- **Mechanism class:** distributed-state observability — every component proves alive/dead on a key that survives identity change; no shared attestation substrate.
- **Current mitigations + status:** per-check patches (reaper self-check, fixed-HEAD monitors, birth-grace gates) — all point-fixes; C-DSH-1 primitive **designed, not built**; each patch spawns a new seam (census: supervisor oscillation, reaper-UTC, false-cliff, registration-blindness).
- **Why it resists normal fixes:** it's a cross-cutting ontology gap, not a bug — SHEPHERD-NOTES shows two *individually-correct* mechanisms (completion-assert × handoff disposition) composing into a false nag-loop because no shared ownership/delegation model exists. Patching one key just moves the lie to the next key.
- **Quantified cost:** unmeasured directly; proxies — supervisor IDL window 9,660 DEAD : 418 STALL? : 415 ESCALATED (`fr-02`); 20/42 registry rows stale; **how to measure:** count monthly false-page + false-reap incidents attributable to key-mismatch (grep IDL for STALL?→alive reversals).
- **Frontier-fix sketch:** one SID/cwd-keyed write-before-act attestation record `{state, ts, DoD, lifecycle, OWNER}` maintained by poll-loop + fire-hook + recycle-watcher (C-DSH-1 extended with SHEPHERD-NOTES' OWNER field) → makes whole false-inference classes *unrepresentable*. Generator-class: dissolves ≥8 named holes.
- **Confidence + stale-risk:** HIGH (multiply-cited, converged across 2 Fable panels + 2 audits). Stale-risk LOW — structural, integers drift but phenomenon is stable.

**FP-2 — Last-mile activation/deploy gap (the meta-generator that silently disarms every other fix)**
- **Evidence:** `[branch:infra-audit]` root-cause-1 (**39 files unlinked live**, v1-verified); `[checkpoint-ref]` `fr-02` (reap-guard activation **disarmed** the reaper, mode 100644); `[live-fs]` pending-activation 04–09 un-`.done`; `[MAIN]` MEMORY `deploy-lag-checkout-behind-origin` (2 mechanisms: checkout-behind-origin + brand-new-file-never-symlinked).
- **Mechanism class:** deployment/config-substrate — live `~/.claude` = per-file symlinks into a branch-checkout working tree; 5-way settings replication; plists authored-not-loaded; daemons hold pre-fix code.
- **Current mitigations + status:** `link-live.sh`, `deploy-parity-assert.sh` `[branch:infra-audit]` — **not adopted into the ff-sync flow**; activation is C10 operator-gated and manual.
- **Why it resists normal fixes:** it converts "fixed" → "still broken" for *every* other fix, including its own fixes — the reap-guard case proves activation can itself regress. A fix that isn't shipped-with-activation just joins the list.
- **Quantified cost:** 39 unlinked files; K39 log-rotation "fixed" but live-inert → idl.jsonl 85MB (183MB historic); lead-deathwatch/reconciler dormant. **Measure:** unlinked-file count per ff-sync (already scriptable via the RC1 sweep).
- **Frontier-fix sketch:** a compiled, versioned, atomically-switched config/deploy layer (BRIEF T-G) — repo→live is a build artifact with a symlink+launchctl+restart manifest, gate-asserted; no partial-activation states representable.
- **Confidence + stale-risk:** HIGH. Stale-risk MED (file counts drift daily; the *class* is durable).

**FP-3 — Prose-law → substrate enforcement compiler**
- **Evidence:** `[MAIN]` desk-audit theme C ("prose the model can skip under rot"); `[checkpoint-ref]` BRIEF T-B ("invariants enforced by model attention, which decays — injection-channel law"); SHEPHERD-NOTES (a binding law enforced by a matcher that doesn't share the law's ontology → composition deadlock).
- **Mechanism class:** rule-enforcement gap — binding invariants live in CLAUDE.md/design-law prose; enforcement is model-attention, not a deterministic channel.
- **Current mitigations + status:** the failure-critical five are *partly* code-enforced (land-verify, payload-lint, engagement-verify); most invariants remain prose. No enforced-vs-prose ratio measured (fr-07 was to deliver it — report stranded in checkpoint).
- **Why it resists normal fixes:** you cannot fix "the model skipped a rule" with another rule the model can skip; needs a rule→actuator compiler that marks every binding rule as {has-deterministic-channel | explicitly-advisory}.
- **Quantified cost:** unmeasured — **how to measure:** enumerate CLAUDE.md binding rules, classify each as hook/gate/test-backed vs prose-only, report the ratio (fr-07's intended deliverable).
- **Frontier-fix sketch:** compile each binding rule to a hook/gate/test or explicitly tag advisory; couple with T-E's machine-readable DoD + tool-using independent judge for completeness rules.
- **Confidence + stale-risk:** MED-HIGH. Stale-risk LOW.

**FP-4 — Per-session resource lifecycle with no owner (the GC franchise)**
- **Evidence:** `[branch:infra-audit]` root-cause-2 (21GB TMPDIRs / 93 pidfiles / 34-of-43 leaked worktrees / 78% unacked mailboxes); `[MAIN]` SESSION_SPRAWL incident (39 sessions/8.8GB/zero-free-RAM); `[MAIN]` cross-session-mail v3 (1,401 unacked, 0 watchers).
- **Mechanism class:** resource lifecycle — every session mints ~7 resource kinds (mailbox, registry row, watchdog+pidfile, worktree, TMPDIR, transcript, markers); GC exists only where an incident forced one.
- **Current mitigations + status:** cc-reaper (partial, pane-scoped), session-deregister **staged-inert** (K20, un-`.done`), SESSION_SPRAWL recovery-consolidation **landed**. No sweeping GC franchise.
- **Why it resists normal fixes:** no single owner or shared lifecycle record; each store patched independently after its own incident → the next store leaks silently until *its* incident.
- **Quantified cost:** 21GB `/tmp` + 8.8GB peak session RSS + 85MB idl + 1,401 unacked mail — all measured. This is the strongest-quantified axis.
- **Frontier-fix sketch:** one sweeping reaper with per-store adapters keyed off FP-1's attestation record (a resource dies when its owning SID's lifecycle record closes) — couples GC to the truth layer rather than to age heuristics.
- **Confidence + stale-risk:** HIGH (best-measured). Stale-risk MED (numbers move; the no-owner structure is durable).

**FP-5 — Principled autonomous succession under a page-only authority ceiling**
- **Evidence:** `[checkpoint-ref]` BRIEF T-C ("supervisor PAGES never acts × human-absent-by-design = orchestrator death unrecoverable BY LAW", a17 S-1); `[MAIN]` FRONTIER_HOLES C-DSH-1 + H-DSH-1/2 (recycle actuation solved, succession-*fidelity* open); `[MAIN]` context-econ (succession theory: verified knowledge-carry, two-tier inversion above 80%).
- **Mechanism class:** autonomy/authority formalism — C10 ruling (self-mod/persistence = human-only) makes autonomous respawn a law-violation surface; verified mission-carry across the death boundary is unsolved.
- **Current mitigations + status:** deterministic self-*recycle* core built `[branch:feat/desk-self-handoff-trigger]` (H-DSH-1/2, shadow-default); crash-path succession (no graceful chain) **open** — the a5 S1 mail-strand applies exactly here.
- **Why it resists normal fixes:** the constraint is a *law*, not a bug — a succession rail must provably NOT self-widen authority (consent delegated for WORK, never persistence) while still surviving unplanned death; that's a formal-verification-shaped problem.
- **Quantified cost:** unmeasured — **how to measure:** count orchestrator-death events with unrecovered mission (grep for desk gaps > watchdog interval with no successor engagement).
- **Frontier-fix sketch:** C10-compatible respawn where the successor *proves* mission-possession (DoD-carry attestation, again FP-1's record) before predecessor exit; crash-path `.forward` on ALL replacement paths.
- **Confidence + stale-risk:** MED (succession-fidelity less evidence than FP-1/2/4; recycle-actuation already solved). Stale-risk LOW.

**Adjacent, lower-confidence (fr-08 report stranded → thinner evidence):** FP-6 content→action trust boundary / provenance typing (T-D, P17); FP-7 adversarial completeness verification (T-E, P18). Both are real per the BRIEF but their primary axis report (`fr-08-collapse`, adversarial) is the one axis **missing** from the checkpoint tree — flag as a genuine evidence gap for the synthesizer.

## Blockers / uncertainties (named)
- **Which transcript is the Fable synthesizer's** (vs shepherd/successor) not confirmed by reading — I inferred from size + 8 synthesis-signature hits on `7728e86e`/`489d1192`. The *material demonstrably exists in transcripts*; exact session attribution is open.
- **fr-08-collapse absent from the checkpoint tree** — either never landed to that checkpoint or produced later; the adversarial axis (P17/P18 evidence) may be recoverable only from a wave-agent transcript.
- **Did not deep-read** ORCHESTRATOR_DESK_24X7_PLAN (49KB), SESSION_AUTONOMY_PLAN (72KB), the 11 remaining fr-* reports, or W0-W3/SESSION_AUTONOMY_RESEARCH bodies — the desk-audit G-* ledger + RC1–RC4 + BRIEF theses already saturate the problem space (falsifiability test: predicted more staged-inert items = RC1 pattern, wouldn't change ledger). Named here as an explicit scope boundary.
- **Branch counts** are `main..branch` (unlanded), not content-diffs — per the dfacccd lesson, the lead must verify overlapping branches (infra-audit ⊃ handoff-memory-review; two-way-comms family) **by content** before landing.