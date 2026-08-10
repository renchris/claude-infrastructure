# Axis K — The hostile-reviewer defense: what the "sprawl" answers, and what consolidation breaks

**Slot:** adversarial defend (K of 15) · 2026-08-10 · read-only; this file is the deliverable.
**Standard applied:** a subsystem is defended only where a *cited incident or measurement* is the
mechanism's cause; where the record shows genuine redundancy, it is conceded (§5) — a defense that
concedes nothing is not credible.

## 0. Governing verdict

**The indicted sprawl is, on the machine's own attribution record, ~9% of the memory problem and
~90% of the incident-prevention layer.** At every instrumented panic moment the node dev-tooling
fleet was 91% of footprint (140.6 GB / 780 procs at the 08-09 panic) while the entire claude fleet
held 2.0–5.3 GB and infra shell residue ~0.16 GB (`docs/research/crash-rootcause-2026-08-09.md` §3;
`lag-meltdown-2026-08-07.md`: "claude.exe 16 live, 7.2GB — the actual fleet is small"; kitty 130 MB
for 153 panes — "the terminal is not the memory story; the residue was"). The kill chain already has
a landed, armed, field-proven remedy set (sentinel ARMED 08-09 04:36 + parent-breaker + Next
`workerThreads` config + `devserver-gc` one flag from armed — crash doc §6–7). A ground-up
re-architecture of daemons/hooks/worktrees therefore attacks the small term, carries the measured
risk class "remedy worse than the bug" (§4 below — seven documented instances), and — unless every
finding rides an enforcing-store change — reproduces the exact failure the repo has already named:
**five investigations, five detectors, zero armed actuators, then panics #5 and #6**
(crash doc §5.1; `memory/conclusion-must-reach-the-enforcing-store.md`: 8 correct analyses in 11
days changed nothing).

## 1. Per-subsystem defense rows

| Mechanism (indicted as) | The incident/measurement it answers | What consolidation/simplification breaks | Verdict |
|---|---|---|---|
| **~30-daemon launchd fleet** ("too many jobs") | Fleet truth doctrine born from the 2026-07-26/27 outage: an agent `bootout`-disabled 13 labels; the reboot converted latent bits into **total fleet outage** (`memory/daemon-fleet-v2.md` §5). `launchctl list\|grep` maps six states onto one boolean with four broken states reading healthy (§2); a broken daemon gets QUIETER with age (§4). | A "one supervisor daemon" collapse puts every monitor in one QoS band and one failure domain. The crash record is explicit that band diversity is survival: **"Background-band samplers die ~3 min before every wedge… guards for this event must be Standard-band, rate-keyed, self-actuating — which is precisely the sentinel's design"** (crash doc §5.4). One consolidated background monitor = all sensors die together at exactly the moment that matters. | **Load-bearing as a *population*; individual dead rows conceded (§5).** RAM cost ≈ nil (dormant shell scripts; `bash ×70 = 162 MB` fleet-wide, prespawn census). |
| **The 5-reaper "redundancy cluster"** | Each reaper owns a distinct population with a distinct kill discipline and a distinct incident: `cc-reaper garbage` ← the load-781 meltdown (497 zsh, 59 stuck wrappers, 49 watchdogs; relief mechanism itself disabled by load, fixed by retry-at-3×, `lag-meltdown` §3, ship list 2–3); `devserver-gc` ← would have reaped the spawner **27 min before the 04:07 storm** (crash doc §4); `compressor-sentinel` parent-breaker ← spawner outside the child cohort kept minting between trips (§7-bis); `worktree-gc` ← operator fallback to raw `git branch -D` bypassing every gate (`scripts/worktree-gc.sh:4-9`); land-lock reap ← reso's policy imported unmodified would drop commits (`memory/reference-landing-safety-tooling.md` decision 1: "a silently-dropped commit costs more than a wedged-lock wait"). | A unified reaper needs ONE kill discipline over populations whose safety predicates conflict (never-claude-shaped vs never-force vs TERM-then-KILL vs SIGSTOP-reversible-only-while-a-CONTer-survives). The oracle failures are per-population too: `lookup-miss-is-not-absence` (exit 0 "already gone" on a live pid), `probe-that-acts-on-absence` (typed into a LIVE composer), `pgrep-f-matches-agent-briefs` (read 50, truth 1). One shared oracle bug in a unified reaper = fleet-wide kill authority with a fleet-wide blind spot. | **Load-bearing diversity.** Concede: `teammate-reap-alarm` never bootstrapped (`memory/shutdown-request-is-not-an-actuator.md` — "the sensor exists, the cadence does not"). |
| **74 hooks / 41 matchers** ("fork bill") | Hooks are one of the FOUR enforcing stores (`inertness-generator-2026-08-07.md` §2.1) — the only layer where a conclusion binds without a future actor's discretion. Individually incident-born: `backup-before-write` ← plan-file overwrites "happened multiple times, significant rework" (CLAUDE.md File Update Rule); `completion-assert`/`operator-readout` ← operator re-asking "good to close?" at every close (2026-08-01 crux); `qos-rewrite` ← three concurrent corpus runs took load to 66 (inertness doc §1 item 1); `session-continue` wake floor ← sessions idling with own loose ends; `waiting-recycle`/`boundary-handoff` ← **7 sessions dead-in-place at a bare `Prompt is too long`, 39/39 compactions manual, 0 auto** (`CONTEXT_ECONOMY_V2.md` C4/C6). | **The consolidation was already built and its premise measured FALSE.** `hooks/hook-chain.sh` exists, is correct, heavily tested, and *deliberately not wired*: real 6-guard chain serial 174 ms vs dispatcher ~180 ms; the "11-15 ms fork" floor was a 4× measurement artifact (marginal exec ≈ 2-4 ms); the biggest member got +48 ms WORSE under sourcing; and wall-clock cannot adjudicate under the box's own 2× load swing (`hooks/hook-chain.sh:24-47`). Its safety law also names what a skip-mode consolidation costs: "a kill switch that silently disarms six guards is worse than no kill switch" (:69-75). | **Load-bearing; the fork-bill remedy is per-member (curl-gate.py = 26% of the chain, one project — hook-chain.sh:49-51), not structural.** |
| **Per-session pollers** (`cc-await-ping` 15 s, `lead-crash-watchdog` 30 s) | Measured to be already free: idle session + its pollers = **0.0031 runnable threads**; 150-resident projection 0.46 of a 20 budget (`idle-session-occupancy-2026-08-09.md` §1). The indicting census ("19 cc-reaper, 20 await-ping…") was **argv contamination — the wave's own brief matched itself once per pane** (§2; pinned by `tests/occupancy-probe.bats:4`). | Consolidation designed, then **declined on the measured trade** (§5): payoff 0.33 threads (1.6% of budget) vs the wake path — the harness's background-task-completion notification is the ONLY channel that re-invokes an idle model; a box-wide daemon that stops re-stamping one `.watching` marker **blocks that session's Stop forever**. 53 test files + `wait-contract-lint.sh` guard the pair. Cheap lever already priced: 15 s→60 s poll = 4× cut, bounded by `CC_WATCH_FRESH_S=90`. | **Genuinely-cheap already; consolidation is negative-EV by the repo's own arithmetic.** |
| **~280 retained worktrees** | Retention is the fail-closed OUTPUT of a data-loss guard, not neglect. Gate census on live checkout 2026-07-26: 13 of 37 "stale" worktrees were LIVE (gate 4 over-matching "can only ever cause a KEEP"); 24 tracked-clean but **genuinely UNLANDED** — deleting them destroys work (`scripts/worktree-gc.sh:15-42`). The shared `~/Development/.worktrees` hosts **5 repos' live sessions** — a directory-glob GC was the audit's highest-severity finding (§6). Landed-ness must be patch-equivalence (`git cherry`), never count — the `dfacccd` incident: 5 files silently rebase-dropped while `rev-list` read 0 (`memory/reference-landing-safety-tooling.md`). Warm worktrees are also a cache: cold `--worktree` fires race auto-submit and wedge on zsh-correct (`memory/cold-worktree-fire-autosubmit-race.md`); parallel creation races `.git/config.lock` (GH #34645/#48927). | Age-based GC ("simplify the predicate"): `worktree-gc.sh` A2 states why — **"age alone NEVER disposes"**; the DISPOSE class already has the correct design (72 h + terminal-owner oracle + durable-ref proof A3, exit 4 on verification miss). Force-removal: `--force`/`-D` are git's own second gate on the evidence; "a refusal is a KEEP, never something to force through" (audit §8-H). | **Retention logic load-bearing; the COUNT is a disk/scan cost, ~0 RAM.** The gap is arming the built DISPOSE class, not redesigning it. |
| **Per-file-symlink deploy + gated live layer** | Per-file links answer copy-drift (`deploy-lag-checkout-behind-origin`); the descendant check answers rollback (545 REFUSED lines were refusing a genuine rollback target — inertness doc §1 item 2); the green-stamp gate answers running untested bytes under 12+ writers 24/7 with no quiet period (`GROUND_UP_REBUILD_MAP.md` row 1 constraint). The ADD-gap is known, detected (existence parity `33e60df2`), and budgeted (LIVE_ADDS breaches at lag 1 — CLAUDE.md 🚨, backlog `99b715f31a98`). | "Run straight from checkout HEAD" removes the rollback refusal and ships every mid-edit instantly — and the record shows an **uncommitted** `bin/cc-backlog` edit was already executed live by `cc-reaper --reap` (`reference-landing-safety-tooling.md`, 2026-07-31): the simplified design makes that the norm, ungated. "Copy deploy" re-imports the drift incident. The *diagnosed* defect is gate POLARITY (permission-before vs veto-after, inertness §2.3) — and that fix is owned, in-flight (`DEPLOY_LANE_GROUND_UP.md` T0–T3 live 2026-08-07). A fresh re-architecture collides with an in-flight rebuild of the same seam. | **Mechanism load-bearing; the defect is the gate's polarity, already owned elsewhere.** |
| **Standing orchestrator sessions** (desk, dispatcher, wave leads) | Operator standing directives, verbatim in memory: parallel tracks are VISIBLE split-pane sessions, never bg subagents (`feedback-dedicated-split-pane-sessions-for-parallel-work.md`); the system MUST self-drive to 100% when the operator steps away (`feedback-autonomous-to-100-boundary.md`). Their idle cost is the §1 figure above (~0.003 threads); RSS ~208–230 MB flat regardless of age — and `ps` RSS overstates it 3-4× via shared-page double-count (`iterm2-freeze-30-sessions-2026-07-30.md` §1). | Removing them removes the autonomy the operator explicitly bought. The 15-session wall they are blamed for is not theirs on the record: the GUI freeze was WindowServer mach-port saturation with **15 G unused RAM and 0 swap** at 39 sessions (iterm2-freeze §1), and the panic chain is node storms (§0). | **Load-bearing by operator directive; RAM-modest by measurement.** |
| **Dual terminal transports / duplicated arms** | One pinned E2E arm per transport is doctrine from measurement: green on iTerm2, red on kitty — a 2nd delivery path makes an arm AMBIENT, not redundant (`memory/second-transport-makes-an-e2e-ambient.md`). The env-sampling dispatch defect under launchd (`lag-meltdown` §"Why sessions fire off in iTerm2") was fixed by a live socket detector, keeping both arms; `open -a iTerm` (the one unguarded launcher) deleted. | Collapsing to one transport removes the degrade path the fixes deliberately preserved (iTerm2 arm now requires the app already running — rc 3 to callers' queue fallbacks). | **Load-bearing pair.** |
| **Append-log/telemetry stores** (partial) | The evidence base that produced every doctrine IS these stores: 4,890-transcript measurement (CONTEXT_ECONOMY_V2), sentinel JSONL rows surviving panic #6, `land.log` smoke_n/net reads. Counter-lesson also on file: `/tmp`'s reboot-wipe is the ONLY bound on one dead-page population — relocating it was refused for exactly that (`prescribed-remedy-worse-than-the-bug.md` corollary). | Blind compaction deletes the incident record a fresh session needs (crash doc §5.3: only 2 of 5 panic files survive; the crash memories are UNINDEXED because MEMORY.md is over cap — the failure is retention *policy*, not retention). | **Mixed — see concessions.** |

## 2. Where consolidation creates the SPOF the sprawl avoids (question b)

1. **QoS-band monoculture.** crash doc §5.4 (quoted above). The one sensor that caught every storm
   is the one that diverged from the fleet pattern (Standard-band, 10 s internal loop, self-actuating).
   Consolidating monitors "for efficiency" into a shared background daemon reunifies the failure domain.
2. **One flag/gate service.** `memory/gate-default-decides-failure-direction.md`: two siblings with
   opposite defaults fail OPPOSITE ways from ONE outage, silently, logged as normal state. Any
   consolidated config/gate layer inherits this: its outage becomes every guard's simultaneous,
   direction-scrambled failure.
3. **One queue/surface for alarms.** `memory/alarm-polarity-and-attention-budget.md`: a single
   first-come surface starved 2 of 5 classes at ANY queue depth (class-C decision at position 14 of a
   6-slot window). Per-class budgets exist because consolidation was measured to delete classes.
   PARTITION, never FILTER.
4. **One lock over mixed-cost phases.** `memory/lock-scope-gates-not-protects.md`: one lock spanning a
   7-45 s phase and a 414-833 s tail starved the cheap phase (gaps to 1073 s). The remedy that looks
   like simplification ("release before the spawn tail") would have re-created a known double-worker
   incident AND raced `.git/config.lock`.
5. **One escalation ladder with nested rungs.** `memory/liveness-free-channel-never-gated-behind-liveness.md`:
   the liveness-free banner nested inside the desk arm meant a CLEANUP disabled it — while the "primary"
   channel had 0 successful deliveries in 389 attempts. Rung independence is the redundancy that held.

## 3. Apparent waste that is load-bearing redundancy (question a)

- **Fail-closed KEEPs** (worktree gates, land-lock never-reap-live, `git -d` not `-D`): every one is a
  data-loss incident's answer; over-matching is safe by design ("can only ever cause a KEEP").
- **Damping + sticky terminal states** on notify channels (`memory/notify-channel-golive-damp-first.md`)
  and per-class render budgets: the alternative was measured — 55 steps through a 6-slot window.
- **Declaration-based existence evidence** (manifest per label) vs "just check if it's running":
  `launchctl list` collapses six states; gating on the subject's own history makes "never worked"
  unalarmable — 0-green-in-33 could never fire (`daemon-fleet-v2.md` §1-2).
- **`ok_exits` per job** ("exit 1 is the DESIGNED verdict" — deploy-live): an exit-code-keyed
  simplified health model alarms forever on healthy jobs (§3).
- **Two-phase verification everywhere** (content-verify + count; TaskStop + ps-verify + TERM +
  re-verify): each extra phase is a measured claimed-vs-checked failure — `TaskStop` reaped 3 of 4 in
  one wave and 0 of 4 in another, outcome "not knowable from the return value"
  (`shutdown-request-is-not-an-actuator.md`).

## 4. Prior consolidations/simplifications that made things worse (question c) — the record

1. **Hook-chain dispatcher** — built, tested, measured; premise falsified; deliberately unwired
   (`hooks/hook-chain.sh:24-47`). The naive collapse "only pays in the high-load regime it exists to
   prevent — and therefore cannot be validated by measurement at normal load."
2. **Launcher-name consolidation (2026-07-31, `23551b01`)** — correct, and still broke two consumer
   classes: cc-upgrade-gate checks 5/6/12 went RED reading the emptied shims (`49332e4f`); the
   handoff account probe certified a build no successor runs (`d0e8a028`). Consolidation debt is
   consumer-shaped, not author-shaped.
3. **A cleanup disabled a safety channel** — removing stale desk role files silently disabled the
   Notification-Center banner nested in that arm; surfacing got strictly worse
   (`liveness-free-channel-never-gated-behind-liveness.md`).
4. **The blanket /Users/chrisren/.claude/bin/cc-bats fixer** — a mechanical `|| false` "simplification" inverted two GUARDS, turned
   the repo-wide ratchet red, and halted the deploy pipeline (`blanket-remedy-inverts-guards.md`).
5. **Agent fleet-disable (2026-07-26)** — 13 labels booted out "to quiet things down"; the 07-27
   reboot converted it into total outage (`daemon-fleet-v2.md` §5).
6. **The audit's own one-liners** — BSD mktemp constant-name; TMPDIR inert under launchd; telemetry
   relocation refused on three measured hazards (`prescribed-remedy-worse-than-the-bug.md`).
7. **`CLAUDE_CODE_SIMPLE_SYSTEM_PROMPT=0`** — the simplifying remedy sat above a short-circuit,
   model-blind: **+37,143 tokens on every request**; strictly worse than the bug
   (`gate-default-decides-failure-direction.md`).
8. **cc-reaper's load-shedding bound** — a 90 s classify cap (itself a simplification for load)
   disabled the relief mechanism during the exact load it should relieve (`lag-meltdown` §3).
9. **`revert(wrap-ledger): withdraw the --machine memo`** (`5da21949`) — a consumer suite refuted a
   fresh interface addition; the system's own reverts run at a real rate.

## 5. Conceded as genuinely redundant / genuinely broken (the defense's honest column)

- Dead plists: `com.claude.discovery`, `com.claude.lead-supervisor` (status -15, prespawn census).
- The `.page` notification channel: 556 stale pages, one 300 s notification-only consumer —
  "structurally cannot act in time" (crash doc §4); superseded by the armed actuator.
- `teammate-reap-alarm` never bootstrapped; `subagent-stop.sh` unregistered; `assignee-chain-state.py`
  zero callers (`shutdown-request-is-not-an-actuator.md` — "the sensor exists, the cadence does not").
- MEMORY.md over-cap with all four crash memories unindexed — retention policy failure with measured
  harm (crash doc §5.3): a fresh session cannot find the incident record.
- `curl-gate.py`: 46 ms of every Bash call, 26% of the chain, "incapable of deciding anything outside
  one project" (`hook-chain.sh:49-51`) — the repo's own top-value hook fix, still unshipped.
- agent-browser daemon accumulation (42 at census) — filed, unowned (`lag-meltdown` §"does NOT fix").
- `install.sh:306-315` bootout-without-enable on every autonomous advance — bounces enabled jobs,
  cannot recover disabled ones; the broken command is TEST-PINNED in place (`daemon-fleet-v2.md` §6).

## 6. "What dimension would a hostile reviewer say we missed?" — three, with cites

1. **The landing edge of the re-architecture itself. Nobody owns HOW these 15 reports become
   machine behaviour — and this system has measured what happens then.** Every wave deliverable is
   an advisory-store write behind the diode (`docs/research/inertness-generator-2026-08-07.md`
   §2.2-2.3); the score is 8 correct analyses / 0 behaviour changes in 11 days
   (`memory/conclusion-must-reach-the-enforcing-store.md`), and "five investigations, five
   detectors, zero armed actuators" preceded panics #5-6 (crash doc §5.1). Worse, any consolidation
   that ADDS files ships as a silent no-op until the converger runs — `LIVE_ADDS` breaches at lag 1;
   measured on `scripts/lib/pane-spawn-log.sh`, 20 instrumented call sites doing nothing (CLAUDE.md
   🚨 2026-08-09, backlog `99b715f31a98`). The wave needs a 16th deliverable: per finding, the named
   enforcing-store edge (settings.json registration / plist / PATH / live-revision) riding the same
   landing unit, else it is the inertness generator's next input.
2. **The benefit column. Every axis prices cost (RSS, wakes, forks, GB) and no axis prices prevented
   recurrence — a cut-ranking computed on a one-column ledger deletes the highest-benefit rows
   first, because pure prevention looks like pure cost.** The counted evidence exists and is
   uncollected: compressor-sentinel **91 trips Aug 6-9** = storms survived (crash doc §4);
   `hooks/backup-before-write.sh` restore events in `~/.claude/backups/` vs the "significant rework"
   incidents that created it (CLAUDE.md File Update Rule); `scripts/stranded-sweep.sh` recoveries vs
   `dfacccd`; `hooks/completion-assert.sh` false-done blocks; trunk commit `7bf9fd85` ("the
   anti-recurrence detector could not fire, and the control proved it") shows detector-benefit is
   auditable. A fire-count-per-guard census is cheap and changes the rank order.
3. **Census validity under self-contamination. The wave measures a fleet that now contains the wave.**
   The repo's freshest capacity doc found its OWN scoping census was argv contamination — "the
   subject of the measurement was inside the measuring instrument," each pane matching the brief's
   literal strings (`docs/research/idle-session-occupancy-2026-08-09.md` §2; pinned by
   `tests/occupancy-probe.bats:4`; class indexed as `memory/pgrep-f-matches-agent-briefs.md`, read 50
   where truth was 1). Fifteen worker briefs naming every process family are 15 new contamination
   sources; the prespawn anchor census already carries the investigation's own `claude.exe ×5 =
   2.7 GB`. Compounding: `ps` RSS overstates per-session memory 3-4× via shared-page double-count
   (`iterm2-freeze-30-sessions-2026-07-30.md` §1 method note; `memory/gui-memory-dialog-blames-the-coalition-host.md`).
   Unless every sibling used command-position predicates and footprint (not RSS), the wave's numbers
   indict the wrong sizes.
   *Runner-up 4th:* burst-vs-resident conflation — panics are 90-second storms (18→372 procs);
   resident-RSS optimization cannot touch admission, and the admission layer is the named-filed gap
   (`capacity-admit` "fails open… spawn UNGATED", crash doc §5.4; worker-wave splits ungated,
   `lag-meltdown` §"does NOT fix").

## 7. Adversarial self-pass (on this defense)

Checked against myself: (i) *"you only defended winners"* → §5 concedes seven dead/broken rows with
cites; (ii) *"hook fork-cost is real under load"* → conceded via idle-occupancy §3 (fork churn ≈1.5
load/active session, belongs to activity not residency) and the per-member remedy path (curl-gate);
(iii) *"the worktree GC daemons demonstrably leave 254 worktrees"* → conceded that the DISPOSE class
needs ARMING — but that is an activation, not a redesign, and age-only GC is the one design the
guard's own incident record forbids; (iv) *"prior-art axis J overlaps my §4"* → J catalogs settled
decisions; §4 is specifically the *consolidation-failure* record, which is the burden-of-proof
evidence a re-architecture verdict must clear.
