# A new top-level `def` silently shadows a same-named helper

**2026-10-12, accounts board freshness (Land B).** `bin/claude-accounts` is a ~10,000-line Python
module. A new helper `_iso_epoch(t)` (epoch → ISO string) was added near line 6,700. A helper of the
same name already existed at line 1,268 with the OPPOSITE contract (`_iso_epoch(s)`: ISO string →
epoch), used by the transcript walk in `working_concurrency`. Python binds the later `def` at import,
so every caller of the old helper silently got the new one.

Nothing failed at import, at `ast.parse`, or in the new feature's own 19 tests. The symptom surfaced
only in an unrelated suite: `working_concurrency` caught `TypeError: 'str' object cannot be
interpreted as an integer`, logged "walk aborted", and returned None, so 7 of 14
`claude-accounts-kwork-live-bound.bats` cases failed with `'NoneType' object is not subscriptable`.
In production the same bug would have made `k_work` permanently unmeasured with only a log line.

## The rule

Before landing a change that adds module-level names to a large single-file module, check for
duplicate top-level definitions:

```
python3 - <<'PY'
import ast, collections
t = ast.parse(open("bin/claude-accounts").read())
c = collections.Counter(n.name for n in t.body if isinstance(n, (ast.FunctionDef, ast.ClassDef)))
for n in t.body:
    if isinstance(n, ast.Assign):
        c.update(x.id for x in n.targets if isinstance(x, ast.Name))
print([k for k, v in c.items() if v > 1])
PY
```

An empty list is the pass. A helper name that reads as generic (`_iso_epoch`, `_touch`, `_read_json`)
is exactly the one most likely to exist already; grep the name before choosing it.

## Why the feature's own tests could not catch it

The new tests exercised the new helper, which worked. The shadowing broke the OLD callers, and only
a suite that exercised those callers could see it. Run the existing suites of every function in the
module the change touches, not just the new feature's suite.
