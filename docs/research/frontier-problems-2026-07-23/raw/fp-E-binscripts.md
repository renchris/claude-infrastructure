<!-- source: /Users/chrisren/.claude-secondary/projects/-Users-chrisren-Development-claude-infrastructure/5248d2b1-212c-4439-a911-b2e8604a7221.jsonl
 turns=67 assistant_texts=9 last_stop=end_turn mail_injections=['SCOPE ADDITION'] -->

Saturation reached — next call (reading lead-deathwatch/supervisor in full) is predictable (L1 event-death detector → `~/.claude/deathwatch/`, declared miss-blind spot) and answer-invariant. Composing.

---

# bin/ + scripts/ Code-Forward Audit: Reconciler Tax & Receipt Discipline

**Scope confirmed clean** (repo self-audit, no brief-drift). Read fully: cc-reconcile, team-orphan-reaper, stranded-sweep, autonomy-sweep, lead-reconciler, reap-guard, land-verify, completion-push, delivery-verify + headers of cc-reaper/cc-teardown; grep-sampled the rest. Live cadence verified against `launchctl list`, not just repo plists.

## Punchline (the number the lead needs)

**~14 distinct reconcilers + 8 fail-closed safety-gates = ~22 of 109 tools (~20% of the surface) exist solely to prevent or repair invariant violations.** Nearly all trace to **5 missing primitives**: (1) atomic multi-store mutation, (2) locks on *spawners* (not just landers), (3) a durable registration primitive decoupled from lifecycle events, (4) a first-class **receipt/ack**, (5) a single source of truth for liveness. Reconcilers now **depend on reconcilers** (cc-reaper→cc-reconcile→cc-backlog reap), so the tax compounds and grows new blind spots that need *more* reconcilers.

## (a) Reconciler table — invariant / writer-at-fault / cadence / blind spots

| Tool | Invariant restored | Writer that breaks it | Cadence (verified) | Blind spots |
|---|---|---|---|---|
| **cc-reconcile** (`bin/cc-reconcile:2`) | every live pane has a registry row | `hooks/session-register.sh` write-once @ SessionStart + `session-deregister.sh` **never wired** → 82 stale rows (`:216`) | called by cc-reaper `--reap` (`bin/cc-reaper:119`), cc-inbox-guard, cc-backlog — **no own cron** | no `ITERM_SESSION_ID` / no `<pid>.json` / null-sid → left for self-check (`:44`); it2 unreadable ⇒ prune nothing (`:227`) |
| **cc-backlog reap** (`bin/cc-backlog:52`) | no item stuck `claimed` by a dead worker | cc-dispatch claims then spawns; worker dies pre-transition → immortal claim (`bin/cc-backlog:54`) | only `bin/cc-reaper` calls it | thrash-block needs ≥MAX_THRASH cycles; bounded MAX_ATTEMPTS then gives up to human |
| **cc-reaper** (`bin/cc-reaper:2`) | idle handed-off lead doesn't hold a pane | any spawn (handoff-fire/dispatch/teammate) that fails to self-close | **launchd `com.chrisren.cc-reaper` LOADED, pid 96967** | P0-12b: can only reap what cc-classify enumerates; unregistered pane invisible — **surfaces delta, cannot act** (`:19`) |
| **team-orphan-reaper** (`scripts/team-orphan-reaper.sh:2`) | dead teams archived; stale perm-requests auto-denied | team create writes config.json + watchdog pid; nothing cleans on lead death | **launchd 600s LOADED** + `session-end.sh` hook | **no pid file ⇒ "assume dead"** (`:37`) → archives a live team whose watchdog file is missing; pane-liveness check "skipped for v1" (`:135`) |
| **stranded-sweep** (`scripts/stranded-sweep.sh:2`) | committed content actually reaches trunk | concurrent rebase-land drops a commit (2026-07-11 incident) | inline in land path (ship-land, desk-land, handoff-fire, land-verify, `commands/ship.md`) | **modified-but-dropped file NOT flagged** — only new files absent from trunk (`:88`); multi-session box: exit 1 is normal → review-not-verdict |
| **lead-reconciler** (`scripts/lead-reconciler.sh:6`) | 3 rosters (harness/registry/disk) agree on who's alive | separately-maintained rosters drift ("TWO-ROSTER LAW", `:10`) | **⚠ INERT — no plist, no launchctl entry; only gate/test harnesses call it; `roster_tasks` default EMPTY (`:52`)** | L4-blind *declared* (coherent-wrong invisible, `:26`) — **moot, since L4 itself never runs in prod** |
| **autonomy-sweep** (`scripts/autonomy-sweep.sh:2`) | write-only escalation dirs get drained to a desk wake | every escalation layer writes durable evidence into dirs "with no reader" (`:3`) | **launchd 300s LOADED** + 5 callers | no desk role ⇒ fail-loud, retry (good); dedupe by `.seen` marker → a re-fired identical record within TTL suppressed |
| **reap-guard** (`scripts/reap-guard.sh:5`) | never reap a just-born healthy teammate | `teammate-auto-shutdown.sh` reads clean-tree as "idle" (`:7`) | called by the hook "at activation" (C10) | grace-window hang delegated to L2 wait-contract (`:27`) — another layer, not closed here |
| **lead-deathwatch** (`scripts/lead-deathwatch.sh`) | L1 event-death of a lead is detected | harness emits no death event on some exits | family L1 (not read; predicted) | missed-event class (the reason L4 exists) |
| **lead-supervisor** (`scripts/lead-supervisor.sh`) | supervises the standing loop | — | **launchd `com.claude.lead-supervisor` LOADED, pid 67327** | 50× `2>/dev/null` — high silent-failure density |
| **prune-backups / rotate-autonomy-logs** | disk GC (backups, logs) | unbounded append writers | prune=manual(flock); rotate=**launchd 3600s LOADED** | GC-class; loss window if never run |
| **settings-drift-assert / config-mirror-assert / deploy-parity-assert** | live `~/.claude` == checkout | per-file symlink layer + shared checkout lag (memory: deploy-lag) | assert-class (gates/hooks) | brand-new tracked file never symlinked (memory-confirmed) |
| **desk-invariant / desk-recycle-invariant** | desk session state coherent | desk recycle-in-place (new pid, same pane) | **launchd 300s LOADED (desk-invariant, pid 16593)** | 26× `2>/dev/null` |
| **session-index-sweep** (hook) | search index tracks live sessions | write-once index-start | **launchd 60s LOADED** (aggressive) | — |

**Complement — the prevention tax (8 fail-closed safety-gates):** `comms-`, `limit-reset-`, `reaper-`, `respawn-`, `route-`, `session-lifecycle-`, `wait-safety-gate.sh` + `cc-teardown-safety-gate.sh`. Every major mutator carries **both** a pre-gate *and* a post-reconciler — the double tax.

## (b) Receipt table — proof-of-effect per mutating operation

| Operation | Proof-of-effect persisted | Checkable by another process? | reported-success / effect-absent risk |
|---|---|---|---|
| **teardown** (`bin/cc-teardown:10`) | **re-observes both legs**: proc gone (kill-0 poll) AND pane absent (it2 re-list); exit 5 = acted-but-survived | ✅ yes — record + exit code; gold standard ("never trusts a keystroke or exit code as proof", `:11`) | **LOW** — the one op that closed it |
| **land** (`scripts/ship-land.sh:104`) | self-attesting `land.log` JSON `{ts,sid,verify,sweep,esc_scan,exit}` + `land-verify.sh` content-verify (per-path `ls-tree`+`diff`) | ✅ yes — `stranded-sweep --mine <sid>` decides own-drop | **LOW now** (was the 2026-07-11 incident; closed by land-verify exit 8 + bounded retry) |
| **fire** (`scripts/handoff-fire.sh:384`) | **engagement = real first assistant turn** in fired transcript (`assistant_turn_in`), not birth (`:379` "BIRTH IS NOT ENGAGEMENT") | ✅ yes — grep the JSONL for a content-bearing assistant turn | **MED** — retrofitted after birth-check silently passed a never-engaging session (item ff2d6609a33e); cold-worktree auto-submit race still real (memory) |
| **dispatch** (`bin/cc-dispatch:261`) | claim `--by $SID` + append-only IDL `{action}`; spawn-fail → reopen claim (`:306`) | ✅ partial — IDL + claim ledger; **trusts handoff-fire's exit**, so a fired-but-idle worker holds a live claim | **MED** — claim held while no work runs → **cc-backlog reap compensates** (the tax) |
| **page/notify** (escalation dirs) | record written to `pages/`, `cc-announce-alarms/`, `completion-push/` | ✅ via autonomy-sweep drain; **delivery-verify** proves phone-reach with Pushover receipt (`scripts/delivery-verify.sh:7`) | **MED** — delivery-verify is a **manual PROBE**, not inline; a real page's device-delivery is unproven unless `--receipt` used |
| **completion** (`scripts/completion-push.sh:12`) | capture-before-notify record + verdict stamp; exit 5 = pushed-not-verified (LOUD) | ✅ yes — autonomy-sweep reads verdict≠verified as stuck | **LOW** |
| **respawn** (`bin/cc-respawn`) | record to `~/.claude/respawn/` + respawn-safety-gate | partial | **MED** — gate is pre-check; post-effect (did the respawn engage?) leans on the same engagement-verify gap |
| **route** (`bin/cc-route`) | record to `~/.claude/route/` | partial | LOW-MED |

**Receipt discipline verdict:** teardown/land/completion have **true receipts** (predicate + how-to-check + deadline). fire/dispatch/page have **partial receipts** with a compensating reconciler behind them. No **common receipt schema** — each op invented its own proof shape and its own directory.

## (c) Logging map + dead-weight

**~18 distinct log sinks** (fragmentation): `logs/cc-reaper.log`, `logs/cc-reconcile.log`, `team-reaper.log`, `land.log`, `autonomy/{idl.jsonl,supervisor.log,regression.log,power-policy.log,abstain-alarm.log,delivery-probe.log,backlog.jsonl}`, `completion-push/`, `deathwatch/`, `reap-guard/`, `respawn/`, `route/`, `cc-teardown/`.

- **Closest thing to a common bus:** `~/.claude/autonomy/idl.jsonl` — **24 writers** (cc-reaper, cc-dispatch, cc-decide, cc-discover, cc-audit, gate-manifest, desk-recycle-invariant…), queried by `cc-idl`/`cc-audit`. **But** the reconcilers mostly write their *own* logs, not the IDL.
- **"What happened in the last hour?"** — only **partially** answerable today: `cc-idl`/`cc-audit` cover the ~24 IDL writers; the reaper/reconcile/land/team-reaper events live in separate files with no shared schema.
- **Correlation id:** weak — only **9 files** propagate a session id; `Session-Id:` trailer exists for *lands* but not spawns/pages. No cross-tool trace id.

**Dead-weight candidates** (0-3 external refs, validated):
- `scripts/settings-dedup-stop.sh` — **0 external refs, NOT in settings-templates/.claude** → strongest candidate (caveat: can't see live `~/.claude/settings.json`).
- `scripts/auto-revert-getAppState-patch.sh` (1), `scripts/kimi-frontend-ab.sh` (2), `scripts/record-version.sh` (2), `scripts/watch-claude-code-2118-hold.sh` (3) — version-pin/experiment one-offs; stale.
- `bin/claude-bump-models` (3), `bin/cc-value` (7), `bin/desk-assert` (7) — low-connectivity; review.

**Overlap/duplication:** stranded-sweep vs land-verify (both prove landing; land-verify is per-path superset, stranded-sweep is cross-branch) — *deliberate* layering, not dup. cc-reconcile (registry) vs cc-backlog reap (claims) vs lead-reconciler (rosters) — **three separate anti-entropy engines** over three stores that a single liveness SSOT would collapse.

## (d) Candidate frontier problems

**FP-1 — No receipt primitive → the reconciler tax compounds superlinearly**
- *Evidence:* ~14 reconcilers + 8 gates for 5 missing primitives (table a); cc-reaper explicitly depends on cc-reconcile (`bin/cc-reaper:119`) which itself compensates for two writers (`bin/cc-reconcile:2,216`); cc-dispatch's claim strands until cc-backlog reap (`bin/cc-backlog:54`).
- *Mechanism class:* distributed eventually-consistent system on the filesystem with no transactions/locks/receipts; each mutator invents ad-hoc proof.
- *Current mitigations + status:* teardown/land/completion have true receipts (SHIPPED); fire/dispatch/page partial + reconciler backstop (SHIPPED but leaky).
- *Why it resists normal fixes:* each incident spawns a *point* reconciler (whack-a-mole); adding a reconciler grows a new blind spot needing another (cc-reconcile's prune leak → guarded-prune). The operator's own memory names this: "repeated manual reconciliation of the SAME class = a systemic gap."
- *Quantified cost:* unmeasured — **how to measure:** count reconciler LOC vs mutator LOC (est. ~1:1 from sizes: cc-reaper 31K+cc-reconcile 16K+cc-backlog 25K reconciler-side); count reconciler-triggered IDL `{action:"healed|reaped|reopened|pruned"}` rows/week from `idl.jsonl`.
- *Frontier-fix sketch:* one **receipt library** — a `receipt{op, predicate, how-to-check, deadline, sid}` written by every mutator to one append-only store; a *single* generic reconciler verifies open receipts past deadline. Collapses ~14 bespoke reconcilers toward ~1 + per-op predicates.
- *Confidence:* **High** (empirical: read the code, verified layering). Stale-risk: low — architecture is stable.

**FP-2 — Non-atomic multi-store mutation on spawn/land**
- *Evidence:* dispatch writes {claim ledger, registry, cc-fired marker, IDL} non-atomically (`bin/cc-dispatch:261-306`); land writes {local branch, trunk, land.log} (`scripts/ship-land.sh:104,201`); **spawners don't lock** — flock/mkdir-lock appear only in launchers + land scripts (grep: `land-lock.sh`, `ship-land.sh`, `claude-latest`, not cc-dispatch/cc-reaper/cc-teardown).
- *Mechanism class:* partial-write / interleaving on shared state without 2-phase commit or mutex.
- *Current mitigations:* land-lock (mkdir mutex) + land-verify + stranded-sweep for *land only*; spawn side leans on cc-backlog reap after the fact.
- *Why it resists:* filesystem has no cross-file transaction; bash 3.2 portability constraint rules out heavyweight coordination.
- *Quantified cost:* the 2026-07-11 dropped-commit incident (1 known data-loss); claim-strand frequency unmeasured — **measure:** grep `idl.jsonl` for `claim failed`/reopen cycles.
- *Frontier-fix sketch:* a spawn-transaction wrapper: one lock + write-ahead intent record + commit/rollback, mirroring land-lock but for the {claim,registry,marker} tuple.
- *Confidence:* **High** (empirical). Stale-risk: low.

**FP-3 — The L4 anti-entropy backstop is inert; coherent-drift is unguarded in production**
- *Evidence:* `lead-reconciler.sh` appears in **no plist and no `launchctl list` entry**; called only by `wait-safety-gate.sh`, `never-stuck-gate.sh`, `reaper-horizon-lint.sh` (all gates/tests); its `roster_tasks` default is empty (`scripts/lead-reconciler.sh:52` "none wired here — the operator supplies…at activation").
- *Mechanism class:* built-not-wired (the C10 activation gap; matches memory "staged≠loaded").
- *Current mitigations:* cc-reaper's P0-12b self-check + cc-reconcile cover *registry* drift; the *three-way* roster drift (tasks×registry×disk) it was built for has **no live watcher**.
- *Why it resists:* activation is a human-only C10 step; the tool RED-proves in selftest so it *looks* done while being inert — the exact false-green the operator's memory warns about.
- *Quantified cost:* unmeasured — **measure:** does `~/.claude/reconciler/heartbeat.json` exist and is it fresh? (L4-c heartbeat, `:83`). Predict: absent/stale.
- *Frontier-fix sketch:* wire the harness task-table reader + a launchd tick; or fold roster-reconciliation into the already-loaded lead-supervisor.
- *Confidence:* **High** (verified launchctl + code). Stale-risk: med — one activation would flip it.

**FP-4 — Observability fragmentation: no unified event view**
- *Evidence:* 18 log sinks (grep); IDL covers ~24 writers but reconcilers write private logs (`cc-reaper.log`, `team-reaper.log`, `land.log`); correlation-id in only 9 files.
- *Mechanism class:* no shared event schema / trace id across a 109-tool fleet.
- *Current mitigations:* cc-idl/cc-audit over idl.jsonl (partial); cc-crash-report (recent, ef7f7a4).
- *Why it resists:* tools accreted independently, each choosing its own dir; retrofitting a schema touches all 109.
- *Quantified cost:* unmeasured — **measure:** attempt a real "last hour" reconstruction; count events reachable from idl.jsonl vs total.
- *Frontier-fix sketch:* one structured-event emitter (`emit_event op sid outcome`) → single JSONL with a trace id threaded spawn→fire→claim→land→teardown.
- *Confidence:* **Med-High** (empirical on sinks; "last hour" claim is inferential). Stale-risk: low.

**FP-5 — C10-barrier tool proliferation** (lower priority, structural)
- *Evidence:* reap-guard (`scripts/reap-guard.sh:11`) and cc-reconcile exist as standalone tools *because* the live hook "can't be edited in place (the C10 line)"; teardown notes the same (`bin/cc-reaper:50`).
- *Mechanism class:* safety rule (no self-editing live hooks) → fixes ship as new callable tools the hook invokes "at activation," inflating surface + creating staged-not-loaded gaps.
- *Current mitigations:* pending-activation/ staging (memory).
- *Why it resists:* the C10 barrier is a deliberate safety invariant; can't be removed, only managed.
- *Quantified cost:* unmeasured — **measure:** count tools whose sole caller is "a hook at activation" + count files in `pending-activation/`.
- *Frontier-fix sketch:* a thin dispatch hook that reads its decision module from a versioned path, so the *logic* updates without editing the wired hook or minting a new top-level tool.
- *Confidence:* Med (pattern clear; cost unquantified). Stale-risk: low.

## Blockers / uncertainties (explicit)
- **Live-only state I could not read:** `~/.claude/settings.json` (settings-dedup-stop dead-ness is repo-scoped only); `~/Library/LaunchAgents/*.plist` (cc-reaper/lead-supervisor loaded from there, not repo `launchd/` — so repo `launchd/` is **not** the SSOT for cadence).
- **Not read in full** (predicted, answer-invariant): `lead-deathwatch.sh`, `lead-supervisor.sh` body, `claude-accounts` (67K), `handoff-fire.sh` body (134K — grepped only).
- **Empirical vs theoretical:** reconciler inventory, cadence (launchctl), receipt shapes, lead-reconciler inertness, dead-weight refs = **empirical**. "Last-hour unanswerable," claim-strand frequency, cost figures = **theoretical/inferred** — flagged "unmeasured" with a measurement recipe each.
- **Adversarial pass integrated:** it surfaced (1) the safety-gate *prevention* class as the reconciler complement — every mutator carries both, doubling the tax; (2) lead-reconciler being **inert** (I initially assumed it was cron'd); (3) the C10-barrier as a *generative* cause of proliferation (FP-5); (4) validated dead-weight against settings wiring rather than asserting from ref-count alone.