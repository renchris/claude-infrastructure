# SESSION_AUTONOMY — Research Convergence & Build Blueprint

**Status:** convergence of the Wave-2 design research (14 axes: 12 productive Opus workers a–m +
2 Fable adversarial j1/j2, all read-only), grounded in `docs/research/W0-W3_INTERVENTION_AUDIT.md`
(root causes R1–R6, detectors D1–D7). This doc is the blueprint the Agent-Teams build consumes and
the surface for the operator decisions in §5. Every primitive is cited to its axis + R#/D#.

---

## 0. Verdict (answer-first)

The autonomy layer is **buildable, and net-negative on quota+context by construction** — its
read/watch/poll machinery is entirely out-of-session (0 model quota), and its only quota-touching act
(injecting a turn) 1:1-replaces a human relay while preventing far larger context-rebuild and
re-run-wave wastes (axis m). But the two adversarial panelists (j1, j2) converge on one correction
that reshapes the build: **every naive primitive fails _silent/open_, and an autonomous actor keyed
off the audit's own catalog of mendacious signals (D1–D7) can _cause_ a W0-class incident**. So the
design law is **fail-loud, effect-verified, advisory-not-blocking, park-and-page by default** — and
the build order is **safe-docs-first → prove on W4 → runtime actors only to the extent the residual
justifies.** The productive axes independently satisfy this law (k's four-zeros audit, h's
one-shot-latched abstain-on-stale hook, b's bash-can't-close-a-live-pane split, m's 3 guards).

---

## 1. The converged architecture — 7 invariants (every axis obeys these)

1. **Verify the EFFECT, never the report/keystroke/spawn/config** (audit §7, restated by a, b, d, f,
   h, k independently). Concretely: dead-pid → DEAD even if telemetry looks fresh (a/P9); pane-gone
   asserted via `it2 session list`, not "shutdown_request sent" (D5); ack = a commit-sha in the
   branch, not a delivered `SendMessage` (f); the boundary number = payload `used_percentage`, never
   the statusline display offset (h; the §3b 2.3×-lie fix, `1b8d671`).
   **→ EXTENDED 2026-07-14 (audit §3g — the law's blind spot, paid for in production): it must also be
   applied to the VERIFICATION APPARATUS ITSELF.** `cc-notify`'s submit-verifier was inert for ~24h while
   its 15/15 suite stayed green and the audit recorded it as FIXED. Three more surfaces are in scope:
   **(i) the verifier** — an always-abstaining check is indistinguishable from a passing one (both exit 0);
   only a real invocation whose OUTCOME you inspect settles it (→ detector **D9**: a verifier whose positive
   *and* negative branches never fire across N real calls is inert **by construction**; an abstain path that
   is 100% of outcomes is a BUG, never a graceful degrade). **(ii) the test fixture** — a synthetic fixture
   IS a report; it must carry the real artifact's **bytes**. **(iii) the green suite** — prove it RED against
   the real bug, else it is decoration. Full statement + the four harness laws: §3.10. **Corollary for this
   track: a detector that has never fired in production is UNPROVEN, not "quiet"** — which binds the boundary
   hook (h) and the supervisor (b) directly.
2. **Fail-loud / fail-abstain, never fail-silent-open** (j1's root pattern). Telemetry export is
   atomic (a/P1) and a stale/missing row on a *live* session is a LOUD fault, not silence (a/P3, j1
   #6); the boundary hook ABSTAINS on stale telemetry (h); the gate classifier defaults any doubt to
   STOP-ASK (c's asymmetric whitelist).
   **→ THE BLIND-CHECK LAW (audit §3i, 4 instances in one night):** *a check that cannot observe the thing
   it guards is indistinguishable from no check at all* — it exits 0, its suite is green, and the system
   looks healthy. You cannot find one by reading it (all four looked correct; three shipped with passing
   tests). **But it has an unmissable external signature: a human quietly starts doing its job by hand.**
   So the detector is nearly free — **audit what the human DOES, not what they SAY: every manual
   verification is a bug report against an automation, filed by someone who did not know they were filing
   it.** (§1's relay count *undercounted* for exactly this reason: a hand pane-capture, a fallback sweep,
   and a blob-verify never look like "an intervention".) **Corollary, and it bit the fixer:** `cc-bind` —
   built to replace the untrustworthy channel of instance #1 — **reproduced #1's pathology within hours**.
   This is what happens whenever a detector's EVIDENCE and its HYGIENE are served by the same mechanism.
   **Assume it is present in the next primitive: the boundary hook (h) and the supervisor (b) are both
   checks** — pre-mortems for each are written into §3.2 and §3.3.
3. **Advisory, never blocking; boundary-gated, never mid-slot** (BUILD_LOG W2-rule-3; audit §4). No
   blocking Stop hook (banned). The boundary hook fires only at (a)∧(b)∧(c), one-shot-latched, and
   defers to `session-continue` when loose-ends are armed (h). "red-100% = warning not death" —
   fixtures-b2 ran >1h past it and completed.
4. **Plan-time schedule primary; runtime telemetry is advisory refinement** (j2's generator insight,
   realized by d+g). Lead burn is *predictable* (29→64→73% over a day) → succession is scheduled at
   plan time (`cc-wave-plan` placement + `context_budget` window-relative thresholds), and the
   boundary hook only *refines* the scheduled boundary — it does not carry the whole decision.
5. **The metric is paired and mechanical** (j2's Goodhart-bait fix, realized by k). Success =
   zero-unplanned-interventions **AND** zero-autonomy-caused-incidents, re-derived as k's **four
   independent zeros** (unplanned=0, signal-divergence=0, orphaned-intent=0, missed-fire=0) — never a
   bare count a silently-mis-recovering supervisor could game.

6. **🚨 THE AUTHORITY CEILING — the autonomy layer may not widen its own autonomy** (added 2026-07-14,
   audit §2b; discovered by hitting it). An agent cannot self-modify or install persistence on a **peer
   agent's** authority: the harness denied the P8 `settings.json` wiring precisely because *"the only
   authorization is a peer/orchestrator session's CONDITIONAL GO, which is not user intent."* **It was
   right.** Delegated authority is real for WORK and **void for SELF-MODIFICATION** — an agent may delegate
   work it is permitted to do; it cannot delegate consent it does not possess, and no chain of
   agent-to-agent rulings sums to a human's. This track is *the software that most needs this ceiling to
   hold*: a supervisor able to install its own hooks can widen its own powers, and a session able to edit
   `settings.json` can delete the gate that stops it. So the DoD's "zero unplanned intervention" has a
   **principled floor**: config / persistence / autonomy-machinery changes are **designed gates by
   construction** (new permanently-out-of-class ruling class **C10**, with `C6` and `C9`) — never counted as
   failures, or the metric would push the system to defeat its own rail. **Standing pattern:** the agent does
   all the work — code, tests, effect-check, rollback one-liner — and hands the human an **activation
   script** (`/tmp/p8-activate.sh`); it never performs the activation. Autonomy runs right up to the
   boundary; the boundary holds.

7. **🔑 ONE ARTIFACT, ONE ROLE — the evidence invariant** (pinned at the desk's request, 2026-07-14;
   audit §3i's corollary, sharpened). The desk's phrasing was *"evidence and hygiene served by one
   mechanism reproduce the pathology."* True, but the general form is one step up, and it predicts more:

   > **An artifact that is BOTH (a) the evidence of a failure AND (b) subject to a lifecycle serving some
   > other goal — hygiene, addressing, amendability — will have its evidence destroyed by that other goal,
   > SILENTLY, and precisely at the moment the failure occurs.** The two roles have contradictory lifecycle
   > requirements, and the destructive one always wins by default because it is the one with a *policy*.

   Every instance is this, and the conflicting pair is different each time — which is why it kept slipping
   past a reader looking for a repeat of the last bug:

   | artifact | role A — evidence | role B — the policy that destroyed it |
   |---|---|---|
   | telemetry file | proves a session STALLED | **hygiene** — bound `/tmp` growth (deleted on age) |
   | registry row | proves a pane DIED AT SPAWN | **addressing** — don't resolve a name onto a dead pane (deleted on deadness) |
   | ruling file | proves WHAT WAS AUTHORIZED | **amendability** — a ruling must be correctable (mutated after the ack) |

   **The resolution is always the same shape: split the roles, and forbid the destructive one from acting on
   the failure-state itself.** Deletion keys on **AGE** (retention), never on the failure (deadness,
   staleness, closure). A view may **HIDE**, never **DELETE**. An attestation binds by **CONTENT**, never by
   name. Concretely landed: telemetry — liveness(pid) ≠ retention(age) (`93720eb`); registry — liveness(pid)
   ≠ view(addressing filters) ≠ retention(age), *presence must never encode liveness* (`7b2f701`); ruling —
   identity(id) ≠ content(hash) (`1eebe07`).

   **Pre-ship design question (the desk's adopted review criterion — apply to EVERY primitive):**
   > *For every artifact this primitive reads or writes: **is it evidence of something?** And is any other
   > policy permitted to delete, hide, or mutate it? If so, that policy will erase the evidence exactly when
   > it matters — because "when it matters" IS the failure state the policy keys on.*
   > And its twin: ***what is this check structurally unable to see, and who would end up checking that by
   > hand?*** (audit §3i: the hand-check is the blind-check's only external signature.)

   **MECHANICAL COROLLARY — a check must log its ABSTENTIONS, not only its firings.** D9 (an inert verifier)
   is *only* detectable from the outcome DISTRIBUTION, so every check must emit `{fired | passed | abstained
   | failed}` per invocation to the IDL (axis k P1). **Alarm: `abstained == 100%` over N≥10 real invocations
   ⇒ the check is inert by construction.** That single rule would have caught `cc-notify` in hours instead of
   a day — it abstained on *every* send and nothing was counting. Without it, "correctly quiet" and
   "structurally blind" are the same observation.

---

## 2. Central design decisions (resolving the adversarial tensions)

| # | Decision | Rationale (axis) |
|---|---|---|
| D-A | **Build order: docs-first.** Wave A = telemetry-v2 (a) + plan-template §8 (e) + gate-batching (c) + auditability floor (k P1/P2/P6) + E2E harness (i) — all near-zero new failure surface. Then **run doc_classifier W4 on them** as the free experiment. Wave B (boundary hook h) and Wave C (supervisor b) build only to the extent W4's residual justifies. | j2 (invert order; W4 is the experiment), matches PLAN spawn-wave W-a/W-b/W-c |
| D-B | **RULED (#1): the supervisor PAGES, never auto-recovers.** It DETECTS + CHECKPOINTS-to-preserve (safe, pure insurance) + PAGES; the operator or a delegated *live* session performs any respawn. It is bash → cannot call in-session tools, so it physically cannot improvise a close on a live pane (b); live panes get DELEGATED advice via `cc-notify`. No auto-spawn/auto-close of a live *or* dead session — a confirmed-DEAD lead is checkpointed + paged, not auto-respawned (revisit only if a W4 residual proves it safe+needed). | b (DIRECT/DELEGATED split), j2, **operator ruling #1** |
| D-C | **Boundary-hook injection lands on the PROVEN `decision:block`+one-shot-latch fallback; `additionalContext` is probe-gated.** The advisory-vs-block distinction the plan assumed is source-contradicted on 2.1.207 — verify before relying (h/B1). The latch (keyed on configdir\|cwd + HEAD-sha) is what makes block advisory-not-looping. | h, m (guard #1) |
| D-D | **Supervisor = launchd `KeepAlive` daemon (5–10min sweep) + the existing 30s crash daemon; NEVER a standing Claude session.** launchd terminates the who-watches-the-watcher regress (RunAtLoad+KeepAlive); a standing session burns ~144 turns/day and recursively needs its own handoff. | b, m (cadence table) |
| D-E | **Teardown reconciliation: in-session lead teardown = `TaskStop` (the fire's rule, a harness tool the lead has); out-of-session supervisor teardown = `it2 session close` + confirm-gone.** `TaskStop` has no shell entrypoint, so the supervisor uses the proven `close_pane` and VERIFIES the pane is gone (D5). Both honor "teardown ≠ shutdown_request" (decorative). | f, b, D5 |
| D-F | **Widen the auto-compaction margin at the source**: the autonomy launcher profile sets `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=90`; the boundary hook fires at T≤73%. Never disable auto-compact (survival backstop). | h (Q3), j1 #1 |
| D-G | **The 3 ironic-failure guards are non-negotiable** (else the layer flips net-positive cost): one-shot latch (boundary), effect-verified debounce (supervisor false-positive), timeout-no-wake (`cc-await-ping`). | m |

---

## 3. Per-primitive build spec (organized by roster; cross-referenced)

### 3.1 `telemetry-v2` (axis a; owner: statusline.sh + bin/cc-context + new bin/cc-board)
- **P1 atomic export** — replace `>` truncate at `statusline.sh:56` with `.tmp`+`rename(2)` (pattern from `session-register.sh:57-62`); tmp inside `$TDIR`. Closes R1/R3, fixes j1 #6.
- **P2 sid-once guard** — compute `sid` once; empty → skip write (no `unknown.json` cross-corruption).
- **P3 stale-sweep on read** — `find -mmin +15` sweep in cc-context/cc-board, **exclude own sid**; hardened variant marks-stale-for-display + deletes only at long horizon OR `kill -0 <pid>` (avoids the fixtures-b2 long-turn false-negative).
- **P4 `cc-context --me`** — `sid=$CLAUDE_CODE_SESSION_ID` (EMPIRICAL: == telemetry filename on 2.1.207), fallback cwd-heuristic; gate on `[ -z "$CLAUDE_CODE_CHILD_SESSION" ]` (subagent var = parent id). Add `CC_TELEMETRY_DIR` override for E2E.
- **P5 export `config_dir`** — the telemetry→accounts join key, already computed at `statusline.sh:145-147`; ~zero cost.
- **P6 `cc-context --me --quota`** — fused read: config_dir→acct via accounts.json → `claude-accounts --json` (CACHE mode, 90s single-flight — never `--fresh`) → one line `ctx% · 5h% · wk% · fable% (↻h) · quota≤90s`. Answers "stay or go?" with no human relay.
- **P7 `bin/cc-board`** — operator all-sessions board (one glance replaces the 10 §1 relays). Spine = telemetry files; enrich with cached quota + rank footer. `watch -n5 cc-board`. Ships value telemetry-only; upgrades with P8.
- **P8 wire `session-register.sh` + carry `session_id`** — **CODE COMPLETE `7b2f701`; ACTIVATION HUMAN-GATED (audit §2b).** ⚠️ **P8 as originally specced would have shipped BLIND:** `cc-sessions` `rm -f`'d a registry row the moment its pid died — deleting exactly the rows that prove a spawn-death. Fixed by separating **liveness** (the `pid`; presence must NEVER encode liveness) from **retention** (age, 24h) from the **view** (addressing lists live-only, so `cc-notify` still cannot resolve a dead pane; `--all` = forensics). cc-board now joins registry×telemetry → **DIED-UNRENDERED** / **NO-RENDER?**. Original text: — the registry is EMPTY today (only worktree-scoped `live-session-registry.sh` is wired); add `session_id` to the entry + wire on SessionStart (`settings.json`). Gives board name+pid-liveness+paneUUID. Closes R6/D4.
- **P9 stall-state column** — DEAD(`kill -0` fail)/STALE(mtime>15m,pid alive)/HANDOFF-DUE/LIMIT-RISK/OK; **effect-verified** (dead-pid→DEAD even if telemetry fresh). Display-only; action = supervisor.

### 3.2 `boundary-hook` (axis h; owner: new hooks/boundary-handoff.sh)
- Self-resolve via Stop-stdin `.session_id` → read own telemetry. Conditions **(a)** clean tree ∧ `.git/gate-green==HEAD` ∧ no-live-teammates · **(b)** BUILD_LOG-head (or plan status-head)==`git HEAD`, repo resolved via `--git-common-dir` · **(c)** `used_pct≥T` (≤73), **abstain if ts age>180s**.
- **One-shot latch** keyed `hash(configdir|cwd)-<HEADsha>` (mirrors `session-continue.sh:30-34`). **Compose-guard**: no-op if `session-continue` sentinel armed. Explicit Stop-array ordering.
- **Injection**: PRIMARY `additionalContext` **probe-gated**; FALLBACK proven `{decision:"block",reason}` + latch + `systemMessage` for human visibility. (D-C)
- **Build deps**: B2 `.git/gate-green=<sha>` marker (new /ship + commit step — doesn't exist); B3 stale-sweep (axis a owns); B1 additionalContext probe.

**🔍 BLIND-CHECK PRE-MORTEM (invariant 7 + the desk's review criterion, applied BEFORE the build).**
*What is this check structurally unable to see, and who would end up checking that by hand?*
- **B-1 — it cannot see a session that never STOPS.** The hook fires on the **Stop** event. A session hung
  mid-turn never reaches Stop, so **the boundary hook NEVER RUNS for exactly the sessions most likely to be
  past their boundary.** Same shape as "no render ⇒ no telemetry" (§3h): the trigger and the failure are
  the same event. *Who checks by hand?* The operator, glancing at cc-board for DUE rows — i.e. **§1's relay
  survives** unless the SUPERVISOR covers this case (past-threshold ∧ not-Stopping). **The hook cannot be
  the only boundary mechanism; it is a refinement, never the carrier** (which invariant 4 already said for a
  different reason — this is a second, independent proof of it).
- **B-2 — the one-shot latch silences itself in the dangerous state.** The latch is keyed
  `hash(configdir|cwd)-<HEADsha>`. A session that receives the advisory, **ignores it, and keeps working
  without committing** leaves HEAD unchanged ⇒ the latch holds ⇒ **the hook never re-advises.** But
  "past boundary and not committing" is precisely the state the advisory exists for. → the latch needs a
  **second re-arm dimension** (a `used_pct` delta of ~+10, or a time-based re-arm), or it will go quiet
  exactly when it should get louder.
- **B-3 — it must log ABSTENTIONS, not only fires** (invariant 7's mechanical corollary). The hook abstains
  on stale telemetry, on a dirty tree, on a live-teammate check. If those abstentions are unlogged, **"it
  didn't fire" is indistinguishable from "it never evaluated"** — the D9 shape, in the primitive whose whole
  job is to fire. Emit `{fired|abstained:<reason>}` to the IDL every invocation; alarm on 100% abstain.

### 3.3 `supervisor` (axis b; owner: new scripts/lead-supervisor.sh + launchd plist)
- **Topology C**: launchd `KeepAlive`+`RunAtLoad` daemon, `while :; sweep; sleep 30`; **reuses** `lead-crash-watchdog.sh`'s registrar half (strip its per-session detached loop to registrar-only). Backstop tier = existing `team-orphan-reaper` 600s. Mutual re-bootstrap (every SessionStart re-arms the daemon; daemon re-arms sessions) closes the LaunchAgent-booted-out hole.
- **Recovery decision table — PAGE-biased per ruling #1** (detect + preserve + page; the operator/a delegated live session recovers): DEAD→checkpoint-preserve-to `refs/wip/LAST` **then PAGE** (not auto-respawn); STALL→`cc-notify` *advice* to the live session (its own model acts; never force-close); LIMIT-predicted→`cc-notify` advice + PAGE; LIMIT-actual (dead)→checkpoint + PAGE; MODAL-teammate→auto-deny stale `permission_request` (the one bounded auto-act — extends team-orphan-reaper, effect-verified); **MODAL-lead→PAGE** (ruling #2). The only auto-*acts* left are the safe/effect-verified ones (checkpoint-preserve, stale-perm-deny); every *recovery* (respawn/close) is paged.
- **Crash-path checkpoint gate** (the real gap): the graceful path checkpoints-before-remove; the crash path (`team-orphan-reaper archive`) does NOT — add `teammate-checkpoint.sh` on DEAD-lead per member worktree BEFORE any archive/remove (closes D1/D3).
- Detection LOGIC lives in axis h (D1–D7); b maps state→recovery only. Reboot ⟹ hand to `resume-sessions` skill, not respawn-loop.

**🔍 BLIND-CHECK PRE-MORTEM (invariant 7 + the desk's review criterion).**
- **S-1 — the REAPER/SWEEP RACE, and it is a real build constraint, not a nicety.** The supervisor polls
  every 5–10 min. **Any evidence whose lifetime is shorter than the poll interval is INVISIBLE to it** — it
  will sweep, find nothing, and report health. → **RULE: no reaper's horizon may be shorter than the
  supervisor's sweep interval × a safety factor (≥10×).** Today's horizons are safe by luck, not by design
  (telemetry 6h/7d, registry 24h vs a ~5min sweep). **State it, and gate it:** a future "tidy up /tmp" change
  that drops a horizon to 5 minutes would silently blind the supervisor, and every test would still pass.
- **S-2 — the supervisor's correctness DEPENDS on invariant 7 holding upstream.** It reads telemetry and the
  registry — the two artifacts whose reapers were *just* found erasing evidence (`93720eb`, `7b2f701`). A
  supervisor built on a spine that deletes its own evidence is a detector that reports "all clear" into a
  fire. This dependency is now explicit: **do not build b until a's and P8's evidence separation is landed and
  proven** (it is).
- **S-3 — it cannot see in-session state at all** (bash, out-of-session): modals, composer, mid-turn
  reasoning. Already ruled (MODAL-lead → PAGE), but now *named as a structural blindness* rather than a
  policy choice — the difference matters, because a structural blindness cannot be fixed by a better rule.
- **S-4 — it must log ABSTENTIONS** (same corollary as B-3). A supervisor sweep that finds nothing must
  record *that it looked and found nothing*, or a silently-crashed daemon is indistinguishable from a quiet
  system. **This is the "who watches the watcher" question, answered mechanically:** the watcher's own
  heartbeat is an outcome record, and its absence is the alarm.

### 3.4 `gate-batching` (axis c; owner: new scripts/gate-*.sh + template §8)
- **Asymmetric whitelist** (any doubt → STOP-ASK; false-negative catastrophic). 10 ruling classes C1–C10; pre-signable {C1–C5,C7}; conditional {C6 money-path=out-of-class-by-default, C8 go=couples axis d}; **C9 `/ship` = permanent exclusion + backstop**; **C10 self-modification/persistence = permanent exclusion, HUMAN-ONLY — not desk-signable, not agent-signable** (audit §2b: the harness itself enforces this; a peer agent's ruling is not user intent). `G-surface` grep gains `settings.json|hooks/|launchd|LaunchAgent|\.plist|crontab|PATH`.
- **5-gate discriminator**: `G-cite` (grep BUILD_LOG citation — catches born-at-exit) + `G-shape` (model: accept/reject not choose-among) + `G-reversible` (model+tag) + `G-surface` (grep `GPL|license|money|schema|auth|migration|DROP|timeout` — catches escalation) + `G-manifest` (class∈manifest ∧ wave-id current). **G-cite/G-surface are un-fakeable greps.**
- **P1 registry** (docs) → **P2 wave-start manifest** (`scripts/gate-manifest.sh`, wave-id+expiry) → **P3 classifier** (`scripts/gate-classify.sh`, mirrors handoff-disposition split) → **P4 auto-stamp** (`Ratified-By: operator (pre-signed class Cn, manifest…)` trailer — the ledger j1 #7 demanded) → **P5 batched out-of-class gate** (ONE 6-slot message from 31bcd087) → **P6 /ship backstop** (`git log --grep 'pre-signed class' <last-ship>..HEAD` for veto) → **P7 per-wave expiry** (stale W3 manifest at W4 → all out-of-class).

### 3.5 `comms-hardening` (axis f; owner: **`bin/cc-bind` — BUILT `5c881c2`** · merge-gate = `cc-bind gate` · team-teardown still unbuilt)
> ⚠️ **Read this section as a SPEC, not as a report of what exists.** On 2026-07-14 the BIND "fail-closed
> merge gate" described below was believed shipped and was **prose only** — no script, no hook — and a live
> operator ruling was about to ride it (audit §3g #5). Anything here without a commit sha is UNBUILT.
> BUILT: `cc-bind` (issue/ack/gate/selftest, `5c881c2`). UNBUILT: mailbox GC, `team-teardown`,
> `handoff-disposition.sh --teammates`.
- **The reliable downward channel already exists, unused for lead↔teammate**: `cc-notify` submit-verified injection targets any pane by raw UUID = teammate `tmuxPaneId`. Both shipping recovery paths (crash-watchdog shutdown_request + orphan-reaper permission_response) write the DECORATIVE inbox → **reroute both onto cc-notify-to-pane**.
- **Two-tier: NOTIFY (best-effort cc-notify) vs BIND (durable ruling file + commit-trailer `Acked-Ruling:<id>` + fail-closed merge gate)** — absence-of-ack IS the delivery-failure detector. **Respawn-at-boundary over mid-stream correction** (auto-compaction wipes composer; briefs survive as files).
- Extend `handoff-disposition.sh --teammates` (lead's R-PING mechanical); TEAM-PING recipe in brief template; **mailbox GC** (new — unbounded today). Teardown = `it2 session close`+confirm-gone (D-E).
- **Cross-epoch addressing (W4 datapoint, 2026-07-14):** a pane UUID is **epoch-specific** — a session's
  pane dies on self-close; its successor gets a NEW uuid. **Never cache a pane uuid across a
  succession.** Resolve the CURRENT role-holder at **SEND-TIME** via **role→pane indirection** — a roles
  file updated by succession events (`role=<pane>` rewritten on each self-close), or follow the newest
  self-close-log `successor=` chain. Safety nets that WORKED live: `cc-notify` went LOUD (mailbox-only +
  "unreachable", never false-delivered — `98a3dd9`), and the self-close log's `successor=` gave the
  authoritative re-address. Effect-verification CAUGHT the stale address; role-indirection PREVENTS it.
  Feeds §8 E5 (addressing) + R6.
- **⚠️ THE VERIFIER WAS INERT (audit §3g; FIXED `3b12107`, effect-checked live).** The `98a3dd9`
  submit-verify above **never executed its strand branch**: an it2 capture is BINARY (NUL-padded cells)
  and BSD `/usr/bin/grep` needs **`LC_ALL=C`** to byte-match the multibyte `❯` past the NULs (`-a` alone
  does NOT suffice — the UTF-8 locale still misses it). Every send for ~24h, in every session, reported
  `submit UNVERIFIED` + exit 0; the ~1-in-6 Ink strand was unwatched, and the **orchestrator was
  hand-capturing panes after each ruling** to compensate. **Consequence for this section's two-tier
  design: NOTIFY's "best-effort" tier was, in fact, *unverified* effort** — which is exactly why **BIND**
  (durable ruling file + `Acked-Ruling:` commit trailer + fail-closed merge gate) must carry every
  load-bearing ruling. **Absence-of-ack is the only delivery-failure detector that does not itself need a
  verifier.** Do not let a green NOTIFY tier tempt the design back toward trusting the send.
- **Successor-announcement addressing failure (2026-07-14, this session's own startup — dogfooded).** The
  successor's mandated FIRST action (announce its pane so the orchestrator re-addresses to it) **hard-failed,
  exit 3**: the brief carried the pane id as an **8-char prefix** (`99261468`) <!-- pane-id-lint:allow: quoting the bad form to teach it --> — the form the plan corpus,
  the audit and iTerm2's own UI all use — but `cc-notify` resolves **only** {registered friendly name |
  FULL uuid}. The name fallback was unavailable too: the registry is **EMPTY** (`cc-notify --list` →
  "(no sessions registered)") because **P8 is the un-wired Wave-A residual**. Two independent gaps composed
  to break the single most important startup action of a succession. **It failed LOUD** (exit 3 + "try
  --list"), never false-delivered — the fail-loud law holding under fire. **Two fixes, both cheap:**
  (1) `cc-notify` should accept a **unique uuid PREFIX** (expand against `it2 session list`; ambiguous or
  no-match → fail loud) — because the abbreviated form *is* the human/brief form and pretending otherwise
  guarantees recurrence; (2) **land P8** so the friendly-name path exists at all. Until both: a succession
  brief MUST carry the **full** uuid. Feeds §8 E5 + P8.
  - **PROVENANCE (orchestrator's own root-cause credit, 2026-07-14): the truncation entered at
    DOC-AUTHORING time, not brief-writing time.** The orchestrator wrote `orchestrator pane 99261468` <!-- pane-id-lint:allow: quoting the bad form to teach it -->
    into the plan and the W4/W5 proposal; every downstream brief then faithfully copied it. **The corpus
    IS the copy-source** — so the rule belongs in the DOC TEMPLATES, not merely in a brief checklist, and
    a prose rule cannot carry it (the author *knew* the full uuid and truncated anyway, for readability).
    Hence `scripts/pane-id-lint.sh` — mechanical, per this repo's own law that prose rules get violated
    and un-fakeable greps do not. It caught 9 live landmines across 5 files on its first run.
  - **The two shapes (this is the durable rule, and it dissolves BOTH failure modes):** an **operational
    address** → a **ROLE token** (`<orchestrator>`), resolved at SEND-TIME, because any uuid in a doc goes
    stale the moment that session recycles; a **historical reference** → the **FULL uuid**, stamped as a
    past fact. A stale-but-full uuid degrades GRACEFULLY (loud "unreachable" + mailbox fallback,
    recoverable); a TRUNCATED uuid hard-fails **exit 3** — unresolvable, and it cannot even be mailboxed.
    **Truncated is strictly worse than stale.**

### 3.6 `auditability` (axis k; owner: new bin/cc-idl, cc-truth, cc-audit)
- Three lie-classes: **T1 signal-lie** (freeze reported+truth at decision time), **T2 ledger-lie** (independent-observer + tamper-evident chain + transcript reconciliation), **T3 should-have-fired** (coverage check over telemetry series, not decisions-taken).
- **P1 hash-chained IDL** at FIXED `$HOME/.claude/autonomy/idl.jsonl` (cross-account; `git hash-object` chain → tamper-EVIDENT) · **P2 dual-snapshot** (reported `used_pct` vs truth=transcript usage-sum, the `1b8d671` recipe; δ>5pt alarm) · **P3 supervisor independent-observer** (intent w/o matching effect = papering-over) · **P4 completeness** (greppable `[AUTONOMY:kind:sha8]` marker in the immutable transcript → omission detectable) · **P5 should-have-fired** (replay series vs boundary predicate) · **P6 durable series** (+ PreCompact snapshot) · **P7 `cc-audit --wave`** = the FOUR ZEROS (§1 invariant 5) · **P8 designed-gate classification** · **P9 `cc-idl --replay`** (one-command re-derive any decision from raw sources) · **P10 E2E for the guard itself**.

### 3.7 `quota-scheduling` (axis d; owner: new bin/cc-wave-plan)
- Static one-shot planner: wave DAG × `claude-accounts --json` → **greedy-decrement placement** (rank via score, assign argmax, decrement projected headroom — fixes the 90s-blindspot that piles a wave on one account), ≤2/account cap. **Fable window-straddle guard** (front-load early; else downgrade→opus-4-8; else BLOCKER — window closes 2026-07-15T00:00Z). **Infeasibility ladder** (relax CAP→serialize→BLOCKER+earliest-feasible-start). **3-signal limit-predict** (percent-not-tokens → advisory: S1 structural, S2 5h-survival, S3 burn-extrap; needs one-line `prev` patch to `claude-accounts --json`). Output = plan JSON + ready `handoff-fire.sh` lines + `fallback[]` for axis l. **(Route placement from a LIVE `claude-accounts --rank` at plan time — NEVER a baked snapshot: a prior hardcoded "next3 weekly+fable-exhausted" note here went stale when next3 reset to fresh — an Invariant-7 doc-rots-a-live-number instance. Verified 2026-07-14: next3 fresh, next4 Fable 92%.)**
- **Ruled-fix-form de-escalation (added 2026-07-14 — `1336049`, F1-F8; the quota-efficient shape of the two-tier split).** When frontier-grade findings (Fable-judgment) must be FIXED under a tight frontier window, spend Fable **ONCE at ruling time** to convert each into an **Opus-executable RULED FIX FORM** (F1-F8 + a cheap batch), then **de-escalate mechanical execution to the default tier**. Distinct from the straddle guard's downgrade/block: you do NOT downgrade the JUDGMENT (the frontier tier's only value-add, per the opt-in-only routing law) — you downgrade the EXECUTION. "Frontier judgment spent once, mechanical execution de-escalated" is the general pattern; `1336049` ("quota-cliff insurance", fable_pct 91→live 92) is its first production instance.

### 3.8 `runtime-contention` (axis l; owner: mostly EXISTS + small additions)
- **Already solved** (do not rebuild): concurrent-land (`land-lock.sh` + content-verify + `stranded-sweep`), succession legibility, worktree-remove guard. **Add**: A1 land×succession mutual-exclusion (self-close defers on held land-lock); A2 locked-pipeline auto-retry (non-ff push → bounded re-rebase, cap 3); **A3 shared-checkout commit guard** (PreToolUse-Bash hook blocks git commit/push in `~/Development/claude-infrastructure` — machine-enforce the prose rule; dfacccd root); B1 successor-pane exclusive claim (`mkdir /tmp/succession-claim-<S>`); C2 parallel worktree-add mutex; D1 account-slot lease (route-time claim, the 90s-cache TOCTOU) + D2 lease heartbeat+succession-transfer. **Blocker**: `worktree-pool.sh` is ABSENT here (the "warm pool" claim in handoff.md is reso-borrowed) — cold `git worktree add` is the live path.

### 3.9 `context-budget-discipline` (axis g; docs into template §8)
- **Telemetry-first, never transcript-estimate** (thinking=0 bytes persisted but live-counted; B8). **Window-relative threshold** (never fixed tokens — same 47% → opposite verdict 200K vs 1M). **On 1M the binding constraint shifts fill→ROT** → a rot detector (re-read counter, fill-independent; ledger-reread excepted). `context_budget:` plan field (`start_clean≤25/mid_soft 50/boundary_recycle 60/hard_handoff 75`). **Delegate implementation off the lead** (5818bac0 did 31 Write+22 Edit+214 Bash = 704KB — contradicts "lead lands glue"). Relay-byte budget (structured manifests, not prose).

### 3.10 `e2e-harness` (axis i; owner: new scripts/*-e2e.sh + autonomy-e2e.sh)
- 4 reuse patterns already in-repo: **P1** live-pane+fake-binary+assert-effect (`handoff-selfclose-e2e.sh`; **symlink** the platform binary, never copy — macOS AMFI; NOT CI-able, needs `$ITERM_SESSION_ID`); **P2** sandbox-HOME+synthetic-stdin (`test-overwrite-guard.sh`; CI-safe); **P3** fixture-corpus+assert-invariants (`plan-phase-scan-tests`; CI-safe); **P4** verify-before-promote firewall (`smoke-test.sh`).
- **Every primitive needs a NEGATIVE/anti-trigger fixture** — both marquee rescues (§3b, §3c) were OVER-firing; "a suite that only proves firing would have passed the 2.3×-gauge build." Umbrella `scripts/autonomy-e2e.sh` (P4); CI runs P2/P3, P1 pane suites **SKIP-loud** on headless. Wire as pre-commit/pre-`/ship` gate → regressions self-announce.

#### The four harness laws — **paid for in production** (audit §3g, 2026-07-14; `3b12107`)

`cc-notify`'s submit-verifier shipped with an 89-line bats suite at **15/15 green** and was **inert from
birth** — the strand branch was unreachable code for ~24h across every session. Three *independent*
harness defects each sufficed to hide it, and none is specific to that file. These are now **gates on
every primitive's suite**, not advice:

| # | Law | The escape it closes |
|---|---|---|
| **L1** | **Fixtures must carry the REAL artifact's BYTES** — generate them from the real tool and commit them; never hand-`printf` a plausible reconstruction. | Fixtures were plain TEXT; a real `it2 session capture` is **binary** (iTerm2 NUL-pads empty cells). The suite tested a file production never emits, so it could not see that BSD `grep` needs `LC_ALL=C` to byte-match `❯` past the NULs. |
| **L2** | **Assert on a string the FAILURE mode cannot satisfy** — check substrings for accidental containment. | `*"VERIFIED"*` **also matches `"UNVERIFIED"`**: the assertion passed on the precise degraded result it existed to catch. (Now `"submit VERIFIED"`.) |
| **L3** | **Every assertion must actually TRAP** — in bats, a bare mid-body `[[ ]]` is **exempt from errexit** (bash keyword; `[ ]` and `grep -q` do trap), so a non-final `[[ ]]` can NEVER fail its test. Suffix `|| false`, or use `[ ]`/`grep -q`. | 7 of 7 `[[ ]]` assertions in the file were dead. Verified empirically on bats 1.13.0 — assume it of any bats suite until proven otherwise. |
| **L4** | **Prove the suite RED against the real bug** (bidirectional proof), and **effect-check the primitive live** before recording "FIXED". Green is a *report*; its teeth are the *effect*. | The suite was green over unreachable code, and the audit + project memory recorded `98a3dd9` as the strand FIX for ~24h. The live check (`cc-notify` printing `submit VERIFIED` for the first time) is what actually settled it. |

**L4 is the load-bearing one for THIS track**: the layer's whole value proposition is *detectors*, and a
detector's failure mode is to abstain forever while exiting 0 — indistinguishable from success unless you
watch real outcomes (→ detector **D9**, audit §7). Applies with full force to the boundary hook (h) and the
supervisor (b): **a detector that has never fired in production is UNPROVEN, not "quiet".**

**Tool-identity corollary (cost ~20 min of misdiagnosis):** a manual repro at an interactive prompt may not
run the binary the script runs — `grep` here resolved to a shell function → `ugrep`, which *does* match
where `/usr/bin/grep` does not. `type X` / absolute-path before trusting any repro, positive or negative.

### 3.11 `plan-template §8` (axis e; owner: template-author → docs/proposals/)
**Structural finding:** `doc_classifier/docs/specs/C00-orchestration.md` runs §0–§7 and STOPS — every one
of §1–§7 is the **teammate** layer. "§8" is literally the next integer: the first section describing
the **lead/session** layer above teammates. R4 = "the spec ends where the session layer begins."
**§8 ≠ Phase 0** (Phase 0 = generic teammate orchestration; §8 = the 5 improvised-every-wave session
concerns). Today the whole session layer is one unstructured status string (`"W4 lead, Fable @ xhigh,
account next"`).
**9 elements** (each closes R4; each validated by *effect*, not config):
- **E1 lead-session placement** — account/launcher/model/effort as a structured row; validated by `ps -eo command | grep -- --effort/--model` (config file lies, D2).
- **E2 context budget + succession trigger** — the numeric `used_percentage` threshold this lead hands off at; §8 *declares* it, the boundary hook (h) *consumes* it.
- **E3 write-fence inter-wave handoff** — wave N+1 holds a write-fence (no worktree/spawn/integration-write) until `git merge-base --is-ancestor <priorStampSha> integration`. Prevents teammates branching off a pre-ratification base.
- **E4 placement-plan consumption** — a producer(d)→consumer(§8) data contract `{account,launcher,model,effort,cap≤2,window-expiry-ts}` + a staleness/recompute predicate (never live re-rank per spawn).
- **E5 back-channel topology** — the ping graph + ARM state (teammate→lead mailbox pull-verified; lead→orchestrator `cc-notify`+R-PING; orchestrator→lead countermand).
- **E6 gate-batching manifest** — the pre-signed ruling-class slot (references c).
- **E7 lead-session isolation** — each concurrent LEAD (wave-lead, orchestrator, overlapping successor) on its OWN worktree/branch — not just teammates (confirms l/A3).
- **E8 session-spawn-readiness checklist** — the session-layer analog of C00 §7 (`scripts/session-spawn-readiness.sh`): E3 fence cleared · E4 placement fresh · E2 threshold declared · E5 UUIDs registered · E6 manifest signed · E7 worktree isolated → a missing box HALTS the wave cut.
- **E9 telemetry binding + self-cost** — the `cc-context × claude-accounts` join (a) + the layer's own footprint ceiling (m).

**Deliverables (docs/proposals/, NEVER doc_classifier):** `C00-SECTION-8-TEMPLATE.md` (blank E1–E9 + the E8 checklist) + `W4-W5-SESSION-ORCHESTRATION.md` (filled: W4 = next/Fable@xhigh, succession ≥60% at green boundary, `spawn base 3bb2e08` write-fence, 10 teammates→W4-lead→`<orchestrator>` (role, resolved at send-time) R-PING; W5 = maybe Opus@max if the Fable window closed, single lead). **Index per-wave with a succession sub-row** (a lead spans waves; a wave spans leads — keep both).

---

## 4. Revised Phase 0 (build order & team shape) — supersedes the plan's roster shape

**Wave A (safe, docs + near-zero-failure-surface; build + prove on W4 first):**
- `telemetry-v2` (a) — statusline atomic export + config_dir + cc-context --me/--quota + cc-board + wire session-register. Single-owner: `statusline.sh`, `bin/cc-context`, new `bin/cc-board`, `hooks/session-register.sh`.
- `gate-batching` (c) — the whitelist + manifest + classifier + auto-stamp + /ship backstop. Single-owner: `scripts/gate-*.sh`, `commands/ship.md` extension.
- `template+budget` (e+g) — §8 template + context_budget discipline → `docs/proposals/`. Docs-only.
- `auditability-floor` (k P1/P2/P6) — IDL + dual-snapshot + durable series (the load-bearing floor; without it the days-later audit has nothing honest to read).
- `e2e-harness` (i) — the per-primitive harness + umbrella gate; consumes each primitive as it lands.

**Wave B (runtime refinement, after Wave A + a W4 residual read):**
- `boundary-hook` (h) — depends on telemetry-v2 (a) + the `.git/gate-green` marker. Probe additionalContext; land the block+latch fallback.
- `quota-scheduling` (d) — `cc-wave-plan` + the `prev` one-line patch. Feeds the template.

**Wave C (the riskiest, smallest scope justified by residual):**
- `supervisor` (b) — launchd daemon + recovery table + crash-path checkpoint. Consumes h's detectors + k's independent-observer.
- `runtime-contention` additions (l) — A3 guard first (protects everyone), then leases.

**Dependency spine:** telemetry-v2 → boundary-hook → supervisor (detectors consume telemetry); gate-batching + template + auditability-floor + e2e run parallel to Wave A; comms-hardening (f) slots with supervisor (reroutes its recovery channel). Worktrees per-member off this branch; single-owner-per-file (§3). Teammate teardown = `TaskStop`.

**Deploy DoD (from prove-on-W4, 2026-07-14):** a repo commit ≠ a live tool. Every `bin/*` /
`statusline` / hook deliverable ENDS with an EFFECT-CHECK — `which <tool>` resolves AND the live target
carries the change AND `<tool>` runs. Deploy models differ: `bin/*` are SYMLINKED repo→`~/.claude/bin`
(edits auto-live; a NEW file needs `ln -s` created — `cc-board` was committed but un-symlinked, caught
by the orchestrator's effect-check); `statusline.sh` is a COPY captured live→repo by `sync.sh` (edits
need an atomic cp to `~/.claude/statusline.sh`). "Verify the EFFECT, never the report" (§1 invariant 1)
applied to DEPLOYMENT — same class as the statusline copy-drift. Add the effect-check to every build
teammate's DoD.

**Deploy DoD — clause 2 (added 2026-07-14, audit §3g): a "FIXED" claim about *checking* code is not a fix
until the check is seen to FIRE.** `cc-notify` was symlinked, live, and running — it passed clause 1
(`which` resolves, tool runs, exit 0) **while its verifier was unreachable code**. Deployment liveness ≠
functional liveness. So for any deliverable whose job is to DETECT / VERIFY / GATE (boundary hook,
supervisor detectors, gate classifier, `cc-notify`, the E2E umbrella itself), the DoD additionally requires:
**(a) a live invocation whose OUTCOME is inspected** — the positive branch observed firing in production,
not merely "no error" (for `cc-notify`: an actual `submit VERIFIED`); **(b) the suite proven RED against the
real bug** (bidirectional proof); **(c) fixtures built from the real tool's bytes** (§3.10 L1–L4). **Nothing
is recorded as FIXED** — in the audit, in memory, or in a status log — **on the strength of a green suite
alone**; the ~24h of false confidence here traces to exactly that.

**✅ Proof-of-value (prove-on-W4, 2026-07-14 first hour):** within minutes of deploy, `cc-board` caught
the live W4 lead at **63% — past the §8 E2 `boundary_recycle=60`** (from the filled W4/W5 instance) — and
the succession advisory fired on the rails. **This is the exact catch the operator used to make by
hand** (audit §1 — the manual `/context` relay → 0). STALE rows render correctly for closed teammate
panes (the interim age-based liveness proxy works pending the P8 registry-pid wire). The telemetry-v2
thesis + the §8 E2 threshold are **validated in production** — the strongest possible evidence for the
docs-first→prove-on-W4 order the operator ratified.

**Update (W4 succession epoch):** GO-deaf **instance #3** (driver pane, silent mid-queue death, caught
by the lead's task-boundary liveness check — post-dating the spawn-boundary rule) → **pane-death is now
detector `D8` with TWO trigger points** (spawn-boundary GO + task-boundary check-in; audit §3f + §7).
And the **first mid-wave LEAD succession ran clean** (`fire-w4-lead → fire-w4-lead-2`, ruling handed via
ledger stamp, back-channel held) — the §8 *session-layer* succession (E3/E5/E6) validated in production.
Two more confirmations that docs-first surfaces the right residual (D8's second trigger, and the
session-succession working) before any runtime primitive is built.

---

## 5. Operator decisions — **RULED 2026-07-14 ~02:0x · RATIFY ALL 5** (relayed via the orchestrator)

**Ruling stamp (all 5 ratified):** (1) DoD = **batched + legible + park-until-gate → the supervisor
PAGES, never auto-recovers** (stronger than the rec below: it detects + checkpoints-to-preserve +
PAGES; the operator or a delegated *live* session performs any respawn — no auto-spawn/auto-close of a
live *or* dead session). (2) unknown modal = **PAGE**. (3) C6 money-path = **permanently out-of-class**.
(4) build order = **docs-first → prove-on-W4 → runtime-only-to-residual**. (5) **`CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=90`**
on the autonomy launcher. → Boundary-hook + supervisor design UNBLOCKED under these laws.

_The rulings as originally surfaced (now discharged):_

1. **DoD framing** — is the target literally "zero human intervention for days," or j2's reframe
   "**batched, legible, park-until-gate**" (the operator already batches — "RATIFY ALL 7")? This
   changes whether the supervisor auto-recovers or only pages. **Recommendation: park-and-page +
   auto-recover only effect-verified DEAD panes**; measure with k's four zeros.
2. **MODAL-blocked lead** — the one residual non-zero-touch case (a live-but-modal-blocked lead has
   no sanctioned rail). **Recommendation: PAGE for unknown modals; auto-dismiss only the known-safe
   "resume from summary" prompt.** (b/blocker 1)
3. **C6 money-path two-person sign-off** — keep out-of-class (never pre-signable)? **Recommendation:
   yes** — data-integrity surface. (c/adversarial b)
4. **Build order** — approve docs-first (Wave A) + prove-on-W4 before building the supervisor? (D-A)
5. **`CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=90`** on the autonomy launcher profile — approve? (D-F)

## 6. Risk register (j1's ranked failure list → mitigation, all now owned)

| # | Failure | Mitigation | Owner axis |
|---|---|---|---|
| 1 | Auto-compaction beats the boundary hook (mid-turn, below boundary) | T≤73 margin + `AUTOCOMPACT_PCT_OVERRIDE=90`; supervisor pages at compact-threshold−margin regardless of boundary | h, b |
| 2 | Reboot/iTerm2 restart → data loss (worktrees at /tmp) + supervisor dead | worktrees OUT of /tmp; launchd `RunAtLoad`; reboot→`resume-sessions` | l, b |
| 3 | CC bump silently breaks fire/telemetry mechanics | E2E harness as MANIFEST-promotion gate (i); additionalContext probe (h) | i, h |
| 4 | API-incident storm → respawn-loop into the outage | circuit breaker: ≥2 accounts erroring → PARK + single poller | b, d |
| 5 | Account logout mid-wave (next3 ALREADY exhausted → 3/4) | pre-wave auth+routability gate; logout = designed-gate page | d |
| 6 | Telemetry silent-open (`\|\| true`, non-atomic, stale-as-live) | atomic export + stale-as-loud-fault + effect-verified liveness | a |
| 7 | Gate-batching silently absorbs out-of-class | auto-stamp trailer ledger + /ship retro-review + wave-expiry | c, k |

## 7. Empirical-resolve-at-build blockers (verify before trusting either doc)

- **B1** additionalContext-on-Stop on 2.1.207 — probe; land block+latch fallback until green. (h)
- **B2** no `.git/gate-green=<sha>` marker exists — add to commit/`/ship`. (h)
- **D2** per-member effort INERT vs settable — `ps -eo command \| grep -- --agent-name` on the FIRST build spawn is the arbiter, regardless of doc. Set LEAD effort correctly meanwhile. (audit D2; h/b/d/g/i/m all flag it)
- **team_name** required despite "deprecated" — always pass `session-<id>`; assert pre-spawn. (D7)
- **CLAUDE_CODE_SESSION_ID** == telemetry filename verified on 2.1.207; verify 2.1.114/2.1.183; P4 degrades to cwd-heuristic if absent. (a)
- ~~**next3** logged-out/exhausted NOW — the "4 accounts" premise is already false~~ → **STALE WITHIN HOURS (2026-07-14): next3 has fully RESET (5h 0% · weekly 0% · Fable 0%) and now ranks FIRST for both general and fable.** Kept, not deleted, as a worked example of **doc-rot**: this line would have misrouted this session's own successor *away* from the best available account. **Never route from a doc — route from the live read (`claude-accounts --rank general|fable`).** Same law as everything else tonight: verify the effect, never the report. The account-lease + pre-wave gate still stand on their own merits. (d, j1 #5)

---

_Provenance: 14-axis Wave-2 (a15d216 a · ad6e917 b · ab1486d c · a97a1ca d · aeee248 e[pending] ·
a20b151 f · a30eda6 g · a4534c4 h · adc3414 i · a8e98ed j1 · a175b5e j2 · aba397f k · a6381e9 l ·
a1e8697 m). Decomposition critic-revised 11→14 (ae984bf). All read-only; findings cited to R#/D# +
file:line in the source transcripts._
