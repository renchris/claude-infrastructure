# A18 — Liveness-Model Attack: FM2 Scenario Trace

Adversarial trace of the desk liveness stack. Every verdict is traced through actual detector
code. Deployment ground truth (verified live 2026-07-18): launchd runs `cc-reaper sweep --reap`
@300s (plist + log: "sweep end … 33 classified 0 candidates 0 reaped"); `lead-supervisor.sh
--daemon` runs with **CC_PAGE_TO=""** (empty string in com.claude.lead-supervisor.plist);
`waiting-recycle.sh` wired on PostToolUse; `lead-reconciler.sh` and `lead-deathwatch.sh` are
**NOT deployed** (no launchd entry, no caller) — L4/L1 are dormant modules; `reap-guard.sh` is
built but **not called** by hooks/teammate-auto-shutdown.sh (grep: zero references);
`session-deregister.sh` exists but is **not wired** in settings.json (SessionEnd list lacks it);
`~/.claude/cc-roles/` has **no writer anywhere in the repo**; `~/.claude/cc-announce-alarms/`,
`~/.claude/completion-push/`, `~/.claude/autonomy/pages/` have **no consumer anywhere in the repo**.

## 1. Scenario table

### L-1 · fired-never-engaged · cold-fire auto-submit race
- **Setup** (real incident 2026-07-17, memory `cold-worktree-fire-autosubmit-race.md`):
  `handoff-fire.sh --worktree <branch>` creates a cold worktree; prompt keystrokes race CC boot;
  session sits at an empty composer forever. Fire prints "→ fired" unconditionally —
  `spawn()` returns after typing, no engagement check exists (handoff-fire.sh:1065-1070).
- **Signal state**: pid alive; cc-registry row present; transcript absent OR zero
  `type=="assistant"` records; telemetry written once at boot then stale; 0 commits; no ping.
- **Detector trace**:
  - cc-classify: `last_assistant_ts` empty → `IDLE=-1` → **cc-classify:205** `CAUSE=active
    "no readable assistant timestamp — cannot prove idle (fail-safe)"` → never-reap bucket
    (cc-reaper:101). Classified ACTIVE **forever**.
  - lead-supervisor: telemetry age ≥1800 → `STALL?` page (lead-supervisor.sh:142-144) →
    `resolve_page` → `reobserve_effects` dark (no commits/mtimes since page) → `ESCALATED`
    (:110-113). But `[ -n "$PAGE_TO" ]` is false (plist sets "") → cc-notify never fires
    (:66-68) → page = a file in ~/.claude/autonomy/pages/ **that nothing reads**.
  - cc-board: renders the P8 registry×telemetry join — manual eyeball only.
- **VERDICT: ESCAPES.** The memory's own claim "the now-live reaper is the backstop that reaps
  the stalled orphan tab" is **falsified by cc-classify:205** — the fail-safe makes a
  never-engaged session permanently ACTIVE. The only autonomous detector that notices
  (supervisor) emits a dead-letter.

### L-2 · registry-wrong + fired-never-engaged · session never registered
- **Setup**: session-register.sh's `register()` is killed by its own P8 hard timeout
  (session-register.sh:89-95, 3s; the ps ancestor-walk + 2 jq under machine load), or
  `$ITERM_SESSION_ID` is absent/non-UUID at spawn (:39-42 silent return). One-shot: there is
  **no re-register event mid-session** (registration happens only on SessionStart).
- **Signal state**: pid alive, transcript live, NO cc-registry row (or a stale dead-pid row).
- **Detector trace**: cc-classify `--all` iterates `cc-sessions --json` = registry rows only
  (cc-classify:301-316) → session **invisible to the entire classify/reap stack**. cc-notify
  name resolution fails (cc-notify:94-102, exit 3). Supervisor sees it only via telemetry
  (dead-letter pages). lead-reconciler would alarm registry×disk — **not deployed**.
- **VERDICT: ESCAPES.** Deregister-absence self-heals (cc-sessions sweep) but
  register-absence has no healer.

### L-3 · believed-idle-but-working (desk) · handoff-tell contamination → wrongful reap
- **Setup** (mechanically producible): a desk session (a) `Read`s a fire payload
  `/tmp/<slug>-resume.md` or runs `handoff-fire.sh --recycle` **for another session** via Bash,
  (b) sits in a CLEAN, landed cwd shared with ≥1 other live session (old+new desk co-located;
  any sibling), (c) goes quiet ≥600s awaiting pings.
- **Detector trace**:
  - `handoff_fired` (cc-classify:86-91) greps the last-80 records' `.input.command //
    .input.file_path` for `handoff-fire\.sh|--recycle|[a-z0-9_-]+-resume\.md` → **matches
    third-party fires and mere Reads of resume payloads** — nothing scopes the tell to
    "I handed MYSELF off".
  - `find_successor` (:93-104): any DISTINCT live session in the same cwd qualifies. The
    time gate is **vacuous**: registry `startedAt` is epoch-**milliseconds**
    (session-register.sh:69 `$(date +%s) * 1000`) compared `>= $since` where since = last
    assistant ts in **seconds** (cc-classify:99-102, call :217) — ms ≥ s is always true, so
    even a sibling started long BEFORE the "handoff" counts as successor.
  - → `CAUSE=handed-off-lead`, landed=yes → cc-reaper passes all gates (:101-124) →
    cc-teardown: clean ✓, done-evidence text supplied by the reaper itself ✓, tty-exclusive ✓
    (only claude tree + shell on the pane) → **pane torn down**.
- **VERDICT: ESCAPES → false-reap of a live waiting desk.** Two predicate gaps (tell
  over-match + successor=any-co-cwd) and one unit bug (ms/s) line up.

### L-4 · believed-working-but-idle / believed-idle-but-working · team liveness via ps-grep
- **Setup**: lead idle with a spawned team. Historical: the 13h dead-partner wave-2 lead.
- **Detector trace**: `team_live_member` (cc-classify:147-158) greps `ps -eo command` for
  `--agent-name <member>`. Pane/tmux teammates → CAUGHT: live member ⇒ `owned-wait`
  (:237-239, never-reap — the healthy owned-wait memory encoded); none alive ⇒
  `coordination-hang` surface (:249) or `coordination-abandoned` reap past 7200s with a live
  co-cwd owner (:246-248, Gap-A fix).
- **Residual**: members that run **without a `--agent-name` process** (in-process/SDK
  background execution — the same backendType the config records for the lead placeholder)
  are invisible to the ps-grep → a live building wave reads "no live member" →
  coordination-hang, and past 7200s + co-cwd sibling → **reap of a mid-build lead**.
- **VERDICT: CAUGHT for process-teammates (cc-classify:239); ESCAPES for any in-process
  member (positive-liveness predicate = ps command-line only).**

### L-5 · registry-wrong · pane-name fronts a different session after in-place recycle
- **Setup** (real incident 2026-07-16, memory `cc-notify-session-pane-mapping.md`): in-place
  /handoff keeps the pane; friendly name embeds the pane UUID; sessionId behind it changes.
  Desk nudged the hung fix-w6 teammate 3× believing it was the successor.
- **Detector trace**: cc-classify is immune (keys on session_id + last-ASSISTANT-ts,
  cc-classify:63-68 — the encoded fix). But cc-notify resolves **name → registry row →
  paneUUID only** (cc-notify:82-91); no sessionId-addressed mode exists, so every desk-side
  monitor or relay that addresses by name inherits pane≠session drift during/after recycles.
- **VERDICT: CAUGHT at classifier; ESCAPES at the addressing layer** (mis-target, not
  mis-classify).

### L-6 · believed-working-but-idle · rate-limited session parked past its reset
- **Setup**: 5h/weekly cap hits mid-task; structured `isApiErrorMessage` in tail.
- **Detector trace**: cc-classify:198 `rate-limited` NEVER-reap — CAUGHT as a hold. But the
  error is the transcript's last record forever (session takes no further turns), so the
  classification is **absorbing**: nothing transitions it to re-engage at reset. The reset
  time is literally in the matched text (`resets` — cc-classify:77) and is never extracted.
  limit-recover is a manual/desk skill.
- **VERDICT: correctly not-reaped; autonomous re-engagement ESCAPES** (no wake-at-reset
  consumer; a 24/7 fleet loses the account's whole window if the desk misses it).

### L-7 · mutual standoff · completion-push → dead pane; nothing retries (the Q4 chain)
- **Setup**: desk fires worker with a completion-push exit recipe; desk later recycles via
  the DEFAULT split-right /handoff (successor = NEW pane uuid; old pane closed).
- **Trace**: worker finishes → completion-push.sh:73-74 → cc-announce role `operator` →
  resolve_role reads ~/.claude/cc-roles/operator (cc-announce:77-84) — **no writer exists in
  the repo** (one-time manual C10 binding; nothing rebinds on desk recycle) → stale uuid →
  cc-notify: it2 send fails → "mailbox only", **exit 0** (cc-notify:133-137) → classify
  MAILBOX (cc-announce:96) → one retry → `write_alarm` + exit 5 (:120-125) →
  completion-push records `push-failed`, exit 5 (completion-push.sh:80-82). "LOUD" lands in:
  the dying worker's own stderr + two dirs (**cc-announce-alarms/, completion-push/**) that
  **nothing consumes**. The mailbox line sits in `mailbox/<OLD-uuid>.md`; the successor
  desk's cc-await-ping watches `<NEW-uuid>.md` (cc-await-ping:44) → never fires → exit 2 at
  1800s with zero payload. exit-deadline.sh only tightens WHEN the wait times out
  (3600→900); it cannot make the signal arrive.
- **VERDICT: ESCAPES end-to-end.** Worker: done+self-retired. Desk: still waiting. Every
  "never silent" layer fired exactly as designed — into write-only dirs.

### L-8 · believed-armed-but-inert · waiting-recycle disabled by a foreign untracked file
- **Setup**: desk armed in the shared checkout. The repo root **currently** carries untracked
  `usage/` (this session's git snapshot: `?? usage/`).
- **Trace**: fire-predicate 5a (waiting-recycle.sh:190-192) requires `status --porcelain`
  empty — untracked counts → `abstain dirty-tree-hold` on EVERY PostToolUse, forever. The
  desk crosses 55/70/85% accumulating watch noise. boundary-handoff can't reach it (Stop-only,
  B-1 declared at boundary-handoff.sh:7 — a polling desk never Stops); the supervisor's
  PAST-THRESHOLD page at 73% (lead-supervisor.sh:148-151) is a dead-letter (L-1). Second
  inertness path: the GENUINE carve-out (:195-196) matches the desk's own standard readouts
  ("push … your call", "won't push") → `open-decision-hold` on the poll after every readout.
- **VERDICT: ESCAPES — the context-rot standoff the hook was built for (2026-07-17) recurs
  with the hook armed and green-pathed.**

### L-9 · believed-working-but-killed · TeammateIdle birth-reap; reap-guard never activated
- **Setup**: just-born teammate ends its FIRST turn (read brief / asked clarification); tree
  clean; no `.teammate-busy` yet.
- **Trace**: hooks/teammate-auto-shutdown.sh: busy-marker absent (:319-322), tree clean
  (:333 defer skipped) → shutdown `{"continue": false}` (:352+). reap-guard.sh R-a birth-grace
  and R-b products-since-spawn (reap-guard.sh:79-99) exist precisely for this and RED-prove in
  selftest — but the live hook **never calls the module** (activation step never landed).
- **VERDICT: ESCAPES — the original incident's fix is shelf-ware; the bare-idleness
  heuristic is still the live predicate.**

### L-10 · believed-closed-but-orphaned · squash-land ⇒ permanent DEFER loop
- **Setup**: teammate/lead work lands on trunk via squash or cherry-pick (different sha);
  worktree HEAD stays N commits "ahead" though the content landed.
- **Trace**: landed = `rev-list --count origin/main..HEAD == 0` (cc-classify:119-125,170-177;
  re-checked cc-reaper:49-56) — a COUNT check, never CONTENT. → `finished-teammate`/`finished`
  with landed=no → cc-reaper:104-105 `DEFER` **every 300s forever**. Pane + worktree linger.
  The repo's own landing-safety memory ("verify by CONTENT `git ls-tree`, never by count",
  incident dfacccd) already names this exact trap — the reaper uses count.
- **VERDICT: ESCAPES cc-reaper (absorbing defer). team-orphan-reaper may eventually collect
  the worktree; the SESSION/pane has no collector.**

### L-11 · registry-wrong · the drift windows that persist
- (a) In-place recycle gap: between predecessor exit and successor SessionStart, the pane row
  holds a dead pid → cc-sessions filters it (cc-sessions:89-90) → name unresolvable for the
  window; pushes degrade to mailbox-only exit 0. **Transient, self-heals** on successor
  register (session-register.sh:74-81 overwrite).
- (b) Successor's register times out (P8 kill) → the pane's row stays a dead-pid forensics
  row; the LIVE successor is unregistered until its next SessionStart — which already
  happened. **Persists forever** (= L-2 state; no periodic re-assert exists).
- (c) iTerm2 restart: all rows go dead; re-register on resume. Self-heals.
- **VERDICT: (a)/(c) CAUGHT by design; (b) ESCAPES.**

### L-12 · believed-idle-but-working · recycle-race: /exit into a recovered lead
- **Setup** (fired twice 2026-07-16, memories `desk-monitor-fixed-head-ref.md`,
  `desk-wave-monitor-lead-idle-is-owned-wait.md`): desk monitor false-stalls (BASE=HEAD
  recompute; nudge-latency 6-8min > desk escalation timeout) → fires `handoff-fire --recycle`
  at a lead that is recovering.
- **Trace**: recycle_fire (handoff-fire.sh:969-1011) arms the watcher then types `/exit`
  FOREGROUND — `/exit` **interrupts an in-flight turn and kills it with no output persisted**
  (:984-986, E2E-observed). There is **no pre-fire freshness read** in recycle_fire (no
  last-assistant-ts check, no in-flight-tool check); the only guard is desk discipline
  encoded in memory ("wait ≥12min", "kill the watcher if HEAD moves").
- **VERDICT: ESCAPES mechanically — the actuator trusts the caller's stall verdict; both
  documented near-misses were saved by operator vigilance, not by any predicate.**

### L-13 · believed-idle-but-working · long silent tool call in a clean solo cwd ⇒ reap-eligible
- **Setup** (producible): a solo session runs one long-running Bash tool call (12-min test
  suite / build) in a clean, landed checkout. During the call the transcript's last
  `assistant` record is the tool_use message — timestamped at call START.
- **Trace**: IDLE grows past 300 mid-call (cc-classify:63-68 keys on assistant records only;
  tool_result records are type=user and excluded) → not rate-limited, not worktree, no team
  → landed=yes → **cc-classify:255-256 `finished` at IDLE≥300**; reaper acts at IDLE≥600
  (cc-reaper:107) → cc-teardown: clean ✓; tty-exclusivity counts only FOREIGN procs — the
  running build is a descendant of the target claude tree → passes (cc-teardown tty_foreign)
  → `/exit` kills the in-flight turn.
- **Today's fleet is accidentally shielded** (dirty shared checkout / unlanded branches → 0
  candidates in the live log), not protected by any predicate.
- **VERDICT: ESCAPES — "idle" is defined as no-new-assistant-record, which is false during
  any single long tool call. No detector reads in-flight tool state.**

### L-14 · believed-working-but-dead (wave-wide) · spend-cap kills subagents; lead is stunned
- **Setup** (EMPIRICAL — this very wave, 2026-07-18T10:41Z): a MONTHLY spend cap killed 4
  subagents mid-task; the lead/desk received SOME failure notifications only ~11h later when
  the human returned and the cap lifted. (This worker's own report-write Bash call died with
  "claude-opus-4-8 temporarily unavailable" — even the safety classifier path was down.)
- **Signal state**: subagent turns die with a spend-limit error; the lead session is ALSO
  capped — it cannot take the turn that would process the harness's task-failure
  notifications, so they queue invisibly. Lead JSONL frozen; pid alive.
- **Detector trace**:
  - cc-classify on the lead: structured cap error in tail → `rate-limited` (:198) — or, if
    the error record predates 60 tail lines / the cap error text differs (a MONTHLY spend cap
    is a billing error, not the grepped "session limit|weekly limit|usage limit|limit ·|resets"
    set — **cc-classify:77 may not match it at all**) → falls through to idle causes: lead of
    a team with no live `--agent-name` members (subagents are in-process → invisible per L-4)
    → `coordination-hang`, or solo → `owned-wait`. Either way never-reap: survives, correct.
  - But NOTHING pages the operator: supervisor STALL?/ESCALATED pages are dead-letter
    (CC_PAGE_TO=""); the 4 dead subagents produce no death records (lead-deathwatch not
    deployed; subagents aren't registered pids anywhere); completion-push never fires (the
    workers died before their exit recipes).
  - The notifications themselves are **in-session state** — exactly the declared S-3
    structural blindness (lead-supervisor.sh:11-14): no out-of-session detector can see a
    queued-but-unprocessed failure notification.
- **VERDICT: ESCAPES — an entire wave dies and the system's first observer is the returning
  human, 11h later.** Notification delivery to a limit-stunned lead is a liveness blindspot
  of its own class: the wake channel and the thing it must wake share the same failure domain
  (the API budget). Only an API-independent observer (launchd sweep reading transcript-tail
  cap errors across ALL sessions + an OS-level page: osascript notification / push-critical)
  breaks the shared-fate coupling. Also: extend cc-classify:77's cap-grep to the monthly
  spend/billing error text, else a spend-capped session is not even `rate-limited`.

## 2. Standoff taxonomy (mutual-wait deadlocks) + minimal break protocol

| # | Deadlock | Members | Break protocol (minimal) |
|---|---|---|---|
| SO-1 | ping-to-dead-pane (L-7) | worker pushed to old desk uuid; desk awaits new-uuid mailbox | **Role-addressed mailbox**: cc-roles/<role> kept CURRENT — handoff-fire writes the role file at every fire/recycle (1 line at fire time); cc-await-ping gains `--role` (follow the role file each poll). Kills the whole class. |
| SO-2 | rate-limit park (L-6) | session waits for reset+prompt; desk waits for ping | classifier already parses the cap text — extract reset ts into a `wake-at` record; reaper sweep (already 300s launchd) cc-notifies the pane after reset. |
| SO-3 | never-engaged orphan (L-1/L-2) | session waits at composer for a prompt that mislanded; desk believes "fired" | **Engagement verify in handoff-fire**: after spawn, poll ≤120s for transcript-birth (a first assistant record for the new sid / registry row with sid) → on miss, re-send the prompt (`it2 session run`) once, then FAIL LOUD. The fire already holds prompt text + pane id. |
| SO-4 | context-rot standoff (L-8) | desk needs recycle; hook holds on dirt the desk doesn't own; no out-of-band path reaches a non-Stopping session | scope the clean-tree check to desk-owned paths (arm-time `status` snapshot; hold only on DELTA), and drop readout phrases from the GENUINE regex (or gate on `?` in the last message). |
| SO-5 | page-to-nobody (supervisor/announce/completion layer-wide) | supervisor+announce detect and write; no consumer exists; desk polls none of the dirs | ONE pull-based sweep: the desk watch loop (or a 300s launchd tick) reads `autonomy/pages/`, `cc-announce-alarms/`, `completion-push/` and cc-notifies the desk **role**. Also set CC_PAGE_TO (via role indirection) in the supervisor plist. |
| SO-6 | shared-fate stun (L-14) | lead waits on subagent results; subagents dead of the SAME cap that stuns the lead; harness notifications queue behind a turn the lead cannot take; human is the only exit | an **API-budget-independent** observer: launchd sweep greps transcript tails for cap/billing errors fleet-wide → OS-level page (osascript/push-critical, no model turn needed) + a wake-at-reset re-engage. The wake path must not share the failure domain it watches. |

The user's named "idle session standoff" is SO-1+SO-5 compounded: every layer built to make
completion loud writes durable evidence into locations whose consumer was never built, while
the addressing layer (pane-uuid-frozen-at-fire-time) guarantees the one push that could wake
the desk targets yesterday's pane. SO-6 is the same shape one level up: the notification
channel itself runs on the resource whose exhaustion it would need to report.

## 3. Detector-blindspot summary — signals NO current detector reads, ranked

| Rank | Unread signal | Scenarios it catches |
|---|---|---|
| 1 | **Engagement/transcript-birth deadline after a fire** (first assistant record for the fired sid within T+120s; distinguishes long-first-turn = transcript appending, from never-engaged = no record) | L-1, L-2, SO-3 (+ falsifies the "reaper backstops orphan tabs" belief) |
| 2 | **In-flight tool-call state** (unmatched trailing tool_use in the JSONL, or CPU of the claude child tree) — "idle" must mean no-assistant-record AND no-tool-running | L-13, L-12 (pre-fire gate), de-noises supervisor STALL? |
| 3 | **The write-only dirs as inputs** (autonomy/pages, cc-announce-alarms, completion-push records + role-file staleness check) | L-7, SO-5, L-6, all supervisor findings |
| 4 | **API-independent cap/billing-error sweep + OS-level page** (fleet-wide transcript-tail grep incl. MONTHLY spend text missing from cc-classify:77; wake path outside the API failure domain) | L-14, SO-6, L-6 |
| 5 | **Landed-by-content** (`git cherry`/patch-id vs trunk, or ls-tree content check) instead of rev-list count | L-10 + every squash-land false-DEFER |
| 6 | **sessionId-keyed addressing** in cc-notify (resolve `--sid <id>` → current pane via registry) | L-5, L-11 mis-nudges |
| 7 | **Self-scoped handoff tell + real successor time-gate** (fix the ms/s unit bug: compare `startedAt/1000 >= lat`; require the handoff invocation to target SELF) | L-3 |

Cheapest structural fix overall: #3 + role indirection (SO-1/SO-5) — one consumer loop + one
role-file write in handoff-fire converts five dead-letter paths into wakes without touching
any classifier predicate. Highest-severity predicate fixes: #2 (stops a mechanical wrongful
reap of a working session) and #7 (stops a desk-reap). #4 is the only fix that survives the
failure mode that killed this very wave.
