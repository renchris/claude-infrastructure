# This directory is a mirror, and here is exactly what that means

**The working repo is `~/.claude/skills/kpmg-deck`.** It has its own git history — 25 commits at
the time of writing — and **no git remote**, so until this mirror existed the entire package lived
on one disk with no copy anywhere.

## Why kpmg-deck is not like the other skills

Every other skill in this checkout is deployed to the live layer as **per-file symlinks**
(`~/.claude/skills/agent-teams/SKILL.md` → `<checkout>/skills/agent-teams/SKILL.md`). kpmg-deck is
a **real directory in the live layer** that was never in a checkout at all — the same shape as the
STRAY condition `scripts/deploy-link-parity.sh` documents, though skills are outside that script's
scope so nothing flagged it.

It is also unlike the others in kind: the rest are prose (a `SKILL.md`). This one is a package —
about 11,000 lines of Python across `assets/`, plus examples, references and a render script.

## What is and is not recoverable from here

| | Where it lives | Recoverable if the disk dies |
|---|---|---|
| Every source file | this mirror, pushed to the GitHub remote | **yes** |
| The commit messages, which carry the reasoning | `HISTORY.md`, generated from the working repo | **yes** |
| The git history as a graph — branches, diffs, blame | `~/.claude/skills/kpmg-deck/.git` only | **no** |
| `showcase.pptx` | deliberately excluded — a stale build artifact | n/a, regenerate it |

## The one thing left, and why an agent did not do it

Normalising this properly means putting the source here, symlinking the live files back, and
wiring it through `install.sh` the way every other skill is. That was **not** done unattended: the
live directory is a working git repo, and replacing its files with symlinks would strip the local
history that is the only copy of the graph. It needs a deliberate decision about whether that
history is worth keeping before anything is moved.

Until then this mirror is refreshed by hand. Re-run it with:

    cd ~/.claude/skills/kpmg-deck
    git ls-files | grep -v '\.pptx$' | while read -r f; do
      mkdir -p <checkout>/skills/kpmg-deck/"$(dirname "$f")"
      cp "$f" <checkout>/skills/kpmg-deck/"$f"
    done

A mirror that has to be refreshed by hand will go stale, and this paragraph is the only thing
saying so — which is the honest state, not a recommendation.
