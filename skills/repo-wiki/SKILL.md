---
name: repo-wiki
description: >-
  Generate a source-grounded README or multi-page technical wiki for a
  repository — the Grok-Wiki generator distilled into a prompt, with no app, no
  CLI, and no sidecar. Load when asked to "write a README for this repo",
  "document this codebase", "generate a wiki", "explain this repository", or to
  produce onboarding/architecture docs for a repo you did not write. Runs as two
  passes: a STRUCTURE pass that explores the repo and commits to a page plan
  before writing any prose, then a PAGE pass that writes each page against its
  own file list. Carries the decomposition rules (the part that decides whether
  the output is useful), the beyond-README requirement, the citation contract,
  and the diagram harness that stops weak Mermaid. One page = a README; N pages
  = a wiki. NOT for the grok-wiki CLI itself (that is grok-wiki-cli /
  grok-wiki-custom) and NOT for a defect sweep (that is grok-wiki-audit).
---

# Repo wiki, from a prompt

Grok-Wiki's engine is prompts — `rlm-wiki.js` ships `src/prompts/{prelude,structure,page}.ts`
readable, and its local-CLI prelude reduces to *"use native tools, return markdown."* Claude Code
already **is** that harness, so everything below runs here directly. Three things get simpler than
the app's version, and they are the reason this is not a worse copy:

- **No `<ANSWER>` XML contract.** That exists so the app can parse an agent's stdout. Write the plan
  and the pages as files instead.
- **No repair loops.** Mermaid repair, empty-diff repair and format-tune exist to fix a one-shot
  generation you cannot inspect. Read your own output and fix it.
- **No page-level context reset.** The app re-prompts per page with only that page's file list;
  you keep the structure pass in context, so cross-page coherence is free.

What genuinely does not carry over is state, not intelligence: the `~/.rlm-wiki` store, per-page
concurrency, and the multi-repo namespace (`repoId:path`) — do that one by hand if you span repos.

## Pass 1 — structure. Commit to a plan before writing any prose.

**Do NOT settle on a structure from just the README.**

1. Read `README.md` and the manifest (`package.json` / `pyproject.toml` / `Cargo.toml` / `go.mod`).
2. List and search files to see the real layout.
3. Search for a *structural outline* before reading bodies: class/function/export definitions, route
   declarations, commands, plugin registrations, config keys.
4. Prefer clear entry points and load-bearing directories over mechanical repo metrics.
5. Read a few load-bearing files carefully, then expand only where imports, exports, or search
   results point.

**Stop exploring** when you can name the entry points, core abstractions, major module groups, and
build/deploy/runtime surfaces. Another read that would not change the page plan is a read you skip.

### How many pages

| ask | sections | pages | exploration |
|---|---|---|---|
| **a README** | 1 | **exactly 1** | 1–2 targeted steps — just enough to beat a README-only overview |
| fast wiki | 2–4 | 1–4 per section | 1–2 steps |
| regular | 3–5 | 2–6 per section | 2–4 steps |
| deep | 4–8 | 3–8 per section | 4–8 steps |

Auto mode picks the **smallest useful** number in range. Do not fill every slot unless the
repository genuinely needs that many distinct pages. A page count the user gave is a hard target.

### How to decompose — this is the important part

**Do NOT create one giant page per subsystem. SPLIT by concern:**

- a subsystem with several distinct files or responsibilities → one **section**, one **page per
  file / concern / responsibility**
- a multi-step pipeline → one page per stage
- a plugin / adapter / skill system → one section, one sub-page **per category or adapter**
- an API surface → endpoints grouped into logical pages ("Navigation API", "Input API"), never one
  page for the whole API

Concrete, because the abstract rule does not bite:

- Bad: `"Interaction Skills"` — one page containing everything.
- Good: section `"Interaction Skills"` → `"Input & Navigation"`, `"Frames, Shadow DOM & Multi-Tab"`,
  `"Dialogs, Downloads & Network"`.
- Bad: `"Architecture"` — one page for the whole system.
- Good: section `"Architecture & Core Components"` → `"Daemon & CDP Connection Layer"`,
  `"run.py & admin.py — Execution and Lifecycle"`, `"helpers.py — Automation API"`.

### Section patterns — pick what fits, force none

Getting Started & Installation · Core Concepts & Design Philosophy · Architecture & Core Components
(one page per subsystem) · Public API Reference (one page per module) · Data Flow & Pipeline (one
page per stage) · Features / Capabilities · Integration & Extensibility · Examples / Recipes Library
· Build, Deploy & Operations · Testing & Quality (only if the test story is non-trivial).

Ignore what does not fit — no "Deployment" for a library, no "Frontend" for a CLI.

### The plan itself

Emit a table before writing any page, and **attach each page's file list** — that list is what the
page pass is allowed to claim from:

| id | title | one-line description | files this page rests on | section |
|---|---|---|---|---|

## Pass 2 — pages. One page at a time, against its own file list.

Required shape, in order:

1. A collapsible source list first:
   ```html
   <details>
   <summary>Relevant source files</summary>
   The following files were used as context for generating this page:
   - [path/to/file1.ext](path/to/file1.ext)
   </details>
   ```
2. `# <page title>`
3. 1–2 paragraphs on what the page covers and why it matters.
4. Detailed `##` / `###` sections that break the topic down logically.
5. Diagrams only where they pass the harness below.
6. Tables for options, configs, states, APIs, comparisons.
7. Short code excerpts **with the file path**.
8. A closing paragraph; a final citation only if it carries a claim not already supported nearby.

### Beyond-README requirement

The README may orient the plan; it must not dominate the output. Actively surface source-backed
material **not already obvious from the README**: code paths, tests, config, examples, prompts,
adapters, generated assets, scripts, hidden constraints, implementation boundaries. **A page that
restates README claims is weak** — prefer non-README evidence unless the README is the only source
for a setup or positioning fact.

### Evidence bar

Explain *why* each subsystem exists, not just what files exist. Cite representative evidence inline
by path (`src/foo.ts:120`), name the tests a contributor should actually run, and omit any surface
the source does not support rather than documenting the shape you expected to find.

### Diagram harness — weak diagrams are worse than none

Before any Mermaid block, ask what spatial model it teaches that prose cannot: boundaries,
ownership, dependency direction, lifecycle, data shape.

- `flowchart`/`graph` with named subgraphs for architecture — real module names, never `Step 1`
- `classDiagram` for interface-to-implementation contracts, adapter/strategy/observer, domain models
- `sequenceDiagram` for request/response, streaming handshakes, cross-boundary event ordering
- `stateDiagram-v2` for lifecycle/status machines, retry/cancel/resume, job states
- `erDiagram` only when persistence relationships are the main idea
- a compact fenced `text` ASCII sketch for small mental models, before/after contrasts, ownership
  boxes, file-to-responsibility maps — where Mermaid would feel forced

**Reject** `A --> B --> C` linear flowcharts that restate a call order: upgrade them or drop them.
Do not invent a grand architecture for a single-file workflow.

## Verify

Re-read each page against its own file list and check three things: every path cited exists, every
claim traces to a file in that page's list, and no section is README restatement. Then fix what you
find — that is the repair loop, and you are better placed to run it than the app was.
