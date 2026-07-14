# SESSION AUTONOMY — platform-scale orchestration without unplanned human intervention

**Scope (frozen 2026-07-14):** make the multi-wave, multi-session build pattern
(doc_classifier-class: N waves × M teammate-slots × 4 accounts × model windows) run for DAYS with
the human touching ONLY designed gates (ratifications, /ship, wave-exit sign-offs) — zero
unplanned prods, restores, stall rescues, or manual /context + /accounts relays. Operator mandate:
100x research/planning effort for 1% implementation improvement; PERFECTION over speed; W4-W5 of
doc_classifier are live now and benefit immediately, then this becomes the standing pattern.

## Phase 0 — Agent Team Orchestration (shape now; the track lead FINALIZES at research-convergence)

Research phase = background subagents ONLY (read-only fan-out per `~/.claude/rules/research-subagents.md`).
Build phase = **Agent Teams** (the global default). The roster below is the SHAPE — finalize names,
≤150-line briefs, pre-greped line ranges, and spawn waves as the FIRST act of the build phase, per
the pre-spawn checklist in `~/.claude/rules/agent-teams.md`.

- **Roster shape (≤6 live):** `telemetry-v2` (statusline export + cc-context hardening) ·
  `boundary-hook` (advisory Stop-hook) · `supervisor` (watchdog extension + failure detectors) ·
  `e2e-harness` (per-primitive synthetic-pane suites) · `template-author` (C00 §8 template + filled
  W4/W5 instance — docs only). Lead lands glue and reviews merges serially.
- **Dependency graph:** telemetry-v2 → boundary-hook → supervisor (detectors consume telemetry);
  e2e-harness runs parallel to all (consumes each primitive as it lands); template-author independent.
- **Worktrees:** `/tmp/wt-sa-<member>` off this repo's live branch; single-owner per file:
  `statusline.sh` + `bin/cc-context` = telemetry-v2 · `hooks/**` = boundary-hook ·
  `scripts/lead-*` = supervisor · `scripts/*-e2e.sh` = e2e-harness · `docs/**` = template-author.
- **Spawn waves:** W-a = telemetry-v2 + template-author + e2e-harness · W-b = boundary-hook (after
  telemetry-v2 merges) · W-c = supervisor (after boundary-hook merges).

## Why now (operator observation, 2026-07-14 ~00:30)

W0-W3 (~24h) completed with far more human-in-the-loop than the 100th-percentile bar allows: the
operator hand-ran `/context` and `/accounts` between pause-points to tell sessions when to stay /
recycle / hand off, prodded stalled sessions, and manually restored work. Root causes split into
(a) five now-fixed mechanical bugs (see Evidence 2), (b) the missing self-telemetry loop (fixed
tonight, v1 — Evidence 2 last item), (c) NO session-orchestration layer in the plan template
(C00 specifies the teammate layer rigorously; the session/lead layer was improvised live), and
(d) designed gates arriving unbatched. This track closes (b) hardening + (c) + (d) and builds the
supervisor that makes (a)-class regressions self-announcing.

## Evidence base (read FIRST, in order)

1. doc_classifier project memory (`~/.claude-quaternary/projects/-Users-chrisren-Development-doc-classifier/memory/`):
   `handoff-succession-legibility`, `handoff-recycle-watcher-race`, `statusline-context-gauge-1m`,
   `agent-teammate-spawn-2-1-183`, `lr-audit-stale-residue`, `feedback-handoff-paste-one-sentence`.
2. Tonight's fixes in THIS repo: `dd40eca` (setsid watchers), `98a3dd9` (cc-notify submit-verify),
   `9918ff5` (self-close succession contract + `scripts/handoff-selfclose-e2e.sh`), `7674496`
   (statusline context gauge window-aware — a 2.3× lie drove a premature lead relief), `74d267f`
   (statusline telemetry export + `bin/cc-context` — the /context gap, v1).
3. doc_classifier `docs/BUILD_LOG.md`: § "When to clear / hand off" (the boundary rule this track
   makes machine-checkable), § Model routing, the W2/W3 MAILBOX POSTSCRIPT teardown lessons, wave
   exit records. READ-ONLY repo — see Constraints.
4. **W0-W3 operator-intervention audit** (the ground truth this track optimizes): mine
   `~/.claude-quaternary/projects/-Users-chrisren-Development-doc-classifier/*.jsonl` (2026-07-13
   01:44 → 2026-07-14 00:12; ~15 sessions) and classify EVERY human/operator message:
   designed-gate ruling · unplanned rescue · manual relay ( /context, /accounts, pane reads) ·
   conversation. Quantify per class; each unplanned-rescue class gets a detector+recovery in Build.
5. This repo: `docs/plans/TWO_WAY_SESSION_COMMS_PLAN.md`, `docs/research/HANDOFF_BACKCHANNEL_2026-07-10.md`,
   `commands/handoff.md` (the succession rails — current as of tonight), `hooks/` + `~/.claude/hooks/`
   (lead-crash-watchdog.sh runs today; teammate lifecycle hooks are prior art).

## Research phase (decompose per `~/.claude/rules/research-subagents.md`; expect N≈10-12; quota-aware — check `claude-accounts --rank` before waves)

Minimum axes: (a) **telemetry loop hardening** — atomic writes, stale-file sweep, self-resolution
(session→own id), per-account quota join (cc-context × claude-accounts in one read); (b)
**supervisor topology** — extend lead-crash-watchdog vs cron/Monitor vs standing orchestrator
session: stall/dead/limit/modal detection + SANCTIONED recovery only (succession rails), and who
watches the watcher; (c) **designed-gate batching** — formalize tonight's "ratify all" as
pre-delegated standing rulings: operator pre-signs ruling CLASSES at wave start; STOP-ASK only
out-of-class; (d) **quota-aware wave scheduling** — wave DAG × account headroom × model-window
edges (Fable close mid-wave) → lead/teammate placement plans; (e) **plan-template layer** — draft
the C00-class "§8 session-orchestration layer" template: per-wave lead account/model/effort,
context budget, succession triggers (telemetry thresholds AT committed boundaries), back-channel
topology, telemetry contract, gate batching; PLUS a filled W4/W5 instance as a PROPOSAL;
(f) **2-way comms** — ack semantics, mailbox sweep discipline, ping taxonomies (the R-PING loop);
(g) **lead context-budget engineering** — what W0-W3 leads actually spent context on (audit the
transcripts); read-order compression; ledger-first discipline; when 1M windows change the math;
(h) **failure taxonomy → detectors** — every W0-W3 unplanned-rescue class from Evidence 4 gets a
mechanical detector and either auto-recovery or a loud page; (i) **validation harness** — an E2E
per autonomy primitive (synthetic panes, like handoff-selfclose-e2e.sh); (j) **adversarial** —
where does days-long autonomy still break (auto-compaction mid-wave, CC version bumps, API
incidents, account lockouts, iTerm2 restart)?

## Build phase (after research converges; commits LOCAL to this repo)

> **CONVERGED — see `docs/research/SESSION_AUTONOMY_RESEARCH.md`:** §3 per-primitive buildable spec ·
> §4 revised **docs-first Phase 0** (Wave A safe primitives → prove-on-W4 → Wave B/C runtime) · §5 the
> 5 operator decisions · §6 risk register · §7 build blockers. The original bullets below are the
> pre-research shape; the blueprint supersedes sequencing — **template-author is DONE (proposals
> `da141f3`); supervisor + boundary-hook are HELD pending the operator DoD/build-order ruling; the
> ruling-independent telemetry-v2 proceeds first.**

- Telemetry v2 per (a); boundary hook: advisory Stop-hook that, when a session's OWN telemetry
  crosses its plan-declared threshold AND the repo sits at a committed/green boundary, injects
  "execute the /handoff rails now" (ADVISORY — blocking Stop hooks are a banned anti-pattern).
- Supervisor per (b) with detectors from (h); recovery strictly via the succession rails.
- Plan-template §8 + the filled W4/W5 instance → `docs/proposals/` in THIS repo (hand to the
  operator/orchestrator; NEVER write doc_classifier).
- E2E per primitive; all green before any is declared done.

## Constraints (HARD)

- **NEVER write `/Users/chrisren/Development/doc_classifier`** — its W4 lead owns it. Evidence
  mining there is read-only.
- **NEVER push** any repo; commits stay local. Operator ships explicitly.
- Succession/teardown ONLY via `handoff-fire.sh` rails (succession statement mandatory — bare
  self-close exits 2); cross-session sends ONLY via `cc-notify`; teardown of teammates = TaskStop.
- Designed operator gates are FEATURES: the target is zero UNPLANNED intervention, with designed
  gates batched and crisp — never silently absorbed.

## Status log

- 2026-07-14 00:3x — plan created by the orchestrator session (a28944df, doc_classifier pane
  99261468); telemetry v1 + cc-context landed (`74d267f`); deep track fired on next2 (Opus @ max).
- 2026-07-14 (track, next2) — **evidence audit DONE**: `docs/research/W0-W3_INTERVENTION_AUDIT.md`
  committed `3279340`. Deterministic extraction over 31 doc_classifier transcripts (read-only)
  quantified the operator burden: **10 hand-run `/context`+`/accounts` relays**, the 2.3×-gauge
  false-relief (163b5ffa at 47%-read-as-95%), designed gates (`/ship`×4, "go"×2, "RATIFY ALL 7"),
  the 3/3 handoff-closed-without-opening (FIXED). Root causes R1-R6 → Build axes; OPEN detectors
  D1-D7 → supervisor spec; boundary rule verbatim; operator success criteria captured. Memory +
  BUILD_LOG distilled (2 read-only subagents). **Wave-2 design research FIRED** — decomposition-critic
  REVISED 11→**14 axes** (partitioned b/h [where-watcher-lives vs detection-semantics]; +3 non-obvious:
  **k** post-hoc auditability/verifiable-trust, **l** cross-session runtime contention, **m**
  autonomy-layer self-cost). 12 Opus workers (a-m) + 2 Fable adversarial (j1 red-team, j2
  hostile-reviewer), all read-only background. d→e dependency explicit; h owns the boundary hook.
  Quota wide open (all accounts <0.2%). Originator pinged (99261468). Awaiting returns → converge.
- 2026-07-14 (track, next2) — **RESEARCH CONVERGED (14/14) + PROPOSALS DELIVERED.** Blueprint
  `581b75a` (`docs/research/SESSION_AUTONOMY_RESEARCH.md`: 5 architecture invariants, 7 design
  decisions, per-primitive spec, revised docs-first Phase 0, j1 risk register, 6 build blockers).
  Proposals `da141f3` (`docs/proposals/C00-SECTION-8-TEMPLATE.md` + `W4-W5-SESSION-ORCHESTRATION.md`
  — **applicable to live W4/W5 NOW**, manual-mode). **Frontier adversarial finding (j1+j2):** naive
  autonomous actors keyed off the audit's own lying D1-D7 signals can CAUSE a W0-class incident; the
  supervisor has the least evidence of need (post-fixes, n=1 unplanned residual). **Design law:**
  fail-loud · park-and-page · effect-verified · plan-time-schedule primary. **Build law:** docs-first
  → prove-on-W4 → runtime-only-to-residual. **5 operator decisions surfaced (blueprint §5)** — batched
  gate pinged to 99261468. Proceeding on the ruling-independent safe primitive (telemetry-v2);
  HOLDING boundary-hook + supervisor for the DoD/build-order ruling (blueprint §5 #1/#4).
- 2026-07-14 ~02:0x (track, next2) — **OPERATOR RATIFIED ALL 5** (relayed via `99261468`): (1) DoD =
  park-until-gate → **supervisor PAGES, never auto-recovers** (detect + checkpoint-preserve + page;
  operator/delegated-live-session recovers); (2) unknown modal = PAGE; (3) C6 money-path permanently
  out-of-class; (4) **docs-first → prove-on-W4 → runtime-only-to-residual**; (5)
  `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=90` on the autonomy launcher. Blueprint §5 stamped; supervisor spec
  → page-only (D-B, §3.3). Boundary-hook + supervisor UNBLOCKED. Also logged **W4 GO-deafness**, the
  3rd comms-reliability instance in 24h (`e8b6a88`). → Continuing telemetry-v2 (Wave-A safe primitive).
- 2026-07-14 ~02:3x (track, next2) — **telemetry-v2 BUILT + TESTED + DEPLOYED LIVE.** atomic export +
  config_dir + sid-once (`78170a0`), cc-context --me/--quota/sweep (`649c3b6`), cc-board operator
  glance-view (`4e66f97`), E2E 11/11 (`671c211`). **Deploy finding:** live `~/.claude/statusline.sh`
  was a COPY drifted from the repo (`sync.sh` mirrors live→repo, so the repo edit didn't propagate) —
  applied the tested Increment-1 delta atomically (live==repo now; `sync.sh` a no-op). Sessions
  self-heal config_dir on next render; a doc_classifier/next session already shows full quota on
  cc-board. **Finding:** `CLAUDE_CODE_CHILD_SESSION=1` is set in the LEAD's OWN Bash tool (not just
  subagents) → can't gate self-resolution on it (boundary hook self-IDs off Stop-stdin, not the CLI).
  **cc-board kills the §1 relay pain NOW** (`watch -n5 cc-board` = every session's ctx×quota×stall at
  a glance). → NEXT per ratified order: **prove-on-W4** (operator applies §8 + uses telemetry), THEN
  runtime-to-residual (boundary-hook, supervisor page-only, gate-batching, auditability — blueprint
  §3/§4). Wave-A residual deferred: session-register P8 wiring, IDL auditability floor, e2e umbrella.
- 2026-07-14 ~04:0x (track, **next4 successor**; predecessor self-closed at its §8 boundary — 60% ctx /
  87% weekly — and the succession rails ran clean end-to-end) — **THE VERIFIER WAS INERT (`3b12107`).**
  Found by dogfooding: the successor's own mandated startup `cc-notify` printed `submit UNVERIFIED`.
  Root cause: an it2 screen capture is **BINARY** (iTerm2 NUL-pads cells; ~177 NULs / 4.5KB) and BSD
  `/usr/bin/grep` needs **`LC_ALL=C`** to byte-match the multibyte `❯` past the NULs (**`-a` alone is NOT
  enough** — the UTF-8 locale still misses it). So `98a3dd9`'s strand-detector — the audit's recorded FIX
  for the composer-strand class — **never executed once**: every send, in every session, for ~24h reported
  `UNVERIFIED` + exit 0, and the ~1-in-6 Ink strand went **unwatched**. Orchestrator corroborated
  independently (*"a dozen+ sends... I mis-attributed it to a sandbox limitation — retracted"*) and had been
  **hand-capturing panes after each ruling** to compensate — **a human silently serving as the compensating
  control for a blind automation** = a NEW manual-relay class, invisible to a transcript grep (audit §1).
  **Effect-checked live: a real send now prints `submit VERIFIED`** (that branch's first-ever execution).
  **The suite was 15/15 GREEN over unreachable code** via 3 compounding harness defects → the **four harness
  laws** (blueprint §3.10 L1–L4): fixtures must carry the REAL artifact's BYTES · assert a string the FAILURE
  cannot satisfy (`*"VERIFIED"*` also matches `"UNVERIFIED"`) · every assertion must TRAP (**bats does not
  trap a bare mid-body `[[ ]]`** — 7/7 were dead) · **prove the suite RED against the real bug + effect-check
  live before recording "FIXED"**. Suite hardened: 15/15 on the fix, **3 RED** on the as-shipped binary.
  **Captured:** audit §3g (+ D9 detector, R6 corrected, R7 opened, §7 law extended to the verifier/fixture/
  green-suite), blueprint §1/§3.5/§3.10/§4 (**Deploy DoD clause 2**: a "FIXED" claim about *checking* code
  is not a fix until the check is seen to FIRE), template §8 E5. **Standing consequence for the build:
  a detector that has never fired in production is UNPROVEN, not "quiet"** — binds boundary-hook (h) +
  supervisor (b) directly. Also: successor announcement hard-failed **exit 3** on an **abbreviated pane id**
  (briefs/corpus use the 8-char prefix; `cc-notify` takes only {name | FULL uuid}, and the name registry is
  EMPTY — **P8 un-wired**) → two gaps composed to break a succession's most important send; failed LOUD, not
  silent. → §8 E5 now mandates FULL uuids; queued: prefix-expansion in `cc-notify` + land P8.
- 2026-07-14 (prove-on-W4, orchestrator 1st hour) — **✅ VALUE CONFIRMED IN PRODUCTION.** cc-board
  caught the live W4 lead at **63% > §8 `boundary_recycle=60`** → succession advisory fired on the rails
  (the operator's hand-catch, now automated — audit §1 → 0). STALE renders correctly for closed
  teammate panes. **Deploy gap:** cc-board committed but un-symlinked into `~/.claude/bin` — found by
  the orchestrator's effect-check, fixed; added **Deploy DoD** (blueprint §4: every bin/statusline/hook
  ends with `which <tool> && <tool> runs`). All 3 telemetry tools verified live (symlinks → repo).
  Keep parked (no push); awaiting the W4 succession outcome.
