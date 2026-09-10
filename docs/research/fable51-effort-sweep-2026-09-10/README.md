# Fable 5.1 effort re-sweep — 2026-09-10

**Item:** cc-backlog `d98bf0055818` — *"the fable51_* keys are Fable 5's numbers, never probed against
5.1"* (model-upgrade runbook step 5, left open by the 2026-09-03 Fable 5.1 adoption, `9d97439a`).
**Governs:** `model-config.yaml` `effort_defaults.fable51_*`, and the Fable rows of the
`commands/handoff.md` routing table that name those keys.

## Why a sweep was owed

Anthropic, *Prompting Claude Fable 5.1*: *"Re-run the sweep even if you already ran one on Claude
Fable 5: effort level names don't correspond to the same amount of thinking across models."* The four
`fable51_*` keys (`default: high`, `capability_sensitive: xhigh`, `routine: medium`, `cheap: low`)
were written on adoption day as labelled starting points and never measured.

## Method

**Corpus — reused, not built.** The frozen `tests/fixtures/codex-probe/` corpus: nine review briefs,
each a real pre-fix file extracted byte-for-byte from git, **31 anchored ground-truth defects** across
seven defective briefs, plus two screened-clean briefs (`cp-03`, `cp-07`). Its controls are asserted
by `verify-corpus.sh` and gated by `tests/codex-probe-corpus.bats`. It was built for the T4 adversarial
slot probe and suits this one for the same reason: the defects survived a first look, so it
discriminates on exactly the open-ended grounding axis where T1/T2 found effort to be load-bearing.

**Arms.** `claude-fable-5-1` at `low · medium · high · xhigh · max`, one fresh context per
(brief, effort) cell — 45 cells — produced by `run-arms.sh`. Two reference arms come free from W2
(2026-08-11), already verbatim on trunk: `claude-fable-5 @xhigh` (arm A) and `claude-opus-5 @max`
(arm D).

**Isolation** is the W2 recipe measured in `docs/research/codex-probe-screen-2026-08-10/
W2-preflight-findings.md` §3: `--tools ""` (per-cell control: `num_turns=1`), `--setting-sources ""`
plus a neutral `mktemp` cwd, so no `CLAUDE.md` / `MEMORY.md` / hooks load. That matters here: this
repo's `MEMORY.md` states `cp-01`'s ground truth in one line.

**Binary.** 2.1.260 (`~/.claude-260`, the live track). The pinned stable 2.1.114 refuses the model
outright — `400 claude_code_version_too_old … version 2.1.251 or newer is required` — so any future
re-run must not go through `claude-latest`.

**Cost is MEASURED, not directional.** Every prior probe in `model-routing-freewin-probe.md` could
only reason about cost from first principles (`.meta.json` carries no usage; Codex reports none).
`claude -p --output-format json` returns `usage.output_tokens` and `total_cost_usd` per call, so each
cell records its own. `output_tokens` includes thinking, which makes it the positive control that the
`--effort` flag reached the model at all: a flat token curve across efforts would void the sweep.

**Scoring** — `judge.py`: three `claude-opus-5 @xhigh` judges (`effort_defaults.verify_judge`) per
defective brief, each seeing the brief, the ground-truth list and all seven outputs under labels
re-shuffled per (brief, judge). A ground-truth item is credited only for its MECHANISM, never its
topic (the W3 rule). A single-vendor panel is acceptable on this axis only: W3 measured anchored
scoring as judge-vendor-independent (98% cross-vendor vs 99% within). Headline = strict majority
(≥2 of 3), reported beside every other threshold.

**Decision rule** — the operator's lexicographic objective (`model-routing-freewin-probe.md`
§ Purpose): quality first, cost breaks ties. A lower effort is adopted for a key only when it ties the
higher one on recall; any reliable recall loss rejects it.

## Results

*(filled from `runs/index.jsonl` and `scores.jsonl` — see below)*
