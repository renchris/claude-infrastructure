# utilize.md — which model, at which effort, for which use case (phase P5a)

The question a new model raises after it is registered: where does it beat what we route today,
at which rung, and at what quota. The output is a role × effort table written into the SSOT, and it
ends in the Case D emitter census (model.md) — a `roles.*` move is invisible to both sweep tools.
P5a only reads and measures; in the both lane it runs in one Workflow with P5b.

Worked example of the whole method: `docs/research/opus55-utilization-2026-09-22/README.md` and
its three companions (`…-effort-sweep-…`, `…-synth-reprobe-…`, `…-feature-adoption-…`). Copy
their method, never their numbers.

## 1. Facts: the claude-api skill first, then the release pack — fetched by you

Invoke the `claude-api` skill for ids, pricing and capability facts. Then fetch the release
materials YOURSELF; there is no human step (operator ruling). The set is the announcement, the
System Card PDF it links, "Prompting Claude <Model>", and the pages that guide links: effort, what's
new, migration guide, models overview.

```bash
curl -sSL -A "Mozilla/5.0" -o card.pdf "<system-card-url>"   # born-digital: PDF page N == printed N
pdftotext -layout card.pdf card.txt                          # exact text layer
pdfimages -png -p card.pdf figs/fig                          # every chart at NATIVE resolution
pandoc -f html -t plain --wrap=none page.html -o page.txt    # each vendor page
```

The per-effort evidence lives in CHARTS with no data labels, so read the native figures with
vision.

**Do not OCR a born-digital card.** Measured on one card (historical, `…/mistral-ocr-eval.md` in
the utilization run): OCR text matched `pdftotext` except for numbers returned LaTeX-wrapped
(`\(33\%\)` defeats a grep for `33%`), its chart crops were a fraction of native resolution, and it
moved a table's group header onto the wrong model column. OCR is for SCANNED pages only; detect
them per page (`pdffonts` shows no fonts, or `pdftotext` yields under ~50 characters over a
page-spanning image) and read those with Claude vision. The Mistral OCR API (`mistral-ocr-latest`,
key in the keychain as `MISTRAL_API_KEY`) is the purpose-built alternative; its workspace rate
limit has read 0/min before, which is a plan setting to re-check, not a property of the product.

## 2. Page-cited fact base (reader + verifier fan-out)

- `workflow-lean` page-range readers: each brief names its page range, its text and figure files,
  and its output file, and extracts page-cited facts.
- A second reader per range re-checks every fact at its cited page; a fact is unconfirmed until
  then. Verifiers also add what readers missed.
- A completeness critic names gaps; each gets a targeted re-read.
- Output: `facts.json` in the run dir, plus a list of what the sources do NOT state (quota draw per
  token, the CLI's own default effort, long-context curves, …) — each of those is a measurement to
  run, never an assumption.

## 3. Our own measurements (where the vendor charts do not decide)

- **Effort sweep** on a frozen corpus with anchored ground truth (e.g. the review corpus in
  `tests/fixtures/codex-probe/`): every rung low..max plus in-panel anchors from earlier sweeps, a
  blind 3-judge panel, strict-majority headline, and paired sign tests. Isolation recipe:
  `--tools ""`, `--setting-sources ""`, a neutral `mktemp` cwd, `--no-session-persistence`. A
  positive control (median output tokens rise with effort) proves `--effort` reached the model.
  Raise the output cap to the model's max for xhigh/max arms, or they lose cells to it.
- **Quota draw per token**, the currency that binds: read one account's plan meters around a
  single-model interval against an in-situ control of a model whose draw is known. Integer meters
  bound the ratio; state the bound, not a point.
- **Equal-tools re-probe** before replacing an incumbent: every arm gets exactly the same tool set
  (read the tool list the harness really gives that surface — a Workflow agent may lack tools a
  lead has) and the same briefs, judges and permutations. An unequal-tools run is INCONCLUSIVE by
  construction; say so rather than reading a winner off it.

Cells must be absolute-pathed and zsh-safe (write `"cp-${b}:high"`, since `$b:h` is a zsh
modifier). Record spend per arm in labelled currencies ([tokens], [$list], [W-pp], [5h-pp]).

## 4. The role × effort table → SSOT

One row per use case this fleet runs (lead, scoped coding, review, verifier, judge, research
worker, synthesis worker, retrieval, …): model · rung · slack rung · evidence with its page or run
· conviction · what would move it. Below 90% conviction the row names the research still owed (F2).

- Write it to `effort_defaults.<family>_*` and the matching `roles.*` keys. Rungs are advisory
  until code reads them — note which surfaces apply one by hand (`--effort` on a fire, `/effort`
  on a lead, `effort:` in agent frontmatter or a Workflow `agent()`), and re-read how each surface
  resolves effort on the binary in service rather than trusting an older run.
- A typed `/effort` in an interactive pane can persist to that account's settings; never automate it.
- Then run the Case D emitter census (model.md), move ONE role at a time, and spot-check a live
  spawn of each moved role.
