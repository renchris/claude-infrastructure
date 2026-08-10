# 12 — Felt lag: what the operator actually waits on, and whether it forecasts the crash

**Date:** 2026-08-09 · **Scope:** operator-felt latency (keystroke→echo, prompt→first token, mid-turn
stalls, turn-end) attributed to the fleet's own synchronous hook chains vs system load vs the
pre-crash ramp. **Recommend-only — nothing in the live config was changed.**

## Verdict (three sentences)

1. **The dominant felt-lag item is turn-end, and it is 92% one line of shell**: the Stop chain costs
   the operator **3,684 ms at p50 / 7,712 ms at p90** (n=1,668 live Stop events, 7 days), of which
   `operator-readout.sh` is **3,611 ms p50**, and that is almost entirely one
   `cc-backlog list --blocked --json` (**4,200 ms measured standalone**) folding a 7,046-line /
   2.1 MB append-only JSONL with 60 `jq` invocations.
2. **Chronic felt lag and acute pre-crash lag are DIFFERENT MECHANISMS**, separated with zero overlap
   over 47,108 sentinel samples: whole-machine stall (`el ≥ 20 s`) occurred **91 times ever and
   91/91 during a compressor-segment ramp — 0 times under load alone**, including a control measured
   during this investigation at **load 53.64 with 0.0% idle**, where the stall metric never exceeded 13.
3. **Felt lag is not an early warning for the ramp — it is the ramp's first human-perceptible
   symptom**, arriving ~13 s after the segment rate breaks out and **~4.5 minutes before death**; the
   earlier warning already exists and is `srate` (the sentinel's own trip), not anything the operator
   can feel.

---

## 1. Execution model — hooks run in PARALLEL (corrects a standing repo premise)

Per-event felt cost is **max(hook)**, not sum. CPU burned is sum.

**Measured, this session** (0.2 s-interval `ps` sampler over 249 snapshots, grouping hook processes by
claude.exe PPID; scratch script, no config touched):

| t | PPID | n | hooks resident in ONE snapshot |
|---|---|---|---|
| 3142.43 | 56864 | 5 | git-worktree-guard · keychain-guard · rm-safe-allowlist · ship-rail-push-allow · validate-bash (**PreToolUse[Bash]**) |
| 3116.13 | 56864 | 6 | boundary-handoff · completion-assert · dispatch-assert · operator-readout · session-continue · teammate-checkpoint (**Stop**) |
| 3156.77 | 88196 | 8 | activation-watch · config-mirror-assert · mailbox-drain · mcp-auth-guard · pre-session-validate · session-start · setup-plan-symlinks · setup-task-symlinks (**SessionStart**) |
| 3124.09 | 52822 | 4 | cc-permission-beacon · log-bash · mailbox-drain · teammate-checkpoint (**PostToolUse — spans TWO matcher groups**) |

Corroborated by the vendor doc (`https://code.claude.com/docs/en/hooks`): *"All matching hooks run in
parallel. If you define the same handler in more than one settings file, it runs once."*

🚨 **`hooks/hook-chain.sh:8-13` models this chain as SERIAL** ("PreToolUse/Bash 6 processes 232 ms …
total per Bash tool call: 8 processes, 368 ms"). That premise is false, and it inverts the file's own
conclusion: its MEASURED OUTCOME block found the collapse "does not pay" — the stronger statement is
that **collapsing a parallel chain into one sequential process converts max() into sum()**, which on
the Stop chain would take the felt cost from 3,684 ms to 7,657 ms (p50). Recommend annotating that
header; the dispatcher is correctly not wired up, for a better reason than the one recorded.

## 2. The felt-latency budget

Method note on evidence class: **Stop is OBSERVED live** — CC writes a `stop_hook_summary` record with
`hookInfos[].durationMs` into every transcript. No such record exists for UserPromptSubmit /
PreToolUse / PostToolUse (verified: 646 transcript files, 7 days, 1,668 hook-summary records, subtype
histogram = `{stop_hook_summary: 1668}` only). Those three rows are therefore **REPLAYED** in a scratch
dir against fixture stdin, one hook at a time — a **lower bound**, because live they run concurrently
and contend. Measured inflation factor on the one chain where both numbers exist: replay max 508 ms →
live max p50 2,004–3,684 ms, i.e. **4–7×**.

| Interaction | Synchronous path | Component | Measured | Class |
|---|---|---|---|---|
| **Keystroke → echo** | no hook fires | kitty `input_delay 5` (config/kitty.conf:421) | 5 ms | measured (config) |
| | | kitty `repaint_delay 16` (config/kitty.conf:415) | ≤16 ms | measured (config) |
| | | 60 Hz panel | ≤16.7 ms | derived |
| | | render path CPU today: kitty 13.3% + WindowServer 34.7% | 0.48 cores | measured (`top -l 2`) |
| | | **total** | **~21–38 ms** | — |
| **Prompt submit → first token** | UserPromptSubmit ×6, all before the API call | handoff-intent-nudge.sh | 183.4 ms | replay |
| | | session-beat.sh prompt | 76.2 ms | replay |
| | | memory-nudge.sh | 73.7 ms | replay |
| | | research-precognition-nudge.sh | 20.3 ms | replay |
| | | mailbox-drain.sh prompt | 20.1 ms | replay |
| | | cache-expiry-warning.sh | 10.3 ms | replay |
| | | **felt = max** (replay) → **live inferred** | **183 ms → ~0.7–1.3 s** | replay + 4–7× |
| | | CPU burned = sum | 383.9 ms | replay |
| **Each Bash tool call** | PreToolUse[Bash] ×7 | validate-bash.sh | 74.8 ms | replay |
| | | qos-rewrite.sh | 74.0 ms | replay |
| | | rm-safe-allowlist / ship-rail-push-allow / git-worktree-guard | 20.2 / 20.0 / 20.2 ms | replay |
| | | keychain-guard.sh | 19.4 ms | replay |
| | | curl-gate-scope.sh | 10.1 ms | replay |
| | | **felt = max** / CPU = sum | **74.8 ms** / 238.7 ms | replay |
| | PostToolUse ×6 (3 Bash-matched + 3 universal `[]`) | waiting-recycle.sh | 77.2 ms | replay |
| | | log-bash.sh | 38.6 ms | replay |
| | | teammate-checkpoint / cc-permission-beacon clear / mailbox-drain post-tool | 20.0 / 20.1 / 20.2 ms | replay |
| | | relay-verbatim.sh | 10.3 ms | replay |
| | | **felt = max** / CPU = sum | **77.2 ms** / 186.4 ms | replay |
| | | **per Bash call: 13 processes**, felt ~152 ms replay → ~0.3–1.0 s live | | replay + 4–7× |
| **Turn end → composer usable** | Stop ×11 | see §3 | **3,684 ms p50 / 7,712 ms p90** | **live, n=1,668** |
| **Statusline** | not on the render loop | statusline.sh | 40.8 ms med (n=15) | measured — see §5 |

Control floors, same harness, same box, same minute: `/usr/bin/true` 2.4 ms · `bash -c 'exit 0'` 5.0 ms ·
`jq -r .session_id` 5.0 ms · `python3 -c pass` **39.5 ms**.

## 3. Turn end — the live Stop-chain measurement (primary evidence)

Source: `hookInfos[].durationMs` in every session transcript under
`~/.claude-tertiary/projects/*/*.jsonl` (+ `*/subagents/*.jsonl`), 646 files, mtime ≤7 days,
1,668 events.

| | p50 | p90 | max |
|---|---|---|---|
| per-event **MAX** (= parallel wall cost, what the operator waits) | **3,684 ms** | **7,712 ms** | 14,884 ms |
| per-event **SUM** (= CPU burned by the chain) | 7,657 ms | 14,929 ms | — |

Per hook (ms):

| hook | n | p50 | p90 | p99 | max |
|---|---|---|---|---|---|
| `operator-readout.sh` | 1,666 | **3,611** | 7,651 | 10,308 | 13,448 |
| `notify.sh complete` | 1,670 | **1,847** | 2,237 | 5,345 | 7,077 |
| `session-continue.sh` | 1,418 | 581 | 997 | 3,122 | 6,931 |
| `dispatch-assert.sh` | 1,663 | 400 | 821 | 4,697 | 12,234 |
| `boundary-handoff.sh` | 1,667 | 389 | 838 | 4,896 | 7,077 |
| `teammate-checkpoint.sh` | 1,668 | 305 | 1,290 | 3,996 | 12,242 |
| `completion-assert.sh` | 1,463 | 297 | 2,189 | 5,050 | 8,587 |
| `anti-deference-nudge.sh` | 1,632 | 236 | 495 | 1,024 | 6,620 |
| `session-beat.sh stop` | 799 | 160 | 349 | 582 | 6,004 |
| `cc-permission-beacon.sh clear` | 1,666 | 65 | 195 | 642 | 6,633 |
| `cache-expiry-tracker.sh` (7 lines: one `date`, one write) | 1,668 | 45 | 155 | 666 | 6,003 |

Note the shared ~6.0–6.6 s maxima across four *independent trivial* hooks — the signature of a
simultaneous launch hitting one shared stall, which is what parallel execution predicts and serial
execution cannot produce.

**Why `operator-readout.sh` costs 3.6 s — it is not git.** It executes, at
`hooks/operator-readout.sh:377`, `"$blg" list --blocked --json | jq -r …`. Measured standalone on this
box:

| call | wall | user | sys |
|---|---|---|---|
| `cc-backlog list --blocked --json` | **4,200 ms** | — | — |
| `cc-backlog list --open` | 2,343 ms | 1.090 s | 1.251 s |
| `wrap-ledger.sh` | 169 / 180 / 193 ms | — | — |
| `git rev-parse --abbrev-ref HEAD` | 54.5 ms | — | — |
| `git rev-list --count HEAD..origin/main` | 59.9 ms | — | — |
| `git status --porcelain -uno` | 55.0 ms | — | — |

Store: `~/.claude/autonomy/backlog.jsonl` = **7,046 lines / 2,098,087 bytes**, append-only, current
status = the fold of the record trail (`bin/cc-backlog:3-7`), folded with **60 `jq` invocations**
(`grep -c '\bjq\b' bin/cc-backlog`). The 1.25 s of *sys* time is the fork/exec cost of that fold.
`cc-do --list` (also ~3,977 ms, same store) is **printed but never executed** by operator-readout —
verified; only the `cc-backlog` call is on the Stop path.

## 4. Lag vs crash — two mechanisms, and what uniquely precedes death

**Instrument.** `el` in `~/.claude/logs/compressor-sentinel.jsonl` — the sentinel's own **measured**
loop period (`scripts/compressor-sentinel.sh:50`, `:587`: *"Rates divide by MEASURED elapsed seconds,
never by the configured interval"*), target 10 s, Standard band (pri 31), 47,466 rows since 08-05.
A stretched `el` means the box failed to run a pri-31 timer on schedule — which is exactly what an
operator perceives as a freeze. This makes felt lag and the compressor ramp readable **on one clock**.

| regime | n | el p50 | p90 | p99 | max | %(el≥15) | %(el≥20) |
|---|---|---|---|---|---|---|---|
| **CHRONIC** — segments quiet (`pct<5`, `\|srate\|<100`) | 22,129 | 10 | 11 | 11 | **18** | 0.21 % | **0.000 %** |
| MID (`100 ≤ \|srate\| ≤ 1000`) | 1,754 | 10 | 12 | — | 257 | 5.82 % | — |
| **ACUTE** (`srate > 1000` seg/s) | 311 | 10 | 13 | — | 51 | 5.47 % | 2.57 % |

- `el ≥ 20` has occurred **91 times ever (0.193 % of all samples)**, and **91/91 at `segPct ≥ 5 %`**
  (87 in the 5–50 % band, 4 at ≥50 %). **Zero in the chronic regime.**
- 82 of those 91 are from **2026-08-07** — the day of 82 sentinel trips the box survived.
- **Positive control measured during this investigation**: `top -l 2` second sample at 23:31 read
  **Load Avg 53.64, CPU 0.0 % idle**, 963 processes, 21 claude sessions, a full `bats` suite running
  in the background band. Sentinel over the same window (3,714 samples ≥20:00Z): **`el` p50 10,
  p90 11, max 13**, segPct max 0.22 %.

**⇒ CPU saturation does not stall the box. Only the pageout/compressor wedge does.**

| | Chronic lag | Acute pre-crash lag |
|---|---|---|
| Cause | CPU oversubscription — our own hook chains (§2), fork churn, render path | compressor segment exhaustion → pageout wedge (crash doc §1.2–1.4) |
| What degrades | throughput: everything slower, everything still moving | **everything stops at once**, including non-CPU things |
| CPU state | pegged, 0 % idle, fans up | **idle cores** (crash doc §1.4: TH_RUN 235→6 with 10 idle cores) |
| pri-31 10 s timer | lands on time (max drift 8 s in 22,129 samples) | **stretches to 20–51 s** |
| Our lever | §6 wins 1–4 | the armed SIGSTOP actuator (crash doc §6) |

**The symptom that uniquely precedes death**: a multi-second freeze in which things that were never
CPU-bound also stop — a clock stops advancing, another app's cursor stops blinking, a pane that was
idle stops repainting — **while the CPU is not pegged**. Chronic lag never produces this (0 / 22,129).
"Everything is slow" is the ordinary state; "everything froze together and the fans are quiet" is the
pre-death state.

**Warning window, both Aug-9 panics** (sentinel rows, UTC; PDT = UTC−7):

| | panic #5 | panic #6 wave 2 | panic #6 wave 1 (the false positive) |
|---|---|---|---|
| last quiet sample | 10:33:43 el 10, pct 4.96 | 11:12:24 el 10, pct 2.91 | 11:07:25 el 11, pct 0.00 |
| first ramp | 10:33:55 dseg −1,953 → 10:34:14 pct 4.84→**11.08** (el 11) | 11:12:39 pct 2.91→**20.49** | 11:07:41 pct 0.00→**18.98** |
| **first stall (el ≥ 20)** | **10:34:27 el 20**, pct 33.27, srate 18,076/s | **11:12:39 el 21** (same sample as the ramp) | 11:07:41 el 23 |
| worst stall | 10:34:48 el 22 | **11:15:02 el 51**, pct 91.90 | 11:09:25 el 30, pct 85.55 |
| outcome | death ~10:39 | death 11:17 | **survived** — wave exited, dseg −1,393,457 at 11:10:18, pct→7.65, el→10 by 11:11:01 |
| **warning from first stall** | **4 min 33 s** | **4 min 21 s** | n/a |

Three readings, in the order that matters:

1. **Onset is simultaneous with the ramp, never before it.** In both fatal ramps the first `el ≥ 20`
   sample is the same sample as, or the one immediately after, the first segment jump — ~13 s. Felt
   lag has **no lead time on the ramp**; the lead time already lives in `srate`, which the sentinel
   trips on 3–5 minutes before death.
2. **`el ≥ 20` is a perfectly SPECIFIC ramp detector (91/91) but NOT a death predictor.** Wave 1
   produced el 30 and pct 93 and then recovered; 2026-08-07 produced 82 such samples with no panic.
   The operator feeling a freeze means *a storm is running*, not *the box is dying*.
3. **Corroboration in felt units** (weak, recorded honestly): hook durations bucketed by minute across
   the panic-#6 window read MAX-hook median **10,035 ms at 11:06Z** and SUM median **23,628 ms at
   11:10Z**, against a 4-day baseline of MAX p50 3,402 ms / SUM p50 8,086 ms. **n = 2–5 per bucket**,
   and a 1-minute bucket cannot resolve whether a 10 s hook started before or after the 11:07:41
   ramp. Suggestive of the same wedge reaching the hook chain; not decisive.

## 5. Does the statusline block the TUI render loop? No.

- **Vendor doc** (`https://code.claude.com/docs/en/statusline`): it *"renders in its own row above the
  built-in footer badges"*; triggers are session start, a new assistant message, `/compact` finishing,
  a permission-mode change, a vim-mode toggle, and a `refreshInterval` timer *"if you set one"*;
  *"Claude Code debounces updates at 300ms … If a new update triggers while your script is still
  running, Claude Code cancels the in-flight script."*
- `settings.json` `statusLine` = `{"type":"command","command":"~/.claude/statusline.sh"}` — **no
  `refreshInterval`**, so it is event-driven only. Correct as-is; adding one would buy the operator
  nothing and add fleet forks.
- **Cost**: 40.8 ms median / 66.3 ms max (n=15, fixture stdin). 12 command substitutions, of which 2
  `git` + 1 `jq`.
- **Fleet rate**: 5 distinct `statusline.sh` PIDs in 30 s at 10 Hz sampling across 21 sessions ≈
  **0.17 invocations/s**. Negligible against a 13-process-per-Bash-call hook chain.
- **Tail**: one instance (pid 29562) was observed alive ≥25 s. Bounded by the cancellation rule — the
  consequence is a stale bar, not a blocked render.
- **kitty**: `repaint_delay 16` and `input_delay 5` (`config/kitty.conf:415,421`) are already tuned to
  the 60 Hz panel and are worth ≤21 ms; kitty measured **13.3 % CPU** tonight against iTerm2's
  **94.7 %** in `gpu-vs-cpu-lag-2026-07-29.md`. The render path is no longer a lag term.

## 6. Cheapest wins, ranked by ms recovered (RECOMMEND ONLY — nothing changed)

| # | Change | Expected recovery | Evidence |
|---|---|---|---|
| **1** | **Take `cc-backlog list --blocked --json` off the Stop path** — cache the fold to a derived file invalidated by the JSONL mtime, or gate it behind the same damping check that already decides whether to render at all | **~3.4 s off every turn end** (operator-readout p50 3,611 → ~200 ms; chain max p50 3,684 → ~1,850 ms) | `operator-readout.sh:377`; standalone 4,200 ms; store 7,046 lines / 2.1 MB / 60 jq |
| **2** | **Background `notify.sh complete` at Stop** — nothing downstream reads its result; it is a notification | **~1.85 s p50** — becomes the binding constraint after win 1, so this is the second cut | live p50 1,847 / p90 2,237 ms, n=1,670 |
| **3** | **Compact `~/.claude/autonomy/backlog.jsonl`** | attacks the same 4 s from the data side; also speeds `dispatch-assert.sh` (p50 400 ms), `cc-do`, and every other consumer. Complementary to win 1, not a substitute — an O(n) fold on a smaller n is still O(n) | 7,046 lines / 2,098,087 B |
| **4** | **Drop the `python3` fork in `handoff-intent-nudge.sh:17-19`** (`jq -r .prompt` is 5.0 ms; `python3 -c pass` is 39.5 ms) | **~35 ms on the prompt-submit path** — small, but that path has nothing else to remove, and the hook's own comment calls itself *"cheap (grep on the prompt)"* while paying an interpreter start to extract one field | replay 183.4 ms, the max of that chain |
| 5 | Reap the orphaned `lead-crash-watchdog.sh` processes (ppid = 1, avg **5.9 concurrent**, one at etime 1 h 25 m; also orphaned singles of deploy-live, teammate-reap-alarm, postland-verify, autonomy-sweep) | **0 ms** — 0.0 % CPU, ~2.3 MB each. Listed so it is **not** mistaken for a latency win; it is a leak to fix on correctness grounds | 45 s / 114-snapshot census |
| 6 | **Statusline — change nothing** | non-win, stated explicitly | §5 |
| 7 | **kitty — change nothing** | non-win, stated explicitly | §5 |

**Alternatives considered and ruled out**

- **Wire up `hooks/hook-chain.sh`** — ruled out, and for a *stronger* reason than the file records:
  collapsing a **parallel** chain into one sequential process converts max() into sum(). On Stop that
  is 3,684 → 7,657 ms p50. Recommend annotating `hook-chain.sh:8-13`, which still asserts the serial
  model.
- **Blame the statusline** — refuted by measurement and by the vendor doc's cancellation rule.
- **Blame kitty** — already exonerated for the crash (crash doc §1); exonerated here for chronic lag
  too at 13.3 % CPU.
- **Reduce session count to fix felt lag** — the chronic-regime table refutes it: at load 53.64 and
  0.0 % idle the pri-31 loop still landed within 3 s. Session count is a **crash-risk** lever (fork
  churn → storm ignition), not a felt-lag lever.
- **A `type: prompt` Stop hook (`/goal`) as a chronic tax** — checked and ruled out: only **2** such
  hooks in 7 days of transcripts, at 14,205 and 14,884 ms. Enormous when armed, but it is not armed on
  the common path.

## 7. Adversarial pass — what a hostile reviewer gets right

- **"Your PreToolUse / PostToolUse / UserPromptSubmit numbers are replays, not live."** Correct, and
  stated in every row's class column. CC records only `stop_hook_summary`; no live instrument exists
  for the other three events without changing the config, which this brief forbids. The replay ran
  hooks **one at a time**, so it under-reports contention: the same replay of the Stop chain produced
  a max of 508 ms against a live max p50 of 2,004–3,684 ms.
- **"Your fixture short-circuits state-dependent hooks."** Correct, and measured: re-running the Stop
  chain with this session's **real** session id and **real** transcript raised the sum from 1,326 ms
  to 2,458 ms and moved `teammate-checkpoint` 20 → 507 ms and `session-continue` 348 → 508 ms. Both
  replay figures remain below live.
- **"Does the Stop chain actually block the operator?"** Yes, structurally: `session-continue.sh`
  returns `decision:"block"` to feed the next step back, so the harness cannot end the turn until
  every Stop hook has returned its decision. The vendor doc states the same for the general case:
  *"The user must wait for the hook to complete (up to its timeout) before the turn can progress."*
- **"91 stalls, 82 on one day — is `el ≥ 20` a load artifact after all?"** No: all 91 sit at
  `segPct ≥ 5 %`, and the 22,129-sample chronic population contains **zero**. The 2026-08-07 cluster
  is 82 real storms the box survived — which is the point of finding #2, not a counterexample.
- **"Your fork-rate probe."** Discarded: the PID-advance measurement (≈334 pids/s) was confounded by a
  concurrent full `bats` suite and is not used anywhere in this document.
- **Incidental defect found while measuring**: `relay-verbatim.sh` fired twice on Bash calls that
  merely *contained the string* `cc-do` in a grep pattern with output to `/dev/null` — a false-positive
  advisory injected into the model's context on the hot path. Costs context, not milliseconds; filed
  here so it is not rediscovered.

## 8. Method / reproducibility

- Hook replay harness + fixtures: `<scratch>/felt-lag/{timeit.py,pre-bash.json,post-bash.json,prompt.json,stop.json,statusline.json}`;
  mutating hooks redirected via their own documented env seams (`CC_BEAT_DIR`, `CC_MAILBOX_DIR`,
  `CC_WR_STATE_DIR`/`CC_WR_FIRE_DIR`/`CC_WR_HANDOFF_FIRE=0`/`CC_WR_KILL=0`, `CC_BOUNDARY_LATCH_DIR`,
  `CC_NOTIFY_DIR`, `CC_PERMPEND_DIR`, `CC_OPREADOUT_STATE_DIR`) into a scratch sandbox. No live store
  was written; no process was signalled.
- Live Stop-chain miner: `<scratch>/felt-lag/mine.py` — folds `hookInfos[].durationMs` from
  `~/.claude-tertiary/projects/*/*.jsonl` and `*/subagents/*.jsonl`.
- Parallelism sampler and orphan/statusline census: inline `ps` loops, 0.1–0.3 s, ≤75 s each.
- Sentinel regime split: `~/.claude/logs/compressor-sentinel.jsonl`, 47,466 rows, fields
  `el · pct · dseg · srate · n · nrss · wrate · strk`.
