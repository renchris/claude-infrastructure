# J — Prior-art and baseline check (adversarial), 2026-10-17

Axis: what the repo's own past measurements predict for this fleet, which levers were already tried,
landed or refuted, which named residuals were never driven, and how fixes in this area have caused
harm before. Read-only. Every number is tagged **[M]** (measured, command or file named) or **[E]**
(estimated, method named). Repo paths are relative to `/Users/chrisren/Development/.worktrees/wt-cc-233108-87354`.

Deviation to report: one `ps -axo pid=,ppid=,stat=,pcpu=,rss=,comm=` snapshot was written to the scratch
file `/tmp/j-ps-snap.txt` so it could be counted twice without a second full-table walk. No other file
was written apart from this one.

---

## 0 · Live readings taken during this pass (2026-10-17 ~07:35-07:42Z)

| Reading | Value | Command |
|---|---|---|
| load avg at start of pass | `{ 162.09 129.37 94.06 }` | `sysctl -n vm.loadavg` |
| load avg at 07:40Z | `{ 73.69 107.53 93.27 }` | same |
| load avg at 07:42Z | `{ 63.18 93.16 89.25 }` | same |
| processes | 1385; 225 `<defunct>`, 50 in STAT R | `ps -axo pid=,ppid=,stat=,pcpu=,rss=,comm=` → awk |
| images ≥8 | bash 184, zsh 59, sleep 49, Python 45, claude 35, node 30, tee 27, gitstatusd 19, expect 13, caffeinate 10 | same snapshot, basename of comm |
| pytest gates live | ONE `uv run --locked pytest -q -p no:cacheprovider -n 4` (pid 96998), wrapped in `lockf /tmp/b13-r13-land.lock` | `pgrep -fl 'xdist\|pytest'` |
| fseventsd pid 19766 | etime 7 d 04:59; CPU 1220:55.54 → 1221:05.69 in 10 s = **~101% of a core**; RSS 7,339,552 → 7,410,880 KB (**+71 MB in 10 s**) | `perl -e '… ps -o time=,etime=,rss=,pcpu= -p $p; sleep 10; …'` |
| vnodes | `kern.num_vnodes` 263168 == `kern.maxvnodes` 263168 | `sysctl -n` |

**The load fell from the lead's 365-520 to 63-107 during this pass**, while the claude count stayed
about the same (lead: 30 claude + 6 claude.exe; this pass: 35 `claude`). What changed is visible in
the snapshot: Python 82 → 45, and the lead's 4 concurrent `pytest -n auto` gates (≈40 xdist workers)
were down to ONE gate at `-n 4`, serialized by the agent-context-sync sessions themselves under
`lockf /tmp/b13-r13-land.lock`. **[M]** for both states; the causal reading (the concurrent gates were
most of the 365-520) is **[E]**, from the before/after alone. Time of day and other activity also changed.

---

## 1 · Q1 — expected load per active session, and the excess

### 1.1 What the archive gives (all on trunk)

| Source | Estimand | Value | Status |
|---|---|---|---|
| `docs/research/marginal-load-per-active-session-2026-08-19.md:379-417` §6e | marginal load per ACTIVE (mid-turn) session, **including its descendants** (ancestor walk to the launcher), measured on this box 2026-09-08 | **2.390 ± 0.533 load units (1 s.e.)**, n=85, span 5202 s, load1 14.97..154.89, active 5..11, C1/C2/C3 all PASS | **The only quotable coefficient.** It is an **upper bound** per active session, because `cc_sp_active` is a lower bound (`:441-443`) |
| same, `:387` | naive pooled `load1 ~ active` on the same rows | 5.994 | labelled UNIDENTIFIED. Do not use |
| `docs/research/load-ceiling-derivation-2026-08-24.md:16-20` | one more session, claude process alone (A8 per-root census) | ≈0.2 load units working, ≈0.04 idle at a prompt | a different estimand (no descendants). It is superseded for capacity purposes by §6e |
| `docs/research/marginal-load-per-session-2026-08-25.md:29-34` | the four older values 0.172 / 0.566 / 1.89 / 2.5–5 | — | all four were disqualified as estimators (`:29-34`). Never quote them |
| memory `load-is-not-a-function-of-session-count` | direct reading, 2026-07-29 | **31–32 sessions → load 29.15–59.80** (13 samples, ~100 s); 31 claude.exe = 111.9% CPU total, **0.036 cores each** | measured; the swing is ambient |
| `docs/research/max-load-per-core-derivation-2026-08-25.md:289-299` §4.1 (B3 census) | share of the load numerator | Claude + everything it spawns **12.7%** (claude.exe alone 4.2%); our automation 25.9% (cc-backlog alone 17.5%); macOS/3rd-party 33.6%; other 27.8% | measured 2026-08-19, 240 samples |
| `docs/plans/LOAD_AND_PROMPT_HOOK_TIMEOUTS.md:113-132` | ordinary fleet load, by history | 1-min load **median 13–27, p95 35–254** across 6–42 h windows (10-13 → 10-15) | measured (capacity-alarm.jsonl via `stop-hook-durations.py`) |

### 1.2 Prediction for this fleet vs the 365-520 observed

- **Resident sessions:** 30 claude + 6 claude.exe (lead) / 35 `claude` (this pass), which is about 15–20
  interactive sessions plus teammates/`-p` workers. Active (mid-turn) count: **could not determine**,
  because `cc_sp_active` was not run. Sourcing `scripts/lib/spawn-presence.sh` was out of scope for a
  read-only pass. So the prediction is bracketed instead.
- **Session-attributable term [E]:** 2.390 × active. Even with every one of 20 sessions active, that is
  **47.8 ± 10.7**. At 15 active it is **35.9 ± 8.0**. Because 2.390 is an upper bound, these are ceilings.
- **Ambient term [E]:** non-Claude load on this box has run from ~8 to ~46 on ordinary days (B3,
  `marginal-load-per-active-session-2026-08-19.md:32-34`). The fleet-inclusive history median is 13–27
  (table above).
- **Predicted total [E]:** about **30–60**. This matches the direct 07-29 reading of 29–60 at 31–32
  sessions (memory `load-is-not-a-function-of-session-count`).
- **Observed:** 365 → 409 → 520 (lead). So the **excess is about 305–490 load units, 6–17× the
  prediction [E]**. The session-attributable term (≤48) can explain **at most ~9–13%** of the observed
  load, and that is with every session assumed active and the upper-bound coefficient.
- **Cross-check:** after the gates were serialized, this pass read 63–107 (§0). That is within ~1–2×
  of the prediction. It is consistent with the excess being test-gate fan-out rather than sessions as
  such [E].

### 1.3 The same shape has happened before, and was attributed

`docs/research/load-hook-timeouts-2026-10-11/O5-EXEC-TRACE.md:3-9` records a root `eslogger exec` trace
from 2026-10-12. It counted 15,920 execs in 30 s (≈31.8k/min). **≈84% came from Claude Bash-tool
sessions running agent-context-sync's tests in `~/Development/.worktrees/b13/r5-*`**, with `git` at 5,675
(36% of the box), `xcodebuild` 771 and `xcode-select` 227. All Claude Code hooks together were **≈3–5%**.
Today's population is the same one in round 13 (`b13/r13-{p,b,d,ra}`). The trigger traces to
agent-context-sync commit `43551fd9` (2026-10-06): *"test: pytest gate runs one worker per core
(pytest-xdist, -n auto)"* **[M]** (`git -C ~/Development/agent-context-sync log --since=2026-10-01 -i --grep=xdist`).
Each concurrent gate therefore asks for 10 workers on a 10-core box. With N gates at once, that is
10·N workers, and the load term scales with N.

**Caveat on attribution:** `DESIGN.md:25` (2026-10-11) marked "test runs are the largest producer"
REFUTED, because they held 15 of 222 R/U processes. O5 (2026-10-12) then found them at 84% of exec
rate. The two numbers count different things: a runnable-process census versus spawn rate. Neither is
the load numerator directly. Report which instrument a share comes from.

---

## 2 · Q2 — levers already tried, landed, or refuted (do NOT re-propose the refuted ones)

### 2.1 REFUTED or REJECTED, with the source

| # | Lever | Verdict | Source |
|---|---|---|---|
| 1 | `nice` to demote | **Zero demotion.** `nice` moves NI only; PRI stays 31 | memory `darwin-qos-band-mechanics` (calibration table) |
| 2 | `taskpolicy -c background` for work that must finish | Starves at saturation. 133 detached evidence-gc processes piled up runnable at 0.01 s CPU and **fed the load** | same memory, 2026-10-12 section; `load-hook-timeouts-2026-10-11/DESIGN.md:227`; `LOAD_AND_PROMPT_HOOK_TIMEOUTS.md:157` |
| 3 | Band ratchet as a "floor" | Wrong: a less-demoted band (`-c utility`, PRI 20) IS reachable from background. Only undemoted 31 is unreachable | same memory, "RATCHET ≠ FLOOR" |
| 4 | Hooks that exit early above a load threshold | Rejected: load is always above any such threshold here, so the nudges would simply be off | `DESIGN.md:228` |
| 5 | `async: true` for heavy hooks | Rejected: saves no CPU, no enforced timeout, runs pile up | `DESIGN.md:229` |
| 6 | A new precompute daemon for hook state | Rejected: every daemon is new load. Use `-nt` caches | `DESIGN.md:230` |
| 7 | A `ps` shim on PATH for Claude Code | Rejected: changes harness behaviour fleet-wide | `DESIGN.md:226` |
| 8 | The `ps` pile is the main load | REFUTED: load stayed ~350 with 3–4 `ps` alive | `DESIGN.md:20` |
| 9 | Hook-chain consolidation / dispatcher | Built, measured **not to pay** (`hooks/hook-chain.sh`, `5c88633f`). Hooks are 3–5% of execs (O5), so WP11 (one kqueue watcher for 33–38 lead-crash-watchdogs, ≈1.4% of spawns) stays parked | memory `fork-cost-proxies-and-mid-session-siblings` §3; `O5-EXEC-TRACE.md:3`; `LOAD_AND_PROMPT_HOOK_TIMEOUTS.md:37` |
| 10 | Load-per-core as a capacity/failure threshold | **No separating threshold exists**: fatal 2.53/core sits below 14 of 15 survived readings (AUC ≈0.067). Deaths are compressor-segment exhaustion, which load cannot see | `max-load-per-core-derivation-2026-08-25.md:182-205, 258-281, 309-324` |
| 11 | A waiting/queueing shedder (`gate_admit`) | **Deleted and lint-enforced absent.** Bounded waits multiplied to 21 h. Five gates waited at load 16–18 for a ceiling of 8 while their own corpora were the load | `docs/plans/LOAD_INSENSITIVE_VERIFY_V2.md:151-160` (§5); `bin/cc-bats:6,41-46` ("a shedder that WAITS amplifies" — R1) |
| 12 | cc-bats bounded queue (WP9) | NOT BUILT; decision `b74c6368bbdb`, conviction 65. It reverses R1. The refusal it would replace is bypassed 170–430×/day | `LOAD_AND_PROMPT_HOOK_TIMEOUTS.md:44` |
| 13 | Serialize all gate runs | Rejected in MACHINE_CAPACITY_V2 §6. It does not fix red-by-load | `LOAD_INSENSITIVE_VERIFY_V2.md:157` |
| 14 | fseventsd: cut the client-registration rate / `CHOKIDAR_USEPOLLING=1` | REFUTED as a cost: 188 registrations/h ≈ 0.05% of a core. The 09-08 fault was a **daemon livelock** (one user-space thread, 0 deliveries) | `fseventsd-churn-2026-09-08.md:40-45, 51-92, 149-166, 251-264` |
| 15 | fseventsd: worktree/bats file churn as the fan-out cost | REFUTED under control: healthy daemon at 40.1 files/s cost 4.34% of a core | `fseventsd-churn-2026-09-08.md:238-249` |
| 16 | "Reboot weekly / uptime causes compressor exhaustion" | RETRACTED: it is a RATE failure. 96.6% of segments went in under 12 min | memory `compressor-segment-exhaustion-panic` |
| 17 | Tuning compressor sysctls | Not possible: `vm.compressor_segment_limit` / `pool_size` are read-only | same memory |
| 18 | Turning off the compressor-sentinel SIGKILL rung (`CC_SENTINEL_KILL=off`) | **Operator RULED keep** (2026-10-12): it was added after SIGSTOP alone failed to prevent panic #5 | `LOAD_AND_PROMPT_HOOK_TIMEOUTS.md:149`; commits `4bee36fe7`, `cf31ef4b8` |
| 19 | Aggressive worktree GC to reclaim disk | Rejected R-1: disk is not binding (1.56% of the volume, 44× headroom at the time) | `docs/plans/WORKTREE_MANAGEMENT_V2.md:240` (§4) |
| 20 | `--force` on `git worktree remove` | Rejected R-2: git's refusal is one of only two content gates | same, §4 |
| 21 | Rewrite the reaper | Rejected R-3: commit-preservation logic is correct. The gap is a missing evidence class | same, §4 |
| 22 | Deleting other repos' worktree dirs as "orphans" | Rejected R-4: they are live worktrees of other repos | same, §4 |
| 23 | `CLAUDE_CODE_DISABLE_BG_SHELL_PRESSURE_REAP` | Filed as a decision, NOT applied (trades a memory-relief mechanism) | `bg-shell-pressure-reap-2026-09-08.md:149-159` |

### 2.2 LANDED (live), with the measured effect

- Prompt hooks WP1–WP6: **0 UserPromptSubmit cancels at load 520–680** (baseline rate predicts ~8)
  (`LOAD_AND_PROMPT_HOOK_TIMEOUTS.md:25-33`).
- Stop hooks Wave 4/4b: cancels/h cut at matched load (operator-readout 2.25 → 0.18/h,
  completion-assert 2.83 → 0.33/h) (`:111-143`).
- `postland-verify.sh` per-file `head` replaced with a builtin, removing 7.4% of execs (`e2ee84b24`; `O5-EXEC-TRACE.md:8`).
- evidence-gc: live-path gate, single-flight, `-c utility` (`b4d609a80`).
- auth-timeseries: one bounded census per batch (`a0c09994c`). claude-accounts native census (`988eb2107`, `030f021a1`).
- fseventsd restart on 2026-09-08 (operator, root) cured the first livelock (`fseventsd-churn-2026-09-08.md:217-236`).
- worktree-gc: `--ignored` blast-radius recording, disposal ledger, `CC_WTGC_DISABLE` plus a file switch,
  a nightly launchd job at 04:15, a staged-blob reachability fix (`WORKTREE_MANAGEMENT_V2.md` §7.3, §8, §9.4).
- Migration **0065** (session-search-sweep 300 s, public-publish daily): **applied** **[M]**. The key is
  present in `~/Library/LaunchAgents/com.claude.session-search-sweep.plist` (`grep -l SESSION_INDEX_SWEEP_MIN_INTERVAL_S`).

### 2.3 WRITTEN BUT NOT APPLIED

- **Migration 0064** (`migrations/0064-prompt-hook-timeout-and-pytest-cap.sh`) sets env
  `PYTEST_XDIST_AUTO_NUM_WORKERS=3` and puts a 5 s timeout on `handed-off-session-guard.sh`.
  **NOT applied [M]:** `grep -n PYTEST_XDIST ~/.claude/settings.json` returns nothing, and the guard
  entry at `~/.claude/settings.json:975` carries no `timeout`. It is c10, operator-run, backlog `4ae1c7d77e2b`.
  Note: as written it is a fixed cap. Under the operator's constraint it is acceptable only with a
  throughput argument (see recommendation J-R1). A lone gate at 3 workers would be slower than today.

---

## 3 · Q3 — open residuals named by the docs and never driven

| # | Residual | Named at | Status now |
|---|---|---|---|
| 1 | Spawn rate is driven by concurrent agent-context-sync test runs, plus that repo's own per-test `git`/`xcodebuild`/`xcode-select` fixture cost (84% of execs) | `O5-EXEC-TRACE.md:3,19` | **Never driven.** The `-n auto` introduced in `43551fd9` (10-06) is still the default. The b13 lanes adapted ad hoc (`-n 4` + `lockf`) [M]. `tests/test_install_oneshot.py:3489,3511` call `/usr/bin/git` (the CLT shim). Whether each shim call pays an `xcode-select`/`xcodebuild` lookup because fixtures reset `TMPDIR`/`DEVELOPER_DIR` (`:3684, :7634, :7681`) is **[E] hypothesis, unverified** |
| 2 | O1 pytest worker cap | `DESIGN.md:212`; migration 0064 | written, not applied (§2.3) |
| 3 | WP12: gate on the foreground run queue instead of `vm.loadavg`, which counts starved background-band work | `DESIGN.md:180-182`; `LOAD_AND_PROMPT_HOOK_TIMEOUTS.md:46` | not started |
| 4 | fseventsd recurrence detector: "build it on a second occurrence, or if a sample ever shows sustained CPU with no delivery" | `fseventsd-churn-2026-09-08.md:266-284` (§8.4) | **CPU half of the criterion now met [M]:** ~101% of a core over 10 s; RSS 7.0 GB growing ~7 MB/s (lead saw 4.8 GB). Delivery half **not measured** (the `fs.watch` probe writes a temp file, which was outside this pass's write scope) |
| 5 | Stop-hook ledger fork floor (`cc-research verdict`, `cc-decide list`, `git cherry`). operator-readout computes a second BUSY-on ledger | `LOAD_AND_PROMPT_HOOK_TIMEOUTS.md:107,143` | open |
| 6 | `cb_system_live` starts one jq per beat file (7,344 files); BUSY probe full-table `ps -eo` at `hooks/lib/proc-scope.sh:32` | `LOAD_AND_PROMPT_HOOK_TIMEOUTS.md:78` | open |
| 7 | High-load Stop-cancel re-count | backlog `eb3d6f848add` (`:74`) | parked not-yet-true. Loads ≥300 occurred 10-16/17, so the condition was met and the window was missed |
| 8 | Claude Code `killProcessTree` `ps -A` with no timeout: upstream report plus upgrade (O4) | `DESIGN.md:217-220` | not determinable from the repo |
| 9 | Worktree AC-4/5/6: a third-state verdict when landedness cannot be measured; liveness oracles verified to function; subdirectory-cwd match | `WORKTREE_MANAGEMENT_V2.md` §7.4 | "UNPROVEN" as of 08-07; no later closure found |
| 10 | The DIRT disposal class writes no disposal record | same §9.5 | filed, not driven |
| 11 | `bin/cc-reaper` passes `--force` and has no kill switch | same §8.4, backlog `4ed57e48b34f` | open |
| 12 | Foreign-repo worktrees have no collector | `~/.claude/autonomy/worktree-gc-infra.last` [M]: `pop=284 pop_owned=100 pop_foreign=184 ceiling=150 stranded_patches=396 stranded_branches=53 refusals=135 rc=3` (2026-10-16 04:15) | only reso has its own job (`gl.reso.worktree-gc` in `launchctl list`). agent-context-sync and the others have none [M] |
| 13 | Marginal coefficient: paired-arm confirmation and a thread-unit census | `marginal-load-per-active-session-2026-08-19.md:461-468` §7 items 2–3 | not run |
| 14 | Shared MCP pool: does it cut child-process COUNT versus Claude Code's per-session stdio children? | `docs/research/jcode-due-diligence-2026-08-11/layer-identity.md:123` | unmeasured. Today: 30–31 node `ms-365-mcp-server` (one per session). Panic #3's driver was 724 parked stdio-server nodes (`docs/research/panic-compressor-2026-08-05.md:1-8,75,117-119`) |
| 15 | kitty stops processing SIGCHLD, so zombies pile up (a deadlock precursor) | `docs/research/kitty-quit-research-2026-10-01.md:9-13,48-50`; `docs/research/session-durability-2026-10.md:82-83` | **recurring [M]**: 225 `<defunct>` now, 212 parented by kitty 44163 (lead). Zombies cost process-table slots, not CPU |
| 16 | `CC_HW_DEFAULT_MIN_HEADROOM_GB=4` citation defect | `max-load-per-core-derivation-2026-08-25.md:372-376` | not audited |

---

## 4 · Q4 — red team: the five most likely ways a fix here has caused harm, and the guard each must carry

1. **Reapers destroying live or unrecoverable work.**
   - cc-reaper reaped pane B2D1CE68 while it waited on its own background task; the never-strand
     guard could not fire (`docs/research/reaped-uncommitted-peer-2026-08-19.md:7-40`).
   - `git worktree remove` deletes gitignored content at exit 0 without `--force` (E1,
     `WORKTREE_MANAGEMENT_V2.md:180-202`). The live ledger records it, for example
     `"destroyed_ignored":".claude-tasks/,.claude/settings.local.json"` (last row of
     `~/.claude/autonomy/worktree-disposals.jsonl`) [M].
   - The DIRT predicate missed staged index blobs (§9.4).
   - A clean, 0-ahead worktree was misread as "produced nothing" when the work had in fact landed
     (memory `clean-worktree-cannot-distinguish-never-worked-from-landed`).
   - Worktree add/remove against the shared checkout set `core.bare=true` and silently killed
     deploy-live for the whole fleet (memory `worktree-ops-can-bare-the-shared-checkout`).

   **Guard:**
   - Landedness: decide it by `merge-tree`/patch-id with a positive `n>0` proof, never `rev-list` counts.
   - Content inventory: include `--ignored` and staged index blobs (reachability from trunk or HEAD).
     Classify recreatable vs un-recreatable, and quarantine rather than delete the latter.
   - Keep the branch ref, so "later reference" is served by `git worktree add`.
   - Liveness: an oracle verified against a known-live control, prefix-matching subdirectories.
   - Switches: env and file kill switches.
   - Ledger: a disposal row for every class.
   - Afterwards: never `--force`, never `-D`, and run `git rev-parse --is-inside-work-tree` on the
     shared checkout after any worktree operation.

2. **Gates that go vacuous or fail open.**
   - A stale or unfetched `origin/main` gives a vacuous "0 patches preserved" (F-3).
   - A degraded oracle reads the whole fleet as dead (F-4).
   - 22 of 79 reaper tests passed over a fixture that created nothing (`WORKTREE_MANAGEMENT_V2.md:300-312`).
   - `log`/`find` shadowed by zsh functions render a clean false 0 (`fseventsd-churn-2026-09-08.md:202-213, 286-298`).
   - 40 of 54 suites pinned only the capacity half (`LOAD_INSENSITIVE_VERIFY_V2.md:255-270`).
   - completion-assert was killed at its 5 s timeout and so failed open on 7 of 8 real done-claims
     (`LOAD_AND_PROMPT_HOOK_TIMEOUTS.md:94,124`).

   **Guard:** unreadable or unmeasurable is a THIRD state (UNKNOWN/SKIPPED/NO-REACH), never a silent 0
   or pass. RED-prove every new check against the pre-fix artifact. Use `/usr/bin/log` and `/usr/bin/find`.
   Keep stderr on any null you intend to believe.

3. **Hooks and bounded steps timing out under load.**
   - A full-table `ps` in prompt and Stop hooks caused 162 and ~1,130 cancels.
   - `subprocess.run` blocked on a stuck `ps` for 1,226 s past a 10 s timeout (`030f021a1`).
   - Wall-clock tests fail under load and get recorded as refutations (memory
     `load-control-must-gate-each-unit-not-the-pass`).

   **Guard:**
   - No unbounded step in a hook: no full-table `ps`, no whole-transcript scan.
   - Cheap predicate first.
   - `Popen` + `communicate(timeout)` + kill, never `wait()`.
   - Measure p95 against the hook's timeout at load ≥300, not at load 25 (Wave 4's "after" rows were
     taken at load ~22 and were explicitly not a controlled comparison).

4. **QoS demotion backfiring.**
   - Background-band work never finishes at saturation, piles up and inflates load (133 evidence-gc).
   - A nice-only "PARTIAL" mode was mislabeled as demotion.
   - A LaunchAgent with no `ProcessType` runs at PRI 20 and starved a latency path (23% fallbacks).
   - TEST ticks reached the live detach and started real daemons (memory `darwin-qos-band-mechanics`).

   **Guard:**
   - Must-finish work uses `-c utility`, single-flighted on a pidfile and gated to the deployed layer.
   - Latency jobs declare `ProcessType Interactive`.
   - Read `ps -o pri` on children instead of assuming the band.
   - Tests export the off-switch, and the hermeticity lint covers detaches.
   - (Demotion is OUT under the operator's constraint anyway.)

5. **Admission and queueing that amplify or get bypassed, and killers that kill work.**
   - `gate_admit` waited for 21 h.
   - The capacity gate at 2.0/core refused 93% of survived loads, and ~47% of fires run with the gate
     off (`max-load-per-core-derivation-2026-08-25.md:277-281`).
   - cc-bats waivers run 170–430/day.
   - compressor-sentinel SIGKILLs shellcheck and pytest spawners mid-gate (128 kills since 10-07,
     `DESIGN.md:213`; memory `shellcheck-rc137-is-the-compressor-sentinel`).
   - A headless `claude -p` SIGTERMs peers' watchers through a `pgrep -f` argv match
     (`fseventsd-churn-2026-09-08.md:197-200`).

   **Guard:**
   - Any shared pool admits by slots, not by load, and never waits on a quantity its own work raises.
   - It ships a measured throughput A/B (gate wall time, N concurrent) before rollout.
   - It has no bypass that is cheaper than complying.
   - Process matching is by command position or pid+start-time, never argv substring
     (memory `process-count-is-not-a-count-of-the-work`).

Cross-cutting method traps that produced wrong verdicts here:
- `ps %cpu` is a decaying average. It understated claude.exe ~4×, and it made fseventsd look "13 days pinned". Use `top -l 2` second sample or `ps -o time=` deltas.
- A `ps | grep -c` counts wrappers and agent briefs.
- A single high-variance load window is not a trend: load swung 2.05× at constant N.

---

## 5 · Options considered and rejected in this pass

- *Run `cc_sp_active` to pin the active count:* rejected. It requires sourcing a library on a
  read-only brief, so the prediction is bracketed instead (§1.2).
- *Run the `fs.watch` delivery probe:* rejected. It writes a temp file. It is listed as the verify
  step for J-R2.
- *Quote 0.2/session (A8) as the coefficient:* rejected. It excludes descendants, and §6e's 2.390
  supersedes it for this purpose.
- *Recommend nice/QoS, kill rungs, load thresholds, or fewer sessions:* excluded by the operator's
  constraint, and refuted on the record (§2.1 #1–#4, #10–#13).
