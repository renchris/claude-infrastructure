# Axis G — what makes a `/docs` folder maximally navigable for a grep-first agent

Scope: the **consumer side** of the lead's L1→L5 hypothesis — L3's mirror layout, L4's curated layer and
its page↔source map, L5's git-as-freshness-query. Acquisition/diff mechanics (L1/L2) are other axes.

**Headline.** The hypothesis survives on every axis I could test, with three corrections and one
unprecedented component. Corrections: (1) the binding page-size constraint is **tokens, not the
2000-line Read default**, and this repo's own docs already breach it — one research file is 146,511
chars / ~37K tokens, ~9% of a 400K effective window in a single Read; (2) **`Glob` caps at 100 files
and sorts by mtime, and git does not preserve mtime** (measured), so neither Glob nor filesystem
timestamps can carry freshness in a git-tracked docs tree — freshness must be *greppable text*;
(3) **there is no golden example for L4's page↔source dependency map.** Cursor re-embeds changed
chunks 1:1 with files; DeepWiki regenerates the whole wiki. Nobody ships many-source→one-page
incremental re-synthesis. That is the part to prototype first and the part most likely to be wrong.

---

## 1. The retrieval model this folder is being designed for (empirical)

| Claim | Evidence |
|---|---|
| Claude Code has **no semantic index**. Retrieval is Glob + Grep + Read, on demand. | "Claude chooses which tools to use based on your prompt"; the tool table lists **Search: Find files by pattern, search content with regex, explore codebases** — no index/embedding category. <https://code.claude.com/docs/en/how-claude-code-works> |
| Anthropic's own position: identifiers + runtime loading, not pre-inference embedding. | "Rather than pre-processing all relevant data up front, agents built with the 'just in time' approach maintain lightweight identifiers (file paths, stored queries, web links, etc.) and use these references to dynamically load data into context at runtime using tools." <https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents> |
| **Folder and file NAMES are load-bearing retrieval signal** — this is the single most important citation for this axis. | "To an agent operating in a file system, the presence of a file named `test_utils.py` in a `tests` folder implies a different purpose than a file with the same name located in `src/core_logic/`. Folder hierarchies, naming conventions, and timestamps all provide important signals that help both humans and agents understand how and when to utilize information." (same URL) |
| Progressive disclosure is the intended access pattern. | "agents to incrementally discover relevant context through exploration… file sizes suggest complexity; naming conventions hint at purpose; timestamps can be a proxy for relevance." (same URL) |
| Hybrid is permitted, not endorsed by default. | "In certain settings, the most effective agents might employ a hybrid strategy, retrieving some data up front for speed, and pursuing further autonomous exploration at its discretion." (same URL) |
| Anthropic removed a working RAG pipeline from Claude Code in favour of grep. | **Second-hand.** Boris Cherny quoted as saying the agentic approach "outperformed everything. By a lot." <https://vadim.blog/claude-code-no-indexing/>, <https://harrisonsec.com/blog/agent-retrieval-cost-curve-claude-code-grep-vs-rag/>. I could not find a first-party Anthropic statement. Treat as corroborating, not load-bearing. |

**Design consequence (theoretical, but forced by the above):** every freshness, provenance and
deletion signal must be **text inside a file, or the output of a shell command the agent can run.**
Nothing in the harness reads a manifest, a frontmatter field, or a sidecar. A design that relies on
the harness interpreting metadata is inert by construction.

---

## 2. Measured limits that set the layout (empirical, this machine / vendor docs)

| Limit | Value | Source |
|---|---|---|
| `Glob` result cap | "Results are sorted by modification time and **capped at 100 files.**" | <https://code.claude.com/docs/en/tools-reference> |
| `Glob` ignores `.gitignore` by default | `CLAUDE_CODE_GLOB_NO_IGNORE=false` to change | same |
| `Read` paging | "When a whole-file read exceeds the token limit, Read returns the first page with a `PARTIAL view` notice that tells Claude how much of the file it received and how to read more with `offset` and `limit`." | same |
| `Read` with explicit range can hard-error | "A read that passes an explicit `offset` or `limit` and still exceeds the token limit returns an error." | same |
| `Read` line default | "Reads up to 2000 lines by default" | the harness's own Read tool description, this session |
| ⚠️ the "~30,000 characters inline" figure | applies to **Bash output read-back**, not `Read`. Do not cite it as a page-size budget. | same page, Bash-tool section |
| Anthropic's own resident-context budget unit | "**target under 200 lines per CLAUDE.md file.** Longer files consume more context and reduce adherence." / MEMORY.md: "The first 200 lines of `MEMORY.md`, or the first 25KB, whichever comes first, are loaded at the start of every conversation." | <https://code.claude.com/docs/en/memory> |
| This repo's real docs: measured | 1,192 `.md` files, 35 MB. Largest: `docs/research/kitty-drag-action-implementation-2026-09-16.md` = 146,511 chars / 1,982 lines / 20,707 words. Mean 61–73 chars/line across 5 sampled files. | `wc` on `~/Development/claude-infrastructure/docs` |

**Derived page-size rule (theoretical, arithmetic from the above).** At ~68 chars/line, 2,000 lines ≈
136 KB ≈ **~34K tokens** — a single Read that costs ~17% of a 200K window and will hit `PARTIAL view`.
The 2000-line default is therefore *not* a budget, it is a ceiling you must stay far below.

> **Page target: ≤ 400 lines / ≤ 25 KB / ≤ ~2,500 words ≈ ~6K tokens.**
> Hard split at 800 lines. Rationale: 25 KB is Anthropic's own shipped budget unit for a file meant to
> be read in full (MEMORY.md), ~6K tokens is ~3% of a 200K window so an agent can read six pages and
> still have room to work, and it is comfortably inside the Read token limit so no page ever pages.

**Derived enumeration rule (empirical).** `Glob('docs/**/*.md')` over a 1,192-file corpus returns 100
of them, chosen by mtime. That is not a truncated listing, it is a **silently biased sample**. Combined
with §4's mtime finding, the bias is toward "whatever git checked out last," i.e. arbitrary. An agent
must never be expected to discover the corpus by Glob. It discovers it by reading one index file.

---

## 3. The index/manifest tier — and its shipped precedents (empirical)

**llms.txt v2** is the closest standardised precedent and its structure maps 1:1 onto what `/docs`
needs. Verbatim, <https://llmstxt.org/>:

- "An H1 with the name of the project or site. This is the only required section"
- "A blockquote with a short summary of the project, containing key information necessary for
  understanding the rest of the file"
- "Zero or more markdown sections delimited by H2 headers, containing 'file lists' of URLs where
  further detail is available"
- file-list entries are "a required markdown hyperlink `[name](url)`, then optionally a `:` and notes"
- v2 adds an **`## Optional`** section: "used, by convention, for secondary information: links an
  agent can skip when a shorter context is needed."
- the budget rule, stated as the design goal: "**the file itself stays small enough to fit in context.
  The detail lives behind the links, and is fetched only when needed.**"
- v2's twin-file convention: "provide a clean markdown version of those pages at the same URL as the
  original page, either with `.md` appended (`page.html.md`) or with the extension replaced by `.md`"

Anthropic ships this exact shape at <https://code.claude.com/docs/llms.txt> — H1, blockquote, `##`
group, `###` subgroup, then `- [Overview](https://…/overview.md): Claude Code is an agentic coding
tool that reads your codebase…`. Note the **`.md` twin URL** and the **one-sentence description per
entry**. That is the row format for `docs/INDEX.md`.

**DeepWiki `.devin/wiki.json`** is the only shipped *manifest that drives generation* of an agent wiki
(<https://docs.devin.ai/work-with-devin/deepwiki>):

- `repo_notes` (array, required): objects with `content` (string, **max 10,000 characters**) and
  optional `author`
- `pages` (array, required): `title` (required, unique, non-empty), `purpose` (required — "Documentation
  scope for the page"), `parent` (optional, title of hierarchical parent), `page_notes` (optional array)
- "**Maximum 30 pages (80 for enterprise)**" and "Maximum 100 total notes"
- "when a config file is present, we bypass the default cluster-based planning and create exactly the
  pages you specify — so list every page you want."

Two things to steal and one to reject. **Steal:** `purpose` as a required field (a page's scope
declared *before* it is written is what makes incremental refresh decidable), and `parent` by title
(hierarchy without path coupling). **Reject:** the 30-page cap as a design rule — it is a vendor cost
control, not a finding. It is still weak evidence that a curated layer is *meant* to be small; a
corporate programme's curated layer will want 40–150 pages, which is fine as long as the index stays
under one Read.

**The local `repo-wiki` skill** (`~/.claude/skills/repo-wiki/SKILL.md`, symlink to
`claude-infrastructure/skills/repo-wiki/SKILL.md`) already encodes the decomposition and citation
contract this axis needs, and it is the right authority for the curated layer's *writing* pass:

- The plan-before-prose contract, with the file list attached: "Emit a table before writing any page,
  and **attach each page's file list** — that list is what the page pass is allowed to claim from:
  `| id | title | one-line description | files this page rests on | section |`" (SKILL.md:150-155).
  **This is already the page↔source dependency map**, invented for a different purpose. Persist that
  table and L4 exists.
- Decomposition, stated as a prohibition: "**Do NOT create one giant page per subsystem. SPLIT by
  concern**" — a multi-step pipeline gets one page per stage, an adapter system one page per adapter,
  an API surface "endpoints grouped into logical pages … never one page for the whole API" (:120-131).
- Required page shape: a collapsible `<details><summary>Relevant source files</summary>` block listing
  every source **first**, before the `# title` (:159-172). That block is the per-page provenance
  record, greppable, and it is where a tombstone belongs.
- The citation contract: "Cite representative evidence inline by path (`src/foo.ts:120`)… omit any
  surface the source does not support rather than documenting the shape you expected to find" (:186-190).
- Verification: "every path cited exists, every claim traces to a file in that page's list, and no
  section is README restatement" (:206-209). Path-existence is a runnable check — that is the staleness
  gate.

---

## 4. Freshness — the three mechanisms, and the two that don't work (empirical)

| Mechanism | Verdict | Evidence |
|---|---|---|
| **filesystem mtime** | **BROKEN in git.** `git clone` set both files to clone time; a file `touch`'d to 2020-01-01 came back as today. | measured: `git init` → `touch -t 202001010000 old.md` → commit → `git clone` → both files show today's date |
| **`Glob` mtime ordering as a "what's new" query** | **BROKEN for the same reason**, and additionally capped at 100. Works only in a long-lived checkout, never in a fresh worktree or CI clone. | vendor doc + the measurement above |
| **`git log` / `git diff --name-status`** | **WORKS** and is the right L5 primitive — but see the rename caveat below. | measured |
| **date in the filename** (`-YYYY-MM-DD` suffix) | **WORKS.** Survives clone, greppable, sortable by `ls`, and visible in a Glob listing without a Read. This repo already does it (`worktree-backlog-triage-2026-07-26.md`). | measured on the local corpus |
| **frontmatter timestamp** | **WORKS**, and has Anthropic's own precedent: auto-memory files get a `modified` ISO 8601 field, because "The timestamp shows how current the fact is, **both to you and to Claude when it reads the memory back.**" | <https://code.claude.com/docs/en/memory> |

**The rename finding (empirical, and it changes the L2 contract).** git's rename detection is a
**similarity heuristic**, not a fact:

```
git mv one.md two.md; (append 4 lines)     → default -M (50%):  D one.md  /  A two.md
                                            → -M20%:            R042 one.md → two.md
pure rename, no edit                        → default:          R100 three.md → four.md
git log --follow two.md                     → does NOT cross the 42%-similar rename
```

So **"renamed" cannot be derived from git** when the rename came with a substantial edit — which is
precisely the messy-corporate case (`Budget FY26.xlsx` → `Budget FY26 v3 FINAL.xlsx`, contents also
changed). The stable identity must come from upstream (the Graph `driveItem` `id`) and be **written
into the mirror page's frontmatter**, so a rename is a frontmatter-preserving path change rather than
a delete+create. This is the strongest single argument in this report for provenance frontmatter.

---

## 5. Deletions — tombstones, and why removal alone is insufficient

**The precedent is CDC, not docs.** Debezium emits *two* events for a delete: an `"op": "d"` event
carrying the previous value, **and a tombstone event with the same key and a null value**;
`tombstones.on.delete` defaults to `true`, and suppressing tombstones "prevents Kafka from removing
records for a deleted key during log compaction"
(<https://debezium.io/documentation/reference/stable/transformations/event-flattening.html>,
<https://docs.redhat.com/en/documentation/red_hat_build_of_debezium/2.5.4/html/debezium_user_guide/applying-transformations-to-modify-messages-exchanged-with-kafka>).

Mapped onto `/docs` (theoretical, by analogy): a curated page cites `../mirror/finance/fy26-budget.md`.
Upstream deletes the source. If the pipeline just removes the mirror file, the agent that follows the
citation gets a missing-file error and **cannot distinguish three states**: deleted upstream · never
existed · I got the path wrong. Those demand opposite actions (trust the curated claim as historical /
correct my reasoning / retry the path). A no-content tombstone is the discriminator.

**Recommendation — tombstone AND changelog, not either/or:**

- **Tombstone in place** (keeps every existing citation resolvable):
  ```markdown
  ---
  status: deleted
  deleted_at: 2026-09-21
  last_seen_sha256: 9f2c…
  source_id: 01ABCD…            # Graph driveItem id — survives renames
  source_path: /Finance/FY26 Budget.xlsx
  superseded_by: ../mirror/finance/fy27-budget.md   # or: null
  ---
  # [DELETED UPSTREAM] FY26 Budget
  Removed from SharePoint on 2026-09-21. Last converted content is at commit `abc1234`:
  `git show abc1234:docs/mirror/finance/fy26-budget.md`
  ```
- **`docs/CHANGELOG.md`**, append-only, one section per sync, `A|M|R|D` per path — because a *set* of
  tombstones is not a *timeline*, and "what changed since I last looked" is a timeline question.
- **`git log` as the authoritative answer**, with the exact command written into `docs/INDEX.md` so the
  agent doesn't have to invent it:
  `git log --since='<date>' --name-status --diff-filter=ACDMR -- docs/`
- Reap tombstones on a policy (e.g. 180 days), never on the next sync. Their whole value is being
  readable *later* than the deletion.

---

## 6. Naming — what is actually mechanical, and what is taste

**Empirical: kebab-case is word-addressable, snake_case and camelCase are not.** Measured with both
BSD `grep -E` and ripgrep 15.2.0 on a file containing `api-spec`, `api_spec`, `apiSpec`:

```
pattern  \bapi\b   → matches ONLY the line containing api-spec
pattern  api\b     → matches ONLY api-spec
pattern  \bspec\b  → matches ONLY api-spec
```

`_` is a word character in PCRE, so `\b` does not fire inside `api_spec`; `-` is not, so it does.
**Honest bound:** this only matters for boundary-anchored patterns (`\b…\b`, `rg -w`, `grep -w`). A
bare substring grep (`api`) or a glob (`*api*`) matches all three spellings equally. The advantage is
real but conditional — cite it as "kebab-case makes every token independently addressable by a
word-boundary search," never as "kebab-case is greppable and snake_case isn't."

**Empirical: two filename hazards on corporate macOS, both silent.**

1. **Case collision.** `touch C/API-Spec.md; touch C/api-spec.md` on APFS produced **one** file,
   `API-Spec.md`; `git config core.ignorecase` = `true`. A slugifier that lowercases must therefore
   assume **collisions overwrite without error**. Require a collision check that appends a
   disambiguator derived from the source id, not from a counter.
2. **`[` in a filename poisons globs.** Real SharePoint names contain brackets. Measured:
   `find . -name '*[FINAL]*'` matched **both** `Q1 Report [FINAL].pdf` *and* `Budget FY26 (v3).xlsx` —
   because `[FINAL]` is a bracket expression matching one of `F,I,N,A,L`, and "FY26" contains an `F`.
   The vendor docs confirm the same class of failure for rule globs: "Glob syntax treats `[` as the
   start of a bracket expression… A pattern with a `[` that can't be read as a bracket expression,
   such as `photos [2024/**`, is invalid: it matches nothing" (<https://code.claude.com/docs/en/memory>).

**Naming rules, each with its reason:**

| Rule | Why |
|---|---|
| `kebab-case.md`, lowercase only | word-boundary addressability (measured); avoids the APFS case-collision trap |
| **entity-first, then aspect**: `acme-migration-scope.md`, not `scope-acme-migration.md` | prefix-sorted listings cluster by entity; `ls docs/clients/acme*` and `Glob('**/acme-*')` both become one-shot queries. *Theoretical*, but directly downstream of Anthropic's "folder hierarchies, naming conventions… provide important signals." |
| `-YYYY-MM-DD` suffix **only on point-in-time artefacts** (meeting notes, a dated deck, a snapshot) | the date *is* part of the identity. Do **not** date living reference pages — a date suffix on a page that gets updated forces a rename, which §4 shows git will misreport as delete+create |
| slugify: strip `[]()#{}`, `–`→`-`, collapse whitespace to `-`, strip diacritics | measured glob poisoning; and `#` is a URL fragment delimiter, so it breaks relative markdown links |
| **mirror path mirrors source path**, slugified segment-by-segment | makes the mirror path *derivable* from the source path, so a curated page's citation can be predicted without consulting a map |
| never abbreviate in a filename (`purchase-order`, not `po`) | grep is lexical; an abbreviation the agent doesn't guess is an unreachable page. Put the abbreviation in a frontmatter `aliases:` line instead (§8) |

---

## 7. Proposed two-tier layout

```
docs/
  INDEX.md                    # the only always-mentioned file. llms.txt shape. ≤200 lines / ≤25KB.
  CHANGELOG.md                # append-only, one section per sync, A|M|R|D per path
  MANIFEST.jsonl              # machine tier: one line per source. NOT for the agent to read whole.
  DEPENDS.tsv                 # page↔source map. TAB-separated. one row per (page, source).
  README.md                   # 20 lines: how this folder is built, which command answers "what's new"

  topics/                     # ── TIER 2: agent-curated. Hand-written/agent-written. The answer layer.
    CLAUDE.md                 # ~15 lines: "pages here are synthesis; every claim cites ../mirror/…"
    clients/
      acme/
        INDEX.md              # local index for this entity
        acme-commercial-terms.md
        acme-integration-scope.md
        acme-open-decisions.md
    workstreams/
      data-migration/
        INDEX.md
        migration-cutover-plan.md
        migration-open-risks.md
    decisions/
      2026-09-14-storage-tier-choice.md     # dated: the decision IS a point-in-time artefact
    people/
      stakeholder-map.md

  mirror/                     # ── TIER 1: machine-generated, 1:1, never hand-edited.
    CLAUDE.md                 # ~10 lines: "GENERATED. Do not edit. Edits are overwritten each sync."
    _tombstones/              # optional: move deleted pages here instead of in-place, if in-place
                              #   tombstones clutter directory listings. Costs link stability — prefer in-place.
    sharepoint/
      finance/
        fy26-budget.md        # + fy26-budget.assets/ for extracted images/sheets
        fy26-budget.md.meta.yaml   # optional sidecar if frontmatter must stay out of the body
    onedrive/<user>/…
    email/
      2026/09/2026-09-14-acme-kickoff-recap.md
    teams/
      <team>/<channel>/2026-09.md          # ONE page per channel per month, not per message
```

**Why this shape, rule by rule:**

| Rule | Justification |
|---|---|
| Two tiers, mirror never hand-edited | the mirror must be a **pure function** of the source, or an incremental sync cannot decide what to rewrite. Hand edits make every page's hash unreliable and force a 3-way merge nobody will maintain. |
| `topics/` organised by **entity** (client / workstream / decision / person), not by **document type** | corporate queries are entity-shaped ("what did we agree with Acme on retention?"), never type-shaped ("show me the spreadsheets"). Type lives in the mirror path, where it came from. *Theoretical, downstream of the Anthropic folder-signal quote.* |
| One `CLAUDE.md` per tier, ~10–15 lines | "Claude Code loads every CLAUDE.md file from your working directory and every parent directory at launch, **then loads each subdirectory's file on demand when it reads files there**" (<https://code.claude.com/docs/en/large-codebases>). A 10-line `mirror/CLAUDE.md` saying GENERATED — DO NOT EDIT costs **zero** context until the agent actually opens the mirror, and then it arrives exactly when needed. This is the cheapest guardrail in the whole design. |
| `_tombstones/` is the *second* choice | moving a deleted page breaks every existing relative citation to it — the thing the tombstone exists to preserve. |
| Teams: one page per channel per **month** | per-message files blow past Glob's 100 cap in a week and each is far below any useful read size. Monthly rollups land near the 25 KB target. |
| `mirror/<source-system>/…` as the first segment | the source system determines the freshness mechanism (Graph delta vs manual inbox), so it must be visible in the path without a lookup. |

**`docs/INDEX.md` row format** (llms.txt-derived, verbatim structure from §3):

```markdown
# Acme Programme — document context

> 412 curated pages over 8,910 mirrored source documents. Every claim in topics/ cites a
> mirror/ path. Last sync 2026-09-21 14:02 UTC (manifest generation 219).
> "What changed since <date>": git log --since='<date>' --name-status --diff-filter=ACDMR -- docs/

## Start here
- [How this folder is built](README.md): sync mechanism, which sources are Graph-delta vs manual.
- [Change log](CHANGELOG.md): one section per sync, A|M|R|D per path.

## Clients
- [Acme — commercial terms](topics/clients/acme/acme-commercial-terms.md): pricing, discount schedule,
  and the renewal clause, as agreed 2026-08; cites 6 mirror sources.

## Optional
- [Mirror tree](mirror/): 1:1 machine conversions. Read these only to verify a specific citation.
```

The `## Optional` section is the llms.txt v2 construct, used for exactly its stated purpose — "links an
agent can skip when a shorter context is needed." The mirror belongs there: it is a *verification*
surface, not a *reading* surface.

---

## 8. Frontmatter contract

**Mirror page** (generated; every field is either from the source or computed):

```yaml
---
source_system: sharepoint
source_id: 01ABCDEF2GHIJK…        # Graph driveItem id — the ONLY stable identity (see §4)
source_path: /sites/acme/Shared Documents/Finance/FY26 Budget.xlsx
source_web_url: https://contoso.sharepoint.com/:x:/r/sites/acme/…
source_etag: "{4F2A…},7"
source_modified: 2026-09-14T09:12:00Z
source_modified_by: jane.doe@contoso.com
content_sha256: 9f2c1d…                # of the SOURCE bytes
rendered_sha256: 3ab77e…               # of THIS markdown — decides whether the page changed
converter: markitdown@0.1.3            # pin: a converter bump is a corpus-wide content change
converted_at: 2026-09-21T14:02:11Z
status: current                        # current | deleted | superseded
aliases: [FY26 budget, FY-26 budget, purchase order forecast, PO forecast]
---
```

**Curated page** (hand/agent-written; the `sources` list IS the dependency-map row set):

```yaml
---
kind: topic
entity: acme
purpose: >-                            # DeepWiki's required `purpose` field, stolen verbatim
  What we have agreed with Acme commercially: pricing, discounts, renewal.
  NOT the technical integration scope — that is acme-integration-scope.md.
sources:
  - path: ../../mirror/sharepoint/acme/finance/fy26-budget.md
    at_rendered_sha256: 3ab77e…        # the mirror version this page was written against
  - path: ../../mirror/email/2026/09/2026-09-14-acme-kickoff-recap.md
    at_rendered_sha256: 71c0aa…
reviewed_at: 2026-09-21
modified: 2026-09-21T14:40:00Z          # Anthropic's own auto-memory field name
aliases: [Acme pricing, Acme MSA terms]
---
```

Two fields carry most of the weight.

- **`at_rendered_sha256`** makes staleness a *comparison*, not a guess: a page is stale iff any listed
  source's current `rendered_sha256` differs from the pinned one. Same idea as Cursor's embedding
  cache, which is "keyed by the content hash from chunking" so "Chunks whose hashes changed since the
  last sync get re-embedded, and the rest reuse cached embeddings"
  (<https://cursor.com/blog/secure-codebase-indexing>) — applied to *synthesis* instead of *embedding*.
- **`aliases:`** is the cheap substitute for embeddings (§10). It is plain greppable text, so the
  query "PO forecast" reaches a page titled "FY26 Budget" via one `rg -i 'PO forecast' docs/`.

---

## 9. The page↔source dependency map — format, and an honest warning

**No golden example exists.** Cursor's unit is a chunk of one file (1:1, no synthesis). DeepWiki has no
incremental path at all — its manifest drives a full generation. The closest genuine precedent is a
build system's **auto-generated depfile** (a `.d` file per target, emitted by the tool that read the
prerequisites, then `include`d by the makefile so the next build knows what to redo). I could not fetch
the GNU make manual for that (HTTP 429), so treat the analogy as **theoretical**, not cited. The local
`repo-wiki` skill's plan table (§3) is the nearest thing we already own.

**Format — `docs/DEPENDS.tsv`, one row per (page, source), TAB-separated:**

```
page	source	pinned_sha	role
topics/clients/acme/acme-commercial-terms.md	mirror/sharepoint/acme/finance/fy26-budget.md	3ab77e	primary
topics/clients/acme/acme-commercial-terms.md	mirror/email/2026/09/2026-09-14-acme-kickoff-recap.md	71c0aa	corroborating
```

- **TSV, not JSON.** The reverse query — "which curated pages does this changed source feed?" — is one
  line: `awk -F'\t' '$2=="<path>"{print $1}' docs/DEPENDS.tsv`. On a JSON graph it is a `jq` program the
  agent has to compose correctly under time pressure. The whole point is that the query be *obvious*.
- **`role`** lets the refresher rank work: a `primary` source changing means the page must be rewritten;
  a `corroborating` source changing may only need a citation line updated.
- **Derive it, don't maintain it.** Generate `DEPENDS.tsv` by parsing every curated page's `sources:`
  frontmatter. A map maintained separately from the pages *will* drift, and the drift is invisible.
- **The refresh queue**, computable in one shell line, is the deliverable:
  ```bash
  # pages whose pinned source version no longer matches the mirror
  awk -F'\t' 'NR>1{print $1"\t"$2"\t"$3}' docs/DEPENDS.tsv | while IFS=$'\t' read -r p s sha; do
    cur=$(sed -n 's/^rendered_sha256: //p' "docs/$s" 2>/dev/null | head -1)
    [ -z "$cur" ] && { echo "TOMBSTONE-OR-MISSING	$p	$s"; continue; }
    case "$cur" in "$sha"*) ;; *) echo "STALE	$p	$s" ;; esac
  done | sort -u
  ```
  Write that command **into `docs/README.md`**, because per §1 nothing in the harness will invent it.

⚠️ **Adversarial note on TAB.** `IFS=$'\t' read` collapses runs of tabs and drops trailing empty
fields, so a row with an empty `role` shifts columns left silently. Parse with `awk -F'\t'`, which is
the only tool here that sees an empty field. (This is a known failure in this repo's own corpus —
`docs/lessons/tab-is-ifs-whitespace-so-empty-tsv-cells-vanish.md`.)

---

## 10. Should there be a local embedding index? — **No, with one named exception**

**Verdict: no, for the curated layer. Build the alias tier first and measure before adding vectors.**

| Consideration | Reading |
|---|---|
| The consumer has no index and does not want one | §1. Any index would be queried only through an MCP tool call the agent must choose to make — i.e. it re-introduces the black-box tool call the operator's whole request is trying to eliminate. |
| Anthropic removed one from this exact product | §1, second-hand but consistent. |
| The failure mode grep actually has | **vocabulary mismatch**, not ranking: the query says "PO", the doc says "purchase order". |
| The cheap fix for that failure mode | an `aliases:` frontmatter line per page (§8) + a synonym block in `docs/INDEX.md`. Plain text, zero infrastructure, reachable by `rg -i`, and it composes with the agent's existing behaviour instead of competing with it. |
| The exception that would justify vectors | a mirror of **tens of thousands** of pages where the operator's *own* question is genuinely fuzzy ("find anything about vendor risk") and the entity taxonomy has failed. That is a search-over-the-mirror problem, not a docs-layout problem. |
| If you do build it | **sqlite-vec.** One file, no daemon, no CGO surprises, `upsert_records` + `delete_by_ids` both present; LanceDB's advantage is columnar bulk-write throughput and fenced/transactional upserts, which matter at a scale this corpus is not at. <https://kanopylabs.com/blog/lancedb-vs-chroma-vs-sqlite-vec>, <https://shaharia.com/blog/choosing-embeddable-vector-database-go-application/>. Key it on `rendered_sha256` + chunk hash so the upsert set is exactly the change set, and **delete by `source_id`** on tombstone — a vector store that never deletes will confidently answer from documents that no longer exist. |
| turbopuffer | ruled out: hosted, and its published advantage is trillion-scale serverless multi-tenancy (<https://cursor.com/blog/secure-codebase-indexing>). Sending a corporate M365 corpus to a third-party vector service is a procurement conversation, not an engineering one. |

---

## 11. Where the index lives in the harness — evidence-backed placement

Do **not** paste the docs index into `CLAUDE.md`. Anthropic's own exclude list names both defects
directly (<https://code.claude.com/docs/en/best-practices>): ❌ "Detailed API documentation (link to
docs instead)" and ❌ "**Information that changes frequently**" — a docs index is both.

| Carrier | Loads | Cost | Use for |
|---|---|---|---|
| `CLAUDE.md` (root) | every session, full content | "Every request" | **3 lines**: `docs/INDEX.md` is the map; `mirror/` is generated; the one command that answers "what changed". |
| `.claude/skills/<name>/SKILL.md` | description at start, body on demand | "Low (descriptions every request)" | **the docs index itself** — Anthropic's named example for a skill is literally "API docs skill with endpoint patterns". `description:` should lead with the words a real request contains. |
| `.claude/rules/*.md` with `paths:` frontmatter | "When Claude works with a file matching the rule's `paths:` glob" | zero until matched | a rule scoped to `paths: ["docs/mirror/**"]` carrying *don't edit, it's generated, here's the sync command*. |
| `docs/mirror/CLAUDE.md` | on demand, when the agent reads a file in that directory | zero until then | the same guardrail, colocated. Prefer this over the rule — it lives next to what it governs and needs no central registry. |
| subagent | isolated window | "Isolated from main session" | the sync itself, and any broad search over the mirror. "The infinite exploration… Claude reads hundreds of files, filling the context. **Fix**: Scope investigations narrowly or use subagents." |

All quotes: <https://code.claude.com/docs/en/features-overview>, <https://code.claude.com/docs/en/memory>,
<https://code.claude.com/docs/en/best-practices>.

---

## 12. Adversarial pass — what I got wrong or cannot support

1. **I nearly cited "~30,000 characters inline" as the Read budget.** It is the **Bash output**
   read-back limit on the same doc page. The Read tool's limit is expressed in tokens and is not
   published as a number. The 2000-line figure comes from the harness's tool description, and §2 shows
   it corresponds to ~34K tokens of real markdown — so it is a ceiling, not a target. Any page-size
   recommendation sourced to "the 2000-line default" is reasoning from the wrong quantity.
2. **The kebab-case argument is narrower than it reads.** It holds for `\b`-anchored and `-w` searches
   only; bare-substring grep and globbing are indifferent. Stated as conditional in §6.
3. **"Glob's 100-cap makes an index mandatory" overstates.** The agent can still enumerate with
   `ls`/`find` in Bash, and Grep's `files_with_matches` has no documented cap. The defensible claim is
   narrower and worse: Glob returns a *silently biased sample* whose bias (mtime) is meaningless after
   a clone, so enumeration via Glob is unreliable rather than impossible.
4. **DeepWiki's 30-page cap is a vendor cost control**, not evidence about optimal page counts. Used
   only as weak support for "keep the curated layer small."
5. **Anthropic-removed-RAG is second-hand.** Two blogs quoting Boris Cherny; no first-party statement
   found. The first-party evidence is the *softer* context-engineering post, which explicitly allows a
   hybrid. If the operator's corpus turns out to need vectors, nothing I found forbids it.
6. **The page↔source dependency map has no shipped precedent** (§9). This is the genuinely novel
   component and the one to prototype on ~20 pages before committing the architecture.
7. **Converter determinism is untested here and is a silent corpus-wide hazard.** If the PDF/DOCX
   converter embeds a timestamp, a GUID, or any nondeterministic ordering, every `rendered_sha256`
   changes on every run, every curated page reads STALE, and the refresh queue becomes the whole
   corpus — the diff-only design fails *closed into a full re-pull*. Assert it before building: convert
   the same file twice and require byte-identical output. (Same class as this repo's
   `docs/lessons/file-hash-is-not-pixel-content.md`, where a PNG `tIME` chunk made identical renders
   differ by hash.) Pin the converter version in frontmatter so a *deliberate* converter bump is
   distinguishable from source churn.
8. **Untested by me:** whether an agent's retrieval success actually improves with entity-first naming
   versus type-first. It follows from the Anthropic folder-signal quote but I ran no A/B. The cheap
   experiment exists: build both layouts over the same 50 sources and score a fixed question set.

---

## 13. Sample rows in the brief's format

| Mechanism | Gives | Golden example | Limits | Slot | Evidence |
|---|---|---|---|---|---|
| llms.txt v2 index file | one-Read map of the corpus; `## Optional` marks skippable links | `code.claude.com/docs/llms.txt` | no freshness, no deletion semantics, hand-maintained | L4/L5 consumer entry | "the file itself stays small enough to fit in context" <https://llmstxt.org/> |
| `.devin/wiki.json` manifest | required per-page `purpose` + `parent` hierarchy declared before generation | DeepWiki | 30 pages (80 ent.); full regeneration, no incremental | L4 plan | "Maximum 30 pages (80 for enterprise)" <https://docs.devin.ai/work-with-devin/deepwiki> |
| repo-wiki structure pass | page plan table with **files this page rests on** — already the dependency map | local skill | written for one-shot generation; nothing persists the table | L4 map | `skills/repo-wiki/SKILL.md:150-155` |
| per-directory `CLAUDE.md` | zero-cost guardrail that arrives only when the agent opens that directory | Anthropic monorepo guide | not enforcement — "Claude treats them as context, not enforced configuration" | consumer guardrail | <https://code.claude.com/docs/en/large-codebases> |
| Skill as index carrier | description resident, body on demand | Anthropic's own "API docs skill" example | description can be truncated when many skills exist | consumer entry | <https://code.claude.com/docs/en/features-overview> |
| frontmatter `modified` / `at_rendered_sha256` | staleness as a comparison, survives clone | Anthropic auto-memory `modified` field | nothing in the harness reads it — a script must | L4 refresh queue | "The timestamp shows how current the fact is" <https://code.claude.com/docs/en/memory> |
| chunk-hash keyed cache | re-do only what changed | Cursor embedding cache | 1:1 file→chunk; no many→one synthesis | L2→L4 | "keyed by the content hash from chunking" <https://cursor.com/blog/secure-codebase-indexing> |
| CDC tombstone | "deleted" distinguishable from "absent" | Debezium `tombstones.on.delete=true` | accumulates; needs a reap policy | L3/L5 | "a tombstone event that has the same key but a null value" <https://debezium.io/documentation/reference/stable/transformations/event-flattening.html> |
| `git log --name-status --diff-filter` | authoritative "what changed since <date>" | git | rename detection is a 50%-similarity heuristic; measured miss at 42% | L5 | measured, §4 |
| filesystem mtime / Glob mtime sort | — | — | **does not survive `git clone`** (measured); Glob caps at 100 | ✗ reject as a freshness carrier | measured, §4 |
