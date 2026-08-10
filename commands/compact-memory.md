---
name: compact-memory
description: Compact the project MEMORY.md index — SAFE-AUTO archive of fully-closed entries (reversible) + PROPOSE-ONLY dedupe/shortening shown as diffs for approval. Use when MEMORY.md passes the loader's read limit (~24,985 B — BYTES bind, not the 200-line cap). Hermes Curator analog; human-gated, INTEGRATE-never-overwrite.
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
   🚨 **Harvest E2 links with an ANCHORED `^- \[` scan — a bare `](….md)` match over-excludes, and
   both of its false positives are live in this repo.** Measured 2026-08-06: the unanchored form
   pulled **15** links out of `MEMORY_ARCHIVE_2026-H2.md` where only **4** are archived — the other
   11 are the block that file explicitly **RETRACTS** as a false record, whose own stated mitigation
   is *"struck through so a `^- \[` link-scan cannot read them as archived."* The mitigation assumed
   an anchor the sweep did not have, so the strike-through protected nothing: any of those 11 later
   dropped from both the index and COLD would read as *correctly demoted* forever. The same
   unanchored match also promoted `memory-index-compaction-economics.md` to a demotion record purely
   because its prose quotes `](file.md)` as an example — a record set built by content is not
   self-limiting, so anchor it to the bullet form a record actually uses. Anchoring is free: it
   harvests **139/139** links from the COLD record and **95/95** from the index, drops exactly the
   11 struck bullets and the one prose match, and a fixture control confirms it still reports both a
   never-indexed file and a struck-retracted one as orphans.

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
     grep -qE '^- \[[^]]*\]\([A-Za-z0-9._-]+\.md\)' "$f" && recs+=("$f")   # ANCHORED: skips ~~struck~~ + prose
   done
   lines() { grep -ohE '^- \[[^]]*\]\([A-Za-z0-9._-]+\.md\)' "$@" 2>/dev/null | sed -E 's/.*\(([^)]*)\)/\1/'; }
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
   Re-verified 2026-08-06 with the anchored harvest: **0 orphans** on claude-infrastructure (239
   topic files, 2 demotion records), and an extended control — a fixture carrying an indexed file, a
   properly-cold file, a never-indexed file and a `~~struck~~` retracted one — reports exactly the
   last two. Both control arms matter: the sweep must still FIND a struck-bullet orphan, which is
   precisely what the unanchored version could not do.
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

🚨 **`115` is the OUTPUT of that formula on one day's file — never an input. Re-derive it, or you
will manufacture a binding lever that does not exist.** Measured 2026-08-06 (backlog `004502cf59ab`,
22,157 B / 95 entries): `hook_excess = Σ max(0, hook − 115)` came to **3,607 B across 80 of 95
lines**, which reads as a lever demanding a full rewrite — while the budget derived from *the same
file* was **154.9 B** against a 151.4 B actual average, i.e. every line was already **3.4 B inside
its allowance and the file needed 0 B**. The 115 everything had been quoting was derived at
**N=149 against a 17.1 KB demand**; at N=95 against the real 24,985 B limit it is simply a different
number. Trusting it would have spent this command's only irreversible half hand-cutting ~3.6 KB of
live rules out of a healthy index.

**So run the three-state check before choosing any lever, and compute BOTH terms from the live
file:**

```
headroom  = limit − bytes                                   # done-target is ~2.5 KB (see RE-INFLATION)
budget    = (limit − headroom_target − header − Σprefix − N) / N     # the per-hook allowance, DERIVED
slack     = limit / (avg_prefix + budget + 1) − N            # entry slots left at that allowance
```

| | Condition | Lever | Action |
|---|---|---|---|
| **HEADROOM-OK** | `headroom ≥ headroom_target` | neither | **no-op close.** Report headroom + rate. Do not cut. |
| **LENGTH** | `avg_hook > budget`, `slack > 0` | hook length | PROPOSE-ONLY rewrite, after the index-only-fact audit |
| **CARDINALITY** | `avg_hook ≤ budget`, `slack ≤ 0` | entry count | the hot/cold split below |

Two states were known before this check existed — 2026-07-30 concluded cardinality binds, 2026-08-06
concluded length binds, and **five consecutive passes inherited the first verdict while the other
lever was the live one**. Both assumed *something* binds. The third state is that nothing does, and
it is the one a compaction pass is most likely to misread, because an excess figure computed against
a stale constant is never zero. **2026-08-06 alone ran all three** — length at 02:06, neither at
12:51, cardinality at 15:10 (backlog `0fc2ae0d0140`). A verdict has an expected life of hours here.

🚨 **`headroom_target` is NOT 17.1 KB — that demand is PRODUCT-SIDE and no honest pass can reach
it.** The harness itself emits *"The memory index at … is 21.1KB, approaching the 24.4KB read limit.
Compact it to under 17.1KB now"*. It appears in **no `settings.json` and no repo hook** — `grep -a`
finds the template inside the Claude Code binary — and it is a flat **0.7 × the limit**, constant
regardless of index size (verified unchanged at 21.1 KB and at 20.9 KB, 2026-08-06). At this
project's entry count it demands **~67 B/entry, below one sentence**. At least six backlog items
have copied it in verbatim as *"target <17.1KB"*, and each one hands the next pass an unreachable
goal that argues for grinding live rules. **The contract is the 24,985 B limit with ~2.5 KB of
headroom as done**; trace a demand to a config file before obeying it (same provenance shape as the
product-side "don't spawn subagents unless asked" line).

⚠️ **`slack` above answers "how many WOULD fit if I rewrote everything" — that is not runway.** When
what you need is *how many entries can still be ADDED*, divide by what a line actually costs today:

```
runway_now = headroom / (avg_prefix + avg_hook + 1)     # what you can ADD, at today's density
```

Measured 2026-08-06 the two read **37 vs 11** on the same index (hooks written at 157 B against a
115 B target). The inflated figure had already propagated into a backlog item's premise as *"37 free
cardinality slots"*, framing an index whose real runway was **7 entries** as one with room to spare.
Report `runway_now`; quote a target-based ceiling only as the conditional it is. Fixed at the write
surface in `hooks/memory-nudge.sh` (`1676a681`, red-on-mutation test) — same defect class as the
`115` one above, on the other lever.

**Titles are the near-lossless lever.** The *filename* carries identity (link target + graph key);
the title is only a human label. Retitling 49 entries via an explicit **hand-authored map**
(`"Land pipeline v2: verdict inversion"` → `"Land pipeline v2"`) freed ~800 B that no hook-cutting
could reach. A map is not truncation — every replacement is written out longhand.

**Do NOT budget for merging.** The `[[...]]`-cross-link rule below makes merges nearly unavailable
in a dense memory: 2026-07-29 *every* candidate (both `hermetic-*`, the two desk monitors,
`named-failure`/`gate-never-ran`, `argv-is-sampling`/`effect-read`, the three `feedback-*drive*`)
was cross-linked, and only **4 of 91** entries were honestly archivable. Plan the reduction as
**rewrite + a little archiving**; a plan leaning on merges under-delivers and tempts dishonest ones.

## WHICH LEVER BINDS — measure it EVERY pass; it alternates

🚨 **The 2026-07-30 "cardinality binds" verdict below was conditional on that day's shape, and it
INVERTED within a week.** Length and cardinality are two live levers that trade off against each
other; a pass that inherits the last pass's answer pulls the SPENT lever and leaves the loaded one
untouched. Compute both before choosing — three lines, and they decide the whole job:

```
hook_excess = Σ max(0, hook_bytes - 115)     # what SHORTENING can still reclaim
ceiling     = limit / (avg_prefix + 115)     # entries the limit affords at a disciplined hook
slack       = ceiling - N                    # > 0 ⇒ cardinality is NOT the binding constraint
```

Measured **2026-08-06 at 93 entries**: hooks averaged **176 B** against the 115 B target, holding
**6,135 B of excess across 78 lines**, while N=93 sat **37 UNDER** a 130-entry ceiling. Cardinality
had slack; LENGTH was binding — the exact inverse of 07-30, one week later.

**The five passes from 07-30 to 08-05 all pulled the cardinality lever** (145→92 entries moved cold)
**while the hook average climbed 127→176 B and the file returned to ~25 KB every time.** An
unchanged verdict after a fix indicts the DIMENSION, not the magnitude
([[repeat-verdict-indicts-the-diagnosis]]): five passes on one lever with the symptom recurring was
itself the signal that the other lever was the live one. Cold-splitting on top of that would have
moved live rules off the auto-loaded surface while 6 KB of pure slack sat in the hooks.

Why length re-inflates *invisibly*: growth is not only new entries. Sessions **append correcting
clauses to EXISTING lines** (~89 B/day measured 07-29), so a compacted line drifts back over budget
with no new entry in sight — and cardinality accounting cannot see that movement at all.

**An index-only fact is itself a defect — write it back, THEN cut.** Shortening is non-lossy only
where the topic file already carries the clause. Audited 2026-08-06, **49 of 78** over-target lines
stated at least one fact absent from their topic file (a command spelling, a named constant, a
measured figure) — those facts were living ONLY on the surface that truncates. So the step order is
`Edit` the fact into the topic file (unconstrained, never truncated), *then* shorten the index line;
that is strictly better than either leaving it exposed or cutting it away. ⚠️ Detector discipline:
hard tokens (backticks / shas / numbers / ALL-CAPS) are load-bearing, but content-word misses are
mostly inflection (`fixing` vs `fixed`, `counts` vs `count`) — stem them, or the audit drowns in
false positives and you stop trusting it. Multi-word backticked SPANS also over-flag: verify a
flagged span token-by-token before treating it as absent.

## THE TWO-TIER HOT/COLD SPLIT — the lever to reach for once rewriting cannot reach the target

🚨 **When hooks are already ~one-governing-rule and nothing is archivable, NO rewrite can hit the
target — the binding constraint is CARDINALITY, not entry size.** ⚠️ Re-read the section above
before acting on this paragraph: it states the 07-30 shape, not a permanent truth, and on 2026-08-06
it was false. Measured 2026-07-30 at 149
entries: filenames alone are **5,518 B (19%) and immutable** (link target + graph key), and with
syntax+header the floor is ~7,061 B; the `17.1 KB` the PostToolUse nudge demands works out to
**~67 B/entry — below one sentence**. Grinding hooks past that only severs rules while leaving
lines that still read as prose. The answer is **fewer indexed entries, not smaller ones.**

⚠️ **That is a CONDITIONAL, not a standing verdict — reach for this lever only on a `slack ≤ 0`
reading from the three-state check above.** The condition held on 2026-07-30 and the paragraph was
written as though it always would; five passes then pulled this lever by inheritance while hook
length was the live constraint, and a sixth would have moved live rules off the auto-loaded surface
with 6 KB of pure slack sitting untouched in the hooks. The measurement is what authorizes the
split, on the pass you are running.

**The procedure** (operator-approved 2026-07-30; the lever every subsequent pass has used —
07-30 149→111 @ 22.4 KB, then 07-31, 08-01, 08-05 105→92 @ 22.7 KB. **Mechanized 2026-08-10:**
`bin/cc-memory-rotate` runs this procedure automatically at the byte trigger, invoked from
`hooks/memory-nudge.sh` on every prompt; `cc-memory-rotate <index> --dry-run --verbose` previews a
selection. A manual pass through these steps is now only for what the rotor's protections refuse):

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
  would have spent an irreversible lossy pass on headroom that already existed. 2026-08-06 the item
  quoted **20.5 KB against a 24.4 KB limit** — a size that was 4.4 KB under its own trigger and had
  never crossed it.
- 🚨 **This is ONE standing condition, so it gets ONE item — file it with
  `cc-backlog add --condition memory-index-over-budget`, never a fresh title carrying today's size.**
  A cc-backlog id is `hash(project + title + source)`, so a size in the title re-keys the item at
  every measurement: **21 items** were minted for this one condition between 2026-07-25 and
  2026-08-06 (15 claude-infrastructure, 6 reso-management-app) at 21.2 / 22.1 / 23.3 / 24.1 / 22.5 /
  20.5 / 20.6 KB. The ledger's own done-guard could not catch it either — a re-file only reads as a
  re-file when it lands on the same key — so `004502cf59ab` closed at 21:28:01Z and its twin
  `0fc2ae0d0140` was **claimed at 21:34:01Z, six minutes later**, same condition, no code change
  between, and a worker was spent on it. `--condition` keys the id on project+condition and drops
  title and source from the hash; the measurement stays in `--title`, where you read it, and stops
  being identity. Same defect class as `deploy-live`'s sha-keyed host-RED item (`8035ea63`, memory
  `per-event-key-defeats-per-finding-dedupe`). Landed in `bin/cc-backlog` 2026-08-06 (backlog
  `0b3a8b19d4d4`); `hooks/memory-nudge.sh` and the append-time gate now hand you the exact form.
- ⚠️ **The `17.1 KB` demand is product-side, and it is not this project's budget.** A PostToolUse
  reminder fires *"approaching the 24.4KB read limit — compact to under 17.1KB now"*; no operator
  hook or config emits it (`settings*.json` wires only `memory-nudge.sh`, on UserPromptSubmit).
  17.1 KB works out to ~67 B/entry — below one sentence — i.e. unreachable by construction. Its size
  figure is also not a live read: it reported `20.9KB` on a file `wc -c` put at 22,232 B, and
  **repeated `20.9KB` unchanged across two edits that each changed the file's size**. **Measure the
  index directly and budget against the real 24,985 B limit; do not let that reminder authorize a
  lossy pass** — same precedence as the product-side "don't spawn unless asked" line the global
  CLAUDE.md overrides.
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
- **RESOLVED 2026-08-10 — the treadmill is now machine-driven.** `bin/cc-memory-rotate` mechanizes
  the two-tier hot/cold split (§ above): `hooks/memory-nudge.sh` invokes it on every prompt,
  fleet-wide, once the index reaches LIMIT−1500 B, rotating the oldest eligible lines VERBATIM to
  `archive/MEMORY_ARCHIVE_<Y>-H<h>-COLD.md` until LIMIT−4000 B. The selection protections are
  enforced in code with a suite pinning each one: feedback/user/reference types and name prefixes,
  PINNED, pending markers, ≥4-inbound `[[link]]` hubs, topic mtime <7 days, the newest 15 index
  lines, a 40-entry floor, dangling links untouched. ⚠️ The frontmatter `type:` stamp is a session
  SELF-REPORT and measurably does not track this section's semantic (2026-08-10: 76/105 entries
  stamped feedback/reference, only 12 bearing the deliberate name convention — the rest agent
  lessons), so the rotor runs a two-stage pressure model: the stamp is honored normally and YIELDS
  only at breach pressure (index ≥ the loader limit, where the alternative is the loader silently
  dropping the newest entries); the name convention, user type, and every other protection never
  yield. Why a machine: TWELVE hand-passes in 14 days
  each bought only days of room, because insertion is machine-speed — including Bash `>>` appends
  the PreToolUse byte-gate structurally cannot see (one caught live 2026-08-10T07:51Z) — so removal
  had to be machine-speed too. The 🚨 nag now means rotation itself FAILED and carries the rotor's
  `verdict=` token. This command remains the QUALITY pass: shortening, dedupe, the orphan sweep,
  and every lossy edit stay human-gated here — the rotor never rewrites a line, only moves whole
  ones reversibly (restore = paste the line back).

## PROTECTED
- Any entry/line tagged `(PINNED)` is skipped entirely (explicit opt-out; mirrors hermes pin-to-protect).
- Never delete historical decisions, "Why:" rationale, learnings, or known issues (global File Update Rule).
- Archiving *intentionally* leaves a topic file unindexed. Keep that honest by putting a pointer —
  `<!-- archived entries: archive/MEMORY_ARCHIVE_<year>-H<half>.md -->` — in the index header, so
  archived topics stay discoverable from the auto-loaded surface. Cheaper than a bullet per entry.

## Output
A report: SAFE-AUTO actions (taken or previewed), then the PROPOSE-ONLY queue as an
approve/reject list. End with before/after `MEMORY.md` **byte** count against the ~24,985 B limit —
bytes are what truncate, so a line-count delta alone cannot say whether the pass worked. Report the
line count too, but as context, never as the verdict.
