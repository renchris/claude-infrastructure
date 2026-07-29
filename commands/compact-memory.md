---
name: compact-memory
description: Compact the project MEMORY.md index — SAFE-AUTO archive of fully-closed entries (reversible) + PROPOSE-ONLY dedupe/shortening shown as diffs for approval. Use when MEMORY.md passes its load warning (>200 lines / ~46KB). Hermes Curator analog; human-gated, INTEGRATE-never-overwrite.
allowed-tools: Read, Edit, Write, Glob, Grep, Bash, AskUserQuestion
argument-hint: "[--apply-safe to apply the SAFE-AUTO archival; default = dry-run report only]"
---

# /compact-memory — MEMORY.md curation (Hermes Curator analog)

Reduce the auto-loaded `MEMORY.md` index without losing information.
**Archive-not-delete, PINNED-protected, INTEGRATE-never-overwrite.** Every lossy edit is
PROPOSE-ONLY. Mirrors hermes-agent `agent/curator.py` (consolidate + archive, reversible),
minus the autonomous fork.

## Scope
- Operates ONLY on the project memory dir: the `MEMORY.md` index + its sibling topic `.md`
  files, resolved from the current project (`.../projects/<encoded-cwd>/memory/`).
  **Print the resolved path and confirm before editing.**
- Default is a DRY-RUN report. Apply the SAFE-AUTO half only when invoked with `--apply-safe`.
  PROPOSE-ONLY items are NEVER auto-applied — present diffs and get per-item approval.

## SAFE-AUTO (mechanical, reversible — only with `--apply-safe`)
1. Scan `## Project State` + `## Completed Work` for entries that are CLOSED with **no pending
   tail** — marked RESOLVED / DONE / SHIPPED / LANDED / SUPERSEDED **and** containing none of:
   `DEFERRED`, `NOT pushed`, `pending`, `backlog`, `open`, `gated on`, or a future-date obligation.
2. Move each such entry VERBATIM (tombstone intact — keep its SHA + date) into
   `memory/archive/MEMORY_ARCHIVE_<YEAR>-H<half>.md` (create dir/file if absent; **append**, never overwrite).
3. Remove ONLY those moved index lines from `MEMORY.md`. Topic `.md` files are NEVER deleted.
4. **Orphan re-index** (additive, never lossy): every topic `.md` in the memory dir must have an
   index line, and every index link must resolve to a file on disk. A topic file with no index
   line is INVISIBLE at session load — silently decayed memory. Re-index it (write a hook from its
   `description:`) and report it; a dangling link is reported, never auto-removed.
5. Report: N archived, N re-indexed, lines/bytes reclaimed, new `MEMORY.md` line count.
   > Reality check: in a dense, active memory most "resolved" entries carry a tail, so SAFE-AUTO
   > alone rarely clears the warning. That is by design — say so; the real lever is PROPOSE-ONLY.

## PROPOSE-ONLY (lossy-at-glance — NEVER auto-apply)

🚨 **PRECONDITION for every shortening — audit for INDEX-ONLY detail first. "its detail already
lives in the topic file" is an ASSUMPTION, and it is routinely false.** An index line accretes
corrections across sessions (`**CORRECTED**`, `**4th CORRECTION**`, a landed SHA, a build status)
that were appended to `MEMORY.md` and never written back to the topic file. Shortening such a line
is the only truly irreversible act in this command. Before proposing ANY shortened line, extract its
hard tokens — backticked code spans, 7-hex SHAs, numbers, ALL-CAPS terms — and grep each against the
linked topic file. Anything absent is index-only: **INTEGRATE it into the topic file first (Edit,
never Write), then shorten.** Re-run the audit against the proposal and report it CLEAN; a token
that survives only as a hyphenation/format variant is fine, a missing fact is not.
2026-07-26 (pass 2), this caught three facts that a semantic rewrite would still have destroyed:
the landed SHA `828816d`, an entire 3rd-instance root-cause finding (`c3edb2d`), and a whole
`P2-P4 BUILT / LAND-BLOCKED` build status. Also snapshot the pre-compaction index verbatim into
`archive/` so any hook can be restored word-for-word.

**Use TWO overlapping detectors, and a case-insensitive second pass.** Token-matching alone both
over- and under-reports. (a) Hard tokens — backticks, 7-hex SHAs, numbers, ALL-CAPS. (b) Clause
coverage — split the hook on `;`/`—`/`→` and flag any clause whose content words are largely
absent from the topic file; this catches index-only clauses built from common words that no token
scan can see. Then re-run **both against the finished file** to prove no surviving line outran its
topic file. The case-insensitive pass is what makes the audit usable: it separates genuine
absences from emphasis-only variants (`DELETES` vs "deleted", `PRE-EXISTING` vs "PREDATES",
`STARTING` vs "STARTS WITH"). 2026-07-29: of 38 first-pass flags across 91 entries only **2 were
real** — a `date -v` sign trap and the `C10` label — and without the second pass the 36 false
positives would have buried them.

6. **Oversized index lines**: any `## Project State` entry whose index line exceeds ~200 chars
   while its detail already lives in the linked topic file. Propose a shortened <=200-char line
   (preserve the load-bearing hook + SHA + `[link]`). Show before/after; apply only on approval.
   🚨 **REWRITE each line semantically — NEVER character-truncate.** A mechanical cut (`hook[:N]`,
   even on a clause boundary, even with a trailing `…`) severs the load-bearing rule while leaving
   a line that still reads as prose. 2026-07-26: a blind 300-char pass over 44 entries reduced
   *"done-evidence must read WHO drove the last turn, not WHEN"* to *"…must read WHO drove …"* —
   the rule was gone but the index looked healthy. Every shortened line must be a hand-written
   sentence that still STATES its rule; a trailing `…` is the tell that it does not. Rebuild from
   the full-fidelity text (`archive/`), never from an already-shortened index.
7. **Near-duplicates**: pairs of topic files whose rule overlaps. Show both descriptions side by
   side + a one-line rationale; the human picks merge / keep-both / supersede. NEVER auto-merge.
   HARD CONSTRAINT: entries sharing an `originSessionId` or cross-referenced via `[[...]]` are
   PRESUMED DISTINCT (e.g. `scope-freeze-at-intake` vs `mvp-ban-is-per-feature` encode different
   concepts) — flag, never merge.

## BUDGET THE PREFIXES FIRST (do this before writing a single line)

`- [Title](file.md) — ` is a **fixed cost no hook-cutting can touch**, and it is far larger than it
looks: measured 2026-07-29, **7,153 B of a 25,393 B index — 28%** — across 91 entries (avg 79 B).
So compute the real per-hook allowance up front:

```
per_hook_budget = (target_bytes - header - Σ prefix_bytes - newlines) / N
# 2026-07-29: (17,100 - 31 - 7,153 - 92) / 88  ≈  115 B   ...against a 199 B average.
```

That number decides *which job you are doing*: ~180 B/hook is a tightening pass (two rules per
line), ~115 B is a **one-governing-rule** pass. They are different jobs and mixing them wastes a
full rewrite — discovering this only after the first pass left it 1,105 B short cost a second pass.

**Titles are the near-lossless lever.** The *filename* carries identity (link target + graph key);
the title is only a human label. Retitling 49 entries via an explicit **hand-authored map**
(`"Land pipeline v2: verdict inversion"` → `"Land pipeline v2"`) freed ~800 B that no hook-cutting
could reach. A map is not truncation — every replacement is written out longhand.

**Do NOT budget for merging.** The `[[...]]`-cross-link rule below makes merges nearly unavailable
in a dense memory: 2026-07-29 *every* candidate (both `hermetic-*`, the two desk monitors,
`named-failure`/`gate-never-ran`, `argv-is-sampling`/`effect-read`, the three `feedback-*drive*`)
was cross-linked, and only **4 of 91** entries were honestly archivable. Plan the reduction as
**rewrite + a little archiving**; a plan leaning on merges under-delivers and tempts dishonest ones.

## CONCURRENCY — the index is written by other sessions while you work

`MEMORY.md` is appended to by sibling sessions mid-task. 2026-07-29 two arrived during one
compaction (+533 B, then +420 B), and a third session had left a **complete topic file with no
index line** (silent decay — re-index it per SAFE-AUTO 4).

- **`Edit`, never `Write`.** Edit's stale-read check is what catches a concurrent append — it fails
  loudly. A wholesale `Write` destroys the sibling's entry silently.
- **Re-measure immediately before applying**, and **fold new arrivals into the compaction** rather
  than clobbering them (audit them first, like any other line).
- **The byte target is a moving one.** Re-verify at the end, and if the index is over target purely
  because siblings appended after your pass, **report that** — do not re-grind other sessions' fresh
  entries to hit a number.

## PROTECTED
- Any entry/line tagged `(PINNED)` is skipped entirely (explicit opt-out; mirrors hermes pin-to-protect).
- Never delete historical decisions, "Why:" rationale, learnings, or known issues (global File Update Rule).
- Archiving *intentionally* leaves a topic file unindexed. Keep that honest by putting a pointer —
  `<!-- archived entries: archive/MEMORY_ARCHIVE_<year>-H<half>.md -->` — in the index header, so
  archived topics stay discoverable from the auto-loaded surface. Cheaper than a bullet per entry.

## Output
A report: SAFE-AUTO actions (taken or previewed), then the PROPOSE-ONLY queue as an
approve/reject list. End with before/after `MEMORY.md` line count + the remaining gap to ~200 lines.
