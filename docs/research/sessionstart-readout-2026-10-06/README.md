# SessionStart account readout: W0 research synthesis

Plan: `docs/plans/SESSIONSTART_READOUT.md`. Method: one Dynamic Workflow, 10 read-only slots on `workflow-lean` (R1-R8 plus a hostile reviewer on Fable 5.1), one synthesis slot (Opus 5.5 xhigh), and a two-skeptic stage (red-team on Fable 5.1, conviction audit on Opus 5.5) — 13 agents, 0 failed. The lead's final disposition is the last section, **Skeptic stage and W1 decision set**, and it supersedes the draft's ranked-change convictions where the two differ.

Inputs: the ten slot files, copied to `slots/` beside this README (r1, r2, r3a, r3b, r4, r5, r6, r7, r8a, adv), plus the two skeptic files. Paths below that read `/tmp/ssr-research/<x>.md` are now `slots/<x>.md`; scratch artifacts the slots cite (CSVs, sandboxes) stayed in `/tmp/ssr-research/` and are not durable. The R1 timing harness is `r1-harness.sh` here. Worktree `sessionstart-readout` @ `b87e6da64`. `bin/claude-accounts` and `hooks/accounts-board.sh` are byte-identical to the live `~/.claude` copies (measured: `diff -q`, SAME-BIN / SAME-HOOK). Receipts marked **[re-verified]** were re-run or re-read by this synthesis. Other receipts are the slot's own.

Constraint keys used below:
- **H1:** the SessionStart hook stays a pure file read, and its p50/p99 must not rise.
- **H2:** no account quota in the status line.
- **H3:** the 2026-10-01 and 2026-10-03 rulings stand: three states inline in the percent column and the bar; a spendable last 1% is never a full red bar; only a server-confirmed refusal prints "100%".
- **H4:** wire reads stay gated to the near-wall band.

## Summary

1. **The server read was right; the board's wording was not.** The wire said `0.99 allowed_warning` at 06:01:41.857Z and the first refusal came at **06:02:41.736Z** (e131c8d2, not the plan's 06:03:04Z). "99.0%" adds a digit the server never sends (0 of 4,142 readings have more than 2 dp **[re-verified]**), and "about 1% / roughly 5% of a 5-hour window" printed a ceiling already spent (5 of the 5h meter's points gone since the first 0.99 read **[re-verified]**; past refusals came after 3–6).
2. **Cadence is not a defect.** Sweeps run 185.6 s apart (p50); the ~6 min spacing is the recorder's 300 s gate (`bin/claude-accounts:5483` **[re-verified]**); the producer read `rejected` 67.5 s after the first refusal. The one real producer bug is a shadowed `deadline` that makes setitimer fail with EINVAL (1 occurrence, 2026-09-30).
3. **Baseline.** The production board runs under bash 5.3.15 in 16/16 live sessions (p50 61.5 / p99 124.2 ms). Under /bin/bash 3.2 it is p50 902.2 / p99 1889.2 ms, all from one superlinear line (`hooks/accounts-board.sh:164` **[re-verified]**). The systemMessage costs 0 model tokens (`hook_system_message:()=>[]` **[re-verified]**).
4. **History.** Every recorded ≥99% stay ended in refusal (10/10, median 47 min, range 17–174). k does not predict the timing (ρ −0.20) but burn does (ρ −0.93). Routing sent no new sessions to next3. A zero-token refusal signal exists: StopFailure markers land within 2 s and were contradicted 0 times in 197.
5. **Minimal fix, in order:** print the server's whole percent (`99%`, not `99.0%`); delete both point headroom figures; put the note in the past tense with the read's clock time and the live/working load; fix the hook's blank check before adding bytes; land the W-11 control red first. Everything else ranks below these.

## R1 baseline table (verbatim from r1-baseline.md)

| # | arm | interpreter | n | p50 | p90 | p99 | max | load 1/5/15 start → end |
|---|---|---|---|---|---|---|---|---|
| 1 | accounts-board.sh, fresh board | /bin/bash 3.2.57 | 300 | **902.2** | 984.8 | **1889.2** | 3725.1 | 32.93 70.06 61.17 → 34.69 44.46 51.48 |
| 1 | accounts-board.sh, fresh board (interleaved) | /opt/homebrew/bin/bash 5.3.15 (PATH bash) | 300 | **61.5** | 81.6 | **124.2** | 143.1 | same batch |
| 2 | accounts-board.sh, stale board (mtime −10 min) | /bin/bash 3.2.57 | 100 | 892.7 | 1132.4 | 1499.9 | 1715.9 | 34.69 44.46 51.48 → 22.38 37.00 47.73 |
| 2 | accounts-board.sh, stale board (interleaved) | bash 5.3.15 | 100 | 69.4 | 83.4 | 132.9 | 151.6 | same batch |
| 3 | session-start-dispatch.sh, `CC_SSD_CHILDREN=accounts-board.sh` (child via `env bash` → 5.3.15) | /bin/bash 3.2.57 (its shebang) | 300 | **89.3** | 222.2 | **411.0** | 506.6 | 22.38 37.00 47.73 → 46.42 40.50 48.15 |
| 3 | bare accounts-board.sh (interleaved control) | bash 5.3.15 | 300 | **67.5** | 159.7 | **279.1** | 308.7 | same batch |
| 4 | activation-watch.sh | /bin/bash 3.2.57 (shebang) | 50 | 168.5 | 245.6 | 294.4 | 294.4 | 46.42 40.50 48.15 → 45.71 40.69 48.08 |
| 4 | escalation-watch.sh (interleaved) | /bin/bash 3.2.57 (shebang) | 50 | 105.4 | 163.8 | 296.7 | 296.7 | same batch |
| 4 | frontier-status.sh | bash 5.3.15 (`env bash` shebang) | 50 | 42.6 | 82.8 | 146.6 | 146.6 | 45.71 40.69 48.08 → 44.06 40.43 47.95 |
| 4 | config-mirror-assert.sh, `CLAUDE_CONFIG_DIR` unset (exit-0 path only) | /bin/bash 3.2.57 | 50 | 3.9 | 5.8 | 97.5 | 97.5 | same batch |
| 5 | dispatch over the 5 read-only children (activation, escalation, board, config-mirror[unset], frontier) | /bin/bash 3.2.57 | 50 | 178.6 | 227.3 | 273.4 | 273.4 | 44.06 40.43 47.95 → 43.03 40.32 47.82 |
| 6a | accounts-board.sh original | /bin/bash 3.2.57 | 100 | 1159.4 | 2247.6 | 3867.4 | 6522.3 | 44.58 40.36 47.27 → 47.24 47.61 49.41 |
| 6a | /tmp variant: line 164 → `case` glob (interleaved) | /bin/bash 3.2.57 | 100 | **91.4** | 152.6 | 237.3 | 324.9 | same batch |
| 6b | accounts-board.sh original | bash 5.3.15 | 150 | 121.5 | 159.9 | 207.9 | 216.6 | 47.24 47.61 49.41 → 69.24 52.72 51.18 |
| 6b | /tmp variant (interleaved) | bash 5.3.15 | 150 | 116.5 | 147.1 | 198.5 | 203.4 | same batch |

Floor controls (batch of 20, load ~70): `#!/bin/bash exit 0` p50 2.9 ms; one `jq -nc` p50 9.2 ms.

| board path | systemMessage bytes | ANSI bytes | ANSI share | est. tokens (bytes/3.5) | est. tokens, ANSI stripped | hook stdout (JSON-escaped) |
|---|---|---|---|---|---|---|
| fresh | 2,193–2,199 (2,089 chars, 16 lines) | 1,306–1,308 (114 sequences) | **59.5%** | **~628** | ~255 | 2,799–2,805 |
| stale | 2,490 | 1,306 | 52.4% | ~711 | ~338 | — |

## R1: hook latency and token cost

- **Answer.** The production board is fast and the 3.2 board is slow, and one line causes the difference.
  - **Interpreter:** all 16 live `claude` processes resolve `bash` to 5.3.15 (`ps eww` PATH probe, r1 §b). The dispatcher is always 3.2 (`#!/bin/bash`), but it execs the board through `#!/usr/bin/env bash`, which resolves to 5.3.
  - **The slow line:** `${body//[[:space:]]/}` at `hooks/accounts-board.sh:164` is superlinear on 3.2: 0.87 s at 1×, 6.47 s at 2×, 43.6 s at 4×.
  - **Dispatcher overhead:** p50 +21.8 / p99 +131.9 ms.
  - **Token cost:** 0 model tokens; the ~628 tokens is a hypothetical cost if the board moved to `additionalContext`.
- **Receipts.** r1 rows 1–6.
  - **[re-verified]** `grep -n 'space:' hooks/accounts-board.sh` shows `164:if [ -z "${body//[[:space:]]/}" ]; then`.
  - **[re-verified]** Spot timing at load 71: `/bin/bash` original 1.74 s and 2.43 s, against 0.00 s and 0.01 s for the `case` form. bash 5.3 original: 0.01 s (`/usr/bin/time -p`).
  - **[re-verified]** On five inputs (empty, spaces, `\n\t `, `x`, ANSI-wrapped space) the `case` form gives the same EMPTY/NONEMPTY verdicts. `shellcheck` on the variant returns rc 0 (PATH `shellcheck`, the `~/.claude/bin` wrapper).
  - **[re-verified]** `grep -a -o 'hook_system_message:[^,]{0,30}'` on `~/.claude-284/.../claude.exe` gives `1 hook_system_message:()=>[]`.
- **Residual uncertainty.**
  - The full nine-child chain is unmeasured, because four children write state.
  - All arms ran at load 22–70 on 10 cores, with no quiet-box baseline.
  - The first-of-day latch path was not timed.
  - Claude Code's own spawn wrapper is estimated at about 3 ms and was not measured.
- **Dissent (verbatim).**
  - adv: "every added word raises p50 unless that line is fixed first", and the blank check is at "~line 128".
  - Disposition: true on 3.2 only. On 5.3 a 4× board costs 0.05 s (r1). The line is 164 **[re-verified]**.
  - The plan's R1 text ("under `/bin/bash` 3.2 as the harness runs it") describes the dispatcher, not the board child.

## R2: wire precision

- **Answer.**
  - **Grid:** the wire is on a 0.01 grid (~97%). Our code does not round it (`_wire_float` = `float(h[name])`, `:1260`).
  - **Rounding:** the server rounds to the nearest hundredth and caps a non-refused window at 0.99 (~80%).
    - The E−W split is 0:1 ≈ 50/50 (r2 §3a).
    - The band-width ratio (W99E100 / W99E99) is 2.34 against a predicted 2.0 for round+cap and 1.0 for floor (r2 §3b).
    - The bundled spend-gateway applies `Math.min(o,0.99)` to the same header family.
  - **What a reading means:** `0.99 allowed_warning` with endpoint 100 means headroom in (0, 1 pp). With endpoint 99 it means true use in [98.5, 99].
- **Receipts.**
  - **[re-verified]** Python scan of `account-utilization.jsonl`: 4,142 wire readings, `{2 dp: 429, 1 dp: 3713}`, none longer.
  - **[re-verified]** Pairs at ≥0.98: `(100, 0.99, aw) 88`, `(99, 0.99, aw) 18`, `(99, 0.98, aw) 30`, `(100, 1.0, rejected) 1891`. Never `1.0` allowed.
  - **[re-verified]** `math.floor(wv*1000)/10` prints `.0` for every k/100 with k in 0..101, so the tenth is always `.0`.
  - **[re-verified]** `math.floor(wv*100)` is **wrong for 0.29, 0.57 and 0.58** (it gives 28, 56, 57), and 0.57 is an observed value (r3a: `(0.57, 58)×24`). `round(wv*100)` is exact for all k.
- **Residual uncertainty.**
  - No literal header string is on disk, so `"0.99"` cannot be told from `"0.990"`.
  - The `surpassed-threshold` header is unrecorded, so the allowed_warning threshold is somewhere in 0.75–0.91.
  - No live wire read was made.
- **Dissent (verbatim). The headroom bound for (endpoint 100, wire 0.99):**
  - r2: "(0, 1 pp); mean ≈ 0.5 pp on a uniform prior".
  - adv: "`(100, 0.99)` ⇒ used ∈ (99.0, 99.5) pp, headroom **< 0.5 pp**", on the hypothesis "wire rounded to nearest" with no cap.
  - r3a: "this fits a server that floors the figure and an endpoint that rounds it … at most 0.5 pp of the week left".
  - r2 rejects round-without-cap ("predicts 1.0-`allowed_warning` rows … None appear in 6,280 rows") and disfavours floor (ratio 2.34 vs 1.0).
  - **Not reconciled.** Every hypothesis agrees on two things: the lower bound is 0, and "about 1%" is at best the maximum. "Under 1%, possibly none" is true under all three, so the ranked changes use it.

## R3: dwell at 0.99 before refusal, by live-session count (r3a and r3b)

- **Answer.**
  - **Base rate:** 10/10 clean episodes (4 accounts, 09-22 to 10-06) ended in refusal, none in reset. The wait from the first 0.99 read to the first session refusal was median 47.3 min, p10 17.5, p90 145.1, range 17.5–174.3.
  - **k does not predict it:** Spearman(k, dwell) = −0.20 (n=10). At k≥11 the waits were 17.5, 22.3, 145.1 and 174.3 min.
  - **Burn does:** trailing-60-min burn ρ = −0.93. k_work ρ = −0.83 (n=8).
  - **The steady quantity:** 5h-meter points spent between the first 0.99 read and the `rejected` read were 3–6, median 4 (n=10).
  - **On-disk signal:** a refusal is on disk within 2 s in the StopFailure marker store (13/13 wire-era onsets). It was never contradicted by the wire (0/197).
- **Receipts.**
  - r3a episode table and Spearman table; r3b lag table.
  - **[re-verified]** next3 rows: 03:08:26 `s 2, w 99, 0.99 aw`; 03:55:54 `s 3, w 100`; 06:01:45 `s 7, w 100, 0.99 aw, k 11, kw 4`; 06:08:11 `1.0 rejected`. That is 5 points spent since the first 0.99 read and 4 since the endpoint reached 100.
  - **[re-verified]** `rate_limit__next3.jsonl:45`: `"ts":"2026-10-06T06:02:42Z" … "session_id":"e131c8d2-…"`.
  - **[re-verified]** `claude-accounts.log`: `06:01:41.856884 … 7d 0.99 allowed_warning` → `06:03:49.210836 … 7d 1.0 rejected`.
- **Residual uncertainty.**
  - n=10 over 15 days; p10 and p90 are single order statistics.
  - `session_pct` is an integer (±1 point).
  - k_work is None on 29 of 105 readings.
- **Correction across slots.** r3a's sweep-gap figures in §(c) (spacing 368–463 s; "accepting" printed 0.1–7.9 min, median 2.2, after the first refusal) are measured on the decimated jsonl. On the probe log the producer lag is median 67.5 s, max 472.7 s (r3b), and the series doubles it (r3b: series median 139 s). Use r3b's figures.
- **Dissent (verbatim).**
  - adv: "11/11 … durations 19 … 180 min (median 50); per-row hazard … 8.5%".
  - r3a: "10/10 … median 47 min" to the session refusal, and 50.2 to the first `rejected` row.
  - These are the same data with different endpoints (adv includes episode 0 and ends at the sweep row). They are consistent.

## R4: cadence and tick cost

- **Answer.**
  - **Period:** 180 s plus run time. launchd re-arms at exit: exit-to-spawn was 180.009–180.047 s on 112 intervals, and spawn-to-spawn p50 185.6 s.
  - **Reads:** next3 was wire-read on 71/71 swept ticks. 0 HTTP 429 lines on 10-06.
  - **QoS:** ProcessType Standard.
  - **Tick wall time:** p50 5.6 s, p90 23.2 s. Census-walk overruns drive it (p50 18 s against 4.3 s).
  - **Defect:** at `:5835` the name `deadline` is rebound to `time.time()+…` and then passed to `_arm_sweep_bound` (`:5861`). That function subtracts `time.monotonic()` (`:5750`), giving ~1.79e9 s, above XNU's 1e8 s limit, hence EINVAL.
- **Receipts.**
  - r4 launchd log extract and tick table.
  - **[re-verified]** `grep -n` shows `5835: deadline = time.time() + _fresh_lock_wait_s(cfg)`, `5841: if time.time() >= deadline`, `5861: disarm = _arm_sweep_bound(deadline)` and `5750: signal.setitimer(… max(deadline - time.monotonic(), 0.01))`. The other `deadline = time.time()` at `:5696` is local to `_acquire_lock` and harmless.
  - **[re-verified]** The err log tail ends `signal.ItimerError: [Errno 22] Invalid argument`, mtime `2026-09-30T17:02:42-0500`.
  - **[re-verified]** `record_utilization` returns 0 when `time.time() - st_mtime < 300` (`:5510`).
- **Residual uncertainty.**
  - The non-keepwarm callers that swept at 06:03:49 and elsewhere are not attributed.
  - The out log has no timestamps.
  - The 06:04:47 board text was not captured.

## R5: spending ticks by expected information

- **Answer.** Prioritising polls cannot help.
  - The fan-out is concurrent and the board waits for every probe (`:2560-2576`).
  - The endpoint is pinned at 100 through the whole band.
  - The 429 budget is per token.
  - Only one account was in `allowed_warning` in 185 of 187 five-minute bins.
- **What could help.** Today the producer's first `rejected` read comes 76 s after the first refusal on average (max 175 s).
  - **Event-triggered confirm read (Rule B):** 11 reads in 16.4 days, 10 of them confirming flips. It would cut the lag to about 3–10 s (estimated).
  - **Burn-gated hot cadence (Rule A):** +9.4 to +19 reads a day (about 235–475 tokens a day) for a mean lag of 32 s or 23 s.
  - Neither rule makes the 06:01:46 board true, because the flip came 55 s after that board was written.
- **Receipts.** r5 tables (a) to (d), `r5_marker_trigger.py`, `r5-armed-output.txt`.
- **Residual uncertainty.**
  - Whether a `rejected` read bills tokens, and the wire round-trip latency, are unmeasured.
  - Rule B and Rule A both need operator-owned plist work.
  - k and burn rest on 9–10 flips.

## R6: other renderers and routing

- **Answer.**
  - **Precision:** comes from one source, `board_eff` (`:6343` floor-to-tenth) → `pct_text` (`:6365`). It reaches the board cell, the `--readout` cell and the note.
  - **Present tense:** the note, `_wire_note`/`_plain_status` (silent on this row), and the board header's age, which is frozen at render.
  - **Same-board contradictions:**
    - `soonest_reset_line` prints "0% of the week left" from the endpoint integer (`:4420`).
    - `pace_line` keeps "⚠ WALL trajectory" after a confirmed refusal.
    - Bare `render_table` draws a full red `100%` from the endpoint (`:7023`).
  - **Routing:** no new sessions went to next3. General put it last via `_demote_thin`. Desk had it at tier 1 against tier-2 rivals and picked next2. Fable and recovery excluded it. The last route decision for next3 was 10-05T01:59Z.
  - **Latent hazard:** the desk picks next3 once every rival projects 5h ≥ 60%.
  - **Status line:** clean (`statusline.sh:598`).
- **Receipts.**
  - r6 sandbox replay: note word for word; desk scores 2.011333 / 2.008441 match `route.jsonl` 06:03:15Z.
  - **[re-verified]** `:4420` `left = max(0.0, 100.0 - r["weekly_pct"])`.
  - **[re-verified]** `:7023` `bar(r.get("weekly_pct")) + " " + pct(r.get("weekly_pct"))`.
  - **[re-verified]** The live board at ~06:41Z (`cat`, ANSI stripped) prints `next reset: next3 in 5.3h, 0% of the week left` and `next3 no strand — 1.03× burn, ⚠ WALL trajectory` under `next3 is out of weekly quota, confirmed`.
  - **[re-verified]** Commit `d6c4f8411` says "pct_text/pct_rgb decide text and colour once; the board's column, its bar and the /accounts table all use them" and "the three states read apart with colour off as well".
- **Residual uncertainty.**
  - Whether "the /accounts table" in d6c4f8411 means `render_table` (step 1) or `--readout` (step 2) is an interpretation.
  - Why handoff-fire placed work on next3 at weekly 94 (10-05T17:00:53Z) was not traced.
- **Cross-slot note.** r7's replay prints `➤ desk (bare claude) → next3`. That is a single-account fixture (r7 `setup()` has only next3), not evidence of routing harm. r6's full-fleet replay matched route.jsonl.

## R7: test pins and the control

- **Answer.**
  - **Pins to edit:** all wall wording and precision pins are in `tests/claude-accounts-wire-truth.bats`, plus freshness F-7 `:285`. Five assertions pin the defect: `:206`, `:207`, `:209`, `:341` (first half) and `:358`; the fixture `0.996` at `:336` goes with them.
  - **Ruling pins to keep:** `:338`, `:339`, `:341` ("100%" not in row), `:344`, `:347`, `:354-356`, `:359-360`.
  - **Wording constraints:** keep "not out of weekly quota" (`:242`, `:350`). No "wire" (`:216`). No "ʷ" or "rate-limit headers" (`:241`, `:352`).
  - **W-11 control:** replays the verbatim 06:01:45 row. It fails 10 of 15 checks on HEAD and passes on a sketch fix; three mutants kill it.
- **Receipts.**
  - r7 §4 (cc-bats for checks 1–5; a direct run for the final fragment).
  - **[re-verified]** `sed -n` of `:200-212` and `:330-362`.
  - **[re-verified]** `grep -c '^@test'` gives 33+11+7+95 = 146.
  - **[re-verified]** The incident row is at jsonl line **44577** (`grep -n`); r7 says 44578. The content matches.
- **Residual uncertainty.**
  - The final fragment's admitted cc-bats run is still owed (refused at load ~95).
  - **Three W-11 regexes conflict with the ranked wording** and must be edited before landing:
    - Check (2) accepts only `≥ ?99%|99%\+`. It must accept the chosen glyph (`99%`).
    - Check (3) bans any `\d+% of (the week|one 5-hour window)`. That bans the bound "under 1% of the week" as well as the point figure, and `0.5% of the week` matches too. Retarget it to point figures (`(about|roughly|~) ?\d+% of`), or word the bound without "of the week".
    - Check (4) demands a relative age (79–89 s or 1 min) in the note. A relative age baked into the pre-rendered board file goes stale with the file. Accept the read's clock time (HH:MM) instead.

## R8: outside view (r8a) and a zero-cost rejection signal (r3b)

- **Answer.**
  - **No surveyed meter promises headroom.**
    - IETF draft-11: "Clients MUST NOT assume that a positive available quota is a guarantee".
    - Anthropic's docs: limits are "not guaranteed minimums".
    - Near-empty gauges withdraw the number or bias it toward caution: GM "LOW", Dexcom LOW/HIGH, Apple's dropped battery ETA.
    - Nightscout prints the reading's age and escalates at 15/30 min.
  - **Wording patterns** (r8a): a bound with no tenth; "as of" plus age plus load; drop the headroom number at the wall; burn only as a labelled trend, never a point ETA.
  - **Zero-cost signal:** the StopFailure markers (r3b):
    - account taken from the hook's `CLAUDE_CONFIG_DIR`, so it survives a transplant;
    - read cost 0.107 ms p50;
    - 203/207 quota refusals covered;
    - folding the marker at the regular tick gains 0 s in the incident (the 06:04:46 tick already served the 06:03:49 `rejected` read). A kick is needed for any gain.
- **Receipts.** r8a survey URLs (§1); r3b candidate table (iii).
- **Residual uncertainty.**
  - The `allowed_warning` semantics come from third-party issue mirrors.
  - The marker hook stops appending at 500 lines (`CAP=500`), while `cc-limited` checks 5000.
  - `launchctl kickstart` against a running keepwarm instance is untested.
- **Dissent (verbatim).**
  - adv: "if anything, read ~/.reso/limit-recover/recon/facts/ filtered on contradicted=False … — or skip it".
  - r3b: "Reject for the board", citing three measured defects in the facts ledger; adv itself measured one of them (`next2.7d.json` blames next2 for 4ad354fc).
  - Disposition: use the markers, never the ledger.

## Hostile-review objections and their disposition

| # | objection (adv, verbatim head) | disposition | basis |
|---|---|---|---|
| 1 | "Defect #3 ('Cadence') is a measurement artifact, not a producer defect" | **Upheld.** Correction: the producer lag is 67.5 s from the first refusal (06:02:41.7), not "45 s" (adv anchored on 4ad354fc). | r4 launchd log; **[re-verified]** probe lines |
| 2 | "'About 1% left' discards the endpoint integer … headroom **< 0.5 pp**" | **Partly upheld.** "About 1%" is the upper bound (all slots agree). The tighter < 0.5 pp needs round-without-cap, which r2 rejects (0 of 6,280 rows read 1.0 while allowed). Wording uses "under 1%, possibly none", true under every hypothesis. | r2 §3; **[re-verified]** pairs table |
| 3 | "The bound text '≥99%' is already taken by the unconfirmed state" | **Upheld, with a second reason.** Under round-to-nearest, (E 99, W 0.99) means u ∈ [98.5, 99], so "≥99%" is not a guaranteed lower bound on those 18 rows. Pick `99%` (the server's own figure) over adv's `~99%`; that choice is the operator's. | r2 §4; **[re-verified]** 18 rows; `board_eff` uses the wire whatever the endpoint reads (`:6339-6343`) |
| 4 | "The wording is not the defect that cost anything; the plan treats a behaviour as a display bug" | **Upheld as fact:** no routing harm (r6, r3b: 0 assignments in the windows). **Policy line deferred to the operator:** 10-01 makes spending the last 1% deliberate, and saying "recovery will move them" is a policy claim the board may not own. | r6 routing trace; r3b (ii) |
| 5 | "The honest form is a forecast from data the producer already holds" | **Partly upheld.** The base rate (10/10, median 47) and points-spent (3–6) are supported (r3a). A point ETA is rejected: a burn ETA under-predicts by a median 2.2× (r3a), and no surveyed product prints one (r8a). | r3a (b) and (d); r8a §3.6 |
| 6 | "R6's renderer list is incomplete; the board contradicted itself" | **Upheld against the plan.** r6 rows 10–11 already cover both lines. ⚠ WALL after a refusal was observed on the live board. | **[re-verified]** live board 06:41Z |
| 7 | "The on-disk rejection signal already exists and already mis-attributes" | **Upheld for the facts ledger; rejected as "skip it".** The markers are transplant-safe (0/197 contradicted). The gain needs a kick (r3b (d)). adv's "≤3 min at best" matches the lag B max of 472.7 s. | r3b (iii) and (d) |
| 8 | "The hook's cost is super-linear in board bytes" | **Upheld on 3.2; overstated for production** (5.3 in 16/16 sessions). The line is 164, not ~128. The fix stays: it is cheap, and it removes the 3.2 coupling between saying more and keeping p99 flat. | r1; **[re-verified]** spot timing |
| 9 | "wire_at is stamped only on the throttled-substitute path"; "print k_work" | **Upheld** on both counts. Print "11 live (4 working)". | **[re-verified]** `:1961` is the only writer; `:2477-2482` has no stamp |

## Ranked changes

Order: the incident's minimal fix (precision and wording, plus what they need to stay inside H1) comes first; the rest follow by conviction × value. "Do not" rows are constraints on the implementation.

| rank | change | file:function | conv % | evidence | constraint check |
|---|---|---|---|---|---|
| 1 | Nearly-out cell prints the server's whole percent: `board_eff` returns `float(min(round(wv*100), 99))` for a non-rejected wire value, and `pct_text` prints `99%`. `≥99%` (unconfirmed) and `100%` (refused) stay as they are. Rewrite the docstring and legend so "99.6%" becomes "99%". **Use `round`, not `floor`** | `bin/claude-accounts:6343` board_eff; `:6365` pct_text; comments `:6333`, `:6352-6356` | 90 | 0/4,142 readings >2 dp **[re-verified]**; a tenth is always `.0`; `floor(wv*100)` misprints the observed 0.57 as 56% **[re-verified]**; `≥99%` collides with the unconfirmed text and is not a bound when E=99 | H1 pass (rendered in the producer; board shrinks 2 bytes). H2 pass. H3 pass (three distinct texts; bar `▆▆▆▆▆▆▆▁` and orange untouched; 100% only on refusal). H4 n/a |
| 2 | Delete both point headroom figures from the nearly-out note: "about N% of the week left" and "roughly N% of one 5-hour window" | `:6747-6750` readout_lines | 92 | From endpoint 100 to refusal, 3–4 5h-pp remained (n=8, never 5; r2). At 06:01:45, 5 points had been spent since the first 0.99 read **[re-verified]**. Every slot agrees | H1 pass (fewer bytes). H2 pass. H3 n/a (the note, not the cell). H4 n/a |
| 3 | Rewrite the note in the past tense with the read's clock time and the load. Keep the lead "not out of weekly quota". Shape: "…: Anthropic's server read 99% used at HH:MM and was still accepting work then; 11 live sessions (4 working) on it; under 1% left, possibly none". No "wire", "ʷ" or "rate-limit headers"; wraps within 76 cells | `:6745-6750` readout_lines | 85 | 60 s from read to the first refusal **[re-verified]**; IETF "MUST NOT assume" (r8a); k vs k_work (r3a); pins `:242`, `:216`, `:241` | H1: board +~60–100 bytes. Unmeasurable on 5.3 (4× = 0.05 s); superlinear on 3.2, so it **lands only with rank 4**. H3 pass. H4 n/a |
| 4 | Hook blank check: `if case "$body" in *[![:space:]]*) false ;; *) true ;; esac; then` | `hooks/accounts-board.sh:164` | 92 | r1 6a/6b: same output; 3.2 p50 1159.4→91.4 ms; 5.3 121.5→116.5 ms. **[re-verified]** semantics on 5 inputs, shellcheck rc 0, spot timing 1.74/2.43 s → 0.00/0.01 s | H1 pass (still a pure file read; p50/p99 measured not to rise on 5.3 and to fall on 3.2). H2–H4 n/a |
| 5 | Add the W-11 control (r7 fragment) and run it red on HEAD first. Edit W-6 `:206/:207/:209` and W-10 `:336` (0.996→0.99), `:341` (first half) and `:358`. Retarget W-11 checks (2), (3) and (4) as in R7 above | `tests/claude-accounts-wire-truth.bats` after `:364` | 85 | r7: 10/15 checks red on HEAD; 3 mutants killed; replay matches the incident sentence word for word | Pins H3 (bar, colour, 100%). Test-only |
| 6 | `soonest_reset_line`: compute "left" from a wire-aware bound ("under 1%") and say "demoted for new work" when the row is thin_demoted. `pace_line`: drop "⚠ WALL trajectory" once the server has confirmed the refusal | `:4420` soonest_reset_line; `:4500` pace_line | 72 | Live board shows "0% of the week left" and ⚠ WALL for a refused account **[re-verified]** | H1 pass (bytes ±). H3 pass. Core pins `:2058`, `:2065-2069` reuse pace_line's figure |
| 7 | Rename the lock-wait bound in get_data's degrade branch (`deadline` → `wedge_at` at `:5835` and `:5841`). Add a bats control (no cache, `lock_wait_s 1`, helper holds the flock ~3 s; assert rc≠1 and no ItimerError) | `:5835`, `:5841` get_data; new test in `claude-accounts-fresh-lock-bound.bats` style | 93 | Traceback **[re-verified]**; code path **[re-verified]**; EINVAL above 1e8 s measured (r4) | Producer-only. H1–H4 pass |
| 8 | Correct the plan: defect 3's premise is wrong (sweeps p50 185.6 s; 6 min is `UTIL_MIN_INTERVAL_S`); the first refusal was 06:02:41.736Z e131c8d2; the board runs under 5.3; drop "cadence fix" from W1 | `docs/plans/SESSIONSTART_READOUT.md:20`, `:27`, `:35`, `:50` | 93 | r4 (112 intervals); r3b; **[re-verified]** markers and probe lines | Docs only |
| 9 | Stamp `row["wire_at"]` on ordinary wire reads | `:2479` probe_account | 75 | Only `:1961` writes it **[re-verified]**; served or patched caches (ranks 12–13) need a per-row read time | H1–H4 pass; 0 tokens |
| 10 | Re-baseline R1 after the change with the same harness, both interpreters interleaved. Judge "p50/p99 must not rise" on the 5.3 arm and report 3.2 separately | W1 gate | 75 | 16/16 live sessions resolve to 5.3 (r1 §b) | Defines H1's measurement |
| 11 | Bats case: run the hook under `/bin/bash` on a 2–4× board, with a structural bound | `tests/accounts-board.bats` near `:282` | 70 | Test 14 runs bash 5 on a small fixture; rule "Deployment interpreter ≠ yours" | Test-only |
| 12 | On the first quota marker, the StopFailure hook does a bare `launchctl kickstart` of keepwarm behind an O_EXCL latch keyed `<acct>__<win>`. The kicked tick folds the marker as "a session was refused at HH:MM" (note only; the cell stays nearly-out until a wire read confirms) | `hooks/stop-failure-marker.sh` limited arm; `bin` `--keepwarm` `~7795-7810` | 55 | r3b: ≤2 s, 0/197 contradicted, 125 s → ~2–6 s (estimated) | H1 pass (SessionStart hook untouched). H3 pass if the cell does not print 100% from a marker. H4 pass (a served tick reads no wire) |
| 13 | Rule B: a refusal-triggered wire-only confirm read for accounts read in the last 15 min | new mode near `:7754-7826`; trigger from the marker hook or WatchPaths | 45 | r5: 11 reads in 16.4 days, 10/10 flips confirmed, ~0–275 tokens | H4 pass (in-band only). H3 pass (a server-confirmed `rejected` prints 100% legitimately). Needs an operator plist |
| 14 | `record_utilization`: bypass the 300 s gate when any wire status changed since the previous snapshot | `:5510` | 65 | r4: the series put next3's first `rejected` 262 s late | H1–H4 pass; 0 tokens |
| 15 | Bare `render_table` weekly and 5h cells go through board_eff/pct_text/pct_rgb; never a full bar unless exhausted is True | `:7023` render_table | 60 | **[re-verified]** it uses the endpoint `weekly_pct`; d6c4f8411 names "the /accounts table" | H3: arguably required by 10-03 |
| 16 | Marker cap: treat ≥500 lines as degraded; align `cc-limited` MARKER_CAP 5000 with the hook's CAP 500 | `bin/cc-limited:93`; `hooks/stop-failure-marker.sh` CAP | 65 | r3b blocker 1 | Pass |
| 17 | Add ISO `ts=` to the keepwarm out-log line | `:7821` | 70 | r4: the out log is untimed | Pass |
| 18 | Record `…-surpassed-threshold` and the raw utilization string in the wire dict and the jsonl row | `:1316-1327` fetch_wire_limits; `:5542-5545` | 60 | r2 open questions | H4 pass (same response, 0 extra calls) |
| 19 | Producer computes the first-≥99% time and the 5h points spent since, and the note cites past refusals at 3–6 points (or the base rate: 10/10, median 47 min) | producer near board_path `~5569`; note | 50 | r3a: steadiest quantity, n=10 | H1 pass (producer-side). Integer resolution; small n |
| 20 | `_wire_note`/`_plain_status` in the past tense with the read time; edit F-7 `:285` | `:6098-6112` | 55 | r6 row 9 (same defect class, silent on the incident row) | Pass; needs a second control (substitute row at 0.99) |
| 21 | Hook puts the file's age into board line 1 while the board is fresh | `hooks/accounts-board.sh:153-188` | 50 | r6 row 13: line 1's age is frozen at render | H1: pure string op, but hook output changes; re-measure p50/p99 and accounts-board tests 1–14 |
| 22 | Keepwarm-only longer lock wait (e.g. 60 s, under alarm 225) instead of degrading to a grace cache | `:5825` | 45 | r4 2/113 ticks; r5 32/2000 ticks older than 180 s | Pass |
| 23 | Re-render the board (detached) when any sweep's wire verdict changes | after `:5873` cache_write | 35 | r4: 58 s board lag at the incident (estimated) | H1 pass; render cost unmeasured |
| 24 | Desk: rank a near-wall row by time to the wall, below tier 0 but still routable | `:4795-4829` desk_keys | 40 | r6: hazard measured in a scenario only | H3/10-01: a demotion, not an exclusion; W-1 pin `:104-108` |
| 25 | Downgrade the nearly-out claim to unconfirmed when the read is older than a threshold | renderer | 40 | r8a Nightscout; thresholds unmeasured | Pass |
| 26 | Correct the SDK-doc paraphrase comment | `:1226-1228` | 50 | r2 §3b last bullet | Pass |
| 27 | Rule A: burn-gated hot wire cadence | new plist | 15 | r5: +235–475 tokens/day, nothing offsets it | H4 technically pass; adds inference |
| 28 | `weekly_headroom` returns a midpoint (0.005) | `:1358-1369` | 5 | — | **FAILS H3/10-01**: `w_rem <= WEEKLY_FLOOR` (`:4698`, `:4917`, **[re-verified]**) would exclude the account; breaks the W-1 pin |
| 29 | desk_why uses the wire-first 5h figure | `:6229-6233` | 25 | Cosmetic (r6 row 12) | Pass |
| D1 | Do not key any wall timing claim on k (pane census) | wording | 85 | ρ −0.20, n=10 (r3a) | — |
| D2 | Do not fork `cc-limited`/`lr-fleet`, scan transcripts, or read the recon facts ledger on the hook or board path | hook, `bin` | 90 | ~1 s per call; 6.5 s scan; 3 ledger defects (r3b) | Guards H1 |
| D3 | Do not shorten StartInterval, re-order polls, or poll usage faster for the hot account | plist; collect `:2511-2616` | 88 | r5; plist 2026-08-11 throttle | Guards the 429 budget and H4 |
| D4 | No point time-to-exhaustion on any surface | renderers | 75 | r8a (Apple); r3a 2.2× under-prediction | — |

## Changes at or below 90% and what would raise them

- **1 (90):** the operator picks the cell glyph from `99%` / `~99%` / `99%+` / `≥99%`. The slots split: r2 `99%`; r6 `99%+` or `99%`; r7 `≥99%` with the bar as the colour-off distinguisher; r8a `≥99%` or `99%+`; adv `~99%`. Also needed: W-11 green under an admitted cc-bats run. Then 95.
- **3 (85):** the operator accepts the sentence; W-11 checks (3) and (4) retargeted and green; the 76-cell width check passes on the real row; the post-change R1 re-measure shows no rise on 5.3.
- **5 (85):** the regex retargets above, plus one admitted `cc-bats -f W-11` run red on HEAD and green after (r7 §4 owes it).
- **6 (72):** a replay of the 06:08:11 refused row shows the drain line and the pace line agreeing with the note; core `:2058`/`:2065-2069` stay green.
- **9 (75):** decide whether the note's read time comes from `wire_at` or from the cache `ts` (r7 says the cache ts already gives 79 s). Measure the gap between them on census-overrun ticks (up to ~15 s, r4).
- **10, 11 (75, 70):** the operator agrees that the 5.3 arm is the production gate; the 3.2 test stays deterministic under load (structural bound, not wall clock).
- **12 (55):** measure `launchctl kickstart` against a running keepwarm instance and repeated kicks; get an operator ruling on whether a session-observed refusal may print "100%" (r3b blocker 2); replay the marker fold over the 13 wire-era onsets.
- **13 (45):** measure whether a `rejected` wire read bills tokens, and the wire round-trip time; get the operator's plist approval.
- **14, 16, 17, 18 (60–70):** none are needed for the incident. Each rises with a concrete consumer (R3-style re-analysis, a cc-limited degraded flag, out-log timing, threshold calibration).
- **15 (60):** the operator says whether 10-03 covers the bare human table.
- **19 (50):** more episodes (n>10). Measure whether points-spent stays at 3–6 on accounts with a different session mix.
- **20 (55):** a control with a substitute row at 0.99; F-7 edited.
- **21 (50):** an R1 re-measure with the age-in-line-1 variant; accounts-board.bats 1–14 green.
- **22, 23 (45, 35):** measure render cost on interactive callers. r4 says 25% and "measure first"; r5 says 50% for a detached render. Dissent unresolved.
- **24, 25 (40):** routing replay over the 10 episodes with the demotion; measured age thresholds.
- **27, 28:** do not do.

## Missing axes

- **Slots:** none failed to return. The plan's R8 second half (the on-disk signal) was answered by r3b, not by an r8 slot.
- **Skeptic stage over this synthesis:** not yet run when this draft was written (adv reviewed the plan, not the draft); it ran afterwards — see the last section.
- **Full dispatch chain p50/p99:** four state-writing children are unmeasured, as is the account-dir path of config-mirror-assert.
- **Quiet-box baseline:** every R1 arm ran at load 22–70.
- **Whether a `rejected` wire read bills tokens; wire round-trip latency; whether /v1/messages throttles an extra request.**
- **Literal header format** (`"0.99"` vs `"0.990"`) and the `surpassed-threshold` value: no live read was made.
- **Board history:** there is no board archive, so the 06:01:46 header and the 06:04:47 board are inferred, not observed.
- **`launchctl kickstart` behaviour and throttling** for ranks 12 and 13.
- **Operator rulings owed:**
  - the cell glyph;
  - whether a session-observed refusal may print "100%";
  - whether the board may state recovery policy ("sessions will be moved");
  - whether 10-03 covers `render_table`.
- **cc-bats run of the final W-11 fragment** (refused under load twice).
- **Attribution of non-keepwarm sweepers** (06:03:49 and others), and **why a fire landed on next3 at weekly 94** (10-05T17:00:53Z).
- **Render cost of re-rendering the board from interactive callers** (rank 23).

## Skeptic stage and W1 decision set (lead, 2026-10-06)

The skeptic stage ran after the draft above: a red-team on a different model (`slots/skeptic-redteam.md`, Fable 5.1) and a conviction audit (`slots/skeptic-conviction.md`, Opus 5.5 xhigh). Neither refuted a top-five change. The conviction audit refuted six convictions as mis-set (ranks 3, 6, 9, 10, 19, 25, 26 adjusted; rank 3 only for its load clause). This section is the lead's final call; it overrides the draft's numbers.

### Implemented in W1 (each above 90% after the skeptics)

| # | change | where | conviction | why it clears 90% |
|---|---|---|---|---|
| 1 | Nearly-out cell prints the server's whole percent (`99%`), `round` not floor, capped at 99; `pct_text` drops the tenth branch | `board_eff`, `pct_text`, the three-state comment | 92 | R2: hundredths, rounded, held at 0.99 while allowed (0/6,793 with a third decimal). `99%` is the server's own figure; `≥99%` (rejected option) would claim "at least 99" when 0.99 covers ~98.5 up, and would merge with the not-confirmed glyph. Three texts stay distinct: `100%` refused / `99%` nearly out / `≥99%` not confirmed, so the 10-03 inline ruling holds without colour. The colour-off overlap with a plain endpoint-99 row (red-team's concern) is two states that both truthfully read 99% and neither is a refusal. |
| 2 | Delete both point headroom figures from the nearly-out note | `readout_lines` wall note | 93 | Both were the band's ceiling and already spent at the incident (5 of the 5h meter's points gone since the first 0.99 read; refusals historically after 3-6). The frozen scope bans them. |
| 3 | Note in the past tense, with the read's LOCAL clock time (from the sweep's cache `ts`, matching the header clock) and the load ("11 live sessions (4 working)"; the working clause omitted when `k_work` is unknown); the lead stays "not out of weekly quota", now "was … at HH:MM"; still gated on `weekly_pct >= 100` | same note | 91 | The frozen scope requires the age and the load beside any "accepting". Absolute clock time rather than "N s ago": a relative age frozen into a file goes stale exactly the way "still accepts work" did. The conviction audit's objection (k is a weak predictor, ρ −0.20) is met by printing `k_work` (ρ −0.83) beside it and making no timing claim from either. No amount is stated ("that reading cannot say how much was left, and it may be none"), so the (E99, W0.99) band the red-team raised stays outside the note's gate and gets no false sentence. |
| 4 | Hook emptiness test by `case` glob instead of `${body//[[:space:]]/}` | `hooks/accounts-board.sh:164` | 95 | Same verdict on 32/32 edge inputs under both interpreters (skeptic); 3.2 p50 1159→91 ms; decouples board length from startup time. |
| 5 | W-11 control replaying the verbatim 06:01:45Z row (both surfaces, `k_work` 4 and None), plus the defect pins edited (W-6, W-10 incl. the never-observed 0.996 fixture → 0.99) | `tests/claude-accounts-wire-truth.bats` | 93 | Mandated by the plan; R7 measured the fragment red on HEAD. |
| 6 | `get_data` no-cache fallback names its epoch bound `wedge_at`, so `_arm_sweep_bound` stays a no-op without `--max-wait`; control test 6 | `bin/claude-accounts` `get_data`; `tests/claude-accounts-fresh-lock-bound.bats` | 95 | Deterministic: epoch − monotonic ≈ 1.8e9 s > macOS's 1e8 s itimer limit → EINVAL (err log 2026-09-30). |
| 7 | Correct the SDK-doc paraphrase and the "~5.2% of a 5-hour window" comment | `bin/claude-accounts` wire-truth comment block, wall-note comment | 92 | Settled by the binary's own string (lowercase "rounded", about event timing) and R2's in-band rate. Comment-only. |
| 8 | Correct the plan: intake defect 3's cause (recorder gate, not cadence), the first refusal (06:02:42Z StopFailure marker, sid e131c8d2 — the durable source; the transcript is gone), the board child's interpreter (bash 5.3) | `docs/plans/SESSIONSTART_READOUT.md` | 93 | Measured (R4, R3b, R1). |
| 9 | Re-measure R1 with the same harness, old and new hooks interleaved, both interpreters | `r1-harness.sh` | 95 | Mandated; see "R1 after the change" below. |

### Not implemented: at or below 90%, and why

- **Desk routing on the last 1%** (rank 24, 30-40%): rank a near-wall account by time to the wall, below tier 0. A routing policy change on the operator's 2026-10-01 ruling, measured only in a scenario. Filed for the operator with `cc-decide` (see the plan's Status).
- **Refusal-on-disk signal into the board** (ranks 12-13, 40-55): StopFailure markers are fast and were never contradicted (0/197), but the existing kick arm is default-OFF for a stated reason (`hooks/stop-failure-marker.sh:284-289`), a bare kickstart is a no-op on a running tick, and whether a marker may print "100%" is an operator question. Research-grade; not driven.
- **`wire_at` on ordinary reads** (rank 9, 45-60): not needed (the wire is never inherited, so the cache `ts` is the read time within one sweep) and it would wake a dormant `--place` branch (`_place_fact_live`).
- **Drain/pace line rewording, render_table through the three-state functions, `_wire_note` tense** (ranks 6, 15, 20; 50-68): consistency work whose ruling coverage is disputed (the 10-03 "/accounts table" most plausibly means `--readout`); the drain line's "0% of the week left" is true on a refused account, which is the case the live board showed.
- **Recorder gate bypass on a status change, keepwarm out-log timestamp, larger-board 3.2 test, marker cap alignment** (ranks 11, 14, 16, 17; 65-75): low-cost but not settled above 90; recorded here as the next increments.
- **Rejected outright:** a midpoint `weekly_headroom` (rank 28; excludes the account at WEEKLY_FLOOR), a burn-gated hot wire cadence (rank 27; tokens for nothing), shortening StartInterval (rank 32).

### R1 after the change (measured 2026-10-06 07:04-07:07Z)

Same harness (`r1-harness.sh`), same sandboxing (DL_DIR copy, fresh board copy, the R1 startup payload). Old arm = `git show HEAD:hooks/accounts-board.sh` before W1; new arm = the W1 hook; each in its own directory with `lib/origin-identity.sh`, runs INTERLEAVED old/new so load drift hits both. Load was high and is reported, not hidden.

| interpreter | arm | n | p50 | p90 | p99 | max | load 1-min start → end |
|---|---|---|---|---|---|---|---|
| bash 5.3.15 (what Claude Code runs, 16/16 sessions) | old | 300 | 64.1 | 99.2 | 151.9 | 164.7 | 65.2 → 50.9 |
| bash 5.3.15 | **new** | 300 | **61.2** | 94.9 | **136.7** | 157.5 | same batch |
| /bin/bash 3.2.57 | old | 100 | 904.9 | 1289.9 | 1897.7 | 2002.6 | 50.9 → 26.9 |
| /bin/bash 3.2.57 | **new** | 100 | **52.7** | 85.4 | **128.3** | 149.4 | same batch |

Verdict: p50 and p99 did not rise on either interpreter (bash 5.3: −2.9 / −15.2 ms, inside load noise; /bin/bash 3.2: −852 / −1769 ms). The hook still forks no `claude-accounts` and makes no network call (the W1 hook diff is the one emptiness line; `tests/accounts-board.bats` pins the no-fork contract).
