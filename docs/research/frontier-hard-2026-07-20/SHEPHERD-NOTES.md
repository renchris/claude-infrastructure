# Shepherd notes — live specimen captured during the wave (2026-07-20 ~00:55Z)

For the synthesizer (fold into the law-composition / verification sections; this happened DURING
the investigation, in the shepherd session itself):

## Specimen: completion-assert × post-fire disposition contract — a live composition defect

- `completion-assert` (Stop hook, FM1 anti-false-done, fires ≤3/session) contradicted the
  shepherd session's ⏳ OPEN disposition twice, citing "dirty tree (2 file(s))" then "(3 file(s))".
- The cited dirt: (a) `M hooks/teammate-auto-shutdown.sh` — a FOREIGN session's claimed work
  (backlog b67f29d9096a; G4 forbids sweeping it), and (b) THIS untracked report dir — deliverables
  whose designated lander is the delegated successor (frontier-synthesis, live, /goal-bound).
- Note the dynamics: every wave-report landing GROWS the dirty-count the hook cites — the
  investigation's success reads to the hook as worsening incompleteness.
- Neither mechanism is wrong alone: the hook correctly refuses self-reported doneness; the
  /handoff disposition contract correctly sanctions an OPEN shepherd wait. They compose into a
  false-positive nag loop because NO shared model of ownership/delegation exists between them:
  the hook cannot represent "this dirt is foreign-claimed" or "this remainder is delegated to a
  live successor with its own DoD".
- The hook's irreducible-blocker taxonomy (credential / sudo / destructive-migration /
  external-info) also has no category for foreign-owned dirt — taxonomy incompleteness of the
  same shape a19 found in the GENUINE carve-outs (keyword-triggered, model-of-world-free).
- Feeds: T-B (prose-law→substrate gap: the laws are enforced by matchers that don't share the
  laws' ontology), T-E (completeness verification blind to delegation), fr-08 target 4
  (law-composition deadlocks/nag-loops), fr-02 (ownership/attestation records would give both
  mechanisms the missing shared state — C-DSH-1's lifecycle record extended with an OWNER field).

## Wave state at capture
6/13 reports on disk (01, 04, 05, 06, 07, 11); successor alive (wt-pool-1-44A7447E), consuming
incrementally; cc-await-ping armed on the shepherd pane, 7200s fallback.
