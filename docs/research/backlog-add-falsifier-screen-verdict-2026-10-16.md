# Verdict — cc-backlog 0d23b9078952 is already cured on trunk (2026-10-16)

**Verdict: CURED by `e8dc8c5b` — close 0d23b9078952 as done, citing that sha. No new code.**

`e8dc8c5b fix(cc-backlog): screen add --falsifier for exit 0 at filing; point not-yet-true at a dated park`
(trailer `Backlog: 0d23b9078952`, landed from cloud branch `claude/fire-20261016T093038Z-53566-1`).
This fire is a re-dispatch of a row whose cure landed earlier the same day.

## What I ran (cloud VM, checkout unshallowed, `HEAD..origin/main` = 0)

- `git merge-base --is-ancestor e8dc8c5b origin/main` → rc 0. The cure is on trunk.
- Dispatcher vintage: `git rev-parse origin/main:bin/cc-dispatch` = `03e82d02b1fc…`, which equals the
  blob in the brief. The dispatcher that fired me IS trunk. So this re-fire is not explained by a stale
  dispatcher. Most likely the desk had not yet closed the row from the landed content when it re-fired.
- **Generator (2), the unscreened `add --falsifier`.** Ran against a scratch ledger
  (`CC_BACKLOG_FILE`, `HOME` both in the scratchpad):
  - `cc-backlog add --falsifier 'npm view bun dist-tags.latest reports >=1.4.4 and that release has a lint command'`
    → **rc 5, REFUSED**. The refusal names case (a) "prose runs under /bin/sh too (`>=1.4.4` is a
    redirect)" and case (c) "a not-yet-true row … park it `On or after YYYY-MM-DD: …` instead".
  - `cc-backlog add --falsifier 'false'` → rc 0, stored. A probe that is live at filing is still accepted.
- **Generator (1), the help text.** `bin/cc-backlog:147-154` lists the `--why-not-now` classes and no
  longer pairs `not-yet-true` with `--falsifier`. `grep -rn "pair --falsifier"` over bin/ scripts/
  docs/ skills/ commands/ finds nothing. The add usage at `bin/cc-backlog:18-20` reads "Never on a
  not-yet-true row: park that one dated instead."
- Suites, with the `1..N` plan line checked against the ok count:
  - `tests/cc-backlog-falsify.bats`: 1..31, 31 ok
  - `tests/cc-backlog-add-update.bats`: 1..33, 33 ok
  - `tests/cc-premise-falsifier.bats`: 1..12, 12 ok

## Residual, not fixed here (scope is frozen to this item)

The screen protects the store. It does not protect the filesystem. To screen a probe, `add` has to
**execute** it in the caller's cwd, so a prose probe still writes its redirect target before being
refused: the run above left a file named `=1.4.4` in the scratch cwd. On the desk, that means a
stray file in whatever checkout the filer stood in. It does no harm to the ledger, and the refusal
text already tells the filer it was prose. If this is worth fixing, run the screen in a throwaway
temp cwd. That would be a separate row.
