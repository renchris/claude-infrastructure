---
status: in-progress
---

# Infra Perfection Pass — 2026-07-25

Scope (frozen): Machine-lag resolution + claude-infrastructure perfection: operator platter for
deploy-lag/panes/reboot; 11-axis audit → implement dead-code removal, unbounded-growth GC, plist
SSOT + plutil guard, bash-log session attribution, orphan-process reaper follow-ups (incl. the
24722de process-witness OR-signal) — Agent Team on `fix/infra-perfection`, gate-green, landed via
project-local /ship. (DoD store: ~/.claude/autonomy/dod/3cca03ed68356913.md)

Context: fired by /goal "investigate why our computer is lagging and slow, and resolve; investigate
if any come from claude-infrastructure; improve to 100th percentile … eliminate tech debt and dead
code … no opportunity for bugs of abrupt session closures or memory leaks."

## Phase 0 — Agent Team Orchestration  (MANDATORY FIRST SECTION)

Roster (draft — refined at spawn; ≤6 concurrent, briefs ≤150 lines, pre-grepped ranges,
verbatim stop-on-issue clause, no investigate-language):

| Teammate | Owns | Depends on |
|---|---|---|
| tp-hygiene | 01 Tier-1 + 02 Tier-A/B deletions (quarantine protocol per audit10) + inverse-orphan versioning (4 real agents + 3 untracked hooks + cc-thread + bump-models live→repo + model-classification live→repo) + install legs (desk-register, agents/, sync.sh list) + plan-update 2 defects + kimi bats coupling | audit10 ✓ (landed) |
| tp-launchd | 05 REPO-IZE list (lead-supervisor #1, screenshot-clipboard pair, cc-reaper move+rename, watch-2118 pending ◆) + scripts/launchd-parity-lint.sh (label-keyed live==SSOT, auto-globbed by nightly) + 09-activator .claude-next fix + 05-ship-rail repo copy + claude-code-archive SSOT refreshes (separate repo, local commit) | audit05 ✓ |
| tp-hooks | 09 D-2 (dedup intra-object + apply ×5) + D-3/D-9 (log-bash field+sid+ts; plan-version-commit sid) + D-4 (jq guards + loud abstain) + D-5 (timeouts) + D-8 (path-keyed backup prune) + D-11 (session-continue telemetry) + D-14 (dod-persist manual) + D-10 GC (cp-*.count, refs/checkpoints retention) + rotation-target additions from 09§3.4 | audit09 ✓ |
| tp-closure-a | 07 G1 (classify lib-miss FAIL CLOSED + deploy-parity existence check) + G2 (gate-skip ⇒ DEFER + new teammate-auto-shutdown.bats) + G3 (empty-answer split, unreadable ⇒ fail-closed) — reaper discipline: every change narrows, RED-proof each | audit07 ✓ |
| tp-closure-b | 07 G4 (ci_/ce_ parity test + safer-direction ce_ upgrade) + G6 (TeammateIdle post-wake cooldown R-e) + G8 (process-witness OR-KEEP on orphan-reaper) + G9 (HOLD_DISABLE loud) + argv-regex parity test | audit07 ✓ |
| tp-gates | 08-driven nightly-green fixes + session-lifecycle-safety-gate into COMPONENT_GATES + premortem --selftest label + model-config SSOT reconcile (with 08 evidence) + D-12 SubagentStop v1 hook (telemetry + report-persist) | audit08 (pending) |

Wave order: spawn tp-hygiene/tp-launchd/tp-hooks/tp-closure-a/tp-closure-b immediately (inputs
landed); tp-gates after audit08 lands. Growth-GC items beyond 09§3.4 fold into tp-hooks or a
follow-up wave slot after audit03 lands. Cap 6 concurrent.

Dependency graph: tp-deletions blocked by audit10 verdicts; others independent. Merge order:
smallest-diff first, serialized, rebase+ff-only onto fix/infra-perfection; gate per merge.

Worktree: /tmp/wt-infra-perfect (branch fix/infra-perfection, base origin/main@14fe28e).
Land: project-local /ship (standing-land authorized in this repo). Deploy: OPERATOR platter.

## Findings ledger (filled per audit report)

### Machine-lag triage (lead, MEASURED 01:0x)
- M1 Max 10c/64GB, 13d uptime, load ~7; swap 2.8/4GB; iTerm2 63%CPU/4GB RSS + WindowServer 42% (top
  UI-lag pair); claude fleet 33 procs / 15.2GB RSS (several 2-9d old); 24 panes / 25 ttys.
- Spotlight innocent (dot-dirs unindexed, mdfind=0). Disk 5TB free. No thermal throttling.
- Shared checkout 24 commits behind origin/main → session-closure hardening landed but NOT live;
  lead-supervisor daemon running since Jul-23 (pre-fix code) — needs kickstart post-deploy.
- 2026-07-25 00:55 incident: a peer session's `plutil -extract StartCalendarInterval json <f>`
  (no -o) destroyed all 5 calendar plists; RESTORED 01:10 from loaded launchd defs + repo SSOT
  (memory: plutil-extract-clobbers-input). Fragments + captures: scratchpad/launchd-rescue/.
- cc-reaper sweep: 0 safe candidates; 2 surfaced finished-operator (panes 52DCAB5E pid 31459, <!-- pane-id-lint:allow: historical sweep record, not a send target -->
  8D4878D1 pid 87542); fleet is operator-owned panes → platter, not auto-kill. <!-- pane-id-lint:allow: historical sweep record, not a send target -->

### 01 dead-scripts (landed)
- Tier-1 safe-delete: scripts/auto-revert-getAppState-patch.sh · scripts/record-version.sh ·
  scripts/current-session-plan.sh · scripts/plan-phase-scan-tests/ (runner+fixtures) ·
  ~/.claude/scripts/watch-getAppState-fix.sh (dangling live symlink; live-layer only).
- Tier-2 (owner nod): kimi-frontend-ab.sh + tests/kimi-frontend-ab.bats (delete TOGETHER or bats
  reds); settings-dedup-stop.sh → KEEP + wire/document (class recurs; install.sh still additive).
- Tier-3 wire-not-delete: bind-gate-e2e, boundary-hook-e2e, reaper-e2e, test-overwrite-guard
  (+ handoff-selfclose-e2e UNSURE) → manual-or-weekly e2e lane (nightly skips *-e2e by design :99).
- Repo-ize 5 plists w/o SSOT: com.claude.lead-supervisor, com.chrisren.restic-claude-archive,
  com.chrisren.watch-claude-code-2118-hold, com.chrisren.verify-2114-archive, com.chrisren.cc-reaper.
- Defects: premortem-gate has NO arg parsing — nightly's `--selftest` label is a lie (full live body
  runs; how p8/telemetry e2e execute at all); session-lifecycle-safety-gate.sh header claims
  COMPONENT_GATES membership but absent from never-stuck-gate.sh:57 list; nightly RED 6+ nights
  with no reader (needs escalation wiring); cc-upgrade-gate.sh landed-undeployed (symlink checklist).
- Open Q: ~/.claude-next/scripts = stale FULL COPY frozen 2026-07-18 (mirror drift — does anything
  execute from it? deploy-parity-assert relevance).

### 02 dead-bin (landed — inverse orphans > dead code)
- BROKEN-DEPLOY: bin/desk-register absent from ~/.claude/bin AND ~/bin → live /desk command calls a
  nonexistent binary (install.sh has no leg). FIX: install leg + link.
- INVERSE ORPHANS (version these, higher value than deletions): the 4 REAL live agents
  (deep-research{,-sonnet}, frontier-derivation, research-decomposition-critic) have NO repo copy;
  19/29 live skills unversioned; 3 wired hooks untracked (see 09 D-6/7); ~/.claude/bin/cc-thread
  unversioned; bin/claude-bump-models live NEWER than repo (repo can't bump frontier; in NO
  install/sync list) → sync live→repo + add to legs; templates/model-classification.json stale
  orphan (0 readers; live-regression hazard) → replace content with live; model-config.yaml TWO
  SSOTs split-brain (repo 415 ln w/ settings_floor NEWER vs live 402; effort-parity-assert reads
  repo, CLAUDE.md names live) → reconcile with 08 evidence (likely the claude-lint-models RED).
- Tier-A deletes: usage/ (untracked litter → quarantine), install.sh:204-231 dead rules/ leg (+ rm
  empty ~/.claude/rules), commands/amplify-build.md, commands/deploy-status.md (broken invocation).
- Tier-B (F-gate PASS): agents/*.md 4 dead repo files — replace with the 4 REAL ones + install leg;
  fix hooks/agent-teams-enforce.sh:121 allowlist + README:256 + skills/plan-update/SKILL.md:303;
  commands/cleanup-team.md (actively WRONG on 2.1.183 runtime — TeamDelete/paths) → delete.
  KEEP: statusline-debug.sh + 5 generic commands (zero cost, operator may type them).
- DORMANT-7 (cc-idl cc-wait cc-run cc-respawn cc-route cc-bind cc-digest): NOT deletable (gates
  attest them); non-invocation problem. cc-idl 93% unsealed ledger = ◆ operator question (wire a
  sealer tick or retire the guarantee). Backlog: consolidations (idl-inert-check lib ×4 copies,
  cc-common.sh, comms-family collapse, plan-update⊂plan-conventions merge) — too big this pass.
- sync.sh degraded: bin list omits claude-kimi + claude-bump-models (the exact drifters) → add;
  auto-commit behavior noted (violates atomic-commit rule) — flag, minimal change only.
### 03 growth (landed — top surfaces are OUTSIDE ~/.claude; full report on disk)
- /private/tmp/claude-501 = 10.67GB @ ~810MB/day (reboot-only bound; 3 sessions hold 10.8GB media);
  ~/.npm/_cacache 11.2GB no GC; sibling config dirs 4.09GB transcripts (idle-dir cleanup lag);
  ~/.claude-versions 853MB + 1.13GB parallel installs (◆ platter, rollback-floor caution).
- Rotation job healthy but covers 3/26 files; 10 ranked misses (teammate-checkpoint 13.6MB #1).
- Systemic gap named: reaper-horizon-lint has floor, NO DUAL — nothing fails when a state dir has
  no reaper (pages/comms-alarms/push-records class, ~1100 dirents, zero rm sites for comms-alarms).
- Fix list #1-10 effort-graded (→ tp-growth wave-2): scratchpad reaper (≥6000s horizon, live-gated),
  npm cache verify, ROTATE_TARGETS 3→13, worktree-gc.sh (→tp-worktree-gc), autonomy age-reaps ×6,
  session-index.db retention+VACUUM (51.7MB indexes 5453 sessions vs ~30d transcripts), plan-history
  keep-policy (superlinear), version-tree reaping (◆), growth-coverage lint (THE class-stopper),
  mailbox/watchdog/state GC. NOT-list honored (archives static, decisions/backlog durable ledgers,
  backups reference-quality).
- Corrections: sweep-daemon.log premise wrong (0 bytes; real sink session-index.log); 'x' session
  not reproduced (transient); cc-registry retention VERIFIED correct (6d rows = genuinely live).
### 04 proclife (landed — machine leaks IMMORTAL SESSIONS, not orphans)
- owned-wait = never-reap AND never-surface terminal bucket (cc-classify:469 fallback; cc-reaper:91
  excludes from SURFACE_PAGE_RE): 13 sessions, 5 idle 47-222h, ~3.5GB — THE accumulation engine.
  landed=no ⇒ DEFER silent+permanent (cc-reaper:417). Pane-less claude.exe trees (~3GB: daemon/
  bg-spare clusters, hosted --fork-session, auth-login orphan ppid-1) invisible to ALL reapers BY
  CONSTRUCTION (registry-only resolution, live_pane_count lacks -A + claude.exe match). Watchdog
  bare kill -0 (:226) → pid-reuse immortality + 3049 phantom crash exits (OWNER_PAT fix exists one
  file over in lead-supervisor:43). team-orphan-reaper covers 1/4 config roots, skips config-less
  dirs (9 zombies since Jun-10), archives live members' inboxes (665 msgs to a dead pane), kills
  nothing. Blind-spot Δ passes VACUOUSLY. Upstream bg knobs (CLAUDE_CODE_DISABLE_BACKGROUND_TASKS
  et al.) all unset — deliberate per-launcher decision, not a blind flip (◆ note).
- G1-G11 all surface-only/fail-closed (→ tp-proclife wave-2, AFTER closure-a/b merge — file
  overlap): owned-wait idle-horizon PAGE (24h default), defer-N page w/ exact ▶ teardown cmd,
  watchdog-stamped team-member marker (narrow kind-gated auto-reap), pane-less inventory rows
  (kind:pane-less, never reapable), live_pane_count -Ao + claude.exe + negative-Δ page, orphan-
  reaper multi-root + configless-mtime-archive + live-member page-not-archive, registry prune
  (dead+absent>24h), helper-sweep provenance-scoped (never name-pkill).
- 04-G8 (watchdog owner-check) → tp-closure-b (same file domain, narrowing).
### 05 launchd (landed — corrects 3 brief premises)
- CORRECTIONS: dispatcher+discovery ACTIVE since Jul 19/20 (.done markers, runs 70/15, exit 0;
  dispatcher abstains on quota cliff correctly) — desk-autonomy-dormancy memory STALE → updated.
  cc-reaper HAS SSOT misfiled at docs/activation/autonomous-reaper.plist (filename≠label) → move+
  rename to launchd/com.chrisren.cc-reaper.plist. restic+verify-2114 SSOTs exist in
  claude-code-archive repo but STALE (verify-2114 repo RunAtLoad=1 vs live 0 — reinstalling from
  repo would CHANGE behavior; refresh SSOT from live, do NOT reinstall).
- ~~lr-reset-poller: live AUTOFIRE=1 vs repo commented-out → reconcile SSOT recording intentional
  divergence (never reinstall from repo — would kill unattended auto-resume).~~ **CLOSED 4b0efff2
  (2026-07-25)** — the repo plist now SETS autofire, so there is no divergence left to record, and the
  remedy rotted SAFER: reinstalling from repo is now behaviour-preserving (launchd-parity-lint asserts
  live == SSOT and fails the nightly on drift), so the "never reinstall from repo" warning no longer
  applies to this job. A 2026-07-29 codex-security scan re-raised this at revision `38eec335`, which
  forked BEFORE 4b0efff2 — the finding was already fixed on trunk when the scan observed it. The
  RESIDUE it did surface was real and is closed by the follow-up: the plist was reconciled but its
  SIBLING surfaces still told the pre-activation story (the daemon's own header, the safety gate's
  output, wiring-all ①). See `docs/research/codex-security-scans/LEDGER.md`.
- Loss-fragile (no copy anywhere): lead-supervisor plist (worst: KeepAlive daemon),
  screenshot-clipboard plist+~/bin script, watch-2118 plist, dia-cdp disabled pair, 6 reso/gl.reso
  plists (+~/.reso scripts). Reboot survival: ALL 25 return (verified incl. 2 plists that fail
  plutil -lint via raw && — launchd parser leniency; escape as free hardening, reso-side).
- NEW GATE (implements the class-fix): scripts/launchd-parity-lint.sh — per live plist assert
  (a) plutil -lint, (b) label-keyed repo SSOT exists, (c) plutil -p live == SSOT. Named *-lint.sh
  so nightly's glob auto-runs it. Would have caught today's clobber + all 4 drift traps.
- pending-activation drift: 10-close-attrib repo-only (not live-linked — operator CANNOT run it;
  deploy-lag inverse) → platter symlink step; 05-ship-rail-push-allow live-only → copy into repo.
- reso-domain (backlog, not this repo): qa-nightly 13/13 broken (dev server :3100 never ready) +
  unconditional `git reset --hard main` pre-check; rum-verify-launchflash RETIRE (one-shot date
  passed); loki-parity-revisit confirm; && escaping; 6 plists repo-ize reso-side.
- watch-2118-hold: ◆ operator judgment (0-byte logs 24d; hold-watch premise moved to 219-era) —
  platter question, not mechanical.
- **INSTALL LEGS NEEDED (tm-launchd captured SSOT only; tm-hygiene owns install.sh/sync.sh):**
  `launchd/com.claude.lead-supervisor.plist` · `launchd/com.chrisren.screenshot-clipboard.plist` ·
  `launchd/com.chrisren.watch-claude-code-2118-hold.plist` · `launchd/com.chrisren.dia-cdp.plist.disabled`
  (archive-only, stays disabled) · `bin/dia-cdp-launch.sh` · `bin/screenshot-to-clipboard.sh` — the
  last two are REAL files in `~/bin` (not symlinks into the checkout), so editing the repo copy does
  NOT reach live; they need an install/symlink leg or they will silently drift back apart.
- **TASK 7 NOT DONE — cherry-pick would REGRESS (tm-launchd, verified):** `524dadf` is superseded by
  `674bfee` (already in HEAD), which declares `bin/cc-value` AND `bin/cc-reconcile` with richer
  justification. Picking 524dadf reverts DECLARED to the older subset, dropping `bin/cc-value` →
  reaper-horizon-lint goes red on cc-value. Correct action was inaction.
- 🔴 **PRE-EXISTING RED, unrelated to this pass:** `scripts/reaper-horizon-lint.sh` exits 1 on
  origin/main — `hooks/lead-crash-watchdog.sh` is an UNDECLARED reaper (reads `CC_REGISTRY_DIR`
  :136/:173 and rm's telemetry rows :175/:179 + pid/id markers :312/:330 + atomic temp :418).
  Landed with `6c9bd6e feat(close-attrib): join close-records in the crash watchdog`, so
  **nightly-regression is RED right now**. Fix = declare it (lifecycle-op vs age-reaper judgment on
  :175/:179) — needs an owner; left untouched per stop-on-issue.
### 06 pollcost (landed — infra scripts ≈2% of machine; NOT the lag)
- Verdict: all pollers+hooks+statusline ≈600-800 CPU-s/h ≈0.2 core (Nice/LowPriorityIO). The lag =
  iTerm2 pane-fleet rendering (1,183 CPU-s/h sustained = 33% core; 2.5 cores burst; O(panes)) +
  swap 68% / 15.9GB claude RSS (one transient ugrep at 15.8GB!) + the sessions themselves.
  Platter levers (close panes, deploy, reboot) confirmed as the real fixes. mds_stores 130-760
  CPU-s/h attribution UNRESOLVED (worktree-indexing probe timed out) — platter note only.
- 🔴 session-search-sweep NO-OP 107 DAYS: no flock on macOS + stale mkdir-lock (Apr 9) ⇒ exits :27
  every tick; index stale since 04-15 (498/1631 rows). SEQUENCING CRITICAL: optimize first (ONE
  sqlite3 batch + find -newermt + merge 3 python full-parses into 1 changed-files-only pass +
  cadence 60→300s + staleness-aware trylock), THEN rmdir the lock — unblocking as-is = 59s-per-60s
  scanner. → tm-growth.
- 🔴 lead-supervisor page storm: 27,407 pages/24h (19/min; ~9.5 rows re-page every 30s sweep ×6h
  GC_S), 98% of IDL growth (558KB/h), ~170 CPU-s/h, feeds cc-discover C3's hourly 18.8MB rescan.
  Fix: (a) cache work_landed verdict for notified-terminal rows (behavior-preserving), (b) GC_S
  21600→3600 (behavior-affecting — flag). → tm-proclife.
- statusline.sh 16-18 spawns/render (109ms CPU) → ~4 (one jq @tsv + one git status porcelain v2)
  = −70% → tm-growth. waiting-recycle.sh:449 unbounded full-transcript jq → bound like sibling
  :456 BUT detection-affecting — fail-safe design required → tm-proclife. Settings dup hooks +
  double boundary-handoff independently confirmed (tm-hooks D-2 ✓). autonomy-sweep 300→600s
  option flagged (behavior-affecting; ~46 CPU-s/h) — NOT taken this pass.

## Wave-2 roster (spawn as wave-1 slots free; cap 6 concurrent)
| Teammate | Owns |
|---|---|
| tm-gates | 08 F4 (pane-id allow ×17 + narrow numeric filter + 99261468 fixture <!-- pane-id-lint:allow: quoting the bad form to name the fixture -->) + F5 (run_check tee) + S3 transitive-e2e assert + S4 supports_selftest hardening + premortem stale header + D-12 SubagentStop v1 hook + settings_floor live-sync (report diff) |
| tm-growth | 03 #1 scratchpad reaper (live-gated, ≥6000s) + #2 npm cache verify wiring + #5 autonomy age-reaps ×6 + #6 session-index.db retention+VACUUM + #7 plan-history keep-policy + #9 growth-coverage lint (the dual) + #10 mailbox/watchdog/state GC + 06 session-index overhaul-then-unlock + statusline slim |
| tm-proclife | 04 G1 owned-wait idle-horizon page + G2 defer-N page + G3 watchdog team-member stamp + G4 pane-less inventory rows + G5 live_pane_count -Ao/claude.exe/negative-Δ + G6 orphan-reaper multi-root+configless + G7 live-member page-not-archive + G11 registry prune + 06 supervisor-storm fix + waiting-recycle:449 fail-safe bound. SEQUENCED AFTER closure-a/b merge (file overlap: cc-reaper, cc-classify, team-orphan-reaper). |
### 07 closure (landed — code CLOSED + red-proven; deployment is the open front)
- All 7 fix bundles verified at file:line on origin/main; every red state RE-PROVED empirically by
  the auditor (pre-fix code + origin/main tests). Earlier wave c063ca0 IS deployed; the 7 are not.
- 🔴 DEPLOY LANDMINE PROVEN E2E: with ~/.claude/hooks/lib/cc-interactive.sh unlinked, all 3 of
  cc-classify's resolve candidates collapse to the same missing path (bash -x verified); §4.7 hold
  silently inert; incident fixture flips owned-wait → finished/REAPABLE. install.sh:88-95 is the
  remediation; NOTHING forces it (deploy-parity-assert covers ~/bin only). → Platter = ff +
  ./install.sh; code = fail-closed hardening below.
- Ranked residual gaps → implementation:
  G1 cc-classify lib-miss must FAIL CLOSED (adoption-unknown ⇒ never-reap, mirroring
     reap-guard.sh:140-143) + extend deploy-parity-assert.sh with existence-parity for
     ~/.claude/{hooks,hooks/lib,scripts,bin} vs repo.
  G2 teammate-auto-shutdown.sh:356 gate-skip is FAIL-OPEN (empty WORKTREE or non-exec reap-guard ⇒
     who-blind close) → gate-absence ⇒ DEFER + create tests/teammate-auto-shutdown.bats (none exists).
  G3 empty-answer conflation: ce_last_interactive_age "" = no-turn OR jq-missing OR corrupt
     transcript; cc-reaper:562+ + reap-guard:144-151 fall through to reap → distinguish; unreadable
     ⇒ fail-closed (cc-classify's own stricter rule).
  G4 predicate divergence ci_last_interactive_epoch vs ce_last_interactive_age (image-only paste +
     whole-file fallback missing in ce_) + ZERO parity tests → parity test + upgrade ce_ (safer
     direction only).
  G6 suspend-guard is cc-reaper-only → post-wake cooldown for the TeammateIdle path (reap-guard
     R-e), narrowing.
  G8 orphan-reaper unregistered-teammate edge → add the dropped team_has_live_member process
     witness as OR-KEEP signal (confirmed filed nowhere — ours).
  G9 CC_CLASSIFY_INTERACTIVE_HOLD_DISABLE=1 kills the whole hold silently → loud stderr + IDL line
     when active outside tests.
  + twin claude/claude.exe argv regexes (cc-reaper:297/cc-reconcile:98) lockstep-by-comment →
     parity test.
  G5 three acknowledged residuals (S6 soft-hold, R1 tail-eviction, teardown caller-trust) stay
     parked on C-SC-1 — UNPROMOTED, no owner → file cc-backlog item + platter note (campaign launch
     is its own ceremony, out of this pass).
  G7 cleanup-team.md tmux kill-pane uninventoried closer → resolved by its deletion (02 Tier-B).
### 08 nightlyred (landed — 8 RED → 1 unexplained + 4 fixes; ZERO fixed-by-deploy)
- Cascade: reaper-horizon-lint §3 fail-closed on 75283a7's rm -f in lead-crash-watchdog (lifecycle
  op, pid-equality-guarded, registry read-only — same shape as already-DECLARED peers) → premortem
  S-1 → wait-safety L0 → never-stuck LEG-1. F1 (2-line DECLARED append + reviewed comment) clears 4.
  ⚠️ POLICY: F1 flips BOTH un-hold bars to "un-hold is defensible" — operator-visible declaration;
  surface on platter, never silent. Also update stale "RED BY DESIGN" header premortem-gate.sh:12.
- F2 gate-manifest.sh:335 `--selftest|selftest)` (gate NEVER ran in nightly); F3 claude-lint-models
  :93 --selftest alias for --all (never ran; Opus-5-staging hypothesis REFUTED — --all exits 0
  clean under launchd env; model-config is PRESERVE-classified). F1-F3 → tm-launchd addendum
  (file ownership). F4 pane-id-lint: 17 historical allow-appends (~10 docs) + narrow numeric-shape
  filter + 99261468 all-digit-real-pane fixture — do NOT require-hex-letter (real blind spot). <!-- pane-id-lint:allow: quoting the bad form to name the fixture -->
  F5 nightly run_check tee per-check output (S1 = highest-value: 6-day-old reds undiagnosable by
  construction). F4/F5 + S3 transitive-e2e-skip assert + S4 supports_selftest hardening → tm-gates.
- bats:tests class (c): 1460/1460 green at HEAD interactively; 07-19 red was SIGTERM 143; causes
  ranked (5h duration/Nice-10 window 04:05→09:25, live-state coupling of 20+ suites, undeployed
  fixture-isolation 7791209). Honest posture: promise 7/8 + instrumented bats, not a green night.
- S6 restored nightly plist verified firing-ready tonight; S7 standing page up + pages dir 393
  entries (tm-growth); S8 nightly path bypasses symlink layer (ff alone deploys its fixes; no new
  LEG-4 rows from origin/main).
### 09 hooks (landed — 15 defects, forensically grounded)
- D-1 🔴 operator-readout NEVER FIRED (0 IDL vs siblings 345): wired only in ~/.claude; sessions run
  on .claude-next; activator 09-…-activate.sh:54,83,107 OMITS .claude-next → fix activator dir list
  (running it stays C10/platter). Same drift: cc-unattended-ask-guard, desk-brief-inject,
  session-deregister (registry-row leak = the 82-row pileup).
- D-2 🟡 duplicate registrations: notify.sh complete at Stop[0] idx0+idx5 ALL 5 dirs; stray Stop[1]
  boundary-handoff (~/.claude) → DOUBLE {decision:block} per Stop (latch written pre-emit, parallel
  exec). settings-dedup-stop.sh exists, never applied, BLIND to intra-object → extend + apply ×5.
- D-3 🔴 log-bash.sh reads .tool_result (field is tool_response) → 'Exit: 0' always; bash-commands
  no ts/sid. Fix: field + SID from stdin .session_id (22 hooks already do) + timestamp. D-9 same
  class: plan-version-commit CLAUDE_SESSION_ID always 'unknown' → stdin sid.
- D-4 validate-bash + rm-safe-allowlist: no jq guard → bash safety validator silently fail-open →
  add guard + loud abstain-log. D-5 🔴 waiting-recycle (795 ln, every Bash call, can block) has NO
  timeout in all 5 dirs → add (also keychain-guard, stray Stop[1]).
- D-6/7 curl-gate.py + enforce-email-formatting.py + keychain-guard.sh WIRED but UNTRACKED (+2 .bak
  squatters in live hooks dir) → version all 3 + quarantine .baks. deploy-parity-assert covers
  ~/bin only → extend scope (hooks).
- D-8 backup-before-write prunes by BASENAME globally (cross-repo eviction; 10-slot bucket per name)
  + xargs-batch resort bug → prune per .path identity. D-10 teammate-checkpoint: no GC (76 orphan
  cp-*.count; >1000 refs/checkpoints/** refs in THIS repo — git perf!) → GC + ref-retention policy.
- D-11 🔴 session-continue (the auto-continue actuator, blocks ×8) writes ZERO telemetry → add IDL
  line + log. D-14 PreCompact manual lacks dod-persist → wire matcher:manual.
- D-12 🔴 SubagentStop supported (22 hits in claude.exe), wired NOWHERE = structural gap behind
  wave-report stranding → v1 hook: telemetry + persist subagent final report to disk.
- D-13 the 4 inert autonomy hooks = pending-activation queue (C10, platter — unchanged).
- D-15 🔴 DEPLOY MUST BE `ff + ./install.sh` (install.sh:93-95 links hooks/lib/*.sh; bare ff leaves
  cc-classify's interactive-hold lib unlinked → the closure fix silently degrades). Platter updated.
- Rotation gaps (→03/tp-growth): rotate-autonomy-logs covers 3 targets only; unbounded:
  teammate-checkpoint.log 13.6MB, sessions.log 2.8MB, cc-reaper.log 2MB, +6 more; watchdog
  cp-count ×76; state nudge-*.count ×95; ~/.claude/logs = 96MB total.
### 10 loadbearing (landed — binds tp-deletions)
- 12 invisible-dependency mechanisms confirmed w/ examples (M1 chained symlink farms ×4 layers incl.
  ~/.claude-secondary/-tertiary; M2 PATH-by-basename; M3 launchd direct-repo-paths + env-var doc
  inputs (desk-boot-brief.md every 300s, FRONTIER_HOLES.md); M5 docs-as-runtime-config incl.
  docs/plans/test.md + relative-test.md = overwrite-guard fixtures; M6 tests-as-runtime-gates (8
  scripts run named bats at operation time — kimi bats coupling confirmed); M7 state-as-database +
  absence-triggers-action (land.log, cc-fired stamps, sweep-seen damping, .done markers); M10
  wt-pool-* host live sessions while ABSENT from `git worktree list` (unlisted ≠ unused!); M12
  skills/agents deploy by COPY — 18 live-only skills; resync would delete them).
- DELETION PROTOCOL (10 checks) adopted verbatim for tp-deletions: reverse-symlink sweep + zero-new-
  dangling assert; basename grep OUTSIDE repo (LaunchAgents/settings/zshrc/runbooks/pending-
  activation//tmp); plutil -p payload decode; reader-graph + absence question for state files;
  docs/tests runtime-consumption grep; worktree-liveness = git worktree list ∪ registry cwds; two-
  direction live↔repo diff (repo-no-symlink may be PENDING-DEPLOY); dormancy soak incl. reboot;
  QUARANTINE to ~/.claude/archives/cleanup-YYYYMMDD/ ≥1 restic cycle (Sat 02:00), never rm; gate
  re-run per batch. ship/backup-* (176): retention window, never bulk-delete. gl.reso.worktree-gc
  (pid 91522) already GCs worktrees — manual deletion RACES it (serialize/respect).
### 11 worktrees (landed — evidence-graded P1/P2; full commands in report)
- PRUNE 14 stale records (all dirs verified EMPTY) + rmdir 10 unregistered empties + 3 stray logs.
- REMOVE-SAFE 42 worktrees + branches (P1/P2-landed, clean, no live cwd via cc-notify ∪ lsof);
  B4 ~166 landed branches. Discipline: worktree remove NEVER --force, branch -d NEVER -D (git =
  second gate), re-run liveness gate immediately before EVERY removal (inventory moved mid-audit;
  19/42 tips <24h deserve tightest re-check), serialize vs cc-reaper worktree_cleanup + gl.reso
  worktree-gc (pid 91522).
- KEEP: live (shutdown-harden, relogin), dirty ×3 (cc-upgrade-gate, permission-beacon w/ untracked
  hook!, perf-hardening ACTIVELY WRITTEN), 24 unlanded branches (43 orphan commits incl.
  board-runnable-commands 19/19, frontier-problems 31 absent docs), wt-infra-perfect (OURS).
- 🚨 CROSS-REPO: ~/Development/.worktrees is SHARED ACROSS 5 REPOS (47 reso + 20 doc_classifier
  + …); wt-pool-* are reso-management-app's with LIVE sessions — drive removals ONLY off
  `git -C <repo> worktree list --porcelain`, never a dir glob.
- SOLE-HOLDER backup refs (re-land candidates): 88255bd fix(ship-land) skip-deleted-paths-in-
  run_gate (WE NEED THIS — our land deletes files!) → tp-gates re-land FIRST; 524dadf
  reaper-horizon-lint declare-cc-reconcile (likely tonight's lint RED) → tp-gates; a8b9fb8
  orphan-reaper process-witness → tp-closure-b reference implementation.
- ship/backup-* ×176 (172 provably redundant): ◆ operator ruling — rolling window (>14d AND
  P1-landed) proposed on platter. worktree-gc.sh MISSING (guard references it 3×, never existed
  anywhere) → tp-worktree-gc writes it with the guard's documented gates.

## Session-closure class (verify-not-rebuild — lead spot-checks DONE)
Confirmed on origin/main at file:line: reap-guard R-d (+fail-closed, wiring
teammate-auto-shutdown:361), cc-reaper suspend-guard (SUSPEND_S=900, :430), orphan-reaper
three-state UNKNOWN (:51-58), waiting-recycle S6 soft (residual → C-SC-1 campaign, ledger row
2026-07-25). Named follow-up to implement: process-liveness witness as extra OR-signal on 24722de
(registration-timing edge under dead-lead pidfile).

## Operator platter (assembled at close → /tmp/lag-relief-operator.sh + board packets)
1. Deploy: `git -C ~/Development/claude-infrastructure merge --ff-only origin/main` + symlink new
   files (hooks/lib/cc-interactive.sh, scripts/cc-upgrade-gate.sh, skills/cc-upgrade-gate/) +
   `launchctl kickstart -k gui/501/com.claude.lead-supervisor`.
2. Close stale panes (frees RAM + iTerm/WindowServer load): finished-operator 52DCAB5E/8D4878D1; <!-- pane-id-lint:allow: historical sweep record, not a send target -->
   aged owned-waits (personal ×5 up to 9d, lakehouse 2d, life-decision cluster ~1.9GB/46h,
   stripe-research 6d, jose-resume) — close after review; reboot obviates individually.
3. Reboot (13d uptime; resets WindowServer/iTerm/swap). Prereq DONE: plists restored+valid;
   boot-resume + resume-sessions cover recovery. Land this pass first.

## Landing attempt — desk 2026-07-25 ~12:40 PDT (AUTHORITATIVE gate diagnosis)

**Status: rebased onto origin/main, but NOT gate-green — the wave was committed but never passed
a full gate (the prior driver DEADLOCKED before completing; worker reached esc-PARK, which runs
BEFORE run_gate, masking the gate state). Land is DOUBLY blocked: run_gate RED + esc operator-gate.**

- **Rebase (DONE):** `git rebase origin/main` from `/private/tmp/wt-infra-perfect` — 2 conflicts,
  both resolved keep-both/superset and rerere-recorded (survive re-rebase): `tests/cc-classify.bats`
  (safeguard-blocked fixtures ⊕ G1 interactive-lib tests) + `scripts/rotate-autonomy-logs.sh` (branch's
  13-log DEFAULT_TARGETS subsumes origin's 4-log). Branch = origin/main + 48, clean tree.
- **esc_scan PARK (operator-gate, unchanged):** destructive-SQL `DELETE FROM session_chunks/
  chunks_fts/sessions_fts/sessions/file_tracking` (local, rebuildable session-index cache — the
  retention/GC deliverable, commits 20c165b/5d2bf1d). No desk override exists. Operator land command:
  narrow `SHIP_LAND_ESC_RE` to exclude `DELETE FROM` (keeps DROP/TRUNCATE/key detection + all other
  ship-land protections), review the 5 DELETEs, then `/ship`. Systemic gap filed: backlog 97148f9ea7e2
  (same gate also parks feat/autonomy-100 → shipland-esc-c661813).
- **run_gate RED (real `ship-land --dry-run` w/ narrowed esc → exit 6):** 1807 ok, 6 not-ok + shellcheck:
  - shellcheck RED — SC2001×23 (session-index-helpers.sh, session-index-sweep.sh) + SC2015×6
    (premortem-gate.sh) + SC1090/SC2115/SC2207. PRE-EXISTING debt (origin/main's own files fail the
    same) — the gate scans the whole changed file, so the wave inherits it. Fix: `.shellcheckrc`
    (severity=warning OR disable those codes) — a repo-policy call, NOT done unilaterally.
  - `not ok 738` deploy-parity (on-origin) — deploy-lag coupled: passes from the MAIN checkout, fails
    from this worktree (branch's tracked runtime files not linked live). Needs operator `install.sh`.
  - `not ok 991` growth-coverage-lint "SSOT green vs LIVE layer" (BRANCH-NEW e438361) — self-blocking:
    checks the live layer for the wave's own not-yet-deployed files → can't pass pre-land. Hermeticize.
  - `not ok 992` growth-coverage-lint "--selftest each failure fires" (BRANCH-NEW) — investigate.
  - `not ok 64` autonomy-sweep "event horizon 7d ≥ lint floor" (on-origin, 579d21c touched) — config/lint.
  - `not ok 1457` scratchpad-reaper "horizon -mmin +N ≥ 6000s floor" (BRANCH-NEW e2daa0a) — config/lint.
  - `not ok 1320` pane-id-lint "live docs corpus clean" (BRANCH-NEW ef34be8) — flags truncated pane-ids
    in THIS plan doc (52DCAB5E/8D4878D1/99261468) + SAFEGUARD_BLOCKED_VISIBILITY.md:149 (725A269A). Fix: <!-- pane-id-lint:allow: the lint's own diagnosis, quoting the flagged forms -->
    `pane-id-lint:allow` markers (they are historical references, not send targets).
- **NOT a machine-wide blocker** (earlier hypothesis REFUTED): origin/main lands every ~20min (738
  passes from the main checkout); 3/6 failing test files are branch-new lints only this branch carries.
  These are the WAVE'S OWN gate-green debt, not a fleet outage.
- **Finishing work (named, backlogged — F4-unbounded so NOT auto-driven):** make the wave's own new
  lints pass (hermeticize 991/738, satisfy 64/992/1457 config, allow-mark 1320 docs) + `.shellcheckrc`
  policy + operator `install.sh` (738) + operator esc-approval. Then `/ship`. → backlog + board.

## LANDED — 2026-07-29/30 (backlog 692eaf74b0be)

**`377df8de` on origin/main.** `land.log`: `verify:"ok" · esc_scan:"clean" · sweep:"review" · exit:0`.
Content-verified (99 paths present + content-identical), deletions confirmed applied.

**The wave was NOT where the brief said it was.** The dispatched worktree was cut fresh from
origin/main; the work survived only on `ship/backup-2a795cd`, **508 commits behind** a trunk that
lands every ~20 min. So the job was not "fix 6 tests" — it was reconciling 4 days of divergence.
`git cherry` found 49 stranded / 4 already-equivalent.

**Rebased 49 → 43 landed.** Six commits were dropped as SUPERSEDED, adjudicated by reading main's
code rather than trusting either side's prose (memory `parallel-stream-convergence-protocol`):

| Commit | Verdict |
|---|---|
| `8200df2b` reaper-lint declare | main declares it already, line refs **re-derived 07-29** (branch's were stale) |
| `4f162ebf` cc-classify fail-closed | **would have been a live regression**: main deleted `CI_LIB_MISSING`/`ci_lib_warn` for a 3-state rc 0/1/2 model, so the branch's `${CI_LIB_MISSING:-1}` would default to 1 and classify EVERY session never-reap. Code dropped, its 3 behaviour tests kept |
| `0e1af819` teammate-auto-shutdown G2 | main has the same gate-absence-is-a-defer fix **plus** SURFACE+page after MAX_DEFERS (12 tests vs 6) |
| `68c1a156` deploy-parity existence | main is a strict superset — it adds the `skills/` class the branch lacked (omission found live 07-28: `skills/video-understanding` landed unlinked while the assert returned 0) |
| `3770e498` nightly per-check output | main implements it with a NEWER design (ephemeral `RUNDIR` + page quoting vs persistent `$LOG.d` + 14d GC) |
| `4728266a` statusline perf | already on main as `df6b328f`, `statusline.sh` byte-identical, plus a hermeticity fixture |

Four conflicts were resolved as genuine UNIONS (rotate: main's chain-epoch handling + the branch's
9 extra log targets = 15; nightly: main's `postland_inertness` **and** the branch's
`transitive_e2e_assert`, renumbered 5/6; install.sh: main's vendor block + the branch's `rules/`-leg
removal; session-index: main's owner-verified lock + the branch's batched-sweep helpers, deleting a
**duplicate `_session_index_lock_is_stale` definition** the naive merge left behind — bash takes the
last, so main's canonical one won by luck, not design).

**⚠ rerere replays must be verified, not trusted.** Three fired; **two were stale**. On
`claude-bump-models` it silently discarded main's deliberate `SC2064` expand-now trap; on
`nightly-regression.sh` it would have downgraded main's newer design and dropped a
`postland_inertness` reference. Both re-resolved by hand. rerere is a *suggestion* across a 508-commit gap.

### The 4 named blockers — 2 fixed, 2 had gone STALE

1. **Branch-side lints** — FIXED (`f6460282`). The real blocker was not in the brief: `run_gate`'s
   **test-hermeticity ratchet** failed on all **7** branch-new suites (main's tree: 0 leaks — every
   leak was ours). Fixed as prescribed, never by allowlist. `subagent-stop.bats` fixtures under
   `$BATS_RUN_TMPDIR`, not `$BATS_TEST_TMPDIR`, because its "four declared sinks" test enumerates
   that dir exactly and a fixture there becomes a fifth entry — caught only by running the suites,
   since the ratchet itself was already green.
2. **`.shellcheckrc`** — DONE, and **positive-controlled**: rc=0 on all 37 changed files, and a
   synthetic probe proves SC2001/SC2015 DO fire outside the repo and are suppressed inside. (A bare
   `--include=SC2001` cannot override a `disable=` — that control returns empty and reads as a pass.)
3. **operator `install.sh` (738)** — **STALE / MOOT.** `deploy-parity` fails identically from the
   MAIN checkout, so the 07-25 claim "passes from the main checkout" no longer holds: 2 tracked
   files (`bin/cc-ctx-audit`, `hooks/lib/idl-log.sh`, both already ON main) have no live symlink.
   That is live-layer **deploy lag**, not wave debt. It also cannot block a land: the fast lane runs
   statics + ratchets + only `--direct` smoke suites, and `gate-select --direct` answers `FULL`
   ("cannot decide") ⇒ **no smoke at all**; the post-land verifier owns the corpus.
4. **operator esc-approval** — **STALE / MOOT.** A sibling landed `scripts/esc-exempt.manifest`,
   which exempts `hooks/lib/session-index-*.sh` — precisely this wave's row-deletes against the
   rebuildable session-index cache. Its own text names this case: *"4 parks … the rail blocked a
   complete, gate-green fix four separate times."* `esc_scan` now reads **clean**; no narrowed
   `SHIP_LAND_ESC_RE` and no operator packet were needed.

**Both operator-gated blockers had been dissolved by other work while the item sat parked** —
memory `parked-blocker-obsoleted-by-later-fix`, and the reason this item must never be re-parked
on a mechanism fact without re-verifying the wall.

### Scope-boundary calls (named, NOT silently taken)

- **`reaper-horizon-lint` is trunk-red, not wave-red.** main reds it with 5 UNDECLARED reapers. This
  branch fixes 2 (`cc-recover-safeguard` via `7b30ed7f`; `hooks/lib/context-econ.sh` declared here —
  its only `rm -f`s are the mv-or-rm on its own atomic-write temp). **5 → 3.** The remaining 3
  (`cc-await-ping`, `dispatch-assert.sh`, `desk-invariant.sh`) are untouched trunk debt. The
  branch-new `scratchpad-reaper.bats:148` asserted the WHOLE-TREE exit 0, making a new suite
  answerable for debt it did not create — narrowed to its own verdict (memory
  `whole-tree-lint-is-a-fleet-wide-hard-stop`).
- **`git-worktree-guard.sh` is slow, and was left alone.** Its liveness leg loops
  `pgrep -f claude` — **139 pids on this box** — running an `lsof` per pid: **12 s per hook
  invocation**, so `tests/git-worktree-guard.bats` takes **263 s** (it passes 6/6; it is slow, not
  broken). The unbounded loop is **main's own code**, and bounding a *safety* guard's liveness check
  can only make it fail-OPEN — i.e. permit a removal it should block. That trips Follow-On Gate F3
  (safety envelope) ⇒ **named and backlogged, not silently changed.**

### Post-land follow-through — running the HAND-MERGED suites found two real defects

The land's fast lane runs statics + ratchets and no corpus, so after landing I ran the suites whose
SUBJECTS this land hand-merged — the union files, which by construction no single side's tests cover.
Two reds, both genuine, both fixed:

- **`rotate-autonomy-logs.bats` (`1e77d64c`)** — my union took DEFAULT_TARGETS from 13 to 15, but the
  suite's fixture still listed 13. A target with no fixture file counts SKIPPED, so it reded both
  `"rotated":13` and `"skipped":0`. Fixture + counts corrected; 14/14.
- **`cc-classify` G1 (`e74208fa`) — a LIVE reap-a-live-operator-conversation defect on trunk.**
  I had kept the stranded branch's 3 G1 tests while dropping its code (its `${CI_LIB_MISSING:-1}`
  form referenced a variable trunk had deleted, so applying it verbatim would have held EVERY
  session forever). Running them measured the real behaviour on the incident fixture:
  **lib resolvable ⇒ `owned-wait`; lib UNRESOLVABLE ⇒ `finished` = REAPABLE.**
  The §4.7 comment had argued no such branch was needed because "every world that makes the WHO-scan
  unreadable ALSO denies this function a last-assistant timestamp". True for an unreadable
  *transcript* — **false for a missing *lib***: the transcript reads fine, IDLE is computed normally,
  the `IDLE<0` fail-safe never fires, and `last_interactive_epoch()` returns 1 for a MISSING PRIMITIVE
  exactly as it does for "nobody typed". Fixed by keying on `command -v ci_last_interactive_epoch`
  (the wrapper's own predicate, so it cannot drift). Reachable via ordinary deploy lag —
  `hooks/lib/idl-log.sh` is live-missing on this box for precisely that reason.

  **Not theoretical, and not finished:** `bin/cc-teardown` (3 uses) and
  `hooks/teammate-auto-shutdown.sh` (5 uses) consume the same primitive with **no such guard**, and
  both **CLOSE PANES** — strictly higher blast radius than the classifier. `hooks/lib/context-econ.sh`
  likewise (2 uses). Filed as **backlog `319831157e33`** with a per-site *measured-proof* DoD rather
  than fixed off a grep (memory `third-state-skips-the-unnamed-gate`: the defect survives in the leg
  a residual list calls strong).

  **CLOSED 2026-07-31 (`28e591ac`) — and the measured-proof DoD is why the census above is wrong on
  two of its three sites.** The paragraph above was written from a `command -v` grep. Measurement
  found a `type -t` guard already present at both pane-closing sites, so "no such guard" was true of
  the *spelling* and false of the *fact* — the real question was never whether a guard existed but
  which way it branched:
  - **`hooks/teammate-auto-shutdown.sh` — the one real defect, and the worst of the family.** Its
    guard branched to `WARN + skip` → `close_and_log`. Measured on the incident fixture (operator
    prompt 950s ago, idle 900s, landed, spawn 50000s ago, reap-guard absent so this belt is the only
    who-gate): **lib present ⇒ held + paged; lib absent ⇒ `it2 session close -f -s PANE-INC`** — a
    live operator conversation killed. Its own bats **pinned that fail-open as correct**, using a
    fixture carrying a REAL operator prompt — the identical pathology `cc-teardown` carried until R3.
    Fixed via the BEAT second oracle (`beat_or_refuse`'s pattern), never an unconditional hold: that
    would make the belt a single point of inertness, the amplifier outage cc-teardown RED-proved.
  - **`bin/cc-teardown` — already fixed, before this item was filed.** R3 (§4.3.5) routes lib-absent
    through `beat_or_refuse`; 17/17 bats green *with positive controls*. No edit needed.
  - **`hooks/lib/context-econ.sh` — ZERO calls.** Both greppable "uses" (`:315`, `:332`) are
    **comments**. It defines its own self-contained `ce_last_interactive_age` and has no dependency on
    the lib, so it has no lib-absent failure mode to guard. The "2 uses" was a miscount.

  Two premises of the item had also **rotted** by the time it ran: `hooks/lib/idl-log.sh` is no longer
  live-missing, and **no** tracked `hooks/lib/` file is — so the deploy-lag path that made this
  reachable is currently closed, making the defect latent rather than live. It was still worth fixing:
  a fail-open on a pane-closing actuator is wrong independent of today's deploy state, and this was the
  only site in a three-site safety family still branching that way. Also logged the previously **silent**
  `reap-guard` skip (`-x` test with no `else`) — R-d and this belt are the two who-gates here and both
  degrade on the same per-file-symlink layer, so a guard that vanishes without a trace is how the
  vanishing stays invisible until an incident.

  **Method note:** the DoD's "measure, do not assume the grep" is what caught all three corrections.
  A grep for one spelling of a guard cannot distinguish *absent* from *present-but-inverted*, and the
  inverted one is the dangerous state — it looks guarded in review and reads green in its own suite.

**Method note worth keeping:** a green ratchet does not prove the suites pass, and a passing land
does not prove the corpus. Both defects above were invisible to the landing gate and were found only
by running the union files' own suites. Also: two bats runs were CUT by my own `timeout` bound and a
cut is a NON-VERDICT, never a pass (`0 not ok` at test 17 of 58 means nothing).

### Residual — operator-owned, none blocking  *(AS FILED 07-29/30 — disposition below)*

- **Live deploy lag (2 links).** `./install.sh` from the main checkout, or the two exact `ln -sf`
  lines `deploy-parity-assert.sh` prints. Agent-side deploy is classifier-blocked (C10).
- **3 trunk-debt reapers** to declare or bound in `reaper-horizon-lint`.
- **`git-worktree-guard` 12 s/invocation** — needs a bounded liveness check that cannot fail open.

### Residual — CLOSED 2026-07-31. All three re-measured BEFORE editing; two had rotted.

Re-verified against the live tree first, never trusted as written (memory
`parked-blocker-obsoleted-by-later-fix`, `scan-revision-predates-the-fix`). **Two of the three were
stale, and the third's prescribed remedy was the wrong fix.** Original text preserved above.

- **Live deploy lag — STALE, already resolved.** `deploy-parity-assert.sh` from the MAIN checkout now
  exits **0**, all 6 rows OK/LINKED; `bin/cc-ctx-audit` and `hooks/lib/idl-log.sh` both have live
  symlinks. Nothing left for the operator. (Consistent with the §CLOSED note above: no tracked
  `hooks/lib/` file is live-missing any more.)

- **3 trunk-debt reapers — STALE on all three names, and the 2 survivors were FALSE POSITIVES.**
  `cc-await-ping`, `dispatch-assert.sh`, `desk-invariant.sh` are all `$DECLARED` and pass. The lint
  was still **trunk-RED (rc=1)** — on two *different* files, `hooks/session-continue.sh` and
  `hooks/lib/mailbox-pending.sh`, **neither of which is a reaper**: each matches `EVIDENCE_GREP` only
  inside a **comment** (`:472`, `:526`, both prose mentioning `cc-registry`).
  **§3 structurally could not see that.** §1/§2 strip comment hits with `is_comment()`; §3 used
  `grep -rl`, which yields a bare filename with no line to test — so the helper was unreachable. That
  is the exact defect this file documents *at* `is_comment()` ("a check must observe the thing it
  guards, not prose about it"), surviving in the one section that could not call it.
  **Fixed the detector, not the subjects.** The remedy §3 *prescribed* — declare both — would have
  recorded two non-reapers as reviewed reapers, diluting the very list §1/§2 scan for horizons
  (memory `work-item-remedy-can-become-forbidden`). §3 now uses `grep -rn` + `is_comment`, and the
  delete-leg tests code rather than prose. **Positive- and negative-controlled:** a planted real
  reaper (code refs to `CC_REGISTRY_DIR` + `-delete`/`rm -f`) still reds it (rc=1); the same file
  with a prose-only reference does not (rc=0). `premortem-gate` **S-1 is now green.**

- **`git-worktree-guard` — FIXED, and the parked premise named the wrong fix.** The residual asked
  for "a bounded liveness check that cannot fail open", and 07-25 parked it under F3 because bounding
  a *safety* guard can only make it fail OPEN. Both true — and both moot: the cost was never the
  check, it was the **spawn count**. `pgrep -f claude` matches the FULL argv — measured **73-78 pids,
  only ~13 actually claude** (the rest bash/zsh/tee/timeout wrappers and agent briefs that merely
  contain the string; memory `pgrep-f-matches-agent-briefs`) — and the loop paid one `lsof` per pid.
  Batched to a single `lsof -p <csv>`: **5.98 s → 0.092 s (65×)**, population and predicate
  byte-identical, so there is no bound to give up and nothing can fail open.
  `tests/git-worktree-guard.bats`: **263 s → 5 s.**
  The `[ -n "$cpids" ]` guard is load-bearing — `lsof -p ""` lists **every process on the box**
  (measured 1890 lines), which would silently widen the predicate to "anyone, anywhere".

**The suite could not have caught a mistake here.** `git-worktree-guard.bats` had **no test that a
live worktree is BLOCKED** — its 6 tests covered `branch -d` blocking and the remove leg *passing on
idle*, and the file's own header conceded test 4 "discriminates nothing on its own". A guard whose
only asserted behaviour is its pass path is pinned fail-open by its own suite (memory
`present-but-inverted-guard` — the second instance in this repo). Added two tests pinning both
directions and **red-proved** them: with the liveness leg emptied, the new BLOCK test fails while
**all 7 others still pass** — which measures exactly how blind the suite was. 6 → 8 tests.

**Found while verifying, then SUPERSEDED at land time: `tests/scratchpad-reaper.bats`.** Its "staged
plist" test asserted on `launchd/com.claude.scratchpad-reaper.plist`, but `c16e4e2a` had deliberately
moved that plist to `launchd/staged/` (`install.sh` globs `launchd/`, so a staged job left there
would be bootstrapped — the move was right and only the test lagged). `plutil` exits non-zero on a
*missing* file, so the stale path read as a plain assertion FAIL rather than as "wrong path", which
is why it survived as red on pristine `origin/main`. Fixed and red-proved here — but the land-time
rebase conflicted: **`5f550b70` had already landed the byte-identical path fix**, with a fuller
write-up (it repairs `session-index-sweep.bats` too and RED-proves both). My commit was **dropped as
SUPERSEDED** — the code was identical and only duplicate prose remained (adjudicated by reading
main's code, per the supersede rule this plan used for its own six dropped commits; memory
`remediation-manufactures-its-own-false-edges`). Kept in this record because the finding was reached
independently and the red was real — but the fix is trunk's, not this item's.
