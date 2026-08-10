# Pre-spawn decomposition — true bottlenecks, 15 → 150+ sessions (2026-08-09)

**Question type:** Operational + Architectural. Out of scope: Market / Competitive / BD / Legal / Product.
**Restatement:** find the true bottlenecks that make the fixed M1 Max (64 GB / 10-core) lag and then crash, and address them so the operator can work from 15+ concurrent sessions towards 150+, reliably and scalably, with no hardware purchase.

**Prior art this wave builds ON (not re-derives):** `docs/research/crash-rootcause-2026-08-09.md` (crash chain + armed actuator), `docs/plans/CONCURRENCY_PROGRAM.md` §S6/S6-UPDATE/S6-DOD (walls ranked: render 107% → memory 78% → ptys 30% → load 2%; design point 150 RESIDENT / ~10 ACTIVE; Waves A closed, C landed, B measured-unbuilt, E precondition passed, F create landed), `session-capacity-ceiling-2026-08-09.md`, `idle-session-occupancy-2026-08-09.md`, `active-session-occupancy-2026-08-09.md`, `pty-ceiling-2026-08-09.md`.

**Known instrument artifacts (every agent must use the corrected instrument):** `ps` RSS double-counts ~1 GB shared libs → use `vmmap` phys_footprint / `top` MEM; `pgrep -f`/argv greps count sessions that *mention* a string → use command-position; `ls /dev/ttys*` carries +16 static legacy nodes → use `ps -axo tty=` distinct; ΔCPU is blind to fork churn → use the 1 Hz R-state sampler (`scripts/occupancy-probe.sh`).

| # | Axis | Sub-questions (each answered by the axis's agent) |
|---|---|---|
| 1 | Memory wall at session AGE | Growth slope MB/h of live sessions (footprint vs age); what grows (heap? transcript? MCP?); equilibrium under the fleet's recycle cadence; corrected 150-resident budget vs the ~45 GB usable denominator |
| 2 | Render wall decomposition | What draws 0.025 cores/pane at idle (blink, statusline cadence, repaint config); kitty levers + expected deltas; pane-count topology at 150/10 (how many panes actually needed); linearity of the 140-pane extrapolation |
| 3 | Headless substrate (E's two gaps) | cc-registry keys on pane UUID → spec identity for pane-less sessions; what wakes an idle headless session (mail → wake path); file:line implementable spec for both |
| 4 | Active-occupancy attribution (Wave B) | Decompose 1.6 runnable-threads/active-session by event class (R-state sampler, not ΔCPU); Stop-event 72–82 forks via 6× wrap-ledger — safe memo design; XProtect/syspolicyd per-exec tax; B's ranked target list with expected Δ-occupancy |
| 5 | Crash-side closure | Does Wave C's landed admission/cap actually bind (diff + tests + mutation evidence); D8 cold-compile-at-80 plan; reso `workerThreads` task status; devserver-gc arming; does 35 GB resident engage compressor/segments at rest |
| 6 | Off-box lane state | Post-`ca7db1a1` create: what stops the first real round trip (NOT-STARTED wall, GitHub App); remaining build list; realistic sessions off-box + when |
| 7 | Account/API ceiling | 150 concurrent vs 4 Max accounts: 5-h/weekly quota arithmetic at 10-active duty cycle; any server-side concurrent-session caps; routing policy so quota never becomes the new wall |
| 8 | Un-modelled platform terms | Derivation-first sweep: Mach ports/WindowServer (incident #0 precedent), fd/vnode/kqueue tables, logd load, XProtect cache behavior, PID churn/wrap, keychain/oauth concurrency, disk/SSD (swap churn, transcript growth, free-space) — verdict each: binds before 150 or not |
| 9 | ADVERSARIAL: constants audit | Re-derive every surviving constant in the S6-UPDATE §6 ranking from primary instruments (0.025 cores/pane, 232 MB, ~45 GB denominator, 1.6 active, 0.0031 idle, 1 pty/pane+2); hunt the FIFTH instrument artifact |
| 10 | ADVERSARIAL: red-team the design | Evidence the 150-resident/10-active design FAILS: sentinel false-positive freezes at 150 legit sessions, Wave-C gate false-negatives, D1 ramp abort risks, headless-fleet failure modes (zombies, mail floods, orphan accumulation) |
| 11 | Prior art + platform levers | How dense agent/dev fleets run on macOS (CI farms, build farms); legitimate exec-assessment reduction; raisable kernel knobs (ptmx_max et al.); Apple Silicon compressor/jetsam tuning lore; kitty many-pane guidance |
| 12 | Felt-lag anatomy | Per-event hook wall-clock (UserPromptSubmit/PreToolUse/Stop) as *felt* input latency; TUI stalls under load; is felt lag an early-warning correlate of segment ramp ("lags THEN crashes") |

**Decomposition: 12 axes → 12 sub-question clusters → 12 parallel subagents.** Adversarial slots: 2/12 (17%). Axes: [memory-age, render, headless, occupancy-B, crash-closure, offbox, accounts, platform-terms, adv-constants, adv-redteam, prior-art, felt-lag].

**Entanglement audit:** tool-pattern spread = Bash-measurement (1,2,4,12) / Read-code (3,5,6) / Web (7,11) / derivation (8,9,10); framing polarity spread = measure / spec / attack / derive; no two productive agents share the same primary source subset. ≤30% pairwise entanglement holds.

**Critic verdict (research-decomposition-critic, 2026-08-09): REVISE → applied.** (1) Axis 1 owns the DYNAMIC memory curve (growth/equilibrium), axis 5 owns the STATIC at-rest compressor engagement — stated in both briefs. (2) Missing term added to axis 8: git ref-lock / shared-store write contention at 150 concurrent sessions (CLAUDE.md § Concurrent Sessions logs it "Observed repeatedly": shared index sweeps, `cannot lock ref 'HEAD'`, shared stash, concurrent `~/.claude.json` writers). (3) Adversarial raised 2→3 of 13 (23%) on the measured same-day 4-artifact correction rate: new axis 13 stress-tests the WALLS RANKING itself (does render>memory>ptys>load survive a fifth correction; does remediation priority change). Sample-row spec added to axes 8/11 briefs: `term/lever | binds-before-150 Y/N/UNKNOWN | evidence (file:line or command) | remedy | confidence`. N: 12 → **13**.

**Spawn-mechanics note (2026-08-09):** named `Agent({name})` spawns are refused in this session — `teammateMode: iterm2` gates on a terminal identity this rebooted session lost (known class; predecessor close). Wave respawned as UNNAMED background research subagents (the shape the skill prescribes anyway).

**Measurement etiquette (binds every agent):** the box under study is LIVE and a sibling ramp (D1) may be running — sample, never stress: ≤1 Hz sampling, ≤120 s per instrument, reuse `scripts/occupancy-probe.sh` / `scripts/pty-census.sh` / `scripts/render-census.sh` where they exist, leave every process running and every config untouched; write only inside `docs/research/scaling-bottlenecks-2026-08-09/`.
