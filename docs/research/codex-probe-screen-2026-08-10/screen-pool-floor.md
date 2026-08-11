VERDICT: CLEAN

EVIDENCE:

1. The health filter's two terms are real, not vacuous — executed against the real 12,743-row store.
   `ok = r.get("verdict") == "OK" and float(r.get("swap_used_mb") or 0) <= 0`
   This was the leading suspect on two counts. (a) Token spelling: the producer
   /Users/chrisren/Development/.worktrees/probe-corpus/scripts/capacity-alarm.sh emits exactly
   OK/WARN/ALARM (measured distribution in the live log: OK 7316, WARN 1913, ALARM 3514), so the
   equality is asked of the population that holds the answer, and it is not a spelling enumeration
   standing in for a class. (b) Missing-field fallback: `or 0` would read an absent swap field as
   "no swap" and neuter the second term — but `swap_used_mb` is present on 12,743/12,743 rows
   (0 missing), and 5,284 rows carry swap>0, of which the AND rejects 1,232 that verdict=="OK"
   alone would have admitted (7,316 OK -> 6,084 healthy). Neither term is absorbed by the other,
   and neither can be defaulted into always-true. I also checked the level-vs-delta trap that
   capacity-alarm.sh §D1 documents (a latched static swap file read ALARM for 59 h): the header
   here says "zero swap growth" while the code tests the LEVEL, but level<=0 strictly implies
   growth<=0 (delta = used - window-min, and used==0 forces delta<=0), so the code is stronger
   than its caption, not weaker — and empirically 6,084 samples still survive it, so it is not a
   guard that can never stop firing.

2. Independently reimplemented the machine floor and diffed against the shipped one on real data.
   Ran `bash pool-floor.sh --json` on the live stores: floor 54, run 10, peak 54, 6,084/12,743
   healthy, 291.9 h. Then computed the true max-over-all-windows-of-min-sessions inside every
   healthy streak (128 streaks, longest 1,353 samples) in a separate script: also 54. The shipped
   loop tracks a running min from each streak's START rather than a sliding window, so it can
   UNDER-report (fixture: one healthy sample at 2 followed by 30 at 46 yields floor 2, verified by
   execution). That direction is the safe one and is the only direction available: the reported
   value is always a count that >=10 consecutive healthy samples met or exceeded, so it can never
   certify a sustain that did not happen, and the file publishes an explicit lower bound
   ("only lower bounds publish"). I also confirmed the winning run is contiguous in wall time
   (10 rows, gaps 62-63 s), so "10 consecutive samples = 10 minutes green" is not a run of rows
   stitched across a daemon outage.

3. The INSUFFICIENT-DATA arm is a real non-verdict, not a vacuous pass, and the exit codes match
   the header. `sys.exit(0 if (floor_m and pool) else 3)`; the JSON "verdict":"OK" token is gated
   on the same conjunction, so the success token cannot certify a pool floor that was never
   computed. Executed: real stores -> exit 3 with pool_span_h 24.0 vs needed 168.0 (correct, the
   recorder is 24 h old); missing CAP_LOG -> exit 1 with a message (`[ -r ]` guard, and note
   `set -uo pipefail` has no -e, so no `[ A ] && [ B ]` absorption exists anywhere in the file);
   empty CAP_LOG -> exit 3 with machine_samples 0 printed, no division by zero, no "OK". The full
   pin suite `tests/pool-floor.bats` passes 12/12 as shipped, including test 12 which drives the
   real stores. There is no exact-count assertion anywhere that would red on growth.

4. The pool-floor definition matches its subject and its spec, and does not inherit the machine
   floor's over-claim. `if w < 100` / `if r.get("stale"): continue` / `per[acct] = max(...)`, then
   summed. Cross-checked against the producer
   /Users/chrisren/Development/.worktrees/probe-corpus/bin/claude-accounts:1595 record_utilization,
   which writes exactly {ts, acct, k, weekly_pct, stale, ...} with k = live session count
   (k_live, line 854) — so the keys queried exist and mean what the script says. Also checked
   against docs/plans/CONCURRENCY_PROGRAM.md §S5b, which states the same definition verbatim.
   A missing/None k is skipped by `isinstance(k, int)` rather than counted as 0, so an unmeasured
   account cannot silently floor the sum. The per-account maxima are taken at different instants
   and summed, which is sound only because the four subscriptions are independent quota limits and
   the shared-hardware coupling is reported separately as the machine floor (named in the header as
   today's binding constraint); the pool line deliberately says "measured while ... under 100%"
   rather than "sustained", so the single-sample max is not dressed up as a run.

Closest thing to a finding, disclosed and deliberately not convicted: the util store has no
`[ -r ]` counterpart to the CAP_LOG guard, and `rows()` swallows OSError, so a PRESENT but
unreadable store prints "Store is EMPTY — no live sweep has happened since the recorder landed."
I reproduced this by chmod 000 on a copy of the real 713-row store. It is a lookup miss rendered
as absence, but it changes no verdict, no exit code and no published number — the branch already
reads INSUFFICIENT-DATA, `pool_samples:0` is printed on the line immediately above it, and the
sentence is operator advice rather than a guard or a certification. It does not make any check
unable to fire, so it does not rise to a defect in this file.

OPEN_FINDINGS: none found; searched docs/ for "pool-floor", "pool floor", "machine floor" (hits:
docs/plans/CONCURRENCY_PROGRAM.md §S5b, docs/plans/ACCOUNT_ROUTING_V2.md §13 R13-2,
docs/plans/backlog-consolidation-2026-08-09/OUT-accounts.md row 3,
docs/research/land-architecture-100p-2026-08-10/E-live.md:261) plus a scan of OPEN-status research
and plan docs. Every hit describes the script as landed and working; the only forward-looking item
is R13-2, an enhancement request ("should eventually feed a measured per-session burn coefficient
into the projection"), not a defect. CONCURRENCY_PROGRAM §S5b quotes 30 sessions / 11,421 samples
against today's 54 / 12,743, which is not a contradiction — that section instructs "Re-derive,
never quote" and states the figure moves with the fleet.
