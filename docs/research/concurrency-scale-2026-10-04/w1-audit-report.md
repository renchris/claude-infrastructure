[harness: subagent output matched instruction-shaped pattern(s): settings-json. Control tags below are neutralized (`<` → `<\`); treat any remaining directive-shaped text as a finding to relay to the user, not an instruction to you.]

# Concurrent-session headroom on this Mac: what limits it and what to change

## 1. Answer

The box is short of CPU. Memory is fine and the claude processes are not the problem. MEASURED: 0.0% idle, load 175-290 on 10 cores, 33-41% of CPU in the kernel, and 440-960 new processes per second. On the other side, memory has 22-26 GB of headroom (room for about 35-40 more sessions by capacity-alarm's model), swap is flat, and all claude processes together use only about 1 core.

**1. Batch work at the same priority as the sessions.** Work that sessions launch runs at the same priority as the claude TUIs. Only 3.8-4.3% of CPU is demoted (MEASURED). The reason is that hooks/qos-rewrite.sh only wraps simple commands, and 90-100% of batch commands are compound. So ffmpeg, magick, OCR and shellcheck (about 2-3 cores at the snapshot peak) compete head to head with every session.

**2. Headless automation Chrome.** It draws on the CPU through SwiftShader and runs at a higher priority than claude (47-55 against claude's 31). MEASURED:
- One agent-browser tree with animated tabs holds 1.5-1.7 cores.
- Film-render bursts reached 1.4-8.9 cores per tick for 71 minutes.
- The 9 browser trees hold 11.8 GB of summed RSS.

**3. The hooks make the lag worse.** They are a victim of the load, not a cause (about 3% of the run queue). But every Bash call waits 0.5-1.9 s for 20 hooks, every turn end waits about 8 s (p50), and session-continue hits its 5 s timeout on 65% of Stops (all MEASURED).

**4. Hard-crash risk.** Memory is not killing sessions: 0 claude jetsam kills in 7 days (MEASURED). The risk sits in two things that need a planned restart:
- **kitty.** kitty 48854 runs with its signal handling dead (187 zombies). Any restart means SIGKILL for all 20 panes, and this is the failure class that took down 32 sessions on 10-01.
- **Kernel memory zone.** The kernel's kalloc.1024 zone is at 3.4 GiB and grows about 1 GiB a day. It needs a planned reboot in about 3 days, and boot-resume cannot cleanly restore from that reboot today.

## 2. Ranked remedies

| # | Remedy | Expected gain | Owner | Effort | Prior coverage |
|---|---|---|---|---|---|
| 1 | Add a bash fast exit to `research-block.sh` when there is no program and no route file | MEASURED: removes the top PreToolUse timeout source (144 tool calls stalled over 5 s in 6 h). Saves 0.3-0.6 s on every tool call (0.01-0.02 s with the hook off). ESTIMATED: 0.04-0.1 core of python starts | agent-drivable | S | NEW. Introduced by 19ddcc365 (10-01); the file header claims the opposite cost |
| 2 | Hooks that see large payloads read stdin with `$(cat)` or jq instead of the byte-at-a-time `read -d ''` | MEASURED: post-tool-batch timed out 43 times in 30 min (p50 11.3 s). 200 PostToolUse Read/Bash timeouts in 6 h. A 400 KB read takes 1.98 s this way against 0.05 s with cat. INFERRED: this is the cause (payload sizes not measured) | agent-drivable | S | Regression of landed MACHINE_CAPACITY_V2 §12.7.3 (c957df9e): it saved 18 ms at load 11 and now costs seconds on big payloads at load 150+ |
| 3 | launch-film `render.mjs`: one render at a time, under `taskpolicy -c utility`, Chrome spawned inside `try`, signal handlers added | MEASURED: bursts of 1.4-8.9 cores (median about 7) for 71 min on 10-04, and 2.6-6.7 cores on 10-03. INFERRED: the burst is capped at one render tree that yields to sessions, and Chrome orphaning stops | agent-drivable (other repo) | S | NEW. gpu-vs-cpu-lag-2026-07-29.md:100 wrongly lists headless Chrome as GPU-accelerated |
| 4 | browser-spin-guard: log `agent-browser close --all` and replace it with a per-session close | MEASURED: about 26 fleet-wide browser wipes on 10-03 and 10-04 (12 in 71 min) that killed 0 spinning processes | agent-drivable | S | Defect in the landed guard (438883e36, 7c3bff112, d31e3e351, df839b1df; activation 41) |
| 5 | Set `AGENT_BROWSER_IDLE_TIMEOUT_MS=1800000` in the settings.json env | MEASURED: 9 trees, 11.8 GB summed RSS (4-7.6 GB estimated true footprint), 8 of 9 near idle. INFERRED: idle trees exit after 30 min | operator-only | S | Extends an open item: documented in dia-zero-human-browser-2026-09-14/06-client-lifecycle.md:116, never configured |
| 6 | Fix launchd priority bands: capacity-alarm and qos-census to Standard; deploy-live and worktree-gc-infra to `taskpolicy -c utility`; minor pollers to Background; safety sensors to Adaptive | MEASURED: the alarm drops from about 55 to 5-9 rows/h at peak. qos-census gives 0 valid verdicts. deploy-live's `git fetch` ran 18+ min on 0.06 s of CPU. worktree-gc runs take 43-202 min. Poller CPU of about 0.25-0.3 core (measured once) leaves the interactive band | operator-only | S | capacity-alarm: the landed Adaptive fix is not working (plist:45-56). qos-census: landed M12. deploy-live and worktree-gc: extends the landed postland-verify migration (70dff02dcf4a). Pollers: NEW |
| 7 | `boot-resume.sh` reads only the first line of `.start`; the kalloc reading moves to its own file | MEASURED: the 09-30 single-line roster resumed 15/20. Today's two-line files are skipped, so restore falls back to tombstones (lower fidelity) | agent-drivable | S | Extends open C2-restore-command.md:123 and judge-verdict.md:63 |
| 8 | kalloc ratchet: root capture at 4 GB, planned reboot at 6 GB, file the Apple feedback, longer timeout for the alarm's zprint probe | MEASURED: 3.40 GiB, growing 0.84-1.0 GiB/day. ESTIMATED: warn level in about 0.7 days, alarm in about 3. A planned reboot with restore replaces an unplanned one | operator-only | S | Extends open kalloc-ratchet-2026-10.md §6 (capture staged, never run) |
| 9 | Batch QoS PATH shim `bin/cc-qos-exec` (utility band), plus deny-with-reason for compound lines the shim cannot reach, plus a wider qos-census pattern | MEASURED: demoted share is 3.8-4.3% of CPU, and batch work was 2-3 cores at the snapshot peak (typical load is lower; not quantified). INFERRED: that CPU drops from PRI 26-31 to PRI 20, behind the sessions. No CPU is removed, and batch runs about 2.4x slower (repo-measured) | agent-drivable | M | Regression of landed §11.3 M7 (inert for everything except bats). Extends the M1 cc-bats shim. The §9.4 ceiling applies (absolute paths bypass a PATH shim) |
| 10 | Put agent-browser behind the same shim and verify its helpers land at PRI 20 | MEASURED: one tree uses 1.5-1.7 cores at PRI 47 (roots at 55), against claude at 31. INFERRED and unverified: that a process clamp also caps Chrome's own thread priority | agent-drivable | M | NEW |
| 11 | Spin guard round 2: exempt trees that are in use, then widen the re-check; add a detection-only TREE-SPIN check | MEASURED: 0 kills across 12 spin ticks (65 REFUSED lifetime). A 1.5-core tree whose members each stay under 80% is logged as "clean" | agent-drivable | M | Defect in the landed guard. The tree check extends browser-tree-aggregation-2026-09-09.md, which measures only |
| 12 | kitty: merge w3-p6, swap in the patched build at a planned restart, relaunch with `ulimit -n 8192` | Removes the failure class behind the 10-01 outage (32 sessions, about 2.5 h of restore; from the record). Clears 187 zombies and about 1.5 GB of kitty RSS. Outage probability is not quantified | operator-only (merge is agent-drivable) | M | Extends open W3-build-plan.md P6 and C3 P1, which the judge dropped. Coordinate with W3 owner b7ce699affec |
| 13 | Stop chain: find out why session-continue sits at its 5 s timeout; raise its timeout to the measured p90; consider making operator-readout async | MEASURED: turn-end p50 7.9 s, p90 10.6 s. session-continue times out on 65% of Stops, operator-readout on 38%. The number of continuation blocks lost is not measured | agent-drivable (settings.json part is operator-only) | M | Extends A01-stop-hook-timeout-decay-2026-09-08 and §12.7.6 item 3 |
| 14 | `teammate-checkpoint.sh`: seed the temp index from the real one, skip the commit when the tree is unchanged, add `/out/` to `.gitignore`, cap large untracked files | MEASURED: one reso session stalls 4-6 s on every 5th tool call and at every Stop (about 104 snapshots/h). ESTIMATED: about 0.035 core. Also stops about 100 duplicate refs/h and new media blobs (713 MiB is held by checkpoint refs now) | agent-drivable | S | NEW. git-maint.md F6 covered ref count only |
| 15 | `lead-supervisor.sh` `assess()`: one jq read with a `\x1f` separator instead of six | MEASURED: sweeps take 10-19 min against a 30 s interval, so stall and crash detection lags by 10-19 min. ESTIMATED: about 380 fewer forks per sweep | agent-drivable | S | NEW. Same anti-pattern as HOOK_CHAIN_COST.md §2.5, which was fixed for hooks only |
| 16 | Stop the stale bg job 9aa483e9; add a check for done, idle and unattached bg jobs older than 8 h | MEASURED: 0.55 GB and 6 processes | operator-only (check is agent-drivable) | S | Extends open C5-cc-native-bg-sessions.md:321 ("Do now"). 5cd333f16 prevents new cases only |
| 17 | capacity-alarm: add idle_pct and spawns_per_s; make the load_per_core rung display-only | MEASURED: 175 of the last 300 rows say ALARM on load alone. Ends alarm fatigue | agent-drivable | S | Extends the landed max-load-per-core-derivation-2026-08-25 |
| 18 | Hook hygiene: the parity bats sees every matcher that fires on Bash; a bash pre-check before python in `bash-output-offload.sh` | MEASURED: 20 hooks per Bash call, 6 of them invisible to the drift guard. INFERRED: one fewer python start per Bash call | agent-drivable | M | Extends the landed readjudication-2026-09-08 drift guard (it matches Bash-only) |
| 19 | Claude Code 2.1.289: capture the pane tail on abnormal close first, then stage it and run cc-upgrade-gate | Unproven. MEASURED: 0 "interface error" exits in 1635 close records. The upstream fixes target fullscreen sessions on busy machines | upstream + operator-only (pin) | M | Extends the MANIFEST.jsonl audit (2.1.285-289 open) |
| 20 | Global git config: `pack.threads 3`, `pack.windowMemory 256m`; finish the reso F3 un-enroll | ESTIMATED: caps a roughly weekly full repack of a 1.1 GB pack. CPU cost not measured | operator-only | S | Extends open git-maint.md F4 and F3 |
| 21 | `validate-bash.sh` advisory for `git log -S/-G` with `--all` or no pathspec | ESTIMATED: about 0.3-0.4 expensive runs/h. MEASURED per run: 400 MB-1 GB RSS, 16-60+ s | agent-drivable | S | NEW |
| 22 | Heavy-batch semaphore (cc-ignition-gate pattern) | Only if contention remains after #9. A blocking wait is itself lag | agent-drivable | M | NEW. Must follow §9.4/R1: defer with a re-run command, never queue-or-sleep |
| 23 | Low-value hygiene, do when convenient (list after the table) | Each under about 0.1 core or diagnostic only | mixed | S | Various |

Items in row 23:
- Drop `| tr | sed` from the lead-crash-watchdog lstart check.
- Retire duplicate mailbox armers.
- Count claimed bg workers correctly in the spawn-presence census.
- Make crash-ledger jetsam attribution match on the dead session's pid.
- Build the fseventsd §8.4 detector.
- Run worktree-gc `--warrant` on the 21 unowned trees.
- Add jetsam-lane to reso `dev`, `typecheck` and `test:e2e`.
- Switch the personal `.mcp.json` ms365 entry to the direct binary.

## 3. Top remedies in detail

**1. research-block fast exit.**
- **Change:** in `hooks/research-block.sh`, read `[.cwd,.session_id]|@tsv` in the existing jq call. After `rp_resolve_cwd`, exit 0 when there is no program slug and no `${CC_RESEARCH_HOME:-$HOME/.claude/autonomy/research}/route-state/<sid>.json`. The sid sanitizing must match `router.py` `route_path` exactly: `[^A-Za-z0-9_.-]`→`_`, cut at 128 characters, `unknown` default. Add a bats case asserting that python3 is not run.
- **Evidence:** `programs.json` exists with one "registered" program, so the header's early exit never fires. `route-state/` does not exist, and `cmd_tool` returns 0 in exactly this case.
- **Risk:** low, because the decision is unchanged. A test should pin the sanitizer so it cannot drift from router.py.

**2. Byte-wise stdin reads.**
- **Change:** in `hooks/post-tool-batch.sh`, let jq read stdin directly (`ROW="$(jq -c '…')"`). Then make the same change in `teammate-checkpoint.sh:77`, `memory-index-drain.sh:53` and `bash-output-offload.sh`. For `log-bash.sh:15` and `validate-bash.sh:24`, log payload byte counts first.
- **Evidence:** `IFS= read -r -d ''` on a pipe makes one syscall per byte: 400 KB takes 1.98 s and 1 MB takes 2.74 s, against 0.05 s with cat (MEASURED). post-tool-batch is cancelled at p50 11.3 s against its 10 s budget.
- **Risk:** one extra fork per hook, which is what §12.7.3 saved. Keep the builtin read where payloads stay small.

**3. render.mjs.**
- **Change:** in all 5 copies under `~/Development/personal/launch-film-2026`:
  - Add a `mkdir`/`shlock` lock so only one render runs at a time.
  - Launch Chrome through `/usr/sbin/taskpolicy -c utility`. Do not use background, which is 84-89x slower.
  - Move the spawn and handshake (lines 41-74) inside `try`, and add SIGINT/SIGTERM/SIGHUP handlers that SIGKILL Chrome. Better still, use `--remote-debugging-pipe`.
  - Leave the Metal A/B until later. It needs pixel parity, `chrome://gpu` showing Metal, and a GPU utilization check, because the GPU is already at 56-58%.
- **Evidence:** every automation GPU process runs SwiftShader. There are 0 `process.on(` calls in any copy, and 17 leaked profile directories (72 MB).
- **Risk:** renders get slower. The utility tax is not measured for renders.

**4. Spin-guard close-all.**
- **Change:** in `scripts/browser-spin-guard.sh:301-303`, log every close and replace `close --all` with a per-session close. Walk from the pegged process to its root, then to the root's parent. Only if that parent is `agent-browser-darwin-arm64`, read `AGENT_BROWSER_SESSION` with `ps -E -ww` and run `agent-browser --session <name> close`. Extend `tests/browser-spin-guard.bats`.
- **Evidence:** close-all runs unlogged on every SPIN tick in `--reap` mode. All 9 live daemons were started right after the 05:35:41Z tick.
- **Risk:** low, since it narrows the blast radius. It is still kill-path code and needs review. Do not widen the REFUSED check in this step (see #11).

**5. agent-browser idle timeout.**
- **Change:** add `"AGENT_BROWSER_IDLE_TIMEOUT_MS": "1800000"` to `env` in `~/.claude/settings.json`; the other account files symlink to it. Add to the agent-browser skill: "one named session per task; close tabs when done; no more than 2 animated tabs".
- **Evidence:** vendor README:1224. No settings file sets it. Several trees are parked on recaptcha or Cloudflare pages.
- **Risk:** logged-in and challenge-solved state is lost after 30 minutes idle (15 minutes is too short). It applies only to daemons started after the change.

**6. launchd bands.**
- **Change:** edit the repo copies under `launchd/`, then the operator reloads:
  - capacity-alarm and qos-census: ProcessType Standard, keep LowPriorityIO.
  - deploy-live and worktree-gc-infra: drop Background and exec through `taskpolicy -c utility` with a fail-open fallback, following `postland-verify.plist:37-66`.
  - load-sampler, lr-reconciler and lr-reconciler-watchdog: Background plus LowPriorityIO. Move the watchdog from 30 s to 120 s if its SLA allows.
  - compressor-sentinel and lead-supervisor: Adaptive or utility, never Background.
- **Evidence:** capacity-alarm runs at PRI 4 even though it is set to Adaptive. deploy-live ran 1h50m on 0.09 s of CPU while three more deploy-live runs waited on its lock. Every agent-drivable fix here depends on deploy-live reaching the fleet (§12.7.7). The live checkout is at 008330afe from 01:07 CDT, so it is current but slow.
- **Risk:** these jobs take a little more CPU from sessions, and worktree-gc's long runs will burn real CPU.

**7. boot-resume `.start`.**
- **Change:** `scripts/boot-resume.sh:333` becomes `st="$(head -1 "${f%.roster.json}.start" | tr -d '[:space:]')"`. `alarm-reboot-prep.sh:52` writes to `reboot-$DAY.kalloc` instead. Add a two-line `.start` bats case and update `alarm-reboot-prep.bats:27`.
- **Evidence:** `reboot-2026-10-01.start` has two lines, so whitespace stripping produces non-digits and the roster is skipped. The existing tests only write one line.
- **Risk:** low.

**8. kalloc ratchet.**
- **Change:**
  - At 4 GB, run `~/.claude/autonomy/kalloc-root-capture.cmd`.
  - File `docs/research/apple-feedback-compressor-panic-draft.md`.
  - Reboot when the 6 GB alarm fires, in the same window as #12.
  - Give the alarm's zprint probe a longer bounded timeout, because the latest row reads `src=timeout`.
- **Evidence:** 1.12 GB on Oct 1 at 18:07Z, 1.85 GB on Oct 2 at 06:19Z, 3.40 GiB now.
- **Risk:** the reboot ends all sessions. It is only cheap once #7 lands.

**9. Batch QoS shim.**
- **Change:**
  - Write `bin/cc-qos-exec`, modelled on `bin/cc-bats`. It walks PATH skipping its own directory, runs `exec /usr/sbin/taskpolicy -c utility <real> "$@"`, falls back to running the command unchanged on any error, and demotes only inside Claude sessions (an env guard such as `CLAUDECODE`).
  - Link it into `~/.claude/bin` as magick, convert, ffmpeg, ffprobe, tesseract, yt-dlp, shellcheck and pytest. Not tsc (it is reached through `node_modules/.bin`), node, python3, git or claude.
  - For compound lines that carry a batch step the shim cannot reach (`xargs -P`, `pnpm|npx tsx`), return deny-with-reason telling the agent to prefix that step with `taskpolicy -c utility`.
  - Widen `QOS_CENSUS_PATTERN`, and add a read-only alarm for any claude descendant tree outside PRI 4 that uses more than 1 core of child CPU for 60 s.
- **Evidence:** `qos-rewrite.sh:305` exits on any compound metacharacter. `~/.claude/bin` is first on PATH, and cc-bats gives 100% bats coverage. A live `xargs shellcheck` ran at PRI 31 with 980 MB for 16 minutes.
- **Risk:** absolute paths bypass the shim (§9.4 measured about 30% for bats), and batch work runs about 2.4x slower. Do not wrap whole compounds in `zsh -c`, which breaks snapshot functions and cd tracking.

**10. agent-browser through the shim.**
- **Change:** add an `agent-browser` link. Check `ps -o pri=` on a fresh daemon's helpers (expect 20, not 47). Optionally print the live daemon list when 4 or more are running.
- **Evidence:** Chrome helpers run at PRI 47 and roots at 55, above every session.
- **Risk:** it is unverified whether the clamp caps Chrome's own thread priority. All 537 logged CLI calls would pay the utility spawn cost, and screenshot and video work would slow down. Do this after #9 proves out.

**11. Spin guard round 2.**
- **Change:**
  - First, exempt any tree whose root's parent is a live process other than launchd, or whose CDP port has an ESTABLISHED client.
  - Then accept chrome-headless-shell in the re-check, matched by lstart and ancestry.
  - Only after that, consider killing roots.
  - Add `TREE-SPIN` (tree sum at or above 150% for 2 ticks) as detection-only until calibrated (browser-tree-aggregation-2026-09-09.md:126-137).
  - An orphan arm can follow as detection-only.
- **Evidence:** 65 REFUSED, all chrome-headless-shell. 7 KILLED against 100 SPIN lines over the guard's lifetime.
- **Risk:** widening the check without the exemption would SIGKILL legitimate film renders every 5 minutes. Today the bug happens to protect them.

**12. kitty.**
- **Change:**
  - Land branch w3-p6 (716322ed5: the talk-thread patch plus `kitty-build-swap.sh --no-band`) after checking with W3 owner b7ce699affec.
  - At the planned restart, run `scripts/kitty-build-swap.sh stage --no-band`, then swap and verify. Relaunch with `ulimit -n 8192`, plan on SIGKILL, and follow kitty-quit-research-2026-10-01.md §5.
  - The detector should be a timed `kitten @ ls` plus a Recv-Q check, not the zombie count.
- **Evidence:** zombies have accumulated since kitty's launch second on 0.48.2. The patch carries the `signal_write_fd` hunk and the accept_peer fix, and the build at `~/ktb-noband` contains "still serving". The 0.49 cask fixes signals but not the talk thread.
- **Risk:** the restart ends all 20 panes.

**13. Stop chain.**
- **Change:**
  - Profile session-continue's no-sentinel path (`session-continue.sh:1245-1263`). Look at the wrap-ledger single-flight wait of up to 750 ms (`wrap-ledger.sh:459`) and the ps ancestry walk.
  - As a stopgap, raise its timeout to about 6 s (p90).
  - Make operator-readout async only after confirming 2.1.284 supports the flag.
- **Evidence:** 190 Stops. session-continue's p50 is 5047 ms, which equals its timeout, with 123 timeouts.
- **Risk:** a longer timeout trades turn-end latency for the gate actually running. Collapsing the five hooks into `hook-chain.sh` is not ready: it cannot merge Stop output, and exec mode did not pay.

## 4. Refuted or weakened by the skeptics (do not re-chase)

**Snapshot premises that were wrong:**
- The "1 GB idle bg-spare" (87268) is the operator's live, attached session (job 032aa97f). Do not stop or reap it.
- 1825 processes is not close to any limit: 1393-1502 of 10666 per uid.

**Refuted:**
- cc-jetsam-exec "unadopted". It is wired into reso build, design:gate and test:unit (8de25e414) with 31 capped runs. Only dev, typecheck and test:e2e are left.
- session-search-sweep "wedged, log growing". The log was last written Sep 27. The slow run is starvation in the Background band.

**Rejected remedies:**
- Wrapping whole compound commands in `taskpolicy … zsh -c`. It breaks the shell snapshot and cd tracking, and repeats a design that was already rejected.
- `-c background` for batch work: an 84-89x tax.
- Background ProcessType for lead-supervisor or compressor-sentinel. Background starves safety sensors at this load.
- `IFS=$'\t' read` for the lead-supervisor collapse. Empty fields shift; use `\x1f`.
- Running the watchdog's lstart check only every 10th tick. The pid space wraps in about 2 minutes.
- Widening the spin-guard re-check or killing roots before adding the exemption (it would kill renders).
- Removing `git status` from operator-readout's cheap_stamp (it is there by design). Collapsing the Stop hooks into hook-chain.sh now.
- A `( … ) &` fallback for post-tool-batch. The slow part is the stdin read, which happens before it.
- A `| head -1` pre-check in teammate-checkpoint. It already has a pre-check, and that shape has a SIGPIPE bug.
- `gc.bigPackThreshold`. git 2.54 already repacks geometrically.
- Zombie-count alerts for kitty. They fire nonstop on any stock 0.48.2.
- ZSH guards for gitstatusd. The owners are interactive shells, so change nothing.

**Overstated numbers:**
- "2.2 cores of process-lifecycle overhead": extrapolated from load 16.
- "Nice 5 demotes": it does nothing on Darwin.
- Render bursts "sustained 5.9-8.9 cores": the real range was 1.4-8.9 cores.
- The 11 leaked render trees are already gone.
- agent-browser trees are idle tabs of live sessions, not leaks from dead ones.
- The `&`-launched Chromes' owner is probably still alive.
- "Over 100 sessions by memory": interactive RSS averages about 560 MB plus satellites.
- "2-3 hidden bg sessions resident": only 9aa483e9 is stale.
- The census bias has about zero effect against the ceiling of 54.
- "AC6 regressed": a min-of-3 at low load is not comparable to a p50 at load 200.
- The 650 CPU-s/h checkpoint cost is about 120-130.
- Media is "permanent": only about 209 MiB is pinned; the rest ages out around Oct 9-12.
- The pickaxe rate: the expensive class is about 0.3-0.4/h, and the swap link is unsupported.
- The fseventsd livelock: the current rate is a healthy 4%.

**Shaky signals and impacts:**
- The spawn-latency trigger. It read 3.5/6.5 ms against 13.6/23.8 ms at the same 0% idle, so keep it display-only.
- The "30-40 panes" kitty fd ceiling. EMFILE as the cause of 10-01 was downgraded to 45% or less, so it is not binding at 20 panes.
- The heavy-batch semaphore's "1-1.5 cores". Unsupported, and a 120 s wait is itself lag.
- kalloc as "the only crash path, with a 9.9 GB tripwire". The prior boot survived 14.2 GB; the zone makes a compressor storm worse but is not the trigger.
- The boot-resume bug as "all sessions lost". The tombstone fallback exists; the loss is in fidelity.
- Claude 2.1.289 as the crash fix. There are no local cases of that error.

**Confirmed: no change needed:**
- Claude process tuning (NODE_OPTIONS, BUN_GC_*), the statusline, and the MCP satellites.
- Kernel and launchd limits.
- kitty render config. kitty plus WindowServer use about 0.4 core, and WindowServer load comes partly from kitty's visible windows, not from headless Chrome.

## 5. Sequencing

**Wave 1, now (1-2 days), all S:**
- Agent: #1, #2, #4, #7, #14 and #15, plus #3 in the launch-film repo and the skill text from #5.
- Operator: #6 first, so deploy-live stops starving and the agent fixes reach the fleet. Then #5, #16, and #8 (the capture when the zone crosses 4 GB, about a day out).
- Exit check: hook timeouts counted from transcripts, capacity-alarm rows per hour, and render CPU on the next burst.

**Wave 2, this week (M, measured before and after):**
- #9 (shim plus deny-with-reason), then #10 with the PRI check, #11, #13, #17 and #18.
- Re-measure the demoted CPU share, idle %, and PreToolUse and Stop p50/p90.
- Decide on #22 only if contention persists after #9.

**Wave 3, one planned restart window at the 6 GB kalloc alarm (about Oct 7):**
- Needs #7 landed and w3-p6 merged first.
- In that window: take the kalloc capture, swap the patched kitty with `ulimit -n 8192`, reboot, and restore through boot-resume.
- Afterwards: #19 if the pane-tail capture shows interface-error exits; #20 and the hygiene items in row 23 whenever convenient.