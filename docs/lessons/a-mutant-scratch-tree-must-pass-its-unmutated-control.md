# A mutant's scratch tree must pass its unmutated control first

**Rule.** Before reading any mutant as killed, run the same suite on the UNMUTATED scratch copy and require it
green under a `1..N` plan. A scratch tree that cannot run the suite's setup turns every mutant red for the
setup's reason, and a table of "killed" mutants then proves nothing.

**Incident (2026-10-16, kit-delegated-acceptance).** Per-site mutants for `tests/research-kit-delegated.bats` were
run on scratch copies of the repo (`rsync` of `scripts tests bin skills`). The suite's `setup_file` runs the
research kit's real `gate.sh run` over the `build_good.py` fixture. On the scratch copies that gate run failed, so
`setup_file` failed and every test in the file read `not ok` — a mutant driver counting `not ok` would have reported
all 38 mutants killed. Three separate reasons, each found only because a CONTROL run of the unmutated copy came
first and went red:

1. **`/tmp` is refused.** Gate row 8 fails any record citing a path under `/tmp` ("wiped on reboot"). A scratch dir
   at `/tmp/...` puts `/tmp` paths into the fixture's records. bats' own dirs live under `$TMPDIR`
   (`/var/folders/...`), which is why the suite passes in the worktree. Put the scratch under `$TMPDIR`.
2. **The repo must be a git repo.** Rows read git state of the tree; an `rsync`ed copy without `.git` fails them.
   `git init && git add -A && git commit` the scratch once.
3. **Row 17 reads `docs/research/research-calibration/`** (`evidence/params-measured.json`) from the repo, which a
   copy of `scripts tests bin skills` omits. Copy that directory too.

**How to apply.** Build the scratch the way the suite expects its repo (git repo, under `$TMPDIR`, every directory
the code under test reads), run the unmutated CONTROL, and stop if it is not all-ok. Then apply one mutant at a
time, restoring the file after each run, and require the targeted test red. A wrapper deferral (`cc-bats` exit 75)
is no verdict: retry it, never count it. Pipe the driver's output to a file, not through `grep`, or a
block-buffered `grep` hides every progress line until the end.

Related: `per-site-mutation-attributes-coverage` (one mutant per site), `a-gate-refusal-is-not-a-gate-result`.
