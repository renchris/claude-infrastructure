# Desk self-handoff — Fable design panel findings + reconciliation

Panel: 2 Fable-5 baseline-grounded design panelists (H-DSH-1 actuation, H-DSH-2 safe-gate),
`/frontier-run`, 2026-07-19. Reconciled against `independent-ground-truth.md` (lead/Opus prior).
Tags: CONFIRMED = panel re-derived the lead prior (confidence↑) · NEW = frontier delta the lead was
blind to · REFUTED = killed.

---

## H-DSH-2 — SAFE-FIRE GATE  (panelist ab498…, ~100K tok, 16 tool calls) — verdict landed

### Identity model (all confirmed by panel code-read)
desk = {SID (dies at recycle) · UUID (iTerm pane uuid — SURVIVES in-place `--recycle`) · ROLE
(`~/.claude/cc-roles/<name>` → UUID, repointable) · CWD (stable)}. `--recycle` is in-place, same
pane, same dir (`handoff-fire.sh:648-664`) → NO concurrent successor pane, only a no-claude gap while
the `__recycle` watcher re-types the launch into the same tty.

### The SAFE-FIRE predicate (S1-S2 exist; S3-S8 are additions)
TRIGGER (one fix): fresh(`/tmp/cc-telemetry/$SID.json`,≤180s) AND used_pct≥55 — OR — rot-tell AND
fresh AND **used_pct ≥ FLOOR(~25)**. [NEW] The floor is DERIVABLE not tunable: rot physically needs
accumulated context; a rot-tell at single-digit fill is by construction re-orientation narration, and
the shipped regex matches HEALTHY watch narration (see probe P1 — CONFIRMED live bug).

| # | Clause | Disk signal | Detects | Tag |
|---|---|---|---|---|
| S1 | Clean tree **+ no git sequencer state** | porcelain empty (exists :190) AND no `MERGE_HEAD`/`rebase-merge`/`rebase-apply`/`CHERRY_PICK_HEAD` in `$CWD/.git` | mid-active-work incl. "mid-merge between clean states" | **NEW** (concrete detector for the audit gap) |
| S2 | No open decision | GENUINE regex, last assistant msg (exists :195) | blocked-on-operator | CONFIRMED |
| S3 | No live INBOUND wait | OPEN `wait-contracts/*.json` with `waitee ∈ {UUID,SID,role-names,registered-name}` AND `deadline>now` AND waiter-alive (`kill -0 waiter_pid` + `waiter_start` match) | a peer contract-blocked on THIS desk | CONFIRMED + **NEW** (liveness filter kills OPEN-zombie-holds-forever) |
| S4 | Quiet inbox | `~/.claude/mailbox/<UUID>.md` + `<role-UUID>.md` mtime older than QUIET_S(~120-300s); cc-notify always mailbox-writes before injecting (`cc-notify:119-124`) | a peer just reached for the desk | **NEW + LOAD-BEARING** (cc-dispatch workers `cc-notify` the desk role but do NOT write contracts — `cc-dispatch:206` — so S3 alone UNDER-detects) |
| S5 | No live context-bound CHILDREN | `~/.claude*/teams/session-${SID:0:8}*/config.json` `members[]` beyond lead, member live (pane/pid) | **HARD HOLD** — teammate/TaskOutput results route to the dying SID, unrecoverable by any successor | **NEW + CRITICAL** |
| S6 | Fire-settle | no `{action:"fired"}` by this desk in idl.jsonl within SETTLE_S(~300s) | just-fired session not yet engagement-verified | NEW |
| S7 | Fresh self-telemetry on BOTH paths | age≤180 (today only threshold path requires it) | flying blind | CONFIRMED (=lead S7) |
| S8 | arm/kill/cooldown/cap | :126-150 | — | exists |

Three states: **idle-babysitting**=all pass (roster reconstructible from telemetry+registry+backlog+
IDL+dod-persist, all durable) · **mid-active-work**=S1/S2 fail · **active-coordination/blocked-on-me**=
S3/S4/S5/S6 fail.

### Active-coordination decidability
Partially decidable via a THREE-SOURCE UNION, each with a durable producer: contracts (S3) · mailbox
(S4) · team-config (S5). Undecidable residue: (a) peer blocked with no contract + no recent ping;
(b) desk's own planned-but-undone multi-step sequence (clean tree between steps); (c) in-flight
background Task subagents (**no durable spawn ledger exists** — negative space). FN-safe approximations:
(a)=S4's generous window; (b)/(c)=the model-confirm layer (advisory `{decision:block}`+additionalContext
— the hook does NOT self-actuate). Inherent tension [NEW]: the model-confirm layer degrades with exactly
the rot that triggers it → the clean escape is an **affirmative attestation** (campaign #1).

### No-double-fire
- **Within-session TOCTOU** [NEW]: cooldown check(:141) vs stamp(:200) + cap RMW(:148 vs :201) — two
  parallel PostToolUse Bash calls in one turn can both fire. Bounded (same model context → one /handoff)
  but fix = atomic `mkdir`/`set -C` acquire before emit.
- **Across the recycle boundary**: cwd is the correct dedup key (arm+cooldown survive :74-78; cap
  SID-resets :79; successor telemetry SID-keyed :154 → **threshold path CANNOT re-fire**, REFUTES lead's
  "successor reads predecessor telemetry" worry). ONLY cross-gen re-fire = rot-tell matching successor
  re-orientation narration after cooldown expiry; **MAX=3 is per-session → toothless across generations
  → unbounded ~600s recycle CHURN gated only by model compliance** [NEW]. Closed by the used_pct FLOOR
  (fuel) + a cwd-keyed generation counter (pacing, campaign #2).
- **Landmine** [NEW]: `arm` clears the cooldown (:86) — a successor that re-arms defeats the loop-breaker.
  Runbook MUST say "do NOT re-arm" (arm survives in-place recycle).

### Bias verdict — TWO-TIER (the sharpest NEW)
HOLD-bias (FALSE-NEGATIVE) is correct ONLY in the soft zone. The calculus INVERTS above ~80%: an
imperfect recycle WITH a handoff brief strictly dominates certain 90% auto-compaction WITHOUT one (both
strand, only one writes a brief; `/compact` also kills teammates). So: **soft zone (trigger..80)** = full
S1-S8 · **hard zone (≥80)** = relax S1-untracked/S4/S6, keep **S3+S5 ABSOLUTE**, emit a distinct ALARM
advisory ("cannot recycle safely: <failing clause>, context critical — resolve NOW") instead of silent
abstain. S5 NEVER relaxes (recycle and compaction both kill teammates → drain-then-recycle + page).

### Probes (falsify-before-file) — RAN
- **P1 CONFIRMED (live bug):** shipped ROT_TELLS regex trips on "Re-checking which sessions are still
  running." / "Let me re-scan which teammates have reported back so far." / "Checking again which tasks
  completed." → healthy watch narration fires the rot trigger. Floor fix validated.
- **P4 CONFIRMED:** 21/29 (72%) telemetry rows stale >1h now (predicted ≥30%). cwd-scan reads ghosts;
  SID-key + AGE_MAX mandatory.
- P2 (mailbox>contract), P3 (TOCTOU reproduce), P5 (identity survives recycle) — deferred to
  implementation-time tests (P5 partially pre-confirmed by lead PROBE 1: ITERM_SESSION_ID survives).

### REFUTED
Two concurrent panes during --recycle (in-place) · successor reads predecessor hot telemetry (SID-keyed)
· "no durable ping inbox" (mailbox always pre-written) · "OPEN zombies litter the dir" (0/62 OPEN;
producer self-closes — zombie risk only on mid-block waiter death → S3 liveness filter) · "parent→child
edge missing everywhere" (exists in `teams/session-<lead-sid>`).

### NEGATIVE SPACE
- **No durable spawn ledger for background Task subagents** (non-team) — a desk with an in-flight
  researcher is invisible to every disk signal; result routes to dying SID. *(Directly live for the lead
  NOW: the H-DSH-1 panelist is such a subagent — a monitoring desk must HOLD while one runs.)*
- Advisory-compliance quality vs used_pct unmeasured.
- Composer-content destruction at relaunch (operator-typed non-mailboxed text).

### CAMPAIGN CANDIDATES (routed to ledger)
1. **Affirmative watch-state attestation** — desk writes `WATCHING|COORDINATING|FIRING` + ts + DoD to a
   cwd-keyed file each poll (write-before-act). Dissolves 4 items: hidden-obligation gap (gate reads the
   attestation), G-P4-4 mission-carry (DoD rides the file), S6 fire-settle (state=FIRING explicit),
   cc-board STALL?-vs-healthy ambiguity. GENERATOR-class. **Also plausibly BECOMES the H-DSH-1 brief
   sentinel** — one primitive spanning both holes.
2. **Lineage identity** — cwd-keyed generation counter bumped at fire. Dissolves cap-reset hole (MAX
   per-episode), bounds cross-gen churn independent of regex quality, answers G-P4-5, board observability.

---

## H-DSH-1 — ACTUATION  (panelist a0d35… — STILL RUNNING)
_(append verdict on return; then synthesize the unified mechanism. Lead prior: advisory-first +
deterministic-fire fallback, armed-sentinel per session-continue.sh; env-inheritance + in-place both
CONFIRMED by lead probes. The attestation file (campaign #1) is the likely convergence point for the
brief-carrying sentinel.)_
