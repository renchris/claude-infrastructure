# P7 — Orchestrator-Desk: Roadmap / Intent / Activation-State Report

**Beat:** the design's own account of itself — designed autonomy end-state (L3→L4, W0–W5 arc) vs
delivered vs staged-awaiting-human. **Method:** read every in-scope doc fully, then VERIFIED each status
claim against live wiring (`~/.claude/settings.json`, `launchctl`, plist internals, `~/.claude/bin`
symlinks, runtime logs, git). **Verdict up front:** the docs *understate* the core-actor activation
(reaper/supervisor/hooks are LIVE, not "awaiting activation") and are *honest* that the L4 self-initiating
loop is unbuilt. The system today = a **largely-activated SAFETY harness for human-initiated waves**, NOT
yet a **self-originating 24/7 operator**. Empirical (verified) vs doc-claimed is flagged throughout.

---

## 1. Inventory — one row per in-scope doc

| Doc | What it decides/designs | Status claims it makes | Verified-in-repo? | Gap ref |
|---|---|---|---|---|
| `docs/L3-L4-AUTONOMY-ROADMAP.md` | Levels (L3 supervised / L4 closed-loop-no-SDK); 2 halt-classes; P0×2→100th-pct L3; P1–P2→L4 loop | "LIVE — committed 2026-07-17; both P0 DELIVERED, branch `feat/autonomous-lifecycle`, **awaiting land**; activation = C10 human-only" (§3,71,86,107) | **PARTLY STALE.** Work LANDED to main (feat/autonomous-lifecycle ⊆ main); reaper+supervisor+rm-hook+P8 **ACTIVATED**. Cited shas (`ef7b997`,`20d3f89`,`0d98384`) are pre-rebase, **not in main** (sha-drift) — reaper verified live by CONTENT (runs=113). | G-P7-4 |
| `docs/plans/SESSION_AUTONOMY_PLAN.md` | The platform-scale charter + full status log: telemetry-v2, boundary-hook, supervisor, never-wait L0–L4, reaper-birth-grace, comms F1–F5, Track-B B1a–d + wiring-all v2 | Nearly all sub-charters "DONE + RED-proven + LANDED"; "Remaining = ACTIVATION ONLY, C10 human-only" (475,553-564,627-635,707-715) | **VERIFIED built+landed**; activation is **SPLIT**: core actors LIVE, runtime-loop integrations STAGED (see §3). | G-P7-1,6,7 |
| `docs/research/SESSION_AUTONOMY_RESEARCH.md` | The blueprint: 7 invariants, 7 design decisions (D-A..D-G), per-primitive spec §3.1–3.11, revised Phase-0 wave order, risk register, blockers | "convergence of 14-axis research"; each primitive cited to axis+R#/D# | **VERIFIED as design.** Some specced primitives UNBUILT: axis c gate-batching (§3.4), axis k auditability/cc-idl (§3.6), axis d cc-wave-plan (§3.7). | G-P7-3,8,9 |
| `docs/research/W0-W3_INTERVENTION_AUDIT.md` | The empirical 24/7-blocker catalog: §1 relays, §2 designed gates + authority ceiling (§2b→C10), §3 rescues, D1–D10 detectors, §9 zero-HITL re-derivation → R-1..R-4 floor | "DoD substantially MET on W4 (`b242789`); residual = R-1..R-4, must NOT be driven to zero" (581,791) | **VERIFIED as ground-truth doc.** The R-1..R-4 floor is real & load-bearing (harness-enforced C10). W4 verdict is doc-claimed (doc_classifier repo, read-only, not re-run here). | §6 |
| `docs/proposals/W4-W5-SESSION-ORCHESTRATION.md` | Filled §8 session-layer instance for doc_classifier W4/W5 (E1–E9), manual-mode-today | "Proposal, manual mode today; upgrades as primitives land"; caveats list unbuilt deps | **VERIFIED as proposal.** Its own caveats (66-75) confirm cc-wave-plan/boundary-hook/gate-green/readiness = unbuilt at write-time; still true. | G-P7-2,8,9 |
| `docs/proposals/C00-SECTION-8-TEMPLATE.md` | Blank §8 template (session-orchestration layer above C00 teammate layer) | template artifact | Not re-read in full (companion to W4-W5); referenced by research §3.11. | — |
| `docs/activation/wiring-all.sh` | THE consolidated C10 bundle: §1 verify, §2 auto-symlinks, §3 effect-check, §4 PRINT templates ①–⑧ for the human | "RUN BY THE HUMAN'S HAND; never loads launchd / edits hook / touches permissions" (2,15) | **VERIFIED.** §2 symlinks done (all present exc cc-idl/cc-wave-plan); §4 templates ①②③④⑤⑥ **NOT installed** (see §3). Unknown if wiring-all.sh itself was run vs piecemeal scripts. | G-P7-6,7 |
| `docs/{AUTONOMOUS-REAPER,D2-RUNTIME,NEVER-WAIT,COMMS-SAFETY,REAPER-SAFETY,RM-SAFE}-ACTIVATION.md` | Per-subsystem C10 runbooks; each = agent built+tested, human runs the activation | each: "C10 human-only; the agent NEVER activates" | **VERIFIED.** RM-SAFE + AUTONOMOUS-REAPER + D2 = human HAS run (live evidence §3). NEVER-WAIT/COMMS/REAPER-SAFETY runtime steps = NOT run. | §3 |
| `docs/rulings/P8-GO.md` | The C10 precedent: orchestrator CONDITIONAL-GO for P8 DENIED by harness (peer-agent ruling ≠ user intent); AMENDMENT-1 voids the class | "CODE COMPLETE; ACTIVATION BLOCKED ON HUMAN; classifier is RIGHT" (48) | **VERIFIED + SUPERSEDED by reality:** P8 `session-register.sh` IS now wired in live SessionStart → operator ran `/tmp/p8-activate.sh` after this ruling. | G-P7-4 |

---

## 2. The design narrative (levels · milestones · decisions · rejected alternatives)

### 2.1 Levels & the frame
- Frame: Boris Cherny "Steps of AI Adoption"; self-assessed **~80th-pct L3 (Supervised autonomy, ~100 agents)** (ROADMAP:4).
- **L3 bottleneck is MECHANICAL, not trust** — the loop breaks on **halts**: (1) permission prompts (`deny>ask>allow`; a broad `ask` shadows any `allow` → only lever is narrow/remove the ask or a PreToolUse hook), (2) idle lingering sessions (handed-off leads don't self-close; teammates auto-reap, leads do not) (ROADMAP:11-24).
- **100th-pct L3 = kill every halt → monitor-by-exception, not by-interruption** (ROADMAP:14,26).
- **L4 = the OPERATING MODEL (closed loop, self-initiating, steer-by-intent, monitor-by-exception) WITHOUT the SDK** — literal L4 (1000s of agents via SDK) is unreachable on 4 Max accounts; the operating mode is reachable at 4-account scale (ROADMAP:38-48). Constraint (4 Max accounts, no SDK, no at-cost API) caps agent COUNT, not MODE (ROADMAP:6-9).

### 2.2 The closed loop (the L4 signature — the end-state) — ROADMAP:50-54
5 pieces: durable **backlog** → **dispatcher routine** (cron-woken, pulls items, checks quota, spawns teams) → **workers that run without halts** (needs §2 P0) → **verify+merge gate** (autonomous land on green, queue red) → **discovery feed** (standing critics / frontier-hole sweeps refill the backlog). *"The discovery feed is the true L4 signature: most work originates from Claude, not the operator."* **← This entire spine is UNBUILT (G-P7-5).**

### 2.3 Build order & milestone status — ROADMAP:62-107
- **P0 — rm PreToolUse hook + allow-list sweep** (M1, `hooks/rm-safe-allowlist.sh`) — **DONE + LIVE**.
- **P0 — autonomous session-lifecycle reaper** (M2, `bin/cc-classify`+`cc-reaper`+`cc-teardown`) — **DONE + LIVE**.
- **P1 — dispatcher routine + durable backlog** (the "Claude kicks off Claude" spine) — **UNBUILT**.
- **P1 — verify+merge gate** (autonomous land) — **PARTIAL** (land-lock/`/ship` exist; no dispatcher-driven autonomous gate).
- **P2 — discovery feed + overnight quota-aware batch + morning digest** — **UNBUILT**.
- Roadmap's own honest line: *"P0×2 → 100th-pct L3 (both DELIVERED). P1–P2 → the L4 build (next)."* (ROADMAP:69).

### 2.4 The W0–W5 arc (empirical spine, from the audit + plan status log)
- **W0–W3** (doc_classifier, ~24h, 2026-07-13/14): ran with far more human-in-loop than the 100th-pct bar — **10 hand-run `/context`+`/accounts` relays** (AUDIT §1:38-49), the **2.3× gauge false-relief** (163b5ffa relieved at "95%" while /context read 47%, AUDIT §3b:152-161), 3/3 handoff-closed-without-opening (FIXED). Root causes **R1–R7** (AUDIT §5:547-554). Ground-truth for the whole track.
- **Wave-2 design research** (14 axes a–m + j1/j2 adversarial) → the blueprint (`581b75a`).
- **prove-on-W4** (2026-07-14): the docs-first primitives deployed live; **cc-board caught the W4 lead at 63%>boundary_recycle=60** — the exact catch the operator used to make by hand (RESEARCH §4:381-387). **W4 verdict: DoD substantially MET — operator slept the wave, §1 relays→0 §3 rescues→0, authority ceiling held** (AUDIT §6:581).
- **W5** + Track-B (never-wait, reaper-birth-grace, comms F1–F5, B1a–d) built 07-14/15.
- **§9 zero-HITL re-derivation:** under the operator's zero-HITL DoD (`fea9200`), touchpoints T1–T8 eliminated/reclassified; residual = **R-1..R-4 floor** (C10 self-mod · C6 money-path · permission-ceiling · un-pre-signed intent) which by §2b **must NOT be driven to zero** — it is the safety rail (AUDIT §9:744-796).

### 2.5 Key decisions + WHY (RESEARCH §1–2)
- **7 invariants:** (1) verify the EFFECT never the report/keystroke/spawn/config; (2) fail-loud/abstain never fail-silent-open + **the Blind-Check Law** (a check that can't observe what it guards ≈ no check; its signature = a human quietly doing its job by hand); (3) advisory never blocking, boundary-gated; (4) plan-time schedule primary, runtime telemetry advisory; (5) the metric is paired (four zeros); (6) **THE AUTHORITY CEILING — the autonomy layer may not widen its own autonomy** (→ C10, human-only, harness-enforced); (7) **ONE ARTIFACT, ONE ROLE** (evidence vs hygiene/addressing/amendability → deletion keys on AGE not failure-state; a view HIDES never DELETEs; an attestation binds by CONTENT not name).
- **Design decisions D-A..D-G** (RESEARCH:131-140): docs-first→prove-on-W4→runtime-to-residual (D-A); **supervisor PAGES, never auto-recovers** (D-B, operator ruling #1); boundary-hook = `decision:block`+one-shot-latch, additionalContext probe-gated (D-C); **supervisor = launchd KeepAlive daemon, NEVER a standing Claude session** (D-D); teardown split TaskStop(in-session)/it2-close(supervisor) (D-E); `AUTOCOMPACT_PCT_OVERRIDE=90` (D-F); 3 ironic-failure guards non-negotiable (D-G).

### 2.6 Explicitly REJECTED alternatives (the brief asked for these)
| Rejected | Why | Cite |
|---|---|---|
| **Blocking Stop hook** for the close protocol | banned anti-pattern (infinite-loop; can't see scope; a hard stop mid-slot kills productive work — fixtures-b2 ran >1h past red-100% & completed) → hook is ADVISORY, boundary-gated, one-shot-latched | RESEARCH inv-3:59-62; AUDIT §4:538-541; CLAUDE.md Session-Close |
| **Supervisor auto-recovery** (auto-respawn/auto-close) | ruling #1: PAGES + checkpoint-preserve only; a naive actor keyed off the audit's own lying D1–D7 signals can CAUSE a W0-class incident; age can NEVER confirm a stall (hung vs healthy-long-turn emit identical zero signal) | RESEARCH D-B:134, §0:17; AUDIT §3h/D10:649 |
| **Standing Claude session as supervisor** | burns ~144 turns/day + recursively needs its own handoff + who-watches-the-watcher regress → launchd daemon terminates the regress | RESEARCH D-D:136 |
| **Age-based deletion of telemetry/registry rows** | Invariant-7: the reaper erases exactly the evidence of the failure (stall/spawn-death) → deletion keys on AGE, liveness on pid, view filters | RESEARCH inv-7:88-111; AUDIT §3h:320-330 |
| **Trusting the send** (NOTIFY best-effort) for load-bearing rulings | the submit-verifier was INERT 24h; delivery≠processing → BIND: durable ruling file + `Acked-Ruling:<id>@<sha>` content-bound merge gate; absence-of-ack is the only verifier-free failure detector | RESEARCH §3.5:243-252; AUDIT §3g:222-267 |
| **Agent self-activation of hooks/daemons** | C10 authority ceiling — a peer-agent ruling is not user intent; harness auto-mode DENIED P8 wiring (correctly) | P8-GO.md; AUDIT §2b:89-125 |

---

## 3. THE WIRING TABLE — LIVE vs STAGED-awaiting-human vs UNBUILT

Legend: **LIVE** = verified running/wired now · **STAGED** = built (+ often symlinked) but the human runtime-integration step is not done · **UNBUILT** = no code.

| Subsystem | Designed behavior | State | Evidence (verified) / which human step remains |
|---|---|---|---|
| **M1 rm-safe hook** | PreToolUse auto-allow regenerable within-tree `rm`; ask still fires on `~`/`/`/`.git`/outside | **LIVE** | `~/.claude/settings.json` PreToolUse→`rm-safe-allowlist.sh`; symlink→repo (Jul 16). Design "activation C10" (ROADMAP:86, RM-SAFE-ACTIVATION.md) → **human HAS run**. |
| **M2 cc-reaper** | launchd 5-min sweep; reap ONLY handed-off-lead/finished-teammate that's work-landed+idle≥settle, checkpoint-first, double-gated | **LIVE + actively sweeping** | `com.chrisren.cc-reaper` plist `ProgramArguments=… cc-reaper sweep --reap`, StartInterval 300, **runs=113 last-exit 0**; log: 5-min `mode=REAP … 0 reaped` (correct conservative default). |
| **cc-classify / cc-teardown / cc-sessions** | 7-cause classifier; effect-verified teardown actuator; registry enumerator | **LIVE (symlinked)** | all symlinked ~/.claude/bin→repo; cc-reaper depends on them and runs clean. |
| **D2 supervisor** | launchd KeepAlive daemon; PAGE-only; DEAD→checkpoint-preserve+page; heartbeat+abstention to IDL | **LIVE + functional** | `com.claude.lead-supervisor` **pid 17867**, plist `lead-supervisor.sh --daemon` RunAtLoad+KeepAlive; **IDL 2026-07-18T10:30:11Z real `page`/`checkpoint`/`heartbeat` records** (DEAD-lead → checkpoint-preserve → page = ruling #1 exactly). |
| **D2 boundary-hook** | advisory Stop hook; fire at committed∧green∧≥T, one-shot-latched, log abstentions | **LIVE but INERT** | settings.json Stop→**repo** `hooks/boundary-handoff.sh` (symlink Jul 15); logs abstentions to idl.jsonl (B-3 done). **`.git/gate-green` ABSENT → abstains 100%** (D2-RUNTIME-ACTIVATION.md:46-55). Marker-writer B2 UNBUILT → hook can never fire → **R2 not closed in prod** (G-P7-2). |
| **P8 session-register** | SessionStart registry spine (pid/start/paneUUID/session_id) before first render | **LIVE** | settings.json SessionStart→`session-register.sh`; `live-session-registry.sh` also wired. Operator ran `/tmp/p8-activate.sh` (P8-GO.md:69) after the C10 denial. |
| **Never-wait L1 deathwatch** | kqueue EVFILT_PROC event-instant death → capture-before-page | **STAGED** | `bin/cc-deathwatch-kqueue` symlinked; **no `com.*.lead-deathwatch` in launchctl** → `--watch` loop not installed (NEVER-WAIT-ACTIVATION.md:14; wiring-all ④). |
| **Never-wait L2 wait-contracts** | disk contract before blocking; `--sweep` pages dead-waiter open contracts | **STAGED** | `bin/cc-wait` symlinked; **supervisor sweep does NOT call `wait-contract-lint --sweep`** (grep = 0 hits). |
| **Never-wait L3 heartbeats** | `cc-run` output-keyed beat; monitor beat-mtime freshness | **STAGED** | `bin/cc-run` symlinked; no beat-freshness monitor wired. |
| **Never-wait L4 reconciler** | 3-way roster reconcile (tasks×registry×telemetry) → page the divergent pair | **STAGED** | `scripts/lead-reconciler.sh` present; **supervisor sweep does NOT call `lead-reconciler --once`** (grep=0). ⇒ the 77-min-strand incident class is NOT actually closed in prod (G-P7-6). |
| **Reaper birth-grace** | `reap-guard.sh` DEFER within N-min of spawn / no-products; abstention record | **STAGED** | built + selftest; **NOT inserted into live `teammate-auto-shutdown.sh`** (grep=0). wiring-all ⑤. |
| **Comms F1 cc-announce** | role→resolve→cc-notify VERIFIED→retry→LOUD alarm | **LIVE (symlinked)** | `bin/cc-announce` symlinked. |
| **Comms F3/F4/F5** | payload-lint back-channel block · exit-adaptive deadlines · completion-push | **STAGED** | scripts built (wiring-all §1 selftests them); **NOT wired into `handoff-fire.sh`** (grep=0). COMMS-SAFETY-ACTIVATION.md; wiring-all ⑥. |
| **cc-teardown permission** | `Bash(cc-teardown:*)` allow for delegated live-session teardown | **STAGED (human /permissions)** | **absent from allow-list** → the supervisor's DELEGATED recovery arm still prompts (FM2 leak, G-P7-7). wiring-all ③. |
| **Track-B cc-respawn / cc-route** | spawn-boundary GO machinery · live-read model/effort routing | **LIVE (symlinked)** | both symlinked; selftests referenced green in wiring-all §1. |
| **B1-d limit-reset poller** | launchd poll → re-fire on limit reset (AUTOFIRE) | **STAGED** | **no `com.reso.lr-reset-poller` in launchctl** → not loaded. wiring-all ① (install + AUTOFIRE flip). |
| **never-stuck meta-gate** | hourly composition check onto the supervisor sweep | **STAGED** | `scripts/never-stuck-gate.sh` built; **not wired into supervisor sweep** (grep=0). wiring-all ②. |
| **Gate-batching (axis c)** | C1–C10 pre-signed ruling CLASSES + manifest + auto-stamp; closes R5 | **UNBUILT** | zero `gate-manifest/gate-classify/gate-stamp` files. `cc-bind` (per-ruling content-sha) exists but is NOT class pre-signing. RESEARCH §3.4:221-224. |
| **Auditability floor cc-idl/cc-audit (axis k)** | hash-chained IDL · dual-snapshot · four-zeros · **D9 abstained==100% alarm** | **UNBUILT** | zero cc-idl/cc-truth/cc-audit; idl.jsonl is **plain JSONL, not hash-chained** (fields ts/hook/sid/disposition/reason). Abstentions logged, nothing watches them (G-P7-3). RESEARCH §3.6:279-281. |
| **cc-wave-plan (axis d)** | wave-DAG × quota greedy-placement + Fable-window guard | **UNBUILT** | zero files. `cc-route` (per-slot) exists, not the wave planner. RESEARCH §3.7:283-284; W4-W5:66. |
| **L4 dispatcher + durable backlog** (P1) | cron-woken pull-items→check-quota→spawn-teams (the "Claude kicks off Claude" spine) | **UNBUILT** | **zero** dispatch/backlog tracked files. THE end-state gap (G-P7-5). ROADMAP:50-54,65. |
| **L4 verify+merge autonomous-land gate** (P1) | green→land unattended, red→queue | **PARTIAL** | land-lock + project `/ship` + content-verify exist; no dispatcher-driven autonomous gate. |
| **L4 discovery feed + overnight batch + morning digest** (P2) | standing critics refill backlog; quota-aware sleep-window batch; AM digest | **UNBUILT** | zero files. ROADMAP:56-60,67. |

**Why C10 is human-only, and what would make agent-run safe:** the harness auto-mode classifier itself
DENIES an agent editing `settings.json` / installing persistence on a *peer-agent's* authority — "not user
intent" (P8-GO.md:53-59; AUDIT §2b:95-98). It is the ceiling that stops the autonomy layer from
bootstrapping its own powers (a supervisor that installs its own hooks can widen them). **Nothing makes
agent-run safe by design** — the ceiling is *intentional and permanent* (C10 AMENDMENT-1: "stronger than
STOP-ASK: not desk-signable even with conditions", P8-GO.md:38-41). The only softening is D-i..D-v (AUDIT
§9.2:770-789): pre-stage each stop as a one-action artifact, and make the activation QUEUE
absence-is-loud (re-page an un-run activation — P8 sat ~90 min on stated-but-unexecuted verbal intent).

---

## 4. Gaps & fragilities

| id | file:line | FM | Pri | One-line failure scenario | Fix sketch |
|---|---|---|---|---|---|
| G-P7-1 | `~/.claude/autonomy/idl.jsonl` (live); `scripts/lead-supervisor.sh` | FM2/24x7 | P1 | Supervisor emits ~85 `page`+84 `checkpoint` records **per 30s sweep** (heartbeat `swept:111 findings:85`) — re-processing accumulated dead-registry rows; page-once dedup present only for wait-contracts (`wait-contract-lint` L2-c), not the DEAD-lead path. If pages fan out to the operator push channel → notification storm that DROWNS the real signal ("never let completion go silent" inverts to "everything screams"); + continuous git-checkpoint churn on ~84 dead worktrees. | Add a page-once marker keyed `sid+state` on the DEAD-lead path (mirror the wait-contract `paged_state`/`page_count`, escalate-at-3); cap/prune registry rows the supervisor re-checkpoints; verify pages don't push per-row. |
| G-P7-2 | `docs/D2-RUNTIME-ACTIVATION.md:46-55`; `hooks/boundary-handoff.sh` | FM1/24x7 | P1 | Boundary hook is LIVE but abstains 100% because the `.git/gate-green` marker-writer (blueprint B2) is UNBUILT → **R2 (the /context-relay DECISION side, the #1 operator pain) is NOT closed in production**; only the page-only supervisor B-1 case covers "past-threshold ∧ not-Stopping". | Build the marker-writer: on a green gate at commit/`/ship`, `git rev-parse HEAD > "$(git rev-parse --git-common-dir)/gate-green"`; then the hook fires and the relay→0 claim becomes true in prod. |
| G-P7-3 | `docs/research/SESSION_AUTONOMY_RESEARCH.md §3.6, §7 D9`; idl.jsonl | none/24x7 | P1 | Boundary hook LOGS abstentions (B-3 done) but **nothing monitors `abstained==100%`** — the exact class (inert-verifier) that hid the cc-notify failure for 24h. A future blind/inert detector goes unnoticed; the layer's own self-check is unbuilt. | Build cc-idl/cc-audit distribution monitor: count `{fired|passed|abstained|failed}`, alarm on `abstained==100%` over N≥10; the design already specifies it (D9). |
| G-P7-4 | `docs/L3-L4-AUTONOMY-ROADMAP.md:3,71,86,107`; `docs/rulings/P8-GO.md:48` | FM1(purpose-loss)/none | P2 | Roadmap says P0 "awaiting land / activation C10 human-only" but work LANDED + ACTIVATED; cited shas (`20d3f89`…) are pre-rebase, **not in main** → a future reader (or the desk itself) trusts a stale self-model of what's live, mis-plans, or re-does activation. | Update ROADMAP §6 + P8-GO status to ACTIVATED with content-verified evidence (runs=113, pid live, settings.json entries); per project CLAUDE.md verify landings by CONTENT (`git ls-tree`), never by sha/count. |
| G-P7-5 | `docs/L3-L4-AUTONOMY-ROADMAP.md:50-67` | 24x7 (the goal) | P1 | The L4 self-initiating loop (dispatcher + durable backlog + discovery feed + morning digest) is **entirely UNBUILT** → the system is a SAFETY harness for HUMAN-initiated waves, not a self-originating operator. The operator's stated end-state ("drive long-horizon work to 100.00, no human in loop") is BLOCKED on this P1–P2 spine. | Build the 5-piece loop (roadmap §3): backlog file/tasklist → dispatcher routine (`/schedule` cron) → quota-aware spawn → verify+merge autonomous gate → discovery-feed critics. Start with backlog+dispatcher (the spine). |
| G-P7-6 | `docs/NEVER-WAIT-ACTIVATION.md:13-16`; `scripts/lead-supervisor.sh` | FM2/24x7 | P1 | Never-wait L1–L4 built+symlinked but **runtime loops UNWIRED** (deathwatch `--watch` not in launchd; reconciler/`wait-contract-lint` not in supervisor sweep) → the 77-min-strand incident class (the incident-as-spec) is NOT closed in production — the tools exist, nothing runs them. | Human installs wiring-all ④ (C10): deathwatch launchd plist; add reconciler `--once` + `wait-contract-lint --sweep` + `never-stuck-gate` to the supervisor sweep; migrate `cc-await-ping` consumers to `cc-wait`. |
| G-P7-7 | `docs/activation/wiring-all.sh:115-118` (template ③) | FM2 | P1 | `Bash(cc-teardown:*)` absent from the allow-list → the supervisor's DELEGATED-recovery arm (D-E) still prompts → an idle-session standoff (FM2) cannot be closed by a delegated live session without a human OK (the 3-denial proof stands). | Human `/permissions` add `Bash(cc-teardown:*)` (harness-enforced C10). |
| G-P7-8 | `docs/research/SESSION_AUTONOMY_RESEARCH.md §3.4:221-224` | FM1/none | P2 | Gate-batching (axis c, C1–C10 pre-signed classes) UNBUILT → designed gates arrive UNBATCHED (R5 open); the zero-HITL "broaden pre-signed classes" lever (D-ii) has no mechanism → more items fall to R-4 human stops than necessary. | Build `gate-manifest.sh`+`gate-classify.sh`+auto-stamp trailer (`Ratified-By: operator (pre-signed class Cn)`); `cc-bind` is the per-ruling half already. |
| G-P7-9 | `docs/research/SESSION_AUTONOMY_RESEARCH.md §3.7:283-284` | 24x7 | P2 | cc-wave-plan (axis d) UNBUILT → a self-initiating dispatcher (G-P7-5) has no quota-aware wave placement → risks piling a wave on one account / straddling a Fable-window close. | Build `cc-wave-plan`: wave-DAG × `claude-accounts --json` greedy-decrement placement + window-straddle guard; `cc-route` (per-slot) is the leaf half already. |

---

## 5. Task candidates

| id | action | acceptance criterion | depends-on |
|---|---|---|---|
| T-P7-1 | Build the boundary-hook `gate-green` marker-writer (commit/`/ship` step) | `.git/gate-green==HEAD` after a green gate; boundary hook fires (idl shows a `fired` not `abstain`) on a real committed+green boundary past T | G-P7-2; commit/ship recipe |
| T-P7-2 | Add DEAD-lead page-once + escalate-at-3 marker to `lead-supervisor.sh`; stop re-checkpointing settled dead rows | 1 sweep of an unchanged dead set emits ≤1 page/sid; heartbeat `findings` stops re-counting settled rows; RED-proven vs the current re-page | G-P7-1; **is live machinery → C10 edit + kickstart is human** |
| T-P7-3 | Build the auditability floor (cc-idl hash-chained IDL + cc-audit `abstained==100%`/four-zeros monitor) | `cc-audit --wave` returns the four zeros; alarm fires on a forced 100%-abstain over N≥10; idl.jsonl hash-chained (tamper-evident) | G-P7-3; RESEARCH §3.6 |
| T-P7-4 | Build the L4 spine: durable backlog + dispatcher routine (`/schedule` cron) that pulls items, checks quota (`claude-accounts --rank`), spawns a team | dispatcher wakes on cron, reads backlog, spawns a worker team unattended on green quota, logs to IDL; **activation C10 human-run** | G-P7-5, T-P7-6 (wave-plan), reaper (LIVE) |
| T-P7-5 | Build the verify+merge autonomous-land gate (generalize `/ship` + land-lock) | green wave lands to trunk unattended; red queues to the async review (early-veto), never a silent fence | T-P7-4; land-lock (exists) |
| T-P7-6 | Build `cc-wave-plan` (axis d) | wave-DAG × live quota → placement JSON + ready fire-lines, ≤2/account, Fable-window guard; selftest RED-proven | G-P7-9; `cc-route` (exists) |
| T-P7-7 | Build gate-batching (axis c: manifest + classify + auto-stamp) | operator pre-signs C1–C7 classes at wave start; out-of-class STOP-ASK only; auto-stamp trailer ledger; `/ship` backstop grep | G-P7-8; `cc-bind` (exists) |
| T-P7-8 | Author the consolidated wiring-all C10 hand-run session (install ①②③④⑤⑥) + a re-page-if-un-run activation-queue watcher (D-v) | never-wait loops live in launchd/supervisor; reap-guard inserted; comms F3/F4/F5 wired; `cc-teardown` permission added; an un-run activation past its window re-pages | G-P7-6,7; wiring-all.sh; **human hand (C10)** |
| T-P7-9 | Freshen the roadmap/P8-GO status to ACTIVATED (content-verified), fix sha-drift | ROADMAP §6 + P8-GO reflect live state with content evidence; no stale "awaiting land"/pre-rebase shas | G-P7-4 |

---

## 6. Cross-beat dependencies
- **Permissions/hooks beat:** this beat owns the *activation* view of the same hooks another beat may audit for *content* (rm-safe, boundary, session-register, teammate-auto-shutdown, waiting-recycle). Confirm no double-count: I assert **wiring state**, not hook correctness.
- **Reaper/lifecycle beat:** cc-reaper/cc-classify/cc-teardown/supervisor internals — this beat asserts they're LIVE + the supervisor's live page/checkpoint volume (G-P7-1); a lifecycle-internals beat should own the page-once fix design (T-P7-2) and the never-reap-guarantee proofs.
- **Comms/2-way beat:** cc-notify/cc-announce/cc-bind + F1–F5 — this beat asserts F1 live, F3/F4/F5 staged; a comms beat owns the channel-ladder/BIND correctness.
- **Quota/accounts beat:** cc-wave-plan/cc-route/claude-accounts — T-P7-6 feeds the L4 dispatcher (T-P7-4).
- **Frontier beat:** the discovery feed (P2) overlaps frontier-hole sweeps as a backlog-refill source (ROADMAP:53).

## 7. Adversarial self-pass + Uncertainties
**Ran (real tool calls), integrated above:** (a) supervisor page-fatigue → **confirmed live** (G-P7-1, IDL counts). (b) `feat/autonomous-lifecycle` merged? → **yes, ⊆ main**; cited shas pre-rebase/not-in-main (sha-drift, G-P7-4) — reaper verified live by CONTENT not sha (aligns with project CLAUDE.md). (c) L4 spine present? → **zero tracked files** (G-P7-5). (d) IDL hash-chained / D9 alarm? → **no** (plain JSONL; alarm unbuilt, G-P7-3). (e) gate-batching / cc-wave-plan? → **unbuilt** (G-P7-8/9).

**Uncertainties (named, not hidden):**
1. **G-P7-1 severity** — I observed ~1 sweep's worth of records (200 IDL lines ≈ 85 pages + 84 checkpoints + 1 heartbeat). Whether the NEXT sweep re-pages the SAME 85 sids (true page-storm) vs dedups (a `page_escalate:1` record hints *some* escalation logic exists) I did not prove across two sweeps. The churn (per-sweep checkpoint of ~84 dead worktrees) is near-certain; the operator-facing push-storm depends on whether `page` fans out to `push-critical.sh`/cc-notify — **unverified**. Worst-case is FM2-grade; recommend T-P7-2 regardless.
2. **Activation path** — I proved the LIVE end-state but not WHETHER `wiring-all.sh` itself was run vs piecemeal per-subsystem scripts (rm-safe-activate / p8-activate / d2-activate). Immaterial to the wiring table (the §4 template items are verifiably NOT done either way).
3. **W4 DoD verdict** is doc-claimed (doc_classifier, read-only, not re-run here) — I report it as the design's own account, flagged.
4. **settings.json is machine-local** (not tracked, not a symlink; only the hook TARGETS symlink to the repo) — so the live hook set is not reconstructable from the repo alone; I read the live file directly. A fresh machine would need the activation scripts re-run (wiring-all ⑦).
5. I did not re-read `C00-SECTION-8-TEMPLATE.md` in full (companion template; its consumer W4-W5 instance was read) — low risk to the wiring conclusions.

**Coverage:** all 10 sourced docs read (2 partial-by-size but paged to the cited sections); every LIVE/STAGED
claim cross-checked against settings.json + launchctl + plist + symlinks + runtime logs + git.
