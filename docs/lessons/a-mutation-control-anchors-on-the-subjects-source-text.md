# A mutation-based control has anchors in the subject's source, and refactoring disarms it silently

**2026-09-20.** A pure performance change to `bin/cc-limited` — merging two `ps` forks into one —
turned `C2 CONTROL stored_liveness_is_red` RED. Every functional assertion in the suite still
passed, including all of that control's own assertions about the real subject. The thing that broke
was the control's ability to BUILD its mutant.

## How a control can be disarmed by a correct refactor

The control proves the suite would notice a census that CACHES liveness instead of re-deriving it.
It constructs that mutant by string-replacing the subject's own source:

```python
src.replace('def ps_table():',
            'def ps_table():\n'
            '    _c = os.environ["MUT_CACHE"]\n'
            '    if os.path.exists(_c):\n'
            '        return json.load(open(_c))', 1)
src.replace('    return table\n',
            '    json.dump(table, open(os.environ["MUT_CACHE"], "w"))\n'
            '    return table\n', 1)
```

Both are anchored on **literal text in the subject**, and the second takes the **first** occurrence.
The refactor added a second, earlier `return table` inside a new branch. The mutant's cache-write
was therefore planted on a branch the fixture seam never takes — so the mutant never wrote a cache,
never behaved like a cache, and could not exhibit the defect it exists to demonstrate. The control
went red saying, correctly, "my mutant no longer misbehaves."

Read the failure the right way round. **It was not a defect in the subject and not a flake.** It was
the control reporting that it had lost its grip on the subject — which is exactly what you want it
to do, and exactly what is easy to misdiagnose as a broken test to be adjusted.

## Why this is worth a rule

A mutation control is the only kind of test whose correctness depends on the **shape** of the code
under test and not merely its behaviour. Every other test couples to the subject's interface; this
one couples to its **source text**. So:

- A refactor that preserves behaviour perfectly — verified here by byte-identical default screen,
  `--tsv` and `--json` output — can still invalidate it.
- The failure surfaces at the control, not at the change, so the natural reading ("the control is
  stale, relax it") is the one that destroys the red-proof. Relaxing it would have left a suite that
  *looks* mutation-covered and is not, which is
  [fail-safe-default-mimics-the-healthy-state](fail-safe-default-mimics-the-healthy-state.md) one
  level up: the guard, not the subject.

## The rule

When a mutation/CONTROL test goes red after a change that was meant to be behaviour-preserving,
**first ask whether the mutant still gets built**, before touching either side. Then fix the
**subject's shape** to keep the anchor unique rather than rewriting the control — the control's
anchors are part of its contract, and every rewrite of a red-proof weakens the lineage that made it
evidence.

Concretely, for any function a control anchors on: **keep its exit points singular**. Here the cure
was to narrow the merged rows back into the existing parse loop's input shape, so the function kept
exactly one `return table`:

```bash
# the invariant, as a check you can run before landing
python3 - <<'PY'
src = open("bin/cc-limited").read()
assert src.count("    return table\n") == 1, "C2's mutant anchor is no longer unique"
PY
```

If a refactor genuinely needs a second exit, then the control must be updated deliberately and its
red-proof RE-RUN against the pre-fix subject — not adjusted until it passes.
