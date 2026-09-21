# TAB is IFS *whitespace*, so `IFS=$'\t' read` silently deletes empty cells

**Found:** 2026-09-20, LIMIT_DETECT_100P W3, wiring `lr-fleet.sh` onto `bin/cc-limited`.

## The rule

`IFS=$'\t' read -r a b c …` does **not** give you a TSV reader. Tab is an IFS *whitespace*
character, and bash applies the whitespace rules to it: **runs of tabs collapse into one
separator, and leading/trailing empties are stripped.** A row whose cells are all non-empty
reads correctly, so the bug is invisible until the first row with a hole in it — and then every
column to the right of the hole shifts LEFT, silently, at exit 0.

`awk -F'\t'` does not do this. It is the only reader in an ordinary shell toolkit that sees an
empty field as a field.

## What it looked like

Two producers of the same 11-field row. `lf_locate` writes `-` for an absent pane, pid or cwd;
`cc-limited --tsv` writes an empty cell. The consumer read both with the same
`IFS=$'\t' read -r sid cfg acct pane pid cwd tier disp kind kinds age`.

A NO-PANE row — empty pane AND empty pid — arrived two cells short:

```
slow scan:  52e35019 next2 -     -  claude-opus-5/high NO-PANE network  /…/wt
census:     52e35019 next2 /…/wt -  network            network 1201     NO-PANE
                           ^^^^^ the CWD, rendered in the PANE column
```

The disposition fell off the end of the line. Nothing errored; the census simply described a
different world than it had computed, and the driver acted on it.

## The cure

Normalise before any `read` sees the row, in `awk`, which can:

```bash
while IFS=$'\t' read -r f1 f2 … f11; do
  …
done < <(awk -F'\t' -v OFS='\t' 'NF { for (i = 1; i <= 11; i++) if ($i == "") $i = "-"; print }')
```

For a producer you control, emit a placeholder for empty and translate it back at the reader —
what the poller's census pass does (`(x or "-")` in the emitter, `-`→`""` in the loop).

## Why it generalises

This is a property of the **shell**, not of this repo's data: any `IFS=$'\t' read` over a TSV
whose cells can be empty has it. The same is true of `IFS=' '` and `IFS=$'\n'` — all three are
IFS whitespace. Only a non-whitespace IFS (`IFS=:`, `IFS=,`) gives one-separator-one-field
semantics, which is why `IFS=: read` over `/etc/passwd` behaves the way people expect
`IFS=$'\t'` to.

The codebase already carried HALF of this knowledge, in a comment at `lr-fleet.sh`'s `--json`
site: *"TAB is IFS whitespace, so a reader naming N variables over N+1 fields folds the
remainder into the LAST one."* That is the too-few-variables direction. This is the other
direction — too-few-**fields** — and it is the one that moves data into the wrong column rather
than merely concatenating the tail.

## Companion

The defect is invisible to a fixture whose rows have no empty cells, which is the usual shape of
a hand-written fixture. Reach it by fixturing the state that produces the hole — here, a session
with no live pane — rather than by writing a row with an empty cell in it on purpose.
