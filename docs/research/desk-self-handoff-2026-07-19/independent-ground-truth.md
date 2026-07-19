# Desk self-handoff trigger — LEAD independent ground truth (pre-panel baseline)

Written BEFORE the Fable panel returns so the NEW-vs-CONFIRMED reconciliation is honest and
survives a compaction. This is the lead's (Opus) own disk-traced view; the panel (H-DSH-1
actuation, H-DSH-2 gate) is being reconciled AGAINST it.

## The reframing (disk truth)
The task ("build a hook that deterministically self-handoffs at ctx>55 + idle") is NOT greenfield.
`hooks/waiting-recycle.sh` already does deterministic DETECTION + advisory DELIVERY. It **fired
0/2419** in prod (1977 not-armed; the rest dirty-tree/below-threshold). It DELIBERATELY stops at
advisory ("only the model can capture live state"). The real deliverable = evolve **advisory →
deterministic ACTUATION**, hardening the safe-fire gate. Everything below is grounded in files read
this session.

## Signal availability (sub-problem a) — SOLVED, in prod
- **context-%**: `/tmp/cc-telemetry/<sid>.json` `.used_pct` + `.ts` (freshness, age-check ≤180s) +
  `.cwd` + `.pid` + `.config_dir`, written by `statusline.sh` each render. Consumed by `bin/cc-context`,
  `bin/cc-board`. RELIABLE, live (this desk renders fresh).
- **Hook→live-model channels (injection-channel law, synthesis.md)**: ONLY
  `UserPromptSubmit.additionalContext`, `PostToolUse.additionalContext`, `decision:block` reason.
  Stop `additionalContext` INERT. A disk record with no consumer never reaches the desk.

## H-DSH-1 actuation — lead's independent verdict
- **Mechanical feasibility: LIKELY YES.** `handoff-fire.sh --recycle` (traced :388-439, :648-673):
  types `/exit` via the `it2` API into the pane and arms a **detached** `__recycle` watcher that
  polls the tty for `node|claude` gone, then types the relaunch command into the bare shell. Both the
  model-invoked and a hook-invoked path run **mid-turn** and type `/exit` the same way → the queue-timing
  the catnav incident warns about (:648-658) is about a trailing PLAIN-TEXT payload steering inline;
  `/exit` alone is a built-in that holds to turn-end. A PostToolUse hook exec should be equivalent.
  RISKS to verify: (1) `$ITERM_SESSION_ID`/`$CLAUDE_CONFIG_DIR` inheritance into the hook subprocess;
  (2) hook blocking on the script (it arms a detached watcher → returns fast); (3) double-fire.
- **The REAL crux = THE BRIEF.** Whoever fires must supply the successor's prompt. The design's
  "only the model can capture live state" rationale is about THIS. Resolution: for a MONITORING desk
  the watch-state is **disk-reconstructible** (cc-board proves it — this desk shows as a live row with
  fleet roster). So a DETERMINISTIC brief = frozen DoD (`dod-persist.sh get`) + a disk-reconstruction
  preamble ("run cc-board, read the registry + wait-contracts, resume monitoring") + OPTIONAL
  model-refreshed sentinel for non-reconstructible operational state (pending decisions, wave specifics).
- **Recommended architecture (lead's prior): (iii) advisory-first + deterministic-fire fallback.**
  Mirror `session-continue.sh` exactly: armed sentinel + dumb actuator + **sid-bind** (successor can't
  inherit the predecessor's fire-intent) + **cap** + **kill-switch**. Advisory (already built) gives the
  healthy model first chance to author a real handoff; on K ignored advisories (rot proven — the cap is
  already counting) the hook FIRES deterministically with the reconstructable brief. Preserves handoff
  quality in the common case AND guarantees determinism in the failure case. Never task-less because
  DoD + disk-reconstruction always yield a working monitoring brief.

## H-DSH-2 gate — lead's independent verdict
- **cc-wait semantics (traced bin/cc-wait):** contract = `{waiter, waiter_pid, waitee, expected_signal,
  deadline, on_timeout_action∈{reobserve,page,escalate}, status:OPEN|SATISFIED|TIMED_OUT}`. The DESK is
  normally the **waiter** (babysitting: `waitee="trackab-leads"`, note="desk monitors Track-A+B…").
  KEY: such a wait is **durable on disk → survives a recycle** (successor resumes it). So "the desk is
  waiting" is SAFE to recycle, NOT unsafe.
- **The UNSAFE coordination case = a sub-session blocked on THIS desk**: an OPEN contract whose
  `waitee` == this desk's id/role, OR an unprocessed INBOUND ping/mailbox-line addressed to the desk
  (`cc-await-ping`/`cc-notify` back-channel). That is the "active-coordination" HOLD signal the current
  clean-tree+no-decision proxy misses.
- **SAFE-FIRE predicate (lead's prior):** existing (armed · not-killed · not-cooldown · under-cap ·
  TRIGGER used_pct≥55|rot · clean-tree · no-open-decision) PLUS: (a) fresh telemetry (age-checked, else
  HOLD); (b) NO unprocessed inbound ping/mailbox-line for this desk; (c) NO OPEN wait-contract with
  waitee==this-desk. The desk's OWN waiter-contracts do NOT block (durable). Bias FALSE-NEGATIVE: any
  ambiguity/staleness → HOLD.
- **No-double-fire:** session-keyed fire latch + cwd-keyed cooldown (existing loop-breaker) + sid-bind.
  Race window to check: the two-pane boundary (old exits, successor launches) — the cwd cooldown stamp
  set at fire-time covers the successor; the recycle-machinery Bash guard covers the fire's own calls.

## Falsifiable predictions the lead will probe after the panel
1. A PostToolUse hook subprocess inherits `$ITERM_SESSION_ID` (env check) — if NOT, direct hook-exec of
   `--recycle` fails and the sentinel must carry the sid.
2. `grep waiting-recycle ~/.claude/autonomy/idl.jsonl | grep fired` stays empty until a real arm+clean+
   ≥55 coincidence — i.e., the fire path has genuinely never exercised (so no regression risk to "fix").
3. 0 OPEN wait-contracts with waitee==<this-desk-id> right now (no sub-session blocked on this desk).

## Probe results (run pre-panel, this session)
- **#1 env inheritance — CONFIRMED.** A CC-spawned subprocess sees `ITERM_SESSION_ID=w2t1p0:65CB…`,
  `CLAUDE_CONFIG_DIR=/Users/chrisren/.claude-tertiary`, `CLAUDE_CODE_SESSION_ID=a2d4377f…`. So a hook
  CAN exec `--recycle` (sid via `${SESSION_ID:-${ITSID##*:}}`) AND has the sid for sid-bind. Feasible.
- **#3 nothing blocked on this desk — CONFIRMED.** 0 OPEN wait-contracts total right now (quiet moment;
  the detector still must handle the non-zero case).
- **NEW (resolves audit G-P4-5): recycle is IN-PLACE.** `handoff-fire.sh:668 IN_PLACE=1 "relaunch stays
  in this pane's dir by definition"` → the cwd-keyed arm SURVIVES the recycle hop (audit left this an
  open uncertainty). Confidence↑ on the armed-sentinel-keyed-by-cwd design.
- **Surprise: THIS desk is ALREADY ARMED.** `arm-e181330604ffe33f` = hash(.claude-tertiary | claude-
  infrastructure) exists (Jul 17). So waiting-recycle IS evaluating this very session — a live test bed.
  (Below 55% now, and my tracked writes are in the WORKTREE not the main-checkout cwd, so the desk's
  clean-tree check on the main checkout still passes — I won't trip a false advisory at this ctx.)

## Reconciliation tags to apply on panel return
CONFIRMED = panel independently re-derived one of the above (confidence↑). NEW = something above is
wrong or incomplete (the frontier delta — the reason for the 2× spend). REFUTED = a hole/assumption
the panel killed. A missed probe prediction outranks any code finding (system-model error).
