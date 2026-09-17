# pipefail-sigpipe-lint is blind to a pipeline split across a line continuation

**2026-09-17.** Backlog row `c128aeff816e`, condition `pipefail-lint-continuation-join`.
Sites fixed: `22e133a0e`. Detector gap: still open.

`scripts/pipefail-sigpipe-lint.sh:532` names this residual itself — *"It does not join
CONTINUATION lines (pipe258.py is a working joiner nobody has wired in)"* — and `:542`
instructs: *"The continuation join is a different gap and it has NO row … File it under its
own condition before citing an id for it."* This is that row's evidence.

## The measurement

One variable per fixture, against the **shipped** detector (`CC_PIPEFAIL_ROOT` fixture tree,
`--census`, `CC_PIPEFAIL_MEMO=off`):

| fixture | shape | detector |
|---|---|---|
| `c_and_oneline` | `printf … \| grep -Eq P && act` — one physical line | **REPORTED** |
| `b_andchain` | same, split by `\` | not reported |
| `a_if` | `if printf … \| grep -Eq P; then` — one physical line | **REPORTED** |
| `d_if_contin` | same, split by `\` | not reported |

So `&&` is **not** the blind axis. The continuation is.

## The residual is no longer hypothetical

The lint's own paragraph says *"Neither shows up in today's numbers."* That was false when
measured. Three live fail-open guard sites were hiding behind exactly this gap in
`bin/cc-cannot` — `:136` (`open tel:/sms:`), `:140` (interactive credential flows), `:208`
(the editor refutation). Each gates an `&&` that fires a **verdict**, so under `set -o
pipefail` a match SIGPIPEs the producer, the pipeline reports the producer's death, and the
guard stays silent exactly when it should speak. That is `0ea2ab91c`'s own polarity argument
reaching three sites its ratchet could not point at.

`0ea2ab91c` drained the five sites the ratchet **did** flag. `22e133a0e` drained these three
and pinned them structurally (not an allowlist row — the allowlist is shrink-only and the
ratchet cannot see these lines to count them). Red-proof: swapping in `origin/main`'s
`bin/cc-cannot` makes the pin fail naming exactly 136, 140, 208.

## Blast radius — a BOUND, not the detector's count

⚠️ Measured with **my own approximating scanner**, not the detector: join backslash-continued
lines, match `| grep -*q` or `| head -N`, restrict to files whose head mentions `pipefail`.
Quote it as a bound.

- **27** continuation-split early-exit pipelines tree-wide
- **9** with rc **consumed**, so a verdict can invert:
  `hooks/lead-crash-watchdog.sh:475` · `hooks/stop-failure-marker.sh:85` ·
  `scripts/completion-push.sh:174` · `scripts/gate-classify.sh:123` ·
  `scripts/plan-phase-scan.sh:112` · `scripts/settings-hook-timeouts.sh:176`, `:194`, `:196` ·
  `scripts/smoke-test.sh:172`
- **18** where the rc dies in a command substitution and **must stay exempt**

🚨 **Do not quote 92.** An earlier, deliberately over-generating pass returned 92; the
commit body of `22e133a0e` cites that figure and is superseded here. The 27/9 split is after
requiring rc-consumption. Drained-or-not is about whether an rc is **read**, never about the
shape — `cc-cannot:174` (`head -80 … | grep -Eom1`) is the canonical case the lint is
**right** not to flag, because its rc dies in a substitution.

## Why this is its own wave

Wire `~/.claude/autonomy/pipe258.py` into the scan, re-measure, drain the rc-consuming set,
keep the discarded-rc set exempt, re-pin. The allowlist is **shrink-only by contract**, so
nothing the joiner reveals can be absorbed: every rc-consuming site must be drained before
the detector can ship, which blocks every land until done. That is a land-gate widening for
the whole fleet, not a follow-on to a one-row fix.

## Re-derive

```
cd ~/Development/claude-infrastructure
sed -n '525,560p' scripts/pipefail-sigpipe-lint.sh      # the residual, in the lint's own words
```
Then rebuild the four fixtures above under a `CC_PIPEFAIL_ROOT` tree and run
`bash scripts/pipefail-sigpipe-lint.sh --census`. Re-measure; never re-quote.
