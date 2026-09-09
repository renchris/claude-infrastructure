# A10 — SKEPTIC pass on idle-visibility (working / idling / needs-you)

Wave exhaustive-drive 2026-09-08, ~23:30-23:55Z. Read-only. Every number: command + population.
"Measured" = I ran it. The axis's scratch scripts `/tmp/a10-*.sh` were re-run unchanged.

## Headline

The axis's central claim — `kind=="prompt"` in `~/.claude/cc-beats/<sid>.json` IS busy — fails in
BOTH directions on today's live fleet, and one of the failures is the dangerous one:

1. **False BUSY after a StopFailure.** The Stop chain does not run when a turn ends in an API failure;
   only `hooks/stop-failure-marker.sh` (event `StopFailure`) runs, and there is no beat writer on that
   event. So `session-beat.sh stop` never fires and `kind` stays `prompt` on a live pid.
   Measured: 9 StopFailure markers / 5 sids today (`jq 'select(.hook=="stop-failure-marker")'
   ~/.claude/autonomy/idl.jsonl`); 3 of those sids are still live; **2 read `kind=prompt`** — panes
   616 (`52e35019`) and 618 (`6e29fee9`), whose transcripts end `assistant:text` → `system:turn_duration`
   at 23:11:09Z / 23:09:32Z, i.e. the turn ENDED 27-38 min before the re-run read them as BUSY.
   Re-run of `/tmp/a10-cross.sh` (population: live-pid telemetry rows): 5 BUSY, of which 2 have
   transcript age 1,145 s and 1,841 s. The axis's "11 of 12 BUSY wrote within 252 s" was a moment
   sample; 2 of 5 right now are false.
2. **False IDLE on an orchestrating lead.** The wave lead `b418b97a` (this wave's parent) reads
   `kind=stop` since 23:28:45Z (beat `t=1788910125`) while running 12 in-process subagents; its
   transcript since then holds only `queue-operation … reason:"absorbed_mid_turn"` records
   (10 in the last 400 lines). In-process subagents / Workflows are neither a `prompt` beat nor a
   descendant process (`pgrep -P 16212` → 11 children while a subagent's Bash runs, 0 between
   calls — sampling). The proposed sensor renders the operator's most important pane IDLE-ARMED.

Beat wall time is NOT the cause: 5 runs of `hooks/session-beat.sh stop` into a scratch
`CC_BEAT_DIR` at load 25/48/71 took 0.06-0.08 s against the 3 s hard kill.

## Numbers re-checked

| claim | axis | re-run (measured) | holds |
|---|---|---|---|
| live claude pids / beat / telemetry / neither | 27 / 25 / 19 / 2 | 23 / 21 / 15 / 2 (`bash /tmp/a10-cov.sh`) | ratios yes |
| live panes BUSY / IDLE / no-beat | 13 / 6 / 0 (n=19) | 5 / 10 / 0 (n=15) (`bash /tmp/a10-beats.sh`) | shape yes |
| BUSY panes with transcript ≤252 s | 11 of 12 | **3 of 5**; two at 1,145 s / 1,841 s (`bash /tmp/a10-cross.sh`) | **no** |
| open class-C / with sid / author alive | 28 / 17 / 1 | 28 / 17 (jq) / 1 — alive-by-beat 1, alive-by-telemetry **0** | yes (see §miss 6) |
| wrap-ledger fields / busy-idle | 50 / 0 | 50 / 0 (`bash scripts/wrap-ledger.sh --machine`) | yes |
| permpend pages today / all-time | 23 / 114 | 23 / 114 (`find ~/.claude/autonomy/pages -name '*.permpend.notified'`) | yes |
| enum at offset 156692984 | 14 types | confirmed verbatim (`tail -c +156692984 claude.exe \| head -c 420`) | yes |
| wrap-ledger.sh:900 join on `.session_sid == $sid` | — | confirmed | yes |
| statusline.sh:55-61 PATH repair; :149-155 keys | — | confirmed | yes |
| push-critical.sh exits on unset PUSHOVER | line 22 | lines 21-22 | yes |
| operator-readout gate :18-27, latch :1380-1394, TTL 900 | — | confirmed (`TTL=` at :316) | yes |
| 2 uncovered pids = jq-off-PATH | inferred | **measured**: pids 66521, 53431 `PATH=~/.aftman/bin:~/.cargo/bin:/usr/bin:/bin:/usr/sbin:/sbin` (`ps -E -o command= -p`) | upgraded |

## New measurements the axis's question required

- **Intra-turn gaps >900 s today**: 47 across 138 today-touched transcripts (4 roots, realpath-deduped,
  <150 MB) / 1,230 prompts; ALL are `assistant:tool_use(Bash)` → `user:tool_result`; **46 of 47 are in
  sessions paged `permpend` that day** (session-level join, 30 paged sids); 0 tool_results read
  rejected/interrupted; largest gap **28,324 s (7.9 h)**, eight gaps >6 h. This CORROBORATES a
  stale-transcript alarm (false-fire on long tool runs ≤1/47 today) and shows the 48-min example
  understates the wedge scale by ~10×.
- **Frozen prompt beats**: 3,057 beat files; 1,427 `kind=prompt`; **1,411 with a dead pid (98.9 %)**.
  Any consumer without the (pid,lstart) leg reads 1,427 BUSY. No GC of the store is proposed.
- **Interrupts**: 3 `[Request interrupted by user` user records today / 3 sessions — negligible
  population; whether Stop fires on Esc was NOT established (regex grep of the 198 MB binary did not
  finish inside the wave; left in background, never read).
- **Existing readers the axis missed**: `scripts/lib/spawn-presence.sh:290-311 cc_sp_active()` already
  computes "live MID-TURN session count" with exactly rec 1's predicate (`kind=="prompt"` AND pid live
  AND lstart match), called from `capacity-admit.sh`, `handoff-fire.sh`, `capacity-marginal*.sh`.
  `scripts/lead-supervisor.sh:91` already pages `STALL?` at telemetry age >1,800 s on a live pid
  (`CC_SUP_STALL_S`) and `:113` a precise `PERMISSION-PENDING: <cmd>` page — pane 618 has been
  `STALL?`-paged every minute since 23:45Z (IDL `p=page v=STALL?`). The axis's BUSY-SUSPECT is a
  second alarm on the same event with no shared damping key; and the supervisor's STALL? is keyed on
  the very telemetry-age signal the axis refutes.
- **`agent_needs_input` / `agent_completed` emit site** (offset 170104593): pushed into an array drained
  by `for(let A of R)tv(A,m,…)` inside `Rg(...)` — the background-agents panel effect
  (`tengu_bg_agent_notification`, `jobSessionId`). Same `tv` symbol as `sendIdleNotification`; that
  it reaches the Notification hook is INFERRED (no session registers a catch-all matcher, so zero
  end-to-end evidence). These are background-job events, not pane-teammate events as the axis says.

## Verdicts (per recommendation)

R1 session-busy.sh on the beat — **refuted as specified** (two measured failure modes above; predicate
already exists in `cc_sp_active`). Keep the direction; add a StopFailure beat writer (settings
migration: `StopFailure → session-beat.sh stop`) and an in-process-work leg before calling it Q1.
Fail direction as written: false IDLE on orchestrating leads (dangerous) AND false BUSY after
StopFailure. 55 %.

R2 re-order a3eaa0dc1be2 — not refuted on the SIGKILL-refactor demotion; refuted on "step 1 is free
and exact". A third question (in-process work under a session) is answered by neither half. 75 %.

R3 wrap-ledger machine fields — holds (50/0 re-measured; fail-open precedent real); inherits R1's
classifier errors but inert until rendered. 85 %.

R4 BUSY-SUSPECT render at 900 s — **strengthened** by the 46/47 corpus result, but the label is
wrong for the StopFailure class (it is IDLE-after-error, not BUSY) and it must share damping with the
supervisor's STALL?/PERMISSION-PENDING pages or it double-pages the desk. 80 %.

R5 register 4 Notification matchers — enum measured, hook reachability and "teammate events" both
inferred; delivery is zero until PUSHOVER is set (the axis's own 51-day loop). Cheap and harmless,
but no value until f91a9701ed21 closes. 60 %, refuted on the value claim.

R6 pane roster — coverage holds; needs a fourth state (in-process work) or it shows the lead IDLE;
orphan re-attachment is policy (axis's own 65 %). 75 %, effort M→L.

R7 jq PATH repair in session-beat.sh — **upgraded from inferred to measured** (both uncovered pids
lack /opt/homebrew/bin). 95 %.

## House-rule check

- "A gate must not key on its own signal": R4's suspect test keys on transcript mtime, which is
  independent of the beat — fine. The supervisor's STALL? keys on telemetry age, refuted — the axis
  should have said so.
- "A positive control that cannot fail": the axis's 11/12 sample had no negative control for the
  lost-Stop class; the StopFailure class supplies it and fails.
- "A count is not content": 92.6 % coverage counted pids, including old-binary resumed panes; the
  two misses were the diagnosable class, now measured.
- "Sibling auditors must share the state model": BUSY-SUSPECT vs lead-supervisor STALL? — unshared.
