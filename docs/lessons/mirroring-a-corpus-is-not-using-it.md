# Mirroring a corpus is not using it

**The rule.** Fetching, measuring, documenting and wrapping a content endpoint in a
skill are all work *about* the endpoint. None of them is evidence the content is
usable. The only proof is an artifact built WITH it. Until one exists, you have
built scaffolding and may not claim the capability.

## The incident (2026-09-19/20, ui.sh)

Asked to mirror the ui.sh corpus before its MCP server retired, one session:

- crawled 99 files by BFS (the server's own `resources/list` advertises 10)
- captured 77 binary assets and `ui-picker.js`
- verified link-closure at 88/88 and sha256-manifested every file
- measured the corpus (0 hex values, 2 aesthetic adjectives across 347 bullets)
- wrote `VISUAL-KIT.md` mapping where the visual leverage sits
- landed a `visual-direction` skill encoding a pipeline for using it

**and never designed a single thing with it.** The operator asked the same question
four times — *"what is the best practice way to apply to get actual studio quality
output"* — and got four analytical answers. On the fourth they named it:

> "everytime we've built around the actual mcp endpoint, we've never maximally
> utilized the mcp endpoint and it's endpoint content, so we've built so much work
> around the mcp and basically 'beat around the bush' saying we've used it and have
> never used the mcp in that call/skill/session."

Correct. Every artifact was *about* the corpus; none was *made with* it.

## What using it actually produced, and why the distinction is not pedantic

Running the guidelines against the one UI that session owned — the contact sheet
`cc-mail-images` emits — found **six real defects** in shipped code (body and caption
type below the text-base floor, no `InterVariable`, no `text-balance`, no per-element
`max-w-[*ch]`, no constrained container) plus a seventh from `frontend-design`'s
cliché list: the subtitle was `N image(s) · date · N failed`, and middle-dot-joined
meta strings are named template chrome.

Then **rendering it and looking** found two more that no rule could state: varying
aspect ratios put every caption on a different baseline (347/353/367/347px) so the
grid read as ragged, and the one signal colour was spent on a constant — every image
shared a source, so four coloured labels carried zero information while pulling the
eye.

Nine defects, none of which the mirroring, measuring, documenting or skill-writing
surfaced. The measurement phase had even produced a *correct* thesis — that the
corpus is a finishing layer with nothing to say about what a page should look like —
and only using it turned that from an assertion into a demonstrated fact.

## How to tell which side of the line you are on

Ask: **what did I make with it?** Not what did I learn about it, catalogue from it,
or build to route to it.

- A manifest, a map, a measurement, a skill that describes the workflow — scaffolding.
- One artifact produced by following the content, rendered and critiqued — use.

A skill that encodes a pipeline is especially deceptive here, because it *feels* like
completion: it is executable, it is durable, and it will make future sessions do the
right thing. It still contains zero evidence the pipeline works.

## Companions

- [[a-plan-is-not-a-queue]] — an artifact describing work is not the work.
- [[conclusion-must-reach-the-enforcing-store]] — docs advise; only code enforces.
- [[spec-named-mechanism-may-be-prose-only]] — a cited mechanism can exist only in prose.
