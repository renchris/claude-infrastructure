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
1. Scan the index for entries that are CLOSED with **no pending tail** — marked RESOLVED / DONE /
   SHIPPED / LANDED / SUPERSEDED **and** containing none of: `DEFERRED`, `NOT pushed`, `pending`,
   `backlog`, `open`, `gated on`, `BLOCKED`, or a future-date obligation. Scan the WHOLE index, not
   `## Project State` / `## Completed Work` — a mature index is a **flat bullet list with no `##`
   sections at all** (claude-infrastructure, 2026-07-29: 91 entries, zero `##` headings), so a
   section-scoped scan silently matches nothing and reports a vacuous "0 archivable".
   🚨 **Then apply the DURABILITY criterion — a CLOSED marker is NOT sufficient.** Archive only
   content that is a **one-time verdict or a closed-incident record**; a **durable rule** stays
   indexed no matter how closed it is, because archiving it removes a live rule from the
   auto-loaded surface — the exact silent decay step 4 exists to catch. A landed SHA is a
   *tombstone on a rule*, not evidence the rule is spent. Verified 2026-07-29: the marker+tail test
   alone passed 4 entries whose hooks are all live prohibitions — `Never re-add corpus`,
   `sharing needs the same ID *and* a shared dir`, `tolerate PARTIALS`, and a pane-keyed-marker
   design rule. All 4 must be KEPT; a spec without this criterion archives all 4.
2. Move each such entry VERBATIM (tombstone intact — keep its SHA + date) into
   `memory/archive/MEMORY_ARCHIVE_<YEAR>-H<half>.md` (create dir/file if absent; **append**, never overwrite).
3. Remove ONLY those moved index lines from `MEMORY.md`. Topic `.md` files are NEVER deleted.
4. **Orphan re-index** (additive, never lossy): every topic `.md` in the memory dir must have an
   index line, and every index link must resolve to a file on disk. A topic file with no index
   line is INVISIBLE at session load — silently decayed memory. Re-index it (write a hook from its
   `description:`) and report it; a dangling link is reported, never auto-removed.

   🚨 **A file is an orphan only after subtracting THREE exclusion sets — E1 the index, E2 the
   demotion record, E3 the always-loaded instruction files.** Each is a *different reason* a topic
   file is CORRECTLY unindexed, and each was found by a measurement in which the naive sweep was
   wrong about EVERY file it flagged. "No index line ⇒ invisible at session load" is the premise of
   this step and it is false for E2 and E3; run the sweep without them and it re-indexes the exact
   files a previous pass deliberately demoted, re-inflating the index on every subsequent run.

   **E2 — the demotion record. Steps 2-4 are otherwise exact inverses.** Archiving deliberately
   leaves a topic file on disk with no index line. Verified 2026-07-29 (claude-infrastructure): 4 of
   the 4 apparent "orphans" were the 4 entries the same-day pass had archived — re-indexing them
   would have undone it and added ~750 B.
   🚨 **DISCOVER that record by CONTENT; never key on a filename.** Measured 2026-08-05 on reso, the
   glob this rule used to prescribe (`archive/MEMORY_ARCHIVE_*.md`) matched **0 of the 577** demoted
   links: reso keeps its cold record at the memory dir's TOP level as `MEMORY-ARCHIVE.md`, and its
   `archive/MEMORY_ARCHIVE_2026-H1.md` holds none. A glob-only E2 therefore read **590** orphans
   where there were **13**, and would have re-indexed 577 entries a standing rotation rule had
   demoted. So build E2 from **every `.md` under the memory dir and its `archive/` except `MEMORY.md`
   itself that carries `](….md)` links** — those are the demotion records, whatever they are called.
   ⚠️ **A whole-index SNAPSHOT is not a demotion record** (`MEMORY_INDEX_SNAPSHOT_*`,
   `MEMORY_INDEX_PRE-COMPACT_*`, `MEMORY_PRECOMPACT_*`, `MEMORY.md.bak-*` — 10 such files in
   claude-infrastructure's `archive/`). It records what was indexed at a moment, so trusting it as
   E2 silently excuses a decay that happened afterwards. Report a file whose ONLY citation is a
   snapshot; do not silently trust it either way.

   **E3 — cited by explicit path from an always-loaded instruction file** (project `CLAUDE.md`,
   `.claude/CLAUDE.md`, `.claude/rules/**`). Such a file is already reaching every session through
   the citing instruction file, so re-indexing buys **zero visibility** and spends index bytes —
   the scarcest resource this command manages. Measured 2026-08-05 on reso: after E1+E2, **13 of 13**
   remaining "genuine orphans" were cited this way (`Reference: `memory/x.md``, `See memory: `x.md``,
   `Memory: `x.md``) — a 100% false-positive rate for the whole residual pool. Re-indexing them
   would have added ~13 lines / ~2-3 KB to a 19.7 KB index, pushing it back over reso's own ~20 KB
   rotate threshold and re-triggering the rotation that had just been done. reso's
   `MEMORY-ARCHIVE.md` had already recorded this rule and this count on 2026-07-27; the finding never
   reached this command, which is why the sweep kept re-deriving it. E3 is project-shaped, not
   universal — claude-infrastructure has 2 instruction files and 0 orphans, so E3 legitimately
   measures 0 there. Report E3 hits as *correctly unindexed, reachable via `<citing file>`*, never as
   decay.

   A genuine orphan is a topic file in NONE of the three: not in the index, not in any demotion
   record, not cited from an always-loaded instruction file. **Run it, do not eyeball it** — every
   miss above came from applying an exclusion rule by hand:

   ```bash
   # bash, NOT zsh — needs nullglob, or a non-matching archive/ glob aborts the substitution.
   M=<memory-dir> P=<project-dir>; shopt -s nullglob
   recs=(); for f in "$M"/*.md "$M"/archive/*.md; do          # E2 by CONTENT, never by filename
     b=${f##*/}; [[ $b == MEMORY.md || $b == *SNAPSHOT* || $b == *PRE-COMPACT* || $b == *PRECOMPACT* ]] && continue
     grep -qE '\]\([A-Za-z0-9._-]+\.md\)' "$f" && recs+=("$f")
   done
   lines() { grep -ohE '\]\([A-Za-z0-9._-]+\.md\)' "$@" 2>/dev/null | tr -d ']()'; }
   comm -23 <(printf '%s\n' "$M"/*.md | xargs -n1 basename | sort -u) \
            <( { printf 'MEMORY.md\n'; printf '%s\n' "${recs[@]##*/}"
                 lines "$M/MEMORY.md" "${recs[@]}"; } | sort -u ) |     # minus E1 + E2
   while read -r f; do                                                  # minus E3
     grep -rqF "${f%.md}" "$P/CLAUDE.md" "$P/.claude/CLAUDE.md" "$P/.claude/rules" 2>/dev/null \
       || echo "ORPHAN $f"
   done
   ```

   Verified 2026-08-05: **0 orphans on both** reso (13 residual, all E3) and claude-infrastructure
   (229 topic files) — and a **positive control** proves that zero is not vacuous. On a fixture whose
   only demotion record is a non-conventionally-named `MEMORY-ARCHIVE.md`, it prints exactly the
   never-indexed file and the snapshot-only file, while the same fixture makes the old
   glob-only-plus-no-E3 sweep report 3 false positives.
5. Report: N archived, N re-indexed, lines/bytes reclaimed, new `MEMORY.md` line count.
   > Reality check: in a dense, active memory most "resolved" entries carry a tail, so SAFE-AUTO
   > alone rarely clears the warning. That is by design — say so; the real lever is PROPOSE-ONLY.
   > 2026-07-29 SAFE-AUTO was a **legitimate no-op** on all counts (0 archivable after the
   > durability criterion, 0 genuine orphans, 0 dangling) — report a no-op as a finding, never as
   > a reason to reach for a lossy edit the byte budget does not need.

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

## THE TWO-TIER HOT/COLD SPLIT — the lever to reach for once rewriting cannot reach the target

🚨 **When hooks are already ~one-governing-rule and nothing is archivable, NO rewrite can hit the
target — the binding constraint is CARDINALITY, not entry size.** Measured 2026-07-30 at 149
entries: filenames alone are **5,518 B (19%) and immutable** (link target + graph key), and with
syntax+header the floor is ~7,061 B; the `17.1 KB` the PostToolUse nudge demands works out to
**~67 B/entry — below one sentence**. Grinding hooks past that only severs rules while leaving
lines that still read as prose. The answer is **fewer indexed entries, not smaller ones.**

**The procedure** (operator-approved 2026-07-30; the lever every subsequent pass has used —
07-30 149→111 @ 22.4 KB, then 07-31, 08-01, 08-05 105→92 @ 22.7 KB):

1. Move whole entries **VERBATIM** into `archive/MEMORY_ARCHIVE_<YEAR>-H<half>-COLD.md`. Nothing is
   deleted, no line is rewritten, every topic file stays on disk untouched. **Restore = paste the
   line back into `MEMORY.md` and delete it there.** This is reversible, so it is not the lossy
   PROPOSE-ONLY class — but it does remove live rules from the auto-loaded surface, so it is
   authorized by the byte budget, never by ritual.
2. **Selection rule.** HOT keeps: every `feedback` operator-directive, every `reference` tooling
   entrypoint, all live-pending state, and every **graph hub (>=4 inbound `[[links]]`)**. COLD takes
   `project`-type entries with **<=3 inbound links**, oldest first.
   ⚠️ **Recency alone is the WRONG rule** — it sent `effect-read-predicate-red-proof` (7-8 inbound),
   `reference-landing-safety-tooling` and the `/accounts` entrypoint cold. Rank *within* the
   eligible set, never across it.
3. **Cut on a stated boundary, not a byte count.** Prefer "the COMPLETE oldest eligible tier"
   (a date boundary) and, if that is short, extend into the next date taking only **zero-inbound**
   entries — least load-bearing in the graph. Write the boundary into the COLD file so the next
   pass can see what rule produced the split rather than guessing.
4. **Define done as HEADROOM.** Target ~2.5 KB under the limit, not the limit itself: the index
   re-inflates ~1 KB/11.6 h at burst and ~470 B/day at the lifetime average, so landing *at* the
   limit means the next sibling append silently drops entries again. Report headroom + rate.

**Name the cold file `archive/MEMORY_ARCHIVE_<YEAR>-H<half>-COLD.md`** so the record is
self-describing and sorts beside its warm sibling. This used to be load-bearing — step 4 globbed
`archive/MEMORY_ARCHIVE_*.md`, so a file named `MEMORY_COLD.md` fell outside it and the next sweep
re-indexed every cold entry, silently undoing the split. **Step 4's E2 no longer depends on the
name** (it discovers demotion records by content), because the prescription was measurably not
followed: reso's live cold record is a top-level `MEMORY-ARCHIVE.md` holding 577 links, and the glob
matched 0 of them. Follow the convention anyway; do not rely on anyone else having followed it.

**A cold move and a decayed orphan look identical from the index.** Both are topic files with no
index line — as is a file cited only from an always-loaded instruction file (step 4 E3). Distinguish
them by the COLD/archive record and by that citation, and when a genuine orphan turns up during a
split, record it in COLD with a note saying it was *never indexed* rather than moved — otherwise the
next reader reads it as a deliberate demotion.

## CONCURRENCY — the index is written by other sessions while you work

`MEMORY.md` is appended to by sibling sessions mid-task. 2026-07-29 two arrived during one
compaction (+533 B, then +420 B), and a third session had left a **complete topic file with no
index line** (silent decay — re-index it per SAFE-AUTO 4, but only after subtracting the archive's
entry set: an archived topic file looks identical to a decayed one from the index alone).

- **`Edit`, never `Write`.** Edit's stale-read check is what catches a concurrent append — it fails
  loudly. A wholesale `Write` destroys the sibling's entry silently.
- **Re-measure immediately before applying**, and **fold new arrivals into the compaction** rather
  than clobbering them (audit them first, like any other line).
- **The byte target is a moving one.** Re-verify at the end, and if the index is over target purely
  because siblings appended after your pass, **report that** — do not re-grind other sessions' fresh
  entries to hit a number.

## RE-INFLATION — compaction is a treadmill, so define "done" as headroom, not bytes

A pass does not close the problem; it buys time. Measured on claude-infrastructure: the 2026-07-29
pass landed **17,088 B at 01:13**, and by **12:46 the same day the index was 18,179 B** — **+1,091 B
in 11.6 h**, fully reconciled as **4 new entries (1,002 B) + ~89 B of corrections appended to 3
already-compacted lines**. Two rates bracket the return trip to the 24.1 KB trigger that filed this
work: **~3 days** at that burst rate, **~17 days** at the project's lifetime average (91 entries over
~7 weeks ≈ 1.8/day) — that day ran ~4× the average, so treat 3 days as a floor, not a forecast.

Consequences for how you run this command:

- **Verify the trigger before you curate.** A backlog item quoting a size is a *timestamped
  observation*, not the current state — a sibling pass may already have cleared it. Re-measure first;
  2026-07-29 the item said 24.1 KB and the index was 18.2 KB, already 6.5 KB under. Curating anyway
  would have spent an irreversible lossy pass on headroom that already existed.
- **A no-op close is a legitimate outcome** when SAFE-AUTO is clean and the index sits under trigger.
  Do not manufacture lossy work to look productive — the byte budget, not the ritual, authorizes a
  shortening. Report the headroom and the rate.
- **Corrections land on the index, not the topic file.** ~89 B of the re-inflation was sessions
  appending a clause to an *existing* compacted line, which is why a compacted line drifts back over
  budget without any new entry appearing. This is the mechanism behind the PROPOSE-ONLY precondition
  above: those appended clauses are the index-only facts a later shortening would destroy.
- **The durable fix is a budget at append time**, not a periodic hand-curation: an entry written at
  ~115 B of hook never needs a pass. Periodic compaction is the fallback for entries written without
  one, and its cost (two full hand-audited passes, 2026-07-26 and 07-29) is the argument for the
  cheaper rule. Fixing it at the write surface is out of this command's scope — the nudge that
  prompts the append (`hooks/memory-nudge.sh`) is where a budget would have to bind.

## PROTECTED
- Any entry/line tagged `(PINNED)` is skipped entirely (explicit opt-out; mirrors hermes pin-to-protect).
- Never delete historical decisions, "Why:" rationale, learnings, or known issues (global File Update Rule).
- Archiving *intentionally* leaves a topic file unindexed. Keep that honest by putting a pointer —
  `<!-- archived entries: archive/MEMORY_ARCHIVE_<year>-H<half>.md -->` — in the index header, so
  archived topics stay discoverable from the auto-loaded surface. Cheaper than a bullet per entry.

## Output
A report: SAFE-AUTO actions (taken or previewed), then the PROPOSE-ONLY queue as an
approve/reject list. End with before/after `MEMORY.md` line count + the remaining gap to ~200 lines.
