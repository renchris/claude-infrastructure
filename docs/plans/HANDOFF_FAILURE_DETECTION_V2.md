---
status: in-progress
---

# HANDOFF_FAILURE_DETECTION_V2 — deskless failure detection, ground-up

**Status:** Phase 1 (measurement) · started 2026-08-07 · branch `deskless` · worktree `.worktrees/deskless`
**Dispatch:** fired by session 247 (lakehouse) · brief `/tmp/deskless-brief.md` (disposable — its durable facts are carried HERE)
**Map seam:** no dedicated GROUND_UP_REBUILD_MAP row — this sits on the seam of row 2 (lifecycle, DONE 2026-07-29), row 3 (cross-session comms), row 10 (operator surface).

## Phase 0 — frame

**Scope (frozen):** with `~/.claude/cc-roles/` EMPTY (no desk pane anywhere), all 3 handoff-failure
alarm classes in `scripts/handoff-fire.sh` (`HANDOFF-RECYCLE-DEAD` · `HANDOFF-STRAND-RISK` ·
`HANDOFF-HUSK-PANE`) reach a durable operator surface with **0 silent-drop call sites** (today:
5/5 role-push sites are `>/dev/null 2>&1 || true` against an unresolvable role — every one drops),
proven by tests that run with roles empty. Also decided, with evidence: whether `desk` should exist
at all, and whether `cc-roles` is needed by the answer.

**Standing constraint (kills lazy designs):** each of the three alarms fires when **its own author
is dying or already dead**, and **no live receiver pane is guaranteed to exist at fire time**
(roles empty is now the operator's deliberate state). Any design that requires a live pane at fire
time — desk or otherwise — is structurally dead on these paths. Push-to-a-pane can only ever be an
optional accelerator layered on something that survives with no receiver.

**Zero-factors:** implementation time/effort. Cost is explicitly not a constraint (dispatcher's words).

## Measured facts carried from the brief (2026-08-07)

1. **Incident chain:** pane-theft fix `1b5ff79a` (landed today) made the desk hint load-bearing and
   fail-closed (unresolvable hint = rc 3, not silent fallthrough). The operator then ran
   `pending-activation/32-cc-roles-kitty-normalise-activate.sh`, which found ALL THREE
   `~/.claude/cc-roles/*` files holding **iTerm2 UUIDs on a kitty box** and removed them.
   `cc-roles/` is now **empty** (backup: `~/.claude/cc-roles.bak-20260807T080444Z`). Do NOT
   repopulate it — operator's deliberate state (constraint 4).
2. **Measured consequence:** `cc-notify --role desk "probe"` → `verdict=unresolvable enqueued=0
   reason=role-unset`. Five consumers in `handoff-fire.sh` route through
   `--role "${CC_COMPLETION_ROLE:-desk}"`, all `>/dev/null 2>&1 || true`:

   | Line | Alarm | Who is alive to receive it |
   |---|---|---|
   | 2571 | `HANDOFF-RECYCLE-DEAD` — pane relaunched, never engaged | **nobody** — detached recycle watcher; original session exited by construction |
   | 2433 | `HANDOFF-STRAND-RISK` — successor died before the close instant | the firer, **mid-self-close** |
   | 2455 | `HANDOFF-HUSK-PANE` — `/exit` worked, `session close` failed 4/4 | **nobody** — detached self-close watcher, firer already gone |
   | 3241 | completion push | varies |
   | 2344 | payload-lint advice text (not an alarm) | n/a |

3. **What already exists (do not rebuild):**
   - **P0-11 engagement verification** (`handoff-fire.sh` ~1186, ~5088–5190): for every real
     non-recycle fire the FIRING session blocks until the successor's transcript shows an assistant
     turn, re-sends once on miss, fails the fire rather than printing a false `→ fired`. Measured
     live today: `proof=marker latency=16s`. **This IS the operator's proposed ping-back, for the
     separate-session path, already built.**
   - `cc-notify --mailbox-only` (record, no liveness verdict) · `cc-notify` **exit 5** (inbox
     unwritable → durable alarm record + best-effort phone page) · `cc-inbox-guard` (reaper cadence;
     escalates enqueued-but-never-consumed) · `~/.claude/logs/close-attrib.jsonl` (every close
     attempt with verified post-state; new in `1b5ff79a`, not yet written to — absence is expected,
     not a defect) · `cc-backlog needs`/`block` + pending-activation queue + SessionStart
     `additionalContext` (durable pull-based operator rails) · `--as-role`/`cc-register` (how a role
     gets set).

## Quarantined prior hypothesis (§4 of brief — NO authority; test or discard)

> Ping-back cannot cover the three dead alarms (author dying/dead). That class needs a durable,
> pull-based sink surfaced at next SessionStart, not a push to a live pane. §3 primitives may
> already be most of it.

Named ways it could be wrong (unexplored): a supervisor process could outlive both parties; the
alarms could be made unnecessary **by construction**; "desk" may be the wrong abstraction entirely;
a pull-based sink nobody reads is not detection.

## Decision questions (operator's, verbatim intent)

1. Can `desk` become genuinely optional opt-in with failure detection **best-in-class without it**?
2. Is ping-back the right primitive for the separate-session path (it exists as P0-11) — and what
   covers self-recycle / self-close?
3. Does the answer need `cc-roles` to exist at all?

## Hard constraints (bind all phases)

C10 stage-don't-edit (activation scripts to `~/.claude/autonomy/pending-activation/` + repo SSOT
`docs/activation/pending-activation/`) · own worktree/branch only · gate green before commit; land
via project-local `/ship` only · never repopulate `cc-roles/` · never flip `CC_FIRE_HEADLESS_ANCHOR`
· never regress `1b5ff79a` (46 tests w/ mutation controls) · read the comment above any
`handoff-fire.sh` block before changing it (d662845 app-frontmost drift; 174-new-windows leak;
three-state `resolve_headless_anchor` contract) · capacity gate refuses net-new fires above 2.0/core
under current load — expect refusals, never work around.

## Phase 1 — measurement plan (running)

- R1 failure archaeology: what was desk FOR; every observed failure on recycle/self-close paths;
  prior desk/roles design docs + incidents.
- R2 live telemetry from disk: how often did the 3 alarms actually fire historically; was desk set
  or empty over time; latency of "next session start" (the pull-rail's clock).
- R3 adjacent seams: cc-notify/cc-inbox-guard/pages/backlog/SessionStart rails — guarantees, exit
  codes, consumers.
- Lead's own reads: the 5 call sites; P0-11 block; self-close/recycle watcher structure; role
  resolution; `1b5ff79a` diff.
- Branch graveyard sweep (both commands) before building anything.

## Scope (grown)

- **+D7 desk-arm ownership trapdoor** (peer finding from 247, 02:01Z, VERIFIED in source): the
  1b5ff79a kitty anchor picker's `pick()` takes the `desk` hint UNCONDITIONALLY
  (`handoff-fire.sh:4724-4727`) — `agent_owned()` gates only the fallback walk (`:4733`). Any
  future `cc-roles/desk` pointing at a live operator pane re-arms the pane-theft class silently
  (an operator kitty id passes the isdigit identity guard `:4685`). Remedy chosen: **decouple the
  role's two uses** — desk stays a valid NOTIFY receiver whatever its ownership, but the ANCHOR use
  requires `agent_owned(desk)`; on failure, LOUD stderr demotion line + fall through to the gated
  walk (which can only ever return agent-owned or refuse — safe by construction). The exit-3
  identity guard is untouched (cross-terminal ids are corruption, not a receiver/anchor split).
  Owner: LEAD, sequential after t1-hfalarm's merge (same file). Constraint-6 note: if any of the
  46 tests pins the unconditional desk take, that test pins the trapdoor — amend WITH a mutation
  control and this justification (stale-assertion-inverts law: the side with the incident wins).
  Until this lands, cc-roles MUST stay empty (247 has told the operator so).
- **+D8 numeric pane-id resolution gap** (hit live, confirmed by 247 both ways): `cc-notify 247`
  → `verdict=unresolvable reason=no-such-target` while `--list` shows the session live; only the
  NAME form (`lakehouse-lecture-247`) resolves. Every fired brief's back-channel recipe says
  `cc-notify <number>` — the fleet's completion pings are one registry-shape away from silent
  drop (this rebuild's exact class). Disposition: verify resolver size at lead-integration time;
  fix if ≤~15 clean lines + test, else `cc-backlog add` with the exact evidence.

## Phase 1 findings — lead's own reads (2026-08-07)

**The lattice is far richer than the brief's §3 — and the break is at exactly ONE point.**

Producers of durable failure evidence (all working today, verified live):
- `~/.claude/logs/handoffs.jsonl` (emit_fire_event, `handoff-fire.sh:354` — fire admits/refusals,
  engagement outcomes incl. `engaged:0` records, `recycle-dead`, `recycle-unverified`). 1126 lines.
  **A real dead fire TODAY 08:35:49Z (pane 292, `engaged:0`) is in it, surfaced nowhere.**
- `~/.claude/completion-push/` (F5 capture-before-notify records). **Three terminal self-closes
  TODAY (sessions 284/253/246) each wrote `verdict: push-failed(cc-announce rc=5)` — correct, loud,
  unread.**
- `~/.claude/cc-announce-alarms/` (F1 announce-alarm + announce-degrade records; today's alarms exist).
- `~/.claude/autonomy/pages/` (supervisor page stamps) · `close-attrib.jsonl` (1b5ff79a) ·
  `FIRED_DIR/<pane>.json` + `record_close_succession` (`handoff-fire.sh:2291` — intent-time
  annotation, R10 "before the pane can evaporate") · `idl.jsonl` (daemon heartbeats).

Consumers:
- **`scripts/autonomy-sweep.sh` — THE ONE pull-based consumer** (self-described, header line 2) of
  pages/ + cc-announce-alarms/ + completion-push/ + decisions/. Loaded live
  (`com.chrisren.autonomy-sweep`, 300s). Its 2026-08-01 fix (REACHED/RECORDED/REFUSED, verdict-token
  parsing) is correct — **but the channel ladder is NESTED WRONG** (`autonomy-sweep.sh:338-384`):
  the Notification-Center fallback lives INSIDE the `[ -n "$DESK_TARGET" ]` arm. With the role file
  REMOVED (today's state) the sweep takes the S-7 no-desk-role branch: logs
  `{"notified":"no-desk-role","delivered":false}` to the IDL, retries every 300s, **and never posts
  the OS banner at all**. Records age out at `CC_EVENT_TTL_DAYS=7` — **silent loss with a 7-day
  fuse**. Removing the stale role uuid today made surfacing STRICTLY WORSE (stale uuid → RECORDED →
  banner fired; no role → nothing).
- `hooks/activation-watch.sh` (SessionStart additionalContext — the proven absence-is-loud pattern)
  and `hooks/operator-readout.sh` (Stop) — **neither reads pages/, cc-announce-alarms/,
  completion-push/**. The operator-facing renders are blind to the escalation stores.
- `scripts/lead-supervisor.sh` — loaded live (`com.claude.lead-supervisor`), pages DEAD/STALL leads,
  checkpoint-preserves worktrees (IDL entries today 08:43). Origin of the REACHED/RECORDED/REFUSED
  partition (efb12c6e).
- `scripts/desk-invariant.sh` — the desk-existence enforcer (no-desk → page + budgeted replacement
  fire). Plist exists in ~/Library/LaunchAgents **but NOT loaded** (absent from `launchctl list`).
  Desk is already de facto not running and its enforcer is inert.
- `bin/cc-reaper` — loaded live. Its desk-notify false-delivery fix sits UNLANDED on branch
  `fix/no-desk-reaper` (13520701, 7 RED-proven tests) — same defect class as the sweep's 2026-08-01
  fix, found by the graveyard sweep. Verify-at-land whether still unlanded.

The three dead alarm sites (real lines, post-1b5ff79a): STRAND-RISK `handoff-fire.sh:2790` ·
HUSK-PANE `:2816` · RECYCLE-DEAD `:2948` — all raw `cc-notify --role desk >/dev/null 2>&1 || true`,
**bypassing the F1/F5 stack that the completion push at `:3648` already uses correctly.** STRAND-RISK
and HUSK-PANE write NOTHING durable at fire time (their echoes go to the detached watcher's log);
RECYCLE-DEAD at least emits `emit_fire_event recycle-dead` first.

P0-11 (`verify_engagement`, `handoff-fire.sh:1449`) is transcript-proof engagement — STRONGER than
the operator's proposed cooperative ping-back (proof does not depend on the successor obeying
instructions). Live-measured today: `proof=marker latency=16s`. Recycle path has `recycle_engaged`;
self-close has T-0 pin re-verify. **Verification-at-fire-time exists on all three paths; the broken
half is exclusively WHERE THE FAILURE VERDICT GOES.**

## Phase 2 — INVARIANTS vs ARCHITECTURE

**INVARIANTS (any design must keep; numbered):**
- **I1 No silent drop.** A failure record is either delivered with PROOF (verdict token) or remains
  visibly undelivered; mark-seen only on proven delivery. (claimed-outcome-vs-checked-outcome; the
  964-marker silent-loss incident, sweep header.)
- **I2 Verdicts are machine tokens**, never exit codes or prose — a `|| true` must not be able to
  launder an outcome. (sc/t4-alarm; cc-announce F3 fail-closed UNKNOWN.)
- **I3 The lattice terminates on a liveness-free surface.** Disk render at the operator's own next
  interaction + OS banner; a live pane (desk or peer) is an ACCELERATOR, never the foundation, and
  no liveness-free channel may be gated behind a liveness-dependent one. (Today's S-7 finding.)
- **I4 Author-death proof.** Detection must survive the author dying at any instant: intent recorded
  at arm time by the author, outcome joined later by an INDEPENDENT reader (launchd cadence).
- **I5 Absence-is-loud.** Every consumer emits a heartbeat/outcome record; a silent consumer is
  itself an alarm (lead-supervisor S-4; IDL fired/abstained B-3).
- **I6 Bounded externals.** Every notify/osascript/it2 fork bounded; rc 124 = REFUSED (retry), never
  a hang. (2026-07-26 machine-wide AppleEvent wedge.)
- **I7 Damped, never dropped.** Re-surfacing is damped (no 300s storms — e5894631) but a record
  survives until proven-delivered or explicitly expired, and expiry of a NEVER-delivered alarm must
  itself be loud, not a quiet unlink.
- **I8 No composer keystrokes.** Inbox/mailbox + additionalContext only (v2 comms law).
- **I9 Id-space assertion.** Every pane/session id carries its terminal space; iTerm2 UUIDs and
  kitty ints never conflate (root of today's incident).
- **I10 Existing gates hold.** 1b5ff79a's 46 mutation-controlled tests; P0-11; recycle_engaged; T-0
  pin; M3 mail disposition. Regressing any is a design failure.
- **I11 C10.** Live layer changes ship as staged activations only.
- **I12 Fail-visible defaults.** A new verdict/class lands in a loud default arm, never absorbed
  (new-enum-member memory; _fire_gate_of pattern).

**ARCHITECTURE (incumbent mechanisms, inherited by default from NOTHING):**
- desk role as THE terminal consumer; cc-roles/desk as the sweep's delivery gate.
- The channel ladder's nesting (OS banner inside the desk arm).
- Alarm sites as raw fire-time pushes (vs the F1/F5 capture-before-notify stack).
- Per-close watcher logs as the only sink for STRAND/HUSK facts.
- 7-day TTL unlink regardless of delivery state.
- desk-invariant's posture that no-desk is a FAULT to repair (page + replacement fire).

**THE INVERSION** (what dissolves the failure class): today every escalation path terminates at a
live pane and treats "no pane" as a fault; the rebuild makes **the durable record the primary
artifact and the operator's own next interaction the guaranteed terminal consumer** — any live pane
becomes an opt-in accelerator. Concretely: (1) alarm sites write capture-before-notify records
FIRST; (2) the sweep's channel ladder un-nests — liveness-free channels fire regardless of role
state; (3) a SessionStart/Stop render makes un-drained escalation records visible in EVERY session
(the activation-queue pattern); (4) role-unset becomes a NORMAL configuration (verdict `RECORDED`,
never an error), which is what "desk as optional opt-in" means mechanically.

## Phase 3 — DESIGN (deskless-first escalation)

**Verdict on the operator's three questions:**
1. **Yes — desk becomes a genuine opt-in accelerator.** Detection is complete without it because
   the lattice terminates on liveness-free surfaces (durable records → session render + OS banner),
   not on a pane.
2. **The ping-back for separate-session fires already exists and is stronger than proposed** —
   P0-11 verifies engagement from the successor's own transcript (no cooperation needed; measured
   16s today). The self-recycle/self-close paths are covered by D1–D4 below: their failure facts
   become durable records with a guaranteed reader, not pushes to a maybe-pane.
3. **cc-roles stays** — as the opt-in wiring for the accelerator (SO-1 role indirection is sound and
   the kitty-normalisation now enforces id-space (I9)). But role-unset becomes a NORMAL
   configuration everywhere: verdict `RECORDED`/`REFUSED`, never an error, never a fault to
   auto-repair, and NO liveness-free channel may be gated on role state.

### D1 — alarm sites: capture-before-notify (handoff-fire.sh)
New helper `hf_alarm <class> <detail>` replacing the raw pushes at :2790 (STRAND-RISK), :2816
(HUSK-PANE), :2948 (RECYCLE-DEAD):
1. **Record FIRST**, dependency-free (printf-JSON, the `write_teardown_marker` precedent — no jq so
   capture can never fail wider than itself; add-on blast-radius law) into
   `~/.claude/handoff-alarms/alarm-<utc>-<pid>-<rand>.json`:
   `{kind:"handoff-alarm", class, pane, sid, successor, detail, ts}`.
2. **Push second**, best-effort accelerator: `cc-announce` (bounded), rc + `verdict=` token CAPTURED
   and echoed to the watcher log — the `>/dev/null 2>&1 || true` idiom is banned at these sites.
3. **Verdict sidecar** `<record>.verdict` written after the push (`reached|recorded|refused-rcN`);
   a record with no sidecar reads as refused (fail-closed, I12) — crash-safe at every instant.
Kill switch: `CC_HF_ALARM_RECORDS=0` → legacy push-only.

### D2 — sweep ladder un-nested (autonomy-sweep.sh)
Today (`:338-384`): OS banner reachable ONLY inside the `[ -n "$DESK_TARGET" ]` arm; no-role branch
= IDL row + retry, **no banner** (the S-7 branch, live since today's role removal).
New ladder, each rung independent (I3):
1. Collect adds `~/.claude/handoff-alarms/` (+ its TTL compaction).
2. Desk push — only if role wired. `REACHED` (verdict=delivered) → mark `.seen` (unchanged).
3. **OS banner fires on new records REGARDLESS of role state.** Posting writes a per-record
   `.bannered` marker (damps re-banner, I7) but does NOT mark `.seen` — a transient banner is not a
   proven read; the records stay visible to D3 until REACHED, acked, or TTL.
   (This deliberately revises the 2026-08-01 RECORDED-branch decision that banner ⇒ seen: that
   choice traded silent loss for storm-avoidance because no damping store existed; `.bannered` IS
   the damping store, so the trade is no longer forced.)
4. **Loud expiry**: a record aging out at `CC_EVENT_TTL_DAYS` with no `.seen` is counted into an
   `expired-unread` IDL row + a D3 render line — never a quiet unlink (I7).
Kill switch: `CC_SWEEP_LADDER=legacy`.

### D3 — the guaranteed reader: session render (new hook + Stop line)
`hooks/escalation-watch.sh` (mirrors `activation-watch.sh`): SessionStart additionalContext, renders
un-`.seen` escalation records (handoff-alarms/ · cc-announce-alarms/ · completion-push non-verified
· pages/) as counts-per-class + first-lines (bounded), once per session, fail-open, reads-only.
Plus ONE counted line in `operator-readout.sh`'s standing block (additive).
Includes sweep-liveness: "sweep last ran Nm ago" goes red > 15 min (the watcher-of-the-watcher, I5 —
reads idl.jsonl tail, no new store).
Registered via staged activation (I11). Kill switch: `CC_ESCALATION_WATCH=0`.

### D4 — author-death join (autonomy-sweep.sh, same owner as D2)
The one uncovered class: the detached watcher itself dies (reboot, kill; detach() survives group
SIGKILL but not the box). Join at sweep cadence:
- INTENT: `~/.claude/watchdog/teardown/<sid|pane>.json` (`{mode, ts}` — written pre-/exit at :3728,
  :5494).
- OUTCOME: `~/.claude/logs/close-attrib.jsonl` row for the same id at/after marker ts.
- WORLD: pane still present (bounded it2/kitty list; rc 124 ⇒ NO-DATA, skip this tick — a blind
  probe never alarms; probe-acting-on-absence law).
Marker older than `CC_HANDOFF_JOIN_DEADLINE_S` (default 900s ≫ watcher's 180+8s worst case) + no
outcome row + pane STILL PRESENT ⇒ synthetic `handoff-orphan` record into handoff-alarms/ (once,
keyed by marker id). Pane gone + no row = benign (vendor close / fail-open attrib) — no alarm
(alarm-polarity law). Kill switch: `CC_HANDOFF_JOIN=0`.

### D5 — `bin/cc-escalations` (list | ack <id>|--all)
The explicit drain: ack writes `.seen`, so D3's nag has a humane off switch. Also the test surface
for the marker semantics.

### D6 — desk opt-in guard (desk-invariant.sh)
desk-invariant currently treats no-desk as a fault (page + budgeted replacement fire). Unloaded
today, but a loaded-later landmine under the new model. Add the opt-in gate: no `cc-roles/desk` AND
`CC_DESK_OPTIN` unset ⇒ exit 0 `verdict=not-opted-in` (IDL row, I5) — enforcement only for those who
opted in. Mutation control: pre-change file pages on the same fixture.

### Failure-mode table (every observed mode → structural answer)
| # | Mode (observed) | Detection today | After |
|---|---|---|---|
| F1 | separate-session fire never engages (INC-4) | P0-11 blocks, fails fire LOUD | unchanged (keep) |
| F2 | recycle relaunch never engages (task-less pane, GH slash-head class) | recycle_engaged + handoffs.jsonl event + DEAD push | + D1 record + D2/D3 surfacing |
| F3 | successor dies before close instant | T-0 pin abort + DEAD push | + D1 + D2/D3 |
| F4 | /exit ok, pane close fails 4/4 (husk, 2026-07-26 pane 1FBFCD05) | 4 retries + DEAD push | + D1 + D2/D3; D4 catches the watcher-death variant |
| F5 | watcher itself killed (2× 2026-07-13 pgid SIGKILL class; reboot) | **nothing** (detach() fixed the pgid case only) | D4 intent/outcome/world join |
| F6 | terminal completion push fails | F5 records exist, verdict correct, **no reader** | D2/D3 surfacing (records already there) |
| F7 | sweep itself dead | IDL heartbeats, **no reader** | D3 sweep-liveness line |
| F8 | roles removed / desk dead (TODAY) | S-7 branch: no banner, 7d silent loss | D2 rung 3 independent of role; D1 records; D3 render |
| F9 | banner unavailable (no osascript / SSH box) | RECORDED-arm banner fails → refused-loop | D3 render is the guarantee; banner stays advisory |
| F10 | record expires unread | quiet unlink | D2 loud expiry + D3 line |

### Rejected alternatives
- **Cooperative ping-back from the spawned session** (the operator's proposed primitive): only
  covers the separate-session path, where P0-11's transcript-proof is already stronger (no successor
  cooperation required); structurally cannot cover self-recycle/self-close (author dead by
  construction). Answer to §5 Q2: keep P0-11; the dead-alarm paths need records, not pings.
- **Restore/repopulate the desk role**: recreates the single point of liveness; violates the
  operator's deliberate state (constraint 4); role files demonstrably rot (held dead iTerm2 uuids
  for 12 days — sweep comment `:253`).
- **A new dedicated supervisor daemon**: the fleet already runs autonomy-sweep + lead-supervisor +
  cc-reaper on cadence; a 4th watcher adds failure surface without a new guarantee. Extend the ONE
  pull consumer instead.
- **Pure pull (rip out pushes)**: loses the fast lane when a receiver exists; pushes are cheap,
  bounded, verdict-parsed. Keep as accelerator.
- **Phone/ntfy as the terminal channel**: transport staged but unactivated (04-page-channel,
  rotting); external dependency; not liveness-free ON the box. Stays the away-channel follow-on.
- **Writing alarm records through completion-push.sh** (reuse instead of hf_alarm): pulls a jq
  dependency into the detached-watcher env (daemon-PATH landmine) and muddles record kinds; the
  record write must be dependency-free. cc-announce is still reused for the PUSH half.

### Acceptance criteria (disk-truth reads, each with a control)
- A1 roles-empty + each of the 3 sites → record file exists in handoff-alarms/ with correct class;
  site output carries a verdict token; `grep` proves the `|| true`-silent idiom GONE from the 3
  sites. Control: pristine tree (git archive) fails all three.
- A2 sweep, roles empty, new records → osascript stub CALLED once; `.bannered` written; `.seen` NOT;
  second run does NOT re-call osascript (damp proven). Control: legacy ladder never calls the stub.
- A3 escalation-watch with records → additionalContext lists class counts; with none → empty output
  (absence-of-noise control); acked records not rendered.
- A4 TTL-expired unseen record → `expired-unread` IDL row + D3 line; expired SEEN record → silent.
- A5 D4 fixture: marker older than deadline, no attrib row, pane present (stub) → ONE
  handoff-orphan record (idempotent on re-run); attrib row present → none; world probe rc 124 → none
  + retry row.
- A6 full handoff suites + 1b5ff79a's 46 mutation-controlled tests green.
- A7 cc-escalations ack → `.seen` exists; D3 stops rendering.
- A8 desk-invariant, no role + no opt-in → `not-opted-in`, zero pages/fires; mutation control:
  pre-change file pages.

### Measured constants (citations)
| Constant | Value | Source |
|---|---|---|
| Sweep tick | 300s | com.chrisren.autonomy-sweep loaded; sweep header |
| Event TTL | 7d (CC_EVENT_TTL_DAYS) | autonomy-sweep.sh:30 |
| Watcher close worst case | 180s poll + 4×2s | handoff-fire.sh:2749,2805 |
| D4 deadline | 900s (derived ≥5× worst case) | this design |
| P0-11 timeout/retry | 120s + 60s (FIRE_ENGAGE_*) | handoff-fire.sh:1451 |
| Engagement latency, live | 16s (proof=marker) | today's fire, brief §3 |
| Banner truncation | 200 chars | autonomy-sweep.sh:324 |
| notify bound | 25s (CC_SWEEP_NOTIFY_TIMEOUT_S) | autonomy-sweep.sh:43 |
| Today's silent-drop volume | 21 announce-alarms, 3 push-failed completion records, 1 engaged:0 fire | live ls/jq 2026-08-07 |
| Alarm-class incidence | R2 (pending) | — |
| Next-SessionStart latency p50/p95 | R2 (pending) — bounds D3's clock | — |

## Phase 0 (Agent Team Orchestration)

**Team: 4 teammates + lead. All spawn in ONE wave (files fully disjoint; interface frozen below).
Teammates work IN THIS WORKTREE (`.worktrees/deskless`) on disjoint files and NEVER run
`git add/commit` — the LEAD commits per-task atomically after review (sidesteps the parallel
worktree-creation races GH #34645/#48927; git index contention is impossible when only the lead
touches the index).** Model: inherit (Opus 5 high). Briefs ≤150 lines, pre-grepped ranges included,
stop-on-issue verbatim.

| Teammate | Owns (exclusively) | Delivers |
|---|---|---|
| `t1-hfalarm` | `scripts/handoff-fire.sh` · `tests/handoff-alarm-records.bats` (new) | D1: `hf_alarm` + 3 site conversions + tests |
| `t2-sweep` | `scripts/autonomy-sweep.sh` · `tests/autonomy-sweep.bats` (extend) | D2 ladder + collect + expiry, D4 join + tests |
| `t3-render` | `hooks/escalation-watch.sh` (new) · `tests/escalation-watch.bats` (new) · `hooks/operator-readout.sh` (ONE additive counted line ~:91 vocabulary) · `tests/operator-readout.bats` (extend) · `docs/activation/pending-activation/33-escalation-watch-activate.sh` (new) | D3 + activation |
| `t4-cliguard` | `bin/cc-escalations` (new) · `tests/cc-escalations.bats` (new) · `scripts/desk-invariant.sh` (opt-in gate at `handle_no_desk` :396) · `tests/desk-invariant.bats` (extend) | D5 + D6 |

**Dependency graph:** none blocking — the interface is frozen here, not negotiated between
teammates. Lead reviews each deliverable against the acceptance criteria (A1–A8), commits serially
(smallest-diff first), runs the cross-suite regression, lands via project-local `/ship`, then
stages the live activation copy (cp repo→live pending-activation, per the SSOT-parity convention).

**FROZEN INTERFACE (all briefs cite this verbatim; changing it = message the lead, stop):**
- Record dir: `${CC_HANDOFF_ALARM_DIR:-$HOME/.claude/handoff-alarms}`
- Record file: `alarm-<utcstamp>-<pid>-<RANDOM>.json`, single line, printf-JSON (NO jq dependency):
  `{"kind":"handoff-alarm","class":"<strand-risk|husk-pane|recycle-dead|handoff-orphan>","pane":"<uuid|kittyid>","sid":"<sid|>","successor":"<uuid|>","detail":"<text>","ts":"<utc>"}`
- Verdict sidecar: `<record>.verdict` containing one token: `reached|recorded|refused-rc<N>`
  (absent sidecar ⇒ treated as refused — fail-closed).
- Seen marker (sweep-owned): `$SEEN_DIR/<record-basename>.seen` (existing sweep convention).
- Banner damp marker (sweep-owned): `$SEEN_DIR/<record-basename>.bannered`.
- D4 inputs: `~/.claude/watchdog/teardown/{<sid>.json,<pane>.json}` (`{key_kind,pane,sid,mode,ts}`),
  `~/.claude/logs/close-attrib.jsonl` (`{ts,site,mode,terminal,id_requested,owner,verdict,…}`).
- Kill switches: `CC_HF_ALARM_RECORDS=0` · `CC_SWEEP_LADDER=legacy` · `CC_ESCALATION_WATCH=0` ·
  `CC_HANDOFF_JOIN=0` · `CC_DESK_OPTIN=1` (opt-in assert).
- Test law: hermetic `$HOME` in `BATS_TEST_TMPDIR` · `CC_FIRE_CAPACITY_GATE=off` where
  handoff-fire runs (box lives above 2.0/core) · RED-proof every new test against a pristine tree
  via `git archive` (never hand-edited) · positive control beside every absence assertion ·
  `|| false` on non-final `[[ ]]` in bats · `bats` on PATH is the cc-bats chokepoint (expect
  admission queueing under load; single-suite runs are fine).
