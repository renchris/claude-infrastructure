# Desk self-handoff — UNIFIED DESIGN (synthesis of both Fable panels + lead reconciliation)

Deterministic desk self-recycle: context%>55 (or floored rot-tell) AND desk-idle → fires the
sanctioned `handoff-fire.sh --recycle` SAFELY. Synthesizes H-DSH-1 (actuation, panelist a0d35…) +
H-DSH-2 (safe-gate, panelist ab498…), reconciled against the lead's pre-panel ground truth. Probes
P1/P4/FM-D/FM-F all CONFIRMED live → both system models validated; high confidence.

## The reframe that reorganizes everything (H-DSH-1 Stage 0 — NEW, the sharpest single insight)
0/2419 fires decomposes as **1977 not-armed**. Determinism does NOT die at the fire step — it dies at
the **ARM** step, which is itself model-diligence (the same "noticing" problem one level up). Making the
fire deterministic while arming stays manual just moves the non-determinism. ROOT FIX = **deterministic
arming**: whatever spawns a monitoring desk arms it (arm-at-spawn), OR the desk self-arms on
SessionStart when it is a monitoring desk. Arm is cwd-keyed and survives the in-place recycle
(`waiting-recycle.sh:74-77`; `handoff-fire.sh:668 IN_PLACE=1`) — both panels independently RESOLVED the
p04 audit's open G-P4-5 ("does the arm ride along?" → YES).

## Mechanism (4 stages)
- **Stage 0 — deterministic arm + standing brief template.** `arm --brief <template>` hard-fails if no
  successor-brief template exists (kills the empty-payload class upstream). Spawner arms the desk.
- **Stage 1 — advisory (EXISTS, unchanged).** First gate-true → today's `decision:block` advisory;
  healthy model runs the rich `/handoff` (strictly the best payload). Grace window ~120-300s.
- **Stage 2 — deterministic FIRE at K=1.** Next gate-true for the SAME SID after grace → the hook
  composes an ATOMIC prompt file (standing template + `dod-persist.sh get` + AGE-GATED intent file +
  the directive: "recycled deterministically; FIRST ACTION = re-derive watch state from disk: registry,
  mailboxes, wait-contracts, worktrees, cc-board") and execs
  `handoff-fire.sh --recycle --prompt-file F --session-id ${ITERM_SESSION_ID##*:}`, then emits
  `decision:block` "recycle FIRED; do NOT run handoff-fire yourself." **Cap-EXEMPT** (bound = the
  one-fire-per-SID latch, a TIGHTER bound than MAX=3 — NEW: the cap check at `:148-150` runs BEFORE the
  trigger, so 3 ignored advisories would permanently SILENCE a non-exempt Stage 2). K=1 because large K =
  non-deterministic for K cycles + each advisory burns a 600s cooldown → K=3 ≈ 30+ min of rot.
- **Stage 3 — idempotency in `handoff-fire.sh --recycle` (new, small).** (a) `[ -s ]` empty-payload
  guard (FM-D live bug — `:618` is `[ -f ]` only → `claude ""` task-less successor); (b) mkdir-lock keyed
  by pane SID, TTL ~15min, cleared by the watcher on confirmed relaunch → kills hook+model double-fire
  and the double-watcher race.

## The GATE — SAFE-FIRE predicate (WHEN Stage 1/2 may fire)
TRIGGER: fresh(`/tmp/cc-telemetry/$SID.json`,≤180s) AND used_pct≥55 — OR — rot-tell AND fresh AND
**used_pct ≥ FLOOR(~25)** [NEW, probe-P1-confirmed LIVE BUG: the shipped regex trips on healthy watch
narration like "Re-checking which sessions are still running"; the floor is derivable — rot needs
accumulated context].

SAFE — ALL hold (existing S1-clean-tree + S2-no-open-decision, PLUS):
- **S1+** no git sequencer state (`MERGE_HEAD`/`rebase-merge`/`rebase-apply`/`CHERRY_PICK_HEAD`) — catches
  "mid-merge between porcelain-clean steps."
- **S3** no live INBOUND wait: no OPEN `wait-contracts/*.json` with `waitee ∈ {UUID,SID,role-names,
  registered-name}` AND `deadline>now` AND waiter-alive (`kill -0 waiter_pid` + `waiter_start` match).
  (The desk's OWN waiter-contracts do NOT block — durable on disk, successor resumes.)
- **S4** quiet inbox: desk mailbox (`~/.claude/mailbox/<UUID>.md` + role) mtime older than QUIET_S
  (~120-300s). **LOAD-BEARING** — cc-dispatch workers `cc-notify` the desk role but do NOT write
  contracts, so S3 alone under-detects a blocked worker.
- **S5** no live context-bound teammates (`teams/session-${SID:0:8}*/config.json` members live). **HARD
  HOLD, NEVER relaxes** — teammate/TaskOutput results route to the dying SID, unrecoverable by any
  successor. (Also covers the lead's own in-flight background subagents once they write a spawn record —
  today they don't: negative space → the FN-safe cover is S5 + the model-confirm layer.)
- **S6** fire-settle: no `{action:"fired"}` by this desk in `idl.jsonl` within SETTLE_S(~300s).
- **S7** fresh self-telemetry required on BOTH trigger paths (today only the threshold path checks age).

**Two-tier bias (NEW — the sharpest gate insight):** HOLD-bias (false-negative) is right ONLY in the
soft zone. Above ~80% the calculus INVERTS — an imperfect recycle WITH a brief strictly dominates certain
90% auto-compaction WITHOUT one (both strand, only one writes a brief; `/compact` also kills teammates).
So: **soft zone (trigger..80)** = full S1-S8; **hard zone (≥80)** = relax S1-untracked/S4/S6, keep
**S3+S5 ABSOLUTE**, and emit a distinct ALARM advisory ("cannot recycle safely: <failing clause>,
context critical — resolve NOW") instead of silent abstain.

## No-double-fire (both panels)
- Within-session TOCTOU (cooldown-check :141 vs stamp-write :200; cap RMW): atomic `mkdir`/`set -C`
  acquire BEFORE emit.
- Across generations: SID-keyed one-fire latch (Stage 3) + cwd cooldown + **the used_pct FLOOR closes the
  rot-tell cross-generation storm** (NEW: MAX=3 is per-session → toothless across generations → unbounded
  ~600s-period churn gated only by model compliance; the floor closes it at the fuel source).
- LANDMINE (NEW): `arm` clears the cooldown (`:86`) — a successor that re-arms defeats the loop-breaker.
  Runbook/advisory MUST say "do NOT re-arm" (arm survives the in-place recycle).

## Reconciliation tags
- **CONFIRMED** (both panels re-derived lead priors → confidence↑): recycle in-place (G-P4-5 resolved) ·
  hook env-inheritance feasible · the real crux is THE BRIEF · desk's own waits durable-safe · unsafe
  case = sub-session-blocked-on-me · bias-to-HOLD in the soft zone · mailbox is a durable inbox.
- **NEW** (frontier delta — the 2× spend): `/exit` INTERRUPTS not holds (brief premise + lead prior both
  WRONG; file self-contradicts) · Stage-0 arming is the root cause · rot-floor (live bug) · S5 teammate
  HARD-hold · S1 sequencer-state · S4 mailbox-over-contract · two-tier bias inversion at 80% ·
  cross-generation cap-reset storm · cap-exempt Stage 2 · FM-D empty-payload bug · FM-F /exit-regression
  risk · K=1.
- **REFUTED**: two concurrent panes during recycle · successor reads predecessor telemetry (SID-keyed) ·
  OPEN-zombie contracts litter the dir (0/62) · per-account hook-registration gaps · payload snapshotted
  at fire time.

## SCOPE — core-now (SHADOWED) vs campaign-later
**CORE (this task's frozen DoD — implement now, SHIPPED DAMPED per notify-golive "damp first"):**
1. Gate hardening in `waiting-recycle.sh`: rot-FLOOR (live-bug fix) + S1-sequencer + S3 + S4 + S5 + S7 +
   two-tier bias.
2. Stage 2 deterministic FIRE (K=1, cap-exempt, atomic brief, SID-keyed escalate stamp) — **defaults to
   SHADOW/log-only**: composes the brief + logs `{action:"would-fire"}` to IDL but does NOT exec, until
   the desk is armed `--live`. Operator soaks the shadow logs, then flips to live-fire. (No behavior
   change on any desk until explicitly lit — the damp-first go-live discipline; kill-switch unchanged.)
3. `handoff-fire.sh`: `[ -s ]` empty-payload guard (FM-D) + Stage-3 SID-keyed idempotency latch.
4. Stage 0 deterministic arming: `arm --brief <template>` + the standing template; wire arm-at-spawn
   (find the desk spawner) OR self-arm-on-SessionStart-if-monitoring.
5. Tests: `tests/waiting-recycle.bats` extension (rot-floor, S3/S4/S5, two-tier, cap-exempt, no-double-
   fire) + a `handoff-fire` `[ -s ]`/latch test.

**CAMPAIGN (route to ledger `## Campaign Candidates`, do NOT build inline — generator-class):**
- **C-DSH-1 unifying lifecycle+attestation primitive** (both panels' campaign #1 CONVERGED): one
  SID/cwd-keyed write-before-act record `{state:WATCHING|COORDINATING|FIRING, ts, DoD, lifecycle:
  fired→exited→relaunched→engaged}` maintained by the poll loop + hook + watcher. Dissolves ≥8 holes
  across BOTH sub-problems (hidden-obligation gap, G-P4-4 mission-carry, S6 fire-settle, cc-board STALL?
  ambiguity, Stage-3 latch, cc-notify fence, supervisor sweep target, engagement-verify anchor).
  GENERATOR-class → `/frontier-campaign`. The core above ships SAFE without it (FN-safe approximations:
  mailbox mtime + contract scan + discrete latch).
- **C-DSH-2 per-CC-version /exit queue-semantics conformance test** (dissolves the catnav/FM-F regression
  class + the file's self-contradiction at :63/:657/:1121 vs :554/:1141).

## Implementation status (2026-07-19, branch feat/desk-self-handoff-trigger)
BUILT + tested (50 tests green: 47 waiting-recycle.bats + 3 handoff-fire-validate.bats):
- **rot-FLOOR** (f790f7a) — the probe-P1 live bug; rot-tell needs fresh telemetry + used_pct ≥ 25.
- **gate hardening S1/S3/S4/S5** (55ccafd) — sequencer-state, inbound-wait (waiter-liveness-filtered),
  mailbox-mtime (load-bearing), teammate hard-hold. FN-safe; seams CC_WR_COORD_DIR/UUID/QUIET_S.
- **Stage-2 deterministic fire, SHADOW-default** (5d5e734) — advisory → K=1 escalation after GRACE_S,
  cap+cooldown-exempt (one-fire-per-SID latch), atomic disk-reconstructible brief, `arm --brief/--live`,
  re-arm no longer clears the loop-breaker. SHADOW logs would-fire; `--live` execs.
- **FM-D empty-payload guard** in handoff-fire.sh (20ed5fa) — `[ -s ]` rejects a task-less fire.

DEFERRED → follow-ons (net-positive, but beyond the DoD's "ctx>55 AND idle → fires safely" core;
each is safe to add later without reworking the above):
- **F1 two-tier bias** (≥80% hard-zone: relax S1-untracked/S4, keep S3+S5 absolute, ALARM instead of
  silent abstain). The riskiest part (fires despite a soft HOLD) — wants its own soak. `CC_WR_HARD_T`
  reserved. Until then the gate is monotone-HOLD (safer, occasionally over-holds at high fill).
- **F2 handoff-fire Stage-3 idempotency latch** (mkdir-lock keyed by pane SID, watcher-cleared) —
  defense-in-depth vs a hook+model double-fire; low-probability under shadow-default + the /exit-interrupt
  window, and it touches the large critical actuator, so deferred.
- **F3 Stage-0 auto-arm-at-spawn** — arming stays opt-in (`arm`); auto-arming monitoring desks at spawn
  needs desk-role detection in the spawner (an arming-policy layer, separable from the fire mechanism).
- **Campaign** C-DSH-1 (unifying attestation primitive) + C-DSH-2 (/exit conformance test) — in the ledger.

GO-LIVE (operator's call, offered not auto-fired): review the shadow-fire IDL records
(`grep stage2-shadow ~/.claude/autonomy/idl.jsonl`), then `waiting-recycle.sh arm --brief <file> --live`
on a chosen desk to enable the exec. Global kill: `waiting-recycle.sh kill`.

## Implementation vehicle
Core is ~2 tightly-coupled safety-critical files on LIVE machinery (`waiting-recycle.sh` +
`handoff-fire.sh`) + tests + arming wiring. Ships DAMPED (shadow default) so a gate bug cannot strand the
fleet before the operator lights it. Build in THIS worktree (`feat/desk-self-handoff-trigger`), tests-
first, land via project-local `/ship` (standing-land authorized). Escalation surfaces are contained by
the shadow default + opt-in arm + kill-switch → no blocking operator decision required to build; the
operator's only call is WHEN to flip a desk to `--live` (offered, not auto-fired).
