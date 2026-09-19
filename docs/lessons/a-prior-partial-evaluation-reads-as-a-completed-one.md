# A prior PARTIAL evaluation reads as a completed one

**2026-09-19, the git-forest adjudication.** Asked whether a third-party worktree manager
(`hiradp/git-forest`) was worth adopting, I ran a 20-candidate, 68-agent workflow against it and
was one step from shipping the verdict when the workflow's own completeness critic asked the
question nobody else had: *what did you never compare this against?*

The answer was sitting in `/opt/homebrew/bin/worktree-harness`, installed on this machine since
2026-06-03 — and, worse, **already cited in our own source**. `scripts/new-worktree.sh:49-56`
carries a paragraph headed "WHY NOT `worktree-harness`", which adjudicates the tool, calls it
"generic and good", and rejects it on two configurable defaults (a worktree root, and a spurious
`npm ci` inferred from a diagram-only `package.json`).

**That paragraph is about `worktree-harness new`. It says nothing about `gc`, `status`, `merge`
or `doctor`** — and those four are where the value was. Run afterwards, its `gc` turned out to be
liveness-aware (`KEEP … open by a live process`), conservative on dirty and unlanded trees, and
to **agree exactly with our own 1,495-line janitor** on the overlapping population. It also ships
a global `--dry-run` and a `status --porcelain` machine contract that the 1-star subject of the
whole investigation does not.

So sixty agent passes went to a repository with 1 star, 0 releases and one author, while the real
comparator sat installed, one command away, named in a file the investigation had already read.

## The shape

A prior evaluation leaves a verdict-shaped residue. Grep finds "we looked at X and rejected it",
the sentence is true, the reasoning is sound — and **the SCOPE of what was examined is nowhere in
the sentence**. A reader takes it as *X was assessed*; what it recorded was *one verb of X was
assessed*. Nothing is wrong with the record, and nothing in it announces the gap.

It is worse than no record at all, because a blank invites the check and a verdict closes it.

## What to do

- **When a prior rejection is your reason for not re-examining something, read what it actually
  tested.** Name the surface: "we rejected `worktree-harness new`" is a different claim from "we
  rejected worktree-harness", and only the first is what the file says.
- **Before adjudicating any third-party tool, run `command -v` on its plausible siblings.** The
  comparator that disqualifies your subject is often already installed — and adoption cost is
  zero for a thing that is already on PATH, which makes it the strongest possible alternative.
- **When you write such a rejection, scope it in the sentence.** `scripts/new-worktree.sh:49-56`
  would have cost its author four words ("its `new` verb specifically") and saved this session.
- **Keep a completeness critic in the harness.** It is the only stage that asks what was never
  examined, and here it was the highest-value agent of sixty-eight. A pipeline of finders and
  verifiers can only sharpen the question it was handed.

## Companions from the same session, both already in the corpus — do not re-mint

- I read the comparator's verdict output with `tail` and drew the **opposite** conclusion (its
  per-line `KEEP` / `WOULD remove` verdicts are at the top; the tail is a bare listing). Already
  indexed: `gate-log-tail-hides-the-first-failure`.
- I then accused it of a safety gap using a liveness reading taken 90 minutes earlier. The
  worktree had since finished and landed; re-measured, 0 holders and an empty `git cherry`.
  Already indexed: `tui-capture-is-a-sample-not-a-state` ("re-read right before acting").

Record: `docs/research/git-forest-adjudication-2026-09-19.md`.
