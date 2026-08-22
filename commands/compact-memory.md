---
name: compact-memory
description: Compact the project MEMORY.md index — SAFE-AUTO archive of fully-closed entries (reversible) + PROPOSE-ONLY dedupe/shortening shown as diffs for approval. Use when MEMORY.md passes either loader cap (25,000 CHARS of the stripped, trimmed index, or 200 LINES — see THE UNIT). Hermes Curator analog; human-gated, INTEGRATE-never-overwrite.
allowed-tools: Read, Edit, Write, Glob, Grep, Bash, AskUserQuestion
argument-hint: "[--apply-safe to apply the SAFE-AUTO archival; default = dry-run report only]"
---

# /compact-memory — MEMORY.md curation (Hermes Curator analog)

## 🚨 THE UNIT — read this before sizing any cut (corrected 2026-08-15)

Everything below this section sizes cuts in **BYTES against 24,985**. That premise is dead, and it
was wrong in three directions at once, all of them OVER-stating the index. Read out of the shipped
bundle (Claude Code 2.1.233, cc-backlog `7a56de4c54ab`; derivation in
`hooks/lib/memory-index-measure.sh`), the loader:

1. **strips the YAML frontmatter** (`/^---\s*\n([\s\S]*?)---\s*\n?/`) — a `--- … ---` header
   costs nothing;
2. **strips block HTML comments** — including the `<!-- cold tier: … -->` pointer
   `bin/cc-memory-rotate` writes into the index itself;
3. **trims**, then compares **`String.length` — UTF-16 CODE UNITS, not bytes** — against
   **25,000**, and the line count against **200**.

Three consequences for a compaction pass:

- **`—`, `⇒`, `·`, `≠` cost ONE each, not three.** A pass that "reclaimed 900 bytes" by trimming
  multibyte punctuation reclaimed ~300. Measure with `hooks/lib/memory-index-measure.sh`
  (`mim_measure_file <index>` → `"<chars> <lines>"`), never with `wc -c`.
- **"BYTES bind, not the 200-line cap" is FALSE** — that line stood in this file's own description
  until 2026-08-15. The loader truncates on *either* cap, and on an index of one-line entries the
  LINE cap binds FIRST: 210 short entries breach it while sitting 20 KB inside the char budget.
  Report both figures; name which one is binding.
- **Only removing a LINE clears a line breach.** Shortening hooks moves the char figure and nothing
  else, so the lever table below (§ WHICH LEVER) answers the char question only.
- 🚨 **`17,100` IS THE SAME MISTAKE, AND `bytes → chars` DOES NOT REPAIR IT** (2026-08-21). Both
  product-side labels are the same quantity over 1024, and this file expanded them with **two
  different KB conventions**: `24.4 KB × 1024 = 24,985.6` → `24985` (binary), but
  `17.1 KB × 1000` → `17100` (decimal). One producer, one unit, two answers. The product's own
  observed ratio is a flat **0.7 × the limit** (recorded below, verified unchanged at two index
  sizes on 2026-08-06), and `0.7 × 25,000 = 17,500` units — which is `17,500/1024 = 17.09`, the
  label, exactly as `25,000/1024 = 24.41` is the other one. **So the product-side target is ~17,500
  UTF-16 units**, and `17,100` was never a byte count of anything: substituting *bytes → chars* into
  it leaves it **400 units short**, understating an already-hostile target. Every historical
  per-entry figure derived from it (67 · 52 · 115 · 167 · 395) inherits that error on top of the
  byte/char one. Re-derive from `0.7 × 25,000`, or better, do not target it at all — see the
  PROVENANCE/ARITHMETIC split at § BUDGET THE PREFIXES FIRST.

Every formula below stays structurally correct with *bytes → chars* substituted and the line cap
checked alongside — **with the one exception just named: the `17,100` constant needs re-deriving,
not substituting.** They are left as written rather than rewritten, because their DERIVATIONS and
the incidents attached to them are the record; only the unit was wrong.

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
     grep -qE '^- \*{0,2}\[.*\([A-Za-z0-9._-]+\.md\)' "$f" && recs+=("$f")  # ANCHORED: skips ~~struck~~ + prose
   done
   # target = the LAST (….md) on the line. NOT [^]]* — see the 🚨 below.
   lines() { grep -ohE '^- \*{0,2}\[.*\([A-Za-z0-9._-]+\.md\)' "$@" 2>/dev/null | sed -E 's/.*\(([A-Za-z0-9._-]+\.md)\).*/\1/'; }
   comm -23 <(printf '%s\n' "$M"/*.md | xargs -n1 basename | sort -u) \
            <( { printf 'MEMORY.md\n'; printf '%s\n' "${recs[@]##*/}"
                 lines "$M/MEMORY.md" "${recs[@]}"; } | sort -u ) |     # minus E1 + E2
   while read -r f; do                                                  # minus E3
     hit=0                                                              # SKIP MISSING PATHS — see below
     for c in "$P/CLAUDE.md" "$P/.claude/CLAUDE.md" "$P/.claude/rules"; do
       [ -e "$c" ] || continue
       grep -rqF "${f%.md}" "$c" 2>/dev/null && { hit=1; break; }
     done
     [ "$hit" = 1 ] || echo "ORPHAN $f"
   done
   ```

   🚨 **`[^]]*` IS THE WRONG WAY TO ANCHOR, and it fails in the safe-looking direction — the snippet
   above carried it for two weeks.** A hook is free to contain a `]`, and the hooks most likely to
   are the ones quoting a regex or an array index. Measured 2026-08-22 on reso, where a single index
   line quotes `grep -qE "Tests +[0-9]+ passed"`: `[^]]*` stops at that `]`, never reaches the link,
   and the line vanishes from the harvest. The damage compounds because the SAME expression harvests
   the E2 demotion record — reso's `MEMORY-ARCHIVE.md` reported **459** links against a true **655**,
   so **24 correctly-demoted topic files came back as ORPHAN** and a pass trusting it would have
   re-indexed all 24 into an index that was already 214 chars from breach. The instrument even
   announced itself: **33 index links against `N=34` entries**, and `cc-memory-rotate` said
   `unparseable=1` in the same breath. **Match `.*` and take the LAST `(….md)` group** (a bullet has
   exactly one link target and it terminates the line), and **reconcile the harvested count against
   `grep -cE '^- \*{0,2}\['` before believing any orphan list** — an off-by-one there is not cosmetic,
   it is one silently dropped rule. Same family as the `^- \[` vs `^- \*{0,2}\[` bold-bullet
   under-count this file already documents: **both are a link scan whose anchor is narrower than the
   bullets it must match, and both report a clean-looking answer while under-reading.**

   🚨 **Why E3 iterates instead of passing all three paths to one `grep`.** The one-shot form —
   `grep -rqF "$stem" "$P/CLAUDE.md" "$P/.claude/CLAUDE.md" "$P/.claude/rules" || echo ORPHAN` —
   reports **every** residual file as an orphan on any project missing one of those paths, because
   an unreadable operand makes grep exit 2 **even when another operand matched**, and `||` cannot
   tell 2 from 1. Measured on reso 2026-08-05 (that worktree has no `.claude/CLAUDE.md`): the
   documented sweep printed **13 ORPHANs**; restricting the grep to paths that exist printed **0
   orphans / 13 E3-ok** — which is the count this section's own text records, so the spec was
   self-inconsistent with its own snippet. The harm is exactly the failure two paragraphs up: a
   pass that trusts the output re-indexes 13 correctly-unindexed files and re-triggers the rotation
   it just performed.

   **And it is environment-dependent, which is why it survived so long.** Re-measured 2026-08-12,
   same fixture, match present + two paths missing:

   | grep the caller resolves | rc | verdict |
   |---|---|---|
   | `/usr/bin/grep` (BSD) | **0** | a match wins over the missing-operand error — snippet looks fine |
   | bare `grep` in an interactive session (shell function) | **2** | `\|\|` fires ⇒ **false ORPHAN** |

   So the snippet was correct under the grep a *script* gets and broken under the grep a *reader
   pasting it* gets. Iterating over paths that exist is right under **both**, which is the property
   to keep — do not "fix" this by appending `/dev/null`, which does not help: the missing operand
   still errors. (Same class as memory: `interactive-grep-is-ugrep-not-usr-bin-grep`.)

   ⚠️ **`shopt -s nullglob` is a bash builtin and the first line means it.** Run this block in
   `bash`, not in the zsh an interactive session gives you — in zsh `shopt` is a
   `command not found` and the block has only ever appeared to work because the globs happened to
   match. `bash -c '...'` or a `#!/usr/bin/env bash` script; never a paste into the prompt.

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

🚨 **`headroom_target` is NOT the product's target — that demand is PRODUCT-SIDE.** The harness
itself emits *"The memory index at … is 21.1KB, approaching the 24.4KB read limit. Compact it to
under 17.1KB now"*. It appears in **no `settings.json` and no repo hook**, and it is a flat
**0.7 × the limit**, constant regardless of index size (verified unchanged at 21.1 KB and at
20.9 KB, 2026-08-06) — i.e. **~17,500 units**, see THE UNIT. At least six backlog items have copied
it in verbatim as *"target <17.1KB"*. **The contract is the 25,000-unit / 200-line limit with
~2.5 KB of headroom as done**; trace a demand to a config file before obeying it (same provenance
shape as the product-side "don't spawn subagents unless asked" line).
*(Provenance note: this used to add "`grep -a` finds the template inside the Claude Code binary".
Re-attempted 2026-08-21 against the shipped `claude-code-darwin-arm64/claude` — the JS payload is
**compressed**: a positive control for a string that must be present (`claude-sonnet`) also returned
0 hits, so that read is a NON-VERDICT on this bundle, not a refutation. The 0.7 ratio above is an
observed-behaviour measurement and does not depend on it.)*

🚨 **What used to follow — *"and no honest pass can reach it"* — was a UNIVERSAL resting on a
POPULATION-DEPENDENT premise, and that is the defect, not the number.** The provenance argument
above is population-independent and load-bearing on its own. The arithmetic one is a function of
`N` and of how the index is SHAPED, so at the populations where it fails a reader who checks
discards the whole paragraph — **including the provenance argument that was doing the work.** Never
bundle them again. The real unreachability test is one line, run it against the LIVE index:

```
per_hook_budget = (17500 − Σprefix − N) / N      # refuse the target only if this nears the ~115 floor
```

Measured 2026-08-21 on two live indexes with `mim_measure_file`, **one instrument for every figure**:

| | N | index | Σprefix | budget @17,500 | observed | verdict |
|---|---|---|---|---|---|---|
| **claude-infrastructure** | 143 | 24,287 u / 146 ln | 10,114 u | **50 u/hook** | 98 u/hook | **unreachable — below the ~115 floor.** The old verdict holds *here* |
| **reso-management-app** | 31 | 22,263 u / 32 ln | *n/a* | **564 u/entry** | 718 u/entry | **reachable** — a 21% trim, nowhere near "below one sentence" |

Two things that table is teaching beyond the arithmetic. First, **`Σprefix` is the whole story**: at
N=143 the immutable `- [Title](file.md) — ` prefixes alone are 10,114 units — 58% of the product's
entire target — which is why the budget collapses to 50 while the *average hook* is a healthy 98.
Second, **reso has no prefix/hook split at all** — its hook text sits INSIDE the link title, so the
formula's `Σprefix` term does not apply and a pass that assumed it would have budgeted against a
term that is not there. **Check the index's SHAPE before running the formula on it**; a sibling
project is not a sibling structure.

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
  **Measure the index directly and budget against the real 25,000-unit / 200-line limit; do not let
  that reminder authorize a lossy pass** — same precedence as the product-side "don't spawn unless
  asked" line the global CLAUDE.md overrides.
  🚨 **Two claims that used to close this bullet are RETRACTED (2026-08-21) — and note they argued
  in OPPOSITE directions while both being cited as support.**
  - *"~67 B/entry, unreachable by construction"* — **conditional on N and on index shape**, not by
    construction. The live table under § BUDGET THE PREFIXES FIRST has both populations; it is
    unreachable at N=143 and reachable at N=31.
  - *"Its size figure is also not a live read"* — **refuted by its own numbers.** It reported
    `20.9KB` on a file `wc -c` put at 22,232 B. `20.9 × 1024 = 21,402` units against 22,232 bytes is
    a ratio of **1.0388**, which sits squarely inside the byte→UTF-16 overhead measured live on two
    real indexes the same day (**1.0161 and 1.0537**). That is what a *correct* live read looks like
    once you stop comparing it to `wc -c`. The second half — *"repeated `20.9KB` unchanged across
    two size-changing edits"* — is a different and still-open observation, but it needs a size it
    never states: a 1-dp label over 1024 has a granularity of **~51 units**, so only edits that move
    the index further than that are evidence of staleness at all.
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
- 🚨 **SCOPE CORRECTION 2026-08-10 (pass 2, backlog `7e2df754d0b8`): the rotor holds the BREACH
  line, it does not hold the BAND — and the band is where this command still earns its keep.**
  The bullet above reads as though the hand pass is retired. Measured on the live index with a
  path-conforming fixture, the rotor has three distinct behaviours and only one of them moves a
  byte:

  | index size | verdict | moved |
  |---|---|---|
  | 22,906 B (under the trigger) | `noop size=22906 rotate_at=23485` | 0 |
  | 23,939 B (**the pressure band**, ≥ LIMIT−1500 and < LIMIT) | `exhausted … min_keep=40` | **0** |
  | 25,219 B (breach, ≥ LIMIT) | `rotated moved=10 stage2=10` | 10 → 23,344 B |

  **Its trigger is LIMIT−1500 but its only effective stage arms at LIMIT**, so across that 1,500 B
  band it returns `exhausted` and moves nothing — every entry is held by a protection
  (`tail=15 type=78 hub=8 young=26 marker=1 min_keep=40`). That is the design working, not a bug:
  the `type:` stamp is only allowed to yield at breach pressure. But `hooks/memory-nudge.sh` also
  suppresses the note for an `exhausted` verdict below the limit (correctly — it is the designed
  steady state), so **the band is crossed silently and nothing but this command can clear it.**
  Note also where the breach case LANDS: 23,344 B, i.e. back just under its own trigger and
  2,359 B short of its `LIMIT−4000` target, because it exhausts its eligible set first. So even
  after a breach rotation the index re-enters the band within a few appends.
  **Read the division this way:** the rotor is the floor that stops the loader silently dropping
  entries; the ~2.5 KB headroom that buys actual runway is still produced by a quality pass. Do not
  close a band-state index as "the machine has it" — measure, and if the verdict is `exhausted`,
  the lever is yours.
- **This pass (2026-08-10 pass 2), for the record.** Intake 23,828 B / 112 entries, headroom 1,157 B
  against the 2,500 B done target ⇒ a pass was authorized. Three-state check re-derived from the live
  file: hook avg **127 B** vs a derived budget of **115 B**, slack **+16** ⇒ **LENGTH binds**, with
  1,635 B of excess. ⚠️ Note the derived budget landed on *exactly* 115 here — the constant was
  accidentally right at this N, so this index's own excess figure did not mislead, and the constant's
  defect had to be demonstrated at N=95 and N=100 instead. **A constant agreeing with the derivation
  once is not evidence it is a constant**; re-derive anyway, which is the whole rule.
  🚨 And derive it correctly: `PFX` (a `sed | wc -c` over the entries) already carries one newline
  per entry, and so does `ENTRY_B`, so `TOTAL = header + PFX + Σhook` exactly. Subtracting `N` again
  "for the newlines" double-counts them and understates the allowance by 1 B/entry — the identity is
  worth asserting before you trust either side of the comparison.
  Lever: 76 hand-authored line rewrites + 12 retitles, **24,080 → 22,468 B, headroom 2,517 B**
  (a sibling appended one entry mid-pass, folded in), 0 entries lost, 0 hooks grew, 1 genuine orphan re-indexed
  (`prescribed-repro-weaker-than-the-harness.md`). Index-only-fact audit: **11 first-pass flags, 0
  real** — every one a format variant (`20/21` vs `20-of-21`, `80/156` vs separate `80` and `156`)
  or a paraphrase (`MISSING` vs "a word NOT in it"), which is the fourth consecutive pass where the
  second detector pass carried the whole verdict. Also swept: 4 broken `[[wiki-links]]` whose
  targets matched an existing file name and were therefore defects, not forward-references
  (`actuator-is-the-arbiter`, `landing-remedy-with-surviving-symptom`, `landing-safety-tooling`,
  `control-decays-vs-its-subject`); 9 remaining broken targets match no file and are legitimate
  forward-references. A sibling appended one entry mid-pass and was folded in, not clobbered — the
  compare-and-swap on the file's md5 is what proves it (fifth consecutive pass to observe a
  concurrent write).
- **This pass (2026-08-11), for the record — and it started at FITS = 0.** Backlog
  `cf6eb3e47b12`, filed quoting *22.5 KB*. Re-measured at intake: **24,879 B / 123 entries,
  headroom 106 B** — 2.4 KB above the size the item named and **one append from the loader dropping
  its newest lines**, the closest to the cliff any recorded pass has begun. The band behaviour
  documented in the SCOPE CORRECTION above reproduced exactly: `cc-memory-rotate --dry-run` returned
  `verdict=exhausted size=24879` and moved **0** (`tail=15 type=76 hub=9 young=22 marker=1
  min_keep=40`), so the machine was holding nothing back and the lever was in fact ours. Three-state
  check re-derived: budget `(22,485 − 610 fixed − 9,803 prefix)/123` = **98 B** vs hook avg
  **117.6 B**, with **112 of 123** lines over ⇒ **LENGTH binds**, 2,463 B of excess against 2,394 B
  needed — i.e. the only available lever cleared the target by 69 B on paper. Lever: 118 hand-authored
  rewrites + 74 retitles, **24,879 → 21,450 B, headroom 106 → 3,535 B** (1,035 B past the done
  target, so the index header comment was left untouched rather than ground for its last ~300 B).
  123/123 entries kept, 0 hooks grew, 0 severed rules, 0 dangling. SAFE-AUTO a legitimate no-op on
  all five sweeps, positive control passing. The audit was run **6-way in parallel**, one shard of
  ~21 entries per agent, each writing only to its own topic files while the lead held `MEMORY.md`
  exclusively — no shard shares a topic file, so there is no owner conflict.
  ⚠️ **First pass in six to observe NO concurrent write** — the md5 CAS held end-to-end. Recorded as
  the measurement it is, not as a change in the mechanism: the four prior passes' rule stands and the
  CAS is why this one is checkable at all.
  ⚠️ **The `--condition` fix has actuated.** This item was minted `condition=memory-index-over-budget`
  with the size left in `--title`, exactly as the RE-INFLATION bullet prescribes — so the 21-duplicate
  re-keying defect is closed at the producer. The title still hands a reader *"compact to <17.1KB"*,
  which remains product-side and — **at THIS project's N, per the live table in § BUDGET THE PREFIXES
  FIRST** — unreachable; read it as the measurement it is and budget against the 25,000-unit /
  200-line limit.
- **This pass (2026-08-11 pass 2), for the record — the FIRST recorded HEADROOM-OK no-op close.**
  Backlog `152e9cacc8aa`, filed quoting *21.7 KB* and asking for *<17.1 KB*. Re-measured at intake:
  **21,450 B / 123 entries, headroom 3,535 B** — i.e. already **1,035 B PAST the 2,500 B done
  target**, because the pass recorded in the bullet directly above had landed it there 6 hours
  earlier. Three-state check re-derived from the live file: budget **104.5 B** vs hook avg
  **96.1 B**, slack **+16.7** entries, `runway_now` **20.7** ⇒ **NEITHER lever binds**, and even the
  discredited 115 B constant reported **0 B** of excess for once. `cc-memory-rotate --dry-run`
  agreed: `verdict=noop size=21450 rotate_at=23485`. **No cut was authorized, so none was made** —
  the outcome the HEADROOM-OK row has always prescribed and which no pass had yet had occasion to
  record. SAFE-AUTO a legitimate no-op on all five sweeps: 0 archivable after the durability
  criterion (5 marker hits, all live rules), **0 orphans**, 0 dangling, 2 demotion records
  discovered by content. The inverse `CORRECTED`/`SUPERSEDED`/`REFUTED` sweep below was also run and
  is clean: **6 topic files carry a correction marker, 0 index hooks assert a refuted mechanism** —
  including `reference-claude-accounts-tooling`, whose hook now states the corrected rule (*"only a
  new /login moves it"*), confirming that fix propagated. A sibling appended 2 entries mid-pass (**21,450 → 21,878 B, 123 → 125**);
  re-measured rather than clobbered, and the verdict is unchanged at headroom 3,107 B.
  ⚠️ **The item was a DUPLICATE of `cf6eb3e47b12` and the store already knew it.** Open item
  `073c620b571e` records `cc-backlog backfill` correctly proposing to join exactly these two ids to
  the `memory-index-over-budget` group — and finding no caller to run it. So the `--condition` fix
  closed re-keying at the producer while these two were minted, but nothing joins pre-existing
  orphans, and a worker was spent on an index that was already 1 KB under its done target.
- **This pass (2026-08-22, reso-management-app), for the record — the first on the OTHER index
  shape, and the one that found the `[^]]*` harvest bug above.** Intake **24,786 chars / 35 lines,
  headroom 214** — the closest to the cliff any recorded pass has begun, beating 2026-08-11's 106 B
  only because the unit is different. **Read the shape before the formula:** reso has no
  prefix/hook split at all (the hook lives INSIDE the link title), so `Σprefix` is not a term here
  and the § BUDGET table's own reso row is the one to use — 34 entries averaging **728** chars
  against a derived **661** budget ⇒ **LENGTH binds**, 3,649 chars of excess against 2,286 needed,
  and the char cap binds while the line cap sits **165 lines** clear. `cc-memory-rotate --dry-run`
  returned `verdict=exhausted` moving **0** — but for a NEW reason worth recording: at **N=34** the
  index is already **under `min_keep=40`**, so on this project the rotor can *never* rotate at any
  size and the § SCOPE CORRECTION band-check has no lower arm to fall back on. The lever is ours by
  construction here, not merely in the band. Lever: **16 hand-authored rewrites**, no retitles
  (reso's titles ARE its hooks — the near-lossless retitle lever does not exist on this shape),
  **24,786 → 21,897 chars, headroom 214 → 3,103** (603 past the done target). 34/34 entries kept,
  0 hooks grew, 0 lines removed, 0 dangling; rotor re-read `verdict=noop`, i.e. the pass cleared the
  whole pressure band and not just the breach line. SAFE-AUTO a legitimate no-op on all five sweeps
  (0 archivable after the durability criterion — both marker hits were live rules; **0** genuine
  orphans, 15 E3-ok, 655 archived links). The inverse `CORRECTED`/`SUPERSEDED`/`REFUTED` sweep found
  2 marked topic files and **0** index hooks asserting a refuted mechanism — both corrections had
  already propagated into the hook. Index-only-fact audit: **11 flags, 0 real** — `TELL`, `7.7x`
  (file says `~7.7×`), `SUCCESS` (file says *"the write really happened"*), `turso db show X` (file
  says `<db>`) — the **seventh** consecutive pass in which the second detector pass carried the
  entire verdict, and the first in which the first detector's flags were *all* emphasis variants of
  the index's own ALL-CAPS vocabulary rather than format variants of a fact.
  ⚠️ **A hazard specific to running this on reso: the interactive `grep` is ugrep (a shell function),
  and a `grep -o -E` over these 700-char lines HUNG past a 120 s timeout.** Do the audits in
  `python3`, not in a shell pipeline — which this file's own
  `interactive-grep-is-ugrep-not-usr-bin-grep` note predicts but had not yet cost a turn.

🚨 **A "denominator disagreement" between a KB figure and `wc -c` is arithmetically REFUTABLE — and
when it refutes, the gap is STALENESS, which is a different bug with a different fix.** This item was
filed on the premise that *"the hook said 21.7KB while wc -c read 23.2KB"* and instructed the worker
to establish *which one the loader applies* before sizing a cut. Three measurements settle it, and
the first two cost nothing:

- ~~**The ratio disproves units.**~~ 🚨 **RETRACTED 2026-08-21 — this refuted ONE candidate
  conversion and concluded that NO conversion applied.** As written: *"KiB→kB is a factor of 1.024.
  The observed gap is 23.2/21.7 = 1.0691 — 2.9× too large for any base-1000/1024 difference to
  produce."* The first two sentences are arithmetically fine and the third does not follow. The
  conversion that actually applies here is **bytes → UTF-16 units, plus the loader's frontmatter and
  block-comment stripping** — the thing this section's own third bullet goes on to discover — and it
  measures **1.0161 and 1.0537** on two live indexes (2026-08-21), composed of ~2.3% multibyte and
  ~3.0% stripping on the larger. A **1.0691** gap is at the top of that band, not 2.9× outside it,
  so the residual this bullet handed to STALENESS was never established. **The transferable rule is
  the opposite of the one it wrote:** disproving the base-1000/1024 factor does not disprove *a unit
  difference* — it disproves *that* unit difference. Name every conversion between the two
  instruments before assigning the remainder to a bug (see also THE UNIT, and the `17,100` constant
  that survived for months precisely because one KB convention was tested and the other was not).
- **The named hook renders no KB figure at all.** `hooks/memory-nudge.sh` emits raw bytes in both
  branches (`"${TOTAL}/${LIMIT} B across $N entries"`), and `grep -iE 'kb|1024|1000'` over it returns
  only comment prose. So *"the memory-nudge hook reports 21.7KB"* misattributes the **product-side**
  reminder to our hook. ⚠️ **The clause that used to follow — that the template "is not a live read"
  and so "the stale figure is the smaller one" — is retracted with the bullet above**; the smaller
  figure is smaller because it is measured in loader units, which is the CORRECT unit, not because
  it is stale. The misattribution finding is unaffected and stands on its own.
- 🚨 **The answer to "which one does the loader apply" is NEITHER — and "it applies BYTES" was also
  wrong.** This bullet asserted `24985` bytes, pinned it in two suites and asserted it present in all
  three code paths; that made the three measurers agree with each other and with nothing else. The
  enforced quantity is **25,000 UTF-16 code units of the stripped, trimmed index, plus 200 lines**
  (see THE UNIT at the top), and it now has ONE spelling —
  `hooks/lib/memory-index-measure.sh` — which the gate, the nudge and the rotor all read. `24.4 ×
  1024 = 24,985.6` reconciled with the product's KB label by coincidence of magnitude, not because
  the quantity was a byte count. **Size a cut in loader chars, and check the line count, or do not
  size it.** Two prior instances of this same failure to re-derive: `eec945d6e2ec` wrote *"re-derive
  the true limit before cutting"* and sat five days because nobody ran the division; this bullet
  then ran the division and stopped one step short of asking what the number counted.

🚨 **A CORRECTION that landed in the topic file and never reached the index is invisible to BOTH
detectors — and it leaves a refuted rule on the auto-loaded surface.** The audit above is
directional: it asks *"does the hook state a fact the topic file lacks?"* This pass found the
inverse, and neither detector can see it. `reference-claude-accounts-tooling`'s index hook read
*"`refreshTokenExpiresAt` anchors to the last /login; no refresh extends it"* while its topic file's
**MECHANISM CORRECTED 2026-08-04** section says the binary recomputes the field on *every* refresh —
a refresh rewrites the cliff and can never advance it, so **only a new grant moves it**, and a grant
can be dead long before its cliff (next2 answered `400` for 95 minutes at `login_expires_h` 674.6).
Every hard token in the hook is *present* in the file — the file quotes the refuted mechanism in
order to correct it — so token-matching passes, and clause coverage passes for the same reason. The
line survived **7 days** as a wrong rule every session loaded. **Sweep it directly: when a topic
file carries a `CORRECTED` / `SUPERSEDED` / `REFUTED` marker, diff the index hook against the text
BELOW that marker, not against the file as a whole.** Cheap, and it is the only check that runs in
this direction. Same family as the "index can be WRONG, not merely bloated" finding, but sharper:
there the index was stale on its own, here the correction existed and simply never propagated
([[work-item-remedy-can-become-forbidden]] is the symptom/remedy version of the same rot).

⚠️ **A hard-token detector that normalizes by stripping punctuation cannot check a PURE-punctuation
token** — it normalizes to the empty string, matches nothing, and auto-flags. **5 of this pass's 8
finished-file flags were that class** (`` `*)` ``, `` `$(` ``, `` `$!` ``, `` `;` ``, `` `&&` ``), all
five literally present in their topic files, and they cluster precisely on shell-operator rules —
the hooks whose one backticked token IS the whole rule. Check any token with no alphanumerics with a
literal `grep -F` *before* normalizing. Same shape as the documented multi-word-span over-flag:
**the detector's own preprocessing decides which facts it is structurally unable to verify.** The
remaining 3 flags were inflection (`ADVISE`/advisory, `ACCUMULATES`/accumulator, `SKIPPED`/skips) —
so **0 real index-only facts**, and the fifth consecutive pass in which the second detector pass
carried the entire verdict.

## PROTECTED
- Any entry/line tagged `(PINNED)` is skipped entirely (explicit opt-out; mirrors hermes pin-to-protect).
- Never delete historical decisions, "Why:" rationale, learnings, or known issues (global File Update Rule).
- Archiving *intentionally* leaves a topic file unindexed. Keep that honest by putting a pointer —
  `<!-- archived entries: archive/MEMORY_ARCHIVE_<year>-H<half>.md -->` — in the index header, so
  archived topics stay discoverable from the auto-loaded surface. Cheaper than a bullet per entry.

## Output
A report: SAFE-AUTO actions (taken or previewed), then the PROPOSE-ONLY queue as an
approve/reject list. End with before/after `MEMORY.md` figures from
**`mim_measure_file` — never `wc -c`** — against **BOTH** caps: **25,000 UTF-16 units** and
**200 lines**. 🚨 **Name which cap is binding, and report both deltas as verdicts.** *(Corrected
2026-08-21. This used to read "before/after **byte** count against the ~24,985 B limit — bytes are
what truncate … report the line count too, but as context, never as the verdict", which contradicted
THE UNIT at the top of this file on both halves: bytes are not what truncate, and the line cap binds
FIRST on an index of one-line entries. A pass that cleared the char cap and reported the line count
"as context" would have declared victory over a live line breach — and only removing a LINE clears
one, so the char-side work would not even have been the right job.)*
