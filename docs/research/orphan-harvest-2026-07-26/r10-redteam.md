# r10-redteam  (session 9fa94148-8e35-41f7-826c-a11ae9c91850)

Harvested 2026-07-26 from disk after lead a3f68174 self-closed leaving this teammate orphaned.
Last assistant turn: 2026-07-25T23:52:08.557Z
Total records: 360

---


## turn @ 2026-07-25T23:16:43.039Z

Correction in flight. Let me wait for the definitive result.

## turn @ 2026-07-25T23:35:18.155Z

Still clean at 645/1579. Continuing to poll.

## turn @ 2026-07-25T23:52:08.557Z

Definitive — and it **inverts** one of my findings in a way that strengthens the verdict. Addendum:

---

# Addendum — measurement correction + resolution of the open uncertainty

## 1. Self-caught bad measurement (retracted)

My first full-suite run used `bats tests/ | tail -40`, so the reported `FULLSUITE_EXIT=0` was **tail's** exit code, not bats'. That is the known `bats … | tail` false-green trap, and I nearly shipped it as evidence. Retracted and re-run correctly (`bats tests/ > file 2>&1; echo EXIT=$?`).

## 2. Definitive result

```
REAL_EXIT=0 · 'not ok' count: 0 · 1588 tests · ~40 min wall (under load avg ~20, 55-66 bats procs)
```

**The full suite, run as one `bats tests/` invocation on the shared checkout, is GREEN.**

Two consequences:

- **Refuted:** my cross-suite-interference hypothesis. Per-suite green *and* all-together green — suites do not poison each other. Drop that speculative mode.
- **Confirmed and worsened:** the nightly's `bats:tests` RED is a **false positive**. It has been reported RED on six consecutive nights (2026-07-20 → -25) against a suite that passes both per-file and whole-dir.

## 3. This makes F12/F13 worse, not better — reclassify

I originally wrote F12 as *"the async net is RED and ignored."* The truth is sharper:

> **F12′ (revised, Sev H · Lik Certain — observed): the async net's dominant failure mode is chronic FALSE red, not missed pages.**

This is the worse of the two diagnoses. Nobody ignored a true signal; the signal is *wrong*, **undiagnosable** (`nightly-regression.sh:54` discards all output, so the page says only `bats:tests`), and **expensive to falsify** (~40 min). A net with those three properties does not get acted on by anyone, ever — and six nights of standing page plus 193 stale page files is exactly the predicted decay curve.

The candidate's C inherits all three properties by construction: it runs the same suite, on the same box, under *higher* load than the nightly, and pages on red. Its steady state is the nightly's steady state.

**New must-fix, promoted into the top tier:**

> **M4. C needs a false-positive budget and self-quarantine.** A green-stamp net that reds must (a) name the failing suite + test + tree SHA in the page, (b) confirm by re-running *that suite alone* before paging, and (c) **auto-quarantine itself** — if the net reds N consecutive times without a human disposition, it must stop paging and instead escalate that *the net is untrusted*, loudly, via the landing rail. Otherwise the net's failure is silent by design, which is the precise thing an "eventually-verified" invariant cannot survive.

Note the ordering implication: **fixing the nightly is not merely a nice-to-have precondition for C — it is the cheapest possible test of whether C's pattern can work at all in this environment.** One detail-carrying page, one confirmed disposition, and you know. Six days of evidence say the answer is currently "no."

## 4. Unchanged, now better-grounded

- **Full-suite wall time ≈ 40 min under real concurrent load** (vs ~35 min estimated serial). It *inflates under exactly the concurrency C exists to cover* — which tightens F14's starvation math: at the 8.6-min peak inter-land gap, a 40-min run is superseded ~5× and never completes.
- **M3 (buy throughput before selling the invariant) is now the strongest recommendation in the report.** A genuinely green 1588-test suite that takes 40 minutes is a *performance* problem, not a *correctness* problem — and `cc-reaper.bats` (531 s = 25%) plus `brew install parallel` + `bats -j 8` on 8 perf cores plausibly reduces it to ~5 min. At 5 min the entire A/B/C architecture becomes optional and the trunk-fully-green invariant survives intact.

## 5. Net effect on the verdict

No change to the A/D/E rows. **B stays "do not ship."** **C's row hardens**: it is not merely "harden first" but *"do not ship until the identical existing mechanism has been demonstrated to produce one actionable, actioned page"* — because the live evidence is that this repo's async-verification pattern currently produces false reds that no one can cheaply falsify, and layering trunk-green semantics on top of that would convert a noisy dashboard into a load-bearing lie.
