# A7: prior-art reconciliation for the SessionStart hooks (2026-10-18)

Axis A7 of the 9-axis startup-hooks study. This axis was read-only: no hook script was run. The only
things written are this file and one helper, `a7_era_compare.py`, in the same directory.

Tags: **[M]** means measured, with the command given. **[E]** means estimated, with the method given.

---

## 0. Answer first

1. **Migration 0056 (the dispatcher) cannot be shown to have cut startup latency, and the number that
   justified it was biased low.**
   - Load-matched, the post-0056 startup span is not better than the pre-0056 one. At 1-minute load
     under 50, p50 is 4.07 s after against 2.47 s before. At load 50-150 it is 7.00 s against 5.80 s
     **[M]** (§2).
   - The pre-0056 baseline is a lower bound, though. Claude Code records a hook's `durationMs` only when
     the hook prints. `session-index-start.sh` was the slowest child, and it printed in only 303 of
     989 starts.
     - In pre-0056 starts where it did print, the span was p50 6.28 s at load under 50.
     - Where it was silent, the span was 2.13 s **[M]**.
   - So j-startup-hang's "p50 2.5-2.9 s" baseline mostly measured runs where the slow hook did not
     print. 0056 did not move the real span much in either direction. It made the span visible,
     because the dispatcher always prints.
   - CONCURRENCY_PROGRAM.md:2253 asked for exactly this before/after measurement. Nobody ran it until
     now.
2. **0056 regressed the no-silent-drop property, which the prior work never weighed.**
   - Before 0056, a slow hook was cancelled by the harness, and the harness wrote a `hook_cancelled`
     record that names the command. The pre-0056 era has 43 such records for accounts-board alone.
   - Now a slow child is killed by the dispatcher's own watchdog (`hooks/session-start-dispatch.sh:65`)
     and leaves **no record at all**. This happened on 95 of 375 dispatcher runs in the last 2 days
     (25%, **[M]**).
   - A dispatcher timeout now drops the output of **all 10 children at once**. That happened 23 times
     after 0056 **[M]**. Before 0056, a timeout cost one hook.
   - The 0056 header says "the span is unchanged". That is true of latency and false of
     attribution.
3. **Two landed fixes have symptoms that persist, because the harness's own cancel path is slow.**
   - Cancel records exceed their timeout: 8,323 ms for a 5,000 ms timeout and 13,544 ms for
     12,000 ms in the incident.
   - j-startup-hang.md already reported this 2-3x overshoot. DESIGN.md:221 then found the cause: the
     2.1.293 `killProcessTree` spawns `ps -A` with no timeout.
   - So a "cancelled" hook can keep running after the harness has thrown its output away. That
     reopens the mailbox-drain emit-then-commit fix (`hooks/mailbox-drain.sh:924-929`). The `.seen`
     commit can land after the harness has already discarded the payload. `mailbox_promote_acked`
     (`hooks/lib/mailbox-pending.sh:583-590`) then makes the loss permanent. This is the
     consumed-but-undelivered shape that `docs/lessons/a-reader-that-cannot-prove-delivery-must-not-consume.md`
     calls worse than losing the mail.
4. **One open prior recommendation explains the incident's "no working version" alarm.**
   - `COLD_START_100P.md:227` prescribed a per-version stamp for `pre-session-validate`, and its C1
     correction noted that `~/.claude-versions/current` is not the binary that sessions run. Neither
     was done.
   - Today the hook validates 2.1.114. All 39 live sessions run `~/.claude-293` **[M]**.
   - At load around 52 per core, a `timeout 2 … --version` boot of a 195 MB binary fails. The hook
     then reports "no working version". That happened in 23 of the 411 transcripts from the last 2
     days **[M]**.
   - It also spends up to 4 `--version` boots on every session start. On a false negative it could
     re-point the `current` symlink (`hooks/pre-session-validate.sh:157`).
5. **Do not re-propose these; they were already rejected with reasons:**
   - `prompt`, `agent` or `mcp_tool` handlers on SessionStart: the harness refuses them.
   - `http` handlers before a long-lived local service exists.
   - Moving absorbed hooks to T2 to save time (D6).
   - Caching tricks on the hook text (it is "not a lever").
   - The S3 and S5 shell trims.
   - Reducing the session count (F7). The operator has ruled it out.
   - Making the banner hooks async, unless the async systemMessage claim is re-verified on 2.1.293.

---

## 1. Method

- **Docs read in full or in their decision sections:**
  - `startup-2026-08-16/` (COLD_START_100P plus the measure and verify files)
  - `concurrency-scale-2026-10-04/` (README §3, j-startup-hang)
  - `sessionstart-readout-2026-10-06/README.md`
  - `load-hook-timeouts-2026-10-11/DESIGN.md` and the upstream draft
  - `R5-startup-print.md`, `cc-startup-modals-2026-08-04.md`, `function-hooks-91870-2026-09-03.md`,
    `hook-chain-occupancy-readjudication-2026-09-08.md`
  - `token-efficiency-2026-09-23/measure/hooks.md` and OPPORTUNITIES
  - `final-response-shaping-2026-08-08.md`, `tui-systemmessage-render-2026-08-22.md`
  - plans: DESK_ROUTER_AND_STARTUP_V1, HOOK_SURFACE_100P, HOOK_CHAIN_COST, LOAD_AND_PROMPT_HOOK_TIMEOUTS,
    CONCURRENCY_PROGRAM §S7
  - lessons: `sessionstart-systemmessage-accepts-sgr`, `a-reader-that-cannot-prove-delivery-must-not-consume`,
    and the "Loud into a dead log" rule
- `rg -l -i "sessionstart|session-start-dispatch" docs/` matched 383 files. I filtered them by name to
  the startup, hook and token docs. The list is in `/tmp/a7-ss-docs.txt`.
- **Status checks.**
  - `git log --format='%h %ad %s' -- <hook>` for all 18 SessionStart hooks.
  - `git log -S` for specific strings:
    - `LAUNCH WATCHDOG` gives `c9271cf99`.
    - `case "$body" in` gives `c3c8fccad`.
    - `CC_DRAIN_STALE_FORWARD_H-24` gives `f4fbb184e`.
    - `boot-latency-probe` gives only the doc commits `346bc006b` and `c80ffc60f`, so the script was
      never built.
  - `jq '.hooks.SessionStart' ~/.claude/settings.json`.
  - `jq '.env' ~/.claude/settings.json`.
  - `ls -d ~/.claude/backups/session-start-dispatch-0056-*` gives `…-20261004160641`. That means
    0056 was applied 2026-10-04 16:06:41 CDT, which is 21:06:41Z.
- **Before/after measurement:** `docs/research/startup-hooks-2026-10-18/a7_era_compare.py`, read-only.
  - It groups SessionStart hook records by `toolUseID`. One group is one SessionStart firing.
  - span = the largest `durationMs` among the synchronous hooks in that group.
  - Load is the nearest `load_1m` in `~/.claude/logs/capacity-alarm.jsonl` (plus the 2026-10-09 gz
    rotation) at or before the group, within 15 min.
  - Input: 2,506 main transcripts. These are every `~/.claude*/projects/*/*.jsonl` with mtime between
    2026-09-27 and 2026-10-12, plus `/tmp/startup-hooks-census-files.txt`. Subagent files are
    excluded.
  - That gives 1,921 SessionStart groups: 1,045 before 0056 and 876 after.
  - Command:
    `find ~/.claude*/projects -maxdepth 2 -name '*.jsonl' -newermt 2026-09-27 ! -newermt 2026-10-12 > L; cat /tmp/startup-hooks-census-files.txt >> L; sort -u L | A7_ROWS=/tmp/a7-era-rows.jsonl nice python3 -I a7_era_compare.py`
- **Known biases:**
  - **(a)** The printer-only bias (§2.2). It makes the pre-0056 span look shorter than it was.
  - **(b)** The two eras are different calendar windows. The stores grew, children were added
    (recycle-failed-inject on 10-09), and the session count changed.
  - **(c)** "board rendered" counts any `hook_system_message`. mailbox-drain also emits one, so the
    count is an upper bound.
  - **(d)** Groups with no load sample within 15 min are left out of the binned tables.

---

## 2. Did 0056 help, regress, or did load change?

### 2.1 Startup span, load-binned [M: a7_era_compare.py, as above]

"Full" groups only: before 0056, at least 5 synchronous hooks printed. After 0056, the dispatcher
printed or was cancelled.

| era | load_1m | n | p50 s | p90 s | p95 s | max s | groups with ≥1 hook_cancelled |
|---|---|---|---|---|---|---|---|
| pre-0056 (09-23 → 10-04 21:06Z) | 0-50 | 578 | 2.47 | 6.46 | 9.05 | 51.6 | 34 (5.9%) |
| pre-0056 | 50-150 | 334 | 5.80 | 8.01 | 10.06 | 13.5 | 58 (17%) |
| pre-0056 | 150-300 | 61 | 6.25 | 9.25 | 12.28 | 35.4 | 4 (6.6%) |
| pre-0056 | ≥300 | 7 | 6.04 | — | 8.69 | 8.7 | 0 |
| post-0056 (10-04 21:06Z → 10-18) | 0-50 | 438 | 4.07 | 9.24 | 9.59 | 21.5 | 17 (3.9%) |
| post-0056 | 50-150 | 245 | 7.00 | 9.88 | 10.16 | 20.1 | 25 (10%) |
| post-0056 | 150-300 | 102 | 6.82 | 11.91 | 12.97 | 120.8 | 18 (18%) |
| post-0056 | ≥300 | 87 | 9.83 | 13.66 | 20.37 | 33.2 | 31 (36%) |

The pre-0056 load-50-150 p95 is 10.06 s. That reproduces the 10.1 s that row 17 cited, so the
instrument agrees with the prior one.

The post-0056 `hook_cancelled` counts **understate** the drops. A child killed inside the dispatcher
writes no record (§3, finding F-A).

### 2.2 The pre-0056 baseline was printer-biased [M: same rows]

| pre-0056 subset | load 0-50: n, p50, p95 | load 50-150: n, p50, p95 |
|---|---|---|
| session-index-start **printed** | 104, **6.28 s**, 11.78 s | 160, **6.44 s**, 11.25 s |
| session-index-start **silent** | 474, **2.13 s**, 5.11 s | 174, 3.28 s, 7.89 s |

Before 0056, the hook that set the span was:

| hook | groups |
|---|---|
| config-mirror-assert | 448 |
| session-index-start | 261 |
| escalation-watch | 120 |
| mailbox-drain | 69 |

`session-index-start.sh` does the same `python3 session-search.py --context-inject` query whether
or not it prints (`hooks/session-index-start.sh:37`, then a print filter at :44-51). So the silent
runs very likely paid the same ~6 s, and the record simply did not show it **[E]**. The estimate rests
on reading the code path: the filter runs after the query. Two facts also point to contention behind
that ~6 s:

- The query opens sqlite with `timeout=5` (`~/Development/claude-session-search/bin/session-search.py:236`).
- `com.claude.session-search-sweep` still runs every 60 s (`launchctl print …session-search-sweep`
  gives `run interval = 60 seconds`) **[M]**.
- The O3 throttle to 300 s is still blocked on the operator (backlog `73ea54aec513` and `629200b47a49`).

**Verdict.** The 2.9 s / 10.1 s baseline that justified 0056 (j-startup-hang.md, README:136) is a
lower bound. Compared with the "printed" subset, the true pre-0056 span was about 6 s at any load,
and today's dispatcher span is about the same:

| window | n | p50 s | p95 s | runs over 9 s |
|---|---|---|---|---|
| 10-16 → 10-18 | 375 | 5.44 | 10.49 | 95 (25%) |
| 10-04 → 10-12 | 459 | 4.17 | 10.94 | 131 |

**[M]**: `python3 -I -c` over `/tmp/a7-era-rows.jsonl`. The brief's census gives p50 5.8 s over
410 runs. The difference comes from my de-duplication by `(sessionId, toolUseID)`.

0056 neither helped nor clearly regressed latency. Higher load moves the span:

- post-0056 p50 by load: 4.1 s, then 7.0 s, then 9.8 s.
- Load itself rose from about 70-270 (j, 10-04) to about 520 (today: `uptime` gives 521.96).
- After 0056, mailbox-drain and dod-persist set the span in 187 of 876 groups. Those two hooks were
  outside the fold.

### 2.3 Per-hook drift across the boundary [M: same rows, all loads]

| hook | pre: n, p50, p95 | post: n, p50, p95 |
|---|---|---|
| dod-persist.sh | 733, 1.56, 5.51 | 705, 1.85, 5.93 (max 30.2) |
| mailbox-drain.sh session-start | 586, 1.80, 5.23 | 527, 2.24, 6.64 (max 14.7) |
| session-start-dispatch.sh | — | 876, 5.02, 10.70 (one 902.6 s outlier on 10-10, no load sample) |

Both hooks that stayed separate got slower, and both have 5 s timeouts. That is consistent with
higher load. In the post-0056 era there are 68 mailbox-drain and 37 dod-persist cancels, against 33
and 45 before.

---

## 3. Ledger: every prior recommendation, with its status

Status key:

- **LANDED** with its commit.
- **PARTIAL**: part of it landed.
- **OPEN**: not done.
- **REJECTED** or **DROPPED**, with the reason.
- **SUPERSEDED**: a later decision or fact replaced it.

"Relevant" says which operator goal (latency, tokens, silent drops) is still affected.

### 3.1 Latency and structure

| # | Source (file:line) | Recommendation | Status | Evidence | Relevant now? |
|---|---|---|---|---|---|
| L1 | concurrency-scale README:136 (row 17); j-startup-hang.md:105 (F5) | Fold the non-gating SessionStart hooks into one process, or mark them async | **LANDED** `efb8f3133` (2026-10-04); applied 2026-10-04 21:06Z | backup dir stamp; settings show 10 registrations | **Symptom persists:** span p95 10.5 s today against the 10.1 s target; latency not improved (§2); attribution regressed (F-A) |
| L2 | CONCURRENCY_PROGRAM.md:2253 | After 0056, measure the span against 2.9 / 10.1 s | **OPEN until this report** | no doc cites a post-0056 span | Done here (§2) |
| L3 | COLD_START_100P.md:376 (S1) + R1 + D2 | Memoised alias tip set; redirect the session-start.sh SWR subshell; bounded adoption take | **LANDED** `55e7ffb0d` (2026-08-16) | COLD_START R1 "Landed" | Holds. mailbox-drain p50 is now 2.2 s: load, not the alias scan |
| L4 | DESK_ROUTER_AND_STARTUP_V1.md:235 (W0.1) | `find_active_list` single pass | **LANDED** `8d642bca9` | commit message | Holds |
| L5 | DESK_ROUTER:238 (W0.2) | `claude mcp list` off the critical path (SWR) | **LANDED** (SWR plus the R1 pipe fix `55e7ffb0d`) | session-start.sh history | Holds. Watch the MAX_AGE cliff (COLD_START M4) |
| L6 | DESK_ROUTER:194 | "Both SessionStart blocks use a null matcher, so every /clear re-pays the full cost" (an observation, no fix) | **OPEN** (never turned into a change) | today all 4 groups have no matcher; post-0056 sources: startup 796, resume 78, clear 1, fork 1 **[M]** | Low frequency (`clear` is rare). A matcher split is a settings edit (c10). See R6 |
| L7 | `22e2c4317` (R3/R4 follow-through) | activation-watch, setup-plan and setup-task batched; sweep detached | **LANDED** | commit message | Holds |
| L8 | `c32795c6c` | escalation-watch tail window and one awk pass ("gated 75% of SessionStart renders") | **LANDED** 2026-09-25 | commit message | Holds. It also documented that CC returns all SessionStart output only after the **last** hook settles. That is still the governing fact for when the board renders |
| L9 | sessionstart-readout README:160 (W1 #4) | accounts-board blank check by `case` glob (superlinear on /bin/bash 3.2) | **LANDED** `c3c8fccad` | `hooks/accounts-board.sh:164-166` | Holds |
| L10 | COLD_START_100P.md:227 | `pre-session-validate`: a per-version stamp, so it skips once validated | **OPEN** | no stamp in `hooks/pre-session-validate.sh` (163 lines) | **Yes, and it got worse:** see F-C (false "no working version" in 23/411 transcripts) |
| L11 | COLD_START §0 C1 (:21-35) | `~/.claude-versions/current` is not the binary sessions run | **OPEN for pre-session-validate** (the hook still targets it, `:4`, `:27`) | `readlink ~/.claude-versions/current` gives 2.1.114; `ps` gives 39× `~/.claude-293` **[M]** | Yes (F-C) |
| L12 | COLD_START §5.1-5.3 (:583, :612, :619) | Build `boot-latency-probe.py`, `hook-latency-probe.sh`, `boot-latency-guard.sh` (a regression guard into wrap-ledger) | **OPEN, never built** | `git log -S'boot-latency-probe'` shows the doc commits only; no script in `scripts/` | **Yes.** Without it, 0056's effect went unmeasured for 14 days |
| L13 | COLD_START I3 (:315) | Every deferral emits a completion signal: T2 jobs write `{job, started, ended, rc}`, and wrap-ledger shows "T2 overdue" | **OPEN** | `rg "T2 overdue" scripts/ hooks/` finds nothing | **Yes:** this is the prescriptive no-silent-drop contract the operator now asks for |
| L14 | COLD_START I1 (:309) | T1 group deadline 250 ms; raising a timeout is forbidden as a remedy | **SUPERSEDED in practice** (never enforced) | span p50 4-10 s | The principle still holds: do not answer timeouts by raising them |
| L15 | COLD_START §2.3 D6 (:249) | Do not move absorbed hooks to T2: it recovers 0 ms because paint (1.5 s) exceeds the group max | **SUPERSEDED by the load change** | the group max is now 4-10 s, well past paint, so hooks are no longer absorbed | The premise is gone. Async moves now save real turn latency, **but** M1 contention still applies, and banner hooks must stay sync (C-3) |
| L16 | j-startup-hang.md:101 (F1); README row 1 | `CLAUDE_CODE_CERT_STORE=bundled` | **LANDED** (operator settings) | `jq .env` has `CLAUDE_CODE_CERT_STORE: bundled` **[M]** | Holds |
| L17 | j:102 (F2); README row 7 | Launch watchdog: name a launch that has not registered after 20 s, and never kill it | **LANDED** `c9271cf99` | `bin/cc-close-attrib:462-501` | Holds. It is the model for "loud and named, never kill" |
| L18 | j:106 (F6) | Explicit timeout on net-context-stamp | **LANDED** (operator) | settings: `timeout: 5, async: true` | Holds. net-context-stamp is still outside the repo (an untracked real file) |
| L19 | j:104 (F4); README row 19 | Upstream: load the system CA off the main thread | **OPEN** (upstream; not filed as far as the docs show) | — | Low (F1 covers it) |
| L20 | j:107 (F7) | Reduce load and cap live sessions | **REJECTED** by the operator's constraint (no throttling or reducing sessions) | brief | Do not re-propose |
| L21 | DESIGN.md:217-221 (O4); backlog `c2aa7ab8be97` | Upgrade CC to ≥2.1.296 (per-hook durations in `--debug`); file the killProcessTree `ps -A` report | **OPEN, blocked on the operator** | `UPSTREAM_PS_A_REPORT_DRAFT.md` not posted | **Yes:** it explains the cancel overshoot (F-B) and gives unbiased per-hook timing |
| L22 | LOAD_AND_PROMPT O3; backlog `73ea54aec513`, `629200b47a49` | session-search-sweep at most every 300 s (it walks 17,334 dirs every 60 s) | **OPEN, blocked on the operator** (launchd) | `launchctl print` gives `run interval = 60 seconds` **[M]** | **Yes:** a likely contender for the ~6 s session-index-start query (§2.2) |
| L23 | hook-chain-occupancy:20-25 | A folding dispatcher must have a drift guard: the PreToolUse chain had drifted 4 members, which "would have run … zero times — silently" | **Lesson not applied to the SessionStart dispatcher** | `hooks/session-start-dispatch.sh:55` `[ -x "$DIR/$c" ] \|\| continue` silently skips a missing child | **Yes:** a silent-drop path (F-D) |
| L24 | function-hooks-91870:~95; HOOK_SURFACE_100P.md:1263 | `type:"http"` handlers as the answer to the per-hook fork tax | **DROPPED** "until a long-lived local service exists" | HOOK_SURFACE:1263 | Re-open only together with a service |
| L25 | HOOK_SURFACE_100P.md:65, :780, :1278 | `prompt`, `agent` and `mcp_tool` handlers | **REJECTED for SessionStart** (the harness refuses them: "no MCP client context"; the gate is `toolUseContext`) | measured on 114, 220 and 260 | Do not re-propose for SessionStart |
| L26 | COLD_START R2 (:825, :837) | S5 `_cc_sync_account` stamp; S3 route verdict to a flat file | **DROPPED**: S5 re-arms a two-day auth outage; S3 saves about 20 ms and breaks `log_route_decision` | R2 text | Do not re-propose |
| L27 | COLD_START S10 (:551) | `showSetupScreens()` 600 ms stall: diagnose first | **OPEN** (upstream-owned) | — | Pre-hook latency; another axis |
| L28 | COLD_START S6 (:510) | `MCP_CONNECTION_NONBLOCKING=1` tail guard | **OPEN** (operator's call) | not in `jq .env` **[M]** | Turn-1 tail only |

### 3.2 Tokens

| # | Source | Recommendation | Status | Evidence | Relevant now? |
|---|---|---|---|---|---|
| T1 | token-eff hooks.md:269 (#5) | config-mirror FORKED list → a count and a path | **LANDED** `bb2e82c27`, then `19a816074` (alarms → systemMessage) | commits | Holds |
| T2 | hooks.md:272 (#8) | dod-persist: lineage only | **LANDED** `bb2e82c27` (flag), `dd3f4033f` (on by default), `f28e44062` (6,000-char newest-first budget, under the 10k persistence cap) | commits | Holds. dod-persist is now a **latency** problem (p95 5.9 s on a 5 s timeout), not a token one |
| T3 | hooks.md:274 (#10) | Collapse stale peer-mail forwards older than 24 h | **LANDED** `f4fbb184e` (default 24 h) | `hooks/mailbox-drain.sh:799` | Holds |
| T4 | hooks.md:275 (#11) | Drop the empty session-index line | **LANDED** `bb2e82c27` | `hooks/session-index-start.sh:44-51` | Holds (but see §2.2 for latency) |
| T5 | `19a816074` | Alarms from activation-watch, config-mirror and escalation-watch → top-level systemMessage (0 tokens) | **LANDED** 2026-10-04 | commit | Holds. It is the prior art for "operator-visible, 0 tokens" |
| T6 | `74d7a3979` | Keep every injected context under the 10,000-char cap (over the cap it persists to file and shows a 2,000-char preview, `Kpo=1e4` / `Pye=2000`, hooks.md:249) | **LANDED** for ms365 and dod | commit | **Live hazard in the dispatcher:** CC_SSD_CAP 9,500 cuts from the end and says so to no one (F-E) |
| T7 | hooks.md:255 (cache layout) | Reorder hook text for prompt caching | **REJECTED, "not a lever"**: the first human prompt precedes memory in 851/858 sessions | hooks.md §4 | Do not re-propose |
| T8 | R5-startup-print.md | Board via `hookSpecificOutput.systemMessage` | **SUPERSEDED**: the nested key is silently ignored; top-level key `76fc7eca5` | DESK_ROUTER §2.7 | Do not regress |

### 3.3 Fault tolerance (no silent drops)

| # | Source | Recommendation | Status | Evidence | Relevant now? |
|---|---|---|---|---|---|
| F1 | COLD_START M5 (:298), I2 (:312) | No capped-and-discarded work; every cap has a named degraded result | **PARTIAL**: S1 and D2 bounded the mailbox, but the dispatcher re-creates M5 (it kills a child and discards its output with no record) | `session-start-dispatch.sh:61-68` | **Yes** (F-A) |
| F2 | backlog `6a178497df5f` (mailbox-drain.sh:277-284) | Emit, then commit: advance `.seen` only after the JSON write | **LANDED** (2026-09-10) | `hooks/mailbox-drain.sh:924-929` | **The symptom can persist:** the harness accepts output at process exit, not at write time, and its cancel overshoots (F-B) |
| F3 | lesson `a-reader-that-cannot-prove-delivery-must-not-consume` | `.acked` only on proof of delivery | **PARTIAL**: `.acked` is promoted at the next Stop as `acked=seen` with no transcript check | `hooks/lib/mailbox-pending.sh:583-590` | Yes (F-B) |
| F4 | `f8c12fce1` | Background children must not hold the hook stdout pipe (lint over all hook files) | **LANDED** | commit; `session-index-start.sh:104-107` comments the rule | Holds; the dispatcher's file redirect also isolates children |
| F5 | rule "Loud into a dead log" (situational rules:7) | Failing loudly into a log nobody reads is silent | Principle | — | **Yes:** a log-only drop record does not meet the operator's bar. The record must reach the terminal (top-level systemMessage) |
| F6 | final-response-shaping-2026-08-08.md:67 | "An async hook's systemMessage reaches the model and is hidden from the terminal" | **Claimed, never re-verified on 2.1.293**; the basis for keeping banner hooks sync (0056 header :14) | the source says "async asymmetry" with no probe recorded beside it | **Yes:** it decides whether the board could leave the sync path (open question Q1) |

---

## 4. Findings flagged by this axis

- **F-A. 0056 turned named cancels into anonymous kills.**
  - A pre-0056 harness cancel left `hook_cancelled` with `command`. That record lives in the
    transcript only, but it is attributable.
  - The dispatcher's watchdog (`session-start-dispatch.sh:65`) kills a child's group, then merges
    whatever exists. Nothing records which child died. `exec 2>/dev/null` (`:33`) and the per-child
    `2>/dev/null` (`:56`) also discard the children's diagnostics.
  - Rate: 95 of 375 runs over 9 s in 10-16 → 10-18 (25%), and 42% at load 50-150 **[M]**.
  - Prescription: the dispatcher names every killed child and every missing child in the top-level
    systemMessage (operator-visible, 0 tokens), and appends one row to a jsonl.
- **F-B. Harness cancel overshoot defeats emit-then-commit.**
  - Incident 5759497b: dod-persist 8,323 ms on a 5,000 ms timeout; mailbox-drain 10,051 ms on 5,000;
    dispatcher 13,544 ms on 12,000 (`jq` over the incident transcript, §1) **[M]**.
  - The cause on record: DESIGN.md:221. killProcessTree spawns `ps -A` with no timeout and resolves
    only on `close`.
  - So mailbox-drain can print, commit `.seen`, and only then be counted as cancelled, with its
    output discarded. The next Stop runs `mailbox_promote_acked` and the mail is gone.
  - Prior art fixed the reap-before-print half only.
  - Prescription:
    - session-start delivery should not commit `.seen` in the hook at all. Defer the commit to the
      first UserPromptSubmit or Stop, and check there that a `hook_additional_context` carrying the
      window's digest is in the transcript.
    - Or have mailbox-drain stamp its own planned emit, and have the next boundary re-deliver any
      window whose stamp has no matching transcript record.
- **F-C. pre-session-validate validates a binary no session runs, and raises a false fatal alarm
  under load.**
  - "no working version" appears in 23 of the 411 transcripts from the last 2 days
    (`xargs rg -l 'pre-session-validate\] ERROR: no working version' < /tmp/startup-hooks-census-files.txt | wc -l`)
    **[M]**. 0 reverts in the same set **[M]**.
  - Each start spends up to 4 `timeout 2 <195 MB binary> --version` boots (`:115`, `:146`). With 46
    sessions on a box at load about 520, that adds load on every start **[E]**: 4 candidates (3
    version dirs plus current) times 2 s.
  - The alarm reaches the model about 6.5 min later as an `async_hook_response` stderr (incident
    record at 05:56:23Z). It never reaches the operator.
- **F-D. A missing child is skipped silently.** `session-start-dispatch.sh:55` skips any child that
  is not executable. This is the drift class `hook-chain-occupancy:20-25` warned about. A child
  renamed or deleted in deploy-live would vanish without a word.
- **F-E. The 9,500-char cap cuts silently from the end.** `:88` does `$c[:$cap]`.
  - The last children in registration order (session-index-start, config-mirror-assert,
    frontier-status) are the ones that lose text, with no marker.
  - Today's mean is about 3.9k chars (brief), so this is not live now. It is a latent silent drop.
- **F-F. Fail-open exits print nothing.** `:46` (`mktemp` failed), `:59` (no children) and `:70`
  (no `jq`) exit 0 with **no** output. They drop all 10 children's work without a word.
- **F-G. The brief's version premise is off.** `~/.claude-versions/current` points to 2.1.114, not
  2.1.183. Live sessions run 2.1.293 (`ps` count 39 **[M]**; backlog `c2aa7ab8be97` agrees).
  - Any binary-string claim about the harness (async channel, cancel path) should be read against
    2.1.293.

---

## 5. Open rows that are still relevant

- **Latency:**
  - L10 / L11: the pre-session-validate stamp and target.
  - L12: the boot-latency instruments and guard.
  - L21: CC ≥2.1.296 per-hook durations, and the killProcessTree report.
  - L22: the session-search-sweep throttle.
  - L6: the matcher split.
- **Tokens:** none open from prior work. Every token-efficiency SessionStart row landed (T1-T6). The
  remaining ~1k tokens per start is new territory for the token axes.
- **Silent drops:**
  - L13: the I3 completion signal.
  - F1: M5 re-created by the dispatcher.
  - F2 / F3: the commit-vs-acceptance gap.
  - F6: the async claim, unverified on 2.1.293.
  - L23: the dispatcher drift guard.
- **Backlog rows** (`cc-backlog list`, read-only, 169 rows):

  | row | state | what |
  |---|---|---|
  | `c2aa7ab8be97` | blocked | O4: upgrade CC; file the `ps -A` report |
  | `73ea54aec513` | blocked | O3: sweep throttle |
  | `629200b47a49` | blocked | O3 launchd reload |
  | `55f0aafea981` | blocked | load plan Wave 3, lead-crash-watchdog kqueue watcher; needs the O5 exec trace |
  | `4ea535a3a3a3` | blocked, c10 | would **add** `net-recover-arm.sh` to SessionStart with asyncRewake |
  | `ecf9c60083ff` | blocked, c10 | mailbox-wake-arm on Stop |
  | `f7d7449ce5e2` | blocked, c10 | batch that closes `ecf9c60083ff` and `4ea535a3a3a3` |

  The brief's exact filter
  (`rg -i "sessionstart|session-start|startup|dispatch|accounts-board|hook timeout"`) matched only
  `55f0aafea981`, `457c166ed9d6` (lr_recon load), `ecf9c60083ff`, `4ea535a3a3a3` and three
  off-topic rows.
  - **No backlog row covers F-A … F-F.**

## 6. Rejected approaches the operator should not see re-proposed

| Approach | Reason on record |
|---|---|
| Fewer sessions, or a session cap, to cut load (j F7) | The operator's standing constraint |
| `prompt`, `agent` or `mcp_tool` SessionStart handlers | The harness refuses them (HOOK_SURFACE_100P.md:780, :1278) |
| `http` handlers now | Dropped until a long-lived local service exists (HOOK_SURFACE:1263) |
| Prompt-cache reordering of hook text | "Not a lever" (token-eff hooks.md:255) |
| S3 route-verdict file, S5 sync stamp | R2 (COLD_START:825, :837): auth-outage risk; about 20 ms gain |
| Raising a hook's timeout as the fix for a slow hook | COLD_START I1 (:309), DESK_ROUTER W0.2 ("Do not simply raise the timeout") |
| Board through `hookSpecificOutput.systemMessage` or `additionalContext` | Silently ignored, or billed (DESK_ROUTER §2.7) |
| Making banner hooks `async` | Kept sync because an async systemMessage is claimed to go to the model. **Only re-open after Q1 is measured on 2.1.293** |

## 7. Recommendations

Each row gives impact, effort (S/M/L), risk, whether settings.json changes (c10 means an
operator-only settings edit), and conviction from 0 to 100.

| # | Recommendation | Where | Impact | Effort | Risk | Settings edit? | Conviction |
|---|---|---|---|---|---|---|---|
| R1 | Dispatcher drop ledger. For every child the watchdog killed (`:65`), every child skipped as missing (`:55`), a cap cut (`:88`) and each fail-open exit (`:46`, `:59`, `:70`), add a line to the **top-level systemMessage**: `⚠ startup: <child> killed at 9 s (output lost); re-run: bash ~/.claude/hooks/<child> < payload` or similar. Also append one jsonl row (`~/.claude/logs/ssd-drops.jsonl`) | `hooks/session-start-dispatch.sh` | Closes 4 silent-drop paths. Names the child in about 25% of runs today (95/375 **[M]**). 0 model tokens (systemMessage) | S | Low. systemMessage lines are terminal-only on the sync path. The record must be built before the merge `jq` and survive a missing `jq` | No | 85 |
| R2 | Finish the dispatcher inside its registration budget under load. Today the bound is 9 s and the registration 12 s, but the harness cancel slips by 1.5-3 s (F-B). Lower `CC_SSD_BOUND_S` to about 7 s, or have the watchdog start the merge at the bound instead of waiting on the killed groups. This does not throttle or cut work: the same children run, and only the reporting deadline moves earlier | `hooks/session-start-dispatch.sh:41,65-68` | Removes most of the 23 post-0056 whole-dispatcher losses (each lost the board and all context) **[M count; E share]** | S | A child that needs 7-9 s now loses its output, but R1 names it, against today's total loss | No | 70 |
| R3 | pre-session-validate: validate the binary the session actually runs (resolve it from `$PPID`'s executable, or `CLAUDE_CODE_EXECPATH` if present) once per version. Keep a stamp keyed on (path, mtime). Never re-point `current` on a timeout under load: tell a timeout (rc 124) apart from a crash | `hooks/pre-session-validate.sh:4,27,110-157` | Removes up to 4 × 195 MB binary boots per session start [E]. Ends the false "no working version" alarm in 23/411 transcripts [M]. Closes COLD_START L10 and L11 | S | A stamp hides a binary that breaks later at the same path and mtime. A path+mtime key makes that impossible short of in-place modification | No | 80 |
| R4 | mailbox-drain session-start: commit on proof of delivery. Do not advance `.seen` in the SessionStart hook. Record `{window_end, digest}` in a pending stamp. At the first UserPromptSubmit or Stop, commit it only if the transcript holds a `hook_additional_context` with that digest; otherwise re-deliver | `hooks/mailbox-drain.sh:924-929`, `hooks/lib/mailbox-pending.sh:583` | Closes the consumed-but-undelivered path under cancel overshoot (F-B). The cost is a possible duplicate, which the drain is already dup-biased toward | M | Changes a delivery contract with 97+ bats tests; the digest match must handle persisted (>10k) context | No | 65 |
| R5 | Build the COLD_START §5 regression guard, reduced to what transcripts already give. Each day, run a load-binned span plus a drop report from transcripts (`a7_era_compare.py` is a start) and write one line into the wrap-ledger store. Count `hook_cancelled` by command, dispatcher runs over the bound, and the R1 drops | new `scripts/startup-span-guard.py` + launchd (staged) | Makes the next 0056-class change measurable. It also implements I3 (completion signals) for SessionStart | M | Inherits the printer bias until CC ≥2.1.296 (L21) | No (the plist reload is operator-only) | 60 |
| R6 | Operator, c10: split the matcher. Give `compact` and `resume` a lean SessionStart group. On compact, the board, symlink setup and registry writes are repeats. Keep mailbox-drain, dod-persist and the context children | `~/.claude/settings.json` | Small: post-0056 sources are startup 796, resume 78, clear 1, compact 0 recorded **[M]**. compact firings may be under-recorded | M | Splitting groups changes what /compact re-injects. It needs a probe | **Yes (c10)** | 30 |
| R7 | Operator: run O3 (`629200b47a49`), so session-search-sweep runs every 300 s instead of 60 s. Then re-measure session-index-start inside the dispatcher | launchd | Plausibly the largest single child cost (about 6 s when printed) [E: §2.2] | S | None stated in O3 | No (launchd is operator-only) | 55 |
| R8 | Operator: O4 (`c2aa7ab8be97`). Upgrade to ≥2.1.296 for per-hook `--debug` durations, and post the killProcessTree report | cc-upgrade gate | Unbiased per-hook timing (ends the printer bias). The upstream fix bounds cancel overshoot | M | The upgrade gate's normal risk | No | 55 |
| R9 | Re-verify the async systemMessage claim (final-response-shaping:67) on 2.1.293 in a sandboxed pty (the R5b probe pattern) before anyone uses async in a design | probe, docs | Decides whether non-board children can go async safely | S | None (sandbox) | No | 60 |

## 8. Open questions

- **Q1.** On 2.1.293, does a settings-level `"async": true` SessionStart hook's top-level systemMessage
  render in the terminal, reach the model, or both? The only source is a 2026-08-08 statement about a
  runtime `{"async":true}` response (final-response-shaping:67). The incident shows an
  `async_hook_response` record carrying stderr 6.5 min after start.
- **Q2.** How much of the ~6 s session-index-start cost is sqlite lock wait (sweep contention), and
  how much is python start plus query? It needs a sandboxed DB copy, or a run under 2.1.296+ debug.
- **Q3.** What fraction of dispatcher runs over 9 s killed which child? It is unknowable from
  transcripts today; R1 would answer it going forward.
- **Q4.** Does the harness show `hook_cancelled` to the operator at all on 2.1.293? If not, then
  before 0056 the drops were attributable but just as invisible to the operator as they are now.
- **Q5.** Did the 902.6 s dispatcher record (2026-10-10T21:13Z, sid 8b2487a3) come from a suspended
  machine, or from a real wedge past the 12 s timeout? A wedge would be another cancel-path defect.

---

## Skeptic verdicts

This was an adversarial review, done read-only. No hook was executed. Helper scripts are in `/tmp/a7skeptic/`
and were all run with `python3 -I`. They read `/tmp/a7skeptic/all-files.txt`, which lists the 3,009 main
transcripts with mtime on or after 2026-09-27 **[M]**
(`find ~/.claude*/projects -maxdepth 2 -name '*.jsonl' -newermt 2026-09-27 | sort -u | wc -l`).

| id | verdict | severity |
|---|---|---|
| A7-1 | **refuted** | major |
| A7-2 | amended | major (R2 as worded breaks the operator constraint) |
| A7-3 | amended (now has stronger evidence) | minor |
| A7-4 | amended | major (the impact is 4x too high, and R3's main mechanism goes against prior art) |
| A7-5 | confirmed | none |
| A7-6 | amended | minor |
| A7-7 | amended | minor |
| A7-8 | **refuted** | major |
| A7-9 | confirmed | none |

### A7-1: refuted. The "printed" subset is really a stderr subset (sqlite lock errors), and silent runs did not pay ~6 s

**The harness records `hook_success` with `durationMs` when a hook writes stdout OR stderr, not only
when it prints.**

- Every empty-stdout `hook_success` record in the 3,009 transcripts carries non-empty stderr **[M]**
  (`xargs rg '"type":"hook_success"[^\n]*"stdout":""' | jq` gives 1,346 records, all with stderr). They
  break down as session-continue 775, session-index-start 265, session-beat 156, pre-session-validate 87,
  session-register 46, plus a few others.

**session-index-start's pre-0056 records are almost all lock errors, not output.**

- 265 of its 266 pre-0056 `hook_success` records have **empty stdout**. All 265 have stderr
  `Error: stepping, database is locked (5)` **[M]** (`/tmp/a7skeptic/empty_success.py`, plus the
  `jq '.attachment.stderr'` tally).
- Only 1 record actually printed.
- A7's "printed in 303 of 989" is these 265 records plus 38 cancels.

**Where the ~6 s comes from.**

- It is not the query at `:37`. It is the background stub-upsert subshell at `hooks/session-index-start.sh:69-107`.
- That subshell redirects only stdout (`:107`), so it keeps the hook's **stderr** pipe open until
  `SESSION_INDEX_BUSY_TIMEOUT` (5000 ms, default at `hooks/lib/session-index-helpers.sh:75`, used at `:79`) expires.
  - The recorded minimum is 5,377 ms. That is the busy timeout plus overhead.
- The hook's own registration was 5 s (`~/.claude/backups/session-start-dispatch-0056-20261004160641/settings.json`).
  Even so, all 265 records have `durationMs` > 5,000 and are `hook_success`, not cancelled.
  - So the harness timeout bounds when the process exits. It does not bound how long the pipes take to drain.

**Silent runs measured directly.**

- `/tmp/a7skeptic/sis_idl_leader.py` joins each pre-0056 group's start time with session-index-start's
  EXIT-trap row in `~/.claude/autonomy/idl.jsonl*`.
  - Start time = record ts − durationMs. Record ts is the completion time: the incident's three cancels
    give the same start to within 1 ms.
- How long the hook's main process ran:

  | runs | n | p50 | p90 | p95 | runs ≥5 s |
  |---|---|---|---|---|---|
  | silent | 528 | **0.8 s** | 2.3 s | 3.1 s | 0.4% |
  | lock-error (recorded) | 269 | 1.16 s | — | — | — |

  **[M]**, at 1 s IDL resolution.
- So the silent runs did **not** pay ~6 s. The pre-0056 load-banded p50s (2.47 s / 5.80 s) are a fair
  baseline, and not a lower bound by ~3.5 s.

**What the matched-load comparison actually says.**

- The in-band mean load is the same in both eras: 26.3 against 27.6 at load 0-50, and 78.1 against 85.6
  at 50-150 **[M]** (python over `/tmp/a7-era-rows.jsonl`).
- At load 0-50, the post-0056 dispatcher p50 is **4.04 s**, against 2.47 s pre-0056.
  - Against the 82% of pre-0056 starts without the lock error, it is 4.04 s against **2.12 s**,
    counting only the hooks the dispatcher later absorbed.
- At load 50-150 it is 7.0 s against 5.8 s (3.21 s for runs without the lock error).
- 0056 did remove one cost. Its per-child `2>/dev/null` (`hooks/session-start-dispatch.sh:56`) took the
  ~5 s stderr-hold off the critical path. That path hit 18% of starts at load under 50 and 48% at
  load 50-150.
- Even so, the span is **worse** at matched load after 0056. This axis has not found what caused it.
  - The candidates are child growth, recycle-failed-inject (added 10-09), the dispatcher's own serial
    fork and jq overhead, and calendar confounds.

The numbers in the table do reproduce (6.28 / 2.13 / 10.06 s). Only the interpretation was wrong.

**Correction.**

- Keep the pre-0056 load-banded p50s as the baseline.
- Report that the startup span got worse at matched load after 0056, with the cause not yet isolated.
- State the bias as "only hooks that write stdout or stderr are timed".
- Do not target session-index-start's query on this evidence: its foreground p50 is about 0.8-1.2 s.
- Find the slow child with per-child timing that the dispatcher records itself.

### A7-2: amended. The code claims are confirmed, R2 breaks the constraint, and "over 9 s" is an upper bound

**Confirmed.**

- `:33` and `:56` discard stderr. `:55` skips a missing child silently. `:65` TERMs the child's process
  group. `:88` cuts with `$c[:$cap]`. `:46`, `:59` and `:70` exit with no output.
- In the window starting 10-16T00:00Z, 98 of 385 runs were over 9 s, and 43 of 103 (42%) at load 50-150
  **[M]**, from the rows file. That is close to A7's 95/375.
- There are 23 dispatcher cancels after 0056 in A7's rows **[M]**.
  - A7's input skipped 460 transcripts modified 10-12 → 10-16 **[M: find … -newermt 2026-10-12 ! -newermt 2026-10-16 | wc -l]**.
  - Those files hold one more dispatcher cancel, so 23 is a lower bound.

**Correct the evidence.**

- A run over 9 s does not prove a child was killed. The watchdog starts only after the spawn loop, and
  the merge runs after it.
- Still, 72 of the 98 runs fall in the 9-10 s bin, against 17 in the 8-9 s bin **[M]**. That pile-up
  is the watchdog's signature, so most are likely kills **[E]**.

**R2 violates the operator constraint as worded.**

- Lowering `CC_SSD_BOUND_S` to 7 s makes `:65` `kill -TERM -- "-$p"` kill children's **process groups**
  2 s sooner. "Every child still runs" is false for that variant.
- Only a deadline that reports without killing complies. At about 7 s the dispatcher merges and prints,
  and stragglers keep running detached. Their late output is named and delivered later, for example at
  the first UserPromptSubmit, and logged to jsonl.
- That design has three traps:
  - The EXIT trap `rm -rf "$T"` (`:47`) deletes the stragglers' output files. Output must go outside `$T`.
  - It deliberately changes `tests/session-start-dispatch.bats:48-58` ("the hung child was killed, not orphaned").
  - Even this variant cannot report anything when the harness cancels the dispatcher itself.

**The drift guard exists at test time.** `tests/session-start-dispatch.bats:82-95` asserts that all
10 listed children exist. Only the runtime gap is real: a missing live-layer symlink.

**More silent paths A7 missed.**

- `:91`: a failed merge `jq` sets `OUT=""` and drops everything.
- A child killed mid-write has its partial output merged as **plain model context**, because
  `try fromjson` fails on partial JSON.

**About R1.** The line fires on about 25-42% of starts under load. Make it a single compact line with a
prescribed automatic recovery (late delivery). "Re-run it by hand with the payload" asks for a payload
the operator does not have.

### A7-3: amended. The precondition is now measured, but no loss has been shown

**Reproduced.**

- In the incident transcript (now at `~/.claude-secondary/projects/…/5759497b-….jsonl`; it moved
  accounts), the cancels are 8,323 / 10,051 / 13,544 ms on 2.1.293 **[M]**.
- `hooks/mailbox-drain.sh:924` prints, and the commit is at `:928-930`.
- `hooks/lib/mailbox-pending.sh:583-590` sets `acked=seen` unconditionally. Its caller is
  `hooks/session-continue.sh:515`.
- DESIGN.md says this at `:219-221`, where the report is drafted.

**New direct evidence.**

- Take the 38 pre-0056 session-index-start `hook_cancelled` records and look for an EXIT-trap row
  between start and end + 5 s:
  - 7 wrote `passed exit:0` **strictly after** the harness's 5 s timer had fired.
  - 9 are ambiguous: the exit falls in the same second as the timer.
  - 21 left no exit row.
  - 1 shows exit 143.
  - **[M]** `/tmp/a7skeptic/sis-cancels.jsonl` joined with `/tmp/a7skeptic/idl-sis.jsonl`.
- So a hook the harness has "cancelled" can keep running to a normal exit while its output is thrown
  away. That is exactly the precondition for mailbox-drain to commit `.seen` and lose the mail.

**But no loss is demonstrated.**

- The incident session's inbox holds no message older than 2026-10-18T10:33:48Z, which is 4.7 h after
  the 05:49Z start **[M: timestamps in `~/.claude/mailbox/5759497b-….md`]**. That cancel probably cost no mail.

R4 stands. It changes a contract covered by 98 tests (`tests/mailbox-drain.bats` 88 and
`mailbox-emit-then-commit.bats` 10) **[M: rg -c @test]**.

### A7-4: amended. One boot, not four, and "validate the running binary" goes against COLD_START:227

**Boots per start: 1, not "up to 4".**

- `~/.claude-versions` holds 2.1.113, 2.1.114 and 2.1.183, and `current` → 2.1.114.
- Both fallbacks are MANIFEST `skip` (MANIFEST.jsonl:7 and :14). `pre-session-validate.log` shows each
  of the 18 failures on 10-17 and 10-18 followed by "fallback skip 2.1.183" and "fallback skip 2.1.113"
  **[M]**.
- So each start boots one 195 MiB binary (204,534,752 bytes, **[M: stat]**). A failure adds 0 more boots.

**Re-pointing `current` is not possible today, though it has happened before.**

- With both fallbacks skip-flagged, the hook cannot re-point `current` now.
- The log does show a past false revert: 2.1.114 → 2.1.80 at 2026-07-21 08:52:29, reverted again
  2 min later **[M]**.

**Line citation.** `:157` is a blank line. The re-point is at `:159`.

**The alarm count reproduces.** 19 of the 402 census files that still exist carry an
`async_hook_response` with "no working version"; 9 files have moved since the census **[M]**. That is
consistent with 23/411.

**"Reaches the model" is unverified.**

- The record has `response:{}`, empty stdout, and the text only in stderr.
- The text appears later in the session only through a tool read.

**R3 should drop "validate the binary the session runs".**

- COLD_START_100P.md:227 already says that the hook "can only ever fix the NEXT launch". A running
  session has trivially passed its own boot.
- MANIFEST.jsonl:44 lists 2.1.293 as `skip`. It escapes the hook's grep only because that line has
  JSON spacing the grep does not match.

**Correction.**

- Keep validating `current`, which the next launches use (`bin/claude-versions`, `bin/claude-latest`).
- Stamp it by (path, mtime).
- Treat rc 124 as "unknown under load": no alarm and no re-point.
- Impact: 1 boot saved per session start, and the false alarm removed (about 5% of transcripts).

### A7-5: confirmed

- All seven commits exist with matching subjects (`git log -1`).
- `hooks.md:255` reads "Cache layout (checked, not a lever)".
- `mailbox-drain.sh:799` sets the 24 h default.
- `dod-persist.sh:303` sets the 6000-char default.

### A7-6: amended. The list is missing recorded rejections

- `load-hook-timeouts-2026-10-11/DESIGN.md:230` rejects **`async: true` for heavy hooks**: "saves no
  CPU and has no enforced timeout, so runs pile up". That reason holds whatever R9's probe shows.
- `:229` rejects **load-threshold early exits**.
- `:227` rejects **a `ps` shim on PATH**.
- Also add COLD_START:227 (see A7-4).
- "D6 no longer applies" is half right. The "0 ms recovered" premise is gone, but its M1 argument
  still applies (moving a hook off the critical path makes it a post-paint contender for turn 1).

### A7-7: amended

- The COLD_START §5 tools were never built **[M]**:
  - `git log -S'boot-latency-probe'` finds only doc commits (346bc006b, 5094a913e).
  - `rg 'T2 overdue'` finds nothing.
- Two corrections:
  - **CC ≥2.1.296 per-hook durations cannot time the 10 dispatcher children**, because they are not
    harness hooks. Only the dispatcher can record their times.
  - The bias is stdout-or-stderr (A7-1).
- "Which is why 0056 went unmeasured" is **[E]**.
- The guard has to show up somewhere the operator sees it. A wrap-ledger line alone would be "loud into
  a dead log" (situational rules, line 7).

### A7-8: refuted. O3 has landed

- Backlog rows `73ea54aec513` and `629200b47a49` are **done** (`cc-backlog list --all`).
- The plist (mtime 2026-10-12 11:11) and the loaded job both carry `SESSION_INDEX_SWEEP_MIN_INTERVAL_S => 300`
  (`launchctl print gui/501/com.claude.session-search-sweep`).
  - "run interval = 60 seconds" is only the launchd wake. The script gates itself to 300 s
    (`hooks/session-index-sweep.sh:91-99`).
- R7 is moot.
- New fact: a single sweep pass, pid 25421, has been running for **5 h 37 min** since 02:54:48 **[M: ps -o lstart,etime]**.
  The last stamp was written at 02:55:12.
  - A multi-hour sweep is the contention source worth examining, not a 60 s cadence.
- O4 (`c2aa7ab8be97`) is still blocked.

### A7-9: confirmed

- `DESK_ROUTER_AND_STARTUP_V1.md:194` checks out, and all 4 live groups have `matcher: null` **[M: jq]**.
- In the 402 census transcripts **[M: rg -o hookName]**:
  - startup 1,445, resume 104, fork 10, clear 4, compact 0.
  - Only 1 transcript has any compaction marker.
- The R6 settings edit is correctly flagged as c10.

### What this axis missed

1. The study-wide bias statement is wrong. The harness times hooks that write stdout **or stderr**.
2. A hook whose background child inherits **stderr** can run past its timeout with no cancel recorded.
   - Shown by 265 records at 5.4-9 s against a 5 s timeout.
   - The f8c12fce1 lint covers stdout only.
   - 0056's per-child `2>/dev/null` hid this class for its children only. It is unguarded for every
     separately registered hook.
3. The startup span got worse at matched load after 0056 (A7-1).
4. O3 has landed, and a 5.6 h sweep pass is running (A7-8).
5. More silent paths in the dispatcher:
   - the `:91` merge failure;
   - partial output from a killed child injected as context;
   - the `:47` EXIT trap deleting the output of any detached straggler.
6. Rejections A7-6 did not list: DESIGN.md:227/229/230 and COLD_START:227.
7. A7's input skipped 460 transcripts from 10-12 to 10-16, so its post-0056 counts are lower bounds.
