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
- cc-reaper sweep: 0 safe candidates; 2 surfaced finished-operator (panes 52DCAB5E pid 31459,
  8D4878D1 pid 87542); fleet is operator-owned panes → platter, not auto-kill.

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
- lr-reset-poller: live AUTOFIRE=1 vs repo commented-out → reconcile SSOT recording intentional
  divergence (never reinstall from repo — would kill unattended auto-resume).
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
| tm-gates | 08 F4 (pane-id allow ×17 + narrow numeric filter + 99261468 fixture) + F5 (run_check tee) + S3 transitive-e2e assert + S4 supports_selftest hardening + premortem stale header + D-12 SubagentStop v1 hook + settings_floor live-sync (report diff) |
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
  filter + 99261468 all-digit-real-pane fixture — do NOT require-hex-letter (real blind spot).
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
2. Close stale panes (frees RAM + iTerm/WindowServer load): finished-operator 52DCAB5E/8D4878D1;
   aged owned-waits (personal ×5 up to 9d, lakehouse 2d, life-decision cluster ~1.9GB/46h,
   stripe-research 6d, jose-resume) — close after review; reboot obviates individually.
3. Reboot (13d uptime; resets WindowServer/iTerm/swap). Prereq DONE: plists restored+valid;
   boot-resume + resume-sessions cover recovery. Land this pass first.
