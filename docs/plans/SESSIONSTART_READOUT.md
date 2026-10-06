---
status: complete
---
# SessionStart account readout — plan

Scope (frozen): the account board a session prints at start says only what its evidence supports at the wall (no "99.0%, about 1% left" off a two-decimal server figure, no "still accepts work" without its age and the load on the account), is as fresh as a zero-token background producer can make it, and the SessionStart hook stays a file read: no fork of `claude-accounts`, no network call, no inference, and no slower at p50/p99 than the baseline measured before the change.

Predecessor: `docs/plans/QUOTA_CACHE_FRESHNESS.md` (complete) made startup a cache read and added the wire read. This plan covers what that one left: what the board claims near 100%.

## Phase 0 — orchestration

- **Execution locus per wave:** W0 research = **S** (the dispatched session runs it as a Dynamic Workflow, read-only slots on `agentType: 'workflow-lean'`). W1 implementation = **S** (same dispatched session leads; Agent Teams only if the research splits the change across 2+ files with separate owners).
- **Lead context budget:** research returns as schema'd slot results and one synthesis written to `docs/research/sessionstart-readout-2026-10-06/README.md`; the lead keeps at least 50% for deciding and recycles after the research synthesis is committed if it is past 50%.
- **Gate:** `cc-bats tests/accounts-board.bats tests/claude-accounts-wire-truth.bats tests/claude-accounts-freshness.bats tests/claude-accounts-core.bats` (assert the `1..N` plan line), `python3 -m py_compile bin/claude-accounts`, bare `shellcheck hooks/accounts-board.sh`, then the project `/ship` and the degraded-tier converge.
- **Hard constraints:** the hook forks no `claude-accounts` (pinned by `tests/accounts-board.bats`; `--readout` measured 5.33 s against the hook's 5 s timeout). No account quota in the status line in any form (operator ruling 2026-10-04). The 2026-10-01 and 2026-10-03 operator rulings on the three wall states (inline in the percent column and the bar; a spendable last 1% is not drawn as a full red bar) stand; this plan corrects the precision and the wording, it does not revert them. Wire reads stay gated to the near-wall band and are the only inference the tool makes.

## Incident (2026-10-06, the reason this plan exists)

- 06:01:45Z: the sweep recorded next3 `weekly_pct 100`, `wire_7d_util 0.99`, `wire_7d_status allowed_warning` (`~/.claude/logs/account-utilization.jsonl`). The board (`/tmp/claude-accounts-board.txt`, mtime 01:01:46 CDT) printed `99.0%` and "next3 is not out of weekly quota: the meter shows 100%, but Anthropic's server says 99.0% used and still accepts work (about 1% of the week left, roughly 5% of one 5-hour window)".
- 06:03:04Z, 79 seconds later: session `4ad354fc` on next3 got "You've hit your weekly limit · resets 7am (America/Chicago)". 11 sessions were live on next3; the board's own drain line read "1.04× burn, ⚠ WALL trajectory".
- The operator read the board as a promise of headroom and reported it as wrong.
- CORRECTED (2026-10-06, W0 R3b): the FIRST refusal on next3 was 06:02:42Z (session e131c8d2; durable source: the StopFailure marker `rate_limit__next3.jsonl`, since that transcript is gone), 57 s after the sweep and 60 s after the wire read at 06:01:41.857Z. `4ad354fc` at 06:03:04Z was a later one.

## Known defects at intake (verified by reading the code and the logs, not yet by experiment)

1. **False precision.** The wire figure arrives as two decimals (`0.99` on four consecutive sweeps). `board_eff` (`bin/claude-accounts`, near line 6325) floors it to a tenth and prints `99.0%`; the note turns it into "about 1% of the week left". The figure supports "99% or more", and the headroom is an upper bound, possibly near zero.
2. **A present-tense claim on a snapshot.** "still accepts work" was true at the read and false 79 s later. The board carries its file age but the sentence does not carry the read's age, the live-session count or the burn trajectory that the same board prints three lines lower.
3. **Cadence.** The producer is `com.claude.accounts-keepwarm` (`StartInterval 180`), yet the last four next3 rows are about 6 min 14 s apart (05:43:11, 05:49:26, 05:55:39, 06:01:45 UTC). Whether that is the Background-band sweep duration, a skipped tick or a throttle is unmeasured.
   - CORRECTED (2026-10-06, W0 R4): none of the three. The observation was right and the suspected causes were wrong: sweeps run 185.6 s apart (p50, ProcessType Standard, launchd re-arms at exit) and next3 was wire-read on every sweep (71/71); the ~6 min spacing is the RECORDER, which appends at most one batch per 300 s (`UTIL_MIN_INTERVAL_S`). No cadence change can close a 60 s read-to-refusal gap. The one real producer defect is a shadowed `deadline` in `get_data`'s no-cache fallback that asked setitimer for ~1.8e9 s (EINVAL, 2026-09-30) — fixed in W1.
4. **(found in W0, R1) Interpreter.** The board child runs under the PATH bash (Homebrew 5.3 in 16/16 live sessions), not /bin/bash 3.2; only the dispatcher is 3.2. Under 3.2 the hook cost ~0.9 s from one superlinear whitespace-strip line — fixed in W1.

## W0 — research (Dynamic Workflow, before any edit)

Questions the research must answer with receipts. Each is one or more read-only slots; add a skeptic stage over the synthesis.

| # | Question | Where to read |
|---|---|---|
| R1 | Baseline: p50/p99 wall time of `hooks/accounts-board.sh` and of the whole `session-start-dispatch.sh` chain, measured under `/bin/bash` 3.2 as the harness runs it; token cost of the emitted `systemMessage` (is it model-visible at all?) | `hooks/accounts-board.sh` header (channel proof), `hooks/session-start-dispatch.sh`, a timing harness |
| R2 | Is the wire figure rounded or truncated, and is two decimals all the server ever sends? | every `wire_7d_util` / `wire_5h_util` value in `account-utilization.jsonl`; the binary's SDK doc strings quoted at `bin/claude-accounts:1220-1247` |
| R3 | How long does an account sit at wire `0.99 allowed_warning` before its first `rejected`, across the recorded series, split by live-session count? This sets what the board may honestly say there. | `account-utilization.jsonl`, `--reset-report`, limit errors in transcripts across the four config dirs |
| R4 | Why are sweeps ~6 min apart on a 180 s interval, and what does a tick cost in the Background band? | `launchd/staged/` plist, `~/.claude/logs/accounts-keepwarm.{out,err}.log`, `launchctl print` |
| R5 | Can the producer spend ticks by expected information (near-wall account with many live sessions first) at zero added tokens, and what freshness does that buy at the wall? | `docs/research/quota-cache-freshness-2026-10-01/README.md`, the poll-budget code |
| R6 | Every other renderer of the same meter (`--readout`, the board note at `bin/claude-accounts:6740-6760`, `_wire_note`, routing `weekly_headroom`): which share the precision defect, and does routing keep sending new sessions to an account in this state? | `bin/claude-accounts` |
| R7 | What do the existing suites pin about the wall wording, so the change edits the right assertions and adds a control that replays the 06:01:45 row? | `tests/accounts-board.bats`, `tests/claude-accounts-wire-truth.bats` |
| R8 | Outside view: how do other quota meters present a coarse reading near a cap (lower bound, age, rate), and is there any zero-cost signal of a rejection (a sibling session's limit error on disk) the producer could fold in? | public docs and the web; `cc-limited --json`, `lr-fleet.sh --locate` stores |

Deliverable: `docs/research/sessionstart-readout-2026-10-06/README.md` with the measured baseline, an answer per row, and the ranked changes with a conviction number each.

**Done 2026-10-06 (78af7aabb):** 13-agent workflow, 0 failed; README + the 12 slot/skeptic files in `slots/`. Answers in one line each — R1: board p50 61.5 / p99 124.2 ms on bash 5.3, 0 model tokens; R2: hundredths, rounded, held at 0.99 until refusal; R3: every ≥99% stay ended in a refusal (10/10, median 47 min), burn predicts it, k does not; R4: see defect 3; R5: no zero-token reallocation buys a 60 s gap; R6: one precision source (`board_eff`) feeding five sites, routing sent nothing new to next3; R7: five defect pins, control drafted red; R8: no surveyed meter prints a point ETA, all print bounds or the source's own resolution.

## W1 — implementation (shape depends on W0; expected, not decided)

- Board and readout print the wall state as a bound that matches the evidence, with the read's age and the account's live load in the same line.
- The limit-error-on-disk signal, if R8 confirms it is free, lets the producer mark an account rejected without waiting for the next wire read.
- Producer cadence fix, if R4 finds a defect.
- A control test that replays the real 2026-10-06T06:01:45Z next3 row and fails on the pre-fix renderer.
- Re-measure R1 after the change; the hook's p50/p99 must not rise and it must still fork nothing.

## Status

- 2026-10-06: plan created from the incident above; nothing implemented. Research not started.
- 2026-10-06: **W0 done, W1 done; scope (frozen) met.** Research: `docs/research/sessionstart-readout-2026-10-06/README.md` (13-agent workflow, two skeptics). W1, the changes above 90%: the nearly-out cell prints the server's whole percent (`99%`, never a tenth; `100%` refused and `≥99%` unconfirmed unchanged); the note is past tense with the read's local clock time and live/working sessions and states no headroom amount; the hook's emptiness test is a `case` glob; `get_data`'s setitimer shadow fixed. Controls: W-11 (verbatim 06:01:45Z row) red on the pre-fix renderer with 20 failed checks, test 6 of `claude-accounts-fresh-lock-bound.bats` red with `itimer_error [Errno 22]`; both green after. Gate: accounts-board 1..33, wire-truth 1..12, freshness 1..7, fresh-lock-bound 1..6, core 1..95, all ok; py_compile and bare shellcheck clean. Hook after vs before, interleaved: bash 5.3 p50/p99 61.2/136.7 ms (was 64.1/151.9), /bin/bash 3.2 52.7/128.3 (was 904.9/1897.7); still a pure file read.
- Open, not in this scope: desk routing on the last 1% is the operator's call, filed as `cc-decide` packet `05490056dd9f` (class B, default no change, deadline 2026-10-15). The refusal-on-disk signal, `wire_at`, drain/pace wording and `render_table` consistency stay at or below 90%; reasons in the README's last section.
