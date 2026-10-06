# R5: spending the producer's reads by expected information

Scope: can `com.claude.accounts-keepwarm` spend its reads where the information is (an account near its wall with live sessions) without adding tokens, and how much fresher would the verdict at the wall be? Read-only. No wire reads were made. Code is cited at worktree HEAD `b87e6da64`; `bin/claude-accounts` is byte-identical to the live `~/.claude/bin/claude-accounts` (`diff -q`). The receipts (scripts and outputs) are in `/tmp/ssr-research/r5_*.py` and `r5-*-output.txt`.

## Answer

- **Not by ordering or prioritising the sweep's polls.** The sweep polls every account at the same time, so there is no "first" to choose. At the wall the usage endpoint is pinned at `100` and tells us nothing. Its 429 budget is per token, so nothing can be moved between accounts (predecessor Q1). And in 185 of 187 five-minute bins only one account was in `allowed_warning`, so there is no queue to rank.
- **Yes at about zero added tokens, if the trigger is an event.** Fire one wire-only confirm read when the StopFailure hook writes a `rate_limit` marker for an account whose cached verdict is not yet `rejected`. Over 16.4 days that would have been **11 reads: 10 confirmed all 10 recorded flips and 1 did not.** At most one of them would have carried tokens (about 25), and none would have touched the usage endpoint, so no extra 429s. Today the producer's first `rejected` read comes **76 s on average after the first session refusal (p50 67 s, max 175 s)**. With the trigger, the estimate is **about 3–10 s**.
- **The token-costing alternative** is a faster wire cadence on accounts where burn says the flip is near. It adds 9–19 reads a day (about 235–475 tokens a day) and gives a mean lag of 32 s or 23 s.
- **Neither rule would have made the 06:01:46 board true.** The flip came about 55 s after that board was written. Faster reads shrink how long a wrong board stays up after the flip. They cannot make a present-tense claim on a snapshot true; only the wording (defects 1 and 2) can fix that.

## (a) How each tick chooses what to poll and wire-read today

| Step | Behaviour | Where |
|---|---|---|
| Cadence | launchd `StartInterval 180` runs `claude-accounts --keepwarm --max-age 90` under a perl `alarm 240`; Python adds `alarm(225)` | plist `launchd/staged/com.claude.accounts-keepwarm.plist`; `bin/claude-accounts:7785-7791` |
| Sweep or serve | Serves the cache when it is younger than `--max-age 90` (another caller swept recently). Otherwise it takes the single-flight lock. If the lock is still held after `lock_wait_s` 5 s, it serves a **grace cache of up to 600 s** and does not sweep. Reset evidence forces a sweep. | `:5796-5799`, `:5825-5829`, `:5709-5716`, `:5857`; `:7797-7799`; `accounts.json` `lock_wait_s 5`, `cache_grace_s 600` |
| Which accounts | **All of them, at once.** `ThreadPoolExecutor(max_workers=len(accounts)+1)`, and `ex.map` waits for every probe and for the census walk (budget 15 s) before anything is written | `:2560-2576`, `:795` |
| Usage poll | One request per account unless that account's shared 429 backoff is running. No in-call 429 retry. | `:2387-2392`; `:1170-1171`, `:1199` |
| Backoff | Per account, shared by every caller: 180 s, then 360 s, capped at 600 s; cleared on the next success | `:1824-1825`, `:1855-1864`, `:1867-1876`, `:1890-1895` |
| Wire read, normal path | Only when the endpoint reads `session_pct` or `weekly_pct` ≥ `WIRE_NEAR_WALL` (99.0) | `:1252`, `:1338-1344`, `:2477-2485` |
| Wire read, throttled or held | A substitute read when the row is stale and its last good reading was ≥ 90%, or it carries a stored rejection, or the window rolled. **The backoff does not hold it back.** | `:1826`, `:1946-1951`, `:2425-2435` |
| Cost of one wire read | `max_tokens: 1`, about 25 quota tokens (≈4e-6 pp of a week) | `:1239-1241` |
| Board | Rendered **only** by `--keepwarm`. A foreground `--rank` or `--fresh` sweep refreshes the cache but not the board. | `:7818` (the only `write_board(` call) |
| Series | `account-utilization.jsonl` writes at most once every 300 s (gated on file mtime), so rows land on every other sweep, about 6 min apart. That is why this replay uses the per-sweep wire lines in `claude-accounts.log`. | `:5483`, `:5510` |

There is no poll budget, priority or ordering anywhere. Every tick costs the same: one usage request per account that is not in backoff, plus one wire read per account in the band.

## (b) What bounds freshness at the wall today

| Candidate | Binding? | Evidence |
|---|---|---|
| **Tick (180 s, counted from the end of the previous tick)** | **Yes, it dominates** | Gap to the next wire read after an `allowed_warning` read: **p50 186 s, p90 231 s, mean 175 s**, n=309. 26% of gaps are under 150 s because foreground sweeps land in between (`r5_replay.py` §1). The next tick starts about 180 s after the previous one ends: start-to-start was 203, 182, 194 and 190 s, following each tick's `took_ms` of 23.0, 0.6, 14.7 and 17.3 s (`r5-watch-board.log`, 06:18–06:31Z). So the real period is 180 s plus the sweep. Sweep `took_ms` over the last 2,000 swept ticks: p50 5.9 s, p90 25.4 s, p99 76.6 s, max 131.8 s. |
| Board written only by keepwarm | Yes, it adds delay | A `rejected` verdict found by a foreground sweep waits for the next keepwarm tick. Cache write to board write took 2–7 s on 3 samples (watch log). |
| `--max-age 90` and the lock fallback | Partly | 395 of the last 2,000 ticks served cache (20%), at age p50 50 s and p90 110 s. **32 ticks served a cache older than 180 s, max 249 s**: the 5 s lock wait fell back to a cache up to 600 s old. |
| 429 backoff | No | The backoff holds usage polls, but the substitute wire read still fires at ≥ 90% (`:2425`). All 10 flips were detected by normal reads, not substitute reads. |
| Wire gate (endpoint ≥ 99) | No | The endpoint rounds up, so the band opens at wire **0.98** in 8 of 9 weekly-window episodes (`r5-spend-output.txt`). next3 read `7d 100` on the endpoint at every probe from 04:57Z to 06:13Z. |

**Estimated average age of the verdict on the board today: about 113 s.** Method: the last 2,000 out.log ticks; period = 180 + `took_ms`; the read is assumed to land mid-sweep on swept ticks and at `age_s` on served ticks; averaged over time.

**Incident timeline (from the logs):**
- 06:01:41.9Z: keepwarm read `0.99 allowed_warning`. The board was written at 06:01:46.
- 06:02:41.7Z: first refusal, session `e131c8d2`; the StopFailure marker landed at 06:02:42.
- 11 refusals followed before the next read.
- 06:03:49Z: first `rejected` read. It does not fall on the keepwarm lattice, so it was a foreground sweep.
- About 06:04:47Z (estimated from that lattice; the cache would have been ~55 s old, so the tick served it): the board showed `rejected`. That is **about 125 s after the first refusal**.

## (c) Allocation rules and their cost

### Why the brief's "k × proximity × burn" reduces to burn alone

- **k does not predict the flip.** The chance of a weekly flip on the next read was **0.024 / 0.031 / 0.028** for k 1–3 / 4–8 / 9+ (42 / 98 / 144 `allowed_warning` reads; 1 / 3 / 4 flips). There was **no `allowed_warning` read at k=0** in 16.4 days, so k has nothing to separate.
- **Proximity cannot be seen inside the last percent.** The wire's two decimals read `0.99` for the whole stay in the band: 0.38–4.18 h, and up to 82 reads (the incident ran 01:53→06:03Z).
- **Session burn since entering the band does predict it.** All 9 weekly-window flips came after **5–8 session-pp** burned from the first `allowed_warning` read (≈0.96–1.54 weekly pp at `K_FROZEN` 0.192), while time in the band ranged from 0.38 to 4.18 h (`r5-spend-output.txt`). This can be computed from wire `5h_util` values the producer already records, at no cost.
- **Ranking accounts is moot.** Only 2 of 187 five-minute bins had two or more accounts in `allowed_warning` (`r5-extra-output.txt`).

### Rule B (recommended): a refusal-triggered confirm read

- **Trigger.** A new line in `~/.claude/autonomy/stop-failure/rate_limit__<acct>.jsonl`, which `hooks/stop-failure-marker.sh` writes at the instant of death. Each line carries `account` (taken from the dying session's `CLAUDE_CONFIG_DIR`) and `last_assistant_message` ("weekly limit" or "session limit"). Using the marker avoids the transcript-copy misattribution problem: 246 refusals appear under 500 dir attributions because of handoffs.
- **Gate.** Fire only when that account had a wire read in the last 15 min (it is in the band, so the wire gate holds) and the cached verdict for that window is not already `rejected`. At most one read per (account, window, gap between producer reads).
- **Action.** One wire-only read (`fetch_wire_limits`, no usage poll). Patch that row's `wire` in the cache under the single-flight lock; if the lock is held, wait for the holder, which reads the wire itself since the endpoint is ≥ 99. Then re-render the board.
- **Replay (`r5_marker_trigger.py`).** 226 markers; 90 suppressed because the verdict was already `rejected`; 59 out of band; **11 confirm reads, 10 confirmed (every flip), 1 not confirmed** (a 2026-09-19 5h marker followed by a window reset).
- **Cost.**
  - Tokens: ≤ 1 token-bearing read in 16.4 d, about 25 tokens. This assumes a `rejected` read (HTTP 429) bills nothing — reasoned, not measured. If that is wrong, the cost is 11 × 25 = 275 tokens in 16 d.
  - Usage-endpoint requests: **zero**, so no new 429s.
  - Requests to /v1/messages: about 0.7 a day.
  - Wire gate: preserved.
- **Lag from the first refusal to a fresh verdict.** Marker, then `launchctl kickstart` (bare, never `-k`, the pattern at `stop-failure-marker.sh:284-291`), then Python start (~0.1 s at PRI 31, plist note), then the wire read (latency not measured), then patch and render (2–7 s measured): **about 3–10 s, estimated.** Today: 76 s mean to the producer plus up to one tick to the board.
- **Limit.** It confirms a refusal; it cannot predict one. The first refusing session is still refused.

### Rule A (alternative; costs tokens): a burn-gated hot wire cadence

- **Arm when** weekly `allowed_warning` holds and at least 3 session-pp have burned since the account entered the band, or when the 5h window is in `allowed_warning` (that window measures itself).
- **When armed:** a wire-only read every T seconds, a cache patch and a board render. Usage polls stay at about 180 s.

| T | Mean / max lag after first refusal (n=10) | Extra wire reads | Tokens |
|---|---|---|---|
| now | 76 s / 175 s | — | — |
| 60 s | 23 s / 30 s | +19.0/day (θ=3) · +36.1/day (always in band) | ≈475–900/day |
| 90 s | 32 s / 45 s | +9.4/day (θ=3) · +17.8/day | ≈235–445/day |

- **Basis.** `r5_replay2.py` (lattice phase uniform; the flip is assumed to equal the first refusal) and `r5-armed-output.txt`. θ=3 cuts armed time from 15.0 h to 7.9 h over 16.4 d and still armed all 9 weekly flips, 9–145 min ahead.
- **Not zero tokens, and nothing can fund it.** No token-bearing read near the wall happened at k=0 (0 reads). **4,427 of 4,752 wire reads (93%) were on `rejected` accounts**, and those are refused, so they bill about 0 tokens. Today's token-bearing reads run about 19.8 a day, so Rule A at T=60 roughly doubles them.
- **Placement.** Not inside the 180 s tick. Because the next tick starts 180 s after the previous one ends, a loop L seconds long stretches every account's usage cadence to 180 + L. It needs its own launchd cadence (a 60 s job, or `StartInterval 60` with a choice of mode per tick), which is an operator-owned plist edit.

### Rejected alternatives

- **Re-ordering accounts within a tick.** The fan-out is concurrent and the board waits for every probe (`:2576`).
- **Faster usage polls for the hot account, or a shorter StartInterval for everyone.** The endpoint is pinned at `100` through the whole stay in the band. The 429 budget is per token, and `StartInterval 60` throttled 3 of 4 accounts on 2026-08-11 (plist note).
- **Funding hot reads by thinning reads on k=0 accounts in the band.** The pool is empty.
- **Thinning reads on `rejected` accounts.** It would save about 270 requests a day but about 0 tokens. In 9 of 9 cases, the weekly window left `rejected` only when the reading itself fell after a reset: 8 times on the endpoint (100 to 99, 74, 57, 2 or 0), and once on a substitute read (wire 0.92) (`r5-unflip-output.txt`). Doing it would need a replayed rejection to render as "server-confirmed", which touches the 10-01 and 10-03 rulings. Low value.
- **A transcript scan instead of markers.** Copied transcripts cause misattribution (above). A scan costs 0.26 s per config dir in the foreground (measured with `find -mmin -3`), and the markers make it unnecessary.

### No-cost publication fixes, independent of A and B

- **Z1.** When keepwarm falls back on the lock (32 of 2,000 ticks served a cache older than 180 s, up to 249 s), wait for the holder's result before rendering instead of rendering the grace cache.
- **Z2.** When any sweep's wire verdict changes, re-render the board in a detached process, so foreground `--rank` gets no slower.

## (d) Replay over the recorded episodes (2026-09-19 → 10-06, 4,755 wire reads, 10 flips)

| Account / window | First `rejected` read | k | Refusals before it | Session-pp burned in band | Lag now (s) | T60 | T90 | Rule B: marker lead over the producer (s) |
|---|---|---|---|---|---|---|---|---|
| next3 7d | 09-22 08:05:32 | 18 | 5 | 4 | 107 | 30 | 45 | 109 |
| next 7d | 09-26 20:24:06 | 4 | 2 | 8 | 13 | 11 | 12 | 13 |
| next4 7d | 09-26 22:19:39 | 4 | 2 | 7 | 6 | 6 | 6 | 6 |
| next3 7d | 09-29 03:04:21 | 3 | 10 | 7 | 136 | 30 | 45 | 136 |
| next2 5h | 09-29 04:01:02 | 6 | 14 | 1 | 175 | 30 | 45 | 175 |
| next2 7d | 09-30 07:10:56 | 6 | 4 | 5 | 67 | 30 | 42 | 67 |
| next4 7d | 10-01 19:59:08 | 14 | 1 | 7 | 5 | 5 | 5 | 5 |
| next 7d | 10-01 20:54:41 | ? | 6 | 7 | 143 | 30 | 45 | 143 |
| next3 7d | 10-02 01:51:05 | 18 | 10 | 6 | 42 | 27 | 32 | 41 |
| next3 7d | 10-06 06:03:49 | 11 | 11 | 6 | 67 | 30 | 42 | 67 |
| **Mean** | | | | | **76** | **23** | **32** | Rule B lag ≈ 3–10 s |

- **"Lag now"** is the time from the first session refusal to the producer's first `rejected` read.
- **The marker-lead column** is the time from the marker to the producer's next read (`r5-marker-trigger-output.txt`). Marker and transcript timestamps agree to about 1 s (06:02:41.7 vs 06:02:42).
- **Assumptions:**
  - The flip is taken to equal the first session refusal. That is an upper bound on the flip time, and tight when sessions are busy: the incident had 4 refusals in 3 s.
  - Rule A's lattice phase is uniform.
  - The board publication delay is not replayed for history, because there are no historical tick timestamps (out.log lines carry none). For the incident it is estimated at about 58 s beyond the read.
  - k is the jsonl row at or before the read, within 600 s.
- **Session refusals on disk** were extracted from transcripts in four config dirs: 264 unique ids, 261 of them weekly or 5h (`r5-limit-errors.jsonl`).

## Blockers and conditions

- **Operator-owned changes.** Rule B needs a new small launchd job, kickstarted by `stop-failure-marker.sh` behind a sentinel file like its existing `.kick-on`, or started by WatchPaths on the marker files. Rule A needs its own cadence. Both are plist changes the operator owns. Neither touches the SessionStart hook, which stays a file read, or the status line.
- **Rule B depends on StopFailure firing on the refusing pane.** The hook's own header claims 126 of 128 `rate_limit` deaths were detected. Here it covered 10 of 10 flips.
- **Not measured:**
  - whether a `rejected` wire read bills tokens;
  - wire round-trip latency;
  - whether /v1/messages throttles one extra request a minute on its own. A 429 without the unified headers is treated as a miss, not a refusal (`:1311-1314`).
- **Small samples.** The tick is counted from the end of the previous tick on 4 intervals. The burn predictor rests on 9 flips.
