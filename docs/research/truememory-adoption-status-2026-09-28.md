# TrueMemory adoption — status verdict for cc-backlog 4efda83b9d14 (2026-09-28)

Written by a cloud-dispatched session (branch `claude/fire-20260928T145337Z-9223-1`), read-only
against trunk except for the two new research files named below.

## Verdict

**The frozen DoD is done. The grown scope is partly in flight in a sibling session, and the rest is
gated on the operator box or on a pre-registered stop.** This row should not be re-dispatched as
"advance the plan". What remains open belongs to named waves with their own owners and entry
conditions, listed below.

## What I ran

- `git rev-parse --is-shallow-repository` → true, then `git fetch --unshallow`; `git fetch origin`;
  `git rev-list --count HEAD..origin/main` → **0** (the checkout IS trunk, tip `ea07499f`).
- `git rev-parse origin/main:bin/cc-dispatch` → `dc9130372d6332940388c2a17da7c65c1af3c3bd`,
  **equal** to the blob that composed the brief, so the dispatcher that fired this row is trunk's.
- Read `docs/plans/TRUEMEMORY_ADOPTION.md` on trunk, then `git log` for the plan and for the Wave D
  subjects.

## Section-by-section, against the plan-phase-scan snapshot in the brief

| scan section | trunk says | disposition |
|---|---|---|
| Phase 0 — orchestration | a container of tables with no work of its own | no action; it reads PENDING only because its heading is unmarked |
| Wave A | `— DONE 2026-09-28` (`abaf1e99`) | done |
| Wave B | `— DONE 2026-09-28` (`15648459`, `f1206329`) | done. The scan's "BLOCKED on Wave A" text is an older heading, so the desk-side snapshot predates these commits |
| Wave C | `— DONE 2026-09-28` (`7062884c`) | done. **Waves A-C are the frozen DoD (#1-#14), so the frozen DoD is met** |
| After this program | marked *Superseded 2026-09-27 by Waves D and E* | kept as a record, no work |
| Wave D (#15-#22) | heading still "ready", but trunk carries #20 `6f4fd40b`, #16 `a775df44`, #17 `51dc2564`, #18 `d16f659e` `a4256318` `cbccd82d`, #19 `d69f06db`, #15 `0d81fb6f` `ea07499f`, all committed 2026-09-28 13:05-13:58Z | **in flight in a sibling Wave D session**. All six buildable items are on trunk. The plan's DONE mark and learnings are that session's to write, so I left the plan untouched to avoid a rebase collision. #21/#22 are gated on Wave E #24's verdict |
| Wave E | not started | see below |
| Open questions | the native-fork hook question | only testable when a native flag flips (#8 sentinel reads `nondefault=0`). Not actionable |
| Cross-cutting X6-X8 | rules, not work | no action |

## Wave E, per experiment

| # | state | why it is not done here |
|---|---|---|
| 4b | entry condition met | needs the private gold (`~/.claude/autonomy/memory-eval/`) and the per-project store map. Operator box only |
| 23 | **stopped** by #35's pre-registered no-gain branch (plan § Wave B, research §5.17) | no work until a delivery-research wave builds tasks the stock arm fails |
| 24, 25 | entry condition met (#14 landed) | need live transcripts and hand-labelling. Operator box |
| 26 | **stopped** by the same no-gain branch; shadow logging keeps running | its verdict needs ≥20 hand-labelled shadow fires from the live log |
| 27 | conditional | adopt only with a non-prose delivery mechanism (X7). No candidate exists yet |
| 36 | step 1 **done in this session**: `docs/research/truememory-2026-09-27/adherence-inventory-36.md` | step 2 needs the #35 harness on an account. Result of step 1: 1 of 4 fixtures (#29) is covered, conditional on migration 0027's registration. #10 and #79 have cheap literal candidates. #11 does not |

## Why no code was written

The six buildable Wave D items were landed by a sibling session under an hour before this dispatch
(13:05-13:58Z, and this row fired at 14:53Z). Rebuilding them would re-derive work already on
trunk. Every Wave E item needs private data, a live account, or hand-labelling, or it is stopped by
a pre-registered branch. The one bounded, repo-only unit was #36 step 1, and it is delivered.

## For the desk

- Close 4efda83b9d14 as "frozen DoD met (Waves A-C DONE on trunk). Wave D landed by its own
  session; Wave E is operator-box work or stopped by pre-registration", citing this file.
- If the plan should stay tracked for Wave E, re-mint rows per experiment (4b, 24, 26 verdict,
  36 step 2), each with its operator-box precondition. The single "advance TrueMemory adoption"
  heading row will keep re-dispatching into work that is either done or not doable off-box.
