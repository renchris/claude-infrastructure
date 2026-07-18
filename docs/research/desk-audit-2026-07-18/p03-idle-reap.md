# P3 — Idle classification + reaping (the liveness model)

Beat: extract cc-classify's idle-cause taxonomy + detectors, and the reaper's policy +
safety envelope, mapping each cause to FM2 (idle-session standoff) coverage or escape.
Coverage: read **20 of 21** in-scope files (code first). Skipped only `tests/cc-reaper.bats`
+ `tests/reap-guard.bats` full bodies (inferred their RED-proofs from the two selftest
harnesses embedded in `bin/cc-reaper` + `scripts/reap-guard.sh`, both read in full). Every
claim below is empirical (read/ran) unless tagged (inferred).

Empirical runtime state captured 2026-07-18 ~03:2x PT: BOTH reapers loaded + sweeping;
`cc-classify --all` run live (classified a real `finished-teammate` + a fail-safe `active`).

---

## 1. Inventory (one row per in-scope asset)

| Asset | Role in desk loop | Wiring | Depends on | Verified by | Goal | Gap |
|---|---|---|---|---|---|---|
| `bin/cc-classify` | THE BRAIN — 1-of-10 idle-cause per session from durable signals | **launchd-scheduled** (invoked by cc-reaper every 300s) + manual | cc-sessions (registry), jq, git, ps, transcript JSONLs, team configs | `tests/cc-classify.bats` (18 cases) GREEN via /ship suite; ran live | b + c | G-P3-5,6 |
| `bin/cc-reaper` | ACTUATOR DRIVER — sweep, gate, checkpoint, delegate close | **launchd-scheduled** `com.chrisren.cc-reaper` @300s (LOADED, running; log shows 5-min sweeps reaping 0) | cc-classify, cc-teardown, hooks/teammate-checkpoint.sh, git | `bin/cc-reaper selftest`→`tests/cc-reaper.bats` (13 RED-proofs); `reaper-e2e.sh` | b + c | G-P3-1,3 |
| `bin/cc-teardown` | FINAL GATE + kill/close + re-observed effect-verify | **prompt-only** (live desk) OR called by cc-reaper; NEVER raw-wired (C10) | cc-teardown-safety-gate.sh, cc-sessions, it2, ps, git | `cc-teardown --selftest` (12 branches) GREEN | b + c | — |
| `bin/cc-teardown-safety-gate.sh` | G-a work-safe + G-b positive-done decision (pure, no side-effect) | **library** (called by cc-teardown) | git, jq | `--selftest` (7 RED-proofs) GREEN | c | — |
| `bin/cc-sessions` | REGISTRY SSOT — live sessions across 4 accounts; lazy stale-sweep | **hook-fed** (session-register.sh SessionStart writes rows); read by classify/teardown | cc-registry/*.json, it2, jq | live (84 rows, ~18 live/sweep) | b | G-P3-1,6 |
| `bin/cc-deathwatch-kqueue` | event-INSTANT death signal (kqueue NOTE_EXIT) | **DEAD** (only consumer is lead-deathwatch.sh, itself unwired) | python3, ps | `lead-deathwatch --selftest` (e2e real-child) GREEN | (c intended) | G-P3-7 |
| `scripts/lead-deathwatch.sh` | L1 orchestrator: death→capture-WIP+page (never respawn) | **DORMANT** — no production invoker; lead-supervisor is page-only, doesn't call it | cc-deathwatch-kqueue, cc-notify, git plumbing | `--selftest` GREEN (L1-b/c/d/e); disk records are all selftest artifacts (2026-07-14 21:06) | (c intended) | G-P3-7 |
| `scripts/reap-guard.sh` | R-a birth-grace / R-b effect-read / R-c abstention for TeammateIdle | **DORMANT** — built+GREEN but NOT wired into the live hook; `~/.claude/reap-guard/` EMPTY (0 live decisions) | git, jq | `--selftest` (6 RED-proofs) GREEN; `reaper-safety-gate.sh` GREEN | (b intended) | G-P3-2 |
| `scripts/reaper-safety-gate.sh` | RED-provable "ready" bar for reap-guard | **manual** (build gate) | reap-guard.sh | self (GREEN: 1 met) | c | — |
| `scripts/reaper-horizon-lint.sh` | constrains: no reaper horizon < supervisor-sweep×10 (=6000s) | **manual** (lint; no CI runner) | grep over declared source | self | c | G-P3-8 |
| `scripts/reaper-e2e.sh` | REAL orphan reproduce+reap on live iTerm2 (throwaway window) | **manual** (acceptance) | it2, cc-reaper, cc-teardown, git | self (2 scenarios) | c | — |
| `scripts/team-orphan-reaper.sh` | TEAM-level: archive dead team dirs + auto-deny stale perms | **launchd-scheduled** `com.claude.team-orphan-reaper` @600s (LOADED, running; log "3 live, 0 archived") | ~/.claude/teams, ~/.claude/watchdog, jq | none (no .bats) | b | G-P3-4,9 |
| `hooks/teammate-auto-shutdown.sh` | LIVE TeammateIdle reaper (checkpoint→defer×3→close pane) | **hook-enforced** (settings.json:834-839 TeammateIdle, timeout 5) | teammate-checkpoint.sh, it2 | none inline | b | G-P3-2 |
| `launchd/com.claude.team-orphan-reaper.plist` | team-reaper standing loop | **installed+loaded** (~/Library/LaunchAgents) | team-orphan-reaper.sh | live | c | G-P3-9 |
| `docs/activation/autonomous-reaper.plist` | cc-reaper standing loop (the 36f9d64 PATH fix lives HERE) | **installed+loaded** as com.chrisren.cc-reaper.plist (1521B, 2026-07-17) | cc-reaper | live (log active) | c | — |
| `docs/AUTONOMOUS-REAPER-ACTIVATION.md` | C10 runbook — cc-reaper activation (DONE by operator) | doc | — | n/a | c | G-P3-5 |
| `docs/REAPER-SAFETY-ACTIVATION.md` | C10 runbook — reap-guard wiring (NOT DONE) | doc | — | n/a | b | G-P3-2 |
| `scripts/session-lifecycle-safety-gate.sh` | cc-reaper build gate (RP-a/b/c/d+CL+TD) | **manual** | cc-classify, cc-reaper, cc-teardown | self (GREEN 3 met) | c | G-P3-5 |

Goal legend: a=exhaustive-task-discovery, b=parallel-session-mgmt, c=self-renewal.

---

## 2. Mechanism (end-to-end, file:line)

### 2.1 Two independent reaper systems (NOT redundant — complementary; answers Q3)

- **Session reaper** = `cc-reaper` (launchd `com.chrisren.cc-reaper`, 300s,
  `docs/activation/autonomous-reaper.plist:22`). Granularity: an individual idle SESSION
  (iTerm2 pane). Actuation: classify → gate → checkpoint → `cc-teardown` (kill+close). This
  is the NEW autonomous lifecycle reaper.
- **Team reaper** = `team-orphan-reaper.sh` (launchd `com.claude.team-orphan-reaper`, 600s,
  `launchd/com.claude.team-orphan-reaper.plist:16`). Granularity: a TEAM-CONFIG dir
  (`~/.claude/teams/<name>/`). Actuation: `mv` dead team → `_archive`
  (`team-orphan-reaper.sh:46-66`) + append a `permission_response deny` envelope to unblock a
  teammate whose lead is unresponsive >5min (`:68-108`). It **does NOT close panes**
  (`:135` "verify no iTerm panes alive … skip for v1") and does NOT classify idle-cause.
- **Liveness sources DIVERGE**: team-reaper reads `~/.claude/watchdog/<sid>.pid`
  (`team-orphan-reaper.sh:34-44`); cc-reaper reads the `cc-registry/` roster via cc-sessions.
  Two rosters that can disagree (G-P3 cross-beat note).
- **reso reap-rule divergence** (memory `reference-landing-safety-tooling.md:50-53`): this is
  `scripts/land-lock.sh`'s rule (the LANDING mutex, a THIRD reaper, out-of-beat), NOT the
  session/team reaper — a LIVE lock-holder is NEVER reaped even past TTL (reso reaps
  live-past-TTL for load; infra won't — a dropped commit costs more than a wedged lock). Same
  philosophy cc-reaper encodes (never-reap-the-living), different subsystem. The brief's
  framing conflates them; the divergence does not touch cc-reaper/team-orphan-reaper.

### 2.2 cc-classify decision tree (the 10 causes, in evaluation order)

Env thresholds: `IDLE_S=300` (active cutoff, `:34`), `COORD_HANG_DEAD_REAP_S=7200`
(coordination-abandoned horizon, `:35`), `TRUNK=origin/main` (`:39`).
Order matters — first match wins (`classify_entry` `:181-273`):

1. pid dead (`kill -0` fails, `:190`) → **crashed** [never-reap]
2. structured usage-cap in last 60 JSONL records (`isApiErrorMessage==true` AND text ~
   `session limit|weekly limit|…`, `recent_api_limit :70-78`, gate `:198`) → **rate-limited** [never-reap]
3. last-assistant-ts < 300s (`:201`) OR no readable ts at all (`IDLE<0` fail-safe `:205`) → **active** [never-reap]
4. fired a `/handoff` (tool_use grep for `handoff-fire.sh|/handoff|--recycle`, `handoff_fired
   :80-91`) AND a LIVE successor (distinct sid, same cwd, started ≥ this session's last turn,
   pid alive; `find_successor :93-104`) → **handed-off-lead** [REAPABLE]
5. cwd is a worktree path (`is_worktree_session :127-130`) → **finished-teammate** [REAPABLE]
6. team config names this sid as lead AND has ≥1 real member (beyond in-process `team-lead`
   placeholder; `team_has_real_members :160-168`):
   - a member is a live `--agent-name` proc (`team_live_member :147-158`) → **owned-wait** [never-reap]
   - else idle≥7200s AND a live co-cwd session owns the tree (`cocwd_live :106-117`) → **coordination-abandoned** [REAPABLE]
   - else → **coordination-hang** [never-reap, surface]
7. work landed (clean tree AND 0 ahead of origin/main; `work_landed :170-177`) → **finished** [REAPABLE]
8. own commits landed (0-ahead) but tree dirty AND live co-cwd sibling owns it
   (`ahead_zero :119-125` + `cocwd_live`) → **finished-shared-review** [never-reap, surface]
9. default (idle+alive, not landed / no real team) → **owned-wait** [never-reap]

Reapable set (4): handed-off-lead, finished-teammate, finished, coordination-abandoned.
Never-reap set (6): active, rate-limited, owned-wait, coordination-hang, crashed, finished-shared-review.

### 2.3 Detector inputs / thresholds / FP / FN / reap-action table

| idle-cause | detector inputs | threshold | false-POSITIVE path | false-NEGATIVE path | reap action |
|---|---|---|---|---|---|
| crashed | registry `pid` + `kill -0` | pid dead | pid recycled to a stranger reads "alive" → NOT crashed (safe miss) | a live-but-hung claude reads alive → never "crashed" | NEVER reap; surface only — **but no consumer (G-P3-3) and no pane-closer (G-P3-4)** |
| rate-limited | last-60 JSONL `isApiErrorMessage` + text match | any in tail-60 | a STALE limit msg in the tail after manual resume → still "rate-limited" (over-conservative, never-reap) | limit msg scrolled past 60 lines → misses; falls to idle causes | NEVER reap (resumes on reset) |
| active | last-assistant-ts (jq, excl. sidechain+api-error) vs NOW | idle<300s OR ts unreadable | unreadable transcript → "active" forever (G-P3-6) | clock skew / stale NOW env | NEVER reap |
| owned-wait | pid alive + (live team member OR not-landed default) | idle≥300 | — | a genuinely-done solo w/ unlanded WIP stays owned-wait (correct, never-reap) | NEVER reap (the safe default bucket) |
| coordination-hang | team config + real members + NO live member | idle≥300, <7200 | implicit solo-team (every session has a config) once collapsed ALL here — fixed by real-members gate (`:160-168`, 95a6618) | a real hang whose member proc lingers as zombie reads "owned-wait" | NEVER reap; surface — **no consumer (G-P3-3)** |
| coordination-abandoned | above + idle≥7200 + live co-cwd owner | idle≥7200s | co-cwd owner is a same-cwd sibling doing unrelated work → still reaps the zombie (safe: committed work in git, WIP checkpointed) | no live co-cwd owner → stays coordination-hang forever | REAP iff ALSO landed (reaper gate) |
| handed-off-lead | `/handoff` tool_use grep + live successor (sid≠, same cwd, newer, pid alive) | idle≥300 | bridge-session record misread as handoff → guarded out (`:84-91`, test `:84`) | successor in a DIFFERENT cwd (rare) → no match → owned-wait | REAP iff landed+settle |
| finished-teammate | cwd matches `/tmp/wt-*|*/.worktrees/*|…` | idle≥300 | a human working in a wt-* dir idle >5min → "finished-teammate" (then reaper's landed+settle gates hold) | worktree at a non-matching path → misses | REAP iff landed+settle |
| finished | clean tree AND 0-ahead-of-trunk | idle≥300 | tree clean because work pushed elsewhere but session still needed → reaped (mitigated: idle≥600 settle + cc-teardown re-gate) | any dirt/ahead → not finished (stays owned-wait) | REAP iff settle |
| finished-shared-review | 0-ahead + dirty + live co-cwd sibling | idle≥300 | sibling's dirt attributed correctly; own WIP could exist → NOT auto-reaped by design | — | NEVER auto-reap; surface for confirm — **no consumer (G-P3-3)** |

### 2.4 cc-reaper gates (defence-in-depth; `bin/cc-reaper:82-135`)

A reap requires ALL, independently: (1) cause ∈ `REAPABLE_RE`
(`^(handed-off-lead|finished-teammate|finished|coordination-abandoned)$`, `:41`); (2)
`work_landed==yes` re-checked post-classify (`:104`, race guard `:118`); (3) idle ≥
`SETTLE_S=600` (`:39,:107` — self-close gets first chance, reaper is BACKSTOP); (4)
checkpoint-first to `refs/wip/<name>/LAST` before any close (`:117`, `checkpoint_first
:58-64`); (5) `cc-teardown` re-runs its OWN gate (double-gate `:124`). A post-classify
dirty/ahead tree → ABORT with WIP already checkpointed (`:118-120`). Dry-run is the default
(`sweep` without `--reap`, `:83`). Trusts cc-teardown's exit (10 DEFER / 2 REFUSE / 5 FAIL)
and does NOT override (`:129`).

### 2.5 cc-teardown final actuator (`bin/cc-teardown`, 6 steps, fail-closed)

RESOLVE (fail-closed on unknown/self/--self → REFUSE 2, `:177-187`); IDEMPOTENT short-circuit
(dead pid + absent pane → 0, `:190-196`); SAFETY GATE delegated to
cc-teardown-safety-gate.sh (G-a clean+0-ahead, G-b caller-asserted `--done-evidence` never
inferred → DEFER 10 / REFUSE 2, `:198-209`); tty-exclusivity runtime guard (foreign proc on
pane tty → DEFER 10; tty indeterminate → fail-closed DEFER, `:211-222`); ACT both legs
(TERM→poll→KILL then it2 close, `:224-238`); EFFECT-VERIFY re-observed (proc gone via
pid/lstart-recycle AND pane absent from FRESH list; else FAIL-LOUD 5, `:240-257`). The
blind-enumerator fix: a 0-length it2 list = INDETERMINATE (return 2), never false-absent
(`pane_present :104-114`) — a machine running cc-teardown always holds ≥1 pane, so 0
enumerated == blind enumerator, not "no panes." Every branch writes an outcome record
(`record :77-92`).

### 2.6 L1 death-watch (Q4: DEAD)

`cc-deathwatch-kqueue` (python, kqueue EVFILT_PROC/NOTE_EXIT, `{pid,start}` recycle guard at
arm time → emits exit|recycled|gone) is consumed ONLY by `lead-deathwatch.sh`
(`kq_helper :45-51`), which turns a DEATH into capture-WIP-to-`refs/deathwatch/`+page (never
respawn). **lead-deathwatch.sh has no production invoker**: grep of bin/hooks/scripts/
commands/settings found only a COMMENT in cc-respawn:82 and test-gate references
(never-stuck-gate, wait-safety-gate). The running daemon `lead-supervisor.sh` (pid 17867,
`com.claude.lead-supervisor` RunAtLoad) is **page-only** — "NEVER reaps/closes anything"
(`lead-supervisor.sh:60`, `:110`) — and does NOT call lead-deathwatch/cc-classify/cc-reaper.
Disk proof: `~/.claude/deathwatch/` holds only 2026-07-14 21:06 artifacts whose labels
(bmember/goneone/real/recyc/none) are exactly the `--selftest` fixtures → L1 has NEVER run in
production. Both files are build-complete + selftest-GREEN but DORMANT.

---

## 3. Gaps & fragilities

| id | file:line | class | sev | failure scenario | fix sketch |
|---|---|---|---|---|---|
| G-P3-1 | cc-sessions registry ↔ memory desk-spawned-…:41-49 | FM2/24x7 | P1 | Some handoff-fire'd spawn modes are NOT enumerated by cc-sessions → cc-reaper/cc-teardown blind to them (verified: cc-teardown REFUSE "unknown target" on fired peer 59664; cc-reaper never listed it). The desk's dominant spawn class can linger idle holding pane+quota with the reaper reporting "healthy." (Empirically PARTIAL — wt-pool-3 worktree sessions DO enumerate live, so mode-specific not total.) | ensure every handoff-fire spawn registers via SessionStart (session-register.sh) with a paneUUID+name the reaper can resolve; add a reaper self-check that enumerated-count ≈ live-pane-count and surface the delta |
| G-P3-2 | hooks/teammate-auto-shutdown.sh (no reap-guard call) + REAPER-SAFETY-ACTIVATION.md | FM2-inverse | P1 | The birth-grace fix (reap-guard R-a/b/c) is built+GREEN but NOT wired into the live TeammateIdle hook (hook last-touched 2026-06-28, before reap-guard 2026-07-14; `~/.claude/reap-guard/` empty). The premature-reap-of-a-just-born-teammate incident (clean tree at 3-4min ≡ finished) remains reproducible. Mitigated: checkpoint-first + 3-defer backstop → wasted spawn, not data loss. | run the C10 activation: insert the `reap-guard.sh decide` gate before the hook's close (REAPER-SAFETY-ACTIVATION.md:30-39); pass spawn-epoch from the registry/team config |
| G-P3-3 | bin/cc-reaper:101,108 (say→stdout/log only) | FM2/24x7 | P1 | Never-reap-but-surface causes (coordination-hang, crashed, finished-shared-review, rate-limited) are printed to stdout + cc-reaper.log and NOTHING consumes them. A hung/crashed/needs-confirm session lingers silently; the desk is never told. This is FM2's "surfaced ≠ acted." | emit surfaced causes as a cc-notify page to the desk pane (like lead-supervisor's page path), or write a desk-readable board row the wave-monitor consumes |
| G-P3-4 | bin/cc-classify:18 + team-orphan-reaper.sh:135 | FM2/24x7 | P1 | A **crashed** (dead-pid) session's iTerm2 pane has no automated closer: cc-reaper never-reaps crashed; team-orphan-reaper skips pane-close ("v1"); cc-teardown's idempotent path only fires if invoked. Registry row swept at 24h but the orphan pane persists indefinitely → pane/quota leak over a 24/7 week. | add a crashed-cause branch that invokes cc-teardown on the dead pane (idempotent path already handles dead-pid safely: exit 0 ALREADY-GONE once pane closes) |
| G-P3-7 | scripts/lead-deathwatch.sh (no invoker) | 24x7 | P1 | L1 never-wait-on-the-dead (kqueue capture+page on out-of-band teammate death) is built+GREEN but DORMANT (no production driver; lead-supervisor is page-only). A teammate dying out-of-band fires no checkpoint+page → orphaned WIP only recoverable via cc-reaper's later checkpoint-on-reap (which needs the session enumerable + idle). | wire `lead-deathwatch.sh --once` into the lead-supervisor daemon cycle (it already runs every interval), or a dedicated launchd job arming the watch-list from the registry |
| G-P3-6 | bin/cc-classify:57,205 | FM2 | P2 | `find -maxdepth 2 -name "$sid.jsonl"` across 4 roots; a transcript deeper or in a 5th root is unreadable → `IDLE<0` → "active" **permanently** (immortal never-reap entry). Safe against false-reap but a slow leak of unreapable rows. Live-observed one `idle=-1` fail-safe entry (93EA2A3C). | raise maxdepth / add roots defensively; after N consecutive unreadable classifications for a live pid, surface as "unclassifiable" rather than silently "active" |
| G-P3-5 | bin/cc-classify:10-18 + docs/AUTONOMOUS-REAPER-ACTIVATION.md:4 + session-lifecycle-safety-gate.sh | none(doc) | P2 | Docs say "7-cause"/list 8 in the CAUSES block; code emits 10 (missing coordination-abandoned + finished-shared-review). Stale docstring → a future maintainer under-counts the never-reap set. | update the CAUSES header block + activation doc to 10 causes with the reapable/never-reap split |
| G-P3-8 | (no .git/hooks/pre-commit, no CI) | 24x7 | P2 | No standing gate-runner: the reaper .bats + safety gates run ONLY via `/ship`'s in-lock whole-suite gate. A reaper regression can reach main if a session ships with a partial gate (the exact 2026-07-17 partial-gate incident, memory reference-landing-safety-tooling.md:37-41). | add a pre-push hook or launchd nightly that runs `bats tests/` + the safety gates and pages on red |
| G-P3-9 | launchd/com.claude.team-orphan-reaper.plist:29-31 | none(latent) | P2 | team-orphan-reaper PATH is `/opt/homebrew/bin:…` with NO `~/.claude/bin`. Fine today (jq-only) but if it ever calls a cc-* tool it silently exits 127 — the EXACT 36f9d64 class of bug, still latent in this sibling plist. | prepend `$HOME/.claude/bin` to the plist PATH now, defensively (parity with the cc-reaper plist fix) |

---

## 4. Task candidates

| id | action | acceptance criterion | depends-on |
|---|---|---|---|
| T-P3-1 | Close the fired-peer enumeration gap: make handoff-fire spawns register in cc-registry with a reaper-resolvable paneUUID+name | `cc-reaper sweep` lists a freshly handoff-fire'd peer; `cc-teardown <its-name>` resolves (no "unknown target") | G-P3-1 diagnosis of which spawn mode skips registration |
| T-P3-2 | Activate reap-guard: wire `reap-guard.sh decide` into teammate-auto-shutdown.sh before its close | spawn a teammate, first within-grace TeammateIdle logs a `grace-held` DEFER in `~/.claude/reap-guard/`, not a reap | REAPER-SAFETY-ACTIVATION.md; operator C10 edit |
| T-P3-3 | Give surfaced-not-reaped causes a consumer: cc-reaper pages the desk on coordination-hang/crashed/finished-shared-review | a hung session produces a cc-notify to the desk pane within one sweep | G-P3-3; desk pane resolution |
| T-P3-4 | Add a crashed-pane closer (cc-teardown idempotent path on dead-pid sessions) | a crashed session's pane is closed within N sweeps; record shows ALREADY-GONE/TEARDOWN | T-P3-3 (or standalone) |
| T-P3-5 | Wire L1 lead-deathwatch --once into the running lead-supervisor cycle | killing a watched teammate proc produces a `~/.claude/deathwatch/death-*.json` + a page in production (not just selftest) | G-P3-7; lead-supervisor cycle hook |
| T-P3-6 | Doc + PATH polish: 10-cause docstring; prepend ~/.claude/bin to team-orphan-reaper.plist | header lists 10 causes; plist PATH includes the symlink dir | none |

---

## 5. Cross-beat dependencies

- **Registry (P8/cross)**: cc-classify + cc-teardown depend entirely on cc-sessions/cc-registry
  correctness. G-P3-1 is really a registration-coverage bug owned by whatever beat covers
  session-register.sh / handoff-fire spawn. Two liveness rosters exist (cc-registry vs
  `~/.claude/watchdog/`, used by team-orphan-reaper) — a reconciliation-beat concern.
- **Supervisor beat**: lead-supervisor.sh (page-only, running) is the natural host to (a)
  consume cc-reaper's surface (G-P3-3) and (b) drive lead-deathwatch --once (G-P3-7). Whoever
  owns the supervisor should absorb T-P3-3 + T-P3-5.
- **Handoff/fire beat**: G-P3-1 + the self-retire-vs-notify-back discipline
  (desk-spawned-…:30-49) — the reaper is the "deterministic backstop" the memory names; its
  fired-peer blindness undpercuts that promise.
- **Checkpoint beat**: cc-reaper + lead-deathwatch both call the same git-plumbing checkpoint
  (hooks/teammate-checkpoint.sh / refs/wip / refs/deathwatch) — a shared dependency.

---

## 6. Adversarial self-pass (what a hostile reviewer would say I missed — then covered)

1. "You called cc-deathwatch DEAD from a grep — did you check cc-wait/cc-run/cc-respawn arm
   it?" → Grepped all three; only cc-respawn matches, and it's a COMMENT (cc-respawn:82). No
   runtime arm. Confirmed dead. Covered.
2. "cc-classify says 7 causes; you say 10 — recount." → Counted emitted CAUSE assignments in
   `classify_entry`: crashed, rate-limited, active(×2 sites), handed-off-lead,
   finished-teammate, owned-wait(×2), coordination-abandoned, coordination-hang, finished,
   finished-shared-review = 10 distinct. The "7" is the stale header (G-P3-5). Covered.
3. "Is the running cc-reaper actually SAFE given reap-guard is unwired?" → They are DIFFERENT
   reapers. cc-reaper (session, launchd, quadruple-gated) is safe and correctly reaping 0.
   reap-guard protects the SEPARATE TeammateIdle hook and is dormant (G-P3-2). Distinguished.
4. "You claim fired peers are invisible but the log shows 18 classified." → Verified live:
   wt-pool-3-* worktree sessions DO enumerate + classify (saw a live finished-teammate). So
   G-P3-1 is mode-specific, not total — downgraded from P0 to P1, with the P0 risk flagged.
   Covered by empirical run, not assumption.
5. "The 300s classify-idle vs 600s reaper-settle — is there a confusing double threshold?" →
   Intentional: classify uses 300s to LABEL a candidate; reaper requires idle≥600s to ACT
   (self-close's 10-min window first). classify runs synchronously inside each sweep so idle
   is fresh. Not a gap.
6. "coordination-abandoned reaps a zombie — could it strand the live co-cwd sibling's work?"
   → No: reap is landed-gated (reaper step 2), committed work is in git, WIP is
   checkpoint-first, and the sibling KEEPS the working tree (only the idle pane closes). Safe
   by construction (cc-classify:242-243).
7. "What closes a crashed session?" → Nothing automated (G-P3-4) — the reviewer's strongest
   catch; promoted to an explicit P1 gap + T-P3-4.

Gaps this pass ADDED that the first sweep missed: G-P3-3 (no surface consumer), G-P3-4
(no crashed-pane closer), G-P3-6 (immortal-active on unreadable transcript).

---

## 7. Uncertainties (empirical vs theoretical)

- (theoretical) G-P3-1 severity: I confirmed worktree-pool sessions enumerate live and cite
  the memory's verified 59664 non-enumeration, but did NOT reproduce a fresh handoff-fire →
  reaper-miss this session. The exact spawn mode that skips registration is unconfirmed
  (candidates: cold `--worktree` fire, `--recycle` pane reuse, or a launcher that bypasses
  SessionStart). T-P3-1 needs that diagnosis first.
- (empirical) Both reapers are loaded + sweeping (launchctl + logs). (theoretical) Whether the
  operator INTENDED reap-guard to remain unwired vs it being an unfinished C10 step — the
  REAPER-SAFETY-ACTIVATION.md wording implies "not done yet," not "declined."
- (theoretical) `tests/cc-reaper.bats` + `tests/reap-guard.bats` full bodies unread; I relied
  on the embedded selftest harnesses (read in full) which the .bats files exec. RED-proof
  counts (13 / 6) are from the docstrings, not a re-run this session.
- (empirical) team-orphan-reaper + cc-reaper use DIFFERENT liveness rosters; whether they ever
  disagree in practice (a session live in one, dead in the other) was not measured.
