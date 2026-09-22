# Integrating review findings by local edits manufactures contradictions — audit the whole after integrating

**Rule.** A document that was corrected by applying N review findings as targeted edits is a new document that nobody has read whole. Each fix moves one span; every other mention of the same artifact, flag, path convention or number stays where it was. Before landing, run one whole-document consistency pass whose unit of work is *the artifact*, not *the edit*: build the table of every named thing and check every occurrence agrees.

**Incident (2026-09-22, `docs/research/agent-context-sync-2026-09-21.md`).** The architecture document was assembled from 14 research axes, then corrected by 10 adversarial verifiers, then by a 4-lens hostile review (facts, operations, retrieval, completeness — 55 findings, all integrated by targeted edits), and landed. On a re-read the author found two contradictions by hand (an untracked `STATE.md` "committed alone"; an agent told to read a file from a worktree that could never contain it). A dedicated two-lens audit (internal consistency; receipt traceability) then found **16 internal disagreements and 12 receipt gaps** in the corrected document:

- the curated-page frontmatter example's relative path was one directory level short for the documented layout, so a literal generator would have normalized every dependency row to a nonexistent path and the refresh queue — the exact mechanism the review had just rewritten to stop failing open — would have reported the whole curated layer as missing;
- the reconcile cadence read *hourly* in three places and *daily* in four, because the reviewer's fix was applied where it was cited and nowhere else;
- the same file was described as gitignored in one bullet and committed in the next;
- a new verdict vocabulary omitted the design's commonest non-deleted terminal state, so it would have been reported as a pipeline bug;
- the printed land gate flagged exactly the pages its own parenthetical declared exempt;
- two measurements added after the review had no receipt file, and one integrated sentence contradicted a live probe in the evidence base.

None of these existed before the integration step, and none was visible to a lens that reads a finding and its span. **The integration is the generator.**

**Why local edits do this.** A review finding names a span and a replacement. The replacement is right *at that span*. But a design document names each artifact many times — in a diagram, an invariant, a table cell, a failure-mode row, a build step, a summary — and a fix that changes what the artifact *is* (its location, its cadence, its vocabulary) silently leaves every other mention describing the old thing. The more thorough the review, the more spans move, and the more contradictions the integration mints. Fable-class models rewriting whole files avoid this by accident and destroy history on purpose; targeted edits preserve history and manufacture disagreement. The audit is the price of the second.

**How to apply.**
1. After integrating any review with more than a handful of findings, run a consistency audit whose brief is: *enumerate every named artifact, field, flag, path convention and numeric claim; check every occurrence agrees; run any printed command against a fixture.* Its unit is the artifact, so it reads the whole document, not the diff.
2. Give it a second lens for receipts: every "measured" sentence must trace to a file in the evidence directory — measurements added *during* integration are the ones most likely to have none, because they came from the author's own late runs, not from a report.
3. Treat the audit's findings as a normal integration and re-audit only the artifacts it touched; two passes converged here (28 findings, then zero critical).
4. Budget it: the audit cost two agents and ~13 minutes against a three-hour research wave — cheap relative to a landed design whose curated layer would have read as entirely broken on first use.

**Companions.** `a-record-correction-wave-breaks-the-record` (insertions break line citations — the same shape at the line level); `docs/lessons/correction-inherits-the-claim-s-burden.md` (a refuted objection is not a proven claim); `reviewer fixture scripts copied as receipts conscript the land gate's shellcheck` — the receipts themselves must pass the repo's gates, so annotate (shebang + directive header, commands unchanged) rather than rewrite or rename.
