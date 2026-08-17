---
name: corpus-to-skill
description: Turn a canonical text (a methodology book, style guide, standard, or spec — typically an OCR'd PDF) into a full-fidelity executable skill whose sessions carry the source's actual rules, limits, and tests. Use when asked to "distill this book/guide/standard into a skill", "make an executable skill from this corpus", or when a compressed/name-drop version of a methodology exists and the user wants the complete method enforced. Proven end-to-end on The Minto Pyramid Principle → pyramid-principle-full (2026-07-09/10).
---

# corpus-to-skill — distill a canonical text into an executable skill

The product is a skill whose instructions are grounded in the *complete* source — not recalled approximations — with the fidelity claim made checkable. Eight phases, each committed before the next (git = the handoff insurance).

## Steps

1. **Prove corpus integrity before reading.** For a per-page OCR layout (`pages/page-N/markdown.md` + images, consolidated `markdown.md`): verify consolidated ≡ concatenation of pages (python, stripped compare); build the image→page map and check reference counts; list near-empty pages. Nothing else is trustworthy until this passes.
2. **Sweep for lacunae deterministically.** Grep standalone printed page numbers; flag gaps AND verify each candidate by opening the surrounding page files — full-page-exhibit pages produce false "missing page" positives; genuinely missing pages show mid-sentence jumps. Also detect out-of-order scans (content relocated to the file tail). Record the verified lacuna inventory; plan to read relocated pages in logical position.
3. **Read exhaustively in LEAD context.** The point is the knowledge in *your* context, so do not delegate the reading to subagents (their reading never lands in yours). Read the consolidated markdown in sequential chunks (~500–700 lines), interleaving every referenced image at its reference point via parallel Read calls. Track with tasks per book part.
4. **Persist a reading log, then commit.** Structural map (book pages ↔ scan pages ↔ md lines), exhibit inventory, lacuna inventory, and a master process inventory (the raw material for the skill). This is the handoff artifact if context runs out.
5. **Distill into an orchestrator + session files.** `SKILL.md` = doctrine, hard-stop protocol, mode routing, session index. One reference file per major process/chapter cluster: purpose → procedure → the source's tables/limits/tests (with page citations) → failure modes → exit checklist. Honor the source's own sequencing claims (e.g., Minto's structure-to-one-level-then-write). Mark lacuna-bridged content explicitly; never invent missing pages.
6. **Verify adversarially with a Workflow, then integrate every finding.** N parallel verifiers (one per book segment + one hostile reviewer for the orchestration itself), each re-reading its segment's page files IN FULL against the skill file under test; structured findings {severity, type: missing|distortion|citation, book_ref, skill_ref, fix}; instruct out-of-segment claims be skipped, and that "faithful/empty findings" is a valid answer. Fix everything; record the verification in the reading log; commit.
7. **Dogfood the deliverable.** Produce the repo README (or equivalent) BY RUNNING the new skill on it, worklog committed beside it as the audit trail. Add a second, non-self-referential worked example exercising the sessions the README run skipped. The worklogs double as future evolution fixtures.
8. **Publish minus the corpus.** If sharing (even privately): assemble a staging dir with FRESH git history containing only derived work (skill, docs, README, examples); the copyrighted corpus stays in the local archive only — most such texts forbid electronic transmission. State the exclusion + lacuna in the README's provenance section. Stage the skill via `~/.claude/skills-pending/` → `/skill-promote` (never write `~/.claude/skills/` directly).

## Do NOT

- **Do NOT let subagents "read the book for you"** when the goal is full-fidelity distillation — summaries reintroduce exactly the recall problem the pipeline exists to kill.
- **Do NOT trust page-number greps alone for lacunae** — verify each gap in the page files (full-page exhibits = false positives; the Minto run had 2 false vs 1 real).
- **Do NOT push the source text to any remote**, private or not, when its notice forbids reproduction/transmission; push only derived work on fresh history (the original repo's history carries the corpus).
- **Do NOT write the skill from headings/TOC knowledge** — the verifiers exist because even a full read compresses lossily; 36 findings survived an exhaustive read on the reference run.
- **Do NOT skip the dogfood** — an unexecuted skill is a document, not a skill; the first run always surfaces protocol ambiguities.
- **Do NOT capture source-specific numbers as pipeline rules** (chunk sizes, verifier counts scale with corpus size; the invariants are the phase gates, not the constants).

## Reference run

`renchris/pyramid-principle-full` (private) + local archive `~/Development/mistral-4-fable-ocr`: 279 scan pages / 149 exhibits read; 1 real lacuna vs 2 false positives; 10 verifiers → 0 critical / 5 major / 31 minor, all integrated; README + Meridian memo dogfoods; corpus excluded from publication.
