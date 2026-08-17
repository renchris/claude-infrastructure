# Skills deliberately NOT tracked here

Every directory under `skills/` is versioned and deployed by `install.sh` as per-file symlinks into
`~/.claude/skills/<name>/`. A handful of live skills are deliberately absent from that list. This
file is the durable record of that decision, because the declaration each one carries lives in an
*untracked* `SKILL.md` and would not survive a rebuild of `~/.claude`.

Filed against backlog `3e2358f03e23`, which measured 18 live skills with no tracked source at all
(2026-08-11, re-measured 2026-08-16). 13 were tracked; these 5 were not, and each has a reason.

| Skill | Why not tracked |
|---|---|
| `motion` | Vendored with the Motion MCP plugin. Upstream owns the text and replaces it wholesale on re-vendor, so a tracked copy is a fork that silently diverges from its source. |
| `react-best-practices` | Vercel Engineering's published React/Next.js performance guidance — third-party text we do not author, refreshed from upstream rather than maintained here. |
| `vercel-design-guidelines` | Vercel's published design guidelines — same reasoning as above. |
| `pyramid-principle-full` | An exhaustive derivative of a copyrighted book (*The Minto Pyramid Principle*, Barbara Minto, 2010 ed. — the complete text and all 149 exhibits, with chapter/page citations back to the source scan). Committing it would put a substantial derivative of a commercial work into git history, where it is effectively permanent. |
| `pyramid-principle` | **Not actually sourceless.** Its `SKILL.md` is a symlink to `~/Development/convert-pdf-to-md/pyramid-principle-prompt.md`, which is *tracked in that repo* and has a remote. It already has history and a path back; it simply is not this repo's to hold. See the note below. |

The first four carry a `> **Local-only …**` block under their first heading, so the next editor who
opens one is told before editing. That block is also what the row's stored falsifier greps for.

## Two premises in the original row that measurement did not support

Recorded so neither gets re-derived from the row's title later.

**"Duplicated independently in `~/.claude` and `~/.claude-secondary`, with nothing keeping them in
sync, so an edit to one silently forks the other" — false.** There is exactly one skills tree:
`~/.claude-secondary/skills` and `~/.claude-tertiary/skills` are *directory symlinks* to
`~/.claude/skills`. All three config dirs resolve to the same inode for every file checked, so a
fork between config dirs is not possible. The row's other claims stand — no git history, no `/ship`
path, invisible to `deploy-parity-assert` — and those are what tracking fixes.

**"19 skills … these are REAL FILES" — 18, and one is not a real file.** `cc-version-audit` was
tracked between the filing and the re-measure, and `pyramid-principle`'s `SKILL.md` is a symlink
into another repository, not a real file.

## The one item this repo cannot close by itself

`pyramid-principle` needs its provenance note written into
`~/Development/convert-pdf-to-md/pyramid-principle-prompt.md` — a tracked file, on `main`, in a
repo with a GitHub remote and no `CLAUDE.md` of its own. That is a cross-repo write to another
project's default branch, so it is not taken unilaterally from here. Until it is, the stored
falsifier for `3e2358f03e23` reports `n=1` against this skill alone.
