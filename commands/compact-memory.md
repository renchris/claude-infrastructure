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
4. Report: N archived, lines/bytes reclaimed, new `MEMORY.md` line count.
   > Reality check: in a dense, active memory most "resolved" entries carry a tail, so SAFE-AUTO
   > alone rarely clears the warning. That is by design — say so; the real lever is PROPOSE-ONLY.

## PROPOSE-ONLY (lossy-at-glance — NEVER auto-apply)
5. **Oversized index lines**: any `## Project State` entry whose index line exceeds ~200 chars
   while its detail already lives in the linked topic file. Propose a shortened <=200-char line
   (preserve the load-bearing hook + SHA + `[link]`). Show before/after; apply only on approval.
6. **Near-duplicates**: pairs of topic files whose rule overlaps. Show both descriptions side by
   side + a one-line rationale; the human picks merge / keep-both / supersede. NEVER auto-merge.
   HARD CONSTRAINT: entries sharing an `originSessionId` or cross-referenced via `[[...]]` are
   PRESUMED DISTINCT (e.g. `scope-freeze-at-intake` vs `mvp-ban-is-per-feature` encode different
   concepts) — flag, never merge.

## PROTECTED
- Any entry/line tagged `(PINNED)` is skipped entirely (explicit opt-out; mirrors hermes pin-to-protect).
- Never delete historical decisions, "Why:" rationale, learnings, or known issues (global File Update Rule).

## Output
A report: SAFE-AUTO actions (taken or previewed), then the PROPOSE-ONLY queue as an
approve/reject list. End with before/after `MEMORY.md` line count + the remaining gap to ~200 lines.
