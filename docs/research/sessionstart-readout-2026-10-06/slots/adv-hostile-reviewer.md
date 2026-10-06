# Hostile review — SESSIONSTART_READOUT plan and its expected W1 fix

Scope: what the plan (`docs/plans/SESSIONSTART_READOUT.md`) and the expected W1 fix miss or get wrong. All paths relative to `/Users/chrisren/Development/.worktrees/sessionstart-readout` unless absolute. "Measured" = command run here; "reasoned" = inference from code/logs.

## 1. Defect #3 ("Cadence") is a measurement artifact, not a producer defect — SEVERITY: high (a W1 "cadence fix" would be work on a non-bug)

- The 6-min gaps are the utilization SERIES being rate-limited, not the sweep. `bin/claude-accounts:5483` `UTIL_MIN_INTERVAL_S = 300`; `record_utilization` (5486-5510) returns 0 when the file mtime is <300 s old. A 180 s tick lands at 180 (skipped), 360 (written): measured sweep gaps in the series, last 24 h, p50 372 s, p10 349, p90 417 (python over `~/.claude/logs/account-utilization.jsonl`, n=228).
- The producer itself ran every ~3 min: `~/.claude/logs/claude-accounts.log` has `probe next3: wire` at 05:40:00, 05:42:57, 05:46:11, 05:49:20, 05:52:28, 05:55:36, 05:57:46, 06:01:41, **06:03:49 (7d 1.0 rejected)**, 06:05:29 … (measured). `launchctl print gui/501/com.claude.accounts-keepwarm`: `run interval = 180 seconds`, `runs = 2418`, `last exit code = 0`.
- The `ItimerError` traceback cited in the shared context is in `accounts-keepwarm.err.log` whose mtime is **Sep 30 17:02** (`ls -la`) — six days before the incident, not current.
- Consequence: the producer saw `rejected` 45 s after the session did (06:03:04Z transcript line vs 06:03:49Z probe). The board was wrong for ~2 min, not for a 6-min tick. R4 should be closed with this receipt, and "producer cadence fix" removed from W1. Also fix the method: the out.log has no timestamps, so cadence can only be read from `claude-accounts.log` probe lines or the plist, never from the series.

## 2. "About 1% left" discards the endpoint integer, which the board already had — SEVERITY: high (precision bound is computable tighter than the plan proposes)

- Server sends two decimals only: 44,586 rows, `wire_7d_util` has 8 distinct values, max 2 decimals; `wire_5h_util` 40 distinct, max 2 (measured). The `99.6%`/`0.996` fixture in `tests/claude-accounts-wire-truth.bats:333-341` is a value the server has never sent; the floor-to-tenth branch of `board_eff` (6341) has no real input.
- Joint distribution at the wall (measured): `(endpoint 99, wire 0.99, allowed)` n=18, `(100, 0.99, allowed)` n=88, `(99, 0.98, allowed)` n=30, `(100, 1.0, rejected)` n=1889, never `1.0 allowed`, never `rejected <1.0`. 18 rows at `(99, 0.99)` across 47 min of burning (03:08-03:55Z) rule out "endpoint = ceil AND wire = truncate" (used would have to sit at exactly 0.9900), so the wire is rounded to nearest (reasoned). Under the file's own claim that the endpoint rounds UP (1217-1222): `(100, 0.99)` ⇒ used ∈ (99.0, 99.5) pp, headroom **< 0.5 pp**, not "about 1%"; `(99, 0.99)` ⇒ used ∈ (98.5, 99.0]. The note at 6745-6749 printed "about 1%… roughly 5% of one 5-hour window" at 06:01 when the evidence supported "under half a percent, under 3% of a 5-h window".
- Do instead: `board_eff` returns a bound derived from BOTH readings (endpoint integer and wire), and the sentence prints the interval's worst case ("under 0.5% of the week left"), never the midpoint. "Print as a bound" alone (plan W1 bullet 1) still over-states by 2x if it keeps `1 - w7`.

## 3. The bound text "≥99%" is already taken by the unconfirmed state — a text collision the plan's "print as a bound" walks into — SEVERITY: medium (breaks the 2026-10-03 three-state ruling with colour off)

- `pct_text` (6362-6367): `exhausted is None and v >= 100` → `"≥99%"` (gray, half-height bar); `exhausted is False` → `"99.0%"` (orange, sliver). Test W-10 pins `("100%", "99.6%", "≥99%")` as three distinct strings and `"≥99%"` in the blind row. If the allowed state also prints "≥99%", two of the three states become byte-identical under `CC_BOARD_COLOR=off` — the exact failure the ruling forbids.
- Do instead: three distinct texts without coded marks (W-9 bans `ʷ`/legends): refused `100%`, allowed-near-wall `~99%` (rounded reading, server accepting at the read), unconfirmed `≥99%`. Colour (`pct_rgb` keys on `v >= 99 and exhausted is False`) and the bar (`board_bar` caps at `width-1` for `exhausted is not True`) are unaffected by any of floor/round/bound as long as `board_eff` still returns `(≥99.0, False)`; only W-6 (`says 99.0% used`, `| 99.0% |`, `still accepts work`, lines 206-209) and W-10 (`" 99.6%"`, 341, 357-358) need editing. `tests/accounts-board.bats` pins no wording (grep for `99|not out|accepts` finds nothing), so the hook suite is untouched.

## 4. The wording is not the defect that cost anything; the plan treats a behaviour as a display bug — SEVERITY: high (question a)

- No new session was routed to next3 during the plateau: `account-assignments.jsonl` 01:56-06:12Z has 17 rows, all next4/next2/next; `claude-accounts.log` has 0 route lines naming next3 in that window (measured). The 11 live sessions were already there (`k_work` 0-4 of 11-15 live; `session_pct` 2→7 over 3 h, i.e. ~1 weekly pp per ~2-3 h at K=0.192). "Gone in minutes at k=11" is not what happened: this plateau was the LONGEST of 11 recorded (180 min).
- Across the whole series, every 0.99-allowed episode ended in `rejected` before its reset: 11/11, durations 19, 20, 23, 41, 50, 50, 86, 95, 145, 165, 180 min (median 50); per-row hazard of the next ~6-min row being `rejected` = 9/106 = 8.5% (measured).
- The operator's 2026-10-01 ruling ("leaving ~1% of a weekly on the table is a lot", 6330-6332) means the system is DESIGNED to run sessions into the wall and recover them (`lr-fleet` moved 5 sessions 06:03:56-06:08:24Z; HANDOFF.json at 06:09:33Z). The plan never states that the 06-06 complaint ("promise of headroom") and the 10-01 ruling (spend the last 1%) are the same policy seen from two sides, so any wording fix leaves the operator meeting the same wall next week.
- Do instead: the board sentence must say what the policy is: "next3 is in its last ~0.5%; 11 sessions are spending it; every account seen here hit the wall before reset (median 50 min after reading 99%); they will be moved by recovery." That is a behaviour statement, not a quota statement, and it is what the operator needed.

## 5. The honest form is a forecast from data the producer already holds, not a snapshot with an age — SEVERITY: medium (question b)

- The series records when the wire first read 0.99 (03:08:26Z) and when the endpoint stepped 98→99→100 (01:56Z, 03:55Z); `apply_burn` (3736) already reads this series inside the producer. Dead reckoning at 06:01: ~0.5 pp/h for 2.9 h since the 0.99 step ⇒ the last pp expected spent — "wall expected now". The board printed "1.04× burn, ⚠ WALL trajectory" (pace_line 4500) three lines below the sentence and did not join the two.
- "Age of the read + live-session count" (plan W1 bullet 1) is necessary but not sufficient: a 60-s-old "accepts work" with k=11 still reads as a promise. Print time-at-99% and the measured prior instead; both are zero-token (series read in the producer, nothing in the hook).
- Caveat the plan should carry: `wall_projection` abstains below 6/7 elapsed for good reasons (its docstring); the near-wall forecast must be keyed on "minutes since the 0.99 step × recent pp/h", a different instrument from the weekly projection.

## 6. R6's renderer list is incomplete; the board contradicted itself on the incident night — SEVERITY: medium

- `soonest_reset_line` (4420-4422) prints `100 - weekly_pct` from the ENDPOINT: with next3 at endpoint 100 it reads "next reset: next3 in 5.9h, **0% of the week left**" beside the note's "**about 1%** of the week left" (reasoned from code; the 06:01 board file is overwritten, the current one shows the line). `pace_line` deficit (4468) also uses `100.0 - r["weekly_pct"]`. Neither is in R6's list (`--readout`, note, `_wire_note`, `weekly_headroom`).
- The current board (06:14Z+) still prints "next3 no strand — 1.04× burn, ⚠ WALL trajectory · 5.8h left" after the server confirmed the refusal — a trajectory warning for an account already AT the wall. Add both to R6 and route them through `board_eff`.

## 7. The on-disk rejection signal already exists and already mis-attributes after a handoff — SEVERITY: high (question d; do not build a second one)

- Transcript error lines are structured: `{"timestamp":"2026-10-06T06:03:04.512Z","quotaLimits":{"status":"rejected","resetsAt":1791288000,"rateLimitType":"seven_day",…},"error":"rate_limit","apiErrorStatus":429}` — window and reset are explicit, so 5h-vs-weekly confusion is solvable from the field, not the text (measured in `~/.claude-secondary/projects/-Users-chrisren-Development-voiceink/4ad354fc….jsonl`). But a 2026-10-05 `session limit` line had `quotaLimits: None` — field presence by version is unverified.
- `lr_recon` already writes per-account facts from these deaths and from the wire: `scripts/limit-recover/lr_recon/facts.py` (`fact_from_death`, `facts_from_wire`, `<acct>.<scope>.json`), store `~/.reso/limit-recover/recon/facts/`, and `claude-accounts --place --facts` (5095-5110) already consumes that format.
- Measured mis-attribution today: `next2.7d.json` = `{"acct":"next2","first_sid":"4ad354fc-…","observed_at":1791267022 (06:10:22Z),"status":"rejected","contradicted":true}`. The next3 session was handed off to `~/.claude-secondary` at 06:09:33Z (HANDOFF.json), the transcript copied with its three `hit your weekly limit` lines (grep -c = 3 in both the `.handed-off` original and the copy), and the census charged the rejection to **next2 at 13% weekly**. `contradicted` marks but never expires (facts.py docstring). `next3.7d.json` carries `observed_at` from 2026-10-01 (merge keeps the oldest). A producer folding these in naively would print next2 as refused.
- Do instead: if W1 folds anything in, read the existing facts store with `contradicted=False`, `src!="census"` or `observed_at > last wire read`, and `resets_at` in the future — or skip it: here the wire saw `rejected` 45 s after the transcript did, so the signal buys ≤3 min at best against a mis-attribution it has already produced.

## 8. The hook's cost is super-linear in board bytes; every added word raises p50 — SEVERITY: high (question e; a hard constraint the plan assumes is free)

- `hooks/accounts-board.sh:~128` `[ -z "${body//[[:space:]]/}" ]` on bash 3.2 under `en_CA.UTF-8`: **0.83 s user** for today's 2,089-char board; **5.33 s** for the board concatenated twice (4,169 chars); 0.16 s under `LC_ALL=C`; `[[ "$body" =~ [^[:space:]] ]]` 0.02 s (all measured, `/usr/bin/time`, load avg 30-77). Whole hook 0.85-1.64 s wall (n=8), of which `cat`/`stat`/`jq` are 0.00-0.03 s. The suite's budget is 1.0 s (`tests/accounts-board.bats:318`) and it skips under load, so this is invisible to the gate.
- A W1 note with age + load + forecast per near-wall account adds ~150-300 chars per account; four accounts at the wall would push the body toward 3 KB and the hook toward 2-3 s, against the 5 s hook timeout and the dispatcher's 9 s bound (`session-start-dispatch.sh`, `BOUND=9`).
- Do instead: replace the blank check with the `=~` form (or `LC_ALL=C` on that line) BEFORE adding text; re-measure R1 with the real 2 KB board, not a fixture. `systemMessage` stays 0 model tokens (hook header, proven channel) — token cost is not the risk; CPU on a loaded box is.

## 9. Smaller misses

- Plan line 19 says the board's "99.0%" came from flooring 0.99; it did, but the sentence's "about 1%" comes from `1 - w7` at 6745 — two separate fixes, one listed.
- `wire_at` is stamped only on the throttled-substitute path (1961); the normal probe row carries no read timestamp the note could print. Add it in `probe`, not in the renderer.
- Live count is already on the row (`live 11` column); the sentence lacks it, but k=11 with `k_work` 0-4 is mostly idle panes — print `k_work`, or the note over-states load.

## Alternatives considered

- Pre-draining sessions off a 0.99 account: rejected — contradicts the 10-01 ruling and the recovery pipeline handles the wall in ~6 min.
- Faster producer cadence at the wall (R5): no — one wire read per 180 s already saw the refusal within 45 s; more reads buy nothing measurable and cost inference.

## Blockers

- The 06:01:45 board file is overwritten; objection 6's "0% vs 1%" is reasoned from code, not observed.
- Hook timing measured at load avg 30-77; a quiet-box baseline (R1) is still needed for p50/p99 before/after.
