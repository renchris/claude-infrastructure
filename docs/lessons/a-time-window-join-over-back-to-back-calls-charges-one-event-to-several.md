# A time-window join over back-to-back calls charges one event to several

**Rule.** When events from a trace are joined to calls by time, the window must not be wider than the
spacing between calls. If calls run back to back, a window of [start - 1 s, start + limit] around each
call also captures events that belong to the calls after it, so one event is counted against several
calls. Join each event to the ONE call whose span (start to start + wall time) contains the event's
own start stamp, or to the latest call that started before it, and check conservation: the number of
events charged must equal the number of events in the trace, with no call holding two.

**Incident (2026-10-08, claude-infrastructure, wave E1m of the research program build).** Guard 2 of
ruling `a7fd5e2ee7c8` replays 42 tuning calls through the live router and counts a call as a miss if the
router's trace holds a `held` row for it with the careful call silent. `e1m-ab.py` matched a `held` row
to every call that started within [t - 1 s, t + 9 s] of it. The trace held exactly one `held` row, at
the start of call 30, but calls 27, 28 and 29 had started within the 9 s before it, so the script
charged that one hold to four calls and printed `caught 37/42`, under the floor of 40. Calls 27-29 had
already returned relay labels in 1.5-3.2 s; the last of them ended 0.09 s before the hold's router
started. Joined by containment, the run reads 40/42, at the floor. The same join had inflated the
wave's matched-load A/B table recorded hours earlier: "held with the careful call silent" read 71 for
the Haiku 4.5 union when its trace holds 44 `held` rows; corrected to 42 (and 2 to 1 for the other
arm). The sibling script `e1k-ab-report.py` was not affected: it gives each trace row to the single
latest call that started before it, and its totals equal the trace's row count.

**How it was caught.** The guard's printed misses included rows whose labels were correct and fast;
reading the per-call records against the single trace row's timestamp showed the overlap.

**Method warning.** The scorer fix was made after the failing result was seen. That is legitimate only
because the rule's own text ("the router did not hold *it*") defines the join, and the conservation
check (every hold maps to exactly one call) is independent of the verdict; the record discloses the
order and keeps the first scoring as a control.
