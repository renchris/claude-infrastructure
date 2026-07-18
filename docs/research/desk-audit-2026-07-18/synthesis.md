# Synthesis workspace — orchestrator-desk investigation

## Lead's independent ground truth (verified live this session)
- launchd LIVE: com.claude.lead-supervisor (RUNNING pid 17867), com.chrisren.cc-reaper (loaded),
  com.claude.team-orphan-reaper, session-search sweep+backfill, restic archive, watch-2118-hold (exit 1),
  watch-getAppState-fix (exit 1), screenshot-clipboard, verify-2114-archive.
- Stop hooks LIVE: notify complete → cache-expiry-tracker → teammate-checkpoint → session-continue →
  anti-deference-nudge → boundary-handoff (wired via REPO path, others via ~/.claude — inconsistency?).
- Also LIVE: rm-safe-allowlist (M1 activated), waiting-recycle (PostToolUse, not Stop), full
  session-register/index/live-registry set, task-quality-gate (TaskCompleted), teammate-auto-shutdown
  (TeammateIdle), worktree-setup (WorktreeCreate), handoff-intent-nudge (UserPromptSubmit — NOT in repo
  hooks/ ⇒ live-vs-repo drift candidate G-LEAD-1).
- ~/.claude/bin has all cc-* + claude-search; NO claude-accounts/claude-latest/claude-kimi there (live
  elsewhere? P10 to confirm).
- Roadmap truth: L3→L4 doc says P0 M1/M2 DELIVERED awaiting land — but main already contains the reaper
  stack commits ⇒ doc staleness; verify per-claim.
- SESSION_AUTONOMY_PLAN: L0-L4 + reap-guard + F1-F5 + B1-a..d ALL BUILT, gates GREEN, RED-proven;
  wiring-all v2 assembled; **Zero-HITL DoD operator-RULED** (STOP-ASK → agent-ruled default + async queue +
  push-notify; autonomous ship at GREEN; stops only C10/permission/external-info); **authority ceiling
  C10** = self-mod/persistence human-only (Invariant 6); supervisor = PAGE-only (ruling #1); D10: age can
  never confirm stall; blind-check law §3i; Invariant 7 (one artifact, one role); harness laws L1-L4.
- Named-by-the-plan missing pieces mapping to THIS goal: NS-blind-1 (voluntary session-continue arming —
  FM1), NS-blind-2 (prose DoDs — "machine-readable DoD registry would close it fully" — FM1/goal-a),
  L4 roadmap P1 dispatcher+durable-backlog, P1 verify+merge gate (partially exists as ship rails),
  P2 discovery feed + overnight quota-batch + morning digest.

## Convergence hypothesis (to be tested against wave returns)
The 24/7 desk = already-built never-stuck runtime (largely ACTIVE) + three missing organs:
1. **Mission ledger** (machine-readable DoD/backlog registry; survives handoffs; closes NS-blind-2; the
   substrate of goal-a "ALL tasks to 100/100").
2. **Dispatcher** (quota-aware wake→read-backlog→spawn→verify→land loop; roadmap §5-P1; closes FM1's
   "pause with work remaining" at the system level, not the session level).
3. **Discovery feed** (standing critics/completeness sweeps that refill the ledger; the L4 signature).
Plus FM-specific hardening from A18/A19 escapes, and de-fragilization (live-vs-repo drift, untested seams
from P12).

## Synthesis themes (emerging, 5/19 folded)
- **A. LAST-MILE WIRING (dominant):** built+RED-proven+gate-GREEN machinery dormant in the live loop:
  F1-F5 comms zero callers (P2); gate-green producer missing → boundary-handoff structurally dead (P1);
  reap-guard unwired into TeammateIdle (P3); L1 deathwatch no invoker (P3/P5); L4 reconciler never runs
  (P5); supervisor CC_PAGE_TO empty + 181 unread pages (P5); alarm dirs no readers (P2); session-deregister
  unwired (P5). Gates test CAPABILITY not LIVE WIRING ⇒ meta-fix: wiring assertions in every gate (the
  blind-check law applied to gates themselves).
- **B. DETECTION ≠ DELIVERY ≠ ACTUATION:** every watcher terminates in a disk record no one consumes; the
  desk is never woken with contrary evidence ⇒ FM2 persists BY CONSTRUCTION. Fix shape: one delivery spine
  (page → desk pane via role-resolved cc-notify + statusline badge + board), consumers for every record dir.
- **C. PROSE-LOAD-BEARING:** ship content-verify, shared-checkout guard, channel ladder, disposition runs,
  mailbox drains — prose the model can skip under rot. Fix: code-enforce the failure-critical five
  (land-verify.sh, payload-lint pre-fire, lock keying, engagement verify, DoD carry).
- **D. MISSING L4 ORGANS (roadmap P1/P2 unbuilt):** durable backlog/mission ledger (machine-readable DoD),
  dispatcher (wake→read→spawn→verify→land), discovery feed, morning digest, overnight quota batching.
- **E. SAFE AUTO-LAND:** P9's 10-point requirements list; crux = ownership-decidable stranded-sweep
  (session-id commit trailers); permission posture contradiction (push main auto-approved) must be resolved
  WITH the operator's G3 ruling (zero-HITL DoD says ship-at-GREEN is already authorized for infra).
- **F. ROSTER FRAGMENTATION:** cc-registry / live-sessions / watchdog / telemetry / task-table disagree;
  reconciler built for exactly this but not running; some handoff-fire spawn modes never register (G-P3-1).

## Gap ledger (G-*) — P0/P1 only (P2s stay in report files)
| ID | Where | FM | Sev | One-line | Source |
|---|---|---|---|---|---|
| G-LEAD-1(=G-P1-4) | handoff-intent-nudge.sh live-only | 24x7 | P1 | live hook untracked in repo | lead+P1 |
| G-P1-1 | boundary-handoff.sh:78 | FM1 | P0/P1 | gate-green has no producer → hook never fires | P1 |
| G-P1-2 | handoff-fire.sh it2_land | FM2 | P1 | no engagement verify on non-recycle fire (cold race OPEN) | P1 |
| G-P1-3 | settings Stop abs-path | 24x7 | P1 | Stop hook runs shared-checkout's checked-out branch | P1 |
| G-P1-5 | settings.example+install.sh | 24x7 | P1→ | fresh machine provisions none of the autonomy layer | P1 |
| G-P1-6 | lead-supervisor CC_PAGE_TO | FM1 | P1 | pages land nowhere; no consumer | P1+P5 |
| G-P1-7 | handoff-disposition fired_peers | FM2 | P1 | empty registry ⇒ close-eligible while peers alive (fail-open) | P1 |
| G-P2-1 | completion-push no caller | FM1 | P0 | terminal completion never pushes the desk (W5 class unfixed live) | P2 |
| G-P2-2 | cc-roles/desk stale UUID | FM2 | P0 | announce to dead/reused pane; roles not self-healing | P2 |
| G-P2-3 | alarm dirs unread | FM1 | P1 | LOUD is disk-only | P2 |
| G-P2-4 | exit-deadline no caller | FM2 | P1 | exit sweeps never tighten 3600→900 | P2 |
| G-P2-5 | payload-lint no caller | FM1 | P1 | back-channel-less payload can fire (W5 root open) | P2 |
| G-P2-6 | cc-notify verify=keystroke | FM2 | P1 | delivered ≠ processed; no desk ACK contract | P2 |
| G-P2-8 | comms-safety-gate | FM1 | P1 | gate GREEN asserts capability, not live wiring | P2 |
| G-P2-10 | notify-back prompt-only | FM2 | P1 | ping recipe/arming droppable; only trailer-text tested | P2 |
| G-P3-1 | some spawns unregistered | FM2 | P1 | reaper/teardown blind to a spawn class | P3 |
| G-P3-2 | reap-guard unwired | FM2⁻¹ | P1 | premature-reap-at-birth still reproducible | P3 |
| G-P3-3 | surfaced causes no consumer | FM2 | P1 | hung/crashed/review sessions linger silently | P3 |
| G-P3-4 | crashed panes no closer | 24x7 | P1 | dead-pid panes leak forever | P3 |
| G-P3-7 | lead-deathwatch dormant | 24x7 | P1 | out-of-band death → no capture/page | P3+P5 |
| G-P5-2 | supervisor blind to spawn-death | FM2 | P1 | telemetry-only sweep; registry-join is manual-board-only | P5 |
| G-P5-3 | reconciler never runs | FM2 | P1 | tasks×registry×disk divergence unwatched (the 77-min class) | P5 |
| G-P5-6 | idl.jsonl 114MB no rotation | 24x7 | P1 | disk bloat + re-page loop every 30s | P5 |
| G-P9-1 | land-lock keys per-worktree | 24x7 | P1/P0 | two worktrees land concurrently; race un-serialized | P9 |
| G-P9-2 | content-verify is prose | 24x7 | P1 | model can skip the one check that caught the incident | P9 |
| G-P9-3 | push main auto-approved | 24x7 | P1 | permission layer contradicts G3 intent | P9 |
| G-P9-4 | shared-checkout guard prose | 24x7 | P1 | empirical bypass land 2026-07-18T03:20 | P9 |
| G-P9-5 | sweep needs human judgment | 24x7 | P1 | exit-1-is-normal blocks auto-land | P9 |

## Task ledger — see report files' T-* tables (P1: T-P1-1..9 · P2: T-P2-1..7 · P3: T-P3-1..6 ·
P5: T-P5-1..8 · P9: T-P9-1..9 + 10-point auto-land requirements). Plan will consolidate.

## Fold 2 additions (P4, P6, P7, P8)
P0-class: G-P6-4 /wrap DOES NOT EXIST (readout=self-report — FM1 core) · G-P8-1 lr-reset-poller NOT
LOADED + AUTOFIRE=0 (limit-killed session strands forever) · G-P8-2 live cliff defaults to STOP-ASK
without standing /goal.
P1-class: G-P6-1 anti-deference 0 fires/74% blind (sidechain-tail extraction bug) · G-P6-2 abstain-alarm
documented-nowhere-built (D9) · G-P6-5b boundary-handoff 0 evaluations (2nd Stop matcher-obj? 1/4 dirs,
abs path) · G-P6-6 no mechanical declared-done==ground-truth check; PreCompact re-injects nothing ·
G-P6-7 template/install.sh miss the whole Stop-hook layer · G-P4-1 never-stuck-gate RED 19·2 + unwatched
(regressed silently from 21·0) · G-P4-2 wait-contract sweep never scheduled (62 contracts, watchdog never
fired in prod) · G-P4-3 exit-deadline inert · G-P4-4 recycle advisory omits mission/DoD (FM1 seam) ·
G-P7-1 supervisor page-storm ~85/sweep no dedup (live) · G-P7-2 gate-green producer unbuilt (=G-P1-1) ·
G-P7-5 L4 spine (backlog+dispatcher+discovery+digest) UNBUILT — THE goal blocker · G-P7-6 never-wait
runtime loops unwired (77-min class open) · G-P7-7 cc-teardown permission absent (delegated recovery
prompts) · G-P8-4 relogin human-gated 3/4 mailboxes · G-P8-5 Kimi hedge keyless · G-P8-6 cc-route/
cc-respawn no standing invoker · G-P8-7 net-positive UNMEASURED (critic hole confirmed).
Design law extracted (P7 §2.5-2.6): 7 invariants (blind-check law, authority ceiling C10, one-artifact-
one-role) · D-A..D-G (supervisor PAGES never acts; advisory never blocking; launchd daemon never a
standing Claude session; AUTOCOMPACT_PCT=90) · rejected-alternatives table (no blocking Stop hooks, no
auto-recovery, no age-keyed deletion, no trusting sends, no self-activation).
C10 doctrine: agent builds+tests+hands one-action activation script; activation queue must be
ABSENCE-IS-LOUD (D-v re-page un-run activations). Zero-HITL DoD (fea9200) is the operator's standing
ruling for unattended escalation (P15 must implement, not re-derive).

## Fold 3 additions (P13, P14, P16)
P0-class: G-P13-1 Session Close Protocol resident-only+untriggered (biggest behavioral rot exposure; fix=
Stop hook contradicting ✅ from live git) · G-P13-2 /wrap absent (=G-P6-4) · G-P14-1/2 plan index blind to
docs/plans + SessionStart 'Plans: 0' lie (feeds FM1 directly) · G-P14-7 TASKS.md can show FOREIGN project's
tasks (find_active_list global most-recent) · G-P14-9 net-positive unmeasured (=G-P8-7) · G-P16-1 reboot =
indefinite halt (FileVault + no auto-login + no auto-resume + AutomaticallyInstallMacOSUpdates ON = standing
self-reboot trigger).
P1-class: G-P13-3 /goal impl not on disk (runtime-only, unversioned) · G-P13-4 brief-line-count unenforced
at spawn (compact-crash class) · G-P14-3 index frozen 6wk/360 phantoms · G-P14-4 no list-open verb ·
G-P14-6 plan status unenforced (prose-done) · G-P16-2/3 battery sleep=1min + pmset policy out-of-band ·
G-P16-4 supervisor telemetry in /tmp wiped on reboot.
CONTRADICTION RESOLVED: P13's G-P13-5 claims lead-supervisor unscheduled — FALSE per my live launchctl read
+ P5/P7 (pid 17867). Real sliver: plist absent from REPO launchd/ (provisioning gap, joins G-P1-5/G-P6-7
template-capture class). Verify-pass value demonstrated; carry the sliver, drop the claim.
Injection-channel law (P13 thesis, design input): mid-session reach = UserPromptSubmit.additionalContext ·
PostToolUse.additionalContext · decision:block reason. Stop additionalContext INERT. Rot-resistance =
deterministic trigger on one of these channels; resident-only rules decay. FM1 fixes MUST ride these
channels, not CLAUDE.md prose.

## Fold 4 additions (P10, P11, P15) + live incident
P0-class: G-P10-1 reboot kills everything (all LaunchAgents, zero LaunchDaemons, FileVault, no auto-login
— pairs w/ G-P16-1) · G-P15-1 push channel INERT (Pushover unconfigured + CC_PAGE_TO empty — every page/
alarm is silent-to-away-human) · G-P15-2 no decision-queue artifact (STOP-ASK idles in-context; LOST on
recycle) · G-P11-1/2 anti-deference double-bug (extraction misses tool_use/metadata tails AND the C10
carve-out exempts push/land = the #1 deference class) · G-P11-4 desk-spawned orphans invisible to reaper.
P1-class: G-P15-3 git push:* ask blocks autonomous ship in all 5 dirs (CONTRADICTION with Zero-HITL T5;
supersedes P9's G-P9-3 reading — smart-bash-allowlist is wired NOWHERE/dead) · G-P15-4 anti-def cap-3 →
bare idle, no packet · G-P15-5 /limit-recover AskUserQuestion blocks unattended · G-P10-3 model-poison
guard heals default dir only · G-P10-4 live hooks = repo symlinks → feature-branch checkout = machine-wide
hook breakage · G-P10-5 desk CLIs not allow-listed (classifier prompt risk S3) · G-P10-7 settings 5-copy
drift · G-P11-5 no engagement verify (=G-P1-2) · G-P11-6 no desk-assert guard (INC-1/2/3 discipline-only) ·
G-P11-7 waiting-recycle 0/971 fires, 714 not-armed (fire path unproven in prod).
FM signatures (P11 — feed the fix hooks):
- FM1 flag: (done_assertion ∨ deference_tell) ∧ (uncommitted ∨ unlanded_verified ∨ scope_remainder) ∧
  ¬genuine_three. Operator ground truth: "you need to drive all this autonomously with no human in loop."
- FM2 flag: any state/causal claim ungrounded by ALL of {last assistant-turn read · sessionId-resolved
  pane · fixed-witnessed-ref HEAD diff}.
P15 protocol (adopt wholesale): A/B/C decision classes · cc-decide + ~/.claude/autonomy/decisions/*.json
packet schema (SPELL-OUT mapped, veto_deadline, default_if_no_veto, inv7 evidence rules) · gate-classify
router (any-doubt→B/C) · cc-digest morning surface · anti-def genuine-3 exit auto-opens packet ·
CC_UNATTENDED guard on command AskUserQuestions · staged activations → durable pending-activation/ dir.

## INCIDENT I-LIVE-1 (2026-07-18, this session — prime forensic specimen)
Monthly spend cap hit 10:41Z during the 19-agent wave: killed p12+a17+a18+a19 mid-flight; p10/p15 wrote
reports but died delivering summaries (COMPLETE_UNDELIVERED); the auto-mode PERMISSION CLASSIFIER went
down with it (Bash 'cannot determine safety' — classifier's own API calls capped); the desk sat STUNNED
~11h until the human returned and ran /limit-recover; failure notifications were delivered only on human
return. lr-audit reported 'NO GAPS' — blind to NAMED agents (inventories bare subagents + workflow slots
only). Findings: (1) monthly-spend is a limit class the poller/limit-recover stack doesn't model (no reset
time; billing decision); (2) classifier-dependency = permission layer has an API-budget SPOF; (3) named-
agent spawns need lr-audit coverage (T-NEW); (4) notification queueing to a stunned lead is an FM2
blindspot (fed to a18). Recovery: 4 SendMessage resumes with salvage-on-failure clauses, 21:2xZ.

## Report arrival tracker
| Agent | Report | Folded |
|---|---|---|
| p01-handoff | read | ✓ |
| p02-comms | read | ✓ |
| p03-idle-reap | read | ✓ |
| p04-wait-recycle | read | ✓ |
| p05-supervision | read | ✓ |
| p06-completeness | read | ✓ |
| p07-roadmap | read | ✓ |
| p08-quota | read | ✓ |
| p09-ship-land | read | ✓ |
| p10-p16, a17-a19 | pending | – |
