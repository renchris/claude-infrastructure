# A17 — HOSTILE REVIEW: the orchestrator desk STRANDS within 24h unattended

Verdict: **the desk strands tonight with high confidence — and in fact it already did, mid-review.**
At 2026-07-18T10:41Z the monthly spend cap killed 4 agents (this reviewer among them), ALSO took
down the auto-mode permission classifier ("claude-opus-4-8[1m] is temporarily unavailable, so auto
mode cannot determine the safety of Bash" — verbatim, this session's own failed tool call), and the
desk sat stunned ~11h until the human returned. That is the thesis, empirically sealed: the stack is
a lattice of detectors whose every terminal branch is "page a human," pointed at a human who is
absent by design. Second live proof: the supervisor's last pre-strand heartbeat read
`swept=116 findings=93` (`~/.claude/autonomy/idl.jsonl`, 10:36:50Z) with dozens of unread `.page`
files in `~/.claude/autonomy/pages/` — `com.claude.lead-supervisor.plist` sets `CC_PAGE_TO` to the
**empty string**, so `lead-supervisor.sh:66` has never delivered a page anywhere.

Method note: every claim below was read from code or live state this session. Speculative items are
quarantined at the end (3 max, per brief).

---

## 1. Strand scenarios (ranked by probability × blast radius)

Legend: FM1 = premature-done/purpose-loss · FM2 = idle-standoff · 24x7 = pure-mechanical strand.

### S-0 · Monthly spend cap: billing-plane kill + permission-classifier outage → 11h stunned desk — 24x7 (EMPIRICAL, 2026-07-18T10:41Z)
- **Trigger:** the monthly spend limit — a BILLING-plane event above all 4 accounts' quota planes —
  fires mid-wave. Observed: 4 agents killed at once; surviving sessions' Bash calls denied because
  the cap also starved the auto-mode permission classifier (same model pool).
- **Stuck state:** a NEW degradation mode no subsystem models: **stunned** — pid alive, reads work,
  every actuator denied. The desk could see everything and do nothing for ~11h.
- **Why no asset recovers it (each checked):**
  - `cc-classify:74-77` greps the transcript tail for `session limit|weekly limit|usage limit|limit ·|resets`
    — the classifier-outage text ("temporarily unavailable… cannot determine the safety") matches
    NONE of it → not `rate-limited`; idle grows on a dirty tree → `owned-wait` (cc-classify:271)
    → never-reap AND never re-engaged. Correctly cautious, uselessly inert, for 11 hours.
  - `claude-accounts`' data model has no monthly-spend field at all (rows carry `session_pct`,
    `weekly_pct`, `fable_pct` only — claude-accounts:362-368); `--rank` would cheerfully route new
    fires onto "healthy" accounts that cannot execute a turn. `cc-route`'s QUOTA CLIFF (cc-route:147-151)
    never trips because the quota data it reads says headroom everywhere.
  - `/limit-recover` is the designated recovery for exactly this class — and it is (a) invoked by a
    live session, (b) **Bash-mediated, so classifier-down means the recovery tool is un-invokable**,
    (c) built for cross-ACCOUNT transplant, useless against a cap that spans the billing plane.
  - `lead-supervisor` kept sweeping (launchd is outside the classifier) and paging DEAD/STALL into
    `CC_PAGE_TO=""`. `cc-reaper` kept running and correctly reaped nothing.
  - Nothing anywhere schedules a retry-at-reset or wakes a stunned session: recovery ended when
    **the human walked in** — the empirical refutation of 24/7-no-human.
- **Time-to-strand:** instant; duration = human absence (observed: ~11h). Blast: fleet-wide, plus
  in-flight subagent results nulled (this reviewer resumed only because context survived).

### S-1 · Desk self-recycle fails at the relaunch seam → decapitated fleet, nothing respawns a desk — 24x7
- **Trigger:** any `/handoff` → `handoff-fire.sh --recycle` where the detached watcher's relaunch
  doesn't take: it2 write fails twice, launcher errors, or claude never appears on the tty. Race
  base rate ~2/day observed (handoff-fire.sh:180-183 "Observed 2× 2026-07-13"; memory
  `cold-worktree-fire-autosubmit-race` 2026-07-17).
- **Stuck state:** `/exit` was already typed (recycle = EXIT + RELAUNCH, handoff-fire.sh:60-76) —
  the old desk is gone; the pane holds a bare shell. handoff-fire.sh:295-304: after one retype and
  90s the watcher's terminal act is typing **a shell comment for a human**: `"# HANDOFF RELAUNCH
  FAILED — run manually: …"`, then it exits.
- **Why no asset recovers it:**
  - `lead-supervisor.sh:136-137`: dead pid → checkpoint + `page DEAD` → `CC_PAGE_TO=""` (plist) →
    dead letter. **Ruling #1 (lead-supervisor.sh:4-8): "PAGES, never auto-recovers" — no respawn branch exists.**
  - `lead-deathwatch.sh:91` pages verbatim "**NOT respawned (ruling #1)**".
  - `bin/cc-respawn` is teammate-only: phases 2/4 are "lead/harness" acts (cc-respawn:10-15) — the
    dead thing IS the lead that would drive it.
  - `bin/cc-reaper` closes sessions; it creates nothing (cc-reaper:1-30).
  - Registry row pid dead → `cc-sessions:89` drops it from the live view; peers' completion pings ride
    cc-notify raw-UUID passthrough (cc-notify:88-91) → "mailbox only", **exit 0** (cc-notify:133-137)
    — every peer *believes it reported*.
- **Time-to-strand:** ~2 min from the recycle attempt. Blast: total orchestration halt; peers finish,
  self-retire (f137b1b default), nothing fires the next wave.

### S-2 · Auto-recycle silently disarmed TONIGHT (twice over) → desk rots to the context wall — FM1
- **Trigger:** nothing — current state. (a) `waiting-recycle.sh:132` requires an explicit `arm` per
  cwd; **no state dir exists** (`~/.claude*/state/waiting-recycle/` absent); live IDL streams
  `"reason":"not-armed"` abstains. (b) Even armed, predicate 5a (waiting-recycle.sh:190-191) aborts
  on ANY `git status --porcelain` output — the shared checkout carries standing dirt **`?? usage/`
  right now** ⇒ perpetual `dirty-tree-hold`.
- **Stuck state:** context climbs 55→73→90%; instruction-following decays exactly as the hook's own
  header predicts (waiting-recycle.sh:4-9); FM1 (dropped sweep duties, forgotten fired-session
  ledger) begins before any mechanical failure.
- **Why no asset recovers it:** `boundary-handoff.sh` is wired on the **primary account's Stop only**
  (settings sweep — absent from `.claude-secondary/settings.json`); the desk runs on secondary.
  `lead-supervisor.sh:148-150` B-1 page → `CC_PAGE_TO=""`. Advisory cap `CC_WR_MAX=3`
  (waiting-recycle.sh:66): even a healthy armed desk gets 3 nudges ever. Nothing else reaches an
  in-turn session.
- **Time-to-strand:** 6–12h of watch-noise. Blast: the desk becomes the *degraded operator* of every
  other scenario. Cruel pairing: the same `?? usage/` dirt currently makes the desk reaper-proof (S-3).

### S-3 · The launchd reaper executes the LIVE, quietly-waiting desk — 24x7 (reaper × wait-system seam)
- **Trigger:** desk goes tree-clean (a conscientious desk commits/cleans `usage/`), lands its work,
  then waits >10 min on fired peers without taking a turn.
- **Mechanics:** `cc-classify:252-257` — idle ≥300s + no team members + work landed ⇒ `finished`.
  Fired peers confer NO protection: classify's only wait evidence is `team_config` members
  (cc-classify:236-249); **it never reads `~/.claude/wait-contracts/`** — the L2 wait system and the
  classifier do not compose. `com.chrisren.cc-reaper.plist` runs `sweep --reap` every 300s; settle
  600s (cc-reaper:39) passes; cc-teardown's gate sees clean+landed ⇒ TEARDOWN. The self-guard is
  inert from launchd: `SELF_UUID` derives from `ITERM_SESSION_ID` (cc-teardown:57-58), which launchd
  lacks — and it guards the *invoker*, not the desk, anyway.
- **Why no asset recovers it:** same as S-1 — a dead desk has no respawner. The plist header
  celebrates the capability: "the desk loop … cannot reap the desk itself."
- **Time-to-strand:** first quiet 10-min boundary after the tree is clean. Blast total. FM2's
  mechanical amplifier: **the punishment for an idle-standoff is execution.**

### S-4 · Reaper reaps mid-recycle: classify-then-act race kills the successor — 24x7 (reaper × recycler)
- **Trigger:** cc-reaper's one-shot classification (cc-reaper:87) marks pane P reapable; between
  classify and the act (cc-reaper:124) P recycles in place — successor boots in the SAME pane and
  `session-register.sh:74-82` **overwrites the per-pane registry row** with the successor's pid/sid.
- **Mechanics:** cc-teardown re-resolves the PANE fresh (cc-teardown:149-158) and takes whatever pid
  the row now holds — **no session-identity pin spans classify-time to kill-time** (the lstart pin
  at :225 is taken after resolve — it pins the successor). Gate re-checks cwd (clean+landed seconds
  after a recycle — passes) and tty-exclusivity (successor's own tree — passes). Both legs verify;
  the log records a clean reap. The freshly-recycled desk dies <1 min after boot.
- **Why no asset recovers it:** the effect-verify *succeeded*; every record says success. Then S-1's
  non-respawn lattice applies.
- **Time-to-strand:** whichever 300s sweep brackets a recycle; the desk recycles several times/day —
  repeated dice rolls all night.

### S-5 · Correlated quota burn: the 90s rank cache routes a whole wave onto one account → mass rate-limit, no resume path — FM2/24x7
- **Trigger:** desk fires an N-session wave inside the `claude-accounts` shared-cache TTL
  (claude-accounts:41, "TTL 90s, flock single-flight"); every `--account auto` fire reads the same
  ranked winner → the wave burns one account's 5h window together (live cache: one account at 77% 5h).
- **Stuck state:** all wave sessions cap near-simultaneously. `cc-classify:197-198` labels them
  `rate-limited — NEVER reap` with the comment "**resumes on reset**" — false as a mechanism: a
  limit-stopped session sits at an error prompt; nothing re-prompts at reset.
- **Why no asset recovers it:** cc-route's cliff correctly STOPs and prints "run /limit-recover"
  (cc-route:149) — to the stderr of a script whose reader may itself be capped (the desk shares the
  account: recycle "defaults to THIS session's" account, handoff-fire.sh:74-75). `/limit-recover`
  needs a live un-capped driver. No launchd job or timer watches `resets_at` and re-prompts anyone.
  The never-reaped limited sessions hold panes/registry slots for hours.
- **Time-to-strand:** 1–3h into a heavy wave; self-heals only if a human-shaped ping arrives — the
  noticer is the desk (see S-2). S-0 is this scenario's billing-plane big brother.

### S-6 · iTerm2 python-API daemon hang: one dependency, every limb — 24x7 (substrate, time-correlated)
- **Trigger:** iTerm2 update/restart/API-daemon wedge, or the fixed-path stack breaking
  (`~/.claude/bin/it2` shim → `REAL_IT2=/Users/chrisren/Library/Python/3.11/bin/it2` +
  `/Library/Frameworks/.../python3.11`, it2-wrapper:24-25).
- **Correlated failure set:** (a) cc-notify composer injection fails → "mailbox only", **exit 0**
  (cc-notify:133-137) — the whole comms plane silently degrades to write-only files while every
  caller sees success; (b) handoff-fire splits fail-loud → no new spawns; (c) recycle: `/exit` typed
  via one control plane, relaunch via the other — a half-working surface **kills the desk and cannot
  restart it** (handoff-fire.sh:285); (d) cc-teardown `pane_present` → 2/indeterminate → FAIL 5
  (safe, no cleanup); (e) cc-sessions pane-sweep disabled (safe).
- **Why no asset recovers it:** nothing monitors the it2 daemon; every per-session recovery assumes
  pane transport; failure hits all sessions in the same second; exit codes read 0 throughout.
- **Time-to-strand:** instant on occurrence; probability/24h moderate-low, blast total.

### S-7 · The escalation lattice terminates nowhere (live-proven) — FM1/FM2/24x7 amplifier
- **Trigger:** already true. Every recovery mechanism's worst branch is a page:
  supervisor → `CC_PAGE_TO=""` (plist; **93 findings/30s sweep** composting unread);
  `cc-wait --on-timeout escalate` → `CC_WAIT_PAGE_TARGET:-$waiter` (cc-wait:152) — **escalates to the
  waiter itself**; `lead-reconciler` → `CC_RECON_PAGE_TARGET:-""` → `cc-notify ""` → exit 3 swallowed
  by `|| true` (lead-reconciler:46,107), and its `roster_tasks` is empty-by-default (:50-55);
  `notify.sh`/`push-critical.sh` → Pushover to the operator's phone (push-critical.sh:62); version
  watchers → macOS notification + `say` to an empty room.
- **Why it's a strand multiplier, not a bug:** each subsystem is individually correct ("detect,
  preserve, page"). Composed with an absent human, "handled (paged)" ≡ "dropped". Every S-n reaches
  its unrecoverable state THROUGH this lattice. S-0's 11h duration — ended only by the human's
  physical return — is this scenario measured.

### S-8 · Desk succession partitions the mailbox plane: stale pane-UUID waits — FM2
- **Trigger:** desk hands off via self-close (new pane, new UUID); live peers hold `--notify-back`
  trailers pointing at the OLD UUID.
- **Stuck state:** completions ride raw-UUID passthrough (cc-notify:88-91 — a full UUID always
  "resolves", live or not) → old pane unreachable → `~/.claude/mailbox/<old-uuid>.md`, exit 0.
  Successor baselines its OWN uuid's mailbox (cc-await-ping:39-47) → never sees them; waits ride to
  timeout; timeout pages the (old) waiter or escalates-to-self (S-7).
- **Why no asset recovers it:** no forwarding — nothing re-keys old-UUID mailboxes to a successor;
  countermanding every peer's trailer is a prompt-space duty performed by a rot-triggered model.
  Memory precedent: 3 misrouted nudges + a 30-min unrelayed decision (cc-notify-session-pane-mapping).
- **Time-to-strand:** first post-handoff completion; degrades the wave until it co-occurs with S-2.

### S-9 · Spawn-death is UNREAPABLE by design: the `active` fail-safe inverts — 24x7
- **Trigger:** a fired session boots claude but never engages (cold-fire auto-submit race, memory
  2026-07-17) or wedges at a permission prompt (PermissionRequest → Pushover → nobody).
- **Stuck state:** zero assistant turns → `last_assistant_ts` empty → IDLE=-1 → `cc-classify:205`
  **"cannot prove idle (fail-safe)" ⇒ `active` ⇒ NEVER reap — forever.** The worst spawn outcome is
  classified as the healthiest. If claude never booted (bare shell), session-register never ran → no
  registry row → invisible to classify/reaper/teardown alike (memory: cc-teardown REFUSE
  "unknown target" on 59664).
- **Why no asset recovers it:** the P8 registry retains the forensic row (cc-sessions:62-78) but the
  spawn-death DETECTOR is cc-board — a desk-read dashboard, i.e. prompt-space. handoff-fire prints
  "→ fired" and never verifies engagement. Wave stalls one slot short; desk waits on a ping that
  cannot come.
- **Time-to-strand:** immediate per occurrence; base rate ≥1/day per memory.

### S-10 · land-lock live-wedged holder freezes ALL landings machine-wide — FM2 (landing seam)
- **Trigger:** one session's gate+push hangs with its pid alive — hung network push,
  classifier-blocked push loop (S-0 makes this concrete), or a capped session mid-`/ship`.
- **Stuck state:** `land-lock.sh:69-70` — a LIVE holder is **never** reaped, TTL notwithstanding
  (deliberate, :57-59). Queuers poll to `WAIT_MAX=3600` then exit 75. Peers sit committed-unlanded:
  `work_landed`=no ⇒ `owned-wait` never-reap (correct) AND self-retire never fires (it triggers at
  completion; completion requires the land) ⇒ panes + quota accumulate fleet-wide.
- **Why no asset recovers it:** the escape (`LAND_SERIALIZE=off`) and holder-kill are operator
  judgment calls; `stranded-sweep.sh` is a hand-run detector ("REVIEW each", :84) wired to nothing.
  The mid-land stall class already stranded Stream B 35+ min WITH a live desk (memory §5).
- **Time-to-strand:** 1h to the first exit-75 wave; accumulates all night.

### S-11 · team-orphan-reaper's foreign identity key strips classify's team protection — 24x7 (reaper × reaper)
- **Trigger:** `team-orphan-reaper.sh:34-44` judges a lead dead by `~/.claude/watchdog/<sid>.pid` —
  "**no record — assume dead**" — a THIRD identity plane (vs cc-registry pid, vs teams glob). A live
  lead whose watchdog registration failed gets its team dir archived (:54) on the 600s launchd cadence.
- **Mechanics:** `cc-classify:136-145` derives `owned-wait`/`coordination-hang` (never-reap) from
  that config's presence; archived ⇒ the mid-wave lead re-classifies down the tree — landed+idle ⇒
  `finished` ⇒ S-3's machinery tears down a lead whose teammates still run. Also :98-106
  **auto-DENIES teammates' stale permission requests after 5 min** — unattended, every escalated
  permission becomes deny + "try alternative": a silent FM1 injector into workers. Scope mismatch:
  it watches only `~/.claude/teams` while classify globs `~/.claude*/teams` (cc-classify:40).
- **Why no asset recovers it:** the reconciler built for roster drift pages nowhere (S-7) and its
  tasks roster is empty-by-default.
- **Time-to-strand:** needs a watchdog miss coinciding with a landed-idle lead — lower probability;
  both reapers roll dice all night at 300/600s.

### S-12 · The behavioral floor: every hook is turn-driven; an idle desk is unpoliced — FM2
- **Trigger:** the desk stops taking turns (FM2, or `session-continue` cap 8 exhausts —
  session-continue.sh:68-74 — or anti-deference cap 3 exhausts — anti-deference:48,104).
- **Stuck state:** Stop/PostToolUse hooks fire only on activity; an idle session emits no events.
  The only external wake is cc-notify — whose senders are retired peers or a supervisor paging
  nowhere. Bonus corruption: session-continue's sentinel is keyed by **config-dir|cwd hash**
  (session-continue.sh:30-34), so a recycled successor in the same cwd *inherits the predecessor's
  armed sentinel* and gets its first stops blocked with a stale next-step composed by the rotted
  predecessor — purpose-corruption injected at birth.
- **Why no asset recovers it:** classify labels an unlanded-idle desk `owned-wait` (never-reap,
  correct) — and never-reap is the ONLY verb the stack knows for it. There is no re-engage actuator
  anywhere: reaper closes, supervisor pages, recycler advises the model that is the problem. S-0's
  11h stun is this scenario's empirical upper bound to date.
- **Time-to-strand:** whenever FM2 recurs — a named chronic failure for a reason.

### Speculative (explicitly ungrounded beyond config reads — max 3)
- **SP-1 caffeinate lapse → system sleep:** `pmset -g` shows sleep held off by 15 caffeinate
  processes, plausibly per-session children; a fleet-wide quiet (S-0/S-5) that exits them could
  re-enable sleep → launchd + panes freeze until a human. Assertion ownership unverified.
- **SP-2 overnight OAuth/keychain expiry:** account-relogin's browser-assisted path is agent-drivable
  but Dia-profile-dependent; a 03:00 token invalidation shrinks the pool with unattended recovery
  cost unknown.
- **SP-3 CC auto-update/version drift mid-fleet:** launchers pin builds (BIN=~/.claude-183/…,
  handoff-fire.sh:128) and watchers are notify-only, so low — but a launcher/zshrc repoint mid-night
  hits every FUTURE spawn while current sessions run the old build (split-brain fleet).

---

## 2. What a subsystem-by-subsystem inventory structurally cannot see

**D-1 · Identity-plane translation faults.** The stack runs on FOUR disjoint identity keys:
pane-UUID (registry rows, mailboxes, cc-teardown, cc-notify) · session_id (transcripts, telemetry,
classify join) · pid+lstart (supervisor, deathwatch, orphan-reaper watchdog) · cwd-hash
(session-continue sentinel, waiting-recycle arm/cooldown). Each subsystem is rigorous about ITS key;
the strands live at the translations: the pane that survives a recycle while the session behind it
changes (S-4: teardown kills by pane whatever pid the row now holds; the misrouted-nudge memory);
the cwd-keyed sentinel leaking a dead session's intent into its successor (S-12); the watchdog-pid
plane contradicting the registry-pid plane (S-11); the mailbox keyed to a pane that no longer means
"the desk" (S-8). An inventory audits each subsystem's own key discipline and passes it; only
reading two subsystems' resolvers side-by-side exposes that they disagree about what a "session"
is. Concrete pairs in this repo: cc-teardown:149-158 × session-register:74-82 (S-4);
session-continue.sh:30-34 × handoff-fire --recycle same-cwd succession (S-12);
team-orphan-reaper:36-38 × cc-classify:136-145 (S-11).

**D-2 · Terminal-escalation topology (where do all the leaves drain?).** Per-subsystem review
grades each failure branch "handled: pages the operator" — a passing grade twelve times over. The
graph view: every leaf drains to one root — cc-notify-to-a-human-surface — and that root is
provably disconnected (CC_PAGE_TO="" in the live plist; CC_WAIT_PAGE_TARGET defaulting to the waiter
itself, cc-wait:152; CC_RECON_PAGE_TARGET empty with the error swallowed, lead-reconciler:46;
Pushover/`say` to an absent human; 93 findings/sweep composting in ~/.claude/autonomy/pages). No
single subsystem is wrong; the TREE is rootless. The 2026-07-18 strand ended by the human's
physical return — the root, measured. Inventories don't draw the tree.

**D-3 · Recovery-under-degradation feedback loops (and the hidden classifier substrate).**
Inventories test each mechanism in a healthy harness; the desk's mechanisms run precisely when
their operator or substrate is degraded, and several turn hostile at that boundary: (a)
waiting-recycle fires BECAUSE the model is rotted, then trusts that rotted model to compose the
state-carrying handoff payload — recycle amplifies FM1 across generations; (b) the recycle
actuator's failure mode is not "recycle didn't happen" but "the desk was destroyed" (/exit lands,
relaunch doesn't — handoff-fire.sh:257-304); (c) cc-classify's fail-safe inverts under the worst
input: a never-engaged session is *permanently* `active` (cc-classify:205); (d) never-reap
discipline + launchd reaper compose into executing the correctly-cautious desk (S-3); (e) —
empirical, 2026-07-18 — **the permission classifier is a hidden substrate under every Bash-mediated
recovery tool**: when the spend cap starved it, cc-notify/limit-recover/handoff-fire all became
un-invokable BY the very sessions that needed them, while read-only tools kept working — a
"stunned" mode (alive, seeing, actuator-denied) that no classifier cause, telemetry field, or
supervisor state models. Each is invisible unless you run the mechanism against its own trigger
condition rather than against health.

---

## 3. Kill-chain walkthrough — the most probable strand
The single most probable is now a matter of record: **S-0 occurred during this review.** Timeline
reconstructed from live artifacts, then the top *prospective* chain (S-2→S-1) retained compressed.

### 3a. The empirical chain (2026-07-18, spend-cap stun — observed)
- **10:36:50Z** Supervisor heartbeat `swept=116 findings=93` (idl.jsonl) — escalation lattice
  already saturated and draining nowhere (S-7 baseline).
- **10:36:51-52Z** waiting-recycle abstains `not-armed` for live sids (idl.jsonl) — in-session
  recycle governance off (S-2 baseline).
- **~10:41Z** Monthly spend cap fires at the billing plane. Four agents die mid-task (this
  reviewer's report-write Bash call among the casualties). The auto-mode permission classifier
  loses its model: every Bash across surviving auto-mode sessions returns "cannot determine the
  safety … wait briefly and retry."
- **10:41–10:45** The desk retries per the error's own advice; each retry re-fails. Its transcript
  tail now holds tool-permission errors that match NO branch of `recent_api_limit`
  (cc-classify:74-77) → it will never classify `rate-limited`.
- **10:45–11:15** Desk exhausts in-context options: read-only tools still work, so it can SEE the
  dead agents and CANNOT actuate anything — cc-notify, handoff-fire, /limit-recover are all Bash.
  Anti-deference/session-continue fire on its stops (if armed) up to caps 3/8
  (anti-deference:48; session-continue:68) feeding it steps it cannot execute, then go silent.
- **11:15Z onward** Desk idles at the composer. cc-classify: pid alive, idle ≥300s, tree dirty
  (`?? usage/`) → `owned-wait` "never-reap default" (cc-classify:271). The reaper keeps correctly
  keeping it (cc-reaper:101-102 log stream). The supervisor pages STALL?/DEAD findings into
  `CC_PAGE_TO=""` every 30s (lead-supervisor.sh:61-68). Pushover pings a phone nobody answers.
- **11:15 → ~21:40Z** Steady state, ~11 hours: launchd jobs green, IDL heartbeats regular, pages
  accumulating, zero work. Every component reports itself healthy; the SYSTEM is stranded — the
  D-2 rootless tree, measured end to end.
- **~21:40Z** The human returns; caps lifted; sessions re-prompted by hand. **Recovery mechanism:
  homo sapiens. Nothing in `bin/`, `hooks/`, `scripts/`, or `launchd/` participated.**

### 3b. The top prospective chain (S-2 → S-1, compressed; fully grounded above)
Desk unarmed+dirty ⇒ no auto-recycle (waiting-recycle:132,190) → 6h of rot, supervisor B-1 pages
to "" (lead-supervisor:148) → rotted desk eventually recycles: `/exit` typed, watcher relaunch
races Ink boot (base rate 2/day, handoff-fire:180-183), 90s fallback types a comment for an absent
human (handoff-fire:303-304) → bare-shell pane; supervisor pages DEAD to "" (:136); deathwatch
pages "NOT respawned" (lead-deathwatch:91); cc-respawn needs a live lead (cc-respawn:10-15) →
peers ping the dead UUID, get exit-0 mailbox-only (cc-notify:133-137), self-retire (f137b1b) →
fleet drains itself tidily; stranded at ~T+5.5h, discovered at breakfast.

---

## Bottom line for the wave
The productive inventory will correctly certify ~every subsystem: gates fail closed, verifies are
effect-read, never-reap discipline is real, records are written. All true — and the system stranded
anyway, mid-review, for 11 hours. Because: (1) no component can CREATE a desk or RE-ENGAGE a
stunned one — the stack's only verbs are close, page, and refuse; (2) every terminal branch drains
to an absent human through a provably-disconnected page channel; (3) four identity planes shear at
every succession event; (4) the permission classifier is an unmodeled substrate under every
recovery tool. The single highest-leverage fix is not another gate: it is ONE launchd-side
**desk-existence + desk-engagement invariant** ("a registered desk session must exist AND have
taken an assistant turn in the last N minutes; else fire one from a canned brief / re-prompt the
stunned one") — the only asset class of which this repo has zero instances.
