<!-- source: /Users/chrisren/.claude-secondary/projects/-Users-chrisren-Development-claude-infrastructure/5d384543-c553-4250-b772-43466507e81c.jsonl
 turns=79 assistant_texts=13 last_stop=end_turn mail_injections=['PREMISE CORRECTION', 'PATH FIX'] -->

SendMessage isn't available in this subagent context (known constraint — bg subagents return via transcript, not messaging). Emitting my final report as the return payload for the lead to harvest.

---

# Crash/memory pool — post-correction residue (read-only, verified this session)

**Headline the brief didn't have:** there are **THREE** docs, not two. A newer forensics doc supersedes BOTH — `docs/research/session-crash-forensics-2026-07-23.md` (branch `docs/crash-forensics-2026-07-23` @ 31c7cb4; worktree `/private/tmp/wt-crash-forensics`) plus its desk-memory second-correction (`session-crash-per-session-bloat.md:11-28`). It refutes the branch doc's version-regression as **~92% teardown-confound artifact**. I **independently re-verified its core claims this session** (empirical, below) — it holds.

The chain: **MAIN** (ef7f7a4, per-session bloat→OOM) → **BRANCH** `feat/handoff-memory-review` (bd2471b, 2.1.207+ version regression, pin-to-183) → **FORENSICS** (31c7cb4, both wrong: 0 real crashes, signal-integrity is the actual bug). Forensics = SSOT.

## (a) Causal-story reconciliation

| Claim | MAIN-doc | BRANCH-doc | FORENSICS + my live verdict |
|---|---|---|---|
| **Crash mechanism** | per-session bloat → per-process OOM | CC **version regression** 2.1.207+ (4.76%) | **Neither.** Mostly **teardown-confound**: `self-close`/`--recycle` SIGKILL the pane mid-Bash → `tool_result` never lands → forges crash signature. Organic rate **0.24% flat** across 207/215 (forensics Part 2). Real crashes exist but ~20× rarer than branch; tonight = 0. |
| **Two 60MB "OOM crashers"** (000ff296, 1a705246) | flagship OOM evidence | (size demoted) | **REFUTED at source (my check):** both end `stop=end_turn` — 000ff296 thinking+text end_turn @16,963 lines; 1a705246 text end_turn @27,105 lines. Neither died mid-anything. `suspected-oom-large-context` was assigned *purely by the >4MB size heuristic*, not death evidence. |
| **520MB-RSS / 100%-ctx-never-crashed paradox** | unexplained | dissolved by version story | Dissolved by teardown story: jetsam-zero, `mem_free` ~87-88%, no OOM (my ledger read confirms 87-88% every row). |
| **"Pin CC to 2.1.183"** | n/a | primary lever | **WITHDRAWN.** Basis (4.76%) is the artifact; launcher attribution INVERTED. |
| **Launcher map** | n/a | "interactive `claude` auto-updates to 2.1.215; `claude-next*` pin 2.1.183" | **Both halves inverted (live check):** stable `claude`/`cc` → `current`=**2.1.114** (user-pinned 2026-06-19; MANIFEST `skip` on 215; `DISABLE_AUTOUPDATER=1`). Eval `claude-next*`/`claude-fable*` → `.zshrc:387` → `~/.claude-183/` which **contains 2.1.215** (deliberate advance; dir name lies). |
| **93% "LEAD CRASH" false signal** | conflation named | root fix: `session-end.sh` reaps pidfile | **Stands + now DEPLOYED** (live `session-end.sh:28-30,42-48`; origin/main=fe52c1f 0-behind). Does NOT cover self-close (SIGKILL skips SessionEnd) → teardown-marker fix needed (unlanded). |
| **State-store "leaks"** | not covered | Part 2 (cp-count 1941, pid 83, logs 92MB) | **Stands + extended** (watchdog 2,170; logs 94MB@+2/day; session-index.db 45MB; refs 1,853@+47/day). Inode/byte growth — NOT the crash. |
| **`/handoff` watchers leak?** | n/a | bounded+self-terminating | **Stands.** Machine-wide = **2 leaked procs**. Not the OOM source. |

**Still load-bearing from MAIN:** only the *conflation diagnosis* + *stderr-gap framing* survive (both actioned). OOM root cause + size-blind-recycle "primary lever" **fully superseded** (size predicts nothing; recycle-on-size demoted to defense-in-depth). **Still load-bearing from BRANCH:** deployed root fixes, telemetry schema, accumulation inventory, Part-3 launcher-truth. **Dead from BRANCH:** Part-5 version rates, "Open decisions #1" pin, claim A4 (refuted by its own Part 3).

## (b) Residue table — UNSOLVED now

| Unsolved item | Evidence (this session) | Partial mitigation | Gap |
|---|---|---|---|
| **Self-close still forges false crashes** | 04eb0a05 tail = unpaired Bash `handoff-fire self-close --terminal`, 680 lines=ledger; live watchdog **0** teardown-marker refs | SessionEnd reap (deployed, clean-exit only) | teardown-marker built on `fix/teardown-marker-fire`(9c0ac91)+`fix/watchdog-classify-marker`(48fbe83) **UNLANDED** |
| **Ledger attributes nothing** | 33/33 `abrupt-unknown`, **0** carry `claude_version` though field is live (watchdog has 2 refs) | version+stderr fields deployed (4d7dd2f) | **stale in-memory daemons** (pre-4d7dd2f) → won't populate until supervisor cycled (operator step 3, not done) |
| **Eval-track forensic blind spot** | tee in `claude-latest:374`; `.zshrc:387` bypasses wrapper → 2.1.215 uncaptured; `concurrent_claude` greps `[c]laude.exe`→0 of eval procs | capture live for *safe* 2.1.114 track only | the artifact that names real crashes watches the ~zero-crash track |
| **Pin sustainability = actually robust** (brief's re-break hypothesis is FALSE) | `current`→2.1.114; MANIFEST 215=`skip`; `DISABLE_AUTOUPDATER=1`; eval=manual npm | default-deny + smoke-test + record-version | no auto-update re-breaks it; residual = `~/.claude-183` name lies (human trap) |
| **No honest per-version crash SLO/canary** | smoke-test TEST-3 greps `doctor` only; C-DSH-2 unbuilt | MANIFEST manual review | version scare happened *because* no teardown-excluded telemetry; C-DSH-2 is a frontier hole |
| **Message-loss races at recovery** | unlocked JSON-array RMW (`lead-crash-watchdog.sh:272-279` vs `team-orphan-reaper.sh:97-106`); ack-on-surface drain | none live | `fix/mail-ack-consume`(74b9c29) **built, unlanded** |
| **Unowned state stores** | watchdog 2,170; logs 94MB@+2/day; db 45MB; refs 1,853@+47/day | per-session reap (forward) | no owner/TTL; `cc-reaper` skips watchdog dir; 9 logs unrotated |
| **Pid-identity hazard** | `kill -0`-only; pids reused up to 5×; 3,274 spawns/3,110 sids; arms ephemeral subagents 73% | rm-race guard landed (4d7dd2f) | frequency-backed hazard (0 active zombies); needs identity=pid+lstart |

## (c) Ledger quantification — `~/.claude/logs/claude-crashes.jsonl` (33 rows)

- **All 2026-07-23 06:42–08:55Z. 100% `class:CRASH`, 100% `cause:abrupt-unknown`, 0% `claude_version`, 0% jetsam, 0% large-context.** `mem_free_pct`=**87-88% every row**. `transcript_kb` 205–2266 (median ~500, small).
- **Cluster A** rows 1-16 (06:42-53) `concurrent_claude` **14→0 monotone** = reliability-audit fan-out (lead 5aef2d9d, never crashed). Row-1 eeb03471 **verified: `stop=end_turn`, 78 records=ledger** = orderly completion. **Row 17** = verifier. **Rows 18-19** = orderly close + **04eb0a05 self-close `--terminal`**. **Cluster B** rows 20-30 (08:13-23) `concurrent_claude` **10→0** = 2nd wave. Rows 31-33 = stragglers.
- **Verdict:** live data supports **neither** version-regression (no version field) **nor** OOM (87-88% free, sub-MB). Consistent **only** with forensics teardown+completion. **Conflation bound TOTAL: 100% `abrupt-unknown`.** The "19-crash storm" = **0 real crashes**.
- **Empirical vs theoretical:** (c) + the 4 sid classifications + launcher/pin/deploy facts = **empirical (this session)**. The 8,489-transcript census (0.24% flat, Fisher p≈0.004-0.008, 96/104 teardown) = **forensics-doc; I spot-corroborated 4 sids + method, not full census**. SessionEnd-on-interrupt-`/exit` = **THEORETICAL** (marker makes it moot).

## (d) CANDIDATE FRONTIER PROBLEMS

**CFP-1 — Surface-state liveness monitors forge false positives at teardown ("the monitor is the malfunction")**
- **Evidence:** forensics Part 1 (3-generation cascade: wave completions→16 pages→spawn investigator→its self-close→17th page→spawn *this* investigation); my check: eeb03471 `end_turn`→CRASH, 04eb0a05 self-close→CRASH.
- **Mechanism class:** liveness inferred from *surface state* (pidfile presence, dangling `tool_result`, prose-grep) not *durable identity/intent*.
- **Mitigations + status:** SessionEnd reap (deployed, clean-exit only); teardown-marker (built, 2 branches, **UNLANDED**); prose `classify_death` (deployed but *missed 04eb0a05, the session that wrote the prose*).
- **Why it resists:** point-fixing each teardown path loses to the next; prose list unbounded. Needs deterministic intent-marker written *before* the kill.
- **Cost:** 3 investigation generations + ≥2 research waves + operator false-page in one night; ~92% of the branch headline was this artifact.
- **Frontier-fix:** teardown-marker contract (built); generalize the invariant — "no monitor may infer death from a state a sanctioned actor can also produce."
- **Confidence + stale-risk:** HIGH diagnosis. **Stale-risk HIGH within days** — 3 fix branches may land, flipping open→closed. Re-check branch-landed state.

**CFP-2 — Registered-state-family + durable-identity contract (generator behind leaks + pid-attribution)**
- **Evidence:** forensics #7 (3,274 spawns/3,110 sids, pids reused 5×, 73% ephemeral-subagent registrations) + #10 (watchdog 2,170 · logs 94MB@+2/day · db 45MB · refs 1,853@+47/day) + branch Part-7 campaign candidate.
- **Mechanism class:** keyed per-session state minted with **no enumerated owner/key-epoch/TTL/identity** → no sweeper can safely GC; `kill -0` confuses reused pids.
- **Mitigations + status:** per-session reap (forward-only); rm-race guard (landed); backlog sweep + log-rotation-broaden (surfaced, unbuilt); `cc-reaper` skips watchdog dir.
- **Why it resists:** ~10 independent producers over months with ad-hoc keys; global sweeper can't know which files are live without a contract → every point-GC risks disarming a live session (the rm-race bug).
- **Cost:** ~94MB+2MB/day logs + 45MB db + thousands of entries/refs; unmeasured pid-reuse misfire frequency.
- **Frontier-fix:** one manifest `(glob, key-epoch, TTL, owner)` per producer, one identity-pinned (pid+lstart) sweeper; dissolves cp-count/pid/watchdog/mailbox/refs GC + idl-seal deadlock → `/frontier-campaign`.
- **Confidence + stale-risk:** HIGH right generalization; MEDIUM frontier-hard-vs-tedious. Stale-risk LOW.

**CFP-3 — No honest per-version organic-crash telemetry → version scares unfalsifiable**
- **Evidence:** branch 4.76% (→pin) was 92% artifact; smoke-test.sh TEST-3 greps `doctor` substrings only; C-DSH-2 (`FRONTIER_HOLES.md`) `/exit` conformance test **unbuilt**.
- **Mechanism class:** version safety gated by *functional* smoke-tests + human review, but organic-death has **no per-version signal** excluding teardowns.
- **Mitigations + status:** MANIFEST default-deny (robust); smoke-test (functional); `claude_version` field (deployed, **unpopulated** — stale daemons + eval bypass).
- **Why it resists:** "organic crash" not distinguishable from ⌘W/subprocess/sleep without stderr on the *right track* — and the right track (eval 2.1.215) is the uninstrumented one.
- **Cost:** one wrong pin recommendation + "still broken" claim on 2.1.215; every future bump re-litigates blind.
- **Frontier-fix:** (1) route eval `claude-next*` through instrumented wrapper; (2) teardown-excluded crash-rate-by-version SLO; (3) build C-DSH-2 canary per bump.
- **Confidence + stale-risk:** HIGH. Stale-risk LOW.

**CFP-4 — Forensic instrumentation points at the safe track (observability topology inversion)**
- **Evidence:** `claude-latest:374` tees stderr; `.zshrc:387` eval bypasses → 2.1.215 uncaptured; `concurrent_claude` greps `[c]laude.exe`→0 of eval procs (`n_claude=0` while 8 ran).
- **Mechanism class:** capture attached to the *wrapper* (stable, ~zero-crash) while the *active* track runs a different exec path — coverage anti-correlated with risk.
- **Mitigations + status:** capture live only on `claude-latest`; no eval-track capture even post-deploy (forensics #8, operator decision #3).
- **Why it resists:** eval track deliberately bypasses wrapper for launch-arg control (`--model`/`--effort`/config-dir); re-routing risks those semantics — operator-owned dotfile call.
- **Cost:** unmeasured — every real eval-track crash named nothing (0 stderr artifacts). Measure: eval-track abnormal-ends with attached stderr (currently 0/all).
- **Frontier-fix:** unify launch through one instrumented entrypoint parameterized by track; fix `concurrent_claude` to count both exec paths.
- **Confidence + stale-risk:** HIGH. Stale-risk LOW.

---

**Blockers/uncertainties:** (1) 3 fix branches are built+tested but **unlanded** — CFP-1 flips to closed if they land; re-check before synthesis. (2) Did not re-run the 8,489-transcript census (spot-corroborated 4 sids). (3) A 4th landed doc composes: `infra-reliability-audit-2026-07-22/` (e78d31d, 15-agent wave, ~90 defects, 4 root causes) — forensics says its root-cause-1 (last-mile activation gap) + root-cause-4 (unguarded hot paths) are the operative reliability problems; **not opened (out of my pool — flagging for coverage)**. (4) Deploy moved *since* forensics was written (it says "11 behind"; now 0-behind, reap deployed) → operator steps 1-2 appear done, step 3 (cycle supervisor) not yet (version field still unpopulated).