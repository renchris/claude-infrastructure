# Premise check: structured-supersession (lens=premise) — 2026-09-27
Verdict: ADAPT (shrink to S). The data model already exists; the remaining gap is small and located elsewhere than the candidate says.

## Already have (MEASURED, read)
- `superseded_by: <name>` is documented as the sanctioned way to declare an entry dead: commands/compact-memory.md:81-93.
- The rotor consumes it as rank 0: bin/cc-memory-rotate:87 and :1149 (awk over the first 12 lines).
  Tests: tests/cc-memory-rotate.bats:682 (demoted first) and :699 (mutation control).
- Design intent: the rotor is "inert on today's corpus by construction — which is correct"
  (bin/cc-memory-rotate:98-100). So 0% adoption was expected, not a broken mechanism.
- The anti-capture rule already says "update the existing entry instead of adding a near-duplicate" and captures
  "corrections to prior memory": CLAUDE.global.md:103-107.
- Rejected alternatives (MEMORY_KNOWLEDGE_V2.md §4 R1-R7, §7.5 R8-R10): none of them covers supersession.
  R2 (no autonomous mutation of the unbacked store) constrains any backfill.
- Git: `git log --all -G"supersede-lint|supersede-redirect|memory-supersede"` returns nothing, so there has been
  no graveyard attempt. `bin/cc-memory-search` does not exist (ls; also premise-episodic-session-recall.md:7).

## Gap numbers re-checked
- superseded_by/supersedes/valid_until in topic files: 0/497 infra and 0/838 reso
  (MEASURED `grep -l` on ~/.claude/projects/*/memory/*.md). This confirms our-write.md:170.
- The prose CORRECTED markers (5.6%/9.4%) are IN-FILE corrections. The rotor author read all 26
  (cc-memory-rotate:93-97) and none of them marks the file dead. In other words the store ALREADY follows the
  proposal's own rule (b), "edit the file it corrects". This number shows the practice working, not failing.
- Duplicates: INFRA has 0 pairs at cos>=0.4 and RESO 3 pairs at >=0.4, 0 at >=0.5 (our_write_dups.out).
  The "four control rules" (our-write.md:193-195; our_write_nn_sample.txt) are a family of distinct lessons,
  not a correction chain, so they are consolidation evidence, not supersession evidence.
- Cross-file supersession prose scan (MEASURED grep for supersed|replace|corrects|obsolete + a filename):
  - INFRA: every hit is either in-file or names a commit or migration (feedback-drive-by-default-operator-values,
    desk-autonomy-dormancy-staged-not-loaded, cc-upgrade-gate-tool). No live unmarked predecessor was found.
  - RESO REAL CASE: MEMORY-ARCHIVE.md:885-888 archives the design-gate cluster as "Superseded by
    reference-design-gate-deferred-postland-v2.md ... topic files untouched". 5 predecessor topic files
    (reference-design-gate-{blocks-on-env-not-regressions,cross-worktree-server-contamination,
    load-flake-and-misleading-error,update-stale-css-skips-baselines}.md, reference-prepush-design-gate-worktree-gotchas.md)
    carry NO in-file marker (grep supersed|postland|v2|obsolete = 0 hits each). A grep reader sees them as current.
  - RESO partial: MEMORY.md:507 says "panes SUPERSEDED by [[...]]; principles hold". This is partial supersession,
    and a binary superseded_by would misstate it.
  - RESO inversion: worktree-isolation-stale-base-2026-06-02.md opens with "RE-VALIDATED 2026-06-16 ... the correction
    below is ITSELF now inverted". A one-way superseded_by/valid_until chain would have been wrong here.
- Read-side reach of the (d) redirect hook: 31/172 main sessions read any topic file in 14 days, 66/496 distinct
  files; after the situational exclusion 3/27 (our-read.md:28, 122-131). Its reach is tiny.

## Refined adoption (S)
1. One clause in the nudge (hooks/memory-nudge.sh:560) and the anti-capture list (CLAUDE.global.md:103):
   "a correction edits the file it corrects (dated CORRECTED line at top); only when a NEW file wholly replaces an
   old one, add `superseded_by: <heir>` to the OLD file's frontmatter".
2. /compact-memory step 1/archive: when an entry or cluster is archived as SUPERSEDED, also write `superseded_by:`
   into each archived topic file's frontmatter. This is human-run, so it fits R2.
   Step 4 (orphan re-index) gains a read-only check for a heir that does not resolve and for index lines pointing
   at a file with superseded_by. Fold this into the existing step, with no new script and no fleet-sweep wiring.
3. One human-gated backfill: the 5 reso design-gate files.
Drop: `supersedes:` and `valid_until:` (the back-link invites one-sided drift and the date is the edit date),
the PostToolUse(Read) redirect hook (tiny reach; an in-file top banner does the same job at zero cost),
and the cc-memory-search ranking (the target does not exist).
