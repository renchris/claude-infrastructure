# Materiality rubric — fixed at intake, never edited during a program

Source: REPORT.md §3.11 (`docs/research/upfront-research-exhaustion-2026-09-30/REPORT.md`). Raters, the
verifier and the lead all apply this text and nothing else. A program records the rubric's hash on its
certificate; editing this file mid-program is a change to the method, not to the program (§9 decision 8).

A finding is **material** only if it carries a **location** (file:line or a verbatim quote), **names a frame
row**, and does at least one of these:

| Clause | The finding … |
|---|---|
| a | flips a decision's chosen option, **and** a probe or primary read reproduces the consequence. A change in conviction alone never counts |
| b | changes an acceptance row's verdict or threshold, or shows by running it that the row cannot fail |
| c | changes sequencing or an interface contract, or moves a **measured** cost or timeline figure (one with a probe id) outside its recorded interval. A new estimate counts only if it falls outside the old interval |
| d | adds a member to a census, as of that census's date, that a decision or acceptance row must cover and that changes the row |
| e | moves a load-bearing premise outside its measured tolerance |
| f | is a safety, security, data-integrity or irreversibility hazard. Always material: stop and surface |
| g | shows the frame lacks a decision, acceptance row or component that a signed frame row depends on. Always material; it goes to the frame-delta cycle (§5.4), never fixed in the running rounds |

**Levels** (the `materiality.level` a rater writes into `holes.jsonl`):

- `MATERIAL` — at least 2 raters say material **and** the consequence is reproduced.
- `MATERIAL-DISPUTED` — 2 or more raters say material but one more probe cannot reproduce the consequence:
  named on the certificate, does not reset the quiet count, applied at build.
- `REFINEMENT` — real, but meets no clause: filed to the apply-at-build list, never integrated during
  certification.
- `COSMETIC` — logged.
- `GENERIC` — no location or no row: rejected.

**Seeds go through the same raters.** A seed counts as caught only if it is rated `MATERIAL`.
**An item rated below material that later proves material is an escape, never a relabel** (§3.8).
