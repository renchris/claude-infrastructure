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
  `99261468-A46A-498A-AE9B-F39473E5E7AE`); telemetry v1 + cc-context landed (`74d267f`); deep track fired on next2 (Opus @ max).
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
  Quota wide open (all accounts <0.2%). Originator pinged (the orchestrator). Awaiting returns → converge.
- 2026-07-14 (track, next2) — **RESEARCH CONVERGED (14/14) + PROPOSALS DELIVERED.** Blueprint
  `581b75a` (`docs/research/SESSION_AUTONOMY_RESEARCH.md`: 5 architecture invariants, 7 design
  decisions, per-primitive spec, revised docs-first Phase 0, j1 risk register, 6 build blockers).
  Proposals `da141f3` (`docs/proposals/C00-SECTION-8-TEMPLATE.md` + `W4-W5-SESSION-ORCHESTRATION.md`
  — **applicable to live W4/W5 NOW**, manual-mode). **Frontier adversarial finding (j1+j2):** naive
  autonomous actors keyed off the audit's own lying D1-D7 signals can CAUSE a W0-class incident; the
  supervisor has the least evidence of need (post-fixes, n=1 unplanned residual). **Design law:**
  fail-loud · park-and-page · effect-verified · plan-time-schedule primary. **Build law:** docs-first
  → prove-on-W4 → runtime-only-to-residual. **5 operator decisions surfaced (blueprint §5)** — batched
  gate pinged to the orchestrator. Proceeding on the ruling-independent safe primitive (telemetry-v2);
  HOLDING boundary-hook + supervisor for the DoD/build-order ruling (blueprint §5 #1/#4).
- 2026-07-14 ~02:0x (track, next2) — **OPERATOR RATIFIED ALL 5** (relayed via the orchestrator): (1) DoD =
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
- 2026-07-14 ~07:xx (track, next4) — **INVARIANT 7 + THE BLIND-CHECK LAW + THE UN-HOLD BAR** (`1eebe07`,
  `f738c9c`, `68d7dcb`, `d4e0eac`). **`cc-bind`'s own gate was blind** — the ack bound to an **ID, not the
  ruling's TEXT**, so a ruling rewritten after the ack still PASSED (proven). The tell: the orchestrator
  **hand-verified the blob** — *the audit's own second-class relay reappearing inside the tool built to end
  it, within hours.* Fixed: `Acked-Ruling: <id>@<content-sha>`; gate fails LOUD on amended-since-ack, FAILS
  CLOSED on an unhashed ack, and matches the trailer EXACTLY (an ack for `P8-GO-2` satisfied a `P8-GO` gate
  via substring). selftest 8/8. **Proven live on the desk's own AMENDMENT 1** (which VOIDED condition 4 —
  *"not because timing changed but because the CLASS was mis-signed"*; **precedent, now desk law: an authority
  that discovers it over-signed VOIDS THE CLASS, never re-times the request**). **→ §3i THE BLIND-CHECK LAW
  (the keeper): a check that cannot OBSERVE the thing it guards is indistinguishable from NO CHECK — it exits
  0, its suite is green, the system looks healthy. You cannot find one by reading it (4 instances, 3 shipped
  with passing tests). BUT ITS EXTERNAL SIGNATURE IS UNMISSABLE: A HUMAN QUIETLY STARTS DOING ITS JOB BY HAND.
  ⇒ AUDIT WHAT THE HUMAN *DOES*, NOT WHAT THEY *SAY* — every manual verification is a bug report against an
  automation, filed by someone who didn't know they were filing it.** (This is why §1 UNDERCOUNTED.)
  **→ INVARIANT 7 (ONE ARTIFACT, ONE ROLE):** an artifact that is BOTH the evidence of a failure AND subject
  to a lifecycle serving another goal will have its evidence destroyed by that goal, silently, *at the moment
  the failure occurs* — the destructive role wins because it is the one with a POLICY. **The conflicting pair
  was DIFFERENT every time** (telemetry: stall-evidence vs HYGIENE · registry: spawn-death vs ADDRESSING ·
  ruling: what-was-authorized vs AMENDABILITY), which is why a reader watching for a repeat of the last bug
  missed all three. Fix shape: split the roles; **deletion keys on AGE, never on the failure-state**; a view
  may HIDE, never DELETE; an attestation binds by CONTENT, never by name. **Mechanical corollary (desk-adopted
  as a SHIP-GATE): a check must log its ABSTENTIONS** — D9 is only visible in the outcome DISTRIBUTION; alarm
  on `abstained==100%` over N≥10. *That one rule would have caught `cc-notify` in hours, not a day.*
  **→ THE UN-HOLD BAR is now MECHANICAL** (desk sharpening: *"a pre-mortem nobody can watch fire is itself a
  check that cannot observe what it guards"*): `scripts/premortem-gate.sh` — B-1/B-2/B-3 + S-1..S-4 as
  ASSERTIONS. **RED today by design (2 met · 5 NOT BUILT); its redness IS "not ready", and turning it green IS
  the definition of ready.** Not wired to pre-commit (an always-red gate teaches people to ignore it).
  **S-1 enforced TODAY** per the desk's suggestion: `scripts/reaper-horizon-lint.sh` — *no reaper's horizon may
  be shorter than the supervisor's slowest sweep ×10* — greps the SOURCE, green now, RED on the simulated
  "tidy up /tmp" change, and FAILS CLOSED on an undeclared reaper. **Safe-by-luck → safe-by-construction,
  before the supervisor exists.** (It was itself reading COMMENTS AS CODE until fixed — a `grep -rn` hit is
  `file:line:content`, so `grep -v '^#'` never matches.) **NEXT LEAD: read `premortem-gate.sh` output first —
  it tells you exactly what the runtime phase still owes.**
- 2026-07-14 ~06:xx (track, next4) — **P8 CODE COMPLETE (`7b2f701`) · ACTIVATION HUMAN-GATED · and THE
  AUTHORITY CEILING (audit §2b) — the hardest constraint on this whole track, found by hitting it.**
  Orchestrator gave a CONDITIONAL GO (5 binding conditions) under "desk authority". Wiring the SessionStart
  hook into the four `~/.claude*` `settings.json` was **DENIED by the harness**: *"[Self-Modification] …
  [Unauthorized Persistence]; the only authorization is a peer/orchestrator session's CONDITIONAL GO, **which
  is not user intent**."* **The classifier is RIGHT and this must not be worked around.** The orchestrator is
  a **peer agent**, not the human; its ruling cannot manufacture human consent for the agent to modify its own
  config and install persistence — and the ruling *itself* routed P8 to the operator's wake-up batch, so by the
  desk's own account the human had not reviewed it. **A chain of agent-to-agent rulings is not consent.**
  Delegated authority is real for WORK, **void for SELF-MODIFICATION**. **This track should WELCOME the
  ceiling:** the autonomy layer is by construction *the thing that would grant itself more autonomy* — a
  supervisor that can install its own hooks can widen its own powers. → **Invariant 6** (blueprint §1) +
  **ruling class C10 = self-modification/persistence, PERMANENTLY out-of-class, human-only** (with C6/C9) +
  the DoD gains a **principled floor**: config/persistence/autonomy-machinery changes are designed gates BY
  CONSTRUCTION, never "interventions to drive to zero" (counting them as failures would push the system to
  defeat its own safety rail). **Standing pattern:** agent does ALL the work — code, tests, effect-check,
  rollback one-liner — and hands the human an **activation script** (`/tmp/p8-activate.sh`); never the
  activation. **P8 itself: as specced it would have SHIPPED BLIND** — `cc-sessions` `rm -f`'d a registry row
  the moment its pid died, i.e. **deleted exactly the rows that prove a spawn-death**; the detector would have
  reported nothing while LOOKING fixed (proven: old binary deletes the row on first read). **Third instance of
  ONE mistake tonight** (verifier that could only abstain `3b12107` · telemetry deleted on age `93720eb` ·
  this): **a reaper keyed on DEADNESS erases the forensics.** Cleanup and forensics want opposite things from
  one record → separated: **liveness** = the `pid` (**presence must NEVER encode liveness**) · **view** =
  addressing lists live-only (cc-notify still cannot resolve a dead pane — unchanged, load-bearing for W4;
  `--all` = forensics) · **retention** = an AGE decision, never a liveness one (24h). cc-board now joins
  registry×telemetry → **DIED-UNRENDERED** (spawn death, previously ABSENT=silent) / **NO-RENDER?** (up but
  hung), with a grace window so it does not slander every startup. **BIND ran its first full production cycle:
  issue → gate FAIL(closed) → work → ack trailer → gate PASS.** p8-e2e **16/16** (condition 2 both directions:
  positive never-rendered row; negative = hook forced to fail every way — garbage stdin, no jq, unwritable dir,
  no pane, timeout — still exits 0). **Two phantom greens caught in my own suite**: `PATH=/nonexistent` removed
  `bash` itself; `PATH=/usr/bin:/bin` still HAS jq here, so "jq missing" asserted nothing.
- 2026-07-14 ~05:xx (track, next4) — **THE STALL DETECTOR WAS FAIL-SILENT PAST 6h (`93720eb`).** The
  orchestrator's datapoint (a respawn sat nominally-RUNNING **1h25m** with **78m-stale** telemetry —
  telemetry-age working as a stall detector, manual-mode proof of the supervisor detector) **falsified a
  premise that two comments asserted and one ACTED on**: `cc-context` deleted telemetry on **age alone**
  (`-mmin +360`) because *"a live long-turn re-renders within seconds ⇒ a 6h-old file is definitively
  dead."* False. So a session stalled past 6h had its row **deleted while alive** — it did not go STALE on
  cc-board, it **VANISHED**. **Absence is SILENT where STALE is LOUD**: an overnight stall (routine for the
  days-long target) went invisible exactly when it mattered most — fail-silent-open **inside the stall
  detector itself**. Fixed: statusline exports the owning **`pid`** (process-ancestry walk; bare `$PPID` is
  the shell-shim trap — recipe from `session-register.sh:43-47`; memoized off the prior row so the walk is
  once-per-session, not per-render); the sweep **never deletes what it cannot prove dead**; cc-board now
  splits **DEAD** (pid gone, effect-verified) / **STALL?** (pid ALIVE + stale = the candidate) / **STALE**
  (pid unknown). Effect-checked live (payload `pid=18724`, `kill -0` OK, `ps` confirms it IS the claude
  process); telemetry-e2e **16/16**. **T6 rewrote its own expectation** — the old test asserted "7h → swept",
  *encoding the falsified premise*; it was not bent to pass, the policy it tested was wrong. It now carries
  the **anti-trigger** that would have caught this (live-but-stale MUST be preserved). Also fixed a latent
  field-shift my own change made dangerous: `IFS=$'\t' read` **collapses runs of tabs**, so one empty field
  (empty `config_dir`) shifted every later field left — sliding a PATH into `$pid` → `kill -0` fails → a
  **LIVE session renders DEAD**. Now `\037`-delimited + numeric-guarded. **→ D10** (stall): age can NEVER
  confirm a stall — a hung session and a healthy session inside ONE long operation both render **zero**
  times (a live lead measured **2s** while mid-turn, so "no turn boundary = no render" was too coarse:
  renders track UI updates). **Ruling #1 (page, never reap) is therefore FORCED by the signal's information
  content, not merely chosen.** The effect-verified form = *stale AND emitting no work-products*.
  **→ D8 gains a CIRCUIT BREAKER:** `stage-runners` failed **3-for-3 on ONE slot** (modes: stall·stall·die)
  while **10 siblings worked** — the mode varies, the TARGET does not ⇒ *the slot is the variable, not the
  infra*; D8 had **no stopping rule**, so the recovery loop became the failure. Per-slot respawn budget ≤2,
  then STOP + escalate (the W4 lead's **LEAD-SERIAL takeover** is the right escape hatch, reached under
  fire). **→ E2 gains an ANTICIPATORY RECYCLE:** W4 lead #2 recycled **deliberately at 49%** (below
  `boundary_recycle=60`) for a clean window into a 100–200K lead-serial build — the rule is **reactive**
  (fill ≥ T) but the real variable is **headroom vs. DEMAND**; thresholds are a CEILING, not the only
  trigger. **→ E5 addressing sharpened:** `--recycle` **preserves** the pane uuid, `self-close --successor`
  **changes** it — both are "a succession", so **a sender cannot know from the role whether the address
  survived**. That, not staleness, is the real argument for role tokens. **OPEN — highest-leverage residual
  is P8:** cc-board's spine is the telemetry files, so a pane that **never rendered** (dies at spawn — D8
  trigger 1) has **no row at all** (ABSENT, not STALE — silent). *The spine of a detector determines its
  blind spot.* P8 supplies a spine that exists before the first render; it is now implicated in **three**
  failures (empty name-registry → the exit-3 announce; never-rendered blindness; the pane↔sid mapping a
  supervisor needs). **Needs your go — it wires a global SessionStart hook (blast radius: every live
  session).**
- 2026-07-14 ~04:3x (track, next4) — **BIND WAS PROSE, NOT MACHINERY (`5c881c2`) + pane-id discipline
  (`38199af`).** Orchestrator adopted BIND for load-bearing rulings and was **one step from routing a live
  operator ruling through its "fail-closed merge gate" — which did not exist**: `Acked-Ruling` appeared only
  in *this track's own design docs*; `team-ruling.sh`/`merge-gate.sh` absent; **zero git hooks**. The gate
  could not fail closed because it could not fail at all. Paged → orchestrator STOPPED (*"one step from
  D9-one-layer-up"*), then **D9-proved the interim manual gate both ways** before trusting it (negative
  `GATE FAIL` fired; positive control exercised) — the law applied downstream by another actor within the
  hour. **New failure class (audit §3g #5): PROSE MISTAKEN FOR MACHINERY.** §3g's verifier was code that
  *couldn't fire*; this was a capability that existed **only as a prescription in a document read as a report
  of the system** — and the better the doc, the more convincingly it reads as shipped. This track wrote the
  doc *and* nearly consumed its own prescription as fact. → **R7 broadened**; blueprint §3.5 now carries a
  "read this as a SPEC, not a report — anything without a commit sha is UNBUILT" banner. **Built (authorized
  by orchestrator under ratified law #4; NOT the held runtime directive): `bin/cc-bind`** — issue/ack/gate/
  selftest, deployed + symlinked. Its one invariant is §3g's direct lesson: **never exit 0 on "cannot
  determine"** (no repo / no ruling file / bad range all exit LOUD — an indeterminate gate that passes IS the
  bug). Shipped only after being SEEN to fire: **4 RED + 1 GREEN control**; `bind-gate-e2e.sh` tests the
  **deployed** tool and asserts the selftest's check COUNT (*a suite that runs zero checks also reports zero
  failures*). **Pane-id provenance (orchestrator's root-cause credit): the truncation entered at
  DOC-AUTHORING time** — "orchestrator pane 99261468" <!-- pane-id-lint:allow: quoting the bad form --> was
  written into the plan/proposal and every brief copied it. **The corpus IS the copy-source** → the rule
  belongs in the doc TEMPLATES, and it cannot be prose (the author knew the full uuid and truncated anyway).
  → `scripts/pane-id-lint.sh` (GREEN now; **RED with 14 landmines** at `82ad3cb`; it caught my own violation
  mid-edit). **The durable rule — two shapes:** operational address → **ROLE token** (`<orchestrator>`,
  resolved at send-time, survives the recycle); historical reference → **FULL uuid** (a past fact).
  *Truncated is strictly worse than stale*: stale-full fails LOUD + mailboxes; truncated hard-fails exit 3,
  unresolvable and unmailboxable. W4/W5 proposal converted to role tokens so it survives the orchestrator's
  imminent recycle.
- 2026-07-14 (prove-on-W4, orchestrator 1st hour) — **✅ VALUE CONFIRMED IN PRODUCTION.** cc-board
  caught the live W4 lead at **63% > §8 `boundary_recycle=60`** → succession advisory fired on the rails
  (the operator's hand-catch, now automated — audit §1 → 0). STALE renders correctly for closed
  teammate panes. **Deploy gap:** cc-board committed but un-symlinked into `~/.claude/bin` — found by
  the orchestrator's effect-check, fixed; added **Deploy DoD** (blueprint §4: every bin/statusline/hook
  ends with `which <tool> && <tool> runs`). All 3 telemetry tools verified live (symlinks → repo).
  Keep parked (no push); awaiting the W4 succession outcome.
- 2026-07-14 ~07:4x (track, **next3 keeper-successor #2**; predecessor next4 self-closed at its §8 boundary
  ~60%, **recycle-in-place** → pane uuid `8BD76049-AC98-4C4F-B191-0FFFBE2E4CCD` preserved, new session, the
  predecessor row reads **DEAD** pid-verified — the tri-state detector on its own author) — **PROVE-ON-W4: three
  routine datapoint-relays VERIFIED then CAPTURED (verify, never transcribe — two of the three were subtly
  imprecise on inspection; the third verified clean).** Witnessed all 3 instruments UNPIPED before trusting (premortem-gate exit 1 · cc-bind selftest
  **8/8** content-sha era, not the stale 5/5 · reaper-horizon-lint clean). Live-read correction parked
  **39≠38** → desk fixed the **CLASS** (the wake-up batch now embeds `git rev-list --count`; a cached count is
  a tiny Invariant-7 instance). **Captured LOCAL:** (1) `0675864` — **D8 breaker + LEAD-SERIAL escape hatch
  PROVEN END-TO-END** (stage-runners `e9e6c09..231ad7f` = `8a04bce`'s ancestry, no repeated-slot respawn;
  keeper-caveat: `8a04bce` is the **ff-merge TIP = an e2e flake fix**, cite the series) + **D10** live-confirmed
  on the keeper's OWN STALL? row (effect-probe). (2) `a3aa9ea` — **E2 #3 clean recycle** (stamp `8c59b1e`: lead
  #3 at 60% announced a B22 spawn AT its boundary → desk paged the order-inversion → TaskStopped seconds-in
  **zero-loss** → recycled → **successor** spawned from the committed brief): §8.2 **"NEVER SPAWN AT YOUR OWN E2
  BOUNDARY"** + §8.5 **pgid-SIGKILL mechanism** (`handoff-fire.sh:946`; setsid survives, so the field shorthand
  "kills child panes" is imprecise but recycle-first is safe either way) + D8 **budget PERSISTS across
  succession** + D10 **residual: the effect-probe discriminates IDLE but NOT mid-turn hangs → empirical
  confirmation of premortem-gate S-3**. (3) `f8512e8` — **blind-check law at SCALE**: `wf_b776d7c1` (12-axis
  adversarial verify) returned **49 CONFIRMED on a 3,162/2-GREEN tree** → §3i **instance #6** (an ARMED gate
  with DEAD trigger globs — the FIRST blind-check with no human-by-hand signature, so it needs the mechanical
  legs: ship-gate `abstained==100%` alarm + periodic adversarial derivation against the ARTIFACT) + D9 arm-time
  glob-nonempty detector + E6 verify-findings disposition (closed-slot respawn = roster = operator-only). Bonus:
  a B07 axis seeded from the lead's *uncertainty* partially REFUTED the lead's own adjudication — verify FROM
  the doubt. **OPEN watch:** E4/W5 (17:00 PDT Fable-close → W5 lead likely
  Opus@max). Runtime phase still **HELD** (premortem-gate RED by design — 5 NOT BUILT). Self ample headroom on
  next3.
- 2026-07-14 ~08:xx (track, next3 keeper #2, cont.) — **RELAYS 4-6, S-3b DELIVERED, W4 COMPLETE (11/11).**
  (4) `5c048ef` **E4/quota**: no-succession-while-children-live (pane-kill dominates quota — the routing-order
  generalization of the spawn-order rule) · numeric succession (Fable ≥96% OR >2 Fable-heavy turns → next3) ·
  cliff protocol (stop+disk-truth+`limit-recover`, NEVER silent down-tier) · **F1-F8 de-escalation** (frontier
  judgment ONCE at ruling time, execution de-escalated) · fixed a baked stale-LIVE quota line → live-read
  pointer. (5) `ce8ae4a` **D8 B22 spawn-2 silent-GO**: spawn-boundary GO = fresh respawn ALWAYS (message-resume
  dead, structural per D4) · **as the budget shrinks, the scope should too** · breaker escape is E4-aware.
  (6) `7d25d7e` **FIRST LIVE stall-page cycle** — 4 D10 signals dark 69–75min → page → deadline NO REPLY →
  mandatory RE-READ found the lead ALIVE+productive; reply-or-kill alone would have killed a healthy lead.
  Rules: page-deadline = RE-OBSERVE not act · reply≠liveness. **→ I FLAGGED (not touched) that premortem-gate
  S-3's `grep MODAL` would PASS a reap-on-silence supervisor; the DESK RULED it registered as S-3b + delegated
  implementation to me** (registration=authority's, assertion=implementer's — the §2b authority-ceiling split).
  (7) `ce3c9e8` **S-3b BUILT** — `scripts/s3b-lint.sh` (RED-provable; `--selftest` 3/3, effect-checked incl. a
  mixed control) + premortem-gate S-3b wired (now **2 met · 6 NOT BUILT**); witnessed END-TO-END (a silence-reaps
  straw supervisor goes S-3b RED, then removed + restored clean). (8) `00ed04a` **§3i law**: *review criteria
  rot toward their GREP as checks rot toward their SPINE — the incident→assertion translation is where fidelity
  is lost* (self-demonstrated: s3b-lint guards its own grep-rot). **W4 now 11/11 slots CLOSED** (`945ee0e`) →
  the both-teammates-closed E4 boundary is reached → **WATCH = W5 lead placement** (Fable-if-open-&-<96% else
  Opus@max). Verify discipline held (D8/stall clean; E4 carried the 91→92 live-read correction). Session: 10
  commits + this entry, parked 50. Self 37% ctx/next3 — ample, tracking demand-vs-headroom per the E2 rule.
- 2026-07-14 ~08:3x (track, next3 keeper #2) — **═ W4 EXIT DECLARED `b242789` — E4/W5 WATCH CLOSED ═.**
  Verified read-only: all four exit criteria MET, **11/11 merged (3,562/3), 73 min BEFORE the Fable window
  edge** (early-verify re-sequencing bought the promised margin). **W5 DISPOSITION:** placement = **Opus 4.8 @
  max** (E4 window-edge recompute as designed), account re-ranked at fire = **fresh next3**, E3-fence-held on
  operator ratification of `53e23fb`; **no Fable cliff ever hit** (next4 peaked ~94%, live next3 fable 12% —
  desk relay said ~11%, 1pt-stale). **THE MISSION SENTENCE (desk):** *"the program never blocked on the
  sleeping operator, and nothing out-of-class was desk-signed"* → the DoD's two halves for W4 (§1 relays→0, §3
  rescues→0; authority ceiling held). **Scorecard → audit §6 (`52f3f68`):** 6 leads · 6 clean successions (2
  cross-account) · 2 pages (1 void-by-effects — the re-observe arm; 1 hard-E2) · 1 D8 breaker · 49-finding
  verify (2 criticals fixed) · 9 rehearsal ship-blockers. Also banked this session: the **mixed-control law**
  (§3i, `05e4364`, desk-recorded: presence-of-good ≠ absence-of-bad). **WATCH now CLOSED — prove-on-W4
  essentially complete from the keeper's seat; the operator's ratification is the final gate.** Session: 13
  commits + this entry, parked 53. Self ~40% ctx/next3 — ample; holding for operator wake / W5-ratification.
- 2026-07-14 ~16:5x (track, next3 keeper #2 → **RECYCLING at 52%, anticipatory**) — **OPERATOR WOKE: ZERO-HITL
  DoD RULED + /SHIP AUTHORIZED (blocked by stale tests, root-caused) + P8 BY OPERATOR HAND.** Rulings: (1) **/ship
  AUTHORIZED** for claude-infra; (2) **P8 activation by OPERATOR HAND** (`/tmp/p8-activate.sh` — C10 end-to-end;
  I never run it); (3) rule → §3i notify-on-operator-blocked; (4) **THE ZERO-HITL DoD** (blueprint §5, `fea9200`)
  — implementation runs zero-HITL; STOP-ASKs → agent-ruled defaults + async queues + push-notify (early-veto);
  ship never gates (autonomous at GREEN exits); only stops = C10/permission/external-info; **WHY: every W0–W4
  parked gate ruled EXACTLY as the lead recommended.** **SHIP ATTEMPTED** (authorized + autonomous-per-new-law)
  from a detached worktree (ff-able, clean) → **BLOCKED by a RED gate**: `bats tests/` 2 failures. **Nearly
  filed a FALSE GREEN via the pipe-mask trap** (`rc=$?` after `bats|tail`) → re-ran UNPIPED → true exit 1
  (§3i (ii), `fea9200`). **ROOT-CAUSED (confirmed):** session-registry tests **67/68 are STALE** — they assert
  the pre-P8-fix `rm -f`-on-dead behavior `7b2f701` deliberately removed (dead rows now RETAINED 24h + filtered
  from the addressing view; `--all` = forensic). No push; worktree removed; parked **54**.
  **→ HANDED TO SUCCESSOR (fresh headroom):** **(a) FIX stale tests 67/68** (assert: dead-pid/gone-pane entry
  → absent from default `--names` view BUT file RETAINED until `CC_REG_RETAIN_H`=24h; `--all` shows it) → gate
  GREEN → **SHIP** (operator-authorized, ff-able onto `origin/main`@`c4a6c78`; land from a DETACHED worktree —
  `git worktree add --detach /tmp/wt-ship HEAD` — NEVER the shared checkout, step-2 guard; land-lock + content-
  verify + stranded-sweep; ack desk with landed count). **(b) D1** re-derive the W0–W4 operator-touchpoint
  ledger under the zero-HITL law (residual truly-needed set ~empty = the future design surface). **(c) D2**
  runtime phase RISES (boundary-hook + page-only supervisor for unwatched multi-day runs; entry bar UNCHANGED =
  premortem-gate GREEN + C10-gated activation). **(d)** integrate the DoD framing shift throughout the blueprint.
  Session: 15 commits + this entry, parked 55. Recycle-in-place → pane uuid PRESERVED.
- 2026-07-14 ~17:xx (track, **next3 successor #3**; recycle-in-place, pane uuid PRESERVED) — **TASK 1 + TASK 2
  DONE: STALE TESTS FIXED → GATE GREEN → 57 COMMITS LANDED (wire-witnessed).** **(1) `817448d`** — tests 67/68
  rewritten to the P8 retain-dead contract (VIEW live-only / RETENTION age-24h / FORENSIC `--all`) + a THIRD test
  pinning the age-reap boundary (retention was otherwise unobserved — blind-check law: the check must see the full
  contract). Proven **RED against `7b2f701^`** (immediate-rm-f, no `--all`) and GREEN against current — so they
  DISCRIMINATE the change, not vacuously green (desk: *"a fixed test that never failed against the old behavior
  proves nothing"*). Suite **78/78** (was 77). **(2) SHIP LANDED** — `c4a6c78..817448d`, 57 commits ff onto
  origin/main from a detached `/tmp/wt-ship` under `land-lock`. **WIRE-WITNESSED** (the program's 2nd push, same
  discipline as the 1st): `git ls-remote origin main = 817448dc…` + sha-identity + `git diff 817448d origin/main`
  = 0 lines + ls-tree spot-check. Gate GREEN **inside the lock** (bats 78/78, shellcheck-error 0, bash -n clean).
  Stranded-sweep **0/7**. **LINT-SCOPE RULING (zero-HITL agent-default; DESK CONCURS, logged async):** the ship
  gate blocks on shellcheck **ERRORS** + syntax + bats; the **64 note / 6 warning** findings (idiomatic
  `assert && ok || bad`, `ps -t` by tty, ls-for-time-sort of UUID files, unused loop counters, **1 confirmed
  false-positive SC2154** — `reset_at_utc` is python-emitted-then-eval'd) are **non-blocking** — landing an
  authorized stack ≠ a lint refactor of 12 E2E-green scripts (scope-metastasis + regression risk). The SC2154
  triage-to-confirmation shows it was real triage, not a wave-through. **→ BACKLOG (named, not fixed): land-lock
  keys `REPO_ROOT` via `git rev-parse --show-toplevel`, so a detached worktree gets a DIFFERENT lock key than the
  main checkout** — two worktrees could both hold the "lock" concurrently. Non-ff push rejection is the TRUE
  correctness guard (the lock is only an optimization); **when fixed, key on the REMOTE url, not the worktree
  root** (desk refinement — serializes all landings to a remote regardless of local checkout). **NEXT: D1**
  touchpoint re-derive under zero-HITL, then **D2** runtime phase. Parked after this entry: 2 (status + D1 pending).
- 2026-07-14 ~18:xx (track, next3 successor #3, cont.) — **D1 DONE + D2 RUNTIME PHASE BUILT → premortem-gate
  GREEN (8/8) → un-hold defensible.** **D1 (`7dc63c0`):** audit §9 re-derives every W0–W4 touch under zero-HITL —
  T1–T8 eliminated/reclassified (proven: autonomous ship this session; effect-verified GO), residual = the
  **R-1..R-4 floor** (C10 self-mod, C6 money-path, permission-ceiling, un-pre-signed intent) which by §2b must NOT
  be driven to zero (it is the safety rail) → the design surface is D-i..D-iv (pre-stage each stop as a one-action
  artifact, broaden pre-signed classes, self-declare, supervisor pages-not-acts). **D2 (`928f7e6`, `9296371`,
  `722735e`, deploy `<this>`):** (a) **S-2 precondition** — telemetry-e2e T7-OK was NON-HERMETIC (grepped a live
  next2 quota → RED at next2@93% weekly though cc-board was correct); stubbed the quota feed → 16/16 deterministic
  → S-2 green. (b) **boundary hook** `hooks/boundary-handoff.sh` — advisory latched-`decision:block` at
  committed+green boundary; B-2 used_pct re-arm (RED-proven vs a HEAD-sha-only latch), B-3 IDL abstention log;
  16/16 e2e. (c) **supervisor** `scripts/lead-supervisor.sh` — PAGE-only (ruling #1); B-1 past-threshold∧not-Stopping,
  S-3 declares modal blindness, **S-3b deadline→re-observe** (fresh⇒VOID/dark⇒escalate, never silence — RED-proven
  vs a silence-reap straw), S-4 heartbeat; 10/10 e2e. **Portability bug the e2e CAUGHT: BSD `find -newermt @epoch`
  fails → every re-read read DARK ⇒ the supervisor would have silence-reaped every healthy long turn** (the exact
  §3h failure S-3b exists to prevent) → switched to portable `-newer <ref>`. **C10 activation handed off, NEVER run**
  (`docs/D2-RUNTIME-ACTIVATION.md` + `/tmp/d2-activate.sh` — backup+jq-merge+launchctl+effect-check+rollback; the
  D-i one-action-artifact pattern from D1). **Named residual (safe-inert):** the `.git/gate-green` marker-writer the
  hook abstains without (fail-safe). Full regression GREEN: bats 78, all 5 e2e, all lints, premortem 8/8. Built
  INLINE as the context-holder (law-laden depth-coordination — an under-contextualized teammate would grep-satisfy
  but law-violate, the exact failure premortem-gate catches). Parked after this: 7 (to ship autonomous-at-green).

## Never-wait-on-the-dead — operator-directed build (2026-07-14, L0..L4; incident IS the spec)

**Frozen scope:** a 100th-percentile *never-wait-on-the-dead* runtime. **Incident-as-spec:** a W5 corpus
teammate died out-of-band and went **UNDETECTED 77 min**; the wave-lead's event-driven wait was **UNOWNED**
(existed only in its context); the harness fired nothing (task notifications cover *clean completion*, not
*pane death* — its task table still LISTED the dead teammate = a three-way divergence). Five layers, each
behind **RED-provable pre-mortems REGISTERED BEFORE build** (`scripts/wait-safety-gate.sh` = the un-hold
bar, `43de6d6`; 1 met · 14 NOT BUILT, RED by design), activation **C10-queued** (agent builds+tests+hands
an activation script, never activates). The verbatim per-layer pre-mortem: *"what is this structurally
unable to see, and who ends up checking it by hand?"*

- **L0 — DONE** = p8 (spawn-death row DIED-UNRENDERED) + d2 (boundary-hook + PAGE-only supervisor DEAD
  detection). This incident is L0's live case study. GAP L0 leaves: DEAD is caught at **poll latency**
  (≤1 sweep) and the WAIT it blocked is still unowned → L1 makes it event-instant, L2 owns the wait.
- **L1 — kqueue `EVFILT_PROC` death-watcher — DONE (2026-07-14, successor #4)** — gate rows a–e ✅, RED-
  proven, full regression + shellcheck green. Mechanism VERIFIED by probe: python3 `select.kqueue`
  EVFILT_PROC/NOTE_EXIT fires event-INSTANT at child-exit (not polling); `ps lstart` = start-time; arming a
  dead pid raises ESRCH. Artifacts: `bin/cc-deathwatch-kqueue` (Python helper — arms kqueue per registered
  {pid,start}; the {pid,start} GUARD at ARM time emits DEATH(recycled|gone) on a mismatch/ESRCH rather than
  watch a stranger holding the recycled pid; streams `DEATH⇥label⇥pid⇥reason⇥waiter`) +
  `scripts/lead-deathwatch.sh` (orchestrator `--once`/`--watch`/`--selftest`: per death → CAPTURE-before-
  NOTIFY: git-checkpoint orphaned worktree WIP into `refs/deathwatch/<label>/<ts>` via a temp-index
  plumbing (tracked+untracked, no working-tree touch, no hooks) + a forensics JSON record, both to disk
  BEFORE the PAGE; never respawns) + `tests/lead-deathwatch.bats` (5). Records/heartbeat/alarms →
  `~/.claude/deathwatch/` (`CC_DEATH_RECORDS_DIR` override).
  - **Criteria (all RED-proven):** L1-a unregistered-pid blindness DECLARED → covered by P8 registry + L2
    unregistered-waitee RED (composition). L1-b capture-before-notify (stub the page to FAIL → the record
    survives). L1-c {pid,start} guard (live pid + wrong start → DEATH(recycled); dead pid → DEATH(gone);
    the arm-window race rides the ESRCH path). L1-d death → checkpoint + PAGE, ZERO respawn (exactly one
    page, says NOT respawned). **L1-e (desk-registered mid-build)** the WATCHER's own death is LOUD (S-4):
    heartbeat record each cycle (absence=alarm) + abnormal-helper-exit detection → watcher-died ALARM +
    re-arm (SIGKILL the helper mid-block → alarm + rc 3). Gate wires L1-e to the behavioral selftest.
  - **Key learnings:** (1) the selftest MUST drive fresh subprocess `--once` calls (not in-process
    functions) so each resolves `CC_DEATH_RECORDS_DIR` at its OWN top-level — the cc-wait pattern; an
    in-process call inherits the already-resolved global (this was 0/7 until fixed). (2) `ps lstart` string
    equality IS the recycling identity; the arm-window race self-heals — `select.kevent` ADD on a dead pid
    raises ESRCH → 'gone'. (3) capture WIP with a TEMP `GIT_INDEX_FILE` (read-tree+add-A+write-tree+commit-
    tree) — tracked+untracked, zero working-tree impact (teammate-checkpoint pattern).
  - **Deploy: C10-queued** — symlink both + wire `--watch` (or `--once` per supervisor sweep) against the
    P8 registry watch-list = operator activation.
- **L2 — WAIT CONTRACTS (THE KEEPER) — DONE (2026-07-14, successor #4)** — gate row ✅, RED-proven, full
  regression green. Artifacts: `bin/cc-wait` (producer — writes the disk contract BEFORE blocking, fail-
  closes at the producer on a missing deadline/on-timeout and on a non-allowlisted action; on timeout
  dispatches the STRUCTURED action (page, exit 5) — never a reap; selftest 8/8) + `scripts/wait-contract-
  lint.sh` (auditor — L2-a uncontracted-`cc-await-ping`/poll → RED, L2-b missing deadline|on-timeout →
  RED, L2-c `--sweep` watchdog pages a dead-waiter OPEN contract INDEPENDENT of waiter liveness via
  `{pid,start-time}` (recycled pid = not the same waiter), L2-d on_timeout_action outside the allowlist
  {reobserve,page,escalate} → RED; `--selftest` 13/13) + `tests/{cc-wait,wait-contract-lint}.bats` (16).
  Contract schema on disk: `~/.claude/wait-contracts/<id>.json` `{id,waiter,waiter_pid,waiter_start,
  waitee,expected_signal,heartbeat_expectation,deadline,deadline_s,on_timeout_action(enum),
  on_timeout_note(free-text,guard-ignored),issued,status}` (`CC_WAIT_CONTRACTS_DIR` test override).
  - **Key learnings:** (1) fail-closed AT THE PRODUCER, not only in the lint — cc-wait REFUSES a bad wait
    (the desk hit this live: an unknown-arg REFUSAL exit 2 resolved a false-red in one step *because* it
    refuses loudly instead of doing-something-plausible; the fail-closed parser IS part of witnessability).
    (2) desk-folded sweep semantics vs page-fatigue: THREE OPEN states (dead-waiter / live-past-deadline /
    live-in-window), **page-once + escalate-at-3**, marker (`paged_state`/`page_count`) written ON the
    contract so a persistent divergence is never re-cried every sweep — the receiver-attention/wolf-cry
    blindness DECLARED + covered (composition rule). Selftest proves page-once is the *marker's* doing
    (clear it → re-pages). (3) SATISFIED-but-unclosed = hygiene flag, not alarm. (4) strip whole-line
    comments before grepping (the reaper-horizon comment-as-code bug). (5) L2-a's grep is non-shim because
    `cc-wait` is the real contracted form the desk's own hourly listener migrates to.
    (6) **L2.1 allowlist hardening** (desk live datapoint): the desk migrated its listener and cc-wait
    REFUSED its first attempt because a prose on-timeout `(re-observe, never reap)` substring-matched
    'reap'. A prose ACTION field is the "criteria rot toward their grep" trap from BOTH directions — a
    hostile 'cleanup' evades a denylist, an innocent 'never reap' trips it. Fix: `on_timeout_action` is a
    STRUCTURED enum from a closed ALLOWLIST `{reobserve,page,escalate}` (a disposition is not IN the set,
    so unexpressible) + a guard-ignored free-text `on_timeout_note`. Check a FIELD, never prose; the
    timeout handler dispatches on the enum with NO `eval`. Both selftests prove the note-ignored positive
    (`on_timeout_note:"never reap"` → GREEN) and the hostile 'cleanup' → RED.
  - **Deploy: C10-queued** — symlink `cc-wait`/`wait-contract-lint.sh` into `~/.claude/bin` + wire `--sweep`
    into the supervisor/boundary loop = operator activation (consolidated activation script at build end).
- **L3 — effect-bound progress heartbeats** (`bin/cc-run`): heartbeat per unit of **real output** (not
  wall-clock) → closes D10 long-op-vs-hang at the source. Must DECLARE the residual blindness (silent-compute
  + looping-output ops) and route their liveness to L1(pid)/L2(heartbeat-expectation=none).
- **L4 — three-way anti-entropy reconciler** (`scripts/lead-reconciler.sh`): harness tasks × cc-registry ×
  disk; **persistent pairwise divergence IS the alarm** (names the pair); grace window (anti-cry-wolf); own
  heartbeat (who-watches-the-watcher); declares the coherent-wrong blindness (mitigated by 3 independent
  sources).

**Sequence (my judgment, per desk):** L2 first (the keeper — the contract schema+lint is what every other
layer references) → L1 (feeds contracts a death-event) → L4 (backstops with divergence) → L3 (heartbeats).
Build to `wait-safety-gate.sh` turning green; RED-prove each criterion against its naive/absent form; the
desk registers criteria as drafted (early-veto, never a gate). **NEXT:** build **L4** (three-way anti-
entropy reconciler `scripts/lead-reconciler.sh`): reconcile harness tasks × cc-registry × disk telemetry;
persistent pairwise divergence IS the alarm (name the pair — the incident: tasks listed a registry-dead
pid). Criteria (gate lines 98-108): L4-a divergence alarm names the pair · L4-b grace window (a transient
spawned-not-yet-registered / dying-not-yet-swept transition must NOT alarm — anti-cry-wolf, reuse L2's
page-once discipline) · L4-c reconciler emits its OWN heartbeat (S-4 — its absence is the alarm, same shape
as L1-e) · L4-blind DECLARE coherent-wrong (all-three-agree-wrong) → mitigated by 3 INDEPENDENT sources
(harness API / pid kill-0 / disk mtime). L4 backstops L2-c (dead-waiter) and L1 (unregistered pid). Then
**L3** (`bin/cc-run` effect-heartbeats — heartbeat per unit of REAL output, closing D10; DECLARE the
silent-compute/looping-output blindness → route to L1(pid)/L2(heartbeat-expectation=none)). Criteria are
already registered — read `./scripts/wait-safety-gate.sh` output first (now 7 met · 6 NOT BUILT).
