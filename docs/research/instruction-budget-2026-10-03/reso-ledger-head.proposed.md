<!-- markdownlint-configure-file { "MD013": false } -->
<!-- SIZE CAP: this file is ALWAYS LOADED into every reso session. Cap 6,000 chars, enforced by
     the always-loaded-rules size check. Run rows, verdicts and per-bottle history go in the
     record file named below, never here. -->

# Bottle generation: read this BEFORE firing a single paid draw

Every draw costs real money ($0.24 at 4K). Every configuration tried, its measured outcome,
the EXILED recipes and the per-bottle strategy are recorded in the **record file**
[`.claude/bottles/generation-ledger.md`](../bottles/generation-ledger.md). That file is NOT
auto-loaded. **Before any paid call to `scripts/bottle-gen-production.ts` (anything without
`--dry-run`), open that file's `## <slug>` section and its § THE METHOD.** Do not re-run an
experiment it already records.

## ▶ WHERE BOTTLE REVIEW STANDS, AND THE NEXT STEP

**Re-derive, never copy.** These lines go stale (a stale "still open" sat here for days).

- Baked heroes: `python3 -c "import json;print(sorted(json.load(open('public/bottles/manifest.json'))))" | tr , '\n' | grep -E 'remy|perrier|moet'`
- Unranked queue: `pnpm review:bottles` prints `N images without tiers` on startup.

As of 2026-09-30: **signed off and baked:** `remy-martin-vsop` (run92),
`perrier-jouet-belle-epoque` (run79), `perrier-jouet-blanc-de-blancs` (run76),
`perrier-jouet-grand-brut` (run98, tier `ok`, baked on his selection). **Open in the
current contract:** `moet-ice-imperial`, `moet-nectar-imperial`. They wait on HIS references.

🚨 **The next step for the next bottle is the OPERATOR'S: he curates and downloads the
reference images.** Ruling 2026-09-23: *"The agent doing this is insufficient."* Do not run the
`bottle-reference-sourcing` skill or workflow, do not search the web for references, and do not
fire draws on references already on disk "to get started". Wait for his files, and say so in
one line. What he supplies (dry whole-bottle primary, a label macro of the same vintage and
market, optional region shots, and which vintage the venue pours) is in the record file §
WHERE BOTTLE REVIEW STANDS.

## Operator rulings: binding on every session

1. **The metric is P(at least one production-grade result).** Report the BEST draw reached,
   never a keep-rate or a mean. A near-miss and a far-miss are the same outcome, so do not grade
   the losers against each other.
2. **Label accuracy first, background integration second.** Judge both at 1306 CSS px, never at
   master resolution.
3. **The agent never signs off.** He ranks blind in `pnpm review:bottles`, so name no draws to
   him beforehand. Bake only on his explicit selection.
4. **Declare the inputs VERBATIM before AND after every run:** the main image and each supplement
   (a relative link, its dimensions, one clause on what it shows, and whose it is: his or
   agent-sourced), the prompt IN FULL taken from `--dry-run` output, the run count and the cost.
   "Unchanged" and "same as last time" are BANNED.
5. **The prompt is a fixed budget.** Fix a region with a crop (`--ref-image2`), not a prompt
   clause. Add a `LABEL_COPY` clause only for a string that is wrong in EVERY draw.

## Money guards: check each one before firing

- **Never fire an EXILED recipe** (each bottle's section in the record file lists them).
- **Do not open with a new recipe guess.** Four engineered recipes lost to draws that already
  existed ($2.88).
- **A ledger verdict is a claim about an image that is still on disk.** Re-look at it before
  building on it.
- **Check vintage and market between the primary and the label macro first.** A mismatch goes
  back to him. It is not worked around.
- **Fire small:** several `--runs=2` invocations. Use `--no-supplement` only for a named
  control arm.

## After firing: record it, in the record file

Append the round under its `## <slug>` section in `.claude/bottles/generation-ledger.md`,
following its § How to add a row: BOTH axes, inputs verbatim, cost. Edit THIS file only when a
bake, a sign-off or an operator ruling changes the status above.
