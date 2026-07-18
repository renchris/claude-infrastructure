# P6 — Completeness / Anti-Premature-Done Discipline

**Beat:** FM1 (desk loses purpose / pauses believing it's done / needs a human to re-ask "are you sure?").
Also FM2 (idle standoff) where it touches the supervisor/boundary gates.
**Coverage:** read 12 of 13 named in-scope source files in full (all but `scripts/plan-phase-scan-tests/run.sh`,
referenced only); swept `commands/` (19 files), all 4 `~/.claude*` config dirs, `install.sh`, `settings-templates/`,
`~/Library/LaunchAgents/`; ran `premortem-gate.sh` live + `idl.jsonl` forensics (569,704 lines) + a live-transcript
extraction test. Empirical = read/ran; theoretical = inferred, marked as such.

## The one-sentence thesis
"Done" judgment lives **entirely in the model at every layer**. The only *mechanical* (model-independent) completeness
checks are narrow-technical (`task-quality-gate` tsc; `p8-e2e`; `premortem-gate`) and none of them answer "is the
operator's long-horizon goal actually at 100.00/100.00." The Session-Close readout (✅/🔧/📦/⛔/📤) is model
self-classification against a frozen DoD that is itself only in-context (evaporates on compaction); the `/wrap`
tool that the protocol claims makes the ledger "un-fakeable" **does not exist**; the continuation loop
(`session-continue`) only runs if the model *arms* it — which requires the model to already know it isn't done; and
the single mechanical deference-catcher (`anti-deference-nudge`) has **0 lifetime fires and a 74% blind rate** in
production. FM1 is therefore structurally un-defended against a confident, tell-free false-completion.

---

## (1) Inventory

| Asset | Role in desk loop | Wiring | Depends on | Verified by | Serves goal | Gap |
|---|---|---|---|---|---|---|
| `hooks/anti-deference-nudge.sh` | Stop hook: catch deference reflex (question/hold on drivable work), block+correct → DRIVE | **hook-enforced** — Stop, all 4 config dirs (matcher-obj 1, pos 5) | jq, transcript_path, latch dir, IDL | bats 15+16 cases GREEN; **live: 0 fires / 156 evals** | FM1 (a) | G-P6-1, G-P6-2 |
| `hooks/session-continue.sh` | 🔧 loose-ends continuation: block Stop, feed next step, hard cap | **hook-enforced** — Stop, all 4 dirs (matcher-obj 1, pos 4); **armed prompt-only** | model running `set`, sentinel dir | no dedicated test found; logic sound | FM1 (a) | G-P6-3 |
| `/wrap` (ledger computation) | Session-Close: compute un-fakeable ledger from live git/gate reads | **DEAD — does not exist** (no command, no skill, not built-in) | — | none | FM1 (a) | **G-P6-4 (P0-doc-reality)** |
| `/goal` (built-in) | Persistent session-scoped Stop-hook goal condition; re-anchors intent across Stops | **built-in CLI** (not in repo); prompt-only invocation via Skill dispatch | 4000-char cap; model self-eval at Stop | none (built-in) | FM1 (a) | G-P6-5 |
| CLAUDE.md §Session Close Protocol | The prose ruleset: frozen DoD, disposition table, readout states, G1-G4 auto-continue | **prompt-only** (resident context) | model adherence; `/wrap`; session-continue | none (prose) | FM1 (a,b) | G-P6-4, G-P6-6 |
| `hooks/task-quality-gate.sh` | TaskCompleted: tsc in teammate worktree, exit 2 rejects; Phase-0 verify-team | **hook-enforced** — TaskCompleted (live only) | jq, node_modules, `verify-team.sh` | logic read; no bats | FM1 (b) teammate work | G-P6-10 |
| `scripts/premortem-gate.sh` | Meta-gate: runtime-phase un-hold bar (B-1..3 boundary, S-1..4 supervisor) | **manual-only** (run on un-hold proposal) | boundary-handoff, lead-supervisor, sub-lints | **live: RED (S-1 fails)**, exit 1 | FM2 | G-P6-8 |
| `scripts/plan-phase-scan.sh` | Read-only: per-section DONE/PENDING/IN_PROGRESS/SUPERSEDED from status tokens+hashes | **manual-only** (no caller) | awk/sed/grep | tests dir exists (not read) | FM1 (b) measurement | G-P6-11 |
| `scripts/p8-e2e.sh` | Regression gate: session-registration spine, positive+negative effect-check | **manual-only** gate; spine is SessionStart (blocked, `/tmp/p8-activate.sh`) | cc-board, cc-sessions, session-register | self-contained, GREEN-provable | FM2 | (P8 activation human-blocked) |
| `hooks/boundary-handoff.sh` | Stop hook: at committed+green boundary ≥73% ctx, advise `/handoff` before autocompact | **hook-enforced** — Stop, **~/.claude ONLY (1/4)**, matcher-obj 2, **hardcoded abs path**; **live: 0 IDL records** | telemetry `/tmp/cc-telemetry`, gate-green marker | boundary-hook-e2e (not read); **live: 0 evals** | FM1 (b) state-preservation | **G-P6-5b, G-P6-6** |
| `docs/WORKFLOW_SEAM_GATES.md` | Methodology: calibrated certification, seam/reachability/resource gates, never-idle | **prompt-only** (doc; per-program adoption) | plan authors | none (prose) | FM1 (b), FM2 | G-P6-9 |
| `docs/rulings/P8-GO.md` | Ruling: P8 conditional-GO; C10 (self-persistence = human-only, not desk-signable) | doc/ruling | cc-bind gate | ruling gate FAILS-CLOSED on trailer | FM2 governance | — |
| `settings-templates/settings.example.json` | Checked-in reproducible config template | **template** — Stop=notify only; TaskCompleted=null | install.sh | — | reproducibility | **G-P6-7** |
| `idl.jsonl` ship-gate alarm (abstained==100%) | Documented alarm: "abstained==100% over N≥10 ⇒ tells stopped matching reality" | **DEAD — documented, no monitor** | IDL consumers | none | FM1 self-watch | **G-P6-2** |

---

## (2) Mechanism — end-to-end

**Stop-event chain (every turn-close).** Live `~/.claude/settings.json` Stop has **two matcher-null objects**:
obj-1 runs 5 hooks in order — `notify.sh complete` → `cache-expiry-tracker.sh` → `teammate-checkpoint.sh` →
`session-continue.sh` → `anti-deference-nudge.sh`; obj-2 runs `boundary-handoff.sh` (hardcoded
`/Users/chrisren/Development/claude-infrastructure/hooks/boundary-handoff.sh`). All 4 config dirs carry obj-1's
anti-deference + session-continue; **only ~/.claude carries boundary** (verified per-dir).

1. **session-continue.sh** (`session-continue.sh:55-84`): actuation mode reads Stop JSON, resolves sentinel
   `${CLAUDE_CONFIG_DIR}/state/continue-<hash(cfg|cwd)>` (`:30-34`). No sentinel → `exit 0` allow (`:62-65`).
   Sentinel present → increment `.count`, and if `< CLAUDE_CONTINUE_MAX` (default 8, `:68`) emit
   `{decision:"block",reason:"🔧 …Next: <step>"}` (`:78-83`). **The sentinel is written ONLY by the agent** via
   `session-continue.sh set "<step>"` (`:38-43`). **Grep across the entire repo finds no caller of `set` except the
   usage comment and CLAUDE.md:268** — i.e. nothing arms it but the model's own 🔧-classification.
2. **anti-deference-nudge.sh** (`:74-113`): extracts last assistant text
   (`jq -c 'select(.type=="assistant")' | tail -1 | [.message.content[]|select(.type=="text").text]`, `:74-75`),
   abstains if empty (`:76`). Fire predicate = `has_tell (TELLS :81) AND NOT has_genuine (GENUINE :86)`. Latch-set
   (`:99-101`) + hard cap `ANTIDEF_MAX=3` (`:103-104`). Fire → block with corrective (`:111-113`). Every path
   `exit 0`; one IDL line per invocation (`:54-60`).
3. **boundary-handoff.sh** (`:29-113`): fires at `used_pct ≥ CC_BOUNDARY_T(73)` (`:66`), fresh telemetry (`:63`),
   committed+green tree (`gate-green==HEAD`, `:77-79`), no live teammates (`:84`); one-shot latch with +10% re-arm
   (`:97-107`); advises `/handoff`. **Compose-guard `:51-53`** meant to yield to session-continue checks sentinel
   `$HOME/.claude/hooks/.session-continue-armed` — **which session-continue never writes** (it writes
   `…/state/continue-<hash>`). Dead guard.

**TaskCompleted chain.** `task-quality-gate.sh` runs only for team tasks (`:25` `[ -z "$TEAM_NAME" ] && exit 0`),
runs `tsc --noEmit` in the teammate worktree (`:96`), exit 2 rejects (`:109`); Phase-0 tasks additionally run
`verify-team.sh` (`:33-53`) — but the fallback path is hardcoded to `reso-management-app` (`:37`), and for a worktree
with no `node_modules` it skips (`:90-93`).

**Session-Close readout (prompt-only).** CLAUDE.md §Session Close (`CLAUDE.md:196-283`): agent freezes DoD at intake
(`:210`), classifies each end-state, emits the worst-open rung one-liner (⛔>📤>🔧>📦>✅, `:233-247`), and on **🔧
only** arms session-continue (`:266-270`). `/wrap` (`:200,254,279`) is the claimed ledger computer — **absent**.

**Meta-gates (manual).** `premortem-gate.sh` aggregates B-1..3/S-1..4; **live RED on S-1** (a reaper horizon <
sweep×10). `never-stuck-gate.sh:45` aggregates 7 component safety-gates including premortem-gate — all manual, none
hook/launchd-wired. `lead-supervisor.sh` IS launchd-scheduled (`com.claude.lead-supervisor.plist`) and reads the IDL,
but covers FM2 liveness (past-threshold∧not-Stopping), not FM1 completeness.

---

## (3) Gaps & fragilities

| ID | file:line | FM | Sev | Failure scenario | Fix sketch |
|---|---|---|---|---|---|
| **G-P6-4** | `CLAUDE.md:200,254,279` vs `commands/` (no `wrap.md`) | FM1 | **P0** | Protocol claims "the agent runs the git/gate reads itself, so the ledger reports facts, not self-report" — but the tool that runs them (`/wrap`) doesn't exist. The readout is therefore **self-report**, exactly what the design says it prevents. A model emits `✅ Complete` from memory without ever reading git/gates. | Implement `commands/wrap.md` (skill) that shells the live ledger: `git rev-list trunk..HEAD`, dirty-tree, gate markers, `trunk..HEAD` count → emits the ledger block + forces the readout from FACTS. Until then, downgrade the "un-fakeable" claim in CLAUDE.md. |
| **G-P6-1** | `anti-deference-nudge.sh:74-76` | FM1 | **P1** | **0 lifetime fires / 156 evals (14h, all 4 dirs)**; 116/156 (74%) abstain `no-assistant-text`. Two sampled blind sessions have a *text* last-entry now → the `tail -1` of assistant lines grabs a mid-turn/sidechain (subagent) entry at Stop time, not the main agent's final text. The flagship fix for the operator's #1 flag (flagged 4×) has **no production evidence of ever working**. | Make extraction main-agent-scoped (`select(.type=="assistant" and (.isSidechain|not))`) and/or read the final text block regardless of trailing thinking/tool_use; add a bats fixture reproducing the sidechain-tail case; re-check IDL fire-rate after. |
| **G-P6-2** | `anti-deference-nudge.sh:39-41`; no consumer | FM1 | **P1** | The hook's OWN ship-gate rule ("alarm on abstained==100% over N≥10") is **tripped** (100% abstained, 0 fired) and **nothing watches it**. No launchd/monitor consumes the IDL for this alarm → the silent-inert state is itself undetected. | Add an IDL alarm sweep (launchd or fold into `lead-supervisor`): alarm when a fire-designed hook is abstained==100% over the last N≥10. |
| **G-P6-3** | `session-continue.sh:38-43`; no non-doc caller | FM1 | **P1** | Continuation only runs if the model ARMS it on 🔧 — the same self-judgment that fails in FM1. A model that *wrongly* believes it's ✅ never arms → Stop proceeds. Structurally cannot catch a false-done; it can only extend a *correctly* self-identified loose-end. | Accept as by-design (scope-judgment must stay with the model), but pair with a mechanical ground-truth check (T-P6-2) so false-✅ is caught by facts, not by the model's own arming. |
| **G-P6-6 (FM1 core)** | all Stop hooks; `PreCompact` (`settings.json`) | FM1 | **P1** | **No mechanical check that declared-done == ground-truth.** A confident, tell-free `✅ Complete` passes every Stop hook: session-continue (unarmed→allow), anti-deference (no tell→abstain), boundary (below 73%→abstain), /goal (model self-eval→allow). Only backstop = the human re-asking = the literal FM1. Compounded: the frozen DoD lives only in-context/plan; **PreCompact hooks only `date>>log`** — nothing re-injects the DoD/goal post-compaction, so the completeness *baseline* evaporates and the desk drifts. | (a) A Stop-time "completion assertion" gate: when the model emits ✅, require a machine-checked ledger (git clean + gate-green + trunk..HEAD) or block. (b) A SessionStart/PreCompact hook that re-injects the frozen DoD/goal from a durable file. |
| **G-P6-7** | `settings-templates/settings.example.json` (Stop=notify only); `install.sh:251-257` | FM1 | **P1** | The anti-premature-done Stop hooks (anti-deference, session-continue, teammate-checkpoint) are **live-only**. Template Stop = `notify.sh` only; TaskCompleted = null; `install.sh` only *warns* if hooks missing, never wires them. A fresh install / settings reset silently reverts the desk to **un-guarded premature-done**. (Live coverage across 4 dirs IS currently complete — so this is reproducibility/drift, not a present outage.) | Capture the full live Stop/TaskCompleted/SessionStart hook set into `settings.example.json`; have `install.sh` merge-wire them (jq) and assert post-install. |
| **G-P6-5b** | `settings.json:803` (abs path); per-dir check | FM1 | **P1** | boundary-handoff has **0 IDL records in 14h** despite 115 telemetry files present and clean Stops occurring. It's wired only in ~/.claude (1/4 dirs), in a **second matcher-null Stop object**, via a **hardcoded absolute repo path**. Empirically not evaluating → its state-preservation advisory is dead; only the redundant supervisor (B-1) covers the boundary. | Move boundary-handoff into the SAME Stop hooks array as anti-deference (obj-1), path `~/.claude/hooks/…`, in all 4 dirs; force-fire test; confirm IDL records appear. |
| **G-P6-5** | `commands/handoff.md:204-215` (/goal) | FM1 | P2 | `/goal` (built-in, persistent Stop-hook goal) is the strongest intent-anchor but is **opt-in**, **4000-char capped** (over-cap = silent dead-fire, no task), and handoff.md explicitly tells fires to OMIT it for long briefs → most sessions run without a persistent goal condition. Evaluation still bottoms out in model self-judgment at Stop. | Standardize `/goal <one-line objective> — brief at <path>` in every fired session; add a `wc -c` pre-fire guard (already advised at `:215`) as a hard gate in `handoff-fire.sh`. |
| **G-P6-8** | `premortem-gate.sh` (S-1); manual-only | FM2 | P2 | premortem-gate is **RED live** (S-1: a reaper horizon < sweep×10 ⇒ its evidence is invisible to the supervisor) and is manual-only — nothing runs it on a schedule, so the RED is only seen if a human runs it. | Fix the offending reaper horizon (`reaper-horizon-lint.sh` names it); optionally add premortem-gate to a periodic CI/launchd heartbeat. |
| **G-P6-6b** | `boundary-handoff.sh:51-53` vs `session-continue.sh:33` | FM1 | P2 | Dead compose-guard: boundary checks sentinel `~/.claude/hooks/.session-continue-armed`; session-continue writes `~/.claude/state/continue-<hash>`. Guard never trips → if both ever co-occur, double-inject (rare: boundary needs clean tree, continue implies loose ends). | Point the guard at `session-continue.sh`'s real sentinel (share a `sentinel_for` helper) or delete the guard. |
| **G-P6-9** | `WORKFLOW_SEAM_GATES.md` (whole) | FM1/FM2 | P2 | The strongest anti-premature-done ideas — calibrated certification ("100/100 vs phase-reachable criteria; execution-gated: <list>"), reachability gate, resource ledger, seam audit, never-idle lifecycle — are **prose-only**, adopted per-program by hand. Nothing mechanizes them, so they bind only when a plan author remembers. | Promote the checklist (`:74-82`) into `plan-phase-scan` assertions and/or a plan-lint hook that fails a plan lacking a decision-rule table / calibrated-cert line. |
| **G-P6-10** | `task-quality-gate.sh:25,37,90-93` | FM1 | P2 | Inert for claude-infrastructure's OWN work: no `node_modules` → skip (`:90`); `verify-team.sh` fallback hardcoded to `reso-management-app` (`:37`); non-team tasks skip (`:25`). Infra self-work has no completion gate. | Add a repo-aware gate (bats/shellcheck for infra) as the TaskCompleted check when the worktree is claude-infrastructure. |
| **G-P6-11** | `plan-phase-scan.sh:130-178` | FM1 | P2 | Measures **declared**-done (heading `DONE`/commit-hash/`**Status**:` tokens), not **actual**-done. A section reading `DONE abc1234` scores complete even if the commit didn't achieve the goal → reinforces self-report if used as a completeness oracle. | Keep as an index tool; never treat its DONE count as ground-truth completeness — pair with behavioral verification. |

---

## (4) Task candidates

| ID | Action | Acceptance criterion | Depends on |
|---|---|---|---|
| **T-P6-1** | Implement `/wrap` (`commands/wrap.md` skill) computing the ledger from live git/gate reads | `/wrap` emits the CLAUDE.md ledger block from `git`/gate facts; `/wrap --full` per-field; readout no longer reconstructable from memory alone | — |
| **T-P6-2** | Stop-time completion-assertion gate: when last message asserts ✅/complete/done-live, require machine ledger (clean tree ∧ gate-green ∧ `trunk..HEAD` accounted) else block | New Stop hook + bats: fires-block on a false `✅ Complete` over a dirty/red/unpushed tree; silent on a true one; fail-safe exit 0; latch+cap | T-P6-1 (reuse ledger) |
| **T-P6-3** | Fix anti-deference extraction (main-agent-scoped, ignore sidechain/trailing-tool tail) | New bats fixture (sidechain tail + trailing-thinking) fires correctly; live IDL `no-assistant-text` rate drops <10%; a real defer fires within a probe session | G-P6-1 |
| **T-P6-4** | IDL abstained==100% alarm sweep (launchd or into lead-supervisor) | Alarm emitted when any fire-designed hook is abstained==100% over N≥10; self-test GREEN | — |
| **T-P6-5** | Re-wire boundary-handoff into obj-1 Stop array, `~/.claude/…` path, all 4 dirs | IDL shows boundary records after a forced-fire; per-dir coverage = 4/4 | — |
| **T-P6-6** | Capture live Stop/TaskCompleted/SessionStart hook set into `settings.example.json` + `install.sh` merge-wire + post-install assert | Fresh install reproduces the full anti-premature-done hook set; assertion GREEN | — |
| **T-P6-7** | PreCompact/SessionStart re-injection of the frozen DoD/goal from a durable file | After a compaction, the session's context re-contains the frozen DoD; probe: compact then read-back shows the DoD line | T-P6-1 |
| **T-P6-8** | Fix premortem-gate S-1 (offending reaper horizon) | `premortem-gate.sh` → GREEN (or S-1 ✅); `reaper-horizon-lint.sh` GREEN | — |

---

## (5) Cross-beat dependencies
- **Reaper/lifecycle beat (FM2):** `lead-supervisor` (launchd) is the ONLY scheduled watcher and reads the IDL — it is
  the natural host for T-P6-4 (abstained alarm). `premortem-gate` S-1 fix (T-P6-8) is a reaper-horizon change owned by
  the lifecycle beat. boundary-handoff (T-P6-5) overlaps the boundary/handoff beat.
- **Handoff beat:** `/goal` 4000-char cap + omit-for-long-brief (G-P6-5) is enforced in `handoff-fire.sh`; T-P6-7
  (DoD re-injection) rides the handoff/compaction machinery.
- **Config/install beat:** T-P6-6 (template capture) touches `install.sh` + `config-mirror-assert.sh` (the 4-dir
  mirror invariant). settings.json is NOT mirrored (P8-GO blind-spot map: 4 distinct hashes) — each dir wired
  individually, so T-P6-5/T-P6-6 must edit all four.
- **Governance beat:** P8-GO C10 (self-persistence = human-only, not desk-signable) means any hook that installs
  persistence (T-P6-2/5/6/7 wiring) is **operator-activated**, not desk-activated — hand the operator a script.

## (6) Adversarial self-pass — "what did I miss?"
- **"Coverage across 4 dirs — did you actually check?"** Yes: anti-deference + session-continue = 4/4; boundary = 1/4;
  SessionStart-goal = 0/4. So the live anti-premature-done Stop hooks ARE complete-coverage (correcting my initial
  template-gap worry: live ≠ template — G-P6-7 is reproducibility, not a present outage).
- **"Is anti-deference *really* dead or just conservatively quiet?"** Extraction jq works (11,188 chars on a real
  transcript), so it's not a syntax bug. But 0/156 fires + 74% `no-assistant-text` + two blind sessions whose current
  last-entry IS text ⇒ a timing/sidechain `tail` problem, not calibration. Defensible claim: **unproven in
  production + high blind rate**, ship-gate alarm tripped. Not "provably dead," but "no evidence it works."
- **"Did you assume boundary is dead?"** I inferred non-execution from 0 IDL records despite 115 telemetry files +
  same IDL path + logging-on-every-path code. I flagged it as high-confidence-inferred and gave a falsifiable test
  (T-P6-5 forced-fire). Alternative I ruled out: "narrow AND-precondition rarely met" — rejected because even
  below-threshold/no-telemetry paths log `abstained`, so 0 records ⇒ not-running, not just not-firing.
- **"Is /goal maybe the real backstop you under-weighted?"** It's the strongest intent-anchor (persists across Stops)
  but opt-in + capped + model-evaluated → not a mechanical completeness check. Correctly weighted as partial.
- **"Multiple decision:block hooks on one Stop — ordering?"** Uncertainty: session-continue (pos 4) precedes
  anti-deference (pos 5); harness behavior when both block is unverified. Low impact — session-continue only blocks
  when armed; when unarmed it exits 0 and anti-deference runs. Named in Uncertainties.

## (7) Uncertainties
1. **Harness Stop-matcher semantics** — whether a 2nd matcher-null Stop object executes at all (bears on boundary's
   0 records). Falsifiable by T-P6-5.
2. **`/goal` condition evaluation** — whether the built-in mechanically checks the condition or re-prompts the model
   to self-judge at Stop. Behavior is system-prompt-driven (handoff.md:199-201), so likely model-side — but not
   directly observed.
3. **anti-deference `no-assistant-text` root cause** — sidechain-tail vs read-before-flush timing. Both point to the
   same fix (main-agent-scoped extraction); exact split not isolated.
4. **`lead-supervisor` IDL usage** — it references the IDL (grep hit) but I did not confirm it checks the
   anti-deference abstained-alarm specifically; T-P6-4 may be partially present. Not read in full.
5. `scripts/plan-phase-scan-tests/run.sh` referenced, not read — plan-phase-scan behavior inferred from the script +
   its documented test intent.
