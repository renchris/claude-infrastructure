# Premise check: provenance-and-verification-tier (lens = premise)

Verdict: REJECT, conviction 78. The main example given for the gap refutes the mechanism proposed to close it.

## 1. Do we already have it?
- No memory-frontmatter provenance field exists. MEASURED with `grep -h -E "^\s*(source|confidence|verified|receipt|provenance):"`
  over ~/.claude/projects/-Users-chrisren-Development-claude-infrastructure/memory/*.md. Result: 0 frontmatter keys.
  The only hit was one body line, `verified: git ls-tree ...`.
- A provenance stamp that the harness writes already exists. Every infra topic file carries a nested
  `metadata:` block with `node_type: memory` (428 files), `originSessionId` and `modified`
  (our-write.md:163, MEASURED by our_write_measure.py, 495/495 files parse). A file can therefore be traced
  mechanically to the session that wrote it. docs/research/handoff-high-value-capture-2026-08-19.md:225
  places 317 creations in a transcript.
- A sibling rule covers the operator-vs-agent authorship axis:
  docs/lessons/an-agent-written-refusal-is-inherited-as-operator-policy.md, with its hook at
  .claude/rules/agent-operating-lessons-situational.md:213. It says a restriction names WHO set it (operator
  quote and date, or agent doc path) plus its premise. It applies to briefs, not to memory frontmatter,
  and it is prose.
- Git history: `git log --all -G'source: *(operator|verified|inferred)'` returned 0 commits, and
  `--grep=provenance` found only non-memory work (jev, deploy-parity, cc-custody). No attempt was
  abandoned on a branch.
- MEMORY_KNOWLEDGE_V2.md §4 (R1-R7, :223-267) and §7.5 (R8-R10, :390-407) never consider provenance.
  Nothing was rejected earlier either.

## 2. Is the gap real? Each piece of evidence, checked
### 2a. Flagship case: the "rules dir not loaded" negative (~/.claude/rules/agent-operating-lessons.md)
- The original record was a MEASURED probe with a positive control (:77-86): a `claude -p` sentinel table
  with CLAUDEMD=YES / RULES=NO / PROJRULE=YES / SYMLINK=YES on both binaries. It also shipped a one-line
  re-check command (:88-94). The file says "Its measurements are correct; only its scope was overstated" (:74).
- Under the proposal it would have been written as `source: verified`,
  `receipt: "claude -p 'Reply with RULESLOAD-OK-A7F3…' => NONE"`. The proposed validator flags only negatives
  whose source is NOT verified, so it would have PASSED this entry. The failure was scope over-generalisation
  from a verified measurement (headless to all surfaces, then to a version range, :43-48). A missing
  verification step was not the cause.
- The file already names the structural cause: the re-check rule could only test the headless path (:58-61).
  The companion lesson docs/lessons/re-run-the-probe-on-the-old-binary-too.md is hooked at situational.md:75.

### 2b. Correction-marker rate (5.6% infra / 9.4% reso)
- The rate reproduces from our-write.md:172 (MEASURED there), but the count is inflated. I hand-classified
  the `grep -m2 -n -E "CORRECTED|SUPERSEDED|REFUTED|RETRACTED"` lines of the 28 infra files (ESTIMATED,
  single reader). About 18 are genuine self-corrections. About 10 use the words as verdict vocabulary or
  narrative: landedness-oracle, identifier-superset, stranded-ref, bounded-gate, cc-blockers-board,
  never-engaged, rendering-transform, sweep-hosted, self-comparison, work-item-remedy, parked-blocker.
  That puts genuine corrections at about 3.6% of infra.
- Most genuine corrections revise MEASURED claims: a wrong instrument, a confound, or an incomplete read.
  Examples: pipefail-inverts-early-exit-probe.md:25 "re-measured"; session-crash-per-session-bloat.md:3
  "~92% teardown-confound artifact"; agent-benchmark-panicked-the-box.md:40 miscount of panic files;
  vendor-gate-may-be-an-env-var.md:21 binary read was incomplete; permission-autonomy-allowlist-method.md:54
  cited but backwards. A verified tier would not have flagged any of them. Some were agent inference or advice:
  deploy-lag-checkout-behind-origin.md:17 "I asserted" and compressor-segment-exhaustion-panic.md:47
  "my own advice". The gap therefore exists, but it is a minority of cases and n is small.
- No measurement links a correction to a missing verification. The candidate states that link but gives
  no evidence for it.

### 2c. Would the proposed validator work?
- The negative regex `cannot|can't|never|does not|doesn't|not supported` matched descriptions in 160/496
  infra files (32%) and 169/837 reso files (20%). Bodies matched 469/496 infra. MEASURED with grep -l -i -E
  over topic files. Most hits are prescriptive rules ("never do X"), not tool-claims. The gate would be mostly
  false positives unless everything were tagged verified, which would empty the tag of meaning.
- Two of the five target files do not exist: `hooks/lib/memory-topic-validate.sh` and `bin/cc-memory-search`
  (MEASURED with `ls`, and `git log --all` shows no history for either). They are presumably proposals from
  sibling candidates. No frontmatter validator for topic files exists at all, so the "S" size is understated.

### 2d. Author-declared frontmatter keys go unused (MEASURED)
- `superseded_by:` was made the rotor's rank-0 death signal in 65edba440 (2026-09-05, bin/cc-memory-rotate:87).
  It has 0 adopters in both stores.
- The `paths:` key (bin/cc-memory-rotate:471, 5f50b3ce9 2026-09-03) also has 0 adopters in both stores.
- A third hand-declared key with no enforcing writer is likely to stay unused. The nudge (memory-nudge.sh:560)
  already carries the "verify before encoding" text, and adding a field to that text does not make it checked.

### 2e. TrueMemory side
- extractor.py:101-102 and :119-120 define `confidence` and `source_role`. The only downstream read is a trace
  dict at pipeline.py:472 (`"confidence": fact.confidence`). `source_role` is read nowhere outside
  extractor.py (MEASURED with grep -rn). TM has no working mechanism here to extract. The candidate is a new
  idea motivated by what TM lacks, and it does not port anything.

## 3. What would survive (not proposed for adoption)
- If anything is built, derive it mechanically instead of relying on authors to declare it. originSessionId
  plus the transcript can show whether the operator voiced the rule and whether a Bash tool call preceded the
  write. Checking a receipt's SCOPE (invocation mode, binary version) is the real lesson of 2a, and prose
  already covers it. The evidence does not support this even as an adapt.
