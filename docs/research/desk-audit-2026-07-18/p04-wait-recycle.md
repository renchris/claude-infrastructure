# P4 — Wait / Recycle Discipline (the self-renewal spine)

Beat owner question: WHEN the desk renews itself (recycle) and whether the legal-wait
discipline is safe. Verdict up front: **the mechanisms are built and unit-GREEN, but the
CONSUMER/WATCHDOG half is dormant, and the composition gate is RED at runtime and unwatched.**
Producers are live (cc-wait symlinked; waiting-recycle hook registered); the things that would
CATCH a bad wait or a rotted desk (contract sweep, exit-deadline tightening, never-stuck gate on
the sweep cadence) are not wired. Empirical (ran) unless marked (inferred).

Coverage: read/ran 9 of 11 in-scope source files fully; 3 companion `.bats` verified by RUNNING
their `--selftest` (RED-provable) rather than line-reading; 2 memory notes taken from the brief's
own summary. Grepped outward into settings.json, lead-supervisor.sh, handoff-fire.sh, launchctl,
and live state/contract/telemetry dirs.

---

## (1) Inventory — one row per in-scope asset

| Asset | Role in desk loop | Wiring | Depends on | Verified by | Goal | Gap |
|---|---|---|---|---|---|---|
| `hooks/waiting-recycle.sh` | Advises a WAITING monitoring desk to self-recycle at a moderate quiet boundary | **hook-enforced** — PostToolUse:Bash registered `~/.claude/settings.json:531`; deployed as COPY (byte-identical to repo, no drift). **Dormant: no desk armed** | telemetry writer; handoff-fire `--recycle`; arm sentinel (cwd) | `tests/waiting-recycle.bats` **28/28 GREEN** (read+ran) | c, a | G-P4-4, G-P4-5, G-P4-7 |
| `bin/cc-wait` | Contracted wait primitive — writes disk contract BEFORE blocking (owned wait) | **manual/prompt-only** producer; **symlinked** `~/.claude/bin/cc-wait` (active) | `cc-await-ping` (symlinked); `CONTRACTS_DIR` | `cc-wait selftest` **8/8 GREEN** (ran) | b | G-P4-2 (no sweeper) |
| `scripts/wait-contract-lint.sh` `--sweep` | L2-c watchdog: pages a dead-waiter OPEN contract INDEPENDENT of waiter liveness | **DEAD in runtime** — not in lead-supervisor, no launchd, no scheduler | contracts dir; `cc-notify` (page) | `--selftest` **13/13 GREEN** (ran) | b, d | **G-P4-2 (top)** |
| `scripts/exit-deadline.sh` (F4) | Event-adaptive deadline: tightens 3600→900 during exit sequences | **INERT** — nothing touches the flag or calls `resolve`/`active` in runtime | `CC_EXIT_SEQUENCE` / `exit-sequence.flag` toucher | `--selftest` **7/7 GREEN** (ran) | c | G-P4-3 |
| `scripts/wait-safety-gate.sh` | L0–L4 build-readiness bar for never-wait-on-the-dead | **manual** audit; **RED now (12 met·1 failed)** | premortem-gate (L0) | ran: RED via L0 | verify b/d | G-P4-1 |
| `scripts/never-stuck-gate.sh` (B1-c) | Audits the 4-state invariant composition (progress\|owned-wait\|gate\|terminated) | **manual** audit; **NOT scheduled** onto any sweep (its own closing line asks for it); **RED now (19 met·2 failed)** | 7 component gates; state artifacts | ran: RED; `--selftest` **4/4 GREEN** (mechanics sound) | verify a/b/c/d | **G-P4-1** |
| `handoff-fire.sh --recycle` | The recycle ACTUATOR: pane EXIT + RELAUNCH with the /handoff payload | **prompt-driven** (model runs /handoff) | /handoff capture; iTerm2 it2 API | E2E 3× on 2.1.183 (doc-attested, `hooks/handoff-fire.sh:255,276`) | c | G-P4-4/5 |
| `scripts/premortem-gate.sh` | Cross-beat (comms/reaper) runtime bar; **root of the RED cascade** | manual; **RED at S-1** (reaper horizon < sweep×10) | reaper-horizon-lint | ran: 7 met·1 failed | — | cross-beat |
| `docs/NEVER-WAIT-ACTIVATION.md` | C10 activation runbook for L1–L4 | doc; **stale** ("fully GREEN 13·0"; reality 12·1) | — | read | — | G-P4-1 note |

---

## (2) Mechanism — end-to-end, file:line

### A. The recycle spine (goal c)
1. A desk opts in: `waiting-recycle.sh arm` writes `arm-<hash(cfg|cwd)>` (`hooks/waiting-recycle.sh:83-87`). **Keyed by cwd so it survives a recycle** — a monitoring desk stays one across the hop (:74).
2. On every `PostToolUse:Bash` (a polling desk's heartbeat — chosen because a watch-driven desk never cleanly Stops, so `boundary-handoff.sh`'s Stop-event advisory never lands; :11-20), the hook evaluates a 6-clause FIRE predicate, biased FALSE-NEGATIVE (:27-41):
   - ARMED (:132) · not GLOBAL-killed (:126) · not in cwd COOLDOWN (:141-144) · under per-session CAP (:148-150).
   - **TRIGGER (:185-186)** = fresh telemetry `used_pct ≥ 55` (`/tmp/cc-telemetry/$SID.json`, age ≤180s, :152-164) **OR** a behavioral ROT tell — a backtracking-safe regex over the LAST assistant text block detecting the desk *re-deriving already-known orchestration state* (:182-183). The rot tell fires **even below threshold**.
   - **SAFE (:188-196)** = clean git tree (uncommitted ⇒ HOLD, :190-191) AND no open decision/blocker in the last message (reuses anti-deference's GENUINE carve-out, :195-196).
3. FIRE (:198-213): stamp cwd cooldown (loop-breaker) + bump session cap, log one IDL line, and emit `{decision:"block", additionalContext:<advisory>}`. The advisory tells the model to run **/handoff** → `handoff-fire.sh --recycle` so the **successor pane IS the continuation** and the bloated context is discarded (:208). The hook NEVER recycles directly — only the model can capture live state (:19-20). Exit 0 ALWAYS (PostToolUse can't cost a session, :46).
4. Loop-breaker: the cwd-keyed cooldown means a fresh recycled desk (same cwd) sees the predecessor's stamp and stays quiet → recycle→fresh→recycle cannot spin (:33-35). Defense-in-depth guard skips the recycle machinery's own Bash calls (`*/handoff*|*handoff-fire*|*waiting-recycle*`, :136-138).

### B. The legal-wait discipline (goal b) — BIND applied to waiting
- `cc-wait` writes a durable disk contract `{waiter, waiter_pid, waiter_start, waitee, expected_signal, heartbeat, deadline, on_timeout_action, status:OPEN}` **and fsyncs it BEFORE blocking** (`bin/cc-wait:111-125`) — contract-before-wait, the L2 analog of capture-before-notify. A wait is thus OWNED from the first instant, never a thing living only in a context (the 77-min-strand fix).
- Two fail-closed invariants at the PRODUCER (:87-99): (b) no `--deadline` or no `--on-timeout` ⇒ REFUSED exit 2; (d) `--on-timeout` is a STRUCTURED ALLOWLIST enum `{reobserve,page,escalate}` — a disposition (reap/kill) simply cannot be expressed (:48-49). On deadline: exit 5, a structured PAGE / re-observe, **never a reap** (:144-154; S-3b "a busy waitee that ignores its page is still alive").
- `wait-contract-lint.sh` is the AUDITOR: `--selftest` RED-proves all four criteria; `--sweep` is the runtime WATCHDOG that scans contracts on DISK (independent of any waiter's liveness), uses `{pid,start-time}` identity to catch recycled-pid false-liveness (`:121-128`), and PAGES a dead-waiter / past-deadline divergence **page-once** with escalation at 3 repeats (`:147-198`).

### C. Never-stuck composition + deadlines (goals a–d)
- `never-stuck-gate.sh` audits the standing claim "every live session is progressing | at an owned wait | at a designed gate | cleanly terminated — never silently idle" (:10-13) across 4 legs: LEG1 runs the 7 component gates live (:47-59), LEG2 maps each state (a–d) to guardian artifacts (:69-80), LEG3 maps 10 failure classes NS-1..NS-10 to covers (:82-105), LEG4 is read-only ACTIVE/C10-PENDING inventory (never a failure, :107-126). The **21 met · 0 failed** of commit c88ba53 = 7 (LEG1) + 4 (LEG2) + 10 (LEG3).
- `exit-deadline.sh` (F4) centralizes "are we in an exit sequence?" so L2 wait + L4 sweep tighten on the same signal (`scripts/exit-deadline.sh:12-14,40-59`). Fix for the "learned of a ship 50 min late because the re-observe was hourly-tuned" incident (:8-13).

---

## (3) Gaps & fragilities

| ID | file:line | FM | Sev | Failure scenario | Fix sketch |
|---|---|---|---|---|---|
| **G-P4-2** | `wait-contract-lint.sh:147` (sweep) unscheduled; `lead-supervisor.sh` has no call | FM2 | **P1 (P0-adjacent)** | The flagship L2-c watchdog is **built + selftest-GREEN but NOT running**. cc-wait writes contracts (62 on disk) but nothing enforces them. A waiter that dies mid-wait ⇒ OPEN+orphaned contract **nobody pages** — the *exact* 77-min-strand this layer was built to close. Empirically 0 OPEN-dead now, but that is the CONSUMER self-closing (SATISFIED/SUPERSEDED are written by `cc-wait`/consumer at block-end, `bin/cc-wait:139,147`; the sweep never closes) — the safety net itself has never fired in prod. Adoption-gated (few waits use cc-wait yet), which is the only reason this is P1 not P0. | Schedule `wait-contract-lint.sh --sweep ~/.claude/wait-contracts` on the lead-supervisor cadence (launchd or supervisor loop). |
| **G-P4-1** | `never-stuck-gate.sh:186` (unscheduled) + RED via `wait-safety-gate.sh:57` ← `premortem-gate.sh` S-1 | FM1/FM2 | **P1** | The never-stuck invariant is **RED at runtime (19 met·2 failed)** — a session CAN currently go silently idle through the failing leg — AND the gate is **not wired to any sweep**, so the regression from 21·0→19·2 happened UNWATCHED. The composition "nobody can watch fire is itself a check that cannot observe what it guards." Root (S-1 reaper-horizon) is cross-beat; the *unwatched* half is this beat. | Wire `never-stuck-gate.sh` onto the supervisor sweep + page on non-zero exit; fix premortem S-1 (cross-beat, T-P4-5). |
| **G-P4-3** | `exit-deadline.sh:40-59`; only `comms-safety-gate.sh` references the flag | FM1 | **P1** | F4 is **inert** — no live call site touches `exit-sequence.flag` or calls `resolve`/`active`. The "50-min-late ship" fix is dormant: every deadline resolves to the 3600 default and never tightens to 900 in the exit window (the costliest silence). Even if G-P4-2's sweep were wired, it would use the loose constant. | Add an exit-flag toucher to the /handoff-or-announce exit path; make cc-wait + the sweep call `exit-deadline resolve` at contract-write / sweep time. |
| **G-P4-4** | `hooks/waiting-recycle.sh:208` advisory text | **FM1** | **P1** | The recycle advisory enumerates OPERATIONAL state to carry ("fired sessions, pending pings, wave/merge state, decisions") but **never names mission/goal/DoD/finish-line**. A recycle can carry "what I'm watching" while thinning "why / the 100.00 target" → the classic FM1 (desk loses purpose, believes 'done'). Mitigated by /handoff item-3 (duplicate hard constraints, `commands/handoff.md:68`) + plan pointer, but the advisory itself omits the finish-line, and **no desk is armed** so the spine is currently dormant. | Extend the advisory (and the /handoff capture template) with an explicit "Mission/DoD (frozen) + finish-line %" line; assert it in the bats. |
| G-P4-5 | `waiting-recycle.sh:77` (arm keyed by cwd) vs `handoff-fire.sh --recycle` relaunch cwd | FM1 | P2 | Arm is per-cwd. If `--recycle` relaunches the successor in a DIFFERENT worktree/cwd, the successor is UN-armed → the monitoring desk silently stops self-recycling after one hop (spine breaks at hop 2). Not fully traced (uncertainty). | Verify recycle relaunches in-place; if not, re-arm in the recycle payload or key arm by session-lineage. |
| G-P4-6 | `~/.claude/wait-contracts/` (62 files, 9 TIMED_OUT) | 24x7 | P2 | Contracts accumulate un-pruned; 9 TIMED_OUT linger with no re-observation follow-through (sweep unscheduled). Disk clutter + a lingering TIMED_OUT is a silent divergence. | Add a prune of terminal-status contracts older than N days to the (to-be-scheduled) sweep. |
| G-P4-7 | `waiting-recycle.sh:152-164` telemetry dependency | FM2 | P2 | The threshold branch needs the statusline telemetry writer live (fresh now: this session at age 1-24s). If that writer dies, only the LAGGING rot-tell can fire (rot has already happened by the time the model re-derives state) — recycle becomes purely reactive with no alarm on the stale-telemetry condition. | Emit a distinct alarm when an armed desk sees `fresh=0` for N consecutive polls. |

---

## (4) Task candidates

| ID | Action | Acceptance criterion | Depends-on |
|---|---|---|---|
| T-P4-1 | Schedule `wait-contract-lint --sweep ~/.claude/wait-contracts` on the lead-supervisor cadence | A fabricated OPEN contract with a dead `waiter_pid` is paged exactly once within one sweep; `wait-safety-gate` L2-c green *deployed* | lead-supervisor beat |
| T-P4-2 | Wire `never-stuck-gate.sh` onto the supervisor sweep + page on RED | Flipping any component gate RED yields a supervisor page within one sweep; gate exit-code surfaced | T-P4-5 for green |
| T-P4-3 | Add exit-sequence flag toucher to the exit path; make cc-wait/sweep call `exit-deadline resolve` | During an exit sequence a new contract's deadline resolves to 900, not 3600 | cc-wait, /handoff |
| T-P4-4 | Carry mission/goal/DoD/finish-line in the recycle advisory + /handoff capture | `additionalContext` (and payload template) name the frozen DoD + finish-line %; bats asserts it | none |
| T-P4-5 | Fix premortem-gate **S-1** (reaper horizon ≥ sweep×10) — CROSS-BEAT | `premortem-gate.sh` → 8 met·0 failed; cascades wait-safety + never-stuck to GREEN | reaper beat |
| T-P4-6 | Arm the live monitoring desk(s); add terminal-contract pruning | `arm-<cwd>` present for the desk; contracts with terminal status older than N days pruned | T-P4-1 |

---

## (5) Cross-beat dependencies
- **Reaper beat** owns `premortem-gate` S-1 (reaper-horizon) — the current root of my RED cascade; my gates cannot green until it's fixed (T-P4-5).
- **Supervisor/comms beat** must HOST the wait-contract sweep and the never-stuck gate on its sweep loop (T-P4-1/2). `com.claude.lead-supervisor` launchd is loaded (pid 17867) but sweeps neither.
- **Comms/spawn-death beat** owns L1 deathwatch (`cc-deathwatch-kqueue`) + L4 reconciler — the *declared covers* for L2-c's blind spot (dead-waiter → L4 divergence). Both are **also unwired** (no launchd plists installed), so L2's compositional cover is theoretical until activation.
- **Handoff beat** owns `handoff-fire --recycle`, the actuator my recycle advisory calls (G-P4-5 relaunch-cwd question lands there).

## (6) Adversarial self-pass (hostile-reviewer objections, then covered)
1. *"The sweep might run under a different name / indirect call."* — Grepped `lead-supervisor.sh` for `wait-contract|--sweep|wait-contracts` (none); grepped all scripts/hooks/commands for `wait-contract-lint` (only self + the unscheduled never-stuck-gate); checked `~/Library/LaunchAgents` (no wait/reconcile/deathwatch plists); `launchctl list` matched only lead-supervisor + lr-reset-poller. Covered.
2. *"0 OPEN-dead ⇒ maybe the sweep works."* — No: SATISFIED/TIMED_OUT are written by `cc-wait` `close_contract` at block-end (`bin/cc-wait:139,147,157-163`); the sweep only PAGES/marks, never closes (`wait-contract-lint.sh:147-198`). SUPERSEDED is a consumer-written status. So closure is producer-side; the 0-open-dead is the consumer self-closing, not the watchdog. Gap stands.
3. *"Is waiting-recycle really the recycle path?"* — Yes: advisory names `/handoff` + `handoff-fire.sh --recycle` (bats "advisory" test asserts it, `tests/waiting-recycle.bats:240-248`); handoff-fire documents `--recycle` = EXIT+RELAUNCH, E2E 3× (`hooks/handoff-fire.sh:255,276`).
4. *"Is 21·0→19·2 a real regression or was 21·0 aspirational?"* — c88ba53's message claims 21·0. premortem S-1 predates the recent S-3b add (ce3c9e8), so most likely a config/timing DRIFT flipped S-1 after the green measurement. Either way the operative fact holds: the gate is RED and unwatched. Named as uncertainty.
5. *"Did you prove a recycle EVER fired end-to-end?"* — No. No desk armed now; I did not grep `~/.claude/autonomy/idl.jsonl` for historical `waiting-recycle` `fired` records. The spine is present + unit-GREEN but its production firing is unverified. Named in Uncertainties.

## (7) Uncertainties
- **Has any real recycle fired in prod?** Unverified (IDL not grepped; no desk armed at read time). Cheap follow-up: `grep waiting-recycle ~/.claude/autonomy/idl.jsonl`.
- **Recycle relaunch cwd** (G-P4-5): did not trace `handoff-fire --recycle` to confirm the successor lands in the same worktree (determines whether the cwd-keyed arm rides along).
- **premortem S-1 slowness**: the initial 7-gate loop timed out at 2 min; premortem alone finished <10s. One component gate in the composition is slow enough to matter for a sweep-cadence host — not isolated which; relevant to T-P4-2 (a slow gate on the sweep loop is its own hazard).
- **2 memory notes** (desk-wave-monitor-lead-idle, desk-monitor-fixed-head-ref) taken from the brief's summary, not re-read; both concern monitor stall-detection semantics adjacent to (not inside) this beat.
