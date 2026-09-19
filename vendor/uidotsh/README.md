# ui.sh — local mirror

A complete local copy of the **ui.sh** skill and design-guideline corpus, captured
before Tailwind Labs retires the remote MCP server that currently serves it.

## Why this exists

On 2026-06-10 Adam Wathan announced ("Goodbye /ui, hello local skills") that ui.sh
is being reorganised from a single `/ui` skill backed by a remote MCP server into
separate, locally-installed skills — explicitly "to remove our remote MCP server as
a point of failure in your workflow."

That remote server (`https://ui.sh/mcp`) is the **only** distribution channel for
this content that we currently have access to. The public `https://ui.sh/skills`
page lists the new skills but publishes no download, package, or repo; the local
installer is served from `https://ui.sh/mcp` (POST) and requires a per-account
ui.sh token that is only visible when logged in. So when the MCP server goes away,
so does our access — unless we hold a copy. This is that copy.

Licensed content, mirrored for the account holder's own local use.

## What was captured

| Tree | Files | What it is |
|---|---:|---|
| `*.md` (root) | 10 | The current top-level skills (`design`, `ideas`, `brand-kit`, `componentize`, `canonicalize-tailwind`, `add-dark-mode`, `dark-mode-image`, `make-responsive`, `markup-from-image`, `ui`) |
| `design/` | 40 | The current design system: `design-guidelines.md` index + 37 rule files + 2 reference modules |
| `ui/` | 47 | **The LEGACY tree being removed** — 7 subskills + `design-guidelines.md` index + 39 legacy rule files |
| `brand-kit/` | 1 | `brand-kit-prompt.md` |
| `assets/` | 77 | Binary placeholder assets from `https://assets.ui.sh` |
| `ui-picker.js` | 1 | The picker toolbar script the `ideas` skill injects at runtime |

## Two things here exist nowhere else

1. **`ui/finalize.md`** — a legacy subskill (titled "Organize") that chains
   componentize → canonicalize. It has **no top-level replacement skill**; when the
   legacy tree goes, this workflow is simply gone.

2. **`ui/ideas.md`** is materially richer than its top-level replacement. It carries
   a "Plan each option before coding it" section — a seven-axis style-definition
   checklist (layout, typography, color, spacing, surfaces, shape, personality) with
   worked good/bad examples, plus the 3-4-options-per-decision default. None of that
   survived into the new `ideas.md`.

More broadly the two guideline trees are **not** duplicates. The legacy files are a
terser formulation of the same rules (no `Covers:` preamble, `uidotsh://ui/...` link
paths) and in several cases are organised differently (`## Design guidelines` /
`## Coding guidelines` splits that the new tree flattens). Both are kept verbatim.

## How it was captured

- Markdown: the MCP tool `mcp__claude_ai_uidotsh__uidotsh_fetch`, written byte-for-byte.
- Assets: plain HTTPS GET against `https://assets.ui.sh` (see `fetch-assets.sh`).
- **Discovery was by breadth-first crawl, not by the server's resource listing.**
  `resources/list` advertises only 10 resources. Everything else — all 79 guideline
  files in both trees, the legacy subskills, `brand-kit-prompt` — is reachable only
  by following `uidotsh://` links inside fetched bodies. Anyone relying on the
  advertised listing would have captured ~11% of the corpus.

## Verifying the mirror

`MANIFEST.txt` holds sha256 + size for every file.

```sh
cd vendor/uidotsh && shasum -a 256 -c <(grep -v '^#' MANIFEST.txt | awk '{print $1"  "$3}')
```

Closure check — every `uidotsh://` URI referenced anywhere resolves to a file here
(88 referenced, 0 missing at capture time):

```sh
cd vendor/uidotsh
comm -23 <(grep -rhoE 'uidotsh://[A-Za-z0-9/_-]+' --include='*.md' . | sed 's|uidotsh://||' | sort -u) \
         <(find . -name '*.md' | sed 's|^\./||; s|\.md$||' | sort -u)
```

## Using it

These are verbatim vendor files, deliberately **not** installed as active skills —
links are still `uidotsh://` URIs, not relative paths, so nothing here changes agent
behaviour by sitting on disk. To turn the corpus into working local skills, rewrite
`uidotsh://design/guidelines/x` → `guidelines/x.md` and add SKILL.md frontmatter.

Prefer the vendor's own installer if the account token is to hand — an official
install will track updates; this mirror is frozen at its capture date.
