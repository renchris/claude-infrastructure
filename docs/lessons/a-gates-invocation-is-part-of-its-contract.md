# A gate's INVOCATION is part of its contract — read its source line, never infer a reasonable one

**Measured 2026-09-21, claude-infrastructure. Three land attempts, ~3 h of gate time, one root cause.**

`scripts/ship-land.sh` runs statics as, literally:

```sh
if shellcheck "${sc_todo[@]}" >&2; then      # ship-land.sh:3258
```

**Bare.** No `-S`, no `-x`. I briefed six agents — and checked the merged tip myself — with
`shellcheck -S warning -x`, which is the invocation this repo's own docs and habits reach for. It
is not the one that gates. Two distinct failures came out of that single mismatch, and the second
is the interesting one.

## Failure 1 — a severity filter hides findings BELOW it

`-S warning` suppresses `info`. The gate does not. `SC2016` (expressions don't expand in single
quotes) is `info`, and it blocked the land twice, in `bin/cc-lr` and
`hooks/stop-failure-marker.sh`. This half is already in this fleet's memory as
[[prescribed-repro-weaker-than-the-harness]] — *a milder repro EXONERATES ⇒ match the INVOCATION* —
and I had read that file the same day.

## Failure 2 — a flag that makes the tool do MORE work can SUPPRESS a finding

This is the half the existing lesson does not cover, and it is why "I ran the stricter thing
locally" is not a defence.

`-x` tells shellcheck to FOLLOW sourced files. Following them is strictly more analysis. But
`SC1091` is *"not following: `<file>` was not specified as input (see `shellcheck -x`)"* — a
finding that exists **only when you do not follow**. Turning the deeper analysis ON deletes it.

So `tests/lr-drill.sh:574` carried `# shellcheck disable=SC1090`, passed `shellcheck -x` clean,
and failed the bare gate with `SC1091`. Two different codes for one line, selected by a flag,
pointing in opposite directions: `SC1090` fires when the path is too dynamic to resolve, `SC1091`
when it resolves and the target was not supplied. A partially-constant path like
`"$DRILL_REPO/lib/account-map.generated.sh"` sits exactly on that boundary.

**Generalised:** more-thorough ≠ a superset of findings. Any flag that changes what a tool *can
resolve* changes which diagnostics are *reachable*, in both directions. "Stricter locally" is an
assumption about a partial order that tools do not actually obey.

## The rule

1. **Grep the gate for its literal command before you run a local check, and quote it in the
   brief.** `grep -n '<tool> ' scripts/ship-land.sh` is ten seconds; a wrong guess is a whole gate
   cycle, and this repo's gate cycle is ~50 minutes.
2. **A brief that prescribes a verification command is prescribing an INVOCATION**, not a tool. Six
   agents ran mine faithfully and all six were clean against the wrong bar.
3. **When a local check and a gate disagree, suspect the invocation before the content** — and
   diff the two command lines flag by flag rather than re-reading the file.
4. A `disable=` annotation is keyed on a CODE, so it inherits this problem: an annotation tuned
   under one invocation can be inert under another. Annotate every code the line can emit
   (`disable=SC1090,SC1091`), or use `source=/dev/null`, which is invocation-independent.

**Companions:** [[prescribed-repro-weaker-than-the-harness]] (the severity half) ·
[[a-gate-refusal-is-not-a-gate-result]] · [[as-specified-as-built]] ·
[[repro-exonerates]].
