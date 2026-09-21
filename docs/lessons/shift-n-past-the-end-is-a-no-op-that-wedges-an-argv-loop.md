# `shift N` past the end is a NO-OP, and in an argv loop that is an infinite spin

**Measured 2026-09-21, claude-infrastructure.** `bash tests/lr-drill.sh --assert` — the flag last,
its value absent — ran for **2 h 19 m at ~100 % CPU** (138 minutes of CPU time), produced zero
bytes, and was killed by hand. It should have printed a usage error in milliseconds.

```sh
while [ $# -gt 0 ]; do
  case "$1" in
    --assert) MODE=assert; RESULTS="${2:-}"; shift 2 ;;   # ← $# is 1 here
    …
  esac
done
```

`shift 2` with one argument left **fails and shifts nothing**. `$#` stays 1, `$1` stays `--assert`,
the case re-matches, and the loop runs forever. Every two-arg flag in that parser had it — `--drill`,
`--check-manifest`, `--assert`, `--account`, `--out`, and `--verdict` at `shift 3` — all six
reproduced at rc 124 under `timeout 3`.

## Why `${2:-}` did not save it, and why that is the instructive part

The line already defended the *expansion*: `RESULTS="${2:-}"` cannot be an unbound-variable error
even under `set -u`. It reads like a guard and is not one. **`${2:-}` is a statement about what `$2`
expands to; the wedge is a statement about `$#`.** They are different facts, and defending the
first makes the second look handled.

The downstream consumer was blameless and also looked like protection: `assert_results` opens with
`[ -n "$f" ] && [ -f "$f" ] || return 3`. Correct, and never reached — control never left the
parser. **A guard one layer down cannot rescue a loop that never exits.**

## Why a bound is the assertion

`timeout` returns **124** on a wedge, and nothing else does. A test that asserts only "rc is
non-zero" passes on a wedge that is killed by the harness, and a test with no bound at all hangs
the suite. The red-proof is `run timeout 5 …` plus `[ "$status" -ne 124 ]` *and* the expected
usage rc — two assertions, because the wedge and a wrong-code refusal are different failures.

## The rule

1. **Before `shift N`, assert `$# -ge N`** and refuse by name when it does not hold. A missing
   required value is a usage error, not an empty string to carry forward.
2. **A `${2:-}` default is not an argument check.** Grep for `shift 2`/`shift 3` inside a
   `while [ $# -gt 0 ]` loop; the `${:-}` on the same line is what makes it look safe.
3. **Bound every probe of an argv parser**, and treat rc 124 as the finding rather than as noise.

## What the survey showed, stated with its own limit

A tree-wide grep produced ~25 candidate files with the same shape. Probing a **read-only subset —
`desk-assert`, `cc-digest`, `cc-roles`, `cc-spawn-verify`, `cc-await-ping` — 0 of 5 reproduced**;
each refuses via some other guard. So this was an OUTLIER, not the tip of a systemic defect, and a
repo-wide sweep filed off the grep alone would have been work invented by a pattern rather than by
a measurement. **Honest limit:** 5 of ~25, and they were chosen for being safe to execute, which is
plausibly correlated with being better guarded. The rate is bounded loosely, not tightly; the
remaining candidates are unprobed because probing them could act.

**Companions:** [[a-ratchet-s-culprit-is-in-its-output-not-in-the-range]] ·
[[killed-pipeline-empty-output-is-not-a-verdict]] (0 bytes under `| tail` is the EXPECTED state of
a healthy buffered run — it is not evidence of death, and it is what made this look inert rather
than hot) · [[a-driver-shell-s-own-cpu-is-not-its-pipeline-s-progress]] (the converse held here:
the driver's CPU was ~0 and the LEAF's was 138 minutes — sample the children) ·
[[kill-the-leaf-not-the-wrapper-and-the-orphan-keeps-blocking]].
