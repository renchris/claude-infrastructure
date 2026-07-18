# ORCHESTRATOR DESK 24×7 — the self-originating operator program

**Scope (frozen 2026-07-18):** take the orchestrator-desk stack from "largely-activated safety
harness for human-initiated waves" (P7 verdict) to a **self-originating, 24/7, net-positive,
no-human-in-loop operator** that (a) exhaustively identifies ALL tasks toward 100.00/100.00
completion of any target repo/long-horizon goal via a durable machine-readable mission ledger,
(b) drives many parallel /handoff sessions with verified 2-way comms, graceful close, and
re-handoff at pause points, and (c) renews itself without losing the mission — while killing the
two chronic failure modes: **FM1** premature-done/purpose-loss and **FM2** idle-session standoff.
Clean and non-fragile: every fix is code-enforced at a deterministic seam (never prose-only),
RED-proven, and wired-live (capability-green ≠ active). C10 authority ceiling holds throughout:
agents build + test + hand one-action activation scripts; the operator activates.

**Evidence base:** 19-agent research wave 2026-07-18 (16 productive beats + 3 adversarial),
decomposition critic-gated. Full reports: `docs/research/desk-audit-2026-07-18/` (p01–p16,
a17–a19). Live incident I-LIVE-1 (spend-cap strand, this session) is dossier #8. Prior intent
docs remain SSOT for design law: `docs/L3-L4-AUTONOMY-ROADMAP.md`,
`docs/research/SESSION_AUTONOMY_RESEARCH.md` (7 invariants, D-A..D-G),
`docs/research/W0-W3_INTERVENTION_AUDIT.md` (Zero-HITL DoD `fea9200`, R-1..R-4 floor).

---

## Phase 0 — Agent Team Orchestration (MANDATORY FIRST)

**Team (6 max concurrent, worktree-isolated, ≤150-line briefs, single-owner files):**

| Teammate | Owns (single-owner) | Delivers |
|---|---|---|
| `fm1-stack` | `hooks/anti-deference-nudge.sh`, `hooks/session-continue.sh`, new `hooks/completion-assert.sh`, new `commands/wrap.md` + `scripts/wrap-ledger.sh`, `hooks/boundary-handoff.sh` | Program B (FM1 kill stack) |
| `fm2-stack` | `scripts/handoff-fire.sh`, `hooks/session-register.sh`, new `bin/desk-assert`, `scripts/handoff-disposition.sh` | Program C (FM2 kill stack) |
| `ledger` | `hooks/plan-index-update.sh`, `hooks/setup-plan-symlinks.sh`, `hooks/setup-task-symlinks.sh`, `hooks/lib/task-helpers.sh`, `scripts/find-plan.sh`, `hooks/validate-plan-structure.sh`, new `bin/cc-backlog` | Program D substrate (mission ledger) |
| `escalation` | new `bin/cc-decide`, new `scripts/gate-classify.sh`, new `bin/cc-digest`, `commands/limit-recover.md` (CC_UNATTENDED guard only) | Program E (unattended escalation) |
| `landing` | `scripts/land-lock.sh`, new `scripts/land-verify.sh`, `scripts/stranded-sweep.sh`, new `scripts/ship-land.sh`, `.claude/commands/ship.md` | Program F-land (safe auto-land) |
| `wiring-author` | `docs/activation/wiring-all.sh` (v3), `settings-templates/`, `install.sh`, new `scripts/settings-drift-assert.sh`, new `hooks/activation-watch.sh`, launchd plists (repo copies) | Program A consolidation (docs+scripts only, no live edits) |

- **Dependency graph:** `ledger` and `landing` and `wiring-author` independent (wave W-a with
  `fm1-stack`); `fm2-stack` independent (W-a); `escalation` blockedBy `ledger` (decision packets
  reference backlog items) → W-b. Lead lands serially (smallest-diff first) via project `/ship`.
- **Worktrees:** `/private/tmp/wt-<member>` off `main`; branches `feat/desk-<member>`.
- **Spawn waves:** W-a = fm1-stack + fm2-stack + ledger + landing + wiring-author (5) ·
  W-b = escalation (after ledger merges). Dispatcher/discovery (Program D phases 2-3) are a
  SECOND team cycle after W-a/W-b land — they consume the mission ledger.
- **Per-teammate:** pre-greped line ranges in briefs (from the audit reports — cite report
  file:line); "Stop on issue, message lead" verbatim; no investigate/explore language; visual
  verification n/a (all shell/hooks — bats + selftests are the gate).
- **Gates:** every new detector/hook ships with register-criteria-FIRST RED-provable bats
  (house `43de6d6` discipline) + abstention logging (`{fired|passed|abstained|failed}` to IDL).

## Design law (binding on every task — from the blueprint + this audit)

1. **Verify the EFFECT**, never the report/keystroke/spawn/config (invariant 1).
2. **Fail-loud/abstain, never fail-silent-open**; every check logs abstentions; a check that
   cannot observe what it guards is no check (blind-check law §3i).
3. **Advisory, never blocking**, for context-boundary hooks; `decision:block` one-shot-latched
   is the strongest allowed form (D-C). No blocking Stop-hook loops.
4. **Supervisor PAGES, never auto-recovers** (ruling #1); recovery runs only on succession rails.
5. **One artifact, one role** (invariant 7): deletion keys on AGE never state; views HIDE never
   DELETE; attestations bind by CONTENT.
6. **C10 ceiling**: agent never edits settings.json/launchd/live hooks in place — build + test +
   hand `~/.claude/autonomy/pending-activation/<id>-activate.sh` (durable, NOT /tmp) + rollback
   one-liner. Activation queue is absence-is-loud (activation-watch re-pages un-run items).
7. **Injection-channel law (P13):** mid-session behavioral reach = UserPromptSubmit
   `additionalContext` · PostToolUse `additionalContext` · `decision:block` reason. Stop-hook
   additionalContext is INERT. Every FM1/FM2 behavioral fix rides one of these — never
   resident-prose-only.
8. **FM1 flag predicate (P11):** `(done_assertion ∨ deference_tell) ∧ (uncommitted ∨
   unlanded_verified ∨ scope_remainder) ∧ ¬genuine_three`. Ship/land of verified net-positive
   work is NOT genuine (operator strengthening 2026-07-17).
9. **FM2 grounding triad (P11):** no state/causal claim about a session without ALL of
   {last-assistant-turn read · sessionId-resolved pane · fixed-witnessed-ref diff}.
10. **Wiring assertions:** every capability gate (comms-safety, wait-safety, never-stuck…) gains
    a LIVE-WIRING leg — GREEN requires a production caller/scheduler, not just selftests (the
    capability-green ≠ active lesson, 7 instances this audit).

## The consolidated P0 ledger (start here; each row = agent-buildable unless marked OPERATOR)

| # | Fix | From | Acceptance (RED-provable) |
|---|---|---|---|
| P0-1 | **gate-green producer**: project `/ship` green-gate step + commit-time green path write `git rev-parse HEAD > $(git rev-parse --git-common-dir)/gate-green` | G-P1-1/G-P7-2 | boundary-handoff emits `fired` (not `abstained`) in IDL on a real ≥73% committed+green Stop; e2e fixture no longer the only writer |
| P0-2 | **/wrap as code** (`scripts/wrap-ledger.sh` + `commands/wrap.md`): ledger from live git/gate reads | G-P6-4/G-P13-2 | `/wrap` emits the CLAUDE.md ledger block from facts; readout not reconstructable from memory |
| P0-3 | **completion-assertion Stop hook**: when last text asserts ✅/complete, corroborate vs machine ledger (clean ∧ gate-green ∧ trunk..HEAD accounted ∧ scope_remainder=none) else block-once with the contradiction | G-P6-6/G-P13-1 | bats: false-✅ over dirty/red/unpushed → block naming the fact; true-✅ silent; latch+cap; fail-safe exit 0 |
| P0-4 | **anti-deference triple fix**: main-agent-scoped extraction (walk past tool_use/metadata tails) · narrow C10 carve-out (push/land NOT genuine when clean+verified) · done-assertion tells gated on remainder | G-P6-1/G-P11-1/2/3 | fixture from real 9f1c9526 turn FIRES; sidechain-tail fixture FIRES; genuine-three fixtures abstain; live `no-assistant-text` <10% |
| P0-5 | **mission-ledger index repair**: plan-index covers `docs/plans/` + `.claude-plans/`; SessionStart count truthful; `find-plan --list-open`; `status:` frontmatter schema + lint; task-list project-scoping | G-P14-1/2/4/6/7 | SessionStart reports real counts; `--list-open` enumerates every open plan cross-project; foreign-project TASKS.md impossible (fixture) |
| P0-6 | **decision queue**: `bin/cc-decide` + `~/.claude/autonomy/decisions/*.json` (P15 §3.2 schema) + `gate-classify.sh` A/B/C router (any-doubt→B/C) + anti-def genuine-3 exit auto-opens packet | G-P15-2/4 | packet survives recycle; class-B default fires at veto_deadline; C10 surface routes C; no age-reaper deletes `open` |
| P0-7 | **push delivery** OPERATOR: Pushover creds + `CC_PAGE_TO` (desk role) + supervisor plist env; agent builds the verify probe + digest push | G-P15-1/G-P10-6/G-P5-1 | a synthetic DEAD page + a class-B packet each reach the phone (effect-checked live once) |
| P0-8 | **reset-poller install + AUTOFIRE** OPERATOR (wiring-all ①); agent adds headless spawn path (tmux/`claude -p`) + monthly-spend limit class (no reset time → decision packet, never silent park) | G-P8-1/3 + I-LIVE-1 | launchctl shows poller; a parked test session auto-resumes headless; a monthly-spend event opens a class-B packet |
| P0-9 | **land-lock keying** on `--git-common-dir` + `land-verify.sh` (content-verify as code) + `ship-land.sh` extraction (lock→fetch→rebase→gate→push→verify→sweep, fail-closed) + shared-checkout refusal in code | G-P9-1/2/4 | two worktrees hash-collide (new bats, no LAND_LOCK_DIR override); red verify fails the land; shared-checkout land refused LOUD |
| P0-10 | **reboot survival** OPERATOR DECISION: LaunchDaemon conversion vs auto-login (FileVault call) vs post-login auto-resume agent; + kill self-reboot trigger (`AutomaticallyInstallMacOSUpdates=false`); agent builds the post-login resume chain + boot-delta pager | G-P10-1/G-P16-1..4 | simulated login-after-reboot resumes desk jobs + sessions with zero human action (or pages once if deferred) |
| P0-11 | **engagement verify** in handoff-fire non-recycle path: poll fired session's JSONL for a real first assistant turn / brief-text; non-zero + auto-refire-warm on miss | G-P1-2/G-P11-5 | a cold fire that never engages returns non-zero + warm refire; e2e with throttled boot |
| P0-12 | **fired-peer registration**: every handoff-fire spawn lands in cc-registry (reaper-resolvable) + reaper self-check enumerated≈live-panes | G-P3-1/G-P11-4 | fresh fired peer appears in `cc-reaper sweep` list; cc-teardown resolves it by name |

## Program ladders (P1/P2 detail lives in the per-beat reports; IDs preserved)

- **A — last-mile wiring** (mostly `wiring-author` + OPERATOR one-shot): F3/F4/F5 callers
  (T-P2-1/4/5) · reap-guard insert (T-P3-2) · deathwatch+reconciler+wait-sweep+never-stuck on
  supervisor cadence (T-P3-5, T-P5-3/4, T-P4-1/2) · boundary-handoff 4-dir re-wire (T-P6-5) ·
  cc-roles self-heal (T-P2-2) · crashed-pane closer (T-P3-4) · surfaced-causes consumer (T-P3-3)
  · supervisor page-dedup + IDL rotation (T-P7-2, T-P5-5, T-P10-2) · settings template capture +
  drift assert (T-P6-6, T-P10-4) · abstain-alarm D9 (T-P6-4/T-P7-3) · wiring-all v3 + activation
  watcher (T-P7-8, T-P15-8).
- **B — FM1 stack** (`fm1-stack`): P0-2/3/4 + DoD durable persistence & re-injection
  (PreCompact/SessionStart from the mission ledger, T-P6-7) · mission/DoD line in recycle
  advisory + /handoff capture (T-P4-4) · /goal versioned + standard goal-line in every fire +
  `wc -c` pre-fire guard (G-P6-5, G-P13-3) · brief-count enforcement at spawn (G-P13-4) ·
  task-quality-gate repo-aware (G-P6-10) · exit-deadline wiring (T-P4-3).
- **C — FM2 stack** (`fm2-stack`): P0-11/12 + `desk-assert` grounding guard (T-P11-6) ·
  supervisor spawn-death join (T-P5-2) · disposition fail-closed + word-boundary (T-P1-6) ·
  notify-back e2e + auto-arm fallback (G-P2-10) · process-ACK for terminal pushes (T-P2-7) ·
  waiting-recycle arm-by-default for monitoring desks + escalate-at-cap (G-P11-7, T-P1-8).
- **D — mission ledger → dispatcher → discovery** (`ledger`, then team cycle 2): P0-5 →
  `bin/cc-backlog` (durable backlog; DoD registry closing NS-blind-2) → dispatcher routine
  (cron/`/schedule` wake → read backlog → `cc-wave-plan` (T-P7-6) quota placement → spawn →
  verify+land → refill) (T-P7-4/5) → discovery feed (standing critics + frontier-hole sweeps +
  completeness scans refilling the backlog) → `cc-digest` morning surface (T-P15-6) →
  net-positive value ledger {commits-landed + tasks-closed}÷spend on cc-board (T-P14-7/T-P8-5).
- **E — unattended escalation** (`escalation`): P0-6/7 + CC_UNATTENDED AskUserQuestion guard
  (T-P15-7) · ask-narrowing for the ship rail after U2 verification (T-P15-4) · gate-batching
  manifest C1..C10 (T-P7-7) · lr-audit named-agent coverage (I-LIVE-1) · Kimi hedge key +
  cliff-fallback offer (T-P8-6, OPERATOR key) · headless relogin device-code for 3 mailboxes
  (T-P8-7).
- **F — substrate + landing** (`landing` + OPERATOR): P0-9/10 + ownership-decidable sweep
  (session-id trailers + `--mine`, T-P9-4 — THE auto-land crux) · escalation-scan in code +
  rollback + self-attesting land.log (T-P9-6/7/8) · pmset/caffeinate repo-managed (T-P16-3/4) ·
  model-guard `$CLAUDE_CONFIG_DIR` fix (T-P10-3) · desk-CLI allowlist after S3 probe (T-P10-6) ·
  plist lint + malformed-& fix (T-P16-6) · obsolete watcher removal (T-P10-7) · lr-fire-resume
  binary SSOT (T-P8-8).

## Adversarial addendum (a17/a18/a19 + p12 integrated 2026-07-18; extends the P0 ledger)

| # | Fix | From | Acceptance (RED-provable) |
|---|---|---|---|
| P0-13 | **Reap-safety triple**: (a) fix the ms/s unit bug in `find_successor` (`startedAt` epoch-ms vs seconds — time gate vacuous) + scope the handoff tell to SELF-handoffs; (b) "idle" requires no-assistant-record AND no-in-flight-tool (unmatched trailing tool_use / claude-child CPU); (c) pin {sid,pid,lstart} at classify-time and re-verify at teardown-time (recycle race); (d) classify reads wait-contracts + fired-peer evidence before `finished`; (e) desk-role sessions never-reap | a18 L-3/L-13, a17 S-3/S-4 | RED fixtures: co-cwd sibling no longer fakes a successor; a 12-min tool call in a clean cwd stays `active`; a recycle between classify and act aborts the reap; a desk with open wait-contracts is `owned-wait` |
| P0-14 | **Desk-existence + engagement invariant** (the missing organ — A17 capstone): launchd-side, API-budget-independent check "a registered desk session exists AND took an assistant turn ≤N min (or holds a fresh owned-wait contract); else re-prompt the stunned desk (OS-level, no model turn) / fire one from a canned brief"; includes fleet-wide transcript-tail cap/billing-error sweep + OS-level page (SO-6: the wake path must not share the API failure domain) | a17 S-0/S-1/S-12, a18 L-14/SO-6 | kill the desk (or stun it) in a probe → invariant re-engages/re-creates it ≤2 sweeps with zero human action; spend-cap text triggers the OS-level page |
| P0-15 | **Role indirection + write-only-dirs consumer**: handoff-fire writes `cc-roles/<role>` at EVERY fire/recycle/self-close; `cc-await-ping --role` follows the file; ONE sweep (supervisor tick) drains `autonomy/pages/` + `cc-announce-alarms/` + `completion-push/` → cc-notify to the desk ROLE + statusline badge | a18 SO-1/SO-5, a17 S-7/S-8/D-2 | post-recycle completion push reaches the NEW desk pane (e2e); a synthetic alarm file becomes a desk wake ≤1 sweep; zero write-only dirs remain (every record dir has a named consumer) |
| P0-16 | **Goal/continue hardening**: `handoff-fire` hard-gates /goal payloads >4000 chars (fail-loud pre-fire); session-continue gains kill-switch awareness + cap re-arm mechanics; /goal gets a durable-checklist companion file the evaluator can be pointed at (defeats tool-blindness); anti-deference fix (P0-4) adds scope-based fire using the /wrap ledger, not phrase-list-only (I-3: phrase lists train evasion) | a19 D-7/D-8/D-10/D-11/I-2/I-3 | over-cap goal refuses to fire (loud); "…and stop" wins over a stale sentinel (fixture); a false "all green" fails the checklist companion; the 6 tell-free deference closes (a19 §KQ1) all FIRE via the scope check |
| P0-17 | **Landed-by-content**: cc-classify/cc-reaper `work_landed` uses content (git cherry/patch-id vs trunk) not rev-list count (squash-land ⇒ permanent DEFER loop today); extend cc-classify:77 cap-grep to monthly-spend/billing text | a18 L-10/L-14, p11 INC-5 class | squash-landed fixture reaps (content present, count>0); monthly-spend transcript classifies rate-limited-class (parked, packet opened), not owned-wait |
| P0-18 | **Standing regression signal**: nightly launchd job runs `bats tests/` + all gate scripts + lints + `plutil -lint` and PAGES on red via P0-15's consumer (p12: nothing runs tests between lands; never-stuck regressed 21·0→19·2 unwatched); fix /ship `*.py` glob (extensionless python) | p12, G-P4-1 | a deliberately-broken detector pages by morning; never-stuck-gate red = page ≤24h |

Also folded: boundary-handoff must be registered on ALL FOUR config dirs (desk runs on
.claude-secondary which lacks it entirely — a19 live table) alongside P0-1's gate-green producer;
handoff-disposition gains a completeness axis (delegated-deliverable vs brief, a19 §4); the
compose-guard sentinel path mismatch (I-1) is fixed as part of P0-3's hook work.

**Phase 0 roster delta:** new teammate `reap-safety` (owns `bin/cc-classify`, `bin/cc-reaper`,
`bin/cc-teardown`, `scripts/reap-guard.sh`, `hooks/teammate-auto-shutdown.sh` insert-prep) —
carries P0-13/17. Spawns in W-b (after a W-a slot frees; ≤6 concurrent held). `wiring-author`
additionally owns P0-14 (desk-invariant script + plist template + activation entry) and P0-18
(nightly regression job template). `fm1-stack` picks up P0-16's hook halves; `fm2-stack` picks up
P0-15's handoff-fire role-writes; `escalation` owns the consumer sweep half of P0-15.

## Operator decision points (class-B packets at first need; none block the W-a build)

1. **Reboot posture** (P0-10): auto-login+FileVault-off vs LaunchDaemons vs manual-morning-resume.
2. **Pushover credentials** (P0-7) — one-time secret.
3. **Monthly-spend policy** (I-LIVE-1): cap raise vs cross-account overflow vs Kimi hedge key.
   Default-if-no-veto (per drive-by-default): cross-account continuation (quota-plane isolation);
   Kimi engages only on operator key.
4. **Ask-narrowing scope** (T-P15-4): sanction the ship-rail-only push allow (after U2 probe).
5. **wiring-all v3 run** — the consolidated one-shot activation (supersedes ①–⑥ backlog).
6. **Ruling-#1 scope vs the acting desk-invariant** (red-team V1): ruling #1 (2026-07-14,
   operator-ratified) says the supervisor PAGES, never auto-recovers — because naive actors keyed
   off lying signals CAUSE incidents. P0-14's desk-invariant ACTS (bounded re-prompt/respawn,
   budget ≤2/6h, OS-level channel, conservative predicates). It is built as code + plist template
   only; loading the plist IS the ratification moment (C10 already gates it). Options: (a) ratify
   the invariant as a NEW organ outside ruling #1's supervisor scope (recommended — the 11h stun
   is the empirical cost of pure-page); (b) page-only mode (`DESK_INVARIANT_ACT=0`); (c) reject.

**Sequencing law (red-team V3):** reap-safety (P0-13) MUST land before ship-land.sh is activated
for autonomous use — auto-landing creates clean+landed states that remove the accidental
dirty-tree shield which alone prevents wrongful reaps of working sessions today.

## Verification discipline

Every program carries an un-hold bar gate extended with the LIVE-WIRING leg (law #10); the
existing gates (comms/wait/reaper/never-stuck/premortem) get wiring assertions in the same pass
that wires their subjects — no gate goes green on capability alone again. Full regression =
`bats tests/` + all gate scripts + shellcheck, run inside the land lock per ship-land.sh.

## Status log

- 2026-07-18 (desk session 44f5331d, Fable@max, /goal-driven) — plan created from the 19-agent
  audit wave (15/19 landed pre-spend-cap; p12+a17+a18+a19 resumed post-cap, returns pending —
  their findings integrate here on arrival). Live incident I-LIVE-1 captured (spend-cap killed 4
  agents + the permission classifier; desk stunned ~11h; lr-audit blind to named agents).
  Evidence corpus copied to docs/research/desk-audit-2026-07-18/. Next: integrate adversarial
  returns → OASIS close → fire Phase-0 W-a.
- 2026-07-18 ~23:0xZ — **PHASE 0 WAVES W-a + W-b COMPLETE — all 7 teammates DONE, merged, gates
  green.** Programs delivered (agent-buildable halves of P0-1..18): fm1-stack `91bc922` (wrap-ledger
  f5997c1 · completion-assert 2dc88bd · anti-def triple 9aa901d — 58 bats) · ledger `9ededdf`
  (index+counts+list-open+status-lint+task-scoping+cc-backlog — 47 bats) · wiring-author `108e079`
  (desk-invariant 18-branch RED-proven · nightly-regression · 12-event template+drift-assert ·
  activation-watch · wiring-all v3 — 20 bats + 6 plists lint-clean) · fm2-stack `a103e7f`
  (engagement-verify · registration · role-writer · goal-guard · disposition-hardening ·
  desk-assert — 81 tests) · landing `cf0218b` (lock re-key by git-common-dir · land-verify ·
  ship-land.sh pipeline w/ gate-green producer · thin ship.md · sweep --mine — 32 bats, faithful
  2026-07-11 repro exits 8) · reap-safety `8fe4cb9` (ms/s+self-scope · in-flight-tool guard ·
  wait-contract+desk-role never-reap · classify→act identity pin · landed-by-content ·
  monthly-spend cap-grep — 58 checks; + C-locale unicode-adjacency fix, repo sweep clean) ·
  fm1b-continuity (kill-switch-aware+sid-bound continue 7215f4e · compose-guard SSOT fee0b10 ·
  dod-persist 5c6f117 — 374-green exit) · lead glue (cc-await-ping --role `3856580` ·
  autonomy-sweep plist · wiring-all symlink coverage). Wave learnings: SendMessage RESUMES a
  mid-loop-dead teammate with context intact but is a NO-OP on a completed one (read its transcript
  instead); one silent mid-loop death (I-LIVE-2) cost 40 min wall, zero work; per-task checkpoint
  notes + single-owner files produced 0 merge conflicts across 7 branches; RED-first held in every
  commit. Operator concurrently issued the Follow-On Gate (F1-F4) + THIS-repo standing-land
  authorization — the land below runs under it.
- 2026-07-18 ~22:2xZ — adversarial returns integrated (addendum P0-13..18); OASIS closed
  (three-angle convergence, sublinear tail; out-of-scope-named: prompt-injection hardening,
  multi-machine). W-a fired (5 teammates) + W-b reap-safety. fm1-stack DONE + merged `91bc922`
  (58/58: wrap-ledger f5997c1 · completion-assert 2dc88bd · anti-def triple 9aa901d). Red-team
  verdict integrated (pre-addendum read → V1/V3 stale = independent convergence on P0-14/P0-13;
  REAL catches: V4 gate-green producer unassigned → assigned to landing's ship-land.sh green
  path + blockedBy edge landing→fm1-consumers; V1-core → operator decision #6; V3 corollary →
  the sequencing law above; V2 residual → decision #3's default-if-no-veto). Incidents: I-LIVE-2
  landing teammate died silently mid-loop (tool_result, no error record, no notification — the
  reconciler-class divergence live) → resumed by SendMessage with the gate-green addendum;
  result-delivery gap 3rd instance (rt-synthesis completed, final payload never delivered,
  completed-agent resume no-op — verdict recovered by transcript read; feeds P0-15's consumer
  design: harness notification channels are themselves a lossy layer).
