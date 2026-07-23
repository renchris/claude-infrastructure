# Frontier-problem portfolio — claude-infrastructure (2026-07-23)

**Scope (frozen):** investigate the most complex problems in the application and architecture
requiring highest-frontier intelligence (Fable 5, max reasoning) to improve, fix, and solve —
including memory issues eliminated, context/time performance/efficiency, quality of detail in
session-to-session pass-through, clean-up/GC, 2-way communication visible to Terminal UI/User,
and eliminating silent failures with UI visibility + details captured in logs.

**Method:** 14-agent read-only research wave (12 evidence pools + 2 in-wave adversarial slots,
critic-gated decomposition; raw returns in `raw/`), synthesized on Fable 5 max against: the
**recovered** 2026-07-20 frontier-hard wave (13 reports + BRIEF theses T-A..T-G — rescued this
session from dangling checkpoint `38c6efb`, landed in `../frontier-hard-2026-07-20/`), the
desk-audit-2026-07-18, the infra-reliability-audit-2026-07-22 (~90 defects, 4 root causes), and
the session-crash-forensics-2026-07-23 (teardown-confound correction). This goal is a **re-issue**
of the identical 2026-07-20 operator mission whose synthesis stranded uncommitted — completing
that DoD is part of this deliverable.

**Echo discipline (per the in-wave hostile review):** this is the FOURTH multi-agent audit of this
system in 6 days; cross-audit convergence is partly shared-corpus echo. Every load-bearing claim
below was **re-verified live 2026-07-23** by this wave (not inherited), and four prior-audit
claims were found stale and are corrected here: dispatcher+discovery are now LOADED (not inert);
the 5 permission dirs have ZERO drift today (md5-identical); the desk CAN self-land (subprocess
allow-listing, 2026-07-20); pin-to-2.1.183 is WITHDRAWN (teardown-confound artifact).

---

## TL;DR — the ranked portfolio

The system's hardest problems are not component bugs. They are **nine structural gaps that
regenerate whole failure classes** faster than point-fixes retire instances. Three meta-findings
frame them: (1) **the monitor manufactured its own crisis** — tonight's "19 crashes" were 0 real,
and three generations of investigation were spawned by the monitoring layer's own false signal;
(2) **"landed" ≠ "live" ≠ "firing"** — the single largest generator converts finished fixes into
silent no-ops (the permission-autonomy layer is *fully built on main* and wired 0/5); (3) **the
knowledge the system trusts about itself rots in days** — three crash root-causes in three days,
two stale memory entries live-corrected by this wave; any mechanism that reads yesterday's
conclusion as today's state is already wrong.

| # | Problem | One-line | Leverage | First-move cost |
|---|---|---|---|---|
| FP-1 | Activation/deploy substrate | landed≠live≠wired silently disarms every fix whose effect lives in wiring/deploy — incl. the safety layer that can't self-wire | ~10+ named findings | LOW (script + assert) |
| FP-2 | Identity/attestation kernel | liveness/death/role inferred from forgeable proxies; no {id, generation, intent, heartbeat} contract | ≥12 named findings | MED (campaign) |
| FP-3 | Universal receipts | async ops report "sent/fired/done" with no checkable effect-predicate; sent≠delivered≠acted | ~8 named findings | LOW-MED (library) |
| FP-4 | Verify the verifiers | green tests/mock oracles/broken tamper-chain/unread heartbeats — the audit layer is unfalsifiable | trust in everything else | MED |
| FP-5 | The human plane | 82.9% of mail invisible to the operator; phone leg 133/133 inert; one loud oracle missing | operator's stated axis | LOW-MED (spec'd) |
| FP-6 | Succession ledger | pass-through fidelity is bimodal: rich hand-authored brief or bare scope; event-source it from residue | 59.3M tok/wk + crash-floor | MED |
| FP-7 | Economics closed loop | the recycle policy has NEVER fired (538/538 abstains); 4 controllers, no shared objective, wall-clock unread | 249K tok/turn base | MED |
| FP-8 | Retirement by construction | landing CREATES artifacts (147 backup branches); no unit-retired event; reapers enumerated not derived | 6+ unbounded stores | LOW-MED |
| FP-9 | Knowledge layer as tested artifact | rules/memory are untested, unversioned-in-effect, self-reinforcing; deletion has no budget | rot ceiling on all agents | MED |

**Ranking axis (confronting the in-wave hostile objection head-on):** fp-K argued the activation
gap is "real but triple-counted" and that marginal frontier value lies elsewhere. The table is
ordered by **leverage × activation-cost — it is a build order, not a difficulty order.** FP-1
stays first because it is the *precondition* for every fix whose effect lives in wiring, deploy,
or daemon memory (FP-2's landed-but-unwired teardown markers are the live exhibit) — but it is
mechanical, not frontier-hard. The **frontier-need core** — problems that genuinely require
top-tier reasoning — is FP-2, FP-4, and the five open holes (H-SEC-1, H-VER-1, H-ECON-1,
H-KNOW-1, H-RESTORE-1). FP-6/FP-8/FP-9 first-moves deploy through the normal repo path and are
NOT gated on FP-1.

**Anti-frontier verdicts** (explicitly NOT worth frontier effort — evidence says stop):
- **Crash/memory elimination as a project — CLOSED.** Tonight's 19 recorded crashes were 0 real;
  organic abnormal-end rate is 0.24% flat across CC 2.1.207/215 (0.00% on 183-era); the two
  flagship "60MB OOM crashers" **ended `end_turn`** (orderly — refuted at source by fp-B). The
  residue is: land the 3 built fix-branches (teardown-marker contract), cycle the supervisor
  (forensics step 3, still pending — ledger shows 0% `claude_version` populated), and wire
  eval-track stderr (one dotfile line). All routine.
- **Cache-TTL optimization — anti-frontier.** 97.24% cache-read; cold-reprocess is 0.11% of
  input-side (~98 events/wk). The cache-expiry nag targets a ~$0 problem (this session opened
  with that nag). Keepalive is justifiable only for UX latency, never tokens.
- **Quota placement — greedy is adequate** (T-F verdict). The real scheduler gap is FP-7's
  missing inputs, not the placement algorithm.
- **Worktree disk (94G)** — mostly reso/doc_classifier bytes with their own GC; claude-infra's
  accumulation is refs/rows/markers (FP-8), not gigabytes.

---

## Meta-findings (frame for everything below)

**M1 — The monitor was the malfunction.** The crash-signal chain (watchdog pidfile heuristic +
prose-grep classifier + claude.exe-only process count) manufactured 3 generations of crisis: 16
wave-completions + that wave's verifier + one unrelated orderly close paged as 18 crashes →
spawned an investigator → its own sanctioned self-close paged as the 19th → spawned the next
investigation. Monitoring that can misclassify sanctioned
behavior as failure **steers operator attention and multi-session compute** — signal integrity is
a first-class reliability surface, not cosmetics. (forensics Part 1; fp-B re-verified rows.)

**M2 — The strand is the specimen.** The 2026-07-20 run of THIS SAME GOAL produced 13/13
substantive reports and a drafted portfolio — and delivered none of it: reports lived only in a
dangling checkpoint ref, the synthesis died in transcripts, FRONTIER_HOLES was never updated.
Uncommitted work-product + no delivery receipt = the system's own research is subject to the same
stranded-output class it documents. (fp-A; recovered + landed this session.)

**M3 — Stale-knowledge velocity is high; verify-at-read-time is law.** Three crash theories in
three days; "dispatcher inert" and "permission-dir drift" both false by the time this wave read
them; mail corrections sent to my own agents were delivered only to those still running (turn-
boundary delivery race — the five finished agents never saw them). **Any consumer of a recorded
conclusion must re-verify the live state it asserts** — this is the effect-read law generalized
from files to knowledge. (fp-K discount list; fp-J/fp-M live corrections; this session's own mail
race.)

---

## FP-1 · The activation/deploy substrate — make "landed but not live" unrepresentable

**Problem.** The path repo→live is a hand-tended lattice: per-file symlinks (new tracked files
never auto-link), real-copy surfaces (skills/, ~/bin, ~/.claude/CLAUDE.md) with no parity assert,
hook *wiring* that exists only in live settings.json (un-versioned, un-diffable — a dropped hook
is indistinguishable from a healthy-dormant one), launchd plists authored-not-loaded, `.done`
markers that assert the past not the present (RunAtLoad=false jobs read "activated" while cold
after any reboot), and long-lived daemons holding pre-fix code in memory.

**Fresh evidence (this wave, live-verified).**
- The **entire permission-autonomy layer is built, landed, and wired 0/3-0/5**: cc-permission-beacon
  (producer never fires — `/tmp/cc-permission-pending` has never existed), reset-hard-shadow-allow,
  ship-rail-push-allow (staged, no `.done`), cc-unattended-ask-guard, smart-bash-allowlist (fp-M §d).
  The 133-minute permission-hang class stays open **because its finished fix is unwired**.
- The false 19-crash storm ran on an **undeployed** pidfile-reap + **stale in-memory watchdog
  daemons**; the crash ledger still shows 0% `claude_version` because the supervisor was never
  cycled (forensics step 3 — still pending as of this synthesis; fp-B §b).
- skills/ = 20 real-copy dirs, **no parity check at all** — a repo skill edit silently never
  deploys (fp-F §b). Hook wiring absent from every tracked settings file (fp-D §a).
- Activation can itself regress: the 07-20 reap-guard activation **chmod'd the reaper 100644 —
  disarmed it** (fp-A P2, still-open P0).
- The deploy-symlink reconciler has been **filed 4× and blocked 4×**; the backlog's `block` state
  is a one-way graveyard (the unblock-fix is itself blocked) (fp-C §c).

**Why default-tier keeps failing.** Each instance gets a point-assert (deploy-parity covers ~/bin
copies only; config-mirror covers some mirrors; abstain-alarm covers 5 hooks) — the CLASS persists
because live state is assembled by hand from four different mechanisms with no build step, and the
agent is (correctly) forbidden from self-wiring settings — so "the last mile" structurally belongs
to no one.

**Solution shape.** Treat repo→live as a **compiled, versioned, atomically-switched build** (T-G):
one manifest declares every live surface {path, mode: symlink|copy|settings-wiring|launchd,
source, wiring}; a builder materializes it; a **wiring-assert gate fails closed** on any tracked-
but-unlinked file, unwired hook, or loaded-job version drift; SessionStart asserts manifest-hash
== live-hash and pages on mismatch. The settings tier (the one agents must not touch) compiles to
**one idempotent operator-run activation script with a content-verified receipt** — the
silver-platter generalized from allow-rows to hook-arrays (fp-M F1 sketch).

**First move (LOW):** `link-live` reconciler + wiring-assert in the land flow (the RC1 sweep
already computes the diff); generate `activate-permission-layer.sh` (4 wirings × 5 dirs +
shadow-arms + Pushover env + receipt).
**Verification:** unlinked-tracked-file count == 0 as a land-gate; every `.done` marker paired
with a live-state probe (launchctl print / settings grep) that re-runs at SessionStart.
**Routing:** campaign candidate **C-DEPLOY-1** (FRONTIER_HOLES); quick-wins to backlog.

---

## FP-2 · The identity/attestation kernel — registered state with generation and intent

**Problem.** Every subsystem infers liveness/death/role/ownership from a proxy that survives
identity change or that a sanctioned actor can also produce: bare pids (`kill -0` — OS reuses
pids, watchdog daemons become immortal; 21 live now, oldest 8 days), pane UUIDs across in-place
recycles, transcript tails (self-close forges the mid-Bash "crash" signature), prose dispositions
(the classifier missed the very session that wrote it), role files pointing at dead panes
(cc-roles/desk → a pane absent from the 21 live sessions, **flooded live**: 423 pending, `.acked`
frozen 3 days), mtime/HEAD/name/count proxies (3 wrong causal claims in one day, twice-wrong crash
attribution).

**Fresh evidence.** fp-L: watchdog spawn is source-blind + unguarded (stacking; subagent arming =
73% of registrations); `session-end` cleanup races its own `/exit` SIGKILL (83 stale pidfiles
unchanged across a day); supervisor heartbeat has **no reader anywhere** ("absence is the alarm"
— with no alarm consumer); cc-reaper has no single-instance lock. fp-E: three separate
anti-entropy engines (cc-reconcile / cc-backlog reap / lead-reconciler — the last one INERT) exist
because there is no liveness SSOT; the claim ledger keys liveness to the *dispatcher's* pid, which
exits seconds after claiming (V1). fp-G: role indirection doesn't survive succession; 0 `.forward`
files have ever been written.

**Why default-tier keeps failing.** Each wrong-key incident gets a right-key patch (fixed-HEAD
refs, sessionId-only mapping, birth→turn engagement, teardown markers) — and the next monitor
picks a new proxy, because writing an authoritative record is nobody's contract. The supervisor
already uses generation checks; the watchdog beside it doesn't — same repo, same lesson,
un-adopted: **that is a missing kernel, not a missing lesson**.

**Solution shape** (extends C-DSH-1 with fp-L's scoping + SHEPHERD-NOTES' OWNER field): one
registered-state record per actor — `{id: sid|label, pid+starttime (generation), role, owner,
intent/teardown-marker, heartbeat, TTL}` — written **before acting** (write-before-act), consumed
by watchdog/reaper/supervisor/cc-notify/claims; **scoped to the non-launchd tier** (launchd
already owns labels/KeepAlive for its 15 jobs — do not re-register those); one reconciler retires
generation-mismatched daemons, repoints dead role-holders, and pages on heartbeat gaps
(version-stamped heartbeats catch alive-but-stale code — the class KeepAlive cannot see).
Invariant: **no monitor may infer death from a state a sanctioned actor can also produce** —
intent markers outrank inference (the teardown-marker contract, generalized).

**First move (MED):** land the 3 built crash-signal branches (teardown markers + watchdog marker
classification + mail mutexes); then the registry for watchdog-family daemons + the role-liveness
check in cc-notify (refuse/repair a role whose target shows no `.acked` advance).
**Verification:** duplicate-sid crash rows = 0; stale pidfiles trend to 0; `cc-roles/*` always
resolves to a live consumer or pages; N-daemons-per-sid == 1.
**Routing:** **C-RSF-1** campaign (registered-state family — already named in memory; this is its
charter), superseding-and-extending C-DSH-1.

---

## FP-3 · Universal receipts — no async operation without a checkable effect-predicate

**Problem.** Operations report success at the *send* step, not the *effect* step. Live specimens
from this very session: 6 lead→agent corrections returned "sent to inbox" — **none reached the
five agents that finished first** (turn-boundary delivery race), and only running agents got them;
the predecessor wave's "engagement confirmed (birth)" fired a session that never engaged.

**Fresh evidence.** fp-E's receipt table: true receipts exist for exactly three ops — teardown
(re-observes process AND pane; exit 5 = acted-but-survived), land (self-attesting log + per-path
content-verify), completion-push (capture-before-notify + LOUD unverified state). fire/dispatch/
page are partial: engagement-verify is **entirely OFF for --recycle** (the desk's hottest path,
fp-I FP-3); dispatch trusts fire's exit while a fired-but-idle worker holds a live claim; a page's
device-delivery is unproven unless a manual probe runs (Pushover inert anyway); mail has **no
read-receipt in either direction** — nothing tells a sender `.acked` advanced (82.9% unacked).

**Why default-tier keeps failing.** Each op invented its own proof shape in its own directory;
new ops default to no-receipt (the race to ship). Point-fixing one op (engagement birth→turn)
leaves every other op's proxy in place.

**Solution shape.** A receipt **library + discipline**: every mutating/async op appends
`receipt{op, target, predicate, check_cmd, deadline, sid}` to one store; a single generic
verifier (launchd tick) executes overdue `check_cmd`s → refire/escalate/page; senders can await
receipts (`cc-await-ping` generalized). The teardown-marker contract is the seed instance; fp-I's
detached engagement receipt-watcher (brief-hash marker + deadline + N-retry, re-fire into a
fresh warm pane, extended to --recycle) is the second.
**First move (LOW-MED):** the engagement receipt-watcher (retires fired-never-engaged wholesale);
mail read-receipts (`.acked` delta notification back to sender's inbox).
**Verification:** fires with no matching engagement receipt = 0/wk; sender-side "unconfirmed
sends older than deadline" = a queryable number that trends to 0.
**Routing:** design+build under C-RSF-1 (receipts are the kernel's verbs); backlog for the two
first-moves.

---

## FP-4 · Verify the verifiers — the audit layer must be falsifiable from outside

**Problem.** The layers that vouch for the system cannot currently be caught lying:
- **64/105 bats tests are mock-based; 5 assert live-binary emission** — gates test capability,
  not wiring; they stayed green through three audits while live backstops were dead-letters (fp-K #1).
- The **IDL tamper-evidence chain is decorative**: `cc-idl verify` reports TAMPER permanently
  (rotation truncates what the chain sealed; no auto-seal caller; 7 hot-path writers bypass the
  sealing mutex) (fp-F c#1, fp-L c-3).
- A **torn line in idl.jsonl flips the auditor GREEN** ("no records" reads as healthy) — inverted
  blast radius (fp-D FP-3).
- Supervisor heartbeats have **no reader**; pages carry **no type** (ts-only files; 20,129
  supervisor.log lines contain zero typed findings) — so the permission-stall rate is
  **unmeasurable by construction** (fp-M F2).
- The **fire-ratio census covers 5 hooks** (abstain-alarm); the general "mechanism inert by
  construction" detector doesn't exist — the 1,309-abstains-0-fires incident class recurs (fp-C FP-2).

**Why default-tier keeps failing.** Self-reference: you cannot test the test with another test of
the same kind, and every new guard deepens the trusted-but-unverified layer (fp-K: "the
investigation cannot verify itself with the instruments it trusts").

**Solution shape.** (a) **Live-wiring attestation**: every gate/hook/daemon must emit a runtime
"I ran against live state" record (event, version, wall-clock) to one flock'd appender; a census
alarms on `abstained==100% over N` **or `invocations==0 over T`** across ALL mechanisms —
self-registering, not enumerated. (b) **Typed durable findings**: pages/stalls/findings append
`{ts,sid,type,detail}` — make stall-rate an SLO-able metric. (c) **Oracle validity**: a tagged
live-emission test tier (fixture-from-producer's-literal-output law) + a per-CC-version
conformance canary (C-DSH-2: /exit queue semantics, SessionEnd-on-interrupt, hook-merge order —
the harness behaviors this system leans on). (d) Repair-or-retire the tamper chain
(rotation-as-epoch or delete `cc-idl seal` — a decorative security control is worse than none).
**First move (LOW):** the flock'd IDL appender + typed page records + `cc-idl verify` in nightly
with an honest verdict.
**Verification:** an induced dead-letter (unwire a test hook in a sandbox dir) must page within
one census cycle — the detector's own RED-proof.
**Routing:** hole **H-VER-1** (what CAN'T runtime self-attestation catch — panel-worthy);
first-moves to backlog.

---

## FP-5 · The human plane — one loud oracle; everything else quiet, typed, and receipted

**Problem (the operator's "2-way communication visible to Terminal UI / User").** Inbound TO the
operator: 82.9% of cross-session mail is unacked (1,899/2,291 — *worse* than the 78% at v3 design
time); mailbox-drain emits `additionalContext` only (model-eyes; no `systemMessage`); the
statusline has no 📬; 227 undelivered-mail alarms sit in a dir nothing reads; the phone leg has
**never delivered once** (133/133 records "inert — creds unset") and nothing surfaces that the
last-resort channel is itself down; supervisor findings page a **dead** desk role. Outbound FROM
the operator: typing into a running pane works but has no receipt, doesn't trigger a drain, and a
`/goal`-headed long message is silently rejected; steering an *unattended* session has no
receipted path. Permission halts: ~80 prompts/day, all ephemeral local banners; unattended stalls
are invisible for ≤30 min, then surface as an untyped `STALL?`.

**Why default-tier keeps failing.** The one proven human-push channel (Stop-hook `systemMessage`)
is used by exactly one renderer (operator-readout), and each new alert class grew its own
file-store + page path instead (≥8 operator read-surfaces and counting — fp-N FP-3); harness
floor: only the model can arm its own wake, and nothing makes arming an invariant.

**Solution shape.** Collapse to **one gated oracle**: a single "does anything need me?" surface
(cc-blockers generalized) that (a) joins mail-unacked + typed stalls + pages + receipts-overdue +
activation-pending, (b) renders via the readout `systemMessage` + a statusline badge — and
**suppresses every other surface when it reads clean**; every channel gets delivery receipts
(FP-3) and a fail-loud when the channel itself is inert (the Pushover lesson: an escalation path
must page through a *different* path when it can't deliver). Wake-arming becomes an invariant:
every owned wait arms `cc-await-ping` (0 armed watchers across 21 live sessions today), enforced
by the census (FP-4b).
**First move (LOW-MED):** D11 `systemMessage` on drain + statusline 📬 + typed stall ledger +
repoint the desk role with liveness-checked resolution; Pushover creds = operator env (staged).
**Verification:** unacked% trending down and *rendered*; "channel-down" pages fire in a drill;
zero surfaces to read when the oracle is green.
**Routing:** mail-v3 P3/P4 unblocked as backlog; role-liveness under C-RSF-1.

---

## FP-6 · The succession ledger — event-source pass-through from residue, not diligence

**Problem (the operator's "quality of detail in session-to-session pass-through").** Fidelity is
**bimodal**: a disciplined model hand-authors a rich brief (both measured chains crossed decisions
and anti-patterns intact) — or the floor is `Scope (frozen)` alone (crash/auto-compact: the brief
doesn't exist). State classes with NO mechanical carrier: decisions+why, rejected-hypotheses,
in-flight verification state, watch-obligations (armed watchers die with the session), the peer
map, operator-pending items, and the predecessor's **touched-file map** — the measured #1
re-derivation cost (17 calls / 3m45s before first edit in chain 1). The DoD file accumulates
scopes (7 injected as all-"binding"; consumers count checkboxes that never exist → the REMAINDER
rung is structurally dead). System-wide: **38% of sessions are fresh-context successors**, median
237K re-cache tokens + 619 s to first productive action ≈ **59.3M tokens/week of re-orientation
LOAD** (honest label: the population includes fired teammates and research subagents — every
fresh-context start pays it — and the strictly-*redundant* fraction is unmeasured; recipe in fp-H).

**Why default-tier keeps failing.** Every fix adds another thing the model must *remember to
write* — under the exact conditions (rot, crash, hurry) where diligence is least available.

**Solution shape** (fp-I FP-1 + FP-4): materialize the ledger **from artifacts the session already
produced** — commits since fork, files Read/Edited (from transcript tool-calls), `Scope (grown)`
lines, armed watchers (process table), open decisions (cc-decide), claims held — auto-written at
PreCompact/recycle/fire into the DoD dir and re-injected at SessionStart beside the scope. Zero
per-turn bookkeeping. Mark scope supersession (newest ACTIVE, priors labeled superseded — keeps
INTEGRATE law, kills the 7-binding-scopes ambiguity). Extend the engagement receipt-watcher to
--recycle (FP-3).
**First move (MED):** the touched-file-map + commits section (pure transcript/git derivation);
DoD supersession marking.
**Verification:** successor time-to-first-edit and first-5-turn re-read volume drop on measured
chains; crash-floor drill carries decisions without a hand-authored brief.
**Routing:** backlog (design is concrete); measurement recipe already defined (fp-H pair-linking).

---

## FP-7 · The economics closed loop — one objective, measured outcomes

**Problem.** Four controllers (cache-expiry hooks / waiting-recycle / wave-plan+dispatch /
claude-accounts) optimize disjoint axes with no shared cost model. The recycle policy — the only
lever on the true cost base (249K cache-read tokens per assistant turn; 23.4B/wk) — has **never
fired** (538/538 abstains this window; 0/2419 historically) and its thresholds are validated by
nothing (outcomes unlogged). Wall-clock is entirely latent (nothing aggregates tool/gate/model
latency; ~50h/wk of model-wait extrapolated), so any token-optimal decision can be time-terrible.
Meanwhile the one instrumented signal (cache expiry) measures a 0.11% problem.

**Why default-tier keeps failing.** Un-falsifiable control policy: no outcome telemetry, no rot
proxy, no re-orientation cost on the ledger's other side — so thresholds can't be tuned, only
asserted (and the policy never fires, so no data accrues: a closed loop that was never closed).

**Solution shape.** (a) Shadow-fire outcome logging for waiting-recycle (log would-have-fired +
what happened next); (b) pair-link predecessor→successor and score re-work/decision-reversal as
the rot proxy; (c) `cc-timing` post-hoc aggregator over transcript timestamps (zero new
instrumentation) for tool/gate/wave wall-clock; (d) one objective — min(token-equiv + λ·wall-clock)
s.t. quota + monthly-cap-reset — consumed by recycle, routing, and wave placement. Context-utility
attribution (which cached segments a turn actually referenced) is the research-grade piece that
would let trimming be evidence-based.
**First move (LOW):** shadow-fire logging + `cc-timing`.
**Verification:** the first tuned threshold beats the asserted one on the rot-proxy metric; wave
placement stops routing to token-cheap/latency-slow accounts (measured).
**Routing:** backlog (a,c); hole **H-ECON-1** for context-utility attribution (genuinely open
research).

---

## FP-8 · Retirement by construction — a unit-retired event with fan-out

**Problem.** Cleanup is creation's inverse nowhere: landing *creates* a `ship/backup-*` branch
(147 now) and deletes nothing; 134 merged branches undeleted (63% of all branches are land-cruft);
`stranded-sweep` pays O(233 branches × `git cherry`) on every land; session-index.db is ADD-only
over a self-pruning corpus (5,323 rows, ~3,800 ghosts, 47MB, **read per statusline render**);
watchdog dir 2,193 files; pages/comms-alarms/push-records unbounded (only sweep-seen has GC). The
one *proven* degradation: the supervisor's find-walk hit 5 min vs a 30 s sweep interval and pinned
the disk (fixed by pruning the scan — the accumulation remains). Reaper coverage is **enumerated,
not derived**: every new writer is born uncovered.

**Why default-tier keeps failing.** Retirement is cross-cutting (branch+worktree+backup+DB rows+
registry+markers span stores owned by different scripts) and no join key ties a work unit's
artifacts together; each reaper keys on a proxy trigger (age/mtime/idle), never on "this unit is
semantically done."

**Solution shape.** A **retirement ledger**: stamp a `unit-id` at worktree/session birth
(session-register already hooks there); on land, emit one `unit-retired` event; ONE consumer fans
out: branch -d, worktree remove, backup-branch keep-last-N, DB anti-join row-delete + VACUUM,
marker sweep. Invert reaper coverage to **deny-by-default**: a manifest of write-paths (FP-1's
store manifest — same artifact) diffed against reaper target-lists in CI; any growing uncovered
path fails the lint. Pair with fp-N's **deletion budget** for the control layer itself (every new
hook/rule retires one, or carries a sunset + never-recurred auto-flag).
**First move (LOW):** post-land fan-out (branch/worktree/backup pruning) + session-index
reconcile+VACUUM — both mechanical.
**Verification:** branch count and DB row count become bounded functions of live work; the
reaper-coverage lint goes red when a test writer is added uncovered.
**Routing:** backlog (first moves); store-manifest shared with FP-1/C-DEPLOY-1.

---

## FP-9 · The knowledge layer as a tested, bounded artifact

**Problem.** The system's rules and memory steer every agent, but nothing tests them: the resident
layer is ~18.8K tokens/turn in-repo **with a byte-identical duplicate CLAUDE.md loaded twice**;
one section (Session Close) is 35% of the file and duplicates what fact-bound hooks already
enforce; superseded thresholds coexist with live ones in one skill; 322 LOC of dead hooks; 3
crash-theory generations were each written into memory as ground truth and each shaped the next
agent's priors (self-reinforcing error — caught only by a full-population census); adherence has
never been evaluated (the lazyload review asserted "no behavior change" untested); ~/.claude/
CLAUDE.md syncs by luck. Meanwhile the control layer takes ~14 commits/day (~70 agent-hrs/30d) of
self-maintenance — the guard-begets-guard loop is the upstream generator of both the tax and new
failure surface.

**Why default-tier keeps failing.** Every incident's reflex is *additive* (new rule/hook/memory);
deletion has no constituency; and adherence/conflict are probabilistic, load-dependent properties
nobody unit-tests.

**Solution shape.** (a) **Kernel tiering**: an always-resident core ≤5K tokens; everything else
lazy-loads on trigger (the skill model applied to CLAUDE.md itself); de-dup structurally (pointer,
not copy — retires config-mirror-assert). (b) **Memory provenance + decay**: entries carry
{observed-fact | agent-conclusion, confidence, verify-cmd, review-by}; a periodic fresh-context
re-verification demotes stale claims (the crash entry would have been caught in one cycle).
(c) **Adherence eval harness**: scenario probes that trigger each binding rule, scored for
compliance under load; conflict-linter across resident layers. (d) The **deletion budget** (with
FP-8). This is T-B (prose-law → substrate) matured: compile binding rules to deterministic
channels or mark them advisory — and *test* the residue that stays prose.
**First move (LOW):** de-dup CLAUDE.md + delete the 3 dead hooks + prune archaeological
thresholds (all verified-safe by fp-N); memory provenance fields on new entries.
**Verification:** resident tokens/turn drops ≥40% with adherence-eval flat-or-better; a planted
stale memory claim is demoted within one re-verification cycle.
**Routing:** backlog (first moves); hole **H-KNOW-1** (how to *measure* rule adherence under
context load — genuinely open).

---

## Live specimens captured DURING this investigation (evidence the classes are active)

| Specimen | Class |
|---|---|
| 14 wave reports returned only via transcript harvest; `idle_notification` ≠ delivery | stranded-output (FP-3/FP-5) |
| 6 mid-flight corrections "sent to inbox"; 0 delivered to the 5 finished agents; 4 delivered to still-running agents at turn boundaries | sent≠delivered race (FP-3) |
| The 07-20 wave's 13 reports recovered from a dangling checkpoint ref; synthesis had died in transcripts | stranded work-product (M2) |
| iTerm2 per-assignee consent storm: new runtime's `iterm2It2SetupComplete` flag is per-config-dir; first-run state unregistered machine-wide | config-drift / registered-state (FP-1/FP-2) |
| This session opened with a cache-expiry nag targeting a measured 0.11% problem | attention mis-allocation (FP-7) |
| Crash-forensics doc unreadable at `origin/main:` because its landing was in flight mid-read | read-during-land seam (FP-3 receipts) |
| Two agents' briefs premise-corrected by events mid-flight (crash story ×2, dispatcher-loaded) | stale-knowledge velocity (M3) |

## Measurement recipes (the unmeasured, with how-to-measure)

- False-page/false-reap rate from key-mismatch: grep IDL for STALL?→alive reversals monthly (FP-2).
- Fired-never-engaged rate: cc-fired markers with no engagement receipt ÷ fires (FP-3).
- Permission-stall rate/p95: typed `permission-stalls.jsonl` once the beacon is wired (FP-4/M-F2).
- Succession fidelity loss: sample auto-compact successors; count re-derivations of predecessor-known facts in first 20 turns (FP-6).
- Recycle policy value: shadow-fire log + successor pair-linking + decision-reversal rate (FP-7).
- Reconciler tax: reconciler-LOC vs mutator-LOC + healed/reaped/reopened IDL rows per week (FP-3/FP-8).
- Rule adherence: scenario-probe eval per binding rule under 3 context loads (FP-9).

## The net-complexity constraint (binding on this portfolio itself)

The red-team pass on this draft named the sharpest residual risk: every FP adds a subsystem to a
system whose own diagnosis (FP-9, fp-N) says complexity growth is the upstream generator — ~14
control-layer commits/day maintaining the maintainer. So the portfolio binds itself to a
**net-complexity ledger**: an FP's implementation lands only with a mechanisms-retired list ≥ its
mechanisms-added, or an explicit justification of the residual.

| FP | Adds | Retires (the consolidation case) |
|---|---|---|
| FP-1 | manifest + builder + wiring-assert | hand link-passes, per-surface point-asserts (deploy-parity/config-mirror subsumed), the `.done` marker system, the 4×-filed reconciler churn |
| FP-2 | 1 registry + 1 reconciler | the 3 overlapping anti-entropy engines, ~7 marker/latch families, prose death-classifiers, per-monitor proxy checks |
| FP-3 | 1 receipt store + 1 generic verifier | ~8 bespoke proof shapes, several compensating reconcilers (the ~22-of-109 tax shrinks toward 1 + predicates) |
| FP-4 | census + typed ledger | the decorative tamper chain (repair **or delete**), the abstain-alarm special case; net additive — accepted as the falsifiability floor |
| FP-5 | 1 oracle surface | ≥8 operator read-surfaces (suppressed-when-green), the cache-expiry nag, per-channel ad-hoc alarm dirs |
| FP-6 | 1 ledger materializer | the hand-authored-brief burden (partially), the stale-scope ambiguity; bounded by the zero-per-turn-tax design |
| FP-7 | shadow-log + a post-hoc timing reader | the 2 cache-expiry hooks' framing (deprecate), threshold-assertion churn |
| FP-8 | 1 unit-retired event + 1 consumer | future per-store reapers (coverage becomes derived), 281 cruft branches, ~3,800 ghost rows |
| FP-9 | eval harness + provenance fields | duplicate CLAUDE.md, 322 LOC dead hooks, superseded thresholds, config-mirror-assert (via structural de-dup), + the standing deletion budget |

Executed as designed, FP-2/FP-3 are the consolidation of ~22 compensating tools into one kernel
plus predicates — **the portfolio is the deletion program**, and the quarterly readout should
report the tally (mechanisms added vs retired) so drift from this constraint is itself loud.

## Routing summary

- **Campaigns:** C-RSF-1 (identity/attestation kernel + receipts; extends C-DSH-1) · C-DEPLOY-1
  (compiled deploy/activation substrate).
- **New holes (panel-worthy unknowns):** H-VER-1 (limits of runtime self-attestation) · H-SEC-1
  (content→action trust chains / prompt-injection threat model — fr-08's axis, STILL never swept:
  the one adversarial report the 07-20 wave lost) · H-ECON-1 (context-utility attribution) ·
  H-KNOW-1 (adherence measurement) · H-RESTORE-1 (backup scope + restore drill: restic covers
  only frozen CC archives; autonomy stores/memory/repo unprotected; never restore-tested).
- **Operator one-time steps (already-built things made live):** cycle the supervisor (forensics
  step 3 — crash-ledger version field is empty until then); run the permission-layer activation
  script once generated (FP-1 first move); Pushover creds; eval-track stderr (one `.zshrc:387`
  route-through).
- **Backlog quick-wins:** engagement receipt-watcher · mail read-receipts + drain systemMessage +
  statusline badge · typed page records + flock'd IDL appender · post-land retirement fan-out ·
  session-index reconcile/VACUUM · CLAUDE.md de-dup + dead-hook deletion · `--force-with-lease` +
  `--dangerously-skip-permissions` hook-level deny · shadow-fire recycle logging + `cc-timing`.

## Honest limits

- fr-08 (the 07-20 adversarial axis) was never recovered — T-D/security rests on derivation, not
  a dedicated sweep (hence H-SEC-1, not a portfolio claim).
- fp-B spot-corroborated the forensics census (4 sids), did not re-run 8,489 transcripts.
- Cost figures marked "unmeasured" carry recipes instead of numbers — deliberately.
- Three fix-branches (teardown-marker family) may land any hour and flip FP-2's first-move state;
  all wiring/dormancy claims were live-verified 2026-07-23 ~09:00Z and rot at M3 velocity —
  **re-verify at read time.**
