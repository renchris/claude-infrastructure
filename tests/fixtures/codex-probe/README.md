# codex-probe — the frozen brief corpus

W1 of `docs/plans/CODEX_ADVERSARIAL_SLOT_PROBE.md`. Nine review briefs drawn from this repo's own
landed fixes, each with the correct answer written down in advance.

**What it measures.** Not quality — **complementarity**. Over briefs with KNOWN defects, which
defects does each arm find, and what is the **non-overlap**? A candidate can lose head-to-head and
still be worth routing (its misses are uncorrelated); a candidate can tie and be worth nothing
(redundancy buys nothing in a verification slot). That is why every brief carries a ground-truth
list a judge can score against, and why a brief whose correct answer cannot be stated in advance
was dropped rather than included.

## Layout

| Path | What |
|---|---|
| `manifest.json` | one record per brief — ground truth, provenance, controls. **Never shown to an arm.** |
| `briefs/<id>.md` | the brief text handed to a model, identical wording for every arm |
| `build-briefs.sh` | regenerates `briefs/` from the manifest by extracting each artifact from git |
| `verify-corpus.sh` | asserts the three controls mechanically — run this before W2 |

Ids are opaque (`cp-01` … `cp-09`) because the id appears in the brief. The descriptive `title`
lives in the manifest only.

## The three controls

The corpus is worth nothing without these. Each has bitten this repo before, and a corpus that
fails one passes vacuously — returning a confident wrong verdict, which is more expensive than no
verdict.

1. **SIBLING-INERT.** A defect another mechanism already catches is vacuous: the model "finds" it
   because the tree screams. Every brief is a **self-contained text artifact** — no repo, no test
   suite, no lint, no docs, no git history, no execution — so every sibling axis is inert by
   construction. `sibling_axis_pinned` names the specific sibling that would otherwise leak and how
   far it leaks. Two are worth knowing: `cp-04`'s defect is stated almost verbatim in
   `docs/research/terminal-for-30-panes-2026-07-31.md`, and `cp-02`'s assertion is visibly red the
   moment the suite is RUN. Both are reachable only outside the brief.
   *(memory: sibling-guard-makes-the-fixture-vacuous)*
2. **REAL ARTIFACT, NEVER A RECONSTRUCTION.** Each brief body is the file **extracted byte-for-byte
   from the pre-fix tree** at `pre_fix_ref`. A hand-edited "buggy-looking" stand-in passes vacuously
   because reconstruction drops exactly the incidental detail that let the defect survive a first
   look. `verify-corpus.sh` check B re-extracts from git and diffs — so this control is checked, not
   asserted. *(memory: control-must-replay-the-real-artifact)*
3. **TWO CLEAN BRIEFS** (`has_defect: false`). Without them the panel cannot separate a good finder
   from a model that always reports something, and false-positive rate is half the verdict in a
   verification slot.

   🚨 **This was the hard control, and picking the clean briefs cost more than picking the defective
   ones.** The obvious basis — a file with **zero subsequent commits**, i.e. one nothing ever came
   back to fix — turns out to be worth almost nothing here. Thirteen candidates were put through an
   independent adversarial pass over the same defect classes the corpus scores. **Nine were
   convicted** (as of 2026-08-10 — the figure moved twice while late screens landed; read it with its
   denominator, never as a census), several on scored classes, one on a defect already sitting in this repo's own
   red-team notes as an open MED-HIGH finding, and one on an argument-parsing bug that spins forever
   at 100% CPU on a documented flag. A file nobody has fixed is not a file with nothing wrong; it is
   a file nobody has looked at hard.

   So the surviving basis is **screened and not convicted**, recorded per record in `screen` — and
   the screen that clears a candidate must have *executed* things, not reasoned about them. The
   other two survivors, `tests/origin-identity.bats` and `hooks/lib/origin-identity.sh`, arrived after
   the corpus was fixed and are held as **vetted alternates** should either clean seat be challenged. Two
   further candidates were rejected for **disclosure** rather than defects: both were post-fix twins
   of `cp-01`, and one narrated `cp-01`'s defect outright in its own comments ("the corpus CONVICTS
   the shipped pre-fix hook") while the other shared its subject matter, so a corpus run in one
   context would have primed that brief. Check D in `verify-corpus.sh` caught those and now fails
   any brief naming another brief's subject without a per-pair adjudication. **A realistic clean
   brief is not the same as a safe one, and an unfixed file is not the same as a sound one.**

## Run-time requirements for W2

- **No repo access, no tools, no network for an arm.** The brief is the whole input. An arm that can
  `git log` the subject can find the fix commit, and every control above collapses. The brief says
  so in its own text; the harness must also enforce it.
- **One brief per fresh context.** Nine briefs in one session is one arm reading nine files, and a
  finding on brief N is then not independent of briefs 1..N-1. Check D removes the cross-brief
  disclosures it can see mechanically; a fresh context is what removes the rest.
- **Ship the brief file unmodified.** Identical wording across arms is the comparison's basis.
- **Never show `manifest.json`, the titles, or this README to an arm or to a judge before scoring.**

## Honest caveats

- **Corpus bias, stated rather than quietly benefited from.** These are defects a Claude-family
  model already missed once. That tilts the field toward the candidate. It is also the honest
  population — these are exactly the defects the slot exists to catch — but the W3 verdict must
  state the tilt.
- **"Clean" means screened and not convicted, not proven defect-free.** No file in a live repo can
  be proven clean, and the 8-of-10 conviction rate above is the measurement that says so. The basis
  is recorded per record in `clean_basis` and `screen`. A model that finds a genuine unknown defect
  in a clean brief should be **credited** by the judge, not scored as a false positive — W3 must
  adjudicate the finding against the code rather than assume the label. Given the base rate, expect
  this to happen at least once.
- **Ground truth is a floor, not a ceiling.** The lists are the defects that were found and fixed in
  reality. A finding outside the list is not automatically a false positive; it is a finding the
  judge must adjudicate against the code.
