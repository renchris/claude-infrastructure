# wave2 red-team: reso landing design (2026-09-22)

1. **Phase-2 lease wedges the fleet on a live hung holder** (§5.2 I2). The ported source has no self-abort or heartbeat: payload unbounded (`land-lock.sh:466`), TTL reaps only a pid-less dir (`:340-346`), live over-budget = "needs a human" (`:204-232`). Inside the lease sit unbounded SSH fetches (`ship-reconcile.sh:78`, `ship-land.sh:277,753`; no ServerAlive in `~/.ssh/config`). Today a hung fetch stalls one session (fetch precedes cc-sem, B3); Phase 2 stalls every land incl. non-code — v1's 47-h wedge (`ship-land.sh:14-24`). **Breaks latency target.** Fix: `timeout` all network calls, real self-abort, waiter bound → CAS fallback.

2. **Model flatters Phases 3-4; acceptance gates unmeetable.** With E's +45 s/concurrent suite (§2), which the stub harness must include (Phase 1): P5f p95 13.2→16.3 (N=15), 15.0→21.5, 19.1→41.2 (N=40); P5 7.6→10.7, 16.9→40.7; PS unchanged. Phase 3 gates (≤15/≤25) and Phase 4 (≤8) all fail. P5f also skips its "once per batch" suite at k=0 (`landsim.py` pint(0)=0, q=1): 31% of code batches at N=8. `/tmp/rla/redteam_model.py`. **Breaks latency target** (PS<P5 ordering survives).

3. **Non-code claim false at target N.** PS N=15/30-min: non-code p50 9.7 min, p95 25 min vs today 14-20 s and "~1 min median" (§4.5, §5.4; true only at N=8). 60% of PS lands exceed the 600-s foreground Bash ceiling (no BASH_MAX_TIMEOUT_MS; Phase 2 lacks `--async`); a killed holder orphans suite+push (reso lesson "stopping the wrapper does not stop the child") → trunk moves under next holder → full re-verify, never charged by PS. **Breaks latency target.**

4. **Hang row contradicts I2.** "Heartbeat stale ⇒ takeover" of a live combiner is v1's live-holder steal (`ship-land.sh:18`); a main-loop heartbeat stales on every long suite → duplicate combiner, +45 s each, positive feedback under load. **Latency under load.** Fix: side-process heartbeat; takeover only on dead pid.

5. **Recovery "by content" unsound for in-batch supersession** (§5.5). Ticket A's file rewritten by later ticket B (H1: both overlap pairs were `tests/presubmit-always.txt`): blob≠trunk and `--is-ancestor` on A's head fails, trunk holding a cherry-picked copy (`ship-land.sh:761-766`) → landed A re-picked → false conflict eject. Same primitive false-FAILs per-ticket verify. No double-land (3-way pick merges identical hunks once). **Correctness of reported outcome.** Fix: WAL candidate tip + landed shas before push.

6. **Adoption (I6) unspecified off the clean sync path.** `--async`/successor: `reset --keep` aborts on any local edit to a batch-touched file → AHEAD>0 → `wrap-ledger.sh:539` UNLANDED → "/ship … else lost" (`:1988`) → empty pick → rc 6 "already upstream" (`ship-reconcile.sh:247-259`) logged `statics-red` (B8). No loss; confusion loop. **Cosmetic-moderate.**

verdict: SOUND-WITH-FIXES
