# A probe corpus kept under /tmp erodes between runs — rebuild from git and check its hash before reusing it

**2026-09-28** (evidence `docs/research/sonnet55-synth-probe-2026-09-28/void-run1-briefs-missing/`).

The 2026-09-22 synthesis re-probe left its six briefs in `/tmp/o55-briefs/` and its repo snapshot in
`/tmp/o55probe-repo-47c3317eb/`. Six days later the brief directory existed but was EMPTY, and the snapshot had
lost ~3,700 files — the macOS /tmp cleaner deletes files by age and leaves directories standing. A 24-cell re-run
against those paths produced 24 polite "I never got the brief" answers, each costing a full model call, and every
cell exited 0 with `end_turn`, so nothing in the result envelope flagged it.

**Rule.** Treat anything under /tmp as gone after a few days, even when the directory is still there. Before
reusing a probe corpus: rebuild the repo snapshot with `git archive <sha> | tar -x`, restore briefs from the
committed corpus, and verify the committed `corpus.sha256`. Then look at one cell's output before letting the
other N run — an exit code of 0 and a stop reason of `end_turn` say nothing about whether the model had its input.
