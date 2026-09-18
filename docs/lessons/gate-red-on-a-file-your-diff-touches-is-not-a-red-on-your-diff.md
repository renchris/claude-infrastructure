# A gate's red on a file your diff touches is not a red on your diff — check the line numbers against your hunks first

**2026-09-17**, closing DoD #8 (Q23, the docs build) of `docs/plans/KITTY_DRAG_ACTION.md`.

## What happened

The kitty docs gate is `make FAIL_WARN=1 -C docs html` — sphinx with `-n` (nitpicky) and `-W`
(warnings are errors). Run against the tree carrying the W5 `mouse_drag_window` patch, it failed:

```
/Users/chrisren/kdev/docs/changelog.rst:4856: ERROR: git commit id "8dea5b3" not recognized.
/Users/chrisren/kdev/docs/changelog.rst:4971: ERROR: git commit id "ad1109b" not recognized.
/Users/chrisren/kdev/docs/changelog.rst:4983: ERROR: git commit id "889ca77" not recognized.
rc=1
```

`docs/changelog.rst` **is one of the seven files the patch modifies.** The obvious reading — the
patch broke the docs build, deliverable B fails its own gate — is wrong, and it is the reading a
session arrives at by looking at the file name and stopping.

The patch adds exactly four lines to that file, at **line 205**. The three failures are at lines
**4856, 4971 and 4983** — roughly 4,650 lines away, in changelog entries for releases from years
earlier. The cause was the clone: `~/kdev` was **shallow**, so those three old commit ids were not
in its object store and kitty's `:commit:` role could not resolve them. `git fetch --unshallow`
made all three resolve and the same build passed `rc=0`.

## The rule

**Before a whole-tree gate's red convicts your diff, diff the red against your hunks.** A gate that
walks the entire tree reports by FILE and LINE; a file appearing in both your diff and the gate's
output is a coincidence of scope, not evidence of causation. Ask, in this order:

1. Are the failing LINE NUMBERS inside any hunk of mine? If no, it is not my diff.
2. Can this environment even run the gate correctly — full history, right interpreter, deps present?
3. Only then: is the content I added wrong?

This is the [reachability](a-ratchet-s-culprit-is-in-its-output-not-in-the-range.md) failure one
level down: that rule says a whole-tree suite attributes nothing by reachability, so read the
failing assertion's printed path. This one says the printed path is not enough either — read the
printed LINE, because the same file can hold both your change and someone else's pre-existing red.

## The companion trap, same session, same gate

The first attempt at the gate did not fail, it **segfaulted** (`rc=139`, `make: *** Segmentation
fault: 11`). `sphinx-build` on `PATH` is Homebrew's, shebanged to Homebrew's `python3.14`;
`kitty/fast_data_types.so` in that tree is linked against a **vendored** Python framework of the
same version at `~/kdev/dependencies/darwin-arm64/python/Python.framework/Versions/3.14/Python`.
Two different libpython 3.14 binaries in one process crash at `PyInit_fast_data_types`.

Nothing in the version numbers shows this — both are 3.14. It is visible only in the **C stack**,
which `python3 -X faulthandler` prints and which names both framework paths on adjacent lines. The
control that settled it in one command: the *unpatched-by-this-wave* sibling tree
(`/private/tmp/kitty-482`) imported the same module cleanly under the same Homebrew interpreter,
so the difference was the tree's linkage, not the patch.

⇒ **A compiled extension names its own interpreter.** Matching the version is not matching the ABI
when a project vendors its own Python. When a module segfaults at import, get the C stack before
suspecting the source — and reach for a sibling tree as the control rather than rebuilding.
