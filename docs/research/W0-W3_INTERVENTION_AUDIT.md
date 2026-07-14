# W0–W3 Operator-Intervention Audit — the ground truth SESSION_AUTONOMY optimizes

**Status:** evidence-base deliverable (Evidence 4 of `docs/plans/SESSION_AUTONOMY_PLAN.md`). Read
this before the design research — every unplanned-rescue class below gets a mechanical detector +
sanctioned recovery in the Build phase.

**Method.** Deterministic extraction over the doc_classifier session transcripts
(`~/.claude-quaternary/projects/-Users-chrisren-Development-doc-classifier/*.jsonl`, 31 files,
read-only). Isolated human/operator turns = `type=="user"` ∧ `message.content` is a **string** ∧
`userType=="external"`, then tagged by content (extraction script + tagged corpus preserved in the
track scratchpad). Of 31 transcripts, **6 are operator-facing lead sessions**; the other 25 are
teammate panes whose only external-string turns are their own `<teammate-message>` briefs. Operator
burden therefore concentrates in the leads. Window per plan: **2026-07-13 01:44 → 2026-07-14 00:12
PST** (= UTC 07-13 ~08:44 → 07-14 ~07:12); leads in-window: `5818bac0` (W0/W1, Fable), `163b5ffa`
(W2/W3), `31bcd087` (W3-exit), `a28944df` (the orchestrator that wrote the plan + fired this track,
pane 99261468). Two earlier leads (`89369003` 07-11 port-readiness; `f2ba5c7b` 07-09) are tagged
**pre-window** and mined only for the limit-recover / workflow-supervision classes.

**Corpus tally (all 31 files, external-string turns):** 94 teammate→lead relays · 30 raw "operator"
(of which ~11 are harness `<task-notification>` auto-injections, not human) · 13 local-command
wrappers · 6 command-setup (`/model` `/goal` `/clear` `/effort`) · **5 `/context` relays** · **5
`/accounts` relays** · 4 `/ship` · 3 fire-headers. The human-authored intervention set is small and
fully enumerable — quantified below.

---

## 1. The headline pain, quantified — MANUAL TELEMETRY RELAY

The operator's own words (retrospective, `a28944df` 2026-07-14 07:28 UTC): *"One of the most glaring
patterns is that in between pause-points I have to run the `/context` and `/accounts` to give you the
understanding of when is an appropriate time to stay … or to handoff into the same session or a
separate session."*

Every hand-run diagnostic, in order (this is the burden to drive to zero):

| # | UTC ts | session | relay | value the operator read off | why it was needed |
|---|---|---|---|---|---|
| 1 | 07-13 09:21:39 | 5818bac0 | `/context` | 285.7k / 1M = **29%** | is the Fable lead safe to keep? |
| 2 | 07-13 09:21:40 | 5818bac0 | `/accounts` | (quota headroom) | which account for the next fire? |
| 3 | 07-13 15:36:26 | 5818bac0 | `/context` | 642.8k / 1M = **64%** | approaching hand-off? |
| 4 | 07-13 15:36:27 | 5818bac0 | `/accounts` | (quota) | — |
| 5 | 07-13 16:59:54 | 5818bac0 | `/context` | 726.4k / 1M = **73%** | pre-`/ship` fill check |
| 6 | 07-13 16:59:54 | 5818bac0 | `/accounts` | (quota) | — |
| 7 | 07-14 05:52:16 | 163b5ffa | `/context` | 474.2k / 1M = **47%** | is the W3 lead near its boundary? |
| 8 | 07-14 06:55:32 | 31bcd087 | `/context` | 374k / 1M = **37%** | W3-exit lead headroom |
| 9 | 07-14 06:55:33 | 31bcd087 | `/accounts` | (quota) | — |
| 10 | 07-14 06:55:42 | a28944df | `/accounts` | (quota) | orchestrator placement |

Plus two **derived** relays that are the same pain in a different shape:
- `a28944df` 07:04:52 — operator *delegates the whole burden*: *"Please proceed us through with this
  session, that session, any new sessions … with appropriate context managing, clearing,
  hand-offing, for all parallel … work."* The operator is asking the agent to do (1)–(10) itself.
- `163b5ffa` 05:55:51 — **forced relief on a relayed context number** (see §3b): *"You are at 95%
  context: do NOT take further work … you may self-close."*

**Root cause R1 + R2.** `/context` is TUI-only — a session cannot query its own fill mid-turn — and
the BUILD_LOG boundary rule's decisive condition is **qualitative** (see §4), so a human had to read
the number and make the stay/recycle/handoff call *for* the session. **Status:** the READ side is
fixed tonight (telemetry v1: `statusline.sh` exports `/tmp/cc-telemetry/<sid>.json`; `bin/cc-context`
reads it; `1b8d671` gives exact `/context` parity within 0.6pt on 1M). The **DECISION side is the
Build target** — the boundary hook that consumes a session's own telemetry at a committed/green
boundary and injects "run the `/handoff` rails now." Quota half of the relay (`/accounts`) needs the
telemetry×`claude-accounts` join (axis a).

---

## 2. DESIGNED GATES — features, but they arrived unbatched

These are legitimate human decision points (the plan calls them features); the defect is only that
each was a *separate* interrupt rather than a pre-delegated standing ruling.

| Gate | Instances (evidence) | What the operator ruled |
|---|---|---|
| Wave-exit ratification queue | W0 (5 spec deviations), W1 (queue carried), W2 `626b2fa` "RULED IN FULL", W3 `833186d` "RULED IN FULL, stamped `3bb2e08`" — and `31bcd087` 07:11:02 **"RATIFY ALL 7 … no exceptions"** | provisional/as-built forms stand |
| `/ship` (push to origin) | ×4 in transcripts; BUILD_LOG: W0–W2 pushed `fba97e9..ff5cf60` "operator /ship" | land the merged waves |
| "go" to cut the next wave | `5818bac0` 09:24 & 17:03 **"You have my go."**; BUILD_LOG "operator W1 go" | proceed to next wave's worktrees |

**Observation:** the operator *already* batches ("RATIFY ALL 7", "RULED IN FULL") — so the
formalization (axis c) is to let the operator **pre-sign ruling CLASSES at wave start**; the session
then STOP-ASKs only for genuinely out-of-class items. The `31bcd087` ruling even bundles the ruling
+ the exact stamp/commit steps + the successor pane id + the self-close command — a fully-specified
batched gate. That message is the template for a pre-delegated gate.

---

## 3. UNPLANNED RESCUES — the set that must reach ZERO

Each row is a time the operator had to intervene to fix a state the system should have self-handled.
Trigger → detector → recovery is the Build contract (axis h).

### 3a. Handoff "closed our session without opening the new one" — 3/3, verbal-intent path
- **Evidence:** `a28944df` 06:06:01 `/goal`: *"three out of three times today that we attempted a
  handoff on ourselves that closed our own session without opening the new one … the three times it
  happened from a verbal mention of handoff rather than me explicitly typing `/handoff`."*
- **Trigger:** verbal/relayed handoff intent executed by improvisation instead of the rails; the
  recycle watcher was `nohup`'d and died with the `/exit`-interrupt's process-group kill.
- **Status: FIXED** — `dd40eca` (nohup→setsid detached watcher, own session+pgid), `9918ff5`
  (self-close succession contract: verify-alive successor + announce-into-survivor + focus; bare
  self-close now exits 2 so an undeclared close is unrepresentable), and handoff.md's verbal/typed
  parity clause (`handoff-intent-nudge.sh`). **Detector exists:** `scripts/handoff-selfclose-e2e.sh`
  (9/9). Build adds this to the per-primitive E2E suite (axis i) so a regression self-announces.

### 3b. Premature relief driven by a 2.3× telemetry LIE — the marquee case
- **Evidence:** `163b5ffa` relieved at 05:55 on *"you are at 95% context"* while its own `/context`
  three minutes earlier (05:52) read **47%** (474k/1M). The old fixed-offset statusline gauge (built
  for the 200k era) over-reported ~2.3× on a 1M window.
- **Trigger:** the operator (and the session) trusted a broken gauge; a **half-full session was
  retired**, discarding its accumulated context.
- **Status: FIXED** — `7674496` (window-aware gauge kills the 2.3× lie) + `74d267f` (telemetry
  export) + `1b8d671` (exact payload `used_percentage` parity). **This is the proof-of-value for the
  whole telemetry loop:** an inaccurate self-signal doesn't just fail to help, it *causes* false
  rescues. The boundary hook (Build) must key off the payload's honest number, never a display offset.

### 3c. "Continue appropriately" — over-cautious pause
- **Evidence:** `5818bac0` 15:40:22 — a bare prod after the session paused.
- **Trigger:** a session STOP-ASKed / idled at a non-decision point (input it didn't strictly need).
- **Status: PARTIAL** — the Session-Close auto-continue arm (`session-continue.sh`, 🔧-state
  actuator) addresses the *in-scope-work-remaining* case; the boundary hook's advisory injection
  covers the *at-a-boundary* case. Build must ensure the two compose so a session neither stalls for
  a non-decision nor barrels past a real gate. Detector: idle-at-non-boundary (supervisor, axis b/h).

### 3d. Usage-limit kills mid-workflow (pre-window, 07-11, but recurring-class)
- **Evidence:** `89369003` ran `/limit-recover` ×2 (21:00, 22:15 — the second ingesting a salvage
  bundle) after limit interruptions during Dynamic-Workflow convergence.
- **Trigger:** 5-hour / weekly / Fable-scoped limit hit mid-run; slots died partial.
- **Status:** `/limit-recover` skill exists (disk-truth audit + transplant/salvage). Build's
  supervisor (axis b) adds the **detector** (telemetry×quota join predicts the limit BEFORE the kill)
  and routes recovery through the sanctioned rails, so the operator isn't the one noticing the kill.

### 3e. Workflow-convergence babysitting (pre-window, 07-11)
- **Evidence:** `89369003` — repeated operator prods *"Check workflow wf_… ; if slots failed on
  limits, resume with resumeFromRunId until 100% executed; loop until converged=true."*
- **Trigger:** no self-driving convergence loop; the operator manually re-checked and re-launched.
- **Status:** largely Dynamic-Workflow-internal (adjacent to core scope). Note as a **named
  out-of-scope discovery** feeding the plan-template's "self-driving convergence" pattern (axis e),
  not a core detector.

### 3f. GO-deafness at the spawn boundary — **W4 LIVE** (2026-07-14 ~01:3x, relayed via orchestrator `99261468`)
- **Evidence:** during the live W4 wave, two teammate panes (**B19b** + **web-core**) were
  **GO-deaf at their spawn boundary** — the lead's spawn-time GO never landed / was never acted on;
  the teammates sat deaf. The W4 lead **respawned both** and sharpened its rule to *"spawn-boundary GO
  unanswered = respawn, never nudge."*
- **Trigger:** the lead→teammate downward channel is unreliable at the **SPAWN boundary** too — a
  startup variant of the mid-stream unreliability (R6). A GO that reports sent but never binds.
- **Status: LIVE-VALIDATED design.** This is the **third comms-reliability instance in ~24h**, all
  ONE root — *a downward/cross-session send reports success but does not bind*:
  1. **composer-strand** — raw `osascript write text` submit newline redraw-swallowed ~1-in-6; a live
     countermand sat stranded 20 min → **FIXED** `98a3dd9` (cc-notify submit-verify, exit 4 on strand).
  2. **shutdown_request zombies** — 3 panes "shut down" alive hours later → teardown = `TaskStop`
     (in-session) / `it2 session close` (supervisor) **+ confirm-gone** (D5).
  3. **GO-deafness at spawn** (this) → **respawn-with-GO-in-the-brief, never nudge.**
- **Detector + recovery (feeds axis f / blueprint §3.5, R6):** effect-verify the GO (the teammate's
  first commit or an explicit ack); unanswered within N → **respawn with the GO baked into the fresh
  ≤150-line brief** (briefs are files → survive the unreliable channel + auto-compaction), never a
  mid-stream nudge (a nudge rides the same channel that just failed). The W4 lead reached axis f's
  "respawn-at-boundary over mid-stream correction" independently, under live fire — strong external
  validation of the meta-lesson "verify the EFFECT, never the send" (§7).
- **Instance #3 (W4 succession epoch, 2026-07-14):** the **DRIVER teammate pane died SILENTLY
  mid-queue** — *post-dating* the sharpened spawn-boundary rule, so this was NOT a spawn-GO miss; it was
  caught by the lead's **task-boundary liveness check** (mid-work), which the spawn-boundary rule alone
  would have missed. Recovery: lead rebased the branch onto `a90513e` and **respawned from task 5 with
  the accumulated rulings banked in-brief** (respawn-at-boundary, again). → **Detector generalization
  (orchestrator directive): silent pane-death is a D-detector — `D8` — with TWO trigger points: (1)
  spawn-boundary GO unanswered [#1 B19b, #2 web-core], (2) task-boundary check-in / mid-work pane-death
  [#3 driver].** Both effect-verify liveness (atomic `ps` + the expected commit); both recover by
  respawn-with-rulings-in-brief, never a nudge. Three GO-deaf instances now — the detection surface is
  spawn AND every task boundary, not spawn alone.
- **✅ Proof-of-value (same epoch): the first mid-wave LEAD succession completed CLEAN**
  (`fire-w4-lead → fire-w4-lead-2`) — the ruling handed across the boundary via a **ledger stamp** (§8
  E6 gate-batching + E3 write-fence) and back-channel continuity held (§8 E5). The §8 *session-layer*
  succession — not just the teammate layer — is validated in production.

---

## 4. The boundary rule — verbatim, and why it needed a human

From doc_classifier `docs/BUILD_LOG.md:30-37` ("When to clear / hand off"):

> Clear or `/handoff` **iff ALL hold**: (a) at a **committed + gates-green boundary** (a slot or a
> whole wave merged clean); **and** (b) this log's head names **every slot merged up to `git HEAD`**
> + memory captures the cross-session decisions; **and** (c) context is getting heavy *or* early rot
> shows (re-reading known things, drifting decisions). **Never mid-slot; never before this log is
> updated.** Because the trail always holds everything, clearing at a clean boundary loses nothing —
> so clear *proactively, at boundaries, before rot.*

- (a) is **machine-checkable now** (git state + the repo gate).
- (b) is **machine-checkable** (BUILD_LOG head vs `git HEAD`; memory presence).
- (c) was **qualitative** — "getting heavy / early rot" has no number, so a human read `/context` and
  judged it. Telemetry v1 makes (c) numeric (payload `used_percentage`). The boundary hook evaluates
  **(a) ∧ (b) ∧ (c-numeric ≥ plan-declared threshold)** and, only then, advises the rails.
- BUILD_LOG's companion warning (`W2 rule 3`): *"red-100% statusline = WARNING, not death … don't
  interrupt productive work (fixtures-b2 ran >1h past red-100% and completed)."* → the hook must be
  **advisory** and **boundary-gated**, never a hard stop mid-slot. This is why the plan bans a
  blocking Stop hook.

---

## 5. Cross-cutting root causes → Build axes

| # | Root cause | W0–W3 symptom | Status | Build axis |
|---|---|---|---|---|
| R1 | No self-telemetry loop (context + quota) | 10 hand-run `/context`+`/accounts` relays | READ fixed (v1); DECISION open | a (telemetry hardening), boundary hook |
| R2 | Boundary rule cond. (c) qualitative | operator supplies the number | open | boundary hook (a∧b∧c-numeric) |
| R3 | Handoff/succession mechanical bugs | 3/3 closed-without-opening; 2.3× gauge false-relief | FIXED (`dd40eca`,`9918ff5`,`7674496`,`1b8d671`) | i (E2E so regressions self-announce) |
| R4 | **No session-orchestration LAYER in the plan template** | lead account/model/context/succession improvised live | open | e (C00 §8 template + filled W4/W5) |
| R5 | Designed gates unbatched | each ratification/ship/go a separate interrupt | open | c (pre-delegated ruling classes) |
| R6 | Downward comms unreliable mid-stream; liveness lies | **3 comms-reliability instances/24h** (§3f): composer-strand (FIXED `98a3dd9`) · shutdown_request zombies · **GO-deafness at spawn (W4 live)**; plus idle-hook+ps both lied | partial (cc-notify submit-verify `98a3dd9`); design LIVE-VALIDATED | b/f (pull-based liveness, effect-verified GO, respawn-at-boundary-with-GO-in-brief, TaskStop/it2 teardown), supervisor |

**R4 is the structural one the operator named directly:** *"is there room for improvement on how we
create our multi-layer end-to-end implementation plans, and not just single Agent Team plans which
seem to go fine end-to-end there, but not when we are doing a whole platform implementation."* The
teammate layer (C00) was rigorous; the **session/lead layer above it had no template** and was
improvised every wave — that improvisation IS most of R1/R2/R5.

---

## 6. Success criteria — the mission contract, operator's words

`a28944df` 2026-07-14 07:28 UTC (verbatim extracts):
- *"self-manage like clock work … would have driven W0 through W3 perfectly, with clean clear and low
  context when starting tasks, continued context when working on the same task … autonomously without
  us human in the loop for essentially 24 hours straight without any prompts or pick-ups to prod us
  and restore us."*
- *"100x more research and planning effort/time/cost for a 1% implementation improvement … PERFECTION
  quality over quantity and speed … start and go through the entire end-to-end effort without human
  in loop for days straight as needed."*
- *"We still have W4-W5 to work through, so improving here would also be immediately beneficial."*

**Definition of done for this track = zero UNPLANNED interventions across a W-class wave** (the §1
relays → 0, the §3 rescues → 0), with the §2 designed gates **batched and crisp** (never silently
absorbed — they stay features). Measured against the exact patterns enumerated here.

---

## 7. Prior-fix lessons (from doc_classifier memory)

Seven memory files record the mechanical bugs behind the §3 rescues. Most are **FIXED tonight**; the
**OPEN** ones are runtime defects with named deterministic detectors — those become the supervisor's
sensor suite (§8).

| Memory file | Lesson (durable) | Status |
|---|---|---|
| `handoff-succession-legibility` | a close the operator can't SEE == a crash, however clean; announce must land in the SURVIVOR + move focus | FIXED (`9918ff5`; E2E 9/9) |
| `handoff-recycle-watcher-race` | a child outliving its own `/exit` needs `setsid` (PPID 1), not `nohup` (shares the SIGKILL'd pgid); gate irreversible steps on survivor-liveness proof | FIXED (`dd40eca`, `98a3dd9`) |
| `statusline-context-gauge-1m` | the statusline `NN%` is an estimate; trust `/context`/`used_percentage` for any relieve/split/handoff call; the 48pt/200k offset overstated 1M ~2.3× | FIXED (window-scaled `RESERVED_TOKENS`; `1b8d671` parity) |
| `agent-teammate-spawn-2-1-183` | on 2.1.183 the schema, effort file, mailbox, and `shutdown_request` all LIE — live process/disk state is the only truth | **OPEN** (workarounds landed) |
| `lr-audit-stale-residue` | per-agent transcript residue persists after `resumeFromRunId`; reconcile flagged slots vs the workflow journal+ledger before re-running | **OPEN** (discipline only) |
| `feedback-handoff-paste-one-sentence` | the human paste is ONE pointer sentence; the long payload lives only in the fire file no human reads | FIXED (Stop-hook contract) |

**The unifying meta-lesson (memory's "TOP PATTERNS"): _verify the EFFECT, never the keystroke /
spawn / config / report._** Every rescue traces to trusting a signal that lied — spawn-success (not
survivor heartbeat), a composer newline (not a cleared `❯`), the effort file (not `ps`), a clean tree
(not atomic ps+git), `shutdown_request` (not TaskStop). The supervisor and boundary hook must be
built on effect-verification, not status-reports.

### The OPEN mechanical detectors → supervisor sensor suite (feeds axis b/h)

| # | OPEN defect (source) | Deterministic detector (already named) | Recovery |
|---|---|---|---|
| D1 | Stale / edge-triggered idle notification → lead nearly commits over a woken-mid-edit teammate | **ONE atomic `ps` + `git status`**; alive-and-dirty ⇒ STAND DOWN | defer reap; re-check |
| D2 | Effort config file INERT (Agent passes `--effort <lead's>`) → whole-wave cost/quality silently wrong | `ps -eo command \| grep -- --agent-name` (read actual `--effort`) | set LEAD effort before spawn; re-verify |
| D3 | `.teammate-busy` is DELAY-only; reaped despite marker | reap decision keys off atomic ps+git, marker only defers | respawn successor w/ follow-up in brief |
| D4 | `SendMessage`/mailbox to a reaped teammate = dead mail reported as success | pull-based liveness (`cc-sessions` sweep) before trusting any downward send | TaskStop + respawn; corrections in the brief |
| D5 | `shutdown_request` decorative → zombie panes hours later | teardown via **TaskStop by name**; confirm pane gone | TaskStop; force-close pane |
| D6 | `lr-audit` re-flags superseded slots from stale transcript residue | reconcile flag vs `workflows/wf_<id>.json` journal + recovery ledger | ledger-append re-confirmation; skip re-run |
| D7 | `team_name` required though schema says "deprecated; ignored" (spawn blocked 4/5 without) | always pass `team_name:"session-<id>"`; assert before spawn | (workaround is the fix) |
| D8 | **silent teammate pane-death** (GO-deaf — pane dies at spawn OR mid-queue; 3 live W4 instances §3f) | **TWO trigger points:** (1) spawn-boundary GO effect-verified (first commit/ack), unanswered→act; (2) task-boundary liveness = atomic `ps` + expected check-in commit, mid-work death→act | respawn-with-rulings-in-brief (never nudge); rebase onto last-good commit, resume from failed task |

⚠️ **Build-time reconciliation flag (D2):** this audit's sources (BUILD_LOG + `agent-teammate-spawn-2-1-183`)
say per-member teammate effort is **INERT** on 2.1.183 (Agent forwards the lead's `--effort`), while
`~/.claude/rules/agent-teams.md` says `set-teammate-effort.sh` at worktree setup **works**
(binary-verified 2026-06-11). This is a version/mechanism discrepancy — **resolve empirically with
`ps | grep -- --agent-name` immediately after the first Build spawn** before trusting either; set the
LEAD's effort correctly as the safe default regardless.

---

## 8. What Build must deliver (audit → contract)

Directly implied by §1–§7, in dependency order:
1. **Telemetry v2** (axis a) — atomic writes, stale-file sweep, self-resolution (session→own id), and
   the **quota join** (`cc-context × claude-accounts` in one read) so a session sees BOTH its context
   fill and its account headroom without a human relay. Closes R1's read side fully.
2. **Boundary hook** (advisory Stop-hook) — evaluates **(a) committed+green ∧ (b) log-head==HEAD ∧
   (c) own `used_percentage` ≥ plan-declared threshold**, and only then injects "run the `/handoff`
   rails now." Never mid-slot; never a hard block (BUILD_LOG W2 rule 3). Closes R2.
3. **Supervisor** (axis b) — an out-of-session watcher extending `lead-crash-watchdog.sh` with the D1–D7
   detectors, stall/dead/limit/modal detection, and recovery **only** via the succession rails. Answers
   "who watches the watcher." Closes R6 + the §3d limit-kill detection.
4. **Gate batching** (axis c) — pre-delegated ruling CLASSES (the `31bcd087` "RATIFY ALL 7 + steps +
   successor + self-close" message is the template); STOP-ASK only out-of-class. Closes R5.
5. **Plan-template §8** (axis e) — the session-orchestration layer C00 never had: per-wave lead
   account/model/effort, context budget + succession triggers at committed boundaries, back-channel
   topology, gate batching. PLUS a filled W4/W5 instance. Closes R4 — the structural gap.
6. **E2E per primitive** (axis i) — so every FIXED item (§3a/§3b) and every new primitive
   self-announces on regression.
