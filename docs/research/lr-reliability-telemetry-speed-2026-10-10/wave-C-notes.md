# Wave C notes — terminal states, aborts and registry cost (2026-10-11)

Report: `docs/research/lr-reliability-telemetry-speed-2026-10-10/REPORT.md` (lead worktree wt-cc-221850-13950; not on trunk when this was written). Items C1-C3 are the report's D4, D5 (writer half) and D7; C4 is ranked row 8.

## C4 (rank 8): what was built, and the two halves that were not

**Built, at 92%.** The cleanup lives in `lr-transplant.sh`, not in lr-handoff's FAILED arm. The report proposed the arm ("abort only a lock that was absent before the call and present after"). The transplant can state that ownership exactly, because it knows it wrote the lock: the lock records its own pid, and it can see whether a lock or a target transcript existed before the write. lr-handoff can only infer this, and it races any other actuator that writes a lock between its before and after reads. A fix in the transplant also covers every caller (lr-handoff, the move worker, the reconciler), not just one.

- A run that writes a fresh lock (no lock and no target transcript before it) arms an EXIT trap from the lock write until the sha check passes.
- On a non-zero exit inside that window, the trap moves the partial target transcript and the session dir it created into `locks/<sid>.failed-admit-<ts>/`, then releases the lock. It releases the lock only if the lock still records its pid, and it deletes nothing.
- A second hop or a `--force` over an existing lock or copy arms nothing.
- Test: `tests/lr-transplant-admit-cleanup.bats`. The real rsync fails (rc 23) on a mode-000 file. The test is red on trunk: the orphan lock and the partial copy are left behind.

**Not built: releasing the capacity token on FAILED.** Conviction 60 that it is worth doing. B1's own ruling (slot B1, "Ruled out") is that the 58d3640a token "expires by itself; it is not a leak" (TTL 1020 s). The only release path is `_cc_admit_token_discard`, a private function of `scripts/lib/capacity-admit.sh`, which belongs to neither this wave nor lr-handoff. The gain is about 17 minutes of capacity, early, once per failed admit (1 of 25 fleet verdicts). It was dropped, not filed: there is no operator decision in it.

**Not built: rsync retry or tolerance for vanishing files under `tool-results/`.** Conviction 70. The 58d3640a error is `mkstempat` ENOENT on the destination, not rsync's rc 24 "vanished" class. Whether a second pass clears it was not measured, and a tolerated rc 23 could hide a real copy failure. With the cleanup above, a failed copy is now a clean failure that can be retried: no lock, no partial copy. The poller keeps the request parked instead of retiring it as "transplanted", so the next tick re-drives it. Dropped, with the same reason: nothing here is the operator's call.

## C2 (D5 writer half): design notes

- `lrh_verdict` appends the verdict token as the run's state before anything else, at stage `verdict`, with the note as detail.
- The armed `SWITCHED-UNPROVEN`, mailed before the recycle fires, writes the non-final state `recycle-armed` instead. The skeptic's risk was that a reader matching `^SWITCHED` as done would stick on the armed line ahead of the real outcome. Under this design, every final verdict is written last.
- The chained EXIT trap (`lrh_exit_state` ahead of `lrh_git_lock_drop`) writes `exited` with `rc=N` only on a non-zero exit where this process wrote no final verdict and the log's last state, from any writer, is not final.
- A zero exit without a verdict writes nothing. That is the spawn path handing the run to the relaunched pane, whose own lines (READY, submitted) are the truthful tail, and an `exited` there would race them.
- The reader half belongs to wave A (`bin/cc-lr`): rank the reconciler record and `fleet/one-*/verdict.txt` above the bundle, and print no `repair` hint for a sid the reconciler holds (the B1-5 skeptic). Until it lands, `cc-lr status` shows `FAILED` from the bundle together with its existing `→ cc-lr repair` hint, the behavior that hint was written for.
