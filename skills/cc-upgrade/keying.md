# keying.md — rewrite every hardcoded id site in the SAME diff as the flip (phase P7)

A half-fix is worse than none. Grep the fleet for the OLD id before flipping. Sites split into two
classes that fail in opposite directions, and **a check that finds only one class produces a flip
that looks complete and is not**:

- **DETECTORS** test `$MODEL` against the literal (`[ "$MODEL" = "claude-fable-5" ]`). After a flip
  they evaluate FALSE — no error, no log — so the new model runs while nothing accounts it as that
  tier. Under-counting, silent.
- **EMITTERS** *write* the literal (`fable) MODEL="claude-fable-5" ;;`, `--model claude-fable-5`,
  `model=claude-fable-5`). They are keyed on an alias or a flag, so they never "go false" — they
  keep launching the OLD model while the SSOT claims the new one. The config reads adopted and the
  fleet is not.

```bash
# detectors                                   # emitters
grep -rnE '=[[:space:]]*"?<old-id>"?' bin scripts hooks lib    grep -rnE '(model=|--model )<old-id>' bin scripts hooks lib
```

Two more traps (historical: both measured on the Fable 5 → 5.1 census):

1. **Selftest assertions pinned to the old id go VACUOUSLY GREEN** (`bin/cc-route`,
   `bin/cc-wave-plan` both asserted the old frontier id). A green suite is not evidence that the
   keying survived; it may be asserting the very thing you failed to change.
2. **Glob matchers survive the flip while equality matchers do not.** `~/.zshrc`'s cost warning
   uses `== *claude-fable-5*`, which still matches `claude-fable-5-1`. Fix only the detectors and
   you get the worst split available: the human is still warned about the tier's cost while every
   mechanical arm that counts it reads "not that tier".

**Prefer the glob's shape** — a prefix or `case` test covering both ids — over swapping one
literal for another, so the *next* bump in that family does not re-create the problem. Where a
consumer may run under an older binary than the one that knows the new id (model.md Case A 0b),
prefer the family alias over the full id.

## Pins — one resolver, and a ratchet instead of a census

Every consumer that needs "the claude binary" reads `bin/cc-claude-bin`, which parses the
launcher's own `_bin=` line — so the only pin to move is `~/.zshrc` `claude()`'s `_bin`, and the
activation script moves it. A `${VAR:-$HOME/.claude-<NNN>/…}` default is the dangerous class: it
never fails, it keeps running the previous build, which stays on disk precisely because we keep it
for rollback. **Do not restate a pin census here** (the last one rotted within weeks): the RATCHET
case in `tests/cc-claude-bin.bats` fails the land on any new versioned pin under `bin scripts hooks
lib`. Run it; a red there is a pin to route through the resolver, not a test to relax.
