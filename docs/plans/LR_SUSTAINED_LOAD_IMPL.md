---
status: open
---

# Implementation plan: the remaining limit-recover levers under permanent load (completeness-critic corrected, 2026-10-20)

Scope (frozen): build, prove under the measured band mix, and hand to the operator for activation every remaining limit-recover lever from REPORT §4 (B1, A6, B2 stage 1, B3 rescoped, B4, B5 narrowed, B6, B7, A7 parts A-D, D2a/D2b, G2 behind a measured trigger), plus six closures the reviews and the completeness critic found:
- test hermeticity, and the reaper's reach into the rail;
- the actuator load term;
- the typed-prompt retry class;
- the HELD:load verdict;
- the actuator hold reasons that today fall to DETERMINISTIC;
- the typed-relaunch load hold.

File these decisions: A7, D1, D2, B8 (three), C1, the typed-relaunch hold, the pass-boundary restart request, the harness's load and window use, and self-recovery's scope.

Three rules bind every wave:
- No gate waits for load.
- Every timeout we impose means "unknown, retry".
- Every wave ships a kill switch that needs no reload: a file read per call or per pass. Env knobs are secondary.

**Lever codes, expanded once here** (REPORT.md §4-§5; design files under `docs/research/lr-sustained-load-2026-10-20/impl/`):

| Code | Meaning |
|---|---|
| A6 | restart safety: a reconciler restart loses no actuator exit code, no claim, no killed-pass settle |
| A7 | lanes for a session that turns limited while queued: reconciler first, reset poller as a bounded backstop, move lane lets go |
| B1 | load harness: a hermetic simulation tier (Tier G) and a live two-arm rig tier (Tier L) that prove the guarantee |
| B2 | bounded reconciler pass (stage 1 = synchronous bounds; stage 2 = async children, dropped here) |
| B3 | per-record deadline that bypasses soft gates after W_soft |
| B4 | cheap `claude-accounts --place` (client parts C1-C3; reconciler part R1 = the holds map) |
| B5 | kitty off the pre-commit path (B5a = kernel pane identity + one-window probe; B5-R = kitty-free pane binding in the census; K1 = cached-draft proof, deferred) |
| B6 | telemetry (`recon/telemetry.jsonl`, `cc-lr status --rail`) |
| B7 | audit of the pass-scoped `now` (census instant vs action time) |
| B8 | kitty hygiene: App Nap key, official build, fd headroom |
| C1 | zero-restart credential flip (operator-only prototype) |
| C2 | owed prompt over the Claude Code messaging socket; **C2-lite** = making today's typed delivery retry instead of escalate |
| D1 | a recycle re-pick leaves an account the router holds back from new work |
| D2 | moving idle sessions before the weekly wall (D2a = at-the-wall idle fan-out switch; D2b = late-band shed) |
| G2 | each capped session recovers itself from its own priority-31 tree |
| TR | the typed-relaunch hold: handoff-fire's 24/core (commit) and 20/core (precheck) hold whenever no successor of ours is staged (`handoff-fire.sh:4150-4194`, decision 600709c5fe4b) |
| G, G1-G6 | the REPORT §5 invariant and its supporting invariants: no load wait, timeout ≠ verdict, wall-clock pacing, band ≥31, no soft give-up, restart-neutral |
| S1-S5 / H1-H9 / T1-T5 / P1-P4 | Tier G simulation cases / Tier L hard assertions / target assertions owned by a wave / run preconditions |
| W_soft, P_target, P_cap, T_att, B_max, D, D_eff, k_r | guarantee terms: 600 s soft window; observed pass target 180 s (T2); enforced worst-case pass, the sum of W9/W11 bounds; attempt budget; 300 s backoff cap; lane width 6; width actually free; earlier overdue non-held records (REPORT.md:435-443) |

**Baseline at plan time (measured 2026-10-20T19:29:45Z, all read-only).**
- `sysctl -n vm.loadavg hw.ncpu` => `{ 320.20 249.39 223.39 }` `10` (32/core).
- `tail -1 ~/.reso/limit-recover/recon/band.log` => `1792524582 pid=5233 pri=31 floor=31 ok`.
- Open records => 4, all `idle PRE-MOVE PARKED-REBOOT`, open since early October.
- Spawns since the 07:23Z reload => 2.
- `wc -l recon/restarts.jsonl` => 49.

**Live-state leak (measured).**
- `stat` => `~/.reso/limit-recover/recon.on` was modified 2026-10-20T13:51:26-0500, and `locks/swap-slots/slot-1` was rewritten at 13:51 by dead pid 37486.
- Cause (strong hypothesis; code read): `lr_recon/tests/test_restore_budget_bound.py:142-144` builds `Paths.from_env(root=…)` with no env, then `open(paths.recon_on, "w")`. Paths resolve under the real HOME (`types.py:238-241`), and its `M.Ctx` takes live swap slots (`__main__.py:100-105`).
- Severity: if `recon.on` were absent, such a run would **create the operator's actuation cutover file** (B3 §13). This is the third occurrence today (B3 §13 at 17:55Z, the B3 review at 18:08Z, the baseline at 13:51 local).
- W0b closes it before any other wave starts.

**Added at the completeness review (read-only):**
1. An `expectedFailure` that starts passing fails the suite under the plist interpreter. `/usr/bin/python3 -m unittest discover -s /tmp/critic-xpass -p test_xp.py` => rc 1, `FAILED (unexpected successes=1)`.
2. `cc-reaper` TERMs any launchd-parented bash older than 600 s whose argv misses `GARBAGE_WL` (`bin/cc-reaper:737,965`).
   - An actuator wrapper inherited across a restart is ppid 1 (A6 §1.3), and its argv token `lr-recon-act` is not whitelisted.
   - The reaper TERMed `/tmp/lr-rig` processes on 2026-09-29: `grep lr-rig ~/.claude/logs/cc-reaper.log`.
3. The hook's ARM 3 runs `python3 -m lr_recon.facts` in the capped session's cwd (`hooks/stop-failure-marker.sh:620-622`). G2 review C1 measured a cwd import hijack of exactly this shape.
4. `com.reso.lr-move-kick` is still not installed: `ls ~/Library/LaunchAgents` lists no lr-move-kick.

Already landed and not redone: 31f4242e0, 20368fc85, c82a349ce, 58885750c, ed5614054, e6bbd0465, waves 1-5 (07ce89a99, 9316d9842, 9fc5964c3, a8ebaa7c0+a24255bf6, 9d6cd03ff), 28b25a119.

## Phase 0: agent team orchestration

**Status**: IN PROGRESS — every buildable wave was fired and its code landed (`impl/PLAN-STATUS.md`); the lead still owes the Tier-L queue row `bbe7b5b1ba63` and the parked L flips `718ef4662d91` (W5 Part A) and `a76128229b2a` (W12 identity); re-read 2026-10-23, `docs/research/lr-sustained-load-plan-reread-2026-10-23.md`

**Execution locus per wave (first field).**

| Wave | Locus | Why (T/L only) |
|---|---|---|
| W0 | L | lands the 15 design files and this plan as docs, then files the decision packets and needs rows; no code; minutes of lead time |
| W0b | S | dispatched **alone, before any slot starts**: three small safety preconditions (test hermeticity, reaper whitelist, ARM 3 cwd) |
| W1-W17, W4b, W12b | S | default: one dispatched handoff session per wave, in its own worktree and branch. It lands via project-local `/ship`, unwrapped, and converges with `CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh` |
| expectation flips and resolved-debt row removals requested by slot B/C waves | L | one-line edits to `tests/rig/load-expect.json` / `tests/rig/g1-allow.tsv`, landed by the lead so that two sessions never write those files at once |
| one-line default flips (W5 Part A to `on`, W12 identity to `on`) | L | landed only under the edge rules below, never while another wave writing that file is in flight |
| Tier-L run queue and post-reload read-backs | L | the lead runs or schedules every Tier-L pair (one box-wide) and the read-only checks after each operator reload |

**Lead context budget and succession.**
- The lead keeps ≤40% of its window. It holds this plan, a status table and each wave's return, capped at 60 lines.
- The status table records: wave, branch, landed sha, harness verdict line, owed Tier-L runs, pending flips, pending operator steps.
- The lead does not re-read design files. Wave briefs cite them by section.
- **Succession point:** when W10 lands, or at 60% context, whichever comes first. The lead then:
  1. writes the status table to `docs/research/lr-sustained-load-2026-10-20/impl/PLAN-STATUS.md` on its branch;
  2. lands it;
  3. hands off with `/handoff`, naming the plan and the status file.

**Max concurrency: 3 dispatched waves (slots A, B, C) plus the lead.** Why:
- the lr_recon production modules form one serial lane (slot A);
- lands serialize on the ship lock;
- kitty's coalition sits at 482 against a warn level of 500 (B1 M11), so **at most one Tier-L harness run box-wide**. W4's `mkdir` lock enforces this, holding (pid, lstart); there is no `flock` here (`command -v flock` => nothing, B1 review).

**Slot schedule (dependency order inside each slot), after W0b lands:**
- Slot A (lr_recon, serial): W2 → W6 → W8 → W9 → W10 → W11 → W13 → W14 → W17
- Slot B (harness, then routing): W1 → W4 → W4b → W15 → W16
- Slot C (bash lanes and tools): W3 → W5 → W7 → W12 → W12b

**Cross-slot edges.** *Hard* means the waiting wave may not start. *DoD* means only that wave's Tier-L or live done-condition waits; its code may land.

| Edge | Kind | Reason |
|---|---|---|
| W0b → every wave | hard | the leak, the reaper exposure and the ARM 3 cwd hazard are closed before any wave runs suites or rigs |
| W1 → W8 | hard | W8 edits `tests/rig/g1-allow.tsv`, which W1 creates |
| W2 → W7 | hard | both write `lr-band-reload.sh` and `tests/lr-band-reload.bats` |
| W3 → W15; W12 → W15; W12b → W15 | hard | `bin/claude-accounts` (W3), `handoff-fire.sh` (W12, W12b) |
| W5 → W16; W6 → W16; W15 → W16 | hard | `lr-move-worker.sh`/`lr-reset-poller.sh` (W5), `bin/cc-lr` (W6), `bin/claude-accounts` (W15) |
| W12 identity-flip L commit | hard | lands before W12b starts, or rides W12b's branch; never while W12b or W15 is in flight |
| W5 Part A flip L commit | hard | lands before W16 starts, or rides W16's branch |
| W4 → W2, W6, W8, W9, W10, W11, W13, W14, W17 | DoD | their Tier-L pairs need the live tier; owed runs go to the queue |
| W4b → W11, W13, W14, W16, T5 | DoD | guarantee30's move batch, the idle-fanout switch, the kitty-deaf fault, the shed E1 matrix, the move-lane driver |
| W5 → W4b | DoD | T5 proves A7 Part B under the rig |
| W3 → W10 | soft | the map format `{acct: [cfg, bool]}`, compatible in either order (B4 §3) |
| W11, W13 → W16 | soft | slot priority and the limited-slot reservation make E1's bound hold |
| W12 → W14 | soft | W14 reuses W12's identity rules; its value depends on W12 being on |
| W9, W11, W12, operator reload RK (W7) → W17 | hard | slot rename-steal and tri-state lstart (W9), the soft self claim (W11), identity (W12), router-cache producers at 31 (W7 plus the operator reload) |

**File ownership.** Waves that can run at the same time touch disjoint files.

| Wave (slot) | Files it may write |
|---|---|
| W0b | `lr_recon/tests/test_restore_budget_bound.py`, `bin/cc-reaper`, `tests/cc-reaper.bats`, `hooks/stop-failure-marker.sh` (ARM 3 only), `tests/stop-failure-fact-cwd.bats` (new) |
| W1 (B) | `tests/rig/{stub-claude.py, lr-recon-rig.sh, rig_lib.py, g1-allow.tsv, faults/smoke3.json, shims/launchctl, shims/osascript}`, `lr_recon/tests/{test_guarantee_sim.py, test_hermetic_ctx.py}`, `tests/{rig-stub, lr-recon-guarantee-sim, lr-guarantee-g1-lint}.bats`, `tests/fixtures/lr-recon/{jsonl,screens}/*` |
| W2 (A) | `lr_recon/{act,settle,types,__main__,store}.py`, `lr_recon/tests/{test_restart_safety,test_act,test_settle}.py`, `lr_recon/tests/test_guarantee_sim.py` (S5b flip only, if W1 has landed), `tests/lr-recon-restart-claim.bats`, `scripts/limit-recover/lr-band-reload.sh`, `tests/lr-band-reload.bats` |
| W3 (C) | `bin/claude-accounts`, `scripts/limit-recover/lr-transplant.sh`, `tests/{claude-accounts-place, claude-accounts-util-tail, lr-transplant}.bats` |
| W4 (B) | `tests/rig/{loadgen.py, runq.py, load_lib.py, lr-load-harness.sh, kitty-slow, kitten-slow, fake-claude-accounts.py, stub-claude.py, faults/guarantee9.json, faults/guarantee30.json, load-expect.json, rig_lib.py, lr-recon-rig.sh}`, `tests/lr-load-harness-lib.bats`, `tests/fixtures/lr-load-harness/*` |
| W4b (B) | `tests/rig/{lr-recon-rig.sh, rig_lib.py, kitty-slow, poller-standin (new), faults/move9.json (new), faults/shed-e1.json (new), faults/kitty-deaf.json (new), faults/guarantee30.json}`, `tests/rig-move-lane.bats` (new) |
| W5 (C) | `scripts/limit-recover/{lr-reset-poller.sh, lr-fleet.sh, lr-move-worker.sh}`, `tests/{lr-reset-poller-recon-first (new), lr-move-worker, lr-fleet}.bats` |
| W6 (A) | `lr_recon/{telemetry.py (new), band.py, clock.py, types.py, __main__.py, report.py}`, `bin/cc-lr`, `lr_recon/tests/test_telemetry.py`, `tests/lr-recon-telemetry.bats` |
| W7 (C) | `scripts/kitty-hygiene.sh` (new), `scripts/lib/kitty-naps.py` (new), `scripts/lib/kitty-fd-headroom.py` (new, the O2b no_ui kitten; `scripts/lib` is globbed `*.sh`/`*.py` by `install.sh:700-712`), `bin/cc-restore`, `scripts/alarm-reboot-prep.sh`, `launchd/staged/com.claude.accounts-{keepwarm,local}.plist`, `scripts/limit-recover/lr-band-reload.sh`, `tests/{kitty-hygiene, cc-restore, alarm-reboot-prep, lr-band-reload, accounts-local-job}.bats` |
| W8 (A) | `lr_recon/{__main__,settle,admit,act,report,evidence,classify,types,clock}.py`, `lr_recon/tests/{longpass.py, test_now_audit.py, test_classify.py, test_report.py, test_main.py}`, `tests/lr-recon-now-audit.bats`, `tests/rig/{g1-allow.tsv, load-expect.json}` |
| W9 (A) | `lr_recon/{clock,act,store,admit,__main__,report,types,observe}.py`, `lr_recon/tests/{test_bounded_pass, test_step_per_child, test_admit, test_store}.py`, `tests/lr-recon-watchdog.bats` |
| W10 (A) | `lr_recon/{types,transcript,plan,__main__}.py`, `lr_recon/tests/{test_place_holds.py, test_main.py}` |
| W11 (A) | `lr_recon/{types,clock,admit,classify,settle,plan,__main__,report}.py`, `scripts/limit-recover/lr-move-lib.sh`, `lr_recon/tests/test_deadline.py`, `tests/{lr-recon-deadline, lr-move-slot-priority}.bats`, `tests/rig/load-expect.json`; conditional on the token-TTL measurement: `scripts/lib/capacity-admit.sh` |
| W12 (C) | `scripts/handoff-fire.sh`, `scripts/limit-recover/lr-lib.sh`, `bin/it2-kitty`, `tests/{handoff-kernel-identity (new), handoff-pane-proof-only (new), handoff-probe-preconditions, handoff-recycle-kitty-precheck, lr-lib}.bats` |
| W12b (C) | `scripts/handoff-fire.sh`, `tests/{handoff-typed-relaunch-hold (new), handoff-probe-preconditions}.bats` |
| W13 (A) | `lr_recon/{report,act,__main__,census,types}.py`, `lr_recon/tests/{test_report,test_act,test_main,test_idle_fanout_switch}.py` |
| W14 (A) | `lr_recon/{observe,observe_rows,types}.py`, `lr_recon/tests/test_pane_bind_env.py`, `tests/fixtures/lr-recon/ps-env/*` |
| W15 (B) | `bin/claude-accounts`, `scripts/handoff-fire.sh`, `accounts.json`, `tests/{handoff-recycle-repick, account-recovery-lane}.bats` |
| W16 (B) | `scripts/limit-recover/{lr-shed.py (new), lr-move-worker.sh, lr-reset-poller.sh, lr-move-batch.sh}`, `bin/claude-accounts`, `bin/cc-lr`, `tests/{lr-shed (new), lr-move-worker, lr-reset-poller-shed-kick (new)}.bats` (no `tests/rig/*`; E1 uses W4b's `faults/shed-e1.json`) |
| W17 (A) | `hooks/stop-failure-marker.sh` (ARM 4), `lr_recon/{selfrec.py (new), seats.py (new), store,plan,act,__main__}.py`, `scripts/limit-recover/lr-handoff.sh`, `tests/rig/{rig_lib.py, lr-recon-rig.sh, faults/self9.json (new)}`, `lr_recon/tests/{test_selfrec.py, test_seats.py, test_selfrec_fence.py}`, `tests/{stop-failure-self-recover, lr-handoff-placed-self, lr-self-recover}.bats` |

**Disjointness proof for every pair that can run at the same time.** A shared file appears only on pairs separated by a hard edge.

| Pair that can overlap | Shared files | Why safe |
|---|---|---|
| W1 ∥ W2 ∥ W3 | none | W2 edits `test_guarantee_sim.py` only after W1 has landed, which is a sequence, not an overlap |
| W4, W4b ∥ {W6, W8, W9, W10, W11} | none | W4/W4b write `tests/rig/*` except `g1-allow.tsv`. Slot A writes only `g1-allow.tsv` (W8) and `load-expect.json` (W8, W11), and those only after W4 has created it |
| W5, W7 ∥ slot A | none | W7's `lr-band-reload.sh` is also W2's: hard edge W2→W7 |
| W12, W12b ∥ slot A, slot B up to W4b | none | `handoff-fire.sh`/`lr-lib.sh`/`it2-kitty` are slot C only until W15 |
| W15 ∥ slot A | none | `bin/claude-accounts` (W3) and `handoff-fire.sh` (W12, W12b) come before W15 by hard edges |
| W16 ∥ slot A (W13, W14, W17) | none | `bin/cc-lr` (W6) and `lr-move-worker.sh`/`lr-reset-poller.sh` (W5) come before W16 by hard edges |
| W17 ∥ W16 | none | W16 writes no `tests/rig/*`, no lr_recon, no hook |

**Shared expectation files.**
1. After W1 lands, `tests/rig/g1-allow.tsv` and `lr_recon/tests/test_guarantee_sim.py` are written only by the slot-A wave in flight. After W4 lands, `tests/rig/load-expect.json` follows the same rule.
2. Slot B and C waves return their flip request (row, harness run id, verdict line) to the lead. The lead forwards it to the slot-A wave in flight, or lands it as an L commit when slot A is idle.
3. A resolved `debt:` row never blocks a land (see W1 lever 5). The lead removes it later.
4. **A land that makes an `expectedFailure` pass flips it in the same commit.** An unexpected success fails unittest under 3.9.6 (measured, baseline item 1).

**Tier-L run queue (lead-owned).**
- One run box-wide. A wave's Tier-L DoD becomes an *owed run* when its wave lands before the needed tier (W4 or W4b) exists, or when the lock is held.
- The lead runs owed pairs in landing order from a band-31 context:
  - with `--detach`;
  - in `wait` slices of at most 270 s;
  - against `--red tree:<wave parent>@31`.
- It records each verdict line in the status table and hands the resulting flips to the slot-A wave in flight.
- `NO-VERDICT` (lock held, production busy, load below the premise floor, a reaper TERM of an arm process) means retry later, never a wait inside a wave.

**Rules every wave brief carries** (from `.claude/rules/*.md` and the reviews):
- Work in your own worktree. Never `git stash`, `rm -r`, `git reset --hard` or heredoc writes.
- Land with `/ship` unwrapped ("Never wrap /ship", rules :36), then run the diff's suites yourself ("Landed ≠ tested", :49).
- Assert the `1..N` plan line of every bats run ("Gate refusal ≠ gate result", :38).
- Run lr_recon suites under `/usr/bin/python3` (3.9.6, the plist interpreter) and bash suites under `/bin/bash` 3.2 ("Deployment interpreter ≠ yours", :47).
- Every test sets HOME, `LR_STATE_DIR`, `LR_RECON_ROOT` and TMPDIR under `/tmp`.
- Every new rule gets a mutant that dies ("Green in both arms", situational :62).
- Every live reading carries load1 and the band beside it ("Verify a cure under its load", :83).
- No `launchctl`, no typing into panes, no signals except to the wave's own `/tmp` processes.
- A new lr_recon module that `__main__` imports is imported guarded, so a converge that links it late cannot crash-loop a restart (G2 C12).
- Long unattended drivers are Python or covered by W0b's reaper whitelist ("Detached bash is reaped at 10 min", situational :215).
- After folding review changes, audit the brief by artifact, not by edited span ("Integration manufactures contradictions", situational :187).

**Operator activation batches for reconciler code.**
- Agents may not reload launchd jobs (`lr-band-reload.sh:4-5`).
- A wave is done when its code is landed, converged and proven by Tier G plus its Tier-L pair (owed runs included).
- Production activation is a separate operator step that does not block the next wave.

| Batch | After | Operator command | Read-back (lead, read-only) |
|---|---|---|---|
| R1 | W2 | `bash ~/.claude/scripts/limit-recover/lr-band-reload.sh` (dry run), then `bash ~/.claude/scripts/limit-recover/lr-band-reload.sh --confirm lr-band`. Its bounded quiet wait applies. If it refuses after 1800 s, re-run with `--now`, accepting the one-time loss of old-wrapper exit codes (A6 F-J option 1) | `tail -1 ~/.reso/limit-recover/recon/restarts.jsonl` shows the new forensics keys; `tail -1 recon/band.log` shows the new pid with `pri=31 … ok` |
| R2 | W6 + W8 | `… --confirm lr-band --now` (A6 is live, so a mid-act restart loses no code) | `tail -n 3 recon/telemetry.jsonl`; `cc-lr status --rail` |
| R3 | W9 + W10 | same | the heartbeat has `pass_at` and `pages_queued`; the next `place` event carries `holds=n/n holds_s=` |
| R4 | W11 + W13 | same | open limited records in `recon/sessions/*.json` carry `deadline_at`; `ls -la ~/.reso/limit-recover/locks/slot-priority` shows an `until` in the future while overdue records wait |
| R5 | W14 (+ W17 yield stamp) | same | `recon/features` contains `self-yield-1` (W17 only) |
| RK | W7 | `bash ~/.claude/scripts/limit-recover/lr-band-reload.sh --keepwarm`, then `--confirm keepwarm-band` | `ps -M -p <keepwarm pid>` and `ps -M -p <accounts-local pid>` read ≥ 31 |

If the operator rules yes on the pass-boundary restart request (W2 lever 11), the lead runs `touch ~/.reso/limit-recover/recon/ctl/restart.request` for R2-R5 instead.

## W0: land the designs, file the decisions, record the baseline (L) — DONE (2026-10-20 20:31Z, lead pane 187)

- Designs and plan landed `dc13d1a09` (15 files under `impl/`; no separate `impl/PLAN.md` was written, so this plan file is the PLAN receipt, used for the TR packet). Converged: the live checkout reads `dc13d1a09`.
- Filed (class B packets, as specified): A7 `4ffc4e1e5f1c`, D1 `0223cae3d185`, D2b `76a584cc935b`, D2a `c9a05672e692`, TR `db44ab0ebc55`, pass-boundary restart `5353dd6e8277`, harness top-up load `4eee30ac4de4`, harness windows `75bb72581c54`, G2 scope `4ab193daae88`, B8-2 `74b9bd774c40`, B8-3 `1ef91f32a58c`, B8-4 `1c7000af9e41`, C1 `745e0fdc78e6`.
- Filed needs rows: B8 App Nap `d25661ba57f1`, fd headroom `7e912ef257cb`, kitty restart `1c94119a286d` (`--confirm 853`, the main kitty), C1 credentials `bd40ec7f3d4f` / `156c1aa935e7` (needs-credential), R1-R5 reload `b8bbc2317870`, RK `626ed25b243c`, D2b shadow `f259e20643bf`. Backlog rows: `6473702a6bfe` (boot-resume load wording), `d80b297539d5` (move-path per-sid globs).
- Learning: `handoff-fire.sh` refuses a brief whose `cc-notify` target is a pane number (F3 back-channel check); name the lead's full session uuid.

- **Goal.** Make the 15 reviewed designs and this plan durable on `main`, so that every decision receipt and wave brief resolves to a tracked file.
- **Actions, in order.**
  1. Land `docs/research/lr-sustained-load-2026-10-20/impl/*.md` plus `PLAN.md` written from this plan. They are untracked now: `git status` => `?? docs/research/lr-sustained-load-2026-10-20/impl/`.
  2. Converge.
  3. Only after converge, check `ls` of every `--receipt` path. The receipts are main-checkout paths, which are absent today.
  4. File the packets, needs rows and backlog rows in "Operator decisions and actions".
  5. Dispatch W0b alone.
- **Done.**
  - `git ls-tree origin/main -- docs/research/lr-sustained-load-2026-10-20/impl/ | wc -l` => 16.
  - `cc-decide list --open --json | jq length` grows by the 14 packets filed now. The thermal packet is conditional, and the act-mode packet is filed later.
  - `cc-backlog list --open --json` shows the needs and backlog rows listed below.
- **Kill switch / reload.** None (docs).

## W0b: safety preconditions (S; dispatched alone, before any slot starts) — DONE (`3471aebea` `d8fb9210b` `79090c717` `9f005ae66`, grown `b24389ff7`)

- **Goal.** Close three exposures before any wave runs suites or live rigs:
  - lr_recon tests that reach live state;
  - the reaper killing inherited actuators and the rig;
  - the hook importing from a capped session's cwd.
- **Levers.**
  1. **Hermetic test.** `StandingRefusalIsVisible.setUp` (`test_restore_budget_bound.py:136-145`) builds `Paths.from_env(root=…, env={"HOME": self.home, "LR_STATE_DIR": self.tmp + "/lr"})` and asserts `self.paths.lr_root.startswith(self.tmp)`. That assertion is red at HEAD even under a sandbox HOME, because HEAD resolves `lr_root` under `$HOME`.
  2. **Reaper whitelist.**
     - `GARBAGE_WL` (`bin/cc-reaper:737`) gains `lr-recon-act`, the actuator wrapper's own argv token (`act.py:34`). An actuator inherited across a reconciler restart is ppid 1 (A6 §1.3) and is no longer TERMed as `orphan-bash` at 600 s (`:965`).
     - It also gains `/tmp/lrh-[0-9A-Za-z]+-(cure|red)/`, the harness arm roots, so the rig's detached bash supervisor survives a 75-min run.
     - Hypothesis on frequency: no such actuator kill is in the current log (`grep -c` => 0), but the rule matches by construction, and the reaper TERMed `/tmp/lr-rig` processes on 2026-09-29.
  3. **ARM 3 cwd.** The hook's fact write (`hooks/stop-failure-marker.sh:620-622`) runs `cd "$_sf_lrd"` in a subshell before `/usr/bin/python3 -E -s -m lr_recon.facts`. A planted `json.py` in the capped session's cwd can then no longer run against live facts (G2 review C1 measured that hijack shape).
- **Red controls.**
  - The `lr_root` assertion is red at HEAD.
  - A `tests/cc-reaper.bats` fixture: a launchd-parented `/bin/bash -c shift 4; "$@" lr-recon-act --record-id r --intent 0123456789ab …` aged 700 s is classified `orphan-bash` at HEAD and skipped after. A plain orphan bash is still classified (control). The mutant "drop the WL entry" goes red.
  - `tests/stop-failure-fact-cwd.bats`: the hook run from a cwd holding a planted `json.py` that writes a marker. The marker exists at HEAD and is absent after.
- **Done.**
  - `HOME=/tmp/w0b/h LR_STATE_DIR=/tmp/w0b/lr TMPDIR=/tmp/w0b/t /usr/bin/python3 -m unittest lr_recon.tests.test_restore_budget_bound` (in `scripts/limit-recover`) => OK.
  - `bats tests/cc-reaper.bats tests/reap-sweep-bounds.bats tests/autonomy-sweep.bats tests/stop-failure-marker.bats tests/stop-failure-fact-cwd.bats`: plan lines asserted, 0 `not ok`.
  - `stat -f %m ~/.reso/limit-recover/recon.on` and `ls -la ~/.reso/limit-recover/locks/swap-slots` are recorded before and after the wave's own runs and are unchanged.
- **Kill switch.** Revert. **Reload.** None. The reaper and the hook read their source on each run, so both are live at converge.

## W1: load harness, hermetic tier (B1 part 1; slot B) — DONE (`e6713c4da`..`2d99d8e93`, S5b hard `a12101b6c`)

- **Goal.** A seconds-long, land-gate tier that proves three things: the decision code never reads load; it never turns our timeout into a verdict; and it bounds first and retry attempts on a virtual clock. Plus the rig repaired and made safe.
- **Levers (design §9.1-9.5 and §9.11, with every review change):**
  1. **Hermetic lint.** New `lr_recon/tests/test_hermetic_ctx.py`, an AST lint. It fails any test that constructs `M.Ctx` or `Paths.from_env` without an env or an `LR_STATE_DIR` under `tempfile`, and any `open(<paths>.recon_on …, "w")` on a non-temp root. Red on a `git archive` of W0b's parent in `/tmp`, and on a planted file.
  2. **Rig repair.**
     - `stub-claude.py` honours the positional prompt after `--resume`. Today `:614-617` drops what `lr-fire-resume.sh:1734` passes (M10).
     - Stub tests run under a pty ended by SIGHUP (`termios.tcgetattr` at `:385`).
     - The `go_barrier` death is guarded by `not self.resumed` plus a `died_at` mark. With idle fan-out on, waiting members boot WORKING, never idle (C15, both halves).
  3. **Rig safety** (correctness S1-S4, S9, C13-C14):
     - Kills only by verified (pid, lstart, argv containing the arm root), for teardown (`lr-recon-rig.sh:73-74`) and drive (`rig_lib.py:449-456`), because pids advance ~800/s (measured by the reviewer).
     - Teardown first kills every `rig_procs(rig)` process by verified identity, then closes windows. A second sweep runs about 30 s later. Leftovers are listed in `rig-result.json` (S3).
     - A per-arm deadman.
     - `launchctl`/`osascript` no-op shims come first on the rig PATH (`tests/rig/shims/`), plus `CC_LR_POLLER_LABEL=rig.invalid`; `bin/cc-lr:76,1112-1115` would otherwise kickstart the real poller.
     - The root guard `[[ $RIG =~ ^/tmp/lrh-[0-9A-Za-z]+-(cure|red)$ ]]`.
     - At most 2 members per single-tab OS window, with a containment sampler, because placement rule 2 scans every kitty OS window (`pane-placement.sh:39-41,134-145`; `lr-handoff.sh:2260-2269`).
     - `$KITTY_REAL` is defined before use under `set -u`.
  4. **Tier G simulation.** `test_guarantee_sim.py` drives the real `run_pass` on a virtual clock and starts no real child: `subprocess.Popen/run`, `clock.run_bounded`, `store.proc_lstart` (`store.py:530`), `_run_snap` and `_provenance` are patched to raise (F3). It scans every lr_recon function's `__defaults__`/`__kwdefaults__` for `os.getloadavg` (`clock.py:82`, `observe.py:91`; F2). Cases:
     - S1: the decision trace is identical at load1 {5, 150, 250, 400, 1000} on 10 CPUs. The mutant "`pace_ok` requires load/ncpu < 2.0" must turn it red (F1).
     - S2: k ≥ 7, simulated T_att > 20 s, and `ctx.boots.limit == 6` asserted on every pass, so wiring the dead AIMD (`admit.py:422`) turns it red (F4).
     - S2b: the restore budget with active > R (F5).
     - S3: ≥ 6 consecutive TRANSIENT failures; the backoff reaches 240 then 300, never more (`classify.py:18,173`).
     - S4: ≥ 5 consecutive rc-124 placer passes (`KEEP_MAX_MISSES` 3, `plan.py:54,372-373`); never a verdict.
     - S5a (hard if it holds at HEAD): a restart leaves `t_detect` unchanged and starts no second spawn.
     - S5b: the claim is not re-stamped to the new daemon (C16). It is `expectedFailure` with owner W2 if W2 has not landed; if W2 has landed, W1 writes it hard (Phase 0, shared-file rule 4).
     - `k_r` is as REPORT.md:441 defines it (C17).
  5. **G1 lint** (`tests/lr-guarantee-g1-lint.bats`, `tests/rig/g1-allow.tsv`).
     - **Row classes:** `telemetry | capped-bound-stretch | env-off:<function> | debt:<owner>`, anchored on function names. Debt rows are printed (F11).
     - It flags `from os import getloadavg` and aliases.
     - A bound-stretch row must show its `min(MAX, …)` cap (F12).
     - **Stale rows:** a stale `telemetry` or `capped-bound-stretch` row fails. A stale `debt:` row prints `RESOLVED (remove row)` and passes, so a slot-C wave that resolves debt is never blocked by a file it may not write.
     - **Rule 3:** a bare `cc_capacity_admit`/`cc_capacity_probe` is a violation unless an `env-off:<function>` row names the one function that builds every rail caller's env and a test proves it sets the term off. `${X:-off}` passes only if no rail environment sets X (F10, C7).
     - **Files scanned:** `lr_recon/**`, `scripts/limit-recover/*.sh`, `handoff-fire.sh`, `boot-resume-launch.sh`, `bin/reso-resume-one`, `bin/cc-lr`, `capacity-admit.sh`, `bin/cc-wave-plan`, `bin/cc-dispatch`, and the `--place`/`--rank` path of `bin/claude-accounts`.
     - **Seeded debt rows:**
       - `hf_lr_admit` (`handoff-fire.sh:17961-17962`) → W12;
       - `boot-resume-launch.sh:429` under the actuator env → W8, which converts it to `env-off:act.actuator_env`;
       - `clock.load_multiplier` (`clock.py:156-164`, uncapped, no caller) → W8;
       - `hf_recycle_load_gate` (`handoff-fire.sh:4183`) → `debt:typed-relaunch` (W12b and the TR ruling);
       - `bin/reso-resume-one:306` → `debt:resume-sessions` (off the rail: no rail caller, `grep -rn reso-resume-one` in the actuators finds comments only).
     - **Allowed, capped:** `plan.place_timeout` (`plan.py:358`, 120 s), `observe.ps_bound` (40 s), `hf_load_scaled` (`:4957`, ×4), and `bin/cc-lr` `cl_self_wait_s` (`:330-341`, ×4).
     - The build enumerates and classifies the other load matches in `handoff-fire.sh` (B1 §9.10).
  6. **Postland safety.** Tier-G cases that start Python and wait skip with a counted reason when `band.py $$` reads < 20, because postland runs suites at background QoS (`postland-verify.sh:14-18`; C11/F18). Before landing, run the three suites under `taskpolicy -b` and assert their `1..N` plan lines and skip counts.
- **Red controls.**
  - C1: the `rig-stub.bats` argv-prompt token case, red on today's stub.
  - C2: S1-S4 are each killed by their named mutant; record "mutant → red" in the commit.
  - C3: the lint is red on a planted bare `getloadavg`, on an emptied allowlist, and on a stale telemetry row. A resolved debt row passes and prints RESOLVED.
  - The hermetic lint is red on W0b's parent.
- **Done.**
  - In `scripts/limit-recover`: `HOME=/tmp/w1h LR_STATE_DIR=/tmp/w1h/lr TMPDIR=/tmp/w1h/t /usr/bin/python3 -m unittest discover -s lr_recon/tests -t .` => `Ran N tests … OK`.
  - `bats tests/rig-stub.bats tests/lr-recon-guarantee-sim.bats tests/lr-guarantee-g1-lint.bats` => plan lines `1..N`, 0 `not ok`.
  - `bash tests/rig/lr-recon-rig.sh --n 3 --faults tests/rig/faults/smoke3.json` exits rc 0 twice, after a pre-fix legacy-path run (no `go_barrier`, `LR_RIG_REQUEST=cc-lr`, shims on PATH) that shows the mechanism: a prompt-argv note, then a C spawn ≥ 600 s after the relaunch per `LAUNCHER_CHAIN_MAX_S` (`settle.py:756,819-823`; C10/F21).
- **Kill switch.** Tests only; revert. **Reload.** None.

## W2: restart safety (A6; slot A)

**Status**: IN PROGRESS — code LANDED `1eb5548ac` `45b8bbfa9` `288b5f897`, live since reload R1 (2026-10-21 02:30Z); owed: the guarantee9 pair (tries `20261021T102850Z9471`, `20261021T120053Zdc2a` read NO-VERDICT on the premise; re-run after W14f `b8ce080ca`), Tier-L queue row `bbe7b5b1ba63`

- **Goal.** A restart loses no exit code, never re-stamps an in-flight claim to the new daemon, and replays a killed pass exactly once. Every later reload is then safe mid-cohort.
  - About half of all restarts are watchdog TERM kills under load: `grep -c 'KILL -TERM' watchdog.log` => 28, 24 of 48 restarts (A6 efficacy review).
  - Measured motive: 9 of 54 own-actuator exits had no code between 09-30 and 10-20, all restart-associated (A6 §1).
- **Levers (design (a)-(e) plus both reviews):**
  1. **Durable exit file.**
     - `WRAPPER` (`act.py:34`) writes the child's rc with builtins to `recon/exits/<12-hex nonce>.rc` and exits with it.
     - `ProcRole.nonce` (`types.py:404-410`); `Paths.exits` in `reconciler_dirs` (`types.py:360`).
     - `read_exit` validates hex; `_WRAPPER_TOK` is anchored on `/bin/bash -c `.
  2. **Reader-side identity.**
     - `_CHILDREN[pid] = (proc, nonce)`.
     - `dead_actuators` (`settle.py:561-565`) reads the file first, then accepts an in-memory code only when the nonces match, and pops it once consumed.
     - The `waitpid(-1)` loop in `reap_children` (`act.py:394-415`) stays for W9 to delete.
     - `test_settle.py:275-281` stays valid via `spawned=None` (S-4, efficacy 7).
  3. **Adoption and dedupe.** `adopt` (`act.py:360-372`) repairs an entry that already carries the nonce instead of appending. A dead entry whose nonce a live entry carries settles `None` (S-3, efficacy 6).
  4. **Stale-spawn guard.** Capture `want = rec.intent.nonce` before `prune_dead`. A dead proc with another nonce settles `None`, with a `stale-exit` event. An intent-only exit file is settled once under `intent.actuator` before the intent is cleared (S-5, S-9).
  5. **Claim keeper.**
     - `claim_holder_for` considers only named wrappers (or a wrapper adopted by nonce); otherwise the holder is the daemon. Control on the 4fe9935f shape (efficacy 1).
     - `keep_claim` runs only in `daemon()`, after the flock, never in `--once` (`__main__.py:1893-1897`; S-2).
     - It runs for every open record in a cheap loop right after the abstain gate (`__main__.py:1684`) and before `_facts`/`_census` (efficacy 4).
     - It never raises: `OSError` means unknown, retried next pass. It re-reads after the write and emits a `claim-race` event on a mismatch (S-6).
  6. **Startup.**
     - `daemon()` reads the previous heartbeat for the restart row, then writes the new heartbeat before `_startup`'s claim loop, using one `proc_lstart` for both (`__main__.py:1790`, `:1822`; efficacy 5).
     - "Inherited" means `rec.intent is not None` or any actuator-role proc, named or adopted (efficacy 2).
     - Stamp the last named actuator's recorded (pid, lstart) when that lstart is non-empty; otherwise re-stamp the live daemon.
     - Never leave an old-daemon claim with an empty lstart, which bash judges by pid alone (`lr-lib.sh:810-819`; S-1, efficacy 3).
  7. **Bookkeeping order.** `rec.close["move_attempt"]` is set before `act.spawn`, so it rides the pre-Popen intent save (`__main__.py:1313`; S-8). `wake_eta` stays after spawn.
  8. **Forensics row** in `restarts.jsonl`: `inflight`, `inherited`, `prev_phase`, code fingerprint. It never raises.
  9. **Reload predicate.** `lr-band-reload.sh:153-157` also counts every live `lr-recon-act` process (ppid 1 included) whose `--record-id` names an open record (S-11, efficacy rollout).
  10. **Kill switches are semantic.** `recon/claim-keeper.off` means "the holder is always the daemon", never "write nothing" (S-7). Also `recon/exit-files.off`.
  11. **Optional, inert until ruled.** A `recon/ctl/restart.request` pass-boundary restart, enabled only when `recon/restart-request.on` exists. Both its own row and the startup row that follows it are exempt from the restart-loop page (S-11).
  12. **Owner of the page-only `RECON-DEFECT PRE-MOVE/None` class** (an unknown exit with no NOTMOVED, `settle.py:205-209`, `:236-272`): W11 lever 10.
  13. **`lr-band-reload.sh --now`.** It skips the bounded quiet wait (`:36`, `:158-160`). The script's help says it is for batches after R1, when an inherited actuator keeps its exit file and claim. R1 itself keeps the wait (A6 F-J, B4 F5).
  14. **S5b flip.** If W1 has landed, this wave writes S5b as hard in `test_guarantee_sim.py` in its own commit. An unexpected success fails the suite (baseline item 1).
  15. **Reaper.** W0b already whitelists `lr-recon-act`. This wave's bats case 1b also asserts that an inherited wrapper survives one `cc-reaper` classification pass on a fixture snapshot.
- **Tests (red at HEAD unless marked CONTROL).**
  - Design py1-py18 with 12-hex nonces (`n1` writes no file; S-10).
  - Test 11 with a killable mutant: the keeper writes an absent claim.
  - The F10 duplicate shape is scored exactly once.
  - An intent-only record across a restart is not re-stamped to the daemon.
  - Unfenced C record + a taker that skips the fence + live inherited wrapper ⇒ held-live.
  - py8b: a first pass with a `ps` shim delayed 35 s still re-stamps before `_dispatch`.
  - A real `/bin/bash` 3.2 wrapper writes 0/6/143, equal to `Popen.poll()`.
  - S-11 stale phase: an old exit file plus a derive that proves MOVED leaves the record open and not escalated.
  - Bats `lr-recon-restart-claim.bats`:
    - case 1 (today: `foreign pid=<daemon2> by=lr-reconciler`);
    - 1b;
    - 2 CONTROL (a live stranger is still refused);
    - 3 power (`claim-keeper.off` reproduces the refusal).
    - All sandboxed per S-10: patched `observe.observe`, an `LR_PAGE_BIN` stub.
  - `test_act.py:276-292` strips `LR_RECON_ROOT` from the spawn env.
  - `lr-band-reload.bats` gains a `--now` dry-run case and a refusal case for an unknown flag.
- **Done.**
  - Unittest `Ran N … OK` under `/usr/bin/python3`.
  - `bats tests/lr-recon-restart-claim.bats tests/lr-band-reload.bats` with plan lines.
  - **Owed Tier-L run (queue, once W4 lands):** `bash tests/rig/lr-load-harness.sh run --matrix tests/rig/faults/guarantee9.json --arms cure,red --red tree:<W2 parent sha>@31`. T4 (zero `another actuator holds session` after `kill9_post_transplant`) must PASS in cure and FAIL in red (power). The flip goes to the slot-A wave in flight.
  - **Live acceptance after R1** (L, read-only), over ≥ 3 restarts with `inflight ≥ 1`:
    - zero own-actuator `code unknown` exits;
    - zero `move claim (pid` actlog lines;
    - a count of `RECON-DEFECT PRE-MOVE/None` records whose move exit left no exit file, expected 0 (A6 R.3 #8).
- **Kill switch.** `touch ~/.reso/limit-recover/recon/claim-keeper.off` and/or `recon/exit-files.off` (read every pass).
- **Reload.** R1. The first restart still loses the codes of old-wrapper actuators in flight (accepted; design §10).

## W3: cheap `--place`, client side, plus the arrival check (B4 C1-C3; slot C) — DONE (`c79df708d`)

- **Goal.** Make `claude-accounts --place` cost a fraction of a CPU-second and stop growing with the corpus.
  - B4 measured at priority 31 with 9 movers: originally 4.75-11.7 s and 4.3-4.9 CPU-s; the prototype 0.15-0.56 s and 0.15 CPU-s.
  - `--rank`, `--route` and the board stop re-parsing 19.5 MB on ~85% of calls (B4 review F3, measured).
- **Levers.**
  - **C1.** `cmd_place` trusts a per-mover map shipped as `{acct: [cfg, bool]}` only when `realpath(cfg) == realpath(dirs[a])` (single source of truth, correctness F5). Otherwise it globs (`holds` at `bin/claude-accounts:6637-6638`, called at `:6658`).
  - **C2.** `apply_burn`'s read for `--place` covers 49 h, not 336 h (`:4856`). The three fields read (`burn_5h_ewma_ph`, `burn_5h_ph`, `wk_strand_pp`) are bit-identical.
  - **C3.** `_util_tail_read` (`:4657-4748`) stops once a slice reaches back past `cutoff − UTIL_TAIL_CROSS_SLACK_S` (3600 s), with an unconditional `out.sort(key=_t)`. The time-order precondition is cited (`:8319`, `:7124`, `:8125-8147`).
  - **Arrival check.** `lr-transplant.sh`'s admit refusal widens from the same slug to `$TO/projects/*/$SID.jsonl`: one glob per move, 1.2-2.4 s at load1 241-247 (B4 review F10). A different-slug copy then becomes a re-place instead of a "multiple copies" strand (`lr-transplant.sh:869-885`; correctness F4).
- **Tests.**
  - P1-P7, plus the mutant "trust any cfg" (red).
  - P5/P6 burn equivalence; the mutant 24 h goes red.
  - U1-U4, and U5 (one write inversion straddling the cutoff, red on the prototype per `c3adv.py`). U2 is offset so no row lands within 60 s after the cutoff.
  - E1 is a scaling assertion: a 20-day and a 60-day series with identical last 49 h give equal `json.loads` counts. The absolute 5,000 bound is dropped, because the prototype measured 11,880-13,865.
  - Arrival test: a copy under another slug is refused before any tombstone. Today it passes the arrival check.
  - The file switches are read per call (case: switch file present ⇒ glob / 336 h / old stop rule).
- **Done.**
  - `bats tests/claude-accounts-place.bats tests/claude-accounts-util-tail.bats tests/lr-transplant.bats` with plan lines (today 1..23, 1..8, 1..33, plus the new cases).
  - A differential over 40 randomized frozen cases => 0 mismatches.
  - `/usr/bin/time -p claude-accounts --place …` (cache-only, log redirected) from a PRI-31 shell: **user+sys ≤ 0.3 s** (load-independent). Wall time is reported beside load1/ncpu and is not a threshold, because wall time under 15-40/core reads the band.
- **Kill switch.** Files read per call: `~/.claude/state/place-holds-map.off`, `~/.claude/state/place-burn-narrow.off`, `~/.claude/state/util-tail-cross.off`. The env forms `CC_PLACE_HOLDS_MAP=off`, `CC_PLACE_BURN_NARROW=off` and `CC_UTIL_TAIL_CROSS=off` stay for interactive callers. The fastest full rollback is revert + converge.
- **Reload.** None (a per-call binary, live at converge).

## W4: load harness, live tier (B1 part 2; slot B)

**Status**: IN PROGRESS — code LANDED `30cadb316` `354bd4c04` `da293caf2`; owed: its own guarantee9 pair (cure-only and pair read NO-VERDICT on load and containment), Tier-L queue row `bbe7b5b1ba63`

- **Goal.** A two-arm live rig, run on demand from a priority-31 context. It measures every member's death → detect → first attempt → retries → engaged under the real band mix, with an honest verdict and a power control.
- **Levers (design §3-§9 plus every review change):**
  - **Arms.**
    - The cure arm runs from `git archive <sha>` in `/tmp/lr-harness/trees/<sha>` (C14) and inherits the caller's band. It refuses with `NO-VERDICT band:caller-clamped` when `band.py $$` < 31.
    - The red arm is `taskpolicy -c utility` (20) or, for a wave's DoD, `--red tree:<parent sha>@31`. F16: 58885750c is not an incident tree; it contains 31f4242e0 and 20368fc85 and has no `band.py`.
  - **Bands read inside the call path.**
    - The stub and the fake placer record `band.base_priority(os.getpid())` on every call.
    - Cure requires 100% of `band.log` lines at 31 (F14).
    - The rig watchdog runs under `taskpolicy -c utility` in the cure arm, mirroring production (F23; hypothesis that production's runs at 20).
  - **Load generator** (`loadgen.py`).
    - One process started at 31, whose threads set their own band (`PRIO_DARWIN_BG` → 4, utility QoS → 20, or 31) and spin in `hashlib`. Top-up only; it never waits for load.
    - Stop path: the sampler (a separate process at 31) SIGKILLs it by verified pid on OFF, deadline or harness death (S6).
  - **P2 (load present).** load1/ncpu ≥ 15 and ≥ 1 runnable base-31 thread per P-core on ≥ 70% of samples. Load bins are tags per attempt, and analysis stratifies attempts, not runs (F7).
  - **C6, the physical G1 control** (F22). Load1 is pushed to ≥ 36/core at constant r31, and the cure arm's per-attempt intervals must not change. It runs when ambient reaches 36/core, or with `--bg-topup` if the harness top-up packet allows it. The gap-4 census is armed whenever ambient load1 reaches 280.
  - **Fidelity.**
    - Stub boot delay is drawn from gap-4's distribution for the run's bin (30-40/core: median 46 s, p90 212 s), plus a slow-boot group at 190-300 s, past the 180 s READY wait (F6).
    - `busy_extra: N` working rig panes (F5).
    - The placer block makes the heavy lead placeable (19 + n−1 free seats on one account), with a 900 s charge TTL, `--unassign` voids, and sleeps keyed to the daemon's `--movers` calls (C1).
    - After W3 lands, the placer's CPU model reflects the map: 0.15 CPU-s with a map, glob cost without one (B4 "worth weighing").
    - kitty-slow faults only the first K calls (or 30%), has a pure-builtin fast path, and parses `window_id:` and `--match=id:N` (F15).
  - **New fault knobs for later waves.**
    - kitty-slow `send_text_fail_n: N` fails the first N `send-text` calls for a member window. The guarantee9 group **`c_rpc_fail_twice`** (N = 2), with that member's H2/H3 scoped `target:W8`, has power because one DETERMINISTIC failure is only RETRY at HEAD and the second identical one escalates (`classify.py` `apply_failure`).
    - The stub's `stop_failure_hook` seam (B1 §9.2 item 8) for W17.
  - **Measurements.**
    - Attempt starts come from `events.jsonl` `ev=spawn` rows plus `ProcRole.lstart`, never actlog birth time (`act.py:302-305,322`; C2/F24).
    - P_obs comes from heartbeat pass boundaries.
    - T2 is judged on max(rig, production `band.log` in the same window) (F16-F17).
    - **Token-expiry count:** admission-token expiry and fresh-gate notes in arm actlogs, per attempt, by load bin. This is the measurement for the TTL hypothesis (W11 lever 12).
    - `analyze` reports t_first against load bin (report only).
  - **Assertions.**
    - **H1** is widened to capacity-ledger load refusals and `hf_recycle_load_gate` text, scoped to staged reconciler paths. The typed-relaunch group (`CC_PANE_SUCCESSOR=off`) is reported separately (C6/F9/F11).
    - **H2**, by outcome: no ESCALATED/IMPOSSIBLE for a member whose expect is ENGAGED (F25).
    - **H4**, without true-busy, kept alive for hold entry + `MAX_AGE_S` + 2 passes (C4/C5).
    - **H6**, for BACKOFF/RETRY: `next_eligible_at − t_exit ≤ 300 s` for soft classes, and the spawn by the 2nd pass boundary after `next_eligible_at`, minus waits named by `admit-refused`/`boot-slots` events (C3/F8).
    - **H7**: a submit token appears ≤ 1× per attempt.
    - **H8**: the HOLD-DRAFT composer still holds its draft; the stub logs any `\x15`, `\x7f` or submit on a draft.
    - **H9**: ≤ 1 live holder per sid; the transcript is live in exactly one account (S8).
    - `kill9_post_transplant`'s H3/H6 are `target:A6` until W2's flip (C9).
    - The group `target-limited` is added (F20).
    - Power needs an outcome assertion (T1, H3 or H6). T2/T3 alone print `PASS (power: pass-length only)` with exit 5 (C8).
    - The verdict line states `lanes: reconciler` (F19).
  - **Safety.**
    - **Production gate:** any open production record with `kind == limited` outside `HARD_HOLD ∪ OTHER_LANE (PARKED-REBOOT)` ⇒ NO-VERDICT, retry later (never wait). The 4 idle PARKED-REBOOT records open since early October do not block.
    - A final read-only check that `~/.reso/limit-recover/recon/sessions` holds no rig sid (S7).
    - The window-opening phase is serialized across arms under the harness lock, and a control window is opened first in every new OS window. Focus theft is counted and handed back (S5).
    - **Reaper:** the driver, sampler and generator are Python or under W0b's whitelist. Any `cc-reaper.log` TERM line naming an arm root during the run ⇒ `NO-VERDICT reaper`.
    - Run length is derived from the matrix (guarantee9 ≈ go + 3,780 s; F13).
    - Preflight refuses when kitty fds + 3×windows > 230, or the coalition projection is ≥ 650.
  - **Optional, report only:** a real-`--place` arm at the run's load on frozen inputs (cache-only, log redirected; B4 efficacy 6).
- **Tests.**
  - `tests/lr-load-harness-lib.bats` fixtures: PASS (exit 0), SIGNAL-DEAD (4), NO-VERDICT band (3), NO-VERDICT load (3), NO-VERDICT reaper (3), pass-length-only (5), XPASS/XFAIL.
  - The production-gate predicate: idle PARKED-REBOOT ⇒ proceed; open limited BACKOFF ⇒ NO-VERDICT.
  - kitty-slow `send_text_fail_n` fires exactly N times.
  - The loadgen stop case runs in the Tier-L preflight (`--bg 200`, gone within 10 s of OFF), not in the land gate.
- **Done.**
  - `bats tests/lr-load-harness-lib.bats` with plan line.
  - A cure-only guarantee9 at ambient, reviewed by hand: every fault fired, bands read back, costs inside budget.
  - Then `bash tests/rig/lr-load-harness.sh run --matrix tests/rig/faults/guarantee9.json --arms cure,red --detach`, followed in ≤ 270 s `wait` slices, with its verdict line in the commit.
  - Acceptance: the cure arm passes H1-H9 with preconditions met. Exit 0 (PASS) or 4 (SIGNAL-DEAD, then rerun with `--red tree:<parent>@31` in the next wave) is a valid baseline. Exit 3 means rerun, never PASS.
  - The lead then starts the owed-run queue.
- **Kill switch.** `bash tests/rig/lr-load-harness.sh stop`; `touch /tmp/lr-harness/OFF`. **Reload.** None.

## W4b: rig completion for the later waves (B1 phase 2; slot B)

**Status**: IN PROGRESS — code LANDED `1e52a4b3d` `d5850fc77` `c8a26b0d6` `0fd7ced3c`; owed: the move9 pair, then `load-expect.json` T5 to hard, Tier-L queue row `bbe7b5b1ba63`

- **Goal.** The rig drives what W5, W11, W13, W14 and W16 must prove: the move lane, the D2a switch file, a deaf kitty, and a shed-shaped batch.
- **Levers.**
  - **Move-lane driver.**
    - A rig poller stand-in (`tests/rig/poller-standin`) runs the real `lr-reset-poller.sh --move-kick` against the arm's state, with `LR_LAUNCHCTL_BIN` and W1's shims (`lr-reset-poller.sh:320,330`; `bin/cc-lr:1731-1745`).
    - A matrix block `move_batch: {rows, slots, at, origin}` queues a real `cc-lr move` batch in the arm.
    - Swap slots live under the arm's `LR_STATE_DIR` (`__main__.py:100-104`).
  - **`idle_fanout_switch: true`** creates the arm's `recon/idle-fanout.on` as well as setting `LR_IDLE_FANOUT`. The rig sets only the env today (`lr-recon-rig.sh:59`), and W13 moves the daemon to the file.
  - **`kitty_ls_fail: {from, for}`** makes kitty-slow fail the daemon's full `kitten @ ls` for a window, for W14 and the C2/B5-R class.
  - **Matrices:**
    - `faults/move9.json`: T5, a member that turns limited while queued in the move lane;
    - `faults/shed-e1.json`: k = 9 limited plus a concurrent 4-row `origin: shed` batch on `--slots 1`;
    - `faults/kitty-deaf.json`;
    - guarantee30 gains the 4-row idle move batch holding slots.
- **Tests.** `tests/rig-move-lane.bats` (fixture-level, land-gate safe):
  - the stand-in claims and starts a batch by hard link, never twice;
  - the switch file is created;
  - `kitty_ls_fail` fires inside its window only;
  - the shims log their argv and do nothing.
- **Done.**
  - Plan line.
  - Tier-L `move9` pair, cure against `tree:<W5 parent>@31`: the member is released at once in cure (`became-limited … the reconciler recovers it`) and driven by the reconciler, while red holds it through the slot wait. **T5 flipped to hard.**
- **Kill switch.** Tests only. **Reload.** None.

## W5: reconciler first, poller as a bounded backstop; the move lane lets go (A7 parts A and B; slot C)

**Status**: IN PROGRESS — code LANDED `fef98e423` `1f1e42206` `a294d2bcb`; Part A flipped to `on` 2026-10-23 (packet `4ffc4e1e5f1c`'s class-B default fired 17:29Z; row `fa97d2db22d1`, supersedes `718ef4662d91`; `shadow` stays as an explicit opt-in); owed: the live-wall reads

- **Goal.** Hands-off recovery is on: the operator touched `recon/autorecover.on` at 17:10:31Z (A7 §0). Two changes follow:
  - the poller stops racing the reconciler for a record it is about to place, for a bounded time only;
  - a move-lane worker releases a session the moment it turns limited.
- **Levers (design §6 plus both reviews):**
  - **Part A predicate**, after `lrp_act_done` (`lr-reset-poller.sh:180`), at call sites `:1660`, `:1748`, `:1798`, `:2465-2468` and `:2814`:
    - **The poller owns the clock.** `$STATE/recon-first/<sid>` is stamped write-once (`set -C`) at the first deferral, plus one stamp when an eta passes. The poller defers only while `now − stamp < g`, never re-reads a newer `wait.eta`, and clears the stamps when the request or parked record retires (efficacy R1).
    - `g` = `LR_POLLER_RECON_FIRST_S` 600; the ingest grace is 180 s; both are clamped ≤ 900 in code.
    - `t0 = min(record t0, request ts)` (correctness F-A2).
    - The ingest grace applies whenever no open record exists and the request is newer than any record (`terminal.at` earlier than the request, or `close.death` ≠ `death_uuid`). 22 of 157 records re-opened a sid, including pane 20's (F-A1).
    - **Scope:** `kind == "limited"` only. PARKED-REBOOT and `close.wake_failed` records are not deferred. WAIT_RESET and HELD:team take the eta window. Call site 1 requires `_rq_by == stop-failure-marker` (F-A5, R4).
    - Per-tick constants are computed once; rows are read as `@tsv`; the mode read uses the brace-form stderr redirect (F-A4).
    - The RECON-FIRST count is deduped by sid and logged beside RECON-OWNED (`:1911-1913`) (F-A6).
    - **Activation without a premature landing.** Part A lands with code default `LR_POLLER_RECON_FIRST=shadow`: it logs `RECON-FIRST would-defer <sid>` and dispatches exactly as today. After the A7 packet is ruled or its deadline fires, the lead lands a one-line default flip to `on` (edge: before W16 starts, or riding W16).
  - **Part A′, bounding the backstop's claim block.** Under `--from-daemon`, `lr-fleet --one` re-reads `recon/sessions/<sid>.json` right before its router call. An open, acting PLANNED record with a target ends PARKED "reconciler placed", which `rq_refund_park` refunds (efficacy R3 option a).
  - **Part B** (`lr-move-worker.sh`):
    - Re-read the limit every 30 s inside the slot, draft and idle waits (`:134-202`, `:256`), caching the resolved transcript path (F-B1).
    - Print "the reconciler recovers it" only when `recon/mode` = act and `lr_recon_live` (F-B2).
    - One `limited_now` read before W5, after `intent_ok` (`:394`) (F-B3).
    - Edit `lr-move-worker.sh` only, never `lr-lib.sh`.
  - **File-backed switches:** `~/.reso/limit-recover/move-limit-recheck.off` (Part B) and `~/.reso/limit-recover/fleet-recon-placed.off` (Part A′), read per worker and per run.
- **Tests.**
  - T-A1..T-A17 in `tests/lr-reset-poller-recon-first.bats`, with hook-shaped requests (`ts`, no `at`, mtime set by `touch -t`; F-A3):
    - T-A1, red measured (`/tmp/a7/bt2.out`: `DISPATCHED: --one 52e35019… reason=not-owned`);
    - T-A6b: terminal record + fresh request ⇒ defer;
    - T-A13: a stay re-offer loop ⇒ total deferral ≤ 2·g;
    - T-A14: wake_failed ⇒ dispatched;
    - T-A15: PARKED-REBOOT ⇒ dispatched;
    - T-A16: g = 5000 is clamped;
    - T-A17: a promoted record gets one fresh window;
    - **T-A18 (new):** in shadow, the would-defer line is logged and the request is dispatched as today.
  - Move-worker tests 30-33 (the suite has 29 today) cover the slot, draft and W2 idle waits and the wording. A switch-file case: `move-limit-recheck.off` ⇒ no re-read.
  - `lr-fleet.bats`: the "reconciler placed" park plus refund, and `fleet-recon-placed.off`.
  - All under `/bin/bash` 3.2.
- **Done.**
  - Plan lines for `lr-reset-poller-recon-first.bats`, `lr-reset-poller-requests.bats` (1..51), `lr-recon-fence-callsites-poller.bats` (1..23), the reroute and bash32 poller suites, `lr-move-worker.bats` (1..33) and `lr-fleet.bats` (1..149 plus the new cases).
  - At the next real wall (L, read-only):
    - `RECON-FIRST would-defer` lines (shadow), or `RECON-FIRST` lines (on), in `poller.log`;
    - no `REQUEST <sid> — dispatching` within g of the stamp for actionable records (on);
    - backstop hand-overs counted, with their claim-hold wall and PARKED rate;
    - **the PRI-31 detect→PLANNED distribution (from W6 telemetry), recorded as g's acceptance number** (A7 efficacy 3).
- **Kill switch.** `touch ~/.reso/limit-recover/recon-first.off` (next tick); the two switch files above. **Activation.** Part B and A′ at converge; Part A in shadow at converge, then live at the L flip. Poller ticks are fresh processes (StartInterval 600), so no reload.

## W6: telemetry (B6; slot A)

**Status**: IN PROGRESS — code LANDED `8f4ab29f9` `748186142`, live since reload R2; owed: the Tier-L cure run, Tier-L queue row `bbe7b5b1ba63`

- **Goal.** Make the following readable without forensics: pass phases, child costs, gate refusals (including the four silent paths), per-record dwell and latency, rail bands, kitty's band, thermal and memory pressure, and the runnable census by base priority. Telemetry is write-only, makes zero forks, and never raises.
- **Levers (design §3-§6 plus correctness items 1-15 and efficacy RC-1..RC-14):**
  - **Robustness.**
    - Helpers live inside `telemetry.py` (no `store._max_bytes_env`, no `_read_json_or_none`).
    - The constructor is guarded.
    - The import catches `Exception`, not only `ImportError`; it sets `telemetry = None` and writes one event.
    - The `run_bounded` hook (`clock.py:349`) computes its label after `step()` and never raises.
    - The fault budget re-arms after 1 h. With `cur` None, the pass methods return without counting (RC-10).
  - **The census runs off the loop thread** (ctypes releases the GIL), with a 2 s monotonic deadline that returns `partial: true`. The throttle uses `time.thread_time()` (RC-8). Thread handles are pinned to `c_uint64`; a plain int reads 0 threads (measured).
  - **Roles.**
    - Matched on argv structure in the first 400 bytes.
    - argv0 in {claude, node, expect, jq, bats, cc-close-attrib} is excluded.
    - An `lr-fire-resume.sh` with a live claude descendant is `session-parent` (RC-6: 38 hits, 9 of them Claude sessions classed `hf`, measured).
  - **The G instrument is de-biased:**
    - Born-terminal records get close rows, and the readout prints detect→first over attempted + censored records, with `n_censored` and `n_closed_unattempted{outcome}` (RC-1).
    - `held_pre` nets hard-hold time out of `first − det`, using a `HARD_HOLD` table and `OTHER_LANE = {PARKED-REBOOT}` (RC-2).
    - Spawn rows carry `gap` since the last exit seen (RC-3). The "stuck" WARN is: not in HARD_HOLD, and either no spawn within B_max + P_obs after the last exit or none since W_soft. Flapping cannot reset it.
    - `act_exit` carries the settle detail, the exit-based wall, `seen_lag`, and counts no-op attempts (RC-4).
    - Record rows carry `p0`, the pass-begin wall, so a transition is bracketed `[p0, t]`. T4 moves the wall clock across a transition inside one pass (RC-12).
  - **Readout follows the watchdog.**
    - The daemon is alive iff the heartbeat `wall` age is ≤ 60 s.
    - An in-progress pass renders "pass N running …", never NO DATA.
    - "Telemetry stopped" shows only when `pass_seq` has advanced ≥ 2 past the newest row.
    - `phase`/`phase_at`/`pass_at` are set directly by `clock.set_phase`, outside the guard (RC-5).
    - Child timeouts alone are not WARN (premise).
    - The verdict reads `reconciler:`, never a bare `rail: ok`. It lists the move lane and boot-resume as not covered, and lists OTHER_LANE records with their owner and age (RC-11).
  - **New counters:**
    - thermal level and memory-pressure level per pass (W11's hard-stop evidence);
    - `HELD:load` after confirm (G2 R8);
    - `deadline-held` reasons;
    - per-record detect→PLANNED (W5's acceptance number for g).
  - **Odds and ends.**
    - Kitty pids come from the `/tmp/kitty-*` glob, with liveness by `proc_pidinfo`, so a ps-degraded pass reads `kitty unknown` (RC-9).
    - Ledger labels split `ps:all`/`ps:pid` and use `argv[1]` for interpreters (RC-13).
    - `note_states` runs before `cohort_status` (`__main__.py:1723` vs `:1728`), item 8.
    - `first` is stamped so that it rides spawn's own save (item 10).
    - `FIRST` is derived from `settle.MOVE_ACTUATORS` + C/C-retry (RC-14).
    - Lint T11's module list is computed as `lr_recon/*.py` minus telemetry/report/`__main__`, with the paging functions included (item 13).
- **Tests.**
  - T1-T15, plus:
    - the unguarded-constructor mutant (red);
    - a module raising `SyntaxError` at import ⇒ the daemon still runs;
    - the census deadline returns `partial`;
    - an own-thread census reads > 0 threads;
    - role fixtures from the measured shapes;
    - the born-terminal close row and the censored counts;
    - `held_pre`;
    - a 14-minute in-progress pass renders WARN-in-progress;
    - the flap-proof stuck WARN (a PLANNED↔WAIT_DATA loop still trips it).
  - `test_daemon_loop_starts_and_runs_a_pass` (`test_main.py:1845-1860`) gets an injected fake, so no unit test censuses the live box.
  - T6 drives methods directly, not 28,800 `run_pass` calls.
  - All under `/usr/bin/python3` 3.9.6.
- **Done.**
  - Unittest OK.
  - `bats tests/lr-recon-telemetry.bats tests/lr-recon-watchdog.bats` (watchdog 1..31 unchanged).
  - Tier G S1 is identical with telemetry on and off.
  - **Owed Tier-L run (queue):** the cure run's rows record role-scan and census CPU per row, each **with its load bin**. Targets: role-scan ≤ 3 ms CPU, census ≤ 20 ms CPU. CPU is load-independent, so no minimum load is required.
- **Kill switch.** `touch ~/.reso/limit-recover/recon/telemetry.off` (read every pass).
- **Reload.** R2. The activation precondition is `ls recon/owned/` empty, not an empty readout line (item 14: the four PARKED-REBOOT records keep it non-empty).

## W7: kitty hygiene tools and the router-cache producers' band (B8 agent parts; slot C; after W2) — DONE (`2aef52ed4` + fixups to `29fa7e597`; operator RK ran 2026-10-21 ~08:07Z)

- **Goal.** Read-only tooling for the operator's App Nap A/B, the fd-headroom kitten, and the planned kitty restart, fixed so it can neither give a false green nor cause the outage it watches for.
  - Plus the same band fix as waves 1 and 5, for the producers of the router cache that D1, G2, `cc-wave-plan` and `recycle_repick` read.
  - Keepwarm and accounts-local read 20T (`ps -M`, G2 review R6), while their staged plists say `ProcessType Standard` (`plutil -p ~/Library/LaunchAgents/com.claude.accounts-keepwarm.plist`). The plist's own comment (`launchd/staged/com.claude.accounts-keepwarm.plist:91-99`) intended priority 31.
- **Levers.**
  - **`scripts/kitty-hygiene.sh status`:**
    - `TZ=UTC LC_ALL=C ps` (the locale bug, S11);
    - the repo's timeout resolver with `-k` (pattern `_hb_to`, `restore-heartbeat.sh:82-90`);
    - any rc ≠ 0 ⇒ UNKNOWN;
    - both fd metrics plus `fds_unix=`;
    - `version=?` WARN when the bundle is newer than the process;
    - `probe=` WARN;
    - the dev kitty's parent pid named;
    - `--pid` left out when the number of main kitties ≠ 1.
  - **`naps` on a positive surface:**
    - a held adapter in `RBSStateCaptureSet` = ENROLLED;
    - NO-ADAPTER needs a dump plus a challenge line;
    - windows sliced to ≤ 20 min, each bounded, with coverage per slice (E-1, E-2, S10, S12);
    - `--start` defaults to the process lstart, and an earlier one is refused;
    - never run inside `cc-restore`.
  - **`sample`:**
    - makes no remote-control calls to the production kitty by default;
    - reads the band via `band.py`;
    - stops RC calls to a kitty after its first rc ≠ 0;
    - allows ≤ 10 unanswered calls per run (S2: each unanswered call costs kitty an fd).
  - **`scripts/lib/kitty-fd-headroom.py`** (new): a `no_ui` kitten with two modes. `set` calls `resource.setrlimit(RLIMIT_NOFILE, (8192, hard))`; `get` reads the limit back. It is for O2b, run by the operator against the throwaway probe first (B8 efficacy 6).
  - **`bin/cc-restore`:**
    - the hook moves to `finish()`, before `:832`;
    - bounded ≤ 30 s and never raises;
    - `self.appnap` is initialised in `__init__` (`:576-586`);
    - `appnap=` sits at the END of the verdict line, so `tests/cc-restore.bats:279` stays green;
    - skipped in `--after-crash` (S5, S6, E-7).
  - **`alarm-reboot-prep.sh`** captures the `status` output, then matches it (pipefail at `:57` hid the hint, measured `HINT-NOT-PRINTED`), and calls a cheap, bounded `status --only key,main,probe` (S4, E-8).
  - **The operator script (in the tool's help and the needs rows):**
    - The probe recipe uses `--listen-on unix:/tmp/b8probe/<arm>.sock`, outside `/tmp/kitty-*` (S1), and ends with `pgrep -f 'instance-group b8-'` empty.
    - The rc 124 readings in O1/O3/O3b/O5 count as UNKNOWN (E-9).
    - The O4 restart adds:
      - no `ship-land.sh` in flight;
      - after an upgrade, `kitten @ ls` and a `get-text` parse against the new kitty, rolling back with `kitty-build-swap.sh rollback` if either fails;
      - on the reboot path, upgrade only after `alarm-reboot-prep.sh` has saved drafts and the heartbeat;
      - the post-start check is challenge-based: ⌘H the **new** kitty for 90 s, then require `band.py` ≥ 31 and no napped adapter (efficacy 2, correctness 6).
  - **Band fix.** Both staged plists get `ProcessType Interactive`. `lr-band-reload.sh` gains `--keepwarm`, with consent `keepwarm-band`, which reloads both and reads the band back.
- **Tests.**
  - T10f from the review's capture (role lines + a held adapter ⇒ ENROLLED, never NO-ADAPTER).
  - A K3 stub that exits 1 with `key=absent` prints the hint (red today).
  - `cc-restore.bats:279` stays green.
  - A static lint that allows only `kill -0`.
  - A band-reload `--keepwarm` dry run.
  - A plist `ProcessType` assertion in `accounts-local-job.bats`.
  - The headroom kitten's `get` mode against a fixture limit, with no live kitty.
- **Done.**
  - Plan lines for the five suites.
  - `bash scripts/kitty-hygiene.sh status` on the live box prints `key=absent`, the main kitty and the fd counts within its bound.
- **Kill switch.** `CC_KITTY_HYGIENE=off`; point `CC_RESTORE_HYGIENE_BIN` at `/usr/bin/true`. Both are operator-shell env, which is where these tools run.
- **Activation.** The scripts at converge. The band fix is operator batch RK.

## W8: right clock per decision, retry instead of escalate, no actuator load term, every hold reason mapped (B7 + C2-lite + G1/G5 closure; slot A; after W1)

**Status**: IN PROGRESS — code LANDED `72fc09748`, live since reload R2; owed: the pair, then the target:W8 flip in `load-expect.json`, Tier-L queue row `bbe7b5b1ba63`

- **Goal.**
  - Evidence waits read the census instant, and actions read the wall clock, so no second prompt can be typed and nothing is stranded silently.
  - Today's typed prompt delivery (C) never ends IMPOSSIBLE because of our own kitty-RPC uncertainty.
  - No actuator inherits the capacity library's load term.
  - Neither HELD:load nor any other actuator hold reason escalates to IMPOSSIBLE.
- **Levers.**
  - **B7, as amended by both reviews:**
    - `t_dec = max(now, wall())` for spawn stamps (`act.py:320,321,337,345`; `__main__.py:1323`) and pacer slots (`admit.py:187-198`, `:302-303`, `:330-332`), re-reading the wall after the probe (efficacy 6).
    - C's grace reads the census instant: `settle.quiet_for(rec, "typer", now) < C_GRACE_S` at `__main__.py:1237` (variant M1). E1 is deleted and replaced by its negation (correctness 1).
    - `evidence.build` (`evidence.py:180-234`): after `_target_reads`, set `ev.submitted` when this attempt's token record is found (correctness 2).
    - The quiet anchors for `rolled_back` (`settle.py:236-259`) and `holder_gone` (`:991-1011`) become first-unseen census stamps, written before any reader. The typer observation is stamped for every open record before any early `continue` (`__main__.py:746-791`; correctness 4).
    - "Busy" counts an `lr-fire-resume` relay only if it started after the move (lstart later than `timeline.planned`/`intent.at`) or its launcher has not settled. The same predicate gates `_invariant`'s `ACTIVE_FAST_S` skip (`__main__.py:1594-1600`), so a relay-held record is re-driven or paged, never silent. Both reviews measured 6 relays alive for 13-15 h. C5 is rebuilt with a launcher started after the move.
    - The IN-FLIGHT anchor never expires while this attempt's watcher or launcher is live. The change is limited to an `_invariant` page; there is no DETERMINISTIC ladder (efficacy 3).
    - The report fallbacks (`report.py:196,224,996`) are anchored on `timeline.detected`. Docstrings at `admit.py:7,13-16` are updated.
  - **C2-lite (C2 efficacy E2):**
    - cc-tui's C/C-retry lines classify TRANSIENT (≤ 300 s), not DETERMINISTIC:
      - `submitted, but no user record … CANNOT TELL` (rc 5);
      - `the send-text RPC failed for window N`;
      - `… not in kitty's window list …`.
    - Today, after `REARM_CAP` re-arms, they end IMPOSSIBLE (`classify.py:118-126`, `:194-197`; `settle.py:120-136`).
    - **Double-prompt guard:** before a C-retry spawns after an rc 5, the target transcript is re-read in process for the previous attempt's token. If it is present, the retry is skipped and the record re-derives. Kitty executes timed-out requests late, ~9 min measured (`handoff-fire.sh:1118-1119`).
    - `close.unprompted_since` is stamped when row 7 first yields UNPROMPTED; `MAX_AGE_S["UNPROMPTED"] = 1800` pages (`types.py:119-134`).
    - A `kitty-degraded` event fires when a pass's degraded list holds `kitty:` while any open record is UNPROMPTED (C2 E5 T4).
  - **G1 closure (lr_recon side):**
    - `act.actuator_env` (`act.py:50-93`) sets `CC_ADMIT_LOAD_TERM=off`. That covers `boot-resume-launch.sh:429` under R's `cmd_replace` (`act.py:247-255`), whose library term is on by default (`capacity-admit.sh:1305`) with a 2.0/core ceiling (B1 F9).
    - The g1-allow row converts from `debt:W8` to `env-off:act.actuator_env`, proven by a test that builds the env for every actuator letter.
    - `map_notmoved("load")` returns `("HOLD", "HOLD-LOAD")` instead of falling to DETERMINISTIC (`classify.py:129-169`). A precheck HELD:load then re-probes and pages at 900 s (wave 3), never IMPOSSIBLE. Its root, the typed-relaunch hold, is W12b and the TR ruling.
    - The uncapped `clock.load_multiplier` (`clock.py:156-164`, no caller) is deleted.
  - **G5 closure: every actuator hold reason gets an explicit row** (B3 correctness R.3: today these fall to DETERMINISTIC, escalate on a repeat, and end IMPOSSIBLE after 4 re-arms).
    - Hard holds become HOLD + page:
      - `mid-turn` → HOLD-COMPOSER (busy) (`handoff-fire.sh:3284`);
      - `bg-work:ship-land` and `bg-work:other` → HOLD-BGWORK (`:3293`, `:3300`);
      - `launch-lock` and `holder` → HOLD (`:13577`, `:13583`; a live foreign holder is a REPORT §5 hard predicate).
    - Our own guard becomes TRANSIENT: `wake-guard` (`lr-handoff.sh:1647-1649`, "a retry is safe").
    - `no-shell` keeps its page-once refusal, with the reason stated in the table.
    - Each mapping is verified against its emitting site before landing (hypothesis until read).
- **Tests (red at HEAD).**
  - Pacer: the 3-per-account cap inside one long pass (C1/C2).
  - `test_b7_review_hazard`: token written after `_derive`, dispatch at census+61 ⇒ no C.
  - Finding 2: token visible at census+70 ⇒ no C.
  - Relay strand at 120 s and 10 s pass gaps ⇒ rolled back within 60 s + 2 passes, never zero events.
  - Watcher live for 1,195 s ⇒ no DETERMINISTIC.
  - A C rc-5 line ⇒ TRANSIENT.
  - rc 5 with the token landing at census+70 ⇒ no second C.
  - rc 5 with the token landing during the backoff ⇒ the C-retry is skipped by the guard.
  - `actuator_env` contains `CC_ADMIT_LOAD_TERM=off` for every actuator letter. `map_notmoved("load")` ⇒ HOLD-LOAD.
  - **Enumeration test:** every `HELD:<reason>` literal in `handoff-fire.sh` and `lr-handoff.sh` (grep at test time) maps to a non-DETERMINISTIC class or an allowlisted, reasoned exception. An unmapped literal is red. `mid-turn`, `bg-work:ship-land` and `wake-guard` are red today.
  - The UNPROMPTED page at 1800 s.
  - E2 and E3 (designed, never run) are run.
- **Done.**
  - Unittest OK with count; `bats tests/lr-recon-now-audit.bats`.
  - Tier G S1-S4 still green.
  - The G1 lint shows the `load_multiplier` row RESOLVED and the boot-resume row as `env-off`.
  - **Owed Tier-L run (queue):** a pair with `--red tree:<W8 parent>@31`. The cure arm passes H1-H9, and the `c_rpc_fail_twice` member is ENGAGED in cure while ESCALATED in red (power on H2/H3). Then flip that member's `target:W8`.
- **Kill switch.**
  - `printf 'pass\n' > ~/.reso/limit-recover/recon/pass-clock` reverts `t_dec` and the pacer. It does not restore the old busy-stamp position; this is stated.
  - `touch recon/c-rc5-transient.off`.
  - `touch recon/actuator-load-term.on` restores the library term for actuators.
  - `touch recon/hold-map.off` restores today's DETERMINISTIC fall-through.
- **Reload.** R2.

## W9: a bounded pass, synchronous (B2 stage 1; slot A)

**Status**: IN PROGRESS — code LANDED `784682330` `9700c6213`, live since reload R3; owed: the T2 run, then the T2 row to hard, Tier-L queue row `bbe7b5b1ba63`

- **Goal.**
  - Every child the loop waits on is wall-bounded, including its kill-wait.
  - Reaping never steals another owner's exit.
  - The per-record serial terms are bounded or capped per pass: lstart reads, composer reads, pages, mails, draft snapshots and our own boot slot.
  - **P_cap becomes a published, n-independent sum of enforced bounds.**
- **Measured motive (B2):**
  - A 0.2 s timeout costs 6.29 s, because `subprocess.run` waits unbounded after a kill (`/tmp/b2meas/killwait.py`).
  - The four largest PRI-31 pass gaps (98-193 s) coincide with ps abstains against a 90 s budget.
  - `waitpid(-1)` read another owner's rc 9 as 0 (`/tmp/b2meas/steal.py`, reproduced by the reviewer).
- **Levers.**
  - **`clock._run_reaped`** behind `run_bounded` (`clock.py:349-372`):
    - kill, then wait ≤ `REAP_GRACE_S` (2 s);
    - an orphan registry, paged once at ≥ 16 live orphans;
    - the Popen constructor time recorded as `spawn_s`;
    - the in-pass retry is skipped while ≥ N orphans of the same argv0 live; ps is never blocked outright (efficacy 6).
  - **Registered-only reaping.** Delete the `waitpid(-1)` loop in `act.reap_children` (`act.py:394-415`, on W2's nonce-keyed table). Add an `_INFLIGHT` set. An unowned-zombie event is raised only after 2 passes. `_note_child` never raises (correctness C10).
  - **`wait_for_change`** wakes, edge-triggered, on an actuator exit.
  - **In-process lstart.**
    - `store.proc_lstart` (`store.py:530-546`) reads via `proc_pidinfo(PROC_PIDTBSDINFO)` in ps's TZ=UTC format, with ps as the fallback. It matched 40 of 41 pids in 0.6 ms total (efficacy measurement).
    - A timeout returns `unknown`, distinct from dead.
    - `_alive` (`__main__.py:129-130`) returns True on unknown, which closes the claim-steal split-brain on a ps timeout (correctness C8).
    - Callers `act.py:335`, `admit.py:387/415` and `__main__.py:1061` use the cached self lstart.
  - **Boot slots.**
    - Our own slot needs no ps, and an empty self lstart keeps it live (correctness C6).
    - `BootSlots._disk_take` (`admit.py:390-415`) steals a dead slot by `os.rename(d, d + ".dead.<pid>")` then `mkdir`, as `lr-move-lib.sh:254-255` does. G2 C6 measured 12 processes against 6 dead slots believing they held 7-11.
  - **Composer reads.**
    - A per-pass, per-socket breaker in `_read_composer` (`__main__.py:693-713`): after one timed-out read, the rest on that socket return unknown with no child. That is the same bucket as a timed-out read (`census.py:236-241`).
    - **A per-pass composer budget of 20 s**, with oldest-read-first rotation. Past the budget, reads return unknown with no child. That polarity is safe: never assumed empty.
  - **Pages and mails.**
    - A durable outbox `recon/outbox/`: written before send, unlinked after the sink, re-enqueued at startup.
    - A SIGTERM handler raises `SystemExit`, so `daemon()`'s finally runs. There is none today (correctness C5). The finally flushes the outbox and releases the flock only; it never saves records mid-pass (A6 §2.7).
    - Immediate kinds go first.
    - **At most one synchronous send per pass, pages and requester mails combined** (≤ 55 s: cc-notify 10 s + lr-page 45 s, `report.py:552-602`). Mails stay latched-on-result for a later pass (`report.py:895-908`).
    - `pages_queued` goes in the heartbeat.
  - **Draft snapshots:** at most one per pass; the rest go to later passes (B2 S2.d c).
  - **Mints:** counted per pass (≤ D by the pace and deadline lanes), with each bound stated.
  - **`--assign-many` memo:** only on a changed row set, or every 120 s.
  - **Per-pass exception guard** in the daemon loop (`__main__.py:1827-1849`): a `pass-exception` event, a page latched hourly, and exit 1 after 3 consecutive raising passes. KeepAlive restarts it, and W2 makes the restart safe. This answers B3 review F-B.
  - Phase marks go through W6's `tel.phase()`. There is no separate `passes.jsonl`.
  - **P_cap, published in the commit and in the guarantee section** (estimated, sum of bounds):

    | Term | Bound |
    |---|---|
    | ps | 92 |
    | kitty | 7 |
    | composer | 20 + 7 |
    | place | 2 × 122 |
    | assign | 32 |
    | probe (W11) | 32 |
    | mints | 6 × 32 |
    | claim argv ps | 6 × 7 |
    | one page or mail | 55 |
    | one draft snapshot | 44 |
    | unassign | 32 |
    | **P_cap** | **≈ 800 s** |

    It is independent of n. The observed target stays 180 s (T2).
- **Tests (red at HEAD).**
  - T1: a stuck child costs bound + grace (today 6.29 s). T2 control. T3 orphan mutant.
  - T4: an owner keeps rc 9 after `reap_children` (today 0).
  - T6: registry membership asserted with no intervening Popen.
  - T7: exit wake ≤ 1.5 s.
  - T9: heartbeat keys against the watchdog's sed (mutant).
  - T20: the assign-many memo.
  - T21: own slot, 0 ps calls (today 5).
  - `_alive` on a ps timeout ⇒ True (today the claim is stolen).
  - A two-arm multi-process slot race (Python only; Python against `lr_swap_slot_acquire`) ⇒ ≤ 6 holders.
  - A second read on a timed-out socket spawns no child.
  - The composer budget: 30 reads at 4.9 s each ⇒ ≤ 27 s spent, with rotation.
  - The outbox survives SIGTERM mid-queue, and the finally writes no record.
  - One synchronous send per pass with 5 pages and 5 mails queued.
  - The pass-exception guard.
  - T22: the incident-shape fake-wall replay, extended to n = 20 with composer reads at and just under their bound, one foreign claim per record, 5 mails and 2 HOLD-DRAFT records ⇒ P ≤ P_cap.
  - `test_step_per_child.py`'s `subprocess.run` patches are retargeted to `clock._run_reaped` in the same diff.
- **Done.**
  - Unittest OK.
  - `bats tests/lr-recon-watchdog.bats` (1..32).
  - **Owed Tier-L run (queue):** T2 (P_obs ≤ 180 s, on the max of rig and production `band.log` in the window) XPASS ⇒ flipped to hard by the slot-A wave in flight.
- **Kill switch.** `touch recon/bounded-pass.off` (restores `subprocess.run` and the old reaper), `recon/inproc-lstart.off`, `recon/page-outbox.off`, `recon/pass-caps.off` (lifts the composer, send and snapshot caps). **Reload.** R3.

## W10: the holds map from the kept transcript index (B4 R1; slot A)

**Status**: IN PROGRESS — code LANDED `52fc6f2b8`, live since reload R3; owed: the pair and the production `holds=` read-back, Tier-L queue row `bbe7b5b1ba63`

- **Goal.** The reconciler hands `--place` the "store already holds this sid" answer it already has. That removes about 64% of `--place` CPU (B4 §1.2).
- **Levers.**
  - `with_holds` runs on the loop thread, right after `plan.movers` in `_plan` (`__main__.py:997-1056`), from the kept `transcript.ProjectsIndex` (`transcript.py:84`, `recheck` at `:262-280`).
  - It is exact on every pass while movers exist: at most one per-pass `st.full` walk per store, removing the different-slug lag. Adopted from the efficacy review's "worth weighing". Cost ≈ 0.5 s at load1 268 (`idxcost2.out`, measured by the designer).
  - Account → cfg is resolved the way `plan.kmax` does it (`CLAUDE_ACCOUNTS_JSON` first, `plan.py:172-186`) and shipped as `{acct: [cfg, bool]}` (W3's trust rule).
  - `holds=k/n holds_s=` tokens go in the place event (`__main__.py:1014-1036`).
  - `recon/place-holds.off` is read every pass (efficacy 9).
  - Called off its thread, `with_holds` returns movers with `holds` None and raises nothing.
  - The intra-pass window is stated: the answer is as of each store's refresh in the pass (correctness F1).
- **Tests.**
  - R1-R7.
  - R4b: a copy created after the pass's refresh reads False, then True on the next pass, with no observe call.
  - R5: 40 new names ⇒ one walk per store.
  - R7 mutant: `with_holds` called from a worker ⇒ `holds` None ⇒ red.
  - Integration through `run_pass` with the real `ProjectsIndex` and a spied `plan.place`: every mover's holds equals the old glob, and the event reads `holds=n/n`.
  - An unreadable `accounts.json` ⇒ no holds key.
- **Done.**
  - Unittest OK.
  - After R3, production `place` events are reported by load1 band (150-249, 250-349, ≥ 350) with n, and "unverified at ≥ X" for any band with fewer than 5 events (efficacy 6).
  - The count of `multiple copies of` in `recon/actlogs/` stays 0.
- **Kill switch.** `touch ~/.reso/limit-recover/recon/place-holds.off`. **Reload.** R3.

## W11: per-record deadline, rescoped (B3; slot A)

**Status**: IN PROGRESS — code LANDED `b54efff86` `c8c922dc8` `ed6f47072`; live after operator reload R4 (step `3853d91f9626`); owed: the guarantee9 and guarantee30 pairs, then T1 to hard, Tier-L queue row `bbe7b5b1ba63`

- **Goal.** A persisted per-record deadline after which soft gates no longer hold a record. Around it:
  - a lane width that is real and bounded in time;
  - a probe that runs once per pass;
  - priority over the idle move lane and idle fan-out for boot slots, honoured for as long as the reconciler is alive;
  - pages that fire once.
  
  This makes T1 (t_first within bound) a hard assertion.
- **Levers.**
  1. **Deadline.**
     - `deadline_at` = `timeline.detected` + 600 s, persisted on the record.
     - The reset-wake lane uses due + 300 s.
     - It shifts across a system sleep (`clock.shift_record`).
     - A record re-offered from WAIT_RESET or HELD:team (`plan.movers` `:214-266`, `REOFFER_AFTER_S` `:205`) gets `max(deadline_at, wake_due + W_wake)` (efficacy 8).
     - Idle moves get none.
  2. **Overdue bypass inside `Admission.decide`** (`admit.py:264-333`). It skips:
     - restore-r;
     - the token-bucket pace (still charged);
     - the per-account pacer (still charged);
     - the probe;
     - the drip interval, including the probe's `active` term (rc 9 "capacity" covers memory, segment and active count, `admit.py:216-238`).

     Every hard gate is untouched (design §3 census). `actuator_env` is unchanged.
  3. **Lane width.**
     - D = 6 counts deadline-admitted first turns that are submitted, not yet ENGAGED, **and admitted ≤ T_att ago** (correctness F-A, "admitted ≤ a stated bound ago"). C, C-retry and wake actuators exit in about 24 s (measured by the reviewer: C 24.2-24.5 s, against A's p50 of 754 s).
     - Only non-adopted actuator-role procs count.
     - A per-account deadline cap of 3 applies (correctness F-A, efficacy 7).
     - The bound uses `D_eff = min(D, free boot slots)`.
  4. **Slot priority, subject-relative.**
     - While an overdue A/R record waits on boot slots, the reconciler writes `lr_root/locks/slot-priority` holding an `until` epoch = write time + max(180 s, 2 × the last pass's duration). It refreshes the file each pass and from `clock.step` during long phases.
     - `lr-move-lib.sh`'s acquire (`:236-260`) caps the move lane at 1 slot while `until` > now, so the cap does not lapse in a long pass ("Freshness is subject-relative", situational :76).
     - W13's idle fan-out reads the same signal and takes 0 slots.
     - Without this, the move lane can hold 4 of the 6 shared slots (`LR_MOVE_SLOTS`, `lr-move-worker.sh:57`) and D_eff falls to 2 (efficacy 1; 7 `boot-slots` refusals on 10-18, measured by the D2 review).
  5. **Probe at most once per pass.**
     - A refusing reading counts once per pass toward `DRIP_AFTER` (`admit.py:56`) and is reused for later candidates in that pass.
     - An admitting reading admits one member.
     - Overdue records skip the probe.
     - Semantics change, stated: the drip opens after 3 refusing passes, not 3 members (B2 review C3, B3 efficacy 4).
  6. **Mint failure.** If `mint_token` (`admit.py:243-255`) returns None on `admit:deadline`, no A/R spawns: a `deadline-mint-failed` event is written, the charges are kept, and the record retries next pass. Otherwise lr-handoff re-probes and can park (`lr-handoff.sh:1590-1599`; efficacy 3).
  7. **Hard stop, in-process, never forks.**
     - It trips on sentinel `strk > 0` or `pct ≥ 60`, memory pressure level 4, or thermal critical (3). Thermal already reads 2 at 15/core (measured by the reviewer), so 2 would be a hidden load gate.
     - Each source releases after two clear reads ≥ 30 s apart.
     - A stale or absent sentinel row is "unknown": it never trips. A **tripped source whose reads turn unknown stays tripped for at most 300 s, then releases with a `hardstop-unknown-release` event** (correctness F-I, efficacy 6a).
     - The thermal notify token is registered once, with `argtypes`/`restype` set, and cancelled at exit (F-B).
     - A trip lasting over W_hard (900 s) while overdue records wait pages `deadline bypass off: <source>`.
     - Thermal and pressure are logged every pass through W6.
     - **While tripped, the bound is today's drip plus slots**; this is stated in the guarantee section (efficacy 6d).
  8. **Pages through W9's outbox.**
     - DEADLINE is coalesced per cohort at deadline + 900 s, then hourly.
     - It is suppressed when an `age:<record_id>` latch or `close.hold_since` exists.
     - It excludes PARKED-REBOOT, `wake_failed`, `plan_only` and `cohort_exit` stays (F-D, F-E).
     - Wire the computed-but-unsent `Admission.page_due` (`admit.py:124,163,324`), `BACKOFF_PAGE` (`classify.py:191`) and `Reporter.slo_page` (`report.py:1010`).
     - One DRIP page per cohort.
  9. **Attempt over budget.** An actuator alive past T_att (900 s) pages once and is not killed. Its first turn leaves the D count (lever 3); its boot slot stays held while it is alive.
  10. **Unknown-exit resolution (owner handed over by W2).**
      - A PRE-MOVE/None record whose move exit had no code, and whose actlog does not end NOTMOVED, re-derives instead of paging every pass (`settle.py:205-209`).
      - After the `HOLDER_GONE_QUIET_S` window, with no live actuator, `confirmed` and `exit_typed_by_me` unset and the phase still PRE-MOVE, it is re-offered as a counted TRANSIENT retry plus one page. The safety of this is a hypothesis, guarded by the same predicates as `rolled_back` (`settle.py:236-259`).
  11. **Never raise.**
      - Env resolves to `os.environ`. Wrappers return unknown, not "overdue" or "not tripped".
      - Tests cover torn, blank and string sentinel fields (F-B).
      - `next_action(rec, now=None)` (`report.py:153`) adds no prefix when `now` is None (F-C: 5 of 57 `test_report` tests broke otherwise, measured).
      - `deadline.off` and `deadline.shadow` gate decide, the earliest-deadline-first sort and the slot-priority writer (F-H).
      - A `deadline-admit` event rides spawn rows (F-K).
      - `deadline_why` is reset on each decide; `Admission.hard` gets a default; `drip_pages` is cleared in `leave_active` (F-L).
  12. **Token TTL (conditional on W4's measurement; hypothesis).**
      - The admission token's TTL is 1020 s, a sum of unscaled literals (`capacity-admit.sh:1043-1052`), while the watcher scales its stages up to ×4 (`hf_load_scaled`, `handoff-fire.sh:4957`; G2 R1: 2760-3120 s at ≥ 30/core).
      - The reconciler's mint passes no `CC_ADMIT_TOKEN_RUN` (`admit.py:243-255`), so a token can expire before the relaunch redeems it. The relaunch then re-evaluates with the active term on (`lr-fire-resume.sh:905` turns off load only).
      - If W4's token-expiry count is > 0 at ≥ 15/core, this wave adds `scripts/lib/capacity-admit.sh` and scales `_cc_admit_token_ttl`'s stage sum by the same min(4, 1 + load/core ÷ 10) cap, as a `capped-bound-stretch` row.
  
  **Dropped from B3:** kept-target retries (see Dropped).
- **Tests (red at HEAD where marked).**
  - D1: 30 PLANNED limited records on one account, detected now − 1200 ⇒ spawns ≤ the per-account cap and lane (today 3 spawn and 27 refuse `pacer:next`, measured).
  - D2 CONTROL, with the mutant "overdue always true".
  - D3: probe standing at rc 9 with 10 overdue C records ⇒ admitted, with the probe not called.
  - D5: a 24-member fake-wall cohort ⇒ first admission ≤ deadline + one pass (today +690 s).
  - D6: 30 overdue C records on one account over 5 passes ⇒ ≤ cap.
  - D7 (new): a first turn that never ENGAGES leaves the D count after T_att.
  - A multi-pass `_dispatch` with live actuators holding slots, and 0 or 4 move-lane slots held ⇒ every `t_first ≤ deadline + P + ceil(k_r/D_eff)·T_att`. Today: 12,630 s against a 5,110 s promise at T_att 900, with rc 9 and 4 slots held (simulated by the reviewer).
  - `lr-move-slot-priority.bats`:
    - the move lane takes ≤ 1 slot while `until` is in the future (today 4);
    - a file whose `until` passed is ignored;
    - a 300 s pass with the file refreshed from `clock.step` keeps the cap.
  - H1-H8 hard-gate controls; H9-H11b hard stop, including tripped-then-unknown released at 300 s; mint-failed ⇒ no spawn; one probe call for two candidates; W1/W2 wakes; C1/C2 sleep shift and round trip; P1-P3 pages (P2 with a cycling hold); S1/S2 off and shadow, including the sort; unknown-exit resolution.
  - The retry bound counts the workers-cap (`act.py:477-478`) as a named wait.
  - The red proof is taken on `git archive <parent of the first commit>` into `/tmp/b3-pre` (F-J).
- **Done.**
  - Unittest OK.
  - `bats tests/lr-recon-deadline.bats tests/lr-move-slot-priority.bats`.
  - **Owed Tier-L runs (queue; guarantee30 needs W4b):** guarantee9 and guarantee30 pairs, the latter with W4b's 4-row idle move batch holding slots, using `--red tree:<W11 parent>@31`. T1 PASS in cure and FAIL in red ⇒ T1 flipped to hard.
- **Kill switch.** `touch ~/.reso/limit-recover/recon/deadline.off` (or `recon/deadline.shadow` to log would-admit only); `touch ~/.reso/limit-recover/locks/slot-yield.off`. **Reload.** R4.

## W12: pane identity from the kernel, one-window probe (B5a; slot C)

**Status**: IN PROGRESS — code LANDED `c85b7063b`, in shadow; owed: the identity flip, parked as `a76128229b2a` until 30 agreeing `recycle-kid-shadow` rows exist

- **Goal.** A slow or outaged kitty no longer stops pane identity, or the watcher's probe, from being proven. There is no new draft risk, and no proceed into a kitty that is background-banded. It ships in shadow.
  - Its value is insurance against kitty-side outages: 0 `recycle-held-unreachable` since the PRI-31 reload, and 48/48 stages claimed (measured by the reviewer).
- **Levers (design §5.1-5.4 plus every review change; the cached-draft proof K1 is excluded):**
  - **Mode file.** `~/.reso/limit-recover/kitty-offpath.mode` (`off|shadow|on`), code default `shadow`. The switch is monotone: `off` from any source wins. It is defined above its first user (R-3, S3, S14).
  - **Identity as a re-exec verb**, `handoff-fire.sh __kid`, under `hf_bounded_s 20` (`handoff-fire.sh:1145`). It prints validated `KEY=VALUE` lines that the parent imports (R-2, S2).
    - At most 3 forks: one `ps -E -ww -o command=`; one `ps -axo pid=,ppid=,stat=,tty=,comm=`, walked in awk; one `TZ=UTC LC_ALL=C ps -o pid=,lstart= -p pid,root,kpid`. Every ps goes through `HF_KID_PS_BIN`.
    - It requires the socket to exist, binds `CC_TERM_KITTY_TO` to the verified kitty's socket, and exports `CC_TERM_KITTY_PID` for `prove_target` (`bin/it2-kitty:590-600`).
    - It returns rc 2 when `CC_TERM` is preset to anything but kitty, or when `CC_REMOTE_PANE_TERM=off` (S1, S8).
    - It normalizes the tty and parses the env block only.
  - **Shadow is side-effect-free:** no export, and the resolver still runs. `recycle-kid-shadow` rows carry the kitty-resolved tty beside the kernel one.
  - **New seam `LR_PID_ENV_DIR`.** `lr_pid_cfg` (`lr-lib.sh:1079-1094`) and its 21 fixture suites stay byte-identical (R-11, S4).
  - **`--only P` transport for `pane_proof`** (`:11616`, `:4422`; 0.047-0.084 s against 0.44-0.68 s, axis 07 L5). It is off whenever the mode is off.
  - **The precheck probe schedule stays** at 5 tries over 120 s (`:1566-1597`) for `LR_INPLACE_AWAIT=0` (R-1, S7).
  - **Advisory watcher deferral**, narrowed to `RCY_PP=3` with listing rc 124/137.
    - The hold is placed after the `hf_recycle_subject_gone` yield (`:19456`) and preceded by `_hf_resume_debt abandon` (S5, S6).
    - `HF_PANE_PROOF_ADVISORY` is exported as 0 when the conditions fail, and `export -n`'d in the watcher (S17).
    - A revoke-and-type happens only after a bounded kitty probe answers (R-10).
    - **Kitty band gate (R-5):** before any advisory proceed past an unanswered kitty, read kitty's main-thread band with `ps -M -p $HF_KID_KPID`, ≥ 3 samples, bounded. If it is ≤ 4 (background band), hold TRANSIENT with the reason "kitty background-banded: its main thread would not drain the successor's output (B8)".
    - Mode shadow.
  - **G1 closure (bash):** `hf_lr_admit` passes `CC_ADMIT_LOAD_TERM="${LR_LOAD_TERM:-off}"` (`:17961-17962`).
  - Every new text is linted against `classify._CLASSES` (`classify.py:44-80`; S16b).
- **Tests.**
  - A stub ps sleeping past the bound ⇒ rc 2.
  - Shadow control: the resolver ran, and stderr equals base.
  - A wrong-kitty preset ⇒ overridden or rc 2.
  - T9 rewritten to 5 stub probe calls.
  - S5 ordering plus the debt abandon.
  - rc 2 and usage rc keep today's hold.
  - Mode-off byte equality.
  - The band gate: a stub `ps -M` reading 4 ⇒ hold TRANSIENT; reading 47 ⇒ proceed; a mutant without the gate goes red.
  - `hf_lr_admit`'s env has the load term off (red today).
  - Suites that do not opt in pin `HF_KITTY_OFFPATH=off`.
  - All under `/bin/bash` 3.2 (S16).
- **Done.**
  - Plan lines for the five suites.
  - On the live box, read-only: ≥ 30 `recycle-kid-shadow` rows with 0 tty disagreements (the design measured 30/30 offline).
  - Then a one-line default flip to `on` for identity and `--only`. It lands as an L commit before W12b starts, or rides W12b's branch, and never while W12b or W15 is in flight. At the flip, run every suite that reaches `hf_remote_pane_term`, `pane_proof` or `__recycle` under `/bin/bash` 3.2 (S16). K1 is untouched.
- **Kill switch.** `printf off > ~/.reso/limit-recover/kitty-offpath.mode` (read every call). **Activation.** Converge.
- **Flip request to the lead:** the `hf_lr_admit` debt row (RESOLVED, remove).

## W12b: the typed-relaunch hold (TR; slot C; part 2 after the TR ruling)

**Status**: IN PROGRESS — part 1 LANDED `ac25e898e`; owed: the typed-relaunch rig group (Tier-L queue row `bbe7b5b1ba63`), then the `debt:typed-relaunch` row; part 2 waits on packet `db44ab0ebc55`

- **Goal.** Remove the last gate on the recovery path that waits for load to fall.
  - Today a move that cannot stage its successor holds `HELD:load` whenever load is above 24/core at the commit and 20/core at the precheck (`handoff-fire.sh:4150-4194`, decision 600709c5fe4b).
  - Under 15-40/core that hold never releases, and W8 makes it a paged HOLD-LOAD.
- **Levers.**
  1. **Stage retry (no ruling needed; G2 R8's follow-up).** When `hf_succ_stage` (`:4787`) refuses, including "watcher has no readable start time" (a ps read, `:4805-4806`), re-read the watcher's lstart and retry staging once, bounded, before the commit-time hold. A staged move is exempt from the hold today (`:4189`).
  2. **Re-key per the ruling.**
     - A mode file `~/.reso/limit-recover/typed-relaunch-hold.mode` (`load|terminal`), with code default `load` = today's 24/20.
     - Under `terminal`, the per-core comparison is replaced by two checks:
       - a bounded `kitten @ ls --match id:<P>` against the verified socket answering within 2 s;
       - kitty's main-thread band ≥ 31 over 3 samples.
     - Otherwise it holds TRANSIENT with "terminal not responsive". The harm this gate exists for is a typed relaunch over a backlogged kitty (F1, pane 44, 42-45/core; REPORT §3.3: "key it on the resource itself, not on load").
  3. A `HELD:load`-after-confirm count in the hold's log row, for W6.
- **Tests.**
  - `tests/handoff-typed-relaunch-hold.bats`, via the existing seam `HF_LOAD_PER_CORE` (`:4605-4606`):
    - a stub stage that refuses once at 25/core ⇒ today `HELD:load` (red); after the change, retried and staged;
    - mode `terminal` with a responsive stub kitty at 40/core ⇒ proceed;
    - a stub kitty that does not answer ⇒ TRANSIENT hold, never `HELD:load`;
    - mode `load` ⇒ today's bytes (equivalence; the mutant "ignore the mode file" goes red).
  - `/bin/bash` 3.2.
- **Done.**
  - Plan lines.
  - Owed Tier-L run (queue): W4's typed-relaunch group shows 0 HOLD-LOAD under `terminal`. The flip request resolves `debt:typed-relaunch` in `g1-allow.tsv`.
- **Kill switch.** `printf load > ~/.reso/limit-recover/typed-relaunch-hold.mode`; `touch ~/.reso/limit-recover/stage-retry.off`. **Activation.** Converge. Part 2's default flip follows the ruling (L commit, under the handoff-fire edge rules).

## W13: plan-only honesty and hand-over, and the at-the-wall idle fan-out switch (A7 parts C and D + D2a; slot A)

**Status**: IN PROGRESS — code LANDED `ef94cd89c` `0022f026d`; live after operator reload R4 (step `3853d91f9626`); owed: the guarantee30 idle-fanout pair, Tier-L queue row `bbe7b5b1ba63`

- **Levers.**
  - **Part C.** `next_action` (`report.py:153-176`) names plan-only records honestly.
    - The branch sits after the `_NEXT` lookup and the HELD:team branch, applies only to `kind == "limited"`, and reads "opened while hands-off recovery was off … the poller lane or `cc-lr recover <sid8>`". Placed earlier, it would mislabel the 4 live PARKED-REBOOT records (F-C1).
    - When Part D ships, an own-move-in-flight record reads "finishing its own move, then stops" (F-C1).
  - **Part D.** The plan-only gate (`act.py:453-456`) lets an own move in flight finish, using an explicit (phase, actuator) allowlist:
    - TRANSPLANTED/A or R; EXITED/B; HUSK-RETIRED/A-husk or UNCONFIRM; RELAUNCHED/C; TARGET-TRANSIENT/C-retry; PANE-GONE/R; PRE-MOVE IN-FLIGHT/R.
    - It requires `close.move_attempt == rec.attempt` (F-D2).
    - **Hand-over:** an open plan-only record that is not in flight and holds `owned/<sid>` releases the fence and the claim, with a `release plan-only` event. `_release_terminal` (`__main__.py:1545-1558`) frees only terminal records (F-D1).
  - **D2a.**
    - `recon/idle-fanout.on`, read every pass (absent = off), replaces the env-only `LR_IDLE_FANOUT` for the daemon (`census.py:281`). The fan-out env is computed once per pass (`__main__.py:326`, `:710`).
    - **Idle records take 0 boot slots while any overdue limited record waits** (W11's slot-priority signal), and at most 1 slot while any limited record is open (D16, E9; in `_admit`, `__main__.py:1132-1140`). D_eff therefore stays ≥ 5 with D2a on.
    - Per-session composer verdict TTL ≥ 60 s, and at most 4 idle composer reads per pass, inside W9's composer budget.
- **Tests.**
  - T-C1 (red, measured).
  - F-C1 control: the PARKED-REBOOT idle text is unchanged.
  - The T-D1 matrix, with TARGET-LIMITED/A and TARGET-AUTH as refused controls.
  - The T-D2 matrix over TRANSPLANTED, RELAUNCHED/UNPROMPTED, PRE-MOVE IN-FLIGHT and PLANNED; D ships if any case is red (F-D3).
  - T-D3 hand-over: owned and claim gone, and the bash fence reads `not-owned`.
  - D2a:
    - switch absent ⇒ no idle record; present ⇒ IDLE-ELIGIBLE fan-out;
    - a limited relaunch never waits on an idle boot;
    - an overdue limited record waiting ⇒ 0 idle slots;
    - the composer TTL;
    - driven through the `hold_claim` path (D16).
- **Done.**
  - Unittest OK; `tests/lr-recon-fence*.bats` green.
  - **Owed Tier-L run (queue; needs W4b's `idle_fanout_switch`):** in guarantee30, the idle groups are MOVED via fan-out with the switch present, and the limited members' T1 is unchanged against the no-idle control.
- **Kill switch.** `rm ~/.reso/limit-recover/recon/idle-fanout.on`; `touch recon/plan-only-finish.off`.
- **Reload.** R4. With Part D, removing `recon/autorecover.on` means "no new moves". The hard stop stays `recon.on` or `recon/mode` (`act.py:453-455`), and the operator text says so.

## W14: kitty-free pane binding in the census (B5-R; slot A)

**Status**: IN PROGRESS — code LANDED `4b4edf0de`, plus `6adbd797f` (the now-audit mutant re-anchor PLAN-STATUS cites as `cfdb341d2`, a pre-rebase sha) and the pid-reuse fix W14f `b8ce080ca`; live after operator reload R5 (step `7f151e71f291`); owed: the kitty-deaf pair, Tier-L queue row `bbe7b5b1ba63`

- **Goal.** A record born during a kitty remote-control outage still gets a pane and reaches its kitty-dependent step, where it holds TRANSIENT and pages. Today it sits PRE-MOVE/None with nothing dispatched (C2 efficacy E1, measured with `phase.derive_phase` and `act.choose`).
- **Levers.**
  - When a kitty's `kitten @ ls` fails (`observe.py:238`, bound 5 s; `:496-506` drops roots today), bind each claude holder to (kitty_pid, window_id) from `ps -E` `KITTY_WINDOW_ID`/`KITTY_PID` (last token), plus ancestry to that kitty, using W12's rules, marked `pane_src = "env"`.
  - `observe_rows.bind` (`:314-348`) accepts it.
  - Mode file `recon/pane-bind-env.mode`, default shadow: compute and log `pane-bind-env` rows, do not bind.
  - The W8 `kitty-degraded` event carries counts.
  - A step reached through an env-bound pane obeys W12's band gate.
- **Tests.**
  - Red: a degraded-kitty snapshot with a live target holder ⇒ PRE-MOVE/None, action None today; with mode on ⇒ RELAUNCHED/UNPROMPTED, action C.
  - Controls: a healthy `ls` ⇒ identical binding; a `KITTY_PID` mismatch ⇒ not bound; zombie roots excluded.
- **Done.**
  - Unittest OK.
  - On the live box, ≥ 30 shadow rows with 0 disagreements against `ls`.
  - **Owed Tier-L run (queue; needs W4b's `kitty-deaf.json`):** records are bound in mode on, and none in shadow.
- **Kill switch.** `printf off > ~/.reso/limit-recover/recon/pane-bind-env.mode`. **Reload.** R5.

## W15: a recycle re-pick leaves a pace-held account (D1; slot B; may build before the ruling)

**Status**: IN PROGRESS — code LANDED `83e99fccc` + fixups to `01fee6a42`, at mode `off`; owed: a ≥30/core latency bin before mode `on`, which packet `0223cae3d185` sets

- **Levers (design option B plus both reviews):**
  - **Router.** It declares `repick_leave=<accts>|-` from `REPICK_LEAVE_VERDICTS = ("on-pace", "hold-credits")`. `claimed` and `flat` stay (correctness 1).
    - Data-quality holds (`pace-stale`, `pace-unknown`, `level-stale`) stay, with `why=held-unknown` (correctness 2).
    - `dispatch_held=` and `repick_held=<mode>` are also published, appended after `dispatch_floor=` in route-meta (`bin/claude-accounts:11457-11531`; adjacency pinned at `account-recovery-lane.bats:910`).
  - **Consumer.** `recycle_repick` (`handoff-fire.sh:16004-16186`) reads the router cache-only: `--max-wait 0 --max-age 600 --rank general --src "$cur"`, with `--src` after the lane.
    - No sweep and no itimer, so perl's 25 s alarm (`:16039`) stays intact (correctness 3-4, efficacy C1-C2).
    - One retry on rc 142 under a 45 s alarm, the wave-5 pattern (efficacy C4b).
  - **Rows.** Stay rows on every stay carry `pressure=`, `rank_s` and `rank_rc`.
    - rc 2 ⇒ `rank-none`; rc 142/3 ⇒ `rank-unanswered` (C5, correctness 9).
    - A `top-pick` on an incumbent in the held set is classed `held-everywhere` (correctness 5c).
  - **Assign.** `--assign` runs under the same alarm with the id `rp:<SID>:<epoch>`. `hf_recycle_hold` unassigns when the account came from a re-pick (correctness 6, C7).
  - **Mode.** `~/.claude/state/repick-held`. The most restrictive present value wins (off < shadow < on) across the file, env and `accounts.json` (correctness 8).
    - **Code default `off`:** today's decision is kept, with the stay rows logged, so REPORT B6's "write the stays decision to disk" lands whatever the ruling. The ruling sets the mode.
  - **Strand-side stop rule.** An account with D1 moves that closes its week more than `DISPATCH_STRAND_PP` (4 pp) unused flips the mode to off and reopens the ruling. Landings are judged from `recycle-engaged` (correctness 5).
- **Pre-mode measurement (efficacy C3).**
  - Timed runs of the final argv from a PRI-31 shell, in a write-denying sandbox, at ambient, each tagged with load1/ncpu.
  - Report p50, p90 and p99 per bin against 25 s.
  - **Before mode `on`** (not before shadow): ≥ 30 runs in the ≥ 30/core bin. A p99 ≥ 20 s there makes the retry mandatory.
  - Quantitative clause (efficacy C5): among recycles whose incumbent was held, the `rank-unanswered` share at 30-40/core must be ≤ 10%. Above it, the retry stays and `on` waits.
- **Tests.**
  - D1-1..D1-16, including D1-16: a `claimed` incumbent stays; the mutant "leave on any thin_demoted" goes red.
  - Router R-5: `next2:100` ⇒ `dispatch_held=next2 repick_leave=-`.
  - The C-1 fixture with all four accounts and the incumbent `on-pace` (red before: 1.51× < 4×).
  - A cache that predates the incumbent's reset ⇒ stay, `rank_rc=3`.
  - D1-11 taxonomy (142/3/2).
  - With mode off, today's stderr `does not beat … 4x` is kept.
  - Precedence R-2.
  - `/bin/bash` 3.2.
- **Done.**
  - Plan lines for both suites; the per-bin sandbox numbers recorded.
  - At the next thin window, stay and re-pick rows on disk (L, read-only).
- **Kill switch.** `printf off > ~/.claude/state/repick-held`. **Activation.** Converge at mode off; the ruling sets shadow or on.

## W16: late-band idle shed, shadow only (D2b; slot B; may build before the ruling)

**Status**: IN PROGRESS — code LANDED `abb17fa10` `d0ffedbfe` + fixups to `721539ac6`, shadow only; owed: the shed-e1 pair (Tier-L queue row `bbe7b5b1ba63`) and T6, which needs a rig matrix running `lr-shed.py --tick` in an arm (not built); `on` waits on packet `76a584cc935b`

- **Levers (design §6 plus correctness D1-D17 and efficacy E1-E10, each stated):**
  - **Controller.** `lr-shed.py` runs detached, with one writer holding an `O_EXCL` lock on (pid, lstart). The kick writes a different file and checks no pid (D1).
  - **Batch state.** Settled means `summary.settled/` exists. In flight means an `origin: shed` plan with no `summary.settled/`. Shed batches are discovered from disk. `breaker_scan` runs before the band read (D2, D3).
  - **Band rules.**
    - The band opens at weekly ≥ 97%, or when the fast pace puts the wall ≤ 2 h away.
    - The guard requires the slow pace to reach the wall ≥ 2 h before the reset.
    - The level arm acts without a confirmation delay (E2).
    - Inputs pass `math.isfinite` (D4).
    - Windows are keyed on `weekly_reset_at` (D5).
    - A `walled` verdict (used ≥ 1.0, or any rejected 7d/5h fact) sheds nothing (D7).
  - **Idle** = at rest ≥ 30 min, an empty composer, not focused (unknown focus ⇒ hold, D9), no goal, team or background job. At most 4 per account per tick.
  - **Shed environment:** `LR_DEAD_SOURCE_RELEASE=off`, `CC_LR_MOVE_GOAL_HOLD=always` (D7), `LR_MOVE_CARRY_DRAFT=off` (D8), `LR_MOVE_FOCUS_UNKNOWN=hold` (D9), `${A[@]+"${A[@]}"}` array spelling under bash 3.2 (D6).
  - **Yields to recovery.** No queueing while any limited reconciler record is open; that is a queue gate, not a load gate. Shed batches use `cc-lr move --slots 1` and are capped by W11's slot priority (E1, blocker).
  - **Lifecycle.**
    - A bounded release for the one-batch-in-flight gate (E3).
    - The limit re-read inside waits comes from W5 (E4).
    - Transient failures are not final (E5).
    - The cooldown is set on MOVED only (D11).
    - Shadow separates "blind" from "nothing to do" (E7).
  - **Targets** come from `claude-accounts --place` with idle movers, not `tgt[0]` (D17).
    - The requester-identity env is scrubbed.
    - The operator-intent latch is never minted by automation; queued shed moves re-authorize at actuation; a breaker trip aborts unsettled shed batches (D10).
    - Knob typos fail toward no shed (D12).
    - `PLAN_TO`/`MOVE_TO` are sized from measurement, on a monotonic budget (D14).
  - **The replay is re-run on the coded rule** (`shed_band_row` + hysteresis) before any `on` ruling is asked (D13).
  - The casualty breaker and the strand audit drop the shed to shadow.
- **Tests.**
  - D1-D17 controls.
  - The E1 harness test (owed Tier-L run, W4b's `faults/shed-e1.json`): a k = 9 limited cohort plus a concurrent 4-row shed batch ⇒ every member within the no-shed bound. Red arm: `--slots 4` with no yield.
  - T6 rebuilt with power: a batch is queued in the `on` arm when the run's load bins include 25 and 40/core.
  - The worker under `/bin/bash` 3.2 to the handoff line with `hold_focused` absent (D6 red arm).
- **Done.**
  - Suites with plan lines.
  - Shadow rows over ≥ 2 banded walls, after the operator's shadow step (needs row).
  - Before `on` is asked: ≥ 20 actuated move-lane rows after PRI 31 with 0 STRANDED (D15), and the D13 replay.
- **Kill switch.** `rm ~/.reso/limit-recover/shed/mode` (nothing runs while it is absent).

## W17: self-recovery, shadow first (G2; slot A; entry trigger)

**Status**: PARKED — entry trigger unmet: packet `4ab193daae88` is unruled (deadline 2026-11-03), reload R4 is not live, and there is no measured wall or failing guarantee9 cure run

- **Entry trigger** (shared with C1's Gate 0). All of the following must hold:
  - R4 is live, and RK has read the router-cache producers back at ≥ 31 (G2 R6);
  - the self-recovery scope packet is ruled yes;
  - and either the next real weekly wall shows p90(last engaged − detected) for non-held members > 30 min at ≥ 15/core (read from `recon/sessions/*.json` and telemetry), or a Tier-L guarantee9 run at ≥ 30/core fails T1 in the cure arm.

  Otherwise W17 stays parked. Its value over a PRI-31 reconciler is unmeasured, because no cap has happened since 07:23Z (G2 §1 row 9; 2 spawns since then, measured).
- **Levers (design plus efficacy R1-R12 and correctness C1-C14):**
  - The worker runs `/usr/bin/python3 -I` with an explicit `sys.path`, after `chdir` to the package (C1, critical: `-m` in the dying session's cwd imports its files). The hook checks that every module file the worker imports exists (`-f`) and that python is executable (`-x`) before it treats a spawn as act (C12).
  - **S0 band gate:** if `band.base_priority(os.getpid()) < 31`, take no claim, log, and hand back at once with a kick (R3a; G4, not a load check).
  - **Claim and ownership.**
    - An `O_EXCL` latch per `death_uuid`, and a unique rid `self:<sid8>:<pid>:<nonce>` (C2).
    - A self holder always records an lstart, or refuses with `identity-unreadable` (C3).
    - The SIGTERM hand-over means "start no new attempt; keep waiting on the live child", so `settle()` cannot undo it and lr-handoff never becomes a reaped orphan (C4).
    - The reconciler writes `recon/features` with `self-yield-1`. The hook and worker act only when it is present while `recon.on` exists (C5).
  - **Liveness.**
    - Ownership is pid + lstart + a progress stamp. The reconciler takes over a self claim whose progress is older than 180 s, and B3 treats it as soft (R3).
    - A ps timeout is never "dead" (R4, via W9).
    - The worker follows the watcher with `select.kqueue` `EVFILT_PROC`/`NOTE_EXIT` after one lstart check, re-checking every 60 s instead of 2 s `ps` polls (R12).
  - **Resources.**
    - The boot slot (W9's rename steal) is released when lr-handoff exits (R2).
    - A failed mint spawns nothing; a PARKED from lr-handoff means fall back, never retry (R5).
    - Rank is cache-only and hands back when the cache is older than 600 s (R6; producers at 31 after RK). rc 3 is added to T-W14.
  - **Bounds.**
    - The retry window runs from the first lr-handoff spawn, with a separate ceiling on the whole hold (R7).
    - S13's bound is derived from the watcher's load-scaled maximum (`hf_load_scaled` ×4, `handoff-fire.sh:4957`) plus margin (R1).
    - The composed bound is stated: G2's maximum hold, then the reconciler's G with `t_detect` unchanged (R9).
    - Derive is gated for self-driven records (R10).
  - `HELD:load` after confirm is counted, and G1 is not claimed for this lane until W12b's stage retry and its ruling land (R8).
  - The kick is written at worker start and cancelled at settle (R11, C12).
  - The registry is written after verification (C7). The prompt repair is removed (C8). C9-C11 and C13-C14 apply as listed in the review.
- **Tests (red at HEAD unless marked).**
  - T-H8: the hook run from a cwd holding a planted `json.py` and an `lr_recon/` stub ⇒ the worker records the live module path.
  - T-W4: two workers with the same death key ⇒ exactly one `taken`.
  - C3: a self take with an empty lstart ⇒ refused, never `stolen-legacy`.
  - T-W12: the claim and slot dirs still exist after the worker exits while its child lives.
  - T-S6: the multi-process slot race in both arms (with W9).
  - T-R: a live-pid holder with a stale progress stamp ⇒ the record is placed.
  - T-R (R10): no `in-flight-expired` while a live self claim exists.
  - T-R4: no `recon/features` stamp ⇒ the worker runs as shadow `self-skip-recon-not-yielding`.
  - S0: a band below 31 ⇒ no claim.
  - The kqueue follow returns within 1 s of the watcher's exit.
- **Done.**
  - Shadow on the live box writes one `self-shadow` row per death, with the would-act decision and phase timings.
  - **Owed Tier-L run (queue):** guarantee9 with the rig `stop_failure_hook` seam (W4), cure against `tree:<parent>@31`. T1 PASS in cure **and FAIL in red** (power); H5/H9 show no double driver.
  - The act-mode packet is filed once the shadow go criterion holds: ≥ 70% of the cohort eligible, and a median ≥ 5 min earlier than the reconciler's spawn.
- **Kill switch.** The self-recover switch file absent = inert; `recon/features` absent = no act.
- **Activation.** Shadow needs the operator's `touch` (needs row). Act mode needs the act-mode ruling.
- **Reload.** R5 (for the yield stamp).

## Operator decisions and actions

All packets below are filed in W0, after converge, so that every `--receipt` resolves.

**A7: which lane goes first on a newly capped session.** This is a decision; the zero-human ruling itself was made at 17:10:31Z.
- **Question.** Hands-off recovery is on. Should the reconciler go first, with the reset poller stepping in only after a bounded wait (10 minutes, never more than 15)? And should the move lane let go of a session the moment it turns limited?
- **Options and measured outcomes** (A7 §4):
  1. **Keep today's race.**
     - On 10-20 the poller held both claims for 21-22 min on runs that ended PARKED, while the reconciler, already placed, waited 12.5 and 18.5 min.
     - In October the poller recovered 30 of 97 dispatches (31%).
  2. **Reconciler first, with a bounded backstop.**
     - It helps only when detect→PLANNED is under g. In the priority-20 era that failed in 3 of 7 cohorts; at priority 31 it is unmeasured.
     - Part A ships logging-only until this is ruled, and the log measures it.
  3. **Poller first for hook requests.** The poller gives up after 3 dispatches (`lr-reset-poller.sh:1395`).
  4. **Undo the touch.** Plan-only census records closed in a median of 343 min.
- **Recommendation.** Option 2 as amended (W5, W13). **Conviction 60%.**
- **Filing:** `cc-decide open --class B --what "Hands-off recovery is on. Should the reconciler go first on a newly capped session, with the reset poller stepping in only after a bounded wait of 10 minutes (never more than 15), and should the move lane let go of a session the moment it turns limited?" --option "Reconciler first, poller after 10 min::removes the claim race whenever the reconciler places within 10 min; the poller still rescues the rest" --option "Keep today's race::whichever lane takes the claim keeps it; 12.5-18.5 min blocks measured on 2026-10-20" --option "Poller first for hook requests::the poller gives up after 3 dispatches" --option "Turn hands-off recovery off again::plan-only records closed in a median 343 min" --recommendation "Reconciler first, poller after 10 min" --default "Reconciler first, poller after 10 min" --deadline 2026-10-23T17:00:00Z --default-effect change --project claude-infrastructure --conviction 60 --receipt /Users/chrisren/Development/claude-infrastructure/docs/research/lr-sustained-load-2026-10-20/impl/A7-limited-cohort-ruling.md`

**D1: may a recycle leave an account that the router holds back because its own pace will hit the weekly limit.**
- **Question.** When a session recycles onto fresh context, and its account is one the router has stopped giving new work because that account's own pace will hit the weekly limit, should the recycle move to the router's top open account?
- **Options and measured outcomes** (D1 §3-§4):
  1. **Status quo.** 5 of 40 recycles relaunched onto an account at ≥ 90%. 3 of the 9 sessions at the next3 wall got there by recycle, about 284 session-minutes.
  2. **Leave on pace-driven holds only** (`on-pace`, `hold-credits`); stay on `claimed`, `flat` and stale-data holds.
     - 25 of 25 windows at ≥ 90% since 08-29 walled, and cross-account recycles engaged 4 of 4.
     - Estimated 3-4 fewer wall sessions per wall (n = 1 incident).
  3. **Leave on any held verdict** (the design's first form). The reviewers showed that `claimed` is a strand forecast which D1's own charge creates.
  4. **Roomy targets only.**
- **Recommendation.** Leave on pace-driven holds: `shadow` for the first thin window, then `on` if the strand-side stop rule is clean and the router read meets W15's ≥ 30/core numbers. The code lands at mode `off` either way, with stay rows logged. **Conviction 70%.**
- **Filing:** `cc-decide open --class B --what "When a session recycles and its account is one the router has stopped giving new work because its own pace will hit the weekly limit, should the recycle move to the router's top open account? Recommended: yes for pace-driven holds only, logged without acting for the first nearly-full week, then live." --option "Leave on pace-driven holds::estimated 3-4 fewer sessions at each weekly wall; quota stranding watched by a stop rule" --option "Status quo::recycles keep landing on a nearly-full account; 3 of 9 wall sessions on 2026-10-20" --option "Leave on any hold::also leaves accounts whose hold is a forecast the move itself creates" --recommendation "Leave on pace-driven holds, shadow first" --default "Leave on pace-driven holds, shadow first" --deadline 2026-10-24T17:00:00Z --default-effect change --project claude-infrastructure --conviction 70 --receipt /Users/chrisren/Development/claude-infrastructure/docs/research/lr-sustained-load-2026-10-20/impl/D1-repick-ruling.md`

**D2: moving idle sessions before the weekly wall (two decisions).**
- **D2b question.** Before an account hits its weekly limit, may the system move its idle, healthy sessions (at rest 30+ minutes, empty input box, not focused, no goal, team or background job) to another account without asking? That reverses `bin/cc-lr:1801`.
- **D2b options and measured outcomes** (D2 §0, §4; a replay of 7 walls, estimated):
  1. **No:** about 6 limited sessions per wall.
  2. **Late band at 97% with a 2 h guard:** 15 of 43 avoided at 20-min latency (8 of 43 at 45 min), ≤ 0.2 pp stranded per wall. These figures come from a replay of a rule simpler than the coded one, and the strand error is plausibly upward (D2 correctness D13). W16 re-runs the replay on the coded rule before `on` is asked.
  3. **99% trigger:** 11 of 43, 0 pp.
  4. **From 90% with no guard:** 24 of 43, but 2.2-3.1 pp stranded per wall, against the 2026-10-17 "use up the week" ruling. Rejected.
  - The actuator is the risk: the move lane's 66 actuated rows ended 41 MOVED, 13 FAILED and 12 STRANDED (pre-PRI-31, measured).
- **D2a question.** Turn on the at-the-wall idle fan-out. Zero strand by construction; 6-17 of 43 avoided, depending on move latency. With W13, idle moves take no boot slot while an overdue limited session waits.
- **Recommendation.** Build D2b shadow-only (W16) and decide `on` after ≥ 2 banded walls of shadow, a PRI-31 casualty rate, and the re-run replay. "Log only" needs the operator's one-line shadow switch (needs row below). Turn D2a on after W13 is live and guarantee30 shows no slot starvation. **Conviction 45% (D2b), 55% (D2a).**
- **Filing:**
  - `cc-decide open --class B --what "Before an account hits its weekly limit, may the system move its idle, healthy sessions to another account without asking? Recommended: build it to log what it would do, act on nothing, and decide after two nearly-full weeks of logs." --option "Log only, decide later::no session moves; two weeks of would-move rows once you switch logging on (one command)" --option "No::about 6 limited sessions per wall continue" --option "Act at 97% with a 2-hour guard::estimated 8-15 of 43 limited sessions avoided, at most 0.2 points of quota stranded per wall, to be re-checked on the exact rule before acting" --recommendation "Log only, decide later" --default "Log only, decide later" --deadline 2026-10-27T17:00:00Z --default-effect no-change --project claude-infrastructure --conviction 45 --receipt /Users/chrisren/Development/claude-infrastructure/docs/research/lr-sustained-load-2026-10-20/impl/D2-warning-band-shedding.md`
  - `cc-decide open --class B --what "When an account hits its weekly limit, should the reconciler also move that account's idle sessions right away, once it reserves boot slots for limited sessions first?" --option "Yes, after the slot reservation is live::6-17 of 43 limited sessions avoided, no quota stranded" --option "No::idle sessions wait until they start a turn and hit the limit" --recommendation "Yes, after the slot reservation is live" --default "No" --deadline 2026-10-27T17:00:00Z --default-effect no-change --project claude-infrastructure --conviction 55 --receipt /Users/chrisren/Development/claude-infrastructure/docs/research/lr-sustained-load-2026-10-20/impl/D2-warning-band-shedding.md`

**TR: the typed-relaunch hold (new).**
- **Question.** When a move cannot stage its successor and would have to type the relaunch, the recycle holds whenever load is above 24 per core (20 at the precheck). Under the standing 15-40 per core, that hold almost never releases. Should it be replaced by a check of whether the terminal itself answers promptly, after one retry of staging?
- **Options and measured outcomes:**
  1. **Retry staging, then check the terminal.** The typed path runs only after a second staging attempt fails, and only if the terminal answers a one-window query within 2 s and its main thread is not background-banded. No hold on load.
     - Evidence: typing was measured clean up to ~32/core (33 of 33 typed relaunches above 8/core submitted first try; `handoff-fire.sh:4150-4155`). The one harm (pane 44) was a backlogged kitty at 42-45/core (REPORT §3.3).
  2. **Keep the 24/20 per-core hold.** Approved 2026-10-19 (decision 600709c5fe4b). Staged moves (48 of 48 since 10-18) are exempt. A move that cannot stage holds and pages at 15 min, re-checked every 2 min, for as long as load stays above 24.
  3. **Retry staging only, keep the hold.** Fewer moves reach the typed path; the rest still wait for load.
- **Recommendation.** Option 1. **Conviction 55%:** the stage-refusal rate is unmeasured at 31, and the terminal check is new.
- **Filing:** `cc-decide open --class B --what "When a move cannot prepare its replacement session and would have to type the relaunch, the recycle waits whenever load is above 24 per core (20 at its first check). At the box's standing 15-40 per core that wait almost never ends. Should it instead retry the preparation once and then check only whether the terminal itself answers promptly?" --option "Retry, then check the terminal::no wait on load; typing proceeds only into a terminal that answers within 2 s and is not throttled" --option "Keep the 24 and 20 per core wait::approved 2026-10-19; affects only moves that cannot prepare a replacement (none of 48 since 10-18)" --option "Retry only, keep the wait::fewer moves reach typing; the rest still wait for load" --recommendation "Retry, then check the terminal" --default "Retry only, keep the wait" --deadline 2026-10-24T17:00:00Z --default-effect change --project claude-infrastructure --conviction 55 --receipt /Users/chrisren/Development/claude-infrastructure/docs/research/lr-sustained-load-2026-10-20/impl/PLAN.md`

**Pass-boundary restart request (A6 lever 11; new packet).**
- **Question.** May an agent restart the recovery service at the end of its current pass, by dropping a request file, to load landed fixes, instead of asking you to reload it for each batch?
- **Options:**
  1. **Yes, at a pass boundary.** No pass is killed, restarts happen within one pass at any load, and R2-R5 stop needing you.
  2. **No, keep operator reloads.** Five reload batches over the plan; each needs your command (`--now` after the first).
- **Recommendation.** Yes. **Conviction 70%:** A6 makes a restart safe, and the request exits cleanly under KeepAlive.
- **Filing:** `cc-decide open --class B --what "May an agent restart the limit-recovery service at the end of its current pass, by dropping a request file, to load fixes that have already landed, instead of asking you to run the reload for each batch?" --option "Yes, at a pass boundary::no work is cut off mid-pass; reloads stop needing you" --option "No, keep operator reloads::about five reload commands over this plan" --recommendation "Yes, at a pass boundary" --default "No, keep operator reloads" --deadline 2026-10-23T17:00:00Z --default-effect no-change --project claude-infrastructure --conviction 70 --receipt /Users/chrisren/Development/claude-infrastructure/docs/research/lr-sustained-load-2026-10-20/impl/A6-restart-safety.md`

**Harness load and windows (B1 Q1-Q3; new packets).**
- **Top-up question.** To prove recovery at the top of the 15-40 per core range on demand, may the test harness add background CPU load (up to 40 per core, ≤ 45 min per proof run)? And, separately, up to 16 foreground spinner threads (up to about 30% of sessions' CPU share, ≤ 30 min)?
  - Options:
    1. **Background only.** Efficiency-core work (Spotlight, renderers) slows by about half during the run; sessions are unaffected.
    2. **Both.** Also takes up to 30% of sessions' CPU for 30 min.
    3. **Neither.** The top-range proof waits for ambient load, which read 32 per core at plan time.
  - Recommendation: background only. **Conviction 55%.** Default: neither.
- **Windows question.** May the harness open its test windows in your main terminal (up to ⌈n/2⌉ per arm, each on its own Space, focus handed back, about 55 extra file handles), instead of a separate terminal instance that macOS may throttle?
  - Recommendation: main terminal. **Conviction 65%.** Default: main terminal.
- **Ruled 2026-10-22 17:05Z (both defaults fired, no veto):** windows `75bb72581c54` → main terminal; top-up `4eee30ac4de4` → neither. No code change was needed: the harness already defaulted to both (`tests/rig/lr-load-harness.sh` header and `run` refusals now say "ruled"). Backlog row `571f88e04400`.
- **Filing:**
  - `cc-decide open --class B --what "To prove recovery at the top of the 15-40 per core range on demand, may the recovery test harness add background CPU load (up to 40 per core, at most 45 minutes per run), and separately up to 16 foreground spinner threads (up to about 30% of sessions' CPU share, at most 30 minutes)?" --option "Background only::efficiency-core background work slows by about half during a run; sessions unaffected" --option "Both::also takes up to 30% of sessions' CPU for 30 minutes" --option "Neither::the top-range proof waits for ambient load to get there" --recommendation "Background only" --default "Neither" --deadline 2026-10-22T17:00:00Z --default-effect no-change --project claude-infrastructure --conviction 55 --receipt /Users/chrisren/Development/claude-infrastructure/docs/research/lr-sustained-load-2026-10-20/impl/B1-load-harness.md`
  - `cc-decide open --class B --what "May the recovery test harness open its test windows in your main terminal (a few per run, each on its own Space, focus handed back, about 55 extra file handles), instead of a separate terminal instance that macOS may throttle?" --option "Main terminal::measures the same priority band production sees; focus thefts are counted and handed back" --option "Separate instance::nothing opens in your terminal; that instance may be throttled, so results may not match production" --recommendation "Main terminal" --default "Main terminal" --deadline 2026-10-22T17:00:00Z --default-effect change --project claude-infrastructure --conviction 65 --receipt /Users/chrisren/Development/claude-infrastructure/docs/research/lr-sustained-load-2026-10-20/impl/B1-load-harness.md`

**Self-recovery scope (G2 §7 ask 1; new packet).**
- **Question.** When a session has already hit its usage cap, may its own stop hook start a background worker that moves it to another account in the same pane, spending no model turn? The earlier ruling said account switching is "not a Stop-hook nudge" (`VOLUNTARY_ACCOUNT_SWITCH.md:40,382-390`).
- **Options:**
  1. **Yes; that ruling covers nudging a working session, not moving an already-capped one.** This enables W17 once its measured trigger fires, shadow first.
  2. **No.** Self-recovery stays unbuilt, and the reconciler remains the only driver.
- **Recommendation.** Yes. **Conviction 60%.** Default: no.
- **Filing:** `cc-decide open --class B --what "When a session has already hit its usage cap, may its own stop hook start a background worker that moves it to another account in the same pane, spending no model turn? The earlier ruling said account switching is not a stop-hook nudge; this asks whether that ruling covers an already-capped session." --option "Yes, it does not cover an already-capped session::self-recovery can be built once its measured trigger fires, logging only at first" --option "No::the central recovery service stays the only driver" --recommendation "Yes, it does not cover an already-capped session" --default "No" --deadline 2026-11-03T17:00:00Z --default-effect no-change --project claude-infrastructure --conviction 60 --receipt /Users/chrisren/Development/claude-infrastructure/docs/research/lr-sustained-load-2026-10-20/impl/G2-self-recovery.md`
- **Act mode** gets its own packet when W17's shadow go criterion holds: options, measured shadow numbers and conviction at that time.

**B8: kitty hygiene (operator actions plus three decisions).**
- **Measured.**
  - Kitty was App-Napped from 03:56:48 to 04:08:41Z during the incident.
  - A napped, non-focal kitty reads base priority 4 on every thread.
  - 157 zombies sit under kitty 853.
  - It holds 121-122 numeric fds against a probable 256 soft limit (B8 §1 and its reviews).
- **Actions, in order** (no production window touched):
  - **O0:** baseline. An agent may run `bash ~/.claude/scripts/kitty-hygiene.sh status` after W7.
  - **O1/O3:** the throwaway-probe A/B on `--listen-on unix:/tmp/b8probe/<arm>.sock`. Never ⌘H on kitty 853; re-hide the control probe instead. rc 124 readings are UNKNOWN.
  - **O2:** write the key.
  - **O2b, recommended until 0.50.0:** fd headroom via W7's `no_ui` kitten (`scripts/lib/kitty-fd-headroom.py`), tried first on the probe and read back with its `get` mode.
  - **O4:** at the next kitty start, `CC_RESTORE_GATE_MAX_S=0 ~/.claude/bin/cc-restore --restart-kitty --confirm <pid>`.
    - Beforehand: the dev kitty closed, no b8 probe alive, no `ship-land.sh` in flight.
    - Drafts are not captured by cc-restore, and its fd gate counts lsof rows (208), not fds (121).
    - After an upgrade: `kitten @ ls` and a `get-text` parse against the new kitty, rolling back on failure.
    - The post-start check is challenge-based: ⌘H the new kitty for 90 s, then band ≥ 31.
  - **O5:** verify on the following nights by band reads (W6), never by an RC sampler.
  - **O6:** take 0.50.0 when it is released.
- **Decision D-B8-2.** Take the official cask 0.49.2 (signal fix #10436) at the next natural kitty start. **Recommendation:** yes. **Conviction 55%.**
- **Decision D-B8-3 (new).** Load the in-kitty fd watcher (K4: a `watcher` line in `config/kitty.conf` whose `on_load` raises `RLIMIT_NOFILE` to 8192) at the next start. On 0.49.2+ it is live at the land itself, so approval comes before the land (B8 correctness (i)). **Recommendation:** yes, until 0.50.0 (B8 E-6: "K4 is not optional on 0.48.2 or 0.49.x"). **Conviction 60%.** If yes, a short slot-C follow-up lands it.
- **Decision D-B8-4 (new).** Test, on the throwaway probe only, whether an in-process `beginActivityWithOptions:` call through a `no_ui` kitten stops App Nap on the running kitty without a restart (B8 efficacy 7: the earlier rejection, "cannot reach 853", is refuted; the segfault risk stands and is confined to the probe). **Recommendation:** test on the probe. **Conviction 50%.**
- **Filing:**
  - `cc-backlog needs "Kitty App Nap key: run the throwaway probe A/B (control red), write the key, re-run (treatment green); never hide the production kitty" --class needs-human --run "defaults write net.kovidgoyal.kitty NSAppSleepDisabled -bool YES" --project claude-infrastructure`
  - `cc-backlog needs "Raise the running kitty's open-file limit in place with the headroom kitten: on the throwaway probe first, then the main kitty; read the limit back with its get mode" --class needs-human --run "kitten @ --to unix:/tmp/kitty-853 kitten ~/.claude/scripts/lib/kitty-fd-headroom.py set" --project claude-infrastructure`
  - `cc-backlog needs "At the next kitty start: close the dev kitty, confirm no b8 probe is alive and no ship-land is in flight, restart without the load gate, then run the 90-second hide check on the new kitty" --class needs-human --run "CC_RESTORE_GATE_MAX_S=0 ~/.claude/bin/cc-restore --restart-kitty --confirm <kitty-pid>" --project claude-infrastructure`
  - `cc-decide open --class B --what "Should the next kitty start also upgrade to the official kitty 0.49.2, which stops the zombie pile-up and restores graceful quit and config reload?" --option "Upgrade at the next natural start::signal fix, same signer; repo kitty tooling untested on 0.49" --option "Stay on 0.48.2 until 0.50.0::keeps today's zombies and fd risk" --recommendation "Upgrade at the next natural start" --default "Stay on 0.48.2 until 0.50.0" --deadline 2026-10-27T17:00:00Z --default-effect no-change --project claude-infrastructure --conviction 55 --receipt /Users/chrisren/Development/claude-infrastructure/docs/research/lr-sustained-load-2026-10-20/impl/B8-kitty-hygiene.md`
  - `cc-decide open --class B --what "Should kitty load a small watcher at its next start that raises its open-file limit to 8192, so that a pile-up of unanswered remote-control connections cannot kill its control thread? It runs code inside the terminal that hosts every session." --option "Yes, until kitty 0.50.0::protects the control thread on 0.48 and 0.49; goes live when it lands on 0.49.2 or later" --option "No::rely on the one-off headroom raise and the 0.50.0 fix" --recommendation "Yes, until kitty 0.50.0" --default "No" --deadline 2026-10-27T17:00:00Z --default-effect no-change --project claude-infrastructure --conviction 60 --receipt /Users/chrisren/Development/claude-infrastructure/docs/research/lr-sustained-load-2026-10-20/impl/B8-kitty-hygiene.md`
  - `cc-decide open --class B --what "Should we test, on a throwaway kitty only, whether a small in-kitty call can stop macOS from napping kitty today, without waiting for a restart?" --option "Test on a throwaway kitty::if it works it could protect the running terminal before its next start; a wrong call can crash only the test instance" --option "No::rely on the settings key at the next start" --recommendation "Test on a throwaway kitty" --default "No" --deadline 2026-10-27T17:00:00Z --default-effect no-change --project claude-infrastructure --conviction 50 --receipt /Users/chrisren/Development/claude-infrastructure/docs/research/lr-sustained-load-2026-10-20/impl/B8-kitty-hygiene.md`

**C1: credential flip sequencing (decision plus hygiene actions).**
- **Question.** Should any credential work for switching a directory's account without restarting its sessions wait until the next real weekly wall shows whether the rebuilt relaunch path is fast enough?
- **Measured** (C1 §0):
  - The refresh-token cliff is fixed at ~27.7 days per grant.
  - Unattended re-login succeeded in 3 of 106 runs, so 4 spare grants cost about 4.3 interactive logins a month (estimated).
  - The setup-token design is barred by the 2026-09-08 ruling (`48b46f513`).
  - No cap has happened since the 07:23Z band fix.
- **Options.**
  - Wait for Gate 0: drop C1 if the last non-held member engages within 15 min at ≥ 15/core; prototype on a sacrificial account if it takes over 30 min.
  - Prototype now: needs a sacrificial account and ~4.3 logins a month.
- **Recommendation.** Wait. **Conviction 85%** in the sequencing; **14%** that a safe unattended flip is reachable (correctness review).
- **Filing:**
  - `cc-decide open --class B --what "Should all credential work for switching accounts without restarting sessions wait until the next real weekly wall shows whether the rebuilt relaunch path recovers every session within 15 minutes?" --option "Wait for the next wall::drop the idea if recovery finishes within 15 minutes; prototype on a spare account only if it takes over 30" --option "Prototype now::needs a sacrificial account and about 4 interactive logins a month" --recommendation "Wait for the next wall" --default "Wait for the next wall" --deadline 2026-11-03T17:00:00Z --default-effect no-change --project claude-infrastructure --conviction 85 --receipt /Users/chrisren/Development/claude-infrastructure/docs/research/lr-sustained-load-2026-10-20/impl/C1-credential-flip.md`
  - Hygiene actions, valid whatever C1's outcome; two mixed config dirs (C1 §9 ask 5):
    - `cc-backlog needs "Inspect the leftover .credentials.json in the tertiary config dir (key names only); remove a stale claudeAiOauth key after confirming the keychain item is healthy" --class needs-credential --run "python3 -I -c 'import json,sys;print(sorted(json.load(open(sys.argv[1])).keys()))' /Users/chrisren/.claude-tertiary/.credentials.json" --project claude-infrastructure`
    - `cc-backlog needs "Inspect the leftover .credentials.json in the next config dir (key names only); remove a stale claudeAiOauth key after confirming the keychain item is healthy" --class needs-credential --run "python3 -I -c 'import json,sys;print(sorted(json.load(open(sys.argv[1])).keys()))' /Users/chrisren/.claude-next/.credentials.json" --project claude-infrastructure`

**Conditional decision: the hard stop's thermal line (B3 efficacy 6c).**
- Filed only if W6 shows thermal ≥ 3 on > 5% of passes at ≥ 30/core with memory pressure < 4. The bypass would then be off for load-correlated reasons.
- Options: drop thermal from the stop, or raise its line.
- Recommendation and conviction are set from the data at filing.

**Other operator steps the waves need** (needs rows filed in W0):
- **R1-R5 reloads.** R1: `bash ~/.claude/scripts/limit-recover/lr-band-reload.sh --confirm lr-band`; R2-R5 add `--now`. File: `cc-backlog needs "Reload the reconciler at priority 31 to activate the landed limit-recover wave batch R<n> (R2 onward: add --now)" --class needs-human --run "bash ~/.claude/scripts/limit-recover/lr-band-reload.sh --confirm lr-band" --project claude-infrastructure`.
- **RK, the router-cache producers' band (W7).** File: `cc-backlog needs "Reload the account keepwarm and accounts-local jobs at priority 31 (their plists intended it) and read the band back" --class needs-human --run "bash ~/.claude/scripts/limit-recover/lr-band-reload.sh --confirm keepwarm-band" --project claude-infrastructure`.
- **D2b shadow logging** (makes the "Log only" default real). File: `cc-backlog needs "Switch the late-band idle shed to logging-only mode (no session moves)" --class needs-human --run "mkdir -p ~/.reso/limit-recover/shed && printf 'shadow\n' > ~/.reso/limit-recover/shed/mode" --project claude-infrastructure`.
- **Self-recovery shadow (W17, once its trigger and the scope ruling hold).** File at that time: `cc-backlog needs "Switch self-recovery to logging-only mode" --class needs-human --run "touch ~/.reso/limit-recover/self-recover.shadow" --project claude-infrastructure`.
- **Restore-owner follow-ups** (code, out of this plan's scope):
  - `cc-backlog add --title "boot-resume.sh:448-452 tells the operator to wait until load is under 6 per core before restarting a deaf kitty; at the standing 15-40 per core that never happens. Replace with the bounded restore gate (CC_RESTORE_GATE_MAX_S) wording (B8 R8)" --project claude-infrastructure`
  - `cc-backlog add --title "Move path keeps ~20 per-sid projects/*/<sid>.jsonl globs (lr-transplant, lr-fire-resume, lr-handoff, lr-ingest-verify, lr-move-*), measured 1.2-2.4 s each at load1 241-247; no owner (B4 review F10)" --project claude-infrastructure`
    - **Driven 2026-10-20 (backlog `d80b297539d5`).** Owner: `lr_sid_file` in `lr-lib.sh` (lr-transplant's copy is `lrt_at`). It reads the session's own slug first and globs only on a miss. lr-handoff exports `LR_SID_SLUG=slug(--cwd)` to its children, and lr-transplant pins it to the slug it located. Kill switch: `LR_MOVE_LOCATION_FAST=off`. Test: `tests/lr-sid-file.bats`.
    - **Per in-place move, enumerated from the code:** 11 globs before, 5 after.
      - Gone on a slug hit: the voluntary fail-fast read, the tier read (2 globs), the bundle's last-message read (2), and confirm's stub check (1). The stub check is now derived from the copy-count glob confirm already runs.
      - Kept on purpose, because each needs every slug: the admit's source locate ("exactly one copy"), the admit's target-live read (the return hop), confirm's copy count, `lr-ingest-verify` C2 ("exactly one transcript"), and `lr-audit.py find_session` (it picks the newest of several copies).
      - Rare-branch sites stay globs: unconfirm's re-run probe and the fold-stub fallback.
    - **Cost measured** on an 18,401-dir fixture store at load1 266 (5 runs timed with bash 5 `EPOCHREALTIME`): a glob took 0.30-0.81 s (median 0.58), a slug hit 0.007-0.25 s (median 0.07, mostly the subshell fork), and a miss cost the same as a glob.

## The guarantee

**Invariant G, restated with the reviewed terms.** For any limited (or move-requested) record r that no named hard predicate holds:

```
t_first(r) ≤ t_detect(r) + W_soft + P + ceil(k_r / D_eff) · T_att        with P = P_obs ≤ P_cap
```

**The retry clause.**
- After a failed attempt of a soft class (TRANSIENT, our timeout, kitty latency, placer rc 124, an RPC-uncertain C, our own guard), `next_eligible_at − t_exit ≤ B_max` (300 s, `classify.py:18`).
- The next spawn starts by the 2nd pass boundary after `next_eligible_at`, plus only the named waits: boot slot, pace, per-account pacer, and the workers-cap of 16 live actuators (`act.py:477-478`). Each is itself inside the first-attempt bound.
- A repeated deterministic failure re-arms at 900 s (`classify.py:23`) and pages; it is not a soft class.
- No actuator hold reason falls to DETERMINISTIC by default (W8).

**Terms.**
- **W_soft:** 600 s (W11).
- **P:** P_target is 180 s, the observed maximum asserted by T2 (W9). **P_cap ≈ 800 s** is the enforced, n-independent sum of bounds published by W9 (estimated). A bound computed with P_cap is the worst case; acceptance uses P_target once T2 is hard.
- **T_att:** 900 s, a budget, paged and not killed (W11 lever 9). The bound holds only while T3 holds. If T_att,obs exceeds 900 s, the acceptance numbers are recomputed with the observed value and each over-budget attempt has paged.
- **D:** 6, with `D_eff = min(6, free shared slots)`. D_eff ≥ 5 while overdue records wait, because:
  - the move lane is capped at 1 slot by W11's subject-relative slot priority;
  - idle fan-out takes 0 slots while overdue records wait (W13);
  - shed batches queue nothing while limited records are open (W16).

  Self-recovery workers (W17) hold slots only while their lr-handoff runs, and those are limited-record attempts.
- **k_r:** overdue non-held records detected earlier.
- **While W11's hard stop is tripped,** the bypass is off and the bound is today's drip (1 per 30 s per cohort) plus slots. A trip longer than 900 s while overdue records wait pages.
- **No term reads the load average.** `plan.place_timeout` (cap 120 s), `observe.ps_bound` (cap 40 s), `hf_load_scaled` (cap ×4) and `cl_self_wait_s` (cap ×4) stretch bounds and never hold a gate (G1 lint class `capped-bound-stretch`).

**Supporting invariants, and the wave that enforces each:**

| Invariant | Enforced by |
|---|---|
| G1 no wait on load | W1's lint over the widened file set. W8 (actuator env proven as `env-off`, HELD:load as a hold, `load_multiplier` deleted), W12 (`hf_lr_admit`) and W12b (the typed-relaunch hold, per the TR ruling) clear the debt rows. `bin/reso-resume-one:306` stays a printed off-rail debt row. Until the TR ruling, the typed-relaunch hold remains a paged hold, measured by W4's typed group |
| G2 our timeout is never a verdict | W8 (C RPC lines TRANSIENT, our wake-guard TRANSIENT), W9 (ps timeout = unknown, not dead), W11 (stale sentinel = unknown, tripped-then-unknown released) |
| G3 pacing is wall-clock; P ≤ P_cap, P_obs ≤ P_target | W8 (pacer on wall time), W9 (bounded children, per-pass caps), W11 (one probe per pass) |
| G4 band ≥ 31 | the wave-1 band check; W4 reads bands inside every child call; W7 + RK raise the router-cache producers; W12 refuses to proceed into a background-banded kitty; W17's S0 gate |
| G5 no giving up for soft reasons | W8 (C, HELD:load, every actuator hold reason mapped), W11 (unknown-exit resolution, pages wired) |
| G6 restart-neutral | W2, plus W0b (the reaper no longer TERMs an inherited wrapper) |

**How the harness proves it.**
- **Tier G (land gate, seconds).**
  - S1 shows the decision trace does not change from load1 5 to 1000 on 10 CPUs.
  - S2 and S2b bound the first spawn by 2P + ceil(k/6)·T_att with the restore budget active.
  - S3 bounds the retry gap.
  - S4 shows placer rc 124 is never a verdict.
  - S5a/S5b cover restart neutrality.
  - Each case has a mutant that must turn it red.
- **Tier L (on demand, one run box-wide, through the lead's queue).**
  - The cure arm runs at 31 from the candidate tree, against a red arm at 20 or `tree:<parent>@31`.
  - Preconditions P1-P4 must hold; otherwise the verdict is NO-VERDICT and the run is repeated.
  - A reaper TERM of an arm process, or an open limited production record, is also NO-VERDICT.
- **Hard assertions now:** H1-H9.
- **Targets** flip to hard in their owner's wave or owed run:
  - T1 (W11);
  - T2 (W9);
  - T3 (W9 + W12, against modeled boot tails);
  - T4 (W2, owed run);
  - T5 (W4b, proving W5 Part B).
- **Power** requires the red arm to fail an outcome assertion that the cure arm passes. Pass-length-only power exits 5.

**Acceptance numbers.**
- **guarantee9** (n = 9; worst member k_r = 8):
  - with P_target: bound = 600 + 180 + ceil(8/5)·900 = **2,580 s (43 min)**; T_done = bound + 900 = 58 min (estimated from the formula with D_eff 5);
  - worst case with P_cap: 600 + 800 + 1,800 = 3,200 s (53 min).
- **guarantee30** (about 25 non-held limited members): with P_target, 600 + 180 + ceil(24/5)·900 = **5,280 s (88 min)** (estimated).
- **In the cure arm:**
  - 100% of `band.log` lines at 31;
  - P_obs ≤ 180 s on max(rig, production `band.log` in the same window);
  - every retry gap within the H6 rule;
  - zero ESCALATED or IMPOSSIBLE for an ENGAGED-expected member;
  - zero self-claim refusals after `kill9_post_transplant`;
  - ≤ 1 submit token per attempt;
  - drafts intact;
  - zero token-expiry notes at ≥ 15/core, or W11 lever 12 is triggered.
- Each acceptance run records load1/ncpu and the r31-per-P-core bin per attempt. At least one run must have ≥ 30% of its attempts at ≥ 30/core before T1 is called proven at the premise's top half. That claim waits; no wave does.
- **Production** (read-only, at the next real wall after R4):
  - for every non-held limited record, telemetry's net `first − det` ≤ its bound;
  - zero HELD:load-derived IMPOSSIBLE;
  - every hard hold paged;
  - p90(last engaged − detected) recorded as Gate 0 for C1 and W17;
  - the detect→PLANNED distribution recorded as g's acceptance number (W5).
- **Not covered, stated:** the move lane (beyond T5's hand-off), the poller's own runs, boot-resume (OTHER_LANE records are listed by W6 with owner and age) and the dispatcher. The verdict line says `lanes: reconciler`.

## Risks and open questions

| Wave | Conviction | Main risk or open question |
|---|---|---|
| W0 | 95% | none material; the receipts must resolve after converge |
| W0b | 90% | the reaper whitelist's frequency claim is a hypothesis (0 actuator kills on record); the whitelist must not shelter a genuinely abandoned wrapper (the reconciler adopts and settles it, A6) |
| W1 | 70% | the simulation mocks enough of `run_pass` that a real-only path escapes it; the hermetic lint must catch every live-path constructor |
| W2 | 75% | the keeper's interplay with unfenced takers (`lr-unstrand.sh:130`, `lr-move-batch.sh:247`) holds only if the startup stamp is right; UNCONFIRM or C inherited across two restarts is untested at scale |
| W3 | 85% | C3 touches the reader that every ranking verb shares (output-identical by replay); the different-slug residual is closed only once W10 is live |
| W4 | 60% | the red arm may pass at ambient (SIGNAL-DEAD); two-arm isolation in one kitty is argued, not shown; the stub's boot model is still a model; the reaper may still reach arm processes the whitelist does not name (counted as NO-VERDICT) |
| W4b | 60% | a poller stand-in that diverges from the real tick could prove T5 on a lane production does not run; it runs the real `--move-kick` to limit that |
| W5 | 65% | the backstop helps only when detect→PLANNED < g, which is unmeasured at 31 (the shadow log measures it); the backstop can still be the weaker driver |
| W6 | 70% | merge pressure in `_run_pass`; the readout may still WARN on legitimate holds until RC-2's table matches W11's |
| W7 | 65% | the key's effect is inferred from Dia; 0.49.2's compatibility with the repo's kitty tooling is unmeasured; keepwarm at 31 adds PRI-31 CPU every 180 s (sweeps p50 24.6 s at 20) |
| W8 | 60% | a TRANSIENT C retry after rc 5 could double-prompt if the record lands after the token re-read; the 60 s grace, the ordering fix and the re-read guard are the defences. The hold-reason mappings are verified per emitter before landing |
| W9 | 70% | the in-process lstart must match ps's format exactly (one miss in 41 measured); the SIGTERM handler interacts with A6's replay (its finally saves no record); P_cap stays ~13 min worst case |
| W10 | 75% | the intra-pass window, and a per-pass walk cost that grows with project dirs (≈ 0.5 s now) |
| W11 | 55% | the latency gain after waves 1-5 is small (C lane only in the reviewer's simulation); bypassing the per-account pacer is safe only up to the cap of 3 (no 429/529 telemetry); the unknown-exit re-offer's safety is a hypothesis; thermal 3 at 30-40/core is unmeasured |
| W12 | 55% | 21 suites share the old seam; the advisory deferral narrows today's watcher guarantee only where kitty is deaf and its main thread is not background-banded |
| W12b | 55% | the stage-refusal rate at 31 is unmeasured, so the lever may rarely fire; under `terminal`, a responsive-looking kitty can still backlog mid-type (F1's harm) |
| W13 | 60% | whether `plan_only` really flips mid-move is a hypothesis (T-D2 decides Part D) |
| W14 | 50% | an env-bound pane during a deaf kitty may proceed to a step that still needs kitty; its value depends on W12 being on |
| W15 | 70% | the p99 of the router read at ≥ 30/core is unmeasured; stranding is guarded by the stop rule |
| W16 | 45% | move-lane casualties on healthy sessions; burn attribution ±2×; the replay of the coded rule may shrink the benefit |
| W17 | 40% | its value at 31 is unmeasured; 5 critical findings must all hold; it depends on W12's identity, the scope ruling and RK |

**Open questions that would move the plan most:**
- The first post-wave cohort's per-phase pass split, and T_att at 30-40/core (answered by W6 + W4).
- Whether the red arm has power at ambient (W4).
- The p99 of the cache-only router read at ≥ 30/core (W15).
- Whether the next real wall meets Gate 0 (decides C1 and W17).
- Whether admission tokens expire before redemption at ≥ 15/core (W4 measures; W11 lever 12).
- How often a move fails to stage its successor at 31 (W12b, W6).

## Dropped

No design was rated UNSOUND by either reviewer. The closest was C2 as written (its correctness reviewer put "works as specified" at about 0%), and it stays dropped. Each item below was cut, deferred or superseded:

| Item | Why it is out | Re-open trigger |
|---|---|---|
| C2 socket transport for the owed prompt | No relaunch has happened since wave 4. Its target fault (a deaf kitty) dispatches no C at all until W14. As written, its default transport crashes on every spawn (R1) and can send duplicates (R3, R8, R9). C2-lite in W8 keeps the cheap part | Any of C2 §10's triggers with E5's corrections: ≥ 2 argv `FAILED:submit` in the first 20 runs, any kitty-cause C failure, or an UNPROMPTED record > 30 min (now paged by W8) |
| C1 build (design B′) | Operator-only credential work; Gate 0 first; 14% reachable | Gate 0 > 30 min |
| B2 stage 2: async `--place`, async shared probe, 60 s pass budget, async page worker | Reviewers showed it can leave attempts unbounded silently: probe-pending is never counted, the 120 s TTL is shorter than P, the budget runs from pass start, wedged calls are never abandoned, and KMAX can be overcommitted. W3/W10 make `--place` sub-second; W11's one-probe-per-pass and W9's outbox and caps bound the same terms synchronously | Telemetry shows `place_s` p99 > 60 s or pass p99 > 180 s at ≥ 30/core after R4 |
| B2 S1.d merged census `ps` (optional) | Small value (0.01 s saved at 15/core); not needed for the bound | The `ps:all` tty read dominates the ps phase in W6 telemetry |
| B3 kept-target retries | They skip `--place`'s survival floors, store-holds check and KMAX, and keep targets after 429-class failures (F-F, F-G). The 1800 s TTL can expire inside one attempt. Their motive (placer rc 124) shrinks with W3/W10 | `place` rc 124 > 5% at ≥ 30/core after R3 |
| A6 (iii) / REPORT A4 remainder: persisting `refusals`/`last_drip_at`; probe-timeout as no-verdict; sentinel fallback on a probe timeout | Each design deferred it to the other (A6 §2.7 → B3; B3 §4 → A6). W11's overdue bypass skips the probe and the drip after W_soft. Before W_soft, a restart costs ≤ `DRIP_AFTER` passes | W6 shows a post-restart drip delay of > 3 passes on a limited record before W_soft |
| REPORT A1's install of `com.reso.lr-move-kick` | Still not installed (`ls ~/Library/LaunchAgents`). Superseded: wave 1 put the poller at 31, and `cc-lr move` kickstarts it and re-kicks every 15 s (`bin/cc-lr:1731-1747`), so a batch starts at 31 within one kick | A move batch waits > 60 s between request and claim (`move/<batch>` timestamps) |
| B5 K1 (cached composer as draft proof) | Draft-loss paths S1 and S8-S13; its falsifier cannot reach a useful rate; a PRI-4 kitty may not drain a successor (R-5). B8 is the source fix | After B8 O5, with the falsifier rebuilt (≥ 30 occupied pairs, ≥ 300 pairs aged ≥ 300 s, ≥ 30 rows at ≥ 30/core) and an operator ruling |
| B5 tty-write relaunch | XNU refuses TIOCSTI; kitty RC is socket-only | none |
| B5's `actuator_env` `/tmp/kitty-<pid>` socket fallback | Wrong-kitty reads poison the cache (S1) | none |
| B7's `t_dec` grace for C (design E1) | It reopens the double prompt (C's grace is an evidence wait) | none |
| B7's IN-FLIGHT DETERMINISTIC ladder | It turns our own timeout into a verdict while the watcher is live | none |
| B2's separate `recon/passes.jsonl` | Duplicates W6's `pass` rows; one writer | none |
| A6's `_SPAWNED`/`waitpid(-1)` edit | Superseded by W9's registered-only reaping | none |
| A7 options 1, 3 and 4, and REPORT A7's auto-`cc-lr recover` variant | cc-lr origin is sticky and escapes the operator's off switch; poller-first gives up after 3 dispatches | none |
| D1 options leave-on-any-hold, roomy-only, and the rank-stdout flag | Strands `claimed` forecasts; makes the consumer author routing policy; breaks a parsed contract | none |
| D2 shed from 90%, and working-session shedding | 2.2-3.1 pp stranded per wall, against the 10-17 ruling; working sessions need the recovery relaunch itself | none |
| B8 patched kitty build, production RC sampler, ⌘H on kitty 853 | The operator ruled for the official kitty (`891ea9e9d0f3`); the sampler can exhaust fds and kill the talk thread; hiding 853 creates the harmful state | none |
| B1's `58885750c` incident red arm | Not an incident tree: it contains 31f4242e0 and 20368fc85, and has no `band.py` | none |
| G2's prompt repair (C14 in the design) | Can double-prompt (correctness C8) | none |
| REPORT A8 (one seat for a resumed lead) | Superseded by gap 3 and wave 3 (`9fc5964c3`) | none |

Every number above is labelled with its source: a design or review measurement (named), a command run for this plan (the 19:29Z snapshot) or for this critique (named inline), or an estimate from the §5 formula or a named sum of bounds.